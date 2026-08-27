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

## Name
`Nihongo Ride` — unchanged. It is the brand and it already reads as Japanese.

## Subtitle (30 char limit)
```
日本語学習者のためのタイピング
```
15 characters. `学習者` is the standard term for a learner of Japanese as a foreign language, so
it filters intent in the one field Apple weights most after the title.

## Keywords (100 char limit)
```
日本語学習,語彙,JLPT,日本語能力試験,ひらがな,カタカナ,ローマ字,漢字,読み方,例文,単語,暗記,N5,N1,外国人向け
```
Deliberately **excludes** タイピング, タイピング練習, タイピングゲーム — see above.

## Description
```
Nihongo Ride は、日本語を「打ちながら覚える」ための静かな学習アプリです。

多くのタイピングアプリは速さを測ります。Nihongo Ride が教えるのは日本語そのもの
——かな、語彙、そして実際の文です。東京から京都へ、日本各地を自転車で巡りながら、
正しい読みを入力すると前に進みます。間違えた語は、必要なタイミングでもう一度出てきます。

■ 何が違うのか
・ミニ IME 内蔵。ふつうのキーボードでローマ字を打つだけ。システムの日本語入力も設定も不要です。
　shi / si、tsu / tu、n / nn など、正しい綴りはすべて受け付け、打鍵をリアルタイムでかなに変換します。
・速さではなく、身につけるために。すべての語にかな、任意のローマ字ヒント、
　そして英語と中国語の語義が表示されます。
・間隔反復（SM-2）。打ち間違えた語は復習キューに入り、練習が自分の弱点に向きます。

■ 3 つの走り方
・ジャーニー — 日本を巡る旅。打ち続けて先へ進み、名所を解放します。
・タイムアタック — 60 秒、打てるだけ。
・プラクティス — 静かな練習モード。単語ドリルにも長文にも。ローマ字ヒントを
　すべて隠す BLIND チャレンジもあります。

■ 収録内容
・JLPT N5〜N1 の 7,000 語以上。英語と中国語の語義つき。
・例文と 233 の読解パッセージ。日常のあいさつから短い文学的な段落まで。
・カタカナ外来語にも対応（ファ・ティなど、外来語特有の表記を含む）。

■ 設計として、プライベート
・完全オフライン。アカウント不要、通信なし、トラッキングなし、広告なし。
・学習の記録は、あなたの端末の中だけに残ります。

■ 表示言語について
アプリの操作画面は英語または中国語です（学習対象の日本語は、かな・漢字・例文として
アプリ全体に表示されます）。日本語の学習者向けに設計されているため、
語義の表示は英語と中国語のみです。

N5 を始めたばかりでも、N1 を磨いている途中でも、Nihongo Ride は毎日のタイピングを
日本語の上達に変えます。さあ、走り出しましょう。
```

## ⚠️ Numbers in this copy are computed, and one of them was inherited wrong

`183 の読解パッセージ` was copied from the live `en-US` listing while drafting. **The corpus has
233.** Both live listings — `en-US` and `zh-Hans` — have been quoting 183 since the passage set
grew, which is v1.25's "fifty more sentences against a measured 42" moved from What's New into
the description, where nobody re-reads it. `scripts/release_numbers.py` now computes `passages`,
and **v1.28 must correct `en-US` and `zh-Hans` as well as ship `ja` right.**

| claim | value | source |
|---|---|---|
| `7,000 語以上` | 7,071 entries | `release_numbers.py: entries` |
| `233 の読解パッセージ` | 233 | `release_numbers.py: passages` |
| `JLPT N5〜N1` | five levels present | corpus files |

## What's New (v1.28)
Written against whatever v1.28's actual code change is — **not** against the listing, because a
store-metadata change is not something to announce inside the app.

## Support / marketing URLs
Same as `en-US` — the support page is English, which the 表示言語 note above already discloses.
