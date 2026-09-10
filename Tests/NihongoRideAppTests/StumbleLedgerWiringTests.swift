import Testing
import Foundation
import VocabKit
import GameCore
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
        // THE WHOLE MODULE, not just AppModel.swift. `foldStumbles` is internal — deliberately,
        // so `@testable` can reach it — which means any of the ~30 files in this executable target
        // can call it, and a scan of one file would have said "exactly once" while a view called
        // it on appear. The name of this test claimed module scope and the body read one path.
        // `LocalChangeSeamTests.theSeamIsTheOnlyDoor`, which this comment already named as the
        // shape being copied, walks the directory; now so does this. (v1.32 review.)
        let appDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/NihongoRideApp")
        let files = try FileManager.default.contentsOfDirectory(atPath: appDirectory.path)
            .filter { $0.hasSuffix(".swift") }.sorted()
        #expect(files.count > 20, "the directory walk found \(files.count) files — it is misdirected")

        var calls: [String] = []
        var model = ""
        for file in files {
            let source = try String(contentsOf: appDirectory.appendingPathComponent(file),
                                    encoding: .utf8)
            if file == "AppModel.swift" { model = source }
            // Code only: a doc comment naming the function is not a call.
            calls += source.components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .filter { $0.contains("foldStumbles(") && !$0.contains("func foldStumbles(") }
                .map { "\(file): \($0.trimmingCharacters(in: .whitespaces))" }
        }
        #expect(model.count > 50_000, "read \(model.count) bytes of AppModel — the scan is misdirected")
        #expect(calls.count == 1,
                "foldStumbles has \(calls.count) call sites across the module: \(calls)")
        #expect(calls.first?.hasPrefix("AppModel.swift:") == true,
                "the one call is no longer in AppModel: \(calls)")
        // …and it is inside `finishGame`, not somewhere a screen can reach twice.
        guard let finish = model.range(of: "lastSummary = GameSummary(from: session)") else {
            Issue.record("finishGame's anchor moved; this scan is now measuring nothing")
            return
        }
        // 1600 rather than 400: the fix that gated this call carries the reasoning for the gate
        // in a comment above it, and a window that a comment can push the subject out of is a
        // window that fails for a reason unrelated to what it measures. It is still far short of
        // `logRun`, which is what "beside the summary" is protecting against.
        let window = String(model[finish.lowerBound...].prefix(1_600))
        #expect(window.contains("foldStumbles("),
                "the fold is no longer beside the summary it summarises")

        // …and the GATE, because `aCramIsNotFolded` proves the behaviour today and a source scan
        // is what survives somebody moving the call. A cram must not enter a count captioned
        // "rides": `logsRide` is the predicate the journal, the odometer and `lifetimeRuns` all
        // use, and the whole point is that one predicate decides all four.
        let call = try #require(calls.first)
        #expect(call.contains("completion.logsRide"),
                "the fold is no longer gated on the predicate every other lifetime write uses — the line reads: \(call)")
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

    /// **A cram is not a ride, and the ledger's denominator says "rides".**
    ///
    /// `finishGame` gates every other lifetime write on `completion.logsRide` — the journal, the
    /// odometer, and through them `lifetimeRuns`. The fold was not gated, so a weak-words cram
    /// (`GameSession.makeWeak`, `recordsSRS == false`, therefore `isCram`) incremented
    /// `runsRecorded` while incrementing nothing else. Two consequences, both visible:
    ///
    /// * the Stats screen prints `lifetimeRuns` in a tile and `runsRecorded` in the card below
    ///   it, captioned "the N rides where you slipped" — a denominator the Ride Log cannot
    ///   reproduce and can exceed the total ride count sitting directly above it;
    /// * the cram is reached from the results screen's "ride these N words" button, which is the
    ///   app's own remediation loop. Slip on は, tap it, slip again, tap again: three `runs` in
    ///   three minutes, `stumbleHabitRuns` met, and the card reports a lifetime habit built from
    ///   one sitting — the exact claim `StumbleLedger`'s type doc says `runs` exists to prevent.
    ///
    /// `theDenominatorIsRidesWithAMistake` above only ruled out CLEAN runs, so "rides where you
    /// slipped" and "runs where you slipped" stayed indistinguishable. This is the missing half,
    /// and it walks the real journey rather than calling `foldStumbles` directly — the gate is a
    /// property of the CALL SITE, and a test that calls the callee cannot see it.
    /// (Found by the v1.32 pre-submission review.)
    @Test("a weak-words cram does not enter the ledger — and the ride that fed it does")
    func aCramIsNotFolded() throws {
        let model = AppModelTests.makeModel(
            vocab: VocabStore(entries: AppModelTests.verbEntries(10)))
        model.selectedMode = .journey

        // 1. A real ride, ridden badly. THE CONTROL: if this does not fold, everything below is
        //    about a harness that never folds anything.
        model.startGame()
        Self.rideBadly(model)
        model.finishGame()
        #expect(model.stumbleLedger.runsRecorded == 1, "the control did not fire: a ridden run with refusals folded nothing, so the cram assertion below is vacuous")
        #expect(model.journal.records.count == 1, "…and it must be a ride, or `logsRide` is not what is being measured")
        let afterTheRide = model.stumbleLedger.entries

        // 2. The cram, entered through the same door the results screen uses —
        //    `startStumbledWords(_:)`, handed the chips `ResultsView.rideTheseButton` hands it.
        //    The chips are built here rather than derived from step 1's trace because
        //    `StumbledWords.from` only produces chips for SENTENCE runs (it requires
        //    `entry.exampleKana == event.targetKana`), and the gate under test lives in
        //    `finishGame`, not in how the chips were derived. Built from the model's own vocab so
        //    `rideableStumbles` genuinely resolves them — asserted, not assumed, on the next line.
        let entry = try #require(model.vocab.entries.first)
        let displayed = [StumbledWords.Stumble(surface: entry.surface, reading: entry.kana,
                                               refusals: 3, entryID: entry.id)]
        #expect(!model.rideableStumbles(displayed).isEmpty, "the chip does not resolve, so the button a learner taps was never reachable here and the run below is empty")
        model.startStumbledWords(displayed)
        #expect(model.session != nil, "the cram never started — the two expectations below would pass for a test that rode nothing")
        Self.rideBadly(model)
        model.finishGame()

        #expect(model.journal.records.count == 1, "a cram logged a ride; `logsRide` has changed meaning and this whole test is now measuring something else")
        #expect(model.stumbleLedger.runsRecorded == 1, "a cram entered the ledger's run count: the Stats card's denominator says \"rides\" and the Ride Log will disagree with it")
        #expect(model.stumbleLedger.entries == afterTheRide, "a cram moved a kana's `runs`, which is the field that decides whether the app calls something a habit")
    }

    /// Types a run through, being refused twice on every word before typing it correctly.
    ///
    /// The refused character is chosen against `expectedNextCharacters` rather than hard-coded:
    /// a "wrong" key that the matcher happens to accept would advance the word and desynchronise
    /// the romaji typed after it, and the test would then measure the harness.
    static func rideBadly(_ model: AppModel) {
        var guardrail = 0
        while let session = model.session, !session.isFinished, guardrail < 5_000 {
            guard let romaji = session.currentRomaji, !romaji.isEmpty else { session.skip(); continue }
            let expected = session.expectedNextCharacters
            let wrong = "abcdefghijklmnopqrstuvwxyz".first { !expected.contains($0) }
            if let wrong {
                // Two, so the chips clear `StumbledWords.from`'s `minimumRefusals` default and
                // the results screen this test drives is the one a learner sees.
                _ = session.input(wrong)
                _ = session.input(wrong)
            }
            for character in romaji { _ = session.input(character) }
            guardrail += romaji.count + 2
        }
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

        // The list of ride entrances is DERIVED from AppModel, not typed here. The typed version
        // named seven and missed at least five that already exist and are already called from
        // other views — `startWeakWords()`, `startDictationList(_:)`, `startDictationDue()`,
        // `startSentenceList(_:)`, `startSentenceDue()` — so a future `startWhatever()` would have
        // been missed for the same reason. A hand-maintained list of everything that must not
        // happen is the shape this project keeps discovering is stale. (v1.32 review.)
        let appModel = try String(
            contentsOf: root.appendingPathComponent("Sources/NihongoRideApp/AppModel.swift"),
            encoding: .utf8)
        var starters: Set<String> = ["screen = .playing"]
        for line in appModel.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let range = trimmed.range(of: "func start") else { continue }
            guard !trimmed.hasPrefix("//") else { continue }
            let after = trimmed[range.upperBound...]
            guard let first = after.first, first.isUppercase || first == "(" else { continue }
            let name = "start" + after.prefix { $0.isLetter || $0.isNumber }
            starters.insert(name)
        }
        #expect(starters.count >= 8,
                "derived only \(starters.count) ride entrances from AppModel — the scan is misdirected and would pass for a screen that starts anything")
        #expect(starters.contains("startWeakWords") && starters.contains("startStumbledWords"),
                "the derivation missed a known entrance: \(starters.sorted())")

        for starter in starters.sorted() {
            #expect(!code.contains { $0.contains(starter) },
                    "StatsView now calls \(starter) — that makes it a ride entrance, which is a constraint-3 change: register it in PLAN-STAGE1 §K before the release ships, do not avoid it")
        }
    }

    /// **An unreadable ledger is not overwritten by the next finished ride.**
    ///
    /// `foldStumbles` used to pass `allowed: true` — the only one of AppModel's twelve store
    /// writes that did not carry a real writability bit, against a parameter whose own doc says
    /// *"false when this store was UNREADABLE at launch … writing it would replace a file that is
    /// probably intact with nothing."* The failure it protects against is measured and transient
    /// in this repo — `NihongoRideApp.swift` offers a Retry for exactly it, citing file protection
    /// while the device is unlocking and a busy volume. One such launch, one finished ride, and a
    /// learner's whole stumble history was gone: silently, with no `.corrupt` sibling, no alert,
    /// and the Stats card simply vanishing (it draws nothing below three runs).
    ///
    /// The trade `AppModel.init` records — degrade rather than quarantine — is a fair one for a
    /// CORRUPT ledger and backwards for an unreadable one, where the cost of refusing to write is
    /// one session's stumbles. (Found by the v1.32 pre-submission review.)
    @Test("a ledger that could not be READ at launch is not written over")
    func anUnreadableLedgerSurvivesTheNextRide() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory
            .appendingPathComponent("NihongoRideAppTests-\(UUID().uuidString)", isDirectory: true)
        // The app's own path, not the sandbox root: `supportFileURL` nests everything under a
        // `NihongoRide/` subdirectory. Getting this wrong is not a harmless mistake — the first
        // draft of this test wrote to `dir/` and passed, because an ABSENT file is also never
        // overwritten. The control below is what found it.
        let dir = base.appendingPathComponent("NihongoRide", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("stumble-ledger.json")
        defer {
            try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
            try? fm.removeItem(at: base)
        }

        // A history worth losing: three runs, one habit, written the way the app writes it.
        var existing = StumbleLedger()
        for _ in 0..<Self.habitRuns { existing.fold(Self.trace(2)) }
        try existing.save(to: url)
        let bytesBefore = try Data(contentsOf: url)
        #expect(existing.runsRecorded == Self.habitRuns)

        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        try #require((try? Data(contentsOf: url)) == nil, "the file was still readable — this test needs a non-root user")

        AppModel.supportDirectoryOverride = base
        AppModel.widgetContainerOverride = base.appendingPathComponent("group", isDirectory: true)
        let suite = "NihongoRideTests-\(UUID().uuidString)"
        AppModel.settingsDefaults = UserDefaults(suiteName: suite)
        AppModel.settingsSuiteOverride = suite
        let model = AppModel(vocab: Self.vocab())
        #expect(model.stumbleLedger.runsRecorded == 0, "the unreadable file decoded anyway, so nothing below is about an unreadable store")

        // `bgSave` is synchronous, so the file is whatever it is going to be by the time this
        // returns. The whole point is that it is unchanged.
        model.foldStumbles(Self.trace(4))
        try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        let bytesAfter = try Data(contentsOf: url)
        #expect(bytesAfter == bytesBefore,
                "one unlucky launch plus one ride erased the learner's lifetime ledger: \(bytesBefore.count) bytes became \(bytesAfter.count)")
        #expect(StumbleLedger.load(from: url).runsRecorded == Self.habitRuns,
                "the history is gone even though the bytes changed size plausibly")
    }

    /// …and its control: the same ride against a READABLE ledger does write. Without this, the
    /// test above passes for a fold that has stopped saving at all.
    @Test("…and a readable one IS written")
    func aReadableLedgerIsWritten() throws {
        let (model, dir) = AppModelTests.sandboxed(vocab: Self.vocab())
        let url = dir.appendingPathComponent("NihongoRide", isDirectory: true)
            .appendingPathComponent("stumble-ledger.json")
        model.foldStumbles(Self.trace(4))
        #expect(FileManager.default.fileExists(atPath: url.path), "no ledger file was written at all")
        #expect(StumbleLedger.load(from: url).runsRecorded == 1)
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
