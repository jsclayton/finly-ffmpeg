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
      url: "https://github.com/jsclayton/finly-ffmpeg/releases/download/v9.0.1-1/libavutil.xcframework.zip",
      checksum: "e84a17be045500a9b35fc5ea1edf521f066bce0651f6ddf9f71d655d8175f552"),
    .binaryTarget(
      name: "libavcodec",
      url: "https://github.com/jsclayton/finly-ffmpeg/releases/download/v9.0.1-1/libavcodec.xcframework.zip",
      checksum: "7b96c039d8e8c7865517e264e7d8a5e1499c8abe7073690052214b51d6551a32"),
    .binaryTarget(
      name: "libavformat",
      url: "https://github.com/jsclayton/finly-ffmpeg/releases/download/v9.0.1-1/libavformat.xcframework.zip",
      checksum: "84e84b8735567a77abcd920d139d67a6435c10f32f9d613a043720b8ae6376a0"),
    .binaryTarget(
      name: "libswresample",
      url: "https://github.com/jsclayton/finly-ffmpeg/releases/download/v9.0.1-1/libswresample.xcframework.zip",
      checksum: "c0b292dfdea01bf3048f65c5481a33fffb78a55509add4eb09934c58b852ffec"),
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
