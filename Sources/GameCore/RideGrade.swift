import Foundation

/// How well a run went.
///
/// Lives in GameCore, not in the app target, for two reasons. It is the single source of
/// truth shared by the results screen and the Game Center "Flawless Run" achievement — so
/// the badge a player sees and the achievement they earn can never disagree — and the app
/// target has no unit tests, so a rule that lives there is a rule nothing checks. This one
/// had a real bug for that exact reason (v1.12 §C).
public enum RideGrade: Sendable, Equatable {
    case flawless, steady, building, lap

    /// Grades a finished run from the four things that describe it.
    ///
    /// `wordsCompleted > 0` guards `.steady` as well as `.building`, and that is not
    /// symmetry for its own sake: `GameSession.accuracy` is 1.0 when no key was ever
    /// pressed (0/0 is defined as perfect), so a run the user opened and abandoned without
    /// typing arrived here with accuracy 1.0, no lapsed words, and sailed into `.steady` —
    /// the results screen congratulating them with "Solid pace, clean accuracy" for having
    /// done nothing at all. Such a run is correctly discarded by `logRun`, so no journal or
    /// Stats figure was ever wrong; the lie was confined to the screen the user was looking
    /// at. It now grades `.lap` ("Take another lap"), which is what an empty ride is.
    public static func grade(accuracy: Double, maxCombo: Int,
                             wordsCompleted: Int, lapsedCount: Int) -> RideGrade {
        let clean = lapsedCount == 0
        if accuracy >= 0.97 && clean && maxCombo >= max(5, wordsCompleted - 1) {
            return .flawless
        }
        if accuracy >= 0.90 && lapsedCount <= 2 && wordsCompleted > 0 { return .steady }
        if accuracy >= 0.75 && wordsCompleted > 0 { return .building }
        return .lap
    }
}
