// Flying mounts — creatures you saddle and fly: the pegasus, the dragon, the
// alicorn and the griffin.
// Wild ones are tamed with food (each feeding has a chance) and every one
// needs a saddle; placed ones (spawn eggs, /summon, /spawn, the Tools menu)
// arrive tamed and saddled. Ridden, they fly the way creative flight does:
// forward where the rider faces, jump climbs, sneak descends, sprint goes
// faster, and on the ground a fresh sneak press gets off (GameCore). Wild
// ones take short flights of their own. Three have a power their rider uses
// by holding attack (Player.powerHeld, synced for LAN guests): the dragon
// breathes fire, the alicorn's horn casts magic bolts, and the griffin's
// screech knocks creatures back and sends them running.

import Foundation

/// how fast a ridden flyer climbs or descends (blocks per tick)
public let MOUNT_CLIMB = 0.32
/// horizontal drag in flight; top speed is about thrust / (1 - MOUNT_DRAG)
public let MOUNT_DRAG = 0.91
/// a wild flyer takes off on its own about once in this many ticks
let WILD_FLIGHT_CHANCE = 900

open class FlyingMount: Animal {
    /// kept in `data` so the renderer and LAN guests see them (a guest's
    /// click on its copy decides whether they climb on)
    public var tamed: Bool {
        get { data.tamed ?? false }
        set { data.tamed = newValue ? true : nil }
    }
    public var saddled: Bool {
        get { data.saddled ?? false }
        set { data.saddled = newValue ? true : nil }
    }
    /// in the air under its own wings (gravity off)
    public var flying: Bool {
        get { data.flying ?? false }
        set { data.flying = newValue ? true : nil }
    }
    /// what tames a wild one; each feeding works with `tameChance`
    public var tameFoods: [String] = []
    public var tameChance = 1.0 / 3
    /// what to call it in hints ("Feed it …")
    public var tameHint = ""
    /// horizontal thrust per tick in flight
    public var flyThrust = 0.05
    /// wild flight: ticks left aloft, and the heading it keeps
    var skyTicks = 0
    var skyHeading = 0.0

    public override init(world: World) {
        super.init(world: world)
        stepHeight = 1.0
    }

    open override var fallImmune: Bool { true }

    /// a power its rider uses by holding attack, run each tick it's held
    open var hasPower: Bool { false }
    open func usePower(_ p: Player) {}

    /// the player steering it: riding, and it's tamed and saddled
    public var pilot: Player? {
        guard tamed, saddled, let p = passengers.first as? Player else { return nil }
        return p
    }

    /// spawned by a player: tamed, saddled, kept
    public func makeReady() {
        tamed = true
        saddled = true
        persistent = true
    }

    open override func interact(_ player: Entity, _ stack: ItemStack?) -> Bool {
        let name = stack.map { itemDef($0.id).name }
        let rider = player as? LivingEntity
        if baby { return super.interact(player, stack) }
        if !tamed {
            if let name, tameFoods.contains(name) {
                rider?.consumeHeld(1)
                world.hooks.playSound("entity.generic.eat", x, y, z, 1, 1)
                if gameRng.nextFloat() < tameChance {
                    tamed = true
                    ownerId = player.id
                    persistent = true
                    world.hooks.addParticles("heart", x, y + height, z, 7, 0.6, 0)
                } else {
                    world.hooks.addParticles("smoke", x, y + height, z, 6, 0.5, 0)
                }
                return true
            }
            if stack == nil || name == "saddle" {
                world.hooks.playSound("entity.\(type).angry", x, y, z, 1, 1)
                if let p = player as? Player { world.hooks.tellPlayer?(p, "§eThis \(prettify(type)) is wild. \(tameHint)") }
                return true
            }
            return false
        }
        if name == "saddle" && !saddled {
            saddled = true
            rider?.consumeHeld(1)
            world.hooks.playSound("entity.horse.saddle", x, y, z, 1, 1)
            return true
        }
        if let stack, isFood(stack) {
            if health < maxHealth {
                heal(4)
                rider?.consumeHeld(1)
                world.hooks.playSound("entity.generic.eat", x, y, z, 1, 1)
                return true
            }
            return super.interact(player, stack)
        }
        if !(rider?.sneaking ?? false) {
            if !saddled {
                if let p = player as? Player { world.hooks.tellPlayer?(p, "§ePut a saddle on it to ride") }
                return true
            }
            skyTicks = 0
            player.mount(self)
            return true
        }
        return super.interact(player, stack)
    }

    open override func hurt(_ amount: Double, _ source: DamageSource, _ attacker: Entity? = nil) -> Bool {
        let hit = super.hurt(amount, source, attacker)
        // a wild one takes to the air when something goes for it
        if hit && !tamed && passengers.isEmpty && !baby && source != .fall {
            takeOff(160 + rng.nextInt(160))
        }
        return hit
    }

    func takeOff(_ ticks: Int) {
        if !flying {
            flying = true
            vy = max(vy, 0.45)
            onGround = false
            world.hooks.playSound("entity.\(type).flap", x, y, z, 1, 1)
        }
        skyTicks = ticks
        skyHeading = yaw
    }

    open override func tick() {
        // wild ones go for a flight now and then
        if !tamed && !flying && onGround && passengers.isEmpty && !baby && rng.nextInt(WILD_FLIGHT_CHANCE) == 0 {
            takeOff(200 + rng.nextInt(300))
        }
        super.tick()
        // wings ease open in flight, fold on the ground (drawn; synced)
        let target = flying ? 1.0 : 0.0
        let w = data.wings ?? 0
        let next = w < target ? min(target, w + 0.2) : max(target, w - 0.12)
        data.wings = next > 0 ? next : nil
        let using = hasPower && (pilot?.powerHeld ?? false)
        data.breathing = using ? true : nil
        if using, let p = pilot { usePower(p) }
        if flying && age % 12 == 0 {
            world.hooks.playSound("entity.\(type).flap", x, y, z, pilot != nil ? 0.5 : 0.8, 0.9 + rng.nextFloat() * 0.2)
        }
    }

    public override func travel() {
        noGravity = flying
        if let p = pilot {
            ridden(p)
        } else if flying {
            wildFlight()
        } else {
            super.travel()
        }
    }

    /// the rider flies it like creative flight
    func ridden(_ p: Player) {
        yaw = p.yaw
        headYaw = p.yaw
        pitch = clampD(p.pitch * 0.5, -0.6, 0.6)
        nav.stop()   // (it zeroes the move input, so before the rider's goes in)
        moveForward = p.moveForward
        moveStrafe = p.moveStrafe
        if !flying {
            // a jump takes off (also off a ledge mid-fall)
            if p.jumping {
                takeOff(0)
            } else {
                super.travel()
                return
            }
        }
        applyInput(flyThrust * (p.sprinting ? 1.6 : 1))
        let want = p.jumping ? MOUNT_CLIMB : p.sneaking ? -MOUNT_CLIMB : 0
        vy += (want - vy) * 0.35
        move(vx, vy, vz)
        vx *= MOUNT_DRAG
        vz *= MOUNT_DRAG
        fallDistance = 0
        // touched down: walk again until the next jump
        if onGround && !p.jumping { flying = false }
        flapAnim()
    }

    /// on its own: cruise along a heading well above the ground, then come down
    func wildFlight() {
        if skyTicks > 0 { skyTicks -= 1 }
        if horizontalCollision {
            skyHeading += .pi / 2
            vy = max(vy, 0.25)
        } else if age % 60 == 0 {
            skyHeading += (rng.nextFloat() - 0.5) * 1.6
        }
        yaw += wrapAngle(skyHeading - yaw) * 0.08
        headYaw = yaw
        pitch = 0
        moveForward = skyTicks > 0 ? 1 : 0.4
        moveStrafe = 0
        applyInput(flyThrust * 0.6)
        let floor = Double(groundBelow())
        let wantY = skyTicks > 0 ? floor + 8 : floor - 2
        let climb = clampD((wantY - y) * 0.05, -0.2, MOUNT_CLIMB * 0.6)
        vy += (climb - vy) * 0.2
        move(vx, vy, vz)
        vx *= MOUNT_DRAG
        vz *= MOUNT_DRAG
        fallDistance = 0
        if onGround && skyTicks <= 0 { flying = false }
        flapAnim()
    }

    /// the highest solid block within 32 below
    func groundBelow() -> Int {
        let bx = ifloor(x), bz = ifloor(z)
        var yy = ifloor(y)
        let stop = yy - 32
        while yy > stop {
            if blockDefs[world.getBlockId(bx, yy, bz)].solid { return yy + 1 }
            yy -= 1
        }
        return stop
    }

    /// legs keep a gentle stride in the air (the renderer tucks them)
    private func flapAnim() {
        let dxm = x - prevX, dzm = z - prevZ
        let moved = min(1, (dxm * dxm + dzm * dzm).squareRoot() * 4)
        limbAmp += (moved * 0.3 - limbAmp) * 0.4
        limbSwing += limbAmp * 1.2
    }

    /// what a power may hit: living, and not the rider, the mount or the rider's pets
    func isFoe(_ e: EntityRef, of p: Player) -> Bool {
        guard let l = e as? LivingEntity, !l.dead, l !== p, l !== self else { return false }
        if let m = l as? Mob, m.ownerId == p.id { return false }
        return true
    }

    open override func drops() -> [DropEntry] {
        saddled ? [DropEntry("saddle")] : []
    }
    open override func save() -> [String: Any] {
        var d = super.save()
        d["tamed"] = tamed
        d["saddled"] = saddled
        if flying { d["flying"] = true }
        return d
    }
    open override func load(_ d: [String: Any]) {
        super.load(d)
        tamed = (d["tamed"] as? Bool) ?? false
        saddled = (d["saddled"] as? Bool) ?? false
        flying = (d["flying"] as? Bool) ?? false
    }
}

// ---------------------------------------------------------------------------
// Pegasus: a winged horse. Tamed with golden carrots or golden apples.
// ---------------------------------------------------------------------------
public final class Pegasus: FlyingMount {
    public override var type: String { "pegasus" }
    public override init(world: World) {
        super.init(world: world)
        width = 1.4; height = 1.7
        maxHealth = 30; health = 30
        speed = 0.22
        flyThrust = 0.055
        foods = ["golden_carrot", "golden_apple"]
        tameFoods = foods
        tameHint = "Feed it a golden carrot or golden apple to tame it"
        xpReward = 5
        addBasicGoals(1, 1.6)
    }
    public override var seatHeight: Double { 1.15 }
    public override func drops() -> [DropEntry] {
        super.drops() + [DropEntry("feather", min: 1, max: 3, lootingBonus: 1), DropEntry("leather", min: 0, max: 2, lootingBonus: 1)]
    }
}

// ---------------------------------------------------------------------------
// Dragon: tamed with raw meat or fish. Fire can't hurt it, and it breathes
// fire while its rider holds attack.
// ---------------------------------------------------------------------------
/// how far the dragon's fire reaches (blocks)
public let DRAGON_BREATH_RANGE = 10.0

public final class Dragon: FlyingMount {
    public override var type: String { "dragon" }
    public override init(world: World) {
        super.init(world: world)
        width = 2.2; height = 2.2
        maxHealth = 60; health = 60
        speed = 0.18
        flyThrust = 0.06
        foods = ["beef", "porkchop", "mutton", "chicken", "rabbit", "cod", "salmon"]
        tameFoods = foods
        tameHint = "Feed it raw meat or fish to tame it"
        xpReward = 10
        attackDamage = 6
        addBasicGoals(1, 1.4)
    }
    public override var seatHeight: Double { 1.6 }

    public override func hurt(_ amount: Double, _ source: DamageSource, _ attacker: Entity? = nil) -> Bool {
        if source.isFire { fireTicks = 0; return false }
        return super.hurt(amount, source, attacker)
    }

    public override var hasPower: Bool { true }
    public override func usePower(_ p: Player) { breathe(p) }

    public override func tick() {
        super.tick()
        fireTicks = 0
    }

    /// one tick of fire along the rider's view: flames in a cone ahead, and
    /// everything living in it (but the rider and their pets) catches fire
    func breathe(_ p: Player) {
        let (dx, dy, dz) = p.lookDir()
        // from the mouth, a little ahead of the rider
        let mx = x - detSin(yaw) * 2.2, my = y + 1.6, mz = z + detCos(yaw) * 2.2
        var t = 0.5
        while t <= DRAGON_BREATH_RANGE {
            let spread = 0.1 + t * 0.1
            world.hooks.addParticles("dragon_fire", mx + dx * t, my + dy * t, mz + dz * t, t < 4 ? 3 : 4, spread, 0)
            t += 1
        }
        if age % 3 == 0 { world.hooks.addParticles("smoke", mx + dx * DRAGON_BREATH_RANGE, my + dy * DRAGON_BREATH_RANGE, mz + dz * DRAGON_BREATH_RANGE, 2, 1, 0) }
        if age % 6 == 0 { world.hooks.playSound("entity.dragon.breath", mx, my, mz, 1.2, 0.9 + rng.nextFloat() * 0.2) }
        let near = world.getEntitiesNear(mx + dx * 5, my + dy * 5, mz + dz * 5, DRAGON_BREATH_RANGE / 2 + 2) { e in
            self.isFoe(e, of: p)
        }
        for case let l as LivingEntity in near {
            // inside the cone: ahead of the mouth and close to the line
            let rx = l.x - mx, ry = l.y + l.height / 2 - my, rz = l.z - mz
            let s = rx * dx + ry * dy + rz * dz
            if s < 0 || s > DRAGON_BREATH_RANGE { continue }
            let off = detHyp3(rx - dx * s, ry - dy * s, rz - dz * s)
            if off > 0.6 + s * 0.15 + l.width / 2 { continue }
            l.fireTicks = max(l.fireTicks, 100)
            _ = l.hurt(3, .fire, p)
        }
    }
}

// ---------------------------------------------------------------------------
// Alicorn: a winged unicorn. Tamed with golden apples or glistering melon.
// Its horn casts magic bolts while the rider holds attack.
// ---------------------------------------------------------------------------
/// how far a bolt flies (blocks), how fast (blocks per tick), what it deals
public let ALICORN_BOLT_RANGE = 32.0
public let ALICORN_BOLT_SPEED = 1.6
public let ALICORN_BOLT_DAMAGE = 5.0
/// ticks between bolts while attack is held
public let ALICORN_BOLT_EVERY = 6

public final class Alicorn: FlyingMount {
    public override var type: String { "alicorn" }
    struct Bolt { var x, y, z: Double; let dx, dy, dz: Double; var flown: Double; let rider: Player }
    /// bolts in flight (not saved: they live a second or so)
    var bolts: [Bolt] = []
    public var boltsInFlight: Int { bolts.count }
    public private(set) var boltCooldown = 0

    public override init(world: World) {
        super.init(world: world)
        width = 1.4; height = 1.7
        maxHealth = 40; health = 40
        speed = 0.23
        flyThrust = 0.058
        foods = ["golden_apple", "glistering_melon_slice"]
        tameFoods = foods
        tameHint = "Feed it a golden apple or glistering melon slice to tame it"
        xpReward = 8
        addBasicGoals(1, 1.6)
    }
    public override var seatHeight: Double { 1.15 }
    public override var hasPower: Bool { true }

    /// the horn's tip, ahead of and above the rider
    public var hornTip: (Double, Double, Double) {
        (x - detSin(yaw) * 1.5, y + 2.15, z + detCos(yaw) * 1.5)
    }

    public override func usePower(_ p: Player) {
        if boltCooldown > 0 { return }
        boltCooldown = ALICORN_BOLT_EVERY
        // from the horn toward what the rider's crosshair is on (the horn sits
        // below and ahead of their eye), or a bolt's range out along their view
        let (lx, ly, lz) = p.lookDir()
        let ex = p.x, ey = p.eyeY(), ez = p.z
        let reach = world.raycast(ex, ey, ez, lx, ly, lz, ALICORN_BOLT_RANGE)?.t ?? ALICORN_BOLT_RANGE
        let (hx, hy, hz) = hornTip
        var dx = ex + lx * reach - hx, dy = ey + ly * reach - hy, dz = ez + lz * reach - hz
        let len = detHyp3(dx, dy, dz)
        if len < 2 { dx = lx; dy = ly; dz = lz } else { dx /= len; dy /= len; dz /= len }
        bolts.append(Bolt(x: hx, y: hy, z: hz, dx: dx, dy: dy, dz: dz, flown: 0, rider: p))
        world.hooks.addParticles("magic_bolt", hx, hy, hz, 6, 0.15, 0)
        world.hooks.playSound("entity.alicorn.bolt", hx, hy, hz, 1, 0.9 + rng.nextFloat() * 0.25)
    }

    public override func tick() {
        super.tick()
        if boltCooldown > 0 { boltCooldown -= 1 }
        if !bolts.isEmpty { bolts = bolts.compactMap(flyBolt) }
    }

    /// one tick of a bolt, in short steps: it stops at the first solid block
    /// or creature (nil), sparkling along the way
    func flyBolt(_ b0: Bolt) -> Bolt? {
        var b = b0
        let step = 0.4
        var moved = 0.0
        while moved < ALICORN_BOLT_SPEED {
            b.x += b.dx * step; b.y += b.dy * step; b.z += b.dz * step
            moved += step
            b.flown += step
            world.hooks.addParticles("magic_bolt", b.x, b.y, b.z, 2, 0.06, 0)
            if blockDefs[world.getBlockId(ifloor(b.x), ifloor(b.y), ifloor(b.z))].solid {
                burst(b)
                return nil
            }
            let hit = world.getEntitiesNear(b.x, b.y, b.z, 3) { e in
                guard self.isFoe(e, of: b.rider), let l = e as? LivingEntity else { return false }
                let bb = l.bb()
                return b.x > bb.x0 - 0.3 && b.x < bb.x1 + 0.3 && b.y > bb.y0 - 0.3 && b.y < bb.y1 + 0.3
                    && b.z > bb.z0 - 0.3 && b.z < bb.z1 + 0.3
            }.first as? LivingEntity
            if let hit {
                if hit.hurt(ALICORN_BOLT_DAMAGE, .magic, b.rider) {
                    hit.vx += b.dx * 0.4; hit.vz += b.dz * 0.4
                    hit.vy = max(hit.vy, 0.25)
                }
                burst(b)
                return nil
            }
            if b.flown >= ALICORN_BOLT_RANGE { return nil }
        }
        return b
    }

    private func burst(_ b: Bolt) {
        world.hooks.addParticles("magic_bolt", b.x, b.y, b.z, 14, 0.4, 0)
        world.hooks.playSound("entity.alicorn.bolt_hit", b.x, b.y, b.z, 0.8, 1)
    }

    public override func drops() -> [DropEntry] {
        super.drops() + [DropEntry("feather", min: 1, max: 3, lootingBonus: 1), DropEntry("leather", min: 0, max: 2, lootingBonus: 1)]
    }
}

// ---------------------------------------------------------------------------
// Griffin: an eagle's head, wings and talons on a lion's body. Tamed with raw
// meat. The fastest flyer; its screech, while the rider holds attack, knocks
// the creatures around it back and sends them running.
// ---------------------------------------------------------------------------
/// how far the screech reaches (blocks), and ticks between screeches
public let GRIFFIN_SCREECH_RANGE = 10.0
public let GRIFFIN_SCREECH_EVERY = 24
/// how long a screeched creature runs (ticks)
public let GRIFFIN_SCARE_TICKS = 120

public final class Griffin: FlyingMount {
    public override var type: String { "griffin" }
    var screechCooldown = 0
    /// the expanding ring of the last screech: ticks since, and where (drawn only)
    var waveAge = -1
    var waveX = 0.0, waveY = 0.0, waveZ = 0.0

    public override init(world: World) {
        super.init(world: world)
        width = 1.4; height = 1.8
        maxHealth = 40; health = 40
        speed = 0.24
        flyThrust = 0.068
        foods = ["rabbit", "chicken", "beef", "mutton", "porkchop"]
        tameFoods = foods
        tameHint = "Feed it raw meat to tame it"
        xpReward = 8
        attackDamage = 4
        addBasicGoals(1, 1.6)
    }
    public override var seatHeight: Double { 1.2 }
    public override var hasPower: Bool { true }

    public override func usePower(_ p: Player) {
        if screechCooldown > 0 { return }
        screechCooldown = GRIFFIN_SCREECH_EVERY
        screech(p)
    }

    /// every creature in range (not the rider, their pets, other players or
    /// the bosses) is thrown back from the griffin and runs
    func screech(_ p: Player) {
        let cy = y + height * 0.6
        world.hooks.playSound("entity.griffin.screech", x, cy, z, 2, 0.95 + rng.nextFloat() * 0.1)
        waveAge = 0
        waveX = x; waveY = cy; waveZ = z
        let near = world.getEntitiesNear(x, cy, z, GRIFFIN_SCREECH_RANGE) { e in
            self.isFoe(e, of: p) && !(e is Player) && !(e is Warden) && !(e is RiftDragon) && !(e is BlightBoss)
        }
        for case let l as LivingEntity in near {
            var dx = l.x - x, dz = l.z - z
            let d = detHyp(dx, dz)
            if d > GRIFFIN_SCREECH_RANGE { continue }
            if d < 0.01 { dx = -detSin(yaw); dz = detCos(yaw) } else { dx /= d; dz /= d }
            let f = 1 - d / GRIFFIN_SCREECH_RANGE
            let push = 0.5 + 1.3 * f
            l.vx += dx * push; l.vz += dz * push
            l.vy = max(l.vy, 0.3 + 0.35 * f)
            l.onGround = false
            if let m = l as? Mob { m.scare(from: x, z, ticks: GRIFFIN_SCARE_TICKS) }
        }
    }

    public override func tick() {
        super.tick()
        if screechCooldown > 0 { screechCooldown -= 1 }
        // the screech ring spreads out over a few ticks
        if waveAge >= 0 {
            let r = 1 + Double(waveAge) * 1.4
            let n = min(48, Int(r * 6))
            for i in 0..<n {
                let a = Double(i) / Double(n) * .pi * 2
                world.hooks.addParticles("screech", waveX + detSin(a) * r, waveY, waveZ + detCos(a) * r, 2, 0.15, 0)
            }
            waveAge += 1
            if r >= GRIFFIN_SCREECH_RANGE { waveAge = -1 }
        }
    }

    public override func drops() -> [DropEntry] {
        super.drops() + [DropEntry("feather", min: 2, max: 4, lootingBonus: 1), DropEntry("leather", min: 0, max: 2, lootingBonus: 1)]
    }
}
