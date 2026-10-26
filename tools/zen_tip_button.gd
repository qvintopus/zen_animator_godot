class_name ZenTipButton
extends Button
## A Button whose hover tooltip is a ZenTooltip.

var tip := {}:
    set(v):
        tip = v
        # Godot only asks for a tooltip when this is non-empty; it is also
        # what shows if the custom one cannot be built.
        tooltip_text = ZenTooltip.text(v)


func _make_custom_tooltip(_for_text: String) -> Object:
    return ZenTooltip.build(tip)
