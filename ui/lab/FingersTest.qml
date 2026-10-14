import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Fingers: where each finger rests on the pad, drawn live at the pad's real proportions, once Tactile may read it.
Item {
  id: fingersTest

  property var service: null
  property string kind: ""
  property var values: ({})
  property color ink: Commons.Color.menu.text
  property color accent: Commons.Color.accent
  property color faint: Qt.rgba(fingersTest.ink.r, fingersTest.ink.g, fingersTest.ink.b, 0.62)
  property color hairline: Qt.rgba(fingersTest.ink.r, fingersTest.ink.g, fingersTest.ink.b, 0.12)

  readonly property string error: fingersTest.service ? fingersTest.service.fingerError : ""
  readonly property var pad: fingersTest.service ? fingersTest.service.fingerPad : null
  readonly property var frame: fingersTest.service ? fingersTest.service.fingerFrame : null
  readonly property var fingers: fingersTest.frame && fingersTest.frame.fingers ? fingersTest.frame.fingers : []
  readonly property int count: fingersTest.frame ? fingersTest.frame.count : 0
  readonly property real aspect: fingersTest.pad && fingersTest.pad.width_mm && fingersTest.pad.height_mm
    ? fingersTest.pad.width_mm / fingersTest.pad.height_mm : 1.6
  readonly property bool live: fingersTest.error === "" && fingersTest.pad !== null

  Component.onCompleted: if (fingersTest.service) fingersTest.service.startFingers()
  onServiceChanged: if (fingersTest.service) fingersTest.service.startFingers()
  Component.onDestruction: if (fingersTest.service) fingersTest.service.stopFingers()

  Column {
    id: readout
    visible: fingersTest.live
    anchors { left: parent.left; top: parent.top; margins: Style.space(18) }
    spacing: Style.space(2)

    Text {
      text: fingersTest.count === 0 ? "No fingers" : fingersTest.count === 1 ? "1 finger" : fingersTest.count + " fingers"
      color: fingersTest.count > 0 ? fingersTest.accent : fingersTest.ink
      font.family: Style.font.family
      font.pixelSize: Style.font.heading
      font.bold: true
    }

    Text {
      textFormat: Text.PlainText
      text: !fingersTest.pad ? "" : fingersTest.pad.width_mm && fingersTest.pad.height_mm
        ? "Touchpad · " + Math.round(fingersTest.pad.width_mm) + " × " + Math.round(fingersTest.pad.height_mm) + " mm" : "Touchpad"
      color: fingersTest.faint
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }

  Rectangle {
    visible: fingersTest.live
    anchors { right: parent.right; top: parent.top; margins: Style.space(18) }
    width: clickText.implicitWidth + Style.space(20)
    height: clickText.implicitHeight + Style.space(10)
    radius: Style.cornerRadius
    color: fingersTest.frame && fingersTest.frame.button ? Qt.rgba(fingersTest.accent.r, fingersTest.accent.g, fingersTest.accent.b, 0.3) : "transparent"
    border.width: 1
    border.color: fingersTest.frame && fingersTest.frame.button ? fingersTest.accent : fingersTest.hairline

    Text {
      id: clickText
      anchors.centerIn: parent
      text: "Click"
      color: fingersTest.ink
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }
  }

  Item {
    id: area
    visible: fingersTest.live
    anchors { left: parent.left; right: parent.right; top: readout.bottom; bottom: revoke.top; margins: Style.space(18) }

    Rectangle {
      id: padShape
      readonly property real fit: Math.min(area.width, area.height * fingersTest.aspect)
      width: padShape.fit
      height: padShape.fit / fingersTest.aspect
      anchors.centerIn: parent
      radius: Math.max(Style.cornerRadius, Style.space(10))
      color: "transparent"
      border.width: 1
      border.color: fingersTest.faint

      Repeater {
        model: fingersTest.fingers

        delegate: Rectangle {
          required property var modelData
          readonly property real size: Style.space(40) * (typeof modelData.p === "number" ? 0.7 + modelData.p * 0.8 : 1)

          width: size
          height: size
          radius: size / 2
          x: modelData.x * padShape.width - size / 2
          y: modelData.y * padShape.height - size / 2
          color: Qt.rgba(fingersTest.accent.r, fingersTest.accent.g, fingersTest.accent.b, 0.35)
          border.width: 2
          border.color: fingersTest.accent

          Text {
            anchors.centerIn: parent
            text: String(modelData.slot + 1)
            color: fingersTest.ink
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }
        }
      }
    }
  }

  Text {
    id: revoke
    visible: fingersTest.live && fingersTest.service !== null && fingersTest.service.fingerRuleInstalled
    anchors { right: parent.right; bottom: parent.bottom; margins: Style.space(18) }
    text: "Stop letting apps read the touchpad"
    color: revokeMouse.containsMouse ? fingersTest.accent : fingersTest.faint
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.underline: true

    MouseArea {
      id: revokeMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: if (fingersTest.service) fingersTest.service.fingerAccessChange(false)
    }
  }

  Column {
    visible: !fingersTest.live
    anchors.centerIn: parent
    width: Math.min(parent.width - Style.space(48), Style.space(420))
    spacing: Style.space(12)

    Text {
      width: parent.width
      wrapMode: Text.Wrap
      text: fingersTest.error === "no-access" ? "Tactile cannot see the touchpad yet"
        : fingersTest.error === "no-touchpad" ? "No touchpad found"
        : fingersTest.error === "not-multitouch" ? "This touchpad does not report separate fingers"
        : fingersTest.error === "read-failed" ? "The finger view stopped"
        : "Looking at the touchpad…"
      color: fingersTest.ink
      font.family: Style.font.family
      font.pixelSize: Style.font.heading
      font.bold: true
    }

    Text {
      visible: fingersTest.error === "no-access"
      width: parent.width
      wrapMode: Text.Wrap
      text: "Linux keeps the touchpad's raw input private. Tactile can add one system rule, " +
        "/etc/udev/rules.d/70-tactile-touchpad.rules, that lets the person logged in read touchpads, never keyboards. " +
        "It asks for your password once, and the link here takes it back."
      color: fingersTest.faint
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    Text {
      visible: fingersTest.error === "read-failed"
      width: parent.width
      wrapMode: Text.Wrap
      text: "Switch to another test and back to start it again."
      color: fingersTest.faint
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    Button {
      visible: fingersTest.error === "no-access"
      text: fingersTest.service && fingersTest.service.fingerGranting ? "Waiting for your password…" : "Let Tactile see the touchpad"
      selected: true
      bordered: true
      enabled: !!fingersTest.service && !fingersTest.service.fingerGranting
      foreground: fingersTest.ink
      accent: fingersTest.accent
      onClicked: if (fingersTest.service) fingersTest.service.fingerAccessChange(true)
    }
  }
}
