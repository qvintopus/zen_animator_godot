@tool
class_name ZenSceneOps
extends RefCounted
##
## Scene (document) CRUD: new, open, save, rename, duplicate, delete, and the
## snapshot the editor's undo is built on.
##
## Two roots, like ZenAssets: res://anims ships with the project (and is where
## a save lands while running from the Godot editor), user://anims is where an
## exported build saves, since res:// is read-only there. A user scene shadows
## a shipped one of the same name.
##
## RESOURCES ARE SHARED, which is the trap here. An instantiated scene shares
## its built-in sub-resources - the Animations - with the cached PackedScene,
## and a pack() stores references to them, not copies. Editing a key in either
## would silently edit the other: the gallery would play unsaved edits, and an
## undo snapshot would change along with the scene it is meant to preserve.
## detach() gives a canvas its own deep copies and snapshot() packs copies, so
## every way a canvas enters or leaves the editor goes through one of them.
##
## Node.duplicate() is NOT used for copies: on a canvas instantiated from a
## file it re-instantiates that file and then fails on any child added since.
##

const DIRS := ["res://anims", "user://anims"]
## The C editor's new-document clock (AnimDocInit, anim.c:90-105).
const NEW_DURATION := 2.0
const NEW_BLEND := 0.3


## Every scene name mapped to the path that wins (user over shipped).
##
## FOLDERS are plain subdirectories of a root, one level deep
## (res://anims/signal_demo/sig_code.tscn). The basename stays the scene's id
## across folders - is_name_free checks every folder - so everything that
## goes by name (path_of, rename, the export chain, --anim=) ignores them.
static func scene_paths() -> Dictionary:
    var out := {}
    for root in DIRS:
        for dir in _scan_dirs(root):
            for f in DirAccess.get_files_at(dir):
                var file := f.trim_suffix(".remap")
                if not file.ends_with(".tscn"): continue
                out[file.get_basename()] = "%s/%s" % [dir, file]
    return out


## `root` and its direct subdirectories (the folders).
static func _scan_dirs(root: String) -> Array:
    if not DirAccess.dir_exists_absolute(root): return []
    var out: Array = [root]
    for sub in DirAccess.get_directories_at(root):
        if not sub.begins_with("."): out.append("%s/%s" % [root, sub])
    return out


static func path_of(nm: String) -> String:
    return String(scene_paths().get(nm, ""))


## The folder a scene path sits in, "" at a root's top level.
static func folder_of_path(path: String) -> String:
    var dir := path.get_base_dir()
    return "" if DIRS.has(dir) else dir.get_file()


static func folder_of(nm: String) -> String:
    var p := path_of(nm)
    return "" if p.is_empty() else folder_of_path(p)


## Every folder in either root, empty ones too, sorted.
static func folders() -> Array:
    var uniq := {}
    for root in DIRS:
        for dir in _scan_dirs(root):
            if dir != root: uniq[String(dir).get_file()] = true
    var out := uniq.keys()
    out.sort_custom(func(a, b): return String(a).naturalnocasecmp_to(String(b)) < 0)
    return out


## The root saves go to: the shipped one when writable, else user://.
static func write_root() -> String:
    return DIRS[0] if OS.has_feature("editor") else DIRS[1]


static func _dir(root: String, folder: String) -> String:
    return root if folder.is_empty() else "%s/%s" % [root, folder]


## Where a save of `nm` goes. An existing scene in the writable root saves in
## place, so editing never pulls it out of its folder; anything else lands in
## `folder` of the writable root.
static func save_path(nm: String, folder := "") -> String:
    var cur := path_of(nm)
    if not cur.is_empty() and cur.begins_with(write_root() + "/"):
        return cur
    if not cur.is_empty() and folder.is_empty(): folder = folder_of_path(cur)
    return "%s/%s.tscn" % [_dir(write_root(), folder), nm]


## A file-safe scene name ("My Intro!" -> "my_intro_").
static func clean_name(raw: String) -> String:
    var out := ""
    for ch in raw.strip_edges().to_lower():
        out += ch if (ch.is_valid_identifier() or ch.is_valid_int()) else "_"
    while out.contains("__"): out = out.replace("__", "_")
    return out


static func is_name_free(nm: String) -> bool:
    return not nm.is_empty() and not scene_paths().has(nm)


static func unique_name(base: String) -> String:
    base = clean_name(base)
    if base.is_empty(): base = "untitled"
    if is_name_free(base): return base
    var n := 2
    while not is_name_free("%s_%d" % [base, n]): n += 1
    return "%s_%d" % [base, n]


# ---------------------------------------------------------------------------
#  Create / open
# ---------------------------------------------------------------------------

## A new document with the C editor's starter content (anim_editor_zen.c:143):
## a "title" text reading HELLO that fades in over the first 0.6s.
static func new_canvas(nm: String) -> ZenCanvas:
    var title := ZenElemFactory.new_elem("text", "title")
    title["text"] = "HELLO"
    title["pos"] = Vector2(0.5, 0.10)
    title["size"] = Vector2(0.12, 0.12)
    title["tracks"] = {"alpha": [
        {"t": 0.0, "v": 0.0, "ease": "linear"},
        {"t": 0.6, "v": 1.0, "ease": "sineOut"}]}
    var doc := {
        "name": nm, "duration": NEW_DURATION, "intro_end": 0.0,
        "outro_start": NEW_DURATION, "loop_blend": NEW_BLEND, "loop_smooth": true,
        "elems": [title], "signals": [], "pauses": [],
    }
    var canvas := ZenElemFactory.build(doc)
    canvas.design_size = ZenSettings.canvas_size()
    canvas.sync_from_animation()
    return canvas


## Load scene `path` as an editable canvas of its own (see detach()).
static func open(path: String) -> ZenCanvas:
    var ps := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE) as PackedScene
    if ps == null: return null
    var canvas := ps.instantiate() as ZenCanvas
    if canvas == null: return null
    # Not an instance of its file any more: packing it must store the whole
    # tree, not an inherited scene that only records differences.
    canvas.scene_file_path = ""
    detach(canvas)
    return canvas


## Give `canvas` deep copies of everything it shares by reference: the
## Animations (built-in sub-resources), the string pool (one copy, still
## shared by every text) and the bus's signal data.
static func detach(canvas: ZenCanvas) -> void:
    ZenStringOps.detach(canvas)
    var ap := ZenAnimBuilder.find_player(canvas)
    if ap != null:
        for lib_name in ap.get_animation_library_list():
            var lib := _deep_library(ap.get_animation_library(lib_name))
            ap.remove_animation_library(lib_name)
            ap.add_animation_library(lib_name, lib)
        ap.assigned_animation = ZenAnimBuilder.ANIM
    var bus := canvas.bus()
    if bus != null: bus.signals_data = bus.signals_data.duplicate(true)
    canvas.sync_from_animation()
    canvas.timeline_dirty()


## A frozen copy of `canvas`, for an undo snapshot: packed with copies of
## its Animations and signal data swapped in for the pack and the originals
## put straight back, so later edits to the live canvas cannot reach it.
static func snapshot(canvas: ZenCanvas) -> PackedScene:
    _own(canvas)
    var ap := ZenAnimBuilder.find_player(canvas)
    var libs := {}
    if ap != null:
        for lib_name in ap.get_animation_library_list():
            libs[lib_name] = ap.get_animation_library(lib_name)
        for lib_name in libs:
            ap.remove_animation_library(lib_name)
            ap.add_animation_library(lib_name, _deep_library(libs[lib_name]))
    var bus := canvas.bus()
    var sigs: Array = bus.signals_data if bus != null else []
    if bus != null: bus.signals_data = sigs.duplicate(true)
    var pool := ZenStringOps.pool(canvas)
    ZenStringOps.detach(canvas)
    var ps := PackedScene.new()
    ps.pack(canvas)
    ZenStringOps.repoint(canvas, pool)
    if ap != null:
        for lib_name in libs:
            ap.remove_animation_library(lib_name)
            ap.add_animation_library(lib_name, libs[lib_name])
        ap.assigned_animation = ZenAnimBuilder.ANIM
    if bus != null: bus.signals_data = sigs
    return ps


## A live canvas from a snapshot, detached so the snapshot stays frozen.
static func restore(ps: PackedScene) -> ZenCanvas:
    var c := ps.instantiate() as ZenCanvas
    if c != null: detach(c)
    return c


## A library holding its own copy of every Animation (duplicate(true) alone
## does not reach resources held inside the library's Dictionary).
static func _deep_library(src: AnimationLibrary) -> AnimationLibrary:
    var lib := AnimationLibrary.new()
    for an in src.get_animation_list():
        lib.add_animation(an, src.get_animation(an).duplicate(true))
    return lib


## Every descendant owned by `canvas`, so pack() keeps it.
static func _own(canvas: ZenCanvas) -> void:
    for c in canvas.get_children():
        c.owner = canvas


# ---------------------------------------------------------------------------
#  Save / rename / duplicate / delete
# ---------------------------------------------------------------------------

## Save `canvas` as scene `nm`, replacing any cached copy so the gallery plays
## the saved version. Returns the path written, or "".
static func save(canvas: ZenCanvas, nm: String, folder := "") -> String:
    return _save_to(canvas, save_path(nm, folder))


static func _save_to(canvas: ZenCanvas, path: String) -> String:
    DirAccess.make_dir_recursive_absolute(path.get_base_dir())
    _own(canvas)
    # The editor runs its canvas with live playback off; the saved scene must
    # still play on its own when opened (F6, the gallery).
    var live := canvas.live_playback
    canvas.live_playback = true
    var ps := PackedScene.new()
    var packed := ps.pack(canvas)
    canvas.live_playback = live
    if packed != OK: return ""
    if ResourceSaver.save(ps, path) != OK: return ""
    ps.take_over_path(path)
    return path


# ---------------------------------------------------------------------------
#  The clip library: scenes of copied elements (ZenClipOps), kept apart from
#  the animations so they never show up as one.
# ---------------------------------------------------------------------------

const CLIP_DIRS := ["res://library", "user://library"]


## Every clip name mapped to its path (user over shipped), flat: no folders.
static func clip_paths() -> Dictionary:
    var out := {}
    for root in CLIP_DIRS:
        if not DirAccess.dir_exists_absolute(root): continue
        for f in DirAccess.get_files_at(root):
            var file := f.trim_suffix(".remap")
            if file.ends_with(".tscn"): out[file.get_basename()] = "%s/%s" % [root, file]
    return out


static func clip_names() -> Array:
    var out := clip_paths().keys()
    out.sort_custom(func(a, b): return String(a).naturalnocasecmp_to(String(b)) < 0)
    return out


static func clip_save_root() -> String:
    return CLIP_DIRS[0] if OS.has_feature("editor") else CLIP_DIRS[1]


## Save `clip` into the library as `nm` (cleaned). Returns the path, or "".
static func save_clip(clip: ZenCanvas, nm: String) -> String:
    nm = clean_name(nm)
    if nm.is_empty(): return ""
    return _save_to(clip, "%s/%s.tscn" % [clip_save_root(), nm])


static func open_clip(nm: String) -> ZenCanvas:
    var p := String(clip_paths().get(nm, ""))
    return open(p) if not p.is_empty() else null


static func delete_clip(nm: String) -> Error:
    var p := String(clip_paths().get(nm, ""))
    if p.is_empty(): return ERR_FILE_NOT_FOUND
    return DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


## Rename scene `from` to `to` on disk. Fails when `to` is taken.
static func rename(from: String, to: String) -> Error:
    var src := path_of(from)
    if src.is_empty(): return ERR_FILE_NOT_FOUND
    if not is_name_free(to): return ERR_ALREADY_EXISTS
    var dst := "%s/%s.tscn" % [src.get_base_dir(), to]
    return DirAccess.rename_absolute(ProjectSettings.globalize_path(src),
        ProjectSettings.globalize_path(dst))


## Copy scene `from` to a new scene `to` (saved where saves go).
static func duplicate_scene(from: String, to: String) -> Error:
    var src := path_of(from)
    if src.is_empty(): return ERR_FILE_NOT_FOUND
    if not is_name_free(to): return ERR_ALREADY_EXISTS
    var canvas := open(src)
    if canvas == null: return ERR_CANT_OPEN
    canvas.name = ZenElemFactory.node_name(to)
    var ok := not save(canvas, to, folder_of_path(src)).is_empty()
    canvas.free()
    return OK if ok else ERR_CANT_CREATE


## Move scene `nm` to the OS trash.
static func delete(nm: String) -> Error:
    var p := path_of(nm)
    if p.is_empty(): return ERR_FILE_NOT_FOUND
    return ZenAssets.trash(p)


# ---------------------------------------------------------------------------
#  Folders
# ---------------------------------------------------------------------------

## Move scene `nm` into `folder` ("" = the top level) of its own root.
static func move(nm: String, folder: String) -> Error:
    var src := path_of(nm)
    if src.is_empty(): return ERR_FILE_NOT_FOUND
    if folder_of_path(src) == folder: return OK
    var root := String(DIRS[0]) if src.begins_with(DIRS[0] + "/") else String(DIRS[1])
    var dir := _dir(root, folder)
    DirAccess.make_dir_recursive_absolute(dir)
    var dst := "%s/%s" % [dir, src.get_file()]
    var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(src),
        ProjectSettings.globalize_path(dst))
    if err == OK and ResourceLoader.has_cached(src):
        # The cached PackedScene still answers to the old path.
        (load(src) as Resource).take_over_path(dst)
    return err


static func make_folder(folder: String) -> Error:
    if folder.is_empty(): return ERR_INVALID_PARAMETER
    return DirAccess.make_dir_recursive_absolute(_dir(write_root(), folder))


## Rename `from` to `to` in every root that has it. Fails when `to` exists.
static func rename_folder(from: String, to: String) -> Error:
    if from.is_empty() or to.is_empty(): return ERR_INVALID_PARAMETER
    if folders().has(to): return ERR_ALREADY_EXISTS
    var err := ERR_FILE_NOT_FOUND
    for root in DIRS:
        var src := _dir(root, from)
        if not DirAccess.dir_exists_absolute(src): continue
        err = DirAccess.rename_absolute(ProjectSettings.globalize_path(src),
            ProjectSettings.globalize_path(_dir(root, to)))
        if err != OK: return err
    return err


## The scene names inside `folder`, across both roots.
static func scenes_in(folder: String) -> Array:
    var paths := scene_paths()
    return paths.keys().filter(func(n): return folder_of_path(String(paths[n])) == folder)


## Trash an EMPTY folder; one still holding scenes is refused (ERR_BUSY).
static func delete_folder(folder: String) -> Error:
    if folder.is_empty(): return ERR_INVALID_PARAMETER
    if not scenes_in(folder).is_empty(): return ERR_BUSY
    var err := ERR_FILE_NOT_FOUND
    for root in DIRS:
        var d := _dir(root, folder)
        if not DirAccess.dir_exists_absolute(d): continue
        var g := ProjectSettings.globalize_path(d)
        err = OK if OS.move_to_trash(g) == OK else DirAccess.remove_absolute(g)
        if err != OK: return err
    return err


## Indices of `entries` ({name, folder}) whose name or folder contains `query`,
## case-insensitively - the gallery search, like ZenOptions.filter_fonts.
static func filter(entries: Array, query: String) -> Array[int]:
    var q := query.strip_edges().to_lower()
    var out: Array[int] = []
    for i in entries.size():
        var e: Dictionary = entries[i]
        if q.is_empty() or String(e.get("name", "")).to_lower().contains(q) \
                or String(e.get("folder", "")).to_lower().contains(q):
            out.append(i)
    return out
