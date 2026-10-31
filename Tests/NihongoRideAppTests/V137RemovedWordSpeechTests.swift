import Testing
import Foundation
import VocabKit
@testable import NihongoRideApp

/// v1.37 (PLAN-V1.36 §H, recorded for v1.37): **nothing VoiceOver reads on a removed word's row
/// carries the word's internal id** — not the Remove button's label, and not its value, hint or
/// help either.
///
/// The v1.36 review moved the id out of the Remove button's label ("Remove n2-b984 from list",
/// read right after the column said "Removed word") and pinned the label
/// (`V136ListRowsTests.removeLabelNamesNoID`). Its round-2 mutations then showed the rest of the
/// button unpinned: `.accessibilityValue(entry == nil ? id : "")` and `.accessibilityHint(entry ==
/// nil ? "\(id)" : "")` after the label each passed all 1,097 tests, and VoiceOver reads label,
/// value, hint in that order. Measured 2026-10-27, the shipped code sets neither — nothing to fix,
/// so this pins it.
///
/// **What VoiceOver reads on a removed word's row, on both platforms** (`ListDetailView.wordRow`
/// has no platform branch): the column, one element labelled
/// `ListWordRowText.accessibilityLabel(.removed, zh:)` ("Removed word, No longer in the dictionary
/// — you can remove it"); and the Remove button, labelled `ListDetailView.removeLabel(surface: nil,
/// zh:)` ("Remove this word from list" / "从词单移除此词"), with no value, hint or help. Its
/// `accessibilityIdentifier`, `removeWord-<id>`, does carry the id: it is not spoken, and
/// `WordListSearchFlowTests` (an iOS UI test) taps `removeWord-n5-mizu` by it, so it stays.
///
/// **Why a source scan and not the view's own tree.** A hosted `NSHostingView` exposes one AXGroup
/// with no children to an accessibility walk — measured on 2026-10-07 and again on 2026-10-27 (a
/// button with a label, a value and an identifier inside it: none of the three reachable) — so
/// what is spoken is held as values (section 1, with real retired ids from the corpus's own
/// retirement manifests, not from the functions under test) plus the call sites that use them
/// (section 2). The tree itself is the simulator pass's to read.
///
/// Every test here was shown able to fail; the mutations that turned each one red, on
/// 2026-10-27, are named on it.
@MainActor
@Suite("v1.37: a removed word's row speaks no id — label, value, hint or help")
struct V137RemovedWordSpeechTests {

    /// The ids this corpus has retired — the removed words a learner's synced list can actually
    /// hold — read from the manifests that retired them (`check_vocab_diff.py` deletes an entry
    /// only with one).
    static func retiredIDs() throws -> [String] {
        var ids: [String] = []
        for name in ["n3-retirement-manifest.json", "v121-section-c-manifest.json"] {
            let url = CallSiteScanner.repoRoot.appendingPathComponent("docs/measurements/\(name)")
            let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            let entries = try #require(json["entries"] as? [[String: Any]])
            ids += entries.filter { $0["retire"] as? Bool == true }.compactMap { $0["id"] as? String }
        }
        return ids
    }

    /// The shape of a corpus id (`n2-b984`, `n5-mizu`, `n5-k051`), so an id that is not one of the
    /// fixtures is caught too.
    static let idShape = #/n[1-5]-[a-z0-9]+/#

    // MARK: 1. What is spoken, as values

    /// Mutations, 2026-10-27, each red: `removeLabel`'s nil case returning `"Remove n2-b984 from
    /// list"` (also red in `V136ListRowsTests.removeLabelNamesNoID`); `ListWordRowText
    /// .accessibilityLabel`'s `.removed` case appending `" n2-b984"` (also red in
    /// `V136ListRowsTests.oneLabel`); the fixture reader filtering on `retire == false` (no ids: red
    /// on the count, so the loop below cannot pass by having nothing to check).
    @Test("a retired word's column and Remove button read no id, in either language")
    func retiredWordsSpeakNoID() throws {
        let ids = try Self.retiredIDs()
        #expect(Set(ids) == ["n3-b734", "n3-b702", "n2-b984"], "the retirement manifests list \(ids)")
        for id in ids {
            let entry = VocabStore.shared.entry(id: id)
            #expect(entry == nil, "\(id) is in the shipped corpus, so it is not a removed word")
            for zh in [false, true] {
                // Exactly what `wordRow` computes for this id: no entry, so `.removed` and no surface.
                let spoken = [ListWordRowText.accessibilityLabel(.removed, zh: zh),
                              ListDetailView.removeLabel(surface: entry?.surface, zh: zh)]
                for line in spoken {
                    #expect(!line.contains(id), "\(id) is spoken on its own row: \(line)")
                    #expect(line.firstMatch(of: Self.idShape) == nil, "an id is spoken on a removed word's row: \(line)")
                }
                #expect(spoken[1] == (zh ? "从词单移除此词" : "Remove this word from list"))
            }
        }
    }

    /// The same for every word in the dictionary: its Remove button names the word, never its id.
    /// Mutation, 2026-10-27, red: `removeLabel` with a word returning `"Remove \(surface) (n5-x)
    /// from list"` in English — an id-shaped suffix (also red in `removeLabelNamesNoID`).
    @Test("no word's Remove button reads an id")
    func everyWordSpeaksNoID() {
        let entries = VocabStore.shared.entries
        #expect(entries.count > 7_000, "the corpus read \(entries.count) entries")
        var leaks: [String] = []
        for entry in entries {
            for zh in [false, true] {
                let label = ListDetailView.removeLabel(surface: entry.surface, zh: zh)
                if label.contains(entry.id) || label.firstMatch(of: Self.idShape) != nil { leaks.append(label) }
            }
        }
        #expect(leaks.isEmpty, "\(leaks.count) Remove labels read an id, e.g. \(leaks.prefix(3))")
    }

    // MARK: 2. Where it is spoken: the view uses those values and nothing else

    /// Mutations, 2026-10-27, each red here. The first four were green in every other suite
    /// (`V136ListRowsTests`, `V135B6WordSearchTests`, `V133LAccessibilityLayoutTests`):
    /// * m30 `.accessibilityValue(entry == nil ? id : "")` after the Remove button's label;
    /// * m31 `.accessibilityHint(entry == nil ? "\(id)" : "")` after it;
    /// * `.help(id)` after it (macOS speaks help, and shows it as a tooltip);
    /// * `.accessibilityValue(id)` after the row's `.background` (it reaches every element inside);
    /// * the removed case's column built from the id, `} ?? .word(surface: id, reading: nil,
    ///   gloss: "")` (also red in `V136ListRowsTests.columnIsWired`).
    @Test("wordRow's Remove button carries the id only in its identifier; nothing else on the row is spoken")
    func removeButtonIsWired() throws {
        let row = try V135B6WordSearchTests.detail("private func wordRow")
        #expect(!row.isEmpty && row.count < 4000, "the brace walk returned \(row.count) characters of wordRow")

        // The button, whole: its action, its icon, the identifier and the one label — and then the
        // row. Anything chained onto the button (a value, a hint, help) breaks this string.
        #expect(row.contains(#"let remove = Button { model.removeWord(id, from: listID) } label: { Image(systemName: "minus.circle") .scaledSystemFont(16) .foregroundStyle(Theme.accent) .padding(6) .contentShape(Rectangle()) } .buttonStyle(.plain) .accessibilityIdentifier("removeWord-\(id)") .accessibilityLabel(Self.removeLabel(surface: entry?.surface, zh: zh)) return Group {"#),
                "the Remove button's modifiers are not exactly the identifier and removeLabel's label")
        // …and the row after the `Group`: layout and background, nothing an element would inherit.
        #expect(row.hasSuffix("} } .padding(.horizontal, 14).padding(.vertical, 10) .background(Theme.card, in: RoundedRectangle(cornerRadius: 10)) }"),
                "something is chained after wordRow's background: …\(row.suffix(120))")

        // Every spoken attribute, counted over the whole row: one label, and no value, hint, help,
        // input labels or custom content anywhere in it.
        #expect(row.components(separatedBy: "accessibilityLabel(").count - 1 == 1)
        for spoken in ["accessibilityValue", "accessibilityHint", ".help(", "accessibilityInputLabels",
                       "accessibilityCustomContent", "accessibilityRepresentation", "accessibilityChildren"] {
            #expect(!row.contains(spoken), "wordRow sets \(spoken) — VoiceOver reads it on the row")
        }

        // The id itself: in the three places that need it and nowhere else — the lookup, the
        // removal and the identifier the UI test taps. Not `entry?.id`, not a label, not a value.
        let sanctioned = ["model.vocab.entry(id: id)", "model.removeWord(id, from: listID)",
                          #"accessibilityIdentifier("removeWord-\(id)")"#]
        var rest = row
        for use in sanctioned {
            #expect(rest.components(separatedBy: use).count - 1 == 1, "\(use) is not in wordRow exactly once")
            rest = rest.replacingOccurrences(of: use, with: "")
        }
        #expect(rest.firstMatch(of: #/\bid\b/#) == nil,
                "wordRow uses the id somewhere else: …\(rest.firstMatch(of: #/.{0,60}\bid\b.{0,60}/#).map { String($0.output) } ?? "")…")
        #expect(rest.firstMatch(of: #/\blistID\b/#) == nil, "wordRow uses the list's id somewhere else")

        // One level up, the ONE call site: the row is drawn by a bare `wordRow(id: id, listID:
        // list.id)` with nothing chained on it, because a modifier there reaches the whole row as
        // surely as one inside it. Mutation, review r1 (mutation-3): `.accessibilityValue(model
        // .vocab.entry(id: id) == nil ? id : "")` after the call was green in this suite and red
        // only in `V136ListRowsTests.columnIsWired`'s copy of the same string.
        let body = try V135B6WordSearchTests.detail("var body: some View")
        #expect(body.contains(#"ForEach(list.ids, id: \.self) { id in wordRow(id: id, listID: list.id) } } } else { unavailableState }"#),
                "the ForEach that draws a list's words is no longer a bare call to wordRow")
        let detailFile = try V136ListRowsTests.listsSource()
        let detail = try #require(detailFile.typeBodies(named: "ListDetailView").first)
        let detailCode = String(decoding: detailFile.code[detail], as: UTF8.self)
        #expect(detailCode.components(separatedBy: "wordRow(").count - 1 == 2,
                "ListDetailView names wordRow( other than at its declaration and the one ForEach")

        // A removed word is `.removed`, which has nothing to carry an id in.
        #expect(row.contains("} ?? .removed let text = ListWordRowText(content: content, zh: zh, scale: bodyPoints / 17)"))
        #expect(try V136ListRowsTests.columnSource().contains(
                    "enum Content: Equatable { case word(surface: String, reading: String?, gloss: String) case removed }"),
                "ListWordRowText.Content's removed case gained a payload — an id would fit in it")
    }
}
