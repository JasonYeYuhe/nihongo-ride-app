import Testing
import Foundation
@testable import PersistKit

/// The failure these exist for: every store the app owns used to load with
/// `try? decode(...) ?? Store()`, so ONE malformed element discarded the whole file, the
/// next write made it permanent, and iCloud could not heal it (the persisted change token
/// means the server never re-sends records this device already saw). Nine hundred review
/// cards could go to zero because one of them lost a field.
@Suite("LossyLoad — one bad element costs one element")
struct LossyLoadTests {

    private struct Card: Codable, Equatable {
        let id: String
        var score: Int
    }

    private struct Box: Decodable {
        let items: [Card]
        let skipped: Int
        enum CodingKeys: String, CodingKey { case items }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            (items, skipped) = try LossyLoad.lossyArray(Card.self, from: c, forKey: .items)
        }
    }

    private struct Map: Decodable {
        let cards: [String: Card]
        let skipped: Int
        enum CodingKeys: String, CodingKey { case cards }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            (cards, skipped) = try LossyLoad.lossyDictionary(Card.self, from: c, forKey: .cards)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    @Test("an array keeps the good elements and counts the bad")
    func arrayKeepsGood() throws {
        let box = try decode(Box.self, """
        {"items": [{"id":"a","score":1}, {"id":"b"}, {"id":"c","score":3}]}
        """)
        #expect(box.items.map(\.id) == ["a", "c"], "middle element should be the only loss")
        #expect(box.skipped == 1)
    }

    @Test("the container keeps advancing past a bad element — no infinite loop")
    func doesNotSpin() throws {
        // JSONDecoder does NOT advance an unkeyed container's index when an element throws,
        // so the obvious `while !isAtEnd { try? decode() }` spins forever on the first bad
        // element. This is the case that proves the wrapper is load-bearing, not decoration:
        // if it regressed, this test would hang rather than fail.
        let box = try decode(Box.self, """
        {"items": [{"nope":1}, {"nope":2}, {"id":"z","score":9}]}
        """)
        #expect(box.items.map(\.id) == ["z"])
        #expect(box.skipped == 2)
    }

    @Test("a non-object element is skipped like any other bad one")
    func nonObjectElement() throws {
        let box = try decode(Box.self, """
        {"items": [{"id":"a","score":1}, 42, "nope", null]}
        """)
        #expect(box.items.map(\.id) == ["a"])
        #expect(box.skipped == 3)
    }

    @Test("a dictionary loses only the bad entries")
    func dictionaryKeepsGood() throws {
        let map = try decode(Map.self, """
        {"cards": {"a": {"id":"a","score":1}, "b": {"id":"b"}, "c": {"id":"c","score":3}}}
        """)
        #expect(Set(map.cards.keys) == ["a", "c"])
        #expect(map.skipped == 1)
    }

    @Test("unknown keys are ignored — a file from a NEWER version still loads")
    func forwardCompatible() throws {
        let box = try decode(Box.self, """
        {"items": [{"id":"a","score":1,"fieldFromTheFuture":true}], "alsoNew": 7}
        """)
        #expect(box.items == [Card(id: "a", score: 1)])
        #expect(box.skipped == 0)
    }

    // MARK: file-level outcomes

    private func temp() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("lossy-\(UUID().uuidString).json")
    }

    @Test("a missing file is .missing, not corruption")
    func missingFile() {
        let (value, outcome) = LossyLoad.load(Card.self, from: temp())
        #expect(value == nil)
        #expect(outcome == .missing)
        #expect(LossyLoad.isSafeToWrite(outcome), "a fresh install must be allowed to write")
    }

    @Test("undecodable bytes are quarantined before anything can overwrite them")
    func quarantinesCorrupt() throws {
        let url = temp()
        defer { try? FileManager.default.removeItem(at: url)
                try? FileManager.default.removeItem(at: url.appendingPathExtension("corrupt")) }
        let garbage = Data("{ this is not json".utf8)
        try garbage.write(to: url)

        let (value, outcome) = LossyLoad.load(Card.self, from: url)
        #expect(value == nil)
        #expect(outcome == .undecodable)

        let saved = try Data(contentsOf: url.appendingPathExtension("corrupt"))
        #expect(saved == garbage, "the original bytes must survive for recovery")
    }

    @Test("a good file round-trips and reports .loaded")
    func goodFile() throws {
        let url = temp()
        defer { try? FileManager.default.removeItem(at: url) }
        try JSONEncoder().encode(Card(id: "a", score: 5)).write(to: url)

        let (value, outcome) = LossyLoad.load(Card.self, from: url)
        #expect(value == Card(id: "a", score: 5))
        #expect(outcome == .loaded)
    }

    @Test("unreadable is not safe to write; every other outcome is")
    func writeSafety() {
        #expect(!LossyLoad.isSafeToWrite(.unreadable))
        #expect(LossyLoad.isSafeToWrite(.missing))
        #expect(LossyLoad.isSafeToWrite(.loaded))
        #expect(LossyLoad.isSafeToWrite(.undecodable))
        #expect(LossyLoad.isSafeToWrite(.loadedWithSkips(skipped: 3)))
    }
}
