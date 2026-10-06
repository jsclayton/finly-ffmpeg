# finly-ffmpeg — a remux-scoped FFmpeg build for Apple platforms

A repeatable pipeline that cross-compiles FFmpeg for Apple platforms and packages
it as dynamic-framework xcframeworks, ready to consume from a Swift package. It
builds nothing but FFmpeg: the consuming demux/remux engine lives in a separate
repository and depends on tagged releases of this one.

## What it produces

`./build.sh` fetches a pinned FFmpeg release, cross-compiles it for **six Apple
slices**, and assembles **four dynamic-framework xcframeworks** plus an **LGPL
compliance bundle**.

The six slices (see `scripts/config.sh` → `FF_ARCH_MATRIX`) are:

| platform | device | simulator |
|---|---|---|
| iOS (min 26.0)  | arm64 | arm64 + x86_64 |
| tvOS (min 26.0) | arm64 | arm64 + x86_64 |

Device slices are single-arch; each simulator slice is `lipo`'d (arm64 + x86_64)
so it runs on both Apple Silicon and Intel Macs. The four xcframeworks are
`libavutil`, `libavcodec`, `libavformat`, and `libswresample`.

**Debug symbols ship inside the xcframeworks**, so crashes inside these
libraries can be symbolicated. Every slice of every xcframework carries its
framework's dSYM at `<slice>/dSYMs/<lib>.framework.dSYM`, named by
`DebugSymbolsPath` in the xcframework's `Info.plist`. The libraries are
compiled with `-g` at the same optimization level, the dSYM is written from
each final framework binary (the fat one, for a simulator slice), and only then
is the shipped binary stripped (`strip -x`, exported symbols only, as before),
so the binary and its dSYM carry the same UUID for every arch. `make-xcframeworks.sh`
fails the build on a dSYM that would be incomplete or whose UUIDs do not match.
Source and build paths in the debug info are mapped to relative names
(`build/obj/<sdk>-<arch>/src/...`), so the dSYMs carry no path from the machine
that built them.

The dSYMs roughly triple the size of the release zips; the shipped binaries
keep their size and their exported symbols. Measured on FFmpeg 9.0.1, as the
`ditto` zips `release.sh` makes:

| xcframework zip | without dSYMs | with dSYMs |
|---|---|---|
| `libavcodec`    | 6.5 MB | 19.5 MB |
| `libavformat`   | 2.6 MB | 9.6 MB |
| `libavutil`     | 1.8 MB | 5.0 MB |
| `libswresample` | 0.3 MB | 0.7 MB |

The dSYMs sit beside each slice's `.framework`, not inside it, so embedding a
framework in an app does not carry its dSYM into the app bundle.

**The C code keeps its frame pointers**, so unwinders that walk them, as
in-process crash reporters do, see every frame. Apple's arm64 ABI requires x29
to always address a valid frame record; configure adds `-fomit-frame-pointer`
on its own, and `--optflags` in `scripts/config.sh` puts
`-fno-omit-frame-pointer` after it. Leaf functions may still skip the frame
record, as clang does by default on Apple platforms.

## Design constraints (deliberate)

These are fixed by the configure component set in `scripts/config.sh` — the
authoritative list; verify against it, don't trust this summary blindly:

- **Zero video encoders and zero video decoders.** Video is always
  stream-copied by consumers; probe metadata comes from containers and parsers,
  never a decoder.
- **No GPL and no non-free components** (built without `--enable-gpl`; rules out
  `libfdk_aac` — native `aac`/`ac3`/`eac3` only).
- **Audio decoders are included** (`--enable-decoder`): `dca`, `truehd`, `mlp`,
  `aac`, `aac_latm`, `ac3`, `eac3`, `flac`, `opus`, `vorbis`, `mp3`,
  `pcm_s16le`, `pcm_s24le`, `pcm_bluray`, plus text-subtitle decoders (`subrip`,
  `ass`, `ssa`, `movtext`, `webvtt`).
- **Audio encoders are included** (`--enable-encoder`): `aac`, `ac3`, `eac3`,
  `flac`, `alac` (`flac`/`alac` are the lossless transcode targets), plus the
  `webvtt` subtitle encoder.

Also disabled by design: `avdevice`, `swscale`, `avfilter`, programs
(`ffmpeg`/`ffprobe`/`ffplay`), networking (I/O is a consumer-supplied custom
`AVIOContext`), and assembly.

## Usage

```bash
./build.sh            # fetch → 6-arch cross-compile → 4 xcframeworks → LGPL bundle
./build.sh --smoke    # + link and run a probe on the iOS simulator
```

`--smoke` requires a working iOS simulator. Outputs land under `artifacts/`
(`artifacts/xcframework/`, `artifacts/include/`, `artifacts/lgpl/`).

## Bumping FFmpeg

It is a two-line change in `scripts/config.sh` — `FFMPEG_VERSION` and
`FFMPEG_SHA256` — then re-run `./build.sh`. **Re-verify the five vendored
patches still apply on every bump:** their struct paths and hook sites are
version-specific. The `bump-ffmpeg` skill (`.claude/skills/bump-ffmpeg`) walks
the full procedure.

## Vendored patches

Applied to a pristine source tree by `scripts/fetch-ffmpeg.sh`; they exist
because this is a decoder-less build and colour/HDR metadata that a full FFmpeg
would recover in the decoder must instead be lifted in the parser (0005 is the
exception — it is a bitstream-filter capability, not a metadata rescue):

- **0001** — makes the HEVC parser fill `color_trc`/`primaries`/`colorspace`/
  `range` from the SPS VUI. Without it a decoder-less build reads no colour
  metadata and HDR video is declared SDR.
- **0002** — makes `matroskadec` run HEVC header parsing, so 0001 takes effect
  for MKV sources.
- **0003** — same for the MP4/`mov` demux path.
- **0004** — lifts HEVC mastering-display + content-light SEI into
  `coded_side_data`, so `movenc` writes the `mdcv`/`clli` boxes on a
  stream-copied HDR10 output.
- **0005** — adds a `convert=p81` option to the upstream `dovi_rpu` bitstream
  filter: dual-layer Dolby Vision profile 7 in, single-layer profile 8.1 out.
  It sets `disable_residual_flag`, clears `el_spatial_resampling_filter_flag`
  and the NLQ block in the RPU, and rewrites the Dolby Vision configuration
  record on `par_out` (`dv_profile` 8, `dv_bl_signal_compatibility_id` 1,
  `el_present_flag` 0, no metadata compression). That is all it does: the
  enhancement layer itself, and the layer's own configuration record (`hvcE`),
  are removed by **upstream's own `dovi_split` filter**, which consumers chain
  ahead of this one — see *Consumption* below. The patch removes no upstream
  line. Still pure bitstream work — nothing is decoded.

## Licensing

The frameworks are **dynamic**, which preserves the LGPL 2.1 relink right by
construction. `scripts/package-lgpl.sh` emits the compliance bundle
(`artifacts/lgpl/`): the exact verified upstream source tarball, the build
scripts, the vendored patches, the precise configure options, and the license
texts — everything a recipient needs to rebuild and relink. See `NOTICE.md`.

## Consumption

The package vends one library product, **`CFFmpeg`** — the C-interop module that
surfaces the libav* API to Swift — with the four xcframeworks behind it.

**The Dolby Vision conversion is a two-filter chain**, in this order:
`dovi_split=mode=bl_rpu` first, `dovi_rpu=convert=p81` second, with the first
filter's `par_out` carried into the second's `par_in` — `dovi_rpu` reads and
mutates the configuration record on those parameters, so the record the first
filter masked has to be the record the second one sees. The order is forced:
after `dovi_rpu` has rewritten the record to profile 8.1 there is nothing left
to tell `dovi_split` what to strip, and `dovi_rpu` alone leaves the enhancement
layer in the output.

Pin a tagged release `.exact` — tags are `v{ffmpeg}-{N}` (semver pre-releases,
deliberately: a binary-artifact dependency is bumped on purpose, never by range
resolution):

```swift
.package(url: "https://github.com/jsclayton/finly-ffmpeg.git", exact: "9.0.1-1")
// product: .product(name: "CFFmpeg", package: "finly-ffmpeg")
```

The checkout compiles alone: the FFmpeg API headers under
`Sources/CFFmpeg/include/` are tracked, and the four binary targets download
checksummed `.xcframework.zip` release assets. For working ON this package,
consume a local checkout via an Xcode local-package override (and run
`./build.sh` there first).

## Releasing

`bash scripts/release.sh` — cuts a release from the **locally built,
verified** artifacts: refuses an xcframework that is missing a slice's dSYM,
zips the xcframeworks (dSYMs inside), computes SwiftPM checksums from
those exact bytes, rewrites `Package.swift` to this tag's asset URLs, commits,
tags `v{ffmpeg}-{N}`, pushes, and uploads the assets + LGPL bundle. The
tag-triggered GitHub Action is a from-scratch reproducibility check only — it
never publishes, because runner bytes would not match the committed checksums.
GitHub **release immutability** is enabled: published tags and assets lock,
and a deleted release burns its tag name forever — fix a bad release by
incrementing `N`, never by re-cutting.

The step before cutting is `bash scripts/release-notes.sh`, which drafts the
notes for the next tag from the tracker: the **breaking changes** first, since
`v{ffmpeg}-{N}` cannot signal a break the way a semver major would and the notes
are the only place a consumer learns the contract moved, then the list of what
landed. Short on purpose; the evidence stays on each ticket.
