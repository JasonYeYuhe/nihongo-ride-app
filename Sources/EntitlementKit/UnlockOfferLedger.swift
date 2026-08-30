import Foundation

/// A local, never-transmitted count of what happened to the offer row on THIS device.
///
/// ## What it is for, stated honestly, because the honest version is smaller than it sounds
///
/// Stage 1's question is *will anyone pay this developer anything at all*, and its kill criterion
/// is any sustained purchasing. App Store Connect answers the numerator exactly — units, proceeds,
/// territory, refunds, per day, census-grade. What it can never answer is any denominator: Apple
/// sees transactions, not screens, and there is no per-device join at any traffic level.
///
/// So a zero has at least three incompatible readings — nobody is willing to pay; people are
/// willing but nobody has ridden far enough for this to be worth anything; nobody ever opened
/// Settings — and the remote instrument cannot separate them. This ledger can, on one device.
///
/// **And here is the limitation, written where it cannot be skipped rather than in a plan
/// somewhere:** it is never transmitted, so the only way it reaches the developer is a customer
/// choosing to send it. The one measured base rate for a customer of this app volunteering
/// anything is **one written review per 109 installs**, and composing a message is more effort
/// than tapping stars. Over a 90-day window the expected number of returned ledgers is under two
/// and plausibly zero. *This cannot estimate a rate, and nothing about it should ever be
/// described as though it could.*
///
/// What it CAN do is kill a universal from a single sample, and (a)/(b)/(c) above are stated as
/// universals. One returned ledger reading `settingsRowAppeared 0` over sixty launches refutes
/// "the placement works" on that device; one reading `settingsRowAppeared 12 · furthest 京都 ·
/// purchaseStarted 0` refutes "nobody who could use it ever saw it". n=1 cannot measure; n=1 can
/// falsify.
///
/// Its first and most reliable reader is the owner's own device, where its only job is to prove
/// the instrument fires at all — **because a ledger reporting zero and a ledger that was never
/// wired to the row are the same artifact until one of them has been made to move.**
///
/// ## What it must never record
///
/// Nothing identifiable, and — the one that needs saying — **no raw lifetime distance.** A rider's
/// exact odometer is close to a fingerprint of their whole history, and the entire design assumes
/// a customer may paste this into a message. The bucket is not a rounding of the raw figure for
/// tidiness; it is the reason the raw figure is unrepresentable here.
///
/// No dates, no storefront, no locale, no device id, no vocabulary, no scores, no free text.

/// Which stretch of the FREE Tōkaidō a device had reached.
///
/// **Frozen against the eight shipped thresholds, deliberately NOT derived from
/// `RideRoute.tokaidoStages.count`.** Stage 1 adds a second road; a bucket count that followed the
/// road would silently re-index counts already recorded, so a ledger written before the update and
/// one written after would use the same numbers to mean different stretches — and nothing would
/// say so. `UnlockOfferLedgerTests.bucketsMatchTheShippedRoad` asserts these thresholds still
/// equal the Tōkaidō's, so a change to the free road turns this red and forces the decision
/// instead of migrating the meaning quietly.
public enum RoadBucket: Int, Codable, Sendable, CaseIterable, Comparable {
    case nihonbashi = 0, kawasaki, hakone, fuji, hamanako, nagoya, suzuka, kyoto

    /// The v1.29 Tōkaidō thresholds, in metres. A literal copy, on purpose — see above.
    public static let thresholds: [Double] = [0, 400, 1_200, 2_500, 5_000, 9_000, 15_000, 25_000]

    /// NaN lands at the first bucket, mirroring `RideRoute.stage(forLifetimeMetres:in:)` rather
    /// than inventing a different answer for a corrupt odometer than the scene gives it.
    public static func forLifetimeMetres(_ metres: Double) -> RoadBucket {
        guard !metres.isNaN else { return .nihonbashi }
        var current = RoadBucket.nihonbashi
        for bucket in RoadBucket.allCases where metres >= thresholds[bucket.rawValue] {
            current = bucket
        }
        return current
    }

    public static func < (a: RoadBucket, b: RoadBucket) -> Bool { a.rawValue < b.rawValue }
}

/// Every outcome of a row that appeared, or a purchase that was attempted.
///
/// Each case names something this app or StoreKit **actually reports back**. Nothing here is named
/// as though it measured a person: `onAppear` fires when a row enters the view hierarchy, which is
/// an upper bound on anybody looking at it, so the case is `settingsRowAppeared` and not
/// `settingsRowSeen`. And a customer who did not tap did not *decline* — there is no case for
/// refusal, because refusal is not observable. `purchaseCancelled` is permitted only because
/// StoreKit itself reports `.userCancelled`.
///
/// `UnlockOfferLedgerTests.namesClaimOnlyWhatIsObservable` reads this file and fails the build if
/// that discipline slips, exactly as `ReviewPromptNamingTests` already does for the review prompt.
public enum UnlockOfferEvent: String, Codable, Sendable, CaseIterable {
    /// The Settings ROW entered the view hierarchy. The entrance, not the offer — and the two are
    /// a screen apart, so they are counted apart. An upper bound on viewings, never a count.
    case settingsRowAppeared
    /// The OFFER ITSELF rendered, with a price, on the road screen. This is the event that means
    /// somebody was actually in a position to buy: the first version of this counter recorded only
    /// the Settings row and then read it as if it meant this, which is two different predicates
    /// answering one question — the shape this project has shipped twenty-two times.
    case offerAppeared
    /// The offer rendered and the product had not loaded — nothing was actually for sale.
    case offerUnavailable
    /// The road screen was opened on a device that already owns it.
    case alreadyOwned
    /// This app called `Product.purchase()`.
    case purchaseStarted
    case purchaseSucceeded
    /// `.success(.unverified)` — a success this app refused to trust.
    case purchaseUnverified
    /// `.userCancelled`. Apple's own word for it, and the only refusal that is observable.
    case purchaseCancelled
    /// `.pending` — Ask to Buy, or a bank step.
    case purchasePending
    /// `purchase()` threw.
    case purchaseFailed
    /// `@unknown default`. A future StoreKit case is COUNTED, never dropped — the same rule
    /// `sales_report.py` applies to product-type codes it does not recognise.
    case purchaseUnrecognised
    case restoreStarted
    /// A UI test, or a headless screenshot render. Never a person.
    case suppressed
}

/// The counts. One device, never transmitted.
public struct UnlockOfferLedger: Codable, Sendable, Equatable {

    public static let defaultsKey = "NihongoRide.unlockOffer.v1"
    public static var bucketCount: Int { RoadBucket.allCases.count }

    /// `event.rawValue` → counts indexed by `RoadBucket.rawValue`.
    ///
    /// Invariant: every array is exactly `bucketCount` long. Decoding **pads a short array and
    /// never truncates a long one** — an install that skipped a version, or one downgraded, must
    /// lose nothing. That is HARD CONSTRAINT 1 in the one place a counter can violate it.
    public private(set) var counts: [String: [Int]]

    /// The denominator without which `settingsRowAppeared == 0` says nothing at all: "the row
    /// never appeared" across one launch and across sixty are different facts.
    public private(set) var launches: Int

    /// The furthest stretch this device ever reached, whether or not the row ever appeared.
    /// **This is what separates "nobody would pay" from "nobody had a use for it yet"** on a
    /// device whose owner never opened Settings.
    public private(set) var furthestBucket: RoadBucket

    public init(counts: [String: [Int]] = [:], launches: Int = 0,
                furthestBucket: RoadBucket = .nihonbashi) {
        self.counts = counts
        self.launches = launches
        self.furthestBucket = furthestBucket
    }

    // MARK: Reading

    public func count(of event: UnlockOfferEvent) -> Int {
        (counts[event.rawValue] ?? []).reduce(0, +)
    }

    public func count(of event: UnlockOfferEvent, in bucket: RoadBucket) -> Int {
        let row = counts[event.rawValue] ?? []
        return bucket.rawValue < row.count ? row[bucket.rawValue] : 0
    }

    // MARK: Writing

    private mutating func record(_ event: UnlockOfferEvent, at bucket: RoadBucket) {
        var row = counts[event.rawValue] ?? Array(repeating: 0, count: Self.bucketCount)
        if row.count < Self.bucketCount { row += Array(repeating: 0, count: Self.bucketCount - row.count) }
        row[bucket.rawValue] += 1
        counts[event.rawValue] = row
    }

    /// A launch happened, and this is how far the device has ridden. Bumps the furthest mark.
    public mutating func launched(lifetimeMetres: Double) {
        launches += 1
        furthestBucket = max(furthestBucket, RoadBucket.forLifetimeMetres(lifetimeMetres))
    }

    /// The offer row appeared — and what it was actually able to offer.
    ///
    /// One call, one branch: the state of the offer and the fact of its appearing are recorded
    /// together, so a row cannot appear without the ledger knowing which of the three things it
    /// was. Deciding elsewhere and recording here is the shape of every count-versus-run defect
    /// this project has found.
    @discardableResult
    public mutating func rowAppeared(lifetimeMetres: Double, suppressed: Bool) -> UnlockOfferEvent {
        let bucket = RoadBucket.forLifetimeMetres(lifetimeMetres)
        furthestBucket = max(furthestBucket, bucket)
        let event: UnlockOfferEvent = suppressed ? .suppressed : .settingsRowAppeared
        record(event, at: bucket)
        return event
    }

    /// The road screen rendered, and this is what it was actually able to show.
    ///
    /// Recorded HERE rather than at the Settings row, because the row is the entrance and the
    /// offer is a screen behind it — and at the row's `onAppear` the product has usually not
    /// loaded yet, so asking "was it for sale" there answers about the wrong moment.
    @discardableResult
    public mutating func offerAppeared(lifetimeMetres: Double,
                                       entitled: Bool,
                                       offerLoaded: Bool,
                                       suppressed: Bool) -> UnlockOfferEvent {
        let bucket = RoadBucket.forLifetimeMetres(lifetimeMetres)
        furthestBucket = max(furthestBucket, bucket)
        let event: UnlockOfferEvent = suppressed ? .suppressed
            : entitled ? .alreadyOwned
            : offerLoaded ? .offerAppeared
            : .offerUnavailable
        record(event, at: bucket)
        return event
    }

    /// Start a purchase and record its outcome **on one line of control flow**.
    ///
    /// `ReviewPromptLedger.requestIfEarned`'s shape, for its reason: the two sides that must never
    /// disagree are *"the ledger says we asked StoreKit"* and *"we asked StoreKit"*. Here they
    /// cannot, and the recorded outcome is Apple's answer rather than a re-derivation of it.
    ///
    /// Do not refactor this into a call that returns and a caller that records.
    @discardableResult
    /// `isolation:` lets `buy` inherit the caller's actor rather than hopping off it. Without it
    /// Swift 6 refuses to send a `@MainActor` closure in here, and the tempting fix — recording
    /// the outcome at the call site instead — is exactly the split this method exists to prevent.
    public mutating func purchasing(lifetimeMetres: Double,
                                    isolation: isolated (any Actor)? = #isolation,
                                    buy: () async -> UnlockOfferEvent) async -> UnlockOfferEvent {
        let bucket = RoadBucket.forLifetimeMetres(lifetimeMetres)
        furthestBucket = max(furthestBucket, bucket)
        record(.purchaseStarted, at: bucket)
        let outcome = await buy()
        record(outcome, at: bucket)
        return outcome
    }

    public mutating func restoreStarted(lifetimeMetres: Double) {
        record(.restoreStarted, at: RoadBucket.forLifetimeMetres(lifetimeMetres))
    }

    // MARK: Persistence

    public static func load(from defaults: UserDefaults, key: String = defaultsKey) -> UnlockOfferLedger {
        guard let data = defaults.data(forKey: key),
              var ledger = try? JSONDecoder().decode(UnlockOfferLedger.self, from: data)
        else { return UnlockOfferLedger() }
        // Pad, never truncate. A ledger written by a build with fewer buckets must keep every
        // count it has; one written by a build with more must not have counts thrown away.
        for (event, row) in ledger.counts where row.count < Self.bucketCount {
            ledger.counts[event] = row + Array(repeating: 0, count: Self.bucketCount - row.count)
        }
        return ledger
    }

    public func save(to defaults: UserDefaults, key: String = defaultsKey) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: key)
    }

    /// The line a customer can read, and choose to send. Local only.
    ///
    /// Every event is printed **including the zeros**, because the zeros are the finding: a
    /// summary that omitted empty rows would make "the row never appeared" and "this build does
    /// not record that" look identical, which is the whole failure this ledger exists to prevent.
    public var shareableSummary: String {
        let furthest = "furthest \(furthestBucket)"
        let rows = UnlockOfferEvent.allCases.map { "\($0.rawValue) \(count(of: $0))" }
        return "launches \(launches) · \(furthest) — " + rows.joined(separator: " · ")
    }
}
