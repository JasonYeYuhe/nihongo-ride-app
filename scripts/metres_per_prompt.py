"""How far is one prompt worth, per mode?

`GameSession.swift:775` is the whole formula: `distanceMeters += Double(entry.kana.count) * 10`.
A prompt's distance is therefore 10 m per kana of whatever string that mode puts in `kana` —
the headword for word modes, `exampleKana` for sentence/dictation (`sentenceSession`, :538), and
the passage text for Practice.

Measured over the shipped resources, so the numbers are the app's, not an estimate.
"""
import json, glob, statistics

def kana_lengths_words():
    out = []
    for path in sorted(glob.glob("Sources/VocabKit/Resources/n*.json")):
        d = json.load(open(path))
        items = d if isinstance(d, list) else d.get("entries", [])
        for e in items:
            k = e.get("kana")
            if k:
                out.append(len(k))
    return out

def kana_lengths_sentences():
    out = []
    for path in sorted(glob.glob("Sources/VocabKit/Resources/n*.json")):
        d = json.load(open(path))
        items = d if isinstance(d, list) else d.get("entries", [])
        for e in items:
            k = e.get("exKana")
            if k:
                out.append(len(k))
    return out

def kana_lengths_passages():
    d = json.load(open("Sources/VocabKit/Resources/passages.json"))
    items = d if isinstance(d, list) else d.get("passages", [])
    by_level = {}
    for p in items:
        k = p.get("kana") or p.get("textKana") or p.get("text") or ""
        lvl = p.get("level") or p.get("length") or "?"
        by_level.setdefault(lvl, []).append(len(k))
    return by_level

def row(name, lengths):
    if not lengths:
        return f"{name:<28} (no data)"
    mean = statistics.mean(lengths)
    return (f"{name:<28} n={len(lengths):<6} mean kana={mean:6.1f}  "
            f"→ {mean*10:7.0f} m per prompt   (median {statistics.median(lengths)*10:.0f} m)")

words = kana_lengths_words()
sentences = kana_lengths_sentences()
print(row("word modes (headword)", words))
print(row("sentence / dictation", sentences))
for lvl, lens in sorted(kana_lengths_passages().items()):
    print(row(f"passage · {lvl}", lens))

print()
KYOTO = 25_000
print(f"Kyōto is at {KYOTO:,} m (RideRoute.swift:174), and arriving there is what opens the")
print("second offer entrance (AppModel:2273 `openedANewOffer`).")
print()
for name, lengths, prompts in [
    ("journey / word run", words, [12, 20]),
    ("sentence or dictation run", sentences, [5, 12]),
]:
    if not lengths:
        continue
    per = statistics.mean(lengths) * 10
    for n in prompts:
        runs = KYOTO / (per * n)
        print(f"  {name:<26} {n:>2} prompts × {per:5.0f} m = {per*n:7.0f} m/run "
              f"→ {runs:5.1f} runs to Kyōto")
