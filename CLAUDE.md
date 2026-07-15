# finly-ffmpeg

The **FFmpeg build pipeline only** — a repeatable cross-compile of FFmpeg for
Apple platforms, packaged as dynamic-framework xcframeworks plus an LGPL bundle.
There is **no engine, app, or server code here, and none should ever be added**:
the consuming demux/remux engine lives in a separate private repository and
depends on tagged releases of this repo.

## Build

```bash
./build.sh            # fetch → 6-arch cross-compile → 4 xcframeworks → LGPL bundle
./build.sh --smoke    # + link/run a probe on the iOS simulator (needs a working sim)
```

Everything downstream reads its knobs from `scripts/config.sh`. Outputs land
under `artifacts/`.

## Bumping FFmpeg

Two lines in `scripts/config.sh` — `FFMPEG_VERSION` + `FFMPEG_SHA256` — then
re-run `./build.sh`. **Re-verify patches 0001–0004 apply on every bump** (their
struct paths and hook sites are version-specific). The `bump-ffmpeg` skill walks
the full procedure.

## The vendored patches (load-bearing — this is a decoder-less build)

- **0001** — HEVC parser fills `color_trc`/`primaries`/`colorspace`/`range` from
  the SPS VUI. Without it a decoder-less build reads no colour and HDR is
  declared SDR.
- **0002** — `matroskadec` runs HEVC header parsing so 0001 takes effect for MKV.
- **0003** — same for the MP4/`mov` path.
- **0004** — lifts HEVC mastering-display + content-light SEI into
  `coded_side_data` so `movenc` writes `mdcv`/`clli` on a stream-copy.

0002/0003 enable HEVC parsing via `AVSTREAM_PARSE_HEADERS`, which does **not**
repack packets and does **not** set `has_b_frames` — any change there MUST
preserve both properties, or B-frame composition timing breaks downstream.

## Hard rules

- **No GPL, no non-free** components (no `--enable-gpl`, no `libfdk_aac`).
- **No video encoders or decoders, ever.** Video is stream-copied by consumers.
- **Keep the repo generic:** no product names, no private paths or hostnames, no
  media-library statistics — in code, comments, or commit messages.

## Shell gotchas

- Run scripts as `bash script.sh`. Never `source scripts/config.sh` into an
  interactive zsh (it sets `set -euo pipefail`).

## Releases

Fire from `v*` tags (or manual `workflow_dispatch`) — see
`.github/workflows/ci.yml`. A full 6-arch cross-compile is too heavy for
per-push CI, so day-to-day iteration builds locally with `./build.sh`.
