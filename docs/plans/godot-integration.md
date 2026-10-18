# Deeper Godot integration for Zen Animator

## Context

The project is a port of a C/raylib animation editor to Godot 4.7.2. It is already
unusually well integrated in places — easing curves come from `Tween.interpolate_value`,
signal dispatch uses `add_user_signal`, timing hangs off a real `AnimationPlayer` with
native timeline markers, and the gallery is built from native `Control` containers. Most
deviations from engine defaults carry measured justifications in their file headers.

Reviewing what remains hand-rolled against what Godot now provides turned up one claim
that is no longer true, plus three cleanups:

1. **The clock is redundant, and its justification is outdated.** Every scene carries a
   `ZenPlayer` whose 208-line clock never runs in any real path (`autoplay` defaults false
   and is written into no scene); the gallery, exporter, F6 playback and render tests all
   drive the Godot `AnimationPlayer`, with `ZenCanvas._process` hand-rolling the loop wrap.
   The stated blocker — *"Godot's looping always restarts at 0, Zen's restarts at
   `intro_end`"* — is true of `Animation.loop_mode` but **false** for
   `play_section_with_markers()`, which I measured looping strictly inside the marker range
   and wrapping back to `intro_end`, never to 0. Same shape of error as the project's
   earlier easing discovery: the capability existed, the wrong door was tried.
2. **The raylib text emulation is debt in the wrong shape.** `zen_text_metrics.gd`
   reproduces raylib's bitmap-font width table and `zen_text.gd` squeezes each Godot glyph
   into a raylib advance cell — hardcoding one font's metrics into the renderer. The fix is
   not to delete raylib fidelity but to make it *a font you can pick*.
3. **Input is raw keycodes.** The gallery matches on `KEY_*` with no `[input]` section.
4. **Comments carry dev-process narrative** that dates the code — Phase references,
   regression stories, plan risk numbers.

Intended outcome: one clock instead of two, text that renders through real Godot fonts
(raylib's included, as a choice), named input actions, and comments that carry durable
domain knowledge rather than project history — without losing export purity or the
single-resolver design, both of which have cost real regressions before.

## Decisions taken (user calls this session)

| Question | Decision |
|---|---|
| Pause markers | **Keep the capability**, moved onto `ZenCanvas`. Keeps the `.cfg` `pause` grammar, the `--pause_hold=` flag and `ZenExport`'s hold expansion. |
| Fonts | **Bundle a curated set**: Source Sans 3 (raylib template default) **and** raylib's built-in 10px bitmap font, plus a mono and a display face. Font becomes a per-animation choice in a later change. |
| README SSIM 0.90 | **Drop the figure.** raylib is a historical reference, not a target. |

## Verified findings (measured this session, Godot 4.7.2 headless)

| Probe | Result |
|---|---|
| `play_section_with_markers("zen","intro_end","outro_start")` | Loops in `[0.5,1.5]`, wraps to `intro_end`, **never to 0**: `0.60 1.00 1.40 0.80 1.20 0.60 …` |
| `play_section`, `set_section`, `set_section_with_markers`, `get_section_start_time/end_time` | All present |
| Intro-once handover | `play_section("zen",0,outro_start)` then `set_section_with_markers(...)` reports section `0.5..1.5` |
| `TYPE_METHOD` track at path `".."` under a section | Still fires; `is_playing()` stays true across wraps — `ZenAnimBuilder.build` needs no structural change |
| **`seek()` outside the active section** | **Does NOT clamp.** Section `[0.5,1.5]`, `seek(0.1)` → `1.10`. See pitfall |
| `AnimationPlayer.pause()` | Does not block `advance()`; Godot has no stop-at-marker concept, so pause stays Zen-owned |
| `InputEventKey.is_action_pressed(name)` | Matches correctly; `InputMap.add_action()` works headlessly |
| Godot-authored `[input]` block | Verbose `Object(InputEventKey,…)` form, writes `physical_keycode` |
| Native vs raylib text metrics | Widths within ±7% single-line; **height 99 vs 72** at 72px (ascent 77 + descent 22); **`get_string_size()` ignores `\n`** |
| raylib template `font.ttf` | **Source Sans 3 Regular**, Adobe, **SIL OFL 1.1** → redistributable |
| raylib built-in bitmap font | `defaultFontData[512]` → 1-bit-packed 128×128 atlas; `glyphCount=224`, `charsHeight=10`, `charsDivisor=1`, `baseSize=10`; raylib is **zlib** → redistributable |
| `FontFile` API | `set_texture_image`, `set_glyph_uv_rect`, `set_glyph_size`, `set_glyph_advance`, `set_fixed_size` all present (`create_cache`/`set_ascent` are not) |

Keycodes for the generator: `ESCAPE=4194305 R=82 ENTER=4194309 KP_ENTER=4194310
SPACE=32 UP=4194320 DOWN=4194322 1=49 9=57`.

## Baseline (run this session, before any change)

```
tests/run_tests.gd       1152 checks, 0 failures
tools/compare_ripple.gd  2657 comparisons, 0 mismatches
```

`tools/test_render.tscn` (26 render checks) needs a display. Both headless commands emit
harmless `ObjectDB instances were leaked` noise on shutdown — filter with
`2>/dev/null | grep -iE "checks|comparisons"`.

## Invariants that must survive every task

Each has cost a regression before; the headers document four separate incidents where a
clock ticked during the exporter's `await` and every frame came out identical.

- `canvas.pose_looping(t, looping)` stays **the single resolver**.
- A frame stays a **pure function of (scene, t)** — `set_process(false)` until played,
  `bus.inert = true` during export, `rewind()` not `play()` for a signal's `replay`.
- Elements read properties in `_draw()`, which Godot defers — time-varying state must be
  **captured into the element by `pose()`**, never read live from `_draw()`.
- One-shot shows its authored tail; a loop blends the seam.
- Stepped props (`string`, `shape_id`) never interpolate, blend, or offset.
- Colour tracks are RGB-only; alpha rides its own scalar track.
- `crumble` hashes the **glyph index, never the clock**.

---

## Task 1 — Collapse the redundant clock

**Delete `ZenPlayer`.** Its clock is dead code in every real path; the section API covers
the one rule its header claims is inexpressible; and its three surviving live needs are
trivial (`pauses` is data, `rewind()` is a seek, `stop()` is a pause). Keeping it as a
"thin controller" would preserve a node whose only state is an array no document
populates, plus the `_zen_player()` type-scan in three files.

### Scope note: pause markers have no data behind them

No bundled document authors a pause marker — `grep "pause"` over `anims_src/*.cfg` returns
nothing, and no `anims/*.tscn` stores `pauses`. The `Player` nodes carry only
`script = ExtResource(...)`, plus `looping = false` on `game_start` and `mouse_ripple`;
`mouse_ripple_hand.tscn` has no `Player` at all. So migration loses no data, and the
capability is kept (per decision) because it is plumbed end-to-end: the parser accepts
`pause <t> [once]` (`zen_cfg_parse.gd:126-130`), `--pause_hold=` is documented, and
`VISUAL_CHECKS.md` has a manual check that tells you to add a `pause` line and re-import.

### What moves where

| From `ZenPlayer` | To |
|---|---|
| `pauses` | `@export var pauses: Array` on `ZenCanvas` (it is `doc` metadata, beside `duration`/`intro_end`) |
| `_crossed_pause`, `next_pause`, `release_pause`, `held_pause`, `_spent`, `signal paused(index)` | `ZenCanvas`, **logic ported verbatim** — this is the part the section API does not cover |
| `rewind()` | `ZenCanvas.rewind_timeline()` → `_seek_safe(0.0)` + reset pause state. Must **not** start processing |
| `stop()` | `ZenCanvas.stop_timeline()` → `_ap.pause()` + `set_process(false)` |
| `apply()` | gone — `ZenSignalBus._repose()` collapses to its existing `else` branch |
| `signal finished` | the AP's own `animation_finished` |
| `clock`, `playing`, `intro_done`, `autoplay`, `looping`, `play()`, `play_loop_body()`, `advance()`, `sample_time()`, `sec_*`, `loop_start()` | **deleted** |

### Separate `loop_smooth`'s two jobs

`loop_smooth` currently gates both the blend (`zen_element.gd:235`) and whether playback
wraps at all (`zen_canvas.gd:256-258`). Add **`loop_play`** so they separate:

| Flag | Job | Read by |
|---|---|---|
| `loop_play` | does playback wrap at `play_end()`, or hold? | `setup_animation_player`, `_process` |
| `loop_smooth` | is the seam blended? | `ZenElement.blend_begin` — **unchanged** |

Default `loop_play := loop_smooth or intro_end > 0.0` — the rule `zen_cfg_build.gd:42`
already uses for `player.looping`, so it is a move, not a new policy.

⚠️ **This changes `pause_menu`'s live behaviour.** It has a 1.51s intro with
`loop_smooth=false`, so today `_anim_time_for` returns `e` and it *freezes* at
`play_end()`; with `loop_play=true` it will loop back to `intro_end` instead. That is what
its intro exists for and what `ZenCfgBuild:42` already intended — but it is a visible
change. For zero behaviour change, use `loop_play := loop_smooth` and accept that
`pause_menu`'s intro-skip rule stays unreachable. **Recommendation: take the change.**

### Playback mechanics

```
setup_animation_player(autostart):
    ... build anim as today (unchanged) ...
    if autostart and not editor_hint:
        _intro_done = false
        if loop_play and has_intro():
            _ap.play_section(ANIM, 0.0, play_end())   # pass 1 includes the intro
        elif loop_play:
            _ap.play_section(ANIM, play_start(), play_end())
            _intro_done = true
        else:
            _ap.play_section(ANIM, 0.0, play_end())   # one-shot, outro trimmed
```

`_process` shrinks to: pause-crossing check → intro handover → `pose_looping(raw,
loop_smooth)`.

```
# Narrow to the body on the first wrap: the intro is a one-shot lead-in.
if loop_play and has_intro() and not _intro_done and raw >= play_end() - 0.0001:
    _intro_done = true
    _ap.set_section_with_markers(M_INTRO, M_OUTRO)
```

**Marker fallback:** `set_section_with_markers` needs both markers, and `_add_markers`
omits a marker whose field is 0. Use `set_section(play_start(), play_end())` when
`not anim.get_marker_names().has(M_INTRO)`. Keep `_add_markers` as-is — 0-means-absent is
correct and tested.

`loop_mode` stays `LOOP_NONE` (the *section* does the looping, not `loop_mode`) but its
header comment must be rewritten — it currently cites the false claim.

**Leave `_anim_time_for()` in place this pass.** It is pure, unit-tested, and still used
for editor scrubbing where no section is active. In the live path it becomes near-identity.

### ⚠️ Named pitfall: `seek()` does not clamp into the active section

Measured: section `[0.5,1.5]`, `seek(0.1)` → `1.10`, not `0.5`.

> **Never call `seek()` without first widening the section to contain the target time.**

One chokepoint, and nothing else in the project may call `_ap.seek()`:

```gdscript
## seek() does NOT clamp into the active section: with a section [0.5,1.5],
## seek(0.1) lands at 1.10. So widen first, always.
func _seek_safe(t: float) -> void:
    if _ap == null: return
    if t < play_start() - 0.0001:
        _ap.set_section(0.0, play_end())
        _intro_done = false
    _ap.seek(clampf(t, 0.0, play_end()), true)
```

`ZenGallery._restart()` is already safe (it re-instantiates rather than seeking) — note it
in a comment so a future "just seek to 0" refactor does not reintroduce the bug.

### Files

| File | Change |
|---|---|
| `addons/zen/runtime/zen_player.gd` | **delete** |
| `addons/zen/runtime/zen_canvas.gd` | add `loop_play`, `pauses`, `paused(index)`, `held_pause`, `_spent`, `_intro_done`, `release_pause()`, `next_pause()`, `_crossed_pause()`, `advance_pauses(t0,t1)`, `rewind_timeline()`, `stop_timeline()`, `_seek_safe()`; rewrite `setup_animation_player` + `_process`; rewrite the class header and the `live_playback` / `LOOP_NONE` comments |
| `addons/zen/runtime/zen_signal_bus.gd` | delete `_zen_player()`; replay → `canvas.rewind_timeline()`; terminal → `canvas.stop_timeline()`; simplify `_repose()` |
| `addons/zen/runtime/zen_anim_builder.gd` | header only (lines 24, 48, 56-58 assert the false claim) |
| `tools/zen_export.gd` | `pause_times(canvas)` reads `canvas.pauses`; drop the child scan. Keep the `once`-is-ignored comment |
| `addons/zen/importer/zen_cfg_build.gd` | delete the `ZenPlayer` block (31-42, 74-75); set `canvas.pauses` (keep the ascending sort + its `anim.h:536` citation) and `canvas.loop_play`; the z-order `if n == null: continue` guard stays for the bus |

### Scene migration

**Re-run the importer** rather than hand-editing — the importer is the source of truth and
`compare_ripple.gd` (2657 checks) exists to validate its output. `mouse_ripple_hand.tscn`
is hand-built with no `Player` and needs no edit (`loop_play` default `false` is already
right). Commit the re-import **separately**: it rewrites all 5 scenes and churns
`unique_id`s, so the diff is large and mechanical.

### Tests

Every assertion gets a new home — the check count should not drop.

- **Rewrite onto the canvas:** `test_player_clock` → `test_canvas_clock` (drop
  `section_len`/`loop_start`/`advance`/`play_loop_body`; the clamp assertions largely fold
  into the existing `test_trim_clamp`); `test_player_pauses`, `test_pause_across_wrap` →
  same bodies driven through a new `ZenCanvas.advance_pauses(t0, t1)` helper. **That helper
  is required** — `_crossed_pause` must stay unit-testable without a live clock, which is
  how it is tested today. `test_export_pause_source` → `c.pauses`.
  `test_player_idle_until_played` → `test_canvas_idle_until_played` — **keep it, it is the
  four-regressions guard**: `live_playback = false` in the tree ⇒ no AP playing,
  `pose_time` stays 0, `is_processing()` false. `test_imported_players_inert` →
  `test_imported_scenes_inert` (no scene has a `Player` child).
- **Add** `test_section_loops_into_body` — after handover, `get_section_start_time() ==
  intro_end` and position stays `>= play_start()`. Proves the section API replaced the
  hand-rolled wrap. Use `pause_menu` as the discriminator (intro 1.513 > body 0.473 — the
  only scene where "restart at `intro_end`" and "restart at 0" differ).
- **Add** `test_seek_stays_in_section` — pins the measured pitfall; without it the trap
  silently returns.
- **Add** `test_loop_play_separate_from_smooth` — `loop_play=true, loop_smooth=false`
  wraps while `blend_weight()` stays 0.
- **Add** `test_export_purity_no_clock` — run `ZenExport`'s disarm sequence on a live
  scene, await 3 frames, assert `pose_time` unchanged.

Update `_run()` (a flat ordered list).

**Risk: medium.** New API, live `seek()` trap. **No rendered output should change** — if a
render check moves, something is wrong.

---

## Task 2 — Text through real Godot fonts

⚠️ **Changes rendered output in `main_menu`, `pause_menu`, `game_start`.**
`mouse_ripple` and `zooming_box` are shapes only and must stay byte-identical.

The reframe: the problem was never "raylib metrics" — it was *hardcoding one font's
metrics into the renderer*. So raylib fidelity becomes a selectable font, not emulation.

### Bundle the fonts

`addons/zen/fonts/`, with a `LICENSES.md` naming each:

| Font | Source | Licence | Role |
|---|---|---|---|
| `SourceSans3-Regular.ttf` | `raylib_base_template/resources/fonts/font.ttf` (Source Sans 3 Regular, Adobe) | SIL OFL 1.1 | **project default** |
| `raylib_default_10px.tres` | generated from raylib's `defaultFontData[512]` | zlib (raylib) | pixel-exact raylib look |
| one mono face | OFL/Apache, to choose | — | code/UI captions |
| one display face | OFL/Apache, to choose | — | titles |

**Generating the raylib bitmap font** — `tools/gen_raylib_font.gd`, following the
`gen_ease_ref.gd` generator convention. The decode is fully specified in raylib's
`rtext.c:228-300`: unpack `defaultFontData[512]` (1 bit per pixel, MSB-first per uint32)
into a 128×128 image; lay glyphs out from codepoint 32, `charsDivisor=1` between them,
wrapping to a new line of `charsHeight=10` when the row overflows 128px; glyph width is
`charsWidth[i]` — **the table the project already has in `zen_text_metrics.gd`**, which is
why that constant survives as generator input rather than renderer logic. Build a
`FontFile` with `set_texture_image`, `set_glyph_uv_rect`, `set_glyph_size`,
`set_glyph_advance`, `set_fixed_size(10)` (all verified present) and save as `.tres`.

Note `FontFile` has no `set_ascent`/`set_descent` — for a fixed-size bitmap font the
height comes from `fixed_size`, which suits the `size_px`-based box rule below.

### Make the font authorable

```gdscript
@export var font: Font = null     # was: var font: Font = null (unauthorable)
```

Null falls back to the project default, so existing scenes keep working with no `.tscn`
change. `zen_cfg_build.gd::_build_text` assigns the default; the `.cfg` grammar has no
font field, so the bundled default is **project-level**, with per-element override via the
new export. Per-animation font choice is a later change (user's note).

Do **not** add a text-outline export — new scope.

### The vertical-box decision (the trap)

Native reports `height=99` for a 72px font (ascent 77 + descent 22); raylib reported a flat
72. Centring divides the measured box, so adopting `get_string_size().y` shifts every text
element ~13px at 72px — 7% of a 180px canvas.

**Keep the box as a layout rule, not a font metric:**

```
box.y = size_px * lines + LINE_SPACING * (lines - 1)
```

`size_frac` is authored as a fraction of canvas height, so `size_px` **is** the intended
visual height. Deriving the box from `ascent+descent` would make placement depend on a
font's internal padding — so swapping fonts would move the text, defeating the point of
making the font a choice. Place the baseline proportionally inside the box
(`top + size_px * ascent/(ascent+descent)`) so visual mass centres rather than the metric
box. **This is a judgement call and the highest-risk item in Task 2**; text will shift
slightly even with the box rule kept.

### The `\n` trap

**`Font.get_string_size()` ignores `\n`** — measured `"two\nlines"` → `293x99`, one line.
All three text scenes author multi-line strings. So measure per line, mirroring the
existing `_draw_runs` shape:

```gdscript
for line in text.split("\n"):
    box.x = maxf(box.x, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, ps).x)
```

Do **not** use `TextParagraph` — it brings its own line-breaking and alignment model, i.e.
a second layout authority.

### Remove / keep

**Remove:** `WIDTHS` and `glyph_width()` from the renderer path (they move into the font
generator); `_draw_glyph`'s squeeze (`cell/ink`, the `Transform2D(0, Vector2(sx,1), …)`);
`_draw_runs`' per-glyph pen loop → one `draw_string` per line.

**Keep:** `zen_text_metrics.gd` as the single measurement authority, reduced to
`BASE_SIZE`, `LINE_SPACING`, `spacing_for()` and a rewritten `measure(text, size_px,
font)`. Drop `spacing_for()` from *layout* (native kerning owns inter-glyph spacing; adding
raylib's `size/10` on top would double-space) but keep the function — crumble still needs a
per-glyph advance. Also keep: centre anchoring, `_size_px()`, the RGB×alpha×(1−crumble)
colour rule, the whole-block rotation path, and the comment that
`draw_set_transform` **replaces** rather than composes (a Godot fact that cost a render to
find).

**Crumble:** replace the advance with `font.get_string_size(ch, …).x`; keep
`rand11i(idx)` / `rand11i(idx + 977)` **verbatim** — the purity invariant.
`test_crumble_hash` needs zero edits.

### Tests

**Delete `tests/text_ref.txt`** and the comparison loop in `test_text_metrics` — 8 rows of
raylib `MeasureTextEx` output that are no longer the target. Replace with `test_text_layout`
asserting **properties, not magic numbers**, so it survives a font swap:

- `measure("", s) == Vector2.ZERO` (raylib's early-out is still right — a degenerate run
  of the formula gives negative width);
- `measure("A", s).y == s` and `measure("two\nlines", s).y == 2*s + LINE_SPACING` — **the
  `\n` regression guard**, the test that would have caught `get_string_size` being treated
  as a drop-in;
- `measure("two\nlines").x == max(measure("two").x, measure("lines").x)`;
- `measure("MM").x > measure("ii").x` — proportional metrics actually in use;
- **the centring invariant** — a `ZenText` at `pos_frac=(0.5,0.5)` on 320×180 draws its box
  centred on `(160, 90)`. Extract `ZenText.layout(t) -> {lines, size, origin}` called by
  both `_draw()` and the test, otherwise the test only re-implements the draw code.
- Add a bitmap-font case: at `fixed_size` 10 with the raylib font, widths match
  `charsWidth[]` — this pins that the generated font reproduces raylib exactly, which is
  the whole point of shipping it.

Expect roughly −21 checks from the deletions, +8 from the new test; **state the delta in
the commit message** rather than letting the number drift silently.

**`tools/test_render.gd`:** `test_crumble_renders` is the only text-sensitive check and its
observables are structurally font-independent (ink moves down, energy drops, overlap < 0.9,
horizontal centring band 0.33–0.67). Re-measure `before["n"] > 50` (letterform coverage
changes) and the `cy > before.cy + 4.0` shift; the centring band should hold and get
*tighter*. Procedure: capture current numbers **before** the change, then adjust only what
moved, recording new values as threshold calibration (not narrative).

**Risk: high, intentionally.** The only task that changes what the user sees, and the only
one where a green suite is insufficient evidence — the menus must be looked at.

---

## Task 3 — InputMap

| Action | Keys (physical) |
|---|---|
| `zen_play` | ENTER, KP_ENTER, SPACE |
| `zen_back` | ESCAPE |
| `zen_restart` | R |
| `zen_prev` | UP |
| `zen_next` | DOWN |
| `zen_signal_1` … `zen_signal_9` | 1 … 9 |

**Nine named signal actions, not a keycode range.** A range would force the handler to keep
`is InputEventKey` + raw `keycode` arithmetic — exactly the coupling being removed — and is
not rebindable. Nine actions cost nothing to author (generated in a loop) and appear in the
Input Map panel. Handler stays two lines.

**Generate the block; do not hand-edit `project.godot`.** The serialized form is one
`Object(InputEventKey, …)` per event with 16 fields. Add `tools/gen_input_map.gd`
(committed, like `gen_ease_ref.gd`) that sets
`ProjectSettings.set_setting("input/<action>", {"deadzone": 0.2, "events": [...]})` then
`ProjectSettings.save()`. Use `physical_keycode` — layout-independent, and what Godot
itself wrote, so `R` is the physical R key on AZERTY too.

Rewrite `tools/zen_gallery.gd:392-418` to an `is_action_pressed` chain in
`_unhandled_input` (not `Input` polling: the gallery has focusable `Button` children, and
`set_input_as_handled()` only means anything in an event callback). `ev.is_echo()` replaces
the `is InputEventKey` / `pressed` / `echo` guard.

**Add `test_input_actions_declared`:** all 14 actions exist, `zen_play` carries 3 events,
and a synthetic `InputEventKey` with the right `physical_keycode` reports
`is_action_pressed` true. Cheap, and catches a typo'd action name that would otherwise be a
silent dead key.

After running the generator, **diff `project.godot`** — `ProjectSettings.save()` rewrites
the whole file. Update the README hotkey list to say the keys are now rebindable actions.

**Risk: low.** No rendered change.

---

## Task 4 — Comment and doc cleanup

### The editorial rule

Two questions per comment. It stays only if it answers (1).

> **(1) KEEP — "a reader changing this code needs this to not break it."**
> A constraint, invariant, unit convention, measured engine behaviour, or provenance
> citation. Present tense, about the code as it is.
>
> **(2) DELETE — "this is how we got here."**
> Project history, bug narrative, who decided what and when, what an earlier version did,
> which test covers which line, phase/plan numbering. Recognisable by past tense about the
> project, or process voice.

**Greppable deletion triggers:** `Phase \d`; `which is exactly what it (did|does)`;
`hence test_`; `the plan's risk \d`; `an earlier (design note|version)`; `REGRESSION:`;
`was caught by`; `it cost a render`; `decided \d{4}-`; `user call`; `used to`;
`previously`; `Before this`; `the port previously failed`.

**Named keep-list** (so a reviewer can object before the edit): the unit rule
(`zen_element.gd:9-16`, verbatim); why easing is **incoming** and why `ZenSampler` owns
interpolation; why colour is RGB-only; why stepped props never interpolate; the 320×180 /
`unit abs` rationale; export-purity invariants (**keep the rule, delete the "78 identical
frames" story**); `draw_set_transform` replaces rather than composes; why Zen signal names
cannot be `signal` keywords and why user signals do not survive `pack()`; **all 74
`anim.c:NNN`-style citations** — provenance for a port, the highest-value comment class
here, not narrative; and the newly measured facts (`seek()` does not clamp,
`get_string_size()` ignores `\n`).

**The ambiguous middle — rewrite, don't delete.** Several headers are a true invariant
wearing a regression story. `zen_canvas.gd:139-146` becomes: *"The exporter turns this off:
it drives `pose_looping()` from its own explicit frame list, and any clock ticking during
its `await` would re-pose every frame to the same instant."* Same information, no history.
Apply to `zen_player.gd:27-32` (moot — deleted), `zen_signal_bus.gd:68-74`,
`zen_export.gd:150-158`, `zen_element.gd:265-275`, `zen_canvas.gd:61-68`.

### The 16 Phase references

| File:line | Disposition |
|---|---|
| `zen_canvas.gd:146` | delete (part of the Task 1 rewrite) |
| `zen_player.gd:110` | deleted with the file |
| `zen_element.gd:270` | keep the `_draw()`-is-deferred rule, drop the "Phase 4 loop-blend bug" attribution |
| `zen_signal_bus.gd:36` | → "so a caller can `await bus.terminal_finished`" |
| `zen_signal_bus.gd:275,280` | → "a stage running several copies of one document" |
| `zen_signals.gd:13` | → "a stage running one document three times at once needs exactly this" |
| `zen_cfg_build.gd:9` | obsolete — text *is* implemented; rewrite the deferral note |
| `zen_cfg_import.gd:14` | delete the "when text lands in Phase 3" clause |
| `zen_export.gd:155` | delete the parenthetical; keep the purity invariant above it |
| `test_render.gd:187` | → "The signal override, IN PIXELS." |
| `test_render.gd:579` | rewrite without the regression story **and** without `ZenPlayer` |
| `build_ripple.gd:5,8` | → "hand-written so the export pipeline is validated against data that does not depend on the importer; `compare_ripple.gd` diffs the two" |
| `signal_shots.gd:3` | → "Visual evidence for the signal override" |
| `run_tests.gd:688` | → "Intro/loop/outro trim, smooth-loop blend, pause markers." |

### Headers invalidated by Tasks 1-2 (correctness, not style)

`zen_player.gd` (deleted); `zen_canvas.gd` (the false "restarts at 0" at line 255);
`zen_anim_builder.gd` (lines 24, 48, 56-58 — `LOOP_NONE`'s justification becomes "the
section API does the looping, not `loop_mode`"); `zen_text.gd` / `zen_text_metrics.gd` (the
raylib-table rationale is removed code → replace with the box rule, the `\n` trap, and the
font-choice design). `zen_sampler.gd` / `zen_easing.gd` / `zen_element.gd` are the heaviest
but contain no invalidated claims — trim narrative only. **Keep `zen_easing.gd`'s
`transition` vs `Tween.interpolate_value` lesson**: a reader will ask why `transition` is
not used, and it is the same trap this plan just found in the clock.

Do these headers **as part of Tasks 1 and 2**, not a third pass over the same lines.

### Docs

The false looping claim appears in **5 places**: `README.md:204`, `README.md:221`,
`zen_canvas.gd:255`, `zen_anim_builder.gd:57`, `zen_player.gd:8`. Correcting
`README.md:203-204` and `218-226` is the most important doc edit here — it is the sentence
that caused the design error. New text: the intro-skip rule **is** expressible;
`play_section_with_markers` loops strictly inside the marker range and wraps to
`intro_end` (added in 4.4); `Animation.loop_mode` is what cannot express it. Add the
`seek()`-does-not-clamp caveat.

Also in `README.md`: replace the `| Phase | State |` table with a plain "what works" list;
drop the `**Phase 5 complete**` opener; **drop the SSIM 0.90 sentence** (per decision) and
state that the raylib render is a historical reference, not a target; rewrite the
"Text layout is raylib's" paragraph for Task 2 including the bundled fonts; keep
`--pause_hold=` in the flags table; reword item 4 of the "five bugs only a rendered pixel
could find" list, which references `ZenPlayer.play()`.

`VISUAL_CHECKS.md` is organised entirely by Phase, so it needs **restructuring by subject**,
not find-and-replace: ripple export / importer vs hand-built / the two menus / alpha /
frame alignment / loop seam, intro trim, pauses / signals in pixels. Collapse the
run-history header (lines 3, 7) to one "last run" line. Keep §154 "A pause marker freezes
the export" — it becomes the documented way to exercise the kept capability. Add a note
that text rendering changed, so stored comparison artifacts predating it are not
byte-comparable.

**Measurement target:** runtime+importer is 3217 lines / 1011 comment (31%). Deleting
`zen_player.gd` plus the narrative trim should land near 24-26% — but **do not treat the
percentage as the goal.** A reviewer should agree with every deletion under the rule above;
a comment deleted to hit a number is the failure mode.

**Risk: low mechanically, medium editorially.** Separate commit, per file, no code changes
in it — so the diff reviews as pure prose.

---

## Execution order

Ordered to keep the suite green as long as possible. Do not proceed on a red step.

**0. Baseline.** Record 1152 / 2657 / 26. Export a reference artifact to diff later:
`--anim=mouse_ripple --fmt=png --scale=2`.

**1. Task 3 (InputMap).** Independent, zero render impact — banks a win and proves the
harness. Generator, run once, diff `project.godot`, rewrite the handler, add
`test_input_actions_declared`. → green at 1152+N. Manual: F5, every key.

**2. Task 1a — canvas gains the clock, `ZenPlayer` still present.** Add `loop_play`,
`pauses`, the pause machinery, `advance_pauses()`, `rewind_timeline()`, `stop_timeline()`,
`_seek_safe()`; rewrite `setup_animation_player` / `_process`; add the three new tests. Do
not touch the scenes. → green, with `test_player_*` still passing against the live class.

**3. Task 1b — switch consumers.** `zen_signal_bus.gd`, `zen_export.gd::pause_times`,
`zen_cfg_build.gd`. Rewrite the `test_player_*` family onto the canvas. → green.

**4. Task 1c — re-import the 5 scenes.** Run the importer, then `compare_ripple.gd`
(2657) **first** — it is the importer's own regression test. Then `dump_scene.gd` on each
of the 5. **Commit separately.**

**5. Task 1d — delete `zen_player.gd`.** Grep for `ZenPlayer` and confirm only comments
remain. → full suite incl. **`test_render` with a display** — where a clock regression
shows as identical frames.

**6. Export smoke test — the four-regressions guard. Do not skip.**
```
./Godot_v4.7.2-stable_linux.x86_64 --path . --rendering-driver opengl3 \
    tools/export_scene.tscn -- --anim=main_menu --fps=30 --fmt=png --scale=2
md5sum exports/main_menu/*.png | awk '{print $1}' | sort -u | wc -l
```
Must be ≈ the frame count. **`1` is the regression.** Also re-export `mouse_ripple` and
diff against step 0 — should be byte-identical.

**7. Task 2 — fonts and native text.** Generate the raylib bitmap font, add the bundled
set + `LICENSES.md`, rewrite `zen_text_metrics.gd` (`measure(text, size_px, font)`, per-line
`\n` loop, `box.y = size_px*lines + LINE_SPACING*(lines-1)`), rewrite `zen_text.gd`
(`@export var font`, drop the squeeze, `draw_string` per line, native advances in crumble),
extract `layout()`, update `_build_text`. Delete `tests/text_ref.txt`; replace
`test_text_metrics` with `test_text_layout`. → green at the new count (state the delta);
then **`test_render` with a display** and re-calibrate the two crumble tolerances.

**8. Visual sign-off — RENDERED OUTPUT CHANGED.** Human step; no test substitutes.
```
--anim=main_menu  --fps=30 --fmt=webm --scale=4
--anim=pause_menu --fps=60 --fmt=webm --scale=2 --intro
--anim=game_start --fps=30 --fmt=webm --scale=4
```
Check: text centred horizontally **and vertically**; `\n` still breaks; crumble still
scatters near the title; the raylib bitmap font reproduces the original look when selected;
`pause_menu`'s new loop behaviour is wanted.

**9. Task 4 — comments and docs.** Last, so it never blocks a green suite and describes the
code as it finally is. One commit per file.

**Final verification:**
```
./Godot_v4.7.2-stable_linux.x86_64 --headless --path . --script res://tests/run_tests.gd
./Godot_v4.7.2-stable_linux.x86_64 --path . --rendering-driver opengl3 tools/test_render.tscn
./Godot_v4.7.2-stable_linux.x86_64 --headless --path . --script res://tools/compare_ripple.gd
for a in main_menu pause_menu mouse_ripple zooming_box game_start; do
  ./Godot_v4.7.2-stable_linux.x86_64 --headless --path . \
      --script res://tools/dump_scene.gd -- $a
done
./Godot_v4.7.2-stable_linux.x86_64 --path .        # F5 gallery: every key, every scene
grep -rn "Phase" --include=*.gd --include=*.md .   # must return nothing
grep -rn "ZenPlayer\|zen_player" --include=*.gd --include=*.md --include=*.tscn .
```

## Risk summary

| Step | Risk | Changes rendered output |
|---|---|---|
| 1 InputMap | low | no |
| 2 section API | **medium** — new API, `seek()` trap | no (verify) |
| 3 switch consumers | low | no |
| 4 re-import | medium — large mechanical diff, id churn | no (gated by `compare_ripple`) |
| 5-6 delete + export | **high if unverified** — four prior regressions in this exact shape | no (gated by the hash check) |
| 7-8 fonts / text | **high, intentional** — vertical box is a judgement call, `\n` is a measured trap | **yes: `main_menu`, `pause_menu`, `game_start`** |
| 9 comments | low mechanically, medium editorially | no |

## Critical files

- `addons/zen/runtime/zen_canvas.gd` — absorbs the clock
- `addons/zen/runtime/zen_player.gd` — deleted
- `addons/zen/runtime/zen_text.gd`, `zen_text_metrics.gd` — native text
- `addons/zen/importer/zen_cfg_build.gd` — stops building a player, assigns the font
- `addons/zen/runtime/zen_signal_bus.gd` — drops `_zen_player()`
- `tools/zen_gallery.gd` — InputMap actions
- `tools/zen_export.gd` — `pause_times` reads the canvas
- `tests/run_tests.gd` — test moves, additions, deletions
- `project.godot` — generated `[input]` block
- new: `tools/gen_input_map.gd`, `tools/gen_raylib_font.gd`, `addons/zen/fonts/`
