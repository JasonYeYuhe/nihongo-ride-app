# 商标检索报告 — "Nihongo Dash"

> 2026-06 由 Gemini 3.1 Pro 联网检索;**仅作初筛参考,正式申请前需委托律所/代理做正式查册**(USPTO TESS、JPO J-PlatPat、EUIPO eSearch 的交互界面需要登录/防爬验证,LLM 检索只能覆盖公开 web 索引)。

## 结论:🚫 不建议沿用 "Nihongo Dash"

**直接撞名**——已有现成产品在用同一个名字:

- **kawaiiNihongo**(Marduk Corp 出品)内置一个名为 "Nihongo Dash" 的迷你游戏,定位:**日语学习**(与我们完全相同)。
  官网:https://kawaiinihongo.com
- 独立 App "Nihongo Dash Lite",Android 端在 APKPure 上架,2016 年起就在跑。
  Bundle ID:`com.mardukcorp.nihongodash`
  Listing:https://apkpure.com/nihongo-dash-lite/com.mardukcorp.nihongodash

按各市场:

| 市场 | 注册库 | 通用市场 |
|---|---|---|
| 🇺🇸 USPTO | 无注册商标 | ⚠️ Common Law 风险(同行业已在用 ≥ 2016)|
| 🇯🇵 JPO J-PlatPat | 无注册商标 | ⚠️ 不正当竞争防止法保护既有显著标识 |
| 🇪🇺 EUIPO | 无注册商标 | ⚠️ "passing off" 可被诉 |
| 🇬🇧 UK IPO | 无注册商标 | ⚠️ 同上 |

**Apple 上架审核**(App Store Review Guideline 5.2.3):涉嫌侵犯他方知识产权的名字会被拒。
Marduk 完全可在我们提交后向 Apple 投诉(只需一份证据),Apple 通常会下架被指控的 App。

## 「寿司打」/「Sushida」相关

「寿司打」(Sushida)是日本注册商标,且是最知名的日语打字游戏。我们的产品**与寿司打不同**(寿司打侧重反应/计速,我们侧重学习),但:
- ❌ 文案中不要直接对标 "like Sushida"
- ✅ 可以用 "kanji typing game" / "Japanese typing practice" 等类目描述
- ✅ 骑行环游 + 等级/SRS 是我们的差异化,放大它

## 替代命名方案

按推荐度排:

### A. ⭐ Kana Dash
- 直接点出核心机制(打**假名**)
- 仍保留你「Dash」系列的命名结构
- 5 字符 + 5 字符,品牌念起来干净
- 还可衍生:Kana Dash Lite / Kana Dash Pro
- **风险:** 还需正式查;但比 "Nihongo Dash" 通用得多,而且"kana"指向更窄

### B. Kotoba Dash(言葉 Dash)
- "kotoba" = "words / language"
- 文学感 + 实用感
- 不撞 "Nihongo" 已撞商标

### C. ⭐ Tabikana(旅かな)
- 你最早的提议(本会话开头我提的工作名)
- 旅 + かな,对应「打字环游日本」主玩法
- 极独特,商标空间几乎肯定空
- **缺点:**「Dash」系列形态丢了一半;但旅(tabi)在系列里也可以做不同语言的变体(Tabihangul、Tabipinyin、Tabilangue……)

### D. Romaji Dash
- 描述准确(罗马字输入打日语)
- 但对不会日语的人 "Romaji" 一词较陌生

### E. Hop / Sprint / Run 系前缀替代「Dash」
- "Nihongo Sprint" / "Kana Sprint"
- 同义词避开 "Dash" 与 Sushida 的关联

### F. 完全脱离日语词
- 例:"Tegami"(手紙=信)、"Sora"(空=天)、"Hikari"(光)
- 简洁、Apple 风,但需做完整商标检索

## 我的建议

**首选 A. Kana Dash**,保留你的视觉资产(图标里那个键盘骑手),改名成本极低:
- `Package.swift`:`name: "KanaDash"`
- `Sources/NihongoDashApp/` → `Sources/KanaDashApp/`
- `project.yml`:`PRODUCT_BUNDLE_IDENTIFIER: com.jasonye.kanadash`,`CFBundleName: Kana Dash`
- 文案里 "Nihongo Dash" → "Kana Dash"
- App Icon 不变(那张「え」骑行图标完全适用)
- 整套 8 个图标(日/中/法/西/韩)未来命名:Kana Dash / Hanyu Dash / Mots Dash / Letras Dash / Geul Dash 之类

**改名总耗时估计 ~30 min**(全字串替换 + 测试 + 重新跑截图)。

## 上架前最终防线

无论用哪个名字:
1. **正式查册**:在 USPTO TESS 和 J-PlatPat 自己跑一遍交互式精确搜索(LLM 无法跑表单)
2. **找美国商标律所做 1-2 小时知识产权 freedom-to-operate 评估**($300-600 一次性,非常便宜的保险)
3. 上架后 **每月监控 App Store 是否有人 spoof / 抢注**

## 行动项

- [ ] 选定新名字(我建议 **Kana Dash**)
- [ ] 我跑全字串替换 + 测试 + 截图
- [ ] 你在 USPTO TESS https://tmsearch.uspto.gov 手动查新名一遍(免费,2 分钟)
- [ ] 你在 J-PlatPat https://www.j-platpat.inpit.go.jp 手动查新名一遍
- [ ] 准备好上架时 一次性付费 让律所做 freedom-to-operate 评估
