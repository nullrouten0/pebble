// Structure placement (/place) — capture a structure into memory on a
// virtual flat world, then stamp it into the live world at any position/depth,
// clearing trees and terrain in its footprint. App-side command only: never
// runs during worldgen or the tick, so no determinism constraints apply.

import Foundation

/// virtual ground level structures are captured against
public let PREFAB_GROUND = 64

/// ChunkSink over an unbounded sparse volume: stone below `ground`, air above,
/// with every write recorded in insertion order.
public final class CaptureSink: ChunkSink {
    public let cx = 0, cz = 0
    public let minY: Int, maxY: Int
    public let ground: Int
    public private(set) var keys: [Int64] = []
    public private(set) var cells: [Int64: UInt16] = [:]
    public var blockEntities: [BESpec] = []
    public var entities: [EntitySpec] = []
    private let stone = Int(cell(B.stone))

    public init(minY: Int, maxY: Int, ground: Int = PREFAB_GROUND) {
        self.minY = minY; self.maxY = maxY; self.ground = ground
    }

    @inline(__always) static func pack(_ x: Int, _ y: Int, _ z: Int) -> Int64 {
        (Int64(x + (1 << 20)) << 42) | (Int64(y + (1 << 20)) << 21) | Int64(z + (1 << 20))
    }
    @inline(__always) static func unpack(_ k: Int64) -> (Int, Int, Int) {
        (Int(k >> 42) - (1 << 20), Int((k >> 21) & 0x1F_FFFF) - (1 << 20), Int(k & 0x1F_FFFF) - (1 << 20))
    }

    public func set(_ x: Int, _ y: Int, _ z: Int, _ c: UInt16) {
        if y < minY || y >= maxY { return }
        let k = CaptureSink.pack(x, y, z)
        if cells.updateValue(c, forKey: k) == nil { keys.append(k) }
    }
    public func get(_ x: Int, _ y: Int, _ z: Int) -> Int {
        if y < minY || y >= maxY { return 0 }
        if let c = cells[CaptureSink.pack(x, y, z)] { return Int(c) }
        return y < ground ? stone : 0
    }
    public func topY(_ x: Int, _ z: Int) -> Int { ground }
    public func addBlockEntity(_ spec: BESpec) { blockEntities.append(spec) }
    public func addEntity(_ spec: EntitySpec) { entities.append(spec) }
}

/// a captured structure, in capture coordinates
public struct Prefab {
    public let id: String
    public let cells: [(Int, Int, Int, UInt16)]
    public let blockEntities: [BESpec]
    public let entities: [EntitySpec]
    public let x0: Int, y0: Int, z0: Int, x1: Int, y1: Int, z1: Int
    /// true when anything sits at/above the virtual ground (anchored to the surface)
    public let surface: Bool
}

func makePrefab(_ id: String, _ sink: CaptureSink) -> Prefab? {
    if sink.keys.isEmpty { return nil }
    var out: [(Int, Int, Int, UInt16)] = []
    out.reserveCapacity(sink.keys.count)
    var x0 = Int.max, y0 = Int.max, z0 = Int.max, x1 = Int.min, y1 = Int.min, z1 = Int.min
    var surface = false
    for k in sink.keys {
        let (x, y, z) = CaptureSink.unpack(k)
        let c = sink.cells[k]!
        out.append((x, y, z, c))
        x0 = min(x0, x); y0 = min(y0, y); z0 = min(z0, z)
        x1 = max(x1, x); y1 = max(y1, y); z1 = max(z1, z)
        if c != 0 && y >= sink.ground { surface = true }
    }
    return Prefab(id: id, cells: out, blockEntities: sink.blockEntities, entities: sink.entities,
                  x0: x0, y0: y0, z0: z0, x1: x1, y1: y1, z1: z1, surface: surface)
}

/// every name /place accepts: starters first, then worldgen structures
public func placeableStructureIds() -> [String] {
    registerAllStructures()
    return STARTER_STRUCTURES.map { $0.id } + STRUCTURES.map { $0.id }
}

/// capture a starter or worldgen structure. Worldgen plans run unchecked at
/// origin chunk (0,0) with the same per-piece Builder RNG as worldgen;
/// `variant` reseeds the plan for a different layout.
public func capturePrefab(_ id: String, dim: Int, minY: Int, maxY: Int, biome: Int, variant: Int) -> Prefab? {
    registerAllStructures()
    let sink = CaptureSink(minY: minY, maxY: maxY)
    let seed = UInt32(truncatingIfNeeded: 0x51ACE &+ variant &* 0x9E3779B1)
    if let st = STARTER_STRUCTURES.first(where: { $0.id == id }) {
        st.build(Builder(sink, Rng(seed)), 0, PREFAB_GROUND, 0)
        return makePrefab(id, sink)
    }
    guard let def = STRUCTURES.first(where: { $0.id == id }) else { return nil }
    func ctxFor(_ bi: Int) -> GenCtx {
        GenCtx(seed: seed, heightAt: { _, _ in PREFAB_GROUND }, biomeAt: { _, _ in bi }, dim: dim)
    }
    // plans may assume their check passed (villages force-unwrap a biome
    // style), so prefer the local biome but fall back to one the check accepts.
    // Checks that are pure chance/position just keep the local biome.
    let fallbacks: [Biome] = [.plains, .desert, .savanna, .taiga, .snowyPlains, .jungle, .swamp, .ocean, .deepOcean, .netherWastes, .endHighlands]
    var ctx = ctxFor(biome)
    for bi in [biome] + fallbacks.map({ $0.rawValue }) {
        if def.check(ctxFor(bi), 0, 0, Rng(hash2(seed, 0, 0, def.salt ^ 0x5757))) { ctx = ctxFor(bi); break }
    }
    guard let plan = def.plan(ctx, 0, 0, Rng(hash2(seed, 0, 0, def.salt ^ 0x1234))) else { return nil }
    for (pi, p) in plan.pieces.enumerated() {
        p.build(Builder(sink, Rng(hash2(seed, pi, -pi, def.salt ^ 0x9999))))
    }
    return makePrefab(id, sink)
}

/// tree parts and loose plants — cleared out of a footprint, never treated as ground
func isTreeOrPlant(_ id: Int) -> Bool {
    if id == 0 { return true }
    let d = blockDefs[id]
    if !d.solid { return UInt16(id) != B.water && UInt16(id) != B.lava }
    let n = d.name
    return n.hasSuffix("_leaves") || n.hasSuffix("_log") || n.hasSuffix("_wood") || n.hasSuffix("_stem")
        || n.hasSuffix("_hyphae") || n.hasSuffix("mushroom_block") || n == "mangrove_roots" || n == "bee_nest"
}

/// first air cell above real ground at (x,z), looking through trees and plants
/// (water counts as ground so builds sit on the surface)
public func groundLevel(_ w: World, _ x: Int, _ z: Int) -> Int {
    var y = w.info.minY + w.info.height - 1
    while y > w.info.minY {
        if !isTreeOrPlant(w.getBlockId(x, y, z)) { return y + 1 }
        y -= 1
    }
    return w.info.minY + 1
}

/// where a buried structure's entrance shaft should land: the highest floor-level
/// air cell (air with headroom over a solid captured block), nearest the middle
func entranceTarget(_ pf: Prefab) -> (Int, Int, Int)? {
    var map: [Int64: UInt16] = [:]
    map.reserveCapacity(pf.cells.count)
    for (x, y, z, c) in pf.cells { map[CaptureSink.pack(x, y, z)] = c }
    let mx = Double(pf.x0 + pf.x1) / 2, mz = Double(pf.z0 + pf.z1) / 2
    var best: (Int, Int, Int)? = nil, bestScore = Double.infinity
    for (x, y, z, c) in pf.cells where c == 0 {
        guard map[CaptureSink.pack(x, y + 1, z)] == 0,
              let below = map[CaptureSink.pack(x, y - 1, z)], below != 0,
              blockDefs[Int(below >> 4)].solid else { continue }
        // prefer high (shorter shaft), then central
        let score = -Double(y) * 4 + detHyp3(Double(x) - mx, 0, Double(z) - mz)
        if score < bestScore { bestScore = score; best = (x, y, z) }
    }
    return best
}
