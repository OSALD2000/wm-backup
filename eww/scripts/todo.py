#!/usr/bin/python3
"""Missionen (Todo-Liste) fuer das eww-Fenster "mission" (Super+m).

Aufruf: todo.py watch | add (Text auf stdin) | done ID | del ID | clear | selftest
Daten:  ~/.local/share/missions/data.json
Der Text kommt per stdin, nicht als Argument: eww setzt {} ungeschuetzt in die
Shell-Zeile, ein ' im Text wuerde sie sonst zerbrechen (Heredoc in eww.yuck).
"""
import fcntl
import json
import os
import shutil
import sys
import time
from datetime import date

DIR = os.path.expanduser("~/.local/share/missions")
DATA = os.path.join(DIR, "data.json")
BACKUPS = os.path.join(DIR, "backups")  # eine Kopie pro Tag, die letzten 30 bleiben


def load():
    try:
        with open(DATA) as f:
            return json.load(f)
    except FileNotFoundError:
        return {"items": []}


def save(d):
    os.makedirs(BACKUPS, exist_ok=True)
    target = os.path.join(BACKUPS, f"{date.today()}.json")
    if os.path.exists(DATA) and not os.path.exists(target):
        shutil.copy2(DATA, target)
        for old in sorted(os.listdir(BACKUPS))[:-30]:
            os.remove(os.path.join(BACKUPS, old))
    with open(DATA + ".tmp", "w") as f:
        json.dump(d, f, indent=1, ensure_ascii=False)
    os.replace(DATA + ".tmp", DATA)


def view(d):
    """-> eww-JSON: offene Ziele zuerst (nummeriert), erfuellte hinten."""
    items = sorted(d["items"], key=lambda i: i["done"])
    return {"open": sum(not i["done"] for i in items),
            "done": sum(i["done"] for i in items),
            "items": [{"id": i["id"], "nr": f"{k + 1:02d}", "text": i["text"], "done": i["done"]}
                      for k, i in enumerate(items)]}


def command(d, cmd, arg):
    if cmd == "add":
        if arg:
            d["items"].append({"id": max([i["id"] for i in d["items"]] + [0]) + 1, "text": arg, "done": False})
    elif cmd == "done":
        for i in d["items"]:
            if i["id"] == int(arg):
                i["done"] = not i["done"]
    elif cmd == "del":
        d["items"] = [i for i in d["items"] if i["id"] != int(arg)]
    elif cmd == "clear":
        d["items"] = [i for i in d["items"] if not i["done"]]


def watch():
    """Gibt den Stand aus, sobald sich die Datei aendert (deflisten in eww)."""
    last = None
    while True:
        try:
            m = os.path.getmtime(DATA)
        except FileNotFoundError:
            m = 0
        if m != last:
            print(json.dumps(view(load()), ensure_ascii=False), flush=True)
            last = m
        time.sleep(0.5)


class locked:
    def __enter__(self):
        self.f = open(os.path.join(DIR, ".lock"), "w")
        fcntl.flock(self.f, fcntl.LOCK_EX)

    def __exit__(self, *a):
        self.f.close()


def selftest():
    d = {"items": []}
    for t in ("Bericht 'Q3'; rm -rf ~", "Steuer", ""):
        command(d, "add", t)
    assert [i["text"] for i in d["items"]] == ["Bericht 'Q3'; rm -rf ~", "Steuer"]  # leer = nichts
    command(d, "done", "1")
    v = view(d)
    assert (v["open"], v["done"]) == (1, 1) and [i["id"] for i in v["items"]] == [2, 1], v
    assert v["items"][0]["nr"] == "01"
    command(d, "done", "1")
    assert not d["items"][0]["done"]  # zweiter Klick = wieder offen
    command(d, "done", "2")
    command(d, "clear", None)
    assert [i["id"] for i in d["items"]] == [1]
    command(d, "add", "neu")
    assert d["items"][-1]["id"] == 2
    command(d, "del", "1")
    assert [i["text"] for i in d["items"]] == ["neu"]
    print("selftest ok")


if __name__ == "__main__":
    os.makedirs(DIR, exist_ok=True)
    cmd = sys.argv[1] if len(sys.argv) > 1 else "watch"
    if cmd == "watch":
        watch()
    elif cmd == "selftest":
        selftest()
    else:
        arg = sys.stdin.read().strip() if cmd == "add" else (sys.argv[2] if len(sys.argv) > 2 else None)
        with locked():
            d = load()
            command(d, cmd, arg)
            save(d)
