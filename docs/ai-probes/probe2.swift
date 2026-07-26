import Foundation
import FoundationModels

@Generable
struct Example {
    @Guide(description: "One natural Japanese sentence, 8-20 characters, using the target word. Kanji allowed.")
    var japanese: String
    @Guide(description: "The same sentence written ONLY in hiragana and katakana — no kanji, no romaji, no spaces.")
    var kana: String
    @Guide(description: "A plain English translation.")
    var english: String
}

@main
struct Probe {
    static func main() async {
        guard case .available = SystemLanguageModel.default.availability else {
            print("unavailable"); return
        }
        let instructions = """
        You produce example sentences for a Japanese typing app used by JLPT learners.
        Rules, all mandatory:
        - The sentence must USE the target word, not merely mention it.
        - Keep it natural, everyday Japanese at the stated JLPT level.
        - The kana field must be the EXACT reading of the japanese field, in kana only.
        """
        let cases = [("勉強する", "N5"), ("рассвет", "N5"), ("披露", "N2"), ("落ち着く", "N3"), ("しかし", "N4")]
        for (word, level) in cases {
            let session = LanguageModelSession(instructions: instructions)
            let t0 = Date()
            do {
                let r = try await session.respond(
                    to: "Target word: \(word). Level: \(level).",
                    generating: Example.self)
                let dt = Date().timeIntervalSince(t0)
                let e = r.content
                print("[\(word)] \(String(format: "%.2f", dt))s")
                print("   JA: \(e.japanese)")
                print("   KANA: \(e.kana)")
                print("   EN: \(e.english)")
            } catch {
                print("[\(word)] ERROR: \(error)")
            }
        }
    }
}
