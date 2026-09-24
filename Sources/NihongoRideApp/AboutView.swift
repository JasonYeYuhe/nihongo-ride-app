import SwiftUI
import VocabKit

/// In-app About / Credits screen. Required for App Store submission because
/// our bundled data sources (Mozc, Tanos JLPT, Bluskyo, Tatoeba) carry
/// attribution obligations under their respective licenses.
struct AboutView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    private var zh: Bool { model.languageCode == "zh" }

    private let bundleVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"

    var body: some View {
        // Use a ScrollView at runtime so content adapts to short windows; in
        // headless screenshot mode we drop the ScrollView (it doesn't lay out
        // its contents inside ImageRenderer).
        let content = VStack(alignment: .leading, spacing: 22) {
                header
                Divider().background(Theme.cardStroke).padding(.vertical, 4)
                section(
                    title: zh ? "感谢" : "Acknowledgements",
                    body: zh
                        ? "Nihongo Ride 借助多个开源/开放许可的语言数据,才得以做出一个真正帮你学日语的打字游戏。下方列出每一项的来源、许可与用途。"
                        : "Nihongo Ride is built on top of several openly licensed language data sources. Below: every source, its license, and what we use it for."
                )
                credit("Google Mozc",
                       license: "BSD-3-Clause",
                       url: "https://github.com/google/mozc",
                       en: "Romaji-to-kana table — the data behind the typing engine.",
                       zh: "罗马字↔假名映射表 — 打字引擎的数据基础。")
                credit("Jonathan Waller — JLPT Resources (Tanos)",
                       license: "CC BY",
                       url: "https://www.tanos.co.uk/jlpt/",
                       en: "JLPT level data for the N5–N1 vocabulary classification.",
                       zh: "JLPT N5–N1 词汇分级数据。")
                credit("Bluskyo / JLPT_Vocabulary",
                       license: "MIT (Tanos CC BY derivative)",
                       url: "https://github.com/Bluskyo/JLPT_Vocabulary",
                       en: "Word forms + authoritative readings + levels (the source of our -b / -k entries).",
                       zh: "词形 + 权威读音 + 等级(本作 -b / -k 词条来源)。")
                credit("EDRDG — JMdict / EDICT",
                       license: "CC BY-SA 4.0",
                       url: "https://www.edrdg.org/jmdict/j_jmdict.html",
                       en: "Verb-class facts for the conjugation practice (only the derived class label ships, no dictionary text).",
                       zh: "动词变形练习的词类事实(仅 ship 派生的类标签,不含词典原文)。")
                credit("Tatoeba Project",
                       license: "CC BY 2.0 FR",
                       url: "https://tatoeba.org",
                       // DERIVED, not typed. This said 183 while `stats` twelve lines below
                       // printed `PassageStore.shared.passages.count` — 233 — so one screen
                       // contradicted itself, on the surface that carries a licence attribution.
                       // A number in copy beside the same number computed is this repo's
                       // signature defect at its smallest. (v1.32 §F1.)
                       en: "Inspiration corpus for the \(PassageStore.shared.passages.count) Practice-mode passages (most are LLM-original; see THIRD_PARTY_LICENSES.md).",
                       zh: "Practice 模式 \(PassageStore.shared.passages.count) 篇文章的灵感语料(大多为 LLM 原创衍生,详见 THIRD_PARTY_LICENSES.md)。")
                credit("WanaKana (reference)",
                       license: "MIT",
                       url: "https://github.com/WaniKani/WanaKana",
                       en: "Romaji trie / gemination design inspiration for the engine.",
                       zh: "引擎设计参考(trie / 促音构造思路)。")

                Divider().background(Theme.cardStroke).padding(.vertical, 4)
                section(
                    title: zh ? "数据声明" : "Data disclosure",
                    body: zh
                        // "母语审核": the 核 was missing, so the sentence named its last step with
                        // a word that is not one. It now says what the English beside it says —
                        // a native-speaker review is still the required final step before
                        // release — in the word the sentence already uses for the machine audit
                        // (机器审核). (v1.33 §B S)
                        ? "中英文释义、例句与文章主要由大语言模型(Gemini 3.1 Pro)起草并经多轮独立机器审核;读音与等级以 Bluskyo 数据为准,异常项已剔除。正式发布的母语审核仍是必备的最后一步。"
                        : "Chinese and English glosses, example sentences and passages are LLM-drafted (Gemini 3.1 Pro) and audited; readings & levels follow Bluskyo's authoritative data with errors removed. A native-speaker review pass is still the required final step before release."
                )
                stats
                contact
                diagnostics
                Spacer(minLength: 18)
                footerNote
            }
            .padding(isPhoneIdiom ? 22 : 40)
            .frame(maxWidth: 760, alignment: .leading)

        return Group {
            if Screenshotter.isCapturing {
                content
            } else {
                ScrollView { content }
            }
        }
        .frame(maxWidth: .infinity)
        .background {
            if !Screenshotter.isCapturing {
                KeyCaptureView(
                    onKey: { _ in },
                    onCommand: { command in
                        if command == .escape || command == .returnKey { model.backToMenu() }
                    },
                    suppressSoftwareKeyboard: true
                )
            }
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Back first, then the title, at the accessibility sizes; the row as it was below them.
            //
            // CoreText at AX5 on a 393pt phone: "About" ~167pt + Back ~162pt + spacing = 345pt of
            // a 349pt row — a 4pt margin, gone the moment the chevron's gap is a little wider than
            // assumed or the phone a little narrower ("Abou / t" or "Ba / ck").
            //
            // **Not `ScreenHeader`, deliberately.** Tried on 2026-09-17 with `subtitle` made
            // optional and rendered: `about.png` changed in 864,427 pixels — the whole page moved
            // five pixels (2.5pt), because `ScreenHeader`'s row aligns on `.firstTextBaseline`
            // where this one centres, which makes the row taller. It also draws a phone title at
            // 28pt, not 32. So the same switch is written here with this header's own pieces, and
            // the default size stays pixel-identical. (v1.33 §B S)
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    backButton
                    headerTitle.minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack {
                    headerTitle
                    Spacer()
                    backButton
                }
            }
            Text("Nihongo Ride · v\(bundleVersion)")
                .scaledSystemFont(13, weight: .medium, design: .monospaced)
                .foregroundStyle(Theme.accent2)
            Text(zh ? "打字环游日本 · macOS / iOS · SwiftUI" : "Type your way across Japan · macOS / iOS · SwiftUI")
                .scaledSystemFont(14).foregroundStyle(Self.dimTextColor)
        }
    }

    private var headerTitle: some View {
        Text(zh ? "关于" : "About")
            .scaledSystemFont(32, weight: .heavy, design: .rounded, relativeTo: .largeTitle)
            .foregroundStyle(.white)
    }

    /// It had no identifier, so no UI test could land on About; `aboutBackButton` follows the
    /// `<screen>BackButton` pattern of the others. Nothing matched this button before (checked:
    /// no test under `Tests/` mentions About or queries a Back button by its label).
    private var backButton: some View {
        Button(action: model.backToMenu) {
            Label(zh ? "返回" : "Back", systemImage: "chevron.left")
                .scaledSystemFont(14, weight: .semibold)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Theme.card, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.cardStroke))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("aboutBackButton")
    }

    private func section(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .scaledSystemFont(11, weight: .black).tracking(3)
                .foregroundStyle(Theme.accent)
                // "ACKNOWLEDGEMENTS" is one word, so wrapping it can only break it: measured on an
                // iPhone 17 Pro at AX5 (2026-09-17, `A_about_en_ax5.png`) it read
                // "ACKNOWLEDGEMEN / TS". At the accessibility sizes it keeps one line and may
                // shrink. CoreText, tracking held at 3pt: it needs ~443pt at AX5 against 349pt on
                // a 393pt phone (×0.76) and 331pt on a 375pt one (×0.71); the floor of 0.5 leaves
                // room for a narrower column still, and at AX5 half size is 17pt — half again
                // larger than the 11pt this label is at the default size. Below AX1 these are the
                // environment's own defaults (no line limit, no shrink), i.e. what it was.
                // (v1.33 §B S)
                .lineLimit(typeSize.isAccessibilitySize ? 1 : nil)
                .minimumScaleFactor(typeSize.isAccessibilitySize ? 0.5 : 1)
            Text(body)
                .scaledSystemFont(14)
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func credit(_ name: String, license: String, url: String, en: String, zh zhText: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // **The name above its licence at the accessibility sizes**; side by side below them,
            // as it was. Side by side, the two split one row: measured on an iPhone 17 Pro at AX5
            // (2026-09-17, `B_about_p4_en_ax5.png`) the name took five lines — "Bluskyo", "/",
            // "JLPT_V", "ocabula", "ry" — beside a licence that also took five, "derivat" /
            // "ive)" among them, in a capsule turned into a blob. On its own line in the ~321pt
            // card column every licence but one fits whole (CoreText: "BSD-3-Clause" and
            // "CC BY-SA 4.0" ~254pt), and
            // "MIT (Tanos CC BY derivative)" wraps at its spaces, onto two lines — which is why
            // the badge is a rounded rectangle there: a two-line capsule's ends cut into its first
            // and last letters. (v1.33 §B S)
            if typeSize.isAccessibilitySize {
                Text(Self.breakingIdentifiers(name))
                    .scaledSystemFont(15, weight: .semibold)
                    .foregroundStyle(.white)
                Text(license)
                    .scaledSystemFont(11, weight: .bold, design: .monospaced)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Theme.accent2.opacity(0.22), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(Theme.accent2)
            } else {
                HStack(spacing: 8) {
                    Text(name)
                        .scaledSystemFont(15, weight: .semibold)
                        .foregroundStyle(.white)
                    Text(license)
                        .scaledSystemFont(11, weight: .bold, design: .monospaced)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Theme.accent2.opacity(0.22), in: Capsule())
                        .foregroundStyle(Theme.accent2)
                }
            }
            Text(typeSize.isAccessibilitySize ? Self.breakingIdentifiers(zh ? zhText : en) : (zh ? zhText : en))
                .scaledSystemFont(13)
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            Text(typeSize.isAccessibilitySize ? Self.breakingIdentifiers(url) : url)
                .scaledSystemFont(12, weight: .regular, design: .monospaced)
                .foregroundStyle(Self.dimTextOnCardColor)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.cardStroke))
        // One element: name + license + description. The raw URL is excluded so
        // VoiceOver doesn't spell out "h-t-t-p-s-colon-slash-slash…".
        .accessibilityElement()
        .accessibilityLabel("\(name), \(license). \(zh ? zhText : en)")
    }

    /// `text` with a zero-width space after every underscore, so an identifier-like name can
    /// break between its parts instead of wherever the column runs out.
    ///
    /// "JLPT_Vocabulary" and "THIRD_PARTY_LICENSES.md" are one unbreakable run to the line
    /// breaker (an underscore is an ordinary letter to it, and "." before letters does not allow
    /// a break either), and at AX5 each is wider than the card: CoreText lays them out as
    /// "JLPT_Vocabul / ary" and "THIRD_PARTY_LI / CENSES.md)." — the simulator showed
    /// "THIRD_PARTY_LICE / NSES.md" (`B_about_p8_en_ax5.png`). With U+200B after each underscore
    /// they break as "JLPT_ / Vocabulary" and "THIRD_ / PARTY_ / LICENSES.md).": still broken, as
    /// a name wider than the screen has to be, but between words that can each be read.
    ///
    /// A zero-width space has no advance in SF Pro or SF Mono (measured: identical widths with and
    /// without it), so nothing moves where no break is needed. Used ONLY at the accessibility
    /// sizes — below them the strings are passed through untouched — and never in the VoiceOver
    /// label, which is built from the plain strings above. (v1.33 §B S)
    nonisolated static func breakingIdentifiers(_ text: String) -> String {
        text.replacingOccurrences(of: "_", with: "_\u{200B}")
    }

    private var stats: some View {
        let vocab = model.vocab.entries.count
        let passages = PassageStore.shared.passages.count
        return HStack(spacing: 20) {
            stat(label: zh ? "词汇" : "Words", value: "\(vocab)")
            stat(label: zh ? "文章" : "Passages", value: "\(passages)")
            stat(label: zh ? "等级" : "Levels", value: "N5–N1")
        }
        .padding(.top, 4)
    }

    private func stat(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).scaledSystemFont(22, weight: .bold, design: .rounded).foregroundStyle(.white)
            Text(label.uppercased()).scaledSystemFont(10, weight: .bold).tracking(2).foregroundStyle(Self.dimTextOnCardColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }

    /// The one place the local counters can actually be read.
    ///
    /// §G licenses local, never-transmitted counting with the distinction the first draft got
    /// wrong — *Data Not Collected forbids collecting, not counting* — and it names two readout
    /// paths: a debug view, and something a customer can attach to a support message. **Neither
    /// existed.** `ReviewPromptLedger.debugSummary` has had zero call sites since v1.27, and the
    /// Stage 1 counter shipped its first version the same way: a type whose whole justification
    /// is "a customer can choose to send it" with nothing anywhere for them to send.
    ///
    /// Deliberately plain text rather than a mail composer. It is selectable, it is at the bottom
    /// of a screen nobody visits by accident, and it asks for nothing. The honest limit is on
    /// `UnlockOfferLedger` itself: the one measured base rate for a customer of this app
    /// volunteering anything is one message per 109 installs, so this cannot estimate a rate. It
    /// can let a single person refute a universal, and it can prove to the OWNER that the counter
    /// fires at all — which is the reader it will actually have.
    /// Somewhere to write. **The block below this one has been telling people to write in since
    /// v1.30's first build, and the app contained no address, no `mailto:`, and no tappable link
    /// anywhere** — so the sentence "if you write in, pasting the two lines below helps" named an
    /// action the product did not offer.
    ///
    /// That is not only a courtesy problem. §K's day-90 decision has a branch that turns a zero
    /// into evidence, and it requires at least one voluntarily returned counter; without a return
    /// path that branch cannot fire, so the pre-registered outcome was fixed at "record the zero
    /// as UNINTERPRETABLE" by construction rather than by evidence. This is the only lever on that
    /// probability that changes neither price nor offer.
    ///
    /// Plain selectable text, matching `diagnostics` below: no mail composer, no "contact us"
    /// prompt, nothing sent by the app, and nothing asked for. The address is the one already
    /// published on the support page that the App Store product page links to, so this discloses
    /// nothing new — it just stops making the reader go and find it.
    ///
    /// Its honest limit is the same as the counter's: the measured base rate for a customer of
    /// this app volunteering anything is one message per 109 installs. This cannot produce a rate.
    /// It can let one person refute a universal.
    private var contact: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text((zh ? "联系" : "Contact").uppercased())
                .scaledSystemFont(10, weight: .black).tracking(2)
                .foregroundStyle(Self.dimTextColor)
            Text(zh ? "有问题、看法,或者想要某条路线 —— 写信来。"
                    : "Questions, thoughts, or a route you want — write in.")
                .scaledSystemFont(11).foregroundStyle(Self.dimTextColor)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: "yyyyy.yeyuhe@gmail.com")
                .scaledSystemFont(11, design: .monospaced)
                .foregroundStyle(Self.dimTextColor)
                .textSelection(.enabled)
        }
        .padding(.top, 6)
        .accessibilityIdentifier("contactAddress")
    }

    /// The colour of the two counter lines — their colour only; their text and format are frozen
    /// (PLAN-V1.33 §C: §K's STOP branch reads counters a customer copies back).
    ///
    /// They were `Theme.dim.opacity(0.7)`, white at 0.315, measured on the simulator at 2.78–2.84:1
    /// (`B_about_p3_en_large.png`) against WCAG's 4.5:1. Recomputed from the colour values: the
    /// block is NOT in a card — it sits straight on `Theme.background`, and scrolls over all of it,
    /// so the worst case is the gradient's lightest stop, (0.10, 0.14, 0.26), luminance 0.0185.
    /// Compositing is source-over on the sRGB values (predicts the simulator's (96,103,123) text
    /// pixel over (23,32,61) to within one unit):
    ///
    /// * white at 0.315 → (0.384, 0.411, 0.493), luminance 0.141 → (0.141 + 0.05) / (0.0185 + 0.05)
    ///   = **2.79:1**;
    /// * white at 0.47 → 4.49:1, a hair short;
    /// * white at **0.48** → (0.532, 0.553, 0.615), luminance 0.267 → **4.62:1** (4.61:1 after
    ///   8-bit quantisation); 4.91:1 at the top stop.
    ///
    /// So 0.48 is the smallest opacity that clears 4.5:1 wherever the block can scroll. It is lower
    /// than Settings' caption colour (0.51) because Settings' captions sit on a card, which lightens
    /// what is behind them. `V133SContrastTests` recomputes both. (v1.33 §B S)
    static let counterColor = Color.white.opacity(0.48)

    /// Every other small dim text on About that sits straight on the background, at
    /// `counterColor`'s arithmetic.
    ///
    /// 1.33 recoloured the two counter lines and left the rest (PLAN-V1.33 §G): the footer note
    /// (`Theme.dim.opacity(0.7)`, 2.79:1 at the bottom stop), the contact and counter prompts
    /// (`.opacity(0.8)`, 3.23:1), the address (`.opacity(0.85)`, 3.46:1) — and, measured for this
    /// item rather than listed in 1.33, the header's subtitle and the two small-caps titles at
    /// plain `Theme.dim`, white at 0.45: over the bottom stop that is (0.505, 0.527, 0.593),
    /// luminance 0.240 → **4.24:1**, over the line at the top stop (4.47:1) and under it once the
    /// page has scrolled. None of these is in a card, so the worst case is the counters' worst
    /// case: white at 0.47 → 4.49:1 (4.48 after 8-bit quantisation), white at **0.48** →
    /// 4.62:1. The same number as `counterColor` in a second constant, deliberately: the counters'
    /// colour is held beside their frozen text and pinned to exactly its two readers
    /// (`V133SContrastTests.aboutUsesTheCounterColor`); the prose is not frozen and should not
    /// share that pin. `V134B4AboutContrastTests` recomputes both. (v1.34 §B4)
    static let dimTextColor = Color.white.opacity(0.48)

    /// The credit URLs and the stat labels, which sit on `Theme.card`, not on the background.
    ///
    /// The card is white at 0.06 over the gradient, so it is lighter than what is behind it and
    /// the same white needs more opacity to stand off it. At the bottom stop the card is
    /// (0.154, 0.192, 0.304), luminance 0.0317; `Theme.dim` over that is (0.535, 0.555, 0.617),
    /// luminance 0.270 → **3.91:1**; white at 0.50 → 4.46:1, still short; white at **0.51** →
    /// (0.585, 0.604, 0.659), luminance 0.324 → 4.57:1 (4.56 quantised), 5.03:1 at the top stop.
    /// It is `SettingsView.captionColor`'s number for `SettingsView.captionColor`'s reason — the
    /// same card over the same gradient — written here rather than read from Settings so that
    /// every colour About draws is next to the arithmetic that produced it. (v1.34 §B4)
    static let dimTextOnCardColor = Color.white.opacity(0.51)

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text((zh ? "本机计数" : "On-device counters").uppercased())
                .scaledSystemFont(10, weight: .black).tracking(2)
                .foregroundStyle(Self.dimTextColor)
            // "The two lines below" was true until `shareableSummary` gained its own second line
            // for the kyoto column. Counts the blocks rather than the lines, so the sentence stays
            // true the next time either summary grows.
            Text(zh
                 ? "只存在这台设备上,从不上传。如果你写信来,把下面的计数一起贴上会很有帮助。"
                 : "Local to this device and never transmitted. If you write in, pasting the counters below helps.")
                .scaledSystemFont(11).foregroundStyle(Self.dimTextColor)
                .fixedSize(horizontal: false, vertical: true)
            Text(model.unlockOfferLedger.shareableSummary)
                .scaledSystemFont(10, design: .monospaced)
                .foregroundStyle(Self.counterColor)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Text(model.reviewPromptLedger.debugSummary)
                .scaledSystemFont(10, design: .monospaced)
                .foregroundStyle(Self.counterColor)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
        .accessibilityIdentifier("onDeviceCounters")
    }

    private var footerNote: some View {
        Text(zh
             ? "感谢所有开源项目的维护者,以及让 Tatoeba 句子被翻译成数十种语言的志愿者们。"
             : "Thanks to the maintainers of every open project above, and to the volunteers who translated Tatoeba sentences into dozens of languages.")
            .scaledSystemFont(12)
            .foregroundStyle(Self.dimTextColor)
            .italic()
    }
}
