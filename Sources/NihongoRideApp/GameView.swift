import SwiftUI
import SceneryKit
import GameCore
import RomajiKana

struct GameView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var isPaused = false
    @State private var timeRemaining = 0.0
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
                    HUDBar(session: session, language: model.languageCode,
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
        .onAppear {
            Sound.enabled = model.soundEnabled
            isPaused = false
            timeRemaining = session.config.timeLimit ?? 0
            // Defensive: a session that was already finished at construction
            // (e.g. an empty queue) would otherwise strand here — onChange won't
            // fire for a value that never changes. Finish it immediately.
            if session.isFinished { model.finishGame() }
        }
        .onReceive(ticker) { _ in
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
            if let session = model.session, !session.showRomajiHint {
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
                 label: zh ? "进度" : "Words",
                 spoken: zh ? "\(session.wordsCompleted) / \(session.wordCount)"
                            : "\(session.wordsCompleted) of \(session.wordCount)")
                .accessibilityIdentifier("hudProgress")
            if !narrow {
                stat(icon: "scope",
                     value: "\(Int(session.accuracy * 100))%", tint: .white,
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
                .frame(width: 46, alignment: .trailing)
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

    var body: some View {
        VStack(spacing: compact ? 10 : 18) {
            Text(session.currentSurface ?? "")
                .scaledSystemFont(compact ? 40 : 64, weight: .bold, relativeTo: .largeTitle)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.4)   // long compounds shrink instead of clipping (narrow screens)

            kanaReading

            Text(session.currentGloss ?? "")
                .scaledSystemFont(compact ? 15 : 20, weight: .medium, design: .rounded)
                .foregroundStyle(Theme.dim)

            Divider().background(Theme.cardStroke).frame(maxWidth: compact ? 300 : 360)

            romaji

            if !compact, let example = session.currentExampleJP {
                VStack(spacing: 3) {
                    Text(example)
                        .scaledSystemFont(16, weight: .medium)
                        .foregroundStyle(.white.opacity(0.7))
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
            SpeakButton(kana: session.currentKana, compact: compact, language: language)
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

            if session.showRomajiHint {
                Text("→ \(session.currentRomaji ?? "")")
                    .scaledSystemFont(compact ? 14 : 18, weight: .regular, design: .monospaced)
                    .foregroundStyle(Theme.dim)
                    .accessibilityIdentifier("romajiHint")
                nextKeys
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
