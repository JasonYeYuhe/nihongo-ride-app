import Foundation
import GameKit
import GameCore
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Game Center: authenticate the local player, submit Time Attack scores, and
/// report achievements. The dashboard entry is `GKAccessPoint` (cross-platform,
/// presents the dashboard itself) — shown only on non-game screens so it never
/// floats over the ride.
///
/// Mirrors ReminderScheduler / CloudKitSyncController: gated on a real bundle so
/// `swift run` (no Info.plist) and headless screenshot capture never touch
/// GameKit. Every API call is a no-op until the player is authenticated, so the
/// rest of the app is unaffected if the user isn't signed in to Game Center.
@MainActor
@Observable
final class GameCenterManager {
    /// App Store Connect leaderboard id (must match the ASC configuration).
    static let leaderboardTimeAttack = "ta_score"

    /// Achievement ids (must match the ASC configuration exactly).
    enum Achievement: String {
        case firstRide = "ach_first_ride"
        case words100  = "ach_words_100"
        case words1000 = "ach_words_1000"
        case streak7   = "ach_streak_7"
        case flawless  = "ach_flawless"
    }

    private(set) var isAuthenticated = false

    static var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil && !Screenshotter.isCapturing
    }

    /// Authenticate the local player. Call once at launch; GameKit invokes the
    /// handler on the main thread (immediately if already signed in, otherwise
    /// after the sign-in UI).
    func authenticate() {
        guard Self.isAvailable else { return }
        GKLocalPlayer.local.authenticateHandler = { viewController, _ in
            if let viewController { Self.present(viewController) }
            MainActor.assumeIsolated {
                self.isAuthenticated = GKLocalPlayer.local.isAuthenticated
                if self.isAuthenticated { self.configureAccessPoint() }
            }
        }
    }

    private func configureAccessPoint() {
        GKAccessPoint.shared.location = .topLeading
        GKAccessPoint.shared.showHighlights = true
    }

    /// Show/hide the Game Center access point. Visible only on non-game screens
    /// and only once authenticated.
    func setAccessPointActive(_ active: Bool) {
        guard Self.isAvailable else { return }
        GKAccessPoint.shared.isActive = active && isAuthenticated
    }

    /// High-level hook from `AppModel.finishGame` (non-practice runs only).
    /// Submits the Time Attack score and reports any achievements reached.
    func recordRun(summary: GameSummary, mode: GameMode,
                   lifetimeWords: Int, streakDays: Int, totalRuns: Int) {
        guard isAuthenticated else { return }

        if mode == .timeAttack, summary.score > 0, summary.wordsCompleted > 0 {
            submitScore(summary.score, leaderboardID: Self.leaderboardTimeAttack)
        }

        var earned: [(Achievement, Double)] = []
        if totalRuns >= 1 { earned.append((.firstRide, 100)) }
        if lifetimeWords > 0 {
            earned.append((.words100, Double(lifetimeWords) / 100 * 100))
            earned.append((.words1000, Double(lifetimeWords) / 1000 * 100))
        }
        if streakDays >= 7 { earned.append((.streak7, 100)) }
        if summary.grade == .flawless { earned.append((.flawless, 100)) }
        report(earned)
    }

    private func submitScore(_ score: Int, leaderboardID: String) {
        Task {
            try? await GKLeaderboard.submitScore(
                score, context: 0, player: GKLocalPlayer.local, leaderboardIDs: [leaderboardID])
        }
    }

    private func report(_ achievements: [(Achievement, Double)]) {
        guard !achievements.isEmpty else { return }
        // GKAchievement.report keeps the max percentComplete server-side, so
        // re-reporting an already-earned achievement each run is harmless.
        let items = achievements.map { ach, percent -> GKAchievement in
            let a = GKAchievement(identifier: ach.rawValue)
            a.percentComplete = min(100, max(0, percent))
            a.showsCompletionBanner = true
            return a
        }
        Task { try? await GKAchievement.report(items) }
    }

    /// Present GameKit's sign-in view controller when it hands us one.
    private static func present(_ viewController: GKViewController) {
        #if os(iOS)
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? UIApplication.shared.connectedScenes.first as? UIWindowScene
        guard let root = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
            ?? scene?.windows.first?.rootViewController else { return }
        root.present(viewController, animated: true)
        #elseif os(macOS)
        guard let host = (NSApp.keyWindow ?? NSApp.windows.first)?.contentViewController else { return }
        host.presentAsSheet(viewController)
        #endif
    }
}

#if os(iOS)
private typealias GKViewController = UIViewController
#elseif os(macOS)
private typealias GKViewController = NSViewController
#endif
