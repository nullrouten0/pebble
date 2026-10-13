// GameCore — the simulation orchestrator (the app target owns rendering
// and UI; everything sim-side lives here, ticking in frozen order). Chunk
// gen/meshing/saves run on GCD queues, persistence goes through SaveDB,
// and input + screens reach the app through the GameHost protocol.

import Foundation

// =============================================================================
// Constants (the frozen baseline)
// =============================================================================
public let TICK_MS = 1000.0 / 20.0
public let REACH_SURVIVAL = 4.5
public let REACH_CREATIVE = 5.0
public let ATTACK_REACH = 3.0

let SAVE_INTERVAL_TICKS = 1200          // 60 s autosave
let GEN_RADIUS_PAD = 1                  // generate one ring beyond render distance
// ~2 jobs per core keeps the gen queue fed across the main-thread hand-off
// (capped at 32 on big Macs; 20 on a 10-core iPad, 12 on a 6-core iPhone)
let MAX_GEN_INFLIGHT = max(8, min(32, ProcessInfo.processInfo.activeProcessorCount * 2))
let MAX_MESH_INFLIGHT = 26
let LIGHT_BUDGET_MS = 4.0               // seam-stitch time budget per frame

/// item-billboard projectiles (the app renders these as sprites)
/// tools that act once per click, never on held-use repeat
let ONE_SHOT_TOOLS: Set<String> = ["wall_builder", "box_builder", "quarry_charge", "infinity_wipe"]
/// heavy world tools a LAN guest doesn't predict locally — the host runs them
let HOST_ONLY_TOOLS: Set<String> = ["bazooka", "void_bomb", "quarry_charge", "wall_builder", "box_builder", "infinity_wipe"]

public let SPRITE_TYPES: Set<String> = [
    "snowball", "egg", "ender_pearl", "xp_bottle", "thrown_potion", "firework",
    "eye_of_ender", "fishing_bobber", "wither_skull", "dragon_fireball", "fireball",
    "shulker_bullet", "llama_spit", "rocket", "void_bomb",
]
/// entities that tick regardless of sim distance (bosses roam the whole arena;
/// rockets and void bombs outfly it and would hang in the air)
let ALWAYS_TICK: Set<String> = ["ender_dragon", "wither", "warden", "end_crystal", "eye_of_ender", "lightning",
                                "rocket", "void_bomb"]

// =============================================================================
// Load-path profiler (PEBBLE_PROF=1) — aggregates per-stage wall time
// =============================================================================
public final class LoadProf {
    public static let shared = LoadProf()
    public let enabled = ProcessInfo.processInfo.environment["PEBBLE_PROF"] != nil
    private var lock = NSLock()
    private var buckets: [String: (count: Int, ms: Double)] = [:]
    private var lastPrint = CFAbsoluteTimeGetCurrent()

    @inline(__always)
    public func time<T>(_ name: String, _ body: () -> T) -> T {
        if !enabled { return body() }
        let t0 = CFAbsoluteTimeGetCurrent()
        let r = body()
        let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        lock.lock()
        let b = buckets[name] ?? (0, 0)
        buckets[name] = (b.count + 1, b.ms + ms)
        lock.unlock()
        return r
    }
    public func tickPrint() {
        guard enabled else { return }
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastPrint < 2 { return }
        lastPrint = now
        lock.lock()
        let snap = buckets
        lock.unlock()
        let line = snap.sorted { $0.value.ms > $1.value.ms }
            .map { String(format: "%@ %.0fms/%d(%.1f)", $0.key, $0.value.ms, $0.value.count, $0.value.ms / Double(max(1, $0.value.count))) }
            .joined(separator: "  ")
        print("[prof] " + line)
        fflush(stdout)
    }
}

// =============================================================================
// Construction-pattern detection (golems, wither)
// =============================================================================
func tryBuildGolem(_ world: World, _ x: Int, _ y: Int, _ z: Int) {
    // snow golem: pumpkin on 2 snow blocks
    if world.getBlockId(x, y - 1, z) == Int(B.snow_block) && world.getBlockId(x, y - 2, z) == Int(B.snow_block) {
        world.setBlock(x, y, z, 0)
        world.setBlock(x, y - 1, z, 0)
        world.setBlock(x, y - 2, z, 0)
        spawnMob(world, "snow_golem", Double(x) + 0.5, Double(y - 2), Double(z) + 0.5, SpawnOpts(persistent: true))
        world.hooks.addParticles("block", Double(x) + 0.5, Double(y - 1) + 0.5, Double(z) + 0.5, 20, 0.6, Int(cell(B.snow_block)))
        return
    }
    // iron golem: T of iron blocks below pumpkin
    if world.getBlockId(x, y - 1, z) != Int(B.iron_block) || world.getBlockId(x, y - 2, z) != Int(B.iron_block) { return }
    for (ax, az) in [(1, 0), (0, 1)] {
        if world.getBlockId(x - ax, y - 1, z - az) == Int(B.iron_block) && world.getBlockId(x + ax, y - 1, z + az) == Int(B.iron_block) {
            world.setBlock(x, y, z, 0)
            world.setBlock(x, y - 1, z, 0)
            world.setBlock(x, y - 2, z, 0)
            world.setBlock(x - ax, y - 1, z - az, 0)
            world.setBlock(x + ax, y - 1, z + az, 0)
            // (baseline passes playerMade:true into the loose data bag; nothing reads it)
            spawnMob(world, "iron_golem", Double(x) + 0.5, Double(y - 2), Double(z) + 0.5, SpawnOpts(persistent: true))
            world.hooks.playSound("block.anvil.land", Double(x), Double(y), Double(z), 0.6, 1.2)
            return
        }
    }
}

func tryBuildWither(_ world: World, _ x: Int, _ y: Int, _ z: Int) {
    func isSoul(_ id: Int) -> Bool { id == Int(B.soul_sand) || id == Int(B.soul_soil) }
    func isSkull(_ bx: Int, _ by: Int, _ bz: Int) -> Bool { world.getBlockId(bx, by, bz) == Int(B.wither_skeleton_skull) }
    for (ax, az) in [(1, 0), (0, 1)] {
        // the skull just placed can be any of the three top positions
        for off in -1...1 {
            let cx = x - off * ax, cz = z - off * az
            if !isSkull(cx - ax, y, cz - az) || !isSkull(cx, y, cz) || !isSkull(cx + ax, y, cz + az) { continue }
            if !isSoul(world.getBlockId(cx, y - 1, cz)) || !isSoul(world.getBlockId(cx - ax, y - 1, cz - az)) ||
                !isSoul(world.getBlockId(cx + ax, y - 1, cz + az)) || !isSoul(world.getBlockId(cx, y - 2, cz)) { continue }
            // clear the structure
            for (dx, dy, dz) in [(-ax, 0, -az), (0, 0, 0), (ax, 0, az), (-ax, -1, -az), (0, -1, 0), (ax, -1, az), (0, -2, 0)] {
                world.setBlock(cx + dx, y + dy, cz + dz, 0)
            }
            let w = spawnMob(world, "wither", Double(cx) + 0.5, Double(y - 2), Double(cz) + 0.5, nil)
            if w != nil { world.hooks.playSound("entity.wither.spawn", Double(cx), Double(y), Double(cz), 8, 1) }
            return
        }
    }
}

// =============================================================================
// Host surface — the app implements this (screens, HUD, audio, renderer)
// =============================================================================
public struct BossBarInfo {
    public let name: String
    public let progress: Double
    public let color: String
    public init(name: String, progress: Double, color: String) {
        self.name = name
        self.progress = progress
        self.color = color
    }
}

public protocol GameHost: AnyObject {
    // screens
    func hasScreen() -> Bool
    func screenPausesGame() -> Bool
    func openScreen(_ kind: String, _ data: ScreenData?)
    func openTrading(_ villager: Mob)
    func openVehicleChest(_ kind: String, _ vehicle: Entity)
    func openChat(_ prefix: String)
    func openDeathScreen(_ message: String)
    func openPauseScreen()
    func openTitleScreen()
    func closeAllScreens()
    func releasePointer()
    // HUD / chat
    func showActionBar(_ text: String, _ time: Int)
    func pushChat(_ line: String)
    func pushToast(_ adv: AdvancementDef)
    func setBossBars(_ bars: [BossBarInfo])
    // audio
    func playSound(_ name: String, _ x: Double, _ y: Double, _ z: Double, _ volume: Double, _ pitch: Double)
    func playUI(_ name: String)
    func setAudioEnvironment(_ underwater: Bool, _ caveFactor: Double)
    func setAudioListener(_ x: Double, _ y: Double, _ z: Double, _ yaw: Double)
    func tickMusic(_ mood: String, _ enabled: Bool)
    func stopDisc()
    // particles (count already scaled by the particles setting)
    func addParticles(_ type: String, _ x: Double, _ y: Double, _ z: Double, _ count: Int, _ spread: Double, _ cell: Int)
    func spawnPrecipitation(_ kind: String, _ x: Double, _ y: Double, _ z: Double, _ groundY: Double)
    // renderer
    func uploadMesh(_ cx: Int, _ sy: Int, _ cz: Int, _ minY: Int, _ mesh: MeshOutput)
    func removeChunkMeshes(_ cx: Int, _ cz: Int, _ sections: Int)
    func clearAllSections()
}

/// interpolated camera for the renderer — reference implementation CameraState
public struct CamState {
    public var x = 0.0, y = 0.0, z = 0.0
    public var yaw = 0.0, pitch = 0.0
    public var fov = 70.0
    public var underwater = false
    public var underLava = false
    public var powderSnow = false
    public var portalWarp = 0.0
    public var nightVision = 0.0
    public var darkness = 0.0
    public var blindness = 0.0
    public init() {}
}

// =============================================================================
// Streaming bookkeeping keys
// =============================================================================
struct SectionPos: Hashable {
    let cx: Int, sy: Int, cz: Int
}
struct DimSection: Hashable {
    let dim: Int
    let pos: SectionPos
}
struct DimChunk: Hashable {
    let dim: Int
    let key: Int64
}
final class MeshJobState {
    var dirtyAgain = false
}

// =============================================================================
// The Game
// =============================================================================
public final class GameCore {
    public weak var host: GameHost?
    public let db = SaveDB()
    public var settings: Settings
    public var keybinds: [String: String]

    // world state
    public var worlds: [Dim: World] = [:]
    public var dim: Dim = .overworld
    public var player: Player!
    public var worldRec: WorldRecord?
    public var advancements = AdvancementTracker()
    public private(set) var inWorld = false
    public private(set) var paused = false

    // streaming
    private var genInFlight = Set<DimChunk>()
    /// keys of chunks that exist on disk — fresh chunks skip the read entirely
    private var savedChunkKeys = Set<String>()
    /// keys whose DB record holds full block data — an unload rewrite of these
    /// must emit a full record again or the blocks are lost (entity-only stubs
    /// REPLACE the row)
    private var savedFullKeys = Set<String>()
    /// chunks awaiting initial lighting, processed under a per-frame budget
    private var lightQueue: [Dim: Set<Int64>] = [:]
    private var dirtySections: [Dim: Set<SectionPos>] = [:]
    /// sections whose neighborhood isn't ready — parked so the per-frame dirty
    /// scan doesn't rescan the streaming frontier forever; retried once per second
    private var stalledSections: [Dim: Set<SectionPos>] = [:]
    /// chunks loaded (for a LAN guest) beyond our own sight: not meshed, or
    /// their meshes freed, until we come within range again
    private var unmeshedChunks: [Dim: Set<Int64>] = [:]
    /// the chunk we stood in at the last mesh-range sweep
    private var meshCenter: (dim: Dim, cx: Int, cz: Int)?
    private var meshJobs: [DimSection: MeshJobState] = [:]
    public private(set) var meshedThisSecond = 0
    public var lastChunkUpdates = 0
    /// unload records awaiting the once-per-second batched write
    private var pendingChunkSaves: [String: ChunkRecord] = [:]

    private let genQueue = DispatchQueue(label: "pebble.gen", qos: .userInitiated, attributes: .concurrent)
    private let meshQueue = DispatchQueue(label: "pebble.mesh", qos: .userInitiated, attributes: .concurrent)
    private let saveQueue = DispatchQueue(label: "pebble.save", qos: .utility)

    // input
    private var keys = Set<String>()
    private var leftDown = false
    private var rightDown = false
    private var useCooldown = 0
    private var breakCooldown = 0
    /// creative dig time when settings.creativeBreakDelay is unset: a short
    /// visible erode, so you see the block you're on before it breaks
    /// (Options → Controls → Creative Dig sets it, down to instant)
    public var creativeBreakDelayDefault = 0.4
    /// seconds a creative-mode block takes to break (0 = instant)
    public var creativeBreakDelay: Double { settings.creativeBreakDelay ?? creativeBreakDelayDefault }

    // infinity wipe (Systems/InfinityWipe.swift)
    /// every wipe fired in this world, saved with it
    private var wipes: [WipeZone] = []
    /// shockwaves still rolling out: index into `wipes`, front radius
    private var wipeFronts: [(zone: Int, r: Double)] = []
    /// player entity id → world time the wipe was armed
    private var wipeArmedAt: [Int: Int] = [:]
    /// chunks a rising mountain still needs, kept loaded until it's done
    private var mountainPins: [(job: MountainJob, keys: Set<Int64>)] = []
    private var lastLightHealTick = -1
    private var lastSlot = 0
    public var heldNameTime = 0
    public var targetedBlock: (x: Int, y: Int, z: Int, cell: Int)?
    public var perspective = 0          // 0 first, 1 back, 2 front
    private var sprintHeld = false
    /// analog movement from a stick or touch pad (forward +1, right +1, each
    /// -1…1), added to the keyboard intent; nil = keyboard only
    public var analogMove: (forward: Double, right: Double)? = nil
    private var lastJumpPress = 0.0
    private var lastForwardPress = 0.0

    // loop
    private var accumulator = 0.0
    private var ticksSinceSave = 0

    // bookkeeping for vanilla feel — bob advances per TICK (frame-rate
    // independent) and camState interpolates; mutating it per frame made the
    // camera shake violently once the fps cap was lifted
    private var bobPhase = 0.0
    private var prevBobPhase = 0.0
    private var bobAmp = 0.0
    private var prevBobAmp = 0.0
    private var fovScale = 1.0
    private var prevFovScale = 1.0
    public private(set) var portalWarp = 0.0
    private var dragonSpawned = false
    private var brushTicks = 0
    private var deathScreenShown = false
    /// a portal/respawn chunk-load is in flight — player is held in place
    private var traveling = false
    /// player is frozen because the chunk under them hasn't streamed in yet
    private var heldForChunks = false
    public private(set) var musicMood = "menu"

    // LAN multiplayer
    public private(set) var netHost: NetHost?
    public private(set) var netClient: NetClient?
    /// the app runs guests' world commands (/fill, /place, /undo…) as their
    /// player and returns the chat lines they produced
    public var netCommandRunner: ((Player, String) -> [String])?
    /// shown to the joining screen / title when a LAN session ends
    public private(set) var netEndMessage: String?
    /// playing in someone else's LAN game
    public var isGuest: Bool { netClient != nil }
    /// hosting or visiting — the world never pauses
    public var isNetworked: Bool { netHost != nil || netClient != nil }
    public var playerName: String {
        if let n = settings.playerName?.trimmingCharacters(in: .whitespaces), !n.isEmpty { return n }
        let full = NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
        return full.isEmpty ? "Player" : String(full.prefix(16))
    }

    public init() {
        settings = loadSettings()
        keybinds = loadKeybinds()
        // registry boot, in frozen order
        registerAllBlocks()
        registerAllItems()
        registerAllBiomes()
        registerAllRecipes()
        registerAllLootTables()
        registerAllEntities()
        registerAllSystems()
        for d in [Dim.overworld, .nether, .end] {
            dirtySections[d] = []
            lightQueue[d] = []
        }
        onPlacedHandlers[Int(B.carved_pumpkin)] = { w, x, y, z, _ in tryBuildGolem(w, x, y, z) }
        onPlacedHandlers[Int(B.wither_skeleton_skull)] = { w, x, y, z, _ in tryBuildWither(w, x, y, z) }
        bindCrystalDestroyed { crystal, _ in
            let dragon = crystal.world.entities.first {
                ($0 as? Entity)?.type == "ender_dragon" && !$0.dead
            } as? EnderDragon
            if let dragon {
                _ = dragon.hurt(10, .explosion)
                dragon.pathAngle += 1.5
            }
        }
        // screen-opening hooks fired from entity interactions
        bindOpenTrading { [weak self] player, villager in
            guard let self, player === self.player else { return }
            self.host?.openTrading(villager)   // "What a Deal!" waits for an actual trade
        }
        openContainerScreenFn = { [weak self] player, kind, vehicle in
            guard let self, player === self.player else { return }
            self.host?.openVehicleChest(kind, vehicle)
        }
    }

    // ===========================================================================
    // GameUI / MenuHost surface
    // ===========================================================================
    public var world: World { worlds[dim]! }
    public func hasWorld() -> Bool { inWorld }

    public func playUISound(_ name: String) {
        host?.playUI(name)
    }

    public func advance(_ id: String) {
        if !inWorld { return }
        if advancements.grant(id) {
            playUISound("ui.toast.challenge_complete")
        }
    }

    public func applySettings() {
        saveSettings(settings)
        saveKeybinds(keybinds)
    }

    /// the top of a column, past air and plants, is solid ground (not water,
    /// lava or a waterlogged block)
    private func isDryColumn(_ w: World, _ x: Int, _ z: Int) -> Bool {
        var y = w.info.minY + w.info.height - 1
        while y > w.info.minY {
            let c = UInt16(truncatingIfNeeded: w.getBlock(x, y, z))
            if isWaterlogged(c) || isLavaCell(c) { return false }
            let id = Int(c >> 4)
            if id != 0 && blockDefs[id].solid { return true }
            y -= 1
        }
        return false
    }

    /// The world spawn was picked from a terrain estimate, which can put it
    /// in a lake or ocean the real terrain has there — and surfaceY looks
    /// through water, so players landed on the sea floor. Move it to the
    /// nearest dry land (rings every 4 blocks out to 64) and keep it.
    func settleSpawn(_ w: World) {
        guard !w.isRemote, var rec = worldRec else { return }
        let sx = Int(w.spawnX.rounded(.down)), sz = Int(w.spawnZ.rounded(.down))
        if isDryColumn(w, sx, sz) { return }
        for r in stride(from: 4, through: 64, by: 4) {
            var ring: [(Int, Int)] = []
            for d in stride(from: -r, through: r, by: 4) {
                ring += [(d, -r), (d, r)]
                if abs(d) != r { ring += [(-r, d), (r, d)] }
            }
            for (dx, dz) in ring {
                let x = sx + dx, z = sz + dz
                ensureChunksLoaded(w, floorDiv(x, 16), floorDiv(z, 16), 0)
                guard isDryColumn(w, x, z) else { continue }
                let y = w.surfaceY(x, z)   // the first air, as createWorld sets it
                for ww in worlds.values {
                    ww.spawnX = Double(x); ww.spawnY = Double(y); ww.spawnZ = Double(z)
                }
                rec.spawnX = x; rec.spawnY = y; rec.spawnZ = z
                worldRec = rec
                db.putWorld(rec)
                ensureChunksLoaded(w, floorDiv(x, 16), floorDiv(z, 16), 1)
                return
            }
        }
    }

    public func respawnPlayer() {
        if traveling { return }
        traveling = true
        defer { traveling = false }
        let p = player!
        deathScreenShown = false
        // respawn at bed / anchor / world spawn
        var dest: (Double, Double, Double)? = nil
        var destDim = Dim(rawValue: p.spawnDim) ?? .overworld
        if let sp = p.spawnPoint {
            let w = worlds[destDim]!
            ensureChunksLoaded(w, floorDiv(sp.0, 16), floorDiv(sp.2, 16), 1)
            let (sx, sy, sz) = sp
            let id = w.getBlockId(sx, sy, sz)
            let def = blockDefs[id]
            if SHAPE_OF[id] == Shape.bed.rawValue || def.name == "respawn_anchor" {
                if def.name == "respawn_anchor" {
                    let charge = w.getMeta(sx, sy, sz)
                    if charge > 0 {
                        w.setBlock(sx, sy, sz, Int(cell(UInt16(id), charge - 1)))
                        dest = (Double(sx) + 0.5, Double(sy + 1), Double(sz) + 0.5)
                    }
                } else {
                    dest = (Double(sx) + 0.5, Double(sy) + 0.6, Double(sz) + 0.5)
                }
            }
        }
        if dest == nil && !isGuest {
            destDim = .overworld
            let w = worlds[.overworld]!
            ensureChunksLoaded(w, floorDiv(Int(w.spawnX), 16), floorDiv(Int(w.spawnZ), 16), 1)
            settleSpawn(w)
            dest = (w.spawnX + 0.5, Double(w.surfaceY(Int(w.spawnX), Int(w.spawnZ))), w.spawnZ + 0.5)
        }
        if isGuest {
            // a guest respawns in the host's dimension, at its bed if that's
            // loaded here, else at world spawn (chunks stream in under it)
            if destDim != dim || dest == nil {
                let w = world
                dest = (w.spawnX + 0.5, w.spawnY + 1, w.spawnZ + 0.5)
                if w.isLoadedAt(Int(w.spawnX), Int(w.spawnZ)) {
                    dest!.1 = Double(w.surfaceY(Int(w.spawnX), Int(w.spawnZ)))
                }
            }
            destDim = dim
        }
        if destDim != dim { moveToDimension(destDim) }
        p.respawn()
        p.setPos(dest!.0, dest!.1, dest!.2)
        p.insidePortalKind = nil
        p.portalTicks = 0
    }

    public func exitToTitle() {
        if inWorld { saveAndFlush(synchronous: true) }
        if let nc = netClient {
            nc.disconnect()
            netClient = nil
        }
        stopHosting()
        inWorld = false
        worldRec = nil
        dragonSpawned = false
        deathScreenShown = false
        worlds.removeAll()
        for d in dirtySections.keys { dirtySections[d]!.removeAll() }
        stalledSections.removeAll()
        unmeshedChunks.removeAll()
        meshCenter = nil
        for d in lightQueue.keys { lightQueue[d]!.removeAll() }
        meshJobs.removeAll()
        genInFlight.removeAll()
        savedChunkKeys.removeAll()
        savedFullKeys.removeAll()
        clearEntityTimeouts()
        host?.clearAllSections()
        host?.setBossBars([])
        host?.stopDisc()
        host?.releasePointer()
        host?.closeAllScreens()
        host?.openTitleScreen()
    }

    // ---- MenuHost ----
    public func listWorlds() -> [WorldRecord] {
        db.listWorlds()
    }

    public func createWorld(name: String, seedText: String, mode: Int, difficulty: Int) {
        let trimmed = seedText.trimmingCharacters(in: .whitespaces)
        var seed: Int32
        if trimmed.isEmpty {
            seed = Int32.random(in: 0..<0x7fffffff)
        } else if trimmed.range(of: "^-?\\d+$", options: .regularExpression) != nil {
            seed = wrapToInt32(Double(trimmed) ?? 0)
        } else {
            // (seed * 31 + ch.charCodeAt(0)) | 0 over code points
            seed = 0
            for unit in trimmed.utf16 {
                seed = seed &* 31 &+ Int32(unit)
            }
        }
        let ms = Int(Date().timeIntervalSince1970 * 1000)
        let id = "w" + String(ms, radix: 36) + String(Int.random(in: 0..<1_000_000), radix: 36)
        var rec = WorldRecord(id: id, name: name, seed: seed, gameMode: mode, difficulty: difficulty)
        // pick a spawn: walk outward for a land biome
        let gen = overworldGen(UInt32(bitPattern: seed))
        var sx = 8, sz = 8
        for r in 0..<40 {
            let tx = 8 + r * 40, tz = 8 + ((r * 13) % 7 - 3) * 40
            let b = gen.surfaceBiomeAt(Double(tx), Double(tz))
            let h = gen.heightEstimate(Double(tx), Double(tz))
            let bname = (BIOMES[Int(b.rawValue)]?.name ?? "").lowercased()
            if h > DIMS[Dim.overworld.rawValue].seaLevel && !bname.contains("ocean") && !bname.contains("river") {
                sx = tx
                sz = tz
                break
            }
        }
        rec.spawnX = sx
        rec.spawnZ = sz
        rec.spawnY = gen.heightEstimate(Double(sx), Double(sz)) + 1
        db.putWorld(rec)
        enterWorld(rec, nil, nil)
    }

    public func loadWorld(_ id: String) {
        guard let rec = db.getWorld(id) else { return }
        let playerData = db.getPlayer(id)
        let adv = db.getAdvancements(id)
        enterWorld(rec, playerData, adv)
    }

    public func deleteWorld(_ id: String) {
        db.deleteWorld(id)
    }

    // ===========================================================================
    // World lifecycle
    // ===========================================================================
    private func enterWorld(_ rec: WorldRecord, _ playerData: [String: Any]?, _ adv: [String]?) {
        worldRec = rec
        netHostView = nil
        wipes = rec.wipes ?? []
        wipeFronts = []
        wipeArmedAt = [:]
        advancements = AdvancementTracker()
        if let adv { advancements.load(adv) }
        dragonSpawned = false
        worlds.removeAll()
        resetEntityIds(max(1, rec.nextEntityId))
        for d in [Dim.overworld, .nether, .end] {
            let w = World(dim: d, seed: UInt32(bitPattern: rec.seed))
            if let ds = rec.dims["\(d.rawValue)"] {
                w.time = ds.time
                w.dayTime = ds.dayTime
                w.raining = ds.raining
                w.thundering = ds.thundering
                w.weatherTimer = ds.weatherTimer
                w.rainLevel = ds.raining ? 1 : 0
                w.thunderLevel = ds.thundering ? 1 : 0
            }
            w.difficulty = rec.difficulty
            for (k, v) in rec.gameRules { w.gameRules[k] = v }
            w.spawnX = Double(rec.spawnX)
            w.spawnY = Double(rec.spawnY)
            w.spawnZ = Double(rec.spawnZ)
            hookWorld(w)
            worlds[d] = w
        }
        savedChunkKeys = db.getChunkKeys(rec.id)
        dim = Dim(rawValue: (playerData?["dim"] as? NSNumber)?.intValue ?? 0) ?? .overworld
        let w = world
        player = Player(world: w)
        player.setGameMode(rec.gameMode)
        if let pd = playerData?["data"] as? [String: Any] {
            player.load(pd)
            // a corrupted save (NaN position from an old physics blowup) renders
            // nothing at all — snap back to world spawn instead
            if !player.x.isFinite || !player.y.isFinite || !player.z.isFinite {
                player.setPos(Double(rec.spawnX) + 0.5, Double(rec.spawnY + 1), Double(rec.spawnZ) + 0.5)
                player.vx = 0; player.vy = 0; player.vz = 0
            }
        } else {
            player.setPos(Double(rec.spawnX) + 0.5, Double(rec.spawnY + 1), Double(rec.spawnZ) + 0.5)
            // starter nothing — vanilla survival starts empty-handed
        }
        w.addEntity(player)

        // spawn area must exist before the first tick — saved copies are read so
        // edits near spawn aren't shadowed by fresh generation
        let pcx = floorDiv(ifloor(player.x), 16), pcz = floorDiv(ifloor(player.z), 16)
        ensureChunksLoaded(w, pcx, pcz, 1)
        if playerData == nil {
            if dim == .overworld { settleSpawn(w) }
            let rec = worldRec ?? rec
            let sy = w.surfaceY(rec.spawnX, rec.spawnZ)
            player.setPos(Double(rec.spawnX) + 0.5, Double(sy), Double(rec.spawnZ) + 0.5)
        }
        // if loading into the End with a living fight, re-arm the dragon hook
        for e in w.entities {
            if let d = e as? EnderDragon { armDragon(d) }
        }

        inWorld = true
        deathScreenShown = false
        ticksSinceSave = 0
        host?.closeAllScreens()
        host?.showActionBar("§e\(rec.name)§r - seed \(rec.seed)", 60)
        // loaded in deep underground? say so loudly instead of looking like a render bug
        let bx = ifloor(player.x), bz = ifloor(player.z)
        if w.info.hasSky && Double(w.heightAt(bx, bz)) > player.eyeY() + 10 {
            host?.pushChat("§eYou are deep underground. Type §f/surface§e to climb out.")
            host?.showActionBar("§eDeep underground - press T, type §f/surface", 400)
        }
    }

    private func hookWorld(_ w: World) {
        var hooks = WorldHooks()
        hooks.onSectionDirty = { [weak self, weak w] cx, cz, sy in
            guard let self, let w else { return }
            self.dirtySections[w.dim]!.insert(SectionPos(cx: cx, sy: sy, cz: cz))
        }
        hooks.playSound = { [weak self, weak w] name, x, y, z, volume, pitch in
            guard let self, let w, w === self.worlds[self.dim] else { return }
            self.host?.playSound(name, x, y, z, volume, pitch)
            self.netHost?.sound(name, x, y, z, volume, pitch)
        }
        hooks.addParticles = { [weak self, weak w] type, x, y, z, count, spread, data in
            guard let self, let w, w === self.worlds[self.dim] else { return }
            self.netHost?.particle(type, x, y, z, count, spread, data)
            let mult = [0.3, 0.65, 1.0][min(2, max(0, self.settings.particles))]
            let n = max(1, Int((Double(count) * mult).rounded()))
            self.host?.addParticles(type, x, y, z, n, spread, data)
        }
        hooks.onVibration = { [weak w] x, y, z, freq, src in
            guard let w else { return }
            handleVibration(w, x, y, z, freq)
            for e in w.getEntitiesNear(x, y, z, 24, filter: { ($0 as? Entity)?.type == "warden" }) {
                (e as? Warden)?.hearVibration(x, y, z, src as? Entity)
            }
        }
        hooks.requestChunk = { [weak self, weak w] cx, cz in
            guard let self, let w else { return }
            self.requestChunk(w, cx, cz)
        }
        w.hooks = hooks
    }

    public func saveAndFlush(synchronous: Bool = false) {
        // a guest's player is kept by the host; the world isn't ours to save
        if let nc = netClient { nc.sendSave(); return }
        guard inWorld, var rec = worldRec else { return }
        rec.lastPlayed = Date().timeIntervalSince1970 * 1000
        rec.gameMode = player.gameMode
        rec.wipes = wipes.isEmpty ? nil : wipes
        rec.nextEntityId = peekNextEntityId()
        for (d, w) in worlds {
            rec.dims["\(d.rawValue)"] = DimState(
                time: w.time, dayTime: w.dayTime,
                raining: w.raining, thundering: w.thundering, weatherTimer: w.weatherTimer)
        }
        // rules/difficulty are world-global (kept in sync across dims by
        // setGameRule/setDifficulty) — read one deterministic source
        if let cur = worlds[dim] {
            rec.difficulty = cur.difficulty
            rec.gameRules = cur.gameRules
        }
        worldRec = rec
        db.putWorld(rec)
        db.putPlayer(rec.id, ["dim": dim.rawValue, "data": player.save()])
        db.putAdvancements(rec.id, advancements.save())
        // all modified chunks across all dims
        var records: [ChunkRecord] = []
        for (d, w) in worlds {
            for c in w.chunks.values where c.modified {
                records.append(chunkRecord(rec.id, d, w, c))
            }
        }
        // include any unload records still waiting in the batch buffer
        for r in pendingChunkSaves.values { records.append(r) }
        pendingChunkSaves.removeAll()
        for r in records { savedChunkKeys.insert(r.key) }
        if synchronous {
            saveQueue.sync { self.writeChunkBatch(records) }
        } else {
            saveQueue.async { [weak self] in self?.writeChunkBatch(records) }
        }
        for w in worlds.values {
            for c in w.chunks.values { c.modified = false }
        }
    }

    /// block until queued chunk writes have landed (tests, diagnostics)
    public func waitForSaves() { saveQueue.sync {} }

    /// runs ON the save queue; on failure re-marks the chunks dirty (on main)
    /// so the next autosave retries instead of silently losing the edits
    private func writeChunkBatch(_ records: [ChunkRecord]) {
        if db.putChunks(records) { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            print("[saves] chunk batch failed - re-marking \(records.count) chunks dirty for retry")
            for r in records {
                guard let d = Dim(rawValue: r.dim), let w = self.worlds[d] else { continue }
                if let c = w.chunks[chunkKey(r.cx, r.cz)] {
                    c.modified = true
                } else {
                    // already unloaded — requeue the record itself
                    self.pendingChunkSaves[r.key] = r
                }
            }
        }
    }

    /// Difficulty is world-global: apply to every dimension so the value can't
    /// drift (and can't depend on which dim happens to save last).
    public func setDifficulty(_ d: Int) {
        for w in worlds.values { w.difficulty = d }
        worldRec?.difficulty = d
    }

    /// Game rules are world-global: apply to every dimension.
    public func setGameRule(_ rule: String, _ value: Double) {
        for w in worlds.values { w.gameRules[rule] = value }
        worldRec?.gameRules[rule] = value
    }

    private func chunkRecord(_ worldId: String, _ d: Dim, _ w: World, _ c: Chunk) -> ChunkRecord {
        // persist entities standing in this chunk (skip player + transient)
        var ents: [[String: Any]] = []
        for e in w.entities {
            guard let ent = e as? Entity, !ent.isPlayer, !ent.dead else { continue }
            if floorDiv(ifloor(ent.x), 16) != c.cx || floorDiv(ifloor(ent.z), 16) != c.cz { continue }
            if (ent.type == "item" || ent.type == "xp_orb") && ent.age > 4000 { continue }
            ents.append(ent.save())
        }
        let key = db.chunkKey(worldId, d.rawValue, c.cx, c.cz)
        c.savedEntities = !ents.isEmpty
        if !c.modified && !savedFullKeys.contains(key) {
            // entity-only record (~KBs): the blocks regenerate from seed
            return ChunkRecord(key: key, worldId: worldId, dim: d.rawValue, cx: c.cx, cz: c.cz, entities: ents)
        }
        // once a full record exists on disk, every rewrite must stay full —
        // the autosave clears `modified` but the blocks no longer regenerate
        savedFullKeys.insert(key)
        // deep-copy block entities — live BEs keep mutating while the save
        // queue serializes, and BlockEntityData is a reference type
        var besCopy: [BlockEntityData]? = nil
        let besLive = Array(c.blockEntities.values)
        if let data = try? JSONEncoder().encode(besLive) {
            besCopy = try? JSONDecoder().decode([BlockEntityData].self, from: data)
        }
        return ChunkRecord(
            key: key, worldId: worldId, dim: d.rawValue, cx: c.cx, cz: c.cz,
            blocks: c.blocks, biomes: c.biomes, blockEntities: besCopy ?? besLive, entities: ents)
    }

    // ===========================================================================
    // Chunk streaming
    // ===========================================================================
    private func requestChunk(_ w: World, _ cx: Int, _ cz: Int) {
        let key = chunkKey(cx, cz)
        let flight = DimChunk(dim: w.dim.rawValue, key: key)
        if w.chunks[key] != nil || genInFlight.contains(flight) { return }
        if genInFlight.count >= MAX_GEN_INFLIGHT { return }
        guard let rec = worldRec else { return }
        genInFlight.insert(flight)
        let worldId = rec.id
        let d = w.dim
        let seed = w.seed
        let height = w.info.height
        let hasSky = w.info.hasSky
        let saved = savedChunkKeys.contains(db.chunkKey(worldId, d.rawValue, cx, cz))
        let db = self.db
        let minY = w.info.minY
        // wipe zones this chunk still owes a cut (applied before it's lit)
        let wipeIdx = wipesOwed(w, cx, cz)
        let zones = wipeIdx.map { wipes[$0] }
        genQueue.async { [weak self] in
            var savedRec: ChunkRecord? = nil
            if saved { savedRec = db.getChunk(worldId, d.rawValue, cx, cz) }
            let c: Chunk
            var beSpecs: [BESpec]? = nil
            var entitySpecs: [EntitySpec]? = nil
            var loadedFull = false
            var wiped = false
            func cut(_ blocks: inout [UInt16]) {
                for z in zones where wipeChunkBlocks(&blocks, cx, cz, minY: minY, height: height, seed: seed, zone: z) { wiped = true }
            }
            if let savedRec, Self.recordUsable(savedRec, height: height) {
                // saved chunk: relight the stored blocks
                loadedFull = true
                var blocks = savedRec.blocks!
                cut(&blocks)
                let light = LoadProf.shared.time("light") { computeLocalLight(blocks: blocks, height: height, hasSky: hasSky) }
                c = LoadProf.shared.time("mkchunk") { Self.makeChunk(cx, cz, minY, height, blocks, savedRec.biomes!, light.sky, light.blk) }
            } else {
                // fresh generation; a corrupt/entity-only record still re-attaches its entities
                let out = LoadProf.shared.time("gen") { generateChunk(d, seed, cx, cz) }
                var blocks = out.blocks
                cut(&blocks)
                let light = LoadProf.shared.time("light") { computeLocalLight(blocks: blocks, height: height, hasSky: hasSky) }
                c = LoadProf.shared.time("mkchunk") { Self.makeChunk(cx, cz, minY, height, blocks, out.biomes, light.sky, light.blk) }
                beSpecs = out.blockEntities
                entitySpecs = savedRec != nil ? nil : out.entities
            }
            let savedFinal = savedRec
            let wipedFinal = wiped
            DispatchQueue.main.async {
                guard let self else { return }
                self.genInFlight.remove(flight)
                guard self.inWorld, self.worlds[d] === w, w.chunks[key] == nil else { return }
                if loadedFull { self.savedFullKeys.insert(db.chunkKey(worldId, d.rawValue, cx, cz)) }
                self.adoptChunk(w, c, beSpecs, entitySpecs, savedFinal)
                self.wipeOnLoad(w, c, cutBy: wipeIdx, changed: wipedFinal)
                self.enqueueLightAround(w, cx, cz)
            }
        }
    }

    /// A saved record is only trustworthy if its arrays have the exact expected sizes
    private static func recordUsable(_ saved: ChunkRecord, height: Int) -> Bool {
        guard let blocks = saved.blocks, let biomes = saved.biomes else { return false }
        if blocks.count != 16 * 16 * height { return false }
        if biomes.count != 4 * 4 * ((height + 3) / 4) { return false }
        return true
    }

    /// heavy chunk assembly (heightmap + special scan) — safe off-main, the
    /// chunk isn't shared until adoptChunk
    static func makeChunk(
        _ cx: Int, _ cz: Int, _ minY: Int, _ height: Int,
        _ blocks: [UInt16], _ biomes: [UInt8],
        _ skyLight: [UInt8]?, _ blockLight: [UInt8]?
    ) -> Chunk {
        let c = Chunk(cx: cx, cz: cz, minY: minY, height: height)
        c.blocks = blocks
        c.biomes = biomes
        if let skyLight { c.skyLight = skyLight }
        if let blockLight { c.blockLight = blockLight }
        c.buildHeightmap()
        c.scanSpecials()
        c.status = .generated
        return c
    }

    private func adoptChunk(
        _ w: World, _ c: Chunk,
        _ beSpecs: [BESpec]?, _ entitySpecs: [EntitySpec]?,
        _ saved: ChunkRecord?
    ) {
        let cx = c.cx, cz = c.cz
        _ = (cx, cz)
        w.setChunk(c)
        // block entities: a full saved record carries them verbatim; otherwise
        // worldgen specs resolve deterministically
        if let savedBEs = saved?.blockEntities {
            for be in savedBEs {
                c.setBlockEntity(posMod(be.x, 16), be.y, posMod(be.z, 16), be)
            }
            // unchanged since it was read: savedFullKeys keeps any rewrite
            // full (marking it modified re-saved every revisited chunk)
            c.modified = false
        } else if let beSpecs {
            for spec in beSpecs { resolveBESpec(w, c, spec) }
            c.modified = false
        }
        w.adoptChunkBlockEntities(c)
        // entities: any saved record (full or entity-only) overrides worldgen spawns
        if let saved {
            c.savedEntities = !saved.entities.isEmpty
            for ed in saved.entities {
                if let e = loadEntity(w, ed) {
                    w.addEntity(e)
                    if let dragon = e as? EnderDragon { armDragon(dragon) }
                }
            }
        } else if let entitySpecs {
            for es in entitySpecs {
                let m = spawnMob(w, es.mob, es.x, es.y, es.z, spawnOptsFrom(es.data))
                m?.persistent = true
            }
        }
    }

    private func spawnOptsFrom(_ data: [String: BEValue]) -> SpawnOpts {
        var opts = SpawnOpts()
        if case .bool(let b)? = data["baby"] { opts.baby = b }
        if case .bool(let b)? = data["persistent"] { opts.persistent = b }
        if case .bool(let b)? = data["captain"] { opts.captain = b }
        if case .num(let n)? = data["size"] { opts.size = Int(n) }
        if case .num(let n)? = data["variant"] { opts.variant = Int(n) }
        return opts
    }

    /// worldgen block-entity specs → live block entities
    private func resolveBESpec(_ w: World, _ c: Chunk, _ spec: BESpec) {
        let x = spec.x, y = spec.y, z = spec.z
        let lx = posMod(x, 16), lz = posMod(z, 16)
        func put(_ be: BlockEntityData) { c.setBlockEntity(lx, y, lz, be) }
        func str(_ k: String) -> String? {
            if case .str(let s)? = spec.data[k] { return s }
            return nil
        }
        func num(_ k: String) -> Double? {
            if case .num(let n)? = spec.data[k] { return n }
            return nil
        }
        func bool(_ k: String) -> Bool? {
            if case .bool(let b)? = spec.data[k] { return b }
            return nil
        }
        var rng = RandomX(hash3(w.seed ^ 0xBE5, x, y, z))
        switch spec.kind {
        case "chest_loot":
            let be = makeContainerBE(x, y, z, 27)
            var lootRng = RandomX(UInt32(truncatingIfNeeded: Int64(num("seed") ?? 0)))
            let items = rollLoot(str("lootTable") ?? "", &lootRng, luck: 0)
            for s in items {
                var slot = rng.nextInt(27)
                var i = 0
                while i < 27 && be.items![slot] != nil {
                    slot = (slot + 1) % 27
                    i += 1
                }
                be.items![slot] = s
            }
            be.lootTable = str("lootTable")
            put(be)
        case "chest_items":
            // fixed contents: "item*count,item*count,…" in slot order
            let be = makeContainerBE(x, y, z, 27)
            for (slot, entry) in (str("items") ?? "").split(separator: ",").prefix(27).enumerated() {
                let parts = entry.split(separator: "*")
                guard let id = iidOpt(String(parts[0])) else { continue }
                let n = parts.count > 1 ? Int(parts[1]) ?? 1 : 1
                be.items![slot] = ItemStack(id, max(1, min(n, itemDef(id).maxStack)))
            }
            put(be)
        case "elytra_chest":
            let be = makeContainerBE(x, y, z, 27)
            be.items![13] = ItemStack(iid("elytra"), 1)
            let extra = rollLoot("end_city_treasure", &rng, luck: 0)
            for s in extra.prefix(4) {
                let slot = rng.nextInt(27)
                if be.items![slot] == nil { be.items![slot] = s }
            }
            put(be)
        case "dispenser_arrows":
            let be = makeContainerBE(x, y, z, 9)
            be.items![4] = ItemStack(iid("arrow"), 2 + rng.nextInt(7))
            put(be)
        case "spawner":
            put(makeSpawnerBE(x, y, z, str("mob") ?? "zombie"))
        case "brushable":
            put(makeBrushableBE(x, y, z, str("lootTable") ?? "trail_ruins_common", Int(hash3(w.seed, x, y, z))))
        case "beehive":
            let be = BlockEntityData(type: "beehive", x: x, y: y, z: z)
            be.bees = Int(num("bees") ?? 3)
            be.honey = 0
            put(be)
        case "sign":
            let be = makeSignBE(x, y, z)
            let lines = (str("text") ?? "").components(separatedBy: "|")
            be.lines = (0..<4).map { $0 < lines.count ? lines[$0] : "" }
            put(be)
        case "pot_plant":
            let be = BlockEntityData(type: "lectern", x: x, y: y, z: z)
            be.plant = str("plant") ?? "poppy"
            put(be)
        case "pot_sherds":
            let pool: [String?] = ["archer", "prize", "arms_up", "skull", "heart", "heartbreak", "howl", "sheaf", nil, nil]
            let be = BlockEntityData(type: "pot", x: x, y: y, z: z)
            be.sherds = (0..<4).map { _ in pool[rng.nextInt(pool.count)] }
            put(be)
        case "shrieker":
            let be = BlockEntityData(type: "shrieker", x: x, y: y, z: z)
            be.canSummon = bool("canSummon") ?? true
            be.shrieking = 0
            put(be)
        default:
            break
        }
    }

    // MARK: - /place

    public struct PlaceResult {
        public let changed: Int
        public let skippedCells: Int
        public let x0: Int, y0: Int, z0: Int, x1: Int, y1: Int, z1: Int
        /// top of the marked ladder shaft dug down to a buried structure
        public var entrance: (Int, Int, Int)? = nil
    }

    /// stamp a captured structure into the live world centered on (tx,tz).
    /// Surface structures sit with their ground level at `ty` (default: the real
    /// ground under (tx,tz), ignoring trees); underground ones keep their native
    /// depth, or put their lowest block at `ty`. Everything in the footprint above
    /// ground — terrain, trees, plants — is destroyed and replaced, and columns
    /// overhanging lower terrain get a foundation down to solid ground.
    public func placePrefab(_ pf: Prefab, _ tx: Int, _ ty: Int?, _ tz: Int) -> PlaceResult {
        let w = world
        let G = PREFAB_GROUND
        let dx = tx - floorDiv(pf.x0 + pf.x1, 2), dz = tz - floorDiv(pf.z0 + pf.z1, 2)
        let dy: Int
        if pf.surface { dy = (ty ?? groundLevel(w, tx, tz)) - G } else { dy = ty.map { $0 - pf.y0 } ?? 0 }
        let flags = SET_NO_NEIGHBORS
        var changed = 0, skipped = 0
        let batch = beginEdit(w, "place \(pf.id)")
        func put(_ x: Int, _ y: Int, _ z: Int, _ c: Int) {
            guard w.isLoadedAt(x, z) else { skipped += 1; return }
            if batch.set(x, y, z, c, flags) { changed += 1 }
        }

        var captured = Set<Int64>()
        captured.reserveCapacity(pf.cells.count)
        for (x, y, z, _) in pf.cells { captured.insert(CaptureSink.pack(x, y, z)) }

        if pf.surface {
            // per column (capture coords): highest captured y, lowest solid y
            struct Col { var top = Int.min; var low = Int.max; var lowCell: UInt16 = 0 }
            var cols: [Int64: Col] = [:]
            var order: [Int64] = []
            for (x, y, z, c) in pf.cells where y >= G - 1 {
                let k = CaptureSink.pack(x, 0, z)
                var col = cols[k] ?? { order.append(k); return Col() }()
                col.top = max(col.top, y)
                if c != 0 && y < col.low { col.low = y; col.lowCell = c }
                cols[k] = col
            }
            let dirt = Int(cell(B.dirt))
            for k in order {
                let col = cols[k]!
                let (x, _, z) = CaptureSink.unpack(k)
                let wx = x + dx, wz = z + dz
                // clear: ground level up to 4 above the structure, then any tree above that
                var y = G
                while y <= col.top + 4 {
                    if !captured.contains(CaptureSink.pack(x, y, z)) { put(wx, y + dy, wz, 0) }
                    y += 1
                }
                // trees above that, across air gaps (a tall trunk's canopy
                // was left floating over the site), up to the first other block
                let treeTop = min(w.info.minY + w.info.height - 1 - dy, y + 32)
                while y <= treeTop {
                    let id = w.getBlockId(wx, y + dy, wz)
                    if id != 0 {
                        if !isTreeOrPlant(id) { break }
                        put(wx, y + dy, wz, 0)
                    }
                    y += 1
                }
                // foundation under columns that rest on the ground
                if col.low <= G {
                    let lid = Int(col.lowCell >> 4)
                    let fill = blockDefs[lid].fullCube && OPAQUE[lid] == 1 && HAS_GRAVITY[lid] == 0 ? Int(col.lowCell) : dirt
                    func open(_ y: Int) -> Bool {
                        let id = w.getBlockId(wx, y, wz)
                        return isTreeOrPlant(id) || id == Int(B.water) || id == Int(B.lava)
                    }
                    // only when real ground is within reach — a build placed
                    // up in the air on purpose shouldn't trail a pillar
                    let top = col.low + dy - 1
                    var fy = top
                    while fy > max(w.info.minY, top - 24), open(fy) { fy -= 1 }
                    if !open(fy) {
                        for y in stride(from: top, to: fy, by: -1) { put(wx, y, wz, fill) }
                    }
                }
            }
        }

        for (x, y, z, c) in pf.cells { put(x + dx, y + dy, z + dz, Int(c)) }

        // block entities after blocks: setBlock drops BEs whose block changes
        for spec in pf.blockEntities {
            let s = BESpec(x: spec.x + dx, y: spec.y + dy, z: spec.z + dz, kind: spec.kind, data: spec.data)
            guard let c = w.getChunkAt(s.x, s.z) else { continue }
            resolveBESpec(w, c, s)
            if let be = c.getBlockEntity(posMod(s.x, 16), s.y, posMod(s.z, 16)), beTickHandlers[be.type] != nil {
                w.trackTickingBE(be)
            }
        }
        for es in pf.entities {
            let m = spawnMob(w, es.mob, es.x + Double(dx), es.y + Double(dy), es.z + Double(dz), spawnOptsFrom(es.data))
            m?.persistent = true
        }
        var r = PlaceResult(changed: changed, skippedCells: skipped,
                            x0: pf.x0 + dx, y0: pf.y0 + dy, z0: pf.z0 + dz, x1: pf.x1 + dx, y1: pf.y1 + dy, z1: pf.z1 + dz)
        // buried structures get a lit ladder shaft and a flag so they can be found
        if !pf.surface, let (ex, ey, ez) = entranceTarget(pf) {
            r.entrance = digEntrance(w, ex + dx, ey + dy, ez + dz, put)
        }
        return r
    }

    /// ladder shaft from the surface down to the air cell (x,y,z), lined with
    /// stone bricks where it crosses caves or loose ground, with a flag pole
    /// and lanterns on top. Returns the surface point.
    private func digEntrance(_ w: World, _ x: Int, _ y: Int, _ z: Int,
                             _ put: (Int, Int, Int, Int) -> Void) -> (Int, Int, Int) {
        let brick = Int(cell(B.stone_bricks)), ladder = Int(cell(B.ladder, 0))
        let top = max(groundLevel(w, x, z), y + 3)
        func weak(_ x: Int, _ y: Int, _ z: Int) -> Bool {
            let id = w.getBlockId(x, y, z)
            return isTreeOrPlant(id) || id == Int(B.water) || id == Int(B.lava) || HAS_GRAVITY[id] != 0
        }
        // the ladder's backing wall (+z) runs all the way down to the floor
        for sy in y...(top + 1) {
            for oz in -1...1 {
                for ox in -1...1 where ox != 0 || oz != 0 {
                    let isBack = ox == 0 && oz == 1
                    if (isBack && sy <= top) || (sy < top && sy > y + 2 && weak(x + ox, sy, z + oz)) { put(x + ox, sy, z + oz, brick) }
                }
            }
            put(x, sy, z, sy <= top ? ladder : 0)
            // a light in the west wall every 6 blocks
            if sy < top - 1 && (top - sy) % 6 == 0 && !isTreeOrPlant(w.getBlockId(x - 1, sy, z)) {
                put(x - 1, sy, z, Int(cell(B.glowstone)))
            }
        }
        // clear the canopy over the entrance so the flag shows
        let ceil = min(w.info.minY + w.info.height - 1, top + 40)
        var canopy = top
        for oz in -6...6 {
            for ox in -6...6 {
                for cy in top...ceil where w.getBlockId(x + ox, cy, z + oz) != 0 {
                    let id = w.getBlockId(x + ox, cy, z + oz)
                    if abs(ox) <= 3 && abs(oz) <= 3 && isTreeOrPlant(id) { put(x + ox, cy, z + oz, 0) }
                    else { canopy = max(canopy, cy) }
                }
            }
        }
        // surface collar, flag pole and lights
        for oz in -2...2 {
            for ox in -2...2 where abs(ox) == 2 || abs(oz) == 2 {
                put(x + ox, top - 1, z + oz, brick)
                put(x + ox, top, z + oz, 0)
                put(x + ox, top + 1, z + oz, 0)
            }
        }
        for (ox, oz) in [(-1, -1), (1, -1), (-1, 1), (1, 1)] {
            put(x + ox, top, z + oz, Int(cell(B.stone_brick_wall)))
            put(x + ox, top + 1, z + oz, Int(cell(B.lantern)))
        }
        // flag pole tall enough to clear the surrounding trees
        let px = x + 2, pz = z + 2
        let poleTop = min(ceil - 1, max(top + 10, canopy + 5))
        for py in top..<poleTop { put(px, py, pz, Int(cell(B.oak_fence))) }
        for fy in (poleTop - 3)..<poleTop {
            for fx in 1...4 { put(px + fx, fy, pz, Int(cell(B.red_wool))) }
        }
        put(px, poleTop, pz, Int(cell(B.glowstone)))
        return (x, top, z)
    }

    /// queue every chunk around (cx,cz) whose 3×3 neighborhood is now generated
    private func enqueueLightAround(_ w: World, _ cx: Int, _ cz: Int) {
        for dz in -1...1 {
            for dx in -1...1 {
                guard let c = w.getChunk(cx + dx, cz + dz), c.status == .generated else { continue }
                if !w.neighborsReady(c.cx, c.cz) { continue }
                lightQueue[w.dim]!.insert(chunkKey(c.cx, c.cz))
            }
        }
    }

    /// finish lighting a chunk: cheap seam exchange (local light came from the gen queue)
    private func lightChunk(_ w: World, _ c: Chunk) {
        w.light.stitchChunk(c)
        var dirty = dirtySections[w.dim]!
        for s in 0..<c.sections { dirty.insert(SectionPos(cx: c.cx, sy: s, cz: c.cz)) }
        for (nx, nz) in [(c.cx - 1, c.cz), (c.cx + 1, c.cz), (c.cx, c.cz - 1), (c.cx, c.cz + 1)] {
            if let n = w.getChunk(nx, nz), n.status == .lit {
                for s in 0..<n.sections { dirty.insert(SectionPos(cx: nx, sy: s, cz: nz)) }
            }
        }
        dirtySections[w.dim] = dirty
        if !w.isRemote { activateFluids(w, c) }
    }

    /// schedule flow ticks for fluid cells that should be moving — the fluid sim
    /// is purely event-driven, so worldgen springs/lakes (and saves made mid-flow)
    /// otherwise sit frozen forever until some neighbor changes
    private func activateFluids(_ w: World, _ c: Chunk) {
        let waterId = B.water, lavaId = B.lava
        let minY = c.minY
        // pure scan first; world lookups outside the unsafe buffer access
        var fluidCells: [(Int, Int, Int, UInt16)] = []
        c.blocks.withUnsafeBufferPointer { bp in
            for i in 0..<bp.count {
                let cellv = bp[i]
                let id = cellv >> 4
                if id == waterId || id == lavaId {
                    fluidCells.append((i & 15, (i >> 8) + minY, (i >> 4) & 15, cellv))
                }
            }
        }
        // ocean/lake chunks hold thousands of stable sources — waking them all
        // floods the tick queue and the drop-seek BFS melts the frame rate.
        // Big water bodies are self-stable; only wake modest fluid populations.
        let wakeSources = fluidCells.count <= 400
        var woken = 0
        let baseX = c.cx * 16, baseZ = c.cz * 16
        for (lx, wy, lz, cellv) in fluidCells {
            if woken >= 128 { break }
            let wx = baseX + lx, wz = baseZ + lz
            let id = Int(cellv >> 4)
            if (cellv & 15) != 0 {
                w.scheduleTick(wx, wy, wz, id, id == Int(waterId) ? 5 : 30)
                woken += 1
                continue
            }
            guard wakeSources else { continue }
            // source: only wake it if it can actually act
            let below = w.getBlock(wx, wy - 1, wz) >> 4
            if below == 0 || (below != id && REPLACEABLE[below] == 1) {
                w.scheduleTick(wx, wy, wz, id, id == Int(waterId) ? 5 : 30)
                woken += 1
                continue
            }
            for d in 0..<4 {
                let n = w.getBlock(wx + [0, 0, -1, 1][d], wy, wz + [-1, 1, 0, 0][d]) >> 4
                if n == 0 {
                    w.scheduleTick(wx, wy, wz, id, id == Int(waterId) ? 5 : 30)
                    woken += 1
                    break
                }
            }
        }
    }

    /// Budgeted initial lighting: nearest chunks first, stop when the frame's budget is spent
    private func processLightQueue() {
        guard inWorld else { return }
        let w = world
        var q = lightQueue[dim]!
        if !q.isEmpty {
            let pcx = floorDiv(ifloor(player.x), 16)
            let pcz = floorDiv(ifloor(player.z), 16)
            var ready: [(key: Int64, c: Chunk, d: Int)] = []
            for key in q {
                guard let c = w.chunks[key], c.status == .generated else {
                    q.remove(key) // gone or already lit — done with it
                    continue
                }
                if !w.neighborsReady(c.cx, c.cz) { continue } // keep queued, never drop
                ready.append((key, c, (c.cx - pcx) * (c.cx - pcx) + (c.cz - pcz) * (c.cz - pcz)))
            }
            ready.sort { $0.d < $1.d }
            let t0 = CFAbsoluteTimeGetCurrent()
            for r in ready {
                q.remove(r.key)
                lightChunk(w, r.c)
                if (CFAbsoluteTimeGetCurrent() - t0) * 1000 > LIGHT_BUDGET_MS { break }
            }
        }
        // self-heal: any chunk that slipped through the queue gets re-queued
        // (this runs per frame — gate to once per qualifying tick)
        if w.time % 20 == 0 && lastLightHealTick != w.time {
            lastLightHealTick = w.time
            for c in w.chunks.values {
                if c.status == .generated && w.neighborsReady(c.cx, c.cz) {
                    q.insert(chunkKey(c.cx, c.cz))
                }
            }
            // retry sections parked on an unfinished neighborhood
            if let stalled = stalledSections[dim], !stalled.isEmpty {
                dirtySections[dim]!.formUnion(stalled)
                stalledSections[dim] = []
            }
        }
        lightQueue[dim] = q
    }

    /// Guarantee an area exists before placing the player in it (synchronous)
    private func ensureChunksLoaded(_ w: World, _ ccx: Int, _ ccz: Int, _ radius: Int) {
        if w.isRemote { return } // a guest's chunks come from the host
        let worldId = worldRec?.id
        for dz in -radius...radius {
            for dx in -radius...radius {
                let cx = ccx + dx, cz = ccz + dz
                if w.chunks[chunkKey(cx, cz)] != nil { continue }
                var saved: ChunkRecord? = nil
                if let worldId, savedChunkKeys.contains(db.chunkKey(worldId, w.dim.rawValue, cx, cz)) {
                    saved = db.getChunk(worldId, w.dim.rawValue, cx, cz)
                    if let s = saved, Self.recordUsable(s, height: w.info.height) {
                        let light = computeLocalLight(blocks: s.blocks!, height: w.info.height, hasSky: w.info.hasSky)
                        adoptChunk(w, Self.makeChunk(cx, cz, w.info.minY, w.info.height, s.blocks!, s.biomes!, light.sky, light.blk),
                                   nil, nil, s)
                        if let c = w.getChunk(cx, cz) { wipeOnLoad(w, c, cutBy: [], changed: false) }
                        continue
                    }
                }
                let out = generateChunk(w.dim, w.seed, cx, cz)
                let light = computeLocalLight(blocks: out.blocks, height: w.info.height, hasSky: w.info.hasSky)
                adoptChunk(w, Self.makeChunk(cx, cz, w.info.minY, w.info.height, out.blocks, out.biomes, light.sky, light.blk),
                           out.blockEntities, saved != nil ? nil : out.entities, saved)
                if let c = w.getChunk(cx, cz) { wipeOnLoad(w, c, cutBy: [], changed: false) }
            }
        }
        // teleport targets need light immediately — stitch the area now
        for dz in (-radius - 1)...(radius + 1) {
            for dx in (-radius - 1)...(radius + 1) {
                if let c = w.getChunk(ccx + dx, ccz + dz), c.status == .generated, w.neighborsReady(c.cx, c.cz) {
                    lightChunk(w, c)
                }
            }
        }
    }

    private func streamChunks() {
        let w = world
        let pcx = floorDiv(ifloor(player.x), 16)
        let pcz = floorDiv(ifloor(player.z), 16)
        w.simCenterX = pcx
        w.simCenterZ = pcz
        let R = settings.renderDistance + GEN_RADIUS_PAD
        // LAN guests need their own areas loaded too (the host's comes first)
        let centers = [(pcx, pcz, R)] + (netHost?.guestCenters().map { ($0.0, $0.1, $0.2 + 1) } ?? [])
        w.extraSimCenters = centers.dropFirst().map { ($0.0, $0.1) }
        // request missing chunks ring by ring (closest first)
        outer: for (ccx, ccz, cr) in centers {
            for r in 0...cr {
                for dz in -r...r {
                    for dx in -r...r {
                        if max(abs(dx), abs(dz)) != r { continue }
                        if genInFlight.count >= MAX_GEN_INFLIGHT { break outer }
                        let cx = ccx + dx, cz = ccz + dz
                        if w.chunks[chunkKey(cx, cz)] == nil { requestChunk(w, cx, cz) }
                    }
                }
            }
        }
        // unload far chunks (tight radius — chunk arrays are ~400KB each),
        // except under a mountain that's still rising
        mountainPins.removeAll { $0.job.done }
        let pinned = mountainPins.reduce(into: Set<Int64>()) { $0.formUnion($1.keys) }
        for c in Array(w.chunks.values) {
            let far = centers.allSatisfy { abs(c.cx - $0.0) > $0.2 + 2 || abs(c.cz - $0.1) > $0.2 + 2 }
            if far && !pinned.contains(chunkKey(c.cx, c.cz)) { unloadChunk(w, c) }
        }
        // inactive dimensions don't stream — drop everything they hold
        if w.time % 100 == 0 {
            for (d, other) in worlds {
                if d == dim { continue }
                for c in Array(other.chunks.values) { unloadChunk(other, c) }
            }
        }
    }

    private func unloadChunk(_ w: World, _ c: Chunk) {
        // persist if edited, if live entities stand in it, or if its record may
        // be stale: entities have left it, or block entities (chest contents,
        // furnaces, signs) changed in place, which doesn't mark the chunk
        var hasEntities = false
        for e in w.entities {
            guard let ent = e as? Entity, !ent.isPlayer, !ent.dead else { continue }
            if floorDiv(ifloor(ent.x), 16) == c.cx && floorDiv(ifloor(ent.z), 16) == c.cz {
                hasEntities = true
                break
            }
        }
        if let rec = worldRec {
            let dbKey = db.chunkKey(rec.id, w.dim.rawValue, c.cx, c.cz)
            let stale = c.savedEntities || !c.blockEntities.isEmpty
            if c.modified || hasEntities || (stale && savedChunkKeys.contains(dbKey)) {
                let record = chunkRecord(rec.id, w.dim, w, c)
                savedChunkKeys.insert(record.key)
                pendingChunkSaves[record.key] = record
            }
        }
        // entities standing in the chunk were captured in the record; drop the live ones
        w.removeEntities { e in
            guard let ent = e as? Entity, !ent.isPlayer, !ent.dead else { return false }
            return floorDiv(ifloor(ent.x), 16) == c.cx && floorDiv(ifloor(ent.z), 16) == c.cz
        }
        w.releaseChunkBlockEntities(c)
        w.removeChunk(c.cx, c.cz)
        if w.dim == dim { host?.removeChunkMeshes(c.cx, c.cz, c.sections) }
        lightQueue[w.dim]!.remove(chunkKey(c.cx, c.cz))
        unmeshedChunks[w.dim]?.remove(chunkKey(c.cx, c.cz))
        for s in 0..<c.sections {
            dirtySections[w.dim]!.remove(SectionPos(cx: c.cx, sy: s, cz: c.cz))
        }
    }

    // ---- meshing --------------------------------------------------------------
    private func streamMeshes() {
        guard inWorld else { return }
        let w = world
        let pcx = floorDiv(ifloor(player.x), 16)
        let pcz = floorDiv(ifloor(player.z), 16)
        // the renderer draws out to about renderDistance + 1 chunks; a host
        // also holds every LAN guest's surroundings, which it never sees
        let meshRange = settings.renderDistance + 2
        sweepMeshRange(w, pcx, pcz, meshRange)
        var dirty = dirtySections[dim]!
        if dirty.isEmpty { return }
        // skip the scan entirely while the queue is already full
        if meshJobs.count >= MAX_MESH_INFLIGHT { return }
        // sort a bounded batch by distance
        var candidates: [(pos: SectionPos, d: Int)] = []
        for pos in dirty {
            if max(abs(pos.cx - pcx), abs(pos.cz - pcz)) > meshRange {
                // loaded for a guest, out of our sight: meshed if we come closer
                unmeshedChunks[dim, default: []].insert(chunkKey(pos.cx, pos.cz))
                dirty.remove(pos)
                continue
            }
            guard let c = w.getChunk(pos.cx, pos.cz), c.status == .lit, w.neighborsReady(pos.cx, pos.cz) else { continue }
            // neighbors must be lit too or the seam light is garbage
            var ok = true
            for (nx, nz) in [(pos.cx - 1, pos.cz), (pos.cx + 1, pos.cz), (pos.cx, pos.cz - 1), (pos.cx, pos.cz + 1)] {
                guard let n = w.getChunk(nx, nz), n.status == .lit else { ok = false; break }
            }
            // diagonals only need to exist — the snapshot reads their cells
            if ok && (w.getChunk(pos.cx - 1, pos.cz - 1) == nil || w.getChunk(pos.cx + 1, pos.cz - 1) == nil ||
                w.getChunk(pos.cx - 1, pos.cz + 1) == nil || w.getChunk(pos.cx + 1, pos.cz + 1) == nil) { ok = false }
            if !ok {
                // park it: retried when the surrounding area completes
                stalledSections[dim, default: []].insert(pos)
                dirty.remove(pos)
                continue
            }
            candidates.append((pos, (pos.cx - pcx) * (pos.cx - pcx) + (pos.cz - pcz) * (pos.cz - pcz)))
        }
        candidates.sort { $0.d < $1.d }
        for cand in candidates {
            if meshJobs.count >= MAX_MESH_INFLIGHT { break }
            let jobKey = DimSection(dim: dim.rawValue, pos: cand.pos)
            if let existing = meshJobs[jobKey] {
                existing.dirtyAgain = true
                dirty.remove(cand.pos)
                continue
            }
            dirty.remove(cand.pos)
            dirtySections[dim] = dirty
            dispatchMesh(w, cand.pos, jobKey)
            dirty = dirtySections[dim]!
        }
        dirtySections[dim] = dirty
    }

    /// flip mesh mode at runtime and rebuild every visible section
    public func setMeshMode(simple: Bool) {
        settings.simpleMesh = simple
        saveSettings(settings)
        remeshAll()
    }

    private func remeshAll() {
        host?.clearAllSections()
        meshJobs.removeAll()
        guard inWorld else { return }
        let w = world
        for c in w.chunks.values where c.status == .lit {
            for s in 0..<c.sections {
                dirtySections[dim]!.insert(SectionPos(cx: c.cx, sy: s, cz: c.cz))
            }
        }
    }

    /// when we cross into another chunk: re-mesh parked chunks now in range,
    /// and free the meshes of chunks well out of it (two rings of slack, so
    /// walking back and forth over a border doesn't churn)
    private func sweepMeshRange(_ w: World, _ pcx: Int, _ pcz: Int, _ range: Int) {
        if let m = meshCenter, m.dim == dim, m.cx == pcx, m.cz == pcz { return }
        meshCenter = (dim, pcx, pcz)
        var parked = unmeshedChunks[dim] ?? []
        for key in parked {
            let (cx, cz) = chunkCoords(key)
            guard max(abs(cx - pcx), abs(cz - pcz)) <= range else { continue }
            parked.remove(key)
            if let c = w.getChunk(cx, cz), c.status == .lit {
                for s in 0..<c.sections { dirtySections[dim]!.insert(SectionPos(cx: cx, sy: s, cz: cz)) }
            }
        }
        for c in w.chunks.values where max(abs(c.cx - pcx), abs(c.cz - pcz)) > range + 2 {
            if parked.insert(chunkKey(c.cx, c.cz)).inserted {
                host?.removeChunkMeshes(c.cx, c.cz, c.sections)
            }
        }
        unmeshedChunks[dim] = parked
    }

    private func dispatchMesh(_ w: World, _ pos: SectionPos, _ jobKey: DimSection) {
        let snapOpt = LoadProf.shared.time("snapshot") { buildSnapshot(w, pos.cx, pos.sy, pos.cz) }
        guard var snap = snapOpt else {
            // a diagonal neighbor is missing (streaming frontier / unload churn) —
            // the dirty key was already consumed, so REQUEUE or this section's
            // remesh is lost forever (stale black mesh / permanent hole)
            dirtySections[w.dim]!.insert(pos)
            return
        }
        snap.noMerge = settings.simpleMesh
        let state = MeshJobState()
        meshJobs[jobKey] = state
        let d = w.dim
        let minY = w.info.minY
        meshQueue.async { [weak self] in
            let mesh = LoadProf.shared.time("mesh") { buildSectionMesh(snap) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.meshJobs.removeValue(forKey: jobKey)
                guard self.inWorld, self.worlds[d] === w else { return }
                // (a chunk parked out of range while this job ran stays unmeshed)
                if d == self.dim, self.unmeshedChunks[d]?.contains(chunkKey(pos.cx, pos.cz)) != true {
                    self.host?.uploadMesh(pos.cx, pos.sy, pos.cz, minY, mesh)
                    self.meshedThisSecond += 1
                }
                if state.dirtyAgain { self.dirtySections[d]!.insert(pos) }
            }
        }
    }

    /// reset the once-per-second chunk-update counter (the app's fps timer calls this)
    public func harvestMeshCounter() -> Int {
        let n = meshedThisSecond
        meshedThisSecond = 0
        lastChunkUpdates = n
        return n
    }

    /// padded 18×18×18 snapshot for the mesher
    private func buildSnapshot(_ w: World, _ cx: Int, _ sy: Int, _ cz: Int) -> MeshInput? {
        let P = 18
        var blocks = [UInt16](repeating: 0, count: P * P * P)
        var skyLight = [UInt8](repeating: 0, count: P * P * P)
        var blockLight = [UInt8](repeating: 0, count: P * P * P)
        var biomes = [UInt8](repeating: 0, count: BIOME_P * BIOME_P)
        let minY = w.info.minY
        let baseY = minY + sy * 16
        let baseX = cx * 16, baseZ = cz * 16
        // The biome halo (BIOME_H) is wider than the 1-cell block halo so the
        // mesher can blend biome colors — but it still spans the same 3x3 chunk
        // neighborhood, so no extra chunks need to be loaded.
        for dz in -BIOME_H...(15 + BIOME_H) {
            for dx in -BIOME_H...(15 + BIOME_H) {
                let wx = baseX + dx, wz = baseZ + dz
                guard let c = w.getChunkAt(wx, wz) else { return nil }
                let lx = posMod(wx, 16), lz = posMod(wz, 16)
                biomes[(dz + BIOME_H) * BIOME_P + (dx + BIOME_H)] = UInt8(c.biomeAt(lx, min(minY + w.info.height - 1, max(minY, baseY + 8)), lz))
                guard dx >= -1, dx <= 16, dz >= -1, dz <= 16 else { continue }
                for dy in -1...16 {
                    let wy = baseY + dy
                    let idx = ((dy + 1) * P + (dz + 1)) * P + (dx + 1)
                    if wy < minY || wy >= minY + w.info.height {
                        skyLight[idx] = wy >= minY + w.info.height ? 15 : 0
                    } else {
                        blocks[idx] = c.get(lx, wy, lz)
                        skyLight[idx] = UInt8(c.getSky(lx, wy, lz))
                        blockLight[idx] = UInt8(c.getBlockLight(lx, wy, lz))
                    }
                }
            }
        }
        return MeshInput(blocks: blocks, skyLight: skyLight, blockLight: blockLight, biomes: biomes)
    }

    /// drop every GPU mesh and re-mesh all lit chunks in the current dimension —
    /// used when the atlas/tint semantics change under us (resource pack swap)
    public func remeshAllLoaded() {
        guard hasWorld() else { return }
        host?.clearAllSections()
        meshJobs.removeAll()
        stalledSections.removeAll()
        unmeshedChunks.removeAll()
        meshCenter = nil
        for c in world.chunks.values where c.status == .lit {
            for s in 0..<c.sections {
                dirtySections[dim]!.insert(SectionPos(cx: c.cx, sy: s, cz: c.cz))
            }
        }
    }

    // ===========================================================================
    // Dimension travel
    // ===========================================================================
    private func moveToDimension(_ dest: Dim) {
        let from = world
        from.removeEntity(player)
        dim = dest
        let w = world
        player.world = w
        w.addEntity(player)
        host?.clearAllSections()
        meshJobs.removeAll()
        // re-mesh everything already loaded in the destination
        for c in w.chunks.values where c.status == .lit {
            for s in 0..<c.sections {
                dirtySections[dest]!.insert(SectionPos(cx: c.cx, sy: s, cz: c.cz))
            }
        }
        // LAN guests follow the host (they arrive after the host is placed)
        if let nh = netHost {
            DispatchQueue.main.async { nh.hostChangedDimension(from: from) }
        }
    }

    private func travelNetherPortal() {
        if traveling { return }
        traveling = true
        defer { traveling = false }
        let p = player!
        let fromDim = dim
        let destDim: Dim = fromDim == .nether ? .overworld : .nether
        let scale = DIMS[fromDim.rawValue].coordScale / DIMS[destDim.rawValue].coordScale
        let tx = p.x * scale, tz = p.z * scale
        let destW = worlds[destDim]!
        ensureChunksLoaded(destW, floorDiv(ifloor(tx), 16), floorDiv(ifloor(tz), 16), 1)
        let (px, py, pz) = findOrCreatePortal(
            destW, tx,
            clampD(p.y, Double(destW.info.minY + 4), Double(destW.info.minY + destW.info.height - 8)), tz)
        moveToDimension(destDim)
        p.setPos(px, py, pz)
        p.vx = 0; p.vy = 0; p.vz = 0
        p.portalCooldown = 200
        p.portalTicks = 0
        p.insidePortalKind = nil
        host?.playSound("block.portal.travel", px, py, pz, 1, 1)
        advance("nether_root")
    }

    private func travelEndPortal() {
        if traveling { return }
        traveling = true
        defer { traveling = false }
        let p = player!
        if dim != .end {
            let end = worlds[.end]!
            ensureChunksLoaded(end, floorDiv(100, 16), 0, 1)
            let (px, py, pz) = buildEndSpawnPlatform(end)
            moveToDimension(.end)
            p.setPos(px, py, pz)
            p.vx = 0; p.vy = 0; p.vz = 0
            p.portalCooldown = 200
            p.insidePortalKind = nil
            advance("enter_end")
            // first visit: the fight begins
            if !(worldRec?.dragonKilled ?? false) && !dragonSpawned {
                ensureChunksLoaded(end, 0, 0, 2)
                let dragon = spawnMob(end, "ender_dragon", 0.5, 90, 0.5, nil) as? EnderDragon
                if let dragon { armDragon(dragon) }
                dragonSpawned = true
            }
        } else {
            // leaving the End: drop at world spawn (credits-free return)
            let ow = worlds[.overworld]!
            ensureChunksLoaded(ow, floorDiv(Int(ow.spawnX), 16), floorDiv(Int(ow.spawnZ), 16), 1)
            moveToDimension(.overworld)
            p.setPos(ow.spawnX + 0.5, Double(ow.surfaceY(Int(ow.spawnX), Int(ow.spawnZ))), ow.spawnZ + 0.5)
            p.vx = 0; p.vy = 0; p.vz = 0
            p.portalCooldown = 200
            p.insidePortalKind = nil
        }
    }

    private func armDragon(_ dragon: EnderDragon) {
        dragonSpawned = true
        dragon.onDeath = { [weak self] _ in
            guard let self, let end = self.worlds[.end] else { return }
            activateEndPortal(end)
            let n = self.worldRec?.gatewaysSpawned ?? 0
            self.worldRec?.gatewaysSpawned = n + 1
            spawnEndGateway(end, n)
            self.worldRec?.dragonKilled = true
            self.advance("kill_dragon")
            self.host?.pushChat("§dThe Ender Dragon has been defeated!")
        }
    }

    private func tickPortals() {
        let p = player!
        if p.portalCooldown > 0 {
            p.insidePortalKind = nil
            return
        }
        let bb = p.bb()
        var inNether = false, inEnd = false
        var inGateway: BlockEntityData? = nil
        let x0 = ifloor(bb.x0), x1 = ifloor(bb.x1)
        let y0 = ifloor(bb.y0), y1 = ifloor(bb.y1)
        let z0 = ifloor(bb.z0), z1 = ifloor(bb.z1)
        let w = world
        for y in y0...y1 {
            for z in z0...z1 {
                for x in x0...x1 {
                    let id = w.getBlockId(x, y, z)
                    if id == Int(B.nether_portal) { inNether = true }
                    else if id == Int(B.end_portal) { inEnd = true }
                    else if id == Int(B.end_gateway) {
                        if let be = w.getBlockEntity(x, y, z), be.type == "end_gateway" { inGateway = be }
                    }
                }
            }
        }
        if let be = inGateway {
            if traveling { return }
            traveling = true
            defer { traveling = false }
            p.portalCooldown = 200
            let exitX = be.exitX ?? 0, exitZ = be.exitZ ?? 0
            ensureChunksLoaded(w, floorDiv(exitX, 16), floorDiv(exitZ, 16), 1)
            let sy = w.surfaceY(exitX, exitZ)
            p.setPos(Double(exitX) + 0.5,
                     (be.exactTeleport ?? false) ? Double(be.exitY ?? 0) : Double(max(sy, 50)),
                     Double(exitZ) + 0.5)
            p.vx = 0; p.vy = 0; p.vz = 0
            host?.playSound("block.portal.travel", p.x, p.y, p.z, 1, 1)
            advance("enter_gateway")
            return
        }
        if inEnd {
            travelEndPortal()
            return
        }
        if inNether {
            p.insidePortalKind = "nether"
            p.portalTicks += 1
            let wait = p.gameMode == GameMode.creative ? 1 : 80
            if p.portalTicks >= wait { travelNetherPortal() }
        } else {
            p.insidePortalKind = nil
        }
    }

    // ===========================================================================
    // Tick
    // ===========================================================================
    private func tick() {
        if !inWorld { return }
        netHost?.processInbox()
        if let nc = netClient {
            nc.pump()
            if !inWorld { return } // kicked
        }
        let w = world
        let p = player!
        let guest = netClient != nil
        // a LAN game never pauses — others are still playing
        paused = (host?.screenPausesGame() ?? false) && !isNetworked
        if paused { return }

        if !guest { streamChunks() }

        // ---- player intent ----
        let playerDead = p.dead || p.deathTime > 0
        let blocked = (host?.hasScreen() ?? false) || playerDead || p.sleepTicks > 0
        if !blocked {
            func k(_ b: String) -> Bool { keys.contains(keybinds[b] ?? "") }
            p.moveForward = (k("forward") ? 1 : 0) + (k("back") ? -1 : 0)
            // applyInput's strafe basis points +strafe to the LEFT of the view
            // direction (golden baselines shipped the same quirk) — flip here so D=right
            p.moveStrafe = (k("right") ? -1 : 0) + (k("left") ? 1 : 0)
            if let a = analogMove {
                p.moveForward = clampD(p.moveForward + a.forward, -1, 1)
                p.moveStrafe = clampD(p.moveStrafe - a.right, -1, 1)
            }
            // vanilla: eating / drawing a bow slows movement to 20%
            if p.usingItem {
                p.moveForward *= 0.2
                p.moveStrafe *= 0.2
            }
            p.jumping = k("jump")
            p.sneaking = k("sneak") && !p.flying
            let wantSprint = (k("sprint") || sprintHeld) && p.moveForward > 0 && p.hunger > 6 && !p.sneaking
            if wantSprint && !p.sprinting && p.moveForward > 0 { p.sprinting = true }
            if !wantSprint || p.moveForward <= 0 || p.horizontalCollision { p.sprinting = false }
            sprintHeld = p.sprinting
            // creative flight vertical
            if p.flying {
                p.vy = (k("jump") ? 0.35 : 0) + (k("sneak") ? -0.35 : 0)
            }
            // elytra start: jump while airborne
            if k("jump") && !p.onGround && !p.elytraFlying && p.vy < 0 && !p.flying {
                if p.startElytra() {
                    host?.playSound("item.armor.equip_elytra", p.x, p.y, p.z, 1, 1)
                }
            }
        } else {
            p.moveForward = 0
            p.moveStrafe = 0
            p.jumping = false
            p.sprinting = false
        }

        // ---- player physics & state ----
        if !p.x.isFinite || !p.y.isFinite || !p.z.isFinite {
            // physics blowup — recover instead of rendering nothing forever
            p.setPos(w.spawnX + 0.5, max(p.prevY.isFinite ? p.prevY : w.spawnY, w.spawnY), w.spawnZ + 0.5)
            p.vx = 0; p.vy = 0; p.vz = 0
        }
        let feetReady = w.isChunkReady(floorDiv(ifloor(p.x), 16), floorDiv(ifloor(p.z), 16))
        if !playerDead && (!feetReady || traveling) {
            // the world doesn't exist under the player yet — hold them in place
            p.prevX = p.x; p.prevY = p.y; p.prevZ = p.z
            p.vx = 0; p.vy = 0; p.vz = 0
            p.fallDistance = 0
            heldForChunks = true
        } else if !playerDead {
            if heldForChunks {
                heldForChunks = false
                // if the hold began mid-fall through unloaded terrain, the player may
                // now be inside solid blocks or under the world — surface them
                let bx = ifloor(p.x), bz = ifloor(p.z)
                let inSolid = blockDefs[w.getBlockId(bx, ifloor(p.y), bz)].solid ||
                    blockDefs[w.getBlockId(bx, ifloor(p.y + 1), bz)].solid
                if p.y < Double(w.info.minY + 1) || inSolid {
                    p.setPos(p.x, Double(w.surfaceY(bx, bz)), p.z)
                }
            }
            p.tick()
            if let v = p.vehicle {
                p.setPos(v.x, v.y + v.height * 0.6, v.z)
                p.fallDistance = 0
                p.vx = 0; p.vy = 0; p.vz = 0
            } else if p.flying {
                // creative flight: friction-only horizontal w/ input
                let speed = p.sprinting ? 0.05 : 0.025
                let sin = detSin(p.yaw), cos = detCos(p.yaw)
                p.vx += (p.moveStrafe * cos - p.moveForward * sin) * speed * 2.5
                p.vz += (p.moveForward * cos + p.moveStrafe * sin) * speed * 2.5
                p.move(p.vx, p.vy, p.vz)
                p.vx *= 0.85; p.vy *= 0.6; p.vz *= 0.85
                p.fallDistance = 0
                if p.onGround { p.flying = false }
            } else if p.elytraFlying {
                p.move(p.vx, p.vy, p.vz)
            } else if p.sleepTicks <= 0 {
                p.travel()
            }
            if p.sprinting { p.addExhaustion(0.0) }
        } else {
            p.tickDeath()
            if !deathScreenShown {
                deathScreenShown = true
                host?.closeAllScreens()
                host?.openDeathScreen(deathCauseText(p.data.deathCause, p.data.deathAttacker))
                host?.releasePointer()
            }
        }

        // ---- world & entities ----
        if guest {
            // the host simulates; we keep the clock running between its syncs
            w.time += 1
            if w.rule("doDaylightCycle") && w.info.hasSky { w.dayTime = (w.dayTime + 1) % DAY_LENGTH }
            w.light.flush()
            netClient!.tickCopies()
            tickShake()
        } else {
            netHost?.tickProxies()
            w.tick()
            tickCarveJobs()
            tickWipes()
            tickShake()
            let simR = Double(w.simDistance * 16) * Double(w.simDistance * 16)
            let players: [Player] = [p] + (netHost?.proxies ?? [])
            for e in Array(w.entities) {
                if e === p || e.dead { continue }
                guard let ent = e as? Entity else { continue }
                if ent.isNetProxy { continue } // a guest's player: moved by the guest
                var near = ALWAYS_TICK.contains(ent.type)
                for pl in players where !near {
                    let dx = ent.x - pl.x, dz = ent.z - pl.z
                    near = dx * dx + dz * dz <= simR
                }
                if !near { continue }
                ent.tick()
                // sculk catalyst blooms on death
                if let liv = ent as? LivingEntity, liv.deathTime == 1 {
                    tryCatalystBloom(w, ent.x, ent.y, ent.z, liv.xpReward)
                }
            }
            for e in Array(w.entities) where e.dead && !((e as? Entity)?.isNetProxy ?? false) {
                w.removeEntity(e)
            }

            // ---- per-tick systems ----
            let living = [p] + (netHost?.liveProxies ?? [])
            tickEntityTriggers(w)
            tickFangs(w)
            // (updateDaylightDetectors is a no-op — detectors self-schedule ticks)
            naturalSpawnTick(w, living, &w.rng)
            raidManager.tick(w)
            if w.time % 1200 == 0 && dim == .overworld { tryPatrolSpawn(w, living, &w.rng) }
            raidManager.tryStartRaid(w, p)
        }
        tickWeatherEffects()
        if guest {
            // dimension travel follows the host for now
            if w.time % 40 == 0, ["nether", "end"].contains(portalUnderPlayer()) {
                host?.showActionBar("§eOnly the host can travel between dimensions in a LAN game", 60)
            }
        } else {
            tickPortals()
        }
        tickUsing()
        tickMining()
        tickViewBob()
        tickAmbience()
        tickAdvancementScan()
        tickBossBars()

        // toasts
        while !advancements.pendingToasts.isEmpty {
            host?.pushToast(advancements.pendingToasts.removeFirst())
        }

        // sleeping skips to morning (everyone in a LAN game has to be in bed)
        if !guest && p.sleepTicks > 100 && (netHost?.allGuestsSleeping ?? true) {
            p.sleepTicks = 0
            w.dayTime = 0
            if w.raining && w.rng.chance(0.6) {
                w.raining = false
                w.thundering = false
                w.weatherTimer = 12000
            }
            advance("sleep_in_bed")
            netHost?.wakeEveryone()
        }

        // hotbar name flash
        if p.selectedSlot != lastSlot {
            lastSlot = p.selectedSlot
            heldNameTime = 60
        } else if heldNameTime > 0 {
            heldNameTime -= 1
        }
        if useCooldown > 0 { useCooldown -= 1 }
        if breakCooldown > 0 { breakCooldown -= 1 }

        // portal overlay warp factor
        let targetWarp = p.insidePortalKind == "nether" ? min(1, Double(p.portalTicks) / 60) : 0
        portalWarp += (targetWarp - portalWarp) * 0.1

        if let nc = netClient {
            nc.sendTick()
            return
        }

        // batched unload writes — one transaction per second at most
        if !pendingChunkSaves.isEmpty && w.time % 20 == 0 {
            let batch = Array(pendingChunkSaves.values)
            pendingChunkSaves.removeAll()
            saveQueue.async { [weak self] in self?.writeChunkBatch(batch) }
        }

        // autosave
        ticksSinceSave += 1
        if ticksSinceSave >= SAVE_INTERVAL_TICKS {
            ticksSinceSave = 0
            saveAndFlush()
        }
        netHost?.flushTick()
    }

    /// "nether" / "end" when the player stands in a portal
    private func portalUnderPlayer() -> String? {
        let p = player!
        let w = world
        for y in ifloor(p.y)...ifloor(p.y + 1) {
            let id = w.getBlockId(ifloor(p.x), y, ifloor(p.z))
            if id == Int(B.nether_portal) { return "nether" }
            if id == Int(B.end_portal) || id == Int(B.end_gateway) { return "end" }
        }
        return nil
    }

    private func tryCatalystBloom(_ w: World, _ x: Double, _ y: Double, _ z: Double, _ xp: Int) {
        let bx = ifloor(x), by = ifloor(y), bz = ifloor(z)
        for dy in -4...4 {
            for dz in -4...4 {
                for dx in -4...4 {
                    if w.getBlockId(bx + dx, by + dy, bz + dz) == Int(B.sculk_catalyst) {
                        sculkBloom(w, bx + dx, by + dy, bz + dz, xp)
                        advance("avoid_warden")
                        return
                    }
                }
            }
        }
    }

    private func tickWeatherEffects() {
        let w = world
        if dim != .overworld { return }
        let p = player!
        // lightning strikes
        if !w.isRemote && w.thundering && w.rng.chance(0.00004 * w.thunderLevel * 16) {
            let x = ifloor(p.x + (w.rng.nextFloat() - 0.5) * 160)
            let z = ifloor(p.z + (w.rng.nextFloat() - 0.5) * 160)
            if w.isLoadedAt(x, z) {
                let y = w.surfaceY(x, z)
                if w.canSeeSky(x, y, z) {
                    spawnLightningFn?(w, Double(x) + 0.5, Double(y), Double(z) + 0.5)
                }
            }
        }
        // snow/ice accumulation + fire spread damp: sample random loaded columns
        if w.rainLevel > 0.5 && !w.isRemote {
            for _ in 0..<4 {
                let x = ifloor(p.x + (w.rng.nextFloat() - 0.5) * 128)
                let z = ifloor(p.z + (w.rng.nextFloat() - 0.5) * 128)
                if w.isLoadedAt(x, z) { weatherRandomTick(w, x, z) }
            }
        }
        // precipitation particles near the camera (cosmetic randomness stays native)
        if w.rainLevel > 0.2 && settings.particles > 0 {
            let n = Int((6 * w.rainLevel).rounded())
            for _ in 0..<n {
                let x = p.x + (Double.random(in: 0..<1) - 0.5) * 18
                let z = p.z + (Double.random(in: 0..<1) - 0.5) * 18
                let bx = ifloor(x), bz = ifloor(z)
                if !w.isLoadedAt(bx, bz) { continue }
                let top = Double(w.heightAt(bx, bz) + 1)
                if top > p.y + 14 || top < p.y - 20 { continue }
                let biome = w.biomeAt(bx, ifloor(p.y), bz)
                if snowsAt(biome, Int(top)) {
                    host?.spawnPrecipitation("snow", x, p.y + 8 + Double.random(in: 0..<4), z, 0)
                } else if (BIOMES[biome]?.downfall ?? 1) > 0.05 {
                    host?.spawnPrecipitation("rain", x, top + 4 + Double.random(in: 0..<8), z, top)
                }
            }
        }
    }

    /// per-tick walk-bob state, vanilla-style smoothed amplitude
    private func tickViewBob() {
        let p = player!
        prevBobPhase = bobPhase
        prevBobAmp = bobAmp
        let speed = min(0.4, detHyp(p.x - p.prevX, p.z - p.prevZ))
        bobAmp += (speed - bobAmp) * 0.4
        if p.onGround && p.vehicle == nil {
            bobPhase += bobAmp * 1.4
        }
        // smoothed FOV kick (vanilla eases toward the speed-scaled FOV)
        prevFovScale = fovScale
        let target = p.elytraFlying ? 1.12 : (p.sprinting ? 1.15 : (p.usingItem && itemUseSlows() ? 0.9 : 1.0))
        fovScale += (target - fovScale) * 0.5
    }

    /// screen shake from nearby blasts (decays ~15%/tick)
    private var shake = 0.0
    private func tickShake() {
        shake *= 0.85
        netHost?.broadcastBlasts(pendingBlasts)
        guard let p = player else { pendingBlasts.removeAll(); return }
        for (x, y, z, r) in pendingBlasts {
            let d = detHyp3(p.x - x, p.y - y, p.z - z)
            shake = max(shake, min(1.2, r * 2.5 / max(6, d)))
        }
        pendingBlasts.removeAll()
    }

    /// bows/spyglass zoom-slow while charging
    private func itemUseSlows() -> Bool {
        guard let held = player?.mainHand else { return false }
        let n = itemDef(held.id).name
        return n == "bow" || n == "spyglass" || n == "crossbow" || n == "trident"
    }

    // ---- held item use / eating / brushing ----
    private func tickUsing() {
        let p = player!
        if p.dead || p.deathTime > 0 || (host?.hasScreen() ?? false) {
            if p.usingItem { p.usingItem = false; p.useItemHand = "main" }
            return
        }
        let ctx = interactCtx()
        if p.usingItem {
            if !rightDown {
                releaseUse(ctx)
            } else {
                p.useItemTicks += 1
                let held = p.usingHandStack
                let def = held.map { itemDef($0.id) }
                if def?.name == "mining_laser" {
                    // a guest's beam burns on the host (its usingItem flag is synced)
                    if !isGuest { fireLaser(world, p, wide: p.sneaking, tick: p.useItemTicks) }
                } else if let def, def.food != nil || def.name == "potion" || def.name == "milk_bucket" {
                    if p.useItemTicks % 4 == 0 {
                        host?.playSound("entity.generic.eat", p.x, p.y, p.z, 0.4, 0.9 + Double.random(in: 0..<0.3))
                    }
                    if p.useItemTicks >= 32 { finishUsingItem(ctx) }
                }
            }
        } else if rightDown && useCooldown <= 0
                    && !ONE_SHOT_TOOLS.contains(p.mainHand.map { itemDef($0.id).name } ?? "") {
            // held use repeats (block placement etc.) every 4 ticks
            doUse()
            useCooldown = 4
        }
        // brushing suspicious blocks
        let held = p.mainHand
        if rightDown, let held, itemDef(held.id).name == "brush", !p.usingItem {
            let hit = crosshairBlock()
            if let hit, (hit.cell >> 4) == Int(B.suspicious_sand) || (hit.cell >> 4) == Int(B.suspicious_gravel) {
                brushTicks += 1
                let w = world
                if brushTicks % 5 == 0 {
                    host?.playSound("item.brush.brushing", Double(hit.x), Double(hit.y), Double(hit.z), 0.8, 1)
                    w.hooks.addParticles("block", hit.px, hit.py, hit.pz, 4, 0.15, hit.cell)
                }
                if brushTicks >= 10 {
                    brushTicks = 0
                    var be = w.getBlockEntity(hit.x, hit.y, hit.z)
                    if be == nil || be!.type != "brushable" {
                        be = makeBrushableBE(hit.x, hit.y, hit.z, "trail_ruins_common", Int(hash3(w.seed, hit.x, hit.y, hit.z)))
                        w.setBlockEntity(be!)
                    }
                    let brushable = be!
                    brushable.dusted = (brushable.dusted ?? 0) + 1
                    if (brushable.dusted ?? 0) >= 4 {
                        if brushable.item == nil {
                            var rng = RandomX(UInt32(truncatingIfNeeded: brushable.lootSeed ?? 0))
                            let loot = rollLoot(brushable.lootTable ?? "trail_ruins_common", &rng, luck: 0)
                            brushable.item = loot.first ?? ItemStack(iid("stick"), 1)
                        }
                        let isGravel = (hit.cell >> 4) == Int(B.suspicious_gravel)
                        netClient?.sendBrush(hit.x, hit.y, hit.z)
                        world.setBlock(hit.x, hit.y, hit.z, Int(cell(isGravel ? B.gravel : B.sand)))
                        spawnItem(world, Double(hit.x) + 0.5, Double(hit.y) + 0.6, Double(hit.z) + 0.5, brushable.item!)
                        if itemDef(brushable.item!.id).name.hasSuffix("_pottery_sherd") { advance("brush_sherd") }
                        if itemDef(brushable.item!.id).name == "sniffer_egg" { advance("sniffer_egg") }
                        host?.playSound("block.suspicious_sand.break", Double(hit.x), Double(hit.y), Double(hit.z), 1, 1)
                    }
                }
            } else {
                brushTicks = 0
            }
        } else if !rightDown {
            brushTicks = 0
        }
    }

    // ---- mining ----
    private func tickMining() {
        let p = player!
        if !leftDown || p.dead || p.deathTime > 0 || (host?.hasScreen() ?? false) {
            p.breakingProgress = -1
            return
        }
        let hitOpt = crosshairBlock()
        targetedBlock = hitOpt.map { ($0.x, $0.y, $0.z, $0.cell) }
        guard let hit = hitOpt else {
            p.breakingProgress = -1
            return
        }
        let w = world
        let def = blockDefs[hit.cell >> 4]
        if def.hardness < 0 && p.gameMode != GameMode.creative {
            p.breakingProgress = -1
            return
        }
        if p.gameMode == GameMode.creative {
            let delayTicks = Int((creativeBreakDelay * 1000 / TICK_MS).rounded())
            if delayTicks <= 0 {
                if breakCooldown <= 0 {
                    netClient?.sendBreak(hit.x, hit.y, hit.z)
                    finishBreaking(interactCtx(), hit.x, hit.y, hit.z)
                    breakCooldown = 5
                }
                return
            }
            // a short erode with the crack overlay, so the player sees what
            // they're digging and can look away (resets) or let go to keep it
            if breakCooldown > 0 {
                p.breakingProgress = -1
                return
            }
            if p.breakingProgress < 0 || p.breakingX != hit.x || p.breakingY != hit.y || p.breakingZ != hit.z {
                p.breakingX = hit.x; p.breakingY = hit.y; p.breakingZ = hit.z
                p.breakingProgress = 0
            }
            p.breakingProgress += 1 / Double(delayTicks)
            p.attackAnim = 1
            if w.time % 4 == 0 {
                host?.playSound("block.\(def.sound).hit", Double(hit.x) + 0.5, Double(hit.y) + 0.5, Double(hit.z) + 0.5, 0.25, 0.6)
                w.hooks.addParticles("block", hit.px, hit.py, hit.pz, 1, 0.12, hit.cell)
            }
            if p.breakingProgress >= 1 - 1e-9 {
                netClient?.sendBreak(hit.x, hit.y, hit.z)
                finishBreaking(interactCtx(), hit.x, hit.y, hit.z)
                p.breakingProgress = -1
                breakCooldown = 1
            }
            return
        }
        if breakCooldown > 0 {
            p.breakingProgress = -1
            return
        }
        if p.breakingProgress < 0 || p.breakingX != hit.x || p.breakingY != hit.y || p.breakingZ != hit.z {
            p.breakingX = hit.x; p.breakingY = hit.y; p.breakingZ = hit.z
            p.breakingProgress = 0
        }
        p.breakingProgress += breakSpeed(p, hit.cell)
        p.attackAnim = 1
        if w.time % 4 == 0 {
            host?.playSound("block.\(def.sound).hit", Double(hit.x) + 0.5, Double(hit.y) + 0.5, Double(hit.z) + 0.5, 0.25, 0.6)
            w.hooks.addParticles("block", hit.px, hit.py, hit.pz, 1, 0.12, hit.cell)
        }
        if p.breakingProgress >= 1 {
            netClient?.sendBreak(hit.x, hit.y, hit.z)
            finishBreaking(interactCtx(), hit.x, hit.y, hit.z)
            trackBreakAdvancements(hit.cell >> 4)
            p.breakingProgress = -1
            breakCooldown = 3
            p.addExhaustion(0.005)
        }
    }

    private func trackBreakAdvancements(_ id: Int) {
        let name = blockDefs[id].name
        if name.hasSuffix("_log") || name.hasSuffix("_stem") { advance("mine_log") }
        if id == Int(B.stone) || id == Int(B.deepslate) { advance("mine_stone") }
        if id == Int(B.diamond_ore) || id == Int(B.deepslate_diamond_ore) { advance("mine_diamond") }
        if id == Int(B.ancient_debris) { advance("obtain_ancient_debris") }
    }

    /// periodic inventory / situation scan for item- & place-based advancements
    private func tickAdvancementScan() {
        let w = world
        let p = player!
        if w.time % 40 != 0 { return }
        func has(_ n: String) -> Bool {
            guard let id = iidOpt(n) else { return false }
            if p.inventory.contains(where: { $0?.id == id }) || p.offHand?.id == id { return true }
            return p.armor.contains { $0?.id == id }
        }
        if has("crafting_table") { advance("crafting_table") }
        if has("wooden_pickaxe") { advance("wooden_pickaxe") }
        if has("stone_pickaxe") { advance("stone_pickaxe") }
        if has("iron_ingot") { advance("iron_ingot") }
        if has("iron_pickaxe") { advance("iron_tools") }
        if has("iron_chestplate") || has("iron_helmet") || has("iron_leggings") || has("iron_boots") { advance("iron_armor") }
        if has("diamond") { advance("mine_diamond") }
        if has("diamond_chestplate") && has("diamond_helmet") && has("diamond_leggings") && has("diamond_boots") { advance("diamond_armor") }
        if has("blaze_rod") { advance("obtain_blaze_rod") }
        if has("ender_eye") { advance("ender_eye") }
        if has("dragon_egg") { advance("dragon_egg") }
        if has("elytra") { advance("elytra") }
        if has("ancient_debris") { advance("obtain_ancient_debris") }
        if has("netherite_helmet") && has("netherite_chestplate") && has("netherite_leggings") && has("netherite_boots") { advance("netherite_armor") }
        if has("nether_star") { advance("kill_wither") }
        if has("dragon_breath") { advance("dragon_breath") }
        if has("sniffer_egg") { advance("sniffer_egg") }
        if has("emerald") { advance("adventure_root") }
        if has("wheat_seeds") || has("wheat") { advance("husbandry_root") }
        // location-based
        if dim == .nether {
            let below = w.getBlockId(ifloor(p.x), ifloor(p.y) - 1, ifloor(p.z))
            if below == Int(B.nether_bricks) { advance("find_fortress") }
            if below == Int(B.polished_blackstone_bricks) || below == Int(B.gilded_blackstone) { advance("find_bastion") }
        }
    }

    private func tickBossBars() {
        let w = world
        var bars: [BossBarInfo] = []
        for e in w.entities {
            guard let ent = e as? Entity else { continue }
            if let d = ent as? EnderDragon {
                bars.append(BossBarInfo(name: "Ender Dragon", progress: d.health / d.maxHealth, color: "#e864e8"))
            } else if let d = ent as? WitherBoss {
                bars.append(BossBarInfo(name: "Wither", progress: d.health / d.maxHealth, color: "#7a7ab8"))
            }
        }
        for r in raidManager.raids {
            if r.world === w && r.active {
                bars.append(BossBarInfo(
                    name: "Raid",
                    progress: r.maxHealth > 0 ? min(1, r.totalHealth / max(1, r.maxHealth)) : 1,
                    color: "#e84040"))
            }
        }
        host?.setBossBars(bars)
    }

    private func tickAmbience() {
        let w = world
        let p = player!
        // audio environment
        let eyeBlock = w.getBlock(ifloor(p.x), ifloor(p.eyeY()), ifloor(p.z))
        let underwater = isWaterlogged(UInt16(eyeBlock))
        let sky = w.getSkyLight(ifloor(p.x), ifloor(p.y), ifloor(p.z))
        let caveFactor = dim == .overworld
            ? clampD(Double(8 - sky) / 8, 0, 1) * (p.y < 50 ? 1 : 0.4)
            : 0.3
        host?.setAudioEnvironment(underwater, caveFactor)
        host?.setAudioListener(p.x, p.eyeY(), p.z, p.yaw)
        // music mood
        var mood = "overworld"
        if dim == .nether { mood = "nether" }
        else if dim == .end { mood = "end" }
        else {
            let biome = w.biomeAt(ifloor(p.x), ifloor(p.y), ifloor(p.z))
            if biome == Int(Biome.deepDark.rawValue) { mood = "dark" }
            else if biome == Int(Biome.lushCaves.rawValue) { mood = "lush" }
            else if underwater { mood = "water" }
        }
        musicMood = mood
        host?.tickMusic(mood, (settings.volumes["music"] ?? 0) > 0.01)
    }

    // ===========================================================================
    // Interaction wiring
    // ===========================================================================
    private func interactCtx() -> InteractCtx {
        InteractCtx(
            world: world,
            player: player,
            openScreen: { [weak self] kind, data in self?.openScreen(kind, data) },
            advance: { [weak self] id in self?.advance(id) })
    }

    public func openScreen(_ kind: String, _ data: ScreenData?) {
        if kind == "toast" {
            host?.showActionBar(data?.text ?? "", 60)
            return
        }
        if let nc = netClient, let data {
            // container / sign edits go back to the host
            for be in [data.be, data.other].compactMap({ $0 }) { nc.watch(be.x, be.y, be.z) }
            if kind == "sign" { nc.watch(data.x, data.y, data.z) }
        }
        host?.openScreen(kind, data)
    }

    /// raycast the crosshair against blocks
    public func crosshairBlock() -> RaycastHit? {
        let p = player!
        let reach = p.gameMode == GameMode.creative ? REACH_CREATIVE : REACH_SURVIVAL
        let dx = -detSin(p.yaw) * detCos(p.pitch)
        let dy = -detSin(p.pitch)
        let dz = detCos(p.yaw) * detCos(p.pitch)
        return world.raycast(p.x, p.eyeY(), p.z, dx, dy, dz, reach)
    }

    /// nearest entity under the crosshair within attack reach
    private func crosshairEntity(_ maxDist: Double) -> Entity? {
        let p = player!
        let dx = -detSin(p.yaw) * detCos(p.pitch)
        let dy = -detSin(p.pitch)
        let dz = detCos(p.yaw) * detCos(p.pitch)
        let ox = p.x, oy = p.eyeY(), oz = p.z
        var best: Entity? = nil
        var bestT = maxDist
        let blockHit = world.raycast(ox, oy, oz, dx, dy, dz, maxDist)
        let blockT = blockHit?.t ?? maxDist
        for e in world.getEntitiesNear(ox, oy, oz, maxDist + 2) {
            if e === p || e.dead { continue }
            guard let ent = e as? Entity else { continue }
            if !(ent is LivingEntity) && !["boat", "minecart", "item_frame", "end_crystal"].contains(ent.type) { continue }
            let bb = ent.bb()
            if let t = rayBoxT(ox, oy, oz, dx, dy, dz,
                               bb.x0 - 0.1, bb.y0 - 0.1, bb.z0 - 0.1,
                               bb.x1 + 0.1, bb.y1 + 0.1, bb.z1 + 0.1),
               t < bestT && t < blockT {
                best = ent
                bestT = t
            }
        }
        return best
    }

    private func doAttack() {
        let p = player!
        if p.dead || p.deathTime > 0 || (host?.hasScreen() ?? false) { return }
        p.useItemHand = "main" // an attack always swings (and wears) the main hand
        let target = crosshairEntity(ATTACK_REACH)
        p.attackAnim = 1
        if let target, let nc = netClient {
            // the host lands the hit; we predict our side (cooldown, wear,
            // the target's flash) — only living things have a safe prediction
            nc.sendAttack(target)
            if target is LivingEntity {
                playerAttack(p, target)
            } else {
                p.resetAttackCooldown()
            }
            return
        }
        if let target {
            if target is LivingEntity || target.type == "end_crystal" {
                playerAttack(p, target)
            } else if target.type == "boat" || target.type == "minecart" {
                _ = target.hurt(2, .player, p)
            }
            return
        }
        host?.playSound("entity.player.attack.sweep", p.x, p.y, p.z, 0.3, 1.2)
    }

    private func doUse() {
        let p = player!
        if p.dead || p.deathTime > 0 || (host?.hasScreen() ?? false) { return }
        let target = crosshairEntity(REACH_SURVIVAL - 1)
        let hit = crosshairBlock()
        if let nc = netClient {
            nc.sendUse(target, hit)
            // big world tools run on the host only — just pay for them here
            let heldName = p.mainHand.map { itemDef($0.id).name } ?? ""
            if HOST_ONLY_TOOLS.contains(heldName) {
                p.attackAnim = 0.6
                if heldName == "void_bomb" || (heldName == "quarry_charge" && hit != nil) { p.consumeHeld(1) }
                return
            }
        }
        performUse(p, interactCtx(), target: target, hit: hit)
    }

    /// the right-click ladder: entity, then block, then held item, then the
    /// off hand. Shared with the LAN host, which replays guests' clicks.
    @discardableResult
    func performUse(_ p: Player, _ ctx: InteractCtx, target: Entity?, hit: RaycastHit?) -> Bool {
        p.useItemHand = "main"
        if p.mainHand.map({ itemDef($0.id).name }) == "infinity_wipe" {
            useInfinityWipe(p)
            p.attackAnim = 0.6
            return true
        }
        // entities first
        if let target, !p.sneaking {
            if target.interact(p, p.mainHand) {
                p.attackAnim = 0.6
                return true
            }
        }
        let heldName = p.mainHand.map { itemDef($0.id).name }
        let destroyer = ["bazooka", "mining_laser", "void_bomb", "quarry_charge", "wall_builder", "box_builder"].contains(heldName) // fire, don't open doors/chests
        if let hit, !destroyer, !p.sneaking || p.mainHand == nil {
            if useBlock(ctx, hit) {
                p.attackAnim = 0.6
                return true
            }
        }
        if useItem(ctx, hit) {
            p.attackAnim = 0.6
            return true
        }
        // offhand fallback: retry the held-item use with the offhand item
        // (food, shield, torches/blocks, throwables, …) when the main hand did nothing.
        if p.offHand != nil {
            p.useItemHand = "off"
            let used = useItem(ctx, hit)
            if !p.usingItem { p.useItemHand = "main" } // keep "off" only for an ongoing use
            if used { p.attackAnim = 0.6; return true }
        }
        if !p.usingItem { p.useItemHand = "main" }
        return false
    }

    /// let go of a drawn bow / trident / eaten item (a guest tells the host too)
    private func releaseUse(_ ctx: InteractCtx) {
        let p = player!
        netClient?.sendRelease(p.useItemTicks, p.useItemHand)
        releaseUsingItem(ctx)
    }

    private func pickBlock() {
        let p = player!
        guard let hit = crosshairBlock() else { return }
        let raw = blockToItem[hit.cell >> 4]
        if raw < 0 { return }
        let itemId = Int(raw)
        // already in hotbar?
        for i in 0..<9 {
            if p.inventory[i]?.id == itemId {
                p.selectedSlot = i
                return
            }
        }
        if p.gameMode == GameMode.creative {
            p.inventory[p.selectedSlot] = ItemStack(itemId, 1)
        } else {
            for i in 9..<36 {
                if p.inventory[i]?.id == itemId {
                    let tmp = p.inventory[p.selectedSlot]
                    p.inventory[p.selectedSlot] = p.inventory[i]
                    p.inventory[i] = tmp
                    return
                }
            }
        }
    }

    // ===========================================================================
    // Input — the app forwards events here when no screen is open
    // ===========================================================================
    public func mouseDown(_ button: Int) {
        guard inWorld, !(host?.hasScreen() ?? false) else { return }
        if button == 0 {
            leftDown = true
            player?.breakingProgress = -1   // a fresh press starts a fresh crack
            doAttack()
        } else if button == 1 {
            pickBlock()
        } else if button == 2 {
            rightDown = true
            doUse()
            useCooldown = 4
        }
    }

    public func mouseUp(_ button: Int) {
        if button == 0 { leftDown = false }
        if button == 2 {
            rightDown = false
            if player?.usingItem == true { releaseUse(interactCtx()) }
        }
    }

    public func mouseDelta(_ dx: Double, _ dy: Double) {
        guard inWorld, !(host?.hasScreen() ?? false), let p = player else { return }
        let sens = 0.0008 + settings.sensitivity * 0.004
        p.yaw += dx * sens
        p.pitch += dy * sens * (settings.invertY ? -1 : 1)
        p.pitch = clampD(p.pitch, -Double.pi / 2 + 0.001, Double.pi / 2 - 0.001)
    }

    /// touch controls: does a tap at the crosshair hit something to attack?
    public var crosshairOnEntity: Bool {
        guard inWorld, player != nil else { return false }
        return crosshairEntity(ATTACK_REACH) != nil
    }

    /// touch controls: the held item does something while use is HELD (eat,
    /// drink, draw a bow, raise a shield), so a long press means use, not break
    public var heldItemUsesOnHold: Bool {
        guard let p = player, let s = p.mainHand else { return false }
        let def = itemDefs[s.id]
        if def.food != nil { return true }
        return ["potion", "bow", "trident", "crossbow", "shield", "spyglass", "goat_horn", "mining_laser"].contains(def.name)
    }

    public func wheelHotbar(_ dir: Int) {
        guard inWorld, let p = player else { return }
        p.selectedSlot = posMod(p.selectedSlot + dir, 9)
    }

    /// world-mode keydown (app already routed screen input elsewhere).
    /// `now` is a monotonic millisecond clock for double-tap detection.
    public func keyDown(_ code: String, now: Double, ctrlOrCmd: Bool = false) {
        guard inWorld else { return }
        keys.insert(code)
        let p = player!
        // while sleeping, swallow input — Escape/Sneak/Jump leave the bed
        if p.sleepTicks > 0 {
            if code == "Escape" || code == keybinds["sneak"] || code == keybinds["jump"] {
                p.sleepTicks = 0
                p.bedPos = nil
                host?.playSound("block.wood.step", p.x, p.y, p.z, 0.4, 1)
            }
            return
        }
        if code == "Escape" {
            host?.openPauseScreen()
            host?.releasePointer()
        } else if code == keybinds["perspective"] {
            perspective = (perspective + 1) % 3
        } else if code == keybinds["inventory"] {
            if p.gameMode == GameMode.creative {
                host?.openScreen("creative", nil)
            } else {
                host?.openScreen("inventory", nil)
            }
        } else if code == keybinds["chat"] {
            host?.openChat("")
        } else if code == keybinds["command"] {
            host?.openChat("/")
        } else if code == keybinds["drop"] {
            p.dropSelected(ctrlOrCmd)
        } else if code == keybinds["swapOffhand"] {
            let tmp = p.offHand
            p.offHand = p.mainHand
            p.mainHand = tmp
        } else {
            // hotbar digits
            if code.hasPrefix("Digit"), code.count == 6, let n = Int(code.suffix(1)), n >= 1, n <= 9 {
                p.selectedSlot = n - 1
            }
            // double-space → toggle creative flight
            if code == keybinds["jump"] {
                if now - lastJumpPress < 280 && p.gameMode == GameMode.creative {
                    p.flying = !p.flying
                    if p.flying { p.vy = 0 }
                }
                lastJumpPress = now
            }
            if code == keybinds["sprint"] { sprintHeld = true }
        }
        // double-tap forward → sprint
        if code == keybinds["forward"] {
            if now - lastForwardPress < 250 { sprintHeld = true }
            lastForwardPress = now
        }
    }

    public func keyUp(_ code: String) {
        keys.remove(code)
        if code == keybinds["sprint"] { sprintHeld = player?.sprinting ?? false }
    }

    /// window blur / screen opened — release all held input
    public func clearInput() {
        keys.removeAll()
        analogMove = nil
        leftDown = false
        rightDown = false
    }

    // ===========================================================================
    // Frame pump — the app's render loop calls this once per frame
    // ===========================================================================
    /// Runs fixed-step sim ticks, then the budgeted light/mesh streamers.
    /// Returns the interpolation partial for rendering.
    public func frame(dtMs: Double) -> Double {
        guard inWorld else { return 0 }
        netClient?.pump()
        guard inWorld else { return 0 }
        accumulator += min(dtMs, 250)
        var steps = 0
        while accumulator >= TICK_MS && steps < 10 {
            LoadProf.shared.time("tick") { tick() }
            accumulator -= TICK_MS
            steps += 1
        }
        if steps >= 10 { accumulator = 0 }
        LoadProf.shared.time("lightQ") { processLightQueue() }
        LoadProf.shared.time("streamMesh") { streamMeshes() }
        LoadProf.shared.tickPrint()
        return paused ? 1 : clampD(accumulator / TICK_MS, 0, 1)
    }

    // ===========================================================================
    // Infinity wipe (the cut itself is in Systems/InfinityWipe.swift)
    // ===========================================================================
    /// first use arms it; a second use within 3 s fires it
    private func useInfinityWipe(_ p: Player) {
        let w = p.world
        if w.dim != .overworld { return tell(p, "§cThe Infinity Wipe only works in the Overworld") }
        if let t = wipeArmedAt[p.id], w.time - t <= 60 {
            wipeArmedAt[p.id] = nil
            fireWipe(w, p, p.sneaking ? WIPE_BIG_RADIUS : WIPE_RADIUS)
            return
        }
        wipeArmedAt[p.id] = w.time
        tell(p, "§c§lInfinity Wipe armed§r§c - use again within 3s to erase the land \(Int(WIPE_RADIUS)) blocks around you (sneak: \(Int(WIPE_BIG_RADIUS))). It can't be undone.")
        w.hooks.playSound("pebble.wipe.arm", p.x, p.y, p.z, 1, 1)
    }

    private func fireWipe(_ w: World, _ p: Player, _ radius: Double) {
        wipes.append(WipeZone(dim: w.dim.rawValue, x: p.x, z: p.z, radius: radius))
        wipeFronts.append((wipes.count - 1, 0))
        pendingBlasts.append((p.x, p.y, p.z, 60))
        w.hooks.playSound("pebble.wipe.blast", p.x, p.y, p.z, 12, 1)
        w.hooks.addParticles("explosion", p.x, p.y + 1, p.z, 60, 6, 0)
        let line = "§c\(p === player ? playerName : p.name) fired an Infinity Wipe (\(Int(radius)) blocks)"
        if let nh = netHost { nh.broadcastChat(line) } else { host?.pushChat(line) }
    }

    /// a note for one player: the local one's action bar, or a guest's chat
    private func tell(_ p: Player, _ msg: String) {
        if p === player { host?.showActionBar(msg, 100) }
        else if let c = p.netLink as? RemoteClient { netHost?.sendChat(c, msg) }
    }

    /// zones (indices into `wipes`) that still owe chunk (cx, cz) a cut
    private func wipesOwed(_ w: World, _ cx: Int, _ cz: Int) -> [Int] {
        if w.isRemote || wipes.isEmpty { return [] }
        let key = chunkKey(cx, cz)
        return wipes.indices.filter {
            wipes[$0].dim == w.dim.rawValue && wipes[$0].touches(cx, cz) && !wipes[$0].done.contains(key)
        }
    }

    /// a chunk just joined the world. `cutBy`: zones already applied to its
    /// blocks off the main thread; any other zone it owes (one fired while it
    /// was generating, or a synchronous load) is cut here
    private func wipeOnLoad(_ w: World, _ c: Chunk, cutBy: [Int], changed: Bool) {
        let key = chunkKey(c.cx, c.cz)
        for i in cutBy { wipes[i].done.insert(key) }
        if changed { dropWipedBlockEntities(w, c) }
        for i in wipesOwed(w, c.cx, c.cz) { wipeLoadedChunk(w, c, i) }
    }

    /// roll each shockwave outward, cutting loaded chunks as it reaches them.
    /// Chunks out of view are cut when they load (wipeOnLoad)
    private func tickWipes() {
        if wipeFronts.isEmpty { return }
        let started = CFAbsoluteTimeGetCurrent()
        for f in wipeFronts.indices {
            let zi = wipeFronts[f].zone
            let zone = wipes[zi]
            guard zone.dim == dim.rawValue else { continue }
            let w = world
            let target = min(zone.radius, wipeFronts[f].r + WIPE_SPEED)
            var due: [(Double, Chunk)] = []
            for c in w.chunks.values where c.status != .empty && !zone.done.contains(chunkKey(c.cx, c.cz)) {
                let d = zone.chunkDistance(c.cx, c.cz)
                if d <= target { due.append((d, c)) }
            }
            due.sort { $0.0 < $1.0 }
            var reached = target
            for (d, c) in due {
                // ~8 ms of cutting per tick; the front waits for the backlog
                if CFAbsoluteTimeGetCurrent() - started > 0.008 { reached = d; break }
                wipeLoadedChunk(w, c, zi)
            }
            wipeFronts[f].r = reached
            wipeFrontEffects(w, zone, reached)
        }
        wipeFronts.removeAll { $0.r >= wipes[$0.zone].radius }
    }

    /// dust and smoke along the front where anyone could see it, and a rumble
    private func wipeFrontEffects(_ w: World, _ zone: WipeZone, _ r: Double) {
        if r > 200 { return }
        let gen = overworldGen(w.seed)
        let n = max(12, Int(r / 3))
        for i in 0..<n {
            let a = Double(i) / Double(n) * 2 * .pi + Double(w.time % 7) * 0.1
            let x = zone.x + detCos(a) * r, z = zone.z + detSin(a) * r
            let y = Double(max(gen.refinedHeightEstimate(x, z) - WIPE_DEPTH, w.info.seaLevel) + 2)
            w.hooks.addParticles("explosion", x, y, z, 1, 2, 0)
            w.hooks.addParticles("smoke", x, y + 2, z, 3, 3, 0)
        }
        if w.time % 4 == 0 { pendingBlasts.append((zone.x, player.y, zone.z, 2)) }
    }

    /// cut a chunk that's already in the world, then relight, remesh, save
    /// and resend it — straight on the block array, not millions of setBlocks
    private func wipeLoadedChunk(_ w: World, _ c: Chunk, _ zi: Int) {
        wipes[zi].done.insert(chunkKey(c.cx, c.cz))
        var blocks = c.blocks
        guard wipeChunkBlocks(&blocks, c.cx, c.cz, minY: c.minY, height: c.height, seed: w.seed, zone: wipes[zi]) else { return }
        c.blocks = blocks
        dropWipedBlockEntities(w, c)
        let light = computeLocalLight(blocks: c.blocks, height: c.height, hasSky: w.info.hasSky)
        c.skyLight = light.sky
        c.blockLight = light.blk
        c.buildHeightmap()
        c.scanSpecials()
        if c.status == .lit && w.neighborsReady(c.cx, c.cz) {
            lightChunk(w, c)   // seams + remesh (this chunk and its neighbors)
        } else {
            c.status = .generated
            enqueueLightAround(w, c.cx, c.cz)
        }
        netHost?.resendChunk(c.cx, c.cz)
    }

    /// block entities whose block was cut go with it; the chunk saves
    private func dropWipedBlockEntities(_ w: World, _ c: Chunk) {
        for (i, be) in c.blockEntities where c.blocks[i] == 0 {
            w.untrackTickingBE(be)
            c.blockEntities.removeValue(forKey: i)
        }
        c.modified = true
    }

    // ===========================================================================
    // Mountains (Systems/Mountain.swift)
    // ===========================================================================
    /// pour a mountain centered on (x, z); the plan says how big it came out
    public func placeMountain(_ x: Int, _ z: Int, variant: Int) -> MountainPlan {
        let w = world
        // the whole footprint has to exist, and stay loaded while it rises
        let ccx = floorDiv(x, 16), ccz = floorDiv(z, 16), cr = MountainShape.reach / 16 + 1
        ensureChunksLoaded(w, ccx, ccz, cr)
        let baseY = groundLevel(w, x, z) - 1
        let plan = planMountain(w, cx: x, cz: z, baseY: baseY, variant: variant)
        if plan.keys.isEmpty { return plan }
        let job = startMountain(w, plan, players: { [weak self] in
            guard let self else { return [] }
            return [self.player] + (self.netHost?.proxies ?? [])
        })
        var keys = Set<Int64>()
        for dz in -cr...cr { for dx in -cr...cr { keys.insert(chunkKey(ccx + dx, ccz + dz)) } }
        mountainPins.append((job, keys))
        w.hooks.playSound("pebble.mountain.rise", Double(x) + 0.5, Double(baseY), Double(z) + 0.5, 10, 1)
        pendingBlasts.append((Double(x), Double(baseY), Double(z), 20))
        return plan
    }

    /// change our own game mode; a LAN host's guests follow it
    public func applyGameMode(_ mode: Int) {
        player.setGameMode(mode)
        player.flying = player.flying && mode == GameMode.creative
        if !player.isNetProxy { netHost?.broadcastGameMode(mode) }
    }

    // ===========================================================================
    // LAN multiplayer
    // ===========================================================================
    /// open the current world to the local network; returns the port
    @discardableResult
    public func hostLAN(port: UInt16 = NET_DEFAULT_PORT) throws -> UInt16 {
        if let nh = netHost { return nh.port }
        guard inWorld, !isGuest else { throw NetError.badFrame }
        let nh = NetHost(game: self)
        try nh.start(port: port, name: "\(playerName)'s world - \(worldRec?.name ?? "Pebble")")
        netHost = nh
        player.name = playerName
        for w in worlds.values {
            w.hooks.onBlockChanged = { [weak self, weak w] x, y, z, c in
                guard let self, let w, w === self.worlds[self.dim] else { return }
                self.netHost?.blockChanged(x, y, z, c)
            }
            w.onLocalSpawn = { [weak self] e in self?.netHost?.shouldSpawn(e) ?? true }
        }
        return nh.port
    }

    public func stopHosting() {
        guard let nh = netHost else { return }
        nh.stop()
        netHost = nil
        for w in worlds.values {
            w.hooks.onBlockChanged = nil
            w.onLocalSpawn = nil
            w.extraSimCenters = []
        }
    }

    public var lanPort: UInt16? { netHost?.port }
    /// a LAN host's render distance: it loads no farther around us than that
    public internal(set) var netHostView: Int?
    /// how far to draw: our render distance, or a LAN host's if that's shorter
    /// (beyond it no chunks arrive, so the fog belongs there)
    public var drawDistance: Int { min(settings.renderDistance, netHostView ?? settings.renderDistance) }
    public var lanGuests: [String] { netHost?.guestNames ?? [] }
    /// everyone in the LAN game, host first
    public var lanPlayers: [String] {
        if let nc = netClient { return nc.playerNames.isEmpty ? [nc.hostName, nc.name] : nc.playerNames }
        return [playerName] + lanGuests
    }
    /// say something to everyone in the LAN game
    public func lanChat(_ text: String) {
        if let nc = netClient { nc.sendChat(text) }
        else if let nh = netHost { nh.broadcastChat("<\(playerName)> \(text)") }
    }

    /// connect to a LAN game by address; the world opens when the host answers
    @discardableResult
    public func joinLAN(host: String, port: UInt16 = NET_DEFAULT_PORT) -> NetClient {
        startJoin(NetConn(host: host, port: port))
    }
    @discardableResult
    public func joinLAN(_ game: LANGame) -> NetClient {
        startJoin(NetConn(endpoint: game.endpoint))
    }
    private func startJoin(_ conn: NetConn) -> NetClient {
        if inWorld { exitToTitle() }
        netClient?.disconnect()
        netEndMessage = nil
        netHostView = nil
        let nc = NetClient(game: self, conn: conn, name: playerName)
        netClient = nc
        return nc
    }
    /// give up on a join in progress
    public func cancelJoin() {
        if inWorld { return }
        netClient?.disconnect()
        netClient = nil
    }

    /// the host accepted us: build a world shell that the host will fill
    func enterRemoteWorld(_ nc: NetClient, name: String, seed: Int32, dim d: Dim, mode: Int,
                          pos: (Double, Double, Double, Double, Double), spawn: (Int, Int, Int),
                          saved: [String: Any]?) {
        var rec = WorldRecord(id: "lan-guest", name: name, seed: seed, gameMode: mode, difficulty: 2)
        rec.spawnX = spawn.0; rec.spawnY = spawn.1; rec.spawnZ = spawn.2
        worldRec = rec
        wipes = []
        wipeFronts = []
        advancements = AdvancementTracker()
        dragonSpawned = false
        worlds.removeAll()
        for dd in [Dim.overworld, .nether, .end] {
            let w = World(dim: dd, seed: UInt32(bitPattern: seed))
            w.spawnX = Double(spawn.0); w.spawnY = Double(spawn.1); w.spawnZ = Double(spawn.2)
            w.isRemote = true
            w.randomTickSpeed = 0
            hookWorld(w)
            w.onLocalSpawn = { [weak nc] e in nc?.localSpawn(e) ?? false }
            worlds[dd] = w
        }
        dim = d
        let w = world
        player = Player(world: w)
        player.name = nc.name
        if let saved {
            player.load(saved)
        }
        player.setGameMode(mode)   // the host's mode, not the one we last saved in
        player.setPos(pos.0, pos.1, pos.2)
        if saved == nil { player.yaw = pos.3; player.pitch = pos.4 }
        w.addEntity(player)
        inWorld = true
        deathScreenShown = false
        ticksSinceSave = 0
        host?.showActionBar("§eJoined \(nc.hostName)'s world - \(name)", 80)
    }

    /// a chunk from the host (already decoded and locally lit off-main)
    func netAdoptChunk(_ c: Chunk, _ bes: [BlockEntityData]) {
        let w = world
        if let old = w.getChunk(c.cx, c.cz) {
            // a resend after a big edit replaces what we had
            w.releaseChunkBlockEntities(old)
            w.removeChunk(old.cx, old.cz)
            host?.removeChunkMeshes(old.cx, old.cz, old.sections)
        }
        w.setChunk(c)
        for be in bes { c.setBlockEntity(posMod(be.x, 16), be.y, posMod(be.z, 16), be) }
        c.modified = false
        enqueueLightAround(w, c.cx, c.cz)
        // neighbors' border faces depend on this chunk
        for (nx, nz) in [(c.cx - 1, c.cz), (c.cx + 1, c.cz), (c.cx, c.cz - 1), (c.cx, c.cz + 1)] {
            if let n = w.getChunk(nx, nz), n.status == .lit {
                for s in 0..<n.sections { dirtySections[w.dim]!.insert(SectionPos(cx: nx, sy: s, cz: nz)) }
            }
        }
    }

    func netDropChunk(_ cx: Int, _ cz: Int) {
        let w = world
        guard let c = w.getChunk(cx, cz) else { return }
        w.releaseChunkBlockEntities(c)
        w.removeChunk(cx, cz)
        host?.removeChunkMeshes(cx, cz, c.sections)
        lightQueue[w.dim]!.remove(chunkKey(cx, cz))
        for s in 0..<c.sections { dirtySections[w.dim]!.remove(SectionPos(cx: cx, sy: s, cz: cz)) }
    }

    /// the host changed dimension and took us along
    func netChangeDim(_ d: Dim, _ x: Double, _ y: Double, _ z: Double) {
        let from = world
        for c in Array(from.chunks.values) { netDropChunk(c.cx, c.cz) }
        if d != dim {
            from.removeEntity(player)
            dim = d
            player.world = world
            world.addEntity(player)
            host?.clearAllSections()
            meshJobs.removeAll()
        }
        player.setPos(x, y, z)
        player.vx = 0; player.vy = 0; player.vz = 0
    }

    /// the connection to the host ended (kick, host quit, network error)
    func netClientClosed(_ nc: NetClient, _ why: String) {
        guard netClient === nc else { return }
        netClient = nil
        netEndMessage = why
        if inWorld {
            inWorld = false
            worldRec = nil
            worlds.removeAll()
            for d in dirtySections.keys { dirtySections[d]!.removeAll() }
            stalledSections.removeAll()
        unmeshedChunks.removeAll()
        meshCenter = nil
            for d in lightQueue.keys { lightQueue[d]!.removeAll() }
            meshJobs.removeAll()
            host?.clearAllSections()
            host?.setBossBars([])
            host?.stopDisc()
            host?.releasePointer()
            host?.closeAllScreens()
            host?.openTitleScreen()
            host?.pushChat("§eDisconnected: \(why)")
        }
    }

    /// interpolated camera (view bobbing, third person, effect overlays)
    public func camState(_ partial: Double, timeSec: Double) -> CamState {
        let p = player!
        let w = world
        let ix = p.prevX + (p.x - p.prevX) * partial
        let iy = p.prevY + (p.y - p.prevY) * partial
        let iz = p.prevZ + (p.z - p.prevZ) * partial
        var eyeY = iy + (p.sneaking ? 1.27 : PLAYER_EYE)
        var cx = ix, cz = iz
        // view bobbing — phase/amp advance in tickViewBob (20Hz), interpolate here
        // View bob is a first-person camera effect. Applying the same lateral
        // translation to the third-person chase camera made the player appear
        // to weave left/right while running.
        if settings.viewBobbing && p.vehicle == nil && perspective == 0 {
            let bp = prevBobPhase + (bobPhase - prevBobPhase) * partial
            let ba = prevBobAmp + (bobAmp - prevBobAmp) * partial
            eyeY += abs(detSin(bp * .pi)) * ba * 0.55
            cx += detSin(bp * .pi) * ba * 0.16 * detCos(p.yaw)
            cz += detSin(bp * .pi) * ba * 0.16 * detSin(p.yaw)
        }
        if shake > 0.01 && !settings.reduceMotion {
            let a = shake * 0.12
            cx += detSin(timeSec * 61) * a
            eyeY += detSin(timeSec * 47 + 1.3) * a
            cz += detSin(timeSec * 53 + 2.1) * a
        }
        var yaw = p.yaw, pitch = p.pitch
        if perspective == 2 {
            yaw += .pi
            pitch = -pitch
        }
        // third person: pull camera back along the view ray, clipped by blocks
        if perspective > 0 {
            let back = 4.0
            let dx = detSin(yaw) * detCos(pitch)
            let dy = detSin(pitch)
            let dz = -detCos(yaw) * detCos(pitch)
            let hit = w.raycast(cx, eyeY, cz, dx, dy, dz, back)
            let dist = hit.map { max(0.2, $0.t - 0.25) } ?? back
            cx += dx * dist
            eyeY += dy * dist
            cz += dz * dist
        }
        let eyeBlock = w.getBlock(ifloor(cx), ifloor(eyeY), ifloor(cz))
        let eyeId = eyeBlock >> 4
        var cam = CamState()
        cam.x = cx; cam.y = eyeY; cam.z = cz
        cam.yaw = yaw; cam.pitch = pitch
        cam.fov = Double(settings.fov) * (prevFovScale + (fovScale - prevFovScale) * partial)
        cam.underwater = isWaterlogged(UInt16(eyeBlock))
        cam.underLava = eyeId == Int(B.lava)
        cam.powderSnow = eyeId == Int(B.powder_snow)
        cam.portalWarp = portalWarp
        cam.nightVision = p.hasEffect("night_vision") ? 1 : 0
        cam.darkness = p.hasEffect("darkness") ? (0.6 + 0.4 * detSin(timeSec * 2)) * settings.darknessPulse : 0
        cam.blindness = p.hasEffect("blindness") ? 1 : 0
        return cam
    }
}

// ---- small math helpers -------------------------------------------------------
/// radians into (-π, π]
public func wrapAngle(_ a: Double) -> Double {
    var a = a
    while a > .pi { a -= .pi * 2 }
    while a < -.pi { a += .pi * 2 }
    return a
}

func rayBoxT(_ ox: Double, _ oy: Double, _ oz: Double,
             _ dx: Double, _ dy: Double, _ dz: Double,
             _ x0: Double, _ y0: Double, _ z0: Double,
             _ x1: Double, _ y1: Double, _ z1: Double) -> Double? {
    var tmin = 0.0, tmax = Double.infinity
    let axes: [(Double, Double, Double, Double)] = [(ox, dx, x0, x1), (oy, dy, y0, y1), (oz, dz, z0, z1)]
    for (o, d, lo, hi) in axes {
        if abs(d) < 1e-9 {
            if o < lo || o > hi { return nil }
        } else {
            var t1 = (lo - o) / d, t2 = (hi - o) / d
            if t1 > t2 { swap(&t1, &t2) }
            tmin = max(tmin, t1)
            tmax = min(tmax, t2)
            if tmin > tmax { return nil }
        }
    }
    return tmin
}

/// deterministic ToInt32 (the `| 0` coercion) for seed-text parity with the golden baselines
func wrapToInt32(_ d: Double) -> Int32 {
    if !d.isFinite { return 0 }
    let m = d.truncatingRemainder(dividingBy: 4294967296)
    let u = UInt32(truncatingIfNeeded: Int64(m))
    return Int32(bitPattern: u)
}
