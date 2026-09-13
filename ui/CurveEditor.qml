import QtQuick
import qs.Commons
import qs.Ui
import "../TactileModel.js" as Model

// A curve to draw: how fast you move (across) against what comes out (up). Drag a point up or down; a faster movement
// never comes out slower, so its neighbours follow. The dashed line is one-to-one.
Item {
  id: curveEditor

  property string text: ""
  property string what: "pointer"
  property color ink: Color.menu.text
  property color accent: Color.accent
  property color faint: Qt.rgba(curveEditor.ink.r, curveEditor.ink.g, curveEditor.ink.b, 0.62)
  property color hairline: Qt.rgba(curveEditor.ink.r, curveEditor.ink.g, curveEditor.ink.b, 0.12)

  // A curve as Hyprland takes it (without "custom"); `final` is false while a point is still moving.
  signal edited(string text, bool final)

  property var curve: Model.parseCurve(curveEditor.text, false) || Model.presetCurve("straight")
  property real yMax: 10
  property bool dragging: false
  property int hot: -1

  implicitHeight: presets.implicitHeight + Style.space(10) + plot.height + Style.space(8) + caption.implicitHeight

  function fit() {
    var top = 0
    var points = curveEditor.curve.points
    for (var i = 0; i < points.length; i++) top = Math.max(top, points[i])
    curveEditor.yMax = Math.max(8, Math.ceil(top * 1.25))
  }

  onTextChanged: {
    if (curveEditor.dragging) return
    curveEditor.curve = Model.parseCurve(curveEditor.text, false) || Model.presetCurve("straight")
    curveEditor.fit()
  }
  onCurveChanged: canvas.requestPaint()
  onYMaxChanged: canvas.requestPaint()
  onHotChanged: canvas.requestPaint()
  Component.onCompleted: curveEditor.fit()

  ButtonGroup {
    id: presets
    anchors { top: parent.top; left: parent.left }
    focusable: false
    spacing: Style.space(6)
    options: Model.CURVE_PRESETS.map(function (p) { return { value: p.id, label: p.title } })
    value: Model.presetOf(curveEditor.curve)
    foreground: curveEditor.ink
    background: "transparent"
    accent: curveEditor.accent
    fontSize: Style.font.bodySmall
    onChanged: function (id) {
      curveEditor.curve = Model.presetCurve(id)
      curveEditor.fit()
      curveEditor.edited(Model.curveText(curveEditor.curve, false), true)
    }
  }

  Item {
    id: plot
    anchors { top: presets.bottom; topMargin: Style.space(10); left: parent.left; right: parent.right }
    anchors.leftMargin: Style.space(8)
    anchors.rightMargin: Style.space(8)
    height: Style.space(160)

    readonly property int count: curveEditor.curve.points.length

    function px(i) { return plot.count > 1 ? i * (plot.width - 1) / (plot.count - 1) : 0 }
    function py(v) { return plot.height - 1 - Math.min(1, v / curveEditor.yMax) * (plot.height - 1) }

    Canvas {
      id: canvas
      anchors.fill: parent
      onWidthChanged: requestPaint()
      onHeightChanged: requestPaint()

      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var n = plot.count
        var points = curveEditor.curve.points
        ctx.lineWidth = 1
        ctx.strokeStyle = curveEditor.hairline
        for (var i = 0; i < n; i++) {
          ctx.beginPath()
          ctx.moveTo(Math.round(plot.px(i)) + 0.5, 0)
          ctx.lineTo(Math.round(plot.px(i)) + 0.5, height)
          ctx.stroke()
        }
        ctx.beginPath()
        ctx.moveTo(0, height - 0.5)
        ctx.lineTo(width, height - 0.5)
        ctx.stroke()

        ctx.setLineDash([3, 4])
        ctx.strokeStyle = curveEditor.faint
        ctx.beginPath()
        ctx.moveTo(plot.px(0), plot.py(0))
        ctx.lineTo(plot.px(n - 1), plot.py((n - 1) * curveEditor.curve.step))
        ctx.stroke()
        ctx.setLineDash([])

        ctx.fillStyle = Qt.rgba(curveEditor.accent.r, curveEditor.accent.g, curveEditor.accent.b, 0.12)
        ctx.beginPath()
        ctx.moveTo(plot.px(0), height)
        for (var j = 0; j < n; j++) ctx.lineTo(plot.px(j), plot.py(points[j]))
        ctx.lineTo(plot.px(n - 1), height)
        ctx.closePath()
        ctx.fill()

        ctx.strokeStyle = curveEditor.accent
        ctx.lineWidth = 2
        ctx.beginPath()
        for (var k = 0; k < n; k++) {
          if (k === 0) ctx.moveTo(plot.px(k), plot.py(points[k]))
          else ctx.lineTo(plot.px(k), plot.py(points[k]))
        }
        ctx.stroke()
      }
    }

    Repeater {
      model: plot.count

      delegate: Rectangle {
        id: handle
        required property int index
        readonly property real value: curveEditor.curve.points[handle.index] || 0

        width: Style.space(12)
        height: width
        radius: width / 2
        x: plot.px(handle.index) - width / 2
        y: plot.py(handle.value) - height / 2
        color: grab.pressed || grab.containsMouse ? curveEditor.accent : curveEditor.ink
        border.width: Math.max(2, Style.space(2))
        border.color: Qt.rgba(Color.menu.background.r, Color.menu.background.g, Color.menu.background.b, 1)

        MouseArea {
          id: grab
          anchors.fill: parent
          anchors.margins: -Style.space(8)
          hoverEnabled: true
          preventStealing: true
          cursorShape: Qt.SizeVerCursor
          onContainsMouseChanged: curveEditor.hot = containsMouse ? handle.index : (curveEditor.hot === handle.index ? -1 : curveEditor.hot)
          onPressed: curveEditor.dragging = true
          onPositionChanged: function (mouse) {
            if (!pressed) return
            var p = mapToItem(plot, mouse.x, mouse.y)
            var v = (plot.height - 1 - p.y) / (plot.height - 1) * curveEditor.yMax
            curveEditor.curve = Model.curveWithPoint(curveEditor.curve, handle.index, v)
            curveEditor.edited(Model.curveText(curveEditor.curve, false), false)
          }
          onReleased: {
            curveEditor.dragging = false
            curveEditor.fit()
            curveEditor.edited(Model.curveText(curveEditor.curve, false), true)
          }
        }
      }
    }

    Text {
      visible: curveEditor.hot >= 0
      anchors { top: parent.top; right: parent.right }
      text: curveEditor.hot < 0 ? "" : (curveEditor.hot * curveEditor.curve.step).toFixed(1) + " in → "
        + (curveEditor.curve.points[curveEditor.hot] || 0).toFixed(2) + " out"
      color: curveEditor.ink
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.features: { "tnum": 1 }
    }
  }

  Text {
    id: caption
    anchors { top: plot.bottom; topMargin: Style.space(8); left: parent.left; right: parent.right }
    wrapMode: Text.Wrap
    text: curveEditor.what === "scroll"
      ? "Across: how fast you swipe. Up: how far the page goes. Dashed: one-to-one."
      : "Across: how fast you move. Up: how fast the pointer goes. Dashed: one-to-one."
    color: curveEditor.faint
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }
}
