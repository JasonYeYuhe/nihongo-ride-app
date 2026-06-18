import SwiftUI

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
                }
                Toggle(isOn: $model.showRomajiHint) {
                    rowLabel(icon: "character.cursor.ibeam",
                             text: zh ? "显示罗马字提示" : "Show romaji hints")
                }
                .toggleStyle(.switch).tint(Theme.accent2)
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
                        .font(.system(size: 12)).foregroundStyle(Theme.dim)
                    Text(zh
                         ? "数据存于你自己的 iCloud(私有库),仅你可见。"
                         : "Stored in your own private iCloud — visible only to you.")
                        .font(.system(size: 11)).foregroundStyle(Theme.dim.opacity(0.7))
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
                    }
                }
                Text(zh
                     ? "默认关闭。开启后会按未来几天的实际到期数提醒你。"
                     : "Off by default. When on, reminders reflect each day's actual due count.")
                    .font(.system(size: 11)).foregroundStyle(Theme.dim.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
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
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            Button(action: model.backToMenu) {
                Label(zh ? "返回" : "Back", systemImage: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Theme.card, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.cardStroke))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settingsBackButton")
        }
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
                .font(.system(size: 11, weight: .black)).tracking(3)
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
            Text(text).font(.system(size: 15)).foregroundStyle(.white.opacity(0.9))
        } icon: {
            Image(systemName: icon).foregroundStyle(Theme.accent2)
        }
    }
}
