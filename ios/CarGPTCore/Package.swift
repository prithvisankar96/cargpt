// swift-tools-version: 6.0

// Platform-independent logic shared by the app. Kept separate so `swift test`
// runs on any machine, including Linux CI, without the iOS SDK.

import PackageDescription

let package = Package(
    name: "CarGPTCore",
    platforms: [.iOS("26.4"), .macOS(.v14)],
    products: [
        .library(name: "CarGPTCore", targets: ["CarGPTCore"]),
    ],
    targets: [
        .target(name: "CarGPTCore"),
        .testTarget(name: "CarGPTCoreTests", dependencies: ["CarGPTCore"]),
    ]
)
