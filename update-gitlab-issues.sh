#!/usr/bin/env bash
# AI generated
# update-gitlab-issues.sh — snapshot of open GitLab work items for Finalist
# Drupal projects whose issue queues have migrated to git.drupalcode.org
# (issues_source == "gitlab" in projects.js).
#
# Complements update-issues.sh:
#   - update-issues.sh handles issues_source == "drupal.org" via api-d7.
#   - This script handles issues_source == "gitlab" via GitLab REST v4.
#   - Both scripts preserve each other's rows in issues.js on rewrite, so
#     they can run in any order. open_issues in projects.js is refreshed
#     only for the projects this script actually fetched.
#
# Emits the same issue schema as update-issues.sh so issues.html/projects.html
# do not need to know which backend produced a row.

set -euo pipefail

# ─── Defaults ────────────────────────────────────────────────────────────
PROJECTS_FILE="projects.js"
OUTPUT_DIR="."
PARALLEL=5
PER_PAGE=100
API_BASE="https://git.drupalcode.org/api/v4"

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --projects FILE       Projects file (default: projects.js — either .js or .json)
  --output-dir DIR      Output directory (default: .)
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
    --projects)   PROJECTS_FILE="$2"; shift 2 ;;
    --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
    -h|--help)    usage; exit 0 ;;
    *)            echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

# ─── Prereqs ─────────────────────────────────────────────────────────────
command -v curl >/dev/null || { echo "curl required" >&2; exit 2; }
command -v jq   >/dev/null || { echo "jq required"   >&2; exit 2; }
[ -f "$PROJECTS_FILE" ] || { echo "projects file not found: $PROJECTS_FILE" >&2; exit 2; }

TMPDIR=$(mktemp -d -t update-gitlab-issues.XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

# ─── Fetch open work items for one project across all pages ─────────────
fetch_gitlab_issues() {
  local slug="$1"
  local out="$TMPDIR/gl-$slug.json"
  local combined="$TMPDIR/gl-$slug.pages.jsonl"
  local project_path="project%2F${slug}"
  local page=1
  : > "$combined"
  while :; do
    local tmp="$TMPDIR/gl-$slug.p${page}.json"
    local url="${API_BASE}/projects/${project_path}/issues?state=opened&per_page=${PER_PAGE}&page=${page}"
    if ! curl -sS --compressed --fail -H "Accept: application/json" -o "$tmp" "$url"; then
      echo "  ✗ $slug: GitLab fetch failed on page $page" >&2
      break
    fi
    local count
    count=$(jq 'length' "$tmp")
    [ "$count" -eq 0 ] && break
    cat "$tmp" >> "$combined"
    [ "$count" -lt "$PER_PAGE" ] && break
    page=$((page + 1))
  done
  if [ -s "$combined" ]; then
    jq -s 'add' "$combined" > "$out"
  else
    echo '[]' > "$out"
  fi
}
export -f fetch_gitlab_issues
export TMPDIR API_BASE PER_PAGE

# ─── Load projects and filter to gitlab-issue projects ──────────────────
ALL_PROJECTS_JSON=$(projects_json)
PROJECTS_JSON=$(jq '[.[] | select((.issues_source // "drupal.org") == "gitlab")]' <<<"$ALL_PROJECTS_JSON")

ALL_COUNT=$(jq 'length' <<<"$ALL_PROJECTS_JSON")
PROJECTS_COUNT=$(jq 'length' <<<"$PROJECTS_JSON")

if [ "$PROJECTS_COUNT" -eq 0 ]; then
  echo "No gitlab-issue projects found in $PROJECTS_FILE — nothing to do." >&2
  exit 0
fi

echo "Fetching $PROJECTS_COUNT gitlab-issue projects (of $ALL_COUNT total; parallel=$PARALLEL)..." >&2

jq -r '.[] | .machine_name' <<<"$PROJECTS_JSON" \
  | xargs -n 1 -P "$PARALLEL" bash -c 'fetch_gitlab_issues "$1"' _

# ─── Parse each response into the shared issue schema ───────────────────
echo "Processing..." >&2

TITLE_MAP=$(jq 'map({key: .machine_name, value: .title}) | from_entries' <<<"$ALL_PROJECTS_JSON")

while IFS= read -r slug; do
  in="$TMPDIR/gl-$slug.json"
  [ -f "$in" ] || { echo "  ⚠ $slug: no response" >&2; continue; }

  parsed=$(jq --arg slug "$slug" \
              --argjson titles "$TITLE_MAP" '
    def state_label:
      (.labels // []) | map(select(startswith("state::"))) | .[0] // "opened";
    def version_label:
      (.labels // []) | map(select(test("^v[0-9]"))) | .[0] // null
      | if . then sub("^v"; "") else null end;
    def to_iso:
      sub("\\.[0-9]+Z$"; "Z");
    map({
      project: $slug,
      project_title: $titles[$slug],
      nid: .iid,
      title: .title,
      url: .web_url,
      status_id: null,
      status_label: state_label,
      version: version_label,
      created: (.created_at | to_iso),
      changed: (.updated_at | to_iso)
    })
  ' "$in")

  echo "$parsed" > "$TMPDIR/$slug.parsed.json"
  echo "  ✓ $slug: $(echo "$parsed" | jq 'length') open" >&2
done < <(jq -r '.[] | .machine_name' <<<"$PROJECTS_JSON")

# ─── Merge fresh gitlab issues with preserved drupal.org rows ───────────
jq -s 'add // []' "$TMPDIR"/*.parsed.json 2>/dev/null > "$TMPDIR/fresh_issues.json" \
  || echo '[]' > "$TMPDIR/fresh_issues.json"

GITLAB_SLUGS=$(jq '[.[].machine_name]' <<<"$PROJECTS_JSON")
PRIOR_ISSUES_FILE="$OUTPUT_DIR/issues.js"
if [ -f "$PRIOR_ISSUES_FILE" ]; then
  sed '1d; s/^window\.[a-zA-Z]*Data = //; s/;$//' "$PRIOR_ISSUES_FILE" \
    | jq --argjson gitlab "$GITLAB_SLUGS" \
        '(.issues // []) | map(select(.project as $p | ($gitlab | index($p)) | not))' \
    > "$TMPDIR/preserved_issues.json"
else
  echo '[]' > "$TMPDIR/preserved_issues.json"
fi

jq -s 'add' "$TMPDIR/preserved_issues.json" "$TMPDIR/fresh_issues.json" \
  > "$TMPDIR/all_issues.json"

echo "$ALL_PROJECTS_JSON" > "$TMPDIR/all_projects.json"

# ─── Write output files ─────────────────────────────────────────────────
mkdir -p "$OUTPUT_DIR"

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
ISSUES_COUNT=$(jq 'length' "$TMPDIR/all_issues.json")

# issues.js
jq -n \
  --arg gen "$NOW" \
  --argjson pc "$ALL_COUNT" \
  --argjson ic "$ISSUES_COUNT" \
  --slurpfile issues_wrap "$TMPDIR/all_issues.json" \
  '{generated_at: $gen, projects_count: $pc, issues_count: $ic, issues: $issues_wrap[0]}' \
  | { echo "// AI generated - regenerate via update-gitlab-issues.sh"; printf 'window.issuesData = '; cat; echo ';'; } \
  > "$OUTPUT_DIR/issues.js"

# projects.js — reuses all fields from input, refreshes open_issues only for
# the gitlab-issue projects; other projects keep their prior count.
jq -n \
  --slurpfile projects_wrap "$TMPDIR/all_projects.json" \
  --argjson processed "$GITLAB_SLUGS" \
  --slurpfile issues_wrap "$TMPDIR/all_issues.json" \
  --arg gen "$NOW" \
  --argjson pc "$ALL_COUNT" \
  --argjson ic "$ISSUES_COUNT" \
  '
    ($projects_wrap[0]) as $projects |
    ($issues_wrap[0])   as $issues   |
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
  | { echo "// AI generated - regenerate via update-gitlab-issues.sh"; printf 'window.projectsData = '; cat; echo ';'; } \
  > "$OUTPUT_DIR/projects.js"

FRESH_COUNT=$(jq 'length' "$TMPDIR/fresh_issues.json")
echo "" >&2
echo "Done: $FRESH_COUNT open GitLab work items across $PROJECTS_COUNT projects (total in issues.js: $ISSUES_COUNT)" >&2
echo "  → $OUTPUT_DIR/issues.js" >&2
echo "  → $OUTPUT_DIR/projects.js (open_issues refreshed for gitlab projects)" >&2
