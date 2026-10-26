@tool
class_name ZenClipOps
extends RefCounted
##
## Inserting an EFFECT - any other animation - into a scene. An effect is an
## ordinary ZenCanvas (anims/effects by convention): its elements are added as
## new ones and its keys laid in from time `t`, so the effect's 0 lands at `t`.
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
#  Insert
# ---------------------------------------------------------------------------

## Lay `fx` into `dest` from time `t`: its elements are added as new ones
## (named `prefix` + their name, made unique) at the front of the draw order.
## `dest` is lengthened when the effect ends past it. Returns the new rows.
static func paste(dest: ZenCanvas, fx: ZenCanvas, t: float, prefix := "") -> Array:
    if not dest.edit_anim.is_empty() or fx == null or not fx.edit_anim.is_empty(): return []
    var out: Array = []
    var end := 0.0
    for r in ZenElemOps.rows(fx):
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
        out.append(ZenElemOps.row_of(dest, made))
    ZenElemFactory.assign_z(dest)
    if end > dest.duration: ZenDocOps.set_duration(dest, end)
    dest.timeline_dirty()
    return out


## The names paste() would give `fx`'s elements in `dest`, in order (a
## preview: the effect's own names are already distinct).
static func names_for(dest: ZenCanvas, fx: ZenCanvas, prefix := "") -> Array:
    var out: Array = []
    for r in ZenElemOps.rows(fx):
        out.append(ZenElemOps.unique_name(dest, prefix + (r as ZenElement).elem_name))
    return out


## Copy every track of effect node `h` onto `to`, shifted to `t`. Returns the
## time of the last key written.
static func _apply(dest: ZenCanvas, fx: ZenCanvas, h: ZenElement, to: ZenElement, t: float) -> float:
    var end := 0.0
    for prop in _props(h):
        if not to.owns(prop) or not ZenKeyOps.has_track(fx, h, prop): continue
        if ZenProps.is_stepped(prop):
            for k in ZenKeyOps.keys(fx, h, prop):
                var v := float(k["v"])
                if prop == "string": v = _map_string(fx, dest, h, int(v))
                # A stepped insert clamps to the length: make room first.
                if float(k["t"]) + t > dest.duration: ZenDocOps.set_duration(dest, float(k["t"]) + t)
                ZenKeyOps.insert(dest, to, prop, float(k["t"]) + t, v)
                end = maxf(end, float(k["t"]) + t)
            continue
        var m := shift(ZenKeyOps.read_model(fx, h, prop), t)
        var cur := ZenKeyOps.read_model(dest, to, prop)
        ZenKeyOps.write_model(dest, to, prop, merge(cur, m) if not cur.is_empty() else m)
        end = maxf(end, last_t(m))
    return end
