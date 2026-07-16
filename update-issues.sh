#!/usr/bin/env bash
# AI generated
# update-issues.sh — snapshot of open issues for the Finalist Drupal projects.
# Reads projects.json, writes issues.json + issues.js for the HTML viewer,
# and projects-overview.json + projects.js for the projects table.

set -euo pipefail

# ─── Defaults ────────────────────────────────────────────────────────────
PROJECTS_FILE="projects.js"
OUTPUT_DIR="."
INCLUDE_CLOSED=0
INCLUDE_INACTIVE=0
PARALLEL=5
API_BASE="https://www.drupal.org/api-d7/node.json"

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --projects FILE       Projects file (default: projects.js — either .js or .json)
  --output-dir DIR      Output directory (default: .)
  --include-closed      Include closed issues in the snapshot
  --include-inactive|-a Also fetch issues for projects with status="inactive"
                        (skipped by default to save drupal.org requests)
  -h, --help            Show this message
EOF
}

# Extract the projects array from a .js (window.xxxData = {..., projects: [...]};)
# or .json file. Tolerates both wrapper-object and bare-array formats.
projects_json() {
  case "$PROJECTS_FILE" in
    *.js) sed '1d; s/^window\.[a-zA-Z]*Data = //; s/;$//' "$PROJECTS_FILE" ;;
    *)    cat "$PROJECTS_FILE" ;;
  esac | jq 'if type == "array" then . else .projects end'
}

# ─── Parse args ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --projects)          PROJECTS_FILE="$2"; shift 2 ;;
    --output-dir)        OUTPUT_DIR="$2"; shift 2 ;;
    --include-closed)    INCLUDE_CLOSED=1; shift ;;
    --include-inactive|-a) INCLUDE_INACTIVE=1; shift ;;
    -h|--help)           usage; exit 0 ;;
    *)                   echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

# ─── Prereqs ─────────────────────────────────────────────────────────────
command -v curl >/dev/null || { echo "curl required" >&2; exit 2; }
command -v jq   >/dev/null || { echo "jq required"   >&2; exit 2; }
[ -f "$PROJECTS_FILE" ] || { echo "projects file not found: $PROJECTS_FILE" >&2; exit 2; }

TMPDIR=$(mktemp -d -t update-issues.XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

# ─── jq helpers ─────────────────────────────────────────────────────────
# Status IDs: 2,3,5,6,7,17,18 are the closed states on drupal.org.
JQ_LOOKUP='
def status_label:
  {"1":"Active","2":"Fixed","3":"Closed (duplicate)","4":"Postponed",
   "5":"Closed (wont fix)","6":"Closed (works as designed)","7":"Closed (fixed)",
   "8":"Needs review","13":"Needs work","14":"Reviewed & tested by the community",
   "15":"Patch (to be ported)","16":"Postponed (maintainer needs more info)",
   "17":"Closed (outdated)","18":"Closed (cannot reproduce)"}[.] // "Unknown";
def is_closed: . as $s | ["2","3","5","6","7","17","18"] | index($s) != null;
def to_iso: (tonumber | strftime("%Y-%m-%dT%H:%M:%SZ"));
'

# ─── Fetch issues for one project (with retries) ────────────────────────
fetch_project() {
  local nid="$1"
  local slug="$2"
  local out="$TMPDIR/$nid.json"
  local url="${API_BASE}?type=project_issue&field_project=${nid}&sort=changed&direction=DESC&limit=50"
  local tries=0 delay=1
  while [ $tries -lt 3 ]; do
    if curl -sS --compressed --fail -H "Accept: application/json" -o "$out" "$url"; then
      return 0
    fi
    tries=$((tries + 1))
    sleep "$delay"
    delay=$((delay * 2))
  done
  echo "  ✗ $slug (nid=$nid) — failed after 3 attempts" >&2
  return 1
}
export -f fetch_project
export TMPDIR API_BASE

# ─── Parallel fetch via xargs ────────────────────────────────────────────
# Load projects.js/json once. ALL_PROJECTS_JSON preserves the full tracked
# list (so inactive projects survive in the output); PROJECTS_JSON is the
# filtered subset that we actually fetch issues for.
ALL_PROJECTS_JSON=$(projects_json)

if [ "$INCLUDE_INACTIVE" -eq 1 ]; then
  PROJECTS_JSON="$ALL_PROJECTS_JSON"
else
  PROJECTS_JSON=$(jq '[.[] | select((.status // "active") == "active")]' <<<"$ALL_PROJECTS_JSON")
fi

ALL_COUNT=$(jq 'length' <<<"$ALL_PROJECTS_JSON")
PROJECTS_COUNT=$(jq 'length' <<<"$PROJECTS_JSON")
SKIPPED=$((ALL_COUNT - PROJECTS_COUNT))

if [ "$SKIPPED" -gt 0 ]; then
  echo "Fetching $PROJECTS_COUNT active projects (skipping $SKIPPED inactive; parallel=$PARALLEL, gzip on)..." >&2
else
  echo "Fetching $PROJECTS_COUNT projects (parallel=$PARALLEL, gzip on)..." >&2
fi

jq -r '.[] | "\(.nid) \(.machine_name)"' <<<"$PROJECTS_JSON" \
  | xargs -n 2 -P "$PARALLEL" bash -c 'fetch_project "$1" "$2"' _

# ─── Parse each response into issue entries ─────────────────────────────
echo "Processing..." >&2

# Preload machine_name → title map so we don't re-parse the file per row.
TITLE_MAP=$(jq 'map({key: .machine_name, value: .title}) | from_entries' <<<"$ALL_PROJECTS_JSON")

while IFS=' ' read -r nid slug; do
  [ -f "$TMPDIR/$nid.json" ] || { echo "  ⚠ $slug: no response" >&2; continue; }

  parsed=$(jq --arg slug "$slug" \
              --argjson titles "$TITLE_MAP" \
              --argjson closed "$INCLUDE_CLOSED" "
    $JQ_LOOKUP
    .list
    | map(select((\$closed == 1) or (.field_issue_status | is_closed | not)))
    | map({
        project: \$slug,
        project_title: \$titles[\$slug],
        nid: .nid,
        title: .title,
        url: (\"https://www.drupal.org/project/\" + \$slug + \"/issues/\" + .nid),
        status_id: (.field_issue_status | tonumber),
        status_label: (.field_issue_status | status_label),
        version: (.field_issue_version // null),
        created: (.created | to_iso),
        changed: (.changed | to_iso)
      })
  " "$TMPDIR/$nid.json")

  echo "$parsed" > "$TMPDIR/$nid.parsed.json"
  echo "  ✓ $slug: $(echo "$parsed" | jq 'length') open" >&2
done < <(jq -r '.[] | "\(.nid) \(.machine_name)"' <<<"$PROJECTS_JSON")

ALL=$(jq -s 'add' "$TMPDIR"/*.parsed.json 2>/dev/null || echo '[]')

# ─── Write output files ─────────────────────────────────────────────────
mkdir -p "$OUTPUT_DIR"

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
ISSUES_COUNT=$(echo "$ALL" | jq 'length')

# issues.js
jq -n \
  --arg gen "$NOW" \
  --argjson pc "$PROJECTS_COUNT" \
  --argjson ic "$ISSUES_COUNT" \
  --argjson issues "$ALL" \
  '{generated_at: $gen, projects_count: $pc, issues_count: $ic, issues: $issues}' \
  | { echo "// AI generated - regenerate via update-issues.sh"; printf 'window.issuesData = '; cat; echo ';'; } \
  > "$OUTPUT_DIR/issues.js"

# projects.js — reuses all fields from projects.js input, adds open_issues.
# Full list (including inactive) is preserved; open_issues is only refreshed
# for projects we actually fetched. Skipped projects keep their prior count.
PROCESSED_SLUGS=$(jq '[.[].machine_name]' <<<"$PROJECTS_JSON")

jq -n \
  --argjson projects "$ALL_PROJECTS_JSON" \
  --argjson processed "$PROCESSED_SLUGS" \
  --argjson issues "$ALL" \
  --arg gen "$NOW" \
  --argjson pc "$ALL_COUNT" \
  --argjson ic "$ISSUES_COUNT" \
  '
    ($issues | group_by(.project) | map({key: .[0].project, value: length}) | from_entries) as $counts |
    {
      generated_at: $gen,
      projects_count: $pc,
      issues_count: $ic,
      projects: ($projects | map(
        . as $p |
        if ($processed | index($p.machine_name)) then
          $p + { open_issues: ($counts[$p.machine_name] // 0) }
        else
          $p + { open_issues: ($p.open_issues // 0) }
        end
      ))
    }
  ' \
  | { echo "// AI generated - regenerate via update-issues.sh"; printf 'window.projectsData = '; cat; echo ';'; } \
  > "$OUTPUT_DIR/projects.js"

echo "" >&2
echo "Done: $ISSUES_COUNT open issues across $PROJECTS_COUNT projects" >&2
echo "  → $OUTPUT_DIR/issues.js" >&2
echo "  → $OUTPUT_DIR/projects.js (overwritten with open_issues count)" >&2
