#!/usr/bin/python3
"""Tickets als Markdown-Dateien im Obsidian-Vault (Quelle der Wahrheit).

Aufruf: ticket.py list [PROJ] [STATUS] | show KEY | new PROJ TITEL [-p PRIO] [-l LABEL]... [-s STATUS]
        | set KEY FELD WERT | selftest
FELD:   status | prio | title | project | labels | archived (ja|nein)
Datei:  <Vault>/Tickets/<PROJ>/<PROJ>-<N> <Titel>.md, Frontmatter status prio created
        archived aliases tags. Fremde Frontmatter-Zeilen und der Text bleiben byte-gleich.
Nur dieses Skript schreibt Ticket-Dateien: atomar (.tmp + os.replace) unter flock.
"""
import fcntl
import os
import re
import sys
from datetime import date
from pathlib import Path

STATUSES = ("backlog", "todo", "in-arbeit", "review", "fertig")
PRIOS = ("hoch", "mittel", "niedrig")
WIP = 3  # hoechstens so viele nicht archivierte Tickets in-arbeit (alle Projekte)
MANAGED = ("status", "prio", "created", "archived", "aliases", "tags")
DEFAULT_BODY = """## Ziel

## Naechste Schritte
- [ ]

## Notizen & Links
"""
FILE_RE = re.compile(r"^([A-Z][A-Z0-9]*)-(\d+) (.+)\.md$")
PROJ_RE = re.compile(r"^[A-Z][A-Z0-9]*$")
KEY_RE = re.compile(r"^([A-Za-z_][\w-]*):(.*)$")
VAULT = ROOT = TEMPLATE = LAST = None


def use_vault(vault, last=None):
    global VAULT, ROOT, TEMPLATE, LAST
    VAULT = Path(vault)
    ROOT = VAULT / "Tickets"
    TEMPLATE = VAULT / "Templates" / "Ticket.md"
    LAST = Path(last) if last else Path.home() / ".local/state/tickets-last"


use_vault(Path.home() / "Private/obsidian-vault")


class locked:
    """flock auf Tickets/.lock (legt Tickets/ an). Nicht verschachteln."""
    def __enter__(self):
        ROOT.mkdir(parents=True, exist_ok=True)
        self.f = open(ROOT / ".lock", "w")
        fcntl.flock(self.f, fcntl.LOCK_EX)

    def __exit__(self, *a):
        self.f.close()


# --- Frontmatter ---------------------------------------------------------

def split(text):
    """-> (Frontmatter-Zeilen ohne ---, Text danach unveraendert)."""
    if not text.startswith("---\n"):
        return [], text
    pos, lines = 4, []
    while pos <= len(text):
        nl = text.find("\n", pos)
        end = len(text) if nl < 0 else nl
        line = text[pos:end]
        if line.rstrip() == "---":
            return lines, text[end + 1:]
        if nl < 0:
            break
        lines.append(line)
        pos = nl + 1
    raise ValueError("Frontmatter ohne schliessendes ---")


def _unq(v):
    v = v.strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
        return v[1:-1]
    return v


def _block_end(lines, i):
    """Index hinter dem Block der Schluesselzeile i (eingerueckte bzw. `- `-Zeilen)."""
    j = i + 1
    while j < len(lines) and (lines[j][:1] in (" ", "\t") or lines[j].startswith("- ") or lines[j] == "-"):
        j += 1
    return j


def parse_fm(lines):
    """key: wert, [a, b], Blockliste -> dict (Werte str oder list[str])."""
    out, i = {}, 0
    while i < len(lines):
        m = KEY_RE.match(lines[i])
        if not m:
            i += 1
            continue
        k, v = m.group(1), m.group(2).strip()
        j = _block_end(lines, i)
        if v.startswith("[") and v.endswith("]"):
            out[k] = [_unq(x) for x in v[1:-1].split(",") if x.strip()]
        elif v == "":
            out[k] = [_unq(l.strip()[1:]) for l in lines[i + 1:j] if l.strip().startswith("-")]
        else:
            out[k] = _unq(v)
        i = j
    return out


def set_fm(lines, updates):
    """Ersetzt nur die Bloecke der genannten Schluessel; None entfernt, Fehlende werden angehaengt."""
    lines = list(lines)
    for k, v in updates.items():
        new = [] if v is None else [f"{k}: [{', '.join(v)}]" if isinstance(v, (list, tuple)) else f"{k}: {v}"]
        for i, l in enumerate(lines):
            m = KEY_RE.match(l)
            if m and m.group(1) == k:
                lines[i:_block_end(lines, i)] = new
                break
        else:
            lines += new
    return lines


def clean_title(s):
    """Obsidian-verbotene Zeichen -> Leerzeichen, hoechstens 80 Zeichen an Wortgrenze."""
    s = re.sub(r'[/\\:*?"<>|#^\[\]]', " ", s)
    s = re.sub(r"\s+", " ", s).strip(" .")
    if len(s) > 80:
        cut = s[:80]
        if s[80] != " " and " " in cut:
            cut = cut.rsplit(" ", 1)[0]
        s = cut.strip(" .")
    if not s:
        raise ValueError("Titel ist leer.")
    return s


def clean_project(p):
    p = p.strip().upper()
    if not PROJ_RE.match(p):
        raise ValueError("Projektname nur A-Z und 0-9, Beginn mit Buchstabe.")
    return p


def clean_labels(labels):
    out = []
    for l in labels:
        l = re.sub(r'[,\[\]"\'#\s]', "", l)
        if l and l not in out:
            out.append(l)
    return out


def _list(v):
    return v if isinstance(v, list) else ([v] if v else [])


# --- Lesen ---------------------------------------------------------------

def read(path):
    path = Path(path)
    m = FILE_RE.match(path.name)
    if not m:
        raise ValueError(f"{path.name}: kein Ticket-Dateiname")
    text = path.read_text()
    lines, body = split(text)
    d = parse_fm(lines)
    bad = []
    status, prio = d.get("status", "backlog"), d.get("prio", "mittel")
    if status not in STATUSES:
        bad.append(f"Status '{status}' unbekannt")
        status = "backlog"
    if prio not in PRIOS:
        bad.append(f"Prio '{prio}' unbekannt")
        prio = "mittel"
    labels = [t for t in _list(d.get("tags", [])) if t != "ticket"
              and not t.startswith(("projekt/", "status/", "prio/"))]
    check = re.findall(r"^\s*- \[( |x|X)\]", body, re.M)
    return {"key": f"{m.group(1)}-{m.group(2)}", "project": m.group(1), "num": int(m.group(2)),
            "title": m.group(3), "status": status, "prio": prio, "labels": labels,
            "archived": str(d.get("archived", "")).lower() in ("true", "ja", "yes"),
            "aliases": _list(d.get("aliases", [])),
            "check": [sum(c != " " for c in check), len(check)],
            "created": str(d.get("created", "")), "mtime": int(path.stat().st_mtime),
            "path": str(path), "body": body, "bad": "; ".join(bad)}


def scan():
    """Alle Projekte und Tickets; Probleme einzeln in `error` (nie schreiben)."""
    projects, tickets, errs, seen = [], [], [], set()
    if ROOT.is_dir():
        for d in sorted(ROOT.iterdir()):
            if d.is_dir() and PROJ_RE.match(d.name):
                projects.append(d.name)
                for f in sorted(d.glob("*.md")):
                    m = FILE_RE.match(f.name)
                    if not m or m.group(1) != d.name:
                        errs.append(f"{d.name}/{f.name}: keine Kennung {d.name}-<N>")
                        continue
                    try:
                        t = read(f)
                    except (ValueError, OSError, UnicodeDecodeError) as e:
                        errs.append(f"{d.name}/{f.name}: {e}")
                        continue
                    if t["key"] in seen:
                        errs.append(f"doppelte Kennung {t['key']}")
                    seen.add(t["key"])
                    if t["bad"]:
                        errs.append(f"{t['key']}: {t['bad']}")
                    tickets.append(t)
    wip = sum(t["status"] == "in-arbeit" and not t["archived"] for t in tickets)
    return {"projects": projects, "tickets": tickets, "wip": wip, "error": "; ".join(errs)}


def find(key, tickets):
    k = key.strip().upper()
    for t in tickets:
        if t["key"].upper() == k:
            return t
    for t in tickets:
        if k in (a.upper() for a in t["aliases"]):
            return t
    raise ValueError(f"Ticket {key} nicht gefunden.")


def next_num(project, tickets):
    pre, n = project.upper() + "-", 0
    for t in tickets:
        for k in [t["key"], *t["aliases"]]:
            m = re.fullmatch(re.escape(pre) + r"(\d+)", k.upper())
            if m:
                n = max(n, int(m.group(1)))
    return n + 1


# --- Schreiben (nur unter locked aufrufen) ----------------------------------

def _atomic(path, text):
    tmp = Path(str(path) + ".tmp")
    tmp.write_text(text)
    os.replace(tmp, path)


def _tags(project, status, prio, labels):
    return ["ticket", f"projekt/{project.lower()}", f"status/{status}", f"prio/{prio}", *labels]


def write(t, fields, title=None, project=None):
    """Schreibt die genannten Felder (+ Tags, Aliase neu), benennt um / verschiebt."""
    p = Path(t["path"])
    lines, body = split(p.read_text())
    proj, key = t["project"], t["key"]
    if project and project != proj:
        proj = project
        key = f"{proj}-{next_num(proj, scan()['tickets'])}"
    name = clean_title(title) if title else t["title"]
    fields = dict(fields)
    labels = fields.pop("labels", t["labels"])
    status, prio = fields.get("status", t["status"]), fields.get("prio", t["prio"])
    aliases = list(t["aliases"])
    for k in (t["key"], key):
        if k not in aliases:
            aliases.append(k)
    upd = {**fields, "aliases": aliases, "tags": _tags(proj, status, prio, labels)}
    new = ROOT / proj / f"{key} {name}.md"
    if new != p and new.exists():
        raise ValueError(f"{new.name} gibt es schon.")
    new.parent.mkdir(parents=True, exist_ok=True)
    _atomic(new, "---\n" + "\n".join(set_fm(lines, upd) + ["---"]) + "\n" + body)
    if new != p:
        p.unlink()
    return read(new)


def _template_body():
    if not TEMPLATE.exists():
        TEMPLATE.parent.mkdir(parents=True, exist_ok=True)
        TEMPLATE.write_text(DEFAULT_BODY)
    return split(TEMPLATE.read_text())[1]


def _check_wip(tickets, me=None):
    full = sorted((t for t in tickets if t["status"] == "in-arbeit" and not t["archived"]
                   and t["key"] != me), key=lambda t: (t["project"], t["num"]))
    if len(full) >= WIP:
        raise ValueError(f"In Arbeit ist voll ({len(full)}/{WIP}): "
                         + ", ".join(t["key"] for t in full) + ". Erst eins weiterschieben.")


def _check_enum(name, value, allowed):
    if value not in allowed:
        raise ValueError(f"{name} muss eins von {', '.join(allowed)} sein.")


def new(project, title, prio="mittel", labels=(), status="todo"):
    project, title = clean_project(project), clean_title(title)
    _check_enum("Prio", prio, PRIOS)
    _check_enum("Status", status, STATUSES)
    with locked():
        tickets = scan()["tickets"]
        if status == "in-arbeit":
            _check_wip(tickets)
        key = f"{project}-{next_num(project, tickets)}"
        body = _template_body()
        lines = set_fm([], {"status": status, "prio": prio, "created": date.today().isoformat(),
                            "aliases": [key],
                            "tags": _tags(project, status, prio, clean_labels(labels))})
        path = ROOT / project / f"{key} {title}.md"
        path.parent.mkdir(parents=True, exist_ok=True)
        _atomic(path, "---\n" + "\n".join(lines + ["---"]) + "\n\n" + body)
        LAST.parent.mkdir(parents=True, exist_ok=True)
        LAST.write_text(project + "\n")
    return key


def set_field(key, field, value):
    if field == "project":
        value = clean_project(value)
    elif field == "status":
        _check_enum("Status", value, STATUSES)
    elif field == "prio":
        _check_enum("Prio", value, PRIOS)
    elif field == "archived":
        _check_enum("archived", value, ("ja", "nein"))
    elif field not in ("title", "labels"):
        raise ValueError("Feld muss eins von status, prio, title, project, labels, archived sein.")
    with locked():
        tickets = scan()["tickets"]
        t = find(key, tickets)
        if field == "status" and value == "in-arbeit" and t["status"] != "in-arbeit":
            _check_wip(tickets, t["key"])
        if field == "title":
            r = write(t, {}, title=value)
        elif field == "project":
            r = write(t, {}, project=value)
        elif field == "labels":
            r = write(t, {"labels": clean_labels(value.split())})
        elif field == "archived":
            r = write(t, {"archived": "true" if value == "ja" else None})
        else:
            r = write(t, {field: value})
    return r["key"]


def list_lines(project=None, status=None):
    """Zeilen fuer `list`: Kennung, Status, Prio, Titel, Labels (ohne archivierte)."""
    ts = [t for t in scan()["tickets"] if not t["archived"]
          and (project is None or t["project"] == project.upper())
          and (status is None or t["status"] == status)]
    ts.sort(key=lambda t: (PRIOS.index(t["prio"]), t["project"], t["num"]))
    return [f"{t['key']:<12}{t['status']:<11}{t['prio']:<8}{t['title']}"
            + "".join(" #" + l for l in t["labels"]) for t in ts]


def main(argv):
    import argparse
    ap = argparse.ArgumentParser(prog="ticket.py")
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("list")
    s.add_argument("project", nargs="?")
    s.add_argument("status", nargs="?")
    sub.add_parser("show").add_argument("key")
    s = sub.add_parser("new")
    s.add_argument("project")
    s.add_argument("title")
    s.add_argument("-p", "--prio", default="mittel")
    s.add_argument("-l", "--label", action="append", default=[])
    s.add_argument("-s", "--status", default="todo")
    s = sub.add_parser("set")
    s.add_argument("key")
    s.add_argument("field")
    s.add_argument("value")
    sub.add_parser("selftest")
    a = ap.parse_args(argv)
    if a.cmd == "list":
        print("\n".join(list_lines(a.project, a.status)))
    elif a.cmd == "show":
        t = find(a.key, scan()["tickets"])
        print(t["path"] + "\n\n" + Path(t["path"]).read_text(), end="")
    elif a.cmd == "new":
        print(new(a.project, a.title, a.prio, a.label, a.status))
    elif a.cmd == "set":
        print(set_field(a.key, a.field, a.value))
    else:
        selftest()


def selftest():
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        use_vault(Path(tmp), Path(tmp) / "last")
        k = new("WORK", "Atlas MCP anpassen", labels=["mcp"])
        assert k == "WORK-1" and (ROOT / "WORK" / "WORK-1 Atlas MCP anpassen.md").exists()
        assert TEMPLATE.exists() and LAST.read_text().strip() == "WORK"
        t = find("work-1", scan()["tickets"])
        assert (t["status"], t["prio"], t["labels"], t["aliases"]) == ("todo", "mittel", ["mcp"], ["WORK-1"])
        assert parse_fm(split(Path(t["path"]).read_text())[0])["tags"] == ["ticket", "projekt/work", "status/todo", "prio/mittel", "mcp"]
        # WIP-Limit
        for n in range(3):
            set_field(new("WORK", f"A{n}"), "status", "in-arbeit")
        try:
            set_field("WORK-1", "status", "in-arbeit"); raise AssertionError("WIP fehlt")
        except ValueError as e:
            assert "WORK-2" in str(e) and "WORK-4" in str(e)
        # Projektwechsel + keine Wiederverwendung (Review Focus 1)
        assert set_field("WORK-4", "project", "aurora") == "AURORA-1"
        assert find("WORK-4", scan()["tickets"])["key"] == "AURORA-1"
        assert find("AURORA-1", scan()["tickets"])["aliases"] == ["WORK-4", "AURORA-1"]
        assert new("WORK", "Danach") == "WORK-5"
        # Titel mit Sonderzeichen (Review Focus 5)
        assert set_field("WORK-1", "title", "Bericht 'Q3': $(false) / λ") == "WORK-1"
        assert (ROOT / "WORK" / "WORK-1 Bericht 'Q3' $(false) λ.md").exists()
        for bad in ("???", " / ", ".."):
            try:
                clean_title(bad); raise AssertionError("leerer Titel")
            except ValueError:
                pass
        assert clean_title(".versteckt") == "versteckt" and len(clean_title("wort " * 40)) <= 80
        # Fremde Zeilen + Text byte-gleich, Obsidian-Blocklisten (Review Focus 3)
        p = Path(find("WORK-1", scan()["tickets"])["path"])
        fm, body = split(p.read_text())
        p.write_text("---\nstatus: todo\nquelle: \"Jan\"  # Kommentar\ntags:\n  - ticket\n  - mcp\naliases:\n  - WORK-1\n---\n" + body)
        set_field("WORK-1", "labels", "docs ki")
        fm2, body2 = split(p.read_text())
        assert body2 == body and 'quelle: "Jan"  # Kommentar' in fm2
        assert find("WORK-1", scan()["tickets"])["labels"] == ["docs", "ki"]
        p.write_text("---\nstatus: todo\ntags:\n---\n" + body)
        assert find("WORK-1", scan()["tickets"])["labels"] == []
        # Ungueltig + Hinweise
        p.write_text("---\nstatus: erledigt\n---\n" + body)
        t = find("WORK-1", scan()["tickets"])
        assert t["status"] == "backlog" and "erledigt" in t["bad"]
        (ROOT / "WORK" / "Neue Notiz.md").write_text("x")
        assert "Neue Notiz.md" in scan()["error"]
        assert set_field("WORK-1", "archived", "ja") and find("WORK-1", scan()["tickets"])["archived"] is True
        assert "WORK-1" not in "\n".join(list_lines("WORK"))   # archivierte nicht in list
        try:
            set_field("WORK-5", "project", "1x"); raise AssertionError("Projektname")
        except ValueError as e:
            assert "A-Z" in str(e)
        # (spaetere Tasks haengen hier weitere Asserts an; WORK-5 und AURORA-1 existieren)
    print("selftest ok: Kern (new/set/list/find, WIP, Projektwechsel, Frontmatter)")


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except (ValueError, OSError) as e:
        print(f"Fehler: {e}", file=sys.stderr)
        sys.exit(1)
