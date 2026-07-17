import Testing
import Foundation
@testable import ReviewKit

private let tokyo: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    return calendar
}()

/// 2026-06-01 12:00 JST.
private let noon: Date = {
    var components = DateComponents()
    components.year = 2026; components.month = 6; components.day = 1
    components.hour = 12
    return tokyo.date(from: components)!
}()

@Suite("Due forecast")
struct DueForecastTests {

    private func store(dueOffsets hours: [Double]) -> ReviewStore {
        var store = ReviewStore()
        for (index, offset) in hours.enumerated() {
            var card = SRSCard(id: "w\(index)", createdAt: noon.addingTimeInterval(-86_400))
            card.dueDate = noon.addingTimeInterval(offset * 3600)
            store = withCard(store, card)
        }
        return store
    }

    /// ReviewStore has no public card setter; rebuild through Codable.
    private func withCard(_ store: ReviewStore, _ card: SRSCard) -> ReviewStore {
        var cards = store.cards
        cards[card.id] = card
        return ReviewStore(cards: cards)
    }

    @Test("overdue and later-today cards land in the today bucket")
    func todayBucket() {
        // -24h overdue, -1h overdue, +6h this evening (18:00), +20h → tomorrow 08:00
        let forecast = store(dueOffsets: [-24, -1, 6, 20]).dueForecast(asOf: noon, calendar: tokyo)
        #expect(forecast.today == 3)
        #expect(forecast.tomorrow == 1)
        #expect(forecast.thisWeek == 0)
    }

    @Test("tomorrow vs this-week boundaries")
    func weekBucket() {
        // +36h → tomorrow midnight area (day+1 24:00 = day+2 00:00? 12:00+36h = day+2 00:00 → thisWeek)
        // +30h → tomorrow 18:00; +72h → day+4 12:00 (thisWeek); +160h → day+7 04:00 (beyond)
        let forecast = store(dueOffsets: [30, 36, 72, 160]).dueForecast(asOf: noon, calendar: tokyo)
        #expect(forecast.tomorrow == 1)      // +30h
        #expect(forecast.thisWeek == 2)      // +36h, +72h
        #expect(forecast.today == 0)         // +160h falls outside every bucket
    }

    @Test("empty store forecasts zeros")
    func empty() {
        #expect(ReviewStore().dueForecast(asOf: noon, calendar: tokyo) == DueForecast())
    }
}

@Suite("Due-by-day histogram (widget)")
struct DueByDayTests {

    private func store(dueOffsets hours: [Double]) -> ReviewStore {
        var cards: [String: SRSCard] = [:]
        for (index, offset) in hours.enumerated() {
            var card = SRSCard(id: "w\(index)", createdAt: noon.addingTimeInterval(-86_400))
            card.dueDate = noon.addingTimeInterval(offset * 3600)
            cards[card.id] = card
        }
        return ReviewStore(cards: cards)
    }

    @Test("overdue and same-day both land in bucket 0")
    func overdueFoldsIntoToday() {
        // -48h and -1h overdue, +6h same evening → all bucket 0; +30h → bucket 1
        let h = store(dueOffsets: [-48, -1, 6, 30]).dueByDay(asOf: noon, horizon: 7, calendar: tokyo)
        #expect(h[0] == 3)
        #expect(h[1] == 1)
        #expect(h[2...].allSatisfy { $0 == 0 })
    }

    @Test("each calendar day gets its own bucket")
    func perDayBuckets() {
        // noon + 0h, +24h, +48h, +72h → buckets 0,1,2,3 (JST, no DST so hours map cleanly)
        let h = store(dueOffsets: [0, 24, 48, 72]).dueByDay(asOf: noon, horizon: 7, calendar: tokyo)
        #expect(Array(h[0...3]) == [1, 1, 1, 1])
        #expect(h[4...].allSatisfy { $0 == 0 })
    }

    @Test("cards at or beyond the horizon are omitted, not clamped into the last bucket")
    func horizonTruncates() {
        // horizon 3 (buckets 0,1,2); a card +72h (day 3) must NOT appear
        let h = store(dueOffsets: [0, 72]).dueByDay(asOf: noon, horizon: 3, calendar: tokyo)
        #expect(h == [1, 0, 0])
    }

    @Test("horizon 1 collapses everything in-range to a single bucket")
    func horizonOne() {
        let h = store(dueOffsets: [-24, 6]).dueByDay(asOf: noon, horizon: 1, calendar: tokyo)
        #expect(h == [2])
    }

    @Test("crossing a DST spring-forward still counts whole calendar days")
    func dstSafe() {
        // US Pacific springs forward 2026-03-08 02:00. A day that is only 23 hours long
        // must still be one bucket, which a fixed +86400 would get wrong.
        var la = Calendar(identifier: .gregorian)
        la.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        var c = DateComponents(); c.year = 2026; c.month = 3; c.day = 7; c.hour = 12
        let mar7noon = la.date(from: c)!
        var store = ReviewStore()
        var cards: [String: SRSCard] = [:]
        // due Mar 7 (day 0), Mar 8 (day 1, the 23h day), Mar 9 (day 2)
        for (i, day) in [7, 8, 9].enumerated() {
            var cc = DateComponents(); cc.year = 2026; cc.month = 3; cc.day = day; cc.hour = 15
            var card = SRSCard(id: "d\(i)", createdAt: mar7noon.addingTimeInterval(-86_400))
            card.dueDate = la.date(from: cc)!
            cards[card.id] = card
        }
        store = ReviewStore(cards: cards)
        let h = store.dueByDay(asOf: mar7noon, horizon: 4, calendar: la)
        #expect(Array(h[0...2]) == [1, 1, 1], "the 23-hour DST day is still exactly one bucket")
    }

    @Test("empty store is all zeros")
    func empty() {
        #expect(ReviewStore().dueByDay(asOf: noon, horizon: 5, calendar: tokyo) == [0, 0, 0, 0, 0])
    }
}
