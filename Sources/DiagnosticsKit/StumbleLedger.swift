import Foundation
import RomajiKana
import PersistKit

/// What a learner keeps getting refused on, **across rides** (v1.32 §F2).
///
/// # The gap this fills
///
/// The app has had the data since v1.18 and has never asked the question. Every run produces a
/// `MistakeTrace`; `StumbledWords` turns it into the chips on the results screen and
/// `TypingDiagnostics` into the coach's headline — and then it is gone. `AppModel.GameSummary`
/// says so in as many words: *"In memory with the summary; never persisted."*
///
/// So the app can tell you what you missed **in this run** and has never once been able to tell
/// you what you keep missing. A learner who fumbles は in nine runs out of ten sees nine separate
/// observations and no pattern, which is precisely the thing a person cannot see about themselves
/// and software can.
///
/// # What is recorded, and what deliberately is not
///
/// Per KANA: how many keystrokes were refused while standing on it, how many distinct RUNS it
/// happened in, when it was last seen, and which `TypingPattern` explains most of them.
///
/// **`runs` is the load-bearing field, not `refusals`.** One bad run is not a pattern — hold a key
/// down and you can log two hundred refusals on one kana in a minute, which is exactly why
/// `MistakeTrace` is capped. A kana that turns up across several separate sittings is a different
/// claim, and it is the one worth showing. `Diagnosis.isRecurring` makes the same distinction one
/// level down, and for the same reason.
///
/// **Nothing here is ever transmitted.** `PLAN-WINDOW`'s constraint list forbids collected
/// telemetry; it does not forbid counting, and this file counts. The app's privacy declaration
/// stays `Data Not Collected` and this ledger must never become a reason to change it: it is a
/// local file, in Application Support, beside the review stores, and nothing in this app sends it
/// anywhere — not CloudKit, not an export, not a log. It rides along in the user's own device
/// backup exactly as every other store here does, which is what "stays on the device" means for
/// this app and is consistent with `Data Not Collected`.
///
/// # Bounds
///
/// Keyed by kana, so the key space is the syllabary — a few hundred at most, and it cannot grow
/// with the corpus the way an entry-id key would (7,071 and rising). `capacity` is a second belt:
/// a corpus edit that introduced an unexpected character class cannot make this file grow without
/// limit, and what was dropped is COUNTED rather than silently discarded — counted for a future
/// reader, which is a weaker promise than `MistakeTrace.dropped` keeps: that one reaches the
/// learner, through `TypingDiagnostics`' `sampleTruncated`. `droppedKana` reaches a test and
/// nothing else. Deliberate, because the cap cannot bind (see the key space above) — but stated
/// accurately rather than by claiming a parity that is not there.
public struct StumbleLedger: Codable, Equatable, Sendable {

    /// One kana the learner keeps being refused on.
    public struct Entry: Codable, Equatable, Sendable {
        /// The kana itself, as a string because `Character` is not a dictionary key that
        /// round-trips through JSON cleanly.
        public let kana: String
        /// Refused keystrokes while standing on this kana, all runs.
        public var refusals: Int
        /// How many distinct RUNS it happened in. See the type doc: this is the field that
        /// separates a pattern from one bad minute.
        public var runs: Int
        /// When it was last refused, so a ledger can age.
        public var lastSeen: Date
        /// Lifetime refusals on this kana, per `TypingPattern` raw value.
        ///
        /// Keyed by raw value rather than by the enum so the file survives a pattern being
        /// renamed or retired — an unknown key decodes fine and simply stops winning.
        ///
        /// **A map, not a winner plus a tally**, and the first version was the latter: it kept
        /// `dominantPattern`/`dominantCount` and compared each RUN's count against a LIFETIME
        /// accumulator, so a challenger's evidence was thrown away instead of banked. Two
        /// consequences. Once the incumbent's accumulator passed any plausible single-run count
        /// the label could never change again — a learner who fixed their particle habit and now
        /// trips on the same kana for a different reason kept being told the rule they had
        /// already learned. And the "incumbent wins" branch ASSIGNED rather than added (run of 1
        /// then run of 5 stored 5, not 6), so the number being compared was not the total it
        /// claimed to be. Both were invisible: the comment above it said "decided over the
        /// LIFETIME", which is what this now is. (v1.32 pre-submission review.)
        public var patternCounts: [String: Int]

        public init(kana: String, refusals: Int, runs: Int, lastSeen: Date,
                    patternCounts: [String: Int]) {
            self.kana = kana
            self.refusals = refusals
            self.runs = runs
            self.lastSeen = lastSeen
            self.patternCounts = patternCounts
        }

        /// The pattern that explains the most refusals on this kana, over its whole history.
        ///
        /// Ties break by raw value, ascending — deterministic, so the screen does not reshuffle
        /// between launches on equal evidence. `.unknown` when nothing has been recorded.
        public var dominantPattern: String {
            patternCounts.max { a, b in (a.value, b.key) < (b.value, a.key) }?.key
                ?? TypingPattern.unknown.rawValue
        }

        /// How many refusals the dominant pattern explains.
        public var dominantCount: Int { patternCounts[dominantPattern] ?? 0 }

        public var pattern: TypingPattern { TypingPattern(rawValue: dominantPattern) ?? .unknown }
    }

    /// How many kana the ledger will track. Chosen well above the syllabary so it is a backstop
    /// rather than a working limit — if it ever binds, something is wrong with the key, not with
    /// the learner.
    public static let capacity = 400

    public private(set) var entries: [String: Entry]
    /// How many entries the last decode had to drop. Zero for a ledger built in memory.
    /// Reported by the loader, not acted on — the surviving entries are still correct.
    public private(set) var skippedOnLoad: Int = 0
    /// Kana the cap refused to start tracking. Counted, never silently dropped: a ledger that
    /// quietly stopped recording would look exactly like a learner who stopped making mistakes.
    public private(set) var droppedKana: Int
    /// How many runs have been folded in. The denominator for "in 9 of your last 20 runs", and
    /// the thing that makes a `runs` count readable.
    public private(set) var runsRecorded: Int

    public init(entries: [String: Entry] = [:], droppedKana: Int = 0, runsRecorded: Int = 0) {
        self.entries = entries
        self.droppedKana = droppedKana
        self.runsRecorded = runsRecorded
    }

    // Element-lossy decode, the same reason every other store in this repo has one: a single
    // malformed entry must not take the whole ledger with it. Unlike the review stores this one
    // is derived data and could be rebuilt from nothing — but "could be rebuilt" means "the
    // learner loses their history", which is the thing it exists to accumulate.
    //
    // The first version of this file said exactly the paragraph above and then decoded
    // `[String: Entry]` whole, which is all-or-nothing: `Entry`'s six fields are synthesized and
    // required, so one lost field threw for the entire dictionary and `load` swallowed it into an
    // empty ledger. A guard stated in prose that nothing enforces is this project's second
    // signature defect, and that one was in the store's own decoder. `lossyDictionary` is what
    // the sentence claimed; `EntryLossyDecodeTests` is what keeps the claim honest.
    private enum CodingKeys: String, CodingKey { case entries, droppedKana, runsRecorded }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        (entries, skippedOnLoad) = try LossyLoad.lossyDictionary(Entry.self, from: c, forKey: .entries)
        droppedKana = try c.decodeIfPresent(Int.self, forKey: .droppedKana) ?? 0
        runsRecorded = try c.decodeIfPresent(Int.self, forKey: .runsRecorded) ?? 0
    }

    // `entries` is no longer optional-tolerant at the key level, so an old file that predates the
    // key (there is none — v1.32 is the first) or a hand-edited one missing it must still load.
    // `lossyDictionary` requires the key; this keeps the encoder always writing it.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(entries, forKey: .entries)
        try c.encode(droppedKana, forKey: .droppedKana)
        try c.encode(runsRecorded, forKey: .runsRecorded)
    }

    // MARK: Folding a run in

    /// Folds one run's refusals into the ledger.
    ///
    /// **Called once per run and not once per event**, which is what makes `runs` mean what it
    /// says: every kana touched by this trace has its `runs` incremented by exactly one, however
    /// many times it was refused. Calling this twice for one run would inflate the field the whole
    /// type is built on.
    ///
    /// `now` is injected rather than read, because a test that cannot control the clock has to
    /// assert on something other than what it is trying to check.
    public mutating func fold(_ trace: MistakeTrace, now: Date = Date()) {
        guard !trace.isEmpty else { return }
        runsRecorded += 1

        // Group this run's events by kana first, so `runs` is incremented once per kana and the
        // dominant pattern is decided over the whole run rather than by whichever event landed
        // last.
        var perKana: [String: (refusals: Int, patterns: [TypingPattern: Int])] = [:]
        for event in trace.events {
            guard let kana = event.kanaAtMistake else { continue }
            let key = String(kana)
            var bucket = perKana[key] ?? (0, [:])
            bucket.refusals += 1
            bucket.patterns[TypingDiagnostics.classify(event), default: 0] += 1
            perKana[key] = bucket
        }

        for (kana, bucket) in perKana {
            // Every pattern this run saw is banked, not just the run's winner. `dominantPattern`
            // then reads the lifetime maximum, which is what this type has always claimed to
            // report — see `Entry.patternCounts` for what it used to do instead.
            let counts = bucket.patterns.reduce(into: [String: Int]()) { $0[$1.key.rawValue] = $1.value }
            if var existing = entries[kana] {
                existing.refusals += bucket.refusals
                existing.runs += 1
                existing.lastSeen = now
                for (pattern, n) in counts { existing.patternCounts[pattern, default: 0] += n }
                entries[kana] = existing
            } else if entries.count < Self.capacity {
                entries[kana] = Entry(kana: kana, refusals: bucket.refusals, runs: 1,
                                      lastSeen: now, patternCounts: counts)
            } else {
                droppedKana += 1
            }
        }
    }

    // MARK: Reading it back

    /// The kana worth telling the learner about, worst first.
    ///
    /// - Parameter minimumRuns: how many separate runs a kana must appear in before it counts as
    ///   a habit rather than a bad minute. **Required, with no default**, for the reason v1.24 §C
    ///   removed every `resolves:` default: a threshold that can be omitted is a threshold that
    ///   will be, and a caller that forgets it gets "everything you have ever mistyped" while
    ///   believing it asked for "what you keep missing".
    /// - Parameter limit: applied AFTER the filter, never before. Filtering after a cap is the
    ///   v1.23 weak-words bug verbatim — there the cap was taken first and the leeches sorted to
    ///   the front, so fifteen were promised and twelve ridden.
    public func habits(minimumRuns: Int, limit: Int = 20) -> [Entry] {
        entries.values
            .filter { $0.runs >= minimumRuns }
            .sorted { a, b in
                if a.runs != b.runs { return a.runs > b.runs }
                if a.refusals != b.refusals { return a.refusals > b.refusals }
                return a.kana < b.kana          // deterministic, so the screen does not reshuffle
            }
            .prefix(limit)
            .map { $0 }
    }

    /// The patterns behind the habits, worst first — the bridge to the coach, which drills a
    /// PATTERN rather than a kana.
    ///
    /// Built from `habits` rather than from `entries`, so the list the learner reads and the list
    /// this summarises cannot describe different populations. That is the one property this
    /// project has broken more than twenty times.
    public func dominantPatterns(minimumRuns: Int, limit: Int = 20) -> [(pattern: TypingPattern, kana: [String])] {
        var grouped: [TypingPattern: [String]] = [:]
        for entry in habits(minimumRuns: minimumRuns, limit: limit) {
            grouped[entry.pattern, default: []].append(entry.kana)
        }
        return grouped
            .map { (pattern: $0.key, kana: $0.value) }
            .sorted { a, b in
                if a.kana.count != b.kana.count { return a.kana.count > b.kana.count }
                return a.pattern.rawValue < b.pattern.rawValue
            }
    }

    // MARK: Persistence

    public func save(to url: URL) throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
    }

    /// Loads the ledger and says what happened, so a caller that can WRITE it back can refuse to.
    ///
    /// The shape every other store here has, and it did not used to: this file loaded with the
    /// `try? Data` / `try? decode` block quoted at the top of `LossyLoad` as the defect that
    /// module exists to delete. Its third failure is the one that mattered here — **it cannot
    /// tell "unreadable" from "undecodable"**, so a ledger the process momentarily could not READ
    /// (file protection while the device is still unlocking, a busy volume, an iCloud-backed home
    /// directory on macOS) came back empty and the very next finished ride wrote that emptiness
    /// over bytes that were probably intact. The trade recorded in `AppModel.init` — "a corrupt
    /// ledger degrades to an empty one … quarantining it and refusing to write would cost more
    /// than it protects" — is a fair trade for `.undecodable` and a bad one for `.unreadable`,
    /// where the cost of refusing to write is one session's stumbles and the cost of writing is
    /// the learner's whole history.
    public static func loadReporting(from url: URL) -> (ledger: StumbleLedger, outcome: LossyLoad.Outcome) {
        let (decoded, outcome) = LossyLoad.load(StumbleLedger.self, from: url)
        let ledger = decoded ?? StumbleLedger()
        if ledger.skippedOnLoad > 0 {
            return (ledger, .loadedWithSkips(skipped: ledger.skippedOnLoad))
        }
        return (ledger, outcome)
    }

    public static func load(from url: URL) -> StumbleLedger { loadReporting(from: url).ledger }
}
