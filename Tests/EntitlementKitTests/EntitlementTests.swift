import Testing
import Foundation
@testable import EntitlementKit

/// The failure rule, driven through every branch it has.
///
/// The rule under test:
///
/// > Never revoke on failure what was previously verified. Persist the last verified entitlement
/// > and honour it offline. Fail closed **only where entitlement was never established**, and
/// > reconcile refunds and revocations when connectivity returns.
///
/// **Read `theRuleIsNotVacuous` first.** Everything else here is one half of a pair: an
/// implementation that simply answered "entitled" to every input would satisfy the offline
/// assertions and fail nothing, which is precisely the broken checker this project refuses to
/// trust. Each protective assertion is therefore matched by one that must go the other way.
@Suite("Entitlement — the failure rule")
struct EntitlementTests {

    private let sku = "com.jasonye.nihongoride.scenery.lifetime"
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func later(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    // MARK: The rule

    @Test("a verified entitlement survives every silent answer the store can give")
    func silenceNeverRevokes() {
        var record = EntitlementRecord(productID: sku)
        record.apply(.entitled(id: 1, at: t0))
        #expect(record.isEntitled)

        // An offline launch, a signed-out account, a failed product request, a StoreKit outage,
        // and the measured race in the moments after a successful purchase are ALL this input.
        // Not one of them may take the road away.
        for _ in 0 ..< 50 { record.apply(.silent) }
        #expect(record.isEntitled, "silence revoked a verified entitlement — the exact bug the house pattern ships")
        #expect(record.lastVerifiedAt == t0, "silence must not even disturb the evidence")
    }

    @Test("the rule is not vacuous: silence on a device that never bought stays closed")
    func theRuleIsNotVacuous() {
        // Without this, `silenceNeverRevokes` is satisfied by `var isEntitled: Bool { true }`.
        var record = EntitlementRecord(productID: sku)
        #expect(!record.isEntitled)
        for _ in 0 ..< 50 { record.apply(.silent) }
        #expect(!record.isEntitled, "an absence became an entitlement — the road is now free")
    }

    @Test("only an affirmative revocation closes it")
    func revocationIsTheOnlyDownward() {
        var record = EntitlementRecord(productID: sku)
        record.apply(.entitled(id: 1, at: t0))
        record.apply(.revoked(id: 1, at: later(60)))
        #expect(!record.isEntitled)
    }

    @Test("buying again after a refund re-opens it, because the later verification wins")
    func rePurchaseAfterRefund() {
        var record = EntitlementRecord(productID: sku)
        record.apply(.entitled(id: 1, at: t0))
        record.apply(.revoked(id: 1, at: later(60)))
        #expect(!record.isEntitled)
        record.apply(.entitled(id: 1, at: later(120)))
        #expect(record.isEntitled, "a customer who paid twice must not be locked out by the first refund")
    }

    @Test("a revocation older than the verification it arrives after does not reopen the question")
    func staleRevocationIsIgnored() {
        var record = EntitlementRecord(productID: sku)
        record.apply(.entitled(id: 1, at: later(120)))
        record.apply(.revoked(id: 1, at: t0))       // an old refund replayed by Transaction.updates
        #expect(record.isEntitled)
    }

    @Test("verification is monotonic, so an out-of-order replay cannot undo a later revocation")
    func verificationIsMonotonic() {
        var record = EntitlementRecord(productID: sku)
        record.apply(.entitled(id: 1, at: later(120)))
        record.apply(.revoked(id: 1, at: later(180)))
        #expect(!record.isEntitled)
        // StoreKit replays old transactions on relaunch. If this walked `lastVerifiedAt`
        // backwards it would still be < revokedAt, but the record would then be lying about when
        // it was last verified — and the next comparison after a second refund would be wrong.
        record.apply(.entitled(id: 1, at: t0))
        #expect(record.lastVerifiedAt == later(120))
        #expect(!record.isEntitled)
    }

    @Test("revocation is monotonic too")
    func revocationIsMonotonic() {
        var record = EntitlementRecord(productID: sku)
        record.apply(.revoked(id: 1, at: later(60)))
        record.apply(.revoked(id: 1, at: t0))
        #expect(record.revokedAt == later(60))
    }

    @Test("apply reports whether anything moved, and silence never moves anything")
    func changeReporting() {
        var record = EntitlementRecord(productID: sku)
        #expect(record.apply(.silent) == false)
        #expect(record.apply(.entitled(id: 1, at: t0)) == true)
        #expect(record.apply(.entitled(id: 1, at: t0)) == false, "the same verification twice is not a change")
        #expect(record.apply(.silent) == false)
        #expect(record.apply(.revoked(id: 1, at: later(1))) == true)
    }

    // MARK: Whose refund is it

    @Test("a revocation of somebody else's transaction does not close this one")
    func revocationMustMatchTheVerification() {
        // Without the id match, every revocation is a global off-switch. A shared device where
        // two Apple Accounts have both owned the SKU, or a stale transaction replayed after an
        // account switch, would close an entitlement it has no authority over — revoking somebody
        // who paid and was never refunded, which is the one-star review this product cannot
        // absorb, arriving through the code that exists to prevent it.
        var record = EntitlementRecord(productID: sku)
        record.apply(.entitled(id: 111, at: t0))
        record.apply(.revoked(id: 222, at: later(60)))
        #expect(record.isEntitled, "another account's refund closed this device's purchase")
        #expect(record.revokedAt == nil, "the unmatched revocation was recorded as if it applied")

        // …and the matching one still closes it, so the guard is not simply "never revoke".
        record.apply(.revoked(id: 111, at: later(120)))
        #expect(!record.isEntitled)
    }

    @Test("switching to an account that also owns it re-points the id, so ITS refund lands")
    func theStoredIDFollowsTheLatestVerification() {
        // Last-writer-wins on the id, deliberately. Pinning the first id ever seen looks safer
        // and is not: it makes the second account's refund unmatchable, so the road stays open
        // for somebody who WAS refunded — and the code that dropped the revocation looks like it
        // handled it correctly, which is the worst version of a bug.
        var record = EntitlementRecord(productID: sku)
        record.apply(.entitled(id: 111, at: t0))
        record.apply(.entitled(id: 222, at: later(60)))
        #expect(record.verifiedTransactionID == 222)
        record.apply(.revoked(id: 222, at: later(120)))
        #expect(!record.isEntitled)
    }

    @Test("a record written before ids existed is still closable by a refund")
    func anAbsentIDDoesNotBlockARevocation() {
        // v1.30 may persist a record with no id. The asymmetry is chosen rather than inherited:
        // losing a purchase to an unmatched refund is recoverable — the customer re-buys, or
        // Restore heals it — while keeping a refunded purchase open is not recoverable at all,
        // and is the case Apple would be right to complain about.
        var record = EntitlementRecord(productID: sku, lastVerifiedAt: t0, revokedAt: nil,
                                       verifiedTransactionID: nil)
        #expect(record.isEntitled)
        record.apply(.revoked(id: 999, at: later(60)))
        #expect(!record.isEntitled)
    }

    // MARK: Persistence

    private func freshDefaults(_ name: String) throws -> UserDefaults {
        let suite = "EntitlementTests.\(name).\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("a verified entitlement survives a relaunch")
    func roundTrip() throws {
        let defaults = try freshDefaults("roundTrip")
        var ledger = EntitlementLedger(productID: sku)
        ledger.apply(.entitled(id: 1, at: t0), savingTo: defaults)

        let reloaded = EntitlementLedger.load(from: defaults, productID: sku)
        #expect(reloaded.isEntitled)
        #expect(reloaded.record.lastVerifiedAt == t0)
    }

    @Test("silence does not write to disk at all")
    func silenceIsInert() throws {
        let defaults = try freshDefaults("silenceIsInert")
        var ledger = EntitlementLedger(productID: sku)
        #expect(ledger.apply(.silent, savingTo: defaults) == false)
        #expect(defaults.data(forKey: EntitlementLedger.defaultsKey) == nil,
                "an offline launch touched storage; it should be completely inert")
    }

    @Test("a record stored for a different product is not adopted")
    func productIDIsNotInherited() throws {
        let defaults = try freshDefaults("productID")
        var other = EntitlementLedger(productID: "com.jasonye.nihongoride.something.else")
        other.apply(.entitled(id: 1, at: t0), savingTo: defaults)

        let ours = EntitlementLedger.load(from: defaults, productID: sku)
        #expect(!ours.isEntitled, "a second SKU inherited this one's verification")
    }

    @Test("unreadable storage fails toward never-established, not toward entitled")
    func corruptStorageFailsClosed() throws {
        let defaults = try freshDefaults("corrupt")
        defaults.set(Data("not json".utf8), forKey: EntitlementLedger.defaultsKey)
        let ledger = EntitlementLedger.load(from: defaults, productID: sku)
        #expect(!ledger.isEntitled)
        // Stated because the asymmetry looks like a contradiction of the failure rule and is not:
        // the rule forbids a FAILURE revoking a verification this device made. Storage that
        // cannot be parsed contains no verification to protect, and defaulting to entitled would
        // hand the road to anyone whose defaults were ever corrupt. The next successful store
        // read restores a real purchase within seconds.
        //
        // But the unreadable bytes are the only local evidence that a purchase happened, and the
        // next write destroys them — so they are copied aside first.
        #expect(defaults.data(forKey: EntitlementLedger.quarantineKey) == Data("not json".utf8),
                "the unreadable record was discarded instead of quarantined")

        // …and a SECOND bad load must not overwrite the first. The earliest blob is the one
        // closest to the purchase; a later one may just be this app having written over it.
        defaults.set(Data("also not json".utf8), forKey: EntitlementLedger.defaultsKey)
        _ = EntitlementLedger.load(from: defaults, productID: sku)
        #expect(defaults.data(forKey: EntitlementLedger.quarantineKey) == Data("not json".utf8))
    }

    @Test("the debug summary names its evidence, not just its answer")
    func debugSummaryCarriesEvidence() {
        var ledger = EntitlementLedger(productID: sku)
        #expect(ledger.debugSummary.contains("never verified"))
        ledger.apply(.entitled(id: 1, at: t0), savingTo: nil)
        #expect(ledger.debugSummary.contains("entitled"))
        #expect(!ledger.debugSummary.contains("never verified"))
    }

    // MARK: The module's own boundary

    @Test("this module cannot reach StoreKit, and cannot reach the network")
    func theModuleIsPure() throws {
        // Not style. MEASURED: under `swift test` the host process is SwiftPM's own binary, and
        // `Transaction.currentEntitlements` returns [] there SILENTLY — no throw, no diagnostic.
        // Every assertion above would still pass against real StoreKit while exercising nothing,
        // which is this project's most expensive failure mode. Purity is what makes them mean
        // something.
        //
        // The directory is enumerated rather than a filename hardcoded: a scan that names one
        // file lets the second file added escape it, which is the v1.25 "what a scan cannot see"
        // lesson. The count is asserted so an empty enumeration cannot report clean.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let dir = root.appendingPathComponent("Sources/EntitlementKit")
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasSuffix(".swift") }
        #expect(files.count >= 1, "the scan read no files — it cannot report clean")

        let forbidden = ["import StoreKit", "URLSession", "URLRequest", "import Network",
                         "CKContainer", "NSXPCConnection", "Process("]

        // Comments are stripped before scanning, and that is a real weakening of the check, so
        // it is stated rather than hidden: this module's whole doc comment is ABOUT StoreKit and
        // why it is absent, and a scanner that could not tell an explanation from an import would
        // have to be either disabled or lied to. Code is what is scanned; prose is not code.
        func code(_ source: String) -> String {
            source.split(separator: "\n", omittingEmptySubsequences: false)
                .map { line -> Substring in
                    guard let slashes = line.range(of: "//") else { return line }
                    return line[line.startIndex ..< slashes.lowerBound]
                }
                .joined(separator: "\n")
        }

        var scannedLines = 0
        for file in files {
            let source = try String(contentsOf: dir.appendingPathComponent(file), encoding: .utf8)
            let body = code(source)
            scannedLines += body.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
            for needle in forbidden {
                #expect(!body.contains(needle), "\(file) contains \(needle)")
            }
        }
        #expect(scannedLines > 40, "the scan saw \(scannedLines) lines of code — too few to have checked anything")

        // The negative control, run through the SAME stripper the real scan uses. Without it, a
        // stripper that returned "" would pass every assertion above while reading nothing —
        // which is the failure this project names most often, hiding inside the thing that exists
        // to prevent it.
        #expect(forbidden.contains { code("import StoreKit\n").contains($0) },
                "the stripper eats real code, so the scan above proves nothing")
        #expect(!forbidden.contains { code("// import StoreKit\n").contains($0) },
                "the stripper does not actually strip comments")
    }
}
