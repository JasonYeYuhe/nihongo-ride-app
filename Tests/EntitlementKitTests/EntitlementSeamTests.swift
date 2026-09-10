import Testing
import Foundation

/// **The one scanner.** Both suites' real assertions and all of their negative controls run
/// through it, so a control cannot certify a parser that is not the one doing the work.
///
/// It exists because that is exactly what was happening. The scanning loop was written out FOUR
/// times in this file — two real copies reading shipped source, two controls reading a planted
/// string — and only the real copies carried the `#else` rule. Git records how: `83ab016` added
/// the rule to the one scanner that then existed and, in the same commit, fixed the identical
/// defect in `RideRouteFreezeTests`' regex control; `1b267ce` then added the second suite by
/// copying the fixed scanner and re-writing an unfixed control.
///
/// **Measured before the repair: deleting BOTH `#else` rules left the whole suite green.** The
/// property the comment declared was enforced by nothing — in the file whose subject is a comment
/// that nothing enforces, guarding the one seam in this app that is worth money.
enum SeamScanner {
    struct Result: Equatable {
        /// Every non-comment line naming the needle.
        var mentions = 0
        /// The 1-based lines where it is reachable OUTSIDE `#if DEBUG`.
        var escaped: [Int] = []
        /// How many `#else` branches the scan walked out of. Zero in both shipped sources today,
        /// which is precisely why the rule needs a planted sample and cannot be exercised by them.
        var elseBranches = 0
    }

    static func scan(_ source: String, for needle: String) -> Result {
        var out = Result()
        var depth = 0
        for (number, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#if DEBUG") { depth += 1 }
            else if trimmed.hasPrefix("#endif") { depth = max(0, depth - 1) }
            // THE `#else` RULE, in the one place it now exists.
            //
            // `#else` flips out of the DEBUG branch, so a seam sitting on the RELEASE side reads as
            // guarded without this line. Deleting it must turn `aSeamHiddenInAnElseBranchIsCaught`
            // red in BOTH suites and nothing else — that is the acceptance criterion, and it is
            // only reachable because those samples exist. Neither shipped source contains an
            // `#else` anywhere near its seam, so the real tests cannot exercise this rule and must
            // not be asked to.
            else if trimmed.hasPrefix("#else") && depth > 0 { depth -= 1; out.elseBranches += 1 }
            if line.contains(needle), !trimmed.hasPrefix("//"), !trimmed.hasPrefix("///") {
                out.mentions += 1
                if depth == 0 { out.escaped.append(number + 1) }
            }
        }
        return out
    }

    // MARK: The planted samples
    //
    // Swift does not evaluate `#if` inside a `"""` literal — the scanner reads these as data, the
    // compiler as text. Each needle gets all three shapes, because one alone proves less than it
    // looks: "the scanner reports an escape" is satisfied by a parser that always does.

    /// No directives at all. The shape the original controls used — and the reason the first
    /// draft's acceptance criterion was impossible: with no `#else` in the sample, repairing the
    /// control still leaves it green when the rule is deleted.
    static func unguarded(_ needle: String) -> String {
        """
        init() {
            if ProcessInfo.processInfo.environment["\(needle)"] != nil { entitled = true }
        }
        """
    }

    /// The arrangement this file exists to forbid: the seam on the RELEASE side of an `#else`.
    /// A scanner without the rule counts `#if DEBUG` and never leaves it, so it reads depth 1 —
    /// guarded — for a line that ships.
    static func hiddenInElse(_ needle: String) -> String {
        """
        init() {
            #if DEBUG
            entitled = ledger.isEntitled
            #else
            if ProcessInfo.processInfo.environment["\(needle)"] != nil { entitled = true }
            #endif
        }
        """
    }

    /// Genuinely guarded. Without this, "the scanner finds an escape" is satisfied by a scanner
    /// that finds one everywhere, and both assertions above would pass for the wrong reason.
    static func properlyGuarded(_ needle: String) -> String {
        """
        init() {
            #if DEBUG
            if ProcessInfo.processInfo.environment["\(needle)"] != nil { entitled = true }
            #endif
        }
        """
    }
}

/// The UI-test seam, and the proof that it cannot ship.
///
/// iOS StoreKit testing is measurably dead on this toolchain, so the iOS UI tests assert PLACEMENT
/// against a faked entitlement (`NIHONGO_FAKE_ENTITLEMENT`) rather than buying anything. That
/// hook's failure mode is not subtle: **it is a free unlock for anyone who can set an environment
/// variable, and in a Release build that is anyone.**
///
/// So the hook is inside `#if DEBUG`, and this reads the shipped source to prove it rather than
/// trusting the comment next to it — which is this project's cheapest detector applied to the one
/// place where the thing being asserted is worth money.
@Suite("The UI-test entitlement seam cannot reach a shipping build")
struct EntitlementSeamTests {

    /// One needle for the real assertion AND its controls — they must not be able to look for
    /// different strings.
    private static let needle = "NIHONGO_FAKE_ENTITLEMENT"

    private static var routeStoreSource: String {
        get throws {
            let url = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Sources/NihongoRideApp/RouteStore.swift")
            return try String(contentsOf: url, encoding: .utf8)
        }
    }

    @Test("every mention of the fake-entitlement variable sits inside #if DEBUG")
    func theSeamIsDebugOnly() throws {
        let result = SeamScanner.scan(try Self.routeStoreSource, for: Self.needle)
        #expect(result.mentions >= 1,
                "the seam has vanished from RouteStore.swift — if it moved, this test must follow it")
        #expect(result.escaped.isEmpty,
                "the fake-entitlement seam is reachable outside #if DEBUG at line(s) \(result.escaped)")
    }

    /// The negative control, run through the REAL scanner. Without it, a parser that never matched
    /// anything would report the seam safely contained in exactly the same words as one that
    /// checked — and before v1.32 §D4 this control ran a hand-typed copy instead, so it certified
    /// a parser that was not the one doing the work.
    @Test("the scanner sees an unguarded seam, and does not see a guarded one")
    func theScannerFires() {
        #expect(SeamScanner.scan(SeamScanner.unguarded(Self.needle), for: Self.needle).escaped.count == 1,
                "the scanner cannot detect an unguarded seam")
        #expect(SeamScanner.scan(SeamScanner.properlyGuarded(Self.needle), for: Self.needle).escaped.isEmpty,
                "the scanner reports an escape for a seam that IS guarded — it is not discriminating")
    }

    /// **The acceptance criterion for v1.32 §D4.** Delete the `#else` line in `SeamScanner.scan`
    /// and this goes red; restore it and it passes. Measured both ways.
    ///
    /// It needs the planted sample as much as the shared scanner: §D4's first draft asked for
    /// "delete the rule and watch the control go red", which was impossible, because the sample
    /// the control scanned contained no `#else` at all. Repairing the control was necessary and
    /// not sufficient.
    @Test("a seam hidden on the release side of an #else is caught")
    func aSeamHiddenInAnElseBranchIsCaught() {
        let result = SeamScanner.scan(SeamScanner.hiddenInElse(Self.needle), for: Self.needle)
        #expect(result.elseBranches == 1, "the sample no longer contains an #else — the rule is untested again")
        #expect(result.escaped.count == 1,
                "a seam on the RELEASE side of an #else read as guarded — that is a free unlock that ships")
    }

    @Test("an unset or misspelled value leaves the real ledger alone")
    func theSeamFailsTowardTheRealAnswer() throws {
        // A seam that faked EVERY launch would satisfy a naive assertion and ship a free unlock —
        // so the shape that matters is that the DEFAULT branch does nothing. Asserted against the
        // source because the behaviour lives in an initialiser that cannot be constructed here
        // without the app module.
        let source = try Self.routeStoreSource
        let switchBody = try #require(source.range(of: "switch fake {").map { String(source[$0.upperBound...]) })
        let body = String(switchBody.prefix(while: { $0 != "}" }))
        #expect(body.contains("default: break"),
                "the fake-entitlement switch has no inert default — an unrecognised value must leave the real ledger untouched")
        #expect(body.contains("case \"verified\""))
    }
}

/// The **second** debug seam, and the one that could repaint somebody's world.
///
/// v1.30's menu shows an arrived state past Kyōto, which is 25 km and 48 rides away — so neither a
/// UI test nor a headless render can reach it by riding. `NIHONGO_FAKE_LIFETIME_METRES` overrides
/// the odometer so they can.
///
/// It is more dangerous than the entitlement seam and is guarded accordingly. Distance does not
/// only decide what is *offered*: `AppModel.rideableStages` and `resolveRideStage()` read it to
/// decide **which stretch of road a rider is on**. A seam that leaked would not hand out a free
/// unlock, it would change the world an existing rider sees — HARD CONSTRAINT 1, the one this
/// release is not allowed to break. So it carries two guards where the entitlement seam carries
/// one, and this file checks both.
@Suite("The UI-test odometer seam cannot reach a shipping build")
struct DebugSeamTests {

    private static let needle = "NIHONGO_FAKE_LIFETIME_METRES"

    private static var appModelSource: String {
        get throws {
            let url = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Sources/NihongoRideApp/AppModel.swift")
            return try String(contentsOf: url, encoding: .utf8)
        }
    }

    @Test("every mention of the fake-odometer variable sits inside #if DEBUG")
    func theSeamIsDebugOnly() throws {
        let result = SeamScanner.scan(try Self.appModelSource, for: Self.needle)
        #expect(result.mentions >= 1,
                "the odometer seam has vanished from AppModel.swift — if it moved, this test must follow it")
        #expect(result.escaped.isEmpty,
                "the fake-odometer seam is reachable outside #if DEBUG at line(s) \(result.escaped)")
    }

    @Test("and it is additionally gated on an isolation that touches nothing of the user's")
    func theSeamIsAlsoGatedOnIsolation() throws {
        // The second guard, which the entitlement seam does not have and this one needs. `#if
        // DEBUG` still runs in every developer build and every simulator run of the real app; on
        // its own it would let a debug launch with this variable set rewrite what road the owner's
        // own install draws. The isolation predicate is what keeps it to UI tests and captures.
        let source = try Self.appModelSource
        let start = try #require(source.range(of: "NIHONGO_FAKE_LIFETIME_METRES"))
        // The guard must be part of the SAME condition, so look immediately above the mention
        // rather than anywhere in the file — a `touchesNothingOfTheUsers` five hundred lines away
        // would satisfy a whole-file search while guarding nothing.
        let preceding = String(source[..<start.lowerBound].suffix(400))
        #expect(preceding.contains("touchesNothingOfTheUsers"),
                """
                the fake-odometer seam is not gated on the isolation predicate. #if DEBUG alone \
                lets any debug launch repaint a real rider's road.
                """)
    }

    @Test("the scanner sees an unguarded seam, and does not see a guarded one")
    func theScannerFires() {
        #expect(SeamScanner.scan(SeamScanner.unguarded(Self.needle), for: Self.needle).escaped.count == 1,
                "the scanner cannot detect an unguarded seam")
        #expect(SeamScanner.scan(SeamScanner.properlyGuarded(Self.needle), for: Self.needle).escaped.isEmpty,
                "the scanner reports an escape for a seam that IS guarded — it is not discriminating")
    }

    /// Same acceptance criterion as the entitlement suite's. Both, because the `#else` rule was
    /// missing from BOTH controls and a repair to one would have left the other certifying a
    /// parser it does not use.
    @Test("a seam hidden on the release side of an #else is caught")
    func aSeamHiddenInAnElseBranchIsCaught() {
        let result = SeamScanner.scan(SeamScanner.hiddenInElse(Self.needle), for: Self.needle)
        #expect(result.elseBranches == 1, "the sample no longer contains an #else — the rule is untested again")
        #expect(result.escaped.count == 1,
                "a seam on the RELEASE side of an #else read as guarded — that is a free unlock that ships")
    }
}
