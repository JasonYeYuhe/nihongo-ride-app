/// The result of feeding a single keystroke to a ``KanaInputMatcher``.
public enum InputResult: Equatable, Sendable {
    /// The key advanced along a valid path toward the target.
    case accepted
    /// The key is not valid here; matcher state is unchanged (the game can count an error).
    case rejected
    /// The key completed the whole target word.
    case completed
}

/// Per-keystroke, multi-path, **target-aware** romaji typing matcher — the
/// project's "mini-IME" for the typing game.
///
/// Given a target kana string (e.g. `"がっこう"`), it consumes romaji keystrokes
/// and reports whether each key is on a valid path to that target, when the word
/// is finished, and which keys are valid next.
///
/// Because it knows the target, it is deliberately lenient where a blind IME
/// would be ambiguous: `みんな` accepts `minna`, `minnna`, and `min'na`.
///
/// ## How it works
/// At construction it compiles "all romaji paths that spell the target" into a
/// character-level NFA (non-deterministic finite automaton), then tracks the set
/// of reachable states. Each keystroke filters that set; an empty result means
/// the key is wrong; reaching the accepting state means the word is complete.
/// See `docs/PLAN.md` §4 for the full design.
public struct KanaInputMatcher {
    /// The kana string being typed.
    public let target: String

    // Compiled NFA. Nodes are dense integer ids.
    private let transitions: [[Character: [Int]]]   // node id → (char → destination node ids)
    private let committedKana: [Int]                // node id → kana committed at that node
    private let acceptingNode: Int

    // Live state.
    private var active: Set<Int>
    private var typed: String = ""

    public init(target: String, table: RomajiKanaTable = .shared) {
        self.target = target
        // Match katakana targets by normalizing to hiragana (ー keeps its own producer).
        var builder = NFABuilder(target: Array(KanaScript.katakanaToHiragana(target)), table: table)
        builder.build()
        transitions = builder.transitions
        committedKana = builder.committedKana
        acceptingNode = builder.acceptingNode
        active = [builder.startNode]
    }

    /// Whether the whole target word has been typed.
    public var isComplete: Bool { active.contains(acceptingNode) }

    /// The romaji accepted so far (one valid path's worth of keystrokes).
    public var typedRomaji: String { typed }

    /// How many target kana are committed on the most-advanced live path.
    /// Useful for a progress indicator.
    public var completedKanaCount: Int {
        active.map { committedKana[$0] }.max() ?? 0
    }

    /// The set of keys that would be accepted next (for hint/highlight UI).
    public var expectedNextCharacters: Set<Character> {
        var characters = Set<Character>()
        for node in active {
            characters.formUnion(transitions[node].keys)
        }
        return characters
    }

    /// Feeds one keystroke. A rejected key leaves the matcher unchanged so the
    /// caller can simply count the error and let the user try again.
    public mutating func input(_ character: Character) -> InputResult {
        let key = Character(character.lowercased())
        var next = Set<Int>()
        for node in active {
            if let destinations = transitions[node][key] {
                next.formUnion(destinations)
            }
        }
        guard !next.isEmpty else { return .rejected }
        active = next
        typed.append(key)
        return isComplete ? .completed : .accepted
    }
}

// MARK: - NFA construction

/// Builds the character-level NFA for a target kana sequence from the romaji table.
private struct NFABuilder {
    let target: [Character]
    let table: RomajiKanaTable

    var transitions: [[Character: [Int]]] = []
    var committedKana: [Int] = []
    private var pendingByNode: [String] = []
    var acceptingNode = 0
    var startNode = 0

    /// A "boundary" node sits between kana, optionally owing some already-typed
    /// romaji (`pending`) to the next rule. Boundary nodes are de-duplicated and
    /// are the only nodes that get expanded.
    private struct Boundary: Hashable { let position: Int; let pending: String }
    private var boundaryNodes: [Boundary: Int] = [:]

    init(target: [Character], table: RomajiKanaTable) {
        self.target = target
        self.table = table
    }

    private mutating func makeNode(committed: Int, pending: String) -> Int {
        let id = transitions.count
        transitions.append([:])
        committedKana.append(committed)
        pendingByNode.append(pending)
        return id
    }

    /// Returns the boundary node for `(position, pending)`, creating it if new.
    private mutating func boundary(position: Int, pending: String) -> (id: Int, isNew: Bool) {
        let key = Boundary(position: position, pending: pending)
        if let existing = boundaryNodes[key] { return (existing, false) }
        let id = makeNode(committed: position, pending: pending)
        boundaryNodes[key] = id
        return (id, true)
    }

    private mutating func addEdge(from: Int, _ character: Character, to: Int) {
        transitions[from][character, default: []].append(to)
    }

    mutating func build() {
        startNode = boundary(position: 0, pending: "").id
        acceptingNode = boundary(position: target.count, pending: "").id

        var stack = [startNode]
        var enqueued: Set<Int> = [startNode]

        while let node = stack.popLast() {
            let position = committedKana[node]
            guard position < target.count else { continue }   // accepting / end: no expansion
            let pending = pendingByNode[node]
            let maxLength = min(table.maxOutputLength, target.count - position)

            for length in 1...maxLength {
                let kana = String(target[position ..< position + length])
                for production in table.productions(forOutput: kana) {
                    guard production.romaji.hasPrefix(pending) else { continue }
                    let remaining = Array(production.romaji.dropFirst(pending.count))
                    guard !remaining.isEmpty else { continue }

                    let destination = boundary(position: position + length, pending: production.pending)
                    // Lay down a chain of single-character edges for `remaining`.
                    var current = node
                    for (index, character) in remaining.enumerated() {
                        if index == remaining.count - 1 {
                            addEdge(from: current, character, to: destination.id)
                        } else {
                            let mid = makeNode(committed: position, pending: "")   // intermediate: kana not yet committed
                            addEdge(from: current, character, to: mid)
                            current = mid
                        }
                    }
                    if destination.isNew, enqueued.insert(destination.id).inserted {
                        stack.append(destination.id)
                    }
                }
            }
        }

        pruneDeadEnds()
    }

    /// Removes states (and the edges leading into them) that can no longer reach
    /// the accepting node — e.g. a sokuon `pending` consonant that the following
    /// kana cannot consume (`っ` + `か` offers `kk`/`xtu` but not `ss`). Without
    /// this the matcher would *accept* keystrokes into dead states and soft-lock
    /// the player, since there is no backspace. [Codex/Gemini review finding]
    private mutating func pruneDeadEnds() {
        var reverse: [Int: [Int]] = [:]
        for (source, edges) in transitions.enumerated() {
            for (_, dests) in edges {
                for dest in dests { reverse[dest, default: []].append(source) }
            }
        }
        var live: Set<Int> = [acceptingNode]
        var stack = [acceptingNode]
        while let node = stack.popLast() {
            for previous in reverse[node] ?? [] where live.insert(previous).inserted {
                stack.append(previous)
            }
        }
        for source in transitions.indices {
            guard live.contains(source) else { transitions[source] = [:]; continue }
            for (character, dests) in transitions[source] {
                let kept = dests.filter { live.contains($0) }
                transitions[source][character] = kept.isEmpty ? nil : kept
            }
        }
    }
}
