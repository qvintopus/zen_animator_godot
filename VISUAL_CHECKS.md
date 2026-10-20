# Visual checks

**Last run: 2026-10-18, all sections pass.** Six pixel-only bugs were found this way
(vertical flip, 4x-wrong design canvas, loop-blend timing, a live clock ticking during
export, the crumble transform, and the signal override) - all now pinned automatically by
`tools/test_render.tscn`. Final sign-off is the user's.

**Needs a fresh eye (2026-10-19, not yet confirmed):** text now draws through a real Godot
font instead of raylib's bitmap metrics (section 3), and `pause_menu`'s live loop behaviour
changed - it now loops back into its body instead of freezing at its outro (section 6). Any
PNG/webm exported before 2026-10-19 is NOT byte-comparable to a fresh export of the same
scene. See `docs/plans/session-2026-10-19-log.md` for what changed and why.

Keep this list for re-checking after changes that touch rendering.

Every command here needs a real display: `--headless` cannot render at all
(`frame_post_draw` never fires and the export hangs). Nothing in this file is
required for the headless test suite, which stays green independently.

```sh
G=./Godot_v4.7.2-stable_linux.x86_64
EXPORT="$G --path . --rendering-driver opengl3 tools/export_scene.tscn --"
```

---

## 1. Ripple still exports

```sh
$EXPORT --anim=mouse_ripple --fps=60 --fmt=webm --scale=2
ffprobe -v error -count_frames \
  -show_entries stream=codec_name,width,height,r_frame_rate,nb_read_frames \
  -of default=nk=1 exports/mouse_ripple.webm
```

Expect at `--scale=2`: `vp9 640 360 60/1 120` (the canvas is 320x180). Watch it: a thin ring expands from the centre
and fades out over 2s. No flicker, no pop at the start.

## 2. Imported vs hand-built ripple

The importer's output must match the hand-built scene that was already verified.
`tools/compare_ripple.gd` does this numerically and headlessly (see below), but
confirm it visually too:

```sh
$EXPORT --anim=mouse_ripple_imported --fps=60 --fmt=webm --scale=2
ffmpeg -y -v error -i exports/mouse_ripple.webm          -vf "select=eq(n\,80)" -vframes 1 /tmp/hand.png
ffmpeg -y -v error -i exports/mouse_ripple_imported.webm -vf "select=eq(n\,80)" -vframes 1 /tmp/imp.png
ffmpeg -v error -i /tmp/hand.png -i /tmp/imp.png -lavfi ssim -f null -
```

Expect: SSIM `All:1.000000` - verified byte-identical. Anything below ~0.99 means the
importer changed the animation.

## 3. The two menus

```sh
$EXPORT --anim=main_menu  --fps=60 --fmt=webm --scale=2            # seamless loop
$EXPORT --anim=main_menu  --fps=60 --fmt=webm --scale=2 --intro    # one-shot with intro
$EXPORT --anim=pause_menu --fps=60 --fmt=webm --scale=2 --intro
```

Check against the raylib reference `../raylib_base_template/anims/exports/MAIN_MENU.webm`:

- title "MAIN MENU" and subtitle slide in from the left while fading up, finishing
  together around t=0.6;
- the white bar under the subtitle collapses in width and shifts white -> blue;
- the 16px yellow ball drops in from below, then bobs gently;
- two teal diagonals cross behind everything, static;
- in the LOOP render (no `--intro`) the wrap must be invisible - the ball's bob and
  the bar's colour both resolve through the 0.3s smooth-loop blend. A visible jump
  at the loop point means the blend is wrong.

Text draws through a real Godot font, by default raylib's own bitmap font rebuilt glyph for
glyph (2026-10-19, `tools/gen_raylib_font.gd`). What to look for:

- is the text centred, and does `\n` still break correctly? (layout)
- do the letters look like the raylib editor's - blocky, crisp, no blur or stray pixels
  from neighbouring atlas cells, at export scale 1 and 4?

### Crumble

`TV-out` drives the title/subtitle crumble, so it is only visible once a signal is
fired - see the signals section below. An ordinary export never fires one (that is the purity
guard), so crumble does not appear in any of the renders above. That is correct,
not a missing feature.

## 4. Alpha / transparency

```sh
$EXPORT --anim=mouse_ripple --fps=30 --fmt=png --transparent --scale=1
```

Expect `exports/mouse_ripple/mouse_ripple_0040.png` to have a transparent
background with a soft-edged ring. If the ring's edge looks doubly dark, the
premultiply workaround was wrongly reintroduced (Godot already blends straight
alpha - verified, a 50% rect reads back 0.498).

GIF transparency:

```sh
$EXPORT --anim=mouse_ripple --fps=30 --fmt=gif --transparent --scale=1
```

Do NOT expect webm/mp4 transparency: libvpx-vp9 accepts `yuva420p` and even
reports it, but the frames decode back fully opaque.

## 5. Frame alignment (off-by-one guard)

Frame 0 must be the pose at `t = start`, not one frame late.

```sh
$EXPORT --anim=mouse_ripple --fps=10 --fmt=png --scale=1
```

`mouse_ripple_0000.png` should be essentially empty: at t=0 the circle is 0.4px
across with a 0.12px outline, below the half-pixel threshold. If frame 0 already
shows a visible ring, the seek is landing one frame ahead.

---

## 6. Loop seam, intro trim, pauses

The seam is now pinned automatically by `tools/test_render.tscn`
(`test_loop_seam_pixels`), so these are confirmations rather than the only safety net.

### 1. The loop no longer jumps

```sh
B=./Godot_v4.7.2-stable_linux.x86_64
$B --path . --rendering-driver opengl3 tools/export_scene.tscn -- \
	--anim=main_menu --fps=30 --fmt=webm
mpv --loop exports/main_menu.webm
```

Watch the wrap. The title, subtitle, rule and ball should all carry straight through it;
nothing should step. Measured: mean channel delta across the wrap fell from **0.587
(unblended) to 0.019**, against **0.007** for an ordinary adjacent frame pair.

### 2. The intro plays once, and only when asked

```sh
$B --path . --rendering-driver opengl3 tools/export_scene.tscn -- \
	--anim=pause_menu --fps=30 --fmt=png                 # 14 frames: loop body only
$B --path . --rendering-driver opengl3 tools/export_scene.tscn -- \
	--anim=pause_menu --fps=30 --fmt=png --intro=true    # 60 frames: with the run-in
```

`pause_menu` is mostly intro (`intro_end` 1.513 of a 1.987 play length), so the two
counts should differ sharply. With `--intro` the clip is a one-shot and ends on its
authored tail; without it, it is a seamless loop.

### 3. A pause marker freezes the export

`ma_prog_01` has four pause markers (`pause_1`.. in its `zen` animation); another is
added by a `pause 1.0 0` line plus a re-import, or by dragging/adding a `pause_N`
marker in Godot's animation panel. In the gallery, playback holds at a marker and SPACE
continues. At `--fps=30 --pause_hold=2` the output should grow by
60 frames, all of them identical, starting at the marker's own frame.

### 4. The outro is never rendered

`main_menu` has `duration` 3.346 but `outro_start` 3.211. No exported frame should come
from after 3.211 - the tail exists in the document for the editor's benefit only.

---

## 7. Signals (override layer)

A signal overrides the timeline per-property, easing from the pose on screen *right
now* into its authored keys. Three of these checks are pinned automatically by
`tools/test_render.tscn` (`test_crumble_renders`, `test_ripple_anchors_to_cursor`,
`test_signal_export_purity_pixels`); the rest need an eye.

**Signals never fire during an export.** The exporter sets `inert` on every bus
before rendering, so a frame stays a pure function of `(scene, t)` and remains
renderable out of order. Seeing a signal therefore needs a *live* scene, not an
exported file - which is why the checks below run the scene rather than `ffprobe` it.

### 1. Crumble is visible for the first time

```sh
B=./Godot_v4.7.2-stable_linux.x86_64
$B --path . --rendering-driver opengl3 tools/test_render.tscn
```

Expect `26 render checks, 0 failures`. The crumble check asserts five independent
observables on `main_menu` after firing `TV-out`, all measured against the un-fired
frame:

- the ink **centroid moves down** - MAIN_MENU authors no `crumble_fx`, so the
  defaults apply: direction **90 degrees is straight DOWN** with a 12 degree spread.
  The title slides down as a near-block, it does not fan out sideways. (An earlier
  version of this test wanted a growing bounding box and failed for exactly this
  reason - the renderer was right and the test was wrong.)
- total ink **energy drops** - colour is multiplied by `alpha * (1 - crumble)`.
- the glyphs **tumble** - per-glyph overlap with a pure translation of the original
  stays under 0.9, which separates a scatter from a slide.

**This check found a real bug, and only by looking.** `_draw_glyph` called
`draw_set_transform`, which REPLACES the canvas transform rather than composing
with it - so it overwrote the per-glyph placement `_draw_crumbled` had just set,
and every glyph was drawn at its raw baseline. The title collapsed into a single
smear in the top-left corner while every crumble PROPERTY read back correct.

The three original observables all passed on that smear: it is below the original
centroid, it is dimmer than the intact title, and it does not overlap a pure
translation of it. Two further checks now pin where the ink actually goes - it
must stay in a band near the title, and the text's horizontal centroid must stay
centred (it read 54.9 of 320 while broken). Both were verified to fail when the
bug is reintroduced.

Deliberately NOT a bright-pixel COUNT: at crumble 0.76 the colour alpha is
`1 - 0.76`, so the correct render leaves FEWER bright pixels (62) than the broken
one (136), whose stacked glyphs accumulate alpha. Counting has the sign backwards.

Determinism is also checked - two independent canvases driven to the same signal
clock by different routes (one step vs eleven) must render the same bytes. Known
limit, measured rather than assumed: it cannot catch a hash that reads the clock
WITHIN one draw, because each viewport executes `_draw()` once from identical
state (verified by injecting `randf() * 180.0` into the glyph angle - both frames
stayed byte-identical). Clock-independence of the hash is covered numerically
instead, and structurally by the hash taking only the glyph index.

### 1b. Look at the frames

```sh
$B --path . --rendering-driver opengl3 tools/signal_shots.tscn
```

Writes `exports/signal_shots/*.png` - the crumble arc at six points plus the
ripple at three emit positions. This is the only way to SEE a signal, since an
export never fires one. What the crumble strip should show:

- at 0.15s the title is essentially intact, with the faintest per-glyph tilt;
- by 0.35s glyphs are visibly tumbling at independent angles, text still readable;
- by 0.9s the words are breaking apart and drifting DOWN (dir 90 is down, spread
  12, so it is a narrow downward cone, not a starburst);
- by 2.0s it has faded out, alpha being `1 - crumble`.

A title that vanishes immediately, or a white block in a corner, is the transform
bug above.

### 2. The ripple is born at the cursor

`mouse_ripple`'s `ripple` signal uses `pos_anchor`, which does **not** replace the
slot - it adds a constant translation, so the element is born at the cursor and then
plays its authored path. Pinned by `test_ripple_anchors_to_cursor`, which emits at
`(0.25, 0.30)` and measures the ring's centroid there.

Sampled at `t = 0.75` deliberately: the scale track runs to 10 by `t = 2`, and a ring
of ~100px radius centred off-centre is clipped by the canvas edges, which drags the
measured centroid back toward the middle and makes a working anchor look broken.

To see it by hand, run the scene and click around - the ring should appear under the
pointer each time, not at the canvas centre. `replay` is set, so each click restarts
the ripple from the beginning.

### 3. Export purity still holds with a bus present

```sh
$B --path . --rendering-driver opengl3 tools/export_scene.tscn -- \
	--anim=main_menu --fps=30 --fmt=webm
```

Must be byte-identical to an earlier export of the same scene/settings. All five scenes
carry a `Signals` node, and a bus that ticked during the exporter's `await` would re-pose
the canvas to its own clock, which would blank every frame of a render to the same
instant. Guarded three ways: `inert` during export, `set_process(false)` until fired, and
`ZenCanvas.rewind_timeline()` (never a path that plays) on the `replay` path.


---

## 8. Easings are Godot's now

`ZenEasing` is backed by `Tween.interpolate_value`, not the raylib/Penner port. The
raylib `.webm` is NO LONGER the fidelity target - a visual diff against it will show real
differences and that is expected.

What actually changed, measured rather than guessed: linear/sine/quad/cubic agree with
raylib to 1e-7, which covers 165 of the 170 keys in the bundled documents. Only **four**
keys use a curve where the families differ:

| scene | element | track |
|---|---|---|
| `main_menu` | `line_sub_title` | `color` (bounceOut) |
| `main_menu` | `Signals` | a `TV-out` key (bounceOut) |
| `mouse_ripple` | `shape` | `scale` (bounceOut) |
| `mouse_ripple_hand` | `shape` | `scale` (bounceOut) |

Measured effect of the swap at the bounce peak: **1.4-3.9% of pixels differ, worst
channel delta 0.07** (an upper bound - it includes VP9 re-encode noise).

```sh
$EXPORT --anim=mouse_ripple --fps=60 --fmt=webm --scale=2
```

Watch the ring's **expansion rhythm** around t=0.56-0.64, where the `scale` bounce lands.
It should settle with a slightly different spring than the old render - softer, since
Godot's bounce reaches further at the same p. The ball's bob is `sineInOut` and must look
EXACTLY as before; if the bob changed, something other than the easing table moved.

Note: Godot's expo does not reach its endpoint (`expoIn(1.0) = 0.999`). On `pause_menu`'s
slide-in that leaves the element 0.07px short on a 320px canvas, corrected by the next
key. Invisible, but it is why the endpoint test allows a wider tolerance for `expo*`.

## 9. Scenes play on F6

This is the one that had no coverage at all before: every scene opened **static**.

```sh
# Open the project, open anims/main_menu.tscn, press F6.
./Godot_v4.7.2-stable_linux.x86_64 --path . --editor
```

Expect the authored animation to run immediately: title and subtitle slide in from the
left while fading up, the rule under the subtitle collapses in width and shifts white to
blue, the yellow ball drops in and bobs. Then it should **loop seamlessly** - and the
wrap must restart at `intro_end`, so the slide-in is NOT replayed on later cycles.

In the animation panel, the `zen` animation should show `intro_end` and `outro_start` as
draggable markers. Dragging one edits the document (`ZenAnimBuilder.sync_markers`).

Checked automatically by `test_anim_player_plays` / `_markers` / `_tracks` / `_roundtrip`, all
verified to fail when their bug is reintroduced. Two of those three did NOT bite at
first, which is worth recording:

- the stepped-prop assertion walked `main_menu`, which carries **no** stepped track, so
  it was vacuously true. It now builds a canvas that has one.
- the wrap check sampled `pose_time` a few frames after the wrap, by which point the
  clock has passed `intro_end` anyway - so "restart at 0" passed it too. Worse,
  `main_menu` cannot distinguish the two formulas at all: its body is longer than its
  intro, so `fmod(raw, cyc)` and `intro_end + fmod(raw - intro_end, cyc)` agree. The rule
  is now pinned on `pause_menu`, whose long intro (1.513 of 1.987) makes them diverge
  sharply (1.5230 correct vs 0.1010 buggy).

The exporter must stay unaffected: `live_playback` is cleared BEFORE the canvas enters
the tree (`export_scene.gd`), because `_ready()` is what starts the clock and Godot
defers `_ready()` past `add_child()`. Pinned by the distinct-frames check - a live clock
during the export await collapses every frame to the same instant.


## 10. The gallery (F5)

```sh
./Godot_v4.7.2-stable_linux.x86_64 --path . --rendering-driver opengl3
```

Expect a dark two-pane window: the animation list on the left, metadata on the right.

- **ENTER** or **double-click** plays the selected animation; **single click only
  selects**, so metadata can be read without committing to playback.
- While one is playing, **clicking another row switches straight to it** and keeps
  playing.
- A **one-shot replays** after holding its final frame for ~0.9s, with `[ended]` shown in
  the status while it holds. `mouse_ripple` and `game_start` are the one-shots. This is a
  gallery affordance only - an export must never loop a one-shot, and does not.
- **R** restarts the playing animation; in the list it re-scans `anims/`, so a scene
  edited in another window appears without restarting the app.
- **ESC** backs out of playback, then quits from the list.
- **1-9** fire the playing document's signals. `main_menu` has one (`TV-out`) and the
  title should crumble; `mouse_ripple` has `ripple`. The status shows `[signal]` while
  one runs.

Check the stage is **crisp, not blurred** (nearest-neighbour) and that **nothing is
clipped** - both teal diagonals in `main_menu` must reach the frame corners. The stage
keeps the document's own aspect, so a non-16:9 window letterboxes rather than cropping;
Zen geometry is fractional, so cropping silently hides elements instead of scaling them.


## 11. Export dialog (E / Ctrl+E)

```sh
./Godot_v4.7.2-stable_linux.x86_64 --path . --rendering-driver opengl3
```

- **E** opens the Export dialog from the gallery list or from a playing animation; **ESC**
  closes it (cancelling a running job first if one is in flight, closing on a second ESC).
- **Ctrl+E** tags the selected (or playing) animation onto an export queue **without**
  opening the dialog - the gallery's status line should show `[queued: N]`. Queueing a
  second animation with a different canvas size must be **refused** with a reason in the
  status line, not silently dropped.
- Opening the dialog with a non-empty queue should seed the chain list with it; a
  successful export should clear the queue (check by re-opening E afterwards).
- **+ Add animation** opens a search popup; an animation whose canvas does not match the
  chain's first link must appear **disabled, not hidden**, with a tooltip explaining why.
  The chain is capped at 8 links - the Add button should disable past that.
- Switching **format** should disable (not hide) ffmpeg-only formats with a visible hint
  when ffmpeg is not on the machine running the build, and re-cap the fps field (GIF: 60).
- **Scale** buttons 1x-8x should update the resolution line using the chain's *first
  link's own* canvas size, not a hardcoded 320x180.
- Build a 2-link chain of two same-size animations: the frame/duration line and the size
  estimate should update live as format, scale, fps, and quality change. GIF/PNG read
  "Estimated size:", MP4/WebM read "Rough guess:", AVI reads "Output size:" (exact).
- Export a GIF with transparency and a cutout threshold change, then an MP4 with a changed
  quality slider - both should produce a real file in `exports/` and the status line
  should report the frame count and path.
- **Cancel mid-export** (press the button again while it reads "Cancel") and confirm **no
  partial file** is left in `exports/` for a video format, and that every setting control
  was frozen (greyed out / non-interactive) for the duration of the run.
- **Folder** button opens `exports/` in the OS file manager; it should be disabled until
  that directory actually exists (i.e. before the first export in a fresh checkout).
- Reopen the dialog after closing it: every field should come back exactly as left
  (`ZenSettings.set_export_defaults()`), except scale, which was already shared with
  Options and format/fps.

---

## 11. Gallery sections, playback toggles, shape editor

```sh
$G --path .          # F5: the gallery
```

- **Accordion.** "animations" is open on start, "assets (visual)" collapsed below it.
  Click "assets (visual)" (or TAB): animations collapse to their header and the 9 pixel
  shapes list under it with a preview and "used by". Each header stays put while only its
  list scrolls; holding DOWN keeps the selection on screen.
- **Terminal signal holds.** Play `pause_menu`, press `1` (`exit`): the title flies off and
  the screen **stays** empty with `[signal end]` in the status, then the animation restarts
  from its intro. Press `L` (`[LOOP off]`) and fire again: it stays empty for good.
- **I / L.** `I` toggles `[INTRO on/off]` (off: playback starts at intro_end); `n/a` on a
  document with no intro. `L` off plays once and holds the last frame.
- **Custom shapes render.** Play `ma_prog_02_coding` and `fangs_test`: icons are crisp pixel
  art (square texels, no blur) tinted by their element colours.
- **Shape editor.** ENTER on `book_icon`: paint (LMB), erase (RMB), zoom about the cursor
  (wheel), pan (MMB), grid at high zoom, the brush footprint follows the cursor. Try line /
  rect / fill (L / R / G), mirror (M), undo/redo (Ctrl+Z / Ctrl+Shift+Z). The title gains `*`
  when dirty; ESC asks Save / Discard / Cancel. Drop a PNG on the window, raise "threshold
  preview", Convert. Save, go back, play `ma_prog_02_coding`: the book shows the edit.
- **Footer and H.** At a narrow window (e.g. 960 wide) the gallery fits with nothing cut
  off left or right, in both sections and while playing. Holding H shows the hotkey sheet
  for that screen and releasing H hides it; the same in the shape editor.
- **Options.** Opens scrolled to the saved font, fonts A-Z, the search field sits on the
  "font" row and filters as you type; ESC clears the search, a second ESC closes.
- **Multi-select.** Click `game_start`, Shift+click `main_menu`: three rows highlight, the
  right pane lists them, the footer shows `E export 3  Delete delete 3`. E opens Export with
  that chain; ESC there and ESC again clears the selection (it does not quit). Ctrl+click
  toggles single rows; Shift+DOWN extends. Delete on copies only: the dialog lists the
  `.tscn` and its `.cfg`, and "Move to trash" puts both in the OS trash. In assets, a
  shape used by an animation is named in the dialog.

## 12. Scene editor (Ctrl+ENTER / N)

Not yet run by eye - added 2026-10-20 with the editor. Work on a copy: open a scene,
**File > Save as...** right away, and delete the copy afterwards.

- **Open.** Ctrl+ENTER on `main_menu` opens it; N opens a new scene whose HELLO title fades
  in. The first time, the Elements and Timeline panels are shown.
- **Panels.** The top-bar buttons and 1-4 summon Elements / Inspector / Document /
  Timeline. An unpinned panel floats over the canvas and closes on ESC, on a click on
  empty canvas, or when another unpinned panel opens on its side. **pin** keeps it open
  and the canvas shrinks to make room. Pins survive a restart. During playback (SPACE)
  the unpinned panels slide away and come back on pause; pinned ones (a pinned
  Timeline) stay, so the playhead can be watched running through the keys.
- **Playback.** SPACE at (or after) the end replays from 0, like Home then SPACE. With a
  pause marker (right-click the ruler > add pause), playback holds there; a click on the
  canvas, or SPACE, continues - in the gallery too.
- **Intro marker.** With no intro set (`zooming_box`), the blue intro triangle sits at
  0.00 in the lower half of the ruler, under the gold playhead handle; dragging the lower
  half moves the intro, dragging the upper half scrubs.
- **The timeline is the AnimationPlayer.** Select `title`: its `pos_x` and `alpha` lanes
  show the authored keys only (no fit keys), with intro/outro triangles at 0.62 / 3.21.
  Drag on the ruler: the canvas follows. Drag a key (Ctrl snaps to 0.1s); right-click it,
  choose `ease (incoming) > bounceOut`, and scrub through the segment - it bounces.
- **Auto-key.** K toggles it (the button turns red). Off: dragging an element moves its
  base pose, and keyed props are greyed out in the Inspector. On: dragging at t=1.0 keys
  pos_x/pos_y there (a prop's first key also pins its old value at 0).
- **Elements = node tree.** +shape adds `shape` at the centre, frontmost. Drag a row in
  the Elements list to reorder; draw order follows. Double-click (or F2) renames, and its
  keys keep playing. Delete removes it and its keys.
- **Undo.** Ctrl+Z / Ctrl+Shift+Z step through every edit above; a whole drag is one step.
- **Save.** Ctrl+S, back to the gallery: the copy is listed and plays exactly as edited.
  Open the copy's `.tscn` in the Godot editor: the Animation panel shows the bezier tracks
  plus a `zen_ease_<prop>` track beside each one.
