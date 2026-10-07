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
    @Environment(\.dynamicTypeSize) private var typeSize
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

    /// One list.
    ///
    /// ⚠️ **At the accessibility text sizes this row becomes two lines**, for the reason
    /// `JournalView.rideRow` gives: a horizontal arrangement that cannot fit stops being one.
    /// Measured with CoreText on 2026-09-17 for a 393pt phone at AX5 (v1.33 scan finding #16):
    /// the icon, play button, menu and gaps take 230 of the card's 321pt, leaving the NAME a
    /// 91pt column — "Saved" alone needs 141 — so the default list rendered as "★ / Save / d"
    /// over "2 / words" on a 402pt iPhone 17 Pro (simulator pass #14). The default list always
    /// exists, so every AX5 learner met it.
    ///
    /// Stacked, the identity keeps line 1 (icon, name, count) and the name gets 244pt of it;
    /// the two controls move to line 2. Below the accessibility sizes the row is exactly what
    /// it was (at XXXL the inline name column is 182pt against 113 for "Vocabulary").
    ///
    /// The residue, measured rather than hoped away: a single unbroken word wider than 244pt
    /// at AX5 — "Vocabulary" is 255 — still breaks before its last letter. Names with spaces
    /// wrap at the spaces. (v1.33 §B L.)
    ///
    /// The name is `rowName`'s: the default list's without its "★ ", which `listIcon` draws.
    @ViewBuilder
    private func listRow(_ list: WordList) -> some View {
        let name = Self.rowName(displayName(list), isDefault: list.isDefault)
        let count = list.ids.count
        let playable = model.playableCount(in: list)
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        listIcon(list)
                        openListButton(list, name: name, count: count)
                    }
                    HStack(spacing: 12) {
                        playListButton(list, name: name, playable: playable)
                        listActionsMenu(list, name: name)
                        Spacer(minLength: 0)
                    }
                }
            } else {
                HStack(spacing: 12) {
                    listIcon(list)
                    openListButton(list, name: name, count: count)
                    playListButton(list, name: name, playable: playable)
                    listActionsMenu(list, name: name)
                }
            }
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.cardStroke))
    }

    private func listIcon(_ list: WordList) -> some View {
        Image(systemName: list.isDefault ? "star.fill" : "rectangle.stack")
            .foregroundStyle(list.isDefault ? Theme.gold : Theme.accent2)
            .scaledSystemFont(16)
    }

    private func openListButton(_ list: WordList, name: String, count: Int) -> some View {
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
    }

    /// Play this list (resolve-then-guard lives in startListGame). Disabled
    /// when no words resolve on this device — not just when the list is empty.
    private func playListButton(_ list: WordList, name: String, playable: Int) -> some View {
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
    }

    private func listActionsMenu(_ list: WordList, name: String) -> some View {
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

    /// The name a list's row on this screen shows, and the name its three controls are read out
    /// with: the default list's without its leading "★ ", because the row's own `listIcon` already
    /// draws that star, in gold. "★ Saved" beside it showed two (PLAN-V1.33 §C, "the saved list's
    /// double star"; v1.36 §C item 2).
    ///
    /// Display only, and only here. The stored name (`AppModel.defaultListName`), the detail
    /// screen's header and the add-to-lists sheet draw no star icon, and keep "★ Saved" / "★ 收藏".
    /// A list the learner named is shown as typed, a ★ of their own included.
    static func rowName(_ name: String, isDefault: Bool) -> String {
        guard isDefault, name.hasPrefix("★ ") else { return name }
        return String(name.dropFirst(2))
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
/// (resolve-then-guard), per-word removal, and — since v1.35 §B6 — a search over the whole
/// corpus that adds a word to THIS list. Non-game-screen contract.
///
/// **The search field is the one inline text field on a screen that otherwise follows the
/// keyboard contract** (`ListsView`'s header: text entry happens in alerts that bring their own
/// field). It follows the rename alert's shape rather than sitting on the screen permanently:
/// a button opens it with the field focused, and a cancel-role Done — Esc on a hardware keyboard,
/// on both platforms, through `.keyboardShortcut(.cancelAction)` as the alert's Cancel is —
/// closes it. While it is open the screen's `KeyCaptureView` is REMOVED, not merely idle: on iOS
/// that view re-takes first responder for five seconds after it appears and again whenever the
/// app becomes active (`KeyCaptureUIView.startRetryLoop`), and on macOS it claims focus when it
/// joins the window. Left in place it would take the focus back from the field under the
/// learner's fingers, with a software keyboard it suppresses. Removing it before the field exists
/// means there is no moment when both want focus. When search closes, the view returns and Esc
/// goes back to the lists as before.
struct ListDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    private var zh: Bool { model.languageCode == "zh" }

    private var list: WordList? {
        model.selectedListID.flatMap { model.list(id: $0) }
    }

    /// Search is open: the field and its results replace the three launchers.
    @State private var searching = false
    @State private var query = ""
    @State private var results: [VocabEntry] = []
    @FocusState private var searchFocused: Bool
    @State private var errorMessage: String?
    /// What VoiceOver has been told about the results, and the pending wait before the next line.
    @State private var announcer = SearchAnnouncer()
    @State private var announceTask: Task<Void, Never>?

    /// Search is open AND on screen. The panel is drawn only for a live list, so a list deleted
    /// on another device while search is open takes the panel away — and with it the field that
    /// Esc would close. Keyed on this rather than on `searching`, the key-capture view comes back
    /// in that case too, so Esc still leaves the screen instead of going nowhere.
    private var searchIsShowing: Bool {
        searching && (list.map { !$0.deleted } ?? false)
    }

    /// How many results a query shows. A keystroke-sized query ("a") matches thousands; the list
    /// says it is showing the first ones and asks for more letters rather than rendering them all.
    static let searchLimit = 50

    /// The body text size at the learner's Dynamic Type setting, as a multiplier for the result
    /// row (`WordSearchResultRow.scale`). Passed down rather than read inside the row so the row
    /// can be laid out at the accessibility sizes by a test: a hosted view on macOS ignores
    /// `dynamicTypeSize`, measured 2026-09-29 (`scaledSystemFont(17)` and `.body` laid out
    /// byte-identically at `.large`, AX1 and AX5).
    @ScaledMetric(relativeTo: .body) private var bodyPoints: CGFloat = 17

    var body: some View {
        let content = VStack(alignment: .leading, spacing: 16) {
            header
            if let list, !list.deleted {
                if searching {
                    searchPanel(list)
                } else {
                    playButton(list)
                    sentenceButton(list)
                    dictationButton(list)
                    searchOpenButton
                }
                if list.ids.isEmpty {
                    if !searching { emptyState }
                } else {
                    if searching { inThisListCaption(count: list.ids.count) }
                    if model.playableCount(in: list) == 0 {
                        unplayableHint
                    }
                    ForEach(list.ids, id: \.self) { id in
                        wordRow(id: id, listID: list.id)
                    }
                }
            } else {
                unavailableState
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
            // Absent while search is open — see the type's comment for why absent and not idle.
            if !Screenshotter.isCapturing && !searchIsShowing {
                KeyCaptureView(
                    onKey: { _ in },
                    onCommand: { command in
                        if command == .escape { backToLists() }
                    },
                    suppressSoftwareKeyboard: true)
            }
        }
        .onChange(of: query) { _, new in
            results = model.vocab.search(new, limit: Self.searchLimit)
            // WCAG 4.1.3: the result list appearing or emptying is a status a VoiceOver user
            // cannot see. Said once the outcome has held for `SearchAnnouncer.settleDelay`, and
            // only when its kind differs from the last one said — not at every keystroke, which
            // would interrupt the typing it reports on (`SearchAnnouncer`).
            announcer.changed(to: Self.searchOutcome(query: new, count: results.count), at: .now)
            announceTask?.cancel()
            announceTask = Task { @MainActor in
                try? await Task.sleep(for: SearchAnnouncer.settleDelay)
                // A cancelled sleep returns at once; a cancelled task says nothing.
                guard !Task.isCancelled else { return }
                if let line = announcer.due(at: .now, limit: Self.searchLimit, zh: zh) {
                    AccessibilityNotification.Announcement(line).post()
                }
            }
        }
        // Leaving the screen by any route — Back, Esc, the model moving the screen — drops a line
        // still waiting to be said about a list the learner has left (round 3).
        .onDisappear { resetAnnouncer() }
        // Cap / validation errors from an add — the same alert ListsView shows.
        .alert(zh ? "无法完成" : "Can't do that",
               isPresented: Binding(get: { errorMessage != nil },
                                    set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Search (v1.35 §B6)

    /// Opens search. Disabled while the lists file could not be read, like New list: an add
    /// would be refused (`AppModel.refusesListMutation`), so offering it would be a dead end.
    private var searchOpenButton: some View {
        Button(action: openSearch) {
            Label(zh ? "搜索词库" : "Search the dictionary", systemImage: "magnifyingglass")
                .scaledSystemFont(15, weight: .semibold)
                .foregroundStyle(Theme.accent2)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .disabled(model.wordListsReadOnly)
        .accessibilityIdentifier("wordSearchOpen")
        .accessibilityLabel(zh ? "搜索词库,把词加入这个词单" : "Search the dictionary to add words to this list")
    }

    private func searchPanel(_ list: WordList) -> some View {
        let members = Set(list.ids)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let full = list.ids.count >= WordListStore.maxWordsPerList
        return VStack(alignment: .leading, spacing: 10) {
            // At the accessibility sizes Done goes under the field, as the list header's Back
            // goes above its title: beside it, Done at AX5 leaves the field too little room to
            // show what is being typed.
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    searchField
                    searchCloseButton
                }
            } else {
                HStack(spacing: 12) {
                    searchField
                    searchCloseButton
                }
            }
            if full {
                Text(Self.fullNotice(zh: zh))
                    .font(.callout).foregroundStyle(Theme.gold)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("wordSearchListFull")
            }
            if trimmed.isEmpty {
                Text(zh ? "可以输入假名、罗马字(如 mizu)、汉字,或英文、中文词义。"
                        : "Type kana, romaji (like mizu), kanji, or a meaning in English or Chinese.")
                    .font(.callout).foregroundStyle(Self.dimTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            } else if results.isEmpty {
                Text(Self.noResults(trimmed, zh: zh))
                    .font(.callout).foregroundStyle(Self.dimTextColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("wordSearchNoResults")
            } else {
                ForEach(results) { entry in
                    let inList = members.contains(entry.id)
                    WordSearchResultRow(
                        surface: entry.surface,
                        reading: Self.reading(for: entry),
                        gloss: entry.gloss(for: model.languageCode),
                        state: WordSearchResultRow.state(inList: inList, wordCount: list.ids.count,
                                                         cap: WordListStore.maxWordsPerList),
                        zh: zh,
                        stacked: typeSize.isAccessibilitySize,
                        scale: bodyPoints / 17,
                        add: { add(entry.id, to: list.id) })
                    .accessibilityIdentifier("wordSearchResult-\(entry.id)")
                }
                if results.count == Self.searchLimit {
                    Text(zh ? "只显示前 \(Self.searchLimit) 个结果,多输入几个字可以缩小范围。"
                            : "Showing the first \(Self.searchLimit). Type more to narrow it down.")
                        .font(.caption).foregroundStyle(Self.dimTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        #if os(macOS)
        // Behind the cancel shortcut: AppKit's field editor answers Esc with `cancelOperation`,
        // which reaches this whether or not the shortcut claimed the key first. Closing twice is
        // harmless — `closeSearch` only resets state.
        .onExitCommand(perform: closeSearch)
        #endif
    }

    private var searchField: some View {
        TextField(zh ? "假名、罗马字、汉字或词义" : "Kana, romaji, kanji or a meaning", text: $query)
            .textFieldStyle(.roundedBorder)
            .scaledSystemFont(16)
            .focused($searchFocused)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .submitLabel(.search)
            #endif
            .accessibilityIdentifier("wordSearchField")
            .accessibilityLabel(zh ? "搜索词库" : "Search the dictionary")
            // Focused once it exists — the rename alert's field is focused when it appears.
            // Deferred one turn, because a focus set in the same update that inserts the field
            // can be dropped.
            .onAppear { DispatchQueue.main.async { searchFocused = true } }
    }

    /// Cancel role and the cancel shortcut: Esc closes search on a Mac and on an iPad or iPhone
    /// with a hardware keyboard, while the field has focus — the rename alert's Cancel, which is
    /// how that field is left.
    private var searchCloseButton: some View {
        Button(role: .cancel, action: closeSearch) {
            Text(zh ? "完成" : "Done")
                .scaledSystemFont(15, weight: .semibold)
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(Theme.accent)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
        .accessibilityIdentifier("wordSearchClose")
        .accessibilityLabel(zh ? "完成搜索" : "Done searching")
    }

    private func openSearch() {
        query = ""
        results = []
        resetAnnouncer()
        searching = true
        // The index is built on the first search (`VocabStore.search`): ~47 ms on this Mac in a
        // release build (re-measured 2026-09-30, median of 15; 31 ms at the first commit, before
        // the corpus merge and the ん readings), against ~0.7 ms for a keystroke once built. Built
        // here, off the main actor, it is ready before the first keystroke instead of costing that
        // keystroke a frame or two. Read-only — the store is a Sendable value and the lazy index is
        // locked.
        let vocab = model.vocab
        Task.detached(priority: .userInitiated) { _ = vocab.wordSearchIndex }
    }

    private func closeSearch() {
        searchFocused = false
        query = ""
        results = []
        searching = false
        resetAnnouncer()
    }

    private func resetAnnouncer() {
        announceTask?.cancel()
        announceTask = nil
        announcer = SearchAnnouncer()
    }

    /// Through `AppModel.addWord` — the path the ★ and the add-to-lists sheet take — so the save,
    /// the read-only refusal and the sync enqueue are the ones every other add gets.
    private func add(_ vocabID: String, to listID: String) {
        if let error = model.addWord(vocabID, to: listID) {
            errorMessage = ListsView.message(for: error, zh: zh)
        }
    }

    /// The reading a word's row shows under it: the word's kana, or nil when the word is written in
    /// kana and the reading would only repeat it (おいしい, アパート). One rule for the two kinds of
    /// row on this screen — the search results (`WordSearchResultRow`, since v1.35) and, since v1.36,
    /// the list's own words (`ListWordRowText`) — so the same word cannot show a reading in one and
    /// not the other.
    static func reading(for entry: VocabEntry) -> String? {
        entry.surface == entry.kana ? nil : entry.kana
    }

    /// What a query that matches nothing says. Names the query, so a typo is visible, and the four
    /// kinds of thing that can be searched for.
    static func noResults(_ query: String, zh: Bool) -> String {
        zh ? "词库里没有和“\(query)”匹配的词。可以试试假名、罗马字、汉字或词义。"
           : "No word in the dictionary matches “\(query)”. Try kana, romaji, kanji or a meaning."
    }

    /// Shown above the results when the list is at `WordListStore.maxWordsPerList`: every add
    /// button is then disabled rather than failing on tap, and this says why and what to do.
    static func fullNotice(zh: Bool) -> String {
        let max = WordListStore.maxWordsPerList
        return zh ? "该词单已满(\(max) 词)。移除一个词后才能再添加。"
                  : "This list is full (\(max) words). Remove a word to add another."
    }

    /// "In this list · 12", between the results and the list's own words while search is open.
    private func inThisListCaption(count: Int) -> some View {
        Text(zh ? "词单里的词 · \(count)" : "In this list · \(count)")
            .font(.caption.weight(.semibold)).foregroundStyle(Self.dimTextColor)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 6)
    }

    /// The small dim text the search panel draws straight on `Theme.background` — its hint, the
    /// no-results line, the first-50 note, the "In this list" caption — and the empty-list and
    /// unavailable-list lines, which point to it; since the second review, every other dim line
    /// this screen draws on the background too (the unplayable hint, the sentence and dictation
    /// launchers' notes). The list's own word rows sit on `Theme.card` and use
    /// `WordSearchResultRow.glossColor` instead. `Theme.dim` (white at 0.45) on the background
    /// computes 4.24:1 at the gradient's lighter bottom stop and 4.47:1 at the top: under the line
    /// at both. This is About's `dimTextColor`, white at
    /// 0.48 → 4.62:1 at the bottom stop, the smallest opacity that clears (0.47 → 4.49:1), read
    /// from there rather than copied so the two screens' dim text is one number with one proof
    /// (`V134B4AboutContrastTests`). `V135B6WordSearchTests.screenTextClears` recomputes every
    /// colour each view on this screen draws, over what it sits on. (v1.35 §B6 reviews)
    static let dimTextColor = AboutView.dimTextColor

    /// What the result list says to VoiceOver: nothing typed yet, nothing matched, or a count.
    enum SearchOutcome: Equatable {
        case idle
        case none
        case some(Int)
    }

    static func searchOutcome(query: String, count: Int) -> SearchOutcome {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .idle }
        return count == 0 ? .none : .some(count)
    }

    /// The line VoiceOver hears when the settled result list is compared with the last one
    /// announced (`SearchAnnouncer`: `old` is that one), or nil. Said when results appear
    /// where there were none (from an empty field or a query that matched nothing), and when
    /// they go to none from anything else; not when a count moves while there are results, nor
    /// when the field is cleared — the pattern of `CustomTextAddView.announcement` (v1.35 §F),
    /// which re-reads its notice only when it appears, goes or changes kind.
    ///
    /// `nonisolated`: it reads nothing but its arguments, and `SearchAnnouncer.due`, which is not
    /// main-actor isolated, calls it (the Swift 6 warning recorded at v1.35 §G, fixed in v1.36).
    nonisolated static func searchAnnouncement(from old: SearchOutcome, to new: SearchOutcome, limit: Int, zh: Bool) -> String? {
        switch (old, new) {
        case (.some, .some), (.none, .none), (_, .idle): return nil
        case (_, .none): return zh ? "没有匹配的词。" : "No words match."
        case (_, .some(let count)):
            if count >= limit {
                return zh ? "显示前 \(limit) 个词。" : "Showing the first \(limit) words."
            }
            return zh ? "找到 \(count) 个词。" : "\(countLabel(count, "word")) found."
        }
    }

    /// When the results are worth a VoiceOver line: after the outcome has held still, and only if
    /// its kind moved from the last one said (v1.35 §B6 review).
    ///
    /// Announcing each none ↔ some flip as it happened spoke on about every other keystroke of
    /// romaji — "tabem" read as nothing and found nothing, "tabemo" found words again — and each
    /// line cut into the typing. Two changes answer it: the search reads an unfinished kana as the
    /// text before it (`RomajiReading.partialReadings`), so the outcome no longer flips while a
    /// word is typed; and this waits `settleDelay` after the last change and compares the kind with
    /// the last ANNOUNCED one, not the previous keystroke's, so a flip and its reversal inside the
    /// wait say nothing. `V135B6WordSearchTests.typingAWordAnnouncesAtMostTwice` replays real
    /// words' keystrokes through this and `searchOutcome`.
    ///
    /// Pure, with the time passed in, so the replay can run on a synthetic clock; the view calls
    /// `changed` from the query's onChange and `due` from a task that sleeps `settleDelay`.
    ///
    /// **An emptied field resets at once** (round 3). Clearing the field says nothing, but it does
    /// end what was said: the next results are news. The first version waited for the empty field
    /// to SETTLE before it forgot the last line, so a learner who cleared "water" and typed "mizu"
    /// inside 0.8 s — select-all and retype, or delete and go on — heard nothing about mizu's
    /// results: some → some. Now `changed(to: .idle)` sets `announced` to idle then and there, and
    /// drops any line still pending (there is nothing to say about an empty field).
    struct SearchAnnouncer {
        static let settleDelay: Duration = .milliseconds(800)

        private(set) var announced: SearchOutcome = .idle
        private var pending: SearchOutcome?
        private var changedAt: ContinuousClock.Instant?

        mutating func changed(to outcome: SearchOutcome, at time: ContinuousClock.Instant) {
            if outcome == .idle {
                announced = .idle
                pending = nil
                changedAt = nil
                return
            }
            pending = outcome
            changedAt = time
        }

        /// The line to post at `time`, or nil: nil until the last change is `settleDelay` old,
        /// and nil when the settled kind is the one last said (`searchAnnouncement`'s table).
        mutating func due(at time: ContinuousClock.Instant, limit: Int, zh: Bool) -> String? {
            guard let outcome = pending, let changedAt, time - changedAt >= Self.settleDelay else { return nil }
            pending = nil
            let line = ListDetailView.searchAnnouncement(from: announced, to: outcome, limit: limit, zh: zh)
            announced = outcome
            return line
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
                    .font(.caption).foregroundStyle(Self.dimTextColor)
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
                        .font(.caption).foregroundStyle(Self.dimTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var unplayableHint: some View {
        Text(zh ? "这些词在本设备上暂不可用(可能来自更新版本的词库)。"
                : "These words aren't available on this device (they may come from a newer vocabulary).")
            .font(.callout).foregroundStyle(Self.dimTextColor)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 4)
    }

    /// One of the list's own words, on `Theme.card`: its text column (`ListWordRowText` — the word,
    /// its reading, its gloss; or a removed word's label and note) and its Remove button, which is
    /// its own element for VoiceOver and for the UI test (`removeWord-<id>`). The column's dim text
    /// is `WordSearchResultRow.glossColor`, the search row's card colour (4.57:1): it sits right
    /// under the results while search is open, and was `Theme.dim` (3.91:1), the note at 0.7 of
    /// that (2.67:1). (v1.35 §B6, second review; colour only.) Since v1.36 the column shows the
    /// reading by the search results' rule (`reading(for:)`) and the gloss wraps instead of being
    /// cut to one line; it is handed the text size as `scale`, as the result rows are.
    ///
    /// ⚠️ **At the accessibility text sizes the Remove button goes under the text**, the
    /// arrangement `WordSearchResultRow` (directly above, while search is open) and
    /// `ListsView.listRow` use, so the column keeps the row's whole width. Beside it, the button
    /// grows with the text and left the column 168pt on a 320pt phone at AX5 (248pt stacked),
    /// where the gloss is 37pt and one English word can be wider than the line: 便利's
    /// "convenient" took two lines for its one word — the "★ / Save / d" shape v1.33 fixed on the
    /// lists screen by stacking — and so did a word in 1,476 of the 7,071 English glosses. How
    /// many glosses break a word, beside and stacked, and the residue stacking leaves, are measured
    /// in `V136ListRowsTests.glossWordsAreWhole`. Below the accessibility sizes the row is what it
    /// was. (v1.36 §C item 1, review.)
    private func wordRow(id: String, listID: String) -> some View {
        let entry = model.vocab.entry(id: id)
        let content: ListWordRowText.Content = entry.map {
            .word(surface: $0.surface, reading: Self.reading(for: $0), gloss: $0.gloss(for: model.languageCode))
        } ?? .removed
        let text = ListWordRowText(content: content, zh: zh, scale: bodyPoints / 17)
        let remove = Button { model.removeWord(id, from: listID) } label: {
            Image(systemName: "minus.circle")
                .scaledSystemFont(16)
                .foregroundStyle(Theme.accent)
                .padding(6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("removeWord-\(id)")
        .accessibilityLabel(zh ? "从词单移除 \(entry?.surface ?? id)"
                               : "Remove \(entry?.surface ?? id) from list")
        return Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    text
                    remove
                }
            } else {
                HStack(spacing: 10) {
                    text
                    remove
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
    }

    /// A list that is gone — deleted on another device while this screen was open, or an id that
    /// no longer resolves. Until the v1.35 §B6 review this branch showed `emptyState`, which
    /// tells the learner to search the dictionary: a button this branch does not draw, for a list
    /// that cannot take a word. It says what happened and where to go instead.
    private var unavailableState: some View {
        Text(Self.unavailableText(zh: zh))
            .font(.callout).foregroundStyle(Self.dimTextColor)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 8)
    }

    static func unavailableText(zh: Bool) -> String {
        zh ? "这个词单已不存在,可能已在另一台设备上删除。返回即可查看你的词单。"
           : "This list isn't here any more — it may have been deleted on another device. Go back to see your lists."
    }

    /// Until v1.35 this said a list could only be filled by riding, which was true; search is the
    /// second way, and the copy names it first because it is the one on this screen — drawn only
    /// for a live list, where that button is.
    private var emptyState: some View {
        Text(Self.emptyStateText(zh: zh))
            .font(.callout).foregroundStyle(Self.dimTextColor)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 8)
    }

    /// ⚠️ **At the accessibility sizes the title may wrap, and Back moves above it** — the
    /// arrangement `ScreenHeader` documents, for its reason: at those sizes the title alone can
    /// fill the row, and a way out pushed off the screen is not a way out.
    ///
    /// Below them the title stays one line, as it always was. At AX5 that one line truncated the
    /// default list to "★ Sav…" (simulator pass #14, 402pt iPhone 17 Pro). Letting it wrap BESIDE
    /// Back would not be enough: measured with CoreText for a 393pt phone at AX5, 2026-09-17,
    /// Back leaves the title 179pt and "Vocabulary" needs 274, so a one-word name would break
    /// mid-word instead of truncating. Above Back it has the full 349. (v1.33 §B L.)
    @ViewBuilder
    private var header: some View {
        let name = list.map { $0.isDefault ? AppModel.defaultListName(model.languageCode) : $0.name }
            ?? (zh ? "词单" : "List")
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                backButton
                Text(name)
                    .scaledSystemFont(28, weight: .heavy, design: .rounded, relativeTo: .largeTitle)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack {
                Text(name)
                    .scaledSystemFont(28, weight: .heavy, design: .rounded, relativeTo: .largeTitle)
                    .foregroundStyle(.white).lineLimit(1)
                Spacer()
                backButton
            }
        }
    }

    private var backButton: some View {
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

    private func backToLists() {
        // A pending announcement is about this screen's results; the lists screen is next.
        resetAnnouncer()
        model.selectedListID = nil
        model.screen = .lists
    }

    static func emptyStateText(zh: Bool) -> String {
        zh ? "这个词单还没有词。可以搜索词库来添加,也可以在游戏或结算页点 ★ 收藏。"
           : "No words yet. Search the dictionary to add some, or tap ★ during a ride or on the results screen."
    }
}

/// One search result on a list's detail screen (v1.35 §B6): the word, its reading when the word
/// is not already kana, its gloss in the UI language, and an add control.
///
/// **One element for VoiceOver.** The whole row is the add button, so it reads as one element —
/// "水, みず, water", value "not in list" — and activating it adds. It also carries a named
/// "Add to list" action while it can add, and none once it cannot: a word already in the list
/// shows a checkmark and is disabled, and so is every row while the list is at its cap (the
/// panel above says why).
///
/// **Nothing is truncated, at any size.** Every line wraps (`fixedSize(horizontal: false,
/// vertical: true)`, no `lineLimit`): the word, because a cut headword is a different word; the
/// gloss, because it is what tells two readings apart. At the accessibility sizes (`stacked`) the
/// control moves under the text instead of beside it, the arrangement `ListsView.listRow` uses,
/// so the text keeps the row's whole width. `V135B6WordSearchTests` lays this view out at the
/// five accessibility sizes with the corpus's longest word, reading and glosses, in both
/// languages, and checks from the pixels that the last character of each is drawn.
///
/// **Sizes arrive as `scale`**, the body text's Dynamic Type multiplier, instead of through
/// `scaledSystemFont` inside the row: a hosted view on macOS does not scale with
/// `dynamicTypeSize`, so a row that scaled itself could only ever be tested at the default size.
/// At `scale` 1 the fonts are exactly `scaledSystemFont`'s at the default size.
struct WordSearchResultRow: View {
    enum State: Equatable { case addable, inList, listFull }

    let surface: String
    /// The reading, or nil when the word is written in kana and the reading would repeat it.
    let reading: String?
    let gloss: String
    let state: State
    let zh: Bool
    /// The accessibility sizes: the add control goes under the text.
    let stacked: Bool
    /// Body text size ÷ 17 at the learner's setting (1 at the default size).
    let scale: CGFloat
    let add: () -> Void

    static let wordPoints: CGFloat = 18
    static let readingPoints: CGFloat = 14
    static let glossPoints: CGFloat = 14
    static let iconPoints: CGFloat = 22

    static func state(inList: Bool, wordCount: Int, cap: Int) -> State {
        if inList { return .inList }
        return wordCount >= cap ? .listFull : .addable
    }

    var body: some View {
        Button(action: add) {
            Group {
                if stacked {
                    VStack(alignment: .leading, spacing: 8) {
                        text
                        icon
                    }
                } else {
                    HStack(alignment: .center, spacing: 12) {
                        text
                        icon
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(RowStyle())
        .disabled(state != .addable)
        .accessibilityLabel(Self.accessibilityLabel(surface: surface, reading: reading, gloss: gloss))
        .accessibilityValue(Self.accessibilityValue(state, zh: zh))
        .accessibilityActions {
            if state == .addable {
                Button(Self.addActionName(zh: zh), action: add)
            }
        }
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(surface)
                .font(.system(size: Self.wordPoints * scale, weight: .semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            if let reading {
                Text(reading)
                    .font(.system(size: Self.readingPoints * scale))
                    .foregroundStyle(Theme.accent2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(gloss)
                .font(.system(size: Self.glossPoints * scale))
                .foregroundStyle(Self.glossColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var icon: some View {
        Image(systemName: state == .inList ? "checkmark.circle.fill" : "plus.circle.fill")
            .font(.system(size: Self.iconPoints * scale))
            .foregroundStyle(state == .inList ? Theme.gold : state == .addable ? Theme.accent : Self.glossColor)
    }

    /// The gloss, and the full-list icon, on the row's `Theme.card`. `Theme.dim` there computed
    /// **3.91:1** (the card is white at 0.06 over the gradient, lighter than what is behind it).
    /// This is About's `dimTextOnCardColor`, white at 0.51 → 4.57:1 on the card at the bottom
    /// stop, 5.03:1 at the top — the smallest that clears (0.50 → 4.46:1) — read from there so the
    /// app has one "dim on a card" number (`V134B4AboutContrastTests` proves it). The row's other
    /// colours — white, `Theme.accent2`, `Theme.gold`, `Theme.accent` — are recomputed with this
    /// one by `V135B6WordSearchTests.rowTextClears`, in every state; and the disabled rows draw
    /// the same pixels as an addable one (`disabledRowIsNotDimmed`). (v1.35 §B6 review)
    static let glossColor = AboutView.dimTextOnCardColor

    /// The row's button style: the label as drawn, shrunk a little while pressed. Not `.plain`,
    /// because `.plain` dims a DISABLED button's whole label — measured in the renderer,
    /// 2026-09-29: the gloss went from 137 to 71 of 255 and the white word to 131 on an in-list
    /// or full-list row, about 2:1 on the card — and every row of a full list is disabled. Here
    /// `.disabled` still does what it is for (no action, VoiceOver's "dimmed"), the icon and the
    /// value say which state the row is in, and the text keeps the colours whose contrast
    /// `rowTextClears` computes. The press feedback is a scale, not an opacity, for the same
    /// reason. (v1.35 §B6 review)
    struct RowStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
        }
    }

    static func accessibilityLabel(surface: String, reading: String?, gloss: String) -> String {
        [surface, reading, gloss].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// The same words the add-to-lists sheet uses for membership, plus the cap.
    static func accessibilityValue(_ state: State, zh: Bool) -> String {
        switch state {
        case .addable: return zh ? "未加入" : "not in list"
        case .inList: return zh ? "已加入" : "in list"
        case .listFull: return zh ? "词单已满" : "list is full"
        }
    }

    static func addActionName(zh: Bool) -> String { zh ? "加入词单" : "Add to list" }
}

/// The text of one of a list's own words on its detail screen (v1.36 §C item 1): the word, its
/// reading under it when the word is not written in kana (`ListDetailView.reading(for:)`, the rule
/// the search results above it use), and its gloss in the UI language. `ListDetailView.wordRow`
/// puts it beside the word's Remove button, on the row's card — above the button at the
/// accessibility sizes, so it keeps the row's whole width there.
///
/// Until v1.36 this column drew the word and a gloss cut to one line (`.lineLimit(1)`): a list's
/// own words had no reading while the search results right above them did (PLAN-V1.33 §C,
/// "list-detail rows without a reading").
///
/// **Nothing is truncated, at any size** — `WordSearchResultRow`'s rule: every line wraps
/// (`fixedSize(horizontal: false, vertical: true)`, no `lineLimit`). `V136ListRowsTests` lays the
/// column out at the default size and the five accessibility sizes, with the corpus's longest
/// word, reading and glosses, in the width `wordRow` leaves it, and checks from the pixels that the
/// last character of each line is drawn and that a gloss wider than the column wraps; and lays
/// every gloss in the corpus out at those sizes to count the ones that break inside a word. The
/// residue is a single English word wider than the whole line — 46 glosses at AX4 and AX5 on a
/// 320pt phone, "otorhinolaryngology" and "misunderstanding" among them, none N5
/// (`V136ListRowsTests.glossWordsAreWhole`).
///
/// **One element for VoiceOver**, read the way the search row is — "水, みず, water", through
/// `WordSearchResultRow.accessibilityLabel` — instead of a stop per line. A removed word is one
/// element too: its label, then its note. The Remove button beside it (or under it) is not inside
/// it.
///
/// **Sizes arrive as `scale`**, the body text's Dynamic Type multiplier, as the result row's do, so
/// a hosted test can lay the column out at the accessibility sizes (a hosted view on macOS ignores
/// `dynamicTypeSize`). At `scale` 1 the word is exactly what `scaledSystemFont(16, weight:
/// .semibold)` drew here before, and the gloss and the removed-word note are the iOS default
/// `.caption` and `.caption2` sizes they were drawn at (12 and 11pt, regular). On macOS those two
/// styles are 10pt — `.caption2` in medium — so a Mac now shows the gloss two points and the note
/// one point larger, the note in regular (measured in the renderer, 2026-10-07). Every line scales
/// at the body's rate, as the result row's do.
///
/// **A word whose entry is gone** (`.removed`) shows "Removed word" and a note, not its raw internal
/// id — "n2-b984" where a learner expects 「ペン」. That was only reachable via a list synced from a
/// newer device until v1.22, which withdraws an entry outright, so it is a thing a learner can
/// actually meet. An id is not a word; this says so instead. Unchanged by v1.36 but for the sizes
/// above and the one VoiceOver element.
struct ListWordRowText: View {
    enum Content: Equatable {
        /// A word in the dictionary. `reading` is nil when it would repeat `surface`.
        case word(surface: String, reading: String?, gloss: String)
        /// A word whose entry is no longer in the dictionary.
        case removed
    }

    let content: Content
    let zh: Bool
    /// Body text size ÷ 17 at the learner's setting (1 at the default size).
    let scale: CGFloat

    static let wordPoints: CGFloat = 16
    static let readingPoints: CGFloat = 13
    static let glossPoints: CGFloat = 12
    static let notePoints: CGFloat = 11

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch content {
            case .word(let surface, let reading, let gloss):
                Text(surface)
                    .font(.system(size: Self.wordPoints * scale, weight: .semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                if let reading {
                    Text(reading)
                        .font(.system(size: Self.readingPoints * scale))
                        .foregroundStyle(WordSearchResultRow.glossColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(gloss)
                    .font(.system(size: Self.glossPoints * scale))
                    .foregroundStyle(WordSearchResultRow.glossColor)
                    .fixedSize(horizontal: false, vertical: true)
            case .removed:
                Text(Self.removedLabel(zh: zh))
                    .font(.system(size: Self.wordPoints * scale, weight: .semibold))
                    .foregroundStyle(WordSearchResultRow.glossColor)
                    .fixedSize(horizontal: false, vertical: true)
                Text(Self.removedNote(zh: zh))
                    .font(.system(size: Self.notePoints * scale))
                    .foregroundStyle(WordSearchResultRow.glossColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.accessibilityLabel(content, zh: zh))
    }

    static func removedLabel(zh: Bool) -> String { zh ? "已移除的词" : "Removed word" }

    static func removedNote(zh: Bool) -> String {
        zh ? "此词已从词库中移除,可以删掉这一行" : "No longer in the dictionary — you can remove it"
    }

    /// The column's one VoiceOver label: the search row's for a word, so the two rows read alike.
    static func accessibilityLabel(_ content: Content, zh: Bool) -> String {
        switch content {
        case .word(let surface, let reading, let gloss):
            return WordSearchResultRow.accessibilityLabel(surface: surface, reading: reading, gloss: gloss)
        case .removed:
            return removedLabel(zh: zh) + (zh ? "," : ", ") + removedNote(zh: zh)
        }
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
