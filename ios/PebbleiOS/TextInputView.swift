// Invisible first responder that raises the on-screen keyboard while a text
// field, chat or sign is open. Pebble's fields are canvas-drawn, so typed
// text is forwarded to InputRouter like hardware keys.

import UIKit
import PebbleApp

final class TextInputView: UIView, UIKeyInput {
    weak var runtime: GameRuntime?

    override var canBecomeFirstResponder: Bool { true }

    // plain typing: seeds, world names, commands — no autocorrect surprises
    var autocorrectionType: UITextAutocorrectionType = .no
    var autocapitalizationType: UITextAutocapitalizationType = .none
    var spellCheckingType: UITextSpellCheckingType = .no
    var smartQuotesType: UITextSmartQuotesType = .no
    var smartDashesType: UITextSmartDashesType = .no
    var smartInsertDeleteType: UITextSmartInsertDeleteType = .no
    var keyboardType: UIKeyboardType = .asciiCapable
    var returnKeyType: UIReturnKeyType = .done

    var hasText: Bool { true }   // keep Backspace live even on an "empty" view

    func insertText(_ text: String) {
        guard let input = runtime?.input else { return }
        for ch in text {
            if ch == "\n" || ch == "\r" {
                input.keyDown("Enter", characters: nil, isRepeat: false, command: false, control: false, shift: false)
                input.keyUp("Enter")
            } else {
                input.keyDown("", characters: String(ch), isRepeat: false, command: false, control: false, shift: false)
            }
        }
    }

    func deleteBackward() {
        runtime?.input.keyDown("Backspace", characters: nil, isRepeat: false, command: false, control: false, shift: false)
        runtime?.input.keyUp("Backspace")
    }
}
