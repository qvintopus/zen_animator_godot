# Effects: guided Extract / Insert

**Status (2026-10-26):** done. Replaces [clip-library.md](clip-library.md)'s clipboard.

## Why

Copy/paste had grown into many controls for one idea: Ctrl+C/V/Shift+V, three ruler-menu
paste items, merge-onto, relative mode, and a 5-button Library panel over a second store
(`library/`) that duplicated `anims/effects`. What is wanted is two flows: take part of an
animation out as an *effect*, and put an effect into an animation.

## Decisions

- An effect is an **ordinary animation**. Extract saves into `effects/` by default, and
  Insert can pick any animation, grouped by folder. `library/` and `tools/gen_library.gd`
  are gone; `swing_in` and `orbit_symbols` became `anims/effects/fx_swing_in` and `fx_orbit`.
- **No clipboard.** `ZenClipOps` is only the insert engine:
  `paste(dest, fx, t, prefix)` plus `names_for` for the preview.
- **Extract is a guide over plain editing** (`tools/zen_effects.gd`): save, copy
  (`ZenSceneOps.duplicate_scene(from, to, folder)`, with signals optionally cut by
  `ZenSignalOps.remove_all`), keep elements, delete keys on the timeline, trim, save.
- **Insert** asks where (the playhead, scrubbed live from the dialog, or a second), how
  fast (a length ratio, applied with `ZenDocOps.retime` on the opened effect, never on
  the file) and whether to prefix the names. It is one undo step.
- **Edit > Options**: Length (with or without scaling keys) and Trim
  (`ZenDocOps.key_span` / `trim`). Empty time is time where no value changes: auto-key's
  t=0 pose pin and other holds do not count as movement.
- Every new button is a `ZenTipButton` (`ZenUI.bar_button`), every dialog control has a
  tooltip, and the menu bar is built from ZenUI actions, so each item carries one.
  `ZenUI.popup_fill` now handles submenus.

## Tests

`test_clip_ops` (insert timing, eases, prefix, ratio, text pool), `test_doc_retime_trim`,
and `test_scene_editor_effects` (Length, Extract end to end, Insert, undo).
