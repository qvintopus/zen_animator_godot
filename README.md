# Zen Animator (Godot)

Port of the C/raylib **Zen Editor** (`../raylib_base_template/src/anim*`) to Godot 4.7.2.
Animations are authored as Godot scenes and exported to video.

## Status

What works: the one-shot `.cfg` importer (shape/text/global elements); intro/loop/outro
trim with a smooth-loop blend and pause markers; signals (a named transition that
overrides the timeline per-property, so `crumble` and the cursor-anchored ripple are
reachable); frame-exact video export; and a gallery (F5) and live playback (F6) built on
Godot's own `AnimationPlayer`. Live interactive UI (wiring a signal to a button, a stage
running several copies of one document) is not built yet.

**F5 opens a gallery.** `zen_gallery.tscn` is the project's main scene: it lists every
animation in `anims/`, shows what each one actually contains (clock, elements, tracks,
easings, signals - all read off the scene, so it cannot drift from the data), and plays
them in place. Hotkeys are named `InputMap` actions (**zen_play**: ENTER/KP_ENTER/SPACE,
**zen_back**: ESC, **zen_restart**: R, **zen_prev/zen_next**: UP/DOWN,
**zen_signal_1..9**: 1-9), rebindable in Project Settings > Input Map rather than
hard-coded keycodes. **zen_play** or double-click plays, **zen_prev/zen_next** selects,
**zen_restart** restarts (re-scans in the list), **zen_back** backs out then quits, and
**zen_signal_1..9** fire a signal while playing - the only interactive way to see one,
since an export never fires one. Clicking another row while playing switches straight to
it, and a finished one-shot replays after holding its last frame, so the gallery always
shows motion. A **terminal** signal (pause_menu's `exit`) holds the pose it ends on - it no
longer snaps back to the timeline - and then the whole animation restarts.

**zen_toggle_intro** (I) and **zen_toggle_loop** (L) are viewer toggles, persisted in
`ZenSettings` and shown as `[INTRO ..] [LOOP ..]` badges in the status line: intro off
starts playback at `intro_end`; loop off plays once and holds the last frame (no wrap, no
auto-replay - including after a terminal signal). They are `ZenCanvas.play_intro` /
`play_loop`, runtime overrides the exporter never reads.

The left column is an accordion: **animations** (open by default) and **assets (visual)**.
Clicking a header (or **zen_tab**, TAB) opens that section and collapses the other; each
header stays pinned while its own list scrolls, and the selection is kept in view.

Each screen's footer names only its essential keys (a full legend in one Label set the
window's minimum width and pushed the gallery off both sides of the screen). **Hold H**
(**zen_help**) for a sheet of every hotkey of the current screen - gallery, playback or
shape editor - read from the live InputMap, so rebinding a key updates it.

**Visual assets are pixel shapes** - the original editor's `.shp` files, ported as
`ZenPixelShape` resources in `assets/shapes/*.tres` (`tools/import_shp.gd` converts them).
A pixel shape is a grid of fill/outline cells with no colour of its own: a `custom`
`ZenShape` tints fill with its `color` track and outline with `outline_color`, and a
stepped `shape_id` track switches between `shape_refs`. A missing asset draws a magenta
box with a diagonal, so it shows in exports too. ENTER on an asset (or "+ new asset...")
opens the **shape editor** (`tools/zen_shape_editor.tscn`): pen / line / rect / flood-fill
with fill, rim or erase ink, brush size, mirror X, resize, clear, bulk ink, auto-outline,
UndoRedo-backed undo/redo, a reference image (native file dialog or drag-and-drop) traced
with fade/threshold/scale/offset and converted to pixels, a live preview tinted with
pickable colours, and rename / duplicate / delete. It knows nothing of the old `.shp`
text format - only `tools/import_shp.gd`, the one-shot migration, does. The editor works on a copy; **Save** writes the `.tres` and updates the
already-loaded resource, so animations using it redraw at once.

**Scenes play on F6.** A `ZenCanvas` builds a real Godot `AnimationPlayer` for itself, so
opening a scene and running it animates, and `intro_end` / `outro_start` appear as
draggable markers on Godot's own timeline. The live clock is driven entirely through
Godot's `AnimationPlayer` section API (`play_section` / `play_section_with_markers`): a
document with an intro plays through once, then `ZenCanvas._process` narrows the
AnimationPlayer's own section to `[intro_end, outro_start)`, so Godot's native section-loop
restarts the body there and never at 0 - see the design note below.

Easings are now **Godot's own** (`Tween.interpolate_value`), not the raylib port - see
the design note below for what that changed and why.

The menus match the raylib reference in layout, size and timing - raylib is a historical
reference now, not a fidelity target (text in particular renders through a real Godot font,
not raylib's bitmap metrics; see the design note below). The loop seam is closed: on
`main_menu` the wrap went from a mean channel delta of **0.587 to 0.019**, which is the
same order as an ordinary adjacent frame pair (0.007).

The suite stands at **1196 numeric checks** and **31 render checks**, all green. Crumble and
the cursor-anchored ripple render correctly; `VISUAL_CHECKS.md` lists what to look at.
Final sign-off is the user's.

Five bugs so far that only a *rendered pixel* could find, all now pinned by
`tools/test_render.tscn`:

1. the exporter inherited raylib's vertical flip (Godot's SubViewport is already top-down);
2. the design canvas is **320x180**, not 1280x720 (see below);
3. the loop blend was armed around `pose()`, but elements read their properties in
   `_draw()`, which Godot defers to the frame being rendered - so the blend was live for
   an interval in which nothing consulted it. Every property-level test passed while the
   renderer blended nothing. The weight is now captured *into* the element by `pose()`
   and read back during `_draw()`.
4. a signal's `replay` flag used to start the live clock outright - so it ticked during the
   exporter's `await` and re-posed the canvas to its own `t`. Every property read back
   correctly while the frame came out black.
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

The **Export dialog** (press `E` in the gallery, or `Ctrl+E` to queue an animation onto a
chain without opening it) is the primary export path - every option below, plus chaining
multiple animations, AVI, a GIF alpha cutout, a size estimate, and progress/cancel. See
`docs/plans/export-dialog.md`. The CLI below is the scripted/batch door onto the exact same
engine (`ZenExport.plan_chain()` + `Job`), useful for CI or a one-off from a terminal.

```sh
./Godot_v4.7.2-stable_linux.x86_64 --path . --rendering-driver opengl3 \
    tools/export_scene.tscn -- --anim=mouse_ripple --fps=60 --fmt=webm --scale=2
```

| Flag | Default | Notes |
|---|---|---|
| `--anim=` | `mouse_ripple` | scene basename in `anims/` |
| `--chain=a,b,c` | - | overrides `--anim=`; every link must share one `design_size` |
| `--fmt=` | `webm` | `webm` \| `mp4` \| `gif` \| `avi` \| `png` |
| `--fps=` | `30` | capped at 60 for gif, 120 for video |
| `--scale=` | `4` | 1..8, nearest-neighbour upscale (320x180 x4 = 1280x720) |
| `--quality=` | `70` | 0..100, mapped to codec CRF 34..18 (webm/mp4 only) |
| `--quality_gif=` | `16` | 1..16 palette depth (gif only) |
| `--cutout=` | `128` | 1..255 alpha threshold (gif + `--transparent` only) |
| `--intro` | off | include the intro (one-shot); omit for a seamless loop |
| `--transparent` | off | gif/png only - VP9 decodes `yuva420p` opaque |
| `--pause_hold=` | `2.0` | seconds a pause marker (or a chain join) freezes for |
| `--join_pause` | off | freeze on each join between chained animations |
| `--name=` | first anim name | output basename |
| `--out=` | `res://exports` | output directory |

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
# 1196 checks
./Godot_v4.7.2-stable_linux.x86_64 --headless --path . --script res://tests/run_tests.gd

# importer fidelity: 2657 sampled comparisons, must be 0 mismatches
./Godot_v4.7.2-stable_linux.x86_64 --headless --path . --script res://tools/compare_ripple.gd

# what an imported scene actually resolves to, without a display
./Godot_v4.7.2-stable_linux.x86_64 --headless --path . \
    --script res://tools/dump_scene.gd -- main_menu

# 31 render checks - NEEDS A DISPLAY. Pins frame orientation, the 320x180 canvas, the
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
addons/zen/runtime/    zen_easing, zen_curve, zen_sampler, zen_canvas (clock + pauses),
                       zen_element, zen_shape, zen_text, zen_text_metrics, zen_global,
                       zen_props (property registry), zen_signal_player (override eval),
                       zen_signal_bus (per-canvas dispatch), zen_signals (global relay
                       autoload), zen_anim_builder (Godot AnimationPlayer + timeline markers),
                       zen_pixel_shape (the pixel-shape asset), zen_assets (asset lookup/save)
addons/zen/fonts/      bundled fonts (LICENSES.md) - ZenText's project-default font
addons/zen/importer/   zen_cfg_parse (grammar), zen_cfg_build (nodes), zen_cfg_import (entry)
zen_gallery.tscn       the main scene (F5): browse, inspect and play animations
tools/                 zen_gallery.gd, zen_options.gd (font picker), zen_shape_editor.gd/.tscn
                       + zen_pixel_canvas.gd + zen_shape_preview.gd (shape editor),
                       zen_hotkey_help.gd (the hold-H hotkey sheet),
                       import_shp.gd (.shp -> .tres), zen_export.gd (the
                       engine: plan_chain + Job), zen_export_dialog.gd/.tscn (the Export
                       screen, E / Ctrl+E), export_scene.tscn (CLI door onto the same
                       engine), build_ripple.gd, compare_ripple.gd, dump_scene.gd,
                       test_render.tscn,
                       signal_shots.tscn (renders what an export cannot show),
                       gen_ease_ref.gd (regenerates tests/ease_ref.txt),
                       gen_input_map.gd (regenerates project.godot's [input] section)
assets/shapes/         pixel-shape assets (ZenPixelShape .tres)
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
render path. The intro-skip-on-loop rule *is* expressible on Godot's own clock (added in
4.4): `AnimationPlayer.play_section_with_markers()` loops strictly inside a marker range and
wraps to its start marker, never to 0 - what `Animation.loop_mode` alone cannot do. See the
next note for how `ZenCanvas` drives it.

**Text is drawn through a real Godot font**, bundled at `addons/zen/fonts/` (Source Sans 3
Regular, SIL OFL 1.1, the raylib template's own default - see `LICENSES.md` there).
`ZenText.font` is a per-element override; null falls back to the project default. A text
element's position is its CENTRE, so `ZenTextMetrics.measure()` decides where the box
lands - and that box is a LAYOUT rule (`size_px * lines + LINE_SPACING * (lines-1)`), not a
font metric: `Font.get_string_size()` ignores `\n` entirely (measured on 4.7.2) and a real
font's ascent+descent does not equal `size_px` the way a fixed-size bitmap font's does, so
deriving the box from the font would move every text element on every font swap, defeating
the point of making the font a choice. Each line's own baseline is placed proportionally
inside its slot instead (`ZenText._baseline_offset`), so swapping fonts changes letterforms
without moving anything. The old approach - reproducing raylib's bitmap-font width table
exactly and squeezing each Godot glyph into its cell - is gone; a pixel-exact raylib bitmap
font remains a possible future per-animation font choice, not built in this pass (see
`docs/plans/session-2026-10-19-log.md`).

**The live clock is `AnimationPlayer`'s own section, narrowed at the right moment.** A Zen
document is `[0,intro_end)` + `[intro_end,outro_start)` + a trimmed outro, and the intro is
a one-shot lead-in: it plays on the first pass and is skipped on *every* pass after it.
`ZenCanvas.setup_animation_player` starts a document with an intro via
`play_section(ANIM, 0.0, play_end())` under `Animation.loop_mode = LOOP_NONE` (plays once,
holds at the end); `ZenCanvas._process` watches for that section's end and, on the first
crossing, flips `loop_mode` to `LOOP_LINEAR` and calls
`play_section_with_markers(ANIM, "intro_end", "outro_start")` (or `set_section` as a
fallback when a marker is absent) - which both resumes playback AND restarts it at
`intro_end`, exactly the wrap target. Two behaviours here are measured on 4.7.2, not
documented anywhere: a section only auto-loops under `LOOP_LINEAR` (`LOOP_NONE` plays once
and holds, regardless of which `play_section` variant started it), and `is_playing()`
already reports `false` on the very frame a `LOOP_NONE` section reaches its own end - not
one frame later - so the handover cannot be gated on "still playing". Pause markers
(`ZenCanvas.pauses`) hold the AnimationPlayer at the marker's own instant
(`_seek_safe` + `pause()`) until `release_pause()`. The exporter ignores all of this and
builds an explicit frame list instead, which is what keeps a frame a pure function of
`(scene, t)` and renderable out of order.

A live scene's `AnimationPlayer` is driven by `live_playback` - `false` disarms it
entirely, which is load bearing, not tidiness: a clock ticking inside the exporter's
`await` re-poses the canvas to its own time, and every frame of a render would come out
byte-identical. `AnimationPlayer.seek()` does NOT clamp into whatever section is currently
active (measured: section `[0.5,1.5]`, `seek(0.1)` lands at `1.1`, not `0.5`) - `ZenCanvas`
funnels every seek through `_seek_safe()`, the one place in the project allowed to call
`_ap.seek()` directly, which widens the section first when the target falls outside it.

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
Zen signal appearing in Godot's Signals dock so a future button can be wired by dragging.

Evaluation is **per canvas**, and a thin `ZenSignals` autoload only fans a name out over
the `zen_canvas` group. That split is the C's own (`signal.c` / `anim_signal.c`) and it is
load bearing: one emit must reach every live instance with each blending from its *own*
pose, which a global bus owning evaluation state could not express - a stage running
`zooming_box` three times at once needs exactly this.

Four ordering rules carry the weight, in `prop()`, in the C's order:
**stepped props return before the override is consulted** (they key a pool index, so a
signal targeting `string` is ignored by design); a signal **replaces** the timeline *and*
the loop blend (an `if` instead of an `else` would still pass every seam test); the two
additive offsets - seq and pos-anchor - apply **even when the signal did not drive that
property** (`zooming_box` seq-targets a `scale` that has no plain target); and pos-params
**outrank** plain targets.

And the same `_draw()`-is-deferred trap again, the highest-risk detail here: elements read
properties inside `_draw()`, which Godot defers to the rendered frame, so `pose()` must
**capture** the signal's contribution into the element rather than let `_draw()` ask the
bus. The obvious implementation reads correctly and passes every property-level test while
the renderer shows nothing.

Export purity needed one more guard than expected. A signal's `replay` flag calls
`ZenCanvas.rewind_timeline()`, never anything that would start the live clock - a `play()`
there would tick inside the exporter's `await` and re-pose the canvas to its own `t`,
caught by a pixel, not by a property. Exports are guarded three ways: `inert` on every bus,
`set_process(false)` until fired, and `rewind_timeline()` rather than any path that plays.
