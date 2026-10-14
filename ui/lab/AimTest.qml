import QtQuick
import qs.Commons
import qs.Commons as Commons
import "../../TactileModel.js" as Model

// Aiming: targets appear one after another; how long each takes and how far the pointer wanders on the way tell you
// whether it is too slow or too fast.
Item {
  id: aimTest

  property string kind: ""
  property var values: ({})
  property color ink: Commons.Color.menu.text
  property color accent: Commons.Color.accent
  property color faint: Qt.rgba(aimTest.ink.r, aimTest.ink.g, aimTest.ink.b, 0.62)
  property color hairline: Qt.rgba(aimTest.ink.r, aimTest.ink.g, aimTest.ink.b, 0.12)

  readonly property real targetSize: Style.space(30)
  property var samples: []
  property int misses: 0
  property real targetX: -1
  property real targetY: -1
  property real shownAt: 0
  property real travelled: 0
  property real straight: 1
  property real pointerX: -1
  property real pointerY: -1
  readonly property var summary: Model.aimSummary(aimTest.samples)

  function place() {
    if (aimTest.width <= 0 || aimTest.height <= 0) return
    var margin = aimTest.targetSize + Style.space(24)
    var fromX = aimTest.pointerX < 0 ? aimTest.width / 2 : aimTest.pointerX
    var fromY = aimTest.pointerY < 0 ? aimTest.height / 2 : aimTest.pointerY
    var x = aimTest.width / 2
    var y = aimTest.height / 2
    for (var i = 0; i < 16; i++) {
      x = margin + Math.random() * Math.max(1, aimTest.width - margin * 2)
      y = margin + Math.random() * Math.max(1, aimTest.height - margin * 2)
      if (Math.sqrt((x - fromX) * (x - fromX) + (y - fromY) * (y - fromY)) > Math.min(aimTest.width, aimTest.height) * 0.4) break
    }
    aimTest.targetX = x
    aimTest.targetY = y
    aimTest.straight = Math.max(1, Math.sqrt((x - fromX) * (x - fromX) + (y - fromY) * (y - fromY)) - aimTest.targetSize / 2)
    aimTest.travelled = 0
    aimTest.shownAt = Date.now()
  }

  onWidthChanged: placeTimer.restart()
  onHeightChanged: placeTimer.restart()

  Timer {
    id: placeTimer
    interval: 120
    onTriggered: aimTest.place()
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.CrossCursor

    onPositionChanged: function (mouse) {
      if (aimTest.pointerX >= 0) {
        var dx = mouse.x - aimTest.pointerX
        var dy = mouse.y - aimTest.pointerY
        aimTest.travelled += Math.sqrt(dx * dx + dy * dy)
      }
      aimTest.pointerX = mouse.x
      aimTest.pointerY = mouse.y
    }

    onPressed: function (mouse) {
      var dx = mouse.x - aimTest.targetX
      var dy = mouse.y - aimTest.targetY
      if (Math.sqrt(dx * dx + dy * dy) > aimTest.targetSize / 2 + Style.space(4)) {
        aimTest.misses++
        return
      }
      aimTest.samples = aimTest.samples.concat([{ ms: Date.now() - aimTest.shownAt, travelled: aimTest.travelled, straight: aimTest.straight }]).slice(-20)
      aimTest.pointerX = mouse.x
      aimTest.pointerY = mouse.y
      aimTest.place()
    }
  }

  Column {
    anchors { left: parent.left; top: parent.top; margins: Style.space(18) }
    spacing: Style.space(2)

    Text {
      text: aimTest.summary.count === 0 ? "Click the target" : aimTest.summary.seconds.toFixed(2) + " s per target"
      color: aimTest.ink
      font.family: Style.font.family
      font.pixelSize: Style.font.heading
      font.bold: true
      font.features: { "tnum": 1 }
    }

    Text {
      text: aimTest.summary.count === 0 ? "Each target shows up away from the last one."
        : "path " + aimTest.summary.path.toFixed(1) + "× a straight line · " + aimTest.misses + " missed · last " + aimTest.summary.count
      color: aimTest.faint
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.features: { "tnum": 1 }
    }
  }

  Rectangle {
    visible: aimTest.targetX >= 0
    width: aimTest.targetSize * 1.9
    height: width
    radius: width / 2
    x: aimTest.targetX - width / 2
    y: aimTest.targetY - height / 2
    color: "transparent"
    border.width: 1
    border.color: aimTest.accent

    SequentialAnimation on opacity {
      loops: Animation.Infinite
      NumberAnimation { from: 0.6; to: 0.1; duration: 900; easing.type: Easing.InOutSine }
      NumberAnimation { from: 0.1; to: 0.6; duration: 900; easing.type: Easing.InOutSine }
    }
  }

  Rectangle {
    visible: aimTest.targetX >= 0
    width: aimTest.targetSize
    height: width
    radius: width / 2
    x: aimTest.targetX - width / 2
    y: aimTest.targetY - height / 2
    color: aimTest.accent
  }
}
