extends Node
##
## Export entry point. Runs as a SCENE, not --script, because capturing pixels
## needs the main loop (and a real rendering driver - `--headless` cannot
## render at all: frame_post_draw never fires and the export hangs forever).
##
##   Godot --path . --rendering-driver opengl3 tools/export_scene.tscn -- \
##         --anim=mouse_ripple --fps=60 --fmt=webm --scale=2
##

var _sub: SubViewport = null


func _ready() -> void:
    # Vsync pins the loop to the monitor: ~200x slower (1.2 fps vs 234).
    DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
    Engine.max_fps = 0

    var a := _args()
    var anim := String(a.get("anim", "mouse_ripple"))
    var s := ZenExport.Settings.new()
    s.fmt = String(a.get("fmt", "webm"))
    s.fps = int(a.get("fps", 30))
    s.scale = clampi(int(a.get("scale", 4)), 1, ZenExport.MAX_SCALE)
    s.quality = int(a.get("quality", 70))
    s.show_intro = _flag(a, "intro")
    s.transparent = _flag(a, "transparent")
    s.pause_hold = float(a.get("pause_hold", 2.0))

    var cap := ZenExport.max_fps(s.fmt)
    if s.fps > cap:
        print("fps %d above %s cap, clamping to %d" % [s.fps, s.fmt, cap])
        s.fps = cap

    var path := "res://anims/%s.tscn" % anim
    if not ResourceLoader.exists(path):
        push_error("no such animation: " + path)
        get_tree().quit(1)
        return

    var canvas: ZenCanvas = (load(path) as PackedScene).instantiate()

    # BEFORE the canvas enters the tree. _ready() is what builds and plays the
    # live AnimationPlayer, and Godot defers _ready() to after add_child(), so
    # clearing the flag later (ZenExport.run does it too, belt and braces) would
    # be a race on exactly when that deferred call lands. An export must never
    # have a clock of its own: it poses at explicit times from its frame list.
    canvas.live_playback = false

    # Render into a SubViewport at the NATIVE canvas size; the finished frame is
    # upscaled afterwards. Drawing into a larger viewport would reposition every
    # element, because Zen geometry is a fraction of the canvas.
    _sub = SubViewport.new()
    _sub.size = Vector2i(canvas.design_size)
    _sub.transparent_bg = s.transparent
    _sub.render_target_update_mode = SubViewport.UPDATE_ONCE
    if not s.transparent:
        var bg := ColorRect.new()
        bg.size = canvas.design_size
        bg.color = canvas.clear_color
        _sub.add_child(bg)
    _sub.add_child(canvas)
    add_child(_sub)

    print("exporting %s -> %s  %dx%d @%dfps" % [
        anim, s.fmt, int(canvas.design_size.x) * s.scale,
        int(canvas.design_size.y) * s.scale, s.fps])

    var t0 := Time.get_ticks_msec()
    var r: Dictionary = await ZenExport.run(self, canvas, _sub, s, anim)
    var secs := float(Time.get_ticks_msec() - t0) / 1000.0

    if r.get("ok", false):
        print("OK  %d frames in %.1fs -> %s" % [r["frames"], secs, r["path"]])
        get_tree().quit(0)
    else:
        push_error("export failed: " + String(r.get("error", "unknown")))
        get_tree().quit(1)


## A boolean flag. `--intro` (bare) and `--intro=true/1/yes` are all true;
## absent, or an explicit false/0/no, is false.
##
## Written out rather than using bool(): GDScript's bool() has NO String
## constructor, so bool(a.get("intro", false)) fails to compile the moment the
## argument is actually supplied on the command line - the bare-flag path
## (which yields a real bool) hid it until `--intro=true` was first used.
func _flag(a: Dictionary, key: String) -> bool:
    if not a.has(key): return false
    var v: Variant = a[key]
    if v is bool: return v
    var t := String(v).to_lower().strip_edges()
    return t in ["true", "1", "yes", "on", ""]


## Parse --key=value pairs after the `--` separator.
func _args() -> Dictionary:
    var out := {}
    for raw in OS.get_cmdline_user_args():
        var arg := String(raw)
        if not arg.begins_with("--"): continue
        var body := arg.substr(2)
        var eq := body.find("=")
        if eq < 0:
            out[body] = true
        else:
            out[body.substr(0, eq)] = body.substr(eq + 1)
    return out
