#!/usr/bin/env python3
"""Does AVSpeech read each example sentence the way its own exKana says it reads?

PLAN-V1.21 §A gates dictation on this. Dictation plays a synthesizer's reading of the
KANJI sentence and grades the learner against `exKana`, so any sentence where those two
disagree marks a learner wrong for typing exactly what they heard.

WHY THIS IS NOT A LISTENING PASS BY EAR. The plan expected sampling, because no API
returns what AVSpeech *will* say. That part is true and was verified rather than
assumed:

  * `AVSpeechSynthesisMarker` (macOS 14+) does carry a `.phoneme` mark — but every
    Japanese voice on this machine emits only `.word` markers, with an empty phoneme
    string.
  * The legacy `NSSpeechSynthesizer.phonemes(from:)` returns empty for every ja voice.
    It also returns empty for an ENGLISH voice, which is the only reason we know the
    API is dead on macOS 26 rather than unsupported for Japanese. Probing only the
    case you care about would have produced a confident wrong conclusion.

So the reading is not read out of the synthesizer; it is measured. Both hypotheses are
rendered to audio and compared, which covers the whole corpus instead of a sample.

WHAT IS COMPARED, AND WHY IT IS COMPARATIVE. The obvious test — distance(audio of
exJP, audio of exKana) against a threshold — was built and thrown away. Kanji text and
kana text are parsed into different phrases, so prosody alone puts honest pairs on top
of dishonest ones: at the threshold that caught 96% of known-bad, 80% of known-good was
flagged too. What works is asking which of several candidate readings the kanji audio
is NEAREST to. The prosody residual is common to every candidate, so it cancels.

Candidates come from Sudachi's lexicon (every reading it holds for a surface, not just
the one it picked) and from the corpus's own attested readings. Sudachi is the tool
that WROTE exKana, so this is asking it to disagree with itself — which is the point:
it and AVSpeech regress to different defaults, and the corpus took Sudachi's.

THE PARTICLES. exKana spells the topic particle は and the direction particle へ
orthographically, because it is the TYPING target. Kyoko reads a bare hiragana は as
"ha" — measured: わたしはがくせいです and わたしわがくせいです render to different audio,
and the kanji 私は学生です lands nearer the わ one. Feeding exKana straight in would
therefore make ~2,900 sentences differ from their own kanji for a reason that has
nothing to do with kanji readings. `exTokens` isolates the particles, so they are
respelled before the comparison. (This is also why dictation SPEAKS exJP rather than
exKana, which would otherwise look like the safe choice.)

FLAGGING IS ONE-SIDED ON PURPOSE. A false flag costs one sentence of dictation
coverage. A miss ships a dictation item whose audio does not match its answer.

    python3 scripts/check_dictation_readings.py --render      # synthesize (slow, ~40 min)
    python3 scripts/check_dictation_readings.py --report      # compare what is rendered
    python3 scripts/check_dictation_readings.py --write       # emit the shipped exclusions

Needs the project venv for Sudachi: ./.venv-jp/bin/python.
"""
import argparse
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import warnings
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np
from scipy.io import wavfile

warnings.filterwarnings("ignore", category=wavfile.WavFileWarning)

REPO = Path(__file__).resolve().parent.parent
RESOURCES = REPO / "Sources/VocabKit/Resources"
CACHE = Path(os.environ.get("DICTATION_WAV_CACHE", REPO / ".dictation-wav"))
KATA_TO_HIRA = {chr(c): chr(c - 0x60) for c in range(0x30A1, 0x30F7)}

# --- the renderer -------------------------------------------------------------------

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


def synth_binary():
    """Compiles the renderer once into the cache dir and returns its path."""
    CACHE.mkdir(parents=True, exist_ok=True)
    binary = CACHE / "synth"
    source = CACHE / "synth.swift"
    if binary.exists() and source.exists() and source.read_text() == SYNTH_SWIFT:
        return binary
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
    chunks = [todo[i::workers] for i in range(workers)]

    def run(chunk):
        if not chunk:
            return
        payload = "".join(f"{k}\t{t}\n" for k, t in chunk)
        subprocess.run([str(binary), str(CACHE)], input=payload.encode("utf-8"),
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)

    with ThreadPoolExecutor(max_workers=workers) as ex:
        list(ex.map(run, chunks))
    return len(todo)


# --- the comparison -----------------------------------------------------------------

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
    x = x.astype(np.float64) / 32768.0 if np.issubdtype(x.dtype, np.integer) else x.astype(np.float64)
    energy = np.abs(x)
    if energy.size:
        nz = np.nonzero(energy > max(1e-4, energy.max() * 0.01))[0]
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
    mel = mel / (np.linalg.norm(mel, axis=1, keepdims=True) + 1e-8)
    _mel_cache[path] = mel
    return mel


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
        base = row + np.minimum(prev[1:], prev[:-1])
        cs = np.cumsum(row)
        prev = np.concatenate(([np.inf], np.minimum.accumulate(base - cs) + cs))
    return float(prev[-1] / (n + m))


# --- the corpus ---------------------------------------------------------------------

def to_hira(s):
    return "".join(KATA_TO_HIRA.get(c, c) for c in s)


def phonetic(tokens):
    out = []
    for surface, reading in tokens:
        if surface == "は" and reading == "は":
            out.append("わ")
        elif surface == "へ" and reading == "へ":
            out.append("え")
        else:
            out.append(reading)
    return "".join(c for c in "".join(out) if "぀" <= c <= "ヿ")


def build_rows():
    entries = []
    for f in sorted(RESOURCES.glob("n[1-5].json")):
        entries += json.loads(f.read_text(encoding="utf-8"))
    typeable = [e for e in entries
                if e.get("exJP") and e.get("exKana") and e.get("exTokens")]

    corpus_readings = defaultdict(set)
    for e in entries:
        corpus_readings[e["surface"]].add(e["kana"])

    try:
        from sudachipy import Dictionary
    except ImportError:
        sys.exit("sudachipy missing — run with ./.venv-jp/bin/python")
    dic = Dictionary()
    lex = {}

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
        base = phonetic(tokens)
        cands = []
        for i, (surface, reading) in enumerate(tokens):
            if not any("一" <= c <= "鿿" for c in surface):
                continue
            for alt in sorted((readings(surface) | corpus_readings.get(surface, set())) - {reading}):
                swapped = [list(t) for t in tokens]
                swapped[i][1] = alt
                text = phonetic(swapped)
                if text != base:
                    cands.append({"surface": surface, "from": reading, "to": alt, "kana": text})
        rows.append({"id": e["id"], "jlpt": e["jlpt"], "exJP": e["exJP"],
                     "exKana": e["exKana"], "phonetic": base, "candidates": cands})
    return rows


def build_decoys(rows, n=1500, seed=20260810):
    """Known-WRONG candidates, to measure how often the comparison flags nothing at all.

    The comparison answers "which hypothesis is the audio nearest to". Some of its
    winners are obviously not readings — 古い as ふりい, 長年 as ちゃんねん — which means
    a candidate can beat the truth on spectral luck rather than on being what was said.
    Without a number for how often that happens, "AVSpeech disagrees on N% of sentences"
    is a measurement of the corpus and the instrument added together, reported as if it
    were only the corpus.

    So each sampled sentence gets two decoys built by scrambling one token's reading into
    something the synthesizer certainly did not say:
      * SAME LENGTH — mora count preserved, which isolates pure spectral noise.
      * SHORTER — one mora dropped, which tests whether a shorter hypothesis wins simply
        by having less to disagree with. Several real flags are shorter than the reading
        they beat (彼 かれ -> か, 入っ はいっ -> いっ), so this is the specific worry.
    A decoy that beats the true reading is a false positive by construction.
    """
    import random
    rng = random.Random(seed)
    kana = "あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわ"
    sample = [r for r in rows if r["candidates"]]
    rng.shuffle(sample)
    out = []
    for r in sample[:n]:
        c = rng.choice(r["candidates"])
        true_reading = c["from"]
        if len(true_reading) < 2:
            continue
        # Rebuild the sentence with a scrambled reading in the same slot. Working from the
        # candidate's own kana string keeps the substitution in the right place without
        # re-deriving the tokenisation.
        same = "".join(rng.choice(kana) for _ in true_reading)
        shorter = same[:-1]
        base_before = r["phonetic"]
        if c["from"] not in base_before:
            continue
        out.append({
            "id": r["id"], "exJP": r["exJP"], "phonetic": base_before,
            "same": base_before.replace(true_reading, same, 1),
            "shorter": base_before.replace(true_reading, shorter, 1),
        })
    return out


def measure_decoys(decoys):
    same_wins = short_wins = compared = 0
    margins = []
    for d in decoys:
        jp, base = logmel(clip(d["exJP"])), logmel(clip(d["phonetic"]))
        if jp is None or base is None:
            continue
        d0 = dtw(jp, base)
        ds, dsh = dtw(jp, logmel(clip(d["same"]))), dtw(jp, logmel(clip(d["shorter"])))
        if d0 is None or ds is None or dsh is None:
            continue
        compared += 1
        if ds < d0:
            same_wins += 1
            margins.append(d0 - ds)
        if dsh < d0:
            short_wins += 1
            margins.append(d0 - dsh)
    return compared, same_wins, short_wins, margins


def compare(rows, require_complete=True, margin=0.0):
    """For each sentence: is its own reading the nearest hypothesis, or is another?"""
    results, skipped = [], 0
    for r in rows:
        jp, base = logmel(clip(r["exJP"])), logmel(clip(r["phonetic"]))
        if jp is None or base is None:
            skipped += 1
            continue
        d0 = dtw(jp, base)
        if d0 is None:
            skipped += 1
            continue
        best, incomplete = None, False
        for c in r["candidates"]:
            cm = logmel(clip(c["kana"]))
            if cm is None:
                incomplete = True
                continue
            d = dtw(jp, cm)
            if d is not None and (best is None or d < best[0]):
                best = (d, c)
        if incomplete and require_complete:
            skipped += 1
            continue
        results.append({
            "id": r["id"], "jlpt": r["jlpt"], "exJP": r["exJP"], "exKana": r["exKana"],
            "own": d0,
            "best": best[0] if best else None,
            "beaten": bool(best and best[0] < d0 - margin),
            "says": best[1] if best else None,
            "candidates": len(r["candidates"]),
        })
    return results, skipped


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--render", action="store_true", help="synthesize every hypothesis (slow)")
    ap.add_argument("--report", action="store_true", help="compare what is already rendered")
    ap.add_argument("--write", action="store_true", help="emit the shipped exclusion list")
    ap.add_argument("--partial", action="store_true",
                    help="report over sentences whose clips are all present, mid-render")
    ap.add_argument("--calibrate", action="store_true",
                    help="measure the false-positive rate with known-wrong decoy readings")
    ap.add_argument("--margin", type=float, default=0.0,
                    help="a candidate must beat the true reading by this much to flag")
    args = ap.parse_args()

    rows = build_rows()
    total_cands = sum(len(r["candidates"]) for r in rows)
    print(f"sentences={len(rows)} with_candidates={sum(1 for r in rows if r['candidates'])} "
          f"candidates={total_cands}")

    if args.render:
        texts = []
        for r in rows:
            texts += [r["exJP"], r["phonetic"]] + [c["kana"] for c in r["candidates"]]
        print(f"rendering into {CACHE} …")
        print(f"rendered {render(texts)} new clips")

    if args.calibrate:
        decoys = build_decoys(rows)
        print(f"\ncalibrating on {len(decoys)} sentences with known-wrong decoy readings")
        render([t for d in decoys for t in (d["exJP"], d["phonetic"], d["same"], d["shorter"])])
        compared, same_wins, short_wins, margins = measure_decoys(decoys)
        print(f"  compared {compared}")
        print(f"  same-length decoy beat the true reading: {same_wins} "
              f"({100 * same_wins / max(1, compared):.2f}%)")
        print(f"  shorter decoy beat the true reading:     {short_wins} "
              f"({100 * short_wins / max(1, compared):.2f}%)")
        if margins:
            q = np.percentile(margins, [50, 90, 95, 99])
            print(f"  false-win margins: med={q[0]:.5f} p90={q[1]:.5f} "
                  f"p95={q[2]:.5f} p99={q[3]:.5f} max={max(margins):.5f}")

    if not (args.report or args.write):
        return 0

    results, skipped = compare(rows, require_complete=not args.partial, margin=args.margin)
    flagged = [r for r in results if r["beaten"]]
    print(f"\ncompared {len(results)} sentences ({skipped} skipped for missing clips)")
    print(f"AVSpeech reads a DIFFERENT candidate for {len(flagged)} "
          f"({100 * len(flagged) / max(1, len(results)):.2f}%) at margin {args.margin}")

    by_swap = defaultdict(int)
    for r in flagged:
        by_swap[f"{r['says']['surface']}: {r['says']['from']} -> {r['says']['to']}"] += 1
    for swap, n in sorted(by_swap.items(), key=lambda kv: -kv[1])[:20]:
        print(f"    {n:4d}  {swap}")

    if args.write:
        payload = {
            "measurement": "scripts/check_dictation_readings.py",
            "date": "2026-08-10",
            "voice": "com.apple.voice.compact.ja-JP.Kyoko (AVSpeechSynthesisVoice(language: \"ja-JP\"))",
            "compared": len(results),
            "excludedCount": len(flagged),
            "excluded": [{"id": r["id"], "exJP": r["exJP"], "exKana": r["exKana"],
                          "heardInstead": f"{r['says']['surface']} {r['says']['from']} -> {r['says']['to']}",
                          "own": round(r["own"], 5), "best": round(r["best"], 5)}
                         for r in sorted(flagged, key=lambda r: r["id"])],
        }
        out = RESOURCES / "dictation-exclusions.json"
        out.write_text(json.dumps(payload, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
        print(f"\nwrote {out} ({len(flagged)} excluded)")
        detail = REPO / "docs/measurements/dictation-reading-mismatches.json"
        detail.write_text(json.dumps({"summary": {k: payload[k] for k in
                                                  ("date", "voice", "compared", "excludedCount")},
                                      "excluded": payload["excluded"]},
                                     ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
        print(f"wrote {detail}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
