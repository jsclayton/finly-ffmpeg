/*
 * CFFmpeg.h — umbrella surfacing the slim FFmpeg C API to Swift.
 *
 * This is the ONLY bridge between Swift and libav*. The higher-level engine
 * (URLSession AVIOContext bridge, Fragmenter, playlist engine) is built on top of
 * these symbols; nothing here knows about HLS, transport, or policy.
 *
 * Header search resolves <libavformat/...> etc. against this target's
 * publicHeadersPath (the FFmpeg install headers are synced alongside this file
 * by scripts/make-xcframeworks.sh), so cross-library includes work naturally.
 */
#ifndef MUSKET_CFFMPEG_H
#define MUSKET_CFFMPEG_H

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

/*
 * Swift can't see FFmpeg's function-like macros (AVERROR, AVERROR_EOF, …) or
 * compute AVERROR values. These trivial inlines surface exactly what the Swift
 * engine needs across the interop boundary.
 */
static inline int cff_averror(int errnum)      { return AVERROR(errnum); }
static inline int cff_error_eof(void)          { return AVERROR_EOF; }
static inline int cff_error_invaliddata(void)  { return AVERROR_INVALIDDATA; }
static inline int cff_error_einval(void)       { return AVERROR(EINVAL); }
static inline int64_t cff_nopts_value(void)    { return AV_NOPTS_VALUE; }
static inline int cff_seek_size(void)          { return AVSEEK_SIZE; }
static inline int cff_seek_force(void)         { return AVSEEK_FORCE; }
static inline int64_t cff_time_base(void)      { return AV_TIME_BASE; }
static inline int cff_error_eagain(void)       { return AVERROR(EAGAIN); }

/* movenc/output helpers */
static inline unsigned cff_tag_hvc1(void)      { return MKTAG('h','v','c','1'); }
static inline int cff_pkt_flag_key(void)       { return AV_PKT_FLAG_KEY; }
static inline int cff_avfmt_globalheader(void) { return AVFMT_GLOBALHEADER; }

/* Encoder flag: emit the codec's headers (FLAC STREAMINFO) out-of-band, so
 * movenc carries them in the sample entry (dfLa) rather than in-band. The macro
 * (1 << 22) does not reliably import into Swift. Audio transcode only. */
static inline int cff_codec_flag_global_header(void) { return AV_CODEC_FLAG_GLOBAL_HEADER; }

/* Seeking. AVSEEK_FLAG_BACKWARD lands on the keyframe at or before the target. */
static inline int cff_seek_flag_backward(void) { return AVSEEK_FLAG_BACKWARD; }

/*
 * AVIndexEntry.flags is a C bitfield (`int flags:2`), which Swift cannot read.
 * These accessors expose the demuxer's keyframe index — the cheap way to derive
 * exact segment boundaries without producing anything.
 */
static inline int cff_index_entry_is_keyframe(const AVIndexEntry *e) {
    return e && (e->flags & AVINDEX_KEYFRAME) != 0;
}
static inline int64_t cff_index_entry_timestamp(const AVIndexEntry *e) {
    return e ? e->timestamp : 0;
}
/* Absolute byte offset in the file: matroskadec adds segment_start to the raw
 * CueClusterPosition, and mov stores chunk_offset + preceding sample sizes. */
static inline int64_t cff_index_entry_pos(const AVIndexEntry *e) {
    return e ? e->pos : -1;
}
/* Also a bitfield (`int size:30`). Exact sample size in MP4; always 0 in
 * Matroska, whose index entries are added with size 0. */
static inline int cff_index_entry_size(const AVIndexEntry *e) {
    return e ? e->size : 0;
}

/* Render an AVERROR code to a human string (av_strerror wrapper). */
static inline void cff_strerror(int errnum, char *buf, size_t buflen) {
    if (av_strerror(errnum, buf, buflen) < 0) snprintf(buf, buflen, "error %d", errnum);
}

#endif /* MUSKET_CFFMPEG_H */
