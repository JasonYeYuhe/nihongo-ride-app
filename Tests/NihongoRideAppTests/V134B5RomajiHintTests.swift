import Testing
import Foundation
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
import RomajiKana
@testable import NihongoRideApp

/// v1.34 §B5 — the ride card's romaji hint wraps instead of being cut.
///
/// **What these can and cannot prove, stated first.** The defect was seen on a simulator: a
/// sentence's hint drawn on one line with "…" and left so as the rider typed. `swift test` has no
/// iPhone and `ImageRenderer` ignores Dynamic Type, so what is measured here is the hint's own
/// layout, replicated with its full modifier chain (section 4 pins the replica to the source) at
/// the card widths the code's paddings give a phone, at 18 and 14pt and at the AX1 cap the game
/// screens use (the size × 28/17, as `V133GRideAndDrillLayoutTests` scales). Whether the card
/// around it keeps its other rows when the hint takes two or three lines is the simulator's
/// question, not this file's.
///
/// **Addendum, 2026-09-27 (review round 2): the card, measured once, outside this file.** The ride
/// was hosted on macOS at 402pt with the phone layout forced by a temporary patch (reverted; the
/// probe is not committed, because the phone layout cannot be reached here without one), a
/// sentence ride, assistance on, rows read with GeometryReader. The card does not grow for the
/// hint — SwiftUI takes the extra lines from the card's other rows, even with 4,000pt of screen:
///
/// * Default size, keyboard up (521pt of screen; 476 with a suggestion bar), 56/67/76
///   characters: the card stays 338 / 342 / 338pt at 521pt, as in 1.33; the hint goes from 1.33's
///   one line (17pt, cut) to two whole lines (34pt), and the typed-romaji row pays — 24 → 17–18pt
///   before typing, and late in a sentence from 1.33's two lines (26–38pt) to one line at its own
///   0.5 floor (13pt). In that line 54 typed characters were measured whole and 65 lost their last
///   9, so near the end of a sentence longer than about 55 characters (88 in the corpus; 24 longer
///   than 59) the last typed characters are cut. Three lines and two cost the same here: at 14pt
///   every corpus hint needs two.
/// * Default size, keyboard down (778pt), 56 characters: three lines (872f14d) took the example
///   sentence from 77 to 58pt — a line cut — and the kana from 1.33's 102 to 90pt; two lines (this
///   file's chain) leave the example whole and the kana at 93pt (shrunk, whole).
/// * AX1 cap, keyboard up: at 476pt three lines halved the surface line (62 → 31pt) for all three
///   hints; two lines keep it for the 67- and 76-character ones (they shrink to fit) and still
///   halve it for the 56. At 521pt two lines keep the kana whole where 1.33 squeezed it (56
///   characters: 120pt against 1.33's 105) and three took it to 96.
/// * AX1 cap, keyboard down (778pt): the card is ~300pt over budget in 1.33 already (surface,
///   gloss, example, typed and kana all squeezed, the hint cut to one line). With two or three hint
///   lines the kana row drops from 66 to 33pt (two lines to one) for the 56- and 67-character
///   hints; the 76-character one keeps 66.
///
/// So the chain takes at most two lines, not three: the example's cut and the AX1 surface squeeze
/// were what three lines cost, and a lower line limit or a lower floor were the only levers taken.
/// The typed-row cut late in the 24 longest sentences and the AX1 keyboard-down kana are what two
/// lines still cost; one line would cost them nothing and shrink every hint over 40 characters
/// (2,007 sentences) to 10pt or less, so they are reported rather than traded.
///
/// **The instrument.** A character is DRAWN if replacing it with "#" changes the rendered pixels,
/// and the rows that change say which line it is on. So "every character is drawn, on two lines"
/// is read off the pixels, not inferred from a height. Its control is 1.33's chain offered one
/// line's height — the device's failure — which must lose characters here, or the instrument is
/// blind.
@Suite("v1.34 §B5: the ride card's romaji hint wraps instead of being cut")
struct V134B5RomajiHintTests {

    // MARK: 1. Where the breaks go

    /// Mutation, 2026-09-27: `joined(separator: "")` in place of U+200B goes red here (and in the
    /// layout tests below, where the 56-character hint shrinks on the 402pt card).
    @Test("from 20 characters a hint gets U+200B between every two characters, and below that it is unchanged")
    func breakOpportunities() {
        let nineteen = "watashihagakuseides"
        #expect(nineteen.count == 19)
        #expect(RomajiHintLayout.breakable(nineteen) == "watashihagakuseides")
        #expect(RomajiHintLayout.breakable("kashikomarimashita") == "kashikomarimashita")
        #expect(RomajiHintLayout.breakable("") == "")

        let twenty = "watashihagakuseidesu"
        #expect(twenty.count == 20)
        let broken = RomajiHintLayout.breakable(twenty)
        #expect(broken == "w\u{200B}a\u{200B}t\u{200B}a\u{200B}s\u{200B}h\u{200B}i\u{200B}h\u{200B}a\u{200B}g\u{200B}a\u{200B}k\u{200B}u\u{200B}s\u{200B}e\u{200B}i\u{200B}d\u{200B}e\u{200B}s\u{200B}u")
        #expect(broken.filter { $0 == "\u{200B}" }.count == 19)
        #expect(broken.count == 39, "U+200B is its own grapheme, so the characters are 20 + 19")
        #expect(String(broken.filter { $0 != "\u{200B}" }) == twenty, "the plain romaji is recoverable")
        // Apostrophes and long-vowel dashes are characters like any other.
        #expect(RomajiHintLayout.breakable("su-pa-de kin'youbini") == "s\u{200B}u\u{200B}-\u{200B}p\u{200B}a\u{200B}-\u{200B}d\u{200B}e\u{200B} \u{200B}k\u{200B}i\u{200B}n\u{200B}'\u{200B}y\u{200B}o\u{200B}u\u{200B}b\u{200B}i\u{200B}n\u{200B}i")
    }

    // MARK: 2. Why 20 — measured from the corpus and the line

    struct Corpus {
        let entries: Int
        /// Every entry's word romaji (`KanaRomanizer` over `kana`).
        let words: [String]
        /// Every typeable sentence's romaji (`KanaRomanizer` over `exKana`, where `exJP` and
        /// `exKana` are both non-empty — `VocabEntry.isTypeableSentence`).
        let sentences: [String]
        /// The same sentences' kana, in the same order.
        let sentenceKana: [String]
    }

    /// Read from the raw JSON the app bundles, not through `VocabStore`, so the population is the
    /// files' and not whatever a loader keeps.
    static let corpus: Corpus = {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var entries = 0
        var words: [String] = []
        var sentences: [String] = []
        var sentenceKana: [String] = []
        for level in 1...5 {
            let url = root.appendingPathComponent("Sources/VocabKit/Resources/n\(level).json")
            guard let data = try? Data(contentsOf: url),
                  let array = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { continue }
            entries += array.count
            for entry in array {
                if let kana = entry["kana"] as? String { words.append(KanaRomanizer.romaji(for: kana)) }
                if let jp = entry["exJP"] as? String, !jp.isEmpty,
                   let kana = entry["exKana"] as? String, !kana.isEmpty {
                    sentences.append(KanaRomanizer.romaji(for: kana))
                    sentenceKana.append(kana)
                }
            }
        }
        return Corpus(entries: entries, words: words, sentences: sentences, sentenceKana: sentenceKana)
    }()

    /// `RomajiHintLayout.breakableFrom`'s comment, read back: the longest word, the sentences below
    /// the threshold, and the corpus's longest hint — which section 3 lays out.
    @Test("the corpus facts the threshold's comment states")
    func corpusFacts() throws {
        let corpus = Self.corpus
        #expect(corpus.entries == 7_071 && corpus.words.count == 7_071, "entries \(corpus.entries)")
        #expect(corpus.sentences.count == 6_724, "typeable sentences \(corpus.sentences.count)")

        let wordLengths = corpus.words.map(\.count).sorted(by: >)
        #expect(Array(wordLengths.prefix(2)) == [18, 14], "longest words \(wordLengths.prefix(2))")
        #expect(corpus.words.filter { $0.count == 18 } == ["kashikomarimashita"])

        let sentenceLengths = corpus.sentences.map(\.count)
        #expect(sentenceLengths.min() == 8 && sentenceLengths.max() == 67,
                "sentence hints \(sentenceLengths.min() ?? -1)–\(sentenceLengths.max() ?? -1)")
        #expect(sentenceLengths.filter { $0 < 20 }.count == 701)
        #expect(corpus.sentences.contains(Self.longest) && Self.longest.count == 67)
        #expect(corpus.sentences.contains(Self.observed) && Self.observed.count == 56)

        // "One token": no sentence's romaji has a space — the arrow's is the only one in the hint.
        #expect(corpus.sentences.filter { $0.contains(" ") }.isEmpty)
        // The longest READING is 38 kana (not the longest romaji: that one is 36 kana), so the
        // margin hint's 76 characters — two per kana — is past every sentence in the corpus.
        let kanaLengths = corpus.sentenceKana.map(\.count)
        #expect(kanaLengths.max() == 38, "longest reading \(kanaLengths.max() ?? -1) kana")
        #expect(corpus.sentenceKana[try #require(corpus.sentences.firstIndex(of: Self.longest))].count == 36)
        #expect(corpus.sentenceKana[try #require(corpus.sentences.firstIndex(of: Self.observed))].count == 30)
        #expect(Self.margin.count == 76 && sentenceLengths.allSatisfy { $0 < Self.margin.count })
    }

    #if canImport(AppKit)
    /// The threshold is pinned from both sides by measurement: above the longest word (so every
    /// word's hint is 1.33's, byte for byte), and exactly the shortest hint that outgrows the
    /// narrowest phone card's line at the default size (so every hint that can need a break has
    /// them, and none that fits every phone's line gets them). The line is measured with SwiftUI's
    /// own layout of 1.33's Text: the first length at which "→ " + hint takes a second line.
    /// Card widths are the code's: the phone's outer padding 16 with the keyboard down, the card's
    /// 24 — 402pt → 322, 375pt → 295, 320pt Display Zoom → 240.
    /// Mutations, 2026-09-27: `breakableFrom = 21` and `= 19` each go red here, on the measured
    /// line (`breakableFrom == narrowest`), not only on section 1's written-out strings.
    @MainActor
    @Test("the threshold is above every word and exactly where a hint first outgrows the narrowest phone's line")
    func thresholdIsMeasured() {
        func firstOverflow(_ width: CGFloat) -> Int? {
            let one = Self.laidOut(Self.hint133("m", points: 18), width: width, height: nil).height
            return (1...60).first { n in
                Self.laidOut(Self.hint133(String(repeating: "m", count: n), points: 18), width: width, height: nil).height > one
            }
        }
        #expect(firstOverflow(322) == 27, "402pt phone: \(String(describing: firstOverflow(322)))")
        #expect(firstOverflow(295) == 25, "375pt phone: \(String(describing: firstOverflow(295)))")
        let narrowest = firstOverflow(240)
        #expect(narrowest == 20, "320pt Display Zoom: \(String(describing: narrowest))")

        let longestWord = Self.corpus.words.map(\.count).max() ?? .max
        #expect(RomajiHintLayout.breakableFrom > longestWord,
                "a word of \(longestWord) characters would get break opportunities")
        #expect(RomajiHintLayout.breakableFrom == narrowest,
                "breakableFrom \(RomajiHintLayout.breakableFrom); the shortest hint that outgrows a phone's line is \(String(describing: narrowest))")

        // The advance the comment states, and a zero-width space's: none.
        for (points, advance) in [(18, 11.126953125), (14, 8.654296875)] as [(CGFloat, CGFloat)] {
            let font = NSFont.monospacedSystemFont(ofSize: points, weight: .regular)
            func width(_ s: String) -> CGFloat { NSAttributedString(string: s, attributes: [.font: font]).size().width }
            #expect(width("a") == advance && width("→") == advance, "\(points)pt: SF Mono advances \(width("a"))")
            #expect(width("a\u{200B}a") == 2 * advance, "\(points)pt: U+200B has an advance")
        }
    }
    #endif

    // MARK: 3. The layout, measured

    /// The corpus's longest hint (67 characters, 36 kana).
    static let longest = "karehakaigainodaigakudekeizaigakunogakushigouwomigotonishutokushita"
    /// A 30-kana, 56-character N1 hint — the length the simulator showed cut on 2026-09-25.
    static let observed = "tsuginoteireikaiginogidaiwojizennime-rudeoshiraseshimasu"
    /// A margin past the corpus: 76 characters, two for each kana of its longest reading (38).
    static let margin = String(repeating: "shinkansen", count: 8).prefix(76).description

    /// The shipped chain (section 4 pins it), with the font `scaledSystemFont` resolves to.
    @MainActor
    static func hint(_ romaji: String, points: CGFloat, lineLimit: Int = 2) -> some View {
        Text("→ \(RomajiHintLayout.breakable(romaji))")
            .font(.system(size: points, weight: .regular, design: .monospaced))
            .foregroundStyle(Theme.dim)
            .lineLimit(lineLimit)
            .minimumScaleFactor(0.45)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 872f14d's chain — three lines at a 0.6 floor — which review round 2 replaced; kept to state
    /// what the two-line chain gives up and keeps.
    @MainActor
    static func hintThreeLines(_ romaji: String, points: CGFloat) -> some View {
        Text("→ \(RomajiHintLayout.breakable(romaji))")
            .font(.system(size: points, weight: .regular, design: .monospaced))
            .foregroundStyle(Theme.dim)
            .lineLimit(3)
            .minimumScaleFactor(0.6)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The same chain with the plain romaji — what the hint would be without its break opportunities.
    @MainActor
    static func hintUnbroken(_ romaji: String, points: CGFloat) -> some View {
        Text("→ \(romaji)")
            .font(.system(size: points, weight: .regular, design: .monospaced))
            .foregroundStyle(Theme.dim)
            .lineLimit(2)
            .minimumScaleFactor(0.45)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 1.33's chain, as `git show main:Sources/NihongoRideApp/GameView.swift` has it.
    @MainActor
    static func hint133(_ romaji: String, points: CGFloat) -> some View {
        Text("→ \(romaji)")
            .font(.system(size: points, weight: .regular, design: .monospaced))
            .foregroundStyle(Theme.dim)
    }

    static let ax1: CGFloat = 28 / 17

    #if canImport(AppKit)
    @MainActor
    static func laidOut<V: View>(_ view: V, width: CGFloat, height: CGFloat?) -> CGSize {
        NSHostingController(rootView: view).sizeThatFits(in: CGSize(width: width, height: height ?? 10_000))
    }

    struct Bitmap: Equatable {
        let width: Int
        let height: Int
        let bytes: [UInt8]
    }

    /// The view at 2× on black, offered `width` and `height` (nil: as much height as it wants).
    @MainActor
    static func render<V: View>(_ view: V, width: CGFloat, height: CGFloat?) -> Bitmap? {
        let renderer = ImageRenderer(content: view.background(Color.black))
        renderer.proposedSize = ProposedViewSize(width: width, height: height)
        renderer.scale = 2
        guard let image = renderer.cgImage else { return nil }
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        guard let context = CGContext(data: &bytes, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Bitmap(width: image.width, height: image.height, bytes: bytes)
    }

    struct Drawn {
        /// Per character of the romaji, the pixel rows that change when it becomes "#"; nil if none.
        let rows: [ClosedRange<Int>?]
        /// The rendered height in points.
        let height: CGFloat
        var missing: [Int] { rows.indices.filter { rows[$0] == nil } }
        /// Lines, counted from the rows each drawn character occupies, in reading order.
        var lines: Int {
            var count = 0
            var bottom = Int.min
            for range in rows.compactMap({ $0 }) where range.lowerBound > bottom {
                count += 1
                bottom = range.upperBound
            }
            return count
        }
    }

    @MainActor
    static func drawn<V: View>(_ romaji: String, width: CGFloat, height: CGFloat?,
                               _ view: (String) -> V) -> Drawn? {
        guard let base = render(view(romaji), width: width, height: height) else { return nil }
        let characters = Array(romaji)
        var rows: [ClosedRange<Int>?] = []
        for index in characters.indices {
            var changed = characters
            changed[index] = "#"
            guard let other = render(view(String(changed)), width: width, height: height),
                  other.width == base.width, other.height == base.height else { rows.append(nil); continue }
            var top = Int.max, bottom = -1
            let stride = base.width * 4
            base.bytes.withUnsafeBytes { a in
                other.bytes.withUnsafeBytes { b in
                    for row in 0..<base.height where memcmp(a.baseAddress! + row * stride, b.baseAddress! + row * stride, stride) != 0 {
                        top = min(top, row); bottom = max(bottom, row)
                    }
                }
            }
            rows.append(bottom < 0 ? nil : top...bottom)
        }
        return Drawn(rows: rows, height: CGFloat(base.height) / 2)
    }

    /// The instrument's control, and the defect reproduced: 1.33's hint, offered one line's height
    /// — as the card offered it on the simulator — takes it and loses the rest of the token; offered
    /// room, it wraps. And the instrument sees a line limit: the shipped chain at `lineLimit(1)`
    /// loses characters too.
    @MainActor
    @Test("control: 1.33's hint offered one line is cut, and the instrument sees it")
    func instrumentControl() throws {
        let line = Self.laidOut(Self.hint133("m", points: 18), width: 322, height: nil).height
        #expect(line == 21, "one line of the 18pt hint is \(line)pt")
        let cut = try #require(Self.drawn(Self.observed, width: 322, height: line) { Self.hint133($0, points: 18) })
        #expect(cut.missing.count > 20 && cut.lines == 1,
                "1.33 offered one line: \(cut.missing.count) characters not drawn, \(cut.lines) line(s)")
        let roomy = try #require(Self.drawn(Self.observed, width: 322, height: nil) { Self.hint133($0, points: 18) })
        #expect(roomy.missing.isEmpty, "1.33 offered room still lost \(roomy.missing)")
        // The margin hint, not the observed: at the 0.45 floor (review round 2) one line of 322pt
        // holds the observed 56 characters shrunk, and the control must be a hint it cannot hold.
        let oneLine = try #require(Self.drawn(Self.margin, width: 322, height: nil) { Self.hint($0, points: 18, lineLimit: 1) })
        #expect(!oneLine.missing.isEmpty, "control: lineLimit(1) should cut the hint")
    }

    /// Every character of the observed, the longest and the margin hint is drawn, on two lines —
    /// never three (review round 2) — at the card widths a 402pt phone gives: 322pt at 18pt with
    /// the keyboard down, 354pt at 14pt with it up (402 − 2×10 − 2×14), and 346pt; all offered one
    /// line's height as the card offered it, at the default size and the AX1 cap. With the keyboard
    /// up at the default size — the phone's usual state — all three are drawn at FULL size (two
    /// lines of 14pt hold 81 characters). On the 18pt cards the 67- and 76-character hints shrink to
    /// fit two lines: that is the price of the second line the card no longer gives (the file's
    /// header has the card measured).
    /// Mutations, 2026-09-27: U+200B → nothing is red here (the longest hint at 354pt keeps its
    /// romaji on one shrunk line after the arrow); `.lineLimit(2)` → `.lineLimit(3)` or `(1)` in the
    /// source is red in section 4's pin, which is what ties this replica to the source.
    @MainActor
    @Test("sentence hints are drawn whole, on two lines, at the default size and the AX1 cap")
    func sentenceHintsAreWhole() throws {
        for (points, width) in [(18, 322), (18, 346), (14, 354)] as [(CGFloat, CGFloat)] {
            for scale in [1, Self.ax1] {
                let size = points * scale
                let line = Self.laidOut(Self.hint133("m", points: size), width: width, height: nil).height
                for romaji in [Self.observed, Self.longest, Self.margin] {
                    let label = "\(romaji.count) characters, \(size)pt in \(width)pt"
                    let result = try #require(Self.drawn(romaji, width: width, height: line) { Self.hint($0, points: size) })
                    #expect(result.missing.isEmpty, "\(label): characters \(result.missing) not drawn")
                    #expect(result.lines == 2, "\(label): \(result.lines) line(s)")
                    #expect(result.height <= 2 * line + 0.5, "\(label): height \(result.height), taller than two lines of \(line)")
                    if scale == 1 && points == 14 {
                        #expect(abs(result.height - 2 * line) < 0.5,
                                "\(label): height \(result.height), two lines of \(line) — shrunk with the keyboard up at the default size")
                    }
                    if scale == 1 && points == 18 && romaji.count > 56 {
                        #expect(result.height < 2 * line - 0.5,
                                "\(label): height \(result.height) — two full lines of \(line) hold it; update the comment")
                    }
                }
            }
        }
    }

    /// Review round 2: what 872f14d's three lines at a 0.6 floor took, against the two lines that
    /// replaced them — one line of the card on the 322pt keyboard-down card at the default size,
    /// which the card took from its other rows (the file's header). And the two-line chain keeps
    /// every hint whole that the three-line chain did, down to 240pt at the default size.
    @MainActor
    @Test("two lines, not three: one line fewer from the card, and nothing that was whole is cut")
    func twoLinesNotThree() throws {
        let line = Self.laidOut(Self.hint133("m", points: 18), width: 322, height: nil).height
        let three = Self.laidOut(Self.hintThreeLines(Self.margin, points: 18), width: 322, height: line).height
        let two = Self.laidOut(Self.hint(Self.margin, points: 18), width: 322, height: line).height
        #expect(three == 3 * line, "872f14d's chain: \(three)pt")
        #expect(two <= 2 * line, "this chain: \(two)pt")
        for (points, width) in [(18, 322), (18, 346), (14, 354), (18, 240), (14, 272)] as [(CGFloat, CGFloat)] {
            for scale in [1, Self.ax1] {
                let size = points * scale
                let one = Self.laidOut(Self.hint133("m", points: size), width: width, height: nil).height
                for romaji in [Self.observed, Self.longest, Self.margin] {
                    let before = try #require(Self.drawn(romaji, width: width, height: one) { Self.hintThreeLines($0, points: size) })
                    guard before.missing.isEmpty else { continue }
                    let after = try #require(Self.drawn(romaji, width: width, height: one) { Self.hint($0, points: size) })
                    #expect(after.missing.isEmpty,
                            "\(romaji.count) characters, \(size)pt in \(width)pt: whole in three lines at 0.6, \(after.missing) cut in two at 0.45")
                }
            }
        }
    }

    /// The narrowest cards. A 320pt Display Zoom phone (240pt) at the default size fits every
    /// corpus hint whole, on two shrunk lines; a Slide Over iPad window (320 − 2×32 − 2×24 = 208pt)
    /// fits the longest word, which breaks at the arrow's space. The limit, measured and stated: at
    /// the AX1 cap on the 240pt card the corpus's longest hint loses characters even at the 0.45
    /// floor, as it did in three lines at 0.6, while the observed 56-character one is whole.
    @MainActor
    @Test("the narrowest cards: whole at the default size; the longest hint's limit at AX1 on 240pt, stated")
    func narrowestCards() throws {
        let line = Self.laidOut(Self.hint133("m", points: 18), width: 240, height: nil).height
        for romaji in [Self.observed, Self.longest] {
            let result = try #require(Self.drawn(romaji, width: 240, height: line) { Self.hint($0, points: 18) })
            #expect(result.missing.isEmpty && result.lines == 2, "\(romaji.count) at 240pt: missing \(result.missing), \(result.lines) lines")
        }
        let word = try #require(Self.drawn("kashikomarimashita", width: 208, height: line) { Self.hint($0, points: 18) })
        #expect(word.missing.isEmpty && word.lines == 1, "the longest word at 208pt: missing \(word.missing), \(word.lines) line(s) of romaji")

        let big = 18 * Self.ax1
        let bigLine = Self.laidOut(Self.hint133("m", points: big), width: 240, height: nil).height
        let observed = try #require(Self.drawn(Self.observed, width: 240, height: bigLine) { Self.hint($0, points: big) })
        #expect(observed.missing.isEmpty, "AX1, 240pt, 56 characters: missing \(observed.missing)")
        let longest = try #require(Self.drawn(Self.longest, width: 240, height: bigLine) { Self.hint($0, points: big) })
        #expect(!longest.missing.isEmpty,
                "AX1, 240pt, 67 characters is now whole — the limit this test states has moved; update the comment")
    }

    /// Where no break is needed nothing moves, so the default size cannot change for any hint that
    /// fits its line: the longest word, a word, the shortest sentence (below the threshold, so
    /// untouched), and a 20- and a 25-character hint (above it, so carrying U+200B) render
    /// byte for byte as 1.33's chain, offered room or one line, at the three card widths.
    /// Measured 2026-09-26 and again 2026-09-27: `.multilineTextAlignment(.center)` added to the
    /// chain fails 26 of these 30 comparisons — centring a one-line Text in its own rounded-up width moves its glyphs by a
    /// fraction of a point — so the chain keeps 1.33's alignment, and section 4 pins it without one.
    @MainActor
    @Test("a hint that fits its line renders byte for byte as 1.33's")
    func fittingHintsAreUnchanged() throws {
        let hints = ["kashikomarimashita", "mizu", "hawonuku", "watashihagakuseidesu", "tsuginoteireikaiginogidai"]
        #expect(hints.map(\.count) == [18, 4, 8, 20, 25])
        for (points, width) in [(18, 322), (18, 346), (14, 354)] as [(CGFloat, CGFloat)] {
            let line = Self.laidOut(Self.hint133("m", points: points), width: width, height: nil).height
            for romaji in hints {
                for height in [nil, line] as [CGFloat?] {
                    let old = try #require(Self.render(Self.hint133(romaji, points: points), width: width, height: height))
                    let new = try #require(Self.render(Self.hint(romaji, points: points), width: width, height: height))
                    #expect(old == new, "\(romaji) at \(points)pt in \(width)pt, offered \(String(describing: height)): the pixels moved — \(old.width)×\(old.height) against \(new.width)×\(new.height), \(zip(old.bytes, new.bytes).filter { $0 != $1 }.count) bytes differ")
                }
            }
        }
        // Review round 2: the words, on every phone card at the default size — 375pt (295 keyboard
        // down, 327 up) and 320pt Display Zoom (240, 272), where the longest word's 222.5pt still
        // fits one line.
        for (points, width) in [(18, 295), (18, 240), (14, 327), (14, 272)] as [(CGFloat, CGFloat)] {
            let line = Self.laidOut(Self.hint133("m", points: points), width: width, height: nil).height
            for romaji in ["kashikomarimashita", "mizu", "hawonuku"] {
                for height in [nil, line] as [CGFloat?] {
                    let old = try #require(Self.render(Self.hint133(romaji, points: points), width: width, height: height))
                    let new = try #require(Self.render(Self.hint(romaji, points: points), width: width, height: height))
                    #expect(old == new, "\(romaji) at \(points)pt in \(width)pt, offered \(String(describing: height)): the pixels moved")
                }
            }
        }
        // And where the comment says it does NOT hold: a word whose hint needs a second line — the
        // longest at the AX1 cap (366.5pt on the 322pt card), and in the 208pt Slide Over card
        // offered one line's height, where 1.33 cut it (offered room, both break at the arrow).
        #expect(Self.render(Self.hint133("kashikomarimashita", points: 18 * Self.ax1), width: 322, height: nil)
                != Self.render(Self.hint("kashikomarimashita", points: 18 * Self.ax1), width: 322, height: nil),
                "the longest word at the AX1 cap renders as 1.33's; the comment's limit has moved")
        let slideOverLine = Self.laidOut(Self.hint133("m", points: 18), width: 208, height: nil).height
        #expect(Self.render(Self.hint133("kashikomarimashita", points: 18), width: 208, height: slideOverLine)
                != Self.render(Self.hint("kashikomarimashita", points: 18), width: 208, height: slideOverLine),
                "the longest word in the 208pt card renders as 1.33's; the comment's limit has moved")
        // Control: the comparison sees a one-character difference.
        #expect(Self.render(Self.hint133("mizu", points: 18), width: 322, height: nil)
                != Self.render(Self.hint133("mizo", points: 18), width: 322, height: nil))
    }

    /// Why the break opportunities, measured: without them the same chain has only the space after
    /// the arrow and the hyphen of "jizennime-rude", and the observed hint on the 322pt card shrinks
    /// to fit two lines instead of filling them — what the U+200B mutation above turns the shipped
    /// hint into.
    @MainActor
    @Test("without its break opportunities the observed hint shrinks on the 402pt phone's card")
    func breaksKeepTheHintFullSize() {
        let line = Self.laidOut(Self.hint133("m", points: 18), width: 322, height: nil).height
        let broken = Self.laidOut(Self.hint(Self.observed, points: 18), width: 322, height: line).height
        let unbroken = Self.laidOut(Self.hintUnbroken(Self.observed, points: 18), width: 322, height: line).height
        #expect(broken == 2 * line, "with U+200B: \(broken)pt")
        #expect(unbroken < 2 * line - 5, "without: \(unbroken)pt against two lines of \(line)")
    }

    /// Review round 2: a hyphen is a break opportunity too — `KanaRomanizer` writes ー as "-" — so
    /// the comments say "the space after the arrow and a hyphen", not "only the space". Without
    /// U+200B, "→ " + 20 a + "-" + 20 b on a 270pt line breaks after the hyphen into two full
    /// lines (23 characters, 255.9pt, then 20), while the same with "x" or an apostrophe in its place
    /// has no break and shrinks.
    @MainActor
    @Test("a hyphen is a break opportunity; a letter or an apostrophe is not")
    func hyphenIsABreak() {
        let line = Self.laidOut(Self.hint133("m", points: 18), width: 270, height: nil).height
        func laid(_ joint: String) -> CGSize {
            Self.laidOut(Self.hintUnbroken(String(repeating: "a", count: 20) + joint + String(repeating: "b", count: 20), points: 18),
                         width: 270, height: line)
        }
        let hyphen = laid("-")
        #expect(hyphen.height == 2 * line && abs(hyphen.width - 23 * 11.126953125) < 0.5,
                "with a hyphen: \(hyphen) — expected two full lines, the first 23 characters wide")
        for joint in ["x", "'"] {
            let other = laid(joint)
            #expect(other.height < 2 * line - 0.5, "with \(joint): \(other) — expected no break, so shrunk")
        }
    }
    #endif

    // MARK: 4. The source

    /// The hint's chain in `WordCard`, comment-stripped, line for line — the replica above is this
    /// chain with `scaledSystemFont` resolved — and its VoiceOver label built from the PLAIN romaji,
    /// so VoiceOver reads 1.33's words. `breakable` is called once in shipped code, there.
    /// Mutations, 2026-09-27, each red here: `.lineLimit(3)` → `.lineLimit(1)`; (review round 2)
    /// `.lineLimit(2)` → `.lineLimit(3)`; `.minimumScaleFactor(0.45)` → `(0.6)`; the label built
    /// as `"→ \(RomajiHintLayout.breakable(hint))"`.
    @Test("the hint's modifier chain, and its VoiceOver label from the plain romaji")
    func hintChainIsPinned() throws {
        let lines = V133GRideAndDrillLayoutTests.codeLines(try V133GRideAndDrillLayoutTests.source("GameView.swift"))
        let start = try #require(lines.firstIndex(of: "let hint = session.currentRomaji ?? \"\""),
                                 "WordCard's hint moved; update this test")
        let expected = [
            "let hint = session.currentRomaji ?? \"\"",
            "Text(\"→ \\(RomajiHintLayout.breakable(hint))\")",
            ".scaledSystemFont(compact ? 14 : 18, weight: .regular, design: .monospaced)",
            ".foregroundStyle(Theme.dim)",
            ".lineLimit(2)",
            ".minimumScaleFactor(0.45)",
            ".fixedSize(horizontal: false, vertical: true)",
            ".accessibilityLabel(\"→ \\(hint)\")",
            ".accessibilityIdentifier(\"romajiHint\")",
            "nextKeys",
        ]
        let found = Array(lines[start...].filter { !$0.isEmpty }.prefix(expected.count))
        #expect(found == expected, "the hint's chain is now:\n\(found.joined(separator: "\n"))")
        #expect(lines[..<start].last { !$0.isEmpty } == "if session.romajiVisible {",
                "the hint is no longer the romajiVisible branch")

        let files = try CallSiteScanner.shippedSources.get()
        let calls = files.flatMap { file in
            file.calls(named: "breakable").filter { CallSiteScanner.receiverComponents($0.receiver) == ["RomajiHintLayout"] }
                .map { file.location($0.nameOffset) }
        }
        #expect(calls.count == 1 && calls.first?.hasPrefix("Sources/NihongoRideApp/GameView.swift:") == true,
                "RomajiHintLayout.breakable is called at \(calls)")
    }

    /// The practice screen's hint is its own row and v1.34 does not touch it: `romajiGuide`,
    /// comment-stripped, is 1.33's text line for line.
    @Test("PracticeView's romaji row is 1.33's")
    func practiceRowUntouched() throws {
        let lines = V133GRideAndDrillLayoutTests.codeLines(try V133GRideAndDrillLayoutTests.source("PracticeView.swift"))
        let start = try #require(lines.firstIndex(of: "private func romajiGuide(_ s: GameSession) -> some View {"))
        let expected = [
            "private func romajiGuide(_ s: GameSession) -> some View {",
            "VStack(spacing: 6) {",
            "Text(s.typedRomaji.isEmpty ? \" \" : s.typedRomaji)",
            ".foregroundStyle(accent)",
            ".scaledSystemFont(22, weight: .semibold, design: .monospaced)",
            "Text(s.currentRomaji ?? \"\")",
            ".foregroundStyle(ink.opacity(0.32))",
            ".scaledSystemFont(15, weight: .regular, design: .monospaced)",
            ".accessibilityIdentifier(\"practiceRomaji\")",
            "}",
            "}",
        ]
        #expect(Array(lines[start..<min(lines.count, start + expected.count)]) == expected)
        #expect(!lines.contains { $0.contains("RomajiHintLayout") }, "PracticeView reads RomajiHintLayout")
    }
}
