@tool
class_name ZenOptions
extends Control
##
## Options screen, reachable from the gallery with O (zen_options). Creation-
## time defaults only - everything export-related (including scale) lives on
## the Export dialog instead (E / Ctrl+E), since a document's real export
## resolution depends on its own design_size, not a setting here.
##
##   - FONT: applied process-wide via ZenText's static override, so every
##     element with no per-element `font` picks it up with no .tscn edit.
##     "Default" is the bundled Source Sans 3; everything else is a real
##     installed font looked up by family name through Godot's SystemFont -
##     no bundling needed to offer actual choice.
##

signal closed

const DEFAULT_LABEL := "Default (Source Sans 3)"

@onready var _font_list: VBoxContainer = $Margin/Rows/Body/FontCol/FontScroll/FontList
@onready var _font_scroll: ScrollContainer = $Margin/Rows/Body/FontCol/FontScroll
@onready var _search: LineEdit = $Margin/Rows/Body/FontCol/FontHead/Search
@onready var _preview: Label = $Margin/Rows/Body/PreviewCol/Preview
@onready var _hint: Label = $Margin/Rows/Foot/Hint

## "" is the bundled default; the rest are whatever OS.get_system_fonts()
## reports on this machine, so the list is never stale against what the font
## picker can actually resolve. Sorted A-Z, default pinned first.
var _fonts: Array = []
## Indices into _fonts that match the search, in display order.
var _shown: Array[int] = []
var _sel := 0          ## index into _fonts: the applied font


func _ready() -> void:
    _fonts = sorted_fonts(OS.get_system_fonts())
    _sel = maxi(_fonts.find(ZenSettings.font_name()), 0)
    _search.text_changed.connect(func(_t): _rebuild())
    _search.text_submitted.connect(_on_search_submitted)
    _rebuild()
    _preview.add_theme_font_override("font", ZenText.default_font())
    _hint.text = "  UP/DOWN  font      type  search      ESC  clear search / back"
    # Typing filters straight away; the arrows still move the selection.
    _search.grab_focus()


## Default first, then the system families A-Z, case-insensitively and with
## duplicates dropped (some platforms report a family once per style).
static func sorted_fonts(system: Array) -> Array:
    var uniq := {}
    for f in system:
        if String(f) != "": uniq[String(f)] = true
    var names := uniq.keys()
    names.sort_custom(func(a, b): return String(a).naturalnocasecmp_to(String(b)) < 0)
    var out: Array = [""]
    out.append_array(names)
    return out


## Indices of `fonts` whose label contains `query`, case-insensitively. The
## default row matches on its label, so "source" or "default" still finds it.
static func filter_fonts(fonts: Array, query: String) -> Array[int]:
    var q := query.strip_edges().to_lower()
    var out: Array[int] = []
    for i in fonts.size():
        var label := DEFAULT_LABEL if String(fonts[i]) == "" else String(fonts[i])
        if q.is_empty() or label.to_lower().contains(q): out.append(i)
    return out


func _rebuild() -> void:
    _shown = filter_fonts(_fonts, _search.text)
    var labels := _shown.map(func(i): return DEFAULT_LABEL if _fonts[i] == "" else _fonts[i])
    # Rows are indexed by position in the FILTERED list; map back to _fonts.
    ZenUI.fill_list(_font_list, labels, func(row): _select(_shown[row]))
    _mark_sel()


## Selecting a row applies the font immediately - a static override on
## ZenText, so the preview label (and every animation played after this)
## picks it up with no further wiring.
func _select(i: int) -> void:
    if _fonts.is_empty(): return
    _sel = clampi(i, 0, _fonts.size() - 1)
    ZenSettings.set_font_name(_fonts[_sel])
    _preview.add_theme_font_override("font", ZenText.default_font())
    _mark_sel()


## Highlight and scroll to the applied font's row, if the search shows it.
func _mark_sel() -> void:
    var row := _shown.find(_sel)
    ZenUI.mark_selected(_font_list, row)
    ZenUI.scroll_to(_font_scroll, _font_list, row)


## UP/DOWN step through the FILTERED rows. When the applied font is filtered
## out, the first step lands on the first (or last) match.
func _step(d: int) -> void:
    if _shown.is_empty(): return
    var row := _shown.find(_sel)
    if row < 0: row = 0 if d > 0 else _shown.size() - 1
    else: row = clampi(row + d, 0, _shown.size() - 1)
    _select(_shown[row])


func _on_search_submitted(_t: String) -> void:
    if not _shown.is_empty() and not _shown.has(_sel): _select(_shown[0])


## _input, not _unhandled_input: the search field has focus and would
## otherwise swallow the arrows and ESC before they get here.
func _input(ev: InputEvent) -> void:
    if not (ev is InputEventKey) or not ev.is_pressed(): return
    if ev.is_action_pressed("zen_back") and not ev.is_echo():
        if _search.text != "":
            _search.clear()
            _rebuild()
        else:
            closed.emit()
        get_viewport().set_input_as_handled()
    elif ev.is_action_pressed("zen_prev", true):
        _step(-1)
        get_viewport().set_input_as_handled()
    elif ev.is_action_pressed("zen_next", true):
        _step(1)
        get_viewport().set_input_as_handled()
