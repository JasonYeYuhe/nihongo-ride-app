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


# The number comparison used to live here and has been REMOVED. It caught exactly one real
# defect across three corpora — "I caught a big fish" against 钓到了两条大鱼 — and produced
# about eight false positives, and each fix opened a new hole:
#
#   一个圆      一 plus a classifier is Chinese's indefinite article, not a count
#   8:30        one clock time, not the numbers 8 and 30
#   四月        April, not four of something
#   三到四个小时  a range written with 到, which the range patterns did not cover
#   乱七八糟     七八 inside an idiom meaning "in a mess" — a false positive the range fix
#               itself created
#   一周に二回    "a week" made the article rule fire against a genuine count of 2
#
# Chinese numerals appear in idioms, approximations, classifiers and dates in ways a regex
# cannot separate from quantities, and a check that mostly fires on good material trains
# people to ignore it. The subject and day-part comparisons below have been stable across
# every corpus, so those stay.


def disagreements(en, zh):
    out = []
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
