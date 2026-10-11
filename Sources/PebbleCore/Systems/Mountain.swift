// Mountain (/place mountain) — pours a natural-looking mountain onto the live
// world: a noise-shaped peak about 160 blocks across and 80 tall, roughly 1.5×
// the Giza pyramid. Every column fills from the mountain's surface down through
// air, water, trees and plants until it meets solid ground, so it settles over
// valleys, lakes and buildings alike (burying them); ground that already
// stands higher is left alone, so it melts into the hills around it.
// It rises layer by layer over a few seconds, lifting anyone standing in it,
// and it's one undoable edit like any other /place.

import Foundation

public let MOUNTAIN_RADIUS = 80.0
public let MOUNTAIN_HEIGHT = 80.0

/// the mountain's height above its base, around (cx, cz)
struct MountainShape {
    let cx: Double, cz: Double
    let warp: FBM, outline: FBM, ridges: FBM, detail: FBM

    init(cx: Double, cz: Double, variant: Int) {
        self.cx = cx
        self.cz = cz
        let s = UInt32(truncatingIfNeeded: 0x30A7 &+ variant &* 0x9E3779B1)
        warp = FBM(s, 2, 1 / 70)
        outline = FBM(s &+ 11, 2, 1)
        ridges = FBM(s &+ 23, 4, 1 / 38, persistence: 0.45)
        detail = FBM(s &+ 37, 3, 1 / 9)
    }

    /// widest reach of the footprint (the outline wobbles past the radius)
    static let reach = Int(MOUNTAIN_RADIUS * 1.3) + 20

    func height(_ x: Int, _ z: Int) -> Double {
        let fx = Double(x) + 0.5, fz = Double(z) + 0.5
        // warp the footprint so it isn't a cone, and lobe its outline
        let dx = fx - cx + warp.sample2(fx, fz) * 20
        let dz = fz - cz + warp.sample2(fz + 517, fx - 517) * 20
        let a = atan2(dz, dx)
        let r = MOUNTAIN_RADIUS * (1 + 0.24 * outline.sample2(cos(a) * 1.7 + 9, sin(a) * 1.7 + 9))
        let u = (dx * dx + dz * dz).squareRoot() / r
        if u >= 1 { return 0 }
        // steep summit, long gentle skirt
        let body = pow(1 - u, 1.65)
        // sharp ridgelines and gullies running down the flanks
        let ridge = 1 - abs(ridges.sample2(fx, fz))
        let h = MOUNTAIN_HEIGHT * body * (0.62 + 0.5 * ridge * ridge) + detail.sample2(fx, fz) * 3 * (1 - u)
        return max(0, h)
    }
}

/// a planned mountain: every cell to write, bottom layer first
public struct MountainPlan {
    public var keys: [Int64] = []
    public var cells: [UInt16] = []
    public var peakY = Int.min
    public var x0 = Int.max, z0 = Int.max, x1 = Int.min, z1 = Int.min
    /// columns that fell in unloaded chunks
    public var skipped = 0
}

/// shape the mountain over the world as it is now. `baseY` is the ground the
/// heights stand on (usually the ground at the center)
public func planMountain(_ w: World, cx: Int, cz: Int, baseY: Int, variant: Int) -> MountainPlan {
    let shape = MountainShape(cx: Double(cx) + 0.5, cz: Double(cz) + 0.5, variant: variant)
    let R = MountainShape.reach
    let n = 2 * R + 3
    // heightfield with a 1-block border for slopes
    var hf = [Double](repeating: 0, count: n * n)
    for j in 0..<n {
        for i in 0..<n { hf[j * n + i] = shape.height(cx - R - 1 + i, cz - R - 1 + j) }
    }
    // every variant peaks MOUNTAIN_HEIGHT above its base, whatever the noise did
    let scale = MOUNTAIN_HEIGHT / max(1, hf.max() ?? 1)
    for k in hf.indices { hf[k] *= scale }
    let patches = FBM(UInt32(truncatingIfNeeded: 0x9A7C &+ variant), 2, 1 / 18)
    let veins = FBM(UInt32(truncatingIfNeeded: 0x7E1D &+ variant), 2, 1 / 14)
    let ceilY = w.info.minY + w.info.height - 2
    let water = Int(B.water), lava = Int(B.lava)
    func open(_ id: Int) -> Bool { isTreeOrPlant(id) || id == water || id == lava }
    let C = { (b: UInt16) in UInt16(cell(b)) }
    let stone = C(B.stone), andesite = C(B.andesite), granite = C(B.granite), tuff = C(B.tuff)
    let grass = C(B.grass_block), dirt = C(B.dirt), gravel = C(B.gravel), snow = C(B.snow_block)
    let tuft = C(B.short_grass)

    var plan = MountainPlan()
    // collected per layer, then emitted bottom-up
    var layers: [Int: [(Int64, UInt16)]] = [:]
    for j in 1..<(n - 1) {
        for i in 1..<(n - 1) {
            let h = hf[j * n + i]
            if h < 1 { continue }
            let x = cx - R - 1 + i, z = cz - R - 1 + j
            guard w.isLoadedAt(x, z) else { plan.skipped += 1; continue }
            let top = min(ceilY, baseY + Int(h.rounded()))
            // pour down until something solid holds it up
            var y = top
            while y > w.info.minY, open(w.getBlockId(x, y, z)) { y -= 1 }
            if y >= top { continue }   // the ground here already stands taller
            let floor = y + 1
            let slope = max(abs(hf[j * n + i + 1] - hf[j * n + i - 1]), abs(hf[(j + 1) * n + i] - hf[(j - 1) * n + i])) / 2
            let rel = Double(top - baseY) / MOUNTAIN_HEIGHT
            let p = patches.sample2(Double(x), Double(z))
            // the surface: snowcap, bare cliffs, scree, or grassy lower slopes
            var skin: [UInt16]
            var decorate = false
            if rel > 0.66 + 0.08 * p && slope < 2.4 {
                skin = [snow, snow]
            } else if slope >= 1.6 {
                skin = [p > 0.2 ? andesite : stone]
            } else if rel < 0.4 + 0.1 * p && slope < 1.4 {
                skin = [grass, dirt, dirt, dirt]
                decorate = hash3(0x7AF7, x, 0, z) % 4 == 0
            } else if p > 0.32 {
                skin = [gravel, gravel]
            } else {
                skin = [p < -0.35 ? andesite : stone]
            }
            for yy in floor...top {
                let depth = top - yy
                var c: UInt16
                if depth < skin.count {
                    c = skin[depth]
                } else {
                    // rock body with veins of andesite, granite and tuff
                    let v = veins.sample3(Double(x), Double(yy) * 1.6, Double(z))
                    c = v > 0.5 ? andesite : v < -0.55 ? granite : (yy < baseY - 6 && v > 0.3) ? tuff : stone
                }
                layers[yy, default: []].append((EditBatch.pack(x, yy, z), c))
            }
            if decorate && top + 1 <= ceilY && w.getBlockId(x, top + 1, z) == 0 {
                layers[top + 1, default: []].append((EditBatch.pack(x, top + 1, z), tuft))
            }
            plan.peakY = max(plan.peakY, top)
            plan.x0 = min(plan.x0, x); plan.x1 = max(plan.x1, x)
            plan.z0 = min(plan.z0, z); plan.z1 = max(plan.z1, z)
        }
    }
    for y in layers.keys.sorted() {
        for (k, c) in layers[y]! {
            plan.keys.append(k)
            plan.cells.append(c)
        }
    }
    return plan
}

/// raises a planned mountain a few layers per tick, lifting anyone it reaches
public final class MountainJob: DestroyJob {
    let batch: EditBatch
    let plan: MountainPlan
    /// whoever might be standing in it (the host's player and LAN guests)
    let players: () -> [Player]
    var idx = 0
    public var cancelled = false

    init(_ batch: EditBatch, _ plan: MountainPlan, players: @escaping () -> [Player]) {
        self.batch = batch
        self.plan = plan
        self.players = players
    }

    public func step(_ budget: Int) -> Int {
        let w = batch.world
        let start = idx
        let end = min(plan.keys.count, idx + budget)
        while idx < end {
            let (x, y, z) = EditBatch.unpack(plan.keys[idx])
            batch.set(x, y, z, Int(plan.cells[idx]), SET_NO_NEIGHBORS)
            idx += 1
        }
        if end > start {
            // dust where the rock is rising
            let (x, y, z) = EditBatch.unpack(plan.keys[end - 1])
            if w.time % 3 == 0 {
                w.hooks.addParticles("block", Double(x) + 0.5, Double(y) + 1, Double(z) + 0.5, 12, 3, Int(cell(B.stone)))
            }
            liftPlayers(w)
        }
        return end - start
    }
    public var done: Bool { cancelled || idx >= plan.keys.count }

    /// anyone the rock has risen into climbs out on top of it
    private func liftPlayers(_ w: World) {
        for e in players() {
            let bx = ifloor(e.x), bz = ifloor(e.z)
            if bx < plan.x0 || bx > plan.x1 || bz < plan.z0 || bz > plan.z1 { continue }
            var y = ifloor(e.y)
            let start = y
            while y < plan.peakY + 2, blockDefs[w.getBlockId(bx, y, bz)].solid || blockDefs[w.getBlockId(bx, y + 1, bz)].solid {
                y += 1
            }
            if y != start {
                e.setPos(e.x, Double(y), e.z)
                e.vy = 0
                e.fallDistance = 0
            }
        }
    }
}

/// queue a planned mountain as one undoable edit
public func startMountain(_ w: World, _ plan: MountainPlan, players: @escaping () -> [Player]) -> MountainJob {
    let b = beginEdit(w, "place mountain")
    let job = MountainJob(b, plan, players: players)
    addJob(job, b)
    return job
}
