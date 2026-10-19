extends SceneTree

## Rebuilds raylib's built-in 10px bitmap font - the font the original Zen
## Editor drew every text element with (GetFontDefault(), anim.c:1149) - as a
## Godot FontFile at res://addons/zen/fonts/raylib_default_10px.tres. Run once,
## then diff:
##
##   ./Godot_v4.7.2-stable_linux.x86_64 --headless --path . --script res://tools/gen_raylib_font.gd
##   ... --rtext=/path/to/raylib/src/rtext.c
##       (default: ../raylib_base_template/build/_deps/raylib-src/src/rtext.c)
##
## The glyph data is PARSED out of rtext.c's LoadFontDefault() rather than
## copied here, so raylib stays its one source of truth. The decode mirrors it
## line for line:
##   - defaultFontData[512]: a 128x128 1-bit atlas, 32 pixels per uint32,
##     bit j -> pixel i + j (LSB is the leftmost pixel, despite the j = 31..0
##     loop order in rtext.c);
##   - charsWidth[224]: glyph widths from codepoint 32; every cell is
##     charsHeight=10 tall with a charsDivisor=1 px gap on all sides, packed in
##     rows that wrap when the next glyph would cross 128px.
## Each glyph's advance is width + 1: raylib draws with spacing
## sizePx / baseSize (TextSpacingFor, anim.c:1127), one base pixel - baking it
## into the advance lets Godot's own layout reproduce raylib's rhythm.

const DEFAULT_RTEXT := "../raylib_base_template/build/_deps/raylib-src/src/rtext.c"
const OUT := "res://addons/zen/fonts/raylib_default_10px.tres"
const ATLAS := 128
const CHARS_HEIGHT := 10
const CHARS_DIVISOR := 1
const GLYPHS := 224
const FIRST_CP := 32
## Baseline split of the 10px cell. Only the ratio matters to ZenText (it
## places each line's baseline proportionally in its slot), and the glyph
## offset is -ASCENT, so the cell top always meets the slot top either way.
const ASCENT := 8
const DESCENT := 2


func _init() -> void:
    var path := ProjectSettings.globalize_path("res://").path_join(DEFAULT_RTEXT)
    for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
        if a.begins_with("--rtext="): path = a.trim_prefix("--rtext=")
    var src := FileAccess.get_file_as_string(path)
    if src.is_empty():
        push_error("gen_raylib_font: cannot read %s" % path)
        quit(1)
        return
    var data := int_array(src, "defaultFontData[512]")
    var widths := int_array(src, "charsWidth[224]")
    if data.size() != 512 or widths.size() != GLYPHS:
        push_error("gen_raylib_font: parsed %d data words / %d widths, want 512 / %d"
                   % [data.size(), widths.size(), GLYPHS])
        quit(1)
        return

    var f := build(data, widths)
    var err := ResourceSaver.save(f, OUT)
    if err != OK:
        push_error("gen_raylib_font: save failed (%d)" % err)
        quit(1)
        return
    print("gen_raylib_font: wrote %s (%d glyphs)" % [OUT, GLYPHS])
    quit(0)


## The comma-separated integers of the C array initialiser that follows `decl`.
static func int_array(src: String, decl: String) -> PackedInt64Array:
    var out := PackedInt64Array()
    var at := src.find(decl)
    if at < 0: return out
    var open := src.find("{", at)
    var close := src.find("}", open)
    if open < 0 or close < 0: return out
    for tok in src.substr(open + 1, close - open - 1).split(","):
        var s := tok.strip_edges()
        if s.is_empty(): continue
        out.append(s.hex_to_int() if s.begins_with("0x") else s.to_int())
    return out


static func atlas_image(data: PackedInt64Array) -> Image:
    var img := Image.create_empty(ATLAS, ATLAS, false, Image.FORMAT_RGBA8)
    # Unset pixels are transparent WHITE, as in raylib (gray 0xff, alpha 0),
    # so a filtered edge never fringes dark.
    img.fill(Color(1, 1, 1, 0))
    var counter := 0
    for i in range(0, ATLAS * ATLAS, 32):
        for j in 32:
            if data[counter] & (1 << j):
                var p := i + j
                img.set_pixel(p % ATLAS, p / ATLAS, Color.WHITE)
        counter += 1
    return img


## Glyph rects exactly as rtext.c lays them out (LoadFontDefault, the
## currentPosX / testPosX walk).
static func glyph_rects(widths: PackedInt64Array) -> Array[Rect2i]:
    var rects: Array[Rect2i] = []
    var line := 0
    var cur_x := CHARS_DIVISOR
    var test_x := CHARS_DIVISOR
    for i in GLYPHS:
        var w := int(widths[i])
        var r := Rect2i(cur_x, CHARS_DIVISOR + line * (CHARS_HEIGHT + CHARS_DIVISOR), w, CHARS_HEIGHT)
        test_x += w + CHARS_DIVISOR
        if test_x >= ATLAS:
            line += 1
            cur_x = 2 * CHARS_DIVISOR + w
            test_x = cur_x
            r.position = Vector2i(CHARS_DIVISOR, CHARS_DIVISOR + line * (CHARS_HEIGHT + CHARS_DIVISOR))
        else:
            cur_x = test_x
        rects.append(r)
    return rects


static func build(data: PackedInt64Array, widths: PackedInt64Array) -> FontFile:
    var f := FontFile.new()
    f.font_name = "raylib default"
    f.fixed_size = CHARS_HEIGHT
    f.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
    f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
    f.generate_mipmaps = false
    var sz := Vector2i(CHARS_HEIGHT, 0)
    f.set_cache_ascent(0, CHARS_HEIGHT, ASCENT)
    f.set_cache_descent(0, CHARS_HEIGHT, DESCENT)
    f.set_texture_image(0, sz, 0, atlas_image(data))
    var rects := glyph_rects(widths)
    for i in GLYPHS:
        var cp := FIRST_CP + i
        var r := rects[i]
        f.set_glyph_texture_idx(0, sz, cp, 0)
        f.set_glyph_uv_rect(0, sz, cp, Rect2(r))
        f.set_glyph_size(0, sz, cp, Vector2(r.size))
        f.set_glyph_offset(0, sz, cp, Vector2(0, -ASCENT))
        f.set_glyph_advance(0, CHARS_HEIGHT, cp, Vector2(r.size.x + 1, 0))
    return f
