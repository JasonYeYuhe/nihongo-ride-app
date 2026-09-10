import Testing
import Foundation
import GameCore
@testable import NihongoRideApp

/// The first-launch intro must name every mode that ships (v1.32 §F1).
///
/// **What was wrong.** `OnboardingView` said *"Three modes"* and named Journey, Time Attack and
/// Practice. `GameMode` has six cases. Verbs, Sentence and Listen — added in v1.6, v1.18 and
/// v1.21 — were advertised nowhere a new user would look: not in the intro, and not in the store
/// description, which says the same thing and is frozen for the measurement window
/// (`PLAN-WINDOW` constraint 4). The in-app copy is not frozen, which is why this is the half of
/// the fix the window permits.
///
/// **Why a copy edit was not the fix.** It drifted twice already, silently, across two releases
/// that each added a mode. The page is now composed from `GameMode.allCases`, so adding a case is
/// a compile error in `GameMode.onboardingClause` — and this file is what makes the *page* follow,
/// rather than the enum quietly growing a case the intro never mentions.
///
/// This is the same shape as `GameMode.completedUnitLabel`, whose own doc records what it cost the
/// first time: *"reverting the call site to a bare 'Words' left the entire suite green, because
/// the test can only see this file."*
///
/// `@MainActor` because `OnboardingView` is a SwiftUI `View`, so even its static members are
/// main-actor isolated — and under this package's language mode that is a RUNTIME check, not a
/// compile-time one. The first version of this file compiled clean and the test process died with
/// SIGTRAP after starting five tests: three of them touched `OnboardingView`, two touched only
/// `GameMode` and passed. "Compiles" is not "is allowed to run".
@MainActor
@Suite("The first-launch intro names every mode that ships")
struct OnboardingModesTests {

    /// The assertion that cannot be satisfied by editing a string.
    @Test("every GameMode is named in the intro, in both languages")
    func everyModeIsNamed() {
        for zh in [false, true] {
            let text = OnboardingView.modeChunks.indices
                .map { OnboardingView.modesBody(zh: zh, chunk: $0) }
                .joined(separator: " ")
            for mode in GameMode.allCases {
                #expect(text.contains(mode.shortLabel(zh: zh)),
                        "\(mode) is not named in the \(zh ? "zh" : "en") intro")
                #expect(text.contains(mode.onboardingClause(zh: zh)),
                        "\(mode) has no clause in the \(zh ? "zh" : "en") intro")
            }
        }
    }

    /// The chunking must not silently drop a mode — a bug in the `stride` would produce a page
    /// set that omits the tail, and the test above would then fail for a reason nobody could read.
    @Test("the chunks partition allCases exactly, with no mode lost or repeated")
    func chunksPartitionTheModes() {
        let flattened = OnboardingView.modeChunks.flatMap { $0 }
        #expect(flattened == GameMode.allCases)
        #expect(OnboardingView.modeChunks.allSatisfy { !$0.isEmpty })
        #expect(OnboardingView.modeChunks.allSatisfy { $0.count <= OnboardingView.modesPerPage },
                "a page carries more modes than the density that is known to render")
    }

    /// The numbers in the copy are derived, so they cannot drift from the enum.
    ///
    /// A hand-written numeral is the smallest possible version of the defect this page had, and
    /// it is the one an editor is most likely to reintroduce while "just fixing the wording".
    @Test("the intro's numerals count the modes rather than stating a remembered number")
    func numeralsAreDerived() {
        #expect(OnboardingView.modesTitle(zh: false, chunk: 0) == "Six modes")
        #expect(OnboardingView.modesTitle(zh: true, chunk: 0) == "六种模式")
        #expect(OnboardingView.modesTitle(zh: false, chunk: 1) == "Three more")
        #expect(OnboardingView.modesTitle(zh: true, chunk: 1) == "还有三种")

        // …and the control: the numeral tracks a COUNT. These are the two functions the titles
        // are built from, so a title hard-coded back to "Six" would still pass the four
        // assertions above while these keep it honest.
        #expect(OnboardingView.englishNumeral(GameMode.allCases.count) == "six")
        #expect(OnboardingView.chineseNumeral(GameMode.allCases.count) == "六")
        #expect(OnboardingView.englishNumeral(7) == "seven")
        #expect(OnboardingView.chineseNumeral(7) == "七")
    }

    /// The intro carries no offer language, and must not gain any (`PLAN-WINDOW` constraint 1:
    /// do not touch the offer, the price or the placement — voids the pre-registration).
    ///
    /// The clauses are new copy shown to every fresh install during the measurement window, so
    /// this is worth a check rather than an intention. `Journey`'s clause says "unlock landmarks",
    /// which is about the free road; the words below are the ones that would make the intro a
    /// third purchase entrance.
    /// **The population is the WHOLE intro, not just the mode clauses.**
    ///
    /// It was the clauses alone — roughly a third of what a fresh install reads — while §K credited
    /// this test with guarding the intro. So the titles, the bodies and the four non-mode pages
    /// were uncovered, and constraint 1 is the one whose breach voids the pre-registration. The
    /// four literal pages cannot be reached through an API (`OnboardingView.pages` is `private` on
    /// a SwiftUI view), so they are scanned in source — the same technique `theMenuPickerIsDerived`
    /// below already uses in this file, for the same reason. (v1.32 pre-submission review.)
    @Test("nothing in the intro mentions the road, a price, or a purchase")
    func theIntroCarriesNoOfferLanguage() throws {
        let forbidden = ["Kyōto", "Kyoto", "京都", "西", "Road West", "road west",
                         "purchase", "buy", "unlock the road", "购买", "解锁道路", "¥", "$"]
        var inspected = 0
        func check(_ text: String, _ where_: String) {
            inspected += 1
            for word in forbidden {
                #expect(!text.contains(word),
                        "\(where_) contains offer language: \(word) — that makes the intro a third purchase entrance, which is a constraint-1 change and voids the §K pre-registration")
            }
        }

        for zh in [false, true] {
            for mode in GameMode.allCases {
                check(mode.onboardingClause(zh: zh), "\(mode)'s \(zh ? "zh" : "en") clause")
                check(mode.shortLabel(zh: zh), "\(mode)'s \(zh ? "zh" : "en") label")
            }
            for chunk in 0..<OnboardingView.modeChunks.count {
                check(OnboardingView.modesTitle(zh: zh, chunk: chunk), "modes page \(chunk) title (\(zh ? "zh" : "en"))")
                check(OnboardingView.modesBody(zh: zh, chunk: chunk), "modes page \(chunk) body (\(zh ? "zh" : "en"))")
            }
        }
        #expect(inspected >= (GameMode.allCases.count * 4) + 4,
                "the scan saw \(inspected) strings — it is measuring a smaller population than it claims")

        // The four non-mode pages are string literals inside a `private` computed property, so the
        // only instrument that can see them is the source. The floor matters as much as the rule.
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Sources/NihongoRideApp/OnboardingView.swift"),
            encoding: .utf8)
        #expect(source.count > 4_000, "read \(source.count) bytes — the scan is misdirected")
        #expect(source.contains("Page(icon:"), "the pages array moved; this scan is measuring nothing")
        let code = source.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        for word in forbidden where word != "$" {   // `$` is Swift interpolation, not a price
            #expect(!code.contains(word),
                    "OnboardingView's source contains offer language: \(word) — constraint 1")
        }
    }

    /// The menu capsule and the intro use the SAME label, deliberately: the intro's job is to
    /// point at the menu, so a learner who reads "Verbs" here must find "Verbs" there.
    ///
    /// **This is a source scan and it exists because the first version of this file did not have
    /// one.** The doc comment here used to say `MenuView.modeOptions` maps `GameMode.allCases`, so
    /// agreement was "true by construction" — and a mutation that reverted the menu to a
    /// hand-written list of three left the whole suite green. A comment asserting a property
    /// nothing enforces is this project's cheapest and most-repeated defect, and I had just
    /// written one into the test file whose subject is that exact defect.
    ///
    /// `modeOptions` is `private` on a SwiftUI view with no renderable test path, so the property
    /// is checked where it is written. The floor matters as much as the rule: a scan that read the
    /// wrong file would report clean.
    @Test("the menu builds its mode picker from allCases, not from a hand-written list")
    func theMenuPickerIsDerived() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let menu = try String(contentsOf: root.appendingPathComponent("Sources/NihongoRideApp/MenuView.swift"),
                              encoding: .utf8)
        #expect(menu.count > 10_000, "MenuView.swift read as \(menu.count) bytes — the scan is misdirected")
        #expect(menu.contains("private var modeOptions"), "the property this test is about is gone")
        #expect(menu.contains("GameMode.allCases.map { ($0, $0.shortLabel(zh: zh)) }"),
                "the mode picker no longer derives its entries from GameMode.allCases")

        // And the negative half: no mode label may be written literally in the view's CODE. That
        // is the form the drift took — a list of six strings that a seventh mode does not join.
        //
        // Comments are stripped first, and the reason is a false positive this scan actually
        // produced: MenuView:155 explains a truncation problem by quoting "Sentence" and
        // "Practice", which is a legitimate use and not a label the picker reads. A scan that
        // forces authors to stop naming things in comments is a scan people route around.
        let code = menu.components(separatedBy: "\n")
            .map { line -> String in
                guard let marker = line.range(of: "//") else { return line }
                return String(line[..<marker.lowerBound])
            }
            .joined(separator: "\n")
        #expect(code.contains("GameMode.allCases.map"), "comment stripping ate the code")
        for mode in GameMode.allCases {
            for zh in [false, true] {
                let literal = "\"\(mode.shortLabel(zh: zh))\""
                #expect(!code.contains(literal),
                        "MenuView writes the label \(literal) literally; it must ask GameMode for it")
            }
        }
    }

    @Test("every mode has a non-empty label and clause in both languages")
    func everyModeHasCopy() {
        for mode in GameMode.allCases {
            for zh in [false, true] {
                #expect(!mode.shortLabel(zh: zh).isEmpty)
                #expect(!mode.onboardingClause(zh: zh).isEmpty)
            }
            #expect(mode.shortLabel(zh: false) != mode.shortLabel(zh: true),
                    "\(mode)'s two languages give the same string — one of them is untranslated")
        }
        let english = Set(GameMode.allCases.map { $0.shortLabel(zh: false) })
        #expect(english.count == GameMode.allCases.count, "two modes share a label")
        let chinese = Set(GameMode.allCases.map { $0.shortLabel(zh: true) })
        #expect(chinese.count == GameMode.allCases.count, "two modes share a Chinese label")
    }
}
