@tool
class_name ZenShape
extends ZenElement
##
## The AE_SHAPE element kind. One _draw() switching on shape_kind, ported from
## DrawShapeElem (src/anim/anim.c:1296-1413).
##
## Geometry notes that are not guessable from the property names:
##   - every shape is CENTRE-anchored and rotates about its own centre;
##   - `scale` is a uniform multiplier applied on top of w/h AND the outline
##     thickness, so a scaled shape keeps its authored rim-to-body proportion;
##   - SQUARE uses h for BOTH axes (w is ignored);
##   - LINE is length=w, thickness=h, drawn in the FILL colour with round caps,
##     and its half-length is projected per-axis so a corner-to-corner line
##     stays corner-to-corner when the canvas aspect changes;
##   - fill alpha and outline alpha are INDEPENDENT tracks.
##

enum Kind { RECT, CIRCLE, SQUARE, RHOMBUS, TRIANGLE, LINE, CUSTOM }

const KIND_NAMES := ["rect", "circle", "square", "rhombus", "triangle", "line", "custom"]
const ELLIPSE_SEGS := 36

@export var shape_kind: Kind = Kind.RECT
@export var size_frac := Vector2(0.2, 0.2)
@export var scale_base := 1.0
@export var color_base := Color(1, 1, 1, 1)
@export var outline_color_base := Color(1, 1, 1, 1)
@export var outline_base := 0.0
## Circle-only: stroke as a true annulus instead of a faceted polygon loop, so
## a thin rim does not shimmer as it animates.
@export var outline_crisp := false

var _t := 0.0


func zen_kind() -> String:
    return "shape"


func base_scalar(prop_name: String) -> float:
    match prop_name:
        "w": return size_frac.x
        "h": return size_frac.y
        "alpha": return color_base.a
        "outline_alpha": return outline_color_base.a
        "scale": return scale_base
        "outline": return outline_base
        "shape_id": return float(shape_kind)
    return super.base_scalar(prop_name)


func base_color(prop_name: String) -> Color:
    return outline_color_base if prop_name == "outline_color" else color_base


static func kind_from_name(n: String) -> Kind:
    var i := KIND_NAMES.find(n)
    return (i if i >= 0 else 0) as Kind


func _pose(t: float) -> void:
    _t = t


func _draw() -> void:
    var t := _t
    var fill_a := prop("alpha", t, color_base.a)
    var out_a := prop("outline_alpha", t, outline_color_base.a)
    var sc := maxf(prop("scale", t, scale_base), 0.0)

    var uw := _uw()
    var uh := _uh()
    var thick_px := uh * prop("outline", t, outline_base) * sc

    # Nothing to draw: no fill, and no outline thick enough to land a pixel.
    if fill_a <= 0.0 and (out_a <= 0.0 or thick_px < 0.5): return

    var w_f := prop("w", t, size_frac.x) * sc
    var h_f := prop("h", t, size_frac.y) * sc
    var rot := deg_to_rad(prop("rot", t, rot_base))

    var fill := prop_color("color", t, color_base, fill_a)
    var line := prop_color("outline_color", t, outline_color_base, out_a)

    var c := center_px(t)
    var hw := uw * w_f * 0.5
    var hh := uh * h_f * 0.5

    if shape_kind == Kind.LINE:
        if fill.a <= 0.0: return
        # Half-length projected per axis (see class header).
        var hlx := maxf(uw * w_f * 0.5, 0.0)
        var hly := maxf(uh * w_f * 0.5, 0.0)
        var th := maxf(uh * h_f, 1.0)
        var a := c - Vector2(hlx * cos(rot), hly * sin(rot))
        var b := c + Vector2(hlx * cos(rot), hly * sin(rot))
        draw_line(a, b, fill, th, true)
        draw_circle(a, th * 0.5, fill)      # round caps
        draw_circle(b, th * 0.5, fill)
        return

    # Crisp circle: filled fan plus a smooth annulus stroke.
    if shape_kind == Kind.CIRCLE and outline_crisp:
        var radius := (hw + hh) * 0.5
        if fill.a > 0.0:
            draw_circle(c, radius, fill)
        if thick_px >= 0.5 and line.a > 0.0:
            # draw_arc strokes centred on its radius, so step in by half the
            # width to land the rim inside the shape like DrawRing does.
            var mid := maxf(radius - thick_px * 0.5, 0.0)
            draw_arc(c, mid, 0.0, TAU, ELLIPSE_SEGS, line, thick_px, true)
        return

    var rim := _rim(hw, hh, rot)
    if fill.a > 0.0:
        draw_colored_polygon(rim, fill)
    if thick_px >= 0.5 and line.a > 0.0:
        var loop := rim.duplicate()
        loop.append(rim[0])
        draw_polyline(loop, line, thick_px, true)


## Outline points for the non-line kinds, already rotated about the centre.
func _rim(hw: float, hh: float, rot: float) -> PackedVector2Array:
    var c := center_px(_t)
    var pts := PackedVector2Array()
    var cr := cos(rot)
    var sr := sin(rot)
    var local: Array[Vector2] = []
    match shape_kind:
        Kind.CIRCLE:
            for i in ELLIPSE_SEGS:
                var a := TAU * float(i) / float(ELLIPSE_SEGS)
                local.append(Vector2(cos(a) * hw, sin(a) * hh))
        Kind.SQUARE:
            # side = h on BOTH axes; w is deliberately unused.
            local = [Vector2(-hh, -hh), Vector2(hh, -hh), Vector2(hh, hh), Vector2(-hh, hh)]
        Kind.RHOMBUS:
            local = [Vector2(0, -hh), Vector2(hw, 0), Vector2(0, hh), Vector2(-hw, 0)]
        Kind.TRIANGLE:
            # isosceles pointing up: apex at -h/2, base w wide at +h/2
            local = [Vector2(0, -hh), Vector2(hw, hh), Vector2(-hw, hh)]
        _:
            local = [Vector2(-hw, -hh), Vector2(hw, -hh), Vector2(hw, hh), Vector2(-hw, hh)]
    for p in local:
        pts.append(c + Vector2(p.x * cr - p.y * sr, p.x * sr + p.y * cr))
    return pts
