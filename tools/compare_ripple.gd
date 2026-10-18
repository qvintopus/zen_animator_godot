extends SceneTree
##
## Does the importer reproduce the hand-built mouse_ripple scene?
##
## Compares SAMPLED PROPERTY VALUES over the whole timeline, not the .tscn text:
## two scenes can differ in node order, float formatting or property ordering and
## still animate identically - and conversely, identical-looking text could hide
## a track that silently fails to evaluate. What matters is what gets drawn.
##
##   Godot --headless --path . --script res://tools/compare_ripple.gd
##

const PROPS := ["pos_x", "pos_y", "w", "h", "alpha", "rot", "outline",
                "outline_alpha", "scale"]
const COLOR_PROPS := ["color", "outline_color"]
const EPS := 0.0001

var fails := 0
var compared := 0


func _init() -> void:
    var hand: ZenCanvas = (load("res://anims/mouse_ripple_hand.tscn") as PackedScene).instantiate()
    hand.live_playback = false   # tests pose by hand; no live clock
    var imp: ZenCanvas = (load("res://anims/mouse_ripple.tscn") as PackedScene).instantiate()
    imp.live_playback = false   # tests pose by hand; no live clock

    _cmp_float("duration", hand.duration, imp.duration)
    _cmp_float("intro_end", hand.intro_end, imp.intro_end)
    _cmp_float("outro_start", hand.outro_start, imp.outro_start)
    _cmp_float("loop_blend", hand.loop_blend, imp.loop_blend)

    var he := hand.elements()
    var ie := imp.elements()
    if he.size() != ie.size():
        print("FAIL element count %d vs %d" % [he.size(), ie.size()])
        fails += 1
        _report()
        return

    for i in he.size():
        var a := he[i] as ZenShape
        var b := ie[i] as ZenShape
        if a.elem_name != b.elem_name:
            print("FAIL elem %d name '%s' vs '%s'" % [i, a.elem_name, b.elem_name])
            fails += 1
        _cmp_bool("elem %d unit_abs" % i, a.unit_abs, b.unit_abs)
        _cmp_bool("elem %d outline_crisp" % i, a.outline_crisp, b.outline_crisp)
        if a.shape_kind != b.shape_kind:
            print("FAIL elem %d shape_kind %d vs %d" % [i, a.shape_kind, b.shape_kind])
            fails += 1

        # Sample densely across the whole document, including past the end so
        # the clamp-and-hold behaviour is compared too.
        for s in range(0, 241):
            var t := float(s) / 100.0
            for p in PROPS:
                var base := _base_of(a, p)
                _cmp_float("elem %d %s @%.2f" % [i, p, t],
                           a.prop(p, t, base), b.prop(p, t, base))
            for p in COLOR_PROPS:
                var ca := a.prop_color(p, t, a.color_base, 1.0)
                var cb := b.prop_color(p, t, b.color_base, 1.0)
                _cmp_color("elem %d %s @%.2f" % [i, p, t], ca, cb)
    _report()


func _base_of(s: ZenShape, p: String) -> float:
    match p:
        "pos_x": return s.pos_frac.x
        "pos_y": return s.pos_frac.y
        "w": return s.size_frac.x
        "h": return s.size_frac.y
        "alpha": return s.color_base.a
        "rot": return s.rot_base
        "outline": return s.outline_base
        "outline_alpha": return s.outline_color_base.a
        "scale": return s.scale_base
    return 0.0


func _cmp_float(what: String, a: float, b: float) -> void:
    compared += 1
    if absf(a - b) > EPS:
        print("FAIL %s: %.6f vs %.6f" % [what, a, b])
        fails += 1


func _cmp_bool(what: String, a: bool, b: bool) -> void:
    compared += 1
    if a != b:
        print("FAIL %s: %s vs %s" % [what, a, b])
        fails += 1


func _cmp_color(what: String, a: Color, b: Color) -> void:
    compared += 1
    if absf(a.r - b.r) > EPS or absf(a.g - b.g) > EPS or absf(a.b - b.b) > EPS:
        print("FAIL %s: %s vs %s" % [what, a, b])
        fails += 1


func _report() -> void:
    print("\n%d comparisons, %d mismatches" % [compared, fails])
    quit(1 if fails > 0 else 0)
