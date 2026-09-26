import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Ui
import qs.Commons
import "LayoutModel.js" as LayoutModel

// ARRANGEMENT section: a live, scaled preview of the
// connected displays. Drag a tile to change the left-to-right order, or drive
// it from the keyboard through moveCursor()/activate(). The order is saved to
// ~/.config/omarchy/monitor-layout.json and applied right away; Service.qml
// keeps it applied across hotplug and config reloads.
//
// Self-contained so any panel can embed it, e.g. a Display panel:
//
//   Arrangement {
//     bar: root.bar
//     active: root.opened
//     focused: root.focusSection === "arrangement"
//     cursorActive: root.cursorActive
//     onFocusRequested: { root.cursorActive = true; root.focusSection = "arrangement" }
//   }
Column {
  id: root

  required property QtObject bar
  // Refresh on display events only while the host panel is open.
  property bool active: false
  // The host's keyboard cursor is on this section / visible at all.
  property bool focused: false
  property bool cursorActive: false

  readonly property string orderPath: Quickshell.env("HOME") + "/.config/omarchy/monitor-layout.json"

  // [{ name, key, label, internal, focused, x, w, h }], left to right.
  property var tiles: []
  readonly property bool available: tiles.length > 1

  // Keyboard cursor over the tiles, and the tile picked up with Enter (-1 = none).
  property int selectedIndex: 0
  property int grabbedIndex: -1

  // Hover asks the host panel to move its keyboard focus here.
  signal focusRequested()

  function refresh() {
    if (!monitorsProc.running) monitorsProc.running = true
  }

  // h/l: move the cursor, or the picked-up tile.
  function moveCursor(dx) {
    if (!available) return
    var to = Math.max(0, Math.min(tiles.length - 1, selectedIndex + dx))
    if (grabbedIndex >= 0) {
      if (to === grabbedIndex) return
      moveTile(grabbedIndex, to)
      grabbedIndex = to
    }
    selectedIndex = to
  }

  // Enter: pick up / drop the tile under the cursor.
  function activate() {
    if (!available) return
    grabbedIndex = grabbedIndex >= 0 ? -1 : selectedIndex
  }

  // Move a tile, show the result immediately, then persist and apply it.
  function moveTile(from, to) {
    if (from === to || from < 0 || to < 0 || from >= tiles.length || to >= tiles.length) return
    tiles = LayoutModel.moveItem(tiles, from, to)
    orderFile.save(tiles.map(function(tile) { return tile.key }))
  }

  spacing: Style.space(10)

  onActiveChanged: {
    grabbedIndex = -1
    if (active) {
      selectedIndex = 0
      refresh()
    }
  }
  onFocusedChanged: if (!focused) grabbedIndex = -1
  onTilesChanged: {
    if (selectedIndex > tiles.length - 1) selectedIndex = Math.max(0, tiles.length - 1)
    if (grabbedIndex > tiles.length - 1) grabbedIndex = -1
  }

  Component.onCompleted: refresh()

  Process {
    id: monitorsProc
    command: ["hyprctl", "monitors", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var monitors = []
        try { monitors = JSON.parse(String(text || "[]")) } catch (e) { monitors = [] }
        root.tiles = LayoutModel.tilesFromMonitors(monitors)
      }
    }
  }

  // Saved order. Kept in memory so remembered-but-unplugged monitors survive
  // a save made while they are away.
  FileView {
    id: orderFile
    path: root.orderPath
    atomicWrites: true
    printErrors: false

    property var order: []

    onLoaded: order = LayoutModel.parseOrder(text())
    onLoadFailed: order = []

    function save(keys) {
      order = LayoutModel.mergeOrder(keys, order)
      setText(LayoutModel.serializeOrder(order))
      applier.apply()
    }
  }

  LayoutApplier {
    id: applier
    orderPath: root.orderPath
    onApplied: root.refresh()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!root.active || !event || !event.name) return
      var name = String(event.name)
      if (name.indexOf("monitor") === 0 || name === "configreloaded" || name === "focusedmon")
        refreshDebounce.restart()
    }
  }

  Timer {
    id: refreshDebounce
    interval: 350
    repeat: false
    onTriggered: root.refresh()
  }

  Item {
    width: parent.width
    implicitHeight: Math.max(header.implicitHeight, hint.implicitHeight)

    PanelSectionHeader {
      id: header
      text: "ARRANGEMENT"
      foreground: root.bar.foreground
      fontFamily: root.bar.fontFamily
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: hint
      textFormat: Text.PlainText
      text: root.grabbedIndex >= 0 ? "H/L TO MOVE · ENTER TO DROP" : "DRAG TO REORDER"
      color: Qt.darker(root.bar.foreground, 1.4)
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      anchors.right: parent.right
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  CursorSurface {
    id: row
    width: parent.width
    height: Style.space(110)
    hasCursor: root.cursorActive && root.focused
    foreground: root.bar.foreground
    outline: true

    Item {
      id: canvas
      anchors.fill: parent
      anchors.margins: Style.space(10)

      readonly property var tiles: root.tiles
      readonly property real gap: Style.space(6)
      readonly property real totalW: {
        var sum = 0
        for (var i = 0; i < tiles.length; i++) sum += tiles[i].w
        return sum
      }
      readonly property real totalH: {
        var max = 0
        for (var i = 0; i < tiles.length; i++) max = Math.max(max, tiles[i].h)
        return max
      }
      // Preview pixels per logical monitor pixel, fitting all tiles in one row.
      readonly property real unit: totalW > 0 && totalH > 0
        ? Math.min((width - gap * (tiles.length - 1)) / totalW, height / totalH)
        : 0
      readonly property real groupLeft: (width - (totalW * unit + gap * (tiles.length - 1))) / 2
      readonly property real groupTop: (height - totalH * unit) / 2

      // Tile being dragged (-1 = none) and by how much. Cleared on release,
      // so tiles always rest where the live layout puts them.
      property int dragIndex: -1
      property real dragOffset: 0

      function restX(index) {
        var x = groupLeft
        for (var i = 0; i < index && i < tiles.length; i++) x += tiles[i].w * unit + gap
        return x
      }

      function clampOffset(tileWidth, base, offset) {
        return Math.max(-base, Math.min(width - tileWidth - base, offset))
      }

      function finishDrag() {
        var from = dragIndex
        var offset = dragOffset
        dragIndex = -1
        dragOffset = 0
        if (from < 0) return
        var rest = []
        for (var i = 0; i < tiles.length; i++)
          rest.push({ left: restX(i), width: tiles[i].w * unit })
        root.moveTile(from, LayoutModel.dropIndex(rest, from, offset))
      }

      Repeater {
        model: canvas.tiles

        ScreenTile {
          id: screenTile
          required property var modelData
          required property int index

          readonly property real restX: canvas.restX(index)
          readonly property bool dragged: canvas.dragIndex === index

          x: restX + (dragged ? canvas.dragOffset : 0)
          y: canvas.groupTop
          z: dragged ? 2 : 0
          width: modelData.w * canvas.unit
          height: modelData.h * canvas.unit
          icon: modelData.internal ? "󰌢" : "󰍹"
          label: modelData.label
          highlighted: modelData.focused
          grabbed: dragged || root.grabbedIndex === index
          hasCursor: root.cursorActive && root.focused && root.selectedIndex === index

          MouseArea {
            anchors.fill: parent
            // The panel scrolls inside a Flickable; without this it can steal
            // the gesture and swallow the release.
            preventStealing: true
            hoverEnabled: true
            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor

            property real pressX: 0

            onContainsMouseChanged: if (containsMouse && !pressed) {
              root.selectedIndex = screenTile.index
              root.focusRequested()
            }
            onPressed: function(mouse) {
              pressX = mapToItem(canvas, mouse.x, 0).x
              root.grabbedIndex = -1
              canvas.dragOffset = 0
              canvas.dragIndex = screenTile.index
            }
            onPositionChanged: function(mouse) {
              if (!pressed) return
              canvas.dragOffset = canvas.clampOffset(screenTile.width, screenTile.restX,
                mapToItem(canvas, mouse.x, 0).x - pressX)
            }
            onReleased: canvas.finishDrag()
            onCanceled: {
              canvas.dragIndex = -1
              canvas.dragOffset = 0
            }
          }
        }
      }
    }
  }

  // One display in the preview. highlighted = focused display (accent border);
  // grabbed = being dragged or picked up with Enter (filled); hasCursor =
  // keyboard cursor (thicker outline).
  component ScreenTile: Rectangle {
    id: tile
    property string icon: ""
    property string label: ""
    property bool highlighted: false
    property bool grabbed: false
    property bool hasCursor: false

    readonly property color faint: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.06)
    readonly property color line: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.35)

    radius: Style.cornerRadius
    color: grabbed ? Style.selectedFillFor(root.bar.foreground, Color.accent) : faint
    border.width: hasCursor ? 2 : 1
    border.color: hasCursor ? root.bar.foreground : (highlighted ? Color.accent : line)

    Column {
      anchors.centerIn: parent
      width: parent.width - Style.space(6)
      spacing: Style.space(2)

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: tile.icon
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.title
      }

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: tile.label
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }
  }
}
