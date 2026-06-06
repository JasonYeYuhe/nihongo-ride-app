import AppKit

/// Tiny sound-effects helper using built-in macOS system sounds
/// (/System/Library/Sounds) — no bundled audio assets required.
/// Main-actor isolated since it's only driven from the SwiftUI layer.
@MainActor
enum Sound {
    /// Global mute switch, mirrored from the user's setting.
    static var enabled = true

    private static var cache: [String: NSSound] = [:]

    private static func play(_ name: String, volume: Float = 1.0) {
        guard enabled else { return }
        let sound = cache[name] ?? NSSound(named: NSSound.Name(name))
        cache[name] = sound
        sound?.stop()
        sound?.volume = volume
        sound?.play()
    }

    /// A keystroke was accepted (subtle click for typing feel).
    static func tick() { play("Tink", volume: 0.22) }
    /// A word was finished.
    static func wordComplete() { play("Pop", volume: 0.7) }
    /// A wrong key was pressed.
    static func mistake() { play("Basso", volume: 0.4) }
    /// The whole run finished.
    static func finish() { play("Glass", volume: 0.6) }
}
