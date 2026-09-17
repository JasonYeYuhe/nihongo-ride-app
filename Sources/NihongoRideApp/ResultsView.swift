import SwiftUI
import StoreKit
import SceneryKit
import VocabKit
import DiagnosticsKit

struct ResultsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Verified against the shipping SDK: `RequestReviewAction` is iOS 16 / macOS 13, below
    /// this app's 17.0 / 14.0 targets, and unlike `SKStoreReviewController` — deprecated in
    /// iOS 18 / macOS 15 — it is one call on both platforms with no window-scene plumbing.
    @Environment(\.requestReview) private var requestReview

    private var zh: Bool { model.languageCode == "zh" }
    /// Word whose "add to lists" multi-select sheet is open (long-press a chip).
    @State private var addToListsTarget: String?
    /// The rendered ride card, or nil while it hasn't rendered / couldn't render.
    /// Rendered once on appear rather than per body pass: ImageRenderer is not free,
    /// and body runs on every state change (each ★ toggle, each sheet open).
    @State private var shareCard: ShareCardImage?

    var body: some View {
        // iPhone: results (cards + review list) outgrow the screen — scroll.
        ZStack {
            // The sky you arrived under (v1.12 §D2). Attached OUTSIDE the ScrollView so it
            // fills the screen and stays put; inside, it would become a tall scrolling
            // canvas and drift away with the review list.
            RideArrivalBackdrop(stage: model.rideStage)
            // Scrolls on every device now, not only iPhone — see scrollsWhenTall for why
            // a bare ScrollView would have moved the roomy layouts. (v1.15 §A.)
            scrollsWhenTall { content }
        }
        .background {
            if !Screenshotter.isCapturing {
                KeyCaptureView(
                    onKey: { _ in },
                    onCommand: { command in
                        switch command {
                        case .returnKey, .space: model.startGame()
                        case .escape: model.backToMenu()
                        case .backspace: break
                        }
                    },
                    suppressSoftwareKeyboard: true
                )
            }
        }
        .onAppear {
            // Never in capture mode: the headless renderer would be re-entering
            // ImageRenderer from inside its own render pass.
            guard !Screenshotter.isCapturing, let summary = model.lastSummary else { return }
            shareCard = ShareCardRenderer.render(summary: summary, zh: zh)
                .map { ShareCardImage(data: $0, title: zh ? "にほんご ライド" : "Nihongo Ride") }
        }
        .onAppear {
            // Arriving somewhere after a good ride is the positive moment; the model decides
            // whether this particular one has earned the ask, and records the answer either way.
            model.considerReviewPrompt { requestReview() }
        }
        .sheet(isPresented: Binding(get: { addToListsTarget != nil },
                                    set: { if !$0 { addToListsTarget = nil } })) {
            if let id = addToListsTarget {
                AddToListsSheet(vocabID: id, isPresented: Binding(
                    get: { addToListsTarget != nil },
                    set: { if !$0 { addToListsTarget = nil } }))
                    .presentationBackground(Theme.background)
            }
        }
    }

    /// Names the stretch this run was ridden on. Deliberately about the RUN, not the
    /// rider's current lifetime position: rideStage is frozen at run start, so at a stage
    /// boundary the two can differ, and "arrived at X" would be a lie exactly then.
    private var stageLine: some View {
        Text(zh ? "本程路段:\(model.rideStage.name)"
                : "This ride: the \(model.rideStage.romaji) stretch")
            .font(.caption)
            .foregroundStyle(Theme.dim)
    }

    private var content: some View {
        let summary = model.lastSummary

        return VStack(spacing: 20) {
            Spacer(minLength: 0)

            if let summary {
                VStack(spacing: 20) {
                    // Title lives INSIDE the panel: naked over the scene it measured
                    // 2-5:1 against the clouds (the Codex review predicted exactly this),
                    // and dimming the whole arrival sky to fix a title would defeat the
                    // feature. The panel already owes its content 7:1.
                    if summary.typedNothing {
                        // A run that typed nothing is not an arrival. It showed "You've arrived!",
                        // the 🏁 and a grade over "0 m" and 100% accuracy — at every size, in both
                        // languages (simulator pass 2026-09-17, defect 5) — for a run the Ride Log
                        // had already refused. Asked of the SAME rule `logRun` refuses it by, so
                        // the log and this screen cannot disagree. Says what happened, and nothing
                        // else: no flag, no grade. The buttons below do not change. (v1.33 §B R)
                        Text(zh ? "第一个词还没打,这一程就结束了" : "The ride ended before the first word")
                            .scaledSystemFont(isPhoneIdiom ? 30 : 36, weight: .heavy, design: .rounded, relativeTo: .largeTitle)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                    } else {
                        Text("🏁")
                            .scaledSystemFont(50, relativeTo: .largeTitle)
                            .accessibilityHidden(true)
                        Text(zh ? "到站!" : "You've arrived!")
                            .scaledSystemFont(isPhoneIdiom ? 30 : 36, weight: .heavy, design: .rounded, relativeTo: .largeTitle)
                            .foregroundStyle(.white)
                        grade(for: summary)
                    }
                    scoreGrid(summary)
                    // Only where a lapsed entry really is a WORD. On a sentence or dictation
                    // run `GameSession.sentenceSession` wraps each sentence as a VocabEntry
                    // whose `surface` IS the whole sentence, so this list rendered 「友達と映画を
                    // 見ました。」 inside a 116pt word cell, captioned with one word's gloss
                    // ("movie, film"), and VoiceOver announced "Save 〈whole sentence〉" — while
                    // the star actually saved 映画, a word the cell never named. Seen in the
                    // headless render.
                    //
                    // Nothing replaces it because something already had: the chips below name
                    // what went wrong per WORD, resolve to real entries, and are actionable.
                    // This list was the same question answered worse. (v1.25 §B; v1.24 §B left
                    // this open as "decide what replaces it rather than leaving a gap".)
                    if !summary.reviewWords.isEmpty, summary.mode.lapsesAreWords {
                        reviewList(summary.reviewWords)
                    }
                    stageLine
                    coachEntry
                    stumbledWords
                }
                .arrivalPanel(compact: isPhoneIdiom)
            }

            adaptiveStack(horizontal: !isPhoneIdiom && !typeSize.wantsStackedButtons, spacing: isPhoneIdiom ? 12 : 16) {
                Button(action: model.startGame) {
                    Text(zh ? "再来一程 ▶" : "Ride again ▶")
                        .scaledSystemFont(18, weight: .bold, design: .rounded)
                        .ctaLabel(minWidth: 200, minHeight: 50)
                }
                .buttonStyle(.plain)
                .background(Theme.accent, in: Capsule())
                .foregroundStyle(.white)
                .accessibilityIdentifier("rideAgainButton")

                Button(action: model.backToMenu) {
                    Text(zh ? "回到主页" : "Menu")
                        .scaledSystemFont(18, weight: .semibold, design: .rounded)
                        .ctaLabel(minWidth: 140, minHeight: 50)
                }
                .buttonStyle(.plain)
                .background(Theme.card, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.cardStroke))
                .foregroundStyle(.white)
                .accessibilityIdentifier("menuButton")

                // Only shown once a card actually rendered — never a button that
                // would hand the share sheet nothing. Nor for a run that typed nothing: the card
                // prints a grade and "100%" for it, the claim the headline above stopped making.
                // The card is still rendered on appear exactly as before. (v1.33 §B R)
                if let card = shareCard, model.lastSummary?.typedNothing != true {
                    ShareLink(item: card, preview: SharePreview(card.title)) {
                        Label(zh ? "分享" : "Share", systemImage: "square.and.arrow.up")
                            .scaledSystemFont(18, weight: .semibold, design: .rounded)
                            .ctaLabel(minWidth: 140, minHeight: 50)
                    }
                    .buttonStyle(.plain)
                    .background(Theme.card, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.cardStroke))
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("shareButton")
                    // ShareLink is a real control, so it TAKES first responder from the
                    // hidden KeyCaptureView — and unlike the speak button (v1.9 §D3,
                    // which dodged this by not being a Button at all) it has to be one.
                    // Summon focus back, or Return/Escape stay dead on this screen after
                    // the sheet closes: macOS claimed first responder exactly once at
                    // viewDidMoveToWindow, and iOS would leave the keyboard dismissed.
                    // Fires on tap rather than on dismissal because there is no dismissal
                    // callback; the re-claim is idempotent and the sheet keeps focus while
                    // it is up. (Device gate: both platforms, after the sheet closes.)
                    .simultaneousGesture(TapGesture().onEnded {
                        Task { @MainActor in KeyboardSummon.summon() }
                    })
                }
            }
            .padding(.top, 8)

            Spacer()
        }
        .padding(isPhoneIdiom ? 24 : 40)
    }

    /// One line about HOW the ride was typed, when the run gives grounds for one.
    ///
    /// Absent by default and absent by design: it appears only when a pattern recurred across
    /// two distinct words and the app has a name and a rule for it. A ride with a clean run,
    /// a single slip, or only unexplainable refusals shows nothing here — the coach earns its
    /// space or does not take it. (v1.15 §E.)
    @ViewBuilder
    private var coachEntry: some View {
        if let d = model.coachHeadline,
           let advice = CoachContent.advice(for: d.pattern, zh: zh) {
            Button(action: { model.screen = .coach }) {
                HStack(spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(Theme.gold)
                        .accessibilityHidden(true)
                    Text(advice.title)
                        .scaledSystemFont(14, weight: .semibold, design: .rounded)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "chevron.right")
                        .font(.caption2).foregroundStyle(Theme.dim)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Theme.card, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.cardStroke))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("coachEntryButton")
            .accessibilityLabel(zh ? "打字教练:\(advice.title)" : "Typing coach: \(advice.title)")
            .accessibilityHint(zh ? "查看这次反复出错的地方" : "See what kept going wrong this ride")
        }
    }

    /// The WORDS a sentence or dictation run stopped the learner on.
    ///
    /// The coach line above explains typing mechanics — the rule that keeps going wrong. It
    /// is silent, correctly, when the refusals have no rule behind them, and in a sentence
    /// run that is the common case: the learner did not know the word, or in dictation did
    /// not hear it. Until now the app answered that with a number. This answers it with the
    /// words.
    ///
    /// Sentence and dictation runs only. A word run's results already list the words that
    /// lapsed, and repeating them here would say nothing new. (PLAN-V1.23 §A.)
    @ViewBuilder
    private var stumbledWords: some View {
        if let summary = model.lastSummary,
           summary.mode == .sentence || summary.mode == .dictation {
            // Particles count in dictation and not on screen: a を the learner could SEE and
            // still refused is the wa/ha spelling trap, which the coach explains a line above
            // with an actual rule. Naming it here as well would relabel a spelling slip as a
            // word they do not know. Heard rather than seen, missing it is a listening result
            // and worth saying.
            let stumbles = StumbledWords.from(summary.mistakes, vocab: model.vocab,
                                              includesParticles: summary.mode == .dictation)
            // Resolve first, render second, and count what the run will contain. The displayed
            // slice is computed ONCE and both the chips and the ride button are derived from
            // it, so the screen cannot promise a word it will not ride. (v1.24 §A.)
            let displayed = Array(stumbles.prefix(6))
            let rideable = model.rideableStumbles(displayed)
            if !displayed.isEmpty {
                VStack(spacing: 6) {
                    Text(summary.mode == .dictation
                         ? (zh ? "这些词没听出来" : "The words you could not catch")
                         : (zh ? "这些词卡住了你" : "The words that stopped you"))
                        .scaledSystemFont(13, weight: .semibold, design: .rounded)
                        .foregroundStyle(Theme.dim)
                    MenuFlow(spacing: 8, rowSpacing: 8) {
                        ForEach(displayed, id: \.self) { stumble in
                            stumbleChip(stumble)
                        }
                    }
                    .frame(maxWidth: 460)
                    if !rideable.isEmpty {
                        rideTheseButton(displayed, count: rideable.count)
                    }
                }
                .accessibilityIdentifier("stumbledWords")
            }
        }
    }

    /// One stumbled word, actionable when the app can say which word it is.
    ///
    /// Two kinds of chip on one screen, which the plan chose deliberately rather than papering
    /// over. Dictation keeps particles because mishearing に for の is a real listening result,
    /// and a particle is exactly the thing that cannot be saved or drilled; filtering those out
    /// would gut the diagnostic v1.23 shipped. So an unresolvable chip stays, reads the same,
    /// and simply offers nothing — no star, no gestures, and a dimmer border to say why without
    /// a sentence of explanation.
    ///
    /// The star and the long-press mirror the lapsed-word rows above exactly (tap = save,
    /// long-press = add to lists), because a learner who has used one should not have to
    /// discover the other.
    @ViewBuilder
    private func stumbleChip(_ stumble: StumbledWords.Stumble) -> some View {
        let saved = stumble.entryID.map(model.isSaved) ?? false
        VStack(spacing: 1) {
            Text(stumble.reading)
                .font(.caption2).foregroundStyle(Theme.dim)
            HStack(spacing: 4) {
                if stumble.entryID != nil {
                    Image(systemName: saved ? "star.fill" : "star")
                        .scaledSystemFont(9)
                        .foregroundStyle(saved ? Theme.gold : Theme.dim)
                }
                Text(stumble.surface)
                    .scaledSystemFont(15, weight: .semibold)
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(saved ? Theme.gold.opacity(0.14) : Theme.card,
                    in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(
            saved ? Theme.gold.opacity(0.5)
                  : (stumble.entryID == nil ? Theme.cardStroke.opacity(0.4) : Theme.cardStroke)))
        // Width follows the proposal; height never truncates. Was `.fixedSize()`, which ignored
        // every width proposal, so a word wider than the row could only overflow: at AX5 on a
        // 393pt phone a chip is 65pt + the word, 7 characters (かもしれません) spill into the margin
        // and 8+ are clipped on both edges (ax-findings #27, CoreText-measured 2026-09-17).
        // `MenuFlow` now proposes the row's width to exactly such a chip, and this is what lets
        // the word wrap inside it. A chip that fits is proposed its own natural size, which is
        // the size it had. (v1.33 §B R)
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
        // Composed tap + long-press rather than Button + simultaneousGesture, which lets a
        // long-press also toggle the ★ (the bug the review list already documents).
        .onTapGesture { if let id = stumble.entryID { model.toggleSaved(id) } }
        .onLongPressGesture { if let id = stumble.entryID { addToListsTarget = id } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: stumble, saved: saved))
        .accessibilityHint(accessibilityHint(for: stumble, saved: saved) ?? "")
        .accessibilityAddTraits(stumble.entryID == nil ? [] : .isButton)
        .accessibilityActions {
            if let id = stumble.entryID {
                Button(zh ? "加入词单" : "Add to lists") { addToListsTarget = id }
            }
        }
    }

    private func accessibilityLabel(for stumble: StumbledWords.Stumble, saved: Bool) -> String {
        StumbleChipLabel.label(surface: stumble.surface, reading: stumble.reading,
                               actionable: stumble.entryID != nil, saved: saved, zh: zh)
    }

    private func accessibilityHint(for stumble: StumbledWords.Stumble, saved: Bool) -> String? {
        StumbleChipLabel.hint(actionable: stumble.entryID != nil, saved: saved, zh: zh)
    }

    /// Rides the words this screen just named, as a word run that records no SRS.
    ///
    /// The number is `rideableIDs`' own count, not `displayed.count` and not a fresh filter
    /// written here: showing six words and riding four would be the fifteenth instance of this
    /// project's recurring defect, and the first one introduced *after* the sweep meant to end
    /// it. `ResolvesCallSiteTests` cannot catch it — there is no `resolves:` keyword on this
    /// path — which is precisely the blind spot the v1.23 audit's own calibration named.
    private func rideTheseButton(_ displayed: [StumbledWords.Stumble], count: Int) -> some View {
        Button { model.startStumbledWords(displayed) } label: {
            HStack(spacing: 6) {
                Image(systemName: "bicycle").accessibilityHidden(true)
                Text(zh ? "骑这 \(count) 个词" : rideLabel(count))
                    .scaledSystemFont(13, weight: .semibold, design: .rounded)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Theme.accent, in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
        .accessibilityIdentifier("rideStumbledButton")
        .accessibilityHint(zh ? "只练这些词,不计入复习进度"
                              : "Practise just these words. Nothing is added to your review schedule.")
    }

    private func rideLabel(_ count: Int) -> String {
        count == 1 ? "Ride this word" : "Ride these \(count) words"
    }

    /// Six stat cards: 3×2 rows on roomy screens, a 2-column grid on iPhone.
    private func scoreGrid(_ summary: GameSummary) -> some View {
        // Dictation trades the distance tile for the replay count. The grid is a fixed 3+3,
        // and of the six, distance is the one a listening exercise says least with — while
        // the replay count is the one thing about a dictation run the score cannot express:
        // twelve replays and none score the same. The ride is still journalled with its
        // distance either way; this is what the learner is shown, not what is recorded.
        let secondCard: (icon: String, tint: Color, value: String, label: String, spoken: String?) =
            summary.mode == .dictation
            ? (icon: "arrow.clockwise", tint: Theme.accent2,
               value: "\(summary.replays)", label: zh ? "重听" : "Replays",
               spoken: zh ? "重听 \(summary.replays) 次" : countLabel(summary.replays, "replay"))
            : (icon: "bicycle", tint: Theme.accent2,
               value: "\(Int(summary.distanceMeters)) m", label: zh ? "距离" : "Distance",
               spoken: zh ? "\(Int(summary.distanceMeters)) 米" : "\(Int(summary.distanceMeters)) meters")
        // A run that pressed no key has no accuracy: `GameSession.accuracy` defines 0/0 as 1, which
        // printed "100%" under a ride of nothing. "—" is a drawing, so VoiceOver gets words — the
        // StatsView "Best WPM" tile's rule. (v1.33 §B R) Asked as `pressedNoKey`, not
        // `typedNothing`: a ride of only wrong keys also typed nothing — the headline still says
        // so — but its 0% is real, and "—" / "Nothing typed" was not true of it. (v1.33 review)
        let accuracyCard: (icon: String, tint: Color, value: String, label: String, spoken: String?) =
            summary.pressedNoKey
            ? (icon: "scope", tint: Color.white, value: "—", label: zh ? "准确率" : "Accuracy",
               spoken: zh ? "没有输入" : "Nothing typed")
            : (icon: "scope", tint: Color.white,
               value: "\(Int(summary.accuracy * 100))%", label: zh ? "准确率" : "Accuracy", spoken: nil)
        let cards: [(icon: String, tint: Color, value: String, label: String, spoken: String?)] = [
            (icon: "star.fill", tint: Theme.gold,
             value: "\(summary.score)", label: zh ? "得分" : "Score", spoken: nil),
            secondCard,
            (icon: "flame.fill", tint: Theme.accent,
             value: "×\(summary.maxCombo)", label: zh ? "最高连击" : "Best combo",
             spoken: "\(summary.maxCombo)"),
            // `wordsCompleted` counts whatever the run's queue held, and on a sentence or
            // dictation run that is SENTENCES. Labelling it "Words" put a second unit on a
            // screen that already says "the words that stopped you" a few lines below, with a
            // different number, about different things. (v1.25 §B.)
            (icon: "checkmark.circle.fill", tint: Theme.done,
             value: "\(summary.wordsCompleted)",
             label: summary.mode.completedUnitLabel(zh: zh), spoken: nil),
            accuracyCard,
            // "To review" is a promise, and on a run that persists no SRS it is a false one:
            // sentence, dictation and the weak-words cram all merge nothing into the schedule,
            // so nothing here will ever come back for review. The words are still worth naming
            // — they are what went wrong — so the tile keeps them and stops promising.
            // (v1.24 §B; the fix is the label, not the behaviour.)
            (icon: summary.persistsSRS ? "brain.head.profile" : "figure.strengthtraining.functional",
             tint: Theme.accent,
             value: "\(summary.reviewWords.count)",
             // "Missed" was the first attempt and it read as a contradiction beside the chips:
             // the tile counts whole words that LAPSED (skipped, hinted, heavily mistyped) while
             // the chips count words a refused key landed in, so a sentence ride shows "Missed 0"
             // above four words that plainly stopped the learner. Seen in the headless render,
             // not reasoned about. This wording matches the list directly below it instead.
             label: summary.persistsSRS ? (zh ? "待复习" : "To review")
                                        : summary.mode.struggledLabel(zh: zh),
             spoken: nil),
        ]
        return Group {
            // One column at the accessibility sizes. Two columns broke the captions mid-word at AX5
            // ("Word / s", "Dis- / tance", "Accu- / racy"; Chinese "准确 / 率") and set tiles of
            // different heights side by side out of line — on the core loop's own screen
            // (simulator pass 2026-09-17 on a 402pt iPhone 17 Pro, defects 1 and 26,
            // `B_results_p1_en_ax5.png`). From this file's own padding, a caption had about 110pt
            // in two columns and has about 278pt in one, where the longest ("Tough lines", "Best
            // combo", 11 characters) should fit on one line — computed, not yet seen on a device. The fixed 150pt tiles of
            // the wide row would break the same way on an iPad, so this is decided by text size,
            // not by width. (v1.33 §B R)
            if typeSize.isAccessibilitySize {
                VStack(spacing: 12) {
                    ForEach(cards.indices, id: \.self) { i in
                        scoreCard(cards[i], flexible: true)
                    }
                }
                .frame(maxWidth: 420)
            } else {
                // Width-driven, not idiom-driven — see ConjugationResultsView.scoreGrid for the bug
                // this replaces (iPad portrait treated as roomy, tiles off both screen edges).
                ViewThatFits(in: .horizontal) {
                    VStack(spacing: 14) {
                        HStack(spacing: 14) { ForEach(0..<3) { i in scoreCard(cards[i], flexible: false) } }
                        HStack(spacing: 14) { ForEach(3..<6) { i in scoreCard(cards[i], flexible: false) } }
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(cards.indices, id: \.self) { i in
                            scoreCard(cards[i], flexible: true)
                        }
                    }
                    .frame(maxWidth: 420)
                }
            }
        }
    }

    private func scoreCard(_ c: (icon: String, tint: Color, value: String, label: String, spoken: String?),
                           flexible: Bool) -> some View {
        VStack(spacing: 8) {
            Image(systemName: c.icon).font(.title2).foregroundStyle(c.tint)
            // A number must never lose digits — 1100 m truncated to "11…" reports a
            // different ride. Shrink to fit instead, and only then wrap.
            Text(c.value)
                .scaledSystemFont(28, weight: .bold, design: .rounded, relativeTo: .largeTitle)
                .foregroundStyle(.white).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.4)
            Text(c.label).font(.caption).foregroundStyle(Theme.dim)
                .lineLimit(2).multilineTextAlignment(.center)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: flexible ? .infinity : nil)
        // minHeight, not height: at the accessibility text sizes the contents are taller
        // than 104/120pt and a fixed frame does not clip them — it lets them spill OUTSIDE
        // the panel, so the tiles overlapped each other and the labels sat on the next
        // row's icon. Growing the tile is the only thing that keeps the grid readable.
        // (v1.14 §C, seen on a device at AX5 — ImageRenderer cannot show this.)
        .frame(width: flexible ? nil : 150)
        .frame(minHeight: flexible ? 104 : 120)
        .panel(20)
        // One element: "Score, 150" instead of icon + "150" + "Score" fragments.
        .accessibilityElement()
        .accessibilityLabel(c.label)
        .accessibilityValue(c.spoken ?? c.value)
    }

    // MARK: Grade

    private func grade(for s: GameSummary) -> some View {
        let g = s.grade
        let (title, tint): (String, Color) = {
            switch g {
            case .flawless: return (zh ? "完美" : "Flawless", Theme.gold)
            case .steady:   return (zh ? "稳健" : "Steady",   Theme.done)
            case .building: return (zh ? "有进步" : "Building", Theme.accent2)
            case .lap:      return (zh ? "再来一程" : "Take another lap", Theme.accent)
            }
        }()
        let line: String = {
            if zh {
                switch g {
                case .flawless: return "几乎一个错都没有,一路飞驰。"
                case .steady:   return "节奏稳,准确率不错。"
                case .building: return "正在打磨手感,继续。"
                case .lap:      return "深呼吸,再来一程会更顺。"
                }
            } else {
                switch g {
                case .flawless: return "Barely a missed key. Pure flow."
                case .steady:   return "Solid pace, clean accuracy."
                case .building: return "You're tuning the rhythm. Keep going."
                case .lap:      return "Take a breath — the next lap will feel better."
                }
            }
        }()
        return VStack(spacing: 6) {
            Text(title.uppercased())
                .scaledSystemFont(14, weight: .black, design: .rounded)
                .tracking(4)
                .foregroundStyle(tint)
            Text(line)
                .scaledSystemFont(13, weight: .regular)
                .foregroundStyle(Theme.dim)
        }
    }

    private func reviewList(_ words: [VocabEntry]) -> some View {
        // Same correction as the tile above, for the same reason: on a run that persists no
        // SRS these words are not queued for review, and "review these" says they are. Saving
        // them still works, and is now the only thing that will actually bring them back.
        let persists = model.lastSummary?.persistsSRS ?? true
        return VStack(spacing: 8) {
            Text(persists ? (zh ? "复习这些词(点 ★ 收藏):" : "Review these (tap ★ to save):")
                          : (zh ? "这些让你吃力(点 ★ 收藏):" : "These gave you trouble (tap ★ to save):"))
                .font(.caption).foregroundStyle(Theme.dim)
            // One column at the accessibility sizes. The adaptive grid makes two 168pt columns on a
            // phone, and with the star and the speaker beside it the word keeps about 76pt — one
            // kanji is 45pt at AX5, so 図書館 stacked one character per line (ax-findings #29,
            // CoreText-measured 2026-09-17). One column gives the word about 250pt. (v1.33 §B R)
            LazyVGrid(columns: typeSize.isAccessibilitySize
                                ? [GridItem(.flexible(), spacing: 8)]
                                : [GridItem(.adaptive(minimum: 116), spacing: 8)],
                      spacing: 8) {
                ForEach(words.prefix(12)) { word in
                    let saved = model.isSaved(word.id)
                    // Composed tap + long-press (NOT Button + simultaneousGesture,
                    // which let a long-press also toggle the ★ unintentionally).
                    let canSpeak = model.ttsEnabled && model.ttsAvailable
                    VStack(spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: saved ? "star.fill" : "star")
                                .scaledSystemFont(9).foregroundStyle(saved ? Theme.gold : Theme.dim)
                            Text(word.surface)
                                .scaledSystemFont(15, weight: .semibold).foregroundStyle(.white)
                            // Read-aloud: reads the word's kana. A tap that LANDS on this shape wins
                            // (innermost gesture) — but a tap that MISSES falls through to the chip
                            // and toggles ★. v1.9 shipped this at ~12x12pt, which made a near-miss a
                            // silent un-save; harmless then (a peer's union resurrected the word) but
                            // Phase A is exactly what turns it into a propagating cross-device delete
                            // an old peer can't undo. Hence a solid 28pt target (~5x the area) — the
                            // most a chip this dense allows. No keyboard summon: results suppresses
                            // the keyboard (not a game screen). (v1.10 §A4.)
                            if canSpeak {
                                Group {
                                    let glyph = Image(systemName: "speaker.wave.2")
                                        .scaledSystemFont(12).foregroundStyle(Theme.accent2)
                                    // At the accessibility sizes the scaled glyph (~37pt at AX5)
                                    // overflowed the fixed 28pt frame onto its neighbours
                                    // (ax-findings #29). There the frame is a floor, so the target
                                    // is never smaller than 28pt and grows with its glyph; the
                                    // default size keeps the fixed frame. (v1.33 §B R)
                                    if typeSize.isAccessibilitySize {
                                        glyph.frame(minWidth: 28, minHeight: 28)
                                    } else {
                                        glyph.frame(width: 28, height: 28)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { model.speak(word.kana) }
                            }
                        }
                        Text(word.gloss(for: model.languageCode))
                            .font(.caption2).foregroundStyle(Theme.dim).lineLimit(1)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(saved ? Theme.gold.opacity(0.14) : Theme.card,
                                in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(saved ? Theme.gold.opacity(0.5) : .clear))
                    .contentShape(Rectangle())
                    .onTapGesture { model.toggleSaved(word.id) }
                    .onLongPressGesture { addToListsTarget = word.id }
                    .accessibilityElement()
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(saved ? (zh ? "\(word.surface),已收藏" : "\(word.surface), saved")
                                              : (zh ? "\(word.surface),收藏" : "Save \(word.surface)"))
                    .accessibilityAction(named: Text(zh ? "加入词单" : "Add to lists")) { addToListsTarget = word.id }
                    .accessibilityActions {
                        if canSpeak {
                            Button(zh ? "朗读" : "Read aloud") { model.speak(word.kana) }
                        }
                    }
                }
            }
            if words.count > 12 {
                Text(zh ? "还有 \(words.count - 12) 个…" : "+\(words.count - 12) more…")
                    .font(.caption2).foregroundStyle(Theme.dim)
            }
        }
        .frame(maxWidth: 540)
    }
}
