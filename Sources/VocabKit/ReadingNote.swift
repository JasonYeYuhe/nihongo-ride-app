import Foundation

/// What a card should say when the reading it teaches is not the everyday reading of its
/// own spelling (PLAN-V1.21 §C).
///
/// 216 entries teach a reading no naturally-written sentence would produce for that
/// spelling, which is why they have no example — and 29 of them sit beside a sibling card
/// with the SAME kanji and a byte-identical English gloss. 鼠/ねず and 鼠/ねずみ are two cards
/// a learner cannot tell apart, and nothing on either says which one an ordinary sentence
/// would use. That is the gap this fills.
///
/// **87 of the 216 carry a note, and the cut is the point.** The rest claimed an everyday
/// reading sourced only from the measurement file's `defaultReading`, a field whose name
/// promises more than it holds — on the first six N5 cards it was backwards three times,
/// and it would have printed "言う is usually read ゆう" on the very card v1.18 created by
/// retiring 言う/ゆう as the colloquial form. A note ships only when a SECOND source agrees:
/// the everyday reading it names is a sibling ENTRY that exists with the same spelling, that
/// sibling carries a reviewed example sentence in which the spelling really is read that
/// way, and the corpus's own token readings do not contradict it.
///
/// **Why these entries were kept rather than retired.** Both external reviewers consulted
/// on §C said retire, and both argued from the premise that the card asks "given this
/// spelling, what reading?" — leaving these underdetermined. The app does not ask that. The
/// word card prints the reading beside the spelling unconditionally (the assistance setting
/// gates the romaji, not the kana), the conjugation drill prints the dictionary reading, and
/// dictation never draws these entries because it needs an example sentence they do not
/// have. A learner types a reading they can see; they are never asked to choose one. The
/// over-generalisation harm both reviewers described needs a recall task this app does not
/// have, and retiring 222 entries plus every learner's progress on them to fix a problem the
/// interface already prevents is the more expensive mistake.
///
/// What the reviewers' critique did change is the WORDING. "No example sentence could be
/// generated" is implementation history and says nothing a learner can use, so the note
/// never mentions sentences. It states the reading fact, and nothing else.
public struct ReadingNote: Sendable, Equatable {
    public enum Kind: String, Sendable, Decodable {
        /// This spelling's everyday reading has its OWN card, named by `siblingID`.
        ///
        /// The only kind that ships. A second kind (`lessCommon`, for spellings whose usual
        /// reading no entry teaches) was built and cut: nothing corroborated its claim.
        case commonIs
    }

    public let kind: Kind
    /// The everyday reading of this entry's spelling — the one this card does NOT teach.
    public let common: String
    /// The entry that teaches `common`, when one exists.
    public let siblingID: String?
}

public enum ReadingNotes {
    /// The note for an entry, or nil for the 96% of the corpus that needs none.
    public static func note(for id: String) -> ReadingNote? { all[id] }

    /// Whether the shipped list loaded. A missing file means every card silently loses its
    /// note; the count is small enough that nothing else would reveal it.
    public static let isLoaded: Bool = !all.isEmpty

    public static let all: [String: ReadingNote] = load()

    private struct Payload: Decodable {
        let notes: [Note]
        struct Note: Decodable {
            let id: String
            let kind: ReadingNote.Kind
            let common: String
            let siblingID: String?
        }
    }

    private static func load() -> [String: ReadingNote] {
        guard let url = Bundle.module.url(forResource: "reading-notes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            assertionFailure("VocabKit: reading-notes.json is missing or malformed")
            return [:]
        }
        return Dictionary(payload.notes.map {
            ($0.id, ReadingNote(kind: $0.kind, common: $0.common, siblingID: $0.siblingID))
        }, uniquingKeysWith: { first, _ in first })
    }
}
