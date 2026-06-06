import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Renders the app's screens to PNGs via SwiftUI `ImageRenderer` (no window,
/// no screen-recording permission). Triggered by `NIHONGO_SHOT=<dir>`:
///   NIHONGO_SHOT=/tmp/shot swift run NihongoRideApp
enum Screenshotter {
    /// While true, views omit their `KeyCaptureView` background (an
    /// NSViewRepresentable that ImageRenderer can't render).
    @MainActor static var isCapturing = false

    @MainActor static func capture(into directory: String) {
        isCapturing = true
        // App Store mode: 1440×900 logical × @2x scale = 2880×1800 actual PNG,
        // the preferred macOS App Store screenshot resolution.
        let storeMode = ProcessInfo.processInfo.environment["NIHONGO_SHOT_STORE"] != nil
        #if os(iOS)
        // iPad 13" landscape logical points (×2 scale → 2752×2064 store size).
        let size = CGSize(width: 1376, height: 1032)
        #else
        let size = storeMode ? CGSize(width: 1440, height: 900) : CGSize(width: 1000, height: 700)
        #endif

        // Optional UI language for the rendered screenshots (NIHONGO_SHOT_LANG=zh).
        let shotLang = ProcessInfo.processInfo.environment["NIHONGO_SHOT_LANG"] ?? "en"
        let makeModel: () -> AppModel = {
            let m = AppModel.init()
            m.languageCode = shotLang
            return m
        }

        // Menu
        render(RootView().environment(makeModel()), size: size, to: directory + "/menu.png")

        // Mid-game (type a couple keys so the word card shows progress)
        let game = makeModel()
        game.startGame()
        if let romaji = game.session?.currentRomaji {
            for character in romaji.prefix(2) { _ = game.session?.input(character) }
        }
        render(RootView().environment(game), size: size, to: directory + "/game.png")

        // Mid-journey (a later landmark approaching)
        let mid = makeModel()
        mid.startGame()
        for _ in 0 ..< 7 {
            guard let romaji = mid.session?.currentRomaji else { break }
            for character in romaji { _ = mid.session?.input(character) }
        }
        if let romaji = mid.session?.currentRomaji { for character in romaji.prefix(2) { _ = mid.session?.input(character) } }
        render(RootView().environment(mid), size: size, to: directory + "/game-mid.png")

        // Results (play a few words so the numbers are non-zero)
        let results = makeModel()
        results.startGame()
        results.session?.skip()   // one lapse so the review list shows
        for _ in 0 ..< 6 {
            guard let romaji = results.session?.currentRomaji else { break }
            for character in romaji { _ = results.session?.input(character) }
        }
        results.finishGame()
        render(RootView().environment(results), size: size, to: directory + "/results.png")

        // Practice (passage) mode — washi paper, full multi-sentence paragraph
        let practice = makeModel()
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
        let blind = makeModel()
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
        let about = makeModel()
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
        renderer.scale = scale
        var data: Data?
        #if os(macOS)
        if let image = renderer.nsImage,
           let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff) {
            data = rep.representation(using: .png, properties: [:])
        }
        #elseif os(iOS)
        data = renderer.uiImage?.pngData()
        #endif
        guard let png = data else {
            FileHandle.standardError.write(Data("screenshot render failed: \(path)\n".utf8))
            return
        }
        try? png.write(to: URL(fileURLWithPath: path))
        FileHandle.standardError.write(Data("wrote \(path)\n".utf8))
    }

    /// Render scale: 2× (macOS Retina, and iPad @2x → 2752×2064 store size).
    private static var scale: CGFloat { 2 }
}
