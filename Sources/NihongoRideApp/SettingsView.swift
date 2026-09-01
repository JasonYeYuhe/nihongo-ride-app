import SwiftUI
import GameCore

/// App settings: general preferences (now persisted across launches), iCloud
/// sync, and the opt-in SRS due reminder. Mirrors the menu's quick toggles and
/// adds the v1.2 controls. Follows the non-game-screen contract: software
/// keyboard suppressed, Esc/Back returns to the menu, and the `.id`-swap zIndex
/// rule is handled by RootView.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    private var zh: Bool { model.languageCode == "zh" }

    var body: some View {
        @Bindable var model = model

        let content = VStack(alignment: .leading, spacing: 22) {
            header

            // General preferences.
            settingsCard(title: zh ? "通用" : "General") {
                row(icon: "globe", label: zh ? "界面语言" : "Language") {
                    Picker("", selection: $model.languageCode) {
                        Text("English").tag("en")
                        Text("中文").tag("zh")
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 200)
                    .accessibilityLabel(zh ? "界面语言" : "Language")
                }
                // **The label and the picker share a row only where there is room for both.**
                // On a phone there is not: "Romaji assistance" takes most of the width and the
                // three segments were left with about sixty points each, so the control read
                // "Hints… / Whe… / Off" — and "Whe…" does not tell a learner what the middle
                // option is. Seen on an iPhone 17 Pro at the default text size.
                //
                // The words themselves are NOT shortened, deliberately: they are the same three
                // the menu's copy of this control uses, and the comment there is right that two
                // spellings of one setting reads as two settings. So the layout yields instead.
                if isPhoneIdiom {
                    VStack(alignment: .leading, spacing: 8) {
                        rowLabel(icon: "character.cursor.ibeam",
                                 text: zh ? "罗马字提示" : "Romaji assistance")
                        assistancePicker.frame(maxWidth: .infinity)
                    }
                } else {
                    HStack {
                        rowLabel(icon: "character.cursor.ibeam",
                                 text: zh ? "罗马字提示" : "Romaji assistance")
                        Spacer()
                        assistancePicker.frame(maxWidth: 260)
                    }
                }
                Toggle(isOn: $model.soundEnabled) {
                    rowLabel(icon: "speaker.wave.2.fill",
                             text: zh ? "音效" : "Sound effects")
                }
                .toggleStyle(.switch).tint(Theme.accent2)
            }

            // iCloud sync (hidden until the feature ships in a later version).
            if AppModel.cloudSyncAvailable {
                settingsCard(title: zh ? "iCloud 同步" : "iCloud Sync") {
                    Toggle(isOn: $model.iCloudSyncEnabled) {
                        rowLabel(icon: "icloud",
                                 text: zh ? "同步复习进度与骑行日志" : "Sync review progress & ride log")
                    }
                    .toggleStyle(.switch).tint(Theme.accent2)
                    Text(syncStatusText)
                        .scaledSystemFont(12).foregroundStyle(Theme.dim)
                        .accessibilityLabel(zh ? "同步状态" : "Sync status")
                        .accessibilityValue(syncStatusText)
                    Text(zh
                         ? "数据存于你自己的 iCloud(私有库),仅你可见。"
                         : "Stored in your own private iCloud — visible only to you.")
                        .scaledSystemFont(11).foregroundStyle(Theme.dim.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // SRS due reminder.
            settingsCard(title: zh ? "复习提醒" : "Review Reminder") {
                Toggle(isOn: $model.dueReminderEnabled) {
                    rowLabel(icon: "bell.badge",
                             text: zh ? "每日到期提醒" : "Daily due reminder")
                }
                .toggleStyle(.switch).tint(Theme.accent2)
                if model.dueReminderEnabled {
                    row(icon: "clock", label: zh ? "提醒时间" : "Remind at") {
                        Picker("", selection: $model.dueReminderHour) {
                            ForEach(0..<24, id: \.self) { hour in
                                Text(String(format: "%02d:00", hour)).tag(hour)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 120)
                        .accessibilityLabel(zh ? "提醒时间" : "Reminder time")
                    }
                }
                Text(zh
                     ? "默认关闭。开启后会按未来几天的实际到期数提醒你。"
                     : "Off by default. When on, reminders reflect each day's actual due count.")
                    .scaledSystemFont(11).foregroundStyle(Theme.dim.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Read-aloud (TTS) of the card kana.
            settingsCard(title: zh ? "例句注音" : "Furigana") {
                Toggle(isOn: $model.exampleFurigana) {
                    rowLabel(icon: "textformat.superscript",
                             text: zh ? "在例句汉字上标注读音" : "Show readings above kanji")
                }
                .toggleStyle(.switch)
            }

            settingsCard(title: zh ? "假名朗读" : "Read Aloud") {
                Toggle(isOn: $model.ttsEnabled) {
                    rowLabel(icon: "speaker.wave.2",
                             text: zh ? "卡片上显示朗读按钮" : "Show a read-aloud button on cards")
                }
                .toggleStyle(.switch).tint(Theme.accent2)
                if model.ttsEnabled {
                    row(icon: "gauge.with.dots.needle.50percent", label: zh ? "语速" : "Speed") {
                        Slider(value: $model.ttsRate, in: 0.30...0.65)
                            .frame(maxWidth: 180)
                            .tint(Theme.accent2)
                            .accessibilityLabel(zh ? "朗读语速" : "Read-aloud speed")
                    }
                    if !model.ttsAvailable {
                        Text(zh
                             ? "未检测到日语语音。可在系统「设置 › 辅助功能 › 朗读内容」中下载后使用。"
                             : "No Japanese voice found. Add one in System Settings › Accessibility › Spoken Content.")
                            .scaledSystemFont(11).foregroundStyle(Theme.accent)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text(zh
                     ? "默认关闭。开启后练习卡片上会出现朗读按钮,使用离线日语语音。"
                     : "Off by default. When on, a speaker button appears on the cards, using an offline Japanese voice.")
                    .scaledSystemFont(11).foregroundStyle(Theme.dim.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Stage 1. ONE row, here, and nowhere else in the app.
            //
            // The placement is Codex's discipline adopted whole and it is a design constraint
            // rather than a detail: no modal, no badge, no post-ride solicitation, no recurring
            // reminder, and deliberately far from the rating prompt v1.27 already fires after a
            // completed ride — two asks landing on the same moment would spend the goodwill of
            // one on the other. `PaidRouteRowTests` asserts on the running app that exactly one
            // such row exists and that the results screen has none.
            //
            // The row names the thing and goes to a screen; it does not itself sell. That screen
            // is the product page, and it is what lets the offer be honest to a rider who is
            // still twenty kilometres from this being any use to them.
            settingsCard(title: zh ? "路" : "The Road") {
                Button(action: model.showRoad) {
                    HStack {
                        rowLabel(icon: "map",
                                 text: model.entitlements.isEntitled
                                     ? (zh ? "东海道与西の道" : "The Tōkaidō and the Road West")
                                     : (zh ? "京都之后的路" : "The road past Kyōto"))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .scaledSystemFont(13).foregroundStyle(Theme.dim)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("roadRow")
                .onAppear { model.recordOfferRowAppeared() }
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
                        if command == .escape || command == .returnKey { model.backToMenu() }
                    },
                    suppressSoftwareKeyboard: true
                )
            }
        }
    }

    // MARK: Pieces

    private var header: some View {
        HStack {
            Text(zh ? "设置" : "Settings")
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
            .accessibilityIdentifier("settingsBackButton")
        }
    }

    /// The three options, written once. Both layouts above render THIS — the words are the
    /// setting's identity and a second copy would drift from the menu's.
    private var assistancePicker: some View {
        Picker("", selection: Bindable(model).assistance) {
            Text(zh ? "总是提示" : "Hints on").tag(AssistanceMode.always)
            Text(zh ? "卡住时" : "When stuck").tag(AssistanceMode.afterStruggle)
            Text(zh ? "关闭" : "Off").tag(AssistanceMode.off)
        }
        .pickerStyle(.segmented)
        .accessibilityLabel(zh ? "罗马字提示" : "Romaji assistance")
    }

    private var syncStatusText: String {
        switch model.syncStatus {
        case .off:       return zh ? "已关闭" : "Off"
        case .waiting:   return zh ? "等待同步…" : "Waiting to sync…"
        case .syncing:   return zh ? "同步中…" : "Syncing…"
        case .synced:    return zh ? "已同步" : "Up to date"
        case .noAccount: return zh ? "未登录 iCloud — 请在系统设置登录" : "Not signed in to iCloud"
        case .error(let message): return (zh ? "同步出错:" : "Sync error: ") + message
        }
    }

    private func settingsCard(title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title.uppercased())
                .scaledSystemFont(11, weight: .black).tracking(3)
                .foregroundStyle(Theme.accent)
            content()
        }
        .panel()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(icon: String, label: String, @ViewBuilder _ control: () -> some View) -> some View {
        HStack {
            rowLabel(icon: icon, text: label)
            Spacer()
            control()
        }
    }

    private func rowLabel(icon: String, text: String) -> some View {
        Label {
            Text(text).scaledSystemFont(15).foregroundStyle(.white.opacity(0.9))
        } icon: {
            Image(systemName: icon).foregroundStyle(Theme.accent2)
        }
    }
}
