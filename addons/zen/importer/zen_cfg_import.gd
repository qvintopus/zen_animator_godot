@tool
extends SceneTree
##
## One-shot .cfg -> .tscn importer.
##
##   Godot --headless --path . --script res://addons/zen/importer/zen_cfg_import.gd
##
## Reads every anims_src/*.cfg and writes anims/<snake_name>.tscn. Headless is
## fine: this authors resources and renders nothing.
##
## Native Godot scenes are the source of truth from here on - this tool exists
## to carry the existing documents across ONCE, not to be a round-trip format.
## It is kept (rather than deleted after the run) only so the import can be
## re-run when the node layer gains a feature, e.g. when text lands in Phase 3.
##

const SRC_DIR := "res://anims_src"
const OUT_DIR := "res://anims"


func _init() -> void:
    var easings := _load_easings()
    print("custom easings: %d" % easings.size())

    var names := _list_cfgs()
    if names.is_empty():
        print("no .cfg files in %s" % SRC_DIR)
        quit(1)
        return

    var failed := 0
    for file_name in names:
        if not _import_one(file_name): failed += 1
    print("\n%d/%d imported" % [names.size() - failed, names.size()])
    quit(1 if failed > 0 else 0)


## Register the shared custom easings so ZenEasing.apply resolves them by name.
func _load_easings() -> Dictionary:
    var path := "%s/_easings.cfg" % SRC_DIR
    if not FileAccess.file_exists(path): return {}
    var parsed := ZenCfgParse.parse_easings(FileAccess.get_file_as_string(path))
    for n in parsed["curves"]:
        ZenEasing.register_custom(n, parsed["curves"][n])
    return parsed["curves"]


## Documents only: a leading underscore marks the shared library/easing files.
func _list_cfgs() -> Array:
    var out: Array = []
    var d := DirAccess.open(SRC_DIR)
    if d == null: return out
    for f in d.get_files():
        if f.ends_with(".cfg") and not f.begins_with("_"):
            out.append(f)
    out.sort()
    return out


## MAIN_MENU.cfg -> main_menu, "new anim test.cfg" -> new_anim_test
static func scene_name(cfg_file: String) -> String:
    var base := cfg_file.get_basename().to_lower()
    var out := ""
    for ch in base:
        out += ch if (ch.is_valid_identifier() or ch.is_valid_int()) else "_"
    while out.contains("__"):
        out = out.replace("__", "_")
    return out.strip_edges(true, true)


func _import_one(cfg_file: String) -> bool:
    var text := FileAccess.get_file_as_string("%s/%s" % [SRC_DIR, cfg_file])
    var res := ZenCfgParse.parse_doc(text)
    if not res["ok"]:
        print("  %s FAILED: %s" % [cfg_file, res["error"]])
        return false

    var doc: Dictionary = res["doc"]
    var built := ZenCfgBuild.build(doc)
    var canvas: ZenCanvas = built["canvas"]
    var skipped: Array = built["skipped"]

    var out_name := scene_name(cfg_file)
    var packed := PackedScene.new()
    if packed.pack(canvas) != OK:
        print("  %s FAILED: pack" % cfg_file)
        return false
    var out_path := "%s/%s.tscn" % [OUT_DIR, out_name]
    var err := ResourceSaver.save(packed, out_path)
    if err != OK:
        print("  %s FAILED: save %s" % [cfg_file, error_string(err)])
        return false

    var note := ""
    if not skipped.is_empty():
        note = "  [deferred: %s]" % ", ".join(skipped)
    print("  %-22s -> %-28s %d elem, %d signal, %.2fs%s" % [
        cfg_file, out_name + ".tscn", doc["elems"].size(),
        doc["signals"].size(), doc["duration"], note])
    return true
