import Testing
import Foundation
@testable import ConjugationReviewKit

/// Deterministic RNG for the weighting-distribution tests (SplitMix64).
private struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

@Suite("ConjugationReviewKit — SRS card + store")
struct ConjugationReviewKitTests {

    private let day: TimeInterval = 86_400

    @Test("a fresh card is due immediately and parses its source id / form token")
    func freshCard() {
        let c = ConjugationSRSCard(id: "n5-123#te", createdAt: Date(timeIntervalSince1970: 0))
        #expect(c.isDue)
        #expect(c.sourceID == "n5-123")
        #expect(c.formToken == "te")
        #expect(c.totalReviews == 0)
        // a source id that itself contains no '#'
        let d = ConjugationSRSCard(id: "abc-g1#pastNegative")
        #expect(d.sourceID == "abc-g1")
        #expect(d.formToken == "pastNegative")
    }

    @Test("SM-2 scheduling: clean pass advances the interval; a lapse restarts at 1 day")
    func sm2() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        var c = ConjugationSRSCard(id: "v#te", createdAt: t0)
        c.review(quality: 5, on: t0)                 // first success → 1 day
        #expect(c.interval == 1)
        #expect(c.repetitions == 1)
        #expect(c.dueDate == Calendar.current.date(byAdding: .day, value: 1, to: t0))
        c.review(quality: 5, on: c.dueDate)          // second success → 6 days
        #expect(c.interval == 6)
        let easeBefore = c.easeFactor
        c.review(quality: 0, on: c.dueDate)          // lapse → restart, EF untouched
        #expect(c.interval == 1)
        #expect(c.repetitions == 0)
        #expect(c.lapses == 1)
        #expect(c.easeFactor == easeBefore)          // original SM-2: EF unchanged on lapse
    }

    @Test("quality mapping mirrors the SRSCard rubric")
    func qualityMapping() {
        #expect(ConjugationSRSCard.quality(from: .init(completed: false)) == 0)              // blank skip
        #expect(ConjugationSRSCard.quality(from: .init(completed: false, mistakes: 3)) == 1) // tried, failed
        #expect(ConjugationSRSCard.quality(from: .init(completed: true, usedHint: true)) == 2)
        #expect(ConjugationSRSCard.quality(from: .init(completed: true, mistakes: 4)) == 2)  // many typos
        #expect(ConjugationSRSCard.quality(from: .init(completed: true, mistakes: 1)) == 3)
        #expect(ConjugationSRSCard.quality(from: .init(completed: true, durationRatio: 1.0)) == 5)
        #expect(ConjugationSRSCard.quality(from: .init(completed: true, durationRatio: 2.0)) == 4)
    }

    @Test("record creates the card, applies SM-2, and accumulates mistakes")
    func record() {
        var store = ConjugationReviewStore()
        let q = store.record(promptID: "v#te", outcome: .init(completed: true, mistakes: 1))
        #expect(q == 3)
        let card = store.card(for: "v#te")
        #expect(card?.totalReviews == 1)
        #expect(card?.totalMistakes == 1)
        #expect(card?.interval == 1)
    }

    @Test("dueCards / dueCount filter by date, soonest first")
    func dueFiltering() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        var store = ConjugationReviewStore()
        store.record(promptID: "a#te", outcome: .init(completed: true), on: now)          // due +1d
        store.record(promptID: "b#te", outcome: .init(completed: false), on: now)         // lapse, due +1d
        // Nothing is due right now (both scheduled a day out).
        #expect(store.dueCount(on: now) == 0)
        let tomorrow = now.addingTimeInterval(day + 1)
        #expect(store.dueCount(on: tomorrow) == 2)
        #expect(store.dueCards(on: tomorrow, limit: 1).count == 1)     // capped
    }

    @Test("weakestFormCards is a pure read — it never mutates the store")
    func weakestReadOnly() {
        var store = ConjugationReviewStore()
        for i in 0..<5 { store.record(promptID: "v#f\(i)", outcome: .init(completed: true, mistakes: i)) }
        let before = store
        let weak = store.weakestFormCards(limit: 10)
        #expect(store == before, "weakestFormCards must not schedule/mutate")
        #expect(weak.allSatisfy { $0.totalReviews > 0 })
        #expect(!weak.isEmpty)
    }

    @Test("persistence round-trips through JSON")
    func persistence() throws {
        var store = ConjugationReviewStore()
        store.record(promptID: "v#te", outcome: .init(completed: true, mistakes: 2))
        store.record(promptID: "w#past", outcome: .init(completed: false))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("conj-review-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try store.save(to: url)
        let loaded = ConjugationReviewStore.load(from: url)
        #expect(loaded == store)
        #expect(loaded.card(for: "v#te")?.totalMistakes == 2)
    }

    @Test("load from a missing file yields an empty store")
    func loadMissing() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString).json")
        #expect(ConjugationReviewStore.load(from: url).count == 0)
    }

    // MARK: FormWeighting

    @Test("weightedPick edge cases: empty → nil, single → that token")
    func weightingEdges() {
        var rng = SeededRNG(seed: 1)
        let store = ConjugationReviewStore()
        #expect(FormWeighting.weightedPick(entryID: "v", formTokens: [], store: store, using: &rng) == nil)
        #expect(FormWeighting.weightedPick(entryID: "v", formTokens: ["te"], store: store, using: &rng) == "te")
    }

    @Test("weightedPick with no data is ~uniform; every token still appears")
    func weightingUniformWhenNoData() {
        var rng = SeededRNG(seed: 42)
        let store = ConjugationReviewStore()
        let tokens = ["te", "past", "polite", "negative"]
        var counts: [String: Int] = [:]
        for _ in 0..<4000 {
            let pick = FormWeighting.weightedPick(entryID: "v", formTokens: tokens, store: store, using: &rng)!
            counts[pick, default: 0] += 1
        }
        // No card data → uniform-ish: each token near 25% (1000/4000), all present.
        for t in tokens {
            #expect(counts[t, default: 0] > 700, "\(t) underrepresented: \(counts[t] ?? 0)")
            #expect(counts[t, default: 0] < 1300, "\(t) overrepresented: \(counts[t] ?? 0)")
        }
    }

    @Test("dueForecast buckets cards into today / tomorrow / this week (v1.9 §B)")
    func dueForecast() {
        let now = Date(timeIntervalSince1970: 3_000_000)
        let cal = Calendar.current
        var store = ConjugationReviewStore()
        func addCard(_ id: String, dueOffsetDays: Int) {
            // record once to create the card, then force its dueDate
            store.record(promptID: id, outcome: .init(completed: true), on: now)
            var c = store.card(for: id)!
            c.dueDate = cal.date(byAdding: .day, value: dueOffsetDays, to: cal.startOfDay(for: now))!
                .addingTimeInterval(3600)
            store = ConjugationReviewStore(cards: store.cards.merging([id: c]) { _, new in new })
        }
        addCard("a#te", dueOffsetDays: -1)   // overdue → today
        addCard("b#te", dueOffsetDays: 0)    // today
        addCard("c#te", dueOffsetDays: 1)    // tomorrow
        addCard("d#te", dueOffsetDays: 4)    // this week
        addCard("e#te", dueOffsetDays: 30)   // beyond → uncounted
        let f = store.dueForecast(asOf: now, calendar: cal)
        #expect(f.today == 2)
        #expect(f.tomorrow == 1)
        #expect(f.thisWeek == 1)
    }

    @Test("weightedPick biases toward the weak form but never starves the others")
    func weightingBiasesWeak() {
        var store = ConjugationReviewStore()
        // Make "te" the weak form (leech), the rest strong (clean, high ease).
        for _ in 0..<10 { store.record(promptID: "v#te", outcome: .init(completed: false)) }   // lots of lapses → leech
        for t in ["past", "polite", "negative"] {
            for _ in 0..<3 { store.record(promptID: "v#\(t)", outcome: .init(completed: true)) } // clean
        }
        var rng = SeededRNG(seed: 7)
        let tokens = ["te", "past", "polite", "negative"]
        var counts: [String: Int] = [:]
        for _ in 0..<4000 {
            let pick = FormWeighting.weightedPick(entryID: "v", formTokens: tokens, store: store, using: &rng)!
            counts[pick, default: 0] += 1
        }
        // The weak "te" should dominate…
        let te = counts["te", default: 0]
        for t in ["past", "polite", "negative"] {
            #expect(te > counts[t, default: 0], "weak te (\(te)) should beat \(t) (\(counts[t] ?? 0))")
        }
        // …but the floor (1-bias)/n = 0.1 each keeps every form present (>5%).
        for t in tokens {
            #expect(counts[t, default: 0] > 200, "\(t) starved: \(counts[t] ?? 0)")
        }
    }
}
