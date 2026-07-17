// swift-tools-version: 6.2
import PackageDescription

// finly-ffmpeg — a remux-scoped FFmpeg build for Apple platforms.
//
// This package vends the four dynamic-framework xcframeworks produced by
// ./build.sh, plus `CFFmpeg`: the C-interop module that surfaces the libav* API
// to Swift. CFFmpeg is the Swift-facing half of the *build*, not the engine —
// it carries only what Swift cannot see on its own (C bitfields and
// function-like macros, via the cff_* shims in include/CFFmpeg.h).
//
// The binary targets reference the locally built xcframeworks under artifacts/,
// which is gitignored: a fresh clone must run ./build.sh before this package
// will resolve. That is the intended shape while the repo is private —
// consumers use a local package override. Once the repo is public, a v* tag
// publishes the xcframework zips and these flip to .binaryTarget(url:checksum:)
// so consumers resolve without building FFmpeg themselves.

let package = Package(
  name: "finly-ffmpeg",
  platforms: [
    .iOS("26.0"),
    .tvOS("26.0"),
  ],
  products: [
    .library(name: "CFFmpeg", targets: ["CFFmpeg"])
  ],
  targets: [
    .binaryTarget(
      name: "libavutil",
      url: "https://github.com/jsclayton/finly-ffmpeg/releases/download/v8.1.2-2/libavutil.xcframework.zip",
      checksum: "1816ffc61781843dbf4ace7e5ee5e9c6643659d374325786911144bd44666f71"),
    .binaryTarget(
      name: "libavcodec",
      url: "https://github.com/jsclayton/finly-ffmpeg/releases/download/v8.1.2-2/libavcodec.xcframework.zip",
      checksum: "587de4decd16fa7cca88bc4796b56f57a00b5f9566e22e393304ef437378899f"),
    .binaryTarget(
      name: "libavformat",
      url: "https://github.com/jsclayton/finly-ffmpeg/releases/download/v8.1.2-2/libavformat.xcframework.zip",
      checksum: "ac3d4bc9c48eecc0ff70f50504541217283cd932bf7a2904d66445ee55a91bb7"),
    .binaryTarget(
      name: "libswresample",
      url: "https://github.com/jsclayton/finly-ffmpeg/releases/download/v8.1.2-2/libswresample.xcframework.zip",
      checksum: "69d6fdd7c016bccbcc287e8d6a0afbd2eec8e82a2ef86d208770d6f91661950a"),
    .target(
      name: "CFFmpeg",
      dependencies: ["libavutil", "libavcodec", "libavformat", "libswresample"],
      publicHeadersPath: "include",
      // The libav* dylibs record their system deps by absolute path, so
      // these are belt-and-suspenders for the SwiftPM link graph.
      linkerSettings: [
        .linkedLibrary("z"),
        .linkedLibrary("iconv"),
        .linkedFramework("CoreFoundation"),
        .linkedFramework("CoreMedia"),
        .linkedFramework("CoreVideo"),
      ]
    ),
  ],
  cLanguageStandard: .c11
)
