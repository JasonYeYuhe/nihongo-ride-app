import Testing
import Foundation
import JournalKit
import StoreReviewKit
import VocabKit
@testable import NihongoRideApp

/// The join between `finishGame` and the review prompt.
///
/// `StoreReviewKitTests` holds the policy and holds it thoroughly. **That is not a test of the
/// app**, and this project has paid for the difference: v1.26 fixed two defects at the model
/// seam, proved them by mutation, then restored the original labels in `MenuView` and watched
/// all 527 tests stay green. The tests held the predicate; nothing bound the screen to it.
/// These bind it.
@MainActor
@Suite("The review prompt is wired to a real ride")
struct ReviewPromptWiringTests {

    static func vocab() -> VocabStore {
        VocabStore(entries: [AppModelTests.entry("a", "水", "みず"),
                             AppModelTests.entry("b", "火", "ひ"),
                             AppModelTests.entry("c", "山", "やま")])
    }

    /// Types every prompt correctly until the ride ends.
    static func rideCleanly(_ model: AppModel) {
        model.startGame()
        while let romaji = model.session?.currentRomaji, model.session?.isFinished == false {
            for ch in romaji { _ = model.session?.input(ch) }
        }
        model.finishGame()
    }

    /// A model sandboxed like the others, but with a journal seeded before `init` reads it —
    /// the only way to arrange a rider who came back on a second day without waiting a day.
    static func seededJournal(_ records: [RideRecord]) -> AppModel {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReviewPromptTests-\(UUID().uuidString)", isDirectory: true)
        AppModel.supportDirectoryOverride = dir
        AppModel.widgetContainerOverride = dir.appendingPathComponent("group", isDirectory: true)
        let suite = "ReviewPromptWiring-\(UUID().uuidString)"
        AppModel.settingsDefaults = UserDefaults(suiteName: suite)
        AppModel.settingsSuiteOverride = suite
        var journal = RideJournal()
        for r in records { journal.append(r) }
        // Written with the journal's OWN writer, not a hand-rolled JSONEncoder: `save`/`load`
        // use `.iso8601` dates, and a default encoder emits numeric timestamps that LossyLoad
        // then drops row by row — a seed that silently loads nothing. The first draft of this
        // helper did exactly that, and the assertion below is what caught it.
        try? journal.save(to: AppModel.supportFileURL("history.json"))
        let model = AppModel(vocab: vocab())
        // The seed is a claim; a helper that silently seeded nothing would make every assertion
        // below pass for the wrong reason.
        #expect(model.journal.count == records.count, "the journal seed did not load")
        return model
    }

    static func record(daysAgo: Int, accuracy: Double = 1.0,
                       distanceMeters: Double = 500) -> RideRecord {
        RideRecord(date: Date().addingTimeInterval(Double(-daysAgo) * 24 * 60 * 60),
                   mode: "journey", level: "n5", score: 100, wpm: 30,
                   accuracy: accuracy, wordsCompleted: 3, lapsed: 0,
                   distanceMeters: distanceMeters, duration: 60)
    }

    // MARK: - The moment

    /// The numbers that gate the prompt must be the numbers that were logged. If `finishGame`
    /// built the moment from `session` instead of from the appended `RideRecord`, the accuracy
    /// deciding the prompt and the accuracy in the Ride Log could differ — the shape of every
    /// count-vs-run defect this project has found.
    @Test("a finished ride becomes a moment whose numbers are the logged ride's own")
    func momentMatchesTheLoggedRide() throws {
        let model = AppModelTests.makeModel(vocab: Self.vocab())
        Self.rideCleanly(model)
        let moment = try #require(model.pendingReviewMoment)
        let logged = try #require(model.journal.recent(1).first)
        #expect(moment.wasLogged)
        #expect(moment.accuracy == logged.accuracy)
        #expect(moment.lifetimeRides == model.lifetimeRuns)
        #expect(moment.riddenDays == model.journal.riddenDays().count)
    }

    @Test("a run with nothing typed logs no ride and is no moment")
    func abandonedRunIsNotAMoment() throws {
        let model = AppModelTests.makeModel(vocab: Self.vocab())
        model.startGame()
        model.session?.skip()
        model.finishGame()
        let moment = try #require(model.pendingReviewMoment)
        #expect(moment.wasLogged == false, "an abandoned run must not be offered as a moment")

        var asked = 0
        model.considerReviewPrompt { asked += 1 }
        #expect(asked == 0)
        #expect(model.reviewPromptLedger.count(of: .notALoggedRide) == 1)
    }

    // MARK: - The consume

    /// "Ride again" bounces back through the results screen, and `onAppear` fires again. If the
    /// moment were not consumed, one ride would spend two of Apple's three annual prompts.
    @Test("a results screen appearing twice asks once")
    func momentIsConsumed() {
        let model = Self.seededJournal([Self.record(daysAgo: 3), Self.record(daysAgo: 1)])
        Self.rideCleanly(model)
        var asked = 0
        model.considerReviewPrompt { asked += 1 }
        model.considerReviewPrompt { asked += 1 }
        model.considerReviewPrompt { asked += 1 }
        #expect(asked == 1, "one ride must produce at most one request")
        #expect(model.reviewPromptLedger.requestsMade == 1)
        #expect(model.reviewPromptLedger.momentsEvaluated == 1,
                "a consumed moment must not be counted again either")
    }

    /// The positive control. Without it every assertion here is satisfied by a wiring that
    /// never asks anybody, which is exactly the failure this feature cannot detect in the field.
    @Test("a returning rider who rode well IS asked")
    func aReturningRiderIsAsked() {
        let model = Self.seededJournal([Self.record(daysAgo: 4), Self.record(daysAgo: 2)])
        Self.rideCleanly(model)
        var asked = 0
        model.considerReviewPrompt { asked += 1 }
        #expect(asked == 1)
        #expect(model.reviewPromptLedger.count(of: .asked) == 1)
    }

    @Test("a rider on their very first day is not asked")
    func aFirstDayRiderIsNotAsked() {
        let model = AppModelTests.makeModel(vocab: Self.vocab())
        Self.rideCleanly(model)
        var asked = 0
        model.considerReviewPrompt { asked += 1 }
        #expect(asked == 0)
        #expect(model.reviewPromptLedger.count(of: .asked) == 0)
    }

    // MARK: - The ledger is the instrument

    @Test("the ledger survives a relaunch, so the cooldown cannot be reset by quitting")
    func ledgerSurvivesRelaunch() {
        let model = Self.seededJournal([Self.record(daysAgo: 4), Self.record(daysAgo: 2)])
        Self.rideCleanly(model)
        model.considerReviewPrompt {}
        #expect(model.reviewPromptLedger.requestsMade == 1)

        // Same overrides, same defaults suite — a second launch of the same install.
        let relaunched = AppModel(vocab: Self.vocab())
        #expect(relaunched.reviewPromptLedger.requestsMade == 1,
                "a relaunch forgot that it had already asked")
    }

    /// **The gap this suite would otherwise have.** Everything above drives `AppModel`
    /// directly, so deleting the one line in `ResultsView` that calls `considerReviewPrompt`
    /// leaves every test green and ships a feature that never fires — which is precisely what
    /// v1.26 §B measured when it restored the original `MenuView` labels against 527 green
    /// tests. `requestReview` is a SwiftUI environment action, so there is no headless way to
    /// observe the call; this reads the shipped source instead.
    ///
    /// **It is a scan, not a behavioural test, and the difference matters**: it proves the call
    /// site exists, not that it runs. What makes it worth having anyway is that the failure it
    /// guards is deletion, and deletion is exactly what a scan can see.
    @Test("the results screen is the one place that consumes the moment")
    func resultsViewCallsIt() throws {
        let appDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/NihongoRideApp")
        let files = try FileManager.default.contentsOfDirectory(at: appDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        // A scan that reads nothing cannot report clean.
        #expect(files.count >= 20, "the scanner found only \(files.count) sources; it is broken, not clean")

        var callers: [String] = []
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let code = source.split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            if code.contains("considerReviewPrompt") && file.lastPathComponent != "AppModel.swift" {
                callers.append(file.lastPathComponent)
            }
        }
        #expect(callers == ["ResultsView.swift"],
                "the review prompt must be consumed by the ride results screen and nowhere else, found: \(callers)")

        let results = try String(contentsOf: appDir.appendingPathComponent("ResultsView.swift"), encoding: .utf8)
        #expect(results.contains("requestReview()"),
                "ResultsView must pass the environment action in, or the prompt can never appear")
    }

    /// The pre-submission review's BLOCKER, tested rather than argued.
    ///
    /// Its claim: a UI-test launch loads the owner's real ledger, records a `.suppressed`
    /// outcome into it, and saves it back. That failure does not occur — `settingsStore` routes
    /// a UI-test launch into a throwaway suite, which `uiTestIsolationIsConsumed` already
    /// asserts. But "safe because a second mechanism happens to catch it" is not a property
    /// anybody checked, so this checks it: with every explicit override cleared, the only thing
    /// standing between this model and `UserDefaults.standard` is the isolation itself.
    @Test("a UI-test launch neither reads nor writes the owner's prompt ledger")
    func uiTestNeverTouchesTheRealLedger() {
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
        AppModel.supportDirectoryOverride = nil
        AppModel.widgetContainerOverride = nil
        AppModel.settingsDefaults = nil
        AppModel.settingsSuiteOverride = nil
        AppModel.isUITestOverride = true

        let key = ReviewPromptLedger.defaultsKey
        let before = UserDefaults.standard.data(forKey: key)
        let model = AppModel(vocab: Self.vocab())
        #expect(model.reviewPromptLedger == ReviewPromptLedger(),
                "an isolated launch must start from an empty ledger, not the owner's")
        Self.rideCleanly(model)
        var asked = 0
        model.considerReviewPrompt { asked += 1 }
        #expect(asked == 0, "a UI test must never spend one of Apple's three annual prompts")
        #expect(UserDefaults.standard.data(forKey: key) == before,
                "a UI-test launch wrote the owner's real review-prompt ledger")
    }

    /// A run that cannot reach the user's data must not spend one of the three real prompts
    /// Apple allows per year. The isolation value is the single source of truth for both.
    @Test("an isolated launch is suppressed, and an ordinary one is not")
    func isolationDecidesSuppression() {
        for (label, iso) in [
            ("ui test", AppModel.launchIsolation(uiTest: true, layoutHarness: false, capturing: false,
                                                 supportOverride: nil, widgetOverride: nil, settingsOverride: nil)),
            ("capture", AppModel.launchIsolation(uiTest: false, layoutHarness: false, capturing: true,
                                                 supportOverride: nil, widgetOverride: nil, settingsOverride: nil)),
        ] {
            #expect(iso.touchesNothingOfTheUsers, "\(label) must be suppressed")
        }
        let shipping = AppModel.launchIsolation(uiTest: false, layoutHarness: false, capturing: false,
                                                supportOverride: nil, widgetOverride: nil, settingsOverride: nil)
        #expect(shipping.touchesNothingOfTheUsers == false,
                "a shipping launch must be able to ask, or this feature does nothing")
    }

    // MARK: - The offer collision (v1.30)

    /// Three seeded rides across three days, totalling `total` metres — enough to clear
    /// `minimumLoggedRides` (3) and `minimumRiddenDays` (2), so that a moment built on top of this
    /// is earned on every clause EXCEPT the one under test. The first draft seeded one ride, and
    /// `asked == 0` passed because `decide` returned `.tooFewRides` before it ever reached the
    /// offer guard — the assertion holding for a reason that had nothing to do with the feature.
    static func seededAtDistance(_ total: Double) -> AppModel {
        let each = total / 3
        return seededJournal([record(daysAgo: 3, distanceMeters: each),
                              record(daysAgo: 2, distanceMeters: each),
                              record(daysAgo: 1, distanceMeters: each)])
    }

    /// **The wiring the policy test cannot reach.** `ReviewPromptOfferCollisionTests` proves
    /// `decide` yields when `openedANewOffer` is true; it cannot prove anything ever sets it.
    /// Mutating `finishGame` to pass a hard-coded `false` left that whole suite green — the guard
    /// present and nothing reaching it, which is this project's v1.26 lesson exactly.
    @Test("the ride that crosses into Kyōto is the one that yields, and only that ride")
    func crossingIntoKyotoOpensAnOfferAndYieldsThePrompt() throws {
        // Just short of the 25 km arrival. The test vocab is three short words
        // (みず・ひ・やま = 5 kana = 50 m), so the seed must sit within one ride of the threshold —
        // hence 24,990 and not a round number. The assertions either side of the ride keep that
        // honest: if the arithmetic drifts, this fails as "did not cross" rather than passing.
        let crossing = Self.seededAtDistance(24_990)
        #expect(crossing.hasArrivedAtKyoto == false, "the seed should start short of Kyōto")
        Self.rideCleanly(crossing)
        #expect(crossing.hasArrivedAtKyoto, "the ride should have crossed into Kyōto")
        #expect(try #require(crossing.pendingReviewMoment).openedANewOffer,
                "the ride that opened the menu entrance did not yield the rating prompt")

        var askedOnCrossing = 0
        crossing.considerReviewPrompt { askedOnCrossing += 1 }
        #expect(askedOnCrossing == 0, "the rating prompt fired on the same ride that opened the offer")
        #expect(crossing.reviewPromptLedger.count(of: .rideOpenedANewOffer) == 1,
                "the prompt was withheld, but not for this reason — check which clause fired")

        // **The pair that makes the above mean something.** Same seed shape, same ride, same
        // policy — the ONLY difference is that this rider was already past Kyōto, so nothing new
        // opened. If this one is not asked, the test above proved nothing about the offer.
        let past = Self.seededAtDistance(30_000)
        #expect(past.hasArrivedAtKyoto)
        Self.rideCleanly(past)
        #expect(try #require(past.pendingReviewMoment).openedANewOffer == false,
                "a rider already past Kyōto opened no new entrance, but the ride claimed it did")
        var askedOnPast = 0
        past.considerReviewPrompt { askedOnPast += 1 }
        #expect(askedOnPast == 1,
                "the control was not asked either — the crossing test is not isolating the offer")

        // And a rider far short of it: without this, a `finishGame` that set the flag on every
        // ride would still pass everything above.
        let short = Self.seededAtDistance(3_000)
        Self.rideCleanly(short)
        #expect(try #require(short.pendingReviewMoment).openedANewOffer == false)
        #expect(short.hasArrivedAtKyoto == false)
    }
}
