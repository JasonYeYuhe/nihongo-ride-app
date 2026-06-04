import Testing
@testable import RomajiKana

// MARK: - A. Multi-path single kana

@Suite("A. Multi-path single kana")
struct MultiPathTests {
    @Test("alternate spellings reach the same kana", arguments: [
        ("shi", "し"), ("si", "し"), ("ci", "し"),
        ("tsu", "つ"), ("tu", "つ"),
        ("chi", "ち"), ("ti", "ち"),
        ("fu", "ふ"), ("hu", "ふ"),
        ("ji", "じ"), ("zi", "じ"),
        ("ka", "か"), ("ca", "か"),
        ("ku", "く"), ("cu", "く"),
        ("wo", "を"),
    ])
    func accepts(_ c: (input: String, target: String)) {
        #expect(typesOut(c.input, as: c.target), "‘\(c.input)’ should type ‘\(c.target)’")
    }
}

// MARK: - B. Youon (拗音)

@Suite("B. Youon")
struct YouonTests {
    @Test("contracted sounds, whole + decomposed", arguments: [
        ("sha", "しゃ"), ("sya", "しゃ"),
        ("cha", "ちゃ"), ("tya", "ちゃ"), ("cya", "ちゃ"),
        ("ja", "じゃ"), ("zya", "じゃ"), ("jya", "じゃ"),
        ("kya", "きゃ"), ("kixya", "きゃ"), ("kilya", "きゃ"),   // whole + decomposed き+small ゃ
        ("nya", "にゃ"),
        ("ryo", "りょ"),
        ("kyo", "きょ"),
    ])
    func accepts(_ c: (input: String, target: String)) {
        #expect(typesOut(c.input, as: c.target), "‘\(c.input)’ should type ‘\(c.target)’")
    }
}

// MARK: - C. Sokuon (促音 っ)

@Suite("C. Sokuon")
struct SokuonTests {
    @Test("gemination (doubled consonant) + explicit xtu/ltu/tch", arguments: [
        ("gakkou", "がっこう"), ("gaxtukou", "がっこう"), ("galtukou", "がっこう"),
        ("kitte", "きって"), ("kixtute", "きって"),
        ("zasshi", "ざっし"), ("zassi", "ざっし"),
        ("maccha", "まっちゃ"), ("mattya", "まっちゃ"), ("matcha", "まっちゃ"),   // っ+ちゃ, incl. tch
        ("kippu", "きっぷ"), ("kixtupu", "きっぷ"),
        ("kotchi", "こっち"), ("kocchi", "こっち"),
    ])
    func accepts(_ c: (input: String, target: String)) {
        #expect(typesOut(c.input, as: c.target), "‘\(c.input)’ should type ‘\(c.target)’")
    }
}

// MARK: - D. Hatsuon (撥音 ん)

@Suite("D. Hatsuon")
struct HatsuonTests {
    @Test("n / nn / n' / xn, with lenient single-n", arguments: [
        ("hon", "ほん"), ("honn", "ほん"), ("hon'", "ほん"),
        ("minna", "みんな"), ("minnna", "みんな"), ("min'na", "みんな"),
        ("kanji", "かんじ"), ("kanzi", "かんじ"),
        ("ren'ai", "れんあい"), ("rennai", "れんあい"), ("renai", "れんあい"),
        ("shinbun", "しんぶん"), ("sinbun", "しんぶん"),
        ("kin'youbi", "きんようび"), ("kinnyoubi", "きんようび"), ("kinyoubi", "きんようび"),
        ("xnke", "んけ"),
    ])
    func accepts(_ c: (input: String, target: String)) {
        #expect(typesOut(c.input, as: c.target), "‘\(c.input)’ should type ‘\(c.target)’")
    }

    @Test("ん is typed as n; Hepburn 'm' before b/p is rejected like a real IME")
    func rejectsHepburnM() {
        // しんぶん: after し (s,h,i), position 3 expects ん (n/nn/n'/xn); 'm' is invalid.
        #expect(firstRejection(of: "shimbun", as: "しんぶん", at: 3))
    }
}

// MARK: - E. Choon (長音 / long vowels)

@Suite("E. Long vowels")
struct ChoonTests {
    @Test("long vowels are literal vowel sequences", arguments: [
        ("toukyou", "とうきょう"),
        ("koukou", "こうこう"),
        ("ookii", "おおきい"),
        ("nee", "ねえ"),
        ("oneesan", "おねえさん"),
    ])
    func accepts(_ c: (input: String, target: String)) {
        #expect(typesOut(c.input, as: c.target), "‘\(c.input)’ should type ‘\(c.target)’")
    }
}

// MARK: - F. Whole-word integration

@Suite("F. Integration (N5 words)")
struct IntegrationTests {
    @Test("full words type out", arguments: [
        ("nihon", "にほん"),
        ("nihongo", "にほんご"),
        ("sensei", "せんせい"),
        ("gakusei", "がくせい"),
        ("densha", "でんしゃ"), ("densya", "でんしゃ"),
        ("shinkansen", "しんかんせん"),
        ("tabemono", "たべもの"),
        ("nani", "なに"),
    ])
    func accepts(_ c: (input: String, target: String)) {
        #expect(typesOut(c.input, as: c.target), "‘\(c.input)’ should type ‘\(c.target)’")
    }
}

// MARK: - G. State-machine robustness

@Suite("G. Robustness")
struct RobustnessTests {
    @Test("a rejected key does not change state; typing can continue")
    func rejectionIsNonDestructive() {
        var m = KanaInputMatcher(target: "にほん")
        for ch in "niho" { #expect(m.input(ch) != .rejected) }
        let snapshot = m.typedRomaji
        #expect(m.input("a") == .rejected)        // 'a' is invalid after にほ
        #expect(m.typedRomaji == snapshot)        // ...and state is unchanged
        #expect(m.input("n") == .completed)       // can still finish correctly
        #expect(m.isComplete)
    }

    @Test("a completed word reports completion and expects nothing further")
    func completion() {
        var m = KanaInputMatcher(target: "ねこ")
        #expect(m.input("n") == .accepted)
        #expect(m.input("e") == .accepted)
        #expect(m.input("k") == .accepted)
        #expect(m.input("o") == .completed)
        #expect(m.isComplete)
        #expect(m.expectedNextCharacters.isEmpty)
    }

    @Test("expectedNextCharacters reflects all valid first keys")
    func expectedNext() {
        let shi = KanaInputMatcher(target: "し")       // shi / si / ci
        #expect(shi.expectedNextCharacters == Set("sc"))
        let ni = KanaInputMatcher(target: "にほん")     // に = ni only
        #expect(ni.expectedNextCharacters == Set("n"))
    }

    @Test("completedKanaCount advances per committed kana")
    func progress() {
        var m = KanaInputMatcher(target: "にほん")
        #expect(m.completedKanaCount == 0)
        _ = m.input("n"); _ = m.input("i")
        #expect(m.completedKanaCount == 1)
        _ = m.input("h"); _ = m.input("o")
        #expect(m.completedKanaCount == 2)
        _ = m.input("n")
        #expect(m.completedKanaCount == 3)
        #expect(m.isComplete)
    }

    @Test("uppercase input is normalized to lowercase")
    func caseInsensitive() {
        #expect(typesOut("SHI", as: "し"))
        #expect(typesOut("Nihongo", as: "にほんご"))
    }

    @Test("an empty target is trivially complete")
    func emptyTarget() {
        let m = KanaInputMatcher(target: "")
        #expect(m.isComplete)
    }

    @Test("typedRomaji accumulates accepted keys only")
    func typedAccumulates() {
        var m = KanaInputMatcher(target: "し")
        _ = m.input("s")
        _ = m.input("x")          // rejected
        _ = m.input("i")
        #expect(m.typedRomaji == "si")
    }

    @Test("a wrong sokuon gemination consonant is rejected (no soft-lock)")
    func sokuonNoSoftLock() {
        // がっこう: after が, っこ accepts kk/cc/xtu… ('k','c','x','l') but not 's'.
        #expect(firstRejection(of: "gasu", as: "がっこう", at: 2))
        var m = KanaInputMatcher(target: "がっこう")
        for ch in "ga" { _ = m.input(ch) }
        #expect(m.expectedNextCharacters.contains("k"))
        #expect(!m.expectedNextCharacters.contains("s"))
    }

    @Test("a word ending in っ is typeable via xtu/ltu, with no dead-end key")
    func trailingSokuon() {
        #expect(typesOut("axtu", as: "あっ"))
        #expect(typesOut("axtsu", as: "あっ"))
        #expect(firstRejection(of: "ak", as: "あっ", at: 1))   // kk path can't complete → rejected
    }
}
