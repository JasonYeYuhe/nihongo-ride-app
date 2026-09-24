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
/// bottom stop) while the two on a card share another (`Theme.card` over that stop). What is
/// deliberately NOT held here: the two counter lines, whose colour 1.33 fixed and whose text is
/// frozen (`aboutUsesTheCounterColor` above); and text that is not dim — the coral section titles
/// (5.65:1), the sky version line (8.15:1) and the licence badges (4.28:1 on their tinted
/// background, the one small text on About still under the line, left because it is the brand
/// colour and PLAN-V1.34 §I keeps brand-colour contrast on the day-91 list).
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
