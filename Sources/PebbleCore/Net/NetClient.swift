// LAN guest — plays in a copy of the host's world. The guest's own player is
// simulated here (movement, inventory, health); everything else comes from the
// host: chunks and block changes, entities (drawn but never simulated here),
// time, weather, sounds. Actions run locally for instant feedback and are sent
// to the host, which replays them for real; what the host world does to us
// (damage, pickups, knockback) arrives as messages.

import Foundation
import Network

public final class NetClient {
    unowned let game: GameCore
    let conn: NetConn
    private let inbox = NetInbox()
    public let name: String
    /// human-readable progress for the join screen
    public private(set) var status = "Connecting..."
    /// set when the connection failed or the host kicked us
    public private(set) var failure: String?
    public private(set) var joined = false
    public private(set) var hostName = ""
    public private(set) var playerNames: [String] = []
    /// host entity id of our own stand-in (never drawn here)
    private(set) var myId = 0
    /// host entity id → local copy
    private var ents: [Int: Entity] = [:]
    /// local copy's id → host id
    private var hostIdOf: [Int: Int] = [:]
    private var targets: [Int: NetSnap] = [:]
    private var invFingerprint = Data()
    private var tickN = 0
    /// block entities an open screen is editing: packed position → fingerprint
    private var watched: [Int64: Data] = [:]
    /// ignore host copies of a block entity we just edited (theirs is older)
    private var localEditUntil: [Int64: Int] = [:]
    private var closing = false
    private let pumpLock = NSLock()
    private var pumpQueued = false
    /// chunk counters for the join screen
    public private(set) var chunksReceived = 0

    init(game: GameCore, conn: NetConn, name: String) {
        self.game = game
        self.conn = conn
        self.name = name
        let viewDistance = game.settings.renderDistance
        conn.onReady = { [weak self] in
            var w = ByteWriter()
            w.u16(NET_PROTOCOL)
            w.str(name)
            w.str(PEBBLE_VERSION)
            w.u8(viewDistance)
            conn.send(w.frame(.hello))
            DispatchQueue.main.async { self?.status = "Joining..." }
        }
        conn.onFrame = { [weak self] f in
            guard let self else { return }
            var f = f
            if f.type == .chunk { f.built = Self.buildChunk(f.body) }
            self.inbox.push(conn.id, f)
            self.schedulePump()
        }
        conn.onClose = { [weak self] why in
            DispatchQueue.main.async { self?.closed(why) }
        }
        conn.start()
    }

    /// before we're in the world nothing ticks — pump from the run loop
    private func schedulePump() {
        pumpLock.lock()
        let need = !pumpQueued && !joined
        if need { pumpQueued = true }
        pumpLock.unlock()
        if need {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.pumpLock.lock(); self.pumpQueued = false; self.pumpLock.unlock()
                if !self.joined { self.pump() }
            }
        }
    }

    /// decode + light a chunk on the connection queue (pure work, no game state)
    private static func buildChunk(_ body: [UInt8]) -> Any? {
        var r = ByteReader(body)
        guard let dim = try? r.u8(), let cx = try? r.i32(), let cz = try? r.i32(),
              let blob = try? r.blob(), dim < DIMS.count else { return nil }
        let info = DIMS[dim]
        guard let dec = decodeChunkPayload(blob, height: info.height) else { return nil }
        let light = computeLocalLight(blocks: dec.blocks, height: info.height, hasSky: info.hasSky)
        let c = GameCore.makeChunk(cx, cz, info.minY, info.height, dec.blocks, dec.biomes, light.sky, light.blk)
        return (dim, c, dec.bes)
    }

    private func closed(_ why: String) {
        if closing { return }
        closing = true
        if failure == nil { failure = why }
        status = failure ?? why
        game.netClientClosed(self, failure ?? why)
    }

    /// leave: save our player on the host, then hang up
    func disconnect() {
        if closing { return }
        if joined { flushSpawns() }
        closing = true
        if joined {
            sendSave()
            send(.bye, ByteWriter())
        }
        let c = conn
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { c.close() }
    }

    private func send(_ type: NetMsg, _ w: ByteWriter) {
        if closing && type != .bye && type != .playerSave { return }
        conn.send(w.frame(type))
    }

    // =========================================================================
    // Inbound
    // =========================================================================
    func pump() {
        for (_, f) in inbox.drain() {
            netLog.count(f.type)
            var r = ByteReader(f.body)
            do {
                try handle(f, &r)
            } catch {
                print("[net] bad \(f.type) from host: \(error)")
            }
            if closing { return }
        }
    }

    private var world: World { game.world }

    private func handle(_ f: NetFrame, _ r: inout ByteReader) throws {
        if !joined && f.type != .welcome && f.type != .kick { return }
        switch f.type {
        case .welcome: try onWelcome(&r)
        case .kick:
            failure = try r.str()
            print("[net] kicked: \(failure!)")
            closed(failure!)
        case .chunk:
            guard let (dim, c, bes) = f.built as? (Int, Chunk, [BlockEntityData]) else { return }
            if dim != game.dim.rawValue { return }
            game.netAdoptChunk(c, bes)
            chunksReceived += 1
        case .unloadChunk:
            let cx = try r.i32(), cz = try r.i32()
            game.netDropChunk(cx, cz)
        case .blocks:
            let n = try r.u32()
            let w = world
            for _ in 0..<n {
                let x = try r.i32(), y = try r.i16(), z = try r.i32(), cell = try r.u16()
                if (cell >> 4) >= blockDefs.count { continue }
                w.setBlock(x, y, z, cell, SET_NO_NEIGHBORS)
            }
        case .entSpawn:
            let id = try r.u32()
            guard let d = try r.json() as? [String: Any] else { return }
            spawnCopy(id, d)
        case .entMove:
            let n = try r.u16()
            for _ in 0..<n {
                let (id, s) = try NetSnap.read(&r)
                targets[id] = s
            }
        case .entDespawn:
            let n = try r.u16()
            for _ in 0..<n { removeCopy(try r.u32()) }
        case .entData:
            let id = try r.u32()
            guard let d = try r.json() as? [String: Any], let e = ents[id] else { return }
            refreshCopy(e, d)
        case .worldTime:
            let time = try r.i64(), day = try r.i32()
            let rain = try r.f32(), thunder = try r.f32()
            let raining = try r.bool(), thundering = try r.bool()
            for w in game.worlds.values {
                w.time = time
                w.dayTime = day
                w.rainLevel = rain; w.thunderLevel = thunder
                w.raining = raining; w.thundering = thundering
            }
        case .worldInfo:
            let diff = try r.u8()
            let rules = try r.json() as? [String: Any] ?? [:]
            let sx = try r.i32(), sy = try r.i32(), sz = try r.i32()
            for w in game.worlds.values {
                w.difficulty = diff
                for (k, v) in rules { if let n = v as? NSNumber { w.gameRules[k] = n.doubleValue } }
                w.spawnX = Double(sx); w.spawnY = Double(sy); w.spawnZ = Double(sz)
            }
        case .sounds:
            let n = try r.u16()
            for _ in 0..<n {
                let name = try r.str()
                let x = try r.f64(), y = try r.f64(), z = try r.f64()
                let vol = try r.f32(), pitch = try r.f32()
                world.hooks.playSound(name, x, y, z, vol, pitch)
            }
        case .particles:
            let n = try r.u16()
            for _ in 0..<n {
                let type = try r.str()
                let x = try r.f64(), y = try r.f64(), z = try r.f64()
                let count = try r.u16(), spread = try r.f32(), data = try r.i32()
                world.hooks.addParticles(type, x, y, z, count, spread, data)
            }
        case .chatLine:
            let line = try r.str()
            if netLog.on { print("[net] chat: \(line)"); fflush(stdout) }
            game.host?.pushChat(line)
        case .hurt:
            let amount = try r.f32(), source = try r.str(), attacker = try r.i32()
            _ = game.player.hurt(amount, source, ents[attacker])
        case .give:
            guard let s = try r.stack() else { return }
            let p = game.player!
            if !p.give(s) && s.count > 0 {
                // full after all: drop the rest at our feet
                _ = spawnItem(world, p.x, p.y + 0.5, p.z, s)
            } else {
                world.hooks.playSound("entity.item.pickup", p.x, p.y, p.z, 0.3, 1.4 + Double.random(in: 0..<0.6))
            }
        case .xp:
            game.player.addXP(try r.i32())
        case .effect:
            let id = try r.str(), dur = try r.i32(), amp = try r.u8(), amb = try r.bool()
            game.player.addEffect(id, dur, amp, ambient: amb)
        case .impulse:
            let p = game.player!
            p.vx += try r.f32(); p.vy += try r.f32(); p.vz += try r.f32()
        case .teleport:
            let x = try r.f64(), y = try r.f64(), z = try r.f64()
            let p = game.player!
            p.setPos(x, y, z)
            p.vx = 0; p.vy = 0; p.vz = 0
            p.fallDistance = 0
        case .setFire:
            let p = game.player!
            p.fireTicks = max(p.fireTicks, try r.i32())
        case .dimChange:
            let dim = try r.u8()
            let x = try r.f64(), y = try r.f64(), z = try r.f64()
            for id in Array(ents.keys) { removeCopy(id) }
            targets.removeAll()
            watched.removeAll()
            if let d = Dim(rawValue: dim) { game.netChangeDim(d, x, y, z) }
        case .playerList:
            let n = try r.u16()
            var names: [String] = []
            for _ in 0..<n { names.append(try r.str()) }
            playerNames = names
        case .blockEntity:
            guard let be = try r.decodable(BlockEntityData.self) else { return }
            let key = EditBatch.pack(be.x, be.y, be.z)
            if let until = localEditUntil[key], until > tickN { return }
            let w = world
            if let live = w.getBlockEntity(be.x, be.y, be.z) {
                live.copyContents(from: be)
            } else if w.getBlockId(be.x, be.y, be.z) != 0 {
                w.setBlockEntity(be)
            }
            if watched[key] != nil { watched[key] = beFingerprint(be) }
        case .wake:
            let p = game.player!
            if p.sleepTicks > 0 {
                p.sleepTicks = 0
                p.bedPos = nil
            }
        default:
            break
        }
    }

    private func onWelcome(_ r: inout ByteReader) throws {
        myId = try r.u32()
        hostName = try r.str()
        let worldName = try r.str()
        let seed = Int32(truncatingIfNeeded: try r.i32())
        let dim = Dim(rawValue: try r.u8()) ?? .overworld
        let mode = try r.u8()
        let x = try r.f64(), y = try r.f64(), z = try r.f64()
        let yaw = try r.f32(), pitch = try r.f32()
        let sx = try r.i32(), sy = try r.i32(), sz = try r.i32()
        let saved = try r.json() as? [String: Any]
        joined = true
        status = "Joined"
        game.enterRemoteWorld(self, name: worldName, seed: seed, dim: dim, mode: mode,
                              pos: (x, y, z, yaw, pitch), spawn: (sx, sy, sz), saved: saved)
        print("[net] joined \(hostName)'s world \"\(worldName)\" as \(name)")
    }

    // ---- entity copies ------------------------------------------------------
    private func spawnCopy(_ id: Int, _ d: [String: Any]) {
        if id == myId { return }
        removeCopy(id)
        guard let type = d["type"] as? String else { return }
        let w = world
        let e: Entity
        if type == "player" {
            let p = Player(world: w)
            p.name = (d["name"] as? String) ?? "Player"
            p.setPos(dnum(d["x"]), dnum(d["y"]), dnum(d["z"]))
            p.yaw = dnum(d["yaw"]); p.pitch = dnum(d["pitch"])
            readArmor(p, d)
            e = p
        } else {
            guard let made = createEntity(type, w) else { return }
            made.load(d)
            e = made
        }
        e.isNetProxy = true
        e.prevYaw = e.yaw; e.prevPitch = e.pitch
        w.addEntity(e)
        ents[id] = e
        hostIdOf[e.id] = id
    }

    private func readArmor(_ p: Player, _ d: [String: Any]) {
        guard let arr = d["armor"] as? [Any] else { return }
        for (i, raw) in arr.prefix(4).enumerated() {
            if raw is NSNull { p.armor[i] = nil; continue }
            guard let bytes = try? JSONSerialization.data(withJSONObject: raw),
                  let s = try? JSONDecoder().decode(ItemStack.self, from: bytes), s.id < itemDefs.count else { continue }
            p.armor[i] = s
        }
    }

    /// new save data for a copy, keeping its interpolation state
    private func refreshCopy(_ e: Entity, _ d: [String: Any]) {
        let (px, py, pz, x, y, z) = (e.prevX, e.prevY, e.prevZ, e.x, e.y, e.z)
        let (pyaw, yaw) = (e.prevYaw, e.yaw)
        if let p = e as? Player {
            readArmor(p, d)
        } else {
            e.load(d)
        }
        e.prevX = px; e.prevY = py; e.prevZ = pz
        e.x = x; e.y = y; e.z = z
        e.prevYaw = pyaw; e.yaw = yaw
    }

    private func removeCopy(_ id: Int) {
        guard let e = ents.removeValue(forKey: id) else { return }
        hostIdOf.removeValue(forKey: e.id)
        targets.removeValue(forKey: id)
        e.world.removeEntity(e)
    }

    /// host id of a local copy (0 = not a copy)
    func hostId(_ e: Entity?) -> Int {
        guard let e else { return 0 }
        return hostIdOf[e.id] ?? 0
    }

    /// once per guest tick: step every copy toward the host's latest pose
    func tickCopies() {
        tickN += 1
        for (id, e) in ents {
            e.prevX = e.x; e.prevY = e.y; e.prevZ = e.z
            e.prevYaw = e.yaw; e.prevPitch = e.pitch
            e.age += 1
            let liv = e as? LivingEntity
            if let l = liv, l.hurtTime > 0 { l.hurtTime -= 1 }
            guard let s = targets.removeValue(forKey: id) else { continue }
            e.x = s.x; e.y = s.y; e.z = s.z
            e.yaw = s.yaw; e.pitch = s.pitch
            e.onGround = s.flags & NetSnap.ON_GROUND != 0
            e.netAiming = s.flags & NetSnap.AIMING != 0
            if let l = liv {
                l.headYaw = s.headYaw
                l.limbSwing = s.limbSwing; l.limbAmp = s.limbAmp; l.attackAnim = s.attackAnim
                l.hurtTime = max(l.hurtTime, s.hurtTime)
                l.deathTime = s.deathTime
                l.health = s.health
            }
            if let m = e as? Mob { m.sitting = s.flags & NetSnap.SITTING != 0 }
            if let p = e as? Player {
                p.sneaking = s.flags & NetSnap.SNEAKING != 0
                p.elytraFlying = s.flags & NetSnap.ELYTRA != 0
            }
            // a jump of more than a few blocks is a teleport — don't streak
            if abs(e.x - e.prevX) + abs(e.y - e.prevY) + abs(e.z - e.prevZ) > 8 {
                e.prevX = e.x; e.prevY = e.y; e.prevZ = e.z
            }
        }
    }

    /// the local world tried to spawn something: items and XP (our drops,
    /// predicted block drops) go to the host; everything else the host makes
    /// itself when it replays our action
    func localSpawn(_ e: EntityRef) -> Bool {
        guard let ent = e as? Entity else { return false }
        if ent.isNetProxy || ent === game.player { return true }
        // sent at the end of the tick: callers set throw velocity / pickup
        // delay after spawning
        if ent is ItemEntity || ent is XPOrb { pendingSpawns.append(ent) }
        return false
    }
    private var pendingSpawns: [Entity] = []

    private func flushSpawns() {
        for ent in pendingSpawns {
            forwardSpawn(ent)
        }
        pendingSpawns.removeAll()
    }

    private func forwardSpawn(_ ent: Entity) {
        if let item = ent as? ItemEntity {
            var w = ByteWriter()
            w.stack(item.stack)
            w.f64(item.x); w.f64(item.y); w.f64(item.z)
            w.f32(item.vx); w.f32(item.vy); w.f32(item.vz)
            w.i16(item.pickupDelay)
            send(.spawnItem, w)
        } else if let orb = ent as? XPOrb {
            var w = ByteWriter()
            w.i32(orb.amount)
            w.f64(orb.x); w.f64(orb.y); w.f64(orb.z)
            send(.spawnXP, w)
        }
    }

    // =========================================================================
    // Outbound
    // =========================================================================
    /// end of every guest tick: our player's state, plus inventory / container
    /// edits when they changed
    func sendTick() {
        guard joined, let p = game.player else { return }
        netLog.report("guest", tickN, String(format: "hp %.1f | %d items | %d copies | %d chunks", p.health,
                                               p.inventory.compactMap { $0?.count }.reduce(0, +), ents.count, chunksReceived))
        flushSpawns()
        var w = ByteWriter(capacity: 128)
        w.f64(p.x); w.f64(p.y); w.f64(p.z)
        w.f32(p.yaw); w.f32(p.pitch); w.f32(p.headYaw)
        var flags = 0
        if p.onGround { flags |= GuestState.ON_GROUND }
        if p.sneaking { flags |= GuestState.SNEAKING }
        if p.sprinting { flags |= GuestState.SPRINTING }
        if p.flying { flags |= GuestState.FLYING }
        if p.elytraFlying { flags |= GuestState.ELYTRA }
        if p.usingItem { flags |= GuestState.USING }
        if p.jumping { flags |= GuestState.JUMPING }
        if p.dead || p.deathTime > 0 { flags |= GuestState.DEAD }
        w.u16(flags)
        w.f32(p.limbSwing); w.f32(p.limbAmp); w.f32(p.attackAnim)
        w.u8(p.hurtTime); w.u8(min(255, p.deathTime))
        w.f32(p.health); w.f32(p.fallDistance)
        w.u8(p.selectedSlot); w.u16(p.useItemTicks); w.u8(p.useItemHand == "off" ? 1 : 0)
        w.u8(p.gameMode)
        w.u16(min(65535, p.sleepTicks)); w.i16(max(-32768, min(32767, p.fireTicks)))
        w.f32(p.moveForward); w.f32(p.moveStrafe)
        w.i32(hostId(p.vehicle))
        w.f32(p.attackStrengthTicker)
        send(.playerState, w)

        if tickN % 5 == 0 { sendInventoryIfChanged() }
        if tickN % 4 == 0 { pollWatched() }
        if tickN % 600 == 0 { sendSave() }
    }

    private func sendInventoryIfChanged(force: Bool = false) {
        guard let p = game.player else { return }
        var w = ByteWriter(capacity: 2048)
        for s in p.inventory { w.stack(s) }
        for s in p.armor { w.stack(s) }
        w.stack(p.offHand)
        if !force && w.data == invFingerprint { return }
        invFingerprint = w.data
        send(.inventory, w)
    }

    /// the player's save record, kept by the host for our next visit
    func sendSave() {
        guard joined, let p = game.player else { return }
        var w = ByteWriter(capacity: 4096)
        w.json(["dim": game.dim.rawValue, "data": p.save()] as [String: Any])
        send(.playerSave, w)
    }

    /// a container / sign screen opened on (x,y,z): send our edits to the host
    func watch(_ x: Int, _ y: Int, _ z: Int) {
        let key = EditBatch.pack(x, y, z)
        watched[key] = world.getBlockEntity(x, y, z).map(beFingerprint) ?? Data()
    }

    private func pollWatched() {
        if watched.isEmpty { return }
        let w = world
        for (key, fp) in watched {
            let (x, y, z) = EditBatch.unpack(key)
            guard let be = w.getBlockEntity(x, y, z) else { continue }
            let now = beFingerprint(be)
            if now == fp { continue }
            watched[key] = now
            localEditUntil[key] = tickN + 30
            var m = ByteWriter(capacity: now.count + 8)
            m.blob(now)
            send(.blockEntity, m)
        }
        // screen closed: that was the final check
        if !(game.host?.hasScreen() ?? false) { watched.removeAll() }
    }

    /// hands + look at the moment of an action (the host replays with these)
    private func writeHeld(_ w: inout ByteWriter, _ p: Player) {
        w.u8(p.selectedSlot)
        w.stack(p.mainHand)
        w.stack(p.offHand)
        w.f64(p.x); w.f64(p.y); w.f64(p.z)
        w.f32(p.yaw); w.f32(p.pitch)
        var flags = 0
        if p.sneaking { flags |= GuestState.SNEAKING }
        if p.sprinting { flags |= GuestState.SPRINTING }
        if p.onGround { flags |= GuestState.ON_GROUND }
        w.u16(flags)
    }

    func sendBreak(_ x: Int, _ y: Int, _ z: Int) {
        guard let p = game.player else { return }
        var w = ByteWriter()
        w.i32(x); w.i32(y); w.i32(z)
        writeHeld(&w, p)
        send(.actBreak, w)
    }

    func sendUse(_ target: Entity?, _ hit: RaycastHit?) {
        guard let p = game.player else { return }
        var w = ByteWriter()
        w.i32(hostId(target))
        w.bool(hit != nil)
        if let hit {
            w.i32(hit.x); w.i32(hit.y); w.i32(hit.z); w.u8(hit.face)
            w.f64(hit.px); w.f64(hit.py); w.f64(hit.pz); w.f64(hit.t)
        }
        writeHeld(&w, p)
        send(.actUse, w)
    }

    func sendRelease(_ ticks: Int, _ hand: String) {
        guard let p = game.player else { return }
        var w = ByteWriter()
        w.u16(ticks); w.u8(hand == "off" ? 1 : 0)
        writeHeld(&w, p)
        send(.actRelease, w)
    }

    func sendAttack(_ target: Entity) {
        guard let p = game.player else { return }
        let id = hostId(target)
        if id == 0 { return }
        var w = ByteWriter()
        w.i32(id)
        w.f32(p.attackStrengthTicker)
        writeHeld(&w, p)
        send(.actAttack, w)
    }

    func sendBrush(_ x: Int, _ y: Int, _ z: Int) {
        var w = ByteWriter()
        w.i32(x); w.i32(y); w.i32(z)
        send(.actBrush, w)
    }

    public func sendChat(_ text: String) {
        var w = ByteWriter()
        w.str(text)
        send(.chat, w)
    }

    public func sendCommand(_ text: String) {
        var w = ByteWriter()
        w.str(text)
        send(.command, w)
    }
}
