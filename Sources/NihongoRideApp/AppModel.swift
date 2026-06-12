import Foundation
import Observation
import GameCore
import JournalKit
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
    enum Screen: Equatable { case menu, playing, results, about, journal }

    var screen: Screen = .menu {
        didSet { navCount += 1 }
    }
    /// Monotonic navigation counter. RootView uses it as the screen's zIndex so
    /// the incoming screen always stacks ABOVE the outgoing one mid-transition —
    /// otherwise the dying screen (still hit-testable for ~0.4s) swallows taps
    /// meant for the new screen's buttons.
    private(set) var navCount = 0

    // Settings
    var languageCode: String = "en"      // "en" or "zh"
    var showRomajiHint: Bool = true
    var soundEnabled: Bool = true
    var selectedMode: GameMode = .journey
    /// Chosen JLPT level for new words; `nil` mixes all levels.
    var selectedLevel: JLPTLevel? = .n5
    /// In Practice mode: cycle whole passages (true) or stream individual words (false).
    var practicePassages: Bool = true
    var practicePassageLevel: Passage.Level = .med

    private(set) var session: GameSession?
    private(set) var lastSummary: GameSummary?
    private(set) var reviewStore: ReviewStore
    private(set) var journal: RideJournal
    /// Wall-clock start of the current run, for duration/WPM in the journal.
    private var runStartedAt: Date?

    private let storeURL: URL
    private let journalURL: URL

    init() {
        storeURL = Self.supportFileURL("review.json")
        journalURL = Self.supportFileURL("history.json")
        reviewStore = ReviewStore.load(from: storeURL)
        journal = RideJournal.load(from: journalURL)
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
        switch selectedMode {
        case .timeAttack:
            config.timeLimit = 60
            config.newWordCount = 300   // plenty for a 60s sprint
            config.reviewWordCount = 0
        case .practice:
            config.newWordCount = practicePassages ? 12 : 30
            config.reviewWordCount = 0
        case .journey:
            break
        }
        if selectedMode == .practice && practicePassages {
            session = GameSession.makePractice(level: practicePassageLevel, config: config)
        } else {
            session = GameSession.make(config: config, vocab: .shared, review: reviewStore)
        }
        runStartedAt = Date()
        screen = .playing
    }

    /// Ends the current run, persists SRS progress (except for Practice, which
    /// uses a transient SRS store), logs the run to the ride journal, and shows
    /// results. Practice mode skips the score screen and returns to the menu.
    func finishGame() {
        guard let session else { return }
        let wasPractice = session.mode == .practice
        if !wasPractice {                          // never overwrite real SRS with a practice run
            reviewStore = session.review
            try? reviewStore.save(to: storeURL)
        }
        lastSummary = GameSummary(from: session)
        logRun(session)
        self.session = nil
        screen = wasPractice ? .menu : .results
    }

    func backToMenu() {
        session = nil
        runStartedAt = nil
        screen = .menu
    }

    /// Appends the finished run to the ride journal and persists it. Runs with
    /// nothing typed at all (abandoned immediately) aren't worth remembering.
    private func logRun(_ session: GameSession) {
        guard session.wordsCompleted > 0 || session.correctKeystrokes > 0 else {
            runStartedAt = nil
            return
        }
        let now = Date()
        let duration = runStartedAt.map { now.timeIntervalSince($0) } ?? 0
        // Same WPM convention as PracticeView's live readout: a run shorter
        // than 2s (or with no correct keys) has no meaningful speed.
        let wpm = (duration < 2 || session.correctKeystrokes == 0)
            ? 0
            : (Double(session.correctKeystrokes) / 5.0) / (duration / 60)
        let level: String
        if session.mode == .practice && practicePassages {
            level = practicePassageLevel.rawValue
        } else {
            level = session.config.level?.label ?? "all"
        }
        var seen = Set<String>()
        let lapsed = session.lapsedEntries.filter { seen.insert($0.id).inserted }.count
        journal.append(RideRecord(
            date: now,
            mode: session.mode.rawValue,
            level: level,
            score: session.score,
            wpm: wpm,
            accuracy: session.accuracy,
            wordsCompleted: session.wordsCompleted,
            lapsed: lapsed,
            distanceMeters: session.distanceMeters,
            duration: duration
        ))
        // Snapshot + background write: RideJournal is a Sendable value type,
        // so the copy is immune to later mutations on the main actor.
        let snapshot = journal
        let url = journalURL
        Task.detached(priority: .utility) {
            try? snapshot.save(to: url)
        }
        runStartedAt = nil
    }

    /// Fills the in-memory journal with a believable two-week history for
    /// headless screenshot rendering ONLY. Never persisted: nothing here calls
    /// `save`, and the screenshot process exits without finishing a run.
    func seedDemoJournal() {
        var demo = RideJournal()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let wpms: [Double] = [16, 18, 17, 20, 22, 21, 24, 23, 26, 28, 27, 30, 29, 32]
        for (index, wpm) in wpms.enumerated() {
            // Most days ridden, two rest days — streak ends up 4.
            let daysAgo = wpms.count - 1 - index
            if daysAgo == 4 || daysAgo == 9 { continue }
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
            demo.append(RideRecord(
                date: day.addingTimeInterval(9 * 3600 + Double(index) * 600),
                mode: index % 3 == 2 ? "practice" : (index % 3 == 1 ? "timeAttack" : "journey"),
                level: index % 3 == 2 ? "med" : "N5",
                score: index % 3 == 2 ? 0 : 180 + index * 14,
                wpm: wpm,
                accuracy: 0.88 + Double(index % 5) * 0.025,
                wordsCompleted: 10 + index,
                lapsed: max(0, 3 - index / 4),
                distanceMeters: Double(200 + index * 18),
                duration: 240
            ))
        }
        journal = demo
    }

    private static func supportFileURL(_ name: String) -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("NihongoRide", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }
}
