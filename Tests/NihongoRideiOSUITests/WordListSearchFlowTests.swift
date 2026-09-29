import XCTest

/// v1.35 §B6 — a word added to a list from search, on a real device.
///
/// The placement suite never visits Word Lists, so it proves nothing about this (the plan's
/// review said so, and was right). `swift test` covers the search itself and lays the result row
/// out at the accessibility sizes; what only a device can show is the wiring between them — that
/// the field takes the keyboard on a screen whose `KeyCaptureView` otherwise holds it with the
/// software keyboard suppressed, that typing reaches the query, that tapping a result goes through
/// the store and the word appears in the list below.
///
/// **How it finds things — identifiers, listed here because each one is load-bearing:**
/// * `wordListsButton` (menu) → `newListButton` (lists screen), then the native alert's own text
///   field and its Create button, by label in both languages;
/// * `practiceListButton` — proof the detail screen is the one on screen;
/// * `wordSearchOpen` (button), `wordSearchField` (text field), `wordSearchClose` (button);
/// * `wordSearchResult-n5-mizu` — each result row is ONE button whose identifier is
///   `wordSearchResult-<vocab id>`, its accessibility value "not in list" / "in list" (未加入 / 已加入);
/// * `removeWord-n5-mizu` — the remove button of a word in the list, `removeWord-<vocab id>`.
/// The no-results line is found by its words, not an identifier: an identifier on a `Text` did not
/// surface to XCUITest on the results screen (`StumbledWordsFlowTests`, measured twice), and the
/// line a learner reads is the better anchor anyway.
final class WordListSearchFlowTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

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

    private func dumpOnFailure(_ app: XCUIApplication, _ name: String) -> String {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.lifetime = .keepAlways
        shot.name = name
        add(shot)
        return (app.buttons.allElementsBoundByIndex.map { "\($0.identifier)=\($0.label)" }
                + app.staticTexts.allElementsBoundByIndex.map(\.label)).joined(separator: " | ")
    }

    @MainActor
    func testSearchingAndAddingPutsTheWordInTheList() throws {
        let app = XCUIApplication()
        app.launchIsolated()

        // Menu → Word Lists → a new list. An isolated launch starts with no lists of its own
        // (the default ★ list only), so the list under test is one this test made.
        let lists = app.buttons["wordListsButton"]
        XCTAssertTrue(lists.waitForExistence(timeout: 15), "the menu should show Word Lists")
        tapWhenSettled(lists)
        let newList = app.buttons["newListButton"]
        XCTAssertTrue(newList.waitForExistence(timeout: 5), "the lists screen should offer New list")
        tapWhenSettled(newList)

        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "New list should ask for a name")
        let name = alert.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("B6 search")
        let create = alert.buttons.matching(NSPredicate(format: "label IN {'Create', '创建'}")).firstMatch
        XCTAssertTrue(create.exists, "no Create button: \(alert.buttons.allElementsBoundByIndex.map(\.label))")
        create.tap()

        // Creating a list opens it.
        XCTAssertTrue(app.buttons["practiceListButton"].waitForExistence(timeout: 5),
                      "the new list's detail screen never appeared")

        // Open search. The field is focused when it appears, so the software keyboard comes up
        // WITHOUT a tap on the field — the screen's key-capture view, which suppresses that
        // keyboard, is removed while search is open. A tap here would hide exactly that defect.
        let open = app.buttons["wordSearchOpen"]
        XCTAssertTrue(open.waitForExistence(timeout: 5), "no Search the dictionary button")
        tapWhenSettled(open)
        let field = app.textFields["wordSearchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the search field never appeared")
        if !app.keyboards.firstMatch.waitForExistence(timeout: 5) {
            XCTFail("the keyboard did not come up for the search field. " + dumpOnFailure(app, "search-no-keyboard"))
        }
        // The key-capture view gone is also what makes the practice launchers leave: search
        // replaces them. Their absence is proof the panel, not the old screen, is showing.
        XCTAssertFalse(app.buttons["practiceListButton"].exists, "the launchers are still on screen with search open")

        // Romaji, so the query exercises the reading match and not only a gloss: the fixture
        // tests pin that "mizu" finds 水 (n5-mizu) first in the shipped corpus.
        app.typeText("mizu")
        let result = app.buttons["wordSearchResult-n5-mizu"]
        if !result.waitForExistence(timeout: 5) {
            XCTFail("typing mizu did not show 水. " + dumpOnFailure(app, "search-no-mizu"))
        }
        XCTAssertTrue(["not in list", "未加入"].contains(result.value as? String ?? ""),
                      "a word not yet in the list reads \(String(describing: result.value))")
        XCTAssertTrue(result.label.hasPrefix("水, みず, "), "the row's one VoiceOver label is \(result.label)")

        result.tap()

        // The row now says it is in the list, and the list below has the word.
        let inList = NSPredicate(format: "value IN {'in list', '已加入'}")
        expectation(for: inList, evaluatedWith: result)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(result.isEnabled, "a word already in the list can be added again")
        XCTAssertTrue(app.buttons["removeWord-n5-mizu"].waitForExistence(timeout: 5),
                      "水 was added but is not in the list. " + dumpOnFailure(app, "search-added-not-listed"))

        // A query that matches nothing says so, in words. Four deletes clear "mizu" (the field
        // kept focus through the add — the row is a button, not a text input).
        app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "zzqx")
        let none = app.staticTexts.matching(NSPredicate(format:
            "label BEGINSWITH 'No word in the dictionary matches' OR label BEGINSWITH '词库里没有'")).firstMatch
        if !none.waitForExistence(timeout: 5) {
            XCTFail("no empty-result line for zzqx. " + dumpOnFailure(app, "search-no-empty-state"))
        }

        // Done closes search; the launchers are back, the word is still in the list, and the
        // list now has something to practise.
        let done = app.buttons["wordSearchClose"]
        XCTAssertTrue(done.exists)
        done.tap()
        let practice = app.buttons["practiceListButton"]
        XCTAssertTrue(practice.waitForExistence(timeout: 5), "closing search did not bring the launchers back")
        XCTAssertTrue(practice.isEnabled, "a list holding 水 has nothing to practise")
        XCTAssertTrue(app.buttons["removeWord-n5-mizu"].exists, "水 left the list when search closed")
        XCTAssertFalse(app.textFields["wordSearchField"].exists, "the search field outlived Done")
    }
}
