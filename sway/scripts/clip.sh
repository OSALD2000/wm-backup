#!/bin/sh
# Zwischenablage (Super+Shift+V): copyq-Verlauf im HL2-Hauptmenue-Stil wie
# powermenu.sh. copyq bleibt der Speicher (laeuft per exec_always), rofi ist
# nur die Anzeige. Enter = Eintrag wieder in die Zwischenablage, Strg+V fuegt
# ihn dann ein. Eine Zeile je Eintrag, Zeilenumbrueche zu Leerzeichen.
# ponytail: kein automatisches Einfuegen (wtype); wer das will, haengt
# "wtype -M ctrl v" ans Ende.
set -e

i=$(copyq eval -- '
  for (var i = 0; i < size(); i++) {
    var t = str(read(i)).replace(/\s+/g, " ").trim();
    print((t ? t.slice(0, 140) : "[ BILD ]") + "\n");
  }' |
  rofi -dmenu -i -p "" -no-custom -format i \
       -config ~/.config/rofi/config-nord.rasi \
       -theme-str 'mainbox { padding: 18% 30% 0 7%; }
                   textbox-title { str: "λ  ZWISCHENABLAGE"; }
                   listview { lines: 12; spacing: 2px; }
                   element { padding: 4px 12px; }
                   element-text { font: "Verdana Bold 12"; }')

[ -n "$i" ] && exec copyq select "$i"
