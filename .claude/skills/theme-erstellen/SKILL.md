---
name: theme-erstellen
description: Legt fuer Osas Sway-Desktop ein neues Theme an (oder eine neue Version eines bestehenden) und speichert es als Git-Tag <Theme>-v<N> in wm-backup – vom Entwurf ueber das Umbauen von sway, waybar, rofi, eww, swaync, hyprlock, alacritty, cool-retro-term (Konsole) und Browser bis zu Commit, Tag und Push. Nutze diesen Skill immer, wenn der User einen neuen Look, ein neues Farbschema oder Design fuer seinen Desktop will, ein bestehendes Theme nachbessern und als neue Version sichern moechte, oder seine aktuellen Live-Aenderungen in ~/.config ins Repo uebernehmen und taggen will – z. B. "neues Theme im Cyberpunk-Stil", "mach HL2 v2", "sichere meinen aktuellen Stand als Theme", "Tag fuer das Theme anlegen".
---

# Neues Theme erstellen

Lies zuerst `CLAUDE.md` im Repo-Root: dort steht, welche Datei wofuer da ist
und wohin sie deployt wird. Das Werkzeug:

```sh
S=.claude/skills/theme-switch/scripts/theme.sh
```

## Regeln, die das ganze Modell tragen

- **Tag = Theme-Stand**, Format `<Theme>-v<N>` (CamelCase-Name, z. B.
  `HL2-v2`, `Cyberpunk-v1`). Tags werden nie verschoben oder geloescht: sonst
  zeigt ein alter Tag ploetzlich einen anderen Look, und `theme-switch` kann
  nicht mehr zuverlaessig zurueck.
- **Linear auf master.** Jedes Theme baut auf dem vorherigen Commit auf.
  Commits heissen `<Theme>: <was, deutsch>`.
- **Live editieren, zurueck syncen.** In `~/.config` aendern, sofort neu laden,
  anschauen. Erst wenn es passt, mit `$S sync-back` ins Repo holen und
  committen. So sieht der User jeden Schritt direkt.

## Ablauf

### 1. Ausgangslage pruefen
- `$S status` muss "sauber" melden. Wenn nicht, gibt es ungesicherte
  Aenderungen: den User fragen, ob sie Teil des neuen Themes sind (dann weiter)
  oder erst verworfen werden sollen.
- `git status` im Repo sauber, `master` aktuell (`git pull`).
- Basis festlegen: der neueste Standard-Tag (in der Theme-Tabelle als
  "Aktueller Standard" markiert), sonst fehlen dem neuen
  Theme Bausteine der Standard-Bedienung. Will der User bewusst auf einem
  aelteren Tag aufbauen (z. B. FirstSetup), erst mit `theme-switch` dorthin
  wechseln und die Bausteine danach nachruesten. Der neue Commit landet trotzdem linear auf
  `master`, weil sync-back den ganzen Live-Stand uebernimmt.

### 2. Name und Version
- Neues Theme → `<Name>-v1`. Nachbesserung → naechste freie Nummer:
  `git tag -l '<Name>-v*'`. Pruefen, dass der Tag noch nicht existiert.

### 3. Design festlegen
Die **Bedienung ist fest** (Abschnitt "Standard-Bedienung" in `CLAUDE.md`:
Workspaces u/i/o mit 1-10, Ziel-Monitor Super+Esc + Super+Ctrl[+Shift]+N, Super+q/b/Shift+z, Mausrad kippen = Super+q (mit Super = Workspace weiter), Fensterliste links, Hilfe-Panel,
unsichtbare Tab-Zeile, Vorschau Super+Tab (rofi, Entf schliesst), Missionen Super+m, Konsole Super+Shift+Tab (cool-retro-term),
Zwischenablage Super+Shift+V, Pickup-Popups unten rechts,
waybar mit Nummer vor dem Icon und hervorgehobenem Workspace auf jedem Monitor, daneben Fensterzahl + Symbol
der Fensterliste `custom/wins`, Ziel-Monitor `custom/target`, Boersenuhr `custom/market` und Agenten `custom/agents`,
Trading-Journal Super+Ctrl+j, Schnellnotiz Super+Ctrl+n, Mission-Schnelleingabe Super+Ctrl+m, Agenten-Panel Super+c, Agenten-Tafel Super+g, Session parken Super+Ctrl+p / zurueck Super+Ctrl+Shift+p). Das gilt fuer jedes
Theme, nicht nur HL2. Ein Theme aendert nur den Look. Soll davon etwas
anders werden, erst mit dem User klaeren und danach `CLAUDE.md` nachziehen.
Kommt ein neuer Baustein dazu, in `CLAUDE.md`/`AGENTS.md` unter
"Standard-Bedienung" eintragen und den neuen Tag in der Tabelle als
"Aktueller Standard" markieren (Markierung beim alten entfernen).

Mit dem User klaeren, bevor Dateien angefasst werden:
- Palette: Hintergrund, Text, Akzent, gedimmter Akzent, Linie, Alarm. Als
  Variablen oben in jede Datei, wie die bestehenden `$hl2_*` in der
  sway-Config oder die Farbkommentare in `waybar/style.css`.
- Welche Komponenten umgebaut werden (siehe unten). Nicht jedes Theme muss
  alles anfassen. Was unveraendert bleibt, uebernimmt es vom Vorgaenger.
- Wallpaper: neues Bild nach `~/Private/wallpaper.jpg` (sync-back holt es ins Repo).

### 4. Umbauen, eine Komponente nach der anderen
Pro Komponente: live aendern → neu laden → User schaut → `$S sync-back` →
`git diff` durchsehen → commit `<Name>: <Komponente> …`. Kleine Commits
machen einen spaeteren Fix oder Rueckbau billig.

| Komponente | Datei(en) live | Neu laden |
|---|---|---|
| Fensterrahmen, Farben, Autostart | `~/.config/sway/config` | `swaymsg reload` |
| Leiste | `~/.config/waybar/{config.jsonc,style.css}` | `swaymsg reload` (exec_always) |
| Launcher/Power-Menue | `~/.config/rofi/<theme>.rasi`, per `@theme` in `config-nord.rasi` einhaengen | naechster Aufruf |
| Widgets | `~/.config/eww/{eww.yuck,eww.scss}` | `eww reload` |
| Benachrichtigungen | `~/.config/swaync/style.css` | `swaync-client -rs` |
| Sperre | `~/.config/hypr/hyprlock.conf` (+ `swaylock/config` als Fallback) | testen mit `~/.config/sway/scripts/lock.sh` |
| Terminal | `~/.config/alacritty/<theme>.toml`, import in `alacritty.toml` umstellen | neues Fenster |
| Konsole | `~/.config/cool-retro-term/profile.json`, oder per Rechtsklick -> Settings einstellen, schliessen, `~/.config/sway/scripts/console.py dump` | Konsole schliessen, Super+Shift+Tab |
| Browser | `~/.config/chrome-hl2-theme/`, Firefox `…/h5d4ltr7.default/chrome/` | Browser-Neustart |

Konventionen aus den bisherigen Themes, die sich bewaehrt haben:
- Neue Theme-Dateien bekommen einen eigenen Namen (`hl2-menu.rasi`,
  `hl2.toml`), statt die Vorgaenger-Datei zu ueberschreiben. Die Umschaltung
  ist dann eine einzige Zeile (`@theme`, `import`). Oben einen Kommentar
  "Vorgaenger: … — Zurueck = …" setzen.
- Dateinamen, auf die andere Dateien zeigen (`config-nord.rasi`,
  `lock.sh`, `learn.py`), nicht umbenennen.
- `learn.py stop` vor Lock/Exit/Idle und die eww-Datenquelle `learn` erhalten:
  der Lern-Timer ist Funktion, nicht Deko.
- eww startet nur ueber `exec_always … sidebar.py watch`; der Watcher oeffnet
  `hud-left hud-right` in `watch()`. Braucht das Theme andere Dauer-Fenster,
  dort eintragen, keine zweite `eww open`-Zeile (zwei Starts = zwei Daemons).
  Der Watcher klappt auch Workspaces ohne eigenen Monitor ein (`collapse()`,
  1 Monitor = nur o, 2 = o+i) und benennt Workspaces mit fremdem Kuerzel um: `sidebar.py` unveraendert uebernehmen.
- Die Bausteine der Standard-Bedienung mit umfaerben, nicht weglassen:
  `sidebar`, `info`, die waybar-Workspaces (Nummer + Icon, `button.visible`
  wie `button.focused`), `custom/wins` (Klassen `open`/`idle`/`off`), `custom/target`, `custom/market` (Klassen `active`/`idle`/`closed`), `custom/agents` (Klassen `busy`/`idle`/`new`/`none`), die swaync-Popups (Pickups
  unten rechts, Block `.floating-notifications` in `swaync/style.css`), das
  Zwischenablage-Menue `clip.sh`, die Eingabezeile `ask.sh` (Journal, Schnellnotiz, Mission-Schnelleingabe, Session parken), das Vorschau-Raster (rofi, `overview()` in `sidebar.py`), die
  Mission Control (eww `mission`, `.ms-*`, Fokus/Archiv ohne Loeschen, Obsidian-Notizen pro ID), das Agenten-Panel (eww `agents` + Tafel `agents-board`, `.ag-*`) und die Konsole (cool-retro-term, eigenes `profile.json` in den Farben des
  Themes). Nach dem Umbau alle einmal ausprobieren:
  `notify-send`, Super+Shift+V, Super+Tab (Entf schliesst ein Fenster), Super+m (Ziel mit `'` anlegen, Fokus setzen, abhaken, archivieren/zurueckholen, Notiz oeffnen), Super+Shift+Tab, Super+b (Symbol
  in `custom/wins` wechselt, Zahl stimmt mit den Fenstern ueberein), Super+Esc
  (`custom/target` schaltet weiter) + Super+Ctrl+Shift+N, Super+Ctrl+m, Super+Ctrl+j (Eintrag im Obsidian-Journal, Esc verwirft), Super+Ctrl+n (Notiz geht in Obsidian auf), Super+c (j/k, Enter springt, Esc zu, Mode wieder `default`), Super+g (Chats live nebeneinander, Spalten voll, nichts laeuft unten raus).
- Seit HL2-v24: IPv6-Modul aus der Leiste lassen, konstante Workspace-Breiten
  und kurze Farbuebergaenge erhalten; Missionen behalten Ansichts-Ueberblendungen.
- Aendern sich Binds oder Assigns, das Hilfe-Panel `info` in `eww.yuck`
  mitziehen.
- Neue Komponente (neuer Ordner, neues Ziel ausserhalb von `~/.config`)?
  In `map()` in `theme.sh` und in die Tabelle in `CLAUDE.md` eintragen,
  sonst deployt `switch` sie nicht.

### 5. Abschluss
1. `$S sync-back`, dann `git status`: Muell (Backups, Caches) wieder
   entfernen und in `EXCL` in `theme.sh` aufnehmen, falls er wiederkommt.
2. `CLAUDE.md` → Theme-Tabelle um eine Zeile ergaenzen (Tag + Look in einem Satz).
3. Letzter Commit, dann `git tag -a <Name>-v<N> -m "<Name>-v<N>: <Look in einem Satz>"`
   (ab `HL2-v2` annotiert; `theme.sh list` zeigt die Nachricht).
4. `echo <Name>-v<N> > ~/.local/state/wm-theme`, damit `theme.sh current`
   stimmt.
5. `$S status` → muss "sauber" sein.
6. **Vor dem Push fragen**: `git push origin master <Name>-v<N>`.

## Nur den aktuellen Stand sichern

Hat der User schon live herumprobiert und will das nur festhalten: Schritte
1 (Abweichungen sind hier gewollt), 2 und 5, dabei ein Commit
`<Name>: Stand gesichert` oder genauer.
