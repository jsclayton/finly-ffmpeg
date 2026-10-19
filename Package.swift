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
      url: "https://github.com/jsclayton/finly-ffmpeg/releases/download/v9.0.1-5/libavutil.xcframework.zip",
      checksum: "d090c5ce8bca78c296c2c1e5b00b1f1215d55290f73a162bce52430596e2af63"),
    .binaryTarget(
      name: "libavcodec",
      url: "https://github.com/jsclayton/finly-ffmpeg/releases/download/v9.0.1-5/libavcodec.xcframework.zip",
      checksum: "fc87668a4ab38fb29c2c5d74ddc37ce928e626574a9f2d483234c69d3ed7cd2f"),
    .binaryTarget(
      name: "libavformat",
      url: "https://github.com/jsclayton/finly-ffmpeg/releases/download/v9.0.1-5/libavformat.xcframework.zip",
      checksum: "27ddd0fefee217df9d699cc053ae5a9acb32b24dae72f649ef7d09b1a4417118"),
    .binaryTarget(
      name: "libswresample",
      url: "https://github.com/jsclayton/finly-ffmpeg/releases/download/v9.0.1-5/libswresample.xcframework.zip",
      checksum: "a2407b3dffa43409c5c2777676ce3fe26954e44304a7129e286546aceda1566b"),
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
