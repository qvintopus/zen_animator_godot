@tool
class_name ZenText
extends ZenElement
##
## The AE_TEXT element kind. Port of DrawTextElem (src/anim/anim.c:1135-1219).
##
## Three things that are easy to get wrong:
##   - POSITION IS THE TEXT CENTRE, not a corner. Godot's draw_string anchors at
##     the baseline-left, so the measured box (ZenTextMetrics, against a real
##     Godot font - see effective_font()) recentres it, and each line's own
##     baseline sits proportionally inside its slot (_baseline_offset) rather
##     than from the font's own ascent/descent, so swapping fonts changes
##     letterforms without moving the text.
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

## Per-element font override. Null falls back to the project default
## (default_font() below), so an existing scene needs no .tscn change - the
## .cfg grammar has no font field, so the bundled default is project-level.
## Per-animation font choice is a later change.
@export var font: Font = null
var _t := 0.0

const DEFAULT_FONT_PATH := "res://addons/zen/fonts/SourceSans3-Regular.ttf"
static var _default_font_cache: Font = null

## Options-screen override, applied process-wide so every element with no
## per-element `font` picks it up without touching any .tscn. Null means "use
## the bundled default" - see ZenSettings.apply_startup().
static var _font_override: Font = null


static func set_font_override(f: Font) -> void:
    _font_override = f


## The project default font, loaded once and cached. A static func rather than
## a member so it resolves correctly even for a node that is instantiated but
## never enters the tree (dump_scene.gd, the importer) - _ready() is not
## guaranteed to have run.
static func default_font() -> Font:
    if _font_override != null:
        return _font_override
    if _default_font_cache == null:
        _default_font_cache = load(DEFAULT_FONT_PATH)
    return _default_font_cache


func effective_font() -> Font:
    return font if font != null else default_font()


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


func _pose(t: float) -> void:
    _t = t


## Font size in pixels: a fraction of canvas HEIGHT unless unit_abs.
func _size_px(t: float) -> float:
    var s := prop("size", t, size_frac.x)
    return maxf(1.0, s if unit_abs else design().y * s)


func _draw() -> void:
    var fnt := effective_font()
    var t := _t
    var alpha := prop("alpha", t, color_base.a)
    if alpha <= 0.0: return

    var size_px := _size_px(t)
    var spacing := ZenTextMetrics.spacing_for(size_px)
    var rot := deg_to_rad(prop("rot", t, rot_base))
    var crumble := prop("crumble", t, 0.0)

    var box := ZenTextMetrics.measure(text, size_px, fnt)
    var c := center_px(t)
    var left := c.x - box.x * 0.5
    var top := c.y - box.y * 0.5

    var col := prop_color("color", t, color_base, alpha * (1.0 - crumble))
    if col.a <= 0.0: return

    if crumble > 0.0:
        _draw_crumbled(t, fnt, size_px, spacing, rot, crumble, left, top, col)
        return

    if is_zero_approx(rot):
        _draw_runs(fnt, left, top, size_px, col)
    else:
        # Rotate the whole block about its centre.
        draw_set_transform(c, rot, Vector2.ONE)
        _draw_runs(fnt, left - c.x, top - c.y, size_px, col)
        draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Draw the text line by line, through the font's own native layout - no
## manual pen stepping, so the font's own kerning decides inter-glyph spacing
## (the old raylib-cell squeeze is gone; see docs/plans/godot-integration.md
## Task 2 for why that was debt in the wrong shape).
func _draw_runs(fnt: Font, left: float, top: float, size_px: float, col: Color) -> void:
    var ps := int(round(size_px))
    var baseline_y := top + _baseline_offset(fnt, ps, size_px)
    for line in text.split("\n"):
        draw_string(fnt, Vector2(left, baseline_y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, ps, col)
        baseline_y += size_px + ZenTextMetrics.LINE_SPACING


## Where a line's baseline sits inside its own size_px-tall slot, so the
## visual mass centres regardless of a font's internal ascent/descent split -
## a fixed box derived from the font's own metrics would move text on every
## font swap, defeating the point of making the font a choice.
func _baseline_offset(fnt: Font, ps: int, size_px: float) -> float:
    var asc := fnt.get_ascent(ps)
    var desc := fnt.get_descent(ps)
    var total := maxf(asc + desc, 0.0001)
    return size_px * (asc / total)


## One glyph, with the transform ALREADY in force (the crumble path places and
## spins each glyph with one). `draw_set_transform` REPLACES the canvas
## transform rather than composing with it, so the caller's transform must be
## passed in rather than set independently - otherwise every crumbled glyph
## draws at its raw baseline in canvas coordinates and the whole title
## collapses into one smear in the top-left corner, which is exactly what it
## did the first time this was gotten wrong.
func _draw_glyph(fnt: Font, ch: String, at: Vector2, size_px: float, col: Color,
                 outer := Transform2D.IDENTITY) -> void:
    var ps := int(round(size_px))
    if ps <= 0: return
    var baseline := Vector2(at.x, at.y + _baseline_offset(fnt, ps, size_px))
    if outer == Transform2D.IDENTITY:
        draw_string(fnt, baseline, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, ps, col)
    else:
        draw_set_transform_matrix(outer)
        draw_string(fnt, baseline, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, ps, col)
        draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_crumbled(t: float, fnt: Font, size_px: float, spacing: float, rot: float,
                    crumble: float, left: float, top: float, col: Color) -> void:
    var c_dir := prop("crumble_dir", t, crumble_dir)
    var c_spread := prop("crumble_spread", t, crumble_spread)
    var c_dist := prop("crumble_dist", t, crumble_dist)
    var c_spin := prop("crumble_spin", t, crumble_spin)
    # Quadratic in crumble: letters accelerate away, so most of the travel
    # happens late and the text stays readable as it starts to go.
    var reach := crumble * crumble * design().y * c_dist
    var ps := int(round(size_px))

    var pen_x := left
    var pen_y := top
    var idx := 0
    for ch in text:
        if ch == "\n":
            pen_x = left
            pen_y += size_px + spacing      # the C uses spacing here, not LINE_SPACING
            continue
        # Native per-glyph advance, replacing the raylib WIDTHS table - kept
        # scattered letters at the same rhythm as the block text beside them.
        var advance := fnt.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, ps).x + spacing
        if ch != " ":
            # The angle hash is OFFSET from the spin hash so the two stay
            # independent: otherwise a glyph's tumble would predict which way it
            # flies and the cone would visibly pair up at narrow spreads.
            var ang := deg_to_rad(c_dir + rand11i(idx + 977) * c_spread * 0.5)
            var gsz := ZenTextMetrics.measure(ch, size_px, fnt)
            var org := gsz * 0.5
            var ctr := Vector2(pen_x + org.x + cos(ang) * reach,
                               pen_y + org.y + sin(ang) * reach)
            var grot := rot + deg_to_rad(crumble * (rand11i(idx) * c_spin))
            _draw_glyph(fnt, ch, -org, size_px, col,
                        Transform2D(grot, Vector2.ONE, 0.0, ctr))
            idx += 1
        pen_x += advance
