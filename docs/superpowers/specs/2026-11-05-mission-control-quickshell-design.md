# Mission Control in Quickshell (Super+m)

Stand: 2026-11-05. Ersetzt das eww-Fenster `mission` durch ein animiertes
Quickshell-Panel. Daten und Regeln bleiben in `eww/scripts/todo.py`.

## Ziel

Mission Control soll sich lebendig anfuehlen statt statisch: viele kleine
Animationen bei jedem Zustandswechsel, Bedienung per Tastatur und Maus,
Eingabe direkt im Panel statt rofi. Der Look folgt der Quickshell-Fensterliste
und dem Workspace-Raster (Federn, Gluehen, Ploppen, HL2-Farben).

## Entscheidungen (mit Osa abgestimmt)

- Stil: **lebendiges Panel rechts** (Lage wie bisher), keine Vollbild-Missionsziele.
- Bedienung: **Tastatur + Maus, Eingabe inline**. Das Panel nimmt beim Oeffnen
  die Tastatur exklusiv.
- Daten: Quickshell startet `todo.py watch` und liest dessen JSON-Zeilen.
  Keine zweite Implementierung von Gruppen/Fokuslimit in JavaScript.
- Mikroanimationen ausdruecklich erwuenscht ("mehr micro animation").

## Aufbau

| Datei | Aenderung |
|---|---|
| `quickshell/Missions.qml` | neu: komplettes Panel (Fenster, Daten, Tasten, Animationen) |
| `quickshell/shell.qml` | `Missions { shell: root }` einbinden; Farben bleiben oben in `shell.qml` |
| `eww/scripts/todo.py` | `add TEXT`, `edit ID TEXT`; rofi-Teile (`new`, `prompt()`) entfallen |
| `eww/eww.yuck` | `deflisten missions`, `defvar mission_tab`, `mission-row`, `mission-list`, `defwindow mission` raus |
| `eww/eww.scss` | nur von Mission Control benutzte `.ms-*`-Regeln raus (Journal/Agenten nutzen `.mission`, `.ms-head`, `.ms-lambda`, `.ms-title`, `.ms-subtitle`, `.ms-tabs`, `.ms-tab`, `.ms-action`, `.ms-add`, `.ms-error` weiter; vor dem Loeschen per grep pruefen) |
| `sway/config` | `$mod+m` -> `quickshell ipc call missions toggle` |
| `CLAUDE.md` = `AGENTS.md`, `theme-erstellen`-Skill (beide Kopien) | Mission Control, Komponenten-Tabelle, Bausteinliste |

`theme.sh` deployt `quickshell/` als ganzen Ordner, `Missions.qml` braucht
keinen neuen Eintrag in `map()`.

## Datenfluss

1. `Missions.qml` haelt einen `Process { command: [todo.py, "watch"]; running: true }`
   mit `stdout: SplitParser`. Jede Zeile = kompletter Stand
   `{open, done, focus, archived, progress, groups[4], error}` (wie bisher fuer eww).
   Laeuft dauerhaft, damit beim Oeffnen sofort Daten da sind.
2. Die Liste eines Reiters ist `ScriptModel { values: state.groups[tab]; objectProp: "id" }`,
   damit Add/Remove/Displaced-Transitions greifen, wenn sich die Daten aendern.
3. Aktionen per `Quickshell.execDetached([todo.py, cmd, id, ...])`: Argument-Array,
   keine Shell. Freitext (`add`, `edit`) geht als eigenes Argument, `'`/`$()` sind harmlos.
4. `todo.py` bleibt die Autoritaet: Fokuslimit, Validierung, atomares Speichern,
   Tagesbackups, Archiv statt Loeschen, Obsidian-Notiz (`note ID`) unveraendert.

### todo.py

- `add [TEXT]`: Text aus dem Argument, sonst aus stdin (`Super+Ctrl+m` per `ask.sh` bleibt).
- `edit ID TEXT`: setzt den Text unter Lock. Leerer Text = nichts tun.
- `new` und die rofi-Variante von `edit` entfallen (nur das eww-Panel hat sie benutzt),
  ebenso `prompt()`. Docstring und `selftest` nachziehen.

## Fenster und Oeffnen

- `IpcHandler { target: "missions" }` mit `toggle()`, `open()`, `close()`.
  Beim Oeffnen wird der Monitor aus `I3.focusedMonitor.name` festgehalten
  (Fenster bleibt auf diesem Monitor, bis es zu ist).
- `PanelWindow` wie das Workspace-Raster: Ebene Overlay, alle Kanten verankert,
  `exclusionMode: Ignore`, `keyboardFocus: Exclusive`, Namespace `missions`.
- Darin: Abdunkelung (Alpha ~0.35) mit MouseArea = Klick daneben schliesst.
  Das Panel selbst: rechts, 24px Rand, 560px breit, 80 % Bildschirmhoehe,
  vertikal mittig mit 15px Ausgleich fuer die 30px-Waybar (wie bisher).
- Schliessen: Esc, `Super+m` (sway-Bind feuert auch bei exklusivem Fokus), Klick daneben, ✕.
- Laufende Endlos-Animationen (Atmen, Glanzlicht, Funkeln, Schweben) nur
  `running: open`.

## Inhalt des Panels

Von oben nach unten:

1. **Kopf:** λ, Titel `MISSION CONTROL`, Untertitel, ✕.
2. **Status:** `N offen · M erledigt` (rollende Zaehler), Fortschrittsbalken,
   Fokus als drei Punkte `●●○`.
3. **Reiter:** Jetzt / Offen / Erledigt / Archiv, je mit Zahl-Badge.
4. **Eingabefeld** (nur bei Neu): klappt hier auf.
5. **Liste** der Karten des Reiters (scrollbar). Karte: Kreis/Haken, Text
   (umbrechend), Aktionsknoepfe Fokus / Bearbeiten / Notiz / Archiv bzw. Zurueckholen.
   Knoepfe nur bei Hover oder Auswahl sichtbar.
6. **Leerer Reiter:** Symbol + Text wie bisher (je Reiter eigener Text).
7. **Fehlerzeile** aus `state.error`.
8. **Fuss:** `+ Neue Mission` und eine Zeile mit den Tasten.

## Tasten

| Taste | Wirkung |
|---|---|
| `j` / `k`, `↓` / `↑` | Karte waehlen |
| `Leertaste` | erledigen / wieder oeffnen |
| `f` | Fokus an/aus |
| `e`, `Enter` | bearbeiten (inline) |
| `n` | neue Mission (inline) |
| `a` | archivieren / zurueckholen |
| `o` | Obsidian-Notiz |
| `1`-`4`, `Tab` / `Shift+Tab`, `h` / `l` | Reiter |
| `Esc` | schliessen (im Eingabefeld: abbrechen) |

Im Eingabefeld: `Enter` = speichern (leer = abbrechen), `Esc` = abbrechen.
Die Auswahl je Reiter wird auf die Listenlaenge begrenzt, wenn Karten verschwinden.
Maus: Hover = Auswahl, Klick auf Kreis/Knoepfe wie bisher.

## Animationen

Dauer-Richtwerte; Federn wie in der Fensterliste (`SpringAnimation`, spring 4-5, damping 0.25-0.32).

**Oeffnen / Schliessen**
- Panel faehrt von rechts ein (OutBack, ~380 ms), Abdunkelung blendet ein.
- Eine helle Scanline laeuft einmal von oben nach unten ueber das Panel (~600 ms).
- Kopf, Status, Reiter, dann Karten gestaffelt (je 35 ms versetzt, von rechts + Einblenden).
- λ leuchtet beim Oeffnen auf, danach atmet sein Gluehen (wie `breathe` der Fensterliste).
- Schliessen: Karten schnell rueckwaerts raus, Panel faehrt raus (InBack, ~220 ms),
  erst danach wird das Fenster unsichtbar.

**Kopf / Status**
- Zaehler rollen zur neuen Zahl (`NumberAnimation` auf angezeigtem Wert) + kurzer Puls.
- Fortschrittsbalken federt auf neue Breite; alle ~4 s laeuft ein Glanzlicht darueber;
  bei 100 % leuchtet er einmal auf.
- Fokus-Punkte ploppen rein/raus. Vierter Fokus versucht: Punkte wackeln (Shake ~300 ms)
  + Hinweis "Drei reichen fuer jetzt" blendet kurz ein; `todo.py` wird dann nicht gerufen.

**Reiter**
- Markierung gleitet federnd und streckt sich dabei (Breite folgt mit Verzoegerung).
- Badge huepft, wenn sich seine Zahl aendert.
- Reiterwechsel: Liste gleitet in Richtung des Wechsels raus und rein, Karten gestaffelt.

**Karten**
- Rein: Ploppen (scale 0.9 -> 1, OutBack) + Einblenden.
- Hover: leicht anheben (scale 1.02, Schatten waechst), Rand hellt auf,
  Aktionsknoepfe gleiten von rechts rein.
- Auswahl: leuchtender Rahmen gleitet federnd zur Karte und passt seine Hoehe an.
- Fokus-Karten: Akzentstrich links atmet, Stern funkelt ab und zu.
- Knopfdruck: eindruecken (scale 0.9) und zurueckfedern.

**Aktionen**
- Erledigen: Kreis fuellt sich, Haken zeichnet sich (`QtQuick.Shapes`, Strichlaenge animiert),
  Durchstreichlinie waechst ueber den Text, ~8 Funken spruehen aus dem Haken.
  Erst nach der Animation (~600 ms) `todo.py done`; dann gleitet die Karte
  nach rechts raus, Rest rueckt federnd nach, Badge "Erledigt" huepft.
- Wieder oeffnen: Haken loest sich rueckwaerts auf, dann `todo.py done`.
- Fokus: Stern ploppt gross auf und dreht sich, Lichtring breitet sich aus.
- Archivieren / Zurueckholen: Karte klappt zusammen (Hoehe -> 0), Badge "Archiv" huepft.
- Neu: Eingabefeld klappt federnd auf (Cursor blinkt); Enter -> Feld klappt zu,
  neue Karte ploppt mit kurzem Gluehen in die Liste.
- Bearbeiten: Kartentext blendet in ein Eingabefeld ueber; Enter -> kurzes Aufblitzen.
- Notiz: Pfeil ↗ schiesst kurz nach rechts oben und kommt zurueck.
- Fehler: Fehlerzeile schuettelt sich, pulsiert rot, blendet nach 4 s aus.
- Leerer Reiter: Symbol schwebt sanft, Ring pulsiert darum.

## Fehlerbehandlung

- `todo.py`-Fehler (Datei kaputt, Fokuslimit, nicht gefunden): wie bisher `notify-send`
  + `error` im naechsten `watch`-Stand -> Fehlerzeile im Panel.
- Endet `todo.py watch` unerwartet: Prozess nach 2 s neu starten (`onExited` -> Timer).
- Optimistische Animationen (Haken, Archiv) laufen vor dem Aufruf. Kommt der neue
  Stand nicht, zeigt die Liste nach dem naechsten `watch`-Stand wieder die Wahrheit.

## Tests

- `todo.py selftest` erweitert: `add` mit Argument (Sonderzeichen `'`, `$()`, λ),
  `edit ID TEXT`, leerer Text aendert nichts.
- Quickshell: Dateien nach `~/.config/quickshell/` deployen (Hot-Reload),
  `quickshell ipc call missions open`, Screenshot per `grim -o <Monitor>`, ansehen;
  `quickshell log` ohne Fehler. Reiterwechsel/Auswahl per `ipc` bzw. Tasten pruefen.
- Bedienung und Gefuehl testet Osa am Ende selbst.

## Nicht-Ziele

Kein Sortieren per Drag&Drop, keine Unteraufgaben, keine Datenmigration,
kein Sound, keine Aenderung am Journal-Panel.

## Offen

HL2-v29 (Quickshell-Workspace-Raster) ist noch nicht committet/getaggt. Ohne
Ansage von Osa wird von v29 nichts committet; Mission Control baut auf dem
Arbeitsbaum auf. Tag (voraussichtlich `HL2-v30`) erst, wenn v29 geklaert ist.
