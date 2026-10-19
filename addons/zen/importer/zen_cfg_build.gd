@tool
class_name ZenCfgBuild
extends RefCounted
##
## Turns a parsed .cfg document (ZenCfgParse.parse_doc) into a ZenCanvas tree.
##
## Element kinds the node layer does not implement are SKIPPED and reported
## rather than half-built: a text element silently rendering as nothing would
## look like a broken animation, whereas a named deferral is a to-do.
##

## Element kinds that currently have a node.
const SUPPORTED := ["shape", "text", "global"]


static func build(doc: Dictionary) -> Dictionary:
    var canvas := ZenCanvas.new()
    canvas.set_script(load("res://addons/zen/runtime/zen_canvas.gd"))
    canvas.name = _node_name(String(doc["name"]))
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

    var skipped: Array = []
    for e in doc["elems"]:
        var kind := String(e["kind"])
        if not SUPPORTED.has(kind):
            if not skipped.has(kind): skipped.append(kind)
            continue
        # A global element is TWO rects at different depths: its background half
        # is drawn before every element, its fade half at its own index.
        if kind == "global":
            var bg := _build_global(e, true)
            canvas.add_child(bg)
            bg.owner = canvas
            bg.z_index = -1                     # behind every element
        var node: Node2D = _build_text(e) if kind == "text" else (
            _build_global(e, false) if kind == "global" else _build_shape(e))
        canvas.add_child(node)
        node.owner = canvas

    # Element order IS draw order in Zen (anim.h:556), so index -> z_index.
    # The background half keeps its -1 and is skipped here.
    var z := 0
    for c in canvas.get_children():
        var n := c as Node2D
        if n == null: continue              # the bus is a plain Node
        if n.z_index < 0: continue
        n.z_index = z
        z += 1

    var bus := _build_bus(doc)
    if bus != null:
        canvas.add_child(bus)
        bus.owner = canvas

    return {"canvas": canvas, "skipped": skipped}


## The signal bus, or null for a document that authored no signals.
##
## Signals reference elements BY NAME (which is what the .cfg already stores),
## so nothing here needs resolving to an index: the bus looks elements up at
## fire time. That also means an element renamed in the Godot editor breaks its
## signal loudly, rather than an index silently repointing at a neighbour.
static func _build_bus(doc: Dictionary) -> ZenSignalBus:
    var sigs: Array = doc.get("signals", [])
    if sigs.is_empty(): return null
    var bus := ZenSignalBus.new()
    bus.set_script(load("res://addons/zen/runtime/zen_signal_bus.gd"))
    bus.name = "Signals"
    bus.signals_data = sigs.duplicate(true)
    return bus


static func _build_text(e: Dictionary) -> ZenText:
    var n := ZenText.new()
    n.set_script(load("res://addons/zen/runtime/zen_text.gd"))
    n.name = _node_name(String(e["name"]))
    n.elem_name = String(e["name"])
    n.text = String(e["text"])
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
    n.tracks = _tracks_for(e, ZenCfgParse.TEXT_PROPS)
    return n


static func _build_global(e: Dictionary, background: bool) -> ZenGlobal:
    var n := ZenGlobal.new()
    n.set_script(load("res://addons/zen/runtime/zen_global.gd"))
    n.name = _node_name(String(e["name"])) + ("_bg" if background else "")
    n.elem_name = String(e["name"])
    n.is_background = background
    n.corner_mode = bool(e["corner_mode"])
    n.color_base = e["color"]
    n.bg_color_base = e["bg_color"]
    n.tracks = _tracks_for(e, ZenCfgParse.GLOBAL_PROPS)
    return n


static func _build_shape(e: Dictionary) -> ZenShape:
    var s := ZenShape.new()
    s.set_script(load("res://addons/zen/runtime/zen_shape.gd"))
    s.name = _node_name(String(e["name"]))
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
    s.tracks = _tracks_for(e, ZenCfgParse.SHAPE_PROPS)
    if s.shape_kind == ZenShape.Kind.CUSTOM:
        _resolve_shapes(s, e)
    return s


## Pixel shapes are referenced BY NAME, resolved against ZenAssets.
##
## A `shape_id` key holds a pool slot index from the SAVING build, which
## means nothing here; the element's `shape_ref` lines map those indices to
## names (anim_io.c FixupShapeRefs). Each key is rewritten to an index into
## `shape_refs`, and a name with no asset becomes SHAPE_MISSING so it draws
## the placeholder rather than whichever shape inherited the number.
static func _resolve_shapes(s: ZenShape, e: Dictionary) -> void:
    var nm := String(e.get("shape_name", ""))
    s.shape_name = nm
    if not nm.is_empty():
        s.shape = ZenAssets.load_shape(nm)
        if s.shape == null: push_warning("zen import: missing pixel shape '%s'" % nm)
    if not s.tracks.has("shape_id"): return
    var refs: Dictionary = e.get("shape_refs", {})
    var order: Array[String] = []
    var list: Array[ZenPixelShape] = []
    for k in s.tracks["shape_id"]:
        var saved := int(float(k["v"]) + 0.5)
        if not refs.has(saved):
            k["v"] = ZenShape.SHAPE_MISSING
            continue
        var ref_name := String(refs[saved])
        var res := ZenAssets.load_shape(ref_name)
        if res == null:
            push_warning("zen import: missing pixel shape '%s'" % ref_name)
            k["v"] = ZenShape.SHAPE_MISSING
            continue
        var i := order.find(ref_name)
        if i < 0:
            order.append(ref_name)
            list.append(res)
            i = order.size() - 1
        k["v"] = float(i)
    s.shape_refs = list


## Keep only the tracks valid for this element kind. A cross-kind track would
## silently do nothing, so dropping it here keeps the scene honest.
static func _tracks_for(e: Dictionary, valid: Array) -> Dictionary:
    var out := {}
    for prop in e["tracks"]:
        if valid.has(prop):
            out[prop] = (e["tracks"][prop] as Array).duplicate(true)
    return out


## Node names cannot contain . : @ / " % and must not be empty.
static func _node_name(raw: String) -> String:
    var out := ""
    for ch in raw:
        out += "_" if ".:@/\"%".contains(ch) else ch
    out = out.strip_edges()
    return out if not out.is_empty() else "unnamed"
