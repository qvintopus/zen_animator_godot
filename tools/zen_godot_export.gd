@tool
class_name ZenGodotExport
extends RefCounted
##
## Export an animation as a scene for ANOTHER Godot project: it plays there on
## F6 and can be the base of an inherited scene that game code drives
## (ZenCanvas's game API: play/stop/restart/resume/fire, `finished`).
##
## RE-PATH, DON'T CONVERT. The exported .tscn is the animation's own scene with
## its dependency paths rewritten, plus the files those paths name. Converting
## to stock Sprite2D/Label property tracks would lose signals, the smooth-loop
## blend, crumble text and tinted pixel shapes, while the runtime that already
## plays the scene from its own AnimationPlayer is ~3k lines - so it travels.
##
## Two modes:
##   STANDALONE - a private copy of the runtime under <sub>/zen_runtime/, with
##                every class_name stripped and cross-references rewritten to
##                preload consts (ZenCanvas -> ZRCanvas). It never collides with
##                an installed Zen plugin, or with a copy exported by another
##                version into another subfolder.
##   PLUGIN     - the scene points at res://addons/zen/, which the target must
##                have; `install_plugin` copies it there.
##
## Writes with absolute OS paths into the target folder; every path written
## INTO a file is a res:// path of the target project. uid= attributes are
## dropped: they belong to this project's uid cache and would only mislead the
## target's, which assigns fresh ones on import.
##

enum Mode { STANDALONE, PLUGIN }

const ADDON := "res://addons/zen/"
const RUNTIME_DIR := "res://addons/zen/runtime"
const FONTS_DIR := "res://addons/zen/fonts"
const ANIMS_DIR := "res://anims"

## Runtime files that stay home: user settings and the asset library are this
## app's, and the ZenSignals autoload needs a project.godot entry a plain copy
## cannot make (the plugin registers it).
const VENDOR_SKIP := ["zen_settings.gd", "zen_assets.gd", "zen_signals.gd"]

## The standalone copy's prefix: ZenCanvas -> ZRCanvas.
const PREFIX := "ZR"

const FONT_EXTS := ["ttf", "otf", "woff", "woff2", "fnt", "font"]


class Settings extends RefCounted:
    var target_dir := ""        # absolute; holds the target's project.godot
    var subdir := "zen"         # under the target's res://
    var mode := Mode.STANDALONE
    var install_plugin := false # PLUGIN mode: copy addons/zen into the target


## The subfolder as written into paths: no leading/trailing slash, "zen" when
## empty.
static func clean_subdir(sub: String) -> String:
    var s := sub.strip_edges().replace("\\", "/").trim_prefix("res://")
    while s.begins_with("/"): s = s.substr(1)
    while s.ends_with("/"): s = s.left(-1)
    return s if s != "" else "zen"


## "" when the settings can be exported with, else what is wrong.
static func validate(s: Settings) -> String:
    if s.target_dir == "":
        return "pick a target Godot project"
    if not FileAccess.file_exists(s.target_dir.path_join("project.godot")):
        return "not a Godot project (no project.godot): %s" % s.target_dir
    var sub := clean_subdir(s.subdir)
    if sub.split("/").has(".."):
        return "the subfolder must stay inside the project"
    if sub == "addons/zen" or sub.begins_with("addons/zen/"):
        return "the subfolder must not be the plugin's own folder"
    if s.mode == Mode.PLUGIN and not s.install_plugin \
            and not DirAccess.dir_exists_absolute(s.target_dir.path_join("addons/zen/runtime")):
        return "the target has no Zen plugin - tick \"install/update plugin\""
    return ""


## res:// root the runtime lives at in the target, with a trailing slash.
static func runtime_root(s: Settings) -> String:
    if s.mode == Mode.PLUGIN: return ADDON
    return "res://%s/zen_runtime/" % clean_subdir(s.subdir)


## What game code puts at the top of an inherited scene's root script.
static func extends_line(s: Settings) -> String:
    if s.mode == Mode.PLUGIN: return "extends ZenCanvas"
    return "extends \"%sruntime/zen_canvas.gd\"" % runtime_root(s)


## Absolute OS path of a target res:// path.
static func _abs(s: Settings, res_path: String) -> String:
    return s.target_dir.path_join(res_path.trim_prefix("res://"))


# ---------------------------------------------------------------------------
#  Text rewriting - pure, so it is tested on strings.
# ---------------------------------------------------------------------------

## Rewrite a .tscn/.tres: every ext_resource path through `path_map` (paths not
## in it are kept), every uid= attribute dropped, and - for the standalone copy
## - the script_class hint, which names a global class the target lacks.
static func rewrite_resource(text: String, path_map: Dictionary, drop_script_class: bool) -> String:
    var out := PackedStringArray()
    var uid_re := RegEx.create_from_string(" uid=\"[^\"]*\"")
    var path_re := RegEx.create_from_string("path=\"([^\"]*)\"")
    var cls_re := RegEx.create_from_string(" script_class=\"[^\"]*\"")
    for line in text.split("\n"):
        if line.begins_with("[ext_resource") or line.begins_with("[gd_scene") \
                or line.begins_with("[gd_resource"):
            line = uid_re.sub(line, "", true)
            if drop_script_class: line = cls_re.sub(line, "", true)
            var m := path_re.search(line)
            if m != null and path_map.has(m.get_string(1)):
                line = line.replace(m.get_string(0), "path=\"%s\"" % path_map[m.get_string(1)])
        out.append(line)
    return "\n".join(out)


## The ext_resource dependencies of a .tscn/.tres text: [{type, path}].
static func ext_resources(text: String) -> Array:
    var out: Array = []
    var type_re := RegEx.create_from_string("type=\"([^\"]*)\"")
    var path_re := RegEx.create_from_string("path=\"([^\"]*)\"")
    for line in text.split("\n"):
        if not line.begins_with("[ext_resource"): continue
        var tm := type_re.search(line)
        var pm := path_re.search(line)
        if pm == null: continue
        out.append({"type": tm.get_string(1) if tm != null else "", "path": pm.get_string(1)})
    return out


## The class_name a runtime source declares, or "".
static func class_name_of(src: String) -> String:
    var m := RegEx.create_from_string("(?m)^class_name\\s+(\\w+)").search(src)
    return m.get_string(1) if m != null else ""


## One runtime file as the standalone copy carries it.
##
## `names` maps every vendored class_name to its file name. The class_name line
## goes, each referenced class becomes `const ZRFoo = preload("zen_foo.gd")`
## right under `extends` (a file preloads itself too when it names its own
## type - measured to compile, cyclic preloads included), and the addon's own
## res:// paths move to `root`.
static func vendor_source(src: String, names: Dictionary, root: String) -> String:
    var s := RegEx.create_from_string("(?m)^class_name\\s+\\w+[ \\t]*\\n").sub(src, "", true)
    var keys: Array = names.keys()
    # Longest first, so ZenEasingSet is not eaten as ZenEasing + "Set".
    keys.sort_custom(func(a, b): return String(a).length() > String(b).length())
    var re := RegEx.create_from_string("\\b(" + "|".join(PackedStringArray(keys)) + ")\\b")
    var used := {}
    for m in re.search_all(s):
        used[m.get_string(1)] = true
    s = re.sub(s, PREFIX + "$1", true)
    # Undo the double prefix the substitution makes of a name that already
    # starts with Zen: ZenCanvas -> ZRZenCanvas -> ZRCanvas.
    s = s.replace(PREFIX + "Zen", PREFIX)
    s = s.replace(ADDON, root)

    var consts := ""
    var sorted_used: Array = used.keys()
    sorted_used.sort()
    for nm in sorted_used:
        consts += "const %s = preload(\"%s\")\n" % [PREFIX + String(nm).trim_prefix("Zen"), names[nm]]
    var ext := RegEx.create_from_string("(?m)^extends [^\\n]*\\n").search(s)
    if ext == null: return consts + s
    return s.insert(ext.get_end(), consts)


# ---------------------------------------------------------------------------
#  File plumbing.
# ---------------------------------------------------------------------------

static func _read(path: String) -> String:
    var f := FileAccess.open(path, FileAccess.READ)
    return f.get_as_text() if f != null else ""


static func _write(path: String, text: String, files: Array) -> String:
    var err := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
    if err != OK: return "cannot create %s" % path.get_base_dir()
    var f := FileAccess.open(path, FileAccess.WRITE)
    if f == null: return "cannot write %s" % path
    f.store_string(text)
    files.append(path)
    return ""


static func _copy(from: String, to: String, files: Array) -> String:
    var err := DirAccess.make_dir_recursive_absolute(to.get_base_dir())
    if err != OK: return "cannot create %s" % to.get_base_dir()
    if DirAccess.copy_absolute(from, to) != OK: return "cannot copy %s" % from
    files.append(to)
    return ""


## The files of `dir` (res://), without the editor's .import/.uid sidecars.
static func _list(dir: String, ext := "") -> Array:
    var out: Array = []
    for f in DirAccess.get_files_at(dir):
        if f.ends_with(".import") or f.ends_with(".uid"): continue
        if ext != "" and f.get_extension() != ext: continue
        out.append(f)
    out.sort()
    return out


static func vendored_files() -> Array:
    return _list(RUNTIME_DIR, "gd").filter(func(f): return not VENDOR_SKIP.has(f))


## The source commit, so a copy in a game can be traced back.
static func _source_version() -> String:
    var out: Array = []
    var dir := ProjectSettings.globalize_path("res://")
    if OS.execute("git", ["-C", dir, "rev-parse", "--short", "HEAD"], out) == OK and not out.is_empty():
        return String(out[0]).strip_edges()
    return "unknown"


## Write the standalone runtime copy. Stale .gd files of an older copy are
## removed; their .uid sidecars too, the current files' are kept so the target
## keeps its uids across re-exports.
static func vendor_runtime(s: Settings, files: Array) -> String:
    var root := runtime_root(s)
    var rt_abs := _abs(s, root + "runtime")
    var names := {}
    var sources := {}
    for f in vendored_files():
        var src := _read(RUNTIME_DIR.path_join(f))
        sources[f] = src
        var cn := class_name_of(src)
        if cn != "": names[cn] = f

    if DirAccess.dir_exists_absolute(rt_abs):
        for old in DirAccess.get_files_at(rt_abs):
            var base := old.trim_suffix(".uid")
            if base.get_extension() == "gd" and not sources.has(base):
                DirAccess.remove_absolute(rt_abs.path_join(old))

    for f in sources:
        var err := _write(rt_abs.path_join(f), vendor_source(sources[f], names, root), files)
        if err != "": return err
    var fonts_abs := _abs(s, root + "fonts")
    for f in _list(FONTS_DIR):
        var from := FONTS_DIR.path_join(f)
        var err := ""
        if f.get_extension() == "tres":
            err = _write(fonts_abs.path_join(f), rewrite_resource(_read(from), {}, true), files)
        else:
            err = _copy(ProjectSettings.globalize_path(from), fonts_abs.path_join(f), files)
        if err != "": return err
    return _write(_abs(s, root + "VERSION"),
        "Zen Animator runtime, standalone copy (no class_names).\nsource: %s\n" % _source_version(),
        files)


## Copy the plugin itself into the target's addons/zen, verbatim.
static func install_plugin(s: Settings, files: Array) -> String:
    var dest := s.target_dir.path_join("addons/zen")
    for f in _list(RUNTIME_DIR, "gd"):
        var err := _copy(ProjectSettings.globalize_path(RUNTIME_DIR.path_join(f)),
            dest.path_join("runtime").path_join(f), files)
        if err != "": return err
    for f in _list(FONTS_DIR):
        var err := _copy(ProjectSettings.globalize_path(FONTS_DIR.path_join(f)),
            dest.path_join("fonts").path_join(f), files)
        if err != "": return err
    for f in ["plugin.cfg", "plugin.gd"]:
        var err := _copy(ProjectSettings.globalize_path(ADDON + f), dest.path_join(f), files)
        if err != "": return err
    return ""


## The runtime half of an export: the standalone copy, or the plugin install
## when asked for.
static func ship(s: Settings, files: Array) -> String:
    if s.mode == Mode.STANDALONE: return vendor_runtime(s, files)
    if s.install_plugin: return install_plugin(s, files)
    return ""


# ---------------------------------------------------------------------------
#  The scene.
# ---------------------------------------------------------------------------

## The animation's scene as it should ship: live playback on, filling the
## window when run on its own, a click continuing a pause, the background
## painted, and the Options font override pinned on each text that would
## have picked it up (the target has no Options screen).
static func scene_text(anim: String) -> Dictionary:
    var path := ANIMS_DIR.path_join(anim + ".tscn")
    var ps := load(path) as PackedScene
    if ps == null: return {"error": "no such animation: %s" % anim}
    var canvas := ps.instantiate() as ZenCanvas
    if canvas == null: return {"error": "%s is not a Zen animation" % anim}
    canvas.live_playback = true
    canvas.fit_window = true
    canvas.click_to_continue = true
    canvas.draw_background = true
    var override := ZenText.font_override()
    if override != null:
        for e in canvas.elements():
            if e is ZenText and (e as ZenText).font == null:
                (e as ZenText).font = override
    var out := PackedScene.new()
    var err := out.pack(canvas)
    canvas.free()
    if err != OK: return {"error": "cannot pack %s" % anim}
    var tmp := "user://zen_godot_export.tscn"
    if ResourceSaver.save(out, tmp) != OK: return {"error": "cannot save %s" % tmp}
    var text := _read(tmp)
    DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
    return {"text": text}


static func _is_pixel_shape(path: String) -> bool:
    return path.get_extension() == "tres" and _read(path).contains("ZenPixelShape")


## Export one animation. {ok, error, files, scene} - `scene` is the target
## res:// path of the written .tscn, `files` every absolute path written.
## `ship_runtime` false skips the runtime copy / plugin install (a chain does
## it once).
static func export_anim(anim: String, s: Settings, files: Array = [], ship_runtime := true) -> Dictionary:
    var bad := validate(s)
    if bad != "": return {"ok": false, "error": bad, "files": files}
    var sub := clean_subdir(s.subdir)
    var standalone := s.mode == Mode.STANDALONE
    var st := scene_text(anim)
    if st.has("error"): return {"ok": false, "error": st["error"], "files": files}
    var text: String = st["text"]

    # Map every dependency; anything unrecognised fails the export rather than
    # shipping a scene that cannot load.
    var root := runtime_root(s)
    var map := {}
    var copies: Array = []   # [from res path, to res path, is_text]
    for dep in ext_resources(text):
        var p := String(dep["path"])
        if p.begins_with(ADDON):
            map[p] = root + p.trim_prefix(ADDON)
        elif _is_pixel_shape(p):
            map[p] = "res://%s/shapes/%s" % [sub, p.get_file()]
            copies.append([p, map[p], true])
        elif FONT_EXTS.has(p.get_extension()) or (p.get_extension() == "tres" and dep["type"].contains("Font")):
            map[p] = "res://%s/fonts/%s" % [sub, p.get_file()]
            copies.append([p, map[p], p.get_extension() == "tres"])
        else:
            return {"ok": false, "error": "%s uses %s, which cannot be exported" % [anim, p], "files": files}

    if ship_runtime:
        var err := ship(s, files)
        if err != "": return {"ok": false, "error": err, "files": files}

    # A copied shape names its script under the addon too.
    var addon_map := {}
    for c in copies:
        if not c[2]: continue
        for dep in ext_resources(_read(c[0])):
            var p := String(dep["path"])
            if p.begins_with(ADDON): addon_map[p] = root + p.trim_prefix(ADDON)
    for c in copies:
        var err := ""
        if c[2]:
            err = _write(_abs(s, c[1]), rewrite_resource(_read(c[0]), addon_map, standalone), files)
        else:
            err = _copy(ProjectSettings.globalize_path(c[0]), _abs(s, c[1]), files)
        if err != "": return {"ok": false, "error": err, "files": files}

    var scene := "res://%s/%s.tscn" % [sub, ZenExport.sanitize(anim)]
    var err := _write(_abs(s, scene), rewrite_resource(text, map, standalone), files)
    if err != "": return {"ok": false, "error": err, "files": files}
    return {"ok": true, "error": "", "files": files, "scene": scene}


## Export several animations into one target (the dialog's chain). Stops at
## the first failure.
static func export_chain(anims: Array, s: Settings) -> Dictionary:
    var files: Array = []
    var scenes: Array = []
    for i in anims.size():
        var r := export_anim(String(anims[i]), s, files, i == 0)
        if not bool(r["ok"]): return {"ok": false, "error": r["error"], "files": files, "scenes": scenes}
        scenes.append(r["scene"])
    return {"ok": true, "error": "", "files": files, "scenes": scenes}
