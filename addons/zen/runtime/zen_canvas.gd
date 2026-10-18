@tool
class_name ZenCanvas
extends Node2D
##
## Root of a Zen animation. Owns the design canvas and the document clock
## metadata; every ZenElement child resolves its fractional geometry against it.
##
## Zen positions are ALWAYS a fraction of the canvas (anim.h:21-24), so the
## canvas size is part of the data model, not a display setting. Keeping it here
## - rather than reading the live viewport - is what makes a render at 1x and a
## render at 4x produce the same composition: the exporter upscales the finished
## frame instead of drawing into a bigger canvas, which would reposition
## everything.
##

## 320x180 - Zen's canvas is ScreenStateTargetSize() = 1920/6 x 1080/6
## (screen_state.c:23). This is NOT a display preference: `unit abs` sizes are
## pixels IN THIS SPACE, so the 16px ball in MAIN_MENU covers 5% of the width
## and lands at 64px in a 1280-wide render. Getting this wrong shrinks every
## absolute-unit element by 4x while leaving fractional ones correct, which is
## exactly as confusing as it sounds.
@export var design_size := Vector2(320, 180)

## Document clock, straight off the `doc` line of a .cfg.
@export var duration := 2.0
@export var intro_end := 0.0
@export var outro_start := 0.0
@export var loop_smooth := false
@export var loop_blend := 0.3

## Pause markers, ASCENDING in t - next_pause() relies on that order. Each is
## {"t": float, "once": bool}. Doc metadata, like duration/intro_end.
@export var pauses: Array = []

## Emitted when the clock reaches a pause marker and stops. `index` indexes
## `pauses`. Release it with release_pause().
signal paused(index: int)

## Background colour painted before any element. Alpha 0 means "draw nothing",
## letting whatever is behind show through (anim_stage.h:20-27).
@export var clear_color := Color(0, 0, 0, 0)


## The loop body is [intro_end, outro_start); the outro is never played.
##
## Both accessors CLAMP, matching AnimDocIntroEnd / AnimDocOutroStart
## (anim.c:1099-1122): outro_start <= 0 is the "unset" case meaning "play the
## whole clock", and a nonsense pair (intro past the outro, outro past the
## duration) must not produce a negative or inverted cycle.
func play_end() -> float:
    var o := outro_start if outro_start > 0.0 else duration
    if o > duration: o = duration
    return maxf(o, 0.0)


func play_start() -> float:
    return clampf(intro_end, 0.0, play_end())


func cycle_length() -> float:
    return maxf(play_end() - play_start(), 0.0001)


## True when there is an intro worth showing or hiding at all.
func has_intro() -> bool:
    return play_start() > 0.0001


## The group the global ZenSignals autoload relays over. An editor preview
## never joins, so authoring cannot fire anything.
##
## NOTE: the EXPORTER's canvas *does* join - it is parented to a SubViewport
## which is added to the live tree, so _ready() runs normally. Group membership
## is therefore NOT a purity guard; the guard is ZenSignalBus.inert, which
## ZenExport.run() sets before rendering a frame. Said explicitly because the
## opposite is easy to assume and would leave the real guard looking redundant.
const GROUP := "zen_canvas"


func _ready() -> void:
    _join_group()
    set_process(false)
    if Engine.is_editor_hint(): return
    # Build the Godot clock and play. Gated on live_playback so the exporter can
    # opt out - it drives pose() from its own explicit frame list, and a player
    # ticking during its await would make every frame land on the same instant.
    if live_playback:
        setup_animation_player(true)
        set_process(true)


func _enter_tree() -> void:
    # Joined from _enter_tree as well as _ready, because Godot defers _ready()
    # to the frame AFTER add_child(): code that adds a canvas and immediately
    # broadcasts would find an empty group. add_to_group is idempotent.
    _join_group()


func _join_group() -> void:
    if Engine.is_editor_hint(): return
    if not is_in_group(GROUP): add_to_group(GROUP)


## The `t` and loop flag of the most recent pose.
##
## A signal captures the pose that is ON SCREEN at fire time, so it needs the
## time the canvas was last posed at - NOT a clock. Reading it from the
## ZenPlayer would be wrong in two ways: the exporter poses without a player at
## all (so the capture would silently read t=0), and an editor preview poses at
## a scrubbed t the player knows nothing about. The canvas is the only thing
## that knows what is actually being shown.
##
## Not exported: it is the record of a call, not authored data.
var pose_time := 0.0
var pose_looping_flag := false


## The signal bus child, or null for a document that authored no signals.
func bus() -> ZenSignalBus:
    for c in get_children():
        if c is ZenSignalBus: return c
    return null


func elements() -> Array:
    var out: Array = []
    for c in get_children():
        if c is ZenElement: out.append(c)
    return out


## Pose every element at `t` as a ONE-SHOT: no loop blend, the authored tail
## shown as-is. Pure function of (scene, t) - nothing reads a clock or RNG,
## which is what lets the exporter ask for frames out of order.
##
## Callers that are rendering a LOOP must say so via pose_looping(t, true);
## defaulting that from loop_smooth here would silently blend a one-shot export
## whose document happens to have the flag set.
func pose(t: float) -> void:
    pose_looping(t, false)


## Should this canvas build and run a Godot AnimationPlayer, so the scene plays
## on F6 and scrubs on Godot's timeline?
##
## ON by default, because "open the scene, press F6, watch it play" is the
## baseline expectation of a Godot scene and the port previously failed it: the
## only clock was ZenPlayer, whose `autoplay` defaults false and is written into
## no scene, so every scene opened static.
##
## The EXPORTER turns this off (zen_export.gd), for the same reason it leaves
## ZenPlayer idle: a player ticking during the exporter's await would re-pose
## the canvas to its own clock and every frame would come out at the same
## instant - the Phase 4 regression that blanked all 78 frames of a render.
@export var live_playback := true

## Does playback WRAP at play_end(), or hold the last pose? Separate from
## loop_smooth, which only decides whether the wrap is BLENDED - a document can
## wrap hard (loop_smooth=false) or hold without wrapping at all. Explicit, not
## derived: the importer (zen_cfg_build.gd) sets it from `loop_smooth or
## intro_end > 0.0`, matching the rule the old ZenPlayer.looping used.
@export var loop_play := false

## Mirror the Zen tracks onto the AnimationPlayer as real Godot tracks.
##
## OFF by default: they are an EDITING surface, not the render path (see
## ZenAnimBuilder.populate_keys), and on a document the size of MAIN_MENU they
## add ~30 tracks to the panel. A future authoring tool turns this on.
@export var mirror_keys := false


## The AnimationPlayer this canvas drives itself with, created on demand.
var _ap: AnimationPlayer = null

## True once the first cycle has completed, i.e. the intro is spent.
var _intro_done := false

## Index into `pauses` of the marker currently holding playback, or -1.
var held_pause := -1

## Markers whose `once` is set and which have already fired this playthrough.
var _spent: Dictionary = {}


## Build (or rebuild) the Godot AnimationPlayer for this canvas and start it.
##
## Called from _ready() for a live scene. Idempotent: a second call replaces the
## animation rather than stacking another player, so an authoring tool can call
## it after an edit.
func setup_animation_player(autostart := true) -> AnimationPlayer:
    if _ap == null:
        for c in get_children():
            if c is AnimationPlayer:
                _ap = c
                break
    if _ap == null:
        _ap = AnimationPlayer.new()
        _ap.name = "AnimationPlayer"
        add_child(_ap)
        # Keep it out of the saved scene's element order: like Player and
        # Signals, a non-element child must not consume a z index.
        if Engine.is_editor_hint() and get_tree() != null:
            _ap.owner = get_tree().edited_scene_root

    var looping := loop_smooth
    var anim := ZenAnimBuilder.build(self, looping)
    if mirror_keys:
        ZenAnimBuilder.populate_keys(anim, self)

    var lib: AnimationLibrary
    if _ap.has_animation_library(ZenAnimBuilder.LIB):
        lib = _ap.get_animation_library(ZenAnimBuilder.LIB)
        if lib.has_animation(ZenAnimBuilder.ANIM):
            lib.remove_animation(ZenAnimBuilder.ANIM)
    else:
        lib = AnimationLibrary.new()
        _ap.add_animation_library(ZenAnimBuilder.LIB, lib)
    lib.add_animation(ZenAnimBuilder.ANIM, anim)

    # The method track must fire while scrubbing too, or dragging the playhead
    # in the editor would move the clock without re-posing anything.
    _ap.callback_mode_method = AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_IMMEDIATE
    _ap.current_animation = ZenAnimBuilder.ANIM

    if autostart and not Engine.is_editor_hint():
        _intro_done = false
        held_pause = -1
        _spent.clear()
        # Godot's native section-loop only engages with LOOP_LINEAR (measured:
        # with LOOP_NONE a section plays once and holds at its end, regardless
        # of play_section vs play_section_with_markers). LOOP_NONE is what one
        # intro pass needs - looping into it would replay the lead-in.
        if loop_play and has_intro():
            anim.loop_mode = Animation.LOOP_NONE
            _ap.play_section(ZenAnimBuilder.ANIM, 0.0, play_end())
        elif loop_play:
            anim.loop_mode = Animation.LOOP_LINEAR
            _ap.play_section(ZenAnimBuilder.ANIM, play_start(), play_end())
            _intro_done = true
        else:
            anim.loop_mode = Animation.LOOP_NONE
            _ap.play_section(ZenAnimBuilder.ANIM, 0.0, play_end())   # one-shot, outro trimmed
    return _ap


func animation_player() -> AnimationPlayer:
    return _ap


## The method track's target. Poses the canvas at the AnimationPlayer's own
## clock, trimming the outro and skipping the intro on later cycles the way
## ZenPlayer does - the rules live there, this just applies them.
##
## A method track fires only at its KEY, so this is called once per play rather
## than once per frame; the per-frame pose comes from _process below. The key
## still earns its place: it is what makes the track visible on the timeline and
## what re-poses on a scrub.
func _anim_pose(looping: bool) -> void:
    pose_looping(_anim_time(), looping)


## Map the AnimationPlayer's raw clock onto Zen's play section.
##
## The animation spans the FULL duration so the outro is visible on the
## timeline, but the outro is never rendered: past outro_start the pose holds
## there. The intro plays once, then each wrap restarts at intro_end.
func _anim_time() -> float:
    if _ap == null: return pose_time
    return _anim_time_for(_ap.current_animation_position)


## The raw-clock -> play-section mapping, as a pure function so it can be tested
## without a running clock. Sampling pose_time after a wrap cannot distinguish
## "restarted at intro_end" from "restarted at 0", because by the time a few
## frames have elapsed the clock has passed intro_end either way.
func _anim_time_for(raw: float) -> float:
    var e := play_end()
    var s := play_start()
    if raw <= e: return raw
    # Past the play end. A one-shot holds the last rendered pose; a loop wraps
    # into the body, never back into the intro.
    if not loop_smooth: return e
    var cyc := maxf(e - s, 0.0001)
    return s + fmod(raw - s, cyc)


func _process(_delta: float) -> void:
    if Engine.is_editor_hint(): return
    if _ap == null: return
    # The handover below is NOT gated on is_playing(): measured on 4.7.2, a
    # LOOP_NONE section playing to its own end already reports is_playing() ==
    # false on the very frame current_animation_position reaches that end -
    # not one frame later. Bailing out here, as a plain "still playing" guard
    # would, means the intro->body handover (and the final pause-hold) never
    # runs at all.
    var pending_handover := loop_play and has_intro() and not _intro_done
    if not _ap.is_playing() and not pending_handover and held_pause < 0:
        return
    var raw := _anim_time()

    if not pauses.is_empty():
        var was_held := held_pause >= 0
        advance_pauses(pose_time, raw)
        if held_pause >= 0:
            if not was_held:
                # Pin exactly to the marker's own instant, not wherever the
                # frame delta happened to land - a pause freezes the picture
                # AT the marker, matching the old ZenPlayer's clamp.
                raw = float(pauses[held_pause]["t"])
                _seek_safe(raw)
            _ap.pause()

    # Narrow to the body on the first wrap: the intro is a one-shot lead-in,
    # played once and skipped on every pass after it. Flipping loop_mode to
    # LOOP_LINEAR here (not at setup) is deliberate - looping before this point
    # would replay the intro, since the section still spans [0, play_end()].
    if pending_handover and raw >= play_end() - 0.0001:
        _intro_done = true
        var anim := _ap.get_animation(ZenAnimBuilder.ANIM)
        anim.loop_mode = Animation.LOOP_LINEAR
        var names: PackedStringArray = anim.get_marker_names() if anim.has_method("get_marker_names") else PackedStringArray()
        # play_section[_with_markers], not a bare set_section() + play(): the
        # section already auto-stopped this frame (is_playing() == false, see
        # above), and plain play() resets the section to the full animation -
        # measured, it silently undid set_section() when called after it.
        # A fresh play_section[_with_markers] restarts AT the section start -
        # intro_end - which is exactly the wrap target: every cycle after the
        # first restarts the body, never the lead-in, and never 0.
        if names.has(ZenAnimBuilder.M_INTRO) and names.has(ZenAnimBuilder.M_OUTRO):
            _ap.play_section_with_markers(ZenAnimBuilder.ANIM, ZenAnimBuilder.M_INTRO, ZenAnimBuilder.M_OUTRO)
        else:
            _ap.play_section(ZenAnimBuilder.ANIM, play_start(), play_end())
        raw = _anim_time()

    # Re-pose every frame from the AnimationPlayer's clock. The AP owns TIME;
    # this owns the resolve. Deliberately not a method key per frame - that
    # would be thousands of keys for no gain.
    pose_looping(raw, loop_smooth)


## Pose at `t` with the smooth-loop blend armed iff `looping`.
##
## A one-shot play must show its authored tail, so the blend is installed for
## the duration of this call only and ALWAYS torn down - leaking it would make
## the next render depend on the previous one, which is exactly the impurity the
## exporter relies on not existing (anim.c:1449-1479).
func pose_looping(t: float, looping: bool) -> void:
    pose_time = t
    pose_looping_flag = looping
    ZenElement.blend_begin(self, looping)
    for e in elements():
        (e as ZenElement).pose(t)
    ZenElement.blend_end()


## First marker in (from, to], or -1. `pauses` is ascending, so the first hit
## is the earliest.
func next_pause(from: float, to: float) -> int:
    if to <= from: return -1
    for i in pauses.size():
        if _spent.has(i): continue
        var t := float(pauses[i]["t"])
        if t > from and t <= to: return i
    return -1


## Which pause marker does the step t0 -> t1 cross, if any? -1 for none.
##
## Containment is (t0, t1]: a marker exactly AT t0 was served by the frame that
## stopped there and must not re-fire the instant it resumes. A wrapping step
## (t1 < t0) is TWO ranges - the tail of this cycle and the head of the next -
## because checking only (t0,t1] would silently skip a marker near the loop end.
func _crossed_pause(t0: float, t1: float) -> int:
    if t1 >= t0: return next_pause(t0, t1)
    var idx := next_pause(t0, play_end())
    if idx >= 0: return idx
    # The new cycle's head starts just BEFORE the loop point, so a marker
    # exactly at play_start() is not missed.
    return next_pause(play_start() - 1e-4, t1)


## Advance the pause state over a step [t0, t1) of doc time, without a clock of
## its own - the AnimationPlayer owns time, this only tracks the hold.
## Unit-testable without a live clock, which is how pause behaviour is tested.
## Returns the index now held, or -1.
func advance_pauses(t0: float, t1: float) -> int:
    if held_pause >= 0: return held_pause
    var pi := _crossed_pause(t0, t1)
    if pi >= 0:
        held_pause = pi
        if bool(pauses[pi].get("once", false)): _spent[pi] = true
        paused.emit(pi)
    return held_pause


## Release a held pause and resume. The marker is not re-fired on resume: the
## crossing test is half-open at the start for exactly that reason.
func release_pause() -> void:
    held_pause = -1
    if _ap != null: _ap.play()


## Restart the timeline from the beginning WITHOUT changing whether playback is
## ticking - what a signal's `replay` flag does (anim_stage.c:215-223). Must
## NOT start processing: a player ticking during the exporter's await re-poses
## the canvas to its own t, which is the regression that blanked a whole render
## (every frame landed on the same instant).
func rewind_timeline() -> void:
    _intro_done = false
    held_pause = -1
    _spent.clear()
    _seek_safe(0.0)


## Stop live playback outright, holding the current pose.
func stop_timeline() -> void:
    if _ap != null: _ap.pause()
    set_process(false)


## seek() does NOT clamp into the active section: with a section [0.5,1.5],
## seek(0.1) lands at 1.10, not 0.5 (measured on 4.7.2). So widen the section
## first whenever the target falls outside it - this is the ONLY chokepoint
## that may call `_ap.seek()` in the whole project.
func _seek_safe(t: float) -> void:
    if _ap == null: return
    if t < play_start() - 0.0001:
        _ap.set_section(0.0, play_end())
        _intro_done = false
    _ap.seek(clampf(t, 0.0, play_end()), true)
