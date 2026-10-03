// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "LiteRT",
  platforms: [
    .iOS(.v15)
  ],
  products: [
    .library(
      name: "LiteRT",
      targets: [
        "CLiteRT",
        "LiteRTMetalAccelerator"
      ]
    )
  ],
  targets: [
    .binaryTarget(
      name: "CLiteRT",
      path: "CLiteRT.xcframework"
    ),
    .binaryTarget(
      name: "LiteRTMetalAccelerator",
      path: "LiteRTMetalAccelerator.xcframework"
    )
  ]
)
