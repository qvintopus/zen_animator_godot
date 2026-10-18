# Zen Animator (Godot)

Port of the C/raylib **Zen Editor** (`../raylib_base_template/src/anim*`) to Godot 4.7.2.
Animations are authored as Godot scenes and exported to video.

## Status

**Phase 5 complete** (pending visual sign-off): signals override the timeline per-property,
so `crumble` and the cursor-anchored ripple are reachable for the first time.

**F5 opens a gallery.** `zen_gallery.tscn` is the project's main scene: it lists every
animation in `anims/`, shows what each one actually contains (clock, elements, tracks,
easings, signals - all read off the scene, so it cannot drift from the data), and plays
them in place. Hotkeys: **ENTER** or **double-click** plays, **UP/DOWN** selects,
**R** restarts (re-scans in the list), **ESC** backs out then quits, **1-9** fire a
signal while playing - the only interactive way to see one, since an export never fires
one. Clicking another row while playing switches straight to it, and a finished one-shot
replays after holding its last frame, so the gallery always shows motion.

Before this, F5 ran `tools/export_scene.tscn`, a batch tool that reads `--anim=` off the
command line - so pressing F5 in the editor started an exporter with no arguments.

**Scenes now play on F6.** A `ZenCanvas` builds a real Godot `AnimationPlayer` for itself,
so opening a scene and running it animates, and `intro_end` / `outro_start` appear as
draggable markers on Godot's own timeline. Before this, the only clock was `ZenPlayer`,
whose `autoplay` defaults false and was written into no scene - every scene opened static.

| Phase | State |
|---|---|
| 0 skeleton | done |
| 1 export pipeline + `mouse_ripple` | done |
| 2 one-shot `.cfg` importer | done |
| 3 text + global elements, MAIN_MENU / PAUSE_MENU | done |
| 4 intro/loop/outro, smooth blend, pauses | done |
| 5 signals (override layer) | **done**, one render check outstanding |
| 6 live interactive UI | next |

Easings are now **Godot's own** (`Tween.interpolate_value`), not the raylib port - see
the design note below for what that changed and why.

The menus match the raylib reference in layout, size and timing (SSIM 0.90 against
`MAIN_MENU.webm`, the residual being letterforms). The loop seam is now closed: on
`main_menu` the wrap went from a mean channel delta of **0.587 to 0.019**, which is the
same order as an ordinary adjacent frame pair (0.007).

The suite stands at **1152 numeric checks** and **26 render checks**, all green. Crumble and
the cursor-anchored ripple render correctly and are shown in `exports/signal_shots/`;
`VISUAL_CHECKS.md` lists what to look at. Final sign-off is the user's.

Five bugs so far that only a *rendered pixel* could find, all now pinned by
`tools/test_render.tscn`:

1. the exporter inherited raylib's vertical flip (Godot's SubViewport is already top-down);
2. the design canvas is **320x180**, not 1280x720 (see below);
3. the loop blend was armed around `pose()`, but elements read their properties in
   `_draw()`, which Godot defers to the frame being rendered - so the blend was live for
   an interval in which nothing consulted it. Every property-level test passed while the
   renderer blended nothing. The weight is now captured *into* the element by `pose()`
   and read back during `_draw()`.
4. a signal's `replay` flag called `ZenPlayer.play()`, which starts the live clock - so the
   player ticked during the exporter's `await` and re-posed the canvas to its own `t`. Every
   property read back correctly while the frame came out black.
5. `_draw_glyph` called `draw_set_transform`, which **replaces** the canvas transform rather
   than composing with it - so it overwrote the per-glyph placement the crumble path had just
   set, and the whole title collapsed into one smear in the top-left corner. Every crumble
   property was correct; only *where the ink landed* could see it, and the first three pixel
   checks (centroid down, energy drops, no overlap with a translation) were all satisfied by
   the smear. Caught by eye, from `tools/signal_shots.tscn`, not by the suite.

The lesson each time: a test that calls the same function the renderer calls is not the
same as a test that looks at a pixel.

## Export

Needs a real display: `--headless` cannot render (`frame_post_draw` never fires).

```sh
./Godot_v4.7.2-stable_linux.x86_64 --path . --rendering-driver opengl3 \
    tools/export_scene.tscn -- --anim=mouse_ripple --fps=60 --fmt=webm --scale=2
```

| Flag | Default | Notes |
|---|---|---|
| `--anim=` | `mouse_ripple` | scene basename in `anims/` |
| `--fmt=` | `webm` | `webm` \| `mp4` \| `gif` \| `png` |
| `--fps=` | `30` | capped at 60 for gif, 120 for video |
| `--scale=` | `4` | 1..8, nearest-neighbour upscale (320x180 x4 = 1280x720) |
| `--quality=` | `70` | 0..100, mapped to codec CRF 34..18 |
| `--intro` | off | include the intro (one-shot); omit for a seamless loop |
| `--transparent` | off | gif/png only - VP9 decodes `yuva420p` opaque |
| `--pause_hold=` | `2.0` | seconds a pause marker freezes for |

Boolean flags take a bare form (`--intro`) or a value (`--intro=true`, `--intro=0`).

`--intro` is the one-shot/loop switch and it also decides the blend: a loop render
(intro hidden) eases the cycle's tail into the loop-start pose, while a one-shot shows
its authored tail exactly as keyed.

Output lands in `exports/`.

## Import

One-shot: native Godot scenes are the source of truth, so this exists to carry the
existing documents across once. Headless - it authors resources and renders nothing.

```sh
./Godot_v4.7.2-stable_linux.x86_64 --headless --path . \
    --script res://addons/zen/importer/zen_cfg_import.gd
```

Reads `anims_src/*.cfg` -> writes `anims/<snake_name>.tscn`, and reports any element
kind it had to defer. All three kinds (shape, text, global) are supported, so the five
bundled documents import complete.

## Tests

Headless is fine - nothing here renders.

```sh
# 1152 checks
./Godot_v4.7.2-stable_linux.x86_64 --headless --path . --script res://tests/run_tests.gd

# importer fidelity: 2657 sampled comparisons, must be 0 mismatches
./Godot_v4.7.2-stable_linux.x86_64 --headless --path . --script res://tools/compare_ripple.gd

# what an imported scene actually resolves to, without a display
./Godot_v4.7.2-stable_linux.x86_64 --headless --path . \
    --script res://tools/dump_scene.gd -- main_menu

# 26 render checks - NEEDS A DISPLAY. Pins frame orientation, the 320x180 canvas, the
# loop seam, crumble, the ripple anchor and export purity - none of which a numeric
# test can see.
./Godot_v4.7.2-stable_linux.x86_64 --path . --rendering-driver opengl3 \
    tools/test_render.tscn

# signal evidence - NEEDS A DISPLAY. Signals never fire during an export (that is the
# purity guard), so this is the only way to SEE crumble and the ripple anchor.
# Writes exports/signal_shots/*.png.
./Godot_v4.7.2-stable_linux.x86_64 --path . --rendering-driver opengl3 \
    tools/signal_shots.tscn
```

The 34 built-in easings are compared against `tests/ease_ref.txt`, which is GENERATED
from Godot by `tools/gen_ease_ref.gd` - never hand-edited. A drift in the easing table is
caught immediately.
`compare_ripple.gd` checks the importer against the hand-built `mouse_ripple_hand.tscn`
by sampling every property across the whole timeline - two scenes can differ in text and
animate identically, so what is compared is what gets drawn.

Visual checks needing a display are collected in `VISUAL_CHECKS.md`.

## Layout

```
addons/zen/runtime/    zen_easing, zen_curve, zen_sampler, zen_canvas, zen_element,
                       zen_shape, zen_text, zen_text_metrics, zen_global,
                       zen_player (clock), zen_props (property registry),
                       zen_signal_player (override eval), zen_signal_bus (per-canvas
                       dispatch), zen_signals (global relay autoload),
                       zen_anim_builder (Godot AnimationPlayer + timeline markers)
addons/zen/importer/   zen_cfg_parse (grammar), zen_cfg_build (nodes), zen_cfg_import (entry)
zen_gallery.tscn       the main scene (F5): browse, inspect and play animations
tools/                 zen_gallery.gd, zen_export.gd, export_scene.tscn, build_ripple.gd,
                       compare_ripple.gd, dump_scene.gd, test_render.tscn,
                       signal_shots.tscn (renders what an export cannot show),
                       gen_ease_ref.gd (regenerates tests/ease_ref.txt)
anims/                 authored Godot scenes (source of truth)
anims_src/             the original .cfg files, input to the one-shot importer
tests/                 run_tests.gd + the generated easing reference
```

## Design notes

Three decisions carry most of the weight; the reasoning is in the file headers.

**Easing CURVES are Godot's; easing APPLICATION is `ZenSampler`'s.** These are two
separate questions and an earlier design note conflated them.

*The curves* come from `Tween.interpolate_value`, which is a **static** function exposing
Godot's whole family - bounce, elastic, back, spring included - with no Tween instance
needed. An earlier note ruled Godot's easings out as "pow(p,n)-only"; that measured
value-track `transition`, which really is, but it is the wrong door. Switching cost 4
content keys their exact raylib shape (`line_sub_title.color`, a `TV-out` key, and the
ripple's `scale`): measured 1.4-3.9% of pixels differ mid-bounce, worst channel delta
0.07. The other 165 of 170 keys are bit-identical, because linear/sine/quad/cubic agree
to 1e-7. The raylib `.webm` is therefore no longer the fidelity target. Custom curves
(`ZenCurve`, multi-knot bezier with overshoot and hold steps, which Godot's `Curve`
cannot express) register by name and **shadow** a built-in of the same name.

*The application* stays in `ZenSampler`, because Zen's easing is **incoming** (it eases
the segment ENDING at a key) while Godot's `transition` is outgoing, and because a value
track would have to duplicate the whole fraction-to-pixel resolver. So Godot owns timing
and key storage; `ZenSampler` owns interpolation.

**The `AnimationPlayer` owns time; `pose_looping()` owns the resolve.** The animation
carries ONE method track calling `canvas._anim_pose(t)` - the same entry point the
exporter uses - rather than a value track per property. Zen geometry is *resolved*, not
stored (a fraction of the canvas, times `scale`, times the unit mode, plus any signal
override), so there is no `Node2D.position` to key; a value track per property would mean
a second resolver that drifts from the first. `ZenAnimBuilder.populate_keys()` can mirror
the Zen tracks onto the timeline as real draggable keys for authoring, and
`sync_from_keys()` reads them back - but those tracks are an editing surface, never the
render path. The intro-skip-on-loop rule stays hand-written: Godot's looping always
restarts at 0, Zen's restarts at `intro_end`.

**Text layout is raylib's, text glyphs are Godot's.** Zen measured with raylib's built-in
10px bitmap font - a fixed per-glyph width table, not a real typeface - and a text
element's position is its CENTRE, so the measured box decides where the text lands.
`zen_text_metrics.gd` reproduces that table and `MeasureTextEx` exactly (verified against
the compiled raylib, `tests/text_ref.txt`), while the glyphs themselves are drawn with a
Godot font, each glyph scaled horizontally into the advance the layout reserved for it
(without that, the fallback font's glyphs run up to 39% wider or 35% narrower than the
cell and the text reads with ragged gaps). Centring, line widths, line breaks, letter
rhythm and crumble pen positions therefore match the original; only letterforms differ.
Embedding raylib's 128x128 atlas would close that last gap - worth doing only if the
drift proves objectionable.

**The clock is Zen's, not `AnimationPlayer`'s.** A Zen document is
`[0,intro_end)` + `[intro_end,outro_start)` + a trimmed outro. The intro is a one-shot
lead-in: it plays on the first pass and is skipped on *every* pass after it, and no
`AnimationPlayer` loop mode expresses that - Godot restarts at 0. So `zen_player.gd` owns
the clock, wraps with `fmod` (an overshoot carries into the next cycle rather than being
dropped), and holds at pause markers until released. The exporter ignores the player
entirely and builds an explicit frame list, which is what keeps a frame a pure function of
`(scene, t)` and renderable out of order.

A player is **inert until played** - `set_process(false)` until `play()`. That is load
bearing, not tidiness: a player ticking inside the exporter's `await` re-posed the canvas
to its own clock, and all 78 frames of a render came out byte-identical at `t=0`.

**The smooth-loop blend lives in `ZenElement.prop()`.** Keys clamp at the last key, so a
looping document holds its final pose and then snaps. Over the last `loop_blend` seconds
every property is eased (smoothstep `p*p*(3-2p)`) into the pose it holds at the loop
start, so the two poses coincide by the time the clock wraps. Putting it in `prop()` /
`prop_color()` - the only two callers of `ZenSampler` in the project - is what makes it
impossible for a property to be silently left unblended, which the plan flagged as a risk.
Three rules carry over from the C: colour blends **RGB only** (alpha rides its own scalar
track), **stepped** props (`string`, `shape_id`) are never blended because they key a pool
index and a value between two entries resolves to the wrong one, and the blend can never
be longer than the cycle it belongs to.

**Geometry is a fraction of a fixed 320x180 canvas.** That is Zen's
`ScreenStateTargetSize()` = 1920/6 x 1080/6 (`screen_state.c:23`), and `unit abs` sizes
are pixels *in that space* - MAIN_MENU's 16px ball is 5% of the width and lands at 64px
in a 1280-wide render. The exporter renders at native size and upscales the finished
frame nearest-neighbour (default 4x = 1280x720, matching the reference renders); drawing
into a bigger viewport would *reposition* everything rather than enlarge it, and gives up
the crisp pixel look.

**Export asks for frames, it does not capture them.** `ZenCanvas.pose(t)` is a pure
function of `t`, so frame `i` comes from `t = start + i/fps` - never an accumulated delta,
so there is no drift. Vsync must stay off (it is a ~200x throughput difference), stdin must
be closed and ffmpeg waited on (killing it truncates the container), and two raylib
workarounds do *not* port: Godot blends straight alpha (no premultiply dance) and its
SubViewport reads back top-down (no vertical flip).

**Signals own the emit edge only.** A Zen signal is a named transition that *overrides*
the timeline per-property, easing from whatever is on screen right now into its authored
keys. Godot's native signal table does the dispatch - `add_user_signal` on a `ZenSignalBus`
node, because the `signal` keyword cannot carry Zen's names (`signal TV-out` is a parse
error, and user signals do not survive `PackedScene.pack()`, so the data is an exported
Array re-declared at runtime). Everything downstream - capture, eval, seq, anchor - is
plain data and method calls. The payoff is real: `await bus.terminal_finished`, and every
Zen signal appearing in Godot's Signals dock so a Phase 6 button can be wired by dragging.

Evaluation is **per canvas**, and a thin `ZenSignals` autoload only fans a name out over
the `zen_canvas` group. That split is the C's own (`signal.c` / `anim_signal.c`) and it is
load bearing: one emit must reach every live instance with each blending from its *own*
pose, which a global bus owning evaluation state could not express. Phase 6 runs
`zooming_box` three times at once and needs exactly this.

Four ordering rules carry the weight, in `prop()`, in the C's order:
**stepped props return before the override is consulted** (they key a pool index, so a
signal targeting `string` is ignored by design); a signal **replaces** the timeline *and*
the loop blend (an `if` instead of an `else` would still pass every seam test); the two
additive offsets - seq and pos-anchor - apply **even when the signal did not drive that
property** (`zooming_box` seq-targets a `scale` that has no plain target); and pos-params
**outrank** plain targets.

And the Phase 4 trap again, which is the highest-risk detail in the phase: elements read
properties inside `_draw()`, which Godot defers to the rendered frame, so `pose()` must
**capture** the signal's contribution into the element rather than let `_draw()` ask the
bus. The obvious implementation reads correctly and passes every property-level test while
the renderer shows nothing.

Export purity needed one more guard than expected. `ZenPlayer.rewind()` exists because the
`replay` flag used to call `play()`, which calls `set_process(true)` - the live clock then
ticked inside the exporter's `await` and re-posed the canvas to its own `t`. That is the
Phase 4 regression (78 identical frames) resurfacing through a new path, and it was caught
by a pixel, not by a property. Exports are guarded three ways now: `inert` on every bus,
`set_process(false)` until fired, and `rewind()` rather than `play()`.
