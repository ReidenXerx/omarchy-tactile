import QtQuick
import qs.Commons
import qs.Ui
import "../TactileModel.js" as Model

// The feel lab: a test for each kind of setting, with what to try worded for the settings the device has right now.
Item {
  id: feelLab

  property string kind: ""
  property var values: ({})
  property string test: "scroll"
  property var service: null
  property color ink: Color.menu.text
  property color accent: Color.accent
  property color faint: Qt.rgba(feelLab.ink.r, feelLab.ink.g, feelLab.ink.b, 0.62)
  property color hairline: Qt.rgba(feelLab.ink.r, feelLab.ink.g, feelLab.ink.b, 0.12)
  property color wash: Qt.rgba(feelLab.ink.r, feelLab.ink.g, feelLab.ink.b, 0.04)

  signal picked(string id)

  readonly property var tests: Model.LAB_TESTS
  readonly property string current: {
    for (var i = 0; i < feelLab.tests.length; i++) if (feelLab.tests[i].id === feelLab.test) return feelLab.test
    return feelLab.tests[0].id
  }
  readonly property var hints: feelLab.hintsFor(feelLab.current, feelLab.kind, feelLab.values)

  function hintsFor(id, kind, values) {
    if (id === "scroll") return Model.scrollHints(kind, values)
    if (id === "click") return Model.clickHints(kind, values)
    if (id === "drag") return Model.dragHints(kind, values)
    if (id === "aim") return ["Click each target as it appears. Slow to reach means a slow pointer; a long path means it overshoots."]
    if (id === "pinch") return kind === "touchpad" ? ["Pinch with two fingers to zoom the card, and twist to turn it. Double-click puts it back."]
                                                   : ["Pinching needs a touchpad."]
    if (id === "fingers") return ["Rest your fingers on the pad to see where each one lands, how many it counts, and when it clicks."]
    return ["Type in the box and let your palm brush the pad: with the pad ignored while typing, the pointer stays still."]
  }

  ButtonGroup {
    id: tabs
    anchors { top: parent.top; left: parent.left }
    focusable: false
    spacing: Style.space(4)
    options: feelLab.tests.map(function (t) { return { value: t.id, label: t.title } })
    value: feelLab.current
    foreground: feelLab.ink
    background: "transparent"
    accent: feelLab.accent
    fontSize: Style.font.bodySmall
    onChanged: function (v) { feelLab.picked(v) }
  }

  Column {
    id: hintColumn
    anchors { top: tabs.bottom; topMargin: Style.space(10); left: parent.left; right: parent.right }
    spacing: Style.space(2)

    Repeater {
      model: feelLab.hints

      delegate: Text {
        required property var modelData
        width: hintColumn.width
        wrapMode: Text.Wrap
        text: String(modelData)
        color: feelLab.faint
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
    }
  }

  Rectangle {
    id: stage
    anchors { top: hintColumn.bottom; topMargin: Style.space(12); left: parent.left; right: parent.right; bottom: parent.bottom }
    radius: Style.cornerRadius
    color: feelLab.wash
    border.width: 1
    border.color: feelLab.hairline
    clip: true

    Loader {
      id: stageLoader
      anchors.fill: parent
      anchors.margins: 1
      source: Qt.resolvedUrl("lab/" + feelLab.current.charAt(0).toUpperCase() + feelLab.current.slice(1) + "Test.qml")
    }

    Binding { target: stageLoader.item; property: "kind"; value: feelLab.kind; when: stageLoader.item !== null }
    Binding { target: stageLoader.item; property: "service"; value: feelLab.service; when: stageLoader.item !== null && stageLoader.item.hasOwnProperty("service") }
    Binding { target: stageLoader.item; property: "values"; value: feelLab.values; when: stageLoader.item !== null }
    Binding { target: stageLoader.item; property: "ink"; value: feelLab.ink; when: stageLoader.item !== null }
    Binding { target: stageLoader.item; property: "accent"; value: feelLab.accent; when: stageLoader.item !== null }
    Binding { target: stageLoader.item; property: "faint"; value: feelLab.faint; when: stageLoader.item !== null }
    Binding { target: stageLoader.item; property: "hairline"; value: feelLab.hairline; when: stageLoader.item !== null }
  }
}
