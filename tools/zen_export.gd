@tool
class_name ZenExport
extends RefCounted
##
## Frame-exact video export: pose the scene at t, grab the viewport, pipe raw
## RGBA to ffmpeg. Port of src/anim_editor_zen/zen_export.c.
##
## The design rests on five things measured on this machine (Godot 4.7.2):
##   1. ZenCanvas.pose(t) is a PURE function of t, so a frame is ASKED FOR, not
##      captured. Frame i comes from t = start + i/fps, never an accumulated dt,
##      so there is no drift however slow the render is.
##   2. OS.execute_with_pipe gives a WRITABLE stdio FileAccess - raw frames go
##      straight to ffmpeg, no temp PNGs.
##   3. stdin must be CLOSED and the process WAITED on. Killing ffmpeg truncates
##      the container and leaves a 0-byte file.
##   4. Vsync must be off: it is a ~200x throughput difference (1.2 fps vs 234).
##   5. Godot already blends straight alpha, so the raylib premultiply /
##      unpremultiply workaround does NOT port - doing it here would double-darken
##      every semi-transparent edge.
##
## The scene renders at the NATIVE canvas size and the finished frame is
## upscaled nearest-neighbour. This is load-bearing, not an optimisation:
## element geometry is a FRACTION of the canvas, so rendering into a bigger
## viewport would reposition everything instead of enlarging it.
##

const FFMPEG := "/usr/bin/ffmpeg"

## fps caps: GIF stores delays in centiseconds, so only 100/n is exact.
const MAX_FPS_GIF := 60
const MAX_FPS_VIDEO := 120


class Settings extends RefCounted:
    var fmt := "webm"           # webm | mp4 | gif | png
    var fps := 30
    var scale := 4              # 1..8; 320x180 x4 = 1280x720
    var quality := 70           # 0..100, mapped to a codec CRF
    var show_intro := false     # false => seamless loop, true => one-shot clip
    var pause_hold := 2.0       # seconds a pause marker freezes for
    var transparent := false    # GIF/PNG only; VP9 decodes yuva420p opaque
    var out_dir := "res://exports"


## Map 0..100 quality to a CRF, matching VideoCRF() in zen_export.c:
## 34 (worst) .. 18 (best).
static func _crf(quality: int) -> int:
    return int(round(34.0 - float(quality) * 0.16))


## Shell-safety: the name reaches a command line. SanitizeName, zen_export.c:696.
static func sanitize(name: String) -> String:
    var bad := " '\"\\/`$;&|<>\n\t"
    var out := ""
    for ch in name:
        out += "_" if bad.contains(ch) else ch
    return out


## 320x180 is small, so allow a deeper upscale than the C's 4x cap.
const MAX_SCALE := 8


static func max_fps(fmt: String) -> int:
    return MAX_FPS_GIF if fmt == "gif" else MAX_FPS_VIDEO


## The frame plan: which document time each output frame samples.
##
## start = show_intro ? 0 : intro_end, end = outro_start. The OUTRO IS ALWAYS
## TRIMMED - it is the tail the doc plays on the way out, and including it means
## the result cannot loop. Pause markers become durations, because a file has
## nobody to press a key (zen_export.c:296-340).
static func frame_times(canvas: ZenCanvas, s: Settings, pauses: Array) -> PackedFloat32Array:
    var start := 0.0 if s.show_intro else canvas.play_start()
    var end := canvas.play_end()
    var span := maxf(end - start, 0.0)
    var base := maxi(int(round(span * s.fps)), 1)
    var hold := maxi(int(round(s.pause_hold * s.fps)), 0)

    var marks: Array = []
    for p in pauses:
        var pt := float(p)
        if pt >= start and pt < end: marks.append(pt)   # [a,b), see below
    marks.sort()

    var out := PackedFloat32Array()
    for i in base:
        var t := start + float(i) / float(s.fps)
        out.append(t)
        # A marker's own frame is the last free-running one; the hold is added
        # AFTER it, so a "2 second" hold is not two seconds plus a frame.
        for m in marks:
            var nxt := start + float(i + 1) / float(s.fps)
            if m >= t and m < nxt:
                for _h in hold: out.append(m)
    return out


static func _args(s: Settings, w: int, h: int, out_path: String) -> PackedStringArray:
    var a := PackedStringArray([
        "-y", "-hide_banner", "-loglevel", "error",
        "-f", "rawvideo", "-pix_fmt", "rgba",
        "-s", "%dx%d" % [w, h], "-r", str(s.fps), "-i", "-"])
    match s.fmt:
        "webm":
            a.append_array(PackedStringArray([
                "-c:v", "libvpx-vp9", "-crf", str(_crf(s.quality)),
                "-b:v", "0", "-pix_fmt", "yuv420p"]))
        "mp4":
            a.append_array(PackedStringArray([
                "-c:v", "libx264", "-crf", str(_crf(s.quality)),
                "-pix_fmt", "yuv420p",
                "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2"]))
        "gif":
            # ffmpeg's two-pass palette beats a fixed palette, and ffmpeg is
            # already a dependency - no need to vendor msf_gif.
            var pal := "split[a][b];[a]palettegen=stats_mode=diff"
            if s.transparent: pal += ":reserve_transparent=1"
            pal += "[p];[b][p]paletteuse=dither=bayer"
            a.append_array(PackedStringArray(["-vf", pal]))
    a.append(out_path)
    return a


## Pause marker times from the canvas's own `pauses`, ascending.
##
## `once` is deliberately ignored: an export is a SINGLE forward pass, so every
## marker is on its first pass and `once` could never suppress anything
## (zen_export.c:323-325).
static func pause_times(canvas: ZenCanvas) -> Array:
    var out: Array = []
    for p in canvas.pauses:
        out.append(float(p["t"]))
    out.sort()
    return out


## Run the export. `host` must be a Node in the tree (it awaits frames).
## Returns {ok: bool, frames: int, path: String, error: String}.
static func run(host: Node, canvas: ZenCanvas, sub: SubViewport,
                s: Settings, name: String, pauses := []) -> Dictionary:
    # An empty `pauses` means "take them from the scene". Passing them stays
    # supported so a test can plan a frame list without a canvas's pauses set.
    var marks: Array = pauses if not pauses.is_empty() else pause_times(canvas)
    var times := frame_times(canvas, s, marks)

    # A frame is a pure function of (scene, t), and a signal override is the one
    # thing that could break that mid-render: the global ZenSignals autoload
    # outlives any one scene, and this canvas is in the `zen_canvas` group like
    # any other, so a stray emit from editor tooling would otherwise reach it.
    # Silence the bus for the whole render - a clock or a fired signal ticking
    # inside the capture await would re-pose the canvas and every frame would
    # come out identical.
    var bus := canvas.bus()
    if bus != null: bus.inert = true

    # Same reasoning for the Godot AnimationPlayer the canvas builds for live
    # F6 playback: it must not tick during this render. Stopping it is not
    # enough on its own - _process would keep re-posing - so the canvas's own
    # per-frame pose is switched off too, leaving pose_looping() below as the
    # ONLY thing that moves this scene.
    canvas.live_playback = false
    canvas.set_process(false)
    var ap := canvas.animation_player()
    if ap != null and ap.is_playing(): ap.stop()

    if times.is_empty():
        return {"ok": false, "error": "nothing to export (zero-length range)"}

    var w := int(canvas.design_size.x) * s.scale
    var h := int(canvas.design_size.y) * s.scale
    var safe := sanitize(name)

    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(s.out_dir))

    if s.fmt == "png":
        return await _run_png(host, canvas, sub, s, safe, times, w, h)

    var out_path := ProjectSettings.globalize_path(
        "%s/%s.%s" % [s.out_dir, safe, s.fmt])
    var proc := OS.execute_with_pipe(FFMPEG, _args(s, w, h, out_path))
    if proc.is_empty():
        return {"ok": false, "error": "could not start ffmpeg at " + FFMPEG}

    var pipe: FileAccess = proc["stdio"]
    var pid: int = proc["pid"]
    for i in times.size():
        var img := await _frame(host, canvas, sub, times[i], w, h, not s.show_intro)
        pipe.store_buffer(img.get_data())
        if i % 30 == 0:
            print("  %d/%d" % [i, times.size()])

    pipe.close()                                    # EOF -> ffmpeg finalizes
    while OS.is_process_running(pid):               # never kill: truncates
        OS.delay_msec(10)
    var code := OS.get_process_exit_code(pid)
    return {
        "ok": code == 0,
        "frames": times.size(),
        "path": out_path,
        "error": "" if code == 0 else "ffmpeg exit %d" % code,
    }


static func _run_png(host: Node, canvas: ZenCanvas, sub: SubViewport,
                     s: Settings, safe: String, times: PackedFloat32Array,
                     w: int, h: int) -> Dictionary:
    var dir := "%s/%s" % [s.out_dir, safe]
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
    for i in times.size():
        var img := await _frame(host, canvas, sub, times[i], w, h, not s.show_intro)
        img.save_png("%s/%s_%04d.png" % [dir, safe, i])
    return {"ok": true, "frames": times.size(),
            "path": ProjectSettings.globalize_path(dir), "error": ""}


## One frame: pose, render, read back, orient, upscale.
static func _frame(host: Node, canvas: ZenCanvas, sub: SubViewport,
                   t: float, w: int, h: int, looping: bool) -> Image:
    # A loop render (intro hidden) blends the seam; a one-shot (intro shown)
    # must display its authored tail. show_intro is exactly that distinction.
    canvas.pose_looping(t, looping)
    sub.render_target_update_mode = SubViewport.UPDATE_ONCE
    await RenderingServer.frame_post_draw
    var img := sub.get_texture().get_image()
    # NO flip here. raylib's RenderTexture2D is bottom-up and zen_export.c has to
    # ImageFlipVertical every frame; Godot's SubViewport already reads back
    # top-down. Flipping turned out to be invisible on the centred, symmetric
    # ripple and only showed up once text was rendered - hence the check in
    # tests/run_tests.gd that pins orientation with an asymmetric probe.
    if img.get_size() != Vector2i(w, h):
        img.resize(w, h, Image.INTERPOLATE_NEAREST)
    if img.get_format() != Image.FORMAT_RGBA8:
        img.convert(Image.FORMAT_RGBA8)
    return img
