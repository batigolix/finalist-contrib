#!/usr/bin/env bash
# AI generated
# build-projects.sh — reads projects-source.csv (machine_name,status,type),
# enriches each project via the drupal.org api-d7 and the /project/<nid>/
# maintainers.json endpoint, and writes projects.js.
#
# Cross-references maintainers against finalist-maintainers.txt to fill the
# finalist_maintainers array per project. Taxonomy term labels are cached in
# term-labels.json (they rarely change).

set -euo pipefail

# ─── Defaults ────────────────────────────────────────────────────────────
SOURCE_FILE="projects-source.csv"
FINALIST_FILE="finalist-maintainers.txt"
OUTPUT_FILE="projects.js"
TERM_CACHE_FILE="term-labels.json"
PARALLEL=5
API_BASE="https://www.drupal.org/api-d7"
MAINTAINERS_BASE="https://www.drupal.org/project"
UPDATES_BASE="https://updates.drupal.org/release-history"

# ─── Prereqs ─────────────────────────────────────────────────────────────
command -v curl >/dev/null || { echo "curl required" >&2; exit 2; }
command -v jq   >/dev/null || { echo "jq required"   >&2; exit 2; }
[ -f "$SOURCE_FILE" ] || { echo "$SOURCE_FILE not found" >&2; exit 2; }
[ -f "$TERM_CACHE_FILE" ] || echo '{}' > "$TERM_CACHE_FILE"

TMPDIR=$(mktemp -d -t build-projects.XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

# ─── HTTP helper: fetch JSON with retries, fall back to $3 on failure ───
fetch_json() {
  local url="$1"
  local out="$2"
  local fallback="${3:-null}"
  local tries=0
  while [ $tries -lt 3 ]; do
    if curl -sS --compressed --fail -H "Accept: application/json" -o "$out" "$url"; then
      return 0
    fi
    tries=$((tries + 1))
    sleep 1
  done
  echo "$fallback" > "$out"
  return 1
}
export -f fetch_json

# ─── Workers exposed to xargs subshells ─────────────────────────────────
fetch_project() {
  local slug="$1"
  fetch_json "${API_BASE}/node.json?field_project_machine_name=${slug}" \
             "$TMPDIR/proj-$slug.json" \
             '{"list":[]}' \
    || echo "  ✗ project fetch failed: $slug" >&2
}
export -f fetch_project

# Fetch release + maintainers for one nid in a single worker so the two
# per-nid calls can overlap across the xargs pool.
fetch_by_nid() {
  local nid="$1"
  fetch_json "${API_BASE}/node.json?type=project_release&field_release_project=${nid}&sort=created&direction=DESC&limit=1" \
             "$TMPDIR/rel-$nid.json" \
             '{"list":[]}' || true
  fetch_json "${MAINTAINERS_BASE}/${nid}/maintainers.json" \
             "$TMPDIR/maint-$nid.json" \
             '{}' || true
}
export -f fetch_by_nid

# Release-history XML per slug — different host (updates.drupal.org) so a
# separate worker. Body is XML, not JSON; empty file on failure.
fetch_release_history() {
  local slug="$1"
  local out="$TMPDIR/rh-$slug.xml"
  local tries=0
  while [ $tries -lt 3 ]; do
    if curl -sS --compressed --fail -o "$out" "${UPDATES_BASE}/${slug}/current"; then
      return 0
    fi
    tries=$((tries + 1))
    sleep 1
  done
  : > "$out"
  return 1
}
export -f fetch_release_history
export TMPDIR API_BASE MAINTAINERS_BASE UPDATES_BASE

# Extract supported Drupal cores as a JSON array of majors (e.g. [10,11]).
# For each supported branch (per <supported_branches>) takes the NEWEST
# release's <core_compatibility> and unions the majors — handles constraint
# strings like "^10.2 || ^11", "~11.1", "8.x", ">=8", "&gt;=8".
parse_supported_cores() {
  local xml="$1"
  [ -s "$xml" ] || { echo '[]'; return; }
  grep -q '<error>' "$xml" && { echo '[]'; return; }
  local branches
  branches=$(sed -n 's|.*<supported_branches>\([^<]*\)</supported_branches>.*|\1|p' "$xml")
  [ -z "$branches" ] && { echo '[]'; return; }
  sed 's|<release>|\n<release>|g' "$xml" | awk -v branches="$branches" '
    /<release>/ {
      v = ""; cc = ""
      if (match($0, /<version>[^<]*<\/version>/)) v = substr($0, RSTART+9, RLENGTH-19)
      if (match($0, /<core_compatibility>[^<]*<\/core_compatibility>/)) cc = substr($0, RSTART+20, RLENGTH-41)
      if (v == "" || cc == "") next
      n = split(branches, prefixes, ",")
      for (i = 1; i <= n; i++) {
        p = prefixes[i]
        if (p == "") continue
        if (index(v, p) == 1) {
          if (!(p in seen)) { seen[p] = 1; print cc }
          break
        }
      }
    }
  ' | tr '|' '\n' \
    | awk '{ if (match($0, /[0-9]+/)) print substr($0, RSTART, RLENGTH) }' \
    | sort -un \
    | jq -R -s -c 'split("\n") | map(select(length>0) | tonumber)'
}

# ─── Phase 1: fetch project nodes ────────────────────────────────────────
# CSV: skip header, first column is the machine_name.
COUNT=$(tail -n +2 "$SOURCE_FILE" | grep -c .)
echo "Fetching $COUNT project nodes (parallel=$PARALLEL, gzip on)..." >&2
tail -n +2 "$SOURCE_FILE" | cut -d, -f1 \
  | xargs -n 1 -P "$PARALLEL" bash -c 'fetch_project "$1"' _

# ─── Phase 2: fetch release + maintainers per nid ───────────────────────
echo "Fetching releases + maintainers..." >&2
jq -r '.list[0].nid // empty' "$TMPDIR"/proj-*.json 2>/dev/null | sort -u \
  | xargs -n 1 -P "$PARALLEL" bash -c 'fetch_by_nid "$1"' _

# ─── Phase 2b: fetch release-history XML per slug (for supported cores) ─
echo "Fetching release-history XML..." >&2
tail -n +2 "$SOURCE_FILE" | cut -d, -f1 | tr -d ' \r' | grep -v '^$' \
  | xargs -n 1 -P "$PARALLEL" bash -c 'fetch_release_history "$1"' _

# ─── Phase 3: resolve unknown taxonomy term labels (cached across runs) ─
echo "Resolving taxonomy term labels..." >&2
UNIQUE_TERMS=$(jq -r '.list[0] | (.taxonomy_vocabulary_44.id, .taxonomy_vocabulary_46.id) | select(. != null)' \
                 "$TMPDIR"/proj-*.json 2>/dev/null | sort -u)
for tid in $UNIQUE_TERMS; do
  if [ -z "$(jq -r --arg t "$tid" '.[$t] // empty' "$TERM_CACHE_FILE")" ]; then
    label=$(curl -sS --compressed "$API_BASE/taxonomy_term/$tid.json" | jq -r '.name // "Unknown"')
    jq --arg t "$tid" --arg l "$label" '. + {($t): $l}' "$TERM_CACHE_FILE" > "$TMPDIR/terms.json"
    mv "$TMPDIR/terms.json" "$TERM_CACHE_FILE"
    echo "  + term $tid → \"$label\"" >&2
  fi
done

# ─── Phase 4: assemble projects.json ────────────────────────────────────
echo "Assembling $OUTPUT_FILE..." >&2

TERMS=$(cat "$TERM_CACHE_FILE")

# Load Finalist maintainer names as a JSON array for jq lookup.
if [ -f "$FINALIST_FILE" ]; then
  FINALIST_NAMES=$(jq -R -s 'split("\n") | map(select(length > 0))' "$FINALIST_FILE")
else
  FINALIST_NAMES='[]'
  echo "  ⚠ $FINALIST_FILE not found — finalist_maintainers will be empty" >&2
fi

: > "$TMPDIR/entries.jsonl"
# CSV columns: machine_name,status,type — `kind` in output is overridden by
# the CSV `type` value (source of truth), the API `type` is discarded.
while IFS=, read -r slug status kind; do
  slug=$(printf '%s' "$slug" | tr -d '\r' | tr -d '[:space:]')
  status=$(printf '%s' "$status" | tr -d '\r' | tr -d '[:space:]')
  kind=$(printf '%s' "$kind" | tr -d '\r' | tr -d '[:space:]')
  [ -z "$slug" ] && continue

  proj_file="$TMPDIR/proj-$slug.json"
  [ -f "$proj_file" ] || { echo "  ✗ skip $slug (no project data)" >&2; continue; }

  nid=$(jq -r '.list[0].nid // empty' "$proj_file")
  [ -z "$nid" ] && { echo "  ✗ skip $slug (no nid)" >&2; continue; }

  cores_json=$(parse_supported_cores "$TMPDIR/rh-$slug.xml")

  jq -n \
    --slurpfile proj  "$proj_file" \
    --slurpfile rel   "$TMPDIR/rel-$nid.json" \
    --slurpfile maint "$TMPDIR/maint-$nid.json" \
    --argjson terms   "$TERMS" \
    --argjson finalist "$FINALIST_NAMES" \
    --argjson cores   "$cores_json" \
    --arg slug        "$slug" \
    --arg status      "$status" \
    --arg kind        "$kind" \
    '
    $proj[0].list[0]                          as $p |
    ($rel[0].list[0] // null)                 as $r |
    ($maint[0] // {})                         as $m |
    ($m | to_entries | map(.value.name))      as $all_maintainers |
    ($finalist | map(ascii_downcase))         as $finalist_lc |
    ($all_maintainers
      | map(select((ascii_downcase) as $n | $finalist_lc | index($n)))) as $finalist_maintainers |
    {
      machine_name: $slug,
      nid: $p.nid,
      title: $p.title,
      status: $status,
      kind: $kind,
      url: ("https://www.drupal.org/project/" + $slug),
      security_coverage: ($p.field_security_advisory_coverage // "unknown"),
      maintenance_status: ($terms[$p.taxonomy_vocabulary_44.id // ""] // null),
      development_status: ($terms[$p.taxonomy_vocabulary_46.id // ""] // null),
      has_issue_queue: $p.field_project_has_issue_queue,
      has_releases:    $p.field_project_has_releases,
      latest_version: ($r.field_release_version // null),
      latest_release_date: (if ($r.created // null) then ($r.created | tonumber | strftime("%Y-%m-%d")) else null end),
      supported_cores: $cores,
      maintainers: $all_maintainers,
      finalist_maintainers: $finalist_maintainers
    }
  ' >> "$TMPDIR/entries.jsonl"
done < <(tail -n +2 "$SOURCE_FILE")

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

jq -n \
  --slurpfile projects "$TMPDIR/entries.jsonl" \
  --arg gen "$NOW" \
  '{
     generated_at: $gen,
     projects_count: ($projects | length),
     projects: $projects
   }' \
  | { echo "// AI generated - regenerate via build-projects.sh"; printf 'window.projectsData = '; cat; echo ';'; } \
  > "$OUTPUT_FILE"

count=$(sed '1d; s/^window\.projectsData = //; s/;$//' "$OUTPUT_FILE" | jq '.projects | length')
echo "" >&2
echo "Done: $count projects → $OUTPUT_FILE" >&2
