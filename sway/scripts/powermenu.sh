#!/bin/sh
# Power-Menue fuer den ⏻-Button in waybar. rofi -dmenu statt eines eigenen
# GUI-Widgets: rofi laeuft sowieso und traegt schon das HL2-Theme.
# ponytail: kein Bestaetigungsdialog vor Neustart/Aus. Wer das will, haengt
# ein zweites rofi -dmenu mit Ja/Nein davor.
#
# -theme-str schaltet die Suchzeile ab; der Titel "λ HALF-LIFE²" bleibt.
set -e

# HL2-Hauptmenue: Grossbuchstaben, keine Icons, RESUME = Abbrechen.
# Layout (Vollbild, Liste unten links) kommt aus hl2-menu.rasi.
resume="RESUME"
lock="LOCK"
logout="LOG OUT"
suspend="SUSPEND"
reboot="RESTART"
poweroff="QUIT"

choice=$(printf '%s\n%s\n%s\n%s\n%s\n%s\n' \
    "$resume" "$lock" "$logout" "$suspend" "$reboot" "$poweroff" |
  rofi -dmenu -i -p "" -no-custom \
       -config ~/.config/rofi/config-nord.rasi \
       -theme-str 'inputbar { enabled: false; }
                   listview { lines: 6; spacing: 6px; }
                   element { padding: 4px 12px; }
                   element-text { font: "Verdana Bold 17"; }')

# Lern-Timer anhalten, egal ob Sperren, Abmelden oder Ausschalten
[ -n "$choice" ] && [ "$choice" != "$resume" ] && { ~/.config/eww/scripts/learn.py stop || true; }

case "$choice" in
  "$lock")     exec ~/.config/sway/scripts/lock.sh ;;
  "$logout")   exec swaymsg exit ;;
  "$suspend")  exec systemctl suspend ;;
  "$reboot")   exec systemctl reboot ;;
  "$poweroff") exec systemctl poweroff ;;
esac
