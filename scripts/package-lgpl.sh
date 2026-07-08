#!/usr/bin/env bash
#
# package-lgpl.sh — produce the LGPL corresponding-source compliance bundle.
#
# FFmpeg is LGPL-2.1+. Shipping it (even dynamically linked) obliges Finly to
# provide the library's complete corresponding source and the scripts used to
# build it, so a recipient can rebuild and relink (design §10 / parent §6).
#
# Because we ship DYNAMIC frameworks, the relink right is satisfied by
# construction: a recipient rebuilds FFmpeg from this bundle and drops the
# replacement frameworks into the app. This script emits everything they need.

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

[[ -f "${FFMPEG_TARBALL}" ]] || die "source tarball missing — run scripts/fetch-ffmpeg.sh first"

BUNDLE_NAME="finly-ffmpeg-lgpl-${FFMPEG_VERSION}"
BUNDLE_DIR="${ARTIFACTS_DIR}/lgpl/${BUNDLE_NAME}"
rm -rf "${BUNDLE_DIR}"
mkdir -p "${BUNDLE_DIR}/scripts"

log "assembling LGPL bundle: ${BUNDLE_NAME}"

# 1) the exact, verified upstream source (the corresponding source itself)
cp "${FFMPEG_TARBALL}" "${BUNDLE_DIR}/"
echo "${FFMPEG_SHA256}  ffmpeg-${FFMPEG_VERSION}.tar.xz" > "${BUNDLE_DIR}/ffmpeg-${FFMPEG_VERSION}.tar.xz.sha256"

# 2) the exact build scripts (so the build is reproducible byte-for-byte)
cp "${CONFIG_DIR}"/*.sh "${BUNDLE_DIR}/scripts/"
if [[ -d "${PATCHES_DIR}" ]]; then cp -R "${PATCHES_DIR}" "${BUNDLE_DIR}/scripts/patches"; fi

# 3) the license texts, lifted from the source tree if it is extracted
if [[ -d "${FFMPEG_SRC_DIR}" ]]; then
  for f in COPYING.LGPLv2.1 COPYING.LGPLv3 LICENSE.md; do
    [[ -f "${FFMPEG_SRC_DIR}/${f}" ]] && cp "${FFMPEG_SRC_DIR}/${f}" "${BUNDLE_DIR}/"
  done
fi

# 4) the canonical configure invocation used for every slice (audit trail)
{
  echo "# Exact FFmpeg configure options used by the Finly build pipeline."
  echo "# Per-arch flags (--arch/--cc/--sysroot/--extra-cflags/--extra-ldflags with the"
  echo "# clang -target triple) are added by scripts/build-ffmpeg.sh; see below."
  echo
  echo "FFmpeg version: ${FFMPEG_VERSION}"
  echo "Source SHA-256: ${FFMPEG_SHA256}"
  echo
  echo "Structural flags:"
  printf '  %s\n' "${FF_CONFIGURE[@]}"
  echo
  echo "Component flags:"
  printf '  %s\n' "${FF_COMPONENTS[@]}"
  echo
  echo "Per-arch matrix (slice|sdk|arch|clang-target):"
  printf '  %s\n' "${FF_ARCH_MATRIX[@]}"
} > "${BUNDLE_DIR}/CONFIGURE.txt"

# 5) the recipient-facing relink instructions + written offer
cat > "${BUNDLE_DIR}/README-LGPL.md" <<MD
# FFmpeg — LGPL Corresponding Source (Finly)

This bundle is provided to satisfy the GNU LGPL (v2.1 or later) obligations for
the FFmpeg libraries distributed with Finly. Finly does not modify FFmpeg; it
links the unmodified libraries below as **dynamic frameworks**.

## What FFmpeg version this is
- Version: **${FFMPEG_VERSION}**
- Upstream source: \`ffmpeg-${FFMPEG_VERSION}.tar.xz\` (included here, unmodified)
- SHA-256: \`${FFMPEG_SHA256}\`
- License: LGPL-2.1-or-later (no GPL, no non-free components were enabled)

## How this build was produced
1. \`scripts/fetch-ffmpeg.sh\` downloads and SHA-256-verifies the source above.
2. \`scripts/build-ffmpeg.sh\` cross-compiles it for iOS/tvOS (device + simulator)
   with the options recorded in \`CONFIGURE.txt\`.
3. \`scripts/make-xcframeworks.sh\` packages the shared libraries into dynamic
   \`.xcframework\`s (libavutil, libavcodec, libavformat, libswresample).

## Your relink right
Because the libraries are dynamic frameworks, you may replace them with your own
build of FFmpeg ${FFMPEG_VERSION} (or a compatible LGPL version): rebuild using
the scripts here, then substitute the resulting \`*.xcframework\` binaries.

## Written offer
The complete corresponding source for the FFmpeg version used is included in
this bundle. For any questions contact: john@johnclayton.co
MD

# 6) tar it up next to the bundle dir
( cd "${ARTIFACTS_DIR}/lgpl" && tar -czf "${BUNDLE_NAME}.tar.gz" "${BUNDLE_NAME}" )
log "  -> ${ARTIFACTS_DIR}/lgpl/${BUNDLE_NAME}.tar.gz"
log "LGPL bundle complete"
