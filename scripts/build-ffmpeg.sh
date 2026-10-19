#!/usr/bin/env bash
#
# build-ffmpeg.sh — cross-compile the slim FFmpeg for every arch in the matrix.
#
# One out-of-tree build per (sdk, arch). Each installs shared dylibs +
# public headers into build/install/<sdk>-<arch>/. Assembly into fat
# frameworks and xcframeworks happens later in make-xcframeworks.sh.
#
# In-process, not a process: we build the libav* shared libraries the app links
# against. There is no ffmpeg binary here — --disable-programs.

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

[[ -d "${FFMPEG_SRC_DIR}" ]] || die "source not found — run scripts/fetch-ffmpeg.sh first"

# configure writes its whole command line into config.h as FFMPEG_CONFIGURATION,
# the string avutil_configuration() and its siblings return, so every absolute
# path passed to configure (--prefix, the prefix maps in --extra-cflags, the
# -oso_prefix in --extra-ldflags) would be compiled into each shipped binary.
# Rewrite the checkout root to "." on that one line before make reads it, so
# the string reads --prefix=./build/install/...
# The rewrite is literal, not a pattern, and touches no other line (the install
# itself still uses the real prefix, from config.mak). It dies if the line does
# not hold the root first (configure moved the string, so the rewrite would
# silently do nothing) and if the line still holds it after.
scrub_configuration() { # config.h, tag
  local header="$1" tag="$2" key='#define FFMPEG_CONFIGURATION ' line
  [[ "$(grep -c -F -- "${key}" "${header}" || true)" == 1 ]] \
    || die "${tag}: ${header} does not hold exactly one FFMPEG_CONFIGURATION line"
  line="$(grep -F -- "${key}" "${header}")" || die "${tag}: cannot read FFMPEG_CONFIGURATION from ${header}"
  [[ "${line}" == *"${ROOT_DIR}"* ]] \
    || die "${tag}: FFMPEG_CONFIGURATION does not hold the checkout root; configure moved the string"
  ROOT="${ROOT_DIR}" KEY="${key}" perl -pi -e 's/\Q$ENV{ROOT}\E/./g if index($_, $ENV{KEY}) == 0' "${header}" \
    || die "${tag}: rewriting FFMPEG_CONFIGURATION failed"
  line="$(grep -F -- "${key}" "${header}")" || die "${tag}: the rewrite removed FFMPEG_CONFIGURATION from ${header}"
  [[ "${line}" != *"${ROOT_DIR}"* ]] \
    || die "${tag}: FFMPEG_CONFIGURATION still holds the checkout root after the rewrite"
}

build_one() {
  local slice="$1" sdk="$2" arch="$3" triple="$4"
  local tag="${sdk}-${arch}"
  local objdir="${BUILD_DIR}/obj/${tag}"
  local prefix="${BUILD_DIR}/install/${tag}"

  log "building ${tag}  (slice=${slice}, target=${triple})"

  local sysroot; sysroot="$(xcrun --sdk "${sdk}" --show-sdk-path)" \
    || die "cannot resolve SDK path for ${sdk}"
  local cc; cc="$(xcrun --sdk "${sdk}" --find clang)"

  # FFmpeg's --arch expects the machine name; map arm64 -> aarch64.
  local ffarch="${arch}"
  [[ "${arch}" == "arm64" ]] && ffarch="aarch64"

  # -target carries the min-OS version and the simulator variant, so the linker
  # stamps the correct LC_BUILD_VERSION for xcframework bucketing.
  local flags="-target ${triple} -arch ${arch} -isysroot ${sysroot} -fPIC"

  # The debug info (--enable-debug in config.sh) records source and build paths;
  # map them to stable relative names so the published dSYMs are the same
  # wherever the build ran and carry no path from the machine that built them.
  # -ffile-prefix-map covers __FILE__ as well as the debug info. __FILE__ is
  # already relative (FFmpeg's out-of-tree build compiles through its `src`
  # link), so that half is a backstop. configure records these flags, with
  # their absolute paths, in its configuration string, which scrub_configuration
  # rewrites after configure.
  local cflags="${flags}"
  cflags+=" -ffile-prefix-map=${FFMPEG_SRC_DIR}=ffmpeg-${FFMPEG_VERSION}"
  cflags+=" -ffile-prefix-map=${BUILD_DIR}=build"

  # The same commit builds to the same bytes in any checkout. The linker writes
  # a debug map into the unstripped library, one N_OSO entry per object file
  # with its absolute path and its modification time, and derives the
  # library's LC_UUID from the whole output. strip removes the map, but not the
  # UUID, so two checkouts (or two builds) gave libraries that differed in
  # their UUID and the signature over it. -oso_prefix records the object paths
  # relative to the checkout root (make_dsym gives dsymutil the root back), and
  # ZERO_AR_DATE=1, on make below, records each modification time as 0.
  local ldflags="${flags} -Wl,-oso_prefix,${ROOT_DIR}/"

  rm -rf "${objdir}" "${prefix}"
  mkdir -p "${objdir}"

  ( cd "${objdir}" && "${FFMPEG_SRC_DIR}/configure" \
      --prefix="${prefix}" \
      --enable-cross-compile \
      --target-os=darwin \
      --arch="${ffarch}" \
      --cc="${cc}" \
      --as="${cc}" \
      --sysroot="${sysroot}" \
      --extra-cflags="${cflags}" \
      --extra-ldflags="${ldflags}" \
      "${FF_CONFIGURE[@]}" \
      "${FF_COMPONENTS[@]}" \
      > "${objdir}/configure.log" 2>&1 ) \
    || { tail -40 "${objdir}/configure.log" >&2; die "configure failed for ${tag} (see ${objdir}/configure.log)"; }

  scrub_configuration "${objdir}/config.h" "${tag}"

  ( cd "${objdir}" && ZERO_AR_DATE=1 make -j"${FF_MAKE_JOBS}" > "${objdir}/make.log" 2>&1 ) \
    || { tail -40 "${objdir}/make.log" >&2; die "make failed for ${tag} (see ${objdir}/make.log)"; }

  ( cd "${objdir}" && make install > "${objdir}/install.log" 2>&1 ) \
    || { tail -40 "${objdir}/install.log" >&2; die "make install failed for ${tag}"; }

  log "  installed ${tag} -> ${prefix}"
}

# Allow building a single arch for iteration:  build-ffmpeg.sh iphoneos-arm64
filter="${1:-}"
built=0
for entry in "${FF_ARCH_MATRIX[@]}"; do
  IFS='|' read -r slice sdk arch triple <<< "${entry}"
  if [[ -n "${filter}" && "${filter}" != "${sdk}-${arch}" ]]; then
    continue
  fi
  build_one "${slice}" "${sdk}" "${arch}" "${triple}"
  built=$((built + 1))
done

[[ "${built}" -gt 0 ]] || die "no arch matched filter '${filter}'"
log "compiled ${built} arch build(s)"
