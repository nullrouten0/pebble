// Pebble — native macOS app shell. Window + MTKView, NSEvent → internal key
// codes, pointer capture, fullscreen, and the menu bar. Everything else (game,
// renderer, UI, frame loop) lives in PebbleApp's GameRuntime.

import AppKit
import MetalKit
import PebbleApp

// ---------------------------------------------------------------------------
// NSEvent keyCode (kVK_*) → internal key-code strings (GameCore keybinds)
// ---------------------------------------------------------------------------
let KEYCODE_MAP: [UInt16: String] = [
    0: "KeyA", 1: "KeyS", 2: "KeyD", 3: "KeyF", 4: "KeyH", 5: "KeyG", 6: "KeyZ", 7: "KeyX",
    8: "KeyC", 9: "KeyV", 11: "KeyB", 12: "KeyQ", 13: "KeyW", 14: "KeyE", 15: "KeyR",
    16: "KeyY", 17: "KeyT", 18: "Digit1", 19: "Digit2", 20: "Digit3", 21: "Digit4",
    22: "Digit6", 23: "Digit5", 24: "Equal", 25: "Digit9", 26: "Digit7", 27: "Minus",
    28: "Digit8", 29: "Digit0", 30: "BracketRight", 31: "KeyO", 32: "KeyU", 33: "BracketLeft",
    34: "KeyI", 35: "KeyP", 36: "Enter", 37: "KeyL", 38: "KeyJ", 39: "Quote", 40: "KeyK",
    41: "Semicolon", 42: "Backslash", 43: "Comma", 44: "Slash", 45: "KeyN", 46: "KeyM",
    47: "Period", 48: "Tab", 49: "Space", 50: "Backquote", 51: "Backspace", 53: "Escape",
    96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11", 109: "F10",
    111: "F12", 118: "F4", 120: "F2", 122: "F1", 123: "ArrowLeft", 124: "ArrowRight",
    125: "ArrowDown", 126: "ArrowUp", 117: "Delete",
    10: "IntlBackslash", // ISO § key
    82: "Numpad0", 83: "Numpad1", 84: "Numpad2", 85: "Numpad3", 86: "Numpad4",
    87: "Numpad5", 88: "Numpad6", 89: "Numpad7", 91: "Numpad8", 92: "Numpad9",
    65: "NumpadDecimal", 67: "NumpadMultiply", 69: "NumpadAdd", 75: "NumpadDivide",
    76: "NumpadEnter", 78: "NumpadSubtract", 81: "NumpadEqual",
]

/// bundle resource lookup with a dev fallback: under `swift run` the
/// resourcePath is .build/<config> (no bundle assembly), so walk up to the
/// repo's packaging/ — otherwise dev builds silently lose the title photo,
/// wordmark and default pack
func bundleResourcePath(_ name: String) -> String? {
    if let rp = Bundle.main.resourcePath {
        let p = rp + "/" + name
        if FileManager.default.fileExists(atPath: p) { return p }
    }
    var dir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    for _ in 0..<6 {
        let cand = dir.appendingPathComponent("packaging/" + name).path
        if FileManager.default.fileExists(atPath: cand) { return cand }
        dir = dir.deletingLastPathComponent()
    }
    return nil
}

// ---------------------------------------------------------------------------
// platform hooks: what the shared runtime needs from AppKit
// ---------------------------------------------------------------------------
final class MacPlatform: PlatformHooks {
    weak var window: NSWindow?
    weak var view: GameView?
    private var uncappedMode = false
    private var uncapTimer: Timer?

    func resourcePath(_ name: String) -> String? { bundleResourcePath(name) }

    var canQuit: Bool { true }
    func quit() { NSApp.terminate(nil) }

    var supportsFullscreen: Bool { true }
    var isFullscreen: Bool { window?.styleMask.contains(.fullScreen) ?? false }
    func toggleFullscreen() { window?.toggleFullScreen(nil) }

    func setPointerCaptured(_ captured: Bool) {
        CGAssociateMouseAndMouseCursorPosition(captured ? 0 : 1)
        if captured { NSCursor.hide() } else { NSCursor.unhide() }
    }

    func pasteboardString() -> String? { NSPasteboard.general.string(forType: .string) }
    func openURL(_ url: String) { if let u = URL(string: url) { NSWorkspace.shared.open(u) } }

    func showStatus(_ title: String) { window?.title = title }

    /// maxFps >= 250 = unlimited: MTKView's display link can't exceed the panel
    /// refresh, so drive draw() from a runloop timer with vsync off instead
    func applyMaxFps(_ maxFps: Int) {
        guard let view else { return }
        let unlimited = maxFps >= 250
        if unlimited != uncappedMode {
            uncappedMode = unlimited
            (view.layer as? CAMetalLayer)?.displaySyncEnabled = !unlimited
            view.isPaused = unlimited
            view.enableSetNeedsDisplay = false
            uncapTimer?.invalidate()
            uncapTimer = nil
            if unlimited {
                let t = Timer(timeInterval: 0.0001, repeats: true) { [weak view] _ in
                    view?.draw()
                }
                RunLoop.main.add(t, forMode: .common)
                uncapTimer = t
            }
        }
        if !unlimited {
            view.preferredFramesPerSecond = max(30, maxFps)
        }
    }
}

// ---------------------------------------------------------------------------
// MTKView: NSEvent → InputRouter
// ---------------------------------------------------------------------------
final class GameView: MTKView {
    var input: InputRouter?

    override var acceptsFirstResponder: Bool { true }

    /// AppKit origin is bottom-left in points; the router wants top-left drawable pixels
    private func pixelPos(_ event: NSEvent) -> (Double, Double) {
        let p = convert(event.locationInWindow, from: nil)
        let bsf = Double(window?.backingScaleFactor ?? 1)
        return (Double(p.x) * bsf, (Double(bounds.height) - Double(p.y)) * bsf)
    }

    override func keyDown(with event: NSEvent) {
        let f = event.modifierFlags
        input?.keyDown(KEYCODE_MAP[event.keyCode] ?? "", characters: event.characters, isRepeat: event.isARepeat,
                       command: f.contains(.command), control: f.contains(.control), shift: f.contains(.shift))
    }
    override func keyUp(with event: NSEvent) {
        guard let code = KEYCODE_MAP[event.keyCode] else { return }
        input?.keyUp(code)
    }
    override func flagsChanged(with event: NSEvent) {
        input?.modifiers(shift: event.modifierFlags.contains(.shift), ctrl: event.modifierFlags.contains(.control))
    }

    private func down(_ event: NSEvent, _ btn: Int) {
        let (x, y) = pixelPos(event)
        input?.pointerDown(x: x, y: y, button: btn)
    }
    private func up(_ event: NSEvent, _ btn: Int) {
        let (x, y) = pixelPos(event)
        input?.pointerUp(x: x, y: y, button: btn)
    }
    override func mouseDown(with event: NSEvent) { down(event, 0) }
    override func rightMouseDown(with event: NSEvent) { down(event, 2) }
    override func otherMouseDown(with event: NSEvent) {
        if event.buttonNumber == 2 { down(event, 1) }
    }
    override func otherMouseUp(with event: NSEvent) {
        if event.buttonNumber == 2 { up(event, 1) }
    }
    override func mouseUp(with event: NSEvent) { up(event, 0) }
    override func rightMouseUp(with event: NSEvent) { up(event, 2) }
    override func mouseDragged(with event: NSEvent) { handleMove(event) }
    override func rightMouseDragged(with event: NSEvent) { handleMove(event) }
    override func mouseMoved(with event: NSEvent) { handleMove(event) }
    private func handleMove(_ event: NSEvent) {
        let (x, y) = pixelPos(event)
        input?.pointerMoved(x: x, y: y, dx: Double(event.deltaX), dy: Double(event.deltaY))
    }
    private var scrollAccum = 0.0
    override func scrollWheel(with event: NSEvent) {
        var dy = event.scrollingDeltaY
        if event.hasPreciseScrollingDeltas {
            // trackpads deliver many sub-notch deltas — accumulate to a
            // notch instead of discarding them (slow two-finger scrolling
            // did nothing at all)
            scrollAccum += dy
            if abs(scrollAccum) < 8 { return }
            dy = scrollAccum
            scrollAccum = 0
        } else if abs(dy) < 0.5 {
            return
        }
        input?.wheel(up: dy > 0)
    }
}

// ---------------------------------------------------------------------------
// app delegate: window, fullscreen, lifecycle
// ---------------------------------------------------------------------------
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var gameView: GameView!
    let platform = MacPlatform()
    var runtime: GameRuntime!

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let device = MTLCreateSystemDefaultDevice() else { fatalError("no Metal device") }
        runtime = GameRuntime(platform: platform, device: device)

        // test hooks: PEBBLE_WINDOWED=1 skips fullscreen; PEBBLE_WINSIZE=960x540,
        // PEBBLE_WINPOS=0,0 (two side-by-side windows for LAN testing)
        let wenv = ProcessInfo.processInfo.environment
        let windowed = wenv["PEBBLE_WINDOWED"] != nil
        var rect = NSRect(x: 0, y: 0, width: 1440, height: 810)
        if let sz = wenv["PEBBLE_WINSIZE"]?.split(separator: "x").compactMap({ Double($0) }), sz.count == 2 {
            rect.size = NSSize(width: sz[0], height: sz[1])
        }
        window = NSWindow(contentRect: rect, styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Pebble"
        window.center()
        if let pos = wenv["PEBBLE_WINPOS"]?.split(separator: ",").compactMap({ Double($0) }), pos.count == 2 {
            window.setFrameOrigin(NSPoint(x: pos[0], y: pos[1]))
        }
        gameView = GameView(frame: rect, device: device)
        gameView.input = runtime.input
        gameView.delegate = runtime
        gameView.colorPixelFormat = .bgra8Unorm
        gameView.depthStencilPixelFormat = .invalid
        gameView.preferredFramesPerSecond = 120
        if GameRuntime.needsReadableFramebuffer { gameView.framebufferOnly = false }
        platform.window = window
        platform.view = gameView
        window.contentView = gameView
        window.acceptsMouseMovedEvents = true
        window.delegate = self
        // invisible until the fullscreen transition lands — the user never sees
        // the windowed popup or the zoom animation, just a fade-in (the reveal
        // happens in windowDidEnterFullScreen, or after the retry loop gives up)
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(gameView)
        NSApp.activate(ignoringOtherApps: true)
        // launch straight into fullscreen (F11 toggles back). AppKit silently
        // drops toggleFullScreen during the launch transaction, so retry until
        // the window actually transitions.
        window.collectionBehavior.insert(.fullScreenPrimary)
        if windowed {
            window.alphaValue = 1
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.enterFullscreenAtLaunch()
            }
        }
        // a LAN game must keep ticking while the window is hidden (the view
        // stops drawing when occluded, and drawing is what drives ticks)
        let bg = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.runtime.backgroundTick() }
        RunLoop.main.add(bg, forMode: .common)

        runtime.start(drawableSize: gameView.drawableSize)
    }

    func applicationWillTerminate(_ notification: Notification) {
        runtime.willTerminate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Edit→Paste (Cmd-V): route pasteboard text into the focused screen field
    @objc func pasteText(_ sender: Any?) {
        if let s = platform.pasteboardString() { runtime.paste(s) }
    }

    /// AppKit refuses toggleFullScreen while the app is still activating
    /// (windowDidFailToEnterFullScreen fires and the window reverts), so the
    /// launch toggle re-checks until the transition actually completes.
    func windowDidEnterFullScreen(_ notification: Notification) {
        fsEntered = true
        NSAnimationContext.runAnimationGroup {
            $0.duration = 0.3
            window?.animator().alphaValue = 1
        }
    }
    private var fsEntered = false
    private var fsChecks = 0
    private func enterFullscreenAtLaunch() {
        guard let w = window, !fsEntered else { return }
        if fsChecks >= 5 {
            w.alphaValue = 1   // fullscreen never engaged: show windowed, don't stay invisible
            return
        }
        fsChecks += 1
        if !w.styleMask.contains(.fullScreen) { w.toggleFullScreen(nil) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.enterFullscreenAtLaunch()
        }
    }

    /// Cmd-Tab away: release every held key (keyUps go to the other app),
    /// give the system its cursor back (capture sets GLOBAL state that froze
    /// the cursor system-wide), and auto-pause
    /// (scripted windowed test runs keep playing in the background).
    func applicationDidResignActive(_ notification: Notification) {
        runtime?.didResignActive(autoPause: ProcessInfo.processInfo.environment["PEBBLE_WINDOWED"] == nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)

// minimal main menu: Cmd-Q quits, Cmd-V pastes into UI fields (seeds!),
// Window gets the standard entries
let mainMenu = NSMenu()
let appItem = NSMenuItem()
let appMenu = NSMenu()
appMenu.addItem(withTitle: "About Pebble",
                action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
appMenu.addItem(NSMenuItem.separator())
appMenu.addItem(withTitle: "Quit Pebble",
                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
appItem.submenu = appMenu
mainMenu.addItem(appItem)
let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
let editMenu = NSMenu(title: "Edit")
editMenu.addItem(withTitle: "Paste",
                 action: #selector(AppDelegate.pasteText(_:)), keyEquivalent: "v")
editItem.submenu = editMenu
mainMenu.addItem(editItem)
let winItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
let winMenu = NSMenu(title: "Window")
winMenu.addItem(withTitle: "Minimize",
                action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
winItem.submenu = winMenu
mainMenu.addItem(winItem)
app.mainMenu = mainMenu
app.windowsMenu = winMenu

app.run()
