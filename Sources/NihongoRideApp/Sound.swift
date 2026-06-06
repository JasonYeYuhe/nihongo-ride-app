import Foundation
#if os(macOS)
import AppKit
#elseif os(iOS)
import AudioToolbox
#endif

/// Tiny sound-effects helper. On macOS it uses the built-in system sounds in
/// /System/Library/Sounds; on iOS it uses AudioServices system sound IDs. No
/// bundled audio assets required on either platform. Main-actor isolated since
/// it's only driven from the SwiftUI layer.
@MainActor
enum Sound {
    /// Global mute switch, mirrored from the user's setting.
    static var enabled = true

    /// A keystroke was accepted (subtle click for typing feel).
    static func tick() { play(macName: "Tink", macVolume: 0.22, iosID: 1104) }
    /// A word was finished.
    static func wordComplete() { play(macName: "Pop", macVolume: 0.7, iosID: 1057) }
    /// A wrong key was pressed.
    static func mistake() { play(macName: "Basso", macVolume: 0.4, iosID: 1053) }
    /// The whole run finished.
    static func finish() { play(macName: "Glass", macVolume: 0.6, iosID: 1109) }

    #if os(macOS)
    private static var cache: [String: NSSound] = [:]
    private static func play(macName: String, macVolume: Float, iosID: UInt32) {
        guard enabled else { return }
        let sound = cache[macName] ?? NSSound(named: NSSound.Name(macName))
        cache[macName] = sound
        sound?.stop()
        sound?.volume = macVolume
        sound?.play()
    }
    #elseif os(iOS)
    private static func play(macName: String, macVolume: Float, iosID: UInt32) {
        guard enabled else { return }
        AudioServicesPlaySystemSound(SystemSoundID(iosID))
    }
    #endif
}
