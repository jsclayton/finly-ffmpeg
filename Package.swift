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
      url: "https://github.com/jsclayton/finly-ffmpeg/releases/download/v8.1.2-1/libavutil.xcframework.zip",
      checksum: "6ee2acd4d8defbb643891939e78072a734e7b3dd018bb011958e72c10772d011"),
    .binaryTarget(
      name: "libavcodec",
      url: "https://github.com/jsclayton/finly-ffmpeg/releases/download/v8.1.2-1/libavcodec.xcframework.zip",
      checksum: "fe9e79ea29d21a9397b9432609f046e816b627763ff2fa54bb2a24a47f0322bd"),
    .binaryTarget(
      name: "libavformat",
      url: "https://github.com/jsclayton/finly-ffmpeg/releases/download/v8.1.2-1/libavformat.xcframework.zip",
      checksum: "831b30ead65696c7a64e2c18f5a1d9b1d6bf2a31f2ead63c136a8506cb6355e6"),
    .binaryTarget(
      name: "libswresample",
      url: "https://github.com/jsclayton/finly-ffmpeg/releases/download/v8.1.2-1/libswresample.xcframework.zip",
      checksum: "9da5b6e06f6ba7b3c88863b64698278c5d501a8762ab7b9aa1d6e476e6352c8b"),
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
