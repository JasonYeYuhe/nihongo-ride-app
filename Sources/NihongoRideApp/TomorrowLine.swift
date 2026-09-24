import Foundation

/// "3-day streak · 12 words and 4 forms due tomorrow" — the line the results screen ends on.
///
/// Every ride ends on the results screen, and until v1.34 that screen said nothing about the
/// streak or the review forecast, although both exist and the Ride Log draws both. This is the
/// copy matrix from PLAN-V1.34 §B1, decided before it was built, and it is pure so the matrix can
/// be held row by row against strings written out by hand rather than against the function itself.
/// `AppModel.tomorrowLine(zh:)` supplies the three numbers from the reads the Ride Log and Stats
/// already make; nothing here counts anything.
///
/// The streak half is shown only from two days: "1-day streak" is a rider on their first day, and
/// saying so would announce the absence of a streak. The due half always names cards — words and
/// forms — never rides: a line that promised "12 rides" would be the wrong-denominator copy of
/// v1.32 §C2. English singulars come from `countLabel` ("1 word", "1 form"); the Chinese counter
/// 个 does not inflect, exactly as the tiles above the line write their counts.
enum TomorrowLine {
    static func compose(streakDays: Int, wordsDue: Int, formsDue: Int, zh: Bool) -> String {
        let due: String
        switch (wordsDue > 0, formsDue > 0) {
        case (true, true):
            due = zh ? "明天到期 \(wordsDue) 个词、\(formsDue) 个变形"
                     : "\(countLabel(wordsDue, "word")) and \(countLabel(formsDue, "form")) due tomorrow"
        case (true, false):
            due = zh ? "明天到期 \(wordsDue) 个词"
                     : "\(countLabel(wordsDue, "word")) due tomorrow"
        case (false, true):
            due = zh ? "明天到期 \(formsDue) 个变形"
                     : "\(countLabel(formsDue, "form")) due tomorrow"
        case (false, false):
            due = zh ? "明天没有到期的复习" : "nothing due tomorrow"
        }
        guard streakDays >= 2 else { return due }
        return (zh ? "连续 \(streakDays) 天 · " : "\(streakDays)-day streak · ") + due
    }
}
