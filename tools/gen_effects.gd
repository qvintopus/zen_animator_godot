extends SceneTree
##
## Builds the effect showcase scenes (anims/effects/fx_*.tscn): small timeline-only
## animations, each one a template to copy into other scenes. Re-run after changing
## a design here; the scenes are plain Zen scenes and stay editable afterwards.
##
##   Godot --headless --path . --script res://tools/gen_effects.gd
##
## Effects that must loop seamlessly are authored so every element is back at its
## first-key pose on the last frame (loop_blend 0).
##

const SIZE := Vector2(320, 180)
const BG := Color(0.07, 0.08, 0.12, 1)
const FOLDER := "effects"
const WHITE := Color(0.96, 0.96, 0.96, 1)
const DIM := Color(0.55, 0.6, 0.7, 1)
const GOLD := Color(1.0, 0.8, 0.35, 1)
const CYAN := Color(0.35, 0.85, 1.0, 1)
const PINK := Color(1.0, 0.4, 0.6, 1)
const GREEN := Color(0.45, 0.95, 0.55, 1)


func _init() -> void:
    for fn in [_ring_pulse, _sparkle_burst, _shake, _wobble]:
        var doc: Dictionary = fn.call()
        var path := _save(doc)
        print("%s  %s" % ["wrote" if not path.is_empty() else "FAILED", doc["name"]])
    quit()


# ---------------------------------------------------------------------------
#  Effects
# ---------------------------------------------------------------------------

## Three rings expanding and fading in turn, round a pulsing core.
func _ring_pulse() -> Dictionary:
    var elems: Array = [hint("RING PULSE"), ]
    var life := 0.8
    for i in 3:
        var s := life * i
        var a: Array = []
        if s > 0.0: a.append(k(0.0, 0.0)); a.append(k(s - 0.01, 0.0))
        a.append(k(s, 1.0)); a.append(k(s + life, 0.0, "quadIn"))
        var sc: Array = []
        if s > 0.0: sc.append(k(0.0, 0.1))
        sc.append(k(s, 0.1)); sc.append(k(s + life, 1.6, "cubicOut"))
        elems.append(shape("ring%d" % (i + 1), "circle", Vector2(0.5, 0.5), Vector2(80, 80),
            {"color": Color(CYAN, 0), "outline_color": Color(CYAN, 0), "outline": 3.0},
            {"outline_alpha": a, "scale": sc}))
    elems.append(shape("core", "circle", Vector2(0.5, 0.5), Vector2(14, 14), {"color": WHITE},
        {"scale": [k(0.0, 1.0), k(0.2, 1.35, "quadOut"), k(0.8, 1.0, "quadIn"),
                   k(1.0, 1.35, "quadOut"), k(1.6, 1.0, "quadIn"), k(1.8, 1.35, "quadOut"),
                   k(2.4, 1.0, "quadIn")]}))
    var doc := scene("fx_ring_pulse", 2.4, elems)
    doc["loop_blend"] = 0.0
    return doc


## A flash and twelve sparks flung outward, shrinking as they fade.
func _sparkle_burst() -> Dictionary:
    var elems: Array = [hint("SPARKLE BURST")]
    var n := 12
    for i in n:
        var ang := TAU * i / n
        var r := 62.0 if i % 2 == 0 else 38.0
        var col := GOLD if i % 2 == 0 else WHITE
        var sz := 9.0 if i % 2 == 0 else 6.0
        var d := Vector2(cos(ang) * r / SIZE.x, sin(ang) * r / SIZE.y)
        elems.append(shape("spark%d" % (i + 1), "rhombus", Vector2(0.5, 0.5), Vector2(sz, sz),
            {"color": col, "alpha": 0.0},
            {"pos_x": [k(0.0, 0.5), k(0.1, 0.5), k(1.3, 0.5 + d.x, "cubicOut")],
             "pos_y": [k(0.0, 0.5), k(0.1, 0.5), k(1.3, 0.5 + d.y, "cubicOut")],
             "alpha": [k(0.0, 0.0), k(0.09, 0.0), k(0.1, 1.0), k(0.7, 1.0), k(1.3, 0.0, "sineIn")],
             "scale": [k(0.0, 1.0), k(0.1, 1.2), k(1.3, 0.0, "quadIn")],
             "rot": [k(0.0, 0.0), k(0.1, 0.0), k(1.3, 180.0 if i % 2 == 0 else -180.0, "cubicOut")]}))
    elems.append(shape("flash", "circle", Vector2(0.5, 0.5), Vector2(56, 56),
        {"color": Color(WHITE, 0)},
        {"alpha": [k(0.0, 0.0), k(0.08, 0.0), k(0.1, 0.9), k(0.5, 0.0, "quadOut")],
         "scale": [k(0.0, 0.2), k(0.1, 0.2), k(0.5, 1.2, "cubicOut")]}))
    var doc := scene("fx_sparkle_burst", 2.0, elems)
    doc["loop_blend"] = 0.0
    return doc


## A box takes a hit: flashes, jitters with a decaying amplitude, settles.
func _shake() -> Dictionary:
    var px: Array = [k(0.0, 0.5), k(0.3, 0.5)]
    var py: Array = [k(0.0, 0.5), k(0.3, 0.5)]
    var rt: Array = [k(0.0, 0.0), k(0.3, 0.0)]
    var steps := 14
    for i in steps:
        var decay := 1.0 - float(i + 1) / (steps + 1)
        var sgn := 1.0 if i % 2 == 0 else -1.0
        var t := 0.3 + 0.05 * (i + 1)
        px.append(k(t, 0.5 + sgn * 0.045 * decay, "sineInOut"))
        py.append(k(t, 0.5 - sgn * 0.02 * decay, "sineInOut"))
        rt.append(k(t, sgn * 6.0 * decay, "sineInOut"))
    var end := 0.3 + 0.05 * (steps + 1)
    px.append(k(end, 0.5, "sineOut")); py.append(k(end, 0.5, "sineOut")); rt.append(k(end, 0.0, "sineOut"))
    var elems: Array = [hint("SHAKE"),
        shape("impact", "rhombus", Vector2(0.5, 0.5), Vector2(110, 110), {"color": Color(GOLD, 0)},
            {"alpha": [k(0.0, 0.0), k(0.29, 0.0), k(0.3, 0.8), k(0.7, 0.0, "quadOut")],
             "scale": [k(0.0, 0.5), k(0.3, 0.5), k(0.7, 1.4, "cubicOut")],
             "rot": [k(0.0, 0.0), k(0.3, 0.0), k(0.7, 45.0, "cubicOut")]}),
        shape("box", "rect", Vector2(0.5, 0.5), Vector2(60, 60), {"color": CYAN},
            {"pos_x": px, "pos_y": py, "rot": rt,
             "color": [kc(0.0, CYAN), kc(0.29, CYAN), kc(0.3, PINK), kc(0.7, CYAN, "sineOut")]})]
    var doc := scene("fx_shake", 2.0, elems)
    doc["loop_blend"] = 0.0
    return doc


## An elastic pop-in, a damped rotational wobble, then a shrink away.
func _wobble() -> Dictionary:
    var elems: Array = [hint("WOBBLE"),
        shape("badge", "rhombus", Vector2(0.5, 0.5), Vector2(64, 64), {"color": GREEN},
            {"scale": [k(0.0, 0.0), k(0.2, 0.0), k(1.1, 1.0, "elasticOut"), k(2.3, 1.0),
                       k(2.8, 0.0, "backIn"), k(3.0, 0.0)],
             "rot": [k(0.0, 0.0), k(1.2, 0.0), k(1.4, -14.0, "sineOut"), k(1.65, 10.0, "sineInOut"),
                     k(1.9, -6.0, "sineInOut"), k(2.1, 3.0, "sineInOut"), k(2.3, 0.0, "sineInOut"),
                     k(3.0, 0.0)],
             "w": [k(0.0, 64.0), k(1.2, 64.0), k(1.3, 56.0, "sineOut"), k(1.5, 68.0, "sineInOut"),
                   k(1.8, 62.0, "sineInOut"), k(2.1, 64.0, "sineInOut")],
             "h": [k(0.0, 64.0), k(1.2, 64.0), k(1.3, 72.0, "sineOut"), k(1.5, 60.0, "sineInOut"),
                   k(1.8, 66.0, "sineInOut"), k(2.1, 64.0, "sineInOut")]})]
    var doc := scene("fx_wobble", 3.0, elems)
    doc["loop_blend"] = 0.0
    return doc


# ---------------------------------------------------------------------------
#  Building blocks
# ---------------------------------------------------------------------------

func scene(nm: String, dur: float, elems: Array) -> Dictionary:
    return {"name": nm, "duration": dur, "intro_end": 0.0, "outro_start": dur,
            "loop_blend": 0.3, "loop_smooth": true, "elems": elems,
            "signals": [], "pauses": []}


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


func k(t: float, v: float, ease := "linear") -> Dictionary:
    return {"t": t, "v": v, "ease": ease}


func kc(t: float, c: Color, ease := "linear") -> Dictionary:
    return {"t": t, "c": Color(c, 1.0), "ease": ease}


func _save(doc: Dictionary) -> String:
    var canvas := ZenElemFactory.build(doc)
    canvas.design_size = SIZE
    canvas.clear_color = BG
    canvas.sync_from_animation()
    var path := ZenSceneOps.save(canvas, String(doc["name"]), FOLDER)
    canvas.free()
    return path
