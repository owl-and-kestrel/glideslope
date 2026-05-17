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
  targets: [
    .executableTarget(
      name: "Glideslope",
      path: "Sources/Glideslope"
    )
  ]
)
