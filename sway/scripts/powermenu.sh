#!/bin/sh
# Die Icons sind echte Nerd-Font-Zeichen (Private Use Area). sh kennt kein
# \uXXXX, also stehen sie hier als UTF-8-Bytes. Gehen sie beim Kopieren
# verloren, bleibt nur der Text stehen — kaputt geht nichts.
# Codepoints: f023 Schloss, f08b Abmelden, f186 Mond, f021 Neustart,
# f011 Power. Pruefen mit: fc-list ':charset=f023' family | grep Iosevka
# Power-Menue fuer den ⏻-Button in waybar. rofi -dmenu statt eines eigenen
# GUI-Widgets: rofi laeuft sowieso und traegt schon das Nord-Theme.
# ponytail: kein Bestaetigungsdialog vor Neustart/Aus. Wer das will, haengt
# ein zweites rofi -dmenu mit Ja/Nein davor.
#
# -theme-str schaltet die Suchzeile ab und zieht die Karte unter den
# Power-Button oben rechts. Ohne 'inputbar { enabled: false; }' klebte hier
# die 19px-Suchzeile des Spotlight-Themes als leerer Block obendrueber.
set -e

lock=" Sperren"
logout=" Abmelden"
suspend=" Bereitschaft"
reboot=" Neu starten"
poweroff=" Ausschalten"

choice=$(printf '%s\n%s\n%s\n%s\n%s\n' \
    "$lock" "$logout" "$suspend" "$reboot" "$poweroff" |
  rofi -dmenu -i -p "" -no-custom \
       -config ~/.config/rofi/config-nord.rasi \
       -theme-str 'window { width: 280px; border-radius: 12px;
                            location: northeast; anchor: northeast;
                            y-offset: 58px; x-offset: -12px; }
                   inputbar { enabled: false; }
                   listview { lines: 5; padding: 8px; border: 0; }
                   element { padding: 11px 16px; border-radius: 9px; }')

# Lern-Timer anhalten, egal ob Sperren, Abmelden oder Ausschalten
[ -n "$choice" ] && { ~/.config/eww/scripts/learn.py stop || true; }

case "$choice" in
  "$lock")     exec swaylock ;;
  "$logout")   exec swaymsg exit ;;
  "$suspend")  exec systemctl suspend ;;
  "$reboot")   exec systemctl reboot ;;
  "$poweroff") exec systemctl poweroff ;;
esac
