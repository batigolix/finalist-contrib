<!-- AI generated -->
# TODO

## Open

- [ ] **Onderzoek `jq` dependency** — beide scripts vereisen `jq` (hard `command -v` check). Uitzoeken: is dit acceptabel voor collega's (macOS: `brew install jq`, Linux: standaard in repos), of loont het om over te stappen op iets dat standaard aanwezig is (bijv. `python3 -c` met `json`-stdlib)? Ook: zijn alle jq-expressies compatibel met de oudere `jq 1.6` (Ubuntu 20.04) of gebruiken we `jq 1.7`-only features?

## Simplification

_geen open items_

## Done

- [x] Rename modules → projects (project files, variables, UI labels)
- [x] Drop `maintainers.json` uit `build-projects.sh` (was voor `finalist_maintainers` veld)
- [x] Inline docs in EN (comments/section markers), UI blijft Nederlands
- [x] `modules-source.txt` → `projects-source.txt` (committed source of truth)
- [x] Datum-formaat: standaard ISO in tabellen (relatieve tijd via tooltip)
- [x] Grid.js tabel voor projecten
- [x] `finalist-maintainers.txt` toegevoegd (42 display names, gescrapet)
- [x] Scrape-scripts opgeruimd — Fastly CAPTCHA re-challenget elke navigatie, dus automatisch scrapen is niet praktisch. Txt-files zijn nu handmatig te onderhouden.
- [x] **Maintainer-endpoint gevonden**: `/project/<nid>/maintainers.json` retourneert `{uid: {name, permissions}}` voor alle maintainers van een project. `build-projects.sh` haalt dit nu op en matcht tegen `finalist-maintainers.txt` → `finalist_maintainers` per project. 73/142 projecten hebben ≥1 Finalist maintainer.
- [x] `projects.html`: kolom + dropdown-filter voor Finalist maintainer.
- [x] "Explain scraping logic" — obsoleet sinds `/project/<nid>/maintainers.json` endpoint gevonden; scraping vervalt volledig.
- [x] `projects-source.txt` opgeschoond: 142 → 73 (alleen met Finalist maintainer).
- [x] **Cleanup & simplification**: verouderde `recent-issues-plan.md`, leftover `modules.json.new`, `.previous`-backups, `.playwright-cli/`, `template-project-page.txt` (unrelated readme-template) weg. `.gitignore` toegevoegd. `build-projects.sh` en `update-issues.sh` gerefactored: 3 fetch-functies → 1 helper (`fetch_json`), Phase 2+2b samengevoegd (release+maintainers in één worker), dood hout (`priority_label`, `category_label`, `--diff`/`--audit` flags, `.previous` backup) verwijderd, `ptitle`-lookup uit de loop gehaald. build-projects.sh: 51s → 19s. update-issues.sh: 11s → 2.4s.
- [x] **.json output vervangen door .js**: geen aparte `projects.json` / `issues.json` / `projects-overview.json` meer. Alle scripts lezen/schrijven `.js` bestanden (met `window.xxxData = {...}` wrapper) die direct door de HTML-viewers geladen worden. Inspectie via `sed '1d; s/^window\.[a-zA-Z]*Data = //; s/;$//' file.js | jq .`.
- [x] **projects.html**: Machine name kolom verwijderd (nog wel hidden voor URL-generatie); Open issues cell linkt nu naar `issues.html#project=<slug>` en issues.html preselecteert het project-filter via URL-hash.
- [x] **CLAUDE.md** herschreven naar de huidige pipeline: source-of-truth txt-bestanden, twee bash-scripts, twee Grid.js viewers, verwijzing naar api-d7-quirks memory. Verouderde module-list en scraping-secties weg.
- [x] **Issue-versie/branch** — `version` (uit `field_issue_version`) toegevoegd aan `issues.js` en kolom "Versie" in `issues.html`. Toont bijv. `7.x-1.x-dev`, `3.0.0`.
- [x] **README.md** — human-readable instructies voor dagelijks gebruik (setup, workflow, betekenis van kolommen, FAQ).
- [x] **Link naar project in issues.html** — Project-kolom is nu klikbaar naar `https://www.drupal.org/project/<slug>`.
- [x] **Uniform data-formaat** — beide scripts schrijven nu `projects.js` in dezelfde `{generated_at, projects_count, projects: [...]}` wrapper; `update-issues.sh` is tolerant voor beide bare-array en object-input.
- [x] **`projects-source.txt` → `projects-source.csv`** — kolommen `machine_name,status,type` (header verplicht). `status` (active/inactive) bepaalt of `update-issues.sh` issues fetcht (standaard skipt inactive; `--include-inactive`/`-a` overschrijft). `type` (module/theme) is bron van waarheid en overschrijft de API-derived `kind` in `projects.js`. `build-projects.sh` fetcht altijd alle rijen. Overgeslagen projecten behouden hun vorige `open_issues`-count.
