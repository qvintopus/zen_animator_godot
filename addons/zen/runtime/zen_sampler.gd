@tool
class_name ZenSampler
extends RefCounted
##
## Keyframe evaluation - the port of AnimTrackEval (src/anim/anim.c:397-459).
##
## WHY THIS EXISTS instead of using Godot's own track interpolation:
## measured on Godot 4.7.2, a value track's `transition` is both OUTGOING (wrong
## end - Zen's eases the segment ENDING at a key) and pow(p,n)-only, so it
## cannot express bounceOut/elasticOut/backIn or any custom bezier. Bezier
## tracks can overshoot but need ~33 keys to get bounceOut within 3%, and dense
## linear baking needs ~256 keys per segment for 0.3% - both destroy the
## hand-editable sparse timeline that is the whole reason for moving to Godot.
##
## So: Godot's AnimationPlayer owns TIMING and KEY STORAGE (sparse, draggable,
## 1:1 with what the author made); this sampler owns INTERPOLATION, using Zen's
## exact easing functions. Fidelity is exact by construction at any key count.
##
## A key is a Dictionary {t: float, v: float, ease: String}; colour keys carry
## `c: Color` instead of `v`. Keys must be ascending in t.
##

## Find the segment straddling `t`. Returns [i0, i1]; i0 == i1 means clamped.
static func _segment(keys: Array, t: float) -> Vector2i:
    var n := keys.size()
    if n == 0: return Vector2i(-1, -1)
    if t <= float(keys[0]["t"]): return Vector2i(0, 0)
    if t >= float(keys[n - 1]["t"]): return Vector2i(n - 1, n - 1)
    # Scan forward for the first key at or past t, exactly as AnimTrackSegment
    # does. The order matters: duplicate keys at the same time resolve to the
    # LAST one via the clamp above, which is what makes a zero-span segment an
    # instant step rather than a stall on the left value.
    for i in range(1, n):
        if t <= float(keys[i]["t"]): return Vector2i(i - 1, i)
    return Vector2i(n - 1, n - 1)


## Eased 0..1 position within the segment. The RIGHT key's ease shapes it -
## Zen easing is INCOMING (anim.h:370). A zero-span segment steps instantly.
static func _fraction(a: Dictionary, b: Dictionary, t: float) -> float:
    var span := float(b["t"]) - float(a["t"])
    var p := 1.0 if span <= 0.0 else (t - float(a["t"])) / span
    return ZenEasing.apply(String(b.get("ease", "linear")), p)


## Scalar track evaluation.
## `stepped` is for AP_T_STRING / AP_S_SHAPE, which key a pool index and must
## never interpolate. `missing` is returned for an empty track - the caller
## passes the element's base-pose field (TrackOrBase, anim.c:609).
static func eval(keys: Array, t: float, stepped := false, missing := 0.0) -> float:
    var seg := _segment(keys, t)
    if seg.x < 0: return missing
    var a: Dictionary = keys[seg.x]
    if seg.x == seg.y: return float(a["v"])
    var b: Dictionary = keys[seg.y]
    if stepped:
        return float(b["v"]) if t >= float(b["t"]) else float(a["v"])
    var p := _fraction(a, b, t)
    var av := float(a["v"])
    return av + (float(b["v"]) - av) * p


## Colour track evaluation. Zen colour tracks are RGB-ONLY: alpha always comes
## from the separate alpha track, never from a colour key (anim.c:457). Channels
## are clamped because back/elastic overshoot would otherwise wrap.
static func eval_color(keys: Array, t: float, missing_a := 1.0,
                       missing: Color = Color.WHITE) -> Color:
    var seg := _segment(keys, t)
    if seg.x < 0:
        return Color(missing.r, missing.g, missing.b, missing_a)
    var a: Dictionary = keys[seg.x]
    var ac: Color = a["c"]
    if seg.x == seg.y:
        return Color(ac.r, ac.g, ac.b, missing_a)
    var b: Dictionary = keys[seg.y]
    var bc: Color = b["c"]
    var p := _fraction(a, b, t)
    return Color(
        clampf(ac.r + (bc.r - ac.r) * p, 0.0, 1.0),
        clampf(ac.g + (bc.g - ac.g) * p, 0.0, 1.0),
        clampf(ac.b + (bc.b - ac.b) * p, 0.0, 1.0),
        missing_a)
