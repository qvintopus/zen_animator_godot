@tool
extends Node
##
## The global signal relay: the port of signal.c's named dispatch, registered as
## an autoload so game code can say ZenSignals.emit("TV-out") without knowing
## which canvases are on screen.
##
## DELIBERATELY A RELAY, NOT A PLAYER. It holds no signal player, no clock and
## no captured pose: it looks up canvases by group and forwards the name. That
## is not minimalism for its own sake - the C gives EVERY instance its own
## AnimSignalPlayer so that one emit reaches all of them, "each blending from
## its own pose" (anim_stage.c:155-159). A bus owning evaluation state could not
## express that, and Phase 6 runs zooming_box three times at once, which is
## precisely the case that needs it.
##
## So: dispatch is global, evaluation is per-canvas. canvas.bus().fire(...) stays
## the direct path and is what the tests call; this is for "broadcast to
## everything on screen".
##
## NO class_name: the autoload singleton is already named ZenSignals, and a
## global class of the same name is a parse error ("hides an autoload
## singleton"). The autoload name is the access path - ZenSignals.emit(...).
##

## Relayed for every canvas that accepted the signal.
signal relayed(signal_name: String, canvas: Node)


## Fire `signal_name` on every live canvas that declares it. Returns how many
## accepted it, so a caller can tell "nothing on screen listens" from "fired".
##
## An INERT bus is skipped (ZenSignalBus.fire returns false): an autoload
## outlives any one scene, so without this an emit from editor tooling could
## install an override in the middle of an export and make a frame depend on
## something other than (scene, t).
func emit(signal_name: String, params: Dictionary = {}) -> int:
    var n := 0
    for c in _canvases():
        var bus := (c as ZenCanvas).bus()
        if bus == null: continue
        if bus.fire(signal_name, params):
            n += 1
            relayed.emit(signal_name, c)
    return n


## True when any live canvas declares `signal_name`.
func has(signal_name: String) -> bool:
    for c in _canvases():
        var bus := (c as ZenCanvas).bus()
        if bus != null and bus.has(signal_name): return true
    return false


## The canvases that would receive `signal_name`, inert ones included - this is
## introspection, so it reports what is declared rather than what would fire.
func listeners(signal_name: String) -> Array:
    var out: Array = []
    for c in _canvases():
        var bus := (c as ZenCanvas).bus()
        if bus != null and bus.has(signal_name): out.append(c)
    return out


## Every authored signal name live on screen, deduplicated.
func names() -> Array:
    var out: Array = []
    for c in _canvases():
        var bus := (c as ZenCanvas).bus()
        if bus == null: continue
        for nm in bus.names():
            if not out.has(nm): out.append(nm)
    return out


func _canvases() -> Array:
    if not is_inside_tree(): return []
    return get_tree().get_nodes_in_group(ZenCanvas.GROUP)
