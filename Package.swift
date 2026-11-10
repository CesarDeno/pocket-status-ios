// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PocketStatus",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0"),
    ],
    products: [
        .library(
            name: "PocketStatus",
            targets: ["PocketStatus"]
        ),
    ],
    targets: [
        .target(
            name: "PocketStatus"
        ),
    ]
)

