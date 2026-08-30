import Foundation

/// Whether a purchase is honoured, and — the part that matters — *why this device believes so*.
///
/// ## The one rule this module exists to enforce
///
/// > **Never revoke on failure what was previously verified.** Persist the last verified
/// > entitlement and honour it offline. Fail closed **only where entitlement was never
/// > established**, and reconcile refunds and revocations when connectivity returns.
///
/// ## Why the fix is a NAME rather than a branch
///
/// StoreKit cannot tell you the difference between the cases you must distinguish. An empty
/// `Transaction.currentEntitlements` comes back for a customer who never purchased, a customer
/// signed out of the App Store, a customer with no network, a customer mid-refund — and,
/// measured on this machine on 2026-08-30, **for a customer in the fraction of a second after a
/// successful purchase**, because `currentEntitlements` is not immediately consistent with
/// `purchase()`. Any code that maps "empty" onto "not entitled" has invented information it does
/// not have, and it reads as obviously correct, which is why it keeps shipping.
///
/// The house pattern ships that bug seven times over. Wearform's `refreshEntitlements()` ends
/// `isPro = active`, rebuilt from `currentEntitlements` on every call with nothing persisted, and
/// it runs immediately after `transaction.finish()` — so on the measured race it writes
/// `isPro = false` **the instant a customer pays**. That is HARD CONSTRAINT 2 failing in the
/// happy path, not the error path. Take the shape; never that method.
///
/// So the store adapter is given no vocabulary for the lie. It may say `entitled`, `revoked`, or
/// **`silent`** — and `silent` is honest about carrying no information at all. Once the type
/// cannot express "the store told me no", nothing downstream can act on it.
///
/// ## Deliberately no `import StoreKit`
///
/// Measured, not assumed: under `swift test` the host process is SwiftPM's own binary, so
/// `Product.products(for:)` and `AppTransaction.shared` throw `unknown` — **and
/// `Transaction.currentEntitlements` yields `[]` silently, with no error at all.** A headless
/// test asserting "not entitled when nothing was purchased" against real StoreKit would therefore
/// pass forever without exercising anything. This module is pure so its ~40 tests mean what they
/// say; the real StoreKit is proven separately, against a local StoreKit configuration, on macOS.
///
/// ## What is designed and what is observed
///
/// **Designed.** This app ships no telemetry and will not: at ~70 downloads a month none could
/// resolve a change. So if a paying customer ever loses access, nobody will find out. There is no
/// monitoring behind these rules — only the tests, and the fact that the type system refuses to
/// represent the mistake.
public enum StoreEntitlementSignal: Sendable, Equatable {

    /// The store returned a verified, unrevoked transaction for the product. Authoritative.
    case entitled(Date)

    /// The store returned a verified transaction carrying a revocation date — a refund, a family
    /// removal, or an Apple-side revocation. **The only signal permitted to close an entitlement.**
    ///
    /// Deliberately distinct from `silent`: a revocation is something the store *said*, and an
    /// empty result is something it did not say.
    case revoked(Date)

    /// The store said nothing about this product: no transaction, or an error, or a query that
    /// never completed.
    ///
    /// **Carries no information, and the ledger must never treat it as a verdict.** It is the
    /// state of a signed-out account, an offline launch, a failed product request, a StoreKit
    /// outage, the moments after a successful purchase, and a customer who genuinely never
    /// bought anything — indistinguishable from here, and pretending otherwise is the defect
    /// this module is built around.
    case silent
}

/// What this device believes about one product, and the evidence for it. Persisted; never sent.
public struct EntitlementRecord: Codable, Sendable, Equatable {

    /// The product this record is about.
    ///
    /// Stored rather than assumed so a future second SKU cannot inherit this one's verification
    /// by sharing its storage key — the ledger refuses to answer for a product it was not built
    /// for, instead of quietly answering for the wrong one.
    public let productID: String

    /// The last moment the store affirmatively verified this entitlement on this device.
    /// `nil` means it never has, and that is the only state that fails closed.
    public private(set) var lastVerifiedAt: Date?

    /// Set only by an affirmative `revoked` signal. Never by an absence.
    public private(set) var revokedAt: Date?

    public init(productID: String, lastVerifiedAt: Date? = nil, revokedAt: Date? = nil) {
        self.productID = productID
        self.lastVerifiedAt = lastVerifiedAt
        self.revokedAt = revokedAt
    }

    /// **The one predicate.** Nothing else may decide whether the purchase is honoured — not the
    /// offer row, not the scenery, not the counter. Twenty-two of this project's defects are the
    /// shape *the number shown and the run produced are computed by different predicates*, and
    /// the durable fix every time was to leave the two sides no way to disagree.
    ///
    /// A re-purchase after a refund verifies again, and the later verification wins; that is why
    /// this compares dates rather than treating `revokedAt` as a tombstone.
    public var isEntitled: Bool {
        guard let verified = lastVerifiedAt else { return false }
        guard let revoked = revokedAt else { return true }
        return verified > revoked
    }

    /// Applies a store signal. Returns whether anything changed, so a caller can persist only
    /// when there is something to persist.
    @discardableResult
    public mutating func apply(_ signal: StoreEntitlementSignal) -> Bool {
        let before = self
        switch signal {
        case .entitled(let at):
            // Monotonic. StoreKit delivers updates out of order (a relaunch replaying an old
            // transaction, `Transaction.updates` racing a manual refresh), and a verification
            // that walked backwards would let a stale delivery undo a later revocation.
            if lastVerifiedAt.map({ at > $0 }) ?? true { lastVerifiedAt = at }
        case .revoked(let at):
            if revokedAt.map({ at > $0 }) ?? true { revokedAt = at }
        case .silent:
            // Nothing, and the absence of code here is the module's entire point.
            //
            // Note there is no "else fail closed" branch to write: a record that was never
            // verified already answers `false`, so "fail closed only where entitlement was never
            // established" needs no statement to be true. It is the strongest form of a rule —
            // one that cannot be forgotten because there is nothing to forget.
            break
        }
        return self != before
    }
}

/// The record plus the small amount of bookkeeping the app needs around it.
///
/// Separate from `EntitlementRecord` so the rule above stays a pure value that a test can drive
/// through every branch without a filesystem, a defaults suite, or a clock.
public struct EntitlementLedger: Sendable, Equatable {

    /// Where the record lives. Local, on-device, never transmitted — the same shape as
    /// `StoreReviewKit.ReviewPromptLedger`, which §G of the product plan licenses with the
    /// distinction the first draft got wrong: *Data Not Collected forbids collecting, not
    /// counting.*
    public static let defaultsKey = "NihongoRide.entitlement.v1"

    public private(set) var record: EntitlementRecord

    public init(record: EntitlementRecord) { self.record = record }

    public init(productID: String) { self.record = EntitlementRecord(productID: productID) }

    /// The one predicate, forwarded. See `EntitlementRecord.isEntitled`.
    public var isEntitled: Bool { record.isEntitled }

    /// Apply a signal and persist it **in one branch**.
    ///
    /// The shape is `ReviewPromptLedger.requestIfEarned`'s, and for the same reason: the two
    /// sides that must never disagree are *"the stored record"* and *"the record this process is
    /// answering from"*, so the mutation and the save sit on one line of control flow. Do not
    /// refactor this into an `apply` that returns and a caller that saves — that is the shape of
    /// every defect this project keeps finding.
    ///
    /// Saves only on a change, which also means a `silent` signal never touches the disk. An
    /// offline launch is therefore not merely honoured, it is inert.
    @discardableResult
    public mutating func apply(_ signal: StoreEntitlementSignal,
                               savingTo defaults: UserDefaults?,
                               key: String = defaultsKey) -> Bool {
        let changed = record.apply(signal)
        if changed, let defaults { save(to: defaults, key: key) }
        return changed
    }

    // MARK: - Persistence

    /// Loads the stored record, or a never-established one.
    ///
    /// **Fails toward "never established", not toward "entitled"** — and that asymmetry is
    /// deliberate in the one direction it can be. Unreadable storage on a device that HAS bought
    /// the product costs that customer their purchase until the next successful store read, which
    /// then restores it; the alternative, defaulting to entitled, would hand the road to everyone
    /// whose defaults were ever corrupt. The failure rule protects a *verified* entitlement from
    /// being revoked by a failure; it does not license inventing one that was never recorded.
    ///
    /// A record stored under a different `productID` is discarded rather than adopted: a second
    /// SKU must never inherit this one's verification.
    public static func load(from defaults: UserDefaults,
                            productID: String,
                            key: String = defaultsKey) -> EntitlementLedger {
        guard let data = defaults.data(forKey: key),
              let record = try? JSONDecoder().decode(EntitlementRecord.self, from: data),
              record.productID == productID
        else { return EntitlementLedger(productID: productID) }
        return EntitlementLedger(record: record)
    }

    public func save(to defaults: UserDefaults, key: String = defaultsKey) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        defaults.set(data, forKey: key)
    }

    /// A line the owner can read in a debug view. Local only, and it names its own evidence
    /// rather than just its answer, because "entitled" without "since when, and did anything
    /// revoke it" is not diagnosable.
    public var debugSummary: String {
        let verified = record.lastVerifiedAt.map { "verified \($0)" } ?? "never verified"
        let revoked = record.revokedAt.map { " · revoked \($0)" } ?? ""
        return "\(record.productID): \(record.isEntitled ? "entitled" : "not entitled") — \(verified)\(revoked)"
    }
}
