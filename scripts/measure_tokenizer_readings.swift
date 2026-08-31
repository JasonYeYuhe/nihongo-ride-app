import Foundation

// How good is CFStringTokenizer + latinToHiragana on REAL Japanese with KNOWN readings?
//
// Population: this app's 6,724 typeable example sentences, each with an `exKana` that went
// through a three-lens human review. Best labelled Japanese in reach, and the population the
// claim "its quality problem does not bind here" is actually about.
//
// THE FIRST VERSION OF THIS SCRIPT WAS WRONG AND ITS CONTROL COULD NOT SAY SO. It filtered both
// sides to U+3041–U+3096, which silently deleted the prolonged-sound mark ー (U+30FC) that 569
// corpus sentences carry — and its "positive control" compared the corpus to ITSELF through the
// same destructive filter, so it read 100% for any normaliser whatsoever, destructive ones
// included. The control proved the comparison could tell apart the two things it was handed. It
// said nothing about whether the right answer survived the handing.

// Run from the repo root:  swift scripts/measure_tokenizer_readings.swift
let repo = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = repo.appendingPathComponent("Sources/VocabKit/Resources")
let output = repo.appendingPathComponent("docs/measurements/tokenizer-reading-accuracy.json")

// The app's own kana set, copied from scripts/gen_sentence_kana.py, which is the authority on
// what this corpus considers kana — INCLUDING ー and the small kana.
let KANA = Set("ぁあぃいぅうぇえぉおかがきぎくぐけげこごさざしじすずせぜそぞただちぢっつづてでとど"
             + "なにぬねのはばぱひびぴふぶぷへべぺほぼぽまみむめもゃやゅゆょよらりるれろゎわゐゑをんー")
let PUNCT = Set("、。！？「」・…‥　 ｡｢｣､")

struct Sentence { let jp: String; let kana: String }

func load() -> [Sentence] {
    var out: [Sentence] = []
    for level in ["n1", "n2", "n3", "n4", "n5"] {
        let data = try! Data(contentsOf: resources.appendingPathComponent("\(level).json"))
        for r in (try! JSONSerialization.jsonObject(with: data) as! [[String: Any]]) {
            guard let jp = r["exJP"] as? String, let kana = r["exKana"] as? String,
                  !jp.isEmpty, !kana.isEmpty else { continue }
            out.append(Sentence(jp: jp, kana: kana))
        }
    }
    return out
}

func toHiragana(_ s: String) -> String {
    String(s.map { c in
        let v = c.unicodeScalars.first!.value
        return (v >= 0x30A1 && v <= 0x30F6) ? Character(UnicodeScalar(v - 0x60)!) : c
    })
}

func isKanaOnly(_ s: String) -> Bool { s.allSatisfy { KANA.contains($0) || PUNCT.contains($0) } }

/// Drop punctuation and nothing else. `exKana` is the typing target and carries none.
func stripPunctuation(_ s: String) -> String { String(s.filter { !PUNCT.contains($0) }) }

func reading(of text: String) -> [(surface: String, kana: String)] {
    let cf = text as CFString
    let tokenizer = CFStringTokenizerCreate(nil, cf, CFRangeMake(0, CFStringGetLength(cf)),
                                            kCFStringTokenizerUnitWordBoundary,
                                            Locale(identifier: "ja") as CFLocale)
    var out: [(String, String)] = []
    let ns = text as NSString
    while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
        let r = CFStringTokenizerGetCurrentTokenRange(tokenizer)
        let surface = ns.substring(with: NSRange(location: r.location, length: r.length))
        // A token already written in kana reads as ITSELF. Taking the transcription would
        // normalise ー and the small kana away — gen_sentence_kana.py records exactly this
        // about Sudachi, and it is true of CFStringTokenizer for the same reason.
        if isKanaOnly(toHiragana(surface)) {
            out.append((surface, toHiragana(surface)))
            continue
        }
        let latin = CFStringTokenizerCopyCurrentTokenAttribute(
            tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String ?? ""
        out.append((surface, (latin as NSString).applyingTransform(.latinToHiragana,
                                                                   reverse: false) ?? ""))
    }
    return out
}

func pct(_ a: Int, _ b: Int) -> String {
    b == 0 ? "n/a" : String(format: "%.1f%%", Double(a) / Double(b) * 100)
}

let sentences = load()

// --- CONTROLS ----------------------------------------------------------------------------
// Positive, and this one can FAIL: the normaliser must not delete anything that is not
// punctuation. The previous version's control could not have detected the deletion it had.
var destroyed = 0
for s in sentences where stripPunctuation(s.kana).count != s.kana.filter({ !PUNCT.contains($0) }).count {
    destroyed += 1
}
// A second, sharper one: every character the corpus calls kana must survive normalisation.
var lostChars = 0
for s in sentences {
    let kept = Set(stripPunctuation(s.kana))
    for c in s.kana where !PUNCT.contains(c) && !kept.contains(c) { lostChars += 1 }
}
// Negative: a "reading" that is just the surface. Must be near zero, or the comparison is not
// comparing readings at all.
var surfaceMatch = 0
for s in sentences where stripPunctuation(toHiragana(s.jp)) == stripPunctuation(s.kana) {
    surfaceMatch += 1
}

var exact = 0, charsRight = 0, charsTotal = 0
var withMark = 0, withMarkExact = 0
var misses: [(String, String, String)] = []
for s in sentences {
    let expected = stripPunctuation(s.kana)
    let got = stripPunctuation(reading(of: s.jp).map(\.kana).joined())
    let hasMark = s.jp.contains("ー") || s.kana.contains("ー")
    if hasMark { withMark += 1 }
    if got == expected {
        exact += 1
        if hasMark { withMarkExact += 1 }
    } else if misses.count < 12 {
        misses.append((s.jp, expected, got))
    }
    let e = Array(expected), g = Array(got)
    charsTotal += e.count
    charsRight += zip(e, g).filter(==).count
}

print("population: \(sentences.count) reviewed sentences with a human-checked exKana")
print("")
print("CONTROLS")
print("  positive — normaliser destroys nothing but punctuation : \(destroyed) violations, "
      + "\(lostChars) characters lost   [must be 0, 0]")
print("  negative — surface used as the reading                 : \(pct(surfaceMatch, sentences.count))   [must be near 0]")
print("")
print("CFStringTokenizer + latinToHiragana, kana tokens read as themselves")
print("  whole sentence exactly right : \(exact)/\(sentences.count) = \(pct(exact, sentences.count))")
print("  kana positions right         : \(charsRight)/\(charsTotal) = \(pct(charsRight, charsTotal))")
print("  of the \(withMark) sentences carrying ー: \(pct(withMarkExact, withMark)) exact")
print("")
print("a sample of what is left:")
for (jp, want, got) in misses { print("  \(jp)\n      want \(want)\n      got  \(got)") }

let artefact: [String: Any] = [
    "instrument": "CFStringTokenizer(kCFStringTokenizerUnitWordBoundary, ja) + "
        + "kCFStringTokenizerAttributeLatinTranscription + StringTransform.latinToHiragana, "
        + "with kana-only tokens read as themselves",
    "population": "every typeable example sentence in this corpus (exJP with an exKana), each "
        + "exKana human-reviewed under three lenses",
    "populationSize": sentences.count,
    "controls": [
        "positiveNormaliserDestroysNothing": destroyed == 0 && lostChars == 0,
        "negativeSurfaceAsReadingRate": Double(surfaceMatch) / Double(sentences.count),
    ],
    "sentencesExactlyRight": exact,
    "sentenceExactRate": Double(exact) / Double(sentences.count),
    "kanaPositionsRight": charsRight,
    "kanaPositionsTotal": charsTotal,
    "kanaPositionRate": Double(charsRight) / Double(charsTotal),
    "sentencesCarryingProlongedMark": withMark,
    "prolongedMarkExactRate": Double(withMarkExact) / Double(max(1, withMark)),
    "sampleOfMisses": misses.map { ["exJP": $0.0, "corpus": $0.1, "tokenizer": $0.2] },
    "whatThisDoesNotCover": "These are short, curated sentences built around JLPT vocabulary and "
        + "reviewed for teaching. Text a learner pastes — news, lyrics, forum posts, names — is "
        + "a different population and this number does not describe it.",
]
try! JSONSerialization.data(withJSONObject: artefact, options: [.prettyPrinted, .sortedKeys])
    .write(to: output)
print("\nwrote \(output.lastPathComponent)")
