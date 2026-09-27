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
            let shown = model.liveWPM().rounded()
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
    @Environment(\.dynamicTypeSize) private var typeSize
    let session: GameSession
    let language: String
    /// Whole words per minute over RIDDEN time, from `AppModel.liveWPM`. Zero means "not yet
    /// meaningful" by `RunClock.wpm`'s own convention — under two seconds of riding, or no
    /// correct keystrokes — and is rendered as a dash rather than as a zero, because a rider
    /// three seconds into a ride is not going at 0 wpm.
    var wpm: Double = 0
    var onPause: (() -> Void)? = nil

    /// iPhone width fits ~4 pills; distance, accuracy and speed move to the results screen there
    /// (they're informational, not actionable mid-run). **An iPad drops the same three at the
    /// accessibility sizes** — the gates below read `narrow || typeSize.isAccessibilitySize`, not
    /// this alone — because there the values may not wrap and the iPad's full row outgrew iPad
    /// windows (`RideHUDLayout` has the measurement). Below those sizes an iPad keeps all seven.
    private var narrow: Bool { isPhoneIdiom }

    private var zh: Bool { language == "zh" }

    /// Time Attack is played FOR the score — it is what Game Center's leaderboard takes — so at
    /// the accessibility sizes that ride keeps its score and drops the combo instead, and its
    /// second row drops the level capsule (`RideHUDLayout.fallbackDrops`).
    private var scoreIsTheRide: Bool { session.mode == .timeAttack }

    var body: some View {
        // **Round 3: pills chosen by rules alone still outgrew the screen**, because at the
        // accessibility sizes the values may not wrap and they grow with the ride. Late in a 150- or
        // 500-word list ride ("149/150", "×149") the round-2 row left 20 of the pause button's 44pt on
        // a 320pt Display Zoom iPhone with the level capsule past the left edge, and 26.5 in a 400pt
        // iPad window; Time Attack past 100 words left 36.5 at 320. Rows that did fit often paid with
        // the level capsule, truncated to "…" or clipped to a sliver (375pt with the keyboard down late
        // in a journey, 375–402pt list rides, a 507pt iPad window). So at those sizes the row is
        // offered to `ViewThatFits` twice: as it was, then with one more pill removed
        // (`RideHUDLayout.shows`). Below the accessibility sizes there is no second row and no
        // `ViewThatFits`: the row is 1.32's. (v1.33 pre-submission review, round 3)
        //
        // **`ViewThatFits` compares each row's IDEAL width**, so the first row is kept only while it
        // fits with the level capsule unshrunk: the capsule is never shrunk or "…" in a first row.
        // Round 3 wrote here that the capsule's shrink toward its 0.7 floor counted as room ("taken
        // at 0.8 of its width"); its test had framed the label 10pt tall, which shrank it for HEIGHT.
        // In every accessibility-size render of this HUD the first row was taken exactly when its
        // ideal width fitted (`V133GRideAndDrillLayoutTests` measures the rule). (Round 4)
        //
        // **Round 4: the choice followed values that go down as well as up.** The first row's ideal
        // width held the current combo and the current word's level label, so at tight widths the
        // combo pill left as a streak passed ×9 and came back after every mistake, and a mixed-level
        // list changed rows word to word — each change a rebuilt row and new VoiceOver elements. Late
        // in a 150-word list on a 402pt phone with the keyboard up that row needed 363pt at "—", 369
        // at ×9, 385 at ×10 and 401 at ×149, against 382; on a 430pt phone with it dismissed, 397 on
        // an N1 word and 401 on an N5, against 398. So the first row reserves the widest combo and
        // level label its ride can show (`IdealWidthReserve`, `RideHUDLayout.comboReserve` and
        // `levelReserve`), leaving the progress count and the score, which only grow: the row changes
        // at most once in a ride. That change is a change of view — onDisappear/onAppear fire,
        // measured in round 3 — which costs nothing here: this view holds no state, no appearance
        // hook and no animation. Where VoiceOver focus goes if it sits on a pill at that moment is
        // not measured. `RideHUDLayout` has the measurements. (v1.33 pre-submission review, round 4)
        if typeSize.isAccessibilitySize {
            ViewThatFits(in: .horizontal) {
                row(fallback: false)
                row(fallback: true)
            }
        } else {
            row(fallback: false)
        }
    }

    /// The ride row. `fallback` is the second row `ViewThatFits` is offered at the accessibility
    /// sizes, with one more pill removed (`RideHUDLayout.shows`); below those sizes it is never asked
    /// for, and it removes nothing there either.
    private func row(fallback: Bool) -> some View {
        HStack(spacing: narrow ? 8 : 14) {
            // The conjugation HUD's v1.31 fix, which this row never got (v1.33 §B G). At AX5 —
            // capped to AX1 here — a journey ride's progress pill read "0/1" over "2" (simulator
            // pass 2026-09-17, iPhone 17 Pro 402pt, `A_game-journey_en_ax5.png`): nothing in the
            // row had a line limit, so SwiftUI resolved a row wider than the screen by wrapping
            // every Text in it. ConjugationGameView's HUD comment says why the answer is "shrink,
            // never wrap".
            //
            // **Here that holds at the accessibility sizes only**, where `RideHUDLayout` hides one
            // pill, an iPad also hides distance, accuracy and speed (round 2, below), and `body`
            // falls back to a row with one pill fewer (round 3), so a row that cannot wrap fits a
            // phone of 320pt or wider and an iPad window of 400pt or wider in every ride measured,
            // up to the 500-word list cap (`RideHUDLayout`); narrower iPad windows were not
            // measured in round 3. Below them no pill is hidden, and a row that may not wrap does
            // not get narrower — it pushes its last item, the pause button, off the screen. The
            // results-and-ride review measured this HUDBar hosted on macOS: late in a journey ride
            // the row needs ~752pt, so with the limits at every size an iPad mini in portrait
            // (744pt) and iPad Split View (678pt and narrower) lost the pause button partly or
            // wholly at the DEFAULT size — for a touch-only rider the only way to pause or end the
            // ride — and by scaled-font arithmetic so did 375/393/402pt iPhones at xxLarge and
            // xxxLarge, the ordinary Text Size slider. In 1.32 those values wrapped and the button
            // stayed on screen. So below the accessibility sizes this capsule and the values in
            // `stat` carry 1.32's modifiers again: no line limit, no shrink, no fixed size
            // (`lineLimit(nil)`, `minimumScaleFactor(1)` and `fixedSize` in neither axis are the
            // defaults — `V133GRideAndDrillLayoutTests` measures that). (v1.33 review)
            //
            // **Round 2: the accessibility-size row had only been fitted to a phone.** On an iPad
            // `narrow` is false, so that row kept distance, accuracy and speed as well, and with its
            // values unable to wrap it measured 758pt at the start of a journey, 846pt late in one
            // and 862pt late in a long Time Attack at AX1: the pause button partly or wholly off an
            // iPad mini in portrait (744pt) and every narrower Split View or Stage Manager window,
            // and partly off a portrait 820/834pt iPad late in a ride. So at these sizes an iPad
            // shows the phone's pills (the two gates below); `RideHUDLayout` has the measurements.
            // (v1.33 pre-submission review, round 2)
            //
            // Round 4: what the first row reserves at the accessibility sizes — nothing below them and
            // nothing in the second row (`RideHUDLayout.comboReserve`). The level capsule's reserve
            // sits on its Text before the font, so the placeholders are set in that font; the combo's
            // is inside `stat`. (v1.33 pre-submission review, round 4)
            let levels = RideHUDLayout.levelReserve(typeSize, fallback: fallback, words: session.wordList)
            let combos = RideHUDLayout.comboReserve(typeSize, fallback: fallback, wordCount: session.wordCount)
            if RideHUDLayout.shows(.level, typeSize, scoreIsTheRide: scoreIsTheRide, fallback: fallback) {
                Text(session.currentLevelLabel)
                    .reservingIdealWidth(for: levels)
                    .scaledSystemFont(14, weight: .heavy, design: .rounded)
                    .foregroundStyle(.white)
                    .lineLimit(typeSize.isAccessibilitySize ? 1 : nil)
                    .minimumScaleFactor(typeSize.isAccessibilitySize ? 0.7 : 1)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Theme.accent2.opacity(0.85), in: Capsule())
                    .accessibilityLabel(zh ? "等级 \(session.currentLevelLabel)" : "Level \(session.currentLevelLabel)")
            }
            if RideHUDLayout.shows(.score, typeSize, scoreIsTheRide: scoreIsTheRide, fallback: fallback) {
                stat(icon: "star.fill", value: "\(session.score)", tint: Theme.gold,
                     label: zh ? "得分" : "Score")
            }
            if RideHUDLayout.shows(.combo, typeSize, scoreIsTheRide: scoreIsTheRide, fallback: fallback) {
                stat(icon: "flame.fill",
                     value: RideHUDLayout.comboValue(session.combo),
                     tint: session.combo >= 2 ? Theme.accent : Theme.dim,
                     label: zh ? "连击" : "Combo",
                     spoken: RideHUDSpoken.comboWords(session.combo, zh: zh),
                     reserving: combos)
            }
            // At the accessibility sizes the Spacer may collapse, as `ConjugationHUD`'s does: its
            // default minimum was the last 8pt a 320pt Display Zoom iPhone lacked late in a journey
            // (row 328pt against 320, the pause button 4pt off the edge). `minLength: nil` is the
            // same value `Spacer()` builds — its only initializer defaults to nil — so below them
            // this is 1.32's Spacer. (v1.33 pre-submission review, round 2)
            Spacer(minLength: typeSize.isAccessibilitySize ? 0 : nil)
            // A phone's rule at every size, and an iPad's at the accessibility sizes: see `narrow`.
            if !(narrow || typeSize.isAccessibilitySize) {
                stat(icon: "bicycle", value: "\(Int(session.distanceMeters)) m", tint: Theme.accent2,
                     label: zh ? "距离" : "Distance",
                     spoken: RideHUDSpoken.distanceWords(session.distanceMeters, zh: zh))
            }
            stat(icon: "checkmark.circle.fill",
                 // Time Attack shows a bare count: its queue is a pool, not a target, and the
                 // timer bar directly above is already the progress this mode has.
                 value: session.mode.queueLengthIsTheTarget
                     ? "\(session.wordsCompleted)/\(session.wordCount)"
                     : "\(session.wordsCompleted)",
                 tint: Theme.done,
                 // One run must not show three units for one number. v1.25 §B taught the
                 // results screen to say "Sentences" on a sentence or dictation ride, and this
                 // HUD kept saying "Words" for the same queue — so mid-ride read "Words 2/5"
                 // and the results screen read "Sentences 5". The Chinese has always said
                 // 进度 ("progress"), which is mode-neutral and therefore already right in all
                 // six modes: one language had solved this and the other had not. (v1.26 §B3.)
                 label: session.mode.hudProgressLabel(zh: zh),
                 // After its own value, the values THIS row hides — the one element drawn in
                 // every row is where a VoiceOver rider can still hear them. Nil, and so
                 // nothing, below the accessibility sizes (`RideHUDSpoken`). (v1.34 §B3) The
                 // joining is `progressWords`, not an expression here: written inline, one pair of
                 // parentheses decided whether the suffix followed the whole ternary or only Time
                 // Attack's branch, and no test could see which. (v1.34 §B3, review round 2)
                 spoken: RideHUDSpoken.progressWords(
                     queueLengthIsTheTarget: session.mode.queueLengthIsTheTarget,
                     completed: session.wordsCompleted, count: session.wordCount, zh: zh,
                     hidden: RideHUDSpoken.hiddenValues(typeSize: typeSize, scoreIsTheRide: scoreIsTheRide,
                                                        fallback: fallback, narrow: narrow,
                                                        level: session.currentLevelLabel,
                                                        score: session.score, combo: session.combo,
                                                        distanceMeters: session.distanceMeters,
                                                        accuracy: session.accuracy, wpm: wpm, zh: zh)))
                .accessibilityIdentifier("hudProgress")
            if !(narrow || typeSize.isAccessibilitySize) {
                stat(icon: "scope",
                     value: RideHUDSpoken.accuracyWords(session.accuracy), tint: .white,
                     label: zh ? "正确率" : "Accuracy")
                // Informational, so it follows the same width rule as distance and accuracy:
                // the fixed ride layout fits about four pills on a phone and cannot reflow, and
                // a shattered HUD is device-verified territory (Gate E). A phone rider — and an
                // iPad rider at the accessibility sizes — still gets the number on the results
                // screen and in the Ride Log, which is where it was already.
                stat(icon: "speedometer",
                     value: RideHUDSpoken.speedValue(wpm), tint: Theme.accent,
                     label: zh ? "速度" : "Speed",
                     spoken: RideHUDSpoken.speedWords(wpm, zh: zh))
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
    /// where the on-screen glyph would read poorly (e.g. "—", "150 m"). `reserving`: values whose
    /// width the pill's ideal width covers without drawing them (`reservingIdealWidth`).
    private func stat(icon: String, value: String, tint: Color,
                      label: String, spoken: String? = nil, reserving: [String] = []) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(tint)
            // "0/12" wrapping to "0/1" over "2" is not a smaller number, it is a broken pill —
            // the same two lines ConjugationHUD.stat carries since v1.31. (v1.33 §B G.) At the
            // accessibility sizes only: below them a value that cannot wrap pushes the pause button
            // off a narrow screen at the default size, which is worse — see the level capsule.
            //
            // The reserve goes AFTER `fixedSize`, which proposes no width to what it wraps: inside
            // it the reserve would be asked for its ideal at every layout, the pill drawn at the
            // widest value's width. (v1.33 pre-submission review, round 4 — measured in
            // `V133GRideAndDrillLayoutTests`.)
            Text(value).foregroundStyle(.white).monospacedDigit()
                .lineLimit(typeSize.isAccessibilitySize ? 1 : nil)
                .fixedSize(horizontal: typeSize.isAccessibilitySize, vertical: false)
                .reservingIdealWidth(for: reserving) { Text($0).monospacedDigit() }
        }
        .padding(.horizontal, narrow ? 9 : 12).padding(.vertical, 7)
        .background(.black.opacity(0.42), in: Capsule())
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(spoken ?? value)
    }
}

/// What the two game HUDs — the ride's `HUDBar` and the drill's `ConjugationHUD` — drop at the
/// accessibility text sizes, decided once so the two rows cannot drift apart. (v1.33 §B G.)
///
/// **One line limit is not enough on its own.** With the v1.31 fix a value can no longer wrap,
/// but a row of unwrappable pills that is wider than the phone is pushed past both edges instead.
/// Measured with CoreText at AX1 (both game screens cap there), pill widths calibrated against the
/// 2026-09-17 simulator shot `A_game-conjugation_en_ax5.png` on a 402pt iPhone 17 Pro (the model
/// read 4.7pt wide per pill; the figures below are corrected). Room for the row: 382pt on a 402pt
/// phone with the keyboard up, 373 on a 393pt phone, 361 on a 393pt phone with it dismissed.
///
/// | ride row (level, score, combo, progress, pause) | all pills | combo hidden | score hidden |
/// |---|---|---|---|
/// | start: ★0, —, 0/20 | 391 | 313 | 315 |
/// | mid: ★450, ×4, 7/20 | 429 | 345 | 321 |
/// | late: ★2400, ×10, 19/20 | 477 | **377** | 353 |
///
/// The same fact is why the ride row carries its one-line limit at these sizes only (`HUDBar`):
/// below them nothing here hides a pill, and an unwrappable row pushed the pause button off an iPad
/// mini in portrait at the default size.
///
/// **Everything above is a phone's row, and an iPad's was never checked** — found by round 2 of
/// the pre-submission review, 2026-09-18. `HUDBar.narrow` is the device, so an iPad's row also held
/// distance, accuracy and speed, and at AX1 with its values unable to wrap it was 758pt wide at the
/// start of a journey, 792 mid-way, 846 late, and 825 / 862 late in a Time Attack with a four /
/// five-digit score. The pause button was partly or wholly off every iPad window up to 744pt wide
/// (an iPad mini in portrait) and partly off an 820 or 834pt portrait iPad late in a ride. So at
/// these sizes an iPad hides those three pills too, as a phone does at every size, and keeps its
/// own spacing and fonts: the same five rides then need 337 / 345 / 381 / 360 / 378pt on one line
/// (49–49.5pt tall), and for those rides the pause button is wholly on screen from 400 to 1376pt
/// with the keyboard up or down. Measured with this `HUDBar` hosted on macOS in `GameView`'s
/// padding, every `scaledSystemFont` scaled by 28/17 (macOS does not scale `@ScaledMetric`), after
/// the Spacer change below. Below the accessibility sizes the same instrument read identical rows
/// before and after, on a phone and on an iPad. **That held for 20-word rides and Time Attack under
/// 100 words only** (round 3, below): a 150-word list ride late on left 26.5 of the 44pt at 400pt.
///
/// **And a phone's row can use all of its width.** Its Spacer may collapse at these sizes (as the
/// drill's does), because a 320pt Display Zoom iPhone late in a journey measured 328pt — the pause
/// button 4pt past the edge — and 320 without the Spacer's default minimum. A five-digit Time Attack
/// is 318.5. **Round 3 corrected what "fits" meant there:** the 320pt row fitted only by squeezing
/// the level capsule to a clipped 20pt sliver (early in a journey, to "…"), and a ride of 100 words
/// or more did not fit at all — 20 of the 44pt at 149/150, 36 at 99/150, 36.5 in a 110-word Time
/// Attack.
///
/// The drill row has the same pills with a "Verbs" badge in the level's place, and what matters
/// there is how much is left for the badge late in a drill (★1200, ×10, 11/12) on the three
/// phones: 58 / 49 / 37 with combo hidden, 82 / 73 / 61 with score hidden. "Verbs" needs 66 at its
/// 0.7 shrink floor.
///
/// **So the score goes, not the combo** — the combo was the first candidate, and the arithmetic
/// is what moved it. The score is the pill whose width grows with the run (one digit to four);
/// the combo is bounded at three characters in a 20-word ride (not in a word-list ride, where it
/// reaches "×499" — round 3, below). Hiding the combo leaves the ride row 4pt over on a
/// 393pt phone and 16pt over with the keyboard dismissed by the end of a good ride, and the drill
/// badge truncated again; hiding the score fits every case above (the drill's 61 becomes 69 once
/// its spacer may collapse — see `ConjugationHUD`). It is also the least essential
/// by the rule `HUDBar` already applies to distance, accuracy and speed — informational,
/// not actionable mid-run, and the rider gets the number on the results screen and in the Ride
/// Log. The live combo is not recoverable afterwards (results keep only the best one).
///
/// **Except in Time Attack**, added at merge (2026-09-17): there the score is not informational —
/// it is the point of the mode and what Game Center's leaderboard receives — and the 1.32
/// simulator pass saw that HUD fit at AX5 already. Its progress pill is a bare count ("37", not
/// "19/20"), roughly 45pt narrower than the ride row measured above, so with the combo hidden
/// instead it comes to about 332pt late in a run (≈350 with a five-digit score) against 361.
/// Arithmetic again, from the table's figures; the simulator pass re-shoots Time Attack at AX5.
///
/// **Round 3: the rules alone do not fit, because the values grow** — found by round 2's review,
/// 2026-09-18. A word-list ride takes every word in the list (up to 500), so late on the progress
/// pill reads "149/150" or "499/500" and the combo "×149" or "×499", and Time Attack's count passes
/// 100. So `HUDBar` offers `ViewThatFits` a second row that gives up one pill more,
/// `fallbackDrops`: the combo where the queue is the target (its score is already hidden), the
/// level capsule in Time Attack (its combo is already hidden, and the score is the point). Progress
/// and pause are never given up. Pause button visible, of 44pt, at AX1, worst of keyboard up and
/// down, round 2 → round 3:
///
/// | ride | 320pt phone | 375 | 393 / 402 | 400pt iPad window | 507 |
/// |---|---|---|---|---|---|
/// | list 149/150 ×149, 499/500 ×499 | 20 → 44 | 44 "…" → 44 | 44 "…" → 44 | 26.5 → 44 | 44 "…" → 44 |
/// | list 99/150 ×99 | 36 → 44 | 44 "…" → 44 | 44 → 44 | 44 "…" → 44 | 44 → 44 |
/// | Time Attack, 110 words, ★23599 | 36.5 → 44 | 44 "…" → 44 | 44 → 44 | 44 "…" → 44 | 44 → 44 |
/// | journey late (19/20 ×19), N5 or N4 | 44 sliver → 44 | 44 "…" → 44 | 44 → 44 | 44 "…" → 44 | 44 → 44 |
///
/// ("…": the level capsule truncated in at least one keyboard position.) On every phone from 320 to
/// 440pt and every iPad window from 400 to 1376pt, in all 14 rides measured — 20-word journeys
/// early, mid-way and late at N5 and N4; list rides at 99/150, 149/150 and 499/500; Time Attack at
/// 37, 70 and 110 words; sentence and dictation at 4/5 — the pause button is wholly on screen, no
/// value wraps (rows 45pt tall on a phone, 49.5 on an iPad), and the level capsule is either whole
/// or, in Time Attack's second row, absent: never shrunk, never "…". The second row is taken on a
/// 320pt phone in every ride; on a 375pt phone late in a journey (keyboard down), in list rides and
/// in Time Attack from 70 words; at 393–430pt only in list rides and (393) a 110-word Time Attack;
/// on a 400pt iPad window in every ride, with the keyboard down at least; at 507pt only late in a
/// 150- or 500-word list ride with the keyboard down. In those rides the first row always fits from
/// 600pt up and on a 440pt phone, and wherever the first row is taken the HUD is pixel-identical to
/// round 2's. AX5 renders as AX1. **Not fitted:** a grandfathered default list over the 500-word
/// cap — at "1199/1200" on a 320pt phone, or in a 400pt iPad window with the keyboard down, neither
/// row fits; the second is kept, the pause button stays whole and the level capsule reads "…".
///
/// **Round 4: the row changed as the values changed, not only as they grew** — found by round 3's
/// review, 2026-09-18. `ViewThatFits` compares each row's IDEAL width, and the first row's held the
/// current combo and the current word's level label, so at tight widths the combo pill left as a
/// streak passed ×9 and came back after every mistake, and a list mixing levels changed rows word to
/// word — and every change rebuilds the row, handing VoiceOver new elements. Late in a 150-word list
/// ride on a 402pt phone with the keyboard up that row needed 363pt at "—", 369 at ×9, 385 at ×10
/// and 401 at ×149, against the 382 available; on a 430pt phone with the keyboard dismissed, 397 on
/// an N1 word and 401 on an N5, against 398. So at these sizes the first row reserves the widest
/// value each of those two pills can show in THIS ride (`comboReserve`, `levelReserve`,
/// `IdealWidthReserve`), and what is left in its ideal width is the progress count and the score,
/// which only ever grow. The reserve is answered only when no width is proposed, so it moves no
/// drawn pixel.
///
/// **So the row changes at most once in a ride**, measured by stepping whole rides key by key with
/// the session mutated as a rider would — clean rides, and rides with a wrong key at the end of
/// streaks of 1 to 40 words — over 10 rides (20-word journeys at N5, at N4 and over mixed levels;
/// 150-word lists at N5 and mixed; a 300-word Time Attack; a five-sentence ride) at 12 widths and
/// keyboard positions (320, 375, 402 and 430pt phones; 400 and 507pt iPad windows): 120 rides,
/// 10,248 HUD states. Round 3's rows changed 143 times over the same rides — 22 times in one ride (a
/// mixed-level 150-word list on a 430pt phone with the keyboard down) and 18 in another (that list
/// at 402pt with the keyboard up). This row changed 26 times in 120 rides, never more than once, and
/// always from the first row to the second: each change fell on the one key where the progress count
/// or the score gained a digit — 16 at 9→10 words, 5 at 99→100, and 5 on a score passing 100, 1,000
/// or 10,000. **A score can pass 100 on the very first word**, so in a Time Attack ride at 320pt or
/// in a 400pt iPad window with the keyboard down the first row lasts exactly one word (three of the
/// 26; named because round 4's first draft of this paragraph implied the change always falls well
/// into a ride, and the review counted the keys). The pause
/// button was whole — 44 of 44pt — in all 10,248 states on both, and no first row shrank its level
/// capsule.
///
/// The row a ride settles on is round 3's table with four additions: a 99/150 list ride now takes
/// the second row at 393pt with the keyboard up (it already did with it down), at 402pt either way,
/// and in a 507pt iPad window with the keyboard down; and a journey takes the second row from its
/// start, not from its second word, in a 400pt iPad window with the keyboard up.
/// Re-measured in full — 28 rides × phones 320–440pt and iPad windows 380–1376pt × keyboard up and
/// down, 952 rows, plus 112 on macOS — the pause button is 44 of 44pt in every row, nothing wraps,
/// the first row is taken exactly when its ideal width fits, and AX5 renders as AX1. 698 rows keep
/// round 3's first row and are byte-identical to it; 233 keep round 3's second row, identical; in 21
/// the reserve moves the ride to its second row, with the pause button whole and the level capsule
/// full. Below the accessibility sizes, 7,448 renders on phone, iPad and Mac widths at the 7 sizes
/// are byte-identical to 1.32's (two first renders in a process differed and re-rendered identical,
/// as in round 3). **iPad windows under 400pt**, round 3's open note: at 380pt the pause button is
/// whole in all 28 rides both ways, and a late 150- or 500-word list ride's second row shrinks the
/// level capsule to 0.83 of its width, exactly as round 3's row does; 320pt windows are still
/// unmeasured. (v1.33 pre-submission review, round 4)
///
/// Instrument: this `HUDBar` rendered with `ImageRenderer` on macOS inside a copy of `GameView`'s
/// padding, its fonts scaled from the environment's size through iOS's body-size table so
/// `GameView`'s cap clamps them, items read by pixel segmentation against the same row 2400pt wide,
/// the row drawn cross-checked against `ViewThatFits`' own test in all 1080 accessibility-size
/// cases. Below the accessibility sizes the 3780 renders on phone, iPad and Mac widths were
/// byte-identical to 1.32's (the sweep's one mismatch re-rendered identical eight times).
/// (v1.33 pre-submission review, round 3.) Round 4 read the same instrument, with a verbatim copy of
/// round 3's `HUDBar` beside this one as the before, and the session stepped key by key.
///
/// `ImageRenderer` ignores Dynamic Type on its own, so every figure here is an instrument's, not a
/// device's: the AX5 simulator pass re-shoots both HUDs.
enum RideHUDLayout {
    /// The ride row's pills a rule may hide. The progress pill and the pause button are not cases, on
    /// purpose: the words-done count is the pill whose wrapping started §B G, and pause is a touch
    /// rider's only way to stop or end a ride. (`V133GRideAndDrillLayoutTests` pins both
    /// unconditional in `HUDBar`.)
    enum Pill: CaseIterable { case level, score, combo }

    /// Whether the ride row shows `pill`. Below the accessibility sizes, always, whatever `fallback`
    /// says — so the default-size HUD is exactly what it was. At them the score goes, except in Time
    /// Attack (`scoreIsTheRide`), which keeps its score and drops the combo; and `fallback` — the
    /// second row `HUDBar` offers `ViewThatFits` — gives up one pill more, `fallbackDrops`.
    static func shows(_ pill: Pill, _ typeSize: DynamicTypeSize, scoreIsTheRide: Bool, fallback: Bool) -> Bool {
        guard typeSize.isAccessibilitySize else { return true }
        if fallback, pill == fallbackDrops(scoreIsTheRide: scoreIsTheRide) { return false }
        switch pill {
        case .level: return true
        case .score: return scoreIsTheRide
        case .combo: return !scoreIsTheRide
        }
    }

    /// The pill the second row gives up. A ride whose queue is the target keeps its level and drops
    /// the combo (its score is already hidden); Time Attack keeps the score — the point of the mode —
    /// and drops the level (its combo is already hidden).
    static func fallbackDrops(scoreIsTheRide: Bool) -> Pill { scoreIsTheRide ? .level : .combo }

    /// The drill's score pill (`ConjugationHUD`): the ride's rule for a ride whose score is not the
    /// point. The drill has no second row.
    static func showsScore(_ typeSize: DynamicTypeSize) -> Bool {
        shows(.score, typeSize, scoreIsTheRide: false, fallback: false)
    }

    /// Whether the ride row shows distance, accuracy and speed: never on a phone (`HUDBar.narrow`
    /// — its width fits four pills, and the three are on the results screen), and on an iPad below
    /// the accessibility sizes only (round 2, above). `HUDBar` draws the three behind this
    /// expression written out — `V133GRideAndDrillLayoutTests` pins that gate's text, so the row
    /// keeps the literal — and `RideHUDSpoken` asks here; `V134B3HUDSpokenTests` holds the two to
    /// one truth table, so they cannot drift apart. (v1.34 §B3)
    static func showsInformational(narrow: Bool, _ typeSize: DynamicTypeSize) -> Bool {
        !(narrow || typeSize.isAccessibilitySize)
    }

    /// The combo pill's value: a dash until a streak of two, then "×n". Here rather than in `HUDBar`
    /// so the widths `comboReserve` reserves are the strings the pill draws.
    static func comboValue(_ combo: Int) -> String { combo >= 2 ? "×\(combo)" : "—" }

    /// The combo values the ride row's first row reserves room for at the accessibility sizes
    /// (round 4, `IdealWidthReserve`): the dash, and the longest streak the ride can reach. A streak
    /// grows by one per word completed and restarts on a mistake, a reveal or a skip
    /// (`GameSession`), so it cannot pass `wordCount`; the value's digits are tabular
    /// (`monospacedDigit`), so "×\(wordCount)" is as wide as any value of as many digits and wider than
    /// any of fewer — both measured in `V133GRideAndDrillLayoutTests`. Nothing below the accessibility
    /// sizes, where there is no `ViewThatFits`, and nothing for the second row, its last child, which
    /// is never measured to be chosen. Time Attack never shows this pill at those sizes.
    static func comboReserve(_ typeSize: DynamicTypeSize, fallback: Bool, wordCount: Int) -> [String] {
        guard typeSize.isAccessibilitySize, !fallback else { return [] }
        return wordCount >= 2 ? [comboValue(0), comboValue(wordCount)] : [comboValue(0)]
    }

    /// The level labels the first row reserves room for, on the same terms as `comboReserve`: one
    /// per JLPT level in the ride's queue, because the capsule shows the current word's
    /// (`GameSession.currentLevelLabel`) and "N1" is narrower than "N5". A one-level ride reserves
    /// its own label, which changes nothing.
    static func levelReserve(_ typeSize: DynamicTypeSize, fallback: Bool, words: [VocabEntry]) -> [String] {
        guard typeSize.isAccessibilitySize, !fallback else { return [] }
        return Set(words.map(\.jlpt)).sorted { $0.rawValue < $1.rawValue }.map(\.label)
    }
}

/// What VoiceOver hears of the values the accessibility-size row hides. (v1.34 §B3)
///
/// 1.33 hid the score pill at the accessibility sizes (Time Attack: the combo), one pill more in
/// the second row, and on an iPad also distance, accuracy and speed (`RideHUDLayout`,
/// `HUDBar.narrow`). That kept a touch rider's pause button on screen and took the numbers away
/// from a VoiceOver rider at the same sizes, who had heard each as its pill's own
/// `accessibilityValue` (v1.33 §G, deferred by name). So the one pill drawn in every row —
/// progress — carries the hidden pills' values after its own: "6 of 12, score 891, combo 6". The
/// spoken forms are the pills' — the same functions below that the pills call for their `value:` and
/// `spoken:` (review round 2) — so a rider hears the same words whichever row `ViewThatFits` draws;
/// `V134B3HUDSpokenTests` pins both call sites.
///
/// **Nil below the accessibility sizes**, where nothing is hidden, so the progress pill's value is
/// byte for byte what it was and the default-size renders and VoiceOver strings cannot change. A
/// value is spoken when this row hides it AND the default-size row shows it: a phone's distance,
/// accuracy and speed have never been in its row at any size, so on a phone the suffix names only
/// what the size took. The level capsule counts as a pill here although it has no
/// `accessibilityValue` — its label, "Level N3", is the value: Time Attack's second row drops it,
/// and a Time Attack at "All" (混合) changes level word by word. This is a pure function with a
/// table test and a pinned call site, and deliberately not a hosted test of the live accessibility
/// tree, which `NSHostingView` does not expose without an assistive client (v1.33 §G).
enum RideHUDSpoken {
    /// The size the comparison is made against: SwiftUI's default, at which no rule hides a pill.
    static let defaultSize: DynamicTypeSize = .large

    /// The suffix the progress pill's spoken value carries: each hidden pill's spoken value in HUD
    /// order (level, score, combo, distance, accuracy, speed), each led by the list separator — ", " in
    /// English, "、" in Chinese — so the call site appends it as it is. Nil when this row hides
    /// nothing the default-size row shows, which is every size below the accessibility sizes.
    static func hiddenValues(typeSize: DynamicTypeSize, scoreIsTheRide: Bool, fallback: Bool, narrow: Bool,
                             level: String, score: Int, combo: Int, distanceMeters: Double, accuracy: Double,
                             wpm: Double, zh: Bool) -> String? {
        // The rules are `RideHUDLayout`'s, asked twice: at this size and at the default size.
        func hid(_ shows: (DynamicTypeSize) -> Bool) -> Bool { !shows(typeSize) && shows(defaultSize) }
        var parts: [String] = []
        // The capsule's own label, "Level N3" / "等级 N3"; nothing when there is no current word.
        if !level.isEmpty,
           hid({ RideHUDLayout.shows(.level, $0, scoreIsTheRide: scoreIsTheRide, fallback: fallback) }) {
            parts.append(zh ? "等级 \(level)" : "level \(level)")
        }
        if hid({ RideHUDLayout.shows(.score, $0, scoreIsTheRide: scoreIsTheRide, fallback: fallback) }) {
            parts.append(zh ? "得分 \(score)" : "score \(score)")
        }
        // Each value in its pill's own words, from the one function the pill itself calls: the
        // composer formats no number of its own. (v1.34 §B3, review round 2)
        if hid({ RideHUDLayout.shows(.combo, $0, scoreIsTheRide: scoreIsTheRide, fallback: fallback) }) {
            parts.append((zh ? "连击 " : "combo ") + comboWords(combo, zh: zh))
        }
        if hid({ RideHUDLayout.showsInformational(narrow: narrow, $0) }) {
            parts.append((zh ? "距离 " : "distance ") + distanceWords(distanceMeters, zh: zh))
            parts.append((zh ? "正确率 " : "accuracy ") + accuracyWords(accuracy))
            parts.append((zh ? "速度 " : "speed ") + speedWords(wpm, zh: zh))
        }
        guard !parts.isEmpty else { return nil }
        let separator = zh ? "、" : ", "
        return parts.map { separator + $0 }.joined()
    }

    // MARK: The pills' words — one function each, called by the pill and by the composer

    /// Round 2 of the v1.34 review: the composer had written each pill's form out again, so the two
    /// could drift with every test green — rounding the accuracy in one place (0.978 heard as "98%"
    /// while the pill and the results screen draw "97%"), or `wpm > 1` against the pill's `>= 1`
    /// (exactly 1.0 heard as "not yet" while the pill says "1 words per minute"). Now each form is
    /// one function that `HUDBar`'s pill calls for what it draws or speaks and `hiddenValues` calls
    /// for what it appends; `V134B3HUDSpokenTests` pins both call sites and writes the boundary
    /// cases out.

    /// The progress pill's spoken value: its own count — "6 of 12" / "6 / 12" in a ride whose queue
    /// is the target, the bare count in Time Attack — followed by `hidden`, nil as nothing. The
    /// suffix follows the WHOLE count, whichever branch it came from.
    static func progressWords(queueLengthIsTheTarget: Bool, completed: Int, count: Int, zh: Bool,
                              hidden: String?) -> String {
        let own = queueLengthIsTheTarget ? (zh ? "\(completed) / \(count)" : "\(completed) of \(count)")
                                         : "\(completed)"
        return own + (hidden ?? "")
    }

    /// The combo pill's spoken value: the streak from two, "none" / 无 below (the pill draws "—").
    static func comboWords(_ combo: Int, zh: Bool) -> String {
        combo >= 2 ? "\(combo)" : (zh ? "无" : "none")
    }

    /// The distance pill's spoken value, whole metres truncated as the drawn "150 m" is.
    static func distanceWords(_ meters: Double, zh: Bool) -> String {
        zh ? "\(Int(meters)) 米" : "\(Int(meters)) meters"
    }

    /// The accuracy pill's value, drawn and spoken: the percentage TRUNCATED, as `Int(_:)` does and
    /// as the results screen draws it (0.978 is "97%"). The pill has no `spoken:`; VoiceOver reads
    /// this.
    static func accuracyWords(_ accuracy: Double) -> String {
        "\(Int(accuracy * 100))%"
    }

    /// Whether the speed is a number yet: from 1 wpm — below it the pill draws "—" and speaks "not
    /// yet". 1.0 itself is a number. The 1 is this function's own threshold, not `RunClock.wpm`'s:
    /// RunClock says "not meaningful" only with 0 (under two seconds of riding, or no correct
    /// keystroke), and `GameView`'s ticker hands the HUD `liveWPM` rounded to a whole number, so a
    /// raw 0.3 arrives here as 0 and a raw 0.5 as 1.
    static func paceIsKnown(_ wpm: Double) -> Bool { wpm >= 1 }

    /// The speed pill's drawn value: whole words per minute, "—" before `paceIsKnown`.
    static func speedValue(_ wpm: Double) -> String {
        paceIsKnown(wpm) ? "\(Int(wpm))" : "—"
    }

    /// The speed pill's spoken value, built on `speedValue`'s number.
    static func speedWords(_ wpm: Double, zh: Bool) -> String {
        guard paceIsKnown(wpm) else { return zh ? "尚未开始计算" : "not yet" }
        return zh ? "每分钟 \(speedValue(wpm)) 词" : "\(speedValue(wpm)) words per minute"
    }
}

/// A view whose IDEAL width — its size when no width is proposed, which is what `ViewThatFits`
/// compares — is the widest of its subviews, and whose size under any real proposal is its first
/// subview's alone. The others are hidden placeholders: they are measured, never drawn.
///
/// **Round 4 of the pre-submission review.** A hidden placeholder in a `ZStack` would reserve the
/// same width, and move what is drawn: the level capsule's `ZStack` would push the combo pill right,
/// and a pill's own background would grow. Answering the reserve only when no width is proposed
/// leaves every drawn frame where it was — `HStack` proposes real widths when it places its children
/// — so wherever the first row is taken it renders byte for byte as round 3's (`RideHUDLayout` has
/// the measurement; `V133GRideAndDrillLayoutTests` measures the Layout on its own).
struct IdealWidthReserve: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let size = content.sizeThatFits(proposal)
        guard proposal.width == nil else { return size }
        let widest = subviews.dropFirst().map { $0.sizeThatFits(proposal).width }.max() ?? 0
        return CGSize(width: max(size.width, widest), height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(at: bounds.origin, anchor: .topLeading, proposal: proposal)
        }
    }
}

extension View {
    /// This view inside `IdealWidthReserve`, with one hidden placeholder per value (`placeholder`
    /// builds it; the environment's font reaches it, a `Text` modifier on this view does not). No
    /// values, no change: the view itself, as before round 4.
    @ViewBuilder
    func reservingIdealWidth(for values: [String],
                             _ placeholder: @escaping (String) -> Text = { Text($0) }) -> some View {
        if values.isEmpty {
            self
        } else {
            IdealWidthReserve {
                self
                ForEach(values, id: \.self) { placeholder($0).hidden().accessibilityHidden(true) }
            }
        }
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
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The corner controls' glyph size — the ★ here and `SpeakButton` opposite it both use
    /// `scaledSystemFont(compact ? 15 : 18)` — so the room reserved for them grows with them.
    @ScaledMetric(relativeTo: .body) private var cornerGlyphCompact: CGFloat = 15
    @ScaledMetric(relativeTo: .body) private var cornerGlyphRegular: CGFloat = 18
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
                // Same defect as `kanaReading` below and the same reason: this is one line for
                // a WORD and a whole sentence in sentence/dictation mode. It was truncating to
                // 「授業でこの新しい辞書を使…」, and with the software keyboard up the card drops
                // the full sentence it repeats underneath — so on a phone, mid-run, the
                // truncated line was the ONLY copy on screen.
                Text(session.currentSurface ?? "")
                    .scaledSystemFont(compact ? 40 : 64, weight: .bold, relativeTo: .largeTitle)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.4)   // long compounds shrink instead of clipping (narrow screens)
                    // The ★ and the speaker are OVERLAYS in the card's top corners, and this is
                    // the line they sit on. At the default size a sentence's first line stops
                    // short of them; at AX5 (capped to AX1) the ★ sat on 「ギ」 of
                    // 「フォークでケーキを食べます。」 and on 「て」 of 「白いシャツを着ています。」
                    // (simulator pass 2026-09-17, `B_mode-sentence_game_{en,zh}_ax5.png`). So at
                    // the accessibility sizes the line is inset by exactly how far a corner control
                    // reaches past the card's own padding, on both sides so it stays centred.
                    // (v1.33 §B G.)
                    //
                    // And on a SENTENCE card with the keyboard up, at every size (simulator pass,
                    // 2026-09-27). "Stops short of them" was vertical: the card centres its rows
                    // in the height it is given, and the slack above the surface kept a full
                    // first line below the ★. v1.34 §B5's second hint line spends that slack —
                    // late in a long sentence none is left — and the ★ sat on 「魅」 of
                    // 「新しい事業の将来性に魅力を感じて投資を決めた。」 on the 402pt phone. Only
                    // sentence cards carry a hint long enough to wrap, and only the keyboard-up
                    // card lost the slack (keyboard down, 1.33 and 1.34 lay out alike), so that is
                    // where the rule now also applies. Zero on every other card below the
                    // accessibility sizes. The cost, measured: a long sentence's surface is drawn
                    // in 298pt instead of 354pt there, so it shrinks ~16% — PLAN-V1.34 §B5.
                    .padding(.horizontal, RideCardLayout.cornerControlReserve(
                        glyphPoints: compact ? cornerGlyphCompact : cornerGlyphRegular,
                        controlPadding: compact ? 10 : 14,
                        cardPadding: compact ? 14 : 24,
                        accessibilitySize: typeSize.isAccessibilitySize,
                        sentenceUnderKeyboard: compact && session.mode == .sentence))

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
    ///
    /// **IT MUST WRAP, AND UNTIL v1.31 IT DID NOT.** The comment above was written for long
    /// WORDS, where one shrinking line is right. v1.18 then sent whole SENTENCES through the
    /// same view, and a sentence does not fit one phone line at any scale: 授業でこの新しい辞書
    /// を使います。 rendered as 「じゅぎょうでこのあたらしいじしょをつか…」 and stayed that way as
    /// the learner typed, so once the caret passed the ellipsis **they were typing blind** —
    /// the kana they still owed were off the end and the romaji buffer below was truncated too.
    ///
    /// `PracticeView` fixed exactly this in v1.16 §D and its comment says why in the words that
    /// apply here verbatim: SwiftUI "resolved that by putting an ellipsis through the characters
    /// the learner is supposed to be typing — a typing app hiding the typing target." **The fix
    /// was applied to one of the two screens that show a typing target.** A fix applied to one
    /// call site is not a fix.
    ///
    /// Both branches now wrap. A short word still occupies one line because it fits, so nothing
    /// about the word modes changes; only a target that could not be shown at all is affected.
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
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .minimumScaleFactor(0.5)
        } else {
            // FlowLayout rather than HStack for the same reason: an HStack cannot wrap, so a
            // sentence-length target ran off the card and was clipped. It is the app's own
            // wrapping layout, already carrying every furigana sentence in the corpus.
            FlowLayout(spacing: 2, lineSpacing: 6) {
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
            // What the learner has typed so far. It was truncating on a sentence, so past a
            // certain length they could see neither what they still owed (the kana line) nor
            // what they had already entered.
            //
            // **When it is cut, it is cut at the head (simulator pass, 2026-09-27).** Since the
            // hint below takes its two lines (v1.34 §B5), this row is the one the card squeezes:
            // with the keyboard up, late in a long sentence, it is offered one line and drops to
            // it at its 0.5 floor. At the AX1 cap that line (about 16pt on the 354pt card) holds
            // about 35 characters, and a 51-character sentence was drawn
            // "kanojohageimeidekatsudoushiteorihon…" with 45 typed — the ten characters just
            // typed were the ones hidden. Cut at the head, the oldest characters give way and the
            // newest, the ones the rider is checking, stay: the line starts "…" and ends
            // "myouhahiko". (On two lines the head mode cuts the head of the SECOND line: the first
            // line stays, the second starts "…" and still ends with the last key typed.) Where the
            // row fits, nothing changes — a truncation mode acts only on text that is cut, and
            // `V134B5RomajiHintTests` measures both, the kept tail and the unchanged pixels.
            Text(session.typedRomaji.isEmpty ? " " : session.typedRomaji)
                .scaledSystemFont(compact ? 20 : 26, weight: .bold, design: .monospaced)
                .foregroundStyle(Theme.accent2)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .truncationMode(.head)
                .accessibilityIdentifier("typedRomaji")

            if session.romajiVisible {
                // A sentence's romaji is one token — no spaces, 8 to 67 characters across the
                // corpus — and 1.33 drew it as one Text with no height of its own. On a 402pt
                // phone (simulator, 2026-09-25, en, default size, Sentence mode, N1) a 30-kana
                // sentence's 56-character hint was drawn on ONE line, "…" after about 40
                // characters, and stayed so at 18 and 36 typed characters: the rider could read
                // the upcoming romaji nowhere on this row, while the kana row's cursor and the
                // next-key chips were whole. Offered one line's height, 1.33's Text takes it and
                // cuts the token; offered room, it wraps (`V134B5RomajiHintTests` measures both).
                // So the hint takes the height it needs (`fixedSize`, at most TWO lines, shrinking
                // to a 0.45 floor rather than taking a third), and a hint long enough to outgrow a
                // phone's line gets a break opportunity between every two characters
                // (`RomajiHintLayout.breakable`): without them the line breaker has only the
                // space after the arrow and any hyphen (`KanaRomanizer` writes ー as "-"), and a
                // 56-character hint on the 322pt card shrank instead of filling its lines at full
                // size. A word's hint passes through unchanged, and where it fits its line — every
                // phone card at the default size, 240pt and wider (the longest word, "→ " and 18
                // characters, is 222.5pt at 18pt) — it renders byte for byte as in 1.33. Where a
                // word's hint needs a second line it does not: at the AX1 cap (the longest word is
                // 366.5pt at 29.6pt) and in a 208pt iPad Slide Over card, 1.33 wrapped the token by
                // character or cut it, and this chain breaks it at the arrow's space and shrinks it
                // if it must. The lines keep 1.33's leading alignment: `.multilineTextAlignment(
                // .center)` moved a one-line word's glyphs by a fraction of a point (measured), and
                // a wrapped hint's block is centred on the card either way. VoiceOver reads the
                // plain romaji, never the inserted characters. (v1.34 §B5)
                //
                // **Two lines, not three (review round 2, measured 2026-09-27).** The card does not
                // grow for the hint: SwiftUI takes its extra lines from the card's other rows. The
                // ride hosted on macOS as a 402pt phone (patched to the phone layout for the
                // measurement only), 30-kana sentence, default size: with three lines and the
                // keyboard down (778pt of screen), the example sentence under the card lost a line
                // (77 → 58pt, cut) and the kana shrank (1.33's 102 → 90pt); with at most two, the
                // example is whole and the kana 93pt. At the AX1 cap with the keyboard up (476pt of
                // screen), three lines halved the surface line (62 → 31pt) for every long hint; two
                // keep it for the 67- and 76-character ones.
                // The cost is the hint's size: 67 and 76 characters shrink to fit two lines on the
                // 322pt card (the 0.45 floor keeps whole every hint that three lines at 0.6 kept
                // whole). What two lines still take — the typed-romaji row with the keyboard up —
                // `V134B5RomajiHintTests`' header records.
                let hint = session.currentRomaji ?? ""
                Text("→ \(RomajiHintLayout.breakable(hint))")
                    .scaledSystemFont(compact ? 14 : 18, weight: .regular, design: .monospaced)
                    .foregroundStyle(Theme.dim)
                    .lineLimit(2)
                    .minimumScaleFactor(0.45)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("→ \(hint)")
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

/// Room the ride card keeps clear for its corner controls at the accessibility sizes.
/// (v1.33 §B G.)
enum RideCardLayout {
    /// The widest corner glyph's layout width per point of font size, with headroom. Measured
    /// 2026-09-17 by laying out `Image(systemName:)` in an `NSHostingView` at 15, 24.7 and 29.6pt:
    /// `star` / `star.fill` 1.27–1.32, `speaker.wave.2` 1.39–1.42. The speaker is the wider one, so
    /// it sets the reserve for both corners — the line is centred, and `SpeakButton` shows whenever
    /// speech is on, which the card does not otherwise track.
    ///
    /// **1.46, not the measured 1.42.** 1.42 was fitted to that one measurement: at AX1 keyboard-up
    /// the speaker lays out 35pt wide at 24.7pt (the host reports whole points), so it reaches
    /// 35 + 20 − 14 = 41pt against a reserve of 24.7 × 1.42 + 6 = 41.08 — 0.08pt to spare, on this
    /// Mac's SF Symbols metrics and rounding. Another machine's (CI's macos-26 runner) can differ by
    /// that much, and then the ★ or the speaker sits on the sentence again with nothing to say so.
    /// At 1.46 the reserve clears the measured reach by ≥ 1pt in both layouts: 24.7 × 1.46 + 6 =
    /// 42.07 against 41 keyboard-up, 29.6 × 1.46 + 4 = 47.28 against 45 keyboard-down. The cost is
    /// accessibility sizes only — about 1pt more inset per side there (0.04 em) — because the
    /// reserve is zero below them (`cornerControlReserve`'s guard). `V133GRideAndDrillLayoutTests`
    /// re-measures the glyphs and still fails if the reserve drops below what they reach.
    static let widestCornerGlyphEm: CGFloat = 1.46

    /// How far a corner control reaches past the card's own padding into its content: the
    /// control is `padding + glyph + padding` measured in from the card's edge, the content starts
    /// `cardPadding` in. At AX1 that is 24.7 × 1.46 + 20 − 14 ≈ 42pt keyboard-up and
    /// 29.6 × 1.46 + 28 − 24 ≈ 47pt keyboard-down; a sentence line on a 402pt phone keeps 270 of
    /// its 354pt. **Zero below the accessibility sizes, except on a sentence card with the keyboard
    /// up** (`sentenceUnderKeyboard`, simulator pass 2026-09-27): there, at the default size,
    /// 15 × 1.46 + 20 − 14 ≈ 27.9pt, and the sentence line keeps 298 of its 354pt. Every other
    /// default-size layout — a word card, and any card with the keyboard down — does not move.
    static func cornerControlReserve(glyphPoints: CGFloat, controlPadding: CGFloat,
                                     cardPadding: CGFloat, accessibilitySize: Bool,
                                     sentenceUnderKeyboard: Bool = false) -> CGFloat {
        guard accessibilitySize || sentenceUnderKeyboard else { return 0 }
        return max(0, glyphPoints * widestCornerGlyphEm + 2 * controlPadding - cardPadding)
    }
}

/// Where the ride card's romaji hint may break. (v1.34 §B5)
///
/// Romaji has no spaces, so to the line breaker a sentence's hint is nearly one word: the only
/// breaks it offers are the space after the arrow and a hyphen, which is how `KanaRomanizer` writes
/// ー (review round 2: the observed hint's "jizennime-rude" has one). Under a line limit, a stretch
/// with no break that is longer than its line is shrunk or cut rather than wrapped.
/// `WordCard.romaji` has the device observation and `V134B5RomajiHintTests` the measurements. The
/// answer is `AboutView.breakingIdentifiers`' (v1.33 §B S): a zero-width space is a break opportunity with no advance (re-measured here for
/// SF Mono at 14 and 18pt: "a", U+200B, "a" is exactly two advances), so a token that carries one
/// between every two characters fills its lines like a paragraph and, where no break is needed,
/// draws byte for byte as it did without them.
enum RomajiHintLayout {
    /// From this many characters a hint gets its break opportunities. Measured, not chosen:
    ///
    /// * **Above every word.** The longest word's romaji in the corpus is 18 characters
    ///   ("kashikomarimashita"; the next longest are 14), so the word modes' hints pass through
    ///   untouched — and render byte for byte as in 1.33 wherever they fit their line, which at the
    ///   default size is every phone card (`WordCard.romaji` says where a word's hint needs two).
    /// * **Exactly the shortest hint that can outgrow a phone's line at the default size.** SF Mono
    ///   advances 11.13pt at 18pt, so the keyboard-down card on a 402pt phone (402 − 2×16 − 2×24 =
    ///   322pt) holds 28 characters — the arrow, its space and 26 of romaji — and the narrowest
    ///   phone card, 320pt Display Zoom (240pt), holds 21: a 19-character hint fits it and a
    ///   20-character one does not. Lower would only give breaks to hints that fit every phone's
    ///   line whole.
    ///
    /// It does not sort words from sentences: 701 of the corpus's 6,724 typeable sentences
    /// romanise to fewer than 20 characters (the shortest, 8), and those pass through as a word
    /// does, because they fit every phone's line whole.
    static let breakableFrom = 20

    /// `romaji` with U+200B between every two characters when it is `breakableFrom` characters or
    /// longer, else `romaji` unchanged. Never for the VoiceOver label, which is built from the
    /// plain string, and never for the practice screen's hint, which has its own row
    /// (`practiceRomaji`) and is not touched by v1.34.
    static func breakable(_ romaji: String) -> String {
        guard romaji.count >= breakableFrom else { return romaji }
        return romaji.map(String.init).joined(separator: "\u{200B}")
    }
}
