import Testing
import Foundation

// The source scanner behind `OneBranchRuleTests`, and the tests that prove it reads code rather than
// comments or strings. Kept apart from the rules so a change to how Swift is read shows up as a
// change to THIS file, and its own controls sit next to it.

/// The one scanner. It reads Swift source as bytes, blanks comments and string contents (keeping
/// newlines, so line numbers stay true, and keeping interpolations, which are code), then finds
/// declarations and calls by brace and parenthesis matching.
enum CallSiteScanner {

    struct Declaration {
        /// `func`, `init`, `struct`, `class`, `enum`, `extension`, `actor`, or `protocol`.
        let keyword: String
        let name: String
        let keywordOffset: Int
        /// The text from the start of the line to the keyword — `public mutating`, `private`, …
        let modifiers: String
        /// Inside the parameter parentheses, for `func` and `init`.
        let parameters: Range<Int>?
        /// From `{` through `}` inclusive. Nil for a requirement with no body.
        let body: Range<Int>?
    }

    struct Call {
        let name: String
        /// The identifier chain before `.name`, e.g. `entitlements.ledger`; empty for an implicit
        /// `self` call or an implicit member (`.entitled(...)`).
        let receiver: String
        let dotPrefixed: Bool
        let nameOffset: Int
        /// Inside the parentheses, if the call has any.
        let arguments: Range<Int>?
        /// Every closure handed to the call: the trailing closure and each `{ }` literal that is
        /// an argument. Each range runs from `{` through `}` inclusive.
        let closures: [Range<Int>]
        /// From the receiver (or the name) to the end of the call, including a trailing closure.
        let extent: Range<Int>
    }

    struct File {
        let path: String
        /// Comments and string contents blanked to spaces. Newlines are preserved.
        let code: [UInt8]
        /// Comments blanked; string contents kept.
        let codeWithStrings: [UInt8]
        let declarations: [Declaration]
        private let lineStarts: [Int]

        init(path: String, source: String) {
            self.path = path
            let bytes = Array(source.utf8)
            let lexed = CallSiteScanner.lex(bytes)
            code = lexed.code
            codeWithStrings = lexed.withStrings
            var starts = [0]
            for (index, byte) in bytes.enumerated() where byte == 10 { starts.append(index + 1) }
            lineStarts = starts
            declarations = CallSiteScanner.declarations(in: lexed.code)
        }

        /// 1-based.
        func line(of offset: Int) -> Int {
            var low = 0, high = lineStarts.count - 1
            while low < high {
                let mid = (low + high + 1) / 2
                if lineStarts[mid] <= offset { low = mid } else { high = mid - 1 }
            }
            return low + 1
        }

        func location(_ offset: Int) -> String { "\(path):\(line(of: offset))" }

        func text(_ range: Range<Int>) -> String { String(decoding: code[range], as: UTF8.self) }

        var allCode: String { String(decoding: code, as: UTF8.self) }
        var allCodeWithStrings: String { String(decoding: codeWithStrings, as: UTF8.self) }

        /// A one-line excerpt of the call, for failure messages.
        func excerpt(_ call: Call) -> String {
            let end = min(call.extent.upperBound, call.extent.lowerBound + 160)
            return text(call.extent.lowerBound..<end)
                .split(whereSeparator: { $0 == "\n" })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: " ")
        }

        var functions: [Declaration] {
            declarations.filter { $0.keyword == "func" || $0.keyword == "init" }
        }

        func functions(named name: String) -> [Declaration] {
            functions.filter { $0.name == name }
        }

        /// Bodies of every `struct`/`class`/`enum`/`extension`/`actor` named `name` in this file.
        func typeBodies(named name: String) -> [Range<Int>] {
            declarations.filter { $0.keyword != "func" && $0.keyword != "init" && $0.name == name }
                .compactMap(\.body)
        }

        /// The innermost function or initialiser whose body contains `offset`.
        func enclosingFunction(of offset: Int) -> Declaration? {
            functions.filter { $0.body?.contains(offset) == true }
                .min { $0.body!.count < $1.body!.count }
        }

        /// The innermost `{ }` block inside `range` that contains `offset`, braces included.
        func innermostBlock(containing offset: Int, within range: Range<Int>) -> Range<Int>? {
            var stack: [Int] = []
            var best: Range<Int>?
            for index in range {
                if code[index] == UInt8(ascii: "{") { stack.append(index) }
                else if code[index] == UInt8(ascii: "}"), let open = stack.popLast() {
                    let block = open..<(index + 1)
                    if block.contains(offset), block.count < (best?.count ?? Int.max) { best = block }
                }
            }
            return best
        }

        /// Word-boundary occurrences of `word` in code (comments and strings excluded).
        func mentions(of word: String) -> [Int] {
            CallSiteScanner.occurrences(of: Array(word.utf8), in: code)
        }

        func calls(named name: String) -> [Call] {
            CallSiteScanner.calls(named: name, in: code)
        }

        /// The internal names of `function`'s parameters whose TYPE is a function type — found by
        /// the `->` in the type, never by the name: `ask: () -> Void`, `_ act: @escaping () -> Void`,
        /// `onAsked: (() -> Void)?`. A closure typed through a typealias has no `->` here and is missed.
        func closureParameters(of function: Declaration) -> [String] {
            guard let parameters = function.parameters else { return [] }
            var segments: [Range<Int>] = []
            var depth = 0, start = parameters.lowerBound
            for index in parameters {
                switch code[index] {
                case UInt8(ascii: "("), UInt8(ascii: "["), UInt8(ascii: "{"): depth += 1
                case UInt8(ascii: ")"), UInt8(ascii: "]"), UInt8(ascii: "}"): depth -= 1
                case UInt8(ascii: ",") where depth == 0: segments.append(start..<index); start = index + 1
                default: break
                }
            }
            segments.append(start..<parameters.upperBound)
            return segments.compactMap { segment in
                let parameter = text(segment)
                guard let colon = parameter.firstIndex(of: ":"),
                      parameter[parameter.index(after: colon)...].split(separator: "=", maxSplits: 1).first?.contains("->") == true
                else { return nil }
                return parameter[..<colon].split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "_") })
                    .last.map(String.init)     // `_ act` → `act`: the name the body uses
            }
        }

        /// True when `offset` lies inside a closure handed to a call named one of `names`.
        func isInsideClosure(handedTo names: Set<String>, _ offset: Int) -> Bool {
            names.contains { name in
                calls(named: name).contains { call in call.closures.contains { $0.contains(offset) } }
            }
        }
    }

    // MARK: Loading

    static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// Every `.swift` file under `Sources/`, recursively.
    static func loadSources() throws -> [File] {
        let sources = repoRoot.appendingPathComponent("Sources").standardizedFileURL
        guard let walker = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
        else { return [] }
        var files: [File] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            let full = url.standardizedFileURL.path
            let relative = full.hasPrefix(sources.path + "/")
                ? "Sources/" + full.dropFirst(sources.path.count + 1)
                : url.lastPathComponent
            files.append(File(path: relative, source: try String(contentsOf: url, encoding: .utf8)))
        }
        return files.sorted { $0.path < $1.path }
    }

    /// Loaded once per process; every real assertion reads the same bytes.
    static let shippedSources: Result<[File], Error> = Result { try loadSources() }

    // MARK: Lexing

    static func isIdentifier(_ byte: UInt8) -> Bool {
        (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122)
            || byte == 95 || byte >= 0x80
    }

    private enum Context {
        case string(multiline: Bool, hashes: Int)
        case interpolation(depth: Int)
    }

    /// Blanks comments (line, doc, and nested block) and string contents. Interpolations inside
    /// strings are kept as code; their delimiters — `\(` (or `\#(`) and the closing `)` — are
    /// blanked TOGETHER, so parentheses in the code view stay balanced. Blanking one without the
    /// other made every call with an interpolated argument unmatched, and so invisible to every
    /// rule; `shippedCodeViewsBalance` fails if that drifts again.
    static func lex(_ bytes: [UInt8]) -> (code: [UInt8], withStrings: [UInt8]) {
        var code = bytes
        var withStrings = bytes
        let count = bytes.count
        var stack: [Context] = []
        var index = 0

        func blankComment(_ at: Int) {
            guard bytes[at] != 10 else { return }
            code[at] = 32
            withStrings[at] = 32
        }
        func blankString(_ at: Int) {
            guard bytes[at] != 10 else { return }
            code[at] = 32
        }
        func hashesFollow(_ at: Int, _ hashes: Int) -> Bool {
            guard at + hashes <= count else { return false }
            return (0..<hashes).allSatisfy { bytes[at + $0] == UInt8(ascii: "#") }
        }

        while index < count {
            let byte = bytes[index]

            if case .string(let multiline, let hashes)? = stack.last {
                if byte == UInt8(ascii: "\\") {
                    var next = index + 1
                    var seen = 0
                    while seen < hashes, next < count, bytes[next] == UInt8(ascii: "#") { seen += 1; next += 1 }
                    if seen == hashes, next < count, bytes[next] == UInt8(ascii: "(") {
                        for at in index...next { blankString(at) }   // `\`, any `#`, and the `(`
                        stack.append(.interpolation(depth: 1))
                        index = next + 1
                        continue
                    }
                    if hashes == 0 {
                        blankString(index)
                        if index + 1 < count { blankString(index + 1) }
                        index += 2
                        continue
                    }
                }
                if byte == UInt8(ascii: "\"") {
                    if multiline {
                        if index + 2 < count, bytes[index + 1] == UInt8(ascii: "\""),
                           bytes[index + 2] == UInt8(ascii: "\""), hashesFollow(index + 3, hashes) {
                            stack.removeLast()
                            index += 3 + hashes
                            continue
                        }
                    } else if hashesFollow(index + 1, hashes) {
                        stack.removeLast()
                        index += 1 + hashes
                        continue
                    }
                }
                if byte == 10, !multiline {
                    // An unterminated single-line string: recover at the newline.
                    stack.removeLast()
                    index += 1
                    continue
                }
                blankString(index)
                index += 1
                continue
            }

            if case .interpolation(let depth)? = stack.last {
                if byte == UInt8(ascii: "(") {
                    stack[stack.count - 1] = .interpolation(depth: depth + 1)
                } else if byte == UInt8(ascii: ")") {
                    if depth == 1 {
                        stack.removeLast()
                        blankString(index)
                        index += 1
                        continue
                    }
                    stack[stack.count - 1] = .interpolation(depth: depth - 1)
                }
            }

            if byte == UInt8(ascii: "/"), index + 1 < count, bytes[index + 1] == UInt8(ascii: "/") {
                while index < count, bytes[index] != 10 { blankComment(index); index += 1 }
                continue
            }
            if byte == UInt8(ascii: "/"), index + 1 < count, bytes[index + 1] == UInt8(ascii: "*") {
                var depth = 0
                repeat {
                    if index + 1 < count, bytes[index] == UInt8(ascii: "/"), bytes[index + 1] == UInt8(ascii: "*") {
                        depth += 1; blankComment(index); blankComment(index + 1); index += 2
                    } else if index + 1 < count, bytes[index] == UInt8(ascii: "*"), bytes[index + 1] == UInt8(ascii: "/") {
                        depth -= 1; blankComment(index); blankComment(index + 1); index += 2
                    } else {
                        blankComment(index); index += 1
                    }
                } while depth > 0 && index < count
                continue
            }
            if byte == UInt8(ascii: "\"") || byte == UInt8(ascii: "#") {
                var quote = index
                var hashes = 0
                while quote < count, bytes[quote] == UInt8(ascii: "#") { hashes += 1; quote += 1 }
                if quote < count, bytes[quote] == UInt8(ascii: "\"") {
                    let multiline = quote + 2 < count && bytes[quote + 1] == UInt8(ascii: "\"")
                        && bytes[quote + 2] == UInt8(ascii: "\"")
                    stack.append(.string(multiline: multiline, hashes: hashes))
                    index = quote + (multiline ? 3 : 1)
                    continue
                }
            }
            index += 1
        }
        return (code, withStrings)
    }

    // MARK: Structure

    static func matching(_ code: [UInt8], open: Int) -> Int? {
        let opener = code[open]
        let closer: UInt8
        switch opener {
        case UInt8(ascii: "("): closer = UInt8(ascii: ")")
        case UInt8(ascii: "{"): closer = UInt8(ascii: "}")
        case UInt8(ascii: "<"): closer = UInt8(ascii: ">")
        default: return nil
        }
        var depth = 0
        var index = open
        while index < code.count {
            if code[index] == opener { depth += 1 }
            else if code[index] == closer {
                depth -= 1
                if depth == 0 { return index }
            }
            index += 1
        }
        return nil
    }

    static func occurrences(of needle: [UInt8], in code: [UInt8]) -> [Int] {
        guard !needle.isEmpty, code.count >= needle.count else { return [] }
        var hits: [Int] = []
        var index = 0
        let last = code.count - needle.count
        while index <= last {
            if code[index] == needle[0], code[index..<(index + needle.count)].elementsEqual(needle),
               index == 0 || !isIdentifier(code[index - 1]),
               index + needle.count == code.count || !isIdentifier(code[index + needle.count]) {
                hits.append(index)
                index += needle.count
            } else {
                index += 1
            }
        }
        return hits
    }

    static func word(in code: [UInt8], at start: Int) -> (String, Int)? {
        guard start < code.count, isIdentifier(code[start]) else { return nil }
        var end = start
        while end < code.count, isIdentifier(code[end]) { end += 1 }
        return (String(decoding: code[start..<end], as: UTF8.self), end)
    }

    static func skipSpace(_ code: [UInt8], _ from: Int, newlines: Bool = true) -> Int {
        var index = from
        while index < code.count,
              code[index] == 32 || code[index] == 9 || (newlines && (code[index] == 10 || code[index] == 13)) {
            index += 1
        }
        return index
    }

    /// Words that end a declaration's header without a body (a protocol requirement), or that
    /// make the word before `name` a declaration rather than a call.
    static let declarationStarters: Set<String> = [
        "func", "var", "let", "case", "init", "struct", "class", "enum", "extension", "actor",
        "protocol", "subscript", "typealias", "static", "public", "private", "internal",
        "fileprivate", "open", "mutating", "nonisolated", "override", "convenience", "required",
        "final", "lazy", "weak", "deinit",
    ]
    static let typeKeywords: Set<String> = ["struct", "class", "enum", "extension", "actor", "protocol"]

    static func declarations(in code: [UInt8]) -> [Declaration] {
        var out: [Declaration] = []
        let count = code.count
        var index = 0
        while index < count {
            guard isIdentifier(code[index]), index == 0 || !isIdentifier(code[index - 1]),
                  let (keyword, afterKeyword) = word(in: code, at: index)
            else { index += 1; continue }
            defer { index = afterKeyword }
            guard keyword == "func" || keyword == "init" || typeKeywords.contains(keyword) else { continue }

            var lineStart = index
            while lineStart > 0, code[lineStart - 1] != 10 { lineStart -= 1 }
            let modifiers = String(decoding: code[lineStart..<index], as: UTF8.self)
                .trimmingCharacters(in: .whitespaces)

            if keyword == "func" || keyword == "init" {
                var cursor: Int
                let name: String
                if keyword == "init" {
                    // `self.init(` and `Foo.init(` are calls.
                    var before = index - 1
                    while before >= 0, code[before] == 32 || code[before] == 9 { before -= 1 }
                    if before >= 0, code[before] == UInt8(ascii: ".") { continue }
                    name = "init"
                    cursor = afterKeyword
                    if cursor < count, code[cursor] == UInt8(ascii: "?") || code[cursor] == UInt8(ascii: "!") { cursor += 1 }
                } else {
                    cursor = skipSpace(code, afterKeyword)
                    if let (identifier, end) = word(in: code, at: cursor) {
                        name = identifier
                        cursor = end
                    } else {
                        var end = cursor
                        while end < count, code[end] != UInt8(ascii: "("), code[end] != UInt8(ascii: "<"),
                              code[end] != 32, code[end] != 10 { end += 1 }
                        name = String(decoding: code[cursor..<end], as: UTF8.self)
                        cursor = end
                    }
                }
                cursor = skipSpace(code, cursor)
                if cursor < count, code[cursor] == UInt8(ascii: "<"), let close = matching(code, open: cursor) {
                    cursor = skipSpace(code, close + 1)
                }
                guard cursor < count, code[cursor] == UInt8(ascii: "("),
                      let closeParen = matching(code, open: cursor)
                else { continue }
                let parameters = (cursor + 1)..<closeParen
                var body: Range<Int>?
                var scan = closeParen + 1
                while scan < count {
                    let byte = code[scan]
                    if byte == UInt8(ascii: "{") {
                        if let close = matching(code, open: scan) { body = scan..<(close + 1) }
                        break
                    }
                    if byte == UInt8(ascii: "}") || byte == UInt8(ascii: ";") || byte == UInt8(ascii: "@") { break }
                    if isIdentifier(byte), !isIdentifier(code[scan - 1]), let (next, end) = word(in: code, at: scan) {
                        if declarationStarters.contains(next) { break }
                        scan = end
                        continue
                    }
                    scan += 1
                }
                out.append(Declaration(keyword: keyword, name: name, keywordOffset: index,
                                       modifiers: modifiers, parameters: parameters, body: body))
            } else {
                let nameStart = skipSpace(code, afterKeyword)
                guard let (first, firstEnd) = word(in: code, at: nameStart),
                      !declarationStarters.contains(first)
                else { continue }
                var name = first
                var cursor = firstEnd
                while cursor + 1 < count, code[cursor] == UInt8(ascii: "."), let (part, end) = word(in: code, at: cursor + 1) {
                    name += "." + part
                    cursor = end
                }
                var body: Range<Int>?
                var scan = cursor
                while scan < count {
                    if code[scan] == UInt8(ascii: "{") {
                        if let close = matching(code, open: scan) { body = scan..<(close + 1) }
                        break
                    }
                    if code[scan] == UInt8(ascii: "}") || code[scan] == UInt8(ascii: ";") { break }
                    scan += 1
                }
                out.append(Declaration(keyword: keyword, name: name, keywordOffset: index,
                                       modifiers: modifiers, parameters: nil, body: body))
            }
        }
        return out
    }

    static func calls(named name: String, in code: [UInt8]) -> [Call] {
        let count = code.count
        var out: [Call] = []
        for hit in occurrences(of: Array(name.utf8), in: code) {
            // The word before, if the name follows it directly: `func apply(` is a declaration.
            var before = hit - 1
            while before >= 0, code[before] == 32 || code[before] == 9 || code[before] == 10 { before -= 1 }
            if before >= 0, isIdentifier(code[before]) {
                var start = before
                while start > 0, isIdentifier(code[start - 1]) { start -= 1 }
                let previous = String(decoding: code[start...before], as: UTF8.self)
                if declarationStarters.contains(previous) { continue }
            }

            var cursor = skipSpace(code, hit + name.utf8.count, newlines: false)
            var arguments: Range<Int>?
            var end = hit + name.utf8.count
            var closures: [Range<Int>] = []
            if cursor < count, code[cursor] == UInt8(ascii: "("), let close = matching(code, open: cursor) {
                arguments = (cursor + 1)..<close
                var scan = cursor + 1
                while scan < close {
                    if code[scan] == UInt8(ascii: "{"), let blockEnd = matching(code, open: scan) {
                        closures.append(scan..<(blockEnd + 1))
                        scan = blockEnd + 1
                    } else {
                        scan += 1
                    }
                }
                end = close + 1
                cursor = skipSpace(code, close + 1, newlines: false)
            }
            // `if ledger.apply(x) {` — Swift allows no trailing closure in a condition, so that brace
            // opens the statement's body, not a closure handed to the call.
            if cursor < count, code[cursor] == UInt8(ascii: "{"), !isInConditionHead(code, hit),
               let close = matching(code, open: cursor) {
                closures.append(cursor..<(close + 1))
                end = close + 1
            }
            guard arguments != nil || !closures.isEmpty else { continue }

            var receiver = ""
            var start = hit
            let dotPrefixed = hit > 0 && code[hit - 1] == UInt8(ascii: ".")
            if dotPrefixed {
                var scan = hit - 1
                while scan > 0 {
                    let byte = code[scan - 1]
                    if isIdentifier(byte) || byte == UInt8(ascii: ".") || byte == UInt8(ascii: "?")
                        || byte == UInt8(ascii: "!") { scan -= 1 } else { break }
                }
                receiver = String(decoding: code[scan..<(hit - 1)], as: UTF8.self)
                start = scan
            }
            out.append(Call(name: name, receiver: receiver, dotPrefixed: dotPrefixed, nameOffset: hit,
                            arguments: arguments, closures: closures, extent: start..<end))
        }
        return out
    }

    /// True when `offset` sits in the condition of an `if`, `guard`, `while` or `switch` that
    /// starts earlier on the same line — no `{` between that keyword and `offset`.
    static func isInConditionHead(_ code: [UInt8], _ offset: Int) -> Bool {
        var lineStart = offset
        while lineStart > 0, code[lineStart - 1] != 10 { lineStart -= 1 }
        let prefix = String(decoding: code[lineStart..<offset], as: UTF8.self)
        guard let regex = try? NSRegularExpression(pattern: #"\b(?:if|guard|while|switch)\b"#),
              let last = regex.matches(in: prefix, range: NSRange(prefix.startIndex..., in: prefix)).last,
              let keyword = Range(last.range, in: prefix)
        else { return false }
        return !prefix[keyword.upperBound...].contains("{")
    }

    /// `self?.entitlements.ledger` → `["entitlements", "ledger"]`.
    static func receiverComponents(_ receiver: String) -> [String] {
        let parts = receiver.replacingOccurrences(of: "?", with: "").replacingOccurrences(of: "!", with: "")
            .split(separator: ".").map(String.init)
        if let first = parts.first, first == "self" || first == "Self" { return Array(parts.dropFirst()) }
        return parts
    }

    /// Names captured by `pattern`'s first group, across `text`.
    static func captures(_ pattern: String, in text: String) -> Set<String> {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var out: Set<String> = []
        for match in regex.matches(in: text, range: range) where match.numberOfRanges > 1 {
            if let captured = Range(match.range(at: 1), in: text) { out.insert(String(text[captured])) }
        }
        return out
    }

    /// Where a file's code view stops pairing `(` with `)` or `{` with `}`; empty when both pair up.
    static func unbalanced(_ file: File) -> [String] {
        var out: [String] = []
        for (open, close) in [(UInt8(ascii: "("), UInt8(ascii: ")")), (UInt8(ascii: "{"), UInt8(ascii: "}"))] {
            var depth = 0
            for (index, byte) in file.code.enumerated() {
                if byte == open { depth += 1 } else if byte == close { depth -= 1 }
                if depth < 0 { out.append("\(file.location(index)) closes a \(Character(Unicode.Scalar(open))) that was never opened"); break }
            }
            if depth > 0 { out.append("\(file.path) leaves \(depth) \(Character(Unicode.Scalar(open))) unclosed") }
        }
        return out
    }

    /// Each match's first two groups, in order, across `text`.
    static func capturePairs(_ pattern: String, in text: String) -> [(String, String)] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard match.numberOfRanges > 2, let first = Range(match.range(at: 1), in: text),
                  let second = Range(match.range(at: 2), in: text) else { return nil }
            return (String(text[first]), String(text[second]))
        }
    }
}

@Suite("The call-site scanner reads code, not comments or strings")
struct CallSiteScannerTests {

    @Test("comments, doc comments, nested block comments and strings are blind; interpolations are code")
    func commentsAndStringsAreBlind() {
        let file = CallSiteScanner.File(path: "Sample.swift", source: #"""
            // ledger.save(to: defaults)
            /// record.apply(.silent)
            /* record.apply(.silent) /* nested */ ledger.save(to: stillAComment) */
            let s = "ledger.save(to: defaults) // not a comment either"
            let url = "https://example.com"; ledger.save(to: afterAString)
            let block = """
                record.apply(.silent)
                """
            let escaped = "a \"quoted\" ledger.save(to: x)"
            let spliced = "\(ledger.save(to: interpolated))"
            """#)
        let saves = file.calls(named: "save")
        #expect(saves.count == 2,
                "expected the call after a string holding // and the interpolated call, got \(saves.map { file.line(of: $0.nameOffset) })")
        #expect(saves.map { file.line(of: $0.nameOffset) } == [5, 10],
                "line numbers drifted: \(saves.map { file.line(of: $0.nameOffset) })")
        #expect(file.calls(named: "apply").isEmpty, "a commented or quoted apply was read as code")
        #expect(file.allCodeWithStrings.contains("https://example.com"), "the strings-kept view lost a string")
        #expect(!file.allCode.contains("example.com"), "the code view kept a string's contents")
    }

    /// The sample above puts a call INSIDE an interpolation, which stays balanced however the
    /// delimiters are blanked. This puts interpolations inside a call's ARGUMENTS — the shape that
    /// went unmatched and vanished from every rule when only the `)` was blanked.
    @Test("a call whose arguments hold an interpolated string is still a call, with its arguments")
    func interpolatedArgumentsKeepTheCall() throws {
        let file = CallSiteScanner.File(path: "Sample.swift", source: ##"""
            ledger.save(to: UserDefaults(suiteName: "group.\(Self.teamID)")!)
            ledger.save(to: UserDefaults(suiteName: #"group.\#(Self.teamID)"#)!)
            ledger.save(to: UserDefaults(suiteName: "g.\(names["a\(1)"] ?? "")")!)
            let decision = ledger.requestIfEarned(moment: m, note: """
                ride \(n)
                """, ask: {})
            """##)
        let saves = file.calls(named: "save")
        #expect(saves.map { file.line(of: $0.nameOffset) } == [1, 2, 3], "a call with an interpolated argument was lost: \(saves.map { file.line(of: $0.nameOffset) })")
        #expect(saves.allSatisfy { $0.arguments.map { file.text($0).contains("suiteName:") } ?? false }, "a call's arguments were cut short")
        let request = try #require(file.calls(named: "requestIfEarned").first, "a call with a multi-line interpolated argument was lost")
        #expect(request.closures.count == 1 && file.line(of: request.extent.upperBound - 1) == 6)
        #expect(file.calls(named: "teamID").isEmpty && file.mentions(of: "teamID").count == 2, "an interpolation is code, not a call")
    }

    /// Lexer drift shows up here first: every rule matches `(` with `)` and `{` with `}`, and a
    /// view that leaves one unpaired silently drops every call that spans it.
    @Test("every shipped file's code view has balanced parentheses and braces")
    func shippedCodeViewsBalance() throws {
        // Control, through the same function: no shipped file has an unpaired bracket inside a
        // string or comment today, so only a planted one can show the check able to fail.
        let broken = CallSiteScanner.File(path: "Broken.swift", source: "func f() {\n    g(\"}\")\n    h(x))\n")
        #expect(CallSiteScanner.unbalanced(broken) == ["Broken.swift:3 closes a ( that was never opened", "Broken.swift leaves 1 { unclosed"],
                "the balance check does not report what it must: \(CallSiteScanner.unbalanced(broken))")
        let files = try CallSiteScanner.shippedSources.get()
        #expect(files.count >= 80, "only \(files.count) Swift files under Sources/ — the check is reading nothing")
        let unbalanced = files.flatMap(CallSiteScanner.unbalanced)
        #expect(unbalanced.isEmpty, "\(unbalanced.count) unbalanced code view(s) — the lexer has drifted:\n\(unbalanced.prefix(10).joined(separator: "\n"))")
    }

    @Test("declarations are not calls; closures, receivers and enclosing functions are found")
    func structureIsFound() throws {
        let file = CallSiteScanner.File(path: "Sample.swift", source: #"""
            struct Buyer {
                private mutating func record(_ e: Event) {}
                func purchase() async {
                    await product.purchase()
                }
                func trailing() async {
                    await self?.ledger.purchasing(lifetimeMetres: 1) {
                        await x.purchase()
                    }
                }
                func labelled() async {
                    await ledger.purchasing(lifetimeMetres: 1, buy: { await y.purchase() })
                }
                func noParens() { model.considerReviewPrompt { requestReview() } }
            }
            """#)
        let purchases = file.calls(named: "purchase")
        #expect(purchases.count == 3, "the declaration `func purchase()` must not count as a call")
        #expect(purchases.map(\.receiver) == ["product", "x", "y"])
        #expect(file.enclosingFunction(of: purchases[0].nameOffset)?.name == "purchase")
        #expect(file.enclosingFunction(of: purchases[1].nameOffset)?.name == "trailing")

        let purchasing = file.calls(named: "purchasing")
        #expect(purchasing.count == 2)
        #expect(purchasing.first?.receiver == "self?.ledger")
        #expect(file.isInsideClosure(handedTo: ["purchasing"], purchases[1].nameOffset), "a trailing closure was not seen")
        #expect(file.isInsideClosure(handedTo: ["purchasing"], purchases[2].nameOffset), "a closure argument was not seen")
        #expect(!file.isInsideClosure(handedTo: ["purchasing"], purchases[0].nameOffset),
                "the scanner reports every call as inside a closure — it is not discriminating")

        let review = try #require(file.calls(named: "considerReviewPrompt").first, "a call with only a trailing closure was missed")
        #expect(review.arguments == nil && review.closures.count == 1)
        let record = try #require(file.functions(named: "record").first)
        #expect(record.modifiers.contains("private") && record.modifiers.contains("mutating"))
        #expect(file.typeBodies(named: "Buyer").count == 1)

        let wrapper = CallSiteScanner.File(path: "Wrapper.swift", source: #"""
            func consider(now: Date = Date(), _ act: @escaping @MainActor () -> Void, onAsked: (() -> Void)?,
                          map: [String: (Int) -> Void] = [:], ask: Ask, count: Int = { 1 }()) {}
            """#)
        let function = try #require(wrapper.functions.first)
        #expect(wrapper.closureParameters(of: function) == ["act", "onAsked", "map"],
                "closure parameters must be found by their type: \(wrapper.closureParameters(of: function))")
    }

    /// Swift allows no trailing closure in a condition, so the brace after `if x.apply(y)` is the
    /// statement's body. Read as a closure, every call inside that body would look "handed to"
    /// the call in the condition — a way for a split to pass as inside.
    @Test("the brace after a call in an if/guard/switch condition is a body, not a closure")
    func conditionBodiesAreNotClosures() throws {
        let file = CallSiteScanner.File(path: "Sample.swift", source: #"""
            func sample() async {
                if record.apply(signal) { ledger.save(to: defaults) }
                switch try await product.purchase() { default: break }
                if ready { ledger.purchasing(lifetimeMetres: 1) { await x.purchase() } }
            }
            """#)
        let apply = try #require(file.calls(named: "apply").first)
        #expect(apply.closures.isEmpty, "an if body was read as a trailing closure of the condition's call")
        let save = try #require(file.calls(named: "save").first)
        #expect(!file.isInsideClosure(handedTo: ["apply"], save.nameOffset))
        let purchases = file.calls(named: "purchase")
        #expect(purchases.count == 2 && purchases[0].closures.isEmpty, "a switch body was read as a closure")
        // Control: a real trailing closure that follows a condition's `{` on the same line is still seen.
        #expect(file.isInsideClosure(handedTo: ["purchasing"], purchases[1].nameOffset),
                "the condition rule swallowed a genuine trailing closure")
    }
}
