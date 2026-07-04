import SwiftUI
import VocabKit
import GameCore

struct MenuView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // iPhone: the stack can outgrow short screens (SE class), so scroll.
        if isPhoneIdiom {
            ScrollView(showsIndicators: false) { content }
        } else {
            content
        }
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

            routePreview
                .frame(maxWidth: 520)
                .padding(.vertical, isPhoneIdiom ? 0 : 8)
                .accessibilityElement()
                .accessibilityLabel(model.languageCode == "zh"
                                    ? "路线:东京 · 富士 · 名古屋 · 京都"
                                    : "Route: Tokyo, Fuji, Nagoya, Kyoto")

            VStack(spacing: 18) {
                HStack(spacing: 12) {
                    Image(systemName: "gamecontroller").accessibilityHidden(true)
                    Picker("", selection: $model.selectedMode) {
                        Text(model.languageCode == "zh" ? "环游" : "Journey").tag(GameMode.journey)
                        Text(model.languageCode == "zh" ? "限时" : "Time").tag(GameMode.timeAttack)
                        Text(model.languageCode == "zh" ? "练习" : "Practice").tag(GameMode.practice)
                        Text(model.languageCode == "zh" ? "变形" : "Verbs").tag(GameMode.conjugation)
                    }
                    .pickerStyle(.segmented)
                    .menuControlWidth(340)
                    .accessibilityLabel(model.languageCode == "zh" ? "游戏模式" : "Game mode")
                }
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
                            let n = model.conjugationDueCount
                            Button(action: model.startConjugationReview) {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .accessibilityHidden(true)
                                    Text(zh ? "复习 \(n) 个到期变形" : "Review \(n) due")
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
                            .accessibilityLabel(zh ? "复习 \(n) 个到期的变形" : "Review \(n) due conjugations")
                        }
                    }
                    .menuControlWidth(340)
                }
                if model.selectedMode == .practice {
                    HStack(spacing: 12) {
                        Image(systemName: "text.alignleft").accessibilityHidden(true)
                        Picker("", selection: $model.practicePassages) {
                            Text(model.languageCode == "zh" ? "文章" : "Passages").tag(true)
                            Text(model.languageCode == "zh" ? "词流" : "Words").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .menuControlWidth(220)
                        .accessibilityLabel(model.languageCode == "zh" ? "练习内容" : "Practice content")
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
                Toggle(isOn: $model.showRomajiHint) {
                    Label(model.languageCode == "zh" ? "显示罗马字提示" : "Show romaji hints",
                          systemImage: "character.cursor.ibeam")
                }
                .toggleStyle(.switch)
                .tint(Theme.accent2)
                .menuControlWidth(320)
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
            let zhLang = model.languageCode == "zh"
            Button(action: model.startGame) {
                Text(isConjugation ? (zhLang ? "开始变形 ▶" : "Start drill ▶")
                                   : (zhLang ? "出发 ▶" : "Start ride ▶"))
                    .scaledSystemFont(20, weight: .bold, design: .rounded)
                    .frame(width: 240, height: 54)
            }
            .buttonStyle(.plain)
            .background(Theme.accent, in: Capsule())
            .foregroundStyle(.white)
            .shadow(color: Theme.accent.opacity(0.5), radius: 16, y: 6)
            .accessibilityIdentifier("startButton")
            .accessibilityLabel(isConjugation ? (zhLang ? "开始动词变形练习" : "Start conjugation drill")
                                              : (zhLang ? "出发,开始骑行" : "Start ride"))
            // Derived live from the pool (never a stale flag): updates as the level
            // changes. With shipped data every level has verbs, so this stays hidden.
            if isConjugation && model.conjugationPoolCount == 0 {
                Text(zhLang ? "该等级暂无可练的动词,换个等级试试。"
                            : "No verbs to drill at this level — try another level.")
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
                    .accessibilityLabel(model.languageCode == "zh"
                        ? "弱词练习,\(model.weakWordsPoolCount) 个薄弱词"
                        : "Weak words drill, \(model.weakWordsPoolCount) words")
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

    private var streak: Int { model.journal.streakDays() }

    private var routePreview: some View {
        let stops: [(String, String)] = [("🗼", "Tokyo"), ("🗻", "Fuji"), ("🏯", "Nagoya"), ("⛩️", "Kyoto")]
        return HStack(spacing: 0) {
            ForEach(Array(stops.enumerated()), id: \.offset) { index, stop in
                VStack(spacing: 6) {
                    Text(stop.0).scaledSystemFont(isPhoneIdiom ? 24 : 30, relativeTo: .largeTitle)
                    Text(stop.1).font(.caption2).foregroundStyle(Theme.dim)
                }
                if index < stops.count - 1 {
                    Rectangle()
                        .fill(Theme.cardStroke)
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                        .overlay(alignment: .center) {
                            Image(systemName: "bicycle").font(.caption).foregroundStyle(Theme.gold)
                        }
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text(model.languageCode == "zh"
                 ? "N5 词库:\(model.totalWordsAvailable) 词 · 待复习:\(model.dueReviewCount)"
                 : "N5 deck: \(model.totalWordsAvailable) words · Due for review: \(model.dueReviewCount)")
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
