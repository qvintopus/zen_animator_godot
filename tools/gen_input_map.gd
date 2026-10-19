extends SceneTree

## Regenerates the [input] section of project.godot. Run once, then diff.
## See docs/plans/godot-integration.md Task 3 for why these are named actions
## rather than raw keycodes.

const ACTIONS := {
    "zen_play": [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE],
    "zen_back": [KEY_ESCAPE],
    "zen_restart": [KEY_R],
    "zen_prev": [KEY_UP],
    "zen_next": [KEY_DOWN],
    "zen_options": [KEY_O],
    "zen_scale_down": [KEY_LEFT],
    "zen_scale_up": [KEY_RIGHT],
}

func _init() -> void:
    for action in ACTIONS:
        _set_action(action, ACTIONS[action])
    for i in range(1, 10):
        _set_action("zen_signal_%d" % i, [KEY_0 + i])
    ProjectSettings.save()
    print("input map written")
    quit()

func _set_action(action_name: String, keys: Array) -> void:
    var events := []
    for key in keys:
        var ev := InputEventKey.new()
        ev.physical_keycode = key
        events.append(ev)
    ProjectSettings.set_setting("input/%s" % action_name, {"deadzone": 0.2, "events": events})
