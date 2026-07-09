# Third-Party Notices

## FFmpeg

This project builds and distributes the FFmpeg libraries (libavutil, libavcodec,
libavformat, libswresample).

- **License:** GNU Lesser General Public License, version 2.1 or later (LGPL-2.1-or-later).
- **Configuration:** built **without** `--enable-gpl` and **without** any
  non-free component (notably no `libfdk_aac`). The build enables only the
  demuxers, muxers, parsers, bitstream filters, audio decoders, and native audio
  encoders required for on-device demux/remux and DTS/TrueHD→AAC/EAC3 transcode.
  No video encoders are built; no video decoders are enabled.
- **Linkage:** the libraries are linked as **dynamic frameworks**, preserving the
  LGPL relink right by construction.
- **Corresponding source:** the exact upstream release tarball, the build scripts,
  and the precise configure options are published as an LGPL compliance bundle
  (see `scripts/package-lgpl.sh`, output under `artifacts/lgpl/`). The bundle is
  what ships alongside any distributed binary to satisfy LGPL §6 / §4(d).

FFmpeg is a trademark of Fabrice Bellard, originator of the FFmpeg project.
Upstream: https://ffmpeg.org

An in-app attribution screen and the bundled `COPYING.LGPLv2.1` / `LICENSE.md`
texts must accompany any shipped Musket build that links these libraries.
