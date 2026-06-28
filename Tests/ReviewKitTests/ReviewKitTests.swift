import Testing
import Foundation
@testable import ReviewKit

private let day0 = Date(timeIntervalSince1970: 1_700_000_000)

private func daysBetween(_ start: Date, _ end: Date) -> Int {
    Int((end.timeIntervalSince(start) / 86_400).rounded())
}

@Suite("SM-2 scheduling")
struct SRSCardTests {
    @Test("a new card starts at EF 2.5 and is due immediately")
    func newCard() {
        let card = SRSCard(id: "x", createdAt: day0)
        #expect(card.easeFactor == 2.5)
        #expect(card.interval == 0)
        #expect(card.repetitions == 0)
        #expect(card.dueDate == day0)
    }

    @Test("successive successes schedule 1 day, 6 days, then round(interval × EF)")
    func successScheduling() {
        var card = SRSCard(id: "x", createdAt: day0)

        card.review(quality: 5, on: day0)
        #expect(card.interval == 1)
        #expect(card.repetitions == 1)
        #expect(card.easeFactor == 2.6)                    // +0.1
        #expect(daysBetween(day0, card.dueDate) == 1)

        card.review(quality: 5, on: card.dueDate)
        #expect(card.interval == 6)
        #expect(card.repetitions == 2)

        card.review(quality: 5, on: card.dueDate)
        #expect(card.interval == 16)                       // round(6 × 2.7)
    }

    @Test("q=4 leaves EF unchanged; q=3 lowers it by 0.14")
    func easeAdjustment() {
        var clean = SRSCard(id: "x", createdAt: day0)
        clean.review(quality: 4, on: day0)
        #expect(clean.easeFactor == 2.5)

        var hard = SRSCard(id: "y", createdAt: day0)
        hard.review(quality: 3, on: day0)
        #expect(abs(hard.easeFactor - 2.36) < 1e-9)
    }

    @Test("a lapse resets repetitions to 1 day and leaves EF unchanged (original SM-2)")
    func lapse() {
        var card = SRSCard(id: "x", createdAt: day0)
        card.review(quality: 5, on: day0)
        card.review(quality: 5, on: card.dueDate)          // reps 2, interval 6
        let easeBefore = card.easeFactor
        card.review(quality: 1, on: card.dueDate)
        #expect(card.repetitions == 0)
        #expect(card.interval == 1)
        #expect(card.lapses == 1)
        #expect(card.easeFactor == easeBefore)
    }

    @Test("EF never drops below 1.3")
    func easeFloor() {
        var card = SRSCard(id: "x", createdAt: day0)
        var date = day0
        for _ in 0 ..< 20 {
            card.review(quality: 3, on: date)
            date = card.dueDate
        }
        #expect(card.easeFactor == 1.3)
    }

    @Test("a card becomes a leech after enough lapses")
    func leech() {
        var card = SRSCard(id: "x", createdAt: day0)
        #expect(!card.isLeech)
        for _ in 0 ..< 8 { card.review(quality: 1, on: card.dueDate) }
        #expect(card.isLeech)
    }

    @Test("typing outcome maps to the expected SM-2 quality", arguments: [
        (TypingOutcome(completed: true, mistakes: 0, usedHint: false, durationRatio: 1.0), 5),
        (TypingOutcome(completed: true, mistakes: 0, usedHint: false, durationRatio: 2.0), 4),
        (TypingOutcome(completed: true, mistakes: 2, usedHint: false), 3),
        (TypingOutcome(completed: true, mistakes: 4, usedHint: false), 2),   // many typos → lapse
        (TypingOutcome(completed: true, mistakes: 0, usedHint: true), 2),
        (TypingOutcome(completed: false, mistakes: 3), 1),
        (TypingOutcome(completed: false, mistakes: 0), 0),
    ])
    func qualityMapping(_ c: (outcome: TypingOutcome, expected: Int)) {
        #expect(SRSCard.quality(from: c.outcome) == c.expected)
    }
}

@Suite("ReviewStore")
struct ReviewStoreTests {
    @Test("recording a perfect outcome creates a card scheduled into the future")
    func record() {
        var store = ReviewStore()
        let quality = store.record(entryID: "n5-mizu", outcome: TypingOutcome(completed: true), on: day0)
        #expect(quality == 5)
        #expect(store.count == 1)
        #expect((store.card(for: "n5-mizu")?.dueDate ?? day0) > day0)
    }

    @Test("due cards are filtered and ordered by due date")
    func dueOrdering() {
        var store = ReviewStore()
        store.record(entryID: "a", outcome: TypingOutcome(completed: true), on: day0)
        store.record(entryID: "b", outcome: TypingOutcome(completed: false), on: day0)
        #expect(store.dueCount(on: day0) == 0)             // both pushed to day0+1

        let later = Calendar.current.date(byAdding: .day, value: 2, to: day0)!
        let due = store.dueCards(on: later)
        #expect(due.count == 2)
        for i in 1 ..< due.count {
            #expect(due[i - 1].dueDate <= due[i].dueDate)
        }
    }

    @Test("mistakes accumulate on the card")
    func mistakeTracking() {
        var store = ReviewStore()
        store.record(entryID: "a", outcome: TypingOutcome(completed: true, mistakes: 2), on: day0)
        #expect(store.card(for: "a")?.totalMistakes == 2)
    }

    @Test("persists and reloads via Codable")
    func persistence() throws {
        var store = ReviewStore()
        store.record(entryID: "a", outcome: TypingOutcome(completed: true), on: day0)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("review-test-\(UUID().uuidString).json")
        try store.save(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let loaded = ReviewStore.load(from: url)
        #expect(loaded.count == 1)
        #expect(loaded.card(for: "a")?.easeFactor == store.card(for: "a")?.easeFactor)
    }
}

/// Weak-words cram pool (PLAN-V1.7 §B). `weakestCards` is a PURE read that ranks the
/// user's hardest reviewed cards — it must never mutate the store (a cram never writes SRS).
@Suite("ReviewStore — weakest cards (v1.7 cram)")
struct WeakestCardsTests {
    private func card(_ id: String, ease: Double = 2.5, lapses: Int = 0,
                      reviews: Int = 1, mistakes: Int = 0) -> SRSCard {
        var c = SRSCard(id: id, createdAt: day0)
        c.easeFactor = ease
        c.lapses = lapses
        c.totalReviews = reviews
        c.totalMistakes = mistakes
        return c
    }

    @Test("only reviewed cards are eligible; fresh (never-reviewed) cards are excluded")
    func excludesFresh() {
        let store = ReviewStore(cards: [
            "fresh": card("fresh", reviews: 0),
            "seen": card("seen", reviews: 3),
        ])
        #expect(store.reviewedCount == 1)
        #expect(store.weakestCards().map(\.id) == ["seen"])
    }

    @Test("leeches rank first, then lower ease, then more lapses, then mistake-rate")
    func ranking() {
        let store = ReviewStore(cards: [
            "leech":   card("leech",   ease: 2.5, lapses: 8, reviews: 10),  // isLeech (lapses≥8)
            "lowEase": card("lowEase", ease: 1.4, lapses: 1, reviews: 5),
            "midEase": card("midEase", ease: 2.0, lapses: 3, reviews: 5),
            "clean":   card("clean",   ease: 2.8, lapses: 0, reviews: 5),
        ])
        #expect(store.weakestCards().map(\.id) == ["leech", "lowEase", "midEase", "clean"])
    }

    @Test("mistake-rate breaks ties after ease and lapses")
    func mistakeRateTiebreak() {
        let store = ReviewStore(cards: [
            "sloppy": card("sloppy", ease: 2.0, lapses: 2, reviews: 4, mistakes: 8),  // rate 2.0
            "tidy":   card("tidy",   ease: 2.0, lapses: 2, reviews: 4, mistakes: 1),  // rate 0.25
        ])
        #expect(store.weakestCards().map(\.id) == ["sloppy", "tidy"])
    }

    @Test("limit caps the result count")
    func limit() {
        let cards = Dictionary(uniqueKeysWithValues: (0..<10).map { ("c\($0)", card("c\($0)", reviews: 2)) })
        #expect(ReviewStore(cards: cards).weakestCards(limit: 3).count == 3)
    }

    @Test("weakestCards / reviewedCount are pure reads — they never mutate the store")
    func pureRead() {
        let store = ReviewStore(cards: [
            "a": card("a", ease: 1.5, lapses: 2, reviews: 4, mistakes: 3),
            "b": card("b", reviews: 1),
        ])
        let before = store.cards
        _ = store.weakestCards()
        _ = store.reviewedCount
        #expect(store.cards == before)
    }

    @Test("an empty store yields no weak cards")
    func empty() {
        let store = ReviewStore()
        #expect(store.weakestCards().isEmpty)
        #expect(store.reviewedCount == 0)
    }
}
