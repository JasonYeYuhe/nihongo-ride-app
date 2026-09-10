import Testing
import Foundation
import VocabKit
import ReviewKit
import ConjugationReviewKit
import JournalKit
import WordListsKit
import SyncKit
@testable import NihongoRideApp

/// `applyCloudChanges` — six inputs, five merge branches, three contracts written in prose, and
/// until now not one test that called it (v1.32 §D3).
///
/// Every one of the three is a shipped defect written down after it was fixed:
///
/// | contract | the defect it records |
/// |---|---|
/// | compaction runs ONLY after a merge, never on the load path | v1.10 §A3 — a not-yet-propagated deletion compacted early gets revived by a peer's union on the next fetch |
/// | reminders are rescheduled after **both** SRS merges | v1.14 §B — the call sat inside the vocab branch, so a peer's conjugation progress reached the app but never the badge |
/// | the widget is republished when the journal **or** odometer branch fires alone | v1.12 §C — a Practice run syncs as records only, so the peer's ride restored the streak in-app while the widget kept walking its decay curve |
///
/// **All three hold in the code as written.** That is the point: this file is not fixing them, it
/// is making them able to fail. `STATE-2026-08-18.md` names the detector — *where a comment states
/// a contract, check whether anything enforces it* — and three of v1.23's six defects were found
/// exactly that way.
///
/// Each test below names the mutation that kills it, and each mutation was run.
@MainActor
@Suite("applyCloudChanges — the three contracts nothing pinned")
struct ApplyCloudChangesTests {

    // MARK: Arrangement

    static let day: TimeInterval = 86_400

    /// A store holding the default list, one live list, and one tombstone old enough to compact.
    static func listsWithAnExpiredTombstone(now: Date) -> WordListStore {
        WordListStore(lists: [
            WordList(id: WordList.defaultID, name: "Saved", ids: ["a"], nameUpdatedAt: now,
                     isDefault: true),
            WordList(id: "live", name: "Live", ids: ["a"], nameUpdatedAt: now),
            WordList(id: "gone", name: "Gone", nameUpdatedAt: now - 40 * day,
                     deleted: true, deletedAt: now - 31 * day),
        ])
    }

    /// A model whose word-list file is seeded, plus the directory it was sandboxed into.
    ///
    /// The seed is a claim, so it is checked: a silently-empty seed would make every compaction
    /// assertion below pass for the wrong reason, which is the failure mode
    /// `AppModelTests.seeded` already guards its own review seeds against.
    static func modelWithLists(now: Date) throws -> AppModel {
        let sandbox = AppModelTests.sandboxed(vocab: VocabStore(entries: [
            AppModelTests.entry("a", "赤", "あか"),
        ]))
        let store = listsWithAnExpiredTombstone(now: now)
        try JSONEncoder().encode(store).write(to: AppModel.supportFileURL("word-lists.json"))

        // Re-read through the app's own loader rather than trusting the write.
        let model = AppModel(vocab: VocabStore(entries: [AppModelTests.entry("a", "赤", "あか")]))
        #expect(model.allWordListIDs.sorted() == ["default", "gone", "live"],
                "the seed did not load — got \(model.allWordListIDs)")
        _ = sandbox
        return model
    }

    /// Counts calls and snapshots what the stores held AT the moment of the call.
    ///
    /// The state matters as much as the count: "reminders were rescheduled once" is satisfied by a
    /// call placed before the conjugation merge, which is v1.14 §B's defect exactly.
    final class EffectProbe: @unchecked Sendable {
        private(set) var calls = 0
        private(set) var vocabCardsAtCall: [Int] = []
        private(set) var conjugationCardsAtCall: [Int] = []
        func fired(vocab: Int, conjugation: Int) {
            calls += 1
            vocabCardsAtCall.append(vocab)
            conjugationCardsAtCall.append(conjugation)
        }
    }

    static func watchEffects(_ model: AppModel) -> (reminders: EffectProbe, widget: EffectProbe) {
        let reminders = EffectProbe(), widget = EffectProbe()
        model.remindersNeedRescheduling = { [weak model] in
            reminders.fired(vocab: model?.reviewStore.count ?? -1,
                            conjugation: model?.conjugationReviewStore.count ?? -1)
        }
        model.widgetNeedsRepublishing = { [weak model] in
            widget.fired(vocab: model?.reviewStore.count ?? -1,
                         conjugation: model?.conjugationReviewStore.count ?? -1)
        }
        return (reminders, widget)
    }

    static func dueCard(_ id: String) -> SRSCard {
        var card = SRSCard(id: id)
        card.dueDate = Date() - day
        return card
    }

    // MARK: Contract 1 — compaction runs only after a merge

    /// KILLED BY: deleting `wordLists.compactTombstones()` from the lists branch.
    @Test("a word-list merge compacts an expired tombstone")
    func aListsMergeCompacts() throws {
        let now = Date()
        let model = try Self.modelWithLists(now: now)
        model.applyCloudChanges(wordLists: [
            WordList(id: "remote", name: "Remote", nameUpdatedAt: now),
        ])
        #expect(!model.allWordListIDs.contains("gone"), "the expired tombstone survived a merge")
        #expect(model.allWordListIDs.contains("live"), "compaction took a live list with it")
        #expect(model.allWordListIDs.contains(WordList.defaultID))
    }

    /// The half the comment is actually about, and the one a naive reading omits.
    ///
    /// Without this, moving compaction onto the load path leaves the test above green — and that
    /// move is precisely the v1.10 §A3 defect, because a tombstone compacted before it has
    /// propagated is revived by the next peer's union.
    ///
    /// KILLED BY: calling `compactTombstones()` in `WordListStore.loadOrMigrate` after a
    /// successful decode.
    @Test("merely LOADING does not compact — the tombstone has to survive to propagate")
    func loadingDoesNotCompact() throws {
        let now = Date()
        let model = try Self.modelWithLists(now: now)
        #expect(model.allWordListIDs.contains("gone"),
                "the tombstone was compacted on the load path, where a peer can still revive it")
    }

    /// "ONLY here" is a claim about a BRANCH, not about the function.
    ///
    /// KILLED BY: hoisting `compactTombstones()` out of the `if !incomingLists.isEmpty` block to
    /// the end of `applyCloudChanges`.
    @Test("a merge that carries no word lists does not compact either")
    func aNonListsMergeDoesNotCompact() throws {
        let now = Date()
        let model = try Self.modelWithLists(now: now)
        model.applyCloudChanges(cards: [Self.dueCard("a")])
        #expect(model.allWordListIDs.contains("gone"),
                "a cards-only merge compacted a tombstone the lists branch never touched")
    }

    // MARK: Contract 2 — reminders reschedule after BOTH SRS merges

    /// v1.14 §B verbatim: the call used to sit inside the vocab branch.
    ///
    /// KILLED BY: narrowing the gate to `if !cards.isEmpty`.
    @Test("a conjugation-only merge reschedules reminders")
    func aConjugationOnlyMergeReschedules() {
        let model = AppModelTests.makeModel(vocab: VocabStore(entries: [AppModelTests.entry("a", "赤", "あか")]))
        let probes = Self.watchEffects(model)
        model.applyCloudChanges(conjugationCards: [ConjugationSRSCard(id: "a#te")])
        #expect(probes.reminders.calls == 1,
                "a peer's conjugation progress reached the app but not the badge")
    }

    /// The half a call-COUNT probe cannot see.
    ///
    /// A single reschedule is also what you get from a call placed *inside* the vocab branch on a
    /// mixed batch — it fires once, and it fires with a conjugation store that is still about to
    /// change. So assert the STATE at the moment of the call, not just the count.
    ///
    /// KILLED BY: moving the call inside the `!cards.isEmpty` block.
    @Test("a mixed merge reschedules ONCE, and after both stores have merged")
    func aMixedMergeReschedulesAfterBoth() {
        let model = AppModelTests.makeModel(vocab: VocabStore(entries: [AppModelTests.entry("a", "赤", "あか")]))
        let probes = Self.watchEffects(model)
        model.applyCloudChanges(cards: [Self.dueCard("a")],
                                conjugationCards: [ConjugationSRSCard(id: "a#te")])
        #expect(probes.reminders.calls == 1, "rescheduled \(probes.reminders.calls) times")
        #expect(probes.reminders.vocabCardsAtCall == [1],
                "the vocab store had not merged yet at the moment reminders were rescheduled")
        #expect(probes.reminders.conjugationCardsAtCall == [1],
                "the conjugation store had not merged yet at the moment reminders were rescheduled")
    }

    /// The negative control. Without it, an unconditional call passes both tests above.
    ///
    /// KILLED BY: making the reminder gate unconditional.
    @Test("a merge that touches neither SRS store does not reschedule reminders")
    func aRecordsOnlyMergeDoesNotReschedule() {
        let model = AppModelTests.makeModel(vocab: VocabStore(entries: [AppModelTests.entry("a", "赤", "あか")]))
        let probes = Self.watchEffects(model)
        model.applyCloudChanges(records: [RideRecord(id: UUID(), date: Date(), mode: "journey",
                                                     level: "N5", score: 1, wpm: 1, accuracy: 1,
                                                     wordsCompleted: 1, lapsed: 0,
                                                     distanceMeters: 10, duration: 10)])
        #expect(probes.reminders.calls == 0,
                "a records-only merge rescheduled reminders it cannot have changed")
    }

    // MARK: Contract 3 — the widget follows all four snapshot sources

    /// v1.12 §C: a Practice run uses a transient SRS store, so it syncs as records only. Gating
    /// the republish on the review stores alone let the peer's ride restore the streak in-app
    /// while the widget kept walking its decay curve toward a streak the user had not lost.
    ///
    /// KILLED BY: dropping `|| !records.isEmpty` — and, for the second case,
    /// `|| !odometerSlots.isEmpty`.
    @Test("the journal and odometer branches each republish the widget on their own")
    func journalAndOdometerRepublishAlone() {
        let ride = RideRecord(id: UUID(), date: Date(), mode: "journey", level: "N5", score: 1,
                              wpm: 1, accuracy: 1, wordsCompleted: 1, lapsed: 0,
                              distanceMeters: 10, duration: 10)

        let a = AppModelTests.makeModel(vocab: VocabStore(entries: [AppModelTests.entry("a", "赤", "あか")]))
        let aProbes = Self.watchEffects(a)
        a.applyCloudChanges(records: [ride])
        #expect(aProbes.widget.calls == 1, "a records-only merge did not republish the widget")

        let b = AppModelTests.makeModel(vocab: VocabStore(entries: [AppModelTests.entry("a", "赤", "あか")]))
        let bProbes = Self.watchEffects(b)
        b.applyCloudChanges(odometerSlots: ["peer": .init(words: 500, distanceMeters: 1000, runs: 5)])
        #expect(bProbes.widget.calls == 1, "an odometer-only merge did not republish the widget")
    }

    /// The negative control, and it is the one that matters: with it missing, "always republish"
    /// satisfies every positive assertion above. That is the shape this repo keeps shipping.
    ///
    /// KILLED BY: making the widget gate unconditional.
    @Test("a merge that touches nothing the snapshot derives from does not republish")
    func aListsOnlyMergeDoesNotRepublish() throws {
        let now = Date()
        let model = try Self.modelWithLists(now: now)
        let probes = Self.watchEffects(model)
        model.applyCloudChanges(wordLists: [WordList(id: "remote", name: "Remote", nameUpdatedAt: now)])
        #expect(probes.widget.calls == 0,
                "a word-list merge republished a snapshot that carries no word lists")
        #expect(probes.reminders.calls == 0)
    }

    // MARK: Examined and NOT a defect — recorded so it is not re-examined a fourth time

    /// The survey that produced §D3 proposed a tenth test asserting that a cap-overflowing merge
    /// loses the journal's lifetime counters, to be written RED against current code.
    ///
    /// **It is not a defect, and this test is the check rather than the claim.** `applyCloudChanges`
    /// rebuilds the journal with `RideJournal(records:)`, which does recompute `lifetimeRuns` from
    /// the capped array — but every displayed lifetime takes the maximum with the odometer
    /// (`AppModel.lifetimeRuns`, `lifetimeWords`), which the code says in a comment one line above
    /// the rebuild. And the odometer cannot be back-filled downward afterwards:
    /// `OdometerLog.shouldBackfill` is gated on `hasSyncedBefore`, and a device that has merged
    /// cloud changes has synced by definition.
    ///
    /// Kept as a test rather than as a paragraph, because a paragraph is what §C2 spent four
    /// examinations proving is not enough.
    @Test("a journal rebuild cannot lower the lifetime the user is shown")
    func theRebuildCannotLowerTheDisplayedLifetime() {
        let model = AppModelTests.makeModel(vocab: VocabStore(entries: [AppModelTests.entry("a", "赤", "あか")]))
        model.applyCloudChanges(odometerSlots: ["peer": .init(words: 5_000, distanceMeters: 9_000,
                                                              runs: 250)])
        let beforeRuns = model.lifetimeRuns
        let beforeWords = model.lifetimeWords
        #expect(beforeRuns == 250, "the odometer merge is the arrangement — it must have landed")

        // A merge whose records rebuild the journal from a single ride.
        model.applyCloudChanges(records: [RideRecord(id: UUID(), date: Date(), mode: "journey",
                                                     level: "N5", score: 1, wpm: 1, accuracy: 1,
                                                     wordsCompleted: 1, lapsed: 0,
                                                     distanceMeters: 10, duration: 10)])
        #expect(model.lifetimeRuns >= beforeRuns,
                "the displayed lifetime run count went backwards: \(beforeRuns) → \(model.lifetimeRuns)")
        #expect(model.lifetimeWords >= beforeWords,
                "the displayed lifetime word count went backwards")
    }
}
