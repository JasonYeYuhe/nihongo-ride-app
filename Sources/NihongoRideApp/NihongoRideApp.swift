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
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: model.screen)
        .preferredColorScheme(.dark)
        // Keep the due-reminder schedule and iCloud sync fresh as days pass.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.appBecameActive() }
        }
        // Game Center access point: show on non-game screens only (never over the ride).
        .onChange(of: model.screen) { _, screen in
            model.gameCenter.setAccessPointActive(screen != .playing)
        }
        .onChange(of: model.gameCenter.isAuthenticated) { _, _ in
            model.gameCenter.setAccessPointActive(model.screen != .playing)
        }
    }

    @ViewBuilder private var screen: some View {
        switch model.screen {
        case .menu:    MenuView()
        case .playing:
            if model.session?.mode == .practice { PracticeView() } else { GameView() }
        case .results: ResultsView()
        case .about:   AboutView()
        case .journal: JournalView()
        case .settings: SettingsView()
        case .lists:   ListsView()
        case .listDetail: ListDetailView()
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
    static let background = LinearGradient(
        colors: [Color(red: 0.06, green: 0.09, blue: 0.18),
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
