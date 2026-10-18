extends SceneTree
##
## Hand-build mouse_ripple.tscn from the values in anims_src/mouse_ripple.cfg.
##
## Deliberately hand-written rather than imported: Phase 1 is validating the
## node layer and the export pipeline, and a hand-built scene keeps a bug in
## the (not yet written) .cfg parser from being mistaken for a rendering bug.
## The importer reproduces this file in Phase 2, and the two are diffed.
##

func k(t: float, v: float, e := "linear") -> Dictionary:
    return {"t": t, "v": v, "ease": e}


func kc(t: float, r: int, g: int, b: int, e := "linear") -> Dictionary:
    return {"t": t, "c": Color8(r, g, b), "ease": e}


func _init() -> void:
    var canvas := ZenCanvas.new()
    canvas.name = "MouseRippleHand"
    canvas.set_script(load("res://addons/zen/runtime/zen_canvas.gd"))
    # doc mouse_ripple 2.000000 0.000000 2.000000 0.000000 0
    canvas.design_size = Vector2(320, 180)
    canvas.duration = 2.0
    canvas.intro_end = 0.0
    canvas.outro_start = 2.0
    canvas.loop_blend = 0.0
    canvas.loop_smooth = false
    canvas.clear_color = Color(0.1, 0.12, 0.16, 1.0)   # preview backdrop

    var s := ZenShape.new()
    s.set_script(load("res://addons/zen/runtime/zen_shape.gd"))
    s.name = "shape"
    s.elem_name = "shape"
    s.shape_kind = ZenShape.Kind.CIRCLE
    s.unit_abs = true                       # `unit abs` -> size is PIXELS
    s.pos_frac = Vector2(0.5, 0.5)
    s.size_frac = Vector2(32.0, 32.0)
    s.scale_base = 0.01
    s.color_base = Color8(245, 245, 245, 0) # fill alpha 0: ring only
    s.outline_color_base = Color8(245, 245, 245, 255)
    s.outline_base = 9.0
    s.outline_crisp = false

    s.tracks = {
        "scale": [
            k(0.0, 0.01), k(0.563181, 1.0, "cubicIn"),
            k(0.641612, 1.0, "bounceOut"), k(2.0, 10.0, "sineIn")],
        "w": [k(0.0, 32.0), k(0.563181, 32.0), k(0.641612, 48.0, "sineIn")],
        "h": [k(0.0, 32.0), k(0.563181, 32.0), k(0.641612, 48.0, "sineIn")],
        "outline": [
            k(0.0, 9.0), k(0.236383, 9.0), k(0.562092, 1.417323),
            k(1.082789, 1.201656), k(1.988017, 0.885827, "quadIn")],
        "outline_color": [
            kc(0.0, 39, 76, 146), kc(0.236383, 35, 93, 167),
            kc(0.562092, 13, 28, 65), kc(1.082789, 67, 90, 124),
            kc(1.988017, 145, 182, 211, "quadIn")],
        "outline_alpha": [
            k(0.0, 1.0), k(0.236383, 1.0), k(0.562092, 1.0),
            k(1.082789, 1.0), k(1.988017, 0.0, "quadIn")],
    }

    canvas.add_child(s)
    s.owner = canvas

    var packed := PackedScene.new()
    var err := packed.pack(canvas)
    if err != OK:
        print("pack failed: ", err)
        quit(1)
        return
    err = ResourceSaver.save(packed, "res://anims/mouse_ripple_hand.tscn")
    print("saved res://anims/mouse_ripple_hand.tscn -> ", error_string(err))
    quit(0 if err == OK else 1)
