extends SceneTree
##
## Plain SceneTree test runner - no GUT dependency, matching the source
## project's "tests stay small and focused" convention.
##
##   Godot --headless --path . --script res://tests/run_tests.gd
##
## Headless is fine here: nothing in these tests renders.
##

var checks := 0
var fails := 0


func check(cond: bool, what: String) -> void:
    checks += 1
    if not cond:
        fails += 1
        print("FAIL  ", what)


func check_near(a: float, b: float, what: String, eps := 0.0001) -> void:
    checks += 1
    if absf(a - b) > eps:
        fails += 1
        print("FAIL  %s: got %.6f want %.6f (d=%.6f)" % [what, a, b, absf(a - b)])


func _init() -> void:
    _run()


## Async because two tests need a processed frame: in a SceneTree script
## add_child() DEFERS _enter_tree and _ready to the next frame, so a canvas is
## not in the `zen_canvas` group until one has passed. That is a property of
## this harness, not of the runtime - a real game adds nodes during a frame.
func _run() -> void:
    test_easing_against_godot()
    test_custom_curve()
    test_export_plan()
    test_easing_set()
    test_text_layout()
    test_crumble_hash()
    test_canvas_size()
    test_resolution_presets()
    test_blend_weight()
    test_trim_clamp()
    test_loop_seam_closes()
    test_seam_open_without_blend()
    test_stepped_never_blends()
    test_anim_player_tracks()
    test_anim_player_roundtrip()
    test_bake_accuracy()
    test_signal_capture_segment()
    await test_release_pause_keeps_section()
    await test_canvas_clock()
    test_canvas_pauses()
    test_pause_across_wrap()
    test_export_pause_source()
    await test_canvas_idle_until_played()
    test_scenes_inert()
    test_export_pause_holds()
    test_chain_frame_plan()
    test_chain_rejects_size_mismatch()
    test_single_link_plan_matches_legacy()
    test_estimate_bytes_shape()
    test_cutout_snaps_alpha()
    test_ffmpeg_args_per_format()
    await test_job_cancel_png()
    test_signal_u_normalization()
    test_signal_no_start()
    test_signal_seq_offset()
    test_signal_override_order()
    test_signal_replaces_loop_blend()
    test_signal_never_touches_stepped()
    test_signal_offset_without_target()
    test_signal_color_keeps_track_alpha()
    test_signal_no_compounding()
    test_signal_pos_anchor_translates()
    test_signal_pos_param_replaces()
    test_signal_pos_param_outranks_target()
    test_signal_pointer_fill()
    test_signal_follow_tracks_pointer()
    test_signal_follow_superseded()
    test_signal_trigger_press_release()
    test_signal_trigger_end_oneshot()
    test_signal_trigger_end_every_loop()
    test_signal_then_chain()
    test_signal_chain_carries_pose()
    test_signal_demos()
    test_signal_normalize_legacy()
    test_signal_bake_no_pos_offset()
    test_signal_ops_add_rename_remove()
    test_signal_edit_anim_keyops()
    test_signal_terminal_edge()
    test_signal_terminal_holds_end_pose()
    test_signal_pack_roundtrip()
    await test_signal_autoload_relay()
    await test_signal_autoload_respects_inert()
    test_signal_autoload_registered()
    test_signal_bases_match_draw()
    test_signal_captures_posed_time()
    test_signal_unknown_element()
    test_scene_signals_present()
    test_signal_export_purity()
    await test_anim_player_plays()
    test_anim_player_markers()
    test_input_actions_declared()
    await test_section_loops_into_body()
    test_seek_stays_in_section()
    await test_loop_play_separate_from_smooth()
    await test_viewer_intro_loop_toggles()
    test_pixel_shape()
    test_custom_shape_resolution()
    test_element_hit()
    test_stage_view()
    test_help_pages()
    test_options_font_sort_filter()
    test_raylib_font()
    test_list_selection()
    await test_gallery_multi_select()
    test_scene_folders()
    await test_gallery_folders()
    await test_gallery_actions()
    await test_shape_editor()
    test_zen_settings()
    test_export_dialog_preview()
    test_ease_tracks()
    test_key_ops_rebake()
    test_key_ops_raw_segments()
    test_key_ops_color_and_stepped()
    test_key_set_times()
    test_key_set_times_keeps_raw()
    test_elem_ops()
    test_doc_ops()
    test_scene_ops_roundtrip()
    test_clip_ops()
    test_clip_map()
    test_doc_retime_trim()
    test_string_pool_scenes()
    test_string_ops()
    test_string_pool_shared()
    await test_scene_editor()
    await test_scene_editor_strings()
    await test_scene_editor_effects()
    await test_canvas_game_api()
    test_godot_export_rewrite()
    test_godot_export_vendor_source()
    test_godot_export_validate()
    test_godot_export_files()
    print("\n%d checks, %d failures" % [checks, fails])
    quit(1 if fails > 0 else 0)


## Signal key times are NORMALIZED u (0..1 of `length`), not seconds. Tested
## with a length that makes the confusion obvious: at t=1.5s of a 3.03s signal
## u is ~0.495, whereas reading the keys as seconds would give a wildly
## different answer.
func test_signal_u_normalization() -> void:
    var p := ZenSignalPlayer.new()
    var sig := {"name": "T", "length": 3.031496, "terminal": false,
                "uses_pos": false, "pos_anchor": false, "replay": false,
                "targets": [{"elem": "a", "prop": "alpha",
                             "keys": [{"t": 1.0, "v": 1.0, "ease": "linear"}]}],
                "pos_params": [], "seq_mult": 0.0, "uses_seq": false,
                "seq_targets": [], "seq_keys": []}
    var cap := func(_e: String, _pr: String) -> Variant: return 0.0
    _start(p, sig, {}, 0, cap)
    check(p.playing, "signal with a target plays")
    check_near(p.u(), 0.0, "u starts at 0")
    p.update(1.5157)
    check_near(p.u(), 0.5, "u is clock/length, not seconds", 0.001)
    check_near(float(p.eval("a", "alpha")), 0.5, "eval at u=0.5 is half way", 0.001)

    # The clock REACHING length ends it, and u clamps at 1.
    p.update(10.0)
    check(p.is_done(), "signal ends when the clock reaches length")
    check_near(p.u(), 1.0, "u clamps at 1")

    # length <= 0 is INSTANT: u snaps to the final key immediately.
    var inst := sig.duplicate(true)
    inst["length"] = 0.0
    var q := ZenSignalPlayer.new()
    _start(q, inst, {}, 0, cap)
    check_near(q.u(), 1.0, "length=0 snaps u to 1")
    check_near(float(q.eval("a", "alpha")), 1.0, "length=0 lands on the final key")
    q.update(0.016)
    check(q.is_done(), "length=0 is done on its first update")


## A signal driving NOTHING must not start (anim.c:1505-1507). mouse_ripple's
## `enter` signal is exactly this, and a player that "ran" would install an
## override that drives no property while still blocking the loop blend.
func test_signal_no_start() -> void:
    var empty := ZenSignalData.defaults("enter")
    var p := ZenSignalPlayer.new()
    _start(p, empty, {}, 0, func(_e, _pr): return 0.0)
    check(not p.playing, "a signal with no targets/point elems/seqtargets never starts")
    check(p.is_done(), "and reports done immediately")
    check(p.eval("shape", "pos_x") == null, "an unstarted signal drives nothing")

    # But point bindings ALONE, or seqtargets ALONE, are enough to play.
    var only_pos: Dictionary = empty.duplicate(true)
    only_pos["point"] = "anchor"
    only_pos["point_elems"] = [{"elem": "shape", "off": Vector2.ZERO}]
    var q := ZenSignalPlayer.new()
    _start(q, only_pos, {"pos": Vector2(0.5, 0.5)}, 0, func(_e, _pr): return 0.0)
    check(q.playing, "point bindings alone are enough to start")
    # ...but not when point is "none": the bindings are then inert data.
    only_pos["point"] = "none"
    var q2 := ZenSignalPlayer.new()
    _start(q2, only_pos, {}, 0, func(_e, _pr): return 0.0)
    check(not q2.playing, "point bindings with point=none do not start a signal")

    var only_seq: Dictionary = empty.duplicate(true)
    only_seq["seq_targets"] = [{"elem": "shape", "prop": "scale"}]
    var r := ZenSignalPlayer.new()
    _start(r, only_seq, {}, 0, func(_e, _pr): return 0.0)
    check(r.playing, "seqtargets alone are enough to start")


## seq offset = seq * seq_mult * env(u), and every gate that zeroes it.
func test_signal_seq_offset() -> void:
    var sig := {"name": "s", "length": 2.0, "uses_pos": false, "pos_anchor": false,
                "targets": [], "pos_params": [], "uses_seq": true, "seq_mult": 0.5,
                "seq_targets": [{"elem": "shape", "prop": "scale"}],
                "seq_keys": [{"t": 1.0, "v": 1.0, "ease": "linear"}]}
    var cap := func(_e, _pr): return 0.0

    var p := ZenSignalPlayer.new()
    _start(p, sig, {}, 3, cap)
    check_near(p.seq_offset("shape", "scale"), 0.0, "seq env starts at 0")
    p.update(1.0)
    check_near(p.seq_offset("shape", "scale"), 3.0 * 0.5 * 0.5, "seq = seq*mult*env(u)")
    check_near(p.seq_offset("shape", "pos_x"), 0.0, "seq only hits its seqtargets")
    check_near(p.seq_offset("other", "scale"), 0.0, "seq only hits its element")

    # seq 0 means "not sequenced" and must contribute nothing at all.
    var q := ZenSignalPlayer.new()
    _start(q, sig, {}, 0, cap)
    q.update(1.0)
    check_near(q.seq_offset("shape", "scale"), 0.0, "seq index 0 contributes nothing")

    # No env keys: a CONSTANT full offset, not zero.
    var flat: Dictionary = sig.duplicate(true)
    flat["seq_keys"] = []
    var r := ZenSignalPlayer.new()
    _start(r, flat, {}, 2, cap)
    check_near(r.seq_offset("shape", "scale"), 1.0, "no env keys = constant full offset")


## Every built-in must match the generated reference, which comes from GODOT's
## Tween family (see zen_easing.gd for why Godot owns these curves, and what
## that changed). Regenerate with tools/gen_ease_ref.gd. The raylib curves and
## Godot's differ on bounce/elastic/circ/back; a failure here means the easing
## TABLE drifted, not that the port is unfaithful to raylib.
func test_easing_against_godot() -> void:
    var ps := [0.0, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0]
    var f := FileAccess.open("res://tests/ease_ref.txt", FileAccess.READ)
    check(f != null, "ease_ref.txt present")
    if f == null: return
    var rows := 0
    while not f.eof_reached():
        var line := f.get_line().strip_edges()
        if line.is_empty() or line.begins_with("#"): continue
        var tok := line.split(" ", false)
        var nm := tok[0]
        for i in ps.size():
            check_near(ZenEasing.apply(nm, ps[i]), float(tok[i + 1]),
                       "%s(%.2f)" % [nm, ps[i]], 0.0005)
        rows += 1
    check(rows == ZenEasing.GODOT_EASE.size(),
          "every built-in easing compared (%d of %d)"
          % [rows, ZenEasing.GODOT_EASE.size()])
    # linear is identity
    check_near(ZenEasing.apply("linear", 0.37), 0.37, "linear identity")
    # unknown name degrades to linear, never errors (AnimEaseByName semantics)
    check_near(ZenEasing.apply("no_such_ease", 0.42), 0.42, "unknown -> linear")

    # Endpoints. p=0 must be exactly 0 for every curve; p=1 is exact for all
    # but expo, where Godot's formulation reaches 0.999 (measured, not a bug
    # here - it leaves pause_menu's slide-in 0.07px short on a 320px canvas,
    # which the next key corrects).
    for nm3 in ZenEasing.GODOT_EASE:
        check_near(ZenEasing.apply(nm3, 0.0), 0.0, "%s(0) == 0" % nm3, 1e-6)
        var tol := 0.0011 if nm3.begins_with("expo") else 1e-6
        check_near(ZenEasing.apply(nm3, 1.0), 1.0, "%s(1) == 1" % nm3, tol)

    # A custom curve must SHADOW a built-in of the same name, so a document can
    # redefine a stock curve without the engine's name becoming unusable.
    var shadow := ZenCurve.new()
    shadow.knots = [PackedFloat32Array([0,0,0,0,0,0]),
                    PackedFloat32Array([1,1,0,0,0,0])]
    ZenEasing.register_custom("bounceOut", shadow)
    check_near(ZenEasing.apply("bounceOut", 0.5), 0.5,
               "a custom curve shadows the built-in of the same name", 0.01)
    ZenEasing.clear_custom()
    check_near(ZenEasing.apply("bounceOut", 0.5), 0.765625,
               "clearing customs restores the built-in", 0.0005)


## Custom curves: endpoints exact, overshoot preserved, hold steps honoured.
func test_custom_curve() -> void:
    # bop_n_up from assets/easings.tres - has a hold step (two knots at
    # x=0.284375) and overshoots to y=1.5.
    var c := ZenCurve.new()
    c.knots = [PackedFloat32Array([0, 0, 0, 0, 0.06875, 1.5]),
               PackedFloat32Array([0.284375, 0.6, -0.1625, 1.275, 0.1625, -1.275]),
               PackedFloat32Array([0.284375, 0.3, -0.107344, 0, 0.107344, 0]),
               PackedFloat32Array([1, 1, -0.25, -0.25, 0, 0])]
    check_near(c.sample(0.0), 0.0, "custom p=0 -> first knot y")
    check_near(c.sample(1.0), 1.0, "custom p=1 -> last knot y")
    # Between the two coincident knots the curve must not explode.
    var mid := c.sample(0.284375)
    check(mid >= -1.0 and mid <= 2.0, "hold step stays bounded (got %.3f)" % mid)
    # Monotonic x-solve: sampling must be finite everywhere.
    for i in 101:
        var v := c.sample(float(i) / 100.0)
        check(is_finite(v), "custom finite at p=%.2f" % (float(i) / 100.0))


## Export frame planning: the outro is always trimmed, the intro is optional,
## and pause markers become durations (zen_export.c:296-340).
func test_export_plan() -> void:
    var c := ZenCanvas.new()
    c.duration = 3.3455
    c.intro_end = 0.619826
    c.outro_start = 3.210659

    var s := ZenExport.Settings.new()
    s.fps = 10
    s.pause_hold = 0.0

    # Loop render: starts at intro_end, ends at outro_start. The trimmed
    # outro (3.2107..3.3455) must never be sampled.
    s.show_intro = false
    var loop := ZenExport.frame_times(c, s, [])
    check(loop.size() > 0, "loop plan non-empty")
    check_near(loop[0], c.intro_end, "loop starts at intro_end", 0.001)
    check(loop[loop.size() - 1] < c.outro_start, "loop never reaches outro_start")
    check(loop[loop.size() - 1] < c.duration - 0.1, "outro is trimmed")
    check(loop.size() == 26, "loop frame count = round(span*fps) (got %d)" % loop.size())

    # One-shot render: starts at 0, same end.
    s.show_intro = true
    var shot := ZenExport.frame_times(c, s, [])
    check_near(shot[0], 0.0, "intro render starts at 0")
    check(shot.size() > loop.size(), "intro render is longer than the loop")

    # A pause marker inside the range freezes for pause_hold seconds.
    s.show_intro = false
    s.pause_hold = 1.0                      # 10 extra frames at 10fps
    var held := ZenExport.frame_times(c, s, [1.5])
    check(held.size() == loop.size() + 10, "pause adds hold frames (got %d vs %d)"
          % [held.size(), loop.size() + 10])
    # A marker outside [start, end) is ignored - including one in the trimmed
    # outro, which no longer plays.
    var outside := ZenExport.frame_times(c, s, [3.3])
    check(outside.size() == loop.size(), "marker in trimmed outro ignored")

    # fps caps: GIF delays are centiseconds, so 60 is the ceiling.
    check(ZenExport.max_fps("gif") == 60, "gif fps cap")
    check(ZenExport.max_fps("webm") == 120, "video fps cap")

    # Names reach a command line.
    check(ZenExport.sanitize("my anim; rm -rf") == "my_anim__rm_-rf", "name sanitized")


## The project's custom easings (assets/easings.tres) load, register by name
## and evaluate.
func test_easing_set() -> void:
    var es := load(ZenEasingSet.PATH) as ZenEasingSet
    check(es != null and es.curves.size() == 7, "7 custom easings (%d)" % (es.curves.size() if es else 0))
    if es == null: return
    for n in es.curves:
        var c: ZenCurve = es.curves[n]
        check(c.knots.size() >= 2, "%s has knots" % n)
        check_near(c.sample(0.0), c.knots[0][1], "%s starts at its first knot" % n)
        for i in 21:
            check(is_finite(c.sample(float(i) / 20.0)), "%s finite" % n)
    ZenEasing.clear_custom()
    ZenEasingSet.load_project()
    check(ZenEasing.custom_names().size() == 7 and ZenEasing.has("bop_n_up"),
          "the project's custom easings register")
    check_near(ZenEasing.apply("bop_n_up", 0.0), 0.0, "...and bop_n_up evaluates")
    ZenEasing.clear_custom()


## Text layout against a real Godot font. Property-based rather than pinned to
## magic numbers, so it survives a font swap (unlike the old raylib-table
## comparison this replaces - see docs/plans/godot-integration.md Task 2).
func test_text_layout() -> void:
    var fnt := ZenText.default_font()

    check(ZenTextMetrics.measure("", 32.0, fnt) == Vector2.ZERO,
          "empty text measures zero - raylib's early-out, still right")

    check_near(ZenTextMetrics.measure("A", 72.0, fnt).y, 72.0,
                "single line height is exactly size_px")
    # THE \n REGRESSION GUARD: Font.get_string_size() ignores "\n" entirely
    # (measured on 4.7.2) - a naive drop-in would report one line's height.
    check_near(ZenTextMetrics.measure("two\nlines", 72.0, fnt).y,
                2.0 * 72.0 + ZenTextMetrics.LINE_SPACING,
                "two lines measure 2*size_px + LINE_SPACING, not one line's height")

    var two := ZenTextMetrics.measure("two", 40.0, fnt)
    var lines := ZenTextMetrics.measure("lines", 40.0, fnt)
    var both := ZenTextMetrics.measure("two\nlines", 40.0, fnt)
    check_near(both.x, maxf(two.x, lines.x), "block width is the widest LINE, not the sum")

    check(ZenTextMetrics.measure("MM", 40.0, fnt).x > ZenTextMetrics.measure("ii", 40.0, fnt).x,
          "proportional metrics are actually in use (M is wider than i)")

    check_near(ZenTextMetrics.spacing_for(72.0), 7.2, "spacing = size/baseSize")

    # The centring invariant: a ZenText at pos_frac (0.5,0.5) on a 320x180
    # canvas centres on (160,90) - calling the SAME center_px() _draw() calls,
    # per the project's own "a test that calls the renderer's function is not
    # the same as a test that looks at a pixel" lesson, applied the other way:
    # here the function IS what's under test, so calling it directly is right.
    var c := ZenCanvas.new()
    c.design_size = Vector2(320, 180)
    var tx := ZenText.new()
    tx.set_script(load("res://addons/zen/runtime/zen_text.gd"))
    tx.elem_name = "t"
    tx.pos_frac = Vector2(0.5, 0.5)
    c.add_child(tx)
    check(tx.center_px(0.0).is_equal_approx(Vector2(160, 90)),
          "pos_frac (0.5,0.5) centres on the canvas midpoint")

    # One-way mirror: pose() writes the resolved centre into Node2D.position so
    # game code can read where the element is.
    tx.pos_frac = Vector2(0.25, 0.5)
    tx.pose(0.0)
    check(tx.position.is_equal_approx(Vector2(80, 90)),
          "pose() mirrors the resolved centre into Node2D.position")
    c.free()


## Crumble scatter must hash the GLYPH INDEX, never the clock - that is what
## keeps a frame a pure function of (scene, t) for the exporter.
func test_crumble_hash() -> void:
    for seed in [0, 1, 977, 12345]:
        var a := ZenText.rand11i(seed)
        var b := ZenText.rand11i(seed)
        check(a == b, "rand11i(%d) is stable" % seed)
        check(a >= -1.0 and a <= 1.0, "rand11i(%d) in [-1,1] (got %f)" % [seed, a])
    # Different seeds must actually differ, or the scatter would be a uniform
    # translation instead of a cone.
    check(ZenText.rand11i(0) != ZenText.rand11i(1), "seeds differ")
    # The angle hash is offset by 977 from the spin hash so tumble cannot
    # predict direction; those two series must not coincide.
    var same := 0
    for i in 50:
        if is_equal_approx(ZenText.rand11i(i), ZenText.rand11i(i + 977)): same += 1
    check(same == 0, "spin and angle hashes are independent (%d collisions)" % same)


## The design canvas is 320x180, NOT 1280x720.
##
## Zen's canvas is ScreenStateTargetSize() = 1920/6 x 1080/6 (screen_state.c:23),
## and `unit abs` sizes are pixels IN THAT SPACE. Getting it wrong shrinks every
## absolute-unit element by 4x while leaving fractional ones correct - which is
## invisible in a numeric test of fractions and only shows up on screen. It cost
## a render to find once; this pins it.
## Canvas presets and named export sizes: every preset reaches 1080p at a
## whole-number scale, the names follow the SHORT side, a new scene takes the
## saved default, and a resized scene saves, reloads, and keeps its layout.
func test_resolution_presets() -> void:
    check(ZenSettings.MAX_SCALE == ZenExport.MAX_SCALE, "settings mirror the exporter's MAX_SCALE")
    var named := func(d: Vector2) -> Dictionary:
        var out := {}
        for o in ZenExport.scale_options(d):
            if String(o["name"]) != "": out[String(o["name"])] = int(o["scale"])
        return out
    var n320: Dictionary = named.call(Vector2(320, 180))
    check(n320 == {"360p": 2, "720p": 4, "1080p": 6, "1440p": 8, "4K": 12},
          "320x180 names its scales (%s)" % n320)
    check(int(named.call(Vector2(180, 320)).get("1080p", 0)) == 6, "a vertical canvas names by its short side")
    var n480: Dictionary = named.call(Vector2(480, 270))
    check(int(n480.get("1080p", 0)) == 4 and not n480.has("720p"), "480x270 reaches 1080p but not 720p")
    for p in ZenCanvas.SIZE_PRESETS:
        check(ZenExport.scale_for_target(p["size"], 1080) > 0, "%s reaches 1080p" % p["label"])
    check(ZenCanvas.preset_index(ZenCanvas.DEFAULT_SIZE) == 0, "the default size is the first preset")
    check(ZenCanvas.preset_index(Vector2(321, 180)) == -1, "an unlisted size is no preset")
    check(ZenExport.scale_for_target(Vector2(480, 270), 720) == 0, "no whole scale -> 0")
    check(ZenExport.parse_target("1080p") == 1080 and ZenExport.parse_target("1440") == 1440
          and ZenExport.parse_target("4k") == 2160 and ZenExport.parse_target("big") == 0,
          "--res values parse")

    var orig_size := ZenSettings.canvas_size()
    var orig_target := ZenSettings.export_target()
    ZenSettings.set_canvas_size(Vector2(123, 45))
    check(ZenSettings.canvas_size() == ZenCanvas.DEFAULT_SIZE, "a non-preset saved size falls back")
    ZenSettings.set_canvas_size(Vector2(640, 360))
    var nm := "zz_test_res"
    var c := ZenSceneOps.new_canvas(nm)
    check(c.design_size == Vector2(640, 360), "a new scene takes the saved canvas size")
    var title := ZenElemOps.find(c, "title")
    var frac := title.center_px(0.0) / c.design_size
    var path := ZenSceneOps.save(c, nm)
    var o := ZenSceneOps.open(path)
    check(o.design_size == Vector2(640, 360), "the canvas size survives save/open")
    o.design_size = Vector2(960, 540)
    var ot := ZenElemOps.find(o, "title")
    check((ot.center_px(0.0) / o.design_size).is_equal_approx(frac),
          "same aspect: fractional geometry keeps its place")
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    for x in [c, o]: x.free()
    ZenSettings.set_export_target(1080)
    check(ZenSettings.export_target() == 1080, "the export target round-trips")
    ZenSettings.set_canvas_size(orig_size)
    ZenSettings.set_export_target(orig_target)


func test_canvas_size() -> void:
    var c := ZenCanvas.new()
    check(c.design_size == Vector2(320, 180),
          "default canvas is 320x180 (got %s)" % c.design_size)

    # Every bundled scene must agree.
    for nm in ["main_menu", "pause_menu", "mouse_ripple", "zooming_box", "game_start"]:
        var path := "res://anims/%s.tscn" % nm
        if not ResourceLoader.exists(path): continue
        var canvas: ZenCanvas = (load(path) as PackedScene).instantiate()
        canvas.live_playback = false   # tests pose by hand; no live clock
        check(canvas.design_size == Vector2(320, 180),
              "%s canvas is 320x180 (got %s)" % [nm, canvas.design_size])

    # MAIN_MENU's ball: `unit abs` size 16 means 16 px of a 320-wide canvas, so
    # it is 5% of the width and lands at 64px in a 1280-wide render. The
    # reference render measures 56px of solid yellow (the rest is the rim).
    var mm: ZenCanvas = (load("res://anims/main_menu.tscn") as PackedScene).instantiate()
    mm.live_playback = false   # tests pose by hand; no live clock
    var ball: ZenShape = null
    for e in mm.elements():
        var sh := e as ZenShape
        if sh != null and sh.elem_name == "the_ball": ball = sh
    check(ball != null, "the_ball present")
    if ball != null:
        check(ball.unit_abs, "the_ball is unit abs")
        check_near(ball.size_frac.x, 16.0, "the_ball authored at 16px")
        # width on screen at scale 4 = 16 (abs px) * 4
        check_near(16.0 * 4.0, 64.0, "16px x scale 4 = 64px rendered")
        # and as a fraction of the canvas it is 5%
        check_near(ball.size_frac.x / mm.design_size.x, 0.05, "ball spans 5% of width")


# ---------------------------------------------------------------------------
#  Intro/loop/outro trim, smooth-loop blend, pause markers.
# ---------------------------------------------------------------------------

## The blend weight itself: 0 outside the window, smoothstep inside, exactly 1
## at the loop end (anim.c:507-516).
func test_blend_weight() -> void:
    var c := ZenCanvas.new()
    c.duration = 4.0
    c.intro_end = 1.0
    c.outro_start = 3.0
    c.loop_blend = 0.5
    c.loop_smooth = true

    ZenElement.blend_begin(c, true)
    # Window is the last 0.5s of the cycle [1,3) -> (2.5, 3].
    check_near(ZenElement.blend_weight(1.0), 0.0, "w=0 at loop start")
    check_near(ZenElement.blend_weight(2.5), 0.0, "w=0 at window open (closed)")
    check_near(ZenElement.blend_weight(2.75), 0.5, "w=0.5 at window midpoint")
    check_near(ZenElement.blend_weight(3.0), 1.0, "w=1 at loop end")
    # Smoothstep, not linear: a quarter in must be well under 0.25.
    check_near(ZenElement.blend_weight(2.625), 0.15625, "smoothstep at p=0.25")
    # Past the end clamps rather than overshooting.
    check_near(ZenElement.blend_weight(3.5), 1.0, "w clamps past loop end")
    ZenElement.blend_end()

    # Disarmed: a one-shot shows its authored tail, so the weight is dead.
    ZenElement.blend_begin(c, false)
    check_near(ZenElement.blend_weight(3.0), 0.0, "one-shot never blends")
    ZenElement.blend_end()

    # loop_smooth off is a hard restart (a strobe or hard cut may want it).
    c.loop_smooth = false
    ZenElement.blend_begin(c, true)
    check_near(ZenElement.blend_weight(3.0), 0.0, "loop_smooth off never blends")
    ZenElement.blend_end()

    # The blend can never eat more than the cycle it belongs to.
    c.loop_smooth = true
    c.loop_blend = 99.0
    ZenElement.blend_begin(c, true)
    check_near(ZenElement.blend_weight(1.0), 0.0, "clamped blend starts at cycle start")
    check_near(ZenElement.blend_weight(3.0), 1.0, "clamped blend still ends at 1")
    ZenElement.blend_end()
    # And it must be torn down, or a later one-shot render inherits it.
    check_near(ZenElement.blend_weight(3.0), 0.0, "blend_end disarms")


## Canvas trim accessors clamp exactly as AnimDocIntroEnd/OutroStart do
## (anim.c:1099-1122).
func test_trim_clamp() -> void:
    var c := ZenCanvas.new()
    c.duration = 5.0

    # outro_start <= 0 is "unset" -> play the whole clock.
    c.outro_start = 0.0
    check_near(c.play_end(), 5.0, "unset outro -> duration")

    # ...and an outro past the duration clamps to it.
    c.outro_start = 9.0
    check_near(c.play_end(), 5.0, "outro clamps to duration")

    # An intro past the outro clamps, so the cycle is never inverted.
    c.outro_start = 2.0
    c.intro_end = 4.0
    check_near(c.play_start(), 2.0, "intro clamps to outro")
    check(c.cycle_length() > 0.0, "cycle length never negative")

    c.intro_end = -1.0
    check_near(c.play_start(), 0.0, "negative intro clamps to 0")

    c.intro_end = 0.0
    check(not c.has_intro(), "no intro -> has_intro false")
    c.intro_end = 0.5
    check(c.has_intro(), "intro -> has_intro true")


## THE SEAM. The whole point of the blend: at the loop end every property must
## already equal its value at the loop start, so the wrap is invisible.
##
## Driven off ZenProps rather than a hand-written list, which is the plan's
## risk 4 - a property missing from the table would otherwise stop animating
## (or stop blending) with nothing to notice it.
func test_loop_seam_closes() -> void:
    for nm in ["main_menu", "pause_menu", "mouse_ripple", "zooming_box", "game_start"]:
        var path := "res://anims/%s.tscn" % nm
        if not ResourceLoader.exists(path): continue
        var canvas: ZenCanvas = (load(path) as PackedScene).instantiate()
        canvas.live_playback = false   # tests pose by hand; no live clock
        canvas.loop_smooth = true
        if canvas.loop_blend <= 0.0: canvas.loop_blend = 0.3

        var t_end := canvas.play_end()
        var t_start := canvas.play_start()

        # Pose THROUGH THE CANVAS, exactly as a render does, and read the
        # properties AFTER the blend window has closed. Reading them inside the
        # window (the obvious way to write this) passes even when the renderer
        # blends nothing, because _draw() runs later than pose() - that is the
        # bug this shape of test exists to catch.
        canvas.pose_looping(t_end, true)
        for e in canvas.elements():
            var el := e as ZenElement
            var kind := "text" if el is ZenText else (
                "global" if el is ZenGlobal else "shape")

            for prop_name in ZenProps.scalars_for(kind):
                if ZenProps.is_stepped(prop_name): continue
                if not el.has_track(prop_name): continue
                var at_end := el.prop(prop_name, t_end, 0.0)
                var at_start := el.track_or_base(prop_name, t_start, 0.0)
                # at_end must carry the blend; at_start is the raw loop-start
                # pose the blend is aiming at.
                check_near(at_end, at_start,
                    "%s/%s.%s seam closes" % [nm, el.elem_name, prop_name], 0.0005)

            for prop_name in ZenProps.colors_for(kind):
                if not el.has_track(prop_name): continue
                var ce := el.prop_color(prop_name, t_end, Color.WHITE, 1.0)
                var cs := el.track_or_base_color(prop_name, t_start, Color.WHITE, 1.0)
                # RGB only - alpha rides its own scalar track and is asserted
                # above, so it must NOT have been touched here.
                check_near(ce.r, cs.r, "%s/%s.%s seam r" % [nm, el.elem_name, prop_name], 0.005)
                check_near(ce.g, cs.g, "%s/%s.%s seam g" % [nm, el.elem_name, prop_name], 0.005)
                check_near(ce.b, cs.b, "%s/%s.%s seam b" % [nm, el.elem_name, prop_name], 0.005)
        canvas.free()


## Without the blend the seam is genuinely open - otherwise the test above
## proves nothing. MAIN_MENU is the case the README called out as jumping.
func test_seam_open_without_blend() -> void:
    var canvas: ZenCanvas = (load("res://anims/main_menu.tscn") as PackedScene).instantiate()
    canvas.live_playback = false   # tests pose by hand; no live clock
    var t_end := canvas.play_end()
    var t_start := canvas.play_start()

    ZenElement.blend_begin(canvas, false)       # one-shot: no blend
    var worst := 0.0
    for e in canvas.elements():
        var el := e as ZenElement
        var kind := "text" if el is ZenText else ("global" if el is ZenGlobal else "shape")
        for prop_name in ZenProps.scalars_for(kind):
            if ZenProps.is_stepped(prop_name) or not el.has_track(prop_name): continue
            var d := absf(el.prop(prop_name, t_end, 0.0)
                        - el.track_or_base(prop_name, t_start, 0.0))
            if d > worst: worst = d
    ZenElement.blend_end()
    check(worst > 0.01,
          "main_menu seam is open without the blend (worst delta %.4f)" % worst)
    canvas.free()


## A stepped property is an identity, not a quantity: blending it would land
## between two pool entries and resolve to the wrong one (anim.c:652).
func test_stepped_never_blends() -> void:
    var c := ZenCanvas.new()
    c.duration = 2.0
    c.outro_start = 2.0
    c.loop_blend = 1.0
    c.loop_smooth = true

    var el := ZenElement.new()
    c.add_child(el)
    # Pool index 0 at the loop start, 7 at the end. A blend would smear these
    # into a fractional index.
    el.tracks = {"string": [
        {"t": 0.0, "v": 0.0, "ease": "linear"},
        {"t": 2.0, "v": 7.0, "ease": "linear"}]}
    ZenAnimBuilder.install(c)

    ZenElement.blend_begin(c, true)
    # At the loop end the blend weight is 1, so a blended read would return 0.
    check_near(el.prop("string", 2.0, 0.0), 7.0, "stepped prop ignores the blend")
    # And it steps rather than interpolating on the way.
    check_near(el.prop("string", 1.9, 0.0), 0.0, "stepped prop holds the left key")
    ZenElement.blend_end()

    check(ZenProps.is_stepped("string"), "string is stepped")
    check(ZenProps.is_stepped("shape_id"), "shape_id is stepped")
    check(not ZenProps.is_stepped("pos_x"), "pos_x is not stepped")
    c.free()


## The live clock: the intro plays ONCE, then every cycle restarts at intro_end
## (anim.c:1847-1869). This is why Godot's own looping cannot be used directly
## - it must be driven through a section, narrowed to the body at the wrap.
func test_canvas_clock() -> void:
    # No intro: loop_play wraps the whole body, starting right back at 0 -
    # the intro-handover shape (wrap to intro_end, never 0) is pinned
    # separately by test_section_loops_into_body, on pause_menu.
    var c := ZenCanvas.new()
    c.duration = 2.0
    c.outro_start = 2.0
    c.loop_play = true
    ZenAnimBuilder.install(c)
    root.add_child(c)
    await process_frame
    var ap := c.animation_player()
    ap.seek(c.play_end() - 0.01, true)
    for _i in 5: await process_frame
    check(ap.is_playing(), "a no-intro loop keeps playing past its own end")
    check(ap.current_animation_position < c.play_end() - 0.001,
          "and wraps back inside the body (%.4f < %.4f)" % [ap.current_animation_position, c.play_end()])
    c.queue_free()

    # One-shot: stops at the end and reports it via the AP's own signal -
    # replacing ZenPlayer's `finished`.
    var c2 := ZenCanvas.new()
    c2.duration = 2.0
    c2.outro_start = 2.0
    c2.loop_play = false
    ZenAnimBuilder.install(c2)
    root.add_child(c2)
    await process_frame
    var ap2 := c2.animation_player()
    var done := [false]
    ap2.animation_finished.connect(func(_n): done[0] = true)
    ap2.seek(c2.play_end() - 0.01, true)
    for _i in 5: await process_frame
    check(not ap2.is_playing(), "a one-shot stops at the end")
    check(done[0], "and the AP's own animation_finished fires")
    check_near(c2.pose_time, c2.play_end(), "the pose holds at play_end, the outro never shown", 0.02)
    c2.queue_free()


## Pause markers hold the clock until released. Containment is (from, to] so a
## released marker does not instantly re-fire (anim.c:1073-1084). Driven
## through advance_pauses(t0,t1) directly - the pure helper the old
## ZenPlayer.advance() folded the same check into, now unit-testable without a
## live clock.
## Start a bare player on a signal baked straight from its dictionary.
func _start(pl: ZenSignalPlayer, sig: Dictionary, params: Dictionary, seq: int,
            capture: Callable) -> void:
    pl.start(sig, params, seq, capture, ZenTimeline.new(ZenAnimBuilder.bake_signal(sig)))


func test_canvas_pauses() -> void:
    var c := ZenCanvas.new()
    c.duration = 3.0
    c.outro_start = 3.0
    c.loop_play = true
    c.pauses = [{"t": 1.0, "once": false}]

    var fired := [0]
    c.paused.connect(func(_i): fired[0] += 1)

    var t := 0.0
    for _i in 20:
        t = _wrap_step(c, t, 0.1)
        if c.held_pause >= 0: break
    check(c.held_pause == 0, "clock stops at the marker")
    check_near(t, 1.0, "clock parks exactly on the marker")
    check(fired[0] == 1, "paused emitted once")

    # Held: repeated steps do not move past it.
    var before := c.held_pause
    c.advance_pauses(t, t + 5.0)
    check(c.held_pause == before, "a held clock stays held")

    # Released, it resumes WITHOUT re-firing the marker it just served.
    c.release_pause()
    t = _wrap_step(c, t, 0.1)
    check(c.held_pause < 0, "resumes past the marker")
    check(fired[0] == 1, "marker does not re-fire on resume")

    # ...but it fires again on the NEXT cycle, because `once` is false.
    for _i in 60:
        t = _wrap_step(c, t, 0.1)
        if c.held_pause >= 0: break
    check(fired[0] == 2, "non-once marker fires again next cycle")
    c.free()

    # `once` fires exactly once, ever.
    var c2 := ZenCanvas.new()
    c2.duration = 2.0
    c2.outro_start = 2.0
    c2.loop_play = true
    c2.pauses = [{"t": 0.5, "once": true}]
    var n := [0]
    c2.paused.connect(func(_i): n[0] += 1)
    var t2 := 0.0
    for _i in 200:
        t2 = _wrap_step(c2, t2, 0.05)
        if c2.held_pause >= 0: c2.release_pause()
    check(n[0] == 1, "`once` marker fires exactly once (got %d)" % n[0])
    c2.free()


## One doc-time step, wrapping at play_end() back to play_start() the way the
## section API wraps live, and checking pauses over the step taken. A test
## helper, not runtime code - advance_pauses() itself has no clock.
func _wrap_step(c: ZenCanvas, t: float, dt: float) -> float:
    var raw := t + dt
    if raw >= c.play_end():
        raw = c.play_start() + fmod(raw - c.play_end(), c.cycle_length())
    c.advance_pauses(t, raw)
    # Mirrors ZenCanvas._process's own clamp: a pause pins to the marker's
    # exact instant, not wherever the step happened to land.
    if c.held_pause >= 0: return float(c.pauses[c.held_pause]["t"])
    return raw


## A marker near the loop end must not be swallowed by the wrap: a wrapping
## step is TWO ranges, not one (anim_stage.c:266-280).
func test_pause_across_wrap() -> void:
    var c := ZenCanvas.new()
    c.duration = 2.0
    c.intro_end = 0.5
    c.outro_start = 2.0
    c.loop_play = true
    # One marker just before the loop end, one exactly AT the loop point -
    # both are the cases a naive (t0,t1] test drops.
    c.pauses = [{"t": 0.5, "once": false}, {"t": 1.98, "once": false}]

    var hits: Array = []
    c.paused.connect(func(i): hits.append(float(c.pauses[i]["t"])))
    var t := 0.0
    for _i in 400:
        t = _wrap_step(c, t, 0.05)
        if c.held_pause >= 0: c.release_pause()

    check(hits.has(1.98), "marker just before the loop end fires")
    check(hits.has(0.5), "marker exactly at the loop point fires")
    c.free()


## The exporter reads markers off the canvas directly now, and ignores `once` -
## a file has nobody to press a key, and one pass means `once` can never
## suppress anything (zen_export.c:317-334).
func test_export_pause_source() -> void:
    var c := ZenCanvas.new()
    c.duration = 2.0
    c.outro_start = 2.0
    # Deliberately out of order, and one `once`.
    c.pauses = [{"t": 1.5, "once": true}, {"t": 0.5, "once": false}]

    var marks := ZenExport.pause_times(c)
    check(marks.size() == 2, "both markers reach the exporter")
    check_near(float(marks[0]), 0.5, "markers come back ascending")
    check_near(float(marks[1]), 1.5, "`once` marker is NOT skipped on export")
    c.free()


## A live canvas must NOT touch the clock until something plays it.
##
## The exporter poses the canvas at an explicit t and then awaits a frame; a
## clock ticking inside that await would re-pose everything to its own time,
## so every exported frame would render the same instant - correct per-property
## state, overwritten before the pixels are read, which the numeric suite alone
## cannot see. live_playback=false is the guard the exporter relies on.
func test_canvas_idle_until_played() -> void:
    var c := ZenCanvas.new()
    c.duration = 2.0
    c.outro_start = 2.0
    c.live_playback = false
    ZenAnimBuilder.install(c)
    root.add_child(c)
    await process_frame
    check(c.animation_player() == null, "live_playback=false builds no AnimationPlayer")
    check_near(c.pose_time, 0.0, "and the pose stays at 0")
    check(not c.is_processing(), "and the canvas is not processing")
    c.queue_free()


## No bundled scene carries a Player node - the clock is the canvas's own, and
## live_playback=false is what keeps it inert for a test.
func test_scenes_inert() -> void:
    for nm in ["main_menu", "pause_menu", "mouse_ripple", "zooming_box", "game_start"]:
        var path := "res://anims/%s.tscn" % nm
        if not ResourceLoader.exists(path): continue
        var canvas: ZenCanvas = (load(path) as PackedScene).instantiate()
        check(canvas.get_node_or_null("Player") == null, "%s has no Player" % nm)
        canvas.live_playback = false   # tests pose by hand; no live clock
        canvas.free()


## Pause markers become repeated frames on export, because a file has nobody to
## press a key. Checked here end-to-end on the frame PLAN, which is the part
## that decides the output length (zen_export.c:296-340).
func test_export_pause_holds() -> void:
    var c := ZenCanvas.new()
    c.duration = 2.0
    c.outro_start = 2.0
    var s := ZenExport.Settings.new()
    s.fps = 10
    s.show_intro = true
    s.pause_hold = 1.0          # 10 frames at 10fps

    var plain := ZenExport.frame_times(c, s, [])
    var held := ZenExport.frame_times(c, s, [1.0])
    check(held.size() == plain.size() + 10,
          "a 1s hold at 10fps adds 10 frames (got +%d)" % (held.size() - plain.size()))

    # The held frames all sit at the marker time, freezing the picture.
    var at_marker := 0
    for t in held:
        if absf(t - 1.0) < 0.0001: at_marker += 1
    check(at_marker >= 10, "the hold repeats the marker's own instant (got %d)" % at_marker)

    # A marker outside the exported range is ignored, not clamped in.
    var outside := ZenExport.frame_times(c, s, [5.0])
    check(outside.size() == plain.size(), "a marker past the range adds nothing")

    # Containment is [a,b): a marker exactly at the range START is INCLUDED,
    # which is where an intro-trimmed loop tends to put one.
    c.intro_end = 0.5
    s.show_intro = false
    var at_start := ZenExport.frame_times(c, s, [0.5])
    var no_mark := ZenExport.frame_times(c, s, [])
    check(at_start.size() > no_mark.size(),
          "a marker exactly at the range start is not dropped")
    c.free()


## A bare canvas with a known free-running length, for the chain tests.
func _chain_canvas(size := Vector2(320, 180)) -> ZenCanvas:
    var c := ZenCanvas.new()
    c.design_size = size
    c.duration = 2.0
    c.outro_start = 2.0
    c.live_playback = false
    return c


## Chaining several animations into one file: the frame plan is the part that
## decides the output, and the join beat is the part that is easy to get wrong
## (it belongs BETWEEN links, so the last one never has one).
func test_chain_frame_plan() -> void:
    var a := _chain_canvas()
    var b := _chain_canvas()
    var s := ZenExport.Settings.new()
    s.fps = 10
    s.show_intro = true
    s.pause_hold = 1.0          # 10 frames at 10fps

    var links := [{"canvas": a}, {"canvas": b}]

    var loose := ZenExport.plan_chain(links, s, false)
    check(bool(loose["ok"]), "a two-link chain plans")
    var lt: Dictionary = ZenExport.chain_totals(loose["segments"])
    check(int(lt["total"]) == 40, "no join pause: 20 + 20 frames (got %d)" % int(lt["total"]))
    check(int(lt["held"]) == 0, "and nothing is held")

    var joined := ZenExport.plan_chain(links, s, true)
    var jt: Dictionary = ZenExport.chain_totals(joined["segments"])
    check(int(jt["total"]) == 50, "one join adds one hold (got %d)" % int(jt["total"]))
    check(int(jt["held"]) == 10, "and those 10 frames count as held")
    var segs: Array = joined["segments"]
    check((segs[0] as ZenExport.ChainSegment).join_hold == 10, "the join sits after link 1")
    check((segs[1] as ZenExport.ChainSegment).join_hold == 0,
          "the LAST link gets no join - there is nothing after it")

    # An in-document pause marker and a join are both holds, and they add up.
    var marked := ZenExport.plan_chain([{"canvas": a, "pauses": [1.0]}, {"canvas": b}], s, true)
    var mt: Dictionary = ZenExport.chain_totals(marked["segments"])
    check(int(mt["total"]) == 60, "marker hold + join hold both land (got %d)" % int(mt["total"]))
    check(int(mt["held"]) == 20, "and both count as held (got %d)" % int(mt["held"]))

    a.free()
    b.free()


## Mixing canvas sizes in one chain is refused, and refused BEFORE any encoder
## opens - there is no right answer for compositing 320x180 next to 640x360,
## and a half-written file is worse than a clear no.
func test_chain_rejects_size_mismatch() -> void:
    var a := _chain_canvas()
    var b := _chain_canvas(Vector2(640, 360))
    var s := ZenExport.Settings.new()

    var r := ZenExport.plan_chain([{"canvas": a}, {"canvas": b}], s, false)
    check(not bool(r["ok"]), "a mismatched canvas size is refused")
    check(String(r["error"]).contains("640x360"), "and the error names the offender")
    check((r["segments"] as Array).is_empty(), "and no segments come back")

    check(not bool(ZenExport.plan_chain([], s, false)["ok"]), "an empty chain is refused")

    var too_many: Array = []
    for i in ZenExport.MAX_CHAIN + 1: too_many.append({"canvas": a})
    check(not bool(ZenExport.plan_chain(too_many, s, false)["ok"]),
          "a chain past MAX_CHAIN is refused")

    a.free()
    b.free()


## The single-animation door must plan exactly what the old direct path did -
## one encoder loop now serves both, so the one-link case has to stay put.
func test_single_link_plan_matches_legacy() -> void:
    var c := _chain_canvas()
    var s := ZenExport.Settings.new()
    s.fps = 12
    s.show_intro = true
    s.pause_hold = 0.5

    var legacy := ZenExport.frame_times(c, s, [1.0])
    var plan := ZenExport.plan_chain([{"canvas": c, "pauses": [1.0]}], s, false)
    var seg := (plan["segments"] as Array)[0] as ZenExport.ChainSegment
    check(seg.times == legacy, "a one-link chain plans the legacy frame list")
    check(seg.join_hold == 0, "and a lone link never gets a join beat")
    check(int(ZenExport.chain_totals(plan["segments"])["total"]) == legacy.size(),
          "and the total is just that list's length")
    c.free()


## The size estimate is calibrated, not derived (zen_export.c:619-692), so what
## is pinned here is its SHAPE: the directions it must move in, and the one
## format where it is exact arithmetic rather than a guess.
func test_estimate_bytes_shape() -> void:
    for fmt in ["gif", "png", "avi", "mp4", "webm"]:
        var small := ZenExport.estimate_bytes(fmt, 320, 180, 1, 50, 0, 16, 70)
        var longer := ZenExport.estimate_bytes(fmt, 320, 180, 1, 100, 0, 16, 70)
        var bigger := ZenExport.estimate_bytes(fmt, 320, 180, 4, 50, 0, 16, 70)
        check(longer > small, "%s: more frames estimates larger" % fmt)
        check(bigger > small, "%s: a deeper upscale estimates larger" % fmt)

    # AVI is uncompressed: 3 bytes per pixel per frame, exactly.
    check_near(ZenExport.estimate_bytes("avi", 320, 180, 2, 10, 0, 16, 70),
               640.0 * 360.0 * 10.0 * 3.0, "avi is exact arithmetic", 1.0)

    # Held frames are pixel-identical to the one before, so the formats that
    # difference between frames charge them at a tenth.
    for fmt in ["gif", "mp4", "webm"]:
        check(ZenExport.estimate_bytes(fmt, 320, 180, 2, 100, 50, 16, 70)
              < ZenExport.estimate_bytes(fmt, 320, 180, 2, 100, 0, 16, 70),
              "%s: held frames are discounted" % fmt)
    for fmt in ["png", "avi"]:
        check_near(ZenExport.estimate_bytes(fmt, 320, 180, 2, 100, 50, 16, 70),
                   ZenExport.estimate_bytes(fmt, 320, 180, 2, 100, 0, 16, 70),
                   "%s: a duplicate frame costs full price" % fmt, 1.0)

    # Both quality knobs move their own format's estimate.
    check(ZenExport.estimate_bytes("gif", 320, 180, 2, 50, 0, 4, 70)
          < ZenExport.estimate_bytes("gif", 320, 180, 2, 50, 0, 16, 70),
          "gif: a shallower palette estimates smaller")
    check(ZenExport.estimate_bytes("mp4", 320, 180, 2, 50, 0, 16, 20)
          < ZenExport.estimate_bytes("mp4", 320, 180, 2, 50, 0, 16, 90),
          "mp4: lower quality estimates smaller")


## GIF transparency is one bit, so a soft edge has to be decided one way or the
## other. Everything at or above the threshold goes opaque, everything below
## goes fully clear - and colour must survive untouched.
func test_cutout_snaps_alpha() -> void:
    var img := Image.create(3, 1, false, Image.FORMAT_RGBA8)
    img.set_pixel(0, 0, Color(1, 0, 0, 100.0 / 255.0))
    img.set_pixel(1, 0, Color(0, 1, 0, 128.0 / 255.0))
    img.set_pixel(2, 0, Color(0, 0, 1, 200.0 / 255.0))

    ZenExport.cutout(img, 128)
    check_near(img.get_pixel(0, 0).a, 0.0, "below the threshold goes clear", 0.01)
    check_near(img.get_pixel(1, 0).a, 1.0, "exactly at the threshold goes opaque", 0.01)
    check_near(img.get_pixel(2, 0).a, 1.0, "above the threshold goes opaque", 0.01)
    check_near(img.get_pixel(2, 0).b, 1.0, "and the colour is untouched", 0.01)


## Each format's ffmpeg arguments. Cheap to check and easy to break: AVI is the
## one format with no quality control at all, and the GIF palette depth must
## only appear when it is actually reduced.
func test_ffmpeg_args_per_format() -> void:
    var s := ZenExport.Settings.new()
    s.fmt = "avi"
    var avi := " ".join(ZenExport._args(s, 640, 360, "/tmp/x.avi"))
    check(avi.contains("rawvideo"), "avi encodes rawvideo")
    check(not avi.contains("-crf"), "avi has no quality control")

    s.fmt = "gif"
    s.quality_gif = 16
    check(not " ".join(ZenExport._args(s, 640, 360, "/tmp/x.gif")).contains("max_colors"),
          "gif at full quality asks for no palette reduction")
    s.quality_gif = 8
    check(" ".join(ZenExport._args(s, 640, 360, "/tmp/x.gif")).contains("max_colors=128"),
          "gif at half quality halves the palette")

    s.fmt = "mp4"
    s.quality = 100
    check(" ".join(ZenExport._args(s, 640, 360, "/tmp/x.mp4")).contains("-crf 18"),
          "full quality is the best CRF")
    check(ZenExport.crf(0) == 34, "and zero quality is the worst")


## Cancelling. The check sits at the top of the frame loop, so a job cancelled
## before its first frame must come back having written nothing - and the
## partial-file cleanup must not run off and delete anything else.
##
## Deliberately the no-frames case: rendering needs a real display
## (frame_post_draw never fires headless), so a mid-export cancel is a
## VISUAL_CHECKS item, not a suite one.
func test_job_cancel_png() -> void:
    var c := _chain_canvas()
    var s := ZenExport.Settings.new()
    s.fmt = "png"
    s.fps = 10
    s.show_intro = true
    s.out_dir = "user://test_exports"

    var plan := ZenExport.plan_chain([{"canvas": c}], s, false)
    check(bool(plan["ok"]), "the cancel fixture plans")

    var job := ZenExport.Job.new()
    job.cancel_requested = true
    # Merged, not assigned: a lambda captures a local BY VALUE, so rebinding
    # `got` inside it would never reach this scope. A Dictionary is a reference.
    var got := {}
    job.finished.connect(func(r: Dictionary): got.merge(r, true))
    var r: Dictionary = await job.run(root, plan["segments"], s, "cancel_probe")

    check(bool(r["cancelled"]), "a cancelled job says so")
    check(not bool(r["ok"]), "and does not report success")
    check(int(r["frames"]) == 0, "and wrote no frames (got %d)" % int(r["frames"]))
    check(job.total == 20, "while still knowing what it was going to do")
    check(bool(got.get("cancelled", false)), "and the finished signal carries the same result")

    var dir := DirAccess.open(ProjectSettings.globalize_path("user://test_exports/cancel_probe"))
    check(dir != null and dir.get_files().is_empty(), "no png landed on disk")
    if dir != null:
        DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_exports/cancel_probe"))
        DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_exports"))
    c.free()


# ---------------------------------------------------------------------------
#  Signal integration: the override layer against real scenes.
# ---------------------------------------------------------------------------

## A canvas with one shape, one track and one signal, built in code so each
## test states exactly the data it depends on.
func _sig_canvas(sig: Dictionary) -> ZenCanvas:
    var canvas := ZenCanvas.new()
    canvas.set_script(load("res://addons/zen/runtime/zen_canvas.gd"))
    canvas.design_size = Vector2(320, 180)
    canvas.duration = 4.0
    canvas.loop_blend = 1.0
    canvas.loop_smooth = true

    var sh := ZenShape.new()
    sh.set_script(load("res://addons/zen/runtime/zen_shape.gd"))
    sh.name = "shape"
    sh.elem_name = "shape"
    sh.scale_base = 1.0
    sh.color_base = Color(1, 0, 0, 1)
    sh.tracks = {
        "alpha": [{"t": 0.0, "v": 0.0, "ease": "linear"},
                  {"t": 4.0, "v": 1.0, "ease": "linear"}],
        "scale": [{"t": 0.0, "v": 2.0, "ease": "linear"},
                  {"t": 4.0, "v": 2.0, "ease": "linear"}],
        "color": [{"t": 0.0, "c": Color(1, 0, 0, 1), "ease": "linear"},
                  {"t": 4.0, "c": Color(0, 0, 1, 1), "ease": "linear"}],
        "shape_id": [{"t": 0.0, "v": 0.0, "ease": "linear"},
                     {"t": 4.0, "v": 3.0, "ease": "linear"}],
    }
    canvas.add_child(sh)

    var bus := ZenSignalBus.new()
    bus.set_script(load("res://addons/zen/runtime/zen_signal_bus.gd"))
    bus.name = "Signals"
    bus.signals_data = [sig]
    canvas.add_child(bus)
    ZenAnimBuilder.install(canvas)
    return canvas


func _one_target_sig(prop: String, to_value: float) -> Dictionary:
    return {"name": "go", "length": 2.0, "terminal": false, "uses_pos": false,
            "pos_anchor": false, "replay": false,
            "targets": [{"elem": "shape", "prop": prop,
                         "keys": [{"t": 1.0, "v": to_value, "ease": "linear"}]}],
            "pos_params": [], "seq_mult": 0.0, "uses_seq": false,
            "seq_targets": [], "seq_keys": []}


## THE ORDERING, which is the whole phase (anim.c:640-670). Four rules, each
## able to fail independently and each with its own assertion.
func test_signal_override_order() -> void:
    var canvas := _sig_canvas(_one_target_sig("alpha", 1.0))
    root.add_child(canvas)
    var sh: ZenShape = canvas.get_node("shape")
    var bus: ZenSignalBus = canvas.bus()

    # Baseline: the plain track at t=1 of a 0..1-over-4s ramp.
    canvas.pose(1.0)
    check_near(sh.prop("alpha", 1.0, 0.0), 0.25, "plain track before any signal")

    # RULE 2: the signal REPLACES the timeline. Fired at t=1 it captures 0.25
    # and eases to 1.0, so half way through it is 0.625 - a value the track
    # alone can never produce at t=1.
    bus.fire("go")
    bus.advance(1.0)
    canvas.pose(1.0)
    check_near(sh.prop("alpha", 1.0, 0.0), 0.625, "signal replaces the track")

    # ...and once it is over it HOLDS its final key, not the track.
    bus.advance(5.0)
    canvas.pose(1.0)
    check(bus.is_running() == false, "signal finished")
    check_near(sh.prop("alpha", 1.0, 0.0), 0.25, "a finished signal stops driving")
    canvas.queue_free()


## RULE 2, the half that no existing test could catch: the override must REPLACE
## the loop blend, not compose with it. An `if` instead of an `else` leaves every
## seam test green, because the seam tests never fire a signal.
func test_signal_replaces_loop_blend() -> void:
    var canvas := _sig_canvas(_one_target_sig("alpha", 1.0))
    root.add_child(canvas)
    var sh: ZenShape = canvas.get_node("shape")
    var bus: ZenSignalBus = canvas.bus()

    # Inside the blend window (last 1.0s of a 4s cycle) the blend is pulling
    # alpha back toward the loop-start pose, so the blended value differs from
    # the raw track.
    canvas.pose_looping(3.5, true)
    var blended := sh.prop("alpha", 3.5, 0.0)
    check(absf(blended - 0.875) > 0.05, "the loop blend is actually active at t=3.5")

    # Fire and run it to just under `length`, so it is STILL DRIVING: a
    # finished signal stops overriding entirely (the timeline resumes), so the
    # override can only be observed while it runs.
    #
    # Captured at t=3.5 the plain track reads 0.875, and the signal eases that
    # to its 1.0 key. The blended value is 0.4375 - less than HALF - so if the
    # override composed with the blend instead of replacing it, this is wildly
    # off rather than marginally.
    bus.fire("go")
    bus.advance(1.999)
    canvas.pose_looping(3.5, true)
    var driven := sh.prop("alpha", 3.5, 0.0)
    check_near(driven, 1.0,
               "signal overrides the loop blend rather than composing with it", 0.002)
    check(absf(driven - blended) > 0.5, "and the two are not coincidentally equal")
    canvas.queue_free()


## RULE 1: a stepped prop keys a POOL INDEX, so it is never overridden and
## never offset - the plain read, full stop (anim.c:652).
func test_signal_never_touches_stepped() -> void:
    var sig := _one_target_sig("shape_id", 0.0)
    sig["uses_seq"] = true
    sig["seq_mult"] = 1.0
    sig["seq_targets"] = [{"elem": "shape", "prop": "shape_id"}]
    var canvas := _sig_canvas(sig)
    root.add_child(canvas)
    var sh: ZenShape = canvas.get_node("shape")
    var bus: ZenSignalBus = canvas.bus()

    canvas.pose(2.0)
    var plain := sh.prop("shape_id", 2.0, 0.0)
    bus.seq = 5
    bus.fire("go")
    bus.advance(1.0)
    canvas.pose(2.0)
    check_near(sh.prop("shape_id", 2.0, 0.0), plain,
               "a stepped prop is neither overridden nor offset")
    canvas.queue_free()


## RULE 3: the additive offsets apply even when the signal does NOT drive the
## property. zooming_box's `ripple_old` seq-targets `shape scale`, which has no
## plain target, so scale must be the TRACK plus the offset - gating this on
## "the override hit" breaks that one document and nothing else, so it would
## ship (anim.c:665-669).
func test_signal_offset_without_target() -> void:
    var sig := {"name": "go", "length": 2.0, "terminal": false, "uses_pos": false,
                "pos_anchor": false, "replay": false,
                "targets": [{"elem": "shape", "prop": "alpha",
                             "keys": [{"t": 1.0, "v": 1.0, "ease": "linear"}]}],
                "pos_params": [], "seq_mult": 0.5, "uses_seq": true,
                "seq_targets": [{"elem": "shape", "prop": "scale"}],
                "seq_keys": []}
    var canvas := _sig_canvas(sig)
    root.add_child(canvas)
    var sh: ZenShape = canvas.get_node("shape")
    var bus: ZenSignalBus = canvas.bus()

    # Pose first: a signal captures the pose that is ON SCREEN, so firing
    # before the canvas has ever been posed captures t=0, not t=2.
    canvas.pose(2.0)
    bus.seq = 4
    bus.fire("go")
    bus.advance(1.0)
    canvas.pose(2.0)
    # scale's track holds 2.0 and the signal drives no scale target, so the
    # answer is track + seq*mult*env = 2.0 + 4*0.5*1.0.
    check_near(sh.prop("scale", 2.0, 1.0), 4.0,
               "seq offset stacks on the TRACK for an untargeted prop")
    # Captured 0.5 at t=2 and easing to 1.0, so half way it reads 0.75 - above
    # the track, which is what shows the override is live alongside the offset.
    check_near(sh.prop("alpha", 2.0, 0.0), 0.75, "and the targeted prop IS overridden")
    canvas.queue_free()


## Colour override: RGB from the signal, alpha from the plain track, because a
## colour prop carries no alpha of its own (anim.c:556).
func test_signal_color_keeps_track_alpha() -> void:
    var sig := {"name": "go", "length": 2.0, "terminal": false, "uses_pos": false,
                "pos_anchor": false, "replay": false,
                "targets": [{"elem": "shape", "prop": "color",
                             "keys": [{"t": 1.0, "c": Color(0, 1, 0, 1),
                                       "ease": "linear"}]}],
                "pos_params": [], "seq_mult": 0.0, "uses_seq": false,
                "seq_targets": [], "seq_keys": []}
    var canvas := _sig_canvas(sig)
    root.add_child(canvas)
    var sh: ZenShape = canvas.get_node("shape")
    var bus: ZenSignalBus = canvas.bus()

    bus.fire("go")
    bus.advance(1.999)          # still driving; a finished signal stops entirely
    canvas.pose(2.0)
    var c := sh.prop_color("color", 2.0, sh.color_base, 0.4)
    check_near(c.g, 1.0, "signal drives the colour's RGB", 0.01)
    check_near(c.r, 0.0, "signal drives the colour's RGB (red gone)", 0.01)
    check_near(c.a, 0.4, "colour override keeps the PLAIN track's alpha")
    canvas.queue_free()


## No compounding: re-firing mid-flight must capture the TIMELINE pose, not the
## previous signal's override, or the two would stack (anim.c:1522-1524).
func test_signal_no_compounding() -> void:
    var canvas := _sig_canvas(_one_target_sig("alpha", 1.0))
    root.add_child(canvas)
    var sh: ZenShape = canvas.get_node("shape")
    var bus: ZenSignalBus = canvas.bus()

    # First fire at t=1 (track = 0.25), run it most of the way up.
    bus.fire("go")
    bus.advance(1.8)
    canvas.pose(1.0)
    var high := sh.prop("alpha", 1.0, 0.0)
    check(high > 0.8, "first signal has climbed well above the track")

    # Re-fire. The new capture must be the TRACK (0.25), so u=0 reads 0.25 -
    # NOT the 0.9-ish value the previous override was showing.
    bus.fire("go")
    canvas.pose(1.0)
    check_near(sh.prop("alpha", 1.0, 0.0), 0.25,
               "re-firing captures the plain track, not the live override")
    canvas.queue_free()


## A point-signal dictionary over `shape`: `mode` is anchor / seek / follow.
func _point_sig(mode: String, off := Vector2.ZERO) -> Dictionary:
    var sig := ZenSignalData.defaults("go")
    sig["length"] = 2.0
    sig["point"] = mode
    sig["point_ease"] = "linear"
    sig["point_elems"] = [{"elem": "shape", "off": off}]
    return sig


## anchor is a CONSTANT TRANSLATION: the element is born at the cursor and
## plays its authored path, which is why anchor mode does NOT replace the slot
## (anim.c:1621-1622, 1783-1816). This is mouse_ripple's `ripple`.
func test_signal_pos_anchor_translates() -> void:
    var canvas := _sig_canvas(_point_sig("anchor"))
    root.add_child(canvas)
    var sh: ZenShape = canvas.get_node("shape")
    var bus: ZenSignalBus = canvas.bus()

    # The element sits at the centre; emit at (0.75, 0.25).
    check_near(sh.prop("pos_x", 0.0, 0.5), 0.5, "element starts centred")
    bus.fire("go", {"pos": Vector2(0.75, 0.25)})
    canvas.pose(0.0)
    check_near(sh.prop("pos_x", 0.0, 0.5), 0.75, "anchored to the emitted x")
    check_near(sh.prop("pos_y", 0.0, 0.5), 0.25, "anchored to the emitted y")

    # (0,0) is a LEGAL emit - the top-left corner - which is why the payload
    # uses the presence of "pos" rather than a separate has_pos bool that
    # could contradict it (signal.h:33).
    bus.fire("go", {"pos": Vector2.ZERO})
    canvas.pose(0.0)
    check_near(sh.prop("pos_x", 0.0, 0.5), 0.0, "(0,0) is a legal emit, not 'no position'")

    # The binding's constant offset is added to the point.
    var c2 := _sig_canvas(_point_sig("anchor", Vector2(0.1, -0.1)))
    root.add_child(c2)
    c2.bus().fire("go", {"pos": Vector2(0.5, 0.5)})
    c2.pose(0.0)
    var sh2: ZenShape = c2.get_node("shape")
    check_near(sh2.prop("pos_x", 0.0, 0.5), 0.6, "anchor adds the binding offset (x)")
    check_near(sh2.prop("pos_y", 0.0, 0.5), 0.4, "anchor adds the binding offset (y)")
    canvas.queue_free()
    c2.queue_free()


## No position given: a point signal reads the canvas pointer ONCE, at fire
## time - how a code trigger reacts to the mouse with no extra API.
func test_signal_pointer_fill() -> void:
    var canvas := _sig_canvas(_point_sig("anchor"))
    root.add_child(canvas)
    var sh: ZenShape = canvas.get_node("shape")
    canvas.pointer("move", Vector2(0.2, 0.7))
    canvas.fire("go")
    canvas.pose(0.0)
    check_near(sh.prop("pos_x", 0.0, 0.5), 0.2, "a code fire with no pos uses the pointer (x)")
    check_near(sh.prop("pos_y", 0.0, 0.5), 0.7, "a code fire with no pos uses the pointer (y)")
    # A snapshot, not live: moving the pointer afterwards changes nothing.
    canvas.pointer("move", Vector2(0.9, 0.9))
    canvas.pose(0.0)
    check_near(sh.prop("pos_x", 0.0, 0.5), 0.2, "anchor keeps the fire-time pointer")
    canvas.queue_free()


## seek REPLACES the position, easing from the captured centre to the point.
func test_signal_pos_param_replaces() -> void:
    var canvas := _sig_canvas(_point_sig("seek"))
    root.add_child(canvas)
    var sh: ZenShape = canvas.get_node("shape")
    var bus: ZenSignalBus = canvas.bus()

    bus.fire("go", {"pos": Vector2(0.9, 0.1)})
    bus.advance(1.0)
    canvas.pose(0.0)
    check_near(sh.prop("pos_x", 0.0, 0.5), 0.7, "seek is half way at u=0.5 (x)", 0.001)
    check_near(sh.prop("pos_y", 0.0, 0.5), 0.3, "seek is half way at u=0.5 (y)", 0.001)
    bus.advance(0.999)
    canvas.pose(0.0)
    check_near(sh.prop("pos_x", 0.0, 0.5), 0.9, "seek lands on the point (x)", 0.001)
    check_near(sh.prop("pos_y", 0.0, 0.5), 0.1, "seek lands on the point (y)", 0.001)
    # Seek ends like any signal: the timeline takes the element back.
    bus.advance(1.0)
    canvas.pose(0.0)
    check_near(sh.prop("pos_x", 0.0, 0.5), 0.5, "a finished seek hands back to the timeline")
    canvas.queue_free()


## RULE 4: a point binding OUTRANKS a plain target on the same prop.
## `ripple_old` has both, and the point must win (anim.c:1683).
func test_signal_pos_param_outranks_target() -> void:
    var sig := _point_sig("seek")
    sig["targets"] = [{"elem": "shape", "prop": "pos_x",
                       "keys": [{"t": 1.0, "v": 0.2, "ease": "linear"}]}]
    var canvas := _sig_canvas(sig)
    root.add_child(canvas)
    var sh: ZenShape = canvas.get_node("shape")
    var bus: ZenSignalBus = canvas.bus()

    bus.fire("go", {"pos": Vector2(0.9, 0.5)})
    bus.advance(1.999)          # still driving; a finished signal stops entirely
    canvas.pose(0.0)
    # The plain target would drive pos_x to 0.2, the point to 0.9. Opposite
    # directions, so there is no reading of this that both could satisfy.
    check_near(sh.prop("pos_x", 0.0, 0.5), 0.9,
               "the point wins over a plain target on the same prop", 0.001)
    canvas.queue_free()


## follow: seek toward the LIVE pointer, then keep tracking it after `length`
## until something supersedes it.
func test_signal_follow_tracks_pointer() -> void:
    var canvas := _sig_canvas(_point_sig("follow"))
    root.add_child(canvas)
    var sh: ZenShape = canvas.get_node("shape")
    var bus: ZenSignalBus = canvas.bus()

    canvas.pointer("move", Vector2(0.9, 0.5))
    canvas.fire("go")
    bus.advance(1.0)
    canvas.pose(0.0)
    check_near(sh.prop("pos_x", 0.0, 0.5), 0.7, "follow catches up over length", 0.001)
    # The pointer moves mid-flight: the target moves with it.
    canvas.pointer("move", Vector2(0.1, 0.5))
    canvas.pose(0.0)
    check_near(sh.prop("pos_x", 0.0, 0.5), 0.3, "follow eases toward the LIVE pointer", 0.001)

    bus.advance(5.0)
    check(not bus.is_running(), "the catch-up has run")
    check(bus.is_overriding(), "but a follow keeps overriding after length")
    check(bus.is_processing(), "and keeps re-posing every frame")
    canvas.pointer("move", Vector2(0.25, 0.75))
    canvas.pose(0.0)
    check_near(sh.prop("pos_x", 0.0, 0.5), 0.25, "follow sits on the pointer (x)", 0.001)
    check_near(sh.prop("pos_y", 0.0, 0.5), 0.75, "follow sits on the pointer (y)", 0.001)

    canvas.release_signal()
    check(not bus.is_overriding(), "release_signal lets go of a follow")
    check_near(sh.prop("pos_x", 0.0, 0.5), 0.5, "released: back on the timeline")
    canvas.queue_free()


## Another signal fired supersedes a follow - one player per canvas.
func test_signal_follow_superseded() -> void:
    var canvas := _sig_canvas(_point_sig("follow"))
    var bus: ZenSignalBus = canvas.bus()
    var other := _one_target_sig("alpha", 1.0)
    other["name"] = "fade"
    bus.signals_data.append(other)
    ZenAnimBuilder.install(canvas)
    root.add_child(canvas)
    var sh: ZenShape = canvas.get_node("shape")
    canvas.pointer("move", Vector2(0.9, 0.9))
    canvas.fire("go")
    bus.advance(5.0)
    canvas.pose(0.0)
    check_near(sh.prop("pos_x", 0.0, 0.5), 0.9, "following before the next fire")
    canvas.fire("fade")
    canvas.pose(0.0)
    check_near(sh.prop("pos_x", 0.0, 0.5), 0.5, "a new signal supersedes the follow")
    canvas.queue_free()


## press / release triggers fire from pointer(), at the pointer position; a
## trigger with no matching signal fires nothing; the first in list order wins.
func test_signal_trigger_press_release() -> void:
    var down := _point_sig("anchor")
    down["name"] = "down"
    down["trigger"] = "press"
    var canvas := _sig_canvas(down)
    var bus: ZenSignalBus = canvas.bus()
    var up := _point_sig("seek")
    up["name"] = "up"
    up["trigger"] = "release"
    var dup := up.duplicate(true)
    dup["name"] = "up2"
    bus.signals_data.append(up)
    bus.signals_data.append(dup)
    ZenAnimBuilder.install(canvas)
    root.add_child(canvas)
    var fired: Array = []
    bus.signal_fired.connect(func(nm, params): fired.append([nm, params]))

    check(not canvas.pointer("move", Vector2(0.3, 0.3)), "a move fires nothing")
    check(canvas.pointer("press", Vector2(0.2, 0.4)), "press fires the press signal")
    check(canvas.pointer("release", Vector2(0.6, 0.8)), "release fires the release signal")
    check(fired.size() == 2 and fired[0][0] == "down" and fired[1][0] == "up",
          "press -> down, release -> the FIRST release signal")
    check(fired.size() == 2 and fired[1][1].get("pos") == Vector2(0.6, 0.8),
          "the trigger carries the pointer position")
    check(bus.wants_pointer(), "a bus with press/release signals wants the pointer")
    check(not bus.trigger("end"), "no end signal: the end trigger fires nothing")
    canvas.queue_free()


## `end`: a one-shot running out fires its end signal BEFORE `finished`; a
## timeline a terminal signal stopped short is no `end`.
func test_signal_trigger_end_oneshot() -> void:
    var sig := _one_target_sig("alpha", 1.0)
    sig["name"] = "done"
    sig["trigger"] = "end"
    var canvas := _sig_canvas(sig)
    canvas.loop_play = false
    root.add_child(canvas)
    var order: Array = []
    canvas.bus().signal_fired.connect(func(nm, _p): order.append(nm))
    canvas.finished.connect(func(): order.append("finished"))
    canvas.setup_animation_player(false)

    canvas._seek_safe(1.0)          # stopped mid-way: not an end
    canvas.stop_timeline()
    canvas._check_finished()
    check(order == ["finished"], "a timeline stopped short of its end fires no end signal")

    canvas._finished_sent = false
    order.clear()
    canvas._seek_safe(canvas.play_end())
    canvas.stop_timeline()
    canvas._check_finished()
    check(order == ["done", "finished"], "end fires its signal, then finished")
    canvas._check_finished()
    check(order.size() == 2, "and only once")
    canvas.queue_free()


## `end` on a looping timeline: every wrap with every_loop, else the first.
func test_signal_trigger_end_every_loop() -> void:
    for every in [false, true]:
        var sig := _one_target_sig("alpha", 1.0)
        sig["name"] = "wrap"
        sig["trigger"] = "end"
        sig["every_loop"] = every
        var canvas := _sig_canvas(sig)
        canvas.loop_play = true
        root.add_child(canvas)
        var n := [0]
        canvas.bus().signal_fired.connect(func(_nm, _p): n[0] += 1)
        canvas.setup_animation_player(false)
        canvas._seek_safe(1.0)
        canvas._check_wrap()
        check(n[0] == 0, "no wrap, no end signal (every_loop=%s)" % every)
        for _i in 3:
            canvas._last_raw = 3.9          # the clock went backwards: a wrap
            canvas._check_wrap()
        check(n[0] == (3 if every else 1),
              "every_loop=%s fires on %s wrap" % [every, "every" if every else "the first"])
        canvas.rewind_timeline()
        canvas._last_raw = 3.9
        canvas._check_wrap()
        check(n[0] == (4 if every else 2), "a rewind starts the wrap count over")
        canvas.queue_free()


## `then` chains on the completion edge; a terminal signal never chains.
func test_signal_then_chain() -> void:
    var a := _one_target_sig("alpha", 1.0)
    a["name"] = "a"
    a["then"] = "b"
    var canvas := _sig_canvas(a)
    var bus: ZenSignalBus = canvas.bus()
    var b := _one_target_sig("alpha", 0.0)
    b["name"] = "b"
    bus.signals_data.append(b)
    ZenAnimBuilder.install(canvas)
    root.add_child(canvas)
    bus.fire("a")
    bus.advance(1.0)
    check(bus.running_name == "a", "a is still running")
    bus.advance(1.5)
    check(bus.running_name == "b", "a's completion edge fires b")

    (bus.signals_data[0] as Dictionary)["terminal"] = true
    bus.fire("a")
    bus.advance(3.0)
    check(bus.running_name == "", "a terminal signal does not chain")
    check(ZenSignalData.chained(_point_sig("follow")) == "", "a follow does not chain")
    canvas.queue_free()


## A chained signal starts from the previous link's END pose, not from the
## timeline: no one-frame flash of the timeline pose between links.
func test_signal_chain_carries_pose() -> void:
    var a := _one_target_sig("alpha", 1.0)
    a["name"] = "a"
    a["then"] = "b"
    var canvas := _sig_canvas(a)
    var bus: ZenSignalBus = canvas.bus()
    var b := _one_target_sig("alpha", 0.0)
    b["name"] = "b"
    bus.signals_data.append(b)
    # Bake only b: a second install() would rebake a from its stripped keys.
    var lib := ZenAnimBuilder.find_player(canvas).get_animation_library(ZenAnimBuilder.SIG_LIB)
    lib.add_animation(ZenAnimBuilder.sig_anim_name("b"), ZenAnimBuilder.bake_signal(b))
    root.add_child(canvas)
    var sh: ZenShape = canvas.get_node("shape")
    canvas.pose(0.0)
    bus.fire("a")
    bus.advance(2.0)
    check(bus.running_name == "b", "a chained into b")
    canvas.pose(0.0)
    check_near(sh.prop("alpha", 0.0, 0.0), 1.0, "b starts where a left alpha", 0.001)
    bus.advance(1.0)
    canvas.pose(0.0)
    check_near(sh.prop("alpha", 0.0, 0.0), 0.5, "and eases on from there (half way)", 0.001)
    check(bus._carry.is_empty(), "the carried pose is not kept past the hand-over")
    bus.release_signal()
    bus.fire("b")
    canvas.pose(0.0)
    check_near(sh.prop("alpha", 0.0, 0.0), 0.0, "a plain fire still captures the timeline", 0.001)
    canvas.queue_free()


## The sig_* demo scenes (tools/gen_signal_demos.gd): sound data, and each one
## does what its hint says when driven the way a player would.
func test_signal_demos() -> void:
    var names: Array = []
    for nm in ZenSceneOps.scene_paths():
        if String(nm).begins_with("sig_"): names.append(nm)
    check(names.size() == 9, "nine signal demos ship (%d)" % names.size())
    for nm in names:
        var c: ZenCanvas = (load(ZenSceneOps.path_of(nm)) as PackedScene).instantiate()
        root.add_child(c)
        var bus := c.bus()
        check(bus != null, "%s has signals" % nm)
        if bus == null:
            c.queue_free()
            continue
        for sn in bus.names():
            var sd := bus.find(sn)
            var a := ZenAnimBuilder.signal_anim(c, sn)
            check(a != null and a.get_track_count() > 0 or not (sd["point_elems"] as Array).is_empty(),
                  "%s/%s drives something" % [nm, sn])
            check(ZenSignalOps.trigger_clash(c, sn).is_empty(), "%s/%s has no trigger clash" % [nm, sn])
            var nx := String(sd["then"])
            check(nx.is_empty() or bus.has(nx), "%s/%s chains to a real signal" % [nm, sn])
            for pe in sd["point_elems"]:
                check(ZenElemOps.find(c, String(pe["elem"])) != null,
                      "%s/%s binds a real element" % [nm, sn])
        c.queue_free()

    var run := func(nm: String) -> ZenCanvas:
        var cv: ZenCanvas = (load(ZenSceneOps.path_of(nm)) as PackedScene).instantiate()
        root.add_child(cv)
        cv.pose(0.5)
        return cv
    var c: ZenCanvas = run.call("sig_press_anchor")
    c.pointer("press", Vector2(0.2, 0.3))
    check(c.bus().running_name == "burst", "press_anchor: a press fires burst")
    c.bus().advance(0.1)
    c.pose(0.5)
    var ring := ZenElemOps.find(c, "ring")
    check_near(ring.center_px(0.5).x, 64.0, "press_anchor: the ring is born at the click", 0.5)
    c.queue_free()

    c = run.call("sig_release_seek")
    c.pointer("release", Vector2(0.2, 0.3))
    check(c.bus().running_name == "throw", "release_seek: a release fires throw")
    c.bus().advance(0.69)
    c.pose(0.5)
    check_near(ZenElemOps.find(c, "ball").center_px(0.5).y, 0.3 * 180.0,
               "release_seek: the ball arrives at the mouse-up", 1.5)
    c.queue_free()

    c = run.call("sig_follow")
    c.pointer("press", Vector2(0.8, 0.2))
    c.bus().advance(1.0)
    check(c.bus().is_following(), "follow: a press grabs and keeps following")
    c.pointer("release", Vector2(0.3, 0.7))
    check(c.bus().running_name == "drop", "follow: release supersedes with drop")
    c.bus().advance(0.5)
    check(c.bus().running_name == "respawn", "follow: drop chains into respawn")
    c.pose(0.5)
    check_near(ZenElemOps.find(c, "orb").prop("alpha", 0.5, 1.0), 0.0,
               "follow: respawn starts from drop's faded orb", 0.05)
    c.queue_free()

    c = run.call("sig_code")
    check(not c.bus().wants_pointer(), "code: nothing fires on its own")
    c.pointer("move", Vector2(0.7, 0.4))
    c.fire("ping")
    c.bus().advance(0.6)
    c.pose(0.5)
    check_near(ZenElemOps.find(c, "mark").center_px(0.5).x, 0.7 * 320.0,
               "code: ping lands at the pointer read when fired", 0.5)
    c.queue_free()

    c = run.call("sig_end_once")
    check(not c.loop_play, "end_once is a one-shot")
    check(c.bus().trigger("end", null, 0), "end_once: the end trigger fires done")
    c.bus().advance(1.0)
    check(c.bus().is_holding(), "end_once: done is terminal and holds")
    c.queue_free()

    for pair in [["sig_end_every_loop", true], ["sig_end_first_loop", false]]:
        c = run.call(pair[0])
        check(c.bus().trigger("end", null, 1), "%s: the first wrap fires lap" % pair[0])
        c.bus().release_signal()
        check(c.bus().trigger("end", null, 2) == pair[1], "%s: the second wrap %s" % [
              pair[0], "fires again" if pair[1] else "does not"])
        c.queue_free()

    c = run.call("sig_then_chain")
    c.pointer("press", Vector2(0.5, 0.5))
    check(c.bus().running_name == "windup", "then_chain: a press winds up")
    c.bus().advance(0.4)
    check(c.bus().running_name == "launch", "then_chain: windup -> launch")
    c.bus().advance(0.7)
    check(c.bus().running_name == "land", "then_chain: launch -> land")
    c.pose(0.5)
    check(ZenElemOps.find(c, "rocket").center_px(0.5).y < 0.0,
          "then_chain: land picks the rocket up off-screen, where launch left it")
    c.queue_free()

    c = run.call("sig_starfall")
    c.pointer("press", Vector2(0.4, 0.7))
    check(c.bus().running_name == "comet", "starfall: a click sends the comet")
    c.bus().advance(0.8)
    check(c.bus().running_name == "nova", "starfall: the comet chains into the nova")
    c.bus().advance(0.05)
    c.pose(2.0)
    check_near(ZenElemOps.find(c, "nova_ring").center_px(2.0).x, 0.4 * 320.0,
               "starfall: the nova bursts where the comet landed", 0.5)
    check(c.bus().trigger("end", null, 3), "starfall: shimmer fires on every loop")
    c.queue_free()


## Legacy uses_pos / pos_anchor / pos_params upgrade to the point fields.
func test_signal_normalize_legacy() -> void:
    var old := {"name": "r", "length": 1.0, "uses_pos": true, "pos_anchor": false,
                "replay": false, "targets": [],
                "pos_params": [
                    {"elem": "shape", "slot": 0,
                     "keys": [{"t": 1.0, "off": Vector2(0.1, 0.0), "ease": "quadIn"}]},
                    {"elem": "box", "slot": 1, "keys": []}]}
    ZenSignalData.normalize(old)
    check(old["point"] == "seek", "uses_pos without anchor is seek")
    check(old["point_elems"].size() == 1, "the corner slot is dropped")
    check(old["point_elems"][0]["off"] == Vector2(0.1, 0.0), "the last key's offset carries over")
    check(old["point_ease"] == "quadIn", "the last key's ease carries over")
    check(old["trigger"] == "code", "legacy signals are code-triggered")
    check(not old.has("uses_pos") and not old.has("pos_params"), "legacy fields are gone")
    var again: Dictionary = old.duplicate(true)
    ZenSignalData.normalize(again)
    check(again == old, "normalize is idempotent")

    var anchor := {"name": "r", "uses_pos": true, "pos_anchor": true,
                   "pos_params": [{"elem": "shape", "slot": 0, "keys": []}]}
    ZenSignalData.normalize(anchor)
    check(anchor["point"] == "anchor", "uses_pos with pos_anchor is anchor")
    check(anchor["point_elems"][0]["off"] == Vector2.ZERO, "stripped keys mean no offset")
    var none := {"name": "n", "uses_pos": false, "pos_anchor": false, "pos_params": []}
    ZenSignalData.normalize(none)
    check(none["point"] == "none", "uses_pos off is point none")


## Point signals bake no tracks, and a legacy `pos_offset` track is dropped on
## load rather than left for the AnimationPlayer to fail to resolve.
func test_signal_bake_no_pos_offset() -> void:
    var canvas := _sig_canvas(_point_sig("seek"))
    var anim := ZenAnimBuilder.signal_anim(canvas, "go")
    check(anim != null and anim.get_track_count() == 0, "a point signal bakes no tracks")
    var tr := anim.add_track(Animation.TYPE_BEZIER)
    anim.track_set_path(tr, NodePath("shape:pos_offset_0:x"))
    root.add_child(canvas)
    canvas.bus().has("go")          # any entry point upgrades the scene
    check(anim.get_track_count() == 0, "legacy pos_offset tracks are dropped on load")
    canvas.queue_free()


## A canvas with one shape and no signals - what a new scene is.
func _bare_canvas() -> ZenCanvas:
    var canvas := _sig_canvas(ZenSignalData.defaults("x"))
    var bus := canvas.bus()
    canvas.remove_child(bus)
    bus.free()
    ZenAnimBuilder.find_player(canvas).remove_animation_library(ZenAnimBuilder.SIG_LIB)
    return canvas


## ZenSignalOps add / rename / remove keep signals_data, library `sig`, the
## declared user signals and every `then` in step; the first add makes the bus.
func test_signal_ops_add_rename_remove() -> void:
    var canvas := _bare_canvas()
    root.add_child(canvas)
    check(canvas.bus() == null, "a new scene has no bus")
    var a := ZenSignalOps.add(canvas)
    check(canvas.bus() != null and canvas.bus().owner == canvas, "the first add creates an owned bus")
    check(a == "signal1", "default names count up")
    var b := ZenSignalOps.add(canvas, "signal1")
    check(b == "signal11", "a taken name is made unique")
    check(ZenSignalOps.anim(canvas, a) != null, "add makes the signal's Animation")
    check(canvas.bus().has(a) and canvas.bus().has(b), "both are declared user signals")

    ZenSignalOps.set_field(canvas, b, "then", a)
    check(ZenSignalOps.rename(canvas, a, "go"), "rename to a free name")
    check(not ZenSignalOps.rename(canvas, b, "go"), "rename onto a taken name fails")
    check(String(ZenSignalOps.data(canvas, b)["then"]) == "go", "rename rewrites `then`")
    check(ZenSignalOps.anim(canvas, "go") != null and ZenSignalOps.anim(canvas, a) == null,
          "rename moves the Animation")
    check(canvas.bus().has("go") and not canvas.bus().has(a), "rename re-declares the user signal")
    check(canvas.fire("go"), "the renamed signal fires by its new name")

    ZenSignalOps.set_field(canvas, b, "trigger", "press")
    ZenSignalOps.set_field(canvas, "go", "trigger", "press")
    check(ZenSignalOps.trigger_clash(canvas, b) == "go", "a later same-trigger signal clashes")
    check(ZenSignalOps.trigger_clash(canvas, "go") == "", "the first one does not")

    ZenSignalOps.remove(canvas, "go")
    check(not ZenSignalOps.names(canvas).has("go"), "remove drops the data")
    check(ZenSignalOps.anim(canvas, "go") == null, "remove drops the Animation")
    check(not canvas.bus().has("go"), "remove retires the user signal")
    check(String(ZenSignalOps.data(canvas, b)["then"]) == "", "remove clears `then` pointing at it")

    ZenSignalOps.bind_point(canvas, b, "shape", Vector2(0.1, 0))
    ZenSignalOps.bind_point(canvas, b, "shape", Vector2(0.2, 0))
    check(ZenSignalOps.data(canvas, b)["point_elems"].size() == 1, "binding twice updates the offset")
    ZenSignalOps.unbind_point(canvas, b, "shape")
    check(ZenSignalOps.data(canvas, b)["point_elems"].is_empty(), "unbind drops the binding")
    canvas.queue_free()


## Signal keys are edited with ZenKeyOps through canvas.edit_anim; sync()
## adds the t=0 capture key, lists the target and writes the capture meta, so
## the fired signal eases from the LIVE pose into the authored key.
func test_signal_edit_anim_keyops() -> void:
    var canvas := _bare_canvas()
    root.add_child(canvas)
    var sh: ZenShape = canvas.get_node("shape")
    var nm := ZenSignalOps.add(canvas, "go")
    ZenSignalOps.set_field(canvas, nm, "length", 2.0)
    canvas.edit_anim = nm
    ZenKeyOps.insert(canvas, sh, "alpha", 2.0, 1.0, "linear")
    canvas.edit_anim = ""
    check(ZenKeyOps.keys(canvas, sh, "alpha").size() == 2, "the document timeline is untouched")
    ZenSignalOps.sync(canvas, nm)

    var sig := ZenSignalOps.data(canvas, nm)
    check(sig["targets"].size() == 1 and sig["targets"][0]["prop"] == "alpha", "sync lists the target")
    canvas.edit_anim = nm
    var ks := ZenKeyOps.keys(canvas, sh, "alpha")
    canvas.edit_anim = ""
    check(ks.size() == 2 and float(ks[0]["t"]) == 0.0, "sync adds the t=0 capture key")
    var cap: Dictionary = ZenSignalOps.anim(canvas, nm).get_meta(ZenTimeline.META_CAPTURE, {})
    check(cap.has("shape:alpha") and is_equal_approx(float(cap["shape:alpha"][0]), 2.0),
          "the capture meta names the first authored key")

    # Fired at t=1 (track alpha 0.25), half way it reads 0.625: from the
    # live pose, not from the placeholder.
    canvas.pose(1.0)
    canvas.fire(nm)
    canvas.bus().advance(1.0)
    canvas.pose(1.0)
    check_near(sh.prop("alpha", 1.0, 0.0), 0.625, "an edited signal eases from the live pose")

    # Doubling the length keeps each key at its u.
    ZenSignalOps.set_field(canvas, nm, "length", 4.0)
    canvas.edit_anim = nm
    ks = ZenKeyOps.keys(canvas, sh, "alpha")
    canvas.edit_anim = ""
    check(ks.size() == 2 and is_equal_approx(float(ks[1]["t"]), 4.0), "length rescales the keys")

    # Deleting the authored key leaves only the capture key: the target goes.
    canvas.edit_anim = nm
    ZenKeyOps.remove(canvas, sh, "alpha", 1)
    canvas.edit_anim = ""
    ZenSignalOps.sync(canvas, nm)
    check(ZenSignalOps.data(canvas, nm)["targets"].is_empty(), "a capture-only track is dropped")
    canvas.queue_free()


## The terminal EDGE, including the instant case. A cross-frame "was playing"
## flag would miss a length=0 signal entirely (anim_stage.c:310-328).
func test_signal_terminal_edge() -> void:
    var sig := _one_target_sig("alpha", 1.0)
    sig["terminal"] = true
    var canvas := _sig_canvas(sig)
    root.add_child(canvas)
    var bus: ZenSignalBus = canvas.bus()

    var fired: Array = []
    bus.terminal_finished.connect(func(nm: String): fired.append(nm))

    bus.fire("go")
    bus.advance(1.0)
    check(fired.is_empty(), "terminal does not fire mid-signal")
    bus.advance(1.0)
    check(fired.size() == 1 and fired[0] == "go", "terminal fires on the completion edge")
    bus.advance(1.0)
    check(fired.size() == 1, "terminal fires ONCE, not every frame after")
    canvas.queue_free()

    # The instant case: length 0 starts and finishes inside one update.
    var inst := _one_target_sig("alpha", 1.0)
    inst["terminal"] = true
    inst["length"] = 0.0
    var c2 := _sig_canvas(inst)
    root.add_child(c2)
    var b2: ZenSignalBus = c2.bus()
    var fired2: Array = []
    b2.terminal_finished.connect(func(nm: String): fired2.append(nm))
    b2.fire("go")
    b2.advance(0.016)
    check(fired2.size() == 1, "an INSTANT (length 0) terminal signal still fires its edge")
    c2.queue_free()


## A TERMINAL signal holds its end pose once done; a plain one hands back.
##
## The canvas stops on the terminal edge, so without the hold the elements
## snapped back to the frozen timeline pose - pause_menu's `exit` flew off
## screen and then reappeared.
func test_signal_terminal_holds_end_pose() -> void:
    var sig := _one_target_sig("alpha", 0.9)
    sig["terminal"] = true
    var canvas := _sig_canvas(sig)
    root.add_child(canvas)
    var sh: ZenShape = canvas.get_node("shape")
    var bus: ZenSignalBus = canvas.bus()
    canvas.pose(1.0)
    bus.fire("go")
    bus.advance(2.5)
    bus._repose()
    check(not bus.is_running(), "terminal signal is no longer running")
    check(bus.is_holding(), "terminal signal holds after its end")
    check_near(sh.prop("alpha", 1.0, 0.0), 0.9, "held pose is the signal's u=1 value")
    bus.release_hold()
    check(not bus.is_holding(), "release_hold drops the hold")
    check_near(sh.prop("alpha", 1.0, 0.0), 0.25, "released: back on the timeline")
    canvas.queue_free()

    var c2 := _sig_canvas(_one_target_sig("alpha", 0.9))
    root.add_child(c2)
    var sh2: ZenShape = c2.get_node("shape")
    var b2: ZenSignalBus = c2.bus()
    c2.pose(1.0)
    b2.fire("go")
    b2.advance(2.5)
    b2._repose()
    check(not b2.is_holding(), "a NON-terminal signal does not hold")
    check_near(sh2.prop("alpha", 1.0, 0.0), 0.25, "non-terminal hands back to the timeline")
    c2.queue_free()


## Signal names are DOCUMENT DATA, so they must survive a pack/instantiate.
##
## Measured: user signals do NOT survive pack, exported Arrays do. So dropping
## the _ready() re-declaration breaks every signal at RUNTIME only, with the
## whole numeric suite still green - which is what this pins.
func test_signal_pack_roundtrip() -> void:
    var canvas := _sig_canvas(_one_target_sig("alpha", 1.0))
    # Hyphenated, to pin the other half: `signal TV-out` is a parse error, so
    # these names can only ever be user signals.
    (canvas.bus().signals_data[0] as Dictionary)["name"] = "TV-out"
    for c in canvas.get_children():
        c.owner = canvas

    var packed := PackedScene.new()
    check(packed.pack(canvas) == OK, "canvas with a bus packs")
    canvas.queue_free()

    var fresh: ZenCanvas = packed.instantiate()
    root.add_child(fresh)
    var bus: ZenSignalBus = fresh.bus()
    check(bus != null, "the bus survived the pack")
    check(bus.signals_data.size() == 1, "signals_data survived the pack")
    check(bus.has("TV-out"), "the hyphenated user signal was re-declared in _ready()")

    # And it is a real Godot signal, which is what puts it in the Signals dock.
    var found := false
    for s in bus.get_signal_list():
        if String(s["name"]) == "TV-out": found = true
    check(found, "it appears in get_signal_list(), i.e. in Godot's Signals dock")

    # Firing through Godot's own emit_signal must work identically to fire().
    var seen: Array = []
    bus.signal_fired.connect(func(nm: String, _p: Dictionary): seen.append(nm))
    bus.emit_signal("TV-out", {})
    check(seen.size() == 1, "a native emit_signal drives the override")
    fresh.queue_free()


## THE REASON THE GLOBAL BUS EXISTS: one emit reaches every live canvas, and
## each blends from its OWN pose (anim_stage.c:155-159). A relay that owned
## evaluation state could not express this.
func test_signal_autoload_relay() -> void:
    var a := _sig_canvas(_one_target_sig("alpha", 1.0))
    var b := _sig_canvas(_one_target_sig("alpha", 1.0))
    root.add_child(a)
    root.add_child(b)
    # The group is joined in _enter_tree, which this harness defers (see _run).
    await process_frame

    # Give them DIFFERENT poses, which is the whole point.
    a.pose(1.0)
    b.pose(3.0)
    var sha: ZenShape = a.get_node("shape")
    var shb: ZenShape = b.get_node("shape")

    # The autoload singleton does NOT exist under `--script` (a SceneTree
    # script bypasses autoload setup), so the relay is instantiated here. That
    # is the honest test anyway: what is under test is the relay's logic, not
    # Godot's autoload wiring - which test_signal_autoload_registered covers.
    var relay := _relay()
    var n: int = relay.emit("go")
    check(n == 2, "one emit reached both canvases (got %d)" % n)
    check(a.bus().is_running() and b.bus().is_running(), "both buses are running")

    # Each captured its own pose, so at u=0 they read differently.
    a.pose(1.0)
    b.pose(3.0)
    check_near(sha.prop("alpha", 1.0, 0.0), 0.25, "canvas A captured ITS pose")
    check_near(shb.prop("alpha", 3.0, 0.0), 0.75, "canvas B captured ITS pose")
    check(absf(sha.prop("alpha", 1.0, 0.0) - shb.prop("alpha", 3.0, 0.0)) > 0.1,
          "the two captures DIFFER - a shared player could not do this")

    check(relay.has("go"), "the relay reports a live signal")
    check(not relay.has("nope"), "and does not invent one")
    check(relay.listeners("go").size() == 2, "listeners() names both canvases")
    check(relay.names().has("go"), "names() lists what is live")
    relay.queue_free()
    a.queue_free()
    b.queue_free()


## A relay instance, standing in for the autoload (see above).
func _relay() -> Node:
    var r := Node.new()
    r.set_script(load("res://addons/zen/runtime/zen_signals.gd"))
    root.add_child(r)
    return r


## The relay must actually BE an autoload, or ZenSignals.emit() - the whole
## point of the global layer - is an undefined identifier at runtime. The test
## above cannot see this, because autoloads do not exist under `--script`.
func test_signal_autoload_registered() -> void:
    var want := "res://addons/zen/runtime/zen_signals.gd"
    var key := "autoload/ZenSignals"
    check(ProjectSettings.has_setting(key), "ZenSignals is registered as an autoload")
    if ProjectSettings.has_setting(key):
        var v := String(ProjectSettings.get_setting(key))
        # The leading * makes it a Node singleton rather than a plain script.
        check(v.begins_with("*"), "the autoload is enabled (leading *), got '%s'" % v)
        check(v.trim_prefix("*") == want, "the autoload points at zen_signals.gd")


## The purity guard the autoload makes necessary: an inert bus is skipped, so a
## stray emit cannot install an override mid-export.
func test_signal_autoload_respects_inert() -> void:
    var c := _sig_canvas(_one_target_sig("alpha", 1.0))
    root.add_child(c)
    await process_frame
    var bus: ZenSignalBus = c.bus()
    bus.inert = true

    var relay := _relay()
    check(relay.emit("go") == 0, "the relay skips an inert bus")
    check(not bus.is_running(), "and the inert bus did not start")
    check(not bus.fire("go"), "nor does the direct path fire it")
    # Still DECLARED, though: inert is an off switch, not a deletion.
    check(bus.has("go"), "an inert bus still declares its signals")
    check(relay.listeners("go").size() == 1, "and still reports as a listener")
    relay.queue_free()
    c.queue_free()


## The base poses the signal capture reads MUST be the ones _draw() passes to
## prop(). If they drift, a signal eases from a pose the renderer never showed.
func test_signal_bases_match_draw() -> void:
    var sh := ZenShape.new()
    sh.set_script(load("res://addons/zen/runtime/zen_shape.gd"))
    sh.size_frac = Vector2(0.3, 0.4)
    sh.scale_base = 1.5
    sh.color_base = Color(1, 1, 1, 0.6)
    sh.outline_color_base = Color(1, 0, 0, 0.3)
    sh.outline_base = 2.0
    check_near(sh.base_scalar("w"), 0.3, "shape base w")
    check_near(sh.base_scalar("h"), 0.4, "shape base h")
    check_near(sh.base_scalar("scale"), 1.5, "shape base scale")
    check_near(sh.base_scalar("alpha"), 0.6, "shape base alpha = color_base.a")
    check_near(sh.base_scalar("outline_alpha"), 0.3, "shape base outline_alpha")
    check_near(sh.base_scalar("outline"), 2.0, "shape base outline")
    check(sh.base_color("outline_color") == sh.outline_color_base, "shape outline_color base")
    check(sh.base_color("color") == sh.color_base, "shape color base")

    var tx := ZenText.new()
    tx.set_script(load("res://addons/zen/runtime/zen_text.gd"))
    tx.size_frac = Vector2(0.12, 0.12)
    tx.crumble_dir = 45.0
    check_near(tx.base_scalar("size"), 0.12, "text base size = size_frac.x")
    check_near(tx.base_scalar("crumble"), 0.0, "text base crumble is 0")
    check_near(tx.base_scalar("crumble_dir"), 45.0, "text base crumble_dir")

    var gl := ZenGlobal.new()
    gl.set_script(load("res://addons/zen/runtime/zen_global.gd"))
    gl.bg_color_base = Color(0, 0, 0, 0.8)
    check_near(gl.base_scalar("fade"), 0.0, "global base fade is 0")
    check_near(gl.base_scalar("bg_alpha"), 0.8, "global base bg_alpha")

    # Every scalar prop of every kind must resolve to SOMETHING, or the capture
    # would silently read 0 for it.
    for kind in ["text", "shape", "global"]:
        var e: ZenElement = tx if kind == "text" else (sh if kind == "shape" else gl)
        for p in ZenProps.scalars_for(kind):
            if ZenProps.is_stepped(p): continue
            check(not is_nan(e.base_scalar(p)), "%s base for '%s' resolves" % [kind, p])


## A signal captures the pose that is ON SCREEN, which is the time the canvas
## was last posed at - not a clock, and not the time passed to a later prop()
## call.
##
## Worth its own test because getting it wrong is silent: reading the
## AnimationPlayer's own clock instead would capture the wrong instant
## whenever it is not driving the canvas - every export frame and every editor
## scrub - and the signal would still animate, just from the wrong pose.
func test_signal_captures_posed_time() -> void:
    var canvas := _sig_canvas(_one_target_sig("alpha", 1.0))
    root.add_child(canvas)
    var sh: ZenShape = canvas.get_node("shape")
    var bus: ZenSignalBus = canvas.bus()

    # alpha ramps 0..1 over 4s, so posing at 3.0 shows 0.75.
    canvas.pose(3.0)
    bus.fire("go")
    canvas.pose(3.0)
    check_near(sh.prop("alpha", 3.0, 0.0), 0.75, "u=0 reads the POSED pose (t=3)")

    # Pose somewhere else and fire again: the new capture must follow.
    canvas.pose(1.0)
    bus.fire("go")
    canvas.pose(1.0)
    check_near(sh.prop("alpha", 1.0, 0.0), 0.25, "a later fire captures the NEW pose")

    # There is no player here at all, so a clock-based capture would have read
    # 0.0 for both of the above.
    check(canvas.pose_time == 1.0, "the canvas records the time it was posed at")
    canvas.queue_free()


## A signal naming an element that is not there must be survivable, matching the
## C's out-of-range guard (anim.c:1516-1521).
func test_signal_unknown_element() -> void:
    var sig := _one_target_sig("alpha", 1.0)
    (sig["targets"][0] as Dictionary)["elem"] = "ghost"
    var canvas := _sig_canvas(sig)
    root.add_child(canvas)
    var sh: ZenShape = canvas.get_node("shape")
    var bus: ZenSignalBus = canvas.bus()

    bus.fire("go")
    bus.advance(1.0)
    canvas.pose(1.0)
    check(bus.is_running(), "a signal with an unresolvable target still runs")
    check_near(sh.prop("alpha", 1.0, 0.0), 0.25, "and the real element is untouched")
    canvas.queue_free()


## The bundled scenes declare the signals they were authored with.
func test_scene_signals_present() -> void:
    var want := {"main_menu": ["TV-out"], "pause_menu": ["exit"],
                 "mouse_ripple": ["enter", "ripple"],
                 "zooming_box": ["ripple_old", "TV-out"]}
    for anim in want:
        var path := "res://anims/%s.tscn" % anim
        check(ResourceLoader.exists(path), "%s.tscn exists" % anim)
        if not ResourceLoader.exists(path): continue
        var c: ZenCanvas = (load(path) as PackedScene).instantiate()
        c.live_playback = false   # tests pose by hand; no live clock
        root.add_child(c)
        var bus: ZenSignalBus = c.bus()
        check(bus != null, "%s has a signal bus" % anim)
        if bus != null:
            for nm in want[anim]:
                check(bus.has(nm), "%s declares '%s'" % [anim, nm])
        c.queue_free()

    # mouse_ripple's `enter` has NO targets, so it must never start - it is the
    # live example of the no-start rule.
    var mr: ZenCanvas = (load("res://anims/mouse_ripple.tscn") as PackedScene).instantiate()
    mr.live_playback = false   # tests pose by hand; no live clock
    root.add_child(mr)
    var b: ZenSignalBus = mr.bus()
    b.fire("enter")
    check(not b.is_running(), "mouse_ripple's `enter` has no targets and never starts")
    b.fire("ripple", {"pos": Vector2(0.3, 0.7)})
    check(b.is_running(), "mouse_ripple's `ripple` does start")
    mr.queue_free()


## Signals must be INERT during export: the exporter never fires one, and
## ZenExport.run silences the bus regardless.
func test_signal_export_purity() -> void:
    var c: ZenCanvas = (load("res://anims/mouse_ripple.tscn") as PackedScene).instantiate()
    c.live_playback = false   # tests pose by hand; no live clock
    root.add_child(c)
    var bus: ZenSignalBus = c.bus()
    check(bus != null, "mouse_ripple has a bus")
    check(not bus.is_running(), "a freshly loaded bus is idle")
    check(not bus.is_processing(), "and is not ticking a clock (set_process(false))")

    # Two poses at the same t must agree, with an unrelated pose in between:
    # that is the (scene, t) purity the exporter relies on.
    c.pose(1.0)
    var sh: ZenElement = c.elements()[0]
    var a := sh.prop("scale", 1.0, 1.0)
    c.pose(0.2)
    c.pose(1.0)
    check_near(sh.prop("scale", 1.0, 1.0), a, "pose(t) is pure across other poses")
    c.queue_free()


## The AnimationPlayer must actually BUILD and PLAY for a live scene: "open the
## scene, press F6, watch it play" is the baseline expectation of a Godot
## scene, so a scene that does not move on F6 is the bug, and it gets a test.
func test_anim_player_plays() -> void:
    var canvas: ZenCanvas = (load("res://anims/main_menu.tscn") as PackedScene).instantiate()
    # NOT setting live_playback=false here: this test is specifically about the
    # live path, unlike every other canvas test in this file.
    root.add_child(canvas)
    await process_frame
    var ap := canvas.animation_player()
    check(ap != null, "a live canvas builds an AnimationPlayer")
    if ap == null:
        canvas.queue_free()
        return
    check(ap.is_playing(), "and it is playing")
    check(is_equal_approx(ap.current_animation_length, canvas.duration),
          "animation length is the FULL clock %.4f (the outro stays visible on the timeline)"
          % canvas.duration)

    # The clock must advance the POSE, not merely itself.
    var t0 := canvas.pose_time
    for i in 6: await process_frame
    check(canvas.pose_time > t0,
          "the pose advances with the clock (%.4f -> %.4f)" % [t0, canvas.pose_time])

    # The outro is never posed, and a wrap lands in the BODY, not at 0 - the one
    # rule Godot's own looping cannot express (it always restarts at 0).
    #
    # Tested on the MAPPING, not by sampling pose_time a few frames after the
    # wrap: by then the clock has advanced past intro_end on its own, so a wrap
    # to 0 would satisfy a `>= intro_end` check too. Verified: that weaker form
    # passed with `seek(0)` substituted for `seek(play_start())`.
    ap.seek(canvas.duration - 0.004, true)
    for i in 3: await process_frame
    check(canvas.pose_time <= canvas.play_end() + 0.001,
          "the outro is never posed (%.4f <= %.4f)" % [canvas.pose_time, canvas.play_end()])

    # Just past the end, the mapped time must be a BODY time. The first instant
    # of the new cycle is intro_end itself, so an exact-equality probe at the
    # wrap point is what separates "restarts at intro_end" from "restarts at 0".
    var just_past: float = canvas.play_end() + 0.0005
    var mapped: float = canvas._anim_time_for(just_past)
    check(mapped >= canvas.play_start() - 0.0001,
          "a wrap maps into the loop body, not back to 0 (raw %.4f -> %.4f, intro_end %.4f)"
          % [just_past, mapped, canvas.play_start()])
    # A full cycle past the end must land in the body too, not drift into the intro.
    var far: float = canvas.play_end() + canvas.cycle_length() * 0.5
    var mapped2: float = canvas._anim_time_for(far)
    check(mapped2 >= canvas.play_start() - 0.0001 and mapped2 <= canvas.play_end() + 0.0001,
          "and stays in the body a cycle later (raw %.4f -> %.4f, body [%.4f, %.4f])"
          % [far, mapped2, canvas.play_start(), canvas.play_end()])
    canvas.queue_free()

    # MAIN_MENU cannot distinguish the two wrap formulas: its body is longer
    # than its intro, so `fmod(raw, cyc)` and `intro_end + fmod(raw-intro_end,
    # cyc)` give the SAME answer (verified - substituting the wrong one failed
    # nothing). A document with a LONG intro and a SHORT body is where they
    # diverge, which is pause_menu's shape (intro 1.513 of 1.987), so the rule
    # is pinned there instead.
    var pm: ZenCanvas = (load("res://anims/pause_menu.tscn") as PackedScene).instantiate()
    pm.live_playback = false
    pm.loop_smooth = true
    check(pm.play_start() > pm.cycle_length(),
          "pause_menu's intro really is longer than its body (%.4f > %.4f) - the case that discriminates"
          % [pm.play_start(), pm.cycle_length()])
    for off in [0.01, 0.3]:
        var r: float = pm.play_end() + off
        var m: float = pm._anim_time_for(r)
        check(m >= pm.play_start() - 0.0001 and m <= pm.play_end() + 0.0001,
              "long-intro wrap stays in the body (raw %.4f -> %.4f, body [%.4f, %.4f])"
              % [r, m, pm.play_start(), pm.play_end()])
    pm.queue_free()


## The saved scene's AnimationPlayer "zen" animation.
func _zen_anim(c: ZenCanvas) -> Animation:
    return ZenAnimBuilder.find_player(c).get_animation(ZenAnimBuilder.ANIM)


## intro_end / outro_start / pauses are markers in the SAVED animation, and the
## canvas reads them back (also when they are dragged in Godot's panel).
func test_anim_player_markers() -> void:
    var canvas: ZenCanvas = (load("res://anims/main_menu.tscn") as PackedScene).instantiate()
    canvas.live_playback = false
    check(ZenAnimBuilder.find_player(canvas) != null, "the scene carries its AnimationPlayer")
    var anim := _zen_anim(canvas)
    var names: PackedStringArray = anim.get_marker_names()
    check(names.has(ZenAnimBuilder.M_INTRO), "intro_end reaches the timeline as a marker")
    check(names.has(ZenAnimBuilder.M_OUTRO), "outro_start reaches the timeline as a marker")
    check(is_equal_approx(anim.get_marker_time(ZenAnimBuilder.M_INTRO), canvas.intro_end),
          "the intro marker carries the authored time")
    check(is_equal_approx(anim.length, canvas.duration),
          "duration comes from the animation length (%.3f)" % canvas.duration)

    # Dragging a marker edits the document.
    anim.remove_marker(ZenAnimBuilder.M_INTRO)
    anim.add_marker(ZenAnimBuilder.M_INTRO, 0.9)
    check(ZenAnimBuilder.sync_markers(anim, canvas), "a moved marker reports a change")
    check(is_equal_approx(canvas.intro_end, 0.9),
          "and writes back to intro_end (%.4f)" % canvas.intro_end)

    # A 0 is ABSENT, not a marker at the origin.
    var ripple: ZenCanvas = (load("res://anims/mouse_ripple.tscn") as PackedScene).instantiate()
    ripple.live_playback = false
    check(not _zen_anim(ripple).get_marker_names().has(ZenAnimBuilder.M_INTRO),
          "intro_end 0 means no marker at all")

    # Pause markers: pause_N[_once], read back in time order.
    var pg: ZenCanvas = (load("res://anims/ma_prog/ma_prog_01_intro.tscn") as PackedScene).instantiate()
    check(pg.pauses.size() == 4, "ma_prog_01's four pauses come back from markers (%d)" % pg.pauses.size())
    var pa := _zen_anim(pg)
    var first_t := float(pg.pauses[0]["t"])
    for nm in pa.get_marker_names():
        if String(nm).begins_with(ZenAnimBuilder.M_PAUSE) and is_equal_approx(pa.get_marker_time(nm), first_t):
            pa.remove_marker(nm)
            pa.add_marker(String(nm), first_t + 0.25)
    ZenAnimBuilder.sync_markers(pa, pg)
    check(is_equal_approx(float(pg.pauses[0]["t"]), first_t + 0.25) or float(pg.pauses[0]["t"]) > first_t,
          "moving a pause marker moves the pause")
    var asc := true
    for i in range(1, pg.pauses.size()):
        if float(pg.pauses[i]["t"]) < float(pg.pauses[i - 1]["t"]): asc = false
    check(asc, "pauses stay ascending")
    canvas.free()
    ripple.free()
    pg.free()


## What is in the AnimationPlayer is what plays: tracks have the right type,
## stepped props never interpolate, and editing a key changes the pose.
func test_anim_player_tracks() -> void:
    var c := ZenCanvas.new()
    c.live_playback = false
    c.duration = 2.0
    var txt := ZenText.new()
    txt.name = "stepped_text"
    txt.elem_name = "stepped_text"
    txt.tracks = {
        "string": [{"t": 0.0, "v": 0.0, "ease": "linear"},
                   {"t": 1.0, "v": 3.0, "ease": "linear"}],
        "alpha":  [{"t": 0.0, "v": 0.0, "ease": "linear"},
                   {"t": 1.0, "v": 1.0, "ease": "cubicIn"}],
        "color":  [{"t": 0.0, "c": Color(1, 0, 0), "ease": "linear"},
                   {"t": 1.0, "c": Color(0, 0, 1), "ease": "linear"}],
    }
    c.add_child(txt)
    txt.owner = c
    ZenAnimBuilder.install(c)
    var anim := _zen_anim(c)
    var seen := {}
    for ti in anim.get_track_count():
        seen[String(anim.track_get_path(ti))] = anim.track_get_type(ti)
    check(seen.get("stepped_text:string") == Animation.TYPE_VALUE, "stepped prop is a value track")
    var ti_s := anim.find_track(NodePath("stepped_text:string"), Animation.TYPE_VALUE)
    check(anim.track_get_interpolation_type(ti_s) == Animation.INTERPOLATION_NEAREST,
          "stepped props are NEAREST, never interpolated")
    check(seen.get("stepped_text:alpha") == Animation.TYPE_BEZIER, "alpha is a bezier track")
    check(seen.has("stepped_text:color:r") and seen.has("stepped_text:color:b"),
          "colour is split per channel")

    var tl := c.timeline()
    check_near(tl.stepped("stepped_text:string", 0.5, 0.0), 0.0, "stepped holds the left key")
    check_near(tl.stepped("stepped_text:string", 1.0, 0.0), 3.0, "stepped takes the key at its time")
    check_near(tl.scalar("stepped_text:alpha", 0.5, 0.0), 0.125, "cubicIn baked into the curve", 0.002)
    check_near(tl.color("stepped_text:color", 0.5, Color.BLACK, 1.0).r, 0.5, "colour channel interpolates")

    # Editing a key in the saved Animation changes what plays.
    c.pose(0.5)
    var before := txt.prop("alpha", 0.5, 0.0)
    var ti_a := anim.find_track(NodePath("stepped_text:alpha"), Animation.TYPE_BEZIER)
    anim.bezier_track_set_key_value(ti_a, 1, 0.0)
    anim.bezier_track_set_key_in_handle(ti_a, 1, Vector2(-1.0 / 3.0, 0.0))
    anim.bezier_track_set_key_out_handle(ti_a, 0, Vector2(1.0 / 3.0, 0.0))
    c.timeline_dirty()
    check(txt.prop("alpha", 0.5, 0.0) < before - 0.05,
          "editing a key in the AnimationPlayer changes the pose")
    c.free()


## pack -> instantiate keeps every curve.
func test_anim_player_roundtrip() -> void:
    var c: ZenCanvas = (load("res://anims/main_menu.tscn") as PackedScene).instantiate()
    c.live_playback = false
    var packed := PackedScene.new()
    for n in c.get_children(): n.owner = c
    check(packed.pack(c) == OK, "scene packs")
    var d: ZenCanvas = packed.instantiate()
    d.live_playback = false
    var worst := 0.0
    for t in [0.0, 0.7, 1.4, 2.2, 3.0]:
        c.pose(t)
        d.pose(t)
        var ea := c.elements()
        var eb := d.elements()
        for i in ea.size():
            for p in ZenProps.scalars_for((ea[i] as ZenElement).zen_kind()):
                worst = maxf(worst, absf((ea[i] as ZenElement).prop(p, t, 0.0) - (eb[i] as ZenElement).prop(p, t, 0.0)))
    check(worst < 1e-6, "a round-tripped scene poses identically (%s)" % snappedf(worst, 1e-9))
    check(is_equal_approx(c.duration, d.duration), "and keeps the clock")
    c.free()
    d.free()


## Every built-in ease bakes within tolerance; the polynomial ones near exactly.
func test_bake_accuracy() -> void:
    var worst_all := 0.0
    var worst_exact := 0.0
    for nm in ZenEasing.GODOT_EASE.keys():
        var anim := Animation.new()
        anim.length = 5.0
        var tr := anim.add_track(Animation.TYPE_BEZIER)
        for k in ZenCurveBake.bake([{"t": 1.0, "v": 10.0, "ease": "linear"},
                                    {"t": 3.0, "v": 50.0, "ease": nm}]):
            anim.bezier_track_insert_key(tr, k["t"], k["v"], k["in"], k["out"])
        var m := 0.0
        for i in 201:
            var sx := i / 200.0
            m = maxf(m, absf(anim.bezier_track_interpolate(tr, 1.0 + 2.0 * sx)
                - (10.0 + 40.0 * ZenEasing.apply(nm, sx))) / 40.0)
        worst_all = maxf(worst_all, m)
        if ["linear", "quadIn", "quadOut", "cubicIn", "cubicOut", "backIn", "backOut"].has(nm):
            worst_exact = maxf(worst_exact, m)
    check(worst_all < 1.5e-3, "every built-in ease bakes within 1.5e-3 (%s)" % snappedf(worst_all, 1e-9))
    check(worst_exact < 3e-4, "polynomial eases bake near-exactly (%s)" % snappedf(worst_exact, 1e-9))


## A signal's capture segment: the baked placeholder maps onto the live value.
func test_signal_capture_segment() -> void:
    var sig := {"name": "go", "length": 1.0, "targets": [
        {"elem": "x", "prop": "w", "keys": [{"t": 0.5, "v": 10.0, "ease": "backOut"}]}]}
    var tl := ZenTimeline.new(ZenAnimBuilder.bake_signal(sig))
    for v0 in [0.0, 4.0, -3.0, 10.0]:
        for u in [0.0, 0.1, 0.25, 0.4, 0.5, 0.8, 1.0]:
            var want: float = 10.0 if u >= 0.5 else \
                v0 + (10.0 - v0) * ZenEasing.apply("backOut", u / 0.5)
            check_near(tl.blend("x:w", u, v0), want, "capture segment v0=%s u=%s" % [v0, u], 0.02)
    # A track with a key at u=0 has no capture: it ignores the live value.
    var flat := {"name": "f", "length": 1.0, "targets": [
        {"elem": "x", "prop": "w", "keys": [{"t": 0.0, "v": 2.0, "ease": "linear"},
                                            {"t": 1.0, "v": 6.0, "ease": "linear"}]}]}
    var ft := ZenTimeline.new(ZenAnimBuilder.bake_signal(flat))
    check_near(ft.blend("x:w", 0.5, 99.0), 4.0, "keys from u=0 ignore the live value", 0.01)
    check_near(ft.blend("x:w", 3.0, 99.0), 6.0, "past the last key holds")


## SPACE's job: release a held pause and keep playing INSIDE the section.
func test_release_pause_keeps_section() -> void:
    var c: ZenCanvas = (load("res://anims/ma_prog/ma_prog_01_intro.tscn") as PackedScene).instantiate()
    c.loop_smooth = false
    root.add_child(c)
    await process_frame
    c.setup_animation_player(true)
    var ap := c.animation_player()
    c.held_pause = 0
    ap.seek(float(c.pauses[0]["t"]), true)
    ap.pause()
    c.pose(float(c.pauses[0]["t"]))
    c.release_pause()
    check(c.held_pause < 0, "release clears the hold")
    check(ap.has_section(), "the section survives the release")
    check(ap.is_playing(), "and playback resumes")
    check(ap.current_animation_position >= float(c.pauses[0]["t"]) - 0.05,
          "resumes at the marker, not at 0 (%.3f)" % ap.current_animation_position)
    c.queue_free()


## Generated by tools/gen_input_map.gd into project.godot's [input] section.
func test_input_actions_declared() -> void:
    var names := ["zen_play", "zen_back", "zen_restart", "zen_prev", "zen_next",
                  "zen_options", "zen_export", "zen_export_queue",
                  "zen_toggle_intro", "zen_toggle_loop", "zen_tab", "zen_help",
                  "zen_delete"]
    for i in range(1, 10): names.append("zen_signal_%d" % i)
    for n in names:
        check(InputMap.has_action(n), "action %s is declared" % n)
    var play_events: Array = InputMap.action_get_events("zen_play")
    check(play_events.size() == 3, "zen_play carries 3 events")


## ZenSettings: the Options screen's persistence layer. Restores every value
## it touches at the end, so test order never leaves a stray font override
## (which would make every later font-dependent check depend on what fonts
## happen to be installed on the machine running the suite) or a changed
## user://zen_settings.cfg behind.
func test_zen_settings() -> void:
    var orig_font := ZenSettings.font_name()
    var orig_scale := ZenSettings.export_scale()

    ZenSettings.set_export_scale(999)
    check(ZenSettings.export_scale() == ZenExport.MAX_SCALE, "export scale clamps to MAX_SCALE")
    ZenSettings.set_export_scale(-5)
    check(ZenSettings.export_scale() == 1, "export scale clamps to 1")

    ZenSettings.set_font_name("")
    var bundled := ZenText.default_font()
    check(bundled != null, "empty font name resolves to the bundled default")

    var fonts: Array = OS.get_system_fonts()
    if not fonts.is_empty():
        var nm := String(fonts[0])
        ZenSettings.set_font_name(nm)
        var f := ZenText.default_font()
        check(f is SystemFont, "a named system font overrides the bundled default")
        check((f as SystemFont).font_names[0] == nm, "override carries the chosen family name")

    ZenSettings.set_font_name("Source Sans 3 (bundled)")
    check(ZenText.default_font() is FontFile and not ZenTextMetrics.is_bitmap(ZenText.default_font()),
          "the bundled Source Sans name loads the TTF, not a SystemFont")

    ZenSettings.set_font_name("")
    check(ZenText.default_font() == bundled, "clearing the override restores the bundled default")

    var orig_export := ZenSettings.export_defaults()
    ZenSettings.set_export_defaults({"fmt": "mp4", "fps": 24})
    var got := ZenSettings.export_defaults()
    check(String(got["fmt"]) == "mp4", "export default fmt round-trips")
    check(int(got["fps"]) == 24, "export default fps round-trips")
    check(got.has("quality_gif") and int(got["quality_gif"]) == 16,
          "a field not passed to set_export_defaults keeps its default")
    got["fmt"] = "avi"
    check(String(ZenSettings.export_defaults()["fmt"]) != "avi",
          "export_defaults() returns a copy, not the live Dictionary")
    ZenSettings.set_export_defaults(orig_export)

    ZenSettings.set_font_name(orig_font)
    ZenSettings.set_export_scale(orig_scale)

    var ev := InputEventKey.new()
    ev.physical_keycode = KEY_R
    ev.pressed = true
    check(ev.is_action_pressed("zen_restart"),
          "a synthetic physical_keycode=KEY_R event reports zen_restart pressed")


## The Export dialog's frame-count/size preview is built from the gallery's
## scanned metadata, never from instantiating scenes while the chain is being
## edited (see ZenExportDialog's class doc). This pins that arithmetic
## headless, with no display and no .tscn load needed for the dialog itself.
func test_export_dialog_preview() -> void:
    var ps := load("res://tools/zen_export_dialog.tscn") as PackedScene
    var dlg := ps.instantiate()
    root.add_child(dlg)

    var entries := [
        {"name": "a", "ok": true, "design": Vector2(320, 180),
         "intro_end": 0.0, "play_start": 0.0, "play_end": 1.0, "pauses": 0},
        {"name": "b", "ok": true, "design": Vector2(320, 180),
         "intro_end": 0.5, "play_start": 0.5, "play_end": 2.0, "pauses": 1},
    ]
    dlg.open(entries, ["a"])
    # Explicit, not whatever ZenSettings.export_defaults() last persisted - a
    # real export run writes its format back, so this test must not depend
    # on what a previous interactive session left in user://zen_settings.cfg.
    dlg._s.fmt = "gif"
    dlg._s.fps = 10
    dlg._refresh()
    check(dlg._frames_label.text == "10 frames - 1.00s (0 held)",
          "single-link preview matches play_end-play_start * fps with no holds")

    dlg._chain.append("b")
    dlg._s.join_pause = true
    dlg._s.pause_hold = 1.0   # 10 held frames per marker/join at fps=10
    dlg._refresh()
    # a: 10 base + 10 join_hold.  b: 15 base (1.5s*10) + 10 marker_hold (1 pause).
    check(dlg._frames_label.text == "45 frames - 4.50s (20 held)",
          "chained preview adds base frames plus join and pause-marker holds")

    check(dlg._default_name() == "a_chain",
          "default export name for a multi-link chain is <first>_chain")

    # Godot scene: its own block replaces the video rows, and an invalid
    # target disables Export with the reason shown.
    dlg._s.fmt = "godot"
    dlg._gs.to_exports = false
    dlg._gs.target_dir = ""
    dlg._refresh()
    check(dlg._godot_box.visible and not dlg._frames_label.visible and not dlg._size_label.visible,
          "godot format shows its block and hides the video rows")
    check(dlg._export_btn.disabled and dlg._godot_hint.text != "",
          "no target project: Export disabled, reason shown")
    dlg._gs.target_dir = ProjectSettings.globalize_path("res://")
    dlg._refresh()
    check(not dlg._export_btn.disabled and dlg._godot_hint.text.contains("res://zen/a.tscn")
          and dlg._godot_hint.text.contains("README.txt"),
          "a valid target lists the scenes and notes it will write")
    dlg._gs.target_dir = ""
    dlg._gs.to_exports = true
    dlg._refresh()
    check(not dlg._export_btn.disabled and not dlg._godot_target_row.visible
          and dlg._folder_path().ends_with("exports/godot/zen"),
          "exports destination needs no target and hides the project row")
    dlg._s.fmt = "gif"
    dlg._refresh()
    check(not dlg._godot_box.visible and dlg._frames_label.visible and not dlg._export_btn.disabled,
          "back to a video format restores its rows and Export")
    dlg._name_edit.text = ""
    check(dlg._resolved_path_preview() == "res://exports/a_chain.gif",
          "empty name field previews the resolved default-name path")

    dlg.queue_free()


## pause_menu is the discriminator: its intro (1.513) is longer than its body
## (0.473), the one shape where "restart at intro_end" and "restart at 0"
## actually differ. Proves the section API replaced the hand-rolled wrap.
func test_section_loops_into_body() -> void:
    var pm: ZenCanvas = (load("res://anims/pause_menu.tscn") as PackedScene).instantiate()
    pm.loop_play = true
    root.add_child(pm)
    await process_frame
    var ap := pm.animation_player()
    check(ap != null, "pause_menu builds an AnimationPlayer")
    if ap == null:
        pm.queue_free()
        return
    ap.seek(pm.play_end() - 0.01, true)
    for _i in 6: await process_frame
    check(is_equal_approx(ap.get_section_start_time(), pm.intro_end),
          "after the wrap the section starts at intro_end, not 0 (got %.4f, want %.4f)"
          % [ap.get_section_start_time(), pm.intro_end])
    check(ap.current_animation_position >= pm.play_start() - 0.001,
          "and playback position stays in the body (%.4f >= %.4f)"
          % [ap.current_animation_position, pm.play_start()])
    pm.queue_free()


## The measured pitfall this plan exists to pin: AnimationPlayer.seek() does
## NOT clamp into the active section, so a caller must widen the section first
## (the ZenCanvas._seek_safe chokepoint) rather than seek() directly.
func test_seek_stays_in_section() -> void:
    var c := ZenCanvas.new()
    c.duration = 3.0
    c.intro_end = 0.5
    c.outro_start = 2.0
    c.loop_play = true
    ZenAnimBuilder.install(c)
    root.add_child(c)
    for _i in 2: await process_frame
    var ap := c.animation_player()
    ap.set_section(c.play_start(), c.play_end())
    ap.seek(0.1, true)
    check(not is_equal_approx(ap.current_animation_position, 0.1),
          "bare AnimationPlayer.seek() does not land where asked, outside the active section (landed at %.4f)"
          % ap.current_animation_position)
    c._seek_safe(0.1)
    check(is_equal_approx(ap.current_animation_position, 0.1),
          "but _seek_safe widens the section first, landing at the requested time (%.4f)"
          % ap.current_animation_position)
    c.queue_free()


## loop_play decides whether playback WRAPS; loop_smooth decides whether the
## wrap is BLENDED. They must vary independently.
func test_loop_play_separate_from_smooth() -> void:
    var c := ZenCanvas.new()
    c.duration = 2.0
    c.outro_start = 2.0
    c.loop_play = true
    c.loop_smooth = false
    c.loop_blend = 0.5
    ZenAnimBuilder.install(c)
    root.add_child(c)
    await process_frame
    var ap := c.animation_player()
    ap.seek(c.play_end() - 0.01, true)
    for _i in 5: await process_frame
    check(ap.is_playing(), "loop_play wraps instead of stopping")
    check(c.pose_looping_flag == false,
          "the live pose still carries loop_smooth=false even while loop_play wraps - the two vary independently")
    c.queue_free()


## The gallery's I / L toggles: play_intro=false starts in the body, and
## play_loop=false plays through once and holds instead of wrapping.
func test_viewer_intro_loop_toggles() -> void:
    var c := ZenCanvas.new()
    c.duration = 3.0
    c.intro_end = 1.0
    c.outro_start = 2.0
    c.loop_play = true
    c.play_intro = false
    ZenAnimBuilder.install(c)
    root.add_child(c)
    await process_frame
    var ap := c.animation_player()
    check(ap.current_animation_position >= c.play_start() - 0.001,
          "intro off: playback starts at intro_end (%.4f)" % ap.current_animation_position)
    check(c.skips_intro(), "intro off reports skips_intro()")
    c.queue_free()

    var d := ZenCanvas.new()
    d.duration = 3.0
    d.intro_end = 1.0
    d.outro_start = 2.0
    d.loop_play = true
    d.play_loop = false
    ZenAnimBuilder.install(d)
    root.add_child(d)
    await process_frame
    var ap2 := d.animation_player()
    ap2.seek(d.play_end() - 0.01, true)
    for _i in 6: await process_frame
    check(not ap2.is_playing(), "loop off: playback stops at the end instead of wrapping")
    check(d.is_finished(), "loop off: the canvas reports finished")
    check(d.pose_time >= d.play_end() - 0.02,
          "loop off: holds the last frame (t %.4f)" % d.pose_time)
    d.queue_free()


## ZenPixelShape: resize keeps the top-left, auto-outline follows the C
## boundary rule, bulk ink keeps the silhouette.
func test_pixel_shape() -> void:
    var s := ZenPixelShape.new()
    s.size = Vector2i(4, 3)
    check(s.cells.size() == 12, "cells sized w*h")
    for y in 3:
        for x in 4:
            s.set_cell(x, y, ZenPixelShape.FILL)
    s.set_cell(0, 0, ZenPixelShape.OUTLINE)
    s.size = Vector2i(2, 5)
    check(s.get_cell(0, 0) == ZenPixelShape.OUTLINE, "resize keeps the top-left cell")
    check(s.get_cell(1, 2) == ZenPixelShape.FILL, "resize keeps the overlapping region")
    check(s.get_cell(0, 4) == ZenPixelShape.EMPTY, "new rows are empty")

    var o := ZenPixelShape.new()
    o.size = Vector2i(5, 5)
    for y in range(1, 4):
        for x in range(1, 4):
            o.set_cell(x, y, ZenPixelShape.FILL)
    o.auto_outline()
    check(o.get_cell(2, 2) == ZenPixelShape.FILL, "auto-outline keeps an interior cell")
    check(o.get_cell(1, 1) == ZenPixelShape.OUTLINE and o.get_cell(3, 2) == ZenPixelShape.OUTLINE,
          "auto-outline promotes cells touching empty")
    check(o.count(ZenPixelShape.OUTLINE) == 8, "auto-outline reads from a copy (8 rim cells, got %d)"
          % o.count(ZenPixelShape.OUTLINE))
    o.convert_ink(ZenPixelShape.FILL)
    check(o.count(ZenPixelShape.FILL) == 9 and o.count(ZenPixelShape.OUTLINE) == 0,
          "bulk ink keeps the silhouette")
    check(ZenPixelShape.valid_name("page_icon") and not ZenPixelShape.valid_name("_x")
          and not ZenPixelShape.valid_name("a b") and not ZenPixelShape.valid_name(""),
          "shape name rules")


## A custom shape keeps its shape_name, its `shape_refs` list, and shape_at()
## follows the stepped track.
func test_custom_shape_resolution() -> void:
    var c: ZenCanvas = (load("res://anims/ma_prog/ma_prog_02_coding.tscn") as PackedScene).instantiate()
    var icon: ZenShape = null
    for e in c.elements():
        if e is ZenShape and (e as ZenShape).elem_name == "icon_ai": icon = e
    check(icon != null and icon.shape_kind == ZenShape.Kind.CUSTOM, "icon_ai is CUSTOM")
    if icon != null:
        check(icon.shape_name == "ai_icon_128" and icon.shape != null, "shape_name resolves to an asset")
        check(icon.shape_refs.size() >= 1, "shape_ref lines resolve into shape_refs")
        var sanim := _zen_anim(c)
        var sti := sanim.find_track(NodePath("%s:shape_id" % icon.name), Animation.TYPE_VALUE)
        var keys: Array = []
        for ki in sanim.track_get_key_count(sti) if sti >= 0 else 0:
            keys.append({"t": sanim.track_get_key_time(sti, ki),
                         "v": float(sanim.track_get_key_value(sti, ki))})
        var ok := not keys.is_empty()
        for k in keys:
            var v := float(k["v"])
            if v >= 0.0 and int(v) >= icon.shape_refs.size(): ok = false
        check(ok, "every shape_id key indexes shape_refs")
        if not keys.is_empty():
            var k0: Dictionary = keys[0]
            var at := icon.shape_at(float(k0["t"]))
            check(at != null and at == icon.shape_refs[int(float(k0["v"]))], "shape_at follows the track")
    c.free()

    var m := ZenShape.new()
    m.shape_kind = ZenShape.Kind.CUSTOM
    check(m.shape_at(0.0) == null, "no shape: shape_at is null (placeholder)")
    var mc := ZenCanvas.new()
    mc.add_child(m)
    m.tracks = {"shape_id": [{"t": 0.0, "v": ZenShape.SHAPE_MISSING, "ease": "linear"}]}
    ZenAnimBuilder.install(mc)
    m.shape = ZenPixelShape.new()
    check(m.shape_at(0.0) == null, "SHAPE_MISSING key draws the placeholder even with a rest shape")
    mc.free()


## Picking hits what is drawn, not the bounding box: a full-canvas diagonal
## line only near its stroke, a custom shape only on its non-empty cells.
func test_help_pages() -> void:
    var host := Control.new()
    host.size = Vector2(800, 300)
    root.add_child(host)
    var h := ZenHotkeyHelp.new()
    host.add_child(h)
    var rows: Array = []
    for i in 60: rows.append(["row %d" % i, "a long list"])
    h.show_pages("Test", [{"name": "A", "rows": [["zen_play", "play"]]},
        {"name": "B", "rows": rows}, {"name": "C", "rows": [["x", "y"]]}], 1)
    check(h.visible and h.page() == 1, "help: opens on the start page")
    check(h.size.y <= host.size.y, "help: a long page scrolls instead of leaving the screen")
    var key := func(code: Key, shift := false) -> InputEventKey:
        var ev := InputEventKey.new()
        ev.keycode = code
        ev.physical_keycode = code
        ev.shift_pressed = shift
        ev.pressed = true
        return ev
    check(h.handle_key(key.call(KEY_RIGHT)) and h.page() == 2, "help: Right flips to the next page")
    h.handle_key(key.call(KEY_TAB))
    check(h.page() == 0, "help: Tab wraps around")
    h.handle_key(key.call(KEY_TAB, true))
    check(h.page() == 2, "help: Shift+Tab goes back")
    check(h.handle_key(key.call(KEY_SPACE)) and h.visible, "help: other keys are swallowed while open")
    h.handle_key(key.call(KEY_H))
    check(not h.visible, "help: H closes it")
    check(not h.handle_key(key.call(KEY_SPACE)), "help: closed, keys pass through")
    host.free()


func test_stage_view() -> void:
    var st := ZenEditorStage.new()
    root.add_child(st)
    var c := ZenCanvas.new()               # 320 x 180
    ZenAnimBuilder.install(c)
    st.set_canvas(c)
    st.size = Vector2(1000, 600)
    # Fitted: the old framing - 3x (floor of min(984/320, 584/180)), centred.
    check(st.is_fitted(), "stage: starts fitted")
    check_near(st.zoom(), 3.0, "stage: fitted zoom is the largest whole scale")
    check(st.view_rect() == Rect2(Vector2(20, 30), Vector2(960, 540)), "stage: fitted rect centred")
    var mid := Vector2(500, 300)
    var at := st.to_canvas(mid)
    st.zoom_step(-1, mid)
    check(not st.is_fitted(), "stage: zooming leaves the fitted framing")
    check_near(st.zoom(), 2.0, "stage: one step out from 3x is 2x")
    check(st.to_canvas(mid).distance_to(at) < 0.001, "stage: zoom keeps the point under the cursor")
    var p := Vector2(-40, 210)             # off the canvas
    check(st.to_canvas(st.to_screen(p)).distance_to(p) < 0.001, "stage: screen/canvas round trip")
    check(Rect2(Vector2.ZERO, st.size).has_point(st.to_screen(p)), "stage: an off-canvas point is on screen")
    st.pan(Vector2(30, 0))
    check(st.to_canvas(mid).distance_to(at - Vector2(15, 0)) < 0.001, "stage: pan moves the view")
    st.fit_view()
    check(st.view_rect() == Rect2(Vector2(20, 30), Vector2(960, 540)), "stage: fit_view restores the framing")
    for i in 20: st.zoom_step(-1, mid)
    check_near(st.zoom(), 0.25, "stage: zoom out stops at the ladder's end")
    st.free()                              # the canvas goes with it


func test_element_hit() -> void:
    var c: ZenCanvas = (load("res://anims/main_menu.tscn") as PackedScene).instantiate()
    var by := {}
    for e in c.elements(): by[(e as ZenElement).elem_name] = e
    var line: ZenShape = by["line_diag_topleft"]
    var title: ZenText = by["title"]
    var t := 2.0
    check(line.bounds_px(t).has_point(Vector2(160, 30)), "the diagonal's box covers the title area")
    check(line.hit_px(line.center_px(t), t, 1.0), "line: hit on its stroke")
    check(not line.hit_px(Vector2(160, 30), t, 1.0), "line: no hit away from its stroke")
    check(title.hit_px(title.center_px(t), t, 1.0), "text: hit inside its box")
    check(not title.hit_px(title.bounds_px(t).end + Vector2(3, 3), t, 1.0), "text: no hit outside its box")
    c.free()

    var mc := ZenCanvas.new()
    var m := ZenShape.new()
    m.shape_kind = ZenShape.Kind.CUSTOM
    m.size_frac = Vector2(0.1, 0.1)         # 32 x 18 px at 320 x 180
    mc.add_child(m)
    ZenAnimBuilder.install(mc)
    var ps := ZenPixelShape.new()
    ps.size = Vector2i(2, 1)
    ps.set_cell(0, 0, ZenPixelShape.FILL)
    m.shape = ps
    var cp := m.center_px(0.0)
    check(m.hit_px(cp + Vector2(-8, 0), 0.0, 0.0), "custom: hit on a filled cell")
    check(not m.hit_px(cp + Vector2(8, 0), 0.0, 0.0), "custom: no hit on an empty cell")
    check(m.hit_px(cp + Vector2(1, 0), 0.0, 2.0), "custom: slop reaches the neighbouring cell")
    check(m.shows_at(0.0), "custom: shown at full alpha")
    m.color_base.a = 0.0
    m.outline_color_base.a = 0.0
    check(not m.shows_at(0.0), "custom: hidden at zero alpha")
    mc.free()


## Options: default pinned first, families A-Z case-insensitively, deduped;
## the search filter matches the default by its label.
func test_options_font_sort_filter() -> void:
    var f := ZenOptions.sorted_fonts(["beta", "Alpha", "gamma", "Alpha"])
    var src := "Source Sans 3 (bundled)"
    check(f == ["", src, "Alpha", "beta", "gamma"],
          "fonts sorted A-Z, default then bundled first, deduped (%s)" % [f])
    check(ZenOptions.filter_fonts(f, "") == [0, 1, 2, 3, 4], "empty search shows all")
    check(ZenOptions.filter_fonts(f, "ALP") == [2], "search is case-insensitive")
    check(ZenOptions.filter_fonts(f, "original") == [0], "default matches on its label")
    check(ZenOptions.filter_fonts(f, "source") == [1], "bundled Source Sans matches by name")


## The default font IS raylib's built-in bitmap font, rebuilt by
## tools/gen_raylib_font.gd. At its native 10px every glyph advances
## charsWidth[i] + 1 (raylib's one-pixel spacing), and a measured run drops
## the trailing pixel exactly as MeasureTextEx does - that is what puts text
## where the original editor put it.
func test_raylib_font() -> void:
    var f := load(ZenText.DEFAULT_FONT_PATH) as FontFile
    check(f != null and f.fixed_size == 10, "default font is the 10px raylib bitmap font")
    if f == null: return
    check(ZenTextMetrics.is_bitmap(f), "raylib font is recognised as a bitmap font")
    check(not ZenTextMetrics.is_bitmap(load("res://addons/zen/fonts/SourceSans3-Regular.ttf")),
          "a TTF is not a bitmap font")
    # charsWidth[] samples, straight from raylib's rtext.c.
    for pair in [[" ", 3], ["!", 1], ["A", 6], ["M", 7], ["i", 1], ["g", 5], ["~", 4]]:
        var adv := f.get_string_size(pair[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
        check_near(adv, float(pair[1]) + 1.0, "'%s' advances charsWidth + 1" % pair[0])
    # "Hello": 6+5+2+2+5 glyph pixels + 4 gaps = 24, as MeasureTextEx reports.
    check_near(ZenTextMetrics.measure("Hello", 10.0, f).x, 24.0,
               "measure matches raylib MeasureTextEx at 10px")
    check_near(ZenTextMetrics.measure("Hello", 40.0, f).x, 96.0,
               "and scales linearly with size, like raylib's")
    # THE STUTTER GUARD: an animated size must widen the text continuously.
    # Laying out at round(size_px) stepped a whole pixel at a time, so text
    # that grew while moving (fangs_test's title) jittered about its centre.
    check_near(ZenTextMetrics.measure("NeZvers", 40.4, f).x,
               ZenTextMetrics.measure("NeZvers", 40.0, f).x * 40.4 / 40.0,
               "bitmap width is continuous in size, not stepped per pixel")
    var ttf: Font = load("res://addons/zen/fonts/SourceSans3-Regular.ttf")
    var w0 := ZenTextMetrics.measure("NeZvers", 40.0, ttf).x
    var w1 := ZenTextMetrics.measure("NeZvers", 40.3, ttf).x
    check(w1 > w0 and w1 < w0 * 1.02, "vector width grows continuously within a size bucket")
    # has_char() reports false for every glyph of a data-less FontFile, so the
    # Latin-1 half (glyphs 128..255) is checked by its advance instead.
    check_near(f.get_string_size("é", HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x, 6.0,
               "Latin-1 glyphs are present ('é' is charsWidth[201] + 1)")


## Gallery multi-selection rules: plain pick is single, Shift is a range from
## the anchor, Ctrl toggles, and rows below `first` are never marked.
func test_list_selection() -> void:
    var s := ZenListSelection.new(1)
    s.resize(6)
    s.pick(0)
    check(s.rows().is_empty() and s.shows(0), "the command row shows selected but is not marked")
    s.pick(2)
    s.pick(4, true)
    check(s.rows() == [2, 3, 4], "shift extends a range from the anchor (%s)" % [s.rows()])
    s.pick(0, true)
    check(s.rows() == [1, 2], "a range never takes the command row (%s)" % [s.rows()])
    s.pick(5, false, true)
    check(s.rows() == [1, 2, 5] and s.is_multi(), "ctrl adds a row")
    s.pick(2, false, true)
    check(s.rows() == [1, 5], "ctrl removes a row")
    s.move(-1, true)
    check(s.cursor == 1 and s.rows() == [1, 2], "shift+up extends from the ctrl anchor (%s)" % [s.rows()])
    s.resize(2)
    check(s.rows() == [1], "rows past a shrunk list drop out")
    s.collapse()
    check(not s.is_multi() and s.rows() == [1], "collapse keeps only the cursor")


## Folders are subdirectories of an anims root; a scene's name stays its id.
func test_scene_folders() -> void:
    var paths := ZenSceneOps.scene_paths()
    check(String(paths.get("sig_code", "")).ends_with("/signal_demo/sig_code.tscn"),
          "scene_paths finds scenes in a folder")
    check(ZenSceneOps.folder_of("sig_code") == "signal_demo" and ZenSceneOps.folder_of("main_menu") == "",
          "folder_of: the folder, or empty at the top level")
    check(ZenSceneOps.folders().has("signal_demo"), "folders() lists signal_demo")
    check(not ZenSceneOps.is_name_free("sig_code"), "names stay unique across folders")

    var root := ZenSceneOps.write_root()
    var f := "zz_test_folder"
    var nm := "zz_test_folder_scene"
    check(ZenSceneOps.make_folder(f) == OK and ZenSceneOps.folders().has(f), "make_folder adds an empty folder")
    var c := ZenSceneOps.new_canvas(nm)
    check(ZenSceneOps.save(c, nm, f) == "%s/%s/%s.tscn" % [root, f, nm], "a new scene saves into its folder")
    check(ZenSceneOps.save(c, nm) == "%s/%s/%s.tscn" % [root, f, nm], "a later save stays in place")
    check(ZenSceneOps.delete_folder(f) == ERR_BUSY, "a folder holding scenes is not deleted")
    check(ZenSceneOps.move(nm, "") == OK and ZenSceneOps.folder_of(nm) == "", "move to the top level")
    check(ZenSceneOps.move(nm, f) == OK and ZenSceneOps.folder_of(nm) == f, "move back into the folder")
    check(ZenSceneOps.rename_folder(f, f + "2") == OK and ZenSceneOps.folder_of(nm) == f + "2",
          "renaming a folder carries its scenes")
    check(ZenSceneOps.rename_folder(f + "2", "signal_demo") == ERR_ALREADY_EXISTS,
          "a folder cannot be renamed onto another")
    check(ZenSceneOps.duplicate_scene(nm, nm + "_b") == OK and ZenSceneOps.folder_of(nm + "_b") == f + "2",
          "a duplicate lands next to its source")
    for n in [nm, nm + "_b"]:
        DirAccess.remove_absolute(ProjectSettings.globalize_path(ZenSceneOps.path_of(n)))
    check(ZenSceneOps.scenes_in(f + "2").is_empty(), "the folder is empty again")
    DirAccess.remove_absolute(ProjectSettings.globalize_path("%s/%s2" % [root, f]))
    check(not ZenSceneOps.folders().has(f + "2"), "and gone")
    c.free()

    var es := [{"name": "main_menu", "folder": ""}, {"name": "sig_code", "folder": "signal_demo"},
               {"name": "sig_follow", "folder": "signal_demo"}]
    check(ZenSceneOps.filter(es, "") == [0, 1, 2], "an empty search matches everything")
    check(ZenSceneOps.filter(es, "FOLL") == [2], "search matches names, case-insensitively")
    check(ZenSceneOps.filter(es, "demo") == [1, 2], "search matches the folder too")


## The gallery list: folders fold, the search narrows, folder rows are
## never part of a selection.
func test_gallery_folders() -> void:
    var saved := ZenSettings.open_folders()
    var g: Node = (load("res://zen_gallery.tscn") as PackedScene).instantiate()
    root.add_child(g)
    await process_frame
    g._open = {}
    g._build_list()
    var top := 0
    for e in g._entries: if String(e["folder"]) == "": top += 1
    var nf := ZenSceneOps.folders().size()
    var sd := ZenSceneOps.folders().find("signal_demo")
    check(g._rows.size() == top + nf and g._folder_row(sd) == "signal_demo",
          "collapsed: the folder rows, then the top-level animations")
    check(String(g._list.get_child(sd).text).contains("signal_demo  (9)"), "the folder row counts its animations")
    g._select(sd)
    check(g._marked_anims().is_empty() and String(g._info.text).contains("folder"),
          "a folder row selects nothing and describes the folder")
    g._play(sd)
    check(g._playing == null, "playing a folder row does nothing")
    g._toggle_folder("signal_demo")
    check(g._rows.size() == top + nf + 9 and g._entry_at(sd + 1)["name"] == "sig_code", "expanding shows its nine")
    check(ZenSettings.open_folders() == ["signal_demo"], "the open folder is remembered")
    g._select(sd)
    g._select(sd + 3, true)
    check(g._marked_anims().size() == 3, "a range over the folder row takes only animations")
    g._select(sd + 2)
    g._fold_cursor(false)
    check(g._rows.size() == top + nf and g._sel == sd, "LEFT inside a folder folds it, cursor on the folder")

    g._search.text = "seek"
    g._on_search_changed()
    check(g._rows.size() == 2 and g._cur_entry().get("name", "") == "sig_release_seek",
          "a search shows the match under its (opened) folder, cursor on it")
    check(String(g._anim_header.text).contains("1 of"), "the header counts the matches")
    g._search.text = "zzzz"
    g._on_search_changed()
    check(g._rows.is_empty() and String(g._info.text).contains("no animation"), "no match: an empty list says so")
    g._search.text = ""
    g._on_search_changed()
    check(g._rows.size() == top + nf, "clearing the search restores the folded view")
    g.queue_free()
    await process_frame
    ZenSettings.set_open_folders(saved)


## The gallery's top bar and right-click menus come from one action table
## per context; a right-click across a folder and an animation offers a move
## and keeps the selection, since the selection is what moves.
func test_gallery_actions() -> void:
    var saved := ZenSettings.open_folders()
    var g: Node = (load("res://zen_gallery.tscn") as PackedScene).instantiate()
    root.add_child(g)
    await process_frame
    var labels := func(acts: Array) -> Array:
        return acts.filter(func(a): return not (a as Dictionary).is_empty()) \
                   .map(func(a): return String(a["label"]))
    g._open = {}
    g._build_list()
    var nf := ZenSceneOps.folders().size()
    var sd := ZenSceneOps.folders().find("signal_demo")
    var first := String(g._entry_at(nf)["name"])
    g._select(nf)
    var al: Array = labels.call(g._actions())
    check(al.has("Play") and al.has("Rename") and al.has("Move..."), "an animation's bar")
    check(g._bar_context.get_child_count() == g._actions().size(), "the bar shows a button per action")
    check(labels.call(g._global_actions()).has("New folder"), "the right half always offers a new folder")
    var tipped := func() -> bool:
        var ok := true
        for b in g._bar_context.get_children() + g._bar_global.get_children():
            if b is Button: ok = ok and b is ZenTipButton and String(b.tip["text"]) != ""
        return ok
    check(tipped.call(), "every bar button explains itself")
    var qa: Dictionary = g._actions().filter(func(a): return a.get("label", "") == "Queue")[0]
    check(String(qa["note"]) == "The queue is empty.", "Queue's tooltip says the queue is empty")
    g._queue_current()
    qa = g._actions().filter(func(a): return a.get("label", "") == "Queue")[0]
    check(String(qa["note"]).contains(first) and String(g._status.tip["note"]).contains(first),
          "after queuing, the Queue and status tooltips list it")
    g._export_queue.clear()
    var tt: Control = ZenTooltip.build(ZenUI.action_tip(qa))
    var texts: Array = []
    for l in tt.get_child(0).get_children(): texts.append(String((l as Label).text))
    check(texts.size() == 4 and texts[1].contains("export queue") and texts[3].begins_with("Key: "),
          "a tooltip: title, what it does, the live note, the keys")
    tt.free()

    g._select(sd)
    var fa: Array = g._actions()
    check(labels.call(fa)[0] == "Open", "a closed folder's bar opens it")
    var del: Dictionary = fa.filter(func(a): return a.get("label", "") == "Delete")[0]
    check(not bool(del["enabled"]), "a folder holding animations cannot be deleted")
    check(String(del["note"]).begins_with("Holds 9 animations"), "and its tooltip says why")
    check(tipped.call(), "a folder's bar buttons explain themselves")

    var m: Array = g._row_menu(nf)
    check(String(m[0]["label"]) == "Move %s into signal_demo" % first and g._sel == sd,
          "folder selected, right-click an animation: move it in, the folder stays selected")
    g._select(nf)
    g._select(nf + 1, true)
    m = g._row_menu(sd)
    check(String(m[0]["label"]) == "Move 2 animations into signal_demo" and g._marked_anims().size() == 2,
          "two animations selected, right-click a folder: move them in, still selected")
    check(String(labels.call(g._actions())[0]).begins_with("Export 2"), "a multi-selection's bar")
    check(tipped.call(), "a multi-selection's bar buttons explain themselves")
    m = g._row_menu(nf)
    check(String(m[0]["label"]).begins_with("Export 2") and g._anim_sel.is_multi(),
          "right-click inside a multi-selection acts on all of it")
    g._row_menu(nf + 2)
    check(g._sel == nf + 2 and not g._anim_sel.is_multi(), "a plain right-click selects that row")

    var nm := ZenSceneOps.unique_name("zz_gallery_tmp")
    var f := "zz_gallery_dir"
    var c := ZenSceneOps.new_canvas(nm)
    ZenSceneOps.save(c, nm)
    c.free()
    ZenSceneOps.make_folder(f)
    g._reselect(nm)
    g._move_into(f, [nm])
    check(ZenSceneOps.folder_of(nm) == f and String(g._cur_entry().get("name", "")) == nm,
          "move into a folder: it opens and the cursor follows")
    var row: int = g._row_of_folder(f)
    m = g._row_menu(g._sel)
    var sub: Dictionary = m.filter(func(a): return a.get("label", "") == "Move to")[0]
    check(labels.call(sub["sub"]).has("top level") and not labels.call(sub["sub"]).has(f),
          "Move to lists the top level and the other folders")
    g._move_into("", [nm])
    check(ZenSceneOps.folder_of(nm) == "" and row >= 0, "and back to the top level")
    DirAccess.remove_absolute(ProjectSettings.globalize_path(ZenSceneOps.path_of(nm)))
    DirAccess.remove_absolute(ProjectSettings.globalize_path("%s/%s" % [ZenSceneOps.write_root(), f]))

    g._set_section(1)
    g._select_asset(0)
    check(labels.call(g._actions()) == ["Create"], "the new-asset row's bar")
    g.queue_free()
    await process_frame
    ZenSettings.set_open_folders(saved)


## The gallery's selection drives export and delete: a multi-selection
## becomes the export chain, and DEL lists exactly the selected files.
func test_gallery_multi_select() -> void:
    var g: Node = (load("res://zen_gallery.tscn") as PackedScene).instantiate()
    root.add_child(g)
    await process_frame
    # The folder rows come first: start on the first animation after them.
    g._open = {}
    g._build_list()
    var nf := ZenSceneOps.folders().size()
    g._select(nf)
    g._select(nf + 2, true)
    check(g._marked_anims().size() == 3, "shift+click marks a range of animations")
    check(String(g._hint.text).contains("export 3"), "the footer offers the selection's keys")
    g._ask_delete()
    var listed: String = g._confirm.dialog_text
    var ok := true
    for nm in g._marked_anims(): ok = ok and listed.contains("res://anims/%s.tscn" % nm)
    check(ok and g._confirm.visible, "delete asks first, listing every scene")
    g._confirm.hide()
    g._open_export()
    check(g._export_dialog.get_chain() == g._marked_anims(), "export opens with the selection as the chain")
    g._close_export()
    g._back()
    check(not g._anim_sel.is_multi() and g.is_inside_tree(), "ESC clears a multi-selection before quitting")
    g._set_section(1)
    g._select_asset(1)
    g._select_asset(2, false, true)
    check(g._marked_assets().size() == 2 and String(g._info.text).contains("2 assets selected"),
          "ctrl+click marks several assets")
    g.queue_free()
    await process_frame


## The shape editor end to end, headless: a stroke is one undo step, redo
## restores it, line/rect/flood tools touch the right cells, and Save
## publishes into the loaded resource so live users redraw.
func test_shape_editor() -> void:
    check(ZenPixelCanvas.line_cells(Vector2i(0, 0), Vector2i(3, 0)).size() == 4, "line is inclusive")
    check(ZenPixelCanvas.rect_cells(Vector2i(0, 0), Vector2i(2, 2)).size() == 8, "rect is its outline")

    var ed: ZenShapeEditor = (load("res://tools/zen_shape_editor.tscn") as PackedScene).instantiate()
    root.add_child(ed)
    await process_frame
    await ed.open("")
    var cv: ZenPixelCanvas = ed._canvas
    var sh: ZenPixelShape = ed._shape
    check(sh != null and sh.size == ZenShapeEditor.NEW_SIZE, "a blank shape opens at the default size")
    check(ed._dirty(), "an unsaved new shape is dirty")

    cv.tool = ZenPixelCanvas.Tool.PEN
    cv.ink = ZenPixelShape.FILL
    cv._begin(Vector2i(2, 2), ZenPixelShape.FILL)
    cv._end(Vector2i(2, 2))
    check(sh.get_cell(2, 2) == ZenPixelShape.FILL, "pen paints")
    ed._do_undo()
    check(sh.get_cell(2, 2) == ZenPixelShape.EMPTY, "one stroke is one undo step")
    ed._do_redo()
    check(sh.get_cell(2, 2) == ZenPixelShape.FILL, "redo restores the stroke")

    cv.mirror_x = true
    cv._begin(Vector2i(0, 0), ZenPixelShape.OUTLINE)
    cv._end(Vector2i(0, 0))
    check(sh.get_cell(sh.size.x - 1, 0) == ZenPixelShape.OUTLINE, "mirror X paints the opposite cell")
    cv.mirror_x = false

    cv.tool = ZenPixelCanvas.Tool.FILL
    cv._begin(Vector2i(5, 5), ZenPixelShape.FILL)
    var filled := sh.count(ZenPixelShape.FILL)
    check(filled == sh.size.x * sh.size.y - 2, "flood fills the connected empty region (%d)" % filled)
    ed._do_undo()
    check(sh.count(ZenPixelShape.FILL) == 1, "flood fill undoes in one step")

    ed._size_w.value = 10
    check(sh.size.x == 10, "the size box resizes")
    ed._do_undo()
    check(sh.size.x == ZenShapeEditor.NEW_SIZE.x, "resize undoes")

    # Save publishes into an already-loaded instance.
    var nm := "zz_test_tmp"
    ed._name = nm
    ed._save()
    var live := ZenAssets.load_shape(nm)
    check(live != null and live.get_cell(2, 2) == ZenPixelShape.FILL, "save writes the asset")
    check(not ed._dirty(), "saved: no longer dirty")
    var hits := [0]
    live.changed.connect(func(): hits[0] += 1)
    sh = ed._shape
    check(sh != live, "after save the editor works on a fresh copy")
    cv.tool = ZenPixelCanvas.Tool.PEN
    cv._begin(Vector2i(4, 4), ZenPixelShape.FILL)
    cv._end(Vector2i(4, 4))
    check(live.get_cell(4, 4) == ZenPixelShape.EMPTY, "edits stay in the working copy until save")
    ed._save()
    check(live.get_cell(4, 4) == ZenPixelShape.FILL and hits[0] > 0,
          "save updates the loaded resource and emits changed")
    ZenAssets.delete_shape(nm)
    check(not ZenAssets.shape_paths().has(nm), "delete removes the asset")
    ed.queue_free()



# ---------------------------------------------------------------------------
#  Authoring core (addons/zen/authoring)
# ---------------------------------------------------------------------------

## A code-built canvas with one shape keyed by `tracks`, installed.
func _authoring_canvas(tracks: Dictionary) -> ZenCanvas:
    var c := ZenCanvas.new()
    c.live_playback = false
    c.duration = 2.0
    var s := ZenShape.new()
    s.name = "box"
    s.elem_name = "box"
    s.tracks = tracks
    c.add_child(s)
    s.owner = c
    ZenAnimBuilder.install(c)
    return c


## Does `prop` on `c`'s box sample the same as a fresh bake of `keys`?
func _samples_like_bake(c: ZenCanvas, prop: String, keys: Array, what: String) -> void:
    var ref := _authoring_canvas({prop: keys})
    var a: ZenElement = c.get_node("box")
    var b: ZenElement = ref.get_node("box")
    var worst := 0.0
    for i in 201:
        var t := 2.0 * float(i) / 200.0
        worst = maxf(worst, absf(a.track_or_base(prop, t, 0.0) - b.track_or_base(prop, t, 0.0)))
    check(worst < 1e-5, "%s (worst %.7f)" % [what, worst])
    ref.free()


func _k(t: float, v: float, e := "linear") -> Dictionary:
    return {"t": t, "v": v, "ease": e}


## {t, v, ease} is split across the bezier and a discrete ease track; fit keys
## a non-cubic ease adds are bezier-only, and read back as one authored key.
func test_ease_tracks() -> void:
    var keys := [_k(0.0, 0.0), _k(1.0, 1.0, "bounceOut"), _k(1.0, 0.5), _k(1.5, 0.2, "cubicIn")]
    var c := _authoring_canvas({"pos_x": keys, "shape_id": [_k(0.0, 0.0), _k(1.0, 1.0)],
        "color": [{"t": 0.0, "c": Color(1, 0, 0), "ease": "linear"},
                  {"t": 1.0, "c": Color(0, 0, 1), "ease": "quadOut"}]})
    var anim := _zen_anim(c)
    var et := anim.find_track(NodePath("box:zen_ease_pos_x"), Animation.TYPE_VALUE)
    check(et >= 0, "a keyed scalar gets an ease track")
    check(et >= 0 and anim.track_get_key_count(et) == 4, "one ease key per authored key")
    var bt := anim.find_track(NodePath("box:pos_x"), Animation.TYPE_BEZIER)
    check(anim.track_get_key_count(bt) > 4, "bounceOut is fit with extra bezier keys")
    check(anim.find_track(NodePath("box:zen_ease_color"), Animation.TYPE_VALUE) >= 0,
          "one ease track per colour prop")
    check(anim.find_track(NodePath("box:zen_ease_shape_id"), Animation.TYPE_VALUE) < 0,
          "stepped props have no ease track")
    check(not c.timeline().paths().has("box:zen_ease_pos_x"), "the timeline does not sample ease tracks")

    var el: ZenElement = c.get_node("box")
    var got := ZenKeyOps.keys(c, el, "pos_x")
    check(got.size() == 4, "keys() reads back only the authored keys (%d)" % got.size())
    var eases := got.map(func(k): return k["ease"])
    check(eases == ["linear", "bounceOut", "linear", "cubicIn"], "eases read back: %s" % [eases])
    check_near(float(got[1]["v"]), 1.0, "authored value read back")
    check_near(float(got[2]["t"]), 1.0 + ZenCurveBake.STEP_EPS, "an instant step reads back nudged", 1e-5)
    check(ZenKeyOps.keyed_props(c, el) == ["pos_x", "shape_id", "color"],
          "keyed_props lists every keyed prop: %s" % [ZenKeyOps.keyed_props(c, el)])
    var ck := ZenKeyOps.keys(c, el, "color")
    check(ck.size() == 2 and ck[1]["ease"] == "quadOut" and (ck[1]["v"] as Color).is_equal_approx(Color(0, 0, 1)),
          "colour keys read back as one Color per key")
    check(el.get("zen_ease_pos_x") != null, "the ease track path resolves on the node")
    c.free()


## Every op leaves the track sampling exactly like a fresh bake of the
## resulting key list - i.e. rebaking only the touched segments is lossless.
func test_key_ops_rebake() -> void:
    var keys := [_k(0.0, 0.0), _k(0.5, 1.0, "elasticOut"), _k(1.0, 0.0, "bounceOut"), _k(1.8, 0.5, "sineInOut")]
    var c := _authoring_canvas({"pos_x": keys.duplicate(true)})
    var el: ZenElement = c.get_node("box")
    _samples_like_bake(c, "pos_x", keys, "freshly installed track matches its bake")

    ZenKeyOps.set_ease(c, el, "pos_x", 2, "backOut")
    keys[2]["ease"] = "backOut"
    _samples_like_bake(c, "pos_x", keys, "set_ease rebakes the segment")

    ZenKeyOps.set_value(c, el, "pos_x", 1, 0.25)
    keys[1]["v"] = 0.25
    _samples_like_bake(c, "pos_x", keys, "set_value rebakes both neighbouring segments")

    ZenKeyOps.move(c, el, "pos_x", 2, 1.2)
    keys[2]["t"] = 1.2
    _samples_like_bake(c, "pos_x", keys, "move rebakes both neighbouring segments")
    check(ZenKeyOps.move(c, el, "pos_x", 2, 5.0) == 2 and
          float(ZenKeyOps.keys(c, el, "pos_x")[2]["t"]) < 1.8, "a move is clamped short of its neighbour")
    ZenKeyOps.move(c, el, "pos_x", 2, 1.2)

    var at := ZenKeyOps.insert(c, el, "pos_x", 1.5, 0.9, "quadIn")
    check(at == 3, "insert lands in time order (%d)" % at)
    keys.insert(3, _k(1.5, 0.9, "quadIn"))
    _samples_like_bake(c, "pos_x", keys, "insert splits a segment")
    check(ZenKeyOps.insert(c, el, "pos_x", 1.5, 0.7) == 3 and ZenKeyOps.keys(c, el, "pos_x").size() == 5,
          "insert at an existing key sets it instead of adding one")
    keys[3]["v"] = 0.7
    _samples_like_bake(c, "pos_x", keys, "insert-as-set rebakes")

    ZenKeyOps.remove(c, el, "pos_x", 1)
    keys.remove_at(1)
    _samples_like_bake(c, "pos_x", keys, "remove merges two segments into the next key's ease")
    ZenKeyOps.remove(c, el, "pos_x", 0)
    keys.remove_at(0)
    _samples_like_bake(c, "pos_x", keys, "removing the first key")

    for i in range(ZenKeyOps.keys(c, el, "pos_x").size() - 1, -1, -1):
        ZenKeyOps.remove(c, el, "pos_x", i)
    var anim := _zen_anim(c)
    check(anim.find_track(NodePath("box:pos_x"), Animation.TYPE_BEZIER) < 0 and
          anim.find_track(NodePath("box:zen_ease_pos_x"), Animation.TYPE_VALUE) < 0,
          "removing the last key drops the track and its ease track")
    check(not el.has_track("pos_x"), "the element sees the track gone")

    # Auto-key: the first key also pins the base pose at 0.
    el.pos_frac.x = 0.3
    ZenKeyOps.key_at_playhead(c, el, "pos_x", 1.0, 0.8)
    var ak := ZenKeyOps.keys(c, el, "pos_x")
    check(ak.size() == 2 and is_zero_approx(float(ak[0]["t"])) and is_equal_approx(float(ak[0]["v"]), 0.3),
          "auto-key on an untracked prop keys the base pose at 0 first")
    check_near(el.prop("pos_x", 1.0, 0.0), 0.8, "auto-keyed value plays")
    c.free()


## A track hand-shaped in Godot (no ease track) reads as raw: editing one
## segment leaves the other segments' handles exactly as they were.
func test_key_ops_raw_segments() -> void:
    var c := _authoring_canvas({})
    var el: ZenElement = c.get_node("box")
    var anim := _zen_anim(c)
    var tr := anim.add_track(Animation.TYPE_BEZIER)
    anim.track_set_path(tr, NodePath("box:w"))
    anim.bezier_track_insert_key(tr, 0.0, 0.1, Vector2(-0.1, 0), Vector2(0.2, 0.3))
    anim.bezier_track_insert_key(tr, 1.0, 0.2, Vector2(-0.3, -0.1), Vector2(0.25, 0.05))
    anim.bezier_track_insert_key(tr, 2.0, 0.4, Vector2(-0.2, 0.1), Vector2(0.1, 0))
    c.timeline_dirty()
    var ks := ZenKeyOps.keys(c, el, "w")
    check(ks.size() == 3 and ks.all(func(k): return k["ease"] == ZenKeyOps.RAW),
          "a bezier with no ease track is all-authored, ease raw")
    var before := el.track_or_base("w", 0.5, 0.0)
    ZenKeyOps.set_value(c, el, "w", 2, 0.6)
    var t2 := _track_of(anim, "box:w")
    check(anim.bezier_track_get_key_out_handle(t2, 0) == Vector2(0.2, 0.3) and
          anim.bezier_track_get_key_in_handle(t2, 1) == Vector2(-0.3, -0.1),
          "an untouched raw segment keeps its hand-made handles")
    check_near(el.track_or_base("w", 0.5, 0.0), before, "so it samples exactly as before")
    check(anim.find_track(NodePath("box:zen_ease_w"), Animation.TYPE_VALUE) >= 0,
          "the first Zen edit adds the ease track")

    ZenKeyOps.set_ease(c, el, "w", 2, "linear")
    check_near(el.track_or_base("w", 1.5, 0.0), 0.4, "picking an ease rebakes a raw segment")
    ZenKeyOps.move(c, el, "w", 1, 0.5)
    var t3 := _track_of(anim, "box:w")
    var h := anim.bezier_track_get_key_out_handle(t3, 0)
    check_near(h.x, 0.5 / 3.0, "a moved raw segment's handle reach follows the new span")
    check_near(h.y / h.x, 1.5, "and keeps its slope")
    c.free()


func _track_of(anim: Animation, path: String) -> int:
    return anim.find_track(NodePath(path), Animation.TYPE_BEZIER)


func test_key_ops_color_and_stepped() -> void:
    var c := _authoring_canvas({})
    var el: ZenElement = c.get_node("box")
    ZenKeyOps.insert(c, el, "color", 0.0, Color(1, 0, 0), "linear")
    ZenKeyOps.insert(c, el, "color", 1.0, Color(0, 1, 0), "quadOut")
    var anim := _zen_anim(c)
    check(_track_of(anim, "box:color:r") >= 0 and _track_of(anim, "box:color:b") >= 0,
          "keying a colour creates all three channels")
    var mid := el.prop_color("color", 0.5, Color.WHITE, 1.0)
    check_near(mid.r, 0.25, "colour channels follow the shared ease", 0.002)
    check_near(mid.g, 0.75, "...every channel", 0.002)
    ZenKeyOps.set_ease(c, el, "color", 1, "linear")
    check_near(el.prop_color("color", 0.5, Color.WHITE, 1.0).g, 0.5, "set_ease reaches all channels")

    ZenKeyOps.insert(c, el, "shape_id", 0.0, 0.0)
    ZenKeyOps.insert(c, el, "shape_id", 1.0, 2.0)
    check(ZenKeyOps.keys(c, el, "shape_id").size() == 2, "stepped keys insert")
    check_near(el.prop("shape_id", 0.9, -1.0), 0.0, "stepped holds")
    ZenKeyOps.move(c, el, "shape_id", 1, 0.5)
    check_near(el.prop("shape_id", 0.6, -1.0), 2.0, "stepped key moves")
    ZenKeyOps.remove(c, el, "shape_id", 1)
    ZenKeyOps.remove(c, el, "shape_id", 0)
    check(not ZenKeyOps.has_track(c, el, "shape_id"), "removing every stepped key drops the track")
    c.free()


## Several keys of one prop move in one write: in order, each keeping its
## ease, clamped only against neighbours that are not moving with it.
func test_key_set_times() -> void:
    var keys := [_k(0.0, 0.0), _k(0.5, 1.0, "elasticOut"), _k(1.0, 0.0, "bounceOut"), _k(1.8, 0.5, "sineInOut")]
    var c := _authoring_canvas({"pos_x": keys.duplicate(true)})
    var el: ZenElement = c.get_node("box")
    # Keys 1 and 2 right by 0.4: key 2 passes key 1's old time, which a
    # left-to-right order would have clamped.
    ZenKeyOps.set_times(c, el, "pos_x", [1, 2], [0.9, 1.4])
    keys[1]["t"] = 0.9
    keys[2]["t"] = 1.4
    _samples_like_bake(c, "pos_x", keys, "set_times rebakes the moved segments")
    var got := ZenKeyOps.keys(c, el, "pos_x")
    check(got.map(func(k): return k["ease"]) == ["linear", "elasticOut", "bounceOut", "sineInOut"],
          "set_times keeps each key's ease")
    # Left by 1.0: key 1 clamps at key 0, key 2 then clamps at key 1.
    ZenKeyOps.set_times(c, el, "pos_x", [1, 2], [-0.1, 0.4])
    got = ZenKeyOps.keys(c, el, "pos_x")
    check(float(got[1]["t"]) > 0.0 and float(got[2]["t"]) > float(got[1]["t"]) and
          float(got[2]["t"]) <= 0.4 + 1e-4, "set_times clamps against unmoved neighbours, keeps order")
    # Stretch x2 around key 0 of a fresh layout.
    ZenKeyOps.set_times(c, el, "pos_x", [1, 2, 3], [0.3, 0.6, 0.9])
    ZenKeyOps.set_times(c, el, "pos_x", [1, 2, 3], [0.6, 1.2, 1.8])
    got = ZenKeyOps.keys(c, el, "pos_x")
    check_near(float(got[1]["t"]), 0.6, "stretch key 1", 1e-4)
    check_near(float(got[3]["t"]), 1.8, "stretch key 3 (moved right-most first)", 1e-4)

    ZenKeyOps.insert(c, el, "color", 0.0, Color(1, 0, 0), "linear")
    ZenKeyOps.insert(c, el, "color", 1.0, Color(0, 1, 0), "linear")
    ZenKeyOps.set_times(c, el, "color", [1], [0.5])
    check_near(el.prop_color("color", 0.5, Color.WHITE, 1.0).g, 1.0, "set_times moves every colour channel", 0.002)
    ZenKeyOps.insert(c, el, "shape_id", 0.0, 0.0)
    ZenKeyOps.insert(c, el, "shape_id", 1.0, 2.0)
    ZenKeyOps.set_times(c, el, "shape_id", [1], [0.4])
    check_near(el.prop("shape_id", 0.45, -1.0), 2.0, "set_times moves a stepped key")
    c.free()


## A hand-shaped raw segment nowhere near the moved keys survives set_times.
func test_key_set_times_keeps_raw() -> void:
    var c := _authoring_canvas({})
    var el: ZenElement = c.get_node("box")
    var anim := _zen_anim(c)
    var tr := anim.add_track(Animation.TYPE_BEZIER)
    anim.track_set_path(tr, NodePath("box:w"))
    anim.bezier_track_insert_key(tr, 0.0, 0.1, Vector2(-0.1, 0), Vector2(0.2, 0.3))
    anim.bezier_track_insert_key(tr, 1.0, 0.2, Vector2(-0.3, -0.1), Vector2(0.25, 0.05))
    anim.bezier_track_insert_key(tr, 2.0, 0.4, Vector2(-0.2, 0.1), Vector2(0.1, 0))
    anim.bezier_track_insert_key(tr, 3.0, 0.1, Vector2(-0.2, 0.1), Vector2(0.1, 0))
    c.timeline_dirty()
    var before := el.track_or_base("w", 0.5, 0.0)
    ZenKeyOps.set_times(c, el, "w", [3], [2.6])
    var t2 := _track_of(anim, "box:w")
    check(anim.bezier_track_get_key_out_handle(t2, 0) == Vector2(0.2, 0.3) and
          anim.bezier_track_get_key_in_handle(t2, 1) == Vector2(-0.3, -0.1),
          "set_times leaves an untouched raw segment's handles alone")
    check_near(el.track_or_base("w", 0.5, 0.0), before, "so it samples exactly as before")
    c.free()


func test_elem_ops() -> void:
    var c := _authoring_canvas({"pos_x": [_k(0.0, 0.1), _k(1.0, 0.9)]})
    # A signal referencing box, so rename/remove have something to rewrite.
    var bus := ZenSignalBus.new()
    bus.name = "Signals"
    bus.signals_data = [{"name": "go", "length": 1.0, "targets": [
        {"elem": "box", "prop": "alpha", "keys": [_k(1.0, 0.0)]}],
        "seq_targets": [], "pos_params": []}]
    c.add_child(bus)
    bus.owner = c
    ZenAnimBuilder.install(c)

    var t := ZenElemOps.add(c, "text")
    check(t is ZenText and t.elem_name == "text" and (t as ZenText).text == "TEXT", "add text with defaults")
    check_near(t.pos_frac.y, 0.4, "a new text sits at y 0.4 (AnimElemInit)")
    var g := ZenElemOps.add(c, "global")
    check(ZenElemOps.halves(c, g).size() == 2, "a global is added as two nodes")
    check(ZenElemOps.rows(c).size() == 3, "rows list a global once (%d)" % ZenElemOps.rows(c).size())
    var s2 := ZenElemOps.add(c, "shape", "box")
    check(s2.elem_name == "box_2", "names are made unique (%s)" % s2.elem_name)
    check(c.get_children().back() is AnimationPlayer or c.get_children().back() is ZenSignalBus,
          "new elements go before the bus and the player")

    var box: ZenElement = c.get_node("box")
    check(ZenElemOps.rename(c, box, "hero"), "rename succeeds")
    check(box.name == "hero" and box.elem_name == "hero", "rename moves node and elem name")
    check(_track_of(_zen_anim(c), "hero:pos_x") >= 0 and _track_of(_zen_anim(c), "box:pos_x") < 0,
          "rename rewrites track paths")
    check(_zen_anim(c).find_track(NodePath("hero:zen_ease_pos_x"), Animation.TYPE_VALUE) >= 0,
          "...including the ease track")
    var sa := ZenAnimBuilder.find_player(c).get_animation(ZenAnimBuilder.sig_path("go"))
    check(sa.find_track(NodePath("hero:alpha"), Animation.TYPE_BEZIER) >= 0, "...and signal tracks")
    check(bus.signals_data[0]["targets"][0]["elem"] == "hero", "...and signal targets")
    check_near(box.prop("pos_x", 1.0, 0.0), 0.9, "a renamed element still plays its keys")
    check(not ZenElemOps.rename(c, box, "box_2"), "rename refuses a taken name")

    var d := ZenElemOps.duplicate_elem(c, box)
    check(d.elem_name == "hero_2" and d.get_index() == box.get_index() + 1, "duplicate lands right after")
    check_near(d.prop("pos_x", 1.0, 0.0), 0.9, "duplicate copies the keys")

    ZenElemOps.move(c, d, 0)
    check(ZenElemOps.rows(c)[0] == d and d.z_index == 0, "move reorders and re-assigns z")
    ZenElemOps.move(c, g, 0)
    var bg: ZenGlobal = ZenElemOps.halves(c, g)[0]
    check(bg.is_background and bg.z_index == -1 and g.z_index == 0, "a moved global keeps its bg at -1")

    ZenElemOps.remove(c, box)
    check(not c.has_node("hero") and _track_of(_zen_anim(c), "hero:pos_x") < 0, "remove drops node and tracks")
    check((bus.signals_data[0]["targets"] as Array).is_empty(), "remove prunes signal targets")
    check(sa.find_track(NodePath("hero:alpha"), Animation.TYPE_BEZIER) < 0, "remove drops signal tracks")
    check_near(d.prop("pos_x", 1.0, 0.0), 0.9, "the duplicate keeps its own keys")
    c.free()


func test_doc_ops() -> void:
    var c := _authoring_canvas({})
    ZenDocOps.set_intro_end(c, 0.5)
    ZenDocOps.set_outro_start(c, 1.5)
    var anim := _zen_anim(c)
    check(anim.get_marker_names().has("intro_end") and is_equal_approx(anim.get_marker_time("outro_start"), 1.5),
          "intro/outro are written as markers")
    ZenDocOps.add_pause(c, 1.0, true)
    check(c.pauses.size() == 1 and anim.get_marker_names().has("pause_1_once"), "a pause is a marker")
    ZenDocOps.move_pause(c, 0, 0.8)
    check_near(float(c.pauses[0]["t"]), 0.8, "a pause moves")
    ZenDocOps.remove_pause(c, 0)
    check(c.pauses.is_empty() and not anim.get_marker_names().has("pause_1_once"), "a pause is removed")
    ZenDocOps.set_duration(c, 1.2)
    check(is_equal_approx(anim.length, 1.2) and is_equal_approx(c.duration, 1.2), "duration is the length")
    check_near(c.outro_start, 1.2, "shortening clamps the outro")
    ZenDocOps.set_duration(c, 4.0)
    check_near(c.outro_start, 4.0, "lengthening moves an end-of-clip outro with the end")
    check_near(c.play_end(), 4.0, "...so the new tail is played")
    ZenDocOps.set_outro_start(c, 3.0)
    ZenDocOps.set_duration(c, 5.0)
    check_near(c.outro_start, 3.0, "a real outro stays where it was set")
    ZenDocOps.set_intro_end(c, 0.0)
    check(not anim.get_marker_names().has("intro_end"), "intro 0 clears the marker")
    c.free()


func _samp(c: ZenCanvas, path: String, t: float) -> float:
    var anim := _zen_anim(c)
    return anim.bezier_track_interpolate(anim.find_track(NodePath(path), Animation.TYPE_BEZIER), t)


## Inserting an effect: its timing, eases and text, laid in at `t`.
func test_clip_ops() -> void:
    var keys := [_k(0.5, 0.2), _k(1.0, 0.8, "bounceOut"), _k(1.5, 0.4, "cubicIn"), _k(1.8, 0.9)]
    var fx := _authoring_canvas({"pos_x": keys, "alpha": [_k(0.5, 0.0), _k(1.0, 1.0, "sineOut")]})

    # As new elements at t=2: the effect's own times shifted exactly 2s; the scene grows to fit.
    var dest := _authoring_canvas({})
    ZenDocOps.set_outro_start(dest, dest.duration)
    check(ZenClipOps.names_for(dest, fx) == ["box_2"], "names_for previews the de-duplicated name")
    var made := ZenClipOps.paste(dest, fx, 2.0)
    check(made.size() == 1 and (made[0] as ZenElement).elem_name == "box_2", "inserting a taken name renames it")
    var pk := ZenKeyOps.keys(dest, made[0], "pos_x")
    check(pk.map(func(k): return k["ease"]) == ["linear", "bounceOut", "cubicIn", "linear"],
          "eases survive the insert: %s" % [pk.map(func(k): return k["ease"])])
    check_near(float(pk[0]["t"]), 2.5, "the effect's leading time is kept", 1e-4)
    for tt in [0.6, 0.9, 1.2, 1.7]:
        check_near(_samp(dest, "box_2:pos_x", 2.0 + tt), _samp(fx, "box:pos_x", tt),
                   "the inserted curve is the effect shifted (%.1f)" % tt, 1e-4)
    check_near(dest.duration, 3.8, "inserting past the end lengthens the scene", 1e-4)
    check_near(dest.outro_start, dest.duration, "...and an end-of-clip outro stays at the end", 1e-4)

    # A prefix, and a speed ratio applied to the opened effect first.
    var d2 := _authoring_canvas({})
    ZenDocOps.retime(fx, 0.5)
    var m2 := ZenClipOps.paste(d2, fx, 0.0, "fx_")
    check(m2.size() == 1 and (m2[0] as ZenElement).elem_name == "fx_box", "the prefix goes in front of the name")
    var k2 := ZenKeyOps.keys(d2, m2[0], "pos_x")
    check_near(float(k2[k2.size() - 1]["t"]), 0.9, "a ratio of 0.5 plays the effect twice as fast", 1e-4)
    check_near(_samp(d2, "fx_box:pos_x", 0.45), _samp(fx, "box:pos_x", 0.45), "...along the same curve", 1e-4)

    # Text: the words follow into the destination pool, whatever its indices.
    var sc := _authoring_canvas({})
    var tx := ZenElemOps.add(sc, "text", "label")
    var i0 := ZenStringOps.add(sc, "ALPHA")
    var i1 := ZenStringOps.add(sc, "BETA")
    ZenKeyOps.insert(sc, tx, "string", 0.0, float(i0))
    ZenKeyOps.insert(sc, tx, "string", 1.0, float(i1))
    var dc := _authoring_canvas({})
    ZenStringOps.add(dc, "OTHER")
    var pasted := ZenClipOps.paste(dc, sc, 0.5)
    var tl: ZenElement = pasted[pasted.size() - 1]
    var sk := ZenKeyOps.keys(dc, tl, "string")
    var pool := ZenStringOps.pool(dc)
    check(sk.size() == 2 and pool.at(int(sk[0]["v"])) == "ALPHA" and pool.at(int(sk[1]["v"])) == "BETA",
          "string keys point at the same words in the new pool")
    check(absf(float(sk[0]["t"]) - 0.5) < 1e-4 and absf(float(sk[1]["t"]) - 1.5) < 1e-4,
          "...at the shifted times")
    check((tl as ZenText).strings == pool, "an inserted text uses the destination's pool")
    for c in [fx, dest, d2, sc, dc]: c.free()


## Mapping an effect's elements onto existing ones: relative / absolute
## values, skipping, stepped props, and the own keys it lands among.
func test_clip_map() -> void:
    var fx := _authoring_canvas({"pos_x": [_k(0.0, 0.5), _k(0.5, 0.6), _k(1.0, 0.5)],
                                 "scale": [_k(0.0, 1.0), _k(1.0, 2.0)],
                                 "alpha": [_k(0.0, 0.0), _k(1.0, 1.0)]})
    var dest := _authoring_canvas({"pos_x": [_k(0.0, 0.2), _k(2.0, 0.4)], "scale": [_k(0.0, 0.5)]})
    var box: ZenElement = dest.get_node("box")
    var alpha0 := box.base_scalar("alpha")
    check(ZenClipOps.suggest(dest, fx) == {"box": {"to": "box"}}, "a same-name, same-kind element is suggested")
    check(ZenClipOps.names_for(dest, fx, "", {"box": {"to": "box"}}).is_empty(), "a mapped row adds no name")
    check(ZenClipOps.targets_for(dest, fx.get_node("box")).size() == 1, "targets are the same kind")

    # Relative onto the box at 1.0: the nudge starts from where the box is.
    var made := ZenClipOps.paste(dest, fx, 1.0, "", {"box": {"to": "box", "relative": true}})
    check(made.size() == 1 and made[0] == box and ZenElemOps.rows(dest).size() == 1,
          "a mapped insert drives the existing element and adds none")
    check_near(_samp(dest, "box:pos_x", 1.0), 0.3, "relative: position starts at the target's own", 1e-4)
    check_near(_samp(dest, "box:pos_x", 1.5), 0.4, "...and moves by the effect's amount", 1e-4)
    check_near(_samp(dest, "box:pos_x", 0.5), 0.25, "...the target's own keys before stay", 1e-4)
    check_near(_samp(dest, "box:zen_scale", 2.0), 1.0, "relative: a size scales by the target's own", 1e-4)
    check_near(_samp(dest, "box:alpha", 2.0), 1.0, "alpha plays as keyed", 1e-4)
    check_near(_samp(dest, "box:alpha", 0.5), alpha0, "a new track is pinned at 0 to the old value", 1e-4)

    # Absolute, and a skipped row.
    var d2 := _authoring_canvas({"pos_x": [_k(0.0, 0.2)]})
    ZenClipOps.paste(d2, fx, 1.0, "", {"box": {"to": "box", "relative": false}})
    check_near(_samp(d2, "box:pos_x", 1.5), 0.6, "absolute: the effect's own values", 1e-4)
    var d3 := _authoring_canvas({})
    check(ZenClipOps.paste(d3, fx, 0.0, "", {"box": {"to": "-"}}).is_empty() and ZenElemOps.rows(d3).size() == 1,
          "a skipped row writes nothing")

    # Text onto text: the words stay the target's unless asked.
    var sc := _authoring_canvas({})
    var tx := ZenElemOps.add(sc, "text", "label")
    ZenKeyOps.insert(sc, tx, "string", 0.0, float(ZenStringOps.add(sc, "ALPHA")))
    ZenKeyOps.insert(sc, tx, "string", 0.5, float(ZenStringOps.add(sc, "BETA")))
    ZenKeyOps.insert(sc, tx, "alpha", 0.0, 0.0)
    ZenKeyOps.insert(sc, tx, "alpha", 0.5, 1.0)
    var dc := _authoring_canvas({})
    var lt := ZenElemOps.add(dc, "text", "label")
    ZenClipOps.paste(dc, sc, 0.0, "", {"box": {"to": "-"}, "label": {"to": "label"}})
    check(not ZenKeyOps.has_track(dc, lt, "string") and ZenKeyOps.has_track(dc, lt, "alpha"),
          "a driven text keeps its own words, takes the motion")
    ZenClipOps.paste(dc, sc, 0.0, "", {"box": {"to": "-"}, "label": {"to": "label", "stepped": true}})
    var sk := ZenKeyOps.keys(dc, lt, "string")
    check(sk.size() == 2 and ZenStringOps.pool(dc).at(int(sk[1]["v"])) == "BETA", "...or takes them when asked")

    # Own keys inside the span: reported, and settled three ways.
    var own := [_k(0.0, 0.2), _k(1.3, 0.9), _k(1.6, 0.1), _k(3.0, 0.2)]
    var map := {"box": {"to": "box", "relative": false}}
    var dm := _authoring_canvas({"pos_x": own})
    ZenDocOps.set_duration(dm, 3.5)
    var cf := ZenClipOps.conflicts(dm, fx, 1.0, map)
    check(cf.has("box") and int(cf["box"]["keys"]) == 2 and cf["box"]["props"] == ["pos_x"],
          "own keys inside the span are a conflict: %s" % [cf])
    check_near(float(cf["box"]["first"]), 1.3, "...from the first", 1e-4)
    check(ZenClipOps.conflicts(dm, fx, 1.7, map).is_empty(), "a span between own keys is clean")
    check_near(ZenClipOps.clear_after(dm, fx, 1.0, map), 1.6, "the first clean start", 1e-4)
    var times := func(c: ZenCanvas) -> Array:
        return ZenKeyOps.keys(c, c.get_node("box"), "pos_x").map(func(k): return "%.2f" % float(k["t"]))
    ZenClipOps.paste(dm, fx, 1.0, "", map)
    check(times.call(dm) == ["0.00", "1.00", "1.30", "1.50", "1.60", "2.00", "3.00"], "merge interleaves: %s" % [times.call(dm)])
    var dr := _authoring_canvas({"pos_x": own})
    ZenDocOps.set_duration(dr, 3.5)
    ZenClipOps.paste(dr, fx, 1.0, "", {"box": {"to": "box", "relative": false, "resolve": "replace"}})
    check(times.call(dr) == ["0.00", "1.00", "1.50", "2.00", "3.00"], "replace drops them: %s" % [times.call(dr)])
    var dp := _authoring_canvas({"pos_x": own})
    ZenDocOps.set_duration(dp, 3.5)
    ZenClipOps.paste(dp, fx, 1.0, "", {"box": {"to": "box", "relative": false, "resolve": "push"}})
    check(times.call(dp) == ["0.00", "1.00", "1.50", "2.00", "2.30", "2.60", "4.00"], "push moves them after: %s" % [times.call(dp)])
    check_near(dp.duration, 4.0, "...and the scene grows to keep them", 1e-4)
    for c in [fx, dest, d2, d3, sc, dc, dm, dr, dp]: c.free()


## Retime scales the whole clock; trim cuts the still time off both ends.
func test_doc_retime_trim() -> void:
    var c := _authoring_canvas({"pos_x": [_k(0.0, 0.3), _k(0.5, 0.3), _k(1.0, 0.8, "cubicOut"), _k(1.5, 0.4)],
                                "alpha": [_k(0.0, 1.0), _k(1.8, 1.0)]})
    ZenDocOps.set_duration(c, 3.0)
    ZenDocOps.add_pause(c, 0.2)
    ZenDocOps.add_pause(c, 1.2)
    ZenSignalOps.add(c, "tap")
    var sig_len := ZenAnimBuilder.signal_anim(c, "tap").length
    var span := ZenDocOps.key_span(c)
    check_near(span.x, 0.5, "the span starts where the first value changes (holds do not count)", 1e-4)
    check_near(span.y, 1.5, "...and ends where the last change ends", 1e-4)
    var before := _samp(c, "box:pos_x", 0.8)

    ZenDocOps.retime(c, 2.0)
    check_near(c.duration, 6.0, "retime x2 doubles the length", 1e-4)
    check_near(_samp(c, "box:pos_x", 1.6), before, "...and the curve plays at half speed", 1e-4)
    check_near(float(c.pauses[1]["t"]), 2.4, "...and moves the pauses", 1e-4)
    check_near(ZenAnimBuilder.signal_anim(c, "tap").length, sig_len, "...but not a signal's own clock", 1e-4)
    ZenDocOps.retime(c, 0.5)
    check_near(c.duration, 3.0, "retime back", 1e-4)

    check(ZenDocOps.trim(c, true, true), "trim cuts something")
    check_near(c.duration, 1.0, "trimmed to the moving part", 1e-4)
    var ks := ZenKeyOps.keys(c, c.get_node("box"), "pos_x")
    check(ks.size() == 3 and absf(float(ks[0]["t"])) < 1e-4, "the leading hold collapses onto 0: %s" % [ks])
    check_near(_samp(c, "box:pos_x", 0.3), before, "the curve plays the same, earlier", 1e-4)
    check(c.pauses.size() == 1 and absf(float(c.pauses[0]["t"]) - 0.7) < 1e-4,
          "a pause inside the cut goes, a later one moves (%s)" % [c.pauses])
    var ak := ZenKeyOps.keys(c, c.get_node("box"), "alpha")
    check(ak.size() >= 1 and float(ak[ak.size() - 1]["t"]) <= 1.0 + 1e-4, "a hold past the end is cut back")
    check_near(c.outro_start, c.duration, "the outro stays at the end", 1e-4)
    check(not ZenDocOps.trim(c, true, true), "trimming again finds nothing to cut")
    var still := _authoring_canvas({})
    check(ZenDocOps.key_span(still).x < 0.0 and not ZenDocOps.trim(still, true, true), "nothing keyed: nothing to trim")
    for x in [c, still]: x.free()


func test_scene_ops_roundtrip() -> void:
    var nm := "zz_test_scene"
    check(ZenSceneOps.clean_name("My Intro!") == "my_intro_", "scene names are cleaned")
    var c := ZenSceneOps.new_canvas(nm)
    var title := ZenElemOps.find(c, "title")
    check(title is ZenText and (title as ZenText).text == "HELLO", "a new scene has the starter title")
    check(ZenKeyOps.keys(c, title, "alpha").size() == 2, "...fading in")
    ZenKeyOps.insert(c, title, "pos_x", 1.0, 0.7, "bounceOut")
    var path := ZenSceneOps.save(c, nm)
    check(not path.is_empty() and FileAccess.file_exists(path), "save writes the scene (%s)" % path)
    check(ZenSceneOps.path_of(nm) == path, "the saved scene is listed")

    var o := ZenSceneOps.open(path)
    var ot := ZenElemOps.find(o, "title")
    var ek := ZenKeyOps.keys(o, ot, "pos_x")
    check(ek.size() == 1 and ek[0]["ease"] == "bounceOut", "eases survive save/load")
    check_near(ot.prop("alpha", 0.3, 0.0), title.prop("alpha", 0.3, 0.0), "loaded scene samples the same")

    # detach(): editing the opened copy must not touch the cached scene.
    ZenKeyOps.set_value(o, ot, "alpha", 1, 0.5)
    var again := (load(path) as PackedScene).instantiate() as ZenCanvas
    check_near(ZenElemOps.find(again, "title").prop("alpha", 1.0, 0.0), 1.0,
               "an open canvas edits its own copy of the Animation")
    var snap := ZenSceneOps.restore(ZenSceneOps.snapshot(o))
    ZenKeyOps.set_value(o, ot, "alpha", 1, 0.2)
    check_near(ZenElemOps.find(snap, "title").prop("alpha", 1.0, 0.0), 0.5,
               "a snapshot is independent of later edits")

    var dup := nm + "_copy"
    check(ZenSceneOps.duplicate_scene(nm, dup) == OK and not ZenSceneOps.path_of(dup).is_empty(), "duplicate a scene")
    check(ZenSceneOps.rename(dup, nm) == ERR_ALREADY_EXISTS, "rename refuses a taken name")
    var moved := nm + "_moved"
    check(ZenSceneOps.rename(dup, moved) == OK and ZenSceneOps.path_of(dup).is_empty()
          and not ZenSceneOps.path_of(moved).is_empty(), "rename a scene")
    for n in [nm, moved]:
        DirAccess.remove_absolute(ProjectSettings.globalize_path(ZenSceneOps.path_of(n)))
    check(ZenSceneOps.path_of(nm).is_empty(), "test scenes cleaned up")
    for x in [c, o, again, snap]: x.free()



## The bundled scenes' string pools: one ZenStrings per scene, referenced by
## the canvas and every text, entries at stable indices, and the stepped
## `string` track switches the label that game code reads.
func test_string_pool_scenes() -> void:
    var c: ZenCanvas = (load("res://anims/ma_prog/ma_prog_01_intro.tscn") as PackedScene).instantiate()
    c.live_playback = false
    var texts := ZenStringOps.texts(c)
    check(c.strings != null and texts.size() == 3, "ma_prog_01 has a pool and three texts")
    check(texts.all(func(t): return (t as ZenText).strings == c.strings),
          "every text references the canvas's one pool instance")
    var t1 := ZenElemOps.find(c, "t1") as ZenText
    check(t1.string_base == 6 and c.strings.at(6).strip_edges().begins_with("Just like a cup"),
          "t1's own words were pooled onto the identical entry #6 (%d)" % t1.string_base)
    check(c.strings.at(0) == "What Is Programming?" and c.strings.at(10) == "coding w/ ai",
          "pool entries keep their indices")
    c.pose(0.0)
    check(t1.text == "What Is Programming?", "the label is the entry the string track holds at 0 (%s)" % t1.text)
    var seen: Array = []
    t1.text_changed.connect(func(w): seen.append(w))
    c.pose(2.5)
    check(t1.text == "Just like a tree grows its branches", "the string track switches the label at 2.45s")
    check(seen == ["Just like a tree grows its branches"], "text_changed fires once per switch (%s)" % [seen])
    c.pose(2.6)
    check(seen.size() == 1, "no text_changed while the words stay")
    c.pose(7.0)
    check(t1.text == "coding w/ ai", "...and again at 6.6s")
    check(not FileAccess.get_file_as_string("res://anims/ma_prog/ma_prog_01_intro.tscn").contains("\ntext = "),
          "the label is not stored in the scene")
    c.free()

    var c2: ZenCanvas = (load("res://anims/ma_prog/ma_prog_02_coding.tscn") as PackedScene).instantiate()
    c2.live_playback = false
    check(c2.strings.at(9) == "coding" and c2.strings.at(13) == "CODE", "a full pool keeps its indices")
    var t2 := ZenElemOps.find(c2, "t2") as ZenText
    check(t2.string_base == 9 and c2.strings.entries.size() == 14,
          "t2 rests on 'coding' and the pool has no stray entry (%d)" % t2.string_base)
    check(ZenStringOps.holes(c2).is_empty(), "a full pool has no holes (%d)" % ZenStringOps.holes(c2).size())
    c2.free()

    var shapes: ZenCanvas = (load("res://anims/zooming_box.tscn") as PackedScene).instantiate()
    check(shapes.strings == null, "a scene with no text carries no pool")
    check(ZenStringOps.pool(shapes) != null and shapes.strings != null, "...and gets one on demand")
    shapes.free()


## Pool editing: dedupe, in-place edit, references in the document AND signal
## Animations, stable holes, refill, and the clean-up that renumbers.
func test_string_ops() -> void:
    var c := _authoring_canvas({})
    var bus := ZenSignalBus.new()
    bus.name = "Signals"
    bus.signals_data = [{"name": "go", "length": 1.0, "targets": [
        {"elem": "box", "prop": "alpha", "keys": [_k(1.0, 0.0)]}],
        "seq_targets": [], "pos_params": []}]
    c.add_child(bus)
    bus.owner = c
    ZenAnimBuilder.install(c)

    var a := ZenElemOps.add(c, "text", "a") as ZenText
    var b := ZenElemOps.add(c, "text", "b") as ZenText
    check(a.strings == c.strings and b.strings == c.strings, "added texts reference the canvas pool")
    check(a.string_base == 0 and b.string_base == 0 and c.strings.entries.size() == 1,
          "identical words share one entry")
    var i1 := ZenStringOps.add(c, "one")
    var i2 := ZenStringOps.add(c, "two")
    var i3 := ZenStringOps.add(c, "three")
    check([i1, i2, i3] == [1, 2, 3], "new entries append (%s)" % [[i1, i2, i3]])
    check(ZenStringOps.add(c, "two") == i2, "adding existing words reuses the entry")
    ZenStringOps.set_text(c, 0, "shared")
    check(a.text == "shared" and b.text == "shared", "an in-place edit reaches every element using it")
    check(ZenStringOps.users(c, 0) == 2, "both texts count as users")

    ZenStringOps.assign(c, b, i3, 1.0, true)
    check(b.text_at(1.5) == "three" and b.text_at(0.5) == "shared", "assign keys the playhead, base kept at 0")
    check(ZenStringOps.users(c, i3) == 1, "a key is a reference")
    var sa := ZenAnimBuilder.find_player(c).get_animation(ZenAnimBuilder.sig_path("go"))
    var tr := ZenAnimBuilder.add_discrete(sa, "a:string")
    sa.track_insert_key(tr, 0.0, float(i2))
    check(ZenStringOps.users(c, i2) == 1, "a signal key is a reference too")
    check(not ZenStringOps.remove(c, i2), "an entry in use cannot be removed")

    check(ZenStringOps.remove(c, i1), "an unused entry is removed")
    check(c.strings.entries.size() == 4 and c.strings.at(1) == "" and ZenStringOps.holes(c) == [1],
          "...leaving a hole, so later indices hold")
    check(b.text_at(1.5) == "three", "later entries keep their words")
    check(ZenStringOps.add(c, "four") == 1, "a new entry refills the hole")
    ZenStringOps.remove(c, 1)

    check(ZenStringOps.compact(c) == 1, "clean-up removes the hole")
    check(c.strings.entries == PackedStringArray(["shared", "two", "three"]), "...and renumbers (%s)" % c.strings.entries)
    check(b.text_at(1.5) == "three", "document keys are rewritten to the new index")
    check(int(float(sa.track_get_key_value(tr, 0)) + 0.5) == 1, "signal keys are rewritten too")
    check(a.string_base == 0 and a.text == "shared", "base indices survive the renumber")
    var last := ZenStringOps.add(c, "last")
    check(ZenStringOps.remove(c, last) and c.strings.entries.size() == 3, "removing the tail entry trims the pool")
    c.free()


## The pool is ONE instance per canvas through every copy the editor makes:
## open, snapshot/restore, element duplicate and save/load.
func test_string_pool_shared() -> void:
    var cached: ZenCanvas = (load("res://anims/ma_prog/ma_prog_01_intro.tscn") as PackedScene).instantiate()
    var o := ZenSceneOps.open("res://anims/ma_prog/ma_prog_01_intro.tscn")
    var shared_by := func(c: ZenCanvas) -> bool:
        return ZenStringOps.texts(c).all(func(t): return (t as ZenText).strings == c.strings)
    check(o.strings != cached.strings and shared_by.call(o), "open gives the canvas its own shared pool")
    ZenStringOps.set_text(o, 0, "changed")
    check(cached.strings.at(0) == "What Is Programming?", "editing it leaves the cached scene alone")

    var snap := ZenSceneOps.restore(ZenSceneOps.snapshot(o))
    check(snap.strings != o.strings and shared_by.call(snap) and snap.strings.at(0) == "changed",
          "a snapshot holds its own copy, still shared by its texts")
    check(shared_by.call(o), "the live canvas keeps its pool after a snapshot")
    ZenStringOps.set_text(o, 0, "later")
    check(snap.strings.at(0) == "changed", "a snapshot is independent of later pool edits")

    var d := ZenElemOps.duplicate_elem(o, ZenElemOps.find(o, "t1")) as ZenText
    check(d.strings == o.strings, "a duplicated text references the same pool")

    var nm := "zz_test_strings"
    var path := ZenSceneOps.save(o, nm)
    var src := FileAccess.get_file_as_string(path)
    var ids := {}
    for m in RegEx.create_from_string("strings = SubResource\\(\"([^\"]+)\"\\)").search_all(src):
        ids[m.get_string(1)] = true
    check(ids.size() == 1, "the saved scene stores the pool once (%d ids)" % ids.size())
    var back := ZenSceneOps.open(path)
    check(shared_by.call(back) and back.strings.at(0) == "later", "it loads back shared, with the edit")
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    for x in [cached, o, snap, back]: x.free()


## Effects through the editor's own handlers: Length, Trim, Extract, Insert.
func test_scene_editor_effects() -> void:
    var user_state := ZenSettings.editor_state()
    ZenSettings.set_editor_state({})
    var ed: ZenSceneEditor = (load("res://tools/zen_scene_editor.tscn") as PackedScene).instantiate()
    root.add_child(ed)
    await process_frame
    var fx := ed._fx
    check(ed._panel("effects") != null, "the editor has an Effects panel")
    check(not ZenSceneOps.scene_paths().has("zz_fx_src") and not ZenSceneOps.scene_paths().has("zz_fx_out"),
          "(no leftovers from an earlier run)")

    # A source scene with two elements and a signal, saved.
    ed.open("")
    ed._name = "zz_fx_src"
    var c: ZenCanvas = ed._canvas
    var ring := ZenElemOps.add(c, "shape", "ring")
    ZenKeyOps.insert(c, ring, "pos_x", 0.0, 0.2)
    ZenKeyOps.insert(c, ring, "pos_x", 0.8, 0.2)
    ZenKeyOps.insert(c, ring, "pos_x", 1.4, 0.7)
    ZenSignalOps.add(c, "tap")
    ed._save()
    check(not ed._dirty() and ZenSceneOps.scene_paths().has("zz_fx_src"), "the source is saved")

    # Length: plain, then scaled; each one undo step.
    ed._fx.ask_length()
    fx._len_spin.value = 3.0
    fx._apply_length()
    fx._len_dialog.hide()
    check_near(ed._canvas.duration, 3.0, "Length sets the length")
    ed._do_undo()
    check_near(ed._canvas.duration, 2.0, "...in one undo step")
    fx.ask_length()
    fx._len_spin.value = 4.0
    fx._len_scale.button_pressed = true
    fx._apply_length()
    fx._len_dialog.hide()
    var rk := ZenKeyOps.keys(ed._canvas, ZenElemOps.find(ed._canvas, "ring"), "pos_x")
    check_near(float(rk[rk.size() - 1]["t"]), 2.8, "scaled Length stretches the keys", 1e-3)
    ed._do_undo()

    # Extract: copy (signals cut), keep one element, trim, saved.
    ed._sel.assign(["ring"])
    fx.ask_extract()
    check(fx._name_dialog.visible, "a saved scene goes straight to the name step")
    fx._name_edit.text = "zz_fx_out"
    fx._name_sigs.button_pressed = false
    fx._name_dialog.hide()
    fx._copy_for_extract()
    check(ed._name == "zz_fx_out" and ZenSceneOps.folder_of("zz_fx_out") == ZenSceneOps.EFFECTS_FOLDER,
          "the effect is a copy in effects/ (%s, %s)" % [ed._name, ZenSceneOps.folder_of("zz_fx_out")])
    check(ZenSignalOps.names(ed._canvas).is_empty(), "signals are cut off when not kept")
    check(fx._elem_dialog.visible and fx._elem_box.get_child_count() == ZenElemOps.rows(ed._canvas).size(),
          "the element step lists every element")
    fx._elem_dialog.hide()
    fx._keep_elements()
    check(ZenElemOps.rows(ed._canvas).size() == 1 and ZenElemOps.find(ed._canvas, "ring") != null,
          "only the elements selected before extract are kept")
    check(fx._guide.visible and fx._step == 3, "the key step shows the guide strip")
    fx._guide.hide()
    fx.ask_trim()
    check(fx._trim_dialog.visible and fx._trim_lead.button_pressed and fx._trim_tail.button_pressed,
          "the trim step offers both cuts")
    fx._trim_dialog.hide()
    fx._apply_trim()
    check_near(ed._canvas.duration, 0.6, "the effect is trimmed to its moving part", 1e-3)
    check(not ed._dirty() and fx._step == 0 and not fx._guide.visible, "the trim step saves and ends the guide")
    var src := ZenSceneOps.open(ZenSceneOps.path_of("zz_fx_src"))
    check(ZenElemOps.rows(src).size() == 2, "the source animation keeps both its elements")
    check(not ZenSignalOps.names(src).is_empty(), "...and keeps its signal")
    src.free()

    # Insert into the source: at a second, half speed, prefixed.
    ed.open(ZenSceneOps.path_of("zz_fx_src"))
    fx.ask_insert(ZenSceneOps.path_of("zz_fx_out"))
    check(fx._ins_dialog.visible and fx._ins_fx != null, "Insert opens on the chosen effect")
    fx._ins_sec.value = 1.5
    check(fx._ins_at_sec.button_pressed, "typing a second picks 'at second'")
    fx._ins_ratio.value = 2.0
    fx._ins_prefix.text = "pre_"
    fx._ins_prefix.text_changed.emit("pre_")          # what typing sends
    check(fx.insert_prefix() == "pre_", "typing a prefix turns it on")
    check(fx._ins_info.text.contains("1.20s"), "the dialog shows the length after the ratio: %s" % fx._ins_info.text)
    fx._ins_dialog.hide()
    var n0 := ZenElemOps.rows(ed._canvas).size()
    fx._apply_insert()
    var made := ZenElemOps.find(ed._canvas, "pre_ring")
    check(made != null and ZenElemOps.rows(ed._canvas).size() == n0 + 1, "Insert adds the prefixed element")
    if made != null:
        var mk := ZenKeyOps.keys(ed._canvas, made, "pos_x")
        check_near(float(mk[0]["t"]), 1.5, "...from the chosen second", 1e-3)
        check_near(float(mk[mk.size() - 1]["t"]), 2.7, "...at the chosen ratio", 1e-3)
    check(ed._sel.size() == 1 and ed._sel[0] == "pre_ring", "the inserted elements are selected")
    ed._do_undo()
    check(ZenElemOps.find(ed._canvas, "pre_ring") == null, "one undo removes the insert")

    # The playhead option scrubs the editor as it changes.
    fx.ask_insert(ZenSceneOps.path_of("zz_fx_out"))
    fx._ins_head.value = 0.75
    check(fx._ins_at_head.button_pressed and absf(ed._t - 0.75) < 1e-3, "the playhead field moves the playhead")
    fx._ins_dialog.hide()

    for nm in ["zz_fx_src", "zz_fx_out"]: ZenSceneOps.delete(nm)
    ed.queue_free()
    await process_frame
    ZenSettings.set_editor_state(user_state)


## The Strings panel and the text inspector, driven through their handlers.
func test_scene_editor_strings() -> void:
    var user_state := ZenSettings.editor_state()
    ZenSettings.set_editor_state({})
    var ed: ZenSceneEditor = (load("res://tools/zen_scene_editor.tscn") as PackedScene).instantiate()
    root.add_child(ed)
    await process_frame
    ed.open("res://anims/ma_prog/ma_prog_02_coding.tscn")
    await process_frame
    check(ed._panel("strings") != null, "the editor has a Strings panel")
    ed._sel.assign(["t2"])
    ed._on_selection_changed(true)
    await process_frame
    check(ed._insp.get_children().any(func(n): return n is TextEdit), "the text inspector edits the words")

    var times := [0.0, 0.3, 1.0, 5.0]
    var shown := func() -> Array:
        var out: Array = []
        for t in ZenStringOps.texts(ed._canvas):
            for tt in times: out.append((t as ZenText).text_at(tt))
        return out
    # The bundled pool is full; punch two interior holes to clean up.
    var h := [ZenStringOps.add(ed._canvas, "h1"), ZenStringOps.add(ed._canvas, "h2"),
              ZenStringOps.add(ed._canvas, "h3")]
    ZenStringOps.remove(ed._canvas, h[0])
    ZenStringOps.remove(ed._canvas, h[1])
    ed._refresh_strings()
    var full: int = ed._canvas.strings.entries.size()
    var before: Array = shown.call()
    check(ed._str_btns["clean"].text == "clean up holes (2)" and not ed._str_btns["clean"].disabled,
          "the clean-up button counts the holes")
    ed._clean_strings()
    check(ZenStringOps.holes(ed._canvas).is_empty() and ed._canvas.strings.entries.size() == full - 2,
          "clean-up compacts the pool (%d)" % ed._canvas.strings.entries.size())
    check(shown.call() == before, "...and every element shows the same words as before")
    ed._do_undo()
    check(ZenStringOps.holes(ed._canvas).size() == 2, "undo brings the holes back")

    ed._str_sel = 9
    ed._refresh_strings()
    check(ed._str_btns["delete"].disabled, "an entry in use cannot be deleted")
    ed._t = 0.0
    ed._assign_string()
    var t2 := ZenElemOps.find(ed._canvas, "t2") as ZenText
    check(t2.string_index_at(0.0) == 9 and t2.text_at(0.0) == "coding", "assign points the selection at the entry")

    ed._add_string()
    var sel := ed._str_sel
    check(ed._canvas.strings.at(sel).begins_with("new words"), "add makes and selects a fresh entry (#%d)" % sel)
    ed._delete_string()
    check(ed._canvas.strings.at(sel) == "" or not ed._canvas.strings.has_index(sel), "an unused entry deletes")
    ed.queue_free()
    await process_frame
    ZenSettings.set_editor_state(user_state)


## The editor screen end to end: open, add, key through auto-key, scrub,
## undo/redo, reorder, save - driven through its own handlers.
func test_scene_editor() -> void:
    # The editor persists its layout and auto-key; keep the user's own.
    var user_state := ZenSettings.editor_state()
    ZenSettings.set_editor_state({})          # start from the default layout
    var ed: ZenSceneEditor = (load("res://tools/zen_scene_editor.tscn") as PackedScene).instantiate()
    root.add_child(ed)
    await process_frame
    ed.open("res://anims/zooming_box.tscn")
    await process_frame
    check(ed._canvas != null and ed.current_name() == "zooming_box", "the editor opens a scene")
    check(not ed._canvas.live_playback, "the editor drives the clock itself")

    ed._add_element("shape")
    await process_frame
    var el := ed._primary()
    check(el is ZenShape and el.elem_name.begins_with("shape_"), "add shape selects the new, uniquely named element")
    check(ed._dirty(), "an edit makes the scene dirty")
    ed._set_autokey(false)
    ed._on_drag_start()
    ed._on_drag(Vector2(0.1, 0.0))
    ed._commit_live()
    check_near(el.pos_frac.x, 0.6, "auto-key off: a drag moves the base pose")
    check(not ZenKeyOps.has_track(ed._canvas, el, "pos_x"), "...and writes no key")

    ed._set_autokey(true)
    ed._scrub_to(1.0)
    ed._on_drag_start()
    ed._on_drag(Vector2(0.2, 0.0))
    ed._on_drag(Vector2(0.25, 0.0))
    ed._commit_live()
    var ks := ZenKeyOps.keys(ed._canvas, el, "pos_x")
    check(ks.size() == 2, "auto-key on: a drag keys the playhead (and pins t=0) (%d)" % ks.size())
    check_near(el.prop("pos_x", 1.0, 0.0), 0.85, "the dragged position plays at the playhead")
    check_near(el.prop("pos_x", 0.0, 0.0), 0.6, "the base pose is kept at 0")
    var steps := ed._undo.get_history_count()

    ed._do_undo()
    el = ed._primary()
    check(el != null and not ZenKeyOps.has_track(ed._canvas, el, "pos_x"), "undo removes the drag's keys in one step")
    ed._do_redo()
    el = ed._primary()
    check(el != null and ZenKeyOps.keys(ed._canvas, el, "pos_x").size() == 2, "redo restores them")
    check(ed._undo.get_history_count() == steps, "undo/redo adds no history")

    ed._refresh_timeline()
    check(ed._tl.lanes.size() >= 1 and ed._lanes[0]["prop"] == "pos_x", "the timeline shows the keyed prop")
    ed._on_key_pressed(0, 1, false)
    ed._on_keys_drag_start()
    ed._on_keys_dragged(0.5, false)
    ed._commit_live()
    check_near(float(ZenKeyOps.keys(ed._canvas, el, "pos_x")[1]["t"]), 1.5, "dragging a key moves it in time")

    # The Keys panel: summoned by a pick, and its fields edit the picked keys.
    var kid := "%s|pos_x|1" % el.name
    check(ed._key_sel.has(kid), "a key pick is node|prop|idx")
    check(ed._p_keys.is_open, "picking a key summons the Keys panel")
    check(ed._keys._badge.text.begins_with("1 key"), "the panel says what is picked")
    check(ed._keys._value_rows.size() == 1 and ed._keys._time != null, "one value row per picked lane")
    check_near(ed._keys._time.value, 1.5, "the time field shows the key's time")
    ed._shift_keys(-0.25)
    ed._commit_live()
    check_near(float(ZenKeyOps.keys(ed._canvas, el, "pos_x")[1]["t"]), 1.25, "the time field moves the key")
    ed._set_key_values("%s|pos_x" % el.name, 0.42)
    ed._commit_live()
    check_near(float(ZenKeyOps.keys(ed._canvas, el, "pos_x")[1]["v"]), 0.42, "the value field sets the key")
    check(ed._key_preview().has("samples"), "one key previews its real incoming segment")
    # Keying another prop adds a lane; the pick stays on the same key.
    ZenKeyOps.insert(ed._canvas, el, "alpha", 0.5, 0.5)
    ZenKeyOps.insert(ed._canvas, el, "w", 0.5, 0.2)
    ed._refresh_timeline()
    var vs := ed._view_selection()
    check(ed._key_sel.has(kid) and vs.size() == 1 and
          ed._lanes[int(String(vs.keys()[0]).get_slice(":", 0))]["prop"] == "pos_x",
          "a new lane does not retarget the key selection")
    ed._scrub_to(0.0)
    ed._jump_key(1)
    check_near(ed._t, 0.5, "Down jumps the playhead to the next key time")
    check(ed._key_sel.size() == 2, "...and picks the keys there (%d)" % ed._key_sel.size())
    ed._select_all_keys()
    # pos_x and pos_y (the auto-keyed drag keyed both) have two keys each.
    check(ed._key_sel.size() == 6, "select all picks every visible key (%d)" % ed._key_sel.size())
    ed._stretch_keys(2.0)
    ed._commit_live()
    check_near(float(ZenKeyOps.keys(ed._canvas, el, "pos_x")[1]["t"]), 2.5, "stretch doubles gaps about the first key", 0.02)
    ZenKeyOps.remove_track(ed._canvas, el, "alpha")
    ZenKeyOps.remove_track(ed._canvas, el, "w")
    ed._refresh_timeline()
    ed._clear_keys()
    check(ed._key_sel.is_empty(), "the key selection clears")
    ed._on_key_pressed(0, 1, false)
    ZenKeyOps.move(ed._canvas, el, "pos_x", 1, 1.5)
    ed._refresh_timeline()
    ed._set_ease("bounceOut")
    check(String(ZenKeyOps.keys(ed._canvas, el, "pos_x")[1]["ease"]) == "bounceOut", "the ease menu sets the key's ease")
    ed._delete_keys()
    check(ZenKeyOps.keys(ed._canvas, el, "pos_x").size() == 1, "deleting the selected key")

    var rows := ZenElemOps.rows(ed._canvas)
    ed._move_selected(-1)
    check(ZenElemOps.rows(ed._canvas).find(ed._primary()) == rows.size() - 2, "move back reorders")

    ed._toggle_panel("inspector")
    var insp := ed._panel("inspector")
    check(insp.is_open, "a panel opens")
    ed._toggle_panel("document")
    check(not insp.is_open and ed._panel("document").is_open, "an unpinned panel closes others on its side")
    ed._panel("document").set_pinned(true)
    ed._toggle_panel("inspector")
    check(ed._panel("document").is_open and insp.is_open, "a pinned panel stays when another opens")
    ed._layout()
    check(ed._stage.size.x < ed._work.size.x - 1.0, "a pinned panel reserves its edge")
    ed._panel("document").set_pinned(false)
    ed._close_unpinned()
    check(not insp.is_open and not ed._panel("document").is_open, "unpinned panels close on demand")

    # A pinned timeline stays on screen while playing; unpinned panels slide.
    ed._panel("timeline").set_open(true)
    ed._panel("timeline").set_pinned(true)
    ed._toggle_panel("inspector")
    ed._slide = 1.0
    ed._layout()
    var tlp := ed._panel("timeline")
    check(tlp.visible and tlp.position.y + 1.0 < ed._work.size.y, "a pinned timeline stays on screen while playing")
    check(not insp.visible, "an unpinned panel slides away while playing")
    ed._slide = 0.0
    ed._panel("timeline").set_pinned(false)
    ed._close_unpinned()
    ed._layout()

    # The intro marker is there (at 0) even when unset, below the playhead.
    var tv := ed._tl
    tv.intro_end = 0.0
    check(tv.marker_at(Vector2(tv.t_to_x(0.0) + 3.0, ZenTimelineView.RULER_H - 5.0))[0] == "intro",
          "an unset intro marker is grabbable at 0")
    check(tv.marker_at(Vector2(tv.t_to_x(0.0) + 3.0, 4.0))[0] == "",
          "the ruler's top half stays the playhead's")

    # Canvas preset: one undoable step that resizes the stage with it.
    var before_size := ed._canvas.design_size
    var vi := ZenCanvas.preset_index(Vector2(360, 640))
    ed._on_canvas_size_selected(vi)
    check(ed._canvas.design_size == Vector2(360, 640), "picking a preset resizes the canvas")
    check(ed._stage._bg.size == Vector2(360, 640)
          and is_equal_approx(ed._stage.view_rect().size.aspect(), 360.0 / 640.0), "...and the stage's view")
    check((ed._doc_rows["design"] as OptionButton).selected == vi, "the picker shows the preset")
    ed._do_undo()
    check(ed._canvas.design_size == before_size, "undo restores the canvas size")
    check(ed._stage._bg.size == before_size, "...and the stage")

    var nm := "zz_test_editor"
    ed._name = nm
    ed._save()
    check(not ed._dirty(), "save clears dirty")
    var saved := ZenSceneOps.open(ZenSceneOps.path_of(nm))
    var se := ZenElemOps.find(saved, el.elem_name)
    check(se != null and ZenKeyOps.has_track(saved, se, "pos_x"), "the saved scene has the new element and its key")
    check(saved.live_playback, "a saved scene still plays on its own")
    saved.free()
    DirAccess.remove_absolute(ProjectSettings.globalize_path(ZenSceneOps.path_of(nm)))
    var orig := ZenSceneOps.open("res://anims/zooming_box.tscn")
    check(ZenElemOps.find(orig, "shape_2") == null, "the original scene is untouched")
    orig.free()
    ed.queue_free()
    await process_frame
    ZenSettings.set_editor_state(user_state)
    await test_scene_editor_playback()


## SPACE at the end restarts (like Home, then play); a click continues a pause.
func test_scene_editor_playback() -> void:
    var user_state := ZenSettings.editor_state()
    ZenSettings.set_editor_state({})          # start from the default layout
    var ed: ZenSceneEditor = (load("res://tools/zen_scene_editor.tscn") as PackedScene).instantiate()
    root.add_child(ed)
    await process_frame
    ed.open("")
    var c := ed._canvas
    c.loop_play = false
    ed._scrub_to(c.play_end())
    ed._toggle_play()
    check(ed._playing, "space plays")
    await process_frame
    await process_frame
    check(c.animation_player().current_animation_position < 0.5,
          "play at the end restarts from 0 (%.3f)" % c.animation_player().current_animation_position)
    ed._stop()
    # Finish a one-shot for real, then play again.
    ed._scrub_to(c.play_end() - 0.05)
    ed._toggle_play()
    var guard := 0
    while ed._playing and guard < 600:
        await process_frame
        guard += 1
    check(not ed._playing and ed._t > c.play_end() - 0.02, "a one-shot stops at its end")
    ed._toggle_play()
    await process_frame
    check(ed._playing and c.animation_player().is_playing() and
          c.animation_player().current_animation_position < 0.5, "space after the end replays from 0")
    ed._stop()

    ZenDocOps.add_pause(c, 0.3)
    ed._scrub_to(0.25)
    ed._toggle_play()
    guard = 0
    while c.held_pause < 0 and guard < 600:
        await process_frame
        guard += 1
    check(c.held_pause >= 0 and ed._playing, "playback holds at a pause marker")
    ed._stage.play_pointer.emit("press", Vector2(0.5, 0.5))
    check(c.held_pause < 0 and ed._playing, "a click on the canvas continues")
    ed._stop()
    ed.queue_free()
    await process_frame
    ZenSettings.set_editor_state(user_state)
    await test_scene_editor_signals()


## The Signals panel: add a signal (the first one makes the bus), key it in
## signal key mode without touching the document, leave the mode with the
## playhead back, undo it, and fire press triggers from the canvas while
## playing.
func test_scene_editor_signals() -> void:
    var user_state := ZenSettings.editor_state()
    ZenSettings.set_editor_state({})
    var ed: ZenSceneEditor = (load("res://tools/zen_scene_editor.tscn") as PackedScene).instantiate()
    root.add_child(ed)
    await process_frame
    ed.open("")
    ed._add_element("shape")
    var el := ed._primary()
    ed._set_autokey(false)
    ed._scrub_to(1.0)
    ed._sigs.add_requested.emit()
    var nm := ed._sig_pick
    check(nm != "" and ed._canvas.bus() != null, "+ signal adds one and creates the bus")
    check(ed._sigs._list.item_count == 1, "the panel lists it")

    ed._sigs.edit_keys_requested.emit(nm, true)
    check(ed._sig_edit == nm and ed._canvas.edit_anim == nm, "edit keys enters signal key mode")
    check(ed._t == 0.0 and ed._doc_t == 1.0, "the playhead is signal time; the document's is kept")
    ed._scrub_to(1.0)
    ed._on_drag_start()
    ed._on_drag(Vector2(0.2, 0.0))
    ed._commit_live()
    var sig := ZenSignalOps.data(ed._canvas, nm)
    check(sig["targets"].any(func(tg): return tg["prop"] == "pos_x"),
          "a drag in signal key mode keys the signal, auto-key or not")
    check(ZenKeyOps.keys(ed._canvas, ZenElemOps.find(ed._canvas, el.elem_name), "pos_x").size() == 2,
          "...with its capture key at 0")
    check_near(float(ed._value_at(ZenElemOps.find(ed._canvas, el.elem_name), "pos_x", 1.0)), 0.7,
               "the signal lands where it was dragged", 0.001)
    ed._refresh_timeline()
    check(ed._tl.lanes.size() == 2, "the timeline shows the signal's lanes (%d)" % ed._tl.lanes.size())

    ed._set_sig_edit("")
    check(ed._t == 1.0 and ed._canvas.edit_anim == "", "leaving restores the document playhead")
    el = ZenElemOps.find(ed._canvas, el.elem_name)
    check(not ZenKeyOps.has_track(ed._canvas, el, "pos_x"), "the document timeline was never keyed")

    # Undo the drag: the signal loses its target again.
    ed._do_undo()
    check(ZenSignalOps.data(ed._canvas, nm)["targets"].is_empty(), "undo takes the signal keys back")
    ed._do_redo()

    # A press-triggered anchor signal fires from a canvas click while playing.
    ed._sigs.field_set.emit(nm, "trigger", "press")
    ed._sigs.field_set.emit(nm, "point", "anchor")
    ed._sel.assign([el.elem_name])
    ed._sigs.bind_requested.emit(nm)
    check(ZenSignalOps.data(ed._canvas, nm)["point_elems"].size() == 1, "bind selected binds the element")
    ed._play()
    var fired: Array = []
    ed._canvas.bus().signal_fired.connect(func(n, p): fired.append([n, p]))
    ed._stage.play_pointer.emit("press", Vector2(0.25, 0.75))
    check(fired.size() == 1 and fired[0][0] == nm and fired[0][1]["pos"] == Vector2(0.25, 0.75),
          "a press on the canvas fires the press signal at the press")
    ed._stop()
    check(not ed._canvas.bus().is_overriding(), "stopping drops the fired signal")

    ed._sigs.delete_requested.emit(nm)
    check(ZenSignalOps.names(ed._canvas).is_empty(), "delete removes it")
    ed.queue_free()
    await process_frame
    ZenSettings.set_editor_state(user_state)


# ---------------------------------------------------------------------------
#  Godot-scene export (ZenGodotExport) and the canvas game API it ships.
# ---------------------------------------------------------------------------

## What an inherited scene drives: finished on a one-shot's end and on a
## terminal signal (once each), fire/resume reporting whether they did
## anything, stop/restart.
func test_canvas_game_api() -> void:
    var c: ZenCanvas = (load("res://anims/main_menu.tscn") as PackedScene).instantiate()
    c.play_loop = false                     # one-shot, so it runs out
    var got := [0]
    c.finished.connect(func(): got[0] += 1)
    root.add_child(c)
    await process_frame
    check(c.animation_player().is_playing(), "game api: plays on ready")
    check(not c.fire("no such signal"), "game api: fire() of an unknown name is false")
    check(not c.resume(), "game api: resume() with nothing held is false")
    check(c.signal_names().has("TV-out"), "game api: signal_names() lists the authored signals")
    c.animation_player().seek(c.play_end() - 0.01, true)
    for i in 6: await process_frame
    check(got[0] == 1, "game api: finished once at the one-shot's end (got %d)" % got[0])
    for i in 3: await process_frame
    check(got[0] == 1, "game api: and not again while it holds")

    c.restart()
    await process_frame
    check(c.animation_player().is_playing() and c.pose_time < 0.5,
          "game api: restart() plays from the top (t=%.3f)" % c.pose_time)
    c.stop()
    check(not c.animation_player().is_playing(), "game api: stop() holds")
    c.play(false)
    check(c.animation_player().is_playing(), "game api: play(false) carries on")

    # A terminal signal ends the instance - finished fires even mid-clock.
    c.restart()
    await process_frame
    check(c.fire("TV-out"), "game api: fire() of an authored signal is true")
    c.bus().advance(60.0)
    check(got[0] == 2, "game api: a terminal signal sends finished (got %d)" % got[0])
    c.queue_free()

    # Pause markers: resume() releases the hold.
    var p: ZenCanvas = (load("res://anims/ma_prog/ma_prog_01_intro.tscn") as PackedScene).instantiate()
    root.add_child(p)
    await process_frame
    p.advance_pauses(0.0, float(p.pauses[0]["t"]))
    check(p.held_pause == 0, "game api: a crossed marker holds")
    check(p.resume() and p.held_pause < 0, "game api: resume() releases it")
    p.queue_free()


func test_godot_export_rewrite() -> void:
    var src := """[gd_scene format=3 uid="uid://abc"]

[ext_resource type="Script" uid="uid://s1" path="res://addons/zen/runtime/zen_canvas.gd" id="1_a"]
[ext_resource type="Resource" path="res://assets/shapes/arrow_1.tres" id="2_b"]

[node name="X" type="Node2D"]
script = ExtResource("1_a")
note = "res://assets/shapes/arrow_1.tres"
"""
    var deps := ZenGodotExport.ext_resources(src)
    check(deps.size() == 2 and deps[0]["type"] == "Script" and deps[1]["path"] == "res://assets/shapes/arrow_1.tres",
          "godot export: ext_resources() reads type and path")
    var out := ZenGodotExport.rewrite_resource(src, {
        "res://addons/zen/runtime/zen_canvas.gd": "res://zen/zen_runtime/runtime/zen_canvas.gd",
        "res://assets/shapes/arrow_1.tres": "res://zen/shapes/arrow_1.tres"}, true)
    check(not out.contains("uid="), "godot export: every uid= is dropped")
    check(out.contains("path=\"res://zen/zen_runtime/runtime/zen_canvas.gd\""), "godot export: script re-pathed")
    check(out.contains("path=\"res://zen/shapes/arrow_1.tres\" id=\"2_b\""), "godot export: shape re-pathed, id kept")
    check(out.contains("note = \"res://assets/shapes/arrow_1.tres\""), "godot export: property text is not touched")
    var tres := "[gd_resource type=\"Resource\" script_class=\"ZenPixelShape\" format=4]\n"
    check(not ZenGodotExport.rewrite_resource(tres, {}, true).contains("script_class"),
          "godot export: standalone drops script_class")
    check(ZenGodotExport.rewrite_resource(tres, {}, false).contains("script_class"),
          "godot export: plugin mode keeps it")


## The standalone copy: no class_name, no global Zen class left, each ZR name
## it uses preloaded right under `extends`, and no path into addons/zen.
func test_godot_export_vendor_source() -> void:
    var names := {}
    var srcs := {}
    for f in ZenGodotExport.vendored_files():
        var src := FileAccess.get_file_as_string("res://addons/zen/runtime/" + f)
        srcs[f] = src
        names[ZenGodotExport.class_name_of(src)] = f
    check(names.has("ZenCanvas") and names.has("ZenEasingSet") and not names.has("ZenSettings"),
          "godot export: vendored set has the runtime minus the app-only files")
    var root := "res://zen/zen_runtime/"
    var globals := RegEx.create_from_string("\\b(" + "|".join(PackedStringArray(names.keys())) + ")\\b")
    for f in srcs:
        var out := ZenGodotExport.vendor_source(srcs[f], names, root)
        check(ZenGodotExport.class_name_of(out) == "", "godot export: %s has no class_name" % f)
        check(globals.search(out) == null, "godot export: %s names no global Zen class" % f)
        check(not out.contains("res://addons/zen/"), "godot export: %s has no addon path" % f)
        for m in RegEx.create_from_string("\\bZR(\\w+)").search_all(out):
            var c := "const ZR%s = preload(" % m.get_string(1)
            if not out.contains(c):
                check(false, "godot export: %s uses ZR%s without preloading it" % [f, m.get_string(1)])
                break
    var es := ZenGodotExport.vendor_source(srcs["zen_easing_set.gd"], names, root)
    check(es.contains("const ZREasingSet = preload(\"zen_easing_set.gd\")") and es.contains("ZREasing.register_custom"),
          "godot export: ZenEasingSet and ZenEasing stay distinct names")
    var tx := ZenGodotExport.vendor_source(srcs["zen_text.gd"], names, root)
    check(tx.contains("\"res://zen/zen_runtime/fonts/raylib_default_10px.tres\""),
          "godot export: the default font path follows the copy")
    check(tx.find("extends ") < tx.find("const ZR"), "godot export: consts come after extends")


func test_godot_export_validate() -> void:
    check(ZenGodotExport.clean_subdir("") == "zen", "godot export: empty subfolder is zen")
    check(ZenGodotExport.clean_subdir(" res://a/b/ ") == "a/b", "godot export: subfolder trimmed")
    var s := ZenGodotExport.Settings.new()
    check(ZenGodotExport.validate(s) != "", "godot export: no target is an error")
    s.target_dir = ProjectSettings.globalize_path("res://tools")
    check(ZenGodotExport.validate(s).contains("project.godot"), "godot export: a folder without project.godot is refused")
    s.target_dir = ProjectSettings.globalize_path("res://")
    check(ZenGodotExport.validate(s) == "", "godot export: a project folder is fine")
    s.subdir = "../out"
    check(ZenGodotExport.validate(s) != "", "godot export: .. in the subfolder is refused")
    s.subdir = "addons/zen"
    check(ZenGodotExport.validate(s) != "", "godot export: the plugin's own folder is refused")
    s.subdir = "zen"
    check(ZenGodotExport.extends_line(s) == "extends \"res://zen/zen_runtime/runtime/zen_canvas.gd\"",
          "godot export: standalone extends line")
    s.mode = ZenGodotExport.Mode.PLUGIN
    check(ZenGodotExport.extends_line(s) == "extends ZenCanvas", "godot export: plugin extends line")
    var e := ZenGodotExport.Settings.new()
    e.to_exports = true
    check(ZenGodotExport.validate(e) == "", "godot export: the exports stub needs no target")
    check(ZenGodotExport.target_root(e) == ProjectSettings.globalize_path("res://exports/godot"),
          "godot export: the exports stub lives in exports/godot")


## A real export into a throwaway project: the files land, and nothing in them
## points back into this project. (Loading them needs the target project - see
## the README's end-to-end check.)
func test_godot_export_files() -> void:
    var dir := ProjectSettings.globalize_path("user://godot_export_test")
    _rm_tree(dir)
    DirAccess.make_dir_recursive_absolute(dir)
    var f := FileAccess.open(dir.path_join("project.godot"), FileAccess.WRITE)
    f.store_string("config_version=5\n")
    f.close()
    var s := ZenGodotExport.Settings.new()
    s.target_dir = dir
    var r := ZenGodotExport.export_chain(["ma_prog_01_intro", "pause_menu"], s)
    check(bool(r["ok"]), "godot export: standalone chain exports (%s)" % r["error"])
    var scene := FileAccess.get_file_as_string(dir.path_join("zen/ma_prog_01_intro.tscn"))
    check(scene.contains("res://zen/shapes/ai_icon_128.tres"), "godot export: shapes re-pathed into the subfolder")
    check(FileAccess.file_exists(dir.path_join("zen/shapes/ai_icon_128.tres")), "godot export: and copied")
    check(FileAccess.file_exists(dir.path_join("zen/zen_runtime/runtime/zen_canvas.gd")), "godot export: runtime copied")
    check(FileAccess.file_exists(dir.path_join("zen/zen_runtime/fonts/raylib_default_10px.tres")), "godot export: fonts copied")
    check(not FileAccess.file_exists(dir.path_join("zen/zen_runtime/runtime/zen_settings.gd")), "godot export: app-only files stay home")
    check(scene.contains("fit_window = true") and scene.contains("click_to_continue = true"),
          "godot export: the scene ships with the F6 flags on")
    for p in r["files"]:
        var path := String(p)
        if path.get_extension() in ["ttf", "otf"]: continue
        var t := FileAccess.get_file_as_string(path)
        # A script may still MENTION res://assets (a doc comment, the unused
        # easings path); only a resource's own dependency would break.
        var leaks := t.contains("res://addons/zen/") or t.contains("uid://") \
            or (path.get_extension() != "gd" and t.contains("res://assets/"))
        if leaks:
            check(false, "godot export: %s still points into this project" % path)
    var notes := FileAccess.get_file_as_string(dir.path_join("zen/README.txt"))
    check(notes.contains("res://zen/ma_prog_01_intro.tscn") and notes.contains("res://zen/pause_menu.tscn")
          and notes.contains(ZenGodotExport.extends_line(s)) and notes.contains("nothing to copy"),
          "godot export: README.txt lists the scenes, the extends line and the steps")
    check(notes.contains("pause marker(s)"), "godot export: README.txt notes pause_menu's pause marker")
    check(notes.contains("exit - from code only, ends the scene"),
          "godot export: README.txt says what triggers each signal")
    var count := (r["files"] as Array).size()
    var r2 := ZenGodotExport.export_chain(["ma_prog_01_intro", "pause_menu"], s)
    check((r2["files"] as Array).size() == count, "godot export: re-export rewrites the same files")

    s.mode = ZenGodotExport.Mode.PLUGIN
    s.subdir = "plug"
    check(ZenGodotExport.validate(s) != "", "godot export: plugin mode needs the plugin or the checkbox")
    s.install_plugin = true
    r = ZenGodotExport.export_chain(["pause_menu"], s)
    check(bool(r["ok"]) and FileAccess.file_exists(dir.path_join("addons/zen/plugin.cfg")),
          "godot export: install_plugin copies the addon")
    check(FileAccess.get_file_as_string(dir.path_join("plug/pause_menu.tscn")).contains("res://addons/zen/runtime/zen_canvas.gd"),
          "godot export: plugin-mode scene points at the addon")
    check(FileAccess.get_file_as_string(dir.path_join("plug/README.txt")).contains("Project Settings > Plugins"),
          "godot export: plugin-mode README.txt says to enable the plugin")
    _rm_tree(dir)


func _rm_tree(dir: String) -> void:
    if not DirAccess.dir_exists_absolute(dir): return
    for sub in DirAccess.get_directories_at(dir): _rm_tree(dir.path_join(sub))
    for file in DirAccess.get_files_at(dir): DirAccess.remove_absolute(dir.path_join(file))
    DirAccess.remove_absolute(dir)
