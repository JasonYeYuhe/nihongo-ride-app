import Testing
import Foundation
import CustomTextKit
@testable import NihongoRideApp

/// v1.34 §B2 — the two defects in the learner's own texts: the silent cut, and the Mac's missing
/// delete. What can be held here is the wording and the shape of the shipping code; the cut's
/// numbers live in `CustomTextTruncationTests`, beside the cut.
///
/// The source pins read `CustomTextsView.swift` through `CallSiteScanner`, so a modifier named in
/// a comment does not count and a string quoted in a comment does not count. Each pin asserts a
/// count of one before it asserts anything about the one, so a scan that found nothing cannot
/// pass as a scan that found nothing wrong.
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

    // MARK: 1. The notice

    @Test("the notice, both languages, written out by hand")
    func noticeStrings() {
        let both = CustomText.Truncation(keptCharacters: 20_000, droppedCharacters: 1_234,
                                         keptSentences: 200, droppedSentences: 12)
        #expect(CustomTextAddView.truncationNotice(both, zh: false) == [
            "Only the first 20,000 characters are kept — 1,234 dropped.",
            "Only the first 200 sentences are kept — 12 dropped.",
        ])
        #expect(CustomTextAddView.truncationNotice(both, zh: true) == [
            "只保留前 20,000 个字符,已去掉 1,234 个。",
            "只保留前 200 句,已去掉 12 句。",
        ])

        // One cap: one line, and the other cap's line is absent rather than reading "0 dropped".
        let sentencesOnly = CustomText.Truncation(keptCharacters: 1_004, droppedCharacters: 0,
                                                  keptSentences: 200, droppedSentences: 1)
        #expect(CustomTextAddView.truncationNotice(sentencesOnly, zh: false)
                == ["Only the first 200 sentences are kept — 1 dropped."])
        #expect(CustomTextAddView.truncationNotice(sentencesOnly, zh: true)
                == ["只保留前 200 句,已去掉 1 句。"])
        let charactersOnly = CustomText.Truncation(keptCharacters: 20_000, droppedCharacters: 1,
                                                   keptSentences: 200, droppedSentences: 0)
        #expect(CustomTextAddView.truncationNotice(charactersOnly, zh: false)
                == ["Only the first 20,000 characters are kept — 1 dropped."])
        #expect(CustomTextAddView.truncationNotice(charactersOnly, zh: true)
                == ["只保留前 20,000 个字符,已去掉 1 个。"])

        let nothing = CustomText.Truncation(keptCharacters: 20, droppedCharacters: 0,
                                            keptSentences: 2, droppedSentences: 0)
        #expect(CustomTextAddView.truncationNotice(nothing, zh: false).isEmpty)
        #expect(CustomTextAddView.truncationNotice(nothing, zh: true).isEmpty)
    }

    /// The sheet reads the KIT's cut — not a restated `count > 20_000` — and renders the notice
    /// through `truncationNotice`, where both languages' strings live and nowhere else.
    @Test("the add sheet reads CustomText.truncation(of:) and renders both languages from the one place")
    func addSheetUsesTheOneCut() throws {
        let file = try Self.shipped("CustomTextsView.swift")
        let sheet = try #require(file.typeBodies(named: "CustomTextAddView").first)

        let cuts = file.calls(named: "truncation").filter { $0.receiver == "CustomText" }
        #expect(cuts.count == 1, Comment(rawValue: "CustomText.truncation(of:) is read \(cuts.count) times"))
        let cut = try #require(cuts.first)
        #expect(sheet.contains(cut.nameOffset), "the cut is read in the add sheet, not elsewhere")
        #expect(cut.arguments.map { file.text($0).filter { !$0.isWhitespace } } == "of:source",
                "the notice must be about the editor's text")

        let renders = file.calls(named: "truncationNotice")
        #expect(renders.count == 1, Comment(rawValue: "truncationNotice is rendered \(renders.count) times"))
        let render = try #require(renders.first)
        #expect(sheet.contains(render.nameOffset))
        let arguments = render.arguments.map { file.text($0).filter { !$0.isWhitespace } } ?? ""
        #expect(arguments.hasSuffix("zh:zh"), Comment(rawValue: "rendered with \(arguments), not the screen's language"))

        // Both languages, twice each (one line per cap), and every occurrence inside the one
        // function — a string that moved out of it would still render and no longer be pinned.
        let notice = try #require(file.functions(named: "truncationNotice").first?.body)
        for fragment in ["Only the first", "只保留前"] {
            let hits = Self.literal(fragment, in: file)
            #expect(hits.count == 2, Comment(rawValue: "\(fragment) appears \(hits.count) times"))
            #expect(hits.allSatisfy { notice.contains($0) }, Comment(rawValue:
                "\(fragment) is written somewhere other than truncationNotice"))
        }
    }

    // MARK: 2. The delete on the Mac

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
        #expect(button.arguments.map { file.text($0).filter { !$0.isWhitespace } } == "role:.destructive",
                Comment(rawValue: "the menu's button is \(file.excerpt(button))"))
        let removes = file.calls(named: "removeCustomText").filter { call in
            button.closures.contains { $0.contains(call.nameOffset) }
        }
        #expect(removes.count == 1)
        #expect(removes.first?.arguments.map { file.text($0).filter { !$0.isWhitespace } } == "id:text.id",
                "the row's OWN id — not the selected one, which on the Mac is nobody's")

        let swipes = file.calls(named: "onDelete").filter { list.contains($0.nameOffset) }
        #expect(swipes.count == 1, "the iOS swipe is still there")
        let swipeRemoves = file.calls(named: "removeCustomText").filter { call in
            swipes.first?.closures.contains { $0.contains(call.nameOffset) } == true
        }
        #expect(swipeRemoves.count == 1)
    }
}
