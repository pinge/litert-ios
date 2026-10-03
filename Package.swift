// swift-tools-version: 5.9

import PackageDescription

let release = "https://github.com/pinge/litert-ios/releases/download/v2.1.6"

let package = Package(
  name: "LiteRT",
  platforms: [
    .iOS(.v15),
  ],
  products: [
    .library(
      name: "LiteRT",
      targets: [
        "CLiteRT",
        "LiteRTMetalAccelerator",
      ]
    ),
  ],
  targets: [
    .binaryTarget(
      name: "CLiteRT",
      url: "\(release)/CLiteRT.xcframework.zip",
      checksum: "c59b79c8ddc4fade9ee4c6627214eddd08875c5427ee4333f276f7b2ced9aa2b"
    ),
    .binaryTarget(
      name: "LiteRTMetalAccelerator",
      url: "\(release)/LiteRTMetalAccelerator.xcframework.zip",
      checksum: "2b5dfc8ad30ceedf688d2685cdc28794b39863fe850f6d1bb7d74920596396f2"
    ),
  ]
)
