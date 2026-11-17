// Test der Navigator-Decodierung (quickshell/nav.js): node tests/nav.cjs
const fs = require("fs"), vm = require("vm"), assert = require("assert")
const nav = {}
vm.runInNewContext(fs.readFileSync(__dirname + "/../quickshell/nav.js", "utf8"), nav)

// Bildschirme a/s/d; Fensterzahl je Bildschirm + Workspace (0 = sichtbarer)
const n = { a0: 3, a2: 11, s0: 2, s4: 0, d0: 12, d1: 25, d4: 3 }
const ctx = { screens: "asd", here: "d", wins: (s, w) => new Array(n[s + w] || 0).fill({}) }
const d = t => nav.decode(t, ctx)
const pick = (r, ...k) => Object.fromEntries(k.map(x => [x, r[x]]))

// Codes: 1-10 einstellig, 11 = aa, 20 = aö, 21 = sa
assert.deepStrictEqual([0, 9, 10, 11, 19, 20].map(nav.code), ["a", "ö", "aa", "as", "aö", "sa"])

// von rechts gelesen: Fenster, davor Workspace, davor Bildschirm
assert.deepStrictEqual(pick(d("a s aa"), "screen", "ws", "match", "error"), { screen: "a", ws: 2, match: 10, error: false })
assert.strictEqual(nav.enter(d("a s aa")), "win")
assert.strictEqual(nav.label(d("a s aa")), "Enter = A2 · Fenster 11")
assert.deepStrictEqual(pick(d("f a"), "screen", "ws", "match"), { screen: "", ws: 4, match: 0 })
assert.deepStrictEqual(pick(d("f"), "ws", "match"), { ws: 0, match: 3 })   // sichtbarer hier, 12 Fenster
assert.strictEqual(d("as").match, 11)
// a bei 11+ Fenstern: Enter nimmt genau Fenster 1, aa = 11
assert.ok(d("a s a").match === 0 && nav.enter(d("a s a")) === "win")
// Leerzeichen am Ende = kein Fenster: Workspace bzw. Bildschirm
assert.deepStrictEqual(pick(d("f "), "screen", "ws", "code"), { screen: "", ws: 4, code: "" })
assert.ok(nav.enter(d("f ")) === "go" && nav.label(d("f ")) === "Enter = Workspace 4")
assert.ok(nav.enter(d("a s ")) === "go" && d("a s ").screen === "a")
// leerer Teil = aktueller Bildschirm / sichtbarer Workspace
assert.ok(nav.enter(d("s  ")) === "output" && d("s  ").screen === "s")
assert.deepStrictEqual(pick(d("a  s"), "screen", "ws", "match"), { screen: "a", ws: 0, match: 1 })
// ein Buchstabe ohne passendes Fenster darf noch Workspace/Bildschirm werden, Enter tut nichts
const s2 = t => nav.decode(t, { ...ctx, here: "s" })   // S hat 2 Fenster
assert.ok(!s2("f").error && nav.enter(s2("f")) === "" && nav.label(s2("f")) === "")
assert.ok(s2("f ").ws === 4 && s2("ff").error)
// Fehler: zu viele Teile, kein Bildschirm, kein Workspace, Code ohne Fenster
assert.ok(d("a s d f").error && d("f s ").error && d("aa ").error && d("a s ss").error)
assert.ok(d("a s öö").error && d("ad").error && d("x").error && d("s f a").error)  // S4 leer
assert.ok(nav.decode("s  ", { ...ctx, screens: "d" }).error)
// m = verschieben: kein Fensterteil, Leerzeichen am Ende egal
assert.ok(nav.enter(d("m a f")) === "move" && d("m a f").screen === "a" && d("m a f").ws === 4)
assert.deepStrictEqual(pick(d("m a f "), "screen", "ws"), { screen: "a", ws: 4 })
assert.ok(nav.enter(d("mf")) === "move" && d("mf").ws === 4 && !d("mf").screen)
assert.ok(nav.enter(d("m a  ")) === "move" && d("m a  ").screen === "a" && !d("m a  ").ws)
assert.strictEqual(nav.label(d("m a f")), "Enter = verschieben nach A4")
assert.ok(d("m a f g").error && d("am").error && nav.enter(d("m")) === "close")
assert.ok(nav.enter(d("")) === "close" && nav.enter(d(" ")) === "close")
// Backspace: ein Zeichen
assert.deepStrictEqual(["a s aa", "a s ", "m ", "m", ""].map(nav.back), ["a s a", "a s", "", "", ""])
// Befehle: "#" schaltet die Codes ab, Ausfuehren erst mit Enter
assert.deepStrictEqual(pick(d("#all"), "cmd", "match", "error"), { cmd: "all", match: -1, error: false })
assert.ok(nav.enter(d("#clear")) === "cmd" && nav.enter(d("#")) === "close" && nav.enter(d("# ")) === "close")
assert.ok(d("a#").error && d(":all").error)  // "#" nur vorne, ":" gibt es nicht mehr
assert.strictEqual(JSON.stringify(nav.parse(" open  notiz x ")), JSON.stringify({ name: "open", args: ["notiz", "x"] }))
assert.strictEqual(JSON.stringify(nav.parse("")), JSON.stringify({ name: "", args: [] }))
// kuerzester Befehl fuer den Baum
assert.strictEqual(nav.route("a", 2, 10, "d", 2), "a s aa")
assert.strictEqual(nav.route("d", 3, 0, "d", 3), "a")
assert.strictEqual(nav.route("d", 3, 2, "d", 1), "d d")
// jeder Weg aus route() fuehrt per Enter zu genau diesem Fenster
assert.strictEqual(d(nav.route("d", 1, 22, "d", 3)).match, 22)
// Tab-Ergaenzung der Befehlsnamen
const names = ["all", "split", "park", "unpark", "close", "clear", "note"]
assert.strictEqual(nav.complete("sp", names).text, "split ")
assert.strictEqual(nav.complete("c", names).text, "cl")       // close/clear: gemeinsamer Anfang
assert.strictEqual(JSON.stringify(nav.complete("cl", names).hits), JSON.stringify(["clear", "close"]))
assert.strictEqual(nav.complete("", names).hits.length, 7)
assert.strictEqual(nav.complete("x", names), null)
console.log("ok")
