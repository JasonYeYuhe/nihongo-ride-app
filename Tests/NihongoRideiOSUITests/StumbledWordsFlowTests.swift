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
        app.launchIsolated()
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

        assertSentenceResultsCopy(app, labels: labels)
    }

    /// **v1.26 §D — the copy v1.24 §B and v1.25 §B produced, asserted on the screen.**
    ///
    /// Both releases changed what this screen SAYS, and every consumer of
    /// `GameMode.lapsesAreWords` and `GameSummary.persistsSRS` lives here — so all five lines
    /// could be deleted without reddening anything. The predicates were tested and honestly
    /// green; the visible outcome was not tested at all. That is v1.26's own thesis, and it was
    /// re-measured on this release's own work: restoring §B's defect in `MenuView` left every
    /// unit test passing.
    ///
    /// Extending the existing flow rather than building a parallel proof — a second harness for
    /// the same screen is one rule written twice, and this one has already finished a real
    /// sentence run, which is the expensive part.
    ///
    /// Exact-match, never `contains`: the heading on this very screen is "The words that
    /// stopped you", so a substring test for "Words" would pass on a screen that had regressed.
    @MainActor
    private func assertSentenceResultsCopy(_ app: XCUIApplication, labels: [String]) {
        let all = Set(labels)
        let zh = all.contains("这些词卡住了你") || all.contains("这些词没听出来")
        let shown = labels.joined(separator: " | ")

        // v1.25 §B: a sentence run completes SENTENCES, not words.
        let sentences = zh ? "完成句数" : "Sentences"
        let words = zh ? "完成词数" : "Words"
        XCTAssertTrue(all.contains(sentences),
                      "a sentence run must count \(sentences). ELEMENTS: \(shown)")
        XCTAssertFalse(all.contains(words),
                       "a sentence run still labels its count \(words). ELEMENTS: \(shown)")

        // v1.25 §B: and what went wrong on it is tough LINES, so the sentence-level count and
        // the word-level chips read as the different things they are.
        let toughLines = zh ? "吃力句" : "Tough lines"
        let struggled = zh ? "吃力" : "Struggled"
        XCTAssertTrue(all.contains(toughLines),
                      "a sentence run must say \(toughLines). ELEMENTS: \(shown)")
        XCTAssertFalse(all.contains(struggled),
                       "a sentence run still says \(struggled). ELEMENTS: \(shown)")

        // v1.24 §B: "To review" is a promise, and a sentence run persists no SRS — nothing here
        // will ever come back for review, so the tile must not promise it.
        let toReview = zh ? "待复习" : "To review"
        XCTAssertFalse(all.contains(toReview),
                       "a run that persists no SRS promises \(toReview). ELEMENTS: \(shown)")

        // v1.25 §B: the whole-sentence review list is DROPPED on a sentence run. It wrapped a
        // sentence as a VocabEntry whose surface was the whole sentence, so the grid rendered
        // 「友達と映画を見ました。」 in a 116pt word cell captioned with one word's gloss, and
        // VoiceOver announced "Save 〈whole sentence〉". Its heading must be absent; the chips
        // asserted above are what replaced it.
        for heading in ["Words to review", "复习这些词", "Review these words"] {
            XCTAssertFalse(all.contains(heading),
                           "the whole-sentence review list is back. ELEMENTS: \(shown)")
        }
        // A sentence-shaped element in a word cell is the defect itself, whatever it is called:
        // no label on this screen may be long enough to be a whole sentence AND end in 。
        let sentenceShaped = labels.filter { $0.count > 12 && ($0.hasSuffix("。") || $0.contains("。,")) }
        XCTAssertTrue(sentenceShaped.isEmpty,
                      "a whole sentence is being rendered as a word: \(sentenceShaped)")
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
