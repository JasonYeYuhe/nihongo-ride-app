import Testing
import Foundation
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
import VocabKit
import WordListsKit
@testable import NihongoRideApp

/// v1.35 §B6 — search the corpus from a word list, and add a result to THIS list.
///
/// **What these can and cannot prove, stated first.** The search is VocabKit's and is tested
/// there (`WordSearchTests`: fixture rules, the retired words, every hint's reading, timing). This
/// file holds the app layer: the row's words and states (section 1); the row itself laid out at
/// the five accessibility sizes and read back from the pixels (section 2) — possible because the
/// row takes its text size as a parameter, since a hosted view on macOS ignores
/// `dynamicTypeSize` (measured 2026-09-29, `ListDetailView.bodyPoints`); and source pins for what
/// only a device can exercise — focus, Esc, the key-capture view stepping aside — which
/// `WordListSearchFlowTests` (XCUITest, iPhone) drives for real (section 3). Whether the field
/// takes the keyboard on a phone is that test's and the simulator pass's question, not this
/// file's. Added in the review (sections 4–6): pins that the screen calls the copy and cap
/// functions section 1 tests; the VoiceOver status announcement, table-tested; and the contrast of
/// every colour the row and the panel draw, computed with `V133SContrastTests`' model over the
/// backdrops read from the source, with the disabled rows' pixels measured.
@MainActor
@Suite("v1.35 §B6: search from Word Lists")
struct V135B6WordSearchTests {

    // MARK: 1. Words and states

    /// Mutation, 2026-09-29: `wordCount > cap` in place of `>=` → red on the 500 row.
    @Test("a row can add until the list is at its cap, and never a word it already holds")
    func rowState() {
        let cap = WordListStore.maxWordsPerList
        #expect(cap == 500, "the cap moved; the notice and this test say 500")
        #expect(WordSearchResultRow.state(inList: false, wordCount: 0, cap: cap) == .addable)
        #expect(WordSearchResultRow.state(inList: false, wordCount: 499, cap: cap) == .addable)
        #expect(WordSearchResultRow.state(inList: false, wordCount: 500, cap: cap) == .listFull)
        // A grandfathered default list can be over the cap (`seedDefaultIDs`); still full.
        #expect(WordSearchResultRow.state(inList: false, wordCount: 612, cap: cap) == .listFull)
        #expect(WordSearchResultRow.state(inList: true, wordCount: 500, cap: cap) == .inList)
        #expect(WordSearchResultRow.state(inList: true, wordCount: 3, cap: cap) == .inList)
    }

    /// The store refuses the 501st word itself; the row's `.listFull` is the UI saying so before
    /// the tap rather than after it.
    @Test("control: the store refuses a word past the cap, which is what .listFull mirrors")
    func storeRefusesPastTheCap() {
        var store = WordListStore()
        let list = try! store.createList(name: "full").get()
        for n in 0..<WordListStore.maxWordsPerList { store.addWord("w\(n)", to: list.id) }
        guard case .failure(let error) = store.addWord("one-more", to: list.id) else {
            Issue.record("the store took a word past the cap")
            return
        }
        #expect(error == .wordCapReached(max: 500))
        #expect(ListsView.message(for: .wordCapReached(max: 500), zh: false) == "This list is full (500 words).")
    }

    @Test("VoiceOver: one label with word, reading and gloss; a value for the state; an add action")
    func accessibilityWords() {
        #expect(WordSearchResultRow.accessibilityLabel(surface: "水", reading: "みず", gloss: "water") == "水, みず, water")
        #expect(WordSearchResultRow.accessibilityLabel(surface: "コーヒー", reading: nil, gloss: "咖啡") == "コーヒー, 咖啡")
        let values: [(WordSearchResultRow.State, String, String)] = [
            (.addable, "not in list", "未加入"), (.inList, "in list", "已加入"), (.listFull, "list is full", "词单已满"),
        ]
        for (state, en, zh) in values {
            #expect(WordSearchResultRow.accessibilityValue(state, zh: false) == en)
            #expect(WordSearchResultRow.accessibilityValue(state, zh: true) == zh)
        }
        #expect(WordSearchResultRow.addActionName(zh: false) == "Add to list")
        #expect(WordSearchResultRow.addActionName(zh: true) == "加入词单")
    }

    /// The same membership words the add-to-lists sheet reads out, so a learner hears one
    /// vocabulary for "this word is in this list" on both screens. Read from its source.
    @Test("the in-list / not-in-list values are the add-to-lists sheet's")
    func membershipWordsMatchTheSheet() throws {
        let sheet = try V133LAccessibilityLayoutTests.body("ListsView.swift", "var body: some View",
                                                           after: "struct AddToListsSheet")
        #expect(sheet.contains(#"(zh ? "已加入" : "in list") : (zh ? "未加入" : "not in list")"#))
    }

    @Test("the empty list says search is a way to fill it, in both languages, and still names ★")
    func emptyStateMentionsSearch() {
        let en = ListDetailView.emptyStateText(zh: false)
        let zh = ListDetailView.emptyStateText(zh: true)
        #expect(en == "No words yet. Search the dictionary to add some, or tap ★ during a ride or on the results screen.")
        #expect(zh == "这个词单还没有词。可以搜索词库来添加,也可以在游戏或结算页点 ★ 收藏。")
    }

    /// The copy names the button by its words, so the button must still say them.
    @Test("the button the empty state names is labelled with those words")
    func emptyStateNamesTheButton() throws {
        let button = Self.collapsed(try V133LAccessibilityLayoutTests.body(
            "ListsView.swift", "private var searchOpenButton", after: "struct ListDetailView"))
        #expect(button.contains(#"Label(zh ? "搜索词库" : "Search the dictionary", systemImage: "magnifyingglass")"#))
        #expect(ListDetailView.emptyStateText(zh: false).contains("Search the dictionary"))
        #expect(ListDetailView.emptyStateText(zh: true).contains("搜索词库"))
    }

    @Test("no results names the query; the full notice names the cap and the way out")
    func panelCopy() {
        #expect(ListDetailView.noResults("zzqx", zh: false) == "No word in the dictionary matches “zzqx”. Try kana, romaji, kanji or a meaning.")
        #expect(ListDetailView.noResults("zzqx", zh: true) == "词库里没有和“zzqx”匹配的词。可以试试假名、罗马字、汉字或词义。")
        #expect(ListDetailView.fullNotice(zh: false) == "This list is full (500 words). Remove a word to add another.")
        #expect(ListDetailView.fullNotice(zh: true) == "该词单已满(500 词)。移除一个词后才能再添加。")
    }

    // MARK: 2. The row at the accessibility sizes

    /// Body text at each accessibility size ÷ 17, Apple's Dynamic Type table — the same values
    /// `V133GRideAndDrillLayoutTests.accessibilityScales` copies.
    static let scales: [CGFloat] = [1] + V133GRideAndDrillLayoutTests.accessibilityScales.map(\.body)

    /// The column a row gets: the screen's width less `ListDetailView`'s phone padding (22 each
    /// side, read from the source below) — a 402pt iPhone 17 Pro and a 320pt Display Zoom phone.
    static let widths: [CGFloat] = [402 - 44, 320 - 44]

    struct Worst {
        let surface: String
        let reading: String
        let glossEN: String
        let glossZH: String
    }

    /// The corpus's longest written form, longest reading shown under a different written form,
    /// and longest gloss line in each language — combined into one row, which is harsher than any
    /// real one. Read through `VocabStore`, so it is the population the screen shows.
    static let worst: Worst = {
        let entries = VocabStore.shared.entries
        func longest(_ values: [String]) -> String {
            values.max { $0.count != $1.count ? $0.count < $1.count : $0 > $1 } ?? ""
        }
        return Worst(surface: longest(entries.map(\.surface)),
                     reading: longest(entries.filter { $0.surface != $0.kana }.map(\.kana)),
                     glossEN: longest(entries.map { $0.gloss(for: "en") }),
                     glossZH: longest(entries.map { $0.gloss(for: "zh") }))
    }()

    @Test("the worst row is what this file says it is")
    func worstRowIsTheCorpus() throws {
        let worst = Self.worst
        #expect(worst.surface.count == 9 && worst.reading.count == 9,
                "surface \(worst.surface) \(worst.surface.count), reading \(worst.reading) \(worst.reading.count)")
        #expect(worst.glossEN.count >= 80, "the longest English gloss line is \(worst.glossEN.count): \(worst.glossEN)")
        #expect(worst.glossZH.count >= 20, "the longest Chinese gloss line is \(worst.glossZH.count): \(worst.glossZH)")
        // The widths assume the detail screen's phone padding; re-measure if it moves.
        let body = try V133LAccessibilityLayoutTests.body("ListsView.swift", "var body: some View",
                                                          after: "struct ListDetailView")
        #expect(body.contains(".padding(isPhoneIdiom ? 22 : 40)"))
    }

    #if canImport(AppKit)
    @MainActor
    static func row(_ surface: String, _ reading: String?, _ gloss: String, scale: CGFloat,
                    state: WordSearchResultRow.State = .addable) -> some View {
        WordSearchResultRow(surface: surface, reading: reading, gloss: gloss, state: state, zh: false,
                            stacked: scale > 1, scale: scale, add: {})
    }

    /// Whether the last character of `text` is drawn: replacing it changes the pixels. Truncation
    /// cuts the tail, so the tail is the character to ask about.
    @MainActor
    static func lastIsDrawn(_ text: String, width: CGFloat,
                            _ view: (String) -> some View) -> Bool {
        guard let base = V134B5RomajiHintTests.render(view(text), width: width, height: nil) else { return false }
        let changed = String(text.dropLast()) + (text.last == "#" ? "@" : "#")
        guard let other = V134B5RomajiHintTests.render(view(changed), width: width, height: nil) else { return false }
        return base != other
    }

    /// The instrument, calibrated: the worst English gloss on one line (`lineLimit(1)`, what the
    /// list's own word rows use) loses its tail at the default size in the phone column, and the
    /// same Text allowed to wrap draws it. So a `true` below is a real "drawn", not a blind one.
    @MainActor
    @Test("control: the instrument sees a gloss cut by a line limit")
    func instrumentControl() {
        let gloss = Self.worst.glossEN
        func text(_ lineLimit: Int?) -> (String) -> AnyView {
            // White, as the row draws it: the renderer's background is black, and Text's default
            // colour on it draws nothing a pixel comparison could see (measured: the first
            // version of this control had no colour and its "wraps" half failed).
            { s in AnyView(Text(s).font(.system(size: 14)).foregroundStyle(.white).lineLimit(lineLimit)
                .fixedSize(horizontal: false, vertical: true)) }
        }
        #expect(!Self.lastIsDrawn(gloss, width: 358, text(1)), "control: a one-line gloss should lose its tail")
        #expect(Self.lastIsDrawn(gloss, width: 358, text(nil)), "control: a wrapping gloss should draw its tail")
    }

    /// Every line of the worst row, at the default size and each accessibility size, in both
    /// languages' glosses, in both phone columns: the last character of the word, the reading and
    /// the gloss is drawn. And the row grows rather than clips: taller at AX5 than at the default.
    /// Mutations, 2026-09-29, each red here (and in `rowGetsTheScale`'s pin): `.lineLimit(1)` on
    /// the gloss; `.lineLimit(1)` on the word. Removing the gloss's
    /// `.fixedSize(horizontal: false, vertical: true)` is red in `rowIsNotClippedToAFixedHeight`
    /// instead — offered room, a wrapping Text draws whole with or without it.
    @MainActor
    @Test("the worst row draws every line whole at every size, in both languages")
    func worstRowIsWhole() throws {
        let worst = Self.worst
        for width in Self.widths {
            for scale in Self.scales {
                for gloss in [worst.glossEN, worst.glossZH] {
                    let label = "\(width)pt at ×\(String(format: "%.2f", scale)), gloss \(gloss.prefix(12))…"
                    #expect(Self.lastIsDrawn(worst.surface, width: width) { Self.row($0, worst.reading, gloss, scale: scale) },
                            "\(label): the word's last character is not drawn")
                    #expect(Self.lastIsDrawn(worst.reading, width: width) { Self.row(worst.surface, $0, gloss, scale: scale) },
                            "\(label): the reading's last character is not drawn")
                    #expect(Self.lastIsDrawn(gloss, width: width) { Self.row(worst.surface, worst.reading, $0, scale: scale) },
                            "\(label): the gloss's last character is not drawn")
                }
            }
        }
        let small = V134B5RomajiHintTests.laidOut(Self.row(worst.surface, worst.reading, worst.glossEN, scale: 1),
                                                  width: 358, height: nil)
        let ax5 = V134B5RomajiHintTests.laidOut(Self.row(worst.surface, worst.reading, worst.glossEN,
                                                         scale: try #require(Self.scales.last)),
                                                width: 358, height: nil)
        #expect(ax5.height > 3 * small.height, "AX5 \(ax5.height)pt against \(small.height)pt at the default size")
        #expect(ax5.width <= 358 && small.width <= 358, "the row is wider than its column")
    }

    /// The row's check and disabled states draw too — the state is the icon, and a row that drew
    /// the same pixels for "add" and "in list" would say nothing to a sighted learner.
    @MainActor
    @Test("added, addable and full rows look different")
    func statesAreVisible() {
        func pixels(_ state: WordSearchResultRow.State) -> V134B5RomajiHintTests.Bitmap? {
            V134B5RomajiHintTests.render(Self.row("水", "みず", "water", scale: 1, state: state), width: 358, height: nil)
        }
        let addable = pixels(.addable), inList = pixels(.inList), full = pixels(.listFull)
        #expect(addable != nil && addable != inList && addable != full && inList != full)
    }

    /// Offered only one default-size line of height, as a squeezed stack would offer it, the row
    /// still takes the height its text needs: it cannot be clipped by its container.
    @MainActor
    @Test("the row takes the height its text needs")
    func rowIsNotClippedToAFixedHeight() throws {
        let worst = Self.worst
        let ax5 = try #require(Self.scales.last)
        let offered = V134B5RomajiHintTests.laidOut(Self.row(worst.surface, worst.reading, worst.glossEN, scale: ax5),
                                                    width: 358, height: 40)
        let free = V134B5RomajiHintTests.laidOut(Self.row(worst.surface, worst.reading, worst.glossEN, scale: ax5),
                                                 width: 358, height: nil)
        #expect(offered.height == free.height, "offered 40pt it took \(offered.height), free \(free.height)")
    }
    #endif

    // MARK: 3. Pins — what only a device can exercise

    static func collapsed(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    static func detail(_ declaration: String) throws -> String {
        collapsed(try V133LAccessibilityLayoutTests.body("ListsView.swift", declaration, after: "struct ListDetailView"))
    }

    /// The key-capture view claims focus when it joins the window and, on iOS, re-claims it for
    /// five seconds and on every activation — so it is absent, not idle, while search is open.
    /// Mutation, 2026-09-29: dropping `&& !searchIsShowing` → red.
    @Test("the key-capture view is removed while search is open")
    func keyCaptureStepsAside() throws {
        let body = try Self.detail("var body: some View")
        #expect(body.contains("if !Screenshotter.isCapturing && !searchIsShowing { KeyCaptureView("),
                "ListDetailView's KeyCaptureView is no longer conditioned on search being closed")
        let showing = try Self.detail("private var searchIsShowing")
        #expect(showing.contains("searching && (list.map { !$0.deleted } ?? false)"),
                "the capture view's condition no longer matches when the panel is drawn")
        #expect(body.contains("if let list, !list.deleted { if searching { searchPanel(list) }"),
                "the panel is drawn under a different condition than searchIsShowing states")
        #expect(body.components(separatedBy: "KeyCaptureView(").count == 2, "a second KeyCaptureView appeared")
        // And the retry loop this is about is still what the comment says it is.
        let capture = try String(contentsOf: HorizontalTextFitTests.appDirectory
            .appendingPathComponent("KeyCaptureView.swift"), encoding: .utf8)
        #expect(capture.contains("retriesLeft = 20") && capture.contains("withTimeInterval: 0.25"),
                "KeyCaptureUIView's retry loop changed; re-read ListDetailView's comment")
    }

    /// Esc closes search on both platforms: the cancel shortcut on a cancel-role button (the
    /// rename alert's Cancel), and `onExitCommand` on macOS behind it.
    @Test("Done is the cancel action and Esc reaches it")
    func escapeClosesSearch() throws {
        let close = try Self.detail("private var searchCloseButton")
        #expect(close.contains("Button(role: .cancel, action: closeSearch)"))
        #expect(close.contains(".keyboardShortcut(.cancelAction)"))
        #expect(close.contains(#".accessibilityIdentifier("wordSearchClose")"#))
        let panel = try Self.detail("private func searchPanel")
        #expect(panel.contains(".onExitCommand(perform: closeSearch)"))
        let closeSearch = try Self.detail("private func closeSearch")
        #expect(closeSearch.contains("searchFocused = false") && closeSearch.contains("searching = false")
                && closeSearch.contains(#"query = """#))
    }

    @Test("the field is focused when it appears, and is the one the UI test types into")
    func fieldFocus() throws {
        let field = try Self.detail("private var searchField")
        #expect(field.contains(".focused($searchFocused)"))
        #expect(field.contains("searchFocused = true"))
        #expect(field.contains(#".accessibilityIdentifier("wordSearchField")"#))
        #expect(field.contains(".autocorrectionDisabled()"))
    }

    /// The row gets the learner's text size and the accessibility-size arrangement from the
    /// screen — the two inputs section 2 varies. Mutation, 2026-09-29: `scale: 1` → red.
    @Test("the row is handed the Dynamic Type scale and the stacked layout at the accessibility sizes")
    func rowGetsTheScale() throws {
        let file = try #require(try CallSiteScanner.shippedSources.get()
            .first { $0.path == "Sources/NihongoRideApp/ListsView.swift" })
        let code = Self.collapsed(file.allCodeWithStrings)
        #expect(code.contains("@ScaledMetric(relativeTo: .body) private var bodyPoints: CGFloat = 17"))
        let panel = try Self.detail("private func searchPanel")
        #expect(panel.contains("stacked: typeSize.isAccessibilitySize, scale: bodyPoints / 17,"))
        #expect(panel.contains(#".accessibilityIdentifier("wordSearchResult-\(entry.id)")"#))
        #expect(panel.contains("model.vocab.search(") == false, "search runs in onChange, not on every body evaluation")
        let body = try Self.detail("var body: some View")
        #expect(body.contains("results = model.vocab.search(new, limit: Self.searchLimit)"))
        // The row's three lines wrap and never cut.
        let row = try #require(file.typeBodies(named: "WordSearchResultRow").first)
        let rowCode = Self.collapsed(String(decoding: file.codeWithStrings[row], as: UTF8.self))
        #expect(!rowCode.contains("lineLimit"), "a line limit in the result row can cut the word or the gloss")
        #expect(rowCode.components(separatedBy: ".fixedSize(horizontal: false, vertical: true)").count == 4)
    }

    /// An add is the store's add: the save, the read-only refusal and the sync enqueue are the ones
    /// every other add gets. Mutation, 2026-09-29: calling `toggleWord` instead (which would REMOVE
    /// a word tapped twice) → red here.
    @Test("adding goes through AppModel.addWord and surfaces its error")
    func addUsesTheStore() throws {
        let add = try Self.detail("private func add(")
        #expect(add.contains("if let error = model.addWord(vocabID, to: listID) {"))
        #expect(add.contains("errorMessage = ListsView.message(for: error, zh: zh)"))
        #expect(!add.contains("toggleWord"))
        let open = try Self.detail("private var searchOpenButton")
        #expect(open.contains(".disabled(model.wordListsReadOnly)"))
        #expect(open.contains(#".accessibilityIdentifier("wordSearchOpen")"#))
        let row = try Self.detail("private func wordRow")
        #expect(row.contains(#".accessibilityIdentifier("removeWord-\(id)")"#))
    }

    /// The XCUITest finds everything by these identifiers; both sides are read, so renaming one
    /// without the other is red here instead of on the simulator. And the runner runs it on the
    /// iPhone — the invocation, not a comment. Mutation, 2026-09-29: the `-only-testing` line
    /// removed from the script → red.
    @Test("the UI test's identifiers exist, and the runner runs it on the iPhone")
    func uiTestIsWired() throws {
        let root = CallSiteScanner.repoRoot
        // Both read with comments blanked (strings kept): the first version read them raw, and a
        // commented-out identifier passed. Mutation, 2026-09-29: `// .accessibilityIdentifier(
        // "wordSearchOpen")` in ListsView → red; the same line commented in the UI test → red.
        let uiTest = CallSiteScanner.File(
            path: "WordListSearchFlowTests.swift",
            source: try String(contentsOf: root.appendingPathComponent(
                "Tests/NihongoRideiOSUITests/WordListSearchFlowTests.swift"), encoding: .utf8)).allCodeWithStrings
        let source = CallSiteScanner.File(
            path: "ListsView.swift",
            source: try String(contentsOf: HorizontalTextFitTests.appDirectory
                .appendingPathComponent("ListsView.swift"), encoding: .utf8)).allCodeWithStrings
        for identifier in ["wordSearchOpen", "wordSearchField", "wordSearchClose", "newListButton", "practiceListButton"] {
            #expect(uiTest.contains("\"\(identifier)\""), "the UI test does not use \(identifier)")
            #expect(source.contains(".accessibilityIdentifier(\"\(identifier)\")"), "ListsView has no \(identifier)")
        }
        #expect(uiTest.contains(#"app.buttons["wordSearchResult-n5-mizu"]"#)
                && source.contains(#".accessibilityIdentifier("wordSearchResult-\(entry.id)")"#))
        #expect(uiTest.contains(#"app.buttons["removeWord-n5-mizu"]"#)
                && source.contains(#".accessibilityIdentifier("removeWord-\(id)")"#))
        #expect(VocabStore.shared.search("mizu", limit: 1).first?.id == "n5-mizu",
                "the UI test types mizu and expects n5-mizu at the top")

        // The script is shell, not Swift: read raw, and its `-only-testing` line must not be a
        // `#` comment.
        let script = try String(contentsOf: root.appendingPathComponent("scripts/run_ios_placement_tests.sh"),
                                encoding: .utf8)
        let iPhone = try #require(script.range(of: "caffeinate -d -i xcodebuild test").map { start in
            script[start.lowerBound..<(script.range(of: "IPHONE_STATUS=$?")?.lowerBound ?? script.endIndex)]
        })
        #expect(iPhone.contains("-only-testing:NihongoRideiOSUITests/WordListSearchFlowTests \\"))
        #expect(!iPhone.split(separator: "\n").contains {
            $0.contains("WordListSearchFlowTests") && $0.trimmingCharacters(in: .whitespaces).hasPrefix("#")
        }, "the UI test's -only-testing line is commented out")
        #expect(iPhone.contains("name=$SIM_NAME"), "the first invocation is no longer the iPhone's")
        #expect(uiTest.contains("final class WordListSearchFlowTests: XCTestCase"))
        #expect(script.contains("That is all 14 methods in the target."))
    }

    // MARK: 4. The view uses what section 1 tests

    /// Section 1 tests `fullNotice`, `state(inList:wordCount:cap:)`, `noResults` and
    /// `emptyStateText` as functions; these pins say the screen calls them, where it should, read
    /// with comments blanked. Mutations, 2026-09-29, each red: `if full` → `if false`; the row's
    /// `wordCount: list.ids.count` → `wordCount: 0`; the empty state's text replaced by the old
    /// ★-only literal; `.disabled(state != .addable)` removed from the row.
    @Test("the panel shows the cap notice and disables rows at the cap; the empty state and no-results use their copy")
    func capAndCopyAreWired() throws {
        let panel = try Self.detail("private func searchPanel")
        #expect(panel.contains("let full = list.ids.count >= WordListStore.maxWordsPerList"))
        #expect(panel.contains("if full { Text(Self.fullNotice(zh: zh))"))
        #expect(panel.contains("state: WordSearchResultRow.state(inList: inList, wordCount: list.ids.count, cap: WordListStore.maxWordsPerList),"))
        #expect(panel.contains("let inList = members.contains(entry.id)") && panel.contains("let members = Set(list.ids)"))
        #expect(panel.contains("} else if results.isEmpty { Text(Self.noResults(trimmed, zh: zh))"))
        #expect(panel.contains("if results.count == Self.searchLimit {"))
        let file = try #require(try CallSiteScanner.shippedSources.get()
            .first { $0.path == "Sources/NihongoRideApp/ListsView.swift" })
        let row = try #require(file.typeBodies(named: "WordSearchResultRow").first)
        let rowCode = Self.collapsed(String(decoding: file.codeWithStrings[row], as: UTF8.self))
        #expect(rowCode.contains(".disabled(state != .addable)"))
        #expect(rowCode.contains("if state == .addable { Button(Self.addActionName(zh: zh), action: add) }"))
        let empty = try Self.detail("private var emptyState")
        #expect(empty.contains("Text(Self.emptyStateText(zh: zh))"))
        let body = try Self.detail("var body: some View")
        #expect(body.contains("if list.ids.isEmpty { if !searching { emptyState } }"),
                "the empty state is drawn somewhere other than an empty live list with search closed")
        #expect(body.contains("} else { unavailableState }"), "a gone list shows something other than unavailableState")
        #expect(body.components(separatedBy: "emptyState").count == 2, "emptyState is drawn twice")
    }

    /// A list that is gone draws no search button (the panel and the launchers are both under
    /// `if let list, !list.deleted`), so its line must not send the learner to one. It used to
    /// be `emptyState`, which does.
    @Test("a gone list's line names no button it does not draw, in both languages")
    func unavailableCopy() {
        let en = ListDetailView.unavailableText(zh: false)
        let zh = ListDetailView.unavailableText(zh: true)
        #expect(en == "This list isn't here any more — it may have been deleted on another device. Go back to see your lists.")
        #expect(zh == "这个词单已不存在,可能已在另一台设备上删除。返回即可查看你的词单。")
        for text in [en, zh] {
            #expect(!text.contains("Search") && !text.contains("搜索") && !text.contains("★"), "\(text)")
        }
    }

    // MARK: 5. VoiceOver hears the result list appear and empty (WCAG 4.1.3)

    /// Table: every transition between nothing typed, no match and a count. Spoken only when the
    /// set goes from none (or nothing typed) to some, or from anything to none; never when a count
    /// moves while there are results, nor on clearing the field. Mutation, 2026-09-29: the
    /// `(.some, .some)` case removed → red on the 12 → 3 row (every keystroke would speak).
    @Test("the announcement fires on none → some and some → none only, with the count or 'no words match'")
    func announcementTable() {
        typealias O = ListDetailView.SearchOutcome
        let limit = ListDetailView.searchLimit
        let rows: [(O, O, String?, String?)] = [
            (.idle, .idle, nil, nil),
            (.idle, .some(1), "1 word found.", "找到 1 个词。"),
            (.idle, .some(3), "3 words found.", "找到 3 个词。"),
            (.idle, .some(limit), "Showing the first 50 words.", "显示前 50 个词。"),
            (.idle, .none, "No words match.", "没有匹配的词。"),
            (.some(12), .some(3), nil, nil),
            (.some(3), .some(limit), nil, nil),
            (.some(3), .none, "No words match.", "没有匹配的词。"),
            (.some(3), .idle, nil, nil),
            (.none, .none, nil, nil),
            (.none, .some(2), "2 words found.", "找到 2 个词。"),
            (.none, .idle, nil, nil),
        ]
        for (old, new, en, zh) in rows {
            #expect(ListDetailView.searchAnnouncement(from: old, to: new, limit: limit, zh: false) == en, "\(old) → \(new)")
            #expect(ListDetailView.searchAnnouncement(from: old, to: new, limit: limit, zh: true) == zh, "\(old) → \(new)")
        }
        #expect(ListDetailView.searchOutcome(query: "", count: 0) == .idle)
        #expect(ListDetailView.searchOutcome(query: "  ", count: 0) == .idle)
        #expect(ListDetailView.searchOutcome(query: "zzqx", count: 0) == .none)
        #expect(ListDetailView.searchOutcome(query: "mizu", count: 4) == .some(4))
    }

    /// The view posts it, from the query's change, with the outcome before and after the search.
    /// Mutation, 2026-09-29: the `.post()` line removed → red.
    @Test("the query's onChange posts the announcement from the outcomes around the search")
    func announcementIsPosted() throws {
        let body = try Self.detail("var body: some View")
        #expect(body.contains(".onChange(of: query) { old, new in let before = Self.searchOutcome(query: old, count: results.count) results = model.vocab.search(new, limit: Self.searchLimit)"))
        #expect(body.contains("let after = Self.searchOutcome(query: new, count: results.count) if let line = Self.searchAnnouncement(from: before, to: after, limit: Self.searchLimit, zh: zh) { AccessibilityNotification.Announcement(line).post() }"))
    }

    // MARK: 6. Contrast — every text in the row and the panel, on what it sits on

    typealias Model = V133SContrastTests

    /// The arguments of every `.foregroundStyle(…)` in `text`.
    static func foregroundArguments(_ text: String) -> [String] {
        var arguments: [String] = []
        var from = text.startIndex
        while let open = text.range(of: ".foregroundStyle(", range: from..<text.endIndex) {
            var depth = 1
            var index = open.upperBound
            while index < text.endIndex {
                if text[index] == "(" { depth += 1 }
                if text[index] == ")" { depth -= 1; if depth == 0 { break } }
                index = text.index(after: index)
            }
            arguments.append(String(text[open.upperBound..<index]))
            from = index
        }
        return arguments
    }

    /// The colour names in a `foregroundStyle` argument — `Theme.x`, `Self.x`, `.white` — so a
    /// ternary over states yields every colour any state draws.
    static func colourNames(_ argument: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: #"\b(?:Theme|Self|AboutView|ListDetailView|WordSearchResultRow|Color)\.[A-Za-z0-9]+|(?<![A-Za-z0-9_)])\.(?:white|black|primary|secondary|gray|grey)\b"#)
        return regex.matches(in: argument, range: NSRange(argument.startIndex..., in: argument))
            .compactMap { Range($0.range, in: argument).map { String(argument[$0]) } }
    }

    /// Every `foregroundStyle` in `text` names only colours in `known`, with no opacity or
    /// constructed colour beside them, and each clears 4.5:1 over every backdrop in `backdrops`.
    /// Returns how many colour uses it checked, so a scan that found nothing cannot pass.
    static func checkEveryColour(in text: String, where place: String, known: [String: Color],
                                 over backdrops: [Model.RGB]) -> Int {
        var checked = 0
        for argument in foregroundArguments(text) {
            #expect(!argument.contains("opacity") && !argument.contains("Color("),
                    "\(place): .foregroundStyle(\(argument)) changes a colour this test cannot compute")
            let names = colourNames(argument)
            #expect(!names.isEmpty, "\(place): .foregroundStyle(\(argument)) names no colour this test reads")
            for name in names {
                guard let colour = known[name] else {
                    Issue.record("\(place): \(name) is not a colour this test has computed for this backdrop")
                    continue
                }
                for backdrop in backdrops {
                    let ratio = Model.contrast(Model.over(colour, backdrop), backdrop)
                    #expect(ratio >= 4.5, "\(place): \(name) at \(ratio):1 over \(backdrop)")
                }
                checked += 1
            }
        }
        #expect(text.contains(".foregroundColor(") == false, "\(place): a foregroundColor this test does not read")
        return checked
    }

    /// The row sits on `Theme.card` over the gradient; every colour it draws — word, reading, gloss
    /// and each state's icon — clears 4.5:1 on that card at both stops. The gloss was `Theme.dim`,
    /// 3.91:1 (the control below). Mutations, 2026-09-29: the gloss back to `Theme.dim` → red
    /// (an unknown colour); `glossColor` = white at 0.50 → red (4.46:1).
    @Test("every colour the result row draws clears 4.5:1 on its card, in every state")
    func rowTextClears() throws {
        let file = try #require(try CallSiteScanner.shippedSources.get()
            .first { $0.path == "Sources/NihongoRideApp/ListsView.swift" })
        let row = try #require(file.typeBodies(named: "WordSearchResultRow").first)
        let rowCode = Self.collapsed(String(decoding: file.codeWithStrings[row], as: UTF8.self))
        // The backdrop, read from the source: one card, and nothing else behind or over the text.
        #expect(rowCode.components(separatedBy: ".background(").count == 2
                && rowCode.contains(".background(Theme.card, in: RoundedRectangle(cornerRadius: 10))"))
        #expect(!rowCode.contains(".overlay") && !rowCode.contains(".opacity(") && !rowCode.contains("ZStack"))
        // Not `.plain`, which dims a disabled row's text (`disabledRowIsNotDimmed`).
        #expect(rowCode.contains(".buttonStyle(RowStyle())") && !rowCode.contains(".buttonStyle(.plain)"))
        let cards = try Model.gradientStops().map { Model.over(Theme.card, $0) }
        let checked = Self.checkEveryColour(in: rowCode, where: "WordSearchResultRow", known: [
            ".white": .white, "Theme.accent2": Theme.accent2, "Self.glossColor": WordSearchResultRow.glossColor,
            "Theme.gold": Theme.gold, "Theme.accent": Theme.accent,
        ], over: cards)
        #expect(checked == 6, "checked \(checked) colour uses: word, reading, gloss, and the icon's three states")

        let bottomCard = try #require(cards.last)
        let gloss = Model.contrast(Model.over(WordSearchResultRow.glossColor, bottomCard), bottomCard)
        #expect(abs(gloss - 4.57) < 0.01, "the gloss computes \(gloss):1 on the bottom card; its comment says 4.57")
        let before = Model.contrast(Model.over(Theme.dim, bottomCard), bottomCard)
        #expect(before < 4.5 && abs(before - 3.91) < 0.01, "control: Theme.dim on the card computed \(before):1, the review measured 3.91")
    }

    /// The panel's texts sit straight on the gradient (the panel and the screen's content draw no
    /// backdrop of their own — read below); every colour they draw clears 4.5:1 at both stops.
    /// The hint, no-results line, first-50 note and "In this list" caption were `Theme.dim`:
    /// 4.24:1 at the bottom stop, 4.47:1 at the top (the control). Mutation, 2026-09-29: the
    /// hint back to `Theme.dim` → red.
    ///
    /// Not held: the open button while the lists file cannot be read is `.disabled` under
    /// `.buttonStyle(.plain)`, which draws it dimmed — an inactive control, which WCAG 1.4.3
    /// exempts, and the one state here that says "not now" by being dim. The field's own text and
    /// placeholder are the system's `roundedBorder` field, drawn on its own bezel.
    @Test("every colour the search panel draws clears 4.5:1 on the background at both stops")
    func panelTextClears() throws {
        let stops = try Model.gradientStops()
        let known: [String: Color] = [
            "Self.dimTextColor": ListDetailView.dimTextColor, "Theme.gold": Theme.gold,
            "Theme.accent": Theme.accent, "Theme.accent2": Theme.accent2,
        ]
        var checked = 0
        for declaration in ["private func searchPanel", "private var searchField", "private var searchCloseButton",
                            "private var searchOpenButton", "private func inThisListCaption",
                            "private var emptyState", "private var unavailableState"] {
            let text = try Self.detail(declaration)
            #expect(!text.isEmpty && text.count < 5000, "\(declaration): the brace walk returned \(text.count) characters")
            #expect(!text.contains(".background(") && !text.contains(".panel(") && !text.contains(".opacity("),
                    "\(declaration) draws a backdrop or an opacity this test does not compose")
            checked += Self.checkEveryColour(in: text, where: declaration, known: known, over: stops)
        }
        #expect(checked == 9, "checked \(checked) colour uses: full notice, hint, no results, first 50, Done, open, caption, empty, gone")
        // The screen's content draws nothing behind the panel: its only background is the
        // key-capture view, which draws nothing and is absent while search is open.
        let body = try Self.detail("var body: some View")
        #expect(body.components(separatedBy: ".background").count == 2
                && body.contains(".background { if !Screenshotter.isCapturing && !searchIsShowing { KeyCaptureView("))

        let bottom = stops[1], top = stops[0]
        let now = Model.contrast(Model.over(ListDetailView.dimTextColor, bottom), bottom)
        #expect(abs(now - 4.62) < 0.01, "dimTextColor computes \(now):1 at the bottom stop; its comment says 4.62")
        let beforeBottom = Model.contrast(Model.over(Theme.dim, bottom), bottom)
        let beforeTop = Model.contrast(Model.over(Theme.dim, top), top)
        #expect(abs(beforeBottom - 4.24) < 0.01 && abs(beforeTop - 4.47) < 0.01,
                "control: Theme.dim computed \(beforeBottom) / \(beforeTop), the review measured 4.24 / 4.47")
    }

    #if canImport(AppKit)
    /// The arithmetic above holds only if a disabled row — in the list, or the list full — draws
    /// its text in the colours it names. It did not: under `.buttonStyle(.plain)` a disabled row
    /// drew the gloss at 71 of 255 instead of 137 and the word at 131 instead of 255 (this test's
    /// first run, 2026-09-29), about 2:1 on the card, on every row of a full list. Measured in the
    /// renderer: the text side of the row (the icon, which does change, is on the trailing side)
    /// draws the same pixels in all three states, and the gloss's solid glyph is the grey the
    /// model computes over the card (on the renderer's black). Control: the same row at 0.9
    /// opacity differs, so a dimming of disabled content is seen. Mutation, 2026-09-29:
    /// `.buttonStyle(.plain)` back on the row → red. macOS rendering; the iOS look is the
    /// simulator pass's to confirm.
    @MainActor
    @Test("a disabled row draws its text as an addable one does, in the colour computed")
    func disabledRowIsNotDimmed() throws {
        func render(_ state: WordSearchResultRow.State, opacity: Double = 1) -> V134B5RomajiHintTests.Bitmap? {
            V134B5RomajiHintTests.render(Self.row("水", "みず", "████ water", scale: 1, state: state).opacity(opacity),
                                         width: 358, height: nil)
        }
        func textSide(_ bitmap: V134B5RomajiHintTests.Bitmap) -> [UInt8] {
            let columns = bitmap.width * 7 / 10
            return (0..<bitmap.height).flatMap { y in bitmap.bytes[(y * bitmap.width * 4)..<(y * bitmap.width * 4 + columns * 4)] }
        }
        let addable = try #require(render(.addable))
        let inList = try #require(render(.inList))
        let full = try #require(render(.listFull))
        let dimmed = try #require(render(.addable, opacity: 0.9))
        #expect(textSide(addable) == textSide(inList), "an in-list row draws its text differently")
        #expect(textSide(addable) == textSide(full), "a full-list row draws its text differently")
        #expect(textSide(addable) != textSide(dimmed), "control: the comparison does not see a 10% dimming")

        // The gloss's block glyphs are solid: their pixels are the gloss colour over the card over
        // black. Most common grey in the text side between the card and the white word.
        let black: Model.RGB = (0, 0, 0)
        let expected = Model.over(WordSearchResultRow.glossColor, Model.over(Theme.card, black))
        let target = Int((expected.r * 255).rounded())
        let side = textSide(addable)
        var hits = 0
        for pixel in stride(from: 0, to: side.count, by: 4)
        where abs(Int(side[pixel]) - target) <= 2 && side[pixel] == side[pixel + 1] && side[pixel] == side[pixel + 2] {
            hits += 1
        }
        #expect(hits > 500, "only \(hits) pixels at the computed gloss grey \(target) — the row draws another colour")
    }
    #endif
}
