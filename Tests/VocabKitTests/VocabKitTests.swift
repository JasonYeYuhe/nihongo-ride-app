import Testing
import RomajiKana
@testable import VocabKit

@Suite("VocabKit")
struct VocabKitTests {
    let store = VocabStore.shared

    @Test("packs load across all five JLPT levels")
    func loads() {
        #expect(!store.isEmpty)
        #expect(store.entries.count >= 500)
        for level in JLPTLevel.allCases {
            #expect(!store.entries(level: level).isEmpty, "no entries for \(level.label)")
        }
    }

    @Test("every entry has English and Chinese meanings")
    func meaningsPresent() {
        for entry in store.entries {
            #expect(!entry.meanings(for: "en").isEmpty, "\(entry.id) missing en gloss")
            #expect(!entry.meanings(for: "zh").isEmpty, "\(entry.id) missing zh gloss")
        }
    }

    /// Cross-validation: every reading, typed via its generated romaji hint, must
    /// complete on the engine. This catches any non-kana / mistyped reading in the
    /// data and proves the romanizer round-trips on real vocabulary.
    @Test("every reading is typeable by the engine")
    func readingsAreTypeable() {
        for entry in store.entries {
            var matcher = KanaInputMatcher(target: entry.kana)
            var allAccepted = true
            for character in entry.romaji where matcher.input(character) == .rejected {
                allAccepted = false
                break
            }
            #expect(allAccepted && matcher.isComplete,
                    "‘\(entry.romaji)’ should type ‘\(entry.kana)’ (\(entry.id))")
        }
    }

    @Test("entry ids are unique")
    func uniqueIDs() {
        let ids = store.entries.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("difficulty stays within 0...1 and varies")
    func difficultyBounds() {
        for entry in store.entries {
            #expect(entry.difficulty >= 0 && entry.difficulty <= 1, "\(entry.id): \(entry.difficulty)")
        }
        // The pack should contain a spread of difficulties, not all-identical.
        #expect(Set(store.entries.map { Int($0.difficulty * 100) }).count > 5)
    }

    @Test("ordered() is sorted easiest-first")
    func orderedSorted() {
        let ordered = store.ordered()
        #expect(ordered.count == store.entries.count)
        for i in 1 ..< ordered.count {
            #expect(ordered[i - 1].difficulty <= ordered[i].difficulty)
        }
    }

    @Test("meaning lookup falls back for an unknown language")
    func meaningFallback() {
        let entry = try! #require(store.entry(id: "n5-gakkou"))
        #expect(entry.meanings(for: "fr") == entry.meanings(for: "en"))  // unknown → en fallback
        #expect(entry.gloss(for: "zh") == "学校")
    }

    @Test("level filtering and id lookup")
    func levelFilter() {
        let n5Count = store.entries(level: .n5).count
        #expect(n5Count >= 100)
        #expect(n5Count < store.entries.count)            // higher levels exist too
        #expect(store.entry(id: "n5-mizu")?.kana == "みず")
        #expect(store.entry(id: "does-not-exist") == nil)
    }

    @Test("readings are globally unique across levels")
    func globallyUnique() {
        let kana = store.entries.map(\.kana)
        #expect(Set(kana).count == kana.count)
    }

    @Test("N5 entries carry example sentences with translations")
    func exampleSentences() {
        let withExamples = store.entries(level: .n5).filter { $0.exampleJP != nil }
        #expect(withExamples.count >= 50)
        let sample = try! #require(withExamples.first)
        #expect(sample.exampleTranslation(for: "en") != nil)
        #expect(sample.exampleTranslation(for: "zh") != nil)
    }
}
