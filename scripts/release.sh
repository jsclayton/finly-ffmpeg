#!/usr/bin/env bash
#
# release.sh — cut a finly-ffmpeg release from the LOCALLY BUILT artifacts.
#
# The local build is the artifact of record: it is the one the engine's test
# suite and the simulator smoke test actually verified. The checksums written
# into Package.swift must match the exact bytes uploaded as release assets, so
# a CI rebuild must never publish (ci.yml is a reproducibility check only).
#
# Versioning: v{FFMPEG_VERSION}-{N}, N incrementing per FFmpeg version and
# resetting on an FFmpeg bump (8.1.2-1, 8.1.2-2, 8.1.3-1, ...). The hyphen
# makes the tag a semver PRE-RELEASE, which is deliberate: consumers pin
# `.exact` (a binary-artifact package should be bumped on purpose, not by
# range resolution).
#
# What it does, in order:
#   1. next N from existing v{VER}-* tags
#   2. zip the four xcframeworks (ditto --keepParent: .xcframework at zip root,
#      the layout SwiftPM requires) + collect the LGPL bundle
#   3. swift package compute-checksum per zip
#   4. rewrite Package.swift's binaryTargets to url:checksum: for this tag
#   5. commit, tag, push main + tag
#   6. gh release create with the zips, the LGPL bundle, and checksums.txt
#
# Requires: a clean tree, artifacts/ from a ./build.sh run, gh authenticated.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FF_LIBS=(libavutil libavcodec libavformat libswresample)

VER="$(sed -n 's/^FFMPEG_VERSION="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' scripts/config.sh | head -1)"
[[ -n "$VER" ]] || { echo "could not read FFMPEG_VERSION from scripts/config.sh" >&2; exit 1; }

[[ -z "$(git status --porcelain)" ]] || { echo "working tree not clean" >&2; exit 1; }
for lib in "${FF_LIBS[@]}"; do
  [[ -d "artifacts/xcframework/${lib}.xcframework" ]] \
    || { echo "missing artifacts/xcframework/${lib}.xcframework — run ./build.sh" >&2; exit 1; }
done
LGPL_TAR="$(ls artifacts/lgpl/*.tar.gz 2>/dev/null | head -1)"
[[ -n "$LGPL_TAR" ]] || { echo "missing LGPL bundle tar.gz — run ./build.sh" >&2; exit 1; }

# Next N for this FFmpeg version (tags fetched so a stale local clone can't reuse one).
git fetch --tags --quiet
last=$(git tag -l "v${VER}-*" | sed -n "s/^v${VER}-\([0-9]*\)$/\1/p" | sort -n | tail -1)
N=$(( ${last:-0} + 1 ))
TAG="v${VER}-${N}"
echo "==> releasing ${TAG}"

DIST="build/dist-${TAG}"
rm -rf "$DIST"; mkdir -p "$DIST"

# Zip each xcframework with the .xcframework directory at the zip ROOT — the
# layout SwiftPM's binaryTarget unpacker requires.
declare -a CHECKSUMS=()
for lib in "${FF_LIBS[@]}"; do
  ditto -c -k --sequesterRsrc --keepParent \
    "artifacts/xcframework/${lib}.xcframework" "$DIST/${lib}.xcframework.zip"
  sum="$(swift package compute-checksum "$DIST/${lib}.xcframework.zip")"
  CHECKSUMS+=("$sum")
  echo "    ${lib}.xcframework.zip  ${sum}"
done
cp "$LGPL_TAR" "$DIST/"
( cd "$DIST" && shasum -a 256 * > checksums.txt )

# Rewrite the four binaryTargets to url:checksum for this tag. Matches both the
# path: form (first release) and a previous url: form (subsequent releases).
BASE="https://github.com/jsclayton/finly-ffmpeg/releases/download/${TAG}"
python3 - "$TAG" "$BASE" "${CHECKSUMS[@]}" <<'PY'
import re, sys
tag, base = sys.argv[1], sys.argv[2]
sums = dict(zip(["libavutil", "libavcodec", "libavformat", "libswresample"], sys.argv[3:]))
s = open("Package.swift").read()
for lib, sum_ in sums.items():
    new = (f'.binaryTarget(\n      name: "{lib}",\n'
           f'      url: "{base}/{lib}.xcframework.zip",\n'
           f'      checksum: "{sum_}"),')
    pat = re.compile(
        r'\.binaryTarget\(\s*name:\s*"' + lib + r'",\s*(?:path:\s*"[^"]*"|url:\s*"[^"]*",\s*checksum:\s*"[^"]*")\s*\),')
    s, n = pat.subn(new, s)
    assert n == 1, f"binaryTarget for {lib}: {n} matches"
open("Package.swift", "w").write(s)
print("Package.swift -> url:checksum for", tag)
PY

swift package dump-package > /dev/null || { echo "manifest broken after rewrite" >&2; exit 1; }

git add Package.swift
git commit -q -m "release ${TAG}: binaryTargets -> this tag's release assets"
git tag "$TAG"
git push origin main "$TAG"

gh release create "$TAG" \
  --title "${TAG} — FFmpeg ${VER}, patches 0001–0004" \
  --notes-file "$DIST/checksums.txt" \
  "$DIST"/*.xcframework.zip "$DIST"/*.tar.gz "$DIST/checksums.txt"

echo "==> ${TAG} published"
