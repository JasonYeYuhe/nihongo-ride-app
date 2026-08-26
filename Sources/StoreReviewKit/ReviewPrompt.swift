import Foundation

/// Deciding when to ask for an App Store review — and counting every time we decided not to.
///
/// ## Why this is instrumented at all
///
/// `requestReview()` is **fire-and-forget by design**: Apple decides whether to show anything,
/// never says which way it went, and silently drops calls past its own limit. So the only thing
/// this app can ever observe is *what it asked for*, and if the rejections are not counted then
/// a release that produces no new reviews is indistinguishable from a release whose gates never
/// let a single moment through. That is this project's oldest rule wearing new clothes:
/// **a checker that reports "no problems" is indistinguishable from a broken checker.**
///
/// Hence `ReviewPromptLedger` counts EVERY outcome, not just the asks. After a release the
/// question "did the accuracy floor block most of the moments?" has an answer, so the thresholds
/// below can be revised against data instead of defended.
///
/// ## What the counters do NOT mean
///
/// `requestDates` records the moments this app **called** `requestReview`. It is **not** a count
/// of prompts shown, ratings left, or users reached — none of those are observable. Nothing in
/// this module's public surface may be named as though they were, and
/// `ReviewPromptNamingTests` fails the build if that changes.
///
/// ## Which numbers here are judgements
///
/// All five thresholds are **judgements, not measurements**, and are recorded as such:
/// nobody has measured the right moment to ask a Nihongo Ride rider for a review, and this
/// project's rule is that a threshold written from intuition and validated by its own effect
/// has not been validated (v1.24 `inflectionalTails`). They are here to be *measured against*,
/// which is what the ledger is for.
public struct ReviewPromptPolicy: Sendable, Equatable {

    /// Judgement: a rider who has finished three rides has seen the app work. Below that, a
    /// prompt spends one of Apple's three annual slots on somebody who may never return.
    public var minimumLoggedRides: Int

    /// Judgement, and the one with the clearest reasoning behind it: coming back on a second
    /// calendar day is the cheapest available evidence of retention, and retention is what a
    /// review is being asked to vouch for.
    public var minimumRiddenDays: Int

    /// Judgement: asking immediately after a rough ride asks at the wrong moment. The bar is
    /// deliberately low — this is meant to skip disasters, not to select for perfection.
    public var minimumAccuracy: Double

    /// Judgement: local spacing, so two good rides in one evening cannot spend two of Apple's
    /// three annual slots.
    public var cooldownDays: Int

    /// **Not** a judgement — this mirrors Apple's documented limit of three prompts per app per
    /// user per 365 days. Mirrored locally so the ledger's numbers mean the same thing Apple's
    /// throttle does; without it the ledger would count asks that Apple silently discarded.
    public var maximumRequestsPerYear: Int

    public init(minimumLoggedRides: Int = 3,
                minimumRiddenDays: Int = 2,
                minimumAccuracy: Double = 0.80,
                cooldownDays: Int = 120,
                maximumRequestsPerYear: Int = 3) {
        self.minimumLoggedRides = minimumLoggedRides
        self.minimumRiddenDays = minimumRiddenDays
        self.minimumAccuracy = minimumAccuracy
        self.cooldownDays = cooldownDays
        self.maximumRequestsPerYear = maximumRequestsPerYear
    }
}

/// The finished ride being considered. Built once, where the data is freshest.
public struct RideMoment: Sendable, Equatable {
    /// True only for a ride that actually went into the journal — not a practice run, not a
    /// cram, and not an abandoned run with nothing typed. The app derives this from the same
    /// value that decides whether a `RideRecord` was appended, so the two cannot disagree.
    public var wasLogged: Bool
    public var accuracy: Double
    /// Lifetime rides INCLUDING this one (the journal has already been appended to).
    public var lifetimeRides: Int
    public var riddenDays: Int

    public init(wasLogged: Bool, accuracy: Double, lifetimeRides: Int, riddenDays: Int) {
        self.wasLogged = wasLogged
        self.accuracy = accuracy
        self.lifetimeRides = lifetimeRides
        self.riddenDays = riddenDays
    }
}

/// Why a finished ride did or did not become a review request. Every case is counted.
public enum ReviewPromptDecision: String, Codable, Sendable, CaseIterable {
    case asked
    case notALoggedRide
    case tooFewRides
    case tooFewRiddenDays
    case rideTooRough
    case withinCooldown
    case annualLimitReached
    /// A UI test, a screenshot capture, or any other run that must not touch the real store.
    case suppressed
}

/// Local, on-device, never transmitted. The distinction §G of the product plan turns on:
/// *Data Not Collected forbids collecting, not counting.*
public struct ReviewPromptLedger: Codable, Sendable, Equatable {

    /// Moments at which this app CALLED `requestReview`. Not prompts shown — see the module note.
    public private(set) var requestDates: [Date]

    /// Every decision ever reached, by case. The sum is the number of finished rides evaluated.
    public private(set) var outcomes: [String: Int]

    public init(requestDates: [Date] = [], outcomes: [String: Int] = [:]) {
        self.requestDates = requestDates
        self.outcomes = outcomes
    }

    public func count(of decision: ReviewPromptDecision) -> Int {
        outcomes[decision.rawValue] ?? 0
    }

    /// Finished rides evaluated, across every outcome.
    public var momentsEvaluated: Int { outcomes.values.reduce(0, +) }

    /// Times `requestReview` was called. Says nothing about what the user saw.
    public var requestsMade: Int { requestDates.count }

    public func requests(since date: Date) -> Int {
        requestDates.lazy.filter { $0 >= date }.count
    }

    // MARK: - The decision

    /// Pure. Exposed so tests can drive every branch without a side effect in sight.
    public func decide(moment: RideMoment,
                       policy: ReviewPromptPolicy,
                       now: Date,
                       suppressed: Bool) -> ReviewPromptDecision {
        if suppressed { return .suppressed }
        guard moment.wasLogged else { return .notALoggedRide }
        guard moment.lifetimeRides >= policy.minimumLoggedRides else { return .tooFewRides }
        guard moment.riddenDays >= policy.minimumRiddenDays else { return .tooFewRiddenDays }
        guard moment.accuracy >= policy.minimumAccuracy else { return .rideTooRough }
        let yearAgo = now.addingTimeInterval(-365 * 24 * 60 * 60)
        guard requests(since: yearAgo) < policy.maximumRequestsPerYear else { return .annualLimitReached }
        if let last = requestDates.max() {
            let cooldownEnds = last.addingTimeInterval(Double(policy.cooldownDays) * 24 * 60 * 60)
            guard now >= cooldownEnds else { return .withinCooldown }
        }
        return .asked
    }

    /// Evaluate this moment and, if it is earned, ask — **in one branch**.
    ///
    /// This shape is deliberate and it is this project's most-repeated lesson applied ahead of
    /// time rather than after. Twenty-one times now a number shown and a run produced have been
    /// computed by different predicates, and the durable fix each time was to give the two sides
    /// no way to disagree. Here the two sides are *"the ledger says we asked"* and *"we asked"*:
    /// `requestDates.append` and `ask()` sit on the same line of control flow, so a caller cannot
    /// record a request it never made or make one it never recorded.
    ///
    /// Do not refactor this into a `decide()` that returns and a caller that acts. That is the
    /// same shape as every defect above.
    @discardableResult
    public mutating func requestIfEarned(moment: RideMoment,
                                         policy: ReviewPromptPolicy = .init(),
                                         now: Date = Date(),
                                         suppressed: Bool = false,
                                         ask: () -> Void) -> ReviewPromptDecision {
        let decision = decide(moment: moment, policy: policy, now: now, suppressed: suppressed)
        outcomes[decision.rawValue, default: 0] += 1
        if decision == .asked {
            requestDates.append(now)
            ask()
        }
        return decision
    }

    // MARK: - Persistence

    public static let defaultsKey = "NihongoRide.reviewPrompt.v1"

    public static func load(from defaults: UserDefaults, key: String = defaultsKey) -> ReviewPromptLedger {
        guard let data = defaults.data(forKey: key),
              let ledger = try? JSONDecoder().decode(ReviewPromptLedger.self, from: data)
        else { return ReviewPromptLedger() }
        return ledger
    }

    public func save(to defaults: UserDefaults, key: String = defaultsKey) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: key)
    }

    /// A line the owner can read in the debug view, or paste into a support mail. Local only.
    public var debugSummary: String {
        let parts = ReviewPromptDecision.allCases
            .map { "\($0.rawValue) \(count(of: $0))" }
            .joined(separator: " · ")
        return "moments \(momentsEvaluated) · requested \(requestsMade) — \(parts)"
    }
}
