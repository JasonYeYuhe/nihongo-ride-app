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
                             level: JLPTLevel?, reviewWords: Int, on day: Date) -> Double? {
        var config = GameSession.Config()
        config.mode = .journey
        config.level = level
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
    /// A road walked: the per-ride distances, and **whether it actually got there**.
    ///
    /// `arrived` is not bookkeeping. The first version returned only the distances, so a run that
    /// stopped because the WORD POOL RAN OUT was indistinguishable from one that stopped because
    /// it reached Kyōto — and on the default N5 level that is exactly what happens. The test then
    /// compared a ride count from an exhausted pool against a golden taken from an arrival: a
    /// number and a run computed by different predicates, inside the instrument written to catch
    /// that.
    private struct Walk { var rides: [Double]; var arrived: Bool }

    private static func rideTo(_ metres: Double, level: JLPTLevel?, reviewWords: Int) -> Walk {
        let vocab = VocabStore.shared
        // ONE review store across the whole road. It is what makes `seen` grow, so each ride
        // introduces the NEXT twelve words rather than the same twelve forever — a fresh store per
        // ride would report a 150 m ride to infinity and look perfectly reasonable doing it.
        var review = ReviewStore()
        var lifetime = 0.0
        var perRide: [Double] = []
        var day = Date(timeIntervalSince1970: 0)
        var exhausted = false
        while lifetime < metres && perRide.count < 5_000 {
            guard let d = ride(vocab: vocab, review: &review, level: level,
                               reviewWords: reviewWords, on: day),
                  d > 0 else { exhausted = true; break }
            lifetime += d
            perRide.append(d)
            // Days advance so review cards actually come due; without it the "with reviews" path
            // would be a fiction that quietly measured the new-words-only path.
            day = day.addingTimeInterval(60 * 60 * 24)
        }
        return Walk(rides: perRide, arrived: !exhausted && lifetime >= metres)
    }

    @Test("the first ride is 150 m, which is where RideRoute's ~150 m came from")
    func theFirstRide() {
        let walk = Self.rideTo(200, level: .n5, reviewWords: 0)
        #expect(walk.rides.first == 150,
                "the first twelve words are nine single kana plus みず・あさ・よる")
    }

    @Test("on the DEFAULT level a rider reaches Kyōto in 48 rides — and only because of reviews")
    func theRoadToKyotoOnTheDefaultLevel() throws {
        // **N5, because that is what a fresh install actually rides.** `AppSettings`'s default
        // `selectedLevel` is 5 (Sources/SettingsKit/AppSettings.swift:86) and `startGame` passes
        // it straight into `GameSession.Config.level`. The first version of this suite measured
        // the MIXED corpus — a population no default rider is in — which is the same rule this
        // file's own header corrects PLAN-STAGE1 for, committed one level down.
        let kyoto = try #require(RideRoute.tokaidoStages.last).startMetres
        #expect(kyoto == 25_000, "the road's end moved; every number below is calibrated to it")

        let withReviews = Self.rideTo(kyoto, level: .n5, reviewWords: 8)
        let newOnly = Self.rideTo(kyoto, level: .n5, reviewWords: 0)
        let meanMixed = withReviews.rides.reduce(0, +) / Double(withReviews.rides.count)

        print("""
              N5 (the default): \(withReviews.rides.count) rides with reviews, arrived \(withReviews.arrived)
              N5 new words only: \(newOnly.rides.count) rides, arrived \(newOnly.arrived)
              mean ride with reviews: \(Int(meanMixed)) m · first ride: \(Int(newOnly.rides[0])) m
              """)

        #expect(withReviews.arrived)
        #expect(withReviews.rides.count == 48)
        #expect(meanMixed > 520 && meanMixed < 545)

        // **The finding this parameterisation surfaced, and it is a product fact rather than a
        // test detail:** the whole N5 pool is 646 words ≈ 20.8 km, so a rider who never leaves the
        // default level CANNOT reach Kyōto on new words at all. They get there on SRS repetitions,
        // which means anything changing how often words come back for review moves the road.
        #expect(!newOnly.arrived,
                "N5's new-word pool now reaches 25 km on its own — the corpus grew, and the claim that reviews carry the last stretch is no longer true")
    }

    @Test("a rider who switches to the mixed pool takes 72 rides on new words alone")
    func theRoadToKyotoMixed() throws {
        let kyoto = try #require(RideRoute.tokaidoStages.last).startMetres
        let newOnly = Self.rideTo(kyoto, level: nil, reviewWords: 0)
        let meanNew = newOnly.rides.reduce(0, +) / Double(newOnly.rides.count)
        #expect(newOnly.arrived)
        #expect(newOnly.rides.count == 72)
        #expect(meanNew > 340 && meanNew < 360)
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
