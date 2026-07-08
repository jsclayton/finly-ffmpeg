#!/usr/bin/env bash
#
# build.sh — one-command orchestrator for the Finly FFmpeg pipeline.
#
#   ./build.sh              fetch -> build all slices -> xcframeworks -> LGPL bundle
#   ./build.sh --smoke      also run the simulator link+run smoke test at the end
#   ./build.sh --clean      wipe build/ and artifacts/ first
#
# Bumping FFmpeg is a two-line edit in scripts/config.sh (version + sha256),
# then re-run this. That is the entire update path (design §10).

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HERE}/scripts/config.sh"

do_clean=0; do_smoke=0
for a in "$@"; do
  case "$a" in
    --clean) do_clean=1 ;;
    --smoke) do_smoke=1 ;;
    *) die "unknown flag: $a" ;;
  esac
done

if [[ "${do_clean}" -eq 1 ]]; then
  log "cleaning build/ and artifacts/"
  rm -rf "${BUILD_DIR}" "${ARTIFACTS_DIR}"
fi

log "=== [1/4] fetch FFmpeg ${FFMPEG_VERSION} ==="
bash "${HERE}/scripts/fetch-ffmpeg.sh"

log "=== [2/4] cross-compile all slices ==="
bash "${HERE}/scripts/build-ffmpeg.sh"

log "=== [3/4] assemble xcframeworks ==="
bash "${HERE}/scripts/make-xcframeworks.sh"

log "=== [4/4] LGPL corresponding-source bundle ==="
bash "${HERE}/scripts/package-lgpl.sh"

if [[ "${do_smoke}" -eq 1 ]]; then
  log "=== smoke test (simulator link + run) ==="
  bash "${HERE}/scripts/smoke-test.sh"
fi

log "DONE. Artifacts:"
echo "  xcframeworks : ${ARTIFACTS_DIR}/xcframework/"
echo "  headers      : ${ARTIFACTS_DIR}/include/"
echo "  LGPL bundle  : ${ARTIFACTS_DIR}/lgpl/"
