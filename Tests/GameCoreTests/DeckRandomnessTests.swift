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
///
/// The C3 review (2026-09-25) found two mutations that list missed, both green against 8fb7b4b.
/// Mutation, 2026-09-25, on the fixed branch (filtered run with `CaptureToolTests` and
/// `AppModelTests`; each restored after): each goes red, and where.
/// - U1, seeded draws that never advance (the seeded `shuffle`, `randomElement` and
///   `Generator.next()` each drawing from a copy of the generator): `seededDrawsAdvance`, on
///   `a != b` (two successive shuffles), `Set(picks).count > 1` and `x != y` (two `next()`s).
/// - U8, a Fisher–Yates over `Int.random(in:)` in place of `DeckRandomness.shuffle(&words)`
///   in `GameSession.makeSaved`: `everyDrawGoesThroughTheSeam`, `offenders.isEmpty`.
///
/// Round 2 (2026-09-27) found mutation A green on the FULL suite: `seeded` given an initialiser
/// (`= SplitMix64(seed: 0x5EED)`), so every shipping launch drew the same first deck while
/// `seed` still read nil. Mutation, 2026-09-27 (`--filter DeckRandomnessTests`; restored
/// byte-for-byte after, shasum c74a172c…): red in `seamStartsUnseeded` (`statics == [ … ]`) and
/// in `shippingLaunchesDiffer` (`first != second`: two child launches drew the same deck).
///
/// `shippingLaunchesDiffer` then compared deck and draw as ONE string, so a fixed unseeded
/// `Generator` draw hid behind the random deck: mutation "unseeded `Generator.next()` returns a
/// constant" (`return 0x1234_5678_9ABC_DEF0`) left it green. It now compares the two separately.
/// Mutation, 2026-09-27 (`--filter DeckRandomnessTests`; restored byte-for-byte after, shasum
/// 176494c7…): red in `shippingLaunchesDiffer` (`first[1] != second[1]`) and in `unseededIsRandom`
/// (`generator.next() != generator.next()`); with the old one-string comparison the launch test
/// stayed green.
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

    /// A seeded generator that never advanced would pass `seededIsReproducible`: the same seed
    /// gives the same answer twice because it gives the same answer always. The review made the
    /// seeded branches draw from a COPY of the generator and every determinism test stayed
    /// green — while under capture every `randomElement` in a screen returned the same index and
    /// the practice re-roll redrew the same passage thirty times. So: two successive seeded
    /// shuffles of thirty elements differ, ten successive seeded picks are not one value, two
    /// successive `Generator.next()` values differ. And `withSeed` hands back the seed it FOUND,
    /// not nil — nested here so the outer lock keeps another test's draw from interleaving.
    @Test("seeded draws advance, and withSeed restores the seed it found")
    func seededDrawsAdvance() {
        let (a, b) = DeckRandomness.withSeed(11) {
            (DeckRandomness.shuffled(Array(0 ..< 30)), DeckRandomness.shuffled(Array(0 ..< 30)))
        }
        #expect(Set(a) == Set(0 ..< 30) && Set(b) == Set(0 ..< 30), "a seeded shuffle must keep every element once")
        #expect(a != b, "two successive seeded shuffles agreed — the seeded generator is not advancing")
        let picks = DeckRandomness.withSeed(11) { (0 ..< 10).map { _ in DeckRandomness.randomElement(Array(0 ..< 1000))! } }
        #expect(Set(picks).count > 1, "ten successive seeded picks from a thousand all agreed")
        let (x, y) = DeckRandomness.withSeed(11) { () -> (UInt64, UInt64) in
            var g = DeckRandomness.Generator()
            let x = g.next()
            return (x, g.next())
        }
        #expect(x != y, "two successive seeded Generator.next() values agreed")
        let restored: (inner: UInt64?, outer: UInt64?) = DeckRandomness.withSeed(99) {
            let inner = DeckRandomness.withSeed(5) { DeckRandomness.seed }
            return (inner, DeckRandomness.seed)
        }
        #expect(restored.inner == 5)
        #expect(restored.outer == 99, "withSeed restored \(String(describing: restored.outer)), not the 99 it found")
        #expect(DeckRandomness.seed == nil, "withSeed must restore the previous seed")
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
    /// GameCore source except the seam itself. The needles are every way Swift and libc offer
    /// to draw: the first list had only the four this tree used, and the review wrote a
    /// Fisher–Yates over `Int.random(in:)` into `makeSaved` that was neither routed nor an
    /// offender.
    @Test("every shuffle and pick in GameCore goes through the seam")
    func everyDrawGoesThroughTheSeam() throws {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/GameCore")
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasSuffix(".swift") }
        #expect(files.contains("GameSession.swift") && files.contains("ConjugationSession.swift"),
                "the scan is looking in the wrong place: \(files)")
        let needles = [".random(", "Int.random", "Bool.random", "Double.random", "randomElement(",
                       "shuffle(", "shuffled(", "SystemRandomNumberGenerator", "arc4random", "drand48"]
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

    // MARK: A shipping launch never draws seeded

    /// The source's lines with every comment removed — `//` and `/* … */`, nested and across
    /// lines — string literals kept, each line trimmed, the line count unchanged. A twin of
    /// `CaptureToolTests.codeLines` (the two test targets share no module), checked there
    /// against a written-out answer.
    static func codeLines(_ source: String) -> [String] {
        let chars = Array(source)
        var out = ""
        var i = 0
        var blockDepth = 0
        var inString = false
        var multiline = false
        func at(_ k: Int) -> Character? { k < chars.count ? chars[k] : nil }
        while i < chars.count {
            let c = chars[i]
            let next = at(i + 1)
            if blockDepth > 0 {
                if c == "/" && next == "*" { blockDepth += 1; i += 2; continue }
                if c == "*" && next == "/" { blockDepth -= 1; i += 2; continue }
                if c == "\n" { out.append(c) }
                i += 1
                continue
            }
            if inString {
                out.append(c)
                if c == "\\", let next { out.append(next); i += 2; continue }
                if multiline {
                    if c == "\"" && next == "\"" && at(i + 2) == "\"" {
                        out += "\"\""; i += 3; inString = false; multiline = false; continue
                    }
                } else if c == "\"" || c == "\n" {
                    inString = false
                }
                i += 1
                continue
            }
            if c == "/" && next == "/" {
                while i < chars.count && chars[i] != "\n" { i += 1 }
                continue
            }
            if c == "/" && next == "*" { blockDepth = 1; i += 2; continue }
            if c == "\"" {
                inString = true
                if next == "\"" && at(i + 2) == "\"" { multiline = true; out += "\"\"\""; i += 3; continue }
            }
            out.append(c)
            i += 1
        }
        return out.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// A shipping launch never sets `seed`, so the shipping app is unchanged only if the seam's
    /// stores START empty. The review gave `seeded` an initialiser (`= SplitMix64(seed: 0x5EED)`,
    /// mutation A): `seed` still read nil, every helper took the seeded branch, every in-process
    /// test stayed green — they compare draws inside one process, and a fixed-seed generator
    /// advances — and every user would have got the same first deck on every launch. So, from
    /// the comment-stripped source: the file declares exactly these statics, the two stores
    /// with NO initialiser, and the only lines that assign either store are the two inside the
    /// `seed` setter (`withSeed` goes through that setter). `shippingLaunchesDiffer` is the
    /// same property measured across two real processes.
    @Test("the seam's stores are declared with no initialiser and assigned only by the seed setter")
    func seamStartsUnseeded() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/GameCore/DeckRandomness.swift")
        let lines = Self.codeLines(try String(contentsOf: file, encoding: .utf8))
        let statics = lines.filter { $0.range(of: #"\bstatic\s+(var|let)\b"#, options: .regularExpression) != nil }
        #expect(statics == [
            "private static let lock = NSRecursiveLock()",
            "nonisolated(unsafe) private static var storedSeed: UInt64?",
            "nonisolated(unsafe) private static var seeded: SplitMix64?",
            "public static var seed: UInt64? {",
        ], Comment(rawValue: "DeckRandomness's static stores changed — a store with an initialiser, or a new one, "
                   + "can make a shipping launch draw seeded:\n" + statics.joined(separator: "\n")))
        guard let seedAt = lines.firstIndex(of: "public static var seed: UInt64? {"),
              let setAt = lines[seedAt...].firstIndex(where: { $0.hasPrefix("set {") }) else {
            Issue.record("the seed property or its setter was not found; the pin is reading nothing")
            return
        }
        var depth = 0
        var setEnd = setAt
        scan: for index in setAt ..< lines.count {
            for character in lines[index] {
                if character == "{" { depth += 1 }
                if character == "}" { depth -= 1 }
            }
            if depth == 0 { setEnd = index; break scan }
        }
        let assignments = lines.indices.filter {
            lines[$0].range(of: #"\b(storedSeed|seeded)\s*=[^=]"#, options: .regularExpression) != nil
        }
        #expect(assignments.map { lines[$0] } == ["storedSeed = newValue", "seeded = newValue.map(SplitMix64.init(seed:))"],
                "the seam's stores are assigned somewhere new: \(assignments.map { "\($0 + 1): \(lines[$0])" })")
        #expect(assignments.allSatisfy { $0 > setAt && $0 < setEnd },
                "a store is assigned outside the seed setter (setter spans lines \(setAt + 1)–\(setEnd + 1))")
    }

    static let probeEnvironment = "NIHONGO_DECK_PROBE_OUT"

    /// The child half of `shippingLaunchesDiffer`, and a no-op in every other run: when the
    /// parent launches this process with `NIHONGO_DECK_PROBE_OUT` set, it writes the process's
    /// FIRST unseeded shuffle of thirty and first `Generator` draw to that file.
    @Test("probe for shippingLaunchesDiffer (a no-op unless launched by it)")
    func shippingLaunchProbe() throws {
        guard let out = ProcessInfo.processInfo.environment[Self.probeEnvironment] else { return }
        let deck = DeckRandomness.shuffled(Array(0 ..< 30))
        var generator = DeckRandomness.Generator()
        let draw = generator.next()
        let line = deck.map(String.init).joined(separator: ",") + " \(draw) seed=\(String(describing: DeckRandomness.seed))"
        try line.write(toFile: out, atomically: true, encoding: .utf8)
    }

    /// Mutation A measured the way a user would meet it: two LAUNCHES. This process's own test
    /// runner is started twice as a child, filtered to `shippingLaunchProbe`, and each child
    /// reports the first deck and generator draw it made with no seed set. Two unseeded launches
    /// agree on a 30-card shuffle with probability 1/30!; a seam that starts seeded makes them
    /// agree always. Cheapest real cross-process check available under `swift test`: the runner
    /// (`swiftpm-testing-helper`) and the test bundle are already built, so a child costs one
    /// process launch and no build. Run any other way (no `--test-bundle-path` in the
    /// arguments), it records an issue rather than passing without measuring.
    @Test("two launches with no seed draw different first decks")
    func shippingLaunchesDiffer() throws {
        if ProcessInfo.processInfo.environment[Self.probeEnvironment] != nil { return }   // we are the child
        let arguments = CommandLine.arguments
        guard let bundleFlag = arguments.firstIndex(of: "--test-bundle-path"), bundleFlag + 1 < arguments.count else {
            Issue.record("not run by swiftpm-testing-helper (\(arguments.first ?? "?")): no child can be launched, so nothing was measured")
            return
        }
        // The parent's own arguments, minus any filter or skip, plus the probe's filter.
        var childArguments: [String] = []
        var index = 1
        while index < arguments.count {
            if arguments[index] == "--filter" || arguments[index] == "--skip" { index += 2; continue }
            childArguments.append(arguments[index])
            index += 1
        }
        childArguments += ["--filter", "shippingLaunchProbe"]
        func launch(_ n: Int) throws -> String {
            let out = FileManager.default.temporaryDirectory
                .appendingPathComponent("NihongoDeckProbe-\(UUID().uuidString).txt")
            defer { try? FileManager.default.removeItem(at: out) }
            let child = Process()
            child.executableURL = URL(fileURLWithPath: arguments[0])
            child.arguments = childArguments
            var environment = ProcessInfo.processInfo.environment
            environment[Self.probeEnvironment] = out.path
            child.environment = environment
            child.standardOutput = FileHandle.nullDevice
            child.standardError = FileHandle.nullDevice
            try child.run()
            child.waitUntilExit()
            #expect(child.terminationStatus == 0, "probe launch \(n) exited \(child.terminationStatus)")
            return (try? String(contentsOf: out, encoding: .utf8)) ?? ""
        }
        // Each report is "<deck> <draw> seed=nil". The deck and the draw are compared SEPARATELY:
        // compared as one string, a random deck would hide a Generator draw that is the same on
        // every launch.
        let first = try launch(1).split(separator: " ").map(String.init)
        let second = try launch(2).split(separator: " ").map(String.init)
        for (n, report) in [(1, first), (2, second)] {
            #expect(report.count == 3 && report[0].split(separator: ",").count == 30
                        && UInt64(report[1]) != nil && report[2] == "seed=nil",
                    "probe launch \(n) reported nothing usable: \(report)")
        }
        guard first.count == 3, second.count == 3 else { return }
        #expect(first[0] != second[0], "two unseeded launches drew the same first deck — a shipping launch is seeded: \(first[0])")
        #expect(first[1] != second[1], "two unseeded launches made the same first Generator draw — a shipping launch's Generator is fixed: \(first[1])")
    }
}
