import Testing
import Foundation
import RomajiKana
import VocabKit
import ReviewKit
import GameCore
import SceneryKit

/// How far the road actually is, measured through the production path rather than asserted.
///
/// ## Why this exists
///
/// PLAN-STAGE1 rested its whole product argument on *"673 completed words reach Kyōto"*, computed
/// as 25,000 m ÷ (mean kana length × 10) over the **whole 7,071-entry corpus**. The arithmetic is
/// right and the population is wrong: new words are not drawn at random. `VocabStore.ordered`
/// sorts by `VocabEntry.difficulty`, whose `0.6 × length` term deals the SHORT words first, so the
/// words a rider actually meets average **2.92 kana, not 3.71**.
///
/// One more instance of the shape this project keeps finding — *a predicate correct for one
/// population, silently wrong on another* — and this time it was in the plan rather than the code,
/// where nothing was ever going to catch it.
///
/// `RideRoute`'s own doc comment had the same error pointing the other way: *"a journey ride is
/// ~150 m"* is exactly right for the FIRST ride and was then used as a steady-state constant to
/// justify the entire threshold ladder.
///
/// ## Why it rides a real `GameSession` instead of recomputing the rule
///
/// The distance rule lives in exactly one place — `distanceMeters += kana.count * 10` inside
/// `GameSession`. Re-deriving it here would be the *"one rule written twice will drift"* trap,
/// which has already cost this project three releases. So these tests build sessions the way
/// `AppModel.startGame` builds them, type every word through the real matcher, and read
/// `session.distanceMeters` back. If the rule changes, these numbers move with it.
///
/// ## What is asserted, and the one caveat on it
///
/// The ride counts are golden values over frozen corpus fields (`kana` and `jlpt` are red-line
/// frozen), so they move when entries are added or removed — which is exactly when somebody should
/// be told, and a band wide enough to absorb that would be a check that cannot fail.
///
/// **The caveat, found by the first version of this file rather than assumed away.** `sorted(by:)`
/// is not a stable sort, and `VocabEntry.difficulty` produces plenty of ties **between words of
/// different length** — it mixes length with JLPT rank, so a 5-kana N5 word ties a 3-kana N4 one.
/// The draft of this suite asserted that ties could not move the road; run, it printed fifty-odd
/// counterexamples. So these numbers are reproducible for a given corpus and toolchain and are not
/// guaranteed by `sorted`'s contract. If a Swift upgrade moves them by a ride or two, **that is
/// why, and the fix is to re-measure** — not to go hunting for a corpus regression that is not
/// there.
///
/// ## Cost
///
/// ~70 s, because it rides 120 full journeys through the real matcher and `ordered()` re-sorts
/// 7,071 entries on each one. That is most of `swift test`'s wall clock. It is kept in the default
/// suite anyway: this is the number the whole product argument rests on, and a gate somebody has
/// to remember to run is not a gate.
@Suite("The road, measured")
struct RoadDistanceTests {

    /// One ride, built the way `AppModel.startGame` builds a `.journey` run.
    ///
    /// Returns nil if the pool is exhausted, so a caller can stop rather than spin.
    private static func ride(vocab: VocabStore, review: inout ReviewStore,
                             reviewWords: Int, on day: Date) -> Double? {
        var config = GameSession.Config()
        config.mode = .journey
        config.reviewWordCount = reviewWords
        let session = GameSession.make(config: config, vocab: vocab, review: review, now: { day })
        guard !session.isFinished else { return nil }

        while let kana = session.currentKana {
            let before = session.wordsCompleted
            for character in KanaRomanizer.romaji(for: kana) { session.input(character) }
            // A word the matcher will not accept is a broken instrument, not a shorter road. A run
            // that silently typed nothing would report a distance of zero and read exactly like a
            // working one, so it fails loudly and names itself.
            guard session.wordsCompleted == before + 1 else {
                Issue.record("the matcher refused the romanization of \(kana) — the instrument is broken, not the road")
                return nil
            }
        }
        // `ReviewStore` is a VALUE type, so the session mutated its own copy. Carrying that copy
        // forward is what makes `seen` grow and the next ride introduce the NEXT twelve words.
        //
        // The first version of this file did not, and it measured a 167-ride road of identical
        // 150 m rides — the same twelve easiest words, forever. Which is precisely the failure the
        // comment above warns about, arriving by a different mechanism than the one it names:
        // the store was not fresh, it was a copy. `AppModel.finishGame` does the same carry-back
        // (`reviewStore = merged`), so this now measures the path the app actually walks.
        review = session.review
        return session.distanceMeters
    }

    /// Ride until the odometer reaches `metres`, returning each ride's distance.
    ///
    /// The threshold is READ FROM `RideRoute`, never written here: the number this suite reports
    /// and the number the app uses to decide you have arrived must be the same value, not two
    /// values that agree by inspection.
    private static func rideTo(_ metres: Double, reviewWords: Int) -> [Double] {
        let vocab = VocabStore.shared
        // ONE review store across the whole road. It is what makes `seen` grow, so each ride
        // introduces the NEXT twelve words rather than the same twelve forever — a fresh store per
        // ride would report a 150 m ride to infinity and look perfectly reasonable doing it.
        var review = ReviewStore()
        var lifetime = 0.0
        var perRide: [Double] = []
        var day = Date(timeIntervalSince1970: 0)
        while lifetime < metres && perRide.count < 5_000 {
            guard let d = ride(vocab: vocab, review: &review, reviewWords: reviewWords, on: day),
                  d > 0 else { break }
            lifetime += d
            perRide.append(d)
            // Days advance so review cards actually come due; without it the "with reviews" path
            // would be a fiction that quietly measured the new-words-only path.
            day = day.addingTimeInterval(60 * 60 * 24)
        }
        return perRide
    }

    @Test("the first ride is 150 m, which is where RideRoute's ~150 m came from")
    func theFirstRide() {
        let rides = Self.rideTo(200, reviewWords: 0)
        #expect(rides.first == 150,
                "the first twelve words are nine single kana plus みず・あさ・よる")
    }

    @Test("Kyōto is 47 rides away with reviews mixed in, 72 without")
    func theRoadToKyoto() throws {
        let kyoto = try #require(RideRoute.tokaidoStages.last).startMetres
        #expect(kyoto == 25_000, "the road's end moved; every number below is calibrated to it")

        let withReviews = Self.rideTo(kyoto, reviewWords: 8)
        let newOnly = Self.rideTo(kyoto, reviewWords: 0)
        let meanNew = newOnly.reduce(0, +) / Double(newOnly.count)
        let meanMixed = withReviews.reduce(0, +) / Double(withReviews.count)

        // Printed so a corpus change reports the NEW figure rather than only that the old one
        // broke. A golden whose failure message does not carry the replacement gets "fixed" by
        // pasting in whatever the run produced, without anyone asking whether it should have moved.
        print("""
              road to Kyōto — \(withReviews.count) rides with reviews, \(newOnly.count) without
              mean ride: \(Int(meanMixed)) m with reviews, \(Int(meanNew)) m without
              first ride: \(Int(newOnly[0])) m
              """)

        #expect(withReviews.count == 48)
        #expect(newOnly.count == 72)
        #expect(meanNew > 340 && meanNew < 360,
                "a journey ride averages ~350 m on the road to Kyōto, not the ~150 m of the first")
        #expect(meanMixed > 515 && meanMixed < 535)
    }

    @Test("the ordering is at least deterministic within a run, which is what makes the goldens reproducible")
    func theOrderingIsDeterministic() {
        // The draft of this test asserted something stronger and FALSE — that equal difficulty
        // implies equal kana length, so tie order could not move the road. It printed fifty-odd
        // counterexamples on its first run: `difficulty` mixes length with JLPT rank, so a 5-kana
        // N5 word ties a 3-kana N4 one. Recorded rather than deleted, because "I assumed it and it
        // was false" is the more useful half of the finding.
        let ties = Dictionary(grouping: VocabStore.shared.entries, by: \.difficulty)
            .filter { Set($0.value.map(\.kana.count)).count > 1 }
        #expect(!ties.isEmpty,
                "difficulty ties between different lengths have disappeared; if real, the goldens above became contract-guaranteed and this test should be replaced")

        // What IS true, and what the goldens actually rest on: for a fixed input array and a fixed
        // stdlib, `sorted` is deterministic. Asserted over the LENGTH sequence rather than the ids,
        // because lengths are what the distance is made of.
        let first = VocabStore.shared.ordered().map(\.kana.count)
        let second = VocabStore.shared.ordered().map(\.kana.count)
        #expect(first == second, "ordering the same corpus twice gave two different roads")
        #expect(first.count == VocabStore.shared.entries.count)
    }
}
