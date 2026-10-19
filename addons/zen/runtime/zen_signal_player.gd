@tool
class_name ZenSignalPlayer
extends RefCounted
##
## One running Zen signal: the port of AnimSignalPlayer (anim.c:1495-1816).
##
## A signal is a named TRANSITION, not an animation. Firing it captures the
## pose that is on screen right now and eases each targeted property from that
## capture into the signal's authored keys over `length` seconds. That captured
## pose is the IMPLICIT KEY AT u=0, and it is the whole reason a signal reads as
## a transition rather than a jump.
##
## A RefCounted, like ZenSampler and ZenEasing: it is a value owned by the bus,
## with no business in the scene tree.
##
## TWO THINGS THAT LOOK LIKE BUGS AND ARE NOT:
##
##   - Key times are NORMALIZED u in 0..1 of `length`, NOT seconds, even though
##     the key dictionaries are structurally identical to timeline keys (anim.h
##     :365). `length <= 0` means "instant": u snaps to 1 and the signal lands
##     on its final key. Never hand these keys to ZenSampler.
##   - eval() returns a Variant, null meaning "not driven". The C uses an
##     out-param plus a bool because EVERY float is a legal property value, so
##     no sentinel float can mean "no". Same reason here.
##

## Parallel to the C's ANIM_SIG_* caps. Not enforced - Godot arrays grow - but
## kept as documentation of the authoring limits the .cfg format assumes.
const KEYS_MAX := 8

var sig: Dictionary = {}          ## the authored signal (ZenCfgParse shape)
var clock := 0.0
var playing := false
## True once a TERMINAL signal has run to its end: the player keeps answering
## with its final (u=1) pose instead of handing the elements back to the
## timeline. The canvas has stopped by then (ZenSignalBus.advance), so the
## end pose of e.g. pause_menu's `exit` is what stays on screen rather than
## the frozen timeline pose underneath it. Cleared by start() and release().
var held := false
var seq := 0                      ## stage sequence index, 0 = not sequenced
var params: Dictionary = {}       ## {"pos": Vector2}; presence of "pos" IS has_pos

## The captured live pose, by target index: scalars and colours.
var _from_value: Array = []
var _from_color: Array = []
## The captured live geometry, by pos-param index:
## {"px","py","w","h","scale","corner"}.
var _from_pose: Array = []
## One warning per player for the deferred corner branch, not one per frame.
var _warned_corner := false


func has_pos() -> bool:
    return params.has("pos")


func pos() -> Vector2:
    return params.get("pos", Vector2.ZERO)


## Normalized progress. `length <= 0` is instant: land on the final key.
func u() -> float:
    var len_s := float(sig.get("length", 0.0))
    if len_s <= 0.0: return 1.0
    return clampf(clock / len_s, 0.0, 1.0)


## Fire. `capture` is a Callable(elem_name: String, prop: String) -> Variant
## returning the PLAIN timeline value (float or Color) - the caller owns element
## lookup, so this class never touches the scene tree.
##
## The capture MUST read the plain path, with no override installed: a signal
## captures the timeline pose and must never sample a previous signal's
## override, or re-firing mid-flight would compound (anim.c:1522-1524).
func start(signal_data: Dictionary, p: Dictionary, seq_index: int,
           capture: Callable) -> void:
    sig = signal_data
    clock = 0.0
    playing = false
    held = false
    seq = seq_index
    params = p.duplicate()
    _from_value = []
    _from_color = []
    _from_pose = []
    if sig.is_empty(): return

    var targets: Array = sig.get("targets", [])
    var pos_params: Array = sig.get("pos_params", [])
    var seq_targets: Array = sig.get("seq_targets", [])
    # A signal driving NOTHING does not start. `signal enter` in
    # mouse_ripple.cfg is exactly this (anim.c:1505-1507). A signal with only
    # posparams or only seqtargets DOES start: it has a pose to ease from and a
    # length to run.
    if targets.is_empty() and pos_params.is_empty() and seq_targets.is_empty():
        return

    for tg in targets:
        var prop := String(tg["prop"])
        var v: Variant = capture.call(String(tg["elem"]), prop)
        if ZenProps.is_color(prop):
            _from_value.append(0.0)
            _from_color.append(v if v is Color else Color(0, 0, 0, 0))
        else:
            _from_value.append(float(v) if v is float or v is int else 0.0)
            _from_color.append(Color(0, 0, 0, 0))

    for pp in pos_params:
        var nm := String(pp["elem"])
        var pose := {"px": 0.0, "py": 0.0, "w": 0.0, "h": 0.0,
                     "scale": 1.0, "corner": false}
        # The geometry a binding eases FROM (anim.c:1537-1543).
        for slot in [["px", "pos_x"], ["py", "pos_y"], ["w", "w"],
                     ["h", "h"], ["scale", "scale"]]:
            var v: Variant = capture.call(nm, String(slot[1]))
            if v is float or v is int: pose[String(slot[0])] = float(v)
        var cm: Variant = capture.call(nm, "corner_mode")
        pose["corner"] = cm is bool and cm
        _from_pose.append(pose)

    playing = true


## Advance. The clock REACHING length ends playback, so a `length = 0` signal
## is done on its first update - which is why the terminal edge has to be
## checked in the same call that updates (anim_stage.c:310-328).
func update(dt: float) -> void:
    if not playing or sig.is_empty(): return
    clock += dt
    var len_s := float(sig.get("length", 0.0))
    if clock >= len_s:
        clock = len_s
        playing = false
        held = bool(sig.get("terminal", false))


func is_done() -> bool:
    return not playing


## Still contributing to the pose: running, or holding a terminal end pose.
func is_overriding() -> bool:
    return (playing or held) and not sig.is_empty()


## Drop a held end pose, handing the elements back to the timeline.
func release() -> void:
    held = false


## The scalar value this signal drives for (elem, prop), or null if it drives
## none. Pos-param bindings are tried FIRST: they replace the authored value
## outright (anim.c:1683), and `ripple_old` has both a posparam and a plain `w`
## target on the same element, where the posparam must win.
func eval(elem: String, prop: String) -> Variant:
    if not is_overriding(): return null

    var pv: Variant = _pos_param_eval(elem, prop)
    if pv != null: return pv

    var i := _target_index(elem, prop)
    if i < 0: return null
    var keys: Array = sig["targets"][i]["keys"]
    # A target with no keys has nothing to drive it with: NOT driven, so the
    # plain track (and the loop blend) stay in charge (anim.c:1687).
    if keys.is_empty(): return null
    return _keyed(float(_from_value[i]), keys, u())


## The colour this signal drives, or null. `alpha` is supplied by the caller
## because colour props carry NO alpha of their own - it always rides a
## separate scalar track (anim.c:556).
func eval_color(elem: String, prop: String, alpha: float) -> Variant:
    if not is_overriding(): return null
    var i := _target_index(elem, prop)
    if i < 0: return null
    var keys: Array = sig["targets"][i]["keys"]
    if keys.is_empty(): return null
    var c: Color = _keyed_color(_from_color[i], keys, u())
    return Color(c.r, c.g, c.b, alpha)


## seq * seq_mult * env(u), added ON TOP of whatever else drives the property
## (anim.c:1747-1781). Scalar props only. No env keys means a constant full
## offset.
func seq_offset(elem: String, prop: String) -> float:
    if not is_overriding(): return 0.0
    if not bool(sig.get("uses_seq", false)): return 0.0
    var mult := float(sig.get("seq_mult", 0.0))
    if seq == 0 or mult == 0.0: return 0.0

    var matched := false
    for st in sig.get("seq_targets", []):
        if String(st["elem"]) == elem and String(st["prop"]) == prop:
            matched = true
            break
    if not matched: return 0.0

    var env := 1.0
    var keys: Array = sig.get("seq_keys", [])
    if not keys.is_empty():
        env = _keyed(0.0, keys, u())
    return float(seq) * mult * env


## The spawn-anchor translation: a CONSTANT offset moving the element so its
## bound point at fire time lands on the emitted position (anim.c:1783-1816).
##
## This is what "born at the cursor" means - the element keeps its authored
## path and the whole path is translated, which is why anchor mode makes
## _pos_param_eval return null instead of replacing the slot. POS props only;
## size is left to the authored animation. Only the FIRST binding of an element
## is honoured: anchoring one element to two cursor points is contradictory.
func pos_anchor(elem: String, prop: String) -> float:
    if not is_overriding(): return 0.0
    if not bool(sig.get("uses_pos", false)): return 0.0
    if not bool(sig.get("pos_anchor", false)): return 0.0
    if not has_pos(): return 0.0
    if not ZenProps.is_pos(prop): return 0.0

    var pos_params: Array = sig.get("pos_params", [])
    for i in pos_params.size():
        if String(pos_params[i]["elem"]) != elem: continue
        if i >= _from_pose.size(): return 0.0
        var fp: Dictionary = _from_pose[i]
        var px := float(fp["px"])
        var py := float(fp["py"])
        if bool(fp["corner"]):
            # The bound point is a corner, so shift by half the fire-time size.
            var sc := float(fp["scale"])
            var s := -1.0 if int(pos_params[i]["slot"]) == 0 else 1.0
            px += s * float(fp["w"]) * sc * 0.5
            py += s * float(fp["h"]) * sc * 0.5
        return (pos().x - px) if prop == "pos_x" else (pos().y - py)
    return 0.0


# ---------------------------------------------------------------------------
#  Internals
# ---------------------------------------------------------------------------

func _target_index(elem: String, prop: String) -> int:
    var targets: Array = sig.get("targets", [])
    for i in targets.size():
        if String(targets[i]["elem"]) == elem and String(targets[i]["prop"]) == prop:
            return i
    return -1


## Pos-param binding for (elem, prop), or null when nothing binds it.
##
## Anchor mode deliberately returns null: it does NOT replace the slot, it lets
## the authored value through and adds a constant offset later (anim.c:1621).
##
## The CORNER branch is deferred - no bundled document binds a corner, and the C
## itself flags the mode as limited (fire-time pose, no live scale tracking).
## `corner_mode` is carried as data so nothing is lost at import.
func _pos_param_eval(elem: String, prop: String) -> Variant:
    if not bool(sig.get("uses_pos", false)): return null
    if not has_pos(): return null
    if bool(sig.get("pos_anchor", false)): return null
    if not ZenProps.is_pos(prop) and not ZenProps.is_size(prop): return null

    var pos_params: Array = sig.get("pos_params", [])
    var i_center := -1
    var saw_corner := false
    for i in pos_params.size():
        if String(pos_params[i]["elem"]) != elem: continue
        if i < _from_pose.size() and bool(_from_pose[i]["corner"]):
            saw_corner = true              # corner binding: deferred
            continue
        i_center = i
    if i_center < 0:
        # Loud, not silent: a corner binding would animate as if the signal
        # had no posparam at all, which looks like a content bug.
        if saw_corner and not _warned_corner:
            _warned_corner = true
            push_warning("zen: pos-param CORNER binding on '%s' is not implemented; "
                         % elem + "the element keeps its authored position")
        return null
    if not ZenProps.is_pos(prop): return null        # centre drives POS only

    var fp: Dictionary = _from_pose[i_center]
    var live := float(fp["px"]) if prop == "pos_x" else float(fp["py"])
    return _pos_binding_point(i_center, live, prop == "pos_x", u())


## The eased point a binding drives its centre to: each key's target is
## (emitted pos + the key's offset), blended from the live capture over u.
func _pos_binding_point(i: int, live: float, is_x: bool, uu: float) -> float:
    var pp: Dictionary = sig["pos_params"][i]
    var base := pos().x if is_x else pos().y
    var keys: Array = []
    for k in pp.get("keys", []):
        var off: Vector2 = k["off"]
        keys.append({"t": k["t"], "v": base + (off.x if is_x else off.y),
                     "ease": k["ease"]})
    return _keyed(live, keys, uu)


## BlendKeyed (anim.c:1570-1584): blend from the implicit u=0 anchor `v0`
## through `keys` at progress `uu`.
##
## Three edges, all load-bearing: no keys returns the anchor; past the last key
## HOLDS it (it does not keep extrapolating); and before the first key it eases
## from the anchor, using that key's own ease - because Zen easing is INCOMING,
## easing the segment that ENDS at the key.
static func _keyed(v0: float, keys: Array, uu: float) -> float:
    var n := keys.size()
    if n == 0: return v0
    if uu >= float(keys[n - 1]["t"]): return float(keys[n - 1]["v"])

    var at := 0.0
    var av := v0
    var k := 0
    while k < n and uu > float(keys[k]["t"]):
        k += 1
    if k >= n: k = n - 1
    var bt := float(keys[k]["t"])
    var bv := float(keys[k]["v"])
    if k > 0:
        at = float(keys[k - 1]["t"])
        av = float(keys[k - 1]["v"])
    if bt <= at: return bv                        # degenerate segment: snap
    var f := ZenEasing.apply(String(keys[k]["ease"]), (uu - at) / (bt - at))
    return av + (bv - av) * f


## The colour form. RGB only, and mixed through ZenElement._mix so a
## half-blended channel lands on the same byte the C reference picked.
static func _keyed_color(c0: Color, keys: Array, uu: float) -> Color:
    var n := keys.size()
    if n == 0: return c0
    if uu >= float(keys[n - 1]["t"]): return keys[n - 1]["c"]

    var at := 0.0
    var av := c0
    var k := 0
    while k < n and uu > float(keys[k]["t"]):
        k += 1
    if k >= n: k = n - 1
    var bt := float(keys[k]["t"])
    var bv: Color = keys[k]["c"]
    if k > 0:
        at = float(keys[k - 1]["t"])
        av = keys[k - 1]["c"]
    if bt <= at: return bv
    var f := ZenEasing.apply(String(keys[k]["ease"]), (uu - at) / (bt - at))
    return Color(ZenElement._mix(av.r, bv.r, f), ZenElement._mix(av.g, bv.g, f),
                 ZenElement._mix(av.b, bv.b, f), 1.0)
