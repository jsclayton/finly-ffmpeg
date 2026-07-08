/*
 * CFFmpeg.h — umbrella surfacing the slim FFmpeg C API to Swift.
 *
 * This is the ONLY bridge between Swift and libav*. The higher-level engine
 * (pump-loop actor, URLSession AVIOContext bridge, Fragmenter, Playlist Engine)
 * is built on top of these symbols in later phases; nothing here knows about
 * Jellyfin, HLS, or policy.
 *
 * Header search resolves <libavformat/...> etc. against this target's
 * publicHeadersPath (the FFmpeg install headers are synced alongside this file
 * by scripts/make-xcframeworks.sh), so cross-library includes work naturally.
 */
#ifndef FINLY_CFFMPEG_H
#define FINLY_CFFMPEG_H

#include <libavutil/avutil.h>
#include <libavutil/opt.h>
#include <libavutil/dict.h>
#include <libavutil/error.h>
#include <libavutil/channel_layout.h>
#include <libavutil/samplefmt.h>
#include <libavutil/mathematics.h>
#include <libavutil/rational.h>

#include <libavcodec/avcodec.h>
#include <libavcodec/bsf.h>
#include <libavcodec/codec.h>
#include <libavcodec/packet.h>

#include <libavformat/avformat.h>
#include <libavformat/avio.h>

#include <libswresample/swresample.h>

#endif /* FINLY_CFFMPEG_H */
