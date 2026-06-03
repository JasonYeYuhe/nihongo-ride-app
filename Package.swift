// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tabikana",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // Pure-Swift logic libraries (UI-independent, fully testable).
        .library(name: "RomajiKana", targets: ["RomajiKana"]),
        .library(name: "VocabKit", targets: ["VocabKit"]),
        .library(name: "ReviewKit", targets: ["ReviewKit"]),
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
                .copy("Resources/n5_starter.json")
            ]
        ),
        .testTarget(name: "VocabKitTests", dependencies: ["VocabKit"]),

        // MARK: Spaced repetition — simplified SM-2 over typing performance.
        .target(name: "ReviewKit"),
        .testTarget(name: "ReviewKitTests", dependencies: ["ReviewKit"]),
    ]
)
