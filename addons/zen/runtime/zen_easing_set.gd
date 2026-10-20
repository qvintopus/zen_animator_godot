@tool
class_name ZenEasingSet
extends Resource
##
## The project's shared custom easings, by name: res://assets/easings.tres.
##
## Played scenes never need this - their curves are already baked into bezier
## keys. The scene editor does: a key it rebakes with a custom name gets its
## real curve only if the name is registered, as ZenEasing falls back to linear
## for a name it does not know. Referenced by NAME because the C's custom
## easing ids were not stable across runs (anim_ease_custom.h:13-17).
##

const PATH := "res://assets/easings.tres"

@export var curves: Dictionary[String, ZenCurve] = {}


## Register every curve with ZenEasing.
func register() -> void:
    for n in curves:
        ZenEasing.register_custom(n, curves[n])


## Register the project's set, if there is one.
static func load_project() -> void:
    if not ResourceLoader.exists(PATH): return
    var s := load(PATH) as ZenEasingSet
    if s != null: s.register()
