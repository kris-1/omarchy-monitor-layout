import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Keeps monitors in the saved left-to-right order, with their kept settings,
// and carries out the saved laptop-screen mode (extend, external only,
// mirror). Re-applies all of it when a monitor is plugged in or removed, when
// Hyprland reloads its config (which resets positions to the ones in
// monitors.lua), and when the order file changes on disk.
Item {
  id: root

  // Injected by omarchy-shell.
  property var shell: null
  property var manifest: null

  readonly property string orderPath: Quickshell.env("HOME") + "/.config/omarchy/monitor-layout.json"

  LayoutApplier {
    id: applier
    orderPath: root.orderPath
    manageExternalMode: true
  }

  // Hotplug arrives as a burst (a dock brings several outputs at once, a
  // config reload fires several events); settle before arranging.
  Timer {
    id: settle
    interval: 300
    repeat: false
    onTriggered: applier.apply()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event || !event.name) return
      switch (String(event.name)) {
      case "monitoradded":
      case "monitoraddedv2":
      case "monitorremoved":
      case "monitorremovedv2":
      case "configreloaded":
        settle.restart()
        break
      }
    }
  }

  FileView {
    path: root.orderPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: settle.restart()
  }

  Component.onCompleted: settle.restart()
}
