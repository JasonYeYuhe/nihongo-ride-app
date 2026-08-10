import Foundation

/// Which example sentences must NOT be offered as dictation prompts (PLAN-V1.21 §A).
///
/// Dictation grades a learner against `exKana` while playing them a synthesizer's reading
/// of `exJP`. Those are two different systems answering the same question — how does this
/// kanji sentence read — and they do not always agree. `exKana` came from Sudachi; the
/// audio comes from AVSpeech. Measured against each other over the whole corpus, they part
/// company on a minority of sentences: 私 read わたし where the corpus says わたくし, 紅葉 as
/// もみじ where the corpus says こうよう, 明日 as あした where the corpus says あす. Every one
/// of those would mark a learner wrong for typing exactly what they heard.
///
/// Neither side is "the bug". They are two defensible readings of an ambiguous spelling,
/// which is the same failure that put 225 entries beyond teaching in v1.19 — and it is
/// invisible from inside either tool, because each is confident. So the list is not a
/// correction of anything: it records where the two disagree, and dictation declines those
/// sentences. They remain fully available in sentence mode, where the reading is shown
/// rather than spoken and the disagreement never reaches the learner.
///
/// The measurement is `scripts/check_dictation_readings.py`; `docs/measurements/
/// dictation-reading-mismatches.json` carries the evidence for every id here, including
/// what the audio was measured to say instead.
public enum DictationSafety {
    /// Ids withheld from dictation. Loaded from the bundled measurement; an unreadable or
    /// absent file yields an EMPTY set on purpose — see `excludedIDs`.
    public static let excludedIDs: Set<String> = loadExcluded()

    /// Whether the exclusion list actually loaded. A missing file must not silently turn
    /// into "every sentence is safe": the mode's honesty rests entirely on this list, so
    /// the caller gates on this rather than on `excludedIDs.isEmpty` (which is also what an
    /// empty-but-valid list looks like).
    public static let isLoaded: Bool = loadRaw() != nil

    private struct Payload: Decodable {
        let excluded: [Entry]
        struct Entry: Decodable { let id: String }
    }

    private static func loadRaw() -> Payload? {
        guard let url = Bundle.module.url(forResource: "dictation-exclusions", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            assertionFailure("VocabKit: dictation-exclusions.json is missing or malformed")
            return nil
        }
        return payload
    }

    private static func loadExcluded() -> Set<String> {
        Set((loadRaw()?.excluded ?? []).map(\.id))
    }
}
