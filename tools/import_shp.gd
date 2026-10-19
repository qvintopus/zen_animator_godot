extends SceneTree

## Converts the original editor's `.shp` pixel shapes into ZenPixelShape
## resources under res://assets/shapes/. Run once, then diff:
##
##   ./Godot_v4.7.2-stable_linux.x86_64 --headless --path . --script res://tools/import_shp.gd
##   ... --src=/path/to/raylib_base_template   (default: ../raylib_base_template)
##
## Builtin shapes (resources/shapes/) are read first and user shapes (shapes/)
## second, so a user shape replaces a builtin of the same name - the original
## pool's load order.
##
## This is the ONLY place that knows the .shp text format: a one-shot
## migration, not a round-trip. The grammar (anim_shape_pool.h): `#` comments,
## `shape <name>` (advisory - the file basename wins), `size <w> <h>`, then
## `rows` and h rows of '.' empty / '#' fill / 'O' outline, then `end`.

const DEFAULT_SRC := "../raylib_base_template"


func _init() -> void:
    var src := ProjectSettings.globalize_path("res://").path_join(DEFAULT_SRC)
    for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
        if a.begins_with("--src="): src = a.trim_prefix("--src=")
    var found := {}
    for sub in ["resources/shapes", "shapes"]:
        var dir := src.path_join(sub)
        var d := DirAccess.open(dir)
        if d == null: continue
        for f in d.get_files():
            if not f.ends_with(".shp") or f.begins_with("_"): continue
            found[f.get_basename()] = dir.path_join(f)

    DirAccess.make_dir_recursive_absolute("res://assets/shapes")
    var n := 0
    for name in found:
        var text := FileAccess.get_file_as_string(found[name])
        var s := parse(text)
        if s == null:
            push_error("import_shp: cannot parse %s" % found[name])
            continue
        var out := "res://assets/shapes/%s.tres" % name
        if ResourceSaver.save(s, out) != OK:
            push_error("import_shp: cannot save %s" % out)
            continue
        print("  %s  %dx%d  -> %s" % [name, s.size.x, s.size.y, out])
        n += 1
    print("imported %d shapes" % n)
    quit()


## Parse `.shp` text, or null when there is no `size` before `rows` - the
## original reader's rejection. Unknown keys skip one value, and a short
## `rows` block ending early in `end` is tolerated.
static func parse(text: String) -> ZenPixelShape:
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
                w = clampi(int(toks[i + 1]), 1, ZenPixelShape.GRID_MAX)
                h = clampi(int(toks[i + 2]), 1, ZenPixelShape.GRID_MAX)
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


static func _px_val(ch: String) -> int:
    if ch == "#": return ZenPixelShape.FILL
    if ch == "O" or ch == "o": return ZenPixelShape.OUTLINE
    return ZenPixelShape.EMPTY
