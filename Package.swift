// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Kapture",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "KaptureKit", targets: ["KaptureKit"])
    ],
    targets: [
        .target(name: "KaptureKit"),
        .testTarget(name: "KaptureKitTests", dependencies: ["KaptureKit"])
    ]
)
