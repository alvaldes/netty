// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NettyKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "NettyKit", targets: ["NettyKit"]),
    ],
    targets: [
        .target(
            name: "NettyKit",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "NettyKitTests",
            dependencies: ["NettyKit"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
