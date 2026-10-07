import Testing
import Foundation
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
import VocabKit
@testable import NihongoRideApp

/// v1.36 §C items 1 and 2 — a list's own words show their reading and a long gloss wraps
/// (`ListWordRowText`, drawn by `ListDetailView.wordRow`); the Saved list's row on the Word Lists
/// screen draws its star once (`ListsView.rowName`).
///
/// **What these can and cannot prove, stated first.** The reading rule and the row's name are pure
/// functions and are tested as values (sections 1 and 3). The text column is laid out hosted on
/// macOS at the default size and the five accessibility sizes, with the corpus's longest word,
/// reading and glosses (`V135B6WordSearchTests.worst`, pinned there to the entries they come from),
/// in the width `wordRow` leaves it on a 402pt and a 320pt phone — beside the Remove button below
/// the accessibility sizes, over it at them — and read back from the pixels (section 4) — possible
/// because the column takes its text size as `scale`, as `WordSearchResultRow` does; a hosted view
/// on macOS ignores `dynamicTypeSize`. Which arrangement the row picks is `typeSize`'s, so it is a
/// source pin (`columnIsWired`); every gloss in the corpus is then laid out by CoreText in the
/// column each arrangement leaves, to count words broken inside themselves (section 5). VoiceOver's one
/// element is a label tested as a value plus a source pin on the modifier that makes it one: a
/// hosted `NSHostingView` exposed no accessibility children to a probe on 2026-10-07 (one AXGroup,
/// no children, with the window ordered front), so the tree itself is the simulator pass's to read.
/// Whether the screen around the rows scrolls and the Remove button stays tappable at AX5 on a
/// phone is that pass's question too, with `WordListSearchFlowTests`, which adds 水 from search and
/// then finds the Remove button `removeWord-n5-mizu` in the list below — the identifier this change
/// keeps (`oneElementIsWired`).
///
/// Every test here was shown able to fail: the mutations that turned each one red, on 2026-10-07,
/// are named on it (34 in all, each applied, run, seen red and reverted; the review's five findings
/// added 16 more on the same day, named the same way). Not every `#expect` has
/// a mutation of its own — the sweep's case count and width bound, for instance, ride on the ones
/// named.
@MainActor
@Suite("v1.36 §C 1–2: a list's own words show their reading, and the Saved row one star")
struct V136ListRowsTests {

    static func listsSource() throws -> CallSiteScanner.File {
        try #require(try CallSiteScanner.shippedSources.get()
            .first { $0.path == "Sources/NihongoRideApp/ListsView.swift" })
    }

    /// The body of `ListWordRowText`, comments blanked, strings kept, whitespace collapsed.
    static func columnSource() throws -> String {
        let file = try listsSource()
        let body = try #require(file.typeBodies(named: "ListWordRowText").first)
        return V135B6WordSearchTests.collapsed(String(decoding: file.codeWithStrings[body], as: UTF8.self))
    }

    // MARK: 1. The reading: one rule, both rows

    /// Mutations, 2026-10-07, each red: `reading(for:)` returning `entry.kana` always (おいしい and
    /// アパート show a reading that repeats them); returning nil always (水 loses みず).
    @Test("a word written in kana shows no reading; any other word shows its kana")
    func readingRule() throws {
        let store = VocabStore.shared
        let mizu = try #require(store.entry(id: "n5-mizu"))
        #expect(mizu.surface == "水" && ListDetailView.reading(for: mizu) == "みず")
        let oishii = try #require(store.entry(id: "n5-oishii"))
        #expect(oishii.surface == "おいしい" && ListDetailView.reading(for: oishii) == nil, "hiragana")
        let apartment = try #require(store.entry(id: "n5-k001"))
        #expect(apartment.surface == "アパート" && ListDetailView.reading(for: apartment) == nil, "katakana")
        // Over the population the screen shows: both kinds are common, and no shown reading
        // repeats its word.
        let entries = store.entries
        let shown = entries.filter { ListDetailView.reading(for: $0) != nil }
        print("V136 READINGS: \(shown.count) of \(entries.count) entries show a reading")
        #expect(shown.count > entries.count / 2 && shown.count < entries.count)
        #expect(shown.allSatisfy { ListDetailView.reading(for: $0) != $0.surface })
    }

    /// Both rows on the screen call the helper, and the rule is written nowhere else in the file —
    /// no `.kana` outside it. Mutations, 2026-10-07, each red: the search panel back to the inline
    /// `entry.surface == entry.kana ? nil : entry.kana`; the word row passing `reading: $0.kana`.
    @Test("the search results and the list's own words both take the reading from reading(for:)")
    func bothRowsUseTheReadingRule() throws {
        let panel = try V135B6WordSearchTests.detail("private func searchPanel")
        #expect(panel.contains("reading: Self.reading(for: entry),"), "the search results no longer use reading(for:)")
        let row = try V135B6WordSearchTests.detail("private func wordRow")
        #expect(row.contains(".word(surface: $0.surface, reading: Self.reading(for: $0), gloss: $0.gloss(for: model.languageCode))"),
                "the list's own words no longer use reading(for:)")
        let helper = try V135B6WordSearchTests.detail("static func reading(for entry: VocabEntry)")
        #expect(helper.contains("entry.surface == entry.kana ? nil : entry.kana"))
        // Strings and comments blanked: `.kana` in code, the helper's two and no more.
        let code = try Self.listsSource().allCode
        #expect(code.components(separatedBy: ".kana").count - 1 == 2,
                "\(code.components(separatedBy: ".kana").count - 1) uses of .kana in ListsView — the rule is written twice again")
    }

    // MARK: 2. VoiceOver, and a removed word

    /// The column's one label is the search row's for the same word. Mutation, 2026-10-07: the
    /// word case joined with " " instead of through `WordSearchResultRow.accessibilityLabel` → red.
    @Test("the text column reads as one label: word, reading, gloss, as the search row does")
    func oneLabel() {
        #expect(ListWordRowText.accessibilityLabel(.word(surface: "水", reading: "みず", gloss: "water"), zh: false)
                == "水, みず, water")
        #expect(ListWordRowText.accessibilityLabel(.word(surface: "アパート", reading: nil, gloss: "公寓"), zh: true)
                == "アパート, 公寓")
        for (surface, reading, gloss) in [("水", "みず", "water"), ("アパート", nil, "apartment")] as [(String, String?, String)] {
            #expect(ListWordRowText.accessibilityLabel(.word(surface: surface, reading: reading, gloss: gloss), zh: false)
                    == WordSearchResultRow.accessibilityLabel(surface: surface, reading: reading, gloss: gloss))
        }
        #expect(ListWordRowText.accessibilityLabel(.removed, zh: false)
                == "Removed word, No longer in the dictionary — you can remove it")
        #expect(ListWordRowText.accessibilityLabel(.removed, zh: true) == "已移除的词,此词已从词库中移除,可以删掉这一行")
    }

    /// The words a removed entry shows are v1.35's, verbatim (`da462c4`'s `wordRow`). Mutation,
    /// 2026-10-07: "Removed word" → "Removed" → red here and in `oneLabel`.
    @Test("a removed word says what it said before")
    func removedCopyIsUnchanged() {
        #expect(ListWordRowText.removedLabel(zh: false) == "Removed word")
        #expect(ListWordRowText.removedLabel(zh: true) == "已移除的词")
        #expect(ListWordRowText.removedNote(zh: false) == "No longer in the dictionary — you can remove it")
        #expect(ListWordRowText.removedNote(zh: true) == "此词已从词库中移除,可以删掉这一行")
    }

    /// The column is one element carrying that label, and the Remove button is beside it (or under
    /// it), not in it: its own button, with the identifier the UI test taps and the label it had.
    /// Mutations, 2026-10-07, each red: `.accessibilityElement(children: .combine)` removed from the
    /// column; `.accessibilityElement(children: .combine)` added to `wordRow`'s row (which would
    /// fold the Remove button into the text); the identifier renamed `removeWordButton-\(id)` (also
    /// red in `V135B6WordSearchTests.addUsesTheStore` and `uiTestIsWired`). The column moved after
    /// the Remove button is `columnIsWired`'s now, which pins both of the row's arrangements whole.
    ///
    /// **Held at both ends of the chain, and one level up** (v1.36 review, findings 3 and 4). The
    /// first version read the column's modifiers as a substring, so anything chained after the
    /// label passed — `.accessibilityHidden(true)` hid the word, its reading and its gloss and left
    /// VoiceOver only "Remove 水 from list" — and it read `wordRow` alone, so the same merge one
    /// level up, on the `ForEach` that calls it, passed too. Mutations, 2026-10-07, each red here
    /// and in nothing else in the 4 suites: `.accessibilityHidden(true)` after the column's label
    /// (A2); `.accessibilityLabel("")` after it; `wordRow(id: id, listID: list.id)
    /// .accessibilityElement(children: .combine)` in `ListDetailView.body` (A3); the same modifier
    /// on the `ForEach` itself.
    @Test("the column is one VoiceOver element; Remove stays its own button, removeWord-<id>")
    func oneElementIsWired() throws {
        let column = try Self.columnSource()
        #expect(column.contains(".frame(maxWidth: .infinity, alignment: .leading) .accessibilityElement(children: .combine) .accessibilityLabel(Self.accessibilityLabel(content, zh: zh))"),
                "the column is not one element with its label")
        // The label is the LAST modifier of the column's body: nothing after it can hide or relabel it.
        let columnBody = V135B6WordSearchTests.collapsed(try V133LAccessibilityLayoutTests.body(
            "ListsView.swift", "var body: some View", after: "struct ListWordRowText"))
        #expect(columnBody.hasPrefix("{ VStack(alignment: .leading, spacing: 2) { switch content {")
                && columnBody.hasSuffix(".accessibilityLabel(Self.accessibilityLabel(content, zh: zh)) }"),
                "something is chained after the column's label: …\(columnBody.suffix(120))")
        // One element and one label: the modifier and the `Self.accessibilityLabel(` it calls.
        #expect(column.components(separatedBy: "accessibilityElement").count - 1 == 1
                && columnBody.components(separatedBy: "accessibilityLabel(").count - 1 == 2)
        #expect(!column.contains("accessibilityHidden") && !column.contains("accessibilityRemoveTraits"),
                "the column is hidden from VoiceOver")

        let row = try V135B6WordSearchTests.detail("private func wordRow")
        #expect(!row.contains("accessibilityElement"), "wordRow merges its children — the Remove button with them")
        #expect(row.contains(#".accessibilityIdentifier("removeWord-\(id)")"#))
        #expect(row.contains(#".accessibilityLabel(zh ? "从词单移除 \(entry?.surface ?? id)" : "Remove \(entry?.surface ?? id) from list")"#))

        // One level up: the screen calls `wordRow` bare, and nothing in `ListDetailView` merges or
        // hides an element (it has no `accessibilityElement` or `accessibilityHidden` at all).
        let body = try V135B6WordSearchTests.detail("var body: some View")
        #expect(body.contains(#"ForEach(list.ids, id: \.self) { id in wordRow(id: id, listID: list.id) } } } else { unavailableState }"#),
                "the ForEach that draws the list's words is no longer a bare call to wordRow")
        let file = try Self.listsSource()
        let detail = try #require(file.typeBodies(named: "ListDetailView").first)
        let detailCode = String(decoding: file.code[detail], as: UTF8.self)
        #expect(detailCode.count > 20_000, "the type walk returned \(detailCode.count) characters of ListDetailView")
        #expect(!detailCode.contains("accessibilityElement") && !detailCode.contains("accessibilityHidden"),
                "ListDetailView merges or hides an element — the Remove button with the text, or the word")
    }

    /// What `wordRow` hands the column, and what the column may not do. Mutations, 2026-10-07,
    /// each red: `scale: 1` in `wordRow`; `.lineLimit(1)` back on the gloss; the reading coloured
    /// `Theme.accent2` (the result row's; v1.36 §C asks for the gloss colour here); a removed word's
    /// label coloured `.white`; a missing entry drawn as an empty `.word` instead of `.removed`.
    ///
    /// **The row's two arrangements** (v1.36 review, finding 1): the Remove button beside the
    /// column below the accessibility sizes and under it at them — the geometry `columnWidth`
    /// assumes, pinned whole. Mutations, 2026-10-07, each red here (and in
    /// `V133LAccessibilityLayoutTests.theAccessibilitySwitchesAreStillThere` for the first two): the
    /// row always the `HStack` (v1.36's first version); `typeSize.isAccessibilitySize` → `false`;
    /// the stacked branch with `remove` above `text`.
    ///
    /// **The order of the lines** (finding 5): the word, then its reading, then the gloss — "a
    /// reading line under the surface", which each line's own pin above did not order. Mutations,
    /// 2026-10-07, each red here and in `linesAreInOrder`: the word's and the reading's blocks
    /// swapped (R3); the reading's and the gloss's swapped.
    @Test("wordRow hands the column the text size and stacks Remove at the accessibility sizes; no line is limited; the colours and order are the plan's")
    func columnIsWired() throws {
        let row = try V135B6WordSearchTests.detail("private func wordRow")
        #expect(row.contains("let text = ListWordRowText(content: content, zh: zh, scale: bodyPoints / 17)"))
        #expect(row.contains("} ?? .removed"), "a word with no entry is no longer the removed case")
        #expect(row.range(of: #"\bText\("#, options: .regularExpression) == nil && !row.contains("lineLimit"),
                "wordRow draws text of its own again")
        // The geometry `columnWidth` below assumes.
        #expect(row.contains("return Group { if typeSize.isAccessibilitySize { VStack(alignment: .leading, spacing: 8) { text remove } } else { HStack(spacing: 10) { text remove } } } .padding(.horizontal, 14).padding(.vertical, 10)"),
                "the row no longer puts Remove beside the text below the accessibility sizes and under it at them")
        #expect(row.contains(#"let remove = Button { model.removeWord(id, from: listID) } label: { Image(systemName: "minus.circle") .scaledSystemFont(16) .foregroundStyle(Theme.accent) .padding(6)"#))

        let column = try Self.columnSource()
        #expect(!column.contains("lineLimit") && !column.contains("minimumScaleFactor"), "a line of the column can be cut")
        #expect(column.components(separatedBy: ".fixedSize(horizontal: false, vertical: true)").count - 1 == 5,
                "every line — word, reading, gloss, removed label, note — takes the height it needs")
        #expect(!column.contains("scaledSystemFont"), "a scaledSystemFont inside the column ignores `scale`")
        let gloss = "WordSearchResultRow.glossColor"
        #expect(column.contains("Text(surface) .font(.system(size: Self.wordPoints * scale, weight: .semibold)) .foregroundStyle(.white)"))
        #expect(column.contains("Text(reading) .font(.system(size: Self.readingPoints * scale)) .foregroundStyle(\(gloss))"))
        #expect(column.contains("Text(gloss) .font(.system(size: Self.glossPoints * scale)) .foregroundStyle(\(gloss))"))
        #expect(column.contains("Text(Self.removedLabel(zh: zh)) .font(.system(size: Self.wordPoints * scale, weight: .semibold)) .foregroundStyle(\(gloss))"))
        #expect(column.contains("Text(Self.removedNote(zh: zh)) .font(.system(size: Self.notePoints * scale)) .foregroundStyle(\(gloss))"))
        // In that order, each once: word, reading (only when there is one), gloss.
        let lines = try ["Text(surface)", "if let reading { Text(reading)", "Text(gloss)"].map { line in
            #expect(column.components(separatedBy: line).count - 1 == 1, "\(line) is not drawn exactly once")
            return try #require(column.range(of: line)).lowerBound
        }
        #expect(lines[0] < lines[1] && lines[1] < lines[2], "the column's lines are no longer word, reading, gloss")
        // At the default size the word is what `scaledSystemFont(16, weight: .semibold)` drew, and
        // the gloss and note the iOS `.caption` / `.caption2` sizes.
        #expect(ListWordRowText.wordPoints == 16 && ListWordRowText.glossPoints == 12 && ListWordRowText.notePoints == 11)
    }

    // MARK: 3. The Saved row's star

    /// Mutations, 2026-10-07, each red: the guard without `isDefault` (a learner's "★ Favourites"
    /// loses its star); `dropFirst(1)` (" Saved", a leading space); the prefix "★" without the
    /// space.
    @Test("the Saved row drops its leading star; every other name is shown as it is")
    func rowName() {
        #expect(ListsView.rowName("★ Saved", isDefault: true) == "Saved")
        #expect(ListsView.rowName("★ 收藏", isDefault: true) == "收藏")
        #expect(ListsView.rowName(AppModel.defaultListName("en"), isDefault: true) == "Saved")
        #expect(ListsView.rowName(AppModel.defaultListName("zh"), isDefault: true) == "收藏")
        // Names a learner typed, star or not, as typed — including one spelled like the default.
        for name in ["Verbs", "★ Favourites", "★ Saved", "★ 收藏", "My ★ words", "★Stars", "★"] {
            #expect(ListsView.rowName(name, isDefault: false) == name, "\(name) was changed")
        }
        // A default name with no leading "★ " is left alone, not cut.
        #expect(ListsView.rowName("Saved", isDefault: true) == "Saved")
        #expect(ListsView.rowName("★Saved", isDefault: true) == "★Saved")
    }

    /// Only the Word Lists row uses `rowName`; the stored name, the detail header and the
    /// add-to-lists sheet keep the star, because none of them draws the icon. Mutations,
    /// 2026-10-07, each red: `rowName` applied in `AddToListsSheet.displayName`; `listRow` back to
    /// `displayName(list)`; `AppModel.defaultListName` returning "Saved".
    ///
    /// **All three of the row's VoiceOver labels** (v1.36 review, finding 2). The first version
    /// held only the open button's, so `listRow` handing the play button or the actions menu
    /// `displayName(list)` — "Practice ★ Saved", "More actions for ★ Saved" — passed every test.
    /// Now every control in both of `listRow`'s arrangements takes `name`, `displayName` is read
    /// once there (for `rowName`), and each control's label is built from `name`. Mutations,
    /// 2026-10-07, each red: `playListButton(list, name: displayName(list), …)` in both branches
    /// (S2); `listActionsMenu(list, name: displayName(list))` in both (S3); either in the stacked
    /// branch only; "Practice \(displayName(list))" inside `playListButton`; "More actions for
    /// \(displayName(list))" inside `listActionsMenu`.
    @Test("only the Word Lists row drops the star: the stored name, the detail header and the sheet keep it")
    func rowNameIsOnlyTheRow() throws {
        #expect(AppModel.defaultListName("en") == "★ Saved" && AppModel.defaultListName("zh") == "★ 收藏",
                "the stored name changed — v1.36 changes the row only")
        let code = try Self.listsSource().allCode
        #expect(code.components(separatedBy: "rowName(").count - 1 == 2, "rowName is declared once and called once (listRow)")
        let listRow = V135B6WordSearchTests.collapsed(try V133LAccessibilityLayoutTests.body("ListsView.swift", "private func listRow"))
        #expect(listRow.contains("let name = Self.rowName(displayName(list), isDefault: list.isDefault)"))
        // Every control, in both arrangements, is handed that name and nothing else.
        #expect(listRow.components(separatedBy: "displayName(").count - 1 == 1,
                "listRow reads displayName(list) outside rowName — a control is named with the star again")
        for call in ["openListButton(list, name: name, count: count)",
                     "playListButton(list, name: name, playable: playable)",
                     "listActionsMenu(list, name: name)"] {
            #expect(listRow.components(separatedBy: call).count - 1 == 2, "\(call) is not in both of listRow's arrangements")
        }
        #expect(listRow.components(separatedBy: "name: ").count - 1 == 6, "a control in listRow is named some other way")
        // The row draws that name and reads it out; the icon it no longer repeats is still the star.
        let open = V135B6WordSearchTests.collapsed(try V133LAccessibilityLayoutTests.body("ListsView.swift", "private func openListButton"))
        #expect(open.contains("Text(name).scaledSystemFont(16, weight: .semibold)"))
        #expect(open.contains(#".accessibilityLabel(zh ? "\(name),\(count) 词,打开" : "\(name), \(count) words, open")"#))
        let play = V135B6WordSearchTests.collapsed(try V133LAccessibilityLayoutTests.body("ListsView.swift", "private func playListButton"))
        #expect(play.contains(#".accessibilityLabel(zh ? "\(name),开始练习" : "Practice \(name)")"#))
        let menu = V135B6WordSearchTests.collapsed(try V133LAccessibilityLayoutTests.body("ListsView.swift", "private func listActionsMenu"))
        #expect(menu.contains(#".accessibilityLabel(zh ? "\(name),更多操作" : "More actions for \(name)")"#))
        for control in [open, play, menu] {
            #expect(!control.contains("displayName("), "a control names its list by displayName, star and all")
        }
        let icon = try V133LAccessibilityLayoutTests.body("ListsView.swift", "private func listIcon")
        #expect(icon.contains(#"Image(systemName: list.isDefault ? "star.fill" : "rectangle.stack")"#))
        // The detail header and the sheet name the default list by `AppModel.defaultListName`, star and all.
        let header = try V135B6WordSearchTests.detail("private var header")
        #expect(header.contains("$0.isDefault ? AppModel.defaultListName(model.languageCode) : $0.name"))
        let sheet = V135B6WordSearchTests.collapsed(try V133LAccessibilityLayoutTests.body(
            "ListsView.swift", "private func displayName", after: "struct AddToListsSheet"))
        #expect(sheet.contains("list.isDefault ? AppModel.defaultListName(model.languageCode) : list.name") && !sheet.contains("rowName"))
    }

    // MARK: 4. The column at the accessibility sizes

    #if canImport(AppKit)
    /// The width `wordRow` leaves its text column in a row `rowWidth` wide.
    ///
    /// * **Beside** the Remove button, below the accessibility sizes: less the row's padding (14 a
    ///   side), the HStack's spacing (10) and the button — laid out with the button's own label
    ///   modifiers (pinned in `columnIsWired`), scaled by `emulatedTextScale`, which is how a
    ///   hosted test makes `scaledSystemFont` scale.
    /// * **Stacked** over it, at the accessibility sizes: less the row's padding only.
    ///
    /// The sweep's sizes are the default and the five accessibility sizes, so in it `stacked` is
    /// `scale > 1` (`V135B6WordSearchTests.row` makes the same call for the result row). The row
    /// widths are `V135B6WordSearchTests.widths`: a 402pt and a 320pt phone less the detail
    /// screen's 22pt padding a side.
    static func columnWidth(row rowWidth: CGFloat, scale: CGFloat, stacked: Bool) -> CGFloat {
        if stacked { return rowWidth - 2 * 14 }
        let button = V134B5RomajiHintTests.laidOut(
            Image(systemName: "minus.circle").scaledSystemFont(16).padding(6).environment(\.emulatedTextScale, scale),
            width: 400, height: nil)
        return rowWidth - 2 * 14 - 10 - button.width
    }

    /// The column `wordRow` leaves at one of the sweep's sizes.
    static func columnWidth(row rowWidth: CGFloat, scale: CGFloat) -> CGFloat {
        columnWidth(row: rowWidth, scale: scale, stacked: scale > 1)
    }

    static func word(_ surface: String, _ reading: String?, _ gloss: String, scale: CGFloat) -> ListWordRowText {
        ListWordRowText(content: .word(surface: surface, reading: reading, gloss: gloss), zh: false, scale: scale)
    }

    /// The instrument, calibrated: `V135B6WordSearchTests.lastIsDrawn` is the one this sweep reads,
    /// and its own control (`instrumentControl`) shows it seeing a gloss cut by a line limit. Here,
    /// the button's width grows with the size as a button's should, so the column the beside
    /// arrangement leaves is measured and not a guess; and stacked, the column is the row's.
    /// Mutations, 2026-10-07, each red: `columnWidth` without `emulatedTextScale` (a button that
    /// never grows); the stacked branch returning the beside width (v1.36's first row).
    @Test("control: beside, the column narrows as the Remove button grows; stacked, it is the row's")
    func columnWidthIsMeasured() throws {
        let ax5 = try #require(V135B6WordSearchTests.scales.last)
        let small = Self.columnWidth(row: 358, scale: 1)
        let beside = Self.columnWidth(row: 358, scale: ax5, stacked: false), stacked = Self.columnWidth(row: 358, scale: ax5)
        print("V136 COLUMN: 358pt row → \(small)pt at the default size; at AX5 \(beside)pt beside Remove, \(stacked)pt stacked. 276pt row → \(Self.columnWidth(row: 276, scale: 1)) / \(Self.columnWidth(row: 276, scale: ax5, stacked: false)) / \(Self.columnWidth(row: 276, scale: ax5))")
        #expect(small > 280 && small < 300, "the default column is \(small)pt")
        #expect(beside < small - 25, "the AX5 column beside Remove is \(beside)pt, the default \(small)pt — the button did not grow")
        #expect(stacked == 358 - 28 && stacked > small, "stacked at AX5 the column is \(stacked)pt")
    }

    /// Every line of the worst word, at the default size and each accessibility size, with each
    /// language's worst gloss, in both phones' columns: the last character of the word, the reading
    /// and the gloss is drawn, and a gloss wider than the column on one line takes more than one
    /// line in it. Mutations, 2026-10-07, each red: `.lineLimit(1)` on the gloss (the v1.35 row);
    /// `.lineLimit(1)` on the word; `.lineLimit(1)` on the reading; the reading line removed; the
    /// gloss's `.fixedSize(horizontal: true, vertical: true)` (one line, however wide).
    @Test("the worst word draws every line whole, and a wide gloss wraps, at every size, in both languages")
    func worstWordIsWhole() throws {
        let started = ContinuousClock.now
        let worst = V135B6WordSearchTests.worst
        var wrapped = ["en": 0, "zh": 0]
        var fits: [String] = []
        var cases = 0
        for rowWidth in V135B6WordSearchTests.widths {
            for scale in V135B6WordSearchTests.scales {
                let width = Self.columnWidth(row: rowWidth, scale: scale)
                let short = V134B5RomajiHintTests.laidOut(Self.word(worst.surface, worst.reading, "x", scale: scale),
                                                          width: width, height: nil)
                for (language, gloss) in [("en", worst.glossEN), ("zh", worst.glossZH)] {
                    let label = "\(rowWidth)pt row, \(String(format: "%.0f", width))pt column, ×\(String(format: "%.2f", scale)), \(language)"
                    #expect(V135B6WordSearchTests.lastIsDrawn(worst.surface, width: width) { Self.word($0, worst.reading, gloss, scale: scale) },
                            "\(label): the word's last character is not drawn")
                    #expect(V135B6WordSearchTests.lastIsDrawn(worst.reading, width: width) { Self.word(worst.surface, $0, gloss, scale: scale) },
                            "\(label): the reading's last character is not drawn")
                    #expect(V135B6WordSearchTests.lastIsDrawn(gloss, width: width) { Self.word(worst.surface, worst.reading, $0, scale: scale) },
                            "\(label): the gloss's last character is not drawn")
                    let oneLine = V134B5RomajiHintTests.laidOut(
                        Text(gloss).font(.system(size: ListWordRowText.glossPoints * scale)).fixedSize(), width: 10_000, height: nil)
                    let whole = V134B5RomajiHintTests.laidOut(Self.word(worst.surface, worst.reading, gloss, scale: scale),
                                                              width: width, height: nil)
                    #expect(whole.width <= width + 0.5, "\(label): the column is \(whole.width)pt, wider than its \(width)pt")
                    if oneLine.width > width {
                        wrapped[language, default: 0] += 1
                        #expect(whole.height - short.height >= 0.9 * oneLine.height,
                                "\(label): a \(oneLine.width)pt gloss added \(whole.height - short.height)pt to the row, under one more line (\(oneLine.height)pt) — it did not wrap")
                    } else {
                        fits.append("\(label) (\(String(format: "%.1f", oneLine.width))pt)")
                    }
                    cases += 1
                }
            }
        }
        #expect(cases == 24)
        // The sweep exercised wrapping in both languages: the 83-character English gloss is wider
        // than every column at every size, and the 17-character Chinese one at most accessibility
        // sizes. Measured 9 of 12 on 2026-10-07 with Remove beside the column; 8 of 12 once it
        // stacked at the accessibility sizes (review, finding 1), since the wide phone's column
        // then holds the Chinese gloss on one line at AX1 and AX2 as well as at the default size —
        // every size in the 248pt column but the default, and AX3 up in the 330pt one. Held at 8:
        // the case nearest the edge, AX2 in the 330pt column, is on the side that fits, so a
        // font's metrics moving a point can only add a wrapped case, while a sweep that stopped
        // wrapping Chinese still fails.
        #expect(wrapped["en"] == 12, "the English gloss was wider than its column in \(wrapped["en"] ?? 0) of 12 cases")
        #expect((wrapped["zh"] ?? 0) >= 8, "the Chinese gloss was wider than its column in only \(wrapped["zh"] ?? 0) cases")
        print("V136 SWEEP: \(cases) cases, gloss wider than its column in en \(wrapped["en"] ?? 0) / zh \(wrapped["zh"] ?? 0); on one line: \(fits); \(ContinuousClock.now - started)")
    }

    /// Offered only a sliver of height, as a squeezed stack would offer it, the column still takes
    /// the height its lines need. Mutations, 2026-10-07, each red: the gloss's
    /// `.fixedSize(horizontal: false, vertical: true)` removed; the reading's removed.
    @Test("the column takes the height its text needs")
    func columnIsNotClippedToAFixedHeight() throws {
        let worst = V135B6WordSearchTests.worst
        let ax5 = try #require(V135B6WordSearchTests.scales.last)
        let width = Self.columnWidth(row: 358, scale: ax5)
        for gloss in [worst.glossEN, worst.glossZH] {
            let view = Self.word(worst.surface, worst.reading, gloss, scale: ax5)
            let offered = V134B5RomajiHintTests.laidOut(view, width: width, height: 40)
            let free = V134B5RomajiHintTests.laidOut(view, width: width, height: nil)
            #expect(offered.height == free.height, "offered 40pt it took \(offered.height), free \(free.height)")
        }
    }

    /// A removed word's two lines take the height each needs alone, at every size and in both
    /// languages, and still do when squeezed. Calibrated: at AX5 in the narrow column the note is
    /// more than one line, so the sum is not trivially one line each. Mutations, 2026-10-07, each
    /// red: `.lineLimit(1)` on the note; the note's `.fixedSize(horizontal: false, vertical: true)`
    /// removed.
    @Test("a removed word's label and note are whole at every size, in both languages")
    func removedWordIsWhole() throws {
        func height(_ view: some View, _ width: CGFloat, _ offered: CGFloat? = nil) -> CGFloat {
            V134B5RomajiHintTests.laidOut(view, width: width, height: offered).height
        }
        var noteLines: CGFloat = 0
        for rowWidth in V135B6WordSearchTests.widths {
            for scale in V135B6WordSearchTests.scales {
                let width = Self.columnWidth(row: rowWidth, scale: scale)
                for zh in [false, true] {
                    let column = ListWordRowText(content: .removed, zh: zh, scale: scale)
                    let label = height(Text(ListWordRowText.removedLabel(zh: zh))
                        .font(.system(size: ListWordRowText.wordPoints * scale, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true), width)
                    let note = height(Text(ListWordRowText.removedNote(zh: zh))
                        .font(.system(size: ListWordRowText.notePoints * scale))
                        .fixedSize(horizontal: false, vertical: true), width)
                    let line = height(Text("x").font(.system(size: ListWordRowText.notePoints * scale)), width)
                    noteLines = max(noteLines, note / line)
                    let whole = height(column, width)
                    #expect(abs(whole - (label + 2 + note)) < 1,
                            "\(rowWidth)pt ×\(scale) zh \(zh): the column is \(whole)pt, its lines alone \(label) + 2 + \(note)")
                    #expect(height(column, width, 20) == whole, "\(rowWidth)pt ×\(scale) zh \(zh): squeezed to 20pt it gave way")
                }
                // And no English word of either line is wider than the column, so neither breaks
                // inside a word. Beside the Remove button, "Removed" (210pt semibold at AX5, 187 at
                // AX4) broke in the 320pt phone's 168 / 173pt column; v1.35's row did the same.
                // Mutation, 2026-10-07: the stacked `columnWidth` returning the beside width → red
                // at AX4 and AX5 on the 320pt phone.
                for (text, points, weight) in [(ListWordRowText.removedLabel(zh: false), ListWordRowText.wordPoints, Font.Weight.semibold),
                                               (ListWordRowText.removedNote(zh: false), ListWordRowText.notePoints, .regular)] {
                    for piece in text.split(separator: " ") {
                        let wide = V134B5RomajiHintTests.laidOut(
                            Text(String(piece)).font(.system(size: points * scale, weight: weight)).fixedSize(),
                            width: 10_000, height: nil).width
                        #expect(wide <= width, "\(rowWidth)pt ×\(String(format: "%.2f", scale)): “\(piece)” is \(wide)pt in a \(width)pt column")
                    }
                }
            }
        }
        print("V136 REMOVED: the note's tallest is \(String(format: "%.1f", noteLines)) lines")
        #expect(noteLines >= 2.5, "control: the note never took more than \(noteLines) lines, so the sweep says little")
    }

    /// The reading is drawn under the word and the gloss under the reading — read from the pixels:
    /// the rows that change when the word's last character changes are all above the rows that
    /// change with the reading's, which are all above the gloss's. Each character is swapped for
    /// one in the same script, so the line's font and height stay put. (v1.36 review, finding 5:
    /// each line's pin said what the line is and not where it is.) Mutations, 2026-10-07, each red
    /// here and in `columnIsWired`: the word's and the reading's blocks swapped (R3); the reading's
    /// and the gloss's swapped.
    @Test("the column draws the word, then the reading under it, then the gloss")
    func linesAreInOrder() throws {
        let ax5 = try #require(V135B6WordSearchTests.scales.last)
        for (scale, rowWidth) in [(CGFloat(1), CGFloat(358)), (ax5, 276)] {
            let width = Self.columnWidth(row: rowWidth, scale: scale)
            func pixels(_ surface: String, _ reading: String, _ gloss: String) throws -> V134B5RomajiHintTests.Bitmap {
                try #require(V134B5RomajiHintTests.render(Self.word(surface, reading, gloss, scale: scale), width: width, height: nil))
            }
            let base = try pixels("一生懸命", "いっしょうけんめい", "with all one's might")
            func rows(_ other: V134B5RomajiHintTests.Bitmap) throws -> ClosedRange<Int> {
                try #require(other.width == base.width && other.height == base.height, "a swap changed the column's size")
                let stride = base.width * 4
                let changed = (0..<base.height).filter {
                    base.bytes[$0 * stride ..< ($0 + 1) * stride] != other.bytes[$0 * stride ..< ($0 + 1) * stride]
                }
                return try #require(changed.first.flatMap { first in changed.last.map { first...$0 } }, "a swap changed no pixel")
            }
            let word = try rows(pixels("一生懸今", "いっしょうけんめい", "with all one's might"))
            let reading = try rows(pixels("一生懸命", "いっしょうけんめぃ", "with all one's might"))
            let gloss = try rows(pixels("一生懸命", "いっしょうけんめい", "with all one's mighx"))
            print("V136 ORDER ×\(String(format: "%.2f", scale)): rows word \(word), reading \(reading), gloss \(gloss)")
            #expect(word.upperBound < reading.lowerBound, "×\(scale): the reading is not under the word (\(word) / \(reading))")
            #expect(reading.upperBound < gloss.lowerBound, "×\(scale): the gloss is not under the reading (\(reading) / \(gloss))")
        }
    }

    // MARK: 5. A word broken inside itself

    /// Whether CoreText, laying `text` out at `points` in a column `width` wide in the system font
    /// (`V134B1TomorrowLineTests.lineTexts`), ends a line inside a Latin word: an ASCII letter or
    /// digit on both sides of the break. A break at a space, after a hyphen or a slash, or between
    /// two Chinese characters is not one.
    nonisolated static func breaksAWord(_ text: String, points: Double, width: Double) throws -> Bool {
        let lines = try V134B1TomorrowLineTests.lineTexts(text, points: points, width: width)
        return zip(lines, lines.dropFirst()).contains { above, below in
            guard let last = above.unicodeScalars.last, let first = below.unicodeScalars.first else { return false }
            return isWordScalar(last) && isWordScalar(first)
        }
    }

    nonisolated static func isWordScalar(_ scalar: Unicode.Scalar) -> Bool {
        scalar.isASCII && (scalar.properties.isAlphabetic || ("0"..."9").contains(scalar))
    }

    /// The ids of the glosses CoreText breaks inside a word at `points` in `width`. Only a gloss with
    /// a space-separated piece wider than the column can be — a piece that fits a line is wrapped
    /// whole — so the others are not laid out, which keeps the 7,071 glosses × 2 languages × 34
    /// columns below to about a second. `pieces` caches each piece's width at these `points`.
    nonisolated static func brokenMidWord(_ glosses: [(id: String, gloss: String)], points: Double, width: Double,
                                          pieces: inout [String: Double]) throws -> [String] {
        let font = try #require(CTFontCreateUIFontForLanguage(.system, points, nil))
        var broken: [String] = []
        for (id, gloss) in glosses {
            var wide = false
            for piece in gloss.split(whereSeparator: \.isWhitespace) where piece.unicodeScalars.contains(where: isWordScalar) {
                let key = String(piece)
                let measured = pieces[key] ?? CTLineGetTypographicBounds(
                    CTLineCreateWithAttributedString(NSAttributedString(string: key, attributes: [.font: font])), nil, nil, nil)
                pieces[key] = measured
                if measured > width { wide = true; break }
            }
            if wide, try breaksAWord(gloss, points: points, width: width) { broken.append(id) }
        }
        return broken
    }

    /// **A gloss breaks between its words, not inside one** (v1.36 review, finding 1). The sweep
    /// above cannot see this: a word broken mid-word still draws its last letter, and still wraps.
    /// So every gloss in the corpus, in both languages, is laid out by CoreText at the gloss's size
    /// in the column `wordRow` leaves it, at the default size and the five accessibility sizes, on
    /// both phones, and the glosses with a line ending inside a word are counted — and, as the
    /// control, the same in the column the Remove button left beside it at the accessibility sizes
    /// (v1.36's first row, and v1.35's).
    ///
    /// Measured 2026-10-07 (printed as `V136 MIDWORD`), of 7,071 English glosses:
    /// * **beside the button** (v1.36's first row): on the 320pt phone 1,476 at AX5 (29 of them
    ///   N5 — 便利 "convenient", 新聞 "newspaper", 水曜日 "Wednesday" …), 573 at AX4, 62 at AX3 and
    ///   1 at AX2; on the 402pt phone 36 at AX5 and 8 at AX4. The review's own count, splitting
    ///   words by hand, was 1,469 / 36.
    /// * **as shown now, stacked:** the 402pt phone none at any size; the 320pt phone 37 at AX5
    ///   and 9 at AX4, none of them N5. **That is the residue**: a single word wider than the
    ///   whole 248pt line at 37pt — "otorhinolaryngology", "nearsightedness", "misunderstanding",
    ///   "recommendation", "communication" — which no arrangement of this row can fit, the way
    ///   `ListsView.listRow` records "Vocabulary" at 255pt. Held at 46 here: never raised.
    /// * the default size breaks none, and no Chinese gloss breaks inside a Latin word at any size.
    ///
    /// Mutations, 2026-10-07, each red: the stacked `columnWidth` returning the beside width (the
    /// first row — the residue goes to 2,156); `isWordScalar` returning false for every scalar (an
    /// instrument that sees no break: the control below, and `midWordInstrumentMatchesSwiftUI`).
    @Test("a gloss breaks between its words, not inside one, but for the residue named here")
    func glossWordsAreWhole() throws {
        let started = ContinuousClock.now
        let entries = VocabStore.shared.entries
        let n5 = Set(entries.filter { $0.jlpt == .n5 }.map(\.id))
        let ax5 = try #require(V135B6WordSearchTests.scales.last)
        var counts: [String: Int] = [:]
        var stackedN5 = 0
        var lines: [String] = []
        for language in ["en", "zh"] {
            let glosses = entries.map { (id: $0.id, gloss: $0.gloss(for: language)) }
            for scale in V135B6WordSearchTests.scales {
                let points = Double(ListWordRowText.glossPoints * scale)
                var pieces: [String: Double] = [:]
                for rowWidth in V135B6WordSearchTests.widths {
                    let shown = try Self.brokenMidWord(glosses, points: points, width: Double(Self.columnWidth(row: rowWidth, scale: scale)),
                                                       pieces: &pieces)
                    let size = "\(Int(rowWidth + 44))pt ×\(String(format: "%.2f", scale)) \(language)"
                    counts["shown \(size)"] = shown.count
                    stackedN5 += shown.filter(n5.contains).count
                    if !shown.isEmpty, scale == ax5 {
                        let byID = Dictionary(uniqueKeysWithValues: glosses.map { ($0.id, $0.gloss) })
                        print("V136 MIDWORD RESIDUE \(size): \(shown.prefix(12).map { "\($0) “\(byID[$0] ?? "")”" })")
                    }
                    var line = "\(size): \(shown.count) shown"
                    if scale > 1 {
                        let beside = try Self.brokenMidWord(glosses, points: points,
                                                            width: Double(Self.columnWidth(row: rowWidth, scale: scale, stacked: false)),
                                                            pieces: &pieces)
                        counts["beside \(size)"] = beside.count
                        line += ", \(beside.count) beside Remove (\(beside.filter(n5.contains).count) N5)"
                    }
                    lines.append(line)
                }
            }
        }
        print("V136 MIDWORD: \(lines.joined(separator: "; ")); \(ContinuousClock.now - started)")

        let shown = counts.filter { $0.key.hasPrefix("shown ") }
        #expect(shown.count == 24)
        // The default size, the 402pt phone at every size, and every Chinese gloss: none.
        #expect(shown.filter { $0.key.contains("×1.00") || $0.key.contains("402pt") || $0.key.hasSuffix(" zh") }
                    .allSatisfy { $0.value == 0 },
                "\(shown.filter { $0.value > 0 }.sorted { $0.key < $1.key })")
        // The residue: the 320pt phone's English at the accessibility sizes, never more than measured.
        let residue = shown.values.reduce(0, +)
        #expect(residue <= 46 && stackedN5 == 0, "\(residue) glosses (\(stackedN5) N5) break inside a word as shown: \(shown.filter { $0.value > 0 }.sorted { $0.key < $1.key })")
        // Control: the instrument sees the defect stacking fixed, where the review measured it.
        let beside = try #require(counts["beside 320pt ×\(String(format: "%.2f", ax5)) en"])
        #expect(beside > 1_000, "beside the button at AX5 on the 320pt phone only \(beside) glosses broke a word")
    }

    /// The instrument agrees with SwiftUI. 便利's gloss at AX5, in the 320pt phone's column: beside
    /// the button (168pt) SwiftUI's `Text` takes two lines for the one word and CoreText ends a line
    /// inside it; stacked (248pt), one line, and no break. Mutation, 2026-10-07: `isWordScalar`
    /// returning false for letters → red (CoreText "sees" no break beside).
    @Test("control: CoreText's word break is SwiftUI's — 便利's “convenient” at AX5")
    func midWordInstrumentMatchesSwiftUI() throws {
        let benri = try #require(VocabStore.shared.entry(id: "n5-g117"))
        #expect(benri.surface == "便利" && benri.gloss(for: "en").hasPrefix("convenient"), "\(benri.gloss(for: "en"))")
        let ax5 = try #require(V135B6WordSearchTests.scales.last)
        let points = ListWordRowText.glossPoints * ax5
        let line = V134B5RomajiHintTests.laidOut(Text("x").font(.system(size: points)), width: 1_000, height: nil).height
        for (stacked, lines) in [(false, 2), (true, 1)] {
            let width = Self.columnWidth(row: 276, scale: ax5, stacked: stacked)
            let height = V134B5RomajiHintTests.laidOut(
                Text("convenient").font(.system(size: points)).fixedSize(horizontal: false, vertical: true),
                width: width, height: nil).height
            #expect(abs(height / line - CGFloat(lines)) < 0.2, "stacked \(stacked): “convenient” takes \(height / line) lines in \(width)pt")
            #expect(try Self.breaksAWord("convenient", points: Double(points), width: Double(width)) == !stacked,
                    "stacked \(stacked): CoreText disagrees with SwiftUI about “convenient” in \(width)pt")
        }
    }
    #endif
}
