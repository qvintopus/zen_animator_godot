@tool
class_name ZenPlayer
extends Node
##
## The document clock for LIVE playback (anim.c:1841-1900).
##
## Zen owns this rather than delegating to AnimationPlayer's own looping,
## because Godot's loop restarts at 0 every cycle and Zen's must restart at
## `intro_end`: the intro is a one-shot lead-in, played on the first pass and
## skipped on every pass after it. There is no AnimationPlayer setting for that.
##
## The clock is also what pause markers hold, and what the smooth-loop blend
## window is measured against. Export does NOT use this node - it builds an
## explicit frame list instead (zen_export.gd), so a frame stays a pure function
## of (scene, t) and can be rendered out of order.
##

## Emitted when a non-looping play reaches the end of its section.
signal finished
## Emitted when the clock reaches a pause marker and stops. `index` indexes
## `pauses`. Release it with release_pause().
signal paused(index: int)

@export var canvas: ZenCanvas = null
@export var looping := true

## Drive the clock from _process. OFF by default, which is what keeps the
## EXPORTER correct: the exporter poses the canvas at an explicit t and then
## awaits a frame, and a player ticking during that await would re-pose
## everything to its own clock - every exported frame would render the same
## instant. A live scene turns this on (play() does), an export never does.
@export var autoplay := false

## Pause markers, ASCENDING in t - next_pause() relies on that order.
## Each is {"t": float, "once": bool}.
@export var pauses: Array = []

var clock := 0.0
var playing := false
## True once the first cycle has completed, i.e. the intro is spent.
var intro_done := false
var held_pause := -1

## Markers whose `once` is set and which have already fired.
var _spent: Dictionary = {}


func _ready() -> void:
    if canvas == null and get_parent() is ZenCanvas:
        canvas = get_parent()
    # Idle until something asks to play. A scene instantiated by the exporter
    # must leave the canvas alone; see `autoplay`.
    set_process(false)
    if autoplay and not Engine.is_editor_hint():
        play()


func _process(delta: float) -> void:
    if Engine.is_editor_hint(): return
    advance(delta)
    apply()


## Section bounds. The outro is NEVER played; the intro is played only until the
## first wrap, after which the cycle starts at intro_end.
func sec_start() -> float:
    return 0.0


func sec_end() -> float:
    return canvas.play_end() if canvas != null else 0.0


func section_len() -> float:
    return maxf(sec_end() - sec_start(), 0.0)


## Where a loop cycle restarts: intro_end, or the section start when there is no
## intro. Matches the `ie > 0 && ie < len` guard in AnimPlayerUpdate.
func loop_start() -> float:
    if canvas == null: return 0.0
    var ie := canvas.play_start() - sec_start()
    var len := section_len()
    return ie if ie > 0.0 and ie < len else 0.0


func play(from := 0.0) -> void:
    clock = clampf(from, 0.0, section_len())
    playing = true
    intro_done = false
    held_pause = -1
    _spent.clear()
    # Only a play() starts the tick, so merely HAVING a player in the scene
    # never moves the clock (the exporter depends on that).
    set_process(true)


func stop() -> void:
    playing = false
    set_process(false)


## Restart the timeline from the beginning WITHOUT changing whether the clock
## is ticking. This is what a signal's `replay` flag does.
##
## Deliberately not play(): play() calls set_process(true), which would start
## the live clock in contexts that are not live - an export frame, a render
## test, an editor scrub. A ticking player re-poses the canvas during the
## exporter's await and every frame comes out at the player's own t, which is
## the Phase 4 regression (all 78 frames identical). `replay` is about the
## timeline position, not about taking over playback (anim_stage.c:215-223).
##
## A fresh run from u=0 also gets its pause markers back - a `once` hold belongs
## to the playthrough, not to the scene's lifetime - and releases any hold in
## progress, because the replay overrides it.
func rewind() -> void:
    clock = 0.0
    intro_done = false
    held_pause = -1
    _spent.clear()


## Skip the intro: start the first pass where a looped pass would. Used by the
## live UI when a menu is re-entered and the run-in has already been seen.
func play_loop_body() -> void:
    play(loop_start())
    intro_done = true


## Advance the clock by `delta` of doc time, honouring pause markers and the
## intro-skipping wrap. Returns the sample time.
func advance(delta: float) -> float:
    if canvas == null or not playing or held_pause >= 0:
        return sample_time()

    var t0 := clock
    clock += delta

    # A pause is checked BEFORE the wrap, against the step that was actually
    # taken, so a marker near the loop end is not swallowed by the wrap.
    var pi := _crossed_pause(sec_start() + t0, sec_start() + clock)
    if pi >= 0:
        var pt := float(pauses[pi]["t"])
        clock = pt - sec_start()
        held_pause = pi
        if bool(pauses[pi].get("once", false)): _spent[pi] = true
        paused.emit(pi)
        return sample_time()

    var len := section_len()
    if clock >= len:
        if not looping:
            clock = len
            playing = false
            finished.emit()
            return sample_time()
        intro_done = true
        var ls := loop_start()
        var cycle := len - ls
        # fmod, not a reset: an overshoot carries into the next cycle, so a long
        # frame does not quietly lose time.
        clock = (ls + fmod(clock - len, cycle)) if cycle > 0.0 else ls
    return sample_time()


## Release a held pause and resume. The marker is not re-fired on resume: the
## crossing test is half-open at the start for exactly that reason.
func release_pause() -> void:
    held_pause = -1


## Which pause marker does the step t0 -> t1 cross, if any? -1 for none.
##
## Containment is (t0, t1]: a marker exactly AT t0 was served by the frame that
## stopped there and must not re-fire the instant it resumes. A wrapping step
## (t1 < t0) is TWO ranges - the tail of this cycle and the head of the next -
## because checking only (t0,t1] would silently skip a marker near the loop end
## (anim_stage.c:266-280).
func _crossed_pause(t0: float, t1: float) -> int:
    if t1 >= t0: return next_pause(t0, t1)
    var idx := next_pause(t0, sec_end())
    if idx >= 0: return idx
    # The new cycle's head starts just BEFORE the loop point, so a marker
    # exactly at intro_end is not missed.
    return next_pause(canvas.play_start() - 1e-4, t1)


## First marker in (from, to], or -1. `pauses` is ascending, so the first hit is
## the earliest.
func next_pause(from: float, to: float) -> int:
    if to <= from: return -1
    for i in pauses.size():
        if _spent.has(i): continue
        var t := float(pauses[i]["t"])
        if t > from and t <= to: return i
    return -1


## Doc time the clock currently points at.
func sample_time() -> float:
    return sec_start() + clock


## Pose the canvas at the current clock, with the loop blend armed iff this
## playback actually loops - a one-shot must show its tail as authored.
func apply() -> void:
    if canvas == null: return
    canvas.pose_looping(sample_time(), looping)
