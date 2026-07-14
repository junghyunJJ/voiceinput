// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "VoiceInput",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(
            url: "https://github.com/argmaxinc/argmax-oss-swift.git",
            exact: "1.0.0"
        ),
    ],
    targets: [
        .executableTarget(
            name: "VoiceInput",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift")
            ],
            path: "VoiceInput",
            exclude: ["Resources/Info.plist", "Resources/VoiceInput.entitlements"]
        ),
        .testTarget(
            name: "VoiceInputTests",
            dependencies: ["VoiceInput"],
            path: "VoiceInputTests"
        ),
    ]
)
