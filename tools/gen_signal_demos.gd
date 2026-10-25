extends SceneTree
##
## Builds the signal demo scenes (anims/sig_*.tscn): one small scene per signal
## feature, plus `sig_starfall`, which combines them. Re-run after changing a
## design here; the scenes are plain Zen scenes and stay editable in the scene
## editor afterwards.
##
##   Godot --headless --path . --script res://tools/gen_signal_demos.gd
##
## Two runtime rules shape every design:
##   - a finished signal (not terminal, not follow) hands its elements straight
##     back to the timeline, so anything a signal MOVES fades out by the end -
##     the return home reads as a respawn, not a jump;
##   - a signal captures the PLAIN timeline pose, never where an earlier signal
##     left an element.
##
## Signal keys are in u (0..1 of `length`). The first key of every track sits
## just past u=0 (U0): the editor's model treats a key AT u=0 as the captured
## pose, so a key there would be reinterpreted on the first edit.
##

const SIZE := Vector2(320, 180)
const BG := Color(0.07, 0.08, 0.12, 1)
## The gallery folder the demos live in (anims/signal_demo/).
const FOLDER := "signal_demo"
const U0 := 0.02
const WHITE := Color(0.96, 0.96, 0.96, 1)
const DIM := Color(0.55, 0.6, 0.7, 1)
const GOLD := Color(1.0, 0.8, 0.35, 1)
const CYAN := Color(0.35, 0.85, 1.0, 1)
const PINK := Color(1.0, 0.4, 0.6, 1)
const GREEN := Color(0.45, 0.95, 0.55, 1)


func _init() -> void:
    for fn in [_press_anchor, _release_seek, _follow, _code, _end_once,
               _end_every_loop, _end_first_loop, _then_chain, _starfall]:
        var doc: Dictionary = fn.call()
        var path := _save(doc)
        print("%s  %s" % ["wrote" if not path.is_empty() else "FAILED", doc["name"]])
    quit()


# ---------------------------------------------------------------------------
#  Scenes
# ---------------------------------------------------------------------------

## press + anchor: a burst made only of signal keys, born at the click.
func _press_anchor() -> Dictionary:
    var ring := shape("ring", "circle", Vector2(0.5, 0.5), Vector2(64, 64),
                      {"color": Color(CYAN, 0), "outline_color": Color(CYAN, 0), "outline": 3.0})
    var core := shape("core", "rhombus", Vector2(0.5, 0.5), Vector2(18, 18),
                      {"color": Color(WHITE, 0)})
    var dot := shape("dot", "circle", Vector2(0.5, 0.5), Vector2(6, 6), {"color": Color(GOLD, 0)})
    var burst := sig("burst", {"trigger": "press", "point": "anchor", "length": 0.9,
        "point_elems": [bind("ring"), bind("core"), bind("dot")],
        "targets": [
            tgt("ring", "scale", [k(U0, 0.05), k(1.0, 1.0, "cubicOut")]),
            tgt("ring", "outline_alpha", [k(U0, 1.0), k(1.0, 0.0, "quadIn")]),
            tgt("core", "alpha", [k(U0, 1.0), k(0.5, 1.0), k(1.0, 0.0, "sineIn")]),
            tgt("core", "rot", [k(U0, 0.0), k(1.0, 270.0, "cubicOut")]),
            tgt("core", "scale", [k(U0, 1.6), k(1.0, 0.0, "backIn")]),
            tgt("dot", "alpha", [k(U0, 1.0), k(0.7, 1.0), k(1.0, 0.0)]),
        ]})
    return scene("sig_press_anchor", 2.0, [hint("PRESS: BURST BORN AT THE CLICK"),
        idle_pulse("title", "ANCHOR"), ring, core, dot], [burst])


## release + seek: the ball flies to where the mouse is let go, then pops.
func _release_seek() -> Dictionary:
    var pad := shape("pad", "rect", Vector2(0.5, 0.83), Vector2(0.14, 0.03), {"color": DIM})
    var ball := shape("ball", "circle", Vector2(0.5, 0.74), Vector2(16, 16), {"color": PINK},
        {"pos_y": [k(0.0, 0.74), k(0.6, 0.71, "sineOut"), k(1.2, 0.74, "sineIn")]})
    var throw := sig("throw", {"trigger": "release", "point": "seek", "length": 0.7,
        "point_ease": "backOut", "point_elems": [bind("ball")],
        "targets": [
            tgt("ball", "w", [k(U0, 16.0), k(0.15, 12.0, "sineOut"), k(0.8, 16.0, "sineInOut"),
                              k(1.0, 30.0, "quadOut")]),
            tgt("ball", "h", [k(U0, 16.0), k(0.15, 22.0, "sineOut"), k(0.8, 16.0, "sineInOut"),
                              k(1.0, 30.0, "quadOut")]),
            tgt("ball", "alpha", [k(U0, 1.0), k(0.8, 1.0), k(1.0, 0.0, "quadIn")]),
        ]})
    return scene("sig_release_seek", 1.2, [hint("RELEASE: THE BALL SEEKS THE MOUSE-UP"),
        idle_pulse("title", "SEEK"), pad, ball], [throw])


## press + follow, superseded on release, then a chained respawn.
func _follow() -> Dictionary:
    var home := shape("home", "circle", Vector2(0.5, 0.55), Vector2(30, 30),
                      {"color": Color(0, 0, 0, 0), "outline_color": DIM, "outline": 1.0})
    var orb := shape("orb", "circle", Vector2(0.5, 0.55), Vector2(18, 18), {"color": GREEN},
        {"scale": [k(0.0, 1.0), k(0.8, 1.12, "sineInOut"), k(1.6, 1.0, "sineInOut")]})
    var grab := sig("grab", {"trigger": "press", "point": "follow", "length": 0.3,
        "point_ease": "sineOut", "point_elems": [bind("orb")],
        "targets": [tgt("orb", "scale", [k(U0, 1.0), k(1.0, 1.5, "backOut")])]})
    var drop := sig("drop", {"trigger": "release", "point": "anchor", "length": 0.45,
        "then": "respawn", "point_elems": [bind("orb")],
        "targets": [
            tgt("orb", "w", [k(U0, 27.0), k(1.0, 50.0, "cubicOut")]),
            tgt("orb", "h", [k(U0, 27.0), k(1.0, 6.0, "cubicOut")]),
            tgt("orb", "alpha", [k(U0, 1.0), k(1.0, 0.0, "quadIn")]),
        ]})
    var respawn := sig("respawn", {"length": 0.5,
        "targets": [tgt("orb", "scale", [k(U0, 0.0), k(1.0, 1.0, "backOut")]),
                    tgt("orb", "alpha", [k(U0, 0.0), k(0.4, 1.0, "sineOut")])]})
    return scene("sig_follow", 1.6, [hint("HOLD TO GRAB - RELEASE TO DROP"),
        idle_pulse("title", "FOLLOW"), home, orb], [grab, drop, respawn])


## code triggers: fired by fire() (gallery digits), reading the pointer once.
func _code() -> Dictionary:
    var flash := shape("flash", "rect", Vector2(0.5, 0.5), Vector2(1.0, 1.0),
                       {"color": Color(GOLD, 0)})
    var pin := shape("pin", "triangle", Vector2(0.5, 0.5), Vector2(12, 14),
                     {"color": Color(PINK, 0), "rot": 180.0})
    var mark := shape("mark", "circle", Vector2(0.5, 0.5), Vector2(14, 5),
                      {"color": Color(0, 0, 0, 0), "outline_color": Color(PINK, 0), "outline": 1.0})
    var f := sig("flash", {"length": 0.5, "targets": [
        tgt("flash", "alpha", [k(U0, 0.35), k(1.0, 0.0, "quadOut")]),
        tgt("title", "color", [kc(U0, GOLD), kc(1.0, WHITE, "sineIn")]),
    ]})
    var ping := sig("ping", {"point": "anchor", "length": 1.4,
        "point_elems": [bind("pin", Vector2(0, -0.05)), bind("mark", Vector2(0, 0.0))],
        "targets": [
            tgt("pin", "pos_y", [k(U0, 0.2), k(0.35, 0.5, "bounceOut")]),
            tgt("pin", "alpha", [k(U0, 1.0), k(0.8, 1.0), k(1.0, 0.0)]),
            tgt("mark", "outline_alpha", [k(U0, 0.0), k(0.3, 0.0), k(0.4, 1.0), k(1.0, 0.0)]),
            tgt("mark", "scale", [k(U0, 0.5), k(0.3, 0.5), k(1.0, 2.0, "cubicOut")]),
        ]})
    return scene("sig_code", 2.0, [flash, hint("KEY 1: FLASH   KEY 2: PING AT MOUSE"),
        idle_pulse("title", "CODE"), mark, pin], [f, ping])


## end on a one-shot: the bar runs out, `done` stamps in and holds (terminal).
func _end_once() -> Dictionary:
    var track := shape("track", "rect", Vector2(0.5, 0.5), Vector2(0.6, 0.04),
                       {"color": Color(0, 0, 0, 0), "outline_color": DIM, "outline": 0.006})
    var bar := shape("bar", "rect", Vector2(0.5, 0.5), Vector2(0.0, 0.04), {"color": CYAN},
        {"w": [k(0.0, 0.0), k(2.0, 0.6, "sineInOut")]})
    var stamp := text("stamp", "DONE", Vector2(0.5, 0.3), 20.0, Color(GREEN, 0))
    var done := sig("done", {"trigger": "end", "terminal": true, "length": 0.5,
        "targets": [
            tgt("stamp", "alpha", [k(U0, 0.0), k(0.4, 1.0)]),
            tgt("stamp", "size", [k(U0, 40.0), k(1.0, 20.0, "backOut")]),
            tgt("bar", "color", [kc(U0, WHITE), kc(1.0, GREEN, "sineOut")]),
        ]})
    var doc := scene("sig_end_once", 2.0, [hint("ONE-SHOT: END FIRES WHEN IT RUNS OUT"),
        track, bar, stamp], [done])
    doc["loop_smooth"] = false
    return doc


## end + every_loop: the lap signal fires on every loop wrap.
func _end_every_loop() -> Dictionary:
    return _laps("sig_end_every_loop", true, "EVERY LOOP: LAP ON EACH WRAP", "LAP!")


## end without every_loop: only the first wrap.
func _end_first_loop() -> Dictionary:
    return _laps("sig_end_first_loop", false, "FIRST LOOP ONLY: ONE LAP SIGNAL", "FIRST LAP!")


func _laps(nm: String, every: bool, hint_text: String, word: String) -> Dictionary:
    var lane := shape("lane", "rect", Vector2(0.5, 0.55), Vector2(0.8, 0.005), {"color": DIM})
    var goal := shape("goal", "rect", Vector2(0.1, 0.55), Vector2(0.006, 0.16), {"color": WHITE})
    var runner := shape("runner", "circle", Vector2(0.1, 0.55), Vector2(10, 10), {"color": GOLD},
        {"pos_x": [k(0.0, 0.1), k(1.5, 0.9, "sineInOut")]})
    var ring := shape("ring", "circle", Vector2(0.1, 0.55), Vector2(40, 40),
                      {"color": Color(0, 0, 0, 0), "outline_color": Color(GOLD, 0), "outline": 2.0})
    var label := text("lap_word", word, Vector2(0.5, 0.32), 20.0, Color(GOLD, 0))
    var lap := sig("lap", {"trigger": "end", "every_loop": every, "length": 0.8,
        "targets": [
            tgt("ring", "outline_alpha", [k(U0, 1.0), k(1.0, 0.0, "quadIn")]),
            tgt("ring", "scale", [k(U0, 0.2), k(1.0, 1.0, "cubicOut")]),
            tgt("goal", "color", [kc(U0, GOLD), kc(1.0, WHITE)]),
            tgt("lap_word", "alpha", [k(U0, 1.0), k(0.6, 1.0), k(1.0, 0.0)]),
            tgt("lap_word", "pos_y", [k(U0, 0.36), k(1.0, 0.3, "cubicOut")]),
        ]})
    var doc := scene(nm, 1.5, [hint(hint_text), lane, goal, ring, runner, label], [lap])
    doc["loop_blend"] = 0.0
    return doc


## then: windup -> launch -> land, one click.
func _then_chain() -> Dictionary:
    var ground := shape("ground", "rect", Vector2(0.5, 0.82), Vector2(0.5, 0.006), {"color": DIM})
    var rocket := shape("rocket", "triangle", Vector2(0.5, 0.72), Vector2(14, 24), {"color": WHITE})
    var flame := shape("flame", "triangle", Vector2(0.5, 0.82), Vector2(8, 12),
                       {"color": Color(GOLD, 0), "rot": 180.0})
    var windup := sig("windup", {"trigger": "press", "length": 0.35, "then": "launch",
        "targets": [
            tgt("rocket", "h", [k(U0, 24.0), k(1.0, 16.0, "quadOut")]),
            tgt("rocket", "pos_y", [k(U0, 0.72), k(1.0, 0.745, "quadOut")]),
            tgt("rocket", "w", [k(U0, 14.0), k(1.0, 18.0, "quadOut")]),
        ]})
    var launch := sig("launch", {"length": 0.6, "then": "land",
        "targets": [
            tgt("rocket", "pos_y", [k(U0, 0.745), k(1.0, -0.2, "expoIn")]),
            tgt("rocket", "h", [k(U0, 16.0), k(0.3, 30.0, "quadOut")]),
            tgt("rocket", "w", [k(U0, 18.0), k(0.3, 12.0, "quadOut")]),
            tgt("flame", "alpha", [k(U0, 1.0), k(0.8, 1.0), k(1.0, 0.0)]),
            tgt("flame", "pos_y", [k(U0, 0.82), k(1.0, -0.1, "expoIn")]),
        ]})
    var land := sig("land", {"length": 0.9,
        "targets": [tgt("rocket", "pos_y", [k(U0, -0.2), k(1.0, 0.72, "bounceOut")])]})
    return scene("sig_then_chain", 2.0, [hint("CLICK: WINDUP > LAUNCH > LAND"),
        idle_pulse("title", "THEN"), ground, flame, rocket], [windup, launch, land])


## The showcase: intro, a twinkling loop, and every trigger working together.
func _starfall() -> Dictionary:
    var intro := 1.2
    var dur := 4.2
    var elems: Array = []
    # The horizon glow: three stacked bands make a stepped gradient.
    for i in 3:
        var h := 0.08 + 0.07 * i
        var lo := 0.18 - 0.04 * i
        elems.append(shape("glow%d" % i, "rect", Vector2(0.5, 1.0 - h * 0.5), Vector2(1.0, h),
                           {"color": Color(0.3, 0.2, 0.55, 0.0)},
            {"alpha": [k(0.0, 0.0), k(intro, lo, "sineOut"), k(2.7, lo * 1.6, "sineInOut"),
                       k(dur, lo, "sineInOut")]}))
    # Stars: staggered twinkles, each back to its start value at the loop end.
    var stars := [Vector2(0.08, 0.14), Vector2(0.22, 0.32), Vector2(0.36, 0.1),
                  Vector2(0.62, 0.18), Vector2(0.71, 0.4), Vector2(0.9, 0.12),
                  Vector2(0.15, 0.55), Vector2(0.86, 0.6)]
    for i in stars.size():
        var ph: float = intro + 0.35 * i
        var a := [k(0.0, 0.0), k(intro, 0.5, "sineOut")]
        var sc := [k(0.0, 1.0), k(intro, 1.0)]
        var t := ph
        if t > intro + 0.05:
            a.append(k(t, 0.5))
            sc.append(k(t, 1.0))
        a.append(k(t + 0.4, 1.0, "sineOut"))
        a.append(k(t + 0.9, 0.5, "sineIn"))
        sc.append(k(t + 0.4, 1.8, "sineOut"))
        sc.append(k(t + 0.9, 1.0, "sineIn"))
        a.append(k(dur, 0.5))
        sc.append(k(dur, 1.0))
        elems.append(shape("star%d" % i, "rhombus", stars[i], Vector2(4, 6),
                           {"color": WHITE}, {"alpha": a, "scale": sc}))
    elems.append(shape("moon", "circle", Vector2(0.84, 0.3), Vector2(26, 26), {"color": Color(1, 0.95, 0.8, 1)},
        {"alpha": [k(0.0, 0.0), k(intro, 1.0, "sineOut")],
         "pos_y": [k(0.0, 0.36), k(intro, 0.3, "sineOut"), k(2.7, 0.27, "sineInOut"),
                   k(dur, 0.3, "sineInOut")]}))
    elems.append(shape("moon_bite", "circle", Vector2(0.815, 0.28), Vector2(22, 22), {"color": BG},
        {"alpha": [k(0.0, 0.0), k(intro, 1.0, "sineOut")],
         "pos_y": [k(0.0, 0.34), k(intro, 0.28, "sineOut"), k(2.7, 0.25, "sineInOut"),
                   k(dur, 0.28, "sineInOut")]}))
    elems.append(text("title", "ZEN SIGNALS", Vector2(0.5, 0.42), 20.0, GOLD,
        {"alpha": [k(0.0, 0.0), k(0.8, 1.0, "sineOut")],
         "pos_y": [k(0.0, 0.5), k(0.9, 0.42, "backOut")]}))
    elems.append(text("subtitle", "CLICK THE SKY", Vector2(0.5, 0.56), 10.0, DIM,
        {"alpha": [k(0.0, 0.0), k(0.6, 0.0), k(intro, 1.0, "sineOut"),
                   k(2.7, 0.55, "sineInOut"), k(dur, 1.0, "sineInOut")]}))
    # The comet and its trail rest off-screen, top-left, invisible.
    elems.append(shape("trail2", "circle", Vector2(-0.05, -0.05), Vector2(4, 4), {"color": Color(CYAN, 0)}))
    elems.append(shape("trail", "circle", Vector2(-0.05, -0.05), Vector2(6, 6), {"color": Color(CYAN, 0)}))
    elems.append(shape("comet", "circle", Vector2(-0.05, -0.05), Vector2(9, 9), {"color": Color(WHITE, 0)}))
    # The nova rests centred, invisible; the anchor moves it to the point.
    elems.append(shape("nova_ring", "circle", Vector2(0.5, 0.5), Vector2(70, 70),
                       {"color": Color(0, 0, 0, 0), "outline_color": Color(CYAN, 0), "outline": 2.0}))
    elems.append(shape("nova_core", "circle", Vector2(0.5, 0.5), Vector2(24, 24), {"color": Color(WHITE, 0)}))
    var sparks := {"spark_n": Vector2(0, -0.16), "spark_e": Vector2(0.1, 0),
                   "spark_s": Vector2(0, 0.16), "spark_w": Vector2(-0.1, 0)}
    for nm in sparks:
        elems.append(shape(nm, "rhombus", Vector2(0.5, 0.5), Vector2(5, 9), {"color": Color(GOLD, 0)}))

    var comet := sig("comet", {"trigger": "press", "point": "seek", "length": 0.7,
        "point_ease": "expoOut", "then": "nova",
        "point_elems": [bind("comet"), bind("trail", Vector2(-0.03, -0.05)),
                        bind("trail2", Vector2(-0.06, -0.1))],
        "targets": [
            tgt("comet", "alpha", [k(U0, 1.0), k(0.9, 1.0), k(1.0, 0.0)]),
            tgt("trail", "alpha", [k(U0, 0.7), k(0.6, 0.7), k(0.95, 0.0)]),
            tgt("trail2", "alpha", [k(U0, 0.4), k(0.5, 0.4), k(0.85, 0.0)]),
            tgt("comet", "scale", [k(U0, 0.6), k(1.0, 1.4, "quadIn")]),
        ]})
    var nova_targets := [
        tgt("nova_ring", "scale", [k(U0, 0.1), k(1.0, 1.0, "expoOut")]),
        tgt("nova_ring", "outline_alpha", [k(U0, 1.0), k(1.0, 0.0, "quadIn")]),
        tgt("nova_core", "alpha", [k(U0, 1.0), k(0.25, 0.0, "quadOut")]),
        tgt("nova_core", "scale", [k(U0, 0.3), k(0.25, 1.2, "cubicOut")]),
    ]
    for i in 3:
        nova_targets.append(tgt("glow%d" % i, "color",
            [kc(U0, Color(0.55, 0.85, 1.0)), kc(1.0, Color(0.3, 0.2, 0.55), "sineOut")]))
    var nova_binds := [bind("nova_ring"), bind("nova_core")]
    for nm in sparks:
        var d: Vector2 = sparks[nm]
        nova_binds.append(bind(nm))
        nova_targets.append(tgt(nm, "alpha", [k(U0, 1.0), k(0.6, 1.0), k(1.0, 0.0)]))
        nova_targets.append(tgt(nm, "pos_x", [k(U0, 0.5), k(1.0, 0.5 + d.x, "expoOut")]))
        nova_targets.append(tgt(nm, "pos_y", [k(U0, 0.5), k(1.0, 0.5 + d.y, "expoOut")]))
        nova_targets.append(tgt(nm, "rot", [k(U0, 0.0), k(1.0, 360.0, "cubicOut")]))
    var nova := sig("nova", {"point": "anchor", "length": 1.0,
        "point_elems": nova_binds, "targets": nova_targets})
    var shimmer := sig("shimmer", {"trigger": "end", "every_loop": true, "length": 0.9,
        "targets": [
            tgt("title", "color", [kc(U0, WHITE), kc(0.4, CYAN, "sineOut"), kc(1.0, GOLD, "sineIn")]),
            tgt("title", "size", [k(U0, 20.0), k(0.3, 22.0, "sineOut"), k(1.0, 20.0, "sineInOut")]),
        ]})
    var pop := sig("title_pop", {"length": 0.8,
        "targets": [tgt("title", "pos_y", [k(U0, 0.42), k(0.3, 0.34, "quadOut"),
                                           k(1.0, 0.42, "bounceOut")])]})
    var doc := scene("sig_starfall", dur, elems, [comet, nova, shimmer, pop])
    doc["intro_end"] = intro
    doc["loop_blend"] = 0.0
    return doc


# ---------------------------------------------------------------------------
#  Building blocks
# ---------------------------------------------------------------------------

## A looping document. Every scene but the one-shot loops, so the gallery never
## restarts it under a running signal.
func scene(nm: String, dur: float, elems: Array, sigs: Array) -> Dictionary:
    return {"name": nm, "duration": dur, "intro_end": 0.0, "outro_start": dur,
            "loop_blend": 0.3, "loop_smooth": true, "elems": elems,
            "signals": sigs, "pauses": []}


## Elements size in pixels (unit_abs) unless `size` reads as a fraction.
func shape(nm: String, kind: String, pos: Vector2, size: Vector2, opts := {},
           tracks := {}) -> Dictionary:
    var e := ZenElemFactory.new_elem("shape", nm)
    e["shape"] = kind
    e["pos"] = pos
    e["size"] = size
    e["unit_abs"] = size.x > 1.0 or size.y > 1.0
    for key in opts: e[key] = opts[key]
    # Outline alpha rides outline_color's alpha (base_scalar); none = no outline.
    if not opts.has("outline_color"): e["outline_color"] = Color(0, 0, 0, 0)
    e["tracks"] = tracks
    return e


## Text in pixels (10 = the bitmap font's native size).
func text(nm: String, s: String, pos: Vector2, px: float, col: Color, tracks := {}) -> Dictionary:
    var e := ZenElemFactory.new_elem("text", nm)
    e["text"] = s
    e["pos"] = pos
    e["size"] = Vector2(px, px)
    e["unit_abs"] = true
    e["color"] = col
    e["tracks"] = tracks
    return e


func hint(s: String) -> Dictionary:
    return text("hint", s, Vector2(0.5, 0.93), 10.0, DIM)


## The scene's name, breathing gently at the top.
func idle_pulse(nm: String, s: String) -> Dictionary:
    return text(nm, s, Vector2(0.5, 0.1), 10.0, WHITE,
        {"alpha": [k(0.0, 0.6), k(0.5, 1.0, "sineInOut"), k(1.0, 0.6, "sineInOut")]})


func k(t: float, v: float, ease := "linear") -> Dictionary:
    return {"t": t, "v": v, "ease": ease}


func kc(t: float, c: Color, ease := "linear") -> Dictionary:
    return {"t": t, "c": Color(c, 1.0), "ease": ease}


func sig(nm: String, fields: Dictionary) -> Dictionary:
    var s := ZenSignalData.defaults(nm)
    for key in fields: s[key] = fields[key]
    return ZenSignalData.normalize(s)


func tgt(elem: String, prop: String, keys: Array) -> Dictionary:
    return {"elem": elem, "prop": prop, "keys": keys}


func bind(elem: String, off := Vector2.ZERO) -> Dictionary:
    return {"elem": elem, "off": off}


func _save(doc: Dictionary) -> String:
    var canvas := ZenElemFactory.build(doc)
    canvas.design_size = SIZE
    canvas.clear_color = BG
    canvas.sync_from_animation()
    var path := ZenSceneOps.save(canvas, String(doc["name"]), FOLDER)
    canvas.free()
    return path
