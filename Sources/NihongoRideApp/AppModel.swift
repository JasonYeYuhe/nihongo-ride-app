import Foundation
import Observation
import GameCore
import JournalKit
import ReviewKit
import SettingsKit
import PersistKit
import DiagnosticsKit
import RomajiKana
import SyncKit
import VocabKit
import WordListsKit
import ConjugationReviewKit
import SpeechKit
import WidgetSharedKit
import WidgetKit
import SceneryKit

/// A snapshot of a finished run, shown on the results screen.
struct GameSummary: Equatable {
    var score: Int
    var maxCombo: Int
    var wordsCompleted: Int
    var accuracy: Double
    var distanceMeters: Double
    /// Distinct words that lapsed this run (skipped / hinted / many typos).
    var reviewWords: [VocabEntry]
    /// The run's refused keystrokes, carried so the results screen can coach from them.
    /// In memory with the summary; never persisted (see RomajiKana.MistakeTrace).
    var mistakes: MistakeTrace
    /// Which mode produced this run — the results screen shows a dictation run a stat the
    /// others do not have.
    var mode: GameMode
    /// Times the learner asked to hear a sentence again (dictation). Never scored: a run
    /// that needed twelve replays and one that needed none score identically, and that is
    /// exactly why the number is reported separately instead of folded into the score.
    var replays: Int
    /// Whether this run's outcomes were merged into the SM-2 schedule.
    ///
    /// Carried on the summary so the results screen can ask the question `finishGame` already
    /// answered instead of re-deriving it from the mode. It is false for sentence, dictation
    /// and the weak-words cram, and the screen was calling `reviewWords` "To review" in all
    /// three — a tile counting words that nothing would ever review. Found by the v1.23 audit
    /// and left; §A puts actionable chips directly beside it, which makes the contradiction
    /// louder. (v1.24 §B.)
    ///
    /// Derived from `RunCompletion`, the same value `finishGame` gates the SRS merge on, so the
    /// label and the behaviour cannot drift apart — which is what a mode check in the view
    /// would have allowed the moment a fourth non-persisting mode appeared.
    var persistsSRS: Bool

    init(from session: GameSession) {
        score = session.score
        maxCombo = session.maxCombo
        wordsCompleted = session.wordsCompleted
        accuracy = session.accuracy
        distanceMeters = session.distanceMeters
        mode = session.mode
        replays = session.replays
        persistsSRS = RunCompletion(mode: session.mode,
                                    recordsSRS: session.config.recordsSRS).persistsSRS
        var seen = Set<String>()
        reviewWords = session.lapsedEntries.filter { seen.insert($0.id).inserted }
        mistakes = session.mistakes
    }
}

extension GameSummary {
    /// How well a run went. Single source of truth shared by the results screen, the share
    /// card, and the Game Center "Flawless Run" achievement (so the badge the player sees
    /// and the achievement they earn never disagree).
    ///
    /// The rule itself lives in `GameCore.RideGrade` — the app target has no unit tests, and
    /// this rule shipped a bug precisely because of that. `Grade` stays as a local alias so
    /// the call sites read unchanged. (v1.12 §C.)
    typealias Grade = RideGrade

    var grade: Grade {
        RideGrade.grade(accuracy: accuracy, maxCombo: maxCombo,
                        wordsCompleted: wordsCompleted, lapsedCount: reviewWords.count)
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
    enum Screen: Equatable { case menu, playing, results, about, journal, settings, lists, listDetail, onboarding, stats, coach }

    var screen: Screen = .menu {
        didSet { navCount += 1 }
    }
    /// Monotonic navigation counter. RootView uses it as the screen's zIndex so
    /// the incoming screen always stacks ABOVE the outgoing one mid-transition —
    /// otherwise the dying screen (still hit-testable for ~0.4s) swallows taps
    /// meant for the new screen's buttons.
    private(set) var navCount = 0

    /// The vocabulary this model reads. Injected rather than reached for, so a test can hand it
    /// a store it arranged. (v1.24 §B — see `init(vocab:)`.)
    let vocab: VocabStore

    /// The last start attempt found nothing to ride — every word at this level is already
    /// scheduled beyond today. Shown on the menu instead of a fake arrival screen. (v1.15 §D.)
    private(set) var emptyPoolNotice = false

    // Settings. Each persists on change (v1.2 — before this they only lived in
    // memory and reset to defaults on every launch). `didSet` doesn't fire during
    // init, so applying loaded values below is free; `settingsLoaded` guards any
    // re-entrancy and skips writes until the initial load is in place.
    var languageCode: String = "en" {                                     // "en" or "zh"
        didSet {
            persistSettings()
            // The widget shows localized labels; without this it lags the app's language
            // until the next run/foreground (review LOW#2). Pending notifications carry
            // their text too and are already written into the system's schedule, so they
            // need rewriting for the same reason — otherwise tonight's reminder still
            // arrives in the language the user just switched away from.
            if oldValue != languageCode {
                refreshWidgetSnapshot()
                refreshReminders()
            }
        }
    }
    /// One assistance policy (v1.16 §A) — replaces the hint toggle. `.afterStruggle` offers
    /// a reveal only when the learner is demonstrably stuck; taking it charges the same
    /// lapse the manual reveal always did.
    /// Initial value is overwritten by the settings load in `init`, so it never decides
    /// anything — but it should still agree with `AppSettings.default`, or a reader
    /// concludes the fresh-install default is "always" when it is "when stuck".
    var assistance: AssistanceMode = .afterStruggle { didSet { persistSettings() } }
    /// Show the reading above the kanji in the displayed example sentence.
    var exampleFurigana: Bool = true { didSet { persistSettings() } }
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

    // Which stores this launch is allowed to WRITE. A store that was merely UNREADABLE
    // decodes to an empty one, and saving that empty store over the file destroys data that
    // was probably intact — the loader's care is undone by the first write otherwise.
    // (v1.15 §C.)
    private let reviewStoreWritable: Bool
    private let conjugationStoreWritable: Bool
    private let journalWritable: Bool
    private let odometerWritable: Bool
    /// What each store's load reported, for the launch log.
    private let persistLoadOutcomes: [(String, LossyLoad.Outcome)]

    /// The word-list file could not be READ at launch, so `wordLists` is an empty stand-in and
    /// nothing may overwrite, sync, or mutate it.
    ///
    /// Write-gating alone is not enough (Codex, v1.16 review): `persistWordLists` records
    /// local CloudKit changes even when the save THREW, so an empty stand-in could reach the
    /// cloud with the file on disk still perfectly fine. Mutations, local persistence,
    /// sync-merge persistence and outbound records are all gated on this.
    private(set) var wordListsReadOnly = false
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
    /// Ridden time for the run in flight — wall clock minus paused / sheet-open /
    /// backgrounded stretches. Replaces a bare start timestamp, which counted all three as
    /// riding and wrote the resulting WPM into the journal permanently. (v1.15 §D.)
    private var runClock: RunClock?

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

    /// - Parameter vocab: the vocabulary to read. Defaults to the shared store, so every
    ///   existing call site is unchanged; a test passes one it arranged, which is the whole
    ///   point of the parameter — see `startGame`'s empty-pool guard, which cannot be reached
    ///   at all from a model whose store is full. (v1.24 §B.)
    init(vocab: VocabStore = .shared) {
        self.vocab = vocab
        storeURL = Self.supportFileURL("review.json")
        conjugationReviewURL = Self.supportFileURL("conjugation-review.json")
        journalURL = Self.supportFileURL("history.json")
        odometerURL = Self.supportFileURL("odometer.json")
        wordListsURL = Self.supportFileURL("word-lists.json")
        savedWordsURL = Self.supportFileURL("saved-words.json")
        // Loaded reporting their outcome (v1.15 §B). A store that was merely UNREADABLE must
        // not be written back over — it is probably intact — and the odometer's outcome also
        // decides whether the one-time backfill below is allowed to run at all.
        let reviewLoad = ReviewStore.loadReporting(from: storeURL)
        reviewStore = reviewLoad.store
        let conjLoad = ConjugationReviewStore.loadReporting(from: conjugationReviewURL)
        conjugationReviewStore = conjLoad.store
        let journalLoad = RideJournal.loadReporting(from: journalURL)
        journal = journalLoad.journal
        let odometerLoad = OdometerLog.loadReporting(from: odometerURL)
        odometer = odometerLoad.log
        reviewStoreWritable = LossyLoad.isSafeToWrite(reviewLoad.outcome)
        conjugationStoreWritable = LossyLoad.isSafeToWrite(conjLoad.outcome)
        journalWritable = LossyLoad.isSafeToWrite(journalLoad.outcome)
        odometerWritable = LossyLoad.isSafeToWrite(odometerLoad.outcome)
        persistLoadOutcomes = [("review", reviewLoad.outcome), ("conjugation", conjLoad.outcome),
                               ("journal", journalLoad.outcome), ("odometer", odometerLoad.outcome)]
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
            : AppSettings.load(from: Self.settingsStore)
        settings = loaded
        languageCode = loaded.languageCode
        assistance = AssistanceMode(rawValue: loaded.assistance)
            ?? (loaded.showRomajiHint ? .always : .off)
        soundEnabled = loaded.soundEnabled
        exampleFurigana = loaded.exampleFurigana
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
        //
        // The condition lives in OdometerLog.shouldBackfill — read its doc before
        // touching this. The guard used to be `slots[deviceID] == nil`, which a second
        // device satisfies with a journal a cloud fetch filled with ANOTHER device's
        // rides, permanently doubling the fleet's lifetime totals. (v1.12 §A.)
        // Considered exactly ONCE per device, and only for a device that can prove it is a
        // genuine upgrader rather than one whose journal a cloud fetch has already filled
        // with the fleet's rides. See OdometerLog.shouldBackfill(slots:localRuns:
        // alreadyConsidered:hasSyncedBefore:fileOutcome:) — a wrong seed here is permanent
        // and spreads. (v1.15 §C.)
        if !settings.odometerBackfillDone {
            let mayBackfill = OdometerLog.shouldBackfill(
                slots: odometer.slots, localRuns: journal.totalRuns,
                alreadyConsidered: settings.odometerBackfillDone,
                hasSyncedBefore: FileManager.default.fileExists(
                    atPath: Self.supportFileURL("cksync-state.json").path),
                fileOutcome: odometerLoad.outcome)
            if mayBackfill {
                odometer.setSlot(.init(words: journal.totalWords,
                                       distanceMeters: journal.totalDistanceMeters,
                                       runs: journal.totalRuns),
                                 for: settings.deviceID)
                bgSave("odometer (backfill)", allowed: odometerWritable) { try odometer.save(to: odometerURL) }
            }
            // Recorded whether it fired or not: the question is settled for this install, so
            // later transient state can never make it look eligible again.
            settings.odometerBackfillDone = true
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
        // An UNREADABLE file (not a corrupt one) means the real lists are probably intact and
        // this session is running on an empty stand-in. Everything that could make that
        // stand-in permanent is disabled below — see `wordListsReadOnly`. (v1.16 §C.)
        wordListsReadOnly = migration.outcome == .unreadableDeferred

        settingsLoaded = true

        // First-launch onboarding: show it only to a genuinely fresh install, and
        // never while capturing screenshots (would replace menu.png). An upgrading
        // user who already has data is silently marked as seen so they never get it.
        // A UI-test launch is a genuinely fresh install — that is the point of the isolation —
        // so it lands on ONBOARDING, and every existing flow test waited fifteen seconds for a
        // menu button that was never coming. Those tests used to pass because the simulator
        // happened to carry a dismissed-onboarding flag from some earlier run: they depended on
        // ambient state they never set, which is precisely what isolating them exposes.
        //
        // So the start state is now declared rather than inherited. `NIHONGO_UITEST_ONBOARDING`
        // opts back in, so onboarding itself stays reachable instead of becoming the one screen
        // no UI test can see.
        let uiTestWantsOnboarding =
            ProcessInfo.processInfo.environment["NIHONGO_UITEST_ONBOARDING"] != nil
        if Self.isUITest && !uiTestWantsOnboarding {
            settings.hasSeenOnboarding = true
        }
        if !settings.hasSeenOnboarding && !Screenshotter.isCapturing {
            let freshInstall = reviewStore.count == 0 && journal.totalRuns == 0
            if freshInstall {
                screen = .onboarding           // didSet doesn't fire in init; navCount stays 0
            } else {
                settings.hasSeenOnboarding = true
            }
        }

        // One line per store, so a support question about vanished progress has something
        // to look at instead of a guess. (v1.15 §C.)
        for (name, outcome) in persistLoadOutcomes where outcome != .loaded && outcome != .missing {
            PersistLog.loadOutcome(name, String(describing: outcome))
        }

        // Persist once so a fresh install writes back its minted deviceID (and the
        // onboarding flag above for upgrading users). Never in capture mode.
        if !Screenshotter.isCapturing { settings.save(to: Self.settingsStore) }
        // Refresh the reminder schedule for the days ahead (no-op when off).
        refreshReminders()
        refreshWidgetSnapshot()   // v1.11: publish the current due counts to the widget
        startSyncIfEnabled()
        gameCenter.authenticate()
    }

    /// Dismisses first-launch onboarding (finish or skip): records it as seen and
    /// drops to the menu. Onboarding deliberately does NOT request notifications —
    /// reminders stay opt-in from the settings screen.
    func finishOnboarding() {
        settings.hasSeenOnboarding = true
        settings.save(to: Self.settingsStore)
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
        let conjStore = conjugationReviewStore
        let hour = dueReminderHour
        let lang = languageCode
        // Captured before the hop, like every other value here: `vocab` is the model's own
        // store and the Task must not reach back into the model for it.
        let resolves = vocab.resolvesID
        Task { [weak self] in
            let scheduled = await ReminderScheduler.apply(
                enabled: enabled, store: store, conjugationStore: conjStore,
                resolves: resolves, hour: hour, languageCode: lang)
            if enabled && !scheduled {
                self?.dueReminderEnabled = false   // denied / unavailable
            }
        }
    }

    /// Rewrites the home-screen widget's derived snapshot (v1.11) from the current
    /// review stores + streak, and asks WidgetKit to reload. Called after anything
    /// that moves the due count: launch, finishing a run or a conjugation drill,
    /// recording a drill outcome, and a cloud merge.
    ///
    /// 🔴 Skipped while capturing. `WidgetSnapshotStore.write` targets the shared App
    /// Group container, which is OUTSIDE `supportFileURL`'s capture redirect — so a
    /// headless render, which mints demo stores and plays fake runs, would otherwise
    /// stamp demo numbers onto the real widget on the user's home screen.
    ///
    /// The write is tiny (a few fields + two 14-int arrays) and atomic, so it runs
    /// inline like `settings.save`. A failure is logged, never alerted: the widget is
    /// a convenience.
    ///
    /// 🔴 Also skipped with no bundle identifier, which is the half this guard was missing
    /// and the half that mattered. The comment here used to say `containerUnavailable` was
    /// "simply the normal state under `swift run` (no entitlement)" — that is FALSE on macOS:
    /// `containerURL(forSecurityApplicationGroupIdentifier:)` resolves for an unbundled
    /// process, so the write SUCCEEDS and stamps whatever stores that process happens to hold
    /// onto the real widget. Latent since v1.11 because nothing unbundled built an `AppModel`
    /// except the screenshot renderer, which the capture guard already covered. v1.24's app
    /// test target made it live: seven models per `swift test`, each computed from an empty
    /// sandbox, each overwriting the owner's real home-screen widget with zeros. Caught by the
    /// pre-submission review, after it had already happened on this machine.
    ///
    /// `Bundle.main.bundleIdentifier != nil` is the same test `GameCenterManager`,
    /// `ReminderScheduler` and `CloudKitSyncController` already use, for the same reason.
    func refreshWidgetSnapshot(now: Date = Date()) {
        guard Bundle.main.bundleIdentifier != nil, !Screenshotter.isCapturing else { return }
        let h = WidgetSnapshot.horizon
        let cal = Calendar.current
        let startToday = cal.startOfDay(for: now)
        // Per-day streak so the widget's streak DECAYS as the days pass without a ride,
        // instead of freezing the write-time value (a lost streak lingering ~2 weeks).
        let streakByDay: [Int] = (0..<h).map { offset in
            let day = cal.date(byAdding: .day, value: offset, to: startToday) ?? now
            return journal.streakDays(asOf: day, calendar: cal)
        }
        let snapshot = WidgetSnapshot(
            generatedAt: now,
            vocabDueByDay: reviewStore.dueByDay(asOf: now, horizon: h,
                                                resolves: vocab.resolvesID),
            conjugationDueByDay: conjugationReviewStore.dueByDay(
                asOf: now, horizon: h,
                resolves: vocab.resolvesID),
            streakByDay: streakByDay,
            lifetimeWords: lifetimeWords,
            languageCode: languageCode)
        switch WidgetSnapshotStore.write(snapshot,
                                         to: Self.currentIsolation.widgetContainer
                                             ?? AppGroup.containerURL()) {
        case .success:
            WidgetCenter.shared.reloadAllTimelines()
        case .failure(.containerUnavailable):
            break   // no App Group entitlement in this context — nothing to do
        case .failure(let error):
            PersistLog.failure("widget snapshot write", error)
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
        // The harness and the UI tests both finish REAL runs; an unguarded push lands those in
        // the owner's real CloudKit database, where nothing local can clean them up. Read from
        // the one isolation value rather than re-testing the flags, so a new harness mode is
        // covered by describing itself there instead of by remembering this line.
        guard Self.currentIsolation.syncAllowed else { syncStatus = .off; return }
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

    /// Every location a launch may touch, decided in ONE value.
    ///
    /// v1.24's sandbox assertion was green while the tests were overwriting the owner's real
    /// home-screen widget, because it checked the one door that was known about. The lesson
    /// recorded then was to assert the PROPERTY — this launch touches nothing that belongs to
    /// the user — over every location, so the next escape trips it without anyone predicting
    /// which door it uses. That is only checkable if the locations are decided together, which
    /// is what this is: four fields, one function, one test that reads all four.
    struct LaunchIsolation: Equatable, Sendable {
        /// Base for `supportFileURL`. Nil means the machine's real Application Support.
        var supportBase: URL?
        /// Where the widget snapshot lands. Nil means the real App Group container.
        var widgetContainer: URL?
        /// Named UserDefaults suite. Nil means `.standard`.
        var settingsSuite: String?
        /// Whether CloudKit sync may start at all.
        var syncAllowed: Bool

        /// True when nothing here can reach data the user owns.
        var touchesNothingOfTheUsers: Bool {
            supportBase != nil && widgetContainer != nil && settingsSuite != nil && !syncAllowed
        }
    }

    /// Pure, so it can be asked about a configuration this process is not in.
    static func launchIsolation(uiTest: Bool,
                                layoutHarness: Bool,
                                capturing: Bool,
                                supportOverride: URL?,
                                widgetOverride: URL?,
                                settingsOverride: String?) -> LaunchIsolation {
        if uiTest {
            let dir = uiTestDirectory
            return LaunchIsolation(
                supportBase: supportOverride ?? dir,
                widgetContainer: widgetOverride ?? dir.appendingPathComponent("group", isDirectory: true),
                settingsSuite: settingsOverride ?? "NihongoRideUITest",
                syncAllowed: false)
        }
        return LaunchIsolation(
            supportBase: supportOverride
                ?? (capturing ? FileManager.default.temporaryDirectory
                        .appendingPathComponent("NihongoRideCapture", isDirectory: true) : nil),
            widgetContainer: widgetOverride,
            settingsSuite: settingsOverride,
            syncAllowed: !layoutHarness)
    }

    /// This launch's isolation, read by every redirect below so they cannot disagree.
    static var currentIsolation: LaunchIsolation {
        launchIsolation(uiTest: isUITest, layoutHarness: isLayoutHarness,
                        capturing: Screenshotter.isCapturing,
                        supportOverride: supportDirectoryOverride,
                        widgetOverride: widgetContainerOverride,
                        settingsOverride: settingsSuiteOverride)
    }

    /// Set by the unit-test target alongside `settingsDefaults`, so the isolation value and the
    /// store it describes cannot drift apart.
    static var settingsSuiteOverride: String?

    /// True while an XCUITest is driving the app.
    ///
    /// The UI tests launch the NORMAL app and complete a REAL run, which writes SRS, the ride
    /// journal, the odometer and the widget snapshot — and pushes all of it to CloudKit if the
    /// device is signed in. That is the v1.24 App Group incident with a bigger blast radius:
    /// that one wrote zeros to a local container, this one can put a phantom ride in the
    /// owner's real CloudKit database, where nothing local can clean it up.
    ///
    /// So this redirects every store the same way `AppModelTests` does, and stops sync before
    /// it starts. It is the precondition for widening the UI suite, not a follow-up to it.
    ///
    /// DEBUG-only, so a shipping build cannot be talked into it by an environment variable.
    static var isUITest: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["NIHONGO_UITEST"] != nil
        #else
        return false
        #endif
    }

    /// The throwaway container a UI-test launch reads and writes.
    ///
    /// FIXED rather than per-launch, because a UI test may relaunch the app mid-case and expect
    /// what it typed to still be there. Cleared ONCE per process instead — screenshot capture
    /// learned this the hard way: a fixed directory that nothing clears makes every run inherit
    /// the last one's rides, and the lifetime odometer grew monotonically until the render gate
    /// depended on how many times it had been run.
    static let uiTestDirectory: URL = {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NihongoRideUITest", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// True while the layout harness is driving. Kept OUTSIDE the `#if` so the guards that
    /// consult it read the same in every configuration; it is constant-false anywhere the
    /// harness cannot run.
    static var isLayoutHarness: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return ProcessInfo.processInfo.environment["NIHONGO_DEBUG_SCREEN"] != nil
        #else
        return false
        #endif
    }

    #if DEBUG && targetEnvironment(simulator)
    /// Debug-only layout harness: `NIHONGO_DEBUG_SCREEN` drops the app straight onto one
    /// screen, populated enough to be worth looking at. Its whole reason to exist is
    /// Dynamic Type — `ImageRenderer` does not honour `dynamicTypeSize` (an explicitly
    /// injected value doesn't reach `@ScaledMetric` either; measured, not assumed), so the
    /// headless gate cannot see large-text layout at all, and the alternative was tapping
    /// through the app by hand once per text size.
    ///
    /// 🔴 This WRITES. `finishGame()` persists SRS progress and logs a ride to the journal —
    /// that is the point of it, since a results screen with no numbers proves nothing about
    /// layout. So it is gated on the SIMULATOR as well as DEBUG: a Debug build on a real
    /// device (or `swift run` on the Mac) would otherwise silently add a phantom ride to the
    /// developer's own history. A simulator container is disposable; a person's is not.
    ///
    /// "Disposable container" is NOT the same as "no side effects", though: a simulator signed
    /// into iCloud would have pushed those phantom rides into the developer's real CloudKit
    /// development database, where they are not disposable at all. `isLayoutHarness` therefore
    /// also keeps the sync controller from starting (see `startSyncIfEnabled`).
    func jumpToDebugScreen() {
        guard let want = ProcessInfo.processInfo.environment["NIHONGO_DEBUG_SCREEN"] else { return }
        switch want {
        case "menu":
            screen = .menu
        case "results":
            // Force Journey: dispatching through the PERSISTED mode meant that if the app was
            // last left on Verbs this built a conjugation session and then called a finishGame
            // that does nothing, and on Practice it returned to the menu — the harness silently
            // showed the wrong screen, which is worse than failing.
            selectedMode = .journey
            startGame()
            session?.skip()                       // one lapse so the review list has a row
            for _ in 0 ..< 6 {
                guard let romaji = session?.currentRomaji else { break }
                for ch in romaji { _ = session?.input(ch) }
            }
            finishGame()
        case "conj-results":
            selectedMode = .conjugation
            startGame()
            for _ in 0 ..< 4 {
                guard let romaji = conjugationSession?.currentRomaji else { break }
                for ch in romaji { _ = conjugationSession?.input(ch) }
            }
            finishConjugation()
        case "coach":
            // Seeds a run that really does contain a recurring, classifiable pattern, so the
            // coach screen can be looked at. It drills words with っ and types each one's own
            // correct romaji with ONE half of the doubled consonant removed — which is
            // precisely the dropped-sokuon mistake, derived from the data rather than faked.
            let sokuonIDs = vocab.entries
                .filter { $0.kana.contains("っ") }.prefix(3).map(\.id)
            var config = GameSession.Config()
            config.languageCode = languageCode
            config.mode = .journey
            session = GameSession.makeSaved(ids: Array(sokuonIDs), vocab: vocab,
                                            review: reviewStore, config: config)
            runClock = RunClock(startedAt: Date())
            while let romaji = session?.currentRomaji, session?.isFinished == false {
                let chars = Array(romaji)
                // First doubled consonant → type the word with one of them missing.
                let doubled = chars.indices.dropLast().first { chars[$0] == chars[$0 + 1] }
                var attempt = chars
                if let d = doubled { attempt.remove(at: d) }
                for ch in attempt where session?.isFinished == false {
                    _ = session?.input(ch)
                }
                session?.skip()
            }
            finishGame()
            screen = .coach
        case "practice":
            // Longest passages, hints on — the worst case for the reflow fix in §D, which is
            // the only way to see whether the typing target is still behind an ellipsis.
            selectedMode = .practice
            practicePassages = true
            practicePassageLevel = .hard
            assistance = .always
            startGame()
        case "game":
            startGame()
        default:
            break
        }
    }
    #endif

    /// The rider stopped riding — pause overlay, a sheet over the game, or the app leaving
    /// the foreground. Idempotent, because those three overlap. (v1.15 §D.)
    func pauseRunClock() { runClock?.pause(at: Date()) }

    /// The rider resumed. Ignored when not paused.
    func resumeRunClock() { runClock?.resume(at: Date()) }

    // MARK: Coach (v1.15)

    /// The one thing worth saying about how the last run was TYPED, if anything is.
    ///
    /// Deterministic, computed from the run's own refused keystrokes. Nil when the run was
    /// clean, when nothing recurred across two distinct words, or when the only recurring
    /// thing has no name the app can explain — silence is the correct output in all three.
    var coachHeadline: Diagnosis? {
        lastSummary.flatMap { TypingDiagnostics.headline($0.mistakes) }
    }

    /// Words the learner has ALREADY reviewed that exercise the diagnosed pattern.
    ///
    /// Already-reviewed on purpose: a drill is meant to isolate the keyboard problem, and an
    /// unfamiliar word adds a second reason to fail on top of the one being fixed.
    func coachDrillIDs(for pattern: TypingPattern) -> [String] {
        // The `resolves:` and the `entry(id:)` below are the same question asked twice, and
        // that is deliberate rather than redundant: the store filters so the POOL is right, and
        // this maps because the drill needs the kana. Before v1.24 §C only the second existed,
        // so the pool was correct by accident of the caller rather than by the API.
        let known = reviewStore.reviewedIDs(resolves: vocab.resolvesID)
            .compactMap { id -> (id: String, kana: String)? in
                guard let e = vocab.entry(id: id) else { return nil }
                return (id: e.id, kana: e.kana)
            }
        return CoachContent.drillCandidates(for: pattern, from: known)
    }

    /// How much material this pattern's drill would have — words for most patterns, sentences
    /// for particle spelling. One question, so the view cannot ask the wrong one: it used to
    /// count reviewed WORDS for every pattern, which meant the particle drill (whose material
    /// is passages) always reported none and offered "learn a few more words first" forever.
    func coachDrillCount(for pattern: TypingPattern) -> Int {
        if CoachContent.drillSource(for: pattern) == .passages {
            return PassageStore.shared.passages
                .filter { CoachContent.exercises($0.kana, pattern: pattern) }.count
        }
        return coachDrillIDs(for: pattern).count
    }

    /// Starts a drill on the diagnosed pattern. Same journey loop, same SRS rules as any
    /// list run — these are the learner's own words, so their progress still counts.
    func startCoachDrill(for pattern: TypingPattern) {
        var config = GameSession.Config()
        config.languageCode = languageCode
        config.assistance = assistance

        let built: GameSession
        if CoachContent.drillSource(for: pattern) == .passages {
            // Particle spelling can only be drilled in sentences. Drilling WORDS whose reading
            // contains は — はな, はし — would have the learner type `hana`, succeed, and learn
            // nothing about the particle, while the app congratulated them on remediating it.
            // Practice mode, so this never touches the SRS schedule.
            config.mode = .practice
            config.newWordCount = 8
            config.reviewWordCount = 0
            built = GameSession.makePractice(
                matching: { CoachContent.exercises($0.kana, pattern: pattern) },
                config: config)
        } else {
            let ids = coachDrillIDs(for: pattern)
            guard !ids.isEmpty else { return }
            config.mode = .journey
            built = GameSession.makeSaved(ids: ids, vocab: vocab, review: reviewStore, config: config)
        }
        guard !built.isFinished else { return }
        session = built
        conjugationSession = nil
        runClock = RunClock(startedAt: Date())
        resolveRideStage()
        screen = .playing
    }

    /// App returned to the foreground: refresh reminders and pull/push sync.
    func appBecameActive() {
        refreshReminders()
        refreshWidgetSnapshot()   // foregrounding may have crossed midnight → re-anchor the histogram
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
        if !Screenshotter.isCapturing { settings.save(to: Self.settingsStore) }
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
            bgSave("word-lists (sync merge)", allowed: !wordListsReadOnly) { try wordLists.save(to: wordListsURL) }
        }
        // Legacy v1.4 `SavedWords:deck` record: folded into the default list on EVERY fetch —
        // the deck is a permanent v1.4-compat mirror, not a one-time migration. (This comment
        // used to claim "once, then never again — a persisted flag in foldLegacyDeck enforces
        // it"; there is no such flag and never was. See foldLegacyDeck's own doc, which had
        // been saying the opposite. v1.10 §A3.)
        if let deckIDs { foldLegacyDeck(deckIDs) }
        if !cards.isEmpty {
            let remote = ReviewStore(cards: Dictionary(cards.map { ($0.id, $0) },
                                                       uniquingKeysWith: { a, _ in a }))
            reviewStore = SyncMerge.reviewStores(reviewStore, remote)
            bgSave("review (sync merge)", allowed: reviewStoreWritable) { try reviewStore.save(to: storeURL) }
        }
        if !records.isEmpty {
            // Display lifetime comes from the odometer, so rebuilding the journal
            // from merged records here can't undercount the odometer totals.
            let merged = SyncMerge.rideRecords(journal.records, records)
            journal = RideJournal(records: merged)
            bgSave("journal (sync merge)", allowed: journalWritable) { try journal.save(to: journalURL) }
        }
        if !odometerSlots.isEmpty {
            var remote = OdometerLog()
            for (id, slot) in odometerSlots { remote.setSlot(slot, for: id) }
            odometer = SyncMerge.odometers(odometer, remote)
            bgSave("odometer (sync merge)", allowed: odometerWritable) { try odometer.save(to: odometerURL) }
        }
        if !conjugationCards.isEmpty {
            // Merge into the SEPARATE conjugation SRS store (never the flat reviewStore,
            // red line §1). newer lastReviewed wins, per (verb, form) card.
            let remote = ConjugationReviewStore(cards: Dictionary(conjugationCards.map { ($0.id, $0) },
                                                                  uniquingKeysWith: { a, _ in a }))
            conjugationReviewStore = SyncMerge.conjugationReviewStores(conjugationReviewStore, remote)
            bgSave("conjugation review (sync merge)", allowed: conjugationStoreWritable) { [conjugationReviewStore, conjugationReviewURL] in
                try conjugationReviewStore.save(to: conjugationReviewURL)
            }
        }
        // Reminders read BOTH SRS stores (v1.14 §B), so they are rescheduled once, after both
        // merges — the call used to sit inside the vocab branch above, which meant a peer's
        // conjugation progress reached the app but never the badge, and a vocab-only fetch
        // rescheduled from a conjugation store that was still about to change.
        if !cards.isEmpty || !conjugationCards.isEmpty { refreshReminders() }
        // Republish the widget if the merge touched ANYTHING the snapshot derives from.
        // Gating on the review stores alone was too narrow: `streakByDay` comes from the
        // journal and `lifetimeWords` from the odometer, and both of those branches can fire
        // on their own — a Practice run uses a transient SRS store, so it syncs as records
        // only. The peer's ride would restore the streak in-app while the widget kept walking
        // its decay curve toward a streak the user had not actually lost. (v1.12 §C.)
        if !cards.isEmpty || !conjugationCards.isEmpty
            || !records.isEmpty || !odometerSlots.isEmpty { refreshWidgetSnapshot() }
    }

    /// Mirrors the live settings into the persisted blob and writes it. Cheap
    /// (a single UserDefaults write); called on each settings mutation.
    private func persistSettings() {
        guard settingsLoaded, !Screenshotter.isCapturing else { return }
        settings.languageCode = languageCode
        settings.assistance = assistance.rawValue
        // Kept in sync for a downgrade to v1.15, which reads only the boolean: "always" maps
        // to hints on, the other two to off — the closest older behaviour to each.
        settings.showRomajiHint = assistance == .always
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
        settings.exampleFurigana = exampleFurigana
        settings.save(to: Self.settingsStore)
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

    /// Speaks a DICTATION prompt. Deliberately not `speak(_:)`: that one is gated on
    /// `ttsEnabled`, which is the "show a read-aloud button on cards" preference — a
    /// different question from "play the prompt in the mode whose entire premise is
    /// listening". A learner who chose dictation has asked for audio; asking them to also
    /// find a settings toggle would be a trap. Availability is still respected, and the
    /// menu refuses to start the mode at all without a voice.
    func speakPrompt(_ text: String?) {
        guard let text, !text.isEmpty, ttsAvailable else { return }
        speech.speak(text, rate: ttsRate)
    }

    /// Whether the last dictation run got the audio session it asked for. False means the
    /// prompt may be inaudible on a muted iPhone, and the run says so rather than leaving
    /// the learner staring at silence.
    private(set) var dictationAudioSessionOK = true

    // MARK: Stats screen (v1.9 §B) — pure reads over the journal + conjugation store.
    var statsDailyWords: [(day: Date, words: Int)] { journal.dailyWords() }
    var statsAccuracySeries: [(date: Date, accuracy: Double)] { journal.accuracySeries() }
    var statsWPMSeries: [Double] { journal.wpmSeries() }
    var statsRunsByMode: [(mode: String, runs: Int)] { journal.runsByMode() }
    var statsBestWPM: Double? { journal.bestWPM }
    var statsHasRides: Bool { !journal.isEmpty }
    /// Near-term conjugation due buckets (surfaces the v1.8 conjugation SRS on the Stats screen).
    var conjugationDueForecast: ConjugationReviewStore.Forecast {
        conjugationReviewStore.dueForecast(resolves: vocab.resolvesID)
    }
    // Both filtered on the verb still existing, matching the vocabulary side of the same
    // Stats card, which has been filtered since v1.21. Unfiltered, "Forms practiced" counted
    // drills of withdrawn verbs and "Tough forms" promised the learner work they could never
    // finish — a leech whose verb is gone can never be reviewed away. Found in v1.24 §C by
    // removing the `resolves:` defaults: neither of these is a call with parentheses, so
    // `ResolvesCallSiteTests` never saw them. (Fifteenth instance of the same defect.)
    var conjugationReviewedCount: Int {
        conjugationReviewStore.reviewedCount(resolves: vocab.resolvesID)
    }
    var conjugationLeechCount: Int {
        conjugationReviewStore.leeches(resolves: vocab.resolvesID).count
    }

    /// Capture-only: seed demo journal + conjugation data so the Stats screenshot has content
    /// (the real journal is empty in a fresh render). No-op outside capture mode, where all file
    /// I/O is already redirected to a temp dir — this never touches the user's data.
    func seedDemoStatsData() {
        guard Screenshotter.isCapturing else { return }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var j = RideJournal()
        let words = [8, 0, 12, 15, 10, 18, 22, 0, 20, 25, 19, 28, 24, 30]   // ~2 weeks, upward
        for (i, w) in words.enumerated() where w > 0 {
            let day = cal.date(byAdding: .day, value: -(words.count - 1 - i), to: today)!.addingTimeInterval(36000)
            j.append(RideRecord(date: day, mode: i % 4 == 0 ? "practice" : "journey", level: "N5",
                                score: w * 20, wpm: 24 + Double(i), accuracy: min(0.99, 0.82 + Double(i) * 0.012),
                                wordsCompleted: w, lapsed: max(0, 3 - i / 4),
                                distanceMeters: Double(w) * 20, duration: 120))
        }
        journal = j
        var store = ConjugationReviewStore()
        let ids = ["たべる#te", "かく#past", "のむ#negative", "みる#potential", "はしる#volitional", "いく#te"]
        for (i, id) in ids.enumerated() {
            store.record(promptID: id, outcome: .init(completed: i % 3 != 0, mistakes: i % 3), on: today)
            if i < 2, var c = store.card(for: id) { c.dueDate = today.addingTimeInterval(-3600); store = ConjugationReviewStore(cards: store.cards.merging([id: c]) { _, n in n }) }
        }
        conjugationReviewStore = store
    }

    /// Words currently waiting in the review deck (due now).
    /// Only counts cards whose word still exists — the badge and the daily reminder are built
    /// from this, and a run drops unresolvable ids, so counting them here would promise work
    /// the app cannot hand over.
    var dueReviewCount: Int {
        reviewStore.dueCount(resolves: vocab.resolvesID)
    }
    var totalWordsSeen: Int { reviewStore.count }
    /// Words in the pool the next ride will actually draw new words from — i.e. the
    /// SELECTED level, or all levels when the picker is on "mixed" (`nil`), matching
    /// `GameSession.make`'s `vocab.ordered(level: config.level)`.
    ///
    /// This used to be `entries.count` under a hard-coded "N5 deck" label, which was
    /// wrong twice over: `entries` is all five packs concatenated, so the N5 deck was
    /// advertised at 7074 words when N5 has 646, and the number never moved when you
    /// switched level.
    var wordsAvailableAtLevel: Int {
        guard let level = selectedLevel else { return vocab.entries.count }
        return vocab.entries(level: level).count
    }

    /// Label for the pool above — the selected level, or "mixed", worded to match the
    /// level picker's own options so the footer can't disagree with the control.
    var wordPoolLabel: String {
        selectedLevel?.label ?? (languageCode == "zh" ? "混合" : "All")
    }

    // Lifetime totals prefer the cross-device odometer (G-Counter) but never show
    // less than the local journal's own accumulation (equal on a single device).
    var lifetimeWords: Int { max(journal.totalWords, odometer.totalWords) }
    var lifetimeDistanceMeters: Double { max(journal.totalDistanceMeters, odometer.totalDistanceMeters) }

    /// The stretch of road the CURRENT run is on, resolved when the run starts and then held.
    ///
    /// Frozen deliberately. If it tracked `lifetimeDistanceMeters` live, crossing a threshold
    /// mid-run would repaint the whole world behind the word the player is typing — the one
    /// thing a background in a typing app must never do. Freezing also means the reward lands
    /// where it reads as a reward: you set out on a new road, rather than having it change
    /// under you. (v1.12 §D.)
    private(set) var rideStage: RideStage = RideRoute.stages[0]

    /// Resolves the stage for a run about to start. Called by every start* path.
    func resolveRideStage() {
        rideStage = RideRoute.stage(forLifetimeMetres: lifetimeDistanceMeters)
    }

    /// Capture-only: pin a stage so the headless renderer can shoot the whole route without
    /// riding 25 km. Refuses outside capture, so it can never affect a real rider.
    func forceRideStage(_ stage: RideStage) {
        guard Screenshotter.isCapturing else { return }
        rideStage = stage
    }
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
        list.ids.reduce(0) { $0 + (vocab.entry(id: $1) != nil ? 1 : 0) }
    }

    /// How many of a list's words dictation can actually use — smaller again than
    /// `sentenceCount`, because a sentence also has to have survived the reading
    /// measurement. Three numbers describe a list ("20 words, 14 sentences, 11 you can
    /// hear") and only this one describes the run the learner is about to get.
    func dictationCount(in list: WordList) -> Int {
        GameSession.dictationEntries(ids: list.ids, vocab: vocab).count
    }

    /// Starts a DICTATION run drawn from a list's words (PLAN-V1.22 §A).
    func startDictationList(_ listID: String) {
        guard dictationAvailable, let list = wordLists.list(id: listID), !list.deleted else { return }
        var config = GameSession.Config()
        config.languageCode = languageCode
        config.assistance = .afterStruggle   // see startGame: dictation always keeps a way out
        config.newWordCount = Self.sentenceRunSize
        config.reviewWordCount = 0
        let built = GameSession.makeDictation(ids: list.ids, vocab: vocab, config: config)
        guard !built.isFinished else { return }
        beginDictationAudio()
        startSentenceRun(built)
    }

    /// How many due review words could carry a dictation prompt right now (menu gating).
    var dueDictationCount: Int {
        GameSession.dueDictationCount(review: reviewStore, vocab: vocab)
    }

    /// Starts a DICTATION run over the words whose review is due.
    func startDictationDue() {
        guard dictationAvailable else { return }
        var config = GameSession.Config()
        config.languageCode = languageCode
        config.assistance = .afterStruggle
        config.newWordCount = Self.sentenceRunSize
        config.reviewWordCount = 0
        let built = GameSession.makeDictation(due: reviewStore, vocab: vocab, config: config)
        guard !built.isFinished else { return }
        beginDictationAudio()
        startSentenceRun(built)
    }

    /// How many of a list's words have an example sentence that can be TYPED — a smaller
    /// number than `playableCount`, and a different question. A fully playable list can
    /// still have too few sentences to make a sentence run, so the sentence launcher needs
    /// its own count rather than reusing the word one. (PLAN-V1.21 §B.)
    func sentenceCount(in list: WordList) -> Int {
        GameSession.sentenceEntries(ids: list.ids, vocab: vocab).count
    }

    /// Toggles a word in the default ★ list and persists. All word-list writes run
    /// synchronously on the main actor (small file) so they stay ordered with the
    /// sync-merge writes to the same file — `Task.detached` raced last-writer-wins.
    func toggleSaved(_ id: String) { lastListError = toggleWord(id, in: WordList.defaultID) }

    /// Refuses a list mutation while the store is an unreadable-file stand-in, and says so.
    ///
    /// Checked at the ENTRY point, not just before the write: gating only `persistWordLists`
    /// would let the in-memory store change, so the UI would show a word starred that was
    /// never saved and will vanish on the next launch. Refusing up front keeps what the
    /// learner sees and what is on disk the same thing. (v1.16 §C.)
    private func refusesListMutation() -> Bool {
        guard wordListsReadOnly else { return false }
        lastPersistError = .listsUnreadable
        return true
    }

    /// Toggles a word in any list, persists, and enqueues that list for sync.
    /// Returns the resulting error (cap reached) for the UI to surface, else nil.
    @discardableResult
    func toggleWord(_ vocabID: String, in listID: String) -> WordListError? {
        if refusesListMutation() { return nil }
        switch wordLists.toggle(vocabID, in: listID) {
        case .success: persistWordLists(changed: [listID]); return nil
        case .failure(let error): return error
        }
    }

    @discardableResult
    func addWord(_ vocabID: String, to listID: String) -> WordListError? {
        if refusesListMutation() { return nil }
        switch wordLists.addWord(vocabID, to: listID) {
        case .success: persistWordLists(changed: [listID]); return nil
        case .failure(let error): return error
        }
    }

    func removeWord(_ vocabID: String, from listID: String) {
        if refusesListMutation() { return }
        if case .success = wordLists.removeWord(vocabID, from: listID) {
            persistWordLists(changed: [listID])
        }
    }

    @discardableResult
    func createList(name: String) -> Result<WordList, WordListError> {
        if refusesListMutation() { return .failure(.listNotFound) }
        let result = wordLists.createList(name: name)
        if case .success(let list) = result { persistWordLists(changed: [list.id]) }
        return result
    }

    @discardableResult
    func renameList(_ listID: String, to name: String) -> WordListError? {
        if refusesListMutation() { return nil }
        switch wordLists.rename(listID, to: name) {
        case .success: persistWordLists(changed: [listID]); return nil
        case .failure(let error): return error
        }
    }

    /// Soft-deletes a list (tombstone propagates; default list can't be deleted).
    @discardableResult
    func deleteList(_ listID: String) -> WordListError? {
        if refusesListMutation() { return nil }
        switch wordLists.softDelete(listID) {
        case .success:
            if selectedListID == listID { selectedListID = nil }
            persistWordLists(changed: [listID])
            return nil
        case .failure(let error): return error
        }
    }

    func clearList(_ listID: String) {
        if refusesListMutation() { return }
        if case .success = wordLists.clear(listID) { persistWordLists(changed: [listID]) }
    }

    /// Best-effort BACKGROUND / automatic persist: the write itself is unchanged
    /// (synchronous, main-actor, atomic — the red line), only failure handling
    /// changes. Never alerts (a persistently-failing disk would loop); logs so a
    /// failure isn't fully silent. (PLAN-V1.7 §D.)
    /// - Parameter allowed: false when this store was UNREADABLE at launch. The in-memory
    ///   store is then an empty stand-in, and writing it would replace a file that is
    ///   probably intact with nothing — undoing the loader's whole reason for distinguishing
    ///   "unreadable" from "corrupt". The write is skipped and logged loudly. (v1.15 §C.)
    private func bgSave(_ what: String, allowed: Bool = true, _ write: () throws -> Void) {
        guard allowed else {
            PersistLog.skipped(what, reason: "store was unreadable at launch; not overwriting it")
            return
        }
        do { try write() } catch { PersistLog.failure(what, error) }
    }

    /// Persists the word-list store synchronously + atomically, then tells the sync
    /// controller which list ids changed (no-op when sync is off). This is a
    /// USER-INITIATED path (list CRUD / ★), so a save failure surfaces an alert via
    /// `lastPersistError` — not just a log — so the user knows the change may be lost.
    private func persistWordLists(changed listIDs: [String]) {
        guard !wordListsReadOnly else {
            PersistLog.skipped("word-lists", reason: "file was unreadable at launch")
            lastPersistError = .listsUnreadable
            return
        }
        do {
            try wordLists.save(to: wordListsURL)
        } catch {
            lastPersistError = .saveFailed
            PersistLog.failure("word-lists", error)
            // Do NOT tell the sync controller about a change that did not reach disk. It used
            // to record it unconditionally, so a failed save still queued the in-memory state
            // for upload — the local file survived and the cloud got the version that didn't.
            return
        }
        syncController?.recordLocalChanges(listIDs: listIDs)
    }

    /// Re-reads the word-list file after a transient failure (file protection while locked,
    /// a busy volume). Clears the read-only state on success, so the user is not stranded
    /// until they think to relaunch. (v1.16 §C.)
    @discardableResult
    func retryLoadWordLists() -> Bool {
        let migration = WordListStore.loadOrMigrate(
            wordListsURL: wordListsURL,
            legacySavedWordsURL: savedWordsURL,
            defaultName: Self.defaultListName(languageCode))
        guard migration.outcome != .unreadableDeferred else { return false }
        wordLists = migration.store
        wordListsReadOnly = false
        lastPersistError = nil
        return true
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
        let resolvable = list.ids.filter(vocab.resolvesID)
        guard !resolvable.isEmpty else { return }
        var config = GameSession.Config()
        config.languageCode = languageCode
        config.assistance = assistance
        config.mode = .journey
        session = GameSession.makeSaved(
            ids: resolvable, vocab: vocab, review: reviewStore, config: config)
        conjugationSession = nil   // defensive: a list/saved run must not route to the conjugation screen
        runClock = RunClock(startedAt: Date())
        resolveRideStage()
        screen = .playing
    }

    /// Starts a SENTENCE run drawn from a list's words (PLAN-V1.21 §B). Same
    /// resolve-then-guard shape as `startListGame`, but the resolution test is stricter:
    /// a word only counts if it has a typeable sentence. The pool is never padded from the
    /// level pool — see `GameSession.makeSentence(ids:)` for why.
    func startSentenceList(_ listID: String) {
        guard let list = wordLists.list(id: listID), !list.deleted else { return }
        var config = GameSession.Config()
        config.languageCode = languageCode
        config.assistance = assistance
        config.newWordCount = Self.sentenceRunSize
        config.reviewWordCount = 0
        let built = GameSession.makeSentence(ids: list.ids, vocab: vocab, config: config)
        guard !built.isFinished else { return }
        startSentenceRun(built)
    }

    /// How many due review words could carry a sentence right now (menu gating).
    var dueSentenceCount: Int {
        GameSession.dueSentenceCount(review: reviewStore, vocab: vocab)
    }

    /// Starts a SENTENCE run over the words whose review is due, so the run doubles as
    /// review reading. It still writes no SRS — a whole-sentence mistake count is not a
    /// signal one word's card can carry (see `RunCompletion`).
    func startSentenceDue() {
        var config = GameSession.Config()
        config.languageCode = languageCode
        config.assistance = assistance
        config.newWordCount = Self.sentenceRunSize
        config.reviewWordCount = 0
        let built = GameSession.makeSentence(due: reviewStore, vocab: vocab, config: config)
        guard !built.isFinished else { return }
        startSentenceRun(built)
    }

    /// A sentence is many words' worth of keystrokes, so a run of the usual 30 would be
    /// enormous. Five is roughly a word run's length in characters.
    static let sentenceRunSize = 5

    // MARK: Dictation (v1.21 §A)

    /// Whether the dictation mode can run at all. A whole mode cannot degrade the way the
    /// read-aloud button does — that button hides itself and a learner who never saw it
    /// loses nothing. Pick dictation with no Japanese voice installed and you get a run of
    /// silence you cannot tell from a bug, so the menu says why and refuses to start
    /// instead of hiding the entry.
    var dictationAvailable: Bool { ttsAvailable && DictationSafety.isLoaded }

    /// How many sentences dictation may draw from at the chosen level — smaller than the
    /// sentence-mode pool, because sentences the synthesizer was measured to read
    /// differently from their own `exKana` are withheld (see `DictationSafety`).
    var dictationPoolCount: Int {
        let excluded = DictationSafety.excludedIDs
        let pool = selectedLevel.map { vocab.entries(level: $0) }
            ?? vocab.entries
        return pool.lazy.filter { $0.isTypeableSentence && !excluded.contains($0.id) }.count
    }

    /// True while a dictation run holds the audio session (iOS), so it is released exactly
    /// once no matter which of the three exits the run takes.
    private var holdingAudioSession = false

    private func beginDictationAudio() {
        guard !holdingAudioSession else { return }
        holdingAudioSession = true
        dictationAudioSessionOK = SpeechSynthesizer.beginSpokenPrompts()
    }

    private func endDictationAudio() {
        guard holdingAudioSession else { return }
        holdingAudioSession = false
        SpeechSynthesizer.endSpokenPrompts()
    }

    private func startSentenceRun(_ built: GameSession) {
        session = built
        conjugationSession = nil   // defensive: a sentence run must not route to the conjugation screen
        emptyPoolNotice = false
        runClock = RunClock(startedAt: Date())
        resolveRideStage()
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
    /// caught). Union reaches a fixpoint, so there is no ping-pong.
    ///
    /// **Tombstoned words are skipped (v1.10 §A1).** This doc used to argue there was
    /// "no resurrection asymmetry" because per-word un-save didn't propagate — true
    /// until §A made it propagate, at which point a blind fold silently undoes a
    /// removal on *every* fetch. And this is not only a v1.4 hazard: in an all-v1.10
    /// fleet a peer that hasn't fetched the tombstone yet rewrites the deck mirror
    /// WITH the word, and the same `applyCloudChanges` batch folds it back in one line
    /// after the merge removed it. The deck is a bare, timestamp-less set of ids, so
    /// "a v1.4 peer re-starred it just now" is genuinely indistinguishable from
    /// "pre-removal residue" — the bounded cost of choosing safety is that a v1.4
    /// peer's re-star after a removal is ignored. A removal must never be undone
    /// silently; a re-star that needs doing twice is survivable.
    private func foldLegacyDeck(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        let before = wordLists.defaultList?.ids
        let list = wordLists.defaultList
        for id in ids where list?.isPresent(id, inIDs: true) ?? true {
            _ = wordLists.addWord(id, to: WordList.defaultID)
        }
        if wordLists.defaultList?.ids != before {
            bgSave("word-lists (legacy fold)", allowed: !wordListsReadOnly) { try wordLists.save(to: wordListsURL) }
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
        config.assistance = assistance
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
        case .sentence:
            config.newWordCount = Self.sentenceRunSize
            config.reviewWordCount = 0
        case .dictation:
            config.newWordCount = Self.sentenceRunSize
            config.reviewWordCount = 0
            // Dictation runs at "when stuck" whichever way the setting is turned, and both
            // directions are deliberate.
            //
            // "Hints on" would print the romaji answer to a listening question before the
            // question was asked. "Off" is the worse one: in every other mode the target is
            // on the card, so a learner who cannot manage it can still copy it — but a
            // dictation card shows NOTHING, there is no skip control on the game screen, and
            // the struggle detector that offers the reveal only runs under `.afterStruggle`.
            // A learner who genuinely cannot make out the sentence would be stuck on it with
            // no way forward at all.
            config.assistance = .afterStruggle
        }
        let built: GameSession
        if selectedMode == .dictation {
            guard dictationAvailable else { return }
            built = GameSession.makeDictation(vocab: vocab, config: config)
        } else if selectedMode == .sentence {
            built = GameSession.makeSentence(vocab: vocab, config: config)
        } else if selectedMode == .practice && practicePassages {
            built = GameSession.makePractice(level: practicePassageLevel, config: config)
        } else {
            built = GameSession.make(config: config, vocab: vocab, review: reviewStore)
        }
        // Build-then-guard, like every sibling start path (startListGame, the weak-words
        // cram, the conjugation drill). This one had no guard, and Time Attack sets
        // reviewWordCount = 0 — so once a learner has typed every word at their level the
        // queue is empty, the session is already finished at construction, GameView's
        // defensive onAppear finishes it, and the results screen congratulates them on a run
        // with zero keystrokes at 100% accuracy. Staying on the menu is the honest outcome;
        // the menu explains why. (v1.15 §D.)
        guard !built.isFinished else {
            session = nil
            emptyPoolNotice = true
            // …and the menu is where that explanation lives (MenuView). This is also reached
            // from the results screen's "ride again" — Return, or the button — which is the
            // most likely moment for the pool to be exhausted, since the learner just typed
            // the last of it. Setting a notice on a screen that does not render it made that
            // tap do nothing at all. (v1.23 §B.)
            screen = .menu
            return
        }
        emptyPoolNotice = false
        session = built
        if built.mode == .dictation { beginDictationAudio() }
        runClock = RunClock(startedAt: Date())
        resolveRideStage()
        screen = .playing
    }

    // MARK: Weak-words cram (v1.7) — practice your hardest reviewed words, no SRS.

    /// Minimum reviewed words before the weak-words cram is offered (a cram of one
    /// or two words isn't worth a menu entry). Below this the menu hides the launcher.
    static let weakWordsMinimum = 5
    /// How many of the weakest words a single cram run drills.
    private static let weakWordsRunSize = 15

    /// How many reviewed words are available to cram. **Menu GATING only** — this is every
    /// card the learner has ever reviewed, uncapped, which is the right question for "is this
    /// button worth showing" and the wrong one for "how many words will I ride".
    var weakWordsPoolCount: Int {
        reviewStore.reviewedCount(resolves: vocab.resolvesID)
    }

    /// The weak-words button's spoken label, composed HERE rather than in the view.
    ///
    /// A view that holds a number can interpolate the wrong one, and this project has now done
    /// that nineteen times. Composing the string beside the queue it describes removes the
    /// choice from the call site: `MenuView` cannot pick the pool over the run because it is
    /// handed no number at all. That is a stronger guarantee than a test asserting the view
    /// picked correctly — and it was measured to be necessary, because restoring the original
    /// defect in `MenuView` left all 527 tests green. A unit test on a predicate is not a test
    /// of the screen that uses it.
    func weakWordsButtonLabel(zh: Bool) -> String {
        let n = weakWordsRunIDs.count
        return zh ? "弱词练习,\(n) 个薄弱词" : "Weak words drill, \(n) words"
    }

    /// The conjugation-review button's text and spoken label, composed for the same reason.
    func conjugationReviewButtonText(zh: Bool) -> String {
        let n = conjugationReviewQueue.count
        return zh ? "复习 \(n) 个到期变形" : "Review \(n) due"
    }

    func conjugationReviewButtonLabel(zh: Bool) -> String {
        let n = conjugationReviewQueue.count
        return zh ? "复习 \(n) 个到期的变形" : "Review \(n) due conjugations"
    }

    /// The ids a weak-words cram would actually ride: the cap applied and the withdrawn
    /// filtered, in that order.
    ///
    /// **The menu label and `startWeakWords` must BOTH read this**, and that is the whole
    /// point of its existing. The spoken label used to interpolate `weakWordsPoolCount`, so a
    /// learner with three hundred reviewed words was told three hundred and rode fifteen —
    /// instance nineteen of this app's oldest defect, and audible only to VoiceOver, which is
    /// why every headless render walked past it. Announcing the CAP instead would be the same
    /// defect mirrored: a learner with five weak words would be promised fifteen. The only
    /// number true in both directions is the length of the queue the button produces, so the
    /// count and the run are derived from one function and cannot disagree.
    /// `StumbledWords.rideableIDs` is the same shape for the same reason (v1.24 §A).
    var weakWordsRunIDs: [String] {
        reviewStore.weakestCards(limit: Self.weakWordsRunSize,
                                 resolves: vocab.resolvesID).map(\.id)
    }

    /// Starts a weak-words cram: the user's hardest reviewed words, run through the
    /// same journey loop but recording **NO SRS** (`makeWeak` → `recordsSRS = false`;
    /// a cram must not touch the SM-2 schedule — PLAN-V1.7 §B). Resolve-then-guard:
    /// bails if nothing resolves (the menu gates proactively via `weakWordsPoolCount`,
    /// so a silent no-op here can't strand the player on a blank screen).
    func startWeakWords() {
        // Filter INSIDE the cap. Capping first and filtering after is what shortened this run:
        // weakestCards sorts leeches to the front, and a withdrawn entry's card is a permanent
        // leech — it can never be reviewed away — so the unusable ids sat at the very front of
        // the fifteen and the ride came back with twelve. (v1.23 §B.)
        let resolvable = weakWordsRunIDs
        guard !resolvable.isEmpty else { return }
        var config = GameSession.Config()
        config.languageCode = languageCode
        config.assistance = assistance
        session = GameSession.makeWeak(ids: resolvable, vocab: vocab, config: config)
        conjugationSession = nil   // defensive: a cram must not route to the conjugation screen
        runClock = RunClock(startedAt: Date())
        resolveRideStage()
        screen = .playing
    }

    // MARK: Riding the words that stopped you (v1.24 §A)

    /// The words a sentence or dictation run stopped the learner on, resolved to ids.
    ///
    /// **The only way to ask this question.** The results screen shows a count and offers a
    /// run, and this project's recurring defect — fourteen instances — is a count and a run
    /// computed by different predicates that each looked right on their own. So both go
    /// through here, and here goes through `StumbledWords.rideableIDs`, which applies the run
    /// builder's own `resolves` test rather than a copy of it.
    ///
    /// - Parameter stumbles: the chips **as displayed**, not the full list. A screen that shows
    ///   six words and rides nine is the same broken promise as one that shows six and rides
    ///   four; "what you see is what you ride" is the version a screenshot can falsify.
    func rideableStumbles(_ stumbles: [StumbledWords.Stumble]) -> [String] {
        StumbledWords.rideableIDs(in: stumbles, resolves: vocab.resolvesID)
    }

    /// Rides the stumbled words as a word run, recording **no SRS**.
    ///
    /// `makeWeak`, not `makeSaved`, and the reason is that sentence and dictation runs
    /// deliberately do not persist SRS (`RunCompletion.persistsSRS` is false for both). These
    /// words were failed inside a sentence, not answered wrong as isolated cards, so letting
    /// the follow-up ride advance the SM-2 schedule would walk around that decision by the side
    /// door — and it would do it with a lapse signal that has never been calibrated for it.
    ///
    /// Resolve-then-guard, like every sibling start path: the ids were filtered before the
    /// button was drawn, and they are filtered again here, because the store can change between
    /// a render and a tap and a run of nothing is a blank screen.
    func startStumbledWords(_ stumbles: [StumbledWords.Stumble]) {
        let ids = rideableStumbles(stumbles)
        guard !ids.isEmpty else { return }
        var config = GameSession.Config()
        config.languageCode = languageCode
        config.assistance = assistance
        session = GameSession.makeWeak(ids: ids, vocab: vocab, config: config)
        conjugationSession = nil   // defensive: this must not route to the conjugation screen
        runClock = RunClock(startedAt: Date())
        resolveRideStage()
        screen = .playing
    }

    /// How many verbs are available to drill at the chosen level (menu gating).
    var conjugationPoolCount: Int {
        ConjugationSession.playableCount(vocab: vocab, level: selectedLevel)
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
        config.assistance = assistance
        config.level = selectedLevel
        config.promptCount = 12
        config.setForms(rawValues: conjugationForms)   // empty / unknown → all forms
        let chooser = ConjugationSession.weightedFormChooser(weakBiasedPick: conjugationWeakFormPick())
        let built = ConjugationSession.make(vocab: vocab, config: config, chooseForm: chooser)
        // Resolve-then-guard: an empty pool must not enter the (already-finished) screen.
        // The menu surfaces this proactively via `conjugationPoolCount == 0`, so a no-op
        // here is never silent.
        guard built.promptCount > 0 else { return }
        built.onOutcome = conjugationOutcomeSink()
        session = nil
        conjugationSession = built
        runClock = RunClock(startedAt: Date())
        resolveRideStage()
        screen = .playing
    }

    /// How many (verb, form) cards are due for conjugation review right now. **Menu GATING
    /// only** — uncapped, so it answers "is anything due" and not "how many will I ride".
    var conjugationDueCount: Int {
        conjugationReviewStore.dueCount(resolves: vocab.resolvesID)
    }

    /// The due (verb, form) pairs a review drill would actually ride: the cap applied.
    ///
    /// **The menu label and `startConjugationReview` must BOTH read this.** The label printed
    /// `conjugationDueCount`, which is every due card and uncapped, while the run took twelve —
    /// so a learner with thirty due forms was told thirty and rode twelve. What let this one
    /// survive is worth naming: the builder carried the comment *"Same predicate the menu label
    /// counts with"*, and that is TRUE and insufficient. The two sides did share a predicate;
    /// they never shared the cap. A comment asserting the half of a contract that holds is a
    /// new sub-species of this project's cheapest detector, and it defeated it.
    var conjugationReviewQueue: [(entryID: String, formToken: String)] {
        conjugationReviewStore.dueCards(limit: Self.conjugationRunSize,
                                        resolves: vocab.resolvesID)
            .map { (entryID: $0.sourceID, formToken: $0.formToken) }
    }

    /// Starts a **due-review** conjugation drill: the due (verb, form) cards first, then
    /// fresh forms filled in (weak-form weighted). Resolve-then-guard like `startConjugation`
    /// — a run that resolves to nothing (all due cards point at removed vocab) does NOT enter
    /// the screen. Due review spans all levels (the due cards define its scope).
    func startConjugationReview() {
        // The SAME queue the menu label counts — not merely the same predicate, which is the
        // distinction this comment used to get wrong. `resolves:` keeps the orphans out: a card
        // whose verb is gone is never reviewed away, so it stays maximally overdue, sorts FIRST,
        // spends a slot inside the limit and is then dropped by makeReview and padded over with
        // a fresh prompt. (v1.23 §B for the filter; v1.26 §B for sharing the cap.)
        let due = conjugationReviewQueue
        var config = ConjugationSession.Config()
        config.languageCode = languageCode
        config.assistance = assistance
        config.level = nil                      // review pulls from the whole due set / pool
        config.promptCount = Self.conjugationRunSize
        let chooser = ConjugationSession.weightedFormChooser(weakBiasedPick: conjugationWeakFormPick())
        let built = ConjugationSession.makeReview(due: due, vocab: vocab, config: config,
                                                  chooseForm: chooser)
        guard built.promptCount > 0 else { return }
        built.onOutcome = conjugationOutcomeSink()
        session = nil
        conjugationSession = built
        runClock = RunClock(startedAt: Date())
        resolveRideStage()
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
        bgSave("conjugation review", allowed: conjugationStoreWritable) { [conjugationReviewStore, conjugationReviewURL] in
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
        refreshWidgetSnapshot()   // conjugation due count moved
        refreshReminders()        // …and so did the badge / the next 7 days of reminders
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
        endDictationAudio()
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
            bgSave("review (run)", allowed: reviewStoreWritable) { try reviewStore.save(to: storeURL) }
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
        refreshWidgetSnapshot()   // the due count just moved
        screen = completion.showsResults ? .results : .menu
    }

    func backToMenu() {
        session = nil
        conjugationSession = nil
        runClock = nil
        stopSpeaking()
        endDictationAudio()
        screen = .menu
    }

    /// Appends the finished run to the ride journal + odometer and persists them.
    /// Returns the appended record, or nil for an abandoned run (nothing typed)
    /// that isn't worth remembering.
    @discardableResult
    private func logRun(_ session: GameSession) -> RideRecord? {
        guard session.wordsCompleted > 0 || session.correctKeystrokes > 0 else {
            runClock = nil
            return nil
        }
        let now = Date()
        // Ridden time, not wall clock — see RunClock. The WPM convention lives there too, so
        // the journal row and the live readout cannot drift apart.
        let clock = runClock ?? RunClock(startedAt: now)
        let duration = clock.elapsed(at: now)
        let wpm = clock.wpm(correctKeystrokes: session.correctKeystrokes, at: now)
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
        bgSave("journal (run)", allowed: journalWritable) { try journal.save(to: journalURL) }
        bgSave("odometer (run)", allowed: odometerWritable) { try odometer.save(to: odometerURL) }
        runClock = nil
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

    /// Redirects every persisted store somewhere harmless. Nil in the shipping app.
    ///
    /// `AppModel()` reads — and once a run finishes, writes — the machine's real
    /// `Application Support/NihongoRide`: the owner's review schedule, ride journal, odometer
    /// and word lists, all of it iCloud-synced. An app-layer test target that constructed a
    /// model without this would assert against live data and log invented rides into it, on
    /// the owner's own machine, and the damage would sync. So the test target sets this before
    /// it constructs anything, and `AppModelTests.makeModel` is the only way it does.
    ///
    /// Screenshot capture needed the same escape first and got a FIXED temp path; this one is
    /// chosen by the caller, because tests run in parallel and a shared directory would let
    /// them read each other's stores. (v1.24 §B.)
    static var supportDirectoryOverride: URL?

    /// Where the widget snapshot goes. Nil in the shipping app, meaning the real App Group.
    ///
    /// `supportDirectoryOverride` covers `supportFileURL` and nothing else, and the widget
    /// snapshot is written OUTSIDE it — which is how the app tests came to overwrite the
    /// owner's real home-screen widget with zeros. That was first closed by refusing to write
    /// when `Bundle.main.bundleIdentifier` is nil, and the review then measured that this is a
    /// PROXY rather than the property: under XCTest hosting the identifier is
    /// "com.apple.dt.xctest.tool" and the container still resolves, so one `import XCTest` test
    /// that builds an AppModel reopens the identical hole. This is the property itself — the
    /// test says where the snapshot may land, and no runner detail can move it. (v1.24.)
    static var widgetContainerOverride: URL?

    /// Where settings persist. Nil in the shipping app, meaning `UserDefaults.standard`.
    ///
    /// The third location outside `supportFileURL`, and the third time the answer was "add
    /// another override": settings are the one store this model writes that is neither a file
    /// under Application Support nor the App Group. In the test process `.standard` is the
    /// runner's own domain, so each run left `NihongoRide.settings.v1` behind for the next one
    /// to read — languageCode, selectedMode, selectedLevel, hasSeenOnboarding, deviceID. Not
    /// damage (the shipping app is sandboxed and keeps its own), but a suite whose result can
    /// depend on what a previous run happened to persist is not a suite worth trusting.
    static var settingsDefaults: UserDefaults?

    static var settingsStore: UserDefaults {
        if let settingsDefaults { return settingsDefaults }
        // A UI-test launch must not inherit or leave behind the simulator's real settings —
        // languageCode and selectedMode decide which screen a flow test lands on, so a case
        // that passes only because a previous one left the app in Sentence mode proves nothing.
        if let suite = currentIsolation.settingsSuite, let defaults = UserDefaults(suiteName: suite) {
            return defaults
        }
        return .standard
    }

    static func supportFileURL(_ name: String) -> URL {
        let fm = FileManager.default
        // Screenshot capture redirects ALL file I/O to a throwaway temp dir, so a
        // headless render never reads or writes the machine's real data. (Capture
        // models mint a fresh deviceID and run startGame/finishGame, which would
        // otherwise pollute the real, iCloud-synced odometer/journal/word-lists —
        // and leak the real review queue into store screenshots.)
        let base: URL = currentIsolation.supportBase
            ?? (fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory)
        let dir = base.appendingPathComponent("NihongoRide", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }
}
