import XCTest

/// **Where the offer is, and — the harder half — where it is not.**
///
/// The placement is the one part of Stage 1 that no unit test can reach: where the offer is
/// reachable from is a statement about the running app's screens. It is also the constraint most
/// likely to be quietly violated by a later edit, because adding a second entry point always looks
/// like an improvement to whoever is adding it.
///
/// ## v1.30 has TWO entrances, deliberately, and this file is where that is written down
///
/// The rule was "one row, in Settings, and nowhere else". It is now:
///
///  * the Settings row (`roadRow`), always; and
///  * the menu's route strip (`menuRouteEntrance`), **only at or past Kyōto**.
///
/// The second one was added because the first cannot produce an interpretable zero: the offer is
/// only useful past 48 rides, its counter is never transmitted, and §K's branch that turns a zero
/// into evidence needs a voluntarily returned ledger that probably never arrives. It shipped
/// **before** the observation window opened, and §I/§K were amended and timestamped to say so —
/// doing it mid-window would have voided the pre-registration instead.
///
/// **A second entrance is exactly what the doc comment above warns about**, so the guard is not
/// weakened to accommodate it — it is made specific. What still must never happen: an entrance
/// before arrival, an entrance on a post-ride screen, or a price or buy control anywhere but the
/// road screen. Those are the tests below, and they are the reason a THIRD entrance cannot arrive
/// quietly.
///
/// ## Why these tests fake the entitlement instead of buying anything
///
/// Measured 2026-08-30 on Xcode 26.6 / iOS 26.5: a local `.storekit` configuration never reaches
/// the app on iOS under `xcodebuild test` under any wiring, and `SKTestSession` is inert while its
/// initialiser does not throw. So an iOS test that tried to purchase would be a test that proved
/// nothing while passing. The purchase gates live on macOS (`Tests/NihongoRideMacTests`); what
/// lives here is what only a running iOS app can answer.
///
/// `NIHONGO_FAKE_ENTITLEMENT` is `#if DEBUG` only, and `EntitlementSeamTests` in the SwiftPM suite
/// reads the shipping source to prove it — a seam that faked every launch would satisfy a naive
/// assertion and ship a free unlock.
final class PaidRouteRowTests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    /// Screens slide in with a spring; tapping a mid-flight button can miss.
    /// Waits for an element to stop moving. Split out of `tapWhenSettled` so a test can settle
    /// an element and then tap it somewhere specific — the hit-area test below needs to choose
    /// its own point, and calling `tapWhenSettled` first would consume the tap and navigate away
    /// before it got the chance.
    private func settle(_ element: XCUIElement) {
        var last = element.frame
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            usleep(250_000)
            let now = element.frame
            if now.equalTo(last) { break }
            last = now
        }
    }

    private func tapWhenSettled(_ element: XCUIElement) {
        settle(element)
        element.tap()
    }

    private func openSettings(_ app: XCUIApplication) {
        let settings = app.buttons["settingsButton"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "the menu should show a Settings button")
        tapWhenSettled(settings)
    }

    // MARK: There is exactly one, and it is here

    @MainActor
    func testExactlyOneRoadRowExistsAndItIsInSettings() {
        let app = XCUIApplication()
        app.launchIsolated(["NIHONGO_FAKE_ENTITLEMENT": "neverEstablished"])

        // The road ROW is never on the menu — the menu's entrance is a different element with a
        // different rule (see `testTheMenuEntranceIsAbsentBeforeKyoto`), and this launch is at
        // zero distance so neither should be present.
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "roadRow").count, 0,
                       "the offer row appears on the menu")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "menuRouteEntrance").count, 0,
                       "the menu entrance is present at zero distance")

        openSettings(app)
        let row = app.buttons["roadRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Settings should carry the road row")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "roadRow").count, 1,
                       "there is more than one road row on the Settings screen")
    }

    @MainActor
    func testTheRowOpensTheRoadScreenAndComesBack() {
        let app = XCUIApplication()
        app.launchIsolated(["NIHONGO_FAKE_ENTITLEMENT": "neverEstablished"])
        openSettings(app)

        let row = app.buttons["roadRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        tapWhenSettled(row)

        let back = app.buttons["roadBackButton"]
        XCTAssertTrue(back.waitForExistence(timeout: 5), "the road screen should have a Back button")
        // Restore must be reachable, and reachable in the state where it is NEEDED — a buyer on a
        // second device or after a reinstall whose entitlement has not resolved yet. App Review
        // guideline 3.1.1 requires a restore mechanism for non-consumables; a design that hid the
        // whole row once owned could present none in exactly that state.
        XCTAssertTrue(app.buttons["restorePurchases"].exists,
                      "the road screen must always offer Restore Purchases")
        tapWhenSettled(back)
        XCTAssertTrue(app.buttons["settingsBackButton"].waitForExistence(timeout: 5),
                      "Back should land on Settings")
    }

    // MARK: The second entrance (v1.30), and the arrival gate on it

    /// The guarantee that keeps the free experience and the App Store screenshot identical to
    /// v1.29 for everybody who has not finished the road — which is nearly everybody.
    @MainActor
    func testTheMenuEntranceIsAbsentBeforeKyoto() {
        let app = XCUIApplication()
        app.launchIsolated(["NIHONGO_FAKE_ENTITLEMENT": "neverEstablished",
                            "NIHONGO_FAKE_LIFETIME_METRES": "24999"])

        XCTAssertTrue(app.buttons["startButton"].waitForExistence(timeout: 10),
                      "the menu should have loaded")
        // One metre short. The boundary is the interesting case: an off-by-one here would open the
        // entrance for riders the thing being sold is no use to, which is the population the whole
        // arrival gate exists to exclude.
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "menuRouteEntrance").count, 0,
                       "the menu entrance appeared one metre short of Kyōto")
    }

    @MainActor
    func testTheMenuEntranceAppearsAtKyotoAndOpensTheRoadScreen() {
        let app = XCUIApplication()
        app.launchIsolated(["NIHONGO_FAKE_ENTITLEMENT": "neverEstablished",
                            "NIHONGO_FAKE_LIFETIME_METRES": "25000"])

        let entrance = app.buttons["menuRouteEntrance"]
        XCTAssertTrue(entrance.waitForExistence(timeout: 10),
                      "a rider at Kyōto should see the arrived route strip")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "menuRouteEntrance").count, 1,
                       "there is more than one menu entrance")

        // It carries no price and no buy control — it reports a state and navigates. A buy button
        // here would be the solicitation the placement rule forbids, wearing a state's clothes.
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "buyRoadWest").count, 0,
                       "the menu entrance carries a purchase control")

        tapWhenSettled(entrance)
        XCTAssertTrue(app.buttons["roadBackButton"].waitForExistence(timeout: 5),
                      "the menu entrance should open the road screen")
        XCTAssertTrue(app.buttons["restorePurchases"].exists,
                      "the road screen must always offer Restore Purchases")
    }

    // MARK: What must NOT happen anywhere else

    @MainActor
    func testTheResultsScreenCarriesNoPurchaseAffordance() {
        // The constraint most likely to be broken by a later edit, and the only thing that can
        // catch it is a screen-level assertion. v1.27 already fires the App Store rating prompt
        // after a completed ride; two asks landing on the same moment spends the goodwill of one
        // on the other, which is why the plan puts the offer deliberately far from it.
        let app = XCUIApplication()
        // Launched PAST Kyōto on purpose. At zero distance the menu entrance does not exist, so a
        // results screen with no purchase affordance would prove nothing about the new entrance —
        // the assertion would pass because there was nothing to leak. This is the population that
        // has one.
        app.launchIsolated(["NIHONGO_FAKE_ENTITLEMENT": "neverEstablished",
                            "NIHONGO_FAKE_LIFETIME_METRES": "30000"])

        let start = app.buttons["startButton"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["menuRouteEntrance"].exists,
                      "the entrance should exist on the menu, or this test proves nothing")

        // TYPE one word before ending. Since v1.33 a run that typed nothing gets a different
        // results screen (no 🏁, no grade, no Share — `RunTyping.typedNothing`), and a paused-
        // and-ended run is exactly that. Left as it was, this test would only ever inspect the
        // screen no real rider sees after a ride, and an offer added beside the grade or the
        // Share button — the spot next to the rating prompt this test exists for — would pass.
        // (v1.33 pre-submission review.) Hints on, as `TouchFlowTests` does, so there is romaji
        // to read.
        let assistance = app.segmentedControls.matching(
            NSPredicate(format: "label IN {'Romaji assistance', '罗马字提示'}")).firstMatch
        XCTAssertTrue(assistance.waitForExistence(timeout: 5), "assistance picker missing")
        assistance.buttons.element(boundBy: 0).tap()
        tapWhenSettled(start)

        let hint = app.staticTexts["romajiHint"]
        XCTAssertTrue(hint.waitForExistence(timeout: 10), "romaji hint should be visible")
        let romaji = hint.label.replacingOccurrences(of: "→ ", with: "")
        XCTAssertFalse(romaji.isEmpty)
        app.typeText(romaji)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '1/'"))
                        .firstMatch.waitForExistence(timeout: 5),
                      "one word should be completed, or this inspects the typed-nothing screen again")

        // Then finish the short way: pause and end it.
        let pause = app.buttons["pauseButton"]
        if pause.waitForExistence(timeout: 10) { tapWhenSettled(pause) }
        let end = app.buttons["endRunButton"]
        if end.waitForExistence(timeout: 5) { tapWhenSettled(end) }
        // Proof the screen being inspected IS the results screen. Absent, every absence below
        // would pass on whatever screen the run had stalled on — a gap older than v1.33.
        XCTAssertTrue(app.buttons["menuButton"].waitForExistence(timeout: 10),
                      "the results screen was never reached, so the absences below prove nothing")

        for identifier in ["roadRow", "buyRoadWest", "restorePurchases", "menuRouteEntrance"] {
            XCTAssertEqual(app.descendants(matching: .any).matching(identifier: identifier).count, 0,
                           "\(identifier) reached a post-ride screen — the placement rule is broken")
        }
    }

    @MainActor
    func testNothingALearnerAlreadyOwnsIsBehindTheOffer() {
        // HARD CONSTRAINT 3, asserted while it is still trivially true — which is exactly when
        // such a guard is cheapest to write and easiest to forget. The Ride Log, the word lists
        // and the stats are the learner's own data and must never sit behind a purchase.
        let app = XCUIApplication()
        app.launchIsolated(["NIHONGO_FAKE_ENTITLEMENT": "neverEstablished"])

        for (button, back) in [("journalButton", "journalBackButton"),
                               ("wordListsButton", "listsBackButton"),
                               ("statsButton", "statsBackButton")] {
            let entry = app.buttons[button]
            guard entry.waitForExistence(timeout: 10) else {
                XCTFail("the menu should show \(button)")
                continue
            }
            tapWhenSettled(entry)
            for identifier in ["roadRow", "buyRoadWest"] {
                XCTAssertEqual(app.descendants(matching: .any).matching(identifier: identifier).count, 0,
                               "\(identifier) appeared on the \(button) screen — a learner's own data is behind the offer")
            }
            let backButton = app.buttons[back]
            if backButton.waitForExistence(timeout: 5) { tapWhenSettled(backButton) }
        }
    }

    /// **The entrance must be tappable in its MIDDLE, not only on its text.**
    ///
    /// This pins a defect that shipped in v1.30 and made the sibling test above flaky rather
    /// than red. The strip's connectors are `Rectangle().frame(height: 2)`, so between the four
    /// stops there is a two-point line and a lot of empty space — and empty space in a stack is
    /// not content, so a plain `Button` does not hit-test it. Only the emoji, the stop labels
    /// and the caption row responded.
    ///
    /// Measured before it was fixed: a tap at the element's own centre left the app on the
    /// menu; a tap 28 points lower, on the caption, opened The Road. `element.tap()` chooses
    /// its own point, so whether a run passed depended on which side of that line it picked —
    /// which is why the same commit passed three times and failed six on one afternoon.
    ///
    /// So this taps the CENTRE explicitly. `element.tap()` cannot pin this property, because
    /// the thing being asserted is exactly the point it is free to choose.
    @MainActor
    func testTheMenuEntranceIsTappableInItsMiddleAndNotOnlyOnItsText() {
        let app = XCUIApplication()
        app.launchIsolated(["NIHONGO_FAKE_ENTITLEMENT": "neverEstablished",
                            "NIHONGO_FAKE_LIFETIME_METRES": "25000"])

        let entrance = app.buttons["menuRouteEntrance"]
        XCTAssertTrue(entrance.waitForExistence(timeout: 10),
                      "a rider at Kyōto should see the arrived route strip")
        settle(entrance)           // settle only — the tap that matters is the next line
        entrance.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["roadBackButton"].waitForExistence(timeout: 5),
                      "the middle of the entrance is dead to the touch — a rider tapping the "
                      + "road itself, which is the obvious target, gets nothing")
    }

    // MARK: The owned state

    @MainActor
    func testAnOwnedDeviceStillSeesTheRowAndStillHasRestore() {
        // The row NEVER disappears. Hiding it once owned looks tidy and takes the restore path
        // away from the one person who needs it: a buyer on a second device, or after a reinstall,
        // whose entitlement has not resolved. It changes what it SAYS, not whether it is there.
        let app = XCUIApplication()
        app.launchIsolated(["NIHONGO_FAKE_ENTITLEMENT": "verified"])
        openSettings(app)

        let row = app.buttons["roadRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "an owner lost the road row entirely")
        tapWhenSettled(row)
        XCTAssertTrue(app.buttons["restorePurchases"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["buyRoadWest"].exists,
                       "an owner is still being offered the thing they own")
    }
}
