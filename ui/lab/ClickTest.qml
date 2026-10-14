import QtQuick
import qs.Commons
import qs.Commons as Commons

// Clicking: which button each tap or press reached.
Item {
  id: clickTest

  property string kind: ""
  property var values: ({})
  property color ink: Commons.Color.menu.text
  property color accent: Commons.Color.accent
  property color faint: Qt.rgba(clickTest.ink.r, clickTest.ink.g, clickTest.ink.b, 0.62)
  property color hairline: Qt.rgba(clickTest.ink.r, clickTest.ink.g, clickTest.ink.b, 0.12)

  property string lastText: ""
  property int lastButton: 0
  property var counts: ({ left: 0, middle: 0, right: 0 })

  readonly property var buttons: [
    { id: "left", title: "Left", button: Qt.LeftButton },
    { id: "middle", title: "Middle", button: Qt.MiddleButton },
    { id: "right", title: "Right", button: Qt.RightButton }
  ]

  function hit(button) {
    var name = button === Qt.RightButton ? "right" : button === Qt.MiddleButton ? "middle" : "left"
    var next = { left: clickTest.counts.left, middle: clickTest.counts.middle, right: clickTest.counts.right }
    next[name]++
    clickTest.counts = next
    clickTest.lastText = name.charAt(0).toUpperCase() + name.slice(1) + " click"
    clickTest.lastButton = button
    flash.restart()
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    onPressed: function (mouse) { clickTest.hit(mouse.button) }
    onDoubleClicked: function (mouse) {
      if (mouse.button !== Qt.LeftButton) return
      clickTest.lastText = "Double click"
      flash.restart()
    }
  }

  Timer {
    id: flash
    interval: 700
  }

  Text {
    anchors.centerIn: parent
    anchors.verticalCenterOffset: -Style.space(30)
    text: clickTest.lastText === "" ? "Click or tap here" : clickTest.lastText
    color: flash.running ? clickTest.accent : (clickTest.lastText === "" ? clickTest.faint : clickTest.ink)
    font.family: Style.font.family
    font.pixelSize: Style.font.displayLarge
    font.bold: true

    Behavior on color { ColorAnimation { duration: 200 } }
  }

  Row {
    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: Style.space(24) }
    spacing: Style.space(10)

    Repeater {
      model: clickTest.buttons

      delegate: Rectangle {
        id: chip
        required property var modelData
        readonly property bool lit: flash.running && clickTest.lastButton === modelData.button

        width: Style.space(96)
        height: Style.space(64)
        radius: Style.cornerRadius
        color: chip.lit ? Qt.rgba(clickTest.accent.r, clickTest.accent.g, clickTest.accent.b, 0.28) : "transparent"
        border.width: 1
        border.color: chip.lit ? clickTest.accent : clickTest.hairline

        Behavior on color { ColorAnimation { duration: 160 } }

        Column {
          anchors.centerIn: parent
          spacing: Style.space(2)

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: chip.modelData.title
            color: clickTest.ink
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: String(clickTest.counts[chip.modelData.id])
            color: clickTest.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
            font.features: { "tnum": 1 }
          }
        }
      }
    }
  }
}
