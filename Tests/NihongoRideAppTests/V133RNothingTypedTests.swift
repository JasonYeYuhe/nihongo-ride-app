import Testing
import Foundation
import VocabKit
import GameCore
@testable import NihongoRideApp

/// A run that typed nothing is not shown as a finished one (v1.33 §B R).
///
/// The simulator pass of 2026-09-17 ended a ride and a drill before the first key (defect 5): the
/// ride said "You've arrived!" with a 🏁, a grade and 100% accuracy, and the drill said "Drill
/// complete! STEADY" for 0/12 — while `logRun` had already refused to journal that ride. The rule
/// existed once, inline in `logRun`, and the screens never asked it. It is now `RunTyping`, and
/// these tests hold three things: the rule's own truth table (mutated once to see it fail), that the
/// log and the screen give the same answer for the same run, and that `logRun` still asks the one
/// rule rather than a copy of it.
@MainActor
@Suite("v1.33 R: a run that typed nothing is not shown as a finished one")
struct V133RNothingTypedTests {

    // MARK: - The rule

    /// Expected values are written out, not derived. Mutating `||` to `&&` in `RunTyping` turns the
    /// two middle rows red — a run with a completed word, or with a correct key, becomes "nothing".
    @Test("nothing typed means no completed unit AND no correct key")
    func theRuleItself() {
        #expect(RunTyping.typedNothing(unitsCompleted: 0, correctKeystrokes: 0) == true)
        #expect(RunTyping.typedNothing(unitsCompleted: 1, correctKeystrokes: 0) == false,
                "a completed unit counted as nothing")
        #expect(RunTyping.typedNothing(unitsCompleted: 0, correctKeystrokes: 1) == false,
                "one correct key into the first word is typing — logRun has always journalled it")
        #expect(RunTyping.typedNothing(unitsCompleted: 6, correctKeystrokes: 30) == false)
    }

    // MARK: - The ride: the summary answers from the session's own counters

    static func vocab() -> VocabStore {
        VocabStore(entries: [AppModelTests.entry("a", "水", "みず"),
                             AppModelTests.entry("b", "火", "ひ"),
                             AppModelTests.entry("c", "山", "やま")])
    }

    static func session() -> GameSession {
        GameSession(words: vocab().entries, config: GameSession.Config())
    }

    @Test("the summary of an untouched, a skipped and a refused-only ride says nothing was typed")
    func summaryFromSession() throws {
        let untouched = Self.session()
        #expect(GameSummary(from: untouched).typedNothing)
        // The 0/0 that printed "100%": asserted so the reason for "—" stays visible here.
        #expect(GameSummary(from: untouched).accuracy == 1)

        let skipped = Self.session()
        skipped.skip()
        #expect(GameSummary(from: skipped).typedNothing, "a skip is not typing")
        #expect(!GameSummary(from: skipped).reviewWords.isEmpty,
                "the skip's lapse must still reach the summary — only the headline changes")

        let refused = Self.session()
        _ = refused.input("q")   // no romaji starts with q
        #expect(refused.totalKeystrokes == 1 && refused.correctKeystrokes == 0,
                "the arrangement did not refuse a key — this row measures nothing")
        #expect(GameSummary(from: refused).typedNothing)

        let started = Self.session()
        let first = try #require(started.currentRomaji?.first)
        _ = started.input(first)
        #expect(started.correctKeystrokes == 1, "the arrangement did not accept a key")
        #expect(!GameSummary(from: started).typedNothing)
    }

    // MARK: - The ride: the log and the screen agree

    enum Arrangement: String, CaseIterable {
        case untouched, skippedOnly, refusedOnly, oneCorrectKey, oneWord
    }

    /// Whether a RideRecord should exist for the arrangement. Written from what `logRun` has done
    /// since before v1.33, not from `RunTyping`, so this cannot grade itself.
    static func isLogged(_ a: Arrangement) -> Bool {
        switch a {
        case .untouched, .skippedOnly, .refusedOnly: return false
        case .oneCorrectKey, .oneWord: return true
        }
    }

    static func act(_ a: Arrangement, on session: GameSession) {
        switch a {
        case .untouched: break
        case .skippedOnly: session.skip()
        case .refusedOnly: _ = session.input("q"); _ = session.input("q")
        case .oneCorrectKey:
            if let c = session.currentRomaji?.first { _ = session.input(c) }
        case .oneWord:
            for c in session.currentRomaji ?? "" { _ = session.input(c) }
        }
    }

    /// The screen reads `lastSummary.typedNothing`; the log's answer is whether the journal grew.
    /// For every arrangement they must be opposite — and each must match the pre-v1.33 log.
    ///
    /// The review prompt is recorded too, because the brief for this change is that its rule does
    /// not move: for a refused run `pendingReviewMoment` is built with `wasLogged: false`, and
    /// `ReviewPromptLedger` answers that with `.notALoggedRide` — never an ask. That was so before
    /// v1.33 (the moment is built from `logRun`'s return value, which this change does not alter).
    @Test("for every arrangement, the journal grows exactly when the screen says something was typed",
          arguments: Arrangement.allCases)
    func logAndScreenAgree(_ arrangement: Arrangement) throws {
        let model = AppModelTests.makeModel(vocab: Self.vocab())
        let before = model.journal.count
        model.startGame()
        let session = try #require(model.session, "the ride did not start — the arrangement measures nothing")
        Self.act(arrangement, on: session)
        model.finishGame()

        let logged = model.journal.count == before + 1
        let summary = try #require(model.lastSummary)
        #expect(model.screen == .results)
        #expect(logged == Self.isLogged(arrangement),
                "\(arrangement): logRun's decision moved (logged: \(logged))")
        #expect(summary.typedNothing == !logged,
                "\(arrangement): the Ride Log says \(logged ? "a ride" : "no ride") and the screen says typedNothing = \(summary.typedNothing)")
        #expect(model.pendingReviewMoment?.wasLogged == logged,
                "\(arrangement): the review prompt's input changed")
    }

    // MARK: - The drill

    /// 0 untouched, 1 skipped, 2 one prompt answered, 3 one correct key into the first prompt and
    /// nothing answered. The last is the ride's `.oneCorrectKey`, and it is the only row that reads
    /// the summary's `correctKeystrokes`: without it, `ConjugationSummary` could snapshot that
    /// counter as 0 — the review did exactly that — and every other row would still pass.
    @Test("a drill with nothing answered says so; one answered prompt or one correct key does not",
          arguments: [0, 1, 2, 3])
    func drill(_ arrangement: Int) throws {
        let model = AppModelTests.makeModel(vocab: VocabStore(entries: AppModelTests.verbEntries(3)))
        model.startConjugation()
        let session = try #require(model.conjugationSession, "the drill did not start — nothing to measure")
        switch arrangement {
        case 1: session.skip()
        case 2: for c in session.currentRomaji ?? "" { _ = session.input(c) }
        case 3:
            let first = try #require(session.currentRomaji?.first)
            _ = session.input(first)
            #expect(session.correctKeystrokes == 1 && (session.currentRomaji?.count ?? 0) > 1,
                    "the arrangement did not press exactly one correct key short of an answer")
        default: break
        }
        let answered = session.promptsCompleted
        model.finishConjugation()
        let summary = try #require(model.lastConjugationSummary)
        switch arrangement {
        case 2:
            #expect(answered == 1, "the arrangement did not answer a prompt")
            #expect(!summary.typedNothing)
        case 3:
            #expect(answered == 0, "one key answered a prompt — this row no longer isolates the key")
            #expect(!summary.typedNothing, "a correct key into the first prompt is typing, as it is in the ride")
        default:
            #expect(answered == 0)
            #expect(summary.typedNothing, "arrangement \(arrangement): nothing was answered")
            #expect(summary.accuracy == 1, "the 0/0 the tile no longer prints as 100%")
        }
    }

    // MARK: - One rule, asked by the log and by both screens

    /// Everything `logRun` must satisfy, as a list of what is wrong. Empty means it asks the one
    /// rule in its guard and restates none of it.
    static func logRunProblems(_ file: CallSiteScanner.File) -> [String] {
        guard let logRun = file.functions(named: "logRun").first, let body = logRun.body else {
            return ["\(file.path): no logRun body found"]
        }
        var problems: [String] = []
        let asks = file.calls(named: "typedNothing").filter {
            body.contains($0.nameOffset)
                && CallSiteScanner.receiverComponents($0.receiver) == ["RunTyping"]
                && CallSiteScanner.isInConditionHead(file.code, $0.nameOffset)
        }
        if asks.isEmpty { problems.append("logRun's guard does not ask RunTyping.typedNothing") }
        let restated = CallSiteScanner.captures(#"\b(wordsCompleted|correctKeystrokes)\s*(?:>|<|==|!=)"#,
                                                in: file.text(body))
        if !restated.isEmpty { problems.append("logRun compares \(restated.sorted()) itself") }
        return problems
    }

    @Test("logRun's guard is the shared rule, and both results screens read it")
    func oneRule() throws {
        // Controls first, through the same function: the pre-v1.33 guard, and the fix written only
        // in a comment, must both be reported.
        let old = CallSiteScanner.File(path: "Old.swift", source: """
            final class M {
                private func logRun(_ session: GameSession) -> RideRecord? {
                    guard session.wordsCompleted > 0 || session.correctKeystrokes > 0 else { return nil }
                    return nil
                }
            }
            """)
        #expect(Self.logRunProblems(old).count == 2, "the check passes the pre-v1.33 guard: \(Self.logRunProblems(old))")
        let commented = CallSiteScanner.File(path: "Commented.swift", source: """
            final class M {
                private func logRun(_ session: GameSession) -> RideRecord? {
                    // guard !RunTyping.typedNothing(unitsCompleted: 1, correctKeystrokes: 1) else { }
                    guard session.wordsCompleted>0 || true else { return nil }
                    return nil
                }
            }
            """)
        #expect(Self.logRunProblems(commented).count == 2,
                "a comment counted as code, or a spacing variant hid the restatement: \(Self.logRunProblems(commented))")

        let files = try CallSiteScanner.shippedSources.get()
        let model = try #require(files.first { $0.path == "Sources/NihongoRideApp/AppModel.swift" })
        #expect(Self.logRunProblems(model).isEmpty, "\(Self.logRunProblems(model))")

        // Both summaries answer through the same function, not a copy.
        for type in ["GameSummary", "ConjugationSummary"] {
            let bodies = model.typeBodies(named: type)
            #expect(!bodies.isEmpty, "\(type) not found — the scan is misdirected")
            let asks = model.calls(named: "typedNothing").filter { call in
                bodies.contains { $0.contains(call.nameOffset) }
                    && CallSiteScanner.receiverComponents(call.receiver) == ["RunTyping"]
            }
            #expect(asks.count == 1, "\(type).typedNothing does not ask RunTyping exactly once (\(asks.count))")
        }

        // …and both screens read it, at every place it decides something. Pinned per site below.
        for (view, sites) in Self.screenSites {
            let file = try #require(files.first { $0.path == "Sources/NihongoRideApp/\(view).swift" })
            #expect(Self.screenProblems(file, sites: sites).isEmpty, "\(Self.screenProblems(file, sites: sites))")
        }
    }

    // MARK: - Where each results screen asks

    /// The three decisions a results screen makes from `typedNothing`. A count of mentions held none
    /// of them: the review turned the ride's headline into `if false {` and `>= 2` still counted the
    /// accuracy tile and the Share guard. So each is found by its own shape.
    enum Site: String, CaseIterable {
        /// `if <summary>.typedNothing {` whose ELSE branch — not its then branch — draws the grade.
        case headline
        /// `<summary>.typedNothing ?` inside `scoreGrid`, the accuracy tile's "—".
        case accuracyTile
        /// `… typedNothing != true` in the condition of the `if` that shows the `ShareLink`.
        case shareGuard
    }

    static let screenSites: [(view: String, sites: [Site])] = [
        ("ResultsView", [.headline, .accuracyTile, .shareGuard]),
        ("ConjugationResultsView", [.headline, .accuracyTile]),
    ]

    /// Every site in `sites` that no code mention of `typedNothing` in `file` satisfies, plus any
    /// mention that is none of them (an unpinned new decision is a reason to extend this list).
    static func screenProblems(_ file: CallSiteScanner.File, sites: [Site]) -> [String] {
        let code = file.code
        func next(after offset: Int) -> (byte: UInt8, at: Int)? {
            let at = CallSiteScanner.skipSpace(code, offset)
            return at < code.count ? (code[at], at) : nil
        }
        func block(openingAt open: Int) -> Range<Int>? {
            guard code[open] == UInt8(ascii: "{"), let close = CallSiteScanner.matching(code, open: open) else { return nil }
            return open..<(close + 1)
        }
        func linePrefix(_ offset: Int) -> String {
            var start = offset
            while start > 0, code[start - 1] != 10 { start -= 1 }
            return String(decoding: code[start..<offset], as: UTF8.self).trimmingCharacters(in: .whitespaces)
        }
        let grades = file.calls(named: "grade").map(\.nameOffset)
        let shares = file.calls(named: "ShareLink").map(\.nameOffset)
        let scoreGrid = file.functions(named: "scoreGrid").compactMap(\.body)

        func site(of mention: Int) -> Site? {
            let end = mention + "typedNothing".utf8.count
            // headline
            if linePrefix(mention).range(of: #"^if\s+\w+\.$"#, options: .regularExpression) != nil,
               let open = next(after: end), open.byte == UInt8(ascii: "{"), let then = block(openingAt: open.at),
               let word = CallSiteScanner.word(in: code, at: CallSiteScanner.skipSpace(code, then.upperBound)),
               word.0 == "else", let elseOpen = next(after: word.1), let otherwise = block(openingAt: elseOpen.at),
               grades.contains(where: { otherwise.contains($0) }), !grades.contains(where: { then.contains($0) }) {
                return .headline
            }
            // accuracyTile
            if scoreGrid.contains(where: { $0.contains(mention) }), next(after: end)?.byte == UInt8(ascii: "?") {
                return .accuracyTile
            }
            // shareGuard
            let rest = String(decoding: code[end..<min(code.count, end + 12)], as: UTF8.self)
            if CallSiteScanner.isInConditionHead(code, mention),
               rest.range(of: #"^\s*!=\s*true\b"#, options: .regularExpression) != nil,
               let brace = code[end...].firstIndex(of: UInt8(ascii: "{")), let body = block(openingAt: brace),
               shares.contains(where: { body.contains($0) }) {
                return .shareGuard
            }
            return nil
        }

        let mentions = file.mentions(of: "typedNothing")
        let found = mentions.map { ($0, site(of: $0)) }
        var problems = sites.filter { wanted in !found.contains { $0.1 == wanted } }
            .map { "\(file.path): no \($0.rawValue) decided by typedNothing" }
        problems += found.filter { $0.1 == nil || !sites.contains($0.1!) }
            .map { "\(file.location($0.0)): a typedNothing this test does not know — pin it" }
        return problems
    }

    /// Controls through the same function: the shipped shape passes, and each mutation the review
    /// ran — plus the fix written only in a comment — is reported as exactly the site it removed.
    @Test("control: each screen site is found by its shape, and each removal is named")
    func screenSitesAreCalibrated() {
        let shipped = """
            struct R {
                var content: some View {
                    if summary.typedNothing {
                        Text(title)
                    } else {
                        Text(flag)
                        grade(for: summary)
                    }
                    if let card = shareCard, model.lastSummary?.typedNothing != true {
                        ShareLink(item: card) { Text(share) }
                    }
                }
                private func scoreGrid(_ summary: GameSummary) -> some View {
                    let accuracyCard = summary.typedNothing
                        ? (value: dash, spoken: nothing)
                        : (value: percent, spoken: nil)
                    return Text(accuracyCard.value)
                }
            }
            """
        let all: [Site] = [.headline, .accuracyTile, .shareGuard]
        #expect(Self.screenProblems(.init(path: "Shipped.swift", source: shipped), sites: all).isEmpty,
                "\(Self.screenProblems(.init(path: "Shipped.swift", source: shipped), sites: all))")
        let mutants: [(String, String, Site)] = [
            ("if summary.typedNothing {", "if false { // summary.typedNothing", .headline),
            ("summary.typedNothing\n", "false\n", .accuracyTile),
            (", model.lastSummary?.typedNothing != true {", " {", .shareGuard),
        ]
        for (old, new, removed) in mutants {
            let source = shipped.replacingOccurrences(of: old, with: new)
            #expect(source != shipped, "the \(removed) mutant did not apply")
            #expect(Self.screenProblems(.init(path: "Mutant.swift", source: source), sites: all)
                    == ["Mutant.swift: no \(removed.rawValue) decided by typedNothing"],
                    "\(removed): \(Self.screenProblems(.init(path: "Mutant.swift", source: source), sites: all))")
        }
        // Branches swapped: the grade drawn for a run that typed nothing is not a headline decision.
        let swapped = shipped.replacingOccurrences(of: "Text(title)", with: "grade(for: summary)")
        #expect(Self.screenProblems(.init(path: "Swapped.swift", source: swapped), sites: all).contains {
            $0.hasSuffix("no headline decided by typedNothing")
        })
    }
}
