import Foundation

/// The one door every deck shuffle and form pick in GameCore goes through, so a headless
/// capture can be made reproducible without the shipping app changing at all.
///
/// **Why it exists (v1.34 §C3).** The render gate compares screens pixel by pixel across
/// releases, and until this seam existed 8–9 of its 24 screens differed between two runs of
/// the SAME binary: every session builder shuffled its deck with the system generator, so
/// `game.png` showed a different word each time — and `road.png` varied too, because the road
/// screen reads the odometer the earlier ride captures wrote into the shared container, and
/// how far those rides went depended on which words were drawn. A gate that cannot tell "the
/// deck came out differently" from "the change moved this line" cannot hold `road.png` and
/// `menu.png` identical, which is what the plan requires of them.
///
/// **What it does not change.** With `seed == nil` — every launch except a capture — each
/// helper calls exactly what its call site called before: `shuffle()`, `shuffled()`,
/// `randomElement()`, and `SystemRandomNumberGenerator` behind `Generator`. Only
/// `Screenshotter` sets a seed (a test pins that), and it reseeds before each screen so adding
/// or removing a screen upstream cannot change a later one.
///
/// **Concurrency.** The seeded state is global and lock-protected. `withSeed` holds the lock
/// for its whole body, so a test that seeds, builds two sessions and compares them cannot be
/// interleaved by another test's shuffle on a different thread (swift-testing runs suites in
/// parallel). Capture sets `seed` directly: it runs on the main actor and nothing else is
/// drawing.
public enum DeckRandomness {

    /// SplitMix64 — 64 bits of state, one addition and two xor-multiply mixes per output.
    /// Chosen because it is small enough to read in full and its outputs are published, so
    /// `DeckRandomnessTests` can pin the sequence against a value this file did not compute.
    /// The sequence is what makes a seeded render reproducible ACROSS releases; changing the
    /// algorithm changes every deck-random screen and must be a deliberate, named decision.
    public struct SplitMix64: RandomNumberGenerator, Sendable {
        private var state: UInt64

        public init(seed: UInt64) { state = seed }

        public mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    private static let lock = NSRecursiveLock()
    nonisolated(unsafe) private static var storedSeed: UInt64?
    nonisolated(unsafe) private static var seeded: SplitMix64?

    /// Nil on every launch except a headless capture. Setting it starts a fresh SplitMix64 at
    /// that seed; setting nil returns every helper to the system generator.
    public static var seed: UInt64? {
        get { lock.withLock { storedSeed } }
        set {
            lock.withLock {
                storedSeed = newValue
                seeded = newValue.map(SplitMix64.init(seed:))
            }
        }
    }

    /// Runs `body` with `seed` set, holding the seam's lock throughout so no other thread can
    /// draw from (or reset) the seeded generator in between, then restores the previous seed.
    /// For tests; capture sets `seed` directly.
    public static func withSeed<R>(_ value: UInt64, _ body: () throws -> R) rethrows -> R {
        lock.lock()
        defer { lock.unlock() }
        let previous = storedSeed
        seed = value
        defer { seed = previous }
        return try body()
    }

    /// `elements.shuffle()`, or the seeded order when a seed is set.
    public static func shuffle<T>(_ elements: inout [T]) {
        lock.withLock {
            if seeded != nil {
                elements.shuffle(using: &seeded!)
            } else {
                elements.shuffle()
            }
        }
    }

    /// `elements.shuffled()`, or the seeded order when a seed is set.
    public static func shuffled<T>(_ elements: [T]) -> [T] {
        var copy = elements
        shuffle(&copy)
        return copy
    }

    /// `elements.randomElement()`, or the seeded pick when a seed is set.
    public static func randomElement<T>(_ elements: [T]) -> T? {
        lock.withLock {
            if seeded != nil {
                return elements.randomElement(using: &seeded!)
            } else {
                return elements.randomElement()
            }
        }
    }

    /// A generator for call sites that take `using:` — `FormWeighting.weightedPick` in the app.
    /// Draws from the seeded generator when a seed is set; otherwise from
    /// `SystemRandomNumberGenerator`, which is stateless, so each `next()` is exactly the call
    /// the site made before (`var rng = SystemRandomNumberGenerator()`).
    public struct Generator: RandomNumberGenerator {
        public init() {}

        public mutating func next() -> UInt64 {
            DeckRandomness.lock.withLock {
                if DeckRandomness.seeded != nil {
                    return DeckRandomness.seeded!.next()
                } else {
                    var system = SystemRandomNumberGenerator()
                    return system.next()
                }
            }
        }
    }
}
