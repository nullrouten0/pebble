// Block destroyers — the bazooka (rocket → carving blast) and the mining laser
// (hold to bore a round tunnel). Vanilla explosion rays die after 2–4 blocks of
// stone, so these use their own rule: everything inside the shape goes except
// unbreakable blocks (bedrock, barriers, portal frames). No item drops — a big
// crater would otherwise spawn thousands of item entities.
// Player-driven only; never runs in worldgen or the golden scenarios.

import Foundation

/// a multi-tick destroyer in progress; `step` removes up to `budget` cells
public protocol DestroyJob: AnyObject {
    func step(_ budget: Int) -> Int
    var done: Bool { get }
    /// set when the job is undone mid-way
    var cancelled: Bool { get set }
}

/// cancel any job still writing into an edit that's being undone
func stopJobs(of b: EditBatch) {
    for j in b.jobs { j.cancelled = true }
    b.jobs.removeAll()
}

/// a blast eaten as an expanding shell over several ticks, so a big crater
/// doesn't stall one frame (and looks better)
public final class CarveJob: DestroyJob {
    let world: World
    let batch: EditBatch
    public var cancelled = false
    let radius: Double
    /// cells (world coords) sorted by distance from the center
    let cells: [(Int, Int, Int, Double)]
    var idx = 0
    var shell = 0.0
    let speed: Double
    let frontParticle: String

    init(_ world: World, _ batch: EditBatch, _ x: Double, _ y: Double, _ z: Double, _ radius: Double, rough: Double, speed: Double,
         frontParticle: String = "explosion") {
        self.world = world
        self.batch = batch
        self.radius = radius
        self.speed = speed
        self.frontParticle = frontParticle
        let r = Int(radius.rounded(.up))
        let bx = ifloor(x), by = ifloor(y), bz = ifloor(z)
        var out: [(Int, Int, Int, Double)] = []
        for oy in -r...r {
            for oz in -r...r {
                for ox in -r...r {
                    let cx = bx + ox, cy = by + oy, cz = bz + oz
                    let d = detHyp3(Double(cx) + 0.5 - x, Double(cy) + 0.5 - y, Double(cz) + 0.5 - z)
                    // ragged rim: each cell gets its own cutoff
                    let n = Double(hash3(0xB1A57, cx, cy, cz) & 0xFFFF) / 65535
                    if d <= radius * (1 - rough * n) { out.append((cx, cy, cz, d)) }
                }
            }
        }
        cells = out.sorted { $0.3 < $1.3 }
    }

    /// carve up to `budget` cells; returns cells processed
    public func step(_ budget: Int) -> Int {
        shell += speed
        var n = 0
        let edge = radius - 1.5
        while idx < cells.count, cells[idx].3 <= shell, n < budget {
            let (x, y, z, d) = cells[idx]
            idx += 1
            n += 1
            carveCell(batch, x, y, z, d > edge)
        }
        // smoke on the advancing front
        if idx < cells.count, world.time % 2 == 0 {
            let (x, y, z, _) = cells[idx]
            world.hooks.addParticles(frontParticle, Double(x) + 0.5, Double(y) + 0.5, Double(z) + 0.5,
                                     frontParticle == "explosion" ? 2 : 12, 1.5, 0)
        }
        return n
    }
    public var done: Bool { cancelled || idx >= cells.count }
}

public private(set) var carveJobs: [DestroyJob] = []
/// recent blasts (x, y, z, radius) for the app's screen shake; drained by GameCore
public var pendingBlasts: [(Double, Double, Double, Double)] = []

/// remove one cell unless unbreakable; rim cells notify neighbors so sand falls
/// and water flows into the hole, interior cells skip it (cheaper)
@inline(__always) func carveCell(_ b: EditBatch, _ x: Int, _ y: Int, _ z: Int, _ rim: Bool) {
    let id = b.world.getBlockId(x, y, z)
    if id == 0 || blockDefs[id].hardness < 0 { return }
    b.set(x, y, z, 0, rim ? SET_DEFAULT : SET_NO_NEIGHBORS)
}

/// run `body` with edits credited to whoever `e` is (a LAN guest's player
/// gets their own undo history; everything else is the local player's)
func withEditOwner(_ e: Entity?, _ body: () -> Void) {
    let prev = editOwner
    if let p = e as? Player, p.isNetProxy { editOwner = p.id }
    body()
    editOwner = prev
}

func addJob(_ j: DestroyJob, _ b: EditBatch) {
    carveJobs.append(j)
    b.jobs.append(j)
}

/// queue a carving blast and hit entities in range right away
public func startCarve(_ w: World, _ x: Double, _ y: Double, _ z: Double, _ radius: Double,
                       rough: Double = 0.3, speed: Double = 1.0, source: Entity? = nil) {
    let b = beginEdit(w, "bazooka blast")
    addJob(CarveJob(w, b, x, y, z, radius, rough: rough, speed: speed), b)
    pendingBlasts.append((x, y, z, radius))
    w.hooks.playSound("entity.generic.explode", x, y, z, 6, max(0.4, 1.1 - radius * 0.05))
    w.hooks.addParticles("explosion", x, y, z, Int(min(60, radius * 6)), radius * 0.5, 0)
    w.hooks.addParticles("smoke", x, y, z, Int(min(80, radius * 8)), radius * 0.6, 0)
    let reach = radius * 1.6
    for e in w.getEntitiesNear(x, y, z, reach) {
        guard let ent = e as? Entity, !(ent is Projectile) else { continue }
        let dx = ent.x - x, dy = ent.y + ent.height / 2 - y, dz = ent.z - z
        let dist = detHyp3(dx, dy, dz)
        if dist > reach { continue }
        let exposure = 1 - dist / reach
        ent.hurt(((exposure * exposure + exposure) / 2 * 3.5 * radius + 1).rounded(.down), "explosion", source)
        let d = max(dist, 1)
        ent.vx += dx / d * exposure * 1.5
        ent.vy += dy / d * exposure * 1.5 + 0.2
        ent.vz += dz / d * exposure * 1.5
    }
}

/// advance every carve in progress; ~8k cells/tick total keeps frames smooth
public func tickCarveJobs() {
    var budget = 12000
    for job in carveJobs where budget > 0 { budget -= job.step(budget) }
    carveJobs.removeAll { $0.done }
}

// ---------------------------------------------------------------------------
// Bazooka
// ---------------------------------------------------------------------------
public let BAZOOKA_RADIUS = 9.0
private var bazookaReadyAt = [ObjectIdentifier: Int]()

public final class Rocket: Projectile {
    public override var type: String { "rocket" }
    public var radius = BAZOOKA_RADIUS
    public override init(world: World) {
        super.init(world: world)
        gravity = 0.004
        drag = 1
        width = 0.3
        height = 0.3
    }
    public override func tick() {
        super.tick()
        if dead { return }
        world.hooks.addParticles("smoke", x - vx * 0.5, y - vy * 0.5, z - vz * 0.5, 2, 0.08, 0)
        if age % 2 == 0 { world.hooks.addParticles("flame", x - vx * 0.3, y - vy * 0.3, z - vz * 0.3, 1, 0.03, 0) }
        if age > 120 { detonate() } // ~430 blocks out
    }
    public override func onHitEntity(_ e: Entity) { detonate() }
    public override func onHitBlock(_ hit: RaycastHit) {
        // center the blast a little inside what we hit
        let s = max(0.001, detHyp3(vx, vy, vz))
        x += vx / s; y += vy / s; z += vz / s
        detonate()
    }
    private func detonate() {
        if dead { return }
        withEditOwner(owner) { startCarve(world, x, y, z, radius, rough: 0.3, speed: 2.0, source: owner) }
        remove()
    }
}

/// fire a rocket along the player's look; false while reloading
public func fireBazooka(_ w: World, _ p: Player) -> Bool {
    let key = ObjectIdentifier(p)
    if let t = bazookaReadyAt[key], w.time < t, w.time >= t - 20 { return false }
    bazookaReadyAt[key] = w.time + 12
    let r = Rocket(world: w)
    r.shootFrom(p, p.pitch, p.yaw, 3.6, 0)
    w.addEntity(r)
    w.hooks.playSound("pebble.bazooka.fire", p.x, p.y, p.z, 2, 1)
    w.hooks.addParticles("smoke", p.x, p.eyeY(), p.z, 6, 0.3, 0)
    // recoil
    p.vx += detSin(p.yaw) * detCos(p.pitch) * 0.25
    p.vz -= detCos(p.yaw) * detCos(p.pitch) * 0.25
    return true
}

// ---------------------------------------------------------------------------
// Void bomb — thrown; deletes a clean sphere (no rim noise, no damage)
// ---------------------------------------------------------------------------
public let VOID_BOMB_RADIUS = 12.0
public let VOID_BOMB_BIG_RADIUS = 24.0

public final class VoidBomb: Projectile {
    public override var type: String { "void_bomb" }
    public var radius = VOID_BOMB_RADIUS
    public override init(world: World) {
        super.init(world: world)
        gravity = 0.03
        width = 0.3
        height = 0.3
    }
    public override func tick() {
        super.tick()
        if dead { return }
        world.hooks.addParticles("portal", x, y, z, 3, 0.15, 0)
        if age > 400 { remove() }
    }
    public override func onHitEntity(_ e: Entity) { detonate() }
    public override func onHitBlock(_ hit: RaycastHit) {
        x = hit.px; y = hit.py; z = hit.pz
        detonate()
    }
    private func detonate() {
        if dead { return }
        withEditOwner(owner) { startVoid(world, x, y, z, radius) }
        remove()
    }
}

/// queue a clean sphere deletion: no ragged rim, no entity damage
public func startVoid(_ w: World, _ x: Double, _ y: Double, _ z: Double, _ radius: Double) {
    let b = beginEdit(w, "void bomb")
    addJob(CarveJob(w, b, x, y, z, radius, rough: 0, speed: 3, frontParticle: "portal"), b)
    pendingBlasts.append((x, y, z, radius * 0.4))
    w.hooks.playSound("pebble.void.implode", x, y, z, 8, 1)
    w.hooks.addParticles("portal", x, y, z, 80, radius * 0.4, 0)
    w.hooks.addParticles("dragon_breath", x, y, z, 40, radius * 0.3, 0)
}

/// throw a void bomb; sneaking throws the big one
public func throwVoidBomb(_ w: World, _ p: Player) -> Bool {
    let b = VoidBomb(world: w)
    b.radius = p.sneaking ? VOID_BOMB_BIG_RADIUS : VOID_BOMB_RADIUS
    b.shootFrom(p, p.pitch, p.yaw, 1.6, 0)
    w.addEntity(b)
    w.hooks.playSound("entity.snowball.throw", p.x, p.y, p.z, 0.6, 0.4)
    p.consumeHeld(1)
    return true
}

// ---------------------------------------------------------------------------
// Quarry charge — use on a block; eats a square shaft down to bedrock
// ---------------------------------------------------------------------------
public let QUARRY_SIZE = 9
public let QUARRY_BIG_SIZE = 17

public final class QuarryJob: DestroyJob {
    let world: World
    let batch: EditBatch
    public var cancelled = false
    let x0: Int, z0: Int, x1: Int, z1: Int
    var y: Int
    let bottom: Int
    var tickN = 0

    init(_ w: World, _ batch: EditBatch, _ cx: Int, _ topY: Int, _ cz: Int, _ size: Int) {
        world = w
        self.batch = batch
        let h = size / 2
        x0 = cx - h; x1 = cx - h + size - 1
        z0 = cz - h; z1 = cz - h + size - 1
        y = topY
        bottom = w.info.minY
    }

    /// one layer per tick (the budget only stops it mid-blast-storm)
    public func step(_ budget: Int) -> Int {
        if done || budget < (x1 - x0 + 1) * (z1 - z0 + 1) { return 0 }
        tickN += 1
        var n = 0
        for z in z0...z1 {
            for x in x0...x1 {
                let rim = x == x0 || x == x1 || z == z0 || z == z1
                carveCell(batch, x, y, z, rim)
                n += 1
            }
        }
        let mx = Double(x0 + x1) / 2 + 0.5, mz = Double(z0 + z1) / 2 + 0.5
        let fy = Double(y) + 0.5
        world.hooks.addParticles("smoke", mx, fy, mz, 6, Double(x1 - x0) * 0.3, 0)
        world.hooks.addParticles("explosion", mx, fy, mz, 1, Double(x1 - x0) * 0.3, 0)
        if tickN % 3 == 0 { world.hooks.playSound("pebble.quarry.dig", mx, fy, mz, 3, 0.9 + Double(tickN % 7) * 0.03) }
        y -= 1
        return n
    }
    public var done: Bool { cancelled || y < bottom }
}

/// arm a quarry charge on the clicked block; sneaking makes the big shaft
public func armQuarryCharge(_ w: World, _ p: Player, _ hit: RaycastHit) -> Bool {
    startQuarry(w, hit.x, hit.y, hit.z, p.sneaking ? QUARRY_BIG_SIZE : QUARRY_SIZE)
    p.consumeHeld(1)
    return true
}

/// queue a size×size shaft centered on (x,z), from y down to the world floor
public func startQuarry(_ w: World, _ x: Int, _ y: Int, _ z: Int, _ size: Int) {
    let b = beginEdit(w, "quarry")
    addJob(QuarryJob(w, b, x, y, z, size), b)
    w.hooks.playSound("pebble.quarry.arm", Double(x) + 0.5, Double(y) + 1, Double(z) + 0.5, 2, 1)
}

// ---------------------------------------------------------------------------
// Mining laser
// ---------------------------------------------------------------------------
public let LASER_RANGE = 64.0
/// one undo batch per continuous laser burst
private var laserBatch = [ObjectIdentifier: (EditBatch, Int)]()

/// one tick of beam: erase a round slab (radius 2.5 → 5 wide, or 4.5 → 9 wide)
/// two blocks deep where the beam lands. Hold it to bore a tunnel.
public func fireLaser(_ w: World, _ p: Player, wide: Bool, tick: Int) {
    let dx = -detSin(p.yaw) * detCos(p.pitch)
    let dy = -detSin(p.pitch)
    let dz = detCos(p.yaw) * detCos(p.pitch)
    let ex = p.x, ey = p.eyeY(), ez = p.z
    let hit = w.raycast(ex, ey, ez, dx, dy, dz, LASER_RANGE)
    let len = hit?.t ?? LASER_RANGE
    // beam
    var t = 1.2
    while t < len {
        w.hooks.addParticles("crit", ex + dx * t, ey - 0.15 + dy * t, ez + dz * t, 1, 0.02, 0)
        t += 1.5
    }
    if tick % 4 == 0 { w.hooks.playSound("pebble.laser.hum", ex, ey, ez, 0.8, wide ? 0.8 : 1) }
    guard let hit else { return }
    w.hooks.addParticles("block", hit.px, hit.py, hit.pz, 6, 0.4, hit.cell)
    w.hooks.addParticles("smoke", hit.px, hit.py, hit.pz, 2, 0.3, 0)

    let key = ObjectIdentifier(p)
    let batch: EditBatch
    if let (b, last) = laserBatch[key], last >= w.time - 2, undoStack.last(where: { $0.owner == b.owner }) === b { batch = b }
    else { batch = beginEdit(w, "mining laser") }
    laserBatch[key] = (batch, w.time)
    let R = wide ? 4.5 : 2.5
    let s0 = hit.t - 0.3, s1 = hit.t + 2
    let ax = ex + dx * s0, ay = ey + dy * s0, az = ez + dz * s0
    let bx = ex + dx * s1, by = ey + dy * s1, bz = ez + dz * s1
    let x0 = ifloor(min(ax, bx) - R), x1 = ifloor(max(ax, bx) + R)
    let y0 = ifloor(min(ay, by) - R), y1 = ifloor(max(ay, by) + R)
    let z0 = ifloor(min(az, bz) - R), z1 = ifloor(max(az, bz) + R)
    for y in y0...y1 {
        for z in z0...z1 {
            for x in x0...x1 {
                let cx = Double(x) + 0.5 - ex, cy = Double(y) + 0.5 - ey, cz = Double(z) + 0.5 - ez
                let s = cx * dx + cy * dy + cz * dz
                if s < s0 || s > s1 { continue }
                let perp = detHyp3(cx - dx * s, cy - dy * s, cz - dz * s)
                if perp > R { continue }
                carveCell(batch, x, y, z, perp > R - 1.2)
            }
        }
    }
}
