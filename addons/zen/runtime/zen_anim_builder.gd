@tool
class_name ZenAnimBuilder
extends RefCounted
##
## Builds a real Godot `Animation` for a ZenCanvas, so a scene PLAYS on F6 and
## scrubs on Godot's own timeline.
##
## WHY A METHOD TRACK AND NOT VALUE TRACKS (the whole design in one place):
##
## Zen's geometry is RESOLVED, not stored. A property is a fraction of the
## canvas, times `scale`, times the unit mode, and - for a signal-driven or
## loop-blended property - a function of state that does not exist until the
## frame is posed. There is no `Node2D.position` to key: the position is
## computed from pos_frac against design_size every pose. So a value track per
## property would have to duplicate the entire resolver, and would still be
## wrong the moment a signal fired.
##
## Instead the Animation owns TIME and the timeline UI, and one method track
## calls `canvas.pose_looping(t, looping)` - the same entry point the exporter
## uses. That keeps exactly one resolver in the project, and `pose()` stays a
## pure function of (scene, t), which is what lets the exporter render frames
## out of order.
##
## WHAT THIS BUYS over ZenPlayer alone: F6 plays the scene; Godot's animation
## panel shows the clock with intro_end / outro_start as draggable markers;
## dragging the playhead scrubs the real animation. The markers are DATA, not
## decoration - `ZenCanvas` reads its own exported fields, and a future
## authoring tool writes them back from the markers.
##
## KEY POPULATION (`populate_keys`) is the groundwork for that tool: it mirrors
## each Zen track into a real, visible, draggable Godot track. Those tracks are
## deliberately NOT what drives the render - they are an editing surface, and
## `sync_from_keys` reads them back. Driving from them would mean a second
## resolver, and the two would drift.
##

## Name of the animation added to every canvas, and of its library slot.
const ANIM := "zen"
const LIB := ""

## Marker names. These are the .cfg's own clock fields, surfaced on the Godot
## timeline so they can be dragged instead of typed into the inspector.
const M_INTRO := "intro_end"
const M_OUTRO := "outro_start"


## Build the Animation for `canvas`. `looping` decides whether the method track
## asks for the smooth-loop blend, matching ZenPlayer.apply().
static func build(canvas: ZenCanvas, looping := true) -> Animation:
    var anim := Animation.new()
    # The FULL clock, not the play section: the outro must be visible on the
    # timeline (it is authored data) even though it is never rendered. Trimming
    # is the player's job, not the animation's.
    anim.length = maxf(canvas.duration, 0.0001)
    anim.step = 0.0166667                                  # 1/60, the edit grid
    # LOOP_NONE even when looping: Zen's loop restarts at intro_end, which
    # Godot's own looping cannot express (it always restarts at 0). ZenPlayer
    # owns that rule; see its header.
    anim.loop_mode = Animation.LOOP_NONE

    _add_markers(anim, canvas)

    # One method track, keyed at t=0, calling the one resolver.
    var tr := anim.add_track(Animation.TYPE_METHOD)
    # The AnimationPlayer sits beside the elements under the canvas, so the
    # canvas is its parent.
    anim.track_set_path(tr, NodePath(".."))
    anim.track_insert_key(tr, 0.0, {
        "method": "_anim_pose",
        "args": [looping],
    })
    return anim


## Surface the clock fields as timeline markers, when they are set at all.
##
## `intro_end` 0 means "no intro" and `outro_start` 0 means "unset, play the
## whole clock" (AnimDocOutroStart), so a 0 is an ABSENT marker rather than a
## marker at the origin - otherwise every document would show a spurious
## intro_end pinned to the left edge.
static func _add_markers(anim: Animation, canvas: ZenCanvas) -> void:
    if not anim.has_method("add_marker"): return            # pre-4.5 fallback
    if canvas.intro_end > 0.0:
        anim.add_marker(M_INTRO, clampf(canvas.intro_end, 0.0, anim.length))
    if canvas.outro_start > 0.0:
        anim.add_marker(M_OUTRO, clampf(canvas.outro_start, 0.0, anim.length))


## Read the clock back OUT of the markers, so dragging them on the timeline
## edits the document. Returns true when something changed.
static func sync_markers(anim: Animation, canvas: ZenCanvas) -> bool:
    if anim == null or not anim.has_method("get_marker_names"): return false
    var changed := false
    var names: PackedStringArray = anim.get_marker_names()
    if names.has(M_INTRO):
        var v := anim.get_marker_time(M_INTRO)
        if not is_equal_approx(v, canvas.intro_end):
            canvas.intro_end = v
            changed = true
    if names.has(M_OUTRO):
        var v2 := anim.get_marker_time(M_OUTRO)
        if not is_equal_approx(v2, canvas.outro_start):
            canvas.outro_start = v2
            changed = true
    return changed


## Mirror every Zen track onto the Animation as a real, visible Godot track.
##
## GROUNDWORK, not the render path. These tracks exist so an author can see and
## drag the keys in Godot's timeline; `sync_from_keys` reads them back into the
## Zen tracks, which are what actually render. Deliberately one-way-at-a-time:
## two live sources for the same number is how they drift.
##
## Paths are `ElementName:prop` against the canvas, using the element's NODE
## name (not elem_name) because that is what a NodePath can address. The two
## agree for every imported document; a renamed node is resolved by name here
## and would simply produce no track.
##
## Interpolation is LINEAR and `transition` is left alone: the stored VALUES are
## Zen's, and the per-key easing lives in the Zen track (`ease`), which Godot
## has no field for. So these tracks show WHERE the keys are, not the curve
## between them - that is a known, accepted limit of the editing surface, and
## the reason the render still goes through ZenSampler.
static func populate_keys(anim: Animation, canvas: ZenCanvas) -> int:
    var n := 0
    for e in canvas.elements():
        var el := e as ZenElement
        for prop in el.tracks:
            var keys: Array = el.tracks[prop]
            if keys.is_empty(): continue                    # `track rot 0`
            var stepped := ZenProps.is_stepped(String(prop))
            var tr := anim.add_track(Animation.TYPE_VALUE)
            anim.track_set_path(tr, NodePath("../%s:%s" % [el.name, prop]))
            # A stepped prop keys a POOL INDEX; interpolating it resolves to the
            # wrong entry entirely (anim.c AnimPropIsStepped).
            anim.track_set_interpolation_type(tr, Animation.INTERPOLATION_NEAREST
                if stepped else Animation.INTERPOLATION_LINEAR)
            anim.value_track_set_update_mode(tr, Animation.UPDATE_DISCRETE
                if stepped else Animation.UPDATE_CONTINUOUS)
            for k in keys:
                var kd: Dictionary = k
                anim.track_insert_key(tr, float(kd["t"]),
                    kd["c"] if kd.has("c") else kd.get("v", 0.0))
            n += 1
    return n


## Read mirrored Godot tracks back into the Zen tracks, preserving each key's
## authored `ease` by position.
##
## A key the author ADDED in Godot's timeline has no ease of its own, so it
## inherits "linear" - the same default the .cfg grammar uses for an
## unannotated key. A key that was DELETED simply disappears. Returns the
## number of tracks updated.
static func sync_from_keys(anim: Animation, canvas: ZenCanvas) -> int:
    var n := 0
    for ti in anim.get_track_count():
        if anim.track_get_type(ti) != Animation.TYPE_VALUE: continue
        var path := anim.track_get_path(ti)
        var node_name := String(path.get_concatenated_names()).trim_prefix("../")
        var prop := String(path.get_concatenated_subnames())
        if prop.is_empty(): continue
        var el: ZenElement = null
        for e in canvas.elements():
            if (e as Node).name == node_name: el = e
        if el == null: continue
        var old: Array = el.tracks.get(prop, [])
        var fresh: Array = []
        for ki in anim.track_get_key_count(ti):
            var t := anim.track_get_key_time(ti, ki)
            var v: Variant = anim.track_get_key_value(ti, ki)
            # Carry the ease from the key that was at this index before, which
            # is right for a drag (times move, order does not) and degrades to
            # linear for an insert.
            var ease_name := "linear"
            if ki < old.size(): ease_name = String((old[ki] as Dictionary).get("ease", "linear"))
            var kd := {"t": t, "ease": ease_name}
            if v is Color: kd["c"] = v
            else: kd["v"] = float(v)
            fresh.append(kd)
        el.tracks[prop] = fresh
        n += 1
    return n
