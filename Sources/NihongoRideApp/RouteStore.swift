import Foundation
import StoreKit
import Observation
import EntitlementKit

/// The one-time purchase that opens the road west, and everything StoreKit needs to say about it.
///
/// ## The division of labour, and why it is this one
///
/// The RULE — what happens to an entitlement when the store answers, fails, or says nothing — is
/// not here. It lives in `EntitlementKit`, which has no `import StoreKit` at all, because under
/// `swift test` the host process is SwiftPM's own binary and `Transaction.currentEntitlements`
/// returns `[]` **silently, with no error**. A headless test of the rule written against real
/// StoreKit would pass forever while exercising nothing. So the rule is pure and exhaustively
/// tested; this file is the adapter, and it is proven separately on macOS against a local
/// StoreKit configuration (`Tests/NihongoRideMacTests`).
///
/// ## What this file must never do
///
/// Translate an empty answer into "not entitled". `Transaction.currentEntitlements` comes back
/// empty for a customer who never bought, one who is signed out, one with no network, one
/// mid-refund — and, measured on 2026-08-30, **for a moment after a successful purchase**, because
/// it is not immediately consistent with `purchase()`. The house pattern (`Wearform`'s
/// `StoreManager.refreshEntitlements`, seven apps) ends `isPro = active` rebuilt from that list on
/// every call, so on that race it writes `false` the instant a customer pays. Its shape is worth
/// copying — the split between loading products and resolving entitlements, and the
/// `Transaction.updates` finisher. Its conclusion is not.
///
/// Everything this file learns is expressed as a `StoreEntitlementSignal`, whose vocabulary is
/// `entitled` / `revoked` / `silent`. There is deliberately no case meaning "the store says no".
///
/// ## Timestamps
///
/// Both `entitled` and `revoked` are stamped with **now — the moment of observation** — rather
/// than with Apple's own dates. They are observations, and the ledger resolves conflicts by
/// taking the more recent one. Stamping a revocation with Apple's `revocationDate` would put it
/// in the past, where a stale cached verification could outrank it forever and leave a refunded
/// customer entitled: measured on paper before it was written, not after it shipped.
@MainActor
@Observable
final class RouteStore {

    /// The product id, which is permanent: Apple never lets it be edited, and never lets it be
    /// reused for another product in this app even after the original is deleted.
    ///
    /// Named `scenery` rather than the house `<bundle>.pro.lifetime` because §C of the product
    /// plan requires the capability set to be named before the SKU exists, and `pro` names
    /// nothing. What this buys is **scenery and routes — every route and every backdrop, now and
    /// in future — and nothing else.** Anything needing a server, custom material import, or a
    /// content pack is outside it and sells separately. That boundary is in the identifier
    /// itself, so a future Pro tier cannot inherit a promise this SKU never made.
    nonisolated static let productID = "com.jasonye.nihongoride.scenery.lifetime"

    /// What the app is allowed to show. The one predicate; see `EntitlementRecord.isEntitled`.
    private(set) var ledger: EntitlementLedger

    /// Forwarded so no caller ever reaches past this type into the ledger's internals — and so
    /// there is exactly one spelling of the question in the whole app.
    var isEntitled: Bool { ledger.isEntitled }

    /// The product, once the App Store has answered. `nil` is not "unavailable" — see `hasLoaded`.
    private(set) var product: Product?

    /// True once a load has finished, success or failure. Separates "prices have not arrived yet"
    /// from "the App Store answered and had none of our ids": `Product.products(for:)` returns
    /// what it could resolve and silently drops the rest, so an all-miss arrives as an empty
    /// array rather than an error. Without this the row spins forever on that case.
    private(set) var hasLoaded = false
    private(set) var isLoading = false
    /// Set when the request THREW, cleared when it succeeds. A failed request and a request that
    /// succeeded with none of our ids are two different stories for the customer.
    private(set) var loadError: String?

    /// A purchase outcome worth surfacing. `.userCancelled` maps to nothing — the customer closed
    /// Apple's own sheet and knows what they did.
    enum Notice: Equatable {
        case pending          // Ask to Buy / SCA — may complete later via Transaction.updates
        case unverified       // StoreKit could not verify it; nothing was opened
        case failed(String)
        case productMissing   // tapped before the product loaded; the row disables to prevent this
    }
    var notice: Notice?
    private(set) var isPurchasing = false

    /// What StoreKit answered on the last `purchase()`, in the counter's vocabulary.
    ///
    /// Set on **every** branch of `purchase()`, including the ones that set no `notice` — a
    /// cancel is a real outcome and a silent one, and a ledger that recorded only the noisy
    /// branches would report "nobody tried" for a device where somebody tried and backed out.
    /// That is the difference the whole experiment turns on.
    private(set) var lastOutcome: UnlockOfferEvent = .purchaseUnrecognised

    private let defaults: UserDefaults?
    private var updates: Task<Void, Never>?

    /// - Parameter defaults: where the verified entitlement is persisted. `nil` in capture and
    ///   UI-test runs, which must never write to the owner's real storage — the same rule
    ///   `AppModel`'s stores follow, and the one v1.24 learned the expensive way when a test
    ///   target stamped fourteen days of zeros onto the owner's real home-screen widget.
    init(defaults: UserDefaults?) {
        self.defaults = defaults
        self.ledger = defaults.map { EntitlementLedger.load(from: $0, productID: Self.productID) }
            ?? EntitlementLedger(productID: Self.productID)

        #if DEBUG
        // The UI-test seam. iOS StoreKit testing is measurably dead on this toolchain (a local
        // .storekit configuration never reaches the app; `Product.products` returns 0 under every
        // wiring tried), so the iOS UI tests assert PLACEMENT — one row, in one place, absent
        // when owned — against a faked entitlement and never touch StoreKit.
        //
        // ⚠️ Two things keep this from becoming a free unlock. It is inside `#if DEBUG`, and
        // `EntitlementSeamTests` reads this file to prove that. And it requires the value to be
        // spelled exactly, so an unset or misspelled variable leaves the real ledger alone rather
        // than defaulting to entitled — a seam that faked EVERY launch would satisfy a naive test.
        if let fake = ProcessInfo.processInfo.environment["NIHONGO_FAKE_ENTITLEMENT"] {
            switch fake {
            case "verified": ledger.apply(.entitled(id: 1, at: Date()), savingTo: nil)
            case "revoked":
                ledger.apply(.entitled(id: 1, at: Date(timeIntervalSince1970: 0)), savingTo: nil)
                ledger.apply(.revoked(id: 1, at: Date()), savingTo: nil)
            default: break          // including "neverEstablished": the fresh ledger already is
            }
            return                  // never start StoreKit under a faked entitlement
        }
        #endif

        guard Self.storeIsReachable else { return }
        updates = observeTransactionUpdates()
        // Two tasks, not one after the other. Entitlements come from `currentEntitlements` and
        // need no product at all, so sequencing them behind the product request would leave
        // somebody who has already PAID looking at a locked road while a slow App Store lookup
        // finished. Nothing the two touch overlaps.
        Task { await load() }
        Task { await refresh() }
    }

    /// Whether to talk to StoreKit at all.
    ///
    /// Not `Bundle.main.bundleIdentifier != nil` — STATE records why that is not "this is the
    /// app": under XCTest hosting it is `com.apple.dt.xctest.tool`. What actually must be
    /// excluded is the headless screenshot renderer, which has no store, no UI and no business
    /// making network calls.
    static var storeIsReachable: Bool { !Screenshotter.isCapturing }

    // MARK: - Products

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false; hasLoaded = true }
        do {
            product = try await Product.products(for: [Self.productID]).first
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    // MARK: - Entitlement

    /// Ask the store what it knows, and hand the answer — including "nothing" — to the ledger.
    func refresh() async {
        ledger.apply(await Self.readStore(), savingTo: defaults)
        // An approved Ask to Buy is completed BY the entitlement arriving; the notice must not
        // keep saying "awaiting approval" after the road has opened.
        if ledger.isEntitled, notice == .pending { notice = nil }
    }

    /// The whole of this app's knowledge of the App Store, reduced to three cases.
    ///
    /// `nonisolated` and static so it is a pure translation with nothing to observe: the only
    /// thing it may produce is a signal, and it cannot decide anything about it.
    nonisolated static func readStore() async -> StoreEntitlementSignal {
        // 1. Does the customer own it right now? `currentEntitlements` is documented as "all
        //    currently-subscribed transactions, and all purchased (and NOT REFUNDED)
        //    non-consumables", so a hit here is unambiguous.
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == productID,
                  transaction.revocationDate == nil
            else { continue }
            return .entitled(id: transaction.originalID, at: Date())
        }
        // 2. Nothing owned. That is NOT "never bought" — so before concluding anything, look for
        //    the one thing that IS conclusive: a transaction Apple has revoked.
        //
        //    ⚠️ This CANNOT be found through `currentEntitlements`, and reading the refund case
        //    out of that sequence is the mistake to avoid: the SDK's own doc comment says it
        //    excludes refunded non-consumables, so the branch would never execute and a refunded
        //    customer would keep the road forever while the code looked like it handled refunds.
        //    `Transaction.updates` is not a substitute either — it guarantees redelivery only for
        //    UNFINISHED transactions, and this app finishes every purchase immediately, so a
        //    revocation issued while the app was not running is never redelivered.
        //
        //    `latest(for:)` is the channel that works: "the user's latest transaction for a
        //    product… nil if the user has never purchased this product" — so it still returns the
        //    transaction after a refund, which is exactly the case being looked for.
        if case .verified(let transaction)? = await Transaction.latest(for: productID),
           transaction.revocationDate != nil {
            return .revoked(id: transaction.originalID, at: Date())
        }
        // 3. The store said nothing. Offline, signed out, never purchased, mid-refund, or the
        //    measured moment after a successful purchase — indistinguishable, and therefore
        //    reported as carrying no information rather than as a verdict.
        return .silent
    }

    // MARK: - Buying

    func purchase() async {
        guard let product else {
            notice = .productMissing
            lastOutcome = .offerUnavailable
            return
        }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    await settleEntitlement()
                    lastOutcome = .purchaseSucceeded
                case .unverified:
                    // The customer paid a sheet and StoreKit could not vouch for the result. Do
                    // not open the road; do say what state they are in.
                    notice = .unverified
                    lastOutcome = .purchaseUnverified
                }
            case .pending:
                notice = .pending
                lastOutcome = .purchasePending
            case .userCancelled:
                // No notice: the customer closed Apple's own sheet and knows what they did. It is
                // still recorded — an attempt that was backed out of is the single most
                // informative thing this experiment can observe short of a sale.
                lastOutcome = .purchaseCancelled
            @unknown default:
                notice = .failed(String(localized: "The purchase ended in an unexpected state. If you were charged, use Restore."))
                lastOutcome = .purchaseUnrecognised
            }
        } catch {
            notice = .failed(error.localizedDescription)
            lastOutcome = .purchaseFailed
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await settleEntitlement()
    }

    /// Refresh, then keep asking briefly if the answer was silence.
    ///
    /// MEASURED, not defensive: `Transaction.currentEntitlements` is not immediately consistent
    /// with `purchase()` returning, and a probe recorded `outcome=success entitlements=[]` on a
    /// clean buy. `AppStore.sync()` was flaky the same way. The failure rule means such a race
    /// can never *revoke* anything — but on a first purchase there is nothing to protect, so
    /// without this the customer pays and the road stays shut until they relaunch.
    ///
    /// Bounded, and it stops at the first success: silence after the deadline is left as silence
    /// rather than escalated, because `Transaction.updates` will deliver it later anyway.
    private func settleEntitlement(deadline: TimeInterval = 3) async {
        let stopAt = Date().addingTimeInterval(deadline)
        repeat {
            await refresh()
            if ledger.isEntitled { return }
            try? await Task.sleep(for: .milliseconds(120))
        } while Date() < stopAt
    }

    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task(priority: .background) { [weak self] in
            for await update in Transaction.updates {
                // Finish whatever arrives — an approved Ask to Buy, a revocation. An unfinished
                // transaction is redelivered on every launch forever.
                if case .verified(let transaction) = update { await transaction.finish() }
                await self?.refresh()
            }
        }
    }
}
