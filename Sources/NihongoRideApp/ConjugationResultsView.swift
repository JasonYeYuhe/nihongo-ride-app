import SwiftUI

/// Results for a verb-conjugation drill (v1.6). Lightweight — no distance and no "review
/// these" list on this screen: since v1.8 the drill DOES record to the separate
/// conjugation SRS, but due forms are surfaced from the menu's "Review N due" entry, not
/// here. "Practice again" re-enters the drill (startGame dispatches to startConjugation
/// while the mode is .conjugation).
struct ConjugationResultsView: View {
    @Environment(AppModel.self) private var model
    private var zh: Bool { model.languageCode == "zh" }

    var body: some View {
        Group {
            if isPhoneIdiom { ScrollView(showsIndicators: false) { content } } else { content }
        }
        .background {
            if !Screenshotter.isCapturing {
                KeyCaptureView(
                    onKey: { _ in },
                    onCommand: { command in
                        switch command {
                        case .returnKey, .space: model.startGame()
                        case .escape: model.backToMenu()
                        case .backspace: break
                        }
                    },
                    suppressSoftwareKeyboard: true
                )
            }
        }
    }

    private var content: some View {
        let summary = model.lastConjugationSummary
        return VStack(spacing: 20) {
            Spacer(minLength: 0)
            Text("✓").scaledSystemFont(50, weight: .bold, relativeTo: .largeTitle).foregroundStyle(Theme.done)
                .accessibilityHidden(true)
            Text(zh ? "完成!" : "Drill complete!")
                .scaledSystemFont(isPhoneIdiom ? 30 : 36, weight: .heavy, design: .rounded, relativeTo: .largeTitle)
                .foregroundStyle(.white)

            if let summary {
                grade(for: summary)
                scoreGrid(summary)
            }

            adaptiveStack(horizontal: !isPhoneIdiom, spacing: isPhoneIdiom ? 12 : 16) {
                Button(action: model.startGame) {
                    Text(zh ? "再练一组 ▶" : "Practice again ▶")
                        .scaledSystemFont(18, weight: .bold, design: .rounded)
                        .frame(width: 200, height: 50)
                }
                .buttonStyle(.plain)
                .background(Theme.accent, in: Capsule())
                .foregroundStyle(.white)
                .accessibilityIdentifier("conjugationAgainButton")

                Button(action: model.backToMenu) {
                    Text(zh ? "回到主页" : "Menu")
                        .scaledSystemFont(18, weight: .semibold, design: .rounded)
                        .frame(width: 140, height: 50)
                }
                .buttonStyle(.plain)
                .background(Theme.card, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.cardStroke))
                .foregroundStyle(.white)
                .accessibilityIdentifier("menuButton")
            }
            .padding(.top, 8)
            Spacer()
        }
        .padding(isPhoneIdiom ? 24 : 40)
    }

    private func scoreGrid(_ s: ConjugationSummary) -> some View {
        let cards: [(icon: String, tint: Color, value: String, label: String, spoken: String?)] = [
            ("star.fill", Theme.gold, "\(s.score)", zh ? "得分" : "Score", nil),
            ("flame.fill", Theme.accent, "×\(s.maxCombo)", zh ? "最高连击" : "Best combo", "\(s.maxCombo)"),
            ("checkmark.circle.fill", Theme.done, "\(s.promptsCompleted)/\(s.promptCount)",
             zh ? "完成" : "Completed",
             zh ? "\(s.promptsCompleted) / \(s.promptCount)" : "\(s.promptsCompleted) of \(s.promptCount)"),
            ("scope", .white, "\(Int(s.accuracy * 100))%", zh ? "准确率" : "Accuracy", nil),
        ]
        return Group {
            if isPhoneIdiom {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(cards.indices, id: \.self) { i in card(cards[i]) }
                }
                .frame(maxWidth: 420)
            } else {
                HStack(spacing: 14) { ForEach(cards.indices, id: \.self) { i in card(cards[i]) } }
            }
        }
    }

    private func card(_ c: (icon: String, tint: Color, value: String, label: String, spoken: String?)) -> some View {
        VStack(spacing: 8) {
            Image(systemName: c.icon).font(.title2).foregroundStyle(c.tint)
            Text(c.value).scaledSystemFont(28, weight: .bold, design: .rounded, relativeTo: .largeTitle)
                .foregroundStyle(.white).monospacedDigit()
            Text(c.label).font(.caption).foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: isPhoneIdiom ? .infinity : nil)
        .frame(width: isPhoneIdiom ? nil : 150, height: isPhoneIdiom ? 104 : 120)
        .panel(20)
        .accessibilityElement()
        .accessibilityLabel(c.label)
        .accessibilityValue(c.spoken ?? c.value)
    }

    private func grade(for s: ConjugationSummary) -> some View {
        let (title, tint, line): (String, Color, String) = {
            if s.accuracy >= 0.97 && s.maxCombo >= max(5, s.promptsCompleted - 1) {
                return (zh ? "完美" : "Flawless", Theme.gold,
                        zh ? "变形几乎全对,手感极佳。" : "Nearly every form correct. Pure flow.")
            }
            if s.accuracy >= 0.90 {
                return (zh ? "稳健" : "Steady", Theme.done,
                        zh ? "节奏稳,变形准确。" : "Steady pace, accurate forms.")
            }
            if s.accuracy >= 0.75 {
                return (zh ? "有进步" : "Building", Theme.accent2,
                        zh ? "正在掌握变形规则,继续。" : "You're learning the forms. Keep going.")
            }
            return (zh ? "再练一组" : "Another set", Theme.accent,
                    zh ? "多练几组,变形会越来越自然。" : "A few more sets and the forms will click.")
        }()
        return VStack(spacing: 6) {
            Text(title.uppercased())
                .scaledSystemFont(14, weight: .black, design: .rounded).tracking(4)
                .foregroundStyle(tint)
            Text(line).scaledSystemFont(13).foregroundStyle(Theme.dim)
        }
    }
}
