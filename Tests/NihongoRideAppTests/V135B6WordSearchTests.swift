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
/// file's.
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
        let uiTest = try String(contentsOf: root.appendingPathComponent(
            "Tests/NihongoRideiOSUITests/WordListSearchFlowTests.swift"), encoding: .utf8)
        let source = try String(contentsOf: HorizontalTextFitTests.appDirectory
            .appendingPathComponent("ListsView.swift"), encoding: .utf8)
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

        let script = try String(contentsOf: root.appendingPathComponent("scripts/run_ios_placement_tests.sh"),
                                encoding: .utf8)
        let iPhone = try #require(script.range(of: "caffeinate -d -i xcodebuild test").map { start in
            script[start.lowerBound..<(script.range(of: "IPHONE_STATUS=$?")?.lowerBound ?? script.endIndex)]
        })
        #expect(iPhone.contains("-only-testing:NihongoRideiOSUITests/WordListSearchFlowTests \\"))
        #expect(iPhone.contains("name=$SIM_NAME"), "the first invocation is no longer the iPhone's")
        #expect(uiTest.contains("final class WordListSearchFlowTests: XCTestCase"))
        #expect(script.contains("That is all 14 methods in the target."))
    }
}
