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
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Button(action: model.backToMenu) {
                    Label(zh ? "返回" : "Back", systemImage: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Theme.card, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.cardStroke))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            Text("Nihongo Ride · v\(bundleVersion)")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.accent2)
            Text(zh ? "打字环游日本 · macOS / iOS · SwiftUI" : "Type your way across Japan · macOS / iOS · SwiftUI")
                .font(.system(size: 14)).foregroundStyle(Theme.dim)
        }
    }

    private func section(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .black)).tracking(3)
                .foregroundStyle(Theme.accent)
            Text(body)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func credit(_ name: String, license: String, url: String, en: String, zh zhText: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text(license)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Theme.accent2.opacity(0.22), in: Capsule())
                    .foregroundStyle(Theme.accent2)
            }
            Text(zh ? zhText : en)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            Text(url)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(Theme.dim)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.cardStroke))
    }

    private var stats: some View {
        let vocab = VocabStore.shared.entries.count
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
            Text(value).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(.white)
            Text(label.uppercased()).font(.system(size: 10, weight: .bold)).tracking(2).foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 8))
    }

    private var footerNote: some View {
        Text(zh
             ? "感谢所有开源项目的维护者,以及让 Tatoeba 句子被翻译成数十种语言的志愿者们。"
             : "Thanks to the maintainers of every open project above, and to the volunteers who translated Tatoeba sentences into dozens of languages.")
            .font(.system(size: 12))
            .foregroundStyle(Theme.dim.opacity(0.7))
            .italic()
    }
}
