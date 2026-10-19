@tool
class_name ZenSettings
extends RefCounted
##
## Persisted user preferences: which font text renders with, and the default
## export scale. Stored at user://zen_settings.cfg - a handful of values read
## once at process start and written only when the Options screen changes
## them, so no autoload is needed; the gallery and the exporter each call
## apply_startup() for themselves.
##

const CFG_PATH := "user://zen_settings.cfg"
const SECTION := "zen"

static var _loaded := false
static var _font_name := ""      # "" => bundled default; else a system font family
static var _export_scale := 4


static func _ensure_loaded() -> void:
    if _loaded: return
    _loaded = true
    var cfg := ConfigFile.new()
    if cfg.load(CFG_PATH) == OK:
        _font_name = String(cfg.get_value(SECTION, "font_name", ""))
        _export_scale = int(cfg.get_value(SECTION, "export_scale", 4))


static func font_name() -> String:
    _ensure_loaded()
    return _font_name


static func export_scale() -> int:
    _ensure_loaded()
    return clampi(_export_scale, 1, 8)


static func set_font_name(name: String) -> void:
    _ensure_loaded()
    _font_name = name
    _save()
    ZenText.set_font_override(build_font(name))


static func set_export_scale(scale: int) -> void:
    _ensure_loaded()
    _export_scale = clampi(scale, 1, 8)
    _save()


static func _save() -> void:
    var cfg := ConfigFile.new()
    cfg.set_value(SECTION, "font_name", _font_name)
    cfg.set_value(SECTION, "export_scale", _export_scale)
    cfg.save(CFG_PATH)


## "" resolves to the bundled default (ZenText.default_font() already handles
## that); anything else is a SYSTEM font looked up by family name through
## Godot's SystemFont - no bundling needed to offer real font choice.
static func build_font(name: String) -> Font:
    if name == "": return null
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
