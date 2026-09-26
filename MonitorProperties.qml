import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Ui
import qs.Commons
import "LayoutModel.js" as LayoutModel
import "Model.js" as Model

// Properties window for one display, opened from its ARRANGEMENT tile. Shows
// what the display reports and edits its mode, scale, rotation and adaptive
// sync. Changes are tried first: they apply at once and revert after a
// countdown unless kept in KeepSettingsDialog, so a mode the display cannot
// show never sticks.
// Kept changes are handed to the host (`kept`) to be saved and re-applied by
// the service.
//
// A layer-shell surface of its own, beside the host panel's card: the panel
// stays open and visible next to it.
PanelWindow {
  id: root

  required property QtObject bar
  // KeyboardPanel this window opens beside; it gets keyboard focus back on
  // close. Without one the card is centered on the screen.
  property var hostPanel: null
  property bool open: false
  // Live `hyprctl monitors -j` entry of the display, and its saved settings.
  property var monitor: null
  property var savedSettings: ({})

  // Seconds a tried change waits for Keep before it is reverted.
  readonly property int trialSeconds: 30
  readonly property var scalePresets: ["1", "1.25", "1.5", "1.6", "2", "3", "4"]
  readonly property var rotationOptions: [
    { value: "0", label: "0°" },
    { value: "1", label: "90°" },
    { value: "2", label: "180°" },
    { value: "3", label: "270°" }
  ]
  readonly property var vrrOptions: [
    { value: "0", label: "Off" },
    { value: "1", label: "On" },
    { value: "2", label: "Fullscreen" }
  ]

  signal closeRequested()
  // Settings were changed on the live display (tried or reverted).
  signal settingsApplied()
  // The user kept a tried change: { mode?, scale?, transform?, vrr? }.
  signal kept(var settings)

  // Staged values, edited by the controls and tried with Apply.
  property int stagedWidth: 0
  property int stagedHeight: 0
  property string stagedRefresh: ""
  property real stagedScale: 1
  property int stagedTransform: 0
  property int stagedVrr: 0
  // hyprctl reports VRR as a boolean, so "fullscreen only" (2) is known from
  // the saved settings alone. What the display runs with now.
  property int currentVrr: 0

  // While a change is tried: the settings to restore, the ones tried, and the
  // seconds left before reverting.
  property var trialBefore: null
  property var trialChanges: null
  property int countdown: 0
  // Between Apply and the dialog: checking that the display took the change.
  property bool verifying: false
  property bool _verifyAfterRun: false
  // Why the last change was reverted without asking ("" = nothing to say).
  property string rejectMessage: ""
  readonly property bool trying: trialBefore !== null

  // Keyboard cursor: a row from `rows` and a column within it.
  readonly property var rows: ["resolution", "refresh", "scale", "rotation", "vrr", "actions"]
  property int cursorRow: 0
  property int cursorCol: 0
  property bool cursorActive: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color muted: Qt.darker(foreground, 1.4)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property bool internal: !!monitor && LayoutModel.isInternal(monitor)
  readonly property var resolutions: monitor ? LayoutModel.resolutionOptions(monitor.availableModes || []) : []
  readonly property var refreshRates: monitor
    ? LayoutModel.refreshOptions(monitor.availableModes || [], stagedWidth, stagedHeight)
    : []
  readonly property var scaleOptions: {
    var values = Model.availableScales(scalePresets, stagedWidth, stagedHeight)
    return values.map(function(value) {
      return { value: value, label: Model.cleanScale(value, stagedWidth, stagedHeight) + "x" }
    })
  }

  // Staged fields that differ from the live display.
  readonly property var pending: {
    var changes = {}
    if (!monitor || stagedWidth <= 0) return changes
    var mode = LayoutModel.modeString(stagedWidth, stagedHeight, Number(stagedRefresh))
    if (!LayoutModel.settingsMatch(monitor, { mode: mode })) changes.mode = mode
    var scale = Number(Model.cleanScale(stagedScale, stagedWidth, stagedHeight)) || stagedScale
    if (!LayoutModel.settingsMatch(monitor, { scale: scale })) changes.scale = scale
    if (stagedTransform !== (Number(monitor.transform) || 0)) changes.transform = stagedTransform
    if (stagedVrr !== currentVrr) changes.vrr = stagedVrr
    return changes
  }
  readonly property bool dirty: Object.keys(pending).length > 0

  function stageLive() {
    if (!monitor) return
    stagedWidth = Number(monitor.width) || 0
    stagedHeight = Number(monitor.height) || 0
    stagedRefresh = LayoutModel.formatRefresh(monitor.refreshRate)
    stagedScale = Number(Model.normalizeScale(monitor.scale)) || 1
    stagedTransform = Number(monitor.transform) || 0
    currentVrr = savedSettings && savedSettings.vrr === 2 ? 2 : (monitor.vrr ? 1 : 0)
    stagedVrr = currentVrr
  }

  function stage(settings) {
    var mode = settings.mode !== undefined ? LayoutModel.parseMode(settings.mode) : null
    if (mode) {
      stagedWidth = mode.width
      stagedHeight = mode.height
      stagedRefresh = LayoutModel.formatRefresh(mode.refresh)
    }
    if (settings.scale !== undefined) stagedScale = settings.scale
    if (settings.transform !== undefined) stagedTransform = settings.transform
    if (settings.vrr !== undefined) stagedVrr = settings.vrr
  }

  // A new resolution keeps the refresh rate when the display offers it there,
  // otherwise takes the fastest, and rounds the scale to one that fits.
  function stageResolution(value) {
    var mode = LayoutModel.parseMode(value)
    if (!mode) return
    rejectMessage = ""
    stagedWidth = mode.width
    stagedHeight = mode.height
    var rates = refreshRates.map(function(option) { return option.value })
    if (rates.indexOf(stagedRefresh) === -1 && rates.length > 0) stagedRefresh = rates[0]
    stagedScale = Number(Model.cleanScale(stagedScale, stagedWidth, stagedHeight)) || stagedScale
  }

  function stepResolution(delta) {
    var current = stagedWidth + "x" + stagedHeight
    var index = -1
    for (var i = 0; i < resolutions.length; i++)
      if (resolutions[i].value === current) index = i
    var next = Math.max(0, Math.min(resolutions.length - 1, index + delta))
    if (next !== index && resolutions[next]) stageResolution(resolutions[next].value)
  }

  function tryChanges() {
    if (!dirty || trying || !monitor) return
    var changes = pending
    var live = LayoutModel.liveSettings(monitor)
    var before = {}
    for (var field in changes) before[field] = field === "vrr" ? currentVrr : live[field]
    trialBefore = before
    trialChanges = changes
    if (changes.vrr !== undefined) currentVrr = changes.vrr
    verifying = true
    rejectMessage = ""
    _verifyAfterRun = true
    run(LayoutModel.settingsRule(monitor.name, changes))
    cursorCol = 1
  }

  function keep() {
    if (!trying) return
    var changes = trialChanges
    countdownTimer.stop()
    trialBefore = null
    trialChanges = null
    root.kept(changes)
  }

  function revert() {
    if (!trying) return
    var before = trialBefore
    countdownTimer.stop()
    verifying = false
    trialBefore = null
    trialChanges = null
    if (before.vrr !== undefined) currentVrr = before.vrr
    stage(before)
    if (monitor) run(LayoutModel.settingsRule(monitor.name, before))
  }

  // Closing never keeps a change silently.
  function close() {
    revert()
    root.closeRequested()
  }

  property var _queue: []
  function run(lua) {
    if (!lua) return
    _queue = _queue.concat([lua])
    if (!evalProc.running) _runNext()
  }
  function _runNext() {
    if (_queue.length === 0) return
    evalProc.command = ["hyprctl", "eval", _queue[0]]
    _queue = _queue.slice(1)
    evalProc.running = true
  }

  // ---- keyboard ----

  function optionsFor(row) {
    if (row === "refresh") return refreshRates
    if (row === "scale") return scaleOptions
    if (row === "rotation") return rotationOptions
    if (row === "vrr") return vrrOptions
    if (row === "actions") return [0, 1]
    return []
  }

  function selectedCol(row) {
    var options = optionsFor(row)
    var value = row === "refresh" ? stagedRefresh
      : row === "scale" ? String(stagedScale)
      : row === "rotation" ? String(stagedTransform)
      : row === "vrr" ? String(stagedVrr) : ""
    for (var i = 0; i < options.length; i++) {
      if (row === "scale") {
        if (Math.abs(Number(Model.cleanScale(options[i].value, stagedWidth, stagedHeight)) - stagedScale) < 0.005) return i
      } else if (options[i].value === value) {
        return i
      }
    }
    return row === "actions" ? 1 : 0
  }

  function moveCursor(dx, dy) {
    if (!cursorActive) { cursorActive = true; return }
    var row = rows[cursorRow]
    if (dy !== 0) {
      cursorRow = Math.max(0, Math.min(rows.length - 1, cursorRow + dy))
      cursorCol = selectedCol(rows[cursorRow])
      return
    }
    if (row === "resolution") {
      stepResolution(dx)
      return
    }
    cursorCol = Math.max(0, Math.min(optionsFor(row).length - 1, cursorCol + dx))
  }

  function activate() {
    if (!cursorActive) { cursorActive = true; return }
    var row = rows[cursorRow]
    if (row === "resolution") { resolutionDropdown.open(); return }
    if (row === "actions") {
      if (cursorCol === 0) close()
      else tryChanges()
      return
    }
    var option = optionsFor(row)[cursorCol]
    if (option) choose(row, option.value)
  }

  function choose(row, value) {
    if (trying) return
    rejectMessage = ""
    if (row === "refresh") stagedRefresh = value
    else if (row === "scale") stagedScale = Number(Model.cleanScale(value, stagedWidth, stagedHeight)) || Number(value)
    else if (row === "rotation") stagedTransform = Number(value)
    else if (row === "vrr") stagedVrr = Number(value)
  }

  function hoverCursor(row, col) {
    cursorActive = true
    cursorRow = rows.indexOf(row)
    cursorCol = col
  }

  function hasCursor(row, col) {
    return cursorActive && rows[cursorRow] === row && (col === undefined || cursorCol === col)
  }

  // Hyprland refuses or replaces what a display cannot do without failing
  // the call, so the live state is compared with what was asked for.
  function verifyTrial(monitors) {
    if (!trying || !monitor) return
    verifying = false
    var live = null
    for (var i = 0; i < monitors.length; i++)
      if (monitors[i].name === monitor.name) live = monitors[i]
    var rejected = live ? LayoutModel.rejectedFields(live, trialChanges) : ["mode"]
    if (rejected.length === 0) {
      countdown = trialSeconds
      countdownTimer.restart()
      return
    }
    var names = { mode: "mode", scale: "scale", transform: "rotation", vrr: "adaptive sync" }
    revert()
    rejectMessage = "THE DISPLAY DID NOT ACCEPT THIS " + rejected.map(function(field) {
      return names[field]
    }).join(" AND ").toUpperCase()
  }

  onOpenChanged: {
    if (open) {
      rejectMessage = ""
      verifying = false
      trialBefore = null
      trialChanges = null
      stageLive()
      cursorActive = false
      cursorRow = 0
      cursorCol = 0
      focusPrimed = false
      focusPrime.restart()
      Qt.callLater(function() { if (root.open) keyCatcher.forceActiveFocus() })
    } else {
      resolutionDropdown.close()
      revert()
      if (hostPanel && typeof hostPanel.beginFocusPrime === "function") hostPanel.beginFocusPrime()
      if (hostPanel && hostPanel.focusTarget) hostPanel.focusTarget.forceActiveFocus()
    }
  }
  // Unplugged while open.
  onMonitorChanged: if (open && !monitor) close()

  KeepSettingsDialog {
    screen: root.screen
    open: root.open && root.trying && !root.verifying
    seconds: root.countdown
    totalSeconds: root.trialSeconds
    foreground: root.foreground
    fontFamily: root.fontFamily
    onKept: root.keep()
    onReverted: root.revert()
    // Hand the keyboard back to the properties card.
    onOpenChanged: if (!open && root.open) {
      root.focusPrimed = false
      focusPrime.restart()
      keyCatcher.forceActiveFocus()
    }
  }

  Timer {
    id: countdownTimer
    interval: 1000
    repeat: true
    onTriggered: {
      root.countdown = root.countdown - 1
      if (root.countdown <= 0) root.revert()
    }
  }

  // Give the display a moment to switch before reading its state back.
  Timer {
    id: verifyDelay
    interval: 600
    onTriggered: if (!verifyProc.running) verifyProc.running = true
  }

  Process {
    id: verifyProc
    command: ["hyprctl", "monitors", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var monitors = []
        try { monitors = JSON.parse(String(text || "[]")) } catch (e) { monitors = [] }
        root.verifyTrial(monitors)
      }
    }
  }

  Process {
    id: evalProc
    stdout: StdioCollector { waitForEnd: true }
    onRunningChanged: {
      if (running) return
      root.settingsApplied()
      if (root._verifyAfterRun && root._queue.length === 0) {
        root._verifyAfterRun = false
        verifyDelay.restart()
      }
      root._runNext()
    }
  }

  // ---- surface ----

  // Same focus handling as KeyboardPanel: a brief Exclusive prime so the
  // surface takes the keyboard from the panel, then OnDemand.
  property bool focusPrimed: false
  Timer {
    id: focusPrime
    interval: 75
    onTriggered: if (root.open) root.focusPrimed = true
  }

  screen: hostPanel ? hostPanel.screen : null
  visible: open || card.opacity > 0
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "omarchy-monitor-properties"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: open
    ? (focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)
    : WlrKeyboardFocus.None

  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }

  readonly property real margin: Style.gapsOut
  readonly property real cardWidth: Math.min(Style.space(380), width - margin * 2)
  readonly property real cardHeight: Math.min(body.implicitHeight + card.contentTopInset + card.contentBottomInset,
    height - margin * 2)
  // Beside the host panel's card: left of it when there is room, else right,
  // else centered.
  readonly property point cardOrigin: {
    var x = (width - cardWidth) / 2
    var y = (height - cardHeight) / 2
    if (hostPanel && hostPanel.cardOrigin) {
      var hostX = hostPanel.cardOrigin.x
      var hostW = hostPanel.contentWidth
      if (hostX - margin - cardWidth >= margin) x = hostX - margin - cardWidth
      else if (hostX + hostW + margin + cardWidth <= width - margin) x = hostX + hostW + margin
      y = hostPanel.cardOrigin.y
    }
    y = Math.max(margin, Math.min(y, height - cardHeight - margin))
    return Qt.point(Math.round(x), Math.round(y))
  }

  // Clicks outside the card close the window, the panel stays.
  MouseArea {
    anchors.fill: parent
    enabled: root.open
    acceptedButtons: Qt.AllButtons
    onClicked: root.close()
  }

  BorderSurface {
    id: card
    x: root.cardOrigin.x
    y: root.cardOrigin.y
    width: root.cardWidth
    height: root.cardHeight
    color: Color.popups.background
    borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
    padding: Style.spacing.popupPadding
    radius: Style.cornerRadius
    opacity: root.open ? 1.0 : 0
    clip: true

    Behavior on opacity {
      NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.AllButtons
    }

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      anchors.topMargin: card.contentTopInset
      anchors.rightMargin: card.contentRightInset
      anchors.bottomMargin: card.contentBottomInset
      anchors.leftMargin: card.contentLeftInset
      blocked: resolutionDropdown.popupOpen
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activate()
      onCloseRequested: root.trying ? root.revert() : root.close()

      Column {
        id: body
        width: parent.width
        spacing: Style.space(14)

        // ---------- Hero: display icon · name/summary ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            text: root.internal ? "󰌢" : "󰍹"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              textFormat: Text.PlainText
              text: root.monitor ? (root.internal ? "Built-in display" : LayoutModel.tileLabel(root.monitor)) : ""
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: {
                var m = root.monitor
                if (!m) return ""
                var parts = [String(m.name)]
                var inches = LayoutModel.diagonalInches(m.physicalWidth, m.physicalHeight)
                if (inches > 0) parts.push(inches + "″")
                var ppi = LayoutModel.pixelDensity(m.width, m.height, m.physicalWidth, m.physicalHeight)
                if (ppi > 0) parts.push(ppi + " PPI")
                return parts.join(" · ").toUpperCase()
              }
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }
        }

        // ---------- Details ----------
        PanelSeparator { foreground: root.foreground }

        Column {
          width: parent.width
          spacing: Style.space(6)

          PanelSectionHeader {
            text: "DETAILS"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Repeater {
            model: {
              var m = root.monitor
              if (!m) return []
              var rows = [
                ["Manufacturer", String(m.make || "").trim()],
                ["Model", String(m.model || "").trim()],
                ["Serial", String(m.serial || "").trim()],
                ["Connector", String(m.name || "")],
                ["Physical size", Number(m.physicalWidth) > 0
                  ? m.physicalWidth + " × " + m.physicalHeight + " mm" : ""],
                ["Workspace area", LayoutModel.logicalSize(m).w + " × " + LayoutModel.logicalSize(m).h
                  + " at " + m.x + ", " + m.y],
                ["Pixel format", String(m.currentFormat || "")]
              ]
              return rows.filter(function(row) { return row[1] !== "" })
            }

            DetailRow {
              required property var modelData
              label: modelData[0]
              value: modelData[1]
            }
          }
        }

        // ---------- Mode ----------
        PanelSeparator { foreground: root.foreground }

        Column {
          width: parent.width
          spacing: Style.space(10)
          enabled: !root.trying
          opacity: enabled ? 1 : 0.5

          SectionHeader { text: "RESOLUTION" }

          Dropdown {
            id: resolutionDropdown
            width: parent.width
            showLabel: false
            options: root.resolutions
            value: root.stagedWidth + "x" + root.stagedHeight
            foreground: root.foreground
            fontFamily: root.fontFamily
            hasCursor: root.hasCursor("resolution")
            onChanged: function(value) { root.stageResolution(value) }
            onHovered: function(isHovered) { if (isHovered) root.hoverCursor("resolution", 0) }
          }

          SectionHeader { text: "REFRESH RATE" }
          PillRow { row: "refresh"; options: root.refreshRates; value: root.stagedRefresh }

          SectionHeader { text: "SCALE" }
          PillRow {
            row: "scale"
            options: root.scaleOptions
            value: {
              for (var i = 0; i < root.scaleOptions.length; i++) {
                var v = root.scaleOptions[i].value
                if (Math.abs(Number(Model.cleanScale(v, root.stagedWidth, root.stagedHeight)) - root.stagedScale) < 0.005) return v
              }
              return ""
            }
          }

          SectionHeader { text: "ROTATION" }
          PillRow { row: "rotation"; options: root.rotationOptions; value: String(root.stagedTransform) }

          SectionHeader { text: "ADAPTIVE SYNC" }
          PillRow { row: "vrr"; options: root.vrrOptions; value: String(root.stagedVrr) }
        }

        // ---------- Actions ----------
        PanelSeparator { foreground: root.foreground }

        Item {
          width: parent.width
          implicitHeight: Math.max(status.implicitHeight, actions.implicitHeight)

          Text {
            id: status
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.right: actions.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            text: root.verifying ? "APPLYING…"
              : root.trying ? "WAITING FOR CONFIRMATION"
              : root.rejectMessage !== "" ? root.rejectMessage
              : root.dirty ? "NOT APPLIED YET" : "ESC TO CLOSE"
            color: root.trying ? Color.accent : root.rejectMessage !== "" ? Color.urgent : root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            wrapMode: Text.WordWrap
          }

          Row {
            id: actions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.xs

            ActionButton {
              col: 0
              text: "Close"
              enabled: !root.trying
              onClicked: root.close()
            }

            ActionButton {
              col: 1
              text: "Apply"
              enabled: root.dirty && !root.trying
              active: enabled
              onClicked: root.tryChanges()
            }
          }
        }
      }
    }
  }

  component SectionHeader: PanelSectionHeader {
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  component DetailRow: Item {
    id: detail
    property string label: ""
    property string value: ""
    width: parent ? parent.width : 0
    implicitHeight: Math.max(detailLabel.implicitHeight, detailValue.implicitHeight)

    Text {
      id: detailLabel
      textFormat: Text.PlainText
      text: detail.label
      color: root.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: detailValue
      textFormat: Text.PlainText
      text: detail.value
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignRight
      elide: Text.ElideLeft
      anchors.left: detailLabel.right
      anchors.leftMargin: Style.space(12)
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  // Pick-one row of pills, styled like the panel's SCALE presets.
  component PillRow: Grid {
    id: pillRow
    property string row: ""
    property var options: []
    property string value: ""

    width: parent ? parent.width : 0
    columns: Math.max(1, Math.min(options.length, 4))
    spacing: Style.spacing.xs

    readonly property real cellWidth: (width - spacing * (columns - 1)) / columns

    Repeater {
      model: pillRow.options

      Button {
        required property var modelData
        required property int index

        width: pillRow.cellWidth
        text: modelData.label
        fontSize: Style.font.caption
        foreground: root.foreground
        fontFamily: root.fontFamily
        horizontalPadding: Style.spacing.sm
        verticalPadding: Style.spacing.controlPaddingY
        bordered: true
        active: modelData.value === pillRow.value
        hasCursor: root.hasCursor(pillRow.row, index)
        onClicked: root.choose(pillRow.row, modelData.value)
        onHovered: function(isHovered) { if (isHovered) root.hoverCursor(pillRow.row, index) }
      }
    }
  }

  component ActionButton: Button {
    id: action
    property int col: 0
    fontSize: Style.font.caption
    foreground: root.foreground
    fontFamily: root.fontFamily
    horizontalPadding: Style.spacing.md
    verticalPadding: Style.spacing.controlPaddingY
    bordered: true
    opacity: enabled ? 1 : 0.45
    hasCursor: root.hasCursor("actions", col)
    onHovered: function(isHovered) { if (isHovered) root.hoverCursor("actions", action.col) }
  }
}
