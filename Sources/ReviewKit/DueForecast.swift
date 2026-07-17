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
    /// Absolute-calendar-day due histogram for the home-screen widget (v1.11).
    ///
    /// `result[i]` is the number of cards whose due date falls on the calendar day
    /// `i` days after `date`'s day. `result[0]` also absorbs everything **overdue**
    /// (a card past due is due today), and cards due `horizon` or more days out are
    /// omitted entirely — the widget does not warn about cards two weeks away.
    ///
    /// Why a histogram and not `dueForecast`: the widget's timeline advances past
    /// midnight while the app is not running, so a relative "today/tomorrow" count
    /// would be stale by the next day with no app to recompute it. An absolute-day
    /// histogram lets the widget read bucket `k` on the k-th day itself; it shows
    /// `sum(result[0...k])` — cards accumulated as due since the app was last open
    /// (opening it rewrites the snapshot).
    ///
    /// DST-safe: day offsets come from `dateComponents([.day])` between start-of-day
    /// values, never `+86400`.
    public func dueByDay(asOf date: Date = Date(), horizon: Int, calendar: Calendar = .current) -> [Int] {
        precondition(horizon > 0, "horizon must be positive")
        let start = calendar.startOfDay(for: date)
        var hist = [Int](repeating: 0, count: horizon)
        for card in cards.values {
            let cardDay = calendar.startOfDay(for: card.dueDate)
            guard let off = calendar.dateComponents([.day], from: start, to: cardDay).day else { continue }
            let bucket = max(0, off)        // overdue (off < 0) counts as due today
            if bucket < horizon { hist[bucket] += 1 }
        }
        return hist
    }

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
