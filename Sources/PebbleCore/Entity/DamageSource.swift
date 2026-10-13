// What hurt an entity. The raw values are what LAN `.hurt` messages carry and
// what a player's saved `deathCause` holds, so they're part of the formats:
// add cases freely, but don't rename one.

public enum DamageSource: String {
    // attacks
    case mob, player, projectile, fireball
    case blightSkull = "blight_skull"
    case explosion, thorns, sonic, sting, firework
    // effects
    case magic, blight, poison
    // the world
    case fall
    case flyIntoWall = "fly_into_wall"
    case anvil, lightning, fire, lava, drown, freeze, starve, void

    /// fire protection applies, fire resistance and fire-immune mobs ignore it
    public var isFire: Bool { self == .fire || self == .lava }

    /// damage that armor doesn't reduce
    public var bypassesArmor: Bool {
        switch self {
        case .fall, .void, .magic, .blight, .starve, .drown, .freeze, .sonic: return true
        default: return false
        }
    }

    /// a raised shield facing the attacker stops it
    public var shieldable: Bool {
        switch self {
        case .mob, .player, .projectile, .explosion, .fireball, .blightSkull: return true
        default: return false
        }
    }
}

/// a player's death-screen line, from the `deathCause` its save recorded
/// (a DamageSource raw value, or "fall_high" for a fall of more than 5
/// blocks) and the name of whoever last hurt it
public func deathCauseText(_ cause: String?, _ attacker: String? = nil) -> String {
    let high = cause == "fall_high"
    guard let source = high ? .fall : cause.flatMap(DamageSource.init(rawValue:)) else { return "didn't make it" }
    if let a = attacker {
        switch source {
        case .mob, .player: return "was defeated by \(a)"
        case .projectile: return "took an arrow from \(a)"
        case .fireball: return "was scorched by \(a)'s fireball"
        case .blightSkull: return "was hit by \(a)'s blight skull"
        case .explosion: return "was caught in \(a)'s blast"
        case .thorns: return "was cut on \(a)'s thorns"
        case .sonic: return "was flattened by \(a)'s sonic boom"
        case .sting: return "was stung once too often by \(a)"
        case .firework: return "was caught by a firework while facing \(a)"
        case .magic: return "was undone by \(a)'s magic"
        case .blight: return "succumbed to blight while facing \(a)"
        case .poison: return "didn't make it"
        case .fall: return high ? "took a long fall while running from \(a)" : "landed badly while running from \(a)"
        case .flyIntoWall: return "hit a wall at speed while running from \(a)"
        case .anvil: return "was crushed by an anvil while facing \(a)"
        case .lightning: return "was hit by lightning while facing \(a)"
        case .fire: return "burned while facing \(a)"
        case .lava: return "fled from \(a) into lava"
        case .drown: return "ran out of air while running from \(a)"
        case .freeze: return "was frozen solid by \(a)"
        case .starve: return "starved while facing \(a)"
        case .void: return "dropped into the void while running from \(a)"
        }
    }
    switch source {
    case .mob, .player: return "was defeated"
    case .projectile: return "took an arrow"
    case .fireball: return "was scorched by a fireball"
    case .blightSkull: return "was hit by a blight skull"
    case .explosion: return "was caught in a blast"
    case .thorns: return "was cut on thorns"
    case .sonic: return "was flattened by a sonic boom"
    case .sting: return "was stung once too often"
    case .firework: return "was caught by a firework"
    case .magic: return "was undone by magic"
    case .blight: return "succumbed to blight"
    case .poison: return "didn't make it"
    case .fall: return high ? "took a long fall" : "landed badly"
    case .flyIntoWall: return "hit a wall at speed"
    case .anvil: return "was crushed by an anvil"
    case .lightning: return "was hit by lightning"
    case .fire: return "burned"
    case .lava: return "fell into lava"
    case .drown: return "ran out of air"
    case .freeze: return "froze solid"
    case .starve: return "starved"
    case .void: return "dropped into the void"
    }
}
