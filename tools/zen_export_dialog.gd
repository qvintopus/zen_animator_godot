@tool
class_name ZenExportDialog
extends Control
##
## In-app Export screen (E / Ctrl+E from the gallery). Every option the
## original Zen editor's File > Export modal had, built with native Godot
## controls (OptionButton/HSlider/SpinBox/CheckBox/LineEdit) rather than the
## custom UP/DOWN nav the rest of this UI uses - ~15 heterogeneous rows read
## far better with real Tab/mouse focus than with one axis.
##
## Frame counts and the size estimate come from the gallery's own scanned
## metadata (_entries - intro_end/play_start/play_end/pauses/design), NOT by
## instantiating scenes while the chain is being edited. Real
## ZenCanvas/SubViewport instances (ZenExport.build_link) are only built once,
## at the moment Export is pressed: plan_chain() needs live canvases, but
## editing the chain does not.
##
## The whole UI is built in _ready() rather than hand-authored in the .tscn -
## ~15 heterogeneous rows with live enable/disable rules are far less brittle
## as code than as a node path tree every @onready has to match exactly.
##

signal closed

var _by_name: Dictionary = {}       # name -> entry, from the gallery's _entries
var _chain: Array[String] = []
var _s := ZenExport.Settings.new()

var _job: ZenExport.Job = null
var _links: Array = []              # [{canvas, sub}], built only at export time
var _running := false
var _exported_ok := false

# Controls filled in during _build_ui(), read back in _refresh()/_on_export.
var _chain_box: VBoxContainer
var _add_btn: Button
var _format: OptionButton
var _ffmpeg_hint: Label
var _name_edit: LineEdit
var _path_preview: Label
var _folder_btn: Button
var _scale_buttons: Array[Button] = []
var _res_label: Label
var _fps_spin: SpinBox
var _fps_note: Label
var _intro_check: CheckBox
var _hold_slider: HSlider
var _hold_value: Label
var _join_row: HBoxContainer
var _join_check: CheckBox
var _frames_label: Label
var _gif_row: HBoxContainer
var _gif_quality: HSlider
var _gif_quality_value: Label
var _transparent_check: CheckBox
var _cutout_row: HBoxContainer
var _cutout_slider: HSlider
var _cutout_value: Label
var _video_row: HBoxContainer
var _video_quality: HSlider
var _video_quality_value: Label
var _avi_label: Label
var _size_label: Label
var _progress: ProgressBar
var _progress_label: Label
var _status_label: Label
var _export_btn: Button
var _close_btn: Button

var _add_popup: PopupPanel
var _add_search: LineEdit
var _add_list: ItemList

const FORMATS := ["gif", "mp4", "webm", "avi", "png"]
const FORMAT_LABELS := {
    "gif": "GIF", "mp4": "MP4 (H.264)", "webm": "WebM (VP9)",
    "avi": "AVI (uncompressed)", "png": "PNG frames",
}


func _ready() -> void:
    _build_ui()


## `entries`: the gallery's own _entries (not rescanned). `chain`: ordered
## animation names to seed the chain list with.
func open(entries: Array, chain: Array) -> void:
    _by_name.clear()
    for e in entries:
        _by_name[String(e.get("name", ""))] = e
    _chain.clear()
    for nm in chain:
        if _by_name.has(String(nm)): _chain.append(String(nm))

    var d := ZenSettings.export_defaults()
    _s.fmt = String(d.get("fmt", "gif"))
    _s.fps = int(d.get("fps", 30))
    _s.show_intro = bool(d.get("show_intro", false))
    _s.transparent = bool(d.get("transparent", false))
    _s.quality_gif = int(d.get("quality_gif", 16))
    _s.quality = int(d.get("quality_video", 70))
    _s.cutout = int(d.get("cutout", 128))
    _s.pause_hold = float(d.get("pause_hold", 0.0))
    _s.join_pause = bool(d.get("join_pause", true))
    _s.scale = ZenSettings.export_scale()

    _name_edit.text = _default_name()
    _sync_controls_from_settings()
    _refresh()


func get_chain() -> Array[String]:
    return _chain.duplicate()


func exported_ok() -> bool:
    return _exported_ok


# ---------------------------------------------------------------- UI build

func _build_ui() -> void:
    anchor_right = 1.0
    anchor_bottom = 1.0
    grow_horizontal = Control.GROW_DIRECTION_BOTH
    grow_vertical = Control.GROW_DIRECTION_BOTH

    var bg := Panel.new()
    bg.anchor_right = 1.0
    bg.anchor_bottom = 1.0
    var sb := StyleBoxFlat.new()
    sb.bg_color = Color(0.0862745, 0.0941176, 0.1137255, 1)
    bg.add_theme_stylebox_override("panel", sb)
    add_child(bg)

    var margin := MarginContainer.new()
    margin.anchor_right = 1.0
    margin.anchor_bottom = 1.0
    margin.add_theme_constant_override("margin_left", 18)
    margin.add_theme_constant_override("margin_top", 14)
    margin.add_theme_constant_override("margin_right", 18)
    margin.add_theme_constant_override("margin_bottom", 12)
    add_child(margin)

    var rows := VBoxContainer.new()
    rows.add_theme_constant_override("separation", 8)
    margin.add_child(rows)

    var title := Label.new()
    title.text = "Export"
    title.add_theme_color_override("font_color", Color(0.898, 0.753, 0.482, 1))
    title.add_theme_font_size_override("font_size", 22)
    rows.add_child(title)
    rows.add_child(HSeparator.new())

    var scroll := ScrollContainer.new()
    scroll.size_flags_vertical = SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = 0
    rows.add_child(scroll)

    var body := VBoxContainer.new()
    body.size_flags_horizontal = SIZE_EXPAND_FILL
    body.add_theme_constant_override("separation", 10)
    scroll.add_child(body)

    _build_chain_section(body)
    body.add_child(HSeparator.new())
    _build_options_section(body)

    rows.add_child(HSeparator.new())

    var prog_row := HBoxContainer.new()
    prog_row.add_theme_constant_override("separation", 8)
    _progress = ProgressBar.new()
    _progress.size_flags_horizontal = SIZE_EXPAND_FILL
    _progress.min_value = 0
    _progress.max_value = 1
    _progress.visible = false
    _progress_label = Label.new()
    _progress_label.visible = false
    prog_row.add_child(_progress)
    prog_row.add_child(_progress_label)
    rows.add_child(prog_row)

    _status_label = Label.new()
    _status_label.text = ""
    _status_label.add_theme_color_override("font_color", Color(0.816, 0.835, 0.867, 1))
    rows.add_child(_status_label)

    var foot := HBoxContainer.new()
    foot.add_theme_constant_override("separation", 10)
    _folder_btn = Button.new()
    _folder_btn.text = "Folder"
    _folder_btn.pressed.connect(_on_folder_pressed)
    foot.add_child(_folder_btn)
    var spacer := Control.new()
    spacer.size_flags_horizontal = SIZE_EXPAND_FILL
    foot.add_child(spacer)
    _export_btn = Button.new()
    _export_btn.text = "Export"
    _export_btn.pressed.connect(_on_export_pressed)
    foot.add_child(_export_btn)
    _close_btn = Button.new()
    _close_btn.text = "Close"
    _close_btn.pressed.connect(_on_close_pressed)
    foot.add_child(_close_btn)
    rows.add_child(foot)

    _build_add_popup()


func _build_chain_section(parent: VBoxContainer) -> void:
    var col := VBoxContainer.new()
    col.add_theme_constant_override("separation", 4)
    var lbl := Label.new()
    lbl.text = "chain"
    lbl.add_theme_color_override("font_color", Color(0.38, 0.686, 0.937, 1))
    col.add_child(lbl)

    _chain_box = VBoxContainer.new()
    _chain_box.add_theme_constant_override("separation", 2)
    col.add_child(_chain_box)

    var add_row := HBoxContainer.new()
    _add_btn = Button.new()
    _add_btn.text = "+ Add animation"
    _add_btn.pressed.connect(_on_add_pressed)
    add_row.add_child(_add_btn)
    col.add_child(add_row)

    parent.add_child(col)


func _build_options_section(parent: VBoxContainer) -> void:
    # Format
    var frow := _labeled_row(parent, "format")
    _format = OptionButton.new()
    for fmt in FORMATS:
        _format.add_item(String(FORMAT_LABELS[fmt]))
    _format.item_selected.connect(_on_format_selected)
    frow.add_child(_format)
    _ffmpeg_hint = Label.new()
    _ffmpeg_hint.text = "ffmpeg not found - use GIF or PNG frames"
    _ffmpeg_hint.add_theme_color_override("font_color", Color(0.8, 0.5, 0.4, 1))
    _ffmpeg_hint.visible = false
    parent.add_child(_ffmpeg_hint)

    # Name + folder
    var nrow := _labeled_row(parent, "name")
    _name_edit = LineEdit.new()
    _name_edit.size_flags_horizontal = SIZE_EXPAND_FILL
    _name_edit.focus_exited.connect(_on_name_focus_exited)
    _name_edit.text_submitted.connect(func(_t): _on_name_focus_exited())
    nrow.add_child(_name_edit)
    _path_preview = Label.new()
    _path_preview.add_theme_color_override("font_color", Color(0.5, 0.55, 0.6, 1))
    parent.add_child(_path_preview)

    # Scale
    var srow := _labeled_row(parent, "scale")
    var grp := ButtonGroup.new()
    for i in range(1, ZenExport.MAX_SCALE + 1):
        var b := Button.new()
        b.text = "x%d" % i
        b.toggle_mode = true
        b.button_group = grp
        b.pressed.connect(_on_scale_pressed.bind(i))
        srow.add_child(b)
        _scale_buttons.append(b)
    _res_label = Label.new()
    _res_label.add_theme_color_override("font_color", Color(0.816, 0.835, 0.867, 1))
    parent.add_child(_res_label)

    # FPS
    var fpsrow := _labeled_row(parent, "fps")
    _fps_spin = SpinBox.new()
    _fps_spin.min_value = 1
    _fps_spin.max_value = ZenExport.MAX_FPS_VIDEO
    _fps_spin.value_changed.connect(_on_fps_changed)
    fpsrow.add_child(_fps_spin)
    _fps_note = Label.new()
    _fps_note.add_theme_color_override("font_color", Color(0.5, 0.55, 0.6, 1))
    fpsrow.add_child(_fps_note)

    # Show intro
    var introrow := HBoxContainer.new()
    _intro_check = CheckBox.new()
    _intro_check.text = "show intro"
    _intro_check.toggled.connect(_on_intro_toggled)
    introrow.add_child(_intro_check)
    parent.add_child(introrow)

    # Pause hold
    var holdrow := _labeled_row(parent, "pause hold")
    _hold_slider = HSlider.new()
    _hold_slider.min_value = 0.0
    _hold_slider.max_value = 12.0
    _hold_slider.step = 0.1
    _hold_slider.size_flags_horizontal = SIZE_EXPAND_FILL
    _hold_slider.value_changed.connect(_on_hold_changed)
    holdrow.add_child(_hold_slider)
    _hold_value = Label.new()
    holdrow.add_child(_hold_value)

    # Join pause
    _join_row = HBoxContainer.new()
    _join_check = CheckBox.new()
    _join_check.text = "pause between animations"
    _join_check.toggled.connect(_on_join_toggled)
    _join_row.add_child(_join_check)
    parent.add_child(_join_row)

    _frames_label = Label.new()
    _frames_label.add_theme_color_override("font_color", Color(0.816, 0.835, 0.867, 1))
    parent.add_child(_frames_label)

    # Per-format rows
    _gif_row = HBoxContainer.new()
    var gql := Label.new(); gql.text = "gif quality  "; _gif_row.add_child(gql)
    _gif_quality = HSlider.new()
    _gif_quality.min_value = 1; _gif_quality.max_value = 16; _gif_quality.step = 1
    _gif_quality.custom_minimum_size = Vector2(160, 0)
    _gif_quality.value_changed.connect(_on_gif_quality_changed)
    _gif_row.add_child(_gif_quality)
    _gif_quality_value = Label.new(); _gif_row.add_child(_gif_quality_value)
    parent.add_child(_gif_row)

    _transparent_check = CheckBox.new()
    _transparent_check.text = "transparent"
    _transparent_check.toggled.connect(_on_transparent_toggled)
    parent.add_child(_transparent_check)

    _cutout_row = HBoxContainer.new()
    var cl := Label.new(); cl.text = "cutout threshold  "; _cutout_row.add_child(cl)
    _cutout_slider = HSlider.new()
    _cutout_slider.min_value = 1; _cutout_slider.max_value = 255; _cutout_slider.step = 1
    _cutout_slider.custom_minimum_size = Vector2(160, 0)
    _cutout_slider.value_changed.connect(_on_cutout_changed)
    _cutout_row.add_child(_cutout_slider)
    _cutout_value = Label.new(); _cutout_row.add_child(_cutout_value)
    parent.add_child(_cutout_row)

    _video_row = HBoxContainer.new()
    var vql := Label.new(); vql.text = "quality  "; _video_row.add_child(vql)
    _video_quality = HSlider.new()
    _video_quality.min_value = 0; _video_quality.max_value = 100; _video_quality.step = 1
    _video_quality.custom_minimum_size = Vector2(160, 0)
    _video_quality.value_changed.connect(_on_video_quality_changed)
    _video_row.add_child(_video_quality)
    _video_quality_value = Label.new(); _video_row.add_child(_video_quality_value)
    parent.add_child(_video_row)

    _avi_label = Label.new()
    _avi_label.text = "lossless, no quality control"
    _avi_label.add_theme_color_override("font_color", Color(0.5, 0.55, 0.6, 1))
    parent.add_child(_avi_label)

    _size_label = Label.new()
    _size_label.add_theme_color_override("font_color", Color(0.816, 0.835, 0.867, 1))
    _size_label.tooltip_text = "Video size is a rough guess: compression depends on how much the animation actually moves."
    parent.add_child(_size_label)


func _labeled_row(parent: VBoxContainer, text: String) -> HBoxContainer:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 8)
    var l := Label.new()
    l.text = text
    l.custom_minimum_size = Vector2(90, 0)
    l.add_theme_color_override("font_color", Color(0.38, 0.686, 0.937, 1))
    row.add_child(l)
    parent.add_child(row)
    return row


func _build_add_popup() -> void:
    _add_popup = PopupPanel.new()
    var col := VBoxContainer.new()
    _add_search = LineEdit.new()
    _add_search.placeholder_text = "search"
    _add_search.text_changed.connect(func(_t): _rebuild_add_list())
    col.add_child(_add_search)
    _add_list = ItemList.new()
    _add_list.custom_minimum_size = Vector2(260, 240)
    _add_list.item_activated.connect(_on_add_item_activated)
    col.add_child(_add_list)
    _add_popup.add_child(col)
    add_child(_add_popup)


# ---------------------------------------------------------------- derived state

func _default_name() -> String:
    if _chain.is_empty(): return "export"
    if _chain.size() == 1: return ZenExport.sanitize(_chain[0])
    return ZenExport.sanitize("%s_chain" % _chain[0])


func _sync_controls_from_settings() -> void:
    var idx := FORMATS.find(_s.fmt)
    _format.select(maxi(idx, 0))
    for i in _scale_buttons.size():
        _scale_buttons[i].button_pressed = (i + 1) == _s.scale
    _fps_spin.value = _s.fps
    _intro_check.button_pressed = _s.show_intro
    _hold_slider.value = _s.pause_hold
    _join_check.button_pressed = _s.join_pause
    _gif_quality.value = _s.quality_gif
    _transparent_check.button_pressed = _s.transparent
    _cutout_slider.value = _s.cutout
    _video_quality.value = _s.quality


## First chain link's own entry - every size/frame-count number is anchored
## to its real design_size, never a hardcoded canvas.
func _first_entry() -> Dictionary:
    if _chain.is_empty(): return {}
    return _by_name.get(_chain[0], {})


## Frame/held totals from metadata alone (see the class doc comment for why).
## pauses marks are assumed to fall inside the played range, which holds for
## every authored document; plan_chain() recomputes the exact figure from the
## real pause times when the job actually runs.
func _preview_totals() -> Dictionary:
    var hold := maxi(int(round(_s.pause_hold * _s.fps)), 0)
    var total := 0
    var held := 0
    for i in _chain.size():
        var e: Dictionary = _by_name.get(_chain[i], {})
        if e.is_empty(): continue
        var start := 0.0 if _s.show_intro else float(e.get("play_start", 0.0))
        var end: float = float(e.get("play_end", 0.0))
        var span := maxf(end - start, 0.0)
        var base := maxi(int(round(span * _s.fps)), 1)
        var marker_hold := int(e.get("pauses", 0)) * hold
        var join_hold := hold if (_s.join_pause and i < _chain.size() - 1) else 0
        total += base + marker_hold + join_hold
        held += marker_hold + join_hold
    return {"total": total, "held": held}


func _refresh() -> void:
    if _chain.is_empty():
        _frames_label.text = "chain is empty"
    _build_chain_rows()

    var first := _first_entry()
    var fmt := _s.fmt
    var cap := ZenExport.max_fps(fmt)
    _fps_spin.max_value = cap
    if _s.fps > cap:
        _s.fps = cap
        _fps_spin.value = cap

    var ffmpeg_ok := ZenExport.ffmpeg_available()
    for i in FORMATS.size():
        var disabled := ZenExport.needs_ffmpeg(FORMATS[i]) and not ffmpeg_ok
        _format.set_item_disabled(i, disabled)
    _ffmpeg_hint.visible = not ffmpeg_ok

    _path_preview.text = _resolved_path_preview()

    var scale := _s.scale
    if not first.is_empty():
        var d: Vector2 = first["design"]
        _res_label.text = "export resolution  %d x %d  (%dx%d canvas x%d)" % [
            int(d.x) * scale, int(d.y) * scale, int(d.x), int(d.y), scale]
    else:
        _res_label.text = ""

    if fmt == "gif":
        var delay := roundi(100.0 / float(maxi(_s.fps, 1)))
        var actual := 100.0 / float(maxi(delay, 1))
        _fps_note.text = "plays at %.1f fps" % actual if absf(actual - _s.fps) > 0.05 else ""
    else:
        _fps_note.text = ""

    var has_intro := false
    for nm in _chain:
        var e: Dictionary = _by_name.get(nm, {})
        if float(e.get("intro_end", 0.0)) > 0.0: has_intro = true; break
    _intro_check.disabled = not has_intro
    if not has_intro: _s.show_intro = false; _intro_check.button_pressed = false

    var has_pauses := false
    for nm in _chain:
        if int((_by_name.get(nm, {}) as Dictionary).get("pauses", 0)) > 0: has_pauses = true; break
    var has_joins := _chain.size() > 1
    var hold_enabled := has_pauses or has_joins
    if not hold_enabled:
        _s.pause_hold = 0.0
        _hold_slider.value = 0.0
    _hold_value.text = "%.1fs" % _s.pause_hold

    _join_row.visible = _chain.size() > 1

    var totals := _preview_totals()
    var total := int(totals["total"])
    var held := int(totals["held"])
    _frames_label.text = "%d frames - %.2fs (%d held)" % [
        total, float(total) / float(maxi(_s.fps, 1)), held]

    _gif_row.visible = fmt == "gif"
    _transparent_check.visible = fmt in ["gif", "png"]
    _cutout_row.visible = fmt == "gif" and _s.transparent
    _video_row.visible = fmt in ["mp4", "webm"]
    _avi_label.visible = fmt == "avi"
    _gif_quality_value.text = "%d/16" % _s.quality_gif
    _cutout_value.text = str(_s.cutout)
    _video_quality_value.text = "%d  (crf %d)" % [_s.quality, ZenExport.crf(_s.quality)]

    if not first.is_empty():
        var d2: Vector2 = first["design"]
        var est := ZenExport.estimate_bytes(fmt, int(d2.x), int(d2.y), scale,
                                            total, held, _s.quality_gif, _s.quality)
        var prefix := "Output size: ~" if fmt == "avi" \
                      else ("Rough guess: ~" if fmt in ["mp4", "webm"] else "Estimated size: ~")
        _size_label.text = "%s%s" % [prefix, ZenExport.human_size(est)]
    else:
        _size_label.text = ""

    _export_btn.text = "Cancel" if _running else "Export"
    var exports_dir := ProjectSettings.globalize_path(_s.out_dir)
    _folder_btn.disabled = not DirAccess.dir_exists_absolute(exports_dir)

    # Freeze every setting control once a job is running - the frame plan and
    # encoder args are committed at job start, so editing them mid-run would
    # either do nothing or lie about what is actually being produced.
    _format.disabled = _running
    _name_edit.editable = not _running
    _hold_slider.editable = hold_enabled and not _running
    _join_check.disabled = _running
    _gif_quality.editable = not _running
    _transparent_check.disabled = _running
    _cutout_slider.editable = not _running
    _video_quality.editable = not _running
    _intro_check.disabled = _running or _intro_check.disabled
    for b in _scale_buttons: b.disabled = _running
    _add_btn.disabled = _running or _chain.size() >= ZenExport.MAX_CHAIN


func _resolved_path_preview() -> String:
    var nm := ZenExport.sanitize(_name_edit.text if _name_edit.text != "" else _default_name())
    if _s.fmt == "png":
        return "%s/%s/%s_0000.png" % [_s.out_dir, nm, nm]
    return "%s/%s.%s" % [_s.out_dir, nm, _s.fmt]


func _build_chain_rows() -> void:
    for ch in _chain_box.get_children(): ch.queue_free()
    for i in _chain.size():
        var nm := _chain[i]
        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 6)
        var idx_label := Label.new()
        idx_label.text = "%d." % (i + 1)
        idx_label.custom_minimum_size = Vector2(20, 0)
        row.add_child(idx_label)
        var e: Dictionary = _by_name.get(nm, {})
        var name_label := Label.new()
        var span := maxf(float(e.get("play_end", 0.0)) - float(e.get("play_start", 0.0)), 0.0)
        var base := maxi(int(round(span * _s.fps)), 1)
        name_label.text = "%s   %.2fs / %d f" % [nm, span, base]
        name_label.size_flags_horizontal = SIZE_EXPAND_FILL
        row.add_child(name_label)

        var up := Button.new(); up.text = "^"; up.disabled = (i == 0) or _running
        up.pressed.connect(_on_move_pressed.bind(i, -1))
        row.add_child(up)
        var down := Button.new(); down.text = "v"; down.disabled = (i == _chain.size() - 1) or _running
        down.pressed.connect(_on_move_pressed.bind(i, 1))
        row.add_child(down)
        var rm := Button.new(); rm.text = "x"; rm.disabled = (_chain.size() <= 1) or _running
        rm.pressed.connect(_on_remove_pressed.bind(i))
        row.add_child(rm)

        _chain_box.add_child(row)


func _rebuild_add_list() -> void:
    _add_list.clear()
    var query := _add_search.text.to_lower()
    var first_design: Vector2 = _first_entry().get("design", Vector2.ZERO) if not _chain.is_empty() else Vector2.ZERO
    var names: Array = _by_name.keys()
    names.sort()
    for nm in names:
        if query != "" and not String(nm).to_lower().contains(query): continue
        var e: Dictionary = _by_name[nm]
        var idx := _add_list.add_item(String(nm))
        if not bool(e.get("ok", false)):
            _add_list.set_item_disabled(idx, true)
            _add_list.set_item_tooltip(idx, "could not be read")
            continue
        if first_design != Vector2.ZERO and Vector2(e["design"]) != first_design:
            var d: Vector2 = e["design"]
            _add_list.set_item_disabled(idx, true)
            _add_list.set_item_tooltip(idx, "%dx%d canvas, chain is %dx%d" % [
                int(d.x), int(d.y), int(first_design.x), int(first_design.y)])


# ---------------------------------------------------------------- handlers

func _on_add_pressed() -> void:
    if _chain.size() >= ZenExport.MAX_CHAIN:
        _status_label.text = "chain is full (%d max)" % ZenExport.MAX_CHAIN
        return
    _rebuild_add_list()
    _add_popup.popup_centered(Vector2(300, 320))


func _on_add_item_activated(idx: int) -> void:
    if _add_list.is_item_disabled(idx): return
    _chain.append(_add_list.get_item_text(idx))
    _add_popup.hide()
    _refresh()


func _on_move_pressed(i: int, dir: int) -> void:
    var j := i + dir
    if j < 0 or j >= _chain.size(): return
    var tmp := _chain[i]
    _chain[i] = _chain[j]
    _chain[j] = tmp
    _refresh()


func _on_remove_pressed(i: int) -> void:
    if _chain.size() <= 1: return
    _chain.remove_at(i)
    _refresh()


func _on_format_selected(idx: int) -> void:
    _s.fmt = FORMATS[idx]
    _refresh()


func _on_scale_pressed(i: int) -> void:
    _s.scale = i
    ZenSettings.set_export_scale(i)
    _refresh()


func _on_fps_changed(v: float) -> void:
    _s.fps = int(v)
    _refresh()


func _on_intro_toggled(on: bool) -> void:
    _s.show_intro = on
    _refresh()


func _on_hold_changed(v: float) -> void:
    _s.pause_hold = v
    _refresh()


func _on_join_toggled(on: bool) -> void:
    _s.join_pause = on
    _refresh()


func _on_gif_quality_changed(v: float) -> void:
    _s.quality_gif = int(v)
    _refresh()


func _on_transparent_toggled(on: bool) -> void:
    _s.transparent = on
    _refresh()


func _on_cutout_changed(v: float) -> void:
    _s.cutout = int(v)
    _refresh()


func _on_video_quality_changed(v: float) -> void:
    _s.quality = int(v)
    _refresh()


func _on_name_focus_exited() -> void:
    _name_edit.text = ZenExport.sanitize(_name_edit.text if _name_edit.text != "" else _default_name())
    _refresh()


func _on_folder_pressed() -> void:
    OS.shell_open(ProjectSettings.globalize_path(_s.out_dir))


func _on_close_pressed() -> void:
    if _running:
        if _job != null: _job.cancel_requested = true
        return
    closed.emit()


# ---------------------------------------------------------------- job wiring

func _on_export_pressed() -> void:
    if _running:
        if _job != null: _job.cancel_requested = true
        return
    if _chain.is_empty():
        _status_label.text = "nothing to export (empty chain)"
        return

    var links: Array = []
    for nm in _chain:
        var link := ZenExport.build_link(self, nm, _s.transparent)
        if link.is_empty():
            _status_label.text = "no such animation: %s" % nm
            for l in links: (l["sub"] as SubViewport).queue_free()
            return
        links.append(link)
    _links = links

    var plan := ZenExport.plan_chain(links, _s, _s.join_pause)
    if not bool(plan["ok"]):
        _status_label.text = String(plan["error"])
        _cleanup_links()
        return

    var name := ZenExport.sanitize(_name_edit.text if _name_edit.text != "" else _default_name())

    _job = ZenExport.Job.new()
    _job.progress.connect(_on_job_progress)
    _job.finished.connect(_on_job_finished)
    _running = true
    _status_label.text = "exporting..."
    _progress.visible = true
    _progress_label.visible = true
    _progress.value = 0
    _progress.max_value = maxi(int(ZenExport.chain_totals(plan["segments"])["total"]), 1)
    _refresh()

    # No `await` here on purpose: Job.run() returns at its first internal
    # await and resumes itself each frame, so holding this call would block
    # the dialog's own _process/input instead of letting it stay responsive
    # (progress bar, Cancel button) while the export runs.
    _job.run(self, plan["segments"], _s, name)


func _on_job_progress(frame: int, total: int) -> void:
    _progress.max_value = maxi(total, 1)
    _progress.value = frame
    _progress_label.text = "%d/%d" % [frame, total]


func _on_job_finished(result: Dictionary) -> void:
    _running = false
    _progress.visible = false
    _progress_label.visible = false
    _cleanup_links()
    _job = null

    if bool(result.get("ok", false)):
        _exported_ok = true
        _status_label.text = "%d frames -> %s" % [int(result["frames"]), String(result["path"])]
        ZenSettings.set_export_defaults({
            "fmt": _s.fmt, "fps": _s.fps, "show_intro": _s.show_intro,
            "transparent": _s.transparent, "quality_gif": _s.quality_gif,
            "quality_video": _s.quality, "cutout": _s.cutout,
            "pause_hold": _s.pause_hold, "join_pause": _s.join_pause,
        })
    elif bool(result.get("cancelled", false)):
        _status_label.text = "export cancelled"
    else:
        _status_label.text = "export failed: %s" % String(result.get("error", "unknown"))
    _refresh()


func _cleanup_links() -> void:
    for l in _links:
        var sub := (l as Dictionary).get("sub", null) as SubViewport
        if sub != null: sub.queue_free()
    _links = []


func _unhandled_input(ev: InputEvent) -> void:
    if ev.is_echo(): return
    if ev.is_action_pressed("zen_back"):
        _on_close_pressed()
        get_viewport().set_input_as_handled()
