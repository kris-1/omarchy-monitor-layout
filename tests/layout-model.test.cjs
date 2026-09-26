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
  description: "AOC U34V5C WQVP7HA000383",
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

test("tileLabel names the built-in panel and trims the serial", () => {
  assert.equal(Model.tileLabel(laptop), "Built-in")
  assert.equal(Model.tileLabel(ultrawide), "AOC U34V5C")
  assert.equal(Model.tileLabel({ name: "DP-3", description: "" }), "DP-3")
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

test("tilesFromMonitors sorts by position and exposes keys", () => {
  const tiles = Model.tilesFromMonitors([ultrawide, laptop])
  assert.deepEqual(tiles.map(t => [t.name, t.key, t.w]), [
    ["eDP-1", "Lenovo Group Limited 0x8AB1", 1536],
    ["HDMI-A-1", "AOC U34V5C WQVP7HA000383", 3440]
  ])
  assert.equal(tiles[0].internal, true)
  assert.equal(tiles[0].focused, true)
})
