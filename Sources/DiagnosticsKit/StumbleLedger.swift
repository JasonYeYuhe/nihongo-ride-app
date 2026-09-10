import Foundation
import RomajiKana

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
/// local file, in Application Support, beside the review stores, and it leaves the device only if
/// the learner exports it themselves.
///
/// # Bounds
///
/// Keyed by kana, so the key space is the syllabary — a few hundred at most, and it cannot grow
/// with the corpus the way an entry-id key would (7,071 and rising). `capacity` is a second belt:
/// a corpus edit that introduced an unexpected character class cannot make this file grow without
/// limit, and what was dropped is COUNTED rather than silently discarded, the same way
/// `MistakeTrace.dropped` handles its own cap.
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
        /// The pattern that explains the most refusals on this kana, and how many it explains.
        /// Stored rather than recomputed because the raw events are not kept — the whole point
        /// of the ledger is that it is a summary, not a log.
        public var dominantPattern: String
        public var dominantCount: Int

        public init(kana: String, refusals: Int, runs: Int, lastSeen: Date,
                    dominantPattern: String, dominantCount: Int) {
            self.kana = kana
            self.refusals = refusals
            self.runs = runs
            self.lastSeen = lastSeen
            self.dominantPattern = dominantPattern
            self.dominantCount = dominantCount
        }

        public var pattern: TypingPattern { TypingPattern(rawValue: dominantPattern) ?? .unknown }
    }

    /// How many kana the ledger will track. Chosen well above the syllabary so it is a backstop
    /// rather than a working limit — if it ever binds, something is wrong with the key, not with
    /// the learner.
    public static let capacity = 400

    public private(set) var entries: [String: Entry]
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
    private enum CodingKeys: String, CodingKey { case entries, droppedKana, runsRecorded }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decodeIfPresent([String: Entry].self, forKey: .entries) ?? [:]
        entries = raw
        droppedKana = try c.decodeIfPresent(Int.self, forKey: .droppedKana) ?? 0
        runsRecorded = try c.decodeIfPresent(Int.self, forKey: .runsRecorded) ?? 0
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
            let (pattern, count) = bucket.patterns
                .max { a, b in (a.value, a.key.rawValue) < (b.value, b.key.rawValue) }
                ?? (.unknown, 0)
            if var existing = entries[kana] {
                existing.refusals += bucket.refusals
                existing.runs += 1
                existing.lastSeen = now
                // The dominant pattern is decided over the LIFETIME, not by the latest run, so a
                // single odd sitting cannot relabel a long-standing habit. Ties keep the
                // incumbent, which makes the field stable rather than flapping.
                if count > existing.dominantCount {
                    existing.dominantPattern = pattern.rawValue
                    existing.dominantCount = count
                } else if existing.dominantPattern == pattern.rawValue {
                    existing.dominantCount += count
                }
                entries[kana] = existing
            } else if entries.count < Self.capacity {
                entries[kana] = Entry(kana: kana, refusals: bucket.refusals, runs: 1,
                                      lastSeen: now, dominantPattern: pattern.rawValue,
                                      dominantCount: count)
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

    public static func load(from url: URL) -> StumbleLedger {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(StumbleLedger.self, from: data)
        else { return StumbleLedger() }
        return decoded
    }
}
