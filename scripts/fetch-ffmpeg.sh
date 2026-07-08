#!/usr/bin/env bash
#
# fetch-ffmpeg.sh — download, verify, extract the pinned FFmpeg release.
#
# The pinned SHA-256 is the reproducibility trust anchor: a mismatch aborts the
# build rather than silently compiling unknown source. The verified tarball is
# also the exact artifact republished for LGPL compliance (see package-lgpl.sh).

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

mkdir -p "${VENDOR_DIR}"

# --- download (skip if a byte-identical copy is already present) ------------
need_download=1
if [[ -f "${FFMPEG_TARBALL}" ]]; then
  have="$(shasum -a 256 "${FFMPEG_TARBALL}" | awk '{print $1}')"
  if [[ "${have}" == "${FFMPEG_SHA256}" ]]; then
    log "tarball present and verified: ffmpeg-${FFMPEG_VERSION}.tar.xz"
    need_download=0
  else
    warn "cached tarball hash mismatch — re-downloading"
    rm -f "${FFMPEG_TARBALL}"
  fi
fi

if [[ "${need_download}" -eq 1 ]]; then
  log "downloading ${FFMPEG_URL}"
  curl -fSL --retry 3 -o "${FFMPEG_TARBALL}" "${FFMPEG_URL}" \
    || die "download failed: ${FFMPEG_URL}"
fi

# --- verify -----------------------------------------------------------------
actual="$(shasum -a 256 "${FFMPEG_TARBALL}" | awk '{print $1}')"
if [[ "${actual}" != "${FFMPEG_SHA256}" ]]; then
  die "SHA-256 mismatch for ffmpeg-${FFMPEG_VERSION}.tar.xz
       expected: ${FFMPEG_SHA256}
       actual:   ${actual}
     Refusing to build unverified source. If you intentionally bumped the
     version, update FFMPEG_SHA256 in scripts/config.sh."
fi
log "sha256 verified: ${actual}"

# --- extract (clean each time so patches apply to a pristine tree) ----------
if [[ -d "${FFMPEG_SRC_DIR}" ]]; then
  log "removing previous extracted tree"
  rm -rf "${FFMPEG_SRC_DIR}"
fi
log "extracting into ${FFMPEG_SRC_DIR}"
tar -xf "${FFMPEG_TARBALL}" -C "${VENDOR_DIR}"
[[ -d "${FFMPEG_SRC_DIR}" ]] || die "extraction did not produce ${FFMPEG_SRC_DIR}"

# --- optional patches (empty by default; this is our "fork lite" hook) ------
if [[ -d "${PATCHES_DIR}" ]]; then
  shopt -s nullglob
  patches=("${PATCHES_DIR}"/*.patch)
  shopt -u nullglob
  if [[ ${#patches[@]} -gt 0 ]]; then
    log "applying ${#patches[@]} patch(es) from scripts/patches/"
    for p in "${patches[@]}"; do
      log "  patch: $(basename "${p}")"
      patch -p1 -d "${FFMPEG_SRC_DIR}" < "${p}" || die "failed to apply $(basename "${p}")"
    done
  fi
fi

log "FFmpeg ${FFMPEG_VERSION} source ready at ${FFMPEG_SRC_DIR}"
