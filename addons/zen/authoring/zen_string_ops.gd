@tool
class_name ZenStringOps
extends RefCounted
##
## String pool editing on a live canvas (ZenStrings, held by ZenCanvas.strings
## and referenced by every ZenText). Port of the AnimDoc pool ops
## (anim.c:873-970) plus the editor's "clean up holes", which the C never had.
##
## A REFERENCE is a text element's `string_base` or a key on a `:string` track
## in any of the canvas's Animations (the document and every signal). Usage
## counts both, so an entry a signal switches to is never treated as free.
##
## A HOLE is an empty entry nothing references. Indices are stable: remove()
## leaves a hole, and only compact() renumbers - rewriting every reference
## in the same step, so nothing ever points at the wrong words.
##

const TRACK_SUFFIX := ":string"


static func pool(canvas: ZenCanvas) -> ZenStrings:
    return canvas.adopt_strings()


static func texts(canvas: ZenCanvas) -> Array:
    return canvas.elements().filter(func(e): return e is ZenText)


## Every `:string` value track in every Animation, as [anim, track].
static func _string_tracks(canvas: ZenCanvas) -> Array:
    var out: Array = []
    for anim in ZenElemOps._animations(canvas):
        var a := anim as Animation
        for i in a.get_track_count():
            if String(a.track_get_path(i)).ends_with(TRACK_SUFFIX): out.append([a, i])
    return out


static func _key_index(a: Animation, tr: int, k: int) -> int:
    return int(float(a.track_get_key_value(tr, k)) + 0.5)


## How many references point at entry `i`.
static func users(canvas: ZenCanvas, i: int) -> int:
    var n := 0
    for t in texts(canvas):
        if (t as ZenText).string_base == i: n += 1
    for at in _string_tracks(canvas):
        var a: Animation = at[0]
        for k in a.track_get_key_count(at[1]):
            if _key_index(a, at[1], k) == i: n += 1
    return n


## Reference count of every entry at once: index -> count.
static func usage(canvas: ZenCanvas) -> Dictionary:
    var out := {}
    for t in texts(canvas):
        var b := (t as ZenText).string_base
        out[b] = int(out.get(b, 0)) + 1
    for at in _string_tracks(canvas):
        var a: Animation = at[0]
        for k in a.track_get_key_count(at[1]):
            var i := _key_index(a, at[1], k)
            out[i] = int(out.get(i, 0)) + 1
    return out


## Empty entries nobody references, ascending.
static func holes(canvas: ZenCanvas) -> Array[int]:
    var p := pool(canvas)
    var u := usage(canvas)
    var out: Array[int] = []
    for i in p.entries.size():
        if p.entries[i].is_empty() and int(u.get(i, 0)) == 0: out.append(i)
    return out


static func is_hole(canvas: ZenCanvas, i: int) -> bool:
    return holes(canvas).has(i)


## Add `text` (an identical entry is reused, a hole is refilled) and return
## its index.
static func add(canvas: ZenCanvas, text: String) -> int:
    var free: Array = []
    free.assign(holes(canvas))
    var i := pool(canvas).add(text, free)
    _changed(canvas)
    return i


## Edit entry `i` IN PLACE: every element and key pointing at it follows.
static func set_text(canvas: ZenCanvas, i: int, text: String) -> void:
    pool(canvas).set_text(i, text)
    _changed(canvas)


## Blank entry `i` into a hole. Refused (false) while anything references it,
## as AnimDocRemoveString refuses; trailing holes are trimmed so a pool that is
## filled and cleared does not stay long forever.
static func remove(canvas: ZenCanvas, i: int) -> bool:
    var p := pool(canvas)
    if not p.has_index(i) or users(canvas, i) > 0: return false
    p.set_text(i, "")
    var hs := holes(canvas)
    var n := p.entries.size()
    while n > 0 and hs.has(n - 1): n -= 1
    p.truncate(n)
    _changed(canvas)
    return true


## Remove every hole and renumber what is left, rewriting each `string_base`
## and each `string` key to the entry's new index. Returns the holes removed.
static func compact(canvas: ZenCanvas) -> int:
    var p := pool(canvas)
    var hs := holes(canvas)
    if hs.is_empty(): return 0
    var remap := {}
    var kept := PackedStringArray()
    for i in p.entries.size():
        if hs.has(i): continue
        remap[i] = kept.size()
        kept.append(p.entries[i])
    for t in texts(canvas):
        var tx := t as ZenText
        tx.string_base = int(remap.get(tx.string_base, tx.string_base))
    for at in _string_tracks(canvas):
        var a: Animation = at[0]
        for k in a.track_get_key_count(at[1]):
            var i := _key_index(a, at[1], k)
            if remap.has(i): a.track_set_key_value(at[1], k, float(remap[i]))
    p.entries = kept
    p.emit_changed()
    _changed(canvas)
    return hs.size()


## Point `el` at entry `i` the way the editor writes any prop: a key at the
## playhead when auto-key is on or the element already keys `string`, else
## its base entry.
static func assign(canvas: ZenCanvas, el: ZenText, i: int, t: float, autokey: bool) -> void:
    if autokey or ZenKeyOps.has_track(canvas, el, "string"):
        ZenKeyOps.key_at_playhead(canvas, el, "string", t, float(i))
    else:
        el.string_base = i
    _changed(canvas)


## Move the canvas and every text onto `to` in one step, keeping the single
## shared instance (a per-node copy would split the pool).
static func repoint(canvas: ZenCanvas, to: ZenStrings) -> void:
    canvas.strings = to
    for t in texts(canvas):
        (t as ZenText).strings = to


## Give `canvas` its own copy of the pool, still shared by all its texts.
static func detach(canvas: ZenCanvas) -> void:
    repoint(canvas, pool(canvas).duplicate(true) as ZenStrings)


static func _changed(canvas: ZenCanvas) -> void:
    canvas.timeline_dirty()
    canvas.editor_repose()
