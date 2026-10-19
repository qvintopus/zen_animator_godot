@tool
class_name ZenElement
extends Node2D
##
## Base for the three Zen element kinds. Holds the base pose (the value a
## property has when it has no track) and the tracks themselves, and owns the
## one fraction -> pixel conversion in the project.
##
## THE UNIT RULE (anim.h:21-24, anim.c:1305-1324), which is easy to get subtly
## wrong and impossible to notice until a resize:
##   - position is ALWAYS a fraction of the canvas, in both unit modes;
##   - size is a fraction too, UNLESS unit_abs, in which case it is raw pixels;
##   - the WIDTH axis references canvas.x, the HEIGHT axis canvas.y;
##   - font size and outline thickness are HEIGHT-axis quantities even though
##     they are scalars, because that is what keeps them stable when only the
##     width changes.
##
## Tracks are stored as plain Arrays of {t, v, ease} (or {t, c, ease} for
## colour) and evaluated by ZenSampler, NOT by Godot's interpolator - see the
## header of zen_sampler.gd for why.
##

@export var elem_name := ""
@export var unit_abs := false
@export var pos_frac := Vector2(0.5, 0.5)
@export var rot_base := 0.0

## `anchor corners` in the .cfg. AUTHORING-ONLY metadata: it selects how a
## pos-param BINDING interprets its slot (centre vs the P0/P1 corners), and in
## the C it is read at exactly one place (anim.c:1548, setting fromPose.corner)
## and never affects drawing. Carried so the data stops being lost at import;
## the corner-stretch branch itself is deferred (no bundled document binds a
## corner).
@export var corner_mode := false

## prop name -> Array of key Dictionaries.
@export var tracks: Dictionary = {}

var canvas: ZenCanvas = null


func _ready() -> void:
    _find_canvas()


func _find_canvas() -> void:
    var p := get_parent()
    while p != null:
        if p is ZenCanvas:
            canvas = p
            return
        p = p.get_parent()


func design() -> Vector2:
    if canvas == null: _find_canvas()
    return canvas.design_size if canvas != null else Vector2(320, 180)


## Width/height references. In absolute mode the canvas multiplier drops to 1,
## so the size props are read straight as pixels.
func _uw() -> float:
    return 1.0 if unit_abs else design().x


func _uh() -> float:
    return 1.0 if unit_abs else design().y


func has_track(prop: String) -> bool:
    return tracks.has(prop) and (tracks[prop] as Array).size() > 0


## The plain timeline read: the track if it has keys, else the base pose. No
## loop blend - that is prop()'s job, and the blend TARGET is sampled through
## here so an untracked property blends from its base rather than from 0.
func track_or_base(prop_name: String, t: float, base: float, stepped := false) -> float:
    if not has_track(prop_name): return base
    return ZenSampler.eval(tracks[prop_name], t, stepped, base)


## Scalar property at `t`: the timeline, then the signal override, then the
## additive signal offsets. The ORDER is load bearing - see the four rules in
## the signal-override block near the bottom of this file (anim.c:640-670).
func prop(prop_name: String, t: float, base: float, stepped := false) -> float:
    # 1. A STEPPED property is an identity, not a quantity: easing it toward
    #    the loop start, or letting a signal interpolate it, would land between
    #    two pool entries and resolve to the wrong one. Plain read, and it
    #    returns BEFORE the override is consulted (anim.c:652).
    if stepped or ZenProps.is_stepped(prop_name):
        return track_or_base(prop_name, t, base, true)

    var v: float
    var ov: Variant = _sig_value.get(prop_name)
    if ov != null:
        # 2. The signal OWNS this property. It REPLACES the timeline and the
        #    loop blend - it does not compose with them (the `else` below is
        #    the whole point; an `if` would still pass every seam test).
        v = float(ov)
    else:
        # 3. Plain timeline read plus the smooth-loop blend.
        v = track_or_base(prop_name, t, base)
        var bw := _pose_blend_w
        if bw > 0.0:
            v += (track_or_base(prop_name, _pose_blend_t, base) - v) * bw

    # 4. The two additive offsets apply EVEN WHEN the signal did not drive this
    #    property - they are gated on "this element has a signal", not on
    #    "the override hit" (anim.c:665-669). zooming_box's `ripple_old`
    #    seq-targets `shape scale`, which has no plain target, so scale must
    #    come from the TRACK plus the seq offset.
    return v + float(_sig_offset.get(prop_name, 0.0))


## The plain read with NO override and NO loop blend: what a signal captures as
## its implicit u=0 key.
##
## Needed as its own path rather than clear-then-restore, which would be a
## second piece of leakable state. Re-firing a signal mid-flight must capture
## the TIMELINE pose, never the previous signal's override, or the two would
## compound (anim.c:1522-1524).
##
## It carries no blend weight, and that is correct by construction, not by
## luck: in the C a signal only ever starts from an emit handler, never from
## inside AnimDocDrawLoop, so the loop blend is never armed at capture time.
func plain_prop(prop_name: String, t: float, base: float) -> float:
    return track_or_base(prop_name, t, base, ZenProps.is_stepped(prop_name))


func plain_prop_color(prop_name: String, t: float, base: Color, alpha: float) -> Color:
    return track_or_base_color(prop_name, t, base, alpha)


## The plain colour read, RGB only. See track_or_base.
func track_or_base_color(prop_name: String, t: float, base: Color, alpha: float) -> Color:
    if not has_track(prop_name):
        return Color(base.r, base.g, base.b, alpha)
    return ZenSampler.eval_color(tracks[prop_name], t, alpha, base)


## Colour property at `t`. RGB only - alpha is always a separate track, so it
## blends on its own scalar path and must not be touched here (anim.c:556).
func prop_color(prop_name: String, t: float, base: Color, alpha: float) -> Color:
    var ov: Variant = _sig_color.get(prop_name)
    if ov != null:
        # Signal owns it; the loop blend is skipped, exactly as for scalars.
        # `alpha` is already the plain-track alpha the caller computed, so
        # unlike the C there is nothing to re-read (anim.c:533-557).
        var oc: Color = ov
        return Color(oc.r, oc.g, oc.b, alpha)
    var c := track_or_base_color(prop_name, t, base, alpha)
    var bw := _pose_blend_w
    if bw > 0.0:
        var c0 := track_or_base_color(prop_name, _pose_blend_t, base, alpha)
        c = Color(_mix(c.r, c0.r, bw), _mix(c.g, c0.g, bw), _mix(c.b, c0.b, bw), c.a)
    return c


## Channel mix matching MixChannel (anim.c:436): the C rounds through an 8-bit
## channel, so reproduce the quantisation rather than lerping in float - a
## half-blended colour must land on the same byte the reference picked.
static func _mix(a: float, b: float, p: float) -> float:
    var v := (a * 255.0) + ((b * 255.0) - (a * 255.0)) * p
    return clampf(floorf(v + 0.5), 0.0, 255.0) / 255.0


## Centre of the element in pixels. Position is always fractional.
func center_px(t: float) -> Vector2:
    return Vector2(
        design().x * prop("pos_x", t, pos_frac.x),
        design().y * prop("pos_y", t, pos_frac.y))


## Pose at `t`, then request a redraw. Subclasses override _pose.
##
## Captures the loop-blend weight NOW, while blend_begin's window is open, so
## the deferred _draw() blends with the weight that belonged to this pose.
func pose(t: float) -> void:
    _pose_blend_w = blend_weight(t)
    _pose_blend_t = _blend_start
    _capture_signal()
    _pose(t)
    queue_redraw()


func _pose(_t: float) -> void:
    pass


# ---------------------------------------------------------------------------
#  Smooth-loop blend (anim.c:488-516, 550-559, 658-659).
#
#  A looping clock wraps from the loop end back to the loop start, and key
#  evaluation CLAMPS, so the last key's pose is held to the end of the cycle
#  and then snaps. Over the last `loop_blend` seconds every property is eased
#  into the pose it holds at the loop start, so by the time the clock wraps the
#  two poses are identical and the seam disappears.
#
#  This lives here, in the one place every property read funnels through, which
#  is why no per-kind property table is needed: prop() and prop_color() are the
#  only callers of ZenSampler in the project, so a property cannot be silently
#  left unblended.
#
#  Installed for the duration of one pose() by ZenCanvas and always torn down,
#  so it can never leak into a non-looping render.
# ---------------------------------------------------------------------------
static var _blend_on := false
static var _blend_start := 0.0
static var _blend_end := 0.0
static var _blend_len := 0.0

## The blend armed for THIS element, captured by pose() and read by _draw().
##
## This is per-element and not the static state above because _draw() runs
## LATER than pose() - Godot defers it to the frame being rendered, by which
## time blend_begin/blend_end have long since come and gone. Reading the static
## state from _draw() armed the blend for a window in which nothing actually
## read it, so every property rendered unblended while the unit tests (which
## call prop() directly, inside the window) passed.
var _pose_blend_w := 0.0
var _pose_blend_t := 0.0


## Arm the blend for a looping pass. `looping` false is a one-shot, which must
## show its tail exactly as authored.
static func blend_begin(canvas: ZenCanvas, looping: bool) -> void:
    if canvas == null:
        _blend_on = false
        return
    _blend_start = canvas.play_start()
    _blend_end = canvas.play_end()
    # The blend can never eat more than the cycle it belongs to.
    var cycle := _blend_end - _blend_start
    _blend_len = canvas.loop_blend if canvas.loop_blend < cycle else cycle
    _blend_on = looping and canvas.loop_smooth and _blend_len > 0.0


static func blend_end() -> void:
    _blend_on = false


## Blend weight at `t`: 0 outside the window, 1 exactly at the loop end.
## Smoothstep, so the blend eases in rather than kinking the motion when it
## starts.
static func blend_weight(t: float) -> float:
    if not _blend_on or _blend_len <= 0.0: return 0.0
    var from := _blend_end - _blend_len
    if t <= from: return 0.0
    var p := (t - from) / _blend_len
    if p > 1.0: p = 1.0
    return p * p * (3.0 - 2.0 * p)


# ---------------------------------------------------------------------------
#  Signal override (anim.c:640-670, 533-557, 1675-1816).
#
#  A Zen signal is a named TRANSITION layer: firing one eases each targeted
#  property from the pose that is on screen RIGHT NOW into the signal's
#  authored keys. It REPLACES the timeline for the properties it drives, and
#  adds two further contributions (the sequence offset and the spawn anchor) on
#  top of whatever drove them.
#
#  WHY THE VALUES ARE CAPTURED AND NOT READ LIVE
#
#  The obvious implementation is for prop() to ask the signal player directly.
#  That reads correctly and passes every property-level test - and renders
#  nothing, because elements read their properties inside _draw(), which Godot
#  defers to the frame being rendered. By then the player's clock has moved on
#  (or the signal has finished and been torn down): a test calling the same
#  function the renderer calls is not the same as a test that looks at a pixel.
#
#  So pose() resolves the signal's contribution to concrete values here, and
#  _draw() reads only these dictionaries. They are the ONLY path from an
#  element to signal state.
# ---------------------------------------------------------------------------

## prop -> float / Color the signal DRIVES (replacing the timeline), and
## prop -> float it ADDS. Captured by pose(), read by _draw().
var _sig_value: Dictionary = {}
var _sig_color: Dictionary = {}
var _sig_offset: Dictionary = {}


## Resolve this element's signal contribution for the pose being built.
##
## Cleared unconditionally first: a finished signal must stop contributing on
## the very next pose, and leaking a stale entry would make pose(t) depend on
## what was posed before it - the impurity the exporter relies on not existing.
func _capture_signal() -> void:
    _sig_value.clear()
    _sig_color.clear()
    _sig_offset.clear()
    if canvas == null: _find_canvas()
    if canvas == null: return
    var bus := canvas.bus()
    if bus == null or not bus.is_running(): return

    var kind := zen_kind()
    var nm := elem_name
    for p in ZenProps.scalars_for(kind):
        # Stepped props are never overridden and never offset (rule 1 above),
        # so they are not even asked about.
        if ZenProps.is_stepped(p): continue
        var v: Variant = bus.eval(nm, p)
        if v != null: _sig_value[p] = v
        var off := bus.offset(nm, p)
        if off != 0.0: _sig_offset[p] = off
    for p in ZenProps.colors_for(kind):
        # Alpha is supplied by the caller at read time, so pass a placeholder:
        # prop_color() overwrites it with the plain-track alpha regardless.
        var c: Variant = bus.eval_color(nm, p, 1.0)
        if c != null: _sig_color[p] = c


## Which ZenProps table this element draws from. Overridden by each kind.
func zen_kind() -> String:
    return ""


## The BASE POSE of a property: the value it has with no track, which is what
## track_or_base falls back to. Each kind keeps its base pose in differently
## named exports (size_frac.x is the text size, color_base.a is the shape's
## fill alpha), and the signal capture needs them BY PROPERTY NAME, so the
## mapping has to exist somewhere - here, once, rather than duplicated at every
## _draw() call site.
##
## The bases returned here MUST match what _draw() passes to prop(), or a
## signal would capture a different pose than the renderer shows. Pinned by
## test_signal_bases_match_draw.
func base_scalar(prop_name: String) -> float:
    match prop_name:
        "pos_x": return pos_frac.x
        "pos_y": return pos_frac.y
        "rot": return rot_base
    return 0.0


func base_color(_prop_name: String) -> Color:
    return Color(1, 1, 1, 1)
