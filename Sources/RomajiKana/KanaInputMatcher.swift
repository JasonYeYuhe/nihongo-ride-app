/// The result of feeding a single keystroke to a ``KanaInputMatcher``.
public enum InputResult: Equatable, Sendable {
    /// The key advanced along a valid path toward the target.
    case accepted
    /// The key is not valid here; matcher state is unchanged.
    case rejected
    /// The key completed the whole target word.
    case completed
}

/// Per-keystroke, multi-path, target-aware romaji typing matcher.
public struct KanaInputMatcher {
    public let target: String

    public init(target: String, table: RomajiKanaTable = .shared) {
        self.target = target
    }

    public var isComplete: Bool { false }
    public var typedRomaji: String { "" }
    public var completedKanaCount: Int { 0 }
    public var expectedNextCharacters: Set<Character> { [] }

    public mutating func input(_ character: Character) -> InputResult { .rejected }
}
