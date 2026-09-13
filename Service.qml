import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import "TactileModel.js" as Model

// Tactile's service: the pointer devices Hyprland has, the settings Tactile keeps for each of them (applied again
// whenever the shell starts or Hyprland reloads its config, since a reload drops them), the trial that puts a change
// back unless it is kept, the window, and the shortcut that opens it.
//
// Every change is Lua that TactileModel built and checked, sent with `hyprctl eval` by absolute path, one process at
// a time, each with a deadline. Hyprland config files are never written.
Item {
  id: tactile
  visible: false

  property var shell: null
  property var manifest: null
  property string omarchyPath: ""

  readonly property string pluginId: "reidenxerx.tactile"
  readonly property string hyprctl: "/usr/bin/hyprctl"
  readonly property string shellTool: "/usr/bin/omarchy-shell"
  readonly property string notifyTool: "/usr/bin/notify-send"
  readonly property string toggleCommand: "/usr/bin/omarchy-shell shell toggle reidenxerx.tactile '{}'"
  readonly property string windowTitle: "Tactile"
  readonly property int killGraceMs: 1500
  readonly property int outputMax: 4 * 1024 * 1024

  // ---------------------------------------------------------------- what Tactile knows

  property bool loaded: false
  property bool hasEntry: false
  property var settings: Model.readSettings(null)
  property var devices: []
  readonly property var tunableDevices: Model.tunable(devices)
  property var globals: ({})
  property var live: ({})
  property var trial: null
  property int trialLeft: 0
  property int revision: 0
  property string status: ""
  property bool statusIsError: false
  property bool windowOpen: false
  property bool globalsReady: false
  property var openApps: []
  property bool mousePresent: false
  property string focusedApp: ""

  // The finger view: its reader runs only while the window shows it, and it can read the touchpad only after the user
  // adds Tactile's udev rule, which lets the logged-in user read touchpads (never keyboards).
  readonly property string fingerTool: String(Qt.resolvedUrl("bin/tactile-fingers")).replace("file://", "")
  readonly property string fingerRule: "/etc/udev/rules.d/70-tactile-touchpad.rules"
  readonly property string fingerTrigger: "/usr/bin/udevadm trigger --action=change --subsystem-match=input --property-match=ID_INPUT_TOUCHPAD=1"
  readonly property string grantScript: "PATH=/usr/bin:/bin; umask 022; printf '%s\\n' " +
    "'# Tactile: lets the logged-in user read touchpads (never keyboards) for its finger view. Delete this file to take that back.' " +
    "'ACTION==\"add|change\", SUBSYSTEM==\"input\", KERNEL==\"event*\", ENV{ID_INPUT_TOUCHPAD}==\"1\", TAG+=\"uaccess\"' " +
    "> " + fingerRule + ".new && /usr/bin/mv -f " + fingerRule + ".new " + fingerRule + " && " + fingerTrigger
  readonly property string revokeScript: "PATH=/usr/bin:/bin; /usr/bin/rm -f " + fingerRule + " && " + fingerTrigger
  property bool fingersWanted: false
  property var fingerPad: null
  property var fingerFrame: null
  property string fingerError: ""
  property bool fingerRuleInstalled: false
  property bool fingerGranting: false
  readonly property int trialChanges: Model.trialSize(tactile.trial)
  property string shortcutState: ""
  property string boundCombo: ""

  function say(message, isError) {
    tactile.status = String(message || "")
    tactile.statusIsError = isError === true
    if (tactile.status !== "" && !tactile.statusIsError) statusTimer.restart()
  }

  // A note like "Kept." fades after a few seconds; an error stays until the next change.
  Timer {
    id: statusTimer
    interval: 4000
    onTriggered: if (!tactile.statusIsError) tactile.status = ""
  }

  function parseJson(raw) {
    if (typeof raw !== "string" || raw.length > tactile.outputMax) return null
    try { return JSON.parse(raw) } catch (e) { return null }
  }

  // ---------------------------------------------------------------- one process at a time, each with a deadline

  property var queue: []
  property var job: null

  function enqueue(argv, deadlineMs, done) {
    if (!argv || argv.length === 0) {
      if (done) done(-1, "", "", false)
      return
    }
    var next = tactile.queue.slice()
    next.push({ argv: argv, deadline: deadlineMs, done: done, timedOut: false })
    tactile.queue = next
    Qt.callLater(tactile.pump)
  }

  function pump() {
    if (tactile.job || runner.running || tactile.queue.length === 0) return
    var next = tactile.queue.slice()
    tactile.job = next.shift()
    tactile.queue = next
    runner.outDone = false
    runner.exited = false
    runner.code = -1
    runner.command = tactile.job.argv
    runner.running = true
    deadline.interval = tactile.job.deadline
    deadline.restart()
  }

  function settle(force) {
    var current = tactile.job
    if (!current) return
    if (!runner.exited && !force) return
    if (!runner.outDone && !force) {
      settleGrace.restart()
      return
    }
    deadline.stop()
    settleGrace.stop()
    tactile.job = null
    var out = current.timedOut ? "" : String(runnerOut.text || "")
    var err = current.timedOut ? "" : String(runnerErr.text || "")
    try {
      if (current.done) current.done(runner.exited ? runner.code : -1, out, err, current.timedOut)
    } catch (e) {
      console.warn("Tactile: " + e)
    }
    Qt.callLater(tactile.pump)
  }

  Process {
    id: runner
    property bool outDone: false
    property bool exited: false
    property int code: -1
    stdout: StdioCollector {
      id: runnerOut
      onStreamFinished: {
        runner.outDone = true
        tactile.settle(false)
      }
    }
    stderr: StdioCollector { id: runnerErr }
    onExited: function (exitCode, exitStatus) {
      runner.code = exitCode
      runner.exited = true
      tactile.settle(false)
    }
  }

  Timer {
    id: deadline
    onTriggered: {
      if (!tactile.job) return
      tactile.job.timedOut = true
      if (runner.running) {
        runner.signal(15)
        killTimer.restart()
      } else {
        tactile.settle(true)
      }
    }
  }

  Timer {
    id: killTimer
    interval: tactile.killGraceMs
    onTriggered: if (runner.running) runner.signal(9)
  }

  Timer {
    id: settleGrace
    interval: 400
    onTriggered: tactile.settle(true)
  }

  // ---------------------------------------------------------------- reading

  function ownEntry(config) {
    var list = config && config.plugins instanceof Array ? config.plugins : []
    for (var i = 0; i < list.length; i++)
      if (list[i] && typeof list[i] === "object" && list[i].id === tactile.pluginId) return list[i]
    return null
  }

  function refreshConfig(then) {
    enqueue([tactile.shellTool, "shell", "listShellConfig"], 5000, function (code, out) {
      var parsed = code === 0 ? parseJson(out) : null
      var ok = parsed !== null && typeof parsed === "object" && !(parsed instanceof Array)
      if (ok) {
        var entry = ownEntry(parsed)
        tactile.settings = Model.readSettings(entry)
        tactile.hasEntry = entry !== null
        tactile.loaded = true
        tactile.revision++
      }
      if (then) then(ok)
    })
  }

  function refreshDevices() {
    enqueue([tactile.hyprctl, "devices", "-j"], 3000, function (code, out) {
      var parsed = code === 0 ? parseJson(out) : null
      if (parsed) {
        tactile.devices = Model.readDevices(parsed)
        tactile.revision++
      }
      // A device list that cannot be read counts as no mouse, so a touchpad is never left off by mistake.
      var mouse = !!parsed && Model.tunable(tactile.devices).some(function (d) { return d.kind === "mouse" })
      if (mouse !== tactile.mousePresent) {
        tactile.mousePresent = mouse
        var pads = listOf("padOff")
        Model.padOffSwap(pads, pads, autoContext()).forEach(function (s) { runStatement(s, null) })
      }
    })
  }

  // What automatic changes need to know: is a mouse listed, which app has focus, and a device's value without them.
  function autoContext() {
    return { mouse: tactile.mousePresent, app: tactile.focusedApp, base: function (device, field) { return valueOf(device, field) } }
  }

  // Focus moved to another app: its settings apply and the last app's go back.
  function focusMoved(app) {
    var next = String(app || "").slice(0, 128)
    if (next === tactile.focusedApp) return
    var statements = Model.focusSwap(listOf("profiles"), tactile.focusedApp, next, autoContext())
    tactile.focusedApp = next
    statements.forEach(function (s) { runStatement(s, null) })
  }

  function refreshFocus() {
    enqueue([tactile.hyprctl, "activewindow", "-j"], 3000, function (code, out) {
      var parsed = code === 0 ? parseJson(out) : null
      tactile.focusMoved(parsed && typeof parsed.class === "string" ? parsed.class : "")
    })
  }

  // The global options every device falls back on, one question each.
  function refreshGlobals() {
    var keys = Model.globalKeys()
    var next = {}
    var i = 0
    function step() {
      if (i >= keys.length) {
        tactile.globals = next
        tactile.globalsReady = true
        tactile.revision++
        return
      }
      var key = keys[i++]
      enqueue([tactile.hyprctl, "getoption", key, "-j"], 3000, function (code, out) {
        var v = code === 0 ? Model.parseOption(out) : undefined
        if (v !== undefined) next[key] = v
        step()
      })
    }
    step()
  }

  // Devices that come and go (a mouse switched on) show up while the window is open, or while a touchpad waits for one.
  Timer {
    interval: 3000
    repeat: true
    running: tactile.windowOpen || tactile.listOf("padOff").length > 0
    onTriggered: if (!tactile.job && tactile.queue.length === 0) tactile.refreshDevices()
  }

  // ---------------------------------------------------------------- values

  function deviceNamed(name) {
    var list = tactile.devices
    for (var i = 0; i < list.length; i++) if (list[i].name === name) return list[i]
    return null
  }

  function ownValues(name) {
    var values = {}
    var saved = tactile.settings.devices[name]
    if (saved) for (var k in saved.values) values[k] = saved.values[k]
    var trying = tactile.live[name]
    if (trying) for (var t in trying) values[t] = trying[t]
    return values
  }

  // What a device has now, as the window shows it. Reading `revision` ties a binding to every change.
  function valueOf(name, field) {
    if (tactile.revision < 0) return undefined
    var d = deviceNamed(name)
    return d ? Model.effective(field, d.kind, ownValues(name), tactile.globals) : undefined
  }

  // Every setting a device has now, by name.
  function valuesOf(name) {
    var values = {}
    var d = tactile.revision >= 0 ? deviceNamed(name) : null
    if (!d) return values
    var own = ownValues(name)
    Model.FIELD_ORDER.forEach(function (field) {
      if (Model.fieldApplies(field, d.kind)) values[field] = Model.effective(field, d.kind, own, tactile.globals)
    })
    return values
  }

  // Whether Tactile keeps its own value of a setting for the device, instead of leaving it to your config.
  function isKept(name, field) {
    if (tactile.revision < 0) return false
    var saved = tactile.settings.devices[name]
    return !!saved && Object.prototype.hasOwnProperty.call(saved.values, field)
  }

  function keptCount(name) {
    if (tactile.revision < 0) return 0
    var saved = tactile.settings.devices[name]
    return saved ? Object.keys(saved.values).length : 0
  }

  function setLive(name, field, value) {
    var next = {}
    for (var k in tactile.live) next[k] = tactile.live[k]
    var own = {}
    if (next[name]) for (var f in next[name]) own[f] = next[name][f]
    own[field] = value
    next[name] = own
    tactile.live = next
    tactile.revision++
  }

  function runStatement(statement, done) {
    if (!statement) {
      if (done) done(false)
      return
    }
    enqueue([tactile.hyprctl, "eval", statement], 3000, function (code, out) {
      var ok = code === 0 && String(out || "").trim() === "ok"
      if (done) done(ok)
    })
  }

  // A change, applied at once and put on trial: it is taken back when the countdown ends unless it is kept.
  function setValue(name, field, value) {
    var d = deviceNamed(name)
    // Until the global values are read, what a change would put back is not known.
    if (!d || !tactile.loaded || !tactile.globalsReady) return
    var v = Model.coerceValue(field, value)
    if (v === undefined) return
    var before = valueOf(name, field)
    if (JSON.stringify(before) === JSON.stringify(v)) return
    var values = {}
    values[field] = v
    var statement = Model.deviceStatement(name, d.kind, values)
    if (!statement) return
    setLive(name, field, v)
    tactile.trial = Model.trialAdd(tactile.trial, name, d.kind, field, before, v, Date.now())
    tick()
    say("", false)
    runStatement(statement, function (ok) {
      if (!ok) {
        say("Hyprland did not take that setting, so the changes on trial were put back.", true)
        undoTrial()
      }
    })
  }

  // Every setting of a device back to what Omarchy and your own input.lua give it, as a change on trial.
  function resetDevice(name) {
    var d = deviceNamed(name)
    if (!d) return
    Model.FIELD_ORDER.forEach(function (field) {
      if (Model.fieldApplies(field, d.kind)) setValue(name, field, Model.effective(field, d.kind, {}, tactile.globals))
    })
  }

  // ---------------------------------------------------------------- gestures and scroll speed per app

  // A list as it is now: what is on trial, or else what Tactile keeps.
  function listOf(list) {
    if (tactile.revision < 0) return []
    var t = tactile.trial
    if (t && t.lists && t.lists[list]) return t.lists[list].after
    return tactile.settings[list] || []
  }

  // A new list, applied at once and put on trial like any other change.
  function setList(list, next) {
    if (!tactile.loaded || !Model.LISTS[list]) return false
    var before = Model.LISTS[list].read(listOf(list))
    var after = Model.LISTS[list].read(next)
    if (JSON.stringify(before) === JSON.stringify(after)) return false
    tactile.trial = Model.trialAddList(tactile.trial, list, before, after, Date.now())
    tactile.revision++
    tick()
    say("", false)
    Model.LISTS[list].swap(before, after, autoContext()).forEach(function (statement) {
      enqueue([tactile.hyprctl, "eval", statement], 3000, function (code, out) {
        var text = String(out || "").trim()
        // Removing a gesture a reload already dropped is fine.
        if (text.indexOf("non-existent") >= 0) return
        if (text.indexOf("overshadowed") >= 0)
          say("Your Hyprland config already has a gesture that covers this one, so it does nothing.", true)
        else if (code !== 0 || text !== "ok")
          say("Hyprland did not take that change: " + text.slice(0, 120), true)
      })
    })
    return true
  }

  // What finger drag is set to on the touchpad: swipes with those fingers drag instead.
  function dragSetting() {
    var pads = tactile.tunableDevices.filter(function (d) { return d.kind === "touchpad" })
    return pads.length > 0 ? Number(valueOf(pads[0].name, "drag_3fg")) || 0 : 0
  }

  // The apps with windows open, by class, to pick from.
  function refreshApps() {
    enqueue([tactile.hyprctl, "clients", "-j"], 3000, function (code, out) {
      var parsed = code === 0 ? parseJson(out) : null
      if (!(parsed instanceof Array)) return
      var seen = {}
      var apps = []
      parsed.forEach(function (c) {
        var cls = c && typeof c.class === "string" ? c.class : ""
        if (cls !== "" && Model.APP_RE.test(cls) && !seen[cls] && apps.length < 40) {
          seen[cls] = true
          apps.push(cls)
        }
      })
      apps.sort()
      tactile.openApps = apps
    })
  }

  // ---------------------------------------------------------------- the finger view

  function startFingers() {
    tactile.fingerError = ""
    tactile.fingersWanted = true
  }

  function stopFingers() {
    tactile.fingersWanted = false
    tactile.fingerFrame = null
  }

  function fingerLine(line) {
    if (typeof line !== "string" || line.length > 4096) return
    var o = null
    try { o = JSON.parse(line) } catch (e) { return }
    if (!o || typeof o !== "object") return
    if (typeof o.error === "string") tactile.fingerError = o.error.slice(0, 32)
    else if (o.pad && typeof o.pad === "object") tactile.fingerPad = o.pad
    else if (o.fingers instanceof Array) tactile.fingerFrame = o
  }

  function refreshFingerRule() {
    enqueue(["/usr/bin/test", "-f", tactile.fingerRule], 3000, function (code) { tactile.fingerRuleInstalled = code === 0 })
  }

  // Asks for the password through the desktop's polkit agent; nothing else runs as root.
  function fingerAccessChange(grant) {
    if (fingerAccess.running) return
    fingerAccess.grant = grant
    fingerAccess.command = ["/usr/bin/pkexec", "/usr/bin/sh", "-c", grant ? tactile.grantScript : tactile.revokeScript]
    tactile.fingerGranting = grant
    fingerAccess.running = true
    fingerAccessDeadline.restart()
  }

  Process {
    id: fingerReader
    command: ["/usr/bin/python3", tactile.fingerTool]
    running: tactile.windowOpen && tactile.fingersWanted && tactile.fingerError === ""
    stdout: SplitParser {
      onRead: function (line) { tactile.fingerLine(line) }
    }
    onExited: function (exitCode) {
      if (tactile.fingerError === "" && tactile.windowOpen && tactile.fingersWanted) tactile.fingerError = "read-failed"
    }
  }

  Process {
    id: fingerAccess
    property bool grant: true
    onExited: function (exitCode) {
      fingerAccessDeadline.stop()
      tactile.fingerGranting = false
      if (exitCode !== 0) {
        tactile.say(fingerAccess.grant ? "The touchpad stays private: the password was not given." : "Access stays as it was: the password was not given.", true)
        return
      }
      tactile.fingerRuleInstalled = fingerAccess.grant
      tactile.fingerPad = null
      tactile.fingerFrame = null
      if (fingerAccess.grant) fingerRetry.restart()
      else tactile.fingerError = "no-access"
    }
  }

  Timer {
    id: fingerAccessDeadline
    interval: 180000
    onTriggered: if (fingerAccess.running) fingerAccess.signal(15)
  }

  // Logind hands out the new access a moment after udev applies the rule.
  Timer {
    id: fingerRetry
    interval: 1200
    onTriggered: tactile.fingerError = ""
  }

  function keepTrial() {
    if (!tactile.trial) return
    var next = Model.withKept(tactile.settings, tactile.trial, tactile.globals)
    tactile.trial = null
    tactile.live = ({})
    tactile.trialLeft = 0
    writeSettings(next)
    tactile.revision++
    say("Kept.", false)
  }

  function undoTrial() {
    if (!tactile.trial) return
    var trial = tactile.trial
    tactile.trial = null
    tactile.live = ({})
    tactile.trialLeft = 0
    tactile.revision++
    // Worked out once the trial is gone, so a rule letting go of a setting hands back the kept value.
    Model.trialRevert(trial, autoContext()).forEach(function (s) { runStatement(s, null) })
  }

  function tick() {
    if (!tactile.trial) return
    tactile.trialLeft = Model.trialSeconds(tactile.trial, Date.now())
    if (tactile.trialLeft <= 0) {
      undoTrial()
      say("The time ran out, so your changes were put back.", false)
    }
  }

  Timer {
    interval: 250
    repeat: true
    running: tactile.trial !== null
    onTriggered: tactile.tick()
  }

  function writeSettings(next) {
    var payload = Model.settingsPayload(next)
    tactile.settings = Model.readSettings(payload)
    if (!tactile.shell || typeof tactile.shell.updateEntryInline !== "function" || !tactile.hasEntry) {
      say("Tactile could not save its settings: it has no entry in shell.json's plugin list.", true)
      return false
    }
    tactile.shell.updateEntryInline(tactile.pluginId, payload)
    return true
  }

  // What Tactile keeps, applied again (with what is on trial), and the rule that floats its window.
  function applySaved() {
    Model.applyAll(tactile.settings, autoContext()).forEach(function (s) { runStatement(s, null) })
    if (tactile.trial) {
      Object.keys(tactile.live).forEach(function (name) {
        var d = deviceNamed(name)
        if (d) runStatement(Model.deviceStatement(name, d.kind, tactile.live[name]), null)
      })
      var lists = tactile.trial.lists || {}
      Object.keys(lists).forEach(function (list) {
        if (!Model.LISTS[list]) return
        Model.LISTS[list].swap(tactile.settings[list] || [], lists[list].after, autoContext()).forEach(function (s) { runStatement(s, null) })
      })
    }
    runStatement(Model.windowRuleStatement(tactile.windowTitle), null)
  }

  // ---------------------------------------------------------------- the window

  Loader { id: windowLoader }

  // `tab` names a device or "gestures"; `lab` names a feel lab test to show.
  function openWindow(tab, lab) {
    tactile.windowOpen = true
    refreshDevices()
    refreshGlobals()
    refreshApps()
    refreshFingerRule()
    var test = Model.LAB_TESTS.some(function (t) { return t.id === lab }) ? String(lab) : ""
    if (windowLoader.item) {
      if (tab) windowLoader.item.tab = String(tab)
      if (test) windowLoader.item.labTest = test
      return
    }
    var props = { service: tactile, tab: String(tab || "") }
    if (test) props.labTest = test
    windowLoader.setSource(Qt.resolvedUrl("ui/TactileWindow.qml"), props)
  }

  function closeWindow() {
    if (windowLoader.item) windowLoader.item.closingFromHost = true
    windowLoader.source = ""
    tactile.windowOpen = false
    // Changes nobody kept do not outlive the window that was showing their countdown.
    if (tactile.trial) {
      undoTrial()
      enqueue([tactile.notifyTool, "-a", "Tactile", "Tactile", "Changes you did not keep were put back."], 3000, null)
    }
  }

  // Closed from the window itself (its close button, a Hyprland close key): tell the shell too.
  function windowClosed() {
    closeWindow()
    if (tactile.shell && typeof tactile.shell.hide === "function") tactile.shell.hide(tactile.pluginId)
  }

  // ---------------------------------------------------------------- the shortcut

  property bool shortcutBusy: false

  Timer {
    id: shortcutTimer
    interval: 500
    onTriggered: tactile.syncShortcut()
  }

  function syncShortcut() {
    if (tactile.shortcutBusy) {
      shortcutTimer.restart()
      return
    }
    tactile.shortcutBusy = true
    enqueue([tactile.hyprctl, "binds", "-j"], 3000, function (code, out) {
      var binds = code === 0 ? parseJson(out) : null
      if (!(binds instanceof Array)) {
        finishShortcut("unknown", "")
        return
      }
      var want = tactile.settings.shortcut
      if (tactile.boundCombo && tactile.boundCombo !== want && Model.bindState(binds, tactile.boundCombo) === "ours")
        enqueue([tactile.hyprctl, "eval", Model.unbindStatement(tactile.boundCombo)], 3000, null)
      var state = Model.bindState(binds, want)
      if (state !== "free") {
        finishShortcut(state, state === "ours" ? want : "")
        return
      }
      enqueue([tactile.hyprctl, "eval", Model.bindStatement(want, tactile.toggleCommand)], 3000, function (evalCode, evalOut) {
        var ok = evalCode === 0 && String(evalOut || "").toLowerCase().indexOf("error") < 0
        finishShortcut(ok ? "ours" : "failed", ok ? want : "")
      })
    })
  }

  function finishShortcut(state, combo) {
    tactile.shortcutState = state
    tactile.boundCombo = combo
    tactile.shortcutBusy = false
  }

  // A reload drops runtime device settings, window rules and binds alike.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event) return
      if (event.name === "configreloaded") reloadTimer.restart()
      else if (event.name === "activewindow") tactile.focusMoved(String(event.data || "").split(",")[0])
    }
  }

  Timer {
    id: reloadTimer
    interval: 400
    onTriggered: {
      tactile.applySaved()
      tactile.syncShortcut()
      tactile.refreshGlobals()
    }
  }

  // ---------------------------------------------------------------- start and stop

  Timer {
    interval: 3000
    repeat: true
    running: true
    triggeredOnStart: true
    property int tries: 0
    onTriggered: {
      if (tactile.loaded || tries >= 20) {
        stop()
        return
      }
      tries++
      if (tactile.job || tactile.queue.length > 0) return
      tactile.refreshConfig(function (ok) {
        if (!ok) return
        tactile.refreshDevices()
        tactile.refreshGlobals()
        tactile.applySaved()
        tactile.refreshFocus()
        shortcutTimer.restart()
      })
    }
  }

  Component.onDestruction: {
    if (tactile.shortcutState === "ours" && tactile.boundCombo)
      Quickshell.execDetached(["/usr/bin/timeout", "3", tactile.hyprctl, "eval", Model.unbindStatement(tactile.boundCombo)])
    // A touchpad Tactile turned off must not stay off once Tactile is gone.
    Model.readPadOff(tactile.listOf("padOff")).forEach(function (name) {
      Quickshell.execDetached(["/usr/bin/timeout", "3", tactile.hyprctl, "eval", Model.enabledStatement(name, true)])
    })
  }
}
