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
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
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
                Spacer(minLength: 0)
                // The typing target REFLOWS rather than truncating. At the accessibility text
                // sizes this column outgrew its space and SwiftUI resolved that by putting an
                // ellipsis through the characters the learner is supposed to be typing — a
                // typing app hiding the typing target. (v1.16 §D.)
                //
                // Deliberately NOT the ride screen's fix. GameView caps Dynamic Type at
                // accessibility1 because its HUD is a fixed layout that cannot reflow; this is
                // a column of text that can, so capping would deny AX5 users the size they
                // asked for to solve a problem scrolling solves properly.
                //
                // The capture guard is not optional: ImageRenderer draws ScrollView content as
                // blank, so wrapping this unconditionally would silently empty every practice
                // screenshot in the App Store listing. ListsView guards the same way.
                practiceBody(session)
                    .opacity(passageOpacity)
                    .animation(.easeOut(duration: 0.18), value: passageOpacity)
                Spacer(minLength: 0)
                if model.practiceRendersSentences, let total = session.currentKana?.count, total > 0 {
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
                        // Enter is the ADVERTISED skip (the hint says "Enter for next"; the
                        // touch buttons say Next/Done). Space used to skip too, silently: a
                        // learner pausing mid-passage who tapped space out of habit lost the
                        // whole passage with no undo and no hint that space did that. Space is
                        // never a typing key here (kana targets are punctuation-free), so the
                        // honest behaviour is to ignore it. (v1.15 §K.)
                        case .returnKey: session.skip()               // skip to next passage
                        case .space, .backspace: break
                        }
                    }
                )
            }
        }
        .onAppear { startedAt = Date(); now = Date() }
        // Backgrounding makes a pending offer stale: the learner had all the time they wanted
        // to think, so coming back to a "Stuck?" button from before the interruption is the
        // app claiming to know something it no longer knows. (v1.16 §A.)
        .onChange(of: scenePhase) { _, phase in
            // The RunClock measures RIDDEN time, not wall clock, and the passage screen was the
            // one run screen that never told it when the riding stopped — so a learner who put
            // the app down mid-passage came back to a Ride Log row that had been counting the
            // whole time, with the WPM diluted to match. (v1.23 §B.)
            phase == .active ? model.resumeRunClock() : model.pauseRunClock()
            if phase != .active { model.session?.resetStruggle() }
        }
        .onReceive(ticker) { now = $0 }
        // Brief breath between passages: dim out, then back in
        .onChange(of: session.wordsCompleted) { _, _ in
            passageOpacity = 0.0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { passageOpacity = 1.0 }
        }
        .onChange(of: session.isFinished) { _, finished in if finished { model.finishGame() } }
    }

    /// The passage, its translation and the romaji guide — scrollable, and never truncated.
    @ViewBuilder
    private func practiceBody(_ session: GameSession) -> some View {
        let content = VStack(spacing: 0) {
            if model.practiceRendersSentences {
                // The learner's own sentence, in their own kanji, with the readings the app
                // worked out set above it — and the typing line below is the reading. Both are
                // on screen at once on purpose: Practice always shows its target, and here the
                // source is the thing they pasted and the target is what it says.
                if let tokens = session.currentExampleTokens, !tokens.isEmpty {
                    FuriganaText(tokens: tokens, size: isPhoneIdiom ? 20 : 26,
                                 color: ink.opacity(0.75))
                        .frame(maxWidth: 760, alignment: .leading)
                        .padding(.bottom, 16)
                        .accessibilityIdentifier("practiceSourceFurigana")
                }
                longPassage(session)
                // A bundled passage has a translation; a text the learner pasted does not, and
                // an empty italic line where one used to be reads as a missing translation
                // rather than as an absent one.
                if !(session.currentGloss ?? "").isEmpty {
                    translation(session).padding(.top, 18)
                }
            } else {
                passage(session)
            }
            if session.romajiVisible {
                romajiGuide(session).padding(.top, 28)
            } else if session.assistanceOffered {
                // Tap gesture, not a Button — see the note on the same control in GameView:
                // a focusable control on a key-capture screen can steal first responder.
                // The paper theme is light, so the offer uses the ink colour rather than the
                // coral accent, which does not carry enough contrast at this size.
                Label(model.languageCode == "zh" ? "卡住了?看提示" : "Stuck? Show hint",
                      systemImage: "lightbulb")
                    .scaledSystemFont(14, weight: .semibold)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(ink.opacity(0.06), in: Capsule())
                    .overlay(Capsule().strokeBorder(ink.opacity(0.25)))
                    .foregroundStyle(ink.opacity(0.85))
                    .contentShape(Capsule())
                    .onTapGesture { session.revealHint() }
                    .padding(.top, 28)
                    .accessibilityElement()
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("practiceAssistanceOffer")
                    .accessibilityLabel(model.languageCode == "zh"
                                        ? "看提示。这一条会计为需要复习"
                                        : "Show the hint. This will count as needing review")
            }
        }
        // Without this the Text still truncates inside the ScrollView instead of growing.
        .fixedSize(horizontal: false, vertical: true)

        if Screenshotter.isCapturing {
            content
        } else {
            ScrollView(.vertical, showsIndicators: false) { content }
        }
    }

    /// The label, the hints-off badge, and the controls.
    ///
    /// ⚠️ **At the accessibility sizes this is two rows: Next/Done first, the label and badge
    /// under them.** Measured with CoreText for a 393pt phone at AX5, 2026-09-17 (v1.33 scan
    /// finding #24): Next ▸ and Done cannot shrink and take 300pt; "PRACTICE · LONG" is 354 and
    /// the BLIND capsule 135, against 369 with the keyboard up — 797 on one line. The label's 0.5
    /// floor could not absorb that, so on a 402pt iPhone 17 Pro it collapsed to "PRACT…" (simulator
    /// pass #8) and, with hints off, BLIND had nowhere to go. On their own row the label and badge
    /// have the whole width: with the 8pt gap they need 497, which the label absorbs at ×0.64,
    /// inside its floor, and the Chinese row (318) does not shrink at all. Controls first because
    /// they are what the learner needs to reach; the label is decoration, which is also why it is
    /// the part that yields.
    ///
    /// Below the accessibility sizes the bar is one row, exactly as before. (v1.33 §B L.)
    @ViewBuilder
    private func topBar(_ s: GameSession) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Spacer(minLength: 0)
                    topControls(s)
                }
                HStack {
                    practiceLabel(s)
                    hintsOffBadge
                    Spacer(minLength: 0)
                }
            }
        } else {
            HStack {
                practiceLabel(s)
                hintsOffBadge
                Spacer()
                topControls(s)
            }
        }
    }

    private func practiceLabel(_ s: GameSession) -> some View {
        // Passages ride a synthetic VocabEntry whose jlpt is hardcoded .n5, so the
        // header claimed every passage was N5 — a Long passage full of N3 grammar
        // included. The honest label for a passage is its LENGTH, which is the thing the
        // user actually picked in the menu; the JLPT label stays for word-stream mode,
        // where it is real. (v1.15 §L.)
        //
        // "练习" in Chinese: this read "PRACTICE · 长" in the Chinese UI (simulator pass #8),
        // and 练习 is what the app already calls this mode (`GameMode.displayName`, the Ride
        // Log). The English string is unchanged byte for byte. (v1.33 §B L.)
        Text((model.languageCode == "zh" ? "练习" : "PRACTICE") + " · \(practiceHeaderLabel(s))")
            .scaledSystemFont(12, weight: .bold).tracking(3)
            .foregroundStyle(ink.opacity(0.4))
            // The label yields before the buttons do: it is decoration, they are controls.
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    /// The badge shown when romaji hints are off.
    ///
    /// Chinese says "提示已关", the words the ride and drill screens already use for the same state
    /// (`assistance == .off`, `GameView.controls`) — not 盲打, which in Chinese means touch-typing
    /// without looking at the keyboard, a different thing. It read "BLIND" in the Chinese UI.
    ///
    /// One line and a fixed width: the badge is a state the learner chose and must be able to
    /// read, so when the row is short it is the label beside it that yields, not this. Measured
    /// with CoreText, at XXXL with a custom text the one-row bar needs 381pt even with the label at
    /// its floor — against 369 with the keyboard up and 353 with it down — and the badge was the
    /// only thing left to squeeze. (v1.33 §B L.)
    ///
    /// ⚠️ **This is NOT an accessibility-size-only change, and "nothing moves at the default size"
    /// was true only of the 1000pt macOS render** (corrected in the pre-submission review). On a
    /// 393pt phone at the default size with hints off, the one-row bar needs ~394pt ("PRACTICE ·
    /// LONG") or ~423pt ("· MY TEXT") against 369 with the keyboard up (CoreText). Before, the row
    /// could squeeze the badge or the label; now only the label yields (to ×0.8, inside its 0.5
    /// floor). Kept deliberately: the badge can no longer break mid-word.
    @ViewBuilder
    private var hintsOffBadge: some View {
        if model.assistance == .off {
            Text(model.languageCode == "zh" ? "提示已关" : "BLIND")
                .scaledSystemFont(11, weight: .heavy).tracking(2)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(accent, in: Capsule())
                .padding(.leading, 6)
        }
    }

    @ViewBuilder
    private func topControls(_ s: GameSession) -> some View {
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

    private func practiceHeaderLabel(_ s: GameSession) -> String {
        let zh = model.languageCode == "zh"
        if model.practiceSource == .custom {
            // A SHORT constant, not the text's title. **Measured, and the measurement's
            // CONDITIONS matter:** at the default text size "PRACTICE · MY TEXT" fits an
            // iPhone comfortably, and a twenty-character user title would not. At AX5 — where
            // this was first seen — the header yields its width to the Next/Done buttons (the
            // comment at the call site says so, deliberately) and collapses to "PRAC…"
            // whatever the label is, title or not.
            //
            // So this is not a fix for AX5, which needs the row rethought and is Gate E's
            // territory. It keeps the custom label in the same length class as its siblings —
            // SHORT / MED / LONG — so it costs nothing at any size. The learner chose the text
            // one tap ago and the menu names it.
            //
            // (v1.33 §B L rethought the row: at the accessibility sizes `topBar` gives the label
            // its own line under the buttons, where "PRACTICE · MY TEXT" needs ×0.54 at AX5
            // beside BLIND with the keyboard up, and ×0.50 with it down — at its 0.5 floor.)
            return zh ? "我的文本" : "MY TEXT"
        }
        guard model.practicePassages else { return s.currentLevelLabel }
        switch model.practicePassageLevel {
        case .easy: return zh ? "短" : "SHORT"
        case .med:  return zh ? "中" : "MED"
        case .hard: return zh ? "长" : "LONG"
        }
    }

    private func topButton(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .scaledSystemFont(14, weight: .semibold)
                // One line. At AX5 these wrapped mid-word inside their capsule — "Ne / xt ▸"
                // and "Do / ne" in two circles — because the row has to share its width with
                // the PRACTICE · LONG label. Shrinking is the honest trade for a control whose
                // whole job is to be tappable and readable at a glance. (v1.16 §D.)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: true, vertical: false)
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
        // A custom-text entry carries its punctuated reading in `surface`, because the caret
        // walks THIS string while the engine consumes `kana` — and `CustomSentence` asserts
        // that the two differ by punctuation and nothing else.
        if let id = s.current?.id, id.hasPrefix("customtext-") {
            return s.current?.surface ?? (s.currentKana ?? "")
        }
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
        // "正确率", not "ACC", in Chinese — the in-ride HUD's word for this number (`GameView`
        // and `ConjugationGameView` both label it 正确率 beside the same 进度 used here). The
        // results tiles say 准确率; this row is the HUD's counterpart, so it follows the HUD.
        // "WPM" stays: the Chinese UI already writes it as WPM (Stats, the Ride Log). (v1.33 §B L.)
        let zh = model.languageCode == "zh"
        return HStack(spacing: 34) {
            stat("WPM", wpm)
            stat(zh ? "正确率" : "ACC", "\(Int(s.accuracy * 100))%")
            stat(zh ? "进度" : "DONE", "\(s.wordsCompleted)/\(s.wordCount)")
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
