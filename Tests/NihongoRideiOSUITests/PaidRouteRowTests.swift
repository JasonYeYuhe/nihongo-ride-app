import XCTest

/// **Where the offer is, and — the harder half — where it is not.**
///
/// The placement is the one part of Stage 1 that no unit test can reach: "one row, in Settings, and
/// nowhere else" is a statement about the running app's screens. It is also the constraint most
/// likely to be quietly violated by a later edit, because adding a second entry point always looks
/// like an improvement to whoever is adding it.
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
    private func tapWhenSettled(_ element: XCUIElement) {
        var last = element.frame
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            usleep(250_000)
            let now = element.frame
            if now.equalTo(last) { break }
            last = now
        }
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

        // Not on the menu. The menu is where a rider starts a ride, and an offer there would be
        // the "no modal, no badge" discipline broken by the nearest available surface.
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "roadRow").count, 0,
                       "the offer row appears on the menu")

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

    // MARK: What must NOT happen anywhere else

    @MainActor
    func testTheResultsScreenCarriesNoPurchaseAffordance() {
        // The constraint most likely to be broken by a later edit, and the only thing that can
        // catch it is a screen-level assertion. v1.27 already fires the App Store rating prompt
        // after a completed ride; two asks landing on the same moment spends the goodwill of one
        // on the other, which is why the plan puts the offer deliberately far from it.
        let app = XCUIApplication()
        app.launchIsolated(["NIHONGO_FAKE_ENTITLEMENT": "neverEstablished"])

        let start = app.buttons["startButton"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        tapWhenSettled(start)

        // Finish the run the short way: pause and end it. What matters is reaching the results
        // screen, not how the ride went.
        let pause = app.buttons["pauseButton"]
        if pause.waitForExistence(timeout: 10) { tapWhenSettled(pause) }
        let end = app.buttons["endRunButton"]
        if end.waitForExistence(timeout: 5) { tapWhenSettled(end) }

        for identifier in ["roadRow", "buyRoadWest", "restorePurchases"] {
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
