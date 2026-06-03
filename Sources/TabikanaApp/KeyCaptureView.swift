import SwiftUI
import AppKit

/// Non-character control keys we care about.
enum KeyCommand {
    case escape, returnKey, backspace, space
}

/// A custom `NSView` that captures raw key-down events and **bypasses the system
/// IME** by deliberately *not* adopting `NSTextInputClient` and *not* calling
/// `interpretKeyEvents(_:)`. With a Japanese input source active, a view that
/// stays out of the text-input-management system simply receives the raw event —
/// exactly what our mini-IME needs. See `docs/RESEARCH.md` §1.
final class KeyCaptureNSView: NSView {
    var onKey: ((Character) -> Void)?
    var onCommand: ((KeyCommand) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Take first responder once the window exists.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        // Control keys by physical key code (layout-independent).
        switch event.keyCode {
        case 53: onCommand?(.escape); return
        case 36, 76: onCommand?(.returnKey); return     // Return / keypad Enter
        case 51, 117: onCommand?(.backspace); return    // Delete / Forward-delete
        case 49: onCommand?(.space); return             // Space (consumed → no system beep)
        default: break
        }

        // Romaji letters / punctuation. Use charactersIgnoringModifiers (dead-key
        // resistant) and normalize to lowercase; never forward to interpretKeyEvents.
        guard let characters = event.charactersIgnoringModifiers, !characters.isEmpty else { return }
        for character in characters.lowercased() {
            onKey?(character)
        }
    }

    // Swallow keyUp too so nothing leaks to the responder chain / system beep.
    override func keyUp(with event: NSEvent) { }
}

/// SwiftUI wrapper. Place it in the view hierarchy (e.g. as a background) so it
/// can become first responder and feed keystrokes to the game.
struct KeyCaptureView: NSViewRepresentable {
    var onKey: (Character) -> Void
    var onCommand: (KeyCommand) -> Void = { _ in }

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.onKey = onKey
        view.onCommand = onCommand
        return view
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        nsView.onKey = onKey
        nsView.onCommand = onCommand
    }
}
