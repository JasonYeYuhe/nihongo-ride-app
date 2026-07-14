import Foundation
import Observation
import GameCore
import JournalKit
import ReviewKit
import SettingsKit
import SyncKit
import VocabKit
import WordListsKit
import ConjugationReviewKit
import SpeechKit

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

/// A snapshot of a finished conjugation drill (no SRS / distance / review list — the
/// drill never touches the review store).
struct ConjugationSummary: Equatable {
    var score: Int
    var maxCombo: Int
    var promptsCompleted: Int
    var promptCount: Int
    var accuracy: Double

    init(from session: ConjugationSession) {
        score = session.score
        maxCombo = session.maxCombo
        promptsCompleted = session.promptsCompleted
        promptCount = session.promptCount
        accuracy = session.accuracy
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

    // v1.7 settings (pure-local; no SRS / cloud state).
    /// Which verb-conjugation forms to drill, as `ConjugationForm` raw values.
    /// Empty = all forms. Mapped to typed forms (dropping unknowns) at the drill
    /// boundary via `ConjugationSession.Config.setForms(rawValues:)`.
    var conjugationForms: [String] = [] { didSet { persistSettings() } }

    // v1.8 settings.
    /// Whether verb-conjugation drills record to the separate conjugation SRS store.
    /// Default true (the drill is a learning tool now). The weak-words cram / Practice /
    /// example-sentence drills NEVER write it — only the conjugation drill does.
    var conjugationSRSEnabled: Bool = true { didSet { persistSettings() } }
    /// Read-aloud (TTS) of the card kana. Opt-in (default off). Turning it off cancels
    /// any in-flight utterance.
    var ttsEnabled: Bool = false { didSet { persistSettings(); if !ttsEnabled { speech.stop() } } }
    /// AVSpeech utterance rate (SpeechKit clamps it to the valid range).
    var ttsRate: Float = 0.5 { didSet { persistSettings() } }

    /// Live iCloud sync state, surfaced on the settings screen.
    enum SyncStatus: Equatable { case off, waiting, syncing, synced, noAccount, error(String) }
    private(set) var syncStatus: SyncStatus = .off

    private(set) var session: GameSession?
    private(set) var lastSummary: GameSummary?
    /// The verb-conjugation drill (v1.6). A SEPARATE session type that holds no SRS/vocab
    /// state, so the "conjugation never writes SRS" red line is structural. When this is
    /// non-nil the `.playing` / `.results` screens render the conjugation variants.
    private(set) var conjugationSession: ConjugationSession?
    private(set) var lastConjugationSummary: ConjugationSummary?
    /// True while the results screen is showing a conjugation drill (vs a ride).
    private(set) var resultsAreConjugation = false
    private(set) var reviewStore: ReviewStore
    /// The verb-conjugation SRS store (v1.8 §B) — a SEPARATE store, file, and CKRecord
    /// from the flat `reviewStore` (red line §1): a conjugation lapse (keyed `sourceID#form`)
    /// must never flow into the vocab journey due-queue. Owned here by AppModel (GameCore
    /// stays ignorant of it); written only via a conjugation drill's `onOutcome` sink.
    private(set) var conjugationReviewStore: ConjugationReviewStore
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
    /// Last failure to persist a USER-INITIATED data change (list CRUD, ★). Surfaced
    /// once by a RootView alert so silent data loss is visible. Background/auto writes
    /// only log (no alert — could loop). Cleared on dismiss. (PLAN-V1.7 §D.)
    var lastPersistError: PersistError?
    /// Wall-clock start of the current run, for duration/WPM in the journal.
    private var runStartedAt: Date?

    /// Stable per-install id, used as this device's odometer slot key.
    var deviceID: String { settings.deviceID }

    /// Game Center — leaderboard + achievements. No-op until authenticated.
    let gameCenter = GameCenterManager()

    /// On-demand kana read-aloud (v1.8 §D). A leaf synthesizer owned directly by the app.
    private let speech = SpeechSynthesizer()

    /// Whether an offline Japanese voice is installed (for hiding the speak button /
    /// graceful degradation — no alert when missing).
    var ttsAvailable: Bool { SpeechSynthesizer.isJapaneseAvailable }

    private let storeURL: URL
    private let conjugationReviewURL: URL
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
        conjugationReviewURL = Self.supportFileURL("conjugation-review.json")
        journalURL = Self.supportFileURL("history.json")
        odometerURL = Self.supportFileURL("odometer.json")
        wordListsURL = Self.supportFileURL("word-lists.json")
        savedWordsURL = Self.supportFileURL("saved-words.json")
        reviewStore = ReviewStore.load(from: storeURL)
        conjugationReviewStore = ConjugationReviewStore.load(from: conjugationReviewURL)
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
        conjugationForms = loaded.conjugationForms
        conjugationSRSEnabled = loaded.conjugationSRSEnabled
        ttsEnabled = loaded.ttsEnabled
        ttsRate = loaded.ttsRate

        // One-time odometer backfill: seed this device's slot from the existing
        // journal lifetime so totals stay correct for users upgrading to v1.2
        // (and so this device contributes its real history once sync turns on).
        if odometer.slots[settings.deviceID] == nil && journal.totalRuns > 0 {
            odometer.setSlot(.init(words: journal.totalWords,
                                   distanceMeters: journal.totalDistanceMeters,
                                   runs: journal.totalRuns),
                             for: settings.deviceID)
            bgSave("odometer (backfill)") { try odometer.save(to: odometerURL) }
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

    /// Conjugation-SRS iCloud sync feature switch (v1.8 §C). **ON** since 2026-07-05: the
    /// `ConjugationSRSCard` record type (+ its indexes) is deployed to the CloudKit
    /// **Production** schema (via cktool import to Development + Dashboard Deploy Dev→Prod,
    /// verified with `cktool export-schema --environment production`), so writes/reads of
    /// the new type succeed in the field. Sync flows through the same engine paths as the
    /// v1.2–v1.4 record types (init/start/delegate unchanged; §C only added additive record
    /// handling). This flag ships in the first build AFTER v1.8 (v1.8's in-review build had
    /// it off). Two-device read verify is a recommended follow-up, not a ship blocker.
    static let conjSRSSyncAvailable = true

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

    /// Whether the one-time conjugation-SRS sync back-fill has already run (v1.9 §A1).
    /// The sync controller reads this to enqueue pre-existing conjugation cards exactly once
    /// after conjugation iCloud sync was enabled (v1.8.1).
    var conjSRSBackfilled: Bool { settings.conjSRSBackfilled }

    /// Marks the one-time conjugation-SRS back-fill as done (persisted).
    func markConjSRSBackfilled() {
        settings.conjSRSBackfilled = true
        if !Screenshotter.isCapturing { settings.save(to: .standard) }
    }

    /// Merges cloud changes into the local stores (via the tested SyncKit merges)
    /// and persists. Called by the sync controller when records arrive.
    func applyCloudChanges(cards: [SRSCard] = [], records: [RideRecord] = [],
                           odometerSlots: [String: OdometerLog.Slot] = [:],
                           wordLists incomingLists: [WordList] = [],
                           legacyDeck deckIDs: [String]? = nil,
                           conjugationCards: [ConjugationSRSCard] = []) {
        if !incomingLists.isEmpty {
            wordLists = SyncMerge.wordLists(wordLists, WordListStore(lists: incomingLists))
            // Compaction runs ONLY here — after a successful cloud merge — never on
            // the load path: a not-yet-propagated deletion compacted too early gets
            // revived by a peer's union on the next fetch (§A2 / WordListStore docs).
            wordLists.compactTombstones()
            bgSave("word-lists (sync merge)") { try wordLists.save(to: wordListsURL) }
        }
        // Legacy v1.4 `SavedWords:deck` record: fold into the default list once,
        // then never again (the persisted flag in foldLegacyDeck enforces "once").
        if let deckIDs { foldLegacyDeck(deckIDs) }
        if !cards.isEmpty {
            let remote = ReviewStore(cards: Dictionary(cards.map { ($0.id, $0) },
                                                       uniquingKeysWith: { a, _ in a }))
            reviewStore = SyncMerge.reviewStores(reviewStore, remote)
            bgSave("review (sync merge)") { try reviewStore.save(to: storeURL) }
            refreshReminders()
        }
        if !records.isEmpty {
            // Display lifetime comes from the odometer, so rebuilding the journal
            // from merged records here can't undercount the odometer totals.
            let merged = SyncMerge.rideRecords(journal.records, records)
            journal = RideJournal(records: merged)
            bgSave("journal (sync merge)") { try journal.save(to: journalURL) }
        }
        if !odometerSlots.isEmpty {
            var remote = OdometerLog()
            for (id, slot) in odometerSlots { remote.setSlot(slot, for: id) }
            odometer = SyncMerge.odometers(odometer, remote)
            bgSave("odometer (sync merge)") { try odometer.save(to: odometerURL) }
        }
        if !conjugationCards.isEmpty {
            // Merge into the SEPARATE conjugation SRS store (never the flat reviewStore,
            // red line §1). newer lastReviewed wins, per (verb, form) card.
            let remote = ConjugationReviewStore(cards: Dictionary(conjugationCards.map { ($0.id, $0) },
                                                                  uniquingKeysWith: { a, _ in a }))
            conjugationReviewStore = SyncMerge.conjugationReviewStores(conjugationReviewStore, remote)
            bgSave("conjugation review (sync merge)") { [conjugationReviewStore, conjugationReviewURL] in
                try conjugationReviewStore.save(to: conjugationReviewURL)
            }
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
        settings.conjugationForms = conjugationForms
        settings.conjugationSRSEnabled = conjugationSRSEnabled
        settings.ttsEnabled = ttsEnabled
        settings.ttsRate = ttsRate
        settings.save(to: .standard)
    }

    /// Speaks `text` (a kana string) aloud if TTS is enabled and text is present. Owned by
    /// AppModel so any screen can call it; the synthesizer cancels any in-flight utterance
    /// so tapping the button repeatedly / switching cards never backs up. No-op (never an
    /// alert) when TTS is off or no Japanese voice is installed.
    func speak(_ text: String?) {
        guard ttsEnabled, let text, !text.isEmpty else { return }
        speech.speak(text, rate: ttsRate)
    }

    /// Cancels any in-flight utterance (call when leaving a game screen).
    func stopSpeaking() { speech.stop() }

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

    /// Best-effort BACKGROUND / automatic persist: the write itself is unchanged
    /// (synchronous, main-actor, atomic — the red line), only failure handling
    /// changes. Never alerts (a persistently-failing disk would loop); logs so a
    /// failure isn't fully silent. (PLAN-V1.7 §D.)
    private func bgSave(_ what: String, _ write: () throws -> Void) {
        do { try write() } catch { PersistLog.failure(what, error) }
    }

    /// Persists the word-list store synchronously + atomically, then tells the sync
    /// controller which list ids changed (no-op when sync is off). This is a
    /// USER-INITIATED path (list CRUD / ★), so a save failure surfaces an alert via
    /// `lastPersistError` — not just a log — so the user knows the change may be lost.
    private func persistWordLists(changed listIDs: [String]) {
        do {
            try wordLists.save(to: wordListsURL)
        } catch {
            lastPersistError = .saveFailed
            PersistLog.failure("word-lists", error)
        }
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
        conjugationSession = nil   // defensive: a list/saved run must not route to the conjugation screen
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
            bgSave("word-lists (legacy fold)") { try wordLists.save(to: wordListsURL) }
            // A v1.4 addition changed our default → propagate to v1.5 peers (and the
            // controller refreshes the deck mirror because the default id is included).
            syncController?.recordLocalChanges(listIDs: [WordList.defaultID])
        }
    }

    func startGame() {
        if selectedMode == .conjugation { startConjugation(); return }
        conjugationSession = nil   // defensive: a ride run must never route to the conjugation screen
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
        case .conjugation:
            break   // handled by the early return above
        }
        if selectedMode == .practice && practicePassages {
            session = GameSession.makePractice(level: practicePassageLevel, config: config)
        } else {
            session = GameSession.make(config: config, vocab: .shared, review: reviewStore)
        }
        runStartedAt = Date()
        screen = .playing
    }

    // MARK: Weak-words cram (v1.7) — practice your hardest reviewed words, no SRS.

    /// Minimum reviewed words before the weak-words cram is offered (a cram of one
    /// or two words isn't worth a menu entry). Below this the menu hides the launcher.
    static let weakWordsMinimum = 5
    /// How many of the weakest words a single cram run drills.
    private static let weakWordsRunSize = 15

    /// How many reviewed words are available to cram (menu gating).
    var weakWordsPoolCount: Int { reviewStore.reviewedCount }

    /// Starts a weak-words cram: the user's hardest reviewed words, run through the
    /// same journey loop but recording **NO SRS** (`makeWeak` → `recordsSRS = false`;
    /// a cram must not touch the SM-2 schedule — PLAN-V1.7 §B). Resolve-then-guard:
    /// bails if nothing resolves (the menu gates proactively via `weakWordsPoolCount`,
    /// so a silent no-op here can't strand the player on a blank screen).
    func startWeakWords() {
        let ids = reviewStore.weakestCards(limit: Self.weakWordsRunSize).map(\.id)
        let resolvable = ids.filter { VocabStore.shared.entry(id: $0) != nil }
        guard !resolvable.isEmpty else { return }
        var config = GameSession.Config()
        config.languageCode = languageCode
        config.showRomajiHint = showRomajiHint
        session = GameSession.makeWeak(ids: resolvable, vocab: .shared, config: config)
        conjugationSession = nil   // defensive: a cram must not route to the conjugation screen
        runStartedAt = Date()
        screen = .playing
    }

    /// How many verbs are available to drill at the chosen level (menu gating).
    var conjugationPoolCount: Int {
        ConjugationSession.playableCount(vocab: .shared, level: selectedLevel)
    }

    /// The drillable conjugation forms (for the menu form-picker), localized.
    var conjugationFormOptions: [ConjugationFormOption] {
        ConjugationSession.formOptions(languageCode: languageCode)
    }

    /// Whether `rawValue` is in the drilled-forms set (an empty set = all forms).
    func isConjugationFormSelected(_ rawValue: String) -> Bool { conjugationForms.contains(rawValue) }

    /// Toggles a form in the drilled-forms set. Deselecting everything (empty set)
    /// means "all forms" — the drill builder falls back to all (never zero forms).
    func toggleConjugationForm(_ rawValue: String) {
        if let i = conjugationForms.firstIndex(of: rawValue) {
            conjugationForms.remove(at: i)
        } else {
            conjugationForms.append(rawValue)
        }
    }

    /// Starts a verb-conjugation drill. Resolve-then-guard: if the pool for the chosen
    /// level is empty (no `vc` data / old vocab), it does NOT enter the playing screen —
    /// otherwise the player would be stranded on an empty, already-finished screen
    /// (the v1.4 saved-deck lesson, PLAN-V1.6 §4). The drill writes no SRS by design.
    func startConjugation() {
        var config = ConjugationSession.Config()
        config.languageCode = languageCode
        config.showRomajiHint = showRomajiHint
        config.level = selectedLevel
        config.promptCount = 12
        config.setForms(rawValues: conjugationForms)   // empty / unknown → all forms
        let chooser = ConjugationSession.weightedFormChooser(weakBiasedPick: conjugationWeakFormPick())
        let built = ConjugationSession.make(vocab: .shared, config: config, chooseForm: chooser)
        // Resolve-then-guard: an empty pool must not enter the (already-finished) screen.
        // The menu surfaces this proactively via `conjugationPoolCount == 0`, so a no-op
        // here is never silent.
        guard built.promptCount > 0 else { return }
        built.onOutcome = conjugationOutcomeSink()
        session = nil
        conjugationSession = built
        runStartedAt = Date()
        screen = .playing
    }

    /// How many (verb, form) cards are due for conjugation review right now (menu gating).
    var conjugationDueCount: Int { conjugationReviewStore.dueCount() }

    /// Starts a **due-review** conjugation drill: the due (verb, form) cards first, then
    /// fresh forms filled in (weak-form weighted). Resolve-then-guard like `startConjugation`
    /// — a run that resolves to nothing (all due cards point at removed vocab) does NOT enter
    /// the screen. Due review spans all levels (the due cards define its scope).
    func startConjugationReview() {
        let due = conjugationReviewStore.dueCards(limit: Self.conjugationRunSize)
            .map { (entryID: $0.sourceID, formToken: $0.formToken) }
        var config = ConjugationSession.Config()
        config.languageCode = languageCode
        config.showRomajiHint = showRomajiHint
        config.level = nil                      // review pulls from the whole due set / pool
        config.promptCount = Self.conjugationRunSize
        let chooser = ConjugationSession.weightedFormChooser(weakBiasedPick: conjugationWeakFormPick())
        let built = ConjugationSession.makeReview(due: due, vocab: .shared, config: config,
                                                  chooseForm: chooser)
        guard built.promptCount > 0 else { return }
        built.onOutcome = conjugationOutcomeSink()
        session = nil
        conjugationSession = built
        runStartedAt = Date()
        screen = .playing
    }

    private static let conjugationRunSize = 12

    /// The `onOutcome` sink a conjugation drill writes through. It records each completed/
    /// skipped prompt into the SEPARATE conjugation SRS store and persists it. Gated on
    /// `conjugationSRSEnabled` (default true). The `ConjugationSession` itself still holds
    /// no store — this closure, owned by AppModel, is the only writer. Invoked synchronously
    /// on the main actor (driven by the game view's key handling).
    private func conjugationOutcomeSink() -> (ConjugationPrompt, TypingOutcome) -> Void {
        { [weak self] prompt, outcome in
            MainActor.assumeIsolated {
                self?.recordConjugationOutcome(promptID: prompt.id, outcome: outcome)
            }
        }
    }

    private func recordConjugationOutcome(promptID: String, outcome: TypingOutcome) {
        guard conjugationSRSEnabled, !Screenshotter.isCapturing else { return }
        let c = ConjugationOutcome(completed: outcome.completed, mistakes: outcome.mistakes,
                                   usedHint: outcome.usedHint, durationRatio: outcome.durationRatio)
        conjugationReviewStore.record(promptID: promptID, outcome: c)
        // Background/auto write (a drill outcome, not a user-initiated data action) → log-only
        // on failure, no alert (§D).
        bgSave("conjugation review") { [conjugationReviewStore, conjugationReviewURL] in
            try conjugationReviewStore.save(to: conjugationReviewURL)
        }
        // Push the changed card to iCloud — GATED OFF for v1.8 (conjSRSSyncAvailable=false),
        // so this is a no-op until device gate E flips it on (PLAN-V1.8 §4).
        if Self.conjSRSSyncAvailable {
            syncController?.recordLocalChanges(conjugationSRSIDs: [promptID])
        }
    }

    /// The weak-form picker the drill builders use, expressed in String tokens only so the
    /// app never names a ConjugationKit type (red line §6). It reads a SNAPSHOT of the
    /// conjugation SRS store and biases form selection toward the learner's weakest forms
    /// (60/40 so no single form monopolizes); returns nil to fall back to a random form.
    /// Pure read — selection never writes SRS. `GameCore.weightedFormChooser` (inlined at
    /// the call sites) adapts this into the builders' `ConjugationForm` closure, so GameCore
    /// never sees the store either.
    private func conjugationWeakFormPick() -> (String, [String]) -> String? {
        { [store = conjugationReviewStore] entryID, tokens in
            var rng = SystemRandomNumberGenerator()
            return FormWeighting.weightedPick(entryID: entryID, formTokens: tokens, store: store, using: &rng)
        }
    }

    /// Ends the conjugation drill: snapshot the score and show the results screen. SRS was
    /// already recorded per-prompt via the `onOutcome` sink; there is NO journal / odometer /
    /// Game Center write (the drill is not a ride).
    func finishConjugation() {
        guard let conjugationSession else { return }
        stopSpeaking()
        lastConjugationSummary = ConjugationSummary(from: conjugationSession)
        resultsAreConjugation = true
        self.conjugationSession = nil
        screen = .results
    }

    /// Ends the current run, persists SRS progress (except for Practice, which
    /// uses a transient SRS store), logs the run to the ride journal, and shows
    /// results. Practice mode skips the score screen and returns to the menu.
    ///
    /// The **weak-words cram** (`session.config.recordsSRS == false`) advances
    /// nothing: no SRS persist, no journal/odometer, no Game Center — it just shows
    /// its review-these results. Practice is unchanged (it still logs a ride).
    func finishGame() {
        guard let session else { return }
        stopSpeaking()   // cancel any in-flight read-aloud when a run ends (parity with finishConjugation)
        // Single source of truth for the side-effect gating (tested in GameCore).
        let completion = RunCompletion(mode: session.mode, recordsSRS: session.config.recordsSRS)
        var changedSRS: [String] = []
        if completion.persistsSRS {                // never overwrite real SRS with a practice/cram run
            // MERGE this run's outcomes into the live store instead of wholesale-replacing it —
            // a cloud fetch can merge newer cards into `reviewStore` mid-run, and a bare
            // `reviewStore = session.review` would revert that AND re-upload stale (v1.9 §A2).
            // The pure, tested SyncMerge.applyRun keeps both and reports exactly the changed ids.
            let (merged, changed) = SyncMerge.applyRun(session.review, into: reviewStore)
            changedSRS = changed
            reviewStore = merged
            bgSave("review (run)") { try reviewStore.save(to: storeURL) }
            refreshReminders()                     // the due count just changed
        }
        lastSummary = GameSummary(from: session)
        resultsAreConjugation = false
        let appended = completion.logsRide ? logRun(session) : nil   // a cram doesn't log a ride / odometer
        // Tell the iCloud sync controller what changed (no-op when sync off / a cram).
        syncController?.recordLocalChanges(
            srsIDs: changedSRS,
            rideRecordIDs: appended.map { [$0.id] } ?? [],
            odometerChanged: appended != nil)
        // Game Center: submit score + achievements for real (non-practice, non-cram) runs.
        if completion.reportsGameCenter, let summary = lastSummary {
            gameCenter.recordRun(summary: summary, mode: session.mode,
                                 lifetimeWords: lifetimeWords,
                                 streakDays: journal.streakDays(),
                                 totalRuns: lifetimeRuns)
        }
        self.session = nil
        screen = completion.showsResults ? .results : .menu
    }

    func backToMenu() {
        session = nil
        conjugationSession = nil
        runStartedAt = nil
        stopSpeaking()
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
        bgSave("journal (run)") { try journal.save(to: journalURL) }
        bgSave("odometer (run)") { try odometer.save(to: odometerURL) }
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
