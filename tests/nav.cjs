// Test der Navigator-Decodierung (quickshell/nav.js): node tests/nav.cjs
const fs = require("fs"), vm = require("vm"), assert = require("assert")
const nav = {}
vm.runInNewContext(fs.readFileSync(__dirname + "/../quickshell/nav.js", "utf8"), nav)

// Bildschirme a/s/d; Fensterzahl je Bildschirm + Workspace (0 = sichtbarer)
const n = { a0: 3, a2: 11, s0: 2, s4: 0, d0: 12, d1: 25 }
const ctx = { screens: "asd", here: "d", wins: (s, w) => new Array(n[s + w] || 0).fill({}) }
const d = t => nav.decode(t, ctx)
const pick = (r, ...k) => Object.fromEntries(k.map(x => [x, r[x]]))

// Codes: 1-10 einstellig, 11 = aa, 20 = aö, 21 = sa
assert.deepStrictEqual([0, 9, 10, 11, 19, 20].map(nav.code), ["a", "ö", "aa", "as", "aö", "sa"])

// Beispiel aus dem Ticket: Bildschirm A, Workspace 2, Fenster 11
assert.deepStrictEqual(pick(d("bawsaa"), "screen", "ws", "win", "error"), { screen: "a", ws: 2, win: 10, error: false })
// a ist bei 11 Fenstern Anfang von aa/as: wartet, Enter nimmt Fenster 1
assert.deepStrictEqual(pick(d("bawsa"), "match", "win"), { match: 0, win: -1 })
assert.strictEqual(nav.enter(d("bawsa")), "win")
assert.strictEqual(d("bawss").win, 1)  // s hat bei 11 Fenstern keinen laengeren Code
assert.ok(d("bawsd").win === 2 && d("bawsss").error)  // ss waere 21
// ohne b/w: sichtbarer Workspace des aktuellen Bildschirms (d, 12 Fenster)
assert.strictEqual(d("f").win, 3)
assert.strictEqual(d("as").win, 11)
assert.strictEqual(d("ad").error, true)  // nur 12 Fenster
// 25 Fenster: s ist Anfang von sa…sd, sa = 21
assert.deepStrictEqual(pick(d("wasa"), "ws", "win"), { ws: 1, win: 20 })
assert.strictEqual(d("was").win, -1)
// leerer Workspace: kein Fenstercode, Enter schliesst nur
assert.ok(d("bswfa").error && nav.enter(d("bswf")) === "close")
// Workspace wechselt sofort, Fensterwahl danach
assert.strictEqual(nav.act(d("bsw"), d("bswf")), "go")
assert.strictEqual(nav.act(d("baws"), d("bawss")), "win")
// m = verschieben: fertig nach dem Workspace, kein Fenstercode
assert.strictEqual(nav.act(d("mbaw"), d("mbawd")), "move")
assert.ok(d("mbawdd").error && d("md").error)
assert.strictEqual(nav.enter(d("mbs")), "move")
assert.strictEqual(nav.enter(d("bs")), "output")
assert.ok(nav.enter(d("b")) === "" && nav.enter(d("")) === "close")
// nur vorhandene Bildschirme, m nur vorne, b nach w nicht mehr
assert.ok(nav.decode("bs", { ...ctx, screens: "d" }).error)
assert.ok(d("bm").error && d("wab").error && d("x").error)
assert.strictEqual(nav.act(d(""), d("q")), "error")
// Backspace: eine Stufe zurueck
assert.deepStrictEqual(["bawsaa", "bawsa", "baws", "baw", "ba", "m", "w"].map(t => nav.back(t, ctx)),
                       ["baws", "baws", "ba", "ba", "", "", ""])
// Befehle: ":" schaltet die Codes ab, Ausfuehren erst mit Enter
assert.deepStrictEqual(pick(d(":all"), "cmd", "win", "error"), { cmd: "all", win: -1, error: false })
assert.strictEqual(nav.act(d(":al"), d(":all")), "")
assert.ok(nav.enter(d(":clear")) === "cmd" && nav.enter(d(":")) === "close" && nav.enter(d(": ")) === "close")
assert.strictEqual(nav.back(":all", ctx), ":al")
assert.ok(d("a:").error)  // ":" nur vorne
assert.strictEqual(JSON.stringify(nav.parse(" open  notiz x ")), JSON.stringify({ name: "open", args: ["notiz", "x"] }))
assert.strictEqual(JSON.stringify(nav.parse("")), JSON.stringify({ name: "", args: [] }))
// kuerzester Befehl fuer den Baum
assert.strictEqual(nav.route("a", 2, 10, 11, "d", 2), "baaa")
assert.strictEqual(nav.route("a", 2, 10, 11, "d", 5), "bawsaa")
assert.strictEqual(nav.route("d", 3, 0, 12, "d", 3), "a ⏎")
assert.strictEqual(nav.route("d", 3, 2, 2, "d", 1), "wdd")
console.log("ok")
