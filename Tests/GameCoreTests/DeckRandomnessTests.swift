import Testing
import Foundation
import VocabKit
import ReviewKit
@testable import GameCore

/// v1.34 §C3 — the one seam every deck shuffle and form pick goes through, so a headless
/// capture can be reproducible while the shipping app keeps the system generator.
///
/// Each test here was shown red under a named mutation before it was trusted (2026-09-25):
/// - `unseededIsRandom`: the nil branch of `shuffle` made a no-op → `a != b` fails.
/// - `seededIsReproducible`: the seeded branch of `shuffle` calling `shuffle()` → `first == second` fails.
/// - `splitMixKnownAnswer`: one mixing constant changed → the first output fails.
/// - `everyDrawGoesThroughTheSeam`: one `DeckRandomness.shuffle(&pool)` reverted to `pool.shuffle()` → an offender.
@Suite("DeckRandomness: the seam every deck draw goes through")
struct DeckRandomnessTests {

    static func entry(_ i: Int) -> VocabEntry {
        VocabEntry(id: "w\(i)", surface: "語\(i)", kana: "ご", partsOfSpeech: ["n"], jlpt: .n5,
                   meanings: ["en": ["word \(i)"], "zh": ["词 \(i)"]])
    }

    static var thirtyWords: VocabStore { VocabStore(entries: (0 ..< 30).map(entry)) }

    /// With no seed — every launch but a capture — the helpers ARE the system generator.
    /// Two shuffles of thirty elements agree with probability 1/30!, so a repeat is a defect.
    @Test("with no seed the helpers behave like the system generator")
    func unseededIsRandom() {
        #expect(DeckRandomness.seed == nil, "a test left a seed set; every test must restore nil")
        let a = DeckRandomness.shuffled(Array(0 ..< 30))
        let b = DeckRandomness.shuffled(Array(0 ..< 30))
        #expect(a.count == 30 && Set(a) == Set(0 ..< 30), "a shuffle must keep every element once")
        #expect(a != b, "two unseeded shuffles agreed — the nil path is not shuffling")
        var inPlace = Array(0 ..< 30)
        DeckRandomness.shuffle(&inPlace)
        #expect(inPlace != Array(0 ..< 30) && Set(inPlace) == Set(0 ..< 30))
        let picks = (0 ..< 40).map { _ in DeckRandomness.randomElement(Array(0 ..< 1000)) }
        #expect(Set(picks.compactMap { $0 }).count > 1, "forty unseeded picks from a thousand all agreed")
        #expect(DeckRandomness.randomElement([Int]()) == nil)
        var generator = DeckRandomness.Generator()
        #expect(generator.next() != generator.next(), "the unseeded generator repeated itself")
    }

    /// Seeded, the same seed builds the same deck in the same order, and a different seed does
    /// not. This is what lets `Screenshotter` render `game.png` as the same picture twice.
    @Test("the same seed builds the same deck; a different seed does not")
    func seededIsReproducible() {
        let vocab = Self.thirtyWords
        let config = GameSession.Config(newWordCount: 30, reviewWordCount: 0)
        func deck(seed: UInt64) -> [String] {
            DeckRandomness.withSeed(seed) {
                GameSession.make(config: config, vocab: vocab).wordList.map(\.id)
            }
        }
        let first = deck(seed: 7)
        let second = deck(seed: 7)
        let other = deck(seed: 8)
        #expect(first.count == 30, "the deck did not take every word; the comparison below is weaker than it reads")
        #expect(first == second, "the same seed built two different decks")
        #expect(first != other, "two seeds built the same deck")
        #expect(first != vocab.ordered().map(\.id), "the seeded path must still shuffle, not return the store's order")
        #expect(DeckRandomness.seed == nil, "withSeed must restore the previous seed")
        // Picks and the `using:` generator are seeded by the same state.
        let picksA = DeckRandomness.withSeed(3) { (0 ..< 10).map { _ in DeckRandomness.randomElement(Array(0 ..< 1000))! } }
        let picksB = DeckRandomness.withSeed(3) { (0 ..< 10).map { _ in DeckRandomness.randomElement(Array(0 ..< 1000))! } }
        #expect(picksA == picksB)
        let drawA = DeckRandomness.withSeed(3) { var g = DeckRandomness.Generator(); return g.next() }
        let drawB = DeckRandomness.withSeed(3) { var g = DeckRandomness.Generator(); return g.next() }
        #expect(drawA == drawB)
    }

    /// The generator's outputs are published (SplitMix64, Steele/Lea/Flood 2014); pinning them
    /// against values this repository did not compute means a "tidy-up" of the mixer changes
    /// every seeded screen visibly here, not silently in a render comparison months later.
    @Test("SplitMix64 matches the published sequence")
    func splitMixKnownAnswer() {
        var zero = DeckRandomness.SplitMix64(seed: 0)
        #expect(zero.next() == 0xE220_A839_7B1D_CDAF)
        #expect(zero.next() == 0x6E78_9E6A_A1B9_65F4)
        #expect(zero.next() == 0x06C4_5D18_8009_454F)
        var other = DeckRandomness.SplitMix64(seed: 1_234_567)
        #expect(other.next() == 0x599E_D017_FB08_FC85)
    }

    /// A seam one call site bypasses is not a seam: that screen would vary run to run again,
    /// and the render gate would call the noise a regression. Comment-stripped scan of every
    /// GameCore source except the seam itself.
    @Test("every shuffle and pick in GameCore goes through the seam")
    func everyDrawGoesThroughTheSeam() throws {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/GameCore")
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasSuffix(".swift") }
        #expect(files.contains("GameSession.swift") && files.contains("ConjugationSession.swift"),
                "the scan is looking in the wrong place: \(files)")
        let needles = ["shuffle(", "shuffled(", "randomElement(", "SystemRandomNumberGenerator"]
        var routed = 0
        var offenders: [String] = []
        for file in files where file != "DeckRandomness.swift" {
            let source = try String(contentsOf: dir.appendingPathComponent(file), encoding: .utf8)
            for (number, raw) in source.components(separatedBy: "\n").enumerated() {
                let line = raw.trimmingCharacters(in: .whitespaces)
                guard !line.hasPrefix("//") else { continue }
                let code = line.components(separatedBy: "//").first ?? line
                guard needles.contains(where: { code.contains($0) }) else { continue }
                if code.contains("DeckRandomness.") {
                    routed += 1
                } else {
                    offenders.append("\(file):\(number + 1)  \(line)")
                }
            }
        }
        #expect(routed >= 12, "only \(routed) routed draws found — the scan is not reading the sites it exists for")
        #expect(offenders.isEmpty, Comment(rawValue:
            "a deck draw bypasses DeckRandomness, so its screen varies run to run under capture:\n"
            + offenders.joined(separator: "\n")))
    }
}
