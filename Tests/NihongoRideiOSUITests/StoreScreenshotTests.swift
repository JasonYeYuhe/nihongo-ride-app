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
        app.launchIsolated()
        XCTAssertTrue(app.buttons["startButton"].waitForExistence(timeout: 10))

        // v1.16 §A: a fresh install defaults to "when stuck", which hides the romaji — and the
        // walk READS that romaji to know what to type. Without this the capture would not
        // fail, it would silently produce game and practice shots with nothing typed.
        selectAlwaysHints(app)

        walk(app, lang: "en")

        // Flip the in-app language picker to 中文.
        //
        // **This selected the JLPT LEVEL picker, not the language picker.** Index 1 is the
        // level row (`MenuView.swift:110`); the language picker is index 0 (`:97`). Tapping
        // its second button changed the level and left the app in English, so the whole zh
        // pass would have captured English screens under zh-* filenames — the worst kind of
        // failure for a screenshot walk, because the output looks plausible.
        //
        // Matched by accessibility label instead, which is the technique `selectAlwaysHints`
        // in this same file already uses and the one `TouchFlowTests` adopted for the same
        // reason. Positional indices into `segmentedControls` are a claim about layout that
        // nothing on this screen keeps.
        let language = app.segmentedControls.matching(
            NSPredicate(format: "label IN {'Language', '界面语言'}")).firstMatch
        XCTAssertTrue(language.waitForExistence(timeout: 5), "language picker not found")
        tapWhenSettled(language.buttons.element(boundBy: 1))

        selectAlwaysHints(app)   // the setting persists, but assert it rather than assume
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
        // **The same defect one file over, and it is the one this release already diagnosed.**
        // `segmentedControls.firstMatch` is the LANGUAGE picker, not the mode selector: the
        // mode row stopped being a segmented control when it grew to six modes and became
        // capsule Buttons (`MenuView.swift:58-78`, "a segmented control cannot label six").
        // `boundBy: 2` is out of range on a two-segment picker, so the walk aborted partway
        // through the English pass and the zh pass was unreachable.
        //
        // v1.26 fixed this in `TouchFlowTests` and shipped it in the same commit that left it
        // here. A fix applied to one call site is not a fix — this project's own rule, missed
        // in the release that quotes it.
        let practiceLabel = lang == "zh" ? "练习" : "Practice"
        let mode = app.buttons[practiceLabel]
        XCTAssertTrue(mode.waitForExistence(timeout: 5), "no \(practiceLabel) mode button")
        tapWhenSettled(mode)
        tapWhenSettled(app.buttons["startButton"])
        XCTAssertTrue(app.buttons["practiceNext"].waitForExistence(timeout: 10))
        _ = app.keyboards.firstMatch.waitForExistence(timeout: 5)
        sleep(1)
        typeCurrentWord(app, hint: "practiceRomaji", fraction: 0.3)
        snap("\(lang)-4-practice")
        app.buttons["practiceDone"].tap()
        XCTAssertTrue(app.buttons["startButton"].waitForExistence(timeout: 8))
        tapWhenSettled(mode.buttons.element(boundBy: 0))   // back to journey

        // Ride Log: real history from the runs above.
        tapWhenSettled(app.buttons["journalButton"])
        XCTAssertTrue(app.buttons["journalBackButton"].waitForExistence(timeout: 5))
        sleep(1)
        snap("\(lang)-5-journal")
        tapWhenSettled(app.buttons["journalBackButton"])
        XCTAssertTrue(app.buttons["startButton"].waitForExistence(timeout: 8))
    }

    /// Puts the assistance policy on "always", by accessibility label so it survives the row
    /// moving. Found by label rather than index because the menu's segmented-control count
    /// changes with the selected mode.
    @MainActor
    private func selectAlwaysHints(_ app: XCUIApplication) {
        let picker = app.segmentedControls.matching(
            NSPredicate(format: "label IN {'Romaji assistance', '罗马字提示'}")).firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "assistance picker not found")
        tapWhenSettled(picker.buttons.element(boundBy: 0))
    }

    /// Types the leading `fraction` of the current word's remaining romaji,
    /// read from the on-screen hint.
    ///
    /// Fails loudly when the hint is missing. It used to return silently, which meant a
    /// change that hid the romaji (v1.16 §A did exactly that by default) degraded every store
    /// screenshot instead of breaking the test.
    @MainActor
    private func typeCurrentWord(_ app: XCUIApplication, hint: String, fraction: Double) {
        let hintText = app.staticTexts[hint]
        XCTAssertTrue(hintText.waitForExistence(timeout: 5),
                      "\(hint) missing — is the assistance policy on 'always'?")
        let romaji = hintText.label.replacingOccurrences(of: "→ ", with: "")
        XCTAssertFalse(romaji.isEmpty, "\(hint) was empty")
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
