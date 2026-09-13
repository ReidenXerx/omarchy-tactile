#!/usr/bin/env node
// Tactile's model: devices, settings, the Lua that applies them, trials, saved settings and the shortcut.
const assert = require("assert")
const fs = require("fs")
const path = require("path")
const vm = require("vm")

const source = fs.readFileSync(path.join(__dirname, "..", "TactileModel.js"), "utf8")
const box = {}
vm.runInNewContext(source + "\nthis.M = { readDevices, deviceLabel, tunable, FIELDS, fieldsFor, choiceLabel, coerceValue, " +
  "globalKey, globalKeys, parseOption, effective, luaValue, deviceStatement, trialAdd, trialSeconds, trialRevert, " +
  "readSettings, settingsPayload, withKept, applyAll, comboParts, bindState, bindStatement, unbindStatement, TRIAL_MS, windowRuleStatement, FIELD_ORDER, fieldApplies, LAB_TESTS, testFor, scrollHints, clickHints, dragHints, aimSummary, trialSize, parseCurve, curveText, presetCurve, presetOf, curveWithPoint, CURVE_PRESETS, isCustomProfile, readGesture, readGestures, gestureStatement, gestureSwap, gestureNotes, readApp, appRuleStatement, appSwap, trialAddList, GESTURE_ACTIONS, GESTURE_DIRECTIONS, padOffSwap, readProfile, focusSwap, profileSwap }", box)
const M = box.M

let passed = 0
let failed = 0
function test(name, fn) {
  try {
    fn()
    passed++
  } catch (e) {
    failed++
    console.log("FAIL " + name + ": " + e.message + " @ " + String(e.stack).split(String.fromCharCode(10)).slice(1, 3).join(" | "))
  }
}
const plain = (v) => (v === undefined ? undefined : JSON.parse(JSON.stringify(v)))
const eq = (a, b, msg) => (msg === undefined ? assert.deepStrictEqual(plain(a), plain(b)) : assert.deepStrictEqual(plain(a), plain(b), msg))
const Q = String.fromCharCode(34)

// What this laptop's Hyprland reports.
const devicesJson = { mice: [
  { name: "dell-technologies-keyboard-1" }, { name: "ven_06cb:00-06cb:ceea-mouse" }, { name: "ven_06cb:00-06cb:ceea-touchpad" },
  { name: "ps/2-generic-mouse" }, { name: "logitech-mx-master-3s" }, { name: "Bad Name" }, { name: "logitech-mx-master-3s" }
] }

test("devices are sorted into touchpads, mice and nodes nobody tunes", () => {
  const devices = M.readDevices(devicesJson)
  eq(devices.map((d) => [d.name, d.kind]), [
    ["ven_06cb:00-06cb:ceea-touchpad", "touchpad"], ["logitech-mx-master-3s", "mouse"],
    ["dell-technologies-keyboard-1", "other"], ["ps/2-generic-mouse", "other"], ["ven_06cb:00-06cb:ceea-mouse", "other"]
  ])
  eq(devices.slice(0, 2).map((d) => d.label), ["Touchpad", "Logitech MX Master 3S"])
  eq(M.tunable(devices).length, 2)
  eq(M.readDevices({ mice: Array.from({ length: 40 }, (_, i) => ({ name: "mouse-" + i })) }).length, 16)
  eq(M.readDevices(null), [])
})

test("each kind gets its own settings, grouped", () => {
  const touchpad = M.fieldsFor("touchpad")
  eq(touchpad.map((g) => g.id), ["pointer", "scroll", "tap", "click", "drag", "typing", "advanced"])
  eq(touchpad.find((g) => g.id === "drag").fields, ["tap_and_drag", "drag_lock", "drag_3fg"])
  const mouse = M.fieldsFor("mouse")
  assert.ok(!mouse.some((g) => g.fields.includes("tap_to_click")), "no tapping on a mouse")
  eq(mouse.map((g) => g.id), ["pointer", "scroll", "click"])
  eq([M.choiceLabel("drag_3fg", 2), M.choiceLabel("tap_button_map", "lmr"), M.choiceLabel("natural_scroll", true)],
     ["Four fingers", "Middle, then right", "true"])
})

test("values are made the right type and kept in range", () => {
  eq([M.coerceValue("sensitivity", "0.37"), M.coerceValue("sensitivity", 5), M.coerceValue("sensitivity", "x"), M.coerceValue("sensitivity", true)],
     [0.37, 1, undefined, undefined])
  eq([M.coerceValue("natural_scroll", "true"), M.coerceValue("natural_scroll", 0), M.coerceValue("natural_scroll", "yes")], [true, false, undefined])
  eq([M.coerceValue("drag_3fg", "2"), M.coerceValue("drag_3fg", 3), M.coerceValue("accel_profile", "custom")], [2, undefined, undefined])
  eq(M.coerceValue("nonsense", 1), undefined)
})

test("what a device has now: its own value, the global one for its kind, or Hyprland's default", () => {
  const globals = { "input:touchpad:natural_scroll": true, "input:natural_scroll": false, "input:touchpad:scroll_factor": 0.4,
                    "input:accel_profile": "", "input:sensitivity": 0 }
  eq(M.effective("natural_scroll", "touchpad", {}, globals), true)
  eq(M.effective("natural_scroll", "mouse", {}, globals), false)
  eq(M.effective("scroll_factor", "touchpad", { scroll_factor: 0.8 }, globals), 0.8)
  eq(M.effective("accel_profile", "mouse", {}, globals), "adaptive", "an empty profile is libinput's adaptive")
  eq(M.effective("tap_to_click", "touchpad", {}, {}), true)
  eq(M.globalKey("middle_button_emulation", "mouse"), "")
  assert.ok(M.globalKeys().includes("input:touchpad:tap-to-click") && M.globalKeys().includes("input:scroll_factor"))
  eq([M.parseOption('{"option":"input:touchpad:scroll_factor","float":0.400000,"set":true}'),
      M.parseOption('{"option":"input:accel_profile","str":"[[EMPTY]]","set":false}'),
      M.parseOption('{"option":"input:touchpad:drag_3fg","int":2}'), M.parseOption("nope")], [0.4, "", 2, undefined])
})

test("the Lua for one device: only real devices, known settings and valid values", () => {
  const s = M.deviceStatement("ven_06cb:00-06cb:ceea-touchpad", "touchpad", { scroll_factor: 0.4, natural_scroll: true, drag_3fg: 2, tap_button_map: "lmr" })
  eq(s, "do hl.device({ name = " + Q + "ven_06cb:00-06cb:ceea-touchpad" + Q + ", drag_3fg = 2, natural_scroll = true, scroll_factor = 0.4, tap_button_map = " + Q + "lmr" + Q + " }) end")
  eq(M.deviceStatement("logitech-mx-master-3s", "mouse", { tap_to_click: false, sensitivity: -0.35 }),
     "do hl.device({ name = " + Q + "logitech-mx-master-3s" + Q + ", sensitivity = -0.35 }) end", "a mouse has no tapping")
  eq([M.deviceStatement("bad" + Q + "name", "mouse", { sensitivity: 0 }), M.deviceStatement("x", "keyboard", { sensitivity: 0 }),
      M.deviceStatement("x", "mouse", { sensitivity: "fast" }), M.deviceStatement("x", "mouse", {})], ["", "", "", ""])
  eq(M.luaValue("natural_scroll", false), "false", "false is written as false, never used to unset")
})

test("a trial remembers the first value of each field and puts all of them back", () => {
  const now = 1000
  let t = M.trialAdd(null, "tp", "touchpad", "scroll_factor", 0.4, 0.6, now)
  t = M.trialAdd(t, "tp", "touchpad", "scroll_factor", 0.6, 0.9, now + 2000)
  t = M.trialAdd(t, "mx", "mouse", "sensitivity", 0, 0.5, now + 3000)
  eq(t.changes.tp.before.scroll_factor, 0.4)
  eq(t.changes.tp.after.scroll_factor, 0.9)
  eq([M.trialSeconds(t, now + 3000), M.trialSeconds(t, now + 3000 + M.TRIAL_MS + 1), M.trialSeconds(null, now)], [15, 0, 0])
  eq(M.trialRevert(t), [
    "do hl.device({ name = " + Q + "mx" + Q + ", sensitivity = 0 }) end",
    "do hl.device({ name = " + Q + "tp" + Q + ", scroll_factor = 0.4 }) end"
  ])
})

test("kept changes join the saved settings, which are bounded and applied device by device", () => {
  let t = M.trialAdd(null, "tp", "touchpad", "natural_scroll", false, true, 0)
  t = M.trialAdd(t, "tp", "touchpad", "tap_to_click", true, false, 0)
  const settings = M.withKept(M.readSettings({}), t)
  eq(settings.devices.tp, { kind: "touchpad", values: { natural_scroll: true, tap_to_click: false } })
  eq(M.applyAll(settings), ["do hl.device({ name = " + Q + "tp" + Q + ", natural_scroll = true, tap_to_click = false }) end"])
  const read = M.readSettings({ devices: { "Bad Name": { kind: "mouse", values: {} }, mx: { kind: "mouse", values: { tap_to_click: true, sensitivity: 9 } },
                                           kb: { kind: "keyboard", values: {} } }, shortcut: "SUPER + T; rm" })
  eq(Object.keys(read.devices), ["mx"])
  eq(read.devices.mx.values, { sensitivity: 1 })
  eq(read.shortcut, "SUPER + ALT + T")
  eq(M.readSettings(M.settingsPayload(settings)), settings, "settings survive a round trip")
  const globals = { "input:touchpad:natural_scroll": true, "input:touchpad:tap-to-click": true }
  const followed = M.withKept(settings, M.trialAdd(null, "tp", "touchpad", "tap_to_click", false, true, 0), globals)
  eq(followed.devices.tp.values, { natural_scroll: true }, "a value equal to the config's is left to the config")
  const gone = M.withKept(followed, M.trialAdd(null, "tp", "touchpad", "natural_scroll", true, true, 0), globals)
  eq(Object.keys(gone.devices), [], "a device with nothing of its own is dropped")
})

test("the shortcut is bound only on free keys and taken back only when it is Tactile's", () => {
  eq(M.comboParts("SUPER + ALT + T"), { mask: 72, key: "T" })
  const ours = { modmask: 72, key: "T", submap: "", description: "Tactile: touchpad and mouse" }
  const other = { modmask: 72, key: "t", submap: "", description: "Something" }
  eq([M.bindState([], "SUPER + ALT + T"), M.bindState([ours], "SUPER + ALT + T"), M.bindState([ours, other], "SUPER + ALT + T"), M.bindState([], "")],
     ["free", "ours", "taken", "off"])
  assert.ok(M.bindStatement("SUPER + ALT + T", "/usr/bin/omarchy-shell shell toggle reidenxerx.tactile '{}'").startsWith("hl.bind("))
  eq([M.bindStatement("SUPER + ALT + T", "a" + Q), M.unbindStatement("SUPER + ALT + T;")], ["", ""])
})

test("the window rule floats Tactile's own window and nothing else", () => {
  eq(M.windowRuleStatement("Tactile"), "do hl.window_rule({ match = { title = " + Q + "^Tactile$" + Q + " }, name = " + Q + "tactile-window" + Q + ", float = true, center = true, size = { 1040, 720 }, tag = " + Q + "-default-opacity" + Q + ", opacity = " + Q + "1 1" + Q + " }) end")
  eq([M.windowRuleStatement("Tac" + Q + "tile"), M.windowRuleStatement("")], ["", ""])
  assert.ok(M.FIELD_ORDER.every((f) => M.FIELDS[f]), "every field in the order is defined")
  assert.ok(Object.keys(M.FIELDS).every((f) => M.FIELD_ORDER.includes(f)), "every field is shown")
})

test("the feel lab follows the setting being changed and speaks to the device's settings", () => {
  const ids = M.LAB_TESTS.map((x) => x.id)
  assert.ok(M.FIELD_ORDER.every((f) => ids.includes(M.testFor(f))), "every setting has a test")
  eq([M.testFor("scroll_factor"), M.testFor("drag_lock"), M.testFor("sensitivity"), M.testFor("nope")], ["scroll", "drag", "aim", ""])
  eq(M.clickHints("touchpad", { tap_to_click: true, tap_button_map: "lmr", clickfinger_behavior: true }),
     ["Tap with one finger for left, two for middle, three for right.", "Press the pad with two fingers for right, three for middle."])
  eq(M.clickHints("mouse", { left_handed: true }), ["Click with each button.", "Left-handed: left and right are swapped."])
  eq(M.dragHints("touchpad", { tap_and_drag: false, drag_3fg: 2, drag_lock: 0 }),
     ["Press the pad and slide the dot onto the ring.", "Or move four fingers together, without pressing."])
  eq(M.scrollHints("touchpad", { natural_scroll: true, scroll_method: "2fg" }),
     ["Natural: the page follows your fingers.", "Slide two fingers anywhere on the pad."])
})

test("aim results and trial sizes", () => {
  eq(M.aimSummary([]), { count: 0, seconds: 0, path: 0 })
  eq(M.aimSummary([{ ms: 600, travelled: 300, straight: 200 }, { ms: 800, travelled: 100, straight: 200 }, { ms: 0, travelled: 1, straight: 1 }]),
     { count: 2, seconds: 0.7, path: 1.3 })
  let t = M.trialAdd(null, "tp", "touchpad", "scroll_factor", 0.4, 0.6, 0)
  t = M.trialAdd(t, "tp", "touchpad", "natural_scroll", true, false, 0)
  eq(M.trialSize(t), 2)
  t = M.trialAdd(t, "tp", "touchpad", "scroll_factor", 0.6, 0.4, 0)
  eq([M.trialSize(t), M.trialSize(null)], [1, 0])
})

test("curves: Hyprland's custom profile and scroll points, checked and written one way", () => {
  eq(M.parseCurve("custom 1 0 1.5 3", true), { step: 1, points: [0, 1.5, 3] })
  eq([M.parseCurve("custom 1 0", true), M.parseCurve("custom 0 1 2", true), M.parseCurve("custom 1 -1 2", true),
      M.parseCurve("custom 1 1e2 3", true), M.parseCurve("1 0 1 2", true), M.parseCurve("custom 1 0 999", true)], [null, null, null, null, null, null])
  eq(M.parseCurve("0.5 0 1  2", false), { step: 0.5, points: [0, 1, 2] })
  eq([M.coerceValue("accel_profile", "custom  1 0 1.50 3"), M.coerceValue("accel_profile", "custom"), M.coerceValue("accel_profile", "flat")],
     ["custom 1 0 1.5 3", undefined, "flat"])
  eq([M.coerceValue("scroll_points", ""), M.coerceValue("scroll_points", "1 0 2 4"), M.coerceValue("scroll_points", "1 0 x")], ["", "1 0 2 4", undefined])
  eq(M.choiceLabel("accel_profile", "custom 1 0 1 2"), "Custom")
  eq(M.deviceStatement("mx", "mouse", { accel_profile: "custom 1 0 1 2", scroll_points: "1 0 2" }),
     "do hl.device({ name = " + Q + "mx" + Q + ", accel_profile = " + Q + "custom 1 0 1 2" + Q + ", scroll_points = " + Q + "1 0 2" + Q + " }) end")
  eq(M.presetCurve("straight"), { step: 1, points: [0, 1, 2, 3, 4, 5, 6, 7, 8] })
  eq([M.presetOf(M.presetCurve("quick")), M.presetOf({ step: 1, points: [0, 9] })], ["quick", ""])
  eq(M.curveWithPoint({ step: 1, points: [0, 1, 2, 3] }, 1, 2.5).points, [0, 2.5, 2.5, 3])
  eq(M.curveWithPoint({ step: 1, points: [0, 1, 2, 3] }, 2, 0.5).points, [0, 0.5, 0.5, 3])
  eq(M.effective("accel_profile", "mouse", {}, { "input:accel_profile": "custom 2 0 1 2" }), "custom 2 0 1 2")
  eq(M.curveText({ step: 1, points: [0, NaN] }, true), "")
})

test("gestures: checked, narrow ones added first, removed exactly, with notes on overlaps and finger drag", () => {
  const ws = { fingers: 3, direction: "horizontal", action: "workspace" }
  const close = { fingers: 3, direction: "down", action: "close" }
  eq(M.readGesture(ws), { fingers: 3, direction: "horizontal", action: "workspace", mods: "" })
  eq([M.readGesture({ fingers: 2, direction: "left", action: "close" }), M.readGesture({ fingers: 3, direction: "left", action: "workspace" }),
      M.readGesture({ fingers: 3, direction: "sideways", action: "close" }), M.readGesture({ fingers: 3, direction: "down", action: "close", mods: "SUPER; rm" }),
      M.readGesture({ fingers: 6, direction: "down", action: "close" }), M.readGesture({ fingers: "3", direction: "down", action: "close" })],
     [null, null, null, null, null, null])
  eq(M.gestureStatement({ fingers: 2, direction: "pinchout", action: "zoom" }, false),
     "do hl.gesture({ fingers = 2, direction = " + Q + "pinchout" + Q + ", action = " + Q + "cursor_zoom" + Q + ", mode = " + Q + "live" + Q + ", zoom_level = 2 }) end")
  eq(M.gestureStatement({ fingers: 4, direction: "up", action: "maximize", mods: "SUPER" }, true),
     "do hl.gesture({ fingers = 4, direction = " + Q + "up" + Q + ", mods = " + Q + "SUPER" + Q + ", action = " + Q + "unset" + Q + " }) end")
  const swapped = M.gestureSwap([close], [ws, close])
  eq(swapped.length, 3)
  assert.ok(swapped[0].includes("unset") && swapped[1].includes("down") && swapped[2].includes("horizontal"), "old removed, then narrow before broad")
  eq(M.readGestures([ws, ws, close]).length, 2)
  eq(M.gestureNotes([ws, close], 0), [])
  eq(M.gestureNotes([ws, { fingers: 3, direction: "left", action: "close" }], 1).map((n) => n.text), [
    "Finger drag uses three fingers, so this swipe drags instead.",
    "Swipe left is taken by Close the window.",
    "Finger drag uses three fingers, so this swipe drags instead."
  ])
  assert.ok(M.GESTURE_ACTIONS.every((a) => a.directions.every((d) => M.GESTURE_DIRECTIONS.some((x) => x.id === d))), "actions name real directions")
})

test("scroll speed per app: one named rule per app, turned off when removed", () => {
  eq(M.readApp({ app: "com.mitchellh.ghostty", touchpad: 9 }), { app: "com.mitchellh.ghostty", touchpad: 5, mouse: null })
  eq([M.readApp({ app: "foot; rm", touchpad: 1 }), M.readApp({ app: "foot" }), M.readApp({ app: "foot", touchpad: true })], [null, null, null])
  eq(M.appRuleStatement({ app: "com.mitchellh.ghostty", touchpad: 0.5 }, false),
     "do hl.window_rule({ name = " + Q + "tactile-scroll-com.mitchellh.ghostty" + Q + ", match = { class = " + Q + "^(com[.]mitchellh[.]ghostty)$" + Q + " }, scroll_touchpad = 0.5 }) end")
  eq(M.appSwap([{ app: "foot", touchpad: 2 }, { app: "kitty", mouse: 1.5 }], [{ app: "kitty", mouse: 2 }]), [
    "do hl.window_rule({ name = " + Q + "tactile-scroll-foot" + Q + ", match = { class = " + Q + "^(foot)$" + Q + " }, scroll_touchpad = 1, enabled = false }) end",
    "do hl.window_rule({ name = " + Q + "tactile-scroll-kitty" + Q + ", match = { class = " + Q + "^(kitty)$" + Q + " }, scroll_mouse = 2 }) end"
  ])
})

test("lists join trials: counted, put back, kept and applied again", () => {
  const ws = { fingers: 3, direction: "horizontal", action: "workspace" }
  let t = M.trialAddList(null, "gestures", [], [ws], 0)
  t = M.trialAddList(t, "apps", [{ app: "foot", touchpad: 2 }], [], 0)
  eq(M.trialSize(t), 2)
  eq(M.trialRevert(t), [
    "do hl.window_rule({ name = " + Q + "tactile-scroll-foot" + Q + ", match = { class = " + Q + "^(foot)$" + Q + " }, scroll_touchpad = 2 }) end",
    "do hl.gesture({ fingers = 3, direction = " + Q + "horizontal" + Q + ", action = " + Q + "unset" + Q + " }) end"
  ])
  const kept = M.withKept(M.readSettings({}), t)
  eq([kept.gestures, kept.apps], [[{ fingers: 3, direction: "horizontal", action: "workspace", mods: "" }], []])
  eq(M.applyAll(kept), [
    "do hl.gesture({ fingers = 3, direction = " + Q + "horizontal" + Q + ", action = " + Q + "unset" + Q + " }) end",
    "do hl.gesture({ fingers = 3, direction = " + Q + "horizontal" + Q + ", action = " + Q + "workspace" + Q + " }) end"
  ])
  eq(M.readSettings(M.settingsPayload(kept)), kept)
})

test("automatic changes: a touchpad off while a mouse is listed, and settings while one app has focus", () => {
  const pad = (on) => "do hl.device({ name = " + Q + "tp-touchpad" + Q + ", enabled = " + on + " }) end"
  eq(M.padOffSwap([], ["tp-touchpad"], { mouse: true }), [pad("false")])
  eq(M.padOffSwap(["tp-touchpad"], [], { mouse: true }), [pad("true")])
  eq(M.padOffSwap([], ["tp-touchpad", "logitech-mouse", "bad name"], { mouse: false }), [pad("true")])
  const game = { app: "dota2", device: "mx", kind: "mouse", values: { sensitivity: -0.3, accel_profile: "flat", tap_to_click: false } }
  eq(M.readProfile(game), { app: "dota2", device: "mx", kind: "mouse", values: { sensitivity: -0.3, accel_profile: "flat" } })
  eq([M.readProfile({ app: "org.quickshell", device: "mx", kind: "mouse", values: { sensitivity: 0 } }),
      M.readProfile({ app: "dota2", device: "mx", kind: "mouse", values: {} })], [null, null])
  const base = (device, field) => ({ sensitivity: 0, accel_profile: "adaptive" })[field]
  const on = "do hl.device({ name = " + Q + "mx" + Q + ", accel_profile = " + Q + "flat" + Q + ", sensitivity = -0.3 }) end"
  const off = "do hl.device({ name = " + Q + "mx" + Q + ", accel_profile = " + Q + "adaptive" + Q + ", sensitivity = 0 }) end"
  eq([M.focusSwap([game], "foot", "dota2", { base }), M.focusSwap([game], "dota2", "foot", { base }), M.focusSwap([game], "foot", "kitty", { base })],
     [[on], [off], []])
  eq(M.profileSwap([game], [], { app: "dota2", base }), [off])
  const settings = M.readSettings({ padOff: ["tp-touchpad"], profiles: [game] })
  eq(M.applyAll(settings, { mouse: true, app: "dota2", base }), [pad("false"), on])
  eq(M.readSettings(M.settingsPayload(settings)), settings)
  const t = M.trialAddList(null, "padOff", [], ["tp-touchpad"], 0)
  eq([M.trialSize(t), M.trialRevert(t, { mouse: true })], [1, [pad("true")]])
})

console.log(passed + " passed, " + failed + " failed")
process.exit(failed ? 1 : 0)
