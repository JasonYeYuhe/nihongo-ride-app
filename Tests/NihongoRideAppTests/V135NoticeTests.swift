import Testing
import Foundation
import SwiftUI
import CustomTextKit
@testable import NihongoRideApp
#if canImport(AppKit)
// CoreText comes with AppKit, as in `V134B1TomorrowLineTests`.
import AppKit
#endif

/// v1.35 step 2 (`PLAN-V1.34` §F, the v1.35 owner's-decision addendum, 2026-09-29): the add
/// sheet's over-the-cap notice must reach the learner before the cut text is stored — at every
/// Dynamic Type size, keyboard up or down, on every device, and with VoiceOver.
///
/// **What the 1.34 simulator re-run measured** (iPhone 17 Pro, 402 × 874pt, AX5, keyboard up,
/// after a 230-sentence paste): the notice starts at y=406, 338pt wide, about 53pt semibold with
/// a line about 62pt tall, and the keyboard's glass starts at about 539pt — two readable lines.
/// Those two lines were "Only the first / 200" in English and "只保留前 200 / 句,已去掉 30" in
/// Chinese. So three things are held here:
///
/// 1. The wording puts the kept count in line one and the dropped count by the end of line two, at
///    that size, in the 402pt phone's column and in a 375pt phone's (311pt), for every dropped
///    count up to 999,999 — measured with CoreText, with the 1.34 strings as the calibration
///    control: the instrument must reproduce the breaks the simulator captured, or it measures
///    something other than the screen.
/// 2. Add confirms a paste over a cap before storing it: the guarantee for every layout two lines
///    cannot cover (a scrolled Form, a smaller phone, a larger size). This reverses the 1.34 pin
///    that Add called `addCustomText` under no condition on the truncation.
/// 3. VoiceOver is told when the notice appears, changes unit, or goes.
///
/// Source pins read `CustomTextsView.swift` through `CallSiteScanner` with the helpers of
/// `V134B2CustomTextTests` (comments blanked; each pin counts its hits before it reads them).
@MainActor
@Suite("v1.35: the paste notice reaches the learner before the cut text is stored")
struct V135NoticeTests {

    typealias B2 = V134B2CustomTextTests

    static func grouped(_ n: Int) -> String {
        n.formatted(.number.locale(Locale(identifier: "en_US")))
    }

    // MARK: 1. Both counts in the two lines above the keyboard

    #if canImport(AppKit)
    /// The header's size at AX5 on iOS 26, read off the re-run's captures (label frame and line
    /// pitch); semibold, as a grouped Form's section header is drawn.
    static let ax5HeaderPoints: CGFloat = 53
    /// The notice's column on the 402pt phone, captured; and on a 375pt phone, the same Form's
    /// margins taken off (402 − 338 = 64pt of insets, so 375 − 64).
    static let columns: [CGFloat] = [338, 311]

    /// Where CoreText breaks `text`, as each line's range in UTF-16 offsets. The same framesetter
    /// measurement as `V134B1TomorrowLineTests.lineTexts`, with the header's semibold weight and,
    /// for Chinese, an explicit language: the app's own language setting does not change the
    /// device's, so a Chinese notice may be laid out under an English or Japanese system locale,
    /// whose Han fallback font differs (measured: "ja" moved one break, below).
    static func lineRanges(_ text: String, points: CGFloat, width: CGFloat,
                           language: String?) -> [NSRange] {
        let font = NSFont.systemFont(ofSize: points, weight: .semibold) as CTFont
        var attributes: [NSAttributedString.Key: Any] = [.font: font]
        if let language {
            attributes[NSAttributedString.Key(kCTLanguageAttributeName as String)] = language
        }
        let setter = CTFramesetterCreateWithAttributedString(
            NSAttributedString(string: text, attributes: attributes))
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: 100_000), transform: nil)
        let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), path, nil)
        return (CTFrameGetLines(frame) as? [CTLine] ?? []).map { line in
            let range = CTLineGetStringRange(line)
            return NSRange(location: range.location, length: range.length)
        }
    }

    static func lineTexts(_ text: String, points: CGFloat, width: CGFloat, language: String?) -> [String] {
        lineRanges(text, points: points, width: width, language: language)
            .map { (text as NSString).substring(with: $0) }
    }

    /// The line, counted from 1, in which `kept` ends and the line in which `dropped` (its first
    /// occurrence after `kept`) ends, at the AX5 size. Nil when either number is not in the text
    /// at all, so a wording that lost a number cannot pass as one that placed it well.
    static func countLines(_ text: String, kept: Int, dropped: Int, width: CGFloat,
                           language: String?) -> (kept: Int, dropped: Int)? {
        let ns = text as NSString
        let keptRange = ns.range(of: grouped(kept))
        guard keptRange.location != NSNotFound else { return nil }
        let after = NSRange(location: NSMaxRange(keptRange), length: ns.length - NSMaxRange(keptRange))
        let droppedRange = ns.range(of: grouped(dropped), options: [], range: after)
        guard droppedRange.location != NSNotFound else { return nil }
        let lines = lineRanges(text, points: ax5HeaderPoints, width: width, language: language)
        func line(endingAt end: Int) -> Int {
            (lines.firstIndex { end <= NSMaxRange($0) } ?? lines.count) + 1
        }
        return (line(endingAt: NSMaxRange(keptRange)), line(endingAt: NSMaxRange(droppedRange)))
    }

    /// Whether `kept` ends inside line one and `dropped` ends by the end of line two. Both halves
    /// are needed, and the calibration below has a control that fails each one alone.
    static func countsReadable(_ text: String, kept: Int, dropped: Int, width: CGFloat,
                               language: String?) -> Bool? {
        countLines(text, kept: kept, dropped: dropped, width: width, language: language)
            .map { $0.kept == 1 && $0.dropped <= 2 }
    }

    /// The control first: the 1.34 strings, laid out by this instrument at 53pt semibold in 338pt,
    /// break where the simulator's AX5 capture showed them break. If they did not, a pass below
    /// would describe some other layout than the screen's.
    @Test("calibration: the 1.34 notice breaks at 53pt / 338pt where the AX5 capture showed")
    func calibrationReproducesTheCapture() {
        let english = Self.lineTexts("Only the first 200 sentences are kept — 30 dropped.",
                                     points: Self.ax5HeaderPoints, width: 338, language: nil)
        #expect(Array(english.prefix(2)) == ["Only the first ", "200 "],
                Comment(rawValue: "1.34 English broke as \(english)"))
        for language in [nil, "zh-Hans"] as [String?] {
            let chinese = Self.lineTexts("只保留前 200 句,已去掉 30 句。",
                                         points: Self.ax5HeaderPoints, width: 338, language: language)
            #expect(chinese == ["只保留前 200 ", "句,已去掉 30 ", "句。"],
                    Comment(rawValue: "1.34 Chinese (\(language ?? "no language")) broke as \(chinese)"))
        }
        // And the instrument can say no: 1.34's English dropped count, and the owner's first
        // candidate for the character notice, both fall past line two. ("Keeps 20,000," measures
        // 349pt, wider than the column, so 20,000 opens line two and 5,308 line three.)
        #expect(Self.countsReadable("Only the first 200 sentences are kept — 30 dropped.",
                                    kept: 200, dropped: 30, width: 338, language: nil) == false)
        #expect(Self.countsReadable("Keeps 20,000, cuts 5,308 characters.",
                                    kept: 20_000, dropped: 5_308, width: 338, language: nil) == false)
        // Both of those fail BOTH halves — the kept count is off line one and the dropped count
        // past line two — so a check that forgot either half would still say no to them. One
        // control for each half alone, measured (2026-09-29) the same in both columns:
        // "Keeps 200 " / "sentences, " / "cuts 30." — 200 in line one, 30 in line three — the
        // owner's candidate in its sentence form, with the unit after the kept count; and
        // "Only the first " / "200 fit, 30 " / "don't." — both counts in line two.
        let controls: [(text: String, lines: (kept: Int, dropped: Int))] = [
            ("Keeps 200 sentences, cuts 30.", (1, 3)),
            ("Only the first 200 fit, 30 don't.", (2, 2)),
        ]
        for width in Self.columns {
            for control in controls {
                let placed = Self.countLines(control.text, kept: 200, dropped: 30, width: width, language: nil)
                #expect(placed?.kept == control.lines.kept && placed?.dropped == control.lines.dropped,
                        Comment(rawValue: "\(width)pt: \(Self.lineTexts(control.text, points: Self.ax5HeaderPoints, width: width, language: nil))"))
                #expect(Self.countsReadable(control.text, kept: 200, dropped: 30, width: width, language: nil) == false,
                        Comment(rawValue: "the check passed \"\(control.text)\" at \(width)pt"))
            }
        }
    }

    /// Every dropped count the plan names, both units, both languages, both columns — and, for
    /// Chinese, under no language, zh-Hans and ja (the Han fallback font changes with the system
    /// locale; measured 2026-09-29, "ja" at 338pt keeps "字,999,999 字" on line two where the
    /// others break before the last 字 — the counts stay in place either way). Measured margins
    /// at 311pt: "20,000 fit," is 251pt; "保留 20,000" 290pt (zh-Hans) and 288pt (ja); line two's
    /// "字,999,999" 279pt.
    @Test("at AX5, the kept count is in line one and the dropped count by line two, 338pt and 311pt")
    func bothCountsInTheFirstTwoLines() {
        let dropped = [1, 30, 999, 1_000, 99_999, 999_999]
        let units: [(Int, (Int) -> CustomText.Truncation)] = [
            (200, { .sentences(kept: 200, dropped: $0) }),
            (20_000, { .characters(kept: 20_000, dropped: $0) }),
        ]
        var measured = 0
        for width in Self.columns {
            for (kept, make) in units {
                for count in dropped {
                    for (zh, languages) in [(false, [nil]), (true, [nil, "zh-Hans", "ja"])] as [(Bool, [String?])] {
                        let text = CustomTextAddView.truncationNotice(make(count), zh: zh)
                        for language in languages {
                            let readable = Self.countsReadable(text, kept: kept, dropped: count,
                                                               width: width, language: language)
                            measured += 1
                            #expect(readable == true, Comment(rawValue:
                                "\(width)pt \(language ?? "-"): \(Self.lineTexts(text, points: Self.ax5HeaderPoints, width: width, language: language))"))
                        }
                    }
                }
            }
        }
        #expect(measured == 2 * 2 * 6 * 4, "the matrix ran \(measured) layouts")
    }
    #endif

    // MARK: 2. Add confirms a cut paste before storing it

    /// Hand-written, both units, both languages, with the singular.
    @Test("the confirmation's title has no numbers; its message has both counts and the remedy")
    func confirmationStrings() {
        #expect(CustomTextAddView.confirmationTitle(zh: false) == "Add part of this text?")
        #expect(CustomTextAddView.confirmationTitle(zh: true) == "只添加一部分?")
        for zh in [false, true] {
            #expect(!CustomTextAddView.confirmationTitle(zh: zh).contains { ("0"..."9").contains($0) })
        }

        let sentences = CustomText.Truncation.sentences(kept: 200, dropped: 30)
        #expect(CustomTextAddView.confirmationMessage(sentences, zh: false)
                == "Add keeps the first 200 sentences and leaves out the last 30. You can add the rest as further texts.")
        #expect(CustomTextAddView.confirmationMessage(sentences, zh: true)
                == "添加后只保留前 200 句,最后 30 句不会保存。其余部分可以另外添加。")
        let characters = CustomText.Truncation.characters(kept: 20_000, dropped: 5_308)
        #expect(CustomTextAddView.confirmationMessage(characters, zh: false)
                == "Add keeps the first 20,000 characters and leaves out the last 5,308. You can add the rest as further texts.")
        #expect(CustomTextAddView.confirmationMessage(characters, zh: true)
                == "添加后只保留前 20,000 个字符,最后 5,308 个不会保存。其余部分可以另外添加。")
        // The singular, in both units. One character always fits one more text; one sentence need
        // not (it can run past 20,000 characters), so it is added "separately", not "as another text".
        let one = CustomText.Truncation.sentences(kept: 200, dropped: 1)
        #expect(CustomTextAddView.confirmationMessage(one, zh: false)
                == "Add keeps the first 200 sentences and leaves out the last one. You can add it separately.")
        #expect(CustomTextAddView.confirmationMessage(one, zh: true)
                == "添加后只保留前 200 句,最后 1 句不会保存。其余部分可以另外添加。")
        let oneCharacter = CustomText.Truncation.characters(kept: 20_000, dropped: 1)
        #expect(CustomTextAddView.confirmationMessage(oneCharacter, zh: false)
                == "Add keeps the first 20,000 characters and leaves out the last one. You can add it as another text.")
        #expect(CustomTextAddView.confirmationMessage(oneCharacter, zh: true)
                == "添加后只保留前 20,000 个字符,最后 1 个不会保存。其余部分可以另外添加。")

        // More left out than one text holds (200 sentences, 20,000 characters): the first draft
        // said "You can add those as another text." here, which was false — 250 sentences are at
        // least two more texts and 979,999 characters at least 49. Nothing in the message may say "another".
        let beyondOneText: [CustomText.Truncation] = [
            .sentences(kept: 200, dropped: 250), .characters(kept: 20_000, dropped: 979_999),
        ]
        for cut in beyondOneText {
            let english = CustomTextAddView.confirmationMessage(cut, zh: false)
            #expect(!english.contains("another") && english.hasSuffix("You can add the rest as further texts."),
                    Comment(rawValue: english))
            let chinese = CustomTextAddView.confirmationMessage(cut, zh: true)
            #expect(!chinese.contains("一篇") && chinese.hasSuffix("其余部分可以另外添加。"),
                    Comment(rawValue: chinese))
        }
    }

    /// **Replaces 1.34's "Add's action calls addCustomText with the editor's text, under no
    /// condition on the truncation".** 1.34 let the notice be the whole warning and accepted its
    /// AX5 cost; the 1.35 decision, after the simulator re-run, is that the learner confirms a cut
    /// before it is stored. Held on the source, because no test here runs the sheet:
    ///
    /// * the paste is stored in ONE place, `commit()`, which is 1.34's action verbatim;
    /// * Add's action counts the cut FRESH from the editor's text: nil → `commit()`, as 1.34 did;
    ///   non-nil → the confirmation, and nothing is stored;
    /// * the confirmation is one `.alert` whose Add calls `commit()` and whose Cancel is
    ///   `role: .cancel` with an empty action — it stores nothing and changes no state, so the
    ///   sheet, the text and the notice stay as they were;
    /// * `commit()` is called from exactly those two places.
    @Test("under the cap Add stores directly; over it an alert asks, only its Add stores, Cancel stores nothing")
    func addConfirmsACutPaste() throws {
        let file = try B2.shipped("CustomTextsView.swift")
        let sheet = try #require(file.typeBodies(named: "CustomTextAddView").first)

        // One place stores.
        let stores = file.calls(named: "addCustomText")
        #expect(stores.count == 1, Comment(rawValue: "addCustomText is called \(stores.count) times"))
        let store = try #require(stores.first)
        #expect(store.receiver == "model")
        #expect(B2.squeezed(store.arguments, in: file) == "title:title,source:source")
        let commits = file.functions(named: "commit").filter { sheet.contains($0.keywordOffset) }
        #expect(commits.count == 1, Comment(rawValue: "\(commits.count) commit() functions in the sheet"))
        let commit = try #require(commits.first?.body)
        #expect(commit.contains(store.nameOffset), "addCustomText is called outside commit()")
        #expect(B2.squeezed(commit, in: file) == "{ifmodel.addCustomText(title:title,source:source)!=nil{dismiss()}else{failed=true}}")

        // Two Add buttons in the sheet: the toolbar's and the alert's.
        let adds = file.calls(named: "Button").filter { button in
            sheet.contains(button.nameOffset)
                && B2.squeezed(button.arguments, in: file, strings: true) == #"zh?"添加":"Add""#
        }
        #expect(adds.count == 2, Comment(rawValue: "\(adds.count) Add buttons in the add sheet"))
        let toolbarItems = file.calls(named: "ToolbarItem").filter { sheet.contains($0.nameOffset) }
        let inToolbar = adds.filter { add in
            toolbarItems.contains { $0.closures.first?.contains(add.nameOffset) == true }
        }
        #expect(inToolbar.count == 1, Comment(rawValue: "\(inToolbar.count) Add buttons in the toolbar"))
        let toolbarAdd = try #require(inToolbar.first)
        #expect(toolbarAdd.closures.count == 1)
        #expect(B2.squeezed(toolbarAdd.closures.first, in: file)
                == "{ifletcut=CustomText.truncation(of:source){confirming=cut}else{commit()}}",
                Comment(rawValue: "Add's action is \(file.excerpt(toolbarAdd))"))

        // The alert: presented while `confirming` is set, cleared when it goes.
        let alerts = file.calls(named: "alert").filter { sheet.contains($0.nameOffset) }
        #expect(alerts.count == 1, Comment(rawValue: "\(alerts.count) alerts in the add sheet"))
        let alert = try #require(alerts.first)
        #expect(B2.squeezed(alert.arguments, in: file)
                == "Self.confirmationTitle(zh:zh),isPresented:Binding(get:{confirming!=nil},set:{if!$0{confirming=nil}})",
                Comment(rawValue: "the alert is \(file.excerpt(alert))"))
        // The actions closure is the trailing one; the Binding's get/set literals are closures
        // handed to the call too, inside its parentheses.
        let arguments = try #require(alert.arguments)
        let trailing = alert.closures.filter { $0.lowerBound > arguments.upperBound }
        #expect(trailing.count == 1, Comment(rawValue: "the alert has \(trailing.count) trailing closures"))
        let actions = try #require(trailing.first)
        let alertAdd = try #require(adds.first { actions.contains($0.nameOffset) }, "the alert has no Add")
        #expect(B2.squeezed(alertAdd.closures.first, in: file) == "{commit()}")
        let alertButtons = file.calls(named: "Button").filter { actions.contains($0.nameOffset) }
        #expect(alertButtons.count == 2, Comment(rawValue: "\(alertButtons.count) buttons in the alert"))
        let cancel = try #require(alertButtons.first { $0.nameOffset != alertAdd.nameOffset })
        #expect(B2.squeezed(cancel.arguments, in: file, strings: true) == #"zh?"取消":"Cancel",role:.cancel"#)
        #expect(B2.squeezed(cancel.closures.first, in: file) == "{}", "Cancel does something")
        let message = B2.labelledClosures(after: actions.upperBound, in: file)
        #expect(message.map(\.label) == ["message"])
        #expect(B2.squeezed(message.first?.body, in: file)
                == "{ifletconfirming{Text(Self.confirmationMessage(confirming,zh:zh))}}")

        // commit() from exactly the toolbar's else and the alert's Add.
        let calls = file.calls(named: "commit").filter { sheet.contains($0.nameOffset) }
        #expect(calls.count == 2, Comment(rawValue: "commit() is called \(calls.count) times"))
        #expect(calls.allSatisfy { call in
            toolbarAdd.closures.first?.contains(call.nameOffset) == true
                || alertAdd.closures.first?.contains(call.nameOffset) == true
        }, "commit() is called from somewhere other than the two Adds")
    }

    // MARK: 3. VoiceOver

    /// Hand-written table. The rule: a notice that appears, or changes unit, is read in full; one
    /// that goes is answered; a count moving within its unit is not re-read (it moves at every
    /// keystroke while the rider types into a long paste).
    @Test("announcement: appear or change unit → the notice; gone → the whole text fits; same unit → nothing")
    func announcementTable() {
        let s30 = CustomText.Truncation.sentences(kept: 200, dropped: 30)
        let s31 = CustomText.Truncation.sentences(kept: 200, dropped: 31)
        let c1 = CustomText.Truncation.characters(kept: 20_000, dropped: 1)
        let c4902 = CustomText.Truncation.characters(kept: 20_000, dropped: 4_902)
        let rows: [(CustomText.Truncation?, CustomText.Truncation?, String?, String?)] = [
            (nil, nil, nil, nil),
            (nil, s30, "200 fit, 30 don't — the limit is 200 sentences.", "保留 200 句,30 句放不下。"),
            (nil, c1, "20,000 fit, 1 doesn't — the limit is 20,000 characters.", "保留 20,000 字,1 字放不下。"),
            (s30, s31, nil, nil),
            (s31, s30, nil, nil),
            (c1, c4902, nil, nil),
            (s30, c4902, "20,000 fit, 4,902 don't — the limit is 20,000 characters.", "保留 20,000 字,4,902 字放不下。"),
            (c4902, s31, "200 fit, 31 don't — the limit is 200 sentences.", "保留 200 句,31 句放不下。"),
            (s30, nil, "The whole text fits now.", "现在整段文字都能保留。"),
            (c1, nil, "The whole text fits now.", "现在整段文字都能保留。"),
        ]
        for (old, new, english, chinese) in rows {
            #expect(CustomTextAddView.announcement(from: old, to: new, zh: false) == english,
                    Comment(rawValue: "\(String(describing: old)) → \(String(describing: new))"))
            #expect(CustomTextAddView.announcement(from: old, to: new, zh: true) == chinese,
                    Comment(rawValue: "\(String(describing: old)) → \(String(describing: new)) zh"))
        }
    }

    /// The announcement is posted from the sheet's `.onChange(of: truncation)` with the function
    /// above and nothing else deciding. (`V134B2CustomTextTests.addSheetUsesTheOneCut` counts the
    /// sheet's two `.onChange`s.)
    @Test("the sheet posts announcement(from:to:) from onChange(of: truncation)")
    func announcementIsPosted() throws {
        let file = try B2.shipped("CustomTextsView.swift")
        let sheet = try #require(file.typeBodies(named: "CustomTextAddView").first)
        let changes = file.calls(named: "onChange").filter {
            sheet.contains($0.nameOffset) && B2.squeezed($0.arguments, in: file) == "of:truncation"
        }
        #expect(changes.count == 1, Comment(rawValue: "\(changes.count) onChange(of: truncation)"))
        let change = try #require(changes.first)
        #expect(B2.squeezed(change.closures.first, in: file)
                == "{old,newiniflet line=Self.announcement(from:old,to:new,zh:zh){AccessibilityNotification.Announcement(line).post()}}"
                    .filter { !$0.isWhitespace },
                Comment(rawValue: "the action is \(file.excerpt(change))"))
        let posts = file.mentions(of: "AccessibilityNotification")
        #expect(posts.count == 1, Comment(rawValue: "AccessibilityNotification is named \(posts.count) times"))
        #expect(posts.allSatisfy { change.closures.first?.contains($0) == true },
                "an announcement is posted from somewhere other than onChange(of: truncation)")
    }
}
