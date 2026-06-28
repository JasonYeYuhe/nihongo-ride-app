import SwiftUI
import GameCore
import VocabKit

/// Distraction-free "Practice" mode — the calm opposite of the ride.
///
/// Aesthetic (per /frontend-design): editorial *washi* zen. Warm paper
/// background, large Mincho-style serif Japanese set as a flowing passage,
/// typed characters fading to ink-gray behind a single coral caret, generous
/// negative space, and a whisper-quiet WPM/accuracy row. No scenery, no combo,
/// no timer.
struct PracticeView: View {
    @Environment(AppModel.self) private var model
    @State private var startedAt = Date()
    @State private var now = Date()
    @State private var passageOpacity: Double = 1.0
    @State private var keyboardUp = false   // iOS: software keyboard visible → compact layout
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private let paper = Color(red: 0.96, green: 0.94, blue: 0.88)
    private let paper2 = Color(red: 0.91, green: 0.88, blue: 0.80)
    private let ink = Color(red: 0.12, green: 0.11, blue: 0.10)
    private let accent = Color(red: 0.85, green: 0.29, blue: 0.26)

    var body: some View {
        if let session = model.session { practice(session) } else { Color.clear }
    }

    @ViewBuilder
    private func practice(_ session: GameSession) -> some View {
        ZStack {
            LinearGradient(colors: [paper, paper2], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar(session)
                Spacer()
                Group {
                    if model.practicePassages {
                        longPassage(session)
                        translation(session).padding(.top, 18)
                    } else {
                        passage(session)
                    }
                    if model.showRomajiHint {
                        romajiGuide(session).padding(.top, 28)
                    }
                }
                .opacity(passageOpacity)
                .animation(.easeOut(duration: 0.18), value: passageOpacity)
                Spacer()
                if model.practicePassages, let total = session.currentKana?.count, total > 0 {
                    passageProgress(done: session.completedKanaCount, total: total)
                        .padding(.bottom, keyboardUp ? 0 : 14)
                }
                if !keyboardUp { statsRow(session) }
            }
            .padding(isPhoneIdiom ? (keyboardUp ? 12 : 20) : (keyboardUp ? 20 : 44))
        }
        .summonKeyboardOnTap()
        .observingKeyboard($keyboardUp)
        .background {
            if !Screenshotter.isCapturing {
                KeyCaptureView(
                    onKey: { character in _ = session.input(character) },
                    onCommand: { command in
                        switch command {
                        case .escape: model.finishGame()
                        case .returnKey, .space: session.skip()       // skip to next passage
                        case .backspace: break
                        }
                    }
                )
            }
        }
        .onAppear { startedAt = Date(); now = Date() }
        .onReceive(ticker) { now = $0 }
        // Brief breath between passages: dim out, then back in
        .onChange(of: session.wordsCompleted) { _, _ in
            passageOpacity = 0.0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { passageOpacity = 1.0 }
        }
        .onChange(of: session.isFinished) { _, finished in if finished { model.finishGame() } }
    }

    private func topBar(_ s: GameSession) -> some View {
        HStack {
            Text("PRACTICE · \(s.currentLevelLabel)")
                .scaledSystemFont(12, weight: .bold).tracking(3)
                .foregroundStyle(ink.opacity(0.4))
            if !model.showRomajiHint {
                Text("BLIND").scaledSystemFont(11, weight: .heavy).tracking(2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(accent, in: Capsule())
                    .padding(.leading, 6)
            }
            Spacer()
            if isTouchDevice {
                // Touch-only iPads need tappable controls — Enter/Esc shortcuts
                // don't exist on the software keyboard.
                HStack(spacing: 10) {
                    topButton(model.languageCode == "zh" ? "下一段 ▸" : "Next ▸",
                              id: "practiceNext") { s.skip() }
                    topButton(model.languageCode == "zh" ? "完成" : "Done",
                              id: "practiceDone") { model.finishGame() }
                }
            } else {
                Text(model.languageCode == "zh" ? "Enter 下一段 · Esc 结束" : "Enter for next · Esc to finish")
                    .scaledSystemFont(12, weight: .medium).foregroundStyle(ink.opacity(0.35))
            }
        }
    }

    private func topButton(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .scaledSystemFont(14, weight: .semibold)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(ink.opacity(0.07), in: Capsule())
                .overlay(Capsule().strokeBorder(ink.opacity(0.12)))
                .foregroundStyle(ink.opacity(0.72))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        // Strip the "▸" glyph VoiceOver would read as "black right-pointing triangle".
        .accessibilityLabel(title.replacingOccurrences(of: "▸", with: "")
            .trimmingCharacters(in: .whitespaces))
    }

    // MARK: Flowing passage

    private func passage(_ s: GameSession) -> some View {
        let words = s.wordList
        let i = s.index
        let lo = max(0, i - 1), hi = min(words.count, i + 9)
        var text = Text("")
        for j in lo ..< hi {
            if j < i {
                text = text + Text(words[j].kana).foregroundStyle(ink.opacity(0.18)) + space
            } else if j == i {
                text = text + currentWord(words[j].kana, done: s.completedKanaCount) + space
            } else {
                text = text + Text(words[j].kana).foregroundStyle(ink.opacity(0.55)) + space
            }
        }
        return text
            .scaledSystemFont(isPhoneIdiom ? 32 : 46, weight: .medium, design: .serif, relativeTo: .largeTitle)
            .lineSpacing(isPhoneIdiom ? 14 : 20)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: 720, alignment: .leading)
    }

    private var space: Text { Text("　") }   // ideographic space between words

    /// Long-passage rendering: the current sentence as a single flowing block,
    /// with per-character typed/upcoming styling and a coral caret. Punctuation
    /// (、。) shows in the display but doesn't count as a typing target.
    private func longPassage(_ s: GameSession) -> some View {
        let display = Array(displayText(for: s))
        let done = s.completedKanaCount
        var text = Text("")
        var typed = 0
        for character in display {
            let str = String(character)
            let run = Text(str)
            if isPunct(character) {
                text = text + run.foregroundStyle(ink.opacity(0.30))     // punctuation is dim, always
            } else if typed < done {
                text = text + run.foregroundStyle(ink.opacity(0.20))
                typed += 1
            } else if typed == done {
                text = text + run.foregroundStyle(accent).underline(true, color: accent)
                typed += 1
            } else {
                text = text + run.foregroundStyle(ink.opacity(0.85))
                typed += 1
            }
        }
        return text
            .scaledSystemFont(isPhoneIdiom ? 24 : 34, weight: .medium, design: .serif, relativeTo: .largeTitle)
            .lineSpacing(isPhoneIdiom ? 11 : 16)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: 760, alignment: .leading)
    }

    /// True for kana that the engine considers a typing target — hiragana
    /// (U+3041…U+3094), katakana (U+30A1…U+30FA), or the prolonged-sound mark ー.
    /// Allow-list (not deny) so stray punctuation/whitespace can't desync the caret.
    private func isTypingKana(_ c: Character) -> Bool {
        c.unicodeScalars.allSatisfy { s in
            (0x3041...0x3094).contains(s.value) ||
            (0x30A1...0x30FA).contains(s.value) ||
            s.value == 0x30FC
        }
    }
    private func isPunct(_ c: Character) -> Bool { !isTypingKana(c) }

    /// Looks up the original (punctuated) text for the current passage; falls back to kana.
    private func displayText(for s: GameSession) -> String {
        guard let id = s.current?.id, id.hasPrefix("passage-") else { return s.currentKana ?? "" }
        let pid = String(id.dropFirst("passage-".count))
        return PassageStore.shared.passages.first { $0.id == pid }?.displayText ?? (s.currentKana ?? "")
    }

    private func translation(_ s: GameSession) -> some View {
        Text(s.currentGloss ?? "")
            .scaledSystemFont(15, weight: .regular, design: .serif)
            .italic()
            .foregroundStyle(ink.opacity(0.45))
            .frame(maxWidth: 720, alignment: .leading)
    }

    private func currentWord(_ kana: String, done: Int) -> Text {
        var text = Text("")
        for (index, character) in Array(kana).enumerated() {
            let run = Text(String(character))
            if index < done {
                text = text + run.foregroundStyle(ink.opacity(0.18))            // already typed
            } else if index == done {
                text = text + run.foregroundStyle(accent).underline(true, color: accent) // caret
            } else {
                text = text + run.foregroundStyle(ink.opacity(0.92))            // upcoming
            }
        }
        return text
    }

    private func romajiGuide(_ s: GameSession) -> some View {
        VStack(spacing: 6) {
            Text(s.typedRomaji.isEmpty ? " " : s.typedRomaji)
                .foregroundStyle(accent)
                .scaledSystemFont(22, weight: .semibold, design: .monospaced)
            Text(s.currentRomaji ?? "")
                .foregroundStyle(ink.opacity(0.32))
                .scaledSystemFont(15, weight: .regular, design: .monospaced)
                .accessibilityIdentifier("practiceRomaji")
        }
    }

    private func statsRow(_ s: GameSession) -> some View {
        let elapsed = now.timeIntervalSince(startedAt)
        let wpm = (elapsed < 2 || s.correctKeystrokes == 0)
            ? "—"
            : "\(Int((Double(s.correctKeystrokes) / 5.0) / (elapsed / 60)))"
        return HStack(spacing: 34) {
            stat("WPM", wpm)
            stat("ACC", "\(Int(s.accuracy * 100))%")
            stat(model.languageCode == "zh" ? "进度" : "DONE", "\(s.wordsCompleted)/\(s.wordCount)")
        }
        .foregroundStyle(ink.opacity(0.45))
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value).scaledSystemFont(19, weight: .semibold, design: .monospaced)
            Text(label).scaledSystemFont(10, weight: .bold).tracking(2)
        }
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }

    /// A pencil-thin progress line for the current passage. Subtle ink track,
    /// coral fill, growing as you type.
    private func passageProgress(done: Int, total: Int) -> some View {
        let fraction = total > 0 ? CGFloat(done) / CGFloat(total) : 0
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(ink.opacity(0.08)).frame(height: 2)
                Capsule().fill(accent.opacity(0.85))
                    .frame(width: max(2, geo.size.width * fraction), height: 2)
                    .animation(.easeOut(duration: 0.12), value: done)
            }
        }
        .frame(height: 2)
        .frame(maxWidth: 760)
        .accessibilityHidden(true)   // decorative; the DONE stat conveys progress
    }
}
