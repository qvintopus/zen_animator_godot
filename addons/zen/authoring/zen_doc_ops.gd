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


## Markers out, then read back: the sort and the 0-means-absent rules live in
## ZenAnimBuilder, once.
static func _commit(canvas: ZenCanvas, anim: Animation) -> void:
    canvas.pauses.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))
    ZenAnimBuilder.write_markers(anim, canvas)
    canvas.sync_from_animation()
