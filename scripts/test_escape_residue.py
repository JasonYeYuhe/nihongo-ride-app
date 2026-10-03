#!/usr/bin/env python3
"""Every scripted path into the corpus refuses quoting residue before it writes.

3e9407a shipped 20 apostrophes as `'''` in 18 Practice translations; the v1.34 iPad simulator
pass saw "I'''m" and "father'''s" on screen. Gemini's own output was clean — the tripling
happened in a hand-run merge step, the signature of a shell-quoted `'\\''` read back by an
interpreter that takes `\\'` as `'`. `Tests/VocabKitTests/CorpusEscapeResidueTests.swift` holds
every shipped corpus string to the rule and is the authority.

The paths that refuse residue before writing, each proven here:

  * `gen_passages.validate` and `gen_examples.validate` — the generators;
  * `pilot_gate.gates` — the gate `apply_batch.py` runs every generated example through, which is
    the live example path (it never calls `gen_examples.validate`);
  * `import_review_sheets` — a native reviewer's corrections, refused as a whole row.

Anything else that writes the corpus — a hand edit, a one-off shell merge like the one that made
3e9407a, a script not listed here — is caught only by the Swift test at gate time.

What this proves:

  1. `corpus_io.escape_residue` — the Python copy of the rule — agrees with the Swift test on
     every calibration case the Swift test lists. The cases are READ FROM THE SWIFT FILE, not
     copied here, so a case added on either side is checked on both; and every string literal in
     the Swift test function is accounted for, so a case added outside the two lists fails
     here instead of being silently skipped. (This compares the rules only on those cases; that
     they agree on every input is argued in the comments on both, not measured.)
  2. The generators refuse residue in each translation field.
  3. `corpus_io.residue_reasons` words every refusal as the generators do, and `pilot_gate.gates`
     calls it over jp, en and zh. pilot_gate imports sudachipy, which the system python3 this
     gate runs on does not have, so the call is pinned by parsing its source (`ast`, never
     import) — and the pin is itself shown to go red on a copy with the call removed.
  4. `import_review_sheets` refuses a damaged correction and applies a clean one.

Run: python3 scripts/test_escape_residue.py
"""
import ast
import contextlib
import importlib.util
import io
import json
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
SWIFT_TEST = HERE.parent / "Tests/VocabKitTests/CorpusEscapeResidueTests.swift"
PILOT_GATE = HERE / "pilot_gate.py"
sys.path.insert(0, str(HERE))
from corpus_io import escape_residue, residue_reasons   # noqa: E402

# A Swift string literal on one line: quote, then any run of non-quote/non-backslash characters
# or backslash escapes, then quote.
LITERAL = re.compile(r'"(?:[^"\\\n]|\\.)*"')
# The only interpolated literals the calibration function holds: its failure messages. They are
# named, not skipped by shape, so an interpolated CASE would be reported rather than ignored.
MESSAGES = {r'"missed: \(text)"', r'"false positive: \(text)"'}


class Unreadable(Exception):
    """The Swift test is not shaped the way this reader expects: fail, do not guess."""


def load(name):
    spec = importlib.util.spec_from_file_location(name, HERE / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def strip_line_comments(swift):
    """`swift` with every `//` comment removed — outside string literals only, so a `//` inside
    a case survives. Escapes inside a literal are skipped as pairs, as Swift reads them."""
    out, i, in_string = [], 0, False
    while i < len(swift):
        c = swift[i]
        if in_string:
            out.append(c)
            if c == "\\" and i + 1 < len(swift):
                out.append(swift[i + 1])
                i += 2
                continue
            if c == '"':
                in_string = False
        elif c == '"':
            in_string = True
            out.append(c)
        elif swift.startswith("//", i):
            while i < len(swift) and swift[i] != "\n":
                i += 1
            continue
        else:
            out.append(c)
        i += 1
    return "".join(out)


def swift_cases(source):
    """→ (damaged, clean): the calibration cases of `func ruleIsCalibrated` in the Swift test.

    Swift and JSON agree on the only escapes these literals use (\\\\, \\", \\n), so each one
    decodes with json.loads; a literal using anything else (`\\u{…}`) fails loudly here rather
    than being read wrong. Every string literal in the function body must be a case in one of
    the two lists or one of MESSAGES — a case written after `] + [` or in a third list changes
    the count and raises, and a raw (`#"…"#`) or multi-line (triple-quoted) literal raises before any
    counting, because this reader cannot see inside either. `//` comments are dropped first, so a
    quote in a comment is neither a case nor an error.
    """
    body = re.search(r"func ruleIsCalibrated\(\)\s*\{(.*?)\n    \}\n", source, re.S)
    if not body:
        raise Unreadable(f"no `func ruleIsCalibrated()` in {SWIFT_TEST.name} — the test moved")
    body = body.group(1)
    if '#"' in body or '"""' in body:
        raise Unreadable("ruleIsCalibrated holds a raw or multi-line string literal — this reader "
                         "cannot account for one; write the case as a plain literal")
    body = strip_line_comments(body)
    lists = {}
    for name in ("damaged", "clean"):
        block = re.search(rf"let {name} = \[(.*?)\n\s*\]", body, re.S)
        if not block:
            raise Unreadable(f"no `let {name} = [` in ruleIsCalibrated — the test moved")
        try:
            lists[name] = [json.loads(lit) for lit in LITERAL.findall(block.group(1))]
        except json.JSONDecodeError as exc:
            raise Unreadable(f"a `{name}` literal does not decode as JSON ({exc})") from exc
    everything = LITERAL.findall(body)
    interpolated = [lit for lit in everything if "\\(" in lit]
    if sorted(interpolated) != sorted(MESSAGES):
        raise Unreadable(f"interpolated literals in ruleIsCalibrated are {interpolated}, "
                         f"expected exactly {sorted(MESSAGES)} — a case must be a plain literal")
    listed = len(lists["damaged"]) + len(lists["clean"])
    if len(everything) - len(interpolated) != listed:
        raise Unreadable(f"ruleIsCalibrated holds {len(everything) - len(interpolated)} plain "
                         f"string literals but its two lists hold {listed}: a case lives "
                         "somewhere this reader does not look")
    return lists["damaged"], lists["clean"]


def pilot_gate_pin(source):
    """→ what is wrong with pilot_gate's use of residue_reasons, or None.

    Requires: `from corpus_io import residue_reasons` at module level and no other binding of
    that name; and, as a statement directly in the body of `gates` (not under an `if`), exactly
    `bad.extend(residue_reasons((("jp", jp), ("en", en), ("zh", zh))))` — before the first
    top-level `return`, so it runs, and with no later top-level assignment to `bad` that would
    throw its reasons away.
    """
    try:
        tree = ast.parse(source)
    except SyntaxError as exc:
        return f"pilot_gate.py does not parse: {exc}"
    imported = any(isinstance(node, ast.ImportFrom) and node.module == "corpus_io"
                   and any(a.name == "residue_reasons" and a.asname is None for a in node.names)
                   for node in tree.body)
    if not imported:
        return "pilot_gate does not `from corpus_io import residue_reasons` at module level"
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.ClassDef)) and node.name == "residue_reasons":
            return "pilot_gate defines its own residue_reasons"
        if isinstance(node, ast.Name) and node.id == "residue_reasons" and isinstance(node.ctx, ast.Store):
            return "pilot_gate rebinds residue_reasons"
    gates = [node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == "gates"]
    if len(gates) != 1:
        return f"expected one top-level `def gates`, found {len(gates)}"
    body = gates[0].body
    first_return = next((i for i, s in enumerate(body) if isinstance(s, ast.Return)), len(body))
    for index, stmt in enumerate(body):
        call = stmt.value if isinstance(stmt, ast.Expr) else None
        if not (isinstance(call, ast.Call) and isinstance(call.func, ast.Attribute)
                and isinstance(call.func.value, ast.Name) and call.func.value.id == "bad"
                and call.func.attr == "extend" and len(call.args) == 1):
            continue
        inner = call.args[0]
        if not (isinstance(inner, ast.Call) and isinstance(inner.func, ast.Name)
                and inner.func.id == "residue_reasons" and len(inner.args) == 1
                and isinstance(inner.args[0], (ast.Tuple, ast.List))):
            continue
        pairs = []
        for elt in inner.args[0].elts:
            if (isinstance(elt, ast.Tuple) and len(elt.elts) == 2
                    and isinstance(elt.elts[0], ast.Constant) and isinstance(elt.elts[1], ast.Name)):
                pairs.append((elt.elts[0].value, elt.elts[1].id))
        if pairs == [("jp", "jp"), ("en", "en"), ("zh", "zh")]:
            if index > first_return:
                return "gates() calls residue_reasons only after its final return — it never runs"
            for later in body[index + 1:]:
                if isinstance(later, (ast.Assign, ast.AnnAssign)) and any(
                        isinstance(t, ast.Name) and t.id == "bad"
                        for t in (later.targets if isinstance(later, ast.Assign) else [later.target])):
                    return "gates() reassigns `bad` after residue_reasons — its reasons are discarded"
            return None
    return "gates() has no top-level `bad.extend(residue_reasons(((\"jp\", jp), (\"en\", en), (\"zh\", zh))))`"


def main() -> int:
    failures = []

    # 1. The Python rule against the Swift test's own cases — and the reader against a Swift file
    #    with a case moved outside the lists, which it must refuse to read.
    swift_source = SWIFT_TEST.read_text(encoding="utf-8")
    try:
        damaged, clean = swift_cases(swift_source)
    except Unreadable as exc:
        failures.append(f"could not read the Swift test's cases: {exc}")
        damaged, clean = [], []
    # A parse that found nothing would agree with everything.
    if len(damaged) < 10 or len(clean) < 10:
        failures.append(f"read only {len(damaged)} damaged / {len(clean)} clean cases from the Swift test")
    for text in damaged:
        if escape_residue(text) is None:
            failures.append(f"corpus_io missed a case the Swift test flags: {text!r}")
    for text in clean:
        if escape_residue(text) is not None:
            failures.append(f"corpus_io flags a case the Swift test accepts: {text!r}")
    moved = swift_source.replace('        ]\n        for text in damaged',
                                 '        ] + ["it\'\'s"]\n        for text in damaged', 1)
    if moved == swift_source:
        failures.append("could not build the moved-case copy of the Swift test — update this check")
    else:
        try:
            swift_cases(moved)
            failures.append("the Swift-case reader accepted a case written after `] + [` — "
                            "it would skip it silently")
        except Unreadable:
            pass

    for label, literal in (("a raw literal", '#"it\'\'s"#'), ("a multi-line literal", '"""\n  it\'s\n  """')):
        mutant = swift_source.replace('        ]\n        for text in damaged',
                                      f'            {literal},\n        ]\n        for text in damaged', 1)
        try:
            swift_cases(mutant)
            failures.append(f"the Swift-case reader accepted {label} in the damaged list")
        except Unreadable:
            pass

    # 2. gen_passages: a paragraph that passes every other check, then the same paragraph with
    #    3e9407a's damage in each translation in turn.
    passages = load("gen_passages")
    item = {
        "display": "あさ、まどをあけると、にわはいちめんまっしろなゆきでした。"
                   "しずかなまちに、とおくをはしるでんしゃのおとだけがひびいています。",
        "en": "I'm surprised: when I opened the window this morning, the garden was white with snow.",
        "zh": "早上打开窗户，院子里一片雪白。安静的街上只回荡着远处电车的声音。",
    }
    _, problem = passages.validate(item, set())
    if problem:
        failures.append(f"gen_passages control item was refused ({problem}) — the fixture is wrong, "
                        "so the refusals below prove nothing")
    for lang, bad in (("en", item["en"].replace("'", "'''")), ("zh", item["zh"] + "\\")):
        _, problem = passages.validate({**item, lang: bad}, set())
        # The refusal must be THIS one: "kana length 50" contains "en", and a first draft of this
        # test passed on it.
        if not (problem or "").startswith(f"{lang} carries "):
            failures.append(f"gen_passages.validate accepted residue in {lang}: {bad!r} → {problem!r}")

    # gen_examples: the same, one sentence.
    sys.argv = ["gen_examples"]
    examples = load("gen_examples")
    entry = {"surface": "水", "kana": "みず", "pos": ["n"]}
    item = {"exJP": "水を飲みます。", "exEN": "I'm drinking water.", "exZH": "我在喝水。"}
    problem = examples.validate(item, entry, set())
    if problem:
        failures.append(f"gen_examples control item was refused ({problem}) — fix the fixture")
    for key, bad in (("exEN", "I'''m drinking water."), ("exZH", "我在喝&quot;水&quot;。"),
                     ("exJP", "水を\\飲みます。")):
        problem = examples.validate({**item, key: bad}, entry, set())
        if not (problem or "").startswith(f"{key} carries "):
            failures.append(f"gen_examples.validate accepted residue in {key}: {bad!r} → {problem!r}")

    # 3. residue_reasons, behaviourally: every damaged field, in order, in the generators' words;
    #    the clean field absent. The `why` halves come from escape_residue, which step 1 has
    #    already held to the Swift test's cases.
    fields = (("jp", "水を\\飲みます。"), ("en", "I'''m drinking water."), ("zh", "我在喝水。"))
    expected = [f"jp carries {escape_residue(fields[0][1])}", f"en carries {escape_residue(fields[1][1])}"]
    if residue_reasons(fields) != expected:
        failures.append(f"residue_reasons{fields!r} → {residue_reasons(fields)!r}, expected {expected!r}")
    if residue_reasons((("jp", "水を飲みます。"), ("en", "I'm drinking water."), ("zh", "我在喝水。"))):
        failures.append("residue_reasons refused a clean sentence")
    # ...and pilot_gate.gates calls it. The pin must be seen to fail without the call, or a
    # pin that matched nothing would pass here forever.
    pilot_source = PILOT_GATE.read_text(encoding="utf-8")
    if why := pilot_gate_pin(pilot_source):
        failures.append(f"pilot_gate: {why}")
    stripped = "\n".join(line for line in pilot_source.splitlines()
                         if "residue_reasons((" not in line)
    commented = "\n".join(("# " + line) if "residue_reasons((" in line else line
                          for line in pilot_source.splitlines())
    lines = pilot_source.splitlines()
    call_line = next((i for i, line in enumerate(lines) if "bad.extend(residue_reasons((" in line), None)
    return_line = next((i for i, line in enumerate(lines) if line.strip() == "return bad"
                        and call_line is not None and i > call_line), None)
    if call_line is None or return_line is None:
        failures.append("could not build the pilot_gate dead-code and discard mutants — update this check")
        dead = discarded = pilot_source
    else:
        indent = lines[call_line][: len(lines[call_line]) - len(lines[call_line].lstrip())]
        dead = "\n".join(lines[:call_line] + lines[call_line + 1:return_line + 1]
                         + [lines[call_line]] + lines[return_line + 1:])
        discarded = "\n".join(lines[:call_line + 1] + [indent + "bad = []"] + lines[call_line + 1:])
    for label, mutant in (("removed", stripped), ("commented out", commented),
                          ("moved after the final return", dead), ("followed by bad = []", discarded)):
        if mutant == pilot_source or pilot_gate_pin(mutant) is None:
            failures.append(f"the pilot_gate pin still passes with the call {label} — it pins nothing")

    # 4. import_review_sheets: a damaged correction is refused as a whole row and reported as a
    #    SKIP, like every other rejected row; a clean one is applied.
    sheets = load("import_review_sheets")

    def vocab():
        return {"v1": {"id": "v1", "kana": "みず", "surface": "水", "pos": ["n"],
                       "meanings": {"en": ["water"], "zh": ["水"]}}}

    def passage():
        return {"p1": {"id": "p1", "display": "みずをのみます。", "kana": "みずをのみます",
                       "topic": "daily", "meanings": {"en": "I drink water.", "zh": "我喝水。"}}}

    for apply_row, entries, fname, correction, field in (
        (sheets.apply_vocab_row, vocab, "n5", "en: isn'''t it cold", "en"),
        (sheets.apply_vocab_row, vocab, "n5", "I'''m thirsty", "en"),           # bare text → en
        (sheets.apply_vocab_row, vocab, "n5", "kana: みず | zh: 冷&quot;水&quot;", "zh"),
        (sheets.apply_vocab_row, vocab, "n5", "surface: 水\\", "surface"),
        (sheets.apply_vocab_row, vocab, "n5", "pos: n&amp;v", "pos"),
        (sheets.apply_passage_row, passage, "passages", "display: みずを\\のみます。", "display"),
        (sheets.apply_passage_row, passage, "passages", "zh: 我喝\"\"水\"\"。", "zh"),
        (sheets.apply_passage_row, passage, "passages", "kana: みず | en: it''s water", "en"),
        (sheets.apply_vocab_row, vocab, "n5", "kana: みず\\", "kana"),
        (sheets.apply_passage_row, passage, "passages", "topic: daily&amp;life", "topic"),
    ):
        changes = sheets.Changes()
        rid = next(iter(entries()))
        apply_row({"id": rid, "status": "fix", "correction": correction}, entries(), fname, changes)
        out = io.StringIO()
        # write_back looks up every file a recorded fix lands in, and is given no files here: with
        # the refusal broken it would stop on a KeyError naming neither the correction nor the
        # field. A recorded fix already IS the failure, so say it in the words below instead.
        if not changes.fixes:
            with contextlib.redirect_stdout(out):
                sheets.write_back(changes, {}, apply=False)
        if changes.fixes or f"SKIP {fname} {rid}: correction refused: {field} carries " not in out.getvalue():
            failures.append(f"import_review_sheets did not refuse {correction!r}: fixes={changes.fixes!r}, "
                            f"printed {out.getvalue()!r}")
    for apply_row, entries, fname, correction, want in (
        (sheets.apply_vocab_row, vocab, "n5", "en: cold water; chilled water",
         [("n5", "v1", "meanings.en", "water", "cold water; chilled water")]),
        (sheets.apply_passage_row, passage, "passages", "en: I'm drinking water.",
         [("passages", "p1", "meanings.en", "I drink water.", "I'm drinking water.")]),
    ):
        changes = sheets.Changes()
        rid = next(iter(entries()))
        apply_row({"id": rid, "status": "fix", "correction": correction}, entries(), fname, changes)
        if changes.fixes != want or changes.unparsed:
            failures.append(f"import_review_sheets control {correction!r} was not applied: "
                            f"fixes={changes.fixes!r}, unparsed={changes.unparsed!r}")

    if failures:
        print("\n".join(f"FAIL  {f}" for f in failures))
        return 1
    print(f"ok — {len(damaged)} damaged and {len(clean)} clean cases agree with the Swift test "
          "(every literal in it accounted for); gen_passages, gen_examples, pilot_gate (jp/en/zh) "
          "and import_review_sheets refuse residue in every field they check")
    return 0


if __name__ == "__main__":
    sys.exit(main())
