// The shared game stack every shell hosts: GameCore + renderer + UI + HUD +
// audio, the GameHost bridge between them, the frame body, and the PEBBLE_*
// test hooks. A shell owns the window/view and forwards draw, resize, input
// and lifecycle events here.

import Foundation
import MetalKit
import QuartzCore
import PebbleCore

// ---------------------------------------------------------------------------
// host bridge: GameCore ↔ UI stack / renderer / audio
// ---------------------------------------------------------------------------
final class HostBridge: GameHost {
    weak var app: GameRuntime?
    var ui: UIManager { app!.ui }
    var hud: HUD { app!.hud }
    var game: GameCore { app!.game }

    func hasScreen() -> Bool { app?.ui.hasScreen() ?? false }
    func screenPausesGame() -> Bool { app?.ui.current()?.pausesGame ?? false }

    func openScreen(_ kind: String, _ data: ScreenData?) {
        guard let app else { return }
        switch kind {
        case "crafting": ui.open(CraftingScreen(), game)
        case "inventory": ui.open(InventoryScreen(), game)
        case "creative": ui.open(CreativeScreen(), game)
        case "chest":
            if let be = data?.be {
                ui.open(ChestScreen(be, data?.title ?? "Chest", data?.other), game)
            }
        case "ender_chest":
            let p = game.player!
            ui.open(ChestScreen(items: { p.enderChest }, set: { p.enderChest[$0] = $1 },
                                count: p.enderChest.count, "Ender Chest"), game)
        case "furnace":
            if let be = data?.be { ui.open(FurnaceScreen(be), game) }
        case "brewing":
            if let be = data?.be { ui.open(BrewingScreen(be), game) }
        case "enchanting":
            ui.open(EnchantingScreen((data?.x ?? 0, data?.y ?? 0, data?.z ?? 0)), game)
        case "anvil":
            ui.open(AnvilScreen((data?.x ?? 0, data?.y ?? 0, data?.z ?? 0, data?.damage ?? 0)), game)
        case "grindstone": ui.open(GrindstoneScreen(), game)
        case "stonecutter": ui.open(StonecutterScreen(), game)
        case "smithing": ui.open(SmithingScreen(), game)
        case "beacon":
            if let be = data?.be { ui.open(BeaconScreen(be), game) }
        case "sign":
            ui.open(SignScreen(data?.be, (data?.x ?? 0, data?.y ?? 0, data?.z ?? 0)), game)
        case "toast":
            hud.showActionBar(data?.text ?? "")
        default:
            break
        }
        if ui.hasScreen() { app.input.releaseMouse() }
    }
    func openTrading(_ villager: Mob) {
        ui.open(TradingScreen(villager), game)
        app?.input.releaseMouse()
    }
    func openVehicleChest(_ kind: String, _ vehicle: Entity) {
        let title = kind == "boat_chest" ? "Chest Boat" : "Minecart with Chest"
        if let boat = vehicle as? Boat {
            ui.open(ChestScreen(vehicle: boat, title), game)
        } else if let cart = vehicle as? Minecart {
            ui.open(ChestScreen(vehicle: cart, title), game)
        }
        app?.input.releaseMouse()
    }
    func openChat(_ prefix: String) {
        let g = game
        ui.open(ChatScreen({ cmd in runCommand(g, cmd) }, prefix), g)
        app?.input.releaseMouse()
    }
    func openDeathScreen(_ message: String) {
        ui.open(DeathScreen(message), game)
    }
    func openPauseScreen() {
        ui.open(PauseScreen(), game)
        app?.input.releaseMouse()
    }
    func openTitleScreen() {
        ui.titlePhoto = app?.renderer.titleBgTex != nil; ui.titleLogo = app?.renderer.titleLogoTex != nil
        ui.open(TitleScreen(), game)
        app?.input.releaseMouse()
    }
    func closeAllScreens() { ui.closeAll(game) }
    func releasePointer() { app?.input.releaseMouse() }

    func showActionBar(_ text: String, _ time: Int) {
        hud.showActionBar(text)
        hud.actionBarTime = time
    }
    func pushChat(_ line: String) { Pebble_pushChat(line) }
    func pushToast(_ adv: AdvancementDef) { hud.pushToast(adv) }
    func setBossBars(_ bars: [BossBarInfo]) { hud.bossBars = bars }

    func playSound(_ name: String, _ x: Double, _ y: Double, _ z: Double, _ volume: Double, _ pitch: Double) {
        guard let app else { return }
        if name.hasPrefix("jukebox.play.") {
            app.audio.playDisc(name, x, y, z)
            return
        }
        app.audio.play(name, x, y, z, volume, pitch)
    }
    func playUI(_ name: String) { app?.audio.playUI(name) }
    func setAudioEnvironment(_ underwater: Bool, _ caveFactor: Double) {
        app?.audio.setEnvironment(underwater, caveFactor)
    }
    func setAudioListener(_ x: Double, _ y: Double, _ z: Double, _ yaw: Double) {
        app?.audio.setListener(x, y, z, yaw)
    }
    func tickMusic(_ mood: String, _ enabled: Bool) { app?.audio.tickMusic(mood, enabled) }
    func stopDisc() { app?.audio.stopDisc() }

    func addParticles(_ type: String, _ x: Double, _ y: Double, _ z: Double, _ count: Int, _ spread: Double, _ cell: Int) {
        guard let app, app.game.hasWorld() else { return }
        app.renderer?.particles.spawn(app.game.world, type, x, y, z, count, spread, cell: cell)
    }
    func spawnPrecipitation(_ kind: String, _ x: Double, _ y: Double, _ z: Double, _ groundY: Double) {
        guard let app, app.game.hasWorld() else { return }
        app.renderer?.particles.spawn(app.game.world, kind, x, y, z, 1, 0.1, groundY: groundY)
    }
    func uploadMesh(_ cx: Int, _ sy: Int, _ cz: Int, _ minY: Int, _ mesh: MeshOutput) {
        app?.renderer?.uploadMesh(cx, sy, cz, minY, mesh)
    }
    func removeChunkMeshes(_ cx: Int, _ cz: Int, _ sections: Int) {
        app?.renderer?.removeChunkMeshes(cx, cz, sections)
    }
    func clearAllSections() {
        app?.renderer?.clearAllSections()
    }
}

// pushChat lives in ScreensM at module scope; alias avoids name shadowing here
func Pebble_pushChat(_ line: String) { pushChat(line) }

/// screens reach the runtime (renderer for load progress, LAN join, relayout)
/// through this
weak var gRuntime: GameRuntime?

// ---------------------------------------------------------------------------
// runtime: game, renderer, UI, frame loop
// ---------------------------------------------------------------------------
public final class GameRuntime: NSObject, MTKViewDelegate {
    public let platform: PlatformHooks
    public let device: MTLDevice
    public private(set) var input: InputRouter!
    public private(set) var touch: TouchControls!
    var renderer: WorldRenderer!
    let host = HostBridge()
    var game: GameCore!
    var ui: UIManager!
    let hud = HUD()
    let audio = AudioEngineM()
    /// last drawable size seen (pixels) — re-layout without a resize event
    private(set) var drawableSize: CGSize = .zero
    private var lastFrame = CACurrentMediaTime()
    private var startTime = CACurrentMediaTime()
    private var fpsCounter = 0
    private var fpsTimer = 0.0
    private var fps = 0
    var bot: PhysicsBot?
    var booth: PhotoBooth?
    // test hook: PEBBLE_CMD="/tp 0 120 0;/time set 1000" runs once the world is up
    private var pendingCmds = ProcessInfo.processInfo.environment["PEBBLE_CMD"]
    private var pendingCmdDelay = 0
    // test hook: PEBBLE_MENU="Host LAN Game>Create New>Create & Host" clicks
    // menu buttons by label, one every half second (menu-flow testing)
    private var pendingMenu = ProcessInfo.processInfo.environment["PEBBLE_MENU"]?
        .components(separatedBy: ">").filter { !$0.isEmpty } ?? []
    private var pendingMenuDelay = 0
    // test hook: PEBBLE_SHOT="/tmp/x.png@300" captures the frame N frames after load
    private var shotQuitFrames = 0
    private var pendingShot: (path: String, frames: Int)? = {
        guard let v = ProcessInfo.processInfo.environment["PEBBLE_SHOT"] else { return nil }
        let parts = v.components(separatedBy: "@")
        return (parts[0], parts.count > 1 ? Int(parts[1]) ?? 240 : 240)
    }()

    /// capture hooks blit from the drawable, which framebufferOnly forbids
    public static var needsReadableFramebuffer: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["PEBBLE_SHOT"] != nil || env["PEBBLE_PHOTOBOOTH"] != nil
    }

    /// registries, renderer (atlas + pipelines) and the UI canvas
    public init(platform: PlatformHooks, device: MTLDevice) {
        self.platform = platform
        self.device = device
        super.init()
        gRuntime = self
        input = InputRouter(self)
        touch = TouchControls(self)
        let t0 = CFAbsoluteTimeGetCurrent()
        game = GameCore()
        game.host = host
        host.app = self
        game.netCommandRunner = { [weak self] guest, text in
            guard let self else { return [] }
            return runCommandAs(self.game, guest, text)
        }
        // test hook: PEBBLE_NAME=Bob plays as Bob (not saved to settings)
        if let n = ProcessInfo.processInfo.environment["PEBBLE_NAME"] { game.settings.playerName = n }
        print(String(format: "registries: %.0fms (%d blocks, %d items, %d biomes)",
                     (CFAbsoluteTimeGetCurrent() - t0) * 1000, blockDefs.count, itemDefs.count, BIOMES.count))

        let t1 = CFAbsoluteTimeGetCurrent()
        renderer = WorldRenderer(device: device)
        ui = UIManager(cv: UICanvas(device: device))
        print(String(format: "renderer: %.0fms (atlas + pipelines)", (CFAbsoluteTimeGetCurrent() - t1) * 1000))
    }

    /// once the view exists: audio, layout, resource packs, the title screen
    /// and the launch-time test hooks
    public func start(drawableSize size: CGSize) {
        audio.initEngine()
        audio.applyVolumes(game.settings.volumes)
        audio.onSubtitle = { [weak self] text in
            guard let self, self.game.settings.subtitles else { return }
            self.hud.pushSubtitle(text)
        }

        drawableSize = size
        ui.resize(Double(size.width), Double(size.height), game.settings.guiScale)

        // settings.resourcePacks holds USER packs only — the default pack
        // (Faithful base layer) is self-healing and force-applied inside
        // applyResourcePacks, so this always runs, even with no user packs.
        // older settings that listed the default explicitly migrate cleanly
        // (withDefaultPack dedupes it to the base slot).
        applyResourcePacks(game.settings.resourcePacks ?? [], game: game, renderer: renderer, ui: ui)

        ui.titlePhoto = renderer.titleBgTex != nil ; ui.titleLogo = renderer.titleLogoTex != nil
        ui.open(TitleScreen(), game)
        // test hook: jump straight to the world list (UI testing)
        if ProcessInfo.processInfo.environment["PEBBLE_WORLDS"] != nil {
            ui.open(WorldSelectScreen(), game)
        }

        // test hook: PEBBLE_MULTIPLAYER=1 opens the LAN browser at launch
        if ProcessInfo.processInfo.environment["PEBBLE_MULTIPLAYER"] != nil {
            ui.open(MultiplayerScreen(), game)
        }
        // test hook: PEBBLE_JOIN=127.0.0.1[:port] joins a LAN game at launch
        if let addr = ProcessInfo.processInfo.environment["PEBBLE_JOIN"] {
            let (h, port) = parseLANAddress(addr)
            beginJoin { $0.joinLAN(host: h, port: port) }
        }

        // test hook: skip the menus and jump straight into the latest world.
        // PEBBLE_NEWWORLD=<seed> creates a fresh world instead (worldgen testing)
        if ProcessInfo.processInfo.environment["PEBBLE_AUTOLOAD"] != nil {
            if let seedText = ProcessInfo.processInfo.environment["PEBBLE_NEWWORLD"] {
                game.createWorld(name: "WGTest-\(seedText)", seedText: seedText,
                                 mode: GameMode.survival, difficulty: 2)
            } else if let rec = game.listWorlds().sorted(by: { $0.lastPlayed > $1.lastPlayed }).first {
                game.loadWorld(rec.id)
            } else {
                game.createWorld(name: "New World", seedText: "", mode: GameMode.survival, difficulty: 2)
            }
            ui.open(LoadingScreen(), game)
            input.captureMouse()
            if ProcessInfo.processInfo.environment["PEBBLE_BOT"] != nil {
                bot = PhysicsBot(game: game)
            }
            if ProcessInfo.processInfo.environment["PEBBLE_PHOTOBOOTH"] != nil {
                booth = PhotoBooth(game: game, renderer: renderer)
            }
        }
    }

    // MARK: lifecycle

    /// process exit: flush the world, and tell LAN peers we're leaving
    public func willTerminate() {
        if game.hasWorld() {
            game.saveAndFlush(synchronous: true)
            if game.isNetworked {
                // tell guests / the host we're gone, and let that reach the wire
                game.exitToTitle()
                RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            }
        }
    }

    /// app lost focus: release every held key (keyUps go elsewhere), give the
    /// pointer back, and auto-pause like vanilla
    public func didResignActive(autoPause: Bool = true) {
        game?.clearInput()
        input?.releaseMouse()
        if autoPause, let game, let ui, game.hasWorld(), !ui.hasScreen() {
            ui.open(PauseScreen(), game)
        }
    }

    /// going to the background: write everything to disk now
    public func saveNow() {
        if game.hasWorld() { game.saveAndFlush(synchronous: true) }
    }

    /// the app went to the background / came back (iOS): silence the synth
    public func suspendAudio() { audio.suspend() }
    public func resumeAudio() { audio.resume() }

    /// true once settings.json exists — false means first launch, when a
    /// shell may apply a device preset
    public static var hasSavedSettings: Bool {
        FileManager.default.fileExists(atPath: vcSupportDir().appendingPathComponent("settings.json").path)
    }

    public enum DevicePreset { case tablet, phone }

    /// first-launch video defaults for passively cooled devices
    public func applyDevicePreset(_ preset: DevicePreset) {
        switch preset {
        case .tablet:
            game.settings.renderDistance = 8
            game.settings.shadows = true
        case .phone:
            game.settings.renderDistance = 6
            game.settings.shadows = false
        }
        game.settings.bloom = true
        game.settings.shader = nil
        game.settings.maxFps = 60
        game.applySettings()
    }

    /// leave whatever world we're in and start joining a LAN game
    func beginJoin(_ start: (GameCore) -> Void) {
        if game.hasWorld() { game.exitToTitle() }
        ui.closeAll(game)
        ui.open(TitleScreen(), game)
        start(game)
        ui.open(JoinScreen(), game)
        input.releaseMouse()
    }

    /// drive ticks from a timer when frames stop (window hidden) in a LAN game
    public func backgroundTick() {
        guard let game, game.isNetworked, game.hasWorld() else { return }
        let now = CACurrentMediaTime()
        if now - lastFrame < 0.2 { return }
        _ = game.frame(dtMs: (now - lastFrame) * 1000)
        lastFrame = now
    }

    /// pasted text into the focused screen field — the UI fields are
    /// canvas-drawn, so no system text path ever reaches them
    public func paste(_ s: String) {
        guard let game, let ui, let screen = ui.current(),
              screen.fields.contains(where: { $0.focused }) else { return }
        for ch in s where !ch.isNewline && (ch.asciiValue.map { $0 >= 32 } ?? true) {
            _ = screen.onChar(ui, game, String(ch))
        }
    }

    /// the shell's safe area changed (rotation, multitasking): re-read it
    public func safeAreaChanged() {
        if drawableSize.width > 0 { relayoutUI() }
    }

    /// GUI scale changed: lay the UI out again at the current size
    func relayoutUI() {
        ui.resize(Double(drawableSize.width), Double(drawableSize.height), game.settings.guiScale, relayout: game)
    }

    // MARK: MTKViewDelegate

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        drawableSize = size
        renderer.resize(Int(size.width), Int(size.height))
        ui.resize(Double(size.width), Double(size.height), game.settings.guiScale, relayout: game)
    }

    public func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        let dt = (now - lastFrame) * 1000
        lastFrame = now
        let timeSec = (now - startTime).truncatingRemainder(dividingBy: 1800)

        fpsTimer += dt
        fpsCounter += 1
        if fpsTimer >= 1000 {
            fps = fpsCounter
            fpsCounter = 0
            fpsTimer -= 1000
            let n = game.harvestMeshCounter()
            hud.debugInfo["fps"] = String(fps)
            hud.debugInfo["chunkUpdates"] = String(n)
            hud.debugInfo["sections"] = String(renderer.sections.count)
            hud.debugInfo["drawCalls"] = String(renderer.drawCalls)
            hud.debugInfo["mem"] = "n/a"
            audio.applyVolumes(game.settings.volumes)
            platform.applyMaxFps(game.settings.maxFps)
            if game.hasWorld(), let p = game.player {
                platform.showStatus(String(format: "Pebble — %d fps · %d sections · (%.0f, %.0f, %.0f)",
                                           fps, renderer.sections.count, p.x, p.y, p.z))
            } else {
                platform.showStatus("Pebble")
            }
        }

        guard let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor,
              let cmd = renderer.queue.makeCommandBuffer() else { return }

        if renderer.fbWidth == 0 {
            drawableSize = view.drawableSize
            renderer.resize(Int(view.drawableSize.width), Int(view.drawableSize.height))
            ui.resize(Double(view.drawableSize.width), Double(view.drawableSize.height), game.settings.guiScale, relayout: game)
        }

        renderer.tickTileAnimations(dtMs: dt)   // resource-pack .mcmeta frames
        renderer.flushAtlasUploads(cmd)         // staged slice blits, GPU-ordered

        runTestHooks()

        let enc: MTLRenderCommandEncoder
        // (frame() can end the world: a LAN host dropping us mid-frame)
        let partial = game.hasWorld() ? game.frame(dtMs: dt) : 0
        if game.hasWorld() {
            bot?.tick()
            booth?.tickBooth()
            renderer.particles.tick(game.world)
            let cam = game.camState(partial, timeSec: timeSec)
            enc = renderer.render(cmd: cmd, rpd: rpd, game: game, cam: cam, partial: partial, timeSec: timeSec)
        } else {
            enc = renderer.renderTitle(cmd: cmd, rpd: rpd)
        }

        // ---- UI pass ----
        ui.beginFrame()
        let screen = ui.current()
        if game.hasWorld() && (screen == nil || screen!.showHUD || !screen!.pausesGame) {
            hud.draw(ui, game, 0)
            if !(screen is ChatScreen) { drawChatOverlay(ui) }
        }
        screen?.draw(ui, game, 0)
        ui.endFrame()
        ui.cv.flush(enc, pipeline: renderer.uiPipeline)

        enc.endEncoding()
        renderer.captureFinalFrame(cmd, drawable.texture)
        cmd.present(drawable)
        cmd.commit()
    }

    /// PEBBLE_MENU / PEBBLE_CMD / PEBBLE_SHOT, advanced once per frame
    private func runTestHooks() {
        if !pendingMenu.isEmpty {
            pendingMenuDelay += 1
            if pendingMenuDelay > 30 {
                pendingMenuDelay = 0
                let label = pendingMenu.removeFirst()
                if let b = ui.current()?.buttons.first(where: { $0.label == label && $0.enabled }) {
                    print("[menu] clicked \(label)")
                    b.onClick()
                } else {
                    print("[menu] no button \(label) on \(ui.current().map { String(describing: type(of: $0)) } ?? "nil")")
                }
                fflush(stdout)
            }
        }

        if let cmds = pendingCmds, game.hasWorld(), let p = game.player {
            pendingCmdDelay += 1
            if pendingCmdDelay > 90 {
                if p.dead { game.respawnPlayer() }
                pendingCmds = nil
                let list = cmds.components(separatedBy: ";").filter { !$0.isEmpty }
                for (i, c) in list.enumerated() {
                    // "#down B" / "#up B" press / release mouse button B (0 left, 2 right),
                    // "#slot N" picks hotbar slot N (1-9) — scripted interaction tests
                    if c.hasPrefix("#down") || c.hasPrefix("#up") {
                        let b = Int(c.split(separator: " ").last ?? "") ?? 0
                        if c.hasPrefix("#down") { game.mouseDown(b) } else { game.mouseUp(b) }
                        continue
                    }
                    // "#type text" / "#uikey Key" go to the open screen (sign text, fields)
                    if c.hasPrefix("#type ") {
                        print("[cmd] \(c) → screen \(ui.current().map { String(describing: type(of: $0)) } ?? "none")")
                        for ch in c.dropFirst(6) { _ = ui.current()?.onChar(ui, game, String(ch)) }
                        continue
                    }
                    if c.hasPrefix("#uikey ") {
                        let k = String(c.dropFirst(7))
                        if k == "Escape" { ui.closeTop(game) } else { _ = ui.current()?.onKey(ui, game, k) }
                        continue
                    }
                    if c.hasPrefix("#key") {
                        let code = String(c.split(separator: " ").last ?? "")
                        game.keyDown(code, now: CACurrentMediaTime() * 1000)
                        game.keyUp(code)
                        continue
                    }
                    if c.hasPrefix("#slot") {
                        game.player.selectedSlot = max(0, min(8, (Int(c.split(separator: " ").last ?? "") ?? 1) - 1))
                        continue
                    }
                    // "#waitguests N" holds the rest until N LAN guests are in
                    if c.hasPrefix("#waitguests") {
                        let n = Int(c.dropFirst(11).trimmingCharacters(in: .whitespaces)) ?? 1
                        if game.lanGuests.count < n {
                            pendingCmds = list[i...].joined(separator: ";")
                            pendingCmdDelay = 60
                            break
                        }
                        continue
                    }
                    // "#wait N" defers the rest by N frames
                    if c.hasPrefix("#wait") {
                        pendingCmds = list[(i + 1)...].joined(separator: ";")
                        pendingCmdDelay = 90 - (Int(c.dropFirst(5).trimmingCharacters(in: .whitespaces)) ?? 60)
                        break
                    }
                    let before = chatLog.count
                    runCommand(game, c.trimmingCharacters(in: .whitespaces))
                    for m in chatLog.suffix(max(0, chatLog.count - before)) { print("[cmd] \(c) → \(m.text)") }
                    fflush(stdout)
                }
            }
        }
        if let shot = pendingShot, game.hasWorld() || renderer.captureWithUI, pendingCmds == nil {
            hud.hideGui = !renderer.captureWithUI
            pendingShot = (shot.path, shot.frames - 1)
            if shot.frames <= 0 {
                renderer.requestCapture(path: shot.path)
                pendingShot = nil
                hud.hideGui = false
                print("[shot] captured \(shot.path)")
                fflush(stdout)
                // scripted-shot runs quit on their own — leave a beat for the
                // async blit + PNG write to land before terminating
                shotQuitFrames = 120
            }
        }
        if shotQuitFrames > 0 {
            shotQuitFrames -= 1
            if shotQuitFrames == 0 { platform.quit() }
        }
    }
}
