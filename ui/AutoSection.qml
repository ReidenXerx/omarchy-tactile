import QtQuick
import qs.Commons
import qs.Ui
import "../TactileModel.js" as Model

// What a device does by itself: a touchpad that turns off while a mouse is connected, and settings used only while one
// app has focus. Changes go on trial like everything else.
Column {
  id: autoSection

  property var service: null
  property var device: null
  property color ink: Color.menu.text
  property color accent: Color.accent
  property color faint: Qt.rgba(autoSection.ink.r, autoSection.ink.g, autoSection.ink.b, 0.62)
  property color hairline: Qt.rgba(autoSection.ink.r, autoSection.ink.g, autoSection.ink.b, 0.12)

  readonly property bool isPad: !!autoSection.device && autoSection.device.kind === "touchpad"
  readonly property var padOff: autoSection.service ? autoSection.service.listOf("padOff") : []
  readonly property bool padOffOn: autoSection.isPad && autoSection.padOff.indexOf(autoSection.device.name) >= 0
  readonly property var allProfiles: autoSection.service ? autoSection.service.listOf("profiles") : []
  readonly property var profiles: autoSection.device
    ? autoSection.allProfiles.filter(function (p) { return p.device === autoSection.device.name }) : []
  readonly property var freeApps: autoSection.service ? autoSection.service.openApps.filter(function (a) {
    return a !== "org.quickshell" && !autoSection.profiles.some(function (p) { return p.app === a })
  }) : []

  spacing: Style.space(12)

  function setProfiles(next) {
    if (autoSection.service) autoSection.service.setList("profiles", next)
  }

  function copyProfiles() {
    return autoSection.allProfiles.map(function (p) {
      return { app: p.app, device: p.device, kind: p.kind, values: JSON.parse(JSON.stringify(p.values)) }
    })
  }

  function addProfile(app) {
    var next = autoSection.copyProfiles()
    next.push({ app: app, device: autoSection.device.name, kind: autoSection.device.kind, values: { accel_profile: "flat" } })
    autoSection.setProfiles(next)
  }

  function setProfileValue(app, field, value) {
    var next = autoSection.copyProfiles()
    var p = next.filter(function (x) { return x.app === app && x.device === autoSection.device.name })[0]
    if (!p) return
    p.values[field] = value
    autoSection.setProfiles(next)
  }

  function removeProfile(app) {
    autoSection.setProfiles(autoSection.copyProfiles().filter(function (x) {
      return !(x.app === app && x.device === autoSection.device.name)
    }))
  }

  component Caption: Text {
    wrapMode: Text.Wrap
    color: autoSection.faint
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  Item { width: 1; height: Style.space(4) }

  Text {
    text: "AUTOMATICALLY"
    color: autoSection.faint
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1.5
  }

  Item {
    visible: autoSection.isPad
    width: parent.width
    height: Math.max(padLabel.implicitHeight, padToggle.implicitHeight)

    Column {
      id: padLabel
      anchors { left: parent.left; right: padToggle.left; rightMargin: Style.space(12); verticalCenter: parent.verticalCenter }
      spacing: Style.space(2)

      Text {
        text: "Turn off while a mouse is connected"
        color: autoSection.ink
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }

      Caption {
        width: parent.width
        text: autoSection.service && autoSection.service.mousePresent
          ? "A mouse is connected now, so turning this on turns the touchpad off at once. It comes back on when the mouse goes."
          : "No mouse is connected now. The touchpad turns off when one is."
      }
    }

    ToggleSwitch {
      id: padToggle
      anchors { right: parent.right; verticalCenter: parent.verticalCenter }
      checked: autoSection.padOffOn
      foreground: autoSection.ink
      accent: autoSection.accent
      onToggled: {
        if (!autoSection.service || !autoSection.device) return
        var name = autoSection.device.name
        autoSection.service.setList("padOff", autoSection.padOffOn
          ? autoSection.padOff.filter(function (n) { return n !== name })
          : autoSection.padOff.concat([name]))
      }
    }
  }

  Column {
    width: parent.width
    spacing: Style.space(2)

    Text {
      text: "In one app"
      color: autoSection.ink
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    Caption {
      width: parent.width
      text: "Settings used only while that app has focus, such as flat acceleration for a game."
    }
  }

  Repeater {
    model: autoSection.profiles.length

    delegate: Column {
      id: profileRow
      required property int index
      readonly property var profile: autoSection.profiles[index] || null
      readonly property var values: profileRow.profile ? profileRow.profile.values : ({})

      width: autoSection.width
      spacing: Style.space(6)

      Item {
        width: parent.width
        height: Math.max(appTitle.implicitHeight, removeChip.implicitHeight)

        Text {
          id: appTitle
          anchors { left: parent.left; right: removeChip.left; rightMargin: Style.space(8); verticalCenter: parent.verticalCenter }
          elide: Text.ElideRight
          textFormat: Text.PlainText
          text: profileRow.profile ? profileRow.profile.app : ""
          color: autoSection.ink
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
        }

        Button {
          id: removeChip
          anchors { right: parent.right; verticalCenter: parent.verticalCenter }
          text: "Remove"
          bordered: true
          fontSize: Style.font.bodySmall
          foreground: autoSection.ink
          accent: autoSection.accent
          onClicked: if (profileRow.profile) autoSection.removeProfile(profileRow.profile.app)
        }
      }

      ButtonGroup {
        focusable: false
        spacing: Style.space(6)
        options: [{ value: "adaptive", label: "Adaptive" }, { value: "flat", label: "Flat" }]
        value: typeof profileRow.values.accel_profile === "string" ? profileRow.values.accel_profile : ""
        foreground: autoSection.ink
        background: "transparent"
        accent: autoSection.accent
        fontSize: Style.font.bodySmall
        onChanged: function (v) { if (profileRow.profile) autoSection.setProfileValue(profileRow.profile.app, "accel_profile", v) }
      }

      Item {
        width: parent.width
        height: profileSlider.implicitHeight

        Text {
          id: speedLabel
          anchors { left: parent.left; verticalCenter: parent.verticalCenter }
          text: "Pointer speed"
          color: autoSection.faint
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        PanelSlider {
          id: profileSlider
          anchors {
            left: speedLabel.right; leftMargin: Style.space(10); right: speedReadout.left; rightMargin: Style.space(10)
            verticalCenter: parent.verticalCenter
          }
          minimum: -1
          maximum: 1
          step: 0.05
          tickCount: 3
          tickColor: Qt.rgba(Color.menu.background.r, Color.menu.background.g, Color.menu.background.b, 1)
          value: typeof profileRow.values.sensitivity === "number" ? profileRow.values.sensitivity : 0
          trackColor: autoSection.hairline
          fillColor: autoSection.accent
          knobColor: autoSection.ink
          onReleased: function (v) {
            if (profileRow.profile) autoSection.setProfileValue(profileRow.profile.app, "sensitivity", Math.round(v * 20) / 20)
          }
        }

        Text {
          id: speedReadout
          anchors { right: parent.right; verticalCenter: parent.verticalCenter }
          readonly property real shown: profileSlider.dragging ? profileSlider.liveValue : profileSlider.value
          text: typeof profileRow.values.sensitivity === "number" || profileSlider.dragging
            ? (shown > 0 ? "+" : "") + shown.toFixed(2) : "as usual"
          color: autoSection.ink
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.features: { "tnum": 1 }
        }
      }
    }
  }

  Caption {
    width: parent.width
    text: autoSection.freeApps.length > 0 ? "Give settings to an app that has a window open:" : "Open an app to give it settings here."
  }

  Flow {
    width: parent.width
    spacing: Style.space(6)

    Repeater {
      model: autoSection.freeApps

      delegate: Button {
        required property var modelData
        text: String(modelData)
        bordered: true
        fontSize: Style.font.bodySmall
        foreground: autoSection.ink
        accent: autoSection.accent
        onClicked: if (autoSection.device) autoSection.addProfile(String(modelData))
      }
    }
  }
}
