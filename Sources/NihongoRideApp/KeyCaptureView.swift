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
    /// iOS-only concept (software keyboard); accepted and ignored on macOS so
    /// call sites stay platform-agnostic.
    var suppressSoftwareKeyboard = false

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

/// Posts a request for the key-capture view to (re)claim first responder and
/// bring the on-screen keyboard back. Game screens post this from a whole-screen
/// tap gesture so a dismissed keyboard is never a dead end on touch-only iPads.
enum KeyboardSummon {
    static let notification = Notification.Name("NihongoRideSummonKeyboard")
    @MainActor static func summon() {
        NotificationCenter.default.post(name: notification, object: nil)
    }
}

/// A `UIKeyInput` view that brings up the keyboard (on-screen on iPad, or a
/// hardware keyboard when attached) and feeds each typed character to the game.
/// Both software and hardware keyboards route character keys through
/// `insertText`, so one mechanism covers every device. Autocorrect and
/// auto-capitalization are off so romaji is delivered verbatim — our mini-IME,
/// not the system IME, does the kana.
///
/// First-responder acquisition is deliberately persistent: a single
/// `becomeFirstResponder()` can fail while the SwiftUI screen-change transition
/// is still animating, and on a touch-only iPad a missing keyboard would make
/// the game screen a dead end (App Review rejection 2.1a, 2026-06-10). So the
/// view retries until it sticks, re-asserts when the app re-activates, and
/// answers `KeyboardSummon` requests posted by tap-anywhere gestures.
final class KeyCaptureUIView: UIView, UIKeyInput {
    var onKey: ((Character) -> Void)?
    var onCommand: ((KeyCommand) -> Void)?

    /// Menu/results/about set this: they want hardware-keyboard shortcuts but
    /// have nothing to type, so the software keyboard would only eat the screen
    /// (40% of an iPhone). A zero-sized custom input view suppresses it while
    /// hardware key events still arrive through `insertText`. Game screens keep
    /// the real keyboard — it MUST auto-appear there (App Review 2.1a).
    var suppressSoftwareKeyboard = false
    private lazy var emptyInputView = UIView()
    override var inputView: UIView? { suppressSoftwareKeyboard ? emptyInputView : nil }

    private var retryTimer: Timer?
    private var retriesLeft = 0

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

    override init(frame: CGRect) {
        super.init(frame: frame)
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(reclaimFirstResponder),
                           name: KeyboardSummon.notification, object: nil)
        center.addObserver(self, selector: #selector(reclaimFirstResponder),
                           name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("unused") }

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
            startRetryLoop()
        } else {
            stopRetryLoop()
            // Leaving the game screen: hand the keyboard back so it doesn't
            // linger over the menu/results.
            if isFirstResponder { resignFirstResponder() }
        }
    }

    /// Try now, and keep trying on a short interval until first responder
    /// sticks (covers the screen-change transition window).
    private func startRetryLoop() {
        retriesLeft = 20
        retryTimer?.invalidate()
        attemptBecomeFirstResponder()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.attemptBecomeFirstResponder() }
        }
    }

    private func stopRetryLoop() {
        retryTimer?.invalidate()
        retryTimer = nil
    }

    private func attemptBecomeFirstResponder() {
        guard window != nil else { stopRetryLoop(); return }
        if isFirstResponder || retriesLeft <= 0 {
            stopRetryLoop()
            return
        }
        retriesLeft -= 1
        _ = becomeFirstResponder()
    }

    @objc private func reclaimFirstResponder() {
        guard window != nil else { return }
        startRetryLoop()
    }

    // Hardware-keyboard Escape support.
    override var keyCommands: [UIKeyCommand]? {
        [UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(handleEscape))]
    }

    @objc private func handleEscape() { onCommand?(.escape) }

    // No deinit needed: `didMoveToWindow(nil)` invalidates the retry timer when
    // the view leaves the hierarchy, and selector-based NotificationCenter
    // observers are auto-unregistered on dealloc (iOS 9+).
}

struct KeyCaptureView: UIViewRepresentable {
    var onKey: (Character) -> Void
    var onCommand: (KeyCommand) -> Void = { _ in }
    /// True on screens with nothing to type (menu/results/about) — keeps
    /// hardware shortcuts but doesn't summon the software keyboard.
    var suppressSoftwareKeyboard = false

    func makeUIView(context: Context) -> KeyCaptureUIView {
        let view = KeyCaptureUIView()
        view.onKey = onKey
        view.onCommand = onCommand
        view.suppressSoftwareKeyboard = suppressSoftwareKeyboard
        return view
    }

    func updateUIView(_ uiView: KeyCaptureUIView, context: Context) {
        uiView.onKey = onKey
        uiView.onCommand = onCommand
        uiView.suppressSoftwareKeyboard = suppressSoftwareKeyboard
    }
}
#endif
