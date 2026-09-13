import Quickshell
import QtQuick

// Tactile as the shell opens it (`omarchy-shell shell toggle reidenxerx.tactile`, the shortcut, or the menu). The
// window belongs to the service, since the shell makes overlays anew now and then; this passes open and close along
// and reports Tactile open for as long as its window is.
Item {
  id: launcher

  property var shell: null
  property var manifest: null
  property var service: null
  property string omarchyPath: ""
  property bool opened: launcher.service ? launcher.service.windowOpen === true : false

  readonly property string pluginId: "reidenxerx.tactile"

  function tactile() {
    if (!launcher.service && launcher.shell && typeof launcher.shell.serviceFor === "function")
      launcher.service = launcher.shell.serviceFor(launcher.pluginId)
    if (!launcher.service) console.warn("Tactile: the service is not running, so the window cannot open")
    return launcher.service
  }

  // The payload may name a device or "gestures" to open on, and a feel lab test: {"tab": "logitech-mx-master-3s", "lab": "aim"}.
  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") || {} } catch (e) { payload = {} }
    var service = launcher.tactile()
    if (service) service.openWindow(typeof payload.tab === "string" ? payload.tab.slice(0, 128) : "",
                                    typeof payload.lab === "string" ? payload.lab.slice(0, 16) : "")
  }

  function close() {
    var service = launcher.tactile()
    if (service) service.closeWindow()
  }

  function toggle() {
    var service = launcher.tactile()
    if (!service) return
    if (service.windowOpen) service.windowClosed()
    else service.openWindow("")
  }

  // For scripts, through `omarchy-shell shell call reidenxerx.tactile <verb> '<json>'`:
  //   set {"device": "<name>", "field": "scroll_factor", "value": 0.5}   a change on trial, as if made in the window
  //   keep, undo                                                          the trial's two buttons
  //   state {"device": "<name>"}                                          what Tactile knows, as JSON
  function argsOf(argJson) {
    try {
      var a = JSON.parse(argJson || "{}")
      return a !== null && typeof a === "object" && !(a instanceof Array) ? a : {}
    } catch (e) {
      return {}
    }
  }

  function set(argJson) {
    var service = launcher.tactile()
    if (!service) return "no-service"
    var a = launcher.argsOf(argJson)
    if (typeof a.device !== "string" || typeof a.field !== "string") return "bad-args"
    if (!service.loaded || !service.globalsReady) return "not-ready"
    service.setValue(a.device.slice(0, 128), a.field.slice(0, 64), a.value)
    return service.trial ? "trial" : "unchanged"
  }

  function keep() {
    var service = launcher.tactile()
    if (!service) return "no-service"
    service.keepTrial()
    return "ok"
  }

  function undo() {
    var service = launcher.tactile()
    if (!service) return "no-service"
    service.undoTrial()
    return "ok"
  }

  //   gestures {"list": [{"fingers": 3, "direction": "horizontal", "action": "workspace"}]}   Tactile's gestures, on trial
  //   apps {"list": [{"app": "foot", "touchpad": 1.5}]}                                        scroll speed per app, on trial
  // The list is wrapped in an object because `qs ipc call` reads an argument starting with "[" as a list of its own.
  function listArg(argJson) {
    var a = launcher.argsOf(argJson)
    return a.list instanceof Array ? a.list.slice(0, 64) : null
  }

  function setListVerb(list, argJson) {
    var service = launcher.tactile()
    if (!service) return "no-service"
    var items = launcher.listArg(argJson)
    if (items === null) return "bad-args"
    return service.setList(list, items) ? "trial" : "unchanged"
  }

  function gestures(argJson) { return launcher.setListVerb("gestures", argJson) }

  function apps(argJson) { return launcher.setListVerb("apps", argJson) }

  //   padOff {"list": ["<touchpad name>"]}                                              off while a mouse is listed
  //   profiles {"list": [{"app": "dota2", "device": "<name>", "kind": "mouse", "values": {"accel_profile": "flat"}}]}
  function padOff(argJson) { return launcher.setListVerb("padOff", argJson) }

  function profiles(argJson) { return launcher.setListVerb("profiles", argJson) }

  function state(argJson) {
    var service = launcher.tactile()
    if (!service) return "{}"
    var name = String(launcher.argsOf(argJson).device || "").slice(0, 128)
    return JSON.stringify({
      loaded: service.loaded, globalsReady: service.globalsReady, windowOpen: service.windowOpen,
      devices: service.tunableDevices, trialChanges: service.trialChanges, trialLeft: service.trialLeft,
      shortcut: service.shortcutState, status: service.status,
      values: name ? service.valuesOf(name) : null, kept: name ? service.keptCount(name) : 0,
      gestures: service.listOf("gestures"), apps: service.listOf("apps"), openApps: service.openApps,
      padOff: service.listOf("padOff"), profiles: service.listOf("profiles"), mousePresent: service.mousePresent,
      focusedApp: service.focusedApp, fingerError: service.fingerError, fingerRuleInstalled: service.fingerRuleInstalled,
      fingerPad: service.fingerPad, fingerCount: service.fingerFrame ? service.fingerFrame.count : 0
    })
  }
}
