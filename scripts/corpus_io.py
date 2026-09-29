#!/usr/bin/env python3
"""Read and write a corpus JSON file without reformatting it.

WHY THIS EXISTS, AND IT IS NOT A NEW LESSON. `STATE-2026-08-18.md` records the incident
verbatim: *"A serialiser that does not round-trip will rewrite the whole file. v1.26's first
corpus edit used `json.dumps(indent=2)` against files written with `indent=1`, and reformatted
all 178,868 lines of `n1.json` for a three-token change. A diff that large cannot be reviewed,
which is the same as not being guarded. Assert that re-serialising the parsed file reproduces it
BYTE FOR BYTE before writing anything."*

**The lesson was written into the document and never into the code.** Measured 2026-09-04:
every shipped corpus file round-trips exactly at `indent=1` —

    n1.json 178,871 lines · n2.json 119,990 · n3.json 94,990 · n4.json 40,651 · n5.json 37,801
    dictation-exclusions.json 2,392 · reading-notes.json 404

— while `gen_sentence_kana.py` and `apply_batch.py` both wrote them back with
`json.dumps(..., indent=2)`. Either script's next `--write` would have reproduced the v1.26
incident exactly, on all five files. This is the repo's own cheapest detector — *where a
document states a contract, check whether anything enforces it* — pointed at a document instead
of at a comment.

TWO THINGS, and the second is the durable one:

  * `load` remembers the indent the file actually uses, and `write` uses it again. Hardcoding
    `indent=1` would fix today's five files and break the next file written some other way.
  * `write` REFUSES to write when re-serialising the data it was given, unchanged, would not
    reproduce the original bytes. That is the assertion STATE asks for, and it is what makes
    this a guard rather than a convention: a future edit that changes the shape of the data in
    some way this module does not anticipate stops here instead of landing an unreviewable diff.
"""
import json
import re
from pathlib import Path


# What a quoting layer leaves in text when it is applied and never undone. 3e9407a shipped 20
# apostrophes as `'''` in 18 Practice translations — a shell-quoted `'\''` read back by an
# interpreter that takes `\'` as `'` — and nothing read the text until a person saw it on an
# iPad in the v1.34 simulator pass. None of these shapes has a legitimate use anywhere in the
# corpus. `Tests/VocabKitTests/CorpusEscapeResidueTests.swift` holds every shipped file to the
# SAME rule and is the authority; this copy lets a generator refuse the text before merging it.
# Change one, change both — `scripts/test_escape_residue.py` runs the Swift test's own cases here.
_RESIDUE = (
    (re.compile(r"''"), "a run of ASCII apostrophes (shell `'\\''` read back as `'''`, or SQL `''`)"),
    (re.compile(r"\\"), "a backslash (an escape nobody undid)"),
    (re.compile(r'""'), "a doubled double quote (CSV quoting)"),
    (re.compile(r"&(?:[A-Za-z][A-Za-z0-9]*|#[0-9]+|#[xX][0-9A-Fa-f]+);"), "an HTML character reference"),
)


def escape_residue(text):
    """What is wrong with `text`, or None when nothing is."""
    for pattern, why in _RESIDUE:
        if pattern.search(text):
            return why
    return None


class CorpusFile:
    """One corpus JSON file, its parsed contents, and how to write it back unchanged."""

    def __init__(self, path):
        self.path = Path(path)
        self.raw = self.path.read_text(encoding="utf-8")
        self.data = json.loads(self.raw)
        self.indent = self._detect_indent()

    def _detect_indent(self):
        """The indent that reproduces this file. None when nothing obvious does."""
        for indent in (1, 2, 4, None):
            if self._render(self.data, indent) == self.raw:
                return indent
        return None

    @staticmethod
    def _render(data, indent):
        return json.dumps(data, ensure_ascii=False, indent=indent) + "\n"

    def round_trips(self):
        """True when this file can be written back byte for byte."""
        return self.indent is not None or self._render(self.data, None) == self.raw

    def write(self, data=None):
        """Write `data` (default: this file's own, possibly mutated, object).

        Refuses when the file did not round-trip on load — writing then would reformat
        everything, and a diff nobody can read is the same as no guard at all.
        """
        if self.indent is None and not self.round_trips():
            raise SystemExit(
                f"{self.path}: this file does not round-trip through json.dumps at any indent "
                "this module knows, so writing it would reformat the whole file. Fix the "
                "serialisation here rather than landing an unreviewable diff.")
        payload = self._render(self.data if data is None else data, self.indent)
        tmp = self.path.with_suffix(self.path.suffix + ".tmp")
        tmp.write_text(payload, encoding="utf-8")
        tmp.replace(self.path)   # open(path,"w") truncates before it writes — v1.25's empty project.yml


def load(path):
    return CorpusFile(path)
