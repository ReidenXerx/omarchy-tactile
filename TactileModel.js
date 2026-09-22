// TactileModel.js -- what Tactile decides, with no Qt in it, so node can test it.
//
// The pointer devices Hyprland reports, the settings each kind of device takes (what they do, their ranges and
// Hyprland's defaults), the Lua that applies them to one device, the trial that puts a change back unless it is kept,
// and Tactile's own saved settings. Everything read from Hyprland or shell.json is untrusted: shapes are checked and
// sizes are bounded before anything is built from it.

var DEVICES_MAX = 16
var TRIAL_MS = 15000
var QUOTE = String.fromCharCode(34)
var NAME_RE = new RegExp("^[a-z0-9][a-z0-9:_./+-]{0,127}$")
var COMBO_RE = new RegExp("^(SUPER|ALT|CTRL|SHIFT)( [+] (SUPER|ALT|CTRL|SHIFT))* [+] [A-Z0-9]$")

function isList(v) { return Array.isArray(v) || v instanceof Array }
function isObject(v) { return v !== null && typeof v === "object" && !isList(v) }
function toList(v) { return isList(v) ? Array.prototype.slice.call(v) : [] }
function has(o, k) { return isObject(o) && Object.prototype.hasOwnProperty.call(o, k) }
function copy(v) { return v === undefined ? undefined : JSON.parse(JSON.stringify(v)) }
function validName(name) { return typeof name === "string" && NAME_RE.test(name) }

// ---------------------------------------------------------------- devices

// What a Hyprland pointer device is. A touchpad's companion "-mouse" node (its physical buttons), a keyboard's pointer
// node and the kernel's PS/2 fallback are not devices anyone tunes, so they are kept apart as "other".
function readDevices(raw) {
  var names = (isObject(raw) ? toList(raw.mice) : []).map(function (m) {
    return isObject(m) ? m.name : null
  }).filter(validName).slice(0, DEVICES_MAX * 2)
  var stems = names.filter(function (n) { return n.indexOf("touchpad") >= 0 }).map(function (n) {
    return n.slice(0, n.length - "-touchpad".length)
  })
  var order = { touchpad: 0, mouse: 1, other: 2 }
  var seen = {}
  return names.filter(function (n) {
    if (seen[n]) return false
    seen[n] = true
    return true
  }).map(function (n) {
    var kind = n.indexOf("touchpad") >= 0 ? "touchpad"
      : (n.indexOf("keyboard") >= 0 || n === "ps/2-generic-mouse" || stems.indexOf(n.slice(0, n.length - "-mouse".length)) >= 0
         && n.slice(-"-mouse".length) === "-mouse") ? "other" : "mouse"
    return { name: n, kind: kind, label: deviceLabel(n, kind) }
  }).sort(function (a, b) {
    return order[a.kind] - order[b.kind] || a.name.localeCompare(b.name)
  }).slice(0, DEVICES_MAX)
}

// A readable name: vendor codes say nothing about a touchpad, and a mouse's name is its words.
function deviceLabel(name, kind) {
  if (kind === "touchpad") return "Touchpad"
  // A device names itself, and a hostile one can name itself markup. Omarchy's
  // Button does pin textFormat, so today this is belt and braces rather than a
  // fix -- but the label is handed to a shared component this plugin does not
  // own, and a string that is safe whoever renders it costs one replace.
  name = String(name || "").replace(/[<>&]/g, "")
  return String(name || "").split(new RegExp("[-_ /:]+")).filter(function (w) { return w.length > 0 }).map(function (w) {
    if (new RegExp("[0-9]").test(w) || w.length <= 2) return w.toUpperCase()
    return w.charAt(0).toUpperCase() + w.slice(1)
  }).join(" ")
}

function tunable(devices) {
  return toList(devices).filter(function (d) { return d.kind === "touchpad" || d.kind === "mouse" })
}

// ---------------------------------------------------------------- settings

// Every setting Tactile offers, with Hyprland's own default. `global` is the option that holds the value for all
// devices of that kind, which is what a device shows until Tactile sets its own.
var FIELDS = {
  sensitivity: { type: "number", min: -1, max: 1, step: 0.05, fallback: 0, kinds: ["touchpad", "mouse"], group: "pointer",
                 global: "input:sensitivity", label: "Pointer speed", tip: "How far the pointer travels for the same movement." },
  accel_profile: { type: "profile", choices: ["adaptive", "flat", "custom"], fallback: "adaptive", kinds: ["touchpad", "mouse"],
                   group: "pointer", global: "input:accel_profile", label: "Acceleration",
                   tip: "Adaptive speeds the pointer up on fast movements, flat keeps every movement the same, and custom follows a curve you draw." },
  natural_scroll: { type: "bool", fallback: false, kinds: ["touchpad", "mouse"], group: "scroll",
                    global: { touchpad: "input:touchpad:natural_scroll", mouse: "input:natural_scroll" },
                    label: "Natural scrolling", tip: "Content follows your fingers, as on a phone." },
  scroll_factor: { type: "number", min: 0.1, max: 3, step: 0.05, fallback: 1, kinds: ["touchpad", "mouse"], group: "scroll",
                   global: { touchpad: "input:touchpad:scroll_factor", mouse: "input:scroll_factor" },
                   label: "Scroll speed", tip: "How far one scroll moves the page." },
  scroll_method: { type: "enum", choices: ["2fg", "edge"], fallback: "2fg", kinds: ["touchpad"], group: "scroll",
                   global: "input:scroll_method", label: "Scroll with", tip: "Two fingers anywhere, or one finger along the right edge." },
  scroll_points: { type: "curve", fallback: "", kinds: ["touchpad", "mouse"], group: "scroll", global: "input:scroll_points",
                   label: "Scroll curve", tip: "How much further a quick swipe scrolls than a slow one. Hyprland uses it with a custom pointer curve." },
  tap_to_click: { type: "bool", fallback: true, kinds: ["touchpad"], group: "tap", global: "input:touchpad:tap-to-click",
                  label: "Tap to click", tip: "A light tap clicks, without pressing the pad down." },
  tap_button_map: { type: "enum", choices: ["lrm", "lmr"], fallback: "lrm", kinds: ["touchpad"], group: "tap",
                    global: "input:touchpad:tap_button_map", label: "Two and three finger taps",
                    tip: "Which buttons a two-finger and a three-finger tap press." },
  clickfinger_behavior: { type: "bool", fallback: false, kinds: ["touchpad"], group: "click",
                          global: "input:touchpad:clickfinger_behavior", label: "Click with fingers",
                          tip: "Press down with two fingers for a right click and three for a middle click, instead of pressing the bottom corners." },
  middle_button_emulation: { type: "bool", fallback: false, kinds: ["touchpad", "mouse"], group: "click",
                             global: { touchpad: "input:touchpad:middle_button_emulation" },
                             label: "Middle click from both buttons", tip: "Pressing left and right together clicks the middle button." },
  left_handed: { type: "bool", fallback: false, kinds: ["touchpad", "mouse"], group: "click", global: "input:left_handed",
                 label: "Left-handed", tip: "Swap the left and right buttons." },
  tap_and_drag: { type: "bool", fallback: true, kinds: ["touchpad"], group: "drag", global: "input:touchpad:tap-and-drag",
                  label: "Tap and drag", tip: "Tap, then tap again and slide to drag." },
  drag_lock: { type: "enum", choices: [0, 1, 2], fallback: 0, kinds: ["touchpad"], group: "drag", global: "input:touchpad:drag_lock",
               label: "Drag lock", tip: "Lift your finger mid-drag without dropping: briefly, or until you tap again." },
  drag_3fg: { type: "enum", choices: [0, 1, 2], fallback: 0, kinds: ["touchpad"], group: "drag", global: "input:touchpad:drag_3fg",
              label: "Finger drag", tip: "Drag without pressing, by moving three or four fingers together." },
  disable_while_typing: { type: "bool", fallback: true, kinds: ["touchpad"], group: "typing",
                          global: "input:touchpad:disable_while_typing", label: "Ignore the pad while typing",
                          tip: "A palm brushing the pad while you type does not move the pointer." },
  flip_x: { type: "bool", fallback: false, kinds: ["touchpad"], group: "advanced", global: "input:touchpad:flip_x",
            label: "Flip left and right", tip: "Mirror horizontal movement, for a pad mounted upside down." },
  flip_y: { type: "bool", fallback: false, kinds: ["touchpad"], group: "advanced", global: "input:touchpad:flip_y",
            label: "Flip up and down", tip: "Mirror vertical movement." }
}

var FIELD_ORDER = ["sensitivity", "accel_profile", "natural_scroll", "scroll_factor", "scroll_method", "scroll_points", "tap_to_click",
                   "tap_button_map", "clickfinger_behavior", "middle_button_emulation", "left_handed", "tap_and_drag",
                   "drag_lock", "drag_3fg", "disable_while_typing", "flip_x", "flip_y"]

var GROUPS = [
  { id: "pointer", title: "Pointer" }, { id: "scroll", title: "Scrolling" }, { id: "tap", title: "Tapping" },
  { id: "click", title: "Clicking" }, { id: "drag", title: "Dragging" }, { id: "typing", title: "Typing" },
  { id: "advanced", title: "Advanced" }
]

var CHOICE_LABELS = {
  accel_profile: { adaptive: "Adaptive", flat: "Flat", custom: "Custom" },
  scroll_method: { "2fg": "Two fingers", edge: "Right edge" },
  tap_button_map: { lrm: "Right, then middle", lmr: "Middle, then right" },
  drag_lock: { 0: "Off", 1: "Briefly", 2: "Until tapped" },
  drag_3fg: { 0: "Off", 1: "Three fingers", 2: "Four fingers" }
}

function fieldApplies(field, kind) {
  return has(FIELDS, field) && FIELDS[field].kinds.indexOf(kind) >= 0
}

// The settings of one kind of device, grouped for the window, in the order they are shown.
function fieldsFor(kind) {
  return GROUPS.map(function (g) {
    return { id: g.id, title: g.title, fields: FIELD_ORDER.filter(function (f) {
      return fieldApplies(f, kind) && FIELDS[f].group === g.id
    }) }
  }).filter(function (g) { return g.fields.length > 0 })
}

function choiceLabel(field, value) {
  if (field === "accel_profile" && isCustomProfile(value)) return "Custom"
  var labels = CHOICE_LABELS[field]
  return labels && has(labels, String(value)) ? labels[String(value)] : String(value)
}

// A value made the type its setting wants, within its range: undefined when it cannot be one.
function coerceValue(field, value) {
  if (!has(FIELDS, field)) return undefined
  var f = FIELDS[field]
  if (f.type === "bool") {
    if (value === true || value === "true" || value === 1) return true
    if (value === false || value === "false" || value === 0) return false
    return undefined
  }
  if (f.type === "number") {
    if (value === "" || value === null || typeof value === "boolean") return undefined
    var n = Number(value)
    if (!isFinite(n)) return undefined
    return Math.round(Math.max(f.min, Math.min(f.max, n)) * 1000) / 1000
  }
  if (f.type === "curve") {
    if (value === "") return ""
    return curveText(parseCurve(value, false), false) || undefined
  }
  if (f.type === "profile" && typeof value === "string" && value.indexOf("custom") === 0)
    return curveText(parseCurve(value, true), true) || undefined
  for (var i = 0; i < f.choices.length; i++)
    if (String(f.choices[i]) === String(value) && f.choices[i] !== "custom") return f.choices[i]
  return undefined
}

// The global option that holds a setting for a kind of device, if there is one.
function globalKey(field, kind) {
  if (!has(FIELDS, field)) return ""
  var g = FIELDS[field].global
  if (typeof g === "string") return g
  return isObject(g) && typeof g[kind] === "string" ? g[kind] : ""
}

function globalKeys() {
  var keys = []
  Object.keys(FIELDS).forEach(function (field) {
    ["touchpad", "mouse"].forEach(function (kind) {
      var k = globalKey(field, kind)
      if (k && keys.indexOf(k) < 0) keys.push(k)
    })
  })
  return keys
}

// One `hyprctl getoption -j` answer: its value, or undefined.
function parseOption(raw) {
  var o = null
  try { o = JSON.parse(String(raw || "")) } catch (e) { return undefined }
  if (!isObject(o)) return undefined
  if (typeof o.bool === "boolean") return o.bool
  if (typeof o.int === "number") return o.int
  if (typeof o.float === "number") return Math.round(o.float * 1000) / 1000
  if (typeof o.str === "string") return o.str === "[[EMPTY]]" ? "" : o.str.slice(0, 1024)
  return undefined
}

// What a device has now: the value Tactile set on it, or the global value for its kind, or Hyprland's default.
function effective(field, kind, own, globals) {
  if (has(own, field)) return own[field]
  var key = globalKey(field, kind)
  if (key && has(globals, key)) {
    var v = coerceValue(field, field === "accel_profile" && globals[key] === "" ? "adaptive" : globals[key])
    if (v !== undefined) return v
  }
  return FIELDS[field] ? FIELDS[field].fallback : undefined
}

// ---------------------------------------------------------------- curves

// A curve is what libinput's custom profile takes: the speed that comes out at input speeds 0, step, 2 step and so on
// (units per millisecond). Libinput joins the points with straight lines and carries the last two on past the end;
// with a custom profile the pointer speed setting does nothing. The bounds sit well inside what libinput accepts.
var CURVE_POINTS_MIN = 2
var CURVE_POINTS_MAX = 32
var CURVE_STEP_MIN = 0.1
var CURVE_STEP_MAX = 50
var CURVE_VALUE_MAX = 200
var NUMBER_RE = new RegExp("^[0-9]+([.][0-9]+)?$")

function round3(n) { return Math.round(n * 1000) / 1000 }

function isCustomProfile(value) { return typeof value === "string" && value.indexOf("custom ") === 0 }

// "custom <step> <points...>" (withPrefix) or "<step> <points...>": the curve, or null when it is not one that both
// Hyprland (which splits on spaces and reads each part as a number) and libinput would take.
function parseCurve(text, withPrefix) {
  if (typeof text !== "string" || text.length > 1024) return null
  var parts = text.trim().split(" ").filter(nonEmpty)
  if (withPrefix && parts.shift() !== "custom") return null
  if (parts.length < CURVE_POINTS_MIN + 1 || parts.length > CURVE_POINTS_MAX + 1) return null
  for (var i = 0; i < parts.length; i++) if (!NUMBER_RE.test(parts[i])) return null
  var numbers = parts.map(Number)
  if (numbers[0] < CURVE_STEP_MIN || numbers[0] > CURVE_STEP_MAX) return null
  if (numbers.slice(1).some(function (p) { return p > CURVE_VALUE_MAX })) return null
  return { step: round3(numbers[0]), points: numbers.slice(1).map(round3) }
}

// A curve written the way Hyprland takes it, or "" when it is not a valid one.
function curveText(curve, withPrefix) {
  if (!isObject(curve) || typeof curve.step !== "number") return ""
  var numbers = [curve.step].concat(toList(curve.points))
  if (!numbers.every(function (n) { return typeof n === "number" && isFinite(n) && n >= 0 })) return ""
  var text = numbers.map(function (n) { return String(round3(n)) }).join(" ")
  return parseCurve(text, false) ? (withPrefix ? "custom " : "") + text : ""
}

// Ready-made curves, output = v (a + b v) at v = 0 to 8.
var CURVE_PRESETS = [
  { id: "straight", title: "Straight", a: 1, b: 0 },
  { id: "gentle", title: "Gentle", a: 0.8, b: 0.05 },
  { id: "precise", title: "Precise", a: 0.45, b: 0.12 },
  { id: "quick", title: "Quick", a: 1.2, b: 0.15 }
]

function presetCurve(id) {
  var p = CURVE_PRESETS.filter(function (x) { return x.id === id })[0] || CURVE_PRESETS[0]
  var points = []
  for (var v = 0; v <= 8; v++) points.push(round3(Math.min(CURVE_VALUE_MAX, v * (p.a + p.b * v))))
  return { step: 1, points: points }
}

function presetOf(curve) {
  var text = curveText(curve, false)
  for (var i = 0; i < CURVE_PRESETS.length; i++)
    if (text !== "" && curveText(presetCurve(CURVE_PRESETS[i].id), false) === text) return CURVE_PRESETS[i].id
  return ""
}

// The curve with one point moved. A faster movement never comes out slower: moving a point pushes its neighbours along.
function curveWithPoint(curve, index, value) {
  if (!isObject(curve)) return curve
  var c = { step: curve.step, points: toList(curve.points).slice() }
  if (index < 0 || index >= c.points.length) return c
  var v = round3(Math.max(0, Math.min(CURVE_VALUE_MAX, Number(value) || 0)))
  c.points[index] = v
  for (var i = index + 1; i < c.points.length; i++) if (c.points[i] < v) c.points[i] = v
  for (var j = index - 1; j >= 0; j--) if (c.points[j] > v) c.points[j] = v
  return c
}

// ---------------------------------------------------------------- the feel lab

var LAB_TESTS = [
  { id: "scroll", title: "Scroll" }, { id: "click", title: "Click" }, { id: "drag", title: "Drag" },
  { id: "aim", title: "Aim" }, { id: "pinch", title: "Pinch" }, { id: "type", title: "Type" }, { id: "fingers", title: "Fingers" }
]

var GROUP_TESTS = { pointer: "aim", scroll: "scroll", tap: "click", click: "click", drag: "drag", typing: "type", advanced: "aim" }

// The test that shows what a setting does, so the lab can follow the setting being changed.
function testFor(field) {
  return has(FIELDS, field) && has(GROUP_TESTS, FIELDS[field].group) ? GROUP_TESTS[FIELDS[field].group] : ""
}

function nonEmpty(text) { return typeof text === "string" && text !== "" }

// What to try in each test, worded for the settings the device has right now.
function scrollHints(kind, values) {
  var v = isObject(values) ? values : {}
  var hints = [v.natural_scroll ? "Natural: the page follows your fingers." : "Traditional: the page moves against your fingers."]
  if (kind === "touchpad") hints.push(v.scroll_method === "edge" ? "Slide one finger along the right edge of the pad." : "Slide two fingers anywhere on the pad.")
  else hints.push("Turn the wheel one notch at a time to see how far each notch goes.")
  return hints
}

function clickHints(kind, values) {
  var v = isObject(values) ? values : {}
  var hints = []
  if (kind === "touchpad") {
    if (v.tap_to_click) {
      var lmr = v.tap_button_map === "lmr"
      hints.push("Tap with one finger for left, two for " + (lmr ? "middle" : "right") + ", three for " + (lmr ? "right" : "middle") + ".")
    }
    hints.push(v.clickfinger_behavior ? "Press the pad with two fingers for right, three for middle."
                                      : "Press the bottom right corner for right, the bottom middle for middle.")
  } else {
    hints.push("Click with each button.")
  }
  if (v.middle_button_emulation) hints.push("Press left and right together for middle.")
  if (v.left_handed) hints.push("Left-handed: left and right are swapped.")
  return hints
}

function dragHints(kind, values) {
  var v = isObject(values) ? values : {}
  if (kind !== "touchpad") return ["Hold the left button and move the dot onto the ring."]
  var hints = ["Press the pad and slide the dot onto the ring."]
  if (v.tap_and_drag) hints.push("Or tap, then tap again and slide.")
  if (v.drag_3fg === 1 || v.drag_3fg === 2) hints.push("Or move " + (v.drag_3fg === 1 ? "three" : "four") + " fingers together, without pressing.")
  if (v.drag_lock === 1) hints.push("Lift your finger mid-drag: the drag waits a moment for it.")
  if (v.drag_lock === 2) hints.push("Lift your finger mid-drag: the drag holds until you tap.")
  return hints.filter(nonEmpty)
}

// The last targets hit in the aim test: seconds per target, and how much longer the path was than a straight line.
function aimSummary(samples) {
  var list = toList(samples).filter(function (x) {
    return isObject(x) && x.ms > 0 && x.straight > 0 && x.travelled >= 0
  }).slice(-5)
  if (list.length === 0) return { count: 0, seconds: 0, path: 0 }
  var ms = 0
  var ratio = 0
  list.forEach(function (x) {
    ms += x.ms
    ratio += Math.max(1, x.travelled / x.straight)
  })
  return { count: list.length, seconds: Math.round(ms / list.length / 10) / 100, path: Math.round(ratio / list.length * 10) / 10 }
}

// How many settings a trial really changes: a setting moved back to where it was does not count.
function trialSize(trial) {
  if (!isObject(trial)) return 0
  var n = 0
  Object.keys(trial.changes).forEach(function (device) {
    var c = trial.changes[device]
    Object.keys(c.after).forEach(function (field) {
      if (JSON.stringify(c.after[field]) !== JSON.stringify(c.before[field])) n++
    })
  })
  var lists = isObject(trial.lists) ? trial.lists : {}
  Object.keys(lists).forEach(function (list) {
    if (!has(LISTS, list)) return
    var key = LISTS[list].key
    var before = {}
    var after = {}
    LISTS[list].read(lists[list].before).forEach(function (e) { before[key(e)] = JSON.stringify(e) })
    LISTS[list].read(lists[list].after).forEach(function (e) { after[key(e)] = JSON.stringify(e) })
    Object.keys(after).forEach(function (k) { if (before[k] !== after[k]) n++ })
    Object.keys(before).forEach(function (k) { if (!has(after, k)) n++ })
  })
  return n
}

// ---------------------------------------------------------------- Lua

function luaValue(field, value) {
  var v = coerceValue(field, value)
  if (v === undefined) return null
  if (typeof v === "boolean") return v ? "true" : "false"
  if (typeof v === "number") return String(v)
  return QUOTE + v + QUOTE
}

// The Lua that applies `values` to one device, or "" when the name or a value is not one Tactile can write safely.
// It is wrapped in do ... end, since hyprctl reads an argument that starts with "--" as an option of its own.
function deviceStatement(name, kind, values) {
  if (!validName(name) || (kind !== "touchpad" && kind !== "mouse")) return ""
  var keys = Object.keys(isObject(values) ? values : {}).filter(function (k) { return fieldApplies(k, kind) }).sort()
  var parts = []
  for (var i = 0; i < keys.length; i++) {
    var lit = luaValue(keys[i], values[keys[i]])
    if (lit === null) return ""
    parts.push(keys[i] + " = " + lit)
  }
  if (parts.length === 0) return ""
  return "do hl.device({ name = " + QUOTE + name + QUOTE + ", " + parts.join(", ") + " }) end"
}

// The rule that floats Tactile's window, centred, at a size that fits the settings beside the test areas, and keeps it
// fully opaque as Omarchy does for apps that opt out of its default opacity. The title is Tactile's own fixed text;
// nothing from outside goes into it. The name makes a second call replace the rule rather than add another.
function windowRuleStatement(title) {
  if (!new RegExp("^[A-Za-z ]{1,32}$").test(String(title || ""))) return ""
  return "do hl.window_rule({ match = { title = " + QUOTE + "^" + title + "$" + QUOTE +
    " }, name = " + QUOTE + "tactile-window" + QUOTE + ", float = true, center = true, size = { 1040, 720 }, tag = " +
    QUOTE + "-default-opacity" + QUOTE + ", opacity = " + QUOTE + "1 1" + QUOTE + " }) end"
}

// ---------------------------------------------------------------- gestures

// Touchpad gestures Tactile adds to Hyprland. A config reload drops them, so they are added again then. Hyprland
// refuses a gesture that an earlier one already covers ("left or right" covers "left"), so narrow ones go in first.
var GESTURES_MAX = 12
var GESTURE_MODS = ["", "SUPER", "ALT", "CTRL", "SHIFT"]
var SWIPES = ["left", "right", "up", "down", "horizontal", "vertical", "swipe"]
var ONE_WAY = ["left", "right", "up", "down", "pinchin", "pinchout"]
var FINGER_WORDS = { 2: "two", 3: "three", 4: "four", 5: "five" }

var GESTURE_DIRECTIONS = [
  { id: "left", title: "Swipe left", arrow: "←", covers: ["left"], rank: 0 },
  { id: "right", title: "Swipe right", arrow: "→", covers: ["right"], rank: 0 },
  { id: "up", title: "Swipe up", arrow: "↑", covers: ["up"], rank: 0 },
  { id: "down", title: "Swipe down", arrow: "↓", covers: ["down"], rank: 0 },
  { id: "horizontal", title: "Swipe left or right", arrow: "↔", covers: ["left", "right", "horizontal"], rank: 1 },
  { id: "vertical", title: "Swipe up or down", arrow: "↕", covers: ["up", "down", "vertical"], rank: 1 },
  { id: "swipe", title: "Swipe any way", arrow: "✥", covers: SWIPES, rank: 2 },
  { id: "pinchin", title: "Pinch in", arrow: "⇲", covers: ["pinchin"], rank: 0 },
  { id: "pinchout", title: "Pinch out", arrow: "⇱", covers: ["pinchout"], rank: 0 },
  { id: "pinch", title: "Pinch in or out", arrow: "⤢", covers: ["pinchin", "pinchout", "pinch"], rank: 1 }
]

var GESTURE_ACTIONS = [
  { id: "workspace", title: "Switch workspace", directions: ["horizontal", "vertical"] },
  { id: "special", title: "Show the scratchpad", workspace: "scratchpad", directions: ONE_WAY },
  { id: "close", title: "Close the window", directions: ["left", "right", "up", "down"] },
  { id: "fullscreen", title: "Fullscreen", directions: ONE_WAY },
  { id: "maximize", title: "Maximize", hl: "fullscreen", mode: "maximize", directions: ONE_WAY },
  { id: "float", title: "Float or tile", directions: ONE_WAY },
  { id: "move", title: "Move the window", directions: SWIPES },
  { id: "resize", title: "Resize the window", directions: SWIPES },
  { id: "zoom", title: "Zoom at the pointer", hl: "cursor_zoom", mode: "live", zoom: 2, directions: ["pinchout", "pinch"] }
]

function directionOf(id) { return GESTURE_DIRECTIONS.filter(function (d) { return d.id === id })[0] || null }
function actionOf(id) { return GESTURE_ACTIONS.filter(function (a) { return a.id === id })[0] || null }
function isPinch(direction) { return SWIPES.indexOf(direction) < 0 }

function readGesture(raw) {
  if (!isObject(raw)) return null
  var d = directionOf(raw.direction)
  var a = actionOf(raw.action)
  var mods = raw.mods === undefined ? "" : raw.mods
  var fingers = raw.fingers
  if (!d || !a || GESTURE_MODS.indexOf(mods) < 0 || a.directions.indexOf(d.id) < 0) return null
  if (typeof fingers !== "number" || Math.round(fingers) !== fingers || fingers < (isPinch(d.id) ? 2 : 3) || fingers > 5) return null
  return { fingers: fingers, direction: d.id, action: a.id, mods: mods }
}

function gestureKey(g) { return g.fingers + ":" + g.mods + ":" + g.direction }

function readGestures(list) {
  var seen = {}
  var out = []
  toList(list).forEach(function (raw) {
    var g = readGesture(raw)
    if (!g || seen[gestureKey(g)] || out.length >= GESTURES_MAX) return
    seen[gestureKey(g)] = true
    out.push(g)
  })
  return out
}

function orderedGestures(list) {
  return readGestures(list).map(function (g, i) { return { g: g, i: i } }).sort(function (x, y) {
    return directionOf(x.g.direction).rank - directionOf(y.g.direction).rank || x.i - y.i
  }).map(function (x) { return x.g })
}

// The Lua that adds a gesture, or with `unset` the Lua that removes it (which has to match fingers, direction and mods).
function gestureStatement(g, unset) {
  var v = readGesture(g)
  if (!v) return ""
  var a = actionOf(v.action)
  var parts = ["fingers = " + v.fingers, "direction = " + QUOTE + v.direction + QUOTE]
  if (v.mods !== "") parts.push("mods = " + QUOTE + v.mods + QUOTE)
  if (unset) {
    parts.push("action = " + QUOTE + "unset" + QUOTE)
  } else {
    parts.push("action = " + QUOTE + (a.hl || a.id) + QUOTE)
    if (a.mode) parts.push("mode = " + QUOTE + a.mode + QUOTE)
    if (a.workspace) parts.push("workspace_name = " + QUOTE + a.workspace + QUOTE)
    if (a.zoom) parts.push("zoom_level = " + a.zoom)
  }
  return "do hl.gesture({ " + parts.join(", ") + " }) end"
}

// From one list of Tactile's gestures to another: the old ones removed, then the new ones added narrowest first.
function gestureSwap(before, after) {
  return readGestures(before).map(function (g) { return gestureStatement(g, true) })
    .concat(orderedGestures(after).map(function (g) { return gestureStatement(g, false) })).filter(nonEmpty)
}

// What to say about a list: a direction another gesture takes first, and swipes that finger drag turns into drags.
function gestureNotes(list, dragSetting) {
  var gs = readGestures(list)
  var dragFingers = dragSetting === 1 ? 3 : dragSetting === 2 ? 4 : 0
  var notes = []
  gs.forEach(function (g, i) {
    if (dragFingers === g.fingers && !isPinch(g.direction))
      notes.push({ key: gestureKey(g), text: "Finger drag uses " + FINGER_WORDS[g.fingers] + " fingers, so this swipe drags instead." })
    gs.forEach(function (h, j) {
      if (j === i || h.fingers !== g.fingers || h.mods !== g.mods || h.direction === g.direction) return
      if (directionOf(g.direction).covers.indexOf(h.direction) >= 0)
        notes.push({ key: gestureKey(g), text: directionOf(h.direction).title + " is taken by " + actionOf(h.action).title + "." })
    })
  })
  return notes
}

// ---------------------------------------------------------------- scroll speed per app

// One named window rule per app, so changing it replaces the rule and removing it turns the rule off.
var APPS_MAX = 24
var APP_RE = new RegExp("^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")

function appFactor(value) {
  if (value === null || value === undefined || value === "" || typeof value === "boolean") return null
  var n = Number(value)
  return isFinite(n) ? Math.round(Math.max(0.1, Math.min(5, n)) * 100) / 100 : null
}

function readApp(raw) {
  if (!isObject(raw) || typeof raw.app !== "string" || !APP_RE.test(raw.app)) return null
  var touchpad = appFactor(raw.touchpad)
  var mouse = appFactor(raw.mouse)
  if (touchpad === null && mouse === null) return null
  return { app: raw.app, touchpad: touchpad, mouse: mouse }
}

function readApps(list) {
  var seen = {}
  var out = []
  toList(list).forEach(function (raw) {
    var e = readApp(raw)
    if (!e || seen[e.app] || out.length >= APPS_MAX) return
    seen[e.app] = true
    out.push(e)
  })
  return out
}

function appRuleStatement(entry, off) {
  var e = off ? (isObject(entry) && typeof entry.app === "string" && APP_RE.test(entry.app) ? { app: entry.app, touchpad: 1, mouse: null } : null)
              : readApp(entry)
  if (!e) return ""
  var parts = ["name = " + QUOTE + "tactile-scroll-" + e.app + QUOTE,
               "match = { class = " + QUOTE + "^(" + e.app.split(".").join("[.]") + ")$" + QUOTE + " }"]
  if (e.touchpad !== null) parts.push("scroll_touchpad = " + e.touchpad)
  if (e.mouse !== null) parts.push("scroll_mouse = " + e.mouse)
  if (off) parts.push("enabled = false")
  return "do hl.window_rule({ " + parts.join(", ") + " }) end"
}

function appSwap(before, after) {
  var next = readApps(after)
  var names = next.map(function (e) { return e.app })
  return readApps(before).filter(function (e) { return names.indexOf(e.app) < 0 }).map(function (e) { return appRuleStatement(e, true) })
    .concat(next.map(function (e) { return appRuleStatement(e, false) })).filter(nonEmpty)
}

// The lists a trial can hold besides device settings.
var LISTS = {
  gestures: { read: readGestures, swap: gestureSwap, key: gestureKey },
  apps: { read: readApps, swap: appSwap, key: function (e) { return e.app } },
  padOff: { read: readPadOff, swap: padOffSwap, key: function (n) { return n } },
  profiles: { read: readProfiles, swap: profileSwap, key: profileKey }
}

// ---------------------------------------------------------------- automatic changes

// Rules that change devices by themselves: a touchpad turns off while Hyprland lists a mouse, and a device takes other
// settings while one app has focus. What they do depends on the moment, so their Lua is built from a context:
// { mouse: whether a mouse is listed, app: the focused app's class, base: function (device, field) giving the value the
// device has without any rule }.
var PROFILES_MAX = 16
var PROFILE_FIELDS = ["sensitivity", "accel_profile", "scroll_factor", "natural_scroll"]

function enabledStatement(name, on) {
  return validName(name) ? "do hl.device({ name = " + QUOTE + name + QUOTE + ", enabled = " + (on ? "true" : "false") + " }) end" : ""
}

function readPadOff(list) {
  var seen = {}
  return toList(list).filter(function (n) {
    if (!validName(n) || n.indexOf("touchpad") < 0 || seen[n]) return false
    seen[n] = true
    return true
  }).slice(0, DEVICES_MAX)
}

// Touchpads on the list are off while a mouse is listed and on otherwise; one taken off the list is turned back on.
function padOffSwap(before, after, ctx) {
  var next = readPadOff(after)
  var mouse = isObject(ctx) && ctx.mouse === true
  return readPadOff(before).filter(function (n) { return next.indexOf(n) < 0 }).map(function (n) { return enabledStatement(n, true) })
    .concat(next.map(function (n) { return enabledStatement(n, !mouse) })).filter(nonEmpty)
}

function readProfile(raw) {
  if (!isObject(raw) || typeof raw.app !== "string" || !APP_RE.test(raw.app) || raw.app === "org.quickshell") return null
  if (!validName(raw.device) || (raw.kind !== "touchpad" && raw.kind !== "mouse")) return null
  var values = {}
  PROFILE_FIELDS.forEach(function (f) {
    if (!isObject(raw.values) || !has(raw.values, f) || !fieldApplies(f, raw.kind)) return
    var v = coerceValue(f, raw.values[f])
    if (v !== undefined) values[f] = v
  })
  if (Object.keys(values).length === 0) return null
  return { app: raw.app, device: raw.device, kind: raw.kind, values: values }
}

function profileKey(p) { return p.app + "|" + p.device }

function readProfiles(list) {
  var seen = {}
  var out = []
  toList(list).forEach(function (raw) {
    var p = readProfile(raw)
    if (!p || seen[profileKey(p)] || out.length >= PROFILES_MAX) return
    seen[profileKey(p)] = true
    out.push(p)
  })
  return out
}

// What the profiles give each device while `app` has focus: { device: { kind, values } }.
function profileLayer(list, app) {
  var layer = {}
  readProfiles(list).forEach(function (p) {
    if (p.app !== app) return
    var d = layer[p.device] || (layer[p.device] = { kind: p.kind, values: {} })
    Object.keys(p.values).forEach(function (f) { d.values[f] = p.values[f] })
  })
  return layer
}

// From one layer to another: what the old layer set and the new one does not goes back to the device's own value, and
// what the new layer sets differently is applied.
function layerSwap(before, after, ctx) {
  var base = isObject(ctx) && typeof ctx.base === "function" ? ctx.base : function () { return undefined }
  var names = {}
  Object.keys(before).concat(Object.keys(after)).forEach(function (n) { names[n] = true })
  return Object.keys(names).sort().map(function (name) {
    var b = before[name]
    var a = after[name]
    var values = {}
    if (b) Object.keys(b.values).forEach(function (f) {
      if (a && has(a.values, f)) return
      var v = base(name, f)
      if (v !== undefined) values[f] = v
    })
    if (a) Object.keys(a.values).forEach(function (f) {
      if (!b || JSON.stringify(b.values[f]) !== JSON.stringify(a.values[f])) values[f] = a.values[f]
    })
    return deviceStatement(name, (a || b).kind, values)
  }).filter(nonEmpty)
}

function profileSwap(before, after, ctx) {
  var app = isObject(ctx) && typeof ctx.app === "string" ? ctx.app : ""
  return layerSwap(profileLayer(before, app), profileLayer(after, app), ctx)
}

// When focus moves from one app to another.
function focusSwap(list, fromApp, toApp, ctx) {
  return layerSwap(profileLayer(list, fromApp), profileLayer(list, toApp), ctx)
}

// ---------------------------------------------------------------- trials

// A trial: the changes made since the last Keep, with the value each field had before them, so that everything can
// be put back when the time runs out. Another change joins the trial and restarts its clock; the first value a field
// had stays the one to return to.
function trialAdd(trial, device, kind, field, before, after, now) {
  var t = isObject(trial) ? copy(trial) : { changes: {} }
  var c = t.changes[device] || (t.changes[device] = { kind: kind, before: {}, after: {} })
  if (!has(c.before, field)) c.before[field] = before
  c.after[field] = after
  t.deadline = now + TRIAL_MS
  return t
}

function trialSeconds(trial, now) {
  return isObject(trial) ? Math.max(0, Math.ceil((trial.deadline - now) / 1000)) : 0
}

// The statements that put every device in the trial back as it was.
function trialRevert(trial, ctx) {
  if (!isObject(trial)) return []
  var out = Object.keys(trial.changes).sort().map(function (device) {
    var c = trial.changes[device]
    return deviceStatement(device, c.kind, c.before)
  }).filter(function (s) { return s !== "" })
  var lists = isObject(trial.lists) ? trial.lists : {}
  Object.keys(lists).sort().forEach(function (list) {
    if (has(LISTS, list)) out = out.concat(LISTS[list].swap(lists[list].after, lists[list].before, ctx))
  })
  return out
}

// A change to one of the lists joins the trial the same way: the list as it was before the first change is what comes back.
function trialAddList(trial, list, before, after, now) {
  if (!has(LISTS, list)) return trial
  var t = isObject(trial) ? copy(trial) : { changes: {} }
  t.lists = isObject(t.lists) ? t.lists : {}
  if (!has(t.lists, list)) t.lists[list] = { before: LISTS[list].read(before) }
  t.lists[list].after = LISTS[list].read(after)
  t.deadline = now + TRIAL_MS
  return t
}

// ---------------------------------------------------------------- Tactile's own settings

// What Tactile keeps in its entry in shell.json: the values it set on each device. They are applied again whenever
// the shell starts or Hyprland reloads its config, since a reload drops them.
function readSettings(entry) {
  var raw = isObject(entry) ? entry : {}
  var devices = {}
  var count = 0
  Object.keys(isObject(raw.devices) ? raw.devices : {}).forEach(function (name) {
    var d = raw.devices[name]
    if (count >= DEVICES_MAX || !validName(name) || !isObject(d) || (d.kind !== "touchpad" && d.kind !== "mouse")) return
    var values = {}
    Object.keys(isObject(d.values) ? d.values : {}).forEach(function (field) {
      if (!fieldApplies(field, d.kind)) return
      var v = coerceValue(field, d.values[field])
      if (v !== undefined) values[field] = v
    })
    devices[name] = { kind: d.kind, values: values }
    count++
  })
  return {
    devices: devices,
    gestures: readGestures(raw.gestures),
    apps: readApps(raw.apps),
    padOff: readPadOff(raw.padOff),
    profiles: readProfiles(raw.profiles),
    shortcut: typeof raw.shortcut === "string" && (raw.shortcut === "" || COMBO_RE.test(raw.shortcut)) ? raw.shortcut : "SUPER + ALT + T"
  }
}

function settingsPayload(settings) {
  return { devices: copy(settings.devices), gestures: copy(settings.gestures || []), apps: copy(settings.apps || []),
           padOff: copy(settings.padOff || []), profiles: copy(settings.profiles || []), shortcut: settings.shortcut }
}

// The settings with a trial's changes kept. Given the global values, a setting that ends up the same as your config's
// is not kept, so your config stays in charge of it.
function withKept(settings, trial, globals) {
  var next = copy(settings)
  if (!isObject(trial)) return next
  Object.keys(trial.changes).forEach(function (device) {
    var c = trial.changes[device]
    var d = next.devices[device] || (next.devices[device] = { kind: c.kind, values: {} })
    Object.keys(c.after).forEach(function (field) {
      var v = coerceValue(field, c.after[field])
      if (v === undefined) return
      if (isObject(globals) && JSON.stringify(v) === JSON.stringify(effective(field, c.kind, {}, globals))) delete d.values[field]
      else d.values[field] = v
    })
    if (Object.keys(d.values).length === 0) delete next.devices[device]
  })
  var lists = isObject(trial.lists) ? trial.lists : {}
  Object.keys(lists).forEach(function (list) {
    if (has(LISTS, list)) next[list] = LISTS[list].read(lists[list].after)
  })
  return readSettings(settingsPayload(next))
}

// The statements that apply everything Tactile keeps, one per device.
function applyAll(settings, ctx) {
  return Object.keys(settings.devices).sort().map(function (name) {
    var d = settings.devices[name]
    return deviceStatement(name, d.kind, d.values)
  }).filter(function (s) { return s !== "" })
    .concat(gestureSwap(settings.gestures, settings.gestures), appSwap([], settings.apps),
            padOffSwap([], settings.padOff, ctx), profileSwap([], settings.profiles, ctx))
}

// ---------------------------------------------------------------- the shortcut

var BIND_DESCRIPTION = "Tactile: touchpad and mouse"
var MODS = { SUPER: 64, ALT: 8, CTRL: 4, SHIFT: 1 }

function comboParts(combo) {
  if (!COMBO_RE.test(String(combo || ""))) return null
  var parts = String(combo).split(" + ")
  var mask = 0
  for (var i = 0; i < parts.length - 1; i++) mask |= MODS[parts[i]]
  return { mask: mask, key: parts[parts.length - 1] }
}

function bindState(binds, combo) {
  if (combo === "") return "off"
  var parts = comboParts(combo)
  if (!parts) return "invalid"
  var on = toList(binds).filter(function (b) {
    return isObject(b) && Number(b.modmask) === parts.mask && String(b.key || "").toUpperCase() === parts.key && !b.submap
  })
  if (on.length === 0) return "free"
  return on.every(function (b) { return b.description === BIND_DESCRIPTION }) ? "ours" : "taken"
}

function bindStatement(combo, command) {
  var cmd = String(command || "")
  if (!COMBO_RE.test(String(combo || "")) || cmd.indexOf(QUOTE) >= 0 || cmd.indexOf(String.fromCharCode(92)) >= 0
      || cmd.indexOf(String.fromCharCode(10)) >= 0) return ""
  return "hl.bind(" + QUOTE + combo + QUOTE + ", hl.dsp.exec_cmd(" + QUOTE + cmd + QUOTE + "), { description = " +
    QUOTE + BIND_DESCRIPTION + QUOTE + " })"
}

function unbindStatement(combo) {
  return COMBO_RE.test(String(combo || "")) ? "hl.unbind(" + QUOTE + combo + QUOTE + ")" : ""
}
