class_name ZenEditorStage
extends Control
##
## The scene editor's canvas view: the document rendered into a SubViewport at
## its own design size and drawn here scaled to fit, nearest-filtered - the
## gallery's reason applies (Zen geometry is fractional, so laying the canvas
## out with Control anchors would reposition elements, not enlarge them).
##
## The view starts fitted (the canvas centred at the largest crisp scale) and
## zooms with the wheel, pans with the middle button; fit_view() goes back.
## The SubViewport renders the whole visible region, not just the canvas, so
## elements placed off the canvas still show - under a hatched veil that marks
## them as outside what the scene displays.
##
## On top: the screen border, selection boxes from ZenElement.bounds_px, and
## picking - click selects the topmost element drawn under the cursor (its
## stroke or pixels, not its bounding box), clicking the same spot again
## cycles down through what overlaps there, drag moves the selection (Shift
## locks the move to the nearest axis or diagonal).
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
const PICK_SLOP := 3.0                   ## screen px of grace around thin strokes
## Wheel zoom steps, screen px per canvas px; the fitted scale joins them.
const ZOOMS := [0.25, 1.0 / 3.0, 0.5, 2.0 / 3.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 8.0, 10.0, 12.0]
const VEIL := Color(0.0, 0.0, 0.0, 0.5)

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
var _pick_on_release := false            ## the press landed on the selection
var _fitted := true                      ## follow the stage size; off once zoomed/panned
var _zoom := 1.0                         ## screen px per canvas px
var _origin := Vector2.ZERO              ## the canvas px at the stage's top-left
var _panning := false
var _hatch: ImageTexture


func _ready() -> void:
    clip_contents = true
    focus_mode = FOCUS_CLICK
    texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
    _sub = SubViewport.new()
    _sub.transparent_bg = true
    _sub.size_2d_override_stretch = true
    _sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    _bg = ColorRect.new()
    _sub.add_child(_bg)
    add_child(_sub)


func set_canvas(c: ZenCanvas) -> void:
    if canvas != null and canvas.get_parent() == _sub:
        _sub.remove_child(canvas)
    canvas = c
    _fitted = true
    if c == null: return
    _bg.size = c.design_size
    _bg.color = c.clear_color
    _sub.add_child(c)
    queue_redraw()


## The backdrop follows the canvas's colour AND size: picking a canvas preset
## in the editor resizes the scene in place, with no set_canvas() call.
func refresh_backdrop() -> void:
    if canvas != null:
        _bg.color = canvas.clear_color
        _bg.size = canvas.design_size
    queue_redraw()


## Where the canvas lands on screen.
func view_rect() -> Rect2:
    if canvas == null: return Rect2()
    _sync_view()
    return Rect2(to_screen(Vector2.ZERO), canvas.design_size * _zoom)


## The fitted framing: the largest whole-number scale that fits (crisp
## pixels), or a fractional one when even 1x does not fit.
func _fit_zoom() -> float:
    var d := canvas.design_size
    var k := minf((size.x - 16.0) / d.x, (size.y - 16.0) / d.y)
    if k >= 1.0: k = floorf(k)
    return maxf(k, 0.1)


func _sync_view() -> void:
    if not _fitted or canvas == null: return
    _zoom = _fit_zoom()
    _origin = -((size - canvas.design_size * _zoom) * 0.5).floor() / _zoom


func zoom() -> float:
    _sync_view()
    return _zoom


func is_fitted() -> bool:
    return _fitted


## Back to the fitted framing.
func fit_view() -> void:
    _fitted = true
    queue_redraw()


## One wheel step in (`dir` 1) or out (-1), keeping the canvas point under
## `screen_p` where it is.
func zoom_step(dir: int, screen_p: Vector2) -> void:
    if canvas == null: return
    _sync_view()
    var steps: Array = ZOOMS.duplicate()
    steps.append(_fit_zoom())
    steps.sort()
    var k := _zoom
    if dir > 0:
        for z in steps:
            if z > _zoom * 1.001:
                k = z
                break
    else:
        for i in range(steps.size() - 1, -1, -1):
            if steps[i] < _zoom * 0.999:
                k = steps[i]
                break
    if k == _zoom: return
    var at := to_canvas(screen_p)
    _fitted = false
    _zoom = k
    _origin = at - screen_p / k
    queue_redraw()


## Move the view by a screen-px drag.
func pan(screen_delta: Vector2) -> void:
    if canvas == null: return
    _sync_view()
    _fitted = false
    _origin -= screen_delta / _zoom
    queue_redraw()


func to_screen(p_px: Vector2) -> Vector2:
    _sync_view()
    return (p_px - _origin) * _zoom


func to_canvas(p_screen: Vector2) -> Vector2:
    _sync_view()
    return p_screen / _zoom + _origin


func _process(_dt: float) -> void:
    if canvas != null: _place_sub()
    queue_redraw()


## Point the SubViewport at the visible region: whole canvas px from a whole
## origin (so pixels stay on the grid), at canvas resolution when zoomed in -
## upscaled nearest by _draw - and at screen resolution when zoomed out.
func _place_sub() -> void:
    _sync_view()
    var o := _origin.floor()
    var ext := (size / _zoom + (_origin - o)).ceil() + Vector2.ONE
    ext = ext.max(Vector2.ONE)
    _sub.size_2d_override = Vector2i(ext)
    _sub.size = Vector2i((ext * minf(_zoom, 1.0)).ceil().max(Vector2.ONE))
    _sub.canvas_transform = Transform2D(0.0, -o)


func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.055, 0.065))
    if canvas == null: return
    var r := view_rect()
    RenderingServer.canvas_item_set_default_texture_filter(get_canvas_item(),
        RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_NEAREST)
    # What the canvas shows through a transparent background, as before the
    # view rendered past the canvas edge.
    draw_rect(r, ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color",
        Color(0.3, 0.3, 0.3)))
    var o := Vector2(_sub.size_2d_override)
    draw_texture_rect(_sub.get_texture(), Rect2(to_screen(_origin.floor()), o * _zoom), false)
    _veil(r)
    _dotted(r.grow(1.0), ZenUI.LABEL)
    for e in selected:
        var el := e as ZenElement
        if not is_instance_valid(el): continue
        var b := el.bounds_px(time)
        if b.size == Vector2.ZERO and el is ZenGlobal: continue
        var sr := Rect2(to_screen(b.position), b.size * (r.size.x / canvas.design_size.x))
        draw_rect(sr.grow(1.0), ZenUI.TITLE, false, 1.0)
        draw_circle(to_screen(el.position), 2.5, ZenUI.TITLE)


## Dim and hatch everything outside the canvas: off-canvas elements stay
## visible but plainly not part of what the scene shows.
func _veil(r: Rect2) -> void:
    if _hatch == null: _hatch = _make_hatch()
    var full := Rect2(Vector2.ZERO, size)
    var parts := [
        Rect2(0, 0, size.x, r.position.y),
        Rect2(0, r.end.y, size.x, size.y - r.end.y),
        Rect2(0, r.position.y, r.position.x, r.size.y),
        Rect2(r.end.x, r.position.y, size.x - r.end.x, r.size.y)]
    for p in parts:
        var q := (p as Rect2).intersection(full)
        if q.size.x <= 0.0 or q.size.y <= 0.0: continue
        draw_rect(q, VEIL)
        # The region is the rect itself, so the hatch lines up across parts.
        draw_texture_rect_region(_hatch, q, q)


static func _make_hatch() -> ImageTexture:
    var img := Image.create(12, 12, false, Image.FORMAT_RGBA8)
    img.fill(Color(0, 0, 0, 0))
    for i in 12: img.set_pixel(i, 11 - i, Color(1, 1, 1, 0.07))
    return ImageTexture.create_from_image(img)


func _dotted(r: Rect2, c: Color) -> void:
    var pts := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
    for i in 4:
        draw_dashed_line(pts[i], pts[(i + 1) % 4], c, 1.0, 4.0)


## Elements whose drawing is under canvas point `p`: the shown ones first,
## each group topmost first (z_index, then tree order - later draws on top).
## Globals are full-screen and would win every click, so they are picked from
## the Elements panel instead.
func hits(p: Vector2) -> Array:
    var found: Array = []
    if canvas == null: return found
    var slop := PICK_SLOP / zoom()
    var els := canvas.elements()
    for i in els.size():
        var el := els[i] as ZenElement
        if el is ZenGlobal or not el.hit_px(p, time, slop): continue
        found.append([el, 1 if el.shows_at(time) else 0, el.z_index, i])
    found.sort_custom(func(a, b):
        for k in [1, 2, 3]:
            if a[k] != b[k]: return a[k] > b[k]
        return false)
    return found.map(func(h): return h[0])


func _gui_input(ev: InputEvent) -> void:
    if canvas == null: return
    var mb := ev as InputEventMouseButton
    if mb != null and mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
        zoom_step(1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1, mb.position)
        accept_event()
        return
    if mb != null and mb.button_index == MOUSE_BUTTON_MIDDLE:
        _panning = mb.pressed
        accept_event()
        return
    if ev is InputEventMouseMotion and _panning:
        pan((ev as InputEventMouseMotion).relative)
        accept_event()
        return
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
            if _dragging:
                drag_ended.emit()
                _cycle_at = Vector2(-1e9, -1e9)
                _pick_on_release = false
            elif _pressing: _release(_press)
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
        var k := 1.0 / zoom()
        dragged.emit(Vector2(d.x * k / canvas.design_size.x, d.y * k / canvas.design_size.y))
        accept_event()


## The nearest of horizontal, vertical and the two diagonals.
static func _axis_lock(d: Vector2) -> Vector2:
    var best := Vector2.ZERO
    for dir in [Vector2(1, 0), Vector2(0, 1), Vector2(1, 1).normalized(), Vector2(1, -1).normalized()]:
        var p: Vector2 = dir * d.dot(dir)
        if p.length() > best.length(): best = p
    return best


## A press. On the selection it picks nothing yet - the press may become a
## drag of the whole selection - and _release() decides; elsewhere it picks
## at once, so a press-drag moves what it just picked.
func _pick(screen_p: Vector2, additive: bool) -> void:
    _pick_on_release = false
    var hs := hits(to_canvas(screen_p))
    if hs.is_empty():
        _cycle_at = Vector2(-1e9, -1e9)
        empty_clicked.emit()
        return
    if not additive and hs.any(func(e): return selected.has(e)):
        _pick_on_release = true
        return
    _choose(screen_p, hs, additive)


## A click that did not drag, after a press on the selection.
func _release(screen_p: Vector2) -> void:
    if not _pick_on_release: return
    _pick_on_release = false
    var hs := hits(to_canvas(screen_p))
    if not hs.is_empty(): _choose(screen_p, hs, false)


## The topmost hit - or, clicking the same spot again, the one under the
## current pick, cycling down through what overlaps there.
func _choose(screen_p: Vector2, hs: Array, additive: bool) -> void:
    var el: ZenElement = hs[0]
    if not additive and screen_p.distance_to(_cycle_at) < DRAG_SLOP:
        var at := -1
        for i in hs.size():
            if selected.has(hs[i]): at = i
        el = hs[(at + 1) % hs.size()]
    _cycle_at = screen_p
    if not additive and selected.size() == 1 and selected[0] == el: return
    picked.emit(el, additive)
