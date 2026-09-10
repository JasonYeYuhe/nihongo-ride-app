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
    ///
    /// NotificationKit is here because it was the one place a `{ _ in true }` default survived
    /// v1.24 §C, while `STATE-2026-08-18.md` claimed all ten were gone — a doc asserting a
    /// property nothing checked, which is this project's own cheapest defect. All three scanners
    /// reported that file clean: two never opened the directory, and the third matched only
    /// call sites, where the argument IS passed.
    static let countingModules = ["Sources/ReviewKit", "Sources/ConjugationReviewKit",
                                  "Sources/NotificationKit"]

    /// Name prefixes that make a member a count of outstanding work. Anything matching one of
    /// these has to take `resolves:`, because every one of them is a number a learner reads or
    /// a pool a run is built from.
    static let countingPrefixes = ["due", "reviewed", "leech", "weakest"]

    /// The subset that counts work still to DO, as opposed to work already done. In
    /// `ConjugationReviewKit` these must additionally declare and call `rideable:` (v1.32 §C1):
    /// a card whose `sourceID#form` the drill can no longer build a prompt for is never graded
    /// by any run, so it inflates them forever — the same argument `resolves:` was added on,
    /// one predicate further in.
    ///
    /// **`reviewed` is deliberately absent and that is a decision, not an oversight.**
    /// "Forms practised" is a historical fact; the learner did practise a card that has since
    /// become unbuildable. Filtering it there would make a true number false, which is the
    /// direction v1.24 §C's `sourceID`/`id` swap actually shipped ("Forms practiced 0"). Work
    /// remaining filters; history does not. If that line ever moves, it moves here.
    static let outstandingWorkPrefixes = ["due", "leech", "weakest"]

    /// `rideable:` is meaningful only where a card has a FORM to build. The vocabulary side has
    /// no equivalent, so the rule is scoped to the module that does rather than asserted
    /// everywhere and then excepted.
    static let rideableModule = "Sources/ConjugationReviewKit"

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
        //
        // A STACK, not a running variable. The first version kept one name and never restored
        // it when a nested type closed: `ConjugationReviewStore.Forecast` is declared near the
        // end of its file, so from that line onward the enclosing type read "Forecast", the
        // Store test failed, and everything after it was silently exempt — including the end of
        // the file, which is where a new method actually gets appended. A rule whose coverage
        // depends on where in the file you type is not a rule. (v1.24, pre-submission review.)
        var stack: [(name: String, depth: Int)] = []
        var depth = 0
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            var declared: String?
            for keyword in ["public struct ", "public final class ", "public class ", "extension ",
                            "struct ", "final class ", "class "]
            where trimmed.hasPrefix(keyword) && declared == nil {
                declared = String(trimmed.dropFirst(keyword.count)
                    .prefix { $0.isLetter || $0.isNumber || $0 == "_" })
            }
            let depthBefore = depth
            for character in line {
                if character == "{" { depth += 1 }
                if character == "}" { depth -= 1 }
            }
            if let declared { stack.append((declared, depthBefore)) }
            while let top = stack.last, depth <= top.depth, declared == nil { stack.removeLast() }
            guard stack.last?.name.hasSuffix("Store") == true else { continue }
            guard trimmed.hasPrefix("public func ") || trimmed.hasPrefix("public var ") else { continue }
            let isFunc = trimmed.hasPrefix("public func ")
            let afterKeyword = trimmed.dropFirst(isFunc ? "public func ".count : "public var ".count)
            let name = String(afterKeyword.prefix { $0.isLetter || $0.isNumber || $0 == "_" })
            let lowered = name.lowercased()
            guard countingPrefixes.contains(where: { lowered.hasPrefix($0) }) else { continue }
            // Read the declaration AND its body: brace-balanced from the first `{`.
            //
            // Reading only to the first brace is what let the shipped `ReviewStore.leeches`
            // through — it declared `resolves:` and never called it, so the signature check
            // passed while the filter did nothing. A parameter that is accepted and ignored is
            // worse than a missing one: the call site reads as guarded, the doc comment
            // promises the filter, and every test passes `{ _ in true }`, under which an
            // ignored filter and an applied one are indistinguishable. Found by the v1.24
            // pre-submission review, in code this very rule had just declared clean.
            var declaration = ""
            var depth = 0
            var opened = false
            for continuation in lines[index...] {
                declaration += continuation + "\n"
                for character in continuation {
                    if character == "{" { depth += 1; opened = true }
                    if character == "}" { depth -= 1 }
                }
                if opened && depth <= 0 { break }
            }
            let signature = declaration.components(separatedBy: "{").first ?? declaration
            if !signature.contains("resolves:") {
                found.append("\(file):\(index + 1) \(name) — counts work without a resolves:")
            } else if !declaration.contains("resolves(") {
                found.append("\(file):\(index + 1) \(name) — takes resolves: and never calls it")
            }
            // The same two checks for the second predicate, in the one module where a card has
            // a form. Declared AND called, for the reason the `resolves:` half learned the hard
            // way: `ReviewStore.leeches` shipped declaring a filter it never applied, and a
            // signature check called it clean.
            guard file.hasPrefix(Self.rideableModule),
                  Self.outstandingWorkPrefixes.contains(where: { lowered.hasPrefix($0) })
            else { continue }
            if !signature.contains("rideable:") {
                found.append("\(file):\(index + 1) \(name) — counts OUTSTANDING work without a rideable:")
            } else if !declaration.contains("rideable(") {
                found.append("\(file):\(index + 1) \(name) — takes rideable: and never calls it")
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
            cards.values.filter { $0.dueDate < cutoff && resolves($0.sourceID) }
        }
        }
        """
        #expect(Self.undeclaredGuards(in: after, file: "x").isEmpty)

        // The shape that got through the first version of this rule: declared and ignored.
        let declaredButIgnored = """
        public struct ReviewStore {
        public func leeches(resolves: (String) -> Bool) -> [SRSCard] {
            cards.values.filter(\\.isLeech).sorted { $0.lapses > $1.lapses }
        }
        }
        """
        #expect(Self.undeclaredGuards(in: declaredButIgnored, file: "x").count == 1,
                "a resolves: that is accepted and never called must be flagged")

        // …and the fix must clear it, including the nested closure braces in the sort.
        let declaredAndUsed = """
        public struct ReviewStore {
        public func leeches(resolves: (String) -> Bool) -> [SRSCard] {
            cards.values.filter { $0.isLeech && resolves($0.id) }
                .sorted { $0.lapses > $1.lapses }
        }
        }
        """
        #expect(Self.undeclaredGuards(in: declaredAndUsed, file: "x").isEmpty)

        // A counting method appended AFTER a nested type must still be seen. This is the exact
        // shape that made the rule placement-dependent.
        let afterNestedType = """
        public struct ConjugationReviewStore {
            public func dueCount(resolves: (String) -> Bool) -> Int {
                cards.count { resolves($0.sourceID) }
            }

            public struct Forecast: Sendable {
                public let today: Int
            }

            public func dueSoonCount(within days: Int) -> Int { cards.count }
        }
        """
        #expect(Self.undeclaredGuards(in: afterNestedType, file: "x").count == 1,
                "a method after a nested type is still a member of the Store")

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

    /// A predicate parameter with a default value, wherever it is and whatever it is called.
    ///
    /// **This replaced a name-based rule, and the replacement is both wider and narrower.**
    /// The old version matched any line containing `resolves:` (case-insensitively) plus
    /// `-> Bool` or `-> Int`, and flagged it if the line contained an `=` anywhere:
    ///
    /// * **It was too narrow.** v1.32 added `rideable:` — a second injected predicate on the
    ///   same counting APIs, guarding the same class of defect — and the name rule could not
    ///   see it at all. Giving it `= { _ in true }` would have restored the whole v1.23/v1.24
    ///   trap with every gate green. The next predicate would have inherited the same hole; a
    ///   gate keyed on a NAME only ever guards the names somebody remembered.
    /// * **It was too wide.** `=` anywhere on the line included some OTHER parameter's default,
    ///   so `func dueCount(on date: Date = Date(), resolves: (String) -> Bool) -> Int {` was an
    ///   offender the moment anyone wrote the signature on one line. Every declaration in the
    ///   tree happens to break the line first, which is the only reason it never fired.
    ///
    /// This version asks the structural question instead: does a `-> Bool` closure type have an
    /// `=` immediately after it. That is what a defaulted predicate looks like and nothing else
    /// does.
    static func defaultedPredicates(in source: String, file: String) -> [String] {
        var found: [String] = []
        for (index, line) in source.components(separatedBy: "\n").enumerated() {
            var cursor = line.startIndex
            while let hit = line.range(of: "-> Bool", range: cursor..<line.endIndex) {
                cursor = hit.upperBound
                var after = hit.upperBound
                while after < line.endIndex, line[after] == "?" || line[after] == " " {
                    after = line.index(after: after)
                }
                if after < line.endIndex, line[after] == "=" {
                    found.append("\(file):\(index + 1) — a Bool-returning closure parameter has a default")
                }
            }
        }
        return found
    }

    /// The defaults must not come back. Re-adding one restores the whole trap in a single
    /// character-for-character edit, and it would look like a kindness to the review modules'
    /// own tests — which is exactly the argument v1.23 accepted and v1.24 reversed.
    @Test("no injected predicate has a default value, whatever it is called")
    func noDefaultedPredicates() throws {
        var offenders: [String] = []
        var inspected = 0
        for directory in Self.countingModules {
            let url = Self.repoRoot.appendingPathComponent(directory)
            for file in try FileManager.default.contentsOfDirectory(atPath: url.path)
                    .filter({ $0.hasSuffix(".swift") }) {
                let source = try String(contentsOf: url.appendingPathComponent(file), encoding: .utf8)
                for line in source.components(separatedBy: "\n") where line.contains("-> Bool") {
                    inspected += 1
                }
                offenders += Self.defaultedPredicates(in: source, file: "\(directory)/\(file)")
            }
        }
        // The count is of Bool-returning closure lines, not of `resolves:` ones, so the old
        // threshold does not transfer. Measured at the commit that introduced this rule: 24.
        #expect(inspected >= 16, "only \(inspected) predicate parameters seen — the scan is wrong")
        #expect(offenders.isEmpty, "\(offenders)")
    }

    /// Calibrated both ways, on the two names that actually exist and one that does not, because
    /// the whole point of the replacement is that it does not depend on the name.
    @Test("the default rule fires on any predicate name, and not on another parameter's default")
    func defaultRuleIsCalibrated() {
        // Positive: the shape v1.24 §C removed, under three different names.
        for name in ["resolves", "vocabResolves", "rideable"] {
            let offending = "    public func dueCount(\(name): (String) -> Bool = { _ in true }) -> Int {"
            #expect(Self.defaultedPredicates(in: offending, file: "x").count == 1,
                    "missed a default on `\(name):`")
        }

        // Negative: the false positive the name-based rule had. Another parameter's default on
        // the same line is not a defaulted predicate, and flagging it would push authors to
        // break lines to appease the gate rather than to read well.
        let innocent = "    public func dueCount(on date: Date = Date(), resolves: (String) -> Bool) -> Int {"
        #expect(Self.defaultedPredicates(in: innocent, file: "x").isEmpty,
                "another parameter's default is not a defaulted predicate")

        // Negative: a function that RETURNS Bool is not a parameter.
        #expect(Self.defaultedPredicates(in: "    func isDue(on date: Date = Date()) -> Bool {",
                                         file: "x").isEmpty)

        // Negative: an optional predicate with no default.
        #expect(Self.defaultedPredicates(in: "    resolves: ((String) -> Bool)?,",
                                         file: "x").isEmpty)
    }

    /// The `rideable:` half of the declaration rule, calibrated on the exact shapes that would
    /// reintroduce v1.32 §C1 — written as the code looked BEFORE the fix.
    @Test("the declaration rule flags an outstanding-work count with no rideable:, and spares history")
    func rideableRuleIsCalibrated() {
        let inTheRightModule = "\(Self.rideableModule)/ConjugationReviewStore.swift"

        // Before v1.32: due counts filtered on the verb only.
        let before = """
        public struct ConjugationReviewStore {
        public func dueCount(resolves: (String) -> Bool) -> Int {
            cards.values.filter { resolves($0.sourceID) }.count
        }

        public func leeches(resolves: (String) -> Bool) -> [ConjugationSRSCard] {
            cards.values.filter { $0.isLeech && resolves($0.sourceID) }
        }
        """
        #expect(Self.undeclaredGuards(in: before, file: inTheRightModule).count == 2)

        // Declared and never applied — the `ReviewStore.leeches` shape, which a signature-only
        // check called clean while it shipped.
        let declaredNotCalled = """
        public struct ConjugationReviewStore {
        public func dueCount(resolves: (String) -> Bool,
                             rideable: (ConjugationSRSCard) -> Bool) -> Int {
            cards.values.filter { resolves($0.sourceID) }.count
        }
        """
        #expect(Self.undeclaredGuards(in: declaredNotCalled, file: inTheRightModule).count == 1)

        // Fixed.
        let after = """
        public struct ConjugationReviewStore {
        public func dueCount(resolves: (String) -> Bool,
                             rideable: (ConjugationSRSCard) -> Bool) -> Int {
            cards.values.filter { resolves($0.sourceID) && rideable($0) }.count
        }
        """
        #expect(Self.undeclaredGuards(in: after, file: inTheRightModule).isEmpty)

        // History is spared, in the same module — the decision recorded on
        // `outstandingWorkPrefixes`, asserted rather than left to that comment.
        let history = """
        public struct ConjugationReviewStore {
        public func reviewedCount(resolves: (String) -> Bool) -> Int {
            cards.values.filter { $0.totalReviews > 0 && resolves($0.sourceID) }.count
        }
        """
        #expect(Self.undeclaredGuards(in: history, file: inTheRightModule).isEmpty,
                "forms PRACTISED is history, and history is not outstanding work")

        // And the rule does not leak into the vocabulary module, which has no forms.
        #expect(Self.undeclaredGuards(in: before, file: "Sources/ReviewKit/ReviewStore.swift").isEmpty,
                "ReviewKit has no form to build — rideable: is meaningless there")
    }
}
