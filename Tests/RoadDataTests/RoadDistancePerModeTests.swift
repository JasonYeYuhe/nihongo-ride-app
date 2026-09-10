import Testing
import Foundation
import RomajiKana
import VocabKit
import ReviewKit
import GameCore
import SceneryKit

/// How far the road is **in each mode**, measured through the production path (v1.32 §F1).
///
/// ## Why this exists, and why the number it replaces was arrived at the wrong way
///
/// v1.32 §F1 rewrote the first-launch intro to name all six modes instead of three, and
/// `PLAN-WINDOW` constraint 3 requires registering any change to exposure-per-install in
/// `PLAN-STAGE1` §K. The first registration built its table from a **corpus mean**: 7,071 entries
/// average 3.7 kana, distance is `kana.count * 10`, so 37 m per prompt.
///
/// `RoadDistanceTests`' own doc comment had already recorded why that is the wrong population, one
/// directory away: *"new words are not drawn at random. `VocabStore.ordered` sorts by
/// `VocabEntry.difficulty`, whose `0.6 × length` term deals the SHORT words first, so the words a
/// rider actually meets average **2.92 kana, not 3.71**."* PLAN-STAGE1 made the same error once
/// before, and this is it a second time, in the registration written to be careful about it.
///
/// The corpus-mean estimate put journey at 34–56 rides. The measured answer is 48. **Landing
/// inside the band is not the same as being right**, and this project's own rule is that a number
/// arrived at from the wrong population is a coincidence until it is re-derived — so the §K table
/// is now built from these rides.
///
/// ## Why it rides real sessions
///
/// Same reason `RoadDistanceTests` gives: the rule lives in exactly one place
/// (`distanceMeters += kana.count * 10` inside `GameSession`), and re-deriving it here would be
/// the *"one rule written twice will drift"* trap. Each mode is built the way `AppModel.startGame`
/// builds it, typed through the real matcher, and read back.
///
/// ## What this does NOT measure
///
/// Which mode a rider actually picks. That is exposure, it is not on this device, and this app
/// transmits nothing — the point of the registration is that the *spread between* the modes is
/// large, not that anybody has been observed moving across it.
@Suite("The road, measured per mode")
struct RoadDistancePerModeTests {

    /// Types one whole session and returns its distance, or nil if the builder produced nothing.
    ///
    /// A word the matcher refuses is a broken instrument, not a shorter road — so it fails loudly
    /// and names itself, exactly as `RoadDistanceTests.ride` does. A run that silently typed
    /// nothing would report zero metres and read like a working one.
    private static func typeWholeSession(_ session: GameSession) -> Double? {
        guard !session.isFinished else { return nil }
        while let kana = session.currentKana {
            let before = session.wordsCompleted
            for character in KanaRomanizer.romaji(for: kana) { session.input(character) }
            guard session.wordsCompleted == before + 1 else {
                Issue.record("the matcher refused \(kana) — the instrument is broken, not the road")
                return nil
            }
        }
        return session.distanceMeters
    }

    /// Ride one mode until the odometer reaches Kyōto, or until the pool is exhausted.
    ///
    /// `arrived` is carried for the reason `RoadDistanceTests` learned the hard way: a walk that
    /// stopped because the pool ran out is indistinguishable, in a ride count alone, from one that
    /// stopped because it got there.
    private struct Walk { var rides: [Double]; var arrived: Bool }

    private static func rideTo(_ metres: Double, build: (Int) -> GameSession) -> Walk {
        var lifetime = 0.0
        var perRide: [Double] = []
        var exhausted = false
        while lifetime < metres && perRide.count < 2_000 {
            guard let d = typeWholeSession(build(perRide.count)), d > 0 else { exhausted = true; break }
            lifetime += d
            perRide.append(d)
        }
        return Walk(rides: perRide, arrived: !exhausted && lifetime >= metres)
    }

    /// Sentence and dictation share `sentenceSession`, so they ride identically — asserted rather
    /// than assumed, because "same builder" is a claim about today's code.
    private static func sentenceConfig(_ mode: GameMode) -> GameSession.Config {
        var config = GameSession.Config()
        config.mode = mode
        config.level = .n5                  // the app's default level
        config.newWordCount = 5             // AppModel.sentenceRunSize
        config.reviewWordCount = 0
        return config
    }

    static let kyoto = 25_000.0

    /// The N5 typeable-sentence pool: the population `makeSentence` samples from, uniformly.
    ///
    /// This is the number that makes a band legitimate here rather than a weakened check.
    /// `RoadDistanceTests` can assert an exact golden because `VocabStore.ordered` is
    /// deterministic. `makeSentence` calls `pool.shuffle()` (`GameSession.swift:394`), so a
    /// per-ride golden would be asserting a coin toss. What IS exact is the pool's own mean — and
    /// because the draw is uniform, the measured mean must converge to it. That convergence is the
    /// assertion; the ride count is read off it.
    static func sentencePoolMeanKana() -> Double {
        let pool = VocabStore.shared.ordered(level: .n5).filter { $0.isTypeableSentence }
        let lengths = pool.compactMap { $0.exampleKana?.count }
        return Double(lengths.reduce(0, +)) / Double(max(1, lengths.count))
    }

    @Test("a sentence ride converges on the pool it samples, and reaches Kyōto in 34")
    func theRoadInSentenceMode() throws {
        #expect(RideRoute.hasArrivedAtKyoto(lifetimeMetres: Self.kyoto),
                "the road's end moved; every number here is calibrated to it")

        let walk = Self.rideTo(Self.kyoto) { _ in
            GameSession.makeSentence(vocab: .shared, config: Self.sentenceConfig(.sentence))
        }
        let mean = walk.rides.reduce(0, +) / Double(max(1, walk.rides.count))
        print("sentence: \(walk.rides.count) rides, arrived \(walk.arrived), mean \(Int(mean)) m")

        #expect(walk.arrived, "a sentence rider never reached Kyōto — the pool ran out first")

        // The instrument checked against its population. 5 prompts × mean kana × 10 m is what a
        // uniform draw from this pool must average, and the measured rides must land on it.
        // A builder change that narrowed the pool, or a distance-rule change, moves one and not
        // the other.
        let expected = 5 * Self.sentencePoolMeanKana() * 10
        #expect(abs(mean - expected) / expected < 0.15,
                "measured \(Int(mean)) m against a pool predicting \(Int(expected)) m — the builder is not sampling the pool this test thinks it is")
        #expect(abs(Double(walk.rides.count) - Self.kyoto / expected) <= 4,
                "the sentence road is \(walk.rides.count) rides against a predicted \(Int(Self.kyoto / expected))")
    }

    /// The ORDERING the §K registration rests on, which is what constraint 3 is actually about.
    ///
    /// Asserted as an ordering rather than as ratios, because `makeSentence` and `makePractice`
    /// both shuffle: a ratio between two random walks is a number with a confidence interval, and
    /// pinning one would be pinning noise. The ordering is robust to the shuffle and is the claim
    /// — that the mode a rider picks moves exposure-per-install by a factor, not a few percent.
    @Test("practice is much faster to Kyōto than sentence, and sentence than journey")
    func theSpreadBetweenModes() {
        let sentence = Self.rideTo(Self.kyoto) { _ in
            GameSession.makeSentence(vocab: .shared, config: Self.sentenceConfig(.sentence))
        }
        func practiceWalk(_ level: Passage.Level) -> Walk {
            var config = GameSession.Config()
            config.mode = .practice
            config.newWordCount = 12      // AppModel: practicePassages ? 12 : 30
            config.reviewWordCount = 0
            return Self.rideTo(Self.kyoto) { _ in
                GameSession.makePractice(level: level, config: config)
            }
        }
        let med = practiceWalk(.med), hard = practiceWalk(.hard)
        print("practice(med): \(med.rides.count) rides · practice(hard): \(hard.rides.count) rides")

        #expect(sentence.arrived && med.arrived && hard.arrived)
        // `RoadDistanceTests` owns the journey figure (48) and asserts it there; re-walking 120
        // journeys here to compare would double the suite's wall clock for a number that suite
        // already pins. Read as a constant, and named so a reader knows where it comes from.
        let journeyRides = 48
        #expect(hard.rides.count < med.rides.count)
        #expect(med.rides.count < sentence.rides.count)
        #expect(sentence.rides.count < journeyRides,
                "sentence is no longer faster to Kyōto than journey — the §K table is stale")
    }

    /// Dictation and sentence share a builder, so they ride the same road — §K lists them on one
    /// row, and a row that silently stopped describing both would be a claim nothing checks.
    ///
    /// **Not asserted per-ride.** The first version of this test compared the two walks element by
    /// element and failed immediately: `makeSentence` shuffles its pool, so two calls draw two
    /// different samples. Equal draws would have been the surprising outcome. What must agree is
    /// the POPULATION they sample, so the means over a long walk are compared instead.
    @Test("dictation rides the same road as sentence — same builder, same pool")
    func dictationMatchesSentence() {
        func mean(_ mode: GameMode) -> Double {
            let walk = Self.rideTo(Self.kyoto) { _ in
                GameSession.makeSentence(vocab: .shared, config: Self.sentenceConfig(mode))
            }
            #expect(walk.rides.count > 20, "too few rides to average")
            return walk.rides.reduce(0, +) / Double(walk.rides.count)
        }
        let s = mean(.sentence), d = mean(.dictation)
        #expect(abs(s - d) / s < 0.15,
                "sentence averages \(Int(s)) m and dictation \(Int(d)) m — they no longer sample one pool")
    }

    /// The mode that is advertised for the first time by §F1 and moves the odometer by ZERO.
    ///
    /// Verbs runs on `ConjugationSession`, which holds no odometer and has no `distanceMeters` at
    /// all — a conjugation drill is not a ride.
    ///
    /// **What this asserts, exactly: the mode HOLDS NO ODOMETER.** The doc here used to promote
    /// that into "one of the three modes the intro newly names contributes nothing to
    /// exposure-per-install", and §K credited it with the same. That is a different and larger
    /// claim: a mode that moves the odometer by zero still consumes sittings, and a sitting spent
    /// in it is one that does not advance the 25,000 m Kyōto predicate — so it can move
    /// time-to-second-entrance LATER. A source scan for `distanceMeters` cannot see any of that.
    /// §K now states the sign as unknown, and this test is credited with the narrow fact it holds.
    /// (v1.32 pre-submission review.)
    @Test("the conjugation drill is not a ride — it moves the odometer by nothing")
    func conjugationDoesNotMoveTheOdometer() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Sources/GameCore/ConjugationSession.swift"),
            encoding: .utf8)
        #expect(source.count > 5_000, "read \(source.count) bytes — the scan is misdirected")
        #expect(!source.contains("distanceMeters"),
                "ConjugationSession gained a distance; §K's registration says Verbs holds no odometer")
    }
}
