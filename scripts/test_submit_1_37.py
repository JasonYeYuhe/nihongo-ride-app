#!/usr/bin/env python3
"""`submit_1_37.py`'s own guards must fire, each against a planted defect, with a control that passes.

WHY THIS EXISTS. 1.37's round-1 review mutated the guards that tie What's New and the review notes
to the corpus (`corpus_copy_problems`, `_token_reading`) and found that nothing ran them except the
owner's `--dry-run`: with a check deleted and its defect planted, the script went straight on. The
same review added three guards (every one of the 12 corrections differs from 1.36's corpus; each
quoted word sits next to its own kana; the frozen list is byte-identical to `fdb2b5f`), and a guard
nobody has watched fail is a comment.

WHY IT DOES NOT READ THE LIVE TREE. `submit_1_37.py` checks the tree it runs from at import, and
the next release moves `release_numbers` to its own manifest — so importing it against the live
tree would turn this gate red forever the day 1.37 ships. Instead `release_numbers` is stubbed and
pointed at a throwaway git repository built from pinned commits that never move: the corpus at
`24684c2` (1.36's build commit, the baseline) committed, and the corpus, manifest and instrument-1b
records at `3c091ae` (release/v1.37 with both correction batches, the tree the copy was written
against) in its working tree. The figures `numbers()` would measure are typed here by hand (18
corrected, 7 withheld, pool 5,935 → 5,928, from the v1.37 manifest's counts and 3c091ae's message),
so no expected value comes from the code under test.

    python3 scripts/test_submit_1_37.py
"""
import contextlib
import copy
import importlib.util
import io
import json
import os
import re
import subprocess
import sys
import tempfile
import types
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
REPO = SCRIPTS.parent
sys.path.insert(0, str(SCRIPTS))

BASELINE = "24684c2"          # 1.36's build commit
WRITTEN_AGAINST = "3c091ae"   # the release/v1.37 commit submit_1_37.py's copy was written against
FROZEN_AT = "fdb2b5f"
RES = "Sources/VocabKit/Resources"
CORPUS_FILES = ("n1.json", "n2.json", "n3.json", "n4.json", "n5.json", "dictation-exclusions.json")
MANIFEST = "docs/measurements/v137-reading-manifest.json"
# Typed, not measured: the v1.37 manifest's counts and 3c091ae's message.
NUMBERS = {"correctedThisRelease": 18, "withheldThisRelease": 7,
           "dictationPoolBefore": 5935, "dictationPool": 5928}
# The seven ids 3c091ae withholds (its manifest's decisions), typed.
SEVEN = {"n1-b1418", "n2-b511", "n1-b678", "n2-g300", "n2-b029", "n2-b1064", "n4-b151"}
RECORDS = ("docs/measurements/v137-dictation-remeasure.json",
           "docs/measurements/v137-dictation-remeasure-ichinichi.json")
# Never the owner's real contact: asc_release reads it at import unless this is set.
FAKE_CONTACT = json.dumps({"contactFirstName": "Test", "contactLastName": "Fixture",
                           "contactPhone": "+00 0000", "contactEmail": "fixture@example.invalid"})


def git(cwd, *args, check=True):
    return subprocess.run(["git", "-c", "user.name=fixture", "-c", "user.email=fixture@invalid",
                           "-c", "commit.gpgsign=false", *args],
                          cwd=cwd, capture_output=True, text=True, check=check)


def show(ref, path):
    return git(REPO, "show", f"{ref}:{path}").stdout


def build_fixture_repo(root):
    """A git repo whose HEAD holds BASELINE's corpus and whose working tree holds
    WRITTEN_AGAINST's corpus and manifest. Returns HEAD's sha (the stub BASELINE_REF)."""
    git(root, "init", "-q")
    for name in CORPUS_FILES:
        (root / RES).mkdir(parents=True, exist_ok=True)
        (root / RES / name).write_text(show(BASELINE, f"{RES}/{name}"), encoding="utf-8")
    git(root, "add", "-A")
    git(root, "commit", "-q", "-m", "baseline")
    sha = git(root, "rev-parse", "HEAD").stdout.strip()
    for name in CORPUS_FILES:
        (root / RES / name).write_text(show(WRITTEN_AGAINST, f"{RES}/{name}"), encoding="utf-8")
    (root / MANIFEST).parent.mkdir(parents=True, exist_ok=True)
    for path in (MANIFEST, *RECORDS):
        (root / path).write_text(show(WRITTEN_AGAINST, path), encoding="utf-8")
    return sha


def load_submit(root, baseline_sha, numbers=None, source=None):
    """Import submit_1_37.py (or `source`, an edited copy of it) with `release_numbers` stubbed onto
    the fixture repo, its numbers() returning `numbers` (default NUMBERS).

    Returns (module, None), or (None, the SystemExit its import-time guards raised).
    """
    figures = dict(NUMBERS if numbers is None else numbers)
    stub = types.ModuleType("release_numbers")
    stub.BASELINE_REF = baseline_sha
    stub.CORPUS_MANIFEST = MANIFEST
    stub.REPO = root
    stub.RESOURCES = root / RES
    stub.numbers = lambda: dict(figures)
    saved = sys.modules.get("release_numbers")
    sys.modules["release_numbers"] = stub
    os.environ["NIHONGO_ASC_CONTACT"] = FAKE_CONTACT
    try:
        spec = importlib.util.spec_from_file_location("submit_1_37_under_test",
                                                      source or SCRIPTS / "submit_1_37.py")
        module = importlib.util.module_from_spec(spec)
        try:
            with contextlib.redirect_stdout(io.StringIO()):
                spec.loader.exec_module(module)
        except SystemExit as exc:
            return None, exc
        return module, None
    finally:
        if saved is None:
            sys.modules.pop("release_numbers", None)
        else:
            sys.modules["release_numbers"] = saved


def rewrite_entry(root, entry_id, change):
    """Apply `change(entry)` to one entry of the fixture's working-tree corpus, in place."""
    for name in CORPUS_FILES[:5]:
        path = root / RES / name
        entries = json.loads(path.read_text(encoding="utf-8"))
        for e in entries:
            if e["id"] == entry_id:
                change(e)
                path.write_text(json.dumps(entries, ensure_ascii=False), encoding="utf-8")
                return
    raise AssertionError(f"{entry_id} not in the fixture corpus")


def expect(problems, name, got, *needles):
    """`got` (a list of problems) must be non-empty and mention every needle."""
    text = "\n".join(got)
    if not got or any(n not in text for n in needles):
        problems.append(f"{name}: expected a refusal naming {needles}, got {got!r}")
    else:
        print(f"  refuses: {name}")


# --- the corpus guard ------------------------------------------------------------------------

def test_corpus_guard(mod, root, baseline_sha, problems):
    """`corpus_copy_problems`: the fixture passes, and every planted defect is named."""
    manifest = json.loads((root / MANIFEST).read_text(encoding="utf-8"))
    entries = mod._entries_by_id()
    baseline = mod._baseline_entries_by_id()
    withheld, released = mod._pool_moves()
    counts = manifest["counts"]

    def run(m_entries=None, ents=None, base=None, fixed=NUMBERS["correctedThisRelease"], w=None,
            r=None, c=None):
        return mod.corpus_copy_problems(
            m_entries if m_entries is not None else manifest["entries"],
            ents if ents is not None else entries, base if base is not None else baseline,
            fixed, w if w is not None else withheld, r if r is not None else released,
            c if c is not None else counts)

    control = run()
    print(f"  control: the tree the copy was written against -> {control or 'clean'}")
    if control:
        problems.append(f"corpus guard rejects the tree the copy was written against: {control}")
    if set(withheld) != SEVEN or released:
        problems.append(f"the fixture's pool moves are {sorted(withheld)} / {sorted(released)}, "
                        f"not the seven withholdings {WRITTEN_AGAINST} made — the fixture is wrong")

    def with_entry(entry_id, change):
        out = copy.deepcopy(entries)
        change(out[entry_id])
        return out

    # P1: a quoted entry's token reverted, its exKana left corrected (review-r1 mutation P1/P5).
    def p1(e):
        e["exTokens"] = [[s, "いち" if s == "一" else r] for s, r in e["exTokens"]]
    expect(problems, "P1 a quoted entry's token reverted (n2-b511 一 いっ -> いち)",
           run(ents=with_entry("n2-b511", p1)), "n2-b511", "tokens read 一週間")

    # P3: the count of withheld ids kept at 2, the ids swapped (mutation P3/P4).
    expect(problems, "P3 the withheld ids swapped, the count kept",
           run(w=(SEVEN - {"n2-b511"}) | {"n2-b277"}, r={"n2-b511"}), "n2-b277",
           "returned to the dictation pool")

    # P2: one returned to the pool.
    expect(problems, "P2 a withheld sentence returned to the pool",
           run(w=SEVEN - {"n2-b511"}, r={"n2-b511"}), "n2-b511")

    # submit-2: an UNQUOTED correction reverted to 1.36's text, whole and token-only.
    expect(problems, "submit-2 an unquoted correction reverted whole (n3-k061)",
           run(ents=with_entry("n3-k061", lambda e: e.update(
               exKana=baseline["n3-k061"]["exKana"], exTokens=baseline["n3-k061"]["exTokens"]))),
           "n3-k061's exKana is the same as at", "n3-k061's exTokens is the same as at")
    expect(problems, "submit-2 an unquoted correction's tokens reverted only (n5-b105)",
           run(ents=with_entry("n5-b105", lambda e: e.update(
               exTokens=baseline["n5-b105"]["exTokens"]))),
           "n5-b105's exTokens is the same as at")

    # submit-2: an entry flipped to declined still counted as corrected.
    flipped = copy.deepcopy(manifest["entries"])
    next(e for e in flipped if e["id"] == "n4-g189")["disposition"] = "declined"
    expect(problems, "submit-2 a manifest entry's disposition flipped to declined",
           run(m_entries=flipped), "n4-g189's manifest disposition is 'declined'")

    # The manifest names different entries.
    other = copy.deepcopy(manifest["entries"])
    other[0] = dict(other[0], id="n5-g010")
    expect(problems, "the manifest declares a different entry", run(m_entries=other), "n5-g010")

    expect(problems, "correctedThisRelease is not 18", run(fixed=17), "correctedThisRelease is 17")

    # r2-submit-1: a PARTIAL revert still differs from 1.36. n2-b034 corrects 一 いち -> ひと and
    # 中 ちゅう -> じゅう; put only 中 back, in exKana and its token.
    def only_chuu_back(e):
        e["exKana"] = e["exKana"].replace("ひとばんじゅう", "ひとばんちゅう")
        e["exTokens"] = [[t, "ちゅう" if t == "中" else r] for t, r in e["exTokens"]]
    expect(problems, "r2-submit-1 a partial revert (n2-b034, only 中 back to ちゅう)",
           run(ents=with_entry("n2-b034", only_chuu_back)),
           "n2-b034's exKana is", "not the manifest's corrected")
    # …and the same in the tokens only, exKana left corrected.
    expect(problems, "r2-submit-1 a partial token-only revert (n2-b034 中 ちゅう)",
           run(ents=with_entry("n2-b034", lambda e: e.update(exTokens=[
               [t, "ちゅう" if t == "中" else r] for t, r in e["exTokens"]]))),
           "n2-b034's tokens do not contain the manifest's corrected run")
    # …and a third reading, neither 1.36's nor the correction (n3-k061 十 じっ).
    def third_reading(e):
        e["exKana"] = e["exKana"].replace("じゅっぱーせんと", "じっぱーせんと")
        e["exTokens"] = [[t, "じっ" if t == "十" else r] for t, r in e["exTokens"]]
    expect(problems, "r2-submit-1 a third reading (n3-k061 十 じっ)",
           run(ents=with_entry("n3-k061", third_reading)), "n3-k061's exKana is",
           "not the manifest's corrected")

    # r2-mutation-4: the 7 against the manifest's count, and WITHHELD_IDS inside NAMED_IDS.
    expect(problems, "r2-mutation-4 the manifest's withheldFromDictation drifted to 6",
           run(c=dict(counts, withheldFromDictation=6)), "withheldFromDictation is 6")
    saved_ids = list(mod.WITHHELD_IDS)
    try:
        mod.WITHHELD_IDS = saved_ids + ["n5-g010"]
        expect(problems, "r2-mutation-4 a withheld id that is not a correction (n5-g010)",
               run(w=set(withheld) | {"n5-g010"}), "are not all corrections")
    finally:
        mod.WITHHELD_IDS = saved_ids

    # A second-batch correction reverted (n4-b151 一日 back to ついたち).
    expect(problems, "submit-2 a second-batch correction reverted (n4-b151)",
           run(ents=with_entry("n4-b151", lambda e: e.update(
               exKana=baseline["n4-b151"]["exKana"], exTokens=baseline["n4-b151"]["exTokens"]))),
           "n4-b151's exKana is the same as at")


def test_withheld_reasons(mod, root, problems):
    """`withheld_reason_problems`: the reason sentence's two halves held to the 1b records."""
    verdicts = json.loads((root / RECORDS[0]).read_text(encoding="utf-8"))["verdicts"]
    keep = json.loads((root / RECORDS[1]).read_text(encoding="utf-8"))["keep"]
    entries, baseline = mod._entries_by_id(), mod._baseline_entries_by_id()
    # Typed: the four the voice is proven to say ついたち for, the three 1b is silent on.
    if sorted(mod.WITHHELD_REASONS["says the old reading"]) != \
            ["n2-b029", "n2-b1064", "n2-g300", "n4-b151"] or \
            sorted(mod.WITHHELD_REASONS["not confirmed"]) != ["n1-b1418", "n1-b678", "n2-b511"]:
        problems.append(f"WITHHELD_REASONS is {mod.WITHHELD_REASONS}, not the 4 + 3 the manifest "
                        "decided")
    control = mod.withheld_reason_problems(verdicts, keep, entries, baseline)
    print(f"  control: the records at {WRITTEN_AGAINST} -> {control or 'clean'}")
    if control:
        problems.append(f"the reason guard rejects the records the copy was written against: {control}")

    def with_verdict(entry_id, verdict):
        return dict(verdicts, **{entry_id: dict(verdicts[entry_id], verdict=verdict)})
    expect(problems, "a 'not confirmed' sentence that 1b actually released",
           mod.withheld_reason_problems(with_verdict("n1-b678", "RELEASE"), keep, entries, baseline),
           "n1-b678", "not SILENT")
    expect(problems, "a 'says the old reading' sentence that 1b was silent on",
           mod.withheld_reason_problems(with_verdict("n2-g300", "SILENT"), keep, entries, baseline),
           "n2-g300")
    # One plant per clause of the KEEP-row check, each tripping that clause alone.
    def row(**change):
        return [dict(r, **change) if r["id"] == "n4-b151" else r for r in keep]
    for name, planted in (
            ("the voice said neither the old nor the new reading (いちじつ)", row(kyoko=["いちじつ"])),
            ("the voice said both the old and the new reading", row(kyoko=["ついたち", "いちにち"])),
            ("the KEEP record was taken on another corpus reading", row(corpus="ついたち"))):
        expect(problems, f"a KEEP row where {name}",
               mod.withheld_reason_problems(verdicts, planted, entries, baseline), "n4-b151",
               "is not what 1b measured")
    saved = copy.deepcopy(mod.WITHHELD_REASONS)
    try:
        mod.WITHHELD_REASONS["not confirmed"].remove("n1-b678")
        expect(problems, "a withheld id with no reason",
               mod.withheld_reason_problems(verdicts, keep, entries, baseline), "WITHHELD_REASONS covers")
    finally:
        mod.WITHHELD_REASONS.clear()
        mod.WITHHELD_REASONS.update(saved)


def test_import_wiring(root, baseline_sha, problems):
    """The import-time call passes the right things: a revert planted in the fixture's corpus
    stops the import itself, for a quoted entry and for an unquoted one."""
    for entry_id, field in (("n3-k061", "exKana"), ("n4-b186", "exTokens")):
        n_json = {name: (root / RES / name).read_text(encoding="utf-8") for name in CORPUS_FILES[:5]}
        before = None
        for name in CORPUS_FILES[:5]:
            for e in json.loads(show(BASELINE, f"{RES}/{name}")):
                if e["id"] == entry_id:
                    before = e[field]
        rewrite_entry(root, entry_id, lambda e: e.update({field: before}))
        try:
            mod, exited = load_submit(root, baseline_sha)
        finally:
            for name, text in n_json.items():
                (root / RES / name).write_text(text, encoding="utf-8")
        named = exited is not None and entry_id in str(exited)
        print(f"  import with {entry_id}'s {field} reverted -> "
              f"{'REFUSED by name' if named else 'NOT REFUSED'}")
        if not named:
            problems.append(f"importing submit_1_37 with {entry_id}'s {field} reverted to "
                            f"{BASELINE} did not refuse by name: {exited!r}")


def test_reason_wiring(root, baseline_sha, problems):
    """The import-time call reads the 1b records: n1-b678 planted as RELEASE stops the import."""
    path = root / RECORDS[0]
    original = path.read_text(encoding="utf-8")
    record = json.loads(original)
    record["verdicts"]["n1-b678"]["verdict"] = "RELEASE"
    path.write_text(json.dumps(record, ensure_ascii=False), encoding="utf-8")
    try:
        _, exited = load_submit(root, baseline_sha)
    finally:
        path.write_text(original, encoding="utf-8")
    named = exited is not None and "n1-b678" in str(exited) and "not SILENT" in str(exited)
    print(f"  import with n1-b678's 1b verdict planted as RELEASE -> "
          f"{'REFUSED by name' if named else 'NOT REFUSED'}")
    if not named:
        problems.append(f"importing submit_1_37 with n1-b678 RELEASE in {RECORDS[0]} did not refuse "
                        f"by name: {exited!r}")


def test_quote_and_count_wiring(root, baseline_sha, problems):
    """The import-time exits for the quote guard and for the 7: an edited copy of the script with one
    reading swapped (or a word added) must not import, nor the real script on a withheld count of 6
    from release_numbers or from the manifest."""
    src = (SCRIPTS / "submit_1_37.py").read_text(encoding="utf-8")
    edits = (
        ("one reading swapped in What's New en", "and 一晩 ひとばん.", "and 一晩 いちばん."),
        ("a word that is not an example added", "and 一晩 ひとばん.", "and 一晩 ひとばん, 十ページ じゅっぺーじ."),
    )
    with tempfile.TemporaryDirectory(prefix="submit137_edited_") as tmp:
        for name, old, new in edits:
            if src.count(old) != 1:
                problems.append(f"quote wiring: the anchor {old!r} is not in submit_1_37.py once")
                continue
            edited = Path(tmp) / "submit_1_37.py"
            edited.write_text(src.replace(old, new), encoding="utf-8")
            _, exited = load_submit(root, baseline_sha, source=edited)
            named = exited is not None and "the copy does not quote what EXAMPLES holds" in str(exited)
            print(f"  import with {name} -> {'REFUSED by name' if named else 'NOT REFUSED'}")
            if not named:
                problems.append(f"importing submit_1_37 with {name} did not refuse by name: {exited!r}")

    _, exited = load_submit(root, baseline_sha, numbers=dict(NUMBERS, withheldThisRelease=6))
    named = exited is not None and "withheldThisRelease is 6" in str(exited)
    print(f"  import with withheldThisRelease 6 -> {'REFUSED by name' if named else 'NOT REFUSED'}")
    if not named:
        problems.append(f"importing submit_1_37 with withheldThisRelease 6 did not refuse: {exited!r}")

    path = root / MANIFEST
    original = path.read_text(encoding="utf-8")
    manifest = json.loads(original)
    manifest["counts"]["withheldFromDictation"] = 6
    path.write_text(json.dumps(manifest, ensure_ascii=False), encoding="utf-8")
    try:
        _, exited = load_submit(root, baseline_sha)
    finally:
        path.write_text(original, encoding="utf-8")
    named = exited is not None and "withheldFromDictation is 6" in str(exited)
    print(f"  import with the manifest's withheldFromDictation 6 -> "
          f"{'REFUSED by name' if named else 'NOT REFUSED'}")
    if not named:
        problems.append(f"importing submit_1_37 with the manifest's withheldFromDictation 6 did not "
                        f"refuse: {exited!r}")


def test_token_reading(mod, problems):
    """`_token_reading`, on hand-written tokens."""
    toks = [["この", "この"], ["車", "くるま"], ["は", "は"], ["時速", "じそく"],
            ["六十", "ろくじゅっ"], ["キロ", "きろ"], ["で", "で"]]
    cases = [
        ("a word spelled by two tokens", toks, "六十キロ", "ろくじゅっきろ"),
        ("a word that is one token", toks, "時速", "じそく"),
        ("a word no run of tokens spells", toks, "一週間", None),
        # mutation P6: a token whose surface CONTAINS the word is not a run that spells it
        ("a surface that contains the word but does not start a run at it",
         [["時速六十", "じそくろくじゅう"], ["キロ", "きろ"]], "六十キロ", None),
        ("a run that overshoots the word", [["六十キロで", "ろくじゅっきろで"]], "六十キロ", None),
        ("no tokens at all", None, "六十キロ", None),
        ("the first matching run wins", [["一", "ひと"], ["晩", "ばん"], ["一晩", "いちばん"]],
         "一晩", "ひとばん"),
    ]
    for name, tokens, word, want in cases:
        got = mod._token_reading(tokens, word)
        if got != want:
            problems.append(f"_token_reading, {name}: got {got!r}, want {want!r}")
        else:
            print(f"  _token_reading: {name} -> {got!r}")


# --- the quotes ------------------------------------------------------------------------------

def test_quotes(mod, problems):
    """Each quoted word next to its own kana, per locale; a swap of two readings is refused."""
    control = mod.quote_problems(mod.WHATS_NEW, mod.REVIEW_NOTES)
    print(f"  control: the copy as written -> {control or 'clean'}")
    if control:
        problems.append(f"the quote guard rejects the copy as written: {control}")

    def swapped(text, a, b):
        return text.replace(a, "\0").replace(b, a).replace("\0", b)

    # Every adjacent pair of EXAMPLES swapped in turn, so a check that stopped early cannot pass.
    pairs = list(mod.EXAMPLES.values())
    for loc in mod.WHATS_NEW:
        for (w1, k1), (w2, k2) in zip(pairs, pairs[1:]):
            bad = dict(mod.WHATS_NEW, **{loc: swapped(mod.WHATS_NEW[loc], k1, k2)})
            # Both readings still appear in the text, so the old any-where check passed this.
            assert k1 in bad[loc] and k2 in bad[loc] and bad[loc] != mod.WHATS_NEW[loc]
            expect(problems, f"What's New {loc} with {w1} and {w2}'s readings swapped",
                   mod.quote_problems(bad, mod.REVIEW_NOTES), f"{loc}: {w1} is not quoted next to",
                   f"{loc}: {w2} is not quoted next to")
    quoted = pairs[:mod.NOTES_EXAMPLES]
    for (w1, k1), (w2, k2) in zip(quoted, quoted[1:]):
        bad = swapped(mod.REVIEW_NOTES, k1, k2)
        assert bad != mod.REVIEW_NOTES
        expect(problems, f"the review notes with {w1} and {w2}'s readings swapped",
               mod.quote_problems(mod.WHATS_NEW, bad), f"review notes: {w1}", f"review notes: {w2}")

    # r2-submit-2: the copy quotes nothing EXAMPLES does not hold to the corpus. n5-g010's 十ページ
    # was recorded and NOT corrected; 十分 is n3-b020's, which is not a v1.37 correction either.
    added = {
        "en-US": ("and 一晩 ひとばん.", "and 一晩 ひとばん, and 十ページ じゅっぺーじ."),
        "zh-Hans": ("「一晩」读作 ひとばん。", "「一晩」读作 ひとばん,「十ページ」读作 じゅっぺーじ。"),
        "ja": ("「一晩」ひとばん)", "「一晩」ひとばん、「十分」じゅっぷん)"),
    }
    for loc, (old, new) in added.items():
        assert mod.WHATS_NEW[loc].count(old) == 1, (loc, old)
        bad = dict(mod.WHATS_NEW, **{loc: mod.WHATS_NEW[loc].replace(old, new)})
        expect(problems, f"r2-submit-2 What's New {loc} quoting a word that is not an example",
               mod.quote_problems(bad, mod.REVIEW_NOTES), f"What's New {loc} quotes",
               "十ページ" if loc != "ja" else "十分")
    zh_unbracketed = mod.WHATS_NEW["zh-Hans"].replace("ひとばん。", "ひとばん,十ページ じゅっぺーじ。")
    expect(problems, "r2-submit-2 zh quoting kana outside 「」",
           mod.quote_problems(dict(mod.WHATS_NEW, **{"zh-Hans": zh_unbracketed}), mod.REVIEW_NOTES),
           "What's New zh-Hans quotes", "じゅっぺーじ")
    notes_added = mod.REVIEW_NOTES.replace("一週間 いっしゅうかん)", "一週間 いっしゅうかん, 十ページ じゅっぺーじ)")
    assert notes_added != mod.REVIEW_NOTES
    expect(problems, "r2-submit-2 the review notes quoting a word that is not an example",
           mod.quote_problems(mod.WHATS_NEW, notes_added), "review notes quote", "十ページ")
    expect(problems, "a locale with no quote forms",
           mod.quote_problems(dict(mod.WHATS_NEW, **{"fr-FR": "x"}), mod.REVIEW_NOTES), "fr-FR")


def test_mode_labels(mod, problems):
    """The copy names modes the way the menu capsule does (`GameMode.shortLabel` at the commit the
    copy was written against), and the withheld sentences' mode is named in every locale."""
    before = len(problems)
    src = show(WRITTEN_AGAINST, "Sources/GameCore/GameSession.swift")
    body = src.split("public func shortLabel(zh: Bool) -> String {", 1)[-1].split("\n    }\n", 1)[0]
    labels = {case: (zh, en) for case, zh, en in
              re.findall(r'case \.(\w+):\s*return zh \? "([^"]+)" : "([^"]+)"', body)}
    if set(labels) != {"journey", "timeAttack", "practice", "conjugation", "sentence", "dictation"}:
        problems.append(f"could not read GameMode.shortLabel at {WRITTEN_AGAINST}: {labels}")
        return
    en_labels = {en for _, en in labels.values()}
    zh_labels = {zh for zh, _ in labels.values()}
    en, zh, ja = mod.WHATS_NEW["en-US"], mod.WHATS_NEW["zh-Hans"], mod.WHATS_NEW["ja"]
    named = {
        "en-US": re.findall(r"\b([A-Z][A-Za-z]+) mode\b", en),
        "ja": re.findall(r"「([A-Za-z]+)」", ja),
        "zh-Hans": re.findall(r"「([^」]+)」模式", zh),
    }
    for loc, found in named.items():
        allowed = zh_labels if loc == "zh-Hans" else en_labels
        stray = [f for f in found if f not in allowed]
        if not found or stray:
            problems.append(f"What's New {loc} names modes {found}; {stray or 'none'} is not a "
                            f"capsule label ({sorted(allowed)})")
    dictation_zh, dictation_en = labels["dictation"]
    for loc, text, want in (("en-US", en, f"{dictation_en} mode"), ("ja", ja, f"「{dictation_en}」"),
                            ("zh-Hans", zh, dictation_zh)):
        if want not in text:
            problems.append(f"What's New {loc} does not name the dictation capsule as {want!r}")
    if len(problems) == before:
        print(f"  the copy names {named} — all capsule labels; dictation is "
              f"{dictation_en!r} / {dictation_zh!r}")


def test_preflight_and_lengths(mod, problems):
    """The configuration passes asc_release's preflight, as --metadata would run it."""
    from asc_release import Release
    release = Release(version=mod.VERSION, targets=mod.TARGETS, whats_new=mod.WHATS_NEW,
                      description_edits=mod.DESCRIPTION_EDITS, review_notes=mod.REVIEW_NOTES,
                      iap=None, contact=json.loads(FAKE_CONTACT), numbers=dict(NUMBERS))
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            release.preflight()
        print(f"  preflight: OK ({', '.join(f'{k} {len(v)}' for k, v in mod.WHATS_NEW.items())} "
              f"chars; notes {len(mod.REVIEW_NOTES)})")
    except SystemExit as exc:
        problems.append(f"submit_1_37's configuration fails preflight: {exc}")


# --- the frozen list -------------------------------------------------------------------------

def test_frozen(mod, problems):
    """`frozen_problems` on a fixture repo, one planted defect each, and the real list's paths."""
    # Every named path exists at the pinned commit. Not HEAD: a later release may change these
    # files once the window closes, and this test must not stop it; the script checks HEAD itself.
    missing = [p for p in mod.FROZEN_PATHS
               if git(REPO, "cat-file", "-e", f"{mod.FROZEN_REF}:{p}", check=False).returncode]
    print(f"  FROZEN_PATHS at {mod.FROZEN_REF}: {len(mod.FROZEN_PATHS) - len(missing)} of "
          f"{len(mod.FROZEN_PATHS)} exist")
    if missing:
        problems.append(f"FROZEN_PATHS names paths that do not exist at {mod.FROZEN_REF}: {missing}")
    # The list itself, typed by hand from the brief (common.md, with Theme as the file that holds it):
    # a path dropped from FROZEN_PATHS is a file the guard stops watching.
    typed = {
        "Sources/NihongoRideApp/SettingsView.swift", "Sources/NihongoRideApp/MenuView.swift",
        "Sources/NihongoRideApp/AboutView.swift", "Sources/NihongoRideApp/OnboardingView.swift",
        "Sources/NihongoRideApp/RoadView.swift", "Sources/NihongoRideApp/RouteStore.swift",
        "Sources/NihongoRideApp/NihongoRideApp.swift", "Sources/NihongoRideApp/ScaledFont.swift",
        "Sources/EntitlementKit", "xcode/NihongoRide.storekit",
    }
    if set(mod.FROZEN_PATHS) != typed or len(mod.FROZEN_PATHS) != len(typed):
        problems.append(f"FROZEN_PATHS is not the frozen list: missing "
                        f"{sorted(typed - set(mod.FROZEN_PATHS))}, extra "
                        f"{sorted(set(mod.FROZEN_PATHS) - typed)}")
    if mod.FROZEN_REF != FROZEN_AT:
        problems.append(f"FROZEN_REF is {mod.FROZEN_REF!r}, not 1.35's build commit {FROZEN_AT}")
    theme = show(FROZEN_AT, "Sources/NihongoRideApp/NihongoRideApp.swift")
    if "enum Theme" not in theme or "Sources/NihongoRideApp/NihongoRideApp.swift" not in mod.FROZEN_PATHS:
        problems.append("Theme is not frozen: enum Theme's file is not in FROZEN_PATHS")

    with tempfile.TemporaryDirectory(prefix="frozen_fixture_") as tmp:
        root = Path(tmp)
        git(root, "init", "-q")
        (root / "App").mkdir()
        (root / "Kit").mkdir()
        (root / "App/Road.swift").write_text("road\n")
        (root / "App/Menu.swift").write_text("menu\n")
        (root / "Kit/Store.swift").write_text("store\n")
        (root / "other.txt").write_text("free to change\n")
        git(root, "add", "-A")
        git(root, "commit", "-q", "-m", "frozen")
        ref = git(root, "rev-parse", "HEAD").stdout.strip()
        paths = ["App/Road.swift", "App/Menu.swift", "Kit"]

        def check(name, want_clean, *needles, paths=paths):
            got = mod.frozen_problems(root, ref=ref, paths=paths)
            if want_clean:
                if got:
                    problems.append(f"frozen control ({name}) was refused: {got}")
                else:
                    print(f"  frozen control: {name} -> clean")
            else:
                expect(problems, f"frozen: {name}", got, *needles)

        check("nothing changed", True)
        (root / "other.txt").write_text("changed\n")
        check("a file outside the list changed", True)
        (root / "App/Road.swift").write_text("road, edited\n")
        check("a frozen file edited in the working tree", False, "differs from", "App/Road.swift")
        git(root, "commit", "-q", "-am", "edit")
        check("a frozen file edited and committed", False, "differs from", "App/Road.swift")
        git(root, "reset", "-q", "--hard", ref)
        check("a path that exists nowhere (Theme.swift)", False,
              "App/Theme.swift does not exist at", paths=paths + ["App/Theme.swift"])
        (root / "Kit/Extra.swift").write_text("new\n")
        check("an untracked file under a frozen directory", False, "untracked", "Kit/Extra.swift")
        (root / "Kit/Extra.swift").unlink()
        git(root, "rm", "-q", "App/Menu.swift")
        git(root, "commit", "-q", "-m", "remove")
        check("a frozen file deleted at HEAD", False, "App/Menu.swift does not exist at HEAD")


def test_main_wiring(root, baseline_sha, problems):
    """Run as a script, the frozen check comes before anything else: the fixture repo has no
    fdb2b5f, so the run must stop there, naming the frozen list, and never reach asc_release."""
    import runpy
    import asc_release
    reached = []

    def no_asc(self, method, ep, body=None, allow_empty=False):
        reached.append((method, ep))
        raise AssertionError(f"reached App Store Connect: {method} {ep}")

    original, saved_argv = asc_release.Release.asc, sys.argv
    stub = types.ModuleType("release_numbers")
    stub.BASELINE_REF, stub.CORPUS_MANIFEST = baseline_sha, MANIFEST
    stub.REPO, stub.RESOURCES = root, root / RES
    stub.numbers = lambda: dict(NUMBERS)
    saved_rn = sys.modules.get("release_numbers")
    asc_release.Release.asc = no_asc
    sys.modules["release_numbers"] = stub
    outcome = None
    try:
        for mode in ("--metadata", "--submit", "--dry-run", "(no mode)"):
            sys.argv = (["submit_1_37.py"] if mode == "(no mode)"
                        else ["submit_1_37.py", mode, "--platform=both"])
            try:
                with contextlib.redirect_stdout(io.StringIO()):
                    runpy.run_path(str(SCRIPTS / "submit_1_37.py"), run_name="__main__")
                outcome = "returned"
            except SystemExit as exc:
                outcome = str(exc)
            except AssertionError as exc:
                outcome = str(exc)
            named = "frozen list" in outcome and "does not exist at fdb2b5f" in outcome
            print(f"  {mode:10s} on a tree without fdb2b5f -> "
                  f"{'refused at the frozen list' if named else outcome[:80]}")
            if not named or reached:
                problems.append(f"{mode}: the script did not stop at the frozen list before "
                                f"asc_release ({outcome[:200]!r}; ASC calls {reached})")
    finally:
        asc_release.Release.asc, sys.argv = original, saved_argv
        if saved_rn is None:
            sys.modules.pop("release_numbers", None)
        else:
            sys.modules["release_numbers"] = saved_rn


def main():
    problems = []
    with tempfile.TemporaryDirectory(prefix="submit137_fixture_") as tmp:
        root = Path(tmp)
        baseline_sha = build_fixture_repo(root)
        mod, exited = load_submit(root, baseline_sha)
        if mod is None:
            print(f"FAIL  submit_1_37.py refuses the tree its copy was written against "
                  f"({WRITTEN_AGAINST}):\n{exited}")
            return 1
        print(f"loaded submit_1_37.py against {WRITTEN_AGAINST}'s corpus, baseline {BASELINE}\n")
        print("THE CORPUS GUARD — every planted defect named, the fixture clean")
        test_corpus_guard(mod, root, baseline_sha, problems)
        test_withheld_reasons(mod, root, problems)
        test_import_wiring(root, baseline_sha, problems)
        test_reason_wiring(root, baseline_sha, problems)
        test_quote_and_count_wiring(root, baseline_sha, problems)
        test_token_reading(mod, problems)
        print("\nTHE QUOTES — each word next to its own kana")
        test_quotes(mod, problems)
        print("\nTHE MODE LABELS — the menu capsule's")
        test_mode_labels(mod, problems)
        test_preflight_and_lengths(mod, problems)
        print("\nTHE FROZEN LIST")
        test_frozen(mod, problems)
        test_main_wiring(root, baseline_sha, problems)
    if problems:
        print(f"\n{len(problems)} FAILURE(S):")
        for p in problems:
            print(f"\nFAIL  {p}")
        return 1
    print("\nevery guard in submit_1_37.py refuses its planted defect, and every control passes.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
