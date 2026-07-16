#!/usr/bin/env bash
#
# make-xcframeworks.sh — assemble per-arch dylibs into dynamic frameworks,
# then bundle the four platform slices of each library into one .xcframework.
#
# Dynamic frameworks are the deliberate choice: they satisfy the
# LGPL relink obligation by construction (the app links against replaceable
# framework binaries) and let Xcode "Embed & Sign" per platform.
#
# Per library we produce one .xcframework with four slices:
#   ios-device (arm64) · ios-simulator (arm64+x86_64)
#   tvos-device (arm64) · tvos-simulator (arm64+x86_64)

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

INSTALL_ROOT="${BUILD_DIR}/install"
FWROOT="${BUILD_DIR}/frameworks"
XCF_OUT="${ARTIFACTS_DIR}/xcframework"
INC_OUT="${ARTIFACTS_DIR}/include"

command -v install_name_tool >/dev/null || die "install_name_tool not found"

[[ -d "${INSTALL_ROOT}" ]] || die "no per-arch installs — run scripts/build-ffmpeg.sh first"

rm -rf "${FWROOT}" "${XCF_OUT}"
mkdir -p "${FWROOT}" "${XCF_OUT}" "${INC_OUT}"

# --- slice metadata helpers -------------------------------------------------
# arches for a slice, space-separated, in matrix order
slice_arches() {
  local want="$1" out=""
  for entry in "${FF_ARCH_MATRIX[@]}"; do
    IFS='|' read -r slice sdk arch triple <<< "${entry}"
    [[ "${slice}" == "${want}" ]] && out+="${sdk}-${arch} "
  done
  echo "${out}"
}
slice_platform() { # -> CFBundleSupportedPlatforms value
  case "$1" in
    ios-device)      echo "iPhoneOS" ;;
    ios-simulator)   echo "iPhoneSimulator" ;;
    tvos-device)     echo "AppleTVOS" ;;
    tvos-simulator)  echo "AppleTVSimulator" ;;
  esac
}
slice_minos() { case "$1" in ios-*) echo "${IOS_MIN_VERSION}" ;; tvos-*) echo "${TVOS_MIN_VERSION}" ;; esac; }

# real (non-symlink) versioned dylib for a lib inside an arch install dir
find_dylib() {
  local libdir="$1" name="$2"
  find "${libdir}" -maxdepth 1 -type f -name "${name}.*.dylib" | head -1
}

# rewrite a framework binary's id + inter-library dependency paths to @rpath/<fw>
fixup_install_names() {
  local binary="$1" self="$2"
  install_name_tool -id "@rpath/${self}.framework/${self}" "${binary}"
  # any dependency on one of our sibling libs -> its framework path
  otool -L "${binary}" | awk 'NR>1{print $1}' | while read -r dep; do
    local base libname
    base="$(basename "${dep}")"       # e.g. libavutil.60.dylib
    libname="${base%%.*}"             # e.g. libavutil
    for l in "${FF_LIBS[@]}"; do
      if [[ "${libname}" == "${l}" && "${dep}" != "@rpath/${l}.framework/${l}" ]]; then
        install_name_tool -change "${dep}" "@rpath/${l}.framework/${l}" "${binary}"
      fi
    done
  done
}

write_info_plist() { # dest, name, slice
  local dest="$1" name="$2" slice="$3"
  local platform minos; platform="$(slice_platform "${slice}")"; minos="$(slice_minos "${slice}")"
  cat > "${dest}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>${name}</string>
  <key>CFBundleIdentifier</key><string>com.codemonkeylabs.finly.ffmpeg.${name}</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>${name}</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>${FFMPEG_VERSION}</string>
  <key>CFBundleVersion</key><string>${FFMPEG_VERSION}</string>
  <key>MinimumOSVersion</key><string>${minos}</string>
  <key>CFBundleSupportedPlatforms</key><array><string>${platform}</string></array>
</dict>
</plist>
PLIST
}

# --- build one <lib>.framework per slice, then the xcframework --------------
for lib in "${FF_LIBS[@]}"; do
  log "assembling ${lib}.xcframework"
  xcf_args=()

  for slice in "${FF_SLICES[@]}"; do
    arches=($(slice_arches "${slice}"))
    [[ ${#arches[@]} -gt 0 ]] || die "no arches for slice ${slice}"

    # gather the per-arch dylibs for this lib
    inputs=()
    for tag in "${arches[@]}"; do
      d="$(find_dylib "${INSTALL_ROOT}/${tag}/lib" "${lib}")"
      [[ -n "${d}" ]] || die "missing ${lib} dylib in ${tag} (build incomplete?)"
      inputs+=("${d}")
    done

    fwdir="${FWROOT}/${slice}/${lib}.framework"
    mkdir -p "${fwdir}"
    local_bin="${fwdir}/${lib}"

    if [[ ${#inputs[@]} -eq 1 ]]; then
      cp "${inputs[0]}" "${local_bin}"
    else
      lipo -create "${inputs[@]}" -output "${local_bin}" || die "lipo failed for ${lib}/${slice}"
    fi

    fixup_install_names "${local_bin}" "${lib}"
    write_info_plist "${fwdir}/Info.plist" "${lib}" "${slice}"
    codesign --force --sign - --timestamp=none "${fwdir}" >/dev/null 2>&1 || true

    xcf_args+=(-framework "${fwdir}")
  done

  xcodebuild -create-xcframework "${xcf_args[@]}" \
    -output "${XCF_OUT}/${lib}.xcframework" >/dev/null \
    || die "xcodebuild -create-xcframework failed for ${lib}"
  log "  -> ${XCF_OUT}/${lib}.xcframework"
done

# --- export public headers once (arch-independent) --------------------------
# Headers are identical across arches. We publish them two places:
#   1. artifacts/include        — the canonical export.
#   2. Sources/CFFmpeg/include  — vendored next to the modulemap so the CFFmpeg
#      SwiftPM module resolves <libavformat/...> against its own
#      publicHeadersPath (cross-library includes work for importers).
log "exporting public headers -> artifacts/include + Sources/CFFmpeg/include"
some_arch="$(ls "${INSTALL_ROOT}" | head -1)"
rm -rf "${INC_OUT}"; mkdir -p "${INC_OUT}"
cp -R "${INSTALL_ROOT}/${some_arch}/include/." "${INC_OUT}/"

# vendor the per-library header dirs into the CFFmpeg module (leave CFFmpeg.h /
# module.modulemap untouched).
cffmpeg_inc="${ROOT_DIR}/Sources/CFFmpeg/include"
if [[ -d "${cffmpeg_inc}" ]]; then
  for l in "${FF_LIBS[@]}"; do
    rm -rf "${cffmpeg_inc:?}/${l}"
    [[ -d "${INC_OUT}/${l}" ]] && cp -R "${INC_OUT}/${l}" "${cffmpeg_inc}/"
  done
fi

log "xcframeworks assembled in ${XCF_OUT}"
ls -1 "${XCF_OUT}"
