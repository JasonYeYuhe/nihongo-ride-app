import Foundation
import PersistKit

/// Holds conjugation SM-2 cards keyed by `sourceID#form`, answers "what's due", and
/// records drill outcomes. A **separate store from the flat `ReviewKit.ReviewStore`**
/// with its own file (`conjugation-review.json`) and its own CKRecord type — a
/// conjugation lapse must NEVER flow into the vocab journey due-queue (red line §1,
/// PLAN-V1.8). Value type with `Codable` persistence.
///
/// # Why every count here takes TWO predicates
///
/// `resolves:` answers *does this card's verb still exist* and has been required since v1.24 §C.
/// It is necessary and it is not sufficient, and the gap is not hypothetical arithmetic:
///
/// A card is keyed `sourceID#form`. The drill can only ride it if `GameCore` can build a
/// `ConjugationPrompt` from that pair — which needs the entry to exist (that is `resolves:`),
/// the token to name a `ConjugationForm`, **and the engine to be able to conjugate that entry's
/// reading into that form**. The last one reads the corpus's opaque `vc` field and a per-form
/// stem table, so a *corpus edit* can strand a card whose verb is still perfectly present.
/// `ConjugationSession.makeReview` skips such a pair and pads the run with a fresh prompt, whose
/// outcome is written against a different card id — so the stranded card is never graded, stays
/// maximally overdue, sorts first in every query here, and inflates the menu button, the widget,
/// the Stats forecast and the reminder body forever. That is this project's signature defect
/// (`STATE-2026-08-18.md`, twenty-odd instances) in its exact canonical shape: **the number shown
/// and the run produced computed by different predicates.**
///
/// So `rideable:` is required on every member that answers *how much work is outstanding*, and it
/// is the app's job to make it the SAME function `makeReview` skips with —
/// `ConjugationSession.reviewPrompt(entryID:formToken:vocab:languageCode:) != nil` — not a
/// re-derivation of it. Sharing the function is the property; agreeing by inspection is what
/// failed the previous twenty times.
///
/// **`reviewedCount` deliberately does NOT take it**, and the line is worth stating rather than
/// leaving to be re-litigated: it answers *how many forms have you practised*, which is a
/// historical fact. A stranded card WAS practised. Filtering it there would make a true number
/// false — the opposite error, and the one v1.24 §C's `sourceID`/`id` swap actually shipped
/// ("Forms practiced 0" forever). Work-remaining filters; history does not. (v1.32 §C1.)
public struct ConjugationReviewStore: Codable, Sendable, Equatable {
    public private(set) var cards: [String: ConjugationSRSCard]

    public init(cards: [String: ConjugationSRSCard] = [:]) {
        self.cards = cards
    }

    // Element-lossy decode — see ReviewKit.ReviewStore. (v1.15 §B.)
    private enum CodingKeys: String, CodingKey { case cards }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        (cards, skippedOnLoad) = try LossyLoad.lossyDictionary(
            ConjugationSRSCard.self, from: c, forKey: .cards)
    }

    /// How many cards the last decode had to drop.
    public private(set) var skippedOnLoad: Int = 0

    public var count: Int { cards.count }

    public func card(for promptID: String) -> ConjugationSRSCard? { cards[promptID] }

    /// Cards due **by the end of `date`'s calendar day**, soonest-first, capped at `limit`.
    ///
    /// Day granularity, mirroring `ReviewKit.ReviewStore.dueCards` — read that doc for why.
    /// The same split existed here: `dueForecast` (Stats, the widget) bucketed by calendar
    /// day while this compared instants, so the menu's "Review N due" button could sit
    /// hidden at 0 while Stats said cards were due today. (v1.12 §B.)
    /// - Parameter resolves: whether a card's VERB still exists in the vocabulary, given its
    ///   `sourceID`. Injected because this module is deliberately zero-dependency and cannot
    ///   see VocabKit — the same shape `ReviewKit` uses.
    ///
    ///   It is here for the reason v1.22 added it across the vocabulary side: a card whose
    ///   entry has been withdrawn can never be reviewed away, so it inflates every count it
    ///   appears in, forever. The v1.22 sweep fixed the vocabulary half and left this one,
    ///   which is half a fix — the app badge is `vocab + conjugation`, and 言う/ゆう, one of
    ///   the two entries v1.18 retired, is a VERB.
    ///   The filter is applied BEFORE `limit`, for the reason `weakestFormCards` records below.
    /// - Parameter rideable: whether a review could actually BUILD this card's prompt — see
    ///   ``ConjugationReviewStore`` for why `resolves:` is not enough on its own.
    public func dueCards(on date: Date = Date(), limit: Int = 100,
                         calendar: Calendar = .current,
                         resolves: (String) -> Bool,
                         rideable: (ConjugationSRSCard) -> Bool) -> [ConjugationSRSCard] {
        let cutoff = Self.dueCutoff(for: date, calendar: calendar)
        return cards.values
            .filter { $0.dueDate < cutoff && resolves($0.sourceID) && rideable($0) }
            .sorted { $0.dueDate < $1.dueDate }
            .prefix(limit)
            .map { $0 }
    }

    public func dueCount(on date: Date = Date(), calendar: Calendar = .current,
                         resolves: (String) -> Bool,
                         rideable: (ConjugationSRSCard) -> Bool) -> Int {
        let cutoff = Self.dueCutoff(for: date, calendar: calendar)
        return cards.values
            .filter { $0.dueDate < cutoff && resolves($0.sourceID) && rideable($0) }
            .count
    }

    /// Midnight ending `date`'s day (see `ReviewStore.dueCutoff`).
    static func dueCutoff(for date: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
    }

    /// Cards reviewed at least once (the pool weak-form weighting can rank).
    ///
    /// - Parameter resolves: see ``dueCards(on:limit:calendar:resolves:)``. Required rather
    ///   than defaulted, for the reason v1.24 §C removed every such default: omitting it
    ///   compiles clean and silently returns a number counted over cards whose verb no longer
    ///   exists. This one reached the Stats screen as "Forms practiced" while the vocabulary
    ///   side of the very same screen was already filtered — the two halves disagreed, which
    ///   is "a fix applied to one call site is not a fix" in its purest form.
    public func reviewedCount(resolves: (String) -> Bool) -> Int {
        cards.values.filter { $0.totalReviews > 0 && resolves($0.sourceID) }.count
    }

    /// Cards the learner keeps failing.
    ///
    /// - Parameter resolves: as above, and here it is not merely a count being inflated. A
    ///   leech is a promise of work: the Stats screen says "N tough forms" and the learner is
    ///   meant to be able to drill N down. A card whose verb has been withdrawn can never be
    ///   reviewed away, so it is a leech that no amount of practice can retire — and 言う/ゆう,
    ///   one of the two entries v1.18 retired, is a verb.
    /// - Parameter rideable: and here the argument for it is the same sentence one step on. A
    ///   card the engine can no longer build a prompt for is *also* a leech no amount of practice
    ///   can retire — the drill silently rides something else instead — so "N tough forms" would
    ///   promise work the learner cannot finish. Same promise, second mechanism.
    public func leeches(resolves: (String) -> Bool,
                        rideable: (ConjugationSRSCard) -> Bool) -> [ConjugationSRSCard] {
        cards.values.filter { $0.isLeech && resolves($0.sourceID) && rideable($0) }
            .sorted { $0.lapses > $1.lapses }
    }

    /// The user's weakest *reviewed* (verb, form) cards, worst-first, capped at `limit`.
    /// Ranking mirrors `ReviewStore.weakestCards`: leeches first, then lower ease, more
    /// lapses, higher mistake-rate; id breaks ties for determinism. Only cards with
    /// `totalReviews > 0`. **Pure read — never mutates the store** (weak-form weighting
    /// only ranks; SRS is written solely via ``record(promptID:outcome:on:)``).
    /// - Parameter resolves: applied BEFORE `limit`, exactly as in `ReviewStore.weakestCards`.
    ///   Capping first and filtering after is the v1.23 weak-words bug verbatim: this sort puts
    ///   leeches at the FRONT, and a withdrawn verb's card is a permanent leech, so the unusable
    ///   ids would occupy the first places of the cap and the drill would come back short.
    ///   Nothing calls this yet — which is why it is worth fixing now, while the shape is a
    ///   latent copy of a bug rather than a live one.
    /// - Parameter rideable: applied BEFORE `limit` for the same reason, and it matters more
    ///   here than anywhere: this sort puts leeches first, and a stranded card is a permanent
    ///   leech, so unbuildable ids would occupy the front of the cap.
    public func weakestFormCards(limit: Int = 100,
                                 resolves: (String) -> Bool,
                                 rideable: (ConjugationSRSCard) -> Bool) -> [ConjugationSRSCard] {
        cards.values
            .filter { $0.totalReviews > 0 && resolves($0.sourceID) && rideable($0) }
            .sorted { a, b in
                if a.isLeech != b.isLeech { return a.isLeech }
                if a.easeFactor != b.easeFactor { return a.easeFactor < b.easeFactor }
                if a.lapses != b.lapses { return a.lapses > b.lapses }
                let ra = Double(a.totalMistakes) / Double(max(1, a.totalReviews))
                let rb = Double(b.totalMistakes) / Double(max(1, b.totalReviews))
                if ra != rb { return ra > rb }
                return a.id < b.id
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Records a drill outcome for prompt `promptID` (`sourceID#form`), creating the card
    /// if new. Returns the SM-2 quality grade applied.
    @discardableResult
    public mutating func record(promptID: String, outcome: ConjugationOutcome, on date: Date = Date()) -> Int {
        var card = cards[promptID] ?? ConjugationSRSCard(id: promptID, createdAt: date)
        let quality = ConjugationSRSCard.quality(from: outcome)
        card.review(quality: quality, on: date)
        card.totalMistakes += outcome.mistakes
        cards[promptID] = card
        return quality
    }

    // MARK: Persistence

    public func save(to url: URL) throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
    }

    /// See ReviewKit.ReviewStore.loadReporting. (v1.15 §B.)
    public static func loadReporting(from url: URL) -> (store: ConjugationReviewStore, outcome: LossyLoad.Outcome) {
        let (decoded, outcome) = LossyLoad.load(ConjugationReviewStore.self, from: url)
        let store = decoded ?? ConjugationReviewStore()
        if store.skippedOnLoad > 0 {
            return (store, .loadedWithSkips(skipped: store.skippedOnLoad))
        }
        return (store, outcome)
    }

    public static func load(from url: URL) -> ConjugationReviewStore { loadReporting(from: url).store }

    /// Absolute-calendar-day due histogram for the home-screen widget (v1.11). Parallel to
    /// `ReviewStore.dueByDay` but hand-copied here to keep this module zero-dependency
    /// (Option A parallel types). `result[0]` absorbs everything overdue; cards `horizon`+
    /// days out are omitted. See `ReviewStore.dueByDay` for the full rationale (why a
    /// histogram, not a relative forecast). DST-safe via `dateComponents([.day])`.
    public func dueByDay(asOf date: Date = Date(), horizon: Int, calendar: Calendar = .current,
                         resolves: (String) -> Bool,
                         rideable: (ConjugationSRSCard) -> Bool) -> [Int] {
        precondition(horizon > 0, "horizon must be positive")
        let start = calendar.startOfDay(for: date)
        var hist = [Int](repeating: 0, count: horizon)
        for card in cards.values where resolves(card.sourceID) && rideable(card) {
            let cardDay = calendar.startOfDay(for: card.dueDate)
            guard let off = calendar.dateComponents([.day], from: start, to: cardDay).day else { continue }
            let bucket = max(0, off)
            if bucket < horizon { hist[bucket] += 1 }
        }
        return hist
    }

    /// Near-term due buckets for the Stats screen's conjugation section (v1.9 §B). Parallel to
    /// `ReviewKit.DueForecast` but defined here to keep ConjugationReviewKit zero-dependency.
    /// Disjoint: `today` includes anything overdue, `tomorrow` = next day, `thisWeek` = the 5 days
    /// after that.
    public func dueForecast(asOf date: Date = Date(), calendar: Calendar = .current,
                            resolves: (String) -> Bool,
                            rideable: (ConjugationSRSCard) -> Bool) -> Forecast {
        let start = calendar.startOfDay(for: date)
        guard let endToday = calendar.date(byAdding: .day, value: 1, to: start),
              let endTomorrow = calendar.date(byAdding: .day, value: 2, to: start),
              let endWeek = calendar.date(byAdding: .day, value: 7, to: start)
        else { return Forecast() }
        var f = Forecast()
        for card in cards.values where resolves(card.sourceID) && rideable(card) {
            if card.dueDate < endToday { f.today += 1 }
            else if card.dueDate < endTomorrow { f.tomorrow += 1 }
            else if card.dueDate < endWeek { f.thisWeek += 1 }
        }
        return f
    }

    /// Near-term due counts (today / tomorrow / this week).
    public struct Forecast: Sendable, Equatable {
        public var today: Int
        public var tomorrow: Int
        public var thisWeek: Int
        public init(today: Int = 0, tomorrow: Int = 0, thisWeek: Int = 0) {
            self.today = today; self.tomorrow = tomorrow; self.thisWeek = thisWeek
        }
    }
}
