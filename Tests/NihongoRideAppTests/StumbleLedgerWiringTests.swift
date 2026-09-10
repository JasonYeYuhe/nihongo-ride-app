import Testing
import Foundation
import VocabKit
import RomajiKana
import DiagnosticsKit
@testable import NihongoRideApp

/// The ledger's wiring, which is the half a unit test on the type cannot see (v1.32 §F2).
///
/// `StumbleLedgerTests` proves the aggregate is right about the data it is handed.
/// This proves the app hands it the right data, at the right moment, exactly once — and
/// `STATE-2026-08-18.md` records why the distinction is not pedantic: *"Proving a policy yields is
/// not proving anything sets the flag."* The v1.27 rating-prompt fix passed its own unit tests
/// while `finishGame` passed a hard-coded `false`, and the whole suite stayed green.
@MainActor
@Suite("The stumble ledger is fed once per ride, and only by real ones")
struct StumbleLedgerWiringTests {

    static func vocab() -> VocabStore {
        VocabStore(entries: [AppModelTests.entry("a", "赤", "あか")])
    }

    static func refusal(_ order: Int = 0) -> MistakeEvent {
        MistakeEvent(targetKana: "こんにちは", entryID: nil, acceptedRomaji: "",
                     rejected: "w", expectedNext: ["h"], kanaIndex: 4, order: order)
    }

    static func trace(_ n: Int) -> MistakeTrace {
        var t = MistakeTrace()
        for i in 0..<n { t.record(refusal(i)) }
        return t
    }

    @Test("a ride's refusals reach the lifetime ledger and survive a relaunch")
    func aRideIsFoldedAndPersisted() throws {
        let model = AppModelTests.makeModel(vocab: Self.vocab())
        #expect(model.stumbleLedger.runsRecorded == 0, "a fresh install starts empty")

        for _ in 0..<Self.habitRuns { model.foldStumbles(Self.trace(2)) }
        #expect(model.stumbleLedger.runsRecorded == Self.habitRuns)
        #expect(model.stumbleLedger.entries["は"]?.runs == Self.habitRuns)

        // The point of a LIFETIME ledger is that it outlives the run. A second model over the
        // same directory must read it back — this is what distinguishes the feature from what
        // `ResultsView` already did.
        let reopened = AppModel(vocab: Self.vocab())
        #expect(reopened.stumbleLedger.runsRecorded == Self.habitRuns,
                "the ledger did not survive a relaunch — it is a per-run summary again")
        #expect(reopened.stumbleHabits.map(\.kana) == ["は"])
    }

    static var habitRuns: Int { AppModel.stumbleHabitRuns }

    /// The threshold is the app's, not the type's, and the list a learner reads must honour it.
    @Test("a kana below the habit threshold is recorded but not yet reported")
    func belowThresholdIsRecordedNotReported() {
        let model = AppModelTests.makeModel(vocab: Self.vocab())
        for _ in 0..<(Self.habitRuns - 1) { model.foldStumbles(Self.trace(1)) }

        #expect(model.stumbleLedger.entries["は"] != nil, "it must be RECORDED")
        #expect(model.stumbleHabits.isEmpty, "…and not yet REPORTED")

        // The paired control: one more run crosses the line. Without it, "empty" is equally
        // consistent with a fold that never happened.
        model.foldStumbles(Self.trace(1))
        #expect(model.stumbleHabits.map(\.kana) == ["は"])
    }

    /// **The two views must describe one population.** `stumblePatterns` is what a coach link
    /// would act on and `stumbleHabits` is what the learner reads; a defect here is invisible on
    /// screen and is this project's most-repeated shape.
    @Test("the pattern summary covers exactly the kana the habit list shows")
    func theTwoViewsShareAPopulation() {
        let model = AppModelTests.makeModel(vocab: Self.vocab())
        for _ in 0..<Self.habitRuns { model.foldStumbles(Self.trace(1)) }
        // …plus a kana that stays below the threshold, so the two lists CAN differ.
        var other = MistakeTrace()
        other.record(MistakeEvent(targetKana: "きゃく", entryID: nil, acceptedRomaji: "",
                                  rejected: "y", expectedNext: ["a"], kanaIndex: 1, order: 0))
        model.foldStumbles(other)

        let shown = Set(model.stumbleHabits.map(\.kana))
        let summarised = Set(model.stumblePatterns.flatMap(\.kana))
        #expect(!shown.isEmpty, "both empty would satisfy the line below")
        #expect(shown == summarised)
        #expect(!shown.contains("ゃ") && !shown.contains("き"),
                "a one-run kana reached the list a learner reads")
    }

    /// 🔴 A headless render plays FAKE runs. Its invented mistakes must not become the owner's
    /// typing history — the same rule `refreshWidgetSnapshot` follows, for the same reason, after
    /// v1.24 measured a test target stamping demo numbers onto the owner's real widget.
    @Test("a capture render does not write to the owner's ledger")
    func captureDoesNotFold() {
        let model = AppModelTests.makeModel(vocab: Self.vocab())
        Screenshotter.isCapturing = true
        defer { Screenshotter.isCapturing = false }

        for _ in 0..<Self.habitRuns { model.foldStumbles(Self.trace(5)) }
        #expect(model.stumbleLedger.runsRecorded == 0,
                "a capture render wrote \(model.stumbleLedger.runsRecorded) runs into the ledger")
    }

    /// …and its control, because the test above passes for a fold that never works at all.
    @Test("…and the same call outside capture DOES fold")
    func outsideCaptureItFolds() {
        let model = AppModelTests.makeModel(vocab: Self.vocab())
        model.foldStumbles(Self.trace(5))
        #expect(model.stumbleLedger.runsRecorded == 1)
    }

    /// **Once per ride, and that is a property of the CALL SITE.** A body that folds correctly
    /// called twice inflates `runs`, which is the only field the feature rests on — and no runtime
    /// state can show how many times something was called from where. So the source is scanned,
    /// the same shape `LocalChangeSeamTests.theSeamIsTheOnlyDoor` uses for the sync seam.
    @Test("finishGame folds the ledger exactly once, and nothing else folds it at all")
    func theFoldHasOneCallSite() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let model = try String(
            contentsOf: root.appendingPathComponent("Sources/NihongoRideApp/AppModel.swift"),
            encoding: .utf8)
        #expect(model.count > 50_000, "read \(model.count) bytes — the scan is misdirected")

        // Code only: a doc comment naming the function is not a call.
        let code = model.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        let calls = code.filter { $0.contains("foldStumbles(") && !$0.contains("func foldStumbles(") }
        #expect(calls.count == 1,
                "foldStumbles has \(calls.count) call sites: \(calls.map { $0.trimmingCharacters(in: .whitespaces) })")

        // …and it is inside `finishGame`, not somewhere a screen can reach twice.
        guard let finish = model.range(of: "lastSummary = GameSummary(from: session)") else {
            Issue.record("finishGame's anchor moved; this scan is now measuring nothing")
            return
        }
        let window = String(model[finish.lowerBound...].prefix(400))
        #expect(window.contains("foldStumbles("),
                "the fold is no longer beside the summary it summarises")
    }

    /// The DENOMINATOR the card prints must name the population it counts.
    ///
    /// `runsRecorded` counts rides in which the learner was refused at least once — a clean run
    /// folds nothing, deliberately. The first version of the caption said "of your N rides",
    /// which is a different population: somebody who rode fifty times and slipped in twenty-one
    /// would read 21, check the Ride Log, and find 50. A number labelled as something it is not is
    /// this project's signature defect, and this was a fresh one, caught by looking at the screen.
    ///
    /// The test pins the FACT, not the wording — a caption is a view's business — so it asserts
    /// the two counts genuinely differ when clean runs happen. Without that, "rides where you
    /// slipped" and "your rides" are indistinguishable and the copy fix is unfalsifiable.
    @Test("the ledger's run count is rides-with-a-mistake, not rides")
    func theDenominatorIsRidesWithAMistake() {
        let model = AppModelTests.makeModel(vocab: Self.vocab())
        for _ in 0..<Self.habitRuns { model.foldStumbles(Self.trace(1)) }
        // Three clean rides. A learner has now ridden 6 times and slipped in 3.
        for _ in 0..<3 { model.foldStumbles(MistakeTrace()) }

        #expect(model.stumbleLedger.runsRecorded == Self.habitRuns,
                "clean rides entered the denominator the card prints")
        #expect(model.stumbleLedger.entries["は"]?.runs == Self.habitRuns,
                "the numerator and the denominator must count the same population")
    }

    /// **Constraint 3, asserted rather than claimed.**
    ///
    /// `PLAN-WINDOW`'s third constraint is that a feature which substantially changes how far
    /// people ride changes exposure-per-install, and must be REGISTERED in `PLAN-STAGE1` §K before
    /// it ships. §F2 does not need that registration, and the reason is narrow: the card is
    /// READ-ONLY. It starts no run, and it does not link to the coach drill — which is a real ride
    /// (`makePractice`, ~3.4 km) reachable exactly as before, from the results screen.
    ///
    /// "It has no button" is the kind of claim that is true when written and false two releases
    /// later, which is why it is a test. If a future change gives this card an action, this fails
    /// and whoever wrote it reads the registration rule instead of discovering it at a checkpoint.
    @Test("the stumble card starts nothing — so §F2 needs no constraint-3 registration")
    func theCardCannotStartARide() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let stats = try String(
            contentsOf: root.appendingPathComponent("Sources/NihongoRideApp/StatsView.swift"),
            encoding: .utf8)
        #expect(stats.count > 5_000, "read \(stats.count) bytes — the scan is misdirected")
        #expect(stats.contains("stumbleCard"), "the subject of this test is gone")

        let code = stats.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        // Every way this screen could begin a ride. `backToMenu` is the one navigation it has and
        // it moves nobody down the road.
        for starter in ["startCoachDrill", "startGame(", "startListGame", "startSavedGame",
                        "startStumbledWords", "startConjugation", "screen = .playing"] {
            #expect(!code.contains { $0.contains(starter) },
                    "StatsView now calls \(starter) — that makes it a ride entrance, which is a constraint-3 change: register it in PLAN-STAGE1 §K before the release ships, do not avoid it")
        }
    }

    /// The one thing that is NEVER allowed to change: this ledger is local. A source scan,
    /// because the property is about what the code does not do, and no runtime state can show
    /// the absence of an upload.
    @Test("nothing transmits the ledger")
    func theLedgerIsNeverTransmitted() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sync = try String(
            contentsOf: root.appendingPathComponent("Sources/NihongoRideApp/CloudKitSyncController.swift"),
            encoding: .utf8)
        #expect(sync.count > 10_000, "read \(sync.count) bytes — the scan is misdirected")
        #expect(!sync.contains("stumbleLedger") && !sync.contains("StumbleLedger"),
                "the sync controller now names the stumble ledger — it is local by design, Data Not Collected stays, and merging two devices' habits would average away the thing it exists to show")
    }
}
