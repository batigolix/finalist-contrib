<!-- AI generated -->
# Finalist Drupal projects & issues

Een lokale, statische tracker voor Drupal-projecten die door Finalist-medewerkers worden onderhouden op drupal.org. Twee bash-scripts halen de data op, twee HTML-viewers tonen 'm.

## Wat je krijgt

- **`projects.html`** — overzicht van alle projecten (modules/themes/distributions) met versie, maintenance-status, security-coverage, open-issue-count, en welke Finalist-medewerkers erop staan als maintainer.
- **`issues.html`** — overzicht van álle open issues over al die projecten, sorteerbaar en filterbaar op project/status. Klik op een issue-titel → drupal.org. Klik op een projectnaam → project-pagina.

Klik in projects.html op het aantal open issues van een project → issues.html opent met dat project al gefilterd.

## Setup (eenmalig)

Je hebt nodig:
- **bash** (macOS/Linux)
- **curl** (met gzip-support — meestal standaard)
- **jq** (`brew install jq` op macOS)

Verder niets. Geen build-server, geen dependencies, geen `npm install`. Grid.js wordt via CDN geladen door de HTML.

## Dagelijks gebruik

```bash
# 1. Ververs project-metadata (title, versie, maintainers, status)
./build-projects.sh          # ±20 sec

# 2a. Ververs open issues voor projecten met issues op drupal.org
./update-issues.sh           # ±2-10 sec

# 2b. Ververs open issues voor projecten waarvan de issue queue is gemigreerd naar git.drupalcode.org
./update-gitlab-issues.sh    # ±2 sec (schaalt met aantal gitlab-projecten)

# 3. Open in browser
open projects.html
open issues.html
```

Alle scripts zijn idempotent. `update-issues.sh` en `update-gitlab-issues.sh` mogen in willekeurige volgorde draaien — beide behouden elkaars rijen in `issues.js`. Als drupal.org ooit de issue-migratie voltooit, verdwijnt `update-issues.sh` en blijft alleen `update-gitlab-issues.sh` over.

## De twee lijsten die je zelf onderhoudt

Twee bestanden zijn de "bron van waarheid" — verander die, run de scripts, en de rest gaat vanzelf.

### `projects-source.csv` — welke projecten willen we volgen?

CSV met vier kolommen en een verplichte header-rij:

```
machine_name,status,type,issues_source
flood_control,active,module,drupal.org
rest_menu_items,active,module,gitlab
chameleon,inactive,theme,drupal.org
```

- **`machine_name`**: het slug in de drupal.org URL (`https://www.drupal.org/project/flood_control` → `flood_control`).
- **`status`**: `active` of `inactive`. Alleen een label — beïnvloedt de bash scripts niet. `projects.html` toont standaard alleen `active` (checkbox "Alleen actieve" uit om ook inactive te zien).
- **`type`**: `module` of `theme`. Deze waarde overschrijft de API-derived kind in `projects.js`.
- **`issues_source`**: `drupal.org` (default) of `gitlab`. Drupal.org migreert issue queues gefaseerd naar git.drupalcode.org — zet dit op `gitlab` zodra je voor een project de migratie-mail van drupal.org krijgt. `update-issues.sh` (api-d7) skipt gitlab-projecten; `update-gitlab-issues.sh` (GitLab REST v4) verwerkt ze.

- **Project toevoegen**: nieuwe regel toevoegen (default `drupal.org` voor issues), run alle scripts.
- **Project pauzeren**: zet `status` op `inactive`. Metadata + issues blijven bijwerken; het project wordt in `projects.html` standaard verborgen.
- **Project verwijderen**: regel weghalen, run alle scripts.
- **Issue queue van project is gemigreerd naar GitLab**: zet `issues_source` op `gitlab`, run `build-projects.sh` + `update-gitlab-issues.sh`.

### `finalist-maintainers.txt` — wie zijn Finalist-medewerkers?

Eén drupal.org **display name** per regel (niet de URL-slug — de weergave-naam op het profiel).

- **Medewerker toevoegen**: zoek de exacte weergavenaam op `https://www.drupal.org/u/<slug>` (staat in de `<h1>`), zet 'm op een nieuwe regel.
- **Medewerker weghalen**: regel weghalen.

Bij de eerstvolgende `build-projects.sh` run zie je in projects.html of de match klopt (kolom "Finalist maintainers").

## Wat betekent wat in de tabel?

**projects.html:**

| Kolom | Betekenis |
|-------|-----------|
| Project | Titel + link naar de drupal.org project-pagina |
| Type | module / theme / distribution / (drupalorg/general voor bijzondere entries) |
| Versie | Nummer van de laatste stable release |
| Drupal | Ondersteunde Drupal-cores (bijv. `10 11 12`) — union van de `core_compatibility` van de nieuwste release op elke supported branch. `—` als er geen releases zijn. Sorteert op hoogste ondersteunde major. |
| Maintenance | drupal.org maintenance-status ("Actively maintained", "Minimally maintained", "Seeking co-maintainer(s)", "Unsupported", ...) |
| Security | Of het project onder de drupal.org security-advisory policy valt |
| Open issues | Aantal open issues; klik → filterde issues-view |
| Finalist maintainers | Wie van jullie erop staat als maintainer |

**issues.html:**

| Kolom | Betekenis |
|-------|-----------|
| Project | Naam + link naar drupal.org project |
| Status | Voor drupal.org-issues: "Active", "Needs review", "Needs work", "RTBC", ... Voor gemigreerde projecten: het GitLab `state::*` label (bijv. `state::needsReview`, `state::accepted`). |
| Titel | Titel van het issue; klik → drupal.org issue of git.drupalcode.org work item |
| Versie | Tegen welke versie/branch dit issue speelt (bijv. `3.0.0`, `2.x-dev`) |
| Gewijzigd | Datum van laatste update (tooltip = tijdstip) |

## FAQ

**Waarom `.js` en niet `.json`?**  
`projects.js` en `issues.js` bevatten JSON gewrapt in `window.projectsData = {...}`. Browsers blokkeren `fetch('*.json')` vanaf `file://` (CORS), maar `<script src="*.js">` niet. Zo werkt de viewer zonder lokale webserver.

**Kan ik de data met `jq` bekijken?**  
Ja:
```bash
sed '1d; s/^window\.[a-zA-Z]*Data = //; s/;$//' projects.js | jq .
```

**Waarom soms 2 sec en soms 20 sec voor `update-issues.sh`?**  
Drupal.org zit achter Fastly-CDN met 15 min cache. Twee runs binnen 15 min = warm cache = seconds. Verse runs = ±1 request per project × 73 = ~15 sec cold cache.

**Er staat een project in de lijst waar geen Finalist meer aan werkt.**  
Regel uit `projects-source.csv` halen en beide scripts opnieuw draaien.

**Ik zie een nieuwe Finalist-collega die op drupal.org actief is maar niet in de tabel staat.**  
Regel toevoegen aan `finalist-maintainers.txt` met de exacte display name. Daarna `build-projects.sh`.

## Voor Claude Code

Zie `CLAUDE.md` voor een technische beschrijving van de pipeline. `TODO.md` bevat de openstaande punten.
