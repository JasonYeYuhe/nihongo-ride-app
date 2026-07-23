import SwiftUI
import SceneryKit
import WidgetSharedKit
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
        // iPad 13" landscape logical points (×2 scale → 2752×2064 store size);
        // iPhone 6.9" portrait logical points (×3 scale → 1320×2868 store size).
        let size = UIDevice.current.userInterfaceIdiom == .phone
            ? CGSize(width: 440, height: 956)
            : CGSize(width: 1376, height: 1032)
        #else
        let size = storeMode ? CGSize(width: 1440, height: 900) : CGSize(width: 1000, height: 700)
        #endif

        // Optional UI language for the rendered screenshots (NIHONGO_SHOT_LANG=zh).
        let shotLang = ProcessInfo.processInfo.environment["NIHONGO_SHOT_LANG"] ?? "en"
        // Dev-only: force the read-aloud button on for a visual check (NIHONGO_TTS=1).
        let forceTTS = ProcessInfo.processInfo.environment["NIHONGO_TTS"] == "1"
        let makeModel: () -> AppModel = {
            let m = AppModel.init()
            m.languageCode = shotLang
            if forceTTS { m.ttsEnabled = true }
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

        // Every stretch of road, as a contact sheet (v1.12 §D). The palettes are the one
        // part of the scenery a person has to LOOK at to judge, and there is no other way
        // to see seven of them without riding 25 km. NIHONGO_SHOT_STAGES=1 opts in.
        if ProcessInfo.processInfo.environment["NIHONGO_SHOT_STAGES"] != nil {
            for stage in RideRoute.stages {
                let m = makeModel()
                m.startGame()
                m.session?.skip()
                for _ in 0 ..< 5 {
                    guard let romaji = m.session?.currentRomaji else { break }
                    for ch in romaji { _ = m.session?.input(ch) }
                }
                m.forceRideStage(stage)
                render(RootView().environment(m), size: size,
                       to: directory + "/stage-\(stage.id)-\(stage.romaji).png")
                // The same scene with NO text or HUD, so the contrast check can measure what
                // is actually BEHIND the words. Measuring the composed screen instead just
                // finds the white text and reports 1:1.
                render(ZStack {
                        RideBackgroundView(speed: 1, landmarkPhase: 2.4, stage: stage)
                        Color.black.opacity(stage.palette.textScrim).ignoresSafeArea()
                       }, size: size,
                       to: directory + "/bare-\(stage.id)-\(stage.romaji).png")
                // The results screens' backdrop (heavier scrim, landmark at its closest),
                // again with no text: what the arrival panel and the naked title actually
                // sit on. Measured by check_scene_contrast.py --results.
                render(RideArrivalBackdrop(stage: stage), size: size,
                       to: directory + "/bare-results-\(stage.id)-\(stage.romaji).png")
                // The composed results screen for this stage — title, panel, arrival sky.
                m.finishGame()
                m.forceRideStage(stage)   // finishGame doesn't reresolve, but be explicit
                render(RootView().environment(m), size: size,
                       to: directory + "/results-\(stage.id)-\(stage.romaji).png")
            }
        }

        // The share card (v1.10 §C). Not an App Store screenshot — it is the ONLY
        // headless check that the card renders at all, since ResultsView deliberately
        // skips rendering it while capturing (that would re-enter ImageRenderer from
        // inside its own pass) and the app target has no unit tests. A card that came
        // out blank would otherwise be found by whoever first tapped Share.
        if let summary = results.lastSummary {
            render(ShareCardView(summary: summary, zh: shotLang == "zh"),
                   size: CGSize(width: 540, height: 400), to: directory + "/share-card.png")
        }

        // Widget previews (v1.11). Like the share card, this is the ONLY headless check
        // that the widget's snapshot→view chain renders — the view lives in the widget
        // extension (its @main can't run here), so its render-ready twin ReviewWidgetContent
        // is shared in WidgetSharedKit precisely so it can be drawn here. Backgrounds are
        // supplied by the wrapper (the content carries none, matching the widget's
        // containerBackground). Two data states so an empty/degenerate layout shows up.
        let zh = shotLang == "zh"
        let widgetSample = ReviewWidgetData(hasData: true, stale: false,
                                            vocabDue: 12, conjugationDue: 3, streakDays: 5, zh: zh)
        render(ReviewWidgetContent(data: widgetSample, size: .small).padding(12)
                    .background(WidgetPalette.bg),
               size: CGSize(width: 170, height: 170), to: directory + "/widget-small.png")
        render(ReviewWidgetContent(data: widgetSample, size: .medium).padding(14)
                    .background(WidgetPalette.bg),
               size: CGSize(width: 360, height: 170), to: directory + "/widget-medium.png")
        render(ReviewWidgetContent(data: ReviewWidgetData(hasData: false, stale: false,
                    vocabDue: 0, conjugationDue: 0, streakDays: 0, zh: zh), size: .small).padding(12)
                    .background(WidgetPalette.bg),
               size: CGSize(width: 170, height: 170), to: directory + "/widget-empty.png")
        // Vocab all done but conjugations still due — the small widget must show the
        // conjugation count, NOT claim "all caught up" (v1.13 §B). Checks the fix headlessly.
        render(ReviewWidgetContent(data: ReviewWidgetData(hasData: true, stale: false,
                    vocabDue: 0, conjugationDue: 4, streakDays: 2, zh: zh), size: .small).padding(12)
                    .background(WidgetPalette.bg),
               size: CGSize(width: 170, height: 170), to: directory + "/widget-conj-only.png")

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

        // Conjugation drill (v1.6) — dictionary form + target-form label; type a couple
        // keys so the answer shows progress. Pure-drawn (no native controls), so it
        // renders faithfully unlike the menu.
        let conj = makeModel()
        conj.selectedMode = .conjugation
        conj.startGame()
        if let romaji = conj.conjugationSession?.currentRomaji {
            for character in romaji.prefix(2) { _ = conj.conjugationSession?.input(character) }
        }
        render(RootView().environment(conj), size: size, to: directory + "/conjugation.png")

        // Conjugation results — complete a few prompts, then finish.
        let conjResults = makeModel()
        conjResults.selectedMode = .conjugation
        conjResults.startGame()
        for _ in 0 ..< 5 {
            guard let romaji = conjResults.conjugationSession?.currentRomaji else { break }
            for character in romaji { _ = conjResults.conjugationSession?.input(character) }
        }
        conjResults.finishConjugation()
        render(RootView().environment(conjResults), size: size, to: directory + "/conjugation-results.png")

        // Stats screen (v1.9) — seed demo journal + conjugation data so the charts have content.
        let stats = makeModel()
        stats.seedDemoStatsData()
        stats.screen = .stats
        // Taller than the game viewport: the Stats screen scrolls at runtime, so capture the
        // full content (header + all cards) for a store-worthy shot.
        render(RootView().environment(stats), size: CGSize(width: size.width, height: 1500),
               to: directory + "/stats.png")

        // About / Credits page — render the view directly so the screen-transition
        // animation doesn't catch it mid-flight.
        let about = makeModel()
        let aboutView = ZStack { Theme.background.ignoresSafeArea(); AboutView() }
            .preferredColorScheme(.dark)
            .environment(about)
        render(aboutView, size: CGSize(width: 1000, height: 1100),
               to: directory + "/about.png")

        // Ride Log — seeded with an in-memory demo fortnight (never persisted).
        // Store mode keeps the standard frame (top-aligned; the ledger runs off
        // the bottom edge like a page below the fold). Dev mode renders tall.
        let journal = makeModel()
        journal.seedDemoJournal()
        let journalView = ZStack(alignment: .top) { Theme.background.ignoresSafeArea(); JournalView() }
            .preferredColorScheme(.dark)
            .environment(journal)
        #if os(iOS)
        let journalSize = size            // device sizes are store sizes on iOS
        #else
        let journalSize = storeMode ? size : CGSize(width: size.width, height: max(size.height, 1180))
        #endif
        render(journalView, size: journalSize, alignment: .top,
               to: directory + "/journal.png")

        // First-launch onboarding (page 0). NOTE: ImageRenderer ignores the
        // dynamicTypeSize environment, so large-type layout must be verified on a
        // live device/simulator (C3 §7) — not here.
        let onboarding = makeModel()
        let onboardingView = ZStack { Theme.background.ignoresSafeArea(); OnboardingView() }
            .preferredColorScheme(.dark).environment(onboarding)
        render(onboardingView, size: size, to: directory + "/onboarding.png")

        // Word Lists screen (the default ★ list as migrated locally). Rendered
        // read-only — no list mutations here, so the capture never pollutes the
        // machine's real word-list data. (The ⋯ menu draws as a placeholder in
        // ImageRenderer like all native controls; fine at runtime.)
        let lists = makeModel()
        let listsView = ZStack { Theme.background.ignoresSafeArea(); ListsView() }
            .preferredColorScheme(.dark).environment(lists)
        render(listsView, size: size, to: directory + "/lists.png")
    }

    @MainActor private static func render(_ view: some View, size: CGSize,
                                          alignment: Alignment = .center, to path: String) {
        let renderer = ImageRenderer(content:
            view
                .frame(width: size.width, height: size.height, alignment: alignment)
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

    /// Render scale: 2× (macOS Retina, iPad @2x → 2752×2064) or 3× (iPhone @3x).
    @MainActor private static var scale: CGFloat {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone ? 3 : 2
        #else
        2
        #endif
    }
}
