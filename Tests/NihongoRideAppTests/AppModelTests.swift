import Testing
import Foundation
import VocabKit
import GameCore
import ReviewKit
import ConjugationReviewKit
import WidgetSharedKit
@testable import NihongoRideApp

/// The app layer, under test for the first time.
///
/// v1.23 shipped its dead-tap fix with no execution evidence — the guard was read, agreed with,
/// and never run — because nothing could put `AppModel` into the state that would prove it.
/// Importing was never the obstacle: an `executableTarget` is `@testable import`-able on Swift
/// 6.3.3, `@main` and all. ARRANGING was. A test that constructed the model and called
/// `startGame()` would pass, and pass for nothing, because a fresh model at N5 has a full pool,
/// so the empty-pool guard never fires and `screen != .results` holds for the wrong reason.
/// `AppModel(vocab:)` is what makes that arrangeable, and every test here depends on it.
@MainActor
@Suite("AppModel — the guards that had no test")
struct AppModelTests {

    // MARK: Arrangement

    /// A model whose persisted stores live in a throwaway directory.
    ///
    /// **The only way this target constructs an AppModel.** Without the redirect, `init` reads
    /// the machine's real Application Support and `finishGame` writes back to it — meaning a
    /// test run on the owner's own Mac would assert against their live review schedule and log
    /// invented rides into an iCloud-synced journal. A unique directory per model, because
    /// swift-testing runs these in parallel and a shared one would let them read each other's.
    static func makeModel(vocab: VocabStore) -> AppModel { sandboxed(vocab: vocab).model }

    /// The same construction, handing back the directory it was sandboxed into so a test can
    /// check the sandbox rather than take it on trust.
    static func sandboxed(vocab: VocabStore) -> (model: AppModel, directory: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NihongoRideAppTests-\(UUID().uuidString)", isDirectory: true)
        AppModel.supportDirectoryOverride = dir
        // The App Group container is a SECOND location outside supportFileURL, and it is the
        // one the tests actually clobbered. Redirected explicitly rather than relying on the
        // bundle-identifier guard, which the review measured to be non-nil under XCTest hosting.
        AppModel.widgetContainerOverride = dir.appendingPathComponent("group", isDirectory: true)
        // …and settings, which live in UserDefaults rather than in either directory. A private
        // suite per model, so one test cannot inherit what another persisted.
        AppModel.settingsDefaults = UserDefaults(suiteName: "NihongoRideTests-\(UUID().uuidString)")
        return (AppModel(vocab: vocab), dir)
    }

    /// A sandboxed model whose review stores are SEEDED before `init` reads them.
    ///
    /// Both stores are `private(set)`, and deliberately: `record` is the only writer. So a test
    /// that needs a learner with history arranges it the way the app does — by persisting a
    /// store into the sandbox directory and letting `init` load it — rather than by widening
    /// the model's API for the test's convenience.
    static func seeded(vocab: VocabStore,
                       review: ReviewStore? = nil,
                       conjugation: ConjugationReviewStore? = nil) -> AppModel {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NihongoRideAppTests-\(UUID().uuidString)", isDirectory: true)
        AppModel.supportDirectoryOverride = dir
        AppModel.widgetContainerOverride = dir.appendingPathComponent("group", isDirectory: true)
        AppModel.settingsDefaults = UserDefaults(suiteName: "NihongoRideTests-\(UUID().uuidString)")
        // `supportFileURL` puts its files in a "NihongoRide" subdirectory of the override, so
        // seeds must be written through IT rather than into the override root — writing them
        // one level too high produced a model with empty stores and a suite whose assertions
        // all read zero. Asking the app where its files go is the only version that cannot rot.
        let encoder = JSONEncoder()
        if let review, let data = try? encoder.encode(review) {
            try? data.write(to: AppModel.supportFileURL("review.json"))
        }
        if let conjugation, let data = try? encoder.encode(conjugation) {
            try? data.write(to: AppModel.supportFileURL("conjugation-review.json"))
        }
        let model = AppModel(vocab: vocab)
        // The seed itself is a claim. A helper that silently seeded nothing would make every
        // test built on it pass for the wrong reason, which is this project's signature failure.
        if let review { precondition(model.reviewStore.count == review.count,
                                     "review seed did not load: expected \(review.count), got \(model.reviewStore.count)") }
        if let conjugation { precondition(model.conjugationReviewStore.count == conjugation.count,
                                          "conjugation seed did not load: expected \(conjugation.count), got \(model.conjugationReviewStore.count)") }
        return model
    }

    /// A reviewed card that is genuinely weak, so `weakestCards` will rank it.
    static func weakCard(_ id: String, lapses: Int) -> SRSCard {
        var card = SRSCard(id: id)
        card.totalReviews = 5
        card.totalMistakes = 4
        card.lapses = lapses
        card.easeFactor = 1.5
        return card
    }

    /// A conjugation card that is overdue.
    static func dueConjugationCard(_ sourceID: String, _ form: String) -> ConjugationSRSCard {
        var card = ConjugationSRSCard(id: "\(sourceID)#\(form)")
        card.dueDate = Date().addingTimeInterval(-60 * 60 * 24 * 30)
        card.totalReviews = 1
        return card
    }

    /// Two words with typeable sentences, so a sentence or word run has something to build from.
    static func entry(_ id: String, _ surface: String, _ kana: String,
                      sentence: Bool = true) -> VocabEntry {
        VocabEntry(id: id, surface: surface, kana: kana, partsOfSpeech: ["n"], jlpt: .n5,
                   meanings: ["en": [id], "zh": [id]],
                   exampleJP: sentence ? "\(surface)です。" : nil,
                   exampleEN: sentence ? "It is \(id)." : nil,
                   exampleZH: sentence ? "是\(id)。" : nil,
                   exampleKana: sentence ? "\(kana)です" : nil,
                   exampleTokens: sentence ? [[surface, kana], ["です", "です"], ["。", "。"]] : nil)
    }

    /// The arrangement itself is a claim, so check it. A "sandboxed" test that silently fell
    /// back to the real directory would be worse than no test — it would be an instrument
    /// reporting clean while writing to the thing it was protecting.
    /// Asserted against THIS call's own directory, not against "somewhere under /tmp". The
    /// weaker version would pass because a parallel test had set the override a moment earlier,
    /// which would make it a test that grades itself — the exact failure v1.23 logged when an
    /// end-to-end test computed its expected value with the function under test.
    @Test("the test harness really does redirect persistence away from the real store")
    func harnessIsSandboxed() {
        let (_, directory) = Self.sandboxed(vocab: VocabStore(entries: []))
        let path = AppModel.supportFileURL("review.json").path
        #expect(path.hasPrefix(directory.path), "persistence is not sandboxed: \(path)")
        let real = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("NihongoRide").path
        if let real { #expect(!path.hasPrefix(real), "the tests are writing to the real store") }
    }

    /// Every file this process could reach that belongs to the person running the tests,
    /// with the modification date it had when we looked.
    ///
    /// Two locations, because the sandbox only ever covered one of them and that is precisely
    /// how this got out: `supportDirectoryOverride` redirects `supportFileURL`, and the widget
    /// snapshot is written to the **App Group container**, which `supportFileURL` never names.
    static var realUserRoots: [URL] {
        var roots: [URL] = []
        if let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first {
            roots.append(support.appendingPathComponent("NihongoRide", isDirectory: true))
        }
        if let group = AppGroup.containerURL() { roots.append(group) }
        return roots
    }

    static func fileStamps(in roots: [URL]) -> [String: Date] {
        var stamps: [String: Date] = [:]
        for root in roots {
            let files = (try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for file in files {
                let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate
                stamps[file.path] = date ?? .distantPast
            }
        }
        return stamps
    }

    static func realUserFileStamps() -> [String: Date] { fileStamps(in: realUserRoots) }

    /// **The test that would have caught the one this suite shipped.**
    ///
    /// v1.24 added this target, and every model it built wrote a snapshot computed from an
    /// EMPTY sandbox store onto the owner's real home-screen widget — fourteen days of zeros
    /// over their actual due counts and streak, once per `swift test`, on their own machine.
    /// It had already happened by the time the pre-submission review found it.
    ///
    /// `harnessIsSandboxed` could not see it: it asserts a path under Application Support and
    /// the leak was in the App Group container. So this asserts the property that actually
    /// matters — **running the tests changes nothing that belongs to the user** — rather than
    /// the one mechanism that was known about when the harness was written. Anything new that
    /// escapes the sandbox trips this without anyone having to predict which door it used.
    @Test("running the app-layer tests writes nothing outside the sandbox")
    func nothingOutsideTheSandboxIsWritten() {
        let before = Self.realUserFileStamps()
        // A model plus the events that persist: a finished run merges SRS, logs a ride,
        // refreshes the widget snapshot and saves settings.
        let model = Self.makeModel(vocab: VocabStore(entries: [
            Self.entry("a", "水", "みず"), Self.entry("b", "火", "ひ")]))
        model.startGame()
        model.session?.skip()
        model.finishGame()
        model.refreshWidgetSnapshot()
        let after = Self.realUserFileStamps()
        let touched = after.filter { before[$0.key] != $0.value }.keys.sorted()
        #expect(touched.isEmpty, "the tests wrote to the user's own data: \(touched)")
    }

    /// The instrument, calibrated on a directory we own.
    ///
    /// The first version of the test above ended with `#expect(!before.isEmpty)` — a self-check
    /// so it could not report "nothing was touched" while seeing nothing at all. It was the
    /// right instinct aimed at the wrong thing: on a fresh clone, a CI box or a second Mac,
    /// nobody has run the shipped app, both roots are empty, and that assertion fails for a
    /// reason unrelated to the property. The predictable repair is to delete it, which would
    /// leave a null instrument behind. So the detection is proven HERE instead, where the files
    /// are ours and always exist. (Found by the v1.24 pre-submission review.)
    @Test("the write detector actually detects a write")
    func writeDetectorIsCalibrated() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NihongoRideProbe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("snapshot.json")
        try Data("before".utf8).write(to: file)

        let before = Self.fileStamps(in: [root])
        #expect(before.count == 1, "the walk did not see a file that is definitely there")
        // A different date, not merely different bytes: the comparison is on mtime, and a same
        // -second rewrite would otherwise look unchanged and make this pass for the wrong reason.
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: file.path)
        let after = Self.fileStamps(in: [root])
        let changed = after.filter { before[$0.key] != $0.value }.keys.sorted()
        // Compared on the last component: /var is a symlink to /private/var on macOS, so the
        // path the walk reports and the path we wrote are the same file under two names.
        #expect(changed.map { ($0 as NSString).lastPathComponent } == ["snapshot.json"],
                "the detector missed a write it was looking straight at: \(changed)")
    }

    // MARK: The dead tap (v1.23 §B, shipped with no execution evidence)

    /// "Ride again" at an exhausted level did nothing at all, for a release.
    ///
    /// `startGame`'s empty-pool notice renders only on the menu, and the guard set the notice
    /// without leaving the results screen — so the button the learner is most likely to press
    /// at exactly the moment the pool empties (they just typed the last of it) was inert. The
    /// fix is one line, `screen = .menu`, and this is the first thing that has ever run it.
    ///
    /// The arrangement is the whole test: an EMPTY store, so the built session is finished at
    /// construction and the guard actually fires. From a full store this passes vacuously.
    @Test("ride again on an exhausted pool leaves the results screen for the menu")
    func rideAgainOnEmptyPoolReturnsToMenu() {
        let model = Self.makeModel(vocab: VocabStore(entries: []))
        model.screen = .results          // where "ride again" is pressed
        model.startGame()
        #expect(model.screen == .menu, "the learner was left on results with a dead button")
        #expect(model.emptyPoolNotice, "the menu has nothing to explain the dead ride")
        #expect(model.session == nil, "a finished session must not be handed to the game screen")
    }

    /// The other half of the guard: it must not fire when there IS something to ride, or the
    /// test above would also pass with `startGame` replaced by `screen = .menu`.
    @Test("a pool with words still starts a run")
    func nonEmptyPoolStartsARun() {
        let model = Self.makeModel(vocab: VocabStore(entries: [
            Self.entry("a", "水", "みず"), Self.entry("b", "火", "ひ")]))
        model.screen = .results
        model.startGame()
        #expect(model.screen == .playing)
        #expect(model.emptyPoolNotice == false)
        #expect(model.session != nil)
    }

    // MARK: The count and the run (v1.24 §A)

    static let stumbleStore = VocabStore(entries: [
        entry("hand", "手", "て"), entry("water", "水", "みず"), entry("fire", "火", "ひ")])

    static func chips(_ pairs: [(String, String, String?)]) -> [StumbledWords.Stumble] {
        pairs.map { StumbledWords.Stumble(surface: $0.0, reading: $0.1, refusals: 2, entryID: $0.2) }
    }

    /// The contract the results screen hangs a number on: **what you see is what you ride.**
    ///
    /// Fourteen times now this app has shown a count computed by one predicate beside a run
    /// built with another, and every one of them passed review because both halves looked right
    /// in isolation. So this asserts them against each other rather than against a literal: the
    /// number on the button and the length of the queue the button produces.
    @Test("the ride button's count is exactly the number of words the run contains")
    func rideCountMatchesTheRun() throws {
        let model = Self.makeModel(vocab: Self.stumbleStore)
        // Three actionable words and two that name nothing — a particle and an auxiliary, which
        // is what a dictation results screen genuinely holds.
        let displayed = Self.chips([("手", "て", "hand"), ("を", "を", nil),
                                    ("水", "みず", "water"), ("ます", "ます", nil),
                                    ("火", "ひ", "fire")])
        let promised = model.rideableStumbles(displayed).count
        #expect(promised == 3)
        model.startStumbledWords(displayed)
        let ridden = try #require(model.session).wordList.count
        #expect(ridden == promised, "promised \(promised) words and the run contains \(ridden)")
    }

    // MARK: v1.26 §B — instances nineteen and twenty of the same defect

    /// **The weak-words button announced the pool and rode fifteen.**
    ///
    /// `weakWordsPoolCount` is every card the learner has ever reviewed, uncapped; the run is
    /// `weakestCards(limit: 15)`. A learner with thirty reviewed words was told thirty and rode
    /// fifteen. The visible label carries no number at all — this is spoken only to VoiceOver,
    /// which is why every headless render this project has taken walked straight past it.
    ///
    /// Asserted against each other rather than against a literal, because a literal is exactly
    /// how the suite that SHOULD have held this failed: `ReviewKitTests.swift:217` opens by
    /// quoting the promise — "The menu promises `weakWordsPoolCount` weak words" — then fixtures
    /// twenty cards against a limit of fifteen and asserts `cards.count == 15` as the correct
    /// answer. The contract is written down, the test is green, and nothing checks the contract.
    @Test("the weak-words button speaks the length of the run it starts, not the pool")
    func weakWordsSpokenCountMatchesTheRun() throws {
        let entries = (0..<30).map { Self.entry("w\($0)", "語\($0)", "ご\($0)") }
        let cards = Dictionary(uniqueKeysWithValues: entries.enumerated().map {
            ($1.id, Self.weakCard($1.id, lapses: $0))
        })
        let model = Self.seeded(vocab: VocabStore(entries: entries),
                                review: ReviewStore(cards: cards))
        // The pool must genuinely exceed the run, or this passes for nothing.
        #expect(model.weakWordsPoolCount == 30)
        let spoken = model.weakWordsRunIDs.count
        #expect(spoken == 15, "the cap is 15, so the button may promise at most 15")
        #expect(spoken != model.weakWordsPoolCount, "fixture too small to separate pool from run")
        model.startWeakWords()
        let ridden = try #require(model.session).wordList.count
        #expect(ridden == spoken, "spoke \(spoken) words and the run contains \(ridden)")
    }

    /// The label itself, in BOTH languages, because one rule written twice will drift and this
    /// one already was: the Chinese string interpolated the same wrong count as the English.
    /// A scan keyed on the word "words" would have passed the English fix and left 个薄弱词
    /// wrong. Asserting the composed string is what covers both at once.
    @Test("the weak-words label states the run length in both languages")
    func weakWordsLabelStatesTheRun() {
        let entries = (0..<30).map { Self.entry("w\($0)", "語\($0)", "ご\($0)") }
        let cards = Dictionary(uniqueKeysWithValues: entries.enumerated().map {
            ($1.id, Self.weakCard($1.id, lapses: $0))
        })
        let model = Self.seeded(vocab: VocabStore(entries: entries),
                                review: ReviewStore(cards: cards))
        let run = model.weakWordsRunIDs.count
        #expect(run == 15)
        #expect(model.weakWordsPoolCount == 30, "the two must differ or this proves nothing")
        #expect(model.weakWordsButtonLabel(zh: false) == "Weak words drill, \(run) words")
        #expect(model.weakWordsButtonLabel(zh: true) == "弱词练习,\(run) 个薄弱词")
        // …and neither language may state the pool.
        #expect(!model.weakWordsButtonLabel(zh: false).contains("30"))
        #expect(!model.weakWordsButtonLabel(zh: true).contains("30"))
    }

    /// The same for the conjugation button, whose number is VISIBLE as well as spoken.
    @Test("the conjugation-review label states the run length in both languages")
    func conjugationReviewLabelStatesTheRun() {
        let verbs = (0..<10).map {
            VocabEntry(id: "v\($0)", surface: "書\($0)", kana: "か\($0)",
                       partsOfSpeech: ["v"], jlpt: .n5,
                       meanings: ["en": ["write"], "zh": ["\u{5199}"]], vc: "godan_k")
        }
        var cards: [String: ConjugationSRSCard] = [:]
        for verb in verbs {
            for form in ["masu", "past", "te"] {
                let card = Self.dueConjugationCard(verb.id, form)
                cards[card.id] = card
            }
        }
        let model = Self.seeded(vocab: VocabStore(entries: verbs),
                                conjugation: ConjugationReviewStore(cards: cards))
        let run = model.conjugationReviewQueue.count
        #expect(run == 12)
        #expect(model.conjugationDueCount == 30, "the two must differ or this proves nothing")
        #expect(model.conjugationReviewButtonText(zh: false) == "Review \(run) due")
        #expect(model.conjugationReviewButtonText(zh: true) == "复习 \(run) 个到期变形")
        #expect(model.conjugationReviewButtonLabel(zh: false) == "Review \(run) due conjugations")
        #expect(model.conjugationReviewButtonLabel(zh: true) == "复习 \(run) 个到期的变形")
        for label in [model.conjugationReviewButtonText(zh: false),
                      model.conjugationReviewButtonText(zh: true),
                      model.conjugationReviewButtonLabel(zh: false),
                      model.conjugationReviewButtonLabel(zh: true)] {
            #expect(!label.contains("30"), "\(label) states the pool, not the run")
        }
    }

    /// The mirror image, which is the trap in PLAN-V1.25 §B's unbuilt check: it specified that
    /// the label must "name the quantity the builder caps on", and naming the CAP promises
    /// fifteen to a learner who has five. The only number true in both directions is the length
    /// of the queue the button produces.
    @Test("with fewer weak words than the cap, the button speaks the smaller number")
    func weakWordsBelowTheCapSpeaksThePool() throws {
        let entries = (0..<6).map { Self.entry("w\($0)", "語\($0)", "ご\($0)") }
        let cards = Dictionary(uniqueKeysWithValues: entries.enumerated().map {
            ($1.id, Self.weakCard($1.id, lapses: $0))
        })
        let model = Self.seeded(vocab: VocabStore(entries: entries),
                                review: ReviewStore(cards: cards))
        let spoken = model.weakWordsRunIDs.count
        #expect(spoken == 6, "six reviewed words against a cap of fifteen — the promise is six")
        model.startWeakWords()
        #expect(try #require(model.session).wordList.count == spoken)
    }

    /// **The conjugation-review button announced every due card and rode twelve.**
    ///
    /// What let this one survive is the interesting part: `startConjugationReview` carried the
    /// comment *"Same predicate the menu label counts with (`conjugationDueCount`)"*, which is
    /// TRUE and insufficient. The two sides did share a predicate; they never shared the cap.
    /// A comment asserting the half of a contract that holds defeats this project's cheapest
    /// detector — "where a comment states a contract, check whether anything enforces it" —
    /// by making the contract look as though it were already checked.
    @Test("the conjugation-review button shows the length of the run it starts, not every due card")
    func conjugationReviewCountMatchesTheRun() {
        let verbs = (0..<10).map {
            VocabEntry(id: "v\($0)", surface: "書\($0)", kana: "か\($0)",
                       partsOfSpeech: ["v"], jlpt: .n5,
                       meanings: ["en": ["write"], "zh": ["\u{5199}"]], vc: "godan_k")
        }
        var cards: [String: ConjugationSRSCard] = [:]
        for verb in verbs {
            for form in ["masu", "past", "te"] {
                let card = Self.dueConjugationCard(verb.id, form)
                cards[card.id] = card
            }
        }
        let model = Self.seeded(vocab: VocabStore(entries: verbs),
                                conjugation: ConjugationReviewStore(cards: cards))
        // Thirty due against a cap of twelve — the exact shape the learner was mis-told.
        #expect(model.conjugationDueCount == 30)
        let shown = model.conjugationReviewQueue.count
        #expect(shown == 12, "the cap is 12, so the button may promise at most 12")
        #expect(shown != model.conjugationDueCount,
                "if these are equal the fixture is too small to prove anything")
    }

    /// The same contract where it actually broke before: an id that no longer resolves. The run
    /// builder drops it, so the count must drop it too — a withdrawn entry is a permanent leech
    /// and would inflate this forever.
    @Test("a chip naming a withdrawn entry is neither counted nor ridden")
    func withdrawnEntryDropsFromBothSides() {
        let model = Self.makeModel(vocab: Self.stumbleStore)
        let displayed = Self.chips([("手", "て", "hand"), ("風", "かぜ", "retired-in-v1-18")])
        let promised = model.rideableStumbles(displayed).count
        #expect(promised == 1)
        model.startStumbledWords(displayed)
        #expect(model.session?.wordList.count == promised)
    }

    /// A ride of nothing is a blank screen. The button is hidden when the count is zero, and
    /// the model refuses anyway, because the store can change between a render and a tap.
    @Test("chips that name nothing start no run at all")
    func nothingRideableStartsNothing() {
        let model = Self.makeModel(vocab: Self.stumbleStore)
        model.screen = .results
        model.startStumbledWords(Self.chips([("を", "を", nil), ("ます", "ます", nil)]))
        #expect(model.session == nil)
        #expect(model.screen == .results, "a refused start must not navigate anywhere")
    }

    /// Riding stumbled words must not advance the SM-2 schedule. Sentence and dictation runs
    /// deliberately persist no SRS, and letting their follow-up ride do it would walk around
    /// that decision by the side door.
    @Test("riding stumbled words records no SRS")
    func stumbledRideRecordsNoSRS() throws {
        let model = Self.makeModel(vocab: Self.stumbleStore)
        model.startStumbledWords(Self.chips([("手", "て", "hand")]))
        let session = try #require(model.session)
        #expect(session.config.recordsSRS == false)
        #expect(GameSummary(from: session).persistsSRS == false)
    }

    // MARK: The tile that promised a review nothing would deliver (v1.24 §B)

    /// `persistsSRS` is what `finishGame` gates the SRS merge on, and now what the results
    /// screen reads to decide whether "To review" is a promise it can keep. Asserted against
    /// `RunCompletion` — the run's own rule — rather than against a list of modes, which is the
    /// form this defect keeps taking.
    @Test("the summary agrees with the run about whether anything was scheduled")
    func summaryAgreesWithRunCompletion() {
        for mode in [GameMode.journey, .timeAttack, .sentence, .dictation, .practice] {
            for records in [true, false] {
                var config = GameSession.Config()
                config.mode = mode
                config.recordsSRS = records
                let session = GameSession(words: [Self.entry("a", "水", "みず")], config: config)
                #expect(GameSummary(from: session).persistsSRS
                        == RunCompletion(mode: mode, recordsSRS: records).persistsSRS,
                        "\(mode)/\(records): the tile and the merge disagree")
            }
        }
    }

    /// The three that shipped saying "To review" over words nothing would review.
    @Test("sentence, dictation and the weak-words cram all schedule nothing")
    func theThreeNonPersistingRuns() {
        #expect(RunCompletion(mode: .sentence, recordsSRS: true).persistsSRS == false)
        #expect(RunCompletion(mode: .dictation, recordsSRS: true).persistsSRS == false)
        #expect(RunCompletion(mode: .journey, recordsSRS: false).persistsSRS == false)
        // …and the ordinary journey run, which does, or the label would never say "To review".
        #expect(RunCompletion(mode: .journey, recordsSRS: true).persistsSRS)
    }
}
