import Foundation

/// An sRGB colour as plain components, so palettes can be reasoned about and TESTED.
///
/// Deliberately not `SwiftUI.Color`: a Color cannot be reliably taken apart again, and the
/// whole legibility guarantee here rests on computing luminance from the actual numbers.
/// The app converts these to Color at the drawing edge.
public struct RGB: Sendable, Equatable {
    public var r: Double, g: Double, b: Double

    public init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r; self.g = g; self.b = b
    }

    /// WCAG relative luminance (sRGB linearised, then the standard weights).
    public var luminance: Double {
        func lin(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    public func lerp(to other: RGB, _ t: Double) -> RGB {
        let k = min(max(t, 0), 1)
        return RGB(r + (other.r - r) * k, g + (other.g - g) * k, b + (other.b - b) * k)
    }
}

/// The colours of one stretch of road.
///
/// Split into SKY and GROUND on purpose, and that split is the legibility guarantee rather
/// than a stylistic one. No text is ever drawn above the horizon, so the sky may swing
/// through a wide gamut — that is where a stage gets to feel different. The word card sits
/// over the ground, so `land`, `landFar`, `road` and `roadFar` are held inside a dark band
/// that keeps white text at 7:1 or better THROUGH the card's own backing. A palette that
/// breaks that is a test failure, not a review comment.
public struct RidePalette: Sendable, Equatable {
    public var skyTop: RGB
    public var skyMid: RGB
    public var skyLow: RGB
    public var sun: RGB
    /// Alpha of the sun's radial glow. Bright skies want less of it, not more.
    public var sunGlow: Double
    public var cloudAlpha: Double
    public var landFar: RGB
    public var land: RGB
    public var roadFar: RGB
    public var road: RGB
    public var lane: RGB
    public var silhouette: RGB

    public init(skyTop: RGB, skyMid: RGB, skyLow: RGB, sun: RGB, sunGlow: Double,
                cloudAlpha: Double, landFar: RGB, land: RGB, roadFar: RGB, road: RGB,
                lane: RGB, silhouette: RGB) {
        self.skyTop = skyTop; self.skyMid = skyMid; self.skyLow = skyLow
        self.sun = sun; self.sunGlow = sunGlow; self.cloudAlpha = cloudAlpha
        self.landFar = landFar; self.land = land
        self.roadFar = roadFar; self.road = road
        self.lane = lane; self.silhouette = silhouette
    }

    // MARK: The legibility contract

    /// White text needs 7:1 (WCAG AAA for body text) against whatever is behind it.
    /// contrast = (1.0 + 0.05) / (L + 0.05) ≥ 7  ⇒  L ≤ 0.10.
    public static let maxCompositeLuminance = 0.10

    /// The word card's own black backing.
    ///
    /// Raised from the shipped 0.5 after MEASURING rendered pixels rather than modelling
    /// them. The model below only knows the ground colours, but the brightest things in the
    /// card's region are not ground: the sun disc (luminance ~0.75), its radial glow, the
    /// clouds, the horizon haze and the white road edges. Measured behind the card, the
    /// SHIPPED scene already put white text at 3.7:1 — the palette work did not cause that,
    /// it exposed it.
    ///
    /// Paying for contrast HERE rather than in the full-screen scrim is strictly better:
    /// the scrim dims the whole world including the scenery the rider is meant to enjoy,
    /// while the card only darkens the rectangle that has text in it. So the card got
    /// heavier and the scrim got lighter — the words are more readable AND the road is more
    /// vivid than before.
    public static let cardAlpha = 0.85

    /// The brightest thing the word card can sit on. `road` is normally it — the card
    /// straddles the horizon and the road runs right up the middle underneath it.
    public var groundLuminance: Double {
        max(land.luminance, max(road.luminance, max(landFar.luminance, roadFar.luminance)))
    }

    /// Luminance actually reaching the text: ground, dimmed by the scrim, then by the card.
    public func compositeLuminance(scrim: Double) -> Double {
        groundLuminance * (1 - scrim) * (1 - Self.cardAlpha)
    }

    /// How much full-screen black scrim this palette must pay for.
    ///
    /// Derived, never a literal. The shipped code used a hardcoded `Color.black.opacity(0.18)`
    /// tuned by eye for exactly one palette — so any new palette silently inherited a scrim
    /// that was never checked against it. Tying the two together means a stage cannot be made
    /// brighter without automatically buying the scrim that keeps its text readable.
    public var textScrim: Double {
        let ceiling = Self.luminanceTarget / (1 - Self.cardAlpha)
        guard groundLuminance > ceiling else { return Self.baseScrim }
        return max(Self.baseScrim, 1 - ceiling / groundLuminance)
    }

    /// Solved against a slightly stricter target than the 7:1 floor itself. Solving for the
    /// floor exactly lands at 6.999…:1 once floating-point error is applied — technically
    /// non-compliant, and the sort of thing that gets "fixed" by loosening the assertion.
    /// The margin is cheaper than that argument.
    static let luminanceTarget = maxCompositeLuminance * 0.97

    /// Now that the card carries its own contrast, the world no longer has to be dimmed to
    /// make text work — this is just a touch of depth separating card from scene.
    public static let baseScrim = 0.10

    public func lerp(to other: RidePalette, _ t: Double) -> RidePalette {
        RidePalette(
            skyTop: skyTop.lerp(to: other.skyTop, t),
            skyMid: skyMid.lerp(to: other.skyMid, t),
            skyLow: skyLow.lerp(to: other.skyLow, t),
            sun: sun.lerp(to: other.sun, t),
            sunGlow: sunGlow + (other.sunGlow - sunGlow) * min(max(t, 0), 1),
            cloudAlpha: cloudAlpha + (other.cloudAlpha - cloudAlpha) * min(max(t, 0), 1),
            landFar: landFar.lerp(to: other.landFar, t),
            land: land.lerp(to: other.land, t),
            roadFar: roadFar.lerp(to: other.roadFar, t),
            road: road.lerp(to: other.road, t),
            lane: lane.lerp(to: other.lane, t),
            silhouette: silhouette.lerp(to: other.silhouette, t))
    }
}
