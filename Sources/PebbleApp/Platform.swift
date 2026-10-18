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

    /// a phone: the UI zooms up where the 240-unit menu height isn't needed
    /// (in-world, inventory screens) so touch targets reach finger size
    var isPhone: Bool { get }

    /// keep the screen from dimming and locking (true while in a world)
    func setKeepAwake(_ on: Bool)

    /// battery charge 0…1 and whether it's charging; nil without a battery
    /// or while monitoring is off (the power bench turns it on)
    var battery: (level: Double, charging: Bool)? { get }
    func setBatteryMonitoring(_ on: Bool)

    /// open a web page in the system browser (the texture credit's link)
    func openURL(_ url: String)

    /// the system can send a file to other apps and devices, and let the
    /// player pick one to open (World Select's Share and Import)
    var canShareFiles: Bool { get }
    /// offer a file: the system share sheet (AirDrop, Messages, Mail, Save to
    /// Files…). `from` is the button it came from, in drawable pixels: an
    /// iPad's popover points there
    func shareFile(_ path: String, from rect: (x: Double, y: Double, w: Double, h: Double))
    /// let the player pick a file with one of `extensions`; nil if cancelled.
    /// The path is readable until `done` returns
    func pickFile(extensions: [String], _ done: @escaping (String?) -> Void)
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
    var isPhone: Bool { false }
    func setKeepAwake(_ on: Bool) {}
    var battery: (level: Double, charging: Bool)? { nil }
    func setBatteryMonitoring(_ on: Bool) {}
    var canShareFiles: Bool { false }
    func shareFile(_ path: String, from rect: (x: Double, y: Double, w: Double, h: Double)) {}
    func pickFile(extensions: [String], _ done: @escaping (String?) -> Void) { done(nil) }
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
