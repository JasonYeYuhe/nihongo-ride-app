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

--apply writes only the files a change touched, through corpus_io.CorpusFile, so a correction
changes that entry's bytes and nothing else. Until 2026-09-29 it wrote all six files back with
json.dumps(indent=2): one correction reformatted n1..n5.json (indent=1) whole — the v1.26 incident
corpus_io exists to prevent, found by the v1.35 step-1 review.

Usage:
    python3 scripts/import_review_sheets.py review-sheets-returned/ [--apply]
"""
import argparse
import csv
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from corpus_io import CorpusFile, residue_reasons   # noqa: E402

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


def refuse_residue(fields, fname, rid, changes):
    """True, with the row reported as skipped, when any text the correction would write carries
    quoting residue. A returned sheet has been through a spreadsheet and a CSV writer, both of
    which quote, and a quoting layer applied and never undone is how 18 Practice translations
    shipped `'''` (3e9407a). The whole correction is refused, not only the damaged field, so a
    row is never half-applied. CorpusEscapeResidueTests would catch it at gate time; this stops
    it before the JSON is written."""
    reasons = residue_reasons(fields.items())
    if reasons:
        changes.unparsed.append((fname, rid, "correction refused: " + "; ".join(reasons)))
    return bool(reasons)


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
    if refuse_residue(fields, fname, row["id"], changes):
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
    if refuse_residue(fields, fname, row["id"], changes):
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


def shown(path):
    """`path` relative to the repo when it is inside it, as given when it is not (a test's copy)."""
    try:
        return path.relative_to(ROOT)
    except ValueError:
        return path


def write_back(changes, datasets, apply: bool, blocklist=BLOCKLIST):
    """datasets: {filename: (CorpusFile, by_id)} — by_id holds the same entry objects as the
    CorpusFile's data, so an edit made through it is what gets written."""
    touched = set()
    for fname, rid, field, old, new in changes.fixes:
        print(f"FIX  {fname} {rid} {field}: {old!r} → {new!r}")
        touched.add(fname)
        if not apply:
            continue
        entry = datasets[fname][1][rid]
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
        touched.add(fname)
        if not apply:
            continue
        corpus, by_id = datasets[fname]
        corpus.data[:] = [e for e in corpus.data if e["id"] != rid]
        by_id.pop(rid, None)

    for fname, rid, why in changes.unparsed:
        print(f"SKIP {fname} {rid}: {why}")

    # Every file a change lands in must round-trip before ANY is written: a refusal half way
    # through would leave some corrections on disk and the rest not. The dry run says so too,
    # since it is where a reviewer reads what --apply will do.
    refused = [datasets[f][0].path for f in sorted(touched) if not datasets[f][0].round_trips()]
    if refused:
        print("\nREFUSED: " + ", ".join(str(shown(p)) for p in refused) + " cannot be written "
              "back byte for byte (corpus_io.CorpusFile), so writing would reformat the whole file.")
        if apply:
            raise SystemExit("nothing written")

    if not apply:
        print("\n(dry run — nothing written; add --apply)")
        return

    # Only the files a change landed in are written; the rest are not opened for writing at all.
    for fname, (corpus, _) in datasets.items():
        if fname in touched:
            corpus.write()
            print(f"wrote {shown(corpus.path)}")
    if not touched:
        print("no corpus file changed")

    if bad_readings:
        with blocklist.open("a", encoding="utf-8") as f:
            f.write(f"# native review import\n")
            for kana in bad_readings:
                f.write(kana + "\n")
        print(f"appended {len(bad_readings)} readings to {shown(blocklist)}")

    print("\nNOW RUN: swift test  (typeability + integrity gates)")


def load_datasets(resources=RES):
    """{name: (CorpusFile, by_id)} for n5..n1 and passages, read from `resources`."""
    datasets = {}
    for name in ["n5", "n4", "n3", "n2", "n1", "passages"]:
        corpus = CorpusFile(resources / f"{name}.json")
        datasets[name] = (corpus, {e["id"]: e for e in corpus.data})
    return datasets


def main(argv=None, resources=RES, blocklist=BLOCKLIST):
    """`resources` and `blocklist` are the repo's own unless a caller names others —
    scripts/test_import_review_sheets.py points both at a scratch copy."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sheets_dir", type=Path)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args(argv)

    if not args.sheets_dir.is_dir():
        sys.exit(f"not a directory: {args.sheets_dir}")

    datasets = load_datasets(resources)

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
                apply_vocab_row(row, datasets[level][1], level, changes)
        elif name == "passages":
            for row in rows:
                apply_passage_row(row, datasets["passages"][1], "passages", changes)
        else:
            print(f"skipping {csv_path.name}")
            continue
        found += 1
        print(f"read {csv_path.name} ({len(rows)} rows)")

    if not found:
        sys.exit("no vocab-*.csv / passages.csv found in that directory")

    print()
    write_back(changes, datasets, args.apply, blocklist)
    print(f"\n{changes.summary()}")


if __name__ == "__main__":
    main()
