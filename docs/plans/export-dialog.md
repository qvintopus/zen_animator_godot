# In-app Export screen with the full original Zen option set

## Context

Export used to be CLI-only (`tools/export_scene.tscn --anim= --fmt= --fps= --scale=
--quality= --intro --transparent --pause_hold=`), and the only in-app export control was a
scale number on the Options screen with a hardcoded `320x180` resolution readout. The
original C/raylib Zen Editor (`../raylib_base_template/src/anim_editor_zen/zen_export.c`)
had a full **File > Export...** modal: multi-animation chaining, AVI, named output, a GIF
alpha cutout, a separate GIF palette-quality scale, a size estimate, and progress/cancel.

This adds an in-app Export screen exposing every option the original had, driven by one
engine that the CLI also uses. **Options = defaults for new animations** (font only now);
**Export = everything export-related** (scale moved there).

## Decisions taken (user calls this session)

| Question | Decision |
|---|---|
| Dialog controls | **Native Godot controls** (`OptionButton`/`HSlider`/`SpinBox`/`CheckBox`/`LineEdit`), not the Options screen's custom UP/DOWN axis — too many heterogeneous rows for one axis. |
| Chaining a mismatched canvas | **Reject it.** The picker shows a mismatched entry disabled with a tooltip; there is no single right answer for mixing sizes (letterbox and stretch are both wrong in different ways). |
| CLI vs dialog | **Fold the CLI onto the new Job API.** `export_scene.gd` becomes a thin caller; there is exactly one encoder loop in the codebase. |
| Entry points | `E` opens the dialog from the gallery or from playback. `Ctrl+E` tags the current animation onto an export queue **without** opening the dialog. |
| Scale range | Stays **1..8** (deeper than the C's 4x cap — the design canvas is small). |

## Task 1 — Engine: chain, AVI, cutout, estimate, Job/cancel

**File:** `tools/zen_export.gd`

- `MAX_CHAIN := 8`; `Settings` gained `quality_gif`, `cutout`, `join_pause`.
- `crf()`, `ffmpeg_available()`, `needs_ffmpeg()`, `human_size()`, `estimate_bytes()` —
  calibrated port of the C's `EstimateBytes()`/`EstimateFrames()` (scale^1.09 for LZW
  formats, scale^0.6 for H.264, a 0.1x discount for held frames on differencing codecs,
  exact `w*h*frames*3` for AVI).
- `cutout()` — snaps GIF alpha to 0/255 at **native canvas size, before the upscale**
  (nearest-neighbour only duplicates pixels, so the result is identical at ~16x less work
  at scale 4).
- `ChainSegment` + `plan_chain(links, s, join_pause) -> {ok, error, segments}` — resolves a
  chain, refusing a `design_size` mismatch **before any encoder opens**, naming the
  offending link and size.
- `Job` (`RefCounted`, `progress`/`finished` signals, `cancel_requested`) — the single
  encoder loop (ffmpeg pipe or per-frame PNG). No threading: `_frame()`'s
  `await RenderingServer.frame_post_draw` already yields the whole engine tick, so a
  progress repaint and the cancel check come free once per frame.
- `run()` kept its old signature, now a one-link `plan_chain()` + `Job`.
- `build_link(host, name, transparent) -> {canvas, sub}` — the **one** place a chain link's
  `ZenCanvas`/`SubViewport` pair is built, shared by the CLI and the dialog so a pose/size
  difference between the two cannot be introduced by accident.

**Tests:** `test_chain_frame_plan`, `test_chain_rejects_size_mismatch`,
`test_single_link_plan_matches_legacy`, `test_estimate_bytes_shape`,
`test_cutout_snaps_alpha`, `test_ffmpeg_args_per_format`, `test_job_cancel_png`.

**Risk realized:** none — the single-link path stayed byte-identical (verified against a
pre-change webm/avi/gif/png export on a real display).

## Task 2 — Fold the CLI onto the Job API

**File:** `tools/export_scene.gd`

Replaced the direct `ZenExport.run()` call with `plan_chain()` + `Job`. New flags:
`--chain=a,b,c` (overrides `--anim=`), `--name=`, `--out=`, `--cutout=`, `--quality_gif=`,
`--join_pause`, `--fmt=avi`. Per-link `SubViewport` construction moved out of this file
entirely, into `ZenExport.build_link()` (Task 1), so the CLI and the dialog share it rather
than each keeping their own copy.

**Verified:** the exact pre-change command (`--anim=mouse_ripple --fps=60 --fmt=webm
--scale=2`) still produces a working file; new flags exercised individually
(`--fmt=avi`, `--chain=mouse_ripple,mouse_ripple_hand`, `--fmt=gif --transparent
--cutout=64`).

## Task 3 — Settings split: Options keeps creation defaults, Export owns export

**Files:** `addons/zen/runtime/zen_settings.gd`, `tools/zen_options.gd` + `.tscn`,
`tools/gen_input_map.gd`, `project.godot`

- `ZenSettings.export_defaults()` / `set_export_defaults()` — one `Dictionary`-valued
  `"export"` key (`EXPORT_DEFAULTS` constant for the shape), merged over saved values on
  load so an older `.cfg` with no `export` key loads clean.
- `ZenOptions` lost the scale row, the resolution label, and `CANVAS_SIZE` — deleted, not
  fixed, since the Export dialog now shows each document's *real* resolution.
- `gen_input_map.gd` dropped `zen_scale_down`/`zen_scale_up`, added `zen_export` (`E`) and
  `zen_export_queue` (`Ctrl+E`). Regenerating `project.godot` needed an explicit `RETIRED`
  clear step first — `ProjectSettings.set_setting()` alone does not delete a key that was
  already loaded from disk, it just writes the old value straight back out.

## Task 4 — Input actions, gallery wiring, export queue

**File:** `tools/zen_gallery.gd`

- `View.EXPORT`, `_open_export()`/`_close_export()` — the same overlay-child pattern as
  Options, but remembers whether it was opened from `GALLERY` or `PLAYING` so Close returns
  to the right place.
- `_export_queue: Array[String]`, built by `Ctrl+E` via `_queue_current()`: capped at
  `ZenExport.MAX_CHAIN`, refuses a `design_size` that does not match the queue's first
  entry (status line explains why), duplicates allowed.
- `zen_export_queue` is checked **before** `zen_export` in `_unhandled_input`, with an extra
  `ctrl_pressed` guard on the plain branch — belt and braces, since Godot's own modifier-
  exact action matching already keeps `Ctrl+E` from also firing `zen_export`.
- `_describe()` gained a `pauses` count in its metadata (pause-marker total), used by the
  dialog's pause-hold enable rule.

## Task 5/6 — Dialog UI and job wiring (done together)

**New files:** `tools/zen_export_dialog.gd`, `tools/zen_export_dialog.tscn`

Built as one `ZenExportDialog extends Control` with the entire control tree constructed in
`_ready()` rather than hand-authored in the `.tscn` — ~15 heterogeneous rows with live
enable/disable rules are far less brittle as code than as a node-path tree every `@onready`
has to match exactly; the `.tscn` is just the script-bearing root.

Rows: chain list (reorder/remove, `+ Add animation` popup with mismatched-size entries
disabled-not-hidden and tooltipped), format picker (ffmpeg-gated items disabled with a
hint when `ffmpeg_available()` is false), name + live resolved-path preview, Folder button,
1-8x scale buttons (write through to `ZenSettings.set_export_scale()`), fps (re-capped per
format, with a GIF centisecond-quantization note), show-intro (disabled unless some link
has an intro), pause-hold (disabled unless the chain has pause markers or more than one
link), pause-between-animations (hidden for a single link), frame/duration readout,
per-format quality/transparent/cutout rows, a three-tier size estimate label, progress bar,
status line, and Export/Cancel + Close.

**The deliberate API-gap resolution flagged after Task 1:** the chain editor's live preview
(frame count, held count, size estimate) is computed straight from the gallery's already-
scanned `_entries` metadata (`play_start`/`play_end`/`intro_end`/`pauses`/`design`) — no
`ZenCanvas` is instantiated while the chain is being edited. Real instances
(`ZenExport.build_link()`) are built exactly once, when Export is pressed, and freed in
`_on_job_finished()`/on a failed start. The preview's held-frame count assumes every
authored pause marker falls inside the played range (true for every current animation);
`plan_chain()` recomputes the exact figure from live pause times when the job actually
runs, so the preview can only be off before a real pause-time check happens, never the
actual output.

Every control's change handler routes through one `_refresh()` that recomputes the
resolution line, the frame/held counts, the fps-quantization note, every per-format row's
visibility, the size estimate, and the freeze-during-run state. A running job disables
every setting control (the frame plan and encoder args are committed at job start) and
flips Export into Cancel; `Job.run()` is called without `await` since it returns at its
first internal `await` and resumes itself each frame, so holding the call would block the
dialog's own input/progress updates instead of leaving it responsive. On success,
`ZenSettings.set_export_defaults()` persists every field.

**Tests:** `test_export_dialog_preview` (headless) pins the metadata-only preview
arithmetic for a single link and a two-link chain with a join and a pause marker, plus the
default-name and resolved-path logic.

**Verified on a real display:** the dialog drove a real export through to a working file,
and cancelling mid-export left no partial file (same `JobCleanup` guarantee the CLI gets).

## Verification run this session

1. `godot --headless --script tests/run_tests.gd` — 1071 → 1131 checks across the whole
   feature (+60), 0 failures.
2. CLI regression (`--anim=mouse_ripple --fps=60 --fmt=webm --scale=2`) byte-for-byte same
   shape of output as before the refactor.
3. New CLI surface: one `--fmt=avi` run (byte-exact against `w*h*frames*3` plus container
   header), one `--chain=a,b` run, one `--fmt=gif --transparent --cutout=64` run.
4. Dialog driven headless (open/refresh/chain-edit) and on a real display (a full export,
   and a mid-export cancel with no partial file left).
5. A legacy `user://zen_settings.cfg` with no `export` key loads clean through
   `export_defaults()`.

**Remaining for a human:** `VISUAL_CHECKS.md`'s new section — `E`/`Ctrl+E` from the actual
gallery UI with mouse/keyboard, the `+ Add animation` popup's search and disabled-row
tooltip, and eyeballing the size estimate/progress bar during a real multi-minute export.
