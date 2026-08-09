#!/usr/bin/env python3
"""Do the English and Chinese translations of a sentence say the same thing?

The N5/N4 batch produced 17 adjudicated defects and most were not the Japanese being wrong —
they were the two glosses disagreeing with EACH OTHER while nothing checked them:

    時計   en "clock"              zh 这块手表 (a wristwatch)
    毎日   en "every night"        zh 每天
    負けた  en "we lost"            zh 我输了      (the Japanese states no subject)
    注射   en "I received a shot"  zh 接种了流感疫苗 (vaccination, a different word)

The generator writes three independent renderings in one pass, so nothing forces them to
agree. Full semantic comparison needs a reviewer, but a useful slice is mechanical: when both
translations state a NUMBER, a TIME WORD, or a first-person subject, they must state the same
one. Those are the disagreements that reach a learner as a flat contradiction.

This is a REVIEW FLAG, not a rejection. It fires on things a human should look at, and the
calibration below is the reason: run against the shipped corpus it must not condemn material
that reviewers already accepted.

    python3 scripts/check_translation_agreement.py                # whole corpus
    python3 scripts/check_translation_agreement.py --batch f.json  # one generated batch
"""
import argparse
import json
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent

# English number words up to twelve cover essentially every example sentence.
EN_NUM = {"one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
          "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12}
ZH_NUM = {"一": 1, "两": 2, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7,
          "八": 8, "九": 9, "十": 10}

# Time-of-day words that are NOT interchangeable. Each entry is (english regex, chinese set).
TIME_WORDS = [
    (r"\bevery day\b|\bdaily\b", {"每天", "每日"}),
    (r"\bevery night\b|\bevery evening\b", {"每晚", "每天晚上"}),
    (r"\bevery morning\b", {"每天早上", "每早", "每天早晨"}),
    (r"\bmorning\b", {"早上", "上午", "早晨"}),
    (r"\bnight\b|\bevening\b", {"晚上", "夜里", "傍晚"}),
    (r"\byesterday\b", {"昨天", "昨日"}),
    (r"\btomorrow\b", {"明天", "明日"}),
]


def numbers_in(en, zh):
    # Clock times and dates are not quantities. "8:30" is one time, not the numbers 8 and 30,
    # and 四月 is April, not four of something — the first version reported 「毎朝八時半までに」
    # against 八点半 as a disagreement, and matched an English article against the 4 in 四月.
    en = re.sub(r"\b\d{1,2}:\d{2}\b", " ", en)
    en = re.sub(r"\b(January|February|March|April|May|June|July|August|September|October"
                r"|November|December)\b", " ", en, flags=re.I)
    zh = re.sub(r"[一二三四五六七八九十百]+[点時]半?", " ", zh)
    zh = re.sub(r"[一二三四五六七八九十]+月", " ", zh)
    en_nums = {int(m) for m in re.findall(r"\b(\d+)\b", en)}
    en_nums |= {EN_NUM[w] for w in re.findall(r"[a-z]+", en.lower()) if w in EN_NUM}
    # English marks "one" with an article, so 「大きな魚を釣りました」 / "I caught a big fish"
    # against 「钓到了两条大鱼」 is a real contradiction the number scan missed entirely — it
    # was the batch's second "wrong" verdict. Count a/an as 1, but only when the Chinese
    # states a count, so plain articles do not manufacture a disagreement everywhere.
    if not en_nums and re.search(r"\b(a|an)\s+\w", en, re.I):
        en_nums = {1}
    zh_nums = {int(m) for m in re.findall(r"(\d+)", zh)}
    # A bare 一/两 before a classifier is a quantity; 一 inside 一起/一样 is not.
    for ch, val in ZH_NUM.items():
        # 一 + classifier is Chinese's indefinite article, not a count — 一个圆 is "a circle".
        # Treating it as the number 1 made 「直径十センチの円」 / "a diameter of ten
        # centimeters" / 请画一个直径十厘米的圆 look like 10-versus-1. English "a" is dropped
        # for the same reason, so the two sides stay symmetric.
        if val == 1:
            continue
        if re.search(ch + r"[个只条件本张位杯瓶次天年月日点头把块份]", zh):
            zh_nums.add(val)
    # 一两个 is "one or two", not "two" — without this the check reported en [1,2] against
    # zh [2] on 「誰にでも一つや二つの欠点はある」, where the two renderings agree exactly.
    if "一两" in zh:
        zh_nums |= {1, 2}
    return en_nums, zh_nums


def disagreements(en, zh):
    out = []
    en_nums, zh_nums = numbers_in(en, zh)
    if en_nums and zh_nums and en_nums != zh_nums:
        out.append(f"numbers differ: en {sorted(en_nums)} vs zh {sorted(zh_nums)}")

    # Only the day-part words, and only when the Chinese names a DIFFERENT day part. The
    # first version also compared yesterday/tomorrow against morning/night and reported
    # 「明日は朝から」 / 「明天一早」 as a disagreement, though both say tomorrow morning.
    DAY_PARTS = [t for t in TIME_WORDS if t[0].startswith(r"\bevery") or
                 t[0] in (r"\bmorning\b", r"\bnight\b|\bevening\b")]
    for pattern, zh_forms in DAY_PARTS:
        if re.search(pattern, en, re.I):
            others = {f for pat, forms in DAY_PARTS if pat != pattern for f in forms} - zh_forms
            hit = [f for f in others if f in zh]
            if hit and not any(f in zh for f in zh_forms):
                out.append(f"time word differs: en /{pattern}/ vs zh {hit[0]}")
            break

    # "our" does not mean 我们 — 我家の / 我的 render it perfectly, and flagging
    # 「Our dog is timid」 against 「我家的狗…」 is noise. Only an explicit subject pronoun
    # counts.
    en_we = bool(re.search(r"\bwe\b", en, re.I))
    # "Let me see" is a discourse filler, not a first-person subject — it made 「ええと、次の
    # 予定は何でしたっけ」 look like a disagreement with 我们接下来的计划, where both
    # renderings in fact say "our".
    en_i = bool(re.search(r"\bI\b|\bmy\b", en)) or bool(
        re.search(r"\bme\b", en) and not re.search(r"\blet me\b", en, re.I))
    zh_we = "我们" in zh
    zh_i = bool(re.search(r"我(?!们)", zh))
    if en_we and zh_i and not zh_we:
        out.append("subject differs: en says we, zh says 我")
    if en_i and zh_we and not zh_i:
        out.append("subject differs: en says I, zh says 我们")
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--batch", help="a generated batch JSON instead of the shipped corpus")
    args = ap.parse_args()

    if args.batch:
        rows = [(x.get("id", "?"), x.get("en", ""), x.get("zh", ""), x.get("jp", ""))
                for x in json.load(open(args.batch))]
    else:
        rows = []
        for path in sorted((REPO / "Sources/VocabKit/Resources").glob("n[1-5].json")):
            for e in json.load(path.open()):
                if (e.get("exJP") or "").strip():
                    rows.append((e["id"], e.get("exEN") or "", e.get("exZH") or "",
                                 e["exJP"]))

    flagged = []
    for eid, en, zh, jp in rows:
        if not en or not zh:
            continue
        problems = disagreements(en, zh)
        if problems:
            flagged.append((eid, problems, jp, en, zh))

    print(f"sentences with both translations : {len(rows)}")
    print(f"flagged for review               : {len(flagged)} "
          f"({100 * len(flagged) / max(1, len(rows)):.1f}%)")
    for eid, problems, jp, en, zh in flagged[:20]:
        print(f"\n  {eid}  {problems[0]}")
        print(f"     {jp}")
        print(f"     en {en}")
        print(f"     zh {zh}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
