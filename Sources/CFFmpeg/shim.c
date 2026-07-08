/*
 * shim.c — intentionally minimal.
 *
 * CFFmpeg is a C interop target that exists only to surface the FFmpeg headers
 * to Swift as an importable module. SwiftPM wants at least one compilable
 * source per C target; this is it. All real symbols come from the linked
 * libav* xcframeworks.
 */
#include "CFFmpeg.h"
