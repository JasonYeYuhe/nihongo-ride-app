import Testing
import Foundation
import SwiftUI
@testable import NihongoRideApp

/// `MenuFlow` proposes the row's width to an item wider than the row, and nothing changes for an
/// item that fits (v1.33 §B R).
///
/// The defect: at AX5 on a 393pt phone a stumbled-word chip is 65pt + the word, so a word of 8+
/// characters was wider than the screen, and `MenuFlow` — which gave every item its natural width
/// and centred the row — clipped it on both edges (ax-findings #27, CoreText-measured 2026-09-17).
///
/// The constraint: the same layout draws the menu's chips at every size, and the menu is the one
/// screen v1.33 keeps pixel-identical. So the row arithmetic is pure and tested against a frozen
/// copy of the pre-v1.33 loop, and the one new decision (`narrowedWidth`) is tested at its
/// boundary. What a pure test cannot reach is the glue that measures a `LayoutSubview`, which has
/// no public initialiser; the hosted test at the end covers that on macOS, and the headless menu
/// render (compared against the 3d6c59f baseline) is the proof for the menu itself.
@Suite("v1.33 R: MenuFlow narrows only an item wider than its row")
struct V133RMenuFlowTests {

    // MARK: - The new decision

    @Test("an item is narrowed only when its natural width exceeds the row")
    func narrowedOnlyWhenWider() {
        #expect(MenuFlow.narrowedWidth(natural: 80, maxWidth: 300) == nil)
        #expect(MenuFlow.narrowedWidth(natural: 300, maxWidth: 300) == nil,
                "an item exactly as wide as the row fits, and the pre-v1.33 break (`>`) agrees")
        #expect(MenuFlow.narrowedWidth(natural: 374, maxWidth: 300) == 300)
        // `sizeThatFits` with a nil width proposal arrives as `.infinity`: nothing is ever narrowed
        // while the flow is asked for its ideal size (ViewThatFits' question).
        #expect(MenuFlow.narrowedWidth(natural: 10_000, maxWidth: .infinity) == nil)
    }

    // MARK: - The row arithmetic, unchanged

    @Test("rows break greedily, as written out by hand")
    func rowsByHand() {
        let sizes = [CGSize(width: 50, height: 20), CGSize(width: 60, height: 30),
                     CGSize(width: 100, height: 20), CGSize(width: 20, height: 10)]
        let rows = MenuFlow.rows(sizes: sizes, maxWidth: 120, spacing: 8)
        // 50 + 8 + 60 = 118 fits; + 8 + 100 does not. 100 + 8 + 20 = 128 does not.
        #expect(rows.map(\.indices) == [[0, 1], [2], [3]])
        #expect(rows.map(\.width) == [118, 100, 20])
        #expect(rows.map(\.height) == [30, 20, 10])
        #expect(rows[0].sizes == [sizes[0], sizes[1]], "a row must carry the sizes it was broken with")

        // An item wider than the row still gets a row of its own (the case narrowing now shrinks).
        let wide = MenuFlow.rows(sizes: [CGSize(width: 10, height: 5), CGSize(width: 400, height: 5)],
                                 maxWidth: 120, spacing: 8)
        #expect(wide.map(\.indices) == [[0], [1]])
    }

    /// The pre-v1.33 loop, frozen here as the oracle. It measured inside the loop; the sizes it read
    /// are handed in instead, which for an item that fits is the same `sizeThatFits(.unspecified)`.
    static func preV133Rows(sizes: [CGSize], maxWidth: CGFloat, spacing: CGFloat)
        -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        var row: (indices: [Int], width: CGFloat, height: CGFloat) = ([], 0, 0)
        for (i, size) in sizes.enumerated() {
            let advance = (row.indices.isEmpty ? 0 : spacing) + size.width
            if !row.indices.isEmpty, row.width + advance > maxWidth {
                rows.append(row)
                row = ([], 0, 0)
            }
            row.indices.append(i)
            row.width += (row.indices.count == 1 ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }

    /// For every arrangement in which each item fits its row — every menu chip at every size — no
    /// item is narrowed, so each keeps its natural size, and the rows (hence every placement: x from
    /// row width, y from row height) are the pre-v1.33 rows exactly. Fractional widths included,
    /// because real text measures fractionally.
    @Test("when every item fits, nothing is narrowed and the rows are the pre-v1.33 rows")
    func fittingItemsAreUnchanged() {
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next(_ bound: Double) -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(Double(state >> 11) / Double(1 << 53) * bound)
        }
        var compared = 0
        for _ in 0..<2_000 {
            let maxWidth = 60 + next(600)
            let spacing: CGFloat = [8, 10, 12][Int(next(3))]
            let count = 1 + Int(next(9))
            let sizes = (0..<count).map { _ in CGSize(width: next(Double(maxWidth)), height: 10 + next(60)) }
            #expect(sizes.allSatisfy { MenuFlow.narrowedWidth(natural: $0.width, maxWidth: maxWidth) == nil })
            let new = MenuFlow.rows(sizes: sizes, maxWidth: maxWidth, spacing: spacing)
            let old = Self.preV133Rows(sizes: sizes, maxWidth: maxWidth, spacing: spacing)
            #expect(new.map(\.indices) == old.map(\.indices))
            #expect(new.map(\.width) == old.map(\.width))
            #expect(new.map(\.height) == old.map(\.height))
            compared += 1
        }
        #expect(compared == 2_000)
    }

    // MARK: - Hosted: the glue that measures a real subview (macOS)

    #if canImport(AppKit)
    /// A long unbreakable-by-space Japanese line inside a 160pt proposal. With the change it is
    /// proposed 160pt and wraps, so the flow reports no more than 160pt and more than one line of
    /// height. The control is the same text under `.fixedSize()` — how every menu chip is built —
    /// which ignores any proposal and so keeps its natural width: the menu is untouched by
    /// construction, not by luck.
    @MainActor
    @Test("a wrapping item wider than the row wraps inside it; a fixed-size item does not move")
    func hostedWideItem() {
        let word = String(repeating: "かもしれません", count: 3)
        func measure<V: View>(_ item: V) -> CGSize {
            let host = NSHostingController(rootView: MenuFlow(spacing: 8, rowSpacing: 8) { item })
            return host.sizeThatFits(in: CGSize(width: 160, height: 10_000))
        }
        let oneLine = NSHostingController(rootView: Text(word).fixedSize())
            .sizeThatFits(in: CGSize(width: 10_000, height: 10_000))
        #expect(oneLine.width > 160, "the arrangement is not wider than the row — it measures nothing")

        let wrapping = measure(Text(word).fixedSize(horizontal: false, vertical: true))
        #expect(wrapping.width <= 160, "the wide item was not narrowed to the row: \(wrapping)")
        #expect(wrapping.height > oneLine.height * 1.5, "the narrowed item did not wrap: \(wrapping)")

        let fixed = measure(Text(word).fixedSize())
        #expect(fixed.width == oneLine.width, "a fixed-size item changed width: \(fixed) vs \(oneLine)")
    }

    /// `hostedWideItem` asks only for the flow's SIZE, which `sizeThatFits` answers — and
    /// `placeSubviews` measures again on its own. The pre-submission review put back the pre-v1.33
    /// placement (each item re-measured with `sizeThatFits(.unspecified)` and placed at that) and
    /// the whole target stayed green: the flow reported 160pt while it drew the word one line wide,
    /// centred, past both edges — the defect itself. So this reads where the item was PLACED.
    ///
    /// `PlacementProbe` wraps the item and the flow in a pass-through layout that records the
    /// rectangle its parent placed it in: its size is whatever it was proposed there, so a flow
    /// that placed the wide word at its natural width is caught at the width it drew.
    @MainActor
    @Test("a wide wrapping item is PLACED inside the row, at the size the row was broken with")
    func hostedWideItemIsPlacedInsideTheRow() throws {
        let word = String(repeating: "かもしれません", count: 3)
        let flow = PlacementRecord(), item = PlacementRecord(), fixedItem = PlacementRecord()
        func place<V: View>(_ record: PlacementRecord, _ content: V) {
            let host = NSHostingView(rootView: PlacementProbe(record: flow) {
                MenuFlow(spacing: 8, rowSpacing: 8) { PlacementProbe(record: record) { content } }
            })
            host.frame = CGRect(x: 0, y: 0, width: 160, height: 2_000)
            host.layoutSubtreeIfNeeded()
        }
        let oneLine = NSHostingController(rootView: Text(word).fixedSize())
            .sizeThatFits(in: CGSize(width: 10_000, height: 10_000))
        #expect(oneLine.width > 160, "the arrangement is not wider than the row — it measures nothing")

        place(item, Text(word).fixedSize(horizontal: false, vertical: true))
        let placed = try #require(item.last, "the hosted flow never placed its item — the instrument is not laying out")
        let row = try #require(flow.last)
        #expect(row.width <= 160 + 0.5, "the flow itself was placed wider than the host: \(row)")
        #expect(placed.width <= row.width + 0.5, "the item was placed \(placed.width)pt wide in a \(row.width)pt flow")
        #expect(placed.minX >= row.minX - 0.5 && placed.maxX <= row.maxX + 0.5,
                "the item was placed past the flow's edges: item \(placed), flow \(row)")
        #expect(placed.height > oneLine.height * 1.5, "the placed item did not wrap: \(placed)")

        // Control, through the same instrument: `.fixedSize()` ignores the narrowed proposal, so it
        // is placed at its one-line width and overflows. If this were placed inside the row too, the
        // probe would be reporting the flow's frame rather than the item's.
        place(fixedItem, Text(word).fixedSize())
        let overflowing = try #require(fixedItem.last)
        #expect(abs(overflowing.width - oneLine.width) < 0.5 && overflowing.width > row.width,
                "the control was not placed at its natural width — the probe cannot see an overflow: \(overflowing)")
    }
    #endif

    /// The stumbled-word chip is the item `MenuFlow` narrows for. `.fixedSize()` there — what it was
    /// before v1.33, and what every menu chip still is — ignores the narrowed proposal, and the word
    /// is clipped on both edges again with every flow test above still green, because they build
    /// their own items.
    @Test("the stumbled-word chip takes the row's width and keeps its height")
    func stumbleChipFollowsTheProposal() throws {
        let files = try CallSiteScanner.shippedSources.get()
        let results = try #require(files.first { $0.path == "Sources/NihongoRideApp/ResultsView.swift" })
        let chip = try #require(results.functions(named: "stumbleChip").first?.body, "stumbleChip(_:) moved")
        let sizing = results.calls(named: "fixedSize").filter { chip.contains($0.nameOffset) }
        #expect(sizing.map { results.text($0.arguments ?? 0..<0).filter { !$0.isWhitespace } }
                == ["horizontal:false,vertical:true"],
                "stumbleChip's sizing is \(sizing.map(results.excerpt)) — expected exactly one .fixedSize(horizontal: false, vertical: true)")
    }
}

#if canImport(AppKit)
/// Where a `PlacementProbe` was placed, in the hosting view's layout coordinates. Appended on every
/// layout pass, so `last` is the settled one.
@MainActor
final class PlacementRecord {
    private(set) var frames: [CGRect] = []
    var last: CGRect? { frames.last }
    func append(_ frame: CGRect) { frames.append(frame) }
}

/// A single-child layout that changes nothing — it proposes what it is proposed and places its
/// child where it was placed — and records its own placed bounds.
struct PlacementProbe: Layout {
    let record: PlacementRecord

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        subviews.first?.sizeThatFits(proposal) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        MainActor.assumeIsolated { record.append(bounds) }
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: proposal)
    }
}
#endif
