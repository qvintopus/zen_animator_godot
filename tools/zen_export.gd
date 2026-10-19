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

## Links in one chained export. EXP_CHAIN_MAX, zen_export.c:214.
const MAX_CHAIN := 8


class Settings extends RefCounted:
    var fmt := "webm"           # webm | mp4 | gif | avi | png
    var fps := 30
    var scale := 4              # 1..8; 320x180 x4 = 1280x720
    var quality := 70           # 0..100, mapped to a codec CRF (video only)
    var quality_gif := 16       # 1..16, palette depth (GIF only)
    var cutout := 128           # 1..255 alpha threshold (GIF + transparent)
    var show_intro := false     # false => seamless loop, true => one-shot clip
    var pause_hold := 2.0       # seconds a pause marker freezes for
    var join_pause := true      # freeze on each join between chained animations
    var transparent := false    # GIF/PNG only; VP9 decodes yuva420p opaque
    var out_dir := "res://exports"


## Map 0..100 quality to a CRF, matching VideoCRF() in zen_export.c:
## 34 (worst) .. 18 (best).
static func _crf(quality: int) -> int:
    return int(round(34.0 - float(quality) * 0.16))


## Public form of the above: the export screen shows the resolved CRF next to
## the quality slider, the way the C modal does (zen_export.c:1512-1523).
static func crf(quality: int) -> int:
    return _crf(quality)


## Is there an ffmpeg to pipe to? Video formats stay VISIBLE but disabled when
## there is not, rather than vanishing - a missing dependency should read as
## "install this", not as "this build cannot do video" (zen_export.c:280-284).
static var _ffmpeg_ok := -1

static func ffmpeg_available() -> bool:
    if _ffmpeg_ok < 0:
        _ffmpeg_ok = 1 if FileAccess.file_exists(FFMPEG) else 0
    return _ffmpeg_ok == 1


static func needs_ffmpeg(fmt: String) -> bool:
    return fmt != "png"


static func human_size(bytes: float) -> String:
    if bytes < 1024.0: return "%d B" % int(bytes)
    if bytes < 1048576.0: return "%.0f KB" % (bytes / 1024.0)
    return "%.1f MB" % (bytes / 1048576.0)


## Output size guess. CALIBRATED, NOT DERIVED - the coefficients come straight
## from EstimateBytes()/EstimateFrames() in zen_export.c:619-692, fitted against
## real exports across 16 fps/scale combinations because the obvious
## pixels-x-bytes model was wrong by up to 112x. Two things break that model:
##
##   - A nearest-neighbour upscale duplicates pixels, and both LZW (gif/png) and
##     H.264 encode that redundancy nearly free: cost grows about scale^1.1 and
##     scale^0.6 respectively, NOT scale^2. Hence base canvas pixels with an
##     explicit scale exponent.
##   - Compressed size tracks how much the animation MOVES, which no setting
##     here can observe. That is the error floor, and why video is labelled a
##     rough guess rather than an estimate.
##
## Held frames (pause markers, chain joins) are charged at a DISCOUNT for the
## formats that difference between frames - a held frame is pixel-identical to
## the one before it. PNG (a whole file each) and raw AVI pay full price.
static func estimate_bytes(fmt: String, base_w: int, base_h: int, scale: int,
                           frames: int, held: int,
                           quality_gif: int, quality_video: int) -> float:
    var f := float(frames)
    if held > 0 and held <= frames and fmt in ["gif", "mp4", "webm"]:
        f = float(frames - held) + 0.1 * float(held)
    var base_px := float(base_w) * float(base_h) * f
    var sc := float(scale)
    match fmt:
        "gif":
            return 0.0112 * base_px * pow(sc, 1.09) * (float(quality_gif) / 16.0)
        "png":
            return 0.0121 * base_px * pow(sc, 1.09)
        "avi":
            # rawvideo bgr24 is 3 bytes per pixel with no compression at all:
            # exact arithmetic, not a guess.
            return float(base_w * scale) * float(base_h * scale) * f * 3.0
        "mp4", "webm":
            # CRF moves size a little under 2x per 6 points; the rest is the
            # fitted content-independent floor.
            var q := pow(0.89, float(crf(quality_video)) - 23.0)
            var bytes := 0.01146 * float(base_w) * float(base_h) \
                         * pow(f, 0.55) * pow(sc, 0.6) * q
            return bytes * 0.85 if fmt == "webm" else bytes
    return 0.0


## Snap alpha to 0 or 255 against `threshold`.
##
## GIF transparency is one bit, so a soft edge has to be decided one way or the
## other; msf_gif did this with alpha_threshold in the C (zen_export.c:799) and
## ffmpeg's palette path has no equivalent, so it happens here.
##
## Applied at the NATIVE canvas size, BEFORE the upscale: a nearest-neighbour
## enlargement only duplicates pixels, so the result is identical to cutting out
## afterwards while touching ~16x fewer pixels at scale 4.
static func cutout(img: Image, threshold: int) -> void:
    if img.get_format() != Image.FORMAT_RGBA8:
        img.convert(Image.FORMAT_RGBA8)
    var th := clampi(threshold, 1, 255)
    var d := img.get_data()
    var i := 3
    while i < d.size():
        d[i] = 255 if d[i] >= th else 0
        i += 4
    img.set_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, d)


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


## Free-running frames in one document, before any pause hold is expanded.
## Shared so a chain's held-frame count (and so the size estimate) is derived
## from the same arithmetic the frame list itself uses.
static func base_frame_count(canvas: ZenCanvas, s: Settings) -> int:
    var start := 0.0 if s.show_intro else canvas.play_start()
    var span := maxf(canvas.play_end() - start, 0.0)
    return maxi(int(round(span * s.fps)), 1)


static func hold_frame_count(s: Settings) -> int:
    return maxi(int(round(s.pause_hold * s.fps)), 0)


## The frame plan: which document time each output frame samples.
##
## start = show_intro ? 0 : intro_end, end = outro_start. The OUTRO IS ALWAYS
## TRIMMED - it is the tail the doc plays on the way out, and including it means
## the result cannot loop. Pause markers become durations, because a file has
## nobody to press a key (zen_export.c:296-340).
static func frame_times(canvas: ZenCanvas, s: Settings, pauses: Array) -> PackedFloat32Array:
    var start := 0.0 if s.show_intro else canvas.play_start()
    var end := canvas.play_end()
    var base := base_frame_count(canvas, s)
    var hold := hold_frame_count(s)

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
            # max_colors tracks the C's 1..16 palette-quality slider: 16 is the
            # full 256-colour palette, lower trades colours for size.
            if s.quality_gif < 16:
                var cols := clampi(int(round(256.0 * float(s.quality_gif) / 16.0)), 4, 256)
                pal = pal.replace("palettegen=", "palettegen=max_colors=%d:" % cols)
            a.append_array(PackedStringArray(["-vf", pal]))
        "avi":
            # Uncompressed: no quality control, by design (zen_export.c:810-812).
            a.append_array(PackedStringArray(["-c:v", "rawvideo", "-pix_fmt", "bgr24"]))
    a.append(out_path)
    return a


## Resolve an animation name into a {canvas, sub} link: instantiate the scene,
## clear `live_playback` BEFORE it enters the tree, and build the SubViewport
## it renders into. The one place this happens, so the CLI and the Export
## dialog build segments identically - a size/pose difference between the two
## would otherwise be possible to introduce by accident.
##
## `host` must be a Node already in the tree; the new SubViewport is added
## under it. Returns {} when there is no such animation.
static func build_link(host: Node, name: String, transparent: bool) -> Dictionary:
    var path := "res://anims/%s.tscn" % name
    if not ResourceLoader.exists(path):
        return {}

    var canvas: ZenCanvas = (load(path) as PackedScene).instantiate()
    # BEFORE the canvas enters the tree - see export_scene.gd's longer note;
    # _ready() builds the live AnimationPlayer and Godot defers it to after
    # add_child(), so clearing this later would race on when that call lands.
    canvas.live_playback = false

    # Render at the NATIVE canvas size; the frame is upscaled afterwards.
    # Drawing into a larger viewport would reposition every element, because
    # Zen geometry is a fraction of the canvas.
    var sub := SubViewport.new()
    sub.size = Vector2i(canvas.design_size)
    sub.transparent_bg = transparent
    sub.render_target_update_mode = SubViewport.UPDATE_ONCE
    if not transparent:
        var bg := ColorRect.new()
        bg.size = canvas.design_size
        bg.color = canvas.clear_color
        sub.add_child(bg)
    sub.add_child(canvas)
    host.add_child(sub)

    return {"canvas": canvas, "sub": sub}


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


## One link of a chained export, resolved and frozen before anything is
## allocated. ExpSegment, zen_export.c:214-222.
class ChainSegment extends RefCounted:
    var canvas: ZenCanvas = null
    var sub: SubViewport = null
    var times := PackedFloat32Array()   # document times, pause holds expanded
    var base_frames := 0                # free-running frames, before holds
    var join_hold := 0                  # frozen frames appended AFTER this link

    func held_frames() -> int:
        return times.size() - base_frames + join_hold


## Resolve a chain into segments, or say why it cannot be run.
##
## `links` is [{canvas: ZenCanvas, sub: SubViewport, pauses: Array (optional)}].
## Returns {ok, error, segments}: the chain is frozen HERE, before any encoder
## is opened, so a bad link fails with nothing half-written on disk - the same
## ordering JobStart() uses (zen_export.c:764-769).
##
## Every link must share one design_size. The C had no such case (its canvas
## size is global); here it is per-scene, and there is no single right answer
## for mixing them - letterbox and stretch are both wrong in different ways -
## so a mismatch is refused rather than guessed at.
static func plan_chain(links: Array, s: Settings, join_pause: bool) -> Dictionary:
    if links.is_empty():
        return {"ok": false, "error": "nothing to export (empty chain)", "segments": []}
    if links.size() > MAX_CHAIN:
        return {"ok": false, "error": "chain is full (%d max)" % MAX_CHAIN, "segments": []}

    var segs: Array = []
    var first := Vector2.ZERO
    for i in links.size():
        var link: Dictionary = links[i]
        var canvas: ZenCanvas = link.get("canvas", null)
        if canvas == null:
            return {"ok": false, "error": "link %d has no canvas" % (i + 1), "segments": []}
        if i == 0:
            first = canvas.design_size
        elif canvas.design_size != first:
            return {"ok": false, "segments": [],
                    "error": "link %d canvas is %dx%d, chain is %dx%d" % [
                        i + 1, int(canvas.design_size.x), int(canvas.design_size.y),
                        int(first.x), int(first.y)]}

        # An empty `pauses` means "take them from the scene". Passing them stays
        # supported so a test can plan a frame list without a canvas's pauses set.
        var marks: Array = link.get("pauses", [])
        if marks.is_empty(): marks = pause_times(canvas)

        var seg := ChainSegment.new()
        seg.canvas = canvas
        seg.sub = link.get("sub", null)
        seg.times = frame_times(canvas, s, marks)
        seg.base_frames = base_frame_count(canvas, s)
        if seg.times.is_empty():
            return {"ok": false, "segments": [],
                    "error": "nothing to export (zero-length range)"}
        segs.append(seg)

    # A join is a beat between two links, so the LAST one never gets one.
    if join_pause and segs.size() > 1:
        var hold := hold_frame_count(s)
        for i in range(segs.size() - 1):
            segs[i].join_hold = hold
    return {"ok": true, "error": "", "segments": segs}


## Frame and held-frame totals for a planned chain - what the modal's
## "N frames - X.XXs (M held)" line and the size estimate are built from.
static func chain_totals(segments: Array) -> Dictionary:
    var total := 0
    var held := 0
    for seg in segments:
        var s := seg as ChainSegment
        total += s.times.size() + s.join_hold
        held += s.held_frames()
    return {"total": total, "held": held}


## A running export.
##
## There is no thread here and no manual chunking: _frame()'s
## `await RenderingServer.frame_post_draw` yields the whole engine tick, so the
## UI repaints and `cancel_requested` is seen once per frame for free. The C had
## to hand-roll that as EXPORT_CHUNK because it owned its own frame loop.
class Job extends RefCounted:
    signal progress(frame: int, total: int)
    signal finished(result: Dictionary)

    var cancel_requested := false
    var verbose := false            # the CLI prints; the dialog has a bar
    var frame := 0
    var total := 0
    var result := {}

    var _pipe: FileAccess = null
    var _pid := -1
    var _out_path := ""
    var _is_png := false

    ## Render every segment. Returns the same dictionary it emits on `finished`:
    ## {ok, frames, path, error, cancelled}.
    func run(host: Node, segments: Array, s: ZenExport.Settings, name: String) -> Dictionary:
        total = int(ZenExport.chain_totals(segments)["total"])
        frame = 0

        for seg in segments:
            ZenExport.quiesce((seg as ZenExport.ChainSegment).canvas)

        var first := (segments[0] as ZenExport.ChainSegment).canvas
        var w := int(first.design_size.x) * s.scale
        var h := int(first.design_size.y) * s.scale
        var safe := ZenExport.sanitize(name)
        _is_png = s.fmt == "png"

        DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(s.out_dir))

        if _is_png:
            # A sequence is many files, so it gets its own folder rather than
            # scattering hundreds of pngs next to the single-file exports.
            _out_path = ProjectSettings.globalize_path("%s/%s" % [s.out_dir, safe])
            DirAccess.make_dir_recursive_absolute(_out_path)
        else:
            _out_path = ProjectSettings.globalize_path(
                "%s/%s.%s" % [s.out_dir, safe, s.fmt])
            var proc := OS.execute_with_pipe(ZenExport.FFMPEG,
                                             ZenExport._args(s, w, h, _out_path))
            if proc.is_empty():
                return _fail("could not start ffmpeg at " + ZenExport.FFMPEG)
            _pipe = proc["stdio"]
            _pid = int(proc["pid"])

        var cut := s.cutout if (s.fmt == "gif" and s.transparent) else 0
        for seg_v in segments:
            var seg := seg_v as ZenExport.ChainSegment
            var last: Image = null
            for i in seg.times.size():
                if cancel_requested: return _cancel()
                last = await ZenExport._frame(host, seg.canvas, seg.sub,
                                              seg.times[i], w, h,
                                              not s.show_intro, cut)
                _write(last, safe)
            # The join beat is a FREEZE, so its frames are the segment's last
            # one duplicated - re-posing would be the same pixels at a cost.
            for _j in seg.join_hold:
                if cancel_requested: return _cancel()
                _write(last, safe)

        if _pipe != null:
            _pipe.close()                           # EOF -> ffmpeg finalizes
            _pipe = null
            while OS.is_process_running(_pid):      # never kill: truncates
                OS.delay_msec(10)
            var code := OS.get_process_exit_code(_pid)
            if code != 0: return _fail("ffmpeg exit %d" % code)

        result = {"ok": true, "frames": frame, "path": _out_path,
                  "error": "", "cancelled": false}
        finished.emit(result)
        return result

    func _write(img: Image, safe: String) -> void:
        if _is_png:
            img.save_png("%s/%s_%04d.png" % [_out_path, safe, frame])
        elif _pipe != null:
            _pipe.store_buffer(img.get_data())
        frame += 1
        progress.emit(frame, total)
        if verbose and frame % 30 == 0:
            print("  %d/%d" % [frame, total])

    ## Shared teardown: every exit path goes through here, so a half-open
    ## encoder can never leak (JobCleanup, zen_export.c:728-744).
    func _cleanup(delete_partial: bool) -> void:
        if _pipe != null:
            _pipe.close()
            _pipe = null
        if _pid >= 0:
            while OS.is_process_running(_pid):
                OS.delay_msec(10)
            _pid = -1
        # A partial PNG folder is NOT deleted: each frame in it is a complete,
        # valid file, and the C leaves them too.
        if delete_partial and not _is_png and _out_path != "" \
           and FileAccess.file_exists(_out_path):
            DirAccess.remove_absolute(_out_path)

    func _fail(msg: String) -> Dictionary:
        _cleanup(true)
        result = {"ok": false, "frames": frame, "path": _out_path,
                  "error": msg, "cancelled": false}
        finished.emit(result)
        return result

    func _cancel() -> Dictionary:
        _cleanup(true)
        result = {"ok": false, "frames": frame, "path": _out_path,
                  "error": "export cancelled", "cancelled": true}
        finished.emit(result)
        return result


## Stop everything that could move a canvas behind the renderer's back.
##
## A frame is a pure function of (scene, t), and two things could break that
## mid-render: the global ZenSignals autoload outlives any one scene and this
## canvas is in the `zen_canvas` group like any other, so a stray emit from
## editor tooling would reach it; and the Godot AnimationPlayer built for live
## F6 playback would keep ticking. Stopping the player is not enough on its own
## - _process would keep re-posing - so the canvas's own per-frame pose goes off
## too, leaving pose_looping() as the ONLY thing that moves this scene.
static func quiesce(canvas: ZenCanvas) -> void:
    var bus := canvas.bus()
    if bus != null: bus.inert = true
    canvas.live_playback = false
    canvas.set_process(false)
    var ap := canvas.animation_player()
    if ap != null and ap.is_playing(): ap.stop()


## Run a single-animation export. `host` must be a Node in the tree (it awaits
## frames). Returns {ok: bool, frames: int, path: String, error: String}.
##
## A one-link chain - there is exactly one encoder loop in this file, and this
## is the convenience door into it.
static func run(host: Node, canvas: ZenCanvas, sub: SubViewport,
                s: Settings, name: String, pauses := []) -> Dictionary:
    var plan := plan_chain([{"canvas": canvas, "sub": sub, "pauses": pauses}],
                           s, false)
    if not bool(plan["ok"]):
        return {"ok": false, "error": String(plan["error"])}
    var job := Job.new()
    job.verbose = true
    return await job.run(host, plan["segments"], s, name)


## One frame: pose, render, read back, orient, cut out, upscale.
static func _frame(host: Node, canvas: ZenCanvas, sub: SubViewport,
                   t: float, w: int, h: int, looping: bool, cut := 0) -> Image:
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
    # Cut out BEFORE the upscale: nearest-neighbour only duplicates pixels, so
    # the result is identical at a fraction of the per-pixel work.
    if cut > 0:
        cutout(img, cut)
    if img.get_size() != Vector2i(w, h):
        img.resize(w, h, Image.INTERPOLATE_NEAREST)
    if img.get_format() != Image.FORMAT_RGBA8:
        img.convert(Image.FORMAT_RGBA8)
    return img
