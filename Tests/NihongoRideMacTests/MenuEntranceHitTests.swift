import XCTest
import AppKit
import SwiftUI
@testable import Nihongo_Ride

/// **The macOS form of the placement gate, which did not exist.**
///
/// `run_ios_placement_tests.sh` drives the real app on a simulator and asserts, among other
/// things, that the menu's route entrance is tappable in its MIDDLE and not only on its text.
/// It has no macOS counterpart — `docs/PLAN-ITERATION.md` records that gap — so for eight
/// releases the Mac half of a two-platform product had no automated statement about the entrance
/// to the paid road at all.
///
/// ## What made this worth writing on 2026-09-06
///
/// macOS 1.30 had been IN_REVIEW for six days and its `releaseType` is `AFTER_APPROVAL`, so the
/// moment Apple approves it, it ships — and `Sources/NihongoRideApp/MenuView.swift` is compiled
/// into BOTH targets (`project.yml:39` and `:178`), while `.contentShape(Rectangle())` — the fix
/// for the dead entrance — landed in 1.31. The question "does the Mac share the defect?" had a
/// high prior (shared SwiftUI code, a SwiftUI-level cause) and **no measurement**. §K's day 0
/// starts when that binary goes live, and §B forbids moving the placement afterwards, so a
/// guess was not good enough.
///
/// ## Two tests, because they are two different claims
///
/// `test00` measures the PLATFORM: on macOS, does `.contentShape(Rectangle())` change where a
/// Button of this shape responds? It runs the real click path — synthesized `NSEvent`s through
/// an `NSWindow` — over a grid, on a faithful reproduction of the strip's structure.
///
/// `test01` measures THIS REPO: does the real entrance in `MenuView.swift` carry it? A
/// reproduction can never answer that — delete the modifier from the shipping view and `test00`
/// stays green — and `routePreview` is `private`, which `@testable` does not reach. Reading the
/// source is the same move `EntitlementSeamTests` and `DebugSeamTests` already make for the two
/// debug seams, and it carries a negative control for the same reason.
///
/// ## Why the click path and not `hitTest`
///
/// Measured first, and it is why this file uses events: `NSView.hitTest` returns
/// `NSHostingView` for **every** point in **both** variants. SwiftUI renders into one view, so
/// the cheap probe cannot see the difference — it would have passed identically whether the fix
/// was present or not. That is this project's defining failure mode and it was two lines from
/// being shipped as the gate.
/// `@MainActor` because every instrument in here is AppKit: `NSWindow`, `NSHostingView` and
/// `sendEvent` are all main-actor-isolated, and SwiftUI's `View` conformance makes the reproduction
/// main-actor too. Without it the tap closure is a non-Sendable `() -> ()` crossing an actor
/// boundary, which Swift 6 rejects outright rather than leaving as a race to find later.
@MainActor
final class MenuEntranceHitTests: XCTestCase {

    // MARK: The reproduction

    /// The shipping entrance's structure: a Button wrapping a VStack of (a strip of tall stops
    /// joined by 2-point `Rectangle` connectors) over (a caption row). Kept structurally faithful
    /// rather than pixel-faithful — what is under test is that empty space inside a stack is not
    /// content, which is a property of the SHAPE, not of the font sizes.
    private struct StripLike: View {
        let contentShaped: Bool
        let onTap: () -> Void

        var body: some View {
            let stops: [(String, String)] = [("🗼", "Tokyo"), ("🗻", "Fuji"),
                                             ("🏯", "Nagoya"), ("⛩️", "Kyoto")]
            let strip = HStack(spacing: 0) {
                ForEach(Array(stops.enumerated()), id: \.offset) { index, stop in
                    VStack(spacing: 6) {
                        Text(stop.0).font(.system(size: 30))
                        Text(stop.1).font(.caption2)
                    }
                    if index < stops.count - 1 {
                        Rectangle().fill(Color.yellow.opacity(0.55))
                            .frame(height: 2).frame(maxWidth: .infinity)
                    }
                }
            }
            let button = Button(action: onTap) {
                let content = VStack(spacing: 8) {
                    strip
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill").font(.caption)
                        Text("Tokaido complete").font(.caption)
                    }
                }
                // The one difference between the two variants under test.
                if contentShaped { content.contentShape(Rectangle()) } else { content }
            }
            .buttonStyle(.plain)
            return button.padding(20).frame(width: Geometry.width, height: Geometry.height)
        }
    }

    private enum Geometry {
        static let width = 520.0
        static let height = 160.0
        /// Coarse enough to stay quick, fine enough to land inside the dead band between the
        /// connector line and the stop labels.
        static let step = 10.0
    }

    /// One synthesized click at one point. Returns whether the Button's action ran.
    private func clickFires(contentShaped: Bool, at point: NSPoint) -> Bool {
        var fired = false
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0,
                                                  width: Geometry.width, height: Geometry.height),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: StripLike(contentShaped: contentShaped,
                                                     onTap: { fired = true }))
        host.frame = NSRect(x: 0, y: 0, width: Geometry.width, height: Geometry.height)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.12))
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0) {
                window.sendEvent(event)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        window.orderOut(nil)
        return fired
    }

    /// The set of grid points at which the button responds.
    private func liveCells(contentShaped: Bool) -> Set<Point> {
        var live = Set<Point>()
        var y = Geometry.height - Geometry.step
        while y >= Geometry.step {
            var x = Geometry.step
            while x <= Geometry.width - Geometry.step {
                if clickFires(contentShaped: contentShaped, at: NSPoint(x: x, y: y)) {
                    live.insert(Point(x: Int(x), y: Int(y)))
                }
                x += 2 * Geometry.step
            }
            y -= Geometry.step
        }
        return live
    }

    private struct Point: Hashable { let x: Int; let y: Int }

    // MARK: test00 — the platform, with the control that makes it mean anything

    /// **On macOS, `.contentShape(Rectangle())` is what makes the entrance's middle respond.**
    ///
    /// The assertions are ordered so a broken harness cannot masquerade as a finding:
    ///
    /// 1. `withoutShape` must be NON-EMPTY. A plain Button is clickable on its own glyphs; if
    ///    nothing at all fires, the events are not reaching the view and every other number here
    ///    is noise. This is the known positive, and it is the assertion an earlier version of
    ///    this probe FAILED — a single guessed caption point missed, reported "dead", and looked
    ///    exactly like the defect being hunted.
    /// 2. `withoutShape` must be a STRICT SUBSET of `withShape`: the modifier may only add area.
    /// 3. `withShape` must be strictly larger — that difference IS the dead middle.
    func test00_contentShapeIsWhatMakesTheMiddleRespondOnMacOS() {
        let withoutShape = liveCells(contentShaped: false)
        let withShape = liveCells(contentShaped: true)

        XCTAssertFalse(withoutShape.isEmpty,
                       "harness error, not a finding: a plain Button must respond on its own "
                       + "glyphs. Nothing fired anywhere, so the events are not reaching the view.")
        XCTAssertTrue(withoutShape.isSubset(of: withShape),
                      "contentShape removed responsive area, which is not a thing it can do — "
                      + "the two scans are not measuring the same layout.")
        XCTAssertGreaterThan(withShape.count, withoutShape.count,
                             "contentShape changed nothing on macOS. Either the platform does not "
                             + "share the iOS defect — in which case this whole file's premise is "
                             + "wrong and PLAN-ITERATION should say so — or the grid is too coarse "
                             + "to land in the dead band.")

        // Measured 2026-09-06 on this machine: 53 of 390 cells live without, 168 with. The dead
        // band sits between the 2-point connector line and the stop labels, which is exactly
        // where a user aiming at "the road" would click.
        let deadMiddle = withShape.subtracting(withoutShape)
        XCTAssertGreaterThan(deadMiddle.count, withoutShape.count / 2,
                             "the dead region should be comparable to or larger than the live one; "
                             + "got \(deadMiddle.count) dead vs \(withoutShape.count) live")
    }

    // MARK: test01 — the shipping view, which the reproduction cannot speak for

    /// **The real entrance in `MenuView.swift` carries the modifier.**
    ///
    /// `test00` would stay green if somebody deleted `.contentShape(Rectangle())` from the
    /// shipping view, because it tests a copy. This reads the source, the way
    /// `EntitlementSeamTests` reads `RouteStore.swift`.
    func test01_theShippingEntranceCarriesContentShape() throws {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // NihongoRideMacTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
        let url = repo.appendingPathComponent("Sources/NihongoRideApp/MenuView.swift")
        let source = try String(contentsOf: url, encoding: .utf8)

        let entrance = try XCTUnwrap(Self.routePreviewBody(of: source),
                                     "could not find routePreview in MenuView.swift — this test "
                                     + "reads a shape it no longer recognises, so it is now "
                                     + "asserting nothing. Fix the extraction, do not delete it.")
        XCTAssertTrue(Self.carriesContentShape(entrance),
                      "the menu route entrance lost .contentShape(Rectangle()). Without it only "
                      + "the emoji, the stop labels, the 2-point connector and the caption "
                      + "respond; the middle of the strip — the obvious thing to click — is dead. "
                      + "Measured on macOS by test00 in this file, and on iOS by "
                      + "PaidRouteRowTests.testTheMenuEntranceIsTappableInItsMiddle...")

        // Negative control: the checker must be capable of reporting absence. Without this, a
        // `carriesContentShape` that returned true unconditionally would pass forever.
        let stripped = entrance.replacingOccurrences(of: ".contentShape(Rectangle())", with: "")
        XCTAssertFalse(Self.carriesContentShape(stripped),
                       "the checker cannot see absence, so its agreement above proves nothing")
    }

    /// The body of `private var routePreview`, from its declaration to the start of the next
    /// declaration at the same indentation. Deliberately narrow: a whole-file search for
    /// `.contentShape` would be satisfied by the modifier appearing anywhere else in the menu.
    static func routePreviewBody(of source: String) -> String? {
        guard let start = source.range(of: "private var routePreview") else { return nil }
        let rest = source[start.lowerBound...]
        // The next member declaration at four-space indentation ends it.
        if let end = rest.range(of: "\n    private var ", range: rest.index(rest.startIndex, offsetBy: 1)..<rest.endIndex)
            ?? rest.range(of: "\n    private func ", range: rest.index(rest.startIndex, offsetBy: 1)..<rest.endIndex) {
            return String(rest[..<end.lowerBound])
        }
        return String(rest)
    }

    static func carriesContentShape(_ body: String) -> Bool {
        body.contains(".contentShape(Rectangle())")
    }
}
