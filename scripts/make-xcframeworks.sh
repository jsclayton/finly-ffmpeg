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
#
# Each slice carries its framework's dSYM (<slice>/dSYMs/<lib>.framework.dSYM,
# named by DebugSymbolsPath in the xcframework's Info.plist), so crashes inside
# these libraries can be symbolicated. The shipped binaries are stripped to
# their exported symbols; the dSYM is written from the unstripped binary first.
#
# Each framework also carries a privacy manifest (PrivacyInfo.xcprivacy, at the
# bundle root), copied from scripts/privacy/<lib>.xcprivacy. The build checks
# every manifest against the binary it ships with; see check_privacy_manifest.
#
# No file in an xcframework, binary, dSYM or plist, may carry this checkout's
# path or the builder's home directory; see check_no_build_paths.

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

INSTALL_ROOT="${BUILD_DIR}/install"
FWROOT="${BUILD_DIR}/frameworks"
XCF_OUT="${ARTIFACTS_DIR}/xcframework"
INC_OUT="${ARTIFACTS_DIR}/include"
PRIVACY_DIR="${CONFIG_DIR}/privacy"

for tool in install_name_tool dsymutil dwarfdump strip nm plutil; do
  command -v "${tool}" >/dev/null || die "${tool} not found"
done

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

# write a framework binary's dSYM. dsymutil warns, and still exits 0, for every
# object file in the debug map it cannot read: the dSYM it writes then silently
# lacks those files' DWARF. So any warning is fatal here.
#
# dsymutil also writes a relocation map per arch,
# Contents/Resources/Relocations/<arch>/<lib>.yml, whose binary-path is the
# absolute path of the binary it read. The map is input for linking a mergeable
# library into a client's binary; these are dynamic frameworks built without
# -make_mergeable, so nothing can use it, and symbolication reads only
# Contents/Resources/DWARF. It is removed, so no dSYM carries the build path.
make_dsym() { # binary, dsym, label
  local binary="$1" dsym="$2" label="$3" out
  rm -rf "${dsym}"
  out="$(dsymutil "${binary}" -o "${dsym}" 2>&1)" || { echo "${out}" >&2; die "dsymutil failed for ${label}"; }
  if [[ -n "${out}" ]]; then
    echo "${out}" | head -20 >&2
    die "dsymutil warned for ${label}: the dSYM would be incomplete"
  fi
  rm -rf "${dsym}/Contents/Resources/Relocations"
}

# the binary and its dSYM must carry the same UUID for every arch, or a crash
# report from the binary can never be matched to the dSYM.
check_uuids() { # binary, dsym, label
  local bin_uuids dsym_uuids
  bin_uuids="$(dwarfdump --uuid "$1" | awk '{print $2, $3}' | sort)"
  dsym_uuids="$(dwarfdump --uuid "$2" | awk '{print $2, $3}' | sort)"
  [[ -n "${bin_uuids}" && "${bin_uuids}" == "${dsym_uuids}" ]] \
    || die "UUID mismatch for $3: binary [${bin_uuids}] vs dSYM [${dsym_uuids}]"
}

# --- build paths ---------------------------------------------------------------
# A path from the machine that built a library must not ship in it: not this
# checkout's root (configure's string, the debug info, dsymutil's relocation
# map), and not the builder's home, which also covers a CI runner's home. A
# toolchain installed under the home (an Xcode in ~/Applications) fails here
# too, on purpose: configure records --cc and --sysroot, so its path would be in
# every binary. build-ffmpeg.sh maps the paths out of the debug info and
# rewrites them out of configure's string, and make_dsym drops the relocation
# map; this is the check that it worked, on every file of each assembled
# xcframework: each slice's framework and dSYM, whole, and the Info.plist.
check_no_build_paths() { # xcframework, label
  local xcf="$1" label="$2" needle hits status file first
  local needles=("${ROOT_DIR}")
  if [[ -n "${HOME:-}" && "${HOME}" != "/" ]]; then needles+=("${HOME}"); fi
  for needle in "${needles[@]}"; do
    status=0
    hits="$(LC_ALL=C grep -r -a -l -F -- "${needle}" "${xcf}")" || status=$?
    # grep: 0 is a hit, 1 is none, anything else is a file it could not read
    [[ "${status}" -le 1 ]] || die "${label}: grep could not read every file in $(basename "${xcf}")"
    if [[ "${status}" -eq 0 ]]; then
      file="$(echo "${hits}" | head -1)"
      first="$(LC_ALL=C strings -a "${file}" | LC_ALL=C grep -m1 -F -- "${needle}" | cut -c1-200 || true)"
      die "${label}: $(echo "${hits}" | wc -l | tr -d ' ') file(s) hold the build path ${needle}, first ${file#"${xcf}/"}: ${first}"
    fi
  done
}

# --- privacy manifests -------------------------------------------------------
# Apple requires a privacy manifest in every framework that calls a "required
# reason" API, declaring each API category it uses and why. An app's own
# manifest cannot cover a framework's use. The reasons in scripts/privacy/ are
# chosen by a person; the build never picks one. It checks that the categories
# a manifest declares are exactly the categories its binary imports, so an
# FFmpeg bump that starts calling a listed API fails here instead of shipping
# undeclared, and a manifest cannot declare an API its binary does not call.

# Apple's required-reason C functions, by category ("Describing use of required
# reason API", developer.apple.com). The 64-suffixed names are the same calls
# under their older symbols. The getattrlist family is listed under both
# FileTimestamp and DiskSpace, so which one it is for is a person's decision:
# the check refuses to guess.
api_category() { # C function name -> category, "ambiguous", or nothing
  case "$1" in
    stat|fstat|fstatat|lstat|stat64|fstat64|lstat64)
      echo "NSPrivacyAccessedAPICategoryFileTimestamp" ;;
    statfs|statvfs|fstatfs|fstatvfs|statfs64|fstatfs64)
      echo "NSPrivacyAccessedAPICategoryDiskSpace" ;;
    mach_absolute_time)
      echo "NSPrivacyAccessedAPICategorySystemBootTime" ;;
    getattrlist|getattrlistbulk|fgetattrlist|getattrlistat)
      echo "ambiguous" ;;
  esac
}

# the categories a binary imports, sorted and unique, one per line. Reads every
# arch of a fat binary; drops the leading underscore and any $-suffix
# ($INODE64, $UNIX2003) from each undefined symbol.
imported_categories() { # binary, label
  local syms fn category
  syms="$(nm -u -j -arch all "$1")" || die "nm failed for $2"
  for fn in $(echo "${syms}" | sed -n 's/^_//p' | sed 's/\$.*//' | sort -u); do
    category="$(api_category "${fn}")"
    [[ "${category}" != "ambiguous" ]] \
      || die "$2 imports ${fn}: ambiguous, decide FileTimestamp or DiskSpace in its manifest and in api_category"
    [[ -z "${category}" ]] || echo "${category}"
  done | sort -u
}

# Apple's reasons for each category the check knows. The build never picks
# one; it only refuses a reason that does not belong to its category.
allowed_reasons() { # category -> its reason codes, space-separated
  case "$1" in
    NSPrivacyAccessedAPICategoryFileTimestamp)  echo "DDA9.1 C617.1 3B52.1 0A2A.1" ;;
    NSPrivacyAccessedAPICategoryDiskSpace)      echo "85F4.1 E174.1 7D9E.1 B728.1" ;;
    NSPrivacyAccessedAPICategorySystemBootTime) echo "35F9.1 8FFB.1 3D61.1" ;;
  esac
}

# a key path holds a value of the given plist type. `plutil -extract raw`
# prints an array's count and any other value as itself, so the type is
# checked first.
require_type() { # manifest, key path, type, label
  [[ "$(plutil -type "$2" "$1" 2>/dev/null)" == "$3" ]] || die "$4: $2 must be of type $3"
}

# the categories a manifest declares, sorted, one per line. Each names at least
# one reason, and every reason is one of Apple's for that category.
declared_categories() { # manifest, label
  local count i category key reasons j reason
  require_type "$1" NSPrivacyAccessedAPITypes array "$2"
  count="$(plutil -extract NSPrivacyAccessedAPITypes raw "$1")"
  for ((i = 0; i < count; i++)); do
    key="NSPrivacyAccessedAPITypes.${i}"
    require_type "$1" "${key}.NSPrivacyAccessedAPIType" string "$2"
    require_type "$1" "${key}.NSPrivacyAccessedAPITypeReasons" array "$2"
    category="$(plutil -extract "${key}.NSPrivacyAccessedAPIType" raw "$1")"
    reasons="$(plutil -extract "${key}.NSPrivacyAccessedAPITypeReasons" raw "$1")"
    [[ "${reasons}" -gt 0 ]] || die "$2: ${category} gives no reason"
    for ((j = 0; j < reasons; j++)); do
      require_type "$1" "${key}.NSPrivacyAccessedAPITypeReasons.${j}" string "$2"
      reason="$(plutil -extract "${key}.NSPrivacyAccessedAPITypeReasons.${j}" raw "$1")"
      [[ " $(allowed_reasons "${category}") " == *" ${reason} "* ]] \
        || die "$2: ${reason} is not one of Apple's reasons for ${category}"
    done
    echo "${category}"
  done | sort
}

# a manifest lints, tracks nothing, collects nothing, and declares exactly the
# required-reason categories its binary imports.
check_privacy_manifest() { # binary, manifest, label
  local binary="$1" manifest="$2" label="$3" imported declared
  [[ -f "${manifest}" ]] || die "no privacy manifest for ${label}"
  plutil -lint -s "${manifest}" || die "privacy manifest for ${label} does not lint"
  require_type "${manifest}" NSPrivacyTracking bool "${label}"
  require_type "${manifest}" NSPrivacyTrackingDomains array "${label}"
  require_type "${manifest}" NSPrivacyCollectedDataTypes array "${label}"
  [[ "$(plutil -extract NSPrivacyTracking raw "${manifest}")" == "false" ]] \
    || die "privacy manifest for ${label}: NSPrivacyTracking must be false"
  [[ "$(plutil -extract NSPrivacyTrackingDomains raw "${manifest}")" == "0" ]] \
    || die "privacy manifest for ${label}: NSPrivacyTrackingDomains must be empty"
  [[ "$(plutil -extract NSPrivacyCollectedDataTypes raw "${manifest}")" == "0" ]] \
    || die "privacy manifest for ${label}: NSPrivacyCollectedDataTypes must be empty"
  # each helper has already said why when it fails
  imported="$(imported_categories "${binary}" "${label}")" || exit 1
  declared="$(declared_categories "${manifest}" "${label}")" || exit 1
  [[ "${declared}" == "$(echo "${declared}" | sort -u)" ]] \
    || die "privacy manifest for ${label} declares a category twice: [${declared//$'\n'/, }]"
  [[ "${imported}" == "${declared}" ]] \
    || die "privacy manifest for ${label} declares [${declared//$'\n'/, }] but the binary imports [${imported//$'\n'/, }]"
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

    # dSYM from the final binary (fat for the simulator slices, so it covers
    # every arch in it), while the debug map still points at the object files
    # in build/obj; then strip the shipped binary to its exported symbols.
    dsym="${FWROOT}/${slice}/${lib}.framework.dSYM"
    make_dsym "${local_bin}" "${dsym}" "${lib}/${slice}"
    strip -x "${local_bin}" || die "strip failed for ${lib}/${slice}"
    check_uuids "${local_bin}" "${dsym}" "${lib}/${slice}"

    write_info_plist "${fwdir}/Info.plist" "${lib}" "${slice}"
    # the manifest goes in before the seal, so the signature covers it
    cp "${PRIVACY_DIR}/${lib}.xcprivacy" "${fwdir}/PrivacyInfo.xcprivacy" \
      || die "no privacy manifest at scripts/privacy/${lib}.xcprivacy"
    check_privacy_manifest "${local_bin}" "${fwdir}/PrivacyInfo.xcprivacy" "${lib}/${slice}"
    # a framework that fails to sign stops the build: an unsigned framework
    # would still assemble into the xcframework
    out="$(codesign --force --sign - --timestamp=none "${fwdir}" 2>&1)" \
      || { echo "${out}" >&2; die "codesign failed for ${lib}/${slice}: ${lib}.framework is not signed"; }

    xcf_args+=(-framework "${fwdir}" -debug-symbols "${dsym}")
  done

  xcodebuild -create-xcframework "${xcf_args[@]}" \
    -output "${XCF_OUT}/${lib}.xcframework" >/dev/null \
    || die "xcodebuild -create-xcframework failed for ${lib}"
  # the path check reads the bytes that go into the zip, so first make sure they
  # are all there: one binary and one dSYM DWARF file per slice
  xcf="${XCF_OUT}/${lib}.xcframework"
  shopt -s nullglob
  bins=("${xcf}"/*/"${lib}.framework/${lib}")
  dwarfs=("${xcf}"/*/dSYMs/"${lib}.framework.dSYM/Contents/Resources/DWARF/${lib}")
  shopt -u nullglob
  [[ ${#bins[@]} -eq ${#FF_SLICES[@]} && ${#dwarfs[@]} -eq ${#FF_SLICES[@]} ]] \
    || die "${lib}.xcframework holds ${#bins[@]} binaries and ${#dwarfs[@]} dSYMs, expected ${#FF_SLICES[@]} of each"
  check_no_build_paths "${xcf}" "${lib}"
  # and each framework's seal holds on the copy in the xcframework, the one the
  # zip carries
  for fw in "${xcf}"/*/"${lib}.framework"; do
    out="$(codesign --verify --strict "${fw}" 2>&1)" \
      || { echo "${out}" >&2; die "codesign --verify failed for ${fw#"${XCF_OUT}/"}: its seal does not hold"; }
  done
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
