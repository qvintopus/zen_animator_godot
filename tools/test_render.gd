extends Node
##
## Render tests. Separate from tests/run_tests.gd because these need a real
## display - `--headless` cannot render at all.
##
##   Godot --path . --rendering-driver opengl3 tools/test_render.tscn
##
## Exists because of a bug numeric tests structurally cannot catch: the exporter
## carried raylib's ImageFlipVertical across, but Godot's SubViewport already
## reads back top-down, so every frame came out upside down. The ripple is a
## centred symmetric circle, so it looked perfect; the bug only appeared once
## text was rendered. Orientation needs a pixel, so it is pinned with a pixel.
##

var checks := 0
var fails := 0


func check(cond: bool, what: String) -> void:
    checks += 1
    if not cond:
        fails += 1
        print("FAIL  ", what)


func _ready() -> void:
    DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
    Engine.max_fps = 0
    await test_orientation()
    await test_ball_size()
    await test_loop_seam_pixels()
    await test_crumble_renders()
    await test_ripple_anchors_to_cursor()
    await test_signal_export_purity_pixels()
    print("\n%d render checks, %d failures" % [checks, fails])
    get_tree().quit(1 if fails > 0 else 0)


## An asymmetric probe: a white block in the TOP-LEFT of the canvas must come
## back in the top-left of the captured image.
func test_orientation() -> void:
    var sv := SubViewport.new()
    sv.size = Vector2i(320, 180)
    sv.render_target_update_mode = SubViewport.UPDATE_ONCE
    var bg := ColorRect.new()
    bg.size = Vector2(320, 180)
    bg.color = Color.BLACK
    sv.add_child(bg)
    var mark := ColorRect.new()
    mark.position = Vector2(0, 0)
    mark.size = Vector2(40, 20)
    mark.color = Color.WHITE
    sv.add_child(mark)
    add_child(sv)

    sv.render_target_update_mode = SubViewport.UPDATE_ONCE
    await RenderingServer.frame_post_draw
    var img := sv.get_texture().get_image()

    var top_left := img.get_pixel(10, 5)
    var bottom_left := img.get_pixel(10, 174)
    check(top_left.r > 0.9, "marker is in the TOP-left as drawn (got %s)" % top_left)
    check(bottom_left.r < 0.1, "bottom-left is empty (got %s)" % bottom_left)
    if top_left.r < 0.9:
        print("      -> the capture path is flipping vertically; it must not.")
    sv.queue_free()


## MAIN_MENU's `unit abs` ball must render 5% of the canvas width, not 16 raw
## pixels of a 1280-wide one. Pins the 320x180 canvas through a real render.
func test_ball_size() -> void:
    var canvas: ZenCanvas = (load("res://anims/main_menu.tscn") as PackedScene).instantiate()
    canvas.live_playback = false   # tests pose by hand; no live clock
    var sv := SubViewport.new()
    sv.size = Vector2i(canvas.design_size)
    sv.render_target_update_mode = SubViewport.UPDATE_ONCE
    var bg := ColorRect.new()
    bg.size = canvas.design_size
    bg.color = canvas.clear_color
    sv.add_child(bg)
    sv.add_child(canvas)
    add_child(sv)

    canvas.pose(2.0)
    sv.render_target_update_mode = SubViewport.UPDATE_ONCE
    await RenderingServer.frame_post_draw
    var img := sv.get_texture().get_image()

    # Widest run of yellow on any row.
    var widest := 0
    for y in img.get_height():
        var n := 0
        for x in img.get_width():
            var p := img.get_pixel(x, y)
            if p.r > 0.6 and p.g > 0.6 and p.b < 0.55: n += 1
        widest = maxi(widest, n)
    # 16px authored in a 320 canvas; allow a little for the rim and AA.
    check(widest >= 12 and widest <= 20,
          "ball is ~16px of the 320-wide canvas (got %dpx)" % widest)
    sv.queue_free()


## THE LOOP SEAM, IN PIXELS.
##
## This test exists because the property-level seam test passed while the
## renderer blended nothing at all. Elements read their properties inside
## _draw(), which Godot defers to the frame being rendered - long after
## pose()'s blend window has closed - so the blend was armed for an interval in
## which nothing consulted it. Only a rendered pixel can tell the difference.
##
## A looping render's LAST frame and FIRST frame are shown back to back, so the
## step between them must be no worse than an ordinary adjacent pair.
func test_loop_seam_pixels() -> void:
    var canvas: ZenCanvas = (load("res://anims/main_menu.tscn") as PackedScene).instantiate()
    canvas.live_playback = false   # tests pose by hand; no live clock
    var sv := SubViewport.new()
    sv.size = Vector2i(canvas.design_size)
    sv.render_target_update_mode = SubViewport.UPDATE_ONCE
    var bg := ColorRect.new()
    bg.size = canvas.design_size
    bg.color = Color.BLACK
    sv.add_child(bg)
    sv.add_child(canvas)
    add_child(sv)

    var fps := 30.0
    var start := canvas.play_start()
    var span := canvas.play_end() - start
    var n := int(round(span * fps))

    var t_first := start
    var t_last := start + float(n - 1) / fps
    var t_mid := start + float(n / 2) / fps
    var t_mid_next := start + float(n / 2 + 1) / fps

    var first := await _grab(sv, canvas, t_first, true)
    var last := await _grab(sv, canvas, t_last, true)
    var mid := await _grab(sv, canvas, t_mid, true)
    var mid2 := await _grab(sv, canvas, t_mid_next, true)

    var seam := _mean_diff(last, first)
    var adjacent := _mean_diff(mid, mid2)

    # A blended seam is a single frame step, so it must be the same order of
    # magnitude as any other frame step - not the ~30x jump an unblended wrap
    # produces (measured: 0.587 unblended vs 0.019 blended on main_menu).
    check(seam < 0.12,
          "loop seam is closed (mean channel delta %.4f, adjacent pair %.4f)"
          % [seam, adjacent])

    # And the blend must NOT be flattening the whole animation into stillness -
    # distant frames still have to differ, or "no seam" would be trivially true.
    var far := _mean_diff(first, mid)
    check(far > 0.2, "the animation still moves (first vs mid delta %.4f)" % far)

    # A one-shot shows its authored tail, so its seam stays open: this is what
    # proves the blend is what closed the loop, not some accident of the content.
    var last_shot := await _grab(sv, canvas, t_last, false)
    var open_seam := _mean_diff(last_shot, first)
    check(open_seam > seam * 3.0,
          "one-shot tail is NOT blended (open %.4f vs blended %.4f)"
          % [open_seam, seam])


## Pose at `t` with the blend armed iff `looping`, render, and read back.
func _grab(sv: SubViewport, canvas: ZenCanvas, t: float, looping: bool) -> Image:
    canvas.pose_looping(t, looping)
    sv.render_target_update_mode = SubViewport.UPDATE_ONCE
    await RenderingServer.frame_post_draw
    return sv.get_texture().get_image()


## Mean absolute RGB difference, 0..255 per channel.
func _mean_diff(a: Image, b: Image) -> float:
    var w := a.get_width()
    var h := a.get_height()
    var tot := 0.0
    for y in h:
        for x in w:
            var ca := a.get_pixel(x, y)
            var cb := b.get_pixel(x, y)
            tot += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
    return (tot / float(w * h * 3)) * 255.0


# ---------------------------------------------------------------------------
#  The signal override, IN PIXELS.
#
#  These are not belt-and-braces. Twice now a property-level suite has been
#  fully green while the renderer did nothing - the loop blend was armed for a
#  window in which nothing read it, because elements read their properties
#  inside _draw(), which Godot defers. The signal override has exactly the same
#  shape, and the obvious implementation (prop() asking the bus directly) passes
#  every numeric test while rendering nothing.
#
#  Crumble is also the first code in this project to be rendered at all: only
#  TV-out drives it, so ~35 lines of _draw_crumbled have never executed in a
#  render until now.
# ---------------------------------------------------------------------------

## Build a SubViewport around a scene, ready to pose and grab.
func _stage(path: String, bg: Color) -> Dictionary:
    var canvas: ZenCanvas = (load(path) as PackedScene).instantiate()
    canvas.live_playback = false   # tests pose by hand; no live clock
    var sv := SubViewport.new()
    sv.size = Vector2i(canvas.design_size)
    sv.render_target_update_mode = SubViewport.UPDATE_ONCE
    var rect := ColorRect.new()
    rect.size = canvas.design_size
    rect.color = bg
    sv.add_child(rect)
    sv.add_child(canvas)
    add_child(sv)
    return {"canvas": canvas, "sv": sv}


## Ink statistics over a band of the image: how many pixels carry ink, their
## bounding box, and their total energy. Crumble is a dispersal, so these are
## the observables that separate it from "nothing happened".
func _ink(img: Image, y0: int, y1: int, thresh := 0.25) -> Dictionary:
    var n := 0
    var energy := 0.0
    var sx := 0.0
    var sy := 0.0
    var minx := 1 << 30
    var maxx := -1
    var miny := 1 << 30
    var maxy := -1
    for y in range(y0, mini(y1, img.get_height())):
        for x in img.get_width():
            var lum := _lum(img.get_pixel(x, y))
            if lum > thresh:
                n += 1
                energy += lum
                sx += float(x)
                sy += float(y)
                minx = mini(minx, x)
                maxx = maxi(maxx, x)
                miny = mini(miny, y)
                maxy = maxi(maxy, y)
    var denom := float(maxi(n, 1))
    return {"n": n, "energy": energy,
            "cx": sx / denom, "cy": sy / denom,
            "w": maxi(maxx - minx, 0), "h": maxi(maxy - miny, 0),
            "area": maxi(maxx - minx, 0) * maxi(maxy - miny, 0)}


static func _lum(p: Color) -> float:
    return (p.r + p.g + p.b) / 3.0


## The most common colour in the image, quantised to 5 bits per channel: the
## backdrop, whatever it is and wherever the content happens to sit.
static func _modal_color(img: Image) -> Color:
    var hist := {}
    var best := 0
    var win := Color.BLACK
    for y in img.get_height():
        for x in img.get_width():
            var p := img.get_pixel(x, y)
            var k := (int(p.r * 31.0) << 10) | (int(p.g * 31.0) << 5) | int(p.b * 31.0)
            var c: int = int(hist.get(k, 0)) + 1
            hist[k] = c
            if c > best:
                best = c
                win = p
    return win


## CRUMBLE, RENDERED. MAIN_MENU's TV-out drives `title crumble` to 1.0, and
## nothing else in any document drives crumble at all.
##
## WHAT THE CONTENT ACTUALLY DOES, measured rather than assumed: MAIN_MENU
## authors no `crumble_fx` line, so the defaults apply - direction 90 (straight
## DOWN) in a 12-degree cone, dist 0.5, spin 90. So the glyphs do not scatter
## outward; they slide down together, tumbling, while fading - NOT a growing
## bounding box, which stays unchanged to the pixel because the whole word
## translates as one.
##
## Three INDEPENDENT observables, so a coincidental pass on all of them is
## implausible:
##   - the ink MOVES DOWN by roughly crumble^2 * canvas_h * dist;
##   - total ink ENERGY DROPS, because colour is multiplied by
##     alpha * (1 - crumble) (zen_text.gd:77);
##   - per-glyph SPIN makes the ink non-identical to a pure translation.
## Plus determinism, which is the f(scene,t) guarantee for the glyph-index hash.
func test_crumble_renders() -> void:
    var st := _stage("res://anims/main_menu.tscn", Color.BLACK)
    var canvas: ZenCanvas = st["canvas"]
    var sv: SubViewport = st["sv"]
    await get_tree().process_frame

    var t := 2.0
    canvas.pose(t)
    sv.render_target_update_mode = SubViewport.UPDATE_ONCE
    await RenderingServer.frame_post_draw
    var img0 := sv.get_texture().get_image()
    var before := _ink(img0, 0, img0.get_height())
    check(before["n"] > 50, "the title is drawn before firing (%d px)" % before["n"])

    var bus: ZenSignalBus = canvas.bus()
    check(bus != null and bus.has("TV-out"), "main_menu declares TV-out")
    if bus == null:
        sv.queue_free()
        return

    bus.fire("TV-out")
    # fire() leaves the bus PROCESSING, so its clock would keep advancing on
    # every rendered frame - including the frames this test awaits. A test that
    # steps the clock by hand has to stop the automatic one, or it is measuring
    # a moving target: the determinism check below compared two grabs that were
    # 14ms of signal apart (u 0.3647 vs 0.3695) and called the difference
    # non-determinism.
    bus.set_process(false)
    # Part way in. crumble eases 0 -> 1 with bounceOut, and at crumble = 1 the
    # colour alpha is 0, so a fully crumbled title is INVISIBLE - which would
    # make "the ink moved" vacuously true. Mid-signal keeps it on screen.
    bus.advance(1.1)
    canvas.pose(t)
    sv.render_target_update_mode = SubViewport.UPDATE_ONCE
    await RenderingServer.frame_post_draw
    var img1 := sv.get_texture().get_image()
    var during := _ink(img1, 0, img1.get_height())

    check(during["n"] > 0, "the title is still visible mid-crumble (%d px)" % during["n"])
    check(during["cy"] > before["cy"] + 4.0,
          "crumble moves the ink DOWN (centroid y %.1f -> %.1f)"
          % [before["cy"], during["cy"]])
    check(during["energy"] < before["energy"],
          "crumble FADES the ink (energy %.0f -> %.0f)"
          % [before["energy"], during["energy"]])

    # The glyphs TUMBLE, so the moved ink is not merely the original shifted.
    # Compare against the un-crumbled ink translated by the measured offset: a
    # pure translation would match closely, a tumble must not.
    var dy := int(round(during["cy"] - before["cy"]))
    var same := 0
    var total := 0
    for y in img1.get_height():
        for x in img1.get_width():
            var sy := y - dy
            if sy < 0 or sy >= img0.get_height(): continue
            var a0 := _lum(img0.get_pixel(x, sy)) > 0.25
            var a1 := _lum(img1.get_pixel(x, y)) > 0.25
            if a0 or a1:
                total += 1
                if a0 and a1: same += 1
    # The title sits at y ~29 of 180; reach at crumble 0.76 is ~52px, so every
    # glyph must land within that of its start.
    var band_lo := 0
    var band_hi := int(img1.get_height() * 0.62)
    var overlap := float(same) / float(maxi(total, 1))
    check(overlap < 0.9,
          "glyphs TUMBLE rather than merely translating (overlap %.2f)" % overlap)

    # The scatter must stay NEAR THE TITLE. reach is crumble^2 * design.y *
    # dist, so at crumble 0.76 on a 180px canvas no glyph travels further than
    # ~52px from where it started - the ink cannot leave the upper half.
    #
    # This is the check that was missing, and the gap was not hypothetical:
    # `_draw_glyph` called `draw_set_transform`, which REPLACES the canvas
    # transform rather than composing with it, so it overwrote the placement
    # the crumble path had just set and every glyph was drawn at its raw
    # baseline - the whole title collapsed into one smear in the top-left
    # corner. The three checks above all PASSED on that smear: it is below the
    # original centroid, it is dimmer, and it does not overlap a translation.
    # Only "where did the ink actually go" could see it.
    # Measured on the WHITE text only: the backdrop also carries two teal
    # diagonals and a yellow ball, which move on their own and are not what
    # this is about.
    var far := 0
    var near := 0
    for y in img1.get_height():
        for x in img1.get_width():
            var px := img1.get_pixel(x, y)
            if px.r < 0.6: continue                     # text is near-white
            if absf(px.r - px.g) > 0.16 or absf(px.g - px.b) > 0.16: continue
            if y < band_lo or y > band_hi: far += 1
            else: near += 1
    check(near > 0 and far * 8 < near,
          "crumbled glyphs stay near the title (%d px inside the band, %d outside)"
          % [near, far])

    # WHERE the glyphs end up. This is the check the renderer actually needed:
    #
    # `_draw_glyph` called `draw_set_transform`, which REPLACES the canvas
    # transform rather than composing with it, so it overwrote the placement
    # the crumble path had just set. Every glyph was drawn at its raw baseline
    # and the title collapsed into one overlapping smear in the TOP-LEFT
    # corner. That smear passed every other check here: it is below the
    # original centroid, it is dimmer than the intact title, it does not
    # overlap a pure translation, and it sits inside the band above. Only
    # "which COLUMN is the ink in" separates a scatter from that pile.
    #
    # Deliberately NOT a pixel COUNT. At crumble 0.76 the colour alpha is
    # 1 - 0.76, so the text is nearly faded out and the correct render leaves
    # FEWER bright pixels (62) than the broken one (136), whose stacked glyphs
    # accumulate alpha. Counting would have had the sign backwards.
    var wcx := 0.0
    var wn := 0
    for y in img1.get_height():
        for x in img1.get_width():
            var px2 := img1.get_pixel(x, y)
            if px2.r < 0.6: continue
            if absf(px2.r - px2.g) > 0.16 or absf(px2.g - px2.b) > 0.16: continue
            wcx += float(x)
            wn += 1
    wcx /= float(maxi(wn, 1))
    check(wcx > img1.get_width() * 0.33 and wcx < img1.get_width() * 0.67,
          "the crumbled title stays horizontally centred (text cx %.1f of %d)"
          % [wcx, img1.get_width()])

    # Determinism: a crumbling frame must be renderable OUT OF ORDER, because
    # the exporter builds an explicit frame list and a frame has to be a pure
    # function of (scene, t). The scatter therefore hashes the GLYPH INDEX and
    # never the clock.
    #
    # Two things that look like they'd test determinism here do NOT:
    #
    # 1. Grab twice at an unchanged t with an unrelated pose in between.
    #    Measured on 4.7.2: `queue_redraw()` does not re-execute `_draw()`
    #    before the next capture when nothing the renderer tracks has changed,
    #    so the second grab returns the FIRST frame's bytes regardless of
    #    whether the hash is actually deterministic - structurally incapable
    #    of catching a clock-dependent hash.
    #
    # 2. Re-fire the signal and advance back to the same u. The scatter comes
    #    back identical (same ink count, same energy) but the frame is shifted
    #    ~1.8px, because a fresh fire captures the live - already crumbled -
    #    pose as its new u=0. Correct behaviour; "same u" via a re-fire is
    #    simply not the same frame.
    #
    # What IS the invariant here: two INDEPENDENT canvases, driven to the same
    # signal clock by different routes (one step vs eleven), must render the
    # same bytes. That pins the scatter against path-dependence and against any
    # per-instance state leaking into the glyph positions.
    #
    # Known limit, measured rather than assumed: this cannot catch a hash that
    # reads the clock WITHIN one draw. Injecting `randf() * 180.0` straight
    # into the glyph angle leaves both frames byte-identical, because each
    # viewport executes `_draw()` once and both do so from identical state.
    # Clock-independence of the hash is covered numerically instead (the
    # crumble maths tests), and structurally by the hash taking only `idx`.
    var reference := await _grab_raw(sv)

    var st2 := _stage("res://anims/main_menu.tscn", Color.BLACK)
    var canvas2: ZenCanvas = st2["canvas"]
    var sv2: SubViewport = st2["sv"]
    await get_tree().process_frame
    var bus2: ZenSignalBus = canvas2.bus()
    # POSE BEFORE FIRING. The capture reads `canvas.pose_time`, so a fire on a
    # freshly staged canvas captures the pose at t=0, not at t. That is the
    # whole of what made this check fail: `the_ball` is a TV-out target, and
    # its captured u=0 came from t=0 (pos_y 1.126) on this route and from t=2
    # (pos_y 0.522) on the other, moving the measured centroid ~9px. The
    # crumbling TEXT was byte-identical on every route the entire time.
    canvas2.pose(t)
    bus2.fire("TV-out")
    bus2.set_process(false)
    for i in 11:                            # 1.1s reached in 11 steps, not 1
        bus2.advance(0.1)
    canvas2.pose(t)
    var stepped := await _grab_raw(sv2)

    check(is_equal_approx(bus2.player.clock, bus.player.clock),
          "both routes reached the same signal clock (%.6f vs %.6f)"
          % [bus.player.clock, bus2.player.clock])

    var identical := reference.get_data() == stepped.get_data()
    if not identical:
        var ia := _ink(reference, 0, reference.get_height())
        var ib := _ink(stepped, 0, stepped.get_height())
        print("      one-step: n=%d cy=%.2f energy=%.0f" % [ia["n"], ia["cy"], ia["energy"]])
        print("      stepped : n=%d cy=%.2f energy=%.0f" % [ib["n"], ib["cy"], ib["energy"]])
    check(identical,
          "a crumbling frame is deterministic (same clock, any route -> same bytes)")
    sv2.queue_free()
    sv.queue_free()


func _grab_raw(sv: SubViewport) -> Image:
    sv.render_target_update_mode = SubViewport.UPDATE_ONCE
    await RenderingServer.frame_post_draw
    return sv.get_texture().get_image()


## The ripple must be BORN AT THE CURSOR. mouse_ripple's `ripple` is
## usesPos + posAnchor, so the whole authored path is translated to the emitted
## point - the one signal feature a user sees directly.
##
## Measured properties of this content, which the test has to work with rather
## than around: fill alpha is 0 for the whole document, so the ripple is ONLY a
## ring, about 1.4px thick, in a dark navy (luminance ~0.2) that sits close to
## the scene's own background. So the ink is found by DIFFERENCE from an
## un-fired frame rather than by an absolute luminance threshold, which a first
## version of this test used and which found nothing at all.
func test_ripple_anchors_to_cursor() -> void:
    var st := _stage("res://anims/mouse_ripple.tscn", Color.BLACK)
    var canvas: ZenCanvas = st["canvas"]
    var sv: SubViewport = st["sv"]
    await get_tree().process_frame

    var bus: ZenSignalBus = canvas.bus()
    check(bus != null and bus.has("ripple"), "mouse_ripple declares ripple")
    if bus == null:
        sv.queue_free()
        return

    # A reference frame with the ripple at its AUTHORED centre.
    #
    # t is chosen so the ring FITS INSIDE the canvas: the scale track runs to 10
    # by t=2, and a ring of radius ~100px centred off-centre is clipped by the
    # canvas edges, which drags its measured centroid back toward the middle and
    # makes the anchor look broken when it is not.
    var t := 0.75
    canvas.pose(t)
    var plain := await _grab_raw(sv)
    var authored := _ink_centroid(plain, canvas.design_size)
    check(authored.x > 0.0, "the ripple is drawn at all before firing")

    # Now emit off-centre, in the upper-left quadrant.
    #
    # `ripple` carries replay, so firing REWINDS the document clock to 0 - a
    # click-ripple restarts from nothing and grows at the cursor. At t=0 the
    # shape's scale track reads 0.01, i.e. a sub-pixel dot, so the frame has to
    # be taken once the timeline has run on a little. (A first version posed at
    # the pre-fire t and found no ink, which is the replay working correctly,
    # not the anchor failing.)
    var want := Vector2(0.25, 0.3)
    canvas.pose(t)
    bus.fire("ripple", {"pos": want})
    canvas.pose(t)
    var moved := await _grab_raw(sv)

    var got := _ink_centroid(moved, canvas.design_size)
    check(got.x > 0.0, "the ripple is still drawn after firing")
    check(absf(got.x - want.x) < 0.08,
          "ripple centred on the EMITTED x (%.3f, wanted %.3f)" % [got.x, want.x])
    check(absf(got.y - want.y) < 0.08,
          "ripple centred on the EMITTED y (%.3f, wanted %.3f)" % [got.y, want.y])
    # And emphatically NOT where it was - which is where it would sit if the
    # anchor offset were dropped, with every property-level test still green.
    check(absf(got.x - authored.x) > 0.1,
          "and it MOVED from its authored centre (%.3f -> %.3f)" % [authored.x, got.x])
    sv.queue_free()


## Centroid of the ripple's ink in canvas FRACTIONS, or (-1,-1) if none found.
##
## The ring is thin, antialiased and close in luminance to the backdrop, so the
## ink is whatever differs from the frame's own modal (background) colour rather
## than whatever exceeds a fixed brightness.
func _ink_centroid(img: Image, design: Vector2) -> Vector2:
    # The MODAL colour, not a corner sample: at scale 4+ the ring is ~68px in
    # radius and runs off the canvas, so a fixed corner pixel can land on the
    # ring itself and define the ink away as background.
    var bg := _modal_color(img)
    var sx := 0.0
    var sy := 0.0
    var n := 0
    for y in img.get_height():
        for x in img.get_width():
            var p := img.get_pixel(x, y)
            var d := absf(p.r - bg.r) + absf(p.g - bg.g) + absf(p.b - bg.b)
            if d > 0.06:
                sx += float(x)
                sy += float(y)
                n += 1
    if n < 10: return Vector2(-1, -1)
    return Vector2((sx / float(n)) / design.x, (sy / float(n)) / design.y)


## EXPORT PURITY with a bus present. A frame must stay a pure function of
## (scene, t): same t, same bytes, regardless of what was rendered in between
## and regardless of the global ZenSignals autoload being alive. A clock or a
## signal ticking during the capture await would re-pose the canvas and every
## frame would come out identical - so this is asserted, not assumed.
func test_signal_export_purity_pixels() -> void:
    var st := _stage("res://anims/main_menu.tscn", Color.BLACK)
    var canvas: ZenCanvas = st["canvas"]
    var sv: SubViewport = st["sv"]
    await get_tree().process_frame

    var t := 1.7
    canvas.pose(t)
    var a := await _grab_raw(sv)
    canvas.pose(0.3)
    var _unrelated := await _grab_raw(sv)
    canvas.pose(t)
    var b := await _grab_raw(sv)
    check(a.get_data() == b.get_data(), "pose(t) renders identically across other poses")

    # An INERT bus must change nothing about a render.
    var bus: ZenSignalBus = canvas.bus()
    bus.inert = true
    canvas.pose(t)
    var c := await _grab_raw(sv)
    check(a.get_data() == c.get_data(), "an inert bus does not alter the frame")

    # And an inert bus cannot be fired, so the frame is still unchanged.
    check(not bus.fire("TV-out"), "an inert bus refuses to fire")
    canvas.pose(t)
    var d := await _grab_raw(sv)
    check(a.get_data() == d.get_data(), "a refused fire leaves the frame untouched")
    sv.queue_free()
