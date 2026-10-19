@tool
class_name ZenShapePreview
extends Control
##
## Draws a ZenPixelShape the way a custom ZenShape renders it - fill cells in
## `fill_color`, outline cells in `outline_color` - fitted into this control
## at an integer zoom where it fits, so the texels stay square. Used by the
## gallery's assets section and the shape editor's live preview.
##

@export var shape: ZenPixelShape:
    set(v):
        if shape != null and shape.changed.is_connected(queue_redraw):
            shape.changed.disconnect(queue_redraw)
        shape = v
        if shape != null: shape.changed.connect(queue_redraw)
        queue_redraw()
@export var fill_color := Color(0.96, 0.96, 0.96, 1):
    set(v):
        fill_color = v
        queue_redraw()
@export var outline_color := Color(0.38, 0.686, 0.937, 1):
    set(v):
        outline_color = v
        queue_redraw()
## Fixed zoom in screen pixels per cell; 0 fits the control.
@export var zoom := 0.0:
    set(v):
        zoom = v
        queue_redraw()
## A faint plate behind the shape's box, so empty margins read as part of it.
@export var plate := Color(1, 1, 1, 0.04)


func _ready() -> void:
    texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _draw() -> void:
    if shape == null: return
    var sz := Vector2(shape.size)
    var z := zoom
    if z <= 0.0:
        z = minf(size.x / sz.x, size.y / sz.y)
        if z >= 1.0: z = floorf(z)
    var box := Rect2((size - sz * z) * 0.5, sz * z)
    if plate.a > 0.0: draw_rect(box, plate)
    draw_texture_rect(shape.fill_texture(), box, false, fill_color)
    draw_texture_rect(shape.outline_texture(), box, false, outline_color)
