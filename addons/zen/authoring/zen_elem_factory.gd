@tool
class_name ZenElemFactory
extends RefCounted
##
## Builds Zen elements and canvases from plain element/document Dictionaries:
## the scene editor's "add element" and "new scene".
##
## Track props are the per-kind lists in ZenProps.
##

const CRUMBLE_DEFAULTS := {"crumble_spin": 90.0, "crumble_dir": 90.0,
    "crumble_spread": 12.0, "crumble_dist": 0.5}


## A new element's defaults (AnimElemInit, anim.c:107) - what the scene
## editor's "add element" starts from.
static func new_elem(kind: String, name: String) -> Dictionary:
    return {
        "kind": kind, "name": name, "text": "",
        "color": Color8(245, 245, 245, 255),
        "bg_color": Color(0, 0, 0, 0),
        "outline_color": Color8(245, 245, 245, 255),
        "outline": 0.0,
        "pos": Vector2(0.5, 0.5), "size": Vector2(0.2, 0.2),
        "scale": 1.0, "rot": 0.0,
        "shape": "rect", "shape_name": "",
        "unit_abs": false, "corner_mode": false, "outline_crisp": false,
        "crumble_fx": CRUMBLE_DEFAULTS.duplicate(),
        "tracks": {},
    }


## A canvas holding `doc`'s elements and signals, its keys installed.
static func build(doc: Dictionary) -> ZenCanvas:
    var canvas := ZenCanvas.new()
    canvas.set_script(load("res://addons/zen/runtime/zen_canvas.gd"))
    canvas.name = node_name(String(doc["name"]))
    canvas.design_size = Vector2(320, 180)
    canvas.duration = float(doc["duration"])
    canvas.intro_end = float(doc["intro_end"])
    canvas.outro_start = float(doc["outro_start"])
    canvas.loop_blend = float(doc["loop_blend"])
    canvas.loop_smooth = bool(doc["loop_smooth"])
    # Ascending in t: next_pause() short-circuits on the first hit and so needs
    # the earliest marker first (anim.h:536).
    var marks: Array = (doc["pauses"] as Array).duplicate()
    marks.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))
    canvas.pauses = marks
    canvas.loop_play = bool(doc["loop_smooth"]) or float(doc["intro_end"]) > 0.0
    # A document carries no backdrop of its own unless it has a `global`
    # element; the preview grey keeps an exported clip from being pure black.
    canvas.clear_color = Color(0.1, 0.12, 0.16, 1.0)

    var pool := ZenStrings.new()
    for e in doc["elems"]:
        var kind := String(e["kind"])
        # A global element is TWO rects at different depths: its background half
        # is drawn before every element, its fade half at its own index.
        if kind == "global":
            var bg := build_global(e, true)
            canvas.add_child(bg)
            bg.owner = canvas
            bg.z_index = -1                     # behind every element
        var node: Node2D = build_text(e, pool) if kind == "text" else (
            build_global(e, false) if kind == "global" else build_shape(e))
        canvas.add_child(node)
        node.owner = canvas

    # A scene with no text needs no pool; adopt_strings() makes one on demand.
    if not pool.entries.is_empty(): ZenStringOps.repoint(canvas, pool)
    assign_z(canvas)

    var bus := _build_bus(doc)
    if bus != null:
        canvas.add_child(bus)
        bus.owner = canvas

    # The keys are stored in the scene's AnimationPlayer, not on the nodes.
    ZenAnimBuilder.install(canvas)

    return canvas


## Element order IS draw order in Zen (anim.h:556), so child index -> z_index.
## A global's background half keeps its -1 and is skipped. Re-run after any
## reorder, add or delete.
static func assign_z(canvas: ZenCanvas) -> void:
    var z := 0
    for c in canvas.get_children():
        var n := c as ZenElement
        if n == null: continue              # the bus and the player
        if n is ZenGlobal and (n as ZenGlobal).is_background:
            n.z_index = -1
            continue
        n.z_index = z
        z += 1


## The signal bus, or null for a document that authored no signals.
##
## Signals reference elements BY NAME, so nothing here needs resolving to an
## index: the bus looks elements up at fire time. That also means an element renamed in the Godot editor breaks its
## signal loudly, rather than an index silently repointing at a neighbour.
static func _build_bus(doc: Dictionary) -> ZenSignalBus:
    var sigs: Array = doc.get("signals", [])
    if sigs.is_empty(): return null
    var bus := ZenSignalBus.new()
    bus.set_script(load("res://addons/zen/runtime/zen_signal_bus.gd"))
    bus.name = "Signals"
    bus.signals_data = sigs.duplicate(true)
    return bus


## A text element's own words become a pool entry - reused when the pool
## already holds them (AnimDocStringIdxAt pools them the same way) - and the
## element references the canvas's pool from then on. `pool` is the CANVAS's
## instance, never a private one; `free` lists holes it may fill (and loses
## the one it fills).
static func build_text(e: Dictionary, pool: ZenStrings, free: Array = []) -> ZenText:
    var n := ZenText.new()
    n.set_script(load("res://addons/zen/runtime/zen_text.gd"))
    n.name = node_name(String(e["name"]))
    n.elem_name = String(e["name"])
    n.strings = pool
    n.string_base = pool.add(String(e["text"]), free)
    free.erase(n.string_base)
    n.unit_abs = bool(e["unit_abs"])
    n.pos_frac = e["pos"]
    n.size_frac = e["size"]
    n.rot_base = float(e["rot"])
    n.corner_mode = bool(e["corner_mode"])
    n.color_base = e["color"]
    var fx: Dictionary = e["crumble_fx"]
    n.crumble_spin = float(fx["crumble_spin"])
    n.crumble_dir = float(fx["crumble_dir"])
    n.crumble_spread = float(fx["crumble_spread"])
    n.crumble_dist = float(fx["crumble_dist"])
    n.tracks = _tracks_for(e, "text")
    return n


static func build_global(e: Dictionary, background: bool) -> ZenGlobal:
    var n := ZenGlobal.new()
    n.set_script(load("res://addons/zen/runtime/zen_global.gd"))
    n.name = node_name(String(e["name"])) + ("_bg" if background else "")
    n.elem_name = String(e["name"])
    n.is_background = background
    n.corner_mode = bool(e["corner_mode"])
    n.color_base = e["color"]
    n.bg_color_base = e["bg_color"]
    n.tracks = _tracks_for(e, "global")
    return n


static func build_shape(e: Dictionary) -> ZenShape:
    var s := ZenShape.new()
    s.set_script(load("res://addons/zen/runtime/zen_shape.gd"))
    s.name = node_name(String(e["name"]))
    s.elem_name = String(e["name"])
    s.shape_kind = ZenShape.kind_from_name(String(e["shape"]))
    s.unit_abs = bool(e["unit_abs"])
    s.pos_frac = e["pos"]
    s.size_frac = e["size"]
    s.scale_base = float(e["scale"])
    s.rot_base = float(e["rot"])
    s.corner_mode = bool(e["corner_mode"])
    s.color_base = e["color"]
    s.outline_color_base = e["outline_color"]
    s.outline_base = float(e["outline"])
    s.outline_crisp = bool(e["outline_crisp"])
    s.tracks = _tracks_for(e, "shape")
    if s.shape_kind == ZenShape.Kind.CUSTOM:
        s.shape_name = String(e["shape_name"])
        if not s.shape_name.is_empty():
            s.shape = ZenAssets.load_shape(s.shape_name)
            if s.shape == null: push_warning("zen: missing pixel shape '%s'" % s.shape_name)
    return s


## Keep only the tracks valid for this element kind. A cross-kind track would
## silently do nothing, so dropping it here keeps the scene honest.
static func _tracks_for(e: Dictionary, kind: String) -> Dictionary:
    var valid: Array = ZenProps.scalars_for(kind) + ZenProps.colors_for(kind)
    var out := {}
    for prop in e["tracks"]:
        if valid.has(prop):
            out[prop] = (e["tracks"][prop] as Array).duplicate(true)
    return out


## Node names cannot contain . : @ / " % and must not be empty.
static func node_name(raw: String) -> String:
    var out := ""
    for ch in raw:
        out += "_" if ".:@/\"%".contains(ch) else ch
    out = out.strip_edges()
    return out if not out.is_empty() else "unnamed"
