import Foundation

/// A piece of Japanese the learner supplied, split into sentences, each with a reading they
/// can correct.
///
/// **Deliberately outside the SRS, and that is the whole scoping decision.** `SRSCard(id:)` is
/// keyed on corpus entry ids and `SyncMerge` merges those across devices through CloudKit;
/// giving pasted words card identities is the expensive and dangerous half of "bring your own
/// Japanese", and it is what turns this from days into weeks. Practice mode records no SRS by
/// construction (`RunCompletion(mode: .practice)` sets `persistsSRS = false`), so a custom text
/// rides the one mode where the question cannot arise.
///
/// It also answers the question that decides whether the other half is worth building — *will
/// anyone paste their own material* — and that answer costs nothing to wait for.
///
/// **Local only. Not synced.** The stores that sync are the ones whose loss costs a learner
/// their schedule; a pasted text is something they still have. Adding it to `SyncMerge` would
/// mean a new CloudKit record type and a merge policy for editable free text, which is a
/// separate piece of work with its own failure modes.
public struct CustomSentence: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    /// The sentence as the learner wrote it, kanji and punctuation intact.
    public let source: String
    /// Per-token readings. Editable: the learner is the authority on their own text.
    public var tokens: [JapaneseReading.Token]

    public init(id: String = UUID().uuidString, source: String,
                tokens: [JapaneseReading.Token]) {
        self.id = id
        self.source = source
        self.tokens = tokens
    }

    /// What the learner types: every reading, punctuation stripped.
    public var kana: String { JapaneseReading.typingTarget(tokens) }

    /// The same readings WITH their punctuation — what the practice screen shows above the
    /// caret, so the dim 。 sits where the learner wrote it.
    ///
    /// **These two are a count-and-run pair and the app has shipped that defect two dozen
    /// times.** `PracticeView` walks this string and advances the caret once per character it
    /// considers a typing target, while the engine consumes `kana`; if the two disagree about a
    /// single character the caret desyncs from the text for the rest of the sentence. They
    /// cannot disagree here because there is no third category — `hasNoUncountedCharacters`
    /// asserts every character is either punctuation or kana, so an allow-list and a deny-list
    /// partition the same string.
    public var displayKana: String { tokens.map(\.reading).joined() }

    /// Every character of `displayKana` is either punctuation or kana — nothing in between.
    /// This is what makes the caret alignment above a property rather than an argument.
    public var hasNoUncountedCharacters: Bool {
        displayKana.allSatisfy {
            JapaneseReading.punctuation.contains($0) || JapaneseReading.kana.contains($0)
        }
    }

    /// Whether this sentence can be typed at all, and whether its reading means anything.
    ///
    /// BOTH halves are load-bearing and the second was found by a test. `ABCを見る。` produces
    /// **あぶくをみる**: valid kana, perfectly typeable, and not a reading of the sentence. A
    /// check on the target alone lets it through — see `JapaneseReading.canRead`.
    public var isTypeable: Bool {
        JapaneseReading.canRead(source) && JapaneseReading.isTypeable(kana)
            && hasNoUncountedCharacters
    }

    /// The tokens in `exTokens` shape (`[[surface, reading]]`), so `FuriganaText` renders this
    /// with no second code path.
    public var furiganaTokens: [[String]] { tokens.map { [$0.surface, $0.reading] } }

    /// Replace one token's reading. Returns false when the index is out of range or the new
    /// reading is not kana — an unreadable "reading" would make the sentence untypeable, and
    /// silently accepting it is how a learner ends up unable to finish their own text.
    public mutating func setReading(_ reading: String, at index: Int) -> Bool {
        guard tokens.indices.contains(index) else { return false }
        let hiragana = JapaneseReading.toHiragana(reading)
        guard !hiragana.isEmpty, hiragana.allSatisfy({ JapaneseReading.kana.contains($0) })
        else { return false }
        tokens[index].reading = hiragana
        return true
    }
}

public struct CustomText: Identifiable, Codable, Hashable, Sendable {
    /// Cap per text and per store. Not arbitrary: the practice run draws whole sentences, and
    /// a store with no ceiling is a store that can be made to fail on load.
    public static let maxSentences = 200
    public static let maxTexts = 50
    public static let maxSourceCharacters = 20_000

    public let id: String
    public var title: String
    public let createdAt: Date
    public var sentences: [CustomSentence]

    public init(id: String = UUID().uuidString, title: String, createdAt: Date,
                sentences: [CustomSentence]) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.sentences = Array(sentences.prefix(Self.maxSentences))
    }

    /// The sentences a practice run can actually use. A sentence whose reading came back with
    /// Latin letters or digits in it is **kept and shown** — it is the learner's text — and
    /// withheld from the typing queue, because a target nobody can type is a dead screen.
    public var typeableSentences: [CustomSentence] { sentences.filter(\.isTypeable) }

    /// What the two caps did to a pasted text, so the add sheet can say so before the learner
    /// taps Add. Until v1.34 a paste over either cap was cut without a word (`PLAN-V1.34` §B2).
    public struct Truncation: Equatable, Sendable {
        public let keptCharacters: Int
        public let droppedCharacters: Int
        public let keptSentences: Int
        public let droppedSentences: Int

        public init(keptCharacters: Int, droppedCharacters: Int,
                    keptSentences: Int, droppedSentences: Int) {
            self.keptCharacters = keptCharacters
            self.droppedCharacters = droppedCharacters
            self.keptSentences = keptSentences
            self.droppedSentences = droppedSentences
        }

        public var isTruncated: Bool { droppedCharacters > 0 || droppedSentences > 0 }
    }

    /// The cut `make` will apply to this source, counted.
    public static func truncation(of source: String) -> Truncation { cut(source).truncation }

    /// **The one place both caps are applied.** `make` stores what this returns and the add
    /// sheet's notice reads what this returns, so the two cannot describe different texts —
    /// a second copy of the rule in the view is how a footer ends up honest about a text
    /// other than the one that was saved. Characters first, then the sentence cap on what
    /// survived them: a sentence lost to the character cap is counted once, as characters,
    /// never a second time as a sentence.
    static func cut(_ source: String) -> (source: String, sentences: [String], truncation: Truncation) {
        let kept = String(source.prefix(maxSourceCharacters))
        let all = CustomTextSplitter.sentences(in: kept)
        let sentences = Array(all.prefix(maxSentences))
        let truncation = Truncation(keptCharacters: kept.count,
                                    droppedCharacters: source.count - kept.count,
                                    keptSentences: sentences.count,
                                    droppedSentences: all.count - sentences.count)
        return (kept, sentences, truncation)
    }

    /// Build from raw pasted text: split into sentences, read each one.
    public static func make(title: String, source: String, now: Date) -> CustomText {
        let cut = cut(source)
        let sentences = cut.sentences.map {
            CustomSentence(source: $0, tokens: JapaneseReading.tokens(for: $0))
        }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return CustomText(id: UUID().uuidString,
                          title: name.isEmpty ? Self.defaultTitle(for: cut.source) : name,
                          createdAt: now,
                          sentences: sentences)
    }

    /// A title taken from the text itself when the learner did not give one — the opening
    /// characters, which is what they would recognise it by in a list.
    static func defaultTitle(for source: String) -> String {
        let flat = source.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return flat.isEmpty ? "—" : String(flat.prefix(24))
    }
}

/// Splitting Japanese text into sentences.
///
/// Deliberately small and deliberately conservative. The terminators are the three that end a
/// Japanese sentence plus the line break, and a closing quote or bracket that immediately
/// follows one is carried along with it rather than starting a sentence of its own — 「…。」 is
/// one sentence, and a splitter that breaks before the 」 leaves a fragment that is a whole
/// practice screen showing a single character.
public enum CustomTextSplitter {
    static let terminators: Set<Character> = ["。", "！", "？", "!", "?", "\n"]
    static let openers: Set<Character> = ["「", "『", "（", "(", "\u{201C}"]
    static let closers: Set<Character> = ["」", "』", "）", ")", "\u{201D}"]

    public static func sentences(in text: String) -> [String] {
        var out: [String] = []
        var current = ""
        let characters = Array(text)
        var i = 0
        // Depth, because 「おはよう。」と彼は言った。 is ONE sentence and a splitter that stops
        // at the inner 。 leaves 「おはよう。」 as a whole practice screen and と彼は言った。 as
        // another. Found by the test, not by reading the code.
        var depth = 0
        while i < characters.count {
            let c = characters[i]
            current.append(c)
            i += 1
            if openers.contains(c) { depth += 1 }
            if closers.contains(c) { depth = max(0, depth - 1) }
            guard terminators.contains(c), depth == 0 else { continue }
            while i < characters.count, closers.contains(characters[i]) {
                current.append(characters[i])
                i += 1
            }
            let piece = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty { out.append(piece) }
            current = ""
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { out.append(tail) }
        return out
    }
}
