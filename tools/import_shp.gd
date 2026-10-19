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
        var s := ZenPixelShape.from_shp_text(text)
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
