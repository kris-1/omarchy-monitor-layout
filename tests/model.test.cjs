// Display toggle helpers backported from omacom/omarchy#7036; the assertions
// follow that PR's test/shell.d/monitor-test.sh.
const test = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../Model.js")

test("displayToggleSpec uses hl.monitor through the Lua config API", () => {
  assert.equal(
    Model.displayToggleSpec("DP-1", false),
    'hl.monitor({ output = "DP-1", disabled = false, mode = "preferred", position = "auto", scale = "auto" })'
  )
  assert.equal(Model.displayToggleSpec("DP-1", true), 'hl.monitor({ output = "DP-1", disabled = true })')
  assert.equal(Model.displayToggleSpec("", false), "")
})

test("displayToggleCommand routes the built-in panel through its own command", () => {
  assert.deepEqual(Model.displayToggleCommand("DP-2", true, "eDP-1"),
    ["hyprctl", "eval", 'hl.monitor({ output = "DP-2", disabled = true })'])
  assert.deepEqual(Model.displayToggleCommand("eDP-1", true, "eDP-1"), ["omarchy-hyprland-monitor-internal", "off"])
  assert.deepEqual(Model.displayToggleCommand("eDP-1", false, "eDP-1"), ["omarchy-hyprland-monitor-internal", "on"])
  assert.deepEqual(Model.displayToggleCommand("LVDS-1", true, "LVDS-1"), ["omarchy-hyprland-monitor-internal", "off"])
  assert.deepEqual(Model.displayToggleCommand("DP-2", true, ""),
    ["hyprctl", "eval", 'hl.monitor({ output = "DP-2", disabled = true })'])
  assert.equal(Model.displayToggleCommand("", true, "eDP-1"), null)
})

test("quoteLua escapes a display name", () => {
  assert.equal(Model.quoteLua('DP"1'), '"DP\\"1"')
  assert.equal(Model.quoteLua('a\\b'), '"a\\\\b"')
  assert.equal(Model.quoteLua('eDP-1", disabled = false })os.execute("x")--'),
    '"eDP-1\\", disabled = false })os.execute(\\"x\\")--"')
})
