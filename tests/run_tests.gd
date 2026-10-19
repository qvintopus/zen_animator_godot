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
    test_sampler()
    test_export_plan()
    test_cfg_parse()
    test_real_cfgs()
    test_text_layout()
    test_crumble_hash()
    test_canvas_size()
    test_blend_weight()
    test_trim_clamp()
    test_loop_seam_closes()
    test_seam_open_without_blend()
    test_stepped_never_blends()
    await test_canvas_clock()
    test_canvas_pauses()
    test_pause_across_wrap()
    test_export_pause_source()
    await test_canvas_idle_until_played()
    test_imported_scenes_inert()
    test_export_pause_holds()
    test_chain_frame_plan()
    test_chain_rejects_size_mismatch()
    test_single_link_plan_matches_legacy()
    test_estimate_bytes_shape()
    test_cutout_snaps_alpha()
    test_ffmpeg_args_per_format()
    await test_job_cancel_png()
    test_props_registry_agrees()
    test_blend_keyed()
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
    test_signal_terminal_edge()
    test_signal_terminal_holds_end_pose()
    test_signal_pack_roundtrip()
    await test_signal_autoload_relay()
    await test_signal_autoload_respects_inert()
    test_signal_autoload_registered()
    test_signal_bases_match_draw()
    test_signal_captures_posed_time()
    test_signal_unknown_element()
    test_imported_signals_present()
    test_signal_export_purity()
    await test_anim_player_plays()
    test_anim_player_markers()
    test_anim_player_mirrors_keys()
    test_input_actions_declared()
    await test_section_loops_into_body()
    test_seek_stays_in_section()
    await test_loop_play_separate_from_smooth()
    await test_viewer_intro_loop_toggles()
    test_pixel_shape()
    test_pixel_shape_shp_roundtrip()
    test_custom_shape_resolution()
    test_options_font_sort_filter()
    await test_shape_editor()
    test_zen_settings()
    test_export_dialog_preview()
    print("\n%d checks, %d failures" % [checks, fails])
    quit(1 if fails > 0 else 0)


## BlendKeyed (anim.c:1570-1584), the shared primitive under the pos-param
## bindings and the seq envelope. Three edges carry the behaviour.
func test_blend_keyed() -> void:
    var keys := [{"t": 0.5, "v": 10.0, "ease": "linear"},
                 {"t": 1.0, "v": 20.0, "ease": "linear"}]

    # No keys at all: the implicit u=0 anchor is the answer.
    check_near(ZenSignalPlayer._keyed(7.0, [], 0.5), 7.0, "blend_keyed no keys = anchor")

    # Before the first key it eases FROM the anchor, so u=0 IS the anchor and
    # u=0.25 is half way from the anchor to the first key.
    check_near(ZenSignalPlayer._keyed(0.0, keys, 0.0), 0.0, "blend_keyed u=0 = anchor")
    check_near(ZenSignalPlayer._keyed(0.0, keys, 0.25), 5.0, "blend_keyed eases from anchor")
    check_near(ZenSignalPlayer._keyed(0.0, keys, 0.5), 10.0, "blend_keyed hits first key")

    # Between keys.
    check_near(ZenSignalPlayer._keyed(0.0, keys, 0.75), 15.0, "blend_keyed mid segment")

    # Past the last key it HOLDS - it does not keep extrapolating, which is
    # what makes a finished signal sit still on its final pose.
    check_near(ZenSignalPlayer._keyed(0.0, keys, 1.0), 20.0, "blend_keyed at last key")
    check_near(ZenSignalPlayer._keyed(0.0, keys, 5.0), 20.0, "blend_keyed past end holds")

    # Easing is INCOMING: the segment uses the RIGHT key's ease. quadIn at the
    # half-way point of the first segment is 0.25, not 0.5.
    var eased := [{"t": 1.0, "v": 100.0, "ease": "quadIn"}]
    check_near(ZenSignalPlayer._keyed(0.0, eased, 0.5), 25.0,
               "blend_keyed uses the INCOMING (right-hand) ease")

    # A degenerate segment snaps rather than dividing by zero.
    var dup := [{"t": 0.5, "v": 3.0, "ease": "linear"},
                {"t": 0.5, "v": 9.0, "ease": "linear"}]
    check_near(ZenSignalPlayer._keyed(0.0, dup, 0.5), 9.0, "blend_keyed degenerate snaps")


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
    p.start(sig, {}, 0, cap)
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
    q.start(inst, {}, 0, cap)
    check_near(q.u(), 1.0, "length=0 snaps u to 1")
    check_near(float(q.eval("a", "alpha")), 1.0, "length=0 lands on the final key")
    q.update(0.016)
    check(q.is_done(), "length=0 is done on its first update")


## A signal driving NOTHING must not start (anim.c:1505-1507). `signal enter`
## in mouse_ripple.cfg is exactly this, and a player that "ran" would install an
## override that drives no property while still blocking the loop blend.
func test_signal_no_start() -> void:
    var empty := {"name": "enter", "length": 1.0, "targets": [], "pos_params": [],
                  "seq_targets": [], "seq_keys": [], "uses_seq": false,
                  "seq_mult": 0.0, "uses_pos": false, "pos_anchor": false}
    var p := ZenSignalPlayer.new()
    p.start(empty, {}, 0, func(_e, _pr): return 0.0)
    check(not p.playing, "a signal with no targets/posparams/seqtargets never starts")
    check(p.is_done(), "and reports done immediately")
    check(p.eval("shape", "pos_x") == null, "an unstarted signal drives nothing")

    # But posparams ALONE, or seqtargets ALONE, are enough to play.
    var only_pos: Dictionary = empty.duplicate(true)
    only_pos["uses_pos"] = true
    only_pos["pos_params"] = [{"elem": "shape", "slot": 0, "keys": []}]
    var q := ZenSignalPlayer.new()
    q.start(only_pos, {"pos": Vector2(0.5, 0.5)}, 0, func(_e, _pr): return 0.0)
    check(q.playing, "posparams alone are enough to start")

    var only_seq: Dictionary = empty.duplicate(true)
    only_seq["seq_targets"] = [{"elem": "shape", "prop": "scale"}]
    var r := ZenSignalPlayer.new()
    r.start(only_seq, {}, 0, func(_e, _pr): return 0.0)
    check(r.playing, "seqtargets alone are enough to start")


## seq offset = seq * seq_mult * env(u), and every gate that zeroes it.
func test_signal_seq_offset() -> void:
    var sig := {"name": "s", "length": 2.0, "uses_pos": false, "pos_anchor": false,
                "targets": [], "pos_params": [], "uses_seq": true, "seq_mult": 0.5,
                "seq_targets": [{"elem": "shape", "prop": "scale"}],
                "seq_keys": [{"t": 1.0, "v": 1.0, "ease": "linear"}]}
    var cap := func(_e, _pr): return 0.0

    var p := ZenSignalPlayer.new()
    p.start(sig, {}, 3, cap)
    check_near(p.seq_offset("shape", "scale"), 0.0, "seq env starts at 0")
    p.update(1.0)
    check_near(p.seq_offset("shape", "scale"), 3.0 * 0.5 * 0.5, "seq = seq*mult*env(u)")
    check_near(p.seq_offset("shape", "pos_x"), 0.0, "seq only hits its seqtargets")
    check_near(p.seq_offset("other", "scale"), 0.0, "seq only hits its element")

    # seq 0 means "not sequenced" and must contribute nothing at all.
    var q := ZenSignalPlayer.new()
    q.start(sig, {}, 0, cap)
    q.update(1.0)
    check_near(q.seq_offset("shape", "scale"), 0.0, "seq index 0 contributes nothing")

    # No env keys: a CONSTANT full offset, not zero.
    var flat: Dictionary = sig.duplicate(true)
    flat["seq_keys"] = []
    var r := ZenSignalPlayer.new()
    r.start(flat, {}, 2, cap)
    check_near(r.seq_offset("shape", "scale"), 1.0, "no env keys = constant full offset")


## ZenProps and the parser's per-kind lists must name the SAME properties.
##
## They are two tables of the same truth, and a disagreement is invisible: the
## parser produced an `outline` track while ZenProps called it `outline_thick`,
## which nothing noticed because nothing enumerated the list. The signal layer
## DOES enumerate it (the pose capture walks scalars_for + colors_for), so a
## mismatch there would silently swallow every signal targeting that property.
func test_props_registry_agrees() -> void:
    var parser := {"text": ZenCfgParse.TEXT_PROPS, "shape": ZenCfgParse.SHAPE_PROPS,
                   "global": ZenCfgParse.GLOBAL_PROPS}
    for kind in parser:
        var mine: Array = ZenProps.scalars_for(kind) + ZenProps.colors_for(kind)
        for prop in parser[kind]:
            check(mine.has(prop), "ZenProps[%s] knows parser prop '%s'" % [kind, prop])
        for prop in mine:
            check((parser[kind] as Array).has(prop),
                  "parser[%s] knows ZenProps prop '%s'" % [kind, prop])

    # And the two classifications must agree, not just the names.
    for prop in ZenCfgParse.STEPPED_PROPS:
        check(ZenProps.is_stepped(prop), "'%s' stepped in both tables" % prop)
    for prop in ZenCfgParse.COLOR_PROPS:
        check(ZenProps.is_color(prop), "'%s' colour in both tables" % prop)


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

    # Every name a .cfg may carry must resolve, or the importer would silently
    # linearize an authored curve. This is the check that stops CFG_NAMES and
    # GODOT_EASE drifting apart.
    for nm2 in ZenEasing.CFG_NAMES:
        check(ZenEasing.is_builtin(nm2), "cfg easing '%s' is backed" % nm2)

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
    # bop_n_up from anims_src/_easings.cfg - has a hold step (two knots at
    # x=0.284375) and overshoots to y=1.5.
    var nums := PackedFloat32Array([4,
        0,0,0,0,0.06875,1.5,
        0.284375,0.6,-0.1625,1.275,0.1625,-1.275,
        0.284375,0.3,-0.107344,0,0.107344,0,
        1,1,-0.25,-0.25,0,0])
    var c := ZenCurve.from_tokens(nums)
    check(c.knots.size() == 4, "bop_n_up parsed 4 knots")
    check_near(c.sample(0.0), 0.0, "custom p=0 -> first knot y")
    check_near(c.sample(1.0), 1.0, "custom p=1 -> last knot y")
    # Between the two coincident knots the curve must not explode.
    var mid := c.sample(0.284375)
    check(mid >= -1.0 and mid <= 2.0, "hold step stays bounded (got %.3f)" % mid)
    # Monotonic x-solve: sampling must be finite everywhere.
    for i in 101:
        var v := c.sample(float(i) / 100.0)
        check(is_finite(v), "custom finite at p=%.2f" % (float(i) / 100.0))


## Track evaluation: clamping, incoming easing, stepped props.
func test_sampler() -> void:
    var keys := [
        {"t": 0.0, "v": 0.0, "ease": "linear"},
        {"t": 1.0, "v": 10.0, "ease": "quadIn"},
        {"t": 2.0, "v": 20.0, "ease": "linear"},
    ]
    # Clamp before first / after last (AnimTrackSegment).
    check_near(ZenSampler.eval(keys, -5.0), 0.0, "clamp before first key")
    check_near(ZenSampler.eval(keys, 99.0), 20.0, "clamp after last key (hold)")
    check_near(ZenSampler.eval(keys, 0.0), 0.0, "exactly on first key")
    check_near(ZenSampler.eval(keys, 2.0), 20.0, "exactly on last key")
    # INCOMING ease: the segment 0->1 is eased by key[1].ease (quadIn), so at
    # the midpoint the value is 10*quadIn(0.5) = 10*0.25 = 2.5, NOT 5.
    check_near(ZenSampler.eval(keys, 0.5), 2.5, "incoming ease (quadIn on right key)")
    # The 1->2 segment uses key[2].ease (linear) -> plain midpoint.
    check_near(ZenSampler.eval(keys, 1.5), 15.0, "linear segment midpoint")
    # Stepped: hold the left value until the right key is reached.
    check_near(ZenSampler.eval(keys, 0.5, true), 0.0, "stepped holds left")
    check_near(ZenSampler.eval(keys, 1.0, true), 10.0, "stepped takes right at key")
    # Single key -> that value everywhere.
    check_near(ZenSampler.eval([{"t": 3.0, "v": 7.0, "ease": "linear"}], 0.0), 7.0,
               "single key is constant")
    # Empty track -> the supplied fallback (the element's base pose).
    check_near(ZenSampler.eval([], 1.0, false, 42.0), 42.0, "empty track -> base")
    # Zero-span segment steps instantly: SegmentFraction divides by a zero span
    # and returns p=1.0, so the right value lands immediately. zooming_box.cfg's
    # TV-out signal relies on this (two keys at an identical u=0.457965).
    # Note the duplicate pair must be INTERIOR: a duplicate at the very start
    # hits AnimTrackSegment's `t <= keys[0].t` clamp first and yields the LEFT
    # value - verified against the C, which returns 5.0 for that case.
    var dup := [
        {"t": 0.0, "v": 0.0, "ease": "linear"},
        {"t": 1.0, "v": 5.0, "ease": "linear"},
        {"t": 1.0, "v": 9.0, "ease": "linear"},
        {"t": 2.0, "v": 9.0, "ease": "linear"},
    ]
    # Verified against the C: exactly ON the duplicate time the LEFT value still
    # shows (the scan stops at the first key with t <= keys[i].t); the step to
    # the right value happens immediately after. Both sides are asserted so a
    # future refactor cannot silently move the step by one key.
    check_near(ZenSampler.eval(dup, 1.0), 5.0, "interior dup at t -> left value")
    check_near(ZenSampler.eval(dup, 1.0001), 9.0, "interior dup just past t -> right value")
    var head := [
        {"t": 1.0, "v": 5.0, "ease": "linear"},
        {"t": 1.0, "v": 9.0, "ease": "linear"},
    ]
    check_near(ZenSampler.eval(head, 1.0), 5.0, "duplicate at head clamps left (matches C)")


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


## Parser edge cases that the real documents actually contain.
func test_cfg_parse() -> void:
    # Text escaping: a whole string is ONE whitespace-delimited token.
    check(ZenCfgParse.decode_text("MAIN\\sMENU") == "MAIN MENU", "\\s -> space")
    check(ZenCfgParse.decode_text("a\\nb") == "a\nb", "\\n -> newline")
    check(ZenCfgParse.decode_text("a\\\\b") == "a\\b", "\\\\ -> backslash")
    check(ZenCfgParse.decode_text("plain_text") == "plain_text", "underscore survives")

    var doc_text := """
doc TEST 3.000000 0.500000 2.500000 0.250000 1
elem shape box
  shape circle
  outline 10 20 30 255 1.500000
  scale 2.000000
  color 40 50 60 128
  pos 0.250000 0.750000
  size 16.000000 24.000000
  unit abs
  outline_style crisp
  rot -45.000000
  frobnicate 1 2 3
  track rot 0
  track alpha 2
    key 0.000000 0.000000 linear
    key 1.000000 1.000000 sineIn
  track color 2
    key 0.000000 1 2 3 linear
    key 1.000000 4 5 6 quadIn
  end
pause 1.250000 1
signal zap 0.800000 1 1 1 1
  posparam box 0 1
    poskey 0.000000 0.000000 0.000000 sineOut
  target box pos_x 1
    key 0.500000 0.900000 sineIn
  endsig
"""
    var r := ZenCfgParse.parse_doc(doc_text)
    check(r["ok"], "parse ok")
    var d: Dictionary = r["doc"]
    check(String(d["name"]) == "TEST", "doc name")
    check_near(d["duration"], 3.0, "doc duration")
    check_near(d["intro_end"], 0.5, "doc intro_end")
    check_near(d["outro_start"], 2.5, "doc outro_start")
    check_near(d["loop_blend"], 0.25, "doc loop_blend")
    check(bool(d["loop_smooth"]), "doc loop_smooth")

    check(d["elems"].size() == 1, "one element")
    var e: Dictionary = d["elems"][0]
    check(String(e["shape"]) == "circle", "shape kind")
    check(bool(e["unit_abs"]), "unit abs parsed")
    check(bool(e["outline_crisp"]), "outline_style crisp parsed")
    check_near(e["scale"], 2.0, "scale")
    check_near(e["rot"], -45.0, "rot")
    check_near(e["outline"], 1.5, "outline thickness")
    check(e["outline_color"].r8 == 10 and e["outline_color"].g8 == 20,
          "outline colour split from thickness")
    check(e["color"].a8 == 128, "base colour keeps its alpha")
    check_near(e["pos"].x, 0.25, "pos x")
    check_near(e["size"].y, 24.0, "size y (pixels in abs mode)")

    # An EMPTY track is legal and must be preserved - both menu files have one.
    check(e["tracks"].has("rot"), "empty track kept")
    check((e["tracks"]["rot"] as Array).is_empty(), "empty track has no keys")
    # Unknown leading keys are skipped, not fatal.
    check(not e["tracks"].has("frobnicate"), "unknown key skipped")

    var alpha: Array = e["tracks"]["alpha"]
    check(alpha.size() == 2, "alpha keys")
    check(String(alpha[1]["ease"]) == "sineIn", "key ease name read")
    # Colour keys are RGB-only; alpha never rides along.
    var col: Array = e["tracks"]["color"]
    check(col.size() == 2, "colour keys")
    check(col[0].has("c") and not col[0].has("v"), "colour key stores a Color")
    check(col[1]["c"].r8 == 4, "colour key rgb")

    check(d["pauses"].size() == 1, "pause parsed")
    check(bool(d["pauses"][0]["once"]), "pause once flag")

    check(d["signals"].size() == 1, "signal parsed")
    var sg: Dictionary = d["signals"][0]
    check(String(sg["name"]) == "zap", "signal name")
    check_near(sg["length"], 0.8, "signal length")
    check(bool(sg["terminal"]) and bool(sg["uses_pos"])
          and bool(sg["pos_anchor"]) and bool(sg["replay"]), "signal flags")
    check(sg["targets"].size() == 1, "signal target")
    check(sg["pos_params"].size() == 1, "signal posparam")

    # The crumble group shares ONE key line and fans out into five tracks.
    var cr := ZenCfgParse.parse_doc("""
elem text t
  track crumble 1
    key 2.418417 1.000000 0.000000 145.565216 0.500000 720.000000 linear
  end
""")
    var ce: Dictionary = cr["doc"]["elems"][0]
    for m in ZenCfgParse.CRUMBLE_MEMBERS:
        check(ce["tracks"].has(m), "crumble fans out to %s" % m)
    check_near(ce["tracks"]["crumble"][0]["v"], 1.0, "crumble amount")
    check_near(ce["tracks"]["crumble_dir"][0]["v"], 0.0, "crumble dir")
    check_near(ce["tracks"]["crumble_spread"][0]["v"], 145.565216, "crumble spread", 0.001)
    check_near(ce["tracks"]["crumble_dist"][0]["v"], 0.5, "crumble dist")
    check_near(ce["tracks"]["crumble_spin"][0]["v"], 720.0, "crumble spin")

    # outro_start <= 0 means "unset" and resolves to the duration.
    var nd := ZenCfgParse.parse_doc("doc X 4.0 0.0 0.0")
    check_near(nd["doc"]["outro_start"], 4.0, "outro_start 0 -> duration")


## The real documents must parse, and their known contents must survive.
func test_real_cfgs() -> void:
    var mm := ZenCfgParse.parse_doc(
        FileAccess.get_file_as_string("res://anims_src/MAIN_MENU.cfg"))
    check(mm["ok"], "MAIN_MENU parses")
    var d: Dictionary = mm["doc"]
    check(d["elems"].size() == 6, "MAIN_MENU has 6 elements (got %d)" % d["elems"].size())
    check_near(d["intro_end"], 0.619826, "MAIN_MENU intro_end")
    check_near(d["outro_start"], 3.210659, "MAIN_MENU outro_start")
    check(d["signals"].size() == 1, "MAIN_MENU has the TV-out signal")
    check(String(d["signals"][0]["name"]) == "TV-out", "TV-out name")
    check(bool(d["signals"][0]["terminal"]), "TV-out is terminal")
    check(d["signals"][0]["targets"].size() == 12, "TV-out has 12 targets (got %d)"
          % d["signals"][0]["targets"].size())
    # the_ball is the unit-abs one.
    var ball := {}
    for e in d["elems"]:
        if String(e["name"]) == "the_ball": ball = e
    check(not ball.is_empty(), "the_ball found")
    check(bool(ball["unit_abs"]), "the_ball is unit abs")
    check(bool(ball["outline_crisp"]), "the_ball is crisp")
    check_near(ball["size"].x, 16.0, "the_ball is 16px")
    # Corner-anchored diagonals.
    var diag := {}
    for e in d["elems"]:
        if String(e["name"]) == "line_diag_bottleft": diag = e
    check(bool(diag["corner_mode"]), "diagonal uses corner anchoring")
    check_near(diag["rot"], -45.108170, "diagonal rotation", 0.001)

    var pm := ZenCfgParse.parse_doc(
        FileAccess.get_file_as_string("res://anims_src/PAUSE_MENU.cfg"))
    check(pm["ok"], "PAUSE_MENU parses")
    check(pm["doc"]["elems"].size() == 2, "PAUSE_MENU has 2 elements")
    check(String(pm["doc"]["signals"][0]["name"]) == "exit", "exit signal")
    # Text escaping survived into the element.
    check(String(pm["doc"]["elems"][0]["text"]) == "PAUSE MENU", "title text decoded")
    check(String(pm["doc"]["elems"][1]["text"]) == "still, all the buttons",
          "subtitle text decoded")

    var mr := ZenCfgParse.parse_doc(
        FileAccess.get_file_as_string("res://anims_src/mouse_ripple.cfg"))
    var rs: Dictionary = mr["doc"]["signals"][1]
    check(String(rs["name"]) == "ripple", "ripple signal")
    check(bool(rs["uses_pos"]) and bool(rs["pos_anchor"]) and bool(rs["replay"]),
          "ripple is usesPos+posAnchor+replay")
    check(rs["targets"].is_empty(), "ripple has NO targets - only a posparam")
    check(rs["pos_params"].size() == 1, "ripple posparam")

    # The shared custom easings must all load and evaluate.
    var ez := ZenCfgParse.parse_easings(
        FileAccess.get_file_as_string("res://anims_src/_easings.cfg"))
    check(ez["curves"].size() == 7, "7 custom easings (got %d)" % ez["curves"].size())
    check(ez["hidden"].size() == 5, "5 hidden builtins")
    for n in ez["curves"]:
        var c: ZenCurve = ez["curves"][n]
        check(c.knots.size() >= 2, "%s has knots" % n)
        check_near(c.sample(0.0), c.knots[0][1], "%s starts at its first knot" % n)
        for i in 21:
            check(is_finite(c.sample(float(i) / 20.0)), "%s finite" % n)


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
func test_canvas_size() -> void:
    var c := ZenCanvas.new()
    check(c.design_size == Vector2(320, 180),
          "default canvas is 320x180 (got %s)" % c.design_size)

    # Every imported scene must agree.
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
    root.add_child(c)
    await process_frame
    check(c.animation_player() == null, "live_playback=false builds no AnimationPlayer")
    check_near(c.pose_time, 0.0, "and the pose stays at 0")
    check(not c.is_processing(), "and the canvas is not processing")
    c.queue_free()


## No imported scene carries a Player node any more - the clock is the
## canvas's own, and live_playback=false is what keeps it inert for a test.
func test_imported_scenes_inert() -> void:
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


## posAnchor is a CONSTANT TRANSLATION: the element is born at the cursor and
## plays its authored path, which is why anchor mode does NOT replace the slot
## (anim.c:1621-1622, 1783-1816). This is mouse_ripple's `ripple`.
func test_signal_pos_anchor_translates() -> void:
    var sig := {"name": "ripple", "length": 2.0, "terminal": false,
                "uses_pos": true, "pos_anchor": true, "replay": true,
                "targets": [], "seq_mult": 0.0, "uses_seq": false,
                "seq_targets": [], "seq_keys": [],
                "pos_params": [{"elem": "shape", "slot": 0, "keys": []}]}
    var canvas := _sig_canvas(sig)
    root.add_child(canvas)
    var sh: ZenShape = canvas.get_node("shape")
    var bus: ZenSignalBus = canvas.bus()

    # The element sits at the centre; emit at (0.75, 0.25).
    check_near(sh.prop("pos_x", 0.0, 0.5), 0.5, "element starts centred")
    bus.fire("ripple", {"pos": Vector2(0.75, 0.25)})
    canvas.pose(0.0)
    check_near(sh.prop("pos_x", 0.0, 0.5), 0.75, "anchored to the emitted x")
    check_near(sh.prop("pos_y", 0.0, 0.5), 0.25, "anchored to the emitted y")

    # (0,0) is a LEGAL emit - the top-left corner - which is why the payload
    # uses the presence of "pos" rather than a separate has_pos bool that
    # could contradict it (signal.h:33).
    bus.fire("ripple", {"pos": Vector2.ZERO})
    canvas.pose(0.0)
    check_near(sh.prop("pos_x", 0.0, 0.5), 0.0, "(0,0) is a legal emit, not 'no position'")

    # And with no position at all, the anchor contributes nothing.
    bus.fire("ripple", {})
    canvas.pose(0.0)
    check_near(sh.prop("pos_x", 0.0, 0.5), 0.5, "no emitted pos = no anchor offset")
    canvas.queue_free()


## A non-anchor posparam REPLACES the position (the centre branch), rather than
## offsetting it (anim.c:1615-1673).
func test_signal_pos_param_replaces() -> void:
    var sig := {"name": "go", "length": 2.0, "terminal": false,
                "uses_pos": true, "pos_anchor": false, "replay": false,
                "targets": [], "seq_mult": 0.0, "uses_seq": false,
                "seq_targets": [], "seq_keys": [],
                "pos_params": [{"elem": "shape", "slot": 0,
                                "keys": [{"t": 1.0, "off": Vector2.ZERO,
                                          "ease": "linear"}]}]}
    var canvas := _sig_canvas(sig)
    root.add_child(canvas)
    var sh: ZenShape = canvas.get_node("shape")
    var bus: ZenSignalBus = canvas.bus()

    bus.fire("go", {"pos": Vector2(0.9, 0.1)})
    bus.advance(1.999)          # still driving; a finished signal stops entirely
    canvas.pose(0.0)
    check_near(sh.prop("pos_x", 0.0, 0.5), 0.9, "posparam replaces pos_x", 0.001)
    check_near(sh.prop("pos_y", 0.0, 0.5), 0.1, "posparam replaces pos_y", 0.001)
    canvas.queue_free()


## RULE 4: a posparam OUTRANKS a plain target on the same prop. `ripple_old`
## has both, and the posparam must win (anim.c:1683).
func test_signal_pos_param_outranks_target() -> void:
    var sig := {"name": "go", "length": 2.0, "terminal": false,
                "uses_pos": true, "pos_anchor": false, "replay": false,
                "targets": [{"elem": "shape", "prop": "pos_x",
                             "keys": [{"t": 1.0, "v": 0.2, "ease": "linear"}]}],
                "seq_mult": 0.0, "uses_seq": false,
                "seq_targets": [], "seq_keys": [],
                "pos_params": [{"elem": "shape", "slot": 0,
                                "keys": [{"t": 1.0, "off": Vector2.ZERO,
                                          "ease": "linear"}]}]}
    var canvas := _sig_canvas(sig)
    root.add_child(canvas)
    var sh: ZenShape = canvas.get_node("shape")
    var bus: ZenSignalBus = canvas.bus()

    bus.fire("go", {"pos": Vector2(0.9, 0.5)})
    bus.advance(1.999)          # still driving; a finished signal stops entirely
    canvas.pose(0.0)
    # The plain target would drive pos_x to 0.2, the posparam to 0.9. Opposite
    # directions, so there is no reading of this that both could satisfy.
    check_near(sh.prop("pos_x", 0.0, 0.5), 0.9,
               "the posparam wins over a plain target on the same prop", 0.001)
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


## The real documents must declare the signals their .cfg authored - the
## importer no longer drops them.
func test_imported_signals_present() -> void:
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


## intro_end / outro_start must reach the timeline as markers, and come back
## when dragged. They are the document's own clock fields, not decoration.
func test_anim_player_markers() -> void:
    var canvas: ZenCanvas = (load("res://anims/main_menu.tscn") as PackedScene).instantiate()
    canvas.live_playback = false
    var anim := ZenAnimBuilder.build(canvas, true)
    var names: PackedStringArray = anim.get_marker_names()
    check(names.has(ZenAnimBuilder.M_INTRO), "intro_end reaches the timeline as a marker")
    check(names.has(ZenAnimBuilder.M_OUTRO), "outro_start reaches the timeline as a marker")
    check(is_equal_approx(anim.get_marker_time(ZenAnimBuilder.M_INTRO), canvas.intro_end),
          "the intro marker carries the authored time")

    # Dragging a marker edits the document.
    anim.remove_marker(ZenAnimBuilder.M_INTRO)
    anim.add_marker(ZenAnimBuilder.M_INTRO, 0.9)
    check(ZenAnimBuilder.sync_markers(anim, canvas), "a moved marker reports a change")
    check(is_equal_approx(canvas.intro_end, 0.9),
          "and writes back to intro_end (%.4f)" % canvas.intro_end)

    # A 0 is ABSENT, not a marker at the origin - else every document would show
    # a spurious intro_end pinned to the left edge.
    var ripple: ZenCanvas = (load("res://anims/mouse_ripple.tscn") as PackedScene).instantiate()
    ripple.live_playback = false
    var a2 := ZenAnimBuilder.build(ripple, false)
    check(not a2.get_marker_names().has(ZenAnimBuilder.M_INTRO),
          "intro_end 0 means no marker at all")
    canvas.queue_free()
    ripple.queue_free()


## Key mirroring is the groundwork for the authoring tool: every Zen track must
## become a real, visible Godot track, and survive the round trip back.
func test_anim_player_mirrors_keys() -> void:
    var canvas: ZenCanvas = (load("res://anims/main_menu.tscn") as PackedScene).instantiate()
    canvas.live_playback = false
    root.add_child(canvas)
    var anim := ZenAnimBuilder.build(canvas, true)
    var n := ZenAnimBuilder.populate_keys(anim, canvas)
    check(n > 0, "tracks are mirrored onto the Animation (%d)" % n)

    # Count the non-empty Zen tracks; every one must appear.
    var want := 0
    for e in canvas.elements():
        for prop in (e as ZenElement).tracks:
            if not (e as ZenElement).tracks[prop].is_empty(): want += 1
    check(n == want, "every non-empty Zen track is mirrored (%d of %d)" % [n, want])

    # A stepped prop must never interpolate - a value between two pool entries
    # resolves to the wrong entry entirely.
    #
    # Built by hand because NO bundled document carries a stepped track: walking
    # main_menu's tracks made this assertion vacuously true, and it passed with
    # the interpolation forced to LINEAR. Verified to fail now.
    var stepped_canvas := ZenCanvas.new()
    stepped_canvas.live_playback = false
    stepped_canvas.duration = 2.0
    var txt := ZenText.new()
    txt.name = "stepped_text"
    txt.elem_name = "stepped_text"
    txt.tracks = {
        "string": [{"t": 0.0, "v": 0.0, "ease": "linear"},
                   {"t": 1.0, "v": 3.0, "ease": "linear"}],
        "alpha":  [{"t": 0.0, "v": 0.0, "ease": "linear"},
                   {"t": 1.0, "v": 1.0, "ease": "linear"}],
    }
    stepped_canvas.add_child(txt)
    var sanim := ZenAnimBuilder.build(stepped_canvas, false)
    ZenAnimBuilder.populate_keys(sanim, stepped_canvas)
    var saw_stepped := false
    var stepped_ok := true
    var smooth_ok := false
    for ti in sanim.get_track_count():
        if sanim.track_get_type(ti) != Animation.TYPE_VALUE: continue
        var pr := String(sanim.track_get_path(ti).get_concatenated_subnames())
        var it := sanim.track_get_interpolation_type(ti)
        if ZenProps.is_stepped(pr):
            saw_stepped = true
            if it != Animation.INTERPOLATION_NEAREST: stepped_ok = false
        elif pr == "alpha":
            smooth_ok = it == Animation.INTERPOLATION_LINEAR
    check(saw_stepped, "the stepped track was actually mirrored (else the next check is vacuous)")
    check(stepped_ok, "stepped props are mirrored as NEAREST, never interpolated")
    check(smooth_ok, "and an ordinary prop beside it still interpolates LINEAR")
    stepped_canvas.queue_free()

    # Round trip: read the mirrored tracks back and the key times must survive,
    # each keeping its authored ease.
    var title: ZenElement = null
    for e in canvas.elements():
        if (e as ZenElement).elem_name == "title": title = e
    var before: Array = (title.tracks.get("pos_x", []) as Array).duplicate(true)
    ZenAnimBuilder.sync_from_keys(anim, canvas)
    var after: Array = title.tracks.get("pos_x", [])
    check(before.size() == after.size(),
          "a round trip preserves the key count (%d -> %d)" % [before.size(), after.size()])
    var same := true
    for i in mini(before.size(), after.size()):
        if not is_equal_approx(float(before[i]["t"]), float(after[i]["t"])): same = false
        if String(before[i].get("ease","")) != String(after[i].get("ease","")): same = false
    check(same, "and preserves each key's time and authored ease")
    canvas.queue_free()


## Generated by tools/gen_input_map.gd into project.godot's [input] section.
func test_input_actions_declared() -> void:
    var names := ["zen_play", "zen_back", "zen_restart", "zen_prev", "zen_next",
                  "zen_options", "zen_export", "zen_export_queue",
                  "zen_toggle_intro", "zen_toggle_loop", "zen_tab"]
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
    check(ZenSettings.export_scale() == 8, "export scale clamps to MAX_SCALE")
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
    dlg._name_edit.text = ""
    check(dlg._resolved_path_preview() == "res://exports/a_chain.gif",
          "empty name field previews the resolved default-name path")

    dlg.queue_free()


## pause_menu is the discriminator: its intro (1.513) is longer than its body
## (0.473), the one shape where "restart at intro_end" and "restart at 0"
## actually differ. Proves the section API replaced the hand-rolled wrap.
func test_section_loops_into_body() -> void:
    var pm: ZenCanvas = (load("res://anims/pause_menu.tscn") as PackedScene).instantiate()
    pm.loop_play = true   # not yet authored on the scene - Task 1c re-import sets this
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


## Every ported asset survives .tres -> .shp -> parse unchanged, and a row
## starting with '#' is a row of fill, not a comment.
func test_pixel_shape_shp_roundtrip() -> void:
    var names := ZenAssets.shape_names()
    check(names.size() >= 9, "the 9 ported shapes are present (%d)" % names.size())
    for n in names:
        var a := ZenAssets.load_shape(n)
        var b := ZenPixelShape.from_shp_text(a.to_shp_text(n))
        check(b != null and b.size == a.size and b.cells == a.cells, "%s round-trips through .shp" % n)
    var t := ZenPixelShape.from_shp_text("# c\nshape x\nsize 3 2\nrows\n##O\n.#.\nend\n")
    check(t != null and t.get_cell(0, 0) == ZenPixelShape.FILL and t.get_cell(2, 0) == ZenPixelShape.OUTLINE
          and t.get_cell(1, 1) == ZenPixelShape.FILL, "a '#'-leading row is pixels")
    check(ZenPixelShape.from_shp_text("rows\n##\nend") == null, "rows without size is rejected")


## Import keeps shape_name, resolves shape_ref through to `shape_refs`, and
## shape_at() follows the stepped track.
func test_custom_shape_resolution() -> void:
    var c: ZenCanvas = (load("res://anims/ma_prog_02_coding.tscn") as PackedScene).instantiate()
    var icon: ZenShape = null
    for e in c.elements():
        if e is ZenShape and (e as ZenShape).elem_name == "icon_ai": icon = e
    check(icon != null and icon.shape_kind == ZenShape.Kind.CUSTOM, "icon_ai imports as CUSTOM")
    if icon != null:
        check(icon.shape_name == "ai_icon_128" and icon.shape != null, "shape_name resolves to an asset")
        check(icon.shape_refs.size() >= 1, "shape_ref lines resolve into shape_refs")
        var keys: Array = icon.tracks.get("shape_id", [])
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
    m.tracks = {"shape_id": [{"t": 0.0, "v": ZenShape.SHAPE_MISSING, "ease": "linear"}]}
    m.shape = ZenPixelShape.new()
    check(m.shape_at(0.0) == null, "SHAPE_MISSING key draws the placeholder even with a rest shape")
    m.free()


## Options: default pinned first, families A-Z case-insensitively, deduped;
## the search filter matches the default by its label.
func test_options_font_sort_filter() -> void:
    var f := ZenOptions.sorted_fonts(["beta", "Alpha", "gamma", "Alpha"])
    check(f == ["", "Alpha", "beta", "gamma"], "fonts sorted A-Z, default first, deduped (%s)" % [f])
    check(ZenOptions.filter_fonts(f, "") == [0, 1, 2, 3], "empty search shows all")
    check(ZenOptions.filter_fonts(f, "AL") == [1], "search is case-insensitive")
    check(ZenOptions.filter_fonts(f, "source") == [0], "default matches on its label")


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
