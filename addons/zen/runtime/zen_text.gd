@tool
class_name ZenText
extends ZenElement
##
## The AE_TEXT element kind. Port of DrawTextElem (src/anim/anim.c:1135-1219).
##
## Three things that are easy to get wrong:
##   - POSITION IS THE TEXT CENTRE, not a corner. Godot's draw_string anchors at
##     the baseline-left, so the measured box recentres it. Layout comes from
##     ZenTextMetrics (raylib's exact table), so this lands where Zen put it.
##   - font size is a fraction of canvas HEIGHT (or pixels under `unit abs`).
##   - the colour track is RGB-only and is multiplied by alpha * (1 - crumble):
##     text fades out as it scatters.
##
## CRUMBLE scatters each glyph along its own angle inside a cone, and the glyph
## loop owns line breaking because it places every glyph by hand. Its randomness
## hashes the GLYPH INDEX, never the clock - that is what keeps a frame a pure
## function of (scene, t) so the exporter can ask for frames out of order.
##

@export_multiline var text := "TEXT"
@export var size_frac := Vector2(0.1, 0.1)
@export var color_base := Color(1, 1, 1, 1)
## Rest pose of the scatter, used where no crumble track drives it.
@export var crumble_spin := 90.0
@export var crumble_dir := 90.0
@export var crumble_spread := 12.0
@export var crumble_dist := 0.5

var font: Font = null
var _t := 0.0


## Deterministic pseudo-random in [-1,1] from an int seed. Rand11i, anim.c:1813.
static func rand11i(seed: int) -> float:
    var s := sin(float(seed) * 12.9898) * 43758.5455
    return 2.0 * (s - floor(s)) - 1.0


func zen_kind() -> String:
    return "text"


func base_scalar(prop_name: String) -> float:
    match prop_name:
        "size": return size_frac.x
        "alpha": return color_base.a
        "crumble": return 0.0
        "crumble_dir": return crumble_dir
        "crumble_spread": return crumble_spread
        "crumble_dist": return crumble_dist
        "crumble_spin": return crumble_spin
    return super.base_scalar(prop_name)


func base_color(_prop_name: String) -> Color:
    return color_base


func _ready() -> void:
    super._ready()
    if font == null:
        font = ThemeDB.fallback_font


func _pose(t: float) -> void:
    _t = t


## Font size in pixels: a fraction of canvas HEIGHT unless unit_abs.
func _size_px(t: float) -> float:
    var s := prop("size", t, size_frac.x)
    return maxf(1.0, s if unit_abs else design().y * s)


func _draw() -> void:
    if font == null:
        font = ThemeDB.fallback_font
    var t := _t
    var alpha := prop("alpha", t, color_base.a)
    if alpha <= 0.0: return

    var size_px := _size_px(t)
    var spacing := ZenTextMetrics.spacing_for(size_px)
    var rot := deg_to_rad(prop("rot", t, rot_base))
    var crumble := prop("crumble", t, 0.0)

    var box := ZenTextMetrics.measure(text, size_px)
    var c := center_px(t)
    var left := c.x - box.x * 0.5
    var top := c.y - box.y * 0.5

    var col := prop_color("color", t, color_base, alpha * (1.0 - crumble))
    if col.a <= 0.0: return

    if crumble > 0.0:
        _draw_crumbled(t, size_px, spacing, rot, crumble, left, top, col)
        return

    if is_zero_approx(rot):
        _draw_runs(left, top, size_px, spacing, col)
    else:
        # Rotate the whole block about its centre.
        draw_set_transform(c, rot, Vector2.ONE)
        _draw_runs(left - c.x, top - c.y, size_px, spacing, col)
        draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Draw the text line by line, glyph by glyph, so the raylib advance table
## decides the pen positions rather than the Godot font's own kerning.
func _draw_runs(left: float, top: float, size_px: float, spacing: float,
                col: Color) -> void:
    var pen_y := top
    for line in text.split("\n"):
        var pen_x := left
        for ch in line:
            var cp := ch.unicode_at(0)
            if ch != " ":
                _draw_glyph(ch, Vector2(pen_x, pen_y), size_px, col)
            pen_x += float(ZenTextMetrics.glyph_width(cp)) * (size_px / 10.0) + spacing
        pen_y += size_px + ZenTextMetrics.LINE_SPACING


## One glyph, top-left anchored like raylib (Godot draws from the baseline) and
## squeezed horizontally to occupy raylib's advance for that character.
##
## Without the squeeze the pen positions are right but the ink is not: the
## fallback font's glyphs run up to 39% wider ('i') or 35% narrower (' ', 'E')
## than the advance the layout reserved, so the text reads with ragged gaps
## ("PAUS E  ME NU"). Scaling each glyph into its cell keeps the raylib rhythm,
## which is the half of the look that layout fidelity can actually deliver.
## Draw one glyph, horizontally squeezed into the advance the raylib layout
## reserved for it.
##
## `outer` is the transform ALREADY in force (the crumble path places and spins
## each glyph with one). `draw_set_transform` REPLACES the canvas transform, it
## does not compose, so the squeeze must be folded into the caller's transform
## rather than set on its own - otherwise every crumbled glyph is drawn at its
## raw baseline in canvas coordinates and the whole title collapses into one
## smear in the top-left corner, which is exactly what it did.
func _draw_glyph(ch: String, at: Vector2, size_px: float, col: Color,
                 outer := Transform2D.IDENTITY) -> void:
    var ps := int(round(size_px))
    if ps <= 0: return
    var asc := font.get_ascent(ps)
    var cell := float(ZenTextMetrics.glyph_width(ch.unicode_at(0))) * (size_px / 10.0)
    var ink := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, ps).x
    var baseline := Vector2(at.x, at.y + asc)
    if cell <= 0.0 or ink <= 0.0:
        if outer == Transform2D.IDENTITY:
            draw_string(font, baseline, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, ps, col)
        else:
            draw_set_transform_matrix(outer)
            draw_string(font, baseline, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, ps, col)
            draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
        return
    # Centre the squeezed glyph in its cell so the stroke weight stays even.
    var sx := cell / ink
    var squeeze := Transform2D(0.0, Vector2(sx, 1.0), 0.0, baseline)
    draw_set_transform_matrix(outer * squeeze)
    draw_string(font, Vector2.ZERO, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, ps, col)
    draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_crumbled(t: float, size_px: float, spacing: float, rot: float,
                    crumble: float, left: float, top: float, col: Color) -> void:
    var c_dir := prop("crumble_dir", t, crumble_dir)
    var c_spread := prop("crumble_spread", t, crumble_spread)
    var c_dist := prop("crumble_dist", t, crumble_dist)
    var c_spin := prop("crumble_spin", t, crumble_spin)
    # Quadratic in crumble: letters accelerate away, so most of the travel
    # happens late and the text stays readable as it starts to go.
    var reach := crumble * crumble * design().y * c_dist

    var pen_x := left
    var pen_y := top
    var idx := 0
    for ch in text:
        if ch == "\n":
            pen_x = left
            pen_y += size_px + spacing      # the C uses spacing here, not LINE_SPACING
            continue
        var cp := ch.unicode_at(0)
        var advance := float(ZenTextMetrics.glyph_width(cp)) * (size_px / 10.0) + spacing
        if ch != " ":
            # The angle hash is OFFSET from the spin hash so the two stay
            # independent: otherwise a glyph's tumble would predict which way it
            # flies and the cone would visibly pair up at narrow spreads.
            var ang := deg_to_rad(c_dir + rand11i(idx + 977) * c_spread * 0.5)
            var gsz := ZenTextMetrics.measure(ch, size_px)
            var org := gsz * 0.5
            var ctr := Vector2(pen_x + org.x + cos(ang) * reach,
                               pen_y + org.y + sin(ang) * reach)
            var grot := rot + deg_to_rad(crumble * (rand11i(idx) * c_spin))
            _draw_glyph(ch, -org, size_px, col,
                        Transform2D(grot, Vector2.ONE, 0.0, ctr))
            idx += 1
        pen_x += advance
