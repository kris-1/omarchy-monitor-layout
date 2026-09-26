# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

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
