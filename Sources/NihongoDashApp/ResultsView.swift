import SwiftUI

struct ResultsView: View {
    @Environment(AppModel.self) private var model

    private var zh: Bool { model.languageCode == "zh" }

    var body: some View {
        let summary = model.lastSummary

        VStack(spacing: 26) {
            Spacer()

            Text("🏁")
                .font(.system(size: 60))
            Text(zh ? "到站!" : "You've arrived!")
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)

            if let summary {
                HStack(spacing: 14) {
                    scoreCard(icon: "star.fill", tint: Theme.gold,
                              value: "\(summary.score)", label: zh ? "得分" : "Score")
                    scoreCard(icon: "bicycle", tint: Theme.accent2,
                              value: "\(Int(summary.distanceMeters)) m", label: zh ? "距离" : "Distance")
                    scoreCard(icon: "flame.fill", tint: Theme.accent,
                              value: "×\(summary.maxCombo)", label: zh ? "最高连击" : "Best combo")
                }
                HStack(spacing: 14) {
                    scoreCard(icon: "checkmark.circle.fill", tint: Theme.done,
                              value: "\(summary.wordsCompleted)", label: zh ? "完成词数" : "Words")
                    scoreCard(icon: "scope", tint: .white,
                              value: "\(Int(summary.accuracy * 100))%", label: zh ? "准确率" : "Accuracy")
                    scoreCard(icon: "brain.head.profile", tint: Theme.accent,
                              value: "\(model.dueReviewCount)", label: zh ? "待复习" : "To review")
                }
            }

            HStack(spacing: 16) {
                Button(action: model.startGame) {
                    Text(zh ? "再来一程 ▶" : "Ride again ▶")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .frame(width: 200, height: 50)
                }
                .buttonStyle(.plain)
                .background(Theme.accent, in: Capsule())
                .foregroundStyle(.white)

                Button(action: model.backToMenu) {
                    Text(zh ? "回到主页" : "Menu")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .frame(width: 140, height: 50)
                }
                .buttonStyle(.plain)
                .background(Theme.card, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.cardStroke))
                .foregroundStyle(.white)
            }
            .padding(.top, 8)

            Spacer()
        }
        .padding(40)
        .background(
            KeyCaptureView(
                onKey: { _ in },
                onCommand: { command in
                    switch command {
                    case .returnKey, .space: model.startGame()
                    case .escape: model.backToMenu()
                    case .backspace: break
                    }
                }
            )
        )
    }

    private func scoreCard(icon: String, tint: Color, value: String, label: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title2).foregroundStyle(tint)
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(Theme.dim)
        }
        .frame(width: 150, height: 120)
        .panel(20)
    }
}
