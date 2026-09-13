import Quickshell
import QtQuick
import qs.Commons
import qs.Ui
import "../TactileModel.js" as Model

// Tactile's window: your pointer devices along the top, the chosen one's settings on the left, the feel lab on the
// right, and along the bottom the trial that puts changes back unless you keep them.
FloatingWindow {
  id: tactileWindow

  property var service: null
  property string tab: ""
  property bool closingFromHost: false
  property string deviceName: ""
  property string labTest: "scroll"
  // "device" for a device's settings, "gestures" for gestures and scroll speed per app.
  property string page: "device"

  readonly property var devices: tactileWindow.service ? tactileWindow.service.tunableDevices : []
  readonly property var device: {
    var list = tactileWindow.devices
    for (var i = 0; i < list.length; i++) if (list[i].name === tactileWindow.deviceName) return list[i]
    return list.length > 0 ? list[0] : null
  }
  readonly property string kind: tactileWindow.device ? tactileWindow.device.kind : ""
  readonly property var values: tactileWindow.service && tactileWindow.device
    ? tactileWindow.service.valuesOf(tactileWindow.device.name) : ({})
  readonly property bool trying: !!(tactileWindow.service && tactileWindow.service.trial)
  readonly property bool ready: !!(tactileWindow.service && tactileWindow.service.loaded && tactileWindow.service.globalsReady)

  readonly property color paper: Qt.rgba(Color.menu.background.r, Color.menu.background.g, Color.menu.background.b, 1)
  readonly property color ink: Color.menu.text
  readonly property color accent: Color.accent
  readonly property color faint: Qt.rgba(tactileWindow.ink.r, tactileWindow.ink.g, tactileWindow.ink.b, 0.62)
  readonly property color hairline: Qt.rgba(tactileWindow.ink.r, tactileWindow.ink.g, tactileWindow.ink.b, 0.12)
  readonly property color wash: Qt.rgba(tactileWindow.ink.r, tactileWindow.ink.g, tactileWindow.ink.b, 0.04)

  title: "Tactile"
  color: tactileWindow.paper
  implicitWidth: 1040
  implicitHeight: 720
  minimumSize: Qt.size(880, 600)

  onTabChanged: tactileWindow.applyTab()
  Component.onCompleted: tactileWindow.applyTab()

  function applyTab() {
    if (tactileWindow.tab === "gestures") {
      tactileWindow.page = "gestures"
    } else if (tactileWindow.tab !== "") {
      tactileWindow.page = "device"
      tactileWindow.deviceName = tactileWindow.tab
    }
  }

  // Closed by Hyprland (a close key) rather than by the shell: the service puts back what was not kept.
  onVisibleChanged: {
    if (!visible && !tactileWindow.closingFromHost && tactileWindow.service) tactileWindow.service.windowClosed()
  }

  // A change made in the settings: the lab turns to the test that shows it.
  function change(field, value) {
    if (!tactileWindow.service || !tactileWindow.device) return
    var test = Model.testFor(field)
    if (test !== "") tactileWindow.labTest = test
    tactileWindow.service.setValue(tactileWindow.device.name, field, value)
  }

  function barText() {
    var s = tactileWindow.service
    if (!s) return ""
    if (s.status !== "" && (s.statusIsError || !tactileWindow.trying)) return s.status
    if (!tactileWindow.trying) return "Every change applies at once, and puts itself back unless you keep it."
    var n = s.trialChanges
    var left = s.trialLeft + " s"
    if (n === 0) return "Back as it was · " + left
    return (n === 1 ? "1 change" : n + " changes") + " on trial · put back in " + left + " unless you keep " + (n === 1 ? "it" : "them")
  }

  // The window's ground, painted in the scene as well so the page stays solid whatever the surface is cleared with.
  Rectangle {
    anchors.fill: parent
    color: tactileWindow.paper
  }

  Item {
    id: page
    anchors.fill: parent
    anchors.margins: Style.space(20)
    focus: true

    Keys.onPressed: function (event) {
      if (event.key === Qt.Key_Escape) {
        event.accepted = true
        if (tactileWindow.service) tactileWindow.service.windowClosed()
      } else if (event.key === Qt.Key_Z && (event.modifiers & Qt.ControlModifier)) {
        event.accepted = true
        if (tactileWindow.service) tactileWindow.service.undoTrial()
      }
    }

    Item {
      id: header
      anchors { top: parent.top; left: parent.left; right: parent.right }
      height: Math.max(brand.implicitHeight, deviceTabs.implicitHeight)

      Column {
        id: brand
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        spacing: Style.space(2)

        Text {
          text: "Tactile"
          color: tactileWindow.ink
          font.family: Style.font.family
          font.pixelSize: Style.font.display
          font.bold: true
          font.letterSpacing: 1
        }

        Text {
          text: tactileWindow.page === "gestures" ? "Gestures and scroll speed per app"
            : tactileWindow.kind === "mouse" ? "Your mouse, tuned by feel" : "Your touchpad, tuned by feel"
          color: tactileWindow.faint
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      ButtonGroup {
        id: deviceTabs
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        focusable: false
        options: tactileWindow.devices.map(function (d) { return { value: d.name, label: d.label, tooltip: d.name } })
          .concat([{ value: "gestures", label: "Gestures" }])
        value: tactileWindow.page === "gestures" ? "gestures" : tactileWindow.device ? tactileWindow.device.name : ""
        foreground: tactileWindow.ink
        background: "transparent"
        accent: tactileWindow.accent
        onChanged: function (v) {
          if (v === "gestures") {
            tactileWindow.page = "gestures"
          } else {
            tactileWindow.page = "device"
            tactileWindow.deviceName = v
          }
        }
      }
    }

    Rectangle {
      id: rule
      anchors { top: header.bottom; topMargin: Style.space(16); left: parent.left; right: parent.right }
      height: 1
      color: tactileWindow.hairline
    }

    SettingsList {
      id: settingsList
      visible: tactileWindow.page === "device" && tactileWindow.device !== null && tactileWindow.ready
      anchors { top: rule.bottom; topMargin: Style.space(14); left: parent.left; bottom: trialBar.top; bottomMargin: Style.space(14) }
      width: Math.round(page.width * 0.45)
      service: tactileWindow.service
      device: tactileWindow.device
      values: tactileWindow.values
      ink: tactileWindow.ink
      accent: tactileWindow.accent
      faint: tactileWindow.faint
      hairline: tactileWindow.hairline
      onEdited: function (field, value) { tactileWindow.change(field, value) }
    }

    FeelLab {
      id: lab
      visible: settingsList.visible
      anchors {
        top: rule.bottom; topMargin: Style.space(14); bottom: trialBar.top; bottomMargin: Style.space(14)
        left: settingsList.right; leftMargin: Style.space(22); right: parent.right
      }
      kind: tactileWindow.kind
      values: tactileWindow.values
      test: tactileWindow.labTest
      service: tactileWindow.service
      ink: tactileWindow.ink
      accent: tactileWindow.accent
      faint: tactileWindow.faint
      hairline: tactileWindow.hairline
      wash: tactileWindow.wash
      onPicked: function (id) { tactileWindow.labTest = id }
    }

    GesturesPage {
      id: gesturesPage
      visible: tactileWindow.page === "gestures" && tactileWindow.ready
      anchors { top: rule.bottom; topMargin: Style.space(14); left: parent.left; bottom: trialBar.top; bottomMargin: Style.space(14) }
      width: Math.round(page.width * 0.52)
      service: tactileWindow.service
      ink: tactileWindow.ink
      accent: tactileWindow.accent
      faint: tactileWindow.faint
      hairline: tactileWindow.hairline
    }

    GestureMap {
      visible: gesturesPage.visible
      anchors {
        top: rule.bottom; topMargin: Style.space(14); bottom: trialBar.top; bottomMargin: Style.space(14)
        left: gesturesPage.right; leftMargin: Style.space(22); right: parent.right
      }
      gestures: gesturesPage.gestures
      dragSetting: tactileWindow.service ? tactileWindow.service.dragSetting() : 0
      ink: tactileWindow.ink
      accent: tactileWindow.accent
      faint: tactileWindow.faint
      hairline: tactileWindow.hairline
    }

    Text {
      visible: !settingsList.visible && !gesturesPage.visible
      anchors { top: rule.bottom; left: parent.left; right: parent.right; bottom: trialBar.top }
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      wrapMode: Text.Wrap
      text: !tactileWindow.ready ? "Reading your devices…" : "Hyprland reports no touchpad or mouse to tune."
      color: tactileWindow.faint
      font.family: Style.font.family
      font.pixelSize: Style.font.subtitle
    }

    Rectangle {
      id: trialBar
      anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
      height: Math.max(Style.space(50), trialButtons.implicitHeight + Style.space(16))
      radius: Style.cornerRadius
      color: tactileWindow.trying
        ? Qt.rgba(tactileWindow.accent.r, tactileWindow.accent.g, tactileWindow.accent.b, 0.12) : tactileWindow.wash
      border.width: 1
      border.color: tactileWindow.trying
        ? Qt.rgba(tactileWindow.accent.r, tactileWindow.accent.g, tactileWindow.accent.b, 0.5) : tactileWindow.hairline
      clip: true

      Behavior on color { ColorAnimation { duration: 160 } }

      // The time left before the changes put themselves back.
      Rectangle {
        anchors { left: parent.left; bottom: parent.bottom }
        height: Style.space(3)
        width: tactileWindow.trying ? trialBar.width * Math.min(1, tactileWindow.service.trialLeft * 1000 / Model.TRIAL_MS) : 0
        color: tactileWindow.accent

        Behavior on width { NumberAnimation { duration: 900 } }
      }

      Text {
        anchors {
          left: parent.left; leftMargin: Style.space(16); right: trialButtons.left; rightMargin: Style.space(12)
          verticalCenter: parent.verticalCenter
        }
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: tactileWindow.barText()
        color: tactileWindow.service && tactileWindow.service.statusIsError && tactileWindow.service.status !== "" ? Color.urgent
          : tactileWindow.trying ? tactileWindow.ink : tactileWindow.faint
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }

      Row {
        id: trialButtons
        anchors { right: parent.right; rightMargin: Style.space(8); verticalCenter: parent.verticalCenter }
        spacing: Style.space(8)
        visible: tactileWindow.trying
        width: visible ? implicitWidth : 0

        Button {
          text: "Undo"
          bordered: true
          tooltipText: "Put it all back now (Ctrl+Z)"
          foreground: tactileWindow.ink
          accent: tactileWindow.accent
          onClicked: if (tactileWindow.service) tactileWindow.service.undoTrial()
        }

        Button {
          text: "Keep"
          selected: true
          bordered: true
          tooltipText: "Keep these settings, now and after restarts"
          foreground: tactileWindow.ink
          accent: tactileWindow.accent
          onClicked: if (tactileWindow.service) tactileWindow.service.keepTrial()
        }
      }
    }
  }
}
