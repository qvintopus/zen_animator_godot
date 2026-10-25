extends SceneTree
##
## Seeds library/ with the project's reusable clips: the four effect showcases
## whole, plus two extracted from finished animations by key time range - the
## book swinging in until it rests (ma_prog_02_coding) and the symbols swirling
## round the white ball (fangs_test). Re-run after changing a source scene.
##
##   Godot --headless --path . --script res://tools/gen_library.gd
##
## Each entry copies exactly what Ctrl+C would: whole elements (no `from`/`to`),
## or the keys of `elems` inside [from, to] seconds.
##

const CLIPS := [
    {"name": "swing_in", "scene": "ma_prog_02_coding", "elems": ["sh_book"],
     "from": 0.0, "to": 2.01, "rename": {"sh_book": "book"}},
    {"name": "orbit_symbols", "scene": "fangs_test", "elems": ["txt_scribble", "ball"],
     "from": 4.9, "to": 9.3},
    {"name": "ring_pulse", "scene": "fx_ring_pulse", "skip": ["hint"]},
    {"name": "sparkle_burst", "scene": "fx_sparkle_burst", "skip": ["hint"]},
    {"name": "shake", "scene": "fx_shake", "skip": ["hint"]},
    {"name": "wobble", "scene": "fx_wobble", "skip": ["hint"]},
]


func _init() -> void:
    for spec in CLIPS:
        var path := _make(spec)
        print("%s  %s" % ["wrote" if not path.is_empty() else "FAILED", spec["name"]])
    quit()


func _make(spec: Dictionary) -> String:
    var src := ZenSceneOps.open(ZenSceneOps.path_of(String(spec["scene"])))
    if src == null: return ""
    var elems: Array = []
    for r in ZenElemOps.rows(src):
        var el := r as ZenElement
        if spec.has("elems") and not (spec["elems"] as Array).has(el.elem_name): continue
        if (spec.get("skip", []) as Array).has(el.elem_name): continue
        elems.append(el)
    var ids := {}
    if spec.has("from"):
        for el in elems:
            for h in ZenElemOps.halves(src, el as ZenElement):
                for prop in ZenKeyOps.keyed_props(src, h as ZenElement):
                    var ks := ZenKeyOps.keys(src, h as ZenElement, prop)
                    for i in ks.size():
                        var t := float(ks[i]["t"])
                        if t >= float(spec["from"]) - 1e-4 and t <= float(spec["to"]):
                            ids["%s|%s|%d" % [(h as Node).name, prop, i]] = true
    var clip := ZenClipOps.copy(src, elems, ids)
    var path := ""
    if clip != null:
        var rn: Dictionary = spec.get("rename", {})
        for old in rn:
            var e := ZenElemOps.find(clip, String(old))
            if e != null: ZenElemOps.rename(clip, e, String(rn[old]))
        path = ZenSceneOps.save_clip(clip, String(spec["name"]))
        clip.free()
    src.free()
    return path
