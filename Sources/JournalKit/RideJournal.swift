import Foundation

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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let stored = try container.decode([RideRecord].self, forKey: .records)
        records = stored
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

    // MARK: Persistence

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }

    public static func load(from url: URL) -> RideJournal {
        guard let data = try? Data(contentsOf: url) else { return RideJournal() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(RideJournal.self, from: data)) ?? RideJournal()
    }
}
