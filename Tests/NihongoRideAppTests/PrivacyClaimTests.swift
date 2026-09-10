import Testing
import Foundation

/// **The privacy policy has to describe the app that exists.**
///
/// # What happened
///
/// The Privacy Policy page bound to both store listings said, in September 2026, on the live URL
/// in `docs/ASC_METADATA.md`: *"External servers: None. The app does not connect to the internet."*
/// and *"Accounts & sign-in: None."* The shipping app has had iCloud sync **on by default** since
/// v1.13 (`AppModel.iCloudSyncEnabled = true`, `CKContainer(identifier:).privateCloudDatabase`),
/// submits Time Attack scores to Game Center, and since v1.30 carries an in-app purchase. The
/// marketing page said "No account, no network"; the Support page — which App Review opens
/// alongside the policy — said "There is no network connection at all".
///
/// The page had even written its own trigger and then not fired it: *"If a future version ever
/// adds a feature that changes how data is handled (for example, optional iCloud sync handled
/// entirely by Apple), this page will be updated before that version ships."* iCloud sync shipped
/// eleven days later. `git log -- site/privacy.html` had one commit for fifteen months.
///
/// Found by the v1.32 pre-submission review, which fetched the deployed URL rather than reading
/// the repo copy — the repo copy proves what would be published, not what IS.
///
/// # What this test is, and what it is not
///
/// It is a scan of the three pages in `site/` for sentences that are FALSE about this app. It is
/// not a proof that the pages are complete or well written, and it cannot see the deployed copy —
/// `site/` is the source for a separate public repo, so a page can be right here and stale there.
/// **Checking the live URL before a submission stays a human step**, and it is written into the
/// release checklist rather than implied here.
///
/// # The population it deliberately SKIPS
///
/// `RoadView.boundary`'s purchase disclosure says the app "works fully offline". That is a
/// different and TRUE claim — every feature does work with no connection — and it is the wording
/// the frozen App Store listing carries (`ASC_METADATA.md`, "Works fully offline. No sign-up and
/// no account with the developer"). It also sits on the offer surface, which `PLAN-WINDOW`
/// constraint 1 forbids touching during the measurement window. So it is excluded on purpose, and
/// the exclusion is written down rather than left as an oversight for the next reader to find.
@Suite("The public privacy claims match the app")
struct PrivacyClaimTests {

    static var siteDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("site")
    }

    /// Sentences that are false about this app, in both languages. Each one was live.
    static let falseClaims = [
        "does not connect to the internet",
        "no network connection at all",
        "makes no network connections",
        "no account, no network",
        "never leaves your device",
        "不联网",
        "完全离线运行",
        "永不离开设备",
    ]

    @Test("no page in site/ claims the app has no network, no account, or never leaves the device")
    func thePagesDoNotClaimNoNetwork() throws {
        let files = try FileManager.default.contentsOfDirectory(atPath: Self.siteDirectory.path)
            .filter { $0.hasSuffix(".html") }.sorted()
        // The floor: this scan must actually read the three pages. A directory that moved would
        // otherwise report a clean result, which is how three checkers in this repo's history
        // produced a null answer from a broken instrument.
        #expect(files.count == 3, "expected privacy/support/index in site/, found \(files)")

        var inspected = 0
        for file in files {
            let page = try String(contentsOf: Self.siteDirectory.appendingPathComponent(file),
                                  encoding: .utf8)
            #expect(page.count > 1_000, "\(file) is \(page.count) bytes — the scan is misdirected")
            inspected += 1
            let lowered = page.lowercased()
            for claim in Self.falseClaims {
                #expect(!lowered.contains(claim.lowercased()),
                        "\(file) says \"\(claim)\" — the app syncs to the user's own iCloud by default, submits Game Center scores, and carries an in-app purchase. A privacy policy that is wrong about this is worse than none.")
            }
        }
        #expect(inspected == 3)
    }

    /// The other half, and the one that makes the scan above mean something: the pages must SAY
    /// what does use the network. Removing a false sentence and leaving a silence would satisfy
    /// every assertion above — "0 false claims found" and "nothing said at all" print the same
    /// result and are not the same fact.
    @Test("…and the privacy page names iCloud, Game Center and the App Store")
    func theyDiscloseWhatDoesUseTheNetwork() throws {
        let privacy = try String(contentsOf: Self.siteDirectory.appendingPathComponent("privacy.html"),
                                 encoding: .utf8)
        for required in ["iCloud", "Game Center", "App Store"] {
            #expect(privacy.contains(required),
                    "privacy.html does not mention \(required) — the app uses it, and a policy that omits it is a policy that is still wrong, just more quietly")
        }
        // Both language halves. The zh half has its own copy of every section and drifted before.
        #expect(privacy.components(separatedBy: "iCloud").count - 1 >= 4,
                "iCloud appears too few times to be disclosed in both languages")
        #expect(privacy.contains("私有 iCloud"), "the Chinese half does not disclose iCloud sync")
    }
}
