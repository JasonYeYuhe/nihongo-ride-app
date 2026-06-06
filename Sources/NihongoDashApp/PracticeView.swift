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
                if model.practicePassages {
                    longPassage(session)
                    translation(session).padding(.top, 18)
                } else {
                    passage(session)
                }
                romajiGuide(session).padding(.top, 28)
                Spacer()
                statsRow(session)
            }
            .padding(44)
        }
        .background {
            if !Screenshotter.isCapturing {
                KeyCaptureView(
                    onKey: { character in _ = session.input(character) },
                    onCommand: { command in if command == .escape { model.finishGame() } }
                )
            }
        }
        .onAppear { startedAt = Date(); now = Date() }
        .onReceive(ticker) { now = $0 }
        .onChange(of: session.isFinished) { _, finished in if finished { model.finishGame() } }
    }

    private func topBar(_ s: GameSession) -> some View {
        HStack {
            Text("PRACTICE · \(s.currentLevelLabel)")
                .font(.system(size: 12, weight: .bold)).tracking(3)
                .foregroundStyle(ink.opacity(0.4))
            Spacer()
            Text(model.languageCode == "zh" ? "Esc 结束" : "Esc to finish")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(ink.opacity(0.35))
        }
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
            .font(.system(size: 46, weight: .medium, design: .serif))
            .lineSpacing(20)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: 720, alignment: .leading)
    }

    private var space: Text { Text("　") }   // ideographic space between words

    /// Long-passage rendering: the current sentence as a single flowing block,
    /// with per-character typed/upcoming styling and a coral caret.
    private func longPassage(_ s: GameSession) -> some View {
        let kana = Array(s.currentKana ?? "")
        let done = s.completedKanaCount
        var text = Text("")
        for (index, character) in kana.enumerated() {
            let run = Text(String(character))
            if index < done {
                text = text + run.foregroundStyle(ink.opacity(0.20))
            } else if index == done {
                text = text + run.foregroundStyle(accent).underline(true, color: accent)
            } else {
                text = text + run.foregroundStyle(ink.opacity(0.85))
            }
        }
        return text
            .font(.system(size: 36, weight: .medium, design: .serif))
            .lineSpacing(18)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: 760, alignment: .leading)
    }

    private func translation(_ s: GameSession) -> some View {
        Text(s.currentGloss ?? "")
            .font(.system(size: 15, weight: .regular, design: .serif))
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
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
            Text(s.currentRomaji ?? "")
                .foregroundStyle(ink.opacity(0.32))
                .font(.system(size: 15, weight: .regular, design: .monospaced))
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
            Text(value).font(.system(size: 19, weight: .semibold, design: .monospaced))
            Text(label).font(.system(size: 10, weight: .bold)).tracking(2)
        }
    }
}
