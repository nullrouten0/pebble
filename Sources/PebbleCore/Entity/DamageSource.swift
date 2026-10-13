// What hurt an entity. The raw values are what LAN `.hurt` messages carry and
// what a player's saved `deathCause` holds, so they're part of the formats:
// add cases freely, but don't rename one.

public enum DamageSource: String {
    // attacks
    case mob, player, projectile, fireball
    case witherSkull = "wither_skull"
    case explosion, thorns, sonic, sting, firework
    // effects
    case magic, wither, poison
    // the world
    case fall
    case flyIntoWall = "fly_into_wall"
    case anvil, lightning, fire, lava, drown, freeze, starve, void

    /// fire protection applies, fire resistance and fire-immune mobs ignore it
    public var isFire: Bool { self == .fire || self == .lava }

    /// damage that armor doesn't reduce
    public var bypassesArmor: Bool {
        switch self {
        case .fall, .void, .magic, .wither, .starve, .drown, .freeze, .sonic: return true
        default: return false
        }
    }

    /// a raised shield facing the attacker stops it
    public var shieldable: Bool {
        switch self {
        case .mob, .player, .projectile, .explosion, .fireball, .witherSkull: return true
        default: return false
        }
    }
}

/// a player's death-screen line, from the `deathCause` its save recorded
/// (a DamageSource raw value, or "fall_high" for a fall of more than 5
/// blocks) and the name of whoever last hurt it — vanilla 1.20's wording
public func deathCauseText(_ cause: String?, _ attacker: String? = nil) -> String {
    let high = cause == "fall_high"
    guard let source = high ? .fall : cause.flatMap(DamageSource.init(rawValue:)) else { return "died" }
    if let a = attacker {
        switch source {
        case .mob, .player: return "was slain by \(a)"
        case .projectile: return "was shot by \(a)"
        case .fireball: return "was fireballed by \(a)"
        case .witherSkull: return "was shot by a skull from \(a)"
        case .explosion: return "was blown up by \(a)"
        case .thorns: return "was killed while trying to hurt \(a)"
        case .sonic: return "was sonically charged by \(a)"
        case .sting: return "was stung to death by \(a)"
        case .firework: return "went off with a bang whilst fighting \(a)"
        case .magic: return "was killed by \(a) using magic"
        case .wither: return "withered away whilst fighting \(a)"
        case .poison: return "died"
        case .fall: return high ? "fell from a high place whilst trying to escape \(a)"
                                : "hit the ground too hard whilst trying to escape \(a)"
        case .flyIntoWall: return "experienced kinetic energy whilst trying to escape \(a)"
        case .anvil: return "was squashed by a falling anvil whilst fighting \(a)"
        case .lightning: return "was struck by lightning whilst fighting \(a)"
        case .fire: return "was burned to a crisp whilst fighting \(a)"
        case .lava: return "tried to swim in lava to escape \(a)"
        case .drown: return "drowned whilst trying to escape \(a)"
        case .freeze: return "was frozen to death by \(a)"
        case .starve: return "starved to death whilst fighting \(a)"
        case .void: return "didn't want to live in the same world as \(a)"
        }
    }
    switch source {
    case .mob, .player: return "was slain"
    case .projectile: return "was shot"
    case .fireball: return "was fireballed"
    case .witherSkull: return "was shot by a skull"
    case .explosion: return "blew up"
    case .thorns: return "was killed trying to hurt something"
    case .sonic: return "was sonically charged"
    case .sting: return "was stung to death"
    case .firework: return "went off with a bang"
    case .magic: return "was killed by magic"
    case .wither: return "withered away"
    case .poison: return "died"
    case .fall: return high ? "fell from a high place" : "hit the ground too hard"
    case .flyIntoWall: return "experienced kinetic energy"
    case .anvil: return "was squashed by a falling anvil"
    case .lightning: return "was struck by lightning"
    case .fire: return "burned to death"
    case .lava: return "tried to swim in lava"
    case .drown: return "drowned"
    case .freeze: return "froze to death"
    case .starve: return "starved to death"
    case .void: return "fell out of the world"
    }
}
