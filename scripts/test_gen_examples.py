#!/usr/bin/env python3
"""Unit tests for gen_examples.py: its target gate, and its merge's write.

THE TARGET GATE — the only check that a generated sentence is about the right word. It shipped
as "drop the last character is a stem" applied to EVERY entry, so the noun 学校 became 学 and
「数学を勉強します。」 validated as an example of it. Any sentence containing a common kanji
passed for a large fraction of the corpus, and nothing downstream would notice.

THE MERGE'S WRITE. Until v1.36 `gen` merged a batch by writing the level file back with
`json.dumps(indent=2)` and no final newline, against the shipped indent=1 plus a newline: every
line of n5.json changed for one batch, the v1.26 whole-file rewrite (STATE-2026-08-18). It now
writes through corpus_io.CorpusFile. Proven here on fixture level files in the shipped layout, in
a scratch MIRROR of the repo (scripts/ and Sources/VocabKit/Resources at their usual places, so
the script's module-level ROOT and RES name scratch files; the pattern of
test_import_review_sheets.py), with Gemini replaced by a stub — nothing leaves the machine:

  * the merged entries' bytes change and nothing else does. The expected file is typed out in
    full below, never made by re-serialising parsed data (that is the code under test, and it
    would grade itself); each value's JSON form is typed by hand, one of them with a `\\"`;
  * the other four level files are not written at all (same inode, same mtime);
  * a level file in CRLF, and one in a layout json.dumps cannot reproduce, are each refused
    BEFORE any Gemini call, with their bytes unchanged and a message that says why.

Files are compared as raw bytes, never through read_text, whose universal newlines would
let a CRLF rewrite compare equal.

Run: python3 scripts/test_gen_examples.py
"""
import argparse
import ast
import contextlib
import hashlib
import importlib.util
import inspect
import io
import json
import pathlib
import shutil
import sys
import tempfile
import time
import types

spec = importlib.util.spec_from_file_location("g", pathlib.Path(__file__).with_name("gen_examples.py"))
g = importlib.util.module_from_spec(spec)
sys.argv = ["gen_examples"]
try:
    spec.loader.exec_module(g)
except SystemExit:
    pass

CASES = [
    # (sentence, entry, expected, why)
    ("数学を勉強します。", {"surface": "学校", "kana": "がっこう", "pos": ["n"]}, False,
     "a noun gets no stem: 学校 and 数学 share one kanji and nothing else"),
    ("学校へ行きます。", {"surface": "学校", "kana": "がっこう", "pos": ["n"]}, True,
     "the word itself"),
    ("がっこうへいきます。", {"surface": "学校", "kana": "がっこう", "pos": ["n"]}, True,
     "kana form counts too"),
    ("パンを食べています。", {"surface": "食べる", "kana": "たべる", "pos": ["v"], "vc": "ichidan"}, True,
     "an inflecting verb appears as its stem"),
    ("毎日勉強しています。", {"surface": "勉強する", "kana": "べんきょうする", "pos": ["v"], "vc": "suru"}, True,
     "suru-verbs strip する, not one character"),
    ("車が高いです。", {"surface": "高い", "kana": "たかい", "pos": ["adj-i"]}, True,
     "i-adjectives inflect"),
    ("水を飲みます。", {"surface": "飲み物", "kana": "のみもの", "pos": ["n"]}, False,
     "a noun that merely shares a kanji with the verb in the sentence"),
    ("銀行へ行きます。", {"surface": "行く", "kana": "いく", "pos": ["v"], "vc": "godan_k"}, False,
     "single-character stems are refused: 行 is in 銀行, 旅行, 行事 …"),
    ("学校へ行くつもりだ。", {"surface": "行く", "kana": "いく", "pos": ["v"], "vc": "godan_k"}, True,
     "…so such a word must appear in full"),
]


# ---------------------------------------------------------------------------------------------
# The merge's write.

HERE = pathlib.Path(__file__).resolve().parent
RES_IN_REPO = pathlib.Path("Sources/VocabKit/Resources")
LEVELS = ["n5", "n4", "n3", "n2", "n1"]

# The level files, in the shipped layout: indent=1, non-ASCII raw, a final newline. Raw strings,
# so `\"` is the two characters JSON holds. n5-mizu carries an escaped quote that must survive.
FIXTURE = {
    "n5": r"""[
 {
  "id": "n5-mizu",
  "surface": "水",
  "kana": "みず",
  "pos": [
   "n"
  ],
  "meanings": {
   "en": [
    "water"
   ]
  },
  "exJP": "水を飲みます。",
  "exEN": "I drink \"cold\" water.",
  "exZH": "我喝水。"
 },
 {
  "id": "n5-yama",
  "surface": "山",
  "kana": "やま",
  "pos": [
   "n"
  ],
  "meanings": {
   "en": [
    "mountain"
   ]
  }
 },
 {
  "id": "n5-kawa",
  "surface": "川",
  "kana": "かわ",
  "pos": [
   "n"
  ],
  "meanings": {
   "en": [
    "river"
   ]
  },
  "exJP": "",
  "exEN": "",
  "exZH": ""
 },
 {
  "id": "n5-umi",
  "surface": "海",
  "kana": "うみ",
  "pos": [
   "n"
  ],
  "meanings": {
   "en": [
    "sea"
   ]
  }
 }
]
""",
    "n4": r"""[
 {
  "id": "n4-hon",
  "surface": "本",
  "kana": "ほん",
  "pos": [
   "n"
  ],
  "meanings": {
   "en": [
    "book"
   ]
  },
  "exJP": "本を読みます。",
  "exEN": "I read a book.",
  "exZH": "我看书。"
 },
 {
  "id": "n4-sora",
  "surface": "空",
  "kana": "そら",
  "pos": [
   "n"
  ],
  "meanings": {
   "en": [
    "sky"
   ]
  }
 }
]
""",
    "n3": r"""[
 {
  "id": "n3-kaigi",
  "surface": "会議",
  "kana": "かいぎ",
  "pos": [
   "n"
  ],
  "meanings": {
   "en": [
    "meeting"
   ]
  }
 }
]
""",
    "n2": r"""[
 {
  "id": "n2-keizai",
  "surface": "経済",
  "kana": "けいざい",
  "pos": [
   "n"
  ],
  "meanings": {
   "en": [
    "economy"
   ]
  },
  "exJP": "経済が大きく変わった。",
  "exEN": "The economy changed a lot.",
  "exZH": "经济发生了很大变化。"
 }
]
""",
    "n1": r"""[
 {
  "id": "n1-gaikou",
  "surface": "外交",
  "kana": "がいこう",
  "pos": [
   "n"
  ],
  "meanings": {
   "en": [
    "diplomacy"
   ]
  },
  "exJP": "外交の仕事をしている。",
  "exEN": "I work in diplomacy.",
  "exZH": "我从事外交工作。"
 }
]
""",
}

# What the stub "Gemini" answers for each word it is asked about: (exJP, exEN, exZH).
SENTENCES = {
    "n5-yama": ("山に登りました。", 'We climbed the "big" mountain.', "我们爬了山。"),
    "n5-kawa": ("川で泳ぎます。", "I swim in the river.", "我在河里游泳。"),
    "n5-umi": ("海で遊びました。", "We played at the sea.", "我们在海边玩了。"),
    "n4-sora": ("空がとても青い。", "The sky is very blue.", "天空很蓝。"),
    "n3-kaigi": ("会議は三時に始まる。", "The meeting starts at three.", "会议三点开始。"),
}

# n5.json after `gen n5 --count 2`: n5-yama gains three keys after `meanings` (whose `}` gains a
# comma), n5-kawa's three empty values are filled where they stand, and nothing else moves —
# n5-umi is the third word still waiting and --count 2 does not reach it. Typed out in full.
N5_AFTER = r"""[
 {
  "id": "n5-mizu",
  "surface": "水",
  "kana": "みず",
  "pos": [
   "n"
  ],
  "meanings": {
   "en": [
    "water"
   ]
  },
  "exJP": "水を飲みます。",
  "exEN": "I drink \"cold\" water.",
  "exZH": "我喝水。"
 },
 {
  "id": "n5-yama",
  "surface": "山",
  "kana": "やま",
  "pos": [
   "n"
  ],
  "meanings": {
   "en": [
    "mountain"
   ]
  },
  "exJP": "山に登りました。",
  "exEN": "We climbed the \"big\" mountain.",
  "exZH": "我们爬了山。"
 },
 {
  "id": "n5-kawa",
  "surface": "川",
  "kana": "かわ",
  "pos": [
   "n"
  ],
  "meanings": {
   "en": [
    "river"
   ]
  },
  "exJP": "川で泳ぎます。",
  "exEN": "I swim in the river.",
  "exZH": "我在河里游泳。"
 },
 {
  "id": "n5-umi",
  "surface": "海",
  "kana": "うみ",
  "pos": [
   "n"
  ],
  "meanings": {
   "en": [
    "sea"
   ]
  }
 }
]
"""


def sibling_imports(path):
    """The scripts beside this one that `path` imports, by module name."""
    names = set()
    for node in ast.walk(ast.parse(path.read_text(encoding="utf-8"))):
        if isinstance(node, ast.Import):
            names.update(alias.name.split(".")[0] for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.level == 0 and node.module:
            names.add(node.module.split(".")[0])
    return {name for name in names if (HERE / f"{name}.py").is_file()}


def inside(path, root):
    try:
        pathlib.Path(path).resolve().relative_to(root)
        return True
    except ValueError:
        return False


def read_raw(path):
    """The file's text exactly as its bytes hold it — never read_text, which reads CRLF as LF."""
    return path.read_bytes().decode("utf-8")


def write_raw(path, text):
    path.write_bytes(text.encode("utf-8"))


def stamp(path):
    """What any write changes, even one of the same bytes: CorpusFile.write's replace gives a new
    inode, and any write a new mtime."""
    st = path.stat()
    return st.st_ino, st.st_mtime_ns


def build_mirror(root):
    """root/scripts holding gen_examples and everything beside it that it imports; the fixture
    level files in root/Sources/VocabKit/Resources."""
    (root / "scripts").mkdir(parents=True)
    copied, todo = set(), ["gen_examples"]
    while todo:
        name = todo.pop()
        if name not in copied:
            copied.add(name)
            shutil.copyfile(HERE / f"{name}.py", root / "scripts" / f"{name}.py")
            todo.extend(sibling_imports(HERE / f"{name}.py"))
    (root / RES_IN_REPO).mkdir(parents=True)
    for level in LEVELS:
        write_raw(root / RES_IN_REPO / f"{level}.json", FIXTURE[level])
    return copied


def load_from(root, copied):
    """→ (gen_examples as root/scripts holds it, what of it reaches outside root)."""
    for name in copied | {"gen_examples"}:
        sys.modules.pop(name, None)
    spec = importlib.util.spec_from_file_location("gen_examples", root / "scripts/gen_examples.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    outside = [f"its {attr} is {getattr(module, attr, '<missing>')}" for attr in ("ROOT", "RES")
               if not inside(getattr(module, attr, "<missing>"), root)]
    outside += [f"{name} loaded from {loaded.__file__}" for name, loaded in sorted(sys.modules.items())
                if name != "__main__" and getattr(loaded, "__file__", None) and inside(loaded.__file__, HERE)]
    corpus_io_file = inspect.getfile(module.CorpusFile) if hasattr(module, "CorpusFile") else None
    if corpus_io_file and not inside(corpus_io_file, root):
        outside.append(f"its CorpusFile comes from {corpus_io_file}")
    return module, outside


def stub(module, calls):
    """call_gemini → one JSONL line per `id | surface | kana | gloss` line of the prompt."""
    def fake(prompt):
        calls.append(prompt)
        out = []
        for line in prompt.splitlines():
            parts = [p.strip() for p in line.split("|")]
            if len(parts) == 4 and parts[0] in SENTENCES:
                jp, en, zh = SENTENCES[parts[0]]
                out.append(json.dumps({"id": parts[0], "exJP": jp, "exEN": en, "exZH": zh},
                                      ensure_ascii=False))
        return "\n".join(out)
    module.call_gemini = fake
    module.time = types.SimpleNamespace(sleep=lambda s: None, strftime=time.strftime)


def gen(module, level, count):
    """Run `gen <level> --count <count>` → (stdout, the SystemExit it raised or None)."""
    args = argparse.Namespace(level=level, count=count, chunk=40, retries=0, dry=False, verbose=False)
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        try:
            module.cmd_gen(args)
        except SystemExit as stop:
            return out.getvalue(), stop
    return out.getvalue(), None


def merge_failures():
    failures = []
    real = [HERE.parent / RES_IN_REPO / f"{level}.json" for level in LEVELS]
    real_before = {p: hashlib.sha256(p.read_bytes()).hexdigest() for p in real if p.exists()}

    # The fixtures are what they claim to be — checked with json, not with the code under test.
    for level in LEVELS:
        if json.dumps(json.loads(FIXTURE[level]), ensure_ascii=False, indent=1) + "\n" != FIXTURE[level]:
            failures.append(f"fixture {level} is not in the shipped layout (indent=1 + newline) — fix it first")
    if N5_AFTER == FIXTURE["n5"]:
        failures.append("the expected n5.json equals the fixture — the test would pass on a no-op")
    if failures:
        return failures

    with tempfile.TemporaryDirectory(prefix="gen-examples-merge-") as tmp:
        root = pathlib.Path(tmp).resolve() / "repo"
        module, outside = load_from(root, build_mirror(root))
        if outside:
            return [f"gen_examples loaded from {root} reaches outside it — {'; '.join(outside)} — "
                    "so it was not run"]
        res = root / RES_IN_REPO
        calls = []
        stub(module, calls)

        # 1. The merge changes the merged entries' bytes, and writes no other level file.
        stamps = {level: stamp(res / f"{level}.json") for level in LEVELS}
        out, stop = gen(module, "n5", 2)
        if stop is not None:
            failures.append(f"gen n5 stopped: {stop}; it printed {out[-400:]!r}")
        got = read_raw(res / "n5.json")
        if got != N5_AFTER:
            want_lines, got_lines = N5_AFTER.split("\n"), got.split("\n")
            off = next((i for i, (a, b) in enumerate(zip(want_lines, got_lines)) if a != b),
                       min(len(want_lines), len(got_lines)))
            failures.append(
                f"n5.json is not the fixture with only the merged entries changed: {len(got_lines)} lines "
                f"written, {len(want_lines)} expected; first difference at line {off + 1}: "
                f"{got_lines[off] if off < len(got_lines) else '<end>'!r} vs "
                f"{want_lines[off] if off < len(want_lines) else '<end>'!r}"
                + ("; final newline differs" if got.endswith("\n") != N5_AFTER.endswith("\n") else "")
                + ("; CR in the written file" if "\r" in got else ""))
        # json, not the writer, judges the values — so a hand-typed form wrong the same way as
        # the writer cannot pass.
        try:
            parsed = {e["id"]: e for e in json.loads(got)}
            for rid in ("n5-yama", "n5-kawa"):
                values = tuple(parsed[rid].get(k) for k in ("exJP", "exEN", "exZH"))
                if values != SENTENCES[rid]:
                    failures.append(f"{rid} reads back as {values!r}; the stub returned {SENTENCES[rid]!r}")
        except (ValueError, KeyError) as exc:
            failures.append(f"n5.json does not read back after the merge ({exc!r})")
        for level in LEVELS[1:]:
            if stamp(res / f"{level}.json") != stamps[level] or read_raw(res / f"{level}.json") != FIXTURE[level]:
                failures.append(f"{level}.json was written, and no example was merged into it")
        if not list((root / "review-sheets").glob("examples-batch-n5-*.json")):
            failures.append("no batch manifest in the mirror's review-sheets/")

        # 2. A level file the merge could not write back byte for byte is refused before Gemini is
        #    asked anything, and is not touched: once in CRLF, once in a layout json.dumps cannot
        #    reproduce (ensure_ascii escapes — the same data, other bytes).
        for level, text, why, word in (
                ("n4", FIXTURE["n4"].replace("\n", "\r\n"), "CRLF line endings", "CRLF"),
                ("n3", FIXTURE["n3"].replace("会議", "\\u4f1a\\u8b70"), "\\u escapes", "round-trip")):
            path = res / f"{level}.json"
            write_raw(path, text)
            before, asked = stamp(path), len(calls)
            out, stop = gen(module, level, 5)
            if stop is None:
                failures.append(f"{level}.json with {why}: gen did not refuse; it printed {out[-300:]!r}")
            elif word not in str(stop):
                failures.append(f"{level}.json with {why}: refused without saying why ({word!r}): {stop}")
            if len(calls) != asked:
                failures.append(f"{level}.json with {why}: Gemini was asked {len(calls) - asked} time(s) "
                                "before the refusal — the batch would be generated and then thrown away")
            if read_raw(path) != text or stamp(path) != before:
                failures.append(f"{level}.json with {why}: the refused file was written")

    moved = [str(p) for p in real_before if hashlib.sha256(p.read_bytes()).hexdigest() != real_before[p]]
    if moved:
        failures.append(f"THE REAL FILES CHANGED: {moved} — read `git diff` on them before restoring")
    return failures


def main() -> int:
    failures = 0
    for sentence, entry, expected, why in CASES:
        got = g.contains_target(sentence, entry)
        if got != expected:
            failures += 1
            print(f"FAIL  {entry['surface']} in 「{sentence}」 → {got}, expected {expected}\n      ({why})")
    merge = merge_failures()
    for f in merge:
        print(f"FAIL  {f}")
    if failures or merge:
        print(f"\n{failures} of {len(CASES)} target cases failed; {len(merge)} merge failure(s)")
        return 1
    print(f"{len(CASES)} cases pass; the merge changed only the two merged entries' bytes of n5.json "
          "(an escaped quote typed by hand), wrote no other level, and refused a CRLF and an "
          "unreproducible level before any Gemini call, bytes unchanged; real corpus untouched")
    return 0


if __name__ == "__main__":
    sys.exit(main())
