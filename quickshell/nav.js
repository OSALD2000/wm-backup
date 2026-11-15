// Kommandozeile der Befehlsleiste (Super+f): Eingabe decodieren. Reine Funktionen
// ohne Quickshell, geteilt von CommandBar.qml, tests/nav.cjs und tools/nav-trainer.html
// (deshalb ohne .pragma und ohne export: laeuft in QML, node und Browser).
//
// Grammatik: [m] [b + Bildschirm] [w + Workspace] [Fenstercode]
//   Bildschirm a s d (links, Mitte, Laptop), fehlt b = der aktuelle.
//   Workspace a s d f g h j k l ö = 1-10, fehlt w = der sichtbare.
//   Fenster 1-10 = a…ö, 11 = aa, 12 = as … 20 = aö, 21 = sa … (Codes bleiben
//   gleich, wenn Fenster dazukommen). Ist ein Code zugleich Anfang eines
//   laengeren (a bei 11+ Fenstern), wartet er ohne Timeout: Enter = a, aa = 11.
//   m = das aktive Fenster verschieben statt hingehen.
// ":wort arg …" = Befehl aus commands/commands.json, erst mit Enter (cmd/parse).

var KEYS = "asdfghjklö"

// Code fuer Fenster i (ab 0)
function code(i) {
    return i < 10 ? KEYS[i] : KEYS[Math.floor(i / 10) - 1] + KEYS[i % 10]
}

// ctx = { screens: vorhandene Kuerzel, z. B. "asd", here: Kuerzel des
// fokussierten Bildschirms, wins(screen, ws): Fensterliste, ws 0 = sichtbarer }
// -> { cmd (Text nach ":", sonst null), move, screen ("" = here), ws (1-10, 0 = sichtbarer), code (getippter
//      Fenstercode), wait ("b"/"w": Buchstabe dazu fehlt), match (Index des
//      Fensters mit genau diesem Code, sonst -1), win (= match, sobald kein
//      laengerer Code passt, sonst -1), error (Taste passt nicht) }
function decode(typed, ctx) {
    var r = { cmd: null, move: false, screen: "", ws: 0, code: "", wait: "", match: -1, win: -1, error: false }
    if (typed[0] === ":") { r.cmd = typed.slice(1); return r }
    for (var i = 0; i < typed.length; i++) {
        var c = typed[i]
        if (r.wait === "b") {
            if (ctx.screens.indexOf(c) < 0) return fail(r)
            r.screen = c; r.wait = ""
        } else if (r.wait === "w") {
            if (KEYS.indexOf(c) < 0) return fail(r)
            r.ws = KEYS.indexOf(c) + 1; r.wait = ""
        } else if (r.win >= 0 || (r.move && r.ws)) return fail(r)  // schon fertig
        else if (c === "m" && i === 0) r.move = true
        else if (c === "b" && !r.screen && !r.ws && !r.code) r.wait = "b"
        else if (c === "w" && !r.ws && !r.code) r.wait = "w"
        else if (KEYS.indexOf(c) >= 0 && !r.move) {
            r.code += c
            var n = ctx.wins(r.screen || ctx.here, r.ws).length, longer = false
            r.match = -1
            for (var k = 0; k < n; k++) {
                var s = code(k)
                if (s === r.code) r.match = k
                else if (s.indexOf(r.code) === 0) longer = true
            }
            if (r.match < 0 && !longer) return fail(r)
            if (!longer) r.win = r.match
        } else return fail(r)
    }
    return r
}

function fail(r) {
    r.error = true
    return r
}

// Was nach einer Taste passiert (prev/r = decode vorher/nachher):
// "error" = Taste verwerfen, "go" = Workspace wechseln (Panel bleibt offen),
// "move" = aktives Fenster dorthin (zu), "win" = Fenster fokussieren (zu), "" = weiter tippen
function act(prev, r) {
    if (r.error) return "error"
    if (r.cmd !== null) return ""
    if (r.win >= 0) return "win"
    if (r.ws && !prev.ws) return r.move ? "move" : "go"
    return ""
}

// Enter: "win" = Fenster mit genau dem getippten Code (a bei 11+ Fenstern),
// "output" = Fokus auf den Bildschirm (b<x>), "move" = aktives Fenster auf
// dessen sichtbaren Workspace (m b<x>), "cmd" = Befehl ausfuehren (:wort),
// "" = unvollstaendig, nichts tun, "close" = zu
function enter(r) {
    if (r.cmd !== null) return r.cmd.trim() ? "cmd" : "close"
    if (r.code) return r.match >= 0 ? "win" : ""
    if (r.wait) return ""
    if (r.screen && !r.ws) return r.move ? "move" : "output"
    return "close"
}

// Backspace: eine Stufe zurueck (ganzer Fenstercode, b<x>/w<x> samt Buchstabe, m)
function back(typed, ctx) {
    var r = decode(typed, ctx)
    if (r.cmd !== null) return typed.slice(0, -1)
    if (r.code) return typed.slice(0, typed.length - r.code.length)
    var t = typed.slice(0, -1)
    return decode(t, ctx).wait ? t.slice(0, -1) : t
}

// ":wort a b" (ohne ":") -> { name, args }; nur am Leerzeichen getrennt
function parse(cmd) {
    var w = cmd.trim().split(/\s+/)
    return { name: w[0] || "", args: w.slice(1) }
}

// Kuerzester Befehl zu Fenster i auf Bildschirm s, Workspace w, von here aus;
// visible = sichtbarer Workspace von s. "⏎" = Code wartet auf Enter (a bei 11+)
function route(s, w, i, n, here, visible) {
    var c = code(i), more = false
    for (var k = 0; k < n; k++) if (k !== i && code(k).indexOf(c) === 0) more = true
    return (s === here ? "" : "b" + s) + (w === visible ? "" : "w" + KEYS[w - 1]) + c + (more ? " ⏎" : "")
}
