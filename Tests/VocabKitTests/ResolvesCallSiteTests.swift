import Testing
import Foundation

/// The audit's cheapest rule, kept.
///
/// Six times now the app has shown a number computed by one predicate beside a run built with
/// another, and the difference each time was a missing `resolves:` — a card whose word has been
/// withdrawn can never be reviewed away, so it inflates whatever counts it forever. The parameter
/// defaults to `{ _ in true }` so the review modules stay usable without VocabKit, which is right
/// for their own tests and is exactly the trap in production: forgetting it is not an error, it
/// is a silently wrong number.
///
/// A one-off sweep finds today's instances. This runs on every build. It reads the shipped source
/// rather than exercising behaviour, which is unusual for a test and is the point — the property
/// is about what the code SAYS, and there is no runtime moment at which a missing argument is
/// distinguishable from a genuinely unfiltered store.
///
/// Scope is deliberately narrow: only the app layer, which has no test target of its own, and only
/// the methods whose answer feeds something a learner reads. GameCore is included because its
/// builders are the "run" half of every pair.
@Suite("Every due count declares what resolves")
struct ResolvesCallSiteTests {

    /// Methods that take `resolves:` and default it to true.
    static let guarded = ["dueCards", "dueCount", "dueByDay", "dueForecast",
                          "reviewedCount", "weakestCards"]

    /// Directories whose numbers reach a learner.
    static let scanned = ["Sources/NihongoRideApp", "Sources/GameCore",
                          "Sources/NotificationKit", "Sources/WidgetSharedKit"]

    static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)          // …/Tests/VocabKitTests/ResolvesCallSiteTests.swift
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// Every `.method(` call in `source` that does not pass `resolves:` before its closing paren.
    ///
    /// Balances parentheses from the call's own opening one, so a multi-line call, or one with a
    /// closure argument, is read whole rather than to the end of the line.
    /// How many guarded calls the last scan looked at. An empty offender list means nothing only
    /// if the scan actually read some calls — otherwise "no problems found" is a broken scanner
    /// reporting on a file list it failed to build.
    nonisolated(unsafe) static var inspected = 0

    static func offenders(in source: String, file: String) -> [String] {
        var found: [String] = []
        let characters = Array(source)
        for method in guarded {
            let needle = Array(".\(method)(")
            var i = 0
            while i + needle.count <= characters.count {
                guard Array(characters[i..<(i + needle.count)]) == needle else { i += 1; continue }
                var depth = 0
                var j = i + needle.count - 1
                var call = ""
                while j < characters.count {
                    let c = characters[j]
                    if c == "(" { depth += 1 }
                    if c == ")" { depth -= 1; if depth == 0 { break } }
                    call.append(c)
                    j += 1
                }
                inspected += 1
                if !call.contains("resolves:") {
                    let line = source[source.startIndex..<source.index(source.startIndex, offsetBy: i)]
                        .filter { $0 == "\n" }.count + 1
                    found.append("\(file):\(line) .\(method)( — no resolves:")
                }
                i = j
            }
        }
        return found
    }

    @Test("no learner-facing due count is built on an unfiltered store")
    func everyCallDeclaresResolves() throws {
        var offenders: [String] = []
        Self.inspected = 0
        for directory in Self.scanned {
            let url = Self.repoRoot.appendingPathComponent(directory)
            let files = try FileManager.default.contentsOfDirectory(atPath: url.path)
                .filter { $0.hasSuffix(".swift") }
            #expect(!files.isEmpty, "\(directory) has no Swift files — the scan is looking in the wrong place")
            for file in files {
                let source = try String(contentsOf: url.appendingPathComponent(file), encoding: .utf8)
                offenders += Self.offenders(in: source, file: "\(directory)/\(file)")
            }
        }
        // The app really does count these things in a dozen places; if this drops to nothing,
        // the scan broke rather than the code improving.
        #expect(Self.inspected >= 10, "scan inspected only \(Self.inspected) calls")
        #expect(offenders.isEmpty, "\(offenders.count) unfiltered call(s):\n\(offenders.joined(separator: "\n"))")
    }

    /// The rule is only worth having if it fires. These are the two shapes v1.23 actually fixed,
    /// as they were written before the fix, plus the shapes that must NOT trip it.
    @Test("the rule flags the calls that shipped wrong, and only those")
    func ruleIsCalibrated() {
        let before = """
        let due = conjugationReviewStore.dueCards(limit: Self.conjugationRunSize)
            .map { (entryID: $0.sourceID, formToken: $0.formToken) }
        let ids = reviewStore.weakestCards(limit: Self.weakWordsRunSize).map(\\.id)
        try? await center.setBadgeCount(store.dueCount() + conjugationStore.dueCount())
        """
        #expect(Self.offenders(in: before, file: "x").count == 4)

        let after = """
        let due = conjugationReviewStore.dueCards(
            limit: Self.conjugationRunSize,
            resolves: VocabStore.shared.resolvesID)
        let ids = reviewStore.weakestCards(limit: 15, resolves: VocabStore.shared.resolvesID)
        let n = store.dueCount(on: day, calendar: cal, resolves: { vocab.entry(id: $0) != nil })
        """
        #expect(Self.offenders(in: after, file: "x").isEmpty)

        // A nested closure argument must not end the call early and hide a missing resolves:.
        let nested = "let x = store.dueCards(limit: n, sortedBy: { a, b in a.id < b.id })"
        #expect(Self.offenders(in: nested, file: "x").count == 1)
    }
}
