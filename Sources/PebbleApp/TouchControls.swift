// Touch input: shells forward raw touches (stable id + drawable-pixel
// position) and this turns them into game input.
//
// In-world (crosshair-style, so the engine's aim ray is unchanged):
//   left side    floating move stick; past the outer ring sprints
//   right side   drag to look; tap = use/place (attack if a mob is under the
//                crosshair); press and hold still ~¼ s = break/attack (or
//                use, for food, bows, shields…). Like Minecraft, only a fresh
//                press digs: steering away stops the dig, and the finger must
//                lift and press again (a held use keeps going, so bows aim)
//   buttons      jump (double-tap flies), sneak toggle, drop, offhand swap,
//                inventory, chat, perspective, pause; tap a hotbar slot to
//                select it, hold one to drop it
// Over screens one finger is the mouse: tap = click, hold = right-click
// (place one / take half) with the tooltip, drag = drag (sliders, splits),
// vertical drags scroll lists. A Quick Move toggle stands in for shift-click
// and a × closes screens that otherwise need Escape.

import Foundation
import QuartzCore
import PebbleCore

public final class TouchControls {
    private unowned let rt: GameRuntime
    /// the shell has a touch screen (off on the Mac: nothing is drawn)
    public var enabled = false
    /// shown until a keyboard, mouse or controller is used; the next touch
    /// brings it back
    private(set) var visible = true

    init(_ rt: GameRuntime) { self.rt = rt }

    private var ui: UIManager { rt.ui }
    private var game: GameCore { rt.game }
    private func now() -> Double { CACurrentMediaTime() }

    public func hardwareInputUsed() {
        guard enabled, visible else { return }
        visible = false
        releaseWorldTouches()
        ui.touchMode = false
    }

    // MARK: - layout (UI units, inside the safe area)

    private struct Rect {
        var x, y, w, h: Double
        func contains(_ px: Double, _ py: Double, slop: Double = 3) -> Bool {
            px >= x - slop && px < x + w + slop && py >= y - slop && py < y + h + slop
        }
    }

    private enum WorldButton: CaseIterable {
        case jump, sneak, drop, swap, inventory, chat, perspective, pause
    }

    private var left: Double { ui.safeLeft }
    private var right: Double { ui.width - ui.safeRight }
    private var top: Double { ui.safeTop }
    private var bottom: Double { ui.height - ui.safeBottom }

    private func rect(_ b: WorldButton) -> Rect {
        let R = right, B = bottom, T = top
        // an L in the bottom-right corner: jump above sneak, then along the
        // bottom leftward swap, drop, inventory. The gaps take what room the
        // hotbar leaves (4 on iPads), so inventory never covers the hotbar.
        let colW = 30.0, sneakH = 26.0, rowH = 22.0, swapW = 20.0, dropW = 22.0, invW = 16.0
        let hotbarEnd = (ui.width / 2).rounded(.down) + 91 + 3
        let spare = R - 3 - hotbarEnd - (colW + swapW + dropW + invW)
        let gap = min(4, max(1, (spare / 3).rounded(.down)))
        let sneakX = R - 3 - colW, swapX = sneakX - gap - swapW, dropX = swapX - gap - dropW
        let rowY = B - 1 - rowH, sneakY = B - 1 - sneakH
        switch b {
        case .jump: return Rect(x: sneakX, y: sneakY - gap - 32, w: colW, h: 32)
        case .sneak: return Rect(x: sneakX, y: sneakY, w: colW, h: sneakH)
        case .swap: return Rect(x: swapX, y: rowY, w: swapW, h: rowH)
        case .drop: return Rect(x: dropX, y: rowY, w: dropW, h: rowH)
        case .inventory: return Rect(x: max(dropX - gap - invW, hotbarEnd), y: rowY, w: invW, h: rowH)
        case .pause: return Rect(x: R - 22, y: T + 4, w: 18, h: 16)
        case .chat: return Rect(x: R - 44, y: T + 4, w: 18, h: 16)
        case .perspective: return Rect(x: R - 66, y: T + 4, w: 18, h: 16)
        }
    }

    /// pixel-art glyphs ('#' lit), drawn in white with the font's drop shadow
    private func icon(_ b: WorldButton) -> [String] {
        switch b {
        case .jump: return [        // up arrow
            "....#....",
            "...###...",
            "..#####..",
            ".#######.",
            "#########",
            "...###...",
            "...###...",
            "...###...",
            "...###...",
        ]
        case .sneak: return [       // down arrow onto the floor
            "....###....",
            "....###....",
            "....###....",
            "....###....",
            "###########",
            ".#########.",
            "..#######..",
            "...#####...",
            "....###....",
            ".....#.....",
            "...........",
            "###########",
        ]
        case .drop: return [        // (beside the held item) down arrow
            "...#...",
            "...#...",
            "...#...",
            "#######",
            ".#####.",
            "..###..",
            "...#...",
        ]
        case .swap: return [        // trade hands
            "...#.......",
            "..##.......",
            ".#########.",
            "..##.......",
            "...#.......",
            "...........",
            ".......#...",
            ".......##..",
            ".#########.",
            ".......##..",
            ".......#...",
        ]
        case .inventory: return [   // chest
            "##########",
            "#........#",
            "#........#",
            "##########",
            "#...##...#",
            "#...##...#",
            "#........#",
            "#........#",
            "##########",
        ]
        case .chat: return [        // speech bubble
            "###########",
            "#.........#",
            "#.#######.#",
            "#.........#",
            "#.####....#",
            "#.........#",
            "###########",
            ".##........",
            ".#.........",
        ]
        case .perspective: return [ // eye: change view
            "...#####...",
            ".##.....##.",
            "#...###...#",
            "#..#####..#",
            "#...###...#",
            ".##.....##.",
            "...#####...",
        ]
        case .pause: return [
            "##..##",
            "##..##",
            "##..##",
            "##..##",
            "##..##",
            "##..##",
            "##..##",
            "##..##",
        ]
        }
    }

    private static let closeIcon = [
        "##....##",
        "###..###",
        ".######.",
        "..####..",
        "..####..",
        ".######.",
        "###..###",
        "##....##",
    ]

    /// hotbar slot under a point (matches HUD's layout)
    private func hotbarSlot(_ x: Double, _ y: Double) -> Int? {
        let hbX = (ui.width / 2).rounded(.down) - 91, hbY = bottom - 22
        guard y >= hbY - 2, y < hbY + 24, x >= hbX, x < hbX + 182 else { return nil }
        return min(8, max(0, Int((x - hbX) / 20)))
    }

    private let stickRadius = 20.0

    // MARK: - touch state

    private enum Role {
        case stick(originX: Double, originY: Double)
        case look(LookTouch)
        case button(WorldButton)
        case hotbar(slot: Int, startT: Double, dropped: Bool)
        case pointer(startT: Double, startX: Double, startY: Double, phase: PointerPhase)
        case screenButton(ScreenButton)
        case ignored
    }
    /// a right-side finger: looks when dragged, digs/uses if it's held still
    /// from the press
    private struct LookTouch {
        var startT: Double
        var startX: Double, startY: Double
        /// dragged past the tap slop: turning the camera, no tap on release
        var moved = false
        /// steered away from the press: this touch can't start (or resume) a
        /// dig until the finger lifts
        var steered = false
        /// the mouse button held down since the finger settled (0 break, 2 use)
        var holding: Int?
    }
    /// past this a touch is a drag, not a tap (UI units)
    private static let tapSlop = 6.0
    /// drift within this of the press still counts as holding still (a
    /// pressed finger rolls)
    private static let holdSlop = 9.0
    /// hold this long to start breaking/using
    private static let holdDelay = 0.25

    private enum PointerPhase { case pending, dragging, scrolling, rightHeld }
    /// the slot a drag picked its stack up from (drag-and-drop on release)
    private var dragFrom: SlotDef?
    private enum ScreenButton { case close, quickMove }

    private var touches: [Int: (role: Role, x: Double, y: Double)] = [:]
    private var sneakToggled = false
    private var sprinting = false
    private var quickMove = false
    private var scrollAccum = 0.0
    private var lastStick = (x: 0.0, y: 0.0)   // for drawing the knob

    private func gui(_ x: Double, _ y: Double) -> (Double, Double) { (x / ui.scale, y / ui.scale) }
    private func px(_ gx: Double, _ gy: Double) -> (Double, Double) { (gx * ui.scale, gy * ui.scale) }

    // MARK: - input from the shell (drawable pixels)

    public func began(id: Int, x: Double, y: Double) {
        guard enabled else { return }
        if !visible { visible = true }
        ui.touchMode = true
        rt.controller.pointerTookOver()
        let (gx, gy) = gui(x, y)
        let role: Role
        if ui.hasScreen() {
            role = beganOverScreen(gx, gy)
        } else if game.hasWorld() {
            role = beganInWorld(gx, gy)
        } else {
            role = .ignored
        }
        touches[id] = (role, gx, gy)
    }

    public func moved(id: Int, x: Double, y: Double) {
        guard var t = touches[id] else { return }
        let (gx, gy) = gui(x, y)
        let dx = gx - t.x, dy = gy - t.y
        t.x = gx; t.y = gy
        switch t.role {
        case .stick(let ox, let oy):
            updateStick(gx - ox, gy - oy)
        case .look(var l):
            if !l.moved && hypot(gx - l.startX, gy - l.startY) > Self.tapSlop { l.moved = true }
            if l.moved || l.holding != nil {
                let k = 1.5 + (game.settings.touchSensitivity ?? 0.5) * 4
                rt.input.look(dx: dx * k, dy: dy * k)
            }
            if !l.steered && hypot(gx - l.startX, gy - l.startY) > Self.holdSlop {
                // steering: stop digging (a held use, like a drawn bow, keeps
                // going so it can be aimed)
                l.steered = true
                if l.holding == 0 { game.mouseUp(0); l.holding = nil }
            }
            t.role = .look(l)
        case .pointer(let st, let sx, let sy, var phase):
            phase = movePointer(phase, gx, gy, dy, sx, sy)
            t.role = .pointer(startT: st, startX: sx, startY: sy, phase: phase)
        case .hotbar(let slot, let st, let dropped):
            // slide along the hotbar to pick a different slot
            if let s = hotbarSlot(gx, gy), s != slot, !dropped {
                game.player?.selectedSlot = s
                t.role = .hotbar(slot: s, startT: now(), dropped: false)
            } else {
                t.role = .hotbar(slot: slot, startT: st, dropped: dropped)
            }
        default:
            break
        }
        touches[id] = t
    }

    public func ended(id: Int, x: Double, y: Double) {
        guard let t = touches.removeValue(forKey: id) else { return }
        let (gx, gy) = gui(x, y)
        finish(t.role, gx, gy, cancelled: false)
    }

    public func cancelled(id: Int) {
        guard let t = touches.removeValue(forKey: id) else { return }
        finish(t.role, t.x, t.y, cancelled: true)
    }

    // MARK: - in-world

    private func beganInWorld(_ gx: Double, _ gy: Double) -> Role {
        for b in WorldButton.allCases where rect(b).contains(gx, gy) {
            pressButton(b)
            return .button(b)
        }
        if let s = hotbarSlot(gx, gy) {
            game.player?.selectedSlot = s
            return .hotbar(slot: s, startT: now(), dropped: false)
        }
        // left ~40% is the move stick (below the top button strip)
        if gx < left + (right - left) * 0.4 && gy > top + 24 {
            if stickTouch == nil {
                lastStick = (0, 0)
                return .stick(originX: gx, originY: gy)
            }
        }
        return .look(LookTouch(startT: now(), startX: gx, startY: gy))
    }

    private var stickTouch: Int? {
        touches.first { if case .stick = $0.value.role { return true } else { return false } }?.key
    }

    private func updateStick(_ dx: Double, _ dy: Double) {
        let d = hypot(dx, dy)
        let r = stickRadius
        let k = d > r ? r / d : 1
        lastStick = (dx * k, dy * k)
        let fwd = -dy * k / r, side = dx * k / r
        let dead = d < 3
        game.analogMove = dead ? nil : (fwd, side)
        // past the outer ring while heading forward: sprint
        let wantSprint = d > r * 1.35 && fwd > 0.5
        if wantSprint != sprinting {
            sprinting = wantSprint
            let code = key("sprint")
            if wantSprint { keyDown(code) } else { rt.input.keyUp(code) }
        }
    }

    private func key(_ bind: String) -> String { game.keybinds[bind] ?? "" }
    private func keyDown(_ code: String) {
        rt.input.keyDown(code, characters: nil, isRepeat: false, command: false, control: false, shift: false)
    }
    private func tapKey(_ code: String) {
        keyDown(code)
        rt.input.keyUp(code)
    }

    private func pressButton(_ b: WorldButton) {
        switch b {
        case .jump: keyDown(key("jump"))
        case .sneak:
            if game.player?.flying == true {
                // flying: hold to descend. A sneak toggled on the ground
                // becomes this press, so letting go releases it
                if sneakToggled { sneakToggled = false } else { keyDown(key("sneak")) }
            } else {
                sneakToggled.toggle()
                if sneakToggled { keyDown(key("sneak")) } else { rt.input.keyUp(key("sneak")) }
            }
        case .drop: tapKey(key("drop"))
        case .swap: tapKey(key("swapOffhand"))
        case .inventory: tapKey(key("inventory"))
        case .chat: tapKey(key("chat"))
        case .perspective: tapKey(key("perspective"))
        case .pause: tapKey("Escape")
        }
    }

    private func releaseButton(_ b: WorldButton) {
        switch b {
        case .jump: rt.input.keyUp(key("jump"))
        case .sneak where !sneakToggled: rt.input.keyUp(key("sneak"))
        default: break
        }
    }

    private func finish(_ role: Role, _ gx: Double, _ gy: Double, cancelled: Bool) {
        switch role {
        case .stick:
            game.analogMove = nil
            lastStick = (0, 0)
            if sprinting { sprinting = false; rt.input.keyUp(key("sprint")) }
        case .look(let l):
            if let b = l.holding {
                game.mouseUp(b)
            } else if !l.moved && !cancelled && now() - l.startT < 0.3 && !ui.hasScreen() {
                // tap: hit what's under the crosshair, else use/place
                let b = game.crosshairOnEntity ? 0 : 2
                game.mouseDown(b)
                game.mouseUp(b)
            }
        case .button(let b):
            releaseButton(b)
        case .pointer(_, let sx, let sy, let phase):
            finishPointer(phase, gx, gy, sx, sy, cancelled: cancelled)
        case .screenButton(let b):
            if !cancelled { tapScreenButton(b, gx, gy) }
        case .hotbar, .ignored:
            break
        }
    }

    /// world touches can't survive a screen opening (or hardware taking over)
    private func releaseWorldTouches() {
        for (id, t) in touches {
            switch t.role {
            case .stick, .look, .button, .hotbar:
                finish(t.role, t.x, t.y, cancelled: true)
                touches[id] = (.ignored, t.x, t.y)
            default: break
            }
        }
        if sneakToggled {
            sneakToggled = false
            rt.input.keyUp(key("sneak"))
        }
    }

    // MARK: - over screens

    private func screenButtonRect(_ b: ScreenButton) -> Rect? {
        guard let s = ui.current() else { return nil }
        switch b {
        case .close:
            // screens that only close with Escape get a ×; menus with their
            // own Done/Back buttons don't need one
            guard s.closeOnEsc, !s.buttons.contains(where: { ["Done", "Back", "Cancel", "Back to Game"].contains($0.label) })
            else { return nil }
            return Rect(x: right - 22, y: top + 4, w: 18, h: 18)
        case .quickMove:
            guard !s.slots.isEmpty else { return nil }
            return Rect(x: left + 4, y: top + 4, w: 54, h: 16)
        }
    }

    private func beganOverScreen(_ gx: Double, _ gy: Double) -> Role {
        for b in [ScreenButton.close, .quickMove] {
            if let r = screenButtonRect(b), r.contains(gx, gy, slop: 2) { return .screenButton(b) }
        }
        // only one finger drives the pointer
        if touches.values.contains(where: { if case .pointer = $0.role { return true } else { return false } }) {
            return .ignored
        }
        // hover first: the tooltip (and the screen's hover state) follows the finger
        let (x, y) = px(gx, gy)
        rt.input.pointerMoved(x: x, y: y, dx: 0, dy: 0)
        // fields, buttons and sliders respond on touch-down; slots (and
        // scrollable lists) wait to see whether this is a tap, a hold
        // (right-click), a drag or a scroll
        if let s = ui.current(), onControl(s, gx, gy) || (s.slotAt(gx, gy) == nil && !s.touchScrolls) {
            pointerDown(gx, gy, 0)
            return .pointer(startT: now(), startX: gx, startY: gy, phase: .dragging)
        }
        return .pointer(startT: now(), startX: gx, startY: gy, phase: .pending)
    }

    private func onControl(_ s: Screen, _ gx: Double, _ gy: Double) -> Bool {
        s.buttons.contains { $0.contains(gx, gy) } || s.sliders.contains { $0.contains(gx, gy) }
            || s.fields.contains { $0.contains(gx, gy) }
    }

    private func pointerDown(_ gx: Double, _ gy: Double, _ button: Int) {
        let (x, y) = px(gx, gy)
        let wasShift = ui.shiftDown
        if quickMove && button == 0 { ui.shiftDown = true }
        rt.input.pointerDown(x: x, y: y, button: button)
        ui.shiftDown = wasShift
    }

    private func movePointer(_ phase: PointerPhase, _ gx: Double, _ gy: Double, _ dy: Double,
                             _ sx: Double, _ sy: Double) -> PointerPhase {
        let (x, y) = px(gx, gy)
        switch phase {
        case .pending:
            let ddx = gx - sx, ddy = gy - sy
            guard hypot(ddx, ddy) > 5 else {
                rt.input.pointerMoved(x: x, y: y, dx: 0, dy: 0)
                return .pending
            }
            // mostly vertical, nothing held: scroll; otherwise start a drag
            // from where the finger went down (drag-splitting stacks)
            if abs(ddy) > abs(ddx) * 1.5 && ui.cursorStack == nil && ui.current()?.touchScrolls == true {
                scrollAccum = ddy
                return .scrolling
            }
            dragFrom = ui.current()?.slotAt(sx, sy)
            pointerDown(sx, sy, 0)
            rt.input.pointerMoved(x: x, y: y, dx: 0, dy: 0)
            return .dragging
        case .scrolling:
            scrollAccum += dy
            while abs(scrollAccum) >= 12 {
                rt.input.wheel(up: scrollAccum > 0)
                scrollAccum -= scrollAccum > 0 ? 12 : -12
            }
            return .scrolling
        case .dragging, .rightHeld:
            rt.input.pointerMoved(x: x, y: y, dx: 0, dy: 0)
            return phase
        }
    }

    private func finishPointer(_ phase: PointerPhase, _ gx: Double, _ gy: Double, _ sx: Double, _ sy: Double,
                               cancelled: Bool) {
        let (x, y) = px(gx, gy)
        switch phase {
        case .pending:
            // a quick tap on a slot: left click
            if !cancelled {
                pointerDown(sx, sy, 0)
                rt.input.pointerUp(x: x, y: y, button: 0)
            }
        case .dragging:
            rt.input.pointerUp(x: x, y: y, button: 0)
            // dragged a stack from one slot to another: drop it there
            if let from = dragFrom, ui.cursorStack != nil, !cancelled,
               let to = ui.current()?.slotAt(gx, gy), to !== from {
                pointerDown(gx, gy, 0)
                rt.input.pointerUp(x: x, y: y, button: 0)
            }
            dragFrom = nil
        case .rightHeld:
            rt.input.pointerUp(x: x, y: y, button: 2)
        case .scrolling:
            break
        }
        // park the hover point off-screen so the tooltip doesn't linger —
        // unless an item rides the cursor, which should stay where it was
        if ui.cursorStack == nil {
            rt.input.pointerMoved(x: -10_000, y: -10_000, dx: 0, dy: 0)
        }
    }

    private func tapScreenButton(_ b: ScreenButton, _ gx: Double, _ gy: Double) {
        guard let r = screenButtonRect(b), r.contains(gx, gy, slop: 6) else { return }
        switch b {
        case .close: tapKey("Escape")
        case .quickMove: quickMove.toggle()
        }
    }

    // MARK: - per frame: hold timers, screen transitions

    func frame() {
        guard enabled else { return }
        let t = now()
        if ui.hasScreen() {
            releaseWorldTouches()
        } else {
            // the screen closed under a finger: that finger must not go on to
            // click (or long-press) into the world
            for (id, e) in touches {
                switch e.role {
                case .pointer, .screenButton: touches[id] = (.ignored, e.x, e.y)
                default: break
                }
            }
            dragFrom = nil
        }
        for (id, var e) in touches {
            switch e.role {
            case .look(var l) where l.holding == nil && !l.steered && t - l.startT >= Self.holdDelay:
                // held still from the press: start breaking (or using a
                // hold-to-use item) until the finger lifts or steers away
                let b = game.heldItemUsesOnHold ? 2 : 0
                game.mouseDown(b)
                l.holding = b
                l.moved = true
                e.role = .look(l)
            case .hotbar(let slot, let st, false) where t - st >= 0.5:
                tapKey(key("drop"))
                e.role = .hotbar(slot: slot, startT: st, dropped: true)
            case .pointer(let st, let sx, let sy, .pending) where t - st >= 0.35:
                // long press on a slot: right-click (place one / take half)
                pointerDown(sx, sy, 2)
                e.role = .pointer(startT: st, startX: sx, startY: sy, phase: .rightHeld)
            default:
                continue
            }
            touches[id] = e
        }
    }

    // MARK: - drawing

    private func buttonFrame(_ cv: UICanvas, _ r: Rect, active: Bool) {
        cv.setFill(active ? "rgba(255,255,255,0.45)" : "rgba(0,0,0,0.35)")
        cv.fillRect(r.x, r.y, r.w, r.h)
        cv.setStroke("rgba(255,255,255,0.55)")
        cv.strokeRect(r.x, r.y, r.w, r.h)
    }

    private func button(_ cv: UICanvas, _ r: Rect, _ text: String, active: Bool = false) {
        buttonFrame(cv, r, active: active)
        cv.drawTextCentered(text, r.x + r.w / 2, r.y + (r.h - 8) / 2, 1)
    }

    /// a glyph centered in `r` at the largest whole scale that leaves a margin
    private func drawIcon(_ cv: UICanvas, _ rows: [String], in r: Rect) {
        let w = Double(rows.map(\.count).max() ?? 0), h = Double(rows.count)
        let s = max(1, ((min(r.w, r.h) - 6) / max(w, h)).rounded(.down))
        let x0 = (r.x + (r.w - w * s) / 2).rounded(.down)
        let y0 = (r.y + (r.h - h * s) / 2).rounded(.down)
        for (color, off) in [("#3f3f3f", 1.0), ("#ffffff", 0.0)] {
            cv.setFill(color)
            for (j, row) in rows.enumerated() {
                for (i, ch) in row.enumerated() where ch == "#" {
                    cv.fillRect(x0 + Double(i) * s + off, y0 + Double(j) * s + off, s, s)
                }
            }
        }
    }

    private func drawButton(_ cv: UICanvas, _ b: WorldButton, active: Bool) {
        let r = rect(b)
        buttonFrame(cv, r, active: active)
        guard b == .drop else { drawIcon(cv, icon(b), in: r); return }
        // drop: the held item (or an empty slot) and an arrow out of the hand
        let item = Rect(x: r.x + 4, y: r.y + (r.h - 10) / 2, w: 10, h: 10)
        if let st = game.player?.mainHandStack {
            cv.drawItemIcon(st.id, st.data, item.x, item.y, item.w, item.h)
        } else {
            cv.setStroke("rgba(255,255,255,0.55)")
            cv.strokeRect(item.x + 1, item.y + 1, item.w - 2, item.h - 2)
        }
        drawIcon(cv, icon(.drop), in: Rect(x: item.x + item.w, y: r.y, w: r.x + r.w - item.x - item.w, h: r.h))
    }

    /// on-screen controls over the HUD (no screen open)
    func drawWorld(_ ui: UIManager) {
        guard enabled, visible, game.hasWorld(), !rt.hud.hideGui else { return }
        let cv = ui.cv
        let pressed = Set(touches.values.compactMap { e -> WorldButton? in
            if case .button(let b) = e.role { return b } else { return nil }
        })
        for b in WorldButton.allCases {
            let active = pressed.contains(b) || (b == .sneak && sneakToggled)
            drawButton(cv, b, active: active)
        }
        // the stick, where the thumb went down
        if let id = stickTouch, case .stick(let ox, let oy) = touches[id]!.role {
            let r = stickRadius
            cv.setFill("rgba(0,0,0,0.25)")
            cv.fillRect(ox - r, oy - r, r * 2, r * 2)
            cv.setStroke(sprinting ? "rgba(255,220,120,0.8)" : "rgba(255,255,255,0.4)")
            cv.strokeRect(ox - r, oy - r, r * 2, r * 2)
            cv.setFill("rgba(255,255,255,0.5)")
            cv.fillRect(ox + lastStick.x - 7, oy + lastStick.y - 7, 14, 14)
        } else {
            // a faint hint of where the stick lives
            let hx = left + 40, hy = bottom - 44
            cv.setStroke("rgba(255,255,255,0.18)")
            cv.strokeRect(hx - stickRadius, hy - stickRadius, stickRadius * 2, stickRadius * 2)
        }
    }

    /// × and Quick Move over screens
    func drawScreen(_ ui: UIManager) {
        guard enabled, visible, ui.hasScreen() else { return }
        let cv = ui.cv
        if let r = screenButtonRect(.close) {
            buttonFrame(cv, r, active: false)
            drawIcon(cv, Self.closeIcon, in: r)
        }
        if let r = screenButtonRect(.quickMove) { button(cv, r, "Quick Move", active: quickMove) }
    }
}
