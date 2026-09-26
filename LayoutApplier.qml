import QtQuick
import Quickshell
import Quickshell.Io
import "LayoutModel.js" as LayoutModel

// Reads the saved order and the live monitors, then moves every monitor into
// place with position-only `hl.monitor` rules in a single `hyprctl eval`:
// first past the right edge of the current and the target layout, then to
// the target, so no intermediate state overlaps (see LayoutModel.positionsToLua).
// Does nothing when every monitor is already where it belongs.
QtObject {
  id: root

  required property string orderPath

  // Emitted after each pass, whether or not anything had to move.
  signal applied()

  property bool _pending: false

  function apply() {
    if (readProc.running || evalProc.running) {
      _pending = true
      return
    }
    _pending = false
    readProc.running = true
  }

  function _finish() {
    root.applied()
    if (_pending) apply()
  }

  // Order file and monitor list in one process, split by an ASCII record separator.
  property Process readProc: Process {
    command: ["bash", "-c", "cat -- \"$1\" 2>/dev/null; printf '\\036'; hyprctl monitors -j", "_", root.orderPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parts = String(text || "").split("\u001e")
        var order = LayoutModel.parseOrder(parts[0])
        var monitors = []
        try { monitors = JSON.parse(parts[1] || "[]") } catch (e) { monitors = [] }

        var positions = LayoutModel.computePositions(monitors, order)
        var anyChanged = positions.some(function(p) { return p.changed })
        if (!anyChanged) {
          root._finish()
          return
        }
        var staging = LayoutModel.stagingX(monitors, positions)
        evalProc.command = ["hyprctl", "eval", LayoutModel.positionsToLua(positions, staging)]
        evalProc.running = true
      }
    }
  }

  property Process evalProc: Process {
    stdout: StdioCollector { waitForEnd: true }
    onRunningChanged: if (!running) root._finish()
  }
}
