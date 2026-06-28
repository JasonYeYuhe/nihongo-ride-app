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
                Button {
                    model.clearList(list.id)
                } label: { Label(zh ? "清空" : "Clear words", systemImage: "eraser") }
            } label: {
                Image(systemName: "ellipsis")
                    .scaledSystemFont(16, weight: .bold)
                    .foregroundStyle(Theme.dim)
                    .padding(8)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
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

    private func playButton(_ list: WordList) -> some View {
        let playable = model.playableCount(in: list) > 0
        return Button { model.startListGame(list.id) } label: {
            Label(zh ? "开始练习" : "Practice this list", systemImage: "play.fill")
                .scaledSystemFont(16, weight: .bold)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
        }
        .buttonStyle(.plain)
        .background(playable ? Theme.accent : Theme.card, in: Capsule())
        .foregroundStyle(playable ? .white : Theme.dim)
        .disabled(!playable)
        .accessibilityIdentifier("practiceListButton")
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
                Text(entry?.surface ?? id)
                    .scaledSystemFont(16, weight: .semibold)
                    .foregroundStyle(entry == nil ? Theme.dim : .white)
                if let entry {
                    Text(entry.gloss(for: model.languageCode))
                        .font(.caption).foregroundStyle(Theme.dim).lineLimit(1)
                } else {
                    Text(zh ? "(此词条不可用)" : "(unavailable)")
                        .font(.caption2).foregroundStyle(Theme.dim.opacity(0.7))
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
                                Text(list.isDefault
                                     ? AppModel.defaultListName(model.languageCode) : list.name)
                                    .foregroundStyle(.white)
                                Spacer()
                            }
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(list.name)
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
