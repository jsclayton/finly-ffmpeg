#!/usr/bin/env bash
#
# smoke-test.sh — prove the built xcframeworks are consumable end-to-end.
#
# Compiles + links a tiny C probe against the iOS-simulator slice, then runs it
# in a booted simulator and checks it prints SMOKE_OK. This exercises the whole
# chain: header module -> symbol resolution -> @rpath dynamic load -> real
# libav* calls (including avio_alloc_context, the custom-I/O entry point).

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

XCF="${ARTIFACTS_DIR}/xcframework"
INC="${ROOT_DIR}/Sources/CFFmpeg/include"
SLICE="ios-arm64_x86_64-simulator"
WORK="${BUILD_DIR}/smoketest"
TRIPLE="arm64-apple-ios${IOS_MIN_VERSION}-simulator"

[[ -d "${XCF}/libavformat.xcframework/${SLICE}" ]] \
  || die "no simulator slice — run scripts/make-xcframeworks.sh first"

mkdir -p "${WORK}"
cat > "${WORK}/probe.c" <<'EOF'
#include "CFFmpeg.h"
#include <stdio.h>
int main(void) {
    unsigned v = avformat_version();
    printf("avformat %u.%u.%u\n", AV_VERSION_MAJOR(v), AV_VERSION_MINOR(v), AV_VERSION_MICRO(v));
    if (!avformat_alloc_context()) { printf("FAIL alloc_context\n"); return 1; }
    unsigned char *buf = av_malloc(4096);
    if (!avio_alloc_context(buf, 4096, 0, NULL, NULL, NULL, NULL)) { printf("FAIL avio\n"); return 1; }
    // confirm a remux-critical muxer and audio encoder are actually present
    if (!av_guess_format("mp4", NULL, NULL)) { printf("FAIL mp4 muxer missing\n"); return 1; }
    if (!avcodec_find_encoder(AV_CODEC_ID_AAC))  { printf("FAIL aac encoder missing\n");  return 1; }
    if (!avcodec_find_encoder(AV_CODEC_ID_EAC3)) { printf("FAIL eac3 encoder missing\n"); return 1; }
    if (!avcodec_find_decoder(AV_CODEC_ID_DTS))  { printf("FAIL dts decoder missing\n");  return 1; }
    printf("SMOKE_OK\n");
    return 0;
}
EOF

SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
args=(-target "${TRIPLE}" -isysroot "${SDK}" -I "${INC}" "${WORK}/probe.c" -o "${WORK}/probe")
for l in "${FF_LIBS[@]}"; do
  d="${XCF}/${l}.xcframework/${SLICE}"
  args+=(-F "${d}" -framework "${l}" -Wl,-rpath,"${d}")
done

log "compiling + linking probe (${TRIPLE})"
xcrun clang "${args[@]}" || die "link failed"

# need a booted simulator; boot the first available iPhone if none is booted
if ! xcrun simctl list devices | grep -q "(Booted)"; then
  dev="$(xcrun simctl list devices available | grep -oE '\(([0-9A-F-]{36})\)' | head -1 | tr -d '()')"
  [[ -n "${dev}" ]] || die "no simulator available to boot"
  log "booting simulator ${dev}"
  xcrun simctl boot "${dev}" || true
fi

log "running probe in simulator"
out="$(xcrun simctl spawn booted "${WORK}/probe" 2>/dev/null)"
echo "${out}"
echo "${out}" | grep -q "SMOKE_OK" || die "smoke test did not print SMOKE_OK"
log "SMOKE TEST PASSED"
