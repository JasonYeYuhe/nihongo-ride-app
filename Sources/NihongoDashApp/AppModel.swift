import Foundation
import Observation
import GameCore
import ReviewKit
import VocabKit

/// A snapshot of a finished run, shown on the results screen.
struct GameSummary: Equatable {
    var score: Int
    var maxCombo: Int
    var wordsCompleted: Int
    var accuracy: Double
    var distanceMeters: Double
    /// Distinct words that lapsed this run (skipped / hinted / many typos).
    var reviewWords: [VocabEntry]

    init(from session: GameSession) {
        score = session.score
        maxCombo = session.maxCombo
        wordsCompleted = session.wordsCompleted
        accuracy = session.accuracy
        distanceMeters = session.distanceMeters
        var seen = Set<String>()
        reviewWords = session.lapsedEntries.filter { seen.insert($0.id).inserted }
    }
}

/// Top-level app state: settings, the persistent SRS store, and which screen is showing.
@MainActor
@Observable
final class AppModel {
    enum Screen: Equatable { case menu, playing, results }

    var screen: Screen = .menu

    // Settings
    var languageCode: String = "en"      // "en" or "zh"
    var showRomajiHint: Bool = true
    var soundEnabled: Bool = true
    var selectedMode: GameMode = .journey
    /// Chosen JLPT level for new words; `nil` mixes all levels.
    var selectedLevel: JLPTLevel? = .n5

    private(set) var session: GameSession?
    private(set) var lastSummary: GameSummary?
    private(set) var reviewStore: ReviewStore

    private let storeURL: URL

    init() {
        storeURL = Self.defaultStoreURL()
        reviewStore = ReviewStore.load(from: storeURL)
    }

    /// Words currently waiting in the review deck (due now).
    var dueReviewCount: Int { reviewStore.dueCount() }
    var totalWordsSeen: Int { reviewStore.count }
    var totalWordsAvailable: Int { VocabStore.shared.entries.count }

    func startGame() {
        var config = GameSession.Config()
        config.languageCode = languageCode
        config.showRomajiHint = showRomajiHint
        config.level = selectedLevel
        config.mode = selectedMode
        if selectedMode == .timeAttack {
            config.timeLimit = 60
            config.newWordCount = 300   // plenty for a 60s sprint
            config.reviewWordCount = 0
        }
        session = GameSession.make(config: config, vocab: .shared, review: reviewStore)
        screen = .playing
    }

    /// Ends the current run, persists SRS progress, and shows results.
    func finishGame() {
        guard let session else { return }
        reviewStore = session.review
        try? reviewStore.save(to: storeURL)
        lastSummary = GameSummary(from: session)
        self.session = nil
        screen = .results
    }

    func backToMenu() {
        session = nil
        screen = .menu
    }

    private static func defaultStoreURL() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("NihongoDash", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("review.json")
    }
}
