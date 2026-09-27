import Foundation

/// "3-day streak · 12 words and 4 forms due tomorrow" — the line the results screen ends on.
///
/// Every ride ends on the results screen, and until v1.34 that screen said nothing about the
/// streak or the review forecast, although both exist and the Ride Log draws both. This is the
/// copy matrix from PLAN-V1.34 §B1, decided before it was built, and it is pure so the matrix can
/// be held row by row against strings written out by hand rather than against the function itself.
/// `AppModel.tomorrowLine(zh:)` supplies the three numbers from the reads the Ride Log and Stats
/// already make; nothing here counts anything. "Due tomorrow" means due when the rider opens the
/// app tomorrow — the caller passes each forecast's `today` + `tomorrow`, because a card due or
/// overdue today and not reviewed is still due tomorrow (see `tomorrowLine(zh:)`).
///
/// The streak half is shown only from two days: "1-day streak" is a rider on their first day, and
/// saying so would announce the absence of a streak. The due half always names cards — words and
/// forms — never rides: a line that promised "12 rides" would be the wrong-denominator copy of
/// v1.32 §C2. English singulars come from `countLabel` ("1 word", "1 form"); the Chinese counter
/// 个 does not inflect, exactly as the tiles above the line write their counts.
///
/// English is written as a sentence: whichever half starts the line starts with a capital. With
/// the streak prefix that is "3-day streak", so the due half after the " · " stays lower-case;
/// without it the due half IS the start of the line — "Nothing due tomorrow", "12 words due
/// tomorrow" (a digit has no case and is left as it is). Chinese has no case and is unchanged.
///
/// **Where the line may not break (simulator pass, 2026-09-27).** At AX5 the line wraps, and on
/// the 402pt phone it wrapped as "4-day streak · 7 / words due / tomorrow" — the count at the end
/// of one line, its noun on the next — and as "连续 4 天 · 明天到 / 期 7 个词", splitting the word
/// 到期. So the composer joins what must stay together with characters that forbid a break and
/// draw nothing different: U+00A0 NO-BREAK SPACE between a count and its noun ("7\u{00A0}words",
/// "4\u{00A0}forms") or its measure word ("7\u{00A0}个\u{2060}词", "4\u{00A0}天"), which has a space's
/// advance, and U+2060 WORD JOINER inside 明天, 到期 and 变形 and between 个 and its noun (the verifier
/// found "…7 个" / "词" still possible), which has none. Measured with CoreText
/// in `V134B1TomorrowLineTests` (the device's two breaks reproduced first, as the control); the
/// line's pixels where it does not wrap are unchanged. VoiceOver reads a no-break space as a space
/// and ignores the word joiner, a default-ignorable format character, so the spoken line is the
/// same words as before. Everything else — the matrix, the " · ", the capitals — is as it was.
enum TomorrowLine {
    static func compose(streakDays: Int, wordsDue: Int, formsDue: Int, zh: Bool) -> String {
        let due: String
        switch (wordsDue > 0, formsDue > 0) {
        case (true, true):
            due = zh ? "明\u{2060}天到\u{2060}期 \(wordsDue)\u{00A0}个\u{2060}词、\(formsDue)\u{00A0}个\u{2060}变\u{2060}形"
                     : "\(count(wordsDue, "word")) and \(count(formsDue, "form")) due tomorrow"
        case (true, false):
            due = zh ? "明\u{2060}天到\u{2060}期 \(wordsDue)\u{00A0}个\u{2060}词"
                     : "\(count(wordsDue, "word")) due tomorrow"
        case (false, true):
            due = zh ? "明\u{2060}天到\u{2060}期 \(formsDue)\u{00A0}个\u{2060}变\u{2060}形"
                     : "\(count(formsDue, "form")) due tomorrow"
        case (false, false):
            due = zh ? "明\u{2060}天没有到\u{2060}期的复习" : "nothing due tomorrow"
        }
        guard streakDays >= 2 else { return zh ? due : due.prefix(1).uppercased() + due.dropFirst() }
        return (zh ? "连续 \(streakDays)\u{00A0}天 · " : "\(streakDays)-day streak · ") + due
    }

    /// `countLabel`'s words — its singular and plural — with its one space made a no-break space,
    /// so the count and its noun never part at a line end.
    private static func count(_ n: Int, _ noun: String) -> String {
        countLabel(n, noun).replacingOccurrences(of: " ", with: "\u{00A0}")
    }
}
