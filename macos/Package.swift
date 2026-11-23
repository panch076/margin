// swift-tools-version: 6.2
import PackageDescription

// Margin for macOS. `MarginCore` is plain Foundation (question bank, test engine, scoring);
// `Margin` is the SwiftUI app; `CoreCheck` is a small self-test for the engine.
let package = Package(
    name: "Margin",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "MarginCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "Margin", dependencies: ["MarginCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "CoreCheck", dependencies: ["MarginCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
