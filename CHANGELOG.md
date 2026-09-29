# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed

- Turning a display off or on in DISPLAYS works again on Hyprland 0.55+
  (Lua config), which refuses `hyprctl keyword`: the change goes out through
  `hyprctl eval`, and the laptop screen through
  `omarchy-hyprland-monitor-internal`, as in omacom/omarchy#7036 (#1).
- The DISPLAYS row shows the new state at once, so a second click no longer
  repeats the first while the display state is still being read (#1).

## [0.7.0] - 2026-09-27

### Added

- Displays above or below another: drag a tile onto the top or bottom part
  of another tile (an accent bar marks the edge it will land on), or pick it
  up with `Enter` and press `k`/`j`. A stacked display is centered on the one
  it stands on; several on one side pile up. Saved as `stack` in
  `monitor-layout.json`; a display whose base is unplugged returns to the
  row. The preview shows the real layout in both directions.

### Fixed

- The panel follows changes to `monitor-layout.json` made elsewhere, so the
  WITH AN EXTERNAL DISPLAY buttons always show the saved mode, and Extend
  always brings the laptop screen back.

## [0.6.0] - 2026-09-26

### Added

- Identify: a button under the preview shows a large number and name in the
  corner of every screen for a few seconds, matching the numbers now shown
  on the tiles. The display whose settings window is open keeps its badge.
- Applied changes are checked against what the display reports. A change
  Hyprland refused or replaced (for example adaptive sync on a display
  without it, or a scale it rounded) is reverted at once with a message,
  instead of asking to keep it.
- WITH AN EXTERNAL DISPLAY on laptops: **Extend**, **External only** (the
  laptop screen turns off while an external display is connected) or
  **Mirror**, like Windows' Win+P. The choice is saved (`withExternal`) and
  carried out by the service on every connect through Omarchy's own
  `omarchy-hyprland-monitor-internal` and `-internal-mirror` commands;
  Omarchy turns the laptop screen back on when the last external display is
  unplugged.

### Changed

- `preview.png` shows the settings window next to the panel.
- The DISPLAY SETTINGS hint moved below the preview, next to Identify.
- The layout is read from `hyprctl monitors all -j`, and a connected but
  disabled output (the laptop screen in External only) is no longer parked.

## [0.5.1] - 2026-09-26

### Changed

- The ARRANGEMENT section is now called DISPLAY SETTINGS and also appears
  with a single display, so its settings can be opened; dragging needs two.
  With one display, `Enter` on its tile opens the settings.

## [0.5.0] - 2026-09-26

### Added

- Display properties: double-click a tile in ARRANGEMENT (or press `I` on it)
  to open a window with the display's details and its resolution, refresh
  rate, scale, rotation and adaptive sync.
- Changes are tried first and confirmed in a modal *Keep these display
  settings?* dialog; without confirmation they revert after 30 seconds.
- Kept settings are saved per display in `monitor-layout.json` (`monitors`)
  and restored by the service after hotplug and config reloads.

### Changed

- Choosing a preset in the SCALE section clears a scale kept in the
  properties window for the focused display, so the preset wins.

## [0.4.2] - 2026-09-26

### Fixed

- Plugging a monitor back in no longer triggers Hyprland's "monitor layout
  overlaps" warning. Hyprland kept the monitor's last position rule, a spot
  the compacted layout could now occupy; unplugged monitors are now parked at
  `auto-right`, so they return beside the layout and are then moved into
  place.

## [0.4.1] - 2026-09-26

### Fixed

- Desktops with identical monitors: tiles show the model ("DELL P2419H")
  instead of the vendor, with the port appended when two tiles would read
  the same.
- Identical monitors that report no serial number share a description; they
  are now keyed by port so they can still be reordered.

## [0.4.0] - 2026-09-26

### Changed

- The widget is again a copy of Omarchy's Display widget with the
  ARRANGEMENT section as its only addition, and it declares
  `clonedFrom: omarchy.monitor`: enabling the plugin replaces the built-in
  Display widget, `SUPER + CTRL + D` opens it, and disabling the plugin
  restores the built-in one. The separate bar button is gone.
- `scripts/dev-sync.sh --service-only` installs only the layout service
  for setups with their own Display clone.

## [0.3.1] - 2026-09-26

### Changed

- Prepared for the Omarchy plugin marketplace: `preview.png` in the
  repository root, `license` in the manifest, README with Install, Usage,
  Configure and Remove sections and a list of dependencies.
- `scripts/check.sh` runs `qmllint` when available.
- The upstream proposal links to `omacom/omarchy`.

## [0.3.0] - 2026-09-26

### Changed

- Back to a focused plugin: its own bar button with the ARRANGEMENT section
  only. The copy of Omarchy's Display panel is gone.
- Plugin id is now `monitor-layout`.
- README proposes merging the ARRANGEMENT section into Omarchy's Display
  widget.

## [0.2.0] - 2026-09-26

### Changed

- The bar widget is now Omarchy's full Display panel with an ARRANGEMENT
  section, replacing the built-in Display widget when enabled, instead of a
  separate bar button.
- The ARRANGEMENT section lives in `Arrangement.qml` so existing Display
  clones can embed it.

### Fixed

- Displays are moved through a staging area, so Hyprland no longer warns
  that the monitor layout overlaps while they swap places.

## [0.1.0] - 2026-09-26

### Added

- Bar widget with a live preview of all connected displays; drag a tile to
  change the left-to-right order, or pick it up with Enter and move it with h/l.
- Background service that keeps the saved order applied when displays are
  plugged in or removed and when Hyprland reloads its config.
- Order stored in `~/.config/omarchy/monitor-layout.json`, keyed by monitor
  description so a display keeps its place on any port.
