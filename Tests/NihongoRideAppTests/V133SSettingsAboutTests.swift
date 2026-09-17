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
@Suite("V133S: small dim text in Settings and About reaches 4.5:1 wherever it can sit")
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
}

/// A pin, not a layout test: a source scan cannot measure AX5, and `HorizontalTextFitTests` cannot
/// see these two headers any more (their `Text`s moved into properties, which is its documented
/// helper blind spot). What it can say is that the switch is still there and each Back button
/// still carries exactly one identifier — `PaidRouteRowTests` lands on Settings by that one.
@Suite("V133S: the Settings and About headers switch at accessibility sizes")
struct V133SHeaderSourceTests {

    @Test("each header has an accessibility-size branch, and one Back identifier")
    func headersSwitch() throws {
        for (file, identifier) in [("SettingsView.swift", "settingsBackButton"),
                                   ("AboutView.swift", "aboutBackButton")] {
            let source = try String(contentsOf: HorizontalTextFitTests.appDirectory.appendingPathComponent(file),
                                    encoding: .utf8)
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

    static func source(_ file: String) throws -> String {
        try String(contentsOf: HorizontalTextFitTests.appDirectory.appendingPathComponent(file), encoding: .utf8)
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
