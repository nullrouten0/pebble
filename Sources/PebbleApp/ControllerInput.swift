// Game controllers (any MFi / Xbox / DualSense extended gamepad), polled
// once per frame. In-world: left stick moves, right stick looks, triggers
// break/use. Over screens: the left stick drives a virtual cursor and A
// clicks, so every canvas-drawn menu works without new UI.

import Foundation
import GameController
import QuartzCore
import PebbleCore

final class ControllerInput {
    private unowned let rt: GameRuntime
    private var held: Set<String> = []       // buttons down at the last poll
    private var heldKeys: [String: String] = [:]   // button → key code it pressed
    private var cursorX = -1.0, cursorY = -1.0     // drawable pixels
    private var scrollAt = 0.0
    /// the left stick is steering (so an idle pad doesn't clobber touch movement)
    private var stickMoving = false
    /// a controller drove input since the last touch/mouse event
    private(set) var cursorVisible = false

    init(_ rt: GameRuntime) { self.rt = rt }

    private static let deadzone: Float = 0.15

    private func axis(_ v: Float) -> Double {
        let a = abs(v)
        if a < Self.deadzone { return 0 }
        // rescale past the deadzone, then square for fine aim near center
        let t = Double((a - Self.deadzone) / (1 - Self.deadzone))
        return (v < 0 ? -1 : 1) * t * t
    }

    func poll(dtMs: Double) {
        guard let pad = GCController.current?.extendedGamepad else {
            if !held.isEmpty { releaseAll() }
            return
        }
        let dt = min(dtMs, 100) / 1000
        var now: Set<String> = []
        func mark(_ name: String, _ b: GCControllerButtonInput?) { if b?.isPressed == true { now.insert(name) } }
        mark("a", pad.buttonA); mark("b", pad.buttonB); mark("x", pad.buttonX); mark("y", pad.buttonY)
        mark("lb", pad.leftShoulder); mark("rb", pad.rightShoulder)
        mark("lt", pad.leftTrigger); mark("rt", pad.rightTrigger)
        mark("menu", pad.buttonMenu); mark("options", pad.buttonOptions)
        mark("l3", pad.leftThumbstickButton); mark("r3", pad.rightThumbstickButton)
        mark("up", pad.dpad.up); mark("down", pad.dpad.down)
        mark("left", pad.dpad.left); mark("right", pad.dpad.right)
        let lx = axis(pad.leftThumbstick.xAxis.value), ly = axis(pad.leftThumbstick.yAxis.value)
        let rx = axis(pad.rightThumbstick.xAxis.value), ry = axis(pad.rightThumbstick.yAxis.value)
        let pressed = now.subtracting(held), released = held.subtracting(now)
        held = now
        // a button, or a stick pushed well past any drift, means the player
        // picked up the pad: hide the touch controls
        let pushed = [pad.leftThumbstick, pad.rightThumbstick].contains {
            abs($0.xAxis.value) > 0.5 || abs($0.yAxis.value) > 0.5
        }
        if !pressed.isEmpty || pushed { rt.touch.hardwareInputUsed() }

        // releases first: a key held in-world must let go even if a screen opened
        for b in released {
            if let code = heldKeys.removeValue(forKey: b) { rt.input.keyUp(code) }
            switch b {
            case "rt": rt.game.mouseUp(0)
            case "lt": rt.game.mouseUp(2)
            case "a" where cursorDown: cursorDown = false; rt.input.pointerUp(x: cursorX, y: cursorY, button: 0)
            case "x" where cursorRightDown: cursorRightDown = false; rt.input.pointerUp(x: cursorX, y: cursorY, button: 2)
            default: break
            }
        }

        if rt.ui.hasScreen() {
            pollScreen(pressed, lx, ly, ry, dt)
        } else {
            cursorVisible = false
            if rt.game.hasWorld() { pollWorld(pressed, lx, ly, rx, ry, dt) }
        }
    }

    private var cursorDown = false, cursorRightDown = false

    private func key(_ bind: String) -> String { rt.game.keybinds[bind] ?? "" }

    /// press a key for as long as `button` stays held
    private func hold(_ button: String, _ code: String) {
        heldKeys[button] = code
        rt.input.keyDown(code, characters: nil, isRepeat: false, command: false, control: false, shift: false)
    }
    private func tap(_ code: String) {
        rt.input.keyDown(code, characters: nil, isRepeat: false, command: false, control: false, shift: false)
        rt.input.keyUp(code)
    }

    private func pollWorld(_ pressed: Set<String>, _ lx: Double, _ ly: Double, _ rx: Double, _ ry: Double, _ dt: Double) {
        let g = rt.game!
        if lx != 0 || ly != 0 {
            g.analogMove = (ly, lx)
            stickMoving = true
        } else if stickMoving {
            g.analogMove = nil
            stickMoving = false
        }
        // ~3 rad/s at full deflection with the default sensitivity
        if rx != 0 || ry != 0 { rt.input.look(dx: rx * 1100 * dt, dy: -ry * 800 * dt) }

        for b in pressed {
            switch b {
            case "a": hold(b, key("jump"))
            case "b": hold(b, key("sneak"))
            case "l3": hold(b, key("sprint"))
            case "rt": g.mouseDown(0)
            case "lt": g.mouseDown(2)
            case "r3": g.mouseDown(1); g.mouseUp(1)        // pick block
            case "lb": rt.input.wheel(up: true)
            case "rb": rt.input.wheel(up: false)
            case "y": tap(key("inventory"))
            case "x": tap(key("drop"))
            case "up": tap(key("perspective"))
            case "down": tap(key("swapOffhand"))
            case "left": rt.input.wheel(up: true)
            case "right": rt.input.wheel(up: false)
            case "options": tap(key("chat"))
            case "menu": tap("Escape")
            default: break
            }
        }
    }

    private func pollScreen(_ pressed: Set<String>, _ lx: Double, _ ly: Double, _ ry: Double, _ dt: Double) {
        stickMoving = false
        let size = rt.drawableSize
        if cursorX < 0 { cursorX = Double(size.width) / 2; cursorY = Double(size.height) / 2 }
        if lx != 0 || ly != 0 || !pressed.isEmpty {
            cursorVisible = true
        }
        if lx != 0 || ly != 0 {
            let speed = 320 * rt.ui.scale   // UI units per second at full tilt
            cursorX = min(Double(size.width) - 1, max(0, cursorX + lx * speed * dt))
            cursorY = min(Double(size.height) - 1, max(0, cursorY - ly * speed * dt))
            rt.input.pointerMoved(x: cursorX, y: cursorY, dx: 0, dy: 0)
        }
        // right stick scrolls lists (creative grid, world list)
        let t = CACurrentMediaTime()
        if abs(ry) > 0.3 && t >= scrollAt {
            scrollAt = t + 0.12
            rt.input.wheel(up: ry > 0)
        }
        for b in pressed {
            switch b {
            case "a":
                cursorDown = true
                rt.input.pointerMoved(x: cursorX, y: cursorY, dx: 0, dy: 0)
                rt.input.pointerDown(x: cursorX, y: cursorY, button: 0)
            case "x":
                cursorRightDown = true
                rt.input.pointerDown(x: cursorX, y: cursorY, button: 2)
            case "b", "menu": tap("Escape")
            case "y": tap(key("inventory"))   // closes inventory-style screens
            case "lb", "left": rt.input.wheel(up: true)
            case "rb", "right": rt.input.wheel(up: false)
            default: break
            }
        }
    }

    private func releaseAll() {
        for (_, code) in heldKeys { rt.input.keyUp(code) }
        heldKeys.removeAll()
        if held.contains("rt") { rt.game.mouseUp(0) }
        if held.contains("lt") { rt.game.mouseUp(2) }
        held.removeAll()
        if stickMoving { rt.game.analogMove = nil; stickMoving = false }
        // a dead battery mid-click must not leave a slider grabbed
        if cursorDown { cursorDown = false; rt.input.pointerUp(x: cursorX, y: cursorY, button: 0) }
        if cursorRightDown { cursorRightDown = false; rt.input.pointerUp(x: cursorX, y: cursorY, button: 2) }
        cursorVisible = false
    }

    /// a touch or the mouse took over: hide the controller cursor
    func pointerTookOver() { cursorVisible = false }

    /// the virtual cursor over screens (drawn last, above tooltips)
    func drawCursor(_ ui: UIManager) {
        guard cursorVisible, ui.hasScreen() else { return }
        let x = (cursorX / ui.scale).rounded(), y = (cursorY / ui.scale).rounded()
        let cv = ui.cv
        cv.setFill("#000000")
        cv.fillRect(x - 1, y - 1, 3, 9); cv.fillRect(x - 1, y - 1, 9, 3)
        cv.setFill("#ffffff")
        cv.fillRect(x, y, 1, 7); cv.fillRect(x, y, 7, 1)
    }
}
