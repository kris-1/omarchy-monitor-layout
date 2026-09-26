# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

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
