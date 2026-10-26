# Clip length, and a library of reusable clips

**Status (2026-10-26): superseded** by [effects-flow.md](effects-flow.md). The clipboard
(Ctrl+C/V/Shift+V), merge-onto, relative paste, the Library panel and `library/` were
removed in favour of guided Extract / Insert of ordinary effect animations. The length
fix (`00c1dfb`) stays; retime landed as `ZenDocOps.retime` (Edit > Options > Length).

## Context

Two asks: (1) the length of an animation must be freely changeable, (2) a selection of
elements, or of just some of their keys, must be savable into a library and pasted into
other animations as a template - e.g. the book icon swinging in until it rests
(`ma_prog_02_coding`), or the symbols swirling around the white ball (`fangs_test`).

## 1. Length

**Finding.** `duration` was already editable (Document panel, `ZenDocOps.set_duration`),
but lengthening a clip did not work: every scene stores an `outro_start` marker at its
end, so after lengthening it sat at the old end and read as a real outro. The new tail
was neither played nor exported. **Fixed** (`00c1dfb`): an outro at the old end follows
the end; a deliberately placed outro stays put. Shortening already clamped.

Still to do, in this order:

| Step | What |
|---|---|
| 1a | Drag the end of the timeline ruler to set the length (a handle at `duration`), plus right-click "length ends here". The spinbox is hidden in a summoned panel. |
| 1b | `ZenDocOps.retime(canvas, factor)`: scale every key time, marker and pause. Keys beyond a shortened end are kept, not deleted. Offered as "stretch keys to fit" next to the spinbox. |
| 1c | Keys past `duration` are drawn dimmed on the timeline, so shortening is never silent data loss. |

## 2. Clip library

### Model

A `ZenClip` resource (`library/<name>.tres`), self-contained and engine-version agnostic:

- `elements`: per element, its type and static props (what `ZenElemFactory` already
  builds), with the **text stored as a plain string**, not a pool index.
- `tracks`: per element and prop, the key model `ZenKeyOps._read` already produces
  (time, value, bezier handles, ease), **times rebased so the first copied key is 0**.
- `length`, `name`, and the source scene (informational).

No second key format: copy = `_read` on the selected keys, paste = `_write`.

### Copy

Selection already exists (elements panel, key box-select in the timeline). Two modes:

- **Elements**: whole element(s), every track. Covers the swirling symbols.
- **Keys**: only the selected keys (or the box-selected time range) of the selected
  element(s), e.g. just the book's swing-in, not its later fade. Covers the swing.

### Paste

At the playhead. Choices on the paste dialog:

- **New elements** (default; names de-duplicated, keys shifted to the playhead), or
  **onto the selected element** (merge the keys into it, so one swing-in can be applied
  to any icon).
- **Values: absolute or relative** to the target's pose at the paste time. Relative is what
  makes "swing in to wherever this icon rests" reusable.
- Text interns into the target's `ZenStrings` pool on paste (the pool stays the one place
  text lives).
- Signals are not carried in v1; a clip with signal-bound props pastes without them and says so.

### UI

- Ctrl+C / Ctrl+V keep the in-scene clipboard (same scene or between open scenes).
- "Save selection to library..." (name prompt) writes the `.tres`; a **Library** panel
  (summoned, next in the numbered list) lists clips with a looping preview, double-click
  pastes.
- The gallery gets a third accordion section, **clips**, to browse and delete.

### Order

1. `ZenClip` + `ZenClipOps.copy/paste` (headless, tested: round trip preserves values,
   handles, eases, text; rebase; relative paste).
2. Ctrl+C/V in the editor.
3. Save-to-library + Library panel.
4. Gallery section.

## 3. Showcase animations for the effects

Each is a small scene in `anims/effects/`, built to be copied into the library:

| Effect | Notes |
|---|---|
| `fx_swing_in` | the book swing-in, extracted from `ma_prog_02_coding` |
| `fx_orbit` | the swirling symbols around a ball, from `fangs_test` |
| `fx_ring_pulse` | expanding, fading ring (loop) |
| `fx_sparkle_burst` | radial burst of small shapes, scale-down and fade |
| `fx_shake` | decaying jitter on a shape |
| `fx_wobble` | rotate and scale settle, like an elastic pop |

The first two are extracted once copy works (step 1 above proves it on real data); the
rest can be authored with the current editor and are independent of the library.
