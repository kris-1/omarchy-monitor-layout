// Pure layout logic shared by Service.qml, Panel.qml and the Node tests.
//
// A layout is a left-to-right order of monitor keys. A key is the monitor's
// description (make, model and serial, stable across ports) or, when that is
// empty, its output name. Monitors are placed in a single top-aligned row with
// no gaps, using their logical (post-scale, post-rotation) widths.

var INTERNAL_OUTPUT = /^(eDP|LVDS|DSI)-/

function monitorKey(monitor) {
  var description = String((monitor && monitor.description) || "").trim()
  return description !== "" ? description : String((monitor && monitor.name) || "")
}

function isInternal(monitor) {
  return INTERNAL_OUTPUT.test(String((monitor && monitor.name) || ""))
}

// Disabled and mirrored outputs take no space in the layout.
function isArrangeable(monitor) {
  if (!monitor || monitor.disabled) return false
  var mirrorOf = monitor.mirrorOf
  return mirrorOf === undefined || mirrorOf === null || mirrorOf === "" || mirrorOf === "none"
}

function logicalSize(monitor) {
  var scale = Number(monitor.scale) > 0 ? Number(monitor.scale) : 1
  // Transforms 1/3/5/7 rotate by 90° or 270°: swap the axes.
  var rotated = (Number(monitor.transform) || 0) % 2 === 1
  var width = Number(rotated ? monitor.height : monitor.width) || 0
  var height = Number(rotated ? monitor.width : monitor.height) || 0
  return { w: Math.round(width / scale), h: Math.round(height / scale) }
}

// "AOC U34V5C WQVP7HA000383" -> "AOC U34V5C": make and model, no serial.
function tileLabel(monitor) {
  if (isInternal(monitor)) return "Built-in"
  var words = String(monitor.description || "").trim().split(/\s+/).filter(function(word) {
    return word !== ""
  })
  return words.length ? words.slice(0, 2).join(" ") : String(monitor.name || "")
}

function parseOrder(text) {
  var data = null
  try {
    data = JSON.parse(String(text || ""))
  } catch (e) {
    return []
  }
  var order = data && Array.isArray(data.order) ? data.order : []
  return order.filter(function(key) { return typeof key === "string" && key !== "" })
}

function serializeOrder(order) {
  return JSON.stringify({ order: order }, null, 2) + "\n"
}

// Keys placed by the user come first; remembered monitors that are not
// connected right now keep their relative order after them.
function mergeOrder(keys, previous) {
  var merged = keys.slice()
  for (var i = 0; i < (previous || []).length; i++) {
    if (merged.indexOf(previous[i]) === -1) merged.push(previous[i])
  }
  return merged
}

function rank(order, monitor) {
  var index = order.indexOf(monitorKey(monitor))
  if (index === -1) index = order.indexOf(String(monitor.name || ""))
  return index
}

// Monitors in the saved order come first, in that order. Unknown ones follow,
// keeping their current left-to-right position.
function sortMonitors(monitors, order) {
  var list = (monitors || []).filter(isArrangeable).slice()
  order = order || []
  list.sort(function(a, b) {
    var ra = rank(order, a)
    var rb = rank(order, b)
    if (ra !== -1 && rb !== -1) return ra - rb
    if (ra !== -1 || rb !== -1) return ra !== -1 ? -1 : 1
    var dx = (Number(a.x) || 0) - (Number(b.x) || 0)
    if (dx !== 0) return dx
    return String(a.name) < String(b.name) ? -1 : 1
  })
  return list
}

// [{ name, x, y, changed }] for every arrangeable monitor, left to right.
function computePositions(monitors, order) {
  var sorted = sortMonitors(monitors, order)
  var x = 0
  var result = []
  for (var i = 0; i < sorted.length; i++) {
    var monitor = sorted[i]
    result.push({
      name: String(monitor.name),
      x: x,
      y: 0,
      changed: (Number(monitor.x) || 0) !== x || (Number(monitor.y) || 0) !== 0
    })
    x += logicalSize(monitor).w
  }
  return result
}

function luaString(value) {
  return "\"" + String(value).replace(/\\/g, "\\\\").replace(/"/g, "\\\"").replace(/\n/g, "\\n") + "\""
}

// First free x to the right of every monitor, both where they are now and
// where they are going. Staging monitors there keeps the move overlap-free.
function stagingX(monitors, positions) {
  var right = 0
  var list = (monitors || []).filter(isArrangeable)
  for (var i = 0; i < list.length; i++)
    right = Math.max(right, (Number(list[i].x) || 0) + logicalSize(list[i]).w)
  var total = 0
  for (var j = 0; j < list.length; j++) total += logicalSize(list[j]).w
  return Math.max(right, total)
}

function positionRule(name, x, y) {
  return "hl.monitor({ output = " + luaString(name) + ", position = \"" + x + "x" + y + "\" })"
}

// Position-only rules: Hyprland merges them into each monitor's existing rule,
// so mode, scale and the rest of the user's config stay untouched.
//
// Hyprland re-arranges after every rule, so moving monitors one by one straight
// to their targets can briefly stack two of them (swapping A|B: A moves onto
// B's spot while B is still there), which triggers Hyprland's "monitor layout
// overlaps" warning. With `staging`, every monitor first moves past the right
// edge of both layouts, then into place, so no intermediate state overlaps.
function positionsToLua(positions, staging) {
  var lines = []
  if (staging !== undefined && staging !== null) {
    for (var i = 0; i < positions.length; i++)
      lines.push(positionRule(positions[i].name, staging + positions[i].x, 0))
  }
  for (var j = 0; j < positions.length; j++)
    lines.push(positionRule(positions[j].name, positions[j].x, positions[j].y))
  return lines.join("\n")
}

function moveItem(list, from, to) {
  var copy = list.slice()
  if (from < 0 || from >= copy.length || to < 0 || to >= copy.length || from === to) return copy
  var moved = copy.splice(from, 1)[0]
  copy.splice(to, 0, moved)
  return copy
}

// Where a dragged tile lands: after every other tile whose center its leading
// edge has crossed. Comparing centers instead fails for mismatched sizes, since
// a wide tile's center cannot get past a narrow neighbour's inside the preview.
// tiles: [{ left, width }] at rest; offset: horizontal drag distance.
function dropIndex(tiles, from, offset) {
  if (!tiles || from < 0 || from >= tiles.length || !offset) return from
  var left = tiles[from].left + offset
  var edge = offset < 0 ? left : left + tiles[from].width
  var to = 0
  for (var i = 0; i < tiles.length; i++) {
    if (i === from) continue
    if (tiles[i].left + tiles[i].width / 2 < edge) to++
  }
  return to
}

// View model for the panel: arrangeable monitors sorted by current position.
function tilesFromMonitors(monitors) {
  var list = (monitors || []).filter(isArrangeable).map(function(monitor) {
    var size = logicalSize(monitor)
    return {
      name: String(monitor.name),
      key: monitorKey(monitor),
      label: tileLabel(monitor),
      internal: isInternal(monitor),
      focused: monitor.focused === true,
      x: Number(monitor.x) || 0,
      w: size.w,
      h: size.h
    }
  })
  list.sort(function(a, b) { return a.x - b.x })
  return list
}

if (typeof module !== "undefined") {
  module.exports = {
    monitorKey: monitorKey,
    isInternal: isInternal,
    isArrangeable: isArrangeable,
    logicalSize: logicalSize,
    tileLabel: tileLabel,
    parseOrder: parseOrder,
    serializeOrder: serializeOrder,
    mergeOrder: mergeOrder,
    sortMonitors: sortMonitors,
    computePositions: computePositions,
    stagingX: stagingX,
    positionsToLua: positionsToLua,
    moveItem: moveItem,
    dropIndex: dropIndex,
    tilesFromMonitors: tilesFromMonitors
  }
}
