import SwiftUI
import GameCore
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
///
/// **This tool is a gate, and v1.34 §C3 made it stop lying in three ways** (each of them bit
/// v1.33, and each is pinned by `CaptureToolTests`):
///
/// 1. **Per-target isolation.** The capture's files and settings suite used to be ONE fixed
///    temp directory and ONE fixed suite named `NihongoRideCapture`, so two captures started
///    together shared an odometer, a journal and a defaults domain and clobbered each other —
///    v1.33's en and zh renders had to be run one after the other. `AppModel.launchIsolation`
///    now derives both names from a digest of the target directory: distinct targets never
///    meet, and the same command maps to the same names every time. `captureTarget` and
///    `isCapturing` are read from `NIHONGO_SHOT` when first touched, not set by `capture` —
///    the process is in capture mode from its first instruction, so the eager
///    `@State private var model = AppModel()` in `NihongoRideApp`, built before
///    `applicationDidFinishLaunching` ever calls `capture`, is isolated too. (It was not
///    before: that one model read the owner's Application Support and bumped the launch
///    counter in the dev binary's defaults domain on every headless render. The review
///    measured it; `CaptureToolTests.captureStateComesFromTheEnvironment` pins the
///    declarations, `AppModelTests.captureIsolationIsConsumed` pins that a set target reaches
///    every door, and the §C3 record shows a full render leaving the owner's files untouched.)
///    The container and suite are cleared BEFORE EVERY SCREEN's model is built — "start from
///    nothing", per screen — because before it was, every run inherited the rides of every
///    previous one, lifetime distance grew monotonically and dragged the scenery stage with it,
///    so one screen's whole background changed between two builds for no reason in either
///    build; and within one run, inserting a ride screen moved four screens below it. Both the
///    container and the suite are removed again at the end.
///
/// 2. **Honest output.** `render` used `try?` and then printed "wrote <path>" whatever had
///    happened; two agents each printed 24 "wrote" lines into a directory that did not exist
///    and the process exited 0. Now the target directory is created (with intermediates), a
///    failure to create it names the path on stderr and returns non-zero, every render and
///    write failure is reported and counted, "wrote" is printed only after the file exists
///    with size > 0, and one summary line closes the run. The call sites exit non-zero when
///    anything failed.
///
/// 3. **Determinism.** Every deck shuffle and form pick in GameCore goes through
///    `DeckRandomness`; this file seeds it — the ONLY place that does — from each screen's
///    file name, before that screen's model is built. Together with the per-screen clearing
///    in (1) that makes each screen a function of its own name and the code: the deck is
///    seeded and the stores are empty, so adding, removing or reordering a screen upstream
///    changes nothing below it (shown by mutation in the §C3 record, not claimed). Before
///    this, 8–9 of 24 screens varied between two runs of the same binary, and so did
///    `road.png`: its odometer sentence ("24.3 km still to Kyōto") counted the distance the
///    random decks had ridden earlier in the same process. The plan's gate needs `road.png`
///    and `menu.png` identical across releases, and §B1's proof needs `results.png` to differ
///    from the baseline in exactly one region; neither was decidable while the capture itself
///    was noise.
enum Screenshotter {
    /// True for the whole life of a headless-render process and false on every other launch:
    /// read from the environment when first touched, which happens inside the first
    /// `AppModel.init` — before `capture` runs. While true, views omit their `KeyCaptureView`
    /// background (an NSViewRepresentable that ImageRenderer can't render), models start from
    /// default settings and persist none, and the widget, Game Center and sync stay closed.
    /// Settable so a test can put one model into capture mode and restore it.
    @MainActor static var isCapturing = ProcessInfo.processInfo.environment["NIHONGO_SHOT"] != nil

    /// The capture target exactly as the environment spelled it, or nil outside capture.
    /// `AppModel.currentIsolation` derives the throwaway container and defaults suite from a
    /// digest of it, so it is initialised from `NIHONGO_SHOT` rather than assigned by
    /// `capture`: every model this process builds, including the App struct's eager one, then
    /// resolves to the throwaway container. RAW, not standardised — the digest must be the
    /// same on every run of the same command, and `standardizedFileURL` strips `/private`
    /// only once the directory exists, so a first run and its re-run used to get two
    /// containers. On iOS the environment value is the digest source only; the PNGs go to
    /// the Documents container the call site passes. Never cleared: an `AppModel` that
    /// outlives the capture must keep resolving to the throwaway container, not fall back to
    /// the owner's Application Support. Settable so a test can point one model at a target
    /// of its own and restore it.
    @MainActor static var captureTarget: String? = ProcessInfo.processInfo.environment["NIHONGO_SHOT"]

    /// Screens this run wrote (file present, size > 0) and screens it could not.
    @MainActor private(set) static var written = 0
    @MainActor private(set) static var failed = 0

    /// Renders every screen into `directory`, creating it if needed. Returns the number of
    /// screens that failed to render or write — zero means every "wrote" line is true.
    @MainActor @discardableResult
    static func capture(into directory: String) -> Int {
        // Cleared however this function leaves, so nothing built after a capture in the same
        // process draws seeded — a defer, not the last statement, so a future throwing step
        // cannot skip it.
        defer {
            DeckRandomness.seed = nil
        }
        written = 0
        failed = 0
        // A production launch arrives here with `captureTarget` and `isCapturing` already set
        // from the environment; that is what kept the App struct's eager model isolated. A
        // test that calls `capture` directly has no `NIHONGO_SHOT` in its environment, so it
        // is given its argument as the target here (and restores both afterwards). Nothing
        // else may assign the target: `CaptureToolTests.captureStateComesFromTheEnvironment`.
        if captureTarget == nil { captureTarget = directory }
        isCapturing = true
        let target = URL(fileURLWithPath: directory, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        } catch {
            report("cannot create \(directory): \(error.localizedDescription)")
            report("capture aborted: nothing was written")
            return 1
        }
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
        // One model per screen, and each starts from nothing twice over, BEFORE the model
        // exists. The deck: the seed is reset from the screen's own name, so every draw this
        // screen makes — the deck, the practice re-roll, the drill's form picks — is the same
        // in every run. The stores: the capture container and its defaults suite are cleared,
        // so the odometer, journal, review stores, stumble ledger, word lists and settings are
        // empty for this screen rather than the sum of what the screens above rode into them.
        // The screens that read persisted state, and now read it at zero: `road` and
        // `road-iap-review` (both distance sentences and the stretch rows, from lifetime
        // distance), every ride's backdrop (`rideStage` is resolved from lifetime distance
        // when the run starts: `game`, `game-mid`, `results`, `results-sentence`,
        // `conjugation-results`), `about` (the diagnostics counter line names the furthest
        // stretch), `journal` (the review forecast counts what the review store holds) and
        // `stats` (both take their totals as the larger of the demo journal and the odometer),
        // and `menu` (streak and due count). What the clearing moved, measured by rendering
        // before and after it (en and zh): the road's sentences and stretch rows (the full free
        // road; Kawasaki unreached); about.png's counter line, whose furthest-stretch word went
        // kawasaki → nihonbashi; conjugation-results.png's backdrop, Kawasaki's torii → the
        // Nihonbashi tower on the Nihonbashi dawn; and journal.png's review forecast, whose
        // "Tomorrow" row went 7 → 0 — the 7 were the words the upstream rides had put into the
        // review store. The journal's totals did not move: the demo journal is the larger.
        // Before this, removing ONE upstream ride screen moved road.png, road-iap-review.png,
        // about.png and conjugation-results.png, and the render gate would have filed each as a
        // layout regression. The share card is the exception by design: it is drawn from the
        // results model's in-memory summary.
        let makeModel: (String) -> AppModel = { screen in
            DeckRandomness.seed = StableDigest.fnv1a64(screen)
            clearCaptureStores()
            let m = AppModel.init()
            m.languageCode = shotLang
            // Store screenshots keep showing the hints — a fresh AppModel now defaults to
            // .afterStruggle (v1.16 §A), which would silently strip the romaji row from
            // every captured game screen.
            m.assistance = .always
            if forceTTS { m.ttsEnabled = true }
            return m
        }

        // Menu
        render(RootView().environment(makeModel("menu")), size: size, to: directory + "/menu.png")

        // Mid-game (type a couple keys so the word card shows progress)
        let game = makeModel("game")
        game.startGame()
        if let romaji = game.session?.currentRomaji {
            for character in romaji.prefix(2) { _ = game.session?.input(character) }
        }
        render(RootView().environment(game), size: size, to: directory + "/game.png")

        // Mid-journey (a later landmark approaching)
        let mid = makeModel("game-mid")
        mid.startGame()
        for _ in 0 ..< 7 {
            guard let romaji = mid.session?.currentRomaji else { break }
            for character in romaji { _ = mid.session?.input(character) }
        }
        if let romaji = mid.session?.currentRomaji { for character in romaji.prefix(2) { _ = mid.session?.input(character) } }
        render(RootView().environment(mid), size: size, to: directory + "/game-mid.png")

        // Results (play a few words so the numbers are non-zero)
        let results = makeModel("results")
        results.startGame()
        results.session?.skip()   // one lapse so the review list shows
        for _ in 0 ..< 6 {
            guard let romaji = results.session?.currentRomaji else { break }
            for character in romaji { _ = results.session?.input(character) }
        }
        results.finishGame()
        render(RootView().environment(results), size: size, to: directory + "/results.png")

        // Sentence results — the only screen the stumbled-word chips appear on, and the only
        // way to LOOK at v1.24 §A without riding a sentence by hand. The unit tests prove the
        // attribution and prove the count matches the run; neither can show that the chips fit
        // the panel, that a starred chip and a bare one read as different things, or that the
        // ride button does not crowd the buttons below it. v1.23 shipped a fix to this screen
        // with no execution evidence at all, which is the habit this replaces.
        let sentenceResults = makeModel("results-sentence")
        sentenceResults.selectedMode = .sentence
        sentenceResults.startGame()
        // Skip one, so the review list is NOT empty. A results screen rendered with nothing in
        // it does not exercise the layout that matters here: on a sentence run every lapsed
        // "word" is a whole sentence (GameSession.sentenceSession wraps it as a VocabEntry whose
        // surface IS the sentence), and that only shows up when something lapses.
        sentenceResults.session?.skip()
        for _ in 0 ..< 4 {
            // Two refused keys first: the matcher does not advance on a rejection, so both land
            // inside the same word, which is what makes it a stumble rather than two slips
            // (`minimumRefusals` is 2). "q" has no romaji mapping in any IME table.
            _ = sentenceResults.session?.input("q")
            _ = sentenceResults.session?.input("q")
            guard let romaji = sentenceResults.session?.currentRomaji else { break }
            for character in romaji { _ = sentenceResults.session?.input(character) }
        }
        sentenceResults.finishGame()
        render(RootView().environment(sentenceResults), size: size,
               to: directory + "/results-sentence.png")
        // NO accessibility-size render here, and that is a finding rather than an omission.
        // `ImageRenderer` does not drive `@ScaledMetric`, which is what `scaledSystemFont` is
        // built on and therefore what nearly every size in this app is: injecting
        // `dynamicTypeSize` (or the legacy `sizeCategory`) produced AX3 and AX5 renders that
        // were BYTE-IDENTICAL to each other. A file named results-sentence-ax5.png that cannot
        // tell AX5 from AX3 is worse than no file — it is a gate that reports clean without
        // measuring, which is this project's most expensive recurring mistake.
        //
        // Large-type layout stays device-verified (Gate E). ScaledFont.swift has said so since
        // v1.7 Phase A; this comment exists because that warning was nearly ignored.

        // The road screen (v1.30). Rendered unconditionally because it is the ONE surface Apple's
        // reviewer is told to look at — the IAP's review note points at Settings > The Road — and
        // because the offer's DISTANCE COPY — what it tells a rider who has not arrived — is a
        // layout property nothing else can show. It cannot show the price or the buy button:
        // `RouteStore.storeIsReachable` is false while capturing, so the card renders its
        // "Loading price…" branch. That is a limit of this artifact and it is stated rather than
        // implied, because "the render proves the offer looks right" would be false of the half
        // of the offer that takes the money.
        //
        // ONE state — unentitled — and that is a limitation, not a choice. The owned state would
        // need `NIHONGO_FAKE_ENTITLEMENT`, which is read once per process at `RouteStore.init`,
        // so setting it would fake the entitlement for every other screen in the same capture run.
        // The owned layout is covered by `PaidRouteRowTests` instead. (An earlier version of this
        // comment claimed two states and wrote one, which is the defect this file exists to
        // catch, in this file.)
        // Rendered TALL, not at the store size. In capture mode the views drop their ScrollView
        // (ImageRenderer does not lay out inside one), so a screen taller than the frame is
        // centred and clipped at BOTH ends — the first render of this one lost its header and the
        // §C boundary sentence, which is the one line a reviewer most needs to read.
        //
        // Its odometer sentences read a lifetime distance of ZERO: `makeModel` cleared the
        // container before this model was built, so the rides the screens above finished do
        // not reach it. That is what makes this screen a function of its own name — before
        // the per-screen clearing it counted those rides, so the sentence moved by a tenth of
        // a kilometre between two runs of the old tool, and by 0.6 km when one upstream ride
        // screen was removed from the seeded one. What it shows is the offer as a rider who
        // has not set out sees it: the full free road still ahead.
        let road = makeModel("road")
        road.showRoad()
        render(RootView().environment(road),
               size: CGSize(width: size.width, height: max(size.height, 1400)),
               to: directory + "/road.png")
        // And again at 1320×2868 — iPhone 6.9" portrait, at macOS's ×2 scale from 660×1434.
        //
        // This one is the **App Store Connect IAP review screenshot**, which is why it targets a
        // spec rather than looking nice: Apple asks for "a screenshot that meets any of the
        // screenshot specifications your app supports", the upload is documented as irreversible
        // once made ("you can update it but not remove it"), and 1320×2868 is the exact spec that
        // has already passed review on this team. A non-standard size here is a rejection on an
        // asset that cannot be taken back.
        render(RootView().environment(road), size: CGSize(width: 660, height: 1434),
               to: directory + "/road-iap-review.png")

        // Every stretch of road, as a contact sheet (v1.12 §D). The palettes are the one
        // part of the scenery a person has to LOOK at to judge, and there is no other way
        // to see seven of them without riding 25 km. NIHONGO_SHOT_STAGES=1 opts in.
        if ProcessInfo.processInfo.environment["NIHONGO_SHOT_STAGES"] != nil {
            // BOTH roads, entitlement ignored. This is a developer contact sheet, not the app:
            // its whole purpose is that the palettes are the one part of the scenery a person has
            // to LOOK at to judge, and eight of the sixteen are otherwise unreachable without
            // buying the road and riding 138 km. Never confuse this with a shipping surface —
            // `Screenshotter.isCapturing` gates the whole block, and `forceRideStage` refuses
            // outside capture.
            for stage in RideRoute.everyStage {
                let m = makeModel("stage-\(stage.id)-\(stage.romaji)")
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
        // Lock-screen accessories (v1.13 §C). Rendered light-on-dark here to stand in for
        // the system's monochrome tint — the ONLY headless check the accessory layouts fit
        // their tiny frames. Real tint/vibrancy is a device gate.
        let acc = ReviewWidgetData(hasData: true, stale: false,
                                   vocabDue: 12, conjugationDue: 3, streakDays: 5, zh: zh)
        render(ReviewWidgetContent(data: acc, size: .accessoryRectangular)
                    .foregroundStyle(.white).padding(6).background(.black),
               size: CGSize(width: 160, height: 72), to: directory + "/acc-rectangular.png")
        render(ReviewWidgetContent(data: acc, size: .accessoryInline)
                    .foregroundStyle(.white).padding(6).background(.black),
               size: CGSize(width: 200, height: 30), to: directory + "/acc-inline.png")
        render(ReviewWidgetContent(data: acc, size: .accessoryCircular)
                    .foregroundStyle(.white).padding(6).background(.black),
               size: CGSize(width: 84, height: 84), to: directory + "/acc-circular.png")

        // Practice (passage) mode — washi paper, full multi-sentence paragraph
        let practice = makeModel("practice")
        practice.selectedMode = .practice
        practice.practiceSource = .passages
        practice.practicePassageLevel = .hard
        // Re-roll until we land on one of the long multi-sentence paragraphs (kana > 40 chars).
        // Seeded, so the re-roll lands on the same passage every run.
        for _ in 0 ..< 30 {
            practice.startGame()
            if let k = practice.session?.currentKana, k.count > 40 { break }
        }
        if let romaji = practice.session?.currentRomaji {
            for character in romaji.prefix(romaji.count / 3) { _ = practice.session?.input(character) }
        }
        render(RootView().environment(practice), size: size, to: directory + "/practice.png")

        // Practice BLIND mode (no romaji hint)
        let blind = makeModel("practice-blind")
        blind.selectedMode = .practice
        blind.practiceSource = .passages
        blind.practicePassageLevel = .hard
        blind.assistance = .off
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
        let conj = makeModel("conjugation")
        conj.selectedMode = .conjugation
        conj.startGame()
        if let romaji = conj.conjugationSession?.currentRomaji {
            for character in romaji.prefix(2) { _ = conj.conjugationSession?.input(character) }
        }
        render(RootView().environment(conj), size: size, to: directory + "/conjugation.png")

        // Conjugation results — complete a few prompts, then finish.
        let conjResults = makeModel("conjugation-results")
        conjResults.selectedMode = .conjugation
        conjResults.startGame()
        for _ in 0 ..< 5 {
            guard let romaji = conjResults.conjugationSession?.currentRomaji else { break }
            for character in romaji { _ = conjResults.conjugationSession?.input(character) }
        }
        conjResults.finishConjugation()
        render(RootView().environment(conjResults), size: size, to: directory + "/conjugation-results.png")

        // Stats screen (v1.9) — seed demo journal + conjugation data so the charts have content.
        let stats = makeModel("stats")
        stats.seedDemoStatsData()
        stats.screen = .stats
        // Taller than the game viewport: the Stats screen scrolls at runtime, so capture the
        // full content (header + all cards) for a store-worthy shot.
        render(RootView().environment(stats), size: CGSize(width: size.width, height: 1500),
               to: directory + "/stats.png")

        // About / Credits page — render the view directly so the screen-transition
        // animation doesn't catch it mid-flight.
        let about = makeModel("about")
        let aboutView = ZStack { Theme.background.ignoresSafeArea(); AboutView() }
            .preferredColorScheme(.dark)
            .environment(about)
        render(aboutView, size: CGSize(width: 1000, height: 1100),
               to: directory + "/about.png")

        // Ride Log — seeded with an in-memory demo fortnight (never persisted).
        // Store mode keeps the standard frame (top-aligned; the ledger runs off
        // the bottom edge like a page below the fold). Dev mode renders tall.
        let journal = makeModel("journal")
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
        let onboarding = makeModel("onboarding")
        let onboardingView = ZStack { Theme.background.ignoresSafeArea(); OnboardingView() }
            .preferredColorScheme(.dark).environment(onboarding)
        render(onboardingView, size: size, to: directory + "/onboarding.png")

        // Word Lists screen (the default ★ list as migrated locally). Rendered
        // read-only — no list mutations here, so the capture never pollutes the
        // machine's real word-list data. (The ⋯ menu draws as a placeholder in
        // ImageRenderer like all native controls; fine at runtime.)
        let lists = makeModel("lists")
        let listsView = ZStack { Theme.background.ignoresSafeArea(); ListsView() }
            .preferredColorScheme(.dark).environment(lists)
        render(listsView, size: size, to: directory + "/lists.png")

        // Leave nothing behind: the container and the suite (the seed is cleared by the defer
        // at the top). `isCapturing` and `captureTarget` stay set — see their docs.
        clearCaptureStores()
        if failed == 0 {
            report("\(written) screens written to \(directory)")
        } else {
            report("\(failed) of \(written + failed) screens FAILED")
        }
        return failed
    }

    /// Removes this capture's container and defaults suite. Called before every screen's model
    /// is built (so each screen starts from nothing) and at the end (so the run leaves
    /// nothing). Both names are keyed to this process's target, so this cannot touch another
    /// capture running alongside. Failures are reported, not swallowed: a container that could
    /// not be cleared is a screen that did not start clean.
    @MainActor private static func clearCaptureStores() {
        let isolation = AppModel.currentIsolation
        if let base = isolation.supportBase, FileManager.default.fileExists(atPath: base.path) {
            do {
                try FileManager.default.removeItem(at: base)
            } catch {
                report("could not clear capture container \(base.path): \(error.localizedDescription)")
            }
        }
        if let suite = isolation.settingsSuite {
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
    }

    private enum CaptureError: LocalizedError {
        case renderProducedNoImage
        case emptyFile

        var errorDescription: String? {
            switch self {
            case .renderProducedNoImage: return "ImageRenderer produced no image"
            case .emptyFile: return "file written but empty"
            }
        }
    }

    private static func report(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }

    /// Renders one view to `path`. "wrote" is printed only once the file is on disk with a
    /// non-zero size; every other outcome is reported on stderr with the path and counted in
    /// `failed`. No `try?` here — `CaptureToolTests` pins that, because the `try?` this
    /// replaced is how 24 "wrote" lines were printed for a directory that did not exist.
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
        do {
            guard let png = data else { throw CaptureError.renderProducedNoImage }
            try png.write(to: URL(fileURLWithPath: path))
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
            guard size > 0 else { throw CaptureError.emptyFile }
            written += 1
            FileHandle.standardError.write(Data("wrote \(path)\n".utf8))
        } catch {
            failed += 1
            report("FAILED \(path): \(error.localizedDescription)")
        }
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

/// FNV-1a, 64-bit: a small, dependency-free digest for names that must come out the same in
/// every process and every release — the capture container's tag (`AppModel.launchIsolation`)
/// and the per-screen deck seeds (`Screenshotter`). Its published test vectors are pinned by
/// `CaptureToolTests`, so a "tidy-up" that changed the digest — and with it every seeded
/// screen's deck — would be caught before it was mistaken for a layout regression.
enum StableDigest {
    static func fnv1a64(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    /// The low 32 bits of the digest as eight hex characters — short enough for a directory
    /// name and a defaults suite, distinct enough that two targets on one machine never meet.
    static func tag(_ string: String) -> String {
        String(format: "%08x", UInt32(truncatingIfNeeded: fnv1a64(string)))
    }
}
