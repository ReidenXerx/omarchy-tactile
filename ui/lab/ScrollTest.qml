import QtQuick
import qs.Commons

// Scrolling: a long ruler to scroll, and how far the last swipe moved it, momentum included.
Item {
  id: scrollTest

  property string kind: ""
  property var values: ({})
  property color ink: Color.menu.text
  property color accent: Color.accent
  property color faint: Qt.rgba(scrollTest.ink.r, scrollTest.ink.g, scrollTest.ink.b, 0.62)
  property color hairline: Qt.rgba(scrollTest.ink.r, scrollTest.ink.g, scrollTest.ink.b, 0.12)

  readonly property int lengthPx: 8000
  readonly property int tickPx: 50
  property bool placed: false
  property bool moving: false
  property real settledY: 0
  property real startY: 0
  property int lastDistance: -1
  property int lastDirection: 0
  property int swipes: 0

  function recenter() {
    scrollTest.placed = false
    ruler.cancelFlick()
    ruler.contentY = Math.round((scrollTest.lengthPx - ruler.height) / 2)
    scrollTest.settledY = ruler.contentY
    scrollTest.placed = true
  }

  Flickable {
    id: ruler
    anchors.fill: parent
    contentHeight: scrollTest.lengthPx
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    onHeightChanged: if (!scrollTest.placed && height > 0) scrollTest.recenter()

    onContentYChanged: {
      if (!scrollTest.placed) return
      if (!scrollTest.moving) {
        scrollTest.moving = true
        scrollTest.startY = scrollTest.settledY
      }
      settle.restart()
    }

    Repeater {
      model: Math.floor(scrollTest.lengthPx / scrollTest.tickPx)

      delegate: Item {
        id: tick
        required property int index
        readonly property bool major: index % 5 === 0
        readonly property int offset: index * scrollTest.tickPx - scrollTest.lengthPx / 2

        y: index * scrollTest.tickPx
        width: ruler.width
        height: 1

        Rectangle {
          width: tick.major ? Style.space(40) : Style.space(18)
          height: 1
          color: tick.major ? scrollTest.faint : scrollTest.hairline
        }

        Text {
          visible: tick.major
          x: Style.space(48)
          anchors.verticalCenter: parent.verticalCenter
          text: (tick.offset > 0 ? "+" : tick.offset < 0 ? "−" : "") + Math.abs(tick.offset)
          color: scrollTest.faint
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.features: { "tnum": 1 }
        }
      }
    }
  }

  // A swipe ends once the ruler has been still for a moment.
  Timer {
    id: settle
    interval: 350
    onTriggered: {
      var moved = ruler.contentY - scrollTest.startY
      scrollTest.moving = false
      if (Math.abs(moved) >= 1) {
        scrollTest.lastDistance = Math.round(Math.abs(moved))
        scrollTest.lastDirection = moved > 0 ? 1 : -1
        scrollTest.swipes++
      }
      scrollTest.settledY = ruler.contentY
      if (ruler.contentY < 1200 || ruler.contentY > scrollTest.lengthPx - ruler.height - 1200) scrollTest.recenter()
    }
  }

  Column {
    anchors { right: parent.right; top: parent.top; margins: Style.space(18) }
    spacing: Style.space(2)

    Text {
      anchors.right: parent.right
      text: Math.max(0, scrollTest.lastDistance) + " px"
      color: scrollTest.moving ? scrollTest.accent : scrollTest.lastDistance < 0 ? scrollTest.faint : scrollTest.ink
      font.family: Style.font.family
      font.pixelSize: Style.font.displayLarge
      font.bold: true
      font.features: { "tnum": 1 }
    }

    Text {
      anchors.right: parent.right
      text: scrollTest.lastDistance < 0 ? "Scroll to measure a swipe"
        : (scrollTest.lastDirection > 0 ? "scrolled down" : "scrolled up") + " · swipe " + scrollTest.swipes
      color: scrollTest.faint
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }
}
