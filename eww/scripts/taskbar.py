#!/usr/bin/python3
"""Taskbar fuer die untere eww-Leiste: alle Fenster je Monitor, auch versteckte.

waybar's wlr/taskbar verliert Fenster, die hinter einem Tab oder auf einem
unsichtbaren Workspace liegen (Sway meldet sie keinem Output mehr). Hier kommt
die Zuordnung direkt aus dem Sway-Baum.

Aufruf: taskbar.py watch     JSON {output: [fenster, ...]} bei jeder Aenderung
        taskbar.py open      HUD + je Output ein eww-Fenster "taskbar" oeffnen
        taskbar.py selftest
"""
import configparser
import glob
import json
import os
import subprocess
import sys

APP_DIRS = [os.path.expanduser("~/.local/share/applications"),
            "/usr/share/applications",
            "/var/lib/snapd/desktop/applications",
            "/var/lib/flatpak/exports/share/applications"]
FALLBACK = "application-x-executable"  # Icon fuer Apps ohne .desktop-Eintrag


def swaymsg(*args):
    return json.loads(subprocess.run(["swaymsg", "-r", *args], capture_output=True,
                                     text=True, check=True).stdout)


def desktop_icons():
    """-> {kleingeschriebener Schluessel: Icon}. Schluessel sind Dateiname ohne
    .desktop und StartupWMClass, damit app_id und X11-class beide treffen."""
    icons = {}
    for d in reversed(APP_DIRS):  # ~/.local zuletzt -> gewinnt
        for f in glob.glob(os.path.join(d, "*.desktop")):
            p = configparser.ConfigParser(interpolation=None, strict=False)
            try:
                p.read(f, encoding="utf-8")
                e = p["Desktop Entry"]
            except (configparser.Error, KeyError, UnicodeDecodeError):
                continue
            if not e.get("Icon"):
                continue
            icons[os.path.basename(f)[:-8].lower()] = e["Icon"]
            if e.get("StartupWMClass"):
                icons[e["StartupWMClass"].lower()] = e["Icon"]
    return icons


def icon_for(app, icons):
    """-> (icon, is_path). Absolute Pfade (Snaps) gehen an :path, Namen an :icon."""
    icon = icons.get(app.lower(), FALLBACK)
    return icon, icon.startswith("/")


def windows(tree, icons):
    """-> {output: [{id, app, title, focused, icon, path}]} in Baum-Reihenfolge."""
    out = {}

    def walk(node, output):
        if node.get("type") == "output":
            output = node["name"]
        if node.get("pid") and node.get("type") in ("con", "floating_con"):
            app = node.get("app_id") or (node.get("window_properties") or {}).get("class") or "?"
            icon, is_path = icon_for(app, icons)
            out.setdefault(output, []).append({
                "id": node["id"], "app": app, "title": node.get("name") or app,
                "focused": node.get("focused", False),
                "icon": "" if is_path else icon, "path": icon if is_path else ""})
        for child in node.get("nodes", []) + node.get("floating_nodes", []):
            walk(child, output)

    walk(tree, None)
    out.pop("__i3", None)  # Scratchpad
    return out


def watch():
    icons = desktop_icons()  # ponytail: nur beim Start; neu installierte Apps nach Super+Shift+C
    events = subprocess.Popen(["swaymsg", "-m", "-t", "subscribe", '["window","workspace"]'],
                              stdout=subprocess.PIPE, text=True)
    last = None
    while True:
        cur = json.dumps(windows(swaymsg("-t", "get_tree"), icons))
        if cur != last:
            print(cur, flush=True)
            last = cur
        if not events.stdout.readline():
            return


def open_bars():
    """Alle eww-Fenster in EINEM Aufruf: mehrere eww-Aufrufe gleichzeitig starten
    sonst je einen eigenen Daemon, und nur einer gewinnt."""
    # ponytail: nur bei Start/Reload, nach Hotplug Super+Shift+C
    cmd = ["eww", "open-many", "hud-left", "hud-right"]
    for o in swaymsg("-t", "get_outputs"):
        if o["active"]:
            wid = "taskbar-" + o["name"]
            cmd += [f"taskbar:{wid}", "--arg", f"{wid}:screen={o['name']}"]
    # DEVNULL statt capture_output: der eww-Daemon erbt die Pipe, capture wartet sonst ewig
    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def selftest():
    tree = {"type": "root", "nodes": [
        {"type": "output", "name": "__i3", "nodes": [{"type": "con", "pid": 1, "id": 9, "app_id": "x"}]},
        {"type": "output", "name": "DP-7", "nodes": [{"type": "workspace", "nodes": [
            {"type": "con", "pid": 2, "id": 1, "app_id": "code", "name": "a", "focused": True},
            {"type": "con", "pid": 3, "id": 2, "app_id": None,
             "window_properties": {"class": "jetbrains-idea"}, "name": "b"}],
            "floating_nodes": [{"type": "floating_con", "pid": 4, "id": 3, "app_id": "snap", "name": ""}]}]}]}
    icons = {"code": "vscode", "jetbrains-idea": "idea", "snap": "/snap/x.png"}
    w = windows(tree, icons)
    assert list(w) == ["DP-7"], w
    a, b, c = w["DP-7"]
    assert (a["icon"], a["focused"]) == ("vscode", True)
    assert b["app"] == "jetbrains-idea" and b["icon"] == "idea"
    assert (c["icon"], c["path"], c["title"]) == ("", "/snap/x.png", "snap")
    assert icon_for("unbekannt", icons) == (FALLBACK, False)
    print("ok")


if __name__ == "__main__":
    {"watch": watch, "open": open_bars, "selftest": selftest}[sys.argv[1]]()
