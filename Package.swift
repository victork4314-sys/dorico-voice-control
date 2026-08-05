// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DoricoVoiceControl",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "DoricoVoiceCore", targets: ["DoricoVoiceCore"]),
        .executable(name: "DoricoVoiceControl", targets: ["DoricoVoiceControl"])
    ],
    targets: [
        .target(name: "DoricoVoiceCore"),
        .executableTarget(name: "DoricoVoiceControl", dependencies: ["DoricoVoiceCore"]),
        .testTarget(name: "DoricoVoiceCoreTests", dependencies: ["DoricoVoiceCore"])
    ]
)
