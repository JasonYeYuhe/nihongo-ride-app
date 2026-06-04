/// Small kana-script utilities.
enum KanaScript {
    /// Converts katakana letters (U+30A1…U+30F4, ァ…ヴ) to their hiragana
    /// equivalents, leaving the prolonged-sound mark `ー` (U+30FC) and every other
    /// character unchanged. This lets the hiragana-based romaji table match
    /// katakana targets: `テレビ` → `てれび`, while `ー` keeps its own `-` producer.
    ///
    /// Small `ヵ` (U+30F5) and `ヶ` (U+30F6) are deliberately *not* converted: their
    /// hiragana forms `ゕ`/`ゖ` have no romaji producer, whereas the katakana forms
    /// do (`xka`/`xke` → `ヵ`/`ヶ` in the Mozc table), so leaving them keeps them typeable.
    static func katakanaToHiragana(_ string: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in string.unicodeScalars {
            if (0x30A1...0x30F4).contains(scalar.value),
               let hiragana = Unicode.Scalar(scalar.value - 0x60) {
                scalars.append(hiragana)
            } else {
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }
}
