// PlatformHooks for UIKit: bundle resources, pointer lock, pasteboard,
// safe area, frame-rate cap.

import UIKit
import MetalKit
import PebbleApp

final class IOSPlatform: PlatformHooks {
    weak var controller: GameViewController?
    private(set) var pointerCaptured = false

    func resourcePath(_ name: String) -> String? {
        guard let rp = Bundle.main.resourcePath else { return nil }
        let p = rp + "/" + name
        return FileManager.default.fileExists(atPath: p) ? p : nil
    }

    /// in-world with no screen open: lock the hardware pointer for mouse-look
    /// (iPadOS honors this only for a full-screen, frontmost app)
    func setPointerCaptured(_ captured: Bool) {
        pointerCaptured = captured
        controller?.setNeedsUpdateOfPrefersPointerLocked()
    }

    func pasteboardString() -> String? { UIPasteboard.general.string }

    var safeAreaInsets: (top: Double, left: Double, bottom: Double, right: Double) {
        guard let v = controller?.view else { return (0, 0, 0, 0) }
        let s = Double(v.contentScaleFactor)
        let i = v.safeAreaInsets
        return (Double(i.top) * s, Double(i.left) * s, Double(i.bottom) * s, Double(i.right) * s)
    }

    /// passively cooled devices: cap at the panel rate, and treat the Mac's
    /// "unlimited" setting as just that
    var maxFrameRate: Int? { controller?.view.window?.screen.maximumFramesPerSecond ?? 60 }

    func applyMaxFps(_ maxFps: Int) {
        guard let view = controller?.mtkView else { return }
        let panel = view.window?.screen.maximumFramesPerSecond ?? 60
        view.preferredFramesPerSecond = maxFps >= 250 ? panel : min(max(30, maxFps), panel)
    }
}
