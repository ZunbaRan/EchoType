// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EchoType",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "EchoType", targets: ["EchoType"]),
    ],
    targets: [
        .executableTarget(
            name: "EchoType",
            path: "Sources/EchoType",
            linkerSettings: [
                .linkedFramework("AppKit"),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
