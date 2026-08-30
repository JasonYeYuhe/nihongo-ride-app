import SwiftUI
import GameCore
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

@main
struct NihongoRideApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #elseif os(iOS)
    @UIApplicationDelegateAdaptor(IOSAppDelegate.self) private var appDelegate
    #endif
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Nihongo Ride") {
            #if os(macOS)
            // Dev-only: NIHONGO_WINDOW=1440x900 pins the window to an exact
            // App Store screenshot size for real-window captures
            // (`screencapture -l`) — ImageRenderer can't draw native controls.
            if let size = Self.fixedWindowSize {
                RootView()
                    .environment(model)
                    .frame(width: size.width, height: size.height)
            } else {
                RootView()
                    .environment(model)
                    .frame(minWidth: 880, minHeight: 600)
            }
            #else
            RootView()
                .environment(model)
            #endif
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        #endif
    }

    #if os(macOS)
    private static let fixedWindowSize: CGSize? = {
        guard let spec = ProcessInfo.processInfo.environment["NIHONGO_WINDOW"] else { return nil }
        let parts = spec.lowercased().split(separator: "x").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        return CGSize(width: parts[0], height: parts[1])
    }()
    #endif
}

#if os(macOS)
/// Activates the app when launched via `swift run` (no bundle to do it for us).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Headless screenshot mode: render screens to PNGs and exit (no window).
        if let dir = ProcessInfo.processInfo.environment["NIHONGO_SHOT"] {
            Screenshotter.capture(into: dir)
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // SwiftPM doesn't compile an asset catalog, so set the Dock icon at runtime.
        // Xcode-built app gets its icon from xcode/Assets.xcassets automatically.
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
        #endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
#elseif os(iOS)
/// iOS launch hook — only used for the dev-only screenshot mode (gated behind an
/// env var that is never set in shipping builds).
final class IOSAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        if ProcessInfo.processInfo.environment["NIHONGO_SHOT"] != nil {
            // iOS sandbox: write into the app's Documents container.
            let dir = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                Screenshotter.capture(into: dir)
                exit(0)
            }
        }
        return true
    }
}
#endif

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            screen
                .transition(.screenLift)
                .id(model.screen)
                // Incoming screen must stack above the outgoing one, or the
                // dying view eats taps during the 0.42s transition.
                .zIndex(Double(model.navCount))
        }
        #if os(iOS)
        // A scrolling screen's content passes UNDER the transparent status bar — that is
        // normal iOS behaviour, not a layout bug (verified against a minimal reproduction:
        // every structural variant does it, and it has been so since the first iPhone
        // build). System apps mask it with a navigation bar's material. This app has none,
        // so a status-bar-height fade of the SAME colour as the background sits at the top:
        // invisible when nothing is under it, and it cleanly hides content that scrolls up
        // behind the clock. Only on the flat-background screens — the ride and results
        // screens bleed the scene to the top on purpose, and a band there would cut into it.
        .overlay(alignment: .top) {
            if flatBackgroundScreen(model.screen) {
                GeometryReader { geo in
                    LinearGradient(colors: [Theme.backgroundTop, Theme.backgroundTop,
                                            Theme.backgroundTop.opacity(0)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: geo.safeAreaInsets.top + 8)
                        .ignoresSafeArea(edges: .top)
                        .allowsHitTesting(false)
                }
            }
        }
        #endif
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: model.screen)
        .preferredColorScheme(.dark)
        // Debug-only: jump straight to a screen so its layout can be checked on a device at
        // a large text size. ImageRenderer ignores dynamicTypeSize, so the headless gate is
        // blind to exactly the failures Dynamic Type causes (v1.14 §C found three shipped
        // ones), and Gate E's "verify on a device" was previously a manual walk through the
        // app — impractical to repeat per text size. DEBUG keeps it out of any archive, and
        // the simulator gate keeps it away from real data: the harness WRITES (it finishes a
        // run, which persists SRS and logs a ride) — see jumpToDebugScreen.
        //   NIHONGO_DEBUG_SCREEN=menu|results|conj-results|game xcrun simctl launch …
        #if DEBUG && targetEnvironment(simulator)
        .task { model.jumpToDebugScreen() }
        #endif
        // Keep the due-reminder schedule and iCloud sync fresh as days pass.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.appBecameActive() }
            // Leaving the foreground is the last moment we are guaranteed to run. A
            // conjugation drill writes SRS after EVERY prompt but only reschedules when the
            // drill ends, so backgrounding mid-drill (and then being terminated) left the
            // badge and the next 7 days of reminders describing a store that had moved on.
            // Both surfaces, not just the badge: every other site that moves the due count
            // rewrites the widget snapshot alongside the reminders, and refreshing only one
            // here recreated the badge-vs-widget split v1.14 §B/§D existed to close — a
            // drill abandoned mid-way left a badge of 2 beside a widget still reading 12.
            if phase == .background {
                model.refreshReminders()
                model.refreshWidgetSnapshot()
            }
        }
        // Game Center access point: show on non-game screens only (never over the ride).
        .onChange(of: model.screen) { _, screen in
            model.gameCenter.setAccessPointActive(showsAccessPoint(screen))
        }
        .onChange(of: model.gameCenter.isAuthenticated) { _, _ in
            model.gameCenter.setAccessPointActive(showsAccessPoint(model.screen))
        }
        // Surfaces a word-list error from a path with no local alert (the in-game /
        // results ★ tap hitting the per-list cap), instead of swallowing it.
        .alert(model.languageCode == "zh" ? "无法完成" : "Can't do that",
               isPresented: Binding(get: { model.lastListError != nil },
                                    set: { if !$0 { model.lastListError = nil } })) {
            Button("OK", role: .cancel) { model.lastListError = nil }
        } message: {
            if let error = model.lastListError {
                Text(ListsView.message(for: error, zh: model.languageCode == "zh"))
            }
        }
        // A user-initiated data write (list CRUD / ★) failed to persist — surface it
        // once so silent data loss is visible. Background writes only log (no alert).
        .alert(model.lastPersistError == .listsUnreadable
               ? (model.languageCode == "zh" ? "读不到词单" : "Can't read your lists")
               : (model.languageCode == "zh" ? "保存失败" : "Couldn't save"),
               isPresented: Binding(get: { model.lastPersistError != nil },
                                    set: { if !$0 { model.lastPersistError = nil } })) {
            // The unreadable case gets a Retry, because the failure is usually transient
            // (file protection while the device is locked, a busy volume) and "relaunch the
            // app" is not a recovery path a learner should have to invent. (v1.16 §C.)
            if model.lastPersistError == .listsUnreadable {
                Button(model.languageCode == "zh" ? "重试" : "Retry") {
                    model.lastPersistError = model.retryLoadWordLists() ? nil : .listsUnreadable
                }
            }
            Button("OK", role: .cancel) { model.lastPersistError = nil }
        } message: {
            if let error = model.lastPersistError {
                Text(error.message(zh: model.languageCode == "zh"))
            }
        }
    }

    /// The Game Center access point shows on calm non-game screens only — never
    /// over the ride, and not over the first-launch intro (keep it uncluttered).
    private func showsAccessPoint(_ screen: AppModel.Screen) -> Bool {
        screen != .playing && screen != .onboarding
    }

    /// Screens drawn on the flat `Theme.background` (so a same-colour status-bar scrim is
    /// invisible). The ride and both results screens bleed the ride scene to the very top,
    /// so they are excluded — a scrim would sit over the sky.
    private func flatBackgroundScreen(_ screen: AppModel.Screen) -> Bool {
        switch screen {
        case .playing, .results, .onboarding: return false
        default: return true
        }
    }

    @ViewBuilder private var screen: some View {
        switch model.screen {
        case .menu:    MenuView()
        case .playing:
            if model.conjugationSession != nil { ConjugationGameView() }
            else if model.session?.mode == .practice { PracticeView() }
            else { GameView() }
        case .results:
            if model.resultsAreConjugation { ConjugationResultsView() } else { ResultsView() }
        case .about:   AboutView()
        case .journal: JournalView()
        case .stats:   StatsView()
        case .coach:   CoachView()
        case .settings: SettingsView()
        case .road:    RoadView()
        case .lists:   ListsView()
        case .listDetail: ListDetailView()
        case .onboarding: OnboardingView()
        }
    }
}

extension AnyTransition {
    /// New screen rises ~14pt from below + scales up from 0.97 with fade.
    /// Old screen drops slightly + fades. Gives presence without feeling slow.
    static var screenLift: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.97, anchor: .center)
                .combined(with: .move(edge: .bottom))
                .combined(with: .opacity),
            removal: .scale(scale: 1.02, anchor: .center)
                .combined(with: .opacity)
        )
    }
}

// MARK: - Theme

enum Theme {
    /// The top stop of ``background`` as a plain Color. `background` is a LinearGradient
    /// and can't be sampled, and the status-bar scrim must fade FROM the exact colour the
    /// screen begins at.
    static let backgroundTop = Color(red: 0.06, green: 0.09, blue: 0.18)
    static let background = LinearGradient(
        colors: [backgroundTop,
                 Color(red: 0.10, green: 0.14, blue: 0.26)],
        startPoint: .top, endPoint: .bottom
    )
    static let accent = Color(red: 0.98, green: 0.45, blue: 0.45)      // sunset coral
    static let accent2 = Color(red: 0.42, green: 0.78, blue: 0.98)     // sky
    static let gold = Color(red: 0.98, green: 0.80, blue: 0.35)
    static let done = Color(red: 0.45, green: 0.85, blue: 0.62)        // committed kana
    static let card = Color.white.opacity(0.06)
    static let cardStroke = Color.white.opacity(0.10)
    static let dim = Color.white.opacity(0.45)
}

extension View {
    /// A rounded translucent panel used throughout the UI.
    func panel(_ cornerRadius: CGFloat = 22) -> some View {
        padding(22)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Theme.cardStroke, lineWidth: 1)
            )
    }
}
