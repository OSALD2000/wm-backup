# wm-backup — Osas Sway-Desktop

Dieses Repo ist die **Quelle der Wahrheit** fuer den Window-Manager-Look auf dem
Laptop (Ubuntu, Sway unter Wayland, Login ueber GDM). Jedes Theme ist ein
Git-Tag. `~/.config` ist nur das Ziel, in das ein Tag deployt wird.

Remote: `github.com/OSALD2000/wm-backup` (Branch `master`).
Sprache in Commits und Kommentaren: Deutsch, Umlaute als ae/oe/ue.

## Codex und Claude Code

Codex liest `AGENTS.md` und die Skills unter `.agents/skills/`;
Claude Code liest `CLAUDE.md` und `.claude/skills/`.
Beide Anleitungsdateien bleiben identisch. Die Skill-Kopien unterscheiden
sich nur durch den jeweiligen Anleitungsnamen und Werkzeugpfad.
Codex verwendet `S=.agents/skills/theme-switch/scripts/theme.sh`;
die unten gezeigte Claude-Variante bietet dieselben Befehle.
Aenderungen an `theme.sh` immer in beiden Kopien nachziehen.

## Komponenten und wohin sie deployt werden

| Repo-Pfad | Live-Pfad | Was |
|---|---|---|
| `sway/config` | `~/.config/sway/config` | Compositor, Keybinds, Workspaces, Farben (`set $hl2_*` …), Autostart |
| `sway/scripts/` | `~/.config/sway/scripts/` | `lock.sh` (hyprlock, sonst swaylock), `powermenu.sh` (rofi -dmenu), `clip.sh` (Zwischenablage, rofi ueber copyq), `screens.py` (Monitore anordnen, Laptop rechts), `ws.sh` (Super+N = Workspace N des aktuellen Monitors), `console.py` (Konsole Super+Shift+Tab), `market.py` (waybar `custom/market`: NY-Zeit + Session), `journal.py` (Trading-Journal), `note.py` (Schnellnotiz Obsidian), `park.py` (Session parken), `ask.sh` (rofi-Eingabezeile, mit `-` Auswahlliste), `ipv6.sh`, `ticket.py` (Tickets als Markdown im Vault, einzige Schreibstelle, CLI fuer Board und Agenten) |
| `hypr/` | `~/.config/hypr/` | **nur hyprlock** (Sperrbildschirm) + `loading.sh` (Ladebalken). Hyprland selbst wird nicht benutzt |
| `waybar/` | `~/.config/waybar/` | obere Leiste (`config.jsonc`, `style.css`): Monitor-Badge A/S/D + Workspaces als `<Taste> <Icon>`, sichtbarer Workspace je Monitor hervorgehoben, `custom/agents` = Claude/Codex-Status |
| `rofi/` | `~/.config/rofi/` | Launcher. Sway ruft `rofi -config ~/.config/rofi/config-nord.rasi` auf; der Name "nord" ist historisch, das aktive Theme steht per `@theme` darin (HL2: `hl2-menu.rasi`). `config.rasi` gehoert zu i3 |
| `eww/` | `~/.config/eww/` | Desktop-Widgets. HL2: `hud-left`/`hud-right` + Lern-Panel `learn` (Super+Z), Hilfe `info` (Super+Shift+Z), Trading-Journal `journal` (Super+Ctrl+j, Formular von `sway/scripts/journal.py`). `scripts/learn.py` = Lern-Timer, Daten in `~/.local/share/learn-timer/`; `scripts/sidebar.py` = Watcher fuer die Befehlsleiste (schreibt `$XDG_RUNTIME_DIR/sidebar.json`, startet Quickshell) + Super+q + Workspace hin/verschieben (`workspaces apply`) + Bilder fuer das Vorschau-Raster Super+Tab (`snap()`); `scripts/agents.py` = Agenten-Panel `agents` (Super+c) + Tafel `agents-board` (Super+g) + waybar `custom/agents` |
| `swaync/` | `~/.config/swaync/` | Benachrichtigungen (Popups als Pickups unten rechts) + Panel hinter der Glocke |
| `swaylock/` | `~/.config/swaylock/` | Fallback-Sperre |
| `alacritty/` | `~/.config/alacritty/` | Terminal. `alacritty.toml` importiert die Farbdatei (`hl2.toml`, `nord.toml`), `lambda.txt` = Begruessung |
| `cool-retro-term/` | `~/.config/cool-retro-term/` | Look der Konsole: `profile.json` (Farben, CRT-Effekte, Schrift), traegt `console.py` vor jedem Start ein |
| `quickshell/` | `~/.config/quickshell/` | `shell.qml` = Farben + Stand aus `sidebar.json`. Befehlsleiste unter der waybar (`CommandBar.qml`, je Monitor: Tabs links, Kommandozeile rechts, Super+f) mit Decodierung `nav.js` und Befehlen in `commands/` (`commands.json` + Skripte). Ausserdem das Ticket-Board Super+m (`Tickets.qml` + `TicketCard.qml`, `TicketDetail.qml`, gemeinsamer Knopf `Chip.qml`) und das Vorschau-Raster Super+Tab (`Overview.qml`). Binary `~/.local/bin/quickshell` selbst gebaut (siehe Stolperfallen) |
| `wallpaper.jpg` | `~/Private/wallpaper.jpg` | von `output * bg` in der sway-Config benutzt |
| `browser/chrome-hl2-theme/` | `~/.config/chrome-hl2-theme/` | entpacktes Chrome-Theme (in Chrome ueber "Entpackte Erweiterung laden") |
| `browser/firefox/*.css` | `~/snap/firefox/common/.mozilla/firefox/h5d4ltr7.default/chrome/` | Firefox (Snap) userChrome/userContent |
| `browser/firefox/user.js` | `…/h5d4ltr7.default/user.js` | schaltet userChrome-Laden ein |

Die Zuordnung steht einmalig in `map()` in
`.claude/skills/theme-switch/scripts/theme.sh`. Kommt eine neue Komponente dazu,
nur dort eintragen.

Nicht im Repo, gehoert aber zum Setup: `~/.config/environment.d/50-wayland.conf`
(Wayland-Variablen), `~/.local/bin/shot-wl` (Screenshots), Pakete `tesseract-ocr` +
`tesseract-ocr-deu` (OCR auf Super+Print),
`~/Private/obsidian-vault/` (Obsidian-Vault fuer Trading-Journal, Schnellnotiz und Tickets (`Tickets/<PROJEKT>/`); bis HL2-v28 `~/Documents/Obsidian Vault`),
`~/Private/shell_scripts/` (Lautstaerke-OSD), `~/.local/bin/ticket` (Symlink auf `sway/scripts/ticket.py`), Hinweiszeilen zu `ticket` in `~/.claude/CLAUDE.md` und `~/.codex/AGENTS.md`, `~/.config/rofi/themes/` und
`~/.config/alacritty/themes/` (fremde Themes, per `.gitignore` draussen),
`~/.config/i3/` (alte i3-Session als Rollback: am GDM "i3" waehlen).

## Terminal-Navigation (zsh)

Nicht im Repo, steht in `~/.zshrc` (oh-my-zsh): Pakete `zoxide` + `fzf`,
`plugins=(… fzf)` und **nach** `source $ZSH/oh-my-zsh.sh`
`eval "$(zoxide init zsh --cmd cd)"`. Kein oh-my-zsh-Plugin `zoxide` dazu,
das wuerde zoxide doppelt laden (als `z`).

- `cd <stichwort>` springt in den meistbesuchten passenden Ordner
  (`cd wm` -> `~/Private/wm-backup`), Ordner muss einmal normal besucht sein.
  `cdi` = Auswahl per fzf, `cd -` = zurueck, echte Pfade gehen wie immer.
- `Ctrl+R` = Verlauf durchsuchen, `Ctrl+T` = Datei in die Zeile einfuegen,
  `Alt+C` = Unterordner suchen und hinein.
- oh-my-zsh: `..` / `...` = hoch, `d` = letzte Ordner, `1`-`9` = dorthin.

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
| `HL2-v9` | wie v8, waybar links: Fensterzahl des sichtbaren Workspaces + Symbol Fensterliste offen/zu (`custom/wins`, Klick = Super+b). |
| `HL2-v10` | wie v9, Hilfe-Panel nennt den Klick auf die Fensterzahl. |
| `HL2-v11` | wie v10, Konsole ist cool-retro-term mit HL2-Profil (Gelb auf `#141310`, leichte CRT-Effekte). |
| `HL2-v12` | wie v11, Vorschau-Raster (Super+Tab) als eww-Fenster mit ✕ (Fenster schliessen) / ⏻ (App beenden) je Kachel, Missionen-Panel im Stil der HL2-Missionsziele (Todo-Liste, Super+m). |
| `HL2-v13` | wie v12, Vorschau-Raster (Super+Tab) wieder als rofi-Raster wie bis v11 (eww-Raster mit ✕/⏻ raus), Missionen bleiben. |
| `HL2-v14` | wie v13, im Vorschau-Raster schliesst Entf das gewaehlte Fenster, das Raster geht danach wieder auf. |
| `HL2-v15` | wie v14, Monitor-Kuerzel nach Anzahl Schirme (1: o, 2: o+i, 3: o+i+u), Workspaces fehlender Kuerzel werden eingeklappt. |
| `HL2-v16` | wie v15, Super+u/i/o-Modes raus: Ziel-Monitor in waybar (`custom/target`, `→ U/I/O`), Super+Esc schaltet weiter, Super+Ctrl+N / Super+Ctrl+Shift+N = Workspace N dort / Fenster dorthin. |
| `HL2-v17` | wie v16, Super+Print = OCR: Text aus einem Bereich in die Zwischenablage (tesseract deu+eng). |
| `HL2-v18` | wie v17, Boersenuhr in waybar (NY-Zeit + ICT-Session), Trading-Journal nach Obsidian (Super+Ctrl+j), Mission-Schnelleingabe (Super+Ctrl+m), kein Sperren bei sichtbarem TradingView, Nachtlicht (wlsunset), Workspaces mit fremdem Kuerzel nach dem Login werden umbenannt. |
| `HL2-v19` | wie v18, Schnellnotiz in Obsidian (Super+Ctrl+n): Name eintippen, Notiz aus Vorlage anlegen und oeffnen. |
| `HL2-v20` | wie v19, ohne Nachtlicht (wlsunset raus). |
| `HL2-v21` | wie v20, Agenten-Panel (Super+c): laufende Claude-Code-/Codex-Sessions mit Status + Verlauf, Agenten-Tafel mit den Chats live nebeneinander (Super+g), waybar `custom/agents`, Meldung wenn ein Agent fertig ist. |
| `HL2-v22` | wie v21, Session parken: Super+Ctrl+p schiebt alle Fenster unter einem Namen auf o6, Super+Ctrl+Shift+p holt eine Session zurueck an die alten Plaetze. |
| `HL2-v23` | wie v22, Mausrad kippen rechts/links = naechstes/voriges Fenster der Liste (wie Super+q / Super+Ctrl+q), mit Super = Workspace des Monitors weiter/zurueck. |
| `HL2-v24` | wie v23, Mission Control mit Fokus (max. 3), Offen/Erledigt/Archiv, Bearbeiten und eigenen Obsidian-Notizen; Archiv statt Loeschen, dezente UI-Uebergaenge, stabile Workspace-Breiten, IPv6-Anzeige entfernt. |
| `HL2-v25` | wie v24, Mission Control mit 80 % Bildschirmhoehe und je 10 % Abstand oben/unten. |
| `HL2-v26` | wie v25, Trading-Journal als eww-Formular (Super+Ctrl+j): eine Datei je Setup unter `journaling/{live-trades,backtesting}/JJJJ/MM/TT/`, Model/Symbol/Long-Short/Session/Timeframe/Ergebnis/R im Frontmatter + Tags, weitere Screenshots ans letzte Setup, Altes in `legacy/`. |
| `HL2-v27` | wie v26, Workspace-Raster (Super+u wechseln, Super+Shift+u verschieben): eine Zeile je Bildschirm, zehn Felder, Maus/hjkl/Pfeile, letztes Ziel je Aktion gespeichert. |
| `HL2-v28` | wie v27, Fensterliste links mit Quickshell statt eww: animiert (einfahren, Eintraege ploppen rein/raus, leuchtende Markierung gleitet federnd zum aktiven Fenster, Icon huepft), Look wie die waybar-Workspaces, Fenstertitel als Popout. |
| `HL2-v29` | wie v28, Workspace-Raster (Super+u / Super+Shift+u) als Quickshell-Overlay: live mit App-Icons je Feld, Eingabefeld je Bildschirm fuer die Nummer, Tab = Wechseln/Verschieben, Klick auf Icon springt zum Fenster; Super+j / Super+k = Bildschirm links / rechts; Obsidian-Vault jetzt `~/Private/obsidian-vault`. |
| `HL2-v30` | wie v29, Ticket-Board statt Mission Control: Tickets als Markdown im Obsidian-Vault (`Tickets/<PROJEKT>/`), Board mit Backlog/ToDo/In Arbeit/Review/Fertig in Quickshell (Super+m), Prio, Labels, Detail-Popup, Drag & Drop, Loeschen in den Obsidian-Papierkorb, CLI `ticket` fuer Agenten; Vorschau-Raster (Super+Tab) als animiertes Quickshell-Overlay mit Filter. |
| `HL2-v31`-`v33` | verworfener Versuch (Navigation, Fensterleiste unten, Fokus-Karte), nur lokal am Branch `backup/vor-ruecksetzung-20261115-111324`, nicht auf `master` |
| `HL2-v34` | wie v30, Navigator (Super+f) statt Workspace-Raster und Ziel-Monitor: Bildschirm, Workspace und Fenster per Buchstabencode (`[m] [b+a/s/d] [w+a…ö] [Fenster]`), Kuerzel A/S/D statt U/I/O, Vollbild auf Super+Ctrl+f, Super+Kippen raus, Trainer `tools/nav-trainer.html`. |
| `HL2-v35` | wie v34, Befehlsleiste unter der waybar statt Fensterliste links und Navigator-Overlay: Tabs des Workspaces mit Code links, Kommandozeile rechts (Super+f), Befehle `:all` (Baum mit Befehl je App) und `:clear`, neue Befehle per `commands/commands.json` + Skript; Super+b und `custom/wins` raus. |
| `HL2-v36` | wie v35, Befehle mit `#` statt `:` (`#all`, `#clear`; `#` ohne Shift). |
| `HL2-v37` | wie v36, mehr Befehle: `#split` (alle / `a,s` als geteilter Tab / `> ziel`), `#reset`, `#close`, `#only`, `#full`, `#back`, `#open`, `#park`/`#unpark`, `#note`, `#ticket`; geteilte Tabs unterstrichen; Befehls-Skripte bekommen `BAR_CONTEXT`. |
| `HL2-v38` | wie v37, Tab / Shift+Tab ergaenzt Befehlsnamen in der Befehlsleiste. |
| `HL2-v39` | wie v38, Claude-/Codex-Sessions in der Befehlsleiste als `✳ Claude` / `◎ Codex` mit Session-Titel und Status (aus `agents.json`), `#all text` sucht im Baum. |
| `HL2-v40` | wie v39, Caps Lock ist zweite Super-Taste statt Escape (`xkb_options caps:super`). |
| `HL2-v41` | wie v40, Befehlsleiste ohne `b`/`w`: `[m] [Bildschirm] [Workspace] Fenster` mit Leerzeichen, von rechts gelesen, Ausfuehren mit Enter (`a s aa`, `f `, `m a f`); Ziele `> a j`. **Aktueller Standard** fuer neue Themes |

Welcher Tag gerade live ist: `theme.sh current` (steht in
`~/.local/state/wm-theme`; ohne die Datei gilt der Tag auf HEAD).

## Standard-Bedienung (gilt fuer jedes neue Theme)

Seit `HL2-v4` ist die Bedienung fest, ergaenzt in `HL2-v5` bis `HL2-v41` (Vorschau,
Zwischenablage, Konsole, Pickup-Popups, Workspace-Nummern und Fensterzahl in waybar,
Ticket-Board, Navigator, Befehlsleiste). Alles in dieser Liste gilt fuer
**jedes** neue Theme, nicht nur fuer HL2: es aendert nur den **Look**
(Farben, Schrift, Formen), nicht Tasten, Workspace-Schema, Befehlsleiste oder
die Bausteine unten. Basis fuer ein neues Theme ist immer der neueste Standard-Tag.
Wer davon abweicht, fragt vorher.

- **Workspaces:** jeder Monitor hat eigene 1-10, gleiches Raster ueberall:
  1 Terminal, 2 Browser, 3 Code, 4 Code 2, 5 Trading, 6 frei, 7 Tools,
  8 Todos, 9 Chat, 10 Medien. Name `<nr>:<kuerzel><N>`: `a` = links (11-20),
  `s` = Mitte (21-30), `d` = Laptop (31-40) (bis HL2-v30 `u`/`i`/`o`). Kuerzel nach **Position** ueber
  die Fallback-Listen `$mon_l/$mon_m/$mon_r`, nicht nach Anschlussname.
  Die Nummer haelt die Sortierung, `ws.sh` rechnet daraus den Monitor zurueck.
  **Kuerzel nach Anzahl Monitore:** 1 Monitor = nur `d`, 2 = `d` + `s`,
  3 = `d` + `s` + `a`. Workspaces mit fehlendem Kuerzel (Assigns,
  abgezogener Schirm, erster Workspace nach dem Login) klappt der Watcher
  (`collapse()` in `sidebar.py`) mit gleicher Nummer auf das letzte vorhandene
  Kuerzel zusammen (`23:s3` -> `33:d3`). Genauso jeder Workspace mit dem
  Kuerzel eines anderen Monitors (Login: sway legt den ersten Workspace je
  Schirm an, bevor alle da sind): er bekommt das Kuerzel seines Monitors, per
  `rename`, wenn es den Ziel-Workspace noch nicht gibt. Steckt man einen Schirm wieder an,
  wandern die Fenster nicht zurueck. Alte Namen mit `u`/`i`/`o` gelten dabei als
  fremd und werden so beim ersten Lauf auf `a`/`s`/`d` umbenannt.
- **Tasten:** `Super+N` / `Super+Shift+N` = Workspace N des aktuellen Monitors
  (hin / Fenster schieben). Andere Monitore ueber die **Befehlsleiste** (`Super+f`, unten).
  `Super+j` / `Super+k` = Fokus auf den Bildschirm links / rechts (`focus output`,
  ohne Umlauf); Fokus innerhalb des Monitors per `Super+l/ö` und Pfeile.
  `Super+q` / `Super+Ctrl+q` = naechstes / voriges Fenster der Tabs,
  bleibt auf dem Monitor. Dasselbe per Mausrad kippen (ohne Taste, `button7` =
  rechts = naechstes, `button6` = links = voriges, `--whole-window`, nur `--input-device=$tiltmouse` = Funkmaus, sonst loest seitliches Touchpad-Wischen es aus).
  Kippen mit Super ist nicht belegt. `Super+Ctrl+f` = Vollbild. `Super+Shift+z` = Hilfe.
  `Super+Tab` = alle Fenster aller Monitore als Vorschau-Raster (Quickshell; Bild =
  letzter sichtbarer Stand, sway kann verdeckte Fenster nicht abfotografieren).
  `Super+m` = Ticket-Board. `Super+Print` = OCR: Bereich aufziehen,
  erkannter Text (tesseract, `deu+eng`) landet in der Zwischenablage, Popup bestaetigt.
  `Super+Ctrl+m` = Ticket schnell eintragen (nur Eingabezeile `ask.sh`: `PROJ: Titel #label !prio`, Board bleibt zu).
- **Befehlsleiste** (Quickshell `quickshell/CommandBar.qml`, Decodierung
  `quickshell/nav.js`, Befehle `quickshell/commands/`; `quickshell ipc call bar
  toggle|open|close`, zum Testen `type TEXT`, `press NAME`, `info`): je Monitor eine
  Leiste direkt unter der waybar, volle Breite, 30 px, immer sichtbar, reserviert
  Platz (Ebene `bottom` + `exclusiveZone`: sway setzt die waybar auf `top` zuerst).
  **Links die Tabs** = Fenster des sichtbaren Workspaces (`wins` aus `sidebar.json`,
  Baum-Reihenfolge) mit Code, Icon, App und Titel; aktives Fenster (`active`, auch
  ohne Tastaturfokus) mit federnd gleitender Markierung, Eintraege ploppen rein/raus.
  Klick fokussiert, Mittelklick schliesst, Mausrad sortiert (`sidebar.py nudge`),
  Hover = voller Titel als Popup (deckend, ohne Ausblenden: halbtransparent gab
  Geisterbilder). Breite je Tab 120-260 px, sonst die ersten + `+N`.
  **Rechts die Kommandozeile**: `Super+f` (oder Klick) oeffnet ein Overlay mit
  exklusivem Tastaturfokus genau ueber dem Eingabefeld (eine Leiste auf `bottom`
  bekommt unter sway keinen Fokus; die Leiste selbst wechselt die Ebene nie, sonst
  rutscht sie ueber die waybar). Esc, Klick daneben oder ein ausgefuehrter Befehl
  geben den Fokus zurueck. Eingabe `[m] [Bildschirm] [Workspace] Fenster`, Teile
  durch **ein Leerzeichen** getrennt, **von rechts gelesen**: letzter Teil = Fenster,
  davor Workspace (`a s d f g h j k l ö` = 1-10), davor Bildschirm (`a`/`s`/`d`).
  Endet die Eingabe auf Leerzeichen, ist kein Fenster gemeint; ein leerer Teil (zwei
  Leerzeichen) = der aktuelle Bildschirm / sichtbare Workspace. Ausgefuehrt wird
  **erst mit Enter** (bis HL2-v40 `b`/`w` davor und sofort): ein Buchstabe kann bis
  zum naechsten Leerzeichen Fenster, Workspace oder Bildschirm sein. Fenstercodes
  `a`…`ö` = 1-10, `aa` = 11, `as` = 12 … `aö` = 20, `sa` = 21 (gleich, auch wenn
  Fenster dazukommen); Enter nimmt genau den getippten Code. `m` vorne = das beim
  Oeffnen aktive Fenster verschieben (Fokus bleibt), ohne Fensterteil, Leerzeichen
  am Ende egal. Backspace = ein Zeichen zurueck, Taste, die nicht passen kann (vierter
  Teil, `f` als Bildschirm, `aa` als Workspace, Code ohne Fenster) = Eingabefeld
  wackelt rot. Rechts im Feld steht, was Enter taete (`nav.js` `label()`).
  Beispiele: `d` = Fenster 3 hier; `f ` = Workspace 4 hier; `f d` = dort Fenster 3;
  `a s aa` = A2, Fenster 11; `s  ` = Fokus auf Bildschirm S; `m a f` = aktives
  Fenster nach A4; `m a  ` = auf den sichtbaren Workspace von A. Beim Tippen
  leuchten die passenden Tabs; geht es um einen anderen Bildschirm/Workspace, klappt
  unter dem Eingabefeld die Fensterliste dort mit Code auf (Zeilen anklickbar).
  **Befehle** `#wort arg …` mit Enter (nur am Leerzeichen getrennt, `#` ohne Shift auf
  deutscher Tastatur; bis HL2-v35 `:`); `#` allein
  listet alle mit Hilfe. **Tab** ergaenzt den Befehlsnamen (`nav.js` `complete()`):
  ein Treffer = ganzer Name + Leerzeichen, mehrere = gemeinsamer Anfang, danach
  blaettern Tab / Shift+Tab durch die Treffer (Zeile leuchtet), kein Treffer =
  rot wackeln; Argumente werden (noch) nicht ergaenzt. Codes in Befehlen = Codes der Tabs (Liste mit Komma),
  Ziel mit `>` + `[Bildschirm] Workspace` ohne Fenstercode (`a j` = A7, `f` = Workspace 4 hier;
  nur Bildschirm geht hier nicht, die Argumente verlieren leere Teile):
  `#all` = Baum Bildschirm -> Workspace -> App mit dem kuerzesten Befehl je App
  (`nav.js` `route()`), direkt daraus tippen, Enter/Esc klappt zu. `#all text` =
  **Suche**: nur Fenster, deren App, Titel, Werkzeug, Session-Titel, Verzeichnis oder
  Bereich `text` enthaelt (Codes bleiben die Plaetze im Workspace), Enter = erster
  Treffer. **Agenten in der Leiste**: die Leiste liest `$XDG_RUNTIME_DIR/agents.json`
  (von `agents.py watch`, je Session `con` = sway-Fenster); laeuft in einem Fenster
  eine Claude-/Codex-Session, zeigen Tab, Liste und Baum statt App-Icon und Name
  `✳ Claude` / `◎ Codex`, den Session-Titel und den Status (`⚙` arbeitet, `✓`
  bereit), `look()` in `CommandBar.qml`. Endet die Session, wird es wieder die App.
  Keine Hooks noetig (Codex hat keine Start/Stop-Hooks).
  `#split` = alle Fenster nebeneinander als ein geteilter Tab (ab 4 zwei Reihen),
  `#split a,s` = nur diese als geteilter Tab, der Rest bleibt Vollbild-Tabs,
  `#split a,s > a j` = dasselbe dort (Fokus geht mit; Paar rutscht ans Ende der
  Tabs), `#reset` = alle Teilungen aufloesen, wieder Tabs. Geteilte Tabs haben in
  der Leiste eine gemeinsame Unterstreichung (`group` in `sidebar.json`).
  `#close a,s` / `#only a` / `#clear` = diese / alle ausser / alle Fenster im
  Workspace schliessen (sway `kill`, Apps mit ungespeicherten Aenderungen fragen
  selbst). `#full [a]` = Vollbild an/aus. `#back` = voriger Workspace
  (`back_and_forth`, auch ueber Bildschirme). `#open name [> ziel]` = App aus den
  Desktop-Eintraegen starten (Kennung oder Name, genau vor Anfang vor enthalten,
  `gtk-launch`), mit Ziel dort. `#park name` / `#unpark [name]` = `park.py`,
  `#note Titel #tag` = `note.py`, `#ticket PROJ: Titel #label !prio` = Ticket in
  ToDo (`ticket.py quick todo`).
  **Neuer Befehl** = Eintrag in `commands/commands.json` + Skript, keine
  QML-Aenderung: `{"name": {"help": "...", "exec": ["skript", ...]}}`; `exec[0]` =
  Datei in `commands/`, `~/…` oder absoluter Pfad, ausfuehrbar, beliebige Sprache
  (aber nicht node: das gibt es nur ueber nvm, nicht im PATH von sway). Woerter
  nach `#name` als Argumente (nie durch eine Shell-Zeile). Umgebung `BAR_CONTEXT`
  = JSON des eingefrorenen Stands (`output`, `here`, `con` = aktives Fenster,
  `tabs` mit `code`/`id`/`name`/`title`, `grid`). stdout = `{"notify": "Text"}`
  oder Klartext (erste Zeile) = Meldung im Eingabefeld (4 s), Exit != 0 = rote
  Meldung (letzte stderr-Zeile). Fenster-Befehle in `commands/win.py`
  (`selftest`; plant sway-Befehle als Liste: Abloesen ueber den Hilfs-Workspace
  `99:umbau`, Teilen per `split` + `move container to mark` - auf ein Fenster =
  dahinter, auf einen Container = hinein; `split` auf einem Einzelkind aendert nur
  das Layout, deshalb Reihen erst einzeln). `{"builtin": "tree"}` nur fuer Befehle,
  die die Leiste selbst kann; wenige halten. Codes bleiben feste Grammatik in
  `nav.js` (Pruefung je Taste, kein Prozessstart).
  Daten = `"grid"` aus `sidebar.json`, beim Oeffnen eingefroren (Codes stabil,
  geschlossene Fenster tun nichts); aktives Fenster = `focused` darin.
  Workspace hin/verschieben ueber `sidebar.py workspaces apply go|move OUTPUT N CON`
  (legt den Workspace auf dem richtigen Monitor an), Fenster und Bildschirm per
  `I3.dispatch`. Test: `node tests/nav.cjs`. **Ueben**: `tools/nav-trainer.html` lokal
  im Browser oeffnen = Spiel mit Nachbildung der Leiste (Tabs, Eingabe, Liste, Baum,
  Tab-Ergaenzung) auf einem simulierten Desktop, gleiche `nav.js`, `#`-Befehle als
  JS-Simulation aller Befehle aus `commands.json` (auch open/park/unpark/note/ticket;
  App-Katalog im Trainer, keine echten Apps oder Vault-Dateien). Level 1 Fenster,
  2 Workspaces, 3 Bildschirme, 4 Verschieben, 5 Befehle, 6 Suchen, 7 Mix, 8 Apps,
  9 Sessions, 10 Notizen & Tickets. Standard = **Lernen** ohne Zeitdruck/Leben:
  Erklaerung je Typ, F1 zeigt einen Weg, nach Fehlern Enter = gleiche Ausgangslage
  nochmal, nach Erfolg Enter = weiter. Alle Typen unten einzeln waehlbar;
  Fortschritt zaehlt nur Loesungen ohne Hilfe. **Tempo-Test** = drei Leben,
  Tempo-Bonus, Combo, Gesamt-/Denkzeit, eigener Zeitschnitt und Bestwerte.
  Runde = mindestens 20 Aufgaben (Mix alle Typen), jeder Typ vor Wiederholung.
  Ergebnis zaehlt; Tab-Uebung verlangt zusaetzlich Tab. Alles im localStorage
  (`nav-game-v1`); Lernen veraendert keine Tempo-Bestwerte. Leertaste = neue Runde.
  Test: `node tests/trainer.cjs` prueft Befehlsabdeckung, Musterloesungen,
  Simulation, Wiederholen und Moduswechsel. Seit HL2-v34 statt Workspace-Raster (Super+u),
  Ziel-Monitor (Super+Esc, Super+Ctrl+N) und Super+Kippen; seit HL2-v35 als Leiste
  statt Overlay (Navigator) und statt der Fensterliste links (samt Super+b und
  waybar `custom/wins`).
- **Trading-Journal** (`Super+Ctrl+j`, `sway/scripts/journal.py`, eww `journal`):
  Screenshot des fokussierten Monitors (per `crop_chart()` auf die helle
  Chart-Flaeche samt Achsen zugeschnitten, ImageMagick; ohne helle Flaeche bleibt
  er ganz), dann ein Formular-Panel auf diesem
  Monitor (nochmal Super+Ctrl+j oder ✕ = verwerfen, Bild weg). Oben
  `+ <letztes Setup>` (nur Timeframe; solange `offen` auch Entry-Zeit (setzt Session + HHMM im Namen), Ergebnis, R) oder
  `Neues Setup`: Live/Backtest, Datum `TT.MM.JJJJ` + Entry-Zeit NY `HH:MM` (darf leer bleiben:
  dann ohne Zeit/Session im Namen; vorbelegt heute/jetzt; Session daraus wie in `market.py`), Symbol (`SYMBOLS`
  in journal.py), Long/Short/No Trade (Pflicht, nicht vorbelegt), D-Bias Bullish/Bearish/Neutral (Pflicht, nicht vorbelegt), Model (Unterordner von `Trading/TradingModels/` + `kein Model`;
  neuer Ordner = neues Model), Timeframe, Ergebnis Win/Loss/BE/offen/No Trade, R (optional, nicht bei offen/No Trade).
  Zuletzt benutztes Symbol/Model/TF ist vorgewaehlt. Speichern ist gesperrt,
  solange Datum/Zeit/R nicht passen (Regex im yuck, Rand rot); danach fragt
  `ask.sh` die Notiz (Esc = ohne). Knoepfe schicken nur Indizes/feste Werte,
  Freitext nie durch eww. Eine Datei je Setup:
  `Trading/journaling/{live-trades,backtesting}/JJJJ/MM/TT/<datum> <HHMM> <Symbol> <Long|Short|No Trade> <Model>.md`,
  Frontmatter `date time_ny session type instrument direction d_bias model timeframes result r captured`
  + Tags `journal/<typ>`, `session/…`, `direction/…`, `bias/…`, `model/…`, `instrument/…`, `result/…`;
  je Screenshot ein Abschnitt `## <TF> · erfasst TT.MM.JJJJ HH:MM` mit Bild
  `<erfasst>_HHMMSS.png` daneben. Letztes Setup in `~/.local/state/journal-last.json`,
  offener Screenshot in `$XDG_RUNTIME_DIR/journal-pending.json`. Alte Eintraege
  (auch das fruehere `Trading/Backtesting`) liegen in `Trading/journaling/legacy/`.
- **Schnellnotiz** (`Super+Ctrl+n`, `sway/scripts/note.py [TEXT]`, `#note`): Name per `ask.sh` (oder als Argument),
  `Titel` -> `Notizen/Titel.md`, `Titel #a #b` -> dazu `tags: [a, b]`,
  `Ordner/Titel` -> ab Vault-Wurzel. Inhalt aus `Templates/Schnellnotiz.md` im
  Vault (beim ersten Mal angelegt, in Obsidian frei aenderbar; Platzhalter
  `{{title}} {{date}} {{time}} {{tags}}`). Danach oeffnet Obsidian die Notiz
  (`obsidian://open?path=`); gibt es sie schon, wird sie nur geoeffnet.
- **Boersenuhr** (waybar `custom/market` neben der Uhr, `sway/scripts/market.py`):
  NY-Zeit + ICT-Session (Asia 20-00, London 02-05, NY AM 07-10 mit Countdown bis
  09:30, NY PM 13:30-16, alles NY-Zeit), sonst Countdown zur naechsten; CME-Pause
  und Wochenende = `zu`. Klassen `active`/`idle`/`closed`, Tooltip mit Ortszeiten.
- **TradingView** (app_id `tradingview`) hat `inhibit_idle visible`: kein
  Sperrbildschirm, solange der Chart zu sehen ist.
- **Session parken** (`sway/scripts/park.py save|restore [NAME]`, `#park`/`#unpark`): `Super+Ctrl+p` fragt per `ask.sh`
  einen Namen (ohne NAME), merkt sich je Fenster aller Monitore (ohne Scratchpad) den
  Workspace und schiebt alle auf `36:d6`. `Super+Ctrl+Shift+p` zeigt die
  geparkten Sessions (`ask.sh TITEL -` = Auswahlliste), schiebt jedes noch
  offene Fenster zurueck und vergisst die Session. Gleicher Name = Session
  erweitern. Gespeichert per con_id in `$XDG_RUNTIME_DIR/parked.json`, gilt
  also nur bis zum Neustart von sway.
- **Zwischenablage** (`Super+Shift+V`, `sway/scripts/clip.sh`): copyq speichert
  (laeuft per `exec_always`), rofi zeigt den Verlauf im Menue-Stil des Themes,
  Enter = `copyq select`, also wieder in die Zwischenablage. Kein eigenes
  copyq-Fenster.
- **Konsole** (`Super+Shift+Tab`, `sway/scripts/console.py`): cool-retro-term
  im Scratchpad, schwebend 70x55 % mittig. Erster Druck startet es, danach
  ein/aus (`for_window`-Regel auf app_id `cool-retro-term.cool-retro-term` +
  Bind in der sway-Config). Jedes Theme hat ein eigenes Design in
  `cool-retro-term/profile.json` (Farben des Themes, CRT-Effekte, Schrift).
  `console.py` traegt die Datei vor jedem Start als Profil `wm-theme` in die
  Datenbank von cool-retro-term ein, die Datei gewinnt also immer.
  Das normale Terminal bleibt Alacritty.
- **Benachrichtigungen** (swaync): Popups im Stil der Pickup-Meldungen des
  Themes, unten rechts ueber dem rechten HUD-Kasten (`positionY bottom`,
  `.floating-notifications` mit `margin-bottom` = HUD-Hoehe), 5 s, schmal.
  Das Panel hinter der Glocke (`Super+n`) ist davon getrennt gestylt.
- **Vorschau-Raster** (`Super+Tab`, Quickshell `quickshell/Overview.qml`,
  `quickshell ipc call overview toggle|open|close`, zum Testen `press NAME`,
  `type TEXT` (= Filter), `info`): Overlay auf dem fokussierten Monitor,
  alle Fenster aller Monitore als Kacheln (Reihenfolge wie der Baum `#all`,
  Daten = `"grid"` aus `sidebar.json`), Spaltenzahl so, dass die Kacheln am
  groessten werden. Kachel = Bild + Kennzeichen `<Kuerzel> <Bereich>` (● =
  Workspace gerade sichtbar) + App-Icon, Name, Titel. Startet auf dem
  fokussierten Fenster. Tasten: `h/j/k/l` oder Pfeile, Tab/Shift+Tab = weiter/
  zurueck, `a/s/d` = erstes Fenster des Monitors, `/` = Filter (App, Titel,
  Kuerzel, Bereich; Esc leert), Enter = hin, **Entf** = Fenster schliessen
  (Raster bleibt offen, Kachel blitzt rot und klappt weg), Esc = zu. Maus: Hover
  waehlt (nur bei echter Bewegung), Klick = hin, Mittelklick oder ✕ = schliessen.
  Animiert wie das Ticket-Board (Abtastlinie, Kacheln staffeln herein, Rahmen
  gleitet federnd, gewaehlte Kachel zoomt beim Springen). Bilder macht der
  Watcher in `snap()`, solange ein Fenster sichtbar ist (`$XDG_RUNTIME_DIR/win-shots`,
  nicht bei Sperre und nicht, solange `$XDG_RUNTIME_DIR/overview.open` liegt =
  Raster offen, sonst faenden die Bilder das Overlay).
- **Ticket-Board** (`Super+m`, Quickshell `Tickets.qml` + `TicketCard.qml`,
  `TicketDetail.qml`, `Chip.qml`, `sway/scripts/ticket.py`): Overlay auf dem
  fokussierten Monitor. Quelle der Wahrheit sind Markdown-Dateien im Vault
  `Tickets/<PROJEKT>/<PROJ>-<N> <Titel>.md` (Vorlage `Templates/Ticket.md`),
  Frontmatter `status prio created archived aliases tags`; Nummern je Projekt
  fortlaufend, nie wiederverwendet. Status `backlog|todo|in-arbeit|review|fertig`
  = fuenf Spalten, Prio `hoch|mittel|niedrig`, Labels = Tags. **WIP-Limit 4 je Projekt**
  auf `in-arbeit` (nicht archivierte): das fuenfte prallt ab, auch beim Projektwechsel;
  Spaltenkopf zeigt `n/4` nur mit Projekt-Reiter.
  Projekte (jetzt `WORK` = migrierte Missionen, `PRIVATE`) als Reiter oben
  (Tab/Shift+Tab, `1`-`9`, `0` = alle). Karte: Key, Titel, Prio, Labels,
  Checkliste `x/y` (leere `- [ ]` zaehlen nicht). Tasten: `h/j/k/l` oder Pfeile,
  `H`/`L` = Karte eine Spalte zurueck/vor, Enter = Detail-Popup, `n` neu, `e` Titel,
  `t` Labels, `P` Projekt, `p` Prio weiter, `a` archivieren/zurueckholen, `A`
  Archiv zeigen, `o` Notiz in Obsidian, `/` Filter, `Entf` zweimal binnen 3 s auf
  derselben Karte = loeschen (Hinweis "Nochmal Entf = KEY loeschen"; im Popup
  Knopf LOESCHEN, zweiter Klick bestaetigt), Esc = Popup/Board zu. Drag & Drop
  zwischen Spalten, Mikroanimationen (Oeffnen, fliegende Karte, Funken bei Fertig).
  Aenderungen an Status/Prio/Archiv gelten sofort, `ticket.py` schreibt hinterher.
  **Freitext** (neu, Titel, Labels, Filter) geht als Argument mit `--` an
  `ticket.py`, nie durch eine Shell-Zeile. Fehlerzeile ueber dem Fuss (Dateien
  ohne Kennung, doppelte Kennungen, Lesefehler, stderr fehlgeschlagener Aufrufe).
  `ticket.py list [PROJ] [STATUS] | show KEY | new PROJ TITEL [-p PRIO] [-l LABEL]...
  [-s STATUS] | set KEY FELD WERT | delete KEY | quick | open KEY | watch | migrate |
  selftest`. `FELD` = status|prio|title|project|labels|archived. `delete` schiebt die
  Datei nach `<Vault>/.trash/` (wiederherstellbar). `quick` liest stdin (oder `quick STATUS TEXT`)
  `[PROJ:] Titel #label !prio`, ohne Projekt das zuletzt benutzte
  (`~/.local/state/tickets-last`). Nur `ticket.py` schreibt Ticket-Dateien: atomar
  (`.tmp` + `os.replace`) unter `flock` auf `Tickets/.lock`; Text unter dem
  Frontmatter und fremde Frontmatter-Zeilen bleiben byte-gleich (Obsidian darf
  Listen umschreiben). `watch` (dauerhaft, eine JSON-Zeile je Aenderung) behaelt bei
  halb gespeicherten Dateien den letzten guten Stand. `migrate` (einmalig) holte die
  Missionen aus `~/.local/share/missions/data.json` nach `WORK`; Mission Control
  und `todo.py` sind entfernt. Farben nur ueber `root` in `shell.qml`.
- **Agenten** (`Super+c`, eww `agents`, `scripts/agents.py`): laufende
  Claude-Code- und Codex-Sessions als Karten (Tool, Titel, ⚙ arbeitet / ✓ bereit,
  letzter Prompt, letzte Aktion, Laufzeit, Kontext-Tokens, Workspace), darunter
  die letzten 10 beendeten, beides nach Ordner gruppiert. Overlay mittig auf dem
  fokussierten Monitor; eww kann keine Tasten, deshalb sway-Mode `[ AGENTS ]`:
  `j/k` waehlen, Enter springt zum Fenster (Elternkette der PID bis zum
  sway-Fenster) bzw. setzt eine beendete Session in Alacritty fort
  (`claude --resume`, `codex resume`), Esc / Super+c zu. Alles Oeffnen und
  Schliessen laeuft ueber `agents.py open|close|toggle`, sonst bleibt der Mode haengen.
  Quellen: `~/.claude/sessions/<pid>.json` (`status` busy/idle) + Transkript,
  `~/.codex/state_5.sqlite` (nur `thread_source='user'`: ohne Subagents und
  Claude-Importe) + Ende der rollout-Datei. `agents.py watch` (exec_always,
  PID-Datei, ruft nie eww) schreibt `$XDG_RUNTIME_DIR/agents.json`, weckt
  waybar `custom/agents` (`λ 1⚙ 2✓`, Klasse `new` = fertig und noch nicht
  angesehen) per `SIGRTMIN+11` und schickt ein Pickup, wenn ein Agent fertig
  wird und sein Fenster nicht sichtbar ist (Klick springt hin). Kein Status
  "wartet auf Freigabe": Claude meldet nur busy/idle.
  **Agenten-Tafel** (`Super+g`, eww `agents-board`, `agents.py board`):
  fuellt die freie Flaeche des fokussierten Monitors, je laufender Session
  eine Spalte mit dem Chat live (Prompts, Antworten, Tool-Aufrufe, neueste
  unten). Reine Anzeige, kein Klick, kein Mode. `agents.py chat` (deflisten,
  nur solange offen) liest jede Sekunde das Transkript-Ende (Bild-Zeilen
  uebersprungen) und kuerzt per Zeilenschaetzung (`fit()`, `CHAR_W`/`LINE_H`
  passend zu `.ch-*` in `eww.scss`) auf das, was in die Spalte passt.
- **Assigns:** VS Code `23:s3`, IntelliJ `24:s4`, KeePassXC `37:d7`, To Do
  `38:d8`, Teams `39:d9`, YouTube `40:d10`.
- **Fenster:** `workspace_layout tabbed`, Tab-Zeile per Schrift 1 + leerem
  `title_format` + Titelbar-Farben = Hintergrund auf ~3px geschrumpft (ganz weg
  geht in Sway nicht). Kein `Super+s` (stacking). Rahmen nur ueber `child_border`.
- **Hilfe-Panel** (eww `info`, `?` neben AMMO): Matrix Monitor x Nummer +
  alle Shortcuts. **Statisch**: bei neuen Binds oder Assigns mitziehen.
- **waybar oben:** Badge A/S/D (`custom/monitor`) + je Workspace `<Taste> <Icon>`
  (`1` … `9`, `0` fuer 10, wie Super+N; steht in `format-icons`). Der sichtbare
  Workspace jedes Monitors ist gleich hervorgehoben wie der fokussierte
  (`button.visible, button.focused` in `style.css`), damit jede Bar zeigt, was
  auf ihrem Monitor gerade offen ist. Die Fenster selbst zeigt die Befehlsleiste
  darunter.
  Seit HL2-v24 bleiben Workspace-Breiten beim Wechsel konstant; kurze Farb-
  uebergaenge geben Rueckmeldung. Die IPv6-Anzeige ist aus der Leiste entfernt.
  `sway/scratchpad` (≡ N) zaehlt die Fenster im Scratchpad, also die Konsole.

Ein neues Theme uebernimmt `ws.sh`, `sidebar.py`, `agents.py`, `clip.sh`, `market.py`, `journal.py`, `note.py`, `park.py`, `ticket.py`, `ask.sh`, die
`format-icons` der waybar (Nummer vor dem Icon) und die Module `custom/market` und `custom/agents`, die
Workspace-/Bind-Bloecke, den Mode `[ AGENTS ]` und die Konsolen-Regel (`console.py`, `for_window` auf
cool-retro-term) der sway-Config, die
Befehlsleiste (`CommandBar.qml`, `nav.js`, `commands/`, `tools/nav-trainer.html`), die eww-Fenster `info`/`agents`/`agents-board`/`journal`, das Ticket-Board (`Tickets.qml`/`TicketCard.qml`/`TicketDetail.qml`/`Chip.qml`, `ticket.py`), das Vorschau-Raster (`Overview.qml`) und Lage/Timeout der swaync-Popups
(`swaync/config.json`) und passt nur Farben und Schrift an: `eww.scss`, die Farb-Properties oben in `quickshell/shell.qml` (gelten auch fuer Befehlsleiste, Ticket-Board und Vorschau-Raster; `root` hat `hud bg font barBg edge box fill hover` und `warn` = Rot wie waybar `@warn`),
waybar `style.css`, den Popup-Block in `swaync/style.css` und die
`-theme-str`-Teile in `clip.sh` und `ask.sh` (die rofi-Theme-Datei liefert den Rest); in
`eww.scss` auch die Bloecke `.ms-*` (nur noch vom Journal-Panel benutzt), `.jr-*` (Journal) und `.ag-*` (Agenten). In `style.css` muss `button.visible` dieselbe
Hervorhebung bekommen wie `button.focused`; `#custom-market` (Klassen `active`/`idle`/`closed`) und `#custom-agents` (Klassen `busy`/`idle`/`new`/`none`) umfaerben; `cool-retro-term/profile.json` mit den Farben
des Themes neu einstellen (`fontColor`, `backgroundColor`, Effekte).

**Allgemeine Aenderungen** (Bedienung, Bausteine, Verhalten, nicht nur Farben)
gelten ab dann fuer jedes Theme: hier unter Standard-Bedienung eintragen, im
Skill `theme-erstellen` die Liste der Bausteine nachziehen, neuen Tag anlegen
und ihn in der Tabelle als "Aktueller Standard" markieren. Immer beide
Kopien pflegen: `AGENTS.md` = `CLAUDE.md`, `.agents/skills/` = `.claude/skills/`
(dort steht `AGENTS.md` statt `CLAUDE.md`).

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
waybar, swaync, screens.py und `sidebar.py watch` (startet eww und Quickshell) ueber
`exec_always` neu startet. eww und Quickshell werden vor dem Reload beendet; aeltere Tags, die
eww per `exec … eww open` starten, bekommen diese Zeile danach nachgereicht.
swayidle (traegt den Lock-Befehl) wird mit seiner `exec`-Zeile neu gestartet.
Firefox und Chrome brauchen einen Neustart, die Konsole auch (schliessen,
dann Super+Shift+Tab: erst dann laedt sie das neue `profile.json`).

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
- cool-retro-term hat eine feste app_id und kein `--class`: **jedes**
  cool-retro-term-Fenster landet als Konsole im Scratchpad. Einstellungen per
  Rechtsklick -> Settings speichert es erst beim Beenden in seine Datenbank;
  `console.py dump` holt sie danach nach `profile.json`. Nur `--profile`
  (lang) wirkt, `-p` erkennt die QML-Seite nicht.
- Quickshell ist **selbst gebaut** (`~/.cache/build/quickshell`, `cmake -GNinja -B build -DCMAKE_INSTALL_PREFIX=~/.local -DCRASH_HANDLER=OFF -DSERVICE_PIPEWIRE=OFF -DSERVICE_PAM=OFF -DSERVICE_POLKIT=OFF -DX11=OFF -DHYPRLAND=OFF -DSCREENCOPY=OFF`, dann `cmake --build build && cmake --install build`). Nutzt private Qt-APIs: nach jedem Qt-Update aus apt **neu bauen**, sonst Absturz. Build-Pakete: `qt6-{base,declarative,shadertools,svg,wayland}-dev` (+ `-private-dev`), `spirv-tools libcli11-dev ninja-build libjemalloc-dev qml6-module-qtquick-effects`.
- Mod-Taste ist Super; Richtungen `j k l ö` (i3-Stil), aber `Super+j/k` = Bildschirm wechseln (nur mit Shift = verschieben), Caps = zweite Super-Taste (`caps:super`, bis HL2-v39 Escape), Layout `de`.
- `workspace_layout tabbed` gilt nur fuer **neu angelegte** Workspaces. Alte
  (oder nach `Super+h/v/e`) oeffnen Apps wieder nebeneinander: `Super+w`.
- eww nie mehrfach gleichzeitig starten: zwei Starts = zwei Daemons, einer
  verliert den Socket und zeigt seine Fenster weiter an (doppelte Sidebar),
  `eww kill` erreicht ihn nicht. Deshalb startet nur `sidebar.py watch` eww,
  vorher `pkill -x eww`. Der Watcher ersetzt sich per PID-Datei
  (`$XDG_RUNTIME_DIR/eww-sidebar.pid`), nicht per `pkill -f` (das traefe die
  `sh -c`-Zeile von sway selbst).
- eww setzt `{}` (Text aus `input`) **ungeschuetzt** in die Shell-Zeile: ein `'`
  im Text bricht sie. Freitext deshalb ueber externe Eingabedialoge/stdin uebergeben
  (Journal und `ask.sh` nutzen rofi/stdin), IDs statt Text in
  `onclick`. Befehle aus `onclick` killt eww standardmaessig nach 200 ms:
  fuer Eingabedialoge ein explizites `:timeout` setzen.
- Aus Python eww/Daemons starten: `stdout=DEVNULL`, nie `capture_output` —
  der Daemon erbt die Pipe und der Aufruf haengt fuer immer.
- waybar `wlr/taskbar` taugt unter Sway nicht: Fenster hinter Tabs fehlen.
- Nach Aenderungen an sway: `swaymsg reload` (Super+Shift+C). Syntax pruefen
  mit `sway -C -c ~/.config/sway/config`.
