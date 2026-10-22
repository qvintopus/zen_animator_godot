class_name ZenEaseGraph
extends Control
##
## A small plot of an ease: `samples` when given (a real segment, 0 at the
## previous key and 1 at this one), else ZenEasing.apply(`ease`). The 0 and 1
## levels are always drawn, so overshoot (back, elastic) reads as overshoot.
##

var ease := "linear":
    set(v):
        ease = v
        queue_redraw()
var samples := PackedFloat32Array():
    set(v):
        samples = v
        queue_redraw()
var line_color := ZenUI.LABEL
var caption := ""


func _init() -> void:
    mouse_filter = MOUSE_FILTER_IGNORE


func values() -> PackedFloat32Array:
    if samples.size() > 1: return samples
    var out := PackedFloat32Array()
    for i in 41:
        var p := float(i) / 40.0
        if ease == "step": out.append(0.0 if p < 1.0 else 1.0)
        else: out.append(ZenEasing.apply(ease, p))
    return out


func _draw() -> void:
    var r := Rect2(Vector2(3, 3), size - Vector2(6, 6))
    if r.size.x < 4 or r.size.y < 4: return
    var vs := values()
    var lo := 0.0
    var hi := 1.0
    for v in vs:
        lo = minf(lo, v)
        hi = maxf(hi, v)
    var span := maxf(hi - lo, 1e-6)
    var y_of := func(v: float) -> float: return r.end.y - (v - lo) / span * r.size.y
    draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.25))
    draw_line(Vector2(r.position.x, y_of.call(0.0)), Vector2(r.end.x, y_of.call(0.0)), Color(1, 1, 1, 0.08))
    draw_line(Vector2(r.position.x, y_of.call(1.0)), Vector2(r.end.x, y_of.call(1.0)), Color(1, 1, 1, 0.08))
    var pts := PackedVector2Array()
    for i in vs.size():
        pts.append(Vector2(r.position.x + r.size.x * float(i) / float(vs.size() - 1), y_of.call(vs[i])))
    draw_polyline(pts, line_color, 1.5, true)
    if caption != "":
        draw_string(get_theme_default_font(), Vector2(4, size.y - 4), caption,
                    HORIZONTAL_ALIGNMENT_LEFT, size.x - 8, 10, ZenUI.DIM)
