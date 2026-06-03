/// Small kana-script utilities.
enum KanaScript {
    /// Converts katakana letters (U+30A1…U+30F6) to their hiragana equivalents,
    /// leaving the prolonged-sound mark `ー` (U+30FC) and every other character
    /// unchanged. This lets the hiragana-based romaji table match katakana
    /// targets: `テレビ` → `てれび`, while `ー` keeps its own `-` producer.
    static func katakanaToHiragana(_ string: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in string.unicodeScalars {
            if (0x30A1...0x30F6).contains(scalar.value),
               let hiragana = Unicode.Scalar(scalar.value - 0x60) {
                scalars.append(hiragana)
            } else {
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }
}
