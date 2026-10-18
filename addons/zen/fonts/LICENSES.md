# Bundled fonts

| Font | Source | Licence |
|---|---|---|
| `SourceSans3-Regular.ttf` | `raylib_base_template/resources/fonts/font.ttf` (Source Sans 3 Regular, © 2021 Adobe) | SIL Open Font License 1.1 - redistributable, see https://scripts.sil.org/OFL |

This is the project's default text font (`ZenText.font` falls back to it when
unset). It was raylib's own bundled default in the reference project, kept
here as the visual starting point rather than switched to something else.

A pixel-exact raylib bitmap-font option and separate mono/display faces were
considered (docs/plans/godot-integration.md Task 2) but not built in this
pass - see docs/plans/session-2026-10-19-log.md for why. Per-animation font
choice is a later change; today the font is a project-level default with a
per-element override (`ZenText.font`).
