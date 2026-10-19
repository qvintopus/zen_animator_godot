class_name ZenPixelCanvas
extends Control
##
## The shape editor's paint surface: a zoomable, pannable view of one
## ZenPixelShape, the drawing tools, and the reference image laid under it
## (shape_editor.c DrawCanvas / the canvas half of Update).
##
## Everything is in CELL space except `zoom` (screen px per cell) and `pan`
## (screen position of cell 0,0). The editor screen owns the shape, undo and
## file handling; this only edits cells and reports strokes, so every stroke
## is exactly one undo step:
##
##   stroke_begun   - before the first cell of a stroke changes
##   stroke_ended   - after the last; the editor records the undo step here
##
## Mouse:
##   LMB paints the active ink with the active tool, RMB the same tool with
##   EMPTY (erase). Wheel zooms about the cursor, MMB drags pan. Holding ALT
##   moves (drag) and scales (wheel) the reference image instead.
##

signal stroke_begun
signal stroke_ended
signal hover_changed(cell: Vector2i, inside: bool)
## The reference rect moved or scaled by mouse.
signal reference_moved

enum Tool { PEN, LINE, RECT, FILL }

const ZOOM_MIN := 1.0
const ZOOM_MAX := 48.0
const GRID_MIN_ZOOM := 5.0

var shape: ZenPixelShape:
    set(v):
        if shape != null and shape.changed.is_connected(queue_redraw):
            shape.changed.disconnect(queue_redraw)
        shape = v
        if shape != null: shape.changed.connect(queue_redraw)
        queue_redraw()

var tool: Tool = Tool.PEN
var ink := ZenPixelShape.FILL
var brush := 1
var mirror_x := false
var fill_color := Color(0.96, 0.96, 0.96, 1)
var outline_color := Color(0.38, 0.686, 0.937, 1)

var zoom := 8.0
var pan := Vector2.ZERO

## Reference image: drawn under the cells inside `ref_rect` (cell units).
var ref_texture: Texture2D = null
var ref_rect := Rect2()
var ref_fade := 0.5
## Optional overlay of what Convert would produce: a grid-sized texture.
var ref_mask: Texture2D = null

var _hover := Vector2i(-1, -1)
var _hovering := false
var _stroking := false
var _stroke_ink := ZenPixelShape.FILL
var _start := Vector2i.ZERO
var _last := Vector2i.ZERO
var _panning := false
var _moving_ref := false
var _drag_from := Vector2.ZERO


func _ready() -> void:
    texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    clip_contents = true
    focus_mode = Control.FOCUS_CLICK
    mouse_filter = Control.MOUSE_FILTER_STOP


## Fit the whole shape in view at the largest integer zoom, centred.
func fit() -> void:
    if shape == null or size.x <= 0.0: return
    var sz := Vector2(shape.size)
    zoom = clampf(floorf(minf(size.x / sz.x, size.y / sz.y) * 0.9), ZOOM_MIN, ZOOM_MAX)
    pan = ((size - sz * zoom) * 0.5).floor()
    queue_redraw()


func cell_at(screen: Vector2) -> Vector2i:
    var c := (screen - pan) / zoom
    return Vector2i(floori(c.x), floori(c.y))


func _inside(c: Vector2i) -> bool:
    return shape != null and c.x >= 0 and c.y >= 0 and c.x < shape.size.x and c.y < shape.size.y


# ---------------------------------------------------------------- input

func _gui_input(ev: InputEvent) -> void:
    if shape == null: return
    if ev is InputEventMouseButton:
        var mb := ev as InputEventMouseButton
        if mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and mb.pressed:
            var f := 1.15 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15
            if mb.alt_pressed and ref_texture != null: _scale_ref(f, mb.position)
            else: _zoom_about(f, mb.position)
            accept_event()
        elif mb.button_index == MOUSE_BUTTON_MIDDLE:
            _panning = mb.pressed
            _drag_from = mb.position
            accept_event()
        elif mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
            if mb.pressed:
                if mb.alt_pressed and ref_texture != null and mb.button_index == MOUSE_BUTTON_LEFT:
                    _moving_ref = true
                    _drag_from = mb.position
                elif not _stroking:
                    _begin(cell_at(mb.position),
                           ink if mb.button_index == MOUSE_BUTTON_LEFT else ZenPixelShape.EMPTY)
            else:
                _moving_ref = false
                if _stroking: _end(cell_at(mb.position))
            accept_event()
    elif ev is InputEventMouseMotion:
        var mm := ev as InputEventMouseMotion
        var c := cell_at(mm.position)
        _hovering = true
        if c != _hover:
            _hover = c
            hover_changed.emit(c, _inside(c))
            queue_redraw()
        if _panning:
            pan += mm.position - _drag_from
            _drag_from = mm.position
            queue_redraw()
        elif _moving_ref:
            ref_rect.position += (mm.position - _drag_from) / zoom
            _drag_from = mm.position
            reference_moved.emit()
            queue_redraw()
        elif _stroking:
            if tool == Tool.PEN:
                _stamp_line(_last, c, _stroke_ink)
                shape.commit()
            _last = c
            queue_redraw()


func _notification(what: int) -> void:
    if what == NOTIFICATION_MOUSE_EXIT:
        _hovering = false
        hover_changed.emit(_hover, false)
        queue_redraw()


func _zoom_about(f: float, at: Vector2) -> void:
    var nz := clampf(zoom * f, ZOOM_MIN, ZOOM_MAX)
    # Keep the cell under the cursor under the cursor.
    pan = at - (at - pan) * (nz / zoom)
    zoom = nz
    queue_redraw()


func _scale_ref(f: float, at: Vector2) -> void:
    var c := (at - pan) / zoom
    ref_rect.position = c - (c - ref_rect.position) * f
    ref_rect.size *= f
    reference_moved.emit()
    queue_redraw()


# ---------------------------------------------------------------- tools

func _begin(c: Vector2i, v: int) -> void:
    _stroking = true
    _stroke_ink = v
    _start = c
    _last = c
    stroke_begun.emit()
    match tool:
        Tool.PEN:
            _stamp(c, v)
            shape.commit()
        Tool.FILL:
            flood(c, v)
            _stroking = false
            stroke_ended.emit()
    queue_redraw()


func _end(c: Vector2i) -> void:
    match tool:
        Tool.LINE:
            for p in line_cells(_start, c): _stamp(p, _stroke_ink)
            shape.commit()
        Tool.RECT:
            for p in rect_cells(_start, c): _stamp(p, _stroke_ink)
            shape.commit()
    _stroking = false
    stroke_ended.emit()
    queue_redraw()


## The brush footprint at `c`: a disc `brush` cells across (StampAt).
func footprint(c: Vector2i) -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    var n := maxi(brush, 1)
    var lo := -((n - 1) / 2)
    var o := 0.0 if n % 2 == 1 else 0.5      # even brushes centre between cells
    var r2 := float(n * n) * 0.25 + 0.01
    for dy in range(lo, lo + n):
        for dx in range(lo, lo + n):
            var fx := float(dx) - o
            var fy := float(dy) - o
            if n <= 2 or fx * fx + fy * fy <= r2: out.append(c + Vector2i(dx, dy))
    return out


func _stamp(c: Vector2i, v: int) -> void:
    for p in footprint(c):
        shape.set_cell(p.x, p.y, v)
        if mirror_x: shape.set_cell(shape.size.x - 1 - p.x, p.y, v)


func _stamp_line(a: Vector2i, b: Vector2i, v: int) -> void:
    for p in line_cells(a, b): _stamp(p, v)


## Bresenham, inclusive of both ends.
static func line_cells(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    var dx := absi(b.x - a.x)
    var dy := -absi(b.y - a.y)
    var sx := 1 if a.x < b.x else -1
    var sy := 1 if a.y < b.y else -1
    var err := dx + dy
    var p := a
    while true:
        out.append(p)
        if p == b: break
        var e2 := 2 * err
        if e2 >= dy:
            err += dy
            p.x += sx
        if e2 <= dx:
            err += dx
            p.y += sy
    return out


## The outline of the rectangle spanned by a and b.
static func rect_cells(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
    var out: Array[Vector2i] = []
    var x0 := mini(a.x, b.x)
    var x1 := maxi(a.x, b.x)
    var y0 := mini(a.y, b.y)
    var y1 := maxi(a.y, b.y)
    for x in range(x0, x1 + 1):
        out.append(Vector2i(x, y0))
        if y1 != y0: out.append(Vector2i(x, y1))
    for y in range(y0 + 1, y1):
        out.append(Vector2i(x0, y))
        if x1 != x0: out.append(Vector2i(x1, y))
    return out


## 4-connected flood fill of the region of `c`'s value with `v`.
func flood(c: Vector2i, v: int) -> void:
    if not _inside(c): return
    var from := shape.get_cell(c.x, c.y)
    if from == v: return
    var stack: Array[Vector2i] = [c]
    while not stack.is_empty():
        var p: Vector2i = stack.pop_back()
        if not _inside(p) or shape.get_cell(p.x, p.y) != from: continue
        shape.set_cell(p.x, p.y, v)
        if mirror_x: shape.set_cell(shape.size.x - 1 - p.x, p.y, v)
        stack.append(p + Vector2i.LEFT)
        stack.append(p + Vector2i.RIGHT)
        stack.append(p + Vector2i.UP)
        stack.append(p + Vector2i.DOWN)
    shape.commit()


# ---------------------------------------------------------------- draw

func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.065, 0.08, 1))
    if shape == null: return
    var box := Rect2(pan, Vector2(shape.size) * zoom)
    draw_rect(box, Color(0.13, 0.14, 0.17, 1))

    if ref_texture != null and ref_fade > 0.0:
        draw_texture_rect(ref_texture, Rect2(pan + ref_rect.position * zoom, ref_rect.size * zoom),
                          false, Color(1, 1, 1, ref_fade))
    draw_texture_rect(shape.fill_texture(), box, false, fill_color)
    draw_texture_rect(shape.outline_texture(), box, false, outline_color)
    if ref_mask != null:
        draw_texture_rect(ref_mask, box, false, Color(1.0, 0.75, 0.2, 0.45))

    if zoom >= GRID_MIN_ZOOM:
        var gc := Color(1, 1, 1, 0.07)
        for x in range(shape.size.x + 1):
            var px := pan.x + x * zoom
            draw_line(Vector2(px, box.position.y), Vector2(px, box.end.y), gc)
        for y in range(shape.size.y + 1):
            var py := pan.y + y * zoom
            draw_line(Vector2(box.position.x, py), Vector2(box.end.x, py), gc)
    if mirror_x:
        var mx := pan.x + shape.size.x * zoom * 0.5
        draw_line(Vector2(mx, box.position.y), Vector2(mx, box.end.y), Color(0.9, 0.75, 0.48, 0.5), 1.0)
    draw_rect(box, Color(1, 1, 1, 0.25), false, 1.0)

    # What the stroke in progress (line / rect) or the brush would touch.
    var ghost: Array[Vector2i] = []
    if _stroking and tool == Tool.LINE:
        for p in line_cells(_start, _last): ghost.append_array(footprint(p))
    elif _stroking and tool == Tool.RECT:
        for p in rect_cells(_start, _last): ghost.append_array(footprint(p))
    elif not _stroking and _hovering and tool != Tool.FILL:
        ghost = footprint(_hover)
    elif not _stroking and _hovering:
        ghost = [_hover]
    var gcol := Color(1, 1, 1, 0.35)
    for p in ghost:
        if not _inside(p): continue
        draw_rect(Rect2(pan + Vector2(p) * zoom, Vector2(zoom, zoom)), gcol, false, 1.0)
        if mirror_x:
            var q := Vector2(shape.size.x - 1 - p.x, p.y)
            draw_rect(Rect2(pan + q * zoom, Vector2(zoom, zoom)), gcol, false, 1.0)
