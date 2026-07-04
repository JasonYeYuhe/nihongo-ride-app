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
        .library(name: "WordListsKit", targets: ["WordListsKit"]),
        .library(name: "ConjugationKit", targets: ["ConjugationKit"]),
        .library(name: "ConjugationReviewKit", targets: ["ConjugationReviewKit"]),
        .library(name: "SpeechKit", targets: ["SpeechKit"]),
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
        // Depends on ConjugationKit for the v1.6 conjugation mode (vc→VerbClass mapping
        // + ConjugationSession). The app reaches CK transitively through GameCore, so the
        // app target / project.yml need no direct CK dependency (PLAN-V1.6 §4).
        .target(name: "GameCore", dependencies: ["RomajiKana", "VocabKit", "ReviewKit", "ConjugationKit"]),
        .testTarget(name: "GameCoreTests", dependencies: ["GameCore"]),

        // MARK: Ride journal — append-only run history + streak/trend analytics.
        .target(name: "JournalKit"),
        .testTarget(name: "JournalKitTests", dependencies: ["JournalKit"]),

        // MARK: App settings — Codable settings blob + UserDefaults persistence (v1.2).
        .target(name: "SettingsKit"),
        .testTarget(name: "SettingsKitTests", dependencies: ["SettingsKit"]),

        // MARK: iCloud sync core — pure merge of SRS / history / odometer / saved / word-lists (v1.2 Phase A, +v1.4, +v1.5).
        .target(name: "SyncKit", dependencies: ["ReviewKit", "JournalKit", "SavedWordsKit", "WordListsKit"]),
        .testTarget(name: "SyncKitTests", dependencies: ["SyncKit"]),

        // MARK: SRS due-reminder scheduling — pure planner over the review store (v1.2 Phase A).
        .target(name: "NotificationKit", dependencies: ["ReviewKit"]),
        .testTarget(name: "NotificationKitTests", dependencies: ["NotificationKit"]),

        // MARK: Saved-words deck — user-curated vocab list (v1.4 feature core).
        .target(name: "SavedWordsKit"),
        .testTarget(name: "SavedWordsKitTests", dependencies: ["SavedWordsKit"]),

        // MARK: Word lists — N named user-curated lists w/ CRUD, caps, corruption-aware
        // migration, tombstones (v1.5 Workstream A). Zero deps (pure module).
        .target(name: "WordListsKit"),
        .testTarget(name: "WordListsKitTests", dependencies: ["WordListsKit"]),

        // MARK: Verb conjugation engine — pure kana conjugator + lemma exceptions
        // (v1.5 Workstream B; zero deps, golden-tested). Output is transient, never
        // persisted as a VocabEntry.
        .target(name: "ConjugationKit"),
        .testTarget(name: "ConjugationKitTests", dependencies: ["ConjugationKit"]),

        // MARK: Conjugation SRS — spaced repetition for (verb, form) pairs (v1.8 §B).
        // A deliberate ZERO-dependency sibling of ReviewKit (parallel SM-2 card, Option A):
        // its own store + file + CKRecord, so a conjugation lapse can never leak into the
        // flat vocab journey due-queue. GameCore must NOT depend on this (red line §6):
        // the app (AppModel) owns the store and hands GameCore only plain data/closures.
        .target(name: "ConjugationReviewKit"),
        .testTarget(name: "ConjugationReviewKitTests", dependencies: ["ConjugationReviewKit"]),

        // MARK: Text-to-speech — @MainActor AVSpeechSynthesizer wrapper for on-demand
        // kana read-aloud (v1.8 §D). A leaf module; the app depends on it directly.
        .target(name: "SpeechKit"),
        .testTarget(name: "SpeechKitTests", dependencies: ["SpeechKit"]),

        // MARK: Derived verb-class data path — conservation invariants + end-to-end
        // golden over the real vc-stamped vocab JSON (v1.6 B1, PLAN-V1.6 §3 layer-ii).
        // Imports VocabKit (the data) + ConjugationKit (the engine); vc is mapped via
        // VerbClass(rawValue:) — no extra dependency edge.
        .testTarget(name: "ConjugationDataTests", dependencies: ["VocabKit", "ConjugationKit"]),

        // MARK: SwiftUI app (Nihongo Ride) — bike-journey typing game + IME-bypassing key capture.
        .executableTarget(
            name: "NihongoRideApp",
            dependencies: ["RomajiKana", "VocabKit", "ReviewKit", "GameCore", "JournalKit", "SettingsKit", "SyncKit", "NotificationKit", "SavedWordsKit", "WordListsKit", "ConjugationReviewKit", "SpeechKit"],
            resources: [
                .copy("Resources/AppIcon.png")   // runtime dock icon (swift run); Xcode uses design/AppIcon.appiconset
            ]
        ),
    ]
)
