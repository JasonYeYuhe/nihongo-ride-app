import Foundation
import Observation
import GameCore
import JournalKit
import ReviewKit
import SavedWordsKit
import SettingsKit
import SyncKit
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

extension GameSummary {
    /// How well a run went. Single source of truth shared by the results screen
    /// and the Game Center "Flawless Run" achievement (so the badge the player
    /// sees and the achievement they earn never disagree).
    enum Grade { case flawless, steady, building, lap }

    var grade: Grade {
        let clean = reviewWords.isEmpty
        if accuracy >= 0.97 && clean && maxCombo >= max(5, wordsCompleted - 1) {
            return .flawless
        }
        if accuracy >= 0.90 && reviewWords.count <= 2 { return .steady }
        if accuracy >= 0.75 && wordsCompleted > 0 { return .building }
        return .lap
    }
}

/// Top-level app state: settings, the persistent SRS store, and which screen is showing.
@MainActor
@Observable
final class AppModel {
    enum Screen: Equatable { case menu, playing, results, about, journal, settings }

    var screen: Screen = .menu {
        didSet { navCount += 1 }
    }
    /// Monotonic navigation counter. RootView uses it as the screen's zIndex so
    /// the incoming screen always stacks ABOVE the outgoing one mid-transition —
    /// otherwise the dying screen (still hit-testable for ~0.4s) swallows taps
    /// meant for the new screen's buttons.
    private(set) var navCount = 0

    // Settings. Each persists on change (v1.2 — before this they only lived in
    // memory and reset to defaults on every launch). `didSet` doesn't fire during
    // init, so applying loaded values below is free; `settingsLoaded` guards any
    // re-entrancy and skips writes until the initial load is in place.
    var languageCode: String = "en" { didSet { persistSettings() } }      // "en" or "zh"
    var showRomajiHint: Bool = true { didSet { persistSettings() } }
    var soundEnabled: Bool = true { didSet { persistSettings() } }
    var selectedMode: GameMode = .journey { didSet { persistSettings() } }
    /// Chosen JLPT level for new words; `nil` mixes all levels.
    var selectedLevel: JLPTLevel? = .n5 { didSet { persistSettings() } }
    /// In Practice mode: cycle whole passages (true) or stream individual words (false).
    var practicePassages: Bool = true { didSet { persistSettings() } }
    var practicePassageLevel: Passage.Level = .med { didSet { persistSettings() } }

    // v1.2 settings.
    /// Sync SRS + ride history through the user's private iCloud (CloudKit).
    var iCloudSyncEnabled: Bool = true { didSet { persistSettings(); syncEnabledChanged() } }
    /// Daily local reminder when SRS cards are due (default off; opt-in).
    var dueReminderEnabled: Bool = false { didSet { persistSettings(); refreshReminders() } }
    /// Hour-of-day (0…23) the due reminder fires.
    var dueReminderHour: Int = 20 { didSet { persistSettings(); refreshReminders() } }

    /// Live iCloud sync state, surfaced on the settings screen.
    enum SyncStatus: Equatable { case off, waiting, syncing, synced, noAccount, error(String) }
    private(set) var syncStatus: SyncStatus = .off

    private(set) var session: GameSession?
    private(set) var lastSummary: GameSummary?
    private(set) var reviewStore: ReviewStore
    private(set) var journal: RideJournal
    /// Lifetime odometer as a per-device G-Counter — the iCloud-sync vehicle for
    /// lifetime totals (sums correctly across devices; see SyncKit.OdometerLog).
    private(set) var odometer: OdometerLog
    /// User-curated "saved words" deck (v1.4).
    private(set) var savedWords: SavedWordsStore
    /// Wall-clock start of the current run, for duration/WPM in the journal.
    private var runStartedAt: Date?

    /// Stable per-install id, used as this device's odometer slot key.
    var deviceID: String { settings.deviceID }

    /// Game Center — leaderboard + achievements. No-op until authenticated.
    let gameCenter = GameCenterManager()

    private let storeURL: URL
    private let journalURL: URL
    private let odometerURL: URL
    private let savedWordsURL: URL

    /// The persisted settings blob. Also carries the install `deviceID` and the
    /// v1.2 sync/reminder toggles that don't have dedicated UI yet (Phase B).
    private var settings: AppSettings = .default
    /// Until the initial load is applied, skip per-field persistence.
    private var settingsLoaded = false

    init() {
        storeURL = Self.supportFileURL("review.json")
        journalURL = Self.supportFileURL("history.json")
        odometerURL = Self.supportFileURL("odometer.json")
        savedWordsURL = Self.supportFileURL("saved-words.json")
        reviewStore = ReviewStore.load(from: storeURL)
        journal = RideJournal.load(from: journalURL)
        odometer = OdometerLog.load(from: odometerURL)
        savedWords = SavedWordsStore.load(from: savedWordsURL)

        // Restore persisted settings (a fresh install gets sanitized defaults +
        // a freshly minted deviceID). `didSet` observers don't fire for
        // assignments made inside an initializer, so these don't trigger saves.
        let loaded = AppSettings.load(from: .standard)
        settings = loaded
        languageCode = loaded.languageCode
        showRomajiHint = loaded.showRomajiHint
        soundEnabled = loaded.soundEnabled
        selectedMode = GameMode(rawValue: loaded.selectedMode) ?? .journey
        selectedLevel = loaded.selectedLevel.flatMap { JLPTLevel(rawValue: $0) }
        practicePassages = loaded.practicePassages
        practicePassageLevel = Passage.Level(rawValue: loaded.practicePassageLevel) ?? .med
        iCloudSyncEnabled = loaded.iCloudSyncEnabled
        dueReminderEnabled = loaded.dueReminderEnabled
        dueReminderHour = loaded.dueReminderHour

        // One-time odometer backfill: seed this device's slot from the existing
        // journal lifetime so totals stay correct for users upgrading to v1.2
        // (and so this device contributes its real history once sync turns on).
        if odometer.slots[settings.deviceID] == nil && journal.totalRuns > 0 {
            odometer.setSlot(.init(words: journal.totalWords,
                                   distanceMeters: journal.totalDistanceMeters,
                                   runs: journal.totalRuns),
                             for: settings.deviceID)
            try? odometer.save(to: odometerURL)
        }

        // Dev-only: pin the UI language for screenshot captures (not persisted).
        if let lang = ProcessInfo.processInfo.environment["NIHONGO_UILANG"],
           ["en", "zh"].contains(lang) {
            languageCode = lang
        }

        settingsLoaded = true
        // Persist once so a fresh install writes back its minted deviceID.
        settings.save(to: .standard)
        // Refresh the reminder schedule for the days ahead (no-op when off).
        refreshReminders()
        startSyncIfEnabled()
        gameCenter.authenticate()
    }

    /// Reschedules due reminders for the next few days from the current SRS
    /// state. Called on launch, whenever the reminder preference changes, after a
    /// run (the due count moved), and when the app becomes active. If the user
    /// turned reminders on but denied the system prompt, the toggle flips back.
    func refreshReminders() {
        guard ReminderScheduler.isAvailable else { return }   // dev / screenshot: skip
        let enabled = dueReminderEnabled
        let store = reviewStore
        let hour = dueReminderHour
        let lang = languageCode
        Task { [weak self] in
            let scheduled = await ReminderScheduler.apply(
                enabled: enabled, store: store, hour: hour, languageCode: lang)
            if enabled && !scheduled {
                self?.dueReminderEnabled = false   // denied / unavailable
            }
        }
    }

    /// iCloud sync feature switch. Deferred to v1.4: the CloudKit code is
    /// complete + compile-verified, but the CloudKit container + schema + a
    /// 2-device verification aren't done yet, so it stays off (controller never
    /// starts, Settings card hidden) and the iCloud entitlement is omitted from
    /// the build. Flip to `true` + restore the iCloud entitlements to ship it.
    static let cloudSyncAvailable = false

    /// The iCloud sync controller (nil when sync is off / CloudKit unavailable,
    /// e.g. under `swift run`). Owned here; created lazily when sync is enabled.
    private var syncController: CloudKitSyncController?

    private func startSyncIfEnabled(fullResync: Bool = false) {
        guard Self.cloudSyncAvailable else { syncStatus = .off; return }
        guard iCloudSyncEnabled else { syncStatus = .off; return }
        guard let controller = CloudKitSyncController(model: self) else {
            syncStatus = .off          // CloudKit unavailable (dev / no entitlement)
            return
        }
        syncController = controller
        syncStatus = .waiting
        Task { await controller.start(fullResync: fullResync) }
    }

    /// Reacts to the iCloud sync toggle.
    private func syncEnabledChanged() {
        if iCloudSyncEnabled {
            // Re-enabling: push everything, since edits made while off aren't tracked.
            startSyncIfEnabled(fullResync: true)
        } else {
            syncController?.stop()
            syncController = nil
            syncStatus = .off
        }
    }

    /// App returned to the foreground: refresh reminders and pull/push sync.
    func appBecameActive() {
        refreshReminders()
        if let syncController { Task { await syncController.syncNow() } }
    }

    /// Called by the sync controller to surface live state in the UI.
    func updateSyncStatus(_ status: SyncStatus) { syncStatus = status }

    /// Merges cloud changes into the local stores (via the tested SyncKit merges)
    /// and persists. Called by the sync controller when records arrive.
    func applyCloudChanges(cards: [SRSCard] = [], records: [RideRecord] = [],
                           odometerSlots: [String: OdometerLog.Slot] = [:],
                           savedWords incomingSaved: SavedWordsStore? = nil) {
        if let incomingSaved {
            savedWords = SyncMerge.savedWords(savedWords, incomingSaved)
            let snapshot = savedWords
            let url = savedWordsURL
            Task.detached(priority: .utility) { try? snapshot.save(to: url) }
        }
        if !cards.isEmpty {
            let remote = ReviewStore(cards: Dictionary(cards.map { ($0.id, $0) },
                                                       uniquingKeysWith: { a, _ in a }))
            reviewStore = SyncMerge.reviewStores(reviewStore, remote)
            try? reviewStore.save(to: storeURL)
            refreshReminders()
        }
        if !records.isEmpty {
            // Display lifetime comes from the odometer, so rebuilding the journal
            // from merged records here can't undercount the odometer totals.
            let merged = SyncMerge.rideRecords(journal.records, records)
            journal = RideJournal(records: merged)
            try? journal.save(to: journalURL)
        }
        if !odometerSlots.isEmpty {
            var remote = OdometerLog()
            for (id, slot) in odometerSlots { remote.setSlot(slot, for: id) }
            odometer = SyncMerge.odometers(odometer, remote)
            try? odometer.save(to: odometerURL)
        }
    }

    /// Mirrors the live settings into the persisted blob and writes it. Cheap
    /// (a single UserDefaults write); called on each settings mutation.
    private func persistSettings() {
        guard settingsLoaded else { return }
        settings.languageCode = languageCode
        settings.showRomajiHint = showRomajiHint
        settings.soundEnabled = soundEnabled
        settings.selectedMode = selectedMode.rawValue
        settings.selectedLevel = selectedLevel?.rawValue
        settings.practicePassages = practicePassages
        settings.practicePassageLevel = practicePassageLevel.rawValue
        settings.iCloudSyncEnabled = iCloudSyncEnabled
        settings.dueReminderEnabled = dueReminderEnabled
        settings.dueReminderHour = dueReminderHour
        settings.save(to: .standard)
    }

    /// Words currently waiting in the review deck (due now).
    var dueReviewCount: Int { reviewStore.dueCount() }
    var totalWordsSeen: Int { reviewStore.count }
    var totalWordsAvailable: Int { VocabStore.shared.entries.count }

    // Lifetime totals prefer the cross-device odometer (G-Counter) but never show
    // less than the local journal's own accumulation (equal on a single device).
    var lifetimeWords: Int { max(journal.totalWords, odometer.totalWords) }
    var lifetimeDistanceMeters: Double { max(journal.totalDistanceMeters, odometer.totalDistanceMeters) }
    var lifetimeRuns: Int { max(journal.totalRuns, odometer.totalRuns) }

    // MARK: Saved words (v1.4)

    var savedCount: Int { savedWords.count }
    func isSaved(_ id: String) -> Bool { savedWords.contains(id) }

    /// Toggles a word's saved state and persists in the background.
    func toggleSaved(_ id: String) {
        savedWords.toggle(id)
        let snapshot = savedWords
        let url = savedWordsURL
        Task.detached(priority: .utility) { try? snapshot.save(to: url) }
        syncController?.recordLocalChanges(
            srsIDs: [], rideRecordIDs: [], odometerChanged: false, savedChanged: true)
    }

    /// Starts a journey run drawn from the saved-words deck. No-op if empty.
    func startSavedGame() {
        guard !savedWords.isEmpty else { return }
        var config = GameSession.Config()
        config.languageCode = languageCode
        config.showRomajiHint = showRomajiHint
        config.mode = .journey
        session = GameSession.makeSaved(
            ids: savedWords.ids, vocab: .shared, review: reviewStore, config: config)
        runStartedAt = Date()
        screen = .playing
    }

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
        var changedSRS: [String] = []
        if !wasPractice {                          // never overwrite real SRS with a practice run
            // Diff old vs new so sync pushes exactly the cards that changed.
            let oldCards = reviewStore.cards
            changedSRS = session.review.cards.compactMap { id, card in
                oldCards[id] != card ? id : nil
            }
            reviewStore = session.review
            try? reviewStore.save(to: storeURL)
            refreshReminders()                     // the due count just changed
        }
        lastSummary = GameSummary(from: session)
        let appended = logRun(session)
        // Tell the iCloud sync controller what changed (no-op when sync off).
        syncController?.recordLocalChanges(
            srsIDs: changedSRS,
            rideRecordIDs: appended.map { [$0.id] } ?? [],
            odometerChanged: appended != nil)
        // Game Center: submit score + achievements for real (non-practice) runs.
        if !wasPractice, let summary = lastSummary {
            gameCenter.recordRun(summary: summary, mode: session.mode,
                                 lifetimeWords: lifetimeWords,
                                 streakDays: journal.streakDays(),
                                 totalRuns: journal.totalRuns)
        }
        self.session = nil
        screen = wasPractice ? .menu : .results
    }

    func backToMenu() {
        session = nil
        runStartedAt = nil
        screen = .menu
    }

    /// Appends the finished run to the ride journal + odometer and persists them.
    /// Returns the appended record, or nil for an abandoned run (nothing typed)
    /// that isn't worth remembering.
    @discardableResult
    private func logRun(_ session: GameSession) -> RideRecord? {
        guard session.wordsCompleted > 0 || session.correctKeystrokes > 0 else {
            runStartedAt = nil
            return nil
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
        let record = RideRecord(
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
        )
        journal.append(record)
        // This device's lifetime odometer slot (the cross-device sync vehicle).
        odometer.record(deviceID: deviceID,
                        words: session.wordsCompleted,
                        distanceMeters: session.distanceMeters)
        // Snapshot + background write: both are Sendable value types, so the
        // copies are immune to later mutations on the main actor.
        let snapshot = journal
        let url = journalURL
        let odoSnapshot = odometer
        let odoURL = odometerURL
        Task.detached(priority: .utility) {
            try? snapshot.save(to: url)
            try? odoSnapshot.save(to: odoURL)
        }
        runStartedAt = nil
        return record
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

    static func supportFileURL(_ name: String) -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("NihongoRide", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }
}
