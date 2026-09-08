---
name: bump-ffmpeg
description: Bump the pinned FFmpeg version safely — the pin, the gate, the regenerated headers, and the needs-hands release issue. Use for an FFmpeg security release or any move to a newer upstream release.
---

# Bump FFmpeg

A bump is the pinned version and the tracked headers the build regenerates —
nothing else. Nothing from the new release is adopted in the same change: a new
demuxer, a new bitstream filter, a new option is its own ticket. Keeping the
diff to the pin plus the headers is what lets a bump land on the gate alone
(`docs/adr/0001-landing-proves-the-build-not-the-behaviour.md`).

Run every step from the repo root. Never `source scripts/config.sh` into an
interactive zsh — it sets `set -euo pipefail` and will kill the shell.

## 1. Change the pin

Two lines in `scripts/config.sh`:

```
FFMPEG_VERSION="<new>"
FFMPEG_SHA256="<sha256 of https://ffmpeg.org/releases/ffmpeg-<new>.tar.xz>"
```

ffmpeg.org publishes no digest file, so the checksum is self-computed: put a
value in, let `scripts/fetch-ffmpeg.sh` download and verify it, and commit the
value the fresh download produced. A mismatch is a stop, not a re-pin — the
checksum is the trust anchor for the bytes the LGPL bundle republishes.

While the file is open, fix the comment above the pin: the configure-set
comment states which version the patches were **confirmed against**, and it is
a lie the moment the pin moves.

## 2. Run the gate

```bash
./build.sh --clean --smoke
```

Fetch verifies the tarball, applies every patch in `scripts/patches/` and dies
on the first failure; the six slices cross-compile; the four xcframeworks are
assembled; the LGPL bundle is packaged from the new tarball; the probe links
against the simulator slice and prints `SMOKE_OK`. The exact gate command,
its wall clock and its one retry rule live in `docs/agents/loop.md`.

**A patch that fails to apply stops the bump.** Never skip a hunk, and do not
rebase the patch inside the bump. Ask first: **does upstream now do this?** If
the new release does the patch's job natively, the patch is retired in its own
investigated change, not folded into a bump
(`docs/adr/0002-upstream-is-the-gold-standard.md`). Either way the bump is
blocked until that question has an answer.

## 3. Check the shims

The one thing a major bump breaks that the build itself never compiles:
`Sources/CFFmpeg/include/CFFmpeg.h` carries the `cff_*` shims for the C
bitfields and function-like macros Swift cannot see. Seconds, from the repo
root:

```bash
xcrun clang -fsyntax-only -target arm64-apple-ios26.0-simulator \
  -isysroot "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
  -I Sources/CFFmpeg/include Sources/CFFmpeg/shim.c
```

Exit 0 is green. Run it before the gate as well when a shim looks at risk: it
names the broken shim, where the gate would only say the probe failed to link.

## 4. Commit the pin and the headers together

`scripts/make-xcframeworks.sh` regenerates the tracked FFmpeg API headers under
`Sources/CFFmpeg/include/libav*` and `libsw*`. They are tracked on purpose, so
a SwiftPM checkout compiles without a build; a diff there is the signal that
the FFmpeg version changed. Commit them **in the same commit as the pin** —
a checkout between the two would not compile. Do not hand-edit them.

`vendor/`, `build/` and `artifacts/` are gitignored and per-checkout; nothing
about them is bookkeeping for the commit.

## 5. Update the four doc mentions

- `scripts/config.sh` — the "confirmed against" version in the patch comment (step 1).
- `CLAUDE.md` — the patch range in "Re-verify patches …", if the count moved.
- `README.md` — the stated version and the example `.exact` pin, which becomes
  `"<new>-1"`: `N` resets to 1 on a bump.
- `docs/agents/loop.md` — the gate's measured wall clock and the `avformat`
  number the probe prints. Both move on every bump, and the file's own rule is
  "keep each entry true": a stale measurement is what makes a slow or wrong
  gate run look normal.

## 6. File the needs-hands issue

The bump lands on the gate. What the gate cannot see is behaviour: this repo
has no suite of its own, and the consuming engine's lives in its own
repository. So the bump ends by filing exactly one issue labelled
`needs-hands`, addressed to John, with the two steps that are his:

1. **Confirm** — point the consumer at this checkout through a local package
   override at the landed sha and run its suite.
2. **Release** — `bash scripts/release.sh`, which cuts `v<new>-1` from the
   locally built artifacts.

That issue never blocks the landing. Releasing is John's alone: the tag is
immutable and a burned tag name is permanent, so an implementer never tags and
never pushes.
