// Kommandozeile der Befehlsleiste (Super+f): Eingabe decodieren. Reine Funktionen
// ohne Quickshell, geteilt von CommandBar.qml, tests/nav.cjs und tools/nav-trainer.html
// (deshalb ohne .pragma und ohne export: laeuft in QML, node und Browser).
//
// Grammatik: [m] [Bildschirm] [Workspace] Fenster, Teile durch ein Leerzeichen
//   getrennt, von rechts gelesen: letzter Teil = Fenster, davor Workspace, davor
//   Bildschirm. Endet die Eingabe auf Leerzeichen, ist kein Fenster gemeint.
//   Leerer Teil (zwei Leerzeichen) = der aktuelle Bildschirm / sichtbare Workspace.
//   Bildschirm a s d (links, Mitte, Laptop), Workspace a s d f g h j k l ö = 1-10.
//   Fenster 1-10 = a…ö, 11 = aa, 12 = as … 20 = aö, 21 = sa … (Codes bleiben
//   gleich, wenn Fenster dazukommen). Erst Enter fuehrt aus, vorher ist offen,
//   was ein Buchstabe meint (d = Fenster 3, "d " = Workspace 3, "d f " = D4).
//   m vorne = das aktive Fenster verschieben, dann gibt es keinen Fensterteil
//   ("m a f" = "m a f " = nach A4, "m a  " = auf den sichtbaren von A).
// "#wort arg …" = Befehl aus commands/commands.json, erst mit Enter (cmd/parse).

var KEYS = "asdfghjklö"

// Code fuer Fenster i (ab 0)
function code(i) {
    return i < 10 ? KEYS[i] : KEYS[Math.floor(i / 10) - 1] + KEYS[i % 10]
}

// ctx = { screens: vorhandene Kuerzel, z. B. "asd", here: Kuerzel des
// fokussierten Bildschirms, wins(screen, ws): Fensterliste, ws 0 = sichtbarer }
// -> { cmd (Text nach "#", sonst null), move, screen ("" = here), ws (1-10, 0 = sichtbarer),
//      code (getippter Fenstercode), match (Index des Fensters mit genau diesem
//      Code, sonst -1), error (Eingabe passt nicht) }
function decode(typed, ctx) {
    var r = { cmd: null, move: false, screen: "", ws: 0, code: "", match: -1, error: false }
    if (typed[0] === "#") { r.cmd = typed.slice(1); return r }
    var t = typed
    if (t[0] === "m") { r.move = true; t = t.slice(t[1] === " " ? 2 : 1) }
    var p = t.split(" ")
    if (r.move && p[p.length - 1] !== "") p.push("")
    if (p.length > 3) return fail(r)
    var w = p.pop(), x = p.length ? p.pop() : "", s = p.length ? p.pop() : ""
    if (s && (s.length > 1 || ctx.screens.indexOf(s) < 0)) return fail(r)
    if (x && (x.length > 1 || KEYS.indexOf(x) < 0)) return fail(r)
    r.screen = s; r.ws = x ? KEYS.indexOf(x) + 1 : 0
    if (!w) return r
    for (var i = 0; i < w.length; i++) if (KEYS.indexOf(w[i]) < 0) return fail(r)
    r.code = w
    var n = ctx.wins(s || ctx.here, r.ws).length, longer = false
    for (var k = 0; k < n; k++) {
        if (code(k) === w) r.match = k
        else if (code(k).indexOf(w) === 0) longer = true
    }
    // passt kein Fenster, kann ein einzelner Buchstabe noch Workspace/Bildschirm werden
    if (r.match < 0 && !longer && !(w.length === 1 && !s)) return fail(r)
    return r
}

function fail(r) {
    r.error = true
    return r
}

// Enter: "win" = Fenster mit genau dem getippten Code, "go" = Workspace,
// "output" = Fokus auf den Bildschirm, "move" = aktives Fenster dorthin
// (ohne Workspace: auf den sichtbaren), "cmd" = Befehl ausfuehren (#wort),
// "" = passt nicht, "close" = zu
function enter(r) {
    if (r.cmd !== null) return r.cmd.trim() ? "cmd" : "close"
    if (r.error) return ""
    if (r.code) return r.match >= 0 && !r.move ? "win" : ""
    if (r.move) return r.screen || r.ws ? "move" : "close"
    if (r.ws) return "go"
    if (r.screen) return "output"
    return "close"
}

// Was Enter gerade taete, fuer den Hinweis rechts im Eingabefeld
function label(r) {
    var e = enter(r), at = (r.screen ? r.screen.toUpperCase() : "") + (r.ws ? r.ws % 10 : "")
    if (e === "win") return "Enter = " + (at ? at + " · " : "") + "Fenster " + (r.match + 1)
    if (e === "go") return "Enter = Workspace " + at
    if (e === "output") return "Enter = Bildschirm " + at
    if (e === "move") return "Enter = verschieben nach " + at
    return ""
}

// Backspace: ein Zeichen zurueck, "m " samt Leerzeichen
function back(typed) {
    return typed === "m " ? "" : typed.slice(0, -1)
}

// "#wort a b" (ohne "#") -> { name, args }; nur am Leerzeichen getrennt
function parse(cmd) {
    var w = cmd.trim().split(/\s+/)
    return { name: w[0] || "", args: w.slice(1) }
}

// Kuerzester Befehl zu Fenster i auf Bildschirm s, Workspace w, von here aus;
// visible = sichtbarer Workspace von s. Andere Bildschirme immer mit Workspace,
// gleich lang wie der leere Teil, aber lesbar.
function route(s, w, i, here, visible) {
    return (s !== here ? s + " " + KEYS[w - 1] + " " : w !== visible ? KEYS[w - 1] + " " : "") + code(i)
}

// Tab-Ergaenzung fuer Befehlsnamen: prefix (ohne "#") -> { text, hits } oder null
// (kein Treffer). Ein Treffer = ganzer Name + " ", mehrere = gemeinsamer Anfang;
// ergaenzt der nichts mehr, blaettert die Leiste per Tab durch hits.
function complete(prefix, names) {
    var hits = names.filter(function (n) { return n.indexOf(prefix) === 0 }).sort()
    if (!hits.length) return null
    if (hits.length === 1) return { text: hits[0] + " ", hits: hits }
    var p = hits[0]
    hits.forEach(function (h) { while (h.indexOf(p) !== 0) p = p.slice(0, -1) })
    return { text: p, hits: hits }
}
