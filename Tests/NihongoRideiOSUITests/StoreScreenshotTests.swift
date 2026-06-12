import XCTest

/// Walks the app and captures real-device store screenshots (menu, mid-game
/// with the software keyboard up, results, practice) in both UI languages.
/// Unlike the headless ImageRenderer path (which can't render native controls
/// — Picker/Toggle come out as placeholder bars), these are true screen pixels:
/// 1320×2868 on an iPhone 17 Pro Max, 2064×2752 on the 13" iPad portrait.
///
/// Run on demand (skipped otherwise):
///   NIHONGO_STORE_SHOTS=1 via the scheme/env, then export attachments:
///   xcrun xcresulttool export attachments --path <bundle>.xcresult --output-path <dir>
final class StoreScreenshotTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testCaptureStoreScreenshots() throws {
        guard ProcessInfo.processInfo.environment["NIHONGO_STORE_SHOTS"] != nil else {
            throw XCTSkip("set NIHONGO_STORE_SHOTS=1 to run the screenshot walk")
        }
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["startButton"].waitForExistence(timeout: 10))

        walk(app, lang: "en")

        // Flip the in-app language picker (2nd segmented control) to 中文.
        let language = app.segmentedControls.element(boundBy: 1)
        XCTAssertTrue(language.waitForExistence(timeout: 5))
        tapWhenSettled(language.buttons.element(boundBy: 1))

        walk(app, lang: "zh")
    }

    /// One full capture pass: menu → journey (typed mid-word, keyboard up) →
    /// results → practice. Ends back on the menu in journey mode.
    @MainActor
    private func walk(_ app: XCUIApplication, lang: String) {
        snap("\(lang)-1-menu")

        // Journey: type a couple of words so score/combo/progress are alive.
        tapWhenSettled(app.buttons["startButton"])
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        sleep(1)
        typeCurrentWord(app, hint: "romajiHint", fraction: 1.0)
        typeCurrentWord(app, hint: "romajiHint", fraction: 1.0)
        typeCurrentWord(app, hint: "romajiHint", fraction: 0.5)
        snap("\(lang)-2-game")

        // End the run by touch → results.
        app.buttons["pauseButton"].tap()
        XCTAssertTrue(app.buttons["endRunButton"].waitForExistence(timeout: 5))
        app.buttons["endRunButton"].tap()
        XCTAssertTrue(app.buttons["menuButton"].waitForExistence(timeout: 5))
        sleep(1)   // let the screen-lift transition settle before shooting
        snap("\(lang)-3-results")
        tapWhenSettled(app.buttons["menuButton"])
        XCTAssertTrue(app.buttons["startButton"].waitForExistence(timeout: 8))

        // Practice: washi-paper passage with a little typed progress. Selecting
        // Practice reveals two more picker rows, which pushes the start button
        // down — wait for it to settle or the tap lands on the old position.
        let mode = app.segmentedControls.firstMatch
        tapWhenSettled(mode.buttons.element(boundBy: 2))
        tapWhenSettled(app.buttons["startButton"])
        XCTAssertTrue(app.buttons["practiceNext"].waitForExistence(timeout: 10))
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 5)
        sleep(1)
        typeCurrentWord(app, hint: "practiceRomaji", fraction: 0.3)
        snap("\(lang)-4-practice")
        app.buttons["practiceDone"].tap()
        XCTAssertTrue(app.buttons["startButton"].waitForExistence(timeout: 8))
        mode.buttons.element(boundBy: 0).tap()   // back to journey for the next pass
    }

    /// Types the leading `fraction` of the current word's remaining romaji,
    /// read from the on-screen hint.
    @MainActor
    private func typeCurrentWord(_ app: XCUIApplication, hint: String, fraction: Double) {
        let hintText = app.staticTexts[hint]
        guard hintText.waitForExistence(timeout: 5) else { return }
        let romaji = hintText.label.replacingOccurrences(of: "→ ", with: "")
        guard !romaji.isEmpty else { return }
        let count = max(1, Int(Double(romaji.count) * fraction))
        app.typeText(String(romaji.prefix(count)))
        usleep(300_000)
    }

    @MainActor
    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Tap after the element's frame stops moving (mid-transition taps miss).
    @MainActor
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
}
