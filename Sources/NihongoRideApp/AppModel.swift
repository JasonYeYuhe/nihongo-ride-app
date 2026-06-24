import Foundation
import Observation
import GameCore
import JournalKit
import ReviewKit
import SettingsKit
import SyncKit
import VocabKit
import WordListsKit

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
    enum Screen: Equatable { case menu, playing, results, about, journal, settings, lists, listDetail, onboarding }

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
    /// User-curated word lists (v1.5). The v1.4 single "★ saved" deck survives as
    /// the one `isDefault` list (constant id `"default"`); all the old ★ behavior
    /// now reads/writes that list.
    private(set) var wordLists: WordListStore
    /// The list currently open in the detail screen.
    var selectedListID: String?
    /// Last word-list error from a path that has no local alert of its own (the
    /// in-game / results ★ tap). Surfaced by a RootView alert; cleared on dismiss.
    var lastListError: WordListError?
    /// Wall-clock start of the current run, for duration/WPM in the journal.
    private var runStartedAt: Date?

    /// Stable per-install id, used as this device's odometer slot key.
    var deviceID: String { settings.deviceID }

    /// Game Center — leaderboard + achievements. No-op until authenticated.
    let gameCenter = GameCenterManager()

    private let storeURL: URL
    private let journalURL: URL
    private let odometerURL: URL
    private let wordListsURL: URL
    /// Legacy v1.4 deck file — migration input only (preserved for rollback).
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
        wordListsURL = Self.supportFileURL("word-lists.json")
        savedWordsURL = Self.supportFileURL("saved-words.json")
        reviewStore = ReviewStore.load(from: storeURL)
        journal = RideJournal.load(from: journalURL)
        odometer = OdometerLog.load(from: odometerURL)
        // Word lists load via a corruption-aware, one-time migration from the
        // legacy saved-words deck; localized default name applied after settings
        // load below. Temporary empty store until then (no reads in between).
        wordLists = WordListStore()

        // Restore persisted settings (a fresh install gets sanitized defaults +
        // a freshly minted deviceID). `didSet` observers don't fire for
        // assignments made inside an initializer, so these don't trigger saves.
        // In screenshot-capture mode, start from clean defaults and never persist
        // (below): each render mutates this model's settings (mode/hints/level),
        // and persisting them would both corrupt the real install's settings and
        // make subsequent capture runs non-deterministic.
        let loaded = Screenshotter.isCapturing
            ? AppSettings.default.sanitized()
            : AppSettings.load(from: .standard)
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

        // Now that the language is resolved, load/migrate the word lists. Runs
        // before sync `start()` so the local store is shaped first and the first
        // cloud fetch merges into it (ids union + name LWW) rather than an empty
        // store overwriting the cloud (§A2).
        let migration = WordListStore.loadOrMigrate(
            wordListsURL: wordListsURL,
            legacySavedWordsURL: savedWordsURL,
            defaultName: Self.defaultListName(languageCode))
        wordLists = migration.store

        settingsLoaded = true

        // First-launch onboarding: show it only to a genuinely fresh install, and
        // never while capturing screenshots (would replace menu.png). An upgrading
        // user who already has data is silently marked as seen so they never get it.
        if !settings.hasSeenOnboarding && !Screenshotter.isCapturing {
            let freshInstall = reviewStore.count == 0 && journal.totalRuns == 0
            if freshInstall {
                screen = .onboarding           // didSet doesn't fire in init; navCount stays 0
            } else {
                settings.hasSeenOnboarding = true
            }
        }

        // Persist once so a fresh install writes back its minted deviceID (and the
        // onboarding flag above for upgrading users). Never in capture mode.
        if !Screenshotter.isCapturing { settings.save(to: .standard) }
        // Refresh the reminder schedule for the days ahead (no-op when off).
        refreshReminders()
        startSyncIfEnabled()
        gameCenter.authenticate()
    }

    /// Dismisses first-launch onboarding (finish or skip): records it as seen and
    /// drops to the menu. Onboarding deliberately does NOT request notifications —
    /// reminders stay opt-in from the settings screen.
    func finishOnboarding() {
        settings.hasSeenOnboarding = true
        settings.save(to: .standard)
        screen = .menu
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

    /// iCloud sync feature switch (v1.4: ON). The CloudKit container is created
    /// and assigned to the App ID; entitlements restored in project.yml. The
    /// controller no-ops gracefully when the user isn't signed in to iCloud, so
    /// this is safe even before the schema is deployed to Production.
    static let cloudSyncAvailable = true

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
                           wordLists incomingLists: [WordList] = [],
                           legacyDeck deckIDs: [String]? = nil) {
        if !incomingLists.isEmpty {
            wordLists = SyncMerge.wordLists(wordLists, WordListStore(lists: incomingLists))
            // Compaction runs ONLY here — after a successful cloud merge — never on
            // the load path: a not-yet-propagated deletion compacted too early gets
            // revived by a peer's union on the next fetch (§A2 / WordListStore docs).
            wordLists.compactTombstones()
            try? wordLists.save(to: wordListsURL)
        }
        // Legacy v1.4 `SavedWords:deck` record: fold into the default list once,
        // then never again (the persisted flag in foldLegacyDeck enforces "once").
        if let deckIDs { foldLegacyDeck(deckIDs) }
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
        guard settingsLoaded, !Screenshotter.isCapturing else { return }
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

    // MARK: Word lists (v1.5) — the default list is the old ★ "saved" deck.

    /// Localized display name for the default "★" list. The UI also overrides the
    /// label for `isDefault` lists, so the *stored* name is only a fallback.
    static func defaultListName(_ languageCode: String) -> String {
        languageCode == "zh" ? "★ 收藏" : "★ Saved"
    }

    /// Active (non-deleted) lists, default first.
    var activeLists: [WordList] { wordLists.activeLists }
    func list(id: String) -> WordList? { wordLists.list(id: id) }

    // ★ favorites — the default list, preserving the v1.4 surface API.
    var savedCount: Int { wordLists.defaultList?.ids.count ?? 0 }
    func isSaved(_ id: String) -> Bool { wordLists.defaultContains(id) }
    /// Active lists that contain `vocabID` — drives the "add to lists" checkmarks.
    func listIDs(containing vocabID: String) -> [String] { wordLists.listIDs(containing: vocabID) }

    /// How many of a list's words resolve to a vocab entry on THIS device. A list
    /// whose ids all came from a richer/newer device (via union sync) can be
    /// non-empty yet have 0 playable words — the play button must reflect that
    /// instead of being a silent dead tap.
    func playableCount(in list: WordList) -> Int {
        list.ids.reduce(0) { $0 + (VocabStore.shared.entry(id: $1) != nil ? 1 : 0) }
    }

    /// Toggles a word in the default ★ list and persists. All word-list writes run
    /// synchronously on the main actor (small file) so they stay ordered with the
    /// sync-merge writes to the same file — `Task.detached` raced last-writer-wins.
    func toggleSaved(_ id: String) { lastListError = toggleWord(id, in: WordList.defaultID) }

    /// Toggles a word in any list, persists, and enqueues that list for sync.
    /// Returns the resulting error (cap reached) for the UI to surface, else nil.
    @discardableResult
    func toggleWord(_ vocabID: String, in listID: String) -> WordListError? {
        switch wordLists.toggle(vocabID, in: listID) {
        case .success: persistWordLists(changed: [listID]); return nil
        case .failure(let error): return error
        }
    }

    @discardableResult
    func addWord(_ vocabID: String, to listID: String) -> WordListError? {
        switch wordLists.addWord(vocabID, to: listID) {
        case .success: persistWordLists(changed: [listID]); return nil
        case .failure(let error): return error
        }
    }

    func removeWord(_ vocabID: String, from listID: String) {
        if case .success = wordLists.removeWord(vocabID, from: listID) {
            persistWordLists(changed: [listID])
        }
    }

    @discardableResult
    func createList(name: String) -> Result<WordList, WordListError> {
        let result = wordLists.createList(name: name)
        if case .success(let list) = result { persistWordLists(changed: [list.id]) }
        return result
    }

    @discardableResult
    func renameList(_ listID: String, to name: String) -> WordListError? {
        switch wordLists.rename(listID, to: name) {
        case .success: persistWordLists(changed: [listID]); return nil
        case .failure(let error): return error
        }
    }

    /// Soft-deletes a list (tombstone propagates; default list can't be deleted).
    @discardableResult
    func deleteList(_ listID: String) -> WordListError? {
        switch wordLists.softDelete(listID) {
        case .success:
            if selectedListID == listID { selectedListID = nil }
            persistWordLists(changed: [listID])
            return nil
        case .failure(let error): return error
        }
    }

    func clearList(_ listID: String) {
        if case .success = wordLists.clear(listID) { persistWordLists(changed: [listID]) }
    }

    /// Persists the word-list store synchronously + atomically, then tells the
    /// sync controller which list ids changed (no-op when sync is off).
    private func persistWordLists(changed listIDs: [String]) {
        try? wordLists.save(to: wordListsURL)
        syncController?.recordLocalChanges(listIDs: listIDs)
    }

    /// Starts a journey run drawn from the default ★ list. (Back-compat entry used
    /// by the menu chip / star UI.)
    func startSavedGame() { startListGame(WordList.defaultID) }

    /// Starts a journey run drawn from a list. Resolves ids first and bails if none
    /// resolve to a vocab entry — otherwise an all-unresolvable list (ids synced
    /// from a richer/newer device, or stale after a vocab change) would strand the
    /// player on a blank, already-finished game screen (v1.4 regression, per list).
    func startListGame(_ listID: String) {
        guard let list = wordLists.list(id: listID), !list.deleted else { return }
        let resolvable = list.ids.filter { VocabStore.shared.entry(id: $0) != nil }
        guard !resolvable.isEmpty else { return }
        var config = GameSession.Config()
        config.languageCode = languageCode
        config.showRomajiHint = showRomajiHint
        config.mode = .journey
        session = GameSession.makeSaved(
            ids: resolvable, vocab: .shared, review: reviewStore, config: config)
        runStartedAt = Date()
        screen = .playing
    }

    // MARK: Legacy deck mirror + sync snapshots

    /// All list ids including tombstoned ones — so a deletion also enqueues its
    /// record. Used by the sync controller's full re-enqueue.
    var allWordListIDs: [String] { wordLists.lists.map(\.id) }

    /// Value snapshot of the lists by id (Sendable) for the off-actor record
    /// provider in `nextRecordZoneChangeBatch`.
    var wordListsByID: [String: WordList] {
        Dictionary(wordLists.lists.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// Folds the legacy v1.4 `SavedWords:deck` ids into the default list (union).
    ///
    /// Runs on **every** fetch of the deck — the deck is a permanent v1.4-compat
    /// mirror of the default list (the controller re-writes it whenever the default
    /// changes), so a still-v1.4 peer's later ★ additions keep arriving instead of
    /// being lost after a one-time window (the data-loss the adversarial review
    /// caught). Union add-wins is exactly the cross-device semantics the default
    /// list already has v1.5↔v1.5 — per-word un-save does not propagate (documented
    /// MVP behavior) — so there is no resurrection asymmetry, and union reaches a
    /// fixpoint so there is no ping-pong.
    private func foldLegacyDeck(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        let before = wordLists.defaultList?.ids
        for id in ids { _ = wordLists.addWord(id, to: WordList.defaultID) }
        if wordLists.defaultList?.ids != before {
            try? wordLists.save(to: wordListsURL)
            // A v1.4 addition changed our default → propagate to v1.5 peers (and the
            // controller refreshes the deck mirror because the default id is included).
            syncController?.recordLocalChanges(listIDs: [WordList.defaultID])
        }
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
                                 totalRuns: lifetimeRuns)
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
        // Save on the main actor (small files) so these stay ordered with the
        // sync-merge writes to the same files — a detached write could land after
        // a fetch-merge write and clobber merged cloud data (last-writer-wins).
        try? journal.save(to: journalURL)
        try? odometer.save(to: odometerURL)
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
        let fm = FileManager.default
        // Screenshot capture redirects ALL file I/O to a throwaway temp dir, so a
        // headless render never reads or writes the machine's real data. (Capture
        // models mint a fresh deviceID and run startGame/finishGame, which would
        // otherwise pollute the real, iCloud-synced odometer/journal/word-lists —
        // and leak the real review queue into store screenshots.)
        let base: URL = Screenshotter.isCapturing
            ? fm.temporaryDirectory.appendingPathComponent("NihongoRideCapture", isDirectory: true)
            : (fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory)
        let dir = base.appendingPathComponent("NihongoRide", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }
}
