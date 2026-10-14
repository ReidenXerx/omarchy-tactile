import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../TactileModel.js" as Model

// The chosen device's settings, grouped. A change goes out as it is made: a slider sends its value while it moves, a
// few times a second, so the pointer and the page change under your fingers.
Item {
  id: settingsList

  property var service: null
  property var device: null
  property var values: ({})
  property color ink: Commons.Color.menu.text
  property color accent: Commons.Color.accent
  property color faint: Qt.rgba(settingsList.ink.r, settingsList.ink.g, settingsList.ink.b, 0.62)
  property color hairline: Qt.rgba(settingsList.ink.r, settingsList.ink.g, settingsList.ink.b, 0.12)

  signal edited(string field, var value)

  readonly property string kind: settingsList.device ? settingsList.device.kind : ""
  readonly property var groups: settingsList.kind !== "" ? Model.fieldsFor(settingsList.kind) : []
  readonly property int kept: settingsList.service && settingsList.device ? settingsList.service.keptCount(settingsList.device.name) : 0

  function formatNumber(field, v) {
    var n = Number(v)
    if (!isFinite(n)) return ""
    if (field === "sensitivity") return (n > 0 ? "+" : "") + n.toFixed(2)
    if (field === "scroll_factor") return n.toFixed(2) + "×"
    return String(n)
  }

  function snap(spec, v) {
    var step = spec && spec.step ? spec.step : 0.05
    return Math.round(Number(v) / step) * step
  }

  Item {
    id: summary
    anchors { top: parent.top; left: parent.left; right: parent.right }
    height: Math.max(summaryText.implicitHeight, resetButton.visible ? resetButton.implicitHeight : 0)

    Text {
      id: summaryText
      anchors {
        left: parent.left; right: resetButton.visible ? resetButton.left : parent.right; rightMargin: Style.space(8)
        verticalCenter: parent.verticalCenter
      }
      wrapMode: Text.Wrap
      text: settingsList.kept === 0 ? "Following your Hyprland input settings."
        : (settingsList.kept === 1 ? "1 setting" : settingsList.kept + " settings") + " kept by Tactile, each marked with a dot."
      color: settingsList.faint
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    Button {
      id: resetButton
      anchors { right: parent.right; verticalCenter: parent.verticalCenter }
      visible: settingsList.kept > 0
      text: "Back to your config"
      bordered: true
      fontSize: Style.font.bodySmall
      foreground: settingsList.ink
      accent: settingsList.accent
      tooltipText: "Try this device with your Hyprland input settings again"
      onClicked: if (settingsList.service && settingsList.device) settingsList.service.resetDevice(settingsList.device.name)
    }
  }

  Flickable {
    id: scroller
    anchors { top: summary.bottom; topMargin: Style.space(12); left: parent.left; right: parent.right; bottom: parent.bottom }
    contentHeight: sections.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: sections
      width: scroller.width - Style.space(12)
      spacing: Style.space(20)

      Repeater {
        model: settingsList.groups

        delegate: Column {
          id: section
          required property var modelData
          width: sections.width
          spacing: Style.space(12)

          Text {
            text: String(section.modelData.title).toUpperCase()
            color: settingsList.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.5
          }

          Repeater {
            model: section.modelData.fields

            delegate: Column {
              id: row
              required property var modelData
              readonly property string field: String(row.modelData)
              readonly property var spec: Model.FIELDS[row.field]
              readonly property var value: settingsList.values[row.field]
              readonly property bool kept: settingsList.service && settingsList.device
                ? settingsList.service.isKept(settingsList.device.name, row.field) : false
              // Libinput ignores the pointer speed while a custom curve is on.
              readonly property bool idle: row.field === "sensitivity" && Model.isCustomProfile(settingsList.values.accel_profile)

              width: section.width
              spacing: Style.space(6)
              enabled: !row.idle
              opacity: row.idle ? 0.45 : 1

              Item {
                width: parent.width
                height: Math.max(labelBlock.implicitHeight, toggle.visible ? toggle.implicitHeight : 0)

                Column {
                  id: labelBlock
                  anchors {
                    left: parent.left; verticalCenter: parent.verticalCenter; rightMargin: Style.space(12)
                    right: toggle.visible ? toggle.left : (readout.visible ? readout.left : parent.right)
                  }
                  spacing: Style.space(2)

                  Row {
                    spacing: Style.space(6)

                    Rectangle {
                      visible: row.kept
                      anchors.verticalCenter: parent.verticalCenter
                      width: Style.space(6)
                      height: width
                      radius: width / 2
                      color: settingsList.accent
                    }

                    Text {
                      text: row.spec.label
                      color: settingsList.ink
                      font.family: Style.font.family
                      font.pixelSize: Style.font.body
                    }
                  }

                  Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: row.idle ? "The custom curve below sets the speed, so this does nothing while it is on." : row.spec.tip
                    color: settingsList.faint
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }
                }

                ToggleSwitch {
                  id: toggle
                  visible: row.spec.type === "bool"
                  anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                  checked: row.value === true
                  foreground: settingsList.ink
                  accent: settingsList.accent
                  onToggled: settingsList.edited(row.field, row.value !== true)
                }

                Text {
                  id: readout
                  visible: row.spec.type === "number"
                  anchors { right: parent.right; top: parent.top }
                  text: row.spec.type === "number" ? settingsList.formatNumber(row.field, slider.dragging ? slider.liveValue : row.value) : ""
                  color: settingsList.ink
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                  font.features: { "tnum": 1 }
                }
              }

              PanelSlider {
                id: slider
                visible: row.spec.type === "number"
                width: parent.width
                minimum: row.spec.min !== undefined ? row.spec.min : 0
                maximum: row.spec.max !== undefined ? row.spec.max : 1
                step: row.spec.step || 0.05
                value: typeof row.value === "number" ? row.value : 0
                tickCount: row.field === "sensitivity" ? 3 : 0
                tickColor: Qt.rgba(Commons.Color.menu.background.r, Commons.Color.menu.background.g, Commons.Color.menu.background.b, 1)
                trackColor: settingsList.hairline
                fillColor: settingsList.accent
                knobColor: settingsList.ink
                onMoved: function (v) {
                  throttle.pending = settingsList.snap(row.spec, v)
                  if (!throttle.running) throttle.start()
                }
                onReleased: function (v) {
                  throttle.stop()
                  settingsList.edited(row.field, settingsList.snap(row.spec, v))
                }
              }

              Timer {
                id: throttle
                property var pending: null
                interval: 140
                onTriggered: if (pending !== null) settingsList.edited(row.field, pending)
              }

              ButtonGroup {
                visible: row.spec.type === "enum" || row.spec.type === "profile"
                focusable: false
                spacing: Style.space(6)
                options: visible
                  ? row.spec.choices.map(function (c) { return { value: String(c), label: Model.choiceLabel(row.field, c) } }) : []
                value: row.value === undefined ? "" : Model.isCustomProfile(row.value) ? "custom" : String(row.value)
                foreground: settingsList.ink
                background: "transparent"
                accent: settingsList.accent
                fontSize: Style.font.bodySmall
                onChanged: function (v) {
                  if (v !== "custom") settingsList.edited(row.field, v)
                  else if (!Model.isCustomProfile(row.value))
                    settingsList.edited(row.field, "custom " + Model.curveText(Model.presetCurve("gentle"), false))
                }
              }

              // The pointer curve once Acceleration is custom, and the scroll curve that goes with it.
              Loader {
                width: parent.width
                active: (row.spec.type === "profile" && Model.isCustomProfile(row.value))
                  || (row.spec.type === "curve" && Model.isCustomProfile(settingsList.values.accel_profile))
                visible: active
                sourceComponent: Component {
                  CurveEditor {
                    text: row.spec.type === "profile" ? String(row.value).slice("custom ".length) : String(row.value || "")
                    what: row.spec.type === "curve" ? "scroll" : "pointer"
                    ink: settingsList.ink
                    accent: settingsList.accent
                    faint: settingsList.faint
                    hairline: settingsList.hairline
                    onEdited: function (text, final) {
                      var value = row.spec.type === "profile" ? "custom " + text : text
                      if (final) {
                        curveThrottle.stop()
                        settingsList.edited(row.field, value)
                      } else {
                        curveThrottle.pending = value
                        if (!curveThrottle.running) curveThrottle.start()
                      }
                    }
                  }
                }
              }

              Timer {
                id: curveThrottle
                property var pending: null
                interval: 160
                onTriggered: if (pending !== null) settingsList.edited(row.field, pending)
              }

              Text {
                visible: row.spec.type === "curve" && !Model.isCustomProfile(settingsList.values.accel_profile)
                width: parent.width
                wrapMode: Text.Wrap
                text: "Pick Custom under Acceleration to draw a scroll curve too."
                color: settingsList.faint
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.italic: true
              }
            }
          }
        }
      }

      AutoSection {
        width: sections.width
        service: settingsList.service
        device: settingsList.device
        ink: settingsList.ink
        accent: settingsList.accent
        faint: settingsList.faint
        hairline: settingsList.hairline
      }
    }
  }
}
