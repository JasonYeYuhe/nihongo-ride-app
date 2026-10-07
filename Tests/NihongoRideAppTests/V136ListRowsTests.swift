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
/// in the width `wordRow` leaves it beside the Remove button on a 402pt and a 320pt phone, and read
/// back from the pixels (section 4) — possible because the column takes its text size as `scale`,
/// as `WordSearchResultRow` does; a hosted view on macOS ignores `dynamicTypeSize`. VoiceOver's one
/// element is a label tested as a value plus a source pin on the modifier that makes it one: a
/// hosted `NSHostingView` exposed no accessibility children to a probe on 2026-10-07 (one AXGroup,
/// no children, with the window ordered front), so the tree itself is the simulator pass's to read.
/// Whether the screen around the rows scrolls and the Remove button stays tappable at AX5 on a
/// phone is that pass's question too, with `WordListSearchFlowTests`, which adds 水 from search and
/// then finds the Remove button `removeWord-n5-mizu` in the list below — the identifier this change
/// keeps (`oneElementIsWired`).
///
/// Every test here was shown able to fail: the mutations that turned each one red, on 2026-10-07,
/// are named on it (34 in all, each applied, run, seen red and reverted). Not every `#expect` has
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

    /// The column is one element carrying that label, and the Remove button is beside it, not in
    /// it: its own button, with the identifier the UI test taps and the label it had. Mutations,
    /// 2026-10-07, each red: `.accessibilityElement(children: .combine)` removed from the column;
    /// `.accessibilityElement(children: .combine)` added to `wordRow`'s HStack (which would fold the
    /// Remove button into the text); the identifier renamed `removeWordButton-\(id)` (also red in
    /// `V135B6WordSearchTests.addUsesTheStore` and `uiTestIsWired`); the column moved after the
    /// Remove button.
    @Test("the column is one VoiceOver element; Remove stays its own button, removeWord-<id>")
    func oneElementIsWired() throws {
        let column = try Self.columnSource()
        #expect(column.contains(".frame(maxWidth: .infinity, alignment: .leading) .accessibilityElement(children: .combine) .accessibilityLabel(Self.accessibilityLabel(content, zh: zh))"),
                "the column is not one element with its label")
        let row = try V135B6WordSearchTests.detail("private func wordRow")
        #expect(!row.contains("accessibilityElement"), "wordRow merges its children — the Remove button with them")
        let text = try #require(row.range(of: "ListWordRowText("))
        let button = try #require(row.range(of: "Button { model.removeWord(id, from: listID) } label: { Image(systemName: \"minus.circle\")"))
        #expect(text.lowerBound < button.lowerBound, "the text column is no longer before the Remove button")
        #expect(row.contains(#".accessibilityIdentifier("removeWord-\(id)")"#))
        #expect(row.contains(#".accessibilityLabel(zh ? "从词单移除 \(entry?.surface ?? id)" : "Remove \(entry?.surface ?? id) from list")"#))
    }

    /// What `wordRow` hands the column, and what the column may not do. Mutations, 2026-10-07,
    /// each red: `scale: 1` in `wordRow`; `.lineLimit(1)` back on the gloss; the reading coloured
    /// `Theme.accent2` (the result row's; v1.36 §C asks for the gloss colour here); a removed word's
    /// label coloured `.white`; a missing entry drawn as an empty `.word` instead of `.removed`.
    @Test("wordRow hands the column the text size; no line is limited; the colours are the plan's")
    func columnIsWired() throws {
        let row = try V135B6WordSearchTests.detail("private func wordRow")
        #expect(row.contains("ListWordRowText(content: content, zh: zh, scale: bodyPoints / 17)"))
        #expect(row.contains("} ?? .removed"), "a word with no entry is no longer the removed case")
        #expect(row.range(of: #"\bText\("#, options: .regularExpression) == nil && !row.contains("lineLimit"),
                "wordRow draws text of its own again")
        // The geometry `columnWidth` below assumes.
        #expect(row.contains("return HStack(spacing: 10) { ListWordRowText("))
        #expect(row.contains(#"label: { Image(systemName: "minus.circle") .scaledSystemFont(16) .foregroundStyle(Theme.accent) .padding(6)"#))
        #expect(row.contains(".padding(.horizontal, 14).padding(.vertical, 10)"))

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
    @Test("only the Word Lists row drops the star: the stored name, the detail header and the sheet keep it")
    func rowNameIsOnlyTheRow() throws {
        #expect(AppModel.defaultListName("en") == "★ Saved" && AppModel.defaultListName("zh") == "★ 收藏",
                "the stored name changed — v1.36 changes the row only")
        let code = try Self.listsSource().allCode
        #expect(code.components(separatedBy: "rowName(").count - 1 == 2, "rowName is declared once and called once (listRow)")
        let listRow = V135B6WordSearchTests.collapsed(try V133LAccessibilityLayoutTests.body("ListsView.swift", "private func listRow"))
        #expect(listRow.contains("let name = Self.rowName(displayName(list), isDefault: list.isDefault)"))
        // The row draws that name and reads it out; the icon it no longer repeats is still the star.
        let open = V135B6WordSearchTests.collapsed(try V133LAccessibilityLayoutTests.body("ListsView.swift", "private func openListButton"))
        #expect(open.contains("Text(name).scaledSystemFont(16, weight: .semibold)"))
        #expect(open.contains(#".accessibilityLabel(zh ? "\(name),\(count) 词,打开" : "\(name), \(count) words, open")"#))
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
    /// The width `wordRow` leaves its text column in a row `rowWidth` wide: less the row's padding
    /// (14 a side), the HStack's spacing (10) and the Remove button — laid out with the button's own
    /// label modifiers (pinned in `columnIsWired`), scaled by `emulatedTextScale`, which is how a
    /// hosted test makes `scaledSystemFont` scale. The row widths are `V135B6WordSearchTests.widths`:
    /// a 402pt and a 320pt phone less the detail screen's 22pt padding a side.
    static func columnWidth(row rowWidth: CGFloat, scale: CGFloat) -> CGFloat {
        let button = V134B5RomajiHintTests.laidOut(
            Image(systemName: "minus.circle").scaledSystemFont(16).padding(6).environment(\.emulatedTextScale, scale),
            width: 400, height: nil)
        return rowWidth - 2 * 14 - 10 - button.width
    }

    static func word(_ surface: String, _ reading: String?, _ gloss: String, scale: CGFloat) -> ListWordRowText {
        ListWordRowText(content: .word(surface: surface, reading: reading, gloss: gloss), zh: false, scale: scale)
    }

    /// The instrument, calibrated: `V135B6WordSearchTests.lastIsDrawn` is the one this sweep reads,
    /// and its own control (`instrumentControl`) shows it seeing a gloss cut by a line limit. Here,
    /// the button's width grows with the size as a button's should, so the column the sweep lays
    /// out is the one the row leaves and not a guess. Mutation, 2026-10-07: `columnWidth` without
    /// `emulatedTextScale` (a button that never grows) → red.
    @Test("control: the column narrows as the Remove button grows")
    func columnWidthIsMeasured() throws {
        let scales = V135B6WordSearchTests.scales
        let small = Self.columnWidth(row: 358, scale: 1), ax5 = Self.columnWidth(row: 358, scale: try #require(scales.last))
        print("V136 COLUMN: 358pt row → \(small)pt at the default size, \(ax5)pt at AX5; 276pt row → \(Self.columnWidth(row: 276, scale: 1)) / \(Self.columnWidth(row: 276, scale: scales.last!))")
        #expect(small > 280 && small < 300, "the default column is \(small)pt")
        #expect(ax5 < small - 25, "the AX5 column is \(ax5)pt, the default \(small)pt — the button did not grow")
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
                        fits.append(label)
                    }
                    cases += 1
                }
            }
        }
        #expect(cases == 24)
        // The sweep exercised wrapping in both languages: the 83-character English gloss is wider
        // than every column at every size, and the 17-character Chinese one at the accessibility
        // sizes — measured 9 of 12 on 2026-10-07 (all but the default size in both columns and AX1
        // in the wide one); held at 8, every size from AX2 up in both, so a font's metrics moving a
        // point cannot fail it while a sweep that stopped wrapping Chinese still does.
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
            }
        }
        print("V136 REMOVED: the note's tallest is \(String(format: "%.1f", noteLines)) lines")
        #expect(noteLines >= 2.5, "control: the note never took more than \(noteLines) lines, so the sweep says little")
    }
    #endif
}
