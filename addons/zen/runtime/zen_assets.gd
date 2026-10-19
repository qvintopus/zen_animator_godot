@tool
class_name ZenAssets
extends RefCounted
##
## Where visual assets live, and name -> resource lookup.
##
## Two roots, shipped and user:
##   - res://assets/shapes/   shipped with the project (and where the editor
##                            saves while running from the Godot editor);
##   - user://assets/shapes/  where an EXPORTED build saves, since res:// is
##                            read-only there. A user shape shadows a shipped
##                            one of the same name.
##
## A shape's NAME is its file basename; the resource stores no name.
##

const SHAPE_DIRS := ["res://assets/shapes", "user://assets/shapes"]


## Every shape name, sorted, each mapped to the path that wins.
static func shape_paths() -> Dictionary:
    var out := {}
    for dir in SHAPE_DIRS:
        var d := DirAccess.open(dir)
        if d == null: continue
        for f in d.get_files():
            # An exported build lists `x.tres.remap`; load() takes the plain path.
            var file := f.trim_suffix(".remap")
            if not file.ends_with(".tres"): continue
            out[file.get_basename()] = "%s/%s" % [dir, file]
    var names := out.keys()
    names.sort_custom(func(a, b): return String(a).naturalnocasecmp_to(String(b)) < 0)
    var sorted := {}
    for n in names: sorted[n] = out[n]
    return sorted


static func shape_names() -> Array:
    return shape_paths().keys()


## The shape called `name`, or null when there is none.
static func load_shape(name: String) -> ZenPixelShape:
    var p: String = shape_paths().get(name, "")
    if p.is_empty(): return null
    return load(p) as ZenPixelShape


## Where a save of `name` should go: the shipped root when it is writable
## (running from the editor), the user root otherwise.
static func save_path(name: String) -> String:
    var dir := SHAPE_DIRS[0] if OS.has_feature("editor") else SHAPE_DIRS[1]
    return "%s/%s.tres" % [dir, name]


## Save `shape` as `name`. When that resource is already loaded (a scene in
## the gallery uses it), the LOADED instance takes the new cells, so every
## canvas drawing it redraws on `changed` - the editor works on a copy and
## only publishes on save. Returns the instance that was written.
static func save_shape(shape: ZenPixelShape, name: String) -> ZenPixelShape:
    var path := save_path(name)
    DirAccess.make_dir_recursive_absolute(path.get_base_dir())
    var target := shape
    if ResourceLoader.has_cached(path):
        target = load(path) as ZenPixelShape
        if target == null: target = shape
        elif target != shape:
            target.size = shape.size
            target.cells = shape.cells.duplicate()
    if ResourceSaver.save(target, path) != OK: return null
    if target == shape: shape.take_over_path(path)
    return target


## Delete the file `name` resolves to. A shipped shape shadowed by a user one
## comes back into view afterwards.
static func delete_shape(name: String) -> Error:
    var p: String = shape_paths().get(name, "")
    if p.is_empty(): return ERR_FILE_NOT_FOUND
    return DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


## Move a project file to the OS trash, so a delete from the gallery can be
## undone from the file manager. Falls back to deleting it outright where
## there is no trash.
static func trash(path: String) -> Error:
    var g := ProjectSettings.globalize_path(path)
    if not FileAccess.file_exists(path): return ERR_FILE_NOT_FOUND
    if OS.move_to_trash(g) == OK: return OK
    return DirAccess.remove_absolute(g)


## The name a shape resource is known by: its file basename.
static func name_of(shape: ZenPixelShape) -> String:
    if shape == null or shape.resource_path.is_empty(): return ""
    return shape.resource_path.get_file().get_basename()
