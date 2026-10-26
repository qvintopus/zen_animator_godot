@tool
class_name ZenClipOps
extends RefCounted
##
## Inserting an EFFECT - any other animation - into a scene. An effect is an
## ordinary ZenCanvas (anims/effects by convention) whose keys are laid in from
## time `t`, so the effect's 0 lands at `t`. Each of its elements is MAPPED:
## added as a new element, driving an existing element of the same kind
## (absolute, or relative to that element's own values), or skipped. Where a
## driven element has keys of its own inside the effect's span, conflicts()
## reports them and the map says how to settle them: merge, replace or push.
## There is no second key format: keys travel as ZenKeyOps's segment model, so
## values, bezier handles and eases survive; where they land between existing
## keys the segments they touch are re-derived from their ease.
##
## A speed ratio is ZenDocOps.retime on the opened effect before the insert
## (the file on disk is never touched). Signals are not carried: an effect is
## timeline keys and elements only.
##
## Extracting an effect needs nothing here: it is a duplicated scene, cut down
## (see the scene editor's Extract guide and ZenDocOps.trim).
##

const T_EPS := ZenKeyOps.T_EPS
const STEP := ZenKeyOps.STEP
## Props a RELATIVE mapping moves by the target's own value at the start...
const ADD := ["pos_x", "pos_y", "rot"]
## ...and props it scales by it (the effect's sizes become proportions).
const MUL := ["scale", "w", "h", "size"]
const RESOLVE := ["merge", "replace", "push"]


# ---------------------------------------------------------------------------
#  Model helpers (pure: arrays in, arrays out)
# ---------------------------------------------------------------------------

static func shift(model: Array, dt: float) -> Array:
    var out: Array = []
    for src in model:
        var k: Dictionary = (src as Dictionary).duplicate(true)
        k["t"] = float(k["t"]) + dt
        for ch in k["ch"]:
            for f in ch["fit"]: f["t"] = float(f["t"]) + dt
        out.append(k)
    return out


## Add `dv` to every value of a scalar model.
static func offset(model: Array, dv: float) -> Array:
    var out: Array = []
    for src in model:
        var k: Dictionary = (src as Dictionary).duplicate(true)
        for ch in k["ch"]:
            ch["v"] = float(ch["v"]) + dv
            for f in ch["fit"]: f["v"] = float(f["v"]) + dv
        out.append(k)
    return out


## Multiply every value of a scalar model, and every handle's rise, by `k`.
static func scale_values(model: Array, k: float) -> Array:
    var out: Array = []
    for src in model:
        var key: Dictionary = (src as Dictionary).duplicate(true)
        for ch in key["ch"]:
            for p in [ch] + (ch["fit"] as Array):
                p["v"] = float(p["v"]) * k
                p["in"] = Vector2(p["in"].x, p["in"].y * k)
                p["out"] = Vector2(p["out"].x, p["out"].y * k)
        out.append(key)
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
#  Props and text
# ---------------------------------------------------------------------------

## The keyable props `el` owns.
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
#  Mapping: which element each effect row drives
#
#  map: {effect elem_name: {to, relative, resolve, stepped}} - see entry().
#  `to` "" adds the row as a new element, "-" skips it, a name drives that
#  existing element of the same kind (one effect row per target).
# ---------------------------------------------------------------------------

## The map entry of effect row `nm`, defaults filled in.
static func entry(map: Dictionary, nm: String) -> Dictionary:
    var e := {"to": "", "relative": true, "resolve": "merge", "stepped": false}
    e.merge(map.get(nm, {}), true)
    return e


## The rows of `dest` effect row `r` can drive: the same kind.
static func targets_for(dest: ZenCanvas, r: ZenElement) -> Array:
    return ZenElemOps.rows(dest).filter(func(d): return (d as ZenElement).zen_kind() == r.zen_kind())


## A first map: a row whose name and kind match an element of `dest` drives
## it, every other row is new.
static func suggest(dest: ZenCanvas, fx: ZenCanvas) -> Dictionary:
    var out := {}
    for r in ZenElemOps.rows(fx):
        var d := ZenElemOps.find(dest, (r as ZenElement).elem_name)
        if d != null and d.zen_kind() == (r as ZenElement).zen_kind():
            out[(r as ZenElement).elem_name] = {"to": d.elem_name}
    return out


## [node half, prop] for every keyed prop effect row `r` writes onto an
## existing element: stepped ones (a text's words, a shape) only with `stepped`.
static func carried(fx: ZenCanvas, r: ZenElement, stepped: bool) -> Array:
    var out: Array = []
    for h in ZenElemOps.halves(fx, r):
        for prop in ZenKeyOps.keyed_props(fx, h as ZenElement):
            if stepped or not ZenProps.is_stepped(prop): out.append([h, prop])
    return out


## [first, last] key time of what row `r` writes, in effect time;
## Vector2(-1, -1) when it writes nothing.
static func row_span(fx: ZenCanvas, r: ZenElement, stepped := true) -> Vector2:
    var a := INF
    var b := -INF
    for hp in carried(fx, r, stepped):
        var ks := ZenKeyOps.keys(fx, hp[0] as ZenElement, String(hp[1]))
        if ks.is_empty(): continue
        a = minf(a, float(ks[0]["t"]))
        b = maxf(b, float(ks[ks.size() - 1]["t"]))
    return Vector2(-1, -1) if is_inf(a) else Vector2(a, b)


## The node of `el`'s element that owns `prop` (a global splits its props).
static func _half(canvas: ZenCanvas, el: ZenElement, prop: String) -> ZenElement:
    for h in ZenElemOps.halves(canvas, el):
        if (h as ZenElement).owns(prop): return h
    return null


## The target's own key times on `props`, strictly inside (a, b).
static func _inside(dest: ZenCanvas, target: ZenElement, props: Array, a: float, b: float) -> Array:
    var out: Array = []
    for prop in props:
        var h := _half(dest, target, prop)
        if h == null: continue
        for k in ZenKeyOps.keys(dest, h, prop):
            var kt := float(k["t"])
            if kt > a + T_EPS and kt < b - T_EPS: out.append(kt)
    out.sort()
    return out


static func _prop_names(pairs: Array) -> Array:
    var out: Array = []
    for hp in pairs:
        if not out.has(hp[1]): out.append(hp[1])
    return out


## Where a mapped insert lands among the target's own keys: for each target
## with own keys strictly inside its row's span (on the props the row writes),
## {row, props, keys, first, last}. Keys AT the span's ends are not counted:
## the effect's end keys simply replace them. Empty when nothing overlaps.
static func conflicts(dest: ZenCanvas, fx: ZenCanvas, t: float, map: Dictionary) -> Dictionary:
    var out := {}
    for r in ZenElemOps.rows(fx):
        var e := entry(map, (r as ZenElement).elem_name)
        var target := _target(dest, r as ZenElement, e)
        if target == null: continue
        var span := row_span(fx, r as ZenElement, e["stepped"])
        if span.x < 0.0: continue
        var pairs := carried(fx, r as ZenElement, e["stepped"])
        var props: Array = []
        var times: Array = []
        for prop in _prop_names(pairs):
            var ts := _inside(dest, target, [prop], t + span.x, t + span.y)
            if ts.is_empty(): continue
            props.append(prop)
            times.append_array(ts)
        if times.is_empty(): continue
        times.sort()
        out[target.elem_name] = {"row": (r as ZenElement).elem_name, "props": props,
            "keys": times.size(), "first": times[0], "last": times[times.size() - 1]}
    return out


## The earliest start at or after `t` at which no mapped row lands among its
## target's own keys - the "move the effect out of the way" proposal.
static func clear_after(dest: ZenCanvas, fx: ZenCanvas, t: float, map: Dictionary) -> float:
    var rows: Array = []                  # [span, own times]
    var starts: Array = [t]
    for r in ZenElemOps.rows(fx):
        var e := entry(map, (r as ZenElement).elem_name)
        var target := _target(dest, r as ZenElement, e)
        if target == null: continue
        var span := row_span(fx, r as ZenElement, e["stepped"])
        if span.x < 0.0: continue
        var own := _inside(dest, target, _prop_names(carried(fx, r as ZenElement, e["stepped"])), -INF, INF)
        rows.append([span, own])
        for k in own:
            if float(k) - span.x > t: starts.append(float(k) - span.x)
    starts.sort()
    for s in starts:
        var clean := true
        for row in rows:
            var span: Vector2 = row[0]
            for k in row[1]:
                if float(k) > s + span.x + T_EPS and float(k) < s + span.y - T_EPS:
                    clean = false
                    break
            if not clean: break
        if clean: return s
    return t


## The existing element `e` sends row `r` to, or null (new, skipped, gone, or
## of another kind).
static func _target(dest: ZenCanvas, r: ZenElement, e: Dictionary) -> ZenElement:
    var to := String(e["to"])
    if to == "" or to == "-": return null
    var d := ZenElemOps.find(dest, to)
    return d if d != null and d.zen_kind() == r.zen_kind() else null


# ---------------------------------------------------------------------------
#  Insert
# ---------------------------------------------------------------------------

## Lay `fx` into `dest` from time `t`, row by row as `map` says (see entry()):
## a new element (named `prefix` + its name, made unique, at the front of the
## draw order), an existing element it drives, or nothing. `dest` is
## lengthened when the effect ends past it. Returns the rows written to.
static func paste(dest: ZenCanvas, fx: ZenCanvas, t: float, prefix := "", map := {}) -> Array:
    if not dest.edit_anim.is_empty() or fx == null or not fx.edit_anim.is_empty(): return []
    var out: Array = []
    var end := 0.0
    var added := false
    for r in ZenElemOps.rows(fx):
        var e := entry(map, (r as ZenElement).elem_name)
        if e["to"] == "-": continue
        if e["to"] != "":
            var target := _target(dest, r as ZenElement, e)
            if target == null: continue
            end = maxf(end, _drive(dest, fx, r as ZenElement, target, t, e))
            out.append(ZenElemOps.row_of(dest, target))
            continue
        var nm := ZenElemOps.unique_name(dest, prefix + (r as ZenElement).elem_name)
        var at := ZenElemOps._end_of_elements(dest)
        var made: ZenElement = null
        for h in ZenElemOps.halves(fx, r as ZenElement):
            var n := (h as ZenElement).duplicate() as ZenElement
            n.tracks = {}
            n.elem_name = nm
            n.name = ZenElemOps._node_for(h as ZenElement, nm)
            dest.add_child(n)
            dest.move_child(n, at)
            at += 1
            n.owner = ZenElemOps._owner(dest)
            if n is ZenText: _repool(n as ZenText, h as ZenText, dest)
            end = maxf(end, _apply(dest, fx, h as ZenElement, n, t))
            made = n
        added = true
        out.append(ZenElemOps.row_of(dest, made))
    if added: ZenElemFactory.assign_z(dest)
    if end > dest.duration: ZenDocOps.set_duration(dest, end)
    dest.timeline_dirty()
    return out


## The names paste() would give `fx`'s NEW elements in `dest`, in order (a
## preview: the effect's own names are already distinct).
static func names_for(dest: ZenCanvas, fx: ZenCanvas, prefix := "", map := {}) -> Array:
    var out: Array = []
    for r in ZenElemOps.rows(fx):
        if entry(map, (r as ZenElement).elem_name)["to"] != "": continue
        out.append(ZenElemOps.unique_name(dest, prefix + (r as ZenElement).elem_name))
    return out


## Copy every track of effect node `h` onto the new node `to`, shifted to `t`.
## Returns the time of the last key written.
static func _apply(dest: ZenCanvas, fx: ZenCanvas, h: ZenElement, to: ZenElement, t: float) -> float:
    var end := 0.0
    for prop in _props(h):
        if not to.owns(prop) or not ZenKeyOps.has_track(fx, h, prop): continue
        if ZenProps.is_stepped(prop):
            end = maxf(end, _apply_stepped(dest, fx, h, to, prop, t))
            continue
        var m := shift(ZenKeyOps.read_model(fx, h, prop), t)
        var cur := ZenKeyOps.read_model(dest, to, prop)
        ZenKeyOps.write_model(dest, to, prop, merge(cur, m) if not cur.is_empty() else m)
        end = maxf(end, last_t(m))
    return end


static func _apply_stepped(dest: ZenCanvas, fx: ZenCanvas, h: ZenElement, to: ZenElement,
                           prop: String, t: float) -> float:
    var end := 0.0
    for k in ZenKeyOps.keys(fx, h, prop):
        var v := float(k["v"])
        if prop == "string": v = _map_string(fx, dest, h, int(v))
        # A stepped insert clamps to the length: make room first.
        if float(k["t"]) + t > dest.duration: ZenDocOps.set_duration(dest, float(k["t"]) + t)
        ZenKeyOps.insert(dest, to, prop, float(k["t"]) + t, v)
        end = maxf(end, float(k["t"]) + t)
    return end


## Effect row `r` drives the existing `target`: its own keys inside the span
## are settled first (e.resolve), then the effect's keys merge in - re-based on
## the target's own values when e.relative. Returns the last key time written.
static func _drive(dest: ZenCanvas, fx: ZenCanvas, r: ZenElement, target: ZenElement, t: float,
                   e: Dictionary) -> float:
    var span := row_span(fx, r, e["stepped"])
    if span.x < 0.0: return 0.0
    # Read every model and pivot before the resolve moves the target's keys.
    var plan: Array = []                  # [fx half, prop, target half, shifted model]
    for hp in carried(fx, r, e["stepped"]):
        var prop := String(hp[1])
        var to := _half(dest, target, prop)
        if to == null: continue
        var m: Array = []
        if not ZenProps.is_stepped(prop):
            m = shift(ZenKeyOps.read_model(fx, hp[0] as ZenElement, prop), t)
            if m.is_empty(): continue
            if e["relative"]: m = _rebase(m, prop, _value_at(dest, to, prop, float(m[0]["t"])))
        plan.append([hp[0], prop, to, m, _value_at(dest, to, prop, 0.0)])
    var a := t + span.x
    var b := t + span.y
    match String(e["resolve"]):
        "replace": _clear(dest, target, _prop_names(plan), a, b)
        "push": _push(dest, target, a, b - a)
    var end := 0.0
    for p in plan:
        var prop: String = p[1]
        var to: ZenElement = p[2]
        if ZenProps.is_stepped(prop):
            _pin(dest, to, prop, a, p[4], p[4])
            end = maxf(end, _apply_stepped(dest, fx, p[0] as ZenElement, to, prop, t))
            continue
        var m: Array = p[3]
        _pin(dest, to, prop, float(m[0]["t"]), p[4], ZenKeyOps._value(m[0], prop))
        var cur := ZenKeyOps.read_model(dest, to, prop)
        ZenKeyOps.write_model(dest, to, prop, merge(cur, m) if not cur.is_empty() else m)
        end = maxf(end, last_t(m))
    return end


## Relative: position and rotation move by the target's own value, sizes
## scale by it; alpha and colours stay as keyed.
static func _rebase(m: Array, prop: String, pivot: Variant) -> Array:
    if pivot is Color: return m
    var v0 := float(m[0]["ch"][0]["v"])
    if ADD.has(prop): return offset(m, float(pivot) - v0)
    if MUL.has(prop):
        if absf(v0) > 1e-6: return scale_values(m, float(pivot) / v0)
        return offset(m, float(pivot) - v0)
    return m


## Before `t` the target keeps what it had: with no own key at or before `t`
## the first written key would hold from 0, so 0 is keyed with the old value -
## and held up to `t` when the effect starts elsewhere (`first`), so it steps
## there instead of drifting over from 0.
static func _pin(dest: ZenCanvas, to: ZenElement, prop: String, t: float, old: Variant,
                 first: Variant) -> void:
    if t <= T_EPS: return
    var ks := ZenKeyOps.keys(dest, to, prop)
    if not ks.is_empty() and float(ks[0]["t"]) <= t + T_EPS: return
    ZenKeyOps.insert(dest, to, prop, 0.0, old)
    if not ZenDocOps._same(old, first) and t > 2.0 * STEP:
        ZenKeyOps.insert(dest, to, prop, t - STEP, old)


## Drop the target's own keys strictly inside (a, b) on `props`.
static func _clear(dest: ZenCanvas, target: ZenElement, props: Array, a: float, b: float) -> void:
    for prop in props:
        var h := _half(dest, target, prop)
        if h == null: continue
        var ks := ZenKeyOps.keys(dest, h, prop)
        for i in range(ks.size() - 1, -1, -1):
            var kt := float(ks[i]["t"])
            if kt > a + T_EPS and kt < b - T_EPS: ZenKeyOps.remove(dest, h, prop, i)


## Every own key of `target` after `a` (all its props, so they stay in step)
## moves `dt` later; the scene grows to keep them.
static func _push(dest: ZenCanvas, target: ZenElement, a: float, dt: float) -> void:
    if dt <= 0.0: return
    var moves: Array = []                 # [half, prop, idxs, times]
    var last := 0.0
    for h in ZenElemOps.halves(dest, target):
        for prop in ZenKeyOps.keyed_props(dest, h as ZenElement):
            var ks := ZenKeyOps.keys(dest, h as ZenElement, prop)
            var idxs: Array = []
            var times: Array = []
            for i in ks.size():
                if float(ks[i]["t"]) <= a + T_EPS: continue
                idxs.append(i)
                times.append(float(ks[i]["t"]) + dt)
                last = maxf(last, float(ks[i]["t"]) + dt)
            if not idxs.is_empty(): moves.append([h, prop, idxs, times])
    if last > dest.duration: ZenDocOps.set_duration(dest, last)
    for mv in moves: ZenKeyOps.set_times(dest, mv[0] as ZenElement, String(mv[1]), mv[2], mv[3])


## What `prop` of node `el` plays at `t`: its track, else its base pose.
static func _value_at(canvas: ZenCanvas, el: ZenElement, prop: String, t: float) -> Variant:
    if ZenProps.is_stepped(prop):
        var ks := ZenKeyOps.keys(canvas, el, prop)
        if ks.is_empty(): return el.base_scalar(prop)
        var v := float(ks[0]["v"])
        for k in ks:
            if float(k["t"]) <= t + T_EPS: v = float(k["v"])
        return v
    var anim := ZenKeyOps.anim_of(canvas)
    var vals: Array = []
    for path in ZenKeyOps.channel_paths(el, prop):
        var tr := ZenKeyOps._track(anim, path) if anim != null else -1
        if tr < 0 or anim.track_get_key_count(tr) == 0:
            return el.base_color(prop) if ZenProps.is_color(prop) else el.base_scalar(prop)
        vals.append(anim.bezier_track_interpolate(tr, t))
    if ZenProps.is_color(prop): return Color(vals[0], vals[1], vals[2], 1.0)
    return vals[0]
