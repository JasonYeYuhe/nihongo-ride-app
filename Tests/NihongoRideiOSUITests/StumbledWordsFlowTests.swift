import XCTest

/// The stumbled-word list, on a real device, through a real run.
///
/// The unit tests drive a real `GameSession` and prove the attribution: a refused keystroke's
/// position in the sentence's reading resolves back to the right word. What they cannot prove is
/// that the section reaches the screen — that `GameSummary` carries the trace across
/// `finishGame`, that the mode survives with it, and that the view's own conditions
/// (`.sentence`/`.dictation`, non-empty) let it render. Every one of those is app-layer wiring,
/// and the app layer has no unit test target.
///
/// This is the shape v1.23 §B kept finding: the piece that computes the answer was right, and
/// nothing checked that the answer was the one displayed.
final class StumbledWordsFlowTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// A key with no romaji mapping in any Japanese IME table, so it is refused wherever it is
    /// typed. Asserted rather than assumed: `mistakeCount` on the results screen has to move.
    private let refusedKey = "q"

    @MainActor
    func testSentenceRunNamesTheWordsThatStoppedYou() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["startButton"].waitForExistence(timeout: 15))

        // The romaji has to be on screen for the typist to know what is correct — a fresh
        // install defaults to "when stuck", which hides it. (Same reason the screenshot walk
        // does this; without it the run would type nothing and the section would be empty for
        // a reason that has nothing to do with what is under test.)
        let hints = app.segmentedControls.element(boundBy: 2)
        XCTAssertTrue(hints.waitForExistence(timeout: 5))
        hints.buttons.element(boundBy: 0).tap()

        let sentence = app.buttons["Sentence"]
        XCTAssertTrue(sentence.waitForExistence(timeout: 5), "no Sentence mode capsule")
        sentence.tap()

        app.buttons["startButton"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 15))
        sleep(1)

        // Two refusals at the same position: the matcher does not advance on a rejection, so
        // both land inside the sentence's first word, which is what makes them a stumble
        // rather than two unrelated slips (`minimumRefusals` is 2).
        app.typeText(refusedKey)
        app.typeText(refusedKey)

        // …then type the sentence out, so the run has real content and a real end.
        typeRemainingRomaji(app)

        app.buttons["pauseButton"].tap()
        let endRun = app.buttons["endRunButton"]
        XCTAssertTrue(endRun.waitForExistence(timeout: 5))
        endRun.tap()

        // Queried by the words on screen, not by an identifier. Neither the container's
        // accessibilityIdentifier nor one on the heading Text surfaces to XCUITest from this
        // screen — measured, twice — so asserting on an identifier here would be asserting on
        // something that is not there, and the heading a learner reads is the better anchor
        // anyway. Both languages, because the test must not silently pass by matching neither.
        let heading = app.staticTexts.matching(NSPredicate(format:
            "label IN %@", ["The words that stopped you", "这些词卡住了你",
                            "The words you could not catch", "这些词没听出来"])).firstMatch
        if !heading.waitForExistence(timeout: 10) {
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.lifetime = .keepAlways
            shot.name = "results-without-stumbled-words"
            add(shot)
            XCTFail("no stumbled-word section. STATIC TEXTS: " +
                    app.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " | "))
        }

        // The heading alone would render above an empty list. Each chip combines into one
        // element labelled "surface, reading" — that pairing IS the feature, so assert it, and
        // assert it is Japanese so an English label elsewhere on the screen cannot stand in.
        // Both collections, and the LEADING pair rather than the whole label.
        //
        // v1.24 made a resolvable chip actionable, which changed two things this query used to
        // depend on without saying so: the chip gained `.isButton`, so it is enumerated under
        // `buttons` and no longer under `staticTexts`, and its label gained a saved-state
        // suffix. An earlier draft also PREFIXED the label with "Save", which made every chip
        // invisible here — the test would have failed on a screen that rendered perfectly, and
        // only a simulator run would have said so. The label rule now lives in
        // `StumbleChipLabel` with unit tests (`StumbleChipLabelTests`) asserting exactly the
        // property matched below, so `swift test` catches the next such change.
        let labels = (app.staticTexts.allElementsBoundByIndex
                      + app.buttons.allElementsBoundByIndex).map(\.label)
        let chips = labels.filter { label in
            let parts = label.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 2, !parts[0].isEmpty, !parts[1].isEmpty else { return false }
            return parts.prefix(2).allSatisfy { $0.unicodeScalars.allSatisfy { $0.value > 0x3000 } }
        }
        XCTAssertFalse(chips.isEmpty,
                       "the section rendered with no words in it. ELEMENTS: " +
                       labels.joined(separator: " | "))
    }

    /// Types the current word's remaining romaji, once per word, until the run ends or the hint
    /// stops appearing. Reads the hint rather than carrying a romaji table, so it types what the
    /// app is actually asking for.
    @MainActor
    private func typeRemainingRomaji(_ app: XCUIApplication, words: Int = 3) {
        for _ in 0..<words {
            let hint = app.staticTexts["romajiHint"]
            guard hint.waitForExistence(timeout: 5) else { return }
            let romaji = hint.label.replacingOccurrences(of: "→ ", with: "")
            guard !romaji.isEmpty else { return }
            app.typeText(romaji)
            sleep(1)
        }
    }
}
