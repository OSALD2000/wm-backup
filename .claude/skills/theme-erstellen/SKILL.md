---
name: theme-erstellen
description: Legt fuer Osas Sway-Desktop ein neues Theme an (oder eine neue Version eines bestehenden) und speichert es als Git-Tag <Theme>-v<N> in wm-backup – vom Entwurf ueber das Umbauen von sway, waybar, rofi, eww, swaync, hyprlock, alacritty und Browser bis zu Commit, Tag und Push. Nutze diesen Skill immer, wenn der User einen neuen Look, ein neues Farbschema oder Design fuer seinen Desktop will, ein bestehendes Theme nachbessern und als neue Version sichern moechte, oder seine aktuellen Live-Aenderungen in ~/.config ins Repo uebernehmen und taggen will – z. B. "neues Theme im Cyberpunk-Stil", "mach HL2 v2", "sichere meinen aktuellen Stand als Theme", "Tag fuer das Theme anlegen".
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
- Basis festlegen: Normalerweise ist das der deployte Stand. Will der User auf
  einem anderen Tag aufbauen (z. B. FirstSetup statt HL2), erst mit
  `theme-switch` dorthin wechseln. Der neue Commit landet trotzdem linear auf
  `master`, weil sync-back den ganzen Live-Stand uebernimmt.

### 2. Name und Version
- Neues Theme → `<Name>-v1`. Nachbesserung → naechste freie Nummer:
  `git tag -l '<Name>-v*'`. Pruefen, dass der Tag noch nicht existiert.

### 3. Design festlegen
Die **Bedienung ist fest** (Abschnitt "Standard-Bedienung" in `CLAUDE.md`:
Workspaces u/i/o mit 1-10, Super+q/b/Shift+z, Fensterliste links, Hilfe-Panel,
unsichtbare Tab-Zeile). Ein Theme aendert nur den Look. Soll davon etwas
anders werden, erst mit dem User klaeren und danach `CLAUDE.md` nachziehen.

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
- Die Bausteine der Standard-Bedienung mit umfaerben, nicht weglassen:
  `sidebar`, `info`, die waybar-Workspace-Icons, die swaync-Popups (Pickups
  unten rechts, Block `.floating-notifications` in `swaync/style.css`), das
  Zwischenablage-Menue `clip.sh`, das Vorschau-Raster (`sidebar.py overview`)
  und die Konsole `scratch-term`. Nach dem Umbau alle einmal ausprobieren:
  `notify-send`, Super+Shift+V, Super+Tab, Super+^.
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
