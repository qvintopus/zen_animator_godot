class_name ZenEditorStage
extends Control
##
## The scene editor's canvas view: the document rendered into a SubViewport at
## its own design size and drawn here scaled to fit, nearest-filtered - the
## gallery's reason applies (Zen geometry is fractional, so laying the canvas
## out with Control anchors would reposition elements, not enlarge them).
##
## On top: the screen border, selection boxes from ZenElement.bounds_px, and
## picking - click selects the topmost element under the cursor, clicking the
## same spot again cycles down through what overlaps there, drag moves the
## selection (Shift locks the move to the nearest axis or diagonal).
##
## It knows nothing about undo or keys: it reports picks and drags, and the
## editor turns them into ops.
##

signal picked(el: ZenElement, additive: bool)
signal empty_clicked
signal drag_started
signal dragged(delta_frac: Vector2)
signal drag_ended
## A left click while the scene plays (picking is off then): continues a
## pause marker.
signal play_clicked

const DRAG_SLOP := 3.0

var canvas: ZenCanvas = null
var selected: Array = []                ## ZenElements to outline
var time := 0.0                         ## the t the outlines are drawn at
var playing := false
var _sub: SubViewport
var _bg: ColorRect
var _press := Vector2.ZERO
var _pressing := false
var _dragging := false
var _cycle_at := Vector2(-1e9, -1e9)
var _cycle_i := 0


func _ready() -> void:
    clip_contents = true
    focus_mode = FOCUS_CLICK
    _sub = SubViewport.new()
    _sub.transparent_bg = false
    _sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    _bg = ColorRect.new()
    _sub.add_child(_bg)
    add_child(_sub)


func set_canvas(c: ZenCanvas) -> void:
    if canvas != null and canvas.get_parent() == _sub:
        _sub.remove_child(canvas)
    canvas = c
    if c == null: return
    _sub.size = Vector2i(c.design_size)
    _bg.size = c.design_size
    _bg.color = c.clear_color
    _sub.add_child(c)
    queue_redraw()


func refresh_backdrop() -> void:
    if canvas != null: _bg.color = canvas.clear_color
    queue_redraw()


## Where the canvas lands on screen: the largest whole-number scale that fits
## (crisp pixels), or a fractional one when even 1x does not fit.
func view_rect() -> Rect2:
    if canvas == null: return Rect2()
    var d := canvas.design_size
    var k := minf((size.x - 16.0) / d.x, (size.y - 16.0) / d.y)
    if k >= 1.0: k = floorf(k)
    k = maxf(k, 0.1)
    var sz := d * k
    return Rect2(((size - sz) * 0.5).floor(), sz)


func to_screen(p_px: Vector2) -> Vector2:
    var r := view_rect()
    return r.position + p_px * (r.size.x / canvas.design_size.x)


func to_canvas(p_screen: Vector2) -> Vector2:
    var r := view_rect()
    return (p_screen - r.position) * (canvas.design_size.x / r.size.x)


func _process(_dt: float) -> void:
    queue_redraw()


func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.055, 0.065))
    if canvas == null: return
    var r := view_rect()
    RenderingServer.canvas_item_set_default_texture_filter(get_canvas_item(),
        RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_NEAREST)
    draw_texture_rect(_sub.get_texture(), r, false)
    _dotted(r.grow(1.0), ZenUI.DIM)
    for e in selected:
        var el := e as ZenElement
        if not is_instance_valid(el): continue
        var b := el.bounds_px(time)
        if b.size == Vector2.ZERO and el is ZenGlobal: continue
        var sr := Rect2(to_screen(b.position), b.size * (r.size.x / canvas.design_size.x))
        draw_rect(sr.grow(1.0), ZenUI.TITLE, false, 1.0)
        draw_circle(to_screen(el.position), 2.5, ZenUI.TITLE)


func _dotted(r: Rect2, c: Color) -> void:
    var pts := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
    for i in 4:
        draw_dashed_line(pts[i], pts[(i + 1) % 4], c, 1.0, 4.0)


## Elements under canvas point `p`, topmost first. Globals are full-screen and
## would win every click, so they are picked from the Elements panel instead.
func hits(p: Vector2) -> Array:
    var out: Array = []
    if canvas == null: return out
    for e in canvas.elements():
        var el := e as ZenElement
        if el is ZenGlobal: continue
        if el.bounds_px(time).grow(1.0).has_point(p): out.append(el)
    out.sort_custom(func(a, b): return (a as Node2D).z_index > (b as Node2D).z_index)
    return out


func _gui_input(ev: InputEvent) -> void:
    if canvas == null: return
    var mb := ev as InputEventMouseButton
    if playing:
        if mb != null and mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
            play_clicked.emit()
            accept_event()
        return
    if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
        if mb.pressed:
            grab_focus()
            _press = mb.position
            _pressing = true
            _dragging = false
            _pick(mb.position, mb.shift_pressed or mb.ctrl_pressed)
        else:
            if _dragging: drag_ended.emit()
            _pressing = false
            _dragging = false
        accept_event()
        return
    var mm := ev as InputEventMouseMotion
    if mm != null and _pressing and not selected.is_empty():
        var d := mm.position - _press
        if not _dragging and d.length() < DRAG_SLOP: return
        if not _dragging:
            _dragging = true
            drag_started.emit()
        if mm.shift_pressed: d = _axis_lock(d)
        var k := canvas.design_size.x / view_rect().size.x
        dragged.emit(Vector2(d.x * k / canvas.design_size.x, d.y * k / canvas.design_size.y))
        accept_event()


## The nearest of horizontal, vertical and the two diagonals.
static func _axis_lock(d: Vector2) -> Vector2:
    var best := Vector2.ZERO
    for dir in [Vector2(1, 0), Vector2(0, 1), Vector2(1, 1).normalized(), Vector2(1, -1).normalized()]:
        var p: Vector2 = dir * d.dot(dir)
        if p.length() > best.length(): best = p
    return best


func _pick(screen_p: Vector2, additive: bool) -> void:
    var p := to_canvas(screen_p)
    var hs := hits(p)
    if hs.is_empty():
        _cycle_at = Vector2(-1e9, -1e9)
        empty_clicked.emit()
        return
    # A click on an already-selected element keeps the selection, so it can be
    # dragged as a group; clicking the same spot again cycles through overlaps.
    if not additive and screen_p.distance_to(_cycle_at) < DRAG_SLOP:
        _cycle_i = (_cycle_i + 1) % hs.size()
    else:
        _cycle_i = 0
        for i in hs.size():
            if selected.has(hs[i]):
                _cycle_at = screen_p
                if not additive: return
                break
    _cycle_at = screen_p
    picked.emit(hs[_cycle_i], additive)
