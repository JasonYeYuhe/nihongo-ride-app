# The product plan — from "free and finished" to "worth paying for"

Every release since 1.17 has been a correctness release. The corpus is 7,071 entries and 6,738
example sentences, the reading gates are four deep, the test suite is 545, and the app has never
been rejected. **None of that is the constraint any more.**

This is a different kind of work and should be read differently: the previous eleven releases
could be *verified*, and most of what follows can only be *decided*. Where a claim is measured,
it says so. Where it is a judgement, it says that too.

> **This document has been through three adversarial reviews (Gemini 3.1 Pro, Gemini 3.7 Flash,
> Codex) and the first draft did not survive them.** Its central recommendation was replaced,
> its "red line" was shown to be timid rather than principled, and its reading of its own only
> data point was shown to be an over-interpretation. What each review changed is recorded in §J,
> in the house style, because the pattern is more useful than the verdicts.

---

## §A The evidence, and it cuts both ways

**The app has received exactly one App Store review in its life.** Five stars, from China, dated
2026-07-10, in full:

> **非常完美怎么收费的找不到路口**
> 怎么收费找不到付费路口希望有一次性
>
> *"Absolutely perfect — how do I pay? I can't find the payment entrance. I hope there's a
> one-time option."*

The first draft read this as evidence **for** monetizing. It is that. It is also, read honestly,
evidence of something less comfortable:

**One review in a lifetime is a measurement of near-zero traffic.** Both Gemini reviews said so
independently, and the arithmetic is unforgiving: a 2% conversion on 40 monthly downloads is
under one sale a month. **A paywall built in an empty room earns nothing no matter how well it
is engineered**, and the first draft spent its length on StoreKit failure modes while never
mentioning distribution.

So the same three characters support two conclusions, and the plan needs both.

### What is measured

| | |
|---|---|
| price | **Free**, both platforms, since launch |
| monetization code | **none** — no StoreKit, no IAP, no receipt handling anywhere in `Sources/` |
| App Privacy declaration | **Data Not Collected** |
| written reviews, all time | **1** |
| corpus | 7,071 entries · 6,738 with a sentence · 5,760 in the dictation pool |
| modes / surfaces | 6 modes; 11 screens plus a widget |
| `AppTransaction.originalAppVersion` availability | **macOS 13 / iOS 16** — verified in the MacOSX26.5 SDK's `StoreKit.swiftinterface`, below this app's 14.0 / 17.0 targets |

### ⚠️ What cannot be measured today

The app collects no usage data. There is no answer to: how many people finish a ride, which
modes are touched, where people stop coming back.

The first draft called this an acceptable cost of the privacy promise and proposed measuring
conversion through App Store Connect alone. **Both reviews rejected that, and they are right.**
ASC can tell you conversion is 0.4%; it cannot tell you whether that is because people saw the
price and declined or because they never found the button — which are opposite problems with
opposite fixes.

The error was treating "Data Not Collected" as equivalent to "zero telemetry". They are not the
same thing. **Local, on-device, non-identifying counters that never leave the device are not
tracking** and do not change the privacy declaration. See §G.

---

## §B The literal reading of the only data point

Gemini 3.1 Pro made the observation that reorganised this entire plan, and it is worth quoting
the reasoning rather than the conclusion:

> The user did not ask for a Pro version or more features. They explicitly called the *current,
> free version* "perfect" and simply asked for a way to give you money.

That is what the review says. The first draft read "how do I pay" and designed a Pro tier, a
paywall, a content pipeline and a tier boundary — **a product pivot inferred from a request to
give money.** The simplest reading is that someone wanted to tip a developer whose free app they
liked, and the simplest reading is the one with by far the least engineering behind it.

**This does not settle whether a Pro tier is right.** It settles what to build *first*, because
one of these two costs a fraction of the other and answers a question that gates it.

---

## §C The staged plan

Each stage is cheap relative to the one after it, and each answers a question that decides
whether the next is worth starting. **Do not skip ahead**, and specifically do not build Stage 3
before Stage 1 has produced a number.

### Stage 0 — Distribution, which is the actual constraint

Everything else multiplies by traffic, and traffic is currently near zero. This stage has no
paywall in it at all.

* **ASO.** The keyword list has been unchanged since launch and is English-only. The one review
  came from **China**, the app is already fully localised to Chinese, and its zh keywords are not
  tuned. Japan, Korea and Taiwan are untouched.
* **Ask for reviews.** `SKStoreReviewController`, triggered at a genuine positive moment — a
  completed journey, a streak milestone — not on launch. One review is not a reputation; it is a
  rounding error, and it is the single biggest lever on downloads.
* **Baseline before anything ships.** Record 30 days of downloads, product-page views and
  impressions **now**, so the first post-change number means something. Without a baseline the
  first month's figure is uninterpretable — this project's own rule about instruments applies
  unchanged.

### Stage 1 — The tip jar

**One non-consumable "Support the developer", in Settings and on the results screen. Nothing is
gated. Nothing changes for anyone who ignores it.**

It fulfils the only request the app has ever received, it takes a fraction of a Pro tier to
build, and it answers the question everything else depends on: **will anyone pay this developer
anything at all?**

* Tiered amounts are conventional and cheap (small / medium / large). A repeatable consumable
  is also legitimate; a non-consumable with a visible thank-you is simpler and matches 一次性.
* **This is a real measurement, not a gesture.** A tip jar that earns nothing over 60 days across
  a meaningful download base is strong evidence that a $10 Pro tier earns less, and it costs one
  release to find out instead of four.

### Stage 2 — Decide, with a number in hand

Read Stage 1's conversion against the kill criteria in §G. Three outcomes and all three are
useful:

* **Nobody tips** → the constraint is distribution or desire, not checkout. Do not build Pro.
  Return to Stage 0.
* **People tip a little** → willingness exists but is thin. A Pro tier is defensible; price
  conservatively.
* **People tip well** → build Pro, and price it against what people actually gave.

### Stage 3 — Pro, only if Stage 2 says so

Structure in §E and §F. Not before.

---

## §D The model, and the constraint the first draft missed

**Recommendation: one-time, staged as above — but for a reason the first draft did not give, and
with a limit it did not acknowledge.**

The first draft rejected subscriptions on the grounds that "a subscription has nothing to rent".
Both reviews attacked this and they are both right, from different directions:

* **Flash:** anchoring on 希望有一次性 is confirmation bias. In the Chinese App Store,
  anti-subscription sentiment is strong enough that "one-time" is the *default* request, so that
  phrase carries much less information than the first draft gave it. And language learners
  demonstrably do pay annually — WaniKani, Bunpro, Renshuu.
* **Pro, and this one is a genuine contradiction in the first draft:** it rejected subscriptions
  because there is nothing ongoing to sell, and then proposed **an ongoing content pipeline** as
  the flagship Pro feature. Those cannot both be true. *"You cannot fund an infinite
  content-creation pipeline with a finite, one-time fee."*

**So the rule is alignment, not preference:**

> **A one-time price may only buy things that are finished.** Software utilities that cost
> nothing to maintain — export, custom lists, unlocked features — are honest one-time goods.
> **Ongoing content is not**, and if content is ever sold it must be sold as discrete finite
> packs, priced individually, or as a subscription that is honest about what it renews.

A hybrid (annual pass + lifetime unlock) is a legitimate Stage 3 shape and is explicitly *not*
ruled out here. It was ruled out in the first draft on evidence that will not carry it.

**Price stays an owner decision.** Not an agent's call, and it needs real comparables.

---

## §E The red line, revised — grandfather rather than freeze

The first draft's red line was: *nothing currently free may ever move behind the paywall*. Both
reviews called this over-cautious to the point of making Pro unsellable, and Pro named it
**"timid"** rather than principled — the app has one review, so "the existing base" whose
reaction the rule protects is close to nobody, while the rule permanently constrains every
future user.

**They are right that the rule was wrong. They are right for a reason that is checkable, and I
checked it:**

`AppTransaction.shared` exposes `originalAppVersion` and `originalPurchaseDate`. Verified present
in the shipping SDK and available from **macOS 13 / iOS 16**, below this app's deployment
targets. So an existing install can be identified **on-device, with no account, no server and no
tracking**, and granted everything it already had, permanently.

**The revised rule:**

> **No existing install loses anything, ever — enforced in code by grandfathering on
> `originalAppVersion`, not by freezing the free tier for all time.** What a *new* user gets is a
> product decision that stays open.

Two conditions on it, and neither is optional:

* **⚠️ Verify the offline behaviour before relying on it.** `AppTransaction.shared` may require
  a network call when it is not cached. For an app whose entire pitch is "works fully offline",
  a grandfathered user who opens the app on a plane must not lose access. **This is unverified
  and is a gate on the design, not a detail** — the failure must be "assume entitled" when the
  transaction cannot be read, never "assume not entitled".
* **A generous free tier is still the funnel.** Grandfathering makes gating *possible*; it does
  not make aggressive gating *wise* for an app with no reviews and no traffic.

---

## §F Pro candidates, re-ranked

**The first draft ranked these by what the existing architecture made cheap, and said so.** Both
reviews identified that as supply-side bias — building what is easy rather than what converts —
and both independently inverted the same two items. The ranking below is theirs, not the first
draft's.

### F1 — Export and custom lists · **flagship**

`SavedWordsKit`, `WordListsKit` and `JournalKit` all ship.

* Export review history, saved words and the ride log — CSV, Anki.
* Import a deck and drill it with the existing engine: a *Genki* chapter, a JLPT prep list, a
  teacher's handout.

*Why first:* it is a **finished good** — zero ongoing content labour, so it is honestly priced
once (§D). It targets the highest-intent segment in language learning, the people who already
maintain their own decks. And it is thematically exact for a privacy-first offline app: *your
data is yours and you can take it with you.* Both reviews moved this to the top independently.

### F2 — Audio, scoped honestly

`SpeechKit` ships; dictation already speaks whole sentences.

Flash's correction stands: audio is among the highest willingness-to-pay features in language
apps, and the first draft demoted it out of **engineering perfectionism** — 964 sentences are
withheld from dictation because the system voice mispronounces them.

*The honest version:* **curate a verified subset** (say the top 2,500 words and sentences whose
audio has been checked) and sell that, rather than withholding the feature until the whole corpus
is perfect or selling "audio for everything" while 964 sentences are quietly excluded.

### F3 — More content · **demoted from flagship**

Both reviews rejected this as the anchor. Flash: *"A Japanese typing learner does not exhaust
7,071 words and 6,700 sentences and say, 'I need 500 more business passages.'"* Pro: content sold
against a one-time price is unfunded future labour.

Content remains the thing this project is best at. It is just not what converts a user who
already has more than they can finish. **If sold, sell it as discrete finite packs.**

### F4 — Scenery and routes · cheap, low risk

`SceneryKit` ships. Nobody feels cheated by not owning a theme, which is not true of content or
audio. Good bundle filler; not an anchor.

### F5 — Kanji writing, pitch accent · not soon

Most expensive by a wide margin, needs content the pipeline does not produce, and the conjugation
drill it would extend has a known scheduling defect (v1.26 measured that it grades every clean
answer 5). PLAN-V1.27 §C first.

---

## §G Measurement, with kill criteria

The project's rule — *a checker that reports "no problems" is indistinguishable from a broken
checker* — translates directly: **a launch with no way to tell why it failed teaches nothing.**

* **App Store Connect** for conversion, downloads, product-page views. Baseline first (§C).
* **Local, on-device counters** — paywall/tip-jar impressions, taps, completions. **Never
  transmitted**, inspectable in a debug view, and optionally attachable by the user to a support
  email. This is the distinction the first draft got wrong: *Data Not Collected* forbids
  collecting, not counting. It separates "nobody saw it" from "everybody declined it", which is
  the only question that matters after a weak launch.
* **Placement is measurable design.** A tip jar buried in Settings and one offered after a
  completed ride are different experiments. Choose deliberately and record which was chosen.
* **Ask.** One review produced the clearest product direction this app has had. A support line
  in Settings and a real reply is a legitimate research method at this scale.

### Falsification thresholds — write these down before writing code

Flash's finding: the first draft demanded falsifiability and then set no thresholds, so any
outcome could be rationalised. Numbers below are **starting proposals, to be set by the owner
against the Stage 0 baseline** — the point is that they exist and are fixed *in advance*.

| stage | success | failure → what it kills |
|---|---|---|
| Stage 0 distribution | downloads and reviews both up meaningfully over baseline | if traffic does not move, **monetization is not the problem** — do not proceed to Stage 3 |
| Stage 1 tip jar | any sustained non-trivial tipping across ≥500 new downloads | near-zero over 60 days **kills the Pro tier**, not just the tip jar |
| Stage 3 Pro | conversion at or above the owner's pre-set floor within 45 days | below the floor after ≥500 downloads invalidates *"incremental utilities sell Pro"* — reconsider tier structure, not just price |

---

## §H Risks

* **Building the paywall in an empty room.** The largest risk, and the first draft did not
  mention it. Stage 0 exists for this.
* **A grandfathering bug.** An existing user who loses access is the one-star review this product
  cannot absorb. Fail **open**: unreadable transaction ⇒ entitled. Test the offline path, the
  no-App-Store-account path and the restore path before shipping, and treat an untested purchase
  flow the way this project treats an untested gate.
* **The description becomes untrue.** It says "no network". A purchase is a network call. Reword
  to *"works fully offline; the one-time purchase is handled by the App Store"* rather than
  defending the old wording.
* **App Privacy re-verified** against Apple's current definitions — purchases are brokered by
  Apple, so Data Not Collected *may* still hold. Check; do not assume.
* **Over-gating out of impatience.** Grandfathering makes gating possible and does not make it
  wise while there is no traffic.

---

## §I Not in this plan

* **Ads** — contradict the product and the audience.
* **Accounts and a backend** — load-bearing absences, not gaps.
* **Transmitted analytics** — local counters only (§G).
* **A price** — owner's decision, needs comparables.
* **Building Pro before Stage 1 reports** — the whole point of the staging.

---

## §J What the three reviews changed

Kept in the house style of PLAN-V1.24 and PLAN-V1.26, because the pattern repeats and is worth
watching. **The first draft's central recommendation did not survive.**

**Decisive, and it reorganised the document.** Gemini 3.1 Pro read the one review literally and
observed that the user called the *free* app perfect and asked only how to pay — so the first
draft had inferred a product pivot from a request to leave a tip. The tip jar became Stage 1 and
the Pro tier moved behind a gate that can now report "no".

**Decisive, and it exposed a contradiction inside the plan.** Pro also caught that the draft
rejected subscriptions because there is nothing ongoing to sell, then proposed ongoing content as
the flagship Pro feature. Those cannot both hold. §D now constrains the model by what it is
honest to sell once.

**Decisive, and it was checkable, so it was checked.** Gemini 3.7 Flash pointed out that
`AppTransaction` can grandfather existing users on-device, dissolving the contradiction the "red
line" was built to avoid. **Verified independently against the shipping SDK** —
`originalAppVersion` and `originalPurchaseDate` are present, available from macOS 13 / iOS 16,
below this app's targets. The red line was rewritten from *freeze forever* to *grandfather in
code*. Pro reached the same conclusion by a different route and called the original rule "timid",
which is the fairer word than "cautious".

**Both, independently, on the same two items.** Both inverted §D's ranking — export and custom
lists up, more content down — and both identified the ranking's stated basis ("what the
architecture makes cheap") as supply-side bias. When two reviewers invert the same ranking for
different reasons, that is the finding.

**Right, and it is the thing the draft never mentioned at all.** Flash: one review is a
measurement of near-zero traffic, and 2% of 40 downloads is under one sale a month. The draft
optimised the checkout of a shop with no street outside it. Distribution became Stage 0.

**Right, and it corrected a false dichotomy the draft was rather proud of.** Both reviews
rejected "App Store Connect only" as rationalised blindness, and both drew the same distinction:
*Data Not Collected* forbids collecting, not counting. Local non-transmitted counters answer
"nobody saw it" versus "everybody declined it", which ASC structurally cannot.

**Right, and embarrassing given the house style.** Flash noted the draft demanded falsifiability
and then set no thresholds, so every outcome would have been rationalisable. §G now fixes them in
advance.

**Where the reviews disagreed, and it is left open on purpose.** Flash proposed a hybrid
(annual pass plus lifetime unlock) against Pro's stricter "only sell finished things once".
Both are defensible and the choice needs Stage 1's number, which does not exist yet. §D records
the constraint both agree on — *a one-time price may only buy things that are finished* — and
leaves the shape to Stage 2.
