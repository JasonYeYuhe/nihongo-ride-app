import SwiftUI
import GameCore

/// One-time first-launch intro: three short, skippable pages. Shown only to a
/// fresh install (see `AppModel` init). Follows the non-game-screen contract —
/// software keyboard suppressed — and deliberately does NOT request notification
/// permission (reminders stay opt-in from Settings), so it never collides with a
/// system prompt at launch.
///
/// ## The modes page is DERIVED, and that is the fix (v1.32 §F1)
///
/// It used to be a hand-written sentence saying *"Three modes"* and naming Journey, Time Attack
/// and Practice. Six ship. **Verbs, Sentence and Listen were advertised nowhere a new user would
/// look** — not here, and not in the store description, which says the same thing and is frozen
/// for the measurement window (`PLAN-WINDOW` constraint 4). The in-app copy is not frozen, so
/// this is the half of the fix the window permits.
///
/// A copy edit would have drifted again the next time a mode was added — which is precisely what
/// happened between v1.6 (`.conjugation`) and v1.21 (`.dictation`), twice, silently. So the page
/// is composed from `GameMode.allCases`: adding a case is a compile error in
/// `GameMode.onboardingClause`, and `OnboardingModesTests` fails if the page stops naming one.
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

    /// How many modes fit on one intro page.
    ///
    /// **Three, because three is what renders today.** The page body is a centred `Text` with
    /// `.fixedSize(horizontal: false, vertical: true)` and NO enclosing `ScrollView`, so it grows
    /// downward without bound — and `ImageRenderer` cannot lay out or shrink text the way a device
    /// does, so an overflow here is invisible to every test this repo can run (`ScaledFont.swift`
    /// has said so since v1.7; v1.31 found four separate instances of exactly this shape by
    /// running the app). Naming all six on one page would have doubled a body that is already
    /// two lines at the default size. Splitting keeps each page at the density that is known to
    /// work, and a seventh mode adds a page instead of a line.
    static let modesPerPage = 3

    /// The mode pages: `[[.journey, .timeAttack, .practice], [.conjugation, .sentence, .dictation]]`.
    static var modeChunks: [[GameMode]] {
        stride(from: 0, to: GameMode.allCases.count, by: modesPerPage).map { start in
            Array(GameMode.allCases[start..<min(start + modesPerPage, GameMode.allCases.count)])
        }
    }

    /// "Six modes", then "Three more" — every number derived, none typed. A hand-written numeral
    /// in copy is the smallest possible version of the defect this page had.
    static func modesTitle(zh: Bool, chunk: Int) -> String {
        if chunk == 0 {
            let n = GameMode.allCases.count
            return zh ? "\(Self.chineseNumeral(n))种模式" : "\(Self.englishNumeral(n).capitalized) modes"
        }
        let remaining = modeChunks[chunk...].reduce(0) { $0 + $1.count }
        return zh ? "还有\(Self.chineseNumeral(remaining))种" : "\(Self.englishNumeral(remaining).capitalized) more"
    }

    /// One chunk of modes, each with its one clause.
    static func modesBody(zh: Bool, chunk: Int) -> String {
        modeChunks[chunk]
            .map { "\($0.shortLabel(zh: zh))\(zh ? ":" : ": ")\($0.onboardingClause(zh: zh))" }
            .joined(separator: zh ? "。" : ". ") + (zh ? "。" : ".")
    }

    static func englishNumeral(_ n: Int) -> String {
        let words = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]
        return n < words.count ? words[n] : "\(n)"
    }

    static func chineseNumeral(_ n: Int) -> String {
        let words = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
        return n < words.count ? words[n] : "\(n)"
    }

    private static func modePages(zh: Bool) -> [Page] {
        modeChunks.indices.map { index in
            Page(icon: "gamecontroller",
                 title: modesTitle(zh: zh, chunk: index),
                 body: modesBody(zh: zh, chunk: index),
                 example: nil)
        }
    }

    private var pages: [Page] {
        zh ? [
            Page(icon: "keyboard", title: "随便怎么拼",
                 body: "用罗马音打假名 —— 同一个音多种拼法都认。慢慢来,边骑边学。",
                 example: "し = shi / si      ち = chi / ti"),
        ] + Self.modePages(zh: true) + [
            Page(icon: "star.fill", title: "收藏与词单",
                 body: "游戏或结算页点 ★ 收藏生词;长按 ★ 可加入自定义词单,随时回来专项练习。",
                 example: nil),
        ] : [
            Page(icon: "keyboard", title: "Spell it your way",
                 body: "Type kana in romaji — multiple spellings of the same sound are accepted. Take your time; learn as you ride.",
                 example: "し = shi / si      ち = chi / ti"),
        ] + Self.modePages(zh: false) + [
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
                        .scaledSystemFont(14, weight: .semibold)
                        .foregroundStyle(Theme.dim)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboardingSkipButton")
            }

            Spacer()

            VStack(spacing: 22) {
                Image(systemName: current.icon)
                    .scaledSystemFont(56, weight: .semibold, relativeTo: .largeTitle)
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                Text(current.title)
                    .scaledSystemFont(28, weight: .heavy, design: .rounded, relativeTo: .largeTitle)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(current.body)
                    .font(.title3)
                    .foregroundStyle(Theme.dim)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let example = current.example {
                    Text(example)
                        .scaledSystemFont(16, weight: .medium, design: .monospaced)
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
                    .scaledSystemFont(18, weight: .bold, design: .rounded)
                    .ctaLabel(minWidth: 220, minHeight: 52)
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
