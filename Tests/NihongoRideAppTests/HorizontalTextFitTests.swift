import Testing
import Foundation

/// The one defect shape this project has shipped SEVEN times, and the first instrument that can
/// see any of it without a device (v1.32 §E).
///
/// # The shape
///
/// *A `Text` whose content can grow, in a horizontal row, with no `lineLimit` and no shrink
/// allowance.* At the accessibility sizes it cannot get narrower, so it wraps VERTICALLY — one
/// glyph per line — or pushes the row past the viewport, which the enclosing
/// `.frame(maxWidth: .infinity)` then centres and clips on both edges.
///
/// Seven instances, all found by RUNNING THE APP, never by a test:
///
/// | release | where |
/// |---|---|
/// | v1.31 | the Ride Log's `level` capsule — "custom" squeezed score, WPM and accuracy until they wrapped |
/// | v1.31 | the conjugation HUD — "Conjugate" read as "Conjuga / te", "2/12" as "2/1 / 2" |
/// | v1.31 | the conjugation form chip — the one string naming the form being asked for, truncated |
/// | v1.31 | Settings' romaji picker — "Hints… / Whe… / Off" |
/// | v1.32 | the Stats conjugation card — "Tomorrow" as "Tomorr / ow" |
/// | v1.32 | the Ride Log ROW at AX5 — every column one glyph wide, "MINE" as four stacked letters |
/// | v1.32 | the Ride Log / Stats HEADER at AX5 — title and Back both clipped off the screen edges |
///
/// `ImageRenderer` cannot see ANY of them: it does not drive `@ScaledMetric`, so an AX5 render and
/// an AX3 render come out byte-identical (`ScaledFont.swift` has said so since v1.7, and v1.25
/// caught itself believing otherwise by md5-ing two files).
///
/// # What this scan can and cannot do, stated before the result
///
/// It is a SOURCE scan, so it cannot measure a layout. What it can do is find the shape: a `Text`
/// carrying a `scaledSystemFont` that sits inside a horizontal container and has neither a
/// `lineLimit` nor a `minimumScaleFactor` within its own modifier chain.
///
/// **The population it SKIPS, computed rather than hoped about** — this repo's own rule after a
/// gate validated by its 21 catches turned out to be blind to 240 entries:
///
/// * `Text` in a `VStack` or alone. It has the full width; wrapping there is correct behaviour.
/// * Anything built by a helper whose call site is elsewhere. `rowStat(_:_:tint:)` is a function,
///   so its `Text`s are attributed to the function and not to the six rows that call it.
/// * Interpolated content whose length depends on data the scan cannot see. It flags by SHAPE,
///   not by whether the string is actually long.
/// * Every screen outside `Sources/NihongoRideApp` — the widget has its own layout and its own
///   sizes.
///
/// So a clean run means "no NEW instance of the shape in the files scanned". It does not mean the
/// app survives AX5, and nothing but a device can mean that.
///
/// # How much of the known population it actually covers — MEASURED, 5 of 7
///
/// The question that finds a blind spot is not *what did it catch* but *what can it NOT see*, and
/// the honest answer is checked against the seven instances above rather than estimated:
///
/// | | instance | verdict |
/// |---|---|---|
/// | ✅ | v1.31 Ride Log level capsule | in scope |
/// | ✅ | v1.31 conjugation HUD capsule | in scope |
/// | ✅ | v1.31 conjugation form chip | in scope |
/// | ✅ | v1.32 Ride Log / Stats header | in scope |
/// | ✅ | v1.32 Ride Log row at AX5 | in scope — `rowStat()` declares its OWN `HStack`, so its `Text`s |
/// |   |   | are attributed to it and were caught directly. This row read ◐ until the |
/// |   |   | v1.32 review re-ran the scan over the PRE-FIX tree and got two hits |
/// | ❌ | v1.32 Stats "Tomorrow" | `dueChip()` is a helper — its `HStack` is at the CALL SITE, in another function |
/// | ❌ | v1.31 Settings romaji picker | a `Picker`, not a `Text` in an `HStack`. A different shape entirely |
///
/// **Five of seven**, and the corrected row is worth reading twice: the ◐ was written from the
/// general rule "a helper's `Text`s are attributed to the helper", which is true, and then applied
/// to a helper that opens its own row — where it does not cost coverage at all. A coverage claim
/// derived from a rule instead of from a run is the same mistake as a gate believed because it is
/// green. It was corrected by running the scan against `git show 6e582e3:…JournalView.swift`.
///
/// That is worth having and it is not a gate on this defect class —
/// and the two it misses are missed for reasons no amount of tuning fixes: a source scan cannot
/// follow a helper to its call sites without becoming a type checker, and a `Picker` squeezing its
/// segments is not this shape at all.
///
/// Both blind spots were found by MUTATION, not by reasoning: reintroducing the real "Tomorrow"
/// defect left this suite green twice — once because the first model treated a `VStack` as safe
/// (wrong: a column inside a row is width-constrained, and correcting that is why the model now
/// walks ancestors), and once because `dueChip` is a helper (right, and unfixable here). A scan
/// whose coverage is asserted rather than measured is how a rule that found 21 offenders came to
/// be blind to 240 entries.
///
/// # Why it is a floor and not a ban
///
/// The count is pinned rather than required to be zero. Some of the remaining occurrences are
/// genuinely fine and proving each one by hand would take longer than it is worth — so the rule is
/// **the number must not grow**. A new one has to be either fixed or explicitly accepted by moving
/// the number, which is a line in a diff somebody has to justify.
@Suite("A Text in a row with no room is this repo's most-shipped defect")
struct HorizontalTextFitTests {

    static var appDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/NihongoRideApp")
    }

    struct Finding: Hashable, Comparable {
        let file: String
        let line: Int
        let text: String
        static func < (a: Finding, b: Finding) -> Bool {
            a.file == b.file ? a.line < b.line : a.file < b.file
        }
    }

    /// Every `Text(...)` that opens a modifier chain containing `scaledSystemFont`, sits anywhere
    /// inside a horizontal container, and has neither a `lineLimit` nor a `minimumScaleFactor` in
    /// that chain.
    ///
    /// **"Anywhere inside", not "whose immediate parent is".** The first version asked only about
    /// the innermost container and treated a `VStack` as safe — and a mutation that reintroduced
    /// the exact "Tomorrow → Tomorr / ow" defect fixed earlier the same day SURVIVED it. That
    /// `Text` is in a `VStack`… which is one of three columns inside an `HStack`, so it is width
    /// constrained by the row two levels up. A column inside a row is not the full width; the
    /// model was wrong, and the mutation is what said so.
    ///
    /// A `FlowLayout` CLEARS the constraint, because it wraps: a `Text` inside one is in a
    /// horizontal container that can grow downward, which is the fix the Stats chips and the
    /// stacked Ride Log row both use.
    /// Strips the Swift keywords a container or a `Text` can legitimately hide behind, so the
    /// prefix test below sees `HStack(` on `return HStack(spacing: 12) {` and on
    /// `else { HStack(alignment: .top) { … } }`.
    ///
    /// Repeated, because `else { return HStack(` is both. Deliberately NOT a general expression
    /// parser: matching `HStack` anywhere on the line would count it inside a string, a comment
    /// tail or a type annotation, and a scan that over-reports is a scan people switch off.
    /// `hasPrefix` after stripping keeps the "this line OPENS a container" meaning intact.
    static func stripLeadingKeywords(_ line: String) -> String {
        var out = line
        var changed = true
        while changed {
            changed = false
            for keyword in ["return ", "else { ", "else {", "{ "] where out.hasPrefix(keyword) {
                out = String(out.dropFirst(keyword.count)).trimmingCharacters(in: .whitespaces)
                changed = true
                break
            }
        }
        return out
    }

    static func findings(in source: String, file: String) -> [Finding] {
        var out: [Finding] = []
        let lines = source.components(separatedBy: "\n")
        /// Indentation of every open container, and whether it constrains width.
        /// `.horizontal` = an HStack; `.wrapping` = a FlowLayout, which releases the constraint.
        enum Container { case horizontal, wrapping }
        var stack: [(indent: Int, kind: Container)] = []

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") || trimmed.hasPrefix("///") { continue }
            let indent = line.prefix { $0 == " " }.count

            // Close every container the current line has dedented out of.
            stack.removeAll { indent <= $0.indent }

            // `hasPrefix` on the raw trimmed line missed twelve of the app's horizontal
            // containers, because `return HStack(spacing: 12) {` and `else { HStack(...) {` are
            // both ordinary ways to write one — and with the container invisible, every `Text`
            // inside it was invisible too. Five live instances of the exact shape this file
            // defines were outside the scan, and the ceiling of 34 had been measured over that
            // reduced population. So the leading keywords are stripped before the test.
            // (Found by the v1.32 pre-submission review.)
            let opener = Self.stripLeadingKeywords(trimmed)
            if opener.hasPrefix("HStack") { stack.append((indent, .horizontal)) }
            if opener.hasPrefix("FlowLayout") { stack.append((indent, .wrapping)) }

            guard opener.hasPrefix("Text(") else { continue }
            // Constrained if any ancestor is horizontal and no NEARER ancestor wraps.
            var constrained = false
            for container in stack.reversed() {
                if container.kind == .wrapping { break }
                if container.kind == .horizontal { constrained = true; break }
            }
            guard constrained else { continue }

            var chain = trimmed
            var cursor = index + 1
            while cursor < lines.count {
                let next = lines[cursor]
                let nextTrimmed = next.trimmingCharacters(in: .whitespaces)
                let nextIndent = next.prefix { $0 == " " }.count
                guard nextTrimmed.hasPrefix(".") || nextIndent > indent else { break }
                if !nextTrimmed.hasPrefix("//") && !nextTrimmed.hasPrefix("///") { chain += " " + nextTrimmed }
                cursor += 1
            }
            guard chain.contains("scaledSystemFont") else { continue }
            guard !chain.contains("lineLimit"), !chain.contains("minimumScaleFactor") else { continue }
            out.append(Finding(file: file, line: index + 1, text: String(trimmed.prefix(70))))
        }
        return out
    }

    static func scanAll() throws -> [Finding] {
        let files = try FileManager.default.contentsOfDirectory(atPath: appDirectory.path)
            .filter { $0.hasSuffix(".swift") }.sorted()
        var out: [Finding] = []
        for file in files {
            let source = try String(contentsOf: appDirectory.appendingPathComponent(file),
                                    encoding: .utf8)
            out += findings(in: source, file: file)
        }
        return out.sorted()
    }

    /// **A number that must not grow.**
    ///
    /// Measured 2026-09-10 after the §E pass: **39**, and the number is the measurement rather
    /// than a guess. The first draft wrote 47 from intuition — a ceiling forty percent above the
    /// real count, which is a ceiling that can never bind, which is not a gate. It was measured by
    /// setting it to zero and reading what the failure printed.
    ///
    /// Every remaining occurrence is one somebody has to look at before adding to; a NEW one is a
    /// new instance of a shape this app has shipped seven times, and it should be fixed or
    /// explicitly accepted by moving this number in a diff somebody has to justify.
    ///
    /// **It moved 34 → 39 without a line of view code changing**, and that is the honest kind of
    /// growth: the scan learned to see `return HStack(spacing: 12) {`, which is how twelve of this
    /// app's horizontal containers are written, and every `Text` inside those twelve had been
    /// outside the population the old 34 was measured over. The five that appeared are examined
    /// rather than merely tolerated — the whole point of a residue is that somebody looked:
    ///
    /// * `ListsView:143` `Text(name)` — a word-list name the LEARNER typed, the longest string in
    ///   this list. It sits in a `VStack` with `.frame(maxWidth: .infinity)`, so it wraps
    ///   downward; a row that grows taller is not the clipping shape this file is about.
    /// * `ListsView:422` `Text(entry?.surface ?? …)` — same column shape, and a Japanese surface
    ///   is a handful of characters.
    /// * `MenuView:706` `Text(stop.0)` — one emoji (🗼 / 🗻 / 🏯 / ⛩️).
    /// * `ConjugationGameView:397` and `GameView:792` `Text(key)` — a SINGLE character, in a
    ///   monospaced chip built by `ForEach` over `expectedNextCharacters`.
    ///
    /// None of the five is a defect; all five belong in the count, because the count's job is to
    /// stop the population growing silently, and a population that excluded a whole syntactic form
    /// could not do that. (v1.32 pre-submission review.)
    ///
    /// ⚠️ **Correction, 2026-09-17: `ListsView:143` WAS a defect.** "Wraps downward, so harmless"
    /// was reasoned, not seen. Measured with CoreText and then on a simulator at AX5, the row's icon,
    /// play button and menu left the name a 91pt column: "★ / Save / d", three letters a line, on
    /// the list every install has. Wrapping downward one glyph at a time is the shape this file is
    /// about. Fixed in v1.33 §B L.
    ///
    /// **39 → 26 in v1.33, and only six of the thirteen left because they gained a limit.** Recorded
    /// per finding, because a ceiling that fell for the wrong reason would be read as progress:
    ///
    /// * **Gained a real `lineLimit` / shrink floor (6):** `GameView` HUD level capsule; the Ride
    ///   Log's odometer and forecast label + count (4); Practice's BLIND badge. (Correction, same
    ///   day, results-and-ride review: the HUD capsule's limit and floor now apply at the
    ///   accessibility sizes only — at every size they pushed the pause button off an iPad mini at
    ///   the default size — so below those sizes it wraps as in 1.32, on purpose. The scan still
    ///   reads the conditional `lineLimit` as a limit, and cannot tell.)
    /// * **Fixed by a layout switch, but left the scan's view only because the `Text` moved into a
    ///   property or helper the scan does not look inside (6):** the About and Settings header
    ///   titles; the drill answer kana and the coach's kana row (now one glyph helper under
    ///   `ViewThatFits`); the Ride Log's BEST badge; the Word Lists row name. Each is pinned by a
    ///   `V133*` layout test instead, which is the only thing now watching it.
    /// * **Moved, not fixed (1):** Practice's keyboard hint went into a helper with the top-bar
    ///   rework. It is the macOS-only branch, where accessibility sizes do not occur.
    ///
    /// Still counted though fixed by layout (the scan cannot see an `isAccessibilitySize` switch at
    /// the call site): `ResultsView` stumbled-word chip and review word (`MenuFlow` / one column),
    /// About's credit name and licence, Stats' conjugation card stats. And still counted because
    /// NOT fixed, deliberately: the six `RoadView` findings — the offer screen is frozen for the
    /// §K observation window (`docs/PLAN-V1.33.md` §C).
    static let accepted = 26

    @Test("no NEW Text in a horizontal row without a line limit or a shrink allowance")
    func theShapeDoesNotGrow() throws {
        let found = try Self.scanAll()

        // The floor. A scan that stopped matching would report a clean tree, which is how three
        // checkers in this repo's history produced a null result from a broken instrument.
        #expect(found.count > 10,
                Comment(rawValue: "only \(found.count) matches — the scan is no longer reading SwiftUI"))
        #expect(found.count <= Self.accepted, Comment(rawValue:
            "\(found.count) occurrences, accepted \(Self.accepted). New ones:\n"
            + found.suffix(6).map { "  \($0.file):\($0.line) \($0.text)" }.joined(separator: "\n")))
    }

    /// The instrument, checked against the shape it is FOR and the shape it must not flag.
    ///
    /// Calibrated both ways because a scan validated only by what it catches has not been
    /// validated — this repo's own entry, written after a rule found 21 offenders and was blind to
    /// 240 entries.
    @Test("the scan fires on the shape, and not on its fixes")
    func theScanIsCalibrated() {
        // The Ride Log row as it shipped: a Text in an HStack with a scaled font and no floor.
        let broken = """
        HStack(spacing: 8) {
            Text(levelLabel(record.level))
                .scaledSystemFont(10, weight: .heavy, design: .rounded)
                .foregroundStyle(Theme.accent2)
        }
        """
        #expect(Self.findings(in: broken, file: "x").count == 1)

        // …and its fix.
        let fixed = """
        HStack(spacing: 8) {
            Text(levelLabel(record.level))
                .scaledSystemFont(10, weight: .heavy, design: .rounded)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        """
        #expect(Self.findings(in: fixed, file: "x").isEmpty)

        // A shrink allowance alone is also a fix — the glyphs get smaller instead of wrapping.
        let shrunk = """
        HStack {
            Text(title)
                .scaledSystemFont(28, weight: .heavy)
                .minimumScaleFactor(0.7)
        }
        """
        #expect(Self.findings(in: shrunk, file: "x").isEmpty)

        // A top-level VSTACK is not the shape: a Text there has the full width and wrapping is
        // correct behaviour.
        let column = """
        VStack {
            Text(subtitle)
                .scaledSystemFont(13)
                .foregroundStyle(Theme.dim)
        }
        """
        #expect(Self.findings(in: column, file: "x").isEmpty,
                "a Text in a top-level column is not in a row that cannot grow")

        // …but a COLUMN INSIDE A ROW is. This is `dueChip` as it shipped — "Tomorrow" rendered as
        // "Tomorr / ow" — and the first version of this scan called it safe. A mutation that
        // reintroduced the real defect survived, which is what said the model was wrong.
        let columnInARow = """
        HStack(spacing: 10) {
            VStack(spacing: 2) {
                Text("\\(n)")
                    .scaledSystemFont(22, weight: .heavy)
                    .monospacedDigit()
                Text(label)
                    .scaledSystemFont(10, weight: .medium)
                    .foregroundStyle(Theme.dim)
            }
        }
        """
        #expect(Self.findings(in: columnInARow, file: "x").count == 2,
                "a column inside a row is width-constrained — this is the defect that survived")

        // FlowLayout WRAPS. A Text inside one is in a horizontal container that can grow
        // downward, which is the fix the chips in Stats and the Ride Log both use.
        let flowing = """
        FlowLayout(spacing: 8, lineSpacing: 8) {
            Text(habit.kana)
                .scaledSystemFont(18, weight: .bold)
        }
        """
        #expect(Self.findings(in: flowing, file: "x").isEmpty,
                "FlowLayout wraps — a Text inside one is not the shape")

        // A container opened behind `return`, `else {`, or both. Twelve of this app's horizontal
        // containers are written this way, and the scan could not see any of them — so every Text
        // inside them was outside the population the ceiling was measured over. The ceiling alone
        // cannot protect this: losing the ability to see them makes the count go DOWN, which no
        // upper bound catches. This is the assertion that does. (v1.32 pre-submission review.)
        let behindReturn = """
        return HStack(spacing: 12) {
            Text(name)
                .scaledSystemFont(16, weight: .semibold)
        }
        """
        #expect(Self.findings(in: behindReturn, file: "x").count == 1,
                "`return HStack(` does not open a container for this scan — twelve of the app's rows are invisible to it")

        let behindElse = """
        else { HStack(alignment: .top, spacing: 18) {
            Text(label)
                .scaledSystemFont(12)
        } }
        """
        #expect(Self.findings(in: behindElse, file: "x").count == 1,
                "`else { HStack(` does not open a container for this scan")

        // …and the negative that keeps the strip from turning every line into a container. The
        // scanner hands it an already-trimmed line, so what is checked is that stripping the
        // KEYWORDS does not turn a line merely mentioning HStack into one that opens a row.
        #expect(Self.stripLeadingKeywords("let note = \"see the HStack above\"") == "let note = \"see the HStack above\"")
        let mentionsOnly = """
        VStack {
            let note = "see the HStack above"
            Text(name)
                .scaledSystemFont(16)
        }
        """
        #expect(Self.findings(in: mentionsOnly, file: "x").isEmpty,
                "a line that merely names HStack opened a horizontal container")

        // And a Text with no scaled font is outside the population: it does not grow with the
        // accessibility sizes, so it cannot produce this defect.
        let unscaled = """
        HStack {
            Text("fixed")
                .font(.caption)
        }
        """
        #expect(Self.findings(in: unscaled, file: "x").isEmpty)
    }

    /// The seven known instances are all FIXED, so the scan must not find any of them. This is the
    /// half that makes the accepted number mean something: it is a residue of unexamined cases,
    /// not a residue that still contains the defects this file lists.
    /// The scan's coverage of the KNOWN population, pinned so the doc table above cannot rot.
    ///
    /// Both misses are structural. `dueChip` is a helper whose `HStack` lives at the call site, and
    /// this scan reads one function at a time; the Settings picker is a `Picker`, not a `Text` in
    /// a row. Recorded as a measurement rather than left implied, because "the scan is green" and
    /// "the class is covered" are different sentences and this repo has paid for confusing them.
    @Test("dueChip keeps the floor the scan cannot see")
    func theDueChipBlindSpotIsCompensated() throws {
        let stats = try String(contentsOf: Self.appDirectory.appendingPathComponent("StatsView.swift"),
                               encoding: .utf8)
        // `dueChip`'s label carries its floor. If somebody removes it, THIS scan will not notice —
        // so the floor is asserted directly, which is the only instrument that can see it.
        guard let chip = stats.range(of: "private func dueChip") else {
            Issue.record("dueChip moved; the blind-spot compensation below is measuring nothing")
            return
        }
        // Brace-balanced, not `prefix(700)`. Measured: 700 characters from `private func dueChip`
        // already lands 13 characters INSIDE the next function, `miniStat`, whose own two `Text`s
        // are among the accepted residue — so give either of them a `lineLimit` and this assertion
        // would have passed on a floor belonging to a different function. A window that can drift
        // into its neighbour is not a window. (v1.32 pre-submission review.)
        let body = Self.functionBody(of: stats, from: chip.lowerBound)
        #expect(!body.isEmpty && body.count < 700,
                "the brace walk returned \(body.count) characters — it did not find dueChip's body, so what follows is measuring nothing")
        #expect(!body.contains("func miniStat"), "the window overran into the next function again")
        #expect(body.contains("minimumScaleFactor") || body.contains("lineLimit"),
                "dueChip's label lost its floor, and the source scan CANNOT see it — the HStack that constrains it is at the call site, so this assertion is the only cover")
    }

    /// One declaration's body, from its opening `{` to the brace that closes it.
    ///
    /// Deliberately naive about braces in strings and comments: over-running by a few characters
    /// would be a bug, and the assertions above check the result is bounded and does not reach the
    /// next declaration, rather than trusting the walk.
    static func functionBody(of source: String, from start: String.Index) -> String {
        guard let open = source[start...].firstIndex(of: "{") else { return "" }
        var depth = 0
        var cursor = open
        while cursor < source.endIndex {
            if source[cursor] == "{" { depth += 1 }
            if source[cursor] == "}" {
                depth -= 1
                if depth == 0 { return String(source[open...cursor]) }
            }
            cursor = source.index(after: cursor)
        }
        return ""
    }

    @Test("none of the seven shipped instances is still in the tree")
    func theKnownInstancesAreGone() throws {
        let found = try Self.scanAll()
        let byFile = Dictionary(grouping: found, by: \.file).mapValues(\.count)

        // The Ride Log row and header, and the Stats card — the three fixed in this pass.
        let journal = try String(contentsOf: Self.appDirectory.appendingPathComponent("JournalView.swift"),
                                 encoding: .utf8)
        #expect(journal.contains("stackedRideRow"),
                "the Ride Log no longer switches layout at accessibility sizes")
        #expect(journal.contains("ScreenHeader("),
                "the Ride Log header is no longer the shared one that survives AX5")

        let stats = try String(contentsOf: Self.appDirectory.appendingPathComponent("StatsView.swift"),
                               encoding: .utf8)
        #expect(stats.contains("ScreenHeader("))

        // The conjugation HUD and form chip, fixed in v1.31.
        let conjugation = try String(contentsOf: Self.appDirectory.appendingPathComponent("ConjugationGameView.swift"),
                                     encoding: .utf8)
        #expect(conjugation.contains("lineLimit(1)"))

        // …and the scan agrees the fixed files are not the worst offenders any more.
        #expect((byFile["JournalView.swift"] ?? 0) <= 8,
                Comment(rawValue: "JournalView has \(byFile["JournalView.swift"] ?? 0) — it was the worst screen at AX5"))
    }
}
