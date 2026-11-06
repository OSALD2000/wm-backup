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
| `sway/scripts/` | `~/.config/sway/scripts/` | `lock.sh` (hyprlock, sonst swaylock), `powermenu.sh` (rofi -dmenu), `clip.sh` (Zwischenablage, rofi ueber copyq), `screens.py` (Monitore anordnen, Laptop rechts), `ws.sh` (Super+N = Workspace N des aktuellen Monitors, Super+Ctrl+N = des Ziel-Monitors, Super+Esc = Ziel weiter), `console.py` (Konsole Super+Shift+Tab), `market.py` (waybar `custom/market`: NY-Zeit + Session), `journal.py` (Trading-Journal), `note.py` (Schnellnotiz Obsidian), `park.py` (Session parken), `ask.sh` (rofi-Eingabezeile, mit `-` Auswahlliste), `ipv6.sh`, `ticket.py` (Tickets als Markdown im Vault, einzige Schreibstelle, CLI fuer Board und Agenten) |
| `hypr/` | `~/.config/hypr/` | **nur hyprlock** (Sperrbildschirm) + `loading.sh` (Ladebalken). Hyprland selbst wird nicht benutzt |
| `waybar/` | `~/.config/waybar/` | obere Leiste (`config.jsonc`, `style.css`): Monitor-Badge U/I/O + Workspaces als `<Taste> <Icon>`, sichtbarer Workspace je Monitor hervorgehoben, `custom/wins` = Fensterzahl + Fensterliste offen/zu, `custom/target` = Ziel-Monitor `→ U/I/O`, `custom/agents` = Claude/Codex-Status |
| `rofi/` | `~/.config/rofi/` | Launcher. Sway ruft `rofi -config ~/.config/rofi/config-nord.rasi` auf; der Name "nord" ist historisch, das aktive Theme steht per `@theme` darin (HL2: `hl2-menu.rasi`). `config.rasi` gehoert zu i3 |
| `eww/` | `~/.config/eww/` | Desktop-Widgets. HL2: `hud-left`/`hud-right` + Lern-Panel `learn` (Super+Z), Hilfe `info` (Super+Shift+Z), Trading-Journal `journal` (Super+Ctrl+j, Formular von `sway/scripts/journal.py`). `scripts/learn.py` = Lern-Timer, Daten in `~/.local/share/learn-timer/`; `scripts/sidebar.py` = Watcher fuer die Fensterliste (schreibt `$XDG_RUNTIME_DIR/sidebar.json`, startet Quickshell) + Super+q/b + Workspace-Raster Super[+Shift]+u + Bilder fuer das Vorschau-Raster Super+Tab (`snap()`) + Stand fuer waybar `custom/wins` (`bar`); `scripts/agents.py` = Agenten-Panel `agents` (Super+c) + Tafel `agents-board` (Super+g) + waybar `custom/agents` |
| `swaync/` | `~/.config/swaync/` | Benachrichtigungen (Popups als Pickups unten rechts) + Panel hinter der Glocke |
| `swaylock/` | `~/.config/swaylock/` | Fallback-Sperre |
| `alacritty/` | `~/.config/alacritty/` | Terminal. `alacritty.toml` importiert die Farbdatei (`hl2.toml`, `nord.toml`), `lambda.txt` = Begruessung |
| `cool-retro-term/` | `~/.config/cool-retro-term/` | Look der Konsole: `profile.json` (Farben, CRT-Effekte, Schrift), traegt `console.py` vor jedem Start ein |
| `quickshell/` | `~/.config/quickshell/` | Fensterliste links (`shell.qml`): je Monitor eine animierte Leiste, liest `sidebar.json`. Dazu das Workspace-Raster Super+u (`grid`, per `quickshell ipc` geoeffnet). Ausserdem das Ticket-Board Super+m (`Tickets.qml` + `TicketCard.qml`, `TicketDetail.qml`, gemeinsamer Knopf `Chip.qml`) und das Vorschau-Raster Super+Tab (`Overview.qml`). Binary `~/.local/bin/quickshell` selbst gebaut (siehe Stolperfallen) |
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
| `HL2-v30` | wie v29, Ticket-Board statt Mission Control: Tickets als Markdown im Obsidian-Vault (`Tickets/<PROJEKT>/`), Board mit Backlog/ToDo/In Arbeit/Review/Fertig in Quickshell (Super+m), Prio, Labels, Detail-Popup, Drag & Drop, Loeschen in den Obsidian-Papierkorb, CLI `ticket` fuer Agenten; Vorschau-Raster (Super+Tab) als animiertes Quickshell-Overlay mit Filter. **Aktueller Standard** fuer neue Themes |

Welcher Tag gerade live ist: `theme.sh current` (steht in
`~/.local/state/wm-theme`; ohne die Datei gilt der Tag auf HEAD).

## Standard-Bedienung (gilt fuer jedes neue Theme)

Seit `HL2-v4` ist die Bedienung fest, ergaenzt in `HL2-v5` bis `HL2-v30` (Vorschau,
Zwischenablage, Konsole, Pickup-Popups, Workspace-Nummern und Fensterzahl in waybar,
Ticket-Board). Alles in dieser Liste gilt fuer
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
  **Kuerzel nach Anzahl Monitore:** 1 Monitor = nur `o`, 2 = `o` + `i`,
  3 = `o` + `i` + `u`. Workspaces mit fehlendem Kuerzel (Assigns,
  abgezogener Schirm, erster Workspace nach dem Login) klappt der Watcher
  (`collapse()` in `sidebar.py`) mit gleicher Nummer auf das letzte vorhandene
  Kuerzel zusammen (`23:i3` -> `33:o3`). Genauso jeder Workspace mit dem
  Kuerzel eines anderen Monitors (Login: sway legt den ersten Workspace je
  Schirm an, bevor alle da sind): er bekommt das Kuerzel seines Monitors, per
  `rename`, wenn es den Ziel-Workspace noch nicht gibt. Steckt man einen Schirm wieder an,
  wandern die Fenster nicht zurueck.
- **Tasten:** `Super+N` / `Super+Shift+N` = Workspace N des aktuellen Monitors
  (hin / Fenster schieben). `Super+Ctrl+N` / `Super+Ctrl+Shift+N` = dasselbe
  auf dem **Ziel-Monitor** (Fokus bleibt beim Schieben). Das Ziel zeigt waybar
  (`custom/target`, `→ U/I/O`, bei 1 Monitor ausgeblendet), `Super+Esc` oder
  Klick schaltet es weiter (u -> i -> o, nur vorhandene Kuerzel). Es bleibt
  stehen, bis man es aendert; Start (und Rueckfall, wenn der Schirm fehlt) ist
  `o`. Gespeichert in `$XDG_RUNTIME_DIR/ws-target` (`ws.sh cycle`/`bar`),
  `ws.sh cycle` weckt waybar per `SIGRTMIN+10`.
  `Super+j` / `Super+k` = Fokus auf den Bildschirm links / rechts (`focus output`,
  ohne Umlauf); Fokus innerhalb des Monitors per `Super+l/ö` und Pfeile.
  `Super+q` / `Super+Ctrl+q` = naechstes / voriges Fenster der Liste links,
  bleibt auf dem Monitor. Dasselbe per Mausrad kippen (ohne Taste, `button7` =
  rechts = naechstes, `button6` = links = voriges, `--whole-window`). Mit Super
  gekippt = belegter Workspace des Monitors weiter / zurueck (`next_on_output`). `Super+b` = Liste an/aus. `Super+Shift+z` = Hilfe.
  `Super+Tab` = alle Fenster aller Monitore als Vorschau-Raster (Quickshell; Bild =
  letzter sichtbarer Stand, sway kann verdeckte Fenster nicht abfotografieren).
  `Super+m` = Ticket-Board. `Super+Print` = OCR: Bereich aufziehen,
  erkannter Text (tesseract, `deu+eng`) landet in der Zwischenablage, Popup bestaetigt.
  `Super+Ctrl+m` = Ticket schnell eintragen (nur Eingabezeile `ask.sh`: `PROJ: Titel #label !prio`, Board bleibt zu).
- **Workspace-Raster** (`Super+u` wechseln, `Super+Shift+u` aktives Fenster
  verschieben; `sidebar.py workspaces go|move`): Overlay in Quickshell
  (`grid` in `quickshell/shell.qml`) auf dem fokussierten Monitor, eine Zeile je
  aktivem Bildschirm von links nach rechts (Kopf `U/I/O` + Anschluss) und zehn
  Felder (1-10), auch leere Workspaces. **Live**: der Watcher schreibt alle Felder
  samt Fenstern als `"grid"` nach `sidebar.json`, jedes Feld zeigt die App-Icons
  (bis 4, dann `+N`); sichtbare Workspaces gefuellt mit Punkt, fokussierter mit
  hellem Rand, die Auswahl gleitet federnd. Darunter Kuerzel, Anschluss und die
  Apps des gewaehlten Felds. Tasten: `h/j/k/l` oder Pfeile, `u/i/o` = Zeile,
  Nummer tippen = landet im Eingabefeld unter dem Zeilenkopf der aktuellen Zeile
  (Klick aufs Feld waehlt die Zeile): `2`-`9`, `0` und `10` bestaetigen sofort,
  `1` wartet 0,7 s auf eine `0`, Backspace leert; Enter = bestaetigen, Tab = zwischen
  Wechseln und Verschieben umschalten, Esc oder Klick daneben = abbrechen. Maus:
  Hover waehlt, Klick aufs Feld bestaetigt, Klick auf ein Icon springt direkt zu
  dem Fenster. `sidebar.py` haelt beim Oeffnen Startfeld und Fenster-ID fest und
  ruft `quickshell ipc call grid open ACTION FELD CON OUTPUT`; bestaetigt wird ueber
  `sidebar.py workspaces apply ACTION OUTPUT N CON`.
  Letztes bestaetigtes Ziel je Aktion in `~/.local/state/workspace-grid.json`
  (Anschluss + Nummer); fehlt der Bildschirm, startet die Auswahl beim aktuellen
  Workspace. Beim Verschieben bleibt der Fokus am bisherigen Ort. Aendert sich die
  Bildschirmzuordnung waehrend der Auswahl, wird abgebrochen. Das bestehende
  interne u/i/o-Schema und die Direktkuerzel bleiben erhalten (bis zu drei Bildschirme).
  Raster und Direktkuerzel bedienen dieselben Workspaces; Assigns, Waybar,
  Fensterliste, Session-Parken und `collapse()` verwenden weiter diese Namen.
  Die gemerkten Raster-Ziele sind unabhaengig vom Ziel-Monitor in `ws-target`
  (`Super+Esc`, waybar `custom/target`): Eine Raster-Auswahl aendert den Pfeil
  nicht. Das gilt fuer jedes neue Theme.
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
- **Schnellnotiz** (`Super+Ctrl+n`, `sway/scripts/note.py`): Name per `ask.sh`,
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
- **Session parken** (`sway/scripts/park.py`): `Super+Ctrl+p` fragt per `ask.sh`
  einen Namen, merkt sich je Fenster aller Monitore (ohne Scratchpad) den
  Workspace und schiebt alle auf `36:o6`. `Super+Ctrl+Shift+p` zeigt die
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
  alle Fenster aller Monitore als Kacheln (Reihenfolge wie das Workspace-Raster,
  Daten = `"grid"` aus `sidebar.json`), Spaltenzahl so, dass die Kacheln am
  groessten werden. Kachel = Bild + Kennzeichen `<Kuerzel> <Bereich>` (● =
  Workspace gerade sichtbar) + App-Icon, Name, Titel. Startet auf dem
  fokussierten Fenster. Tasten: `h/j/k/l` oder Pfeile, Tab/Shift+Tab = weiter/
  zurueck, `u/i/o` = erstes Fenster des Monitors, `/` = Filter (App, Titel,
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
  = fuenf Spalten, Prio `hoch|mittel|niedrig`, Labels = Tags. **WIP-Limit 3** auf
  `in-arbeit` (nicht archivierte, alle Projekte): das vierte prallt ab.
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
- **Assigns:** VS Code `23:i3`, IntelliJ `24:i4`, KeePassXC `37:o7`, To Do
  `38:o8`, Teams `39:o9`, YouTube `40:o10`.
- **Fenster:** `workspace_layout tabbed`, Tab-Zeile per Schrift 1 + leerem
  `title_format` + Titelbar-Farben = Hintergrund auf ~3px geschrumpft (ganz weg
  geht in Sway nicht). Kein `Super+s` (stacking). Rahmen nur ueber `child_border`.
- **Fensterliste links** (Quickshell `quickshell/shell.qml`, 60px, volle Hoehe, reserviert Platz, Kaesten wie die waybar-Workspaces): Icon + App-Name je Fenster des
  sichtbaren Workspaces, erst ab 2 Fenstern, Klick fokussiert, Mittelklick
  schliesst, Mausrad ueber einem Eintrag schiebt das Fenster hoch/runter (`sidebar.py nudge`, swap mit dem Nachbarn), Hover = Fenstertitel als Popout (deckend, ohne Ausblenden: halbtransparent gab Geisterbilder). Animiert: Leiste faehrt ein, Eintraege ploppen rein/raus, leuchtende Markierung gleitet federnd zum zuletzt fokussierten Fenster des Workspaces (`active` in `sidebar.json`, auch ohne Tastaturfokus). Ebene `bottom`, damit waybar (Ebene top) immer volle Breite hat. Daten: `sidebar.py watch` schreibt `{"wins", "show"}` atomar, Quickshell liest per `FileView` mit `watchChanges`; der Watcher startet Quickshell (vorher `pkill -x quickshell`). Fehler: `quickshell log`.
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
  Seit HL2-v24 bleiben Workspace-Breiten beim Wechsel konstant; kurze Farb-
  uebergaenge geben Rueckmeldung. Die IPv6-Anzeige ist aus der Leiste entfernt.
  Rechts daneben `custom/target` (`ws.sh bar`) = Ziel-Monitor fuer Super+Ctrl+N.
  `sway/scratchpad` (≡ N) zaehlt die Fenster im Scratchpad, also die Konsole.

Ein neues Theme uebernimmt `ws.sh`, `sidebar.py`, `agents.py`, `clip.sh`, `market.py`, `journal.py`, `note.py`, `park.py`, `ticket.py`, `ask.sh`, die
`format-icons` der waybar (Nummer vor dem Icon) und die Module `custom/wins`, `custom/target`, `custom/market` und `custom/agents`, die
Workspace-/Bind-Bloecke, den Mode `[ AGENTS ]` und die Konsolen-Regel (`console.py`, `for_window` auf
cool-retro-term) der sway-Config, die
Fensterliste `quickshell/shell.qml`, die eww-Fenster `info`/`agents`/`agents-board`/`journal`, das Ticket-Board (`Tickets.qml`/`TicketCard.qml`/`TicketDetail.qml`/`Chip.qml`, `ticket.py`), das Vorschau-Raster (`Overview.qml`) und Lage/Timeout der swaync-Popups
(`swaync/config.json`) und passt nur Farben und Schrift an: `eww.scss`, die Farb-Properties oben in `quickshell/shell.qml` (gelten auch fuer Workspace-Raster, Ticket-Board und Vorschau-Raster; `root` hat `hud bg font barBg edge box fill hover` und `warn` = Rot wie waybar `@warn`),
waybar `style.css`, den Popup-Block in `swaync/style.css` und die
`-theme-str`-Teile in `clip.sh` und `ask.sh` (die rofi-Theme-Datei liefert den Rest); in
`eww.scss` auch die Bloecke `.ms-*` (nur noch vom Journal-Panel benutzt), `.jr-*` (Journal) und `.ag-*` (Agenten). In `style.css` muss `button.visible` dieselbe
Hervorhebung bekommen wie `button.focused`; `#custom-wins` mit den Klassen
`open`/`idle`/`off`, `#custom-target` und `#custom-market` (Klassen `active`/`idle`/`closed`) und `#custom-agents` (Klassen `busy`/`idle`/`new`/`none`) umfaerben; `cool-retro-term/profile.json` mit den Farben
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
- Mod-Taste ist Super; Richtungen `j k l ö` (i3-Stil), aber `Super+j/k` = Bildschirm wechseln (nur mit Shift = verschieben), Caps = Escape, Layout `de`.
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
