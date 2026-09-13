import QtQuick
import qs.Commons
import qs.Ui
import "../TactileModel.js" as Model

// Tactile's gestures and scroll speed per app. Every change goes on trial like a device setting.
Item {
  id: gesturesPage

  property var service: null
  property color ink: Color.menu.text
  property color accent: Color.accent
  property color faint: Qt.rgba(gesturesPage.ink.r, gesturesPage.ink.g, gesturesPage.ink.b, 0.62)
  property color hairline: Qt.rgba(gesturesPage.ink.r, gesturesPage.ink.g, gesturesPage.ink.b, 0.12)

  readonly property var gestures: gesturesPage.service ? gesturesPage.service.listOf("gestures") : []
  readonly property var apps: gesturesPage.service ? gesturesPage.service.listOf("apps") : []
  readonly property var notes: Model.gestureNotes(gesturesPage.gestures, gesturesPage.service ? gesturesPage.service.dragSetting() : 0)

  property int fingers: 3
  property string direction: "horizontal"
  property string action: "workspace"
  readonly property bool pinch: gesturesPage.direction.indexOf("pinch") === 0
  readonly property var actions: Model.GESTURE_ACTIONS.filter(function (a) { return a.directions.indexOf(gesturesPage.direction) >= 0 })
  readonly property bool taken: gesturesPage.gestures.some(function (g) {
    return g.fingers === gesturesPage.fingers && g.mods === "" && g.direction === gesturesPage.direction
  })

  onDirectionChanged: {
    if (!gesturesPage.actions.some(function (a) { return a.id === gesturesPage.action }))
      gesturesPage.action = gesturesPage.actions.length > 0 ? gesturesPage.actions[0].id : ""
    if (!gesturesPage.pinch && gesturesPage.fingers < 3) gesturesPage.fingers = 3
  }

  function setList(list, items) {
    if (gesturesPage.service) gesturesPage.service.setList(list, items)
  }

  function addGesture() {
    gesturesPage.setList("gestures", gesturesPage.gestures.concat([{
      fingers: gesturesPage.fingers, direction: gesturesPage.direction, action: gesturesPage.action, mods: ""
    }]))
  }

  function removeGesture(index) {
    var next = Array.prototype.slice.call(gesturesPage.gestures)
    next.splice(index, 1)
    gesturesPage.setList("gestures", next)
  }

  function setApp(app, touchpad) {
    var next = gesturesPage.apps.map(function (e) { return { app: e.app, touchpad: e.touchpad, mouse: e.mouse } })
    var found = next.filter(function (e) { return e.app === app })[0]
    if (found) found.touchpad = touchpad
    else next.push({ app: app, touchpad: touchpad, mouse: null })
    gesturesPage.setList("apps", next)
  }

  function removeApp(app) {
    gesturesPage.setList("apps", gesturesPage.apps.filter(function (e) { return e.app !== app }))
  }

  component SectionTitle: Text {
    color: gesturesPage.faint
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1.5
  }

  component Caption: Text {
    wrapMode: Text.Wrap
    color: gesturesPage.faint
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  component Chip: Button {
    bordered: true
    foreground: gesturesPage.ink
    accent: gesturesPage.accent
    fontSize: Style.font.bodySmall
  }

  Flickable {
    id: scroller
    anchors.fill: parent
    contentHeight: column.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: column
      width: scroller.width - Style.space(12)
      spacing: Style.space(12)

      SectionTitle { text: "YOUR GESTURES" }

      Caption {
        width: parent.width
        text: gesturesPage.gestures.length === 0
          ? "None from Tactile yet. Gestures added here work everywhere, on top of your Hyprland config."
          : "Added by Tactile, on top of your Hyprland config."
      }

      Repeater {
        model: gesturesPage.gestures.length

        delegate: Column {
          id: gestureRow
          required property int index
          readonly property var gesture: gesturesPage.gestures[index]
          readonly property var dir: gestureRow.gesture ? Model.directionOf(gestureRow.gesture.direction) : null
          readonly property var act: gestureRow.gesture ? Model.actionOf(gestureRow.gesture.action) : null
          readonly property var rowNotes: gestureRow.gesture ? gesturesPage.notes.filter(function (n) {
            return n.key === Model.gestureKey(gestureRow.gesture)
          }) : []

          width: column.width
          spacing: Style.space(4)

          Item {
            width: parent.width
            height: Math.max(gestureText.implicitHeight, removeButton.implicitHeight)

            Rectangle {
              id: fingerBadge
              anchors { left: parent.left; verticalCenter: parent.verticalCenter }
              width: Style.space(26)
              height: width
              radius: width / 2
              color: Qt.rgba(gesturesPage.accent.r, gesturesPage.accent.g, gesturesPage.accent.b, 0.2)
              border.width: 1
              border.color: gesturesPage.accent

              Text {
                anchors.centerIn: parent
                text: gestureRow.gesture ? String(gestureRow.gesture.fingers) : ""
                color: gesturesPage.ink
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
              }
            }

            Text {
              id: gestureText
              anchors {
                left: fingerBadge.right; leftMargin: Style.space(10); right: removeButton.left; rightMargin: Style.space(8)
                verticalCenter: parent.verticalCenter
              }
              elide: Text.ElideRight
              textFormat: Text.PlainText
              text: gestureRow.dir && gestureRow.act
                ? gestureRow.dir.arrow + "  " + gestureRow.dir.title + "  →  " + gestureRow.act.title : ""
              color: gesturesPage.ink
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }

            Chip {
              id: removeButton
              anchors { right: parent.right; verticalCenter: parent.verticalCenter }
              text: "Remove"
              onClicked: gesturesPage.removeGesture(gestureRow.index)
            }
          }

          Repeater {
            model: gestureRow.rowNotes

            delegate: Caption {
              required property var modelData
              x: Style.space(36)
              width: gestureRow.width - x
              text: String(modelData.text)
              color: gesturesPage.accent
            }
          }
        }
      }

      Rectangle { width: parent.width; height: 1; color: gesturesPage.hairline }

      SectionTitle { text: "ADD A GESTURE" }

      Caption { text: "Fingers" }

      Row {
        spacing: Style.space(6)

        Repeater {
          model: [2, 3, 4, 5]

          delegate: Chip {
            required property var modelData
            visible: modelData >= 3 || gesturesPage.pinch
            text: String(modelData)
            selected: gesturesPage.fingers === modelData
            onClicked: gesturesPage.fingers = modelData
          }
        }
      }

      Caption { text: "Movement" }

      Flow {
        width: parent.width
        spacing: Style.space(6)

        Repeater {
          model: Model.GESTURE_DIRECTIONS

          delegate: Chip {
            required property var modelData
            text: modelData.arrow + " " + modelData.title
            selected: gesturesPage.direction === modelData.id
            onClicked: gesturesPage.direction = modelData.id
          }
        }
      }

      Caption { text: "Does" }

      Flow {
        width: parent.width
        spacing: Style.space(6)

        Repeater {
          model: gesturesPage.actions

          delegate: Chip {
            required property var modelData
            text: modelData.title
            selected: gesturesPage.action === modelData.id
            onClicked: gesturesPage.action = modelData.id
          }
        }
      }

      Row {
        spacing: Style.space(10)

        Chip {
          text: "Add gesture"
          selected: true
          enabled: !gesturesPage.taken && gesturesPage.action !== ""
          opacity: enabled ? 1 : 0.5
          onClicked: gesturesPage.addGesture()
        }

        Caption {
          anchors.verticalCenter: parent.verticalCenter
          visible: gesturesPage.taken
          text: "You already have a gesture for that movement."
        }
      }

      Rectangle { width: parent.width; height: 1; color: gesturesPage.hairline }

      SectionTitle { text: "SCROLL SPEED PER APP" }

      Caption {
        width: parent.width
        text: "For apps that scroll too fast or too slow: the speed set here replaces the touchpad scroll speed in that app."
      }

      Repeater {
        model: gesturesPage.apps.length

        delegate: Item {
          id: appRow
          required property int index
          readonly property var entry: gesturesPage.apps[index]

          width: column.width
          height: Math.max(appRemove.implicitHeight, appSlider.implicitHeight)

          Text {
            id: appName
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            width: Math.round(parent.width * 0.3)
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: appRow.entry ? appRow.entry.app : ""
            color: gesturesPage.ink
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          PanelSlider {
            id: appSlider
            anchors {
              left: appName.right; leftMargin: Style.space(10); right: appReadout.left; rightMargin: Style.space(10)
              verticalCenter: parent.verticalCenter
            }
            minimum: 0.1
            maximum: 3
            step: 0.05
            value: appRow.entry && appRow.entry.touchpad !== null ? appRow.entry.touchpad : 1
            trackColor: gesturesPage.hairline
            fillColor: gesturesPage.accent
            knobColor: gesturesPage.ink
            onReleased: function (v) { if (appRow.entry) gesturesPage.setApp(appRow.entry.app, Math.round(v * 20) / 20) }
          }

          Text {
            id: appReadout
            anchors { right: appRemove.left; rightMargin: Style.space(10); verticalCenter: parent.verticalCenter }
            text: (appSlider.dragging ? appSlider.liveValue : appSlider.value).toFixed(2) + "×"
            color: gesturesPage.ink
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
            font.features: { "tnum": 1 }
          }

          Chip {
            id: appRemove
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            text: "Remove"
            onClicked: if (appRow.entry) gesturesPage.removeApp(appRow.entry.app)
          }
        }
      }

      Caption {
        width: parent.width
        readonly property int remaining: gesturesPage.service ? gesturesPage.service.openApps.filter(function (a) {
          return !gesturesPage.apps.some(function (e) { return e.app === a })
        }).length : 0
        text: remaining > 0 ? "Add an app that has a window open:" : "Open an app to set its scroll speed here."
      }

      Flow {
        width: parent.width
        spacing: Style.space(6)

        Repeater {
          model: gesturesPage.service ? gesturesPage.service.openApps.filter(function (a) {
            return !gesturesPage.apps.some(function (e) { return e.app === a })
          }) : []

          delegate: Chip {
            required property var modelData
            text: String(modelData)
            onClicked: gesturesPage.setApp(String(modelData), 1)
          }
        }
      }
    }
  }
}
