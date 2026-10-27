extends SceneTree
##
## Builds the ZombieShooter set (anims/ZombieShooter/zs_*.tscn): HUD moments for
## variant-ZombieShooter - wave start / cleared, boss wave, room cleared, game
## over, victory and weapon pickup cards (katana, pistol, shotgun, rifle). Re-run
## after changing a design here; the scenes are plain Zen scenes and stay
## editable in the scene editor.
##
##   Godot --headless --path . --script res://tools/gen_zombie_shooter.gd
##
## Every scene is a one-shot on a transparent 480x270 canvas (the game's
## viewport), so it overlays the HUD 1:1 and emits `finished` when it has faded
## out. Live game values come in as TEXT ARGS: the pool entries hold %1, %2...
## and the game calls play_with([...]); the saved text_args are the samples the
## gallery shows, text_arg_names say what each slot is.
##
## Text sizes are multiples of 10 px so the bitmap font stays crisp.
##

const SIZE := Vector2(480, 270)
## The gallery folder the set lives in (anims/ZombieShooter/).
const FOLDER := "ZombieShooter"
const CLEAR := Color(0, 0, 0, 0)
const BONE := Color(0.93, 0.89, 0.76, 1)
const BLOOD := Color(0.78, 0.1, 0.1, 1)
const TOXIC := Color(0.55, 0.95, 0.3, 1)
const DARK := Color(0.078, 0.122, 0.09, 1)       # victory.tscn's background
const GOLD := Color(1.0, 0.8, 0.3, 1)
## How far left of the weapon card's centre the icon sits, in px.
const ICON_DX := 110.0


func _init() -> void:
    for fn in [_wave_start, _wave_cleared, _boss_wave, _room_cleared, _game_over, _victory,
               _weapon_katana, _weapon_pistol, _weapon_shotgun, _weapon_rifle]:
        var doc: Dictionary = fn.call()
        var path := _save(doc)
        print("%s  %s" % ["wrote" if not path.is_empty() else "FAILED", doc["name"]])
    quit()


# ---------------------------------------------------------------------------
#  Scenes
# ---------------------------------------------------------------------------

## "WAVE 3" slams in between two skulls, shakes, and crumbles away.
func _wave_start() -> Dictionary:
    var band := shape("band", "rect", Vector2(0.5, 0.42), Vector2(1.0, 0.24), {"color": DARK},
        {"alpha": [k(0.0, 0.0), k(0.15, 0.75, "quadOut"), k(2.0, 0.75), k(2.4, 0.0, "quadIn")],
         "h": [k(0.0, 0.0), k(0.2, 0.24, "cubicOut"), k(2.05, 0.24), k(2.4, 0.0, "backIn")]})
    var title := text("title", "WAVE %1", Vector2(0.5, 0.40), 40.0, BONE,
        {"alpha": [k(0.0, 0.0), k(0.1, 1.0)],
         "size": [k(0.0, 80.0), k(0.25, 40.0, "backOut")],
         "pos_x": [k(0.25, 0.5), k(0.3, 0.512), k(0.35, 0.49), k(0.4, 0.506), k(0.45, 0.497),
                   k(0.5, 0.5)],
         "crumble": [k(1.95, 0.0), k(2.4, 1.0, "quadIn")]})
    var sub := text("sub", "%2 ZOMBIES INCOMING", Vector2(0.5, 0.53), 10.0, TOXIC,
        {"alpha": [k(0.4, 0.0), k(0.6, 1.0, "sineOut"), k(2.0, 1.0), k(2.25, 0.0)],
         "pos_y": [k(0.4, 0.58), k(0.65, 0.53, "cubicOut")]})
    var elems := [band, title, sub]
    for side in [-1, 1]:
        var nm := "skull_l" if side < 0 else "skull_r"
        elems.append(shape(nm, "custom", Vector2(0.5 + side * 0.3, 0.41), Vector2(32, 32),
            {"shape_name": "skull", "color": BONE, "outline_color": BLOOD},
            {"scale": [k(0.3, 0.0), k(0.55, 1.0, "backOut"), k(2.0, 1.0), k(2.3, 0.0, "backIn")],
             "rot": [k(0.55, 0.0), k(0.9, side * 12.0, "sineOut"), k(1.3, side * -6.0, "sineInOut"),
                     k(1.7, 0.0, "sineInOut")]}))
    return scene("zs_wave_start", 2.4, elems, ["wave", "enemies"], ["3", "24"])


## A blood splat with a check on it; "WAVE 3 CLEARED" and how many are left.
func _wave_cleared() -> Dictionary:
    var splat := shape("splat", "custom", Vector2(0.5, 0.4), Vector2(64, 64),
        {"shape_name": "splat", "color": BLOOD, "outline_color": Color(0.35, 0.03, 0.03)},
        {"scale": [k(0.0, 0.0), k(0.2, 1.2, "backOut"), k(0.35, 1.0, "sineInOut")],
         "alpha": [k(1.6, 0.9), k(2.0, 0.0, "quadIn")],
         "rot": [k(0.0, -20.0), k(0.35, 0.0, "cubicOut")]})
    splat["color"] = Color(BLOOD, 0.9)
    var check := shape("check", "custom", Vector2(0.5, 0.4), Vector2(32, 32),
        {"shape_name": "check_mark", "color": BONE, "outline_color": DARK},
        {"scale": [k(0.25, 0.0), k(0.45, 1.0, "backOut"), k(1.6, 1.0), k(1.9, 0.0, "backIn")]})
    var title := text("title", "WAVE %1 CLEARED", Vector2(0.5, 0.62), 20.0, BONE,
        {"alpha": [k(0.3, 0.0), k(0.45, 1.0), k(1.6, 1.0), k(1.9, 0.0, "quadIn")],
         "size": [k(0.3, 30.0), k(0.5, 20.0, "backOut")],
         "pos_y": [k(1.6, 0.62), k(1.9, 0.58, "quadIn")]})
    var sub := text("sub", "%2 WAVES LEFT", Vector2(0.5, 0.71), 10.0, TOXIC,
        {"alpha": [k(0.5, 0.0), k(0.7, 1.0, "sineOut"), k(1.65, 1.0), k(1.9, 0.0)]})
    return scene("zs_wave_cleared", 2.0, [splat, check, title, sub], ["wave", "waves_left"], ["3", "2"])


## A red alarm flash, hazard rows sliding in from both sides, BOSS WAVE and the
## boss's name dropping in.
func _boss_wave() -> Dictionary:
    var elems := []
    elems.append(shape("flash", "rect", Vector2(0.5, 0.5), Vector2(1.0, 1.0), {"color": BLOOD},
        {"alpha": [k(0.0, 0.0), k(0.1, 0.35, "quadOut"), k(0.4, 0.0, "quadIn"), k(0.7, 0.25, "quadOut"),
                   k(1.0, 0.0, "quadIn")]}))
    elems.append(shape("band", "rect", Vector2(0.5, 0.5), Vector2(1.0, 0.34), {"color": DARK},
        {"alpha": [k(0.0, 0.0), k(0.3, 0.85), k(2.6, 0.85), k(3.0, 0.0, "quadIn")]}))
    # Two rows of 32 px hazard tiles; the top one slides in from the left, the
    # bottom one from the right, and they leave the way they came.
    var tile := 32.0 / SIZE.x
    for row in 2:
        var y := 0.5 + (-1 if row == 0 else 1) * (0.17 + 16.0 / SIZE.y)
        var from := -1.0 if row == 0 else 1.0
        for i in int(SIZE.x / 32.0):
            var x := (i + 0.5) * tile
            elems.append(shape("stripe_%d_%d" % [row, i], "custom", Vector2(x, y), Vector2(32, 32),
                {"shape_name": "hazard_stripes", "color": GOLD, "outline_color": DARK},
                {"pos_x": [k(0.1, x + from), k(0.55, x, "cubicOut"), k(2.55, x), k(3.0, x - from, "cubicIn")]}))
    elems.append(text("title", "BOSS WAVE", Vector2(0.5, 0.45), 30.0, BLOOD,
        {"alpha": [k(0.4, 0.0), k(0.5, 1.0), k(2.6, 1.0), k(2.9, 0.0)],
         "size": [k(0.4, 60.0), k(0.65, 30.0, "backOut")],
         "color": [kc(0.65, BLOOD), kc(0.75, BONE), kc(0.85, BLOOD), kc(1.0, BONE), kc(1.15, BLOOD)]}))
    elems.append(text("boss", "%1", Vector2(0.5, 0.57), 20.0, BONE,
        {"alpha": [k(0.9, 0.0), k(1.0, 1.0), k(2.6, 1.0), k(2.9, 0.0)],
         "pos_y": [k(0.9, 0.5), k(1.4, 0.57, "bounceOut")]}))
    return scene("zs_boss_wave", 3.0, elems, ["boss_name"], ["BIG JELLY"])


## A toxic banner wipes across: ROOM CLEARED, the wave tally and the rooms
## left. Holds at a pause marker (a click, or resume() from the game) and wipes
## away.
func _room_cleared() -> Dictionary:
    var band := shape("band", "rect", Vector2(0.5, 0.45), Vector2(1.0, 0.2), {"color": TOXIC},
        {"w": [k(0.0, 0.0), k(0.35, 1.0, "cubicOut")],
         "h": [k(1.5, 0.2), k(1.9, 0.0, "backIn")],
         "alpha": [k(0.0, 0.9)]})
    var door := shape("door", "custom", Vector2(0.15, 0.45), Vector2(32, 32),
        {"shape_name": "door", "color": DARK, "outline_color": DARK},
        {"scale": [k(0.3, 0.0), k(0.5, 1.0, "backOut"), k(1.5, 1.0), k(1.7, 0.0, "backIn")]})
    var title := text("title", "ROOM CLEARED", Vector2(0.53, 0.45), 30.0, DARK,
        {"alpha": [k(0.25, 0.0), k(0.4, 1.0), k(1.5, 1.0), k(1.7, 0.0)],
         "pos_x": [k(0.25, 0.6), k(0.5, 0.53, "cubicOut")]})
    var sub := text("sub", "WAVE %1 COMPLETED WITH %2 ROOMS LEFT", Vector2(0.5, 0.62), 10.0, BONE,
        {"alpha": [k(0.6, 0.0), k(0.8, 1.0, "sineOut"), k(1.5, 1.0), k(1.75, 0.0)],
         "pos_y": [k(0.6, 0.66), k(0.85, 0.62, "cubicOut")]})
    var doc := scene("zs_room_cleared", 2.0, [band, door, title, sub], ["wave", "rooms_left"], ["5", "3"])
    doc["pauses"] = [{"t": 1.2, "once": false}]
    return doc


## The screen darkens, a splat lands and drips, YOU DIED gathers from dust,
## then the run's wave and score. Holds at a pause marker for the menu.
func _game_over() -> Dictionary:
    var elems := []
    elems.append(shape("veil", "rect", Vector2(0.5, 0.5), Vector2(1.0, 1.0), {"color": DARK},
        {"alpha": [k(0.0, 0.0), k(0.6, 0.85, "sineOut"), k(2.4, 0.85), k(3.0, 0.0, "quadIn")]}))
    var splat_y := 0.34
    elems.append(shape("splat", "custom", Vector2(0.5, splat_y), Vector2(96, 96),
        {"shape_name": "splat", "color": BLOOD, "outline_color": Color(0.35, 0.03, 0.03)},
        {"scale": [k(0.2, 0.0), k(0.45, 1.0, "backOut")],
         "alpha": [k(2.4, 1.0), k(2.9, 0.0)]}))
    # Drips run down from under the splat: the rect grows and its centre
    # follows, so the top edge stays put.
    var drips := [[-22.0, 18.0, 0.5], [6.0, 30.0, 0.6], [26.0, 12.0, 0.75]]
    for di in drips.size():
        var d: Array = drips[di]
        var x := 0.5 + float(d[0]) / SIZE.x
        var top := splat_y + 30.0 / SIZE.y
        var len_px := float(d[1])
        var t0 := float(d[2])
        elems.append(shape("drip_%d" % di, "rect", Vector2(x, top), Vector2(5, 0.01),
            {"color": BLOOD},
            {"h": [k(t0, 0.0), k(t0 + 1.0, len_px, "sineIn")],
             "pos_y": [k(t0, top), k(t0 + 1.0, top + len_px / 2.0 / SIZE.y, "sineIn")],
             "alpha": [k(2.4, 1.0), k(2.9, 0.0)]}))
    elems.append(shape("skull", "custom", Vector2(0.5, splat_y), Vector2(48, 48),
        {"shape_name": "skull", "color": BONE, "outline_color": DARK},
        {"alpha": [k(0.55, 0.0), k(0.75, 1.0), k(2.4, 1.0), k(2.8, 0.0)],
         "scale": [k(0.55, 1.4), k(0.8, 1.0, "cubicOut")]}))
    elems.append(text("title", "YOU DIED", Vector2(0.5, 0.66), 40.0, BLOOD,
        {"crumble": [k(0.7, 1.0), k(1.5, 0.0, "cubicOut"), k(2.4, 0.0), k(3.0, 1.0, "quadIn")]}))
    elems.append(text("sub", "WAVE %1   SCORE %2", Vector2(0.5, 0.78), 10.0, BONE,
        {"alpha": [k(1.5, 0.0), k(1.8, 1.0, "sineOut"), k(2.4, 1.0), k(2.7, 0.0)]}))
    var doc := scene("zs_game_over", 3.0, elems, ["wave", "score"], ["7", "1250"])
    doc["pauses"] = [{"t": 2.1, "once": false}]
    return doc


## A gold crosshair spins down onto the screen among sparkles: YOU SURVIVED,
## rooms and score. Holds at a pause marker.
func _victory() -> Dictionary:
    var elems := []
    elems.append(shape("veil", "rect", Vector2(0.5, 0.5), Vector2(1.0, 1.0), {"color": DARK},
        {"alpha": [k(0.0, 0.0), k(0.5, 0.8, "sineOut"), k(2.6, 0.8), k(3.2, 0.0, "quadIn")]}))
    elems.append(shape("crosshair", "custom", Vector2(0.5, 0.36), Vector2(64, 64),
        {"shape_name": "crosshair", "color": GOLD, "outline_color": DARK},
        {"alpha": [k(0.0, 0.0), k(0.3, 1.0), k(2.6, 1.0), k(3.0, 0.0)],
         "scale": [k(0.0, 3.0), k(0.9, 1.0, "cubicOut"), k(2.6, 1.0), k(3.0, 0.4, "backIn")],
         "rot": [k(0.0, -180.0), k(0.9, 0.0, "cubicOut"), k(3.2, 45.0, "sineIn")]}))
    var spots := [Vector2(0.3, 0.24), Vector2(0.7, 0.22), Vector2(0.24, 0.5), Vector2(0.76, 0.48),
                  Vector2(0.38, 0.12), Vector2(0.63, 0.56)]
    for i in spots.size():
        var t0 := 0.8 + i * 0.12
        elems.append(shape("spark_%d" % i, "custom", spots[i], Vector2(16, 16),
            {"shape_name": "star", "color": GOLD if i % 2 == 0 else BONE, "outline_color": DARK},
            {"scale": [k(t0, 0.0), k(t0 + 0.25, 1.2, "backOut"), k(t0 + 0.6, 0.8, "sineInOut"),
                       k(t0 + 1.0, 1.1, "sineInOut"), k(2.6, 1.0), k(2.9, 0.0, "backIn")],
             "rot": [k(t0, 0.0), k(2.9, 90.0)]}))
    elems.append(text("title", "YOU SURVIVED", Vector2(0.5, 0.64), 30.0, GOLD,
        {"alpha": [k(0.8, 0.0), k(0.9, 1.0), k(2.6, 1.0), k(2.9, 0.0)],
         "size": [k(0.8, 60.0), k(1.1, 30.0, "backOut")]}))
    elems.append(text("sub", "%1 ROOMS CLEARED   SCORE %2", Vector2(0.5, 0.74), 10.0, BONE,
        {"alpha": [k(1.2, 0.0), k(1.45, 1.0, "sineOut"), k(2.6, 1.0), k(2.85, 0.0)]}))
    var doc := scene("zs_victory", 3.2, elems, ["rooms", "score"], ["6", "4820"])
    doc["pauses"] = [{"t": 2.3, "once": false}]
    return doc


## A lower-third card slides in over the weapon bar: icon, weapon name and a
## one-line description, then slides out the other way. One scene per weapon
## (the icon and how it moves differ); the samples are placeholder copy, the
## game passes the real name and description.
func _weapon_card(nm: String, icon_shape: String, icon_px: float, samples: Array,
        icon_tracks: Dictionary, extra: Array = []) -> Dictionary:
    var cy := 0.8
    var card := shape("card", "rect", Vector2(0.5, cy), Vector2(280, 44),
        {"color": Color(DARK, 0.9), "outline_color": TOXIC, "outline": 1.0},
        {"pos_x": _card_slide(0.5)})
    var icon_x := 0.5 - ICON_DX / SIZE.x
    var tracks := {"pos_x": _card_slide(icon_x)}
    tracks.merge(icon_tracks)
    var icon := shape("icon", "custom", Vector2(icon_x, cy), Vector2(icon_px, icon_px),
        {"shape_name": icon_shape, "color": BONE, "outline_color": BLOOD}, tracks)
    var text_x := 0.5 + 26.0 / SIZE.x
    var title := text("weapon", "%1", Vector2(text_x, cy - 8.0 / SIZE.y), 20.0, TOXIC,
        {"pos_x": _card_slide(text_x)})
    var desc := text("desc", "%2", Vector2(text_x, cy + 11.0 / SIZE.y), 10.0, BONE,
        {"pos_x": _card_slide(text_x),
         "alpha": [k(0.35, 0.0), k(0.55, 1.0)]})
    return scene(nm, 2.6, [card, icon] + extra + [title, desc], ["weapon_name", "description"],
        samples)


## pos_x keys for a card part at `x`: in from the right, hold, out to the left.
func _card_slide(x: float) -> Array:
    return [k(0.0, x + 0.8), k(0.35, x, "backOut"), k(2.2, x), k(2.6, x - 0.8, "backIn")]


## A muzzle flash `off` px from the icon's centre, popping at each shot time.
func _muzzle(off: Vector2, shots: Array) -> Dictionary:
    var x := 0.5 - ICON_DX / SIZE.x + off.x / SIZE.x
    var sc: Array = [k(0.0, 0.0)]
    for t: float in shots:
        sc += [k(t, 0.0), k(t + 0.03, 1.0, "quadOut"), k(t + 0.1, 0.0, "quadIn")]
    return shape("flash", "custom", Vector2(x, 0.8 + off.y / SIZE.y), Vector2(14, 14),
        {"shape_name": "star", "color": GOLD, "outline_color": BLOOD},
        {"pos_x": _card_slide(x), "scale": sc})


## The icon's rot kicking up at each shot and settling.
func _recoil(shots: Array, kick: float) -> Array:
    var rot: Array = [k(0.35, -25.0), k(0.5, 0.0, "backOut")]
    for t: float in shots:
        rot += [k(t, 0.0), k(t + 0.04, -kick, "quadOut"), k(t + 0.12, 0.0, "sineInOut")]
    return rot


## The game's Sword as a katana: it swings in, and a slash streak cuts across
## the card behind the text.
func _weapon_katana() -> Dictionary:
    var slash := shape("slash", "rect", Vector2(0.5, 0.8), Vector2(0.0, 0.008),
        {"color": BONE, "rot": -8.0},
        {"w": [k(0.45, 0.0), k(0.6, 0.5, "cubicOut")],
         "pos_x": [k(0.45, 0.3), k(0.6, 0.5, "cubicOut")],
         "alpha": [k(0.6, 1.0), k(0.95, 0.0, "quadIn")]})
    return _weapon_card("zs_weapon_katana", "katana", 36.0,
        ["KATANA", "FAST SLASHES, CLOSE RANGE"],
        {"rot": [k(0.25, -110.0), k(0.55, 10.0, "cubicOut"), k(0.8, 0.0, "sineInOut")]},
        [slash])


## The game's Gun: one shot, a flash at the muzzle and the kick.
func _weapon_pistol() -> Dictionary:
    var shots := [0.7]
    return _weapon_card("zs_weapon_pistol", "pistol", 32.0,
        ["PISTOL", "RELIABLE, QUICK TO AIM"],
        {"rot": _recoil(shots, 22.0)}, [_muzzle(Vector2(13, -5), shots)])


func _weapon_shotgun() -> Dictionary:
    return _weapon_card("zs_weapon_shotgun", "shotgun", 32.0,
        ["SHOTGUN", "WIDE SPREAD, LOW DAMAGE"],
        {"rot": [k(0.35, -25.0), k(0.7, 0.0, "elasticOut")]})


## The game's Assault Riffle: a three-round burst.
func _weapon_rifle() -> Dictionary:
    var shots := [0.65, 0.77, 0.89]
    return _weapon_card("zs_weapon_rifle", "rifle", 40.0,
        ["ASSAULT RIFLE", "FULL AUTO, HIGH FIRE RATE"],
        {"rot": _recoil(shots, 8.0)}, [_muzzle(Vector2(21, -4), shots)])


# ---------------------------------------------------------------------------
#  Building blocks
# ---------------------------------------------------------------------------

## A one-shot document with its text packet: `arg_names` say what %1, %2...
## mean, `samples` are what the gallery shows until the game passes values.
func scene(nm: String, dur: float, elems: Array, arg_names: Array, samples: Array) -> Dictionary:
    return {"name": nm, "duration": dur, "intro_end": 0.0, "outro_start": dur,
            "loop_blend": 0.0, "loop_smooth": false, "elems": elems,
            "signals": [], "pauses": [],
            "arg_names": PackedStringArray(arg_names), "samples": PackedStringArray(samples)}


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


func k(t: float, v: float, ease := "linear") -> Dictionary:
    return {"t": t, "v": v, "ease": ease}


func kc(t: float, c: Color, ease := "linear") -> Dictionary:
    return {"t": t, "c": Color(c, 1.0), "ease": ease}


func _save(doc: Dictionary) -> String:
    var canvas := ZenElemFactory.build(doc)
    canvas.design_size = SIZE
    canvas.clear_color = CLEAR
    canvas.text_arg_names = doc["arg_names"]
    canvas.text_args = doc["samples"]
    canvas.sync_from_animation()
    var path := ZenSceneOps.save(canvas, String(doc["name"]), FOLDER)
    canvas.free()
    return path
