// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VoiceInput",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "VoiceInputCore",
            targets: ["VoiceInputCore"]
        ),
        .executable(
            name: "VoiceInput",
            targets: ["VoiceInput"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
    ],
    targets: [
        .target(
            name: "VoiceInputCore",
            path: "VoiceInputCore",
            exclude: ["Resources/Info.plist"]
        ),
        .executableTarget(
            name: "VoiceInput",
            dependencies: [
                "VoiceInputCore",
                "WhisperKit",
            ],
            path: "VoiceInput",
            exclude: ["Resources/Info.plist", "Resources/VoiceInput.entitlements"]
        ),
        // Tests use Swift Testing. Run them through Xcode for the full target matrix.
        .testTarget(
            name: "VoiceInputCoreTests",
            dependencies: ["VoiceInputCore"],
            path: "VoiceInputCoreTests"
        ),
        .testTarget(
            name: "VoiceInputTests",
            dependencies: ["VoiceInput"],
            path: "VoiceInputTests"
        ),
    ]
)
