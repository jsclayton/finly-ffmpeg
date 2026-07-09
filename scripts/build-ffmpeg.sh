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
      --extra-cflags="${flags}" \
      --extra-ldflags="${flags}" \
      "${FF_CONFIGURE[@]}" \
      "${FF_COMPONENTS[@]}" \
      > "${objdir}/configure.log" 2>&1 ) \
    || { tail -40 "${objdir}/configure.log" >&2; die "configure failed for ${tag} (see ${objdir}/configure.log)"; }

  ( cd "${objdir}" && make -j"${FF_MAKE_JOBS}" > "${objdir}/make.log" 2>&1 ) \
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
