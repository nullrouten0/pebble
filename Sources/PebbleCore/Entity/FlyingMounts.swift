// Flying mounts — creatures you saddle and fly: the pegasus and the dragon.
// Wild ones are tamed with food (each feeding has a chance) and every one
// needs a saddle; placed ones (spawn eggs, /summon, /spawn, the Tools menu)
// arrive tamed and saddled. Ridden, they fly the way creative flight does:
// forward where the rider faces, jump climbs, sneak descends, sprint goes
// faster, and on the ground a fresh sneak press gets off (GameCore). Wild
// ones take short flights of their own. The dragon breathes fire while its
// rider holds attack (Player.breathHeld, synced for LAN guests).

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

    public override func tick() {
        super.tick()
        fireTicks = 0
        let breathing = pilot?.breathHeld ?? false
        data.breathing = breathing ? true : nil
        if breathing { breathe(pilot!) }
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
            guard let l = e as? LivingEntity, !l.dead, l !== p, l !== self else { return false }
            if let m = l as? Mob, m.ownerId == p.id { return false }
            return true
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
