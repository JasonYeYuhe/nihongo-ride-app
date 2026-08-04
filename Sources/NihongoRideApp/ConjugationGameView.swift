import SwiftUI
import SceneryKit
import GameCore
import RomajiKana

/// The verb-conjugation drill screen (v1.6). A dedicated `.playing` variant driven by
/// ``ConjugationSession`` (which holds no SRS), but it REUSES the same keyboard path as
/// `GameView` — `KeyCaptureView` + `.summonKeyboardOnTap()` + `.observingKeyboard` with
/// the software keyboard NOT suppressed — so the keyboard auto-summons and the touch HUD
/// shows (red line §4 / App Review 2.1a). The prompt shows the dictionary form + the
/// target form's bilingual label; the learner types the conjugated reading.
struct ConjugationGameView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var isPaused = false
    @State private var keyboardUp = false

    var body: some View {
        if let session = model.conjugationSession {
            play(session)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func play(_ session: ConjugationSession) -> some View {
        ZStack {
            ZStack {
                RideBackgroundView(speed: 1.0 + Double(min(session.combo, 12)) * 0.12,
                                   landmarkPhase: session.progress * 4,
                                   stage: model.rideStage)
                // Derived from the stage's ground luminance — see GameView. (v1.12 §D.)
                Color.black.opacity(model.rideStage.palette.textScrim).ignoresSafeArea()

                VStack(spacing: keyboardUp ? 12 : 22) {
                    ConjugationHUD(session: session, language: model.languageCode,
                                   onPause: isTouchDevice ? { isPaused = true } : nil)
                    ConjugationProgressBar(progress: session.progress, language: model.languageCode)
                    Spacer(minLength: 0)
                    ConjugationCard(session: session, language: model.languageCode, compact: keyboardUp)
                    if !keyboardUp {
                        Spacer(minLength: 0).frame(maxHeight: 60)
                        controls
                    }
                }
                .padding(isPhoneIdiom ? (keyboardUp ? 10 : 16) : (keyboardUp ? 14 : 32))
            }
            .blur(radius: isPaused ? 8 : 0)
            .summonKeyboardOnTap()

            if isPaused { pauseOverlay }
        }
        .observingKeyboard($keyboardUp)
        // Cap Dynamic Type on the dense, fixed drill layout (mirrors GameView): it
        // still scales up to one accessibility step, but extreme sizes can't shatter
        // the HUD / card. Large-type layout is device-verified (Gate E).
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .background {
            if !Screenshotter.isCapturing {
                KeyCaptureView(
                    onKey: { character in
                        guard !isPaused else { return }
                        switch session.input(character) {
                        case .completed: Sound.wordComplete()
                        case .rejected: Sound.mistake()
                        case .accepted: Sound.tick()
                        }
                    },
                    onCommand: { command in
                        switch command {
                        case .escape: isPaused.toggle()
                        case .returnKey: if isPaused { isPaused = false }
                        case .space, .backspace: break
                        }
                    }
                )
            }
        }
        .onAppear {
            Sound.enabled = model.soundEnabled
            isPaused = false
            // Defensive: an empty drill (already finished at construction) must not strand.
            if session.isFinished { model.finishConjugation() }
        }
        .onChange(of: session.isFinished) { _, finished in
            if finished { Sound.finish(); model.finishConjugation() }
        }
    }

    private var controls: some View {
        let zh = model.languageCode == "zh"
        return HStack(spacing: 18) {
            if isTouchDevice {
                Label(zh ? "轻点屏幕呼出键盘" : "Tap screen for keyboard", systemImage: "keyboard")
            } else {
                Label(zh ? "Esc 暂停" : "Esc to pause", systemImage: "escape")
            }
            if let session = model.conjugationSession, session.assistance == .off {
                Label(zh ? "提示已关" : "Hints off", systemImage: "eye.slash")
            }
        }
        .font(.callout)
        .foregroundStyle(Theme.dim)
    }

    private var pauseOverlay: some View {
        let zh = model.languageCode == "zh"
        return ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 18) {
                Text(zh ? "暂停" : "Paused")
                    .scaledSystemFont(34, weight: .heavy, design: .rounded, relativeTo: .largeTitle)
                    .foregroundStyle(.white)
                adaptiveStack(horizontal: !isPhoneIdiom && !typeSize.wantsStackedButtons, spacing: 14) {
                    Button(action: { isPaused = false }) {
                        Text(zh ? "继续 ▶" : "Resume ▶")
                            .scaledSystemFont(17, weight: .bold, design: .rounded)
                            .ctaLabel(minWidth: 160, minHeight: 46)
                    }
                    .buttonStyle(.plain)
                    .background(Theme.accent, in: Capsule())
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("resumeButton")

                    Button(action: { isPaused = false; model.finishConjugation() }) {
                        Text(zh ? "结束本程" : "End run")
                            .scaledSystemFont(17, weight: .semibold, design: .rounded)
                            .ctaLabel(minWidth: 140, minHeight: 46)
                    }
                    .buttonStyle(.plain)
                    .background(Theme.card, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.cardStroke))
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("endRunButton")
                }
                if !isTouchDevice {
                    Text(zh ? "Esc / Enter 继续" : "Esc / Enter to resume")
                        .font(.caption).foregroundStyle(Theme.dim)
                }
            }
            .padding(isPhoneIdiom ? 26 : 36)
            .panel(26)
        }
    }
}

// MARK: - HUD (form-label badge + score + combo + progress + accuracy; no distance)

private struct ConjugationHUD: View {
    let session: ConjugationSession
    let language: String
    var onPause: (() -> Void)? = nil

    private var narrow: Bool { isPhoneIdiom }
    private var zh: Bool { language == "zh" }

    var body: some View {
        HStack(spacing: narrow ? 8 : 14) {
            Text(zh ? "变形" : "Conjugate")
                .scaledSystemFont(14, weight: .heavy, design: .rounded)
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Theme.accent2.opacity(0.85), in: Capsule())
                .accessibilityLabel(zh ? "动词变形模式" : "Conjugation mode")
            stat(icon: "star.fill", value: "\(session.score)", tint: Theme.gold, label: zh ? "得分" : "Score")
            stat(icon: "flame.fill",
                 value: session.combo >= 2 ? "×\(session.combo)" : "—",
                 tint: session.combo >= 2 ? Theme.accent : Theme.dim,
                 label: zh ? "连击" : "Combo",
                 spoken: session.combo >= 2 ? "\(session.combo)" : (zh ? "无" : "none"))
            Spacer()
            stat(icon: "checkmark.circle.fill",
                 value: "\(session.promptsCompleted)/\(session.promptCount)", tint: Theme.done,
                 label: zh ? "进度" : "Done",
                 spoken: zh ? "\(session.promptsCompleted) / \(session.promptCount)"
                            : "\(session.promptsCompleted) of \(session.promptCount)")
                .accessibilityIdentifier("hudProgress")
            if !narrow {
                stat(icon: "scope", value: "\(Int(session.accuracy * 100))%", tint: .white,
                     label: zh ? "正确率" : "Accuracy")
            }
            if let onPause {
                Button(action: onPause) {
                    Image(systemName: "pause.fill")
                        .scaledSystemFont(17, weight: .bold)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 34)
                        .background(.black.opacity(0.42), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(zh ? "暂停" : "Pause")
                .accessibilityIdentifier("pauseButton")
            }
        }
        .scaledSystemFont(narrow ? 15 : 17, weight: .semibold, design: .rounded)
    }

    private func stat(icon: String, value: String, tint: Color, label: String, spoken: String? = nil) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(value).foregroundStyle(.white).monospacedDigit()
        }
        .padding(.horizontal, narrow ? 9 : 12).padding(.vertical, 7)
        .background(.black.opacity(0.42), in: Capsule())
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(spoken ?? value)
    }
}

// MARK: - Progress bar

private struct ConjugationProgressBar: View {
    let progress: Double
    var language: String = "en"

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.card).frame(height: 8)
                Capsule()
                    .fill(LinearGradient(colors: [Theme.accent2, Theme.accent],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(8, geo.size.width * progress), height: 8)
                    .animation(.smooth, value: progress)
            }
        }
        .frame(height: 12)
        .accessibilityElement()
        .accessibilityLabel(language == "zh" ? "练习进度" : "Drill progress")
        .accessibilityValue("\(Int(progress * 100))%")
    }
}

// MARK: - Prompt card

private struct ConjugationCard: View {
    let session: ConjugationSession
    let language: String
    var compact: Bool = false

    private var zh: Bool { language == "zh" }

    var body: some View {
        VStack(spacing: compact ? 10 : 18) {
            Text(zh ? "辞書形" : "Dictionary form")
                .scaledSystemFont(compact ? 11 : 13, weight: .semibold, design: .rounded)
                .foregroundStyle(Theme.dim)
                .accessibilityHidden(true)

            Text(session.currentSurface ?? "")
                .scaledSystemFont(compact ? 36 : 56, weight: .bold, relativeTo: .largeTitle)
                .foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.4)
            Text(session.currentDictKana ?? "")
                .scaledSystemFont(compact ? 18 : 24, weight: .semibold, design: .rounded)
                .foregroundStyle(.white.opacity(0.75))
            Text(session.currentGloss ?? "")
                .scaledSystemFont(compact ? 14 : 18, weight: .medium, design: .rounded)
                .foregroundStyle(Theme.dim)
                .lineLimit(1).minimumScaleFactor(0.5)

            // The instruction: produce THIS form.
            Image(systemName: "arrow.down")
                .scaledSystemFont(compact ? 13 : 16, weight: .bold)
                .foregroundStyle(Theme.accent2)
                .accessibilityHidden(true)
            Text(session.currentFormLabel ?? "")
                .scaledSystemFont(compact ? 18 : 24, weight: .heavy, design: .rounded)
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Theme.accent.opacity(0.22), in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.5)))
                .accessibilityLabel(zh ? "目标形:\(session.currentFormLabel ?? "")"
                                       : "Target form: \(session.currentFormLabel ?? "")")

            Divider().background(Theme.cardStroke).frame(maxWidth: compact ? 300 : 360)

            answer
        }
        .frame(maxWidth: 560)
        .padding(compact ? 14 : 24)
        // The card's own backing IS the legibility mechanism — see RidePalette.cardAlpha.
        .background(.black.opacity(RidePalette.cardAlpha), in: RoundedRectangle(cornerRadius: compact ? 20 : 28))
        .overlay(RoundedRectangle(cornerRadius: compact ? 20 : 28).strokeBorder(.white.opacity(0.12)))
        // Read the DICTIONARY reading (not the answer being typed — that would spoil the drill).
        .overlay(alignment: .topLeading) {
            SpeakButton(kana: session.currentDictKana, compact: compact, language: language)
        }
    }

    /// The answer reading. Already-typed kana are always shown (you typed them); upcoming
    /// kana are revealed when hints are on, or shown as dots when hints are off (a recall
    /// drill that still gives length + progress feedback, never a spoiler).
    @ViewBuilder
    private var answer: some View {
        let kana = Array(session.currentKana ?? "")
        let done = session.completedKanaCount
        let hint = session.romajiVisible
        VStack(spacing: compact ? 6 : 10) {
            HStack(spacing: 2) {
                ForEach(Array(kana.enumerated()), id: \.offset) { index, character in
                    let revealed = index < done || hint
                    Text(revealed ? String(character) : "・")
                        .scaledSystemFont(compact ? 26 : 40, weight: .semibold, design: .rounded, relativeTo: .largeTitle)
                        .foregroundStyle(color(index: index, done: done, revealed: revealed))
                        .scaleEffect(index == done ? 1.12 : 1)
                        .animation(.smooth(duration: 0.15), value: done)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(zh ? "答案" : "Answer")
            .accessibilityValue(hint ? String(kana) : (zh ? "\(kana.count) 个假名" : "\(kana.count) kana"))

            Text(session.typedRomaji.isEmpty ? " " : session.typedRomaji)
                .scaledSystemFont(compact ? 18 : 24, weight: .bold, design: .monospaced)
                .foregroundStyle(Theme.accent2)
                .accessibilityIdentifier("typedRomaji")

            if hint {
                Text("→ \(session.currentRomaji ?? "")")
                    .scaledSystemFont(compact ? 13 : 16, weight: .regular, design: .monospaced)
                    .foregroundStyle(Theme.dim)
                    .accessibilityIdentifier("romajiHint")
                nextKeys
            }
        }
    }

    private func color(index: Int, done: Int, revealed: Bool) -> Color {
        if index < done { return Theme.done }
        if index == done { return Theme.accent }
        return revealed ? .white.opacity(0.85) : Theme.dim.opacity(0.6)
    }

    private var nextKeys: some View {
        let keys = session.expectedNextCharacters.sorted().map(String.init)
        return HStack(spacing: 6) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .scaledSystemFont(compact ? 12 : 14, weight: .bold, design: .monospaced)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Theme.accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(Theme.accent)
            }
        }
        .frame(height: compact ? 22 : 26)
    }
}
