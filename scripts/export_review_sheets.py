#!/usr/bin/env python3
"""
Export Nihongo Ride vocabulary and passages into reviewer-friendly CSVs.

Usage:
    python3 scripts/export_review_sheets.py [output_dir]

Default output_dir = "review-sheets/". Produces:
    review-sheets/
        vocab-n5.csv  (~646 rows)
        vocab-n4.csv  (~642 rows)
        vocab-n3.csv
        vocab-n2.csv
        vocab-n1.csv
        passages.csv   (183 rows)
        README.md      (instructions for the reviewer)

Each row has:
    id, surface (汉字), kana (假名読音), romaji, pos, en, zh, source,
    status (blank — reviewer fills: OK / 修 / 删),
    correction (blank — reviewer fills in the fix),
    notes (blank — for any extra reviewer remark)

`source` column reflects provenance via id-prefix:
    n5-xxx → "hand"      (hand-authored by us)
    *-g*   → "Gemini"    (LLM-generated)
    *-b*   → "Bluskyo"   (Bluskyo word+reading, LLM meanings)
    *-k*   → "Bluskyo-K" (Bluskyo katakana loanword)
"""
import csv
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "Sources/VocabKit/Resources"

REVIEW_COLS = ["status", "correction", "notes"]


def romaji_hint(kana: str) -> str:
    """A simple Hepburn-ish romaji hint, just for reviewer reference.
    Doesn't need to be perfect — they'll judge from the kana."""
    table = {
        "あ":"a","い":"i","う":"u","え":"e","お":"o",
        "か":"ka","き":"ki","く":"ku","け":"ke","こ":"ko",
        "が":"ga","ぎ":"gi","ぐ":"gu","げ":"ge","ご":"go",
        "さ":"sa","し":"shi","す":"su","せ":"se","そ":"so",
        "ざ":"za","じ":"ji","ず":"zu","ぜ":"ze","ぞ":"zo",
        "た":"ta","ち":"chi","つ":"tsu","て":"te","と":"to",
        "だ":"da","ぢ":"ji","づ":"zu","で":"de","ど":"do",
        "な":"na","に":"ni","ぬ":"nu","ね":"ne","の":"no",
        "は":"ha","ひ":"hi","ふ":"fu","へ":"he","ほ":"ho",
        "ば":"ba","び":"bi","ぶ":"bu","べ":"be","ぼ":"bo",
        "ぱ":"pa","ぴ":"pi","ぷ":"pu","ぺ":"pe","ぽ":"po",
        "ま":"ma","み":"mi","む":"mu","め":"me","も":"mo",
        "や":"ya","ゆ":"yu","よ":"yo",
        "ら":"ra","り":"ri","る":"ru","れ":"re","ろ":"ro",
        "わ":"wa","を":"wo","ん":"n","ー":"-",
    }
    katakana_to_hira = lambda c: chr(ord(c) - 0x60) if 0x30A1 <= ord(c) <= 0x30F4 else c
    out = []
    chars = [katakana_to_hira(c) for c in kana]
    i = 0
    while i < len(chars):
        c = chars[i]
        if i + 1 < len(chars) and chars[i + 1] in "ゃゅょ":
            base = table.get(c, c)
            v = {"ゃ": "ya", "ゅ": "yu", "ょ": "yo"}[chars[i + 1]]
            out.append(base[:-1] + v if base.endswith(("i",)) else base + v)
            i += 2
        elif c == "っ":
            if i + 1 < len(chars):
                nxt = table.get(chars[i + 1], "")
                if nxt and nxt[0] not in "aiueo":
                    out.append(nxt[0])
            i += 1
        else:
            out.append(table.get(c, c))
            i += 1
    return "".join(out)


def source_label(entry_id: str) -> str:
    """Provenance from id format. Hand-authored entries have descriptive slugs
    (e.g. n5-mizu); generated ones use numeric suffixes (e.g. n5-g001)."""
    if re.fullmatch(r"n\d-g\d+", entry_id):
        return "Gemini"
    if re.fullmatch(r"n\d-k\d+", entry_id):
        return "Bluskyo-K"
    if re.fullmatch(r"n\d-b\d+", entry_id):
        return "Bluskyo"
    if entry_id.startswith("p") or entry_id.startswith("para"):
        return "Tatoeba-inspired"
    if entry_id.startswith("n5-"):
        return "hand"
    return "?"


def export_vocab(level: str, outdir: Path) -> int:
    entries = json.loads((RES / f"{level}.json").read_text(encoding="utf-8"))
    path = outdir / f"vocab-{level}.csv"
    with path.open("w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow([
            "id", "surface", "kana", "romaji",
            "pos", "english", "chinese", "source", *REVIEW_COLS,
        ])
        for e in entries:
            w.writerow([
                e["id"],
                e.get("surface", ""),
                e["kana"],
                romaji_hint(e["kana"]),
                "/".join(e.get("pos", [])),
                "; ".join(e["meanings"].get("en", [])),
                "; ".join(e["meanings"].get("zh", [])),
                source_label(e["id"]),
                "", "", "",
            ])
    return len(entries)


def export_passages(outdir: Path) -> int:
    entries = json.loads((RES / "passages.json").read_text(encoding="utf-8"))
    path = outdir / "passages.csv"
    with path.open("w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow([
            "id", "display", "kana_only", "topic", "level",
            "english", "chinese", "source", *REVIEW_COLS,
        ])
        for e in entries:
            w.writerow([
                e["id"],
                e.get("display", e["kana"]),
                e["kana"],
                e.get("topic", ""),
                e.get("level", ""),
                e["meanings"].get("en", ""),
                e["meanings"].get("zh", ""),
                "Tatoeba-inspired",
                "", "", "",
            ])
    return len(entries)


README = """\
# Nihongo Ride — 母语者审清单 / Native-speaker Review Sheets

请用 Numbers / Excel / Google Sheets 打开这些 CSV(已为 BOM-UTF-8,中文/日文应正常显示)。

Open these CSVs in Numbers / Excel / Google Sheets (BOM-UTF-8, Japanese/Chinese display correctly).

## Files

| 文件 / File | 内容 / Content | 数量 / Count |
|---|---|---|
| `vocab-n5.csv` | N5 词汇 vocab | (~646) |
| `vocab-n4.csv` | N4 词汇 vocab | (~642) |
| `vocab-n3.csv` | N3 词汇 vocab | (~1452) |
| `vocab-n2.csv` | N2 词汇 vocab | (~1748) |
| `vocab-n1.csv` | N1 词汇 vocab | (~2587) |
| `passages.csv` | Practice 模式文章 passages | (~183) |

## How to review / 如何审

每行填三个空列 / Fill these three blank columns per row:

| 列 / Column | 怎么填 / How to fill |
|---|---|
| **status** | 填 `OK` / `修` / `删`(英文 `ok` / `fix` / `drop` 也行)|
| **correction** | 如果 `status = 修`,把正确读音/释义/词形写这里 / If `fix`, write the correct version here |
| **notes** | 任何附加备注 / Any extra remark |

### 重点关注 / Focus areas

1. **kana (读音)** — 是否就是 surface 这个词的标准读音?是不是误读/截断?(Bluskyo 来源约 1% 行有误)
2. **english / chinese** — 释义是否准确、是否自然?是不是有偏离原义的?
3. **pos (词性)** — n / v / adj-i / adj-na / adv 等是否对应?
4. **passages.csv** 还要看:整段读起来是否自然、是否有不日本人会说的表达。

### 源标签 / Source labels

| `source` | 意思 / Meaning |
|---|---|
| `hand` | 我们手写的(N5 启动包,质量较高)|
| `Gemini` | Gemini 3.1 Pro 生成,已过机器审核 |
| `Bluskyo` | 词形/读音/等级来自 Bluskyo,释义 LLM 生成 |
| `Bluskyo-K` | 同上,但是片假名外来词 |
| `Tatoeba-inspired` | Practice 段,以 Tatoeba 为灵感、LLM 衍生 |

`hand` 标签的多半已审过,可以优先抽 `Gemini` / `Bluskyo` 的样本。

## 提交 / Submitting your review

完成后把改过的 CSV 给我;我会拿你填的 `status / correction` 直接合并回数据 + 同步进黑名单。
When done, send back the edited CSVs. We'll merge the `status` / `correction` columns
straight into the data + sync the blocklist (`design/known-bad-readings.txt`).

谢谢!/ Thank you! 🙏
"""


def main():
    outdir = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "review-sheets"
    outdir.mkdir(parents=True, exist_ok=True)

    total = 0
    print(f"writing to {outdir}/")
    for level in ["n5", "n4", "n3", "n2", "n1"]:
        n = export_vocab(level, outdir)
        print(f"  vocab-{level}.csv  ({n} rows)")
        total += n
    n = export_passages(outdir)
    print(f"  passages.csv      ({n} rows)")
    total += n
    (outdir / "README.md").write_text(README, encoding="utf-8")
    print(f"  README.md")
    print(f"\nDone. {total} rows ready for review.")


if __name__ == "__main__":
    main()
