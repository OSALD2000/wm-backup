#!/bin/sh
# ask.sh TITEL — eine Eingabezeile im Menue-Stil des Themes (rofi, wie clip.sh),
# eingetippter Text auf stdout, Esc = Exit 1. Fuer journal.sh und die
# Mission-Schnelleingabe (Super+Ctrl+m).
exec rofi -dmenu -p "" -l 0 -config ~/.config/rofi/config-nord.rasi \
     -theme-str "mainbox { padding: 18% 30% 0 7%; }
                 textbox-title { str: \"λ  $1\"; }
                 entry { font: \"Verdana Bold 12\"; }" </dev/null
