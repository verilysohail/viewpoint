// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Viewpoint",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "Viewpoint",
            targets: ["Viewpoint"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "Viewpoint",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit")
            ],
            path: "Viewpoint",
            resources: [
                .process("Assets.xcassets")
            ]
        )
    ]
)
