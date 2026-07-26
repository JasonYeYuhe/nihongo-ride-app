import Foundation
import PersistKit

/// History of finished runs, plus the analytics the journal screen shows
/// (streak, totals, WPM trend). Value type with `Codable` persistence,
/// mirroring `ReviewStore`.
///
/// Storage is capped at `maxStoredRecords` (oldest trimmed) so the file and
/// its launch-time decode stay small forever; the lifetime odometer counters
/// survive trimming.
public struct RideJournal: Codable, Sendable {
    /// Chronological append order (oldest first), at most `maxStoredRecords`.
    public private(set) var records: [RideRecord]
    /// Odometer totals over every run ever logged, including trimmed ones.
    public private(set) var lifetimeWords: Int
    public private(set) var lifetimeDistanceMeters: Double
    public private(set) var lifetimeRuns: Int

    /// ~250 bytes/record → the file stays well under a megabyte. 2000 records
    /// also keeps over a year of daily history for the streak math.
    public static let maxStoredRecords = 2000

    public init(records: [RideRecord] = []) {
        self.records = records
        lifetimeWords = records.reduce(0) { $0 + $1.wordsCompleted }
        lifetimeDistanceMeters = records.reduce(0) { $0 + $1.distanceMeters }
        lifetimeRuns = records.count
    }

    // Tolerate files written before the lifetime counters existed by
    // recomputing them from the stored records.
    private enum CodingKeys: String, CodingKey {
        case records, lifetimeWords, lifetimeDistanceMeters, lifetimeRuns
    }

    /// How many records the last decode had to drop.
    public private(set) var skippedOnLoad: Int = 0

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Element-lossy: one unreadable row costs that row, not the whole history.
        // (v1.15 §B — see ReviewKit.SRSCard.)
        let (stored, skipped) = try LossyLoad.lossyArray(
            RideRecord.self, from: container, forKey: .records)
        skippedOnLoad = skipped
        records = stored
        // The stored counters are authoritative when present: they include rides already
        // trimmed by the 2000-record cap, which the surviving records cannot account for.
        lifetimeWords = try container.decodeIfPresent(Int.self, forKey: .lifetimeWords)
            ?? stored.reduce(0) { $0 + $1.wordsCompleted }
        lifetimeDistanceMeters = try container.decodeIfPresent(Double.self, forKey: .lifetimeDistanceMeters)
            ?? stored.reduce(0) { $0 + $1.distanceMeters }
        lifetimeRuns = try container.decodeIfPresent(Int.self, forKey: .lifetimeRuns)
            ?? stored.count
    }

    public var count: Int { records.count }
    public var isEmpty: Bool { records.isEmpty }

    public mutating func append(_ record: RideRecord) {
        records.append(record)
        lifetimeWords += record.wordsCompleted
        lifetimeDistanceMeters += record.distanceMeters
        lifetimeRuns += 1
        if records.count > Self.maxStoredRecords {
            records.removeFirst(records.count - Self.maxStoredRecords)
        }
    }

    // MARK: Analytics

    /// Newest-first slice for the "recent rides" list.
    public func recent(_ limit: Int = 10) -> [RideRecord] {
        Array(records.suffix(limit).reversed())
    }

    public var totalWords: Int { lifetimeWords }

    public var totalDistanceMeters: Double { lifetimeDistanceMeters }

    public var totalRuns: Int { lifetimeRuns }

    /// Consecutive calendar days with at least one ride, counting back from
    /// `date`'s day. A quiet "today" doesn't break the streak — it just isn't
    /// counted yet (the chain only breaks once a full day passes with no ride).
    public func streakDays(asOf date: Date = Date(), calendar: Calendar = .current) -> Int {
        guard !records.isEmpty else { return 0 }
        let days = Set(records.map { calendar.startOfDay(for: $0.date) })
        let today = calendar.startOfDay(for: date)

        var cursor: Date
        if days.contains(today) {
            cursor = today
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                  days.contains(yesterday) {
            cursor = yesterday
        } else {
            return 0
        }

        var streak = 0
        while days.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    /// Chronological WPM values of the last `limit` runs that have a
    /// meaningful WPM (> 0), for the trend sparkline.
    public func wpmSeries(last limit: Int = 20) -> [Double] {
        Array(records.lazy.map(\.wpm).filter { $0 > 0 }.suffix(limit))
    }

    /// Best (highest) recorded WPM, or nil with no meaningful runs yet.
    public var bestWPM: Double? {
        let best = records.lazy.map(\.wpm).max()
        return (best ?? 0) > 0 ? best : nil
    }

    // MARK: Stats aggregations (v1.9 §B — pure, for the Stats screen's charts)

    /// One point per calendar day for the last `days` days (oldest→newest), zero-filled so the
    /// bar chart shows empty days too. Value = words completed that day (summed across runs).
    public func dailyWords(days: Int = 14, asOf date: Date = Date(), calendar: Calendar = .current)
        -> [(day: Date, words: Int)] {
        let startToday = calendar.startOfDay(for: date)
        var byDay: [Date: Int] = [:]
        for r in records { byDay[calendar.startOfDay(for: r.date), default: 0] += r.wordsCompleted }
        return (0..<max(1, days)).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: startToday).map { ($0, byDay[$0] ?? 0) }
        }
    }

    /// The last `limit` runs that typed something, oldest→newest, as (date, accuracy) — for the
    /// accuracy-trend line. Zero-word runs (abandoned) are excluded so the line isn't dragged to 0.
    public func accuracySeries(last limit: Int = 20) -> [(date: Date, accuracy: Double)] {
        records.lazy.filter { $0.wordsCompleted > 0 }.suffix(limit).map { ($0.date, $0.accuracy) }
    }

    /// Run counts grouped by mode (journey / timeAttack / practice …), most-run first — for a
    /// mode-breakdown summary. (Conjugation drills don't log rides, so they never appear here.)
    public func runsByMode() -> [(mode: String, runs: Int)] {
        var counts: [String: Int] = [:]
        for r in records { counts[r.mode, default: 0] += 1 }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { ($0.key, $0.value) }
    }

    // MARK: Persistence

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }

    /// See ReviewKit.ReviewStore.loadReporting. (v1.15 §B.)
    public static func loadReporting(from url: URL) -> (journal: RideJournal, outcome: LossyLoad.Outcome) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let (decoded, outcome) = LossyLoad.load(RideJournal.self, from: url, decoder: decoder)
        let journal = decoded ?? RideJournal()
        if journal.skippedOnLoad > 0 {
            return (journal, .loadedWithSkips(skipped: journal.skippedOnLoad))
        }
        return (journal, outcome)
    }

    public static func load(from url: URL) -> RideJournal { loadReporting(from: url).journal }
}
