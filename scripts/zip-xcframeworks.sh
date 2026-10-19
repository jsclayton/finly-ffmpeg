#!/usr/bin/env bash
#
# zip-xcframeworks.sh — zip the four xcframeworks exactly as a release uploads them.
#
#   bash scripts/zip-xcframeworks.sh <out-dir>
#
# Writes <out-dir>/<lib>.xcframework.zip for each library in
# artifacts/xcframework/, and prints one line per zip on stdout:
#
#   <lib>.xcframework.zip  <checksum>
#
# where the checksum is `swift package compute-checksum`'s. release.sh calls
# this script and writes those checksums into Package.swift, so a run here
# makes the exact bytes a release would upload, without releasing.
#
# Each zip has the .xcframework directory at its root (ditto --keepParent), the
# layout SwiftPM's binaryTarget unpacker requires; each slice's dSYM rides
# inside. ditto runs with --norsrc --noextattr --noacl, so no resource fork,
# extended attribute or ACL goes in. (--sequesterRsrc would store each file's
# extended attributes, such as com.apple.provenance, as an AppleDouble `._`
# file under `__MACOSX/`, and every consumer would unpack them as stray files.)
# A zip that holds a `__MACOSX/` or `._` entry anyway, or any entry outside its
# .xcframework directory, is refused.

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

[[ $# -eq 1 && -n "$1" ]] || die "usage: zip-xcframeworks.sh <out-dir>"
OUT_DIR="$1"

for tool in ditto zipinfo swift; do
  command -v "${tool}" >/dev/null || die "${tool} not found"
done

XCF_DIR="${ARTIFACTS_DIR}/xcframework"
for lib in "${FF_LIBS[@]}"; do
  [[ -d "${XCF_DIR}/${lib}.xcframework" ]] \
    || die "missing ${XCF_DIR}/${lib}.xcframework — run ./build.sh"
done

mkdir -p "${OUT_DIR}"

for lib in "${FF_LIBS[@]}"; do
  zip="${OUT_DIR}/${lib}.xcframework.zip"
  rm -f "${zip}"
  ditto -c -k --norsrc --noextattr --noacl --keepParent "${XCF_DIR}/${lib}.xcframework" "${zip}" \
    || die "ditto failed for ${zip}"

  entries="$(zipinfo -1 "${zip}")" || die "zipinfo cannot read ${zip}"
  [[ -n "${entries}" ]] || die "${zip} is empty"
  appledouble="$(echo "${entries}" | grep -E '(^|/)(__MACOSX/|\._)' || true)"
  [[ -z "${appledouble}" ]] \
    || die "${zip} holds $(echo "${appledouble}" | wc -l | tr -d ' ') AppleDouble entries, first: $(echo "${appledouble}" | head -1)"
  outside="$(echo "${entries}" | grep -v "^${lib}\.xcframework/" || true)"
  [[ -z "${outside}" ]] || die "${zip} holds entries outside ${lib}.xcframework/, first: $(echo "${outside}" | head -1)"

  sum="$(swift package compute-checksum "${zip}")" || die "compute-checksum failed for ${zip}"
  [[ "${sum}" =~ ^[0-9a-f]{64}$ ]] || die "compute-checksum printed '${sum}' for ${zip}"
  echo "${lib}.xcframework.zip  ${sum}"
done
