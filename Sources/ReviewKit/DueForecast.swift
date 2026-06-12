import Foundation

/// How many cards come due in the near-term buckets the journal screen shows.
/// Buckets are disjoint: `today` includes anything already overdue, `tomorrow`
/// is tomorrow's calendar day, `thisWeek` is the five days after that.
public struct DueForecast: Sendable, Equatable {
    public var today: Int
    public var tomorrow: Int
    public var thisWeek: Int

    public init(today: Int = 0, tomorrow: Int = 0, thisWeek: Int = 0) {
        self.today = today
        self.tomorrow = tomorrow
        self.thisWeek = thisWeek
    }
}

extension ReviewStore {
    /// Buckets every card's due date relative to `date`'s calendar day.
    public func dueForecast(asOf date: Date = Date(), calendar: Calendar = .current) -> DueForecast {
        let startOfToday = calendar.startOfDay(for: date)
        guard let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday),
              let endOfTomorrow = calendar.date(byAdding: .day, value: 2, to: startOfToday),
              let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfToday)
        else { return DueForecast() }

        var forecast = DueForecast()
        for card in cards.values {
            if card.dueDate < endOfToday {
                forecast.today += 1
            } else if card.dueDate < endOfTomorrow {
                forecast.tomorrow += 1
            } else if card.dueDate < endOfWeek {
                forecast.thisWeek += 1
            }
        }
        return forecast
    }
}
