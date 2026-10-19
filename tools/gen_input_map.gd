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
    "zen_back": [KEY_ESCAPE],
    "zen_restart": [KEY_R],
    "zen_prev": [KEY_UP],
    "zen_next": [KEY_DOWN],
    "zen_options": [KEY_O],
    "zen_export": [KEY_E],
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
    ProjectSettings.save()
    print("input map written")
    quit()

func _set_action(action_name: String, keys: Array, ctrl := false) -> void:
    var events := []
    for key in keys:
        var ev := InputEventKey.new()
        ev.physical_keycode = key
        ev.ctrl_pressed = ctrl
        events.append(ev)
    ProjectSettings.set_setting("input/%s" % action_name, {"deadzone": 0.2, "events": events})
