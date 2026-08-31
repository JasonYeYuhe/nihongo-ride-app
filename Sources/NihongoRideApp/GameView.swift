import SwiftUI
import SceneryKit
import GameCore
import RomajiKana
import VocabKit

struct GameView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var isPaused = false
    @State private var timeRemaining = 0.0
    /// The speed pill's value, in whole words per minute. Held as view state rather than read
    /// from the model on every render because elapsed time changes with no state change behind
    /// it — nothing in the model moves between keystrokes, so a computed property would show a
    /// number frozen at the last key press. The ticker below is what makes it live.
    @State private var liveWPM = 0.0
    @State private var keyboardUp = false   // iOS: software keyboard visible → compact layout
    /// Vocab id whose "add to lists" sheet is open (long-press ★). While set, the
    /// game must NOT consume keystrokes or advance the word — otherwise the sheet
    /// would end up editing a *different* word than the one the user long-pressed.
    @State private var addToListsID: String?
    private let ticker = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        if let session = model.session {
            play(session)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func play(_ session: GameSession) -> some View {
        ZStack {
            ZStack {
                RideBackgroundView(speed: rideSpeed(session), landmarkPhase: landmarkPhase(session), stage: model.rideStage)
                // Scrim derived from the stage's own ground luminance, never a literal: a
                // brighter road cannot ship without buying the contrast back. (v1.12 §D.)
                Color.black.opacity(model.rideStage.palette.textScrim).ignoresSafeArea()

                VStack(spacing: keyboardUp ? 12 : 22) {
                    HUDBar(session: session, language: model.languageCode, wpm: liveWPM,
                           onPause: isTouchDevice ? { isPaused = true } : nil)
                    if session.mode == .timeAttack {
                        TimerBar(remaining: timeRemaining, total: session.config.timeLimit ?? 1,
                                 language: model.languageCode)
                    } else {
                        JourneyBar(session: session, language: model.languageCode)
                    }
                    Spacer(minLength: 0)
                    WordCard(session: session, language: model.languageCode, compact: keyboardUp,
                             onLongPressStar: { addToListsID = $0 })
                    if !keyboardUp {
                        Spacer(minLength: 0).frame(maxHeight: 60)   // bias card lower; scene breathes above
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
        // The dense, fixed ride layout (HUD pills + word card) can't reflow, so cap
        // Dynamic Type here: it still scales up to one accessibility step but extreme
        // sizes can't shatter the HUD. Large-type layout is device-verified (Gate E).
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .background {
            if !Screenshotter.isCapturing {
                KeyCaptureView(
                    onKey: { character in
                        guard !isPaused, addToListsID == nil else { return }
                        switch session.input(character) {
                        case .completed: Sound.wordComplete()
                        case .rejected: Sound.mistake()
                        case .accepted: Sound.tick()
                        }
                    },
                    onCommand: { command in
                        guard addToListsID == nil else { return }   // sheet open → ignore keys
                        switch command {
                        case .escape: isPaused.toggle()
                        case .returnKey: if isPaused { isPaused = false }
                        case .space, .backspace: break
                        }
                    }
                )
            }
        }
        // The ridden-time clock follows the SAME three signals that already stop the game's
        // own timer, so the duration written to the journal matches what the rider saw.
        // (v1.15 §D — before this, paused/sheet/backgrounded time was recorded as riding.)
        .onChange(of: isPaused) { _, paused in
            paused ? model.pauseRunClock() : model.resumeRunClock()
            if paused {
                // A pause gives the learner time to think, so the struggle count restarts —
                // the offer should mean "stuck NOW", not "was stuck before dinner". (v1.16 §A.)
                session.resetStruggle()
                // And a dictation prompt is a question, which a paused game is not asking.
                // Nothing else in the app needed this, because nothing else auto-plays.
                model.stopSpeaking()
            }
        }
        .onChange(of: addToListsID != nil) { _, open in
            open ? model.pauseRunClock() : model.resumeRunClock()
        }
        .onChange(of: scenePhase) { _, phase in
            phase == .active ? model.resumeRunClock() : model.pauseRunClock()
            if phase != .active { session.resetStruggle(); model.stopSpeaking() }
        }
        .onAppear {
            Sound.enabled = model.soundEnabled
            isPaused = false
            timeRemaining = session.config.timeLimit ?? 0
            // Defensive: a session that was already finished at construction
            // (e.g. an empty queue) would otherwise strand here — onChange won't
            // fire for a value that never changes. Finish it immediately.
            if session.isFinished { model.finishGame() }
            playPrompt(session)
        }
        // The app's ONE auto-playing sound, and the exception is principled: everywhere else
        // audio is an aid a learner opts into per card, so it waits to be asked. In dictation
        // the audio is the question — a card that waited to be asked would be a blank screen
        // demanding you type what you had not been told.
        .onChange(of: session.index) { _, _ in playPrompt(session) }
        .onReceive(ticker) { _ in
            // The speed readout, in every mode — so it is updated BEFORE the time-attack guard
            // below, which returns early. Assigned only when the DISPLAYED whole number moves,
            // so a 10 Hz ticker does not redraw the HUD ten times a second for a value that
            // changes every few seconds. `model.liveWPM` is RunClock's ridden time, so a pause
            // freezes this rather than letting it decay.
            let shown = model.liveWPM.rounded()
            if shown != liveWPM { liveWPM = shown }
            // Sheet open → pause the time-attack clock too (it's a modal interruption).
            guard session.mode == .timeAttack, !isPaused, addToListsID == nil,
                  !session.isFinished else { return }
            timeRemaining = max(0, timeRemaining - 0.1)
            if timeRemaining <= 0 { Sound.finish(); model.finishGame() }
        }
        .onChange(of: session.isFinished) { _, finished in
            if finished { Sound.finish(); model.finishGame() }
        }
        .sheet(isPresented: Binding(get: { addToListsID != nil },
                                    set: { if !$0 { addToListsID = nil } }),
               onDismiss: {
                   // Reclaim the game keyboard the sheet displaced — a touch-only
                   // iPad would otherwise be stuck with no keyboard (App Review 2.1a).
                   #if os(iOS)
                   KeyboardSummon.summon()
                   #endif
               }) {
            if let id = addToListsID {
                AddToListsSheet(vocabID: id, isPresented: Binding(
                    get: { addToListsID != nil },
                    set: { if !$0 { addToListsID = nil } }))
                    .presentationBackground(Theme.background)
            }
        }
    }

    private var pauseOverlay: some View {
        let zh = model.languageCode == "zh"
        return ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 18) {
                Text(zh ? "暂停" : "Paused")
                    .scaledSystemFont(34, weight: .heavy, design: .rounded, relativeTo: .largeTitle)
                    .foregroundStyle(.white)
                // iPhone is too narrow for the buttons side by side — stack them.
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

                    Button(action: { isPaused = false; model.finishGame() }) {
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

    /// Pedalling speed for the ride scene — always moving, faster on a combo.
    /// Speaks the current dictation prompt. It reads `exampleJP` — the KANJI sentence —
    /// and not `exKana`, which is the string the learner is typing and would look like the
    /// safer choice. It is not: Kyoko reads a bare hiragana は as "ha", so feeding it the
    /// typing target would mispronounce the topic particle in roughly 2,900 of the corpus's
    /// sentences. Reading the kanji lets the synthesizer's own parser resolve the particles,
    /// at the cost of it also choosing the kanji readings — which is the thing
    /// `DictationSafety` was measured for, and why some sentences never reach this function.
    private func playPrompt(_ session: GameSession) {
        guard session.mode == .dictation, !session.isFinished, !Screenshotter.isCapturing else { return }
        model.speakPrompt(session.currentExampleJP ?? session.currentSurface)
    }

    private func rideSpeed(_ session: GameSession) -> Double {
        1.0 + Double(min(session.combo, 12)) * 0.12
    }

    /// Which horizon landmark to show (0→4 across a journey; cycles in time-attack).
    private func landmarkPhase(_ session: GameSession) -> Double {
        session.mode == .timeAttack ? Double(session.wordsCompleted) / 4.0 : session.progress * 4
    }

    private var controls: some View {
        let zh = model.languageCode == "zh"
        return HStack(spacing: 18) {
            if isTouchDevice {
                Label(zh ? "轻点屏幕呼出键盘" : "Tap screen for keyboard", systemImage: "keyboard")
            } else {
                Label(zh ? "Esc 暂停" : "Esc to pause", systemImage: "escape")
            }
            if let session = model.session, session.assistance == .off {
                Label(zh ? "提示已关" : "Hints off", systemImage: "eye.slash")
            }
        }
        .font(.callout)
        .foregroundStyle(Theme.dim)
    }
}

// MARK: - HUD

private struct HUDBar: View {
    let session: GameSession
    let language: String
    /// Whole words per minute over RIDDEN time, from `AppModel.liveWPM`. Zero means "not yet
    /// meaningful" by `RunClock.wpm`'s own convention — under two seconds of riding, or no
    /// correct keystrokes — and is rendered as a dash rather than as a zero, because a rider
    /// three seconds into a ride is not going at 0 wpm.
    var wpm: Double = 0
    var onPause: (() -> Void)? = nil

    /// iPhone width fits ~4 pills; distance + accuracy move to the results
    /// screen there (they're informational, not actionable mid-run).
    private var narrow: Bool { isPhoneIdiom }

    private var zh: Bool { language == "zh" }

    var body: some View {
        HStack(spacing: narrow ? 8 : 14) {
            Text(session.currentLevelLabel)
                .scaledSystemFont(14, weight: .heavy, design: .rounded)
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Theme.accent2.opacity(0.85), in: Capsule())
                .accessibilityLabel(zh ? "等级 \(session.currentLevelLabel)" : "Level \(session.currentLevelLabel)")
            stat(icon: "star.fill", value: "\(session.score)", tint: Theme.gold,
                 label: zh ? "得分" : "Score")
            stat(icon: "flame.fill",
                 value: session.combo >= 2 ? "×\(session.combo)" : "—",
                 tint: session.combo >= 2 ? Theme.accent : Theme.dim,
                 label: zh ? "连击" : "Combo",
                 spoken: session.combo >= 2 ? "\(session.combo)" : (zh ? "无" : "none"))
            Spacer()
            if !narrow {
                stat(icon: "bicycle", value: "\(Int(session.distanceMeters)) m", tint: Theme.accent2,
                     label: zh ? "距离" : "Distance",
                     spoken: zh ? "\(Int(session.distanceMeters)) 米" : "\(Int(session.distanceMeters)) meters")
            }
            stat(icon: "checkmark.circle.fill",
                 value: "\(session.wordsCompleted)/\(session.wordCount)", tint: Theme.done,
                 // One run must not show three units for one number. v1.25 §B taught the
                 // results screen to say "Sentences" on a sentence or dictation ride, and this
                 // HUD kept saying "Words" for the same queue — so mid-ride read "Words 2/5"
                 // and the results screen read "Sentences 5". The Chinese has always said
                 // 进度 ("progress"), which is mode-neutral and therefore already right in all
                 // six modes: one language had solved this and the other had not. (v1.26 §B3.)
                 label: session.mode.hudProgressLabel(zh: zh),
                 spoken: zh ? "\(session.wordsCompleted) / \(session.wordCount)"
                            : "\(session.wordsCompleted) of \(session.wordCount)")
                .accessibilityIdentifier("hudProgress")
            if !narrow {
                stat(icon: "scope",
                     value: "\(Int(session.accuracy * 100))%", tint: .white,
                     label: zh ? "正确率" : "Accuracy")
                // Informational, so it follows the same width rule as distance and accuracy:
                // the fixed ride layout fits about four pills on a phone and cannot reflow, and
                // a shattered HUD is device-verified territory (Gate E). A phone rider still
                // gets the number on the results screen and in the Ride Log, which is where it
                // was already.
                stat(icon: "speedometer",
                     value: wpm >= 1 ? "\(Int(wpm))" : "—", tint: Theme.accent,
                     label: zh ? "速度" : "Speed",
                     spoken: wpm >= 1 ? (zh ? "每分钟 \(Int(wpm)) 词" : "\(Int(wpm)) words per minute")
                                      : (zh ? "尚未开始计算" : "not yet"))
                    .accessibilityIdentifier("hudSpeed")
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

    /// One HUD telemetry pill, exposed to VoiceOver as a single labeled+valued
    /// element (the icon is decorative). `spoken` overrides the announced value
    /// where the on-screen glyph would read poorly (e.g. "—", "150 m").
    private func stat(icon: String, value: String, tint: Color,
                      label: String, spoken: String? = nil) -> some View {
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

// MARK: - Journey progress

private struct JourneyBar: View {
    let session: GameSession
    var language: String = "en"
    private let landmarks = ["🗼", "🗻", "🏯", "⛩️"]
    @State private var bob = false
    @State private var hop = false

    var body: some View {
        let progress = session.progress
        return bar(progress)
            // The bar + landmark emoji + bicycle are decorative; expose one element.
            .accessibilityElement()
            .accessibilityLabel(language == "zh" ? "行程进度" : "Journey progress")
            .accessibilityValue("\(Int(progress * 100))%")
    }

    private func bar(_ progress: Double) -> some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.card).frame(height: 8)
                Capsule()
                    .fill(LinearGradient(colors: [Theme.accent2, Theme.accent],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(8, width * progress), height: 8)

                ForEach(Array(landmarks.enumerated()), id: \.offset) { index, emoji in
                    let fraction = landmarks.count == 1 ? 0 : Double(index) / Double(landmarks.count - 1)
                    Text(emoji)
                        .font(.system(size: 22))
                        .position(x: clampX(width * fraction, width), y: 4)
                }

                Text("🚲")
                    .font(.system(size: 28))
                    .scaleEffect(hop ? 1.35 : 1.0)
                    .offset(y: bob ? -3 : 3)
                    .position(x: clampX(width * progress, width), y: 4)
                    .animation(.smooth, value: progress)
            }
        }
        .frame(height: 30)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { bob = true }
        }
        .onChange(of: session.wordsCompleted) { _, _ in
            withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) { hop = true }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.6).delay(0.14)) { hop = false }
        }
    }

    private func clampX(_ x: CGFloat, _ width: CGFloat) -> CGFloat {
        min(max(14, x), width - 14)
    }
}

// MARK: - Time-attack countdown

private struct TimerBar: View {
    let remaining: Double
    let total: Double
    var language: String = "en"
    /// The countdown's width has to grow with the text, or the digits get cut off — and a
    /// truncated countdown does not look broken, it looks like a different number: at the
    /// accessibility sizes "35s" rendered as "3…", i.e. the screen said three seconds
    /// remained when thirty-five did. @ScaledMetric grows the box; minimumScaleFactor is the
    /// backstop for the sizes where even the grown box is not enough. (v1.16 §D.)
    @ScaledMetric(relativeTo: .body) private var readoutWidth: CGFloat = 46

    var body: some View {
        let fraction = total > 0 ? max(0, min(1, remaining / total)) : 0
        let low = remaining <= 10
        return content(fraction: fraction, low: low)
            .accessibilityElement()
            .accessibilityLabel(language == "zh" ? "剩余时间" : "Time remaining")
            .accessibilityValue(language == "zh" ? "\(Int(ceil(remaining))) 秒" : "\(Int(ceil(remaining))) seconds")
    }

    private func content(fraction: Double, low: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "timer").foregroundStyle(low ? Theme.accent : Theme.accent2)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.card)
                    Capsule()
                        .fill(low ? Theme.accent : Theme.accent2)
                        .frame(width: max(0, geo.size.width * fraction))
                        .animation(.linear(duration: 0.1), value: fraction)
                }
            }
            .frame(height: 10)
            Text("\(Int(ceil(remaining)))s")
                .scaledSystemFont(17, weight: .bold, design: .rounded, monospacedDigit: true)
                .foregroundStyle(low ? Theme.accent : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(width: readoutWidth, alignment: .trailing)
        }
        .frame(height: 30)
    }
}

// MARK: - Current word

private struct WordCard: View {
    @Environment(AppModel.self) private var model
    let session: GameSession
    let language: String
    /// True while the on-screen keyboard occupies the lower screen (iOS) —
    /// shrink everything so the card fits the visible upper area.
    var compact: Bool = false
    /// Long-press the ★ → open the "add to lists" sheet for the given vocab id.
    /// Owned by GameView so it can suspend game input while the sheet is up.
    var onLongPressStar: (String) -> Void = { _ in }

    private var isDictation: Bool { session.mode == .dictation }

    var body: some View {
        VStack(spacing: compact ? 10 : 18) {
            if isDictation {
                // The prompt IS the audio. Nothing that would answer the question — not the
                // sentence, not its reading, not the word's meaning — appears before the
                // learner asks to be shown.
                replayControl
            } else {
                Text(session.currentSurface ?? "")
                    .scaledSystemFont(compact ? 40 : 64, weight: .bold, relativeTo: .largeTitle)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)   // long compounds shrink instead of clipping (narrow screens)

                kanaReading

                Text(session.currentGloss ?? "")
                    .scaledSystemFont(compact ? 15 : 20, weight: .medium, design: .rounded)
                    .foregroundStyle(Theme.dim)

                readingNote
            }

            Divider().background(Theme.cardStroke).frame(maxWidth: compact ? 300 : 360)

            romaji

            // The dictation reveal, and the one place furigana earns the most: the learner
            // has just been told what they could not hear, and the ruby is the bridge from
            // the kanji they are now seeing to the kana they were being asked to type. It
            // renders even in the compact (keyboard-up) layout, because a reveal you cannot
            // see is not a reveal.
            if isDictation, session.isRevealed, let example = session.currentExampleJP {
                VStack(spacing: 3) {
                    if model.exampleFurigana,
                       let tokens = session.currentExampleTokens, !tokens.isEmpty {
                        FuriganaText(tokens: tokens, size: compact ? 14 : 16, color: .white.opacity(0.85))
                    } else {
                        Text(example)
                            .scaledSystemFont(compact ? 14 : 16, weight: .medium)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    // The translation is dropped in the compact layout for the reason the
                    // sibling block below drops the whole example there: with the software
                    // keyboard up the card has room for about two lines, and this reveal
                    // already spends them on the sentence and its ruby. The sentence is what
                    // the learner needs; the translation is what they can go back for.
                    if !compact, let translation = session.currentExampleTranslation {
                        Text(translation)
                            .scaledSystemFont(13)
                            .foregroundStyle(Theme.dim)
                    }
                }
                .multilineTextAlignment(.center)
                .padding(.top, 4)
            }

            if !compact, !isDictation, let example = session.currentExampleJP {
                VStack(spacing: 3) {
                    // Furigana on the DISPLAYED example only. In sentence mode the example is
                    // the thing being typed, so showing its reading would hand over the
                    // answer — GameSession reports .sentence and the ruby stays off.
                    if model.exampleFurigana,
                       session.mode != .sentence,
                       let tokens = session.currentExampleTokens, !tokens.isEmpty {
                        FuriganaText(tokens: tokens, size: 16, color: .white.opacity(0.7))
                    } else {
                        Text(example)
                            .scaledSystemFont(16, weight: .medium)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    if let translation = session.currentExampleTranslation {
                        Text(translation)
                            .scaledSystemFont(13)
                            .foregroundStyle(Theme.dim)
                    }
                }
                .multilineTextAlignment(.center)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: 560)
        .padding(compact ? 14 : 24)
        // The card's own backing IS the legibility mechanism — see RidePalette.cardAlpha.
        .background(.black.opacity(RidePalette.cardAlpha), in: RoundedRectangle(cornerRadius: compact ? 20 : 28))
        .overlay(RoundedRectangle(cornerRadius: compact ? 20 : 28).strokeBorder(.white.opacity(0.12)))
        .overlay(alignment: .topTrailing) { saveStar }
        .overlay(alignment: .topLeading) {
            // Not in dictation: that button reads `currentKana`, which here IS the answer.
            // The replay control on the card is the audio affordance, and it plays the
            // kanji sentence, not its reading.
            if !isDictation {
                SpeakButton(kana: session.currentKana, compact: compact, language: language)
            }
        }
    }

    /// Star: tap = ★ favorites (default list); long-press = add to lists.
    @ViewBuilder private var saveStar: some View {
        if let id = session.current?.id {
            let saved = model.isSaved(id)
            let zh = language == "zh"
            // Composed tap + long-press (NOT a Button + simultaneousGesture, which
            // let the long-press ALSO fire the tap → an unintended ★ toggle).
            Image(systemName: saved ? "star.fill" : "star")
                .scaledSystemFont(compact ? 15 : 18)
                .foregroundStyle(saved ? Theme.gold : Theme.dim)
                .padding(compact ? 10 : 14)
                .contentShape(Rectangle())
                .onTapGesture { model.toggleSaved(id) }
                .onLongPressGesture { onLongPressStar(id) }
                .accessibilityElement()
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("saveWordButton")
                .accessibilityLabel(saved ? (zh ? "已收藏,点按取消" : "Saved, tap to remove")
                                          : (zh ? "收藏此词" : "Save this word"))
                .accessibilityAction(named: Text(zh ? "加入词单" : "Add to lists")) { onLongPressStar(id) }
        }
    }

    /// Says so when the reading on this card is NOT the everyday reading of its spelling.
    ///
    /// 64 cards carry one. Each names a reading taught at an EASIER JLPT level than the
    /// card's own, which is the only non-circular evidence available for "this is the
    /// everyday one" — the corpus's own token readings cannot supply it, because the corpus
    /// only contains sentences for whichever entry the pipeline served. Several sit beside a
    /// sibling with a byte-identical gloss (鼠/ねず next to 鼠/ねずみ, both "mouse, rat"), where
    /// without this line the two cards are indistinguishable. (PLAN-V1.21 §C, tightened in
    /// v1.22 after three notes were found printing the claim backwards.)
    ///
    /// It states the reading fact and nothing about why the card has no example: that is
    /// pipeline history and no use to anyone typing.
    ///
    /// Shown in the compact (keyboard-up) layout too, unlike the example block below it. On
    /// an iPhone the keyboard is up for the whole run, so compact IS the normal state there —
    /// hiding it would mean an entire platform never sees it. It is one caption line and it
    /// replaces nothing.
    @ViewBuilder
    private var readingNote: some View {
        if let id = session.current?.id, let note = ReadingNotes.note(for: id) {
            let zh = language == "zh"
            Text(zh ? "这个写法平常读作 \(note.common),那个读音有自己的卡片"
                    : "Usually read \(note.common) — that reading has its own card")
            .font(.caption2)
            .foregroundStyle(Theme.gold.opacity(0.85))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The dictation prompt: a big replay control and the count of how often it was used.
    ///
    /// Replaying is free and unlimited — the mode trains listening, not memory, and a
    /// learner who has to hear a sentence four times has still done the exercise. The count
    /// is shown anyway, live and then again in the results, because it is the part of the
    /// outcome the score cannot express.
    ///
    /// A tap gesture and NOT a Button, for the reason the ★ and the stuck-offer are not
    /// Buttons either: this sits on the live typing screen where KeyCaptureView must hold
    /// first responder, and a focusable control here takes it away — dropping keys on
    /// macOS, dismissing the software keyboard on iOS.
    @ViewBuilder
    private var replayControl: some View {
        let zh = language == "zh"
        VStack(spacing: compact ? 6 : 10) {
            Image(systemName: "speaker.wave.3.fill")
                .scaledSystemFont(compact ? 34 : 52, weight: .semibold, relativeTo: .largeTitle)
                .foregroundStyle(Theme.accent2)
                .padding(compact ? 10 : 18)
                .contentShape(Rectangle())
                .onTapGesture {
                    session.noteReplay()
                    model.speakPrompt(session.currentExampleJP ?? session.currentSurface)
                    #if os(iOS)
                    KeyboardSummon.summon()
                    #endif
                }
                .accessibilityElement()
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("replayButton")
                .accessibilityLabel(zh ? "再听一遍" : "Play the sentence again")

            Text(zh ? "把听到的句子打出来" : "Type the sentence you hear")
                .scaledSystemFont(compact ? 13 : 16, weight: .medium, design: .rounded)
                .foregroundStyle(Theme.dim)

            // The app could not claim the audio session, so on iOS the prompt may be muted
            // by the Ring/Silent switch. Said HERE, in the run, because that is where a
            // learner meets the silence — a notice they only see after backing out to the
            // menu is a notice that arrives after they have concluded the mode is broken.
            if !model.dictationAudioSessionOK {
                Text(zh ? "听不到?检查静音开关和音量。" : "Hear nothing? Check the silent switch and volume.")
                    .font(.caption2)
                    .foregroundStyle(Theme.accent)
                    .multilineTextAlignment(.center)
            }

            if session.currentReplays > 0 {
                Text(zh ? "重听 \(session.currentReplays) 次"
                        : countLabel(session.currentReplays, "replay"))
                    .font(.caption2)
                    .foregroundStyle(Theme.dim.opacity(0.8))
                    .accessibilityIdentifier("replayCount")
            }
        }
    }

    /// Kana reading with committed kana tinted, the current one emphasized.
    /// iPhone: one concatenated Text so a long reading scales down as a unit
    /// instead of overflowing (per-character HStack can't shrink).
    @ViewBuilder
    private var kanaReading: some View {
        let kana = Array(session.currentKana ?? "")
        let done = session.completedKanaCount
        if isPhoneIdiom {
            // Concatenated runs can't scale per character, so the current kana
            // is emphasized with an underline instead (mirrors PracticeView).
            kana.enumerated().reduce(Text("")) { acc, pair in
                acc + Text(String(pair.element))
                    .foregroundStyle(color(index: pair.offset, done: done))
                    .underline(pair.offset == done, color: Theme.accent)
            }
            .scaledSystemFont(compact ? 26 : 34, weight: .semibold, design: .rounded, relativeTo: .largeTitle)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
        } else {
            HStack(spacing: 2) {
                ForEach(Array(kana.enumerated()), id: \.offset) { index, character in
                    Text(String(character))
                        .scaledSystemFont(compact ? 26 : 40, weight: .semibold, design: .rounded, relativeTo: .largeTitle)
                        .foregroundStyle(color(index: index, done: done))
                        .scaleEffect(index == done ? 1.12 : 1)
                        .animation(.smooth(duration: 0.15), value: done)
                }
            }
        }
    }

    private func color(index: Int, done: Int) -> Color {
        if index < done { return Theme.done }
        if index == done { return Theme.accent }
        return .white.opacity(0.85)
    }

    @ViewBuilder
    private var romaji: some View {
        VStack(spacing: compact ? 5 : 8) {
            Text(session.typedRomaji.isEmpty ? " " : session.typedRomaji)
                .scaledSystemFont(compact ? 20 : 26, weight: .bold, design: .monospaced)
                .foregroundStyle(Theme.accent2)
                .accessibilityIdentifier("typedRomaji")

            if session.romajiVisible {
                Text("→ \(session.currentRomaji ?? "")")
                    .scaledSystemFont(compact ? 14 : 18, weight: .regular, design: .monospaced)
                    .foregroundStyle(Theme.dim)
                    .accessibilityIdentifier("romajiHint")
                nextKeys
            } else if session.assistanceOffered {
                // The learner is demonstrably stuck (distinct refusals at the same matcher
                // state). OFFER the answer, never inject it — and price it honestly: this
                // goes through revealHint(), which breaks the combo, scores the word minimally
                // and records the SRS lapse, exactly as the reveal always has.
                //
                // A tap gesture and NOT a Button, for the same reason the ★ above is not one:
                // this sits on the live typing screen, where KeyCaptureView must hold first
                // responder. A focusable control in that view tree can take it and leave the
                // learner typing into nothing. Buttons are fine in the pause overlay, where
                // capture is already suspended; they are not fine here.
                Label(language == "zh" ? "卡住了?看答案" : "Stuck? Show answer",
                      systemImage: "lightbulb")
                    .scaledSystemFont(compact ? 13 : 15, weight: .semibold, design: .rounded)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Theme.gold.opacity(0.16), in: Capsule())
                    .foregroundStyle(Theme.gold)
                    .contentShape(Capsule())
                    .onTapGesture { session.revealHint() }
                    .accessibilityElement()
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("assistanceOffer")
                    .accessibilityLabel(language == "zh" ? "看答案。这个词会计为需要复习"
                                           : "Show the answer. This word will count as needing review")
            }
        }
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
