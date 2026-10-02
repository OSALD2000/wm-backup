# wm-backup — Osas Sway-Desktop

Dieses Repo ist die **Quelle der Wahrheit** fuer den Window-Manager-Look auf dem
Laptop (Ubuntu, Sway unter Wayland, Login ueber GDM). Jedes Theme ist ein
Git-Tag. `~/.config` ist nur das Ziel, in das ein Tag deployt wird.

Remote: `github.com/OSALD2000/wm-backup` (Branch `master`).
Sprache in Commits und Kommentaren: Deutsch, Umlaute als ae/oe/ue.

## Komponenten und wohin sie deployt werden

| Repo-Pfad | Live-Pfad | Was |
|---|---|---|
| `sway/config` | `~/.config/sway/config` | Compositor, Keybinds, Workspaces, Farben (`set $hl2_*` …), Autostart |
| `sway/scripts/` | `~/.config/sway/scripts/` | `lock.sh` (hyprlock, sonst swaylock), `powermenu.sh` (rofi -dmenu), `clip.sh` (Zwischenablage, rofi ueber copyq), `screens.py` (Monitore anordnen, Laptop rechts), `ws.sh` (Super+N = Workspace N des aktuellen Monitors), `ipv6.sh` |
| `hypr/` | `~/.config/hypr/` | **nur hyprlock** (Sperrbildschirm) + `loading.sh` (Ladebalken). Hyprland selbst wird nicht benutzt |
| `waybar/` | `~/.config/waybar/` | obere Leiste (`config.jsonc`, `style.css`): Monitor-Badge U/I/O + Workspaces als `<Taste> <Icon>`, sichtbarer Workspace je Monitor hervorgehoben, `custom/wins` = Fensterzahl + Fensterliste offen/zu |
| `rofi/` | `~/.config/rofi/` | Launcher. Sway ruft `rofi -config ~/.config/rofi/config-nord.rasi` auf; der Name "nord" ist historisch, das aktive Theme steht per `@theme` darin (HL2: `hl2-menu.rasi`). `config.rasi` gehoert zu i3 |
| `eww/` | `~/.config/eww/` | Desktop-Widgets. HL2: `hud-left`/`hud-right` + Lern-Panel `learn` (Super+Z), Hilfe `info` (Super+Shift+Z), Fensterliste `sidebar` je Monitor. `scripts/learn.py` = Lern-Timer, Daten in `~/.local/share/learn-timer/`; `scripts/sidebar.py` = Watcher fuer die Fensterliste + Super+q/b + Vorschau-Raster Super+Tab + Stand fuer waybar `custom/wins` (`bar`) |
| `swaync/` | `~/.config/swaync/` | Benachrichtigungen (Popups als Pickups unten rechts) + Panel hinter der Glocke |
| `swaylock/` | `~/.config/swaylock/` | Fallback-Sperre |
| `alacritty/` | `~/.config/alacritty/` | Terminal. `alacritty.toml` importiert die Farbdatei (`hl2.toml`, `nord.toml`), `lambda.txt` = Begruessung |
| `wallpaper.jpg` | `~/Private/wallpaper.jpg` | von `output * bg` in der sway-Config benutzt |
| `browser/chrome-hl2-theme/` | `~/.config/chrome-hl2-theme/` | entpacktes Chrome-Theme (in Chrome ueber "Entpackte Erweiterung laden") |
| `browser/firefox/*.css` | `~/snap/firefox/common/.mozilla/firefox/h5d4ltr7.default/chrome/` | Firefox (Snap) userChrome/userContent |
| `browser/firefox/user.js` | `…/h5d4ltr7.default/user.js` | schaltet userChrome-Laden ein |

Die Zuordnung steht einmalig in `map()` in
`.claude/skills/theme-switch/scripts/theme.sh`. Kommt eine neue Komponente dazu,
nur dort eintragen.

Nicht im Repo, gehoert aber zum Setup: `~/.config/environment.d/50-wayland.conf`
(Wayland-Variablen), `~/.local/bin/shot-wl` (Screenshots),
`~/Private/shell_scripts/` (Lautstaerke-OSD), `~/.config/rofi/themes/` und
`~/.config/alacritty/themes/` (fremde Themes, per `.gitignore` draussen),
`~/.config/i3/` (alte i3-Session als Rollback: am GDM "i3" waehlen).

## Themes (Tags)

Format: `<Theme>-v<N>`. Tags werden **nie verschoben**; eine Nachbesserung ist
ein neuer Tag (`HL2-v2`). Alle Themes liegen linear auf `master`, Commits heissen
`<Theme>: <was>`.

| Tag | Look |
|---|---|
| `FirstSetup-v1` | warme Tan-Palette (`#A89B77` auf `#1C1A15`), eww-Fenster `desk`, rofi `spotlight-warm.rasi`, swaylock direkt |
| `HL2-v1` | Half-Life-2-HUD (2004): HUD-Gelb `#FFDC00` auf `#141310`, eww `hud-left`/`hud-right`, hyprlock "SUIT LOCKED" mit Ladebalken, rofi als HL2-Hauptmenue, λ ueberall |
| `HL2-v2` | wie v1, Hintergrund einheitlich `#141310`. Letzter Stand mit 12 globalen Workspaces |
| `HL2-v3` | Zwischenstand: 10 Workspaces je Monitor (u/i/o), tabbed, waybar-Taskbar unten (verworfen) |
| `HL2-v4` | **Standard-Bedienung** (siehe unten): Fensterliste links, Tab-Zeile unsichtbar, Super+q/b, Hilfe-Panel |
| `HL2-v5` | wie v4 + Vorschau-Raster (Super+Tab), Benachrichtigungen als HL2-Pickups, Zwischenablage im HL2-Menue (Super+Shift+V), Konsole als Scratchpad-Terminal (Super+^) |
| `HL2-v6` | wie v5, Konsole auf Super+Shift+Tab |
| `HL2-v7` | wie v6, waybar: Nummer vor jedem Workspace-Icon, aktueller Workspace auch auf Monitoren ohne Fokus hervorgehoben. |
| `HL2-v8` | wie v7, Pickup-Popups mit dunklerem, deckenderem Hintergrund (besser lesbar). |
| `HL2-v9` | wie v8, waybar links: Fensterzahl des sichtbaren Workspaces + Symbol Fensterliste offen/zu (`custom/wins`, Klick = Super+b). **Aktueller Standard** fuer neue Themes |

Welcher Tag gerade live ist: `theme.sh current` (steht in
`~/.local/state/wm-theme`; ohne die Datei gilt der Tag auf HEAD).

## Standard-Bedienung (gilt fuer jedes neue Theme)

Seit `HL2-v4` ist die Bedienung fest, ergaenzt in `HL2-v5` bis `HL2-v9` (Vorschau,
Zwischenablage, Konsole, Pickup-Popups, Workspace-Nummern und Fensterzahl in waybar). Alles in dieser Liste gilt fuer
**jedes** neue Theme, nicht nur fuer HL2: es aendert nur den **Look**
(Farben, Schrift, Formen), nicht Tasten, Workspace-Schema, Fensterliste oder
die Bausteine unten. Basis fuer ein neues Theme ist immer der neueste Standard-Tag.
Wer davon abweicht, fragt vorher.

- **Workspaces:** jeder Monitor hat eigene 1-10, gleiches Raster ueberall:
  1 Terminal, 2 Browser, 3 Code, 4 Code 2, 5 Trading, 6 frei, 7 Tools,
  8 Todos, 9 Chat, 10 Medien. Name `<nr>:<kuerzel><N>`: `u` = links (11-20),
  `i` = Mitte (21-30), `o` = Laptop (31-40). Kuerzel nach **Position** ueber
  die Fallback-Listen `$mon_l/$mon_m/$mon_r`, nicht nach Anschlussname.
  Die Nummer haelt die Sortierung, `ws.sh` rechnet daraus den Monitor zurueck.
- **Tasten:** `Super+N` / `Super+Shift+N` = Workspace N des aktuellen Monitors
  (hin / Fenster schieben). `Super+u/i/o` dann `Super+N` = Workspace N auf dem
  Monitor, mit Ctrl schieben (Sway-Modes, Escape bricht ab).
  `Super+q` / `Super+Ctrl+q` = naechstes / voriges Fenster der Liste links,
  bleibt auf dem Monitor. `Super+b` = Liste an/aus. `Super+Shift+z` = Hilfe.
  `Super+Tab` = alle Fenster aller Monitore als Vorschau-Raster (rofi; Bild =
  letzter sichtbarer Stand, sway kann verdeckte Fenster nicht abfotografieren).
- **Zwischenablage** (`Super+Shift+V`, `sway/scripts/clip.sh`): copyq speichert
  (laeuft per `exec_always`), rofi zeigt den Verlauf im Menue-Stil des Themes,
  Enter = `copyq select`, also wieder in die Zwischenablage. Kein eigenes
  copyq-Fenster.
- **Konsole** (`Super+Shift+Tab`): Alacritty mit app_id
  `scratch-term` im Scratchpad, schwebend 70x55 % mittig. Erster Druck
  startet es, danach ein/aus (`for_window`-Regel + Bind in der sway-Config).
- **Benachrichtigungen** (swaync): Popups im Stil der Pickup-Meldungen des
  Themes, unten rechts ueber dem rechten HUD-Kasten (`positionY bottom`,
  `.floating-notifications` mit `margin-bottom` = HUD-Hoehe), 5 s, schmal.
  Das Panel hinter der Glocke (`Super+n`) ist davon getrennt gestylt.
- **Vorschau-Raster** (`Super+Tab`, `sidebar.py overview`): alle Fenster aller
  Monitore als Kacheln (rofi, 5 je Reihe), Beschriftung `<Kuerzel> <Bereich>`
  + App. Bilder macht der Watcher in `snap()`, solange ein Fenster sichtbar ist
  (`$XDG_RUNTIME_DIR/win-shots`, nicht bei Sperre).
- **Assigns:** VS Code `23:i3`, IntelliJ `24:i4`, KeePassXC `37:o7`, To Do
  `38:o8`, Teams `39:o9`, YouTube `40:o10`.
- **Fenster:** `workspace_layout tabbed`, Tab-Zeile per Schrift 1 + leerem
  `title_format` + Titelbar-Farben = Hintergrund auf ~3px geschrumpft (ganz weg
  geht in Sway nicht). Kein `Super+s` (stacking). Rahmen nur ueber `child_border`.
- **Fensterliste links** (eww `sidebar`, 58px): Icon + App-Name je Fenster des
  sichtbaren Workspaces, erst ab 2 Fenstern, Klick fokussiert, Mittelklick
  schliesst. Ebene `bottom`, damit waybar (Ebene top) immer volle Breite hat.
- **Hilfe-Panel** (eww `info`, `?` neben AMMO): Matrix Monitor x Nummer +
  alle Shortcuts. **Statisch**: bei neuen Binds oder Assigns mitziehen.
- **waybar oben:** Badge U/I/O (`custom/monitor`) + je Workspace `<Taste> <Icon>`
  (`1` … `9`, `0` fuer 10, wie Super+N; steht in `format-icons`). Der sichtbare
  Workspace jedes Monitors ist gleich hervorgehoben wie der fokussierte
  (`button.visible, button.focused` in `style.css`), damit jede Bar zeigt, was
  auf ihrem Monitor gerade offen ist. Daneben `custom/wins` (`sidebar.py bar`):
  Zahl der Fenster im sichtbaren Workspace + Symbol der Fensterliste
  (Spalten = offen, gedimmt = erst ab 2 Fenstern, Vollbild = per Super+b aus),
  Klick schaltet die Liste. Der Watcher schreibt den Stand nach
  `$XDG_RUNTIME_DIR/eww-sidebar.bar` und weckt waybar per `SIGRTMIN+9`.
  `sway/scratchpad` (≡ N) zaehlt die Fenster im Scratchpad, also die Konsole.

Ein neues Theme uebernimmt `ws.sh`, `sidebar.py`, `clip.sh`, die
`format-icons` der waybar (Nummer vor dem Icon) und das Modul `custom/wins`, die
Workspace-/Bind-Bloecke und die `scratch-term`-Regel der sway-Config, die
eww-Fenster `sidebar`/`info` und Lage/Timeout der swaync-Popups
(`swaync/config.json`) und passt nur Farben und Schrift an: `eww.scss`,
waybar `style.css`, den Popup-Block in `swaync/style.css` und die
`-theme-str`-Teile in `clip.sh` / `sidebar.py overview` (die rofi-Theme-Datei
liefert den Rest). In `style.css` muss `button.visible` dieselbe
Hervorhebung bekommen wie `button.focused`; `#custom-wins` mit den Klassen
`open`/`idle`/`off` umfaerben.

**Allgemeine Aenderungen** (Bedienung, Bausteine, Verhalten, nicht nur Farben)
gelten ab dann fuer jedes Theme: hier unter Standard-Bedienung eintragen, im
Skill `theme-erstellen` die Liste der Bausteine nachziehen, neuen Tag anlegen
und ihn in der Tabelle als "Aktueller Standard" markieren.

## Aeltere Themes

Noch aelter und ohne Tag: eine Nord-Palette aus der i3-Zeit. Reste davon sind
`set $nord*` in der sway-Config, `alacritty/nord.toml` und der Dateiname
`config-nord.rasi`.

## Werkzeug

```sh
S=.claude/skills/theme-switch/scripts/theme.sh
$S list                  # Tags, * = deployt
$S status                # weicht live vom deployten Stand ab?
$S switch HL2-v1 -n      # Probelauf
$S switch HL2-v1         # deployen + neu laden
$S sync-back             # live -> Repo (beim Bauen eines Themes)
```

`switch` kopiert per rsync **ohne --delete**: Dateien, die der Ziel-Tag nicht
kennt, bleiben liegen und stoeren nicht. Bei ungesicherten Live-Aenderungen
bricht es ab (`-f` ueberschreibt). Neu geladen wird mit `swaymsg reload`, das
waybar, swaync, screens.py und `sidebar.py watch` (startet eww) ueber
`exec_always` neu startet. eww wird vor dem Reload beendet; aeltere Tags, die
eww per `exec … eww open` starten, bekommen diese Zeile danach nachgereicht.
swayidle (traegt den Lock-Befehl) wird mit seiner `exec`-Zeile neu gestartet.
Firefox und Chrome brauchen einen Neustart.

Skills: `theme-erstellen` (neues Theme bauen und taggen), `theme-switch`
(zwischen Tags wechseln).

## Stolperfallen

- Jeder `~/.config/<komponente>`-Ordner hat noch ein **eigenes altes Git-Repo**
  (Tag `pre-hl2`, "Phase N"-Commits vom HL2-Umbau). Diese Repos werden nicht
  mehr gepflegt; nach einem Switch zeigen sie Diffs. Das ist normal.
- `exec` vs. `exec_always` in der sway-Config: nur `exec_always` laeuft bei
  `swaymsg reload` erneut. waybar/swaync haben deshalb `pkill` davor, sonst
  laufen sie doppelt.
- Sperren immer ueber `sway/scripts/lock.sh`, nie hyprlock direkt: lock.sh
  schreibt den Startzeitpunkt fuer den Ladebalken und faellt auf swaylock
  zurueck.
- `learn.py stop` steht vor jedem Lock/Exit/Idle, damit der Lern-Timer nicht
  weiterzaehlt. Beim Aendern von Keybinds erhalten.
- Mod-Taste ist Super; Richtungen `j k l ö` (i3-Stil), Caps = Escape, Layout `de`.
- `workspace_layout tabbed` gilt nur fuer **neu angelegte** Workspaces. Alte
  (oder nach `Super+h/v/e`) oeffnen Apps wieder nebeneinander: `Super+w`.
- eww nie mehrfach gleichzeitig starten: zwei Starts = zwei Daemons, einer
  verliert den Socket und zeigt seine Fenster weiter an (doppelte Sidebar),
  `eww kill` erreicht ihn nicht. Deshalb startet nur `sidebar.py watch` eww,
  vorher `pkill -x eww`. Der Watcher ersetzt sich per PID-Datei
  (`$XDG_RUNTIME_DIR/eww-sidebar.pid`), nicht per `pkill -f` (das traefe die
  `sh -c`-Zeile von sway selbst).
- Aus Python eww/Daemons starten: `stdout=DEVNULL`, nie `capture_output` —
  der Daemon erbt die Pipe und der Aufruf haengt fuer immer.
- waybar `wlr/taskbar` taugt unter Sway nicht: Fenster hinter Tabs fehlen.
- Nach Aenderungen an sway: `swaymsg reload` (Super+Shift+C). Syntax pruefen
  mit `sway -C -c ~/.config/sway/config`.
