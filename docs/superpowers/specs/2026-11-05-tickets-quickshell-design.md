# Ticket-Board in Quickshell (Super+m)

Stand: 2026-11-05. Ersetzt Mission Control (`eww/scripts/todo.py` + eww-Fenster
`mission`) und die nie gebaute Spec `2026-11-05-mission-control-quickshell-design.md`
durch ein Ticket-System wie Jira: Board mit Spalten, Projekte, Prioritaet, Labels.
Die Tickets sind Markdown-Dateien im Obsidian-Vault.

## Ziel

Aufgaben wie in Jira verwalten: Projekte mit Kennungen (`WORK-3`), ein Board mit
fuenf Spalten, Prioritaet und Labels auf der Karte, Notizen je Ticket in Obsidian.
Das Board zeigt so viel wie moeglich, der Rest steht in einem Detail-Popup.
Claude Code und Codex legen Tickets per CLI an und schieben sie weiter.
Viele Mikroanimationen wie in Fensterliste und Workspace-Raster.

## Entscheidungen (mit Osa abgestimmt)

- Ersetzt Mission Control samt `Super+m` / `Super+Ctrl+m`; die Missionen werden migriert.
- Spalten: Backlog / ToDo / In Arbeit / Review / Fertig. Aus "Fokus, max. 3" wird das
  WIP-Limit 3 auf In Arbeit (ueber alle Projekte).
- Felder: Titel, Projekt, Status, Prioritaet, Labels. Kein Typ, keine Faelligkeit,
  kein Verlauf, keine Kommentare.
- Speicher: Obsidian-Vault, Projekt = Unterordner, Ticket = Markdown-Datei mit
  Frontmatter + Tags. Jedes Ticket hat Notizen wie die Missionen.
- Zugriff: Board in Quickshell + CLI `ticket.py` fuer Agenten.
- Layout: Vollbild-Board als Overlay auf dem fokussierten Monitor, Detail-Popup mittig.
- Drag & Drop zwischen Spalten gehoert dazu.
- Datenschicht: `ticket.py` bearbeitet die Dateien direkt. Kein Obsidian-REST-Plugin
  (braeuchte laufendes Obsidian), keine zweite Logik in JavaScript, kein PyYAML.

## Aufbau

| Datei | Aenderung |
|---|---|
| `sway/scripts/ticket.py` | neu: einzige Stelle, die Ticket-Dateien schreibt (CLI, `watch`, `migrate`, `selftest`) |
| `quickshell/Tickets.qml` | neu: Board, Detail-Popup, Tasten, Drag & Drop, Animationen |
| `quickshell/shell.qml` | `Tickets { shell: root }` einbinden; Farben bleiben oben in `shell.qml` |
| `sway/config` | `$mod+m` -> `quickshell ipc call tickets toggle`; `$mod+Ctrl+m` -> `ask.sh "NEUES TICKET" \| ticket.py quick` |
| `eww/eww.yuck` | `info`: Zeile Super+m / Super+Ctrl+m nachziehen; Mission-Teile (`deflisten missions`, `defvar mission_tab`, `mission-row`, `mission-list`, `defwindow mission`) raus |
| `eww/eww.scss` | nur von Mission Control benutzte `.ms-*`-Regeln raus (Journal/Agenten nutzen u. a. `.mission`, `.ms-head`, `.ms-title`, `.ms-tabs`, `.ms-action`; vor dem Loeschen per grep pruefen) |
| `eww/scripts/todo.py` | geloescht |
| `CLAUDE.md` = `AGENTS.md`, `theme-erstellen`-Skill (beide Kopien) | Komponenten-Tabelle, Standard-Bedienung (Mission Control -> Tickets), Bausteinliste, "gehoert zum Setup", Tag-Tabelle |

`theme.sh` deployt `sway/` und `quickshell/` als ganze Ordner, kein neuer Eintrag in `map()`.

Ausserhalb des Repos (in "gehoert zum Setup" dokumentieren):
`~/.local/bin/ticket` -> `~/.config/sway/scripts/ticket.py` (Symlink) und je eine Zeile
in `~/.claude/CLAUDE.md` und `~/.codex/AGENTS.md`: Tickets per `ticket` verwalten,
Status/Projekt/Felder nur ueber `ticket set`, Notiztext darf direkt bearbeitet werden.

## Ticket-Datei

```
~/Private/obsidian-vault/Tickets/
├── WORK/
│   ├── WORK-1 SEO einarbeiten und plan erstellen.md
│   └── WORK-3 Atlas MCP anpassen.md
└── AURORA/
    └── AURORA-1 Online Docs fuer Aurora.md
```

```markdown
---
status: todo
prio: mittel
created: 2026-11-05
aliases: [WORK-3]
tags: [ticket, projekt/work, status/todo, prio/mittel, mcp, docs]
---

## Ziel

## Naechste Schritte
- [ ]

## Notizen & Links
```

- **Projekt = Ordner** unter `Tickets/`, Name = Kennung (`[A-Z][A-Z0-9]*`). Andere Ordner
  werden ignoriert. Neues Projekt = neuer Ordner (Board, CLI oder Obsidian).
- **Dateiname** `<KENNUNG>-<N> <Titel>.md`. Kennung + Nummer sind die feste ID, der Rest
  ist der Titel (eine Quelle, kein `title:`-Feld). Titel aendern = Datei umbenennen.
  Zeichen, die Obsidian im Dateinamen nicht mag (`/ \ : * ? " < > | # ^ [ ]`), werden
  durch Leerzeichen ersetzt, Leerzeichenfolgen zusammengezogen, hoechstens 80 Zeichen
  (an Wortgrenze gekuerzt).
- **Nummer** = hoechste Nummer im Projektordner + 1 (archivierte zaehlen mit).
- **Felder**: `status` in `backlog | todo | in-arbeit | review | fertig`,
  `prio` in `hoch | mittel | niedrig` (Standard `mittel`), `created` (Datum),
  `archived: true` nur wenn wahr, `aliases` enthaelt die aktuelle und alle frueheren
  Kennungen, damit `[[WORK-3]]` immer aufloest.
- **Frontmatter ist die Wahrheit.** Verwaltete Tags (`ticket`, `projekt/<kennung klein>`,
  `status/<status>`, `prio/<prio>`) schreibt `ticket.py` bei jedem Schreiben aus den
  Feldern neu. **Labels = alle anderen Tags** (z. B. in Obsidian `#mcp` als Property-Tag
  ergaenzt -> Label `mcp`). Inline-`#tags` im Text zaehlen nicht.
- **Fremde Properties** und Kommentare im Frontmatter bleiben Zeichen fuer Zeichen
  erhalten; ersetzt werden nur die Zeilen(bloecke) der verwalteten Schluessel
  (`status prio created archived aliases tags`). Fehlt ein verwalteter Schluessel,
  wird er angehaengt.
- **Inhalt** neuer Tickets aus `Templates/Ticket.md` im Vault (beim ersten Mal mit dem
  Inhalt oben angelegt, danach frei aenderbar). Der Text unter dem Frontmatter wird von
  `ticket.py` nie veraendert.
- **Checkliste**: `- [ ]` / `- [x]` im Text werden gezaehlt -> `check: [erledigt, gesamt]`.

### Frontmatter-Leser

Kein PyYAML (nicht installiert, wuerde beim Schreiben alles umformatieren). Eigener
Leser fuer das, was Obsidian schreibt: `key: wert`, Inline-Listen `[a, b]` und
Blocklisten (`key:` + Zeilen `  - a`), Werte optional in `"…"`/`'…'`. Unbekannte
Konstrukte bleiben als rohe Zeilen erhalten.

## CLI `ticket.py`

```
ticket.py list [PROJ] [STATUS]   Tabelle: WORK-3  todo  mittel  Atlas MCP anpassen  #mcp (ohne archivierte)
ticket.py show KEY               Pfad, Frontmatter, Inhalt
ticket.py new PROJ TITEL [-p PRIO] [-l LABEL]... [-s STATUS]   gibt die neue Kennung aus
ticket.py set KEY FELD WERT      FELD: status | prio | title | project | labels | archived
ticket.py open KEY               in Obsidian oeffnen (obsidian://open?path=, dann Fenster fokussieren)
ticket.py quick                  stdin "[PROJ:] Titel [#label]... [!prio]" (Super+Ctrl+m)
ticket.py watch                  JSON-Stand je Zeile (fuer Quickshell)
ticket.py migrate                einmalig: Missionen -> WORK
ticket.py selftest
```

- Alle Schreibbefehle unter `flock` (`Tickets/.lock`), Schreiben atomar
  (`<datei>.tmp` + `os.replace`).
- KEY wird gross/klein-unabhaengig gesucht, auch ueber `aliases` (alte Kennung findet
  das Ticket nach einem Projektwechsel).
- **WIP-Limit:** `set KEY status in-arbeit` (und `new -s in-arbeit`) bricht ab, wenn
  schon 3 nicht archivierte Tickets in Arbeit sind; die Meldung nennt sie.
- `set KEY project ZIEL`: Datei wandert nach `Tickets/ZIEL/` (Ordner wird bei Bedarf
  angelegt), neue Nummer, alte Kennung bleibt in `aliases`; gibt die neue Kennung aus.
- `set KEY labels "mcp docs"`: ersetzt alle Labels, verwaltete Tags bleiben.
- `set KEY archived ja|nein`.
- `quick`: `AURORA: Titel #mcp !hoch` -> Projekt AURORA; ohne `PROJ:` das zuletzt
  benutzte Projekt (`~/.local/state/tickets-last`), sonst `WORK`. Status `todo`.
- Fehler: Text auf stderr, Exit-Code 1. Nur `quick` meldet zusaetzlich per `notify-send`.
- Freitext kommt immer als eigenes Argument oder ueber stdin, nie ueber eine Shell-Zeile.

### `watch`

Prueft jede Sekunde die mtimes unter `Tickets/*/` und liest nur geaenderte Dateien neu.
Bei Aenderung eine Zeile:

```json
{"projects": ["AURORA", "WORK"],
 "tickets": [{"key": "WORK-3", "project": "WORK", "num": 3, "title": "Atlas MCP anpassen",
              "status": "todo", "prio": "mittel", "labels": ["mcp"], "archived": false,
              "check": [2, 5], "created": "2026-11-05", "mtime": 1793900000,
              "path": "/home/osa/Private/obsidian-vault/Tickets/WORK/WORK-3 Atlas MCP anpassen.md",
              "body": "## Ziel\n…", "bad": ""}],
 "wip": 1, "error": ""}
```

`bad` = Grund, wenn das Ticket ungueltige Felder hat (siehe Fehlerfaelle), sonst leer.
`error` sammelt Hinweise (Dateien ohne Kennung, doppelte Kennungen, Lesefehler).

## Board (`quickshell/Tickets.qml`)

### Fenster

- `IpcHandler { target: "tickets" }` mit `toggle()`, `open()`, `close()`. Beim Oeffnen
  wird der Monitor aus `I3.focusedMonitor.name` festgehalten.
- `PanelWindow` wie das Workspace-Raster: Ebene Overlay, alle Kanten verankert,
  `exclusionMode: Ignore`, `keyboardFocus: Exclusive`, Namespace `tickets`.
- Abdunkelung mit MouseArea (Klick daneben schliesst), darauf das Board mit Rand
  (oben Waybar beruecksichtigt).
- Ein `Process` mit `ticket.py watch` laeuft dauerhaft (Daten sind beim Oeffnen da),
  `stdout: SplitParser`. Endet er, nach 2 s neu starten.
- Aktionen per `Process` mit Argument-Array (`ticket.py set KEY FELD WERT` usw.).
  stderr eines fehlgeschlagenen Aufrufs -> Fehlerzeile.
- Gemerkt, solange Quickshell laeuft: aktiver Projekt-Reiter, gewaehlte Karte,
  Archiv-Schalter, Label-Filter.

### Inhalt

```
┌ λ TICKETS   [ALLE 14] WORK 12  AURORA 2   ⌕ mcp ×   ◫ Archiv          ✕ ┐
│ BACKLOG 3   │ TODO 6      │ IN ARBEIT 2/3 │ REVIEW 1    │ FERTIG 5      │
│ ┌─────────┐ │ ┌─────────┐ │ ┌───────────┐ │ ┌─────────┐ │ ┌─────────┐   │
│ │WORK-6  ▼│ │ │AURORA-1▲│ │ │WORK-3    ●│ │ │WORK-15 ●│ │ │WORK-1   │   │
│ │Automated│ │ │Online   │ │ │Atlas MCP  │ │ │Powerpnt │ │ │SEO plan │   │
│ │Test ... │ │ │Docs ... │ │ │anpassen   │ │ │an Jan   │ │ └─────────┘   │
│ │         │ │ │#docs ☑1/4│ │ │#mcp  ☑2/5 │ │ └─────────┘ │               │
│ └─────────┘ │ └─────────┘ │ └───────────┘ │             │               │
├─────────────┴─────────────┴───────────────┴─────────────┴───────────────┤
│ hjkl waehlen · H/L schieben · ⏎ Details · n neu · p Prio · / Filter      │
└──────────────────────────────────────────────────────────────────────────┘
```

- **Kopf:** λ, `TICKETS`, Projekt-Reiter mit Anzahl (`ALLE` zuerst, dann alphabetisch),
  Label-Filter (zeigt nur Karten mit diesem Label), Schalter Archiv, ✕.
- **Spalten:** gleich breit, Kopf mit Name + Anzahl, In Arbeit als `n/3`. Jede Spalte
  scrollt fuer sich. Sortierung: Prioritaet (hoch zuerst), dann Nummer; Fertig nach
  `mtime`, neueste oben.
- **Karte:** Kennung (gedimmt), Prioritaet (▲ hoch, ● mittel, ▼ niedrig, eigene Farben),
  Titel bis 3 Zeilen, Labels als Chips, `☑ erledigt/gesamt` falls Checkliste.
  Archivierte (nur mit Schalter sichtbar) gedimmt. `bad` -> roter Rand.
- **Detail-Popup** (Enter oder Klick): mittig ueber dem Board. Kennung, Titel, Projekt,
  Status und Prioritaet als anklickbare Chips, Labels, `created`, dann der Notiztext
  als gerendertes Markdown (`Text.MarkdownText`), scrollbar. Knoepfe Obsidian (o),
  Archivieren (a). Der Notiztext wird nur in Obsidian bearbeitet.
- **Neu** (`n`): Eingabefeld klappt oben in der aktuellen Spalte auf, Format wie `quick`
  (`Titel #mcp !hoch`), Status = Spalte. Projekt = aktiver Reiter; unter `ALLE`
  `PROJ: Titel`, sonst zuletzt benutztes Projekt.
- **Fehlerzeile** ueber dem Fuss: `error` aus `watch` und stderr fehlgeschlagener Aufrufe.
- **Fuss:** Tastenzeile.

### Tasten

| Taste | Wirkung |
|---|---|
| `h` / `l`, `←` / `→` | Spalte waehlen |
| `j` / `k`, `↓` / `↑` | Karte waehlen |
| `H` / `L` | Karte eine Spalte zurueck / weiter (WIP-Limit greift) |
| `Enter` | Detail-Popup |
| `Esc` | Eingabe abbrechen, sonst Popup schliessen, sonst Board schliessen |
| `n` | neues Ticket (inline) |
| `e` | Titel inline bearbeiten |
| `t` | Labels inline bearbeiten (`mcp docs`, leer = keine) |
| `p` | Prioritaet weiterschalten (hoch -> mittel -> niedrig -> hoch) |
| `P` | Projekt wechseln (inline, Kennung aendert sich) |
| `a` | archivieren an/aus |
| `A` | Archiv einblenden an/aus |
| `o` | in Obsidian oeffnen, Board schliesst |
| `Tab` / `Shift+Tab`, `0`-`9` | Projekt-Reiter (`0` = ALLE, `1`-`9` = n-tes Projekt) |
| `/` | Label-Filter eingeben (leer = aus) |

Im Eingabefeld: `Enter` = speichern (leer = abbrechen), `Esc` = abbrechen.
Die Auswahl wird auf die Spaltenlaenge begrenzt, wenn Karten verschwinden; nach einem
Wechsel/Verschieben bleibt sie auf derselben Kennung.

Maus: Hover waehlt, Klick = Detail-Popup, Karte per Drag & Drop in eine andere Spalte
ziehen = Status setzen, Klick auf Reiter/Chips/Schalter wie die Tasten.

`Super+m` schliesst das Board auch bei exklusivem Tastaturfokus (sway-Bind).

## Animationen

Bausteine wie in `shell.qml`: Federn `SpringAnimation` (spring 4-5, damping 0.25-0.32),
Ploppen `Easing.OutBack`, gelbes Gluehen. Endlos-Animationen nur `running: open`.
Weitere Mikroanimationen sind ausdruecklich erwuenscht (Osa: "ich liebe micro animation").

**Oeffnen / Schliessen**
- Abdunkelung blendet ein, Board ploppt auf (scale 0.92 -> 1).
- Spalten kommen gestaffelt von unten (je 40 ms), danach ihre Karten gestaffelt.
- λ leuchtet auf und atmet danach. Schliessen: alles schnell rueckwaerts (~200 ms),
  erst danach wird das Fenster unsichtbar.

**Navigation**
- Leuchtender Auswahlrahmen gleitet federnd zur gewaehlten Karte, passt die Hoehe an,
  auch ueber Spalten hinweg.
- Reiter-Markierung gleitet und streckt sich; Reiterwechsel: Karten gleiten seitlich raus/rein.
- Kopf der gewaehlten Spalte hellt auf.

**Karten bewegen** (`H`/`L`, Drag & Drop)
- Die Karte fliegt als Kopie ueber dem Board von der alten zur neuen Stelle; die Luecke
  schliesst sich federnd, in der Zielspalte rueckt Platz auf.
- Beim Ziehen: Karte hebt sich (scale 1.04, Schatten waechst, leicht gekippt),
  Zielspalte leuchtet.
- In Arbeit voll: Karte prallt zurueck, `3/3` wackelt und blinkt rot, Hinweis
  "Drei reichen fuer jetzt" blendet kurz ein; `ticket.py` wird dann nicht gerufen.
- Nach Fertig: ~8 Funken + Haken zeichnet sich (`QtQuick.Shapes`).
- Spaltenzaehler rollen zur neuen Zahl, Badge huepft.

**Karten**
- Neu: ploppt mit kurzem Gluehen rein. Archivieren: klappt zusammen.
- Hover: leicht anheben (scale 1.02), Rand hellt auf.
- Prio hoch: Akzentstrich links atmet.
- `p`: Prio-Pfeil dreht sich zur neuen Stufe, Farbe blendet.
- Checklisten-Zaehler blitzt kurz, wenn er waechst.

**Detail-Popup**
- Waechst federnd aus der Karte (deren Position/Groesse) in die Mitte, schrumpft zurueck.
- Status-/Prio-Chips: Auswahl gleitet, Klick drueckt den Chip kurz ein.

**Eingabe / Fehler**
- Eingabefelder klappen federnd auf, Cursor blinkt; Enter blitzt kurz, Feld klappt zu.
- Fehlerzeile schuettelt sich, pulsiert rot, blendet nach 4 s aus.
- Leere Spalte: gestrichelter Rahmen pulsiert sanft.

Optimistische Animationen (Fliegen, Funken) laufen vor dem Aufruf. Kommt der neue Stand
nicht oder schlaegt der Aufruf fehl, zeigt das Board mit dem naechsten `watch`-Stand
wieder die Wahrheit (Karte springt zurueck).

## Migration (`ticket.py migrate`)

- Liest `~/.local/share/missions/data.json`. Bricht ab, wenn `Tickets/WORK/` schon
  Tickets enthaelt.
- Jede Mission wird `WORK-<n>`, nummeriert in Reihenfolge der Missions-ID (ab 1).
- Status: Fokus -> `in-arbeit`, offen -> `todo`, erledigt -> `fertig`. Archivierte
  behalten den Status und bekommen `archived: true`. `prio: mittel`, `created` =
  Migrationsdatum, keine Labels.
- Titel = Missionstext, gekuerzt wie oben. Wurde gekuerzt, steht der volle Text als
  erste Zeile unter `## Ziel`.
- Gibt es `Missionen/Mission-<id>.md`, wird deren Text ab `## Ziel` uebernommen
  (ohne Frontmatter, ohne `# Titel`, ohne die Zeile "> Aufgabenstatus und Titel …").
  Sonst Inhalt aus der Vorlage.
- `data.json`, die Backups und `Missionen/` bleiben unveraendert liegen.

## Fehlerfaelle

- Unbekannter `status`/`prio` (z. B. in Obsidian vertippt): Ticket erscheint im Backlog
  bzw. mit `mittel`, `bad` nennt den Grund (roter Rand), `error` nennt die Kennung.
  `set` repariert es.
- Datei im Projektordner ohne `<KENNUNG>-<N> `-Praefix oder doppelte Kennung: Hinweis
  in `error`, die Datei wird nicht angefasst (doppelte werden beide angezeigt).
- Kaputtes Frontmatter (kein schliessendes `---`): Hinweis in `error`, Datei wird
  ignoriert und nie geschrieben.
- Schreiben atomar; Text unter dem Frontmatter wird nie veraendert (nur umbenannt/verschoben).
  Obsidian laedt extern geaenderte Dateien selbst neu.
- `watch` stirbt: Quickshell startet es nach 2 s neu.
- Fehlgeschlagener Aufruf aus dem Board: stderr in der Fehlerzeile, Karte springt
  mit dem naechsten Stand zurueck.

## Tests

- `ticket.py selftest` in einem temporaeren Vault:
  - `new` (Nummernvergabe, Vorlage angelegt), `list`, `show`, Suche ueber Alias.
  - WIP-Limit: viertes `in-arbeit` scheitert, Meldung nennt die drei.
  - `set project`: Datei verschoben, neue Kennung, alte in `aliases`.
  - `set title` mit `'`, `$()`, `/`, `:` und λ: sauberer Dateiname, Kennung bleibt.
  - `set labels`: verwaltete Tags bleiben, fremde ersetzt.
  - Fremde Properties, Kommentare und der Text bleiben byte-gleich nach jedem `set`.
  - Frontmatter mit Blocklisten (`tags:` + `  - a`) und Inline-Listen wird gelesen.
  - `quick`-Format (`PROJ:`, `#label`, `!prio`, ohne Projekt).
  - Ungueltiger Status -> `bad`; Datei ohne Kennung -> `error`.
  - `migrate` aus Beispiel-`data.json` + Missionsnotiz; zweiter Lauf bricht ab.
- Danach echte Migration und Sichtpruefung der 18 Dateien in `Tickets/WORK/`.
- Quickshell: nach `~/.config/quickshell/` deployen (Hot-Reload),
  `quickshell ipc call tickets open`, Screenshot per `grim -o <Monitor>`, ansehen;
  `quickshell log` ohne Fehler.
- `sway -C -c ~/.config/sway/config` nach der Bind-Aenderung.
- Bedienung, Drag & Drop und das Gefuehl der Animationen testet Osa selbst.

## Nicht-Ziele

Kein Typ (Bug/Task/Story), keine Faelligkeit, kein Verlauf, keine Kommentare,
keine manuelle Reihenfolge innerhalb einer Spalte, kein Bearbeiten des Notiztexts
im Board, keine Zwei-Wege-Synchronisation mit echtem Jira, kein JSON-Ausgabeformat
fuer `list`, keine Backups (Text wird nie umgeschrieben; Obsidian hat eigene
Dateiwiederherstellung).

## Version

Neuer Tag `HL2-v30` (Basis `HL2-v29`), in der Tag-Tabelle als "Aktueller Standard".
Tickets gelten als Standard-Bedienung fuer jedes neue Theme; ein Theme passt nur die
Farben oben in `shell.qml` an (gelten auch fuer das Board).
