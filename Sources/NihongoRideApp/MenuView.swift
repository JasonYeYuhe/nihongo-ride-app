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
                    .font(.system(size: isPhoneIdiom ? 38 : 60, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text("にほんご ライド")
                    .font(.system(size: isPhoneIdiom ? 16 : 22, weight: .semibold, design: .rounded))
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

            VStack(spacing: 18) {
                HStack(spacing: 12) {
                    Image(systemName: "gamecontroller")
                    Picker("", selection: $model.selectedMode) {
                        Text(model.languageCode == "zh" ? "环游" : "Journey").tag(GameMode.journey)
                        Text(model.languageCode == "zh" ? "限时" : "Time").tag(GameMode.timeAttack)
                        Text(model.languageCode == "zh" ? "练习" : "Practice").tag(GameMode.practice)
                    }
                    .pickerStyle(.segmented)
                    .menuControlWidth(280)
                }
                HStack(spacing: 12) {
                    Image(systemName: "globe")
                    Picker("", selection: $model.languageCode) {
                        Text("English").tag("en")
                        Text("中文").tag("zh")
                    }
                    .pickerStyle(.segmented)
                    .menuControlWidth(220)
                }
                // JLPT level applies to word-stream modes; Practice Passages has its own level picker below.
                let showJLPT = !(model.selectedMode == .practice && model.practicePassages)
                if showJLPT {
                    HStack(spacing: 12) {
                        Image(systemName: "graduationcap")
                        Picker("", selection: $model.selectedLevel) {
                            ForEach(JLPTLevel.allCases, id: \.self) { level in
                                Text(level.label).tag(JLPTLevel?.some(level))
                            }
                            Text(model.languageCode == "zh" ? "混合" : "All").tag(JLPTLevel?.none)
                        }
                        .pickerStyle(.segmented)
                        .menuControlWidth(300)
                    }
                }
                if model.selectedMode == .practice {
                    HStack(spacing: 12) {
                        Image(systemName: "text.alignleft")
                        Picker("", selection: $model.practicePassages) {
                            Text(model.languageCode == "zh" ? "文章" : "Passages").tag(true)
                            Text(model.languageCode == "zh" ? "词流" : "Words").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .menuControlWidth(220)
                    }
                    if model.practicePassages {
                        HStack(spacing: 12) {
                            Image(systemName: "ruler")
                            Picker("", selection: $model.practicePassageLevel) {
                                Text(model.languageCode == "zh" ? "短" : "Short").tag(Passage.Level.easy)
                                Text(model.languageCode == "zh" ? "中" : "Med").tag(Passage.Level.med)
                                Text(model.languageCode == "zh" ? "长" : "Long").tag(Passage.Level.hard)
                            }
                            .pickerStyle(.segmented)
                            .menuControlWidth(220)
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

            Button(action: model.startGame) {
                Text(model.languageCode == "zh" ? "出发 ▶" : "Start ride ▶")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .frame(width: 240, height: 54)
            }
            .buttonStyle(.plain)
            .background(Theme.accent, in: Capsule())
            .foregroundStyle(.white)
            .shadow(color: Theme.accent.opacity(0.5), radius: 16, y: 6)
            .accessibilityIdentifier("startButton")

            footer

            MenuFlow(spacing: 12, rowSpacing: 10) {
                Button(action: { model.screen = .journal }) {
                    Label {
                        Text(model.languageCode == "zh" ? "骑行日志" : "Ride Log")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
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

                if model.savedCount > 0 {
                    Button(action: model.startSavedGame) {
                        Label {
                            Text(model.languageCode == "zh" ? "收藏 \(model.savedCount)" : "Saved \(model.savedCount)")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
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
                    .accessibilityIdentifier("savedDeckButton")
                }

                Button(action: { model.screen = .settings }) {
                    Label(model.languageCode == "zh" ? "设置" : "Settings", systemImage: "gearshape")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
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
                        .font(.system(size: 12, weight: .medium))
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
                    Text(stop.0).font(.system(size: isPhoneIdiom ? 24 : 30))
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
