import QtQuick
import qs.Commons

// Pinching: a card that zooms and turns with two fingers on the pad.
Item {
  id: pinchTest

  property string kind: ""
  property var values: ({})
  property color ink: Color.menu.text
  property color accent: Color.accent
  property color faint: Qt.rgba(pinchTest.ink.r, pinchTest.ink.g, pinchTest.ink.b, 0.62)
  property color hairline: Qt.rgba(pinchTest.ink.r, pinchTest.ink.g, pinchTest.ink.b, 0.12)

  property real biggest: 1
  property real smallest: 1

  function reset() {
    card.scale = 1
    card.rotation = 0
    card.x = Math.round((pinchTest.width - card.width) / 2)
    card.y = Math.round((pinchTest.height - card.height) / 2)
    pinchTest.biggest = 1
    pinchTest.smallest = 1
  }

  onWidthChanged: if (!pinch.active) pinchTest.reset()
  onHeightChanged: if (!pinch.active) pinchTest.reset()

  Column {
    anchors { left: parent.left; top: parent.top; margins: Style.space(18) }
    spacing: Style.space(2)

    Text {
      text: card.scale.toFixed(2) + "×  " + Math.round(card.rotation) + "°"
      color: pinch.active ? pinchTest.accent : pinchTest.ink
      font.family: Style.font.family
      font.pixelSize: Style.font.heading
      font.bold: true
      font.features: { "tnum": 1 }
    }

    Text {
      text: "from " + pinchTest.smallest.toFixed(2) + "× to " + pinchTest.biggest.toFixed(2) + "×"
      color: pinchTest.faint
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.features: { "tnum": 1 }
    }
  }

  Rectangle {
    id: card
    width: Style.space(200)
    height: Style.space(130)
    radius: Style.cornerRadius
    antialiasing: true
    color: Qt.rgba(pinchTest.accent.r, pinchTest.accent.g, pinchTest.accent.b, 0.18)
    border.width: 1
    border.color: pinchTest.accent

    onScaleChanged: {
      pinchTest.biggest = Math.max(pinchTest.biggest, scale)
      pinchTest.smallest = Math.min(pinchTest.smallest, scale)
    }

    Text {
      anchors.centerIn: parent
      text: pinchTest.kind === "touchpad" ? "Pinch me" : "Needs a touchpad"
      color: pinchTest.ink
      font.family: Style.font.family
      font.pixelSize: Style.font.title
      font.bold: true
    }
  }

  PinchHandler {
    id: pinch
    target: card
    scaleAxis.minimum: 0.3
    scaleAxis.maximum: 4
  }

  TapHandler {
    onDoubleTapped: pinchTest.reset()
  }
}
