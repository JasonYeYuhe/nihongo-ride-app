import Testing
import Foundation
@testable import SavedWordsKit

@Suite("SavedWordsStore")
struct SavedWordsStoreTests {

    @Test("add appends, is unique, preserves order")
    func addUnique() {
        var s = SavedWordsStore()
        s.add("n5-a"); s.add("n5-b"); s.add("n5-a")   // duplicate ignored
        #expect(s.ids == ["n5-a", "n5-b"])
        #expect(s.count == 2)
        #expect(s.contains("n5-b"))
        #expect(!s.contains("n5-z"))
    }

    @Test("toggle flips saved state and returns it")
    func toggle() {
        var s = SavedWordsStore()
        #expect(s.toggle("w") == true)    // now saved
        #expect(s.contains("w"))
        #expect(s.toggle("w") == false)   // now unsaved
        #expect(!s.contains("w"))
        #expect(s.isEmpty)
    }

    @Test("remove deletes, no-op when absent")
    func remove() {
        var s = SavedWordsStore(ids: ["a", "b", "c"])
        s.remove("b")
        #expect(s.ids == ["a", "c"])
        s.remove("zzz")                   // absent → no change
        #expect(s.ids == ["a", "c"])
    }

    @Test("init de-dups while keeping first-seen order")
    func initDedup() {
        let s = SavedWordsStore(ids: ["a", "b", "a", "c", "b"])
        #expect(s.ids == ["a", "b", "c"])
    }

    @Test("save then load round-trips through a file")
    func roundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("saved-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var s = SavedWordsStore()
        s.add("n3-1"); s.add("n2-2")
        try s.save(to: url)
        let loaded = SavedWordsStore.load(from: url)
        #expect(loaded.ids == ["n3-1", "n2-2"])
    }

    @Test("load from a missing file returns an empty store")
    func loadMissing() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nope-\(UUID().uuidString).json")
        #expect(SavedWordsStore.load(from: url).isEmpty)
    }

    @Test("load re-dedups a hand-edited (duplicate) file")
    func loadDedups() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dup-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"ids":["x","x","y"]}"#.utf8).write(to: url)
        #expect(SavedWordsStore.load(from: url).ids == ["x", "y"])
    }
}
