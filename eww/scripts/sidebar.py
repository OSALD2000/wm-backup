#!/usr/bin/python3
"""Fensterliste links (eww-Fenster "sidebar"), eine pro Monitor.

Zeigt die Fenster des sichtbaren Workspaces dieses Monitors, in Baum-Reihenfolge.
Super+q / Super+Ctrl+q laufen mit next/prev genau durch diese Liste im Kreis und
verlassen den Monitor nie (sways `focus next` springt am Ende raus).

Aufruf: sidebar.py watch       JSON {output: [fenster, ...]} bei jeder Aenderung
        sidebar.py open        HUD + je Output eine Sidebar oeffnen
        sidebar.py next|prev   naechstes/vorheriges Fenster der Liste fokussieren
        sidebar.py selftest
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
WAYBAR_HEIGHT = 30  # = "height" in waybar/config.jsonc


def swaymsg(*args):
    return json.loads(subprocess.run(["swaymsg", "-r", *args], capture_output=True,
                                     text=True, check=True).stdout)


def desktop_apps():
    """-> {kleingeschriebener Schluessel: (Icon, Name)}. Schluessel sind Dateiname
    ohne .desktop und StartupWMClass, damit app_id und X11-class beide treffen."""
    apps = {}
    for d in reversed(APP_DIRS):  # ~/.local zuletzt -> gewinnt
        for f in glob.glob(os.path.join(d, "*.desktop")):
            p = configparser.ConfigParser(interpolation=None, strict=False)
            try:
                p.read(f, encoding="utf-8")
                e = p["Desktop Entry"]
            except (configparser.Error, KeyError, UnicodeDecodeError):
                continue
            val = (e.get("Icon") or FALLBACK, e.get("Name") or "")
            apps[os.path.basename(f)[:-8].lower()] = val
            if e.get("StartupWMClass"):
                apps[e["StartupWMClass"].lower()] = val
    return apps


def visible_windows(tree, apps):
    """-> {output: [{id, name, title, focused, icon, path}]}: nur der sichtbare
    Workspace je Output (current_workspace), Floating-Fenster hinten dran."""
    out = {}

    def collect(node, acc):
        if node.get("pid") and node.get("type") in ("con", "floating_con"):
            app = node.get("app_id") or (node.get("window_properties") or {}).get("class") or "?"
            icon, name = apps.get(app.lower(), (FALLBACK, ""))
            is_path = icon.startswith("/")  # Snaps: absoluter Pfad -> :path statt :icon
            acc.append({"id": node["id"], "name": name or app, "title": node.get("name") or app,
                        "focused": node.get("focused", False),
                        "icon": "" if is_path else icon, "path": icon if is_path else ""})
        for child in node.get("nodes", []) + node.get("floating_nodes", []):
            collect(child, acc)

    for o in tree.get("nodes", []):
        if o.get("name") == "__i3":  # Scratchpad
            continue
        acc = out.setdefault(o["name"], [])
        for ws in o.get("nodes", []):
            if ws.get("name") == o.get("current_workspace"):
                collect(ws, acc)
    return out


def focused_output(tree):
    def has_focus(n):
        return n.get("focused") or any(has_focus(c) for c in n.get("nodes", []) + n.get("floating_nodes", []))
    return next((o["name"] for o in tree.get("nodes", []) if has_focus(o)), None)


def step(wins, delta):
    """-> id des Fensters delta Schritte weiter, im Kreis; None bei leerer Liste."""
    if not wins:
        return None
    i = next((k for k, w in enumerate(wins) if w["focused"]), -1)
    return wins[(i + delta) % len(wins)]["id"]


def cycle(delta):
    tree = swaymsg("-t", "get_tree")
    wid = step(visible_windows(tree, {}).get(focused_output(tree), []), delta)
    if wid is not None:
        subprocess.run(["swaymsg", f"[con_id={wid}] focus"], capture_output=True)


def watch():
    apps = desktop_apps()  # ponytail: nur beim Start; neu installierte Apps nach Super+Shift+C
    events = subprocess.Popen(["swaymsg", "-m", "-t", "subscribe", '["window","workspace"]'],
                              stdout=subprocess.PIPE, text=True)
    last = None
    while True:
        cur = json.dumps(visible_windows(swaymsg("-t", "get_tree"), apps))
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
            wid = "sidebar-" + o["name"]
            # "100%" wuerde unter die waybar reichen und sie verdecken
            h = o["rect"]["height"] - WAYBAR_HEIGHT
            cmd += [f"sidebar:{wid}", "--arg", f"{wid}:screen={o['name']}",
                    "--arg", f"{wid}:height={h}px"]
    # DEVNULL statt capture_output: der eww-Daemon erbt die Pipe, capture wartet sonst ewig
    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def selftest():
    def con(i, app, focused=False, typ="con", **kw):
        return {"type": typ, "pid": i, "id": i, "app_id": app, "name": f"t{i}", "focused": focused, **kw}
    tree = {"type": "root", "nodes": [
        {"type": "output", "name": "__i3", "nodes": [{"type": "workspace", "nodes": [con(9, "x")]}]},
        {"type": "output", "name": "DP-7", "current_workspace": "23:i3", "nodes": [
            {"type": "workspace", "name": "21:i1", "nodes": [con(5, "hidden")]},
            {"type": "workspace", "name": "23:i3", "nodes": [
                {"type": "con", "nodes": [con(1, "code"), con(2, None, True,
                                           window_properties={"class": "jetbrains-idea"})]}],
             "floating_nodes": [con(3, "snap", typ="floating_con")]}]},
        {"type": "output", "name": "eDP-1", "current_workspace": "31:o1", "nodes": [
            {"type": "workspace", "name": "31:o1", "nodes": []}]}]}
    apps = {"code": ("vscode", "Visual Studio Code"), "jetbrains-idea": ("idea", "IntelliJ"),
            "snap": ("/snap/x.png", "")}
    w = visible_windows(tree, apps)
    assert list(w) == ["DP-7", "eDP-1"] and w["eDP-1"] == [], w
    a, b, c = w["DP-7"]
    assert [x["id"] for x in w["DP-7"]] == [1, 2, 3]  # 5 liegt auf unsichtbarem WS
    assert (a["icon"], a["name"]) == ("vscode", "Visual Studio Code")
    assert (b["name"], b["focused"]) == ("IntelliJ", True)
    assert (c["icon"], c["path"], c["name"]) == ("", "/snap/x.png", "snap")
    assert visible_windows(tree, {})["DP-7"][0]["icon"] == FALLBACK
    assert focused_output(tree) == "DP-7"
    assert step(w["DP-7"], 1) == 3 and step(w["DP-7"], -1) == 1
    assert step(w["DP-7"][:2], 1) == 1  # im Kreis
    assert step([], 1) is None
    print("ok")


if __name__ == "__main__":
    {"watch": watch, "open": open_bars, "next": lambda: cycle(1), "prev": lambda: cycle(-1),
     "selftest": selftest}[sys.argv[1]]()
