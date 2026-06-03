// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TypingApp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        // The romaji→kana typing engine. Pure Swift, zero UI dependencies,
        // reusable by the (future) SwiftUI app, CLI tools, and tests.
        .library(name: "RomajiKana", targets: ["RomajiKana"]),
    ],
    targets: [
        .target(
            name: "RomajiKana",
            resources: [
                // Google Mozc romaji table (BSD-3-Clause). See THIRD_PARTY_LICENSES.md.
                .copy("Resources/romaji-hiragana.tsv")
            ]
        ),
        .testTarget(
            name: "RomajiKanaTests",
            dependencies: ["RomajiKana"]
        ),
    ]
)
