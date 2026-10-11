// Hosts the MTKView and translates UIKit input — touches, hardware keyboard,
// mouse/trackpad — into GameRuntime's InputRouter / TouchControls.

import UIKit
import MetalKit
import GameController
import PebbleApp

final class GameViewController: UIViewController {
    let platform = IOSPlatform()
    private(set) var runtime: GameRuntime!
    private(set) var mtkView: MTKView!
    private var started = false

    // keyboard modifier state (iOS reports modifiers as separate presses)
    private var shiftDown = false, ctrlDown = false, cmdDown = false

    override func loadView() {
        guard let device = MTLCreateSystemDefaultDevice() else { fatalError("no Metal device") }
        let firstLaunch = !GameRuntime.hasSavedSettings
        platform.controller = self
        runtime = GameRuntime(platform: platform, device: device)
        if firstLaunch {
            runtime.applyDevicePreset(UIDevice.current.userInterfaceIdiom == .pad ? .tablet : .phone)
        }

        let v = MTKView(frame: UIScreen.main.bounds, device: device)
        v.delegate = runtime
        v.colorPixelFormat = .bgra8Unorm
        v.depthStencilPixelFormat = .invalid
        v.preferredFramesPerSecond = 60
        v.isMultipleTouchEnabled = true
        if GameRuntime.needsReadableFramebuffer { v.framebufferOnly = false }
        mtkView = v
        view = v

        // mouse/trackpad cursor position while no button is held
        let hover = UIHoverGestureRecognizer(target: self, action: #selector(hovered(_:)))
        v.addGestureRecognizer(hover)
        // two-finger trackpad / mouse-wheel scrolling
        let scroll = UIPanGestureRecognizer(target: self, action: #selector(scrolled(_:)))
        scroll.allowedScrollTypesMask = .all
        scroll.allowedTouchTypes = []   // scroll events only, never finger drags
        v.addGestureRecognizer(scroll)

        observeMice()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // native pixels, not points: the GUI scale and render targets want them
        let scale = view.window?.screen.nativeScale ?? UIScreen.main.nativeScale
        if mtkView.contentScaleFactor != scale { mtkView.contentScaleFactor = scale }
        if !started, mtkView.drawableSize.width > 0 {
            started = true
            runtime.start(drawableSize: mtkView.drawableSize)
            platform.applyMaxFps(60)
        }
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        if started { runtime.safeAreaChanged() }
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }
    override var prefersPointerLocked: Bool { platform.pointerCaptured }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }

    private var pointerLocked: Bool { view.window?.windowScene?.pointerLockState?.isLocked ?? false }

    // MARK: lifecycle (from SceneDelegate)

    func appWillResignActive() {
        shiftDown = false; ctrlDown = false; cmdDown = false
        runtime.didResignActive()
        mtkView.isPaused = true
    }
    func appDidBecomeActive() {
        mtkView.isPaused = false
    }
    func appDidEnterBackground() {
        runtime.saveNow()
        runtime.suspendAudio()
    }
    func appWillEnterForeground() {
        runtime.resumeAudio()
    }

    // MARK: touches

    private func pixel(_ t: UITouch) -> (Double, Double) {
        let p = t.location(in: view)
        let s = Double(mtkView.contentScaleFactor)
        return (Double(p.x) * s, Double(p.y) * s)
    }
    private func touchID(_ t: UITouch) -> Int { ObjectIdentifier(t).hashValue }

    /// mouse button for an indirect-pointer touch, from the event's button mask
    private func button(_ event: UIEvent?) -> Int {
        guard let mask = event?.buttonMask else { return 0 }
        if mask.contains(.secondary) { return 2 }
        if mask.contains(.button(3)) { return 1 }
        return 0
    }
    private var pointerButton = 0

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let (x, y) = pixel(t)
            if t.type == .indirectPointer {
                if pointerLocked { continue }   // GCMouse handles locked clicks
                pointerButton = button(event)
                runtime.input.pointerMoved(x: x, y: y, dx: 0, dy: 0)
                runtime.input.pointerDown(x: x, y: y, button: pointerButton)
            } else {
                runtime.touch.began(id: touchID(t), x: x, y: y)
            }
        }
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let (x, y) = pixel(t)
            if t.type == .indirectPointer {
                if pointerLocked { continue }
                if !runtime.input.mouseCaptured { runtime.input.pointerMoved(x: x, y: y, dx: 0, dy: 0) }
            } else {
                runtime.touch.moved(id: touchID(t), x: x, y: y)
            }
        }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let (x, y) = pixel(t)
            if t.type == .indirectPointer {
                if pointerLocked { continue }
                runtime.input.pointerUp(x: x, y: y, button: pointerButton)
            } else {
                runtime.touch.ended(id: touchID(t), x: x, y: y)
            }
        }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            if t.type == .indirectPointer {
                runtime.input.pointerUp(x: -1, y: -1, button: pointerButton)
            } else {
                runtime.touch.cancelled(id: touchID(t))
            }
        }
    }

    @objc private func hovered(_ g: UIHoverGestureRecognizer) {
        guard !runtime.input.mouseCaptured else { return }
        let p = g.location(in: view)
        let s = Double(mtkView.contentScaleFactor)
        runtime.input.pointerMoved(x: Double(p.x) * s, y: Double(p.y) * s, dx: 0, dy: 0)
    }

    private var scrollAccum = 0.0
    @objc private func scrolled(_ g: UIPanGestureRecognizer) {
        // accumulate continuous deltas to wheel notches, like the Mac trackpad path
        let dy = Double(g.translation(in: view).y)
        g.setTranslation(.zero, in: view)
        scrollAccum += dy
        while abs(scrollAccum) >= 12 {
            runtime.input.wheel(up: scrollAccum > 0)
            scrollAccum -= scrollAccum > 0 ? 12 : -12
        }
        if g.state == .ended || g.state == .cancelled { scrollAccum = 0 }
    }

    // MARK: mouse (pointer locked → raw deltas + buttons via GameController)

    private func observeMice() {
        NotificationCenter.default.addObserver(forName: .GCMouseDidConnect, object: nil, queue: .main) { [weak self] n in
            if let m = n.object as? GCMouse { self?.attach(m) }
        }
        GCMouse.mice().forEach(attach)
    }

    private func attach(_ mouse: GCMouse) {
        guard let input = mouse.mouseInput else { return }
        input.mouseMovedHandler = { [weak self] _, dx, dy in
            DispatchQueue.main.async {
                guard let self, self.runtime.input.mouseCaptured else { return }
                // GameController's y axis points up; mouse-look deltas point down
                self.runtime.input.look(dx: Double(dx), dy: Double(-dy))
            }
        }
        let center = { [weak self] () -> (Double, Double) in
            guard let self else { return (0, 0) }
            return (Double(self.mtkView.drawableSize.width) / 2, Double(self.mtkView.drawableSize.height) / 2)
        }
        func bind(_ b: GCControllerButtonInput?, _ index: Int) {
            b?.pressedChangedHandler = { [weak self] _, _, pressed in
                DispatchQueue.main.async {
                    guard let self, self.pointerLocked else { return }
                    let (x, y) = center()
                    if pressed { self.runtime.input.pointerDown(x: x, y: y, button: index) }
                    else { self.runtime.input.pointerUp(x: x, y: y, button: index) }
                }
            }
        }
        bind(input.leftButton, 0)
        bind(input.rightButton, 2)
        bind(input.middleButton, 1)
        input.scroll.yAxis.valueChangedHandler = { [weak self] _, v in
            DispatchQueue.main.async {
                guard let self, self.pointerLocked, v != 0 else { return }
                self.runtime.input.wheel(up: v > 0)
            }
        }
    }

    // MARK: hardware keyboard

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for p in presses {
            guard let key = p.key else { continue }
            handled = true
            let usage = key.keyCode.rawValue
            if let m = modifierKey(usage) {
                setModifier(m, true)
                continue
            }
            var code = HID_KEY_MAP[usage] ?? ""
            // many iPad keyboards have no Escape key: Cmd-. is the standard stand-in
            if cmdDown && code == "Period" { code = "Escape" }
            // Cmd-V pastes into the focused field
            if cmdDown && code == "KeyV", let s = platform.pasteboardString() {
                runtime.paste(s)
                continue
            }
            runtime.input.keyDown(code, characters: key.characters, isRepeat: false,
                                  command: cmdDown, control: ctrlDown, shift: shiftDown)
        }
        if !handled { super.pressesBegan(presses, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for p in presses {
            guard let key = p.key else { continue }
            handled = true
            let usage = key.keyCode.rawValue
            if let m = modifierKey(usage) {
                setModifier(m, false)
                continue
            }
            if let code = HID_KEY_MAP[usage] { runtime.input.keyUp(code) }
        }
        if !handled { super.pressesEnded(presses, with: event) }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        pressesEnded(presses, with: event)
    }

    private func setModifier(_ m: ModifierKey, _ down: Bool) {
        switch m {
        case .shift: shiftDown = down
        case .control: ctrlDown = down
        case .command: cmdDown = down; return
        }
        runtime.input.modifiers(shift: shiftDown, ctrl: ctrlDown)
    }
}
