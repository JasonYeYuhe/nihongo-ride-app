#!/usr/bin/env python3
"""Unit tests for gen_examples.py: its target gate, and its merge's write; and gen_passages.py's
merge's write.

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
  * in the layout the file was READ in, not today's layout hardcoded: n5 is in the shipped
    layout and n4 in passages.json's (indent=2, no final newline), and each is merged once. A
    merge that writes indent=1 plus a newline whatever it read passes n5 and fails n4; the
    pre-v1.36 indent=2 with no newline passes n4 and fails n5;
  * the other level files are not written at all (same inode, same mtime);
  * a level file in CRLF, and one in a layout json.dumps cannot reproduce, are each refused
    BEFORE any Gemini call, with their bytes unchanged and a message that says why.

GEN_PASSAGES' MERGE (v1.36). It wrote passages.json back with `json.dumps(indent=2)` and no final
newline whatever the file held — today's layout only because this script wrote it that way —
after reading it with universal newlines, so a CRLF passages.json came back with every line
ending changed for a one-entry append. It now writes through CorpusFile too. Proven the same way, from its own
mirror: the appended entry's lines are the only change, in the shipped layout (typed out in full)
and in indent=1 plus a newline (the same text re-indented line by line here, never by a
serialiser); a CRLF and an unreproducible passages.json are refused before any Gemini call.

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

# The level files, in the shipped layout: indent=1, non-ASCII raw, a final newline — except n4,
# which is in passages.json's layout (indent=2, no final newline). CorpusFile reproduces both; a
# writer that hardcodes either cannot pass both merges. Raw strings, so `\"` is the two
# characters JSON holds. n5-mizu carries an escaped quote that must survive.
LAYOUT = {"n4": (2, "")}   # (indent, final newline); every other level is (1, "\n")
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
    "exEN": "I read a \"good\" book.",
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
]""",
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
    "n4-sora": ("空がとても青い。", 'The sky is "very" blue.', "天空很蓝。"),
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

# n4.json after `gen n4 --count 1`, still in ITS layout — indent=2, no final newline: n4-sora
# gains three keys after `meanings`, whose `}` gains a comma; n4-hon, escaped quote included, does
# not move. Typed out in full.
N4_AFTER = r"""[
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
    "exEN": "I read a \"good\" book.",
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
    },
    "exJP": "空がとても青い。",
    "exEN": "The sky is \"very\" blue.",
    "exZH": "天空很蓝。"
  }
]"""


# gen_passages: passages.json in its shipped layout (indent=2, no final newline), the shape of
# the real file's entries; p001 carries an escaped quote that must survive. para101 is the
# highest paraNNN id, so the merged paragraph is para102.
PASSAGES_FIXTURE = r"""[
  {
    "id": "p001",
    "kana": "おはようございます",
    "topic": "daily",
    "level": "easy",
    "meanings": {
      "en": "Good \"morning\".",
      "zh": "早上好。"
    },
    "display": "おはようございます"
  },
  {
    "id": "para101",
    "kana": "あめのおとがしずかにきこえるよるだった",
    "topic": "rain",
    "level": "hard",
    "meanings": {
      "en": "It was a night when the rain sounded quiet.",
      "zh": "那是一个雨声静静的夜晚。"
    },
    "display": "あめのおとが、しずかにきこえるよるだった。"
  }
]"""

# What the stub "Gemini" answers: one paragraph that passes gen_passages.validate — hiragana
# only, 2 sentences, 55-120 kana — with a quote in its English.
PARAGRAPH = {
    "display": "あさのひかりがまどからさしこみ、しずかなへやをやわらかくてらしていた。とおくでとりがないて、きょうもいちにちがはじまる。",
    "topic": "morning",
    "en": 'Morning light came in through the "quiet" window, and the day began.',
    "zh": "清晨的阳光从窗户照进安静的房间，新的一天开始了。",
}
# Its kana — the display without 、 and 。 — typed by hand, not made by gen_passages.strip_punct.
PARAGRAPH_KANA = "あさのひかりがまどからさしこみしずかなへやをやわらかくてらしていたとおくでとりがないてきょうもいちにちがはじまる"

# passages.json after `gen --count 1`: para101's `}` gains a comma and para102 follows it, in the
# file's layout; nothing else moves. Typed out in full.
PASSAGES_AFTER = r"""[
  {
    "id": "p001",
    "kana": "おはようございます",
    "topic": "daily",
    "level": "easy",
    "meanings": {
      "en": "Good \"morning\".",
      "zh": "早上好。"
    },
    "display": "おはようございます"
  },
  {
    "id": "para101",
    "kana": "あめのおとがしずかにきこえるよるだった",
    "topic": "rain",
    "level": "hard",
    "meanings": {
      "en": "It was a night when the rain sounded quiet.",
      "zh": "那是一个雨声静静的夜晚。"
    },
    "display": "あめのおとが、しずかにきこえるよるだった。"
  },
  {
    "id": "para102",
    "kana": "あさのひかりがまどからさしこみしずかなへやをやわらかくてらしていたとおくでとりがないてきょうもいちにちがはじまる",
    "topic": "morning",
    "level": "hard",
    "meanings": {
      "en": "Morning light came in through the \"quiet\" window, and the day began.",
      "zh": "清晨的阳光从窗户照进安静的房间，新的一天开始了。"
    },
    "display": "あさのひかりがまどからさしこみ、しずかなへやをやわらかくてらしていた。とおくでとりがないて、きょうもいちにちがはじまる。"
  }
]"""


def halve_indent(text):
    """`text` with each line's leading spaces halved, plus a final newline: typed indent=2 text as
    indent=1 plus a newline, the n*.json layout. Line by line on the typed text, never through a
    serialiser. Sound here because no string in these fixtures holds a newline."""
    return "\n".join(" " * ((len(line) - len(line.lstrip(" "))) // 2) + line.lstrip(" ")
                     for line in text.split("\n")) + "\n"


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


def build_mirror(root, script="gen_examples", files=None):
    """root/scripts holding `script` and everything beside it that it imports; `files`
    ({name: text}, the fixture level files by default) in root/Sources/VocabKit/Resources."""
    (root / "scripts").mkdir(parents=True)
    copied, todo = set(), [script]
    while todo:
        name = todo.pop()
        if name not in copied:
            copied.add(name)
            shutil.copyfile(HERE / f"{name}.py", root / "scripts" / f"{name}.py")
            todo.extend(sibling_imports(HERE / f"{name}.py"))
    (root / RES_IN_REPO).mkdir(parents=True)
    for name, text in (files or {f"{level}.json": FIXTURE[level] for level in LEVELS}).items():
        write_raw(root / RES_IN_REPO / name, text)
    return copied


def load_from(root, copied, script="gen_examples", attrs=("ROOT", "RES")):
    """→ (`script` as root/scripts holds it, what of it reaches outside root)."""
    for name in copied | {script}:
        sys.modules.pop(name, None)
    spec = importlib.util.spec_from_file_location(script, root / "scripts" / f"{script}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    outside = [f"its {attr} is {getattr(module, attr, '<missing>')}" for attr in attrs
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


def mismatch(name, got, want):
    """Why `got` is not `want`, in numbers a reader can check."""
    want_lines, got_lines = want.split("\n"), got.split("\n")
    off = next((i for i, (a, b) in enumerate(zip(want_lines, got_lines)) if a != b),
               min(len(want_lines), len(got_lines)))
    return (f"{name} is not the fixture with only the merged entries changed: {len(got_lines)} lines "
            f"written, {len(want_lines)} expected; first difference at line {off + 1}: "
            f"{got_lines[off] if off < len(got_lines) else '<end>'!r} vs "
            f"{want_lines[off] if off < len(want_lines) else '<end>'!r}"
            + ("; final newline differs" if got.endswith("\n") != want.endswith("\n") else "")
            + ("; CR in the written file" if "\r" in got else ""))


def in_layout(text, indent, newline):
    """True when `text` is json's own rendering of its data at (indent, newline) — the fixtures'
    check of themselves, made with json, not with the code under test."""
    return json.dumps(json.loads(text), ensure_ascii=False, indent=indent) + newline == text


def merge_failures():
    failures = []
    real = [HERE.parent / RES_IN_REPO / f"{level}.json" for level in LEVELS]
    real_before = {p: hashlib.sha256(p.read_bytes()).hexdigest() for p in real if p.exists()}

    # The fixtures are what they claim to be — checked with json, not with the code under test.
    for level in LEVELS:
        indent, newline = LAYOUT.get(level, (1, "\n"))
        if not in_layout(FIXTURE[level], indent, newline):
            failures.append(f"fixture {level} is not in its layout (indent={indent}, final newline "
                            f"{bool(newline)}) — fix it first")
    if not in_layout(N4_AFTER, *LAYOUT["n4"]) or in_layout(N4_AFTER, 1, "\n"):
        failures.append("the expected n4.json is not in n4's own layout (indent=2, no final newline) "
                        "— then it cannot tell a layout-keeping write from a hardcoded one")
    for level, after in (("n5", N5_AFTER), ("n4", N4_AFTER)):
        if after == FIXTURE[level]:
            failures.append(f"the expected {level}.json equals the fixture — the test would pass on a no-op")
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

        # 1. The merge changes the merged entries' bytes, and writes no other level file — once on
        #    n5 (the shipped layout), once on n4 (indent=2, no final newline), each in its own.
        merged = {}
        for level, count, after, rids in (("n5", 2, N5_AFTER, ("n5-yama", "n5-kawa")),
                                          ("n4", 1, N4_AFTER, ("n4-sora",))):
            stamps = {other: stamp(res / f"{other}.json") for other in LEVELS}
            out, stop = gen(module, level, count)
            if stop is not None:
                failures.append(f"gen {level} stopped: {stop}; it printed {out[-400:]!r}")
            got = read_raw(res / f"{level}.json")
            if got != after:
                failures.append(mismatch(f"{level}.json", got, after))
            # json, not the writer, judges the values — so a hand-typed form wrong the same way as
            # the writer cannot pass.
            try:
                parsed = {e["id"]: e for e in json.loads(got)}
                for rid in rids:
                    values = tuple(parsed[rid].get(k) for k in ("exJP", "exEN", "exZH"))
                    if values != SENTENCES[rid]:
                        failures.append(f"{rid} reads back as {values!r}; the stub returned {SENTENCES[rid]!r}")
            except (ValueError, KeyError) as exc:
                failures.append(f"{level}.json does not read back after the merge ({exc!r})")
            merged[level] = after
            for other in LEVELS:
                if other != level and (stamp(res / f"{other}.json") != stamps[other]
                                       or read_raw(res / f"{other}.json") != merged.get(other, FIXTURE[other])):
                    failures.append(f"{other}.json was written by `gen {level}`, which merged nothing into it")
            if not list((root / "review-sheets").glob(f"examples-batch-{level}-*.json")):
                failures.append(f"no batch manifest for {level} in the mirror's review-sheets/")

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


def passages_failures():
    """gen_passages' merge, run from its own scratch mirror with a stubbed Gemini."""
    failures = []
    real = HERE.parent / RES_IN_REPO / "passages.json"
    real_before = hashlib.sha256(real.read_bytes()).hexdigest() if real.exists() else None

    shipped = PASSAGES_FIXTURE, PASSAGES_AFTER
    other = halve_indent(PASSAGES_FIXTURE), halve_indent(PASSAGES_AFTER)
    if not in_layout(shipped[0], 2, "") or not in_layout(other[0], 1, "\n"):
        failures.append("the passages fixtures are not in the layouts they claim — fix them first")
    if shipped[1] == shipped[0]:
        failures.append("the expected passages.json equals the fixture — the test would pass on a no-op")
    if failures:
        return failures

    with tempfile.TemporaryDirectory(prefix="gen-passages-merge-") as tmp:
        root = pathlib.Path(tmp).resolve() / "repo"
        copied = build_mirror(root, "gen_passages", {"passages.json": PASSAGES_FIXTURE})
        module, outside = load_from(root, copied, "gen_passages", ("ROOT", "PASSAGES"))
        if outside:
            return [f"gen_passages loaded from {root} reaches outside it — {'; '.join(outside)} — "
                    "so it was not run"]
        path = root / RES_IN_REPO / "passages.json"
        calls = []

        def fake(prompt):
            calls.append(prompt)
            return json.dumps(PARAGRAPH, ensure_ascii=False)
        module.call_gemini = fake
        module.time = types.SimpleNamespace(sleep=lambda s: None, strftime=time.strftime)

        def run():
            args = argparse.Namespace(count=1, chunk=25, max_rounds=2, dry=False, verbose=True)
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                try:
                    module.cmd_gen(args)
                except SystemExit as stop:
                    return out.getvalue(), stop
            return out.getvalue(), None

        # 1. The appended paragraph's lines are the only change — in the shipped layout, and in
        #    indent=1 plus a newline: whichever layout the file was read in, it is written in.
        for layout, (before, after) in (("indent=2, no final newline", shipped),
                                        ("indent=1 plus a newline", other)):
            write_raw(path, before)
            out, stop = run()
            if stop is not None:
                failures.append(f"gen_passages ({layout}) stopped: {stop}; it printed {out[-400:]!r}")
            got = read_raw(path)
            if got != after:
                failures.append(f"gen_passages ({layout}): " + mismatch("passages.json", got, after))
            try:
                new = json.loads(got)[-1]
                values = (new["id"], new["kana"], new["display"], new["meanings"]["en"], new["meanings"]["zh"])
                want = ("para102", PARAGRAPH_KANA, PARAGRAPH["display"], PARAGRAPH["en"], PARAGRAPH["zh"])
                if values != want:
                    failures.append(f"gen_passages ({layout}): the merged paragraph reads back as {values!r}, "
                                    f"not {want!r}")
            except (ValueError, KeyError, IndexError) as exc:
                failures.append(f"gen_passages ({layout}): passages.json does not read back ({exc!r})")
        if not list((root / "review-sheets").glob("passages-batch-*.json")):
            failures.append("gen_passages wrote no batch manifest in the mirror's review-sheets/")

        # 2. Refused before Gemini is asked anything, bytes unchanged: in CRLF, and in a layout
        #    json.dumps cannot reproduce (a `\u` escape — the same data, other bytes).
        for text, why, word in ((PASSAGES_FIXTURE.replace("\n", "\r\n"), "CRLF line endings", "CRLF"),
                                (PASSAGES_FIXTURE.replace("早上好", "\\u65e9上好"), "a \\u escape", "round-trip")):
            write_raw(path, text)
            before, asked = stamp(path), len(calls)
            out, stop = run()
            if stop is None:
                failures.append(f"passages.json with {why}: gen_passages did not refuse; it printed {out[-300:]!r}")
            elif word not in str(stop):
                failures.append(f"passages.json with {why}: refused without saying why ({word!r}): {stop}")
            if len(calls) != asked:
                failures.append(f"passages.json with {why}: Gemini was asked {len(calls) - asked} time(s) "
                                "before the refusal — the batch would be generated and then thrown away")
            if read_raw(path) != text or stamp(path) != before:
                failures.append(f"passages.json with {why}: the refused file was written")

    if real_before is not None and hashlib.sha256(real.read_bytes()).hexdigest() != real_before:
        failures.append(f"THE REAL FILE CHANGED: {real} — read `git diff` on it before restoring")
    return failures


def main() -> int:
    failures = 0
    for sentence, entry, expected, why in CASES:
        got = g.contains_target(sentence, entry)
        if got != expected:
            failures += 1
            print(f"FAIL  {entry['surface']} in 「{sentence}」 → {got}, expected {expected}\n      ({why})")
    merge = merge_failures() + passages_failures()
    for f in merge:
        print(f"FAIL  {f}")
    if failures or merge:
        print(f"\n{failures} of {len(CASES)} target cases failed; {len(merge)} merge failure(s)")
        return 1
    print(f"{len(CASES)} cases pass; the merge changed only the merged entries' bytes of n5.json (shipped "
          "layout) and n4.json (indent=2, no final newline), escaped quotes typed by hand, wrote no other "
          "level, and refused a CRLF and an unreproducible level before any Gemini call, bytes unchanged; "
          "gen_passages appended only its paragraph's lines in either layout and refused a CRLF and an "
          "unreproducible passages.json before any Gemini call; real corpus untouched")
    return 0


if __name__ == "__main__":
    sys.exit(main())
