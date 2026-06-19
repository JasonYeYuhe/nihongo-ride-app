# Nihongo Ride — v1.4 计划(iCloud 同步上线 + 下一个功能)

> 写于 2026-06-19。状态:**v1.3(Game Center)双端 WAITING_FOR_REVIEW**;v1.2 在售。
> v1.3 把 iCloud 推迟到这一版。本文锁定 v1.4 的路径,并记录我这轮核实出来的两个约束。

---

## 1. v1.4 主线 = iCloud 同步上线(代码已就绪)

CKSyncEngine 同步代码 v1.2/v1.3 已写完、编译验证过,只是关着(`cloudSyncAvailable=false` + entitlement 撤出)。上线只差**真机/后台步骤,这些只有 Jason 能做**:

1. **开发者后台**:给 App ID 的 iCloud 能力**创建并指定 CloudKit 容器** `iCloud.com.jasonye.nihongoride`(当前能力已开,但容器未建/未挂 → 这就是 v1.3 归档签 iCloud 失败的原因)。
2. **真机/模拟器**(登 iCloud)跑一次 debug 版 → CKSyncEngine 即时(JIT)生成 schema → **CloudKit Dashboard 把 schema 部署到 Production**(漏了上架后真机同步全空)。
3. **双设备验证**:同账号两台设备 —— A 复习 → B due 增加;A 跑一局 → B 多一条历史 + 里程累加(不是覆盖);离线改 → 联网收敛。

**Jason 做完 1–3 后,我这边一步到位**:恢复两端 iCloud entitlement(project.yml + 两个 .entitlements)→ 翻 `cloudSyncAvailable=true` → 版本升 1.4(macOS build 5 / iOS build 6)→ build+upload+提交(全 ASC API,跟 v1.2/v1.3 一样)。App Privacy 复核仍「Data Not Collected」(私有库)。

---

## 2. 这轮核实出来的两个约束(影响选下一个功能)

- **动词变位(verb conjugation)暂不可做**:词库 **7074 条全部 `partsOfSpeech` 为空** —— 没有词性/动词类别(godan/ichidan/irregular)数据,而光看词形无法可靠判类(帰る/走る 是五段却以る结尾)。要做变位练习,得**先给动词词条补类别标注**(走内容流水线 + QA),才能建变位引擎。
- **内容生成流水线当前是坏的**:`scripts/gen_examples.py` / `gen_passages.py` 调的是**已停用的 `gemini` CLI**。改用 `agy` 不是直接换命令就行 —— `agy -p` 有 stdout bug(答案不进 stdout),脚本得像那个 MCP 桥一样**读 agy 的 transcript 文件**。所以「例句继续扩 / 母语者审回填生成」要先写个小的 `agy` 查询助手把流水线接通。

---

## 3. v1.4 下一个功能(候选,挑一个或先不带)

主线已是 iCloud。是否再捎一个**不需要新数据、纯代码可做**的功能:

- **A. 自定义词单 / Custom word lists** —— 用户自建/收藏词,生成练习。纯数据+UI+接 GameSession,可单测,完全能自主做。
- **B. 文章导入 / 粘贴自定义文本练习** —— 复用 Practice 引擎,让用户练任意假名文本。基本可做(注意非游戏屏键盘抑制那条红线 + 文本输入入口)。
- **C. 母语者审回填** —— 若 Jason 已在 `review-sheets/*.csv` 填了 correction,我跑 `import_review_sheets.py` 回填(不需新工具)。

**约束类(要先搭地基才能做)**:动词变位(需补词性数据)、例句扩充(需把流水线接到 agy)。

---

## 4. 建议 & 待 Jason 拍板

- **建议**:v1.4 = **iCloud 同步单发**(它是最大的待发价值,只差你的真机三步);功能(A/B)留 v1.5,或如果想 v1.4 更厚就捎上 **A(自定义词单)**(最自包含、可单测)。
- **待你决定**:① iCloud 三步什么时候做(我做不了);② v1.4 是否捎一个功能,捎哪个(默认:先不捎,iCloud 单发)。

> 你说"直接推进"——iCloud 主线卡在你的真机步骤,动词变位卡在数据,内容流水线卡在 agy 接线。所以最干净的自主推进是:**(a)** 我现在就把 agy 内容助手 / `import_review_sheets` 这类地基做了,或 **(b)** 直接开 A(自定义词单)。你点一下方向我就开干;不点的话我默认先做 A(自包含、零风险、可单测)。
