# `ja` App Store listing — draft for review

Positioning decision, and it is the whole difference between this working and diluting the app's
Japanese ranking: **this listing targets 日本語学習者 — people learning Japanese who read
Japanese — and NOT native speed-typing practice.** タイピング in Japanese overwhelmingly means
the native speed-practice category (寿司打 and its neighbours). Ranking for it would buy large
impressions from people the app cannot serve, collapse click-through, and cost the English
long-tail ranking that currently converts at 1.25%.

**So タイピング appears in the SUBTITLE, which Apple indexes, and NOT in the keyword field.** The
mechanic is covered; the keyword budget is not spent buying that category's traffic.

**Honesty note, and it is load-bearing.** The app's interface is English or Chinese — there is no
Japanese UI. A Japanese-device user who installs expecting a Japanese interface and finds English
is a one-star review, and v1.27 now asks people for reviews. (The prompt's own gate protects
against the worst case: it needs three completed rides across two calendar days, which somebody
who bounces on first launch will never reach. But the listing should still say so.)

---

## FINAL, after a native-level review by Gemini 3.7 Flash

Its language findings were largely right and are taken: the first draft carried clear
translationese — `練習が自分の弱点に向きます` is not grammatical Japanese, `解放` is the classic
machine-translation error for "unlock" (`アンロック`), `設計として、プライベート` is a literal
rendering of "Private by design", `N1 を磨く` is the wrong collocation, `任意の` is developer
jargon for "optional", and `打鍵` is typing-niche vocabulary. Em-dashes became `：` and `（）`,
and `233 の` gained its counter (`233 本の`).

**Two recommendations were refused, and both would have undone the positioning.**

| it proposed | verdict |
|---|---|
| subtitle `タイピングで学ぶ日本語・JLPT対策` | **refused** — it drops `学習者`, which is the whole intent filter, and Gemini's own answer confirms `日本語学習者` reads *exclusively* as a foreign-language learner (natives study `国語`). Its Option C shape taken instead. |
| add `Japanese,vocab,kanji` to the `ja` keywords | **refused** — the Japan storefront indexes the `en-US` localization too, so English terms are already served from that keyword field. The gap it identified is real and belongs in `en-US`, which this release deliberately does not touch. |
| add `N2,N3,N4`; drop `外国人向け`; `語彙`→`単語` | **taken** — the exact-match gap is real, and `外国人向け` is a native B2B term no learner searches. |
| `ミニ IME` may read as a keyboard extension (2.5.8) | **taken** — now `アプリ内蔵のローマ字入力エンジン`, with an explicit parenthetical that it is not a system keyboard. |
| conditional BLOCKER: telemetry vs the offline claim | **cleared by measurement** — zero remote package dependencies, no analytics SDK, and no `URLSession`/`URLRequest` anywhere in `Sources/`. |

**And one thing neither of us raised, found while checking that claim: `iCloudSyncEnabled`
defaults to `true`.** The app reaches the network by default, via CloudKit, while the live
`en-US` and `zh-Hans` listings both say *"No network" / "不联网"*. Not a rejection risk — it is
the user's own private database and Apple has passed it nine times — but it is imprecise, and
§I of the product plan assumed this only *became* untrue once an IAP shipped. **It is untrue
now.** The copy below states it accurately; v1.28 must correct the other two.

## Name
`Nihongo Ride` — unchanged.

## Subtitle (19 / 30)
```
日本語学習者のためのローマ字タイピング
```

## Keywords (71 / 100, 18 terms)
```
日本語学習,JLPT,日本語能力試験,N5,N4,N3,N2,N1,単語,ひらがな,カタカナ,漢字,読み方,例文,読解,暗記,語彙力,かな入力
```
`タイピング` stays out: it is in the subtitle, which Apple indexes into the same token pool, so
putting it here would spend budget on a term already covered while buying the native
speed-typing category this app cannot serve. `ローマ字` moved to the subtitle for the same reason.

## Description (1177 / 4000)
```
Nihongo Ride は、タイピングを通じて日本語を身につける、集中できる学習アプリです。

一般的なタイピングアプリの多くは入力スピードを競います。Nihongo Ride が目指すのは、かな・語彙・実践的な例文といった日本語そのものの習得です。東京から京都へ、日本各地を自転車で巡りながら、正しい読みを入力して前へ進みます。間違えた単語は、記憶の定着に最適なタイミングで自動的に再出題されます。

■ 主な特長
・アプリ内蔵のローマ字入力エンジン
普段お使いのキーボードでローマ字を入力するだけ。OS の日本語入力設定やキーボードの切り替えは一切不要です（システムに追加されるキーボードではありません）。shi / si、tsu / tu、n / nn などの表記の揺れにも対応し、入力したローマ字がリアルタイムでかなに変換されます。

・速さよりも定着を重視
すべての単語に「かな表記」「オン/オフを切り替えられるローマ字ヒント」「英語・中国語の対訳」がついています。

・間隔反復（SM-2 アルゴリズム）
間違えた単語は自動で復習キューに入り、苦手な単語を集中的に練習できます。

■ 3 つの走行モード
・ジャーニー：日本各地を巡る旅。タイピングで前進し、名所をアンロックしていきます。
・タイムアタック：60 秒間でどれだけ入力できるかに挑むスピードチャレンジ。
・プラクティス：自分のペースで学べる練習モード。単語ドリルから長文まで対応し、ローマ字ヒントをすべて隠す「BLIND チャレンジ」も搭載しています。

■ 収録内容
・JLPT N5〜N1 に対応した 7,000 語以上（英語・中国語の対訳付き）。
・例文と 233 本の読解パッセージ（日常のあいさつから文学作品の短文まで）。
・カタカナ外来語にも対応（ファ、ティなど外来語特有の表記を含む）。

■ プライバシーについて
・学習はすべて端末内で完結します。アカウント登録は不要で、トラッキングも広告もありません。
・iCloud 同期（設定でオン/オフを切り替えられます）は Apple の iCloud 上にあるあなた個人の領域を使います。開発者がその中身を見ることはできません。オフにすれば、学習の記録は端末内だけに残ります。

■ 対応言語・UI について（ご注意）
本アプリは日本語学習者向けに設計されているため、メニューや設定などの操作画面、および単語の意味の表示は「英語」または「中国語」のみの対応となります。
※学習の対象となるかな・漢字・例文・読解パッセージは、すべて日本語で表示されます。

N5 を始めたばかりの方から N1 を目指す方まで、Nihongo Ride は毎日のタイピング練習を確かな日本語力に変えていきます。さあ、走り出しましょう。
```

## Facts in this copy, all computed

| claim | value | source |
|---|---|---|
| `7,000 語以上` | 7,071 | `release_numbers.py: entries` |
| `233 本の読解パッセージ` | 233 | `release_numbers.py: passages` — **the live listings say 183** |
| `60 秒` | Time Attack duration | app |

## What v1.28 must also fix in the OTHER locales

* `en-US` and `zh-Hans` both say **183** reading passages. The corpus has **233**.
* Both claim **no network** while iCloud sync is on by default.
* Keywords in those locales are **deliberately not touched**, so the per-territory reading of
  this release stays attributable.
