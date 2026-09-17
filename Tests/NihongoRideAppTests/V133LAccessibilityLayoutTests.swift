import Testing
import Foundation

/// The v1.33 §B L accessibility-size layouts, pinned where no other instrument can see them.
///
/// Two instruments exist for this defect class and both are blind here. `ImageRenderer` does not
/// drive Dynamic Type, so every headless render takes the non-accessibility branch of each switch
/// below (`ScaledFont.swift`). `HorizontalTextFitTests` reads one function at a time, and two of
/// these fixes moved a `Text` into a helper with no row of its own — the Ride Log's BEST badge
/// (`bestBadge`) and the Word Lists name (`openListButton`) — which takes them OUT of its count
/// while the rows that hold them are still rows. Its own `dueChip` test compensates for exactly
/// that kind of blind spot, and this file does the same for the ones this release created.
///
/// These read source, so they cannot say a layout WORKS — only that the switch is still there.
/// That is the regression they are for: somebody "simplifying" a two-branch view back to its
/// one-row form, which every other gate in this repo would pass.
///
/// Mutation, 2026-09-17: replacing `typeSize.isAccessibilitySize` in `JournalView.trendHeader` with
/// `false` turned `theAccessibilitySwitchesAreStillThere` red naming `trendHeader`, and nothing
/// else in the suite moved.
@Suite("V133L: the accessibility-size layouts the scan and the renders cannot see")
struct V133LAccessibilityLayoutTests {

    static func source(_ file: String) throws -> String {
        try String(contentsOf: HorizontalTextFitTests.appDirectory.appendingPathComponent(file),
                   encoding: .utf8)
    }

    /// The body of the first `declaration` found at or after `anchor` (or the file start), read with
    /// comments blanked and strings kept. It read the raw file until round 2 of the pre-submission
    /// review turned `trendHeader`'s switch into `if false { // typeSize.isAccessibilitySize` and
    /// `theAccessibilitySwitchesAreStillThere` stayed green on the comment; mutation, 2026-09-18:
    /// that mutant now goes red. `source(_:)` itself stays raw, because `practiceIsTranslated`'s
    /// control needs to see a comment. (v1.33 pre-submission review, round 2)
    static func body(_ file: String, _ declaration: String, after anchor: String? = nil) throws -> String {
        let text = CallSiteScanner.File(path: file, source: try source(file)).allCodeWithStrings
        let start = anchor.flatMap { text.range(of: $0)?.lowerBound } ?? text.startIndex
        guard let found = text.range(of: declaration, range: start..<text.endIndex) else { return "" }
        return HorizontalTextFitTests.functionBody(of: text, from: found.lowerBound)
    }

    @Test("each fixed row still switches at the accessibility sizes")
    func theAccessibilitySwitchesAreStillThere() throws {
        let sites: [(file: String, declaration: String, anchor: String?)] = [
            ("ListsView.swift", "private func listRow", nil),
            ("ListsView.swift", "private var header", "struct ListDetailView"),
            ("JournalView.swift", "private func trendHeader", nil),
            ("StatsView.swift", "private var conjugationCard", nil),
            ("PracticeView.swift", "private func topBar", nil),
        ]
        for site in sites {
            let body = try Self.body(site.file, site.declaration, after: site.anchor)
            // Bounded, so a brace walk that ran into the next declaration cannot pass on ITS text.
            #expect(!body.isEmpty && body.count < 4000,
                    "\(site.file) \(site.declaration): the brace walk returned \(body.count) characters")
            #expect(body.contains("typeSize.isAccessibilitySize"),
                    "\(site.file) \(site.declaration) no longer switches layout at the accessibility sizes")
        }
    }

    /// The anchors above must name the RIGHT declaration: `ListsView` has its own `header`, which
    /// does not switch, and a lookup that found it would be testing the wrong screen.
    @Test("control: the anchor picks the detail header, not the Word Lists one")
    func theAnchorIsCalibrated() throws {
        let lists = try Self.body("ListsView.swift", "private var header")
        #expect(lists.contains("listsBackButton") && !lists.contains("isAccessibilitySize"))
        let detail = try Self.body("ListsView.swift", "private var header", after: "struct ListDetailView")
        #expect(!detail.contains("listsBackButton"))
    }

    @Test("the stacked ride row's icon tile grows with its glyph")
    func theRideIconTileScales() throws {
        let row = try Self.body("JournalView.swift", "private func stackedRideRow")
        #expect(row.contains("stackedIconTile"), "the stacked row's icon is back in a fixed tile")
        #expect(!row.contains("width: 26, height: 26"),
                "a fixed 26pt tile holds a 73pt glyph at AX5 and it overlaps the date")
    }

    @Test("the hints-off badge keeps its one-line floor")
    func theBadgeKeepsItsFloor() throws {
        let badge = try Self.body("PracticeView.swift", "private var hintsOffBadge")
        #expect(badge.contains("lineLimit(1)"))
    }

    /// The Chinese UI showed "PRACTICE", "BLIND" and "ACC". Each is now one side of a `zh ?`.
    ///
    /// Read with strings kept and comments blanked. On the raw file the Chinese checks passed on
    /// their own explanations: "练习", "提示已关" and "正确率" are each quoted in a comment beside the
    /// label, so the review turned all three ternaries back to English and this stayed green. And each
    /// Chinese word is held as the `zh` side of the ternary whose other side is the English word it
    /// replaced, so a Chinese string elsewhere in the file cannot stand in for it.
    @Test("Practice has no English-only label left on screen")
    func practiceIsTranslated() throws {
        let file = try #require(try CallSiteScanner.shippedSources.get()
            .first { $0.path == "Sources/NihongoRideApp/PracticeView.swift" })
        let practice = file.allCodeWithStrings
        for literal in ["Text(\"PRACTICE", "Text(\"BLIND\")", "stat(\"ACC\""] {
            #expect(!practice.contains(literal), "\(literal) is shown to Chinese readers untranslated")
        }
        for (zh, en) in [("练习", "PRACTICE"), ("提示已关", "BLIND"), ("正确率", "ACC")] {
            #expect(practice.range(of: #"\?\s*"\#(zh)"\s*:\s*"\#(en)""#, options: .regularExpression) != nil,
                    "no `? \"\(zh)\" : \"\(en)\"` in PracticeView's code")
        }
        // Control: the comment that quotes each Chinese word is not in the view read above.
        let raw = try Self.source("PracticeView.swift")
        #expect(raw.contains("// \"练习\" in Chinese") && !practice.contains("// \"练习\" in Chinese"),
                "the comment view is not stripping comments, or the comment this control names moved")
    }
}
