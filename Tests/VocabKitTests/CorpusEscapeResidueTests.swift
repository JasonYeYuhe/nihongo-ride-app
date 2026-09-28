import Testing
import Foundation
@testable import VocabKit

/// Quoting residue in shipped corpus text — the `I'''m` the v1.34 iPad simulator pass read on
/// a Practice translation.
///
/// 3e9407a (2026-06-06) merged 73 Practice passages into `passages.json` from a Gemini response
/// whose English was clean: the raw response survives in the Gemini CLI's chat log, and the 73
/// committed translations equal it exactly once every `'''` is read as `'`. Every apostrophe in
/// the batch — 20, in 18 translations — arrived tripled, and nothing else changed. That is the
/// signature of a shell-quoted `'\''` read by an interpreter that takes `\'` as `'`. The merge was
/// a one-off shell step in an agent session, not a script in this repo, so there was no code path
/// to correct afterwards. What was missing was anything that READ the shipped text: the passage
/// test only asked that a translation be non-empty, and the defect shipped in every release from
/// then to 1.33 until a person looked at an iPad.
///
/// So this reads every string in every corpus file — not only translations, and not only
/// `passages.json`, because the next hand-made merge will not pick the same file or the same
/// field. And the rule covers the family, not the one instance: each shape below is what a quoting
/// layer leaves behind when it is applied and never undone, and none has a legitimate use anywhere
/// in this corpus (measured 2026-09-28: zero hits in 240,180 strings once the 18 were corrected).
///
/// `scripts/corpus_io.py` `escape_residue` is the same rule for the generators, which refuse such
/// text before it is merged; `scripts/test_escape_residue.py` proves they do. This test is the
/// authority — it is the one check every path into the corpus passes through, scripted or not.
@Suite("Corpus quoting residue")
struct CorpusEscapeResidueTests {

    static var resources: URL {
        URL(fileURLWithPath: #filePath)          // …/Tests/VocabKitTests/CorpusEscapeResidueTests.swift
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/VocabKit/Resources")
    }

    /// What is wrong with `text`, or nil when nothing is.
    static func residue(in text: String) -> String? {
        if text.contains("''") {
            return "a run of ASCII apostrophes (shell `'\\''` read back as `'''`, or SQL `''`)"
        }
        if text.contains("\\") {
            return "a backslash (an escape nobody undid)"
        }
        if text.contains("\"\"") {
            return "a doubled double quote (CSV quoting)"
        }
        if text.range(of: #"&(?:[A-Za-z][A-Za-z0-9]*|#[0-9]+|#[xX][0-9A-Fa-f]+);"#,
                      options: .regularExpression) != nil {
            return "an HTML character reference"
        }
        return nil
    }

    /// Every string value in `json`, with a readable path. An array element that carries an `id`
    /// is named by it, so a failure says `para033.meanings.en` rather than `[92].meanings.en`.
    static func strings(in json: Any, path: String = "", into found: inout [(path: String, text: String)]) {
        switch json {
        case let text as String:
            found.append((path, text))
        case let object as [String: Any]:
            for (key, value) in object {
                strings(in: value, path: path.isEmpty ? key : "\(path).\(key)", into: &found)
            }
        case let array as [Any]:
            for (index, value) in array.enumerated() {
                let name = ((value as? [String: Any])?["id"] as? String) ?? "[\(index)]"
                strings(in: value, path: path.isEmpty ? name : "\(path).\(name)", into: &found)
            }
        default:
            break
        }
    }

    @Test("no string in any corpus file carries quoting residue")
    func noResidue() throws {
        let files = try FileManager.default
            .contentsOfDirectory(at: Self.resources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var inspected = 0
        var perFile: [String: [(path: String, text: String)]] = [:]
        var hits: [String] = []
        for file in files {
            let json = try JSONSerialization.jsonObject(with: Data(contentsOf: file))
            var found: [(path: String, text: String)] = []
            Self.strings(in: json, into: &found)
            perFile[file.lastPathComponent] = found
            inspected += found.count
            for (path, text) in found {
                if let why = Self.residue(in: text) {
                    hits.append("\(file.lastPathComponent) \(path): “\(text.prefix(90))” — \(why)")
                }
            }
        }

        // A walk that read nothing reports a clean corpus — the null result from an instrument
        // nobody checked that this project keeps logging. So the walk must be seen to reach the
        // place the defect actually lived: one English translation per shipped passage.
        #expect(files.count >= 8, "found \(files.count) corpus files — looking in the wrong place?")
        #expect(inspected > 100_000, "the walk saw only \(inspected) strings")
        let englishReached = perFile["passages.json", default: []]
            .filter { $0.path.hasSuffix(".meanings.en") }.count
        #expect(englishReached == PassageStore.shared.passages.count, """
            the walk reached \(englishReached) passage English translations; \
            the app ships \(PassageStore.shared.passages.count)
            """)

        #expect(hits.count == 0, """
            \(hits.count) corpus string(s) carry quoting residue. Correct the text; a quoting layer \
            was applied and never undone:
            \(hits.prefix(40).joined(separator: "\n"))
            """)
    }

    /// The rule has to fire, or it is decoration — and it must not fire on what a translation
    /// legitimately holds, or the next person to meet it will weaken it rather than read it.
    @Test("the rule flags each quoting residue and nothing a translation legitimately holds")
    func ruleIsCalibrated() {
        let damaged = [
            "The weather is nice today, isn'''t it?",       // the shipped shapes, verbatim
            "I'''m a little tired.",
            "On my father'''s birthday",
            "now I'''ve become able to speak",
            "it''s",                                         // SQL / YAML doubling
            "it'\\''s",                                      // the shell escape, intact
            "it\\'s",                                        // a backslash escape
            "a line\\nbreak",
            "say \"\"hi\"\"",                                // CSV
            "it&#39;s", "it&#x27;s", "salt &amp; pepper", "&quot;hi&quot;",
        ]
        for text in damaged {
            #expect(Self.residue(in: text) != nil, "missed: \(text)")
        }
        let clean = [
            "I'm a little tired.", "isn't it?", "the students' books", "'quoted'",
            "rock 'n' roll", "It’s fine.", "“Hello,” she said.", "He said \"hi\".",
            "Q&A", "AT&T", "salt & pepper; to taste", "R & D",
            "今天天气很好，不是吗？", "他说：“好。”", "わたしは「はい」といった。", "みずをのみます",
        ]
        for text in clean {
            #expect(Self.residue(in: text) == nil, "false positive: \(text)")
        }
    }
}
