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

## Mirror the Zen tracks onto the AnimationPlayer as real Godot tracks.
##
## OFF by default: they are an EDITING surface, not the render path (see
## ZenAnimBuilder.populate_keys), and on a document the size of MAIN_MENU they
## add ~30 tracks to the panel. A future authoring tool turns this on.
@export var mirror_keys := false


## The AnimationPlayer this canvas drives itself with, created on demand.
var _ap: AnimationPlayer = null


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
        _ap.play(ZenAnimBuilder.ANIM)
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
    if _ap == null or not _ap.is_playing(): return
    # Re-pose every frame from the AnimationPlayer's clock. The AP owns TIME;
    # this owns the resolve. Deliberately not a method key per frame - that
    # would be thousands of keys for no gain.
    pose_looping(_anim_time(), loop_smooth)
    # A loop must restart from the body, not from 0, which Godot's own looping
    # cannot express (it always restarts at 0). So the wrap is done by hand.
    if _ap.current_animation_position >= duration - 0.0001:
        if loop_smooth: _ap.seek(play_start(), true)
        else: _ap.pause()


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
