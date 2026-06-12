#!/usr/bin/env python3
"""
Merge a native speaker's finished review sheets back into the data files.

Reads the CSVs produced by export_review_sheets.py after the reviewer filled
the status / correction / notes columns, and applies them to
Sources/VocabKit/Resources/{n5..n1,passages}.json plus the reading blocklist.

Status values (case-insensitive, zh or en):
    OK / ok            → reviewed, no change
    修 / fix           → apply `correction` (see below)
    删 / drop / delete → remove the entry; vocab kana goes to the blocklist

Correction syntax — either explicit field prefixes, one or more separated by
';' or '|' :
    kana: ちょうかく | en: hearing; sense of hearing | zh: 听觉 | surface: 聴覚
    pos: n/v
    display: ... (passages only)
or bare text, which is auto-routed: pure hiragana → kana, CJK → zh, latin → en.

Dry-run by default — prints every planned change. Add --apply to write.

Usage:
    python3 scripts/import_review_sheets.py review-sheets-returned/ [--apply]
"""
import argparse
import csv
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "Sources/VocabKit/Resources"
BLOCKLIST = ROOT / "design/known-bad-readings.txt"

HIRAGANA_ONLY = re.compile(r"^[ぁ-ゖー]+$")
HAS_CJK = re.compile(r"[一-鿿]")
FIELD_KEYS = {"kana", "surface", "en", "zh", "pos", "display", "topic"}

OK_VALUES = {"ok", "好", "可", "✓"}
FIX_VALUES = {"修", "fix", "修正", "改"}
DROP_VALUES = {"删", "drop", "delete", "删除", "x"}


def parse_correction(text: str) -> dict:
    """Split `kana: …; en: …`-style corrections; route bare text by script."""
    text = text.strip()
    if not text:
        return {}
    fields = {}
    parts = re.split(r"[;|]\s*(?=(?:kana|surface|en|zh|pos|display|topic)\s*[::])", text)
    explicit = False
    for part in parts:
        match = re.match(r"\s*(kana|surface|en|zh|pos|display|topic)\s*[::]\s*(.+)\s*$",
                         part, re.S)
        if match:
            fields[match.group(1)] = match.group(2).strip()
            explicit = True
    if explicit:
        return fields
    # Bare correction: guess the field from the script used.
    if HIRAGANA_ONLY.match(text):
        return {"kana": text}
    if HAS_CJK.search(text) and not re.search(r"[a-zA-Z]", text):
        return {"zh": text}
    if re.match(r"^[\x20-\x7e]+$", text) and re.search(r"[a-zA-Z]", text):
        return {"en": text}
    return {"?": text}


def normalize_status(raw: str) -> str:
    value = (raw or "").strip().lower()
    if not value:
        return ""
    if value in OK_VALUES:
        return "ok"
    if value in FIX_VALUES:
        return "fix"
    if value in DROP_VALUES:
        return "drop"
    return "?"


class Changes:
    def __init__(self):
        self.fixes = []      # (file, id, field, old, new)
        self.drops = []      # (file, id, kana)
        self.unparsed = []   # (file, id, status_or_correction)
        self.reviewed = 0

    def summary(self):
        return (f"{self.reviewed} rows reviewed-ok, {len(self.fixes)} field fixes, "
                f"{len(self.drops)} drops, {len(self.unparsed)} rows I couldn't parse")


def apply_vocab_row(row, entries_by_id, fname, changes):
    status = normalize_status(row.get("status", ""))
    if status == "":
        return
    entry = entries_by_id.get(row["id"])
    if entry is None:
        changes.unparsed.append((fname, row["id"], "unknown id"))
        return
    if status == "ok":
        changes.reviewed += 1
        return
    if status == "?":
        changes.unparsed.append((fname, row["id"], f"status={row.get('status')}"))
        return
    if status == "drop":
        changes.drops.append((fname, row["id"], entry["kana"]))
        return
    fields = parse_correction(row.get("correction", ""))
    if not fields or "?" in fields:
        changes.unparsed.append((fname, row["id"], f"correction={row.get('correction')}"))
        return
    for key, value in fields.items():
        if key == "kana":
            changes.fixes.append((fname, row["id"], "kana", entry["kana"], value))
        elif key == "surface":
            changes.fixes.append((fname, row["id"], "surface", entry.get("surface", ""), value))
        elif key == "pos":
            changes.fixes.append((fname, row["id"], "pos", "/".join(entry.get("pos", [])), value))
        elif key in ("en", "zh"):
            old = "; ".join(entry["meanings"].get(key, []))
            changes.fixes.append((fname, row["id"], f"meanings.{key}", old, value))
        else:
            changes.unparsed.append((fname, row["id"], f"{key} not valid for vocab"))


def apply_passage_row(row, entries_by_id, fname, changes):
    status = normalize_status(row.get("status", ""))
    if status == "":
        return
    entry = entries_by_id.get(row["id"])
    if entry is None:
        changes.unparsed.append((fname, row["id"], "unknown id"))
        return
    if status == "ok":
        changes.reviewed += 1
        return
    if status == "?":
        changes.unparsed.append((fname, row["id"], f"status={row.get('status')}"))
        return
    if status == "drop":
        changes.drops.append((fname, row["id"], None))
        return
    fields = parse_correction(row.get("correction", ""))
    if not fields or "?" in fields:
        changes.unparsed.append((fname, row["id"], f"correction={row.get('correction')}"))
        return
    for key, value in fields.items():
        if key == "display":
            changes.fixes.append((fname, row["id"], "display", entry.get("display", ""), value))
        elif key == "kana":
            changes.fixes.append((fname, row["id"], "kana", entry["kana"], value))
        elif key in ("en", "zh"):
            changes.fixes.append((fname, row["id"], f"meanings.{key}",
                                  entry["meanings"].get(key, ""), value))
        elif key == "topic":
            changes.fixes.append((fname, row["id"], "topic", entry.get("topic", ""), value))
        else:
            changes.unparsed.append((fname, row["id"], f"{key} not valid for passage"))


def write_back(changes, datasets, apply: bool):
    """datasets: {filename: (json_path, list_data, by_id)}"""
    for fname, rid, field, old, new in changes.fixes:
        print(f"FIX  {fname} {rid} {field}: {old!r} → {new!r}")
        if not apply:
            continue
        entry = datasets[fname][2][rid]
        if field == "kana":
            entry["kana"] = new
        elif field == "surface":
            entry["surface"] = new
        elif field == "pos":
            entry["pos"] = [p.strip() for p in re.split(r"[/,、]", new) if p.strip()]
        elif field == "display":
            entry["display"] = new
        elif field == "topic":
            entry["topic"] = new
        elif field.startswith("meanings."):
            lang = field.split(".")[1]
            if fname == "passages":
                entry["meanings"][lang] = new
            else:
                entry["meanings"][lang] = [m.strip() for m in re.split(r"[;;]", new) if m.strip()]

    bad_readings = []
    for fname, rid, kana in changes.drops:
        print(f"DROP {fname} {rid}" + (f" (blocklist: {kana})" if kana else ""))
        if kana:
            bad_readings.append(kana)
        if not apply:
            continue
        path, data, by_id = datasets[fname]
        data[:] = [e for e in data if e["id"] != rid]
        by_id.pop(rid, None)

    for fname, rid, why in changes.unparsed:
        print(f"SKIP {fname} {rid}: {why}")

    if not apply:
        print("\n(dry run — nothing written; add --apply)")
        return

    for fname, (path, data, _) in datasets.items():
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"wrote {path.relative_to(ROOT)}")

    if bad_readings:
        with BLOCKLIST.open("a", encoding="utf-8") as f:
            f.write(f"# native review import\n")
            for kana in bad_readings:
                f.write(kana + "\n")
        print(f"appended {len(bad_readings)} readings to {BLOCKLIST.relative_to(ROOT)}")

    print("\nNOW RUN: swift test  (typeability + integrity gates)")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sheets_dir", type=Path)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    if not args.sheets_dir.is_dir():
        sys.exit(f"not a directory: {args.sheets_dir}")

    datasets = {}
    for level in ["n5", "n4", "n3", "n2", "n1"]:
        path = RES / f"{level}.json"
        data = json.loads(path.read_text(encoding="utf-8"))
        datasets[level] = (path, data, {e["id"]: e for e in data})
    ppath = RES / "passages.json"
    pdata = json.loads(ppath.read_text(encoding="utf-8"))
    datasets["passages"] = (ppath, pdata, {e["id"]: e for e in pdata})

    changes = Changes()
    found = 0
    for csv_path in sorted(args.sheets_dir.glob("*.csv")):
        name = csv_path.stem  # vocab-n3 / passages
        with csv_path.open(encoding="utf-8-sig", newline="") as f:
            rows = list(csv.DictReader(f))
        if name.startswith("vocab-"):
            level = name.removeprefix("vocab-")
            if level not in datasets:
                print(f"skipping {csv_path.name} (unknown level)")
                continue
            for row in rows:
                apply_vocab_row(row, datasets[level][2], level, changes)
        elif name == "passages":
            for row in rows:
                apply_passage_row(row, datasets["passages"][2], "passages", changes)
        else:
            print(f"skipping {csv_path.name}")
            continue
        found += 1
        print(f"read {csv_path.name} ({len(rows)} rows)")

    if not found:
        sys.exit("no vocab-*.csv / passages.csv found in that directory")

    print()
    write_back(changes, datasets, args.apply)
    print(f"\n{changes.summary()}")


if __name__ == "__main__":
    main()
