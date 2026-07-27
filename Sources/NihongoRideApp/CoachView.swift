import SwiftUI
import VocabKit
import DiagnosticsKit
import RomajiKana

/// The coach: what this run kept getting wrong, why, and — when repetition actually helps —
/// a drill built from words the learner already knows.
///
/// Everything on this screen is deterministic. The diagnosis comes from the run's own refused
/// keystrokes, the rule is authored text verified against the real matcher in
/// `CoachContentTests`, and the replay is the learner's own keystroke. No model is consulted;
/// if the optional phrasing layer ever ships it appears BELOW this, labeled, and adds nothing
/// the screen depends on.
struct CoachView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    private var zh: Bool { model.languageCode == "zh" }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            scrollsWhenTall { content }
        }
        .background {
            if !Screenshotter.isCapturing {
                KeyCaptureView(onKey: { _ in },
                               onCommand: { if $0 == .escape { model.backToMenu() } },
                               suppressSoftwareKeyboard: true)
            }
        }
    }

    private var content: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)

            if let diagnosis = model.coachHeadline,
               let advice = CoachContent.advice(for: diagnosis.pattern, zh: zh) {
                VStack(spacing: 18) {
                    header(advice)
                    if let replay = MistakeReplay(diagnosis.example) { replayCard(replay) }
                    Text(advice.rule)
                        .scaledSystemFont(15, design: .rounded)
                        .foregroundStyle(Theme.dim)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    evidence(diagnosis)
                }
                .padding(24)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Theme.cardStroke))
                .frame(maxWidth: 560)

                if advice.drillHelps {
                    drillButton(for: diagnosis.pattern)
                }
            } else {
                // Reached only if the run stops being diagnosable between the results screen
                // and here. Saying nothing is the honest output.
                Text(zh ? "这一程没有发现固定的输入问题。" : "Nothing consistent to flag from that ride.")
                    .scaledSystemFont(16, design: .rounded)
                    .foregroundStyle(Theme.dim)
            }

            Button(action: model.backToMenu) {
                Text(zh ? "回到主页" : "Menu")
                    .scaledSystemFont(18, weight: .semibold, design: .rounded)
                    .ctaLabel(minWidth: 140, minHeight: 50)
            }
            .buttonStyle(.plain)
            .background(Theme.card, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.cardStroke))
            .foregroundStyle(.white)
            .accessibilityIdentifier("coachMenuButton")

            Spacer()
        }
        .padding(isPhoneIdiom ? 24 : 40)
    }

    private func header(_ advice: CoachAdvice) -> some View {
        VStack(spacing: 6) {
            Text(zh ? "打字教练" : "Typing coach")
                .scaledSystemFont(12, weight: .black, design: .rounded).tracking(3)
                .foregroundStyle(Theme.accent2)
            Text(advice.title)
                .scaledSystemFont(isPhoneIdiom ? 22 : 26, weight: .heavy, design: .rounded,
                                  relativeTo: .title)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The learner's own keystroke, at the exact character. This is the part that a count of
    /// mistakes can never do: it points.
    private func replayCard(_ replay: MistakeReplay) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(Array(replay.target.enumerated()), id: \.offset) { i, kana in
                    Text(String(kana))
                        .scaledSystemFont(isPhoneIdiom ? 28 : 34, weight: .bold, relativeTo: .title)
                        .foregroundStyle(i == replay.index ? Theme.accent : .white)
                        .padding(.horizontal, 2)
                        .background(i == replay.index
                                    ? Theme.accent.opacity(0.15) : .clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .accessibilityElement()
            .accessibilityLabel(zh ? "\(replay.target),问题出在第 \(replay.index + 1) 个假名 \(String(replay.kana))"
                                   : "\(replay.target), the trouble is at character \(replay.index + 1), \(String(replay.kana))")

            HStack(spacing: 14) {
                keyPill(typed: true, text: replay.typedPrefix + String(replay.rejected))
                Text("→").foregroundStyle(Theme.dim).accessibilityHidden(true)
                keyPill(typed: false, text: correctSpelling(for: replay))
            }
            .scaledSystemFont(14, design: .monospaced)
        }
    }

    /// What the learner should have typed.
    ///
    /// The word's own full romaji when it comes from a vocabulary row — because the
    /// alternative, "the prefix plus whichever key would have been accepted next", renders
    /// as things like `yukk`, and putting a non-word beside the learner's attempt teaches a
    /// spelling that does not exist. Passages have no row, so they fall back to the accepted
    /// key, where the surrounding kana make the point instead.
    private func correctSpelling(for replay: MistakeReplay) -> String {
        if let id = model.coachHeadline?.example.entryID,
           let entry = VocabStore.shared.entry(id: id), !entry.romaji.isEmpty {
            return entry.romaji
        }
        return replay.typedPrefix + (replay.accepted.first.map(String.init) ?? "")
    }

    private func keyPill(typed: Bool, text: String) -> some View {
        Text(text)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(typed ? Theme.accent.opacity(0.18) : Theme.done.opacity(0.18),
                        in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(typed ? Theme.accent : Theme.done)
            .accessibilityLabel(typed ? (zh ? "你打的:\(text)" : "you typed \(text)")
                                      : (zh ? "应该是:\(text)" : "it wanted \(text)"))
    }

    /// How much evidence there is. Shown because "twice, on two words" is a very different
    /// claim from "eleven times", and the learner should be able to judge it themselves.
    private func evidence(_ d: Diagnosis) -> some View {
        Text(zh ? "本程出现 \(d.occurrences) 次,涉及 \(d.distinctWords) 个词。"
                : "\(countLabel(d.occurrences, "time")) this ride, across \(countLabel(d.distinctWords, "word")).")
            .font(.caption).foregroundStyle(Theme.dim.opacity(0.85))
    }

    private func drillButton(for pattern: TypingPattern) -> some View {
        let ids = model.coachDrillIDs(for: pattern)
        return Group {
            if ids.isEmpty {
                // No already-reviewed word exercises this pattern yet. Offering a drill that
                // would be built from unknown words is worse than offering none.
                Text(zh ? "等你多学几个相关的词,这里会出现针对练习。"
                        : "Once you've learned a few words with this in them, a drill appears here.")
                    .font(.caption).foregroundStyle(Theme.dim)
                    .multilineTextAlignment(.center)
            } else {
                Button(action: { model.startCoachDrill(for: pattern) }) {
                    Text(zh ? "练这 \(ids.count) 个词 ▶" : "Drill \(countLabel(ids.count, "word")) ▶")
                        .scaledSystemFont(18, weight: .bold, design: .rounded)
                        .ctaLabel(minWidth: 220, minHeight: 50)
                }
                .buttonStyle(.plain)
                .background(Theme.accent, in: Capsule())
                .foregroundStyle(.white)
                .accessibilityIdentifier("coachDrillButton")
            }
        }
    }
}
