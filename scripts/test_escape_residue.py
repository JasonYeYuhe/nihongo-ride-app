#!/usr/bin/env python3
"""The generators refuse quoting residue in a translation before they merge it.

3e9407a shipped 20 apostrophes as `'''` in 18 Practice translations; the v1.34 iPad simulator
pass saw "I'''m" and "father'''s" on screen. Gemini's own output was clean — the tripling
happened in a hand-run merge step, the signature of a shell-quoted `'\\''` read back by an
interpreter that takes `\\'` as `'`. `Tests/VocabKitTests/CorpusEscapeResidueTests.swift` holds
every shipped corpus string to the rule and is the authority. This proves two narrower things:

  1. `corpus_io.escape_residue` — the generators' copy of the rule — agrees with the Swift test
     on every calibration case the Swift test lists. The cases are READ FROM THE SWIFT FILE, not
     copied here, so a case added on either side is checked on both. (It compares the two rules
     only on those cases: a change to one rule that no listed case exercises would pass here.)
  2. `gen_passages.validate` and `gen_examples.validate` actually call it: an item each accepts
     is refused once the batch's own damage is put into its translation.

Run: python3 scripts/test_escape_residue.py
"""
import importlib.util
import json
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
SWIFT_TEST = HERE.parent / "Tests/VocabKitTests/CorpusEscapeResidueTests.swift"
sys.path.insert(0, str(HERE))
from corpus_io import escape_residue   # noqa: E402


def load(name):
    spec = importlib.util.spec_from_file_location(name, HERE / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def swift_cases(name):
    """The string literals of `let <name> = [ … ]` in the Swift test.

    Swift and JSON agree on the only escapes these literals use (\\\\, \\", \\n), so each one
    decodes with json.loads. A literal using anything else fails loudly here rather than being
    read wrong.
    """
    source = SWIFT_TEST.read_text(encoding="utf-8")
    block = re.search(rf"let {name} = \[(.*?)\n\s*\]", source, re.S)
    if not block:
        raise SystemExit(f"no `let {name} = [` in {SWIFT_TEST.name} — the test moved; update this")
    return [json.loads(literal) for literal in re.findall(r'"(?:[^"\\\n]|\\.)*"', block.group(1))]


def main() -> int:
    failures = []

    damaged, clean = swift_cases("damaged"), swift_cases("clean")
    # A parse that found nothing would agree with everything.
    if len(damaged) < 10 or len(clean) < 10:
        failures.append(f"read only {len(damaged)} damaged / {len(clean)} clean cases from the Swift test")
    for text in damaged:
        if escape_residue(text) is None:
            failures.append(f"corpus_io missed a case the Swift test flags: {text!r}")
    for text in clean:
        if escape_residue(text) is not None:
            failures.append(f"corpus_io flags a case the Swift test accepts: {text!r}")

    # gen_passages: a paragraph that passes every other check, then the same paragraph with
    # 3e9407a's damage in each translation in turn.
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

    if failures:
        print("\n".join(f"FAIL  {f}" for f in failures))
        return 1
    print(f"ok — {len(damaged)} damaged and {len(clean)} clean cases agree with the Swift test; "
          "both generators refuse residue in every translation field")
    return 0


if __name__ == "__main__":
    sys.exit(main())
