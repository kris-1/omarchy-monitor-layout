import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Ui
import qs.Commons
import "LayoutModel.js" as LayoutModel

// ARRANGEMENT section: a live, scaled preview of the
// connected displays. Drag a tile to change the left-to-right order, or drive
// it from the keyboard through moveCursor()/activate(). Double-click a tile
// (or showProperties() for the tile under the cursor) to open its properties
// window (MonitorProperties.qml). The order and the settings kept there are
// saved to ~/.config/omarchy/monitor-layout.json and applied right away;
// Service.qml keeps them applied across hotplug and config reloads.
//
// Self-contained so any panel can embed it, e.g. a Display panel:
//
//   Arrangement {
//     bar: root.bar
//     active: root.opened
//     focused: root.focusSection === "arrangement"
//     cursorActive: root.cursorActive
//     panel: panelWindow   // the KeyboardPanel, to open properties beside it
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
  // Host KeyboardPanel; the properties window opens beside its card.
  property var panel: null

  readonly property string orderPath: Quickshell.env("HOME") + "/.config/omarchy/monitor-layout.json"

  // [{ name, key, label, internal, focused, x, w, h }], left to right.
  property var tiles: []
  // Raw `hyprctl monitors all -j` output behind the tiles.
  property var monitors: []
  readonly property bool hasInternal: monitors.some(function(monitor) { return LayoutModel.isInternal(monitor) })
  // Outputs showing their Identify badge (see identify()).
  property var identifyOutputs: []
  // Output shown in the properties window ("" = closed).
  property string propertiesOutput: ""
  readonly property var propertiesTile: {
    for (var i = 0; i < tiles.length; i++)
      if (tiles[i].name === propertiesOutput) return tiles[i]
    return null
  }
  // One display still gets the section, for its settings; reordering needs two.
  readonly property bool available: tiles.length > 0
  readonly property bool reorderable: tiles.length > 1

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
    if (!reorderable) return
    var to = Math.max(0, Math.min(tiles.length - 1, selectedIndex + dx))
    if (grabbedIndex >= 0) {
      if (to === grabbedIndex) return
      moveTile(grabbedIndex, to)
      grabbedIndex = to
    }
    selectedIndex = to
  }

  // Enter: pick up / drop the tile under the cursor; with a single display,
  // open its settings.
  function activate() {
    if (!available) return
    if (!reorderable) {
      showProperties()
      return
    }
    grabbedIndex = grabbedIndex >= 0 ? -1 : selectedIndex
  }

  // Extend / External only / Mirror for the laptop screen while an external
  // display is connected. The mode is saved first; Service.qml carries out
  // external-only and mirror step by step. It never acts in "extend", so
  // switching back undoes both here.
  function setExternalMode(mode) {
    if (mode === orderFile.layout.withExternal) return
    orderFile.saveExternalMode(mode)
    if (mode === "extend" && !modeReset.running) modeReset.running = true
  }

  // Identify: number every display on its screen for a few seconds.
  function identify() {
    identifyOutputs = tiles.map(function(tile) { return tile.name })
    identifyTimer.restart()
  }

  // I: open the properties of the tile under the cursor.
  function showProperties() {
    if (!available || grabbedIndex >= 0 || !tiles[selectedIndex]) return
    propertiesOutput = tiles[selectedIndex].name
  }

  // Stop keeping a setting for an output, e.g. when the panel's SCALE row
  // changes the scale in monitors.lua, which should then win.
  function forgetSetting(output, field) {
    for (var i = 0; i < tiles.length; i++) {
      if (tiles[i].name !== output) continue
      var saved = orderFile.layout.monitors[tiles[i].key]
      if (!saved || saved[field] === undefined) return
      var change = {}
      change[field] = null
      orderFile.saveSettings(tiles[i].key, change)
      return
    }
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
    if (!active) {
      propertiesOutput = ""
      identifyOutputs = []
    }
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
    // "all" so a laptop screen turned off in external-only mode is still known.
    command: ["hyprctl", "monitors", "all", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var monitors = []
        try { monitors = JSON.parse(String(text || "[]")) } catch (e) { monitors = [] }
        root.monitors = monitors
        root.tiles = LayoutModel.tilesFromMonitors(monitors)
      }
    }
  }

  // Saved layout: order and per-monitor settings. Kept in memory so
  // remembered-but-unplugged monitors survive a save made while they are away.
  FileView {
    id: orderFile
    path: root.orderPath
    atomicWrites: true
    printErrors: false

    property var layout: ({ order: [], monitors: {} })

    onLoaded: layout = LayoutModel.parseLayout(text())
    onLoadFailed: layout = { order: [], monitors: {} }

    function save(keys) {
      layout = LayoutModel.withOrder(layout, keys)
      setText(LayoutModel.serializeLayout(layout))
      applier.apply()
    }

    // Service.qml sees the change and carries the mode out.
    function saveExternalMode(mode) {
      layout = LayoutModel.withExternalMode(layout, mode)
      setText(LayoutModel.serializeLayout(layout))
    }

    // Already live (tried in the properties window), so only saved here.
    function saveSettings(key, settings) {
      layout = LayoutModel.withMonitorSettings(layout, key, settings)
      setText(LayoutModel.serializeLayout(layout))
    }
  }

  MonitorProperties {
    id: properties
    bar: root.bar
    hostPanel: root.panel
    open: root.active && root.propertiesTile !== null
    monitor: {
      var tile = root.propertiesTile
      if (!tile) return null
      for (var i = 0; i < root.monitors.length; i++)
        if (root.monitors[i].name === tile.name) return root.monitors[i]
      return null
    }
    savedSettings: root.propertiesTile ? (orderFile.layout.monitors[root.propertiesTile.key] || {}) : ({})
    onCloseRequested: root.propertiesOutput = ""
    // A new mode, scale or rotation changes the tile's size: re-pack the row
    // without restoring saved settings over the change being tried.
    onSettingsApplied: applier.apply(true)
    onKept: function(settings) {
      if (root.propertiesTile) orderFile.saveSettings(root.propertiesTile.key, settings)
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

  PanelSectionHeader {
    text: "DISPLAY SETTINGS"
    foreground: root.bar.foreground
    fontFamily: root.bar.fontFamily
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
          number: index + 1
          highlighted: modelData.focused
          grabbed: dragged || root.grabbedIndex === index
          hasCursor: root.cursorActive && root.focused && root.selectedIndex === index

          MouseArea {
            anchors.fill: parent
            // The panel scrolls inside a Flickable; without this it can steal
            // the gesture and swallow the release.
            preventStealing: true
            hoverEnabled: true
            cursorShape: !root.reorderable ? Qt.PointingHandCursor
              : pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor

            property real pressX: 0

            onContainsMouseChanged: if (containsMouse && !pressed) {
              root.selectedIndex = screenTile.index
              root.focusRequested()
            }
            onPressed: function(mouse) {
              if (!root.reorderable) return
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
            onDoubleClicked: root.propertiesOutput = screenTile.modelData.name
            onCanceled: {
              canvas.dragIndex = -1
              canvas.dragOffset = 0
            }
          }
        }
      }
    }
  }

  Item {
    width: parent.width
    implicitHeight: Math.max(hint.implicitHeight, identifyButton.implicitHeight)

    Text {
      id: hint
      textFormat: Text.PlainText
      text: root.grabbedIndex >= 0 ? "H/L TO MOVE · ENTER TO DROP"
        : root.cursorActive && root.focused
          ? (root.reorderable ? "ENTER TO PICK UP · I FOR SETTINGS" : "ENTER FOR SETTINGS")
        : root.reorderable ? "DRAG · DOUBLE-CLICK FOR SETTINGS" : "DOUBLE-CLICK FOR SETTINGS"
      color: Qt.darker(root.bar.foreground, 1.4)
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      elide: Text.ElideRight
      anchors.left: parent.left
      anchors.right: identifyButton.left
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
    }

    Button {
      id: identifyButton
      text: "Identify"
      fontSize: Style.font.caption
      foreground: root.bar.foreground
      fontFamily: root.bar.fontFamily
      horizontalPadding: Style.spacing.md
      verticalPadding: Style.spacing.controlPaddingY
      bordered: true
      active: root.identifyOutputs.length > 0
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      onClicked: root.identify()
    }
  }

  // Laptop screen while an external display is connected, like Win+P.
  Column {
    visible: root.hasInternal
    width: parent.width
    spacing: Style.space(10)
    topPadding: Style.space(4)

    PanelSectionHeader {
      text: "WITH AN EXTERNAL DISPLAY"
      foreground: root.bar.foreground
      fontFamily: root.bar.fontFamily
    }

    Grid {
      id: modeRow
      width: parent.width
      columns: 3
      spacing: Style.spacing.xs

      readonly property real cellWidth: (width - spacing * (columns - 1)) / columns

      Repeater {
        model: [
          { value: "extend", label: "Extend" },
          { value: "external-only", label: "External only" },
          { value: "mirror", label: "Mirror" }
        ]

        Button {
          required property var modelData
          width: modeRow.cellWidth
          text: modelData.label
          fontSize: Style.font.caption
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          horizontalPadding: Style.spacing.sm
          verticalPadding: Style.spacing.controlPaddingY
          bordered: true
          active: orderFile.layout.withExternal === modelData.value
          onClicked: root.setExternalMode(modelData.value)
        }
      }
    }
  }

  // Numbers the displays on their screens: all of them for a moment after
  // Identify, and the one whose settings window is open.
  IdentifyOverlay {
    foreground: root.bar.foreground
    fontFamily: root.bar.fontFamily
    entries: {
      var list = []
      for (var i = 0; i < root.tiles.length; i++) {
        var tile = root.tiles[i]
        if (root.identifyOutputs.indexOf(tile.name) === -1 && tile.name !== root.propertiesOutput) continue
        list.push({ output: tile.name, number: i + 1, label: tile.internal ? "Built-in display" : tile.label })
      }
      return root.active ? list : []
    }
  }

  Process {
    id: modeReset
    command: {
      var steps = LayoutModel.extendCommands()
      return ["bash", "-c", "\"$1\" \"$2\"; \"$3\" \"$4\"", "_"]
        .concat(steps[0]).concat(steps[1])
    }
    stdout: StdioCollector { waitForEnd: true }
    onRunningChanged: if (!running) root.refresh()
  }

  Timer {
    id: identifyTimer
    interval: 3000
    onTriggered: root.identifyOutputs = []
  }

  // One display in the preview. highlighted = focused display (accent border);
  // grabbed = being dragged or picked up with Enter (filled); hasCursor =
  // keyboard cursor (thicker outline).
  component ScreenTile: Rectangle {
    id: tile
    property string icon: ""
    property string label: ""
    property int number: 0
    property bool highlighted: false
    property bool grabbed: false
    property bool hasCursor: false

    readonly property color faint: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.06)
    readonly property color line: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.35)

    radius: Style.cornerRadius
    color: grabbed ? Style.selectedFillFor(root.bar.foreground, Color.accent) : faint
    border.width: hasCursor ? 2 : 1
    border.color: hasCursor ? root.bar.foreground : (highlighted ? Color.accent : line)

    // Matches the number Identify shows on the screen.
    Text {
      textFormat: Text.PlainText
      text: tile.number > 0 ? String(tile.number) : ""
      color: Qt.darker(root.bar.foreground, 1.4)
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.leftMargin: Style.space(6)
      anchors.topMargin: Style.space(4)
    }

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
