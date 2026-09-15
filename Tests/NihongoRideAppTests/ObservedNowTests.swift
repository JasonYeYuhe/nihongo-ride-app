import Testing
import Foundation
@testable import NihongoRideApp

/// `RouteStore.observedNow(after:)` — the stamp that keeps a re-purchase from looking older than
/// the refund before it.
///
/// It had no test at all. Its whole reason to exist is the one case that cannot happen on a
/// healthy clock — a revocation this device recorded that now sits in the *future*, because the
/// clock moved backwards between the refund and the next read — so a suite that only ever
/// exercised "now" would pass just as well for `return Date()`. The third case below is the one
/// that fails for that, and it was measured failing (see the commit that added this file).
///
/// What is checked is the property its doc comment states, not a re-derivation of its body:
/// the stamp is "now" whenever "now" is already after everything this device knows, and is
/// otherwise strictly after the revocation — by exactly one second, so the stamp is still a
/// deterministic function of what the device recorded rather than an arbitrary future time.
///
/// No `EntitlementKit` here on purpose: this target does not declare it, and
/// `ModuleDependencyTests` fails a test target that imports what it does not declare. The
/// comparison `isEntitled` makes is `verified > revoked`, and that is asserted directly on the
/// dates.
@Suite("RouteStore.observedNow never stamps before a known revocation")
struct ObservedNowTests {

    /// Tolerance for "is now". The function reads the wall clock itself, so the test can only
    /// bracket it; a second is far wider than the call and far narrower than any offset below.
    static let slack: TimeInterval = 1

    @Test("no revocation on record → the stamp is now")
    func noRevocationIsNow() {
        let before = Date()
        let stamp = RouteStore.observedNow(after: nil)
        #expect(abs(stamp.timeIntervalSince(before)) < Self.slack,
                "with nothing revoked the stamp must be the wall clock, got \(stamp) vs \(before)")
    }

    @Test("a revocation in the past → the stamp is now, and after it")
    func pastRevocationIsNow() {
        let before = Date()
        let revoked = before.addingTimeInterval(-3_600)
        let stamp = RouteStore.observedNow(after: revoked)
        #expect(abs(stamp.timeIntervalSince(before)) < Self.slack,
                "a revocation an hour ago must not move the stamp off the wall clock, got \(stamp)")
        #expect(stamp > revoked, "the stamp must land after the revocation it is compared against")
        // Paired with the future case: a function that ALWAYS returned revoked + 1 s would pass
        // the future case below and fail exactly here.
        #expect(stamp != revoked.addingTimeInterval(1),
                "the stamp was pinned to the revocation although the clock is already past it")
    }

    @Test("a revocation in the future (clock moved backwards) → exactly revocation + 1 s")
    func futureRevocationIsJustAfterIt() {
        let now = Date()
        let revoked = now.addingTimeInterval(3_600)
        let stamp = RouteStore.observedNow(after: revoked)
        #expect(stamp == revoked.addingTimeInterval(1),
                """
                a clock moved backwards past a recorded refund must still stamp the new \
                verification one second after it; got \(stamp) for a revocation at \(revoked). \
                A stamp at "now" would make a re-purchase compare older than the refund and lock \
                a paying customer out until the clock catches up.
                """)
        #expect(stamp > revoked, "verified > revoked is the comparison isEntitled makes, and it must hold")
    }
}
