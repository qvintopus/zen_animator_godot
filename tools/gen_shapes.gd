extends SceneTree
##
## Builds a set of 64x64 pixel-shape icons (assets/shapes/*.tres): general coding,
## coding with AI, a few unrelated ones and the ZombieShooter set. Each is painted as solid FILL from a
## handful of primitives, then auto_outline() rims it - the line-art look of the
## ported icons. The results are plain ZenPixelShape assets, editable in the shape
## editor afterwards, so a re-run KEEPS a name that already exists; pass --force to
## overwrite.
##
##   Godot --headless --path . --script res://tools/gen_shapes.gd [-- --force]
##

const SIZE := Vector2i(64, 64)
const DIR := "res://assets/shapes"

## The shape being painted.
var s: ZenPixelShape


func _init() -> void:
    var force := "--force" in OS.get_cmdline_user_args()
    var shapes := {
        # coding in general
        "code_brackets": _code_brackets, "curly_braces": _curly_braces, "terminal": _terminal,
        "code_file": _code_file, "folder": _folder, "bug": _bug, "gear": _gear,
        "git_branch": _git_branch, "database": _database, "server": _server, "cloud": _cloud,
        "loop_arrows": _loop_arrows, "check_mark": _check_mark, "cross_mark": _cross_mark,
        "warning": _warning, "magnifier": _magnifier, "lock": _lock, "laptop": _laptop,
        "keyboard": _keyboard, "cursor_arrow": _cursor_arrow, "flowchart": _flowchart,
        # coding with AI
        "chip": _chip, "robot_head": _robot_head, "chat_bubble": _chat_bubble,
        "prompt_box": _prompt_box, "sparkles": _sparkles, "neural_net": _neural_net,
        "magic_wand": _magic_wand, "tokens": _tokens, "agent_loop": _agent_loop, "diff": _diff,
        # unrelated
        "heart": _heart, "star": _star, "coffee_cup": _coffee_cup, "rocket": _rocket,
        "cat": _cat, "tree": _tree, "sun": _sun, "moon": _moon, "music_note": _music_note,
        "house": _house,
        # ZombieShooter (anims/ZombieShooter/)
        "skull": _skull, "zombie_hand": _zombie_hand, "crosshair": _crosshair, "splat": _splat,
        "bullet": _bullet, "pistol": _pistol, "shotgun": _shotgun, "hazard_stripes": _hazard_stripes,
        "door": _door, "katana": _katana, "rifle": _rifle,
    }
    DirAccess.make_dir_recursive_absolute(DIR)
    for nm: String in shapes:
        var path := "%s/%s.tres" % [DIR, nm]
        if FileAccess.file_exists(path) and not force:
            print("kept   ", nm)
            continue
        s = ZenPixelShape.new()
        s.size = SIZE
        (shapes[nm] as Callable).call()
        s.auto_outline()
        print("%s  %s" % ["wrote" if ResourceSaver.save(s, path) == OK else "FAILED", nm])
    quit()


# ---------------------------------------------------------------------------
#  Coding in general
# ---------------------------------------------------------------------------

func _code_brackets() -> void:
    polyline([Vector2(22, 18), Vector2(10, 32), Vector2(22, 46)], 5)
    polyline([Vector2(42, 18), Vector2(54, 32), Vector2(42, 46)], 5)
    line(Vector2(36, 14), Vector2(28, 50), 5)


func _curly_braces() -> void:
    polyline([Vector2(24, 10), Vector2(19, 12), Vector2(17, 18), Vector2(17, 27), Vector2(11, 32),
              Vector2(17, 37), Vector2(17, 46), Vector2(19, 52), Vector2(24, 54)], 5)
    mirror_x()
    disc(Vector2(32, 32), 3)


func _terminal() -> void:
    round_frame(Rect2(6, 10, 52, 44), 5, 4)
    rect(Rect2(6, 10, 52, 9))
    for x in [13, 19, 25]: disc(Vector2(x, 14), 1.6, ZenPixelShape.EMPTY)
    polyline([Vector2(14, 28), Vector2(22, 34), Vector2(14, 40)], 4)
    rect(Rect2(26, 39, 14, 4))


func _code_file() -> void:
    polyline([Vector2(14, 6), Vector2(40, 6), Vector2(50, 16), Vector2(50, 58), Vector2(14, 58),
              Vector2(14, 6)], 4)
    polyline([Vector2(40, 6), Vector2(40, 16), Vector2(50, 16)], 4)
    line(Vector2(20, 26), Vector2(34, 26), 3)
    line(Vector2(24, 33), Vector2(44, 33), 3)
    line(Vector2(24, 40), Vector2(38, 40), 3)
    line(Vector2(20, 47), Vector2(30, 47), 3)


func _folder() -> void:
    polyline([Vector2(6, 14), Vector2(24, 14), Vector2(28, 20), Vector2(58, 20), Vector2(58, 52),
              Vector2(6, 52), Vector2(6, 14)], 4)
    line(Vector2(6, 27), Vector2(58, 27), 4)


func _bug() -> void:
    polyline([Vector2(21, 32), Vector2(10, 27)], 3)
    polyline([Vector2(20, 40), Vector2(8, 40)], 3)
    polyline([Vector2(21, 48), Vector2(10, 55)], 3)
    polyline([Vector2(28, 14), Vector2(23, 6)], 3)
    mirror_x()
    ellipse(Vector2(32, 39), 13, 16)
    disc(Vector2(32, 19), 7)
    line(Vector2(18, 25), Vector2(46, 25), 2, ZenPixelShape.EMPTY)
    line(Vector2(32, 27), Vector2(32, 56), 2, ZenPixelShape.EMPTY)


func _gear() -> void:
    var c := Vector2(32, 32)
    disc(c, 20)
    for i in 8:
        var pts: Array = [Vector2(-5, -17), Vector2(5, -17), Vector2(4, -28), Vector2(-4, -28)]
        poly(pts.map(func(p): return c + (p as Vector2).rotated(TAU * i / 8.0)))
    disc(c, 8, ZenPixelShape.EMPTY)


func _git_branch() -> void:
    line(Vector2(20, 17), Vector2(20, 47), 4)
    curve(Vector2(44, 27), Vector2(44, 42), Vector2(21, 44), 4)
    for c in [Vector2(20, 11), Vector2(20, 53), Vector2(44, 21)]:
        disc(c, 7)
        disc(c, 3, ZenPixelShape.EMPTY)


func _database() -> void:
    ellipse_arc(Vector2(32, 14), 20, 7, 0, 360, 5)
    line(Vector2(12, 14), Vector2(12, 50), 4)
    line(Vector2(52, 14), Vector2(52, 50), 4)
    for y in [27, 39, 50]: ellipse_arc(Vector2(32, y), 20, 7, 0, 180, 5)


func _server() -> void:
    for y in [6, 24, 42]:
        round_frame(Rect2(8, y, 48, 16), 3, 4)
        disc(Vector2(17, y + 8), 2.5)
        line(Vector2(34, y + 8), Vector2(47, y + 8), 3)


func _cloud() -> void:
    disc(Vector2(20, 38), 11)
    disc(Vector2(33, 28), 15)
    disc(Vector2(46, 37), 11)
    rect(Rect2(20, 36, 26, 13))


func _loop_arrows() -> void:
    var c := Vector2(32, 32)
    for a0: float in [200.0, 20.0]:
        arc(c, 19, 5, a0, a0 + 125.0)
        var end := a0 + 125.0
        var dir := Vector2(-sin(deg_to_rad(end)), cos(deg_to_rad(end)))
        arrow_head(c + Vector2.from_angle(deg_to_rad(end)) * 19, dir, 8)


func _check_mark() -> void:
    polyline([Vector2(12, 34), Vector2(26, 48), Vector2(52, 18)], 7)


func _cross_mark() -> void:
    line(Vector2(16, 16), Vector2(48, 48), 7)
    line(Vector2(48, 16), Vector2(16, 48), 7)


func _warning() -> void:
    polyline([Vector2(32, 8), Vector2(58, 54), Vector2(6, 54), Vector2(32, 8)], 5)
    line(Vector2(32, 24), Vector2(32, 37), 5)
    disc(Vector2(32, 46), 3)


func _magnifier() -> void:
    ring(Vector2(26, 26), 16, 5)
    line(Vector2(38, 38), Vector2(54, 54), 8)


func _lock() -> void:
    arc(Vector2(32, 26), 11, 5, 180, 360)
    line(Vector2(21, 26), Vector2(21, 31), 5)
    line(Vector2(43, 26), Vector2(43, 31), 5)
    round_rect(Rect2(12, 30, 40, 26), 4)
    disc(Vector2(32, 40), 4, ZenPixelShape.EMPTY)
    line(Vector2(32, 40), Vector2(32, 49), 3, ZenPixelShape.EMPTY)


func _laptop() -> void:
    round_frame(Rect2(12, 12, 40, 30), 3, 4)
    poly([Vector2(4, 45), Vector2(60, 45), Vector2(56, 53), Vector2(8, 53)])
    line(Vector2(27, 48), Vector2(37, 48), 2, ZenPixelShape.EMPTY)


func _keyboard() -> void:
    round_frame(Rect2(4, 16, 56, 32), 4, 3)
    for row in 2:
        for i in 7: rect(Rect2(10 + i * 7, 22 + row * 7, 4, 4))
    rect(Rect2(18, 37, 28, 4))


func _cursor_arrow() -> void:
    poly([Vector2(18, 6), Vector2(18, 48), Vector2(28, 39), Vector2(35, 55), Vector2(43, 51),
          Vector2(36, 36), Vector2(49, 35)])


func _flowchart() -> void:
    line(Vector2(32, 16), Vector2(32, 24), 3)
    polyline([Vector2(22, 32), Vector2(14, 32), Vector2(14, 48)], 3)
    polyline([Vector2(42, 32), Vector2(50, 32), Vector2(50, 48)], 3)
    round_frame(Rect2(21, 4, 22, 13), 2, 3)
    polyline([Vector2(32, 23), Vector2(42, 32), Vector2(32, 41), Vector2(22, 32), Vector2(32, 23)], 3)
    round_frame(Rect2(4, 47, 21, 13), 2, 3)
    round_frame(Rect2(39, 47, 21, 13), 2, 3)


# ---------------------------------------------------------------------------
#  Coding with AI
# ---------------------------------------------------------------------------

func _chip() -> void:
    for i in 4:
        var v := 21 + i * 7
        line(Vector2(v, 5), Vector2(v, 16), 3)
        line(Vector2(v, 48), Vector2(v, 59), 3)
        line(Vector2(5, v), Vector2(16, v), 3)
        line(Vector2(48, v), Vector2(59, v), 3)
    round_frame(Rect2(15, 15, 34, 34), 3, 4)
    rect(Rect2(25, 25, 14, 14))


func _robot_head() -> void:
    line(Vector2(32, 18), Vector2(32, 10), 3)
    disc(Vector2(32, 8), 3.5)
    rect(Rect2(5, 28, 7, 13))
    rect(Rect2(52, 28, 7, 13))
    round_frame(Rect2(11, 18, 42, 34), 6, 4)
    disc(Vector2(24, 32), 4.5)
    disc(Vector2(40, 32), 4.5)
    line(Vector2(24, 43), Vector2(40, 43), 3)


func _chat_bubble() -> void:
    round_frame(Rect2(6, 8, 52, 36), 9, 4)
    poly([Vector2(15, 40), Vector2(29, 40), Vector2(13, 57)])
    poly([Vector2(19, 38), Vector2(25, 38), Vector2(17, 47)], ZenPixelShape.EMPTY)
    for x in [20, 32, 44]: disc(Vector2(x, 26), 3.5)


func _prompt_box() -> void:
    round_frame(Rect2(4, 20, 56, 24), 7, 4)
    line(Vector2(14, 27), Vector2(14, 37), 3)
    for x in [20, 25, 30]: disc(Vector2(x, 34), 1.5)
    poly([Vector2(42, 25), Vector2(54, 32), Vector2(42, 39), Vector2(45, 32)])
    star4(Vector2(52, 10), 7)


func _sparkles() -> void:
    star4(Vector2(26, 36), 21)
    star4(Vector2(49, 14), 10)
    star4(Vector2(51, 48), 6)


func _neural_net() -> void:
    var layers: Array = [[16.0, 32.0, 48.0], [10.0, 25.0, 40.0, 55.0], [24.0, 40.0]]
    var xs: Array = [9.0, 32.0, 55.0]
    for l in 2:
        for a: float in layers[l]:
            for b: float in layers[l + 1]:
                line(Vector2(xs[l], a), Vector2(xs[l + 1], b), 2)
    for l in 3:
        for y: float in layers[l]: disc(Vector2(xs[l], y), 5)


func _magic_wand() -> void:
    line(Vector2(9, 55), Vector2(36, 28), 6)
    star4(Vector2(43, 21), 11)
    star4(Vector2(17, 14), 5)
    star4(Vector2(54, 42), 5)


func _tokens() -> void:
    var rows: Array = [[14, 10, 20], [8, 22, 14], [18, 12]]
    for r in rows.size():
        var x := 6
        for w: int in rows[r]:
            round_rect(Rect2(x, 10 + r * 16, w, 12), 2)
            x += w + 3


func _agent_loop() -> void:
    var c := Vector2(32, 32)
    for a0: float in [-80.0, 40.0, 160.0]:
        var end := a0 + 90.0
        arc(c, 23, 4, a0, end)
        var dir := Vector2(-sin(deg_to_rad(end)), cos(deg_to_rad(end)))
        arrow_head(c + Vector2.from_angle(deg_to_rad(end)) * 23, dir, 7)
    disc(c, 8)


func _diff() -> void:
    for row in 3:
        var y := 14 + row * 18
        line(Vector2(8, y), Vector2(18, y), 3)
        if row != 1: line(Vector2(13, y - 5), Vector2(13, y + 5), 3)
        line(Vector2(25, y), Vector2([54, 44, 50][row], y), 4)


# ---------------------------------------------------------------------------
#  Unrelated
# ---------------------------------------------------------------------------

func _heart() -> void:
    disc(Vector2(21, 23), 13)
    disc(Vector2(43, 23), 13)
    poly([Vector2(9, 28), Vector2(55, 28), Vector2(32, 56)])


func _star() -> void:
    var pts: Array = []
    for i in 10:
        var r := 28.0 if i % 2 == 0 else 11.5
        pts.append(Vector2(32, 34) + Vector2.from_angle(deg_to_rad(-90 + 36 * i)) * r)
    poly(pts)


func _coffee_cup() -> void:
    arc(Vector2(46, 36), 8, 4, -90, 90)
    polyline([Vector2(12, 24), Vector2(46, 24), Vector2(42, 54), Vector2(16, 54), Vector2(12, 24)], 4)
    for x in [23, 34]:
        curve(Vector2(x, 19), Vector2(x - 5, 13), Vector2(x + 1, 6), 3)


func _rocket() -> void:
    poly([Vector2(22, 32), Vector2(11, 49), Vector2(22, 45)])
    poly([Vector2(26, 47), Vector2(38, 47), Vector2(32, 59)])
    mirror_x()
    poly([Vector2(32, 3), Vector2(42, 16), Vector2(42, 45), Vector2(22, 45), Vector2(22, 16)])
    disc(Vector2(32, 22), 5.5, ZenPixelShape.EMPTY)
    disc(Vector2(32, 22), 3)


func _cat() -> void:
    poly([Vector2(13, 32), Vector2(15, 7), Vector2(31, 24)])
    line(Vector2(3, 39), Vector2(14, 42), 3)
    line(Vector2(4, 50), Vector2(14, 47), 3)
    mirror_x()
    ellipse(Vector2(32, 38), 20, 16)
    ellipse(Vector2(24, 36), 2, 4, ZenPixelShape.EMPTY)
    ellipse(Vector2(40, 36), 2, 4, ZenPixelShape.EMPTY)
    poly([Vector2(29, 43), Vector2(35, 43), Vector2(32, 46)], ZenPixelShape.EMPTY)


func _tree() -> void:
    rect(Rect2(28, 36, 9, 21))
    disc(Vector2(32, 20), 15)
    disc(Vector2(21, 31), 11)
    disc(Vector2(43, 31), 11)
    line(Vector2(12, 58), Vector2(52, 58), 3)


func _sun() -> void:
    var c := Vector2(32, 32)
    disc(c, 12)
    for i in 8:
        var d := Vector2.from_angle(TAU * i / 8.0)
        line(c + d * 17, c + d * 27, 4)


func _moon() -> void:
    disc(Vector2(29, 33), 23)
    disc(Vector2(42, 24), 19, ZenPixelShape.EMPTY)
    star4(Vector2(51, 49), 6)


func _music_note() -> void:
    line(Vector2(24, 47), Vector2(24, 16), 4)
    line(Vector2(50, 41), Vector2(50, 10), 4)
    poly([Vector2(22, 12), Vector2(52, 5), Vector2(52, 14), Vector2(22, 21)])
    ellipse(Vector2(17, 48), 8, 6)
    ellipse(Vector2(43, 42), 8, 6)


func _house() -> void:
    rect(Rect2(42, 10, 7, 14))
    polyline([Vector2(13, 28), Vector2(13, 56), Vector2(51, 56), Vector2(51, 28)], 4)
    polyline([Vector2(6, 31), Vector2(32, 9), Vector2(58, 31)], 5)
    rect(Rect2(26, 38, 12, 18))


# ---------------------------------------------------------------------------
#  ZombieShooter
# ---------------------------------------------------------------------------

func _skull() -> void:
    ellipse(Vector2(32, 27), 22, 20)
    round_rect(Rect2(19, 38, 26, 16), 4)
    ellipse(Vector2(23, 29), 6, 7, ZenPixelShape.EMPTY)
    ellipse(Vector2(41, 29), 6, 7, ZenPixelShape.EMPTY)
    poly([Vector2(32, 35), Vector2(28, 42), Vector2(36, 42)], ZenPixelShape.EMPTY)
    for x in [25, 32, 39]: rect(Rect2(x - 1, 47, 2, 8), ZenPixelShape.EMPTY)


## A rotting hand clawing up out of the ground.
func _zombie_hand() -> void:
    rect(Rect2(4, 54, 56, 6))
    for b in [Vector2(10, 54), Vector2(50, 55), Vector2(20, 53)]: ellipse(b, 6, 3)
    round_rect(Rect2(24, 30, 18, 26), 3)
    polyline([Vector2(26, 32), Vector2(22, 20), Vector2(20, 10)], 4)
    polyline([Vector2(31, 30), Vector2(30, 14), Vector2(31, 5)], 4)
    polyline([Vector2(36, 30), Vector2(38, 15), Vector2(41, 8)], 4)
    polyline([Vector2(40, 32), Vector2(45, 22), Vector2(49, 17)], 4)
    polyline([Vector2(25, 42), Vector2(16, 36), Vector2(12, 30)], 4)
    rect(Rect2(30, 40, 6, 4), ZenPixelShape.EMPTY)


func _crosshair() -> void:
    ring(Vector2(32, 32), 20, 4)
    for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
        line(Vector2(32, 32) + d * 10, Vector2(32, 32) + d * 29, 4)
    disc(Vector2(32, 32), 2.5)


## A blood splat: a body, lobes and loose drops.
func _splat() -> void:
    disc(Vector2(32, 32), 15)
    var rng := RandomNumberGenerator.new()
    rng.seed = 7
    for i in 9:
        var a := deg_to_rad(i * 40.0 + rng.randf_range(-12, 12))
        var r := rng.randf_range(14, 20)
        disc(Vector2(32, 32) + Vector2.from_angle(a) * r, rng.randf_range(5, 8))
        disc(Vector2(32, 32) + Vector2.from_angle(a) * (r + 10), rng.randf_range(1.8, 3.2))


func _bullet() -> void:
    round_rect(Rect2(14, 25, 26, 14), 2)
    ellipse(Vector2(40, 32), 12, 7)
    rect(Rect2(10, 24, 5, 16))
    rect(Rect2(15, 27, 2, 10), ZenPixelShape.EMPTY)


func _pistol() -> void:
    round_rect(Rect2(8, 18, 46, 12), 2)
    poly([Vector2(14, 29), Vector2(30, 29), Vector2(27, 52), Vector2(13, 52)])
    ring(Vector2(31, 33), 5, 3)
    rect(Rect2(48, 15, 4, 4))
    rect(Rect2(12, 21, 30, 2), ZenPixelShape.EMPTY)


func _shotgun() -> void:
    rect(Rect2(20, 22, 42, 5))
    rect(Rect2(20, 28, 34, 4))
    round_rect(Rect2(30, 31, 14, 6), 2)
    poly([Vector2(2, 34), Vector2(22, 22), Vector2(26, 32), Vector2(8, 44)])
    arc(Vector2(26, 37), 4, 2.5, 0, 180)


## The game's Sword (sword_0.png: a white blade on a maroon grip) drawn as a
## katana, hilt low-left, the slightly curved blade rising to the upper right.
func _katana() -> void:
    var base := Vector2(21, 43)
    var tip := Vector2(60, 4)
    var n := Vector2(1, 1).normalized()       # across the blade; +n is the edge side
    var mid := base.lerp(tip, 0.55) - n * 1.5   # the curve bows toward the spine
    poly([base + n * 3.6, mid + n * 3.4, tip.lerp(mid, 0.12) + n * 2.0, tip,
          mid - n * 3.0, base - n * 3.2])
    line(Vector2(15, 39), Vector2(25, 49), 4)  # guard (tsuba)
    line(Vector2(18, 46), Vector2(7, 57), 5)   # grip
    for i in 3:
        var c := Vector2(16, 48).lerp(Vector2(9, 55), i / 2.0)
        rect(Rect2(c - Vector2(0.5, 0.5), Vector2(1, 1)), ZenPixelShape.EMPTY)
    disc(Vector2(5.5, 58.5), 2.5)              # pommel (kashira)


## The game's Assault Riffle (gun_3.png): stock, receiver, long barrel, curved
## magazine and a pistol grip, pointing right.
func _rifle() -> void:
    poly([Vector2(1, 24), Vector2(18, 23), Vector2(18, 33), Vector2(4, 39), Vector2(1, 39)])
    rect(Rect2(17, 21, 30, 11))
    rect(Rect2(46, 24, 17, 4))
    rect(Rect2(44, 21, 6, 2))
    rect(Rect2(26, 17, 9, 4))
    poly([Vector2(21, 31), Vector2(28, 31), Vector2(25, 45), Vector2(18, 45)])
    poly([Vector2(35, 31), Vector2(42, 31), Vector2(46, 45), Vector2(39, 46)])
    rect(Rect2(5, 28, 9, 2), ZenPixelShape.EMPTY)
    for x in [38, 42]: rect(Rect2(x, 24, 2, 4), ZenPixelShape.EMPTY)


## Diagonal warning bands, edge to edge, for sweeping across a banner.
func _hazard_stripes() -> void:
    for i in range(-4, 6):
        var x := i * 16.0
        poly([Vector2(x, 64), Vector2(x + 8, 64), Vector2(x + 40, 0), Vector2(x + 32, 0)])
    rect(Rect2(0, 0, 64, 3))
    rect(Rect2(0, 61, 64, 3))


## A boarded-up doorway (rooms left to clear).
func _door() -> void:
    round_frame(Rect2(14, 6, 36, 54), 3, 4)
    rect(Rect2(8, 58, 48, 4))
    line(Vector2(12, 20), Vector2(52, 30), 6)
    line(Vector2(12, 42), Vector2(52, 34), 6)
    disc(Vector2(42, 34), 2)


# ---------------------------------------------------------------------------
#  Raster kit: every primitive paints `v` (FILL by default; EMPTY cuts a hole)
#  into the cells whose centre it covers. Coordinates are cell centres.
# ---------------------------------------------------------------------------

## Paint every cell in `area` (clipped to the grid) whose centre passes `hit`.
func _paint(area: Rect2, hit: Callable, v: int) -> void:
    var x0 := maxi(0, floori(area.position.x))
    var y0 := maxi(0, floori(area.position.y))
    var x1 := mini(s.size.x - 1, ceili(area.end.x))
    var y1 := mini(s.size.y - 1, ceili(area.end.y))
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if hit.call(Vector2(x, y)): s.set_cell(x, y, v)


func disc(c: Vector2, r: float, v := ZenPixelShape.FILL) -> void:
    _paint(Rect2(c - Vector2(r, r), Vector2(r, r) * 2), func(p): return p.distance_to(c) <= r, v)


func ellipse(c: Vector2, rx: float, ry: float, v := ZenPixelShape.FILL) -> void:
    _paint(Rect2(c - Vector2(rx, ry), Vector2(rx, ry) * 2),
        func(p): return pow((p.x - c.x) / rx, 2) + pow((p.y - c.y) / ry, 2) <= 1.0, v)


func ring(c: Vector2, r: float, w: float, v := ZenPixelShape.FILL) -> void:
    arc(c, r, w, 0, 360, v)


## A ring of width `w` from angle a0 to a1 (degrees, 0 = right, y down so it
## runs clockwise), round-capped.
func arc(c: Vector2, r: float, w: float, a0: float, a1: float, v := ZenPixelShape.FILL) -> void:
    var span := a1 - a0
    var e := r + w
    _paint(Rect2(c - Vector2(e, e), Vector2(e, e) * 2), func(p):
        if absf(p.distance_to(c) - r) > w / 2.0: return false
        return span >= 360.0 or fposmod(rad_to_deg((p - c).angle()) - a0, 360.0) <= span, v)
    if span < 360.0:
        disc(c + Vector2.from_angle(deg_to_rad(a0)) * r, w / 2.0, v)
        disc(c + Vector2.from_angle(deg_to_rad(a1)) * r, w / 2.0, v)


## An elliptical outline arc of width `w`, sampled as a polyline.
func ellipse_arc(c: Vector2, rx: float, ry: float, a0: float, a1: float, w: float,
        v := ZenPixelShape.FILL) -> void:
    var pts: Array = []
    for i in 49:
        var a := deg_to_rad(lerpf(a0, a1, i / 48.0))
        pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
    polyline(pts, w, v)


## A capsule of width `w` from a to b.
func line(a: Vector2, b: Vector2, w: float, v := ZenPixelShape.FILL) -> void:
    var h := w / 2.0
    var box := Rect2(a, Vector2.ZERO).expand(b).grow(h)
    _paint(box, func(p): return p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)) <= h, v)


func polyline(pts: Array, w: float, v := ZenPixelShape.FILL) -> void:
    for i in pts.size() - 1: line(pts[i], pts[i + 1], w, v)


## A quadratic bezier stroke through control point `p1`.
func curve(p0: Vector2, p1: Vector2, p2: Vector2, w: float, v := ZenPixelShape.FILL) -> void:
    var pts: Array = []
    for i in 25:
        var t := i / 24.0
        pts.append(p0.lerp(p1, t).lerp(p1.lerp(p2, t), t))
    polyline(pts, w, v)


func rect(r: Rect2, v := ZenPixelShape.FILL) -> void:
    _paint(r, func(p): return p.x >= r.position.x and p.y >= r.position.y \
        and p.x < r.end.x and p.y < r.end.y, v)


## Signed distance from `p` to the rounded box `r` (corner radius `rad`); < 0 inside.
func _rr_dist(p: Vector2, r: Rect2, rad: float) -> float:
    var half := (r.size - Vector2.ONE) / 2.0
    var q := (p - (r.position + half)).abs() - half + Vector2(rad, rad)
    return Vector2(maxf(q.x, 0), maxf(q.y, 0)).length() + minf(maxf(q.x, q.y), 0.0) - rad


func round_rect(r: Rect2, rad: float, v := ZenPixelShape.FILL) -> void:
    _paint(r, func(p): return _rr_dist(p, r, rad) <= 0.0, v)


## The border of a rounded box, `w` cells thick, inside `r`.
func round_frame(r: Rect2, rad: float, w: float, v := ZenPixelShape.FILL) -> void:
    _paint(r, func(p):
        var d := _rr_dist(p, r, rad)
        return d <= 0.0 and d > -w, v)


func poly(pts: Array, v := ZenPixelShape.FILL) -> void:
    var packed := PackedVector2Array(pts)
    var box := Rect2(packed[0], Vector2.ZERO)
    for p in packed: box = box.expand(p)
    _paint(box, func(p): return Geometry2D.is_point_in_polygon(p, packed), v)


## A four-pointed sparkle of radius `r`.
func star4(c: Vector2, r: float, v := ZenPixelShape.FILL) -> void:
    var k := r * 0.22
    poly([c + Vector2(0, -r), c + Vector2(k, -k), c + Vector2(r, 0), c + Vector2(k, k),
          c + Vector2(0, r), c + Vector2(-k, k), c + Vector2(-r, 0), c + Vector2(-k, -k)], v)


## A filled triangle pointing along `dir` from `p` - the head for an arc arrow.
func arrow_head(p: Vector2, dir: Vector2, sz: float, v := ZenPixelShape.FILL) -> void:
    var n := dir.normalized()
    var side := n.orthogonal() * sz * 0.9
    poly([p + n * sz, p + side, p - side], v)


## Copy every inked cell left of the centre column onto the right, mirrored
## about that column (x = 32 on a 64 grid, the centre the icons are drawn on).
func mirror_x() -> void:
    var m := s.size.x / 2
    for y in s.size.y:
        for x in m:
            var c := s.get_cell(x, y)
            if c != ZenPixelShape.EMPTY: s.set_cell(2 * m - x, y, c)
