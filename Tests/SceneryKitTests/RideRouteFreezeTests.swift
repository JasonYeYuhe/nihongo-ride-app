import Testing
import Foundation
import CryptoKit
@testable import SceneryKit

/// **The red line, as a test rather than a promise.**
///
/// Stage 1's first hard constraint is that no existing install loses anything, ever, *enforced in
/// code*. This file is that enforcement. It is separate from `RideRouteTests` because those tests
/// are about whether the road is well-made; these are about whether v1.30's road is, for an
/// unentitled rider, indistinguishable from v1.29's.
///
/// ## Why a golden file and not an assertion
///
/// The obvious test — "the Tōkaidō still resolves correctly" — is circular: it checks v1.30's
/// code against v1.30's code, and would stay green through any change made consistently in both
/// places. `Fixtures/tokaido-v1.29-sweep.json` was produced by **compiling v1.29's own
/// `RideRoute.swift` out of git (`48de373`) and running it**, so the thing being compared against
/// is the shipped behaviour, not a restatement of the current behaviour.
///
/// ## What the previous suite would NOT have caught
///
/// Measured before writing this, by appending one paid stage at 40,000 m to the v1.29 array and
/// re-running the old tests: `arrivalHolds` fails only **one of its three assertions**, because it
/// probes at 1,000,000 m — past the new threshold too, where the new last stage is terminal in its
/// turn. The real damage lands at 30,000 m, a rider just past Kyōto, and **no test in the suite
/// asserted anything there at all.** The assertion point had been chosen for the old array's
/// geometry, so the number the test checked and the property the comment claimed were computed
/// over different domains — this project's signature defect, sitting inside the safety net.
///
/// ## What the sweep actually covers, and what actually catches an append
///
/// 1,167 points: −2,000 … 40,000 at 37 m, every free threshold ±1, both infinities, NaN, and
/// 138,000 and 1,000,000 at the far end.
///
/// It does NOT probe the paid thresholds, and that is fine for a reason worth writing down,
/// because the intuitive reason to add them is wrong. Measured by replaying appends at 28,000,
/// 50,000, 120,000, 500,000 and 2,000,000: **all five produce their first mismatch at exactly
/// m = 25,000**, the first probe past the last free threshold. What catches an append is the
/// TERMINAL INVARIANT — once 京都 stops being last, `metresToNextStage` flips nil → a number and
/// `progressWithinStage` flips 1 → a fraction — not coverage of where the new stretch begins.
/// Believing otherwise invites deleting the clause that does the work as redundant and keeping
/// the ones that do not.
@Suite("The Tōkaidō is frozen")
struct RideRouteFreezeTests {

    private static var fixture: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/tokaido-v1.29-sweep.json")
    }

    /// The commit the golden was swept from — the last one before the paid road existed.
    ///
    /// Asserted rather than trusted. The fixture is 147 KB of machine-generated JSON, which is
    /// unreviewable by eye, so the failure mode worth engineering against is somebody regenerating
    /// it from the WORKING TREE when the test goes red after an intentional change: the test then
    /// grades the code under test against itself, and nothing anywhere goes red.
    /// `scripts/gen_route_golden.py` refuses to read the working tree and refuses any ref that
    /// already contains `westStages`; this line is the other half, so a hand-edited or re-pointed
    /// fixture fails here.
    private static let baselineSHA = "48de373f956fa5f9422628872f783531656dde40"

    /// SHA-256 of the golden's 1,167 rows, canonicalised.
    ///
    /// The SHA above is necessary and was NOT sufficient: it pins which commit the fixture claims
    /// to come from, and somebody editing the rows to make a red test go green would simply leave
    /// that field alone. 147 KB of machine-generated JSON is unreviewable by eye, so the edit
    /// would pass review as well as the test.
    ///
    /// This makes tampering cost a visible one-line diff **in code**, next to a comment saying
    /// what it is for. Regenerating legitimately means running `scripts/gen_route_golden.py
    /// --write`, which refuses any ref containing the paid road, and then updating this constant
    /// in the same commit — where a reviewer will see it and ask why.
    private static let goldenRowsSHA256 =
        "08ea0a3c16ba717be4faabee6afacb690713f57aaf9fb1cea1067d13f63089bf"

    private static func golden() throws -> [[String: String]] {
        let data = try Data(contentsOf: fixture)
        let payload = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(payload["generatedFromSHA"] as? String == baselineSHA,
                "the golden was regenerated from a different commit; if deliberate, change the expected SHA above in the same commit and justify the diff")
        let rows = try #require(payload["rows"] as? [[String: String]])

        // Canonicalised the same way `scripts/gen_route_golden.py` does, so the two agree by
        // construction rather than by inspection.
        let canonical = rows
            .map { row in row.keys.sorted().map { "\($0)=\(row[$0]!)" }.joined(separator: "|") }
            .joined(separator: "\n")
        let digest = SHA256.hash(data: Data(canonical.utf8))
            .map { String(format: "%02x", $0) }.joined()
        #expect(digest == goldenRowsSHA256,
                "the golden's ROWS were edited. If that was deliberate, regenerate with scripts/gen_route_golden.py --write and update goldenRowsSHA256 in the same commit.")
        return rows
    }

    /// Re-derives one golden row from a road. Used by the real assertion AND by its negative
    /// control, so the control cannot pass by testing something else.
    private static func answer(_ raw: String, on stages: [RideStage]) -> (String, String, String) {
        let m = raw == "nan" ? Double.nan : Double(raw)!
        let stage = RideRoute.stage(forLifetimeMetres: m, in: stages)
        let p = RideRoute.progressWithinStage(forLifetimeMetres: m, in: stages)
        let n = RideRoute.metresToNextStage(forLifetimeMetres: m, in: stages)
        return (stage.name,
                String(format: "%.9f", p),
                n.map { $0.isNaN ? "nan" : String(format: "%.6f", $0) } ?? "nil")
    }

    @Test("an unentitled rider's road answers exactly what v1.29 answered, at 1,167 points")
    func theTokaidoResolvesExactlyAsItDid() throws {
        let golden = try Self.golden()
        #expect(golden.count > 1_000, "the golden is too small to have covered anything")

        let free = RideRoute.stages(westOpen: false)
        var mismatches: [String] = []
        for row in golden {
            let (name, progress, next) = Self.answer(row["m"]!, on: free)
            if name != row["stage"] || progress != row["progress"] || next != row["next"] {
                mismatches.append("at \(row["m"]!): v1.29 said \(row["stage"]!)/\(row["progress"]!)/\(row["next"]!), "
                                  + "now \(name)/\(progress)/\(next)")
            }
        }
        let detail = mismatches.prefix(8).joined(separator: "\n")
        #expect(mismatches.isEmpty, "the free road moved under existing riders:\n\(detail)")
    }

    @Test("and that sweep is proven able to fail, on the exact mistake it exists to catch")
    func theSweepCanFail() throws {
        // The committed negative control. A green invariant that has never been shown to go red
        // is indistinguishable from one that reads nothing — this project has paid for that five
        // times. So the mistake is constructed here and the sweep is required to reject it:
        // one paid stage appended to what an UNENTITLED rider is handed.
        let golden = try Self.golden()
        let leaked = RideRoute.tokaidoStages + [RideRoute.westStages[0]]

        var mismatches = 0
        var firstDivergence: String?
        for row in golden {
            let (name, progress, next) = Self.answer(row["m"]!, on: leaked)
            if name != row["stage"] || progress != row["progress"] || next != row["next"] {
                mismatches += 1
                if firstDivergence == nil { firstDivergence = row["m"]! }
            }
        }
        #expect(mismatches > 0, "the sweep accepted a paid stage on the free road — it proves nothing")
        // And it must catch it well before the far end: the old suite's 1,000,000 m probe was
        // blind to exactly this because both roads are terminal out there.
        let divergedAt = Double(firstDivergence ?? "") ?? .infinity
        #expect(divergedAt < 30_000,
                "the sweep only notices past 30 km, which is where the old suite already looked")
    }

    @Test("the eight free stretches are exactly the eight that shipped, field by field")
    func theTokaidoIsFrozen() {
        // Per-stage digests rather than one hash for the array: a single digest tells you
        // something broke and not what, and a failure message that cannot name the stage gets
        // "fixed" by pasting in the new value.
        func digest(_ s: RideStage) -> String {
            func rgb(_ c: RGB) -> String { String(format: "%.2f,%.2f,%.2f", c.r, c.g, c.b) }
            let p = s.palette
            return [String(s.id), s.road.rawValue, s.name, s.romaji, String(s.startMetres),
                    String(s.landmark),
                    rgb(p.skyTop), rgb(p.skyMid), rgb(p.skyLow), rgb(p.sun),
                    String(format: "%.2f", p.sunGlow), String(format: "%.2f", p.cloudAlpha),
                    rgb(p.landFar), rgb(p.land), rgb(p.roadFar), rgb(p.road),
                    rgb(p.lane), rgb(p.silhouette)].joined(separator: "|")
        }
        let expected = [
            "0|tokaido|日本橋|Nihonbashi|0.0|3|0.08,0.11,0.26|0.36,0.30,0.50|0.98,0.62,0.46|0.99,0.86,0.55|0.55|0.50|0.16,0.55,0.52|0.08,0.32,0.35|0.45,0.14,0.18|0.82,0.21,0.21|0.98,0.80,0.35|0.24,0.28,0.50",
            "1|tokaido|川崎|Kawasaki|400.0|1|0.10,0.16,0.32|0.30,0.38,0.58|0.86,0.72,0.60|0.98,0.90,0.72|0.42|0.44|0.14,0.44,0.48|0.07,0.26,0.32|0.36,0.16,0.20|0.68,0.24,0.24|0.96,0.82,0.44|0.20,0.26,0.44",
            "2|tokaido|箱根|Hakone|1200.0|0|0.06,0.12,0.28|0.20,0.34,0.56|0.62,0.74,0.84|0.86,0.90,0.96|0.22|0.40|0.12,0.34,0.44|0.06,0.20,0.30|0.21,0.20,0.24|0.38,0.36,0.44|0.80,0.82,0.72|0.16,0.24,0.42",
            "3|tokaido|富士|Fuji|2500.0|0|0.10,0.24,0.48|0.28,0.50,0.74|0.72,0.86,0.94|0.94,0.90,0.78|0.20|0.40|0.13,0.42,0.42|0.06,0.24,0.28|0.22,0.18,0.17|0.40,0.32,0.30|0.92,0.84,0.60|0.22,0.30,0.52",
            "4|tokaido|浜名湖|Hamanako|5000.0|1|0.08,0.20,0.36|0.24,0.46,0.58|0.80,0.80,0.66|0.99,0.92,0.66|0.40|0.46|0.10,0.44,0.44|0.05,0.26,0.30|0.32,0.26,0.19|0.58,0.48,0.34|0.42,0.28,0.16|0.18,0.30,0.46",
            "5|tokaido|名古屋|Nagoya|9000.0|2|0.12,0.14,0.30|0.42,0.34,0.48|0.96,0.72,0.48|1.00,0.88,0.58|0.50|0.42|0.16,0.48,0.44|0.08,0.28,0.30|0.33,0.17,0.11|0.60,0.30,0.20|0.98,0.82,0.38|0.24,0.26,0.44",
            "6|tokaido|鈴鹿|Suzuka|15000.0|2|0.06,0.07,0.20|0.30,0.20,0.40|0.86,0.46,0.40|0.98,0.68,0.44|0.46|0.38|0.12,0.36,0.38|0.05,0.20,0.26|0.19,0.15,0.18|0.34,0.28,0.32|0.88,0.78,0.50|0.14,0.16,0.34",
            "7|tokaido|京都|Kyōto|25000.0|1|0.04,0.05,0.16|0.16,0.14,0.34|0.52,0.30,0.42|0.98,0.84,0.62|0.34|0.30|0.10,0.30,0.34|0.04,0.16,0.22|0.12,0.11,0.20|0.22,0.20,0.36|0.98,0.76,0.36|0.12,0.14,0.30",
        ]
        #expect(RideRoute.tokaidoStages.count == 8, "a stretch was added to or removed from the free road")
        for (stage, want) in zip(RideRoute.tokaidoStages, expected) {
            #expect(digest(stage) == want, "\(stage.name) changed")
        }
    }

    @Test("opening the west road only ever APPENDS — the free road is a prefix of the full one")
    func theFullRoadIsAdditive() {
        let free = RideRoute.stages(westOpen: false)
        let full = RideRoute.stages(westOpen: true)
        #expect(full.count > free.count)
        #expect(Array(full.prefix(free.count)) == free,
                "buying the road west rewrote a stretch the rider already had")
        #expect(free == RideRoute.tokaidoStages)
    }

    @Test("ids are indices on both roads, which is what makes a stage addressable at all")
    func idsAreIndices() {
        for (i, stage) in RideRoute.stages(westOpen: true).enumerated() {
            #expect(stage.id == i, "\(stage.name) has id \(stage.id) at index \(i)")
        }
        #expect(Set(RideRoute.stages(westOpen: true).map(\.id)).count == 16, "two stretches share an id")
    }

    @Test("the free road is entirely Tōkaidō and the paid road is entirely not")
    func roadsAreLabelledHonestly() {
        #expect(RideRoute.tokaidoStages.allSatisfy { $0.road == .tokaido })
        #expect(RideRoute.westStages.allSatisfy { $0.road == .west })
        #expect(RideRoute.home.road == .tokaido, "the default stretch must never be one somebody paid for")
    }

    @Test("arriving at Kyōto is defined by the road itself, not by a number written twice")
    func arrivalTracksTheRoad() {
        let kyoto = RideRoute.tokaidoStages.last!.startMetres
        #expect(!RideRoute.hasArrivedAtKyoto(lifetimeMetres: kyoto - 1))
        #expect(RideRoute.hasArrivedAtKyoto(lifetimeMetres: kyoto))
        #expect(RideRoute.hasArrivedAtKyoto(lifetimeMetres: 1_000_000))
        #expect(!RideRoute.hasArrivedAtKyoto(lifetimeMetres: .nan), "a corrupt odometer must not claim arrival")
        #expect(!RideRoute.hasArrivedAtKyoto(lifetimeMetres: -.infinity))
        #expect(RideRoute.hasArrivedAtKyoto(lifetimeMetres: .infinity))
    }
}

/// The selector's call sites, read out of the shipped sources.
///
/// `stages(westOpen:)` is the one function in the package that reads an entitlement, which makes
/// the *argument handed to it* the whole security surface. A `Bool` cannot stop anyone writing
/// `true`, so what stops them is this: no file under `Sources/` may hand it a constant, and the
/// one place that legitimately wants every stretch — the developer contact sheet — asks for
/// `everyStage` by name instead.
@Suite("Nothing in the app hands the selector a constant")
struct RouteSelectorTests {

    @Test("entitlement is never a literal in shipping code")
    func entitlementIsNeverALiteral() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")

        let files = FileManager.default
            .enumerator(at: sources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        // The scan must be shown to have read something. A directory walk that silently returned
        // nothing would report clean in exactly the same words as a passing one — the failure
        // mode this project has paid for five times.
        #expect(files.count > 40, "the scan found \(files.count) sources; it cannot report clean")

        var offenders: [String] = []
        var callSites = 0
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for match in source.matches(of: /stages\(westOpen:\s*([A-Za-z0-9_.]+)\s*\)/) {
                callSites += 1
                let argument = String(match.output.1)
                if argument == "true" || argument == "false" {
                    offenders.append("\(file.lastPathComponent): stages(westOpen: \(argument))")
                }
            }
        }
        let detail = offenders.joined(separator: ", ")
        #expect(offenders.isEmpty,
                "a shipping source decides the entitlement by writing it down: \(detail)")

        // …and the scanner must be able to see one when it is there, or the emptiness above is
        // worth nothing. **Run through the SAME regex the real scan uses** — the first version of
        // this control used `(true|false)` while the scan used `([A-Za-z0-9_.]+)` plus a string
        // compare, so it certified a pattern that was not the one doing the work.
        let planted = "let x = RideRoute.stages(westOpen: true)"
        let plantedHits = planted.matches(of: /stages\(westOpen:\s*([A-Za-z0-9_.]+)\s*\)/)
            .filter { $0.output.1 == "true" || $0.output.1 == "false" }
        #expect(plantedHits.count == 1, "the regex cannot detect the thing it exists to detect")
        #expect(callSites >= 1, "no call site was inspected at all")

        // `everyStage` is the OTHER way to get the paid road without an entitlement, and policing
        // only the literal left it wide open. It exists for the developer contact sheet; anywhere
        // else in `Sources/` it is an unguarded bypass of the one seam.
        var bypasses: [String] = []
        for file in files where file.lastPathComponent != "Screenshot.swift" {
            let source = try String(contentsOf: file, encoding: .utf8)
            let code = source.split(separator: "\n", omittingEmptySubsequences: false)
                .map { line -> Substring in
                    guard let c = line.range(of: "//") else { return line }
                    return line[line.startIndex ..< c.lowerBound]
                }
                .joined(separator: "\n")
            // Its own declaration in RideRoute.swift is not a use. Everything else is.
            let uses = code.split(separator: "\n").filter {
                $0.contains("everyStage") && !$0.contains("static let everyStage")
            }
            if !uses.isEmpty { bypasses.append(file.lastPathComponent) }
        }
        let bypassList = bypasses.joined(separator: ", ")
        #expect(bypasses.isEmpty,
                "everyStage hands out the paid road with no entitlement, and is used outside the contact sheet: \(bypassList)")
    }
}

/// **What the buyer was promised, pinned so that re-widening it cannot be silent.**
///
/// v1.30's first draft sold "scenery and routes — all of them, now and in future". That was cut
/// back to the finished thing — the complete road west, Kyōto to Nagasaki, and that route's
/// scenery — while the SKU still had **zero customers**, which is the only window in which a
/// promise can be narrowed at all. Widening one afterwards is always possible; narrowing one never
/// is.
///
/// So the risk this guards is asymmetric and one-directional: nobody will accidentally narrow the
/// promise, and somebody could very easily widen it back by editing a sentence that reads like
/// marketing copy. This is a scan and not a golden, because the sentence should stay editable —
/// what must not happen silently is the return of an unbounded future-catalogue claim.
@Suite("The purchase promises the finished thing, not a future catalogue")
struct PurchasePromiseTests {

    /// Each of these was in the draft that was cut, in one language or the other — or, for the two
    /// "every route" phrases, in `xcode/NihongoRide.storekit`'s product description, which still
    /// read "A second journey west, and every route after." long after all three live store
    /// localizations had dropped the promise, because no scan read that file.
    ///
    /// One list for every file scanned, so a phrase added for one source cannot be missing from
    /// another.
    static let futureCatalogue = ["now and in future", "now and in the future", "added later",
                                  "every route after", "and every route",
                                  "以后的全部", "现在的和以后", "以后新增", "日后所有", "今後の道"]

    static func forwardPromises(in copy: String) -> [String] {
        futureCatalogue.filter { copy.contains($0) }
    }

    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    @Test("no shipping copy sells routes or scenery that do not exist yet")
    func theForwardPromiseIsGone() throws {
        let road = Self.root.appendingPathComponent("Sources/NihongoRideApp/RoadView.swift")
        let source = try String(contentsOf: road, encoding: .utf8)

        // Strings only. The doc comments above `boundary` and `owned` deliberately quote the old
        // wording in order to explain why it came out, and a scanner that could not tell a comment
        // from the copy would have to be lied to — which is how a guard becomes decoration.
        let copy = source.split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        #expect(copy.contains("road west"), "the scan did not find the purchase copy at all")

        for phrase in Self.futureCatalogue {
            #expect(!copy.contains(phrase),
                    """
                    purchase copy contains "\(phrase)", which promises routes or scenery that are \
                    not built. The one-time price may only buy finished goods, and this SKU has \
                    customers now — so the promise can be widened deliberately, but it must not \
                    come back by accident. If this was intended, delete the phrase from this test \
                    in the same commit and say why.
                    """)
        }

        // Negative control: the scan must catch one when it is really there.
        #expect(!Self.forwardPromises(in: "and every route added later").isEmpty,
                "the promise scan cannot detect its own forbidden phrases")
    }

    /// The local StoreKit configuration does not ship, but it is what a Debug run of the Mac app and
    /// `StoreGateTests` present as the product, and it is the file somebody copies from the next
    /// time the listing is edited. It was the last place the widened promise survived.
    @Test("the local StoreKit configuration does not sell a future catalogue either")
    func theStoreKitConfigurationPromisesTheFinishedThing() throws {
        let url = Self.root.appendingPathComponent("xcode/NihongoRide.storekit")
        let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
                                "xcode/NihongoRide.storekit is not a JSON object")
        let products = ((json["products"] as? [[String: Any]]) ?? [])
            + ((json["nonRenewingSubscriptions"] as? [[String: Any]]) ?? [])
        // Floor: the one product this app sells must be there, or everything below reads nothing.
        #expect(products.contains { ($0["productID"] as? String) == "com.jasonye.nihongoride.scenery.lifetime" },
                "the scan did not find the road-west product in the StoreKit configuration")

        var localizationCount = 0
        var textsRead = 0
        for product in products {
            for localization in (product["localizations"] as? [[String: Any]]) ?? [] {
                localizationCount += 1
                let locale = localization["locale"] as? String ?? "?"
                for key in ["description", "displayName"] {
                    guard let text = localization[key] as? String else {
                        Issue.record("the \(locale) localization has no \(key) — the scan would pass it unread")
                        continue
                    }
                    textsRead += 1
                    for phrase in Self.forwardPromises(in: text) {
                        Issue.record("""
                            the StoreKit configuration's \(locale) \(key) "\(text)" contains \
                            "\(phrase)": a promise of routes that are not built, and one the live \
                            store localizations no longer make.
                            """)
                    }
                }
            }
        }
        #expect(localizationCount >= 1, "the product has no localizations — the scan read nothing")
        #expect(textsRead == localizationCount * 2, "read \(textsRead) texts from \(localizationCount) localization(s)")

        // Negative control, on the exact sentence this file used to carry.
        #expect(Self.forwardPromises(in: "A second journey west, and every route after.")
                    == ["every route after", "and every route"],
                "the scan no longer catches the description it was extended to catch")
    }

    @Test("restore does not promise what StoreKit will not do")
    func restoreDoesNotPromiseACrossAccountRecovery() throws {
        // A non-consumable belongs to the Apple Account that bought it; Restore on a different
        // account recovers nothing. The shipped draft said "or a different Apple Account — bring
        // it back here. You will not be charged again", which is a refund and a one-star review
        // waiting to be written.
        let road = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/NihongoRideApp/RoadView.swift")
        let source = try String(contentsOf: road, encoding: .utf8)
        let copy = source.split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")

        #expect(copy.contains("Restore Purchases"), "the scan did not find the restore card")
        for phrase in ["different Apple Account", "换了 Apple 账号", "另一个 Apple 账号"] {
            #expect(!copy.contains(phrase),
                    "restore copy claims a different Apple Account can recover this purchase; it cannot")
        }
        // And it must still say which account IS required, or the correction is only half made.
        #expect(copy.contains("Apple Account that bought it") && copy.contains("当初购买的那个 Apple 账号"),
                "restore no longer makes the false claim, but no longer names the right account either")
    }
}
