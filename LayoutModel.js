// Pure layout logic shared by Service.qml, Panel.qml and the Node tests.
//
// A layout is a left-to-right order of monitor keys. A key is the monitor's
// description (make, model and serial, stable across ports) or its output
// name when the description is empty or shared by another connected monitor
// (identical models that report no serial number). Monitors are placed in a single top-aligned row with
// no gaps, using their logical (post-scale, post-rotation) widths.

var INTERNAL_OUTPUT = /^(eDP|LVDS|DSI)-/

// Saved settings format: "3440x1440@99.98" (see modeString/parseMode).
var SETTINGS_MODE_RE = /^\d+x\d+@\d+(\.\d+)?$/

function description(monitor) {
  return String((monitor && monitor.description) || "").trim()
}

// Descriptions that more than one of `monitors` reports.
function sharedDescriptions(monitors) {
  var seen = {}
  var shared = {}
  for (var i = 0; i < (monitors || []).length; i++) {
    var d = description(monitors[i])
    if (d === "") continue
    if (seen[d]) shared[d] = true
    seen[d] = true
  }
  return shared
}

// `shared` (from sharedDescriptions) lists descriptions that cannot tell
// monitors apart; those monitors are keyed by output name instead.
function monitorKey(monitor, shared) {
  var d = description(monitor)
  if (d !== "" && !(shared && shared[d])) return d
  return String((monitor && monitor.name) || "")
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

// Short tile label: "Built-in" for the laptop panel, otherwise the model
// ("U34V5C", "DELL P2419H"), falling back to the description's first words
// and then to the output name.
function tileLabel(monitor) {
  if (isInternal(monitor)) return "Built-in"
  var model = String(monitor.model || "").trim()
  if (model !== "") return model
  var words = description(monitor).split(/\s+/).filter(function(word) { return word !== "" })
  return words.length ? words.slice(0, 2).join(" ") : String(monitor.name || "")
}

// Keeps only the fields of a per-monitor settings entry that are valid,
// normalizing scale to at most 2 decimals. Returns {} for garbage input.
function cleanSettings(obj) {
  var result = {}
  if (!obj || typeof obj !== "object") return result

  if (typeof obj.mode === "string" && SETTINGS_MODE_RE.test(obj.mode)) result.mode = obj.mode

  if (obj.scale !== undefined && obj.scale !== null) {
    var scale = Number(obj.scale)
    if (isFinite(scale) && scale > 0 && scale <= 10) result.scale = Math.round(scale * 100) / 100
  }

  if (obj.transform !== undefined && obj.transform !== null) {
    var transform = Number(obj.transform)
    if (Number.isInteger(transform) && transform >= 0 && transform <= 7) result.transform = transform
  }

  if (obj.vrr !== undefined && obj.vrr !== null) {
    var vrr = Number(obj.vrr)
    if (Number.isInteger(vrr) && vrr >= 0 && vrr <= 2) result.vrr = vrr
  }

  return result
}

// `text` holds `{ order: [...], monitors: { <key>: { mode, scale, transform, vrr } } }`.
// Tolerates missing fields and invalid JSON, and drops monitor entries that
// clean to nothing.
function parseLayout(text) {
  var data = null
  try {
    data = JSON.parse(String(text || ""))
  } catch (e) {
    data = null
  }

  var order = data && Array.isArray(data.order) ? data.order : []
  order = order.filter(function(key) { return typeof key === "string" && key !== "" })

  var monitors = {}
  var rawMonitors = data && data.monitors && typeof data.monitors === "object" ? data.monitors : {}
  for (var key in rawMonitors) {
    if (!Object.prototype.hasOwnProperty.call(rawMonitors, key)) continue
    var cleaned = cleanSettings(rawMonitors[key])
    if (Object.keys(cleaned).length > 0) monitors[key] = cleaned
  }

  return { order: order, monitors: monitors }
}

function parseOrder(text) {
  return parseLayout(text).order
}

// Omits `monitors` entirely when empty, so files saved before per-monitor
// settings existed stay byte-identical.
function serializeLayout(layout) {
  var order = (layout && layout.order) || []
  var monitors = (layout && layout.monitors) || {}
  var data = { order: order }
  if (Object.keys(monitors).length > 0) data.monitors = monitors
  return JSON.stringify(data, null, 2) + "\n"
}

function serializeOrder(order) {
  return serializeLayout({ order: order })
}

// New layout with `settings` merged into `layout.monitors[key]`, without
// mutating `layout`. A field set to `null` removes that field; an entry left
// empty is dropped entirely. The result is run through cleanSettings.
function withMonitorSettings(layout, key, settings) {
  var monitors = {}
  var sourceMonitors = (layout && layout.monitors) || {}
  for (var k in sourceMonitors) {
    if (Object.prototype.hasOwnProperty.call(sourceMonitors, k)) monitors[k] = sourceMonitors[k]
  }

  var merged = {}
  var existing = monitors[key] || {}
  for (var field in existing) {
    if (Object.prototype.hasOwnProperty.call(existing, field)) merged[field] = existing[field]
  }
  var changes = settings || {}
  for (var f in changes) {
    if (!Object.prototype.hasOwnProperty.call(changes, f)) continue
    if (changes[f] === null) delete merged[f]
    else merged[f] = changes[f]
  }

  var cleaned = cleanSettings(merged)
  if (Object.keys(cleaned).length > 0) monitors[key] = cleaned
  else delete monitors[key]

  return { order: ((layout && layout.order) || []).slice(), monitors: monitors }
}

// Parses "3440x1440@99.98Hz", "3440x1440@99.98" or "1920x1080" (refresh 0
// when absent). Returns null when `str` does not look like a mode.
function parseMode(str) {
  var match = /^(\d+)x(\d+)(?:@(\d+(?:\.\d+)?)(?:Hz)?)?$/i.exec(String(str || "").trim())
  if (!match) return null
  return {
    width: parseInt(match[1], 10),
    height: parseInt(match[2], 10),
    refresh: match[3] ? parseFloat(match[3]) : 0
  }
}

// At most 2 decimals, trailing zeros trimmed: 60 -> "60", 99.982 -> "99.98".
function formatRefresh(hz) {
  return String(Math.round(Number(hz) * 100) / 100)
}

function modeString(width, height, refresh) {
  return width + "x" + height + "@" + formatRefresh(refresh)
}

// Unique resolutions from hyprctl's available-modes strings ("3072x1920@120.00Hz"),
// sorted by pixel count desc, then width desc (widescreen before ultrawide-tall
// equivalents at the same pixel count).
function resolutionOptions(availableModes) {
  var seen = {}
  var list = []
  for (var i = 0; i < (availableModes || []).length; i++) {
    var parsed = parseMode(availableModes[i])
    if (!parsed) continue
    var value = parsed.width + "x" + parsed.height
    if (seen[value]) continue
    seen[value] = true
    list.push({ value: value, label: parsed.width + " × " + parsed.height, width: parsed.width, height: parsed.height })
  }
  list.sort(function(a, b) {
    var pixelsA = a.width * a.height
    var pixelsB = b.width * b.height
    if (pixelsA !== pixelsB) return pixelsB - pixelsA
    return b.width - a.width
  })
  return list
}

// Refresh rates available for one resolution, deduped by their formatted
// value and sorted highest first.
function refreshOptions(availableModes, width, height) {
  var seen = {}
  var list = []
  for (var i = 0; i < (availableModes || []).length; i++) {
    var parsed = parseMode(availableModes[i])
    if (!parsed || parsed.width !== width || parsed.height !== height) continue
    var value = formatRefresh(parsed.refresh)
    if (seen[value]) continue
    seen[value] = true
    list.push({ value: value, label: value + " Hz" })
  }
  list.sort(function(a, b) { return Number(b.value) - Number(a.value) })
  return list
}

// Current settings of a hyprctl monitor JSON object, in the saved-settings shape.
function liveSettings(monitor) {
  var scale = Number(monitor.scale) > 0 ? Number(monitor.scale) : 1
  return {
    mode: modeString(Number(monitor.width) || 0, Number(monitor.height) || 0, Number(monitor.refreshRate) || 0),
    scale: Math.round(scale * 100) / 100,
    transform: Number(monitor.transform) || 0,
    vrr: monitor.vrr ? 1 : 0
  }
}

// True when every field present in `settings` already holds on the live
// `monitor` (a hyprctl monitor JSON object), so re-applying it would be a
// no-op. vrr 2 (fullscreen-only) always matches: hyprctl's JSON cannot tell
// that state apart from off, and treating it as a mismatch would re-apply
// the rule forever.
function settingsMatch(monitor, settings) {
  if (!settings) return true

  if (settings.mode !== undefined) {
    var parsed = parseMode(settings.mode)
    if (!parsed) return false
    if ((Number(monitor.width) || 0) !== parsed.width) return false
    if ((Number(monitor.height) || 0) !== parsed.height) return false
    if (Math.abs((Number(monitor.refreshRate) || 0) - parsed.refresh) >= 0.05) return false
  }

  if (settings.scale !== undefined) {
    if (Math.abs((Number(monitor.scale) || 0) - Number(settings.scale)) >= 0.005) return false
  }

  if (settings.transform !== undefined) {
    if ((Number(monitor.transform) || 0) !== Number(settings.transform)) return false
  }

  if (settings.vrr !== undefined) {
    if (settings.vrr === 0 && monitor.vrr) return false
    if (settings.vrr === 1 && monitor.vrr !== true) return false
    // vrr === 2: always matches.
  }

  return true
}

// hl.monitor({ output = ..., mode = ..., scale = ..., transform = ..., vrr = ... })
// with only the fields present in `settings`, in that fixed order. "" when
// `settings` has none.
function settingsRule(name, settings) {
  settings = settings || {}
  var parts = ["output = " + luaString(name)]
  if (settings.mode !== undefined) parts.push("mode = " + luaString(settings.mode))
  if (settings.scale !== undefined) parts.push("scale = " + settings.scale)
  if (settings.transform !== undefined) parts.push("transform = " + settings.transform)
  if (settings.vrr !== undefined) parts.push("vrr = " + settings.vrr)
  if (parts.length === 1) return ""
  return "hl.monitor({ " + parts.join(", ") + " })"
}

// [{ name, settings }] for connected, non-disabled monitors that have a saved
// settings entry and whose live settings do not already match it. Looked up
// the same way rank() looks up a saved order entry: by monitorKey first,
// falling back to the output name.
function pendingSettings(monitors, layout) {
  var list = (monitors || []).filter(function(monitor) { return monitor && !monitor.disabled })
  var shared = sharedDescriptions(list)
  var monitorSettings = (layout && layout.monitors) || {}
  var result = []
  for (var i = 0; i < list.length; i++) {
    var monitor = list[i]
    var settings = monitorSettings[monitorKey(monitor, shared)]
    if (!settings) settings = monitorSettings[String(monitor.name || "")]
    if (!settings) continue
    if (settingsMatch(monitor, settings)) continue
    result.push({ name: String(monitor.name), settings: settings })
  }
  return result
}

function settingsToLua(pending) {
  return (pending || []).map(function(p) { return settingsRule(p.name, p.settings) }).join("\n")
}

// Screen diagonal in inches, rounded to 1 decimal. 0 when the physical size
// is missing or non-positive (common for VMs and some projectors).
function diagonalInches(physicalWidthMm, physicalHeightMm) {
  var w = Number(physicalWidthMm)
  var h = Number(physicalHeightMm)
  if (!isFinite(w) || !isFinite(h) || w <= 0 || h <= 0) return 0
  var diagonalMm = Math.sqrt(w * w + h * h)
  return Math.round((diagonalMm / 25.4) * 10) / 10
}

// Pixels per inch, rounded to the nearest integer. 0 when unknown.
function pixelDensity(width, height, physicalWidthMm, physicalHeightMm) {
  var diagonal = diagonalInches(physicalWidthMm, physicalHeightMm)
  var w = Number(width)
  var h = Number(height)
  if (diagonal <= 0 || !isFinite(w) || !isFinite(h) || w <= 0 || h <= 0) return 0
  return Math.round(Math.sqrt(w * w + h * h) / diagonal)
}

var ROTATION_LABELS = [
  "Normal", "90°", "180°", "270°",
  "Flipped", "Flipped 90°", "Flipped 180°", "Flipped 270°"
]

function rotationLabel(transform) {
  return ROTATION_LABELS[Number(transform)] || ROTATION_LABELS[0]
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

function rank(order, monitor, shared) {
  var index = order.indexOf(monitorKey(monitor, shared))
  if (index === -1) index = order.indexOf(String(monitor.name || ""))
  return index
}

// Monitors in the saved order come first, in that order. Unknown ones follow,
// keeping their current left-to-right position.
function sortMonitors(monitors, order) {
  var list = (monitors || []).filter(isArrangeable).slice()
  var shared = sharedDescriptions(list)
  order = order || []
  list.sort(function(a, b) {
    var ra = rank(order, a, shared)
    var rb = rank(order, b, shared)
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
//
// `parked` lists outputs that were positioned before but are unplugged now.
// Hyprland keeps their last rule, so a monitor plugged back in would land on
// its old spot, which the compacted layout may now occupy, and trigger the same
// warning before the service can move it. Parking them at "auto-right" makes a
// returning monitor appear beside the layout instead.
function positionsToLua(positions, staging, parked) {
  var lines = []
  if (staging !== undefined && staging !== null) {
    for (var i = 0; i < positions.length; i++)
      lines.push(positionRule(positions[i].name, staging + positions[i].x, 0))
  }
  for (var j = 0; j < positions.length; j++)
    lines.push(positionRule(positions[j].name, positions[j].x, positions[j].y))
  for (var k = 0; k < (parked || []).length; k++)
    lines.push("hl.monitor({ output = " + luaString(parked[k]) + ", position = \"auto-right\" })")
  return lines.join("\n")
}

// Outputs from `known` that are not placed by `positions`, i.e. unplugged.
function parkedOutputs(known, positions) {
  var placed = {}
  for (var i = 0; i < positions.length; i++) placed[positions[i].name] = true
  return (known || []).filter(function(name) { return !placed[name] })
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
  var arrangeable = (monitors || []).filter(isArrangeable)
  var shared = sharedDescriptions(arrangeable)
  var labelCount = {}
  arrangeable.forEach(function(monitor) {
    var label = tileLabel(monitor)
    labelCount[label] = (labelCount[label] || 0) + 1
  })
  var list = arrangeable.map(function(monitor) {
    var size = logicalSize(monitor)
    var label = tileLabel(monitor)
    return {
      name: String(monitor.name),
      key: monitorKey(monitor, shared),
      // Identical models get their port appended: "P2419H · DP-1".
      label: labelCount[label] > 1 ? label + " · " + monitor.name : label,
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
    sharedDescriptions: sharedDescriptions,
    isInternal: isInternal,
    isArrangeable: isArrangeable,
    logicalSize: logicalSize,
    tileLabel: tileLabel,
    cleanSettings: cleanSettings,
    parseLayout: parseLayout,
    parseOrder: parseOrder,
    serializeLayout: serializeLayout,
    serializeOrder: serializeOrder,
    withMonitorSettings: withMonitorSettings,
    parseMode: parseMode,
    formatRefresh: formatRefresh,
    modeString: modeString,
    resolutionOptions: resolutionOptions,
    refreshOptions: refreshOptions,
    liveSettings: liveSettings,
    settingsMatch: settingsMatch,
    settingsRule: settingsRule,
    pendingSettings: pendingSettings,
    settingsToLua: settingsToLua,
    diagonalInches: diagonalInches,
    pixelDensity: pixelDensity,
    rotationLabel: rotationLabel,
    mergeOrder: mergeOrder,
    sortMonitors: sortMonitors,
    computePositions: computePositions,
    stagingX: stagingX,
    positionsToLua: positionsToLua,
    parkedOutputs: parkedOutputs,
    moveItem: moveItem,
    dropIndex: dropIndex,
    tilesFromMonitors: tilesFromMonitors
  }
}
