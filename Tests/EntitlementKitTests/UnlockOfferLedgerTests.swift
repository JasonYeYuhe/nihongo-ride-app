import Testing
import Foundation
import SceneryKit
@testable import EntitlementKit

/// The counter, and the six things that stop it being decoration.
///
/// A counter is the easiest thing in a codebase to ship broken, because a broken one and a working
/// one both report zero. Every test here exists against a specific way this one could report zero
/// while measuring nothing.
@Suite("The offer counter")
struct UnlockOfferLedgerTests {

    // MARK: Buckets

    @Test("the buckets are the shipped Tōkaidō, and stay pinned to it")
    func bucketsMatchTheShippedRoad() {
        // The literals in `RoadBucket` are a deliberate copy of the road rather than a reference
        // to it, so that adding a second route cannot silently re-index counts already recorded.
        // A copy that nothing compares is just drift waiting to happen, so this is the comparison.
        #expect(RoadBucket.thresholds == RideRoute.tokaidoStages.map(\.startMetres),
                "the free road moved and the counter's buckets did not; every recorded count now means a different stretch than it did when it was written")
        #expect(RoadBucket.allCases.count == RideRoute.tokaidoStages.count)
        #expect(RoadBucket.kyoto.rawValue == RideRoute.tokaidoStages.count - 1,
                "the last bucket must be arrival, because that is the one the offer is FOR")
    }

    @Test("a bucket is chosen the same way the scene chooses a stretch")
    func bucketsAgreeWithTheScene() {
        // The counter and the scenery must not disagree about where a rider is: a ledger saying
        // "furthest 鈴鹿" while the rider was looking at 京都 would be a false negative in exactly
        // the case the experiment turns on.
        let free = RideRoute.stages(westOpen: false)
        for m in stride(from: -3_000.0, through: 40_000.0, by: 91.0) {
            let bucket = RoadBucket.forLifetimeMetres(m)
            let stage = RideRoute.stage(forLifetimeMetres: m, in: free)
            #expect(bucket.rawValue == stage.id, "at \(m) m the counter says \(bucket) and the scene says \(stage.name)")
        }
        #expect(RoadBucket.forLifetimeMetres(.nan) == .nihonbashi)
        #expect(RoadBucket.forLifetimeMetres(.infinity) == .kyoto)
    }

    // MARK: The three explanations of a zero

    @Test("a zero can be told apart from a zero: the three readings are distinguishable")
    func theThreeZerosAreDistinguishable() {
        // (c) nobody ever opened Settings — but the device HAD arrived.
        var neverSaw = UnlockOfferLedger()
        for _ in 0 ..< 60 { neverSaw.launched(lifetimeMetres: 30_000) }
        #expect(neverSaw.count(of: .settingsRowAppeared) == 0)
        #expect(neverSaw.launches == 60)
        #expect(neverSaw.furthestBucket == .kyoto)

        // (b) the row appeared, repeatedly, to somebody 20 km short of it mattering.
        var tooEarly = UnlockOfferLedger()
        for _ in 0 ..< 12 {
            tooEarly.rowAppeared(lifetimeMetres: 3_000, entitled: false, offerLoaded: true, suppressed: false)
        }
        #expect(tooEarly.count(of: .settingsRowAppeared, in: .fuji) == 12)
        #expect(tooEarly.count(of: .settingsRowAppeared, in: .kyoto) == 0)
        #expect(tooEarly.furthestBucket == .fuji)

        // (a) the only configuration in which a zero is evidence about willingness to pay.
        var sawAndDeclined = UnlockOfferLedger()
        for _ in 0 ..< 12 {
            sawAndDeclined.rowAppeared(lifetimeMetres: 30_000, entitled: false, offerLoaded: true, suppressed: false)
        }
        #expect(sawAndDeclined.count(of: .settingsRowAppeared, in: .kyoto) == 12)
        #expect(sawAndDeclined.count(of: .purchaseStarted) == 0)

        // …and the three are actually different objects, which is the assertion that matters.
        #expect(neverSaw != tooEarly)
        #expect(tooEarly != sawAndDeclined)
        #expect(neverSaw != sawAndDeclined)
    }

    @Test("a row that could not offer anything is not counted as an offer")
    func unavailableIsItsOwnFact() {
        var ledger = UnlockOfferLedger()
        ledger.rowAppeared(lifetimeMetres: 30_000, entitled: false, offerLoaded: false, suppressed: false)
        #expect(ledger.count(of: .offerUnavailable) == 1)
        #expect(ledger.count(of: .settingsRowAppeared) == 0,
                "an offline device with no prices would otherwise read as a declined offer")
    }

    @Test("an owner's device is not counted as an unconverted one")
    func alreadyOwnedIsItsOwnFact() {
        var ledger = UnlockOfferLedger()
        ledger.rowAppeared(lifetimeMetres: 30_000, entitled: true, offerLoaded: true, suppressed: false)
        #expect(ledger.count(of: .alreadyOwned) == 1)
        #expect(ledger.count(of: .settingsRowAppeared) == 0)
    }

    @Test("a UI test or a screenshot render is never counted as a person")
    func suppressedIsItsOwnFact() {
        var ledger = UnlockOfferLedger()
        ledger.rowAppeared(lifetimeMetres: 100, entitled: false, offerLoaded: true, suppressed: true)
        #expect(ledger.count(of: .suppressed) == 1)
        #expect(ledger.count(of: .settingsRowAppeared) == 0)
    }

    // MARK: The one-branch purchase

    @Test("asking StoreKit and recording that we asked cannot come apart")
    func purchaseIsOneBranch() async {
        var ledger = UnlockOfferLedger()
        let outcome = await ledger.purchasing(lifetimeMetres: 30_000) { .purchaseCancelled }
        #expect(outcome == .purchaseCancelled)
        #expect(ledger.count(of: .purchaseStarted) == 1)
        #expect(ledger.count(of: .purchaseCancelled) == 1)
        #expect(ledger.count(of: .purchaseStarted, in: .kyoto) == 1,
                "the attempt must be filed under where the rider was, not under bucket zero")
    }

    @Test("every StoreKit outcome has somewhere to land, including one nobody has seen yet")
    func noOutcomeIsDropped() async {
        for outcome in UnlockOfferEvent.allCases {
            var ledger = UnlockOfferLedger()
            _ = await ledger.purchasing(lifetimeMetres: 0) { outcome }
            #expect(ledger.count(of: outcome) >= 1, "\(outcome) was recorded nowhere")
        }
        // `purchaseUnrecognised` exists for `@unknown default`. A future StoreKit case must be
        // counted rather than silently dropped — the rule `sales_report.py` applies to product
        // codes it does not know.
        #expect(UnlockOfferEvent.allCases.contains(.purchaseUnrecognised))
    }

    // MARK: Storage

    @Test("a ledger written by a build with fewer buckets loses nothing")
    func decodingPadsAndNeverTruncates() throws {
        let suite = "UnlockOffer.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        // A short row, as an older build would have written it.
        let short = #"{"counts":{"settingsRowAppeared":[1,2,3]},"launches":9,"furthestBucket":2}"#
        defaults.set(Data(short.utf8), forKey: UnlockOfferLedger.defaultsKey)
        let loaded = UnlockOfferLedger.load(from: defaults)
        #expect(loaded.count(of: .settingsRowAppeared) == 6, "counts were lost on load")
        #expect(loaded.counts["settingsRowAppeared"]?.count == UnlockOfferLedger.bucketCount)
        #expect(loaded.launches == 9)
        #expect(loaded.furthestBucket == .hakone)

        // A long row, as a NEWER build would have written it, must not be cut down.
        let long = #"{"counts":{"settingsRowAppeared":[1,1,1,1,1,1,1,1,1,1,1,1]},"launches":1,"furthestBucket":0}"#
        defaults.set(Data(long.utf8), forKey: UnlockOfferLedger.defaultsKey)
        #expect(UnlockOfferLedger.load(from: defaults).count(of: .settingsRowAppeared) == 12,
                "a downgrade threw away counts a later build had recorded")
    }

    @Test("it round-trips")
    func roundTrip() throws {
        let suite = "UnlockOffer.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var ledger = UnlockOfferLedger()
        ledger.launched(lifetimeMetres: 26_000)
        ledger.rowAppeared(lifetimeMetres: 26_000, entitled: false, offerLoaded: true, suppressed: false)
        ledger.save(to: defaults)
        #expect(UnlockOfferLedger.load(from: defaults) == ledger)
    }

    // MARK: The things that make it an instrument rather than decoration

    @Test("the summary prints every event, including the ones that are zero")
    func summaryIsAKnownPositive() async {
        // The known positive this project refuses to proceed without: drive one of everything
        // through, and require the summary to show each with its exact count. A summary that
        // rendered zeros for a ledger that HAD moved would read exactly like a quiet device.
        var ledger = UnlockOfferLedger()
        ledger.launched(lifetimeMetres: 26_000)
        // Through the shipped API only. A test that assigned `counts` directly would be proving
        // that a dictionary can be printed, not that the ledger records what the app does to it.
        for _ in 0 ..< 7 {
            ledger.rowAppeared(lifetimeMetres: 26_000, entitled: false, offerLoaded: true, suppressed: false)
            ledger.rowAppeared(lifetimeMetres: 26_000, entitled: true, offerLoaded: true, suppressed: false)
            ledger.rowAppeared(lifetimeMetres: 26_000, entitled: false, offerLoaded: false, suppressed: false)
            ledger.rowAppeared(lifetimeMetres: 26_000, entitled: false, offerLoaded: true, suppressed: true)
            ledger.restoreStarted(lifetimeMetres: 26_000)
            for outcome: UnlockOfferEvent in [.purchaseSucceeded, .purchaseUnverified, .purchaseCancelled,
                                              .purchasePending, .purchaseFailed, .purchaseUnrecognised] {
                _ = await ledger.purchasing(lifetimeMetres: 26_000) { outcome }
            }
        }
        let summary = ledger.shareableSummary
        for event in UnlockOfferEvent.allCases where event != .purchaseStarted {
            #expect(summary.contains("\(event.rawValue) 7"), "\(event.rawValue) is missing from the summary")
        }
        #expect(summary.contains("purchaseStarted 42"))
        #expect(summary.contains("launches 1"))
        #expect(summary.contains("furthest kyoto"))

        // And an untouched ledger must print the zeros rather than an empty line, because "the
        // row never appeared" and "this build does not record that" must not look the same.
        let empty = UnlockOfferLedger().shareableSummary
        #expect(empty.contains("settingsRowAppeared 0"))
        #expect(empty.contains("purchaseSucceeded 0"))
    }

    @Test("the summary carries no raw distance, and cannot")
    func summaryCannotLeakADistance() {
        var ledger = UnlockOfferLedger()
        // A distinctive odometer value. If any code path ever kept the raw figure, this is where
        // it would surface — and a rider's exact lifetime distance is close to a fingerprint of
        // their entire history, on a string the design expects them to paste into a message.
        ledger.launched(lifetimeMetres: 31_337)
        ledger.rowAppeared(lifetimeMetres: 31_337, entitled: false, offerLoaded: true, suppressed: false)
        #expect(!ledger.shareableSummary.contains("31337"))
        #expect(!ledger.shareableSummary.contains("31,337"))
        #expect(!ledger.shareableSummary.contains("31337.0"))
        // Structural, not incidental: nothing in the stored value is a Double at all.
        let json = try? JSONEncoder().encode(ledger)
        let text = json.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        #expect(!text.contains("31337"), "the raw odometer reached the stored ledger")
    }

    @Test("no name claims something this app cannot observe")
    func namesClaimOnlyWhatIsObservable() throws {
        // `ReviewPromptNamingTests`' discipline, applied to a second ledger. Two module-specific
        // justifications, which are exactly what this test enforces:
        //
        //  * `onAppear` fires when a row is ADDED TO THE HIERARCHY, which is an upper bound on
        //    anyone looking at it — so `seen` / `shown` / `viewed` would be fabrications;
        //  * a customer who did not tap did not DECLINE, so no name may imply refusal.
        //    `cancelled` is allowed only because StoreKit reports `.userCancelled`.
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/EntitlementKit")
        let source = try String(contentsOf: dir.appendingPathComponent("UnlockOfferLedger.swift"),
                               encoding: .utf8)

        // Declarations only — the prose above deliberately discusses the forbidden words in order
        // to explain why they are forbidden, and a scanner that could not tell an explanation
        // from a name would have to be lied to.
        let declarations = source.split(separator: "\n")
            .filter { line in
                let t = line.trimmingCharacters(in: .whitespaces)
                return (t.hasPrefix("case ") || t.hasPrefix("public var ") || t.hasPrefix("public func ")
                        || t.hasPrefix("public mutating func ") || t.hasPrefix("public private(set) var "))
                    && !t.hasPrefix("///")
            }
            .joined(separator: "\n")
        #expect(declarations.split(separator: "\n").count > 15,
                "the scan read \(declarations.split(separator: "\n").count) declarations — too few to judge")

        let fabrications = ["seen", "shown", "viewed", "displayed", "noticed", "declined",
                            "refused", "rejected", "ignored", "dismissed", "interest", "willing",
                            "convert", "users", "people", "customers", "audience"]
        for word in fabrications {
            #expect(!declarations.lowercased().contains(word),
                    "a declaration is named '\(word)', which claims something this app cannot observe")
        }
        // Negative control: the scan must catch one when it is really there.
        #expect(fabrications.contains { "    case settingsRowSeen".lowercased().contains($0) },
                "the naming scan cannot detect its own forbidden words")
    }
}
