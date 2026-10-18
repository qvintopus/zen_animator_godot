@tool
class_name ZenTextMetrics
extends RefCounted
##
## Text layout against a real Godot font, replacing the raylib bitmap-font
## emulation this used to reproduce exactly (see docs/plans/godot-integration.md
## Task 2 - the old WIDTHS table and text_ref.txt comparison are gone).
##
## Two traps this exists to not re-fall into:
##   - Font.get_string_size() IGNORES "\n" (measured on 4.7.2: "two\nlines" at
##     size 72 -> (293, 99), one line's worth of height). So height is
##     computed from the LAYOUT, not the font: box.y = size_px * lines +
##     LINE_SPACING * (lines - 1). This also means the box stays a layout
##     rule, not a font metric - swapping fonts does not move the text, only
##     changes its letterforms, which is the whole point of making the font a
##     choice.
##   - A fixed-size bitmap font reports a flat ascent == size; a real font's
##     ascent+descent (e.g. 77+22 at size 72) is bigger than size_px, so the
##     text BLOCK's height must come from the layout rule above, while each
##     LINE's own baseline (in zen_text.gd) is placed proportionally inside
##     that line's slot, not by summing the font's own metrics.
##

const BASE_SIZE := 10
## Vertical gap between wrapped lines, in px. Matches raylib's old default.
const LINE_SPACING := 2.0


## Zen's spacing rule: TextSpacingFor(sizePx) = sizePx / baseSize (anim.c:1127).
## No longer used for LAYOUT (native kerning owns inter-glyph spacing now) -
## kept because crumble still needs a per-glyph advance between scattered
## letters.
static func spacing_for(size_px: float) -> float:
    return size_px / float(BASE_SIZE)


## The text block's size at `size_px` against `font`. Empty text measures
## {0,0} - not a degenerate run of the per-line loop, which would still give a
## correct {0,0} but needlessly asks the font for an empty string's size.
static func measure(text: String, size_px: float, font: Font) -> Vector2:
    if text.is_empty(): return Vector2.ZERO
    var lines := text.split("\n")
    var ps := int(round(size_px))
    var w := 0.0
    for line in lines:
        w = maxf(w, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, ps).x)
    var h := size_px * lines.size() + LINE_SPACING * (lines.size() - 1)
    return Vector2(w, h)
