import SwiftUI
import AppKit

/// Renders the app's screens to PNGs via SwiftUI `ImageRenderer` (no window,
/// no screen-recording permission). Triggered by `NIHONGO_SHOT=<dir>`:
///   NIHONGO_SHOT=/tmp/shot swift run NihongoDashApp
enum Screenshotter {
    /// While true, views omit their `KeyCaptureView` background (an
    /// NSViewRepresentable that ImageRenderer can't render).
    @MainActor static var isCapturing = false

    @MainActor static func capture(into directory: String) {
        isCapturing = true
        // App Store mode: 1440×900 logical × @2x scale = 2880×1800 actual PNG,
        // the preferred macOS App Store screenshot resolution.
        let storeMode = ProcessInfo.processInfo.environment["NIHONGO_SHOT_STORE"] != nil
        let size = storeMode ? CGSize(width: 1440, height: 900) : CGSize(width: 1000, height: 700)

        // Menu
        render(RootView().environment(AppModel()), size: size, to: directory + "/menu.png")

        // Mid-game (type a couple keys so the word card shows progress)
        let game = AppModel()
        game.startGame()
        if let romaji = game.session?.currentRomaji {
            for character in romaji.prefix(2) { _ = game.session?.input(character) }
        }
        render(RootView().environment(game), size: size, to: directory + "/game.png")

        // Mid-journey (a later landmark approaching)
        let mid = AppModel()
        mid.startGame()
        for _ in 0 ..< 7 {
            guard let romaji = mid.session?.currentRomaji else { break }
            for character in romaji { _ = mid.session?.input(character) }
        }
        if let romaji = mid.session?.currentRomaji { for character in romaji.prefix(2) { _ = mid.session?.input(character) } }
        render(RootView().environment(mid), size: size, to: directory + "/game-mid.png")

        // Results (play a few words so the numbers are non-zero)
        let results = AppModel()
        results.startGame()
        results.session?.skip()   // one lapse so the review list shows
        for _ in 0 ..< 6 {
            guard let romaji = results.session?.currentRomaji else { break }
            for character in romaji { _ = results.session?.input(character) }
        }
        results.finishGame()
        render(RootView().environment(results), size: size, to: directory + "/results.png")

        // Practice (passage) mode — washi paper, full multi-sentence paragraph
        let practice = AppModel()
        practice.selectedMode = .practice
        practice.practicePassages = true
        practice.practicePassageLevel = .hard
        // Re-roll until we land on one of the long multi-sentence paragraphs (kana > 40 chars)
        for _ in 0 ..< 30 {
            practice.startGame()
            if let k = practice.session?.currentKana, k.count > 40 { break }
        }
        if let romaji = practice.session?.currentRomaji {
            for character in romaji.prefix(romaji.count / 3) { _ = practice.session?.input(character) }
        }
        render(RootView().environment(practice), size: size, to: directory + "/practice.png")

        // Practice BLIND mode (no romaji hint)
        let blind = AppModel()
        blind.selectedMode = .practice
        blind.practicePassages = true
        blind.practicePassageLevel = .hard
        blind.showRomajiHint = false
        for _ in 0 ..< 30 {
            blind.startGame()
            if let k = blind.session?.currentKana, k.count > 40 { break }
        }
        if let romaji = blind.session?.currentRomaji {
            for character in romaji.prefix(romaji.count / 2) { _ = blind.session?.input(character) }
        }
        render(RootView().environment(blind), size: size, to: directory + "/practice-blind.png")

        // About / Credits page — render the view directly so the screen-transition
        // animation doesn't catch it mid-flight.
        let about = AppModel()
        let aboutView = ZStack { Theme.background.ignoresSafeArea(); AboutView() }
            .preferredColorScheme(.dark)
            .environment(about)
        render(aboutView, size: CGSize(width: 1000, height: 1100),
               to: directory + "/about.png")
    }

    @MainActor private static func render(_ view: some View, size: CGSize, to path: String) {
        let renderer = ImageRenderer(content:
            view
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, .dark)
        )
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else {
            FileHandle.standardError.write(Data("screenshot render failed: \(path)\n".utf8))
            return
        }
        try? png.write(to: URL(fileURLWithPath: path))
        FileHandle.standardError.write(Data("wrote \(path)\n".utf8))
    }
}
