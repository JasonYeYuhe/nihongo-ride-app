// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NihongoDash",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // Pure-Swift logic libraries (UI-independent, fully testable).
        .library(name: "RomajiKana", targets: ["RomajiKana"]),
        .library(name: "VocabKit", targets: ["VocabKit"]),
        .library(name: "ReviewKit", targets: ["ReviewKit"]),
        .library(name: "GameCore", targets: ["GameCore"]),
        // The macOS SwiftUI app (Nihongo Dash). Run with `swift run NihongoDashApp`.
        .executable(name: "NihongoDashApp", targets: ["NihongoDashApp"]),
    ],
    targets: [
        // MARK: Engine — romaji→kana typing matcher.
        .target(
            name: "RomajiKana",
            resources: [
                // Google Mozc romaji table (BSD-3-Clause). See THIRD_PARTY_LICENSES.md.
                .copy("Resources/romaji-hiragana.tsv")
            ]
        ),
        .testTarget(name: "RomajiKanaTests", dependencies: ["RomajiKana"]),

        // MARK: Vocabulary — entries, multi-language meanings, JLPT levels, difficulty.
        .target(
            name: "VocabKit",
            dependencies: ["RomajiKana"],
            resources: [
                .copy("Resources/n5.json"),
                .copy("Resources/n4.json"),
                .copy("Resources/n3.json"),
                .copy("Resources/n2.json"),
                .copy("Resources/n1.json"),
                .copy("Resources/passages.json"),
            ]
        ),
        .testTarget(name: "VocabKitTests", dependencies: ["VocabKit"]),

        // MARK: Spaced repetition — simplified SM-2 over typing performance.
        .target(name: "ReviewKit"),
        .testTarget(name: "ReviewKitTests", dependencies: ["ReviewKit"]),

        // MARK: Game loop — word queue, scoring, SRS recording (UI-independent).
        .target(name: "GameCore", dependencies: ["RomajiKana", "VocabKit", "ReviewKit"]),
        .testTarget(name: "GameCoreTests", dependencies: ["GameCore"]),

        // MARK: SwiftUI app (Nihongo Dash) — bike-journey typing game + IME-bypassing key capture.
        .executableTarget(
            name: "NihongoDashApp",
            dependencies: ["RomajiKana", "VocabKit", "ReviewKit", "GameCore"],
            resources: [
                .copy("Resources/AppIcon.png")   // runtime dock icon (swift run); Xcode uses design/AppIcon.appiconset
            ]
        ),
    ]
)
