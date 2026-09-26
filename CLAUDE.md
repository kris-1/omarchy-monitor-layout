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
- Scope: Omarchy's Display widget plus monitor positioning and the
  per-display properties window (mode, scale, rotation, VRR), nothing else.
  `Panel.qml` and `Model.js` are copies of Omarchy's
  `shell/plugins/panels/monitor/` (see NOTICE). Keep their diff against
  upstream limited to the `arrangement` wiring so upstream changes can be
  merged; put new UI in `Arrangement.qml` (and the windows it opens,
  `MonitorProperties.qml`, `KeepSettingsDialog.qml`, `IdentifyOverlay.qml`).
- `omarchy.clonedFrom: omarchy.monitor` stays in the manifest on purpose (it
  makes the plugin replace the built-in Display widget and receive its
  shortcut), although the marketplace guide suggests removing it for plugins
  that merely started as clones.
- The long-term goal is an upstream merge of `Arrangement.qml` into Omarchy's
  Display widget. Keep it self-contained, with `bar`, `active`, `focused`,
  `cursorActive`, `panel`, `moveCursor()`, `activate()`, `showProperties()`,
  `identify()`, `forgetSetting()` and `focusRequested` as its API.
- Never edit `/usr/share/omarchy/`; read it for reference only.
- The plugin must pass `omarchy plugin validate`: no symlinks, relative entry
  points, id outside the reserved `omarchy.*` namespace.

## Workflow

- `scripts/check.sh` — unit tests, manifest validation and `qmllint` (CI runs
  the first two; qmllint needs a local Omarchy install).
- `scripts/dev-sync.sh [--enable|--service-only]` — copy into
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
- The marketplace runs a static security scan (see its SECURITY.md) that
  flags privilege escalation, system service management, bundled binaries,
  installers and piping downloads into a shell, even when only mentioned in
  docs. Keep the plugin free of all of them and avoid naming those commands.
- The plugin id `monitor-layout` is permanent once listed.
