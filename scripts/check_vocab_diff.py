#!/usr/bin/env python3
"""Guard a vocabulary data change: only the fields a batch is allowed to touch may move.

Codex's review of PLAN-V1.17 asked for this and was right that nothing enforced it. `swift
test` checks that readings stay globally unique; it does not check that a merge left the
readings alone in the first place, and nothing at all checked that a gloss list only grew.

Two contracts, chosen because the ways this data can be silently corrupted are specific:

**Identity is frozen.** `id`, `surface`, `kana`, `jlpt`, `vc` must be byte-identical. A merge
that edits `kana` re-teaches a word without anyone noticing — the app grades against the new
reading and every SRS card for that word silently changes meaning.

**Meanings are append-only and order-preserving.** The old list must be a PREFIX of the new
one, not merely a subset. Preserving the set is not enough: the displayed gloss line is built
by joining in order, so a reorder changes what a learner reads first, and — if a display bound
is ever added — changes which glosses are visible at all. An entry that already shipped an
example has that example explained by its glosses in their current order; reordering them
re-explains a sentence nobody re-reviewed.

Examples are write-once: a batch may fill an empty exJP/exEN/exZH/exKana/exTokens, never
overwrite a non-empty one, because an overwrite replaces reviewed content with unreviewed
content.

`exKana` and `exTokens` were unguarded until v1.21 and should not have been. `exKana` is not
decoration: it is the string sentence mode grades a learner's typing against, and — as of
v1.21 §A — the answer a DICTATION prompt is marked against. A silent rewrite there marks a
learner wrong for typing what they were correctly told to type, which is the same class of
harm as a rewritten `kana` and was the only field of that class with no rule at all.

    python3 scripts/check_vocab_diff.py                 # working tree vs HEAD
    python3 scripts/check_vocab_diff.py --base <ref>    # vs another commit
"""
import argparse
import json
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
FROZEN = ("surface", "kana", "jlpt", "vc")
EXAMPLE_FIELDS = ("exJP", "exEN", "exZH", "exKana", "exTokens")


def at_ref(ref, path):
    rel = str(Path(path).relative_to(REPO))
    out = subprocess.run(["git", "-C", str(REPO), "show", f"{ref}:{rel}"],
                         capture_output=True, text=True)
    if out.returncode != 0:
        return None                       # new file: nothing to compare against
    return json.loads(out.stdout)


def _normalised(value):
    """A field value reduced to something comparable, for both strings and token lists."""
    if value is None:
        return None
    if isinstance(value, str):
        return value.strip() or None
    return value or None


def dedupe(items):
    seen, out = set(), []
    for x in items:
        if x not in seen:
            seen.add(x)
            out.append(x)
    return out


def check(path, base, allow_dedupe=False, manifest=None):
    old = at_ref(base, path)
    if old is None:
        return []
    new = json.load(open(path))
    problems = []
    by_id_old = {e["id"]: e for e in old}
    by_id_new = {e["id"]: e for e in new}

    for missing in sorted(set(by_id_old) - set(by_id_new)):
        declared = manifest.get(missing) if manifest else None
        # Retiring an entry is the most destructive change available: SRSCard.id IS
        # VocabEntry.id, so the learner's card for it becomes unreachable. It is allowed only
        # when the manifest names the id AND names the entry that replaces it, so the record
        # always says where a retired word's learners are supposed to go.
        if declared and declared.get("retire") and declared.get("replacedBy"):
            continue
        problems.append(f"{missing}: entry DELETED")
    for added in sorted(set(by_id_new) - set(by_id_old)):
        problems.append(f"{added}: entry ADDED (this guard expects merges, not new words)")

    for eid in sorted(set(by_id_old) & set(by_id_new)):
        a, b = by_id_old[eid], by_id_new[eid]
        for field in FROZEN:
            if a.get(field) != b.get(field):
                problems.append(f"{eid}: {field} changed {a.get(field)!r} -> {b.get(field)!r}")

        for lang, before in (a.get("meanings") or {}).items():
            after = (b.get("meanings") or {}).get(lang) or []
            declared = manifest.get(eid) if manifest else None
            removals = set(declared.get("remove" + lang.upper(), [])) if declared else set()
            if declared is not None:
                unexpected = [g for g in before if g not in after and g not in removals]
                if unexpected:
                    problems.append(
                        f"{eid}: meanings.{lang} lost {unexpected!r}, which the manifest "
                        f"did not declare")
                missed = [g for g in removals if g in after]
                if missed:
                    problems.append(
                        f"{eid}: manifest promised to remove {missed!r} from meanings.{lang} "
                        f"but they are still there")
            # A duplicate is not a sense, so dropping one loses nothing a learner could read.
            # `--allow-dedupe` permits exactly that removal and nothing else: the comparison
            # still runs, just against the de-duplicated old list. Every other removal, edit
            # or reorder stays a failure.
            #
            # This runs for manifest-declared entries TOO, minus the glosses they declared.
            # It used to `continue` past this point, which meant naming an entry in a manifest
            # for a Chinese fix silently switched OFF the append-only and duplicate rules for
            # its English — a reorder or a duplicated gloss on a declared entry passed clean.
            # A manifest is permission for the changes it names, not an exemption from the
            # guard. (Measured and closed in v1.21 §D.)
            expect = [g for g in (dedupe(before) if allow_dedupe else before)
                      if g not in removals]
            trimmed = [g for g in after if g not in removals]
            if trimmed[:len(expect)] != expect:
                problems.append(
                    f"{eid}: meanings.{lang} is not append-only — was {before!r}, now {after!r}")
            if len(after) != len(set(after)):
                problems.append(f"{eid}: meanings.{lang} has a duplicate gloss: {after!r}")
        for lang in set(b.get("meanings") or {}) - set(a.get("meanings") or {}):
            problems.append(f"{eid}: meanings gained a whole new language {lang!r}")

        for field in EXAMPLE_FIELDS:
            # exTokens is a list of [surface, reading] pairs; the rest are strings. Normalise
            # both to "empty or not, and equal or not" rather than assuming a string, because
            # a .strip() on the token list is a TypeError, not a passing check.
            was, now = _normalised(a.get(field)), _normalised(b.get(field))
            if was and now != was:
                declared = manifest.get(eid) if manifest else None
                # A reviewed translation correction is still an overwrite, so it still has to
                # be declared field by field. The guard does not care that the new text is
                # better; it cares that somebody said in advance which fields would move.
                if declared and field in (declared.get("rewrite") or []):
                    continue
                problems.append(f"{eid}: {field} OVERWRITTEN (was reviewed) {was!r} -> {now!r}")
    return problems


def load_manifest(path):
    """A reviewed structural change declares itself up front.

    The append-only rule exists to stop a batch merge from silently dropping content. It is not
    meant to make a genuine correction impossible — 下/げ shipped with した's glosses, so the app
    showed two different words the same definition, and fixing that REQUIRES a removal.

    So a structural change is not exempted from the guard; it is checked against a manifest.
    Every id it touches and every gloss it removes must be listed, and anything the diff does
    that the manifest did not predict is still a failure. The guard gets stricter, not weaker:
    it now also fails if the manifest promises a change that did not happen.
    """
    m = json.load(open(path))
    return {e["id"]: e for e in m["entries"]}, m.get("reason", "")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="HEAD")
    ap.add_argument("--manifest",
                    help="JSON declaring a reviewed structural change: "
                         '{"reason": "...", "entries": [{"id": ..., "removeEN": [...], '
                         '"removeZH": [...]}]}')
    ap.add_argument("--allow-dedupe", action="store_true",
                    help="permit removing an EXACT duplicate gloss and nothing else")
    args = ap.parse_args()

    manifest, reason = (load_manifest(args.manifest) if args.manifest else (None, ""))
    if manifest:
        print(f"structural change declared: {reason}")
        print(f"  {len(manifest)} entries listed\n")

    total = 0
    for path in sorted((REPO / "Sources/VocabKit/Resources").glob("n[1-5].json")):
        problems = check(path, args.base, args.allow_dedupe, manifest)
        total += len(problems)
        mark = "FAIL" if problems else "ok  "
        print(f"{mark} {path.name}: {len(problems)} problem(s)")
        for p in problems[:40]:
            print(f"       {p}")
    if total:
        print(f"\n{total} problem(s) — this change is not an additive merge.")
        return 1
    print("\nclean: identity frozen, meanings append-only, examples not overwritten.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
