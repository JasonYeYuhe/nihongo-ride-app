import Foundation
import FoundationModels

@main
struct Probe {
    static func main() async {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            print("AVAILABILITY: available")
        case .unavailable(let reason):
            print("AVAILABILITY: unavailable — \(reason)")
            return
        @unknown default:
            print("AVAILABILITY: unknown"); return
        }
        do {
            let session = LanguageModelSession(instructions: """
            You write single, natural Japanese example sentences for JLPT learners.
            Reply with the sentence only — no translation, no explanation, no quotes.
            """)
            let t0 = Date()
            let r = try await session.respond(to: "Write one short N5-level sentence using 勉強する.")
            print("LATENCY: \(String(format: "%.2f", Date().timeIntervalSince(t0)))s")
            print("OUT: \(r.content)")
        } catch {
            print("ERROR: \(error)")
        }
    }
}
