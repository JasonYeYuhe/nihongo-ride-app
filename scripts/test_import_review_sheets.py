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
"Byte for byte" is meant literally: every corpus file and the blocklist is read as raw bytes,
never in text mode, which reads `\\r\\n` as `\\n`. This test's first version compared through
`read_text`, and a CorpusFile.write that ended every line `\\r\\n` — every line of every touched
file changed on disk — still printed ok (the 1003 review's mutation R2).

Then two runs in which a TOUCHED file cannot round-trip: one through a fix (n2), one through a drop
alone (n4). Each must say so in the dry run, in the REFUSED line a reviewer reads, and the dry run
must write nothing. On --apply each must stop with "nothing written" and write nothing at all, not
even the files listed before it.

The importer is loaded and run from a scratch MIRROR of the repo. The mirror holds its scripts, the
Resources and the blocklist at their usual relative places, so the importer's module-level ROOT,
RES and BLOCKLIST name scratch files, and the test points it at a second copy. If a `resources=` or
`blocklist=` argument is ever lost on the way down, the importer writes the mirror's files, the
test says so, and the real checkout is never opened for writing. Before this, only a hash taken
afterwards guarded it. That hash is kept as a backstop.

A fifth run, added in v1.36: a touched n3.json in CRLF is REFUSED the same way. Until then
CorpusFile read through `read_text`, whose universal newlines hand `\\r\\n` over as `\\n`, so a CRLF
file "round-tripped" and --apply would have rewritten every line of it LF. Each REFUSED line is
the file's own, in corpus_io's words, and must say why: "CRLF" for this one, "round-trip" (and
not CRLF) for the indent=3 ones. Until v1.36's review the importer printed one fixed "would
reformat the whole file" for any refusal, so a CRLF file sent its reviewer to check an indent
that was fine.

THE OTHER CORPUS WRITERS (v1.36). `enrich_verb_classes.py --write` (every n*.json) and
`normalize_pos_tags.py --write` (each one it touched) wrote whole files with `json.dumps(indent=2)`
plus a newline — the shipped layout until abac89d (2026-08-21) made them indent=1, and a
re-indentation of every line of every file written ever since. Both now
write through CorpusFile; their checks live here, beside the importer's, so the gate count stays
17. Each runs from its own scratch mirror, on fixture files typed out below in the shipped
layout, and its expected output is typed out in full, never made by a serialiser:

  * only the entries the script changes change, byte for byte, and a file with no change is not
    written at all, even when CorpusFile could not have reproduced it;
  * each changed file is written in the layout it was read in: n5 is in the shipped layout and
    n4 in passages.json's (indent=2, no final newline), so a write hardcoded to either layout
    fails one of them;
  * a changed file in CRLF, or in a layout json.dumps cannot reproduce, stops the run with
    "nothing written" before ANY file is written — the one sorted before it included — and says
    why;
  * normalize_pos_tags without --write writes nothing, both when a touched file would be refused
    and when none would.

And CorpusFile itself, directly, because every caller checks round_trips() before it writes, so
no caller ever reaches `write`'s own refusal: `write` on a CRLF file and on an unreproducible one
raises and leaves the bytes alone, and the CRLF refusal names the line endings.

Run: python3 scripts/test_import_review_sheets.py
"""
import ast
import contextlib
import csv
import hashlib
import importlib.util
import inspect
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


def read_raw(path):
    """The file's text exactly as its bytes hold it. Every corpus and blocklist comparison here
    reads through this, never `read_text`: text mode turns `\\r\\n` into `\\n` on the way in, so a
    writer that ended every line `\\r\\n` — all 178,871 lines of n1.json changed on disk for one
    correction, the v1.26 diff this test exists to stop — compared equal and printed ok."""
    return path.read_bytes().decode("utf-8")


def write_raw(path, text):
    """`text` to `path` with no newline translation, so what the test lays down is what it reads."""
    path.write_bytes(text.encode("utf-8"))


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
    crlf_w, crlf_e = written.count("\r\n"), expected.count("\r\n")
    return (f"{name}.json is not the original with only the corrected lines changed: {len(w):,} lines "
            f"written, {len(e):,} expected, {moved:,} differ from the original by position; first "
            f"line off the expected text is {off + 1}: {w[off] if off < len(w) else '<end>'!r} "
            f"vs {e[off] if off < len(e) else '<end>'!r}"
            + ("; final newline differs" if written.endswith("\n") != expected.endswith("\n") else "")
            + (f"; {crlf_w:,} lines end CRLF, {crlf_e:,} expected" if crlf_w != crlf_e else ""))


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


def changed(res, blocklist, texts, blocklist_text):
    """The corpus files, and the blocklist, whose bytes are no longer `texts` / `blocklist_text`."""
    names = [f"{n}.json" for n in NAMES if read_raw(res / f"{n}.json") != texts[n]]
    return names + (["the blocklist"] if read_raw(blocklist) != blocklist_text else [])


def refusal_problem(out, path, word):
    """Why `out` does not hold exactly one REFUSED line, naming `path` and giving corpus_io's reason
    for it — `word` is "CRLF" or "round-trip" — or None when it does. A file without CR must not be
    blamed on its line endings, so a message that always said CRLF would not pass either."""
    lines = [line for line in out.splitlines() if line.startswith("REFUSED: ")]
    if len(lines) != 1 or not lines[0].startswith(f"REFUSED: {path}: ") or word not in lines[0]:
        return f"expected one REFUSED line naming {path} and saying {word!r}; got {lines!r}"
    if word != "CRLF" and "CRLF" in lines[0]:
        return f"the REFUSED line blames line endings the file does not have: {lines[0]!r}"
    return None


def refused_run(importer, what, sheets, res, blocklist, path, word, texts, blocklist_text):
    """Failures of one run that must be refused: the dry run prints the REFUSED line — where a
    reviewer reads what --apply will do, and why: one line for `path`, saying `word` — and writes
    nothing; --apply prints it and stops with "nothing written", having written no corpus file and
    not the blocklist. The files are checked after each of the two, and put back after the dry run,
    so each failure names the run that wrote."""
    failures = []
    out, raised = run(importer, [str(sheets)], res, blocklist)
    problem = refusal_problem(out, path, word)
    if raised or problem:
        failures.append(f"with {what}, the dry run did not refuse as it should (it raised {raised!r}): "
                        f"{problem}; it printed {out[-500:]!r}")
    for f in changed(res, blocklist, texts, blocklist_text):
        failures.append(f"with {what}, the dry run changed {f}")
    for n in NAMES:
        write_raw(res / f"{n}.json", texts[n])
    write_raw(blocklist, blocklist_text)
    out, raised = run(importer, [str(sheets), "--apply"], res, blocklist)
    problem = refusal_problem(out, path, word)
    if str(raised) != "nothing written" or problem:
        failures.append(f"with {what}, --apply did not refuse before writing: raised {raised!r}; "
                        f"{problem}; printed {out[-500:]!r}")
    for f in changed(res, blocklist, texts, blocklist_text):
        failures.append(f"with {what}, a refused --apply still wrote {f}")
    return failures


# ---------------------------------------------------------------------------------------------
# The other corpus writers. Fixture files in the shipped layout (indent=1, non-ASCII raw, a final
# newline), raw strings so `\"` is the two characters JSON holds — except n4, which is in
# passages.json's layout (indent=2, no final newline), a layout CorpusFile reproduces and no
# shipped n*.json uses. In each set n4 and n5 change, so a writer that hardcodes today's layout (indent=1
# plus a newline) fails n4 and one that hardcodes the old indent=2 fails n5, while a write in the
# layout each file was read in passes both. n2 does not change, and n3 does not and is in a
# layout CorpusFile cannot reproduce (a `\u` escape: the same data, other bytes) — so writing it
# at all would stop the run.
WRITER_LAYOUT = {"n4": (2, "")}   # (indent, final newline); n2 and n5 are (1, "\n")

ENRICH = {
    "n2": r"""[
 {
  "id": "n2-nomu",
  "surface": "飲む",
  "kana": "のむ",
  "pos": [
   "v"
  ],
  "vc": "godan_m",
  "meanings": {
   "en": [
    "to drink"
   ]
  }
 }
]
""",
    "n3": r"""[
 {
  "id": "n3-mizu",
  "surface": "水",
  "kana": "みず",
  "pos": [
   "n"
  ],
  "meanings": {
   "en": [
    "water"
   ]
  }
 }
]
""",
    "n4": r"""[
  {
    "id": "n4-kaku",
    "surface": "書く",
    "kana": "かく",
    "pos": [
      "v"
    ],
    "meanings": {
      "en": [
        "to write"
      ]
    }
  },
  {
    "id": "n4-yomu",
    "surface": "読む",
    "kana": "よむ",
    "pos": [
      "v"
    ],
    "vc": "godan_m",
    "meanings": {
      "en": [
        "to read"
      ]
    }
  },
  {
    "id": "n4-taberu",
    "surface": "食べる",
    "kana": "たべる",
    "pos": [
      "v1"
    ],
    "vc": "godan_r",
    "meanings": {
      "en": [
        "to eat"
      ]
    }
  },
  {
    "id": "n4-kaeru",
    "surface": "帰る",
    "kana": "かえる",
    "pos": [
      "v"
    ],
    "vc": "godan_r",
    "meanings": {
      "en": [
        "to go home"
      ]
    }
  },
  {
    "id": "n4-yu",
    "surface": "湯",
    "kana": "ゆ",
    "pos": [
      "n"
    ],
    "meanings": {
      "en": [
        "\"hot\" water"
      ]
    }
  }
]""",
    "n5": r"""[
 {
  "id": "n5-oyogu",
  "surface": "泳ぐ",
  "kana": "およぐ",
  "pos": [
   "v"
  ],
  "meanings": {
   "en": [
    "to swim"
   ]
  },
  "vc": "godan_g"
 }
]
""",
}

# `write_mode(None)` — no JMdict — on the fixture: 書く gains godan_k after `pos`; 読む already
# carries its class there and does not move; 食べる's stale godan_r becomes the ichidan its `v1`
# label says, in place; 帰る's godan_r is dropped, because without JMdict a る verb is ambiguous
# and the script withholds it (its behaviour, pinned here, not endorsed); 湯 is no verb, and its
# escaped quotes stay. n5's ONLY change is that 泳ぐ's godan_g, right already, moves up behind
# `pos`: the data compares equal as dicts, the bytes do not, and the file must still be written
# (and, in CRLF, refused) — which pins the key-order comparison in write_mode.
ENRICH_AFTER = {
    "n4": r"""[
  {
    "id": "n4-kaku",
    "surface": "書く",
    "kana": "かく",
    "pos": [
      "v"
    ],
    "vc": "godan_k",
    "meanings": {
      "en": [
        "to write"
      ]
    }
  },
  {
    "id": "n4-yomu",
    "surface": "読む",
    "kana": "よむ",
    "pos": [
      "v"
    ],
    "vc": "godan_m",
    "meanings": {
      "en": [
        "to read"
      ]
    }
  },
  {
    "id": "n4-taberu",
    "surface": "食べる",
    "kana": "たべる",
    "pos": [
      "v1"
    ],
    "vc": "ichidan",
    "meanings": {
      "en": [
        "to eat"
      ]
    }
  },
  {
    "id": "n4-kaeru",
    "surface": "帰る",
    "kana": "かえる",
    "pos": [
      "v"
    ],
    "meanings": {
      "en": [
        "to go home"
      ]
    }
  },
  {
    "id": "n4-yu",
    "surface": "湯",
    "kana": "ゆ",
    "pos": [
      "n"
    ],
    "meanings": {
      "en": [
        "\"hot\" water"
      ]
    }
  }
]""",
    "n5": r"""[
 {
  "id": "n5-oyogu",
  "surface": "泳ぐ",
  "kana": "およぐ",
  "pos": [
   "v"
  ],
  "vc": "godan_g",
  "meanings": {
   "en": [
    "to swim"
   ]
  }
 }
]
""",
}

NORMALIZE = {
    "n2": r"""[
 {
  "id": "n2-michi",
  "surface": "道",
  "kana": "みち",
  "pos": [
   "n"
  ]
 }
]
""",
    "n3": r"""[
 {
  "id": "n3-hashiru",
  "surface": "走る",
  "kana": "はしる",
  "pos": [
   "v"
  ]
 }
]
""",
    "n4": r"""[
  {
    "id": "n4-eki",
    "surface": "駅",
    "kana": "えき",
    "pos": [
      "Noun"
    ],
    "meanings": {
      "en": [
        "\"main\" station"
      ]
    }
  },
  {
    "id": "n4-hon",
    "surface": "本",
    "kana": "ほん",
    "pos": [
      "n",
      "noun"
    ]
  },
  {
    "id": "n4-takai",
    "surface": "高い",
    "kana": "たかい",
    "pos": [
      "adj-i"
    ]
  }
]""",
    "n5": r"""[
 {
  "id": "n5-iku",
  "surface": "行く",
  "kana": "いく",
  "pos": [
   "verb"
  ]
 }
]
""",
}

# `--write` on the fixture: Noun becomes n; ['n', 'noun'] becomes ['n'] — a line goes and the
# comma before it with it; adj-i is already canonical; n5's verb becomes v.
NORMALIZE_AFTER = {
    "n4": r"""[
  {
    "id": "n4-eki",
    "surface": "駅",
    "kana": "えき",
    "pos": [
      "n"
    ],
    "meanings": {
      "en": [
        "\"main\" station"
      ]
    }
  },
  {
    "id": "n4-hon",
    "surface": "本",
    "kana": "ほん",
    "pos": [
      "n"
    ]
  },
  {
    "id": "n4-takai",
    "surface": "高い",
    "kana": "たかい",
    "pos": [
      "adj-i"
    ]
  }
]""",
    "n5": r"""[
 {
  "id": "n5-iku",
  "surface": "行く",
  "kana": "いく",
  "pos": [
   "v"
  ]
 }
]
""",
}

# n3 in a layout CorpusFile cannot reproduce: the same data, one character written as a JSON
# `\u` escape, which json.dumps(ensure_ascii=False) never writes. Made here rather than typed
# into the raw strings above, where an editor or a tool may turn the escape into the character.
ENRICH["n3"] = ENRICH["n3"].replace('"水"', '"\\u6c34"')
NORMALIZE["n3"] = NORMALIZE["n3"].replace('"走る"', '"\\u8d70る"')

WRITER_LEVELS = ["n2", "n3", "n4", "n5"]


def build_writer_mirror(root, scripts, fixture):
    """root laid out as the repo is: `scripts` and every script beside them they import in
    root/scripts, `fixture` as root/Sources/VocabKit/Resources/<name>.json. → module names copied."""
    (root / "scripts").mkdir(parents=True)
    copied, todo = set(), list(scripts)
    while todo:
        name = todo.pop()
        if name not in copied:
            copied.add(name)
            shutil.copyfile(HERE / f"{name}.py", root / "scripts" / f"{name}.py")
            todo.extend(sibling_imports(HERE / f"{name}.py"))
    (root / RES_IN_REPO).mkdir(parents=True)
    for n, text in fixture.items():
        write_raw(root / RES_IN_REPO / f"{n}.json", text)
    return copied


def load_writer(root, name, copied, path_attrs):
    """→ (`name` as root/scripts holds it, what of it reaches outside root). Its sibling imports
    are dropped from sys.modules first, so they load from root/scripts too. What is checked: the
    paths it would write, any module now loaded from the REAL scripts/, and where the CorpusFile
    it holds (if it holds one) was loaded from."""
    for module_name in copied:
        sys.modules.pop(module_name, None)
    spec = importlib.util.spec_from_file_location(name, root / "scripts" / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    outside = [f"its {attr} is {getattr(module, attr, '<missing>')}" for attr in path_attrs
               if not inside(getattr(module, attr, "<missing>"), root)]
    outside += [f"{module_name} loaded from {loaded.__file__}" for module_name, loaded in sorted(sys.modules.items())
                if module_name != "__main__" and getattr(loaded, "__file__", None) and inside(loaded.__file__, HERE)]
    corpus_file = getattr(module, "CorpusFile", None)
    if corpus_file is not None and not inside(inspect.getfile(corpus_file), root):
        outside.append(f"its CorpusFile comes from {inspect.getfile(corpus_file)}")
    return module, outside


def load_corpus_io(tmp):
    """corpus_io from a scratch copy, under a name of its own, so what is tested is the module
    itself whatever any writer imports."""
    copy = tmp / "corpus-io-copy" / "corpus_io.py"
    copy.parent.mkdir(parents=True)
    shutil.copyfile(HERE / "corpus_io.py", copy)
    spec = importlib.util.spec_from_file_location("corpus_io_under_test", copy)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def writer_failures(label, run, res, fixture, after):
    """Failures of the three runs every writer gets. `run()` → (output, what it raised or None)."""
    failures = []
    for n in WRITER_LEVELS:
        indent, newline = WRITER_LAYOUT.get(n, (1, "\n"))
        for what, text in (("fixture", fixture[n]), ("expected", after.get(n))):
            if n != "n3" and text is not None and \
                    json.dumps(json.loads(text), ensure_ascii=False, indent=indent) + newline != text:
                failures.append(f"{label}: {what} {n} is not in its layout (indent={indent}, final "
                                f"newline {bool(newline)}) — fix it first")
    if json.dumps(json.loads(fixture["n3"]), ensure_ascii=False, indent=1) + "\n" == fixture["n3"]:
        failures.append(f"{label}: fixture n3 is meant NOT to be reproducible, and is")
    for n, text in after.items():
        if text == fixture[n]:
            failures.append(f"{label}: expected {n}.json equals its fixture — the test would pass on a no-op")
    if failures:
        return failures

    def put(texts):
        for n, text in texts.items():
            write_raw(res / f"{n}.json", text)

    # 1. Only the changed entries' bytes change; a file with no change is not written at all.
    put(fixture)
    stamps = {n: written_stamp(res / f"{n}.json") for n in WRITER_LEVELS}
    out, raised = run()
    if raised:
        failures.append(f"{label}: the write run raised {raised!r}; it printed {out[-500:]!r}")
    for n in WRITER_LEVELS:
        written = read_raw(res / f"{n}.json")
        want = after.get(n, fixture[n])
        if written != want:
            failures.append(f"{label}: " + describe(n, fixture[n], written, want))
        if n not in after and written_stamp(res / f"{n}.json") != stamps[n]:
            failures.append(f"{label}: {n}.json was written, and nothing in it changed")

    # 2. n5 — changed, and sorted after n4, which also changed — cannot be written back byte for
    #    byte. The run stops with "nothing written" and writes NOTHING, n4 included.
    for why, n5, word in (("in CRLF", fixture["n5"].replace("\n", "\r\n"), "CRLF"),
                          ("with a \\u escape", fixture["n5"].replace('"v', '"\\u0076', 1), "round-trip")):
        texts = dict(fixture, n5=n5)
        put(texts)
        stamps = {n: written_stamp(res / f"{n}.json") for n in WRITER_LEVELS}
        out, raised = run()
        if str(raised) != "nothing written":
            failures.append(f"{label}: with n5.json {why}, the run did not stop with 'nothing written': "
                            f"raised {raised!r}; printed {out[-500:]!r}")
        refused = [line for line in out.splitlines() if line.startswith("REFUSED: ")]
        if len(refused) != 1 or "n5.json" not in refused[0] or word not in refused[0]:
            failures.append(f"{label}: with n5.json {why}, expected one REFUSED line naming n5.json and "
                            f"saying {word!r}; got {refused!r}")
        for n in WRITER_LEVELS:
            if read_raw(res / f"{n}.json") != texts[n] or written_stamp(res / f"{n}.json") != stamps[n]:
                failures.append(f"{label}: with n5.json {why}, the refused run still wrote {n}.json")
    return failures


def corpus_file_failures(corpus_io, tmp):
    """CorpusFile.write's own refusal, which no caller reaches: they all ask round_trips() first."""
    failures = []
    lf = '[\n {\n  "id": "n5-a",\n  "en": "\\"a\\""\n }\n]\n'   # indent=1 + newline, a `\"` inside
    cases = (("an LF file", lf, None),
             ("a CRLF file", lf.replace("\n", "\r\n"), "CRLF"),
             ("a file ending in a lone CR", lf[:-1] + "\r", "CRLF"),
             ("an indent=3 file", lf.replace("\n ", "\n   ").replace("\n    ", "\n      "), "round-trip"))
    for i, (what, text, word) in enumerate(cases):
        path = tmp / f"corpus-file-{i}.json"
        write_raw(path, text)
        corpus = corpus_io.CorpusFile(path)
        try:
            corpus.write()
            raised = None
        except SystemExit as exc:
            raised = str(exc)
        if read_raw(path) != text:
            failures.append(f"CorpusFile.write on {what} changed its bytes")
        if word is None:
            if raised is not None or not corpus.round_trips():
                failures.append(f"CorpusFile refused {what}, which it can reproduce: {raised}")
        elif raised is None:
            failures.append(f"CorpusFile.write on {what} did not refuse")
        elif word not in raised:
            failures.append(f"CorpusFile.write on {what} refused without saying why ({word!r}): {raised}")
    return failures


def other_writers(tmp):
    failures = []
    for label, script, fixture, after in (("enrich_verb_classes", "enrich_verb_classes", ENRICH, ENRICH_AFTER),
                                          ("normalize_pos_tags", "normalize_pos_tags", NORMALIZE, NORMALIZE_AFTER)):
        root = tmp / f"{script}-mirror"
        copied = build_writer_mirror(root, [script], fixture)
        attrs = ("REPO", "VOCAB_GLOB") if script == "enrich_verb_classes" else ("REPO", "RESOURCES")
        module, outside = load_writer(root, script, copied, attrs)
        if outside:
            failures.append(f"{script} loaded from {root} reaches outside it — {'; '.join(outside)} — "
                            "so it was not run")
            continue
        res = root / RES_IN_REPO

        if script == "enrich_verb_classes":
            def run(module=module):
                out = io.StringIO()
                with contextlib.redirect_stderr(out):
                    try:
                        module.write_mode(None)
                    except SystemExit as exc:
                        return out.getvalue(), exc
                    except Exception as exc:   # report it, do not crash
                        return out.getvalue(), exc
                return out.getvalue(), None
        else:
            def run(module=module):
                out = io.StringIO()
                with contextlib.redirect_stdout(out):
                    try:
                        code = module.main(["--write"])
                    except SystemExit as exc:
                        return out.getvalue(), exc
                    except Exception as exc:   # a main() without `argv`, say: report it, do not crash
                        return out.getvalue(), exc
                return out.getvalue(), (f"exit code {code}" if code else None)
        failures += writer_failures(label, run, res, fixture, after)

        if script == "normalize_pos_tags":
            # The report alone — no --write, the documented default — writes nothing. Twice: with
            # nothing refused (n4 and n5 touched, both reproducible), where a write branch reached
            # by mistake WOULD write; and with n5 in CRLF, where the report must also name the
            # refusal a --write would meet. The refused run alone could not tell: its refusal
            # keeps any write branch from being reached.
            for case, texts in (("nothing refused", dict(fixture)),
                                ("n5.json in CRLF", dict(fixture, n5=fixture["n5"].replace("\n", "\r\n")))):
                for n, text in texts.items():
                    write_raw(res / f"{n}.json", text)
                stamps = {n: written_stamp(res / f"{n}.json") for n in WRITER_LEVELS}
                out = io.StringIO()
                with contextlib.redirect_stdout(out):
                    try:
                        module.main([])
                    except (SystemExit, Exception) as exc:
                        failures.append(f"normalize_pos_tags ({case}): the report alone raised {exc!r}")
                lines = out.getvalue().splitlines()
                for want in ("n4.json: 2 entries normalised", "n5.json: 1 entries normalised",
                             "(report only — pass --write to apply)"):
                    if want not in lines:
                        failures.append(f"normalize_pos_tags ({case}): the report did not print {want!r}, "
                                        "so the fixture may not be touching what this check needs")
                refused = [line for line in lines if line.startswith("REFUSED: ")]
                if case == "nothing refused" and refused:
                    failures.append(f"normalize_pos_tags ({case}): the report printed {refused!r}")
                if case != "nothing refused" and not any("n5.json" in line and "CRLF" in line for line in refused):
                    failures.append(f"normalize_pos_tags ({case}): the report did not say a --write would "
                                    f"be refused for n5.json's CRLF; it printed {refused!r}")
                wrote = [line for line in lines if line.startswith("wrote ")]
                if wrote:
                    failures.append(f"normalize_pos_tags ({case}): the report printed {wrote!r}")
                for n in WRITER_LEVELS:
                    if written_stamp(res / f"{n}.json") != stamps[n] or read_raw(res / f"{n}.json") != texts[n]:
                        failures.append(f"normalize_pos_tags ({case}): the report wrote {n}.json")
    return failures + corpus_file_failures(load_corpus_io(tmp), tmp)


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
        n2 = json.loads(read_raw(res / "n2.json"))
        write_raw(res / "n2.json", json.dumps(n2, ensure_ascii=False, indent=3) + "\n")
        original = {n: read_raw(res / f"{n}.json") for n in NAMES}
        original_blocklist = read_raw(blocklist)

        def restore(texts):
            for n in NAMES:
                write_raw(res / f"{n}.json", texts[n])
            write_raw(blocklist, original_blocklist)

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
        for f in changed(res, blocklist, original, original_blocklist):
            failures.append(f"the dry run changed {f}")

        # 2. --apply: the corrected files differ from the original by exactly the corrected lines,
        #    in the hand-written JSON; every other file — the OK-only n3 and the unreproducible n2
        #    among them — is byte for byte the same and was never written at all.
        stamps = {n: written_stamp(res / f"{n}.json") for n in NAMES}
        out, raised = run(importer, [str(sheets), "--apply"], res, blocklist)
        if raised:
            failures.append(f"--apply raised {raised!r}; it printed:\n{out[-600:]}")
        for n in NAMES:
            written = read_raw(res / f"{n}.json")
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
                got = next(e for e in json.loads(read_raw(res / f"{n}.json"))
                           if e["id"] == rid)["meanings"]["en"]
            except (ValueError, StopIteration) as exc:
                failures.append(f"{n}.json does not read back after --apply ({exc!r})")
                continue
            if got != want:
                failures.append(f"{n}.json {rid} meanings.en reads back as {got!r}; the reviewer wrote {want!r}")
        want_blocklist = original_blocklist + "# native review import\n" + dropped["kana"] + "\n"
        if read_raw(blocklist) != want_blocklist:
            failures.append(f"the blocklist did not gain exactly the dropped kana {dropped['kana']!r}, "
                            "byte for byte")

        # 3. A TOUCHED file --apply would have to reformat stops the whole run before ANY file is
        #    written. n2 (indent=3) now gets a fix; the n5 fix lists first and must not land either.
        restore(original)
        write_sheet(sheets / "vocab-n2.csv", [(n2[0]["id"], "fix", "en: reviewed", "")])
        failures += refused_run(
            importer, "a fix in n2.json", sheets, res, blocklist,
            res / "n2.json", "round-trip", original, original_blocklist)

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
            res / "n4.json", "round-trip", drop_only, original_blocklist)

        # 5. A touched file in CRLF, beside an n5 fix that must not land. CorpusFile read through
        #    universal newlines until v1.36, saw LF, called it reproducible, and --apply rewrote
        #    every line of n3.json with LF endings. The REFUSED line must name the line endings:
        #    until v1.36's review it said "would reformat the whole file" for every refusal, and a
        #    reviewer of this file would have gone looking at an indent that was fine.
        crlf = dict(original)
        crlf["n3"] = original["n3"].replace("\n", "\r\n")
        restore(crlf)
        crlf_sheets = tmp / "work" / "crlf"
        write_sheet(crlf_sheets / "vocab-n5.csv", [(vocab["id"], "fix", "en: reviewed", "")])
        write_sheet(crlf_sheets / "vocab-n3.csv", [(n3[0]["id"], "fix", "en: reviewed", "")])
        failures += refused_run(
            importer, "a fix in a CRLF n3.json", crlf_sheets, res, blocklist,
            res / "n3.json", "CRLF", crlf, original_blocklist)

        lost = [str(p.relative_to(mirror)) for p in defaults if digest(p) != defaults_before[p]]
        if lost:
            failures.append(f"the importer wrote its own default paths {lost} in the scratch mirror — a "
                            "`resources=` or `blocklist=` argument is lost on the way down, and only the "
                            "mirror kept that write off the real checkout")

        # The other corpus writers, and CorpusFile's own refusal, each from its own mirror.
        failures += other_writers(tmp)

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
          "cannot round-trip — through a fix or a drop alone, or in CRLF — is REFUSED in the dry run "
          "and stops --apply before any write, its REFUSED line giving that file's own reason (CRLF "
          "named); enrich_verb_classes and normalize_pos_tags change only the changed entries' bytes, "
          "in each file's own layout (indent=1 + newline, and indent=2 without), write no unchanged "
          "file, and refuse a CRLF or unreproducible file with nothing written; normalize's report "
          "writes nothing, refusal or not; CorpusFile.write refuses CRLF, a lone CR and indent=3 by "
          "itself; run from scratch mirrors, the real corpus untouched")
    return 0


if __name__ == "__main__":
    sys.exit(main())
