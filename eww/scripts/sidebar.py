#!/usr/bin/python3
"""Fensterliste links (eww-Fenster "sidebar"), eine pro Monitor.

Zeigt die Fenster des sichtbaren Workspaces dieses Monitors, in Baum-Reihenfolge,
erst ab MIN_WINDOWS Fenstern (sonst ist das eww-Fenster zu und gibt den Platz frei).
Super+q / Super+Ctrl+q laufen mit next/prev genau durch diese Liste im Kreis und
verlassen den Monitor nie (sways `focus next` springt am Ende raus).

Aufruf: sidebar.py watch       eww neu starten (HUD oeffnen), dann bei jeder
                               Aenderung `eww update wins=...` und Sidebars
                               oeffnen/schliessen. Laeuft per exec_always, ein
                               neuer Start beendet den alten (PIDFILE).
        sidebar.py next|prev   naechstes/vorheriges Fenster der Liste fokussieren
        sidebar.py toggle      Sidebar an/aus (Super+b)
        sidebar.py selftest
"""
import configparser
import glob
import json
import os
import re
import subprocess
import sys
import time

APP_DIRS = [os.path.expanduser("~/.local/share/applications"),
            "/usr/share/applications",
            "/var/lib/snapd/desktop/applications",
            "/var/lib/flatpak/exports/share/applications"]
FALLBACK = "application-x-executable"  # Icon fuer Apps ohne .desktop-Eintrag
# Icons selbst als Datei suchen und in eww fest auf 16px skalieren: per
# Icon-Name nimmt GTK die Groesse, die das Theme gerade hat -> ungleich gross.
# Reihenfolge = Vorrang; die Themes nur fuer den FALLBACK.
ICON_DIRS = [os.path.expanduser("~/.local/share/icons"), "/usr/share/icons/hicolor",
             "/usr/share/pixmaps", "/var/lib/snapd/desktop/icons",
             "/var/lib/flatpak/exports/share/icons", "/usr/share/icons/Yaru",
             "/usr/share/icons/Adwaita", "/usr/share/icons/HighContrast"]
WAYBAR_HEIGHT = 30  # = "height" in waybar/config.jsonc
MIN_WINDOWS = 2     # darunter keine Sidebar
RUN = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
PIDFILE = os.path.join(RUN, "eww-sidebar.pid")
OFF = os.path.join(RUN, "eww-sidebar.off")  # existiert = Sidebar per Super+b aus


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


def icon_index():
    """-> {Icon-Name: bester Pfad}. Je Name gewinnt das erste ICON_DIRS-Verzeichnis,
    darin SVG vor der groessten PNG (Pfade wie .../128x128/apps/x.png)."""
    best = {}
    for prio, d in enumerate(ICON_DIRS):
        for root, _, files in os.walk(d):
            m = re.search(r"/(\d+)x\d+", root)
            for f in files:
                stem, ext = os.path.splitext(f)
                if ext not in (".svg", ".png"):
                    continue
                score = (-prio, ext == ".svg", int(m.group(1)) if m else 0)
                if stem not in best or score > best[stem][0]:
                    best[stem] = (score, os.path.join(root, f))
    return {k: v[1] for k, v in best.items()}


def resolve(icon, index):
    """Icon-Name oder absoluter Pfad (Snaps) -> Pfad; unbekannt -> FALLBACK-Pfad."""
    if icon.startswith("/"):
        return icon
    return index.get(icon) or index.get(FALLBACK, "")


def visible_windows(tree, apps, index=None):
    """-> {output: [{id, name, title, focused, icon}]}: nur der sichtbare
    Workspace je Output (current_workspace), Floating-Fenster hinten dran."""
    out = {}

    def collect(node, acc):
        if node.get("pid") and node.get("type") in ("con", "floating_con"):
            app = node.get("app_id") or (node.get("window_properties") or {}).get("class") or "?"
            icon, name = apps.get(app.lower(), (FALLBACK, ""))
            acc.append({"id": node["id"], "name": name or app, "title": node.get("name") or app,
                        "focused": node.get("focused", False),
                        "icon": resolve(icon, index or {})})
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


def eww(*args):
    # DEVNULL statt capture_output: startet eww dabei den Daemon, erbt der die
    # Pipe, und capture wartet ewig
    subprocess.run(["eww", *args], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def kill_previous():
    """exec_always startet bei jedem Reload einen neuen Watcher -> alten beenden.
    Per PID-Datei statt pkill -f: das traefe auch die sh -c-Zeile von sway."""
    try:
        with open(PIDFILE) as f:
            os.kill(int(f.read()), 15)
    except (OSError, ValueError):
        pass
    with open(PIDFILE, "w") as f:
        f.write(str(os.getpid()))


def toggle():
    """Super+b: Sidebar an/aus. Der Tick weckt den Watcher, der das OFF-File liest."""
    if os.path.exists(OFF):
        os.remove(OFF)
    else:
        open(OFF, "w").close()
    subprocess.run(["swaymsg", "-t", "send_tick", "sidebar"], capture_output=True)


def watch():
    kill_previous()
    # Alle eww-Prozesse weg, nicht nur `eww kill`: ein Daemon, der seinen Socket
    # verloren hat (zwei gleichzeitige Starts), zeigt seine Fenster weiter an
    # und ist per eww nicht mehr erreichbar -> doppelte Sidebar.
    subprocess.run(["pkill", "-x", "eww"])
    time.sleep(0.3)
    eww("open-many", "hud-left", "hud-right")
    apps, index = desktop_apps(), icon_index()  # ponytail: nur beim Start; neue Apps nach Super+Shift+C
    events = subprocess.Popen(["swaymsg", "-m", "-t", "subscribe", '["window","workspace","output","tick"]'],
                              stdout=subprocess.PIPE, text=True)
    last, shown = None, set()
    while True:
        wins = visible_windows(swaymsg("-t", "get_tree"), apps, index)
        cur = json.dumps(wins)
        if cur != last:
            eww("update", "wins=" + cur)
            last = cur
        want = set() if os.path.exists(OFF) else {o for o, w in wins.items() if len(w) >= MIN_WINDOWS}
        if want != shown:
            heights = {o["name"]: o["rect"]["height"] for o in swaymsg("-t", "get_outputs")}
            for o in shown - want:
                eww("close", "sidebar-" + o)
            for o in want - shown:
                # "100%" wuerde unter die waybar reichen
                eww("open", "sidebar", "--id", "sidebar-" + o, "--arg", "screen=" + o,
                    "--arg", f"height={heights.get(o, 1080) - WAYBAR_HEIGHT}px")
            shown = want
        if not events.stdout.readline():
            return


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
    index = {"vscode": "/i/vscode.svg", "idea": "/i/idea.png", FALLBACK: "/i/fb.svg"}
    w = visible_windows(tree, apps, index)
    assert list(w) == ["DP-7", "eDP-1"] and w["eDP-1"] == [], w
    a, b, c = w["DP-7"]
    assert [x["id"] for x in w["DP-7"]] == [1, 2, 3]  # 5 liegt auf unsichtbarem WS
    assert (a["icon"], a["name"]) == ("/i/vscode.svg", "Visual Studio Code")
    assert (b["name"], b["focused"]) == ("IntelliJ", True)
    assert (c["icon"], c["name"]) == ("/snap/x.png", "snap")
    assert visible_windows(tree, {}, index)["DP-7"][0]["icon"] == "/i/fb.svg"
    assert resolve("gibtsnicht", {}) == ""
    assert focused_output(tree) == "DP-7"
    assert step(w["DP-7"], 1) == 3 and step(w["DP-7"], -1) == 1
    assert step(w["DP-7"][:2], 1) == 1  # im Kreis
    assert step([], 1) is None
    print("ok")


if __name__ == "__main__":
    {"watch": watch, "next": lambda: cycle(1), "prev": lambda: cycle(-1),
     "toggle": toggle,
     "selftest": selftest}[sys.argv[1]]()
