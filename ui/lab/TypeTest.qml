import QtQuick
import qs.Commons
import qs.Commons as Commons

// Typing: does the pointer move when a palm brushes the pad mid-sentence?
Item {
  id: typeTest

  property string kind: ""
  property var values: ({})
  property color ink: Commons.Color.menu.text
  property color accent: Commons.Color.accent
  property color faint: Qt.rgba(typeTest.ink.r, typeTest.ink.g, typeTest.ink.b, 0.62)
  property color hairline: Qt.rgba(typeTest.ink.r, typeTest.ink.g, typeTest.ink.b, 0.12)

  property real lastKeyAt: 0
  property real lastNudgeAt: 0
  property int nudges: 0
  property int keys: 0
  property real lastX: -1
  property real lastY: -1

  // Pointer moves within a moment of a key press, counted once per brush rather than once per event.
  HoverHandler {
    id: hover
    onPointChanged: {
      var p = hover.point.position
      var now = Date.now()
      if (typeTest.lastX >= 0 && now - typeTest.lastKeyAt < 700
          && Math.abs(p.x - typeTest.lastX) + Math.abs(p.y - typeTest.lastY) >= 2 && now - typeTest.lastNudgeAt > 400) {
        typeTest.nudges++
        typeTest.lastNudgeAt = now
      }
      typeTest.lastX = p.x
      typeTest.lastY = p.y
    }
  }

  Column {
    id: readout
    anchors { left: parent.left; top: parent.top; margins: Style.space(18) }
    spacing: Style.space(2)

    Text {
      text: typeTest.keys === 0 ? "Start typing"
        : typeTest.nudges === 0 ? "The pointer stayed still"
        : "The pointer moved " + (typeTest.nudges === 1 ? "once" : typeTest.nudges + " times") + " while you typed"
      color: typeTest.nudges > 0 ? typeTest.accent : typeTest.ink
      font.family: Style.font.family
      font.pixelSize: Style.font.heading
      font.bold: true
    }

    Text {
      text: "Keep the pointer over this area while you type."
      color: typeTest.faint
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }

  Rectangle {
    id: box
    anchors { left: parent.left; right: parent.right; top: readout.bottom; margins: Style.space(18) }
    height: Style.space(150)
    radius: Style.cornerRadius
    color: "transparent"
    border.width: 1
    border.color: editor.activeFocus ? typeTest.accent : typeTest.hairline

    TextEdit {
      id: editor
      anchors.fill: parent
      anchors.margins: Style.space(12)
      wrapMode: TextEdit.Wrap
      color: typeTest.ink
      selectionColor: Qt.rgba(typeTest.accent.r, typeTest.accent.g, typeTest.accent.b, 0.4)
      selectedTextColor: typeTest.ink
      font.family: Style.font.family
      font.pixelSize: Style.font.subtitle
      clip: true

      Keys.onPressed: function (event) {
        typeTest.lastKeyAt = Date.now()
        typeTest.keys++
      }

      Text {
        visible: editor.text === "" && !editor.activeFocus
        text: "Click here and type…"
        color: typeTest.faint
        font: editor.font
      }
    }
  }

  Text {
    anchors { right: parent.right; top: box.bottom; margins: Style.space(18) }
    text: "Start over"
    color: startOver.containsMouse ? typeTest.accent : typeTest.faint
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.underline: true

    MouseArea {
      id: startOver
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        typeTest.nudges = 0
        typeTest.keys = 0
        editor.text = ""
      }
    }
  }
}
