---
name: theme-switch
description: Wechselt Osas Sway-Desktop zwischen gespeicherten Themes (Git-Tags wie HL2-v1, FirstSetup-v1) und deployt sie nach ~/.config. Nutze diesen Skill immer, wenn der User auf ein anderes Theme, einen anderen Tag oder eine aeltere Version umschalten will, zurueck zum alten Look moechte, fragt welches Theme gerade aktiv ist oder welche Themes es gibt – z. B. "wechsel auf HL2", "mach FirstSetup wieder an", "zurueck zu v1", "welches Theme laeuft gerade", "switch theme".
---

# Theme wechseln

Themes sind Git-Tags `<Theme>-v<N>` in diesem Repo. Wechseln heisst: den Tag
exportieren und nach `~/.config` kopieren (nicht auschecken – HEAD und `master`
bleiben, wo sie sind). Das erledigt das Skript:

```sh
S=.claude/skills/theme-switch/scripts/theme.sh
```

## Ablauf

1. **Ziel klaeren.** `$S list` zeigt alle Tags, `*` markiert den deployten.
   Nennt der User nur einen Namen ("HL2"), nimm die hoechste Version davon.
   Ist das Ziel schon deployt, sag das und hoer auf.

2. **Probelauf.** `$S switch <tag> -n` listet die Dateien, die sich aendern
   wuerden. Dabei wird zuerst geprueft, ob live etwas vom deployten Stand
   abweicht.

3. **Bei Abbruch wegen Abweichungen** (Exit 2): Das sind ungesicherte Tweaks
   des Users. Zeig ihm die Liste und frag, was passieren soll:
   - sichern → Skill `theme-erstellen` (sync-back, commit, neuer Tag), dann wechseln
   - verwerfen → `$S switch <tag> -f`
   Nicht selbst entscheiden: `-f` loescht die Aenderungen unwiderruflich.

4. **Wechseln.** `$S switch <tag>`. Das Skript kopiert die Dateien, schreibt
   den Stand nach `~/.local/state/wm-theme`, ruft `swaymsg reload` auf, startet
   swayidle mit dem Lock-Befehl des neuen Themes neu und
   oeffnet die eww-Fenster, die die neue sway-Config nennt.

5. **Ergebnis melden.** Welcher Tag jetzt live ist, und dass Firefox/Chrome
   neu gestartet werden muessen, falls sich Dateien unter `browser/`
   geaendert haben. Laeuft keine Sway-Session (Skript meldet das), soll der
   User Super+Shift+C druecken.

## Gut zu wissen

- rsync laeuft **ohne --delete**. Beim Wechsel auf ein aelteres Theme bleiben
  neuere Dateien liegen (z. B. `~/.config/hypr/` bei FirstSetup). Sie werden
  nur vom Theme benutzt, das sie referenziert, und stoeren deshalb nicht.
- Die Ordner in `~/.config` haben eigene alte Git-Repos (`pre-hl2`). Diffs
  dort nach einem Wechsel sind normal. Dort nichts committen oder zuruecksetzen.
- Nur "zurueck zum vorherigen Stand ohne Tag" (z. B. uncommittete Arbeit)
  geht mit diesem Skill nicht – dafuer erst mit `theme-erstellen` einen Tag
  anlegen.
- Sieht nach dem Wechsel etwas kaputt aus: `swaymsg -t get_config` /
  `sway -C -c ~/.config/sway/config` pruefen, eww mit `eww logs`, waybar mit
  `pkill waybar; waybar` im Terminal.
