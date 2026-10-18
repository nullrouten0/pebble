// PlatformHooks for UIKit: bundle resources, pointer lock, pasteboard,
// safe area, frame-rate cap, sharing worlds.

import UIKit
import MetalKit
import UniformTypeIdentifiers
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
    func openURL(_ url: String) { if let u = URL(string: url) { UIApplication.shared.open(u) } }

    var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    func setKeepAwake(_ on: Bool) {
        if UIApplication.shared.isIdleTimerDisabled != on { UIApplication.shared.isIdleTimerDisabled = on }
    }

    var battery: (level: Double, charging: Bool)? {
        let d = UIDevice.current
        guard d.isBatteryMonitoringEnabled, d.batteryLevel >= 0 else { return nil }
        return (Double(d.batteryLevel), d.batteryState == .charging || d.batteryState == .full)
    }
    func setBatteryMonitoring(_ on: Bool) { UIDevice.current.isBatteryMonitoringEnabled = on }

    func setTextInputActive(_ active: Bool) { controller?.setTextInput(active) }

    var safeAreaInsets: (top: Double, left: Double, bottom: Double, right: Double) {
        guard let v = controller?.view else { return (0, 0, 0, 0) }
        let s = Double(v.contentScaleFactor)
        let i = v.safeAreaInsets
        return (Double(i.top) * s, Double(i.left) * s, Double(i.bottom) * s, Double(i.right) * s)
    }

    /// passively cooled devices: cap at the panel rate, and treat the Mac's
    /// "unlimited" setting as just that
    var adaptiveRenderScale: Bool { true }

    var maxFrameRate: Int? { controller?.view.window?.screen.maximumFramesPerSecond ?? 60 }

    func applyMaxFps(_ maxFps: Int) {
        guard let view = controller?.mtkView else { return }
        let panel = view.window?.screen.maximumFramesPerSecond ?? 60
        view.preferredFramesPerSecond = maxFps >= 250 ? panel : min(max(30, maxFps), panel)
    }

    // sharing worlds: the share sheet (AirDrop, Messages, Mail, Save to
    // Files…) and the Files picker for Import
    var canShareFiles: Bool { true }

    func shareFile(_ path: String, from rect: (x: Double, y: Double, w: Double, h: Double)) {
        guard let c = controller, let v = c.mtkView else { return }
        let sheet = UIActivityViewController(activityItems: [URL(fileURLWithPath: path)], applicationActivities: nil)
        let s = v.contentScaleFactor
        sheet.popoverPresentationController?.sourceView = v
        sheet.popoverPresentationController?.sourceRect = CGRect(x: rect.x / s, y: rect.y / s, width: rect.w / s, height: rect.h / s)
        c.present(sheet, animated: true)
    }

    func pickFile(extensions: [String], _ done: @escaping (String?) -> Void) {
        guard let c = controller else { return done(nil) }
        c.pickFile(types: extensions.compactMap { UTType(filenameExtension: $0) }, done)
    }
}
