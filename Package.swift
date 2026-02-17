// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VoiceInput",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
    ],
    targets: [
        .executableTarget(
            name: "VoiceInput",
            dependencies: ["WhisperKit"],
            path: "VoiceInput",
            exclude: ["Resources/Info.plist", "Resources/VoiceInput.entitlements"]
        ),
        // Tests require Xcode (XCTest/Testing module not in Command Line Tools)
        // .testTarget(
        //     name: "VoiceInputTests",
        //     dependencies: ["VoiceInput"],
        //     path: "VoiceInputTests"
        // ),
    ]
)
