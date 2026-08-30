import Testing
import Foundation

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
        let source = try Self.routeStoreSource
        let needle = "NIHONGO_FAKE_ENTITLEMENT"
        var depth = 0
        var elseDepth = 0
        var mentions = 0
        var escaped: [Int] = []

        for (number, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#if DEBUG") { depth += 1 }
            else if trimmed.hasPrefix("#endif") { depth = max(0, depth - 1) }
            // `#else` flips out of the DEBUG branch. The first version counted only `#if`/`#endif`,
            // so a seam sitting in the `#else` — the RELEASE side — read as guarded. That is the
            // one arrangement this test exists to forbid, and it was the one it could not see.
            else if trimmed.hasPrefix("#else") && depth > 0 { depth -= 1; elseDepth += 1 }
            // The mention in this file's own name and in prose does not count; only the source's.
            if line.contains(needle), !trimmed.hasPrefix("//"), !trimmed.hasPrefix("///") {
                mentions += 1
                if depth == 0 { escaped.append(number + 1) }
            }
        }

        #expect(mentions >= 1, "the seam has vanished from RouteStore.swift — if it moved, this test must follow it")
        #expect(escaped.isEmpty, "the fake-entitlement seam is reachable outside #if DEBUG at line(s) \(escaped)")
        _ = elseDepth
    }

    @Test("and the scanner can actually see an escape, so the emptiness above means something")
    func theScannerFires() {
        // The negative control. Without it, a parser that never matched anything would report the
        // seam safely contained in exactly the same words as one that checked.
        let planted = """
            init() {
                if let fake = ProcessInfo.processInfo.environment["NIHONGO_FAKE_ENTITLEMENT"] {
                    entitled = true
                }
            }
            """
        var depth = 0
        var escaped = 0
        for line in planted.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#if DEBUG") { depth += 1 }
            else if trimmed.hasPrefix("#endif") { depth = max(0, depth - 1) }
            if line.contains("NIHONGO_FAKE_ENTITLEMENT"), !trimmed.hasPrefix("//"), depth == 0 { escaped += 1 }
        }
        #expect(escaped == 1, "the scanner cannot detect an unguarded seam")
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
        let source = try Self.appModelSource
        let needle = "NIHONGO_FAKE_LIFETIME_METRES"
        var depth = 0
        var mentions = 0
        var escaped: [Int] = []

        for (number, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#if DEBUG") { depth += 1 }
            else if trimmed.hasPrefix("#endif") { depth = max(0, depth - 1) }
            else if trimmed.hasPrefix("#else") && depth > 0 { depth -= 1 }
            if line.contains(needle), !trimmed.hasPrefix("//"), !trimmed.hasPrefix("///") {
                mentions += 1
                if depth == 0 { escaped.append(number + 1) }
            }
        }

        #expect(mentions >= 1, "the odometer seam has vanished from AppModel.swift — if it moved, this test must follow it")
        #expect(escaped.isEmpty, "the fake-odometer seam is reachable outside #if DEBUG at line(s) \(escaped)")
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

    @Test("and the scanner can see an escape, so the emptiness above means something")
    func theScannerFires() {
        let planted = """
            var lifetimeDistanceMeters: Double {
                if let fake = ProcessInfo.processInfo.environment["NIHONGO_FAKE_LIFETIME_METRES"] {
                    return Double(fake) ?? 0
                }
            }
            """
        var depth = 0
        var escaped = 0
        for line in planted.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#if DEBUG") { depth += 1 }
            else if trimmed.hasPrefix("#endif") { depth = max(0, depth - 1) }
            if line.contains("NIHONGO_FAKE_LIFETIME_METRES"), !trimmed.hasPrefix("//"), depth == 0 { escaped += 1 }
        }
        #expect(escaped == 1, "the scanner cannot detect an unguarded seam")
    }
}
