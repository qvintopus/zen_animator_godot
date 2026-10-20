@tool
class_name ZenElemOps
extends RefCounted
##
## Element CRUD on a live canvas. The node tree IS the document: an element is
## a ZenElement child of the canvas, its draw order is its child order, and its
## keys are the tracks in the canvas's Animations whose path starts with its
## node name. So every op here edits nodes and track paths, never a copy.
##
## A global is TWO nodes sharing one elem_name (ZenGlobal: `name_bg` paints the
## background, `name` the fade). Ops take either half and act on both; a ROW is
## the non-background half, which is what the outliner lists.
##
## Signals reference elements by elem_name (signals_data) and their keys by
## node path (the "sig" Animations), so rename and remove rewrite both.
##

const BG_SUFFIX := "_bg"


## One entry per element as the author sees it: every ZenElement except a
## global's background half, in draw order.
static func rows(canvas: ZenCanvas) -> Array:
    var out: Array = []
    for e in canvas.elements():
        if e is ZenGlobal and (e as ZenGlobal).is_background: continue
        out.append(e)
    return out


## Both nodes of `el`'s element (one, unless it is a global): [bg, main].
static func halves(canvas: ZenCanvas, el: ZenElement) -> Array:
    var out: Array = []
    for e in canvas.elements():
        if (e as ZenElement).elem_name == el.elem_name: out.append(e)
    return out


## The row node for `el` (a global's fade half).
static func row_of(canvas: ZenCanvas, el: ZenElement) -> ZenElement:
    for e in halves(canvas, el):
        if not (e is ZenGlobal and (e as ZenGlobal).is_background): return e
    return el


static func find(canvas: ZenCanvas, elem_name: String) -> ZenElement:
    for e in rows(canvas):
        if (e as ZenElement).elem_name == elem_name: return e
    return null


static func is_name_free(canvas: ZenCanvas, nm: String) -> bool:
    if nm.strip_edges().is_empty(): return false
    var node := ZenElemFactory.node_name(nm)
    for c in canvas.get_children():
        if c is ZenElement and (c as ZenElement).elem_name == nm: return false
        var cn := String(c.name)
        if cn == node or cn == node + BG_SUFFIX: return false
    return true


## `base`, or `base_2`, `base_3`... - the first that is free.
static func unique_name(canvas: ZenCanvas, base: String) -> String:
    if is_name_free(canvas, base): return base
    var stem := base
    var m := RegEx.create_from_string("^(.*)_(\\d+)$").search(base)
    if m != null: stem = m.get_string(1)
    var n := 2
    while not is_name_free(canvas, "%s_%d" % [stem, n]): n += 1
    return "%s_%d" % [stem, n]


# ---------------------------------------------------------------------------
#  Create
# ---------------------------------------------------------------------------

## The defaults a new element starts from (AnimElemInit, anim.c:107-151).
static func defaults(kind: String, nm: String) -> Dictionary:
    var e := ZenElemFactory.new_elem(kind, nm)
    match kind:
        "text":
            e["text"] = "TEXT"
            e["pos"] = Vector2(0.5, 0.4)
            e["size"] = Vector2(0.1, 0.1)
        "global":
            e["color"] = Color(0, 0, 0, 1)
    return e


## Add an element of `kind` at the front of the draw order (the end of the
## list) and return its row node. Its keys, if `e` has tracks, are installed
## onto the canvas's Animation.
static func add(canvas: ZenCanvas, kind: String, nm := "", e := {}) -> ZenElement:
    if nm.is_empty(): nm = kind
    nm = unique_name(canvas, nm)
    if e.is_empty(): e = defaults(kind, nm)
    e["name"] = nm
    var nodes: Array = []
    match kind:
        "text":
            var free: Array = []
            free.assign(ZenStringOps.holes(canvas))
            nodes = [ZenElemFactory.build_text(e, ZenStringOps.pool(canvas), free)]
        "shape": nodes = [ZenElemFactory.build_shape(e)]
        "global": nodes = [ZenElemFactory.build_global(e, true), ZenElemFactory.build_global(e, false)]
        _: return null
    var at := _end_of_elements(canvas)
    for n in nodes:
        canvas.add_child(n)
        canvas.move_child(n, at)
        at += 1
        n.owner = _owner(canvas)
    _install_tracks(canvas, nodes)
    ZenElemFactory.assign_z(canvas)
    return nodes[nodes.size() - 1]


static func _owner(canvas: ZenCanvas) -> Node:
    return canvas.owner if canvas.owner != null else canvas


## Child index just past the last element: new elements go before the bus and
## the player, so the child list reads elements-first like a bundled scene.
static func _end_of_elements(canvas: ZenCanvas) -> int:
    var at := 0
    for c in canvas.get_children():
        if c is ZenElement: at = c.get_index() + 1
    return at


## Bake `tracks` of freshly built nodes into the existing Animation, the way
## ZenAnimBuilder.bake_timeline would have.
static func _install_tracks(canvas: ZenCanvas, nodes: Array) -> void:
    var anim := ZenKeyOps.anim_of(canvas)
    if anim == null: return
    for n in nodes:
        var el := n as ZenElement
        for prop in el.tracks:
            var keys: Array = el.tracks[prop]
            if keys.is_empty() or not el.owns(String(prop)): continue
            var path := el.track_path(String(prop))
            if ZenProps.is_stepped(String(prop)):
                ZenAnimBuilder._add_stepped(anim, path, keys)
                continue
            if ZenProps.is_color(String(prop)): ZenAnimBuilder._add_color(anim, path, keys)
            else: ZenAnimBuilder._add_scalar(anim, path, keys)
            ZenAnimBuilder.add_ease(anim, ZenAnimBuilder.ease_path(String(el.name), String(prop)), keys)
        el.tracks = {}
    canvas.timeline_dirty()


## Copy `el` (both halves, all keys) to a new element right after it.
static func duplicate_elem(canvas: ZenCanvas, el: ZenElement) -> ZenElement:
    var src := halves(canvas, el)
    var nm := unique_name(canvas, el.elem_name)
    var at := (src[src.size() - 1] as Node).get_index() + 1
    var made: ZenElement = null
    for s in src:
        var n := (s as Node).duplicate() as ZenElement
        n.elem_name = nm
        n.name = _node_for(s, nm)
        canvas.add_child(n)
        canvas.move_child(n, at)
        at += 1
        n.owner = _owner(canvas)
        _copy_tracks(canvas, String((s as Node).name), String(n.name))
        made = n
    ZenElemFactory.assign_z(canvas)
    return row_of(canvas, made)


static func _node_for(half: ZenElement, nm: String) -> String:
    var bg := half is ZenGlobal and (half as ZenGlobal).is_background
    return ZenElemFactory.node_name(nm) + (BG_SUFFIX if bg else "")


static func _copy_tracks(canvas: ZenCanvas, from_node: String, to_node: String) -> void:
    var anim := ZenKeyOps.anim_of(canvas)
    if anim == null: return
    var n := anim.get_track_count()
    for i in n:
        var p := String(anim.track_get_path(i))
        if not p.begins_with(from_node + ":"): continue
        anim.copy_track(i, anim)
        anim.track_set_path(anim.get_track_count() - 1,
            NodePath(to_node + p.substr(from_node.length())))
    canvas.timeline_dirty()


# ---------------------------------------------------------------------------
#  Delete
# ---------------------------------------------------------------------------

## Remove `el` (both halves), its keys in every Animation, and every signal
## reference to it.
static func remove(canvas: ZenCanvas, el: ZenElement) -> void:
    var nm := el.elem_name
    for h in halves(canvas, el):
        var node := String((h as Node).name)
        for anim in _animations(canvas):
            for i in range(anim.get_track_count() - 1, -1, -1):
                if String(anim.track_get_path(i)).begins_with(node + ":"):
                    anim.remove_track(i)
        canvas.remove_child(h)
        (h as Node).queue_free()
    _prune_signals(canvas, nm)
    ZenElemFactory.assign_z(canvas)
    canvas.timeline_dirty()


## Drop every signal reference to `nm`. A pos-param's keys live at
## `Node:pos_offset_<i>`, indexed by its slot in the signal's list, so
## removing one shifts the tracks of the params after it down a slot.
static func _prune_signals(canvas: ZenCanvas, nm: String) -> void:
    var bus := canvas.bus()
    if bus == null: return
    for s in bus.signals_data:
        var sig: Dictionary = s
        sig["targets"] = (sig.get("targets", []) as Array).filter(
            func(tg): return String(tg["elem"]) != nm)
        sig["seq_targets"] = (sig.get("seq_targets", []) as Array).filter(
            func(tg): return String(tg["elem"]) != nm)
        var pps: Array = sig.get("pos_params", [])
        var sa := _signal_anim(canvas, String(sig.get("name", "")))
        var kept: Array = []
        for i in pps.size():
            if String(pps[i]["elem"]) == nm: continue
            if sa != null and kept.size() != i:
                _rename_slot(sa, i, kept.size())
            kept.append(pps[i])
        sig["pos_params"] = kept


static func _rename_slot(anim: Animation, from: int, to: int) -> void:
    var a := ":pos_offset_%d:" % from
    var b := ":pos_offset_%d:" % to
    for i in anim.get_track_count():
        var p := String(anim.track_get_path(i))
        if p.contains(a): anim.track_set_path(i, NodePath(p.replace(a, b)))


# ---------------------------------------------------------------------------
#  Rename
# ---------------------------------------------------------------------------

## Rename `el` to `nm`: its elem_name, its node name(s), every track path in
## every Animation, and every signal reference. False when `nm` is taken.
static func rename(canvas: ZenCanvas, el: ZenElement, nm: String) -> bool:
    nm = nm.strip_edges()
    if nm == el.elem_name: return true
    if not is_name_free(canvas, nm): return false
    var old := el.elem_name
    for h in halves(canvas, el):
        var hn := h as ZenElement
        var from := String(hn.name)
        var to := _node_for(hn, nm)
        hn.elem_name = nm
        hn.name = to
        for anim in _animations(canvas):
            for i in anim.get_track_count():
                var p := String(anim.track_get_path(i))
                if p.begins_with(from + ":"):
                    anim.track_set_path(i, NodePath(to + p.substr(from.length())))
    var bus := canvas.bus()
    if bus != null:
        for s in bus.signals_data:
            for key in ["targets", "seq_targets", "pos_params"]:
                for tg in (s as Dictionary).get(key, []):
                    if String(tg["elem"]) == old: tg["elem"] = nm
    canvas.timeline_dirty()
    return true


# ---------------------------------------------------------------------------
#  Reorder
# ---------------------------------------------------------------------------

## Move `el` to row `to` of rows(): draw order follows.
static func move(canvas: ZenCanvas, el: ZenElement, to: int) -> void:
    var rs := rows(canvas)
    var row := row_of(canvas, el)
    var from := rs.find(row)
    to = clampi(to, 0, rs.size() - 1)
    if from < 0 or from == to: return
    rs.remove_at(from)
    rs.insert(to, row)
    # Re-lay every element in row order, a global's background half first.
    var at := 0
    for r in rs:
        for h in halves(canvas, r):
            canvas.move_child(h, at)
            at += 1
    ZenElemFactory.assign_z(canvas)


# ---------------------------------------------------------------------------
#  Shared
# ---------------------------------------------------------------------------

## The document timeline and every signal's Animation.
static func _animations(canvas: ZenCanvas) -> Array:
    var out: Array = []
    var ap := ZenAnimBuilder.find_player(canvas)
    if ap == null: return out
    for lib_name in ap.get_animation_library_list():
        var lib := ap.get_animation_library(lib_name)
        for an in lib.get_animation_list():
            out.append(lib.get_animation(an))
    return out


static func _signal_anim(canvas: ZenCanvas, signal_name: String) -> Animation:
    var ap := ZenAnimBuilder.find_player(canvas)
    if ap == null or not ap.has_animation_library(ZenAnimBuilder.SIG_LIB): return null
    var lib := ap.get_animation_library(ZenAnimBuilder.SIG_LIB)
    var an := ZenAnimBuilder.sig_anim_name(signal_name)
    return lib.get_animation(an) if lib.has_animation(an) else null
