class_name ZenTimelineView
extends Control
##
## The scene editor's timeline: a picture of the canvas's "zen" Animation.
##
## Everything drawn here is read from that Animation by the editor - length,
## intro/outro/pause markers, the authored keys (ZenKeyOps.keys) and a curve
## sampled through ZenTimeline - so the timeline cannot disagree with what
## plays. Fit keys (the extra bezier keys of a non-cubic ease) are not drawn:
## they belong to their segment, and editing one would break the ease.
##
## It edits nothing itself. Gestures come out as signals and the editor turns
## them into ZenKeyOps / ZenDocOps calls, then hands the result back via
## set_model().
##
##   ruler drag            scrub            (the playhead IS the player's)
##   marker drag           move intro / outro / pause markers
##   key click / Shift     select / toggle
##   key drag              move the selected keys (Ctrl: 0.1s grid)
##   empty-lane drag       box select;  a plain click there scrubs
##   right-click           context menu (key, lane or ruler)
##   wheel / Ctrl+wheel    pan / zoom about the cursor
##

signal scrubbed(t: float)
signal key_pressed(lane: int, idx: int, additive: bool)
signal keys_drag_started
signal keys_dragged(dt: float, snap: bool)
signal keys_drag_ended
signal marker_dragged(kind: String, idx: int, t: float)
signal marker_drag_ended
signal box_selected(keys: Array, additive: bool)
signal context_key(lane: int, idx: int, at: Vector2)
signal context_lane(lane: int, t: float, at: Vector2)
signal context_ruler(t: float, at: Vector2)

const LABEL_W := 132.0
const RULER_H := 24.0
const LANE_H := 22.0
const KEY_R := 5.0
const SNAP := 0.1

## [{label, keys: [{t, ease}], samples: PackedFloat32Array (0..1), lane_color}]
var lanes: Array = []
var length := 2.0
var intro_end := 0.0
var outro_start := 0.0
var pauses: Array = []
var playhead := 0.0
## "lane:idx" -> true
var selection: Dictionary = {}

var _t0 := 0.0                          ## time at the left edge of the lanes
var _pps := 100.0                       ## pixels per second
var _vscroll := 0.0
## Fit the whole length to the width until the user zooms or pans themselves.
var _auto_fit := true
var _drag := ""                         # "" | scrub | keys | marker | box
var _drag_from := Vector2.ZERO
var _marker := ["", -1]
var _box_add := false


func _ready() -> void:
    clip_contents = true
    focus_mode = FOCUS_CLICK
    custom_minimum_size = Vector2(200, RULER_H + LANE_H * 2)
    resized.connect(func(): if _auto_fit: _fit_now())


func set_model(p_lanes: Array, p_length: float, p_intro: float, p_outro: float,
               p_pauses: Array) -> void:
    lanes = p_lanes
    length = maxf(p_length, 0.01)
    intro_end = p_intro
    outro_start = p_outro
    pauses = p_pauses
    if _auto_fit: _fit_now()
    queue_redraw()


## Show the whole length again, and keep it fitted across resizes.
func fit() -> void:
    _auto_fit = true
    _fit_now()


func _fit_now() -> void:
    if size.x <= LABEL_W + 20.0: return
    _t0 = 0.0
    _pps = maxf((size.x - LABEL_W - 16.0) / length, 1.0)
    queue_redraw()


func t_to_x(t: float) -> float:
    return LABEL_W + (t - _t0) * _pps


func x_to_t(x: float) -> float:
    return _t0 + (x - LABEL_W) / _pps


func _lane_y(i: int) -> float:
    return RULER_H + i * LANE_H - _vscroll


static func ease_color(ease: String) -> Color:
    if ease == ZenAnimBuilder.EASE_RAW: return Color(0.6, 0.6, 0.6)
    if ease == "step": return Color(0.9, 0.9, 0.9)
    if ease == "linear": return Color(0.816, 0.835, 0.867)
    var h := float(hash(ease) % 1000) / 1000.0
    return Color.from_hsv(h, 0.55, 0.95)


## The grid step that keeps labels about 70px apart, snapped to 1-2-5.
func _grid_step() -> float:
    var raw := 70.0 / _pps
    var p := pow(10.0, floorf(log(raw) / log(10.0)))
    for m in [1.0, 2.0, 5.0, 10.0]:
        if p * m >= raw: return p * m
    return p * 10.0


func _draw() -> void:
    var w := size.x
    var h := size.y
    draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.075, 0.09))
    var x_end := t_to_x(length)
    # The trimmed regions: the intro plays once, the outro never plays.
    var body_from := t_to_x(intro_end) if intro_end > 0.0 else LABEL_W
    var outro := outro_start if outro_start > 0.0 else length
    draw_rect(Rect2(LABEL_W, 0, maxf(body_from - LABEL_W, 0.0), h), Color(1, 1, 1, 0.025))
    draw_rect(Rect2(t_to_x(outro), 0, maxf(x_end - t_to_x(outro), 0.0), h), Color(0, 0, 0, 0.35))
    if x_end < w: draw_rect(Rect2(x_end, 0, w - x_end, h), Color(0, 0, 0, 0.5))

    # Grid + ruler labels.
    var step := _grid_step()
    var t := ceilf(_t0 / step) * step
    var font := get_theme_default_font()
    while t_to_x(t) < w:
        var x := t_to_x(t)
        draw_line(Vector2(x, RULER_H - 6), Vector2(x, h), Color(1, 1, 1, 0.06))
        draw_string(font, Vector2(x + 2, 13), "%.*f" % [0 if step >= 1.0 else (1 if step >= 0.1 else 2), t],
                    HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ZenUI.DIM)
        t += step
    draw_line(Vector2(LABEL_W, RULER_H), Vector2(w, RULER_H), ZenUI.DIM)

    # Lanes.
    for i in lanes.size():
        var y := _lane_y(i)
        if y + LANE_H < RULER_H or y > h: continue
        var ln: Dictionary = lanes[i]
        draw_line(Vector2(0, y + LANE_H), Vector2(w, y + LANE_H), Color(1, 1, 1, 0.05))
        var smp: PackedFloat32Array = ln.get("samples", PackedFloat32Array())
        if smp.size() > 1:
            var pts := PackedVector2Array()
            for j in smp.size():
                var st := length * float(j) / float(smp.size() - 1)
                pts.append(Vector2(t_to_x(st), y + LANE_H - 3.0 - smp[j] * (LANE_H - 6.0)))
            draw_polyline(pts, Color(ln.get("lane_color", ZenUI.LABEL), 0.35), 1.0)
        var keys: Array = ln["keys"]
        for j in keys.size():
            var k: Dictionary = keys[j]
            var c := Vector2(t_to_x(float(k["t"])), y + LANE_H * 0.5)
            if c.x < LABEL_W - KEY_R or c.x > w + KEY_R: continue
            var sel := selection.has("%d:%d" % [i, j])
            _diamond(c, KEY_R + (1.0 if sel else 0.0), ease_color(String(k["ease"])), sel)

    # Markers on top of the lanes, in the ruler.
    if intro_end > 0.0: _marker_tri(t_to_x(intro_end), ZenUI.LABEL, true)
    if outro_start > 0.0: _marker_tri(t_to_x(outro_start), ZenUI.WARN, false)
    for p in pauses:
        var px := t_to_x(float(p["t"]))
        draw_line(Vector2(px, RULER_H - 8), Vector2(px, h), Color(ZenUI.TITLE, 0.5), 1.0)
        draw_rect(Rect2(px - 3, RULER_H - 10, 6, 6), ZenUI.TITLE)

    # Playhead.
    var phx := t_to_x(playhead)
    draw_line(Vector2(phx, 0), Vector2(phx, h), ZenUI.TITLE, 1.0)
    draw_colored_polygon(PackedVector2Array([Vector2(phx - 5, 0), Vector2(phx + 5, 0),
        Vector2(phx, 7)]), ZenUI.TITLE)

    if _drag == "box":
        var r := Rect2(_drag_from, get_local_mouse_position() - _drag_from).abs()
        draw_rect(r, Color(ZenUI.LABEL, 0.15))
        draw_rect(r, ZenUI.LABEL, false, 1.0)

    # The label column last, so lanes scrolled under it stay hidden.
    draw_rect(Rect2(0, 0, LABEL_W, h), Color(0.07, 0.075, 0.09))
    for i in lanes.size():
        var y := _lane_y(i)
        if y + LANE_H < RULER_H or y > h: continue
        draw_string(font, Vector2(6, y + 15), String(lanes[i]["label"]),
                    HORIZONTAL_ALIGNMENT_LEFT, LABEL_W - 10, 12, ZenUI.TEXT)
    draw_line(Vector2(LABEL_W, 0), Vector2(LABEL_W, h), ZenUI.DIM)
    draw_string(font, Vector2(6, 15), "%.2f / %.2fs" % [playhead, length],
                HORIZONTAL_ALIGNMENT_LEFT, LABEL_W - 10, 12, ZenUI.TITLE)
    if lanes.is_empty():
        draw_string(font, Vector2(LABEL_W + 12, RULER_H + 16),
            "select an element; keyed props show here (key one from the Inspector)",
            HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ZenUI.DIM)


func _diamond(c: Vector2, r: float, col: Color, sel: bool) -> void:
    var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
    draw_colored_polygon(pts, col)
    pts.append(pts[0])
    draw_polyline(pts, ZenUI.TITLE if sel else Color(0, 0, 0, 0.6), 1.5 if sel else 1.0)


func _marker_tri(x: float, c: Color, pointing_right: bool) -> void:
    var d := 7.0 if pointing_right else -7.0
    draw_colored_polygon(PackedVector2Array([Vector2(x, RULER_H - 12), Vector2(x + d, RULER_H - 6),
        Vector2(x, RULER_H)]), c)
    draw_line(Vector2(x, RULER_H), Vector2(x, size.y), Color(c, 0.4), 1.0)


# ---------------------------------------------------------------- hit tests

## [lane, idx] of the key under `p`, or [-1, -1].
func key_at(p: Vector2) -> Array:
    for i in lanes.size():
        var y := _lane_y(i) + LANE_H * 0.5
        if absf(p.y - y) > KEY_R + 2.0: continue
        var keys: Array = lanes[i]["keys"]
        for j in range(keys.size() - 1, -1, -1):
            if absf(p.x - t_to_x(float(keys[j]["t"]))) <= KEY_R + 2.0: return [i, j]
    return [-1, -1]


func lane_at(y: float) -> int:
    if y < RULER_H: return -1
    var i := int(floorf((y - RULER_H + _vscroll) / LANE_H))
    return i if i >= 0 and i < lanes.size() else -1


## ["intro"|"outro"|"pause", idx] under `p` in the ruler, or ["", -1].
func marker_at(p: Vector2) -> Array:
    if p.y > RULER_H + 2.0: return ["", -1]
    for i in pauses.size():
        if absf(p.x - t_to_x(float(pauses[i]["t"]))) <= 5.0: return ["pause", i]
    if intro_end > 0.0 and absf(p.x - t_to_x(intro_end) - 3.0) <= 6.0: return ["intro", 0]
    if outro_start > 0.0 and absf(p.x - t_to_x(outro_start) + 3.0) <= 6.0: return ["outro", 0]
    return ["", -1]


func _clamp_t(t: float, snap: bool) -> float:
    if snap: t = roundf(t / SNAP) * SNAP
    return clampf(t, 0.0, length)


# ---------------------------------------------------------------- input

func _gui_input(ev: InputEvent) -> void:
    var mb := ev as InputEventMouseButton
    if mb != null:
        _on_button(mb)
        accept_event()
        return
    var mm := ev as InputEventMouseMotion
    if mm != null and _drag != "":
        var snap := mm.ctrl_pressed
        match _drag:
            "scrub": scrubbed.emit(_clamp_t(x_to_t(mm.position.x), snap))
            "keys": keys_dragged.emit((mm.position.x - _drag_from.x) / _pps, snap)
            "marker": marker_dragged.emit(_marker[0], _marker[1], _clamp_t(x_to_t(mm.position.x), snap))
            "box": queue_redraw()
        accept_event()


func _on_button(mb: InputEventMouseButton) -> void:
    if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
        if not mb.pressed: return
        var dir := 1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
        if mb.ctrl_pressed or mb.shift_pressed or mb.position.y < RULER_H: _auto_fit = false
        if mb.ctrl_pressed:
            var at := x_to_t(mb.position.x)
            _pps = clampf(_pps * (1.2 if dir > 0 else 1.0 / 1.2), 5.0, 5000.0)
            _t0 = at - (mb.position.x - LABEL_W) / _pps
        elif mb.shift_pressed or mb.position.y < RULER_H:
            _t0 -= dir * 40.0 / _pps
        else:
            var max_scroll := maxf(lanes.size() * LANE_H - (size.y - RULER_H), 0.0)
            _vscroll = clampf(_vscroll - dir * LANE_H, 0.0, max_scroll)
        _t0 = clampf(_t0, -0.5, length)
        queue_redraw()
        return
    if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
        var k := key_at(mb.position)
        var at := get_screen_transform() * mb.position
        if k[0] >= 0: context_key.emit(k[0], k[1], at)
        elif mb.position.y < RULER_H: context_ruler.emit(_clamp_t(x_to_t(mb.position.x), false), at)
        elif lane_at(mb.position.y) >= 0:
            context_lane.emit(lane_at(mb.position.y), _clamp_t(x_to_t(mb.position.x), false), at)
        return
    if mb.button_index != MOUSE_BUTTON_LEFT: return
    if not mb.pressed:
        match _drag:
            "keys": keys_drag_ended.emit()
            "marker": marker_drag_ended.emit()
            "box":
                _finish_box(mb.position)
        if _drag == "box" and mb.position.distance_to(_drag_from) < 3.0:
            scrubbed.emit(_clamp_t(x_to_t(mb.position.x), mb.ctrl_pressed))
        _drag = ""
        queue_redraw()
        return
    grab_focus()
    _drag_from = mb.position
    if mb.position.x < LABEL_W: return
    var m := marker_at(mb.position)
    if m[0] != "":
        _drag = "marker"
        _marker = m
        return
    if mb.position.y < RULER_H:
        _drag = "scrub"
        scrubbed.emit(_clamp_t(x_to_t(mb.position.x), mb.ctrl_pressed))
        return
    var k := key_at(mb.position)
    if k[0] >= 0:
        var additive := mb.shift_pressed or mb.ctrl_pressed
        key_pressed.emit(k[0], k[1], additive)
        if not additive or selection.has("%d:%d" % [k[0], k[1]]):
            _drag = "keys"
            keys_drag_started.emit()
        return
    _drag = "box"
    _box_add = mb.shift_pressed or mb.ctrl_pressed


func _finish_box(to: Vector2) -> void:
    var r := Rect2(_drag_from, to - _drag_from).abs()
    if r.size.length() < 3.0:
        if not _box_add: box_selected.emit([], false)       # a click clears
        return
    var out: Array = []
    for i in lanes.size():
        var y := _lane_y(i) + LANE_H * 0.5
        if y < r.position.y or y > r.end.y: continue
        var keys: Array = lanes[i]["keys"]
        for j in keys.size():
            var x := t_to_x(float(keys[j]["t"]))
            if x >= r.position.x and x <= r.end.x: out.append([i, j])
    box_selected.emit(out, _box_add)
