#!/usr/bin/python3
"""Missionen (Todo-Liste) fuer das eww-Fenster "mission" (Super+m).

Aufruf: todo.py watch | add (stdin) | new | edit ID | done ID | focus ID | archive ID | note ID | selftest
Daten:  ~/.local/share/missions/data.json
Freitext kommt aus rofi oder stdin, nie aus einer eww-Shell-Interpolation.
Archivieren erhaelt alle Eintraege. Obsidian-Notizen werden nur neu angelegt.
"""
import fcntl
import json
import os
import shutil
import sys
import time
import subprocess
import urllib.parse
from pathlib import Path
from datetime import date

DIR = os.path.expanduser("~/.local/share/missions")
DATA = os.path.join(DIR, "data.json")
BACKUPS = os.path.join(DIR, "backups")  # eine Kopie pro Tag, die letzten 30 bleiben


def load():
    try:
        with open(DATA) as f:
            return validate(json.load(f))
    except FileNotFoundError:
        return {"items": []}


def validate(d):
    if not isinstance(d, dict) or not isinstance(d.get("items"), list):
        raise ValueError("Ungueltige Missionen-Datei; Original bleibt erhalten.")
    ids = set()
    for i in d["items"]:
        if (not isinstance(i, dict) or type(i.get("id")) is not int or i["id"] < 1
                or i["id"] in ids or not isinstance(i.get("text"), str)
                or type(i.get("done")) is not bool
                or any(k in i and type(i[k]) is not bool for k in ("focus", "archived"))):
            raise ValueError("Ungueltiger Missionseintrag; Original bleibt erhalten.")
        ids.add(i["id"])
    return d


def save(d):
    validate(d)
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
    items = [{**i, "focus": i.get("focus", False), "archived": i.get("archived", False)}
             for i in d["items"]]
    active = [i for i in items if not i["archived"]]
    pending = [i for i in active if not i["done"]]
    done = [i for i in active if i["done"]]
    focus = [i for i in pending if i["focus"]]
    archive = [i for i in items if i["archived"]]
    return {"open": len(pending), "done": len(done), "focus": len(focus),
            "archived": len(archive), "progress": round(100 * len(done) / max(1, len(active))),
            "groups": [focus, pending, done, archive], "error": ""}


def command(d, cmd, arg):
    if cmd == "add":
        if arg:
            d["items"].append({"id": max([i["id"] for i in d["items"]] + [0]) + 1,
                               "text": arg, "done": False})
        return
    if cmd == "clear":
        for i in d["items"]:
            if i["done"]:
                i["archived"] = True
        return
    i = next((i for i in d["items"] if i["id"] == int(arg)), None)
    if i is None:
        raise ValueError("Diese Mission wurde nicht gefunden.")
    if cmd == "done":
        i["done"] = not i["done"]
        i["focus"] = False
    elif cmd == "focus":
        if i["done"] or i.get("archived"):
            raise ValueError("Nur offene Missionen koennen im Fokus stehen.")
        if not i.get("focus") and view(d)["focus"] >= 3:
            raise ValueError("Drei Missionen reichen fuer jetzt. Erst einen Fokus freigeben.")
        i["focus"] = not i.get("focus", False)
    elif cmd in ("archive", "del"):
        i["archived"] = True if cmd == "del" else not i.get("archived", False)
        i["focus"] = False
    else:
        raise ValueError("Unbekannter Befehl: " + cmd)


def prompt(initial=""):
    result = subprocess.run(["rofi", "-dmenu", "-l", "0", "-p", "Mission",
                             "-config", os.path.expanduser("~/.config/rofi/config-nord.rasi"),
                             "-filter", initial], input="", capture_output=True, text=True)
    return result.stdout.strip() if result.returncode == 0 else ""


def note(item, vault):
    if not vault.is_dir():
        raise ValueError("Obsidian-Vault nicht gefunden.")
    folder = vault / "Missionen"
    folder.mkdir(exist_ok=True)
    path = folder / f"Mission-{item['id']}.md"
    # Stabile ID: Umbenennen der Aufgabe trennt ihre Notiz nicht ab.
    try:
        with path.open("x") as f:
            f.write(f"---\nmission_id: {item['id']}\ntags: [mission]\n---\n\n"
                    f"# {item['text']}\n\n## Ziel\n\n\n## Naechste Schritte\n\n- [ ] \n\n"
                    "## Notizen & Links\n\n\n"
                    "> Aufgabenstatus und Titel verwaltest du im Missionen-Panel. "
                    "Diese Notiz bleibt frei bearbeitbar.\n")
    except FileExistsError:
        pass
    return path


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "watch"
    if cmd == "selftest":
        selftest()
        return
    os.makedirs(DIR, exist_ok=True)
    if cmd == "watch":
        watch()
        return
    arg = sys.argv[2] if len(sys.argv) > 2 else None
    if cmd == "note":
        with locked():
            item = next(i for i in load()["items"] if i["id"] == int(arg))
            path = note(item, Path.home() / "Documents/Obsidian Vault")
        subprocess.Popen(["sh", "-c", 'xdg-open "$1"; sleep 1; swaymsg "[app_id=obsidian] focus"',
                          "-", "obsidian://open?path=" + urllib.parse.quote(str(path))],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return
    if cmd == "edit":
        with locked():
            before = next(i["text"] for i in load()["items"] if i["id"] == int(arg))
        text = prompt(before)
        if not text:
            return
        with locked():
            d = load()
            item = next(i for i in d["items"] if i["id"] == int(arg))
            if item["text"] != before:
                raise ValueError("Mission wurde inzwischen bearbeitet. Bitte erneut oeffnen.")
            item["text"] = text
            save(d)
        return
    if cmd == "new":
        cmd, arg = "add", prompt()
    elif cmd == "add":
        arg = sys.stdin.read().strip()
    if cmd == "add" and not arg:
        return
    with locked():
        d = load()
        command(d, cmd, arg)
        save(d)


def watch():
    """Gibt den Stand aus, sobald sich die Datei aendert (deflisten in eww)."""
    last = None
    while True:
        try:
            m = os.path.getmtime(DATA)
        except FileNotFoundError:
            m = 0
        if m != last:
            try:
                state = view(load())
            except (ValueError, OSError) as e:
                state = view({"items": []})
                state["error"] = str(e)
            print(json.dumps(state, ensure_ascii=False), flush=True)
            last = m
        time.sleep(0.5)


class locked:
    def __enter__(self):
        self.f = open(os.path.join(DIR, ".lock"), "w")
        fcntl.flock(self.f, fcntl.LOCK_EX)

    def __exit__(self, *a):
        self.f.close()


def selftest():
    import copy
    import tempfile
    d = {"items": [{"id": 7, "text": "Bestehend", "done": True}], "extra": "behalten"}
    original = copy.deepcopy(d)
    view(d)
    assert d == original
    command(d, "add", "Bericht 'Q3'; $(false) λEOF")
    command(d, "focus", "8")
    assert view(d)["focus"] == 1
    command(d, "done", "8")
    assert view(d)["focus"] == 0 and view(d)["done"] == 2
    command(d, "clear", None)
    assert len(d["items"]) == 2 and view(d)["archived"] == 2
    command(d, "archive", "8")
    assert d["items"][1]["done"] and not d["items"][1]["archived"]
    command(d, "del", "8")
    assert len(d["items"]) == 2
    for n in range(4):
        command(d, "add", f"Aufgabe {n}")
    for n in (9, 10, 11):
        command(d, "focus", str(n))
    try:
        command(d, "focus", "12")
        raise AssertionError("Fokuslimit fehlt")
    except ValueError:
        pass
    assert d["items"][0]["text"] == original["items"][0]["text"] and d["extra"] == "behalten"
    for invalid in ({}, {"items": [d["items"][0]] * 2}, {"items": [{"id": "x"}]}):
        try:
            validate(invalid)
            raise AssertionError("Validierung fehlt")
        except ValueError:
            pass
    with tempfile.TemporaryDirectory() as tmp:
        path = note(d["items"][1], Path(tmp))
        assert path.parent == Path(tmp) / "Missionen"
        path.write_text("Meine eigenen Notizen")
        assert note(d["items"][1], Path(tmp)).read_text() == "Meine eigenen Notizen"
    print("selftest ok: Bestand, Archiv, Fokuslimit, Validierung, Notizschutz")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, StopIteration) as e:
        message = str(e) or "Mission nicht gefunden."
        print(message, file=sys.stderr)
        subprocess.run(["notify-send", "Missionen", message], check=False)
        sys.exit(1)
