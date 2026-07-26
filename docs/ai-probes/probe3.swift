import Foundation
import FoundationModels

@Generable
struct Coach {
    @Guide(description: "One or two sentences of concrete, encouraging advice. Plain language, no jargon.")
    var note: String
    @Guide(description: "The single biggest pattern behind these mistakes, in five words or fewer.")
    var pattern: String
}

@Generable
struct Nuance {
    @Guide(description: "Two sentences on when a learner would actually use this word, based ONLY on the gloss given.")
    var usage: String
    @Guide(description: "One short memory hook.")
    var hook: String
}

@main
struct Probe {
    static func main() async {
        guard case .available = SystemLanguageModel.default.availability else { print("unavailable"); return }

        let data = """
        Recent mistakes (expected romaji -> what they typed):
        shi -> si (7 times), chi -> ti (5 times), tsu -> tu (4 times),
        kya -> kiya (3 times), missed small tsu in "itte" -> "ite" (6 times)
        """

        // 1) Mistake analysis over the app's OWN structured data (no Japanese authoring).
        let s1 = LanguageModelSession(instructions: """
        You are a typing coach inside a Japanese practice app. You are given the learner's
        OWN recent typos as structured data. Never invent Japanese. Speak about patterns.
        """)
        var t0 = Date()
        do {
            let r = try await s1.respond(to: data, generating: Coach.self)
            print("[coach EN] \(String(format: "%.1f", Date().timeIntervalSince(t0)))s")
            print("   pattern: \(r.content.pattern)")
            print("   note: \(r.content.note)")
        } catch { print("[coach EN] ERROR \(error)") }

        // 2) Chinese output quality.
        let s2 = LanguageModelSession(instructions: """
        你是一个日语打字练习 app 里的教练。只根据给出的数据说话,不要编造日语。用简体中文回答。
        """)
        t0 = Date()
        do {
            let r = try await s2.respond(to: data, generating: Coach.self)
            print("[coach ZH] \(String(format: "%.1f", Date().timeIntervalSince(t0)))s")
            print("   pattern: \(r.content.pattern)")
            print("   note: \(r.content.note)")
        } catch { print("[coach ZH] ERROR \(error)") }

        // 3) Explanation grounded in the app's own dictionary row.
        let s3 = LanguageModelSession(instructions: """
        You explain vocabulary to JLPT learners. You are given the word's authoritative
        reading and glosses from the app's own dictionary. Ground everything in what you are
        given; do NOT introduce other Japanese words or claim readings of your own.
        """)
        t0 = Date()
        do {
            let r = try await s3.respond(
                to: "Word: 披露 (reading: ひろう). Glosses: announcement, presentation, introduction. Level: N2.",
                generating: Nuance.self)
            print("[nuance] \(String(format: "%.1f", Date().timeIntervalSince(t0)))s")
            print("   usage: \(r.content.usage)")
            print("   hook: \(r.content.hook)")
        } catch { print("[nuance] ERROR \(error)") }
    }
}
