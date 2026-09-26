// Run with: node --test tests/
const test = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../LayoutModel.js")

const laptop = {
  name: "eDP-1",
  description: "Lenovo Group Limited 0x8AB1",
  width: 3072, height: 1920, scale: 2, transform: 0,
  x: 0, y: 0, focused: true, disabled: false, mirrorOf: "none"
}
const ultrawide = {
  name: "HDMI-A-1",
  description: "AOC U34V5C XYZ1234567890",
  width: 3440, height: 1440, scale: 1, transform: 0,
  x: 1536, y: 0, focused: false, disabled: false, mirrorOf: "none"
}
const portrait = {
  name: "DP-2",
  description: "Dell Inc. DELL P2419H ABC123",
  width: 1920, height: 1080, scale: 1, transform: 1,
  x: 4976, y: 0, focused: false, disabled: false, mirrorOf: "none"
}

test("monitorKey prefers the description and falls back to the output name", () => {
  assert.equal(Model.monitorKey(laptop), "Lenovo Group Limited 0x8AB1")
  assert.equal(Model.monitorKey({ name: "HDMI-A-2", description: "  " }), "HDMI-A-2")
})

test("logicalSize applies scale and rotation", () => {
  assert.deepEqual(Model.logicalSize(laptop), { w: 1536, h: 960 })
  assert.deepEqual(Model.logicalSize(portrait), { w: 1080, h: 1920 })
})

test("disabled and mirrored monitors are not arranged", () => {
  assert.equal(Model.isArrangeable({ ...ultrawide, disabled: true }), false)
  assert.equal(Model.isArrangeable({ ...ultrawide, mirrorOf: "eDP-1" }), false)
  assert.equal(Model.isArrangeable(ultrawide), true)
})

test("tileLabel names the built-in panel and shows the model", () => {
  assert.equal(Model.tileLabel(laptop), "Built-in")
  assert.equal(Model.tileLabel({ ...ultrawide, model: "U34V5C" }), "U34V5C")
  assert.equal(Model.tileLabel(ultrawide), "AOC U34V5C")
  assert.equal(Model.tileLabel({ name: "DP-3", description: "" }), "DP-3")
})

// Desktop: two identical monitors, no built-in panel.
const dell = (name, x, serial) => ({
  name,
  description: serial ? "Dell Inc. DELL P2419H " + serial : "Dell Inc. DELL P2419H",
  make: "Dell Inc.", model: "DELL P2419H", serial: serial || "",
  width: 1920, height: 1080, scale: 1, transform: 0,
  x, y: 0, focused: false, disabled: false, mirrorOf: "none"
})

test("desktop: identical models get distinct labels and keys", () => {
  const tiles = Model.tilesFromMonitors([dell("DP-1", 0, "S1"), dell("DP-2", 1920, "S2")])
  assert.deepEqual(tiles.map(t => t.label), ["DELL P2419H · DP-1", "DELL P2419H · DP-2"])
  assert.deepEqual(tiles.map(t => t.key), ["Dell Inc. DELL P2419H S1", "Dell Inc. DELL P2419H S2"])
  assert.ok(tiles.every(t => !t.internal))
})

test("desktop: identical monitors without serials are keyed by port", () => {
  const a = dell("DP-1", 0), b = dell("DP-2", 1920)
  const tiles = Model.tilesFromMonitors([a, b])
  assert.deepEqual(tiles.map(t => t.key), ["DP-1", "DP-2"])
  const positions = Model.computePositions([a, b], ["DP-2", "DP-1"])
  assert.deepEqual(positions.map(p => [p.name, p.x]), [["DP-2", 0], ["DP-1", 1920]])
})

test("desktop: three monitors reorder from the saved order", () => {
  const monitors = [dell("DP-1", 0, "S1"), dell("DP-2", 1920, "S2"), { ...ultrawide, x: 3840 }]
  const order = [Model.monitorKey(ultrawide), "Dell Inc. DELL P2419H S2", "Dell Inc. DELL P2419H S1"]
  const positions = Model.computePositions(monitors, order)
  assert.deepEqual(positions.map(p => [p.name, p.x]), [["HDMI-A-1", 0], ["DP-2", 3440], ["DP-1", 5360]])
})

test("parseOrder tolerates missing or malformed files", () => {
  assert.deepEqual(Model.parseOrder(""), [])
  assert.deepEqual(Model.parseOrder("not json"), [])
  assert.deepEqual(Model.parseOrder('{"order": ["a", 3, "", "b"]}'), ["a", "b"])
  assert.deepEqual(Model.parseOrder(Model.serializeOrder(["x", "y"])), ["x", "y"])
})

test("mergeOrder keeps remembered monitors that are unplugged", () => {
  assert.deepEqual(Model.mergeOrder(["b", "a"], ["a", "c", "b"]), ["b", "a", "c"])
})

test("computePositions follows the saved order", () => {
  const order = [Model.monitorKey(ultrawide), Model.monitorKey(laptop)]
  const positions = Model.computePositions([laptop, ultrawide], order)
  assert.deepEqual(positions.map(p => [p.name, p.x, p.y]), [["HDMI-A-1", 0, 0], ["eDP-1", 3440, 0]])
  assert.ok(positions.every(p => p.changed))
})

test("computePositions reports nothing changed when the layout already matches", () => {
  const order = [Model.monitorKey(laptop), Model.monitorKey(ultrawide)]
  const positions = Model.computePositions([ultrawide, laptop], order)
  assert.deepEqual(positions.map(p => [p.name, p.x]), [["eDP-1", 0], ["HDMI-A-1", 1536]])
  assert.ok(positions.every(p => !p.changed))
})

test("unknown monitors go to the right, keeping their current order", () => {
  const order = [Model.monitorKey(ultrawide)]
  const positions = Model.computePositions([portrait, laptop, ultrawide], order)
  assert.deepEqual(positions.map(p => p.name), ["HDMI-A-1", "eDP-1", "DP-2"])
  assert.deepEqual(positions.map(p => p.x), [0, 3440, 4976])
})

test("computePositions accepts output names in the order file", () => {
  const positions = Model.computePositions([laptop, ultrawide], ["HDMI-A-1", "eDP-1"])
  assert.deepEqual(positions.map(p => p.name), ["HDMI-A-1", "eDP-1"])
})

test("computePositions skips mirrored monitors", () => {
  const mirror = { ...portrait, mirrorOf: "eDP-1" }
  const positions = Model.computePositions([laptop, ultrawide, mirror], [])
  assert.deepEqual(positions.map(p => p.name), ["eDP-1", "HDMI-A-1"])
})

test("positionsToLua emits position-only monitor rules", () => {
  const lua = Model.positionsToLua([{ name: "eDP-1", x: 0, y: 0 }, { name: "HDMI-A-1", x: 1536, y: 0 }])
  assert.equal(lua,
    'hl.monitor({ output = "eDP-1", position = "0x0" })\n' +
    'hl.monitor({ output = "HDMI-A-1", position = "1536x0" })')
})

test("positionsToLua stages monitors before moving them into place", () => {
  const positions = [{ name: "HDMI-A-1", x: 0, y: 0 }, { name: "eDP-1", x: 3440, y: 0 }]
  const lines = Model.positionsToLua(positions, 4976).split("\n")
  assert.deepEqual(lines, [
    'hl.monitor({ output = "HDMI-A-1", position = "4976x0" })',
    'hl.monitor({ output = "eDP-1", position = "8416x0" })',
    'hl.monitor({ output = "HDMI-A-1", position = "0x0" })',
    'hl.monitor({ output = "eDP-1", position = "3440x0" })'
  ])
})

test("staged moves never overlap, whichever way the monitors swap", () => {
  const overlaps = (rects) => rects.some((a, i) => rects.some((b, j) =>
    i < j && a.x < b.x + b.w && b.x < a.x + a.w))
  for (const order of [["HDMI-A-1", "eDP-1"], ["eDP-1", "HDMI-A-1"]]) {
    for (const start of [[laptop, ultrawide], [{ ...laptop, x: 3440 }, { ...ultrawide, x: 0 }]]) {
      const positions = Model.computePositions(start, order)
      const staging = Model.stagingX(start, positions)
      const state = Object.fromEntries(start.map(m => [m.name, { x: m.x, w: Model.logicalSize(m).w }]))
      for (const line of Model.positionsToLua(positions, staging).split("\n")) {
        const [, name, x] = line.match(/output = "([^"]+)", position = "(-?\d+)x/)
        state[name].x = Number(x)
        assert.equal(overlaps(Object.values(state)), false, line)
      }
    }
  }
})

test("positionsToLua parks unplugged outputs beside the layout", () => {
  const positions = [{ name: "eDP-1", x: 0, y: 0 }]
  const parked = Model.parkedOutputs(["HDMI-A-1", "eDP-1"], positions)
  assert.deepEqual(parked, ["HDMI-A-1"])
  assert.equal(Model.positionsToLua(positions, null, parked),
    'hl.monitor({ output = "eDP-1", position = "0x0" })\n' +
    'hl.monitor({ output = "HDMI-A-1", position = "auto-right" })')
})

test("positionsToLua escapes quotes in output names", () => {
  assert.match(Model.positionsToLua([{ name: 'a"b', x: 0, y: 0 }]), /output = "a\\"b"/)
})

test("moveItem moves without mutating and ignores invalid moves", () => {
  const list = ["a", "b", "c"]
  assert.deepEqual(Model.moveItem(list, 0, 2), ["b", "c", "a"])
  assert.deepEqual(Model.moveItem(list, 2, 0), ["c", "a", "b"])
  assert.deepEqual(Model.moveItem(list, 1, 5), list)
  assert.deepEqual(list, ["a", "b", "c"])
})

test("dropIndex lets a wide tile pass a narrow one", () => {
  // Built-in (narrow) on the left, ultrawide on the right, as in the preview.
  const tiles = [{ left: 0, width: 100 }, { left: 106, width: 224 }]
  // The ultrawide's center can never reach the left of the narrow tile's
  // center inside the preview, but its left edge can.
  assert.equal(Model.dropIndex(tiles, 1, -60), 0)
  assert.equal(Model.dropIndex(tiles, 1, -40), 1)
  assert.equal(Model.dropIndex(tiles, 0, 110), 0)
  assert.equal(Model.dropIndex(tiles, 0, 125), 1)
})

test("dropIndex handles three tiles and zero offset", () => {
  const tiles = [{ left: 0, width: 100 }, { left: 110, width: 100 }, { left: 220, width: 100 }]
  assert.equal(Model.dropIndex(tiles, 0, 0), 0)
  assert.equal(Model.dropIndex(tiles, 0, 120), 1)
  assert.equal(Model.dropIndex(tiles, 0, 230), 2)
  assert.equal(Model.dropIndex(tiles, 2, -230), 0)
})

test("cleanSettings keeps only valid fields and normalizes scale", () => {
  assert.deepEqual(Model.cleanSettings({ mode: "3440x1440@99.98", scale: 1.256, transform: 1, vrr: 1 }),
    { mode: "3440x1440@99.98", scale: 1.26, transform: 1, vrr: 1 })
  assert.deepEqual(Model.cleanSettings({ mode: "3440x1440@60" }), { mode: "3440x1440@60" })
})

test("cleanSettings drops invalid fields and garbage", () => {
  assert.deepEqual(Model.cleanSettings({ mode: "not a mode", scale: 0, transform: 8, vrr: 3 }), {})
  assert.deepEqual(Model.cleanSettings({ mode: "3440x1440@99.98Hz" }), {}) // saved format has no "Hz"
  assert.deepEqual(Model.cleanSettings({ scale: -1 }), {})
  assert.deepEqual(Model.cleanSettings({ scale: 11 }), {})
  assert.deepEqual(Model.cleanSettings({ scale: 10 }), { scale: 10 })
  assert.deepEqual(Model.cleanSettings({ transform: -1 }), {})
  assert.deepEqual(Model.cleanSettings({ transform: 1.5 }), {})
  assert.deepEqual(Model.cleanSettings(null), {})
  assert.deepEqual(Model.cleanSettings("garbage"), {})
  assert.deepEqual(Model.cleanSettings([1, 2, 3]), {})
})

test("parseLayout tolerates invalid JSON and drops invalid monitor fields", () => {
  assert.deepEqual(Model.parseLayout(""), { order: [], monitors: {} })
  assert.deepEqual(Model.parseLayout("not json"), { order: [], monitors: {} })
  assert.deepEqual(Model.parseLayout('{"order": ["a"], "monitors": "nope"}'), { order: ["a"], monitors: {} })
  const parsed = Model.parseLayout(JSON.stringify({
    order: ["a", "b"],
    monitors: {
      a: { mode: "3440x1440@99.98", scale: 5, garbage: true },
      b: { scale: -5 } // cleans to {} entirely
    }
  }))
  assert.deepEqual(parsed, { order: ["a", "b"], monitors: { a: { mode: "3440x1440@99.98", scale: 5 } } })
})

test("serializeOrder output is unchanged", () => {
  assert.equal(Model.serializeOrder(["x", "y"]), '{\n  "order": [\n    "x",\n    "y"\n  ]\n}\n')
  assert.equal(Model.parseOrder(Model.serializeOrder(["x", "y"])) && true, true)
})

test("serializeLayout omits monitors when empty and round-trips otherwise", () => {
  assert.equal(Model.serializeLayout({ order: ["a"], monitors: {} }), Model.serializeOrder(["a"]))
  const layout = { order: ["a"], monitors: { a: { scale: 1.25 } } }
  assert.deepEqual(Model.parseLayout(Model.serializeLayout(layout)), layout)
})

test("withMonitorSettings merges without mutating and removes null fields", () => {
  const layout = { order: ["a"], monitors: { a: { mode: "1920x1080@60", scale: 1.25 } } }
  const removed = Model.withMonitorSettings(layout, "a", { scale: null })
  assert.deepEqual(removed.monitors.a, { mode: "1920x1080@60" })
  assert.deepEqual(layout.monitors.a, { mode: "1920x1080@60", scale: 1.25 }) // original untouched

  const cleared = Model.withMonitorSettings(layout, "a", { mode: null, scale: null })
  assert.equal(cleared.monitors.a, undefined)

  const created = Model.withMonitorSettings({ order: [], monitors: {} }, "b", { transform: 1 })
  assert.deepEqual(created.monitors, { b: { transform: 1 } })
})

test("parseMode accepts the hyprctl and saved-settings mode spellings", () => {
  assert.deepEqual(Model.parseMode("3440x1440@99.98Hz"), { width: 3440, height: 1440, refresh: 99.98 })
  assert.deepEqual(Model.parseMode("3440x1440@99.98"), { width: 3440, height: 1440, refresh: 99.98 })
  assert.deepEqual(Model.parseMode("1920x1080"), { width: 1920, height: 1080, refresh: 0 })
  assert.equal(Model.parseMode("garbage"), null)
})

test("formatRefresh trims to at most 2 decimals", () => {
  assert.equal(Model.formatRefresh(60), "60")
  assert.equal(Model.formatRefresh(99.982), "99.98")
  assert.equal(Model.formatRefresh(59.94), "59.94")
})

test("modeString formats width, height and refresh", () => {
  assert.equal(Model.modeString(3440, 1440, 99.982), "3440x1440@99.98")
})

test("resolutionOptions dedupes and sorts by pixel count then width", () => {
  assert.deepEqual(Model.resolutionOptions(["3072x1920@60.00Hz", "3072x1920@120.00Hz"]), [
    { value: "3072x1920", label: "3072 × 1920", width: 3072, height: 1920 }
  ])
  const modes = [
    "1920x1080@60.00Hz", "1920x1080@144.00Hz",
    "3840x2160@60.00Hz",
    "2560x1440@165.00Hz"
  ]
  assert.deepEqual(Model.resolutionOptions(modes).map(o => o.value), ["3840x2160", "2560x1440", "1920x1080"])
})

test("refreshOptions dedupes by formatted value and sorts highest first", () => {
  const options = Model.refreshOptions(["3072x1920@60.00Hz", "3072x1920@120.00Hz"], 3072, 1920)
  assert.deepEqual(options, [
    { value: "120", label: "120 Hz" },
    { value: "60", label: "60 Hz" }
  ])
  assert.deepEqual(Model.refreshOptions(["1920x1080@60.00Hz"], 3072, 1920), [])
})

test("liveSettings reads a hyprctl monitor object", () => {
  assert.deepEqual(Model.liveSettings({ width: 3440, height: 1440, refreshRate: 99.982, scale: 1.25, transform: 1, vrr: true }),
    { mode: "3440x1440@99.98", scale: 1.25, transform: 1, vrr: 1 })
  assert.deepEqual(Model.liveSettings({ width: 1920, height: 1080, refreshRate: 60, scale: 1, transform: 0, vrr: false }),
    { mode: "1920x1080@60", scale: 1, transform: 0, vrr: 0 })
})

test("settingsMatch compares only the fields present in settings", () => {
  const monitor = { width: 3440, height: 1440, refreshRate: 99.98, scale: 1.25, transform: 0, vrr: true }
  assert.equal(Model.settingsMatch(monitor, { mode: "3440x1440@99.95" }), true) // within 0.05
  assert.equal(Model.settingsMatch(monitor, { mode: "3440x1440@99.90" }), false) // 0.08 off
  assert.equal(Model.settingsMatch(monitor, { mode: "1920x1080@99.98" }), false)
  assert.equal(Model.settingsMatch(monitor, { scale: 1.252 }), true)
  assert.equal(Model.settingsMatch(monitor, { scale: 1.3 }), false)
  assert.equal(Model.settingsMatch(monitor, { transform: 0 }), true)
  assert.equal(Model.settingsMatch(monitor, { transform: 1 }), false)
  assert.equal(Model.settingsMatch(monitor, {}), true)
  assert.equal(Model.settingsMatch(monitor, null), true)
})

test("settingsMatch treats vrr 2 (fullscreen-only) as always matching", () => {
  assert.equal(Model.settingsMatch({ vrr: true }, { vrr: 2 }), true)
  assert.equal(Model.settingsMatch({ vrr: false }, { vrr: 2 }), true)
  assert.equal(Model.settingsMatch({ vrr: true }, { vrr: 0 }), false)
  assert.equal(Model.settingsMatch({ vrr: false }, { vrr: 0 }), true)
  assert.equal(Model.settingsMatch({ vrr: true }, { vrr: 1 }), true)
  assert.equal(Model.settingsMatch({ vrr: false }, { vrr: 1 }), false)
})

test("settingsRule emits fields in a fixed order and escapes the output name", () => {
  assert.equal(Model.settingsRule("HDMI-A-1", { vrr: 1, mode: "3440x1440@99.98", transform: 1, scale: 1.25 }),
    'hl.monitor({ output = "HDMI-A-1", mode = "3440x1440@99.98", scale = 1.25, transform = 1, vrr = 1 })')
  assert.match(Model.settingsRule('a"b', { mode: "1920x1080@60" }), /output = "a\\"b"/)
  assert.equal(Model.settingsRule("HDMI-A-1", {}), "")
  assert.equal(Model.settingsRule("HDMI-A-1", null), "")
})

test("pendingSettings looks up identical monitors by output name and skips matches", () => {
  const a = dell("DP-1", 0) // scale 1, no serial: keyed by output name
  const b = dell("DP-2", 1920)
  const layout = { order: [], monitors: { "DP-1": { scale: 1.25 }, "DP-2": { scale: 1 } } }
  const pending = Model.pendingSettings([a, b], layout)
  assert.deepEqual(pending, [{ name: "DP-1", settings: { scale: 1.25 } }])
})

test("pendingSettings ignores disabled monitors and entries with no saved settings", () => {
  const a = { ...dell("DP-1", 0, "S1"), disabled: true }
  const layout = { order: [], monitors: { "Dell Inc. DELL P2419H S1": { scale: 1.25 } } }
  assert.deepEqual(Model.pendingSettings([a], layout), [])
  assert.deepEqual(Model.pendingSettings([dell("DP-1", 0, "S1")], { order: [], monitors: {} }), [])
})

test("settingsToLua joins rules with newlines", () => {
  const pending = [
    { name: "eDP-1", settings: { scale: 2 } },
    { name: "HDMI-A-1", settings: { mode: "3440x1440@99.98" } }
  ]
  assert.equal(Model.settingsToLua(pending),
    'hl.monitor({ output = "eDP-1", scale = 2 })\n' +
    'hl.monitor({ output = "HDMI-A-1", mode = "3440x1440@99.98" })')
})

test("diagonalInches and pixelDensity compute from physical size", () => {
  assert.equal(Model.diagonalInches(797, 333), 34)
  assert.equal(Model.diagonalInches(0, 333), 0)
  assert.equal(Model.diagonalInches(797, -1), 0)
  assert.equal(Model.pixelDensity(3440, 1440, 797, 333), 110)
  assert.equal(Model.pixelDensity(3440, 1440, 0, 0), 0)
})

test("rotationLabel names every transform value", () => {
  assert.equal(Model.rotationLabel(0), "Normal")
  assert.equal(Model.rotationLabel(1), "90°")
  assert.equal(Model.rotationLabel(4), "Flipped")
  assert.equal(Model.rotationLabel(7), "Flipped 270°")
  assert.equal(Model.rotationLabel(99), "Normal")
})

test("tilesFromMonitors sorts by position and exposes keys", () => {
  const tiles = Model.tilesFromMonitors([ultrawide, laptop])
  assert.deepEqual(tiles.map(t => [t.name, t.key, t.w]), [
    ["eDP-1", "Lenovo Group Limited 0x8AB1", 1536],
    ["HDMI-A-1", "AOC U34V5C XYZ1234567890", 3440]
  ])
  assert.equal(tiles[0].internal, true)
  assert.equal(tiles[0].focused, true)
})
