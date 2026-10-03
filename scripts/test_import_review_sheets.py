#!/usr/bin/env python3
"""`import_review_sheets --apply` changes the bytes of the corrected entries and nothing else.

Until that change reached main on 2026-10-03 (the merge of fc406f1, authored 2026-09-29), the
importer wrote every corpus file it had loaded back with `json.dumps(indent=2)`. n1..n5.json are
indent=1, so a single correction rewrote all five whole (n5.json went from 1-space to 2-space
indentation in a measured dry run) — the v1.26 incident `corpus_io.CorpusFile` exists to prevent,
found by the v1.35 step-1 review (PLAN-V1.34 §F, "Step 1 done").

This copies the real corpus to a scratch directory, points the importer at the copy, and runs it
the way a person does — returned CSVs, the default dry run, then --apply — with:

  * corrections that JSON must escape, or must leave alone, on their way to disk:
      - n5, meanings.en with a double quote — written `\\"`;
      - n1, meanings.en with a character outside the BMP and another quote. n1 already holds `\\"`
        escapes, and every one of them must come back as it was;
      - passages.json, meanings.en with U+2028, which JSON leaves raw. That file is indent=2 with
        NO final newline;
  * a correction holding a backslash, which the residue refusal turns away as a whole row;
  * a vocab drop         (n4: the entry's lines go; its kana goes to a scratch blocklist);
  * a sheet of OK rows   (n3: reviewed, nothing to change);
  * an untouched file the writer could not reproduce (n2 at indent=3), which must not matter.

The expected bytes of each changed file are made by editing the ORIGINAL TEXT line by line, with
each correction's JSON form written out by hand. They are never made by re-serialising the parsed
data: that is what the code under test does, and it would grade itself. The written files must
also parse back to exactly what the reviewer typed, which holds the hand-written forms to account.
Every other file must come back byte for byte. A file no change touched must not be written at
all — same inode, same mtime — because writing it is what stops on n2 half way through a run.

Then two runs in which a TOUCHED file cannot round-trip: one through a fix (n2), one through a drop
alone (n4). Each must say so in the dry run, in the REFUSED line a reviewer reads. On --apply each
must stop with "nothing written" and write nothing at all, not even the files listed before it.

The importer is loaded and run from a scratch MIRROR of the repo. The mirror holds its scripts, the
Resources and the blocklist at their usual relative places, so the importer's module-level ROOT,
RES and BLOCKLIST name scratch files, and the test points it at a second copy. If a `resources=` or
`blocklist=` argument is ever lost on the way down, the importer writes the mirror's files, the
test says so, and the real checkout is never opened for writing. Before this, only a hash taken
afterwards guarded it. That hash is kept as a backstop.

Run: python3 scripts/test_import_review_sheets.py
"""
import ast
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
RES_IN_REPO = pathlib.Path("Sources/VocabKit/Resources")
BLOCKLIST_IN_REPO = pathlib.Path("design/known-bad-readings.txt")
RES = HERE.parent / RES_IN_REPO
BLOCKLIST = HERE.parent / BLOCKLIST_IN_REPO
NAMES = ["n5", "n4", "n3", "n2", "n1", "passages"]

# Each correction, and the JSON text it must be written as — typed here by hand, not made with
# json.dumps, which is the serialiser under test.
N5_NEW, N5_JSON = 'the "Yamanote" line', 'the \\"Yamanote\\" line'
N1_NEW, N1_JSON = '\U00020BB7 (the "tsuchi" yoshi)', '\U00020BB7 (the \\"tsuchi\\" yoshi)'
P_NEW, P_JSON = "Line one.\u2028Line two.", "Line one.\u2028Line two."   # U+2028 is not escaped
BACKSLASH = "en: C:\\Windows"   # residue_reasons refuses any backslash, so this row is a SKIP
TOUCHED = {"n5", "n4", "n1", "passages"}


def sibling_imports(path):
    """The scripts beside this one that `path` imports, anywhere in its source, by module name."""
    names = set()
    for node in ast.walk(ast.parse(path.read_text(encoding="utf-8"))):
        if isinstance(node, ast.Import):
            names.update(alias.name.split(".")[0] for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.level == 0 and node.module:
            names.add(node.module.split(".")[0])
    return {name for name in names if (HERE / f"{name}.py").is_file()}


def build_mirror(root):
    """`root` laid out as the repo is, holding what the importer reads: the importer and every
    script it imports (through their own imports too) in scripts/, the corpus in
    Sources/VocabKit/Resources and the blocklist in design/. → the module names copied."""
    (root / "scripts").mkdir(parents=True)
    copied, todo = set(), ["import_review_sheets"]
    while todo:
        name = todo.pop()
        if name not in copied:
            copied.add(name)
            shutil.copyfile(HERE / f"{name}.py", root / "scripts" / f"{name}.py")
            todo.extend(sibling_imports(HERE / f"{name}.py"))
    (root / RES_IN_REPO).mkdir(parents=True)
    for n in NAMES:
        shutil.copyfile(RES / f"{n}.json", root / RES_IN_REPO / f"{n}.json")
    (root / BLOCKLIST_IN_REPO).parent.mkdir(parents=True)
    shutil.copyfile(BLOCKLIST, root / BLOCKLIST_IN_REPO)
    return copied


def inside(path, root):
    try:
        pathlib.Path(path).resolve().relative_to(root)
        return True
    except ValueError:
        return False


def load_importer(root, copied):
    """→ (the importer as root/scripts holds it, what of it resolves to the real checkout instead).

    The scripts it imports are dropped from sys.modules first, so its own imports find
    root/scripts' copies — the importer puts that directory first on sys.path — and not a copy
    some earlier import cached from the real scripts/. A script the mirror lacks is still found,
    in the real scripts/ that `python3 scripts/<this>` puts on sys.path, so what is checked is
    every module now loaded from the real scripts/, not only the ones copied. (Not the whole
    checkout: a python run from the repo's own .venv-jp may load site-packages from inside it.)"""
    for name in copied:
        sys.modules.pop(name, None)
    spec = importlib.util.spec_from_file_location("import_review_sheets", root / "scripts/import_review_sheets.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    outside = [f"{name} loaded from {loaded.__file__}" for name, loaded in sorted(sys.modules.items())
               if name != "__main__" and getattr(loaded, "__file__", None) and inside(loaded.__file__, HERE)]
    outside += [f"its {attr} is {getattr(module, attr, '<missing>')}" for attr in ("ROOT", "RES", "BLOCKLIST")
                if not inside(getattr(module, attr, "<missing>"), root)]
    return module, outside


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def written_stamp(path):
    """What a write changes even when it writes the same bytes: CorpusFile.write's tmp + replace
    gives the path a new inode, and any write a new mtime."""
    st = path.stat()
    return st.st_ino, st.st_mtime_ns


def plain(text):
    """True when `text` needs no JSON escaping and no correction-syntax separator, so the test can
    find its JSON line by hand and the importer reads it back as one value."""
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


def expect_fixed(raw, rid, old, new_json, in_list):
    """`raw` with the one line holding entry `rid`'s meanings.en `old` holding `new_json` instead —
    the JSON text of the new value, written by the caller. A vocab meaning is a list —
    `"en": [`, one string per line, `]`; a passage's is `"en": "…",`."""
    lines = raw.split("\n")   # not splitlines(): that would also split at U+2028
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
    lines[target] = lines[target].replace(f'"{old}"', f'"{new_json}"', 1)
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
    path.parent.mkdir(parents=True, exist_ok=True)
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
        except Exception as exc:   # a main() without these parameters, say: report it, do not crash
            raised = exc
    return out.getvalue(), raised


def refused_run(importer, what, sheets, res, blocklist, line, texts, blocklist_text):
    """Failures of one run that must be refused: the dry run prints `line` — the REFUSED line, which
    is where a reviewer reads what --apply will do — and --apply prints it and stops with "nothing
    written", having written no corpus file and not the blocklist."""
    failures = []
    out, raised = run(importer, [str(sheets)], res, blocklist)
    if raised or line not in out.splitlines():
        failures.append(f"with {what}, the dry run did not print {line!r} (it raised {raised!r}); "
                        f"it printed {out[-500:]!r}")
    out, raised = run(importer, [str(sheets), "--apply"], res, blocklist)
    if str(raised) != "nothing written" or line not in out.splitlines():
        failures.append(f"with {what}, --apply did not refuse before writing: raised {raised!r}, "
                        f"printed {out[-500:]!r}")
    for n in NAMES:
        if (res / f"{n}.json").read_text(encoding="utf-8") != texts[n]:
            failures.append(f"with {what}, a refused --apply still wrote {n}.json")
    if blocklist.read_text(encoding="utf-8") != blocklist_text:
        failures.append(f"with {what}, a refused --apply still appended to the blocklist")
    return failures


def main() -> int:
    failures = []
    real = [*(RES / f"{n}.json" for n in NAMES), BLOCKLIST]
    real_before = {p: digest(p) for p in real}

    with tempfile.TemporaryDirectory(prefix="import-review-sheets-") as tmp:
        tmp = pathlib.Path(tmp).resolve()
        mirror = tmp / "repo"
        importer, outside = load_importer(mirror, build_mirror(mirror))
        if outside:
            # Then a lost argument would reach the real checkout. Run nothing.
            print(f"FAIL  the importer loaded from {mirror} reaches outside it — "
                  f"{'; '.join(outside)} — so it was not run")
            return 1
        defaults = [*(mirror / RES_IN_REPO / f"{n}.json" for n in NAMES), mirror / BLOCKLIST_IN_REPO]
        defaults_before = {p: digest(p) for p in defaults}

        # The importer is pointed at a SECOND copy, outside the mirror, so a lost argument shows
        # up as a write to the mirror's own files instead of passing unseen.
        res = tmp / "work" / "Resources"
        res.mkdir(parents=True)
        for n in NAMES:
            shutil.copyfile(RES / f"{n}.json", res / f"{n}.json")
        blocklist = tmp / "work" / "known-bad-readings.txt"
        shutil.copyfile(BLOCKLIST, blocklist)
        # n2 in a layout CorpusFile cannot reproduce. No change touches it until step 3.
        n2 = json.loads((res / "n2.json").read_text(encoding="utf-8"))
        (res / "n2.json").write_text(json.dumps(n2, ensure_ascii=False, indent=3) + "\n", encoding="utf-8")
        original = {n: (res / f"{n}.json").read_text(encoding="utf-8") for n in NAMES}
        original_blocklist = blocklist.read_text(encoding="utf-8")

        def restore(texts):
            for n in NAMES:
                (res / f"{n}.json").write_text(texts[n], encoding="utf-8")
            blocklist.write_text(original_blocklist, encoding="utf-8")

        # The entries, chosen from the data so a later corpus change cannot strand a fixed id.
        n5, n4, n3, n1, passages = (json.loads(original[n]) for n in ("n5", "n4", "n3", "n1", "passages"))

        def one_plain_en(entries):
            return [e for e in entries if len(e["meanings"].get("en", [])) == 1 and plain(e["meanings"]["en"][0])]

        vocab, backslashed = one_plain_en(n5)[:2]
        v_old = vocab["meanings"]["en"][0]
        escaped = one_plain_en(n1)[0]
        e_old = escaped["meanings"]["en"][0]
        passage = next(e for e in passages if plain(e["meanings"]["en"]))
        p_old = passage["meanings"]["en"]
        dropped = n4[len(n4) // 2]

        sheets = tmp / "work" / "sheets"
        write_sheet(sheets / "vocab-n5.csv", [(vocab["id"], "修", f"en: {N5_NEW}", ""),
                                              (backslashed["id"], "fix", BACKSLASH, ""),
                                              (n5[-1]["id"], "OK", "", ""), (n5[-2]["id"], "", "", "")])
        write_sheet(sheets / "vocab-n1.csv", [(escaped["id"], "fix", f"en: {N1_NEW}", "")])
        write_sheet(sheets / "passages.csv", [(passage["id"], "fix", f"en: {P_NEW}", ""),
                                              (passages[-1]["id"], "ok", "", "")])
        write_sheet(sheets / "vocab-n4.csv", [(dropped["id"], "删", "", "wrong word")])
        write_sheet(sheets / "vocab-n3.csv", [(e["id"], "ok", "", "") for e in n3[:5]])

        expected = dict(original)
        try:
            expected["n5"] = expect_fixed(original["n5"], vocab["id"], v_old, N5_JSON, in_list=True)
            expected["n1"] = expect_fixed(original["n1"], escaped["id"], e_old, N1_JSON, in_list=True)
            expected["passages"] = expect_fixed(original["passages"], passage["id"], p_old, P_JSON, in_list=False)
            expected["n4"] = expect_dropped(original["n4"], dropped["id"])
        except AssertionError as exc:
            failures.append(f"could not build the expected text — the fixture is wrong, fix it first: {exc}")
        for n in sorted(TOUCHED):
            if expected[n] == original[n]:
                failures.append(f"expected {n}.json equals the original — the test would pass on a no-op")
        if '\\"' not in original["n1"]:
            failures.append("n1.json holds no `\\\"` escape any more, so writing it back proves nothing "
                            "about escapes already in a file — fix an entry of a file that has one")

        # 1. The default is a dry run: it names every planned change and writes nothing. n2 cannot
        #    round-trip, but nothing touches it, so nothing is refused.
        out, raised = run(importer, [str(sheets)], res, blocklist)
        if raised:
            failures.append(f"the dry run raised {raised!r}")
        for want in (f"FIX  n5 {vocab['id']} meanings.en", f"FIX  n1 {escaped['id']} meanings.en",
                     f"FIX  passages {passage['id']} meanings.en", f"DROP n4 {dropped['id']}",
                     f"SKIP n5 {backslashed['id']}: correction refused: en carries a backslash",
                     "(dry run — nothing written"):
            if want not in out:
                failures.append(f"the dry run did not print {want!r}")
        if "REFUSED" in out:
            failures.append("the dry run printed REFUSED, though every touched file here round-trips and "
                            f"the one that does not (n2) is untouched: {out[out.index('REFUSED'):][:300]!r}")
        for n in NAMES:
            if (res / f"{n}.json").read_text(encoding="utf-8") != original[n]:
                failures.append(f"the dry run changed {n}.json")
        if blocklist.read_text(encoding="utf-8") != original_blocklist:
            failures.append("the dry run changed the blocklist")

        # 2. --apply: the corrected files differ from the original by exactly the corrected lines,
        #    in the hand-written JSON; every other file — the OK-only n3 and the unreproducible n2
        #    among them — is byte for byte the same and was never written at all.
        stamps = {n: written_stamp(res / f"{n}.json") for n in NAMES}
        out, raised = run(importer, [str(sheets), "--apply"], res, blocklist)
        if raised:
            failures.append(f"--apply raised {raised!r}; it printed:\n{out[-600:]}")
        for n in NAMES:
            written = (res / f"{n}.json").read_text(encoding="utf-8")
            if written != expected[n]:
                failures.append(describe(n, original[n], written, expected[n]))
            rewritten = written_stamp(res / f"{n}.json") != stamps[n]
            if n in TOUCHED and not rewritten:
                failures.append(f"--apply did not write {n}.json, which a change touched")
            if n not in TOUCHED and rewritten:
                failures.append(f"--apply rewrote {n}.json, which no change touched — same bytes or not, "
                                "writing every file is what stops on a file CorpusFile cannot reproduce "
                                "half way through a run")
        # What the reviewer typed is what reads back: json, not the writer, is the judge here, so a
        # hand-written form above that is wrong the same way as the writer cannot pass.
        for n, rid, want in (("n5", vocab["id"], [N5_NEW]), ("n1", escaped["id"], [N1_NEW]),
                             ("passages", passage["id"], P_NEW)):
            try:
                got = next(e for e in json.loads((res / f"{n}.json").read_text(encoding="utf-8"))
                           if e["id"] == rid)["meanings"]["en"]
            except (ValueError, StopIteration) as exc:
                failures.append(f"{n}.json does not read back after --apply ({exc!r})")
                continue
            if got != want:
                failures.append(f"{n}.json {rid} meanings.en reads back as {got!r}; the reviewer wrote {want!r}")
        want_blocklist = original_blocklist + "# native review import\n" + dropped["kana"] + "\n"
        if blocklist.read_text(encoding="utf-8") != want_blocklist:
            failures.append(f"the blocklist did not gain exactly the dropped kana {dropped['kana']!r}")

        # 3. A TOUCHED file --apply would have to reformat stops the whole run before ANY file is
        #    written. n2 (indent=3) now gets a fix; the n5 fix lists first and must not land either.
        restore(original)
        write_sheet(sheets / "vocab-n2.csv", [(n2[0]["id"], "fix", "en: reviewed", "")])
        failures += refused_run(
            importer, "a fix in n2.json", sheets, res, blocklist,
            f"REFUSED: {res / 'n2.json'} cannot be written back byte for byte (corpus_io.CorpusFile), "
            "so writing would reformat the whole file.", original, original_blocklist)

        # 4. The same when the file's ONLY change is a drop: n4 at indent=3, holding nothing but a 删
        #    row, beside an n5 fix that must not land. The check covers every file a change lands
        #    in, not only the files a fix names.
        drop_only = dict(original)
        drop_only["n4"] = json.dumps(n4, ensure_ascii=False, indent=3) + "\n"
        restore(drop_only)
        drop_sheets = tmp / "work" / "drop-only"
        write_sheet(drop_sheets / "vocab-n5.csv", [(vocab["id"], "fix", "en: reviewed", "")])
        write_sheet(drop_sheets / "vocab-n4.csv", [(dropped["id"], "删", "", "")])
        failures += refused_run(
            importer, "only a drop in n4.json", drop_sheets, res, blocklist,
            f"REFUSED: {res / 'n4.json'} cannot be written back byte for byte (corpus_io.CorpusFile), "
            "so writing would reformat the whole file.", drop_only, original_blocklist)

        lost = [str(p.relative_to(mirror)) for p in defaults if digest(p) != defaults_before[p]]
        if lost:
            failures.append(f"the importer wrote its own default paths {lost} in the scratch mirror — a "
                            "`resources=` or `blocklist=` argument is lost on the way down, and only the "
                            "mirror kept that write off the real checkout")

    moved = [str(p) for p in real if digest(p) != real_before[p]]
    if moved:
        failures.append(f"THE REAL FILES CHANGED: {moved} — read `git diff` on them before restoring: "
                        "`git checkout --` would also throw away any uncommitted corpus work there")

    if failures:
        print("\n".join(f"FAIL  {f}" for f in failures))
        return 1
    print(f"ok — --apply changed one line each of n5.json ({vocab['id']}, an escaped quote), n1.json "
          f"({escaped['id']}, a non-BMP character and a quote, its existing escapes kept) and "
          f"passages.json ({passage['id']}, a raw U+2028, no final newline kept), and only "
          f"{dropped['id']}'s lines of n4.json; a backslash correction was refused; n3 and the "
          "unreproducible n2 untouched and unwritten; the dry run wrote nothing; a touched file that "
          "cannot round-trip — through a fix or a drop alone — is REFUSED in the dry run and stops "
          "--apply before any write; run from a scratch mirror, the real corpus untouched")
    return 0


if __name__ == "__main__":
    sys.exit(main())
