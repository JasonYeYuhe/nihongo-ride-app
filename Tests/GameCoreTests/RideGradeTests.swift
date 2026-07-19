import Testing
@testable import GameCore

/// The grade is what the results screen, the share card, and the Game Center achievement
/// all read. It lived in the app target — which has no unit tests — and shipped a bug that
/// nothing could have caught there.
@Suite("RideGrade")
struct RideGradeTests {

    @Test("a run where the user typed nothing is not 'Steady'")
    func emptyRunIsNotSteady() {
        // GameSession.accuracy is 1.0 for zero keystrokes (0/0 defined as perfect), so this
        // is exactly what an abandoned run produced. It used to grade .steady, and the
        // results screen told the user "Solid pace, clean accuracy" for an empty ride.
        let g = RideGrade.grade(accuracy: 1.0, maxCombo: 0, wordsCompleted: 0, lapsedCount: 0)
        #expect(g == .lap)
    }

    @Test("a genuinely good run still grades Steady")
    func realRunIsSteady() {
        #expect(RideGrade.grade(accuracy: 0.93, maxCombo: 4, wordsCompleted: 12, lapsedCount: 1) == .steady)
    }

    @Test("flawless needs accuracy, no lapses, and a real combo")
    func flawless() {
        #expect(RideGrade.grade(accuracy: 0.99, maxCombo: 11, wordsCompleted: 12, lapsedCount: 0) == .flawless)
        #expect(RideGrade.grade(accuracy: 0.99, maxCombo: 2, wordsCompleted: 12, lapsedCount: 0) != .flawless,
                "a high score with no streak is not flawless")
        #expect(RideGrade.grade(accuracy: 0.99, maxCombo: 11, wordsCompleted: 12, lapsedCount: 1) != .flawless,
                "a lapsed word disqualifies flawless")
    }

    @Test("an empty run cannot reach flawless either, however the numbers land")
    func emptyRunIsNotFlawless() {
        // maxCombo 0 < max(5, -1) closes this today; asserted so it stays closed if the
        // combo threshold is ever loosened.
        #expect(RideGrade.grade(accuracy: 1.0, maxCombo: 0, wordsCompleted: 0, lapsedCount: 0) != .flawless)
    }

    @Test("a rough but real run grades Building, and a bad one takes another lap")
    func buildingAndLap() {
        #expect(RideGrade.grade(accuracy: 0.80, maxCombo: 2, wordsCompleted: 8, lapsedCount: 4) == .building)
        #expect(RideGrade.grade(accuracy: 0.50, maxCombo: 1, wordsCompleted: 8, lapsedCount: 6) == .lap)
    }

    @Test("typing accurately but finishing nothing is not a pass")
    func accurateButNothingFinished() {
        // Typed a few correct keys, quit mid-word: high accuracy, zero words. `.steady` and
        // `.building` both require a finished word, so this is a lap.
        #expect(RideGrade.grade(accuracy: 1.0, maxCombo: 3, wordsCompleted: 0, lapsedCount: 0) == .lap)
    }
}
