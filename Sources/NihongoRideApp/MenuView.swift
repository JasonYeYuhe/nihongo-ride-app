import SwiftUI
import VocabKit
import GameCore

struct MenuView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        menu.sheet(isPresented: $managingCustomTexts) { CustomTextsView() }
    }

    @ViewBuilder
    private var menu: some View {
        // iPhone: the stack can outgrow short screens (SE class), so scroll.
        if isPhoneIdiom {
            ScrollView(showsIndicators: false) { content }
        } else {
            // **A Mac window is a short screen too, and this branch used to assume it never was.**
            //
            // `content` opens with a `Spacer()`, so when it does not fit it is CENTRED and clipped
            // at BOTH ends — the "Nihongo Ride" title off the top, the Ride Log / Word Lists /
            // Stats / Settings row off the bottom — with no way to reach either, because there was
            // nothing to scroll. Measured at 900×632, which is a real saved window frame on this
            // machine, and `minHeight: 600` in `NihongoRideApp` permits shorter still.
            //
            // The comment above states the reason correctly and applied it to one platform: a rule
            // right for one population, silently wrong on another. That is this project's rule 5,
            // and here it was sitting in the sentence that explains the fix.
            //
            // `minHeight: proxy.size.height` is what keeps the appearance identical when the
            // window IS tall: the content still gets at least the viewport, so the Spacers still
            // centre it exactly as before. It only scrolls once it genuinely does not fit.
            // The iPhone branch is left byte-identical — its Spacers collapse inside a plain
            // ScrollView today, and giving it a minimum height would change a shipped layout.
            // …and NOT while capturing. `ImageRenderer` does not lay out a ScrollView's contents,
            // so wrapping the menu unconditionally would have rendered the app's PRIMARY App Store
            // screenshot blank — the same guard every other screen in this app already carries,
            // and the reason each of them writes `if Screenshotter.isCapturing { content } else`.
            if Screenshotter.isCapturing {
                content
            } else {
                GeometryReader { proxy in
                    ScrollView(showsIndicators: false) {
                        content.frame(minWidth: proxy.size.width, minHeight: proxy.size.height)
                    }
                }
            }
        }
    }

    @State private var managingCustomTexts = false

    /// Choosing which of the learner's own texts to ride, and getting to the editor.
    ///
    /// Extracted as its own property rather than inlined: this file's `content` already sits at
    /// the Swift type-checker's limit, and adding four views to it failed to compile with
    /// "unable to type-check this expression in reasonable time" — on a line 130 rows away from
    /// the edit.
    @ViewBuilder
    private var customTextRow: some View {
        let zh = model.languageCode == "zh"
        HStack(spacing: 12) {
            Image(systemName: "doc.text").accessibilityHidden(true)
            if model.customTexts.isEmpty {
                Button(zh ? "添加我的文本…" : "Add your own text…") { managingCustomTexts = true }
                    .accessibilityIdentifier("customTextEmptyAdd")
            } else {
                Menu {
                    ForEach(model.customTexts.ordered) { text in
                        Button(text.title) { model.selectedCustomTextID = text.id }
                    }
                    Divider()
                    Button(zh ? "管理…" : "Manage…") { managingCustomTexts = true }
                } label: {
                    Text(model.customTextForRun?.title ?? (zh ? "选择文本" : "Choose a text"))
                        .lineLimit(1)
                }
                .menuControlWidth(220)
                .accessibilityIdentifier("customTextPicker")
            }
        }
        if !model.customTexts.isEmpty {
            // The RUN's number. `typeableSentences` is what the queue is built from, and the
            // stored count can be larger — so the label reads the same property the run does,
            // which is the one rule this project has paid for two dozen times.
            Text(customTextRunLabel(zh: zh))
                .scaledSystemFont(12, weight: .medium)
                .foregroundStyle(Theme.dim)
                .accessibilityIdentifier("customTextRunLabel")
        }
    }

    private func customTextRunLabel(zh: Bool) -> String {
        let n = model.customTextRunCount
        if n == 0 {
            return zh ? "这段文本没有可输入的句子" : "Nothing in this text can be typed"
        }
        return zh ? "\(n) 句" : "\(n) sentence\(n == 1 ? "" : "s")"
    }

    private var content: some View {
        @Bindable var model = model

        return VStack(spacing: isPhoneIdiom ? 20 : 28) {
            Spacer()

            VStack(spacing: 10) {
                Text("Nihongo Ride")
                    .scaledSystemFont(isPhoneIdiom ? 38 : 60, weight: .heavy, design: .rounded, relativeTo: .largeTitle)
                    .foregroundStyle(.white)
                Text("にほんご ライド")
                    .scaledSystemFont(isPhoneIdiom ? 16 : 22, weight: .semibold, design: .rounded)
                    .tracking(isPhoneIdiom ? 3 : 4)
                    .foregroundStyle(Theme.accent)
                Text(model.languageCode == "zh"
                     ? "打字环游日本 · 边骑边学"
                     : "Type your way across Japan")
                    .font(isPhoneIdiom ? .callout : .title3)
                    .foregroundStyle(Theme.dim)
            }

            // At the accessibility text sizes the four-stop strip collapses: each city name
            // wraps to one letter per line and lands on top of the bicycles between them.
            // It is decoration carrying one sentence of information, so at those sizes it
            // becomes that sentence — which is also exactly what VoiceOver already read.
            // (v1.14 §C, found on a device; the headless gate renders only the default size.)
            if typeSize.isAccessibilitySize {
                // The strip collapses at these sizes and becomes its sentence — and after Kyōto
                // that sentence is also the second entrance, so it has to stay reachable. An
                // entrance that exists at default text size and vanishes at accessibility sizes
                // is the same defect as one that exists for sighted riders only.
                let sentence = Text(routeLabel)
                    .font(.callout).foregroundStyle(Theme.dim)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
                if arrived {
                    Button(action: model.showRoad) { sentence }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("menuRouteEntrance")
                        .onAppear { model.recordMenuRouteEntranceAppeared() }
                } else {
                    sentence
                }
            } else {
                routePreview
                    .frame(maxWidth: 520)
                    .padding(.vertical, isPhoneIdiom ? 0 : 8)
                    .accessibilityElement()
                    .accessibilityLabel(routeLabel)
            }

            VStack(spacing: 18) {
                // Six modes, and a segmented control cannot label six. It divides its width
                // evenly and truncates, so "Sentence" and "Practice" become "Sente…" on an
                // iPhone — and the labels only get longer at large Dynamic Type. This is the
                // wrapping capsule layout the conjugation-form picker on this same screen
                // already uses: it reflows instead of shrinking, so a seventh mode would cost
                // a row rather than the words. Buttons are fine here — the keyboard-capture
                // red line applies to GAME screens, and the menu suppresses the keyboard.
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "gamecontroller").accessibilityHidden(true)
                        Text(model.languageCode == "zh" ? "模式" : "Mode")
                            .scaledSystemFont(14, weight: .semibold, design: .rounded)
                            .foregroundStyle(Theme.dim)
                        Spacer()
                    }
                    MenuFlow(spacing: 8, rowSpacing: 8) {
                        ForEach(modeOptions, id: \.mode) { option in
                            let on = model.selectedMode == option.mode
                            Button(action: { model.selectedMode = option.mode }) {
                                Text(option.label)
                                    .scaledSystemFont(14, weight: .semibold, design: .rounded)
                                    .lineLimit(1)
                                    .foregroundStyle(on ? .white : Theme.dim)
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(on ? Theme.accent : Theme.card, in: Capsule())
                                    .overlay(Capsule().strokeBorder(on ? Color.clear : Theme.cardStroke))
                            }
                            .buttonStyle(.plain)
                            .fixedSize()
                            .accessibilityLabel(option.label)
                            .accessibilityAddTraits(on ? [.isSelected] : [])
                        }
                    }
                }
                .menuControlWidth(340)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(model.languageCode == "zh" ? "游戏模式" : "Game mode")
                HStack(spacing: 12) {
                    Image(systemName: "globe").accessibilityHidden(true)
                    Picker("", selection: $model.languageCode) {
                        Text("English").tag("en")
                        Text("中文").tag("zh")
                    }
                    .pickerStyle(.segmented)
                    .menuControlWidth(220)
                    .accessibilityLabel(model.languageCode == "zh" ? "界面语言" : "Language")
                }
                // JLPT level applies to word-stream modes; Practice Passages has its own level picker below.
                let showJLPT = !(model.selectedMode == .practice && model.practicePassages)
                if showJLPT {
                    HStack(spacing: 12) {
                        Image(systemName: "graduationcap").accessibilityHidden(true)
                        Picker("", selection: $model.selectedLevel) {
                            ForEach(JLPTLevel.allCases, id: \.self) { level in
                                Text(level.label).tag(JLPTLevel?.some(level))
                            }
                            Text(model.languageCode == "zh" ? "混合" : "All").tag(JLPTLevel?.none)
                        }
                        .pickerStyle(.segmented)
                        .menuControlWidth(300)
                        .accessibilityLabel(model.languageCode == "zh" ? "JLPT 等级" : "JLPT level")
                    }
                }
                // Conjugation: pick which forms to drill (native buttons — no soft
                // keyboard). Empty selection = all forms (the drill builder falls back).
                if model.selectedMode == .conjugation {
                    let zh = model.languageCode == "zh"
                    VStack(spacing: 8) {
                        HStack(spacing: 12) {
                            Image(systemName: "switch.2").accessibilityHidden(true)
                            Text(zh ? "练习形" : "Forms")
                                .scaledSystemFont(14, weight: .semibold, design: .rounded)
                                .foregroundStyle(Theme.dim)
                            Spacer()
                        }
                        MenuFlow(spacing: 8, rowSpacing: 8) {
                            ForEach(model.conjugationFormOptions) { option in
                                let on = model.isConjugationFormSelected(option.rawValue)
                                Button(action: { model.toggleConjugationForm(option.rawValue) }) {
                                    Text(option.shortLabel)
                                        .scaledSystemFont(14, weight: .semibold, design: .rounded)
                                        .lineLimit(1)
                                        .foregroundStyle(on ? .white : Theme.dim)
                                        .padding(.horizontal, 12).padding(.vertical, 6)
                                        .background(on ? Theme.accent : Theme.card, in: Capsule())
                                        .overlay(Capsule().strokeBorder(on ? Color.clear : Theme.cardStroke))
                                }
                                .buttonStyle(.plain)
                                .fixedSize()
                                .accessibilityLabel(option.accessibilityLabel)
                                .accessibilityValue(on ? (zh ? "已选" : "Selected") : (zh ? "未选" : "Not selected"))
                                .accessibilityAddTraits(on ? [.isSelected] : [])
                            }
                        }
                        Text(model.conjugationForms.isEmpty
                             ? (zh ? "未选 = 全部形" : "None selected = all forms")
                             : (zh ? "只练所选形" : "Drilling selected forms only"))
                            .font(.caption2).foregroundStyle(Theme.dim.opacity(0.8))

                        // Due-review entry (v1.8 §B): shown only when conjugation cards are
                        // due. Runs the spaced-review drill (due forms first, weak-form fill).
                        if model.conjugationDueCount > 0 {
                            // The view is handed no number: both strings are composed beside
                            // the queue they describe, so this call site cannot pick the pool
                            // over the run. (v1.26 §B.) Bound once — each of these properties
                            // filters and sorts the whole store, and asking three times per
                            // body evaluation is three scans for one answer.
                            let buttonText = model.conjugationReviewButtonText(zh: zh)
                            let buttonLabel = model.conjugationReviewButtonLabel(zh: zh)
                            Button(action: model.startConjugationReview) {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .accessibilityHidden(true)
                                    Text(buttonText)
                                        .scaledSystemFont(14, weight: .semibold, design: .rounded)
                                        .lineLimit(1)
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16).padding(.vertical, 8)
                                .background(Theme.accent2, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .fixedSize()
                            .padding(.top, 2)
                            .accessibilityLabel(buttonLabel)
                        }
                    }
                    .menuControlWidth(340)
                }
                // Sentence mode can follow what the learner is actually studying rather than
                // a level pool (PLAN-V1.21 §B). Due-scoped sentences get a launcher here,
                // mirroring the conjugation due-review entry above; list-scoped ones live on
                // the list itself, next to the word-practice button. Shown only when there is
                // something due WITH a sentence — a live count, never a stale flag.
                if model.selectedMode == .sentence {
                    let zh = model.languageCode == "zh"
                    let due = model.dueSentenceCount
                    VStack(spacing: 6) {
                        if due > 0 {
                            Button(action: model.startSentenceDue) {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .accessibilityHidden(true)
                                    Text(zh ? "到期词的例句 · 可用 \(due) 句"
                                            : "Due sentences · \(due) available")
                                        .scaledSystemFont(14, weight: .semibold, design: .rounded)
                                        .lineLimit(1)
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16).padding(.vertical, 8)
                                .background(Theme.accent2, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .fixedSize()
                            .accessibilityIdentifier("dueSentencesButton")
                            .accessibilityLabel(zh ? "练习到期词的例句,有 \(due) 句可用"
                                                   : "Practise sentences for words due today, \(due) available")
                        }
                        Text(zh ? "词单里的例句在「词单」里开始" : "Sentences for a saved list start from Word Lists")
                            .font(.caption2).foregroundStyle(Theme.dim.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                    .menuControlWidth(340)
                }
                // Dictation's own due launcher, the sibling of the sentence one above.
                // Its count is smaller than the sentence count for a reason the learner
                // cannot see, so it gets its own number rather than reusing that one.
                if model.selectedMode == .dictation, model.dictationAvailable {
                    let zh = model.languageCode == "zh"
                    let due = model.dueDictationCount
                    VStack(spacing: 6) {
                        if due > 0 {
                            Button(action: model.startDictationDue) {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .accessibilityHidden(true)
                                    Text(zh ? "到期词的听写 · 可用 \(due) 句"
                                            : "Due dictation · \(due) available")
                                        .scaledSystemFont(14, weight: .semibold, design: .rounded)
                                        .lineLimit(1)
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16).padding(.vertical, 8)
                                .background(Theme.accent2, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .fixedSize()
                            .accessibilityIdentifier("dueDictationButton")
                            .accessibilityLabel(zh ? "听写 \(due) 个到期词的例句"
                                                   : "Dictation for \(due) words due today")
                        }
                        Text(zh ? "词单里的听写在「词单」里开始" : "Dictation for a saved list starts from Word Lists")
                            .font(.caption2).foregroundStyle(Theme.dim.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                    .menuControlWidth(340)
                }
                if model.selectedMode == .practice {
                    HStack(spacing: 12) {
                        Image(systemName: "text.alignleft").accessibilityHidden(true)
                        Picker("", selection: $model.practiceSource) {
                            Text(model.languageCode == "zh" ? "文章" : "Passages")
                                .tag(AppModel.PracticeSource.passages)
                            Text(model.languageCode == "zh" ? "词流" : "Words")
                                .tag(AppModel.PracticeSource.words)
                            Text(model.languageCode == "zh" ? "我的文本" : "My text")
                                .tag(AppModel.PracticeSource.custom)
                        }
                        .pickerStyle(.segmented)
                        .menuControlWidth(300)
                        .accessibilityLabel(model.languageCode == "zh" ? "练习内容" : "Practice content")
                    }
                    if model.practiceSource == .custom {
                        customTextRow
                    }
                    if model.practicePassages {
                        HStack(spacing: 12) {
                            Image(systemName: "ruler").accessibilityHidden(true)
                            Picker("", selection: $model.practicePassageLevel) {
                                Text(model.languageCode == "zh" ? "短" : "Short").tag(Passage.Level.easy)
                                Text(model.languageCode == "zh" ? "中" : "Med").tag(Passage.Level.med)
                                Text(model.languageCode == "zh" ? "长" : "Long").tag(Passage.Level.hard)
                            }
                            .pickerStyle(.segmented)
                            .menuControlWidth(220)
                            .accessibilityLabel(model.languageCode == "zh" ? "文章长度" : "Passage length")
                        }
                    }
                }
                // One assistance policy (v1.16 §A), replacing the hints on/off toggle. The
                // middle option is why this is a picker: "offer help only when I'm stuck" is
                // a real position between study mode and blind practice, and it is the one
                // the old boolean could not express.
                HStack(spacing: 12) {
                    Image(systemName: "character.cursor.ibeam").accessibilityHidden(true)
                    Picker("", selection: $model.assistance) {
                        Text(model.languageCode == "zh" ? "总是提示" : "Hints on").tag(AssistanceMode.always)
                        Text(model.languageCode == "zh" ? "卡住时" : "When stuck").tag(AssistanceMode.afterStruggle)
                        Text(model.languageCode == "zh" ? "关闭" : "Off").tag(AssistanceMode.off)
                    }
                    .pickerStyle(.segmented)
                    .menuControlWidth(320)
                    .accessibilityLabel(model.languageCode == "zh" ? "罗马字提示" : "Romaji assistance")
                }
                Toggle(isOn: $model.soundEnabled) {
                    Label(model.languageCode == "zh" ? "音效" : "Sound effects",
                          systemImage: "speaker.wave.2.fill")
                }
                .toggleStyle(.switch)
                .tint(Theme.accent2)
                .menuControlWidth(320)
            }
            .panel()
            .frame(maxWidth: 420)

            let isConjugation = model.selectedMode == .conjugation
            let isDictation = model.selectedMode == .dictation
            let zhLang = model.languageCode == "zh"
            // Disabled rather than hidden, and paired with the notice below: a start button
            // that silently does nothing is the failure this mode is most likely to ship.
            let startable = !isDictation || model.dictationAvailable
            Button(action: model.startGame) {
                Text(isConjugation ? (zhLang ? "开始变形 ▶" : "Start drill ▶")
                     : isDictation ? (zhLang ? "开始听写 ▶" : "Start dictation ▶")
                                   : (zhLang ? "出发 ▶" : "Start ride ▶"))
                    .scaledSystemFont(20, weight: .bold, design: .rounded)
                    .ctaLabel(minWidth: 240, minHeight: 54)
            }
            .buttonStyle(.plain)
            .background(startable ? Theme.accent : Theme.card, in: Capsule())
            .foregroundStyle(startable ? .white : Theme.dim)
            .shadow(color: Theme.accent.opacity(startable ? 0.5 : 0), radius: 16, y: 6)
            .disabled(!startable)
            .accessibilityIdentifier("startButton")
            .accessibilityLabel(isConjugation ? (zhLang ? "开始动词变形练习" : "Start conjugation drill")
                                : isDictation ? (zhLang ? "开始听写练习" : "Start dictation")
                                              : (zhLang ? "出发,开始骑行" : "Start ride"))
            // A whole mode cannot degrade the way the read-aloud button does. That button
            // hides itself when no Japanese voice is installed and a learner who never saw
            // it loses nothing; pick dictation on the same device and you get a run of
            // silence that is indistinguishable from a bug. So the entry stays visible and
            // says what is wrong and where to fix it. (PLAN-V1.21 §A.)
            if model.selectedMode == .dictation, !model.dictationAvailable {
                Text(zhLang ? "未检测到日语语音,无法听写。请在系统「设置 › 辅助功能 › 朗读内容」中下载日语语音。"
                            : "Dictation needs a Japanese voice. Add one in System Settings › Accessibility › Spoken Content.")
                    .font(.caption).foregroundStyle(Theme.accent)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .accessibilityIdentifier("dictationUnavailableNotice")
            } else if model.selectedMode == .dictation, !model.dictationAudioSessionOK {
                // Only ever shown after a run has actually tried and failed to claim the
                // session — a guess about the mute switch would be noise on every launch.
                Text(zhLang ? "如果听不到声音,请检查手机的静音开关和音量。"
                            : "If you hear nothing, check the silent switch and the volume.")
                    .font(.caption).foregroundStyle(Theme.dim)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            // Derived live from the pool (never a stale flag): updates as the level
            // changes. With shipped data every level has verbs, so this stays hidden.
            if isConjugation && model.conjugationPoolCount == 0 {
                Text(zhLang ? "该等级暂无可练的动词,换个等级试试。"
                            : "No verbs to drill at this level — try another level.")
                    .font(.caption).foregroundStyle(Theme.accent)
                    .multilineTextAlignment(.center)
            }
            // Dictation's live-count sibling to the conjugation one. Its pool is smaller
            // than sentence mode's (the withheld readings), so "there is nothing here" is a
            // different sentence from the level-pool message below — which says "come back
            // tomorrow", the remedy for an exhausted SRS queue and not for this.
            if isDictation, model.dictationAvailable, model.dictationPoolCount == 0 {
                Text(zhLang ? "这个等级暂时没有可用于听写的句子,换个等级试试。"
                            : "No sentences are available for dictation at this level — try another.")
                    .font(.caption).foregroundStyle(Theme.accent)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            // The ride equivalent, but a FLAG rather than a live count: "is there anything to
            // ride" depends on the SRS schedule and the mode's own queue rules, so the only
            // honest test is the one startGame already performs. Set when a start attempt
            // finds an empty queue, cleared by the next successful one. Without it that tap
            // did nothing visible except flash a results screen claiming 100% accuracy on a
            // run with no keystrokes. (v1.15 §D.)
            if !isConjugation && !isDictation && model.emptyPoolNotice {
                Text(zhLang ? "这个等级的词今天都复习完了,换个等级或明天再来。"
                            : "Nothing due at this level today — try another level, or come back tomorrow.")
                    .font(.caption).foregroundStyle(Theme.accent)
                    .multilineTextAlignment(.center)
            }

            footer

            MenuFlow(spacing: 12, rowSpacing: 10) {
                Button(action: { model.screen = .journal }) {
                    Label {
                        Text(model.languageCode == "zh" ? "骑行日志" : "Ride Log")
                            .scaledSystemFont(13, weight: .semibold, design: .rounded)
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: streak >= 2 ? "flame.fill" : "book.closed")
                            .foregroundStyle(streak >= 2 ? Theme.accent : Theme.accent2)
                    }
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Theme.card, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.cardStroke))
                }
                .buttonStyle(.plain)
                .fixedSize()
                .accessibilityIdentifier("journalButton")
                .accessibilityLabel(streak >= 2
                    ? (model.languageCode == "zh" ? "骑行日志,连续 \(streak) 天" : "Ride Log, \(streak)-day streak")
                    : (model.languageCode == "zh" ? "骑行日志" : "Ride Log"))

                Button(action: { model.screen = .lists }) {
                    Label {
                        Text(model.languageCode == "zh" ? "词单" : "Word Lists")
                            .scaledSystemFont(13, weight: .semibold, design: .rounded)
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: "star.fill").foregroundStyle(Theme.gold)
                    }
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Theme.card, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.cardStroke))
                }
                .buttonStyle(.plain)
                .fixedSize()
                .accessibilityIdentifier("wordListsButton")

                Button(action: { model.screen = .stats }) {
                    Label {
                        Text(model.languageCode == "zh" ? "统计" : "Stats")
                            .scaledSystemFont(13, weight: .semibold, design: .rounded)
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: "chart.bar.fill").foregroundStyle(Theme.accent2)
                    }
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Theme.card, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.cardStroke))
                }
                .buttonStyle(.plain)
                .fixedSize()
                .accessibilityIdentifier("statsButton")

                // Weak-words cram: shown only once enough words have been reviewed to
                // make it worthwhile. Starts a run directly (a cram, not a screen).
                if model.weakWordsPoolCount >= AppModel.weakWordsMinimum {
                    Button(action: { model.startWeakWords() }) {
                        Label {
                            Text(model.languageCode == "zh" ? "弱词练习" : "Weak words")
                                .scaledSystemFont(13, weight: .semibold, design: .rounded)
                                .lineLimit(1)
                        } icon: {
                            Image(systemName: "bolt.fill").foregroundStyle(Theme.accent)
                        }
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Theme.card, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.cardStroke))
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .accessibilityIdentifier("weakWordsButton")
                    // Spoken, never shown — which is exactly why the wrong number here
                    // survived every headless render. Composed by the model, so this call
                    // site has no number to get wrong.
                    .accessibilityLabel(model.weakWordsButtonLabel(zh: model.languageCode == "zh"))
                }

                Button(action: { model.screen = .settings }) {
                    Label(model.languageCode == "zh" ? "设置" : "Settings", systemImage: "gearshape")
                        .scaledSystemFont(13, weight: .semibold, design: .rounded)
                        .lineLimit(1)
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Theme.card, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.cardStroke))
                }
                .buttonStyle(.plain)
                .fixedSize()
                .accessibilityIdentifier("settingsButton")

                Button(action: { model.screen = .about }) {
                    Label(model.languageCode == "zh" ? "关于与致谢" : "About & Credits", systemImage: "info.circle")
                        .scaledSystemFont(12, weight: .medium)
                        .lineLimit(1)
                        .foregroundStyle(Theme.dim)
                }
                .buttonStyle(.plain)
                .fixedSize()
            }
            .padding(.top, -8)

            Spacer()
        }
        .padding(isPhoneIdiom ? 20 : 40)
        .background {
            if !Screenshotter.isCapturing {
                KeyCaptureView(
                    onKey: { _ in },
                    onCommand: { command in
                        if command == .returnKey || command == .space { model.startGame() }
                    },
                    suppressSoftwareKeyboard: true
                )
            }
        }
    }

    /// The mode picker's entries, in the order they were added to the app.
    private var modeOptions: [(mode: GameMode, label: String)] {
        let zh = model.languageCode == "zh"
        return [
            (.journey, zh ? "环游" : "Journey"),
            (.timeAttack, zh ? "限时" : "Time"),
            (.practice, zh ? "练习" : "Practice"),
            (.conjugation, zh ? "变形" : "Verbs"),
            (.sentence, zh ? "例句" : "Sentence"),
            (.dictation, zh ? "听写" : "Listen"),
        ]
    }

    private var streak: Int { model.journal.streakDays() }

    /// Whether to draw the strip in its arrived state. See `routePreview`.
    private var arrived: Bool { model.hasArrivedAtKyoto }

    /// One sentence for the route strip — the VoiceOver label, and the strip itself at
    /// accessibility text sizes.
    private var routeLabel: String {
        let zh = model.languageCode == "zh"
        let base = zh ? "路线:东京 · 富士 · 名古屋 · 京都"
                      : "Route: Tokyo, Fuji, Nagoya, Kyoto"
        guard arrived else { return base }
        return base + (zh ? " —— 东海道已走完,已抵达京都。查看路线。"
                          : " — Tōkaidō complete, Kyōto reached. View routes.")
    }

    /// The four-stop strip, and after Kyōto the one place outside Settings that reaches the road
    /// screen.
    ///
    /// ## Why this element changed in v1.30, and what the change is careful not to be
    ///
    /// The strip has always drawn the free road as a little map. It was **static**: it showed
    /// Kyōto as the last stop whether the rider was at 0 m or at 25 km, so the app drew somebody a
    /// map and never marked where they were on it. A rider finished the Tōkaidō — 48 rides at the
    /// default level — and nothing anywhere said so. That was a hole in the product, not in the
    /// funnel, and marking arrival would be worth doing if nothing were for sale.
    ///
    /// It is also, unavoidably, a second entrance to the screen that carries the purchase, and
    /// **the honest thing is to call it that rather than redefine the word.** The placement
    /// discipline this project adopted (one row in Settings; no modal, no badge, no post-ride
    /// solicitation, no recurring reminder, far from v1.27's rating prompt) is kept in every
    /// clause except that there are now two entrances instead of one — and §I/§K are amended to
    /// say so, timestamped, **before** the observation window opens. Shipping this on day 45
    /// instead would have voided the pre-registration.
    ///
    /// Three deliberate limits:
    ///
    ///  * **Nothing changes before Kyōto.** A rider short of arrival sees byte-for-byte what
    ///    v1.29 showed, and the strip is not tappable. The entrance exists only for the population
    ///    the thing being sold is any use to.
    ///  * **The wording reports a state, never the product.** "Tōkaidō complete · Kyōto reached"
    ///    and "view routes" — not "the road continues west", which was the first draft and which
    ///    is solicitation wearing a state's clothes. The destination is the route screen; that the
    ///    road west has a price on it is a property of that screen.
    ///  * **No price, no badge, no count, no modal.** The strip does not know the SKU exists.
    private var routePreview: some View {
        let strip = routeStrip
        return Group {
            if arrived {
                Button(action: model.showRoad) {
                    VStack(spacing: 8) {
                        strip
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption).foregroundStyle(Theme.gold)
                            Text(model.languageCode == "zh" ? "东海道 走完 · 京都到达" : "Tōkaidō complete · Kyōto reached")
                                .font(.caption).foregroundStyle(Theme.dim)
                            Image(systemName: "chevron.right")
                                .font(.caption2).foregroundStyle(Theme.dim.opacity(0.7))
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("menuRouteEntrance")
                .onAppear { model.recordMenuRouteEntranceAppeared() }
            } else {
                strip
            }
        }
    }

    private var routeStrip: some View {
        let stops: [(String, String)] = [("🗼", "Tokyo"), ("🗻", "Fuji"), ("🏯", "Nagoya"), ("⛩️", "Kyoto")]
        return HStack(spacing: 0) {
            ForEach(Array(stops.enumerated()), id: \.offset) { index, stop in
                VStack(spacing: 6) {
                    Text(stop.0).scaledSystemFont(isPhoneIdiom ? 24 : 30, relativeTo: .largeTitle)
                    Text(stop.1).font(.caption2).foregroundStyle(Theme.dim)
                }
                if index < stops.count - 1 {
                    Rectangle()
                        .fill(arrived ? Theme.gold.opacity(0.55) : Theme.cardStroke)
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                        .overlay(alignment: .center) {
                            Image(systemName: "bicycle").font(.caption).foregroundStyle(Theme.gold)
                        }
                }
            }
        }
    }

    /// Deck size + what is actually due, both kinds. See the call site for why.
    private var dueLine: String {
        let zh = model.languageCode == "zh"
        let conj = model.conjugationDueCount
        let head = zh ? "\(model.wordPoolLabel) 词库:\(model.wordsAvailableAtLevel) 词 · 待复习:\(model.dueReviewCount) 词"
                      : "\(model.wordPoolLabel) deck: \(model.wordsAvailableAtLevel) words · "
                        + "Due: \(countLabel(model.dueReviewCount, "word"))"
        guard conj > 0 else { return head }
        return head + (zh ? " + \(conj) 变形" : " + \(countLabel(conj, "conjugation"))")
    }

    private var footer: some View {
        VStack(spacing: 4) {
            // "Due for review" used to mean vocabulary only while the app badge (v1.14 §B)
            // means both, so a learner with 3 conjugations due read a badge of 3 and a menu
            // saying 0. The line now names what it counts, and adds conjugations when there
            // are any — silent on zero, so the common case stays short.
            Text(dueLine)
                .font(.callout).foregroundStyle(Theme.dim)
            Text("Dictionary data: JMdict/Mozc · CC BY-SA / BSD")
                .font(.caption2).foregroundStyle(Theme.dim.opacity(0.6))
        }
    }
}

extension View {
    /// Menu controls are fixed-width on the roomy mac/iPad layout, but stretch
    /// to the panel's width on the narrow iPhone screen.
    @MainActor
    @ViewBuilder
    fileprivate func menuControlWidth(_ width: CGFloat) -> some View {
        if isPhoneIdiom {
            frame(maxWidth: .infinity)
        } else {
            frame(width: width)
        }
    }
}

/// A centered, wrapping row layout for the menu's footer chips: lays items out
/// left-to-right and wraps to a new centered row when the width runs out, so a
/// growing number of chips (Ride Log / Saved / Settings / About) never overflows
/// or forces their labels onto two lines on a narrow iPhone.
struct MenuFlow: Layout {
    var spacing: CGFloat = 12
    var rowSpacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let rows = rows(maxWidth: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + rowSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var y = bounds.minY
        for row in rows(maxWidth: bounds.width, subviews: subviews) {
            var x = bounds.minX + (bounds.width - row.width) / 2   // center each row
            for i in row.indices {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + rowSpacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func rows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for (i, sub) in subviews.enumerated() {
            let size = sub.sizeThatFits(.unspecified)
            let advance = (row.indices.isEmpty ? 0 : spacing) + size.width
            if !row.indices.isEmpty, row.width + advance > maxWidth {
                rows.append(row)
                row = Row()
            }
            row.indices.append(i)
            row.width += (row.indices.count == 1 ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
