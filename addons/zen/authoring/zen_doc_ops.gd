@tool
class_name ZenDocOps
extends RefCounted
##
## The document clock: length, intro/outro and pause markers. The "zen"
## Animation is their one stored copy (ZenAnimBuilder.sync_markers), so each op
## sets the canvas field, writes the markers back and re-syncs - after which
## the canvas and the Animation agree by construction.
##


static func set_duration(canvas: ZenCanvas, d: float) -> void:
    var anim := ZenKeyOps.anim_of(canvas)
    if anim == null: return
    d = maxf(d, 0.1)
    var old := canvas.duration
    anim.length = d
    canvas.duration = d
    # outro_start <= 0 means "unset"; a set outro past the new end is clamped.
    # An outro sitting at the old end is "no outro" (every scene stores one
    # there), so it follows the end - otherwise a longer clip would keep a
    # phantom outro at the old end and never play or export the new tail.
    if canvas.outro_start > d or (canvas.outro_start > 0.0 and canvas.outro_start >= old - 0.0001):
        canvas.outro_start = d
    if canvas.intro_end > d: canvas.intro_end = d
    _commit(canvas, anim)


## 0 clears the intro.
static func set_intro_end(canvas: ZenCanvas, t: float) -> void:
    var anim := ZenKeyOps.anim_of(canvas)
    if anim == null: return
    canvas.intro_end = clampf(t, 0.0, canvas.play_end())
    _commit(canvas, anim)


## 0 (or the full duration) clears the outro.
static func set_outro_start(canvas: ZenCanvas, t: float) -> void:
    var anim := ZenKeyOps.anim_of(canvas)
    if anim == null: return
    canvas.outro_start = clampf(t, canvas.intro_end, canvas.duration)
    _commit(canvas, anim)


static func add_pause(canvas: ZenCanvas, t: float, once := false) -> int:
    var anim := ZenKeyOps.anim_of(canvas)
    if anim == null: return -1
    canvas.pauses.append({"t": clampf(t, 0.0, canvas.duration), "once": once})
    _commit(canvas, anim)
    for i in canvas.pauses.size():
        if is_equal_approx(float(canvas.pauses[i]["t"]), t): return i
    return -1


static func move_pause(canvas: ZenCanvas, i: int, t: float) -> void:
    var anim := ZenKeyOps.anim_of(canvas)
    if anim == null or i < 0 or i >= canvas.pauses.size(): return
    canvas.pauses[i]["t"] = clampf(t, 0.0, canvas.duration)
    _commit(canvas, anim)


static func set_pause_once(canvas: ZenCanvas, i: int, once: bool) -> void:
    var anim := ZenKeyOps.anim_of(canvas)
    if anim == null or i < 0 or i >= canvas.pauses.size(): return
    canvas.pauses[i]["once"] = once
    _commit(canvas, anim)


static func remove_pause(canvas: ZenCanvas, i: int) -> void:
    var anim := ZenKeyOps.anim_of(canvas)
    if anim == null or i < 0 or i >= canvas.pauses.size(): return
    canvas.pauses.remove_at(i)
    _commit(canvas, anim)


# ---------------------------------------------------------------------------
#  Whole-document time: retime and trim
# ---------------------------------------------------------------------------

## Scale the whole clock by `factor`: every document key (and handle reach),
## the length, intro, outro and pauses. Signals keep their own seconds.
static func retime(canvas: ZenCanvas, factor: float) -> void:
    var anim := ZenKeyOps.anim_of(canvas)
    if anim == null or factor <= 0.0 or is_equal_approx(factor, 1.0): return
    var d := maxf(canvas.duration * factor, 0.1)
    ZenKeyOps.scale_anim(anim, factor)
    anim.length = d
    canvas.duration = d
    canvas.intro_end *= factor
    canvas.outro_start *= factor
    for p in canvas.pauses: p["t"] = float(p["t"]) * factor
    _commit(canvas, anim)
    canvas.timeline_dirty()


## The time anything moves: [start of the first segment that changes a value,
## end of the last one] over every document track. Holds (a key repeating the
## value before it, like auto-key's t=0 pose pin) do not count. Vector2(-1, -1)
## when nothing changes at all.
static func key_span(canvas: ZenCanvas) -> Vector2:
    var a := INF
    var b := -INF
    for tk in _tracks(canvas):
        var ks: Array = tk[2]
        for i in range(1, ks.size()):
            if _same(ks[i - 1]["v"], ks[i]["v"]): continue
            a = minf(a, float(ks[i - 1]["t"]))
            b = maxf(b, float(ks[i]["t"]))
    return Vector2(-1, -1) if is_inf(a) else Vector2(a, b)


## Cut the still time off the clip: `lead` the time before key_span().x (every
## key and marker moves left by it), `tail` the time after key_span().y (the
## length ends there). Keys inside the cut are holds, so dropping them changes
## nothing that plays. False when there is nothing to cut.
static func trim(canvas: ZenCanvas, lead: bool, tail: bool) -> bool:
    var anim := ZenKeyOps.anim_of(canvas)
    var span := key_span(canvas)
    if anim == null or span.x < 0.0: return false
    var cut := span.x if lead else 0.0
    var end := span.y if tail else canvas.duration
    if cut <= ZenKeyOps.T_EPS and end >= canvas.duration - ZenKeyOps.T_EPS: return false
    for tk in _tracks(canvas):
        var el: ZenElement = tk[0]
        var prop: String = tk[1]
        # Tail: keys past the end go, but a track keeps its first key (moved
        # to the end) so the value it holds stays.
        var ks := ZenKeyOps.keys(canvas, el, prop)
        for i in range(ks.size() - 1, 0, -1):
            if float(ks[i]["t"]) > end + ZenKeyOps.T_EPS: ZenKeyOps.remove(canvas, el, prop, i)
        ks = ZenKeyOps.keys(canvas, el, prop)
        if float(ks[0]["t"]) > end: ZenKeyOps.set_times(canvas, el, prop, [0], [end])
        # Lead: of the keys before the cut only the last stays, moved onto it.
        ks = ZenKeyOps.keys(canvas, el, prop)
        var last := -1
        for i in ks.size():
            if float(ks[i]["t"]) <= cut + ZenKeyOps.T_EPS: last = i
        for i in range(last - 1, -1, -1): ZenKeyOps.remove(canvas, el, prop, i)
        if last >= 0: ZenKeyOps.set_times(canvas, el, prop, [0], [cut])
    if cut > 0.0:
        _shift(canvas, anim, -cut)
        end -= cut
    var outro_at_end := canvas.outro_start <= 0.0 or canvas.outro_start >= canvas.duration - 0.0001
    var d := maxf(end, 0.1)
    anim.length = d
    canvas.duration = d
    canvas.intro_end = clampf(canvas.intro_end - cut, 0.0, d) if canvas.intro_end > 0.0 else 0.0
    canvas.outro_start = d if outro_at_end else clampf(canvas.outro_start - cut, 0.0, d)
    var kept: Array = []
    for p in canvas.pauses:
        var t := float(p["t"]) - cut
        if t > 0.0 and t < d:
            p["t"] = t
            kept.append(p)
    canvas.pauses = kept
    _commit(canvas, anim)
    canvas.timeline_dirty()
    return true


## Move every key of `anim` by `dt` (every key is at or after -dt).
static func _shift(canvas: ZenCanvas, anim: Animation, dt: float) -> void:
    for tr in anim.get_track_count():
        var n := anim.track_get_key_count(tr)
        var order := range(n - 1, -1, -1) if dt > 0.0 else range(n)
        for i in order:
            anim.track_set_key_time(tr, i, maxf(anim.track_get_key_time(tr, i) + dt, 0.0))
    canvas.timeline_dirty()


## [element half, prop, keys] for every keyed prop of the document.
static func _tracks(canvas: ZenCanvas) -> Array:
    var out: Array = []
    if not canvas.edit_anim.is_empty(): return out
    for r in ZenElemOps.rows(canvas):
        for h in ZenElemOps.halves(canvas, r as ZenElement):
            for prop in ZenKeyOps.keyed_props(canvas, h as ZenElement):
                var ks := ZenKeyOps.keys(canvas, h as ZenElement, prop)
                if not ks.is_empty(): out.append([h, prop, ks])
    return out


static func _same(a: Variant, b: Variant) -> bool:
    if a is Color: return (a as Color).is_equal_approx(b as Color)
    return is_equal_approx(float(a), float(b))


## Markers out, then read back: the sort and the 0-means-absent rules live in
## ZenAnimBuilder, once.
static func _commit(canvas: ZenCanvas, anim: Animation) -> void:
    canvas.pauses.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))
    ZenAnimBuilder.write_markers(anim, canvas)
    canvas.sync_from_animation()
