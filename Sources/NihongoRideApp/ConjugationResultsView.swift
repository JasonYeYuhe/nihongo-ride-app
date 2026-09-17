import SwiftUI
import SceneryKit

/// Results for a verb-conjugation drill (v1.6). Lightweight — no distance and no "review
/// these" list on this screen: since v1.8 the drill DOES record to the separate
/// conjugation SRS, but due forms are surfaced from the menu's "Review N due" entry, not
/// here. "Practice again" re-enters the drill (startGame dispatches to startConjugation
/// while the mode is .conjugation).
struct ConjugationResultsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    private var zh: Bool { model.languageCode == "zh" }

    var body: some View {
        ZStack {
            // Same arrival sky as the ride results — the drill rides the same road.
            // (v1.12 §D2; the Codex review caught that this view is NOT ResultsView.)
            RideArrivalBackdrop(stage: model.rideStage)
            // See ResultsView / scrollsWhenTall. (v1.15 §A.)
            scrollsWhenTall { content }
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
            if let summary {
                VStack(spacing: 20) {
                    // Inside the panel for the same reason as ResultsView's title.
                    if summary.typedNothing {
                        // Nothing answered is not a completed drill. It showed "Drill complete!",
                        // the ✓ and "STEADY — Steady pace, accurate forms." for 0/12 (simulator
                        // pass 2026-09-17, defect 5, `B_mode-conjugation_afterEnd_p0_en_large.png`):
                        // this grade has no "answered anything" guard, and 0/0 accuracy is 1.
                        // The ride's rule, asked of prompts (`ConjugationSummary.typedNothing`).
                        // No mark, no grade; the buttons below do not change. (v1.33 §B R)
                        Text(zh ? "第一题还没答,这组就结束了" : "The drill ended before the first answer")
                            .scaledSystemFont(isPhoneIdiom ? 30 : 36, weight: .heavy, design: .rounded, relativeTo: .largeTitle)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                    } else {
                        Text("✓").scaledSystemFont(50, weight: .bold, relativeTo: .largeTitle).foregroundStyle(Theme.done)
                            .accessibilityHidden(true)
                        Text(zh ? "完成!" : "Drill complete!")
                            .scaledSystemFont(isPhoneIdiom ? 30 : 36, weight: .heavy, design: .rounded, relativeTo: .largeTitle)
                            .foregroundStyle(.white)
                        grade(for: summary)
                    }
                    scoreGrid(summary)
                }
                .arrivalPanel(compact: isPhoneIdiom)
            }

            adaptiveStack(horizontal: !isPhoneIdiom && !typeSize.wantsStackedButtons, spacing: isPhoneIdiom ? 12 : 16) {
                Button(action: model.startGame) {
                    Text(zh ? "再练一组 ▶" : "Practice again ▶")
                        .scaledSystemFont(18, weight: .bold, design: .rounded)
                        .ctaLabel(minWidth: 200, minHeight: 50)
                }
                .buttonStyle(.plain)
                .background(Theme.accent, in: Capsule())
                .foregroundStyle(.white)
                .accessibilityIdentifier("conjugationAgainButton")

                Button(action: model.backToMenu) {
                    Text(zh ? "回到主页" : "Menu")
                        .scaledSystemFont(18, weight: .semibold, design: .rounded)
                        .ctaLabel(minWidth: 140, minHeight: 50)
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
        // Nothing answered has no accuracy (0/0 is defined as 1, which printed "100%"). "—" is a
        // drawing, so VoiceOver gets words. Same rule as ResultsView's tile. (v1.33 §B R)
        let accuracy: (value: String, spoken: String?) = s.typedNothing
            ? ("—", zh ? "没有输入" : "Nothing typed")
            : ("\(Int(s.accuracy * 100))%", nil)
        let cards: [(icon: String, tint: Color, value: String, label: String, spoken: String?)] = [
            ("star.fill", Theme.gold, "\(s.score)", zh ? "得分" : "Score", nil),
            ("flame.fill", Theme.accent, "×\(s.maxCombo)", zh ? "最高连击" : "Best combo", "\(s.maxCombo)"),
            ("checkmark.circle.fill", Theme.done, "\(s.promptsCompleted)/\(s.promptCount)",
             zh ? "完成" : "Completed",
             zh ? "\(s.promptsCompleted) / \(s.promptCount)" : "\(s.promptsCompleted) of \(s.promptCount)"),
            ("scope", .white, accuracy.value, zh ? "准确率" : "Accuracy", accuracy.spoken),
        ]
        // Chosen by AVAILABLE WIDTH, not by device idiom. Four 150pt tiles plus their panel
        // padding need ~950pt, and `isPhoneIdiom` calls every iPad roomy — so on an iPad mini
        // in portrait (744pt) the first and last tiles ran off both edges of the screen, at the
        // DEFAULT text size. ViewThatFits takes the single row when it genuinely fits and the
        // two-column grid otherwise, which also covers Slide Over and the accessibility sizes.
        // (v1.14 §D, after the Codex review; reproduced on the iPad mini simulator.)
        return Group {
            // One column at the accessibility sizes, which this grid used to fall back to two
            // columns for: at AX5 that broke the captions ("Best / com…") and set tiles of
            // different heights side by side out of line (simulator pass 2026-09-17 on a 402pt
            // iPhone 17 Pro, defects 1 and 26, `A_conj-results_en_ax5.png`; the ride results
            // share the caption and the defect). See ResultsView.scoreGrid for the widths.
            // (v1.33 §B R)
            if typeSize.isAccessibilitySize {
                VStack(spacing: 12) {
                    ForEach(cards.indices, id: \.self) { i in card(cards[i], flexible: true) }
                }
                .frame(maxWidth: 420)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) { ForEach(cards.indices, id: \.self) { i in card(cards[i], flexible: false) } }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(cards.indices, id: \.self) { i in card(cards[i], flexible: true) }
                    }
                    .frame(maxWidth: 420)
                }
            }
        }
    }

    private func card(_ c: (icon: String, tint: Color, value: String, label: String, spoken: String?),
                      flexible: Bool) -> some View {
        VStack(spacing: 8) {
            Image(systemName: c.icon).font(.title2).foregroundStyle(c.tint)
            Text(c.value).scaledSystemFont(28, weight: .bold, design: .rounded, relativeTo: .largeTitle)
                .foregroundStyle(.white).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.4)
            Text(c.label).font(.caption).foregroundStyle(Theme.dim)
                .lineLimit(2).multilineTextAlignment(.center)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: flexible ? .infinity : nil)
        // See ResultsView.scoreCard: a fixed height lets accessibility-sized contents spill
        // out of the panel and overlap the row below. (v1.14 §C.)
        .frame(width: flexible ? nil : 150)
        .frame(minHeight: flexible ? 104 : 120)
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
