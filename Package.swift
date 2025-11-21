// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "VPDownloader",
    platforms: [
        .iOS(.v15),
        .macOS(.v13),
        .tvOS(.v15),
        .watchOS(.v8)
    ],
    products: [
        .library(
            name: "VPDownloader",
            targets: ["VPDownloader"]
        ),
    ],
    targets: [
        .target(
            name: "VPDownloader"
        ),
        .testTarget(
            name: "VPDownloaderTests",
            dependencies: ["VPDownloader"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
