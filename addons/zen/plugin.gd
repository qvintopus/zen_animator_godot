@tool
extends EditorPlugin
##
## What enabling the addon in another project does: register the ZenSignals
## relay, so game code can broadcast a signal to every canvas on screen. The
## runtime's class_names need no registering - they exist as soon as the
## folder does.
##
## Not enabled in this project: its project.godot declares the autoload itself.
##

const AUTOLOAD := "ZenSignals"


func _enable_plugin() -> void:
	if not ProjectSettings.has_setting("autoload/" + AUTOLOAD):
		add_autoload_singleton(AUTOLOAD, "res://addons/zen/runtime/zen_signals.gd")


func _disable_plugin() -> void:
	if ProjectSettings.has_setting("autoload/" + AUTOLOAD):
		remove_autoload_singleton(AUTOLOAD)
