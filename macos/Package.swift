// swift-tools-version: 5.8
import PackageDescription

let package = Package(
    name: "VibeRemote",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "VibeRemote", targets: ["VibeRemote"]),
    ],
    targets: [
        .executableTarget(
            name: "VibeRemote",
            linkerSettings: [
                .linkedFramework("SwiftUI"),
                .linkedFramework("AppKit"),
                .linkedFramework("CryptoKit"),
                .linkedFramework("Network"),
            ]
        ),
    ]
)
