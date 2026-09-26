# Project notes for AI assistants

Omarchy shell plugin (`monitor-layout`): drag-and-drop monitor arrangement
for Hyprland, and nothing else. See README.md for the user-facing description.

## Conventions

- Everything in the repository is in English: code, comments, docs, commits.
- Keep logic that can be tested out of QML: put it in `LayoutModel.js` as pure
  functions (ES5 style, exported through the `module.exports` guard at the end
  so Node can load it) and cover it in `tests/layout-model.test.cjs`.
- QML follows the style of Omarchy's first-party panels
  (`/usr/share/omarchy/shell/plugins/panels/*`): `qs.Ui` components,
  `Style`/`Color` tokens from `qs.Commons`, no hard-coded colors or sizes.
- Scope is monitor positioning only; do not add unrelated display settings.
- The long-term goal is an upstream merge into Omarchy's Display widget
  (`shell/plugins/panels/monitor/Panel.qml`). Keep `Arrangement.qml`
  self-contained, with `bar`, `active`, `focused`, `cursorActive`,
  `moveCursor()`, `activate()` and `focusRequested` as its API, so the merge
  stays a small wiring change.
- Never edit `/usr/share/omarchy/`; read it for reference only.
- The plugin must pass `omarchy plugin validate`: no symlinks, relative entry
  points, id outside the reserved `omarchy.*` namespace.

## Workflow

- `scripts/check.sh` — unit tests, manifest validation and `qmllint` (CI runs
  the first two; qmllint needs a local Omarchy install).
- `scripts/dev-install.sh [--enable]` — copy into
  `~/.config/omarchy/plugins/monitor-layout/` and restart the shell.
  A restart is required: plugin hot-reload can serve stale QML.
- Shell log: `/run/user/$UID/quickshell/by-id/*/log.log`.

## Hyprland facts this plugin relies on

- The Lua config parser rejects `hyprctl keyword`; use `hyprctl eval '<lua>'`.
- `hl.monitor({ output = ..., position = ... })` without other fields merges
  into the existing rule: mode and scale are kept.
- `hyprctl reload` re-applies positions from `monitors.lua`; the service
  listens for `configreloaded` and restores the saved layout.

## Publishing

- Listed through the Omarchy plugin marketplace
  (https://plugins.omarchy.org/publish.html): an issue in
  `omacom/omarchy-plugin-marketplace`. Its requirements: `manifest.json`,
  README (Install/Usage/Configure/Remove, dependencies), LICENSE and an
  optional `preview.png`, all in the repository root.
- The marketplace runs a static security scan: never add install scripts,
  `sudo`/`pkexec`, `systemctl`, binaries or `curl | sh`.
- The plugin id `monitor-layout` is permanent once listed.
