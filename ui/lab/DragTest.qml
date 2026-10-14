import QtQuick
import qs.Commons
import qs.Commons as Commons

// Dragging: carry the dot onto the ring without dropping it on the way.
Item {
  id: dragTest

  property string kind: ""
  property var values: ({})
  property color ink: Commons.Color.menu.text
  property color accent: Commons.Color.accent
  property color faint: Qt.rgba(dragTest.ink.r, dragTest.ink.g, dragTest.ink.b, 0.62)
  property color hairline: Qt.rgba(dragTest.ink.r, dragTest.ink.g, dragTest.ink.b, 0.12)

  property int hits: 0
  property string note: ""
  property real ringFraction: 0.5

  function home() {
    puck.x = Style.space(40)
    puck.y = Math.round(dragTest.height / 2 - puck.height / 2)
  }

  function drop() {
    var dx = puck.x + puck.width / 2 - (ring.x + ring.width / 2)
    var dy = puck.y + puck.height / 2 - (ring.y + ring.height / 2)
    var gap = Math.sqrt(dx * dx + dy * dy)
    if (gap <= ring.width / 2) {
      dragTest.hits++
      dragTest.note = "On target"
      dragTest.ringFraction = 0.25 + Math.random() * 0.5
    } else {
      dragTest.note = "Dropped " + Math.round(gap - ring.width / 2) + " px away"
    }
    homeTimer.restart()
  }

  onWidthChanged: if (!grab.drag.active) dragTest.home()
  onHeightChanged: if (!grab.drag.active) dragTest.home()

  Timer {
    id: homeTimer
    interval: 450
    onTriggered: if (!grab.drag.active) dragTest.home()
  }

  Column {
    anchors { left: parent.left; top: parent.top; margins: Style.space(18) }
    spacing: Style.space(2)

    Text {
      text: dragTest.note === "" ? "Drag the dot" : dragTest.note
      color: dragTest.note === "On target" ? dragTest.accent : dragTest.ink
      font.family: Style.font.family
      font.pixelSize: Style.font.heading
      font.bold: true
    }

    Text {
      text: dragTest.hits === 1 ? "1 on target" : dragTest.hits + " on target"
      color: dragTest.faint
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }

  Rectangle {
    id: ring
    width: Style.space(96)
    height: width
    radius: width / 2
    x: dragTest.width - width - Style.space(40)
    y: Math.round(dragTest.height * dragTest.ringFraction - height / 2)
    color: "transparent"
    border.width: Math.max(2, Style.space(2))
    border.color: grab.drag.active ? dragTest.accent : dragTest.faint

    Behavior on y { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
  }

  Rectangle {
    id: puck
    width: Style.space(46)
    height: width
    radius: width / 2
    color: grab.drag.active ? dragTest.accent : dragTest.ink

    Behavior on x {
      enabled: !grab.drag.active
      NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
    }
    Behavior on y {
      enabled: !grab.drag.active
      NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
    }

    MouseArea {
      id: grab
      anchors.fill: parent
      cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
      drag.target: puck
      drag.threshold: 0
      drag.minimumX: 0
      drag.maximumX: dragTest.width - puck.width
      drag.minimumY: 0
      drag.maximumY: dragTest.height - puck.height
      onPressed: homeTimer.stop()
      onReleased: dragTest.drop()
    }
  }
}
