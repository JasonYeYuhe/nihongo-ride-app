import Testing
import Foundation
// CoreText (CTFramesetter, CTLine) comes in through SwiftUI's re-export. It is not imported by name
// because `ModuleDependencyTests` accepts only the platform modules it lists, and CoreText is not one.
import SwiftUI
@testable import NihongoRideApp

// v1.33 §B S — Settings and About at the accessibility sizes, and the two contrast fixes.
//
// What a headless render cannot see is exactly what these screens got wrong: `ImageRenderer`
// ignores Dynamic Type, so the AX layouts are verified on a simulator, not here. What CAN be held
// here is the logic under them — the break opportunities the About credits rely on, and the colour
// arithmetic behind the two contrast fixes — plus a pin that the header switches exist.

@Suite("V133S: identifier-like names break between their parts at accessibility sizes")
struct V133SIdentifierBreakTests {

    @Test("a zero-width space follows every underscore, and nothing else in the string changes")
    func insertsAfterEveryUnderscore() {
        #expect(AboutView.breakingIdentifiers("Bluskyo / JLPT_Vocabulary")
                == "Bluskyo / JLPT_\u{200B}Vocabulary")
        #expect(AboutView.breakingIdentifiers("see THIRD_PARTY_LICENSES.md).")
                == "see THIRD_\u{200B}PARTY_\u{200B}LICENSES.md).")

        // Everything without an underscore passes through untouched — which is most of the screen.
        for plain in ["Google Mozc", "Jonathan Waller — JLPT Resources (Tanos)", "https://tatoeba.org",
                      "词形 + 权威读音 + 等级(本作 -b / -k 词条来源)。", ""] {
            #expect(AboutView.breakingIdentifiers(plain) == plain)
        }

        // What a reader sees is unchanged: remove the inserted scalars and the input comes back.
        let url = "https://www.edrdg.org/jmdict/j_jmdict.html"
        let broken = AboutView.breakingIdentifiers(url)
        #expect(String(String.UnicodeScalarView(broken.unicodeScalars.filter { $0 != "\u{200B}" })) == url)
        #expect(broken.unicodeScalars.count == url.unicodeScalars.count + 1)
    }

    /// The claim the fix actually rests on is about the line breaker, not the string: that CoreText
    /// treats U+200B as a place it may break, and draws it with no width. Measured here rather than
    /// assumed, with a control showing the break does NOT happen there without it.
    @Test("CoreText breaks the name after the underscore, and the inserted space has no width")
    func coreTextBreaksAtTheInsertedSpace() throws {
        // ~15pt semibold at AX5 (15 × 53/17 ≈ 47pt), the credit name's size there.
        let font = try #require(CTFontCreateUIFontForLanguage(.emphasizedSystem, 47, nil))

        func advance(_ s: String) -> Double {
            let line = CTLineCreateWithAttributedString(
                NSAttributedString(string: s, attributes: [.font: font]))
            return CTLineGetTypographicBounds(line, nil, nil, nil)
        }
        func lines(_ s: String, width: Double) -> [String] {
            let setter = CTFramesetterCreateWithAttributedString(
                NSAttributedString(string: s, attributes: [.font: font]))
            let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: 10_000), transform: nil)
            let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), path, nil)
            let ns = s as NSString
            return (CTFrameGetLines(frame) as? [CTLine] ?? []).map { line in
                let range = CTLineGetStringRange(line)
                return ns.substring(with: NSRange(location: range.location, length: range.length))
            }
        }

        let plain = "JLPT_Vocabulary"
        let broken = AboutView.breakingIdentifiers(plain)
        #expect(abs(advance(plain) - advance(broken)) < 0.001,
                "the zero-width space has width — the default size would move")

        // A column narrower than the whole name and wider than either half: the only question left
        // is WHERE it breaks.
        let column = (advance(plain) + advance("Vocabulary")) / 2
        try #require(column < advance(plain) && column > advance("Vocabulary") && column > advance("JLPT_"))

        #expect(lines(plain, width: column).count == 2)
        #expect(lines(plain, width: column).first != "JLPT_",
                "the control: without the inserted space the break should be mid-word, or this test proves nothing")
        #expect(lines(broken, width: column).map { $0.replacingOccurrences(of: "\u{200B}", with: "") }
                == ["JLPT_", "Vocabulary"])
    }
}

/// WCAG 2.x contrast, computed from the resolved colours rather than restated from the comments
/// beside them, so a later change to either colour — or to `Theme` — is recomputed, not trusted.
///
/// **Scope: the two 1.33 fixes, not every small dim text.** Settings' captions and About's two
/// counter lines are what v1.33 changed, and this suite says nothing about the rest. (The title
/// used to say "small dim text in Settings and About", which claimed that too.) The rest of
/// About's small dim text — the footer note among it — is v1.34 §B4's, held by
/// `V134B4AboutContrastTests` below with the same model; Settings' sync-status caption is still
/// under the line and still nobody's, because it sits on the screen that carries the frozen road
/// card (PLAN-V1.34 §B4).
@Suite("V133S: Settings' captions and About's counter lines reach 4.5:1 wherever they can sit")
@MainActor
struct V133SContrastTests {

    typealias RGB = (r: Double, g: Double, b: Double)

    static func resolved(_ color: Color) -> (rgb: RGB, alpha: Double) {
        let c = color.resolve(in: EnvironmentValues())
        return ((Double(c.red), Double(c.green), Double(c.blue)), Double(c.opacity))
    }

    static func linear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    static func luminance(_ c: RGB) -> Double {
        0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
    }

    /// Source-over on the gamma-encoded values — the model `calibration` below checks against the
    /// simulator's own pixels.
    static func over(_ color: Color, _ bg: RGB) -> RGB {
        let (fg, a) = resolved(color)
        return (a * fg.r + (1 - a) * bg.r, a * fg.g + (1 - a) * bg.g, a * fg.b + (1 - a) * bg.b)
    }

    static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// Both stops of `Theme.background`. The top one is a named constant; the bottom one is written
    /// inline in the gradient, so it is READ FROM THE SOURCE rather than copied here — a copy would
    /// keep this test green after the theme changed underneath it.
    static func gradientStops() throws -> [RGB] {
        let source = try String(contentsOf: HorizontalTextFitTests.appDirectory
                                    .appendingPathComponent("NihongoRideApp.swift"), encoding: .utf8)
        let start = try #require(source.range(of: "static let background = LinearGradient("))
        let tail = source[start.upperBound...]
        let pattern = /Color\(red: ([0-9.]+), green: ([0-9.]+), blue: ([0-9.]+)\)/
        let match = try #require(tail.firstMatch(of: pattern), "the gradient's second stop moved")
        let bottom: RGB = (try #require(Double(match.1)), try #require(Double(match.2)), try #require(Double(match.3)))
        return [resolved(Theme.backgroundTop).rgb, bottom]
    }

    @Test("the compositing model reproduces the simulator's measured pixels")
    func calibration() throws {
        // `Color.Resolved.red` must be the gamma-encoded value; if it were linear this would be ~0.005.
        try #require(abs(Self.resolved(Theme.backgroundTop).rgb.r - 0.06) < 0.001)

        func px(_ c: RGB) -> [Int] { [c.r, c.g, c.b].map { Int(($0 * 255).rounded()) } }
        func bg(_ r: Int, _ g: Int, _ b: Int) -> RGB { (Double(r) / 255, Double(g) / 255, Double(b) / 255) }
        func near(_ a: [Int], _ b: [Int]) -> Bool { zip(a, b).allSatisfy { abs($0 - $1) <= 1 } }

        // About's counters, `B_about_p3_en_large.png`: text (96,103,123) over (23,32,61).
        #expect(near(px(Self.over(Theme.dim.opacity(0.7), bg(23, 32, 61))), [96, 103, 123]))
        // Settings' reminder caption, `A_settings_en_large.png`: card (35,43,70) over (22,31,58),
        // caption (105,110,128) over that card.
        let card = Self.over(Theme.card, bg(22, 31, 58))
        #expect(near(px(card), [35, 43, 70]))
        #expect(near(px(Self.over(Theme.dim.opacity(0.7), card)), [105, 110, 128]))
    }

    @Test("Settings' captions, on a card, clear 4.5:1 at both ends of the gradient")
    func settingsCaptions() throws {
        for stop in try Self.gradientStops() {
            let card = Self.over(Theme.card, stop)
            let now = Self.contrast(Self.over(SettingsView.captionColor, card), card)
            #expect(now >= 4.5, "caption at \(now):1 over card \(card)")
            // The control: the colour it replaced must fail here, or this suite cannot fail.
            let before = Self.contrast(Self.over(Theme.dim.opacity(0.7), card), card)
            #expect(before < 4.5 && before > 2.5, "the old caption computed \(before):1 — measured 2.75:1")
        }
    }

    @Test("About's counter lines, straight on the background, clear 4.5:1 at both ends of the gradient")
    func aboutCounters() throws {
        for stop in try Self.gradientStops() {
            let now = Self.contrast(Self.over(AboutView.counterColor, stop), stop)
            #expect(now >= 4.5, "counters at \(now):1 over \(stop)")
            let before = Self.contrast(Self.over(Theme.dim.opacity(0.7), stop), stop)
            #expect(before < 4.5 && before > 2.5, "the old counters computed \(before):1 — measured 2.78:1")
        }
    }

    // MARK: The colours are where they are claimed to be

    /// The two tests above check the CONSTANTS. The review set one Settings caption and one About
    /// counter line back to `Theme.dim.opacity(0.7)` and both stayed green, because nothing said
    /// the constants were used. Read on comment-stripped code, so the colour comments that quote the
    /// old value (both constants have one) are not counted.
    static let oldStyle = #"Theme\.dim\.opacity\(\s*0?\.7\s*\)"#

    static func shipped(_ name: String) throws -> CallSiteScanner.File {
        try #require(try CallSiteScanner.shippedSources.get().first { $0.path == "Sources/NihongoRideApp/\(name)" },
                     "\(name) not found")
    }

    static func foregroundStyles(_ file: CallSiteScanner.File, _ argument: String) -> [CallSiteScanner.Call] {
        file.calls(named: "foregroundStyle").filter {
            $0.arguments.map { file.text($0).filter { !$0.isWhitespace } } == argument
        }
    }

    /// Byte offsets of `pattern` in the comment- and string-stripped code, outside `excluded`.
    static func matches(_ pattern: String, in file: CallSiteScanner.File, excluding excluded: Range<Int>? = nil) -> [Int] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let code = file.allCode
        return regex.matches(in: code, range: NSRange(code.startIndex..., in: code))
            .compactMap { Range($0.range, in: code).map { code.utf8.distance(from: code.startIndex, to: $0.lowerBound) } }
            .filter { excluded?.contains($0) != true }
    }

    @Test("Settings draws its captions in captionColor, three times, and no caption in the old colour")
    func settingsUsesTheCaptionColor() throws {
        // Control: the old-colour pattern finds code, spacing variants included, and not comments.
        let sample = CallSiteScanner.File(path: "Sample.swift", source: """
            // .foregroundStyle(Theme.dim.opacity(0.7))
            Text(a).foregroundStyle(Theme.dim.opacity( .7 )) /* Theme.dim.opacity(0.7) */
            """)
        #expect(Self.matches(Self.oldStyle, in: sample).count == 1, "the old-colour pattern is miscalibrated")

        let settings = try Self.shipped("SettingsView.swift")
        // The Road card (Stage 1's one offer row) is frozen byte-for-byte in v1.33 and is not this
        // fix's to hold, so it is left out of the old-colour check. Located by its identifier, which
        // must lie inside the extent found — so the exclusion is the Road card and only it.
        let road = try #require(settings.calls(named: "settingsCard").first {
            $0.arguments.map { String(decoding: settings.codeWithStrings[$0], as: UTF8.self).contains("\"The Road\"") } ?? false
        }, "the Road card moved")
        let roadText = String(decoding: settings.codeWithStrings[road.extent], as: UTF8.self)
        #expect(roadText.contains("\"roadRow\"") && !roadText.contains("\"Review Reminder\""),
                "the excluded extent is not exactly the Road card")

        let uses = Self.foregroundStyles(settings, "Self.captionColor")
        #expect(uses.count == 3, "captionColor is drawn \(uses.count) time(s), expected the three captions (iCloud, reminder, read-aloud): \(uses.map { settings.location($0.nameOffset) })")
        #expect(settings.mentions(of: "captionColor").count == uses.count + 1,
                "captionColor is read somewhere other than a caption's foregroundStyle")
        let old = Self.matches(Self.oldStyle, in: settings, excluding: road.extent)
        #expect(old.isEmpty, "Theme.dim.opacity(0.7) is back at \(old.map(settings.location))")
    }

    @Test("About draws exactly its two counter lines in counterColor")
    func aboutUsesTheCounterColor() throws {
        let about = try Self.shipped("AboutView.swift")
        let uses = Self.foregroundStyles(about, "Self.counterColor")
        #expect(about.mentions(of: "counterColor").count == uses.count + 1,
                "counterColor is read somewhere other than a foregroundStyle")
        let lines = ["model.unlockOfferLedger.shareableSummary", "model.reviewPromptLedger.debugSummary"]
        let texts = about.calls(named: "Text")
        for line in lines {
            let text = try #require(texts.first { $0.arguments.map { about.text($0).filter { !$0.isWhitespace } } == line },
                                    "the counter line Text(\(line)) moved")
            // Its modifier chain: from the Text to the next Text in the same block, or the block's end.
            let block = try #require(about.innermostBlock(containing: text.nameOffset, within: 0..<about.code.count))
            let end = texts.map(\.nameOffset).filter { $0 > text.nameOffset && block.contains($0) }.min() ?? block.upperBound
            let chain = text.extent.upperBound..<end
            #expect(uses.filter { chain.contains($0.nameOffset) }.count == 1,
                    "Text(\(line)) is not drawn in counterColor")
        }
        #expect(uses.count == lines.count, "counterColor is drawn \(uses.count) time(s), expected the two counter lines")
    }
}

/// v1.34 §B4 — the small dim text 1.33 left under 4.5:1 on About, and only About.
///
/// The same model as `V133SContrastTests` (its helpers are reused, so a change to the model, to
/// `Theme.card` or to the gradient reaches both suites), and the same shape per call site: the new
/// constant clears 4.5:1 wherever the text can sit, AND the colour it replaced computed under —
/// without the second half a suite like this cannot fail. The expected figures are written out
/// from PLAN-V1.33 §G's list and the arithmetic in the constants' comments, and the new colours
/// are held to their stated values, not just to the threshold: a constant raised "to be safe"
/// would also go red, because "the smallest opacity that clears" is the claim.
///
/// Every colour About draws in `Theme.dim` was measured for this item, not only the four the
/// plan lists, and the seven straight on the background share one worst case (the gradient's
/// bottom stop) while the two on a card share another (`Theme.card` over that stop).
///
/// **What the rule holds, exactly** (added after the review, widened after the second): every
/// `Text` and `Label` call in `AboutView` drawn in dim text — any colour but full opaque white or a
/// brand accent as written, so white at an opacity and an opaque grey alike — must clear 4.5:1 at
/// both stops over the backdrops the source puts on its walk (the gradient, and each
/// `.background(<colour>)` or `.panel` between the text and `body` that `backdrop(_:)` reads), white
/// at an opacity at no less than that backdrop's constant (`everyDimWhiteTextClears`,
/// `eachTextSitsWhereItsConstantAssumes`, below). On the same walk, every modifier must be inert, a
/// readable backdrop or the card's edge stroke, and every block a container that draws nothing —
/// no `.opacity`, no `ZStack`, no overlay but the edge stroke (`nothingElseChangesWhatIsDrawn`). The
/// `checkedAbsent` views are held absent from About, and a `Button` may only take its label as a
/// closure. That covers the two counter lines' placement and alpha too; their COLOUR stays pinned
/// where 1.33 pinned it (`aboutUsesTheCounterColor` above), beside their frozen text.
///
/// **Not held here** — the walk reads the colours, containers and overlays on a text's path, and no
/// more; it does not see:
/// - layout overlap without a modifier: a negative `.padding` or a negative stack `spacing:` that
///   pulls a sibling over a text;
/// - shapes inside a closure-form `.background { … }` that are not on `backdrop(_:)`'s painter list;
/// - title-bearing views the enumeration does not read and `checkedAbsent` does not name:
///   `ShareLink`, `ProgressView`, `GroupBox`, `NavigationLink`, `Section`, `Gauge`, `DatePicker`,
///   `ColorPicker`;
/// - a pressed-state dimming (`.buttonStyle(.plain)` is classified by what it draws at rest);
/// - text that is not dim: the coral section titles (5.65:1), the sky version line (8.15:1), and the
///   brand-colour licence badges (4.28:1 on their tinted background, the one small text on About
///   still under the line, left because PLAN-V1.34 §I keeps brand-colour contrast on the day-91
///   list).
///
/// This change is colour only; its proof is the render comparison of `about.png` (en, zh) against
/// the 1.33 baseline, not this suite.
@Suite("V134B4: About's remaining small dim text reaches 4.5:1 wherever it can sit")
@MainActor
struct V134B4AboutContrastTests {

    typealias Model = V133SContrastTests

    static func bottomStop() throws -> Model.RGB {
        let stops = try Model.gradientStops()
        // The bottom stop is the lighter one — the worst case for white text — or the argument
        // in the constants' comments is about the wrong stop.
        try #require(Model.luminance(stops[1]) > Model.luminance(stops[0]))
        return stops[1]
    }

    // MARK: Straight on the background

    @Test("dimTextColor clears 4.5:1 at both stops, at 4.62:1 on the lighter one; 0.47 computes 4.49:1")
    func dimTextColorOnTheBackground() throws {
        for stop in try Model.gradientStops() {
            let now = Model.contrast(Model.over(AboutView.dimTextColor, stop), stop)
            #expect(now >= 4.5, "dim text at \(now):1 over \(stop)")
        }
        let bottom = try Self.bottomStop()
        let stated = Model.contrast(Model.over(AboutView.dimTextColor, bottom), bottom)
        #expect(abs(stated - 4.62) < 0.01, "dimTextColor computes \(stated):1 at the bottom stop; its comment says 4.62")
        // The smallest-opacity claim: one hundredth less does not clear.
        let step = Model.contrast(Model.over(Color.white.opacity(0.47), bottom), bottom)
        #expect(step < 4.5 && step > 4.45, "white at 0.47 computes \(step):1 — expected 4.49")
    }

    @Test("the colours the background text replaced computed 2.79, 3.23, 3.46 and 4.24 to one")
    func oldBackgroundColoursWereUnder() throws {
        let bottom = try Self.bottomStop()
        // (the old colour, its contrast at the bottom stop as PLAN-V1.33 §G lists it, what wore it)
        let cases: [(Color, Double, String)] = [
            (Theme.dim.opacity(0.7), 2.79, "the footer note"),
            (Theme.dim.opacity(0.8), 3.23, "the contact and counter prompts"),
            (Theme.dim.opacity(0.85), 3.46, "the address"),
            (Theme.dim, 4.24, "the subtitle and the two small-caps titles"),
        ]
        for (color, expected, what) in cases {
            let before = Model.contrast(Model.over(color, bottom), bottom)
            #expect(before < 4.5, "\(what) computed \(before):1 in its old colour — this suite could not fail")
            #expect(abs(before - expected) < 0.01, "\(what) computed \(before):1, the plan measured \(expected)")
        }
    }

    // MARK: On a card

    @Test("dimTextOnCardColor clears 4.5:1 on the card at both stops, at 4.57:1 on the lighter one; 0.50 computes 4.46:1")
    func dimTextOnCardColorOnTheCard() throws {
        for stop in try Model.gradientStops() {
            let card = Model.over(Theme.card, stop)
            let now = Model.contrast(Model.over(AboutView.dimTextOnCardColor, card), card)
            #expect(now >= 4.5, "card text at \(now):1 over card \(card)")
        }
        let card = Model.over(Theme.card, try Self.bottomStop())
        let stated = Model.contrast(Model.over(AboutView.dimTextOnCardColor, card), card)
        #expect(abs(stated - 4.57) < 0.01, "dimTextOnCardColor computes \(stated):1 on the bottom card; its comment says 4.57")
        let step = Model.contrast(Model.over(Color.white.opacity(0.50), card), card)
        #expect(step < 4.5 && step > 4.4, "white at 0.50 computes \(step):1 on the card — expected 4.46")
    }

    @Test("Theme.dim on the card — the credit URLs and stat labels — computed 3.91:1")
    func oldCardColourWasUnder() throws {
        let card = Model.over(Theme.card, try Self.bottomStop())
        let before = Model.contrast(Model.over(Theme.dim, card), card)
        #expect(before < 4.5 && abs(before - 3.91) < 0.01, "Theme.dim on the card computed \(before):1, the plan measured 3.91")
    }

    // MARK: The colours are where they are claimed to be

    /// `Theme.dim` — bare, or with any `.opacity(...)` — anywhere in About's code. After this item
    /// About draws no `Theme.dim` at all; every dim text goes through one of the two constants, and
    /// the constants' own comments quote the old colour, which is why this reads comment-stripped
    /// code. `\b` keeps `Theme.dimTextColor` (were anyone to move the constant) from matching.
    static let anyDim = #"Theme\.dim\b"#

    /// The nine `Text`s, each by a fragment of its argument that no other `Text` on About has,
    /// read with strings kept (`codeWithStrings`) because seven of them are string literals.
    static let onTheBackground = [
        "Type your way across Japan",           // the header subtitle
        "\"Contact\").uppercased()",             // the Contact title
        "Questions, thoughts, or a route",      // the contact prompt
        "yyyyy.yeyuhe@gmail.com",               // the address
        "\"On-device counters\").uppercased()",  // the counters title
        "pasting the counters below helps",     // the counters prompt
        "Thanks to the maintainers",            // the footer note
    ]
    static let onACard = [
        "Self.breakingIdentifiers(url) : url",  // each credit's URL
        "label.uppercased()",                   // each stat's label
    ]

    /// `text`'s modifier chain, as `aboutUsesTheCounterColor` walks it: from the end of the `Text`
    /// call to the next `Text` in the same block, or the block's end.
    static func chain(of text: CallSiteScanner.Call, in file: CallSiteScanner.File) throws -> Range<Int> {
        let block = try #require(file.innermostBlock(containing: text.nameOffset, within: 0..<file.code.count))
        let end = file.calls(named: "Text").map(\.nameOffset)
            .filter { $0 > text.nameOffset && block.contains($0) }.min() ?? block.upperBound
        return text.extent.upperBound..<end
    }

    static func theText(containing fragment: String, in file: CallSiteScanner.File) throws -> CallSiteScanner.Call {
        let hits = file.calls(named: "Text").filter {
            $0.arguments.map { String(decoding: file.codeWithStrings[$0], as: UTF8.self).contains(fragment) } ?? false
        }
        #expect(hits.count == 1, "\(hits.count) Text(...) on About contain \(fragment); the fragment is not unique")
        return try #require(hits.first, "no Text(...) on About contains \(fragment) — it moved or was reworded")
    }

    @Test("the old-colour pattern finds bare and opacity uses in code, spacing included, and not comments or the new names")
    func patternCalibration() {
        let sample = CallSiteScanner.File(path: "Sample.swift", source: """
            // .foregroundStyle(Theme.dim.opacity(0.7))
            Text(a).foregroundStyle(Theme.dim.opacity( .8 )) /* Theme.dim */
            Text(b).foregroundStyle(Theme.dim)
            Text(c).foregroundStyle(Theme.dimTextColor).background(Theme.dim.opacity(0.85))
            """)
        #expect(Model.matches(Self.anyDim, in: sample).count == 3, "the any-dim pattern is miscalibrated")
    }

    @Test("About draws its seven background texts in dimTextColor, its two card texts in dimTextOnCardColor, and nothing in Theme.dim")
    func aboutUsesTheTwoConstants() throws {
        let about = try Model.shipped("AboutView.swift")
        let old = Model.matches(Self.anyDim, in: about)
        #expect(old.isEmpty, "Theme.dim is back on About at \(old.map(about.location))")

        for (constant, fragments) in [("dimTextColor", Self.onTheBackground), ("dimTextOnCardColor", Self.onACard)] {
            let uses = Model.foregroundStyles(about, "Self.\(constant)")
            #expect(about.mentions(of: constant).count == uses.count + 1,
                    "\(constant) is read somewhere other than a foregroundStyle")
            for fragment in fragments {
                let text = try Self.theText(containing: fragment, in: about)
                let chain = try Self.chain(of: text, in: about)
                #expect(uses.filter { chain.contains($0.nameOffset) }.count == 1,
                        "the Text containing \(fragment) is not drawn in \(constant)")
            }
            #expect(uses.count == fragments.count,
                    "\(constant) is drawn \(uses.count) time(s), expected \(fragments.count): \(uses.map { about.location($0.nameOffset) })")
        }
    }

    // MARK: What each text sits on, and everything applied to it — read from the source

    /// The review of this item took promised texts under 4.5:1 three ways with every test above
    /// green, because they hold the constants and which `Text` reads which, and take the rest on
    /// trust: `.background(Theme.card, …)` added around the contact block (white 0.48 on a card,
    /// 4.23:1), the stat card's backdrop swapped for white at 0.12 (0.51 on it, 4.07:1), and
    /// `.opacity(0.6)` after the footer note's `.italic()` (2.56:1). What follows holds what the
    /// text is DRAWN as: every modifier between the `Text` and the page — its own chain up to the
    /// next sibling statement, then each enclosing view's, climbing out of the builder (`some View`
    /// property or function) that holds it to every place that builder is used, through
    /// `let content = …` to its uses, as far as `body`. Backdrops are read from that walk and their
    /// colours from the source (`Theme` in NihongoRideApp.swift, the constants here), as
    /// `gradientStops()` reads the gradient, so a changed backdrop changes the arithmetic.
    ///
    /// Outside the walk, stated rather than held: the page itself sits on `Theme.background`
    /// (`Screenshot.swift`'s ZStack; the app's root draws the same gradient behind every flat
    /// screen).
    ///
    /// Layers on the walk are held too (after the second review, which drew a `Theme.card` as a `ZStack`
    /// sibling behind the contact texts and an `.overlay(Color.black.opacity(0.5))` over the footer
    /// note, both green, because the walk read modifiers and a `ZStack`'s other children are not
    /// modifiers, and `.overlay` was on the inert list). Now every block a text's path passes
    /// through must be the body of a container that draws nothing of its own (`containers` —
    /// a `ZStack` is named and fails), and `.overlay` is off the inert list: the one overlay About
    /// has, the card's hairline `.strokeBorder`, passes only as an edge stroke drawn outside a
    /// padding that insets every edge (`isEdgeStroke`); any other overlay fails.

    /// One modifier: `.name(arguments)`, with its trailing `{ closure }` if it has one.
    struct Link {
        let name: String
        let arguments: Range<Int>?
        let closure: Range<Int>?
        let offset: Int
    }

    /// A block a path passes through, named by what it is the body of (`owner(of:)`).
    struct Container {
        let name: String
        let offset: Int
    }

    /// One way a `Text` reaches the page: every link applied on the way, innermost first, and
    /// every block it passes through on the way.
    struct Path {
        var links: [Link] = []
        var containers: [Container] = []
        var reachesBody = false
    }

    typealias Paint = (rgb: Model.RGB, alpha: Double)

    /// Modifiers that neither paint behind a text nor change its colour or alpha. Anything else on a
    /// text's way to the page is a failure until someone says which it is — the list is the claim.
    /// `.overlay` was on it until the second review drew black at 0.5 over the footer with it; it is
    /// now classified per use (`isEdgeStroke`).
    static let inert: Set<String> = [
        "scaledSystemFont", "fixedSize", "textSelection", "italic", "tracking", "lineLimit",
        "minimumScaleFactor", "padding", "frame", "accessibilityElement",
        "accessibilityLabel", "accessibilityValue", "accessibilityIdentifier",
    ]

    /// The blocks a text may be inside on its way to the page: containers that lay their children
    /// out side by side or one at a time and draw nothing themselves — plus `Button`, whose closure
    /// is its label, and the branches of an `if`. Anything else fails until it is classified; a
    /// `ZStack` draws its other children behind or over the text, so it is never on this list.
    nonisolated static let containers: Set<String> = ["VStack", "HStack", "Group", "ScrollView", "Button", "if"]

    /// The text-bearing views the enumeration reads. The title-drawing views in `checkedAbsent` must
    /// not appear on About; the ones in the suite's "not held" list are neither read nor checked.
    static let textViews = ["Text", "Label"]
    static let checkedAbsent = ["Link", "Toggle", "TextField", "SecureField", "TextEditor", "Picker",
                                "Menu", "Stepper", "LabeledContent", "DisclosureGroup", "navigationTitle"]

    /// The brand colours, as written — not dim text, and on PLAN-V1.34 §I's day-91 list.
    nonisolated static let brandAccents: Set<String> = ["Theme.accent", "Theme.accent2"]

    /// Whether a text drawn in `expression` (read as `paint`) is dim text for the rule: anything that
    /// is not full opaque white and not a brand accent as written — white at an opacity, an opaque
    /// grey, a brand colour at an opacity, any other colour.
    nonisolated static func isDim(_ expression: String, _ paint: Paint) -> Bool {
        if paint.rgb == (1, 1, 1) && paint.alpha == 1 { return false }
        return !brandAccents.contains(expression)
    }

    /// The colour an expression names, read from the source: `.white` / `Color.white`,
    /// `Color(red:green:blue:)`, `Theme.x` (NihongoRideApp.swift), `Self.x` / `AboutView.x`
    /// (AboutView.swift), each with any `.opacity(…)` suffixes. Nil for anything else — a material,
    /// a semantic style, a view — so an unreadable backdrop or colour fails instead of passing.
    nonisolated static func paint(_ expression: String, about: CallSiteScanner.File, app: CallSiteScanner.File,
                      depth: Int = 0) -> Paint? {
        var base = expression.filter { !$0.isWhitespace }
        var factor = 1.0
        while let match = base.wholeMatch(of: /(.+)\.opacity\(([0-9.]+)\)/), let value = Double(match.2) {
            factor *= value
            base = String(match.1)
        }
        switch base {
        case ".white", "Color.white": return ((1, 1, 1), factor)
        case ".black", "Color.black": return ((0, 0, 0), factor)
        default: break
        }
        if let match = base.wholeMatch(of: /Color\(red:([0-9.]+),green:([0-9.]+),blue:([0-9.]+)\)/),
           let r = Double(match.1), let g = Double(match.2), let b = Double(match.3) {
            return ((r, g, b), factor)
        }
        guard depth < 4, let match = base.wholeMatch(of: /(Theme|Self|AboutView)\.(\w+)/),
              let definition = try? Regex(#"static\s+let\s+"# + String(match.2) + #"\s*=\s*([^\n]+)"#)
        else { return nil }
        let (file, type) = match.1 == "Theme" ? (app, "Theme") : (about, "AboutView")
        guard let body = file.typeBodies(named: type).first,
              let found = String(decoding: file.code[body], as: UTF8.self).firstMatch(of: definition),
              let value = found.output[1].substring,
              let inner = paint(String(value), about: about, app: app, depth: depth + 1)
        else { return nil }
        return (inner.rgb, inner.alpha * factor)
    }

    nonisolated static func over(_ paint: Paint, _ bg: Model.RGB) -> Model.RGB {
        let a = paint.alpha
        return (a * paint.rgb.r + (1 - a) * bg.r, a * paint.rgb.g + (1 - a) * bg.g, a * paint.rgb.b + (1 - a) * bg.b)
    }

    /// Walks About's source. Every offset is into `file.code` (comments and string contents blanked).
    struct Walker {
        let file: CallSiteScanner.File
        let app: CallSiteScanner.File
        let type: Range<Int>
        let blocks: [Range<Int>]

        struct NoAboutView: Error {}

        init(_ file: CallSiteScanner.File, app: CallSiteScanner.File) throws {
            guard let type = file.typeBodies(named: "AboutView").first else { throw NoAboutView() }
            self.file = file
            self.app = app
            self.type = type
            var stack: [Int] = [], found: [Range<Int>] = []
            for index in type {
                if file.code[index] == UInt8(ascii: "{") { stack.append(index) }
                else if file.code[index] == UInt8(ascii: "}"), let open = stack.popLast() { found.append(open..<(index + 1)) }
            }
            blocks = found.filter { $0 != type }
        }

        /// The chain that starts at `end`: consecutive `.name(…)` / `.name { … }` links, up to the
        /// first thing that is not one — the next sibling statement, or the end of the block.
        func links(after end: Int) -> [Link] {
            let code = file.code
            var index = end
            var out: [Link] = []
            while true {
                let dot = CallSiteScanner.skipSpace(code, index)
                guard dot < code.count, code[dot] == UInt8(ascii: "."),
                      let (name, afterName) = CallSiteScanner.word(in: code, at: dot + 1) else { break }
                var cursor = CallSiteScanner.skipSpace(code, afterName, newlines: false)
                var arguments: Range<Int>?
                if cursor < code.count, code[cursor] == UInt8(ascii: "("),
                   let close = CallSiteScanner.matching(code, open: cursor) {
                    arguments = (cursor + 1)..<close
                    cursor = close + 1
                }
                var closure: Range<Int>?
                let brace = CallSiteScanner.skipSpace(code, cursor, newlines: false)
                if brace < code.count, code[brace] == UInt8(ascii: "{"),
                   let close = CallSiteScanner.matching(code, open: brace) {
                    closure = brace..<(close + 1)
                    cursor = close + 1
                }
                out.append(Link(name: name, arguments: arguments, closure: closure, offset: dot))
                index = cursor
            }
            return out
        }

        /// The builder whose body is `block`: a function, or a `var name: some View` property.
        func builder(of block: Range<Int>) -> (name: String, isFunction: Bool)? {
            if let function = file.functions.first(where: { $0.body == block }) { return (function.name, true) }
            var start = block.lowerBound
            while start > 0, file.code[start - 1] != UInt8(ascii: "\n") { start -= 1 }
            let head = String(decoding: file.code[start..<block.lowerBound], as: UTF8.self)
            guard let match = head.firstMatch(of: /\bvar\s+(\w+)\s*:\s*some\s+View\s*$/) else { return nil }
            return (String(match.1), false)
        }

        /// The innermost builder whose body contains `offset`.
        func builder(containing offset: Int) -> String? {
            blocks.filter { $0.contains(offset) }.sorted { $0.count < $1.count }
                .lazy.compactMap { self.builder(of: $0)?.name }.first
        }

        /// Where a builder is used: a function's calls, a property's mentions (not its declaration).
        func uses(of builder: (name: String, isFunction: Bool)) -> [(offset: Int, end: Int)] {
            if builder.isFunction {
                return file.calls(named: builder.name).filter { type.contains($0.nameOffset) }
                    .map { ($0.nameOffset, $0.extent.upperBound) }
            }
            return file.mentions(of: builder.name).filter { type.contains($0) && !declares($0) }
                .map { ($0, $0 + builder.name.utf8.count) }
        }

        private func declares(_ offset: Int) -> Bool {
            var index = offset - 1
            while index >= 0, file.code[index] == 32 || file.code[index] == 9 { index -= 1 }
            guard index >= 2, String(decoding: file.code[(index - 2)...index], as: UTF8.self) == "var" else { return false }
            return index == 2 || !CallSiteScanner.isIdentifier(file.code[index - 3])
        }

        /// `content` for `let content = VStack(…) { … }` when `block` is that closure; nil otherwise.
        func binding(of block: Range<Int>) -> String? {
            let code = file.code
            var index = block.lowerBound - 1
            func skip() { while index >= 0, [32, 9, 10, 13].contains(code[index]) { index -= 1 } }
            func word() -> String? {
                let end = index + 1
                while index >= 0, CallSiteScanner.isIdentifier(code[index]) { index -= 1 }
                return end > index + 1 ? String(decoding: code[(index + 1)..<end], as: UTF8.self) : nil
            }
            skip()
            if index >= 0, code[index] == UInt8(ascii: ")") {
                var depth = 0
                while index >= 0 {
                    if code[index] == UInt8(ascii: ")") { depth += 1 }
                    else if code[index] == UInt8(ascii: "(") { depth -= 1; if depth == 0 { break } }
                    index -= 1
                }
                index -= 1
                skip()
            }
            guard word() != nil else { return nil }
            skip()
            guard index >= 1, code[index] == UInt8(ascii: "="),
                  !"=!<>".utf8.contains(code[index - 1]) else { return nil }
            index -= 1
            skip()
            guard let name = word() else { return nil }
            skip()
            guard let keyword = word(), keyword == "let" || keyword == "var" else { return nil }
            return name
        }

        /// Every way from `offset` to `body`, each with the links applied on the way — starting with
        /// the chain at `end` when given. A builder used twice gives two paths; one used nowhere, none.
        func paths(from offset: Int, after end: Int?, depth: Int = 0) -> [Path] {
            var links = end.map { self.links(after: $0) } ?? []
            var containers: [Container] = []
            guard depth < 16 else { return [Path(links: links)] }
            let enclosing = blocks.filter { $0.lowerBound < offset && offset < $0.upperBound }.sorted { $0.count < $1.count }
            for block in enclosing {
                if let owner = builder(of: block) {
                    if owner.name == "body" && !owner.isFunction {
                        return [Path(links: links, containers: containers, reachesBody: true)]
                    }
                    let (prefix, held) = (links, containers)
                    return uses(of: owner).flatMap { use in
                        paths(from: use.offset, after: use.end, depth: depth + 1)
                            .map { Path(links: prefix + $0.links, containers: held + $0.containers, reachesBody: $0.reachesBody) }
                    }
                }
                containers.append(Container(name: self.owner(of: block), offset: block.lowerBound))
                links += self.links(after: block.upperBound)
                if let name = binding(of: block) {
                    let scope = enclosing.first { $0.count > block.count } ?? type
                    let (prefix, held) = (links, containers)
                    return file.mentions(of: name).filter { scope.contains($0) && $0 > block.upperBound }.flatMap { use in
                        paths(from: use, after: use + name.utf8.count, depth: depth + 1)
                            .map { Path(links: prefix + $0.links, containers: held + $0.containers, reachesBody: $0.reachesBody) }
                    }
                }
            }
            return [Path(links: links, containers: containers)]
        }

        /// What `block` is the body of: `if` for a branch of an `if` / `else`, otherwise the name of
        /// the call it is the trailing closure of (`VStack`, `ZStack`, `Button`, `background`, …),
        /// read backwards over any argument list. `?` when there is no name.
        func owner(of block: Range<Int>) -> String {
            let code = file.code
            var start = block.lowerBound
            while start > 0, code[start - 1] != 10 { start -= 1 }
            let head = String(decoding: code[start..<block.lowerBound], as: UTF8.self).trimmingCharacters(in: .whitespaces)
            if !head.contains("{"), head.hasPrefix("if ") || head.hasPrefix("} else") || head == "else" { return "if" }
            var index = block.lowerBound - 1
            func skip() { while index >= 0, [32, 9, 10, 13].contains(code[index]) { index -= 1 } }
            skip()
            if index >= 0, code[index] == UInt8(ascii: ")") {
                var depth = 0
                while index >= 0 {
                    if code[index] == UInt8(ascii: ")") { depth += 1 }
                    else if code[index] == UInt8(ascii: "(") { depth -= 1; if depth == 0 { break } }
                    index -= 1
                }
                index -= 1
                skip()
            }
            let end = index + 1
            while index >= 0, CallSiteScanner.isIdentifier(code[index]) { index -= 1 }
            let name = end > index + 1 ? String(decoding: code[(index + 1)..<end], as: UTF8.self) : "?"
            return name == "else" ? "if" : name
        }

        /// `arguments` split at its top-level commas, whitespace removed.
        func split(_ arguments: Range<Int>) -> [String] {
            var parts: [String] = []
            var depth = 0, start = arguments.lowerBound
            for index in arguments {
                switch file.code[index] {
                case UInt8(ascii: "("), UInt8(ascii: "["), UInt8(ascii: "{"): depth += 1
                case UInt8(ascii: ")"), UInt8(ascii: "]"), UInt8(ascii: "}"): depth -= 1
                case UInt8(ascii: ",") where depth == 0:
                    parts.append(file.text(start..<index)); start = index + 1
                default: break
                }
            }
            parts.append(file.text(start..<arguments.upperBound))
            return parts.map { $0.filter { !$0.isWhitespace } }.filter { !$0.isEmpty }
        }

        static let allEdges: Set<String> = ["top", "bottom", "leading", "trailing"]

        /// The edges a `.padding(…)` insets by at least a point, as written: `padding()` and
        /// `padding(n)` all four, `padding(.horizontal, n)` two, `padding(.top, n)` one. An amount
        /// that is not a literal (`isPhoneIdiom ? 22 : 40`, `EdgeInsets(…)`) counts for nothing.
        func paddedEdges(_ link: Link) -> Set<String> {
            guard link.name == "padding" else { return [] }
            let parts = link.arguments.map(split) ?? []
            let named: [String: Set<String>] = [
                ".all": Self.allEdges, ".horizontal": ["leading", "trailing"], ".vertical": ["top", "bottom"],
                ".top": ["top"], ".bottom": ["bottom"], ".leading": ["leading"], ".trailing": ["trailing"],
            ]
            guard let first = parts.first else { return Self.allEdges }
            if let edges = named[first] {
                guard parts.count > 1 else { return edges }
                return (Double(parts[1]) ?? 0) >= 1 ? edges : []
            }
            return parts.count == 1 && (Double(first) ?? 0) >= 1 ? Self.allEdges : []
        }

        /// Whether `link` is `.overlay(<shape>().strokeBorder(<colour>))` — a default-width hairline
        /// drawn inside the view's edge — applied after paddings on the same path (`links`, innermost
        /// first) that inset the text from all four edges, so the stroke cannot lie over it. That is
        /// the card outline in `credit` and the back button's capsule. Any other overlay — a colour,
        /// a closure, a wider stroke, a stroke with no padding between it and the text — is false.
        func isEdgeStroke(_ link: Link, on links: [Link]) -> Bool {
            guard link.name == "overlay", link.closure == nil, let arguments = link.arguments,
                  let index = links.firstIndex(where: { $0.offset == link.offset }) else { return false }
            let argument = split(arguments)
            guard argument.count == 1,
                  let match = argument[0].wholeMatch(of: /(?:RoundedRectangle\(cornerRadius:[0-9.]+\)|Capsule\(\)|Rectangle\(\))\.strokeBorder\(([A-Za-z0-9_.()]+)\)/),
                  V134B4AboutContrastTests.paint(String(match.1), about: file, app: app) != nil
            else { return false }
            return links[..<index].reduce(into: Set<String>()) { $0.formUnion(paddedEdges($1)) }.isSuperset(of: Self.allEdges)
        }

        /// What on a path draws in a layer with the text other than behind it through a readable
        /// `.background`: a container that is not in `containers` (a `ZStack` among them), and an
        /// overlay that is not an edge stroke. `own` is the text's own chain. Empty when there is none.
        func layers(_ path: Path, own: [Link]) -> [String] {
            let links = own + path.links
            return path.containers.filter { !V134B4AboutContrastTests.containers.contains($0.name) }
                .map { "\($0.name) { … } at \(file.location($0.offset))" }
                + links.filter { $0.name == "overlay" && !isEdgeStroke($0, on: links) }
                .map { ".overlay(…) at \(file.location($0.offset))" }
        }

        func firstArgument(_ arguments: Range<Int>) -> String {
            var depth = 0
            for index in arguments {
                switch file.code[index] {
                case UInt8(ascii: "("), UInt8(ascii: "["), UInt8(ascii: "{"): depth += 1
                case UInt8(ascii: ")"), UInt8(ascii: "]"), UInt8(ascii: "}"): depth -= 1
                case UInt8(ascii: ",") where depth == 0: return file.text(arguments.lowerBound..<index)
                default: break
                }
            }
            return file.text(arguments)
        }

        enum Backdrop { case none, paint(Paint, String), unreadable(String) }

        /// What a link paints behind the text. `.background(colour, …)` and `.panel()` paint;
        /// the one `.background { … }` About has — the key-capture view, which draws nothing — does
        /// not, and is recognised by what it contains; any other backdrop is unreadable, and fails.
        func backdrop(_ link: Link) -> Backdrop {
            switch link.name {
            case "panel":
                return V134B4AboutContrastTests.paint("Theme.card", about: file, app: app)
                    .map { .paint($0, "Theme.card") } ?? .unreadable("panel")
            case "background":
                if let arguments = link.arguments {
                    let first = firstArgument(arguments).filter { !$0.isWhitespace }
                    return V134B4AboutContrastTests.paint(first, about: file, app: app)
                        .map { .paint($0, first) } ?? .unreadable(first)
                }
                let closure = link.closure.map { file.text($0) } ?? ""
                let painters = ["Theme.", "Color", ".fill", "Rectangle", "Capsule", "Circle", ".white",
                                ".black", "Image", "Material", "Gradient", "Text("]
                if closure.contains("KeyCaptureView("), !painters.contains(where: closure.contains) { return .none }
                return .unreadable(closure.split(whereSeparator: \.isWhitespace).joined(separator: " "))
            default:
                return .none
            }
        }

        /// The painted backdrops on a path, innermost first.
        func paints(_ links: [Link]) -> [(paint: Paint, expression: String, link: Link)] {
            links.compactMap { link in
                if case .paint(let paint, let expression) = backdrop(link) { return (paint, expression, link) }
                return nil
            }
        }
    }

    static func walker() throws -> Walker {
        try Walker(try Model.shipped("AboutView.swift"), app: try Model.shipped("NihongoRideApp.swift"))
    }

    /// Every `Text` and `Label` inside `AboutView`, in source order.
    static func textViews(_ walker: Walker) -> [CallSiteScanner.Call] {
        textViews.flatMap { walker.file.calls(named: $0) }
            .filter { walker.type.contains($0.nameOffset) }
            .sorted { $0.nameOffset < $1.nameOffset }
    }

    /// A `Text` on About whose arguments are exactly `arguments` (whitespace ignored).
    static func theText(exactly arguments: String, in file: CallSiteScanner.File) throws -> CallSiteScanner.Call {
        let hits = file.calls(named: "Text").filter {
            $0.arguments.map { file.text($0).filter { !$0.isWhitespace } } == arguments
        }
        #expect(hits.count == 1, "\(hits.count) Text(...) on About read exactly \(arguments)")
        return try #require(hits.first, "no Text(\(arguments)) on About")
    }

    @Test("the source reader resolves each colour About uses to what the app resolves it to")
    func paintCalibration() throws {
        let walker = try Self.walker()
        let cases: [(String, Color)] = [
            ("Self.dimTextColor", AboutView.dimTextColor),
            ("Self.dimTextOnCardColor", AboutView.dimTextOnCardColor),
            ("Self.counterColor", AboutView.counterColor),
            ("Theme.card", Theme.card),
            ("Theme.dim", Theme.dim),
            ("Theme.dim.opacity(0.7)", Theme.dim.opacity(0.7)),
            (".white.opacity(0.82)", Color.white.opacity(0.82)),
            (".white", Color.white),
            ("Theme.accent", Theme.accent),
            ("Theme.backgroundTop", Theme.backgroundTop),
        ]
        for (expression, color) in cases {
            let read = try #require(Self.paint(expression, about: walker.file, app: walker.app),
                                    "\(expression) could not be read from the source")
            let resolved = Model.resolved(color)
            #expect(abs(read.alpha - resolved.alpha) < 0.0005
                    && abs(read.rgb.r - resolved.rgb.r) < 0.0005 && abs(read.rgb.g - resolved.rgb.g) < 0.0005
                    && abs(read.rgb.b - resolved.rgb.b) < 0.0005,
                    "\(expression) reads as \(read) from the source; the app resolves it to \(resolved)")
        }
        // Control: what it cannot read, it says so.
        for unreadable in [".ultraThinMaterial", ".secondary", "Theme.nothing", "Rectangle().fill(.red)"] {
            #expect(Self.paint(unreadable, about: walker.file, app: walker.app) == nil, "\(unreadable) read as a colour")
        }
    }

    @Test("the walk climbs through a builder and a let binding to body, and sees every link on the way")
    func walkCalibration() throws {
        let sample = CallSiteScanner.File(path: "Sample.swift", source: """
            struct AboutView: View {
                var body: some View {
                    let content = VStack(spacing: 2) {
                        part
                        Text(b).foregroundStyle(.white) // .opacity(0.1)
                    }
                    .padding(1)
                    return Group { content }.frame(maxWidth: 1).opacity(0.5)
                }
                private var part: some View {
                    VStack { Text(a).italic().foregroundStyle(.white) /* .opacity(0.2) */ }
                        .background(Theme.card, in: Capsule())
                }
                private var unused: some View { Text(c).foregroundStyle(.white) }
            }
            """)
        let app = try Model.shipped("NihongoRideApp.swift")
        let walker = try Walker(sample, app: app)
        let a = try Self.theText(exactly: "a", in: sample)
        #expect(walker.links(after: a.extent.upperBound).map(\.name) == ["italic", "foregroundStyle"])
        let paths = walker.paths(from: a.nameOffset, after: nil)
        #expect(paths.count == 1 && paths.allSatisfy(\.reachesBody))
        #expect(paths.first?.links.map(\.name) == ["background", "padding", "frame", "opacity"],
                "the walk saw \(paths.map { $0.links.map(\.name) })")
        #expect(walker.paints(paths.first?.links ?? []).map(\.expression) == ["Theme.card"])
        #expect(walker.builder(containing: paths.first?.links.first?.offset ?? 0) == "part")
        let c = try Self.theText(exactly: "c", in: sample)
        #expect(walker.paths(from: c.nameOffset, after: nil).isEmpty, "a builder used nowhere reached the page")
        // The blocks on the way, named by what they are the body of: `part`'s VStack, then the
        // `content` VStack, then the Group's closure — a property's body is a builder, not a block.
        #expect(paths.first?.containers.map(\.name) == ["VStack", "VStack", "Group"],
                "the walk named the blocks \(paths.map { $0.containers.map(\.name) })")
        #expect(paths.allSatisfy { walker.layers($0, own: []).isEmpty })
    }

    @Test("the walk names a ZStack, an if branch and a Button label, and tells an edge stroke from any other overlay")
    func layerCalibration() throws {
        let sample = CallSiteScanner.File(path: "Sample.swift", source: """
            struct AboutView: View {
                var body: some View {
                    VStack {
                        ZStack(alignment: .leading) {
                            Theme.card
                            Text(z).foregroundStyle(.white)
                        }
                        if flag { Text(i).foregroundStyle(.white) } else { Text(e).foregroundStyle(.white) }
                        Button(action: go) { Label(l, systemImage: "x").foregroundStyle(.white) }.buttonStyle(.plain)
                        Text(s).padding(14).overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.cardStroke))
                        Text(h).padding(.horizontal, 12).padding(.vertical, 8).overlay(Capsule().strokeBorder(Theme.cardStroke))
                        Text(k).overlay(Color.black.opacity(0.5))
                        Text(t).padding(.top, 6).overlay(Capsule().strokeBorder(Theme.cardStroke))
                        Text(w).padding(14).overlay(Capsule().strokeBorder(Theme.cardStroke, lineWidth: 20))
                        Text(v).padding(14).overlay { Theme.card }
                        Text(n).padding(isPhoneIdiom ? 22 : 40).overlay(Capsule().strokeBorder(Theme.cardStroke))
                    }
                }
            }
            """)
        let walker = try Walker(sample, app: try Model.shipped("NihongoRideApp.swift"))
        func path(_ argument: String, _ name: String = "Text") throws -> (Path, [Link]) {
            let hits = sample.calls(named: name).filter {
                $0.arguments.map { walker.firstArgument($0).filter { !$0.isWhitespace } } == argument
            }
            let call = try #require(hits.count == 1 ? hits.first : nil, "\(name)(\(argument)) is not unique in the sample")
            let paths = walker.paths(from: call.nameOffset, after: nil)
            try #require(paths.count == 1 && paths[0].reachesBody, "\(name)(\(argument)) did not reach body")
            return (paths[0], walker.links(after: call.extent.upperBound))
        }
        let (z, zOwn) = try path("z")
        #expect(z.containers.map(\.name) == ["ZStack", "VStack"])
        #expect(walker.layers(z, own: zOwn).count == 1 && walker.layers(z, own: zOwn).first?.hasPrefix("ZStack") == true,
                "a ZStack sibling behind the text was not seen: \(walker.layers(z, own: zOwn))")
        for argument in ["i", "e"] {
            let (branch, own) = try path(argument)
            #expect(branch.containers.map(\.name) == ["if", "VStack"] && walker.layers(branch, own: own).isEmpty)
        }
        let (l, lOwn) = try path("l", "Label")
        #expect(l.containers.map(\.name) == ["Button", "VStack"] && l.links.map(\.name).first == "buttonStyle"
                && walker.layers(l, own: lOwn).isEmpty)
        for (argument, isStroke) in [("s", true), ("h", true), ("k", false), ("t", false), ("w", false), ("v", false), ("n", false)] {
            let (p, own) = try path(argument)
            let overlay = try #require((own + p.links).first { $0.name == "overlay" })
            #expect(walker.isEdgeStroke(overlay, on: own + p.links) == isStroke,
                    "Text(\(argument))'s overlay classified as \(isStroke ? "not " : "")an edge stroke")
            #expect(walker.layers(p, own: own).isEmpty == isStroke)
        }
    }

    @Test("the rule's idea of dim: anything but full white or a brand accent as written")
    func dimCalibration() throws {
        let walker = try Self.walker()
        let cases: [(String, Bool)] = [
            (".white", false), ("Color.white", false), ("Theme.accent", false), ("Theme.accent2", false),
            ("Self.dimTextColor", true), (".white.opacity(0.82)", true), (".white.opacity(0.99)", true),
            ("Color(red:0.3,green:0.3,blue:0.3)", true), ("Color(red:0.9,green:0.9,blue:0.9)", true),
            ("Theme.accent.opacity(0.5)", true), ("Theme.accent2.opacity(0.3)", true), (".black", true),
            ("Theme.cardStroke", true),
        ]
        for (expression, dim) in cases {
            let paint = try #require(Self.paint(expression, about: walker.file, app: walker.app), "\(expression) unreadable")
            #expect(Self.isDim(expression, paint) == dim, "\(expression) classified as \(dim ? "not " : "")dim")
        }
    }

    @Test("every Text and Label on About has one foregroundStyle, and nothing on its way to the page changes its alpha, layers over or under it, or is unread")
    func nothingElseChangesWhatIsDrawn() throws {
        let walker = try Self.walker()
        let about = walker.file
        let texts = Self.textViews(walker)
        #expect(texts.count >= 21, "only \(texts.count) Text/Label calls found on About — the scan is blind")
        #expect(texts.contains { $0.name == "Label" }, "the back button's Label was not enumerated")
        // None of the `checkedAbsent` title-drawing views on About (the suite doc lists those not
        // checked), and every Button's label is a closure the walk reads, not a title string.
        for name in Self.checkedAbsent {
            let found = about.calls(named: name).filter { walker.type.contains($0.nameOffset) }
            #expect(found.isEmpty, "\(name) at \(found.map { about.location($0.nameOffset) }) draws text this suite does not enumerate")
        }
        for button in about.calls(named: "Button") where walker.type.contains(button.nameOffset) {
            #expect(button.arguments.map { walker.split($0).allSatisfy { $0.hasPrefix("action:") } } ?? true && !button.closures.isEmpty,
                    "\(about.location(button.nameOffset)): a Button with a title the enumeration does not read")
        }
        for text in texts {
            let at = about.location(text.nameOffset)
            let own = walker.links(after: text.extent.upperBound)
            #expect(own.filter { $0.name == "foregroundStyle" }.count == 1,
                    "\(at): the \(text.name)'s own chain has \(own.filter { $0.name == "foregroundStyle" }.count) foregroundStyle, expected exactly one")
            let paths = walker.paths(from: text.nameOffset, after: nil)
            #expect(!paths.isEmpty && paths.allSatisfy(\.reachesBody), "\(at): the walk did not reach body")
            for path in paths {
                let layers = walker.layers(path, own: own)
                #expect(layers.isEmpty, "\(at): drawn in a layer with \(layers) — a ZStack sibling or an overlay can cover the text or sit behind it, and the walk cannot read it as a backdrop")
            }
            for link in own + paths.flatMap(\.links) {
                let where_ = about.location(link.offset)
                #expect(link.name != "opacity", "\(at): .opacity at \(where_) changes the drawn alpha of this text")
                #expect(link.name != "foregroundColor" && (link.name != "foregroundStyle" || own.contains { $0.offset == link.offset }),
                        "\(at): a second colour at \(where_)")
                // `.buttonStyle(.plain)` draws nothing at rest; its pressed state is momentary feedback
                // and is not held. Any other button style is unclassified.
                let plainButton = link.name == "buttonStyle" && link.arguments.map { walker.split($0) == [".plain"] } == true
                #expect(Self.inert.contains(link.name) || plainButton
                        || ["foregroundStyle", "background", "panel", "overlay"].contains(link.name),
                        "\(at): .\(link.name) at \(where_) is not classified — say whether it changes what this text is drawn as")
                if case .unreadable(let what) = walker.backdrop(link) {
                    Issue.record("\(at): the backdrop at \(where_) cannot be read as a colour: \(what)")
                }
            }
        }
    }

    @Test("the seven background texts sit on no backdrop and in no layer; the URL and stat labels sit on exactly their builder's Theme.card")
    func eachTextSitsWhereItsConstantAssumes() throws {
        let walker = try Self.walker()
        for fragment in Self.onTheBackground {
            let text = try Self.theText(containing: fragment, in: walker.file)
            let paths = walker.paths(from: text.nameOffset, after: nil)
            #expect(!paths.isEmpty && paths.allSatisfy(\.reachesBody), "the Text containing \(fragment) does not reach body")
            for path in paths {
                let layers = walker.layers(path, own: walker.links(after: text.extent.upperBound))
                #expect(layers.isEmpty, "the Text containing \(fragment) is drawn in a layer with \(layers)")
                let links = walker.links(after: text.extent.upperBound) + path.links
                let unread = links.filter { if case .unreadable = walker.backdrop($0) { return true } else { return false } }
                #expect(unread.isEmpty, "the Text containing \(fragment) is drawn on a backdrop that cannot be read, at \(unread.map { walker.file.location($0.offset) })")
                let paints = walker.paints(links)
                #expect(paints.isEmpty, "the Text containing \(fragment) is drawn on \(paints.map { "\($0.expression) at \(walker.file.location($0.link.offset))" }), not straight on the background")
            }
        }
        for (fragment, builder) in zip(Self.onACard, ["credit", "stat"]) {
            let text = try Self.theText(containing: fragment, in: walker.file)
            let paths = walker.paths(from: text.nameOffset, after: nil)
            #expect(!paths.isEmpty && paths.allSatisfy(\.reachesBody), "the Text containing \(fragment) does not reach body")
            for path in paths {
                let layers = walker.layers(path, own: walker.links(after: text.extent.upperBound))
                #expect(layers.isEmpty, "the Text containing \(fragment) is drawn in a layer with \(layers)")
                let paints = walker.paints(walker.links(after: text.extent.upperBound) + path.links)
                #expect(paints.count == 1 && paints.first?.expression == "Theme.card" && paints.first?.link.name == "background"
                        && walker.builder(containing: paints.first?.link.offset ?? 0) == builder,
                        "the Text containing \(fragment) is drawn on \(paints.map { "\($0.expression) in \(walker.builder(containing: $0.link.offset) ?? "?")" }), expected exactly \(builder)'s .background(Theme.card, …)")
            }
        }
    }

    /// The rule, not a list: every `Text` and `Label` on About drawn in DIM text — anything that is
    /// not full opaque white and not a brand accent as written (`isDim`): white at an opacity
    /// (`Theme.dim`, a constant, `.white.opacity(x)`), an opaque grey, a brand colour at an opacity —
    /// clears 4.5:1 over the backdrop the walk finds for it (read from the source), at both stops, on
    /// every path. A dim text sits straight on the background or on exactly one `Theme.card`, and on
    /// any other backdrop fails until it has a constant; white at an opacity is also held to at least
    /// that backdrop's constant (`dimTextColor` straight on the background, `dimTextOnCardColor` on
    /// `Theme.card`). The section body (white 0.82) and the credit descriptions (0.7 on a card) pass
    /// by this rule at the numbers written out below, not by being named. (Until the second review
    /// the rule read only white at an opacity, in a `Text`: an opaque grey, or dim text in a `Label`,
    /// was outside it while the suite's title said "all".)
    @Test("every dim text on About, in a Text or a Label, clears 4.5:1 over the backdrop the source puts it on; dim white at no less than its backdrop's constant")
    func everyDimWhiteTextClears() throws {
        let walker = try Self.walker()
        let about = walker.file
        let stops = try Model.gradientStops()
        let white: Model.RGB = (1, 1, 1)
        let onBackground = Model.resolved(AboutView.dimTextColor).alpha
        let onCard = Model.resolved(AboutView.dimTextOnCardColor).alpha
        let card = try #require(Self.paint("Theme.card", about: about, app: walker.app))
        func same(_ a: Paint, _ b: Paint) -> Bool {
            abs(a.alpha - b.alpha) < 1e-9 && abs(a.rgb.r - b.rgb.r) < 1e-9 && abs(a.rgb.g - b.rgb.g) < 1e-9 && abs(a.rgb.b - b.rgb.b) < 1e-9
        }

        var dim: [Int] = []
        for text in Self.textViews(walker) {
            let at = about.location(text.nameOffset)
            let own = walker.links(after: text.extent.upperBound)
            guard let style = own.first(where: { $0.name == "foregroundStyle" }), let arguments = style.arguments else {
                Issue.record("\(at): no foregroundStyle of its own")
                continue
            }
            let expression = about.text(arguments).filter { !$0.isWhitespace }
            guard let foreground = Self.paint(expression, about: about, app: walker.app) else {
                Issue.record("\(at): foregroundStyle(\(expression)) cannot be read as a colour")
                continue
            }
            guard Self.isDim(expression, foreground) else { continue }
            dim.append(text.nameOffset)
            let dimWhite = foreground.rgb == white
            for path in walker.paths(from: text.nameOffset, after: nil) {
                let paints = walker.paints(own + path.links)
                for stop in stops {
                    let backdrop = paints.reversed().reduce(stop) { Self.over($1.paint, $0) }
                    let ratio = Model.contrast(Self.over(foreground, backdrop), backdrop)
                    #expect(ratio >= 4.5, "\(at): \(expression) computes \(ratio):1 over \(paints.map(\.expression)) on \(stop)")
                }
                if paints.isEmpty {
                    #expect(!dimWhite || foreground.alpha >= onBackground - 1e-9 && expression != "Self.dimTextOnCardColor",
                            "\(at): \(expression) straight on the background, under dimTextColor's opacity")
                } else if paints.count == 1, let only = paints.first, same(only.paint, card) {
                    #expect(!dimWhite || foreground.alpha >= onCard - 1e-9 && expression != "Self.dimTextColor" && expression != "Self.counterColor",
                            "\(at): \(expression) on a card, under dimTextOnCardColor's opacity")
                } else {
                    Issue.record("\(at): \(expression) on \(paints.map(\.expression)) — a backdrop with no constant for it")
                }
            }
        }

        // Control: the enumeration sees every dim text there is today — the nine this item
        // recoloured, the two counter lines, the section body and the credit description. (The
        // back button's Label and every brand-colour text are enumerated and are not dim; an opaque
        // grey and a dim Label are shown red by mutation, and `dimCalibration` holds the classes.)
        let expected = try (Self.onTheBackground + Self.onACard + ["breakingIdentifiers(zh ? zhText : en)"])
            .map { try Self.theText(containing: $0, in: about).nameOffset }
            + ["model.unlockOfferLedger.shareableSummary", "model.reviewPromptLedger.debugSummary", "body"]
            .map { try Self.theText(exactly: $0, in: about).nameOffset }
        #expect(Set(expected).isSubset(of: Set(dim)) && expected.count == 13,
                "the enumeration missed \(Set(expected).subtracting(dim).map(about.location))")
    }

    @Test("over the backdrops read from the source: footer 4.62, URL 4.57, section body 10.70, credit description 7.16 at the bottom stop")
    func sourceBackdropsComputeTheStatedNumbers() throws {
        let walker = try Self.walker()
        let about = walker.file
        let bottom = try Self.bottomStop()
        // (the Text, its colour as written, its contrast at the bottom stop and at the top stop)
        let cases: [(CallSiteScanner.Call, String, Double, Double)] = [
            (try Self.theText(containing: "Thanks to the maintainers", in: about), "Self.dimTextColor", 4.62, 4.91),
            (try Self.theText(containing: "Self.breakingIdentifiers(url) : url", in: about), "Self.dimTextOnCardColor", 4.57, 5.03),
            (try Self.theText(exactly: "body", in: about), ".white.opacity(0.82)", 10.70, 12.13),
            (try Self.theText(containing: "breakingIdentifiers(zh ? zhText : en)", in: about), ".white.opacity(0.7)", 7.16, 8.16),
        ]
        let top = try Model.gradientStops()[0]
        for (text, expression, atBottom, atTop) in cases {
            let at = about.location(text.nameOffset)
            let style = try #require(walker.links(after: text.extent.upperBound).first { $0.name == "foregroundStyle" })
            #expect(about.text(try #require(style.arguments)).filter { !$0.isWhitespace } == expression,
                    "\(at) is no longer drawn in \(expression)")
            let foreground = try #require(Self.paint(expression, about: about, app: walker.app))
            let path = try #require(walker.paths(from: text.nameOffset, after: nil).first)
            let paints = walker.paints(walker.links(after: text.extent.upperBound) + path.links)
            for (stop, stated) in [(bottom, atBottom), (top, atTop)] {
                let backdrop = paints.reversed().reduce(stop) { Self.over($1.paint, $0) }
                let ratio = Model.contrast(Self.over(foreground, backdrop), backdrop)
                #expect(abs(ratio - stated) < 0.01, "\(at) computes \(ratio):1 over \(paints.map(\.expression)); written out as \(stated)")
            }
        }
    }
}

/// A pin, not a layout test: a source scan cannot measure AX5, and `HorizontalTextFitTests` cannot
/// see these two headers any more (their `Text`s moved into properties, which is its documented
/// helper blind spot). What it can say is that the switch is still there and each Back button
/// still carries exactly one identifier — `PaidRouteRowTests` lands on Settings by that one.
///
/// **Every pin here reads the code, never the comments** (`source(_:)`: comments blanked, strings
/// kept, through `CallSiteScanner`). They first read the raw file, and round 2 of the pre-submission
/// review switched each fix off the way this release's own calibration treats as realistic —
/// `if false { // if typeSize.isAccessibilitySize {`, `.lineLimit(nil) // .lineLimit(typeSize…` —
/// and all of them stayed green, because the old condition was still in the file, in the comment.
/// Mutation, 2026-09-18: those five commented mutants (About's credit and Settings' Language row,
/// About's section-title limits, Settings' header, and `JournalView.trendHeader` next door in
/// `V133LAccessibilityLayoutTests`) each go red. (v1.33 pre-submission review, round 2)
@Suite("V133S: the Settings and About headers switch at accessibility sizes")
struct V133SHeaderSourceTests {

    @Test("each header has an accessibility-size branch, and one Back identifier")
    func headersSwitch() throws {
        for (file, identifier) in [("SettingsView.swift", "settingsBackButton"),
                                   ("AboutView.swift", "aboutBackButton")] {
            let source = try Self.source(file)
            #expect(source.components(separatedBy: "\"\(identifier)\"").count - 1 == 1,
                    "\(file) should carry \(identifier) exactly once")
            let start = try #require(source.range(of: "private var header: some View"), "\(file) has no header")
            let body = HorizontalTextFitTests.functionBody(of: source, from: start.lowerBound)
            #expect(!body.isEmpty && !body.contains("private var headerTitle"),
                    "the brace walk did not find \(file)'s header, or overran it")
            #expect(body.contains("typeSize.isAccessibilitySize"), "\(file)'s header no longer switches at AX sizes")
            #expect(body.contains("backButton"))
        }
    }

    /// `file`'s code with its comments blanked and its strings kept (lines unchanged), so
    /// a switch that survives only in a comment is not found — see the suite's note.
    static func source(_ file: String) throws -> String {
        let raw = try String(contentsOf: HorizontalTextFitTests.appDirectory.appendingPathComponent(file), encoding: .utf8)
        return CallSiteScanner.File(path: file, source: raw).allCodeWithStrings
    }

    /// The other three accessibility-size fixes of group S. The pre-submission review replaced each
    /// switch with `if false` and every test stayed green, so they were unguarded; these pins are
    /// what goes red now. Same limit as above — a pin that the switch exists, not a measurement.
    @Test("the Language row stacks at accessibility sizes, and only there")
    func languageRowSwitch() throws {
        let source = try Self.source("SettingsView.swift")
        let stacked = try #require(source.range(of: "rowLabel(icon: \"globe\""), "the stacked Language row is gone")
        let shared = try #require(source.range(of: "row(icon: \"globe\""), "the shared Language row is gone")
        let branch = try #require(source.range(of: "if typeSize.isAccessibilitySize {", options: .backwards,
                                               range: source.startIndex..<stacked.lowerBound))
        let head = source[branch.upperBound..<stacked.lowerBound]
        #expect(head.count < 200 && !head.contains("}"),
                "the stacked Language row is not the first thing inside an accessibility-size branch")
        let elseBranch = try #require(source.range(of: "} else {", range: stacked.upperBound..<source.endIndex))
        #expect(elseBranch.upperBound <= shared.lowerBound
                && source[elseBranch.upperBound..<shared.lowerBound].count < 80,
                "the shared Language row is not the else-branch of that switch")
    }

    @Test("About's credits stack and its section titles stay on one line at accessibility sizes")
    func aboutCreditAndTitleSwitches() throws {
        let source = try Self.source("AboutView.swift")
        let creditStart = try #require(source.range(of: "private func credit("), "credit(…) moved")
        let credit = HorizontalTextFitTests.functionBody(of: source, from: creditStart.lowerBound)
        #expect(!credit.isEmpty && !credit.contains("private func section("), "the brace walk missed credit(…)")
        #expect(credit.contains("if typeSize.isAccessibilitySize {"), "the credit rows no longer stack at AX sizes")
        #expect(credit.contains("Text(Self.breakingIdentifiers(name))"),
                "the stacked credit no longer breaks identifier-like names between their parts")

        let sectionStart = try #require(source.range(of: "private func section(title:"), "section(title:body:) moved")
        let section = HorizontalTextFitTests.functionBody(of: source, from: sectionStart.lowerBound)
        #expect(!section.isEmpty && !section.contains("private func credit("), "the brace walk missed section(…)")
        #expect(section.contains(".lineLimit(typeSize.isAccessibilitySize ? 1 : nil)")
                && section.contains(".minimumScaleFactor(typeSize.isAccessibilitySize ? 0.5 : 1)"),
                "\"ACKNOWLEDGEMENTS\" can break mid-word again at AX sizes")
    }
}
