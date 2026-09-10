import Testing
import Foundation
import RomajiKana
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
