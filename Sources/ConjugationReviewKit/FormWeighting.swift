import Foundation

/// Pure, store-read-only weighted picker for the "weak-form weighting" feature
/// (PLAN-V1.8 §3). Given a verb (`entryID`) and its candidate form tokens (the
/// `ConjugationForm` raw values), it biases selection toward the forms the learner is
/// weakest at — while guaranteeing every form keeps a floor probability so one form
/// can never monopolize the drill ("防只练一形").
///
/// It lives in ConjugationReviewKit (which owns the cards + knows only String tokens),
/// NOT in GameCore: the app maps `ConjugationForm ↔ rawValue` around this call and
/// passes GameCore a plain `(String,[ConjugationForm])->ConjugationForm` closure, so
/// GameCore never imports ConjugationReviewKit (red line §6). The function only READS
/// the store — SRS is written solely through `record`.
public enum FormWeighting {

    /// Weakness ∈ [0,1] for one card (higher = drill it more). A never-reviewed form is
    /// neutral (0.5): worth introducing, but not dominating. A leech is maxed (1.0).
    static func weakness(of card: ConjugationSRSCard?) -> Double {
        guard let card, card.totalReviews > 0 else { return 0.5 }
        if card.isLeech { return 1.0 }
        let mistakeRate = min(1.0, Double(card.totalMistakes) / Double(max(1, card.totalReviews)))
        let easeSpan = ConjugationSRSCard.initialEaseFactor - ConjugationSRSCard.minimumEaseFactor
        let easeWeak = easeSpan > 0
            ? min(1.0, max(0.0, (ConjugationSRSCard.initialEaseFactor - card.easeFactor) / easeSpan))
            : 0.0
        return min(1.0, 0.6 * mistakeRate + 0.4 * easeWeak)
    }

    /// Picks one token from `formTokens`, weighted toward weaker forms for `entryID`.
    /// `bias` (0…1) is the share of probability mass distributed by weakness; the
    /// remaining `1-bias` is spread uniformly (the floor). Deterministic given `rng`.
    /// Returns nil only for an empty candidate list.
    public static func weightedPick<G: RandomNumberGenerator>(
        entryID: String,
        formTokens: [String],
        store: ConjugationReviewStore,
        bias: Double = 0.6,
        using rng: inout G
    ) -> String? {
        guard let first = formTokens.first else { return nil }
        guard formTokens.count > 1 else { return first }

        let b = min(1.0, max(0.0, bias))
        let n = Double(formTokens.count)
        let weaknesses = formTokens.map { weakness(of: store.card(for: "\(entryID)#\($0)")) }
        let sum = weaknesses.reduce(0, +)

        // weight = uniform floor (1-b)/n  +  weakness share  b * w/Σw
        let weights: [Double] = formTokens.indices.map { i in
            let share = sum > 0 ? weaknesses[i] / sum : 1.0 / n
            return (1.0 - b) / n + b * share
        }

        let total = weights.reduce(0, +)                    // ~1.0, but normalize defensively
        var roll = Double.random(in: 0..<1, using: &rng) * total
        for (i, w) in weights.enumerated() {
            roll -= w
            if roll < 0 { return formTokens[i] }
        }
        return formTokens[formTokens.count - 1]             // FP fallthrough
    }
}
