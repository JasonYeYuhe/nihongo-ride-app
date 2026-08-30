import SwiftUI
import VocabKit

/// In-app About / Credits screen. Required for App Store submission because
/// our bundled data sources (Mozc, Tanos JLPT, Bluskyo, Tatoeba) carry
/// attribution obligations under their respective licenses.
struct AboutView: View {
    @Environment(AppModel.self) private var model
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
                       en: "Inspiration corpus for the 183 Practice-mode passages (most are LLM-original; see THIRD_PARTY_LICENSES.md).",
                       zh: "Practice 模式 183 篇文章的灵感语料(大多为 LLM 原创衍生,详见 THIRD_PARTY_LICENSES.md)。")
                credit("WanaKana (reference)",
                       license: "MIT",
                       url: "https://github.com/WaniKani/WanaKana",
                       en: "Romaji trie / gemination design inspiration for the engine.",
                       zh: "引擎设计参考(trie / 促音构造思路)。")

                Divider().background(Theme.cardStroke).padding(.vertical, 4)
                section(
                    title: zh ? "数据声明" : "Data disclosure",
                    body: zh
                        ? "中英文释义、例句与文章主要由大语言模型(Gemini 3.1 Pro)起草并经多轮独立机器审核;读音与等级以 Bluskyo 数据为准,异常项已剔除。正式发布的母语审仍是必备的最后一步。"
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
            HStack {
                Text(zh ? "关于" : "About")
                    .scaledSystemFont(32, weight: .heavy, design: .rounded, relativeTo: .largeTitle)
                    .foregroundStyle(.white)
                Spacer()
                Button(action: model.backToMenu) {
                    Label(zh ? "返回" : "Back", systemImage: "chevron.left")
                        .scaledSystemFont(14, weight: .semibold)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Theme.card, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.cardStroke))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            Text("Nihongo Ride · v\(bundleVersion)")
                .scaledSystemFont(13, weight: .medium, design: .monospaced)
                .foregroundStyle(Theme.accent2)
            Text(zh ? "打字环游日本 · macOS / iOS · SwiftUI" : "Type your way across Japan · macOS / iOS · SwiftUI")
                .scaledSystemFont(14).foregroundStyle(Theme.dim)
        }
    }

    private func section(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .scaledSystemFont(11, weight: .black).tracking(3)
                .foregroundStyle(Theme.accent)
            Text(body)
                .scaledSystemFont(14)
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func credit(_ name: String, license: String, url: String, en: String, zh zhText: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
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
            Text(zh ? zhText : en)
                .scaledSystemFont(13)
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            Text(url)
                .scaledSystemFont(12, weight: .regular, design: .monospaced)
                .foregroundStyle(Theme.dim)
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
            Text(label.uppercased()).scaledSystemFont(10, weight: .bold).tracking(2).foregroundStyle(Theme.dim)
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
                .foregroundStyle(Theme.dim)
            Text(zh ? "有问题、看法,或者想要某条路线 —— 写信来。"
                    : "Questions, thoughts, or a route you want — write in.")
                .scaledSystemFont(11).foregroundStyle(Theme.dim.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: "yyyyy.yeyuhe@gmail.com")
                .scaledSystemFont(11, design: .monospaced)
                .foregroundStyle(Theme.dim.opacity(0.85))
                .textSelection(.enabled)
        }
        .padding(.top, 6)
        .accessibilityIdentifier("contactAddress")
    }

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text((zh ? "本机计数" : "On-device counters").uppercased())
                .scaledSystemFont(10, weight: .black).tracking(2)
                .foregroundStyle(Theme.dim)
            // "The two lines below" was true until `shareableSummary` gained its own second line
            // for the kyoto column. Counts the blocks rather than the lines, so the sentence stays
            // true the next time either summary grows.
            Text(zh
                 ? "只存在这台设备上,从不上传。如果你写信来,把下面的计数一起贴上会很有帮助。"
                 : "Local to this device and never transmitted. If you write in, pasting the counters below helps.")
                .scaledSystemFont(11).foregroundStyle(Theme.dim.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            Text(model.unlockOfferLedger.shareableSummary)
                .scaledSystemFont(10, design: .monospaced)
                .foregroundStyle(Theme.dim.opacity(0.7))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Text(model.reviewPromptLedger.debugSummary)
                .scaledSystemFont(10, design: .monospaced)
                .foregroundStyle(Theme.dim.opacity(0.7))
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
            .foregroundStyle(Theme.dim.opacity(0.7))
            .italic()
    }
}
