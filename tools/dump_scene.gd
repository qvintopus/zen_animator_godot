extends SceneTree
##
## Headless sanity check: pose an imported scene across its play range and
## report what each element resolves to. Catches "imported but renders nothing"
## without needing a display.
##
##   Godot --headless --path . --script res://tools/dump_scene.gd -- <name>
##

func _init() -> void:
    var args := OS.get_cmdline_user_args()
    var name := String(args[0]) if args.size() > 0 else "mouse_ripple"
    var path := "res://anims/%s.tscn" % name
    if not ResourceLoader.exists(path):
        print("no such scene: ", path)
        quit(1)
        return
    var c: ZenCanvas = (load(path) as PackedScene).instantiate()
    c.live_playback = false   # tests pose by hand; no live clock
    print("%s  dur=%.3f intro_end=%.3f outro_start=%.3f smooth=%s blend=%.2f"
          % [name, c.duration, c.intro_end, c.outro_start, c.loop_smooth, c.loop_blend])
    var els := c.elements()
    print("%d element(s), play range [%.3f, %.3f)" % [els.size(), c.play_start(), c.play_end()])
    for e in els:
        var tx := e as ZenText
        if tx != null:
            print("  %-20s TEXT     abs=%-5s tracks=%s" % [
                tx.elem_name, tx.unit_abs, ", ".join(_tracks_of(c, tx))])
            print("    text=%s" % JSON.stringify(tx.text))
            for frac in [0.0, 0.25, 0.5, 0.75, 1.0]:
                var tt: float = c.play_start() + (c.play_end() - c.play_start()) * frac
                var sz := tx._size_px(tt)
                var box := ZenTextMetrics.measure(tx.text, sz, tx.effective_font())
                var ctr := tx.center_px(tt)
                print("    t=%6.3f  centre=(%7.1f,%7.1f)  box=(%6.1f,%5.1f)px  size=%5.1fpx  alpha=%.3f crumble=%.3f"
                    % [tt, ctr.x, ctr.y, box.x, box.y, sz,
                       tx.prop("alpha", tt, tx.color_base.a),
                       tx.prop("crumble", tt, 0.0)])
            continue
        var gl := e as ZenGlobal
        if gl != null:
            print("  %-20s GLOBAL   bg=%-5s tracks=%s" % [
                gl.elem_name, gl.is_background, ", ".join(_tracks_of(c, gl))])
            continue
        var s := e as ZenShape
        if s == null: continue
        print("  %-20s kind=%-8s abs=%-5s tracks=%s" % [
            s.elem_name, ZenShape.KIND_NAMES[s.shape_kind], s.unit_abs,
            ", ".join(_tracks_of(c, s))])
        for frac in [0.0, 0.25, 0.5, 0.75, 1.0]:
            var t: float = c.play_start() + (c.play_end() - c.play_start()) * frac
            var sc := s.prop("scale", t, s.scale_base)
            var uw := 1.0 if s.unit_abs else c.design_size.x
            var uh := 1.0 if s.unit_abs else c.design_size.y
            print("    t=%6.3f  centre=(%7.1f,%7.1f)  size=(%7.1f,%7.1f)px  fillA=%.3f outA=%.3f out=%.2fpx"
                % [t, c.design_size.x * s.prop("pos_x", t, s.pos_frac.x),
                   c.design_size.y * s.prop("pos_y", t, s.pos_frac.y),
                   uw * s.prop("w", t, s.size_frac.x) * sc,
                   uh * s.prop("h", t, s.size_frac.y) * sc,
                   s.prop("alpha", t, s.color_base.a),
                   s.prop("outline_alpha", t, s.outline_color_base.a),
                   uh * s.prop("outline", t, s.outline_base) * sc])
    quit(0)


## The element's animated props, read from the scene's AnimationPlayer.
func _tracks_of(c: ZenCanvas, el: ZenElement) -> PackedStringArray:
    var out := PackedStringArray()
    for p in c.timeline().paths():
        var parts := String(p).split(":")
        if parts[0] == String(el.name) and not out.has(parts[1]): out.append(parts[1])
    return out
