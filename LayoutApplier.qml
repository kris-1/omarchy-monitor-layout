import QtQuick
import Quickshell.Io
import "LayoutModel.js" as LayoutModel

// Reads the saved layout and the live monitors, restores each monitor's saved
// settings (mode, scale, rotation, adaptive sync) where they have drifted, then
// moves every monitor into place with position-only `hl.monitor` rules in a
// single `hyprctl eval`:
// first past the right edge of the current and the target layout, then to
// the target, so no intermediate state overlaps (see LayoutModel.positionsToLua).
// Does nothing when every monitor is already where it belongs.
QtObject {
  id: root

  required property string orderPath
  // Also carry out the saved laptop-screen mode (withExternal) through
  // Omarchy's commands. Only the service does, so the panel's applier cannot
  // run them a second time in parallel.
  property bool manageExternalMode: false

  // Emitted after each pass, whether or not anything had to move.
  signal applied()

  property bool _pending: false
  property bool _pendingSettings: false
  // Settings are restored at most once per pass, so a mode Hyprland refuses
  // cannot keep the applier looping.
  property bool _settingsTried: false
  // Outputs this applier has positioned, so unplugged ones can be parked.
  property var _knownOutputs: []

  // positionsOnly: leave monitor settings alone, e.g. while a change made in
  // the properties window waits to be kept or reverted.
  function apply(positionsOnly) {
    if (readProc.running || evalProc.running || modeProc.running) {
      _pending = true
      _pendingSettings = _pendingSettings || !positionsOnly
      return
    }
    _pending = false
    _pendingSettings = false
    _settingsTried = !!positionsOnly
    readProc.running = true
  }

  function _finish() {
    root.applied()
    if (_pending) apply(!_pendingSettings)
  }

  // Order file and monitor list in one process, split by an ASCII record separator.
  property Process readProc: Process {
    command: ["bash", "-c", "cat -- \"$1\" 2>/dev/null; printf '\\036'; hyprctl monitors all -j", "_", root.orderPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parts = String(text || "").split("\u001e")
        var layout = LayoutModel.parseLayout(parts[0])
        var monitors = []
        try { monitors = JSON.parse(parts[1] || "[]") } catch (e) { monitors = [] }

        // The laptop-screen mode goes first: Omarchy's command reloads the
        // config, and the reload brings the service back here.
        var modeCommand = root.manageExternalMode && !root._settingsTried
          ? LayoutModel.externalModeCommand(monitors, layout.withExternal) : null
        if (modeCommand) {
          root._settingsTried = true
          root.modeProc.command = modeCommand
          root.modeProc.running = true
          return
        }

        // Settings change logical sizes, so positions are computed from a
        // fresh read once they have been restored.
        var drifted = root._settingsTried ? [] : LayoutModel.pendingSettings(monitors, layout)
        root._settingsTried = true
        if (drifted.length > 0) {
          root.evalProc.rereadAfter = true
          root.evalProc.command = ["hyprctl", "eval", LayoutModel.settingsToLua(drifted)]
          root.evalProc.running = true
          return
        }

        var positions = LayoutModel.computePositions(monitors, layout.order)
        // Only unplugged outputs are parked; a connected but disabled one (the
        // laptop screen in external-only mode) is left alone.
        var connected = monitors.map(function(monitor) { return String(monitor.name) })
        var parked = LayoutModel.parkedOutputs(root._knownOutputs, positions).filter(function(name) {
          return connected.indexOf(name) === -1
        })
        var known = parked.slice()
        positions.forEach(function(p) { known.push(p.name) })
        root._knownOutputs = known

        var anyChanged = positions.some(function(p) { return p.changed })
        if (!anyChanged) {
          root._finish()
          return
        }
        var staging = LayoutModel.stagingX(monitors, positions)
        root.evalProc.command = ["hyprctl", "eval", LayoutModel.positionsToLua(positions, staging, parked)]
        root.evalProc.running = true
      }
    }
  }

  property Process modeProc: Process {
    stdout: StdioCollector { waitForEnd: true }
    onRunningChanged: if (!running) root._finish()
  }

  property Process evalProc: Process {
    property bool rereadAfter: false
    stdout: StdioCollector { waitForEnd: true }
    onRunningChanged: {
      if (running) return
      if (rereadAfter) {
        rereadAfter = false
        root.readProc.running = true
      } else {
        root._finish()
      }
    }
  }
}
