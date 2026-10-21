extends Node
##
## Export entry point. Runs as a SCENE, not --script, because capturing pixels
## needs the main loop (and a real rendering driver - `--headless` cannot
## render at all: frame_post_draw never fires and the export hangs forever).
##
##   Godot --path . --rendering-driver opengl3 tools/export_scene.tscn -- \
##         --anim=mouse_ripple --fps=60 --fmt=webm --scale=2
##
## `--fmt=godot` writes scenes into another Godot project instead - nothing
## renders, so it also runs `--headless` (see ZenGodotExport):
##
##   Godot --headless --path . tools/export_scene.tscn -- --fmt=godot \
##         --chain=main_menu,pause_menu --target=/abs/game --subdir=zen \
##         --mode=standalone|plugin [--install_plugin]
##
## Without `--target` it writes into this project's exports/godot, a stub
## project to F6-test in and copy the subfolder from.
##
## `--res=1080p` (or 720p/1440p/4k/a bare short side) picks the scale for you
## and fails unless the canvas reaches that size at a whole-number scale.
##
## A thin caller over ZenExport.plan_chain()/Job - the same engine the Export
## dialog drives, so this is a scripted/batch door onto it, not a second
## implementation. `--chain=a,b,c` overrides `--anim=` for multi-link exports.
##

func _ready() -> void:
    # Vsync pins the loop to the monitor: ~200x slower (1.2 fps vs 234).
    DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
    Engine.max_fps = 0

    ZenSettings.apply_startup()

    var a := _args()
    var names := _chain_names(a)
    if String(a.get("fmt", "")) == "godot":
        _export_godot(a, names)
        return

    var s := ZenExport.Settings.new()
    s.fmt = String(a.get("fmt", "webm"))
    s.fps = int(a.get("fps", 30))
    s.scale = clampi(int(a.get("scale", ZenSettings.export_scale())), 1, ZenExport.MAX_SCALE)
    s.quality = int(a.get("quality", 70))
    s.quality_gif = clampi(int(a.get("quality_gif", 16)), 1, 16)
    s.cutout = clampi(int(a.get("cutout", 128)), 1, 255)
    s.show_intro = _flag(a, "intro")
    s.transparent = _flag(a, "transparent")
    s.pause_hold = float(a.get("pause_hold", 2.0))
    s.join_pause = _flag(a, "join_pause")
    if a.has("out"): s.out_dir = String(a["out"])

    var cap := ZenExport.max_fps(s.fmt)
    if s.fps > cap:
        print("fps %d above %s cap, clamping to %d" % [s.fps, s.fmt, cap])
        s.fps = cap

    var links := []
    for anim in names:
        var link := ZenExport.build_link(self, anim, s.transparent)
        if link.is_empty():
            push_error("no such animation: " + anim)
            get_tree().quit(1)
            return
        links.append(link)

    var plan := ZenExport.plan_chain(links, s, s.join_pause)
    if not bool(plan["ok"]):
        push_error("export failed: " + String(plan["error"]))
        get_tree().quit(1)
        return

    var first_canvas: ZenCanvas = links[0]["canvas"]
    if a.has("res"):
        var target := ZenExport.parse_target(String(a["res"]))
        var k := ZenExport.scale_for_target(first_canvas.design_size, target)
        if k == 0:
            push_error("--res=%s: a %dx%d canvas has no whole-number scale (1..%d) to it" % [
                String(a["res"]), int(first_canvas.design_size.x),
                int(first_canvas.design_size.y), ZenExport.MAX_SCALE])
            get_tree().quit(1)
            return
        s.scale = k

    var name := String(a.get("name", names[0] if names.size() == 1 else "%s_chain" % names[0]))
    print("exporting %s -> %s  %dx%d @%dfps" % [
        ",".join(names), s.fmt, int(first_canvas.design_size.x) * s.scale,
        int(first_canvas.design_size.y) * s.scale, s.fps])

    var job := ZenExport.Job.new()
    job.verbose = true
    var t0 := Time.get_ticks_msec()
    var r: Dictionary = await job.run(self, plan["segments"], s, name)
    var secs := float(Time.get_ticks_msec() - t0) / 1000.0

    if r.get("ok", false):
        print("OK  %d frames in %.1fs -> %s" % [r["frames"], secs, r["path"]])
        get_tree().quit(0)
    else:
        push_error("export failed: " + String(r.get("error", "unknown")))
        get_tree().quit(1)


func _export_godot(a: Dictionary, names: PackedStringArray) -> void:
    var gs := ZenGodotExport.Settings.new()
    gs.target_dir = String(a.get("target", ""))
    gs.to_exports = gs.target_dir == ""
    gs.subdir = String(a.get("subdir", "zen"))
    gs.mode = ZenGodotExport.Mode.PLUGIN if String(a.get("mode", "standalone")) == "plugin" \
        else ZenGodotExport.Mode.STANDALONE
    gs.install_plugin = _flag(a, "install_plugin")
    var r := ZenGodotExport.export_chain(Array(names), gs)
    if bool(r["ok"]):
        print("OK  %d files -> %s in %s" % [(r["files"] as Array).size(),
            ", ".join(PackedStringArray(r["scenes"])), ZenGodotExport.target_root(gs)])
        print("inherit with: " + ZenGodotExport.extends_line(gs))
        get_tree().quit(0)
    else:
        push_error("export failed: " + String(r["error"]))
        get_tree().quit(1)


## `--chain=a,b,c` overrides `--anim=`; a bare `--anim=` is a one-link chain.
func _chain_names(a: Dictionary) -> PackedStringArray:
    if a.has("chain"):
        var out := PackedStringArray()
        for part in String(a["chain"]).split(","):
            var nm := part.strip_edges()
            if nm != "": out.append(nm)
        if not out.is_empty(): return out
    return PackedStringArray([String(a.get("anim", "mouse_ripple"))])


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
