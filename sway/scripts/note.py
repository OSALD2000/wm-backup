#!/usr/bin/python3
"""Schnellnotiz (Super+Ctrl+n): Name per ask.sh, Notiz aus der Vorlage im
Obsidian-Vault anlegen und in Obsidian oeffnen.

Eingabe:  "Titel"                  -> Notizen/Titel.md
          "Titel #idee #arbeit"    -> dazu tags: [idee, arbeit]
          "Ordner/Unter/Titel"     -> Ordner/Unter/Titel.md (ab Vault-Wurzel)
Gibt es die Notiz schon, wird sie nur geoeffnet.
Vorlage:  Templates/Schnellnotiz.md im Vault, beim ersten Aufruf angelegt und
danach in Obsidian frei aenderbar. Platzhalter wie beim Obsidian-Plugin
"Vorlagen": {{title}} {{date}} {{time}}, dazu {{tags}}.
Aufruf: note.py | note.py selftest
"""
import os
import re
import subprocess
import sys
import urllib.parse
from datetime import datetime

VAULT = os.path.expanduser("~/Documents/Obsidian Vault")
INBOX = "Notizen"  # Ziel ohne Ordner in der Eingabe
TEMPLATE = os.path.join(VAULT, "Templates", "Schnellnotiz.md")
DEFAULT = """---
erstellt: {{date}} {{time}}
tags: {{tags}}
status: offen
---

# {{title}}

## Worum geht's


## Notizen


## Naechste Schritte
- [ ]

## Links
-
"""


def parse(text):
    """-> (relativer Pfad ohne .md, Titel, Tags) oder None bei leerer Eingabe."""
    tags = re.findall(r"#([\w/-]+)", text)
    text = re.sub(r"#[\w/-]+", "", text)
    # Obsidian verbietet diese Zeichen im Dateinamen; / trennt Ordner
    parts = [re.sub(r'[*"\\<>:|?^\[\]]', "", p).strip(" .") for p in text.split("/")]
    parts = [p for p in parts if p]
    if not parts:
        return None
    rel = os.path.join(*parts) if len(parts) > 1 else os.path.join(INBOX, parts[0])
    return rel, parts[-1], tags


def render(tpl, title, tags, now):
    return (tpl.replace("{{title}}", title).replace("{{date}}", f"{now:%Y-%m-%d}")
               .replace("{{time}}", f"{now:%H:%M}").replace("{{tags}}", "[" + ", ".join(tags) + "]"))


def main():
    ask = subprocess.run([os.path.expanduser("~/.config/sway/scripts/ask.sh"), "NEUE NOTIZ"],
                         capture_output=True, text=True)
    p = parse(ask.stdout.strip()) if ask.returncode == 0 else None
    if not p:
        return
    rel, title, tags = p
    path = os.path.join(VAULT, rel + ".md")
    if not os.path.exists(TEMPLATE):
        os.makedirs(os.path.dirname(TEMPLATE), exist_ok=True)
        with open(TEMPLATE, "w") as f:
            f.write(DEFAULT)
    if not os.path.exists(path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(TEMPLATE) as f:
            tpl = f.read()
        with open(path, "x") as f:
            f.write(render(tpl, title, tags, datetime.now()))
    # sway holt das Obsidian-Fenster bei Aktivierung nicht nach vorn -> selbst fokussieren
    # ponytail: 1 s reicht, wenn Obsidian laeuft; beim Kaltstart bleibt der Fokus, wo er war
    subprocess.Popen(["sh", "-c", 'xdg-open "$1"; sleep 1; swaymsg "[app_id=obsidian] focus"',
                      "-", "obsidian://open?path=" + urllib.parse.quote(path)],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def selftest():
    assert parse("Meeting Kunde X") == ("Notizen/Meeting Kunde X", "Meeting Kunde X", [])
    assert parse("Idee App #idee #arbeit") == ("Notizen/Idee App", "Idee App", ["idee", "arbeit"])
    assert parse("Trading/Ideen/NQ Bias") == ("Trading/Ideen/NQ Bias", "NQ Bias", [])
    assert parse("../a: b?") == ("Notizen/a b", "a b", [])  # kein Ausbruch aus dem Vault
    assert parse("  ") is None and parse("#nurtag") is None
    out = render(DEFAULT, "T", ["a", "b"], datetime(2026, 10, 10, 9, 5))
    assert "erstellt: 2026-10-10 09:05" in out and "tags: [a, b]" in out and "# T" in out
    assert "tags: []" in render(DEFAULT, "T", [], datetime(2026, 1, 1))
    print("ok")


if __name__ == "__main__":
    selftest() if sys.argv[1:] == ["selftest"] else main()
