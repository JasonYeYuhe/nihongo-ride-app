import SwiftUI
import SceneryKit
import VocabKit

struct ResultsView: View {
    @Environment(AppModel.self) private var model

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
            if isPhoneIdiom {
                ScrollView(showsIndicators: false) { content }
            } else {
                content
            }
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
                    Text("🏁")
                        .scaledSystemFont(50, relativeTo: .largeTitle)
                        .accessibilityHidden(true)
                    Text(zh ? "到站!" : "You've arrived!")
                        .scaledSystemFont(isPhoneIdiom ? 30 : 36, weight: .heavy, design: .rounded, relativeTo: .largeTitle)
                        .foregroundStyle(.white)
                    grade(for: summary)
                    scoreGrid(summary)
                    if !summary.reviewWords.isEmpty {
                        reviewList(summary.reviewWords)
                    }
                    stageLine
                }
                .arrivalPanel(compact: isPhoneIdiom)
            }

            adaptiveStack(horizontal: !isPhoneIdiom, spacing: isPhoneIdiom ? 12 : 16) {
                Button(action: model.startGame) {
                    Text(zh ? "再来一程 ▶" : "Ride again ▶")
                        .scaledSystemFont(18, weight: .bold, design: .rounded)
                        .frame(width: 200, height: 50)
                }
                .buttonStyle(.plain)
                .background(Theme.accent, in: Capsule())
                .foregroundStyle(.white)
                .accessibilityIdentifier("rideAgainButton")

                Button(action: model.backToMenu) {
                    Text(zh ? "回到主页" : "Menu")
                        .scaledSystemFont(18, weight: .semibold, design: .rounded)
                        .frame(width: 140, height: 50)
                }
                .buttonStyle(.plain)
                .background(Theme.card, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.cardStroke))
                .foregroundStyle(.white)
                .accessibilityIdentifier("menuButton")

                // Only shown once a card actually rendered — never a button that
                // would hand the share sheet nothing.
                if let card = shareCard {
                    ShareLink(item: card, preview: SharePreview(card.title)) {
                        Label(zh ? "分享" : "Share", systemImage: "square.and.arrow.up")
                            .scaledSystemFont(18, weight: .semibold, design: .rounded)
                            .frame(width: 140, height: 50)
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

    /// Six stat cards: 3×2 rows on roomy screens, a 2-column grid on iPhone.
    private func scoreGrid(_ summary: GameSummary) -> some View {
        let cards: [(icon: String, tint: Color, value: String, label: String, spoken: String?)] = [
            (icon: "star.fill", tint: Theme.gold,
             value: "\(summary.score)", label: zh ? "得分" : "Score", spoken: nil),
            (icon: "bicycle", tint: Theme.accent2,
             value: "\(Int(summary.distanceMeters)) m", label: zh ? "距离" : "Distance",
             spoken: zh ? "\(Int(summary.distanceMeters)) 米" : "\(Int(summary.distanceMeters)) meters"),
            (icon: "flame.fill", tint: Theme.accent,
             value: "×\(summary.maxCombo)", label: zh ? "最高连击" : "Best combo",
             spoken: "\(summary.maxCombo)"),
            (icon: "checkmark.circle.fill", tint: Theme.done,
             value: "\(summary.wordsCompleted)", label: zh ? "完成词数" : "Words", spoken: nil),
            (icon: "scope", tint: Color.white,
             value: "\(Int(summary.accuracy * 100))%", label: zh ? "准确率" : "Accuracy", spoken: nil),
            (icon: "brain.head.profile", tint: Theme.accent,
             value: "\(summary.reviewWords.count)", label: zh ? "待复习" : "To review", spoken: nil),
        ]
        return Group {
            if isPhoneIdiom {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(cards.indices, id: \.self) { i in
                        scoreCard(cards[i])
                    }
                }
                .frame(maxWidth: 420)
            } else {
                VStack(spacing: 14) {
                    HStack(spacing: 14) { ForEach(0..<3) { i in scoreCard(cards[i]) } }
                    HStack(spacing: 14) { ForEach(3..<6) { i in scoreCard(cards[i]) } }
                }
            }
        }
    }

    private func scoreCard(_ c: (icon: String, tint: Color, value: String, label: String, spoken: String?)) -> some View {
        VStack(spacing: 8) {
            Image(systemName: c.icon).font(.title2).foregroundStyle(c.tint)
            Text(c.value)
                .scaledSystemFont(28, weight: .bold, design: .rounded, relativeTo: .largeTitle)
                .foregroundStyle(.white).monospacedDigit()
            Text(c.label).font(.caption).foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: isPhoneIdiom ? .infinity : nil)
        .frame(width: isPhoneIdiom ? nil : 150, height: isPhoneIdiom ? 104 : 120)
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
        VStack(spacing: 8) {
            Text(zh ? "复习这些词(点 ★ 收藏):" : "Review these (tap ★ to save):")
                .font(.caption).foregroundStyle(Theme.dim)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 8)], spacing: 8) {
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
                                Image(systemName: "speaker.wave.2")
                                    .scaledSystemFont(12).foregroundStyle(Theme.accent2)
                                    .frame(width: 28, height: 28)
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
