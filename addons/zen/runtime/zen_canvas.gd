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

## Document clock. NOT exported: the
## scene's AnimationPlayer ("zen" length and markers) is the one stored copy,
## and sync_from_animation() reads these back out of it.
var duration := 2.0
var intro_end := 0.0
var outro_start := 0.0
@export var loop_smooth := false
@export var loop_blend := 0.3

## Pause markers, ASCENDING in t - next_pause() relies on that order. Each is
## {"t": float, "once": bool}. Read from the `pause_N[_once]` animation markers.
var pauses: Array = []

## Emitted when the clock reaches a pause marker and stops. `index` indexes
## `pauses`. Release it with release_pause().
signal paused(index: int)

## The scene's text string pool. The canvas OWNS it; every ZenText child
## references this same instance (see ZenStrings). adopt_strings() repairs a
## text node that has none, so a hand-built scene still resolves its words.
@export var strings: ZenStrings

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
	sync_from_animation()
	adopt_strings()
	_join_group()
	set_process(false)
	if Engine.is_editor_hint(): return
	# Build the Godot clock and play. Gated on live_playback so the exporter can
	# opt out - it drives pose() from its own explicit frame list, and a player
	# ticking during its await would make every frame land on the same instant.
	if live_playback:
		setup_animation_player(true)
		set_process(true)
	else:
		# A saved player must stay idle: ticking, it would re-pose the canvas to
		# its own clock and break the exporter's frame-by-frame purity.
		var idle := ZenAnimBuilder.find_player(self)
		if idle != null:
			idle.stop()
			idle.active = false


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
## time the canvas was last posed at - NOT the AnimationPlayer's own clock.
## Reading the AP's clock directly would be wrong in two ways: the exporter
## poses with the AP stopped entirely (so the capture would silently read
## wherever the AP happens to sit), and an editor preview poses at a scrubbed t
## the AP's own position does not reflect. The canvas is the only thing that
## knows what is actually being shown.
##
## Not exported: it is the record of a call, not authored data.
var pose_time := 0.0
var pose_looping_flag := false


# ---------------------------------------------------------------------------
#  Timeline: the AnimationPlayer's animations, sampled purely (ZenTimeline).
# ---------------------------------------------------------------------------

var _tl: ZenTimeline = null
var _sig_tl: Dictionary = {}            ## signal name -> ZenTimeline
var _tl_stale := true


func _notification(what: int) -> void:
	if what == NOTIFICATION_SCENE_INSTANTIATED:
		sync_from_animation()


## The Animation changed under us (an edit, or a test touching a key).
func timeline_dirty() -> void:
	_tl_stale = true


## The document timeline. Rebuilt lazily after the Animation changes.
func timeline() -> ZenTimeline:
	if _tl == null or _tl_stale: _refresh_timeline()
	return _tl


## The timeline of one signal, or an empty one.
func signal_timeline(signal_name: String) -> ZenTimeline:
	if _tl == null or _tl_stale: _refresh_timeline()
	return _sig_tl.get(signal_name, ZenTimeline.new())


func _refresh_timeline() -> void:
	_tl_stale = false
	_sig_tl.clear()
	var ap := ZenAnimBuilder.find_player(self)
	# No player means no keys: code-built canvases call ZenAnimBuilder.install().
	if ap == null or not ap.has_animation(ZenAnimBuilder.ANIM):
		_tl = ZenTimeline.new()
		return
	var anim := ap.get_animation(ZenAnimBuilder.ANIM)
	_tl = ZenTimeline.new(anim)
	_watch(anim)

	var b := bus()
	if b == null: return
	for s in b.signals_data:
		var nm := String((s as Dictionary).get("name", ""))
		if not ap.has_animation_library(ZenAnimBuilder.SIG_LIB): continue
		var lib := ap.get_animation_library(ZenAnimBuilder.SIG_LIB)
		var an := ZenAnimBuilder.sig_anim_name(nm)
		if not lib.has_animation(an): continue
		var sa := lib.get_animation(an)
		_watch(sa)
		_sig_tl[nm] = ZenTimeline.new(sa)


func _watch(a: Animation) -> void:
	if not Engine.is_editor_hint(): return
	if not a.changed.is_connected(_on_anim_changed):
		a.changed.connect(_on_anim_changed)


func _on_anim_changed() -> void:
	sync_from_animation()
	editor_repose()


## Re-pose at the last pose time, for editor scrubs and key edits.
func editor_repose() -> void:
	if not is_inside_tree(): return
	pose_looping(_anim_time() if _ap != null else pose_time, pose_looping_flag)


## Read the clock (length, intro/outro, pauses) out of the saved Animation, so
## the Animation is the only stored copy. Idempotent; safe before _ready().
func sync_from_animation() -> void:
	_tl_stale = true
	var ap := ZenAnimBuilder.find_player(self)
	if ap == null or not ap.has_animation(ZenAnimBuilder.ANIM): return
	ZenAnimBuilder.sync_markers(ap.get_animation(ZenAnimBuilder.ANIM), self)


## Make sure there is a pool, and point every text child without one at it.
## A text that already references a pool is left alone: only the scene ops
## (ZenStringOps.repoint) move a whole canvas onto another instance.
func adopt_strings() -> ZenStrings:
	if strings == null: strings = ZenStrings.new()
	for e in elements():
		if e is ZenText and (e as ZenText).strings == null:
			(e as ZenText).strings = strings
	return strings


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
## ON by default: "open the scene, press F6, watch it play" is the baseline
## expectation of a Godot scene.
##
## The EXPORTER turns this off (zen_export.gd): a clock ticking during the
## exporter's await would re-pose the canvas to its own time and every frame
## would come out at the same instant, which a frame-by-frame export must
## never risk - see the purity invariants under setup_animation_player/_process.
@export var live_playback := true

## Does playback WRAP at play_end(), or hold the last pose? Separate from
## loop_smooth, which only decides whether the wrap is BLENDED - a document can
## wrap hard (loop_smooth=false) or hold without wrapping at all. Explicit, not
## derived: ZenElemFactory.build sets it from `loop_smooth or intro_end > 0.0`.
@export var loop_play := false

## Viewer overrides for LIVE playback (the gallery's I / L toggles). Not
## exported and not document data: they say how this viewer wants to watch,
## not how the animation is authored, and the exporter never reads them.
## Set before the canvas enters the tree, or call setup_animation_player()
## again after changing them.
var play_intro := true   ## false: start at intro_end, as if the intro were spent
var play_loop := true    ## false: play through once and hold the last frame


## Does live playback wrap? The authored flag, gated by the viewer override.
func loops() -> bool:
	return loop_play and play_loop


## Is the intro being skipped by the viewer?
func skips_intro() -> bool:
	return not play_intro and has_intro()

## The AnimationPlayer this canvas drives itself with, created on demand.
var _ap: AnimationPlayer = null

## True once the first cycle has completed, i.e. the intro is spent.
var _intro_done := false

## Index into `pauses` of the marker currently holding playback, or -1.
var held_pause := -1

## Markers whose `once` is set and which have already fired this playthrough.
var _spent: Dictionary = {}


## Find the scene's saved AnimationPlayer and start it. What plays is what is stored in that player.
##
## Called from _ready() for a live scene. Idempotent.
func setup_animation_player(autostart := true) -> AnimationPlayer:
	if _ap == null: _ap = ZenAnimBuilder.find_player(self)
	if _ap == null or not _ap.has_animation(ZenAnimBuilder.ANIM):
		push_warning("zen: '%s' has no AnimationPlayer with a \"zen\" animation" % name)
		return null
	var anim := _ap.get_animation(ZenAnimBuilder.ANIM)

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
		if skips_intro():
			# Straight into the body: the intro counts as already spent.
			anim.loop_mode = Animation.LOOP_LINEAR if loops() else Animation.LOOP_NONE
			_ap.play_section(ZenAnimBuilder.ANIM, play_start(), play_end())
			_intro_done = true
		elif loops() and has_intro():
			anim.loop_mode = Animation.LOOP_NONE
			_ap.play_section(ZenAnimBuilder.ANIM, 0.0, play_end())
		elif loops():
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
## clock, trimmed to the play section the AP itself is bounded to (see
## setup_animation_player and _process).
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
	var pending_handover := loops() and has_intro() and not _intro_done
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
				# AT the marker.
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
	pose_looping(raw, loop_smooth and play_loop)


## True once live playback has run out and is holding its last pose: a
## one-shot (or loop toggled off) at its end, or a terminal signal having
## stopped the timeline. A held PAUSE MARKER is not finished - it resumes.
func is_finished() -> bool:
	if _ap == null or held_pause >= 0: return false
	if loops() and has_intro() and not _intro_done: return false   # handover frame
	return not _ap.is_playing()


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
	if _ap == null: return
	# Plain play() resets the section to the whole animation (measured), so
	# resume by re-entering the section the hold paused inside.
	var t := pose_time
	var from := _ap.get_section_start_time() if _ap.has_section() else play_start()
	var to := _ap.get_section_end_time() if _ap.has_section() else play_end()
	if to <= from:
		from = 0.0
		to = play_end()
	_ap.play_section(ZenAnimBuilder.ANIM, from, to)
	_ap.seek(clampf(t, from, to), true)


## Restart the timeline from the beginning WITHOUT changing whether playback is
## ticking - what a signal's `replay` flag does (anim_stage.c:215-223). Must
## NOT start processing: a player ticking during the exporter's await re-poses
## the canvas to its own t, which is the regression that blanked a whole render
## (every frame landed on the same instant).
func rewind_timeline() -> void:
	_intro_done = false
	held_pause = -1
	_spent.clear()
	if skips_intro():
		_seek_safe(play_start())
		_intro_done = true
	else:
		_seek_safe(0.0)


## Hand the clock to an editor: the player exists and is seekable but idle,
## and nothing re-poses the canvas until the editor says so (scrub/play_from).
func edit_begin() -> void:
	setup_animation_player(false)
	if _ap == null: return
	_ap.active = true
	_ap.pause()
	set_process(false)


## Editor scrub: park the player at `t` and pose there, one-shot (no blend).
func scrub(t: float) -> void:
	_seek_safe(t)
	if _ap != null: _ap.pause()
	pose_looping(t, false)


## Editor play: live playback from `t`, with the document's own section rules.
func play_from(t: float) -> void:
	if _ap == null: edit_begin()
	if _ap == null: return
	setup_animation_player(true)
	# Always seek, 0 included: play_section() on a PAUSED player resumes where
	# it was paused rather than at the section start (measured), so after a
	# one-shot ran out it would resume at its end and finish again at once.
	_seek_safe(clampf(t, 0.0, play_end()))
	set_process(true)


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
