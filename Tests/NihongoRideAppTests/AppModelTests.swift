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
        let suite = "NihongoRideTests-\(UUID().uuidString)"
        AppModel.settingsDefaults = UserDefaults(suiteName: suite)
        AppModel.settingsSuiteOverride = suite
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
        let suite = "NihongoRideTests-\(UUID().uuidString)"
        AppModel.settingsDefaults = UserDefaults(suiteName: suite)
        AppModel.settingsSuiteOverride = suite
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

    // MARK: The pause reaches the session's clock (v1.31)

    /// **Proving a clock can be paused is not proving anything pauses it.**
    ///
    /// `PromptTimingTests` proves `ConjugationSession`/`GameSession` exclude a paused stretch
    /// when told to. That would stay green with `pauseRunClock()` never calling them — which is
    /// precisely how the ride's word clock came to run through pauses for fifteen releases while
    /// the run clock stopped: v1.15 wired one of the two signals' destinations and nothing
    /// compared them. The same shape defeated `RideMoment.openedANewOffer`'s first fix, where
    /// mutating the caller to pass a hard-coded `false` left the whole suite green.
    ///
    /// So this asserts the wiring from the app's side, on the model the views actually call.
    @Test("pauseRunClock stops the word clock too, and resumeRunClock starts it")
    func pauseReachesTheRideSession() throws {
        let model = Self.makeModel(vocab: VocabStore(entries: Self.verbEntries(10)))
        model.startGame()
        let session = try #require(model.session, "no ride to pause — the arrangement failed")
        #expect(!session.isTypingPaused, "a fresh ride must not start paused")
        model.pauseRunClock()
        #expect(session.isTypingPaused, Comment(rawValue: "the pause overlay, the sheet and "
                + "backgrounding all go through pauseRunClock; if it does not reach the session "
                + "the word clock runs through all three"))
        model.resumeRunClock()
        #expect(!session.isTypingPaused)
    }

    @Test("…and the conjugation drill's prompt clock, which had no pause signal at all")
    func pauseReachesTheConjugationSession() throws {
        let model = Self.makeModel(vocab: VocabStore(entries: Self.verbEntries(10)))
        model.startConjugation()
        let session = try #require(model.conjugationSession,
                                   "no drill to pause — the arrangement failed")
        #expect(!session.isTypingPaused)
        model.pauseRunClock()
        #expect(session.isTypingPaused, Comment(rawValue: "ConjugationGameView called only "
                + "resetStruggle before v1.31, because there was no prompt clock to stop"))
        model.resumeRunClock()
        #expect(!session.isTypingPaused)
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

    /// Ten real verbs. A synthetic 書0/か0 will not conjugate, so `makeReview` builds nothing
    /// and `startConjugationReview` bails at its own guard — which is how the first version of
    /// these tests came to assert against a nil session.
    static let realVerbs: [(String, String, String)] = [
        ("書く", "かく", "godan_k"), ("読む", "よむ", "godan_m"), ("話す", "はなす", "godan_s"),
        ("待つ", "まつ", "godan_t"), ("遊ぶ", "あそぶ", "godan_b"), ("泳ぐ", "およぐ", "godan_g"),
        ("買う", "かう", "godan_u"), ("帰る", "かえる", "godan_r"), ("見る", "みる", "ichidan"),
        ("食べる", "たべる", "ichidan"),
    ]

    static func verbEntries(_ count: Int) -> [VocabEntry] {
        realVerbs.prefix(count).enumerated().map { index, verb in
            VocabEntry(id: "v\(index)", surface: verb.0, kana: verb.1,
                       partsOfSpeech: ["v"], jlpt: .n5,
                       meanings: ["en": ["verb"], "zh": ["\u{52A8}\u{8BCD}"]], vc: verb.2)
        }
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

    // MARK: v1.26 §D — the UI suite finishes a REAL run

    /// **The precondition for widening the XCUITest suite, asserted over every location.**
    ///
    /// Those tests launch the normal app and complete a real sentence run, which writes SRS,
    /// the journal, the odometer and the widget snapshot — and pushes all of it to CloudKit if
    /// the device is signed in. v1.24's App Group incident wrote zeros to a LOCAL container and
    /// was recoverable; this one can put a phantom ride in the owner's real CloudKit database,
    /// where nothing local can clean it up.
    ///
    /// The lesson v1.24 recorded was not "add another override" — it was that a sandbox
    /// assertion checking the door somebody remembered will be green while a different door is
    /// open. So this asserts the PROPERTY over the whole value: under a UI-test launch, no
    /// location resolves to something the user owns, and sync cannot start. A location added
    /// later fails this test by being nil, without anyone predicting which one it would be.
    @Test("a UI-test launch can reach nothing that belongs to the user")
    func uiTestLaunchIsIsolated() {
        let isolation = AppModel.launchIsolation(
            uiTest: true, layoutHarness: false, capturing: false,
            supportOverride: nil, widgetOverride: nil, settingsOverride: nil)
        #expect(isolation.touchesNothingOfTheUsers,
                "a UI-test launch may not resolve any real location: \(isolation)")
        // …and each one named, so a failure says WHICH door opened rather than just "false".
        #expect(isolation.supportBase != nil, "Application Support is not redirected")
        #expect(isolation.widgetContainer != nil, "the App Group container is not redirected")
        #expect(isolation.settingsSuite != nil, "UserDefaults is not redirected")
        #expect(isolation.syncAllowed == false, "CloudKit sync is not disabled")
        // The redirects must be throwaway, not merely non-nil.
        let temp = FileManager.default.temporaryDirectory.path
        #expect(isolation.supportBase?.path.hasPrefix(temp) == true)
        #expect(isolation.widgetContainer?.path.hasPrefix(temp) == true)
    }

    /// **The UI suite's own contract, enforced.**
    ///
    /// `IsolatedLaunch.swift` opens with "Every UI-test launch goes through here, and none of
    /// them may call `app.launch()` directly." That was a comment stating a contract nothing
    /// kept — this project's cheapest detector, pointed at the guard that stands between an
    /// XCUITest and the owner's real CloudKit database. All five call sites complied when it
    /// was written; the sixth is the one that matters.
    ///
    /// Checked from the unit suite because `swift test` cannot run XCUITests, so the target
    /// that owns the rule is the one target that cannot assert it.
    @Test("no UI test launches the app without the isolation")
    func everyUITestLaunchIsIsolated() throws {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("NihongoRideiOSUITests")
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasSuffix(".swift") }
        #expect(files.count >= 3, "only \(files.count) UI test files — the scan is looking in the wrong place")
        var offenders: [String] = []
        var launches = 0
        for file in files {
            let source = try String(contentsOf: dir.appendingPathComponent(file), encoding: .utf8)
            for (number, line) in source.components(separatedBy: "\n").enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//"), !trimmed.hasPrefix("///") else { continue }
                if trimmed.contains(".launchIsolated(") { launches += 1 }
                // `.launch()` on an XCUIApplication, but not `.launchIsolated()` and not the
                // `launchEnvironment` assignment inside the helper itself.
                if trimmed.contains(".launch()") {
                    offenders.append("\(file):\(number + 1)  \(trimmed)")
                }
            }
        }
        #expect(launches >= 5, Comment(rawValue:
            "only \(launches) isolated launches found — a scan that inspects nothing reports clean"))
        #expect(offenders.isEmpty, Comment(rawValue:
            "a UI test launches the app WITHOUT isolation, so it writes the owner's real stores "
            + "and can push a phantom ride to their CloudKit database:\n"
            + offenders.joined(separator: "\n")))
    }

    /// **The isolation is CONSUMED, not merely decided — asserted through the real doors.**
    ///
    /// The four tests around this one call `launchIsolation(...)` with literal arguments and
    /// check what it returns. That is necessary and it is not sufficient, and the pre-submission
    /// review proved it: it severed every consumer from `currentIsolation` — `supportFileURL`,
    /// `settingsStore`, the widget write and the sync guard all back to their pre-v1.26
    /// expressions — while leaving `launchIsolation()` correct, and **the whole suite stayed
    /// green**. In that state a real `NIHONGO_UITEST=1` launch writes the owner's Application
    /// Support, their App Group container and their UserDefaults, and starts CloudKit sync.
    ///
    /// So this one turns the flag ON and reads the doors. The widget container is covered by
    /// the same write detector `nothingOutsideTheSandboxIsWritten` uses — already calibrated by
    /// `writeDetectorIsCalibrated`, so a null result from it is not taken on trust.
    @Test("a UI-test launch actually lands in the throwaway container, door by door")
    func uiTestIsolationIsConsumed() throws {
        let savedSupport = AppModel.supportDirectoryOverride
        let savedWidget = AppModel.widgetContainerOverride
        let savedDefaults = AppModel.settingsDefaults
        let savedSuite = AppModel.settingsSuiteOverride
        defer {
            AppModel.isUITestOverride = nil
            AppModel.supportDirectoryOverride = savedSupport
            AppModel.widgetContainerOverride = savedWidget
            AppModel.settingsDefaults = savedDefaults
            AppModel.settingsSuiteOverride = savedSuite
        }
        // Every explicit override cleared, so the ONLY thing keeping this out of the user's data
        // is the UI-test branch itself. With the overrides left in place the old and new code
        // agree, and the test would pass under the severed consumers too.
        AppModel.supportDirectoryOverride = nil
        AppModel.widgetContainerOverride = nil
        AppModel.settingsDefaults = nil
        AppModel.settingsSuiteOverride = nil
        AppModel.isUITestOverride = true

        let throwaway = AppModel.uiTestDirectory.path
        #expect(AppModel.supportFileURL("review.json").path.hasPrefix(throwaway),
                "Application Support is not redirected: \(AppModel.supportFileURL("review.json").path)")
        #expect(AppModel.settingsStore != UserDefaults.standard,
                "settings still resolve to the user's own UserDefaults")

        // …and the doors that cannot be read directly, observed by their effects.
        let before = Self.realUserFileStamps()
        let model = AppModel(vocab: VocabStore(entries: [
            Self.entry("a", "水", "みず"), Self.entry("b", "火", "ひ")]))
        model.startGame()
        model.session?.skip()
        model.finishGame()
        model.refreshWidgetSnapshot()
        let after = Self.realUserFileStamps()
        let touched = after.filter { before[$0.key] != $0.value }.keys.sorted()
        #expect(touched.isEmpty, "a UI-test launch wrote the user's own data: \(touched)")
        #expect(model.syncStatus == .off, "a UI-test launch started CloudKit sync")
    }

    /// The negative control. Without it the assertion above is satisfied by a function that
    /// isolates EVERY launch, which would silently disable sync in the shipping app.
    @Test("an ordinary launch is not isolated, so the check above means something")
    func ordinaryLaunchIsNotIsolated() {
        let normal = AppModel.launchIsolation(
            uiTest: false, layoutHarness: false, capturing: false,
            supportOverride: nil, widgetOverride: nil, settingsOverride: nil)
        #expect(normal.touchesNothingOfTheUsers == false)
        #expect(normal.supportBase == nil, "a shipping launch must use real Application Support")
        #expect(normal.widgetContainer == nil, "a shipping launch must use the real App Group")
        #expect(normal.settingsSuite == nil, "a shipping launch must use UserDefaults.standard")
        #expect(normal.syncAllowed, "a shipping launch must be allowed to sync")
    }

    /// Screenshot capture must clear the same bar, and until the pre-submission review it did
    /// not: it redirected FILES and left the widget container and the settings suite nil, so
    /// `touchesNothingOfTheUsers` could never have flagged it. Capture was safe only because
    /// three separate `!Screenshotter.isCapturing` guards sat at the call sites — which is the
    /// "check the door somebody remembered" shape, inside the value written to replace it.
    @Test("screenshot capture reaches nothing that belongs to the user either")
    func captureIsIsolated() {
        let capture = AppModel.launchIsolation(
            uiTest: false, layoutHarness: false, capturing: true,
            supportOverride: nil, widgetOverride: nil, settingsOverride: nil)
        #expect(capture.touchesNothingOfTheUsers,
                "a capture launch may not resolve any real location: \(capture)")
        #expect(capture.supportBase?.lastPathComponent == "NihongoRideCapture")
        #expect(capture.widgetContainer != nil, "capture could still write the real widget")
        #expect(capture.settingsSuite != nil, "capture could still write the real settings")
        #expect(capture.syncAllowed == false, "capture could still push to the real CloudKit")
    }

    /// The layout harness keeps the behaviour it already had — sync off, files real — so this
    /// refactor cannot have quietly changed it. `jumpToDebugScreen` is simulator-gated and its
    /// container is disposable; what was never disposable is the CloudKit database.
    @Test("the layout harness still cannot sync")
    func layoutHarnessCannotSync() {
        let harness = AppModel.launchIsolation(
            uiTest: false, layoutHarness: true, capturing: false,
            supportOverride: nil, widgetOverride: nil, settingsOverride: nil)
        #expect(harness.syncAllowed == false)
        // Screenshot capture keeps its fixed temp directory.
        let capture = AppModel.launchIsolation(
            uiTest: false, layoutHarness: false, capturing: true,
            supportOverride: nil, widgetOverride: nil, settingsOverride: nil)
        #expect(capture.supportBase?.lastPathComponent == "NihongoRideCapture")
    }

    /// An explicit override always wins, because the unit-test target sets one per model and
    /// swift-testing runs these in parallel — a shared directory would let them read each
    /// other's stores.
    @Test("an explicit override outranks every harness mode")
    func overrideWins() {
        let mine = URL(fileURLWithPath: "/tmp/mine")
        let isolation = AppModel.launchIsolation(
            uiTest: true, layoutHarness: true, capturing: true,
            supportOverride: mine, widgetOverride: mine, settingsOverride: "mine")
        #expect(isolation.supportBase == mine)
        #expect(isolation.widgetContainer == mine)
        #expect(isolation.settingsSuite == "mine")
        #expect(isolation.syncAllowed == false)
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
        let verbs = Self.verbEntries(10)
        var cards: [String: ConjugationSRSCard] = [:]
        for verb in verbs {
            // VALID ConjugationForm raw values. "masu" is not one — the drill's builder drops a
            // form it cannot parse while `conjugationDueCount` counts the card regardless, so
            // the first fixture produced thirty due cards and an empty run.
            for form in ["polite", "past", "te"] {
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
    func conjugationReviewCountMatchesTheRun() throws {
        let verbs = Self.verbEntries(10)
        var cards: [String: ConjugationSRSCard] = [:]
        for verb in verbs {
            // VALID ConjugationForm raw values. "masu" is not one — the drill's builder drops a
            // form it cannot parse while `conjugationDueCount` counts the card regardless, so
            // the first fixture produced thirty due cards and an empty run.
            for form in ["polite", "past", "te"] {
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

        // …and START the run, which the first version of this test did not. Its weak-words twin
        // does, and the review pointed out that comparing two model properties cannot see a
        // divergence between the label and the queue — only between two readings of the store.
        model.startConjugationReview()
        let ridden = try #require(model.conjugationSession).promptCount
        #expect(ridden >= shown, Comment(rawValue:
            "the button promises \(shown) due forms and the drill holds \(ridden) prompts"))
    }

    /// Below the cap the conjugation button behaves DIFFERENTLY from the weak-words one, and
    /// the difference is legitimate rather than a defect — recorded here so it is a decision
    /// with a reason and not a silence.
    ///
    /// With five forms due the label says five and the drill still holds twelve prompts:
    /// `startConjugationReview` sets `promptCount = conjugationRunSize` unconditionally and
    /// `makeReview` fills the remainder with fresh weak-form prompts. That is the documented
    /// design — "due forms first, weak-form fill" — and the label's promise is about the DUE
    /// ones, all five of which are ridden. It is not B1's defect, where fifteen were promised
    /// and twelve ridden; nothing here is promised and withheld.
    @Test("below the cap the label names the due forms, and the drill may hold more than that")
    func conjugationBelowTheCapNamesTheDue() throws {
        let verbs = Self.verbEntries(3)
        var cards: [String: ConjugationSRSCard] = [:]
        for verb in verbs {
            let card = Self.dueConjugationCard(verb.id, "polite")
            cards[card.id] = card
        }
        let model = Self.seeded(vocab: VocabStore(entries: verbs),
                                conjugation: ConjugationReviewStore(cards: cards))
        #expect(model.conjugationDueCount == 3)
        let shown = model.conjugationReviewQueue.count
        #expect(shown == 3, "three due and a cap of twelve — the label names three")
        #expect(model.conjugationReviewButtonText(zh: false) == "Review 3 due")
        model.startConjugationReview()
        let ridden = try #require(model.conjugationSession).promptCount
        #expect(ridden >= shown, "every due form must be in the drill")
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

/// The learner's own text, from the app's side (v1.31).
///
/// The kit's tests cover reading, splitting and persistence. What can only be observed here is
/// the part that makes this the *bounded* half of "bring your own Japanese": that a pasted
/// sentence reaches the typing engine and reaches **nothing else**.
@MainActor
@Suite("Practice over the learner's own text")
struct CustomTextRunTests {

    static func model() -> AppModel {
        AppModelTests.makeModel(vocab: VocabStore(entries: AppModelTests.verbEntries(10)))
    }

    /// Types the whole run through, the way the view's key handler does.
    static func rideItOut(_ model: AppModel) {
        var guardrail = 0
        while let session = model.session, !session.isFinished, guardrail < 5_000 {
            guard let romaji = session.currentRomaji, !romaji.isEmpty else { session.skip(); continue }
            for character in romaji { _ = session.input(character) }
            guardrail += romaji.count
        }
    }

    @Test("a pasted sentence reaches the typing engine")
    func aCustomTextRides() throws {
        let model = Self.model()
        model.selectedMode = .practice
        model.practiceSource = .custom
        _ = model.addCustomText(title: "mine", source: "毎日勉強する。今日はいい天気ですね。")
        model.startGame()
        let session = try #require(model.session, "the run did not start")
        #expect(session.wordCount == 2)
        #expect(session.currentKana == "まいにちべんきょうする")
        // The furigana line the practice screen draws comes from here, and it must cover the
        // learner's own sentence rather than the reading.
        let tokens = try #require(session.currentExampleTokens)
        #expect(tokens.map { $0[0] }.joined() == "毎日勉強する。")
    }

    /// **A known miss, pinned rather than hidden — and it is the case the whole design is for.**
    ///
    /// 日本語 comes back as にっぽんご, because the tokenizer splits it into 日本[nippon] +
    /// 語[go]. This is the exact compound-splitting this project measured in Sudachi, and the
    /// first draft of the test above expected にほんご and failed on it.
    ///
    /// It is asserted here so that a change in the system tokenizer is NOTICED rather than
    /// discovered by a learner — and immediately afterwards the correction is made and the run
    /// re-checked, because "the app can be wrong about your text" is only acceptable while
    /// "and you can fix it" is true in the same breath.
    @Test("a compound the tokenizer splits is wrong, and the learner can put it right")
    func aKnownMissIsFixable() throws {
        let model = Self.model()
        model.selectedMode = .practice
        model.practiceSource = .custom
        let id = try #require(model.addCustomText(title: "mine", source: "日本語を勉強する。"))
        model.startGame()
        #expect(model.session?.currentKana == "にっぽんごをべんきょうする",
                "if this is now にほんご the system tokenizer changed — good news, worth knowing")

        let text = try #require(model.customTexts.text(id: id))
        let sentence = try #require(text.sentences.first)
        let index = try #require(sentence.tokens.firstIndex { $0.surface == "日本" })
        let ok = model.setCustomReading("にほん", textID: id, sentenceID: sentence.id,
                                        tokenIndex: index)
        #expect(ok)
        model.startGame()
        #expect(model.session?.currentKana == "にほんごをべんきょうする",
                "the learner's correction is the whole answer to the tokenizer's 3.1%")
    }

    /// **The red line, observed rather than argued.** `SRSCard(id:)` is keyed on corpus entry
    /// ids and `SyncMerge` merges them across devices through CloudKit; a pasted word must
    /// never acquire a card identity. The control is what makes this evidence: an ordinary
    /// journey run through the same harness MUST change the review store, or this test would
    /// pass on a harness that never finishes a run at all.
    @Test("…and reaches the review scheduler not at all — with a control that must fire")
    func aCustomTextWritesNoSRS() throws {
        let custom = Self.model()
        custom.selectedMode = .practice
        custom.practiceSource = .custom
        _ = custom.addCustomText(title: "mine", source: "日本語を勉強する。")
        let before = custom.reviewStore.count
        custom.startGame()
        Self.rideItOut(custom)
        custom.finishGame()
        #expect(custom.reviewStore.count == before, "a pasted sentence created review cards")
        // …and the identity itself, named, because a count can stay equal while an id is
        // swapped. Every sentence in the run is checked by id.
        let text = try #require(custom.customTextForRun)
        for sentence in text.typeableSentences {
            #expect(custom.reviewStore.card(for: "customtext-\(sentence.id)") == nil,
                    Comment(rawValue: "a pasted sentence acquired a card identity, which "
                            + "SyncMerge would then carry to every device the learner owns"))
        }

        let ride = Self.model()
        ride.selectedMode = .journey
        let rideBefore = ride.reviewStore.count
        ride.startGame()
        Self.rideItOut(ride)
        ride.finishGame()
        #expect(ride.reviewStore.count > rideBefore, Comment(rawValue:
            "THE CONTROL DID NOT FIRE: an ordinary ride wrote no SRS either (\(rideBefore) → "
            + "\(ride.reviewStore.count)), so the assertion above is about the harness"))
    }

    /// The thing the first draft broke. Setting `recordsSRS = false` on the custom builder
    /// looked like belt-and-braces and would have made `RunCompletion` read the run as a
    /// weak-words cram, which switches off ride logging too — five hundred characters typed
    /// and the road does not move, with nothing on screen saying why.
    @Test("a custom-text run still logs a ride, like every other practice run")
    func aCustomTextLogsARide() {
        let model = Self.model()
        model.selectedMode = .practice
        model.practiceSource = .custom
        _ = model.addCustomText(title: "mine", source: "日本語を勉強する。")
        let before = model.journal.records.count
        model.startGame()
        Self.rideItOut(model)
        model.finishGame()
        #expect(model.journal.records.count == before + 1, "the road must move")
        #expect(model.journal.records.last?.level == "custom",
                "and the Ride Log must not call it a passage length it never had")
    }

    /// The menu's number and the queue it describes, which is this project's most-shipped
    /// defect. An untypeable sentence is KEPT (it is the learner's text) and WITHHELD from the
    /// queue, so the stored count and the run count genuinely differ.
    @Test("the menu's sentence count is the queue's length, not the stored one")
    func theLabelCountsWhatTheRunRides() throws {
        let model = Self.model()
        model.selectedMode = .practice
        model.practiceSource = .custom
        _ = model.addCustomText(title: "mixed", source: "日本語を勉強する。ABCと言った。今日はいい天気。")
        let text = try #require(model.customTextForRun)
        #expect(text.sentences.count == 3, "all three are the learner's text")
        #expect(model.customTextRunCount == 2, "…and only two can be typed")
        model.startGame()
        let session = try #require(model.session)
        #expect(session.wordCount == model.customTextRunCount,
                "the label and the run must read the same property, not merely agree today")
    }

    /// Resolve-then-guard, the rule every start path in this file follows: a run that resolves
    /// to nothing stays on the menu, where the explanation is, rather than entering an
    /// already-finished screen.
    @Test("a text with nothing typeable in it does not enter the game screen")
    func anUntypeableTextStaysOnTheMenu() {
        let model = Self.model()
        model.selectedMode = .practice
        model.practiceSource = .custom
        _ = model.addCustomText(title: "latin", source: "ABC DEF.")
        model.startGame()
        #expect(model.session == nil, "a run with no typeable sentence must not start")
        #expect(model.screen != .playing)
        #expect(model.emptyPoolNotice, "…and the menu must say why")
    }

    @Test("no text at all is the same guarded outcome, not a crash")
    func noTextAtAll() {
        let model = Self.model()
        model.selectedMode = .practice
        model.practiceSource = .custom
        #expect(model.customTextForRun == nil)
        #expect(model.customTextRunCount == 0)
        model.startGame()
        #expect(model.session == nil)
    }

    @Test("a correction the learner makes is what the next run types")
    func correctionsReachTheRun() throws {
        let model = Self.model()
        model.selectedMode = .practice
        model.practiceSource = .custom
        let id = try #require(model.addCustomText(title: "mine", source: "私は行く。"))
        let text = try #require(model.customTexts.text(id: id))
        let sentence = try #require(text.sentences.first)
        let index = try #require(sentence.tokens.firstIndex { $0.surface == "私" })
        #expect(sentence.kana == "わたくしはいく", "the tokenizer's own answer")
        let ok = model.setCustomReading("わたし", textID: id, sentenceID: sentence.id,
                                        tokenIndex: index)
        #expect(ok)
        model.startGame()
        #expect(model.session?.currentKana == "わたしはいく",
                "the correction must be what the engine asks for, or editing is decoration")
    }
}

/// The menu's level picker, which is a claim about what the run will draw from.
///
/// This suite exists because the picker came BACK under "My text" when `practicePassages`
/// narrowed its meaning, and it was found by launching the app rather than by any test. A
/// control that decides nothing is the same defect class as a label that counts something the
/// run does not ride — v1.15 §L is the same note about the same screen.
@MainActor
@Suite("The JLPT picker is shown exactly when it decides something")
struct JLPTPickerVisibilityTests {

    static func model() -> AppModel {
        AppModelTests.makeModel(vocab: VocabStore(entries: AppModelTests.verbEntries(10)))
    }

    @Test("hidden for both sentence-shaped practice sources, shown for the word stream")
    func practiceSources() {
        let model = Self.model()
        model.selectedMode = .practice
        model.practiceSource = .passages
        #expect(!model.showsJLPTPicker, "a passage run draws from a length, not a level")
        model.practiceSource = .custom
        #expect(!model.showsJLPTPicker, "a custom run draws from the learner's own sentences")
        // The control, and it is the half that makes the two above mean anything: if the picker
        // were hidden in every practice mode this suite would pass while the word stream lost a
        // control it genuinely needs.
        model.practiceSource = .words
        #expect(model.showsJLPTPicker, "the word stream really does draw from a level")
    }

    @Test("and every other mode keeps it")
    func otherModes() {
        let model = Self.model()
        for mode in [GameMode.journey, .timeAttack, .sentence, .dictation, .conjugation] {
            model.selectedMode = mode
            #expect(model.showsJLPTPicker, Comment(rawValue: "\(mode) lost its level picker"))
        }
    }
}

/// The ride screen's live speed readout.
///
/// The pill itself is one conditional over `stat(...)`, the same helper four other pills use;
/// what has logic is the number. This suite exists because the first version of `liveWPM` read
/// `Date()` internally and so could not be observed at all — the whole arithmetic on the ride
/// screen, unchecked, which is how a readout and the row it is supposed to match drift apart.
@MainActor
@Suite("The live speed readout is the number the Ride Log will record")
struct LiveWPMTests {

    static func startedModel() -> AppModel {
        let model = AppModelTests.makeModel(vocab: VocabStore(entries: AppModelTests.verbEntries(10)))
        model.selectedMode = .journey
        model.startGame()
        return model
    }

    @Test("nothing to report before the ride has two seconds and a keystroke")
    func belowTheFloor() throws {
        let model = Self.startedModel()
        let session = try #require(model.session)
        // RunClock's own convention: under two seconds, or no correct keystrokes, has no
        // meaningful speed. The HUD renders 0 as a dash rather than as "0 wpm", because a rider
        // three seconds into a ride is not going at zero.
        #expect(model.liveWPM(at: Date()) == 0, "no keystrokes yet")
        for character in (session.currentRomaji ?? "").prefix(5) { _ = session.input(character) }
        #expect(model.liveWPM(at: Date()) == 0, "under two seconds of riding")
        // The control: the same keystrokes, further along the clock, must produce a number.
        #expect(model.liveWPM(at: Date().addingTimeInterval(60)) > 0, Comment(rawValue:
                "…and past the floor it must report something, or this suite is asserting a "
                + "constant zero"))
    }

    @Test("it is RunClock's convention, not a second opinion about speed")
    func matchesTheJournalConvention() throws {
        let model = Self.startedModel()
        let session = try #require(model.session)
        for character in (session.currentRomaji ?? "") { _ = session.input(character) }
        let at = Date().addingTimeInterval(60)
        let keystrokes = session.correctKeystrokes
        // The definition the Ride Log row uses, computed here from the same clock. If the two
        // ever diverge, the rider watches one number during the ride and is shown another
        // afterwards — the count-and-run defect wearing a speedometer.
        let expected = RunClock(startedAt: Date()).wpm(correctKeystrokes: keystrokes, at: at)
        #expect(abs(model.liveWPM(at: at) - expected) < 0.5, Comment(rawValue:
            "live \(model.liveWPM(at: at)) vs journal convention \(expected)"))
    }

    @Test("a pause freezes it rather than letting it decay")
    func pauseFreezesIt() throws {
        let model = Self.startedModel()
        let session = try #require(model.session)
        for character in (session.currentRomaji ?? "") { _ = session.input(character) }
        let atPause = Date().addingTimeInterval(10)
        let running = model.liveWPM(at: atPause)
        #expect(running > 0)
        model.pauseRunClock(at: atPause)
        // Ten minutes of pause: ridden time has not moved, so neither has the readout.
        let after = model.liveWPM(at: atPause.addingTimeInterval(600))
        #expect(abs(after - running) < 0.5, Comment(rawValue:
            "the readout decayed from \(running) to \(after) while the rider was paused"))
        // The control, and it is what makes the freeze mean something: once resumed, more wall
        // clock DOES lower the speed again.
        model.resumeRunClock(at: atPause.addingTimeInterval(600))
        let later = model.liveWPM(at: atPause.addingTimeInterval(1200))
        #expect(later < running, Comment(rawValue:
            "after resuming, the readout must move again — got \(later) against \(running)"))
    }
}

/// The Ride Log's level capsule.
///
/// Written after the row broke. Every ride the app logs carries a `level` string, the capsule
/// beside the date renders it, and the row is laid out for a label of one or two characters —
/// so a longer one squeezes the score, WPM and accuracy columns until they wrap character by
/// character. `levelLabel`'s `default:` passed anything through, and v1.31's `"custom"` was the
/// first string long enough to matter.
@MainActor
@Suite("A ride's level capsule stays short enough for the row")
struct RideLevelLabelTests {

    /// Every level string `AppModel.logRun` can actually write, enumerated from that method's
    /// own branches rather than guessed: the passage lengths, the mixed pool, a JLPT level, and
    /// the custom-text runs added in v1.31.
    static let everyLevelTheAppWrites: [String] =
        ["easy", "med", "hard", "all", "custom"] + JLPTLevel.allCases.map(\.label)

    @Test("no label the app can produce is longer than the row can hold")
    func everyLabelIsShort() {
        for zh in [false, true] {
            for level in Self.everyLevelTheAppWrites {
                let label = JournalView.levelLabel(level, zh: zh)
                #expect(!label.isEmpty, Comment(rawValue: "\(level) rendered nothing"))
                #expect(label.count <= 4, Comment(rawValue:
                    "\(level) → \(label.debugDescription) is \(label.count) characters; the row "
                    + "is laid out for one or two and squeezes everything beside it"))
            }
        }
    }

    @Test("…and an unforeseen level is capped rather than passed through")
    func theDefaultIsBounded() {
        // The mutation this kills: restoring `default: level`. That is what shipped the broken
        // row, and it would pass the test above for as long as nobody adds a long level string
        // — which is precisely how it survived until v1.31.
        let long = "a-level-nobody-has-thought-of-yet"
        #expect(JournalView.levelLabel(long, zh: false).count <= 4)
        // The control: the labels that are meant to pass through still do.
        #expect(JournalView.levelLabel("N5", zh: false) == "N5")
        #expect(JournalView.levelLabel("custom", zh: false) == "MINE")
        #expect(JournalView.levelLabel("custom", zh: true) == "自选")
    }
}
