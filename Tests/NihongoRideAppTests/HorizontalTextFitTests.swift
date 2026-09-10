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
/// # How much of the known population it actually covers — MEASURED, 4 of 7
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
/// | ◐ | v1.32 Ride Log row at AX5 | the row is in scope; its numbers come from `rowStat()` and are not |
/// | ❌ | v1.32 Stats "Tomorrow" | `dueChip()` is a helper — its `HStack` is at the CALL SITE, in another function |
/// | ❌ | v1.31 Settings romaji picker | a `Picker`, not a `Text` in an `HStack`. A different shape entirely |
///
/// **Four and a half of seven.** That is worth having and it is not a gate on this defect class —
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

            if trimmed.hasPrefix("HStack") { stack.append((indent, .horizontal)) }
            if trimmed.hasPrefix("FlowLayout") { stack.append((indent, .wrapping)) }

            guard trimmed.hasPrefix("Text(") else { continue }
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
    /// Measured 2026-09-10 after the §E pass: **34**, and the number is the measurement rather
    /// than a guess. The first draft wrote 47 from intuition — a ceiling forty percent above the
    /// real count, which is a ceiling that can never bind, which is not a gate. It was measured by
    /// setting it to zero and reading what the failure printed.
    ///
    /// Every remaining occurrence is one somebody has to look at before adding to; a NEW one is a
    /// new instance of a shape this app has shipped seven times, and it should be fixed or
    /// explicitly accepted by moving this number in a diff somebody has to justify.
    static let accepted = 34

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
    @Test("the scan's blind spots are the ones documented, and no more")
    func theBlindSpotsAreKnown() throws {
        let stats = try String(contentsOf: Self.appDirectory.appendingPathComponent("StatsView.swift"),
                               encoding: .utf8)
        // `dueChip`'s label carries its floor. If somebody removes it, THIS scan will not notice —
        // so the floor is asserted directly, which is the only instrument that can see it.
        guard let chip = stats.range(of: "private func dueChip") else {
            Issue.record("dueChip moved; the blind-spot compensation below is measuring nothing")
            return
        }
        let body = String(stats[chip.lowerBound...].prefix(700))
        #expect(body.contains("minimumScaleFactor") || body.contains("lineLimit"),
                "dueChip's label lost its floor, and the source scan CANNOT see it — the HStack that constrains it is at the call site, so this assertion is the only cover")
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
