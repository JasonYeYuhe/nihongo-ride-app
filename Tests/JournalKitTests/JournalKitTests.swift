import Testing
import Foundation
@testable import JournalKit

/// A fixed calendar so streak math is independent of the machine's locale.
private let tokyo: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    return calendar
}()

/// 2026-06-01 12:00 JST as a stable anchor.
private let anchor: Date = {
    var components = DateComponents()
    components.year = 2026; components.month = 6; components.day = 1
    components.hour = 12
    return tokyo.date(from: components)!
}()

private func at(day: Int, hour: Int, minute: Int = 0) -> Date {
    var components = tokyo.dateComponents([.year, .month], from: anchor)
    components.day = day; components.hour = hour; components.minute = minute
    return tokyo.date(from: components)!
}

private func ride(on date: Date, wpm: Double = 28, words: Int = 12,
                  distance: Double = 240, mode: String = "journey") -> RideRecord {
    RideRecord(date: date, mode: mode, level: "N5", score: 100, wpm: wpm,
               accuracy: 0.95, wordsCompleted: words, lapsed: 1,
               distanceMeters: distance, duration: 180)
}

@Suite("Ride journal")
struct RideJournalTests {

    @Test("append keeps chronological order; recent() returns newest first")
    func appendAndRecent() {
        var journal = RideJournal()
        journal.append(ride(on: at(day: 1, hour: 9)))
        journal.append(ride(on: at(day: 2, hour: 9)))
        journal.append(ride(on: at(day: 3, hour: 9)))
        #expect(journal.count == 3)
        let recent = journal.recent(2)
        #expect(recent.count == 2)
        #expect(recent[0].date == at(day: 3, hour: 9))
        #expect(recent[1].date == at(day: 2, hour: 9))
    }

    @Test("totals sum words and distance")
    func totals() {
        var journal = RideJournal()
        journal.append(ride(on: at(day: 1, hour: 9), words: 10, distance: 200))
        journal.append(ride(on: at(day: 1, hour: 20), words: 15, distance: 300))
        #expect(journal.totalWords == 25)
        #expect(journal.totalDistanceMeters == 500)
        #expect(journal.totalRuns == 2)
    }

    // MARK: Streak

    @Test("empty journal has streak 0")
    func emptyStreak() {
        #expect(RideJournal().streakDays(asOf: anchor, calendar: tokyo) == 0)
    }

    @Test("rides on 3 consecutive days, asked on the 3rd → 3")
    func basicStreak() {
        var journal = RideJournal()
        journal.append(ride(on: at(day: 1, hour: 8)))
        journal.append(ride(on: at(day: 2, hour: 22)))
        journal.append(ride(on: at(day: 3, hour: 7)))
        #expect(journal.streakDays(asOf: at(day: 3, hour: 12), calendar: tokyo) == 3)
    }

    @Test("a ride at 23:50 and the next at 00:10 are two different streak days")
    func midnightCrossing() {
        var journal = RideJournal()
        journal.append(ride(on: at(day: 1, hour: 23, minute: 50)))
        journal.append(ride(on: at(day: 2, hour: 0, minute: 10)))
        #expect(journal.streakDays(asOf: at(day: 2, hour: 0, minute: 30), calendar: tokyo) == 2)
    }

    @Test("multiple rides in one day count once")
    func sameDayOnce() {
        var journal = RideJournal()
        journal.append(ride(on: at(day: 1, hour: 8)))
        journal.append(ride(on: at(day: 1, hour: 9)))
        journal.append(ride(on: at(day: 1, hour: 21)))
        #expect(journal.streakDays(asOf: at(day: 1, hour: 22), calendar: tokyo) == 1)
    }

    @Test("a quiet today doesn't break yesterday's streak")
    func quietTodayKeepsStreak() {
        var journal = RideJournal()
        journal.append(ride(on: at(day: 1, hour: 8)))
        journal.append(ride(on: at(day: 2, hour: 8)))
        // No ride yet on day 3, asked the morning of day 3.
        #expect(journal.streakDays(asOf: at(day: 3, hour: 9), calendar: tokyo) == 2)
    }

    @Test("a full missed day breaks the streak")
    func gapBreaksStreak() {
        var journal = RideJournal()
        journal.append(ride(on: at(day: 1, hour: 8)))
        journal.append(ride(on: at(day: 2, hour: 8)))
        // Day 3 fully skipped; ask on day 4 before riding.
        #expect(journal.streakDays(asOf: at(day: 4, hour: 9), calendar: tokyo) == 0)
        // After riding on day 4 the streak restarts at 1.
        journal.append(ride(on: at(day: 4, hour: 10)))
        #expect(journal.streakDays(asOf: at(day: 4, hour: 11), calendar: tokyo) == 1)
    }

    @Test("gap further back limits the streak to the recent chain")
    func oldGap() {
        var journal = RideJournal()
        journal.append(ride(on: at(day: 1, hour: 8)))
        // day 2 skipped
        journal.append(ride(on: at(day: 3, hour: 8)))
        journal.append(ride(on: at(day: 4, hour: 8)))
        #expect(journal.streakDays(asOf: at(day: 4, hour: 12), calendar: tokyo) == 2)
    }

    // MARK: Trend

    @Test("wpmSeries is chronological, skips zero-WPM runs, and caps length")
    func wpmSeries() {
        var journal = RideJournal()
        journal.append(ride(on: at(day: 1, hour: 8), wpm: 20))
        journal.append(ride(on: at(day: 1, hour: 9), wpm: 0))      // too-short run
        journal.append(ride(on: at(day: 2, hour: 8), wpm: 24))
        journal.append(ride(on: at(day: 3, hour: 8), wpm: 30))
        #expect(journal.wpmSeries(last: 10) == [20, 24, 30])
        #expect(journal.wpmSeries(last: 2) == [24, 30])
        #expect(journal.bestWPM == 30)
    }

    @Test("bestWPM is nil when no run has a meaningful WPM")
    func bestWPMNil() {
        var journal = RideJournal()
        #expect(journal.bestWPM == nil)
        journal.append(ride(on: at(day: 1, hour: 8), wpm: 0))
        #expect(journal.bestWPM == nil)
    }

    @Test("storage caps at maxStoredRecords but the odometer keeps counting")
    func capAndLifetime() {
        var journal = RideJournal()
        let cap = RideJournal.maxStoredRecords
        for index in 0..<(cap + 25) {
            journal.append(ride(on: anchor.addingTimeInterval(Double(index) * 60),
                                words: 1, distance: 10))
        }
        #expect(journal.count == cap)
        #expect(journal.totalRuns == cap + 25)
        #expect(journal.totalWords == cap + 25)
        #expect(journal.totalDistanceMeters == Double((cap + 25) * 10))
        // Oldest got trimmed: first stored record is run #25.
        #expect(journal.records.first?.date == anchor.addingTimeInterval(25 * 60))
    }

    @Test("lifetime counters survive a save/load round-trip and trimming")
    func lifetimePersistence() throws {
        var journal = RideJournal()
        journal.append(ride(on: at(day: 1, hour: 9), words: 7, distance: 70))
        journal.append(ride(on: at(day: 2, hour: 9), words: 8, distance: 80))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("journal-lifetime-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try journal.save(to: url)
        let loaded = RideJournal.load(from: url)
        #expect(loaded.totalWords == 15)
        #expect(loaded.totalRuns == 2)
        #expect(loaded.totalDistanceMeters == 150)
    }

    @Test("a legacy file without lifetime keys recomputes them from records")
    func legacyDecode() throws {
        var journal = RideJournal()
        journal.append(ride(on: at(day: 1, hour: 9), words: 5, distance: 50))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // Strip the lifetime keys to simulate the pre-counter schema.
        var object = try JSONSerialization.jsonObject(
            with: encoder.encode(journal)) as! [String: Any]
        object.removeValue(forKey: "lifetimeWords")
        object.removeValue(forKey: "lifetimeDistanceMeters")
        object.removeValue(forKey: "lifetimeRuns")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("journal-legacy-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try JSONSerialization.data(withJSONObject: object).write(to: url)

        let loaded = RideJournal.load(from: url)
        #expect(loaded.totalWords == 5)
        #expect(loaded.totalRuns == 1)
        #expect(loaded.totalDistanceMeters == 50)
        #expect(loaded.records.count == 1)
    }

    // MARK: Persistence

    @Test("save/load round-trips every field")
    func persistence() throws {
        var journal = RideJournal()
        journal.append(ride(on: at(day: 1, hour: 23, minute: 50), mode: "timeAttack"))
        journal.append(ride(on: at(day: 2, hour: 7), mode: "practice"))

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("journal-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        try journal.save(to: url)
        let loaded = RideJournal.load(from: url)
        #expect(loaded.records == journal.records)
    }

    @Test("load from a missing or corrupt file yields an empty journal")
    func loadFallback() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("nope-\(UUID().uuidString).json")
        #expect(RideJournal.load(from: missing).isEmpty)

        let corrupt = FileManager.default.temporaryDirectory
            .appendingPathComponent("corrupt-\(UUID().uuidString).json")
        try Data("not json".utf8).write(to: corrupt)
        defer { try? FileManager.default.removeItem(at: corrupt) }
        #expect(RideJournal.load(from: corrupt).isEmpty)
    }
}

@Suite("Ride journal — stats aggregations (v1.9 §B)")
struct StatsAggregationTests {

    @Test("dailyWords zero-fills empty days and sums words within a day")
    func dailyWords() {
        var j = RideJournal()
        j.append(ride(on: at(day: 10, hour: 9), words: 12))
        j.append(ride(on: at(day: 10, hour: 20), words: 8))   // same day → summed
        j.append(ride(on: at(day: 12, hour: 9), words: 5))
        // as of day 12, last 5 days = days 8,9,10,11,12
        let series = j.dailyWords(days: 5, asOf: at(day: 12, hour: 23), calendar: tokyo)
        #expect(series.count == 5)
        #expect(series.map(\.words) == [0, 0, 20, 0, 5])   // day10=20 (12+8), day12=5, rest 0
    }

    @Test("accuracySeries excludes zero-word runs and keeps chronological order")
    func accuracySeries() {
        var j = RideJournal()
        j.append(ride(on: at(day: 1, hour: 9), words: 12))
        j.append(RideRecord(date: at(day: 2, hour: 9), mode: "journey", level: "N5", score: 0,
                            wpm: 0, accuracy: 0, wordsCompleted: 0, lapsed: 0, distanceMeters: 0, duration: 0))
        j.append(ride(on: at(day: 3, hour: 9), words: 8))
        let s = j.accuracySeries()
        #expect(s.count == 2)                       // the zero-word run is dropped
        #expect(s.map(\.date) == [at(day: 1, hour: 9), at(day: 3, hour: 9)])
    }

    @Test("runsByMode counts per mode, most-run first")
    func runsByMode() {
        var j = RideJournal()
        for _ in 0..<3 { j.append(ride(on: at(day: 1, hour: 9), mode: "journey")) }
        j.append(ride(on: at(day: 1, hour: 9), mode: "practice"))
        j.append(ride(on: at(day: 1, hour: 9), mode: "timeAttack"))
        let m = j.runsByMode()
        #expect(m.first?.mode == "journey")
        #expect(m.first?.runs == 3)
        #expect(m.count == 3)
    }

    @Test("empty journal aggregations don't crash")
    func emptyAggregations() {
        let j = RideJournal()
        #expect(j.dailyWords(days: 7).allSatisfy { $0.words == 0 })
        #expect(j.accuracySeries().isEmpty)
        #expect(j.runsByMode().isEmpty)
    }
}
