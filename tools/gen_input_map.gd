extends SceneTree

## Regenerates the [input] section of project.godot. Run once, then diff.
## See docs/plans/godot-integration.md Task 3 for why these are named actions
## rather than raw keycodes.
##
## ProjectSettings already has project.godot loaded, so an action dropped from
## ACTIONS below is NOT removed by set_setting() alone - it stays in the
## loaded settings and gets written straight back out. Retired actions are
## cleared explicitly before saving.

const RETIRED := ["zen_scale_down", "zen_scale_up"]

const ACTIONS := {
    "zen_play": [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE],
    "zen_continue": [KEY_SPACE],      # resume playback held at a pause marker
    "zen_back": [KEY_ESCAPE],
    "zen_restart": [KEY_R],
    "zen_prev": [KEY_UP],
    "zen_next": [KEY_DOWN],
    "zen_options": [KEY_O],
    "zen_export": [KEY_E],
    "zen_toggle_intro": [KEY_I],
    "zen_toggle_loop": [KEY_L],
    "zen_tab": [KEY_TAB],
    "zen_help": [KEY_H],      # toggles the hotkey sheet (ZenHotkeyHelp)
    "zen_delete": [KEY_DELETE],   # gallery: trash the selected rows
    # Shape editor. Several share a key with a gallery action (1-3, R, L):
    # the editor is an overlay that consumes its keys first, and the gallery
    # ignores every key but ESC while it is open.
    "zen_edit_ink_empty": [KEY_1],
    "zen_edit_ink_fill": [KEY_2],
    "zen_edit_ink_outline": [KEY_3],
    "zen_edit_brush_down": [KEY_BRACKETLEFT],
    "zen_edit_brush_up": [KEY_BRACKETRIGHT],
    "zen_edit_fit": [KEY_F],
    "zen_edit_tool_pen": [KEY_P],
    "zen_edit_tool_line": [KEY_L],
    "zen_edit_tool_rect": [KEY_R],
    "zen_edit_tool_fill": [KEY_G],
    "zen_edit_mirror": [KEY_M],
    # Gallery scene CRUD.
    "zen_new": [KEY_N],
    "zen_rename": [KEY_F2],
    # Scene editor. 1-7 summon panels (the shape editor's inks share 1-3);
    # while the scene plays they fire signals instead (zen_signal_N).
    "zen_edit_autokey": [KEY_K],
    "zen_edit_home": [KEY_HOME],
    "zen_edit_frame_prev": [KEY_LEFT],
    "zen_edit_frame_next": [KEY_RIGHT],
    "zen_edit_panel_1": [KEY_1],
    "zen_edit_panel_2": [KEY_2],
    "zen_edit_panel_3": [KEY_3],
    "zen_edit_panel_4": [KEY_4],
    "zen_edit_panel_5": [KEY_5],
    "zen_edit_panel_6": [KEY_6],
    "zen_edit_panel_7": [KEY_7],
    "zen_edit_key_prev": [KEY_UP],
    "zen_edit_key_next": [KEY_DOWN],
}

func _init() -> void:
    for action in RETIRED:
        ProjectSettings.set_setting("input/%s" % action, null)
    for action in ACTIONS:
        _set_action(action, ACTIONS[action])
    for i in range(1, 10):
        _set_action("zen_signal_%d" % i, [KEY_0 + i])
    # Ctrl+E tags the current animation onto the export queue rather than
    # opening the dialog - a distinct action, not a modifier check on
    # zen_export, so _unhandled_input can simply check this one first.
    _set_action("zen_export_queue", [KEY_E], true)
    _set_action("zen_edit_save", [KEY_S], true)
    # Checked before zen_edit_save, which a non-exact match also satisfies.
    _set_action("zen_edit_save_as", [KEY_S], true, true)
    _set_action("zen_duplicate", [KEY_D], true)
    _set_action("zen_edit_select_all", [KEY_A], true)
    # Checked before zen_play (ENTER) for the same reason.
    _set_action("zen_edit_scene", [KEY_ENTER, KEY_KP_ENTER], true)
    _set_action("zen_edit_undo", [KEY_Z], true)
    # Redo is checked before undo by the editor: a non-exact match lets
    # Ctrl+Shift+Z satisfy the Ctrl+Z action too.
    _set_action("zen_edit_redo", [KEY_Z], true, true)
    _add_event("zen_edit_redo", KEY_Y, true)
    ProjectSettings.save()
    print("input map written")
    quit()

func _set_action(action_name: String, keys: Array, ctrl := false, shift := false) -> void:
    var events := []
    for key in keys:
        var ev := InputEventKey.new()
        ev.physical_keycode = key
        ev.ctrl_pressed = ctrl
        ev.shift_pressed = shift
        events.append(ev)
    ProjectSettings.set_setting("input/%s" % action_name, {"deadzone": 0.2, "events": events})


func _add_event(action_name: String, key: int, ctrl := false) -> void:
    var cur: Dictionary = ProjectSettings.get_setting("input/%s" % action_name)
    var ev := InputEventKey.new()
    ev.physical_keycode = key
    ev.ctrl_pressed = ctrl
    (cur["events"] as Array).append(ev)
    ProjectSettings.set_setting("input/%s" % action_name, cur)
