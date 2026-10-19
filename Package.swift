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
      url: "https://github.com/jsclayton/finly-ffmpeg/releases/download/v9.0.2-1/libavutil.xcframework.zip",
      checksum: "0c4885f948eb0b9c1c150f6fc984da7f661f790773d68c25ba0407937515de24"),
    .binaryTarget(
      name: "libavcodec",
      url: "https://github.com/jsclayton/finly-ffmpeg/releases/download/v9.0.2-1/libavcodec.xcframework.zip",
      checksum: "02da918e92dcc6641d378f09e0ce11acbd5a76bbcf3421129fbab66b18eb96d6"),
    .binaryTarget(
      name: "libavformat",
      url: "https://github.com/jsclayton/finly-ffmpeg/releases/download/v9.0.2-1/libavformat.xcframework.zip",
      checksum: "71b94400880b7d0869931be88dce9448218e2bc09dbb22692fa7439f628ead89"),
    .binaryTarget(
      name: "libswresample",
      url: "https://github.com/jsclayton/finly-ffmpeg/releases/download/v9.0.2-1/libswresample.xcframework.zip",
      checksum: "6ca6dd0cbbe3160c233e1da9fbe0b7381b50a52e68c1a0e7c4ad0f3067dfd330"),
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
