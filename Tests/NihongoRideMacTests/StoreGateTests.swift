import XCTest
import StoreKit
import StoreKitTest
import EntitlementKit
// The app target's PRODUCT_NAME is "Nihongo Ride", so Xcode derives its Swift module name by
// c99-identifier-escaping that: `Nihongo_Ride`. Written here rather than renaming the product,
// because PRODUCT_NAME is what users see in the Dock and in About, and changing a shipping
// target's build settings to make a test compile is the wrong direction of accommodation.
@testable import Nihongo_Ride

/// The purchase gates, proven against a real StoreKit, on macOS.
///
/// ## Why macOS, when the product's larger platform is iOS
///
/// Measured 2026-08-30 on Xcode 26.6 with the iOS 26.5 simulator runtime, on an independent
/// minimal project so the finding does not depend on this repo: a local `.storekit` configuration
/// **never reaches the app on iOS** under `xcodebuild test`, under every wiring available —
/// `Product.products(for:)` returns 0 with the scheme reference, with a hand-added TestAction
/// reference, with an `.xctestplan` `storeKitConfigurationFileReference`, unsigned, ad-hoc signed,
/// and on two different simulator devices. `SKTestSession` logs `SKInternalErrorDomain Code=3` for
/// every operation.
///
/// **And its initialiser does not throw.** It logs and returns a live, inert object, so the
/// obvious gate test — construct a session, assert no error — passes forever while proving
/// nothing. That is this project's defining failure mode, shipped by Apple's own test framework.
///
/// The same configuration and the same code pass on macOS. So the gates live here, and
/// `test00_theStoreIsReachable` below is what makes the rest of this file mean anything: it fails
/// on iOS and passes on macOS, which is a known negative and a known positive, today, on this
/// machine.
///
/// ## What this file does NOT cover, stated so nobody reads the green as more than it is
///
/// * **iOS StoreKit behaviour is not observed by any automated test on this machine.** The two
///   targets share `Sources/NihongoRideApp`, so the adapter under test is the same code — but
///   that is an argument, not an observation. Accepted gap, written down.
/// * No App Store account signed in, Family Sharing, and a real cross-platform restore cannot be
///   automated anywhere here. They are manual, and PLAN-STAGE1 carries the procedure and the date
///   they were last walked. A gate listed as "tested" because this file is green would be a lie.
///
/// ## Hygiene that is not optional
///
/// `SKTestSession` settings **persist across processes and across runs** — `askToBuyEnabled` set
/// by one test leaked into later, separate `xcodebuild` invocations and made purchases throw
/// "unknown". Without `resetToDefaultState()` at the top of every test, results depend on what ran
/// before them, possibly in a previous session, which is the worst kind of flake because it is
/// invisible in the failing run's own log.
///
/// And purchases go through `Product.purchase()`, never `session.buyProduct(identifier:)` — the
/// latter throws "unknown" here where the former succeeds, and the app's real path is the one
/// worth testing anyway.
final class StoreGateTests: XCTestCase {

    private static let productID = "com.jasonye.nihongoride.scenery.lifetime"
    private var session: SKTestSession!

    override func setUp() async throws {
        try await super.setUp()
        session = try SKTestSession(configurationFileNamed: "NihongoRide")
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        session.askToBuyEnabled = false
        session.interruptedPurchasesEnabled = false

        // ⚠️ EVERY gate below skips — loudly — if the session cannot actually control the store.
        //
        // `SKTestSession.init` does not throw when it fails. On this machine, for THIS app, it
        // logs `SKInternalErrorDomain Code=3` for every operation and hands back a live object
        // that no-ops. Products still resolve, because the scheme's storeKitConfiguration arms the
        // app's store environment independently — so without this check the whole file passes
        // while every simulated refund, network error and Ask-to-Buy in it does nothing.
        //
        // A green suite that proves nothing is worse than no suite. It is also worse than a red
        // one, because a permanently-red test trains people to ignore red. So the gates SKIP with
        // the reason attached, `run_store_gates.sh` prints a banner, and PLAN-STAGE1 §L lists the
        // paths as MANUAL until this stops firing. The moment a toolchain update fixes the
        // session, they start running again with no edit.
        //
        // The one thing that must never happen here is weakening the check to make the suite
        // green. That is the exact failure this project spends the most effort avoiding.
        let inert = await Self.sessionIsInert(session)
        try XCTSkipIf(inert,
                      """
                      SKTestSession is INERT for this app on this machine (SKInternalErrorDomain \
                      Code=3). Products resolve but nothing can be simulated, so these gates \
                      would prove nothing. They are recorded as MANUAL in PLAN-STAGE1 §L. \
                      Re-check on a toolchain update; a minimal non-App-Store macOS app on this \
                      same machine drives the session fine, so the difference is this app, not \
                      the tooling.
                      """)
    }

    /// Does the session actually control the store? Measured, by making it do something.
    ///
    /// "Products resolve" and "the session controls the store" are two different claims, and the
    /// first was being used as evidence for the second until a run caught it.
    private static func sessionIsInert(_ session: SKTestSession) async -> Bool {
        do {
            try await session.setSimulatedError(
                .generic(.networkError(URLError(.notConnectedToInternet))), forAPI: .loadProducts)
            defer { Task { try? await session.setSimulatedError(nil, forAPI: .loadProducts) } }
            let stillWorks = try await !Product.products(for: [productID]).isEmpty
            return stillWorks          // the simulated error changed nothing ⇒ inert
        } catch {
            return false               // it threw, which means it took effect
        }
    }

    override func tearDown() async throws {
        session?.clearTransactions()
        session = nil
        try await super.tearDown()
    }

    // MARK: The calibration that makes every other test in this file mean something

    func test00_theStoreIsReachable() async throws {
        // Without this, every assertion below is indistinguishable from one made against a store
        // that answers nothing.
        let products = try await Product.products(for: [Self.productID])
        XCTAssertEqual(products.count, 1, "the local StoreKit configuration did not reach the app")
        XCTAssertFalse(try XCTUnwrap(products.first).displayPrice.isEmpty)
    }

    // MARK: GATE (a) — offline

    func test01_offlineProductLoadDoesNotRevokeAnEntitlement() async throws {
        var record = EntitlementRecord(productID: Self.productID)
        record.apply(await readStore())
        try await buy()
        record.apply(await readStore())
        XCTAssertTrue(record.isEntitled, "a clean purchase did not verify")

        // The offline gate, driven by StoreKit's own simulated error rather than by unplugging
        // anything: this is exactly what a rider on a plane hits.
        try await session.setSimulatedError(.generic(.networkError(URLError(.notConnectedToInternet))),
                                            forAPI: .loadProducts)
        let products = try? await Product.products(for: [Self.productID])
        XCTAssertTrue(products?.isEmpty ?? true, "the simulated network error did not take effect")

        record.apply(await readStore())
        XCTAssertTrue(record.isEntitled, "an offline launch revoked a purchase — the whole point")
        try await session.setSimulatedError(nil, forAPI: .loadProducts)
    }

    func test02_offlinePurchaseFailsWithoutDamagingAnything() async throws {
        var record = EntitlementRecord(productID: Self.productID)
        try await session.setSimulatedError(.generic(.networkError(URLError(.notConnectedToInternet))),
                                            forAPI: .purchase)
        let products = try await Product.products(for: [Self.productID])
        let product = try XCTUnwrap(products.first)
        do {
            _ = try await product.purchase()
            XCTFail("the simulated purchase error did not take effect")
        } catch {
            // Expected. The assertion that matters is the next one.
        }
        record.apply(await readStore())
        XCTAssertFalse(record.isEntitled, "a failed purchase granted an entitlement")
        try await session.setSimulatedError(nil, forAPI: .purchase)
    }

    // MARK: GATE (c) — restore

    func test03_restoreBringsBackAPurchaseOnAFreshRecord() async throws {
        try await buy()
        // A fresh record is what a reinstall or a second device looks like: the store owns the
        // transaction, this device has never recorded anything.
        var record = EntitlementRecord(productID: Self.productID)
        XCTAssertFalse(record.isEntitled)
        try? await AppStore.sync()
        record.apply(await settled())
        XCTAssertTrue(record.isEntitled, "Restore did not recover a purchase this account owns")
    }

    // MARK: The rest of §C's list, while the harness is open

    func test04_refundRevokesAndIsFoundWithoutTransactionUpdates() async throws {
        var record = EntitlementRecord(productID: Self.productID)
        try await buy()
        record.apply(await settled())
        XCTAssertTrue(record.isEntitled)

        let transaction = try XCTUnwrap(session.allTransactions().first)
        try await session.refundTransaction(identifier: UInt(transaction.identifier))

        // Deliberately NOT via `Transaction.updates`. A revocation issued while the app is not
        // running is never redelivered for a finished transaction, so the reconciliation path has
        // to find it by asking — and `currentEntitlements` cannot answer, because Apple documents
        // it as excluding refunded non-consumables. This asserts the path that works in
        // production, not the one the test harness makes easy.
        record.apply(await readStore())
        XCTAssertFalse(record.isEntitled, "a refunded purchase kept the road")
    }

    func test05_askToBuyPendsThenGrantsOnApproval() async throws {
        session.askToBuyEnabled = true
        var record = EntitlementRecord(productID: Self.productID)
        let products = try await Product.products(for: [Self.productID])
        let result = try await XCTUnwrap(products.first).purchase()
        guard case .pending = result else {
            return XCTFail("Ask to Buy did not defer the purchase: \(result)")
        }
        record.apply(await readStore())
        XCTAssertFalse(record.isEntitled, "a pending purchase granted the road before approval")

        let pending = try XCTUnwrap(session.allTransactions().first)
        try await session.approveAskToBuyTransaction(identifier: UInt(pending.identifier))
        record.apply(await settled())
        XCTAssertTrue(record.isEntitled, "an approved Ask to Buy never opened the road")
    }

    func test06_aStorefrontChangeDoesNotTakeThePurchaseAway() async throws {
        var record = EntitlementRecord(productID: Self.productID)
        try await buy()
        record.apply(await settled())
        XCTAssertTrue(record.isEntitled)
        session.storefront = "JPN"
        record.apply(await readStore())
        XCTAssertTrue(record.isEntitled, "changing storefront revoked a purchase")
    }

    func test07_anUnknownProductComesBackEmptyRatherThanThrowing() async throws {
        // The case that needs `hasLoaded`: `Product.products(for:)` returns what it could resolve
        // and silently drops the rest, so "the store had none of our ids" arrives as an EMPTY
        // ARRAY, not an error. Without a separate loaded flag the offer row spins forever here.
        let products = try await Product.products(for: ["com.jasonye.nihongoride.does.not.exist"])
        XCTAssertTrue(products.isEmpty)
    }

    func test08_neverPurchasedIsNotEntitled() async throws {
        // The negative control for every test above. If this passed while the store was inert it
        // would prove nothing — which is why test00 exists.
        var record = EntitlementRecord(productID: Self.productID)
        record.apply(await readStore())
        XCTAssertFalse(record.isEntitled)
    }

    // MARK: Helpers

    private func buy() async throws {
        let products = try await Product.products(for: [Self.productID])
        let result = try await XCTUnwrap(products.first).purchase()
        guard case .success(.verified(let transaction)) = result else {
            return XCTFail("purchase did not verify: \(result)")
        }
        await transaction.finish()
    }

    /// The app's own store translation. Duplicating it here would be the "one rule written twice"
    /// trap, so this calls the shipping one.
    private func readStore() async -> StoreEntitlementSignal {
        await RouteStore.readStore()
    }

    /// Poll until the store settles, or give up.
    ///
    /// MEASURED, not defensive: `Transaction.currentEntitlements` is not immediately consistent
    /// with `purchase()` returning — one probe run recorded `outcome=success entitlements=[]` on a
    /// clean buy — and `AppStore.sync()` was flaky the same way (1 failure in ~4 full-suite runs,
    /// 4/4 in isolation with retries). A gate that flakes gets disabled, and a disabled gate is a
    /// missing gate.
    private func settled(within seconds: TimeInterval = 3) async -> StoreEntitlementSignal {
        let deadline = Date().addingTimeInterval(seconds)
        var last = StoreEntitlementSignal.silent
        repeat {
            last = await readStore()
            if case .entitled = last { return last }
            try? await Task.sleep(for: .milliseconds(120))
        } while Date() < deadline
        return last
    }
}
