// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.
import PackageDescription

let package = Package(
  name: "Vellum",
  platforms: [.macOS(.v13), .iOS(.v16), .visionOS(.v1)],
  products: [.library(name: "Vellum", targets: ["Vellum"])],
  targets: [
    .target(name: "Vellum", swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]),
    .testTarget(
      name: "VellumTests",
      dependencies: ["Vellum"],
      swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
    ),
  ],
  swiftLanguageModes: [.v6]
)
