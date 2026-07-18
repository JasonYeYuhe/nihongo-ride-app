import Foundation

/// The single derived snapshot the app writes to the shared App Group container and
/// the widget extensions read (v1.11). The widget is READ-ONLY: it never touches the
/// seven real stores, only this DTO. So a widget refresh can't corrupt anything, and
/// the well-known store/UserDefaults migration hazard (the double-odometer trap) never
/// enters the widget picture at all.
///
/// Everything here is a plain value: `Codable` for the JSON on disk, `Sendable` so it
/// crosses the app↔extension process boundary cleanly.
public struct WidgetSnapshot: Codable, Sendable, Equatable {
    /// Bumped when the shape changes. A widget built against an older shape reads this
    /// first and falls back to a placeholder rather than mis-rendering newer data.
    public static let currentSchema = 1

    public var schemaVersion: Int
    /// When the app wrote this. The widget uses it both to place the due histogram on
    /// the calendar and to decide the snapshot is too stale to trust.
    public var generatedAt: Date
    /// Absolute-calendar-day due histogram for vocabulary review. `dueByDay[i]` = cards
    /// coming due on the i-th day after `generatedAt`'s day; index 0 absorbs overdue.
    /// See `ReviewStore.dueByDay`.
    public var vocabDueByDay: [Int]
    /// Same, for the separate conjugation review store.
    public var conjugationDueByDay: [Int]
    public var streakDays: Int
    public var lifetimeWords: Int
    /// The app's UI language at write time ("en" / "zh") so the widget matches the app
    /// instead of the system locale — the user picks the language in-app, and the whole
    /// app + share card are bilingual, so the widget must be too.
    public var languageCode: String

    public init(
        schemaVersion: Int = WidgetSnapshot.currentSchema,
        generatedAt: Date,
        vocabDueByDay: [Int],
        conjugationDueByDay: [Int],
        streakDays: Int,
        lifetimeWords: Int,
        languageCode: String = "en"
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.vocabDueByDay = vocabDueByDay
        self.conjugationDueByDay = conjugationDueByDay
        self.streakDays = streakDays
        self.lifetimeWords = lifetimeWords
        self.languageCode = languageCode
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, generatedAt, vocabDueByDay, conjugationDueByDay
        case streakDays, lifetimeWords, languageCode
    }

    /// Tolerant decode (matching WordList/RideJournal): a field the writer omitted falls
    /// back to a sane default rather than failing the whole read → placeholder. App and
    /// widget ship together, so this only matters across an upgrade race, but the cost is
    /// nil and the codebase decodes defensively everywhere.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = (try? c.decode(Int.self, forKey: .schemaVersion)) ?? WidgetSnapshot.currentSchema
        generatedAt = (try? c.decode(Date.self, forKey: .generatedAt)) ?? Date(timeIntervalSince1970: 0)
        vocabDueByDay = (try? c.decode([Int].self, forKey: .vocabDueByDay)) ?? []
        conjugationDueByDay = (try? c.decode([Int].self, forKey: .conjugationDueByDay)) ?? []
        streakDays = (try? c.decode(Int.self, forKey: .streakDays)) ?? 0
        lifetimeWords = (try? c.decode(Int.self, forKey: .lifetimeWords)) ?? 0
        languageCode = (try? c.decode(String.self, forKey: .languageCode)) ?? "en"
    }
}

extension WidgetSnapshot {
    /// The horizon the app builds its histograms with. 14 days: the JSON cost of 14
    /// Ints is nil, and the widget's timeline never needs to look further ahead than
    /// the user reasonably would.
    public static let horizon = 14

    /// Vocabulary cards the user should see as due on the calendar day `dayOffset` days
    /// after `generatedAt` — the **accumulation** of every bucket up to and including
    /// that day, NOT bucket `dayOffset` alone.
    ///
    /// Why accumulate: a card in the histogram was not yet due when the snapshot was
    /// written (overdue cards were folded into bucket 0). Once it comes due it stays due
    /// until the user reviews it — and reviewing rewrites the snapshot. So on day `k`,
    /// "cards due since the app was last open" is exactly `sum(buckets 0...k)`.
    ///
    /// `dayOffset` past the horizon clamps to the full sum (the widget then also knows,
    /// via `isStale`, to nudge the user to open the app). Negative clamps to bucket 0.
    public func vocabDue(onDayOffset dayOffset: Int) -> Int {
        Self.accumulate(vocabDueByDay, throughDayOffset: dayOffset)
    }

    public func conjugationDue(onDayOffset dayOffset: Int) -> Int {
        Self.accumulate(conjugationDueByDay, throughDayOffset: dayOffset)
    }

    /// The due counts to show at a wall-clock `date` — the timeline provider's entry
    /// dates are calendar days, and this maps one to the histogram offset from
    /// `generatedAt`. Keeps the provider thin and the date math under test.
    public func vocabDue(asOf date: Date, calendar: Calendar = .current) -> Int {
        vocabDue(onDayOffset: dayOffset(to: date, calendar: calendar))
    }

    public func conjugationDue(asOf date: Date, calendar: Calendar = .current) -> Int {
        conjugationDue(onDayOffset: dayOffset(to: date, calendar: calendar))
    }

    func dayOffset(to date: Date, calendar: Calendar) -> Int {
        let start = calendar.startOfDay(for: generatedAt)
        let target = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: start, to: target).day ?? 0
    }

    static func accumulate(_ histogram: [Int], throughDayOffset dayOffset: Int) -> Int {
        guard !histogram.isEmpty else { return 0 }
        let last = min(max(dayOffset, 0), histogram.count - 1)
        return histogram[0...last].reduce(0, +)
    }

    /// Whether `now` has advanced past the histogram the snapshot carries — i.e. the app
    /// hasn't run in `horizon` days and the widget can no longer place "today" on it.
    /// The widget shows the clamped total and a "open to refresh" hint.
    public func isStale(asOf now: Date, calendar: Calendar = .current) -> Bool {
        let start = calendar.startOfDay(for: generatedAt)
        let day = calendar.startOfDay(for: now)
        guard let off = calendar.dateComponents([.day], from: start, to: day).day else { return true }
        return off >= vocabDueByDay.count
    }
}
