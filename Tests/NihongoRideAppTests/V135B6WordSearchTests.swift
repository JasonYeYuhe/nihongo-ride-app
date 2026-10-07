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
/// functions section 1 tests; the VoiceOver status announcement, table-tested and (second review)
/// replayed keystroke by keystroke through the debounce; and the contrast of every colour the row
/// and every view the screen's body reaches draw, computed with `V133SContrastTests`' model over
/// the backdrops read from the source, with the disabled rows' pixels measured.
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
        /// The entry each field comes from, so the test can name it.
        let ids: (surface: String, reading: String, glossEN: String, glossZH: String)
    }

    /// The corpus's longest written form, longest reading shown under a different written form,
    /// and longest gloss line in each language — combined into one row, which is harsher than any
    /// real one. Read through `VocabStore`, so it is the population the screen shows. Ties go to
    /// the entry first in corpus order.
    static let worst: Worst = {
        let entries = VocabStore.shared.entries
        func longest(_ pool: [VocabEntry], _ field: (VocabEntry) -> String) -> (String, String) {
            var best: (String, String) = ("", "")
            for entry in pool where field(entry).count > best.0.count { best = (field(entry), entry.id) }
            return best
        }
        let surface = longest(entries, \.surface)
        let reading = longest(entries.filter { $0.surface != $0.kana }, \.kana)
        let en = longest(entries) { $0.gloss(for: "en") }
        let zh = longest(entries) { $0.gloss(for: "zh") }
        return Worst(surface: surface.0, reading: reading.0, glossEN: en.0, glossZH: zh.0,
                     ids: (surface.1, reading.1, en.1, zh.1))
    }()

    /// Re-derived from the corpus merged at d476e8b (v1.35 step 5), 2026-09-29. The Chinese floor
    /// was 20 and came from n2-b962's 25-character gloss, which step 5 corrected; the longest
    /// Chinese gloss line is now n1-b1104's, 17. Each field is pinned to the entry it comes from
    /// and its length, so a corpus change that moves the worst row is red here and the row laid
    /// out below is re-read instead of silently getting easier.
    @Test("the worst row is what this file says it is")
    func worstRowIsTheCorpus() throws {
        let worst = Self.worst
        let found = "\(worst.ids) — surface \(worst.surface) \(worst.surface.count), reading \(worst.reading) \(worst.reading.count), en \(worst.glossEN.count), zh \(worst.glossZH.count) \(worst.glossZH)"
        #expect(worst.ids.surface == "n1-k008" && worst.surface == "インターナショナル" && worst.surface.count == 9, "\(found)")
        #expect(worst.ids.reading == "n4-b006" && worst.reading == "いっしょうけんめい" && worst.reading.count == 9, "\(found)")
        #expect(worst.ids.glossEN == "n1-b1750" && worst.glossEN.count == 83, "\(found)")
        #expect(worst.ids.glossZH == "n1-b1104" && worst.glossZH == "讨人喜欢的, 令人满意的, 可取的" && worst.glossZH.count == 17,
                "\(found)")
        // n2-b962, the entry the old floor came from, no longer holds it.
        let old = try #require(VocabStore.shared.entry(id: "n2-b962"))
        #expect(old.gloss(for: "zh").count < worst.glossZH.count, "n2-b962's zh gloss is \(old.gloss(for: "zh").count) again")
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
    /// list's own word rows used until v1.36) loses its tail at the default size in the phone column, and the
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
    /// `emptyStateText` (and `unavailableCopy` tests `unavailableText`) as functions; these pins say
    /// the screen calls them, where it should, read with comments blanked. Mutations, 2026-09-29,
    /// each red: `if full` → `if false`; the row's `wordCount: list.ids.count` → `wordCount: 0`;
    /// the empty state's text replaced by the old ★-only literal; `.disabled(state != .addable)`
    /// removed from the row; the gone-list line drawing `emptyStateText`.
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
        // …and unavailableState draws the gone-list copy `unavailableCopy` tests, not the empty
        // state's (which names a search button the gone branch does not draw). Mutation,
        // 2026-09-29: `Text(Self.emptyStateText(zh: zh))` in unavailableState → red.
        let gone = try Self.detail("private var unavailableState")
        #expect(gone.contains("Text(Self.unavailableText(zh: zh))"), "\(gone)")
        #expect(!gone.contains("emptyStateText"), "the gone-list line is the empty state's copy again")
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

    /// The view searches in the query's onChange, tells the announcer the outcome, and posts what
    /// the announcer says after sleeping its delay — the functions the replay below drives.
    /// Mutations, 2026-09-29, each red: the `.post()` line removed; `announcer.due(at:…)` called
    /// without the sleep before it; the task not cancelled before a new one.
    @Test("the query's onChange searches, records the outcome, and posts only what the settled announcer says")
    func announcementIsPosted() throws {
        let body = try Self.detail("var body: some View")
        let parts: [String] = [
            ".onChange(of: query) { _, new in results = model.vocab.search(new, limit: Self.searchLimit)",
            "announcer.changed(to: Self.searchOutcome(query: new, count: results.count), at: .now)",
            "announceTask?.cancel() announceTask = Task { @MainActor in",
            "try? await Task.sleep(for: SearchAnnouncer.settleDelay)",
            "guard !Task.isCancelled else { return }",
            "if let line = announcer.due(at: .now, limit: Self.searchLimit, zh: zh) {",
            "AccessibilityNotification.Announcement(line).post() } } }",
        ]
        let expected = parts.joined(separator: " ")
        #expect(body.contains(expected), "\(body)")
        #expect(body.components(separatedBy: "AccessibilityNotification.Announcement(").count == 2,
                "a second announcement is posted from the body")
        // Opening and closing search start the announcer afresh and drop a pending line.
        let reset = try Self.detail("private func resetAnnouncer")
        #expect(reset.contains("announceTask?.cancel()") && reset.contains("announcer = SearchAnnouncer()"))
        #expect(try Self.detail("private func openSearch").contains("resetAnnouncer()"))
        #expect(try Self.detail("private func closeSearch").contains("resetAnnouncer()"))
    }

    /// Leaving the screen drops a pending line (round 3): Back and Esc go through `backToLists`,
    /// which resets before it moves the screen, and the view resets on disappearing, whatever moved
    /// it. And a cancelled task says nothing — `try?` swallows the sleep's cancellation, so the
    /// task checks. Mutations, 2026-09-29, each red here: `resetAnnouncer()` removed from
    /// `backToLists`; the `.onDisappear` removed; the `Task.isCancelled` guard removed (red in
    /// `announcementIsPosted`).
    @Test("leaving the screen cancels a pending announcement")
    func leavingCancelsTheAnnouncement() throws {
        let back = try Self.detail("private func backToLists")
        #expect(back.contains("resetAnnouncer() model.selectedListID = nil"), "\(back)")
        let body = try Self.detail("var body: some View")
        #expect(body.contains(".onDisappear { resetAnnouncer() }"), "\(body)")
        #expect(body.contains("onCommand: { command in if command == .escape { backToLists() } }"),
                "Esc no longer leaves through backToLists")
        #expect(try Self.detail("private var backButton").contains("Button(action: backToLists)"))
    }

    /// The announcer forgets what it said when the field empties, at once — not when the empty field
    /// has settled, which a quick retype never lets happen. Replayed at the speed that bit: "water"
    /// settles and is said; the field is cleared and "mizu" typed within 0.3 s. Measured before
    /// (round 2's announcer), 2026-09-29: mizu's results were never said. Mutation, 2026-09-29: the
    /// idle branch of `changed` removed → red here.
    @Test("a query replaced before the empty field settles is announced")
    func replacedQueryIsAnnounced() {
        typealias A = ListDetailView.SearchAnnouncer
        let limit = ListDetailView.searchLimit
        let t0 = ContinuousClock.now
        func at(_ ms: Int) -> ContinuousClock.Instant { t0.advanced(by: .milliseconds(ms)) }
        var a = A()
        a.changed(to: .some(12), at: at(0))
        #expect(a.due(at: at(800), limit: limit, zh: false) == "12 words found.")
        // Cleared, and a new query typed well inside the delay: the empty field never settles.
        a.changed(to: .idle, at: at(1000))
        #expect(a.announced == .idle, "clearing the field did not end what was said")
        a.changed(to: .some(4), at: at(1300))
        #expect(a.due(at: at(1800), limit: limit, zh: false) == nil, "the empty field settled — not the case this is about")
        #expect(a.due(at: at(2100), limit: limit, zh: false) == "4 words found.")
        // A line pending when the field empties is dropped: nothing is said about an empty field.
        a.changed(to: .none, at: at(3000))
        a.changed(to: .idle, at: at(3200))
        #expect(a.due(at: at(4000), limit: limit, zh: false) == nil)
        #expect(a.due(at: at(5000), limit: limit, zh: false) == nil)
        // Control: the same keystrokes without the clear — a query edited in place — say nothing new.
        var b = A()
        b.changed(to: .some(12), at: at(0))
        _ = b.due(at: at(800), limit: limit, zh: false)
        b.changed(to: .some(4), at: at(1300))
        #expect(b.due(at: at(2100), limit: limit, zh: false) == nil)
    }

    /// The announcer on a synthetic clock. It says nothing until the last change is
    /// `settleDelay` old; then it compares the settled kind with the last ANNOUNCED one, so a flip
    /// and its reversal inside the wait say nothing. Mutations, 2026-09-29, each red: the
    /// `time - changedAt >= settleDelay` guard removed (every keystroke speaks); `announced =
    /// outcome` removed (some → some repeats); `settleDelay` set to zero.
    @Test("the announcer speaks once the outcome has settled, and only when its kind changed")
    func announcerSettles() {
        typealias A = ListDetailView.SearchAnnouncer
        let limit = ListDetailView.searchLimit
        let t0 = ContinuousClock.now
        func at(_ ms: Int) -> ContinuousClock.Instant { t0.advanced(by: .milliseconds(ms)) }
        #expect(A.settleDelay == .milliseconds(800))

        var a = A()
        #expect(a.due(at: at(0), limit: limit, zh: false) == nil, "nothing typed, nothing to say")
        a.changed(to: .some(12), at: at(0))
        #expect(a.due(at: at(799), limit: limit, zh: false) == nil, "said before it settled")
        #expect(a.due(at: at(800), limit: limit, zh: false) == "12 words found.")
        #expect(a.due(at: at(2000), limit: limit, zh: false) == nil, "said twice")
        // A flip to none and back inside the wait: the settled kind is the one already said.
        a.changed(to: .none, at: at(3000))
        a.changed(to: .some(4), at: at(3300))
        #expect(a.due(at: at(3800), limit: limit, zh: false) == nil, "the none it passed through was not settled")
        #expect(a.due(at: at(4100), limit: limit, zh: false) == nil, "some → some is not news")
        // A settled none is said, and so are results after it.
        a.changed(to: .none, at: at(5000))
        #expect(a.due(at: at(5800), limit: limit, zh: true) == "没有匹配的词。")
        a.changed(to: .some(limit), at: at(6000))
        #expect(a.due(at: at(6800), limit: limit, zh: false) == "Showing the first 50 words.")
        // Clearing the field says nothing, and results after it are news again.
        a.changed(to: .idle, at: at(7000))
        #expect(a.due(at: at(7800), limit: limit, zh: false) == nil)
        #expect(a.announced == .idle)
        a.changed(to: .some(3), at: at(8000))
        #expect(a.due(at: at(8800), limit: limit, zh: false) == "3 words found.")
    }

    /// The finding this answers: announcing each none ↔ some flip as it happened spoke on about
    /// every other keystroke of romaji, because a keystroke that ended mid-kana ("tabem") read as
    /// nothing and found nothing. Measured on the tree before this fix (7282c86, the same
    /// replay, a line whenever `searchAnnouncement(previous → this keystroke)` spoke): the eight
    /// words below, 32 announcements over 61 keystrokes (tabemono 5, tomodachi 5, jitensha 5,
    /// nomimono 5, shukudai 5, atarashii 5, water 1, school 1); twenty learner words, 64 over 136.
    ///
    /// Replayed here through the functions the view's onChange calls — `VocabStore.search` with the
    /// screen's limit, `searchOutcome`, `SearchAnnouncer` — at two typing speeds on a synthetic
    /// clock: 1.2 s a key, slower than the delay, so every keystroke settles and the debounce
    /// cannot help (what holds there is the partial reading's doing); and 0.25 s a key, where only
    /// the pause after the last key does. At most two lines per word at either speed, and no
    /// keystroke's results empty. Measured after the fix, 2026-09-29: one line per word at both
    /// speeds, eight lines over the 61 keystrokes (each "Showing the first 50 words." at the first
    /// key); no keystroke of the eight words found nothing. Mutation, 2026-09-29: the partial
    /// readings left out of `WordSearchIndex.matches` → red (tabem, tomod, jit, … find nothing again). The debounce's own
    /// mutations are `announcerSettles`'s: at these words' outcomes, with the partial readings in,
    /// every keystroke settling says no more than the debounce does, so this replay cannot see it.
    @Test("typing a word a letter at a time announces at most twice, and never finds nothing midway", arguments: [
        "tabemono", "tomodachi", "jitensha", "nomimono", "shukudai", "atarashii", "water", "school",
    ])
    func typingAWordAnnouncesAtMostTwice(_ word: String) {
        let slow = Self.replay(word, keyInterval: .milliseconds(1200))
        let fast = Self.replay(word, keyInterval: .milliseconds(250))
        print("B6 ANNOUNCEMENTS \(word): \(slow.lines.count) at 1.2 s/key \(slow.lines), \(fast.lines.count) at 0.25 s/key; counts \(slow.counts)")
        #expect(slow.lines.count <= 2, "\(word) at 1.2 s a key: \(slow.lines)")
        #expect(fast.lines.count <= 1, "\(word) at 0.25 s a key: \(fast.lines)")
        #expect(!slow.counts.contains(0), "\(word): a keystroke found nothing — \(slow.counts)")
        #expect(slow.lines.first?.hasSuffix("found.") == true || slow.lines.first == "Showing the first 50 words.",
                "control: the replay's first line should report results — \(slow.lines)")
    }

    /// One word typed a key at a time: each keystroke searches, tells the announcer, and the
    /// announcer is asked at every instant a view's sleeping task would wake (a keystroke's time +
    /// `settleDelay`), in time order with the keystrokes. A task woken after a later keystroke
    /// finds that keystroke's change too young — the announcer's own rule, not the replay's.
    static func replay(_ word: String, keyInterval: Duration) -> (lines: [String], counts: [Int]) {
        let t0 = ContinuousClock.now
        var announcer = ListDetailView.SearchAnnouncer()
        var lines: [String] = []
        var counts: [Int] = []
        let keys = (1...word.count).map { (t0.advanced(by: keyInterval * $0), String(word.prefix($0))) }
        var wakes = keys.map { $0.0.advanced(by: ListDetailView.SearchAnnouncer.settleDelay) }
        for (time, prefix) in keys {
            while let wake = wakes.first, wake < time {
                wakes.removeFirst()
                if let line = announcer.due(at: wake, limit: ListDetailView.searchLimit, zh: false) { lines.append(line) }
            }
            let count = VocabStore.shared.search(prefix, limit: ListDetailView.searchLimit).count
            counts.append(count)
            announcer.changed(to: ListDetailView.searchOutcome(query: prefix, count: count), at: time)
        }
        for wake in wakes {
            if let line = announcer.due(at: wake, limit: ListDetailView.searchLimit, zh: false) { lines.append(line) }
        }
        return (lines, counts)
    }

    // MARK: 6. Contrast — every text on the screen, on what it sits on

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

    enum Backdrop { case gradient, card }

    /// Why the launchers' label colours are not held here. Enabled, each is a label on a
    /// brand-colour capsule — white on the coral (Practice) and on the sky (Sentences), black on the
    /// gold (Dictation): brand-colour contrast, on PLAN-V1.34 §I's day-91 list with About's licence
    /// badges. Disabled, it is `Theme.dim` on `Theme.card` on an inactive control, which WCAG 1.4.3
    /// exempts; the note under a disabled launcher, which says why, is held.
    static let launcherExemption = "brand-colour capsule when enabled (PLAN-V1.34 §I); inactive control when disabled (WCAG 1.4.3)"

    /// Every view `ListDetailView`'s body reaches, with what its text sits on, the backgrounds it
    /// draws (exactly), and the one colour argument it may leave unchecked and why. `screenIsComplete`
    /// derives the reachable set from the source and requires it to be this list's, so a new view on
    /// the screen is red until it is placed here. The result rows are `WordSearchResultRow`, a
    /// separate type, held by `rowTextClears`; the list's own words' text is `ListWordRowText`
    /// (v1.36), another, held at the end of `screenTextClears`. The launchers' backgrounds are their capsules, behind
    /// their labels only; the notes under the Sentences and Dictation launchers sit outside them, on
    /// the gradient.
    static let screen: [(declaration: String, backdrop: Backdrop, backgrounds: [String], exempt: String?)] = [
        // The body itself: text drawn straight in it sits on the gradient (round 3 — the scan
        // walked only the views the body names, so a Text written in the body was never read).
        // Its one background is the key-capture view, which draws nothing (held at the end of
        // `screenTextClears`); its one Text is the alert's message, which the system draws, and
        // is exempted by name (`alertMessage`).
        ("var body: some View", .gradient, [], nil),
        ("private var header", .gradient, [], nil),
        ("private var backButton", .card, ["Theme.card, in: Capsule()"], nil),
        ("private func searchPanel", .gradient, [], nil),
        ("private var searchField", .gradient, [], nil),
        ("private var searchCloseButton", .gradient, [], nil),
        ("private var searchOpenButton", .gradient, [], nil),
        ("private func inThisListCaption", .gradient, [], nil),
        ("private func playButton", .gradient, ["playable ? Theme.accent : Theme.card, in: Capsule()"],
         "playable ? .white : Theme.dim"),
        ("private func sentenceButton", .gradient, ["enabled ? Theme.accent2 : Theme.card, in: Capsule()"],
         "enabled ? .white : Theme.dim"),
        ("private func dictationButton", .gradient, ["enabled ? Theme.gold.opacity(0.9) : Theme.card, in: Capsule()"],
         "enabled ? .black : Theme.dim"),
        ("private var unplayableHint", .gradient, [], nil),
        ("private func wordRow", .card, ["Theme.card, in: RoundedRectangle(cornerRadius: 10)"], nil),
        ("private var unavailableState", .gradient, [], nil),
        ("private var emptyState", .gradient, [], nil),
    ]

    /// The arguments of every `.<modifier>(…)` in `text`, balanced on parentheses.
    static func modifierArguments(_ modifier: String, in text: String) -> [String] {
        var arguments: [String] = []
        var from = text.startIndex
        while let open = text.range(of: ".\(modifier)(", range: from..<text.endIndex) {
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

    /// The view members of `ListDetailView` reachable from its body — each `var`/`func` whose type
    /// is `some View`, found by name in the body or in another reachable member — read from the
    /// comment-blanked source.
    static func reachableViews() throws -> (reachable: Set<String>, all: [String: String]) {
        let file = try #require(try CallSiteScanner.shippedSources.get()
            .first { $0.path == "Sources/NihongoRideApp/ListsView.swift" })
        let type = try #require(file.typeBodies(named: "ListDetailView").first)
        let code = String(decoding: file.codeWithStrings[type], as: UTF8.self)
        var all: [String: String] = [:]   // name → declaration prefix
        // From the name to the opening brace, across lines — a helper whose parameters are laid
        // out one per line has its `-> some View` lines below its name (round 3: the one-line
        // version missed such a helper, and the text it drew was never scanned). The signature
        // may not run into another declaration: a `var` with a value (`bodyPoints: CGFloat = 17`)
        // has no brace of its own, and a match allowed to run on would take the next
        // declaration's signature for its own (the first run found bodyPoints "reachable").
        let declaration = try Regex(#"((?:private\s+)?(?:var|func)\s+(\w+))((?:(?!\b(?:var|func|let|struct|enum|init)\b)[^{}])*)\{"#)
        for match in code.matches(of: declaration) {
            guard let signature = match.output[3].substring, signature.contains("some View"),
                  let prefix = match.output[1].substring, let name = match.output[2].substring else { continue }
            all[String(name)] = collapsed(String(prefix))
        }
        // And every `some View` declaration the type has is one of them: a signature this scan
        // cannot read is red here rather than silently unscanned.
        let declared = code.matches(of: try Regex(#"(?:->|:)\s*some\s+View\b"#)).count
        #expect(declared == all.count,
                "ListDetailView declares \(declared) `some View` members; the scan matched \(all.count): \(all.keys.sorted())")
        var reachable = Set<String>()
        var queue = [try detail("var body: some View")]
        while let text = queue.popLast() {
            for (name, prefix) in all where name != "body" && !reachable.contains(name) {
                if text.firstMatch(of: try Regex("\\b" + name + "\\b")) != nil {
                    reachable.insert(name)
                    queue.append(try detail(prefix))
                }
            }
        }
        return (reachable, all)
    }

    /// The alert's message: drawn by the system in its own panel, not on this screen's gradient, so
    /// it is the one Text in `body` the scan leaves — by name, exactly once.
    static let alertMessage = #"message: { Text(errorMessage ?? "") }"#

    /// Completeness of `screen`: the body and every view it reaches are placed there, and nothing
    /// else is. Calibrated: the walk finds `backButton` through `header` only, and `searchField`
    /// through `searchPanel` only. Mutation, 2026-09-29: the `unplayableHint` row removed from
    /// `screen` → red. Probe, round 3: a helper whose signature spans three lines, called from the
    /// body and drawing `Theme.dim.opacity(0.5)` → red here (the one-line scan did not see it, and
    /// was green).
    @Test("the contrast scan's list is the body and every view it reaches")
    func screenIsComplete() throws {
        let (reachable, all) = try Self.reachableViews()
        let listed = Set(Self.screen.map { String($0.declaration.split(separator: " ").last!) })
            .subtracting(["View"])   // "var body: some View"
        #expect(Self.screen.contains { $0.declaration == "var body: some View" }, "the body is not scanned")
        #expect(reachable == listed, "reached but not listed: \(reachable.subtracting(listed).sorted()); listed but not reached: \(listed.subtracting(reachable).sorted())")
        #expect(all.count >= 15 && all["body"] != nil, "control: the declaration scan found \(all.keys.sorted())")
        let body = try Self.detail("var body: some View")
        #expect(!body.contains("backButton") && !body.contains("searchField"),
                "control: these are reached through header and searchPanel, not named in body")
    }

    /// Every colour every text on the screen draws clears 4.5:1 on what it sits on, at both
    /// gradient stops — the search panel, the list's own word rows under it, the empty and gone
    /// lines, the header and the launchers' notes; only the launchers' own labels are left, for the
    /// reason `launcherExemption` gives. Each declaration's backgrounds are exactly those listed,
    /// with no other `.opacity`, `.overlay` (but the Back capsule's stroke) or `ZStack` on it.
    ///
    /// The second review found three texts under the line that the first scan's hand-picked list
    /// did not reach, all visible under the result rows while search is open: the word row's gloss
    /// (`Theme.dim` on the card, 3.91:1), the removed-word note (`Theme.dim.opacity(0.7)`, 2.67:1)
    /// and the unplayable hint (`Theme.dim` on the gradient, 4.24:1). Walking every reachable view
    /// found three more: a removed word's label (`Theme.dim` on the card, 3.91:1) and the notes
    /// under disabled Sentences and Dictation launchers (4.24:1). All six are now the constants
    /// de57aad introduced — `glossColor` on the card, `dimTextColor` on the gradient — colour only.
    /// Mutations, 2026-09-29, each red: the word row's gloss back to `Theme.dim`; the removed-word
    /// note back to `Theme.dim.opacity(0.7)`; the unplayable hint back to `Theme.dim`; the hint in
    /// the panel back to `Theme.dim` (the first scan's mutation, still red).
    ///
    /// **v1.36:** the word row's text moved into a type of its own, `ListWordRowText`, which this
    /// declaration walk does not reach (it walks `ListDetailView`'s members). It is read whole, as
    /// `rowTextClears` reads the result row, over the card `wordRow` draws, after `wordRow` is held
    /// to drawing it; `wordRow` itself now draws only the Remove icon. Mutations, 2026-10-07, each
    /// red: the new reading line coloured `Theme.dim`; the removed-word note back to
    /// `Theme.dim.opacity(0.7)` inside the new type.
    @Test("every text ListDetailView draws clears 4.5:1 on its backdrop at both stops")
    func screenTextClears() throws {
        let stops = try Model.gradientStops()
        let cards = stops.map { Model.over(Theme.card, $0) }
        let known: [String: Color] = [
            ".white": .white, "Theme.accent": Theme.accent, "Theme.accent2": Theme.accent2, "Theme.gold": Theme.gold,
            "Self.dimTextColor": ListDetailView.dimTextColor, "WordSearchResultRow.glossColor": WordSearchResultRow.glossColor,
        ]
        var checked: [String: Int] = [:]
        for place in Self.screen {
            var text = try Self.detail(place.declaration)
            #expect(!text.isEmpty && text.count < 6000, "\(place.declaration): the brace walk returned \(text.count) characters")
            #expect(Self.modifierArguments("background", in: text) == place.backgrounds,
                    "\(place.declaration) draws backgrounds \(Self.modifierArguments("background", in: text))")
            if place.declaration == "var body: some View" {
                // The key-capture background (checked exactly below) and the alert's message.
                #expect(text.components(separatedBy: ".background {").count == 2)
                #expect(text.components(separatedBy: Self.alertMessage).count == 2,
                        "the alert's message is not `\(Self.alertMessage)` exactly once")
                text = text.replacingOccurrences(of: ".background {", with: "")
                    .replacingOccurrences(of: Self.alertMessage, with: "")
            }
            #expect(!text.contains(".background {") && !text.contains("ZStack") && !text.contains(".panel("),
                    "\(place.declaration) draws a backdrop this test does not compose")
            let overlays = Self.modifierArguments("overlay", in: text)
            #expect(overlays.isEmpty || overlays == ["Capsule().strokeBorder(Theme.cardStroke)"], "\(place.declaration): \(overlays)")
            for background in place.backgrounds { text = text.replacingOccurrences(of: background, with: "") }
            if let exempt = place.exempt {
                #expect(text.components(separatedBy: ".foregroundStyle(\(exempt))").count == 2,
                        "\(place.declaration): the exempt label colour \(exempt) is not drawn exactly once")
                text = text.replacingOccurrences(of: ".foregroundStyle(\(exempt))", with: "")
            }
            #expect(!text.contains(".opacity("), "\(place.declaration) draws an opacity this test does not compose")
            checked[place.declaration] = Self.checkEveryColour(in: text, where: place.declaration, known: known,
                                                               over: place.backdrop == .card ? cards : stops)
        }

        // The list's own words' text column (v1.36), on the card `wordRow` draws it on. Held first
        // to being what `wordRow` draws, then read whole: no backdrop of its own, and every colour
        // it names clears on the card.
        let wordRow = try Self.detail("private func wordRow")
        #expect(wordRow.contains("ListWordRowText(content: content, zh: zh, scale: bodyPoints / 17)"),
                "wordRow no longer draws ListWordRowText, so scanning it says nothing about this screen")
        let file = try #require(try CallSiteScanner.shippedSources.get()
            .first { $0.path == "Sources/NihongoRideApp/ListsView.swift" })
        let column = try #require(file.typeBodies(named: "ListWordRowText").first)
        let columnCode = Self.collapsed(String(decoding: file.codeWithStrings[column], as: UTF8.self))
        #expect(!columnCode.isEmpty && columnCode.count < 6000, "the type walk returned \(columnCode.count) characters")
        #expect(Self.modifierArguments("background", in: columnCode).isEmpty && !columnCode.contains(".overlay")
                && !columnCode.contains("ZStack") && !columnCode.contains(".opacity("),
                "ListWordRowText draws a backdrop or an opacity this test does not compose")
        checked["struct ListWordRowText"] = Self.checkEveryColour(in: columnCode, where: "ListWordRowText",
                                                                  known: known, over: cards)

        let total = checked.values.reduce(0, +)
        print("B6 SCREEN CONTRAST: \(total) colour uses — \(checked.sorted { $0.key < $1.key }.map { "\($0.key.hasPrefix("var body") ? "body" : String($0.key.split(separator: " ").last!)) \($0.value)" })")
        // header 2, Back 1, panel 4, Done 1, open 1, caption 1, sentence note 1, dictation note 1,
        // unplayable 1, word row 1 (the Remove icon), its text column 5 (word, reading, gloss, a
        // removed word's label and note), gone 1, empty 1. Until v1.36 the word row held its text
        // and counted 5 (a removed word's label, both branches; gloss; note; −), and the total was 20.
        #expect(total == 21, "checked \(total) colour uses")
        #expect(checked["private func wordRow"] == 1 && checked["struct ListWordRowText"] == 5
                && checked["private func searchPanel"] == 4)

        // Controls: what the recoloured texts computed before, and what the constants compute now.
        let bottom = stops[1], top = stops[0], bottomCard = cards[1]
        let now = Model.contrast(Model.over(ListDetailView.dimTextColor, bottom), bottom)
        #expect(abs(now - 4.62) < 0.01, "dimTextColor computes \(now):1 at the bottom stop; its comment says 4.62")
        let beforeBottom = Model.contrast(Model.over(Theme.dim, bottom), bottom)
        let beforeTop = Model.contrast(Model.over(Theme.dim, top), top)
        #expect(abs(beforeBottom - 4.24) < 0.01 && abs(beforeTop - 4.47) < 0.01,
                "control: Theme.dim computed \(beforeBottom) / \(beforeTop), the review measured 4.24 / 4.47")
        let glossBefore = Model.contrast(Model.over(Theme.dim, bottomCard), bottomCard)
        let noteBefore = Model.contrast(Model.over(Theme.dim.opacity(0.7), bottomCard), bottomCard)
        #expect(abs(glossBefore - 3.91) < 0.01 && abs(noteBefore - 2.67) < 0.01,
                "control: on the card Theme.dim computed \(glossBefore), at 0.7 \(noteBefore); the review measured 3.91 / 2.67")

        // The screen's content draws nothing behind the panel: its only background is the
        // key-capture view, which draws nothing and is absent while search is open.
        let body = try Self.detail("var body: some View")
        #expect(body.components(separatedBy: ".background").count == 2
                && body.contains(".background { if !Screenshotter.isCapturing && !searchIsShowing { KeyCaptureView("))
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
    ///
    /// **Equal within one level of 255, not byte for byte** (round 3). The byte-exact version
    /// failed about one run in seven to twenty, always on addable ≠ full. The cause, measured
    /// 2026-09-30 from `ImageRenderer`'s own `cgImage` bytes (sRGB, 8 bits, no conversion of ours
    /// in between): the renderer draws a glyph's anti-aliased edge one level differently the first
    /// time or two it draws that glyph at that size than once it has drawn it before — 24–25 bytes
    /// of the 452,512 in this row, by exactly 1. Rendering the three states 30 times in one process
    /// gave the sequence addable 0 1 1 1…, in-list 0 1 1 1…, full 1 1 1…: the first two renders
    /// cold, everything after warm, and the full row (rendered third) already warm. Whether THIS
    /// test's first render is cold depends on which other test drew 水 and みず at these sizes
    /// first — test order — which is why it flaked on addable vs full and never on a later pair.
    /// Warming up first was tried and is not enough: one of six probe processes still saw a
    /// render change after its first round. The dimming this test exists to catch is 66 levels
    /// (`.plain`: 137 → 71), and the control's 10% is up to 24; a tolerance of 1 sees both, and no
    /// renderer cache state can move a pixel past it. `tolerance` is asserted below the
    /// control's effect, so it cannot be widened into blindness.
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
        /// The largest difference of any byte, and how many bytes differ.
        func delta(_ a: [UInt8], _ b: [UInt8]) -> (max: Int, count: Int) {
            guard a.count == b.count else { return (.max, .max) }
            var largest = 0, count = 0
            for i in a.indices where a[i] != b[i] {
                largest = max(largest, abs(Int(a[i]) - Int(b[i])))
                count += 1
            }
            return (largest, count)
        }
        let tolerance = 1
        let addable = try #require(render(.addable))
        let inList = try #require(render(.inList))
        let full = try #require(render(.listFull))
        let dimmed = try #require(render(.addable, opacity: 0.9))
        let inListDelta = delta(textSide(addable), textSide(inList))
        let fullDelta = delta(textSide(addable), textSide(full))
        let dimmedDelta = delta(textSide(addable), textSide(dimmed))
        #expect(inListDelta.max <= tolerance, "an in-list row draws its text differently: \(inListDelta)")
        #expect(fullDelta.max <= tolerance, "a full-list row draws its text differently: \(fullDelta)")
        #expect(dimmedDelta.max > 10 * tolerance, "control: the comparison does not see a 10% dimming: \(dimmedDelta)")

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
