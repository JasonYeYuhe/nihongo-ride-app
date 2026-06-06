import SwiftUI

/// Non-character control keys we care about.
enum KeyCommand {
    case escape, returnKey, backspace, space
}

#if os(macOS)
import AppKit

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
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onCommand?(.escape); return
        case 36, 76: onCommand?(.returnKey); return     // Return / keypad Enter
        case 51, 117: onCommand?(.backspace); return    // Delete / Forward-delete
        case 49: onCommand?(.space); return             // Space (consumed → no system beep)
        default: break
        }
        guard let characters = event.charactersIgnoringModifiers, !characters.isEmpty else { return }
        for character in characters.lowercased() {
            onKey?(character)
        }
    }

    override func keyUp(with event: NSEvent) { }
}

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

#elseif os(iOS)
import UIKit

/// A `UIKeyInput` view that brings up the keyboard (on-screen on iPhone, or a
/// hardware keyboard on iPad) and feeds each typed character to the game. Both
/// software and hardware keyboards route character keys through `insertText`, so
/// one mechanism covers every device. Autocorrect/auto-capitalization are off so
/// romaji is delivered verbatim — our mini-IME, not the system IME, does kana.
final class KeyCaptureUIView: UIView, UIKeyInput {
    var onKey: ((Character) -> Void)?
    var onCommand: ((KeyCommand) -> Void)?

    override var canBecomeFirstResponder: Bool { true }

    // UITextInputTraits — keep the input raw (no smart substitutions).
    var keyboardType: UIKeyboardType = .asciiCapable
    var autocapitalizationType: UITextAutocapitalizationType = .none
    var autocorrectionType: UITextAutocorrectionType = .no
    var smartDashesType: UITextSmartDashesType = .no
    var smartQuotesType: UITextSmartQuotesType = .no
    var smartInsertDeleteType: UITextSmartInsertDeleteType = .no
    var spellCheckingType: UITextSpellCheckingType = .no
    var returnKeyType: UIReturnKeyType = .next

    // UIKeyInput
    var hasText: Bool { false }

    func insertText(_ text: String) {
        for ch in text {
            if ch == " " {
                onCommand?(.space)
            } else if ch == "\n" || ch == "\r" {
                onCommand?(.returnKey)
            } else {
                for c in String(ch).lowercased() { onKey?(c) }
            }
        }
    }

    func deleteBackward() { onCommand?(.backspace) }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            DispatchQueue.main.async { [weak self] in _ = self?.becomeFirstResponder() }
        }
    }

    // Hardware-keyboard Escape support.
    override var keyCommands: [UIKeyCommand]? {
        [UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(handleEscape))]
    }

    @objc private func handleEscape() { onCommand?(.escape) }
}

struct KeyCaptureView: UIViewRepresentable {
    var onKey: (Character) -> Void
    var onCommand: (KeyCommand) -> Void = { _ in }

    func makeUIView(context: Context) -> KeyCaptureUIView {
        let view = KeyCaptureUIView()
        view.onKey = onKey
        view.onCommand = onCommand
        return view
    }

    func updateUIView(_ uiView: KeyCaptureUIView, context: Context) {
        uiView.onKey = onKey
        uiView.onCommand = onCommand
    }
}
#endif
