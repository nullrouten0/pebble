// The seam between the shared game stack and each app shell (macOS AppKit,
// iOS UIKit). PebbleApp never imports a UI framework; anything that needs the
// window, the cursor, the pasteboard or the process goes through these hooks.

import Foundation

public protocol PlatformHooks: AnyObject {
    /// bundled asset path (logo.png, title-bg.png, the default pack zip)
    func resourcePath(_ name: String) -> String?

    /// a "Quit Game" button makes sense (false on iOS: apps don't quit)
    var canQuit: Bool { get }
    func quit()

    var supportsFullscreen: Bool { get }
    var isFullscreen: Bool { get }
    func toggleFullscreen()

    /// hide + lock the cursor for mouse-look (true) or give it back (false)
    func setPointerCaptured(_ captured: Bool)

    func pasteboardString() -> String?

    /// safe-area insets in drawable pixels (notch, home indicator, rounded corners)
    var safeAreaInsets: (top: Double, left: Double, bottom: Double, right: Double) { get }

    /// settings.maxFps changed (>= 250 means "unlimited" where the shell supports it)
    func applyMaxFps(_ maxFps: Int)

    /// the panel's top refresh rate when the frame rate is capped to it (iOS);
    /// nil where Settings offers "Unlimited" (macOS)
    var maxFrameRate: Int? { get }

    /// once a second: a status line the shell may show (the Mac window title)
    func showStatus(_ title: String)

    /// "Auto" render scale adapts to GPU load and heat (passively cooled
    /// devices); false = Auto means full resolution
    var adaptiveRenderScale: Bool { get }

    /// a text field / chat / sign wants typing: raise the on-screen keyboard
    /// (true) or dismiss it (false). Typed text comes back via InputRouter.
    func setTextInputActive(_ active: Bool)
}

public extension PlatformHooks {
    var canQuit: Bool { false }
    func quit() {}
    var supportsFullscreen: Bool { false }
    var isFullscreen: Bool { true }
    func toggleFullscreen() {}
    func pasteboardString() -> String? { nil }
    var safeAreaInsets: (top: Double, left: Double, bottom: Double, right: Double) { (0, 0, 0, 0) }
    func showStatus(_ title: String) {}
    var maxFrameRate: Int? { nil }
    func setTextInputActive(_ active: Bool) {}
    var adaptiveRenderScale: Bool { false }
}

/// where debug hooks (bot logs, photo booth, scripted shots) drop files: /tmp
/// on the Mac, where the scripts look; the app sandbox's tmp elsewhere
func debugOutputDir() -> String {
    #if os(macOS)
    return "/tmp"
    #else
    return (NSTemporaryDirectory() as NSString).standardizingPath
    #endif
}
