import AppKit

/// Tiny sound-effects helper using built-in macOS system sounds
/// (/System/Library/Sounds) — no bundled audio assets required.
/// Main-actor isolated since it's only driven from the SwiftUI layer.
@MainActor
enum Sound {
    /// Global mute switch, mirrored from the user's setting.
    static var enabled = true

    private static var cache: [String: NSSound] = [:]

    private static func play(_ name: String) {
        guard enabled else { return }
        let sound = cache[name] ?? NSSound(named: NSSound.Name(name))
        cache[name] = sound
        sound?.stop()
        sound?.play()
    }

    /// A word was finished.
    static func wordComplete() { play("Pop") }
    /// A wrong key was pressed.
    static func mistake() { play("Basso") }
    /// The whole run finished.
    static func finish() { play("Glass") }
}
