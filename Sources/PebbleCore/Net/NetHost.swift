// LAN host — runs the real world and shares it. Every guest gets a stand-in
// Player in the host world (so mobs target it, pressure plates see it, it
// shows up for everyone); the guest's own machine moves it and owns its
// health and inventory. What the host world does to that stand-in — damage,
// item pickups, XP, effects, knockback, teleports — is sent back to the guest.
// Guest actions (break, use, attack, release a bow…) are replayed here with the
// guest's held items, so world effects happen once, authoritatively.

import Foundation
import Network

/// what a guest last reported about its own player
struct GuestState {
    var x = 0.0, y = 0.0, z = 0.0
    var yaw = 0.0, pitch = 0.0, headYaw = 0.0
    var flags = 0
    var limbSwing = 0.0, limbAmp = 0.0, attackAnim = 0.0
    var hurtTime = 0, deathTime = 0
    var health = 20.0, fallDistance = 0.0
    var selectedSlot = 0, useItemTicks = 0, useHand = 0, gameMode = 0
    var sleepTicks = 0, fireTicks = 0
    var moveForward = 0.0, moveStrafe = 0.0
    var vehicle = 0
    var attackTicker = 100.0

    static let ON_GROUND = 1, SNEAKING = 2, SPRINTING = 4, FLYING = 8, WINGSUIT = 16
    static let USING = 32, JUMPING = 64, DEAD = 128, BREATH = 256

    func has(_ f: Int) -> Bool { flags & f != 0 }
}

/// what a guest last received for one entity
struct NetTrack {
    var snap: NetSnap
    var data: EntityData
    var extra: Int
}

/// the per-tick pose of an entity as guests see it
struct NetSnap: Equatable {
    var x = 0.0, y = 0.0, z = 0.0
    var yaw = 0.0, pitch = 0.0, headYaw = 0.0
    var limbSwing = 0.0, limbAmp = 0.0, attackAnim = 0.0
    var hurtTime = 0, deathTime = 0, flags = 0
    var health = 0.0

    static let ON_GROUND = 1, AIMING = 2, SITTING = 4, SNEAKING = 8, WINGSUIT = 16

    init() {}
    init(_ e: Entity) {
        x = e.x; y = e.y; z = e.z
        yaw = e.yaw; pitch = e.pitch
        if let l = e as? LivingEntity {
            headYaw = l.headYaw
            limbSwing = l.limbSwing; limbAmp = l.limbAmp; attackAnim = l.attackAnim
            hurtTime = l.hurtTime; deathTime = l.deathTime
            health = l.health
        }
        if e.onGround { flags |= Self.ON_GROUND }
        if let m = e as? Mob {
            if m.target != nil { flags |= Self.AIMING }
            if m.sitting { flags |= Self.SITTING }
        }
        if let p = e as? Player {
            if p.sneaking { flags |= Self.SNEAKING }
            if p.wingsuitFlying { flags |= Self.WINGSUIT }
        }
    }

    func write(_ w: inout ByteWriter, _ id: Int) {
        w.u32(id)
        w.f64(x); w.f64(y); w.f64(z)
        w.f32(yaw); w.f32(pitch); w.f32(headYaw)
        w.f32(limbSwing); w.f32(limbAmp); w.f32(attackAnim)
        w.u8(hurtTime); w.u8(min(255, deathTime)); w.u8(flags)
        w.f32(health)
    }
    static func read(_ r: inout ByteReader) throws -> (Int, NetSnap) {
        let id = try r.u32()
        var s = NetSnap()
        s.x = try r.f64(); s.y = try r.f64(); s.z = try r.f64()
        s.yaw = try r.f32(); s.pitch = try r.f32(); s.headYaw = try r.f32()
        s.limbSwing = try r.f32(); s.limbAmp = try r.f32(); s.attackAnim = try r.f32()
        s.hurtTime = try r.u8(); s.deathTime = try r.u8(); s.flags = try r.u8()
        s.health = try r.f32()
        return (id, s)
    }
}

/// spawn payload for an entity: its save data, or a light card for players
func netSpawnDict(_ e: Entity) -> [String: Any] {
    if let p = e as? Player {
        var d: [String: Any] = ["type": "player", "name": p.name, "x": p.x, "y": p.y, "z": p.z,
                                "yaw": p.yaw, "pitch": p.pitch]
        d["armor"] = p.armor.map { s -> Any in
            guard let s, let enc = try? JSONEncoder().encode(s),
                  let obj = try? JSONSerialization.jsonObject(with: enc) else { return NSNull() }
            return obj
        }
        return d
    }
    return e.save()
}

/// cheap change key for things a pose snapshot doesn't carry
private func netExtraKey(_ e: Entity) -> Int {
    if let item = e as? ItemEntity { return item.stack.id &* 1000 &+ item.stack.count }
    if let p = e as? Player {
        var h = 0
        for s in p.armor { h = h &* 31 &+ (s?.id ?? 0) }
        return h
    }
    return 0
}

// =============================================================================
final class RemoteClient: NetPlayerLink {
    let conn: NetConn
    unowned let host: NetHost
    var name = "?"
    var joined = false
    var proxy: Player!
    /// the render distance the guest asked for (its own setting)
    var requestedView = 8
    /// what the host loads, streams and tracks for this guest: never past the
    /// host's own render distance, so a guest at 16 can't make a phone host
    /// hold ~1,500 extra chunks
    var viewDistance: Int { min(requestedView, max(2, host.game.settings.renderDistance)) }
    /// chunk keys this guest holds (host's current dimension)
    var sent = Set<Int64>()
    var resend: [Int64] = []
    var tracked: [Int: NetTrack] = [:]
    /// packed block-entity position → fingerprint the guest has
    var beSent: [Int64: Data] = [:]
    var st = GuestState()
    var hasState = false
    /// proxy position as applied from the guest this tick (teleport detection)
    var appliedX = 0.0, appliedY = 0.0, appliedZ = 0.0
    var savedData: [String: Any]?
    /// frames batched until the end of the tick, sent in order on `sendQueue`
    private var out = Data()
    let sendQueue: DispatchQueue

    init(_ conn: NetConn, _ host: NetHost) {
        self.conn = conn
        self.host = host
        sendQueue = DispatchQueue(label: "pebble.net.send.\(conn.id)")
    }

    func queue(_ type: NetMsg, _ w: ByteWriter) { out.append(w.frame(type)) }
    func flush() {
        if out.isEmpty { return }
        let d = out
        out = Data()
        let c = conn
        sendQueue.async { c.send(d) }
    }
    /// compress a chunk off the main thread, keeping its place in the stream
    func sendChunk(_ c: Chunk, dim: Int) {
        flush()
        let blocks = c.blocks, biomes = c.biomes   // CoW snapshots
        let besJSON = (try? JSONEncoder().encode(Array(c.blockEntities.values))) ?? Data("[]".utf8)
        let cx = c.cx, cz = c.cz
        let conn = self.conn
        sendQueue.async {
            var w = ByteWriter(capacity: 32 << 10)
            w.u8(dim); w.i32(cx); w.i32(cz)
            w.blob(encodeChunkPayload(blocks, biomes, besJSON))
            conn.send(w.frame(.chunk))
        }
    }

    // ---- NetPlayerLink: the host world acting on this guest's player ----
    func netHurt(_ amount: Double, _ source: DamageSource, _ attacker: Entity?) -> Bool {
        guard let p = proxy, joined else { return false }
        if p.dead || st.has(GuestState.DEAD) || amount <= 0 { return false }
        if st.gameMode == GameMode.creative && source != .void { return false }
        if p.invulnTicks > 0 { return false }
        p.invulnTicks = 10
        p.hurtTime = 10
        var w = ByteWriter()
        w.f32(amount); w.str(source.rawValue); w.i32(attacker?.id ?? 0)
        queue(.hurt, w)
        return true
    }
    func netGive(_ stack: ItemStack) -> Bool {
        guard let p = proxy, joined else { return false }
        // fit it into the mirrored inventory so a full guest stops picking up
        let before = stack.count
        let sent = stack.copy()
        p.netLink = nil
        let all = p.give(stack)
        p.netLink = self
        let taken = before - stack.count
        if taken > 0 {
            sent.count = taken
            var w = ByteWriter()
            w.stack(sent)
            queue(.give, w)
        }
        return all
    }
    func netAddXP(_ points: Int) {
        var w = ByteWriter()
        w.i32(points)
        queue(.xp, w)
    }
    func netAddEffect(_ id: String, _ duration: Int, _ amplifier: Int, _ ambient: Bool) {
        var w = ByteWriter()
        w.str(id); w.i32(duration); w.u8(amplifier); w.bool(ambient)
        queue(.effect, w)
    }
}

// =============================================================================
public final class NetHost {
    unowned let game: GameCore
    private var listener: NetListener?
    public private(set) var port: UInt16 = 0
    private(set) var clients: [RemoteClient] = []
    private var pending: [Int: RemoteClient] = [:]
    private let inbox = NetInbox()
    /// block writes this tick, by chunk
    private var changed: [Int64: [(Int, Int, Int, Int)]] = [:]
    private var sounds: [(String, Double, Double, Double, Double, Double, Int)] = []
    private var particles: [(String, Double, Double, Double, Int, Double, Int, Int)] = []
    /// the guest whose action is running right now (their own sounds are skipped)
    private var actor: RemoteClient?
    /// the actor didn't run this action itself, so it gets the sounds too
    private var echoActor = false
    /// item drops are suppressed while replaying a guest action that the guest
    /// already predicted (its copies of the drops arrive as spawnItem)
    private(set) var suppressDrops = false
    private var lastInfo = Data()
    private var tickN = 0
    private var activity: NSObjectProtocol?

    public var guestNames: [String] { clients.filter { $0.joined }.map { $0.name } }

    init(game: GameCore) {
        self.game = game
    }

    func start(port wanted: UInt16, name: String) throws {
        let l = try NetListener(port: wanted, name: name) { [weak self] nw in
            let c = NetConn(nw)
            DispatchQueue.main.async { self?.accept(c) }
        }
        listener = l
        port = l.port
        // keep ticking when the window is hidden (App Nap would stall everyone)
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled], reason: "Hosting a LAN game")
        print("[net] hosting on port \(port)")
    }

    func stop(_ reason: String = "Host closed the game") {
        for c in clients + Array(pending.values) {
            var w = ByteWriter()
            w.str(reason)
            c.queue(.kick, w)
            c.flush()
            let conn = c.conn
            c.sendQueue.asyncAfter(deadline: .now() + 0.3) { conn.close() }
            if let p = c.proxy { p.world.removeEntity(p) }
        }
        clients.removeAll()
        pending.removeAll()
        listener?.stop()
        listener = nil
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }

    private func accept(_ c: NetConn) {
        let rc = RemoteClient(c, self)
        pending[c.id] = rc
        clients.append(rc)
        c.onFrame = { [weak self] f in self?.inbox.push(c.id, f) }
        c.onClose = { [weak self] why in
            DispatchQueue.main.async { self?.drop(c.id, why) }
        }
        c.start()
    }

    private func client(_ id: Int) -> RemoteClient? { clients.first { $0.conn.id == id } }

    private func drop(_ id: Int, _ why: String) {
        guard let i = clients.firstIndex(where: { $0.conn.id == id }) else { return }
        let c = clients.remove(at: i)
        pending.removeValue(forKey: id)
        c.conn.close()
        guard c.joined, let p = c.proxy else { return }
        if let d = c.savedData { saveGuest(c.name, d) }
        p.world.removeEntity(p)
        p.netLink = nil
        print("[net] \(c.name) left (\(why))")
        broadcastChat("§e\(c.name) left the game")
        broadcastPlayerList()
    }

    // ---- guest data persistence (stored under the host's world) ----
    private func guestKey(_ name: String) -> String? {
        game.worldRec.map { "\($0.id)#guest:\(name)" }
    }
    private func saveGuest(_ name: String, _ d: [String: Any]) {
        if let k = guestKey(name) { game.db.putPlayer(k, d) }
    }

    // =========================================================================
    // Inbound
    // =========================================================================
    /// handle everything guests sent since last tick (main thread, tick start)
    func processInbox() {
        for (id, f) in inbox.drain() {
            netLog.count(f.type)
            guard let c = client(id) else { continue }
            var r = ByteReader(f.body)
            do {
                try handle(c, f.type, &r)
            } catch {
                print("[net] bad \(f.type) from \(c.name): \(error)")
            }
        }
    }

    private func handle(_ c: RemoteClient, _ type: NetMsg, _ r: inout ByteReader) throws {
        // hello exactly once: a second would leave a stale linked proxy behind
        if c.joined == (type == .hello) { return }
        switch type {
        case .hello: try onHello(c, &r)
        case .playerState: try readState(c, &r)
        case .inventory: try readInventory(c, &r)
        case .actBreak:
            let x = try r.i32(), y = try r.i32(), z = try r.i32()
            try readHeld(c, &r)
            replay(c, drops: false) {
                finishBreaking(InteractCtx(world: c.proxy.world, player: c.proxy), x, y, z)
            }
            syncCells(c, x, y, z)
        case .actUse:
            let targetId = try r.i32()
            let hasHit = try r.bool()
            var hit: RaycastHit?
            if hasHit {
                let x = try r.i32(), y = try r.i32(), z = try r.i32(), face = try r.u8()
                guard face < 6 else { throw NetError.badFrame }
                let px = try r.f64(), py = try r.f64(), pz = try r.f64(), t = try r.f64()
                let w = c.proxy.world
                hit = RaycastHit(x: x, y: y, z: z, face: face, cell: w.getBlock(x, y, z), t: t, px: px, py: py, pz: pz)
            }
            try readHeld(c, &r)
            let target = targetId != 0 ? c.proxy.world.entityById[targetId] as? Entity : nil
            // host-only tools (bazooka, void bomb…) never ran on the guest
            let hostOnly = HOST_ONLY_TOOLS.contains(c.proxy.mainHand.map { itemDef($0.id).name } ?? "")
            replay(c, drops: hostOnly, echo: hostOnly) {
                _ = game.performUse(c.proxy, InteractCtx(world: c.proxy.world, player: c.proxy),
                                    target: target, hit: hit)
            }
            c.proxy.usingItem = false
            if let hit {
                syncCells(c, hit.x, hit.y, hit.z)
                syncCells(c, hit.x + DIR_X[hit.face], hit.y + DIR_Y[hit.face], hit.z + DIR_Z[hit.face])
            }
        case .actRelease:
            let ticks = try r.u16(), hand = try r.u8()
            try readHeld(c, &r)
            let p = c.proxy!
            p.usingItem = true
            p.useItemTicks = ticks
            p.useItemHand = hand == 1 ? .off : .main
            replay(c, drops: true) { releaseUsingItem(InteractCtx(world: p.world, player: p)) }
            p.usingItem = false
            p.useItemHand = .main
        case .actAttack:
            let targetId = try r.i32()
            let ticker = try r.f32()
            try readHeld(c, &r)
            let p = c.proxy!
            guard let target = p.world.entityById[targetId] as? Entity, !target.dead else { return }
            p.attackStrengthTicker = ticker
            replay(c, drops: true) {
                if target is LivingEntity || target.type == "rift_crystal" {
                    playerAttack(p, target)
                } else if target.type == "boat" || target.type == "minecart" {
                    _ = target.hurt(2, .player, p)
                }
            }
        case .actBrush:
            let x = try r.i32(), y = try r.i32(), z = try r.i32()
            let w = c.proxy.world
            let id = w.getBlockId(x, y, z)
            if id == Int(B.suspicious_sand) || id == Int(B.suspicious_gravel) {
                w.setBlock(x, y, z, Int(cell(id == Int(B.suspicious_gravel) ? B.gravel : B.sand)))
            }
        case .spawnItem:
            guard let stack = try r.stack() else { return }
            let x = try r.f64(), y = try r.f64(), z = try r.f64()
            let vx = try r.f32(), vy = try r.f32(), vz = try r.f32()
            let delay = try r.i16()
            let e = spawnItem(c.proxy.world, x, y, z, stack)
            e.vx = vx; e.vy = vy; e.vz = vz
            e.pickupDelay = delay
        case .spawnXP:
            // a full furnace's worth is a few hundred; cap one message at ~40 orbs
            let n = min(1500, try r.i32())
            let x = try r.f64(), y = try r.f64(), z = try r.f64()
            spawnXP(c.proxy.world, x, y, z, n)
        case .chat:
            let text = try r.str()
            broadcastChat("<\(c.name)> \(text)")
        case .command:
            let text = try r.str()
            let lines = withActor(c, echo: true) { game.netCommandRunner?(c.proxy, text) ?? ["§cThe host can't run commands"] }
            for l in lines { sendChat(c, l) }
        case .blockEntity:
            guard let be = try r.decodable(BlockEntityData.self) else { return }
            be.dropUnknownItems()
            let w = c.proxy.world
            if let live = w.getBlockEntity(be.x, be.y, be.z) {
                live.copyContents(from: be)
            } else if w.getBlockId(be.x, be.y, be.z) != 0 {
                w.setBlockEntity(be)
            }
            c.beSent[EditBatch.pack(be.x, be.y, be.z)] = beFingerprint(be)
            if netLog.on {
                print("[net] \(c.name) edited \(be.type) at \(be.x) \(be.y) \(be.z): lines \(be.lines ?? []) items \(be.items?.compactMap { $0 }.count ?? 0)")
            }
        case .playerSave:
            if let d = try r.json() as? [String: Any] {
                c.savedData = d
                saveGuest(c.name, d)
            }
        case .bye:
            drop(c.conn.id, "quit")
        default:
            break
        }
    }

    private func onHello(_ c: RemoteClient, _ r: inout ByteReader) throws {
        let proto = try r.u16()
        var name = try r.str().trimmingCharacters(in: .whitespaces)
        let version = try r.str()
        c.requestedView = max(2, min(16, try r.u8()))
        pending.removeValue(forKey: c.conn.id)
        guard proto == NET_PROTOCOL else {
            kick(c, "Version mismatch: host runs Pebble \(PEBBLE_BUILD), you have \(version)")
            return
        }
        guard game.inWorld, let rec = game.worldRec else { kick(c, "The host isn't in a world"); return }
        if name.isEmpty { name = "Guest" }
        name = String(name.prefix(16))
        var unique = name, n = 2
        let taken = Set(clients.filter { $0.joined }.map { $0.name } + [game.playerName])
        while taken.contains(unique) { unique = "\(name)\(n)"; n += 1 }
        c.name = unique

        let w = game.world
        let p = Player(world: w)
        p.isNetProxy = true
        p.name = unique
        // the LAN game plays in the host's current mode (the world record only
        // catches up on save), whatever mode this guest last saved in
        let mode = game.player.gameMode
        var saved: [String: Any]? = nil
        if let k = guestKey(unique), let rowData = game.db.getPlayer(k) {
            saved = rowData
            c.savedData = rowData
        }
        let savedDim = (saved?["dim"] as? NSNumber)?.intValue ?? -1
        if let pd = saved?["data"] as? [String: Any], savedDim == game.dim.rawValue {
            p.load(pd)
        }
        p.setGameMode(mode)
        if saved == nil || savedDim != game.dim.rawValue || !p.x.isFinite {
            // first visit (or the host moved dimensions): start beside the host
            let hp = game.player!
            let sx = ifloor(hp.x) + 1, sz = ifloor(hp.z)
            p.setPos(Double(sx) + 0.5, Double(max(w.surfaceY(sx, sz), ifloor(hp.y))), Double(sz) + 0.5)
        }
        p.netLink = c
        w.addEntity(p)
        c.proxy = p
        c.joined = true
        c.appliedX = p.x; c.appliedY = p.y; c.appliedZ = p.z
        c.st.x = p.x; c.st.y = p.y; c.st.z = p.z

        var out = ByteWriter(capacity: 1024)
        out.u32(p.id)
        out.str(game.playerName)
        out.str(rec.name)
        out.i32(Int(rec.seed))
        out.u8(game.dim.rawValue)
        out.u8(mode)
        out.f64(p.x); out.f64(p.y); out.f64(p.z)
        out.f32(p.yaw); out.f32(p.pitch)
        out.i32(Int(w.spawnX)); out.i32(Int(w.spawnY)); out.i32(Int(w.spawnZ))
        // the guest's saved player (inventory, health…) if it has visited before
        if let pd = saved?["data"] as? [String: Any] { out.json(pd) } else { out.json(NSNull()) }
        c.queue(.welcome, out)
        writeWorldInfo(c)
        writeTime(c)
        c.flush()
        print("[net] \(unique) joined from \(c.conn.conn.endpoint)")
        broadcastChat("§e\(unique) joined the game")
        broadcastPlayerList()
    }

    private func kick(_ c: RemoteClient, _ why: String) {
        var w = ByteWriter()
        w.str(why)
        c.queue(.kick, w)
        c.flush()
        let conn = c.conn
        c.sendQueue.asyncAfter(deadline: .now() + 0.5) { conn.close() }
    }

    private func readState(_ c: RemoteClient, _ r: inout ByteReader) throws {
        var s = GuestState()
        s.x = try r.f64(); s.y = try r.f64(); s.z = try r.f64()
        s.yaw = try r.f32(); s.pitch = try r.f32(); s.headYaw = try r.f32()
        s.flags = try r.u16()
        s.limbSwing = try r.f32(); s.limbAmp = try r.f32(); s.attackAnim = try r.f32()
        s.hurtTime = try r.u8(); s.deathTime = try r.u8()
        s.health = try r.f32(); s.fallDistance = try r.f32()
        s.selectedSlot = try r.u8(); s.useItemTicks = try r.u16(); s.useHand = try r.u8()
        s.gameMode = try r.u8()
        s.sleepTicks = try r.u16(); s.fireTicks = try r.i16()
        s.moveForward = try r.f32(); s.moveStrafe = try r.f32()
        s.vehicle = try r.i32()
        s.attackTicker = try r.f32()
        guard s.x.isFinite, s.y.isFinite, s.z.isFinite else { return }
        c.st = s
        c.hasState = true
    }

    private func readInventory(_ c: RemoteClient, _ r: inout ByteReader) throws {
        let p = c.proxy!
        for i in 0..<36 { p.inventory[i] = try r.stack() }
        for i in 0..<4 { p.armor[i] = try r.stack() }
        p.offHand = try r.stack()
    }

    /// the guest's hands (and look) at the moment of an action
    private func readHeld(_ c: RemoteClient, _ r: inout ByteReader) throws {
        let p = c.proxy!
        let slot = try r.u8()
        let main = try r.stack()
        let off = try r.stack()
        let x = try r.f64(), y = try r.f64(), z = try r.f64()
        let yaw = try r.f32(), pitch = try r.f32()
        let flags = try r.u16()
        p.selectedSlot = max(0, min(8, slot))
        p.inventory[p.selectedSlot] = main
        p.offHand = off
        if x.isFinite && y.isFinite && z.isFinite { p.x = x; p.y = y; p.z = z }
        p.yaw = yaw; p.pitch = pitch
        p.sneaking = flags & GuestState.SNEAKING != 0
        p.sprinting = flags & GuestState.SPRINTING != 0
        p.onGround = flags & GuestState.ON_GROUND != 0
    }

    /// run `body` as guest `c` (edits go in their undo history). `echo`: the
    /// guest didn't run it locally, so it still gets the sounds and particles
    private func withActor<T>(_ c: RemoteClient, echo: Bool = false, _ body: () -> T) -> T {
        let prevActor = actor, prevOwner = editOwner, prevEcho = echoActor
        actor = c
        editOwner = c.proxy.id
        echoActor = echo
        defer { actor = prevActor; editOwner = prevOwner; echoActor = prevEcho }
        return body()
    }

    /// run a guest action against the real world. `drops`: false when the
    /// guest predicted it and forwards its own copies of any item drops.
    /// `echo`: the guest didn't run it at all, so it gets the sounds and
    /// particles too
    private func replay(_ c: RemoteClient, drops: Bool, echo: Bool = false, _ body: () -> Void) {
        let prev = suppressDrops
        suppressDrops = !drops
        withActor(c, echo: echo, body)
        suppressDrops = prev
        // the actor's prediction may have differed: send what really happened
        c.appliedX = c.proxy.x; c.appliedY = c.proxy.y; c.appliedZ = c.proxy.z
    }

    /// authoritative 3×3×3 around an action target (repairs mispredictions)
    private func syncCells(_ c: RemoteClient, _ x: Int, _ y: Int, _ z: Int) {
        let w = c.proxy.world
        var cells: [(Int, Int, Int, Int)] = []
        for dy in -1...1 {
            for dz in -1...1 {
                for dx in -1...1 {
                    let bx = x + dx, by = y + dy, bz = z + dz
                    if !c.sent.contains(chunkKey(floorDiv(bx, 16), floorDiv(bz, 16))) { continue }
                    cells.append((bx, by, bz, w.getBlock(bx, by, bz)))
                }
            }
        }
        writeBlocks(c, cells)
    }

    // =========================================================================
    // Hooks from the host world
    // =========================================================================
    func blockChanged(_ x: Int, _ y: Int, _ z: Int, _ c: Int) {
        changed[chunkKey(floorDiv(x, 16), floorDiv(z, 16)), default: []].append((x, y, z, c))
    }
    func sound(_ name: String, _ x: Double, _ y: Double, _ z: Double, _ vol: Double, _ pitch: Double) {
        if clients.isEmpty { return }
        sounds.append((name, x, y, z, vol, pitch, echoActor ? -1 : actor?.conn.id ?? -1))
    }
    func particle(_ type: String, _ x: Double, _ y: Double, _ z: Double, _ n: Int, _ spread: Double, _ data: Int) {
        if clients.isEmpty { return }
        particles.append((type, x, y, z, n, spread, data, echoActor ? -1 : actor?.conn.id ?? -1))
    }
    /// called for every entity added to the host world
    func shouldSpawn(_ e: EntityRef) -> Bool {
        if suppressDrops, let ent = e as? Entity, ent.type == "item" || ent.type == "xp_orb" { return false }
        return true
    }

    /// chunk centers (and radii) guests need loaded
    func guestCenters() -> [(Int, Int, Int)] {
        clients.filter { $0.joined }.map {
            (floorDiv(ifloor($0.proxy.x), 16), floorDiv(ifloor($0.proxy.z), 16), $0.viewDistance)
        }
    }
    var proxies: [Player] { clients.compactMap { $0.joined ? $0.proxy : nil } }
    var liveProxies: [Player] { clients.compactMap { $0.joined && !$0.st.has(GuestState.DEAD) ? $0.proxy : nil } }
    /// every guest is in bed (the host sleeping alone doesn't skip the night)
    var allGuestsSleeping: Bool { clients.allSatisfy { !$0.joined || $0.st.sleepTicks > 100 } }

    // =========================================================================
    // Per tick: move proxies from guest reports (before the world ticks)
    // =========================================================================
    func tickProxies() {
        for c in clients where c.joined {
            let p = c.proxy!
            let s = c.st
            p.prevX = p.x; p.prevY = p.y; p.prevZ = p.z
            p.prevYaw = p.yaw; p.prevPitch = p.pitch
            if c.hasState {
                p.x = s.x; p.y = s.y; p.z = s.z
                p.yaw = s.yaw; p.pitch = s.pitch; p.headYaw = s.headYaw
                p.onGround = s.has(GuestState.ON_GROUND)
                p.sneaking = s.has(GuestState.SNEAKING)
                p.sprinting = s.has(GuestState.SPRINTING)
                p.flying = s.has(GuestState.FLYING)
                p.wingsuitFlying = s.has(GuestState.WINGSUIT)
                p.usingItem = s.has(GuestState.USING)
                p.jumping = s.has(GuestState.JUMPING)
                p.breathHeld = s.has(GuestState.BREATH)
                p.limbSwing = s.limbSwing; p.limbAmp = s.limbAmp; p.attackAnim = s.attackAnim
                p.deathTime = s.deathTime
                p.health = s.health
                p.fallDistance = s.fallDistance
                p.selectedSlot = max(0, min(8, s.selectedSlot))
                p.useItemTicks = s.useItemTicks
                p.useItemHand = s.useHand == 1 ? .off : .main
                p.setGameMode(s.gameMode)
                p.sleepTicks = s.sleepTicks
                p.fireTicks = s.fireTicks
                p.moveForward = s.moveForward; p.moveStrafe = s.moveStrafe
                p.attackStrengthTicker = s.attackTicker
                p.height = p.sneaking ? PLAYER_SNEAK_HEIGHT : PLAYER_HEIGHT
                p.dead = s.has(GuestState.DEAD)
                // riding: follow what the guest says it's on
                let want = s.vehicle != 0 ? (p.world.entityById[s.vehicle] as? Entity).flatMap { $0 is Player ? nil : $0 } : nil
                if want !== p.vehicle {
                    if p.vehicle != nil { p.dismount() }
                    if let want, !want.dead { p.mount(want) }
                    p.x = s.x; p.y = s.y; p.z = s.z
                }
            }
            if p.hurtTime > 0 { p.hurtTime -= 1 }
            if p.invulnTicks > 0 { p.invulnTicks -= 1 }
            p.vx = 0; p.vy = 0; p.vz = 0
            p.age += 1
            c.appliedX = p.x; c.appliedY = p.y; c.appliedZ = p.z
            if p.dead { continue }
            // the mining laser burns for as long as the guest holds it
            if p.usingItem, let held = p.usingHandStack, itemDef(held.id).name == "mining_laser" {
                withActor(c, echo: true) { fireLaser(p.world, p, wide: p.sneaking, tick: p.useItemTicks) }
            }
            // item / XP pickup (lands in the guest's inventory via NetPlayerLink)
            if p.age % 2 == 0 { p.pickUpNearby() }
        }
    }

    // =========================================================================
    // Per tick: send everything (after the world ticks)
    // =========================================================================
    func flushTick() {
        tickN += 1
        netLog.report("host", tickN, String(format: "hp %.1f | ", game.player.health)
                      + clients.map { "\($0.name): \($0.sent.count) chunks, \($0.tracked.count) ents" }.joined(separator: "; "))
        let w = game.world
        let dim = game.dim.rawValue
        for c in clients where c.joined {
            forwardProxyChanges(c)
            streamChunks(c, w, dim)
            sendBlocks(c)
            trackEntities(c, w)
            if tickN % 10 == 0 { syncBlockEntities(c, w) }
            if tickN % 20 == 0 { writeTime(c) }
            sendEvents(c)
        }
        if tickN % 20 == 0 { checkWorldInfo() }
        changed.removeAll(keepingCapacity: true)
        sounds.removeAll(keepingCapacity: true)
        particles.removeAll(keepingCapacity: true)
        for c in clients { c.flush() }
    }

    /// a building tool or undo moved a guest's player between ticks: teleport
    /// its client now, and take that as its position until the client reports
    /// again (the next tick would otherwise put back the stale report)
    func movedByTool(_ p: Player) {
        guard let c = clients.first(where: { $0.joined && $0.proxy === p }) else { return }
        var w = ByteWriter()
        w.f64(p.x); w.f64(p.y); w.f64(p.z)
        c.queue(.teleport, w)
        c.st.x = p.x; c.st.y = p.y; c.st.z = p.z
        c.appliedX = p.x; c.appliedY = p.y; c.appliedZ = p.z
    }

    /// the host world moved / pushed / set fire to a guest's player
    private func forwardProxyChanges(_ c: RemoteClient) {
        let p = c.proxy!
        if p.vehicle == nil, abs(p.x - c.appliedX) + abs(p.y - c.appliedY) + abs(p.z - c.appliedZ) > 0.001 {
            var w = ByteWriter()
            w.f64(p.x); w.f64(p.y); w.f64(p.z)
            c.queue(.teleport, w)
            c.st.x = p.x; c.st.y = p.y; c.st.z = p.z
        }
        if p.vx != 0 || p.vy != 0 || p.vz != 0 {
            var w = ByteWriter()
            w.f32(p.vx); w.f32(p.vy); w.f32(p.vz)
            c.queue(.impulse, w)
            p.vx = 0; p.vy = 0; p.vz = 0
        }
        if p.fireTicks > c.st.fireTicks + 1 {
            var w = ByteWriter()
            w.i32(p.fireTicks)
            c.queue(.setFire, w)
            c.st.fireTicks = p.fireTicks
        }
    }

    private func streamChunks(_ c: RemoteClient, _ w: World, _ dim: Int) {
        let pcx = floorDiv(ifloor(c.proxy.x), 16), pcz = floorDiv(ifloor(c.proxy.z), 16)
        let R = c.viewDistance
        // drop what's out of range
        for key in c.sent {
            let (cx, cz) = chunkCoords(key)
            if abs(cx - pcx) > R + 2 || abs(cz - pcz) > R + 2 {
                c.sent.remove(key)
                var m = ByteWriter()
                m.i32(cx); m.i32(cz)
                c.queue(.unloadChunk, m)
                c.beSent = c.beSent.filter { k, _ in
                    let (bx, _, bz) = EditBatch.unpack(k)
                    return floorDiv(bx, 16) != cx || floorDiv(bz, 16) != cz
                }
            }
        }
        // send nearest first, a few per tick, and never flood the socket
        var budget = 6
        if c.conn.queuedBytes > (3 << 20) { return }
        while budget > 0, let key = c.resend.first {
            c.resend.removeFirst()
            if let ch = w.chunks[key], ch.status != .empty {
                c.sendChunk(ch, dim: dim)
                c.sent.insert(key)
                budget -= 1
            }
        }
        if budget <= 0 { return }
        outer: for r in 0...R {
            for dz in -r...r {
                for dx in -r...r where max(abs(dx), abs(dz)) == r {
                    let key = chunkKey(pcx + dx, pcz + dz)
                    if c.sent.contains(key) { continue }
                    guard let ch = w.chunks[key], ch.status != .empty else { continue }
                    c.sendChunk(ch, dim: dim)
                    c.sent.insert(key)
                    budget -= 1
                    if budget <= 0 { break outer }
                }
            }
        }
    }

    private func sendBlocks(_ c: RemoteClient) {
        var cells: [(Int, Int, Int, Int)] = []
        for (key, list) in changed where c.sent.contains(key) {
            if list.count > 768 {
                // big edit: cheaper to resend the whole chunk
                c.sent.remove(key)
                if !c.resend.contains(key) { c.resend.append(key) }
                continue
            }
            cells.append(contentsOf: list)
        }
        writeBlocks(c, cells)
    }

    private func writeBlocks(_ c: RemoteClient, _ cells: [(Int, Int, Int, Int)]) {
        if cells.isEmpty { return }
        var w = ByteWriter(capacity: cells.count * 12 + 8)
        w.u32(cells.count)
        for (x, y, z, cell) in cells {
            w.i32(x); w.i16(y); w.i32(z); w.u16(cell)
        }
        c.queue(.blocks, w)
    }

    private func trackEntities(_ c: RemoteClient, _ w: World) {
        let me = c.proxy!
        let range = Double(min(c.viewDistance * 16, 128))
        let r2 = range * range
        var seen = Set<Int>()
        var moves = ByteWriter(capacity: 2048)
        var nMoves = 0
        for e in w.entities {
            guard let ent = e as? Entity, ent !== me, !ent.dead else { continue }
            let dx = ent.x - me.x, dz = ent.z - me.z
            if dx * dx + dz * dz > r2 { continue }
            // dead guests vanish for everyone
            if let pp = ent as? Player, pp.netLink != nil, (pp.netLink as? RemoteClient)?.st.has(GuestState.DEAD) == true { continue }
            seen.insert(ent.id)
            let snap = NetSnap(ent)
            if var t = c.tracked[ent.id] {
                if t.data != ent.data || t.extra != netExtraKey(ent)
                    || ((tickN + ent.id) % 200 == 0 && ent is LivingEntity && !(ent is Player)) {
                    var m = ByteWriter()
                    m.u32(ent.id)
                    m.json(netSpawnDict(ent))
                    c.queue(.entData, m)
                    t.data = ent.data
                    t.extra = netExtraKey(ent)
                }
                if t.snap != snap {
                    snap.write(&moves, ent.id)
                    nMoves += 1
                    t.snap = snap
                }
                c.tracked[ent.id] = t
            } else {
                var m = ByteWriter(capacity: 512)
                m.u32(ent.id)
                m.json(netSpawnDict(ent))
                c.queue(.entSpawn, m)
                c.tracked[ent.id] = NetTrack(snap: snap, data: ent.data, extra: netExtraKey(ent))
            }
        }
        if nMoves > 0 {
            var m = ByteWriter(capacity: moves.data.count + 4)
            m.u16(nMoves)
            m.data.append(moves.data)
            c.queue(.entMove, m)
        }
        let gone = c.tracked.keys.filter { !seen.contains($0) }
        if !gone.isEmpty {
            var m = ByteWriter()
            m.u16(gone.count)
            for id in gone { m.u32(id); c.tracked.removeValue(forKey: id) }
            c.queue(.entDespawn, m)
        }
    }

    /// container contents, furnace progress, signs: anything near the guest
    /// (or ticking anywhere they can see) that changed since they last got it
    private func syncBlockEntities(_ c: RemoteClient, _ w: World) {
        let pcx = floorDiv(ifloor(c.proxy.x), 16), pcz = floorDiv(ifloor(c.proxy.z), 16)
        var list: [BlockEntityData] = []
        for be in w.tickingBEList where c.sent.contains(chunkKey(floorDiv(be.x, 16), floorDiv(be.z, 16))) {
            list.append(be)
        }
        for dz in -2...2 {
            for dx in -2...2 {
                guard let ch = w.getChunk(pcx + dx, pcz + dz), c.sent.contains(chunkKey(ch.cx, ch.cz)) else { continue }
                list.append(contentsOf: ch.blockEntities.values)
            }
        }
        var done = Set<ObjectIdentifier>()
        for be in list where done.insert(ObjectIdentifier(be)).inserted {
            let key = EditBatch.pack(be.x, be.y, be.z)
            let fp = beFingerprint(be)
            if c.beSent[key] == fp { continue }
            c.beSent[key] = fp
            var m = ByteWriter(capacity: fp.count + 8)
            m.blob(fp)
            c.queue(.blockEntity, m)
        }
    }

    private func sendEvents(_ c: RemoteClient) {
        let me = c.proxy!
        var sw = ByteWriter(capacity: 512), ns = 0
        for (name, x, y, z, vol, pitch, ex) in sounds where ex != c.conn.id {
            let reach = min(128, max(24, vol * 16))
            if (x - me.x) * (x - me.x) + (y - me.y) * (y - me.y) + (z - me.z) * (z - me.z) > reach * reach { continue }
            sw.str(name); sw.f64(x); sw.f64(y); sw.f64(z); sw.f32(vol); sw.f32(pitch)
            ns += 1
            if ns >= 256 { break }
        }
        if ns > 0 {
            var m = ByteWriter(capacity: sw.data.count + 2)
            m.u16(ns)
            m.data.append(sw.data)
            c.queue(.sounds, m)
        }
        // as far as the guest tracks entities: a rocket's trail and blast
        // shouldn't vanish partway out when the host still shows them
        let pr = Double(min(c.viewDistance * 16, 128))
        var pw = ByteWriter(capacity: 512), np = 0
        for (type, x, y, z, n, spread, data, ex) in particles where ex != c.conn.id {
            if (x - me.x) * (x - me.x) + (y - me.y) * (y - me.y) + (z - me.z) * (z - me.z) > pr * pr { continue }
            pw.str(type); pw.f64(x); pw.f64(y); pw.f64(z); pw.u16(n); pw.f32(spread); pw.i32(data)
            np += 1
            if np >= 400 { break }
        }
        if np > 0 {
            var m = ByteWriter(capacity: pw.data.count + 2)
            m.u16(np)
            m.data.append(pw.data)
            c.queue(.particles, m)
        }
    }

    private func writeTime(_ c: RemoteClient) {
        let w = game.world
        var m = ByteWriter()
        m.i64(w.time); m.i32(w.dayTime)
        m.f32(w.rainLevel); m.f32(w.thunderLevel)
        m.bool(w.raining); m.bool(w.thundering)
        c.queue(.worldTime, m)
    }

    private func worldInfoBody() -> ByteWriter {
        let w = game.world
        var m = ByteWriter()
        m.u8(w.difficulty)
        m.json(w.gameRules)
        m.i32(Int(w.spawnX)); m.i32(Int(w.spawnY)); m.i32(Int(w.spawnZ))
        // guests draw no farther than we load for them (RemoteClient.viewDistance)
        m.u8(game.settings.renderDistance)
        return m
    }
    private func writeWorldInfo(_ c: RemoteClient) {
        let m = worldInfoBody()
        lastInfo = m.data
        c.queue(.worldInfo, m)
    }
    private func checkWorldInfo() {
        let m = worldInfoBody()
        if m.data == lastInfo { return }
        lastInfo = m.data
        for c in clients where c.joined { c.queue(.worldInfo, m) }
    }

    // =========================================================================
    // Chat, players, dimension moves
    // =========================================================================
    func sendChat(_ c: RemoteClient, _ line: String) {
        var m = ByteWriter()
        m.str(line)
        c.queue(.chatLine, m)
    }
    /// to every guest and the host's own chat
    func broadcastChat(_ line: String) {
        if netLog.on { print("[net] chat: \(line)"); fflush(stdout) }
        game.host?.pushChat(line)
        for c in clients where c.joined { sendChat(c, line) }
    }
    private func broadcastPlayerList() {
        var m = ByteWriter()
        let names = [game.playerName] + clients.filter { $0.joined }.map { $0.name }
        m.u16(names.count)
        for n in names { m.str(n) }
        for c in clients where c.joined { c.queue(.playerList, m) }
    }

    /// the host changed dimension: everyone comes along, next to the host
    func hostChangedDimension(from old: World) {
        let w = game.world
        let hp = game.player!
        for c in clients where c.joined {
            let p = c.proxy!
            old.removeEntity(p)
            p.world = w
            p.setPos(hp.x, hp.y, hp.z)
            w.addEntity(p)
            c.sent.removeAll()
            c.resend.removeAll()
            c.tracked.removeAll()
            c.beSent.removeAll()
            c.appliedX = p.x; c.appliedY = p.y; c.appliedZ = p.z
            c.st.x = p.x; c.st.y = p.y; c.st.z = p.z
            var m = ByteWriter()
            m.u8(game.dim.rawValue)
            m.f64(hp.x); m.f64(hp.y); m.f64(hp.z)
            c.queue(.dimChange, m)
            writeWorldInfo(c)
            writeTime(c)
        }
    }

    /// the night was slept through
    func wakeEveryone() {
        for c in clients where c.joined { c.queue(.wake, ByteWriter()) }
    }

    /// a chunk changed wholesale on the host (Infinity Wipe): guests get a fresh copy
    func resendChunk(_ cx: Int, _ cz: Int) {
        let key = chunkKey(cx, cz)
        for c in clients where c.joined && c.sent.remove(key) != nil {
            if !c.resend.contains(key) { c.resend.append(key) }
        }
    }

    /// this tick's blasts, for guests' screen shake
    func broadcastBlasts(_ list: [(Double, Double, Double, Double)]) {
        if list.isEmpty || clients.isEmpty { return }
        var m = ByteWriter()
        m.u16(min(list.count, 1000))
        for (x, y, z, r) in list.prefix(1000) { m.f64(x); m.f64(y); m.f64(z); m.f32(r) }
        for c in clients where c.joined { c.queue(.blasts, m) }
    }

    /// the host changed game mode: everyone follows
    func broadcastGameMode(_ mode: Int) {
        var m = ByteWriter()
        m.u8(mode)
        for c in clients where c.joined {
            c.queue(.gameMode, m)
            c.proxy?.setGameMode(mode)
            c.st.gameMode = mode
        }
    }
}

/// inverse of chunkKey
func chunkCoords(_ key: Int64) -> (Int, Int) {
    // chunkKey packs (cx, cz) — recover both halves
    let cx = Int(Int32(truncatingIfNeeded: key >> 32))
    let cz = Int(Int32(truncatingIfNeeded: key))
    return (cx, cz)
}
