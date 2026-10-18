// Late-bound mob spawning — baseline keeps spawnMobFn in the frozen baseline and binds
// it from the frozen baseline; Swift centralizes the hook here. SpawnOpts mirrors the
// `data` option-bag accepted by registry.spawnMob.

import Foundation

public struct SpawnOpts {
    public var baby = false
    public var size: Int? = nil
    public var persistent = false
    public var captain = false
    public var variant: Int? = nil
    /// placed by a player (spawn egg, /summon, /spawn, the Tools menu): a
    /// mount arrives tamed and saddled, ready to ride
    public var ready = false

    public init(baby: Bool = false, size: Int? = nil, persistent: Bool = false,
                captain: Bool = false, variant: Int? = nil, ready: Bool = false) {
        self.baby = baby
        self.size = size
        self.persistent = persistent
        self.captain = captain
        self.variant = variant
        self.ready = ready
    }
}

public var spawnMobFn: ((World, String, Double, Double, Double, SpawnOpts?) -> Entity?)?
public func bindSpawnMob(_ fn: ((World, String, Double, Double, Double, SpawnOpts?) -> Entity?)?) {
    spawnMobFn = fn
}
