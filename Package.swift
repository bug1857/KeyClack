// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KeyClack",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "KeyClack", targets: ["KeyClack"])
    ],
    targets: [
        .target(
            name: "KeyClackCore",
            path: "Sources/KeyClackCore"
        ),
        .executableTarget(
            name: "KeyClack",
            dependencies: ["KeyClackCore"],
            path: "Sources/KeyClack"
        ),
        .testTarget(
            name: "KeyClackTests",
            dependencies: ["KeyClackCore"],
            path: "Tests/KeyClackTests"
        )
    ]
)
