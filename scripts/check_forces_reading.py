#!/usr/bin/env python3
"""Does a candidate sentence FORCE the reading its entry teaches? Ask two parsers.

225 entries have no example because a naturally-written sentence containing their
spelling gets read the COMMON way, and the rule that closed the retry loop was: an
entry failing two independent generation rounds with the same defect is blocked, not
unlucky. Codex challenged that rule in v1.21 §C and the challenge was fair — two
failures are strong evidence of a systematic generator failure, not proof that an
honest example is impossible. The reason not to simply try again is also real: the
generator and the gate that judged it are both Sudachi-shaped, so "generate and
re-check" cannot decide this.

v1.21 §A produced a second parser that did not exist when these were blocked. Apple's
Japanese speech front-end is a different implementation, and Kyoko is deterministic —
so if the kanji sentence renders to the same WAV bytes as a kana spelling, that spelling
is what she read. This asks both, and reports which one is speaking:

  * PROOF (byte-identical audio) is decisive but quiet — it spoke for ~7% of the corpus.
    A no-match is the instrument being SILENT, not the voice disagreeing, and the first
    version of this script printed those as "the voice reads it another way", which was
    wrong and would have condemned three candidates on nothing.
  * COMPARATIVE (render each rival reading, ask which the kanji audio is nearest) has
    full coverage and was calibrated at 100% recall / 0% false positives against 521
    labelled sentences in v1.21 §A.

Measured on the six entries blocked for content reasons (v1.22 §B): ONE clean rescue
(未だ, both parsers agree and the audio proves it), one false rescue (違える — the
sentence uses 寝違える, a different word that merely contains the headword), and four
that stay blocked, two of them now with two independent parsers disagreeing rather than
one tool's verdict. A machine can say a sentence forces a reading; it cannot say the
sentence teaches the entry's SENSE, which is what killed the false rescue and is why
this feeds a review rather than replacing one.

    ./.venv-jp/bin/python scripts/check_forces_reading.py candidates.json

Each candidate: {id, surface, taughtReading, jp, kana, rivals: {label: rivalKana}}.
"""
import hashlib, itertools, json, os, subprocess, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from check_dictation_readings import logmel, dtw, synth_binary


def distance(a, b):
    return dtw(logmel(a), logmel(b))
HERE = Path(__file__).resolve().parent
CACHE = Path(os.environ.get("FORCES_WAV_CACHE", HERE.parent / ".dictation-wav" / "forces"))
SYNTH = Path(os.environ.get("FORCES_SYNTH", HERE.parent / ".dictation-wav" / "synth"))
def key(t): return hashlib.sha1(t.encode()).hexdigest()[:16]
def path(t): return CACHE/f"{key(t)}.wav"
def render(texts):
    CACHE.mkdir(parents=True, exist_ok=True)
    if not SYNTH.exists():
        synth_binary()          # same renderer the dictation check compiles
    todo=[(key(t),t) for t in dict.fromkeys(texts) if not path(t).exists()]
    if todo: subprocess.run([str(SYNTH), str(CACHE)],
        input="".join(f"{k}\t{t}\n" for k,t in todo).encode(),
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
def sha(t):
    try: return hashlib.sha1(path(t).read_bytes()).hexdigest()
    except FileNotFoundError: return None
def pvars(k):
    slots=[i for i,c in enumerate(k) if c in "はへ"][:6]
    out=[]
    for combo in (itertools.product(*[[k[i],{"は":"わ","へ":"え"}[k[i]]] for i in slots]) if slots else [()]):
        v=list(k)
        for i,c in zip(slots,combo): v[i]=c
        out.append("".join(v))
    return list(dict.fromkeys(out))

cands=json.loads(Path(sys.argv[1]).read_text())
texts=[]
for c in cands:
    texts.append(c["jp"]); texts+=pvars(c["kana"])
    for r in c.get("rivals",{}).values(): texts+=pvars(r)
render(texts)

from sudachipy import Dictionary, SplitMode
tk=Dictionary().create()
KATA={chr(x):chr(x-0x60) for x in range(0x30A1,0x30F7)}
for c in cands:
    print(f"\n=== {c['id']}  {c['surface']} → {c['taughtReading']} ===")
    print(f"    {c['jp']}")
    toks=[(m.surface(), "".join(KATA.get(ch,ch) for ch in m.reading_form()))
          for m in tk.tokenize(c["jp"], SplitMode.C)]
    print(f"    Sudachi: {' / '.join(f'{s}:{r}' for s,r in toks)}")
    tgt=sha(c["jp"])
    proved=any(sha(v)==tgt for v in pvars(c["kana"]))
    print(f"    AVSpeech proof (byte-identical to the taught reading): "
          f"{'YES — decisive' if proved else 'silent (no exact match; this is NOT evidence against)'}")
    if c.get("rivals"):
        own=min(distance(str(path(c['jp'])), str(path(v))) for v in pvars(c["kana"]))
        rows=[("taught: "+c["taughtReading"], own)]
        for label, rk in c["rivals"].items():
            d=min(distance(str(path(c['jp'])), str(path(v))) for v in pvars(rk))
            rows.append(("rival: "+label, d))
        rows.sort(key=lambda r: r[1])
        for lbl,d in rows: print(f"        {lbl:<28} distance {d:.5f}{'   <-- nearest' if d==rows[0][1] else ''}")
        print(f"    AVSpeech comparative verdict: "
              f"{'reads it the TAUGHT way' if rows[0][0].startswith('taught') else 'reads it the RIVAL way'}")
