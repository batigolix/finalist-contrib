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
- **`projects-source.csv`** — kolommen `machine_name,status,type`. Header-rij is verplicht. Bepaalt welke projecten in de output verschijnen. Handmatig te onderhouden.
  - `status`: `active` of `inactive`. `build-projects.sh` verwerkt beide; `update-issues.sh` slaat `inactive` standaard over (spaart requests) tenzij `--include-inactive` wordt meegegeven.
  - `type`: `module` of `theme`. Bron van waarheid — overschrijft de API-derived `kind` in `projects.js`.
- **`finalist-maintainers.txt`** — 1 drupal.org display-name per regel (bijv. `batigolix`, `N Sanders`). Case-insensitive gematcht tegen `/project/<nid>/maintainers.json`.
- **`term-labels.json`** — cache van drupal.org taxonomy-term IDs → labels (maintenance/development status). Wordt automatisch bijgevuld door `build-projects.sh`.

### Scripts
- **`build-projects.sh`** — leest `projects-source.csv`, verrijkt via drupal.org api-d7 (title, latest release, maintainers) + `/project/<nid>/maintainers.json`, matcht tegen `finalist-maintainers.txt`, en schrijft `projects.js`. Verwerkt zowel active als inactive projecten (status wordt gewoon in de output opgenomen).
- **`update-issues.sh`** — leest `projects.js`, haalt de laatste 50 issues per project op via de api-d7 en schrijft `issues.js` + overschrijft `projects.js` (met `open_issues` count). Slaat `inactive` projecten standaard over; met `--include-inactive` / `-a` worden ook die gefetcht. Voor overgeslagen projecten blijft de vorige `open_issues`-waarde behouden.

### Viewers
- **`projects.html`** — Grid.js tabel met kolommen: Project · Type (module/theme/distribution) · Versie · Maintenance · Security · Open issues · Finalist maintainers. Filters: Type / Finalist maintainer / Maintenance status / Open issues (>0/=0). "Open issues"-getal linkt naar `issues.html#project=<slug>`.
- **`issues.html`** — Grid.js tabel met open issues per project (Project · Status · Titel · Gewijzigd). Filters: Project / Status. Leest `#project=<slug>` uit de URL-hash om vooraf te filteren.

### Generated (gitignored)
- `projects.js` — output van `build-projects.sh` (en `update-issues.sh` voor open_issues-count).
- `issues.js` — output van `update-issues.sh`.

## Workflow

```bash
# 1. Ververs project-metadata (release, maintainers, status)
./build-projects.sh

# 2. Ververs open issues + open_issues-count in projects.js
./update-issues.sh

# 3. Open in browser
open projects.html   # of issues.html
```

Beide scripts zijn idempotent. `build-projects.sh` duurt ~20 sec (73 projecten), `update-issues.sh` ~2-10 sec (afhankelijk van Fastly-cache).

## Onderhoud

- **Nieuw project/theme toevoegen**: regel toevoegen aan `projects-source.csv` in het formaat `<machine_name>,active,<module|theme>`. Zoek de exacte machine name op via `https://www.drupal.org/project/<slug>` (URL-segment na `/project/`).
- **Project pauzeren zonder verwijderen**: zet `status` op `inactive` in de CSV. Metadata blijft ververst via `build-projects.sh`; issues worden alleen nog gefetcht als je `./update-issues.sh --include-inactive` draait.
- **Nieuwe Finalist medewerker**: regel toevoegen aan `finalist-maintainers.txt` met de drupal.org display name (kijk op `/u/<slug>` — de tekst in `<h1>` is de correcte naam).
- **Projecten waar Finalist geen actieve maintainer op is verwijderen**: haal de regel uit `projects-source.csv` en run beide scripts.

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
