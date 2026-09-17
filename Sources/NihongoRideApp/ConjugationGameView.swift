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
    @Environment(\.scenePhase) private var scenePhase
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
        // The prompt clock follows the same signals as the ride's, and the drill has two of
        // the three (it has no add-to-lists sheet). Before v1.31 this view stopped the struggle
        // detector and nothing else, because there was no prompt clock to stop.
        .onChange(of: isPaused) { _, paused in
            paused ? model.pauseRunClock() : model.resumeRunClock()
            if paused { model.conjugationSession?.resetStruggle() }
        }
        .onChange(of: scenePhase) { _, phase in
            phase == .active ? model.resumeRunClock() : model.pauseRunClock()
            if phase != .active { model.conjugationSession?.resetStruggle() }
        }
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
    @Environment(\.dynamicTypeSize) private var typeSize
    let session: ConjugationSession
    let language: String
    var onPause: (() -> Void)? = nil

    private var narrow: Bool { isPhoneIdiom }
    private var zh: Bool { language == "zh" }

    var body: some View {
        let accessibilitySize = typeSize.isAccessibilitySize
        HStack(spacing: narrow ? 8 : 14) {
            // **`lineLimit(1)` is not decoration here.** This row had none, and "Conjugate" is
            // nine characters where the ride's equivalent pill holds "N5" — so on a phone, as
            // soon as the score reached three digits the mode capsule wrapped mid-word to
            // "Conjugat / e" and the progress pill broke into "2/1 / 2". Seen at ★230 on an
            // iPhone 17 Pro; the row simply has less width than it needs and SwiftUI resolved
            // that by wrapping every Text in it.
            //
            // Shrink before truncating, and never wrap: a label that wraps mid-word reads as a
            // broken screen, while a slightly smaller one reads as a label.
            //
            // **v1.33: that was still not enough at AX5.** The line limit held, and the badge
            // shrank to its floor and then truncated to a bare "…" — in both languages, even the
            // two-character 变形 (simulator pass 2026-09-17, `A_game-conjugation_{en,zh}_ax5.png`).
            // Three things, all at the accessibility sizes only (`ConjugationHUDLayout`):
            // * the score pill goes, as in the ride HUD — `RideHUDLayout` has the arithmetic;
            // * the badge says the mode's own menu name, "Verbs" / 变形, instead of "Conjugate"
            //   (66pt at its floor against 102), so the learner reads the word they tapped;
            // * the badge is laid out FIRST. The measured shot shows why: 51pt was left over and
            //   the Spacer took 18 of it while the badge got only its "…". An HStack splits the
            //   leftover between the flexible children, so without a priority the badge gets half
            //   of whatever room hiding a pill makes.
            // Late in a drill (★1200, ×10, 11/12) that leaves the badge 82 / 73 / 61pt on a 402pt
            // phone, a 393pt phone, and a 393pt phone with the keyboard dismissed; the last is 5
            // short of "Verbs", which is why the Spacer may also collapse to zero there (+8).
            Text(ConjugationHUDLayout.badgeLabel(zh: zh, accessibilitySize: accessibilitySize))
                .scaledSystemFont(14, weight: .heavy, design: .rounded)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Theme.accent2.opacity(0.85), in: Capsule())
                .accessibilityLabel(zh ? "动词变形模式" : "Conjugation mode")
                .layoutPriority(accessibilitySize ? 1 : 0)
            if RideHUDLayout.showsScore(typeSize) {
                stat(icon: "star.fill", value: "\(session.score)", tint: Theme.gold, label: zh ? "得分" : "Score")
            }
            stat(icon: "flame.fill",
                 value: session.combo >= 2 ? "×\(session.combo)" : "—",
                 tint: session.combo >= 2 ? Theme.accent : Theme.dim,
                 label: zh ? "连击" : "Combo",
                 spoken: session.combo >= 2 ? "\(session.combo)" : (zh ? "无" : "none"))
            Spacer(minLength: accessibilitySize ? 0 : nil)
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
            // Same reason as the capsule above: "2/12" wrapping to two lines is not a smaller
            // number, it is a broken pill. These are short strings; they must never wrap.
            Text(value).foregroundStyle(.white).monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, narrow ? 9 : 12).padding(.vertical, 7)
        .background(.black.opacity(0.42), in: Capsule())
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(spoken ?? value)
    }
}

/// The drill HUD's accessibility-size choices that are not shared with the ride HUD.
/// (v1.33 §B G; the shared one is `RideHUDLayout`.)
enum ConjugationHUDLayout {
    /// The mode badge. Today's "Conjugate" / 变形 at every size below the accessibility sizes;
    /// at them, the mode's own menu chip name (`GameMode.shortLabel`) — "Verbs" / 变形 — because
    /// "Conjugate" needs 102pt at its 0.7 shrink floor at AX1 and the row cannot give it that late
    /// in a drill on any phone measured (see `ConjugationHUD`). Taken from the menu rather than
    /// written again here, so the badge names the chip the learner tapped even if that is renamed.
    static func badgeLabel(zh: Bool, accessibilitySize: Bool) -> String {
        guard accessibilitySize else { return zh ? "变形" : "Conjugate" }
        return GameMode.conjugation.shortLabel(zh: zh)
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
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The verb's and its reading's resolved point sizes — the same `@ScaledMetric`s their
    /// `scaledSystemFont` calls below build, so the verb's shrink floor can be stated in terms of
    /// the reading. (v1.33 §B G, see `ConjugationCardLayout`.)
    @ScaledMetric(relativeTo: .largeTitle) private var verbPointsCompact: CGFloat = 36
    @ScaledMetric(relativeTo: .largeTitle) private var verbPointsRegular: CGFloat = 56
    @ScaledMetric(relativeTo: .body) private var readingPointsCompact: CGFloat = 18
    @ScaledMetric(relativeTo: .body) private var readingPointsRegular: CGFloat = 24
    let session: ConjugationSession
    let language: String
    var compact: Bool = false

    private var zh: Bool { language == "zh" }

    var body: some View {
        let accessibilitySize = typeSize.isAccessibilitySize
        VStack(spacing: compact ? 10 : 18) {
            Text(zh ? "辞書形" : "Dictionary form")
                .scaledSystemFont(compact ? 11 : 13, weight: .semibold, design: .rounded)
                .foregroundStyle(Theme.dim)
                .accessibilityHidden(true)

            // **The verb was shrinking for HEIGHT, not width.** At AX5 (capped to AX1) 降る, 引く
            // and 習う — two characters, ~93pt wide in a 354pt card — rendered at about 19pt,
            // below their 30pt reading (simulator pass 2026-09-17, `A_game-conjugation_en_ax5.png`
            // against `…_large.png`). With the keyboard up the card has about 363pt of content
            // height at AX1 and its lines ask for 420 (CoreText, single-line heights); this Text
            // and the gloss are the only children allowed to shrink, so the VStack took the
            // whole shortfall out of the verb, down to its 0.4 floor. Letting the line wrap would
            // change nothing — it was never too wide.
            //
            // So at the accessibility sizes: the floor is the reading's size (the verb can still
            // give up height, never below its reading), and the arrow below — decoration, hidden
            // from VoiceOver — goes, returning 35pt keyboard-up and 47 keyboard-down. That brings
            // the keyboard-up demand to 385 against 363, a shortfall the verb (20pt above its new
            // floor) and the gloss can absorb to within a couple of points. Keyboard down there is
            // no shot to calibrate against; by the same arithmetic, with the room estimated from
            // the phone's geometry, the card was about 33pt over before and about 15 after. Either
            // way the verb cannot end up below its reading — that part is the floor, not the room.
            Text(session.currentSurface ?? "")
                .scaledSystemFont(compact ? 36 : 56, weight: .bold, relativeTo: .largeTitle)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(ConjugationCardLayout.verbScaleFloor(
                    verbPoints: compact ? verbPointsCompact : verbPointsRegular,
                    readingPoints: compact ? readingPointsCompact : readingPointsRegular,
                    accessibilitySize: accessibilitySize))
            Text(session.currentDictKana ?? "")
                .scaledSystemFont(compact ? 18 : 24, weight: .semibold, design: .rounded)
                .foregroundStyle(.white.opacity(0.75))
            Text(session.currentGloss ?? "")
                .scaledSystemFont(compact ? 14 : 18, weight: .medium, design: .rounded)
                .foregroundStyle(Theme.dim)
                .lineLimit(1).minimumScaleFactor(0.5)

            // The instruction: produce THIS form. Not at the accessibility sizes — see the verb.
            if ConjugationCardLayout.showsFormArrow(accessibilitySize: accessibilitySize) {
                Image(systemName: "arrow.down")
                    .scaledSystemFont(compact ? 13 : 16, weight: .bold)
                    .foregroundStyle(Theme.accent2)
                    .accessibilityHidden(true)
            }
            // **This is the question.** In English the label is "\(japaneseLabel) / \(englishLabel)",
            // and the longest of the seven — ない形（否定） / Negative (-nai) — does not fit a
            // phone at 18pt. It was truncating to "…/ Negative (…", which is the one string on
            // this screen the learner cannot do without: it names the form they are being asked
            // to produce.
            //
            // Shrink rather than truncate, the same choice the practice header and the Ride
            // Log's date column already make. A slightly smaller prompt is still the prompt; a
            // cut one is a different question.
            Text(session.currentFormLabel ?? "")
                .scaledSystemFont(compact ? 18 : 24, weight: .heavy, design: .rounded)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .allowsTightening(true)
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
            // **The typing target wraps; it never shrinks.** One HStack of glyphs cannot get
            // narrower than its glyphs, so a long answer ran off both sides of the card. Measured
            // with CoreText on a 393pt phone: at AX1 with the keyboard down a glyph is 49pt in a
            // 313pt card, so 7 kana overflow — the past negative of any four-kana verb, the
            // largest group (1,024 of 2,317) — and at the DEFAULT size with the keyboard down 8
            // kana (318pt) already do; keyboard up, 11 at AX1 (372 of 345), e.g.
            // トレーニングしなかった. (v1.33 §B G, scan finding #5.)
            //
            // `ViewThatFits` tries today's row first and keeps it whenever it fits, so every
            // answer that fitted renders exactly as before; only one that could not be shown
            // whole moves to `MenuFlow`, which centres each row the same way.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 2) { answerGlyphs(kana, done: done, hint: hint) }
                MenuFlow(spacing: 2, rowSpacing: 4) { answerGlyphs(kana, done: done, hint: hint) }
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
            } else if session.assistanceOffered {
                // Without this the conjugation drill is permanently blind under the new
                // default: the session runs the struggle detector and sets the flag, but no
                // view read it, so "when stuck" hid the answer and offered no way to see it.
                // Tap gesture rather than a Button — this is a key-capture screen.
                Label(zh ? "卡住了?看答案" : "Stuck? Show answer", systemImage: "lightbulb")
                    .scaledSystemFont(compact ? 13 : 15, weight: .semibold, design: .rounded)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Theme.gold.opacity(0.16), in: Capsule())
                    .foregroundStyle(Theme.gold)
                    .contentShape(Capsule())
                    .onTapGesture { session.revealHint() }
                    .accessibilityElement()
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("assistanceOffer")
                    .accessibilityLabel(zh ? "看答案。这一题会计为需要复习"
                                           : "Show the answer. This prompt will count as needing review")
            }
        }
    }

    /// The answer's glyphs, one per kana — laid out by whichever container `answer` picks, so
    /// the row and its wrapped form draw the same glyphs.
    @ViewBuilder
    private func answerGlyphs(_ kana: [Character], done: Int, hint: Bool) -> some View {
        ForEach(Array(kana.enumerated()), id: \.offset) { index, character in
            let revealed = index < done || hint
            Text(revealed ? String(character) : "・")
                .scaledSystemFont(compact ? 26 : 40, weight: .semibold, design: .rounded, relativeTo: .largeTitle)
                .foregroundStyle(color(index: index, done: done, revealed: revealed))
                .scaleEffect(index == done ? 1.12 : 1)
                .animation(.smooth(duration: 0.15), value: done)
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

/// The drill card's accessibility-size rules, out of the view so they can be checked without a
/// device. (v1.33 §B G; the reasoning and the measurements are at the call sites in
/// `ConjugationCard`.)
enum ConjugationCardLayout {
    /// The dictionary-form verb's shrink floor at every size below the accessibility sizes —
    /// unchanged, so the default-size card is exactly what it was.
    static let defaultVerbScaleFloor: CGFloat = 0.4

    /// The verb may shrink, but at the accessibility sizes never below the size of its own
    /// reading: `verbPoints × floor ≥ readingPoints`. At AX1 that is 29.6 / 46.6 ≈ 0.64 with the
    /// keyboard up and 39.5 / 72.5 ≈ 0.55 with it down; never lower than today's 0.4.
    static func verbScaleFloor(verbPoints: CGFloat, readingPoints: CGFloat,
                               accessibilitySize: Bool) -> CGFloat {
        guard accessibilitySize, verbPoints > 0 else { return defaultVerbScaleFloor }
        return min(1, max(defaultVerbScaleFloor, readingPoints / verbPoints))
    }

    /// The decorative arrow between the verb and the form it must become is dropped at the
    /// accessibility sizes to give the card back the height the verb was losing.
    static func showsFormArrow(accessibilitySize: Bool) -> Bool {
        !accessibilitySize
    }
}
