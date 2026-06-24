import SwiftUI

/// One-time first-launch intro: three short, skippable pages. Shown only to a
/// fresh install (see `AppModel` init). Follows the non-game-screen contract —
/// software keyboard suppressed — and deliberately does NOT request notification
/// permission (reminders stay opt-in from Settings), so it never collides with a
/// system prompt at launch.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    private var zh: Bool { model.languageCode == "zh" }
    @State private var page = 0

    private struct Page: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let body: String
        /// Optional illustrative example shown in a mono pill (e.g. romaji spellings).
        let example: String?
    }

    private var pages: [Page] {
        zh ? [
            Page(icon: "keyboard", title: "随便怎么拼",
                 body: "用罗马音打假名 —— 同一个音多种拼法都认。慢慢来,边骑边学。",
                 example: "し = shi / si      ち = chi / ti"),
            Page(icon: "gamecontroller", title: "三种模式",
                 body: "环游:打字穿越日本,解锁地标。限时:60 秒冲刺。练习:沉浸式文章打字,平静不计分。",
                 example: nil),
            Page(icon: "star.fill", title: "收藏与词单",
                 body: "游戏或结算页点 ★ 收藏生词;长按 ★ 可加入自定义词单,随时回来专项练习。",
                 example: nil),
        ] : [
            Page(icon: "keyboard", title: "Spell it your way",
                 body: "Type kana in romaji — multiple spellings of the same sound are accepted. Take your time; learn as you ride.",
                 example: "し = shi / si      ち = chi / ti"),
            Page(icon: "gamecontroller", title: "Three modes",
                 body: "Journey: type across Japan and unlock landmarks. Time Attack: a 60-second sprint. Practice: calm, score-free passage typing.",
                 example: nil),
            Page(icon: "star.fill", title: "Save words & lists",
                 body: "Tap ★ during a ride or on the results screen to save a word; long-press ★ to add it to your own lists and drill them later.",
                 example: nil),
        ]
    }

    var body: some View {
        let pages = self.pages
        let current = pages[min(page, pages.count - 1)]

        return VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(action: model.finishOnboarding) {
                    Text(zh ? "跳过" : "Skip")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboardingSkipButton")
            }

            Spacer()

            VStack(spacing: 22) {
                Image(systemName: current.icon)
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                Text(current.title)
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(current.body)
                    .font(.title3)
                    .foregroundStyle(Theme.dim)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let example = current.example {
                    Text(example)
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.gold)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Theme.card, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.cardStroke))
                }
            }
            .frame(maxWidth: 420)
            .padding(.horizontal, 28)
            // The whole intro respects Dynamic Type; cap the very largest sizes so
            // three lines of body text still fit the card on a small phone.
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)

            Spacer()

            // Page dots.
            HStack(spacing: 8) {
                ForEach(0..<pages.count, id: \.self) { index in
                    Circle()
                        .fill(index == page ? Theme.accent : Theme.cardStroke)
                        .frame(width: 8, height: 8)
                }
            }
            .accessibilityHidden(true)
            .padding(.bottom, 20)

            Button(action: advance) {
                Text(isLast ? (zh ? "开始 ▶" : "Get started ▶")
                            : (zh ? "下一步" : "Next"))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .frame(width: 220, height: 52)
            }
            .buttonStyle(.plain)
            .background(Theme.accent, in: Capsule())
            .foregroundStyle(.white)
            .shadow(color: Theme.accent.opacity(0.5), radius: 14, y: 5)
            .accessibilityIdentifier("onboardingNextButton")
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if !Screenshotter.isCapturing {
                KeyCaptureView(
                    onKey: { _ in },
                    onCommand: { command in
                        if command == .returnKey || command == .space { advance() }
                    },
                    suppressSoftwareKeyboard: true)
            }
        }
    }

    private var isLast: Bool { page >= pages.count - 1 }

    private func advance() {
        if isLast {
            model.finishOnboarding()
        } else {
            withAnimation(.easeInOut(duration: 0.25)) { page += 1 }
        }
    }
}
