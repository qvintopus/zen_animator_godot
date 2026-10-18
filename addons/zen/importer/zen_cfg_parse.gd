@tool
class_name ZenCfgParse
extends RefCounted
##
## Parser for the Zen .cfg text format. Grammar: src/anim/anim_io.c:5-78.
##
## ONE-SHOT TOOLING. Native Godot scenes are the source of truth; this exists to
## carry the existing documents across once. It is not a maintained round-trip,
## so it reads and never writes.
##
## Returns plain Dictionaries rather than building nodes, so the whole thing is
## testable headlessly and a parse bug can never be mistaken for a render bug.
##
## Faithful to the reader it replaces in three ways that matter:
##   - UNKNOWN LEADING KEYS ARE SKIPPED, not errors. Every optional field the C
##     added over time is a trailing token, so old files keep loading and files
##     from a newer build do not hard-fail here.
##   - colour keys are RGB-ONLY (`key <t> <r> <g> <b> <ease>`); alpha always
##     lives in its own scalar track.
##   - an EMPTY track (`track rot 0`) is legal and preserved; both menu files
##     contain one.
##

## Scalar props per element kind, by .cfg name (anim_io.c:90-115).
const TEXT_PROPS := ["pos_x", "pos_y", "size", "alpha", "rot", "crumble",
    "crumble_dir", "crumble_spread", "crumble_dist", "crumble_spin",
    "color", "string"]
const SHAPE_PROPS := ["pos_x", "pos_y", "w", "h", "alpha", "rot", "color",
    "outline_color", "outline", "outline_alpha", "scale", "shape_id"]
const GLOBAL_PROPS := ["fade", "color", "bg_alpha", "bg_color"]

## Props whose keys carry r,g,b instead of a scalar (AnimPropIsColor).
const COLOR_PROPS := ["color", "outline_color", "bg_color"]
## Props keying a pool INDEX - never interpolated (AnimPropIsStepped).
const STEPPED_PROPS := ["string", "shape_id"]
## The one group sharing a key line: `key <t> <amount> <dir> <spread> <dist> <spin> <ease>`
const CRUMBLE_MEMBERS := ["crumble", "crumble_dir", "crumble_spread",
    "crumble_dist", "crumble_spin"]

const CRUMBLE_DEFAULTS := {"crumble_spin": 90.0, "crumble_dir": 90.0,
    "crumble_spread": 12.0, "crumble_dist": 0.5}


static func is_color_prop(p: String) -> bool:
    return COLOR_PROPS.has(p)


static func is_stepped_prop(p: String) -> bool:
    return STEPPED_PROPS.has(p)


## `\s` -> space, `\n` -> newline, `\\` -> backslash (DecodeText, anim_io.c:272).
static func decode_text(s: String) -> String:
    var out := ""
    var i := 0
    while i < s.length():
        if s[i] == "\\" and i + 1 < s.length():
            match s[i + 1]:
                "s": out += " "
                "n": out += "\n"
                "\\": out += "\\"
                _: out += s[i + 1]
            i += 2
        else:
            out += s[i]
            i += 1
    return out


static func _col(r: String, g: String, b: String, a := "255") -> Color:
    return Color8(int(r), int(g), int(b), int(a))


## Parse a whole document. Returns {ok, error, doc}.
static func parse_doc(text: String) -> Dictionary:
    var doc := {
        "name": "", "duration": 2.0, "intro_end": 0.0, "outro_start": 0.0,
        "loop_blend": 0.3, "loop_smooth": true,
        "elems": [], "signals": [], "pauses": [], "strings": {},
    }
    var elem: Dictionary = {}
    var sig: Dictionary = {}
    var track_prop := ""        # track currently being filled, "" = none
    var target: Dictionary = {}
    var posparam: Dictionary = {}

    for raw_line in text.split("\n"):
        var line := raw_line.strip_edges()
        if line.is_empty() or line.begins_with("#"): continue
        var tk := line.split(" ", false)
        var key := tk[0]

        match key:
            "doc":
                # doc <name> <duration> [<introEnd> <outroStart> [<blend> <smooth>]]
                if tk.size() >= 3:
                    doc["name"] = tk[1]
                    doc["duration"] = float(tk[2])
                if tk.size() >= 5:
                    doc["intro_end"] = float(tk[3])
                    doc["outro_start"] = float(tk[4])
                if tk.size() >= 7:
                    doc["loop_blend"] = float(tk[5])
                    doc["loop_smooth"] = int(tk[6]) != 0
                if float(doc["outro_start"]) <= 0.0:
                    doc["outro_start"] = doc["duration"]

            "string":
                # Explicit index: a deleted entry leaves a hole and the rest
                # must not shift.
                if tk.size() >= 3:
                    doc["strings"][int(tk[1])] = decode_text(tk[2])

            "elem":
                _close_track(elem, track_prop)
                track_prop = ""
                if tk.size() >= 3:
                    elem = _new_elem(tk[1], tk[2])
                    doc["elems"].append(elem)

            "end":
                _close_track(elem, track_prop)
                track_prop = ""
                elem = {}

            "pause":
                if tk.size() >= 2:
                    doc["pauses"].append({
                        "t": float(tk[1]),
                        "once": tk.size() >= 3 and int(tk[2]) != 0})

            "signal":
                # signal <name> <length> [terminal [usesPos [posAnchor [replay]]]]
                sig = {
                    "name": tk[1] if tk.size() >= 2 else "",
                    "length": float(tk[2]) if tk.size() >= 3 else 0.0,
                    "terminal": tk.size() >= 4 and int(tk[3]) != 0,
                    "uses_pos": tk.size() >= 5 and int(tk[4]) != 0,
                    "pos_anchor": tk.size() >= 6 and int(tk[5]) != 0,
                    "replay": tk.size() >= 7 and int(tk[6]) != 0,
                    "targets": [], "pos_params": [],
                    "seq_mult": 0.0, "uses_seq": false,
                    "seq_targets": [], "seq_keys": [],
                }
                doc["signals"].append(sig)
                target = {}
                posparam = {}

            "endsig":
                sig = {}
                target = {}
                posparam = {}

            "target":
                # target <elemName> <prop> <keyCount>  - u is 0..1 of length
                if sig.is_empty() or tk.size() < 3: continue
                target = {"elem": tk[1], "prop": tk[2], "keys": []}
                sig["targets"].append(target)
                posparam = {}

            "posparam":
                if sig.is_empty() or tk.size() < 3: continue
                posparam = {"elem": tk[1], "slot": int(tk[2]), "keys": []}
                sig["pos_params"].append(posparam)
                target = {}

            "poskey":
                # poskey <u> <offX> <offY> <ease>
                if posparam.is_empty() or tk.size() < 5: continue
                posparam["keys"].append({
                    "t": float(tk[1]),
                    "off": Vector2(float(tk[2]), float(tk[3])),
                    "ease": tk[4]})

            "seq":
                # seq <mult> <usesSeq> <targetCount> <keyCount>
                if sig.is_empty() or tk.size() < 3: continue
                sig["seq_mult"] = float(tk[1])
                sig["uses_seq"] = int(tk[2]) != 0

            "seqtarget":
                if sig.is_empty() or tk.size() < 3: continue
                sig["seq_targets"].append({"elem": tk[1], "prop": tk[2]})

            "seqkey":
                if sig.is_empty() or tk.size() < 4: continue
                sig["seq_keys"].append({
                    "t": float(tk[1]), "v": float(tk[2]), "ease": tk[3]})

            "track":
                # track <prop> <keyCount>. The count is advisory - the keys that
                # follow are what counts, and a count of 0 is a legal EMPTY track.
                _close_track(elem, track_prop)
                if elem.is_empty() or tk.size() < 2:
                    track_prop = ""
                    continue
                track_prop = tk[1]
                elem["tracks"][track_prop] = []

            "key":
                if not sig.is_empty() and not target.is_empty():
                    _read_key(target["keys"], tk, String(target["prop"]))
                elif not elem.is_empty() and track_prop != "":
                    if track_prop == "crumble":
                        _read_crumble_key(elem, tk)
                    else:
                        _read_key(elem["tracks"][track_prop], tk, track_prop)

            _:
                # Element base-pose fields, then anything unknown (skipped).
                if not elem.is_empty():
                    _read_elem_field(elem, key, tk)

    _close_track(elem, track_prop)
    return {"ok": true, "error": "", "doc": doc}


static func _new_elem(kind: String, name: String) -> Dictionary:
    return {
        "kind": kind, "name": name, "text": "",
        "color": Color8(245, 245, 245, 255),
        "bg_color": Color(0, 0, 0, 0),
        "outline_color": Color8(245, 245, 245, 255),
        "outline": 0.0,
        "pos": Vector2(0.5, 0.5), "size": Vector2(0.2, 0.2),
        "scale": 1.0, "rot": 0.0,
        "shape": "rect", "shape_name": "",
        "unit_abs": false, "corner_mode": false, "outline_crisp": false,
        "crumble_fx": CRUMBLE_DEFAULTS.duplicate(),
        "tracks": {},
    }


static func _read_elem_field(e: Dictionary, key: String, tk: PackedStringArray) -> void:
    match key:
        "text":
            if tk.size() >= 2: e["text"] = decode_text(tk[1])
        "color":
            if tk.size() >= 5: e["color"] = _col(tk[1], tk[2], tk[3], tk[4])
        "bg":
            if tk.size() >= 5: e["bg_color"] = _col(tk[1], tk[2], tk[3], tk[4])
        "outline":
            # outline <r> <g> <b> <a> <thickFrac>
            if tk.size() >= 6:
                e["outline_color"] = _col(tk[1], tk[2], tk[3], tk[4])
                e["outline"] = float(tk[5])
        "pos":
            if tk.size() >= 3: e["pos"] = Vector2(float(tk[1]), float(tk[2]))
        "size":
            if tk.size() >= 3: e["size"] = Vector2(float(tk[1]), float(tk[2]))
        "scale":
            if tk.size() >= 2: e["scale"] = float(tk[1])
        "rot":
            if tk.size() >= 2: e["rot"] = float(tk[1])
        "shape":
            if tk.size() >= 2: e["shape"] = tk[1]
        "shape_name":
            if tk.size() >= 2: e["shape_name"] = tk[1]
        "unit":
            e["unit_abs"] = tk.size() >= 2 and tk[1] == "abs"
        "anchor":
            e["corner_mode"] = tk.size() >= 2 and tk[1] == "corners"
        "outline_style":
            e["outline_crisp"] = tk.size() >= 2 and tk[1] == "crisp"
        "crumble_fx":
            # crumble_fx <spin> <dir> <spread> <dist>
            if tk.size() >= 5:
                e["crumble_fx"] = {
                    "crumble_spin": float(tk[1]), "crumble_dir": float(tk[2]),
                    "crumble_spread": float(tk[3]), "crumble_dist": float(tk[4])}
        _:
            pass        # unknown leading key: skip, stay forward compatible


## `key <t> <value> <ease>` or `key <t> <r> <g> <b> <ease>` for colour props.
static func _read_key(dst: Array, tk: PackedStringArray, prop: String) -> void:
    if is_color_prop(prop):
        if tk.size() < 6: return
        dst.append({"t": float(tk[1]), "c": _col(tk[2], tk[3], tk[4]),
                    "ease": tk[5]})
    else:
        if tk.size() < 4: return
        dst.append({"t": float(tk[1]), "v": float(tk[2]), "ease": tk[3]})


## The crumble group shares one line and fans out into five member tracks:
##   key <t> <amount> <dir> <spread> <dist> <spin> <ease>
static func _read_crumble_key(e: Dictionary, tk: PackedStringArray) -> void:
    if tk.size() < 8: return
    var t := float(tk[1])
    var ease := tk[7]
    var vals := {
        "crumble": float(tk[2]), "crumble_dir": float(tk[3]),
        "crumble_spread": float(tk[4]), "crumble_dist": float(tk[5]),
        "crumble_spin": float(tk[6])}
    for m in CRUMBLE_MEMBERS:
        if not e["tracks"].has(m): e["tracks"][m] = []
        (e["tracks"][m] as Array).append({"t": t, "v": vals[m], "ease": ease})


## Keys must be ascending in t for the sampler's segment scan.
static func _close_track(e: Dictionary, prop: String) -> void:
    if e.is_empty() or prop == "": return
    if prop == "crumble":
        for m in CRUMBLE_MEMBERS:
            if e["tracks"].has(m):
                (e["tracks"][m] as Array).sort_custom(
                    func(a, b): return float(a["t"]) < float(b["t"]))
        return
    if e["tracks"].has(prop):
        (e["tracks"][prop] as Array).sort_custom(
            func(a, b): return float(a["t"]) < float(b["t"]))


## Parse _easings.cfg: `ease <name> <n>` + n*(x y ix iy ox oy), and `hide <name>`.
static func parse_easings(text: String) -> Dictionary:
    var out := {"curves": {}, "hidden": []}
    for raw_line in text.split("\n"):
        var line := raw_line.strip_edges()
        if line.is_empty() or line.begins_with("#"): continue
        var tk := line.split(" ", false)
        if tk[0] == "hide" and tk.size() >= 2:
            out["hidden"].append(tk[1])
        elif tk[0] == "ease" and tk.size() >= 3:
            var nums := PackedFloat32Array()
            for i in range(2, tk.size()):
                nums.append(float(tk[i]))
            out["curves"][tk[1]] = ZenCurve.from_tokens(nums)
    return out
