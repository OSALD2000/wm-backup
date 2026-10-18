#!/bin/sh
# ask.sh TITEL — eine Eingabezeile im Menue-Stil des Themes (rofi, wie clip.sh),
# eingetippter Text auf stdout, Esc = Exit 1. Fuer journal.py und die
# Mission-Schnelleingabe (Super+Ctrl+m).
# ask.sh TITEL - — Auswahl aus den Zeilen auf stdin (park.py restore).
if [ "$2" = - ]; then l=10; else l=0; exec </dev/null; fi
exec rofi -dmenu -p "" -l $l -config ~/.config/rofi/config-nord.rasi \
     -theme-str "mainbox { padding: 18% 30% 0 7%; }
                 textbox-title { str: \"λ  $1\"; }
                 entry { font: \"Verdana Bold 12\"; }"
