#!/bin/sh
# Trading-Journal (Super+Ctrl+j): Screenshot vom fokussierten Monitor, dann
# Notiz per ask.sh, beides in die Tagesdatei im Obsidian-Vault:
#   Trading/journaling/<datum>/<datum>.md, die Bilder liegen daneben.
# Esc = verwerfen, das Bild wird wieder geloescht. Abschnitt je Eintrag mit
# Orts- und NY-Zeit, Bild als Obsidian-Embed ![[…]].
set -e
d=$(date +%F)
dir="$HOME/Documents/Obsidian Vault/Trading/journaling/$d"
md="$dir/$d.md"
img="${d}_$(date +%H%M%S).png"  # Datum im Namen: Obsidian sucht Embeds vault-weit
mkdir -p "$dir"
# erst das Bild, damit rofi nicht mit drauf ist
grim -o "$(swaymsg -t get_outputs | jq -r '.[] | select(.focused).name')" "$dir/$img"
note=$(~/.config/sway/scripts/ask.sh "JOURNAL") || {
    rm -f "$dir/$img"; rmdir "$dir" 2>/dev/null; exit 0; }

[ -f "$md" ] || printf -- '---\ndate: %s\ntags:\n  - trading\n  - journal\n---\n\n# %s – Journal\n' \
    "$d" "$(date +%d.%m.%Y)" > "$md"
printf '\n## %s (NY %s)\n\n%s\n\n![[%s]]\n' \
    "$(date +%H:%M)" "$(TZ=America/New_York date +%H:%M)" "$note" "$img" >> "$md"
notify-send "JOURNAL" "Eintrag $(date +%H:%M) gespeichert"
