import SwiftUI
import CustomTextKit

/// The learner's own texts: paste one in, check what the app thinks it says, fix what it got
/// wrong, then practise it.
///
/// **The editable reading is the feature, not a fallback.** The reading pipeline is measured at
/// 96.9% of whole sentences on corpus Japanese (`docs/measurements/tokenizer-reading-accuracy.json`)
/// and that number describes short curated JLPT sentences — not news, not lyrics, and above all
/// not names, which nothing in that population tests. The standard for pasted text is different
/// from the standard for the shipped corpus: a wrong reading the app teaches is a taught error,
/// and a wrong reading in text the learner supplied is visible to them and theirs to correct.
/// So every reading is shown and every reading can be changed.
struct CustomTextsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var adding = false
    @State private var openTextID: String?

    private var zh: Bool { model.languageCode == "zh" }

    var body: some View {
        NavigationStack {
            list
                .navigationTitle(zh ? "我的文本" : "My text")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(zh ? "完成" : "Done") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button { adding = true } label: {
                            Label(zh ? "添加" : "Add", systemImage: "plus")
                        }
                        .accessibilityIdentifier("customTextAdd")
                    }
                }
                .sheet(isPresented: $adding) { CustomTextAddView() }
                .sheet(item: Binding(get: { openTextID.map(Identified.init) },
                                     set: { openTextID = $0?.id })) { wrapped in
                    CustomTextDetailView(textID: wrapped.id)
                }
        }
    }

    private struct Identified: Identifiable { let id: String }

    @ViewBuilder
    private var list: some View {
        if model.customTexts.isEmpty {
            ContentUnavailableView {
                Label(zh ? "还没有你自己的文本" : "No text of your own yet",
                      systemImage: "doc.text")
            } description: {
                Text(zh
                     ? "粘贴一段日语 —— 歌词、新闻、课本的一页。app 会读出假名,读错的地方你可以改。"
                     : "Paste some Japanese — lyrics, a news item, a page of your textbook. The app works out the readings, and you can correct the ones it gets wrong.")
            } actions: {
                Button(zh ? "添加文本" : "Add a text") { adding = true }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            List {
                ForEach(model.customTexts.ordered) { text in
                    Button { openTextID = text.id } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(text.title).font(.headline).lineLimit(1)
                            // The RUN's number, not the stored count. An untypeable sentence is
                            // kept and shown but never queued, so the two genuinely differ —
                            // and printing the larger one is v1.22's badge again.
                            Text(sentenceLabel(text))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    // The only delete a Mac user can reach. Measured 2026-09-25 by hosting this
                    // view in an NSHostingView: with no `selection:` binding the List's table has
                    // a `SelectionManagerBox<Never>` coordinator, a click on a row selects
                    // nothing, Delete and Forward Delete do nothing even with a row selected, and
                    // `.onDelete` fires only from the `delete:` responder action with a row
                    // selected programmatically — which no gesture produces. `.onDelete` stays
                    // for iOS, where it is the swipe; this is a second route to the same call,
                    // not a second swipe.
                    .contextMenu {
                        Button(role: .destructive) {
                            model.removeCustomText(id: text.id)
                        } label: {
                            Label(zh ? "删除" : "Delete", systemImage: "trash")
                        }
                    }
                }
                .onDelete { offsets in
                    let ordered = model.customTexts.ordered
                    for index in offsets where ordered.indices.contains(index) {
                        model.removeCustomText(id: ordered[index].id)
                    }
                }
            }
        }
    }

    private func sentenceLabel(_ text: CustomText) -> String {
        let usable = text.typeableSentences.count
        let total = text.sentences.count
        if usable == total {
            return zh ? "\(usable) 句" : "\(usable) sentence\(usable == 1 ? "" : "s")"
        }
        // Said out loud rather than rounded away: the learner pasted something the engine
        // cannot type, and a count that quietly excluded it would be a number about a
        // different text than the one they are looking at.
        return zh
            ? "\(usable) 句可练 · \(total - usable) 句含字母或数字,无法输入"
            : "\(usable) of \(total) typeable · the rest contain letters or digits"
    }
}

/// Pasting a text in.
struct CustomTextAddView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var source = ""
    @State private var failed = false
    /// The kit's own count of what Add will cut, re-read when the text changes and not on every
    /// body evaluation: it splits the paste, which measured (2026-09-27, optimised build, this
    /// Mac) ~5 ms for 20,000 characters and ~50 ms for 200,000 — `PLAN-V1.34` §B2, addendum.
    @State private var truncation: CustomText.Truncation?

    private var zh: Bool { model.languageCode == "zh" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(zh ? "标题(可留空)" : "Title (optional)", text: $title)
                        .accessibilityIdentifier("customTextTitle")
                }
                Section {
                    TextEditor(text: $source)
                        .frame(minHeight: 220)
                        .font(.system(size: 17))
                        .accessibilityIdentifier("customTextSource")
                        .onChange(of: source) { truncation = CustomText.truncation(of: source) }
                } header: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(zh ? "日语原文" : "Japanese text")
                        // Said before Add, not after: the text is still added, cut exactly as
                        // the notice says, and the learner decides whether that is the text
                        // they wanted. Handed the state unfiltered; the notice view draws a line
                        // for every non-nil truncation.
                        //
                        // In the HEADER, above the editor — not the footer, below it (simulator
                        // pass, 2026-09-27). The editor grows to fit what is pasted, so the
                        // footer sits under the whole paste: after a 230-sentence paste the
                        // editor was 3,495pt tall and the notice about 3,800pt down the sheet,
                        // off screen, while Add sat in the toolbar. The notice only exists for a
                        // paste over the cap, which is long by definition, so in the footer it
                        // was off screen whenever it had something to say. The header's place
                        // depends on the title field above it and not on the paste. Under the
                        // label, which keeps its look: with no notice the header is the label
                        // alone, as the footer's text was alone in its VStack before this.
                        CustomTextTruncationNotice(truncation: truncation, zh: zh)
                    }
                } footer: {
                    Text(zh
                         ? "只留在这台设备上,不会上传。含字母或数字的句子会保留但无法输入 —— 罗马字引擎打不出它们。"
                         : "Stays on this device and is never uploaded. Sentences containing letters or digits are kept but cannot be typed — a romaji engine has no keys for them.")
                }
                if failed {
                    Text(zh ? "这段文字里没有可用的句子。" : "There are no sentences in that text.")
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle(zh ? "添加文本" : "Add a text")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(zh ? "取消" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(zh ? "添加" : "Add") {
                        if model.addCustomText(title: title, source: source) != nil { dismiss() }
                        else { failed = true }
                    }
                    .disabled(source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("customTextConfirm")
                }
            }
        }
    }

    /// The one line, in the unit of the cap that bounded what is stored (`CustomText.Truncation`).
    /// In one place, so the test that pins the wording in both languages pins what the sheet shows.
    static func truncationNotice(_ truncation: CustomText.Truncation, zh: Bool) -> String {
        switch truncation {
        case let .sentences(kept, dropped):
            return zh
                ? "只保留前 \(grouped(kept)) 句,已去掉 \(grouped(dropped)) 句。"
                : "Only the first \(grouped(kept)) sentences are kept — \(grouped(dropped)) dropped."
        case let .characters(kept, dropped):
            return zh
                ? "只保留前 \(grouped(kept)) 个字符,已去掉 \(grouped(dropped)) 个。"
                : "Only the first \(grouped(kept)) characters are kept — \(grouped(dropped)) dropped."
        }
    }

    /// "20,000", whatever the device locale groups with — the notice is pinned to one spelling
    /// in both languages, and a learner reading 20000 against a 20,000 cap should see the same
    /// number twice.
    private static func grouped(_ n: Int) -> String {
        n.formatted(.number.locale(Locale(identifier: "en_US")))
    }
}

/// The add sheet's truncation line: one orange line for every non-nil truncation, nothing for nil.
/// Its own view so a test can render it (`V134B2CustomTextTests`) — a condition that hid one unit
/// of the notice would put the silent cut back, and a source pin cannot see what is drawn.
struct CustomTextTruncationNotice: View {
    let truncation: CustomText.Truncation?
    let zh: Bool

    var body: some View {
        if let truncation {
            Text(CustomTextAddView.truncationNotice(truncation, zh: zh))
                .foregroundStyle(.orange)
                .accessibilityIdentifier("customTextTruncation")
        }
    }
}

/// One text: what the app thinks it says, and the readings the learner can change.
struct CustomTextDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let textID: String
    @State private var editingTitle = ""

    private var zh: Bool { model.languageCode == "zh" }
    private var text: CustomText? { model.customTexts.text(id: textID) }

    var body: some View {
        NavigationStack {
            Group {
                if let text {
                    List {
                        Section {
                            TextField(zh ? "标题" : "Title", text: $editingTitle)
                                .onSubmit { model.renameCustomText(id: textID, to: editingTitle) }
                        }
                        ForEach(Array(text.sentences.enumerated()), id: \.element.id) { _, sentence in
                            Section {
                                sentenceRows(sentence)
                            }
                        }
                    }
                    .onAppear { editingTitle = text.title }
                } else {
                    // The text was deleted while this sheet was open. Resolve-then-guard rather
                    // than rendering a screen about nothing.
                    ContentUnavailableView(zh ? "文本已删除" : "This text is gone",
                                           systemImage: "doc.text")
                }
            }
            .navigationTitle(zh ? "检查读音" : "Check the readings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(zh ? "完成" : "Done") {
                        model.renameCustomText(id: textID, to: editingTitle)
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sentenceRows(_ sentence: CustomSentence) -> some View {
        FuriganaText(tokens: sentence.furiganaTokens, size: 20, color: .primary)
            .padding(.vertical, 4)
        Text(sentence.kana)
            .font(.system(size: 14, design: .monospaced))
            .foregroundStyle(.secondary)
        if !sentence.isTypeable {
            Label(zh ? "含字母或数字,无法输入" : "Contains letters or digits — cannot be typed",
                  systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange)
        }
        ForEach(Array(sentence.tokens.enumerated()), id: \.offset) { index, token in
            if token.needsReading {
                ReadingRow(surface: token.surface, reading: token.reading) { newReading in
                    model.setCustomReading(newReading, textID: textID,
                                           sentenceID: sentence.id, tokenIndex: index)
                }
            }
        }
    }
}

/// One kanji token and the reading the learner can change.
///
/// Local `@State` with a commit on submit rather than a binding straight into the store: a
/// half-typed reading is not kana, so writing every keystroke through would be refused on all
/// but the last one and the field would appear to fight the learner.
private struct ReadingRow: View {
    let surface: String
    let reading: String
    let commit: (String) -> Bool

    @State private var draft = ""
    @State private var rejected = false

    var body: some View {
        HStack(spacing: 10) {
            Text(surface).font(.system(size: 18, weight: .medium)).frame(minWidth: 44, alignment: .leading)
            TextField("", text: $draft)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 16))
                .onSubmit { apply() }
                .accessibilityLabel("\(surface) reading")
            if rejected {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                    .accessibilityLabel("not kana")
            }
        }
        .onAppear { draft = reading }
        .onChange(of: reading) { _, new in draft = new }
    }

    private func apply() {
        if commit(draft) { rejected = false }
        else {
            // The refusal is visible AND the field snaps back, so the learner is never left
            // looking at a reading the app did not accept.
            rejected = true
            draft = reading
        }
    }
}
