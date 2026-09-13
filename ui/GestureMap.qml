import QtQuick
import qs.Commons
import "../TactileModel.js" as Model

// What each number of fingers does in each direction, as Tactile's gestures and the touchpad settings leave it:
// two-finger swipes scroll, finger drag takes its swipes, and a broad gesture fills what narrow ones leave free.
Item {
  id: gestureMap

  property var gestures: []
  property int dragSetting: 0
  property color ink: Color.menu.text
  property color accent: Color.accent
  property color faint: Qt.rgba(gestureMap.ink.r, gestureMap.ink.g, gestureMap.ink.b, 0.62)
  property color hairline: Qt.rgba(gestureMap.ink.r, gestureMap.ink.g, gestureMap.ink.b, 0.12)

  readonly property var columns: ["left", "right", "up", "down", "pinchin", "pinchout"]
  readonly property var rows: [2, 3, 4, 5]
  readonly property int dragFingers: gestureMap.dragSetting === 1 ? 3 : gestureMap.dragSetting === 2 ? 4 : 0
  readonly property real cellWidth: Math.floor((gestureMap.width - Style.space(40)) / gestureMap.columns.length)

  // The gesture Hyprland would run: the first added (narrow ones go first) that covers the direction.
  function cell(fingers, direction) {
    var pinch = direction.indexOf("pinch") === 0
    if (!pinch && fingers === 2) return { text: "Scroll", kind: "system" }
    if (!pinch && fingers === gestureMap.dragFingers) return { text: "Finger drag", kind: "system" }
    var ordered = Model.orderedGestures(gestureMap.gestures)
    for (var i = 0; i < ordered.length; i++) {
      var g = ordered[i]
      if (g.fingers === fingers && g.mods === "" && Model.directionOf(g.direction).covers.indexOf(direction) >= 0)
        return { text: Model.actionOf(g.action).title, kind: "gesture" }
    }
    return { text: "", kind: "free" }
  }

  Column {
    anchors.fill: parent
    spacing: Style.space(12)

    Text {
      text: "WHAT YOUR FINGERS DO"
      color: gestureMap.faint
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1.5
    }

    Row {
      Item { width: Style.space(40); height: 1 }

      Repeater {
        model: gestureMap.columns

        delegate: Text {
          required property var modelData
          width: gestureMap.cellWidth
          horizontalAlignment: Text.AlignHCenter
          text: Model.directionOf(modelData).arrow
          color: gestureMap.ink
          font.family: Style.font.family
          font.pixelSize: Style.font.heading
        }
      }
    }

    Repeater {
      model: gestureMap.rows

      delegate: Row {
        id: fingerRow
        required property var modelData

        Text {
          width: Style.space(40)
          height: Style.space(58)
          verticalAlignment: Text.AlignVCenter
          text: String(fingerRow.modelData)
          color: gestureMap.ink
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Repeater {
          model: gestureMap.columns

          delegate: Item {
            id: slot
            required property var modelData
            readonly property var info: gestureMap.cell(fingerRow.modelData, String(modelData))

            width: gestureMap.cellWidth
            height: Style.space(58)

            Rectangle {
              anchors.fill: parent
              anchors.margins: Style.space(3)
              radius: Style.cornerRadius
              color: slot.info.kind === "gesture" ? Qt.rgba(gestureMap.accent.r, gestureMap.accent.g, gestureMap.accent.b, 0.2) : "transparent"
              border.width: 1
              border.color: slot.info.kind === "gesture" ? gestureMap.accent : gestureMap.hairline

              Text {
                anchors.fill: parent
                anchors.margins: Style.space(4)
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: slot.info.text === "" ? "·" : slot.info.text
                color: slot.info.kind === "gesture" ? gestureMap.ink : gestureMap.faint
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.italic: slot.info.kind === "system"
              }
            }
          }
        }
      }
    }

    Text {
      width: parent.width
      wrapMode: Text.Wrap
      text: "Italic: what the touchpad does itself. Gestures written in your own Hyprland config are not shown here."
      color: gestureMap.faint
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }
}
