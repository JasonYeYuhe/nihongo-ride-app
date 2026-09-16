import Testing
import Foundation
@testable import NihongoRideApp

// MARK: - What each StoreKit answer means, observed at last
//
// `RouteStore.purchase()` turns StoreKit's answer into three things: a ledger signal, a `notice`,
// and `lastOutcome` — the counter's vocabulary, which PLAN-STAGE1 §K reads. Until 2026-09-17 that
// mapping was written inline against `Product.PurchaseResult`, which a test cannot construct, and
// the macOS StoreKit gates all skip because SKTestSession is inert on this machine. So which notice
// a pending purchase shows, and which outcome a cancel records, were observed by nothing.
//
// The mapping now lives in `RouteStore.purchasePlan(for:revokedAt:now:)`, a pure function these
// tests drive through every answer. `purchase()` only translates StoreKit's result into a
// `PurchaseAnswer` and does what the plan says, and the scan below reads its body to hold it to
// that — a correct plan that `purchase()` ignored would pass every behavioural test here.
//
// ## What these cannot see — stated so nobody reads green as more than it is
//
// * The translation from StoreKit's types into a `PurchaseAnswer`: a `.pending` result mapped to
//   `.userCancelled` inside `purchase()` passes. Only PLAN-STAGE1 §L's manual gates observe it.
// * The settle loop, `isPurchasing`, and whether `transaction.finish()` actually ran. The scan
//   checks that exactly one `finish()` call sits BEFORE the plan in `purchase()`'s source — source
//   order, not execution.
// * The scan finds names, not types (see `CallSiteScanner`). A value laundered through a helper
//   function (`lastOutcome = outcome(of: plan)`) is reported, which is spurious but loud.
//
// No `EntitlementKit` import, for the reason `ObservedNowTests` gives: this target does not declare
// it, and `ModuleDependencyTests` fails a test target that imports what it does not declare. Its
// types are reached through `RouteStore`'s own API, and an outcome is compared by its raw value —
// which is the string the counter persists and prints, so it is also the thing worth pinning.

@Suite("RouteStore.purchasePlan gives every StoreKit answer its meaning")
struct PurchasePlanTests {

    /// A fixed instant, so a stamp is compared exactly rather than bracketed against the clock.
    static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// `PurchaseAnswer` carries values, so it cannot be `CaseIterable`. Coverage is kept by an
    /// exhaustive switch instead: a new answer does not compile here until it has a `Kind`, and a
    /// `Kind` with no row in `rows` fails `everyAnswerHasARow`.
    enum Kind: CaseIterable {
        case verified, unverified, pending, userCancelled, unrecognised, threw, productMissing
    }

    static func kind(of answer: RouteStore.PurchaseAnswer) -> Kind {
        switch answer {
        case .verified: .verified
        case .unverified: .unverified
        case .pending: .pending
        case .userCancelled: .userCancelled
        case .unrecognised: .unrecognised
        case .threw: .threw
        case .productMissing: .productMissing
        }
    }

    struct Row {
        let answer: RouteStore.PurchaseAnswer
        /// The `originalID` the entitled signal must carry; nil when no signal may be applied.
        let entitles: UInt64?
        let notice: RouteStore.Notice?
        /// `UnlockOfferEvent.rawValue`.
        let outcome: String
        let settles: Bool
    }

    /// Written out by hand from what `purchase()` did before the seam existed (`dc2cbb6`), not
    /// computed — a table derived from the function under test would agree with any mutant of it.
    static let rows: [Row] = [
        Row(answer: .verified(originalID: 2_000_000_123), entitles: 2_000_000_123,
            notice: nil, outcome: "purchaseSucceeded", settles: true),
        Row(answer: .unverified, entitles: nil,
            notice: .unverified, outcome: "purchaseUnverified", settles: false),
        Row(answer: .pending, entitles: nil,
            notice: .pending, outcome: "purchasePending", settles: false),
        Row(answer: .userCancelled, entitles: nil,
            notice: nil, outcome: "purchaseCancelled", settles: false),
        Row(answer: .unrecognised, entitles: nil,
            notice: .failed("The purchase ended in an unexpected state. If you were charged, use Restore."),
            outcome: "purchaseUnrecognised", settles: false),
        Row(answer: .threw("The network connection was lost."), entitles: nil,
            notice: .failed("The network connection was lost."), outcome: "purchaseFailed", settles: false),
        Row(answer: .productMissing, entitles: nil,
            notice: .productMissing, outcome: "offerUnavailable", settles: false),
    ]

    @Test("the table covers every answer StoreKit can give")
    func everyAnswerHasARow() {
        let covered = Set(Self.rows.map { Self.kind(of: $0.answer) })
        #expect(covered == Set(Kind.allCases),
                "no row for \(Set(Kind.allCases).subtracting(covered)) — an answer whose meaning nothing checks")
        #expect(Self.rows.count == Kind.allCases.count, "a kind has two rows, so one of them is not the one being read")
    }

    @Test("every answer maps to the notice, outcome, signal and settle it had before the seam")
    func everyAnswerMapsAsBefore() {
        for row in Self.rows {
            let plan = RouteStore.purchasePlan(for: row.answer, revokedAt: nil, now: Self.now)
            #expect(plan.notice == row.notice, "\(row.answer): notice \(String(describing: plan.notice)), expected \(String(describing: row.notice))")
            #expect(plan.outcome.rawValue == row.outcome, "\(row.answer): outcome \(plan.outcome.rawValue), expected \(row.outcome)")
            #expect(plan.settles == row.settles, "\(row.answer): settles \(plan.settles), expected \(row.settles)")
            if let id = row.entitles {
                #expect(plan.signal == .entitled(id: id, at: Self.now),
                        "\(row.answer): signal \(String(describing: plan.signal)), expected entitled(\(id)) stamped now")
            } else {
                #expect(plan.signal == nil, "\(row.answer) must not open anything, got \(String(describing: plan.signal))")
            }
        }
    }

    /// Named on its own because it is the easiest one to "tidy": the customer closed Apple's own
    /// sheet and knows what they did, so no notice — but the attempt is still an outcome, and the
    /// single most informative thing the experiment can see short of a sale.
    @Test("a cancel sets no notice, and still records purchaseCancelled")
    func aCancelIsSilentButCounted() {
        let plan = RouteStore.purchasePlan(for: .userCancelled, revokedAt: nil, now: Self.now)
        #expect(plan.notice == nil, "a cancel must not show a notice, got \(String(describing: plan.notice))")
        #expect(plan.outcome.rawValue == "purchaseCancelled", "a cancel must still be recorded, got \(plan.outcome.rawValue)")
        #expect(plan.signal == nil && !plan.settles)
    }

    /// The one behaviour this seam changed. Before it, `purchase()` stamped the verified signal
    /// with `Date()`, while `readStore` already used `observedNow` — so after a refund, with the
    /// clock moved backwards, a re-purchase compared older than the recorded revocation and read as
    /// not entitled until a later store read answered.
    @Test("a verified purchase is stamped after a revocation the clock has moved back past, and at now otherwise")
    func theVerifiedStampNeverLandsBeforeAKnownRevocation() {
        let id: UInt64 = 2_000_000_456
        /// The stamp on the entitled signal, or nil (recorded as an issue) when there is none.
        func stamp(revokedAt: Date?) -> Date? {
            let plan = RouteStore.purchasePlan(for: .verified(originalID: id), revokedAt: revokedAt, now: Self.now)
            guard case .entitled(let signalled, let at)? = plan.signal else {
                Issue.record("a verified purchase produced \(String(describing: plan.signal)), not an entitled signal")
                return nil
            }
            #expect(signalled == id, "the signal carries \(signalled), not the transaction's originalID \(id)")
            return at
        }

        #expect(stamp(revokedAt: nil) == Self.now, "nothing revoked: the stamp must be now")
        let past = Self.now.addingTimeInterval(-3_600)
        #expect(stamp(revokedAt: past) == Self.now, "a revocation an hour ago must not move the stamp off now")

        // The case `Date()` fails: a refund recorded an hour AHEAD of this device's clock.
        let future = Self.now.addingTimeInterval(3_600)
        let afterRefund = stamp(revokedAt: future)
        #expect(afterRefund.map { $0 > future } == true,
                """
                a re-purchase after a refund the clock has moved back past was stamped \
                \(String(describing: afterRefund)), not after the revocation at \(future) — isEntitled \
                compares verified > revoked, so the customer who just paid would read as not entitled
                """)
    }
}

// MARK: - purchase() does what the plan says, and decides nothing itself

/// A pure function of one file, so the shipped source and the planted samples go through exactly the
/// same code (the house rule `OneBranchRules` states, for the reason `EntitlementSeamTests` records).
enum PurchaseSeamRule {
    typealias File = CallSiteScanner.File

    struct Report {
        var violations: [String] = []
        /// Writes to `notice` or `lastOutcome` found anywhere in the file.
        var writes = 0
    }

    static func check(_ file: File) -> Report {
        var report = Report()
        let purchases = file.functions(named: "purchase").filter { $0.body != nil }
        let homes = file.functions(named: "purchasePlan").filter { $0.body != nil }
        guard purchases.count == 1, let body = purchases[0].body else {
            report.violations.append("expected exactly ONE func purchase with a body in \(file.path), found \(purchases.count)")
            return report
        }
        if homes.count != 1 {
            report.violations.append("expected exactly ONE func purchasePlan with a body in \(file.path), found \(homes.count) — the mapping moved or was duplicated")
        }
        let home = homes.first?.body
        let purchaseText = file.text(body)

        // 1. The mapping is consulted once, and its answer bound to a constant.
        let consults = file.calls(named: "purchasePlan").filter { body.contains($0.nameOffset) }
        if consults.count != 1 {
            report.violations.append("\(file.location(body.lowerBound)) purchase() consults purchasePlan \(consults.count) time(s), not once")
        }
        let planName = CallSiteScanner.captures(#"\blet\s+(\w+)\s*=\s*(?:Self\.|RouteStore\.)?purchasePlan\s*\("#,
                                                 in: purchaseText).sorted().first
        if planName == nil {
            report.violations.append("\(file.location(body.lowerBound)) purchase() does not bind purchasePlan's result with `let`")
        }

        /// `plan.field`, or a name bound from it in purchase() (`if let notice = plan.notice`).
        func isFromPlan(_ value: String, field: String) -> Bool {
            guard let planName else { return false }
            if value == "\(planName).\(field)" { return true }
            let bound = CallSiteScanner.captures(#"\blet\s+(\w+)\s*=\s*"# + planName + #"\."# + field + #"\b(?!\s*\.)"#,
                                                 in: purchaseText)
            return bound.contains(value)
        }

        // 2. No second plan is built anywhere but the mapping.
        for offset in file.mentions(of: "PurchasePlan") where !(home?.contains(offset) ?? false) {
            let after = file.text(offset..<min(file.code.count, offset + 40))
            if after.range(of: #"^PurchasePlan\s*(?:\.init\s*)?\("#, options: .regularExpression) != nil {
                report.violations.append("\(file.location(offset)) builds a PurchasePlan outside purchasePlan — a second mapping")
            }
        }

        // 3. Every write to notice and lastOutcome in the file.
        for property in ["notice", "lastOutcome"] {
            for offset in file.mentions(of: property) {
                guard let value = assignedValue(file, at: offset, name: property) else { continue }
                report.writes += 1
                let inPurchase = body.contains(offset)
                switch (property, inPurchase) {
                case ("lastOutcome", true) where isFromPlan(value, field: "outcome"),
                     ("notice", true) where isFromPlan(value, field: "notice"):
                    continue
                case ("notice", false) where value == "nil":
                    continue   // `refresh()` clearing a pending notice once the road has opened
                case (_, true):
                    report.violations.append("\(file.location(offset)) purchase() sets \(property) to `\(value)`, not from the plan — the mapping is being written twice")
                default:
                    report.violations.append("\(file.location(offset)) sets \(property) to `\(value)` outside purchase() — a purchase outcome decided somewhere the plan does not reach")
                }
            }
        }

        // 4. The ledger is handed the plan's signal, and the settle loop runs on the plan's word.
        let applies = file.calls(named: "apply").filter { body.contains($0.nameOffset) }
        if applies.count != 1 {
            report.violations.append("\(file.location(body.lowerBound)) purchase() applies \(applies.count) signal(s), not one")
        }
        for apply in applies {
            let first = apply.arguments.map { firstArgument(file, $0) } ?? ""
            if !isFromPlan(first, field: "signal") {
                report.violations.append("\(file.location(apply.nameOffset)) purchase() applies `\(first)`, not the plan's signal")
            }
        }
        let settles = file.calls(named: "settleEntitlement").filter { body.contains($0.nameOffset) }
        if settles.count != 1 {
            report.violations.append("\(file.location(body.lowerBound)) purchase() runs the settle loop from \(settles.count) place(s), not one")
        }
        for settle in settles {
            let block = file.innermostBlock(containing: settle.nameOffset, within: body)
            var lineStart = block?.lowerBound ?? settle.nameOffset
            while lineStart > body.lowerBound, file.code[lineStart - 1] != 10 { lineStart -= 1 }
            let head = block.map { file.text(lineStart..<$0.lowerBound) } ?? ""
            let gated = planName.map { head.range(of: #"\bif\s+"# + $0 + #"\.settles\s*$"#, options: .regularExpression) != nil } ?? false
            if !gated {
                report.violations.append("\(file.location(settle.nameOffset)) purchase() settles without asking the plan")
            }
        }

        // 5. The transaction is finished before anything is applied.
        let finishes = file.calls(named: "finish").filter { body.contains($0.nameOffset) }
        if finishes.count != 1 {
            report.violations.append("\(file.location(body.lowerBound)) purchase() finishes \(finishes.count) transaction(s), not one")
        }
        if let finish = finishes.first, let consult = consults.first, finish.nameOffset > consult.nameOffset {
            report.violations.append("\(file.location(finish.nameOffset)) purchase() finishes the transaction after consulting the plan — it must be finished before anything is applied")
        }
        return report
    }

    /// Up to the first comma not nested in brackets: `.entitled(id: x, at: y)` whole.
    static func firstArgument(_ file: File, _ arguments: Range<Int>) -> String {
        var depth = 0
        var end = arguments.upperBound
        for index in arguments {
            switch file.code[index] {
            case UInt8(ascii: "("), UInt8(ascii: "["), UInt8(ascii: "{"): depth += 1
            case UInt8(ascii: ")"), UInt8(ascii: "]"), UInt8(ascii: "}"): depth -= 1
            case UInt8(ascii: ",") where depth == 0: end = index
            default: continue
            }
            if end != arguments.upperBound { break }
        }
        return file.text(arguments.lowerBound..<end).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The value written when `name` at `offset` is an assignment to this object's property —
    /// `notice = x` or `self.notice = x`, not `let notice = x`, `plan.notice`, or `notice == x`.
    static func assignedValue(_ file: File, at offset: Int, name: String) -> String? {
        if offset > 0, file.code[offset - 1] == UInt8(ascii: ".") {
            let before = file.text(max(0, offset - 6)..<(offset - 1))
            guard before.hasSuffix("self"), offset < 6 || !CallSiteScanner.isIdentifier(file.code[offset - 6]) else { return nil }
        } else {
            var end = offset
            while end > 0, file.code[end - 1] == 32 || file.code[end - 1] == 9 { end -= 1 }
            var start = end
            while start > 0, CallSiteScanner.isIdentifier(file.code[start - 1]) { start -= 1 }
            if ["let", "var", "case"].contains(file.text(start..<end)) { return nil }
        }
        var cursor = CallSiteScanner.skipSpace(file.code, offset + name.utf8.count, newlines: false)
        guard cursor < file.code.count, file.code[cursor] == UInt8(ascii: "="),
              cursor + 1 >= file.code.count || file.code[cursor + 1] != UInt8(ascii: "=")
        else { return nil }
        cursor += 1
        var end = cursor
        while end < file.code.count, ![10, UInt8(ascii: ";"), UInt8(ascii: "}")].contains(file.code[end]) { end += 1 }
        return file.text(cursor..<end).trimmingCharacters(in: .whitespaces)
    }
}

enum PurchaseSeamSamples {
    typealias File = CallSiteScanner.File

    /// Today's shape, look-alikes included: a notice cleared outside purchase(), a comparison, two
    /// declarations, bindings named like the properties, and `finish()` in the updates observer.
    /// Line numbers below are this sample's, counted from `final class` as line 1.
    static let todaySource = #"""
        final class RouteStore {
            var notice: Notice?
            private(set) var lastOutcome: UnlockOfferEvent = .purchaseUnrecognised
            func refresh() async {
                if ledger.isEntitled, notice == .pending { notice = nil }
            }
            nonisolated static func purchasePlan(for answer: PurchaseAnswer, revokedAt: Date?, now: Date) -> PurchasePlan {
                switch answer {
                case .pending: return PurchasePlan(signal: nil, notice: .pending, outcome: .purchasePending, settles: false)
                default: return PurchasePlan(signal: nil, notice: nil, outcome: .purchaseCancelled, settles: false)
                }
            }
            func purchase() async {
                let answer: PurchaseAnswer
                if let product {
                    switch try await product.purchase() {
                    case .success(.verified(let transaction)):
                        await transaction.finish()
                        answer = .verified(originalID: transaction.originalID)
                    default: answer = .pending
                    }
                } else { answer = .productMissing }
                let plan = Self.purchasePlan(for: answer, revokedAt: ledger.record.revokedAt, now: Date())
                if let signal = plan.signal { ledger.apply(signal, savingTo: defaults) }
                if plan.settles { await settleEntitlement() }
                if let notice = plan.notice { self.notice = notice }
                lastOutcome = plan.outcome
            }
            private func observeTransactionUpdates() -> Task<Void, Never> {
                Task { for await update in Transaction.updates { if case .verified(let t) = update { await t.finish() } } }
            }
        }
        """#

    static let today = File(path: "Sources/NihongoRideApp/RouteStore.swift", source: todaySource)

    /// Today's sample with each `old` replaced by its `new`. A replacement that no longer matches is
    /// recorded as an issue rather than silently returning today's shape — which would make the
    /// "is caught" expectation fail for the wrong reason, or pass if it only looked for silence.
    static func mutated(_ replacements: [(old: String, new: String)]) -> File {
        var source = todaySource
        for (old, new) in replacements {
            if !source.contains(old) { Issue.record("the planted mutation no longer matches the sample: \(old)") }
            source = source.replacingOccurrences(of: old, with: new)
        }
        return File(path: today.path, source: source)
    }
}

@Suite("RouteStore.purchase() does what purchasePlan says, and decides nothing itself")
struct PurchaseSeamScanTests {
    typealias S = PurchaseSeamSamples

    @Test("the shipped RouteStore.swift takes the signal, settle, notice and lastOutcome only from the plan")
    func theShippedAdapterObeysThePlan() throws {
        let files = try CallSiteScanner.shippedSources.get()
        let file = try #require(files.first { $0.path == "Sources/NihongoRideApp/RouteStore.swift" },
                                "RouteStore.swift is not where the scan looks — if it moved, this test must follow it")
        let report = PurchaseSeamRule.check(file)
        // purchase()'s notice and lastOutcome, and refresh()'s clear: a scan that found fewer is
        // reading nothing and would report clean.
        #expect(report.writes >= 3, "only \(report.writes) write(s) to notice/lastOutcome found — the scan is misdirected")
        #expect(report.violations.isEmpty, "\(report.violations.count) violation(s):\n\(report.violations.joined(separator: "\n"))")
    }

    @Test("today's shape passes, look-alikes included")
    func todaysShapePasses() {
        let report = PurchaseSeamRule.check(S.today)
        #expect(report.violations.isEmpty, "the scan fires on the shape it must allow: \(report.violations)")
        #expect(report.writes == 3, "expected purchase()'s two writes and refresh()'s clear, got \(report.writes)")
    }

    @Test("lastOutcome or notice set directly in one branch of purchase() is caught")
    func aDirectWriteInABranchIsCaught() {
        let outcome = PurchaseSeamRule.check(S.mutated([("default: answer = .pending",
                                                         "default: answer = .pending; lastOutcome = .purchasePending")]))
        #expect(outcome.violations.contains { $0.contains("RouteStore.swift:20 ") && $0.contains("sets lastOutcome to `.purchasePending`") },
                "\(outcome.violations)")
        let notice = PurchaseSeamRule.check(S.mutated([("{ self.notice = notice }", "{ self.notice = .pending }")]))
        #expect(notice.violations.contains { $0.contains("RouteStore.swift:26 ") && $0.contains("sets notice to `.pending`") },
                "\(notice.violations)")
    }

    @Test("an outcome decided outside purchase(), or a second plan built inside it, is caught")
    func aSecondMappingIsCaught() {
        let outside = PurchaseSeamRule.check(S.mutated([("{ notice = nil }", "{ notice = nil; lastOutcome = .purchaseSucceeded }")]))
        #expect(outside.violations.contains { $0.contains("RouteStore.swift:5 ") && $0.contains("outside purchase()") }, "\(outside.violations)")
        let notice = PurchaseSeamRule.check(S.mutated([("{ notice = nil }", "{ notice = .unverified }")]))
        #expect(notice.violations.contains { $0.contains("RouteStore.swift:5 ") && $0.contains("sets notice to `.unverified` outside") }, "\(notice.violations)")
        // Shadowed: `lastOutcome = plan.outcome` still reads `plan.outcome`, from a plan the mapping never built.
        let rebuilt = PurchaseSeamRule.check(S.mutated([("lastOutcome = plan.outcome",
                                                         "if true { let plan = PurchasePlan(signal: nil, notice: nil, outcome: .purchaseFailed, settles: false); lastOutcome = plan.outcome }")]))
        #expect(rebuilt.violations.contains { $0.contains("RouteStore.swift:27 ") && $0.contains("builds a PurchasePlan outside") }, "\(rebuilt.violations)")
    }

    @Test("a signal or a settle that does not come from the plan is caught")
    func applyAndSettleFollowThePlan() {
        let stamped = PurchaseSeamRule.check(S.mutated([("ledger.apply(signal, savingTo: defaults)",
                                                         "ledger.apply(.entitled(id: transactionID, at: Date()), savingTo: defaults)")]))
        #expect(stamped.violations.contains { $0.contains("RouteStore.swift:24 ") && $0.contains("applies `.entitled(id: transactionID, at: Date())`, not the plan's signal") },
                "\(stamped.violations)")
        let settled = PurchaseSeamRule.check(S.mutated([("if plan.settles { await settleEntitlement() }", "await settleEntitlement()")]))
        #expect(settled.violations.contains { $0.contains("RouteStore.swift:25 ") && $0.contains("settles without asking the plan") }, "\(settled.violations)")
    }

    @Test("a transaction finished after the plan, or not at all, is caught")
    func finishingLateIsCaught() {
        let late = PurchaseSeamRule.check(S.mutated([
            ("await transaction.finish()", "finished = transaction"),
            ("lastOutcome = plan.outcome", "lastOutcome = plan.outcome; await finished?.finish()"),
        ]))
        #expect(late.violations.contains { $0.contains("RouteStore.swift:27 ") && $0.contains("after consulting the plan") }, "\(late.violations)")
        let never = PurchaseSeamRule.check(S.mutated([("await transaction.finish()", "_ = transaction")]))
        #expect(never.violations.contains { $0.contains("finishes 0 transaction(s)") }, "\(never.violations)")
    }
}
