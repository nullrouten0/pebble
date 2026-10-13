// Platform-neutral input routing: shells translate their native events into
// internal key-code strings ("KeyW", "ShiftLeft", "Escape") and drawable-pixel
// pointer positions, and this decides whether each goes to the open screen or
// to the game.

import Foundation
import QuartzCore
import PebbleCore

public final class InputRouter {
    private unowned let rt: GameRuntime
    public private(set) var mouseCaptured = false
    private var ui: UIManager? { rt.ui }
    private var game: GameCore? { rt.game }

    init(_ rt: GameRuntime) { self.rt = rt }

    private func nowMs() -> Double { CACurrentMediaTime() * 1000 }

    /// drawable pixels → UI units
    private func guiPos(_ px: Double, _ py: Double) -> (Double, Double) {
        let scale = ui?.scale ?? 1
        return (px / scale, py / scale)
    }

    public func captureMouse() {
        if mouseCaptured { return }
        mouseCaptured = true
        rt.platform.setPointerCaptured(true)
    }
    public func releaseMouse() {
        if !mouseCaptured { return }
        mouseCaptured = false
        rt.platform.setPointerCaptured(false)
    }

    private func recaptureIfClear() {
        if let ui = ui, !ui.hasScreen(), let game = game, game.hasWorld() {
            captureMouse()
        }
    }

    // MARK: keyboard

    /// a key press. `characters` is the text it types (nil/empty for none);
    /// `command`/`control` are the held modifiers (shortcuts, not text)
    public func keyDown(_ code: String, characters: String?, isRepeat: Bool,
                        command: Bool, control: Bool, shift: Bool) {
        guard let game, let ui = ui else { return }
        // fullscreen toggle works everywhere, including over open screens
        if code == "F11" {
            rt.platform.toggleFullscreen()
            return
        }
        if let screen = ui.current() {
            if isRepeat && code != "Backspace" && !code.hasPrefix("Arrow") { return }
            if code == "Escape" {
                if screen.closeOnEsc {
                    ui.closeTop(game)
                    recaptureIfClear()
                }
                return
            }
            if screen.onKey(ui, game, code) { return }
            if let chars = characters, !chars.isEmpty, !command, !control,
               chars.allSatisfy({ !$0.isNewline && $0.asciiValue.map { $0 >= 32 } ?? true }) {
                if screen.onChar(ui, game, chars) { return }
            }
            // inventory key closes inventory-style screens (never text screens)
            if code == game.keybinds["inventory"], screen.closeOnEsc, !(screen is ChatScreen),
               !screen.fields.contains(where: { $0.focused }) {
                ui.closeTop(game)
                recaptureIfClear()
            }
            return
        }
        guard game.hasWorld() else { return }
        if isRepeat { return }
        // HUD toggles stay app-side
        if code == "F3" {
            rt.hud.debugVisible.toggle()
            return
        }
        if code == "F1" {
            rt.hud.hideGui.toggle()
            return
        }
        // Cmd/Ctrl+Z undoes the last big edit (blasts, /place, /fill, builders); +Shift redoes
        if code == "KeyZ" && (command || control) {
            runCommand(game, shift ? "/redo" : "/undo")
            return
        }
        game.keyDown(code, now: nowMs(), ctrlOrCmd: command || control)
    }

    public func keyUp(_ code: String) {
        game?.keyUp(code)
    }

    /// current Shift/Control state. Sneak/sprint default binds are modifier
    /// keys, which some platforms (AppKit) only report as a state change
    public func modifiers(shift: Bool, ctrl: Bool) {
        guard let game, let ui = ui else { return }
        let wasShift = ui.shiftDown, wasCtrl = ui.ctrlDown
        ui.shiftDown = shift
        ui.ctrlDown = ctrl
        if ui.hasScreen() {
            // a modifier PRESS reaches the open screen so it can be bound as a
            // keybind (Shift/Control fire flagsChanged, not keyDown)
            if let screen = ui.current() {
                if shift && !wasShift { _ = screen.onKey(ui, game, "ShiftLeft") }
                if ctrl && !wasCtrl { _ = screen.onKey(ui, game, "ControlLeft") }
            }
            // releases must still reach the game — eating them left the
            // player permanently sneaking after shift+E, release, close
            if !shift { game.keyUp("ShiftLeft") }
            if !ctrl { game.keyUp("ControlLeft") }
            return
        }
        // sneak/sprint default binds are modifier keys — synthesize code events
        if shift { game.keyDown("ShiftLeft", now: nowMs()) } else { game.keyUp("ShiftLeft") }
        if ctrl { game.keyDown("ControlLeft", now: nowMs()) } else { game.keyUp("ControlLeft") }
    }

    // MARK: pointer

    /// button 0 left, 1 middle, 2 right; position in drawable pixels, top-left origin
    public func pointerDown(x: Double, y: Double, button: Int) {
        guard let game, let ui = ui else { return }
        if let screen = ui.current() {
            let (mx, my) = guiPos(x, y)
            ui.mouseX = mx
            ui.mouseY = my
            _ = screen.onMouseDown(ui, game, mx, my, button)
            recaptureIfClear()
            return
        }
        guard game.hasWorld() else { return }
        if !mouseCaptured {
            captureMouse()
            return
        }
        game.mouseDown(button)
    }

    public func pointerUp(x: Double, y: Double, button: Int) {
        if button == 0, let screen = ui?.current(), let game, let ui = ui {
            let (mx, my) = guiPos(x, y)
            screen.onMouseUp(ui, game, mx, my)
        }
        game?.mouseUp(button)
    }

    /// pointer moved to (x, y) by (dx, dy) — cursor over screens, mouse-look
    /// once captured in-world
    public func pointerMoved(x: Double, y: Double, dx: Double, dy: Double) {
        guard let game, let ui = ui else { return }
        if ui.hasScreen() || !mouseCaptured {
            let (mx, my) = guiPos(x, y)
            ui.current()?.onMouseMove(ui, game, mx, my)
            ui.mouseX = mx
            ui.mouseY = my
            return
        }
        game.mouseDelta(dx, dy)
    }

    /// relative look (locked mouse, touch drag, right stick), in mouse-delta units
    public func look(dx: Double, dy: Double) {
        guard let game, let ui = ui, !ui.hasScreen(), game.hasWorld() else { return }
        game.mouseDelta(dx, dy)
    }

    /// one wheel notch; `up` = away from the user (scrolls lists up, hotbar left)
    public func wheel(up: Bool) {
        guard let game, let ui = ui else { return }
        if let screen = ui.current() {
            _ = screen.onWheel(ui, game, up ? -1 : 1)
            return
        }
        if game.hasWorld() {
            game.wheelHotbar(up ? 1 : -1)
        }
    }
}
