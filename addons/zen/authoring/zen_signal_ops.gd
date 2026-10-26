@tool
class_name ZenSignalOps
extends RefCounted
##
## Signal CRUD on a live canvas. A signal is two things that must stay in
## step: its entry in the bus's signals_data (name, trigger, point, flags) and
## its Animation in library `sig` (the keys, at u * length seconds). Every op
## here edits both, never a copy.
##
## Keys are edited with ZenKeyOps, pointed at the signal by canvas.edit_anim;
## sync() then re-derives what the runtime needs from the Animation: the
## `targets` list and the capture placeholders (see ZenTimeline). A signal's
## first key of every track sits at t=0 and IS the captured pose - its value
## is never shown, only its shape: ZenTimeline.blend maps the p0 -> v1 curve
## onto live -> v1.
##

const T_EPS := ZenKeyOps.T_EPS


# ---------------------------------------------------------------------------
#  Lookup
# ---------------------------------------------------------------------------

static func names(canvas: ZenCanvas) -> Array:
    var bus := canvas.bus()
    return bus.names() if bus != null else []


## The signal's data entry (live, not a copy), or {}.
static func data(canvas: ZenCanvas, signal_name: String) -> Dictionary:
    var bus := canvas.bus()
    return bus.find(signal_name) if bus != null else {}


static func anim(canvas: ZenCanvas, signal_name: String) -> Animation:
    return ZenAnimBuilder.signal_anim(canvas, signal_name)


## The earlier signal that shares this one's canvas trigger, or "". Only the
## first in list order fires (ZenSignalBus.trigger), so a later one is dead.
static func trigger_clash(canvas: ZenCanvas, signal_name: String) -> String:
    var sig := data(canvas, signal_name)
    var tr := String(sig.get("trigger", "code"))
    if tr == "code": return ""
    for nm in names(canvas):
        if nm == signal_name: return ""
        if String(data(canvas, nm).get("trigger", "")) == tr: return nm
    return ""


static func is_name_free(canvas: ZenCanvas, nm: String) -> bool:
    return not nm.strip_edges().is_empty() and not names(canvas).has(nm.strip_edges())


# ---------------------------------------------------------------------------
#  Create / delete / rename
# ---------------------------------------------------------------------------

## Add a signal, creating the bus on the first one. Returns its name.
static func add(canvas: ZenCanvas, nm := "") -> String:
    nm = nm.strip_edges()
    if nm.is_empty() or not is_name_free(canvas, nm):
        var base := nm if not nm.is_empty() else "signal"
        var i := 1
        nm = "%s%d" % [base, i]
        while not is_name_free(canvas, nm):
            i += 1
            nm = "%s%d" % [base, i]
    var bus := _bus(canvas)
    var sig := ZenSignalData.defaults(nm)
    bus.signals_data.append(sig)
    var a := Animation.new()
    a.length = float(sig["length"])
    a.step = 0.0166667
    _library(canvas).add_animation(ZenAnimBuilder.sig_anim_name(nm), a)
    bus.refresh()
    canvas.timeline_dirty()
    return nm


static func remove(canvas: ZenCanvas, signal_name: String) -> void:
    var bus := canvas.bus()
    if bus == null: return
    var sig := bus.find(signal_name)
    if sig.is_empty(): return
    if bus.running_name == signal_name or bus.is_holding(): bus.release_signal()
    bus.signals_data.erase(sig)
    for sd in bus.signals_data:
        if String(sd["then"]) == signal_name: sd["then"] = ""
    var lib := _library(canvas)
    var an := ZenAnimBuilder.sig_anim_name(signal_name)
    if lib.has_animation(an): lib.remove_animation(an)
    if canvas.edit_anim == signal_name: canvas.edit_anim = ""
    bus.refresh()
    canvas.timeline_dirty()


## Remove every signal and the bus itself: the scene keeps only its timeline.
static func remove_all(canvas: ZenCanvas) -> void:
    for nm in names(canvas): remove(canvas, String(nm))
    var bus := canvas.bus()
    if bus != null:
        canvas.remove_child(bus)
        bus.free()
    var ap := ZenAnimBuilder.find_player(canvas)
    if ap != null and ap.has_animation_library(ZenAnimBuilder.SIG_LIB):
        ap.remove_animation_library(ZenAnimBuilder.SIG_LIB)
    canvas.timeline_dirty()


## Rename, keeping the Animation and every `then` pointing at it. False when
## `to` is empty or taken.
static func rename(canvas: ZenCanvas, from: String, to: String) -> bool:
    to = to.strip_edges()
    if to == from: return true
    if not is_name_free(canvas, to): return false
    var sig := data(canvas, from)
    if sig.is_empty(): return false
    sig["name"] = to
    var bus := canvas.bus()
    for sd in bus.signals_data:
        if String(sd["then"]) == from: sd["then"] = to
    var lib := _library(canvas)
    var a := ZenAnimBuilder.sig_anim_name(from)
    var b := ZenAnimBuilder.sig_anim_name(to)
    if lib.has_animation(a): lib.rename_animation(a, b)
    if canvas.edit_anim == from: canvas.edit_anim = to
    if bus.running_name == from: bus.running_name = to
    bus.refresh()
    canvas.timeline_dirty()
    return true


# ---------------------------------------------------------------------------
#  Fields
# ---------------------------------------------------------------------------

## Set one field (length, terminal, replay, trigger, every_loop, then, point,
## point_ease). Changing `length` rescales the keys so they keep their u.
static func set_field(canvas: ZenCanvas, signal_name: String, key: String,
                      value: Variant) -> void:
    var sig := data(canvas, signal_name)
    if sig.is_empty(): return
    if key == "length":
        value = maxf(float(value), 0.0)
        _rescale(anim(canvas, signal_name), _span(float(sig["length"])), _span(value))
    sig[key] = value
    ZenSignalData.normalize(sig)
    canvas.timeline_dirty()


## Bind `elem` to the signal's point, or update its offset if bound already.
static func bind_point(canvas: ZenCanvas, signal_name: String, elem: String,
                       off := Vector2.ZERO) -> void:
    var sig := data(canvas, signal_name)
    if sig.is_empty(): return
    for pe in sig["point_elems"]:
        if String(pe["elem"]) == elem:
            pe["off"] = off
            return
    (sig["point_elems"] as Array).append({"elem": elem, "off": off})


static func unbind_point(canvas: ZenCanvas, signal_name: String, elem: String) -> void:
    var sig := data(canvas, signal_name)
    if sig.is_empty(): return
    sig["point_elems"] = (sig["point_elems"] as Array).filter(
        func(pe): return String(pe["elem"]) != elem)


# ---------------------------------------------------------------------------
#  Keys
# ---------------------------------------------------------------------------

## Re-derive the signal's runtime data from its Animation after key edits:
## every keyed prop gets its t=0 capture key, a track left with only that key
## is dropped, `targets` lists what is keyed, and the capture meta is rebuilt.
static func sync(canvas: ZenCanvas, signal_name: String) -> void:
    var sig := data(canvas, signal_name)
    var a := anim(canvas, signal_name)
    if sig.is_empty() or a == null: return
    var prev := canvas.edit_anim
    canvas.edit_anim = signal_name
    var targets: Array = []
    var cap: Dictionary = {}
    var old_cap: Dictionary = a.get_meta(ZenTimeline.META_CAPTURE, {})
    var seen: Dictionary = {}
    for e in canvas.elements():
        var el := e as ZenElement
        for prop in ZenKeyOps.keyed_props(canvas, el):
            if ZenProps.is_stepped(prop):
                ZenKeyOps.remove_track(canvas, el, prop)    # signals never step
                continue
            var ks := ZenKeyOps.keys(canvas, el, prop)
            var paths := ZenKeyOps.channel_paths(el, prop)
            var id := "%s/%s" % [el.elem_name, prop]
            # Baked before signals had ease tracks: every bezier key reads as
            # authored, fit keys included, so the second key is not the first
            # authored one. Its capture entry is already right - keep it.
            if not _has_ease_track(a, el, prop) and old_cap.has(paths[0]):
                for p in paths:
                    if old_cap.has(p): cap[p] = old_cap[p]
                if not seen.has(id):
                    seen[id] = true
                    targets.append({"elem": el.elem_name, "prop": prop, "keys": []})
                continue
            if float(ks[0]["t"]) > T_EPS:
                ZenKeyOps.insert(canvas, el, prop, 0.0, _p0(prop, ks[0]["v"]), "linear")
                ks = ZenKeyOps.keys(canvas, el, prop)
            if ks.size() < 2:
                ZenKeyOps.remove_track(canvas, el, prop)
                continue
            var fixed: Variant = _p0(prop, ks[1]["v"], ks[0]["v"])
            if fixed != ks[0]["v"]:
                ZenKeyOps.set_value(canvas, el, prop, 0, fixed)
            var t1 := float(ks[1]["t"])
            for c in paths.size():
                cap[paths[c]] = [t1, (fixed as Color)[["r", "g", "b"][c]]
                                 if fixed is Color else float(fixed)]
            if seen.has(id): continue
            seen[id] = true
            targets.append({"elem": el.elem_name, "prop": prop, "keys": []})
    canvas.edit_anim = prev
    sig["targets"] = targets
    if cap.is_empty(): a.remove_meta(ZenTimeline.META_CAPTURE)
    else: a.set_meta(ZenTimeline.META_CAPTURE, cap)
    canvas.timeline_dirty()


static func _has_ease_track(a: Animation, el: ZenElement, prop: String) -> bool:
    return a.find_track(NodePath(ZenKeyOps.ease_path(el, prop)), Animation.TYPE_VALUE) >= 0


## A placeholder value for the capture key: any value other than the first
## authored key's works (blend() maps by fraction), but it must DIFFER, or the
## segment has no height to map. Keeps `cur` when it already differs.
static func _p0(prop: String, v1: Variant, cur: Variant = null) -> Variant:
    if ZenProps.is_color(prop):
        var c1: Color = v1
        var c0: Color = cur if cur is Color else Color(0, 0, 0, 1)
        for ch in ["r", "g", "b"]:
            if absf(c0[ch] - c1[ch]) < 1e-6: c0[ch] = 0.0 if absf(c1[ch]) > 1e-6 else 1.0
        return c0
    var f1 := float(v1)
    if cur != null and absf(float(cur) - f1) >= 1e-6: return float(cur)
    return 0.0 if absf(f1) > 1e-6 else 1.0


# ---------------------------------------------------------------------------
#  Internals
# ---------------------------------------------------------------------------

## The span a signal's Animation covers: `length`, or 1 for an instant one.
static func _span(length: float) -> float:
    return length if length > 0.0 else 1.0


## Scale every key time (and bezier handle reach) from span `a` to `b`.
static func _rescale(an: Animation, a: float, b: float) -> void:
    if an == null or is_equal_approx(a, b): return
    var k := b / a
    ZenKeyOps.scale_anim(an, k)
    an.length = b
    var cap: Dictionary = an.get_meta(ZenTimeline.META_CAPTURE, {})
    for p in cap: cap[p] = [float(cap[p][0]) * k, cap[p][1]]
    if not cap.is_empty(): an.set_meta(ZenTimeline.META_CAPTURE, cap)


## The bus, created (owned by the canvas so it saves) on the first signal.
static func _bus(canvas: ZenCanvas) -> ZenSignalBus:
    var bus := canvas.bus()
    if bus != null: return bus
    bus = ZenSignalBus.new()
    bus.name = "Signals"
    canvas.add_child(bus)
    bus.owner = canvas
    return bus


static func _library(canvas: ZenCanvas) -> AnimationLibrary:
    var ap := ZenAnimBuilder.find_player(canvas)
    if ap == null: ap = ZenAnimBuilder.install(canvas)
    if ap.has_animation_library(ZenAnimBuilder.SIG_LIB):
        return ap.get_animation_library(ZenAnimBuilder.SIG_LIB)
    var lib := AnimationLibrary.new()
    ap.add_animation_library(ZenAnimBuilder.SIG_LIB, lib)
    return lib
