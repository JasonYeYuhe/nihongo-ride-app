#!/usr/bin/env python3
"""`import_review_sheets --apply` changes the bytes of the corrected entries and nothing else.

Until 2026-09-29 it wrote every corpus file it had loaded back with `json.dumps(indent=2)`.
n1..n5.json are indent=1, so a single correction rewrote all five whole (n5.json went from 1-space
to 2-space indentation in a measured dry run) — the v1.26 incident `corpus_io.CorpusFile` exists to
prevent, found by the v1.35 step-1 review (PLAN-V1.34 §F, "Step 1 done").

This copies the real corpus to a scratch directory, points the importer at the copy, and runs it
the way a person does — returned CSVs, the default dry run, then --apply — with:

  * a vocab correction   (n5, meanings.en: one line changes);
  * a passage correction (passages.json, meanings.en: one line changes — that file is indent=2
    with NO final newline, which CorpusFile could not reproduce before this change);
  * a vocab drop         (n4: the entry's lines go; its kana goes to a scratch blocklist);
  * a sheet of OK rows   (n3: reviewed, nothing to change).

The expected bytes of each changed file are made by editing the ORIGINAL TEXT line by line — never
by re-serialising the parsed data, which is what the code under test does and would grade itself.
Every other file must come back byte for byte. A second run gives one file a layout CorpusFile
cannot reproduce and checks that --apply then writes nothing at all, not the files before it.

The real Resources and blocklist are hashed before and after: a test that silently wrote the real
corpus would be worse than no test.

Run: python3 scripts/test_import_review_sheets.py
"""
import contextlib
import csv
import hashlib
import importlib.util
import io
import json
import pathlib
import shutil
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
RES = HERE.parent / "Sources/VocabKit/Resources"
BLOCKLIST = HERE.parent / "design/known-bad-readings.txt"
NAMES = ["n5", "n4", "n3", "n2", "n1", "passages"]


def load_importer():
    spec = importlib.util.spec_from_file_location("import_review_sheets", HERE / "import_review_sheets.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def plain(text):
    """True when `text` needs no JSON escaping and no correction-syntax separator, so the test can
    write its JSON line by hand and the importer reads it back as one value."""
    return (json.dumps(text, ensure_ascii=False) == f'"{text}"'
            and not any(c in text for c in ";；|"))


def entry_block(lines, rid):
    """(first, last) line index of entry `rid` in the TEXT: its `{` line through its `}`/`},`.
    Every corpus entry's first key is "id"; the id line must occur exactly once."""
    hits = [i for i, line in enumerate(lines) if line.strip() == f'"id": "{rid}",']
    if len(hits) != 1:
        raise AssertionError(f"{rid}: {len(hits)} id lines in the text, expected 1")
    first = hits[0] - 1
    if lines[first].strip() != "{":
        raise AssertionError(f"{rid}: the line before its id is {lines[first]!r}, not `{{`")
    indent = lines[first][: len(lines[first]) - len(lines[first].lstrip())]
    last = next((i for i in range(first + 1, len(lines)) if lines[i] in (indent + "}", indent + "},")), None)
    if last is None:
        raise AssertionError(f"{rid}: no closing `}}` at its opening brace's indent")
    return first, last


def expect_fixed(raw, rid, old, new, in_list):
    """`raw` with the one line holding entry `rid`'s meanings.en `old` reading `new`. A vocab
    meaning is a list — `"en": [`, one string per line, `]`; a passage's is `"en": "…",`."""
    lines = raw.split("\n")
    first, last = entry_block(lines, rid)
    en = [i for i in range(first, last) if lines[i].lstrip().startswith('"en": ')]
    if len(en) != 1:
        raise AssertionError(f"{rid}: {len(en)} `\"en\":` lines in its block, expected 1")
    i = en[0]
    if in_list:
        if (lines[i].strip(), lines[i + 1].strip()) != ('"en": [', f'"{old}"') or \
                lines[i + 2].strip() not in ("]", "],"):
            raise AssertionError(f"{rid}: meanings.en is not a one-string list in the text")
        target = i + 1
    else:
        if lines[i].strip() not in (f'"en": "{old}"', f'"en": "{old}",'):
            raise AssertionError(f"{rid}: {lines[i]!r} is not its meanings.en line")
        target = i
    lines[target] = lines[target].replace(f'"{old}"', f'"{new}"', 1)
    return "\n".join(lines)


def expect_dropped(raw, rid):
    """`raw` without entry `rid`'s lines. Not the last entry, so no comma moves."""
    lines = raw.split("\n")
    first, last = entry_block(lines, rid)
    if not lines[last].endswith("},"):
        raise AssertionError(f"{rid} is the last entry — pick another, a comma would move")
    del lines[first:last + 1]
    return "\n".join(lines)


def describe(name, original, written, expected):
    """Why `written` is not `expected`, in numbers a reader can check."""
    o, w, e = original.split("\n"), written.split("\n"), expected.split("\n")
    moved = sum(1 for a, b in zip(o, w) if a != b) + abs(len(o) - len(w))
    off = next((i for i, (a, b) in enumerate(zip(w, e)) if a != b), min(len(w), len(e)))
    return (f"{name}.json is not the original with only the corrected lines changed: {len(w):,} lines "
            f"written, {len(e):,} expected, {moved:,} differ from the original by position; first "
            f"line off the expected text is {off + 1}: {w[off] if off < len(w) else '<end>'!r} "
            f"vs {e[off] if off < len(e) else '<end>'!r}"
            + ("; final newline differs" if written.endswith("\n") != expected.endswith("\n") else ""))


def write_sheet(path, rows):
    """A returned sheet: the columns import_review_sheets reads (export writes more; it ignores them)."""
    with path.open("w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["id", "status", "correction", "notes"])
        w.writerows(rows)


def run(importer, argv, res, blocklist):
    """→ (stdout, what it raised or None)."""
    out = io.StringIO()
    raised = None
    with contextlib.redirect_stdout(out):
        try:
            importer.main(argv, resources=res, blocklist=blocklist)
        except SystemExit as exc:
            raised = exc if exc.code not in (None, 0) else None
        except Exception as exc:   # today's main() took no parameters: say so, do not crash
            raised = exc
    return out.getvalue(), raised


def main() -> int:
    failures = []
    importer = load_importer()
    real = [*(RES / f"{n}.json" for n in NAMES), BLOCKLIST]
    real_before = {p: digest(p) for p in real}

    with tempfile.TemporaryDirectory(prefix="import-review-sheets-") as tmp:
        tmp = pathlib.Path(tmp)
        res = tmp / "Resources"
        res.mkdir()
        for n in NAMES:
            shutil.copyfile(RES / f"{n}.json", res / f"{n}.json")
        blocklist = tmp / "known-bad-readings.txt"
        shutil.copyfile(BLOCKLIST, blocklist)
        original = {n: (res / f"{n}.json").read_text(encoding="utf-8") for n in NAMES}
        original_blocklist = blocklist.read_text(encoding="utf-8")

        # The entries, chosen from the data so a later corpus change cannot strand a fixed id.
        n5, n4, n3, passages = (json.loads(original[n]) for n in ("n5", "n4", "n3", "passages"))
        vocab = next(e for e in n5 if len(e["meanings"].get("en", [])) == 1 and plain(e["meanings"]["en"][0]))
        v_old = vocab["meanings"]["en"][0]
        v_new = f"{v_old} (reviewed)"
        passage = next(e for e in passages if plain(e["meanings"]["en"]))
        p_old = passage["meanings"]["en"]
        p_new = f"{p_old} (reviewed)"
        dropped = n4[len(n4) // 2]

        sheets = tmp / "sheets"
        sheets.mkdir()
        write_sheet(sheets / "vocab-n5.csv", [(vocab["id"], "修", f"en: {v_new}", ""),
                                              (n5[-1]["id"], "OK", "", ""), (n5[-2]["id"], "", "", "")])
        write_sheet(sheets / "passages.csv", [(passage["id"], "fix", f"en: {p_new}", ""),
                                              (passages[-1]["id"], "ok", "", "")])
        write_sheet(sheets / "vocab-n4.csv", [(dropped["id"], "删", "", "wrong word")])
        write_sheet(sheets / "vocab-n3.csv", [(e["id"], "ok", "", "") for e in n3[:5]])

        expected = dict(original)
        try:
            expected["n5"] = expect_fixed(original["n5"], vocab["id"], v_old, v_new, in_list=True)
            expected["passages"] = expect_fixed(original["passages"], passage["id"], p_old, p_new, in_list=False)
            expected["n4"] = expect_dropped(original["n4"], dropped["id"])
        except AssertionError as exc:
            failures.append(f"could not build the expected text — the fixture is wrong, fix it first: {exc}")
        for n in ("n5", "passages", "n4"):
            if expected[n] == original[n]:
                failures.append(f"expected {n}.json equals the original — the test would pass on a no-op")

        # 1. The default is a dry run: it names every planned change and writes nothing.
        out, raised = run(importer, [str(sheets)], res, blocklist)
        if raised:
            failures.append(f"the dry run raised {raised!r}")
        for want in (f"FIX  n5 {vocab['id']} meanings.en", f"FIX  passages {passage['id']} meanings.en",
                     f"DROP n4 {dropped['id']}", "(dry run — nothing written"):
            if want not in out:
                failures.append(f"the dry run did not print {want!r}")
        for n in NAMES:
            if (res / f"{n}.json").read_text(encoding="utf-8") != original[n]:
                failures.append(f"the dry run changed {n}.json")
        if blocklist.read_text(encoding="utf-8") != original_blocklist:
            failures.append("the dry run changed the blocklist")

        # 2. --apply: the three corrected files differ from the original by exactly the corrected
        #    lines, and every other file — the OK-only n3 among them — is byte for byte the same.
        out, raised = run(importer, [str(sheets), "--apply"], res, blocklist)
        if raised:
            failures.append(f"--apply raised {raised!r}; it printed:\n{out[-600:]}")
        for n in NAMES:
            written = (res / f"{n}.json").read_text(encoding="utf-8")
            if written != expected[n]:
                failures.append(describe(n, original[n], written, expected[n]))
        want_blocklist = original_blocklist + "# native review import\n" + dropped["kana"] + "\n"
        if blocklist.read_text(encoding="utf-8") != want_blocklist:
            failures.append(f"the blocklist did not gain exactly the dropped kana {dropped['kana']!r}")

        # 3. A file --apply would have to reformat stops the whole run before ANY file is written.
        #    n2 is given indent=3, which CorpusFile does not know; the n5 fix lists first and must
        #    not land either.
        for n in NAMES:
            shutil.copyfile(RES / f"{n}.json", res / f"{n}.json")
        n2 = json.loads(original["n2"])
        reformatted = json.dumps(n2, ensure_ascii=False, indent=3) + "\n"
        (res / "n2.json").write_text(reformatted, encoding="utf-8")
        write_sheet(sheets / "vocab-n2.csv", [(n2[0]["id"], "fix", "en: reviewed", "")])
        out, raised = run(importer, [str(sheets), "--apply"], res, blocklist)
        if not raised or "REFUSED" not in out or "n2.json" not in out:
            failures.append(f"--apply did not refuse a file it cannot write back byte for byte: "
                            f"raised {raised!r}, printed {out[-400:]!r}")
        for n in NAMES:
            want = reformatted if n == "n2" else original[n]
            if (res / f"{n}.json").read_text(encoding="utf-8") != want:
                failures.append(f"a refused --apply still wrote {n}.json")
        if blocklist.read_text(encoding="utf-8") != want_blocklist:
            failures.append("a refused --apply still appended to the blocklist")

    moved = [str(p) for p in real if digest(p) != real_before[p]]
    if moved:
        failures.append(f"THE REAL FILES CHANGED: {moved} — restore them with `git checkout --` "
                        "before anything else")

    if failures:
        print("\n".join(f"FAIL  {f}" for f in failures))
        return 1
    print(f"ok — --apply changed one line of n5.json ({vocab['id']}), one of passages.json "
          f"({passage['id']}, no final newline kept), and only {dropped['id']}'s lines of n4.json; "
          "n3/n2/n1 byte-identical; the dry run wrote nothing; a file that cannot round-trip stops "
          "--apply before any write; the real corpus untouched")
    return 0


if __name__ == "__main__":
    sys.exit(main())
