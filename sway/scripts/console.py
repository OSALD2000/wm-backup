#!/usr/bin/python3
"""Konsole (Super+Shift+Tab): cool-retro-term im Scratchpad, Look je Theme.

Das Design steht in ~/.config/cool-retro-term/profile.json (Repo:
cool-retro-term/profile.json, jedes Theme hat sein eigenes). cool-retro-term
liest Profile nur aus seiner Qt-SQLite-Datenbank -> vor jedem Start wird
profile.json dort als eigenes Profil PROFILE eingetragen und mit --profile
geladen. So gewinnt immer die Datei aus dem Repo.

Aufruf: console.py         einblenden/ausblenden, beim ersten Mal starten
        console.py dump    aktuelles Design aus cool-retro-term nach
                           profile.json (nach Einstellen per Rechtsklick ->
                           Settings, beim Bauen eines Themes; vorher die
                           Konsole schliessen, das Programm speichert beim Beenden)
        console.py selftest
"""
import json
import os
import sqlite3
import subprocess
import sys

APP_ID = "cool-retro-term.cool-retro-term"  # fest, cool-retro-term kennt kein --class
PROFILE = "wm-theme"
PROFILE_FILE = os.path.expanduser("~/.config/cool-retro-term/profile.json")
# Qt LocalStorage: Dateiname = md5 des DB-Namens "coolretroterm1", also fest
DB_DIR = os.path.expanduser("~/.local/share/cool-retro-term/cool-retro-term/QML/OfflineStorage/Databases")
DB = os.path.join(DB_DIR, "27e743fe85b8912a46804fed99e8a9ab.sqlite")
INI = "[General]\nDescription=StorageDatabase\nDriver=QSQLITE\nEstimatedSize=100000\nName=coolretroterm1\nVersion=1.0\n"


def with_profile(customs, obj_string):
    """-> Liste der eigenen Profile, PROFILE durch obj_string ersetzt."""
    rest = [p for p in customs if p.get("text") != PROFILE]
    return rest + [{"text": PROFILE, "obj_string": obj_string, "builtin": False}]


def db():
    os.makedirs(DB_DIR, exist_ok=True)
    if not os.path.exists(DB[:-len("sqlite")] + "ini"):  # erster Start ueberhaupt
        with open(DB[:-len("sqlite")] + "ini", "w") as f:
            f.write(INI)
    c = sqlite3.connect(DB)
    c.execute("CREATE TABLE IF NOT EXISTS settings(setting TEXT UNIQUE, value TEXT)")
    return c


def install_profile():
    with open(PROFILE_FILE) as f:
        obj = json.dumps(json.load(f))
    with db() as c:
        row = c.execute("SELECT value FROM settings WHERE setting='_CUSTOM_PROFILES'").fetchone()
        customs = with_profile(json.loads(row[0]) if row else [], obj)
        c.execute("INSERT OR REPLACE INTO settings VALUES ('_CUSTOM_PROFILES', ?)", (json.dumps(customs),))


def toggle():
    if subprocess.run(["swaymsg", f'[app_id="{APP_ID}"] scratchpad show'],
                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
        return
    if os.path.exists(PROFILE_FILE):
        install_profile()
    os.execvp("cool-retro-term", ["cool-retro-term", "--profile", PROFILE])


def dump():
    with db() as c:
        row = c.execute("SELECT value FROM settings WHERE setting='_CURRENT_PROFILE'").fetchone()
    if not row:
        sys.exit("kein gespeichertes Design: cool-retro-term einmal einstellen und schliessen")
    with open(PROFILE_FILE, "w") as f:
        json.dump(json.loads(row[0]), f, indent=2, sort_keys=True)
        f.write("\n")
    print("gespeichert:", PROFILE_FILE)


def selftest():
    old = [{"text": "Mein", "obj_string": "{}", "builtin": False},
           {"text": PROFILE, "obj_string": '{"a": 1}', "builtin": False}]
    new = with_profile(old, '{"a": 2}')
    assert [p["text"] for p in new] == ["Mein", PROFILE], new
    assert new[-1]["obj_string"] == '{"a": 2}'
    assert with_profile([], "{}")[0]["text"] == PROFILE
    print("ok")


if __name__ == "__main__":
    {"dump": dump, "selftest": selftest}.get(sys.argv[1] if len(sys.argv) > 1 else "", toggle)()
