import Testing
import Foundation
import RomajiKana
import PersistKit
@testable import DiagnosticsKit

/// The ledger that finally asks the question the app has had the data for since v1.18 (v1.32 §F2).
///
/// Every assertion here is paired with the thing it would otherwise be satisfied by. That is not
/// ceremony: a ledger is an aggregate, and an aggregate's failure mode is producing a plausible
/// number from the wrong population — which `STATE-2026-08-18.md` records as the family a
/// known-positive control does NOT catch.
@Suite("The stumble ledger — what a learner keeps missing")
struct StumbleLedgerTests {

    static let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    static func day(_ n: Int) -> Date { t0.addingTimeInterval(Double(n) * 86_400) }

    /// One refusal standing on `kana` inside `target`.
    ///
    /// Built through the real `MistakeEvent` initialiser so `kanaAtMistake` — the accessor the
    /// ledger keys on — is exercised rather than bypassed.
    static func event(target: String, index: Int, rejected: Character,
                      expected: Set<Character>, order: Int = 0) -> MistakeEvent {
        MistakeEvent(targetKana: target, entryID: nil, acceptedRomaji: "",
                     rejected: rejected, expectedNext: expected, kanaIndex: index, order: order)
    }

    static func trace(_ events: [MistakeEvent]) -> MistakeTrace {
        var t = MistakeTrace()
        for e in events { t.record(e) }
        return t
    }

    /// は typed `wa` — the particle-spelling pattern, and the most common real one.
    static func particleRefusal(order: Int = 0) -> MistakeEvent {
        event(target: "こんにちは", index: 4, rejected: "w", expected: ["h"], order: order)
    }

    // MARK: runs vs refusals

    /// **The field the whole type rests on.** Hold a key down and you can log two hundred
    /// refusals on one kana in a minute — which is why `MistakeTrace` is capped at 200. A kana
    /// that recurs across separate sittings is a different claim, and it is the one worth showing.
    @Test("one run of many refusals is one RUN, however many refusals it holds")
    func refusalsAndRunsAreDifferentFacts() {
        var ledger = StumbleLedger()
        ledger.fold(Self.trace((0..<50).map { Self.particleRefusal(order: $0) }), now: Self.day(0))

        let entry = ledger.entries["は"]
        #expect(entry?.refusals == 50)
        #expect(entry?.runs == 1, "fifty refusals in one sitting is one run, not fifty")
        #expect(ledger.runsRecorded == 1)

        // …and the control: a second run must move `runs` by ONE and `refusals` by ten.
        //
        // Ten, not one, and the difference is the whole test. The first version of this used a
        // single refusal here — and a mutation that incremented `runs` by the refusal COUNT
        // survived, because +1 and +1 are the same number. A control whose two arms cannot be
        // told apart is not a control. (Found by the mutation harness, which is what it is for.)
        ledger.fold(Self.trace((0..<10).map { Self.particleRefusal(order: $0) }), now: Self.day(1))
        #expect(ledger.entries["は"]?.runs == 2, "ten refusals in the second sitting counted as ten runs")
        #expect(ledger.entries["は"]?.refusals == 60)
        #expect(ledger.runsRecorded == 2)
    }

    /// An empty trace is not a run. A ride with no mistakes must not inflate the denominator that
    /// "in 9 of your last 20" is read against.
    @Test("a clean run folds nothing")
    func aCleanRunIsNotRecorded() {
        var ledger = StumbleLedger()
        ledger.fold(MistakeTrace(), now: Self.day(0))
        #expect(ledger.runsRecorded == 0)
        #expect(ledger.entries.isEmpty)
    }

    // MARK: the habit threshold

    /// `minimumRuns` has no default, and this is why: without it, "what you keep missing" and
    /// "everything you have ever mistyped" are the same call.
    @Test("a kana from a single run is not yet a habit")
    func oneRunIsNotAHabit() {
        var ledger = StumbleLedger()
        ledger.fold(Self.trace([Self.particleRefusal()]), now: Self.day(0))
        #expect(ledger.habits(minimumRuns: 2).isEmpty)
        // The paired control: the SAME ledger at a threshold of 1 does return it, so the empty
        // result above is the threshold working and not the fold failing.
        #expect(ledger.habits(minimumRuns: 1).count == 1)
    }

    /// Sorted by RUNS first, because a kana seen in six sittings is a stronger finding than one
    /// hammered eighty times in a single bad minute.
    @Test("habits are ordered by how many sittings they span, not by raw refusals")
    func habitsAreOrderedByRuns() {
        var ledger = StumbleLedger()
        // っ: one run, 80 refusals.
        ledger.fold(Self.trace((0..<80).map {
            Self.event(target: "いって", index: 1, rejected: "t", expected: ["c"], order: $0)
        }), now: Self.day(0))
        // は: four runs, one refusal each.
        for d in 1...4 {
            ledger.fold(Self.trace([Self.particleRefusal()]), now: Self.day(d))
        }

        let habits = ledger.habits(minimumRuns: 1)
        #expect(habits.first?.kana == "は", "80 refusals in one sitting outranked four sittings")
        #expect(habits.first?.runs == 4)
        #expect(habits.count == 2)
        #expect(ledger.entries["っ"]?.refusals == 80, "the loud one is still recorded, just not first")
    }

    /// The v1.23 weak-words bug verbatim, in the one member that caps: filter, then cap. Capping
    /// first and filtering after promised fifteen and rode twelve.
    @Test("the habit threshold is applied BEFORE the limit")
    func theThresholdPrecedesTheLimit() {
        var ledger = StumbleLedger()
        // Three one-run kana that would fill a limit of 3 if the cap came first…
        for (i, kana) in ["か", "き", "く"].enumerated() {
            ledger.fold(Self.trace([Self.event(target: kana, index: 0, rejected: "x",
                                               expected: ["k"])]), now: Self.day(i))
        }
        // …and one genuine habit, added last so an unsorted or cap-first implementation loses it.
        for d in 10...13 {
            ledger.fold(Self.trace([Self.particleRefusal()]), now: Self.day(d))
        }

        let habits = ledger.habits(minimumRuns: 2, limit: 3)
        #expect(habits.count == 1, "the one-run kana were counted as habits")
        #expect(habits.first?.kana == "は")
    }

    // MARK: the dominant pattern

    /// The bridge to the coach, which drills a PATTERN and not a kana. It is decided over the
    /// lifetime rather than by the latest run, so one odd sitting cannot relabel a long habit.
    @Test("the dominant pattern is the lifetime one, not the most recent run's")
    func theDominantPatternIsStable() {
        var ledger = StumbleLedger()
        for d in 0..<5 {
            ledger.fold(Self.trace([Self.particleRefusal()]), now: Self.day(d))
        }
        #expect(ledger.entries["は"]?.pattern == .particleSpelling)

        // One run where the same kana is refused for an unrelated reason must not flip the label.
        ledger.fold(Self.trace([Self.event(target: "こんにちは", index: 4,
                                           rejected: "q", expected: ["h"])]), now: Self.day(9))
        #expect(ledger.entries["は"]?.pattern == .particleSpelling,
                "a single odd run relabelled a five-run habit")
    }

    /// **The label follows the evidence — a habit that CHANGES gets relabelled.**
    ///
    /// The mirror of `theDominantPatternIsStable`, and the half that was missing. Stability alone
    /// is satisfied by a field that can never change, and that is exactly what the first version
    /// shipped: each run's count was compared against a lifetime accumulator and a challenger's
    /// evidence was discarded rather than banked, so once the incumbent's total passed any
    /// plausible single-run count the label was frozen for good. A learner who fixed their
    /// particle habit and now trips on the same kana for a different reason would have kept being
    /// told the rule they had already learned — on the one sentence the Stats card exists to
    /// deliver. (Found by the v1.32 pre-submission review.)
    @Test("…and a habit that genuinely changes IS relabelled")
    func theDominantPatternFollowsTheEvidence() throws {
        var ledger = StumbleLedger()
        // A long particle habit: ten runs, one refusal each.
        for d in 0..<10 { ledger.fold(Self.trace([Self.particleRefusal()]), now: Self.day(d)) }
        let incumbent = try #require(ledger.entries["は"])
        #expect(incumbent.pattern == .particleSpelling)
        #expect(incumbent.dominantCount == 10, "the accumulator is not the lifetime total it is compared against: \(incumbent.dominantCount)")

        // Now the same kana, refused for a different reason, in enough runs to outweigh it —
        // never more than 3 in any single run, which is the case the old rule could not see.
        for d in 10..<25 {
            ledger.fold(Self.trace([Self.event(target: "こんにちは", index: 4,
                                               rejected: "q", expected: ["h"])]), now: Self.day(d))
        }
        let entry = try #require(ledger.entries["は"])
        #expect(entry.pattern != .particleSpelling,
                "15 runs of new evidence against 10 of old did not move the label — a challenger's counts are being discarded rather than banked, and the advice sentence is frozen")
        #expect(entry.patternCounts["particleSpelling"] == 10,
                "the old evidence was destroyed rather than kept; the label must be able to move BACK")
        #expect(entry.dominantCount == 15)
        #expect(entry.runs == 25, "the run count went with it")
    }

    /// The arithmetic under the label: every refusal is banked exactly once, and the totals add
    /// up to the refusals the ledger says it saw. The old code ASSIGNED on one branch — a run of
    /// 1 followed by a run of 5 on the same pattern stored 5, not 6 — so the number the label was
    /// chosen by was smaller than the evidence behind it.
    @Test("the per-pattern totals account for every refusal")
    func thePatternTotalsAddUp() throws {
        var ledger = StumbleLedger()
        ledger.fold(Self.trace([Self.particleRefusal()]), now: Self.day(0))
        ledger.fold(Self.trace([Self.particleRefusal(), Self.particleRefusal(),
                                Self.particleRefusal(), Self.particleRefusal(),
                                Self.particleRefusal()]), now: Self.day(1))
        let entry = try #require(ledger.entries["は"])
        #expect(entry.refusals == 6, "the fixture did not produce 6 refusals: \(entry.refusals)")
        #expect(entry.patternCounts.values.reduce(0, +) == entry.refusals,
                "the per-pattern totals sum to \(entry.patternCounts.values.reduce(0, +)) against \(entry.refusals) refusals — one branch is assigning where it should add")
        #expect(entry.dominantCount == 6)
        #expect(entry.runs == 2)
    }

    /// `dominantPatterns` must summarise the SAME list the learner reads. Two views of one ledger
    /// describing different populations is this project's signature defect.
    @Test("the pattern summary is built from the habits, not from everything")
    func thePatternSummaryMatchesTheHabits() {
        var ledger = StumbleLedger()
        for d in 0..<3 { ledger.fold(Self.trace([Self.particleRefusal()]), now: Self.day(d)) }
        // A one-run kana that must NOT appear in the summary at a threshold of 2.
        ledger.fold(Self.trace([Self.event(target: "きゃく", index: 1, rejected: "y",
                                           expected: ["a"])]), now: Self.day(8))

        let habits = Set(ledger.habits(minimumRuns: 2).map(\.kana))
        let summarised = Set(ledger.dominantPatterns(minimumRuns: 2).flatMap(\.kana))
        #expect(summarised == habits, "the summary describes a different set than the list")
        #expect(!summarised.isEmpty, "both empty would satisfy the line above")
    }

    // MARK: bounds

    /// A ledger that quietly stopped recording would look exactly like a learner who stopped
    /// making mistakes. So the cap COUNTS what it refused, the way `MistakeTrace.dropped` does.
    @Test("the cap is counted, not silent")
    func theCapIsCounted() {
        var ledger = StumbleLedger()
        // One DISTINCT kana per run, past the capacity. Built from the CJK plane so the keys are
        // real characters rather than a range that happens to be empty.
        var kana: [String] = []
        for i in 0..<(StumbleLedger.capacity + 5) {
            let scalar = UnicodeScalar(0x4E00 + i)!
            kana.append(String(Character(scalar)))
        }
        var distinct = Set<String>()
        for i in 0..<kana.count {
            let k: String = kana[i]
            distinct.insert(k)
            let e = Self.event(target: k, index: 0, rejected: "x", expected: ["y"])
            ledger.fold(Self.trace([e]), now: Self.day(i))
        }
        #expect(ledger.entries.count <= StumbleLedger.capacity)
        if distinct.count > StumbleLedger.capacity {
            #expect(ledger.droppedKana > 0, "the cap bound but reported nothing")
        }
    }

    // MARK: persistence

    @Test("a ledger round-trips through its own file, whole")
    func itRoundTrips() throws {
        var ledger = StumbleLedger()
        for d in 0..<3 { ledger.fold(Self.trace([Self.particleRefusal()]), now: Self.day(d)) }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("stumble-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try ledger.save(to: url)
        #expect(StumbleLedger.load(from: url) == ledger)

        // A missing file is an empty ledger, not a crash — the learner has simply not ridden yet.
        let absent = url.appendingPathExtension("nope")
        #expect(StumbleLedger.load(from: absent) == StumbleLedger())

        // …and a corrupt one degrades the same way rather than taking the launch with it.
        try Data("{not json".utf8).write(to: url)
        #expect(StumbleLedger.load(from: url) == StumbleLedger())
    }

    /// **One malformed entry costs that entry — the claim the decoder's own comment makes.**
    ///
    /// It used to be false: the comment said "element-lossy" and the line under it decoded
    /// `[String: Entry]` whole, so one missing field threw for the entire dictionary and `load`
    /// swallowed it into an empty ledger. `itRoundTrips` could not see it — whole-file garbage
    /// fails identically either way — so the claim was untrue AND unfalsified, which is this
    /// project's second signature defect sitting in the store's own decoder.
    /// (Found by the v1.32 pre-submission review.)
    @Test("one malformed entry costs that entry, not the whole ledger")
    func oneBadEntryCostsOneEntry() throws {
        // Built as JSON objects rather than as an encoded fixture: the defect is about a field
        // that is NOT there, and the encoder cannot produce one.
        func record(_ kana: String) -> [String: Any] {
            ["kana": kana, "refusals": 7, "runs": 3, "lastSeen": 760_000_000,
             "patternCounts": ["particleSpelling": 7]]
        }
        var broken = record("き")
        broken.removeValue(forKey: "runs")
        #expect(broken.count == record("き").count - 1, "the fixture was not damaged, so both entries are valid and the assertions below are vacuous")

        func ledger(_ entries: [String: Any]) throws -> (StumbleLedger, LossyLoad.Outcome) {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("stumble-lossy-\(UUID().uuidString).json")
            defer { try? FileManager.default.removeItem(at: url) }
            let body: [String: Any] = ["entries": entries, "droppedKana": 0, "runsRecorded": 9]
            try JSONSerialization.data(withJSONObject: body).write(to: url)
            return StumbleLedger.loadReporting(from: url)
        }

        // THE CONTROL. Two well-formed entries load as two — without it, "1 survived" is equally
        // consistent with a decoder that keeps only the first thing it sees.
        let (whole, wholeOutcome) = try ledger(["は": record("は"), "き": record("き")])
        #expect(whole.entries.count == 2, "the control did not fire: two valid entries decoded as \(whole.entries.count)")
        #expect(wholeOutcome == .loaded)

        let (partial, outcome) = try ledger(["は": record("は"), "き": broken])
        #expect(partial.entries.count == 1, "one entry missing one field cost \(2 - partial.entries.count) of 2 entries")
        #expect(partial.entries["は"]?.runs == 3, "the surviving entry did not survive intact")
        #expect(partial.runsRecorded == 9, "the ledger's own counters went with the bad entry")
        #expect(partial.skippedOnLoad == 1)
        #expect(outcome == .loadedWithSkips(skipped: 1),
                "the loss was silent — `persistLoadOutcomes` prints this line, and a learner asking why their card emptied is the reason it exists")
    }

    /// **An UNREADABLE ledger is not the same as a corrupt one, and must not be written over.**
    ///
    /// `AppModel` decides that with `stumbleLedgerWritable`; this pins the half that lives here —
    /// that `loadReporting` can tell the two apart at all. It could not before v1.32: the loader
    /// was the `try? Data` / `try? decode` block quoted at the top of `LossyLoad` as the pattern
    /// that module exists to delete.
    @Test("unreadable and undecodable are different answers")
    func unreadableIsNotUndecodable() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("stumble-perm-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
            try? FileManager.default.removeItem(at: url)
        }
        var ledger = StumbleLedger()
        ledger.fold(Self.trace([Self.particleRefusal()]), now: Self.day(0))
        try ledger.save(to: url)

        // THE CONTROL: readable bytes decode, so a `.unreadable` below is about the permissions
        // and not about a fixture that never loaded.
        #expect(StumbleLedger.loadReporting(from: url).outcome == .loaded)

        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        let (empty, outcome) = StumbleLedger.loadReporting(from: url)
        // Running as root would make the file readable anyway and the assertion vacuous.
        try #require(outcome != .loaded, "the file was still readable — this test needs a non-root user")
        #expect(outcome == .unreadable,
                "an unreadable ledger reported \(outcome): `isSafeToWrite` is then true and the next finished ride overwrites bytes that are probably intact")
        #expect(empty == StumbleLedger(), "the stand-in must be empty, so the app still runs")
        #expect(!LossyLoad.isSafeToWrite(outcome))
        #expect(!FileManager.default.fileExists(atPath: url.appendingPathExtension("corrupt").path),
                "unreadable bytes were quarantined, which copies nothing and only creates a second confusing file")
    }

    /// The fixture must differ from a default value, or the round trip above cannot see a dropped
    /// field. Same precondition `CloudKitCodecTests` states for the same reason.
    @Test("the round-trip fixture is distinguishable from an empty ledger")
    func theFixtureIsUsable() {
        var ledger = StumbleLedger()
        ledger.fold(Self.trace([Self.particleRefusal()]), now: Self.day(0))
        #expect(ledger != StumbleLedger())
        #expect(ledger.runsRecorded != 0)
        let entry = ledger.entries["は"]
        #expect(entry?.refusals != 0 && entry?.runs != 0)
        #expect(entry?.lastSeen != Date(timeIntervalSince1970: 0))
        #expect(entry?.dominantPattern != TypingPattern.unknown.rawValue,
                "an entry whose pattern is the fallback cannot show a dropped pattern field")
    }
}
