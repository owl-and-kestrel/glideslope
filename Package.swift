// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "Glideslope",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(name: "Glideslope", targets: ["Glideslope"])
  ],
  dependencies: [
    .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.9.4")
  ],
  targets: [
    .executableTarget(
      name: "Glideslope",
      dependencies: [
        .product(name: "Sparkle", package: "Sparkle")
      ],
      path: "Sources/Glideslope"
    ),
    .testTarget(
      name: "GlideslopeTests",
      dependencies: ["Glideslope"],
      path: "Tests/GlideslopeTests"
    )
  ]
)
