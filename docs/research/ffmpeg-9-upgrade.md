# Research: upgrading finly-ffmpeg from FFmpeg 8.1.2 to FFmpeg 9

Researched 2026-09-08 against primary sources only (ffmpeg.org, the 9.0.1
release tarball, the GitHub mirror of the FFmpeg git tags, and the tracked
8.1.2 source tree). Every claim cites its source inline. Anything not
confirmed from a primary source is marked UNVERIFIED.

## Summary

1. FFmpeg 9 is released: 9.0 (2026-08-04) and the point release 9.0.1 "Lei"
   (2026-08-12) are on ffmpeg.org; 8.1.2 (2026-06-17) is still the newest 8.x,
   so 8.1.2 is not stale within its branch, but 9.0.1 carries mov/mpegts/hvcC/
   hlsenc/dovi_rpu hardening fixes that no 8.1 release has yet (§1, §2).
2. All five vendored patches apply to 9.0.1 with the pipeline's plain
   `patch -p1` (offsets only; 0005 hunk 1 needs default fuzz because an
   `#include` line moved) and every patched file passes `clang -fsyntax-only`
   against the 9.0.1 headers with this repo's component set. Upstream 9 still
   does none of what 0001-0005 do; all five remain load-bearing (§4).
3. The 9.0 major bump (lavu 61 / lavc 63 / lavf 63 / lsws 10 / lswr 7) removes
   nothing the `cff_*` shims use, and every configure option and component in
   `scripts/config.sh` still exists and is LGPL-clean (`License: LGPL version
   2.1 or later`). The removals that could bite the *consuming engine* are
   `AVCodec.sample_fmts`/`supported_samplerates`/`ch_layouts`/`pix_fmts`
   (use `avcodec_get_supported_config()`), `av_opt_set_int_list`, and
   `FF_FDEBUG_TS` (alias kept behind `FF_API_FDEBUG_TS`) (§3).

Recommended bump inputs for `scripts/config.sh`: `FFMPEG_VERSION="9.0.1"`,
`FFMPEG_SHA256="cf38e0e28c7e5605942c4a77755349b0145804a397af37eb1fb4c77cb237f635"`
(see "Recommended bump inputs").

## 1. Is FFmpeg 9 released? Versions, dates, tarball, checksum

**Yes.** Two 9.x releases exist as of 2026-09-08.

| Release | Tarball on ffmpeg.org (`releases/` listing timestamp) | Git tag (GitHub mirror, tagger date) | Notes |
|---|---|---|---|
| 9.0 | `ffmpeg-9.0.tar.xz` 2026-08-04 01:15 | `n9.0` tagged 2026-08-03T21:21:22Z, "FFmpeg 9.0 release" | first 9.x |
| 9.0.1 | `ffmpeg-9.0.1.tar.xz` 2026-08-12 06:36 | `n9.0.1` tagged 2026-08-12T03:54:50Z, "FFmpeg 9.0.1 releasse" (sic) | **latest 9.x** |
| 8.1.2 | `ffmpeg-8.1.2.tar.xz` 2026-06-17 05:47 | `n8.1.2` tagged 2026-06-17T02:37:03Z | **latest 8.x** (no 8.1.3 exists) |

Sources: directory listing at <https://ffmpeg.org/releases/> (entries
`ffmpeg-9.0.tar.xz`, `ffmpeg-9.0.1.tar.xz`, `ffmpeg-8.1.2.tar.xz` and their
timestamps; no `ffmpeg-8.1.3*` or `ffmpeg-9.1*` entries exist); tag objects
via <https://api.github.com/repos/FFmpeg/FFmpeg/git/refs/tags/n9.0>,
`.../n9.0.1`, `.../n8.1.2` (annotated tag objects, `tagger.date` as above).
The GitHub tag list <https://github.com/FFmpeg/FFmpeg/tags> shows
`n9.1-dev`, `n9.0.1`, `n9.0`, `n8.2-dev`, `n8.1.2` as the newest tags, i.e.
9.1 is only a `-dev` marker, not a release.

<https://ffmpeg.org/download.html> states: "FFmpeg 9.0.1 'Lei' — 9.0.1 was
released on 2026-08-12. It is the latest stable FFmpeg release from the 9.0
release branch, which was cut from master on 2026-06-26. It includes the
following library versions: libavutil 61.1.100, libavcodec 63.1.100,
libavformat 63.1.100, libavdevice 63.1.100, libavfilter 12.1.100, libswscale
10.1.100, libswresample 7.1.100." The same page lists "FFmpeg 8.1.2 'Hoare' —
8.1.2 was released on 2026-06-17. It is the latest stable FFmpeg release from
the 8.1 release branch, which was cut from master on 2026-03-08 …
libavutil 60.26.102, libavcodec 62.28.102, libavformat 62.12.102 …
libswresample 6.3.102" and "FFmpeg 8.0.3 'Huffman' — released 2026-06-18".
The `RELEASE_NOTES` file in the 9.0.1 tarball says: "The FFmpeg Project
proudly presents FFmpeg 9.0 'Lei', about 4 months after the release of
FFmpeg 8.1." (`ffmpeg-9.0.1/RELEASE_NOTES`). `ffmpeg-9.0.1/VERSION` and
`ffmpeg-9.0.1/RELEASE` both contain `9.0.1`.

**Correction (2026-09-08, from the 9.0.1 bump):** the download page's 9.0.1
library numbers above are the 9.0 ones. The tarball itself says micro **101**,
not 100 — `ffmpeg-9.0.1/libavformat/version.h` has `LIBAVFORMAT_VERSION_MICRO
101`, and the built library reports `avformat 63.1.101` from the simulator
probe; likewise lavu 61.1.101, lavc 63.1.101, lswr 7.1.101. The majors are as
stated. Where the two disagree, the tarball is the primary source.

UNVERIFIED: the news page <https://ffmpeg.org/index.html> has no 9.0 or 9.0.1
news post at all (its newest headings are "June 24th, 2026, Ampere Server
Donation" then "September 11th, 2024, Coverity"), so no release announcement
text could be quoted from it. The release is nonetheless real: the tarball,
signature, download page entry and signed git tags all exist.

### Latest 9.x tarball and SHA-256

* URL: <https://ffmpeg.org/releases/ffmpeg-9.0.1.tar.xz> (12,036,420 bytes as
  downloaded 2026-09-08).
* `shasum -a 256 ffmpeg-9.0.1.tar.xz` computed locally:
  `cf38e0e28c7e5605942c4a77755349b0145804a397af37eb1fb4c77cb237f635`
* ffmpeg.org publishes **no** `.sha256` sidecar: a GET of
  <https://ffmpeg.org/releases/ffmpeg-9.0.1.tar.xz.sha256> returns HTTP 404,
  and the `releases/` listing contains zero `sha256` entries. Only a PGP
  signature is published (<https://ffmpeg.org/releases/ffmpeg-9.0.1.tar.xz.asc>,
  520 bytes, downloaded). UNVERIFIED: the PGP signature was not verified
  because no `gpg` binary is installed on this machine; the checksum above is
  therefore the locally computed one, not cross-checked against an upstream
  digest. Re-run `shasum -a 256` on a fresh download before committing it.
* Cross-check of method: `shasum -a 256` on the tracked
  `vendor/ffmpeg-8.1.2.tar.xz` gives
  `464beb5e7bf0c311e68b45ae2f04e9cc2af88851abb4082231742a74d97b524c`, which
  equals the pinned `FFMPEG_SHA256` in `scripts/config.sh`.

## 2. Changelog since 8.1.2

The 9.0.1 tarball's `Changelog` has the headings `version 9.0.1:` (line 4),
`version 9.0:` (line 93), `version 8.1:` (line 114), `version 8.0:` (line
145). It contains **no** `version 8.1.1:`/`8.1.2:` sections (point-release
sections live only in the release branch's own tarball), and there are **no**
8.x point releases after 8.1.2 (see §1). The 9.0 branch was cut from master on
2026-06-26, nine days after 8.1.2 (download.html); whether every 8.1.2
backport is in 9.0.1 was spot-checked only for "avcodec/hevc/ps: Factor window
reading out" (`read_window()` exists in both `ffmpeg-8.1.2/libavcodec/hevc/ps.c:65`
and `ffmpeg-9.0.1/libavcodec/hevc/ps.c:66`) — UNVERIFIED for the rest.

Verbatim from `ffmpeg-9.0.1/Changelog` (lines 4-113):

```text
version 9.0.1:
 Bump for 9.0.1
 avcodec/lcldec: clear what the multithread chunks leave undecoded
 avformat/mlv: end the LJ92 packet where its data ends
 avformat/mpegts: reject a max_packet_size below one TS payload
 avformat/mpegts: keep the PES payload within max_packet_size
 avfilter/spectrumsynth: negotiate one pixel format for both inputs
 avfilter/afir: bound the crossfades by the samples of the input frame
 Update for 9.0.1
 avformat/webp_anim_dec: use ffio_read_size for ICCP and EXIF chunk
 avformat/webp_anim_dec: use ffio_read_size for ICCP and EXIF chunks
 avformat/rtpenc_av1: do not narrow the OBU size to (long)
 avformat/rtpenc_av1: Check num_lebs
 avformat/rtpenc_av1: bound OBU size in the keyframe search loop
 avformat/gopher: Fix CRLF injection
 avformat/rtpenc_vc2hq: reject data units larger than the RTP payload buffer
 avformat/dashdec: reject a negative fragment index
 avformat/hevc: reject hvcC NAL arrays that overflow the 16-bit count
 avformat/mpegenc: reject stream counts that overflow the system header
 avformat/mpegenc: pass buffer size into put_system_header()
 avformat/librist: honor the caller buffer size in librist_read
 avformat/scd: reject zero-channel tracks
 avcodec/dolby_e: Add error recovery when parse_mantissas run out of bits
 avfilter/af_pan: check the id of named input channels before use
 swscale: avoid overflow in fast bilinear edge handling
 avformat/shared: Use correct printf specifier
 Revert "lavfi/bwdif: fix heap-buffer-overflow with small height videos"
 avfilter/vf_bwdif: fix line boundary checks for >8 bits content
 avformat/rawutils: reject raw RGB frames that do not fit an AVPacket
 avcodec/nvenc: write AV1 timecode metadata in AV1 syntax
 avcodec/utils: add ff_alloc_timecode_metadata_av1()
 avcodec/utils: factor the timecode fields out of ff_alloc_timecode_sei
 vulkan_encode_av1: set primary_ref_frame to a reference name, not a slot
 avformat/mov: reject a trun sample count the input cannot hold
 RELEASE_NOTES: Based on the version from 8.0
 avformat/mp3enc: fix underflow of the LAME encoder delay
 avformat/os_support: fix return value of win32_rename
 vulkan_encode: fix leak and swallowed errors in init_base_units()
 avfilter/dnn: fix async teardown race condition in all backends
 avcodec/tiff: reject inflate output shorter than the strip
 avformat/dashdec: check NULL pointer before use str_end_offset
 avformat/dashdec: check NULL pointer of av_strtok value before use it
 avfilter/vf_scale_cuda: fix non-scaling format conversion
 fftools/opt_common: fix format string bug in print_program_info
 avformat/dashdec: fix integer truncation in calc_max_seg_no()
 swscale/x86: fix SIGILL in u8 SCALE on SSE4-only CPUs
 avdevice/android_camera: fix OOB read in metadata parsing
 avformat/dashdec: don't stop at the first input EOF
 avformat/iamf_parse: check that num_sub_mixes and num_audio_elements in Mix Presentations are not zero
 avformat/iamf_parse: bound the output mix gain duration by the audio elements
 avcodec/cbs_h266: size vps_direct_ref_layer_flag for the full layer range
 avcodec/vulkan/ffv1_dec_setup: act on the slice header rejection
 avcodec/ffv1dec: reject a remap that produces zero entries
 avcodec/ffv1dec: mark the slice damaged when its remap fails
 avcodec/vulkan/ffv1_dec_setup: bound the fltmap write
 avcodec/vulkan/ffv1_dec_setup: test mul_count as unsigned
 avcodec/vulkan/ffv1_dec_setup: reject a remap that produces zero entries
 avcodec/pgssubdec: always give an output rect a palette
 scale_d3d11: Fix hw_frame_ctx reference leak
 avcodec/cfhd: reject transform-2 output wider than the plane
 avformat/rtsp: clear authentication on cross-origin redirects
 avcodec/dovi_rpuenc: normalize vdr_dm_metadata_present to 0/1
 avcodec/dovi_rpuenc: validate vdr_rpu_id from the input metadata
 avcodec/bsf/dovi_rpu: handle update_rpu() returning no RPU
 avcodec/dovi_rpudec: bound num_x/y_partitions
 avcodec/dovi_rpuenc: validate the data mapping before generation
 avfilter/af_arnndn: pad the DCT input buffers to the read length
 doc/nut.texi: point at the latest spec in the git repository
 avformat/mov: bound sgpd sync entry_count by the atom size
 avcodec/rscc: do not leave uninitilized data when the input is too short
 avcodec/dvbsub_parser: avoid signed overflow in the capacity check
 avformat/tls_openssl: bind peer identity for numeric-IP verify
 avformat/codec2: avoid integer overflow in packet size and duration
 avfilter/vf_xpsnr: avoid a zero block size on small frames
 avcodec/cbs_av1: pad the ITU-T T.35 payload buffer
 avcodec/screenpresso: reject deflate output shorter than the frame
 avformat/hls: Enforce protocol checks when opening child playlists
 avformat/hlsenc: Fix heap buffer overflow in parse_playlist()
 avformat/hlsenc: Handle extensionless URIs in extract_segment_number()
 avfilter/vf_lut3d: do not compute size*size before the size is validated
 avfilter/vf_hqdn3d: support dynamic frame sizes
 avfilter/vf_hqdn3d: reject unsupported frame parameter changes
 avcodec/bsf/truehd_core: clear profile value on init()
 avcodec/bsf/eac3_core: clear profile value on init()
 avformat/iamf_parse: fix inverted subblock duration validation
 avcodec/get_buffer: use frame pixel format instead of context
 avformat/lcevc: add a log context parameter to all functions


version 9.0:
- Extend AMF Color Converter (vf_vpp_amf) HDR capabilities
- LCEVC track muxing support in MP4 muxer
- Playdate video encoder and muxer
- Add v360_vulkan filter
- HE-AAC 960 decoding (DAB+)
- transpose_cuda filter
- Add AMF Frame Rate Converter (vf_frc_amf) filter
- SMPTE 2094-50 metadata support and passthrough
- ProRes RAW VideoToolbox hwaccel
- APV Vulkan hwaccel
- Animated WebP decoder
- Animated WebP demuxer
- Remove CELT decoding support (doesn't affect Opus CELT)
- Remove ogg/celt parsing
- Bitstream filter to split Dolby Vision multi-layer HEVC
- Add AMF hardware memory mapping support.
- ONNX Runtime DNN backend with GPU execution provider support
- Remove deprecated NVENC options and support for pre-11.1 SDK versions
```

Items in the 9.0 list that touch this build's scope: "Bitstream filter to
split Dolby Vision multi-layer HEVC" (§4 patch 0005, §5), "SMPTE 2094-50
metadata support and passthrough" (§5), "HE-AAC 960 decoding (DAB+)" (§5),
"Remove CELT decoding support (doesn't affect Opus CELT)" and "Remove
ogg/celt parsing" (neither is in `scripts/config.sh`). Items in the 9.0.1 list
that touch it: `avformat/mpegts` (2), `avformat/mov` (2), `avformat/hevc:
reject hvcC NAL arrays that overflow the 16-bit count`, `avformat/hls`/
`hlsenc` (3), `avcodec/bsf/dovi_rpu: handle update_rpu() returning no RPU`,
`avcodec/dovi_rpuenc` (3), `avcodec/dovi_rpudec: bound num_x/y_partitions`,
`avcodec/bsf/eac3_core: clear profile value on init()`.

## 3. API removals / deprecations affecting this repo

### Library majors (`<lib>/version_major.h` + `version.h`)

| Library | 8.1.2 | 9.0.1 |
|---|---|---|
| libavutil | 60.26.102 | **61**.1.101 |
| libavcodec | 62.28.102 | **63**.1.101 |
| libavformat | 62.12.102 | **63**.1.101 |
| libswresample | 6.3.102 | **7**.1.101 |
| libswscale (not shipped) | 9.5.102 | **10**.1.101 |

(Note the tarball's MICRO is 101 whereas download.html prints 100; both are
from ffmpeg.org, the header is authoritative for what gets built.)

### What the major bump removed (FF_API_* macros present in 8.1.2, gone in 9.0.1)

* libavutil (`libavutil/version.h`): `FF_API_MOD_UINTP2`, `FF_API_RISCV_FD_ZBA`,
  `FF_API_VULKAN_FIXED_QUEUES`, `FF_API_OPT_INT_LIST`, `FF_API_OPT_PTR`.
  Effect in public headers: `av_int_list_length()`/`av_int_list_length_for_size()`
  removed from `libavutil/avutil.h`; the `av_opt_set_int_list()` macro and
  `av_opt_ptr()` removed from `libavutil/opt.h`.
* libavcodec (`libavcodec/version_major.h`): `FF_API_V408_CODECID`,
  `FF_API_CODEC_PROPS`, `FF_API_EXR_GAMMA`, `FF_API_NVDEC_OLD_PIX_FMTS`,
  `FF_API_PARSER_PRIVATE`, `FF_API_PARSER_CODECID`. Effect:
  `AVCodecContext.properties` + `FF_CODEC_PROPERTY_*` removed; the private
  `AVCodecParser` fields removed and `av_parser_init()` now takes
  `enum AVCodecID`; `AV_CODEC_ID_V308/V408/V410` removed. Also removed from
  `libavcodec/codec.h` (their FF_API guards were already gone in 8.1.2 as
  attribute_deprecated fields): `AVCodec.supported_framerates`, `.pix_fmts`,
  `.supported_samplerates`, `.sample_fmts`, `.ch_layouts` — the replacement is
  `avcodec_get_supported_config()`. `libavcodec/codec.h` also no longer
  includes `libavutil/rational.h` / `libavutil/samplefmt.h` (the shim includes
  both directly, so nothing changes for `CFFmpeg.h`). `libavcodec/packet.h`:
  `AVPacketList` removed; `av_packet_pack_dictionary()` now takes
  `const AVDictionary *` (APIchanges 2026-06-23, lavc 62.37.100).
* libavformat (`libavformat/version_major.h`): `FF_API_INTERNAL_TIMING`,
  `FF_API_NO_DEFAULT_TLS_VERIFY`. Effect: `enum AVTimebaseSource`,
  `avformat_transfer_internal_stream_timing_info()` and
  `av_stream_get_codec_timebase()` removed from `libavformat/avformat.h`.
  `FF_FDEBUG_TS` is now `#define FF_FDEBUG_TS AV_FDEBUG_TS` under
  `FF_API_FDEBUG_TS` (deprecated, still compiles).
* libswresample: no FF_API macros in either version; `libswresample/swresample.h`
  is byte-identical between 8.1.2 and 9.0.1 (`diff` empty).

New deprecations scheduled for the next bump (9.0.1): lavc `FF_API_INIT_PACKET`,
`FF_API_INTRA_DC_PRECISION`, `FF_API_MJPEG_EXTERN_HUFF` (`< 64`); lavf
`FF_API_COMPUTE_PKT_FIELDS2`, `FF_API_FDEBUG_TS`, `FF_API_LCEVC_STRUCT` (`< 64`);
lavu `FF_API_CPU_FLAG_FORCE`, `FF_API_DOVI_L11_INVALID_PROPS`,
`FF_API_ASSERT_FPU`, `FF_API_VULKAN_SYNC_QUEUES` (`< 62`). `FF_API_R_FRAME_RATE`
stays `1` in both.

UNVERIFIED/observation: `ffmpeg-9.0.1/doc/APIchanges` carries no
"FFmpeg 8.1 was cut here" marker (its newest marker is "FFmpeg 8.0 was cut
here", line 209) and no entry describing the 9.0 removals; the removal set
above was derived by diffing the headers, not from APIchanges. The APIchanges
entries added after the 8.1.2 copy (all additive) are: lavu 60.34.100
`AVVkFrame.access`; lavc 62.37.100 `av_packet_pack_dictionary` const; lavu
60.33.100 `AV_FRAME_DATA_RAW_COLOR_PARAMS`; lsws 9.8.100 `SwsBackend`; lavu
60.32.100 `AVVulkanDeviceContext.queue_flags`; **lavf 62.19.100
`AVStreamGroupLayeredVideo`, `AVStreamGroup.params.layered_video`,
`AV_STREAM_GROUP_PARAMS_DOLBY_VISION`, deprecate `AVStreamGroupLCEVC`**;
**lavc 62.35.100 `AV_PKT_DATA_HEVC_CONF`**; lavf 62.18.100 `AV_FDEBUG_ID3V2`,
deprecate `FF_FDEBUG_TS`; lavf 62.17.100 `AV_STREAM_GROUP_PARAMS_TREF`;
lavf 62.16.100 `AVFMT_FIXED_FRAMESIZE`; lavc 62.33.100
`AV_CODEC_FLAG2_FIXED_FRAME_SIZE`; lavu 60.31.100 IAMF frame side data;
lavf 62.15.100 `av_program_copy()`; lavf 62.14.100
`av_program_add_stream_index2()`; **lavc 62.30.100
`AV_PKT_DATA_DYNAMIC_HDR_SMPTE_2094_APP5`**; lavu 60.30.100
`AVDynamicHDRSmpte2094App5`; plus Vulkan/swscale/AMF entries outside this
build.

### Every symbol `Sources/CFFmpeg/include/CFFmpeg.h` uses — status in 9.0.1

| Symbol | 9.0.1 location | Status |
|---|---|---|
| `AVERROR(e)` | `libavutil/error.h:41` (and `:45` for the non-negated variant) | unchanged |
| `AVERROR_EOF` | `libavutil/error.h:57` | unchanged |
| `AVERROR_INVALIDDATA` | `libavutil/error.h:61` | unchanged |
| `av_strerror(int, char*, size_t)` | `libavutil/error.h:100` | unchanged |
| `AV_NOPTS_VALUE` | `libavutil/avutil.h:247` | unchanged |
| `AV_TIME_BASE` (1000000) | `libavutil/avutil.h:253` | unchanged |
| `AVSEEK_SIZE` (0x10000) | `libavformat/avio.h:468` | unchanged |
| `AVSEEK_FORCE` (0x20000) | `libavformat/avio.h:476` | unchanged |
| `MKTAG` | `libavutil/macros.h:55` | unchanged |
| `AV_PKT_FLAG_KEY` (0x0001) | `libavcodec/packet.h:650` | unchanged |
| `AVFMT_GLOBALHEADER` (0x0040) | `libavformat/avformat.h:478` | unchanged |
| `AV_CODEC_FLAG_GLOBAL_HEADER` (1<<22) | `libavcodec/avcodec.h:318` | unchanged |
| `AVSEEK_FLAG_BACKWARD` (1) | `libavformat/avformat.h:2575` | unchanged |
| `AVIndexEntry` {`int64_t pos; int64_t timestamp; int flags:2; int size:30; int min_distance;`} | `libavformat/avformat.h:601-616` | unchanged (bitfields still need the shims) |
| `AVINDEX_KEYFRAME` (0x0001) | `libavformat/avformat.h:609` | unchanged |

Headers included by the shim, all present in 9.0.1: `libavutil/avutil.h`,
`opt.h`, `dict.h`, `error.h`, `channel_layout.h`, `samplefmt.h`,
`mathematics.h`, `rational.h`; `libavcodec/avcodec.h`, `bsf.h`, `codec.h`,
`packet.h`; `libavformat/avformat.h`, `avio.h`; `libswresample/swresample.h`.
Of these, `dict.h`, `error.h`, `channel_layout.h`, `samplefmt.h`,
`mathematics.h`, `rational.h`, `bsf.h`, `avio.h` and `swresample.h` are
byte-identical to 8.1.2 (`diff` empty). `libavcodec/codec_par.h` changes are
comments only (no non-comment diff lines).

Consequence for the tracked headers under `Sources/CFFmpeg/include/`: they
will change on the bump (by design, per CLAUDE.md), but nothing in
`CFFmpeg.h` itself needs editing.

### configure: options used by `scripts/config.sh`

`./configure --help` was run from both trees and diffed. Options removed in
9.0.1: `--enable-libcelt`, `--enable-libglslang`, `--enable-libshaderc`,
`--enable-libnpp`, `--enable-omx`, `--enable-omx-rpi`. Options added:
`--disable-checkasm`, `--enable-libonnxruntime`, `--makeinfo=`,
`--disable-pmull`, `--disable-eor3`. **None of the removed options is used by
`scripts/config.sh`**; every option it passes (`--disable-everything`,
`--disable-programs`, `--disable-doc`, `--disable-debug`, `--disable-network`,
`--disable-asm`, `--disable-static`, `--enable-shared`, `--enable-pic`,
`--disable-avdevice`, `--disable-swscale`, `--disable-avfilter`,
`--enable-swresample`, `--disable-bzlib`, `--disable-lzma`,
`--disable-audiotoolbox`, `--disable-videotoolbox`, `--disable-sdl2`,
`--install-name-dir=`, `--enable-{demuxer,muxer,parser,bsf,decoder,encoder,protocol}=`)
appears in `ffmpeg-9.0.1/configure --help`. The configure diff contains no
darwin/iOS/tvOS-specific changes beyond adding `llvm` to the `--toolchain`
list and defaulting `cc`/`cxx` to clang in one new branch.

All 52 components named in `FF_COMPONENTS` are still registered in 9.0.1
(`libavcodec/allcodecs.c`, `libavcodec/parsers.c`,
`libavcodec/bitstream_filters.c`, `libavformat/allformats.c`,
`libavformat/protocols.c` each contain the matching `ff_<name>;` line), and
none of their `*_deps=` lines in `ffmpeg-9.0.1/configure` mention `gpl`,
`nonfree` or `version3` (the only such hits, `ahx_parser_deps="lgpl_gpl"` and
`ahx_to_mp2_bsf_deps`, are not in the set). `dovi_rpu_bsf_select="cbs_h265
cbs_av1 dovi_rpudec dovi_rpuenc"` (`configure:3755`) is unchanged. A host
`./configure` run in a scratch copy with exactly the `FF_COMPONENTS` +
`FF_CONFIGURE` flags (minus the cross-compile ones) succeeded and printed
`License: LGPL version 2.1 or later`. `LICENSE.md` is byte-identical between
8.1.2 and 9.0.1.

## 4. The five vendored patches against 9.0.1

Method: `patch -p1 --dry-run -d <pristine 9.0.1 tree> < patch` (BSD patch
2.0-12u11-Apple, the same `patch` the pipeline's `scripts/fetch-ffmpeg.sh:61`
invokes with plain `patch -p1 -d "${FFMPEG_SRC_DIR}"`), then again with
`--verbose -F0` to expose fuzz, then a real application to a scratch copy
followed by `clang -fsyntax-only` of every touched `.c` file using the
`CFLAGS`/`CPPFLAGS` from that copy's `ffbuild/config.mak` plus `-I.
-DHAVE_AV_CONFIG_H`.

| Patch | File | Result (`-F0`) | Result (default fuzz, as the pipeline runs it) |
|---|---|---|---|
| 0001 | `libavcodec/hevc/parser.c` | Hunk #1 succeeded at 95 (offset 1 line) | applies |
| 0002 | `libavformat/matroskadec.c` | Hunk #1 succeeded at 3042 (offset 27 lines) | applies |
| 0003 | `libavformat/mov.c` | Hunk #1 succeeded at 3157 (offset 111 lines) | applies |
| 0004 | `libavcodec/h2645_sei.h` | Hunk #1 succeeded at 172 (offset -5 lines) | applies |
| 0004 | `libavcodec/h2645_sei.c` | Hunk #1 succeeded at 698 (offset -235 lines) | applies |
| 0004 | `libavcodec/hevc/parser.c` | Hunk #1 succeeded at 241 (offset -16 lines) | applies |
| 0005 | `libavcodec/bsf/dovi_rpu.c` | **Hunk #1 failed at 33**; #2 at 48, #3 at 75, #4 at 102 (exact); #5 at 257, #6 at 295, #7 at 363 (offset 6 lines) | **applies** (hunk 1 with fuzz) |

The "No such line 176/932 in input file, ignoring" notices BSD patch prints
for 0004 only mean the hunk's stated start line is past the shorter 9.0.1
file; the hunks then applied by context with an offset and no fuzz.

Syntax check of the merged files (`libavcodec/hevc/parser.c`,
`libavformat/matroskadec.c`, `libavformat/mov.c`, `libavcodec/h2645_sei.c`,
`libavcodec/bsf/dovi_rpu.c`): all `OK`. No `.rej` files were produced.

### Per-patch hook-site analysis and "does upstream 9 do this natively?"

**0001 (SPS VUI colour → avctx in the HEVC parser).** The hook site
(`avctx->profile = …; avctx->level = …;` then the VPS/VUI timing block) is at
`ffmpeg-9.0.1/libavcodec/hevc/parser.c:95-104`; the only parser.c change
since 8.1.2 is the include block (`#include "libavcodec/golomb.h"` etc.,
lines 26-30). Upstream still does **not** export colour from the parser: a
grep of the 9.0.1 parser for `color_primaries|color_trc|colorspace|
color_range` finds nothing (only `separate_colour_plane` at line 150). Still
needed.

**0002 (matroskadec runs HEVC header parsing).** Hook site unchanged in
substance: `if (par->codec_id != AV_CODEC_ID_HEVC) sti->need_parsing =
AVSTREAM_PARSE_HEADERS;` at `libavformat/matroskadec.c:3045-3046`. Upstream 9
still excludes HEVC. Still needed.

**0003 (mov runs HEVC header parsing).** The stsd `switch` at
`libavformat/mov.c:3154-3163` lists `AV_CODEC_ID_APV`, `EVC`, `LCEVC`, `AV1`,
`H264` → `AVSTREAM_PARSE_HEADERS`, still no `HEVC` case; the only other HEVC
route into parsing is the all-keyframe `stss` fallback at `mov.c:3549-3553`.
Still needed.

**0004 (mastering-display + content-light SEI → coded_side_data).** In 9.0.1
`ff_h2645_sei_to_context()` still targets `decoded_side_data`
(`libavcodec/h2645_sei.c:697-701`); `H2645SEI` still has
`mastering_display` and `content_light` (`libavcodec/h2645_sei.h:135-136`) with
the same sub-fields the patch reads; `av_mastering_display_metadata_alloc_size()`
(`libavutil/mastering_display_metadata.h:87`),
`av_content_light_metadata_alloc()` (`:126`), `av_packet_side_data_add()`
(`libavcodec/packet.h:467`) and `FF_COMPLIANCE_STRICT` (`libavcodec/defs.h:59`)
all exist. `H2645SEI` was restructured (`a53_caption`, `afd`,
`dynamic_hdr_plus`, `dynamic_hdr_vivid`, `lcevc` moved into a single
`FFITUTT35Meta itut_t35`; `aom_film_grain` dropped) but the patch does not
touch those. Upstream's own mastering branch now allocates via
`ff_decode_mastering_display_new_ext()` (`h2645_sei.c:431`) while keeping the
identical range validation the patch mirrors (`:439-468`). movenc still reads
only `codecpar->coded_side_data` for `clli`/`mdcv`
(`libavformat/movenc.c:2659-2700`, called at `:2959-2960`), so the patch's
rationale holds. The merged parser call sits at `parser.c:270`, immediately
before `ret = hevc_parse_slice_header(...)` at `:271`, as intended. Still
needed.

**0005 (dovi_rpu `convert=p81`).** Hunk 1 fails at `-F0` only because
`#include "hevc/hevc.h"` became `#include "libavcodec/hevc/hevc.h"`
(`libavcodec/bsf/dovi_rpu.c:34`); with default fuzz the enum lands after the
include block as before. Two upstream changes in 9.0.1 are semantically
relevant and were checked in the merged file: (a) `update_rpu()` now
early-returns `*out_rpu = NULL; *out_size = 0;` when
`ff_dovi_get_metadata()` reports no metadata (`dovi_rpu.c:58-63`, Changelog
9.0.1 "avcodec/bsf/dovi_rpu: handle update_rpu() returning no RPU"); the
patch's three-field mutation is inserted after that early return (merged
lines ~78-89), so it only runs on a non-NULL `metadata`; (b) the HEVC fragment
handler now has `if (!rpu || rpu_size <= 0) return 0;` after `update_rpu()`
(`:102-103`) and the AV1 path skips empty RPUs (`:163-166`); both survive the
patch untouched. All fields/functions the patch uses still exist:
`AVDOVIDecoderConfigurationRecord.{el_present_flag,
dv_bl_signal_compatibility_id, dv_md_compression}` (`libavutil/dovi_meta.h:61-64`),
`AVDOVIRpuDataHeader.{el_spatial_resampling_filter_flag, disable_residual_flag}`
(`:101-102`), `AV_DOVI_NLQ_NONE` (`:131`), `av_dovi_get_header/mapping`
(`:363/:369`), `ff_dovi_configure_from_codedpar()` (`libavcodec/dovi_rpu.h:147`),
`FF_DOVI_COMPRESS_RPU` (`:161`), `ff_dovi_rpu_generate()` (`:174`),
`ff_cbs_delete_unit()` (`libavcodec/cbs.h`).

Does upstream 9 now convert profile 7 → 8.1 natively? **No.** The 9.0.1
`dovi_rpu` bsf still exposes only `strip` and `compression`
(`dovi_rpu.c:268-272`; `doc/bitstream_filters.texi` section `dovi_rpu`), and
its HEVC path still inspects only the *last* NAL of the access unit
(`dovi_rpu.c:83-98`). What 9.0 adds is a **new, separate** `dovi_split` bsf
(`libavcodec/bsf/dovi_split.c`, `bitstream_filters.c:37`,
`configure:3756 dovi_split_bsf_select="hevcparse"`, Changelog 9.0 "Bitstream
filter to split Dolby Vision multi-layer HEVC"). Its `mode` option is `bl`
(default; "drop every UNSPEC63 (EL) and every UNSPEC62 (RPU) … plain HEVC
stream with no Dolby Vision markers"), `bl_rpu` ("Base layer with the RPU NAL
kept"), `el`, `el_rpu` (`doc/bitstream_filters.texi`, section `dovi_split`).
It walks every NAL (`nal_is_kept()`), so it does fix the "strip only sees the
last NAL" defect that 0005 documents — but in `bl_rpu` mode it keeps the
profile-7 RPU **verbatim** (no `disable_residual_flag`/NLQ rewrite) and only
masks `bl_present_flag`/`el_present_flag`/`rpu_present_flag` in the `dvcC`
record; it never sets `dv_profile = 8` or `dv_bl_signal_compatibility_id`
(`dovi_split.c`, `dovi_split_init()`). So `dovi_split` alone does not produce
a valid single-layer 8.1 stream; 0005 is still needed for the conversion. A
future simplification (not required for the bump) would be to chain
`dovi_split=mode=bl_rpu` before `dovi_rpu` and shrink 0005 to the RPU/record
rewrite only.

Also new in 9.0 and relevant to profile-7 handling: `mov`, `matroska` and
`mpegts` demuxers now create an `AV_STREAM_GROUP_PARAMS_DOLBY_VISION` stream
group for **dual-track** carriage (mov: `mov_parse_dovi_streams()`,
`libavformat/mov.c:11160-11230`, requires a `vdep` track reference, a
`dvhe`/`dvh1` sample entry and a `dvcC` with `dv_profile == 7`,
`el_present_flag`, `!bl_present_flag`; matroska:
`matroska_parse_dovi_streams()`, `matroskadec.c:3351-3418`, pairs one
profile-7 EL track with one other HEVC track; mpegts: `mpegts.c:2505-2735`,
via `dependency_pid` or the M2TS BL/EL PIDs). This only *groups* already
separate `AVStream`s; it does not split a single interleaved profile-7 track
into two streams, so the packet content 0005 sees is unchanged. The `hvcE`
box / Matroska BlockAdditionMapping is now exported as
`AV_PKT_DATA_HEVC_CONF` coded side data (`mov.c:8866`,
`matroskadec.c:2518-2524`, `packet.h:378-384`), and movenc writes it back as
`hvcE` (`movenc.c:2540`, called at `:3014`).

### The two properties 0002/0003 rely on

* `AVSTREAM_PARSE_HEADERS` still exists with the doc "Only parse headers, do
  not repack." (`libavformat/avformat.h:593`). `demux.c` maps it to
  `PARSER_FLAG_COMPLETE_FRAMES` in both places (`libavformat/demux.c:1490-1491`
  and `:2657-2658`), and the HEVC parser honours that flag by taking
  `next = buf_size` instead of `hevc_find_frame_end()`/`ff_combine_frame()`
  (`libavcodec/hevc/parser.c:325-333`) — no repacking. The diff of `demux.c`
  between 8.1.2 and 9.0.1 (36 lines) contains no line mentioning
  `need_parsing`, `PARSE`, `PARSER_FLAG` or `has_b_frames`.
* `has_b_frames`: nothing under `libavcodec/hevc/` sets it except the decoder
  (`hevcdec.c:344`), which this build does not compile. The generic
  `demux.c` rule that sets `has_b_frames = 1` when a parser reports a B
  picture (`demux.c:1025-1028`) is byte-identical to 8.1.2 (`:1025-1028`).

## 5. New 9.x features relevant to this build

From `ffmpeg-9.0.1/Changelog` (9.0 section), `doc/APIchanges`, and the source:

* **Dolby Vision**: new `dovi_split` bsf (see §4). New
  `AV_STREAM_GROUP_PARAMS_DOLBY_VISION` / `AVStreamGroupLayeredVideo`
  (APIchanges lavf 62.19.100; `avformat.h:1076-1102`) populated by the mov,
  matroska and mpegts demuxers for dual-track profile 7 (§4).
  `AV_PKT_DATA_HEVC_CONF` (APIchanges lavc 62.35.100) carries the EL `hvcE`
  record through a stream copy. `movenc` still writes `dvcC`/`dvvC`/`dvwC`
  (`movenc.c:2522-2532`) and now `hvcE` (`:2540`). 9.0.1 hardening:
  "avcodec/bsf/dovi_rpu: handle update_rpu() returning no RPU",
  "avcodec/dovi_rpuenc: normalize vdr_dm_metadata_present to 0/1", "…validate
  vdr_rpu_id from the input metadata", "…validate the data mapping before
  generation", "avcodec/dovi_rpudec: bound num_x/y_partitions".
* **HDR static/dynamic metadata**: `mdcv`/`clli`/`amve` writers unchanged
  (`movenc.c:2659-2720`, called at `:2959-2961`). New "SMPTE 2094-50 metadata
  support and passthrough" (Changelog 9.0) via
  `AV_PKT_DATA_DYNAMIC_HDR_SMPTE_2094_APP5` / `AVDynamicHDRSmpte2094App5`
  (APIchanges lavc 62.30.100, lavu 60.30.100). UNVERIFIED whether the mov
  demuxer/muxer or the HEVC parser use 2094-50 in a decoder-less path; only the
  side-data types were confirmed. HDR10+ handling is unchanged in the files
  this build ships (no new HDR10+ entries in Changelog/APIchanges).
* **HEVC/H.264 parsers**: `hevc/parser.c` differs from 8.1.2 only in the
  include block; `h264_parser.c` differs by 2 lines. No behavioural change
  found for the parse-headers path.
* **Demuxers**: `mov.c` (521 diff lines) — DV/LCEVC stream groups, `hvcE`,
  `AV_STREAM_GROUP_PARAMS_TREF` groups, 9.0.1 fixes "reject a trun sample
  count the input cannot hold" and "bound sgpd sync entry_count by the atom
  size". `matroskadec.c` (250) — DV grouping, `hvcE`. `mpegts.c` (298) — DV
  grouping, 9.0.1 fixes "reject a max_packet_size below one TS payload" and
  "keep the PES payload within max_packet_size". `libavformat/hevc.c` — 9.0.1
  "reject hvcC NAL arrays that overflow the 16-bit count".
* **Muxers**: `movenc.c` (480 diff lines) — `hvcE`, "LCEVC track muxing
  support in MP4 muxer" (Changelog 9.0; not enabled here), `AVFMT_FIXED_FRAMESIZE`
  flag. `hlsenc.c` (177) — 9.0.1 "Fix heap buffer overflow in
  parse_playlist()", "Handle extensionless URIs in extract_segment_number()",
  plus "avformat/hls: Enforce protocol checks when opening child playlists".
* **Seeking / AVIndexEntry**: `libavformat/seek.c` is byte-identical to 8.1.2;
  `AVIndexEntry` unchanged (§3).
* **Audio codecs**: "HE-AAC 960 decoding (DAB+)" (Changelog 9.0;
  `libavcodec/aac/aacdec.c` 121 diff lines, `aacenc.c` 230). `ac3enc.c`,
  `eac3enc.c`, `flacdec.c`, `flacenc.c`, `alacenc.c`, `mlpdec.c` are
  byte-identical; `ac3dec.c` 6 lines, `dcadec.c` 26 lines, `opus/dec.c` 7
  lines changed. 9.0.1: "avcodec/bsf/eac3_core: clear profile value on
  init()". "Remove CELT decoding support (doesn't affect Opus CELT)" removes a
  codec this build never enabled.
* **swresample**: `swresample.h`, `swresample.c`, `rematrix.c` byte-identical
  to 8.1.2; only the major number changed (6 → 7).
* **Apple toolchain**: no darwin/iOS/tvOS-specific configure changes (§3).
* **Licensing**: `LICENSE.md` identical; host configure with this component
  set reports `License: LGPL version 2.1 or later`. No component in
  `scripts/config.sh` became GPL-gated or was removed (§3).
* **Deprecations/removals that may affect the consuming engine, not this
  repo** (§3): `AVCodec.sample_fmts`/`supported_samplerates`/`ch_layouts`/
  `pix_fmts`/`supported_framerates` removed (use
  `avcodec_get_supported_config()`); `av_opt_set_int_list`, `av_opt_ptr`,
  `av_int_list_length` removed; `AVPacketList` removed;
  `avformat_transfer_internal_stream_timing_info()`,
  `av_stream_get_codec_timebase()` removed; `FF_FDEBUG_TS` deprecated alias.
  UNVERIFIED whether the engine uses any of these (it lives in another
  repository).

## Recommended bump inputs

```bash
FFMPEG_VERSION="9.0.1"
FFMPEG_SHA256="cf38e0e28c7e5605942c4a77755349b0145804a397af37eb1fb4c77cb237f635"
```

`FFMPEG_URL` stays `https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz`.
The SHA-256 above was computed locally with `shasum -a 256` on the 12,036,420-
byte download of 2026-09-08; ffmpeg.org publishes no digest file (§1), so
recompute on the fresh download `scripts/fetch-ffmpeg.sh` makes before
committing. No change to `scripts/patches/`, `FF_COMPONENTS` or
`FF_CONFIGURE` is required for the patches to apply and compile; the tracked
headers under `Sources/CFFmpeg/include/` will be regenerated by the build.
Re-run the full oracle pass in the engine suite before tagging (the engine
may hit the removed `AVCodec.*` list fields, §3). The first tag would be
`v9.0.1-1`.

## Sources

* <https://ffmpeg.org/releases/> — directory listing (versions, timestamps,
  absence of `.sha256` files and of 8.1.3/9.1).
* <https://ffmpeg.org/releases/ffmpeg-9.0.1.tar.xz> — the tarball analysed
  (SHA-256 `cf38e0e2…37f635`); files cited as `ffmpeg-9.0.1/<path>:<line>`.
* <https://ffmpeg.org/releases/ffmpeg-9.0.1.tar.xz.asc> — PGP signature
  (downloaded, not verified: no gpg installed).
* <https://ffmpeg.org/download.html> — release dates, branch cut dates,
  library versions for 9.0.1, 8.1.2, 8.0.3.
* <https://ffmpeg.org/index.html> — news page (no 9.x announcement present).
* <https://github.com/FFmpeg/FFmpeg/tags> and
  <https://api.github.com/repos/FFmpeg/FFmpeg/git/refs/tags/{n9.0,n9.0.1,n8.1.2}>
  — tag list and annotated tag dates. UNVERIFIED via
  <https://git.ffmpeg.org/gitweb/ffmpeg.git>: the gitweb host served an
  anti-bot challenge page instead of the tags page, so the GitHub mirror was
  used.
* `vendor/ffmpeg-8.1.2/` (extracted from the tracked
  `vendor/ffmpeg-8.1.2.tar.xz`, SHA-256 `464beb5e…b524c`) — the 8.1.2
  comparison tree; note its patched files carry the 0001-0005 hunks.
* `scripts/config.sh`, `scripts/fetch-ffmpeg.sh`, `scripts/patches/000{1..5}-*.patch`,
  `Sources/CFFmpeg/include/CFFmpeg.h`, `CLAUDE.md`, `README.md` — this repo.
