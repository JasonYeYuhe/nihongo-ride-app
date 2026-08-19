import Testing
import Foundation
import VocabKit
import GameCore
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
        return (AppModel(vocab: vocab), dir)
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
    static func realUserFileStamps() -> [String: Date] {
        var stamps: [String: Date] = [:]
        var roots: [URL] = []
        if let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first {
            roots.append(support.appendingPathComponent("NihongoRide", isDirectory: true))
        }
        if let group = AppGroup.containerURL() { roots.append(group) }
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
        // The probe has to be able to SEE those files, or it proves nothing by finding nothing.
        #expect(!before.isEmpty,
                "no real user files were visible — this check cannot detect a leak it cannot see")
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
