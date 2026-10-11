// Touch input: shells forward raw touches (stable id + drawable-pixel
// position) and this turns them into pointer events over screens, or into
// on-screen game controls in-world.

import Foundation
import PebbleCore

public final class TouchControls {
    private unowned let rt: GameRuntime
    /// the finger currently acting as the mouse over a screen
    private var pointerTouch: Int?

    init(_ rt: GameRuntime) { self.rt = rt }

    private var screenOpen: Bool { rt.ui.hasScreen() }

    public func began(id: Int, x: Double, y: Double) {
        if screenOpen {
            guard pointerTouch == nil else { return }
            pointerTouch = id
            rt.input.pointerMoved(x: x, y: y, dx: 0, dy: 0)
            rt.input.pointerDown(x: x, y: y, button: 0)
        }
    }

    public func moved(id: Int, x: Double, y: Double) {
        if id == pointerTouch {
            rt.input.pointerMoved(x: x, y: y, dx: 0, dy: 0)
        }
    }

    public func ended(id: Int, x: Double, y: Double) {
        if id == pointerTouch {
            pointerTouch = nil
            rt.input.pointerUp(x: x, y: y, button: 0)
        }
    }

    public func cancelled(id: Int) {
        if id == pointerTouch {
            pointerTouch = nil
            rt.input.pointerUp(x: -1, y: -1, button: 0)
        }
    }
}
