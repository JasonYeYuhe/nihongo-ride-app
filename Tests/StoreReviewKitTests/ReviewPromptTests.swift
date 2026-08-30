import Testing
import Foundation
@testable import StoreReviewKit

private let day: TimeInterval = 24 * 60 * 60
private let t0 = Date(timeIntervalSince1970: 1_780_000_000)

private func earned(_ overrides: (inout RideMoment) -> Void = { _ in }) -> RideMoment {
    var m = RideMoment(wasLogged: true, accuracy: 0.95, lifetimeRides: 5, riddenDays: 3)
    overrides(&m)
    return m
}

@Suite("Review prompt — every branch, and every branch counted")
struct ReviewPromptDecisionTests {

    @Test("a good ride from a returning rider is asked")
    func asks() {
        var ledger = ReviewPromptLedger()
        var asked = 0
        let d = ledger.requestIfEarned(moment: earned(), now: t0) { asked += 1 }
        #expect(d == .asked)
        #expect(asked == 1)
        #expect(ledger.requestsMade == 1)
    }

    @Test("a practice run, a cram, or an abandoned ride is never a moment")
    func notLogged() {
        var ledger = ReviewPromptLedger()
        var asked = 0
        let d = ledger.requestIfEarned(moment: earned { $0.wasLogged = false }, now: t0) { asked += 1 }
        #expect(d == .notALoggedRide)
        #expect(asked == 0)
        #expect(ledger.requestsMade == 0)
    }

    @Test("a rider below the ride floor is not asked")
    func tooFewRides() {
        var ledger = ReviewPromptLedger()
        let d = ledger.requestIfEarned(moment: earned { $0.lifetimeRides = 2 }, now: t0) {
            Issue.record("must not ask")
        }
        #expect(d == .tooFewRides)
    }

    @Test("a rider who has only ever ridden on one day is not asked")
    func tooFewDays() {
        var ledger = ReviewPromptLedger()
        let d = ledger.requestIfEarned(moment: earned { $0.riddenDays = 1 }, now: t0) {
            Issue.record("must not ask")
        }
        #expect(d == .tooFewRiddenDays)
    }

    @Test("a rough ride is the wrong moment")
    func rough() {
        var ledger = ReviewPromptLedger()
        let d = ledger.requestIfEarned(moment: earned { $0.accuracy = 0.5 }, now: t0) {
            Issue.record("must not ask")
        }
        #expect(d == .rideTooRough)
    }

    @Test("suppression beats everything, so a UI test cannot spend a real slot")
    func suppressed() {
        var ledger = ReviewPromptLedger()
        let d = ledger.requestIfEarned(moment: earned(), now: t0, suppressed: true) {
            Issue.record("must not ask")
        }
        #expect(d == .suppressed)
        #expect(ledger.requestsMade == 0)
    }

    @Test("two good rides in one evening cannot spend two slots")
    func cooldown() {
        var ledger = ReviewPromptLedger()
        _ = ledger.requestIfEarned(moment: earned(), now: t0) {}
        let d = ledger.requestIfEarned(moment: earned(), now: t0.addingTimeInterval(day)) {
            Issue.record("must not ask inside the cooldown")
        }
        #expect(d == .withinCooldown)
        #expect(ledger.requestsMade == 1)
    }

    @Test("past the cooldown, a good ride is asked again")
    func afterCooldown() {
        var ledger = ReviewPromptLedger()
        _ = ledger.requestIfEarned(moment: earned(), now: t0) {}
        var asked = 0
        let d = ledger.requestIfEarned(moment: earned(), now: t0.addingTimeInterval(121 * day)) { asked += 1 }
        #expect(d == .asked)
        #expect(asked == 1)
    }

    /// Apple's own throttle is three per 365 days and it discards the rest SILENTLY. Mirroring it
    /// locally is what keeps `requestsMade` meaning the same thing Apple's counter means.
    @Test("the fourth request inside a year is refused, mirroring Apple's limit")
    func annualLimit() {
        var ledger = ReviewPromptLedger()
        for i in 0..<3 {
            let d = ledger.requestIfEarned(moment: earned(), now: t0.addingTimeInterval(Double(i) * 121 * day)) {}
            #expect(d == .asked, "request \(i + 1) of 3 should be allowed")
        }
        let d = ledger.requestIfEarned(moment: earned(), now: t0.addingTimeInterval(363 * day)) {
            Issue.record("must not exceed Apple's three")
        }
        #expect(d == .annualLimitReached)
        #expect(ledger.requestsMade == 3)
    }

    @Test("the limit is rolling, so a year later the slots come back")
    func limitRolls() {
        var ledger = ReviewPromptLedger()
        for i in 0..<3 { _ = ledger.requestIfEarned(moment: earned(), now: t0.addingTimeInterval(Double(i) * 121 * day)) {} }
        let d = ledger.requestIfEarned(moment: earned(), now: t0.addingTimeInterval(370 * day)) {}
        #expect(d == .asked)
    }
}

@Suite("Review prompt — the ledger is the instrument")
struct ReviewPromptLedgerTests {

    /// The property the whole design exists for: **the ledger cannot record a request that was
    /// never made, and cannot miss one that was.** Drive every branch and assert the two sides
    /// agree on every single call. Mutating `requestIfEarned` so the append and the `ask()` sit
    /// on different branches turns this red.
    @Test("asking and recording an ask are the same branch, over every outcome")
    func askAndRecordCannotDisagree() {
        var ledger = ReviewPromptLedger()
        var asks = 0
        var now = t0
        let moments = [
            earned(), earned { $0.wasLogged = false }, earned { $0.accuracy = 0.1 },
            earned(), earned { $0.lifetimeRides = 1 }, earned { $0.riddenDays = 1 },
            earned(), earned(), earned(), earned(),
        ]
        for (i, m) in moments.enumerated() {
            let before = ledger.requestsMade
            let d = ledger.requestIfEarned(moment: m, now: now, suppressed: i == 8) { asks += 1 }
            let grew = ledger.requestsMade - before
            #expect(grew == (d == .asked ? 1 : 0), "ledger and decision disagreed at \(i)")
            #expect(asks == ledger.requestsMade, "the ask closure and the ledger diverged at \(i)")
            now = now.addingTimeInterval(200 * day)
        }
        #expect(ledger.momentsEvaluated == moments.count, "every evaluated moment must be counted")
    }

    /// A gate whose effect is never measured is folklore. This is what makes the thresholds
    /// revisable after a release instead of permanent.
    @Test("every rejection is counted by reason")
    func rejectionsAreCounted() {
        var ledger = ReviewPromptLedger()
        _ = ledger.requestIfEarned(moment: earned { $0.wasLogged = false }, now: t0) {}
        _ = ledger.requestIfEarned(moment: earned { $0.accuracy = 0.2 }, now: t0) {}
        _ = ledger.requestIfEarned(moment: earned { $0.accuracy = 0.2 }, now: t0) {}
        #expect(ledger.count(of: .notALoggedRide) == 1)
        #expect(ledger.count(of: .rideTooRough) == 2)
        #expect(ledger.count(of: .asked) == 0)
        #expect(ledger.momentsEvaluated == 3)
    }

    @Test("the ledger survives a save and load")
    func persists() throws {
        let suite = "ReviewPromptTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        var ledger = ReviewPromptLedger()
        _ = ledger.requestIfEarned(moment: earned(), now: t0) {}
        _ = ledger.requestIfEarned(moment: earned { $0.accuracy = 0.1 }, now: t0) {}
        ledger.save(to: defaults)

        let loaded = ReviewPromptLedger.load(from: defaults)
        #expect(loaded == ledger)
        #expect(loaded.requestsMade == 1)
        #expect(loaded.count(of: .rideTooRough) == 1)
    }

    @Test("an empty store loads an empty ledger rather than failing")
    func loadsEmpty() throws {
        let suite = "ReviewPromptTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(ReviewPromptLedger.load(from: defaults) == ReviewPromptLedger())
    }

    /// The cooldown must survive a relaunch, which it only does if the DATES persist rather than
    /// a "have we asked" flag. Mutating `requestDates` to a `Bool` turns this red.
    @Test("the cooldown is enforced across a reload")
    func cooldownSurvivesReload() throws {
        let suite = "ReviewPromptTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        var ledger = ReviewPromptLedger()
        _ = ledger.requestIfEarned(moment: earned(), now: t0) {}
        ledger.save(to: defaults)

        var reloaded = ReviewPromptLedger.load(from: defaults)
        let d = reloaded.requestIfEarned(moment: earned(), now: t0.addingTimeInterval(10 * day)) {
            Issue.record("a relaunch must not reset the cooldown")
        }
        #expect(d == .withinCooldown)
    }
}

/// This project's cheapest detector: **where a comment states a contract, check whether anything
/// enforces it.** `ReviewPrompt.swift` states that nothing here counts prompts *shown*, because
/// `requestReview` never reports back. That sentence is worth nothing on its own — a future
/// `promptsShown` would read as fact and be a fabrication. So the sentence is enforced.
@Suite("Nothing claims to observe what Apple never reports")
struct ReviewPromptNamingTests {

    static let forbidden = ["shown", "displayed", "presented", "impression", "seen", "viewed"]

    // Types are scanned too. The first version matched only var/let/func/case, so a
    // `public struct PromptsShown` would have passed the guard that exists to forbid it —
    // a scan whose blind spot was the thing it was written to catch.

    static var sourceFile: URL {
        URL(fileURLWithPath: #filePath)      // …/Tests/StoreReviewKitTests/ReviewPromptTests.swift
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/StoreReviewKit/ReviewPrompt.swift")
    }

    @Test("no public declaration is named as though a prompt could be observed")
    func noObservationNames() throws {
        let source = try String(contentsOf: Self.sourceFile, encoding: .utf8)
        var inspected = 0
        var offenders: [String] = []
        for rawLine in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            // Prose is allowed to use the words; declarations are not.
            guard !line.hasPrefix("//") else { continue }
            guard let range = line.range(of: #"\b(public\s+(private\(set\)\s+)?(var|let|func|struct|class|enum|typealias)|case)\s+([A-Za-z_][A-Za-z0-9_]*)"#,
                                         options: .regularExpression) else { continue }
            let decl = String(line[range])
            guard let name = decl.split(separator: " ").last.map(String.init) else { continue }
            inspected += 1
            let lower = name.lowercased()
            if Self.forbidden.contains(where: { lower.contains($0) }) { offenders.append(name) }
        }
        // A scan that reads nothing cannot report clean — the v1.24 lesson, applied to itself.
        #expect(inspected >= 15, "the scanner found only \(inspected) declarations; it is broken, not clean")
        #expect(offenders.isEmpty, "these names claim to observe what requestReview never reports: \(offenders)")
    }
}

/// **The rating prompt yields to a newly-opened purchase entrance, for exactly one ride.**
///
/// v1.30 gave the offer a second entrance on the menu, live once a rider passes Kyōto. The
/// placement discipline keeps the offer away from the rating prompt, and until now that was a
/// statement about SCREENS — the prompt fires on results, the offer lived in Settings. The new
/// entrance breaks it in TIME instead: the crossing ride is a long, accurate ride after many
/// logged days, which is the exact profile every other clause of `decide` selects for, so both
/// would fire in one session on the population most likely to buy.
@Suite("A ride that opens an offer does not also ask for a rating")
struct ReviewPromptOfferCollisionTests {

    /// Everything the policy wants: enough rides, enough days, clean accuracy, no history.
    private func earnedMoment(openedANewOffer: Bool) -> RideMoment {
        RideMoment(wasLogged: true, accuracy: 0.99, lifetimeRides: 50, riddenDays: 20,
                   openedANewOffer: openedANewOffer)
    }

    @Test("the same moment is asked without the offer and yielded with it")
    func theOnlyDifferenceIsTheOffer() {
        let ledger = ReviewPromptLedger()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let policy = ReviewPromptPolicy()

        // Paired, so the assertion cannot pass because the moment failed some OTHER clause — the
        // shape where a guard "works" because nothing ever reached it.
        #expect(ledger.decide(moment: earnedMoment(openedANewOffer: false),
                              policy: policy, now: now, suppressed: false) == .asked)
        #expect(ledger.decide(moment: earnedMoment(openedANewOffer: true),
                              policy: policy, now: now, suppressed: false) == .rideOpenedANewOffer)
    }

    @Test("yielding does not spend one of the three requests Apple allows per year")
    func yieldingIsNotARequest() {
        var ledger = ReviewPromptLedger()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var asked = 0
        ledger.requestIfEarned(moment: earnedMoment(openedANewOffer: true), now: now,
                               suppressed: false) { asked += 1 }

        #expect(asked == 0, "the prompt was shown on the ride that opened the offer")
        #expect(ledger.requestsMade == 0, "yielding consumed one of the year's three requests")
        #expect(ledger.count(of: .rideOpenedANewOffer) == 1, "the yield was not counted")

        // And the very next ride still can ask — the yield is for one ride, not a suppression.
        ledger.requestIfEarned(moment: earnedMoment(openedANewOffer: false), now: now,
                               suppressed: false) { asked += 1 }
        #expect(asked == 1, "the rider's prompt was not merely deferred, it was lost")
    }

    @Test("the offer check runs before the cooldown, so the order cannot silently reverse")
    func theOfferCheckPrecedesTheCooldown() {
        // If `openedANewOffer` were tested after the cooldown, a rider inside a cooldown would be
        // counted `withinCooldown` and the yield would never appear in the ledger — the outcome
        // would be right and the record wrong, which is how a counter stops meaning anything.
        var ledger = ReviewPromptLedger()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        ledger.requestIfEarned(moment: earnedMoment(openedANewOffer: false), now: now,
                               suppressed: false) { }
        #expect(ledger.requestsMade == 1)

        let soon = now.addingTimeInterval(60 * 60)      // deep inside any cooldown
        #expect(ledger.decide(moment: earnedMoment(openedANewOffer: false),
                              policy: ReviewPromptPolicy(), now: soon, suppressed: false) == .withinCooldown)
        #expect(ledger.decide(moment: earnedMoment(openedANewOffer: true),
                              policy: ReviewPromptPolicy(), now: soon, suppressed: false) == .rideOpenedANewOffer)
    }

    @Test("suppression still wins, so a UI test or a capture is never an offer yield")
    func suppressionOutranksIt() {
        let ledger = ReviewPromptLedger()
        #expect(ledger.decide(moment: earnedMoment(openedANewOffer: true),
                              policy: ReviewPromptPolicy(),
                              now: Date(timeIntervalSince1970: 1_700_000_000),
                              suppressed: true) == .suppressed)
    }
}
