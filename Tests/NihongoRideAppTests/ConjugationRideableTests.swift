import Testing
import Foundation
import VocabKit
import GameCore
import ConjugationReviewKit
@testable import NihongoRideApp

/// A conjugation card the drill can never clear must not be counted as work — on any of the six
/// readouts that count it.
///
/// **The defect, stated as the shared-predicate rule this repo has broken twenty-odd times:**
/// `ConjugationReviewStore`'s due queries filtered on `dueDate` and `resolves(sourceID)`. The
/// drill's builder additionally requires that `GameCore` can BUILD a prompt from the card's
/// `sourceID#form` — and when it cannot, `makeReview` skips the pair and pads the slot with a
/// fresh weak-form prompt, whose outcome is written back against a *different* card id. So the
/// skipped card is never graded. It stays overdue forever, sorts first (it only gets more
/// overdue), displaces a genuinely due card out of the twelve-slot run, and keeps the menu
/// button, the app-icon badge, the reminder body, the home-screen widget and the Stats forecast
/// all reporting work nobody can do.
///
/// **This is not hypothetical, and the evidence is inside this test target.**
/// `AppModelTests.conjugationReviewLabelStatesTheRun` carries the comment *"the drill's builder
/// drops a form it cannot parse while `conjugationDueCount` counts the card regardless, so the
/// first fixture produced thirty due cards and an empty run"* — a previous session walked into
/// the defect, and fixed the fixture.
///
/// **The reachable door is not the one the plan named.** `PLAN-V1.32` §C1 says this needs a
/// `ConjugationForm` case renamed or removed, "a property of history, not of the code". There is
/// a second door and it opens on a hinge this project turns most releases: `verbClass` reads the
/// corpus's opaque `vc` field, and `Conjugator.conjugate` fails per-form on a reading whose class
/// has no stem for it. **An entry can keep its id — passing `resolves:` — and stop being
/// conjugable.** Measured over all 56 corpus commits: `780d40d` (v1.14, "stop teaching wrong
/// conjugations and wrong readings") changed three entries' `vc` — `n1-b479`, `n2-g040`,
/// `n2-g058`, all `godan_u` → `suru`. Those landed on a class that conjugates every form, so no
/// card stranded. Nothing about the edit made that the likely outcome rather than the other one.
///
/// The seed below uses exactly that door: an entry that is present and is not conjugable.
@MainActor
@Suite("A conjugation card no drill can clear is not work")
struct ConjugationRideableTests {

    /// Three rideable verbs plus one entry that resolves and cannot be conjugated.
    ///
    /// `vc: nil` is what a corpus edit that withdrew a verb class leaves behind: `VocabStore`
    /// still answers `entry(id:)`, so `resolves:` says yes, and `ConjugationPrompt.init?` returns
    /// nil because `entry.verbClass` is nil.
    static func strandedSeed(strandedIsConjugable: Bool) -> (VocabStore, ConjugationReviewStore) {
        var entries = AppModelTests.verbEntries(3)
        entries.append(VocabEntry(
            id: "stranded", surface: "開ける", kana: "あける",
            partsOfSpeech: ["v"], jlpt: .n5,
            meanings: ["en": ["to open"], "zh": ["打开"]],
            // The ONLY difference between the two arms. Everything else — id, surface, kana,
            // parts of speech — is identical, so the difference in the numbers is attributable
            // to the verb class and to nothing else.
            //
            // The first draft used 赤い/あかい here and the control read 3 instead of 4: an
            // `ichidan` class needs a る ending, so the "conjugable" arm was not conjugable and
            // both arms measured the same thing. The control caught the test's own defect before
            // the test could certify the code. That is the entire argument for pairing.
            vc: strandedIsConjugable ? "ichidan" : nil))

        var cards: [String: ConjugationSRSCard] = [:]
        for entry in entries {
            var card = AppModelTests.dueConjugationCard(entry.id, "te")
            // Every card a leech, so `conjugationLeechCount` is exercised by the same seed.
            card.lapses = 9
            cards[card.id] = card
        }
        return (VocabStore(entries: entries), ConjugationReviewStore(cards: cards))
    }

    /// The numbers this target can read, off ONE model, so a fix applied to one call site
    /// cannot pass.
    ///
    /// **Two of the six readouts are deliberately absent, and saying which is the point.** The
    /// home-screen widget and the app-icon badge / reminder body are not here:
    ///
    /// * `refreshWidgetSnapshot` returns early on `Bundle.main.bundleIdentifier == nil`
    ///   (`AppModel.swift:670`), which under swift-testing's SwiftPM entry point is always true.
    ///   That guard is what stops a test run stamping its empty sandbox onto the owner's real
    ///   home-screen widget — it had already happened once before v1.24's review caught it —
    ///   **so it must not be weakened to make this test reach further.**
    /// * `ReminderScheduler.apply` talks to `UNUserNotificationCenter` and is gated on the same
    ///   bundle check.
    ///
    /// What holds those two instead: the compiler (`rideable:` is required, so neither call site
    /// can omit it — that is how the badge was found at all, by a build failure rather than by
    /// this sweep), and `ConjugationReviewKitTests`' store-level assertions that `dueByDay`
    /// applies it. Written down because "the tests are green" must not be read as "all six
    /// readouts are covered".
    struct Readouts: Equatable {
        var dueCount = 0
        var queueCount = 0
        var forecastToday = 0
        var leechCount = 0
        var buttonText = ""
    }

    static func readouts(strandedIsConjugable: Bool) -> Readouts {
        let (vocab, conjugation) = strandedSeed(strandedIsConjugable: strandedIsConjugable)
        let model = AppModelTests.seeded(vocab: vocab, conjugation: conjugation)
        return Readouts(
            dueCount: model.conjugationDueCount,
            queueCount: model.conjugationReviewQueue.count,
            forecastToday: model.conjugationDueForecast.today,
            leechCount: model.conjugationLeechCount,
            buttonText: model.conjugationReviewButtonText(zh: false))
    }

    /// The paired control that must fire, in one test with the experiment.
    ///
    /// Reading "3" alone proves nothing: a seed that silently failed to load, a store the model
    /// never read, or a filter that drops every card all print 3 just as well. The two arms
    /// differ in exactly one field — the stranded entry's `vc` — so the difference between them
    /// is attributable to that field and to nothing else. (`STATE-2026-08-18.md`: "If the control
    /// is not asked, the experiment proved nothing.")
    @Test("a card whose verb stopped being conjugable is dropped from every readout here")
    func strandedCardCountsNowhere() {
        let stranded = Self.readouts(strandedIsConjugable: false)
        let control = Self.readouts(strandedIsConjugable: true)

        #expect(control == Readouts(dueCount: 4, queueCount: 4, forecastToday: 4, leechCount: 4,
                                    buttonText: "Review 4 due"),
                "the control must SEE all four, or the experiment is measuring an empty store")
        #expect(stranded == Readouts(dueCount: 3, queueCount: 3, forecastToday: 3, leechCount: 3,
                                     buttonText: "Review 3 due"))
    }

    /// The property itself, rather than an arithmetic consequence of it.
    ///
    /// "Returns one fewer" is satisfied by a filter that drops the WRONG card — a failure this
    /// repo has shipped. This states the contract directly: every pair the count promises is a
    /// pair the run can build. It is the one assertion that stays true if the cap, the sort or
    /// the seed changes.
    @Test("every pair the queue promises is a pair makeReview can actually build")
    func theCountAndTheRunShareThePredicate() {
        let (vocab, conjugation) = Self.strandedSeed(strandedIsConjugable: false)
        let model = AppModelTests.seeded(vocab: vocab, conjugation: conjugation)

        let queue = model.conjugationReviewQueue
        #expect(!queue.isEmpty, "an empty queue would satisfy the loop below vacuously")
        #expect(!queue.contains { $0.entryID == "stranded" })
        for pair in queue {
            #expect(ConjugationSession.reviewPrompt(entryID: pair.entryID,
                                                    formToken: pair.formToken,
                                                    vocab: vocab, languageCode: "en") != nil,
                    "the queue offers \(pair.entryID)#\(pair.formToken), which makeReview skips")
        }
    }

    /// The unparseable-token door the plan named, kept because it is the other half of the
    /// population and costs one test. `"masu"` is the exact token the fixture in
    /// `AppModelTests` had to be corrected away from.
    @Test("an unparseable form token is dropped too, by the same predicate")
    func unparseableTokenIsAlsoDropped() {
        let entries = AppModelTests.verbEntries(3)
        var cards: [String: ConjugationSRSCard] = [:]
        for entry in entries {
            let good = AppModelTests.dueConjugationCard(entry.id, "te")
            cards[good.id] = good
        }
        let bad = AppModelTests.dueConjugationCard(entries[0].id, "masu")
        cards[bad.id] = bad

        let model = AppModelTests.seeded(vocab: VocabStore(entries: entries),
                                         conjugation: ConjugationReviewStore(cards: cards))
        #expect(model.conjugationDueCount == 3, "\"masu\" is not a ConjugationForm raw value")
        #expect(ConjugationSession.reviewPrompt(entryID: entries[0].id, formToken: "masu",
                                                vocab: VocabStore(entries: entries),
                                                languageCode: "en") == nil)
    }

    /// `reviewedCount` deliberately keeps counting the stranded card, and the line is asserted
    /// rather than left to a comment — because a comment stating a contract nothing enforces is
    /// this project's cheapest and most-repeated defect.
    ///
    /// The reason is not symmetry: "forms practised" is a historical fact, and the learner DID
    /// practise it. Filtering it there would make a true number false, which is the direction
    /// v1.24 §C's `sourceID`/`id` swap actually shipped ("Forms practiced 0" forever). Work
    /// remaining filters; history does not.
    @Test("forms PRACTISED still counts the stranded card — history is not outstanding work")
    func historyIsNotFiltered() {
        let (vocab, conjugation) = Self.strandedSeed(strandedIsConjugable: false)
        let model = AppModelTests.seeded(vocab: vocab, conjugation: conjugation)
        #expect(model.conjugationReviewedCount == 4)
        #expect(model.conjugationDueCount == 3, "…while outstanding work drops it")
    }

    /// The closure AppModel injects must be the shared one, and must be handed the whole card.
    ///
    /// A `{ _ in true }` shim makes an ignored parameter indistinguishable from an applied one,
    /// so the store-level suite pins that the argument is consulted. This pins the other half:
    /// that what AppModel passes is `ConjugationSession.reviewPrompt`'s verdict and agrees with
    /// it card for card, rather than a re-derivation that happens to agree today.
    @Test("AppModel's rideable closure IS the builder's predicate")
    func theInjectedClosureIsTheBuildersPredicate() {
        let (vocab, conjugation) = Self.strandedSeed(strandedIsConjugable: false)
        let model = AppModelTests.seeded(vocab: vocab, conjugation: conjugation)
        let rideable = model.conjugationRideable

        for card in conjugation.cards.values {
            let built = ConjugationSession.reviewPrompt(entryID: card.sourceID,
                                                        formToken: card.formToken,
                                                        vocab: vocab, languageCode: "en") != nil
            #expect(rideable(card) == built, "disagreed on \(card.id)")
        }
        #expect(conjugation.cards.values.contains { !rideable($0) },
                "no card in the seed is unrideable — the agreement above is vacuous")
    }
}
