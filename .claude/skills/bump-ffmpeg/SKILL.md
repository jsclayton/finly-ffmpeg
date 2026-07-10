---
name: bump-ffmpeg
description: Bump the vendored FFmpeg version safely — two lines, a rebuild, and the full oracle pass. Use for FFmpeg security releases or version upgrades.
---

# Bump FFmpeg

The update path is deliberately two lines in `scripts/config.sh`:

```
FFMPEG_VERSION=<new>
FFMPEG_SHA256=<sha256 of the release tarball>
```

Then:

```bash
./build.sh --clean          # fetch → 6-arch cross-compile → 4 xcframeworks → LGPL bundle
./build.sh --smoke          # link + run a probe on the simulator
```

Run the build in the foreground; it is long but must not be abandoned.

## After the build — the full oracle pass, no shortcuts

1. `/run-tests` — full suite, audit skips.
2. `/validate-hls` — all dumped streams, 0 MUST-fix expected.
3. Diff behavior, not just green: the traps in `CLAUDE.md` cite `vendor/ffmpeg-*/` file:line
   (movenc strictness gates, matroskadec timestamp assignment, `mlp` parser `frame_size`,
   dovi_rpu machinery). Spot-check that the cited behavior still exists at the new version —
   `ffmpeg-video-expert` with the specific citations is the right tool. A silently moved gate
   is exactly how a bump ships a regression the suite can't see.

## Patches (once `scripts/patches/` exists)

The Dolby Vision P7→8.1 conversion (`docs/design/dolby-vision.md`) adds a patched BSF applied
by the build script. A bump that breaks the patch must **fail loudly at build time** — never
skip a hunk and continue. Rebase the patch, rebuild, and re-run the DV validation (converted
RPUs diffed against dovi_tool on the same source) before calling the bump done.

## Bookkeeping

- Update the version in `README.md` if it's stated there.
- Vendored source lands under `vendor/ffmpeg-<version>/`; the old tree goes away in the same
  commit (the repo carries exactly one).
