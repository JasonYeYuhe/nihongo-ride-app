import XCTest

/// Regression tests for App Review rejection 2.1(a) (2026-06-10): on a
/// touch-only iPad the reviewer was "stuck on the first word screen" — the
/// on-screen keyboard never appeared and nothing on the game screen was
/// tappable. These tests run the real app in the iPad simulator and assert
/// the full touch path: keyboard appears, typing advances, pause/exit work
/// by touch, and Practice mode has tappable Next/Done.
///
/// NOTE: run with the simulator's "Connect Hardware Keyboard" OFF so the
/// software keyboard actually shows (`defaults write com.apple.iphonesimulator
/// ConnectHardwareKeyboard -bool false` before booting).
final class TouchFlowTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// Tap after the element's frame stops moving — screens slide in with a
    /// spring transition, and tapping a mid-flight button can miss.
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

    /// The exact rejected flow: launch → Start ride → keyboard MUST appear,
    /// typing the shown romaji MUST advance the word, and ⏸ → End run MUST
    /// return to the menu. No hardware keyboard involved.
    @MainActor
    func testJourneyIsFullyPlayableByTouch() {
        let app = XCUIApplication()
        app.launch()

        // Menu → start a ride.
        let start = app.buttons["startButton"]
        XCTAssertTrue(start.waitForExistence(timeout: 10), "menu should show Start ride")
        start.tap()

        // The on-screen keyboard must come up on its own (this was the bug).
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 10),
                      "software keyboard must appear automatically on the game screen")

        // Type the full romaji shown in the hint; the word must complete and
        // the HUD progress flip to 1/N — proving keystrokes reach the engine
        // end-to-end through the software keyboard.
        let hint = app.staticTexts["romajiHint"]
        XCTAssertTrue(hint.waitForExistence(timeout: 5), "romaji hint should be visible")
        let romaji = hint.label.replacingOccurrences(of: "→ ", with: "")
        XCTAssertFalse(romaji.isEmpty)
        app.typeText(romaji)

        let completedOne = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH '1/'")).firstMatch
        XCTAssertTrue(completedOne.waitForExistence(timeout: 5),
                      "typing the word's romaji should complete it (HUD 1/N)")

        // Pause and end the run — by touch only.
        let pause = app.buttons["pauseButton"]
        XCTAssertTrue(pause.waitForExistence(timeout: 5), "HUD should show a pause button on iPad")
        pause.tap()

        let endRun = app.buttons["endRunButton"]
        XCTAssertTrue(endRun.waitForExistence(timeout: 5), "pause overlay should offer End run")
        endRun.tap()

        // Results screen → back to menu (both are plain buttons).
        let menuButton = app.buttons["menuButton"]
        XCTAssertTrue(menuButton.waitForExistence(timeout: 5), "results should offer Menu")
        tapWhenSettled(menuButton)
        XCTAssertTrue(start.waitForExistence(timeout: 8), "should be back on the menu")
    }

    /// The Ride Log must open from the menu and return — by touch only.
    @MainActor
    func testJournalOpensAndReturnsByTouch() {
        let app = XCUIApplication()
        app.launch()

        let journal = app.buttons["journalButton"]
        XCTAssertTrue(journal.waitForExistence(timeout: 10), "menu should show a Ride Log button")
        tapWhenSettled(journal)

        let back = app.buttons["journalBackButton"]
        XCTAssertTrue(back.waitForExistence(timeout: 5), "journal should show a Back button")
        tapWhenSettled(back)

        XCTAssertTrue(app.buttons["startButton"].waitForExistence(timeout: 8),
                      "Back should land on the menu")
    }

    /// Practice mode must be controllable by touch: Next advances the passage,
    /// Done returns to the menu (these were Enter/Esc-only before).
    @MainActor
    func testPracticeNextAndDoneByTouch() {
        let app = XCUIApplication()
        app.launch()

        // Switch the mode picker to Practice (3rd segment), then start.
        let modePicker = app.segmentedControls.firstMatch
        XCTAssertTrue(modePicker.waitForExistence(timeout: 10))
        let segments = modePicker.buttons
        XCTAssertGreaterThanOrEqual(segments.count, 3, "mode picker should have 3 segments")
        segments.element(boundBy: 2).tap()

        app.buttons["startButton"].tap()

        let next = app.buttons["practiceNext"]
        XCTAssertTrue(next.waitForExistence(timeout: 10), "Practice should show a Next button on iPad")
        next.tap()   // must not crash; advances passage

        let done = app.buttons["practiceDone"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()

        XCTAssertTrue(app.buttons["startButton"].waitForExistence(timeout: 5),
                      "Done should land back on the menu")
    }
}
