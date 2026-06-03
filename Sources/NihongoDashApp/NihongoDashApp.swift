import SwiftUI
import AppKit

@main
struct NihongoDashApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Nihongo Dash") {
            RootView()
                .environment(model)
                .frame(minWidth: 880, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
    }
}

/// Activates the app when launched via `swift run` (no bundle to do it for us).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // SwiftPM doesn't compile an asset catalog, so set the Dock icon at runtime.
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            switch model.screen {
            case .menu:    MenuView()
            case .playing: GameView()
            case .results: ResultsView()
            }
        }
        .animation(.smooth(duration: 0.35), value: model.screen)
        .preferredColorScheme(.dark)
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
