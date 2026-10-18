@tool
class_name ZenTextMetrics
extends RefCounted
##
## raylib default-font text metrics, reproduced exactly.
##
## WHY: Zen lays text out with raylib's built-in 10px bitmap font - a fixed
## per-glyph width table, not a real typeface. Position is the text CENTRE, so
## every text element's placement depends on the measured box, and a different
## metric moves the text even if the glyphs look similar.
##
## So the port splits the two concerns: LAYOUT comes from this table (exact),
## while the GLYPHS are drawn with a Godot font (necessarily different shapes).
## Centring, line widths, line breaks and crumble pen positions therefore match
## the original; only letterforms differ. Embedding the raylib bitmap font would
## close that last gap, at the cost of carrying a 128x128 atlas and giving up
## Godot's font handling - not worth it unless the drift proves objectionable.
##
## Verified against the real raylib (MeasureTextEx with GetFontDefault) - see
## tests/text_ref.txt, compared in run_tests.gd.
##
## The default font has baseSize 10, advanceX 0 and offsetX 0 for every glyph,
## so MeasureTextEx reduces to:
##     x = sum(width[cp]) * (sizePx/10) + (longestLineChars - 1) * spacing
##     y = sizePx + (lines - 1) * (sizePx + 2)
##

const BASE_SIZE := 10
## raylib's textLineSpacing default (rtext.c), added per extra line.
const LINE_SPACING := 2.0
const FIRST_CODEPOINT := 32

## Glyph widths for codepoints 32..255, lifted verbatim from raylib's
## rtext.c charsWidth[224].
const WIDTHS := [
    3, 1, 4, 6, 5, 7, 6, 2, 3, 3, 5, 5, 2, 4, 1, 7, 5, 2, 5, 5, 5, 5, 5, 5, 5, 5, 1, 1, 3, 4, 3, 6,
    7, 6, 6, 6, 6, 6, 6, 6, 6, 3, 5, 6, 5, 7, 6, 6, 6, 6, 6, 6, 7, 6, 7, 7, 6, 6, 6, 2, 7, 2, 3, 5,
    2, 5, 5, 5, 5, 5, 4, 5, 5, 1, 2, 5, 2, 5, 5, 5, 5, 5, 5, 5, 4, 5, 5, 5, 5, 5, 5, 3, 1, 3, 4, 4,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 5, 5, 5, 7, 1, 5, 3, 7, 3, 5, 4, 1, 7, 4, 3, 5, 3, 3, 2, 5, 6, 1, 2, 2, 3, 5, 6, 6, 6, 6,
    6, 6, 6, 6, 6, 6, 7, 6, 6, 6, 6, 6, 3, 3, 3, 3, 7, 6, 6, 6, 6, 6, 6, 5, 6, 6, 6, 6, 6, 6, 4, 6,
    5, 5, 5, 5, 5, 5, 9, 5, 5, 5, 5, 5, 2, 2, 3, 3, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 3, 5,]


## Zen's spacing rule: TextSpacingFor(sizePx) = sizePx / baseSize (anim.c:1127).
static func spacing_for(size_px: float) -> float:
    return size_px / float(BASE_SIZE)


static func glyph_width(cp: int) -> int:
    var i := cp - FIRST_CODEPOINT
    if i < 0 or i >= WIDTHS.size(): return 0
    return WIDTHS[i]


## Port of MeasureTextEx for the default font. Empty text measures {0,0}, which
## is raylib's early-out - not a degenerate run of the formula (that would give
## a negative width from the -1 character term).
static func measure(text: String, size_px: float) -> Vector2:
    if text.is_empty(): return Vector2.ZERO
    var spacing := spacing_for(size_px)
    var scale := size_px / float(BASE_SIZE)

    var best_w := 0.0
    var w := 0.0
    var best_chars := 0
    var chars := 0
    var height := size_px

    for ch in text:
        chars += 1
        if ch != "\n":
            w += float(glyph_width(ch.unicode_at(0)))
        else:
            best_w = maxf(best_w, w)
            chars = 0
            w = 0.0
            height += size_px + LINE_SPACING
        best_chars = maxi(best_chars, chars)
    best_w = maxf(best_w, w)

    return Vector2(best_w * scale + float(best_chars - 1) * spacing, height)
