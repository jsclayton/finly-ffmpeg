#!/usr/bin/env bash
#
# config.sh — single source of truth for the FFmpeg build pipeline.
#
# Everything downstream (fetch, build, packaging, LGPL bundle) reads its knobs
# from here. Bumping FFmpeg is a two-line change: FFMPEG_VERSION + FFMPEG_SHA256,
# then re-run ./build.sh. That is the whole "bump version, re-run, test" story
# a maintainable FFmpeg dependency needs.
#
# This file is `source`d, never executed directly.

set -euo pipefail

# ----------------------------------------------------------------------------
# Upstream source (pinned release tarball — the LGPL "corresponding source")
# ----------------------------------------------------------------------------
# We consume the blessed FFmpeg release tarball and verify it against a pinned
# SHA-256. The tarball itself is what we republish for LGPL §4(d) compliance.
# We do NOT fork or submodule FFmpeg: this build applies zero source patches
# (the URLSession AVIOContext bridge lives in app-side code against the public
# libav* API, not as an FFmpeg patch). If a patch is ever required, drop a
# *.patch into scripts/patches/ and it is applied on top of the verified tree.
FFMPEG_VERSION="8.1.2"
FFMPEG_SHA256="464beb5e7bf0c311e68b45ae2f04e9cc2af88851abb4082231742a74d97b524c"
FFMPEG_URL="https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz"

# ----------------------------------------------------------------------------
# Deployment targets (baked into every Mach-O via the -target triple)
# ----------------------------------------------------------------------------
IOS_MIN_VERSION="26.0"
TVOS_MIN_VERSION="26.0"

# ----------------------------------------------------------------------------
# Slice / arch matrix
# ----------------------------------------------------------------------------
# Each SLICE is one bucket of the final xcframework. Device slices are single
# -arch; simulator slices are lipo'd (arm64 + x86_64) so they run on both Apple
# Silicon and Intel Macs. The clang -target triple's "-simulator" suffix is what
# stamps LC_BUILD_VERSION correctly so `xcodebuild -create-xcframework` buckets
# each slice into the right platform+variant automatically.
#
# Format per arch entry: "<slice>|<sdk>|<arch>|<clang-target-triple>"
FF_ARCH_MATRIX=(
  "ios-device|iphoneos|arm64|arm64-apple-ios${IOS_MIN_VERSION}"
  "ios-simulator|iphonesimulator|arm64|arm64-apple-ios${IOS_MIN_VERSION}-simulator"
  "ios-simulator|iphonesimulator|x86_64|x86_64-apple-ios${IOS_MIN_VERSION}-simulator"
  "tvos-device|appletvos|arm64|arm64-apple-tvos${TVOS_MIN_VERSION}"
  "tvos-simulator|appletvsimulator|arm64|arm64-apple-tvos${TVOS_MIN_VERSION}-simulator"
  "tvos-simulator|appletvsimulator|x86_64|x86_64-apple-tvos${TVOS_MIN_VERSION}-simulator"
)

# Ordered list of unique slices (used by the xcframework assembler).
FF_SLICES=(ios-device ios-simulator tvos-device tvos-simulator)

# ----------------------------------------------------------------------------
# Libraries we ship (one dynamic framework each)
# ----------------------------------------------------------------------------
# Remux + audio-transcode needs exactly these four. avfilter / swscale /
# avdevice / postproc are disabled (see FF_CONFIGURE below), so they never
# build and are never shipped.
FF_LIBS=(libavutil libavcodec libavformat libswresample)

# ----------------------------------------------------------------------------
# The remux-scoped FFmpeg configure component set
# ----------------------------------------------------------------------------
# Philosophy: --disable-everything, then re-enable only what an on-device
# demux/remux + audio-transcode engine touches. No video encoders, ever. No
# video decoders (probe metadata comes from containers + parsers). No GPL, no
# non-free (rules out libfdk_aac — native aac/eac3 only). No network (I/O is
# the app's custom AVIOContext). asm disabled (audio transcode is trivial;
# keeps the toolchain free of nasm/gas-preprocessor and maximises reproducibility).
FF_COMPONENTS=(
  # --- containers we read ---
  --enable-demuxer=matroska,mov,mpegts
  # --- containers we write (mp4/mov = movenc fMP4; hls muxer for the spike) ---
  --enable-muxer=mov,mp4,hls,webvtt
  # --- framing: video passthrough keyframe detection + audio framing ---
  --enable-parser=h264,hevc,aac,ac3,dca,mlp,flac,opus,vorbis,mpegaudio
  # --- bitstream filters: annexb<->mp4, tagging, extradata, adts->asc ---
  --enable-bsf=h264_mp4toannexb,hevc_mp4toannexb,h264_metadata,hevc_metadata,extract_extradata,aac_adtstoasc,dca_core,eac3_core
  # --- audio decoders: transcode sources + probe correctness (NO video decoders) ---
  --enable-decoder=dca,truehd,mlp,aac,aac_latm,ac3,eac3,flac,opus,vorbis,mp3,pcm_s16le,pcm_s24le,pcm_bluray
  # --- text-subtitle decoders (WebVTT rendition path) ---
  --enable-decoder=subrip,ass,ssa,movtext,webvtt
  # --- audio encoders: native only, LGPL-clean ---
  --enable-encoder=aac,ac3,eac3
  # --- subtitle encoder for WebVTT renditions ---
  --enable-encoder=webvtt
  # --- protocols: file only, for diagnostics/fixtures; app I/O is custom AVIO ---
  --enable-protocol=file
)

# Structural / cross-compile / packaging flags shared by every arch.
# (Per-arch --arch / --cc / --extra-cflags are appended by build-ffmpeg.sh.)
FF_CONFIGURE=(
  --disable-everything
  --disable-programs           # no ffmpeg/ffprobe/ffplay CLIs (can't exec on iOS anyway)
  --disable-doc
  --disable-debug
  --disable-network            # all I/O via app-side custom AVIOContext
  --disable-asm                # acceptable here; keeps the toolchain minimal
  --disable-static
  --enable-shared              # dynamic frameworks satisfy LGPL relink by construction
  --enable-pic
  --disable-avdevice
  --disable-swscale
  --disable-avfilter
  # (postproc is GPL-only and off by default without --enable-gpl — no flag needed)
  --enable-swresample          # needed for audio downmix during DTS/TrueHD transcode
  --disable-bzlib              # libbz2 not needed for our containers
  --disable-lzma               # liblzma not needed for our containers
  --disable-audiotoolbox       # we use FFmpeg's native aac/eac3, not the AT codecs
  --disable-videotoolbox       # no video (de)coding in this engine
  --disable-sdl2
  --install-name-dir=@rpath    # dylib ids become @rpath/lib*.dylib for framework fixup
)

# ----------------------------------------------------------------------------
# Repo layout (absolute paths derived from this file's location)
# ----------------------------------------------------------------------------
CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${CONFIG_DIR}/.." && pwd)"
VENDOR_DIR="${ROOT_DIR}/vendor"
BUILD_DIR="${ROOT_DIR}/build"
ARTIFACTS_DIR="${ROOT_DIR}/artifacts"
PATCHES_DIR="${CONFIG_DIR}/patches"

FFMPEG_TARBALL="${VENDOR_DIR}/ffmpeg-${FFMPEG_VERSION}.tar.xz"
FFMPEG_SRC_DIR="${VENDOR_DIR}/ffmpeg-${FFMPEG_VERSION}"

# Parallelism for make.
FF_MAKE_JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

# Pretty logging helpers.
log()  { printf '\033[1;34m▸ %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m! %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }
