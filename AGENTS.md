# Repository Guidelines

## Project Overview

Tamaki₃ is a chart editor for a ring-judgement rhythm game, built with Godot 4.7.2 (the version pinned in CI). `project.godot` launches `charter/main.tscn`. User docs live in `docs/` (Chinese); game and editor design documents live in `环 GameDesign/`.

## Architecture

- `core/`: chart model, timing and boundary math, judgement math, validation, serialization (`chart_io.gd`, `.lbp`), and import conversion (osu!, Simai).
- `charter/`: editor UI, canvas, inspector, ring editor, 3D preview, and playtest.

The editor, the preview, and the playtest must agree exactly on where a note sits and how it is judged. Implement boundary, timing, and judgement logic once in `core/` and call it from all three. Do not re-derive it locally.

Other directories:

- `tests/`: headless suites, audits, and benchmarks.
- `charts/`: the sample chart and the online chart library indexes (`adx_*.json`).
- `audio/`: click tracks and hit sounds.
- `design/`: visual references.
- `addons/ffmpeg/` and `tools/ffmpeg/`: vendored third-party binaries. `addons/ffmpeg/` is the EIRTeam.FFmpeg GDExtension that decodes BGA video directly. `tools/ffmpeg/` holds the gzip-compressed ffmpeg CLI used for transcoding and audio analysis. Neither has macOS builds.

## Commands

Run from the repository root. `godot` means a Godot 4.7.2 binary.

```bash
godot --headless --path . --import    # required once before headless runs (.godot/ is not committed)
godot --path .                        # launch the editor

# The required CI `tests` job runs all five suites below:
godot --headless --path . --script res://tests/test_runner.gd      # main suite
godot --headless --path . --script res://tests/path_judgement.gd
godot --headless --path . --script res://tests/alpha_commands.gd
godot --headless --path . --script res://tests/sfx_playback.gd
godot --headless --path . res://tests/replay_integration.tscn
```

Every suite exits non-zero on failure, so trust the exit code rather than skimming the output.

ffmpeg-dependent cases (tempo adjustment, transcoding) are skipped silently when ffmpeg is unavailable. A skip is not a pass. On Linux and Windows, `MediaIO` uses the bundled `tools/ffmpeg/`. On macOS, ffmpeg must be on `PATH`.

`docs/testing.md` describes the coverage of each suite, the perf gate, and the known rendering and UI cost pitfalls.

## Testing

- Add main-suite cases as `test_<behavior>` functions in `tests/test_runner.gd`, and register each one in the `tests` list in `_initialize()`. An unregistered case never runs.
- For a chart format change, cover the save → load round trip and the loading of older charts.
- For a change to rendering, the inspector, or per-frame code, run `tests/perf_harness.tscn` against `tests/perf_baseline.json`; `docs/testing.md` has the command. The CI `perf` job does not block merges, so a regression there can slip through unnoticed.

## Code Style

- Indent GDScript with tabs.
- Name files, functions, and variables in `snake_case`, classes in `PascalCase`, and constants in `UPPER_SNAKE_CASE`.
- Type annotations should match the surrounding code.
- Commit the Godot-generated `.uid` sidecar with each new script.
- Keep `.godot/`, `*.import`, and exported videos and builds out of commits. `.gitignore` already covers them.

## Commits and Pull Requests

- Commit subjects use Conventional Commits types with an optional scope. The description may be in Chinese or English. Examples: `fix(chart-io): Limit 区域保留 shape/polarity`, `perf: reduce editor and playtest frame stalls`.
- Update the relevant page in `docs/` when user-visible behavior changes.
- A PR should summarize the behavior change, state how it was verified (which suites ran, and whether ffmpeg cases were skipped), and link related issues.
- For visible UI changes, include screenshots. If you cannot capture them, say so in the PR so a human can add them.
- PRs into `main` must pass the `tests` job.
