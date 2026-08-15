import SwiftUI
import VocabKit
import WordListsKit

extension View {
    /// Medium+large sheet detents on iOS; a no-op on macOS (AppKit sheets have no
    /// detent API and present at the content's natural size).
    @ViewBuilder func sheetDetentsMediumLarge() -> some View {
        #if os(iOS)
        presentationDetents([.medium, .large])
        #else
        self
        #endif
    }
}

/// The word-lists screen (`.lists`): all of the user's named lists plus the
/// default "★" favorites list. Follows the non-game-screen contract — software
/// keyboard suppressed (text entry happens in native alerts that present their
/// own field), Esc/Back returns to the menu, zIndex handled by RootView.
struct ListsView: View {
    @Environment(AppModel.self) private var model
    private var zh: Bool { model.languageCode == "zh" }

    @State private var showingCreate = false
    @State private var newListName = ""
    @State private var renameTarget: WordList?
    @State private var renameText = ""
    @State private var deleteTarget: WordList?
    /// List pending "clear words" confirmation. Clearing is MORE destructive than deleting
    /// the list row (the words are gone fleet-wide via tombstones, the empty list remains),
    /// yet it was the one action on this menu with no confirmation.
    @State private var clearTarget: WordList?
    @State private var errorMessage: String?

    var body: some View {
        let content = VStack(alignment: .leading, spacing: 18) {
            header
            ForEach(model.activeLists) { list in
                listRow(list)
            }
            Button {
                newListName = ""
                showingCreate = true
            } label: {
                Label(zh ? "新建词单" : "New list", systemImage: "plus.circle.fill")
                    .scaledSystemFont(15, weight: .semibold)
                    .foregroundStyle(Theme.accent)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("newListButton")
            .accessibilityLabel(zh ? "新建词单" : "Create a new word list")
            // Disabled while the lists file could not be read: the store on screen is an
            // empty stand-in, and creating a list here would either be refused (confusing)
            // or, before v1.16, saved over data that was probably fine. (v1.16 §C.)
            .disabled(model.wordListsReadOnly)
            Spacer(minLength: 12)
        }
        .padding(isPhoneIdiom ? 22 : 40)
        .frame(maxWidth: 620, alignment: .leading)

        return Group {
            if Screenshotter.isCapturing { content } else { ScrollView { content } }
        }
        .frame(maxWidth: .infinity)
        .background {
            if !Screenshotter.isCapturing {
                KeyCaptureView(
                    onKey: { _ in },
                    onCommand: { command in
                        if command == .escape { model.backToMenu() }
                    },
                    suppressSoftwareKeyboard: true)
            }
        }
        // Create — native alert with its own text field (no keyboard-contract clash).
        .alert(zh ? "新建词单" : "New list", isPresented: $showingCreate) {
            TextField(zh ? "名称" : "Name", text: $newListName)
            Button(zh ? "创建" : "Create") { createList() }
            Button(zh ? "取消" : "Cancel", role: .cancel) {}
        }
        // Rename.
        .alert(zh ? "重命名" : "Rename", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } })) {
            TextField(zh ? "名称" : "Name", text: $renameText)
            Button(zh ? "保存" : "Save") { commitRename() }
            Button(zh ? "取消" : "Cancel", role: .cancel) { renameTarget = nil }
        }
        // Delete confirmation.
        .alert(zh ? "删除词单?" : "Delete list?", isPresented: Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } })) {
            Button(zh ? "删除" : "Delete", role: .destructive) {
                if let target = deleteTarget { _ = model.deleteList(target.id) }
                deleteTarget = nil
            }
            Button(zh ? "取消" : "Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text(zh ? "此词单将被删除并在你的设备间同步移除。"
                    : "This list will be deleted and removed across your devices.")
        }
        // Clear-words confirmation. Same shape as delete above; the message says what the
        // delete alert's does not — that the removals propagate and the list itself stays.
        .alert(zh ? "清空词单?" : "Clear this list?", isPresented: Binding(
            get: { clearTarget != nil },
            set: { if !$0 { clearTarget = nil } })) {
            Button(zh ? "清空" : "Clear", role: .destructive) {
                if let target = clearTarget { model.clearList(target.id) }
                clearTarget = nil
            }
            Button(zh ? "取消" : "Cancel", role: .cancel) { clearTarget = nil }
        } message: {
            Text(zh ? "将移除词单中的所有词,并同步到你的其他设备。词单本身会保留。"
                    : "Every word in this list will be removed, across your devices. The list itself stays.")
        }
        // Cap / validation errors.
        .alert(zh ? "无法完成" : "Can't do that",
               isPresented: Binding(get: { errorMessage != nil },
                                    set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Rows

    private func listRow(_ list: WordList) -> some View {
        let name = displayName(list)
        let count = list.ids.count
        let playable = model.playableCount(in: list)
        return HStack(spacing: 12) {
            Image(systemName: list.isDefault ? "star.fill" : "rectangle.stack")
                .foregroundStyle(list.isDefault ? Theme.gold : Theme.accent2)
                .scaledSystemFont(16)
            Button {
                model.selectedListID = list.id
                model.screen = .listDetail
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).scaledSystemFont(16, weight: .semibold)
                        .foregroundStyle(.white)
                    Text(zh ? "\(count) 词" : "\(count) word\(count == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(Theme.dim)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(zh ? "\(name),\(count) 词,打开" : "\(name), \(count) words, open")

            // Play this list (resolve-then-guard lives in startListGame). Disabled
            // when no words resolve on this device — not just when the list is empty.
            Button { model.startListGame(list.id) } label: {
                Image(systemName: "play.fill")
                    .scaledSystemFont(14, weight: .bold)
                    .foregroundStyle(playable > 0 ? .white : Theme.dim)
                    .padding(8)
                    .background(playable > 0 ? Theme.accent : Theme.card, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(playable == 0)
            .accessibilityLabel(zh ? "\(name),开始练习" : "Practice \(name)")

            Menu {
                if !list.isDefault {
                    Button {
                        renameText = list.name
                        renameTarget = list
                    } label: { Label(zh ? "重命名" : "Rename", systemImage: "pencil") }
                    Button(role: .destructive) {
                        deleteTarget = list
                    } label: { Label(zh ? "删除" : "Delete", systemImage: "trash") }
                }
                Button(role: .destructive) {
                    clearTarget = list
                } label: { Label(zh ? "清空" : "Clear words", systemImage: "eraser") }
            } label: {
                Image(systemName: "ellipsis")
                    .scaledSystemFont(16, weight: .bold)
                    .foregroundStyle(Theme.dim)
                    .padding(8)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .disabled(model.wordListsReadOnly)
            .fixedSize()
            .accessibilityLabel(zh ? "\(name),更多操作" : "More actions for \(name)")
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.cardStroke))
    }

    private var header: some View {
        HStack {
            Text(zh ? "我的词单" : "Word Lists")
                .scaledSystemFont(32, weight: .heavy, design: .rounded, relativeTo: .largeTitle)
                .foregroundStyle(.white)
            Spacer()
            Button(action: model.backToMenu) {
                Label(zh ? "返回" : "Back", systemImage: "chevron.left")
                    .scaledSystemFont(14, weight: .semibold)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Theme.card, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.cardStroke))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("listsBackButton")
        }
    }

    // MARK: Actions

    private func displayName(_ list: WordList) -> String {
        list.isDefault ? AppModel.defaultListName(model.languageCode) : list.name
    }

    private func createList() {
        switch model.createList(name: newListName) {
        case .success(let list):
            model.selectedListID = list.id
            model.screen = .listDetail
        case .failure(let error):
            errorMessage = Self.message(for: error, zh: zh)
        }
    }

    private func commitRename() {
        guard let target = renameTarget else { return }
        if let error = model.renameList(target.id, to: renameText) {
            errorMessage = Self.message(for: error, zh: zh)
        }
        renameTarget = nil
    }

    static func message(for error: WordListError, zh: Bool) -> String {
        switch error {
        case .invalidName:
            return zh ? "请输入名称。" : "Please enter a name."
        case .listCapReached(let max):
            return zh ? "词单数量已达上限(\(max))。" : "You've reached the limit of \(max) lists."
        case .wordCapReached(let max):
            return zh ? "该词单已满(\(max) 词)。" : "This list is full (\(max) words)."
        case .listNotFound:
            return zh ? "找不到该词单。" : "List not found."
        case .cannotDeleteDefault:
            return zh ? "默认收藏单无法删除。" : "The default favorites list can't be deleted."
        }
    }
}

/// The detail of one list (`.listDetail`): its words, a "practice" launcher
/// (resolve-then-guard), and per-word removal. Non-game-screen contract.
struct ListDetailView: View {
    @Environment(AppModel.self) private var model
    private var zh: Bool { model.languageCode == "zh" }

    private var list: WordList? {
        model.selectedListID.flatMap { model.list(id: $0) }
    }

    var body: some View {
        let content = VStack(alignment: .leading, spacing: 16) {
            header
            if let list, !list.deleted {
                playButton(list)
                sentenceButton(list)
                dictationButton(list)
                if list.ids.isEmpty {
                    emptyState
                } else {
                    if model.playableCount(in: list) == 0 {
                        unplayableHint
                    }
                    ForEach(list.ids, id: \.self) { id in
                        wordRow(id: id, listID: list.id)
                    }
                }
            } else {
                emptyState
            }
            Spacer(minLength: 12)
        }
        .padding(isPhoneIdiom ? 22 : 40)
        .frame(maxWidth: 620, alignment: .leading)

        return Group {
            if Screenshotter.isCapturing { content } else { ScrollView { content } }
        }
        .frame(maxWidth: .infinity)
        .background {
            if !Screenshotter.isCapturing {
                KeyCaptureView(
                    onKey: { _ in },
                    onCommand: { command in
                        if command == .escape { backToLists() }
                    },
                    suppressSoftwareKeyboard: true)
            }
        }
    }

    /// A fixed 48pt tall button clips its own label once the text outgrows it — the row that
    /// says "Practice this list" becomes a row that says nothing. Scaling the minimum with the
    /// type size keeps the tap target at 48pt at default sizes and lets it grow. (v1.16 §D.)
    @ScaledMetric(relativeTo: .body) private var playButtonHeight: CGFloat = 48

    private func playButton(_ list: WordList) -> some View {
        let playable = model.playableCount(in: list) > 0
        return Button { model.startListGame(list.id) } label: {
            Label(zh ? "开始练习" : "Practice this list", systemImage: "play.fill")
                .scaledSystemFont(16, weight: .bold)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .frame(minHeight: playButtonHeight)
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .background(playable ? Theme.accent : Theme.card, in: Capsule())
        .foregroundStyle(playable ? .white : Theme.dim)
        .disabled(!playable)
        .accessibilityIdentifier("practiceListButton")
    }

    /// Sentence-mode launcher for this list (PLAN-V1.21 §B).
    ///
    /// It states the count instead of just enabling or disabling, because the count is the
    /// surprising part: a list of twenty words is not a run of twenty sentences, and a
    /// learner who is not told that will read a short run as a bug. When it is zero the
    /// button says why rather than sitting greyed out with no explanation, and nothing is
    /// ever padded in from the level pool to hide the shortfall.
    private func sentenceButton(_ list: WordList) -> some View {
        let count = model.sentenceCount(in: list)
        let enabled = count > 0
        return VStack(spacing: 6) {
            Button { model.startSentenceList(list.id) } label: {
                Label(zh ? "例句练习 · 可用 \(count) 句" : "Sentences · \(count) available",
                      systemImage: "text.quote")
                    .scaledSystemFont(16, weight: .bold)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: playButtonHeight)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .background(enabled ? Theme.accent2 : Theme.card, in: Capsule())
            .foregroundStyle(enabled ? .white : Theme.dim)
            .disabled(!enabled)
            .accessibilityIdentifier("sentenceListButton")
            .accessibilityLabel(zh ? "练习例句,这个词单里有 \(count) 句可用"
                                   : "Practise sentences from this list, \(count) available")
            if !enabled && !list.ids.isEmpty {
                Text(zh ? "这个词单里的词还没有可打字的例句。"
                        : "None of this list's words has a typeable example sentence yet.")
                    .font(.caption).foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Dictation launcher for this list (PLAN-V1.22 §A).
    ///
    /// Its count is a THIRD number, below the word count and the sentence count, and it has
    /// to be its own: a sentence the app will happily show you is not necessarily one the
    /// built-in voice reads the way the app writes it, and those are withheld. Shown only
    /// when dictation is available at all — with no Japanese voice the whole mode is
    /// unavailable and a button here would be a second dead end.
    @ViewBuilder
    private func dictationButton(_ list: WordList) -> some View {
        if model.dictationAvailable {
            let count = model.dictationCount(in: list)
            let enabled = count > 0
            VStack(spacing: 6) {
                Button { model.startDictationList(list.id) } label: {
                    Label(zh ? "听写 · 可用 \(count) 句" : "Dictation · \(count) available",
                          systemImage: "ear")
                        .scaledSystemFont(16, weight: .bold)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: playButtonHeight)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .background(enabled ? Theme.gold.opacity(0.9) : Theme.card, in: Capsule())
                .foregroundStyle(enabled ? .black : Theme.dim)
                .disabled(!enabled)
                .accessibilityIdentifier("dictationListButton")
                .accessibilityLabel(zh ? "听写这个词单的例句,有 \(count) 句可用"
                                       : "Dictation from this list, \(count) available")
                if !enabled, model.sentenceCount(in: list) > 0 {
                    // The distinction worth drawing: the list HAS sentences, they just are
                    // not ones the voice can be trusted with.
                    Text(zh ? "这个词单的例句都不适合听写(语音读法与标注不一致)。"
                            : "None of this list's sentences is one the built-in voice reads the way the app writes it.")
                        .font(.caption).foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var unplayableHint: some View {
        Text(zh ? "这些词在本设备上暂不可用(可能来自更新版本的词库)。"
                : "These words aren't available on this device (they may come from a newer vocabulary).")
            .font(.callout).foregroundStyle(Theme.dim)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 4)
    }

    private func wordRow(id: String, listID: String) -> some View {
        let entry = VocabStore.shared.entry(id: id)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                // A word whose entry is gone showed its raw internal id — "n2-b984" where a
                // learner expects 「ペン」. That was only reachable via a list synced from a
                // newer device until v1.22, which withdraws an entry outright, so it is now
                // a thing a learner can actually meet. An id is not a word; say so instead.
                Text(entry?.surface ?? (zh ? "已移除的词" : "Removed word"))
                    .scaledSystemFont(16, weight: .semibold)
                    .foregroundStyle(entry == nil ? Theme.dim : .white)
                if let entry {
                    Text(entry.gloss(for: model.languageCode))
                        .font(.caption).foregroundStyle(Theme.dim).lineLimit(1)
                } else {
                    Text(zh ? "此词已从词库中移除,可以删掉这一行"
                            : "No longer in the dictionary — you can remove it")
                        .font(.caption2).foregroundStyle(Theme.dim.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { model.removeWord(id, from: listID) } label: {
                Image(systemName: "minus.circle")
                    .scaledSystemFont(16)
                    .foregroundStyle(Theme.accent)
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(zh ? "从词单移除 \(entry?.surface ?? id)"
                                   : "Remove \(entry?.surface ?? id) from list")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
    }

    private var emptyState: some View {
        Text(zh ? "这个词单还没有词。在游戏或结算页点 ★ 收藏来添加。"
                : "No words yet. Tap ★ during a ride or on the results screen to add some.")
            .font(.callout).foregroundStyle(Theme.dim)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 8)
    }

    private var header: some View {
        let name = list.map { $0.isDefault ? AppModel.defaultListName(model.languageCode) : $0.name }
            ?? (zh ? "词单" : "List")
        return HStack {
            Text(name)
                .scaledSystemFont(28, weight: .heavy, design: .rounded, relativeTo: .largeTitle)
                .foregroundStyle(.white).lineLimit(1)
            Spacer()
            Button(action: backToLists) {
                Label(zh ? "返回" : "Back", systemImage: "chevron.left")
                    .scaledSystemFont(14, weight: .semibold)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Theme.card, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.cardStroke))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("listDetailBackButton")
        }
    }

    private func backToLists() {
        model.selectedListID = nil
        model.screen = .lists
    }
}

/// A multi-select sheet for adding/removing one word across lists, with an inline
/// "new list" action. Presented from the in-game word card (long-press ★) and the
/// results review chips. Self-contained: reads/writes through `AppModel`.
struct AddToListsSheet: View {
    @Environment(AppModel.self) private var model
    let vocabID: String
    @Binding var isPresented: Bool
    private var zh: Bool { model.languageCode == "zh" }

    @State private var showingCreate = false
    @State private var newListName = ""
    @State private var errorMessage: String?

    var body: some View {
        let membership = Set(model.listIDs(containing: vocabID))
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(zh ? "加入词单" : "Add to lists")
                    .scaledSystemFont(18, weight: .bold).foregroundStyle(.white)
                Spacer()
                Button(zh ? "完成" : "Done") { isPresented = false }
                    .buttonStyle(.plain).foregroundStyle(Theme.accent)
            }
            .padding(.bottom, 14)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(model.activeLists) { list in
                        let inList = membership.contains(list.id)
                        Button { toggle(list.id) } label: {
                            HStack {
                                Image(systemName: inList ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(inList ? Theme.gold : Theme.dim)
                                Text(displayName(list))
                                    .foregroundStyle(.white)
                                Spacer()
                            }
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        // Same string the row shows. It used to pass `list.name`, so on the
                        // default list VoiceOver announced the raw stored name while the
                        // screen read "★ 收藏" — one helper now feeds both so they can't
                        // drift apart again. (v1.14 §C.)
                        .accessibilityLabel(displayName(list))
                        .accessibilityValue(inList ? (zh ? "已加入" : "in list") : (zh ? "未加入" : "not in list"))
                    }
                    Button {
                        newListName = ""
                        showingCreate = true
                    } label: {
                        Label(zh ? "新建词单" : "New list", systemImage: "plus.circle.fill")
                            .foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14).padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: 460)
        .sheetDetentsMediumLarge()
        .alert(zh ? "新建词单" : "New list", isPresented: $showingCreate) {
            TextField(zh ? "名称" : "Name", text: $newListName)
            Button(zh ? "创建并加入" : "Create & add") { createAndAdd() }
            Button(zh ? "取消" : "Cancel", role: .cancel) {}
        }
        .alert(zh ? "无法完成" : "Can't do that",
               isPresented: Binding(get: { errorMessage != nil },
                                    set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    /// The default list stores an internal name and is shown under a localized one
    /// (mirrors `ListsView.displayName`).
    private func displayName(_ list: WordList) -> String {
        list.isDefault ? AppModel.defaultListName(model.languageCode) : list.name
    }

    private func toggle(_ listID: String) {
        if let error = model.toggleWord(vocabID, in: listID) {
            errorMessage = ListsView.message(for: error, zh: zh)
        }
    }

    private func createAndAdd() {
        switch model.createList(name: newListName) {
        case .success(let list):
            if let error = model.addWord(vocabID, to: list.id) {
                errorMessage = ListsView.message(for: error, zh: zh)
            }
        case .failure(let error):
            errorMessage = ListsView.message(for: error, zh: zh)
        }
    }
}
