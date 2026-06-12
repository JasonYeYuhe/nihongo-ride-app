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
