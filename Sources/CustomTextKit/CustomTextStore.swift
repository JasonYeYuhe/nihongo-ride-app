import Foundation
import PersistKit

/// The learner's own texts, on this device.
///
/// Loads through `LossyLoad` for the reason that module exists: one malformed sentence must not
/// discard every text, and "the file could not be read" must not be treated the same as "the
/// file is corrupt" and then overwritten. Callers that write must check `isSafeToWrite`.
public struct CustomTextStore: Codable, Sendable, Equatable {
    public private(set) var texts: [CustomText]

    public init(texts: [CustomText] = []) { self.texts = texts }

    public var isEmpty: Bool { texts.isEmpty }
    public var count: Int { texts.count }

    public func text(id: String) -> CustomText? { texts.first { $0.id == id } }

    /// Newest first — the one they just added is the one they want.
    public var ordered: [CustomText] { texts.sorted { $0.createdAt > $1.createdAt } }

    /// Add a text, newest kept. At the cap the OLDEST is dropped, which is stated rather than
    /// silent: a store that refuses the add instead would look, from the outside, exactly like
    /// a store that failed to save.
    @discardableResult
    public mutating func add(_ text: CustomText) -> Bool {
        guard !text.sentences.isEmpty else { return false }
        texts.append(text)
        if texts.count > CustomText.maxTexts {
            texts = Array(texts.sorted { $0.createdAt > $1.createdAt }.prefix(CustomText.maxTexts))
        }
        return true
    }

    @discardableResult
    public mutating func remove(id: String) -> Bool {
        let before = texts.count
        texts.removeAll { $0.id == id }
        return texts.count != before
    }

    @discardableResult
    public mutating func rename(id: String, to title: String) -> Bool {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let i = texts.firstIndex(where: { $0.id == id }) else { return false }
        texts[i].title = name
        return true
    }

    /// Correct one token's reading, inside one sentence, inside one text.
    ///
    /// Returns false and changes nothing when the reading is not kana. The learner is the
    /// authority on their own text, but an "reading" that cannot be typed would leave them
    /// unable to finish the sentence they just corrected.
    @discardableResult
    public mutating func setReading(_ reading: String, textID: String, sentenceID: String,
                                    tokenIndex: Int) -> Bool {
        guard let t = texts.firstIndex(where: { $0.id == textID }),
              let s = texts[t].sentences.firstIndex(where: { $0.id == sentenceID })
        else { return false }
        return texts[t].sentences[s].setReading(reading, at: tokenIndex)
    }

    // MARK: Persistence

    public func save(to url: URL) throws {
        let data = try JSONEncoder().encode(self)
        // Round-trip before the write, the way WordListStore does: a store that encodes but
        // cannot decode is a store that is empty on next launch, and the write is what makes
        // that permanent.
        _ = try JSONDecoder().decode(CustomTextStore.self, from: data)
        try data.write(to: url, options: .atomic)
    }

    public static func loadReporting(from url: URL) -> (store: CustomTextStore,
                                                        outcome: LossyLoad.Outcome) {
        let (decoded, outcome) = LossyLoad.load(CustomTextStore.self, from: url)
        return (decoded ?? CustomTextStore(), outcome)
    }

    public static func load(from url: URL) -> CustomTextStore { loadReporting(from: url).store }
}
