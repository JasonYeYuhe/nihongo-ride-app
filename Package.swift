// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NihongoRide",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        // Pure-Swift logic libraries (UI-independent, fully testable).
        .library(name: "RomajiKana", targets: ["RomajiKana"]),
        .library(name: "VocabKit", targets: ["VocabKit"]),
        .library(name: "ReviewKit", targets: ["ReviewKit"]),
        .library(name: "GameCore", targets: ["GameCore"]),
        .library(name: "JournalKit", targets: ["JournalKit"]),
        .library(name: "SettingsKit", targets: ["SettingsKit"]),
        .library(name: "SyncKit", targets: ["SyncKit"]),
        .library(name: "NotificationKit", targets: ["NotificationKit"]),
        .library(name: "SavedWordsKit", targets: ["SavedWordsKit"]),
        // The macOS SwiftUI app (Nihongo Ride). Run with `swift run NihongoRideApp`.
        .executable(name: "NihongoRideApp", targets: ["NihongoRideApp"]),
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

        // MARK: Ride journal — append-only run history + streak/trend analytics.
        .target(name: "JournalKit"),
        .testTarget(name: "JournalKitTests", dependencies: ["JournalKit"]),

        // MARK: App settings — Codable settings blob + UserDefaults persistence (v1.2).
        .target(name: "SettingsKit"),
        .testTarget(name: "SettingsKitTests", dependencies: ["SettingsKit"]),

        // MARK: iCloud sync core — pure merge of SRS / history / odometer / saved (v1.2 Phase A, +v1.4).
        .target(name: "SyncKit", dependencies: ["ReviewKit", "JournalKit", "SavedWordsKit"]),
        .testTarget(name: "SyncKitTests", dependencies: ["SyncKit"]),

        // MARK: SRS due-reminder scheduling — pure planner over the review store (v1.2 Phase A).
        .target(name: "NotificationKit", dependencies: ["ReviewKit"]),
        .testTarget(name: "NotificationKitTests", dependencies: ["NotificationKit"]),

        // MARK: Saved-words deck — user-curated vocab list (v1.4 feature core).
        .target(name: "SavedWordsKit"),
        .testTarget(name: "SavedWordsKitTests", dependencies: ["SavedWordsKit"]),

        // MARK: SwiftUI app (Nihongo Ride) — bike-journey typing game + IME-bypassing key capture.
        .executableTarget(
            name: "NihongoRideApp",
            dependencies: ["RomajiKana", "VocabKit", "ReviewKit", "GameCore", "JournalKit", "SettingsKit", "SyncKit", "NotificationKit", "SavedWordsKit"],
            resources: [
                .copy("Resources/AppIcon.png")   // runtime dock icon (swift run); Xcode uses design/AppIcon.appiconset
            ]
        ),
    ]
)
