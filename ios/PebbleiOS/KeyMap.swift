// Hardware keyboard: USB HID usage → internal key-code strings (the same
// names GameCore keybinds and the Mac shell's KEYCODE_MAP use).

import UIKit

let HID_KEY_MAP: [Int: String] = {
    var m: [Int: String] = [:]
    // letters: a = 0x04 … z = 0x1D
    for (i, c) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ".enumerated() { m[0x04 + i] = "Key\(c)" }
    // digits: 1 = 0x1E … 9 = 0x26, 0 = 0x27
    for i in 1...9 { m[0x1D + i] = "Digit\(i)" }
    m[0x27] = "Digit0"
    // F1 = 0x3A … F12 = 0x45
    for i in 1...12 { m[0x39 + i] = "F\(i)" }
    // keypad 1 = 0x59 … 9 = 0x61, 0 = 0x62
    for i in 1...9 { m[0x58 + i] = "Numpad\(i)" }
    m[0x62] = "Numpad0"
    let named: [Int: String] = [
        0x28: "Enter", 0x29: "Escape", 0x2A: "Backspace", 0x2B: "Tab", 0x2C: "Space",
        0x2D: "Minus", 0x2E: "Equal", 0x2F: "BracketLeft", 0x30: "BracketRight",
        0x31: "Backslash", 0x32: "Backslash", 0x33: "Semicolon", 0x34: "Quote",
        0x35: "Backquote", 0x36: "Comma", 0x37: "Period", 0x38: "Slash",
        0x4C: "Delete", 0x4F: "ArrowRight", 0x50: "ArrowLeft", 0x51: "ArrowDown", 0x52: "ArrowUp",
        0x54: "NumpadDivide", 0x55: "NumpadMultiply", 0x56: "NumpadSubtract", 0x57: "NumpadAdd",
        0x58: "NumpadEnter", 0x63: "NumpadDecimal", 0x64: "IntlBackslash", 0x67: "NumpadEqual",
    ]
    m.merge(named) { _, b in b }
    return m
}()

/// keys that type text — while the soft-keyboard view is first responder it
/// receives these via insertText/deleteBackward, so the press path skips them
let TEXT_KEY_CODES: Set<String> = {
    var s: Set<String> = ["Space", "Minus", "Equal", "BracketLeft", "BracketRight", "Backslash",
                          "Semicolon", "Quote", "Backquote", "Comma", "Period", "Slash", "IntlBackslash",
                          "Enter", "NumpadEnter", "Backspace", "NumpadDecimal", "NumpadDivide",
                          "NumpadMultiply", "NumpadSubtract", "NumpadAdd", "NumpadEqual"]
    for c in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" { s.insert("Key\(c)") }
    for i in 0...9 { s.insert("Digit\(i)"); s.insert("Numpad\(i)") }
    return s
}()

/// modifier keys arrive as their own presses on iOS (no flagsChanged)
enum ModifierKey { case shift, control, command }

func modifierKey(_ usage: Int) -> ModifierKey? {
    switch usage {
    case 0xE1, 0xE5: return .shift
    case 0xE0, 0xE4: return .control
    case 0xE3, 0xE7: return .command
    default: return nil
    }
}
