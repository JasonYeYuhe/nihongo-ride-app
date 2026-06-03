import Foundation

/// Romaji→kana mapping data, indexed for target-aware matching.
///
/// Backed by Google Mozc's `romanji-hiragana.tsv` (BSD-3-Clause).
/// See `THIRD_PARTY_LICENSES.md`.
public struct RomajiKanaTable: Sendable {
    /// The shared default table, parsed once from the bundled Mozc resource.
    public static let shared = RomajiKanaTable()

    init() {}
}
