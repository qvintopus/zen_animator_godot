@tool
class_name ZenClipOps
extends RefCounted
##
## Copy and paste of elements and keys, between scenes or within one. A CLIP is
## a small ZenCanvas of its own - the copied elements plus a "zen" Animation
## holding only the copied keys, rebased so the first one sits at t=0, and its
## own string pool - so it is the same format as a scene: it saves with
## ZenSceneOps and loads back the same way, and nothing here is a second key
## format.
##
## Keys travel as ZenKeyOps's segment model, so values, bezier handles and
## eases survive. Where keys are left out (a key-only copy) or land between
## existing ones (a merge) the segments they touch are marked dirty and
## re-derived from their ease; every other segment is written back as read.
##
## Signals are not carried: a clip is timeline keys and elements only.
##

## Props a RELATIVE merge re-bases onto the target's own position.
const RELATIVE := ["pos_x", "pos_y"]
const T_EPS := ZenKeyOps.T_EPS


# ---------------------------------------------------------------------------
#  Model helpers (pure: arrays in, arrays out)
# ---------------------------------------------------------------------------

## The keys at `keep` (ascending indices) as a model of their own. A key whose
## original predecessor was dropped gets a dirty incoming segment.
static func slice(model: Array, keep: Array) -> Array:
    var out: Array = []
    var prev := -2
    for i in keep:
        var k: Dictionary = (model[i] as Dictionary).duplicate(true)
        if out.is_empty():
            for ch in k["ch"]: ch["fit"] = []        # no incoming segment now
        elif int(i) != prev + 1:
            k["dirty"] = true
        out.append(k)
        prev = int(i)
    return out


static func shift(model: Array, dt: float) -> Array:
    var out: Array = []
    for src in model:
        var k: Dictionary = (src as Dictionary).duplicate(true)
        k["t"] = float(k["t"]) + dt
        for ch in k["ch"]:
            for f in ch["fit"]: f["t"] = float(f["t"]) + dt
        out.append(k)
    return out


## Add `dv` to the value of a single-channel (scalar) model.
static func offset(model: Array, dv: float) -> Array:
    var out: Array = []
    for src in model:
        var k: Dictionary = (src as Dictionary).duplicate(true)
        for ch in k["ch"]:
            ch["v"] = float(ch["v"]) + dv
            for f in ch["fit"]: f["v"] = float(f["v"]) + dv
        out.append(k)
    return out


## `src` keys laid over `dst`: a key at the same time replaces the one there.
static func merge(dst: Array, src: Array) -> Array:
    var out: Array = (dst as Array).duplicate(true)
    for s in src:
        var sk: Dictionary = (s as Dictionary).duplicate(true)
        sk["dirty"] = true
        var at := out.size()
        var replaced := false
        for i in out.size():
            if absf(float(out[i]["t"]) - float(sk["t"])) <= T_EPS:
                out[i] = sk
                replaced = true
                at = i
                break
            if float(out[i]["t"]) > float(sk["t"]):
                at = i
                break
        if not replaced: out.insert(at, sk)
        ZenKeyOps._mark(out, at + 1)         # its incoming segment has a new start
    if not out.is_empty():
        for ch in out[0]["ch"]: ch["fit"] = []
    return out


static func last_t(model: Array) -> float:
    return float(model[model.size() - 1]["t"]) if not model.is_empty() else 0.0


# ---------------------------------------------------------------------------
#  Copy
# ---------------------------------------------------------------------------

## Build a clip from `elems` (rows of `canvas`). `key_ids` ("node|prop|idx", the
## editor's key selection) restricts it to exactly those keys; empty copies every
## track of every element. Null when nothing was copied (or `canvas` is editing
## a signal, whose keys are not timeline keys).
static func copy(canvas: ZenCanvas, elems: Array, key_ids := {}) -> ZenCanvas:
    if not canvas.edit_anim.is_empty(): return null
    var picked := _picked(key_ids)
    var found: Array = []                     # [{node, prop, model | steps}]
    var nodes: Array = []                     # the source halves to carry
    for el in elems:
        for h in ZenElemOps.halves(canvas, el as ZenElement):
            var half := h as ZenElement
            var any := false
            for prop in _props(half):
                if not ZenKeyOps.has_track(canvas, half, prop): continue
                var want: Array = _wanted(picked, String(half.name), prop, canvas, half)
                if want.is_empty(): continue
                any = true
                if ZenProps.is_stepped(prop):
                    var ks := ZenKeyOps.keys(canvas, half, prop)
                    var steps: Array = []
                    for i in want: steps.append(ks[i])
                    found.append({"node": half, "prop": prop, "steps": steps})
                else:
                    var m := slice(ZenKeyOps.read_model(canvas, half, prop), want)
                    found.append({"node": half, "prop": prop, "model": m})
            if any or picked.is_empty(): nodes.append(half)
    if found.is_empty() and nodes.is_empty(): return null

    var t0 := INF
    var t1 := 0.0
    for f in found:
        var first := INF
        var last := 0.0
        if f.has("model"):
            first = float(f["model"][0]["t"])
            last = last_t(f["model"])
        else:
            first = float(f["steps"][0]["t"])
            last = float(f["steps"][f["steps"].size() - 1]["t"])
        t0 = minf(t0, first)
        t1 = maxf(t1, last)
    if t0 == INF: t0 = 0.0

    var clip := ZenCanvas.new()
    clip.live_playback = false
    clip.design_size = canvas.design_size
    clip.clear_color = canvas.clear_color
    clip.duration = maxf(t1 - t0, 0.1)
    clip.outro_start = 0.0
    ZenAnimBuilder.install(clip)
    var made := {}                              # source node name -> clip node
    for h in nodes:
        var n := (h as ZenElement).duplicate() as ZenElement
        n.tracks = {}
        clip.add_child(n)
        n.owner = clip
        if n is ZenText: _repool(n as ZenText, h as ZenText, clip)
        made[String((h as Node).name)] = n
    ZenElemFactory.assign_z(clip)
    # Keys land on a duration-long Animation; the stepped insert clamps to it.
    ZenDocOps.set_duration(clip, maxf(t1 - t0, 0.1))
    ZenDocOps.set_outro_start(clip, 0.0)
    for f in found:
        var n: ZenElement = made[String((f["node"] as Node).name)]
        var prop := String(f["prop"])
        if f.has("model"):
            ZenKeyOps.write_model(clip, n, prop, shift(f["model"], -t0))
        else:
            for k in f["steps"]:
                var v := float(k["v"])
                if prop == "string": v = _map_string(canvas, clip, f["node"], int(v))
                ZenKeyOps.insert(clip, n, prop, float(k["t"]) - t0, v)
    return clip


## The key indices to carry for `prop`: the picked ones, or every key when
## nothing is picked at all.
static func _wanted(picked: Dictionary, node: String, prop: String, canvas: ZenCanvas,
                    half: ZenElement) -> Array:
    var all := range(ZenKeyOps.keys(canvas, half, prop).size())
    if picked.is_empty(): return all
    var idx: Array = (picked.get("%s|%s" % [node, prop], []) as Array).duplicate()
    idx.sort()
    return idx


static func _picked(key_ids: Dictionary) -> Dictionary:
    var out := {}
    for id in key_ids:
        var p := String(id).rsplit("|", true, 2)         # node | prop | idx
        if p.size() != 3: continue
        var k := "%s|%s" % [p[0], p[1]]
        if not out.has(k): out[k] = []
        (out[k] as Array).append(int(p[2]))
    return out


static func _props(el: ZenElement) -> Array:
    var out: Array = []
    for p in ZenProps.scalars_for(el.zen_kind()) + ZenProps.colors_for(el.zen_kind()):
        if el.owns(String(p)): out.append(p)
    return out


## Point a copied text at `dst`'s pool, holding the same words.
static func _repool(n: ZenText, src: ZenText, dst: ZenCanvas) -> void:
    n.strings = ZenStringOps.pool(dst)
    var words := src.strings.at(src.string_base) if src.strings != null else ""
    n.string_base = ZenStringOps.add(dst, words)


static func _map_string(from: ZenCanvas, to: ZenCanvas, src: ZenElement, i: int) -> int:
    var pool := (src as ZenText).strings if src is ZenText else null
    if pool == null: pool = ZenStringOps.pool(from)
    return ZenStringOps.add(to, pool.at(i))


# ---------------------------------------------------------------------------
#  Paste
# ---------------------------------------------------------------------------

## Lay `clip` into `dest` with its first key at `t`. With `target` (and a
## one-element clip) the keys merge into that element; otherwise the clip's
## elements are added as new ones. `relative` re-bases position keys of a merge
## onto the target's own position at `t`. Returns the rows pasted onto.
static func paste(dest: ZenCanvas, clip: ZenCanvas, t: float, target: ZenElement = null,
                  relative := false) -> Array:
    if not dest.edit_anim.is_empty() or clip == null: return []
    var rows := ZenElemOps.rows(clip)
    var out: Array = []
    var end := 0.0
    if target != null:
        if rows.size() != 1: return []
        var src := rows[0] as ZenElement
        for h in ZenElemOps.halves(clip, src):
            for th in ZenElemOps.halves(dest, target):
                end = maxf(end, _apply(dest, clip, h as ZenElement, th as ZenElement, t, relative))
        out.append(target)
    else:
        for r in rows:
            var nm := ZenElemOps.unique_name(dest, (r as ZenElement).elem_name)
            var at := ZenElemOps._end_of_elements(dest)
            var made: ZenElement = null
            for h in ZenElemOps.halves(clip, r as ZenElement):
                var n := (h as ZenElement).duplicate() as ZenElement
                n.tracks = {}
                n.elem_name = nm
                n.name = ZenElemOps._node_for(h as ZenElement, nm)
                dest.add_child(n)
                dest.move_child(n, at)
                at += 1
                n.owner = ZenElemOps._owner(dest)
                if n is ZenText: _repool(n as ZenText, h as ZenText, dest)
                end = maxf(end, _apply(dest, clip, h as ZenElement, n, t, false))
                made = n
            out.append(ZenElemOps.row_of(dest, made))
        ZenElemFactory.assign_z(dest)
    if end > dest.duration: ZenDocOps.set_duration(dest, end)
    dest.timeline_dirty()
    return out


## Copy every track of clip node `h` onto `to`, shifted to `t`. Returns the
## time of the last key written.
static func _apply(dest: ZenCanvas, clip: ZenCanvas, h: ZenElement, to: ZenElement, t: float,
                   relative: bool) -> float:
    var end := 0.0
    for prop in _props(h):
        if not to.owns(prop) or not ZenKeyOps.has_track(clip, h, prop): continue
        if ZenProps.is_stepped(prop):
            for k in ZenKeyOps.keys(clip, h, prop):
                var v := float(k["v"])
                if prop == "string": v = _map_string(clip, dest, h, int(v))
                ZenKeyOps.insert(dest, to, prop, float(k["t"]) + t, v)
                end = maxf(end, float(k["t"]) + t)
            continue
        var m := shift(ZenKeyOps.read_model(clip, h, prop), t)
        if relative and RELATIVE.has(prop) and not m.is_empty():
            m = offset(m, _value_at(dest, to, prop, t) - float(m[0]["ch"][0]["v"]))
        var cur := ZenKeyOps.read_model(dest, to, prop)
        ZenKeyOps.write_model(dest, to, prop, merge(cur, m) if not cur.is_empty() else m)
        end = maxf(end, last_t(m))
    return end


## The value `prop` of `el` has at `t`: its track, else its base pose.
static func _value_at(canvas: ZenCanvas, el: ZenElement, prop: String, t: float) -> float:
    var anim := ZenKeyOps.anim_of(canvas)
    var tr := ZenKeyOps._track(anim, el.track_path(prop)) if anim != null else -1
    if tr >= 0 and anim.track_get_key_count(tr) > 0:
        return anim.bezier_track_interpolate(tr, t)
    return el.base_scalar(prop)
