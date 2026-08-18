import Testing
import Foundation

/// The audit's cheapest rule, kept.
///
/// Six times now the app has shown a number computed by one predicate beside a run built with
/// another, and the difference each time was a missing `resolves:` — a card whose word has been
/// withdrawn can never be reviewed away, so it inflates whatever counts it forever.
///
/// **v1.24 §C removed the `{ _ in true }` defaults**, so forgetting the argument is now a
/// compile error rather than a silently wrong number. That makes this file's original job
/// mostly the compiler's, and leaves it three that the signature cannot do:
///
/// 1. A *new* counting method that never had the parameter. The compiler cannot miss what was
///    never declared.
/// 2. Keeping the defaults from coming back, since re-adding one restores the trap wholesale.
/// 3. The blind spot that actually bit. This file scanned CALL SITES, and matched `.name(` —
///    with a parenthesis. `ConjugationReviewStore.reviewedCount` and `.leeches()` were an
///    unfiltered property and an unfiltered function, both read by the Stats screen, and
///    neither was visible to a call-site scan. The declaration-side check below is what would
///    have found them, and it is calibrated on exactly those two.
///
/// It reads the shipped source rather than exercising behaviour, which is unusual for a test and
/// is the point — the property is about what the code SAYS, and there is no runtime moment at
/// which a missing argument is distinguishable from a genuinely unfiltered store.
///
/// Scope is deliberately narrow: only the app layer, which has no test target of its own, and only
/// the methods whose answer feeds something a learner reads. GameCore is included because its
/// builders are the "run" half of every pair.
@Suite("Every due count declares what resolves")
struct ResolvesCallSiteTests {

    /// Methods that answer "how much work is there", and so must say what counts as work.
    static let guarded = ["dueCards", "dueCount", "dueByDay", "dueForecast",
                          "reviewedCount", "weakestCards", "leeches"]

    /// The modules those methods are DECLARED in.
    static let countingModules = ["Sources/ReviewKit", "Sources/ConjugationReviewKit"]

    /// Name prefixes that make a member a count of outstanding work. Anything matching one of
    /// these has to take `resolves:`, because every one of them is a number a learner reads or
    /// a pool a run is built from.
    static let countingPrefixes = ["due", "reviewed", "leech", "weakest"]

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

    // MARK: The declaration side — what a call-site scan cannot see

    /// Public members of the review modules that count outstanding work without saying what
    /// counts. Returns "file:line name" for each.
    ///
    /// Matches `public func name(` and `public var name:` alike, which is the whole point: the
    /// two defects v1.24 §C found were an unfiltered `public var reviewedCount` and an
    /// unfiltered `public func leeches()`, both read by the Stats screen, and a scan for
    /// `.name(` at the call sites could see neither.
    static func undeclaredGuards(in source: String, file: String) -> [String] {
        var found: [String] = []
        let lines = source.components(separatedBy: "\n")
        // Only members of a STORE are counts over a collection. `SRSCard.dueDate` is one card's
        // own date, and asking it what resolves is meaningless — the first version of this rule
        // flagged it, which is what a calibration pass is for.
        var enclosingType = ""
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            for keyword in ["public struct ", "public final class ", "public class ", "extension "]
            where trimmed.hasPrefix(keyword) {
                enclosingType = String(trimmed.dropFirst(keyword.count)
                    .prefix { $0.isLetter || $0.isNumber || $0 == "_" })
            }
            guard enclosingType.hasSuffix("Store") else { continue }
            guard trimmed.hasPrefix("public func ") || trimmed.hasPrefix("public var ") else { continue }
            let isFunc = trimmed.hasPrefix("public func ")
            let afterKeyword = trimmed.dropFirst(isFunc ? "public func ".count : "public var ".count)
            let name = String(afterKeyword.prefix { $0.isLetter || $0.isNumber || $0 == "_" })
            let lowered = name.lowercased()
            guard countingPrefixes.contains(where: { lowered.hasPrefix($0) }) else { continue }
            // The declaration may wrap over several lines; read to the body brace.
            var declaration = ""
            for continuation in lines[index...] {
                declaration += continuation
                if continuation.contains("{") { break }
            }
            if !declaration.contains("resolves:") {
                found.append("\(file):\(index + 1) \(name) — counts work without a resolves:")
            }
        }
        return found
    }

    @Test("every counting API in the review modules requires a resolves: argument")
    func everyCountingAPIDeclaresResolves() throws {
        var offenders: [String] = []
        var inspectedFiles = 0
        for directory in Self.countingModules {
            let url = Self.repoRoot.appendingPathComponent(directory)
            let files = try FileManager.default.contentsOfDirectory(atPath: url.path)
                .filter { $0.hasSuffix(".swift") }
            #expect(!files.isEmpty, "\(directory) has no Swift files — the scan is misdirected")
            for file in files {
                inspectedFiles += 1
                let source = try String(contentsOf: url.appendingPathComponent(file), encoding: .utf8)
                offenders += Self.undeclaredGuards(in: source, file: "\(directory)/\(file)")
            }
        }
        #expect(inspectedFiles >= 4, "only \(inspectedFiles) files read")
        #expect(offenders.isEmpty, "\(offenders.count) counting API(s) with no resolves:: \(offenders)")
    }

    /// Calibrated on the exact two v1.24 §C found, written as they shipped.
    @Test("the declaration rule flags the two that shipped unfiltered, and not their fixes")
    func declarationRuleIsCalibrated() {
        let before = """
        public struct ConjugationReviewStore {
        public var reviewedCount: Int {
            cards.values.lazy.filter { $0.totalReviews > 0 }.count
        }

        public func leeches() -> [ConjugationSRSCard] {
            cards.values.filter(\\.isLeech).sorted { $0.lapses > $1.lapses }
        }
        """
        #expect(Self.undeclaredGuards(in: before, file: "x").count == 2)

        let after = """
        public struct ConjugationReviewStore {
        public func reviewedCount(resolves: (String) -> Bool) -> Int {
            cards.values.filter { $0.totalReviews > 0 && resolves($0.sourceID) }.count
        }

        public func leeches(resolves: (String) -> Bool) -> [ConjugationSRSCard] {
            cards.values.filter { $0.isLeech && resolves($0.sourceID) }
        }

        public func dueCards(on date: Date = Date(), limit: Int = 100,
                             calendar: Calendar = .current,
                             resolves: (String) -> Bool) -> [ConjugationSRSCard] {
        """
        #expect(Self.undeclaredGuards(in: after, file: "x").isEmpty)

        // Members that are not counts of outstanding work must not be dragged in.
        let unrelated = """
        public struct ReviewStore {
        public var count: Int { cards.count }
        public func save(to url: URL) throws {
        }
        public struct SRSCard {
        public var dueDate: Date
        }
        """
        #expect(Self.undeclaredGuards(in: unrelated, file: "x").isEmpty,
                "a single card's own dueDate is not a count over a store")
    }

    /// The defaults must not come back. Re-adding one restores the whole trap in a single
    /// character-for-character edit, and it would look like a kindness to the review modules'
    /// own tests — which is exactly the argument v1.23 accepted and v1.24 reversed.
    @Test("no resolves: parameter has a default value")
    func noDefaultedResolves() throws {
        var offenders: [String] = []
        var inspected = 0
        for directory in Self.countingModules {
            let url = Self.repoRoot.appendingPathComponent(directory)
            for file in try FileManager.default.contentsOfDirectory(atPath: url.path)
                    .filter({ $0.hasSuffix(".swift") }) {
                let source = try String(contentsOf: url.appendingPathComponent(file), encoding: .utf8)
                for (index, line) in source.components(separatedBy: "\n").enumerated()
                where line.contains("resolves:") && line.contains("-> Bool") {
                    inspected += 1
                    if line.contains("=") {
                        offenders.append("\(directory)/\(file):\(index + 1) — resolves: has a default")
                    }
                }
            }
        }
        #expect(inspected >= 8, "only \(inspected) resolves: parameters seen — the scan is wrong")
        #expect(offenders.isEmpty, "\(offenders)")
    }
}
