import Testing
import Foundation
import SwiftUI
import CustomTextKit
@testable import NihongoRideApp

/// v1.34 §B2 — the two defects in the learner's own texts: the silent cut, and the Mac's missing
/// delete. What is held here: the notice's wording, that what Add stores through the model is the
/// text the notice describes, that the sheet draws the notice whenever there is one and keeps Add
/// enabled, that the notice is ABOVE the editor — in its section's header, since the simulator
/// pass (2026-09-27) found the footer 3,800pt down the sheet after a long paste — that Add's
/// action adds the editor's text under no condition on the truncation, and the shape of the Mac's
/// delete. The cut's own numbers live in
/// `CustomTextTruncationTests`, beside the cut.
///
/// What is NOT held here: the state plumbing between the editor and the notice view. The pins
/// read the sheet's `.onChange(of: source)` action and the one `CustomTextTruncationNotice(...)`
/// it builds; the render test holds the notice VIEW. Nothing reads the declaration of the
/// `@State private var truncation`, and no test runs the sheet — so a property observer on that
/// state (a `didSet` that sets it back to nil for one unit, say) could still hide the notice
/// with every test here green.
///
/// The source pins read `CustomTextsView.swift` through `CallSiteScanner`, so a modifier named in
/// a comment does not count and a string quoted in a comment does not count (both `//` and
/// `/* */` are blanked). Each pin asserts a count of one before it asserts anything about the
/// one, so a scan that found nothing cannot pass as a scan that found nothing wrong.
@MainActor
@Suite("v1.34 B2: the add sheet says what it cut, and every row can be deleted on the Mac")
struct V134B2CustomTextTests {

    static func shipped(_ name: String) throws -> CallSiteScanner.File {
        try #require(try CallSiteScanner.shippedSources.get().first { $0.path == "Sources/NihongoRideApp/\(name)" },
                     "\(name) not found")
    }

    /// Byte offsets of a literal in the comment-stripped, string-keeping code.
    static func literal(_ text: String, in file: CallSiteScanner.File) -> [Int] {
        CallSiteScanner.occurrences(of: Array(text.utf8), in: file.codeWithStrings)
    }

    /// A range of code, whitespace removed. `strings` keeps string contents (comments are gone
    /// either way).
    static func squeezed(_ range: Range<Int>?, in file: CallSiteScanner.File, strings: Bool = false) -> String {
        guard let range else { return "" }
        let bytes = strings ? file.codeWithStrings[range] : file.code[range]
        return String(decoding: bytes, as: UTF8.self).filter { !$0.isWhitespace }
    }

    /// `count` sentences of `length` characters each: `length - 1` あ and a 。.
    static func sentences(_ count: Int, length: Int) -> String {
        String(repeating: String(repeating: "あ", count: length - 1) + "。", count: count)
    }

    // MARK: 1. The notice

    @Test("the notice is one line, both languages, written out by hand")
    func noticeStrings() {
        let sentences = CustomText.Truncation.sentences(kept: 200, dropped: 1_300)
        #expect(CustomTextAddView.truncationNotice(sentences, zh: false)
                == "Only the first 200 sentences are kept — 1,300 dropped.")
        #expect(CustomTextAddView.truncationNotice(sentences, zh: true)
                == "只保留前 200 句,已去掉 1,300 句。")

        let characters = CustomText.Truncation.characters(kept: 20_000, dropped: 5_000)
        #expect(CustomTextAddView.truncationNotice(characters, zh: false)
                == "Only the first 20,000 characters are kept — 5,000 dropped.")
        #expect(CustomTextAddView.truncationNotice(characters, zh: true)
                == "只保留前 20,000 个字符,已去掉 5,000 个。")

        // The plan's 201-sentence case.
        let one = CustomText.Truncation.sentences(kept: 200, dropped: 1)
        #expect(CustomTextAddView.truncationNotice(one, zh: false)
                == "Only the first 200 sentences are kept — 1 dropped.")
        #expect(CustomTextAddView.truncationNotice(one, zh: true) == "只保留前 200 句,已去掉 1 句。")
    }

    // MARK: 2. What Add stores is what the notice describes

    /// Through `AppModel.addCustomText` — the path the Add button takes — and not through
    /// `CustomText.make`, so a second cut or a normalisation in the add path is caught. Both
    /// numbers are compared: what is stored against the notice's kept, and the paste's hand-counted
    /// total less what is stored against the notice's dropped. The third fixture opens with
    /// whitespace, has a blank line between sentences and closes with whitespace: the notice counts
    /// those characters toward the 20,000, so an add path that trimmed the paste or collapsed its
    /// blank lines would store more of the last sentence than the notice says.
    @Test("a text added through the model is the text the notice describes, in both units")
    func addedThroughTheModelMatchesTheNotice() throws {
        let model = CustomTextRunTests.model()

        // Sentences: 300 sentences of 100 characters; 200 stored, 100 dropped.
        let long = Self.sentences(300, length: 100)
        #expect(long.count == 30_000)
        let sentenceNotice = try #require(CustomText.truncation(of: long))
        #expect(sentenceNotice == .sentences(kept: 200, dropped: 100))
        let sentenceID = try #require(model.addCustomText(title: "s", source: long))
        let storedSentences = try #require(model.customTexts.text(id: sentenceID)).sentences.count
        #expect(storedSentences == 200)
        #expect(.sentences(kept: storedSentences, dropped: 300 - storedSentences) == sentenceNotice,
                "stored \(storedSentences) of 300 sentences; the notice says \(sentenceNotice)")

        // Characters: 150 sentences of 100, then one of 10,000 spanning character 20,000 —
        // 25,000 characters; 20,000 stored, 5,000 dropped.
        let spanning = Self.sentences(150, length: 100) + String(repeating: "う", count: 9_999) + "。"
        #expect(spanning.count == 25_000)
        let characterNotice = try #require(CustomText.truncation(of: spanning))
        #expect(characterNotice == .characters(kept: 20_000, dropped: 5_000))
        let characterID = try #require(model.addCustomText(title: "c", source: spanning))
        let stored = try #require(model.customTexts.text(id: characterID))
        let storedCharacters = stored.sentences.reduce(0) { $0 + $1.source.count }
        #expect(storedCharacters == 20_000)
        #expect(.characters(kept: storedCharacters, dropped: 25_000 - storedCharacters) == characterNotice,
                "stored \(storedCharacters) of 25,000 characters; the notice says \(characterNotice)")

        // Whitespace: "  \n\n" (4), 150 sentences of 100 with a blank line ("\n\n") between each
        // (15,000 + 149 × 2), "\n\n" (2), one sentence of 10,000 う, "\n\n  " (4) — 25,308
        // characters. Before the う sentence: 4 + 15,298 + 2 = 15,304, of which 304 are
        // whitespace. The first 20,000 therefore hold 4,696 う. Stored sentences are trimmed, so
        // what is stored is 15,000 + 4,696 = 19,696 characters: the notice's 20,000 less the 304.
        // Trimmed first, the paste would store 4,700 う (19,700); blank lines collapsed, more.
        let body = Array(repeating: String(repeating: "あ", count: 99) + "。", count: 150).joined(separator: "\n\n")
        let padded = "  \n\n" + body + "\n\n" + String(repeating: "う", count: 9_999) + "。" + "\n\n  "
        #expect(padded.count == 25_308)
        let paddedNotice = try #require(CustomText.truncation(of: padded))
        #expect(paddedNotice == .characters(kept: 20_000, dropped: 5_308))
        let paddedID = try #require(model.addCustomText(title: "w", source: padded))
        let paddedStored = try #require(model.customTexts.text(id: paddedID))
        #expect(paddedStored.sentences.count == 151)
        #expect(paddedStored.sentences.last?.source == String(repeating: "う", count: 4_696))
        let paddedCharacters = paddedStored.sentences.reduce(0) { $0 + $1.source.count }
        #expect(paddedCharacters == 19_696)
        #expect(.characters(kept: paddedCharacters + 304, dropped: 25_308 - (paddedCharacters + 304)) == paddedNotice,
                "stored \(paddedCharacters) characters plus 304 of whitespace; the notice says \(paddedNotice)")
    }

    // MARK: 3. The sheet

    /// The sheet reads the KIT's count — not a restated `count > 20_000` — into its state when the
    /// text changes, and hands that state unfiltered to the notice view. Not held: what happens to
    /// the state in between — a property observer on `truncation` is outside every range read here.
    @Test("the add sheet reads CustomText.truncation(of: source) on change and hands it to the notice")
    func addSheetUsesTheOneCut() throws {
        let file = try Self.shipped("CustomTextsView.swift")
        let sheet = try #require(file.typeBodies(named: "CustomTextAddView").first)

        let cuts = file.calls(named: "truncation").filter { $0.receiver == "CustomText" }
        #expect(cuts.count == 1, Comment(rawValue: "CustomText.truncation(of:) is read \(cuts.count) times"))
        let cut = try #require(cuts.first)
        #expect(sheet.contains(cut.nameOffset), "the cut is read in the add sheet, not elsewhere")
        #expect(Self.squeezed(cut.arguments, in: file) == "of:source", "the notice must be about the editor's text")

        // Off the body's hot path: the one read is the whole of an `.onChange(of: source)` action,
        // and it lands in the state unaltered.
        let changes = file.calls(named: "onChange").filter { sheet.contains($0.nameOffset) }
        #expect(changes.count == 1, Comment(rawValue: "\(changes.count) onChange in the add sheet"))
        let change = try #require(changes.first)
        #expect(Self.squeezed(change.arguments, in: file) == "of:source")
        #expect(Self.squeezed(change.closures.first, in: file) == "{truncation=CustomText.truncation(of:source)}",
                Comment(rawValue: "the onChange action is \(file.excerpt(change))"))

        // The notice view is built once, in the sheet, from the state — and not inside any
        // condition: its innermost block is the header's VStack, so nothing decides which
        // truncations are shown except the notice view, which the render test below holds.
        let notices = file.calls(named: "CustomTextTruncationNotice")
        #expect(notices.count == 1, Comment(rawValue: "CustomTextTruncationNotice is built \(notices.count) times"))
        let notice = try #require(notices.first)
        #expect(sheet.contains(notice.nameOffset))
        #expect(Self.squeezed(notice.arguments, in: file) == "truncation:truncation,zh:zh",
                Comment(rawValue: "built as \(file.excerpt(notice))"))
        let stacks = file.calls(named: "VStack").filter { sheet.contains($0.nameOffset) }
        let block = file.innermostBlock(containing: notice.nameOffset, within: sheet)
        #expect(block != nil && stacks.contains { $0.closures.first == block },
                "the notice is inside a condition, not directly in the header's VStack")

        // The view renders the one function, with its own truncation and language.
        let body = try #require(file.typeBodies(named: "CustomTextTruncationNotice").first)
        let renders = file.calls(named: "truncationNotice")
        #expect(renders.count == 1, Comment(rawValue: "truncationNotice is rendered \(renders.count) times"))
        let render = try #require(renders.first)
        #expect(body.contains(render.nameOffset))
        #expect(Self.squeezed(render.arguments, in: file) == "truncation,zh:zh")

        // Both languages, twice each (one per unit), and every occurrence inside the one
        // function — a string that moved out of it would still render and no longer be pinned.
        let wording = try #require(file.functions(named: "truncationNotice").first?.body)
        for fragment in ["Only the first", "只保留前"] {
            let hits = Self.literal(fragment, in: file)
            #expect(hits.count == 2, Comment(rawValue: "\(fragment) appears \(hits.count) times"))
            #expect(hits.allSatisfy { wording.contains($0) }, Comment(rawValue:
                "\(fragment) is written somewhere other than truncationNotice"))
        }
    }

    /// The labelled trailing closures that follow `offset` — `header: { … } footer: { … }` after a
    /// `Section`'s content closure, which the scanner does not attach to the call — each from `{`
    /// through `}`, read on the comment- and string-blanked code so a brace in either is not one.
    static func labelledClosures(after offset: Int, in file: CallSiteScanner.File) -> [(label: String, body: Range<Int>)] {
        var out: [(String, Range<Int>)] = []
        var cursor = offset
        while true {
            let start = CallSiteScanner.skipSpace(file.code, cursor)
            guard let (label, afterLabel) = CallSiteScanner.word(in: file.code, at: start),
                  afterLabel < file.code.count, file.code[afterLabel] == UInt8(ascii: ":") else { break }
            let open = CallSiteScanner.skipSpace(file.code, afterLabel + 1)
            guard open < file.code.count, file.code[open] == UInt8(ascii: "{"),
                  let close = CallSiteScanner.matching(file.code, open: open) else { break }
            out.append((label, open..<(close + 1)))
            cursor = close + 1
        }
        return out
    }

    /// Simulator pass, 2026-09-27 (SERIOUS): after a 230-sentence paste the notice was on no
    /// screen. It sat in the editor Section's FOOTER, and the editor grows to fit the paste — 3,495pt
    /// tall, the footer about 3,800pt down the sheet — while Add is in the toolbar. So the notice is
    /// in the editor Section's HEADER now: above the editor, under the section's label, at a place
    /// that depends on the title field above it and not on the paste. Held on the source: the one
    /// `Section` whose content is the `TextEditor` is followed by `header:` then `footer:`; the
    /// header is exactly the label and then the notice (in that order, nothing else), and the
    /// footer is the privacy line alone, 1.33's footer. Mutation, 2026-09-27: the notice moved back
    /// into the footer's VStack → red here. Not held: that the header is on screen on a device —
    /// that is the simulator re-run's to show; this pins the order a Form draws a section in.
    @Test("the notice sits in the editor section's header, under its label, above the editor — not in the footer")
    func noticeIsAboveTheEditor() throws {
        let file = try Self.shipped("CustomTextsView.swift")
        let sheet = try #require(file.typeBodies(named: "CustomTextAddView").first)

        let editors = file.calls(named: "TextEditor").filter { sheet.contains($0.nameOffset) }
        #expect(editors.count == 1, Comment(rawValue: "\(editors.count) editors in the add sheet"))
        let editor = try #require(editors.first)
        let sections = file.calls(named: "Section").filter { section in
            sheet.contains(section.nameOffset) && section.closures.first?.contains(editor.nameOffset) == true
        }
        #expect(sections.count == 1, Comment(rawValue: "\(sections.count) sections hold the editor"))
        let content = try #require(sections.first?.closures.first)

        let labelled = Self.labelledClosures(after: content.upperBound, in: file)
        #expect(labelled.map(\.label) == ["header", "footer"],
                Comment(rawValue: "the editor's section is followed by \(labelled.map(\.label))"))
        let header = try #require(labelled.first { $0.label == "header" }?.body)
        let footer = try #require(labelled.first { $0.label == "footer" }?.body)

        let notice = try #require(file.calls(named: "CustomTextTruncationNotice").first)
        #expect(header.contains(notice.nameOffset), "the notice is not in the editor section's header")
        #expect(!footer.contains(notice.nameOffset) && !content.contains(notice.nameOffset),
                "the notice is below the editor")
        #expect(Self.squeezed(header, in: file, strings: true)
                == #"{VStack(alignment:.leading,spacing:6){Text(zh?"日语原文":"Japanesetext")CustomTextTruncationNotice(truncation:truncation,zh:zh)}}"#,
                Comment(rawValue: "the header is \(String(decoding: file.codeWithStrings[header], as: UTF8.self))"))
        #expect(Self.squeezed(footer, in: file, strings: true)
                == #"{Text(zh?"只留在这台设备上,不会上传。含字母或数字的句子会保留但无法输入——罗马字引擎打不出它们。":"Staysonthisdeviceandisneveruploaded.Sentencescontaininglettersordigitsarekeptbutcannotbetyped—aromajienginehasnokeysforthem.")}"#,
                Comment(rawValue: "the footer is \(String(decoding: file.codeWithStrings[footer], as: UTF8.self))"))
    }

    #if canImport(AppKit)
    /// The notice view draws the line for EVERY non-nil truncation, in both units and both
    /// languages, and nothing for nil. Measured by hosting it: its size must equal the size of the
    /// hand-written line drawn the same way, and a hidden unit measures zero. This holds the view,
    /// not the state plumbing: it builds the notice from a truncation it chose itself, so it cannot
    /// see a sheet whose `@State` never carries that truncation to the view.
    @Test("the notice view draws the line for every non-nil truncation and nothing for nil")
    func theNoticeIsDrawnWheneverThereIsOne() {
        let proposal = CGSize(width: 320, height: 10_000)
        func size<V: View>(_ view: V) -> CGSize {
            NSHostingController(rootView: view).sizeThatFits(in: proposal)
        }
        let cases: [(CustomText.Truncation, Bool, String)] = [
            (.sentences(kept: 200, dropped: 1), false, "Only the first 200 sentences are kept — 1 dropped."),
            (.sentences(kept: 200, dropped: 1), true, "只保留前 200 句,已去掉 1 句。"),
            (.characters(kept: 20_000, dropped: 5_000), false,
             "Only the first 20,000 characters are kept — 5,000 dropped."),
            (.characters(kept: 20_000, dropped: 5_000), true, "只保留前 20,000 个字符,已去掉 5,000 个。"),
        ]
        for (truncation, zh, line) in cases {
            let expected = size(Text(line).foregroundStyle(.orange))
            #expect(expected.height > 0, "the instrument measures nothing")
            let drawn = size(CustomTextTruncationNotice(truncation: truncation, zh: zh))
            #expect(drawn == expected, Comment(rawValue:
                "\(truncation) zh=\(zh): drew \(drawn), the line is \(expected)"))
        }
        let none = size(CustomTextTruncationNotice(truncation: nil, zh: false))
        #expect(none.height == 0, Comment(rawValue: "nil drew \(none)"))
    }
    #endif

    /// A truncated paste is still added, cut as the notice says: Add's one `.disabled` reads the
    /// empty-source check and nothing else, so no truncation can switch it off.
    @Test("Add stays enabled on a truncated paste")
    func addStaysEnabledOnATruncatedPaste() throws {
        let file = try Self.shipped("CustomTextsView.swift")
        let sheet = try #require(file.typeBodies(named: "CustomTextAddView").first)
        let disables = file.calls(named: "disabled").filter { sheet.contains($0.nameOffset) }
        #expect(disables.count == 1, Comment(rawValue: "\(disables.count) .disabled in the add sheet"))
        #expect(Self.squeezed(disables.first?.arguments, in: file)
                == "source.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty",
                Comment(rawValue: "Add is disabled by \(disables.first.map(file.excerpt) ?? "nothing")"))
    }

    /// Add adds what was pasted, whatever the notice says: its action is the one
    /// `model.addCustomText(title: title, source: source)` under no condition but the model's own
    /// answer. A truncated paste refused (`if truncation == nil, …`) would put the silent cut back
    /// as a silent refusal.
    @Test("Add's action calls addCustomText with the editor's text, under no condition on the truncation")
    func addCallsTheModelWithoutACondition() throws {
        let file = try Self.shipped("CustomTextsView.swift")
        let sheet = try #require(file.typeBodies(named: "CustomTextAddView").first)

        let adds = file.calls(named: "Button").filter { button in
            sheet.contains(button.nameOffset)
                && Self.squeezed(button.arguments, in: file, strings: true) == #"zh?"添加":"Add""#
        }
        #expect(adds.count == 1, Comment(rawValue: "\(adds.count) Add buttons in the add sheet"))
        let add = try #require(adds.first)
        #expect(add.closures.count == 1, Comment(rawValue: "Add has \(add.closures.count) closures"))
        let action = try #require(add.closures.first)

        let calls = file.calls(named: "addCustomText")
        #expect(calls.count == 1, Comment(rawValue: "addCustomText is called \(calls.count) times"))
        let call = try #require(calls.first)
        #expect(action.contains(call.nameOffset), "addCustomText is called outside Add's action")
        #expect(call.receiver == "model")
        #expect(Self.squeezed(call.arguments, in: file) == "title:title,source:source")

        #expect(file.mentions(of: "truncation").filter(action.contains).isEmpty,
                "Add's action reads the truncation")
        #expect(Self.squeezed(action, in: file) == "{ifmodel.addCustomText(title:title,source:source)!=nil{dismiss()}else{failed=true}}",
                Comment(rawValue: "Add's action is \(file.excerpt(add))"))
    }

    // MARK: 4. The delete on the Mac

    /// `.onDelete` on a `List` with plain-Button rows and no `selection:` binding is unreachable on
    /// macOS (measured 2026-09-25, recorded beside the modifier). Every row therefore carries a
    /// context menu whose one button is destructive and removes THAT row — and `.onDelete` stays,
    /// because on iOS it is the swipe.
    @Test("every row carries a destructive Delete in its context menu, and onDelete stays")
    func rowsCarryAContextMenuDelete() throws {
        let file = try Self.shipped("CustomTextsView.swift")
        let manager = try #require(file.typeBodies(named: "CustomTextsView").first)

        let lists = file.calls(named: "List").filter { manager.contains($0.nameOffset) }
        #expect(lists.count == 1)
        let list = try #require(lists.first?.closures.first)

        // One ForEach draws every row, so a menu inside its closure is a menu on every row; a
        // second ForEach would be a second population of rows this pin does not cover.
        let loops = file.calls(named: "ForEach").filter { list.contains($0.nameOffset) }
        #expect(loops.count == 1, Comment(rawValue: "\(loops.count) ForEach loops in the list"))
        let rows = try #require(loops.first?.closures.first)

        let menus = file.calls(named: "contextMenu").filter { rows.contains($0.nameOffset) }
        #expect(menus.count == 1, Comment(rawValue: "\(menus.count) context menus on the row"))
        let menu = try #require(menus.first?.closures.first)

        let buttons = file.calls(named: "Button").filter { menu.contains($0.nameOffset) }
        #expect(buttons.count == 1, Comment(rawValue: "\(buttons.count) buttons in the context menu"))
        let button = try #require(buttons.first)
        #expect(Self.squeezed(button.arguments, in: file) == "role:.destructive",
                Comment(rawValue: "the menu's button is \(file.excerpt(button))"))
        let removes = file.calls(named: "removeCustomText").filter { call in
            button.closures.contains { $0.contains(call.nameOffset) }
        }
        #expect(removes.count == 1)
        #expect(Self.squeezed(removes.first?.arguments, in: file) == "id:text.id",
                "the row's OWN id — not the selected one, which on the Mac is nobody's")

        // The label, both languages, the Chinese on the zh side. (`label:` is a second trailing
        // closure, which the scanner does not attach to the Button; the menu holds one button, so
        // the one Label in the menu is its label.)
        let labels = file.calls(named: "Label").filter { menu.contains($0.nameOffset) }
        #expect(labels.count == 1, Comment(rawValue: "\(labels.count) labels on the menu's button"))
        #expect(Self.squeezed(labels.first?.arguments, in: file, strings: true)
                == #"zh?"删除":"Delete",systemImage:"trash""#,
                Comment(rawValue: "the label is \(labels.first.map(file.excerpt) ?? "missing")"))

        let swipes = file.calls(named: "onDelete").filter { list.contains($0.nameOffset) }
        #expect(swipes.count == 1, "the iOS swipe is still there")
        let swipeRemoves = file.calls(named: "removeCustomText").filter { call in
            swipes.first?.closures.contains { $0.contains(call.nameOffset) } == true
        }
        #expect(swipeRemoves.count == 1)
    }
}
