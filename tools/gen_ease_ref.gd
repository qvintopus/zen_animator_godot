extends SceneTree

func _init() -> void:
    var ps := [0.0, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0]
    var f := FileAccess.open("res://tests/ease_ref.txt", FileAccess.WRITE)
    f.store_line("# Easing reference values, GENERATED - do not hand-edit.")
    f.store_line("# Source: Godot 4.7.2 Tween.interpolate_value(0,1,p,1,TRANS_*,EASE_*).")
    f.store_line("# Regenerate: tools/gen_ease_ref.gd  (see zen_easing.gd for why Godot owns these)")
    f.store_line("# Columns: name then p = 0.0 0.1 0.25 0.5 0.75 0.9 1.0")
    var n := 0
    for nm in ZenEasing.GODOT_EASE:
        var row := [nm]
        for p in ps:
            row.append("%.6f" % ZenEasing.apply(nm, p))
        f.store_line(" ".join(row))
        n += 1
    f.close()
    print("wrote %d rows" % n)
    quit()
