@tool
class_name ZenPixelShape
extends Resource
##
## A pixel shape: the original editor's `.shp` visual asset, as a Godot
## Resource (src/anim/anim_shape_pool.h).
##
## A 2-bit grid - each cell is EMPTY, FILL or OUTLINE - with NO colour of its
## own. A custom ZenShape tints fill cells with its `color` track and outline
## cells with its `outline_color` track, so both stay animatable; baking a
## colour into the asset would freeze exactly what an animation wants to move.
##
## Stored as `.tres` under res://assets/shapes/ so a scene references it as a
## real ext_resource, the inspector edits it, and every canvas using it
## redraws on `changed`. `.shp` text is still read and written
## (from_shp_text / to_shp_text) for round-tripping with the raylib editor.
##

const EMPTY := 0
const FILL := 1
const OUTLINE := 2

## Per-axis cap, ANIM_SHAPE_GRID_MAX in the original.
const GRID_MAX := 128

## Grid size in cells. Assigning it resizes, keeping the top-left region.
@export var size := Vector2i(24, 16):
    set(v):
        var nv := Vector2i(clampi(v.x, 1, GRID_MAX), clampi(v.y, 1, GRID_MAX))
        if nv == size and cells.size() == nv.x * nv.y: return
        var old := cells
        var ow := size.x
        var oh := size.y
        size = nv
        cells = PackedByteArray()
        cells.resize(nv.x * nv.y)
        for y in mini(oh, nv.y):
            for x in mini(ow, nv.x):
                var i := y * ow + x
                if i < old.size(): cells[y * nv.x + x] = old[i]
        _changed()

## Row-major cell values, size.x * size.y long.
@export var cells := PackedByteArray():
    set(v):
        cells = v
        _changed()

var _tex_fill: ImageTexture = null
var _tex_line: ImageTexture = null


func _init() -> void:
    if cells.size() != size.x * size.y:
        cells.resize(size.x * size.y)


func get_cell(x: int, y: int) -> int:
    if x < 0 or y < 0 or x >= size.x or y >= size.y: return EMPTY
    var i := y * size.x + x
    return cells[i] if i < cells.size() else EMPTY


## Set one cell. Does NOT emit `changed` - a brush stroke sets hundreds of
## cells, so the caller calls commit() once when the stroke is done.
func set_cell(x: int, y: int, v: int) -> void:
    if x < 0 or y < 0 or x >= size.x or y >= size.y: return
    cells[y * size.x + x] = v


## Publish edits made through set_cell(): drop the cached textures and tell
## every user of this resource to redraw.
func commit() -> void:
    _changed()


func count(v: int) -> int:
    return cells.count(v)


func clear() -> void:
    cells.fill(EMPTY)
    _changed()


## Every inked cell becomes `v`; empty cells stay empty (bulk ink).
func convert_ink(v: int) -> void:
    for i in cells.size():
        if cells[i] != EMPTY: cells[i] = v
    _changed()


## The boundary rule (shape_editor.c Downsample): a FILL cell with an empty
## or off-grid 4-neighbour becomes OUTLINE. Read from a copy, so a promoted
## cell does not make its neighbour an edge too and eat the whole shape.
func auto_outline() -> void:
    var src := cells.duplicate()
    var w := size.x
    var h := size.y
    for y in h:
        for x in w:
            if src[y * w + x] != FILL: continue
            var edge := x == 0 or y == 0 or x == w - 1 or y == h - 1 \
                or src[y * w + x - 1] == EMPTY or src[y * w + x + 1] == EMPTY \
                or src[(y - 1) * w + x] == EMPTY or src[(y + 1) * w + x] == EMPTY
            if edge: cells[y * w + x] = OUTLINE
    _changed()


## The two stencils a custom ZenShape draws: white where the cell is FILL
## (resp. OUTLINE), transparent elsewhere, so a draw modulate is the tint.
## Built lazily and cached until the next change.
func fill_texture() -> ImageTexture:
    if _tex_fill == null: _tex_fill = _stencil(FILL)
    return _tex_fill


func outline_texture() -> ImageTexture:
    if _tex_line == null: _tex_line = _stencil(OUTLINE)
    return _tex_line


func _stencil(v: int) -> ImageTexture:
    var data := PackedByteArray()
    data.resize(size.x * size.y * 2)
    for i in mini(cells.size(), size.x * size.y):
        data[i * 2] = 255
        data[i * 2 + 1] = 255 if cells[i] == v else 0
    var img := Image.create_from_data(size.x, size.y, false, Image.FORMAT_LA8, data)
    return ImageTexture.create_from_image(img)


func _changed() -> void:
    _tex_fill = null
    _tex_line = null
    emit_changed()


# ---------------------------------------------------------------------------
#  .shp text (anim_shape_pool.c ReadShapeFile / AnimShapePoolSaveOne)
# ---------------------------------------------------------------------------

## Parse `.shp` text, or null when there is no `size` before `rows` - the
## same rejection as the original reader. Unknown keys skip one value, and a
## short `rows` block ending early in `end` is tolerated.
static func from_shp_text(text: String) -> ZenPixelShape:
    var w := 0
    var h := 0
    var have_size := false
    var rows: Array[String] = []
    var in_rows := false
    for raw in text.split("\n"):
        var line := raw.strip_edges()
        if in_rows:
            if line.is_empty(): continue
            # Rows are read as whole tokens, so a row starting with '#' is a
            # row of fill, never a comment.
            var tok := line.split(" ", false)[0]
            if tok == "end" or rows.size() >= h:
                in_rows = false
                if tok == "end": break
                continue
            rows.append(tok)
            if rows.size() >= h: in_rows = false
            continue
        var hash := line.find("#")
        if hash >= 0: line = line.substr(0, hash)
        var toks := line.split(" ", false)
        var i := 0
        while i < toks.size():
            var key := toks[i]
            if key == "size" and i + 2 < toks.size():
                w = clampi(int(toks[i + 1]), 1, GRID_MAX)
                h = clampi(int(toks[i + 2]), 1, GRID_MAX)
                have_size = true
                i += 3
            elif key == "rows":
                if not have_size: return null
                in_rows = true
                i += 1
            elif key == "end":
                i = toks.size()
            else:
                i += 2                      # `shape <name>` and unknown keys
    if not have_size: return null

    var s := ZenPixelShape.new()
    s.size = Vector2i(w, h)
    var c := PackedByteArray()
    c.resize(w * h)
    for y in mini(rows.size(), h):
        var row := rows[y]
        for x in mini(row.length(), w):
            c[y * w + x] = _px_val(row[x])
    s.cells = c
    return s


func to_shp_text(shape_name: String) -> String:
    var out := PackedStringArray()
    out.append("# pixel shape - see src/anim/anim_shape_pool.h for the grammar")
    out.append("# '.' empty   '#' fill (AP_S_COLOR)   'O' outline (AP_S_OUTLINE_COLOR)")
    out.append("shape %s" % shape_name)
    out.append("size %d %d" % [size.x, size.y])
    out.append("rows")
    for y in size.y:
        var row := ""
        for x in size.x:
            row += _px_char(get_cell(x, y))
        out.append(row)
    out.append("end")
    return "\n".join(out) + "\n"


static func _px_val(ch: String) -> int:
    if ch == "#": return FILL
    if ch == "O" or ch == "o": return OUTLINE
    return EMPTY


static func _px_char(v: int) -> String:
    return "#" if v == FILL else ("O" if v == OUTLINE else ".")


## Shape names follow the original's rules (anim_shape_pool.c:41-52): 1-23
## characters, no whitespace, `#`, `/` or `\`, and no leading `_` (a leading
## underscore marks a file the pool skips).
static func valid_name(n: String) -> bool:
    if n.is_empty() or n.length() > 23 or n.begins_with("_"): return false
    for ch in n:
        if ch in [" ", "\t", "#", "/", "\\", ".", ":"]: return false
    return true
