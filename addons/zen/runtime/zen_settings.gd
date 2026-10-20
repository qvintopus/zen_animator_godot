@tool
class_name ZenSettings
extends RefCounted
##
## Persisted user preferences. Stored at user://zen_settings.cfg - a handful
## of values read once at process start and written only when a screen
## changes them, so no autoload is needed; the gallery and the exporter each
## call apply_startup() for themselves.
##
## Two groups, matching who owns what (see docs/plans/export-dialog.md):
##   - FONT + new-scene canvas size: creation-time defaults, edited on the
##     Options screen, read by every entry point.
##   - EXPORT SCALE + TARGET: the Export dialog's last pick. The target (a
##     short side in px, e.g. 1080) wins whenever the canvas reaches it at a
##     whole-number scale, so "1080p" survives moving between canvas sizes.
##   - PLAYBACK: the gallery's intro (I) and loop (L) toggles.
##   - EXPORT DEFAULTS: everything else export-related, edited on the Export
##     dialog and remembered as one Dictionary so a new field never needs a
##     new accessor pair.
##   - SCENE EDITOR: which panels are open and pinned, and auto-key - one
##     Dictionary, for the same reason.
##

const CFG_PATH := "user://zen_settings.cfg"
const SECTION := "zen"
## Mirrors ZenExport.MAX_SCALE (tools/ - the runtime cannot name it).
const MAX_SCALE := 12

const EXPORT_DEFAULTS := {
    "fmt": "gif", "fps": 30, "show_intro": false, "transparent": false,
    "quality_gif": 16, "quality_video": 70, "cutout": 128,
    "pause_hold": 0.0, "join_pause": true,
}

static var _loaded := false
static var _font_name := ""      # "" => bundled default; else a system font family
static var _export_scale := 4
static var _export_target := 0   # short side in px; 0 => no named target, use the scale
static var _canvas_size := Vector2(320, 180)
static var _export: Dictionary = EXPORT_DEFAULTS.duplicate()
static var _play_intro := true
static var _play_loop := true
static var _editor: Dictionary = {}


static func _ensure_loaded() -> void:
    if _loaded: return
    _loaded = true
    var cfg := ConfigFile.new()
    if cfg.load(CFG_PATH) == OK:
        _font_name = String(cfg.get_value(SECTION, "font_name", ""))
        _export_scale = int(cfg.get_value(SECTION, "export_scale", 4))
        _export_target = int(cfg.get_value(SECTION, "export_target", 0))
        _canvas_size = cfg.get_value(SECTION, "canvas_size", Vector2(320, 180))
        _play_intro = bool(cfg.get_value(SECTION, "play_intro", true))
        _play_loop = bool(cfg.get_value(SECTION, "play_loop", true))
        # merge(), not assign: an older .cfg (or a field added after this one
        # was saved) must not drop keys this version expects to find.
        var saved: Dictionary = cfg.get_value(SECTION, "export", {})
        _export = EXPORT_DEFAULTS.duplicate()
        _export.merge(saved, true)
        _editor = cfg.get_value(SECTION, "editor", {})


static func font_name() -> String:
    _ensure_loaded()
    return _font_name


static func export_scale() -> int:
    _ensure_loaded()
    return clampi(_export_scale, 1, MAX_SCALE)


static func export_target() -> int:
    _ensure_loaded()
    return _export_target


## The canvas a NEW scene starts with. Always one of ZenCanvas.SIZE_PRESETS:
## a stale or hand-edited value falls back to the default.
static func canvas_size() -> Vector2:
    _ensure_loaded()
    return _canvas_size if ZenCanvas.preset_index(_canvas_size) >= 0 else ZenCanvas.DEFAULT_SIZE


## A copy, never the live Dictionary - callers may freely mutate it before
## calling set_export_defaults() without this class seeing half an edit.
static func export_defaults() -> Dictionary:
    _ensure_loaded()
    return _export.duplicate()


static func play_intro() -> bool:
    _ensure_loaded()
    return _play_intro


static func play_loop() -> bool:
    _ensure_loaded()
    return _play_loop


static func set_play_intro(on: bool) -> void:
    _ensure_loaded()
    _play_intro = on
    _save()


static func set_play_loop(on: bool) -> void:
    _ensure_loaded()
    _play_loop = on
    _save()


static func set_font_name(name: String) -> void:
    _ensure_loaded()
    _font_name = name
    _save()
    ZenText.set_font_override(build_font(name))


static func set_export_scale(scale: int) -> void:
    _ensure_loaded()
    _export_scale = clampi(scale, 1, MAX_SCALE)
    _save()


## Remember the Export dialog's pick: the scale, plus the named target it
## stood for (0 when it was a plain multiple).
static func set_export_target(target: int) -> void:
    _ensure_loaded()
    _export_target = maxi(target, 0)
    _save()


static func set_canvas_size(size: Vector2) -> void:
    _ensure_loaded()
    _canvas_size = size
    _save()


static func set_export_defaults(d: Dictionary) -> void:
    _ensure_loaded()
    _export = EXPORT_DEFAULTS.duplicate()
    _export.merge(d, true)
    _save()


## The scene editor's remembered layout ({panel_id: {open, pinned}}, autokey).
## A copy, like export_defaults().
static func editor_state() -> Dictionary:
    _ensure_loaded()
    return _editor.duplicate(true)


static func set_editor_state(d: Dictionary) -> void:
    _ensure_loaded()
    _editor = d.duplicate(true)
    _save()


static func _save() -> void:
    var cfg := ConfigFile.new()
    cfg.set_value(SECTION, "font_name", _font_name)
    cfg.set_value(SECTION, "export_scale", _export_scale)
    cfg.set_value(SECTION, "export_target", _export_target)
    cfg.set_value(SECTION, "canvas_size", _canvas_size)
    cfg.set_value(SECTION, "export", _export)
    cfg.set_value(SECTION, "play_intro", _play_intro)
    cfg.set_value(SECTION, "play_loop", _play_loop)
    cfg.set_value(SECTION, "editor", _editor)
    cfg.save(CFG_PATH)


## Bundled fonts other than the default, by the name the Options list shows
## and the settings file stores. Names a system family is unlikely to have.
const BUNDLED_FONTS := {
    "Source Sans 3 (bundled)": "res://addons/zen/fonts/SourceSans3-Regular.ttf",
}


## "" resolves to the bundled default (ZenText.default_font() already handles
## that); a BUNDLED_FONTS name loads that file; anything else is a SYSTEM font
## looked up by family name through Godot's SystemFont - no bundling needed to
## offer real font choice.
static func build_font(name: String) -> Font:
    if name == "": return null
    if BUNDLED_FONTS.has(name): return load(BUNDLED_FONTS[name])
    var f := SystemFont.new()
    f.font_names = [name]
    return f


## Called once at process start by whichever scene is the entry point (gallery
## or the exporter) so a saved choice takes effect with no Options visit
## required this run.
static func apply_startup() -> void:
    _ensure_loaded()
    if _font_name != "":
        ZenText.set_font_override(build_font(_font_name))
