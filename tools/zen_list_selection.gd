class_name ZenListSelection
extends RefCounted
##
## A list's selection: one cursor row plus a set of marked rows, with the
## usual desktop rules - a plain pick selects just that row, Shift extends a
## range from the anchor, Ctrl toggles one row in or out.
##
## Rows below `first` are never marked (the assets list's "+ new asset" row):
## the cursor can sit on them, but they are commands, not things to delete.
##

var cursor := 0
var anchor := 0
var size := 0
var first := 0
## row -> true
var marks := {}


func _init(first_markable := 0) -> void:
    first = first_markable


## The list was rebuilt with `n` rows: drop marks that no longer exist.
func resize(n: int) -> void:
    size = n
    for r in marks.keys():
        if r >= n: marks.erase(r)
    cursor = clampi(cursor, 0, maxi(n - 1, 0))
    anchor = clampi(anchor, 0, maxi(n - 1, 0))


func pick(i: int, shift := false, ctrl := false) -> void:
    if size <= 0: return
    i = clampi(i, 0, size - 1)
    # A range reaching past the command rows stops at the first real row.
    if shift and size > first: i = maxi(i, first)
    if shift and i >= first:
        var a := maxi(anchor, first)
        marks.clear()
        for r in range(mini(a, i), maxi(a, i) + 1): marks[r] = true
    elif ctrl and i >= first:
        if marks.has(i): marks.erase(i)
        else: marks[i] = true
        anchor = i
    else:
        marks.clear()
        if i >= first: marks[i] = true
        anchor = i
    cursor = i


func move(d: int, shift := false) -> void:
    pick(cursor + d, shift)


## Back to a single selection on the cursor row.
func collapse() -> void:
    pick(cursor)


## The marked rows, ascending.
func rows() -> Array[int]:
    var out: Array[int] = []
    for r in marks: out.append(int(r))
    out.sort()
    return out


func is_multi() -> bool:
    return marks.size() > 1


## Whether row `i` shows as selected. With nothing marked the cursor row
## still does, so the "+ new asset" row reads as selected.
func shows(i: int) -> bool:
    return marks.has(i) or (marks.is_empty() and i == cursor)
