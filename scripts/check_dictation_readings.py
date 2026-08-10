#!/usr/bin/env python3
"""Does AVSpeech read each example sentence the way its own exKana says it reads?

PLAN-V1.21 §A gates dictation on this. Dictation plays a synthesizer's reading of the
KANJI sentence and grades the learner against `exKana`, so any sentence where those two
disagree marks a learner wrong for typing exactly what they heard.

THE PLAN EXPECTED A SAMPLED LISTENING PASS, because no API returns what AVSpeech *will*
say. That premise is true and was checked rather than assumed:

  * `AVSpeechSynthesisMarker` (macOS 14+) does carry a `.phoneme` mark — but every
    Japanese voice on this machine emits only `.word` markers, with an empty phoneme.
  * The legacy `NSSpeechSynthesizer.phonemes(from:)` returns empty for every ja voice.
    It also returns empty for an ENGLISH voice, which is the only reason we know the API
    is dead on macOS 26 rather than unsupported for Japanese. Probing only the case you
    care about would have produced a confident wrong conclusion.

So the reading is measured instead of read out, which covers the whole corpus rather
than a sample. Two instruments, and the difference between them is the whole point.

INSTRUMENT 1 — PROOF, by byte-identical audio. Kyoko is deterministic, and two texts
that render to the same WAV were converted to the same phoneme sequence. So if the kana
spelling renders to the same bytes as the kanji sentence, the synthesizer said exactly
that; and if some single-token READING SUBSTITUTION does instead, it said that. This is
proof, not inference. Its weakness is recall: kanji and kana can differ in phrasing
while saying the same words, so non-identity proves nothing, and only 521 of 6,723
sentences fall in the class where the test can speak at all.

INSTRUMENT 2 — NEAREST HYPOTHESIS. Render exKana and every single-token reading variant,
and ask which one the kanji render is nearest (log-mel + DTW). Covers everything, but
argmin is only meaningful when some candidate is close; when the true reading is not in
the candidate set the ordering is arbitrary.

A PLAIN ABSOLUTE THRESHOLD was built first and thrown away: distance(exJP, exKana)
against a cutoff. Kanji and kana are parsed into different phrases, so prosody alone put
honest pairs on top of dishonest ones — at the threshold catching 96% of known-bad, 80%
of known-good was flagged too.

CALIBRATION, AND WHY THE FIRST ONE WAS WRONG. Instrument 2 was first calibrated with
synthetic decoys (a token's reading replaced by random kana), which put its false-positive
rate at 4.3-5.1% per candidate — enough to make its 15.6% flag rate look like mostly
noise. But instrument 1 produces something better than synthetic decoys: 494 sentences
PROVEN to match and 27 PROVEN to differ, i.e. real labelled data. Measured against those:

    recall           27/27  = 100%   (every proven mismatch was flagged)
    false positives  8/494  =  1.6%  (not the 4.7% the decoys predicted)

Random kana turn out to be a harder test than real alternative readings. Calibrating on
the wrong population would have made a working instrument look broken — the same shape of
error as trusting one that is broken.

THE PARTICLES. exKana spells the topic particle は and the direction particle へ
orthographically, because it is the TYPING target. Kyoko reads a bare hiragana は as
"ha" in some parses and "wa" in others, so NEITHER fixed respelling is right — both are
tried, and the learner types は regardless because that is what exKana says. (This is
also why dictation SPEAKS exJP rather than exKana, which would look like the safe choice
and would mispronounce the particle in ~2,900 sentences.)

WHAT SHIPS. The exclusion list is the union of every sentence instrument 2 flags and
every sentence containing a word-reading pair instrument 1 PROVED is spoken differently
— proof about a word propagates to every sentence using that word, because a voice does
not change its mind between sentences. 1,059 of 6,723 (15.8%), leaving 5,664 across all
five levels, none below 79% kept. Flagging is one-sided on purpose: a false flag costs
one sentence of dictation coverage, a miss ships an item whose audio contradicts its own
answer.

    ./.venv-jp/bin/python scripts/check_dictation_readings.py --render     # ~50 min
    ./.venv-jp/bin/python scripts/check_dictation_readings.py --report
    ./.venv-jp/bin/python scripts/check_dictation_readings.py --calibrate
    ./.venv-jp/bin/python scripts/check_dictation_readings.py --write

Needs the project venv (Sudachi, numpy, scipy). Audio is cached in .dictation-wav/,
which is gitignored — the ~37k clips are reproducible, not source.
"""
import argparse
import collections
import hashlib
import itertools
import json
import os
import subprocess
import sys
import warnings
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np
from scipy.io import wavfile

warnings.filterwarnings("ignore", category=wavfile.WavFileWarning)

REPO = Path(__file__).resolve().parent.parent
RESOURCES = REPO / "Sources/VocabKit/Resources"
CACHE = Path(os.environ.get("DICTATION_WAV_CACHE", REPO / ".dictation-wav"))
KATA_TO_HIRA = {chr(c): chr(c - 0x60) for c in range(0x30A1, 0x30F7)}
KANA_RANGE = ("぀", "ヿ")

SYNTH_SWIFT = r'''
// Renders AVSpeech ja-JP audio to WAV WITHOUT playing it: write(_:toBufferCallback:)
// produces buffers rather than sound, so a full-corpus sweep is silent.
import Foundation
import AVFoundation

final class Sink: NSObject, AVSpeechSynthesizerDelegate {
    var done = false
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) { done = true }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) { done = true }
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
guard let voice = AVSpeechSynthesisVoice(language: "ja-JP") else { print("NO_VOICE"); exit(1) }
FileHandle.standardError.write("voice=\(voice.identifier)\n".data(using: .utf8)!)

while let line = readLine(strippingNewline: true) {
    let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
    guard parts.count == 2 else { continue }
    let url = URL(fileURLWithPath: outDir).appendingPathComponent("\(parts[0]).wav")
    let synth = AVSpeechSynthesizer()
    let sink = Sink()
    synth.delegate = sink
    let utt = AVSpeechUtterance(string: parts[1])
    utt.voice = voice
    utt.rate = 0.5
    var file: AVAudioFile?
    synth.write(utt) { buffer in
        guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else { return }
        if file == nil {
            var settings = pcm.format.settings
            settings[AVFormatIDKey] = kAudioFormatLinearPCM
            file = try? AVAudioFile(forWriting: url, settings: settings,
                                    commonFormat: pcm.format.commonFormat,
                                    interleaved: pcm.format.isInterleaved)
        }
        try? file?.write(from: pcm)
    }
    let deadline = Date().addingTimeInterval(30)
    while !sink.done, Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
    file = nil
    print(parts[0])
    fflush(stdout)
}
'''


# --- rendering ----------------------------------------------------------------------

def synth_binary():
    CACHE.mkdir(parents=True, exist_ok=True)
    binary, source = CACHE / "synth", CACHE / "synth.swift"
    if not (binary.exists() and source.exists() and source.read_text() == SYNTH_SWIFT):
        source.write_text(SYNTH_SWIFT)
        subprocess.run(["swiftc", "-O", str(source), "-o", str(binary)], check=True)
    return binary


def key(text):
    return hashlib.sha1(text.encode("utf-8")).hexdigest()[:16]


def clip(text):
    return CACHE / f"{key(text)}.wav"


def render(texts, workers=8):
    todo, seen = [], set()
    for t in texts:
        k = key(t)
        if k in seen:
            continue
        seen.add(k)
        if not clip(t).exists():
            todo.append((k, t))
    if not todo:
        return 0
    binary = synth_binary()

    def run(chunk):
        if chunk:
            subprocess.run([str(binary), str(CACHE)],
                           input="".join(f"{k}\t{t}\n" for k, t in chunk).encode("utf-8"),
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)

    with ThreadPoolExecutor(max_workers=workers) as ex:
        list(ex.map(run, [todo[i::workers] for i in range(workers)]))
    return len(todo)


# --- instrument 1: proof by byte-identical audio -------------------------------------

_sha = {}


def sha(path):
    path = str(path)
    if path not in _sha:
        try:
            _sha[path] = hashlib.sha1(Path(path).read_bytes()).hexdigest()
        except FileNotFoundError:
            _sha[path] = None
    return _sha[path]


def kana_only(s):
    return "".join(c for c in s if KANA_RANGE[0] <= c <= KANA_RANGE[1])


def particle_slots(tokens):
    """Standalone particle は/へ positions, each with both spellings to try."""
    out = []
    for i, (surface, reading) in enumerate(tokens):
        if surface == "は" and reading == "は":
            out.append((i, ("は", "わ")))
        elif surface == "へ" and reading == "へ":
            out.append((i, ("へ", "え")))
    return out


def variants(tokens, substitution=None):
    """Every particle spelling of this sentence's reading, optionally with one token
    replaced. De-duplicated, order preserved."""
    base = [r for _, r in tokens]
    if substitution:
        base[substitution[0]] = substitution[1]
    slots = particle_slots(tokens)
    out = []
    for combo in (itertools.product(*[o for _, o in slots]) if slots else [()]):
        v = list(base)
        for (i, _), choice in zip(slots, combo):
            v[i] = choice
        out.append(kana_only("".join(v)))
    return list(dict.fromkeys(out))


# --- instrument 2: nearest hypothesis ------------------------------------------------

N_MELS, N_FFT, HOP = 40, 512, 160
_mel_cache, _bank_cache = {}, {}


def _melbank(sr, n_bins):
    if (sr, n_bins) in _bank_cache:
        return _bank_cache[(sr, n_bins)]

    def hz2mel(f):
        return 2595 * np.log10(1 + f / 700)

    def mel2hz(m):
        return 700 * (10 ** (m / 2595) - 1)

    pts = mel2hz(np.linspace(hz2mel(50), hz2mel(sr / 2), N_MELS + 2))
    bins = np.floor((N_FFT + 1) * pts / sr).astype(int)
    fb = np.zeros((N_MELS, n_bins))
    for m in range(N_MELS):
        l, c, r = bins[m], max(bins[m + 1], bins[m] + 1), bins[m + 2]
        r = min(max(r, c + 1), n_bins - 1)
        c = min(c, r)
        if c > l:
            fb[m, l:c] = (np.arange(l, c) - l) / (c - l)
        if r > c:
            fb[m, c:r] = (r - np.arange(c, r)) / (r - c)
    _bank_cache[(sr, n_bins)] = fb
    return fb


def logmel(path):
    path = str(path)
    if path in _mel_cache:
        return _mel_cache[path]
    try:
        sr, x = wavfile.read(path)
    except Exception:
        _mel_cache[path] = None
        return None
    if x.ndim > 1:
        x = x.mean(axis=1)
    x = (x.astype(np.float64) / 32768.0 if np.issubdtype(x.dtype, np.integer)
         else x.astype(np.float64))
    if x.size:
        nz = np.nonzero(np.abs(x) > max(1e-4, np.abs(x).max() * 0.01))[0]
        if len(nz):
            x = x[nz[0]:nz[-1] + 1]
    if len(x) < N_FFT:
        _mel_cache[path] = None
        return None
    n = 1 + (len(x) - N_FFT) // HOP
    idx = np.arange(N_FFT)[None, :] + HOP * np.arange(n)[:, None]
    spec = np.abs(np.fft.rfft(x[idx] * np.hanning(N_FFT)[None, :], axis=1)) ** 2
    mel = np.log(spec @ _melbank(sr, spec.shape[1]).T + 1e-10)
    mel = (mel - mel.mean(axis=0)) / (mel.std(axis=0) + 1e-8)
    _mel_cache[path] = mel / (np.linalg.norm(mel, axis=1, keepdims=True) + 1e-8)
    return _mel_cache[path]


def dtw(a, b):
    """DTW over cosine distance, normalised by the path-length bound.

    Exact but vectorised: cur[j] = d[j] + min(prev[j], prev[j-1], cur[j-1]) splits into a
    vectorised part and a running minimum, and subtracting the running sum of d turns that
    running minimum into np.minimum.accumulate.
    """
    if a is None or b is None or len(a) == 0 or len(b) == 0:
        return None
    d = 1.0 - a @ b.T
    n, m = d.shape
    prev = np.full(m + 1, np.inf)
    prev[0] = 0.0
    for i in range(n):
        row = d[i]
        cs = np.cumsum(row)
        base = row + np.minimum(prev[1:], prev[:-1])
        prev = np.concatenate(([np.inf], np.minimum.accumulate(base - cs) + cs))
    return float(prev[-1] / (n + m))


# --- the corpus ----------------------------------------------------------------------

def to_hira(s):
    return "".join(KATA_TO_HIRA.get(c, c) for c in s)


def build_rows():
    entries = []
    for f in sorted(RESOURCES.glob("n[1-5].json")):
        entries += json.loads(f.read_text(encoding="utf-8"))
    typeable = [e for e in entries
                if e.get("exJP") and e.get("exKana") and e.get("exTokens")]

    corpus = collections.defaultdict(set)
    for e in entries:
        corpus[e["surface"]].add(e["kana"])

    try:
        from sudachipy import Dictionary
    except ImportError:
        sys.exit("sudachipy missing — run with ./.venv-jp/bin/python")
    dic, lex = Dictionary(), {}

    def readings(surface):
        if surface not in lex:
            try:
                lex[surface] = {to_hira(m.reading_form()) for m in dic.lookup(surface)} - {""}
            except Exception:
                lex[surface] = set()
        return lex[surface]

    rows = []
    for e in typeable:
        tokens = [list(t) for t in e["exTokens"]]
        subs = []
        for i, (surface, reading) in enumerate(tokens):
            if not any("一" <= c <= "鿿" for c in surface):
                continue          # kana and punctuation read as themselves
            for alt in sorted((readings(surface) | corpus.get(surface, set())) - {reading}):
                subs.append({"i": i, "surface": surface, "from": reading, "to": alt})
        rows.append({"id": e["id"], "jlpt": e["jlpt"], "exJP": e["exJP"],
                     "exKana": e["exKana"], "tokens": tokens, "subs": subs})
    return rows


def all_texts(rows):
    for r in rows:
        yield r["exJP"]
        for v in variants(r["tokens"]):
            yield v
        for s in r["subs"]:
            for v in variants(r["tokens"], (s["i"], s["to"])):
                yield v


# --- the two passes ------------------------------------------------------------------

def prove(rows):
    """Sentences whose audio is byte-identical to some spelling of their reading."""
    proven_ok, proven_bad, unproven = [], [], []
    for r in rows:
        target = sha(clip(r["exJP"]))
        if target is None:
            continue
        if any(sha(clip(v)) == target for v in variants(r["tokens"])):
            proven_ok.append(r)
            continue
        hit = None
        for s in r["subs"]:
            if any(sha(clip(v)) == target for v in variants(r["tokens"], (s["i"], s["to"]))):
                hit = s
                break
        (proven_bad if hit else unproven).append((r, hit))
    return proven_ok, proven_bad, unproven


def nearest(rows):
    """For each sentence: its own reading's distance, and the nearest rival's."""
    out = []
    for r in rows:
        jp = logmel(clip(r["exJP"]))
        own = min([d for d in (dtw(jp, logmel(clip(v))) for v in variants(r["tokens"]))
                   if d is not None] or [None])
        if own is None:
            continue
        best = None
        for s in r["subs"]:
            for v in variants(r["tokens"], (s["i"], s["to"])):
                d = dtw(jp, logmel(clip(v)))
                if d is not None and (best is None or d < best[0]):
                    best = (d, s)
        out.append({"id": r["id"], "jlpt": r["jlpt"], "exJP": r["exJP"], "exKana": r["exKana"],
                    "own": own, "best": best[0] if best else None,
                    "says": best[1] if best else None,
                    "beaten": bool(best and best[0] < own)})
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--render", action="store_true")
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--calibrate", action="store_true")
    ap.add_argument("--write", action="store_true")
    args = ap.parse_args()

    rows = build_rows()
    print(f"sentences={len(rows)} candidates={sum(len(r['subs']) for r in rows)}")

    if args.render:
        print(f"rendering into {CACHE} …")
        print(f"rendered {render(list(all_texts(rows)))} new clips")

    if not (args.report or args.calibrate or args.write):
        return 0

    proven_ok, proven_bad, unproven = prove(rows)
    total = len(proven_ok) + len(proven_bad) + len(unproven)
    print(f"\nPROOF (byte-identical audio — decisive where it speaks at all)")
    print(f"  audio matches exKana        : {len(proven_ok)} ({100 * len(proven_ok) / total:.2f}%)")
    print(f"  audio says something else   : {len(proven_bad)} ({100 * len(proven_bad) / total:.2f}%)")
    print(f"  silent (kanji/kana phrasing): {len(unproven)} ({100 * len(unproven) / total:.2f}%)")
    for pair, n in collections.Counter(
            f"{h['surface']}: {h['from']} -> {h['to']}" for _, h in proven_bad).most_common(20):
        print(f"      {n:4d}  {pair}")

    near = nearest(rows)
    flagged = {r["id"] for r in near if r["beaten"]}
    print(f"\nNEAREST HYPOTHESIS")
    print(f"  flagged: {len(flagged)} ({100 * len(flagged) / max(1, len(near)):.2f}%)")
    for pair, n in collections.Counter(
            f"{r['says']['surface']}: {r['says']['from']} -> {r['says']['to']}"
            for r in near if r["beaten"]).most_common(15):
        print(f"      {n:4d}  {pair}")

    if args.calibrate:
        ok_ids = {r["id"] for r in proven_ok}
        bad_ids = {r["id"] for r, _ in proven_bad}
        caught = len(bad_ids & flagged)
        false_pos = len(ok_ids & flagged)
        print(f"\nCALIBRATION of the nearest-hypothesis pass against the proof pass")
        print(f"  recall          {caught}/{len(bad_ids)} = "
              f"{100 * caught / max(1, len(bad_ids)):.0f}%   (proven mismatches it flagged)")
        print(f"  false positives {false_pos}/{len(ok_ids)} = "
              f"{100 * false_pos / max(1, len(ok_ids)):.1f}%   (proven matches it flagged anyway)")
        print("  Ground truth is real labelled data, not synthetic corruption. An earlier"
              "\n  calibration with random-kana decoys put the false-positive rate at 4.7% —"
              "\n  random kana are a harder test than real alternative readings, and would"
              "\n  have made a working instrument look broken.")

    # A voice does not change its mind between sentences: a PROVEN word-level mismatch
    # applies wherever the corpus assigns that reading to that surface.
    propagated = set()
    for _, hit in proven_bad:
        for r in rows:
            if any(t[0] == hit["surface"] and t[1] == hit["from"] for t in r["tokens"]):
                propagated.add(r["id"])
    excluded = sorted(flagged | propagated)
    print(f"\nEXCLUSIONS = flagged ({len(flagged)}) union proven-word propagation "
          f"({len(propagated)}) = {len(excluded)} ({100 * len(excluded) / len(rows):.1f}%)")

    by_level = collections.defaultdict(lambda: [0, 0])
    for r in rows:
        by_level[r["jlpt"]][0] += 1
        if r["id"] in set(excluded):
            by_level[r["jlpt"]][1] += 1
    for lvl in sorted(by_level, reverse=True):
        t, x = by_level[lvl]
        print(f"    N{lvl}: {t - x} of {t} usable for dictation ({100 * (t - x) / t:.1f}%)")

    if args.write:
        says = {r["id"]: r["says"] for r in near if r["beaten"]}
        proven_by_id = {r["id"]: h for r, h in proven_bad}
        payload = {
            "measurement": "scripts/check_dictation_readings.py",
            "date": "2026-08-10",
            "voice": 'com.apple.voice.compact.ja-JP.Kyoko '
                     '(AVSpeechSynthesisVoice(language: "ja-JP"))',
            "sentences": len(rows),
            "provenMatching": len(proven_ok),
            "provenDiffering": len(proven_bad),
            "excludedCount": len(excluded),
            "note": "Excluded from DICTATION only. Every one of these is still a perfectly "
                    "good sentence to read and type in Sentence mode, where the reading is "
                    "shown rather than spoken.",
            "excluded": [],
        }
        for eid in excluded:
            row = next(r for r in rows if r["id"] == eid)
            hit = proven_by_id.get(eid) or says.get(eid)
            payload["excluded"].append({
                "id": eid,
                "exJP": row["exJP"],
                "exKana": row["exKana"],
                "heardInstead": (f"{hit['surface']} {hit['from']} -> {hit['to']}" if hit else
                                 "same word proven misread in another sentence"),
                "evidence": "proven" if eid in proven_by_id else
                            ("nearest" if eid in says else "propagated"),
            })
        out = RESOURCES / "dictation-exclusions.json"
        out.write_text(json.dumps(payload, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
        print(f"\nwrote {out}")
        detail = REPO / "docs/measurements/dictation-reading-mismatches.json"
        detail.write_text(json.dumps(payload, ensure_ascii=False, indent=1) + "\n",
                          encoding="utf-8")
        print(f"wrote {detail}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
