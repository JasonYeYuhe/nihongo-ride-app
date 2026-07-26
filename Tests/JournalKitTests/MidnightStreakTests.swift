import Testing
import Foundation
@testable import JournalKit

/// A ride is stored with the instant it ENDED. The streak counted only that day, so a rider
/// who started at 23:50 and finished at 00:02 got credit for the new day and none for the one
/// they actually rode most of — and if that was the tail of a six-day chain, the streak they
/// had kept every single day reset to 1.
@Suite("Streak — a ride counts for every day it spanned")
struct MidnightStreakTests {

    private var tokyo: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }

    private func day(_ d: Int, hour: Int = 12, minute: Int = 0) -> Date {
        tokyo.date(from: DateComponents(year: 2026, month: 3, day: d, hour: hour, minute: minute))!
    }

    private func ride(end: Date, duration: TimeInterval = 120) -> RideRecord {
        RideRecord(date: end, mode: "journey", level: "N5", score: 100, wpm: 40,
                   accuracy: 0.95, wordsCompleted: 10, lapsed: 0,
                   distanceMeters: 200, duration: duration)
    }

    @Test("a run that crosses midnight keeps the chain it belongs to")
    func crossesMidnight() {
        // Ridden on the 1st through the 6th, then a session begun 23:50 on the 7th that
        // finished 00:02 on the 8th. As of the 8th that is eight consecutive ridden days.
        var records = (1...6).map { ride(end: day($0)) }
        records.append(ride(end: day(8, hour: 0, minute: 2), duration: 12 * 60))

        let journal = RideJournal(records: records)
        #expect(journal.streakDays(asOf: day(8), calendar: tokyo) == 8,
                "got \(journal.streakDays(asOf: day(8), calendar: tokyo))")
    }

    @Test("without the crossing ride the chain really does break")
    func controlCase() {
        // The same six days, and a ride on the 8th that did NOT span the 7th. The 7th was
        // genuinely missed, so the streak is 1 — the fix must not paper over a real gap.
        var records = (1...6).map { ride(end: day($0)) }
        records.append(ride(end: day(8, hour: 0, minute: 2), duration: 60))

        let journal = RideJournal(records: records)
        #expect(journal.streakDays(asOf: day(8), calendar: tokyo) == 1)
    }

    @Test("a duration cannot invent days the rider was not there for")
    func spansOnlyOneExtraDay() {
        // Only the start day is added, never a range: a stored duration is at most one
        // session, and treating a corrupt or absurd duration as a span of days would
        // manufacture a streak. A single 40-hour duration adds its start day and nothing in
        // between, so the chain stays broken.
        let records = [ride(end: day(8, hour: 12), duration: 40 * 3600)]
        let journal = RideJournal(records: records)
        // Start day is the 6th at 20:00; the 7th was never ridden, so as of the 8th the
        // streak is just the 8th.
        #expect(journal.streakDays(asOf: day(8), calendar: tokyo) == 1)
    }

    @Test("a zero duration behaves exactly as before")
    func zeroDuration() {
        // Records written before `duration` existed decode it as 0 (v1.15 §B). They must
        // count for their end day only, with no phantom extra day.
        let records = (1...3).map { ride(end: day($0), duration: 0) }
        let journal = RideJournal(records: records)
        #expect(journal.streakDays(asOf: day(3), calendar: tokyo) == 3)
    }

    @Test("the same-day case is unchanged")
    func ordinaryDays() {
        let records = (1...5).map { ride(end: day($0)) }
        let journal = RideJournal(records: records)
        #expect(journal.streakDays(asOf: day(5), calendar: tokyo) == 5)
        #expect(journal.streakDays(asOf: day(6), calendar: tokyo) == 5, "yesterday still counts")
        #expect(journal.streakDays(asOf: day(7), calendar: tokyo) == 0, "two days off ends it")
    }
}
