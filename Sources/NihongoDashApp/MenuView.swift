import SwiftUI
import VocabKit
import GameCore

struct MenuView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 10) {
                Text("Nihongo Dash")
                    .font(.system(size: 60, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text("にほんご ダッシュ")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .tracking(4)
                    .foregroundStyle(Theme.accent)
                Text(model.languageCode == "zh"
                     ? "打字环游日本 · 边骑边学"
                     : "Type your way across Japan")
                    .font(.title3)
                    .foregroundStyle(Theme.dim)
            }

            routePreview
                .frame(maxWidth: 520)
                .padding(.vertical, 8)

            VStack(spacing: 18) {
                HStack(spacing: 12) {
                    Image(systemName: "gamecontroller")
                    Picker("", selection: $model.selectedMode) {
                        Text(model.languageCode == "zh" ? "环游" : "Journey").tag(GameMode.journey)
                        Text(model.languageCode == "zh" ? "限时" : "Time Attack").tag(GameMode.timeAttack)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
                HStack(spacing: 12) {
                    Image(systemName: "globe")
                    Picker("", selection: $model.languageCode) {
                        Text("English").tag("en")
                        Text("中文").tag("zh")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
                HStack(spacing: 12) {
                    Image(systemName: "graduationcap")
                    Picker("", selection: $model.selectedLevel) {
                        ForEach(JLPTLevel.allCases, id: \.self) { level in
                            Text(level.label).tag(JLPTLevel?.some(level))
                        }
                        Text(model.languageCode == "zh" ? "混合" : "All").tag(JLPTLevel?.none)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 300)
                }
                Toggle(isOn: $model.showRomajiHint) {
                    Label(model.languageCode == "zh" ? "显示罗马字提示" : "Show romaji hints",
                          systemImage: "character.cursor.ibeam")
                }
                .toggleStyle(.switch)
                .tint(Theme.accent2)
                .frame(width: 320)
                Toggle(isOn: $model.soundEnabled) {
                    Label(model.languageCode == "zh" ? "音效" : "Sound effects",
                          systemImage: "speaker.wave.2.fill")
                }
                .toggleStyle(.switch)
                .tint(Theme.accent2)
                .frame(width: 320)
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

            footer

            Spacer()
        }
        .padding(40)
        .background {
            if !Screenshotter.isCapturing {
                KeyCaptureView(
                    onKey: { _ in },
                    onCommand: { command in
                        if command == .returnKey || command == .space { model.startGame() }
                    }
                )
            }
        }
    }

    private var routePreview: some View {
        let stops: [(String, String)] = [("🗼", "Tokyo"), ("🗻", "Fuji"), ("🏯", "Nagoya"), ("⛩️", "Kyoto")]
        return HStack(spacing: 0) {
            ForEach(Array(stops.enumerated()), id: \.offset) { index, stop in
                VStack(spacing: 6) {
                    Text(stop.0).font(.system(size: 30))
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
