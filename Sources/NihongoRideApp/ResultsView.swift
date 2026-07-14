import SwiftUI
import VocabKit

struct ResultsView: View {
    @Environment(AppModel.self) private var model

    private var zh: Bool { model.languageCode == "zh" }
    /// Word whose "add to lists" multi-select sheet is open (long-press a chip).
    @State private var addToListsTarget: String?

    var body: some View {
        // iPhone: results (cards + review list) outgrow the screen — scroll.
        Group {
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

    private var content: some View {
        let summary = model.lastSummary

        return VStack(spacing: 20) {
            Spacer(minLength: 0)

            Text("🏁")
                .scaledSystemFont(50, relativeTo: .largeTitle)
                .accessibilityHidden(true)
            Text(zh ? "到站!" : "You've arrived!")
                .scaledSystemFont(isPhoneIdiom ? 30 : 36, weight: .heavy, design: .rounded, relativeTo: .largeTitle)
                .foregroundStyle(.white)

            if let summary {
                grade(for: summary)
                scoreGrid(summary)
                if !summary.reviewWords.isEmpty {
                    reviewList(summary.reviewWords)
                }
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
                            // Read-aloud (v1.9 §C): a nested tap-target reads the word's kana; the
                            // innermost gesture wins so it doesn't also toggle the chip's ★. No
                            // keyboard summon here — results suppresses the keyboard (not a game screen).
                            if canSpeak {
                                Image(systemName: "speaker.wave.2")
                                    .scaledSystemFont(10).foregroundStyle(Theme.accent2)
                                    .padding(.leading, 2).contentShape(Rectangle())
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
