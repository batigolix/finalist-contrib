# CLAUDE.md

Guidance for Claude Code when working in this repo.

## Project Overview

Pipeline for tracking Finalist-maintained Drupal projects (modules, themes, distributions) on drupal.org:

- **Bronbestanden** (source of truth, gecommit): een lijst van project machine names + een lijst van Finalist maintainer usernames.
- **Scripts**: verrijken bronbestanden via de drupal.org API tot een `projects.js` en `issues.js` snapshot.
- **Viewers**: statische HTML met Grid.js — sorteerbaar/filterbaar overzicht van projecten en open issues, direct openbaar via `file://`.

Geen scraping, geen build-server nodig. Alles draait lokaal op `curl` + `jq` + `bash`.

## Files

### Source (committed)
- **`projects-source.csv`** — kolommen `machine_name,status,type,issues_source`. Header-rij is verplicht. Bepaalt welke projecten in de output verschijnen. Handmatig te onderhouden.
  - `status`: `active` of `inactive`. Puur een label — beïnvloedt de bash scripts niet (alle non-gitlab projecten worden altijd gefetcht). `projects.html` toont standaard alleen `active` via een checkbox.
  - `type`: `module` of `theme`. Bron van waarheid — overschrijft de API-derived `kind` in `projects.js`.
  - `issues_source`: `drupal.org` (default) of `gitlab`. Drupal.org migreert issue queues gefaseerd naar git.drupalcode.org — flip dit veld zodra de migratie-mail voor een project binnenkomt. `update-issues.sh` skipt `gitlab`; `update-gitlab-issues.sh` verwerkt ze.
- **`finalist-maintainers.txt`** — 1 drupal.org display-name per regel (bijv. `batigolix`, `N Sanders`). Case-insensitive gematcht tegen `/project/<nid>/maintainers.json`.
- **`term-labels.json`** — cache van drupal.org taxonomy-term IDs → labels (maintenance/development status). Wordt automatisch bijgevuld door `build-projects.sh`.

### Scripts
- **`build-projects.sh`** — leest `projects-source.csv`, verrijkt via drupal.org api-d7 (title, latest release, maintainers) + `/project/<nid>/maintainers.json`, matcht tegen `finalist-maintainers.txt`, en schrijft `projects.js`. Verwerkt zowel active als inactive projecten. `issues_source` en `status` uit de CSV worden doorgezet naar `projects.js`.
- **`update-issues.sh`** — leest `projects.js`, haalt de laatste 50 issues per project op via de api-d7 (drupal.org) en schrijft `issues.js` + overschrijft `projects.js` (met `open_issues` count). Fetcht alle non-gitlab projecten (inclusief `inactive`); skipt alleen `issues_source == "gitlab"`. Rijen voor gitlab-projecten in `issues.js` worden vanuit de vorige run behouden zodat `update-gitlab-issues.sh` in willekeurige volgorde mag draaien.
- **`update-gitlab-issues.sh`** — leest `projects.js`, haalt open work items op via de git.drupalcode.org REST v4 API (`/api/v4/projects/project%2F<slug>/issues?state=opened`) voor projecten met `issues_source == "gitlab"`, mergt in `issues.js` (bestaande drupal.org-rijen blijven staan) en refresh't `open_issues` in `projects.js` alleen voor die projecten. Emit dezelfde issue-schema als `update-issues.sh`; status-label = eerste `state::*` uit `labels`.

### Viewers
- **`projects.html`** — Grid.js tabel met kolommen: Project · Type (module/theme/distribution) · Versie · Maintenance · Security · Open issues · Finalist maintainers. Filters: Type / Finalist maintainer / Maintenance status / Open issues (>0/=0). "Open issues"-getal linkt naar `issues.html#project=<slug>`.
- **`issues.html`** — Grid.js tabel met open issues per project (Project · Status · Titel · Gewijzigd). Filters: Project / Status. Leest `#project=<slug>` uit de URL-hash om vooraf te filteren.

### Frontend assets
- **`vendor/gridjs/`** — gevendorde Grid.js dist-files (JS + mermaid theme CSS). Versie in `VERSION`-bestand; bijwerken = twee curl-commando's uit dat bestand + version-bump.
- **`assets/css/`** — per-page stylesheets (`projects.css`, `issues.css`).
- **`assets/js/`** — per-page init-scripts (`projects-init.js`, `issues-init.js`). De HTMLs bevatten geen inline `<script>` of `<style>` meer, zodat ze onder Jenkins' default Content-Security-Policy header werken (HTML Publisher).

### Generated (gitignored)
- `projects.js` — output van `build-projects.sh` (en `update-issues.sh` voor open_issues-count).
- `issues.js` — output van `update-issues.sh`.

### Jenkins (optioneel)
- **`Jenkinsfile.build-projects`** — wekelijkse pipeline (maandag 06:00) die `build-projects.sh` draait en `projects.js` + `term-labels.json` archiveert als build artifacts.
- **`Jenkinsfile.update-issues`** — dagelijkse pipeline (werkdagen 07:00) die via de Copy Artifact plugin `projects.js` uit de build-projects job trekt, achtereenvolgens `update-issues.sh` en `update-gitlab-issues.sh` draait, en `projects.js` + `issues.js` archiveert. Beide scripts moeten in dezelfde job draaien omdat ze samen één `issues.js` produceren.
- Jobs verwachten `curl` + `jq` op de agent en outbound HTTPS naar www.drupal.org **en** git.drupalcode.org. De update-issues job noemt de build-projects job standaard `finalist-contrib-build-projects` (via job-parameter aanpasbaar).

## Workflow

```bash
# 1. Ververs project-metadata (release, maintainers, status)
./build-projects.sh

# 2a. Ververs open issues voor drupal.org-projecten
./update-issues.sh

# 2b. Ververs open issues voor gitlab-projecten (issues_source == "gitlab")
./update-gitlab-issues.sh

# 3. Open in browser
open projects.html   # of issues.html
```

Alle scripts zijn idempotent. `build-projects.sh` duurt ~20 sec (75 projecten), `update-issues.sh` ~2-10 sec (afhankelijk van Fastly-cache), `update-gitlab-issues.sh` ~1-2 sec per gitlab-project. De twee update-scripts mogen in willekeurige volgorde — beide behouden elkaars rijen in `issues.js`.

## Onderhoud

- **Nieuw project/theme toevoegen**: regel toevoegen aan `projects-source.csv` in het formaat `<machine_name>,active,<module|theme>,drupal.org`. Zoek de exacte machine name op via `https://www.drupal.org/project/<slug>` (URL-segment na `/project/`).
- **Project pauzeren zonder verwijderen**: zet `status` op `inactive` in de CSV. Metadata + issues blijven ververst; het project verdwijnt alleen uit de default view in `projects.html` (checkbox "Alleen actieve" is standaard aan).
- **Issue queue van project migreert naar GitLab** (drupal.org stuurt hierover een mail): zet de vierde kolom `issues_source` op `gitlab`. Run `./build-projects.sh` + `./update-gitlab-issues.sh`. `update-issues.sh` skipt het project vanaf dan automatisch.
- **Nieuwe Finalist medewerker**: regel toevoegen aan `finalist-maintainers.txt` met de drupal.org display name (kijk op `/u/<slug>` — de tekst in `<h1>` is de correcte naam).
- **Projecten waar Finalist geen actieve maintainer op is verwijderen**: haal de regel uit `projects-source.csv` en run alle scripts.

## Drupal.org API-details (referentie)

Voor uitgebreide notities over de api-d7 quirks (filter-limitaties, ontbrekende velden, useful escape hatches), zie de memory-entry `drupalorg-api-d7-quirks`.

Key endpoints in deze pipeline:
- `/api-d7/node.json?field_project_machine_name=<slug>` — resolve + volledige project-node in één call
- `/api-d7/node.json?type=project_release&field_release_project=<nid>&sort=created&direction=DESC&limit=1` — laatste release
- `/api-d7/node.json?type=project_issue&field_project=<nid>&sort=changed&direction=DESC&limit=50` — issues
- `/project/<nid>/maintainers.json` — **niet** onder api-d7; retourneert `{uid: {name, permissions}, ...}` voor alle maintainers

Filter closed issues altijd client-side: de api-d7 accepteert alleen single-value filters, dus 7 open statussen zou 7× requests kosten. Cutoff-filter (`changed>=X`) bestaat niet — je moet sorteren en client-side afkappen.

**Prestaties**: gebruik altijd `curl --compressed` (gzip ~8× kleiner over the wire). Fastly cached responses 15 min — herhaalruns zijn near-instant. Parallelliseer met `xargs -P 5` (of hoger); geen rate-limit gemeld op 5 concurrent.

## Data-inspectie

De `.js`-bestanden zijn geen pure JSON — ze zijn gewrapt in `window.xxxData = {...};` zodat `file://` viewers ze via `<script>` kunnen laden zonder CORS-issue. Om ze met `jq` te bekijken:

```bash
sed '1d; s/^window\.[a-zA-Z]*Data = //; s/;$//' projects.js | jq .
```

## Notes

- Het project heeft geen build-server, geen tests, geen CI. Alles draait handmatig via de twee shell-scripts.
- Zie `TODO.md` voor lopende to-dos.
