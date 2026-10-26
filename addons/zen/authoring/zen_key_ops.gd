@tool
class_name ZenKeyOps
extends RefCounted
##
## Key editing on the canvas's "zen" Animation - the scene editor's only way to
## touch a key. There is no editor-side copy: every op reads the tracks, edits
## them in place and leaves the Animation as the one stored copy.
##
## THE KEY MODEL (see ZenAnimBuilder): a prop's {t, v, ease} is split across
## its bezier track(s) {t, v} and its ease track {t, ease}. A key is AUTHORED
## when the ease track has a key at its time; the other bezier keys are FIT
## keys ZenCurveBake inserted for a non-cubic ease, and belong to the segment
## they sit in. A bezier with no ease track reads as all-authored, ease
## EASE_RAW.
##
## Edits REBAKE ONLY THE SEGMENTS THEY TOUCH. Each authored key carries its
## incoming segment (handles plus fit keys); an op marks the segments whose
## ends moved as dirty, and only those are re-derived - from ZenCurveBake for a
## named ease, by rescaling the existing handles for EASE_RAW. Every other
## segment is written back exactly as read, so handles shaped by hand in
## Godot's own Animation panel survive an unrelated edit.
##
## Colour props key all three channels at once with one shared ease track.
## Stepped props (`string`, `shape_id`) are a plain discrete value track.
##

const ANIM := ZenAnimBuilder.ANIM
const RAW := ZenAnimBuilder.EASE_RAW
## Key times are matched within this (a saved scene stores them as float32).
## Well under ZenCurveBake.STEP_EPS, so an instant step stays two keys.
const T_EPS := 2e-5
const STEP := ZenCurveBake.STEP_EPS
## The ease a new key gets when nothing suggests another.
const DEFAULT_EASE := "linear"


# ---------------------------------------------------------------------------
#  Lookup
# ---------------------------------------------------------------------------

## The Animation key ops edit: the document timeline, or the signal named by
## canvas.edit_anim (its keys are seconds into the signal, 0..length).
static func anim_of(canvas: ZenCanvas) -> Animation:
    if not canvas.edit_anim.is_empty():
        return ZenAnimBuilder.signal_anim(canvas, canvas.edit_anim)
    var ap := ZenAnimBuilder.find_player(canvas)
    if ap == null or not ap.has_animation(ANIM): return null
    return ap.get_animation(ANIM)


## The bezier (or, stepped, value) track paths that hold `prop` for `el`.
static func channel_paths(el: ZenElement, prop: String) -> Array:
    var path := el.track_path(prop)
    if ZenProps.is_color(prop):
        return ["%s:r" % path, "%s:g" % path, "%s:b" % path]
    return [path]


static func ease_path(el: ZenElement, prop: String) -> String:
    return ZenAnimBuilder.ease_path(String(el.name), prop)


static func _track(anim: Animation, path: String) -> int:
    for i in anim.get_track_count():
        if String(anim.track_get_path(i)) == path: return i
    return -1


## Does `prop` have keys on `el`?
static func has_track(canvas: ZenCanvas, el: ZenElement, prop: String) -> bool:
    var anim := anim_of(canvas)
    if anim == null: return false
    var tr := _track(anim, channel_paths(el, prop)[0])
    return tr >= 0 and anim.track_get_key_count(tr) > 0


## Every prop of `el` that has keys, in ZenProps order.
static func keyed_props(canvas: ZenCanvas, el: ZenElement) -> Array:
    var out: Array = []
    for p in ZenProps.scalars_for(el.zen_kind()) + ZenProps.colors_for(el.zen_kind()):
        if el.owns(p) and has_track(canvas, el, p): out.append(p)
    return out


## The authored keys of `prop`: [{t, v, ease}], ascending in t. `v` is a float,
## or a Color (alpha 1) for a colour prop. Stepped props report ease "step".
static func keys(canvas: ZenCanvas, el: ZenElement, prop: String) -> Array:
    var anim := anim_of(canvas)
    if anim == null: return []
    if ZenProps.is_stepped(prop): return _stepped_keys(anim, channel_paths(el, prop)[0])
    var out: Array = []
    for k in _read(anim, el, prop):
        out.append({"t": k["t"], "v": _value(k, prop), "ease": k["ease"]})
    return out


## Index of the authored key at `t` (within T_EPS), or -1.
static func key_at(canvas: ZenCanvas, el: ZenElement, prop: String, t: float) -> int:
    var ks := keys(canvas, el, prop)
    for i in ks.size():
        if absf(float(ks[i]["t"]) - t) <= T_EPS: return i
    return -1


static func _value(k: Dictionary, prop: String) -> Variant:
    var ch: Array = k["ch"]
    if ZenProps.is_color(prop):
        return Color(float(ch[0]["v"]), float(ch[1]["v"]), float(ch[2]["v"]), 1.0)
    return float(ch[0]["v"])


# ---------------------------------------------------------------------------
#  The segment model
#
#  [{t, ease, dirty, ch: [{v, in, out, fit: [{t, v, in, out}]}]}] - one entry
#  per authored key, one `ch` per channel. `fit` and `in` belong to the key's
#  INCOMING segment, `out` to its outgoing one.
# ---------------------------------------------------------------------------

static func _read(anim: Animation, el: ZenElement, prop: String) -> Array:
    var paths := channel_paths(el, prop)
    var authored: Array = []          # [t, ease]
    var et := _track(anim, ease_path(el, prop))
    var t0 := _track(anim, paths[0])
    if t0 < 0: return []
    if et >= 0 and anim.track_get_key_count(et) > 0:
        for i in anim.track_get_key_count(et):
            authored.append([anim.track_get_key_time(et, i),
                             String(anim.track_get_key_value(et, i))])
    else:
        for i in anim.track_get_key_count(t0):
            authored.append([anim.track_get_key_time(t0, i), RAW])

    var model: Array = []
    for a in authored:
        model.append({"t": float(a[0]), "ease": String(a[1]), "dirty": false, "ch": []})
    for path in paths:
        var tr := _track(anim, path)
        var j := 0                        # next authored key to match
        var fit: Array = []
        for i in (anim.track_get_key_count(tr) if tr >= 0 else 0):
            var bk := {"t": anim.track_get_key_time(tr, i),
                       "v": anim.bezier_track_get_key_value(tr, i),
                       "in": anim.bezier_track_get_key_in_handle(tr, i),
                       "out": anim.bezier_track_get_key_out_handle(tr, i)}
            if j < model.size() and absf(float(bk["t"]) - float(model[j]["t"])) <= T_EPS:
                bk["fit"] = fit
                fit = []
                (model[j]["ch"] as Array).append(bk)
                j += 1
            else:
                fit.append(bk)
        # A channel short of an authored key (hand-edited out of step with
        # the ease track): sample it so the model stays rectangular.
        while j < model.size():
            var t := float(model[j]["t"])
            var v := anim.bezier_track_interpolate(tr, t) if tr >= 0 else 0.0
            (model[j]["ch"] as Array).append({"t": t, "v": v, "in": Vector2.ZERO,
                "out": Vector2.ZERO, "fit": []})
            j += 1
    return model


## The segment model of `prop` (see above), for ops that move keys between
## elements or canvases (ZenClipOps). Empty when `prop` has no keys.
static func read_model(canvas: ZenCanvas, el: ZenElement, prop: String) -> Array:
    var anim := anim_of(canvas)
    return _read(anim, el, prop) if anim != null else []


static func write_model(canvas: ZenCanvas, el: ZenElement, prop: String, model: Array) -> void:
    _write(canvas, el, prop, model)


## Write the model back: clean segments verbatim, dirty ones re-derived.
static func _write(canvas: ZenCanvas, el: ZenElement, prop: String, model: Array) -> void:
    var anim := anim_of(canvas)
    var paths := channel_paths(el, prop)
    if model.is_empty():
        remove_track(canvas, el, prop)
        return
    for c in paths.size():
        var keys_out: Array = []
        for i in model.size():
            var k: Dictionary = model[i]
            var kc: Dictionary = (k["ch"] as Array)[c]
            var key := {"t": float(k["t"]), "v": float(kc["v"]),
                        "in": kc["in"], "out": kc["out"]}
            if i == 0:
                keys_out.append(key)
                continue
            var prev: Dictionary = keys_out[keys_out.size() - 1]
            if not bool(k["dirty"]):
                for f in kc["fit"]: keys_out.append(f)
                keys_out.append(key)
            elif String(k["ease"]) == RAW:
                _raw_segment(prev, key, kc)
                keys_out.append(key)
            elif float(k["t"]) - float(prev["t"]) <= STEP + T_EPS:
                # An instant step: hold, then jump (as ZenCurveBake.bake).
                key["in"] = Vector2.ZERO
                prev["out"] = Vector2.ZERO
                keys_out.append(key)
            else:
                ZenCurveBake._segment(keys_out, String(k["ease"]), float(prev["v"]),
                    float(key["v"]), float(prev["t"]), float(key["t"]))
                # _segment appended the end key with its own in-handle; keep
                # the authored key's out-handle for the next clean segment.
                keys_out[keys_out.size() - 1]["out"] = key["out"]
        _fill_bezier(anim, paths[c], keys_out)
    _fill_ease(anim, ease_path(el, prop), model)
    canvas.timeline_dirty()


## A raw segment whose ends moved: keep each handle's SLOPE, rescale its reach
## to a third of the new span - the default Godot gives a fresh key.
static func _raw_segment(prev: Dictionary, key: Dictionary, kc: Dictionary) -> void:
    var dt := float(key["t"]) - float(prev["t"])
    prev["out"] = _reach(prev["out"], dt / 3.0)
    key["in"] = _reach(kc["in"], -dt / 3.0)


static func _reach(h: Vector2, x: float) -> Vector2:
    if absf(h.x) < 1e-9: return Vector2(x, 0.0)
    return Vector2(x, h.y * x / h.x)


static func _fill_bezier(anim: Animation, path: String, ks: Array) -> void:
    var tr := _track(anim, path)
    if tr < 0:
        tr = anim.add_track(Animation.TYPE_BEZIER)
        anim.track_set_path(tr, NodePath(path))
    while anim.track_get_key_count(tr) > 0: anim.track_remove_key(tr, 0)
    for k in ks:
        anim.bezier_track_insert_key(tr, float(k["t"]), float(k["v"]), k["in"], k["out"])


static func _fill_ease(anim: Animation, path: String, model: Array) -> void:
    var tr := _track(anim, path)
    if tr < 0: tr = ZenAnimBuilder.add_discrete(anim, path)
    while anim.track_get_key_count(tr) > 0: anim.track_remove_key(tr, 0)
    for k in model:
        anim.track_insert_key(tr, float(k["t"]), String(k["ease"]))


## Channel payloads for a NEW key of value `v` at `t`, with handles following
## the curve already there so a key dropped onto a raw segment keeps its shape.
static func _new_channels(anim: Animation, el: ZenElement, prop: String, t: float,
                          v: Variant) -> Array:
    var out: Array = []
    var paths := channel_paths(el, prop)
    for c in paths.size():
        var cv: float = (v as Color)[["r", "g", "b"][c]] if v is Color else float(v)
        var slope := 0.0
        var tr := _track(anim, paths[c])
        if tr >= 0 and anim.track_get_key_count(tr) > 1:
            var h := 1e-3
            slope = (anim.bezier_track_interpolate(tr, t + h)
                     - anim.bezier_track_interpolate(tr, t - h)) / (2.0 * h)
        out.append({"v": cv, "in": Vector2(-0.1, -0.1 * slope),
                    "out": Vector2(0.1, 0.1 * slope), "fit": []})
    return out


static func _mark(model: Array, i: int) -> void:
    if i >= 0 and i < model.size(): model[i]["dirty"] = true


# ---------------------------------------------------------------------------
#  Ops. Each returns the index of the key it leaves selected (or -1).
# ---------------------------------------------------------------------------

## Key `prop` at `t` with value `v`. On an existing key this sets its value
## (and its ease, when one is given). `ease` "" picks the ease of the segment
## being split, so a key dropped mid-bounce keeps bouncing.
static func insert(canvas: ZenCanvas, el: ZenElement, prop: String, t: float,
                   v: Variant, ease := "") -> int:
    var anim := anim_of(canvas)
    if anim == null: return -1
    t = clampf(t, 0.0, anim.length)
    if ZenProps.is_stepped(prop): return _stepped_insert(canvas, el, prop, t, float(v))
    var model := _read(anim, el, prop)
    for i in model.size():
        if absf(float(model[i]["t"]) - t) <= T_EPS:
            _set_channels(model[i], v, prop)
            if not ease.is_empty(): model[i]["ease"] = ease
            _mark(model, i)
            _mark(model, i + 1)
            _write(canvas, el, prop, model)
            return i
    var at := model.size()
    for i in model.size():
        if float(model[i]["t"]) > t:
            at = i
            break
    var e := ease
    if e.is_empty():
        e = String(model[at]["ease"]) if at < model.size() else DEFAULT_EASE
    var k := {"t": t, "ease": e, "dirty": true,
              "ch": _new_channels(anim, el, prop, t, v)}
    model.insert(at, k)
    _mark(model, at + 1)
    _write(canvas, el, prop, model)
    return at


static func _set_channels(k: Dictionary, v: Variant, prop: String) -> void:
    var ch: Array = k["ch"]
    if ZenProps.is_color(prop):
        var c: Color = v
        ch[0]["v"] = c.r
        ch[1]["v"] = c.g
        ch[2]["v"] = c.b
    else:
        ch[0]["v"] = float(v)


static func set_value(canvas: ZenCanvas, el: ZenElement, prop: String, i: int,
                      v: Variant) -> int:
    var anim := anim_of(canvas)
    if ZenProps.is_stepped(prop):
        var tr := _track(anim, channel_paths(el, prop)[0])
        anim.track_set_key_value(tr, i, float(v))
        canvas.timeline_dirty()
        return i
    var model := _read(anim, el, prop)
    if i < 0 or i >= model.size(): return -1
    _set_channels(model[i], v, prop)
    _mark(model, i)
    _mark(model, i + 1)
    _write(canvas, el, prop, model)
    return i


static func set_ease(canvas: ZenCanvas, el: ZenElement, prop: String, i: int,
                     ease: String) -> int:
    if ZenProps.is_stepped(prop): return i
    var model := _read(anim_of(canvas), el, prop)
    if i < 0 or i >= model.size(): return -1
    model[i]["ease"] = ease
    _mark(model, i)
    _write(canvas, el, prop, model)
    return i


## Move key `i` to `t`, clamped between its neighbours: a drag never reorders
## keys, so a segment's identity (and its ease) is never handed to another.
static func move(canvas: ZenCanvas, el: ZenElement, prop: String, i: int, t: float) -> int:
    var n := keys(canvas, el, prop).size()
    if i < 0 or i >= n: return -1
    set_times(canvas, el, prop, [i], [t])
    return i


## Move keys `idxs` to `times` in one read and one write, each clamped between
## its neighbours as in move(). Keys moving right go rightmost first and keys
## moving left leftmost first, so none is clamped against a selected neighbour
## that is about to move out of its way.
static func set_times(canvas: ZenCanvas, el: ZenElement, prop: String, idxs: Array,
                      times: Array) -> void:
    var anim := anim_of(canvas)
    if anim == null or idxs.is_empty(): return
    var cur: Array = []                   # current times, kept up to date
    var model: Array = []
    var tr := -1
    if ZenProps.is_stepped(prop):
        tr = _track(anim, channel_paths(el, prop)[0])
        if tr < 0: return
        for i in anim.track_get_key_count(tr): cur.append(anim.track_get_key_time(tr, i))
    else:
        model = _read(anim, el, prop)
        for k in model: cur.append(float(k["t"]))
    var moves: Array = []                 # [idx, t]
    for j in idxs.size():
        var i := int(idxs[j])
        if i >= 0 and i < cur.size(): moves.append([i, float(times[j])])
    moves.sort_custom(func(a, b):
        var ra: bool = a[1] > cur[a[0]]
        var rb: bool = b[1] > cur[b[0]]
        if ra != rb: return ra            # right-movers first; they never meet left-movers
        return a[0] > b[0] if ra else a[0] < b[0])
    for m in moves:
        var i: int = m[0]
        var lo := float(cur[i - 1]) + STEP if i > 0 else 0.0
        var hi := float(cur[i + 1]) - STEP if i + 1 < cur.size() else anim.length
        cur[i] = clampf(m[1], lo, maxf(lo, hi))
        if tr >= 0:
            anim.track_set_key_time(tr, i, cur[i])
            continue
        model[i]["t"] = cur[i]
        for ch in model[i]["ch"]: ch["fit"] = []  # rebaked below
        _mark(model, i)
        _mark(model, i + 1)
    if tr >= 0: canvas.timeline_dirty()
    else: _write(canvas, el, prop, model)


static func remove(canvas: ZenCanvas, el: ZenElement, prop: String, i: int) -> int:
    var anim := anim_of(canvas)
    if ZenProps.is_stepped(prop):
        var tr := _track(anim, channel_paths(el, prop)[0])
        if tr < 0 or i < 0 or i >= anim.track_get_key_count(tr): return -1
        anim.track_remove_key(tr, i)
        var left := anim.track_get_key_count(tr)
        if left == 0: anim.remove_track(tr)
        canvas.timeline_dirty()
        return mini(i, left - 1)
    var model := _read(anim, el, prop)
    if i < 0 or i >= model.size(): return -1
    model.remove_at(i)
    if i < model.size():
        if i == 0:
            for ch in model[0]["ch"]: ch["fit"] = []   # no incoming segment now
        else:
            _mark(model, i)
    _write(canvas, el, prop, model)
    return mini(i, model.size() - 1)


## Drop every track of `prop` - its channels and its ease track.
static func remove_track(canvas: ZenCanvas, el: ZenElement, prop: String) -> void:
    var anim := anim_of(canvas)
    if anim == null: return
    var paths := channel_paths(el, prop)
    paths.append(ease_path(el, prop))
    for p in paths:
        var tr := _track(anim, p)
        if tr >= 0: anim.remove_track(tr)
    canvas.timeline_dirty()


## Auto-key: key `prop` at the playhead. The first key of a prop also keys t=0
## with the base pose, so the property holds its old value up to the edit
## instead of jumping to the new one from the start (as in the C).
static func key_at_playhead(canvas: ZenCanvas, el: ZenElement, prop: String, t: float,
                            v: Variant) -> int:
    if not has_track(canvas, el, prop) and t > T_EPS:
        var base: Variant = el.base_color(prop) if ZenProps.is_color(prop) \
            else el.base_scalar(prop)
        insert(canvas, el, prop, 0.0, base, DEFAULT_EASE)
    return insert(canvas, el, prop, t, v)


## Scale every key time of `an`, and every bezier handle's reach, by `k`.
## The length is the caller's.
static func scale_anim(an: Animation, k: float) -> void:
    if an == null or is_equal_approx(k, 1.0) or k <= 0.0: return
    for tr in an.get_track_count():
        var n := an.track_get_key_count(tr)
        # Growing moves the last key first, shrinking the first, so no key is
        # ever moved onto a neighbour that has not moved yet.
        var order := range(n - 1, -1, -1) if k > 1.0 else range(n)
        for i in order:
            an.track_set_key_time(tr, i, an.track_get_key_time(tr, i) * k)
            if an.track_get_type(tr) == Animation.TYPE_BEZIER:
                var hi := an.bezier_track_get_key_in_handle(tr, i)
                var ho := an.bezier_track_get_key_out_handle(tr, i)
                an.bezier_track_set_key_in_handle(tr, i, Vector2(hi.x * k, hi.y))
                an.bezier_track_set_key_out_handle(tr, i, Vector2(ho.x * k, ho.y))


# ---------------------------------------------------------------------------
#  Stepped props: a discrete value track, no segments.
# ---------------------------------------------------------------------------

static func _stepped_keys(anim: Animation, path: String) -> Array:
    var out: Array = []
    var tr := _track(anim, path)
    if tr < 0: return out
    for i in anim.track_get_key_count(tr):
        out.append({"t": anim.track_get_key_time(tr, i),
                    "v": float(anim.track_get_key_value(tr, i)), "ease": "step"})
    return out


static func _stepped_insert(canvas: ZenCanvas, el: ZenElement, prop: String, t: float,
                            v: float) -> int:
    var anim := anim_of(canvas)
    var path := String(channel_paths(el, prop)[0])
    var tr := _track(anim, path)
    if tr < 0: tr = ZenAnimBuilder.add_discrete(anim, path)
    var at := anim.track_find_key(tr, t, Animation.FIND_MODE_APPROX)
    if at >= 0: anim.track_set_key_value(tr, at, v)
    else: at = anim.track_insert_key(tr, t, v)
    canvas.timeline_dirty()
    return at
