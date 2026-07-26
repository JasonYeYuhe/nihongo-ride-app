import Foundation
import FoundationModels

@Generable
enum Pattern: String {
    case kunreiRomaji      // typing si/ti/tu where the app teaches shi/chi/tsu
    case missingSokuon     // dropping the small っ
    case longVowel         // dropping or adding ー / doubled vowels
    case dakuten           // が/か, だ/た confusion
    case smallYa           // きゃ typed as きや
    case none
}

@Generable
struct Diagnosis {
    @Guide(description: "The single pattern that best explains these mistakes.")
    var pattern: Pattern
    @Guide(description: "One sentence of advice, warm and specific. No Japanese words.")
    var advice: String
}

@main
struct Probe {
    static func main() async {
        guard case .available = SystemLanguageModel.default.availability else { print("unavailable"); return }
        let instructions = """
        You classify a Japanese-typing learner's mistakes into ONE of the given patterns,
        using only the data provided. Then write one sentence of advice.
        """
        let cases: [(String, String)] = [
            ("kunrei", "shi -> si (7), chi -> ti (5), tsu -> tu (4)"),
            ("sokuon", "itte -> ite (6), kitte -> kite (4), motto -> moto (3)"),
            ("smallya", "kya -> kiya (5), sho -> shiyo (3), chu -> chiyu (2)"),
            ("mixed",  "shi -> si (2), itte -> ite (1)"),
        ]
        for (label, data) in cases {
            let session = LanguageModelSession(instructions: instructions)
            let t0 = Date()
            do {
                let r = try await session.respond(to: "Mistakes: \(data)", generating: Diagnosis.self)
                print("[\(label)] \(String(format: "%.1f", Date().timeIntervalSince(t0)))s -> \(r.content.pattern)")
                print("        \(r.content.advice)")
            } catch { print("[\(label)] ERROR \(error)") }
        }
    }
}
