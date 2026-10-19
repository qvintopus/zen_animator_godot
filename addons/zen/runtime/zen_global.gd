@tool
class_name ZenGlobal
extends ZenElement
##
## The AE_GLOBAL element kind: two full-canvas rects (anim.c:1418-1431).
##
##   bg_color x bg_alpha  - the scene BACKGROUND, drawn before every element
##                          regardless of this element's own index.
##   color x fade         - a full-screen COVER drawn at this element's index,
##                          so a global placed late covers everything before it.
##
## bg_alpha 0 means "draw no background at all", letting whatever is behind show
## through - that is how a Zen overlay composites over live gameplay
## (anim_stage.h:20-27). GAME_START.cfg uses it as a fade-from-black.
##
## Two nodes rather than one because the two rects live at different depths; the
## background half is parented separately by the builder.
##

@export var color_base := Color(0, 0, 0, 1)
@export var bg_color_base := Color(0, 0, 0, 0)
## When true this instance paints the background half instead of the fade.
@export var is_background := false

var _t := 0.0


func zen_kind() -> String:
    return "global"


## The background half owns bg_alpha/bg_color, the fade half fade/color.
func owns(prop_name: String) -> bool:
    return (prop_name == "bg_alpha" or prop_name == "bg_color") == is_background


func base_scalar(prop_name: String) -> float:
    match prop_name:
        "fade": return 0.0
        "bg_alpha": return bg_color_base.a
    return super.base_scalar(prop_name)


func base_color(prop_name: String) -> Color:
    return bg_color_base if prop_name == "bg_color" else color_base


func _pose(t: float) -> void:
    _t = t


func _draw() -> void:
    var t := _t
    var r := Rect2(Vector2.ZERO, design())
    if is_background:
        var a := prop("bg_alpha", t, bg_color_base.a)
        if a <= 0.0: return
        var c := prop_color("bg_color", t, bg_color_base, a)
        draw_rect(r, c)
    else:
        var f := prop("fade", t, 0.0)
        if f <= 0.0: return
        var c := prop_color("color", t, color_base, f)
        draw_rect(r, c)
