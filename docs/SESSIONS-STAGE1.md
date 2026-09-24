# SESSIONS-STAGE1 — the moderated-session kit

Written 2026-09-25 (JST), day 16 of the pre-registered window, from `PLAN-V1.34` §D2. **This is a kit, not
a record.** Nothing in this file is a result; results go where §6 says and nowhere else. Every on-screen
string below is quoted in 〔〕 verbatim from `Sources/` at commit `04947be` (whose `Sources/` tree is
byte-identical to `d232f42`, the last v1.33 fix), English first, then the Chinese interface's copy; the
file and line for each is in Appendix A. Apple's own UI (App Store, purchase sheets, system dialogs) is
never quoted in 〔〕, because nobody has checked those strings on the OS versions the participants run.

The kit is written so that the owner's part is the only part that costs anything. **It costs nothing if
it waits** (§7): no gate, no reading and no release depends on a session having run.

---

## §1 Purpose — the two questions no other instrument answers

`PLAN-WINDOW` §E calls moderated sessions with 10–15 recruited users the most valuable item available
during the window, and `PLAN-V2-PRODUCT` §H specifies the instrument: watch a session, then force a
choice between concrete packages. Everything else this repository measures is a count — first-time
downloads, purchases, refunds, a counter a stranger might one day volunteer. Counts answer *whether*;
none of them can answer *why*, and two questions in particular have no other instrument at all:

1. **Does anyone paste their own text?** `PLAN-ITERATION` §C3 shipped custom text practice-only *"so it
   does not touch SRS"*, and said the feature *"already answers the question that matters — will anyone
   paste their own material — and that answer is what decides whether the SRS half is worth building"*.
   It cannot answer it: the developer receives nothing from the app (§3 says what the app does send, and
   to whom), and no report from Apple says what a rider typed into a text field. `PLAN-V1.34` §D3's
   design for the expensive half of F1 is keyed to this tally (*"fewer than 2 of n pasted anything →
   shelved"*), and §B2's two improvements wait on it.
2. **What does a rider do when the queue is exhausted?** Once a rider has typed every word at a level,
   `startGame` refuses to build an empty run and the menu shows
   〔Nothing due at this level today — try another level, or come back tomorrow.〕/
   〔这个等级的词今天都复习完了,换个等级或明天再来。〕. Whether they change level, change mode, paste
   their own text, open the Ride Log, or close the app is the difference between "the app ran out" and
   "the rider was done" — and it is exactly the moment the Stage 3 catalogue would be sold into. No count
   distinguishes those.

A third thing the sessions produce is the forced choice (§4, day 2): which of four packages a rider
reaches for when each carries a price. That is `PLAN-V2-PRODUCT` §H's instrument as written, and its
prices are the owner's (§4.4).

What the sessions are **not**: not a test of the offer, not a conversion measurement, not a substitute
for the walk (`PLAN-STAGE1` §K/§L stay owner-only and untouched by this file), and not a source of
"returned counters" — `PLAN-STAGE1` §K's 2026-09-24 box, item 3, says a participant's device is never
evidence about arrival.

---

## §2 The registration rule (restated; the rule itself lives in `PLAN-STAGE1` §K)

The binding text is the box `📌 REGISTERED 2026-09-24, before the N = 35 row was read — recruited session
participants are walk installs` in `docs/PLAN-STAGE1.md` §K. This section restates its six items so a
moderator has them on one page, and then adds three rules the box does not contain, each with the
document it comes from. **If a restated item and the box ever disagree, the box wins and this section is
corrected by a dated addendum**; the three added rules are adjudicated by their named source, not by the
box, which says nothing about them.

**The box's six items, restated** (numbered as the box numbers them):

* **(1) A participant's install is a walk install.** The OWNER registers it in
  `docs/measurements/stage1-known-positives.json` as `kind = first_download` — real platform (`macOS` /
  `iOS`), real two-letter country code, real Pacific report day, `notes: "session participant"` — **the
  day it happens**, and in any case **before the next `--checkpoint` whose window contains that day**
  (`stage1-checkpoints.md` rule 4: an unregistered install is invisible to the tool). No tool writes the
  registry; the entry's shape is `DRAFTS-STAGE1-RECORDS.md` §5. `exclude_walk_first_downloads_from_N`
  is already `true`, so the entry is subtracted from N. Direction: smaller N, less ruled out.
* **(2) A participant's purchase is registered as `kind = purchase`** and subtracted; **GO never fires on
  it**; its refund, if any, is registered and is not a customer refund. Participants are never asked to
  buy anything (§4), so this rule exists for the case where one does so on their own.
* **(3) Participant counters are not returned counters.** A participant was asked to ride, so an
  `offerAppeared` in `kyoto` on their device is not evidence about arrival (§1 says the same from the
  other side: the sessions are not a source of "returned counters").
* **(4) Recruitment happens outside the App Store where possible**, and the number of installs it
  produced, by territory and platform, goes in the tally (§6). No recruiting channel is named here; the
  counts are what the record needs.
* **(5) The reconciliation rule is not relaxed.** An entry claiming more units in a `(day, kind, platform,
  country)` cell than the report holds withholds the bound; the owner records what really happened and
  the reading is withheld rather than adjusted. A dedicated `participant_download` kind would be an
  instrument change and waits, like every instrument change, for the known-positive to be confirmed.
* **(6) No session runs before the box exists.** It exists (2026-09-24); the register-before-the-next-
  `--checkpoint` obligation in item (1) is the box's item 6 extended to participants word for word.

**Three rules from other documents** — not in the box, so the box's precedence clause does not reach them;
each is corrected against the document named beside it:

* **A participant who already had the app is not a first install** (`DRAFTS-STAGE1-RECORDS.md` §5, and
  `scripts/sales_report.py`'s `REGISTRY_KINDS`, which lists `redownload`). They are not a "first ride"
  for §4 either; record which, and use `kind = redownload` if the report shows a redownload code — the
  DRAFTS §5 notes say how the kind is chosen after the report exists.
* **Never TestFlight** (`PLAN-V1.34` §D2, and §I's not-in-scope list) — an ASC write and a different
  StoreKit environment. The participant installs the release **on sale** from the App Store on their own
  device with their own account; `python3 scripts/stage1_walk.py preflight` prints which release that is
  on the day.
* **Never a walk device before §L is recorded** (`PLAN-V1.34` §D2; the devices are the ones
  `WALKCARD-STAGE1` names). The owner's Mac, the owner's iPhone and the family member's device are not
  session devices until `PLAN-STAGE1` §L carries its three outcomes. A participant's device is theirs,
  not the owner's.

---

## §3 Consent text

Read aloud or handed over before anything is installed. Plain, and no longer than it needs to be. The
participant keeps a copy. Their agreement is written in the moderator's private notes (§6) as "consent:
yes, <date>" — no signature file enters the repository.

### English

> **What this is.** You are helping the developer of Nihongo Ride, a Japanese typing app, understand how
> people use it. There are two short meetings: about 30 minutes today, and about 15 minutes tomorrow.
>
> **What you will do.** Install the app from the App Store on your own device, use it while I watch, and
> answer a few questions. Tomorrow you will use it again briefly and then choose between four described
> packages. **You will not be asked to buy anything, today or tomorrow**, and nothing in the app needs a
> purchase for this study.
>
> **What is recorded.** I take written notes of what you do and what is on the screen, and of what you say.
> **No audio or video is recorded** unless you agree to that separately. The app sends nothing to me or to
> this study: it has no account with the developer and no server of the developer's, and my notes are the
> study's only record.
>
> **What the app itself does with your data.** It keeps your progress on your device. If your device is
> signed in to iCloud, it also copies that progress — your review schedule, ride log, distance and word
> lists — into your own private iCloud database, so that your own devices agree. That is on by default;
> you can turn it off at any time under 〔Settings〕 → 〔iCloud Sync〕, with the switch
> 〔Sync review progress & ride log〕 (the note beneath it reads 〔Stored in your own private iCloud —
> visible only to you.〕). If your device is signed in to Game Center, the app submits your Time-mode
> scores and achievements to Game Center under your Apple Account. Neither the developer nor this study
> receives anything from either.
>
> **What becomes public.** The day, platform (Mac or iPhone/iPad) and country of your install are
> recorded, without your name, in a public count the developer keeps. Beyond that, only totals across all
> participants are published — and a sentence of yours only if I ask you at the time and you say yes.
> My notes about you personally are never published and never enter the app's public code repository.
>
> **You can stop at any time**, skip any question, and ask for your notes to be deleted. The app stays on
> your device afterwards if you want it; deleting it is fine too.

### 中文

> **这是什么。** 你在帮 Nihongo Ride(一个日语打字练习 app)的开发者了解大家是怎么用它的。一共两次短会面:今天大约
> 30 分钟,明天大约 15 分钟。
>
> **你要做什么。** 用你自己的设备从 App Store 安装这个 app,在我旁观的情况下使用它,回答几个问题。明天再短暂用一次,
> 然后在四个用文字描述的套餐里选一个。**今天和明天都不会请你购买任何东西**,这次研究里 app 的任何部分都不需要付费。
>
> **会记录什么。** 我会用文字记下你做了什么、屏幕上有什么、你说了什么。**不录音、不录像**,除非你另外单独同意。
> app 不会把任何东西发给我或这项研究:它没有开发者的账号,也没有开发者的服务器,我的笔记是这项研究唯一的记录。
>
> **app 自己会怎么处理你的数据。** 它把你的进度保存在你的设备上。如果设备登录了 iCloud,它还会把这些进度——复习计划、
> 骑行日志、里程和词单——复制到你自己的 iCloud 私有数据库里,让你自己的几台设备保持一致。这一项默认是打开的;你随时
> 可以在〔设置〕→〔iCloud 同步〕里关掉开关〔同步复习进度与骑行日志〕(开关下面的说明写着〔数据存于你自己的
> iCloud(私有库),仅你可见。〕)。如果设备登录了 Game Center,app 会用你的 Apple 账户把限时模式的成绩和成就提交到
> Game Center。这两项的数据,开发者和这项研究都收不到。
>
> **哪些会公开。** 你安装的日期、平台(Mac 还是 iPhone/iPad)和国家/地区会被记进开发者维护的一份公开计数里,
> 不带你的名字。除此之外,只发布所有参与者合起来的汇总;你说过的某一句话,只有在我当场问过、你说可以之后才会引用。
> 关于你个人的笔记永远不会发布,也永远不会进入这个 app 的公开代码仓库。
>
> **你随时可以停止**,可以跳过任何问题,也可以要求删除关于你的笔记。之后 app 留在你设备上还是删掉,都随你。

---

## §4 The 45-minute protocol

Two meetings: **day 1, ~30 minutes** (§4.1–4.2) and **day 2, ~15 minutes** (§4.3–4.4). The forced choice is
on day 2 on purpose: a rider who has come back once knows what they are choosing between; a rider ten
minutes into a first ride is choosing between descriptions.

Rules for the moderator, all of them:

* **Watch; do not steer.** No "try tapping that", no "have you seen Settings", no hints about the road,
  the route strip or anything with a price. If the participant asks what something does, say "what do
  you think?" once, then answer plainly and note that you answered.
* **The device is theirs.** You never touch it. You never sign an Apple Account in or out, never open
  TestFlight, never install anything else.
* **Nothing is bought.** If the participant reaches the road screen on their own and asks whether to buy:
  "not for this study — do what you would normally do". If they buy anyway, §2's purchase rule applies
  and the owner registers it that day.
* **Language is the participant's.** The interface starts in English on a fresh install and can be
  switched at 〔English〕|〔中文〕 on the menu; note which they use and whether they switch.
* **Time-box, do not rush.** If a step runs long, drop the later probes in that step rather than
  compressing the first ride.

### §4.1 Day 1, part A — the first ride (~20 minutes, cold install of the release on sale)

0. Before the participant arrives: run `python3 scripts/stage1_walk.py preflight` and write the release
   it reports as on sale (version and build per platform) at the top of the private notes. That, and
   only that, is the build the session is valid on.
1. **Install.** The participant installs from the App Store on their own device, their own account.
   Note platform, country of their storefront as they state it, and the local date/time — that is the
   registry entry (§2), which the owner writes the same day.
2. **Onboarding.** Fresh installs open on the intro pages with 〔Skip〕/〔跳过〕 top-right. Note: read or
   skipped; which mode names they read aloud or point at, if any.
3. **The menu.** Note the first thing they touch. The mode capsules are 〔Journey〕/〔环游〕 ·
   〔Time〕/〔限时〕 · 〔Practice〕/〔练习〕 · 〔Verbs〕/〔变形〕 · 〔Sentence〕/〔例句〕 ·
   〔Listen〕/〔听写〕; the start button reads 〔Start ride ▶〕/〔出发 ▶〕 (〔Start drill ▶〕/〔开始变形 ▶〕
   for Verbs, 〔Start dictation ▶〕/〔开始听写 ▶〕 for Listen).
   > ⚠️ On a Mac, Return or Space on the menu starts a ride. If that happens, note it — it is data about
   > the menu, not a mistake to correct.
4. **The first ride.** Do not talk during it. Note: mode, level, whether the romaji assistance picker
   (〔Hints on〕/〔总是提示〕 · 〔When stuck〕/〔卡住时〕 · 〔Off〕/〔关闭〕) was touched before or after,
   visible stumbles, whether they pause, and how it ends (finished / abandoned / typed nothing).
5. **The results screen.** Note what they read first and whether they say anything about the headline
   〔You've arrived!〕/〔到站!〕 (or, for a run that typed nothing,
   〔The ride ended before the first word〕/〔第一个词还没打,这一程就结束了〕 ·
   〔The ride ended before the first sentence〕/〔第一句还没打,这一程就结束了〕), the grade (〔Flawless〕/〔完美〕 · 〔Steady〕/〔稳健〕 · 〔Building〕/〔有进步〕 ·
   〔Take another lap〕/〔再来一程〕), and the stumbled-word list. Which button they choose:
   〔Ride again ▶〕/〔再来一程 ▶〕 · 〔Menu〕/〔回到主页〕 · 〔Share〕/〔分享〕.
   > If the rating prompt appears here, note it and do not comment.
6. **Free use, ~8 minutes.** "Use it the way you would if I were not here." Note every screen they open
   from the menu's bottom row — 〔Ride Log〕/〔骑行日志〕 · 〔Word Lists〕/〔词单〕 · 〔Stats〕/〔统计〕 ·
   〔Weak words〕/〔弱词练习〕 (only present once enough words have been reviewed) · 〔Settings〕/〔设置〕 ·
   〔About & Credits〕/〔关于与致谢〕 — and in what order.

### §4.2 Day 1, part B — the two questions, probed without leading (~10 minutes)

**Q1 — own text.** First, *unprompted*: did they find 〔Practice〕/〔练习〕 → 〔My text〕/〔我的文本〕 on
their own during free use? Record yes/no before saying anything. Then, once only:

> en: "Is there any Japanese you are working through right now — a textbook page, lyrics, something you
> read? If you had it on this phone, would you want to type it here?"
> zh:"你现在手头有没有在学的日语材料——课本的一页、歌词、读过的什么?如果它就在这台手机上,你会想在这里打它吗?"

Do not open the screen for them. If they go looking, the path is: menu → 〔Practice〕/〔练习〕 → the
segmented picker 〔Passages〕/〔文章〕 · 〔Words〕/〔词流〕 · 〔My text〕/〔我的文本〕 → the row
〔Add your own text…〕/〔添加我的文本…〕 (when they have none) → the manager 〔My text〕/〔我的文本〕 with
its empty state 〔No text of your own yet〕/〔还没有你自己的文本〕 and the button 〔Add a text〕/〔添加文本〕
→ the add sheet 〔Add a text〕/〔添加文本〕 with 〔Title (optional)〕/〔标题(可留空)〕, the section
〔Japanese text〕/〔日语原文〕, and 〔Cancel〕/〔取消〕 · 〔Add〕/〔添加〕. Record the outcome as exactly one of:

| code | meaning |
|---|---|
| `pasted` | pasted or typed their own Japanese into the add sheet and tapped 〔Add〕/〔添加〕 |
| `opened-not-pasted` | reached the add sheet and left it (〔Cancel〕/〔取消〕, or empty) |
| `looked-not-found` | went looking after the question and did not reach the sheet |
| `declined` | said no, did not look |
| `not-asked` | the probe was dropped for time |

Also record: whether the text was their own material or something they searched for on the spot; whether
they hit 〔There are no sentences in that text.〕/〔这段文字里没有可用的句子。〕; whether they opened
〔Check the readings〕/〔检查读音〕 and corrected anything; and whether they then rode it.

**Q2 — the exhausted queue.** This moment **cannot be manufactured** and the moderator must not try: the
notice 〔Nothing due at this level today — try another level, or come back tomorrow.〕/
〔这个等级的词今天都复习完了,换个等级或明天再来。〕 appears only when a start attempt finds nothing left at the
level, which in a first session is unlikely. So:

* If it appears (day 1 or day 2 — most likely after 〔Ride again ▶〕/〔再来一程 ▶〕 at a small level, or on
  the return visit), say nothing and record what they do next as one of: `changed-level` ·
  `changed-mode` · `own-text` · `ride-log-or-other-screen` · `closed-app` · `asked-me` · `other` (describe).
  This is an **observed** action.
* If it does not appear, at the end of day 2 ask once, and record the answer under a separate heading as a
  **stated** intention, never merged with the observed column:
  > en: "Suppose one day it told you there was nothing left to practise at your level today. What would
  > you do?"
  > zh:"假设有一天它告诉你,今天你这个等级已经没有可练的了。你会怎么做?"

**The notice exists only in the four SRS-queue modes** — 〔Journey〕 · 〔Time〕 · 〔Practice〕 · 〔Sentence〕.
`MenuView.swift:477` draws it only when `!isConjugation && !isDictation`. In 〔Verbs〕/〔变形〕 a refused
start simply returns (`AppModel.swift:2270`, `guard built.promptCount > 0 else { return }`); in
〔Listen〕/〔听写〕 `startGame` sets the flag (`AppModel.swift:2094`) and the menu never renders it. Those two
modes carry their own live captions instead, drawn *before* any tap when the level has nothing:
〔No verbs to drill at this level — try another level.〕/〔该等级暂无可练的动词,换个等级试试。〕 and
〔No sentences are available for dictation at this level — try another.〕/〔这个等级暂时没有可用于听写的句子,换个等级试试。〕.
So in Verbs or Listen, a tap on the start button that leaves the menu unchanged is recorded as its own Q2
code, **`silent-no-op`** — never as "notice appeared" — and what the participant does next still goes in
the observed column under the codes above.

### §4.3 Day 2 — the return (~7 minutes)

1. Before they open the app: "Did you open it since yesterday?" Record yes/no and, if yes, roughly how
   many times — self-report, marked as such. (The app's own record is visible later on 〔Ride Log〕/
   〔骑行日志〕, but reading it is their choice, not the moderator's.)
2. "Use it as you would today." Note the first thing they do, and whether it is a ride.
3. If they open 〔Ride Log〕/〔骑行日志〕 (subtitle 〔Every ride, remembered〕/〔你的打字旅程,一页一页记着〕):
   note whether they look at the 〔Streak〕/〔连续骑行〕 card (the big number with 〔day〕/〔days〕/〔天〕
   beneath 〔Last two weeks〕/〔最近两周〕) or the 〔Review forecast〕/〔复习预报〕 card (rows 〔Today〕/〔今天〕 ·
   〔Tomorrow〕/〔明天〕 · 〔This week〕/〔本周〕), and anything they say about either. A participant who rode
   on day 1 and returns the next calendar day reads a streak of **1** before riding today — `streakDays`
   counts yesterday's ride (`Sources/JournalKit/RideJournal.swift:112-131`); it becomes 2 only after a
   ride today. A **0** appears only when day 2 slipped by two or more calendar days. Note the number and
   their reaction; do not explain either.
4. If Q2's notice appears, §4.2 applies.

### §4.4 Day 2 — the forced choice (~8 minutes)

Four cards, each a package **described in the customer's terms** — what they would get, in one breath,
without the app's vocabulary. **Every price is a blank the owner fills before the first session**
(`PLAN-V2-PRODUCT` §D: price *"determines expectations, conversion and break-even"*, and it is an owner
input an agent must not invent). The cards carry no wording from the app's own offer, no route name, no
mention of what the app sells today, and no mention of the study. Prices are per territory in the
participant's own currency; the currency sign on the cards is whatever the owner writes.

> **Owner supplies prices.** Before any session, replace each `¥____` below with the price for that
> participant's territory, and record the four figures (and the date they were fixed) in the private
> notes — *not* in this file and not in `docs/sessions/`. The cards must never be shown with a blank.

Handed over as four separate cards (paper or four screenshots), in the order §4.5 gives for that
participant. Say:

> en: "Suppose the app offered exactly one of these four, and nothing else. Each has a price. You have to
> pick one — the one you would actually pay for, or the one you would least mind paying for if you had to.
> Then tell me why, and which you would never pay for."
> zh:"假设这个 app 只提供这四个里的一个,别的都没有。每个都有价格。你必须选一个——你真的会付钱的那个,或者非付不可时
> 最不介意的那个。然后告诉我为什么,以及哪一个你绝不会付。"

Record: the choice; the position it was shown in (1–4); the "never" card; the stated reason, verbatim if
they consent (§6); and whether they asked for a fifth option (what).

**Card S — supporter**

> en: *"Everything stays as it is, free for everyone. This is a single thank-you to the person who makes
> it. You get nothing extra, and it says so."* — ¥____ once
> zh:*"一切保持原样,对所有人免费。这是给做这个 app 的人的一份谢意。你不会得到任何额外的东西,卡上就是这么写的。"*
> —— ¥____ 一次

**Card B — bring your own material**

> en: *"Put in the Japanese you are actually studying — a textbook page, lyrics, an article, a word list
> from your class — and practise typing it. The app keeps track of the words from your material that you
> get wrong and brings them back until you don't, and it carries all of that across your Mac and iPhone."*
> — ¥____ once
> zh:*"把你真正在学的日语放进来——课本的一页、歌词、一篇文章、老师发的词表——然后练习打它。app 会记住你在自己材料里
> 打错的词,反复带回来直到你不再错,并且在你的 Mac 和 iPhone 之间同步这一切。"* —— ¥____ 一次

**Card C — structured course**

> en: *"A set path: you tell it which level you are aiming for and by when, and every day it gives you
> the next fixed lesson — the words and sentence patterns for that level, in order, with a progress bar
> that says where you are on the way to the target."* — ¥____ once, per level
> zh:*"一条固定的路线:你告诉它你想达到哪个等级、什么时候,之后每天它给你下一课——那个等级的词和句型,按顺序来,
> 带一个进度条告诉你离目标还有多远。"* —— ¥____ 一次,每个等级

**Card L — listening**

> en: *"Hear it, then type it. Every word and sentence has audio that a person has checked, you can slow
> it down and replay a part, and there are listening exercises — not just reading."* — ¥____ once
> zh:*"先听,再打。每个词和句子都有真人核对过的读音,可以放慢、重放某一段,还有专门的听力练习——不只是看着打。"*
> —— ¥____ 一次

Where the cards come from, so the owner can correct them (and `questionsForOwner` in the delivering
session's return flags each interpretation):

* **S** is `PLAN-V2-PRODUCT` §C's Stage 1 tip jar in customer terms — a thank-you that gates nothing.
  Its kill criterion (§G) is *near-zero over the window kills H2 as well as H1*.
* **B** is §F's F1, *"Bring your own Japanese, have the app revisit what you miss, and continue across
  devices"* — pasted material, mistakes into the same review queue, sync. The card describes the full F1,
  not the practice-only half that shipped, because the choice is between packages that would be built.
  Kill criterion: §D3's *"fewer than 2 of n pasted anything → shelved"*, read together with Q1's tally.
* **C** is the interpretation with the least text behind it. §H lists *"a JLPT candidate on a deadline"*
  among the customers and names the package only as *"structured course"*; §F has no F-item for it, and
  §F3 demotes *more content* rather than a *sequenced* course. The card therefore describes sequencing
  toward a target, not more content. The owner may reword it; the tally records which wording was used.
* **L** is §F's F2 in its honest scope: *"reviewed coverage, playback control, actual listening exercises,
  or recorded human audio"*, with the constraint that *"basic playback should be free"* — so the card
  sells checked audio, control and exercises, not playback. Kill criterion: §F2 — if what the card adds is
  not something the user does not already have, postpone.

The cards deliberately say nothing about a road, a route, a destination, scenery, a lifetime unlock, or a
one-time purchase of anything the app sells today — and they do not use the word "one-time" / "一次性"
at all, because the road screen's own offer label is 〔One-time purchase〕/〔一次性购买〕. The self-check is
case-insensitive and includes the Chinese head of that label:
`grep -n -i "Kyōto\|Tōkaidō\|Road West\|one-time\|一次性\|scenery" docs/SESSIONS-STAGE1.md` must match
only the observation checklist (§5), §8, Appendix A and this paragraph — never a line inside a card.

### §4.5 Card order — rotation table for n ≤ 15

A Williams design for four items (each package in each position once per block of four; each ordered
adjacency once), repeated by blocks. Position 1 is the card on top / shown first.

| participant | 1 | 2 | 3 | 4 |
|---|---|---|---|---|
| P1 | S | B | L | C |
| P2 | B | C | S | L |
| P3 | C | L | B | S |
| P4 | L | S | C | B |
| P5 | S | B | L | C |
| P6 | B | C | S | L |
| P7 | C | L | B | S |
| P8 | L | S | C | B |
| P9 | S | B | L | C |
| P10 | B | C | S | L |
| P11 | C | L | B | S |
| P12 | L | S | C | B |
| P13 | S | B | L | C |
| P14 | B | C | S | L |
| P15 | C | L | B | S |

Across 15 participants each package leads 3 or 4 times (S 4, B 4, C 4, L 3). The tally (§6) records the
choice against its shown position so a first-card effect can be seen rather than assumed. A participant
who drops out after day 1 keeps their number; the next recruit takes the next number, not the vacated one.

---

## §5 Observation checklist — every string grep-matched to source

Tick what was *seen*, not what was expected. A string that does not appear as written here on the
participant's build means the build is not the one Appendix A was pinned to: note the version from
〔About & Credits〕/〔关于与致谢〕 and stop trusting the checklist for that session.

**Onboarding**
- [ ] intro pages shown on the fresh install; 〔Skip〕/〔跳过〕 used at page __ / not used

**Menu**
- [ ] language: stayed 〔English〕 / switched to 〔中文〕 (when)
- [ ] 〔Mode〕/〔模式〕 capsule chosen first: 〔Journey〕/〔环游〕 · 〔Time〕/〔限时〕 · 〔Practice〕/〔练习〕 ·
  〔Verbs〕/〔变形〕 · 〔Sentence〕/〔例句〕 · 〔Listen〕/〔听写〕
- [ ] level left at 〔N5〕 (the fresh-install default: `AppSettings.swift:97` `selectedLevel: Int? = 5`,
  `AppModel.swift:237` `= .n5`) / changed to __ (N4 · N3 · N2 · N1 — write which — or 〔All〕/〔混合〕, the
  picker's **last** segment, `MenuView.swift:210`, reached only by changing it)
- [ ] assistance: 〔Hints on〕/〔总是提示〕 · 〔When stuck〕/〔卡住时〕 · 〔Off〕/〔关闭〕 — touched before ride 1? after?
- [ ] 〔Sound effects〕/〔音效〕 toggled?
- [ ] started with 〔Start ride ▶〕/〔出发 ▶〕 (or 〔Start drill ▶〕/〔开始变形 ▶〕 · 〔Start dictation ▶〕/〔开始听写 ▶〕);
  on a Mac, by Return/Space instead?
- [ ] bottom row opened, in order: 〔Ride Log〕/〔骑行日志〕 · 〔Word Lists〕/〔词单〕 · 〔Stats〕/〔统计〕 ·
  〔Weak words〕/〔弱词练习〕 · 〔Settings〕/〔设置〕 · 〔About & Credits〕/〔关于与致谢〕
- [ ] queue-exhausted notice seen: 〔Nothing due at this level today — try another level, or come back tomorrow.〕/
  〔这个等级的词今天都复习完了,换个等级或明天再来。〕 → §4.2 Q2 code __
- [ ] in 〔Verbs〕/〔变形〕 or 〔Listen〕/〔听写〕 only: start tapped, menu unchanged, no notice → Q2 `silent-no-op`;
  the mode's own caption 〔No verbs to drill at this level — try another level.〕/〔该等级暂无可练的动词,换个等级试试。〕 ·
  〔No sentences are available for dictation at this level — try another.〕/〔这个等级暂时没有可用于听写的句子,换个等级试试。〕
  was already showing? yes / no

**Results screen**
- [ ] headline 〔You've arrived!〕/〔到站!〕 — or typed-nothing: 〔The ride ended before the first word〕/
  〔第一个词还没打,这一程就结束了〕 · 〔The ride ended before the first sentence〕/〔第一句还没打,这一程就结束了〕
- [ ] grade read aloud / pointed at: 〔Flawless〕/〔完美〕 · 〔Steady〕/〔稳健〕 · 〔Building〕/〔有进步〕 · 〔Take another lap〕/〔再来一程〕
- [ ] stumbled words: 〔Review these (tap ★ to save):〕/〔复习这些词(点 ★ 收藏):〕 or
  〔These gave you trouble (tap ★ to save):〕/〔这些让你吃力(点 ★ 收藏):〕 — any ★ tapped? 〔Add to lists〕/〔加入词单〕 used?
- [ ] left by 〔Ride again ▶〕/〔再来一程 ▶〕 · 〔Menu〕/〔回到主页〕 · 〔Share〕/〔分享〕
- [ ] rating prompt appeared here (Apple's sheet; not quoted)

**Ride Log** (day 2 mostly)
- [ ] 〔Streak〕/〔连续骑行〕 card looked at; number __ 〔day〕/〔days〕/〔天〕; 〔Last two weeks〕/〔最近两周〕 strip noticed?
- [ ] 〔Review forecast〕/〔复习预报〕 rows read: 〔Today〕/〔今天〕 __ · 〔Tomorrow〕/〔明天〕 __ · 〔This week〕/〔本周〕 __
- [ ] empty state 〔No rides yet — saddle up! 🚲〕/〔还没有记录——出发吧!🚲〕 seen (means no ride was logged)
- [ ] 〔Back〕/〔返回〕 or system back

**Own text** (Q1)
- [ ] 〔Practice〕/〔练习〕 → picker 〔Passages〕/〔文章〕 · 〔Words〕/〔词流〕 · 〔My text〕/〔我的文本〕 reached unprompted? after the question?
- [ ] 〔Add your own text…〕/〔添加我的文本…〕 (none yet) or 〔Choose a text〕/〔选择文本〕 ▸ 〔Manage…〕/〔管理…〕 (some exist)
- [ ] manager: 〔No text of your own yet〕/〔还没有你自己的文本〕 · 〔Add a text〕/〔添加文本〕 · 〔Add〕/〔添加〕 · 〔Done〕/〔完成〕
- [ ] add sheet: 〔Title (optional)〕/〔标题(可留空)〕 · 〔Japanese text〕/〔日语原文〕 · 〔Cancel〕/〔取消〕 · 〔Add〕/〔添加〕
- [ ] 〔There are no sentences in that text.〕/〔这段文字里没有可用的句子。〕 seen
- [ ] 〔Check the readings〕/〔检查读音〕 opened; readings corrected: __
- [ ] 〔Contains letters or digits — cannot be typed〕/〔含字母或数字,无法输入〕 seen on a sentence
- [ ] rode the pasted text: yes / no

**Settings — observe only** (the iCloud switch was named in §3; it is never suggested during the session)
- [ ] card 〔iCloud Sync〕/〔iCloud 同步〕 scrolled to; switch 〔Sync review progress & ride log〕/〔同步复习进度与骑行日志〕
  turned off by the participant? (their choice, noted; never proposed by the moderator)

**Road entrances — observe only; never point at them**
- [ ] Settings card 〔The Road〕/〔路〕 scrolled to; its row read 〔The road past Kyōto〕/〔京都之后的路〕
  (or 〔The Tōkaidō and the Road West〕/〔东海道与西の道〕 if somehow owned); tapped?
- [ ] menu route strip became a button 〔Tōkaidō complete · Kyōto reached〕/〔东海道 走完 · 京都到达〕 (only after
  Kyōto is reached — not expected in two sessions); tapped?
- [ ] anything the participant said at either entrance, verbatim with consent

---

## §6 The PII rule, and where each thing is written

**Per-participant notes never enter this public repository.** Not as a file, not as a commit message, not
as a quote with a name, not as a device name, not as an Apple ID, not as an order number. The moderator's
notes live wherever the owner keeps private material (`~/Library/Application Support/CLI-Pulse-Secrets/`
is the house location for things that must not be in a repo; any private place outside the repository is
acceptable). Participants are `P1`…`P15` in those notes and nowhere else.

What **does** enter the repository, and only this:

| thing | where | form |
|---|---|---|
| the participant's install | `docs/measurements/stage1-known-positives.json` (owner writes) | `first_download`, platform, country, Pacific day, `notes: "session participant"` — nothing else in `notes` |
| the tally | `docs/sessions/README.md` (template there), appended per completed batch | aggregates only: counts by territory and platform, Q1 codes, Q2 codes (observed and stated apart), package choice × shown position, "never" counts |
| quotes | the tally's quote section | only sentences the participant heard read back and agreed to at the time ("quote OK: yes" in the private notes beside it); no name, no P-number, no territory beside the quote |
| the prices used | private notes only | the four figures and the date fixed; not in this file, not in the tally |

**Consent is per quote, at the time.** Asking later by message is not the same, because the participant
cannot see the context it will be published in.

**Aggregates below n = 3 in any cell are written as "< 3", not as the number.** A cell of 1 in "CN · macOS ·
pasted" with a public install registry is a person. n itself — the participants table's `total` row — is
written exactly: it is the denominator, not a cell that joins a person to an attribute.

**The one cell the mask must not blind.** `PLAN-V1.34` §D3's falsifier reads the all-participants Q1
`pasted` count and splits at 2 (*"fewer than 2 of n pasted anything → shelved"*); "< 3" would collapse 0,
1 and 2 into one symbol and leave the public record unable to say which branch fired. So that one cell is
written as the falsifier's own two categories and nothing finer: **"fewer than 2 of n"** or **"2 or more
of n"**, with n stated. That answers §D3's rule without publishing a 0, a 1 or a 2. It is the only cell so
written: every other Q1 and Q2 cell, every territory × platform cell, every sub-count of `pasted`, and
Q2's observed column keep "< 3" — an observed column that ends the study at 0 (§8) is *printed* as
"< 3", and the tally's prose says the moment never occurred.

**If a participant asks for their notes to be deleted**, the private notes are deleted; the registry entry
stays (it is a count of an install, carries no identity, and removing it would change N after a reading)
and the tally is not recomputed unless the batch has not yet been appended.

---

## §7 The owner's time, stated as the plan states it

`PLAN-V1.34` §D2: **12–18 hours over 2–3 weeks** — recruiting, scheduling, two meetings per participant,
notes, the same-day registry entry for each install, and the tally. That is the honest size for 10–15
participants; the plan writes it beside the observation that the owner *"has not yet found 70 minutes for
the walk in 15 days"*.

**The kit costs nothing if it waits.** No checkpoint reads it, no release is gated on it, no §K rule
depends on a session having happened — the 2026-09-24 box is written so that sessions *may* run, not so
that they must. The only thing that expires is relevance: the forced choice informs Stage 2's decision
(`PLAN-V1.34` §D3's decision pack, v1.36), and the day-90 read is 2026-12-08. Sessions after that date
still answer Q1 and Q2; they no longer inform that read.

The walk (`PLAN-STAGE1` §K/§L) outranks the sessions if both compete for the same hour: it is the only
action that removes the `BOUND WITHHELD` reason, and the sessions cannot use a walk device until §L is
recorded.

---

## §8 What would make this kit wrong

* **If participants are recruited by asking friends and family.** The supporter card (S) then measures
  goodwill toward the owner, not the product; the tally must say how each participant was reached in
  category terms (personal / community / other, with counts), or S's count is uninterpretable.
* **If every participant is one territory or one platform.** `PLAN-V2-PRODUCT` §H asks for spread *"across
  proficiency, territory and platform"*; a single-territory tally cannot be read against a store whose
  impressions are 75% CN and whose installs are 48% CN (§D). Record proficiency as the participant states
  it (never tested).
* **If the return visit does not happen for most.** A day-2 dropout is itself an observation ("did not come
  back") and is tallied as one — but the forced choice from a participant who never returned is a choice
  between descriptions, and is tallied in a separate column if it is taken at all.
* **If the moderator steers**, especially toward the road entrances or toward pasting. Q1's `pasted` code
  is only meaningful when the path was found unprompted or after the one scripted question.
* **If the prices are filled in after some sessions have run**, or differ between participants in the
  same territory without being recorded. The forced choice is then two instruments with one name.
* **If the exhausted-queue moment never occurs.** Then Q2 has only stated intentions, and the tally must
  say so rather than merging the columns; the observed column may legitimately end the study at 0 (printed
  as "< 3" per §6, with the prose saying the moment never occurred).
* **If a card leaks the app's own offer** — a route name, a destination, "one-time purchase", a price the
  app charges today. The participant then compares the card to the thing on the road screen, and the
  choice is contaminated by the frozen offer this window must not touch.
* **If a participant install goes unregistered before the next `--checkpoint`** whose window contains it.
  The reading then counts a recruited install as an arrival; the box's item 6 and `stage1-checkpoints.md`
  rule 4 exist for this, and the same-day entry is the only remedy.
* **If a release ships between sessions.** The strings in §5 are pinned to `04947be`'s `Sources/`; a new
  release may change them (v1.34 changes the results screen — `PLAN-V1.34` §B1). Re-run Appendix A's greps
  against the shipped tree, note the build per participant, and do not compare a "tomorrow line" reaction
  across builds that do and do not have one.
* **If a participant buys the existing purchase during the study.** It is registered as `kind = purchase`
  the same day, GO never fires on it, and the session notes record that it happened unprompted; it is not
  a package choice and is not tallied as one.
* **If N = 100 fires while sessions run.** The record is written per `stage1-checkpoints.md` regardless;
  the sessions do not pause and do not accelerate, and the record names every participant install inside
  the window (rule 4).
* **If the owner's honest time is not there.** §7 is the answer: nothing breaks. Do not run three sessions
  and call it the instrument.

---

## Appendix A — string → source, as grepped 2026-09-25 at `04947be`

Each 〔〕 string in this file was grep-matched against `Sources/` (comment lines excluded) and appears at the
file:line below. Interpolated strings (the streak number, the results stage line, the stumbled-word
counts) are not quoted in 〔〕 and are not listed. A re-pin after any `Sources/` change re-runs these greps
and appends a dated block; it does not edit this one.

| string (en) | string (zh) | file:line |
|---|---|---|
| Skip | 跳过 | `Sources/NihongoRideApp/OnboardingView.swift:120` |
| English · 中文 (segmented picker) | — | `Sources/NihongoRideApp/MenuView.swift:194-195` |
| Mode | 模式 | `Sources/NihongoRideApp/MenuView.swift:164` |
| Journey | 环游 | `Sources/GameCore/GameSession.swift:33` |
| Time | 限时 | `Sources/GameCore/GameSession.swift:34` |
| Practice | 练习 | `Sources/GameCore/GameSession.swift:35` |
| Verbs | 变形 | `Sources/GameCore/GameSession.swift:36` |
| Sentence | 例句 | `Sources/GameCore/GameSession.swift:37` |
| Listen | 听写 | `Sources/GameCore/GameSession.swift:38` |
| All | 混合 | `Sources/NihongoRideApp/MenuView.swift:210` |
| Hints on | 总是提示 | `Sources/NihongoRideApp/MenuView.swift:390` |
| When stuck | 卡住时 | `Sources/NihongoRideApp/MenuView.swift:391` |
| Off | 关闭 | `Sources/NihongoRideApp/MenuView.swift:392` |
| Sound effects | 音效 | `Sources/NihongoRideApp/MenuView.swift:399` |
| Start drill ▶ | 开始变形 ▶ | `Sources/NihongoRideApp/MenuView.swift:416` |
| Start dictation ▶ | 开始听写 ▶ | `Sources/NihongoRideApp/MenuView.swift:417` |
| Start ride ▶ | 出发 ▶ | `Sources/NihongoRideApp/MenuView.swift:418` |
| Nothing due at this level today — try another level, or come back tomorrow. | 这个等级的词今天都复习完了,换个等级或明天再来。 | `Sources/NihongoRideApp/MenuView.swift:478-479` |
| Ride Log | 骑行日志 | `Sources/NihongoRideApp/MenuView.swift:489` |
| Word Lists | 词单 | `Sources/NihongoRideApp/MenuView.swift:510` |
| Stats | 统计 | `Sources/NihongoRideApp/MenuView.swift:527` |
| Weak words | 弱词练习 | `Sources/NihongoRideApp/MenuView.swift:547` |
| Settings | 设置 | `Sources/NihongoRideApp/MenuView.swift:568` |
| About & Credits | 关于与致谢 | `Sources/NihongoRideApp/MenuView.swift:581` |
| Passages | 文章 | `Sources/NihongoRideApp/MenuView.swift:355` |
| Words | 词流 | `Sources/NihongoRideApp/MenuView.swift:357` |
| My text | 我的文本 | `Sources/NihongoRideApp/MenuView.swift:359` (also `CustomTextsView.swift:25`) |
| Add your own text… | 添加我的文本… | `Sources/NihongoRideApp/MenuView.swift:66` |
| Manage… | 管理… | `Sources/NihongoRideApp/MenuView.swift:74` |
| Choose a text | 选择文本 | `Sources/NihongoRideApp/MenuView.swift:76` |
| Tōkaidō complete · Kyōto reached | 东海道 走完 · 京都到达 | `Sources/NihongoRideApp/MenuView.swift:672` |
| You've arrived! | 到站! | `Sources/NihongoRideApp/ResultsView.swift:109` |
| The ride ended before the first word | 第一个词还没打,这一程就结束了 | `Sources/GameCore/GameSession.swift:102` |
| The ride ended before the first sentence | 第一句还没打,这一程就结束了 | `Sources/GameCore/GameSession.swift:103` |
| Ride again ▶ | 再来一程 ▶ | `Sources/NihongoRideApp/ResultsView.swift:139` |
| Menu | 回到主页 | `Sources/NihongoRideApp/ResultsView.swift:149` |
| Share | 分享 | `Sources/NihongoRideApp/ResultsView.swift:165` |
| Add to lists | 加入词单 | `Sources/NihongoRideApp/ResultsView.swift:332` |
| Flawless | 完美 | `Sources/NihongoRideApp/ResultsView.swift:504` |
| Steady | 稳健 | `Sources/NihongoRideApp/ResultsView.swift:505` |
| Building | 有进步 | `Sources/NihongoRideApp/ResultsView.swift:506` |
| Take another lap | 再来一程 | `Sources/NihongoRideApp/ResultsView.swift:507` |
| Review these (tap ★ to save): | 复习这些词(点 ★ 收藏): | `Sources/NihongoRideApp/ResultsView.swift:544` |
| These gave you trouble (tap ★ to save): | 这些让你吃力(点 ★ 收藏): | `Sources/NihongoRideApp/ResultsView.swift:545` |
| Every ride, remembered | 你的打字旅程,一页一页记着 | `Sources/NihongoRideApp/JournalView.swift:69` |
| Back | 返回 | `Sources/NihongoRideApp/JournalView.swift:70` (also `SettingsView.swift:272`, `RoadView.swift:329`) |
| Streak | 连续骑行 | `Sources/NihongoRideApp/JournalView.swift:81` |
| day / days | 天 | `Sources/NihongoRideApp/JournalView.swift:87` |
| Last two weeks | 最近两周 | `Sources/NihongoRideApp/JournalView.swift:92` |
| Review forecast | 复习预报 | `Sources/NihongoRideApp/JournalView.swift:199` |
| Today | 今天 | `Sources/NihongoRideApp/JournalView.swift:200` |
| Tomorrow | 明天 | `Sources/NihongoRideApp/JournalView.swift:201` |
| This week | 本周 | `Sources/NihongoRideApp/JournalView.swift:202` |
| No rides yet — saddle up! 🚲 | 还没有记录——出发吧!🚲 | `Sources/NihongoRideApp/JournalView.swift:319` |
| Done | 完成 | `Sources/NihongoRideApp/CustomTextsView.swift:28` |
| Add | 添加 | `Sources/NihongoRideApp/CustomTextsView.swift:32` (also `:141`) |
| No text of your own yet | 还没有你自己的文本 | `Sources/NihongoRideApp/CustomTextsView.swift:51` |
| Add a text | 添加文本 | `Sources/NihongoRideApp/CustomTextsView.swift:58` (also `:135`, the sheet title) |
| Title (optional) | 标题(可留空) | `Sources/NihongoRideApp/CustomTextsView.swift:115` |
| Japanese text | 日语原文 | `Sources/NihongoRideApp/CustomTextsView.swift:124` |
| There are no sentences in that text. | 这段文字里没有可用的句子。 | `Sources/NihongoRideApp/CustomTextsView.swift:131` |
| Cancel | 取消 | `Sources/NihongoRideApp/CustomTextsView.swift:138` |
| Check the readings | 检查读音 | `Sources/NihongoRideApp/CustomTextsView.swift:186` |
| Contains letters or digits — cannot be typed | 含字母或数字,无法输入 | `Sources/NihongoRideApp/CustomTextsView.swift:206` |
| The Road | 路 | `Sources/NihongoRideApp/SettingsView.swift:187` (also `RoadView.swift:324`) |
| The Tōkaidō and the Road West | 东海道与西の道 | `Sources/NihongoRideApp/SettingsView.swift:192` |
| The road past Kyōto | 京都之后的路 | `Sources/NihongoRideApp/SettingsView.swift:193` |
| iCloud Sync | iCloud 同步 | `Sources/NihongoRideApp/SettingsView.swift:94` |
| Sync review progress & ride log | 同步复习进度与骑行日志 | `Sources/NihongoRideApp/SettingsView.swift:97` |
| Stored in your own private iCloud — visible only to you. | 数据存于你自己的 iCloud(私有库),仅你可见。 | `Sources/NihongoRideApp/SettingsView.swift:105-106` |
| One-time purchase | 一次性购买 | `Sources/NihongoRideApp/RoadView.swift:176` (the offer label the cards must not echo) |
| No verbs to drill at this level — try another level. | 该等级暂无可练的动词,换个等级试试。 | `Sources/NihongoRideApp/MenuView.swift:455-456` |
| No sentences are available for dictation at this level — try another. | 这个等级暂时没有可用于听写的句子,换个等级试试。 | `Sources/NihongoRideApp/MenuView.swift:465-466` |
| N5 | — | `Sources/VocabKit/VocabEntry.swift:9` (`label` is `"N\(rawValue)"`, rawValue 5; the picker's first segment, `MenuView.swift:207-209`; the literal `"N5"` also appears at `AppModel.swift:1538`) |

The greps that produced this table (run from the repository root, each string once; a zero-line result for
any of them means the pin is stale):

```bash
grep -rn --include='*.swift' -F '"Skip"' Sources | grep -v '^\S*:\s*//'
# …and likewise for every en string above, then every zh string, e.g.
grep -rn --include='*.swift' -F '"这个等级的词今天都复习完了,换个等级或明天再来。"' Sources
```

The last eight rows were added the same day (2026-09-25), against the same `Sources/` tree, for the strings
the review corrections of this file introduced; 〔N5〕 is the one interpolated label quoted, because the
checklist has to name the default the way the picker prints it.

## Appendix B — the consent text's claims, each against the shipped code at `04947be`

§3 is read aloud to a recruited person, so each sentence in it that describes the app is tied to a line. The
branch's `Sources/` is byte-identical to `04947be`'s (`git diff --stat 04947be HEAD -- Sources` is empty),
which is the tree v1.33 shipped from.

| claim in §3 | where it is true |
|---|---|
| progress stays on the device | `Sources/NihongoRideApp/CloudKitSyncController.swift:10-11` — "The local JSON files remain the system-of-record" |
| iCloud sync is on by default | `Sources/NihongoRideApp/AppModel.swift:356` `var iCloudSyncEnabled: Bool = true`; `:816` `static let cloudSyncAvailable = true`; `:713` `startSyncIfEnabled()` at launch; `:897-903` the three guards, all passed by a shipped build (`:995` `syncAllowed: !layoutHarness`) |
| it copies the review schedule, ride log, distance and word lists | `CloudKitSyncController.swift:9-10` ("SRS cards, ride history, and the lifetime odometer"); `:123-127` the SRS, ride, odometer and list records enqueued; `:97-100` a first run enqueues everything local and syncs at once |
| into the participant's **own private** iCloud database | `CloudKitSyncController.swift:9-10` "private-database `CKSyncEngine`"; `:74` `.privateCloudDatabase`; the caption at `SettingsView.swift:105-106` says so on screen; container `iCloud.com.jasonye.nihongoride` in `xcode/NihongoRide-iOS.entitlements:7-13` and `xcode/NihongoRide.entitlements:7-13` |
| only when signed in to iCloud | `AppModel.swift:904-916` — `init?` never asks about iCloud; a missing account surfaces later as `.noAccount` (`SettingsView.swift:311` 〔Not signed in to iCloud〕 is that status, not quoted in §3 because the participant is not sent to look for it) |
| the switch under 〔Settings〕 → 〔iCloud Sync〕 turns it off | `SettingsView.swift:93-106` — the card, the `Toggle(isOn: $model.iCloudSyncEnabled)` and the caption; `AppModel.swift:356` `didSet { … syncEnabledChanged() }` |
| Game Center gets Time-mode scores and achievements when signed in | `AppModel.swift:714` `gameCenter.authenticate()` at launch; `GameCenterManager.swift:43-54` sets the `authenticateHandler`; `:69-86` `recordRun` submits a Time Attack score (`:73-75`) and reports achievements (`:77-86`), guarded by `isAuthenticated` (`:71`); `AppModel.swift:2469-2470` calls it from `finishGame` for real runs; entitlement `com.apple.developer.game-center` at `xcode/NihongoRide-iOS.entitlements:5` and `xcode/NihongoRide.entitlements:5` |
| the developer and the study receive nothing | there is no developer endpoint anywhere in `Sources/`: `grep -rn URLSession Sources --include='*.swift'` returns nothing, and the only URLs in the tree are the credits links at `AboutView.swift:29-59`, opened in the browser; the same statement is the corrected public privacy page, `site/privacy.html:23-30` |

What the earlier wording got wrong, for the record: the 2026-09-25 first draft of §3 said the app "collects
nothing and sends nothing" / "不收集、不上传任何数据". The second half was false for the shipped build on any
device signed in to iCloud or Game Center — the same negative universal `STATE-2026-09-11.md` ("Blocker, not code") had
already retracted from the live privacy page. It was corrected the same day, before any participant was recruited.
