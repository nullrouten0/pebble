// Chunk storage: 16×H×16 cells (UInt16 id<<4|meta), light arrays, heightmap,
// quart-resolution biomes. Layout pinned by the frozen baselines. Thread-safe by discipline:
// generation writes before publish; the mesher reads snapshots.

import Foundation

public let CHUNK_W = 16
/// how far out x and z go: commands clamp to it and portals arrive inside it
/// (undo's packing, EditBatch.pack, covers a little past it)
public let WORLD_COORD_LIMIT = 30_000_000.0

/// where a portal trip lands: scaled (×8 out of the Nether, ÷8 into it), but
/// a little inside the world's edge so the portal built there (up to 4 wide)
/// is inside too
public func portalArrival(_ x: Double, _ z: Double, scale: Double) -> (Double, Double) {
    let edge = WORLD_COORD_LIMIT - 16
    return (max(-edge, min(edge, x * scale)), max(-edge, min(edge, z * scale)))
}
public let SECTION_H = 16

public enum Dim: Int, Codable {
    case overworld = 0, nether = 1, end = 2
}

public struct DimInfo {
    public let minY: Int
    public let height: Int
    public let seaLevel: Int
    public let hasSky: Bool
    public let ambientLight: Int
    public let coordScale: Double
    public let bedrockFloor: Bool
    public let bedrockCeil: Bool
    public let fogColor: (Double, Double, Double)
}

public let DIMS: [DimInfo] = [
    DimInfo(minY: -64, height: 384, seaLevel: 63, hasSky: true, ambientLight: 0, coordScale: 1, bedrockFloor: true, bedrockCeil: false, fogColor: (0.62, 0.74, 1.0)),
    DimInfo(minY: 0, height: 128, seaLevel: 32, hasSky: false, ambientLight: 7, coordScale: 8, bedrockFloor: true, bedrockCeil: true, fogColor: (0.2, 0.03, 0.03)),
    DimInfo(minY: 0, height: 256, seaLevel: 0, hasSky: false, ambientLight: 9, coordScale: 1, bedrockFloor: false, bedrockCeil: false, fogColor: (0.04, 0.03, 0.06)),
]

@inline(__always) public func floorDiv(_ a: Int, _ b: Int) -> Int {
    let q = a / b
    return (a % b != 0 && (a ^ b) < 0) ? q - 1 : q
}
@inline(__always) public func posMod(_ a: Int, _ b: Int) -> Int {
    let m = a % b
    return m < 0 ? m + b : m
}
@inline(__always) public func chunkKey(_ cx: Int, _ cz: Int) -> Int64 {
    (Int64(cx) << 32) | (Int64(cz) & 0xFFFF_FFFF)
}

public final class Chunk {
    public let cx: Int
    public let cz: Int
    public let minY: Int
    public let height: Int
    public let sections: Int

    public var blocks: [UInt16]
    public var skyLight: [UInt8]
    public var blockLight: [UInt8]
    /// highest opaque-to-sky block per column (world Y), minY-1 if none
    public var heightmap: [Int16]
    /// quart (4×4×4) biome ids
    public var biomes: [UInt8]
    public var dirty: [Bool]
    public var version = 0
    public var status: ChunkStatus = .empty
    public var modified = false
    /// its record on disk lists entities, so an unload must rewrite it even
    /// when none stand here now (or they'd come back on the next load)
    public var savedEntities = false
    /// saved entities of a type this build doesn't know (a newer build's
    /// mob): written back out untouched so opening the world here can't
    /// delete them
    public var unknownEntities: [[String: Any]] = []
    /// keyed by cell index
    public var blockEntities: [Int: BlockEntityData] = [:]
    public var portalBlocks = Set<Int>()
    public var hushSensors = Set<Int>()

    public enum ChunkStatus { case empty, generated, lit }

    public init(cx: Int, cz: Int, minY: Int, height: Int) {
        self.cx = cx
        self.cz = cz
        self.minY = minY
        self.height = height
        sections = (height + SECTION_H - 1) / SECTION_H
        let n = CHUNK_W * CHUNK_W * height
        blocks = [UInt16](repeating: 0, count: n)
        skyLight = [UInt8](repeating: 0, count: n)
        blockLight = [UInt8](repeating: 0, count: n)
        heightmap = [Int16](repeating: Int16(minY - 1), count: CHUNK_W * CHUNK_W)
        biomes = [UInt8](repeating: 0, count: 4 * 4 * ((height + 3) / 4))
        dirty = [Bool](repeating: false, count: sections)
    }

    @inline(__always)
    public func index(_ x: Int, _ y: Int, _ z: Int) -> Int {
        ((y - minY) * CHUNK_W + z) * CHUNK_W + x
    }
    @inline(__always)
    public func inYRange(_ y: Int) -> Bool { y >= minY && y < minY + height }

    @inline(__always)
    public func get(_ x: Int, _ y: Int, _ z: Int) -> UInt16 {
        if y < minY || y >= minY + height { return 0 }
        return blocks[((y - minY) * CHUNK_W + z) * CHUNK_W + x]
    }
    @inline(__always)
    public func set(_ x: Int, _ y: Int, _ z: Int, _ cell: UInt16) {
        if y < minY || y >= minY + height { return }
        blocks[((y - minY) * CHUNK_W + z) * CHUNK_W + x] = cell
    }
    @inline(__always)
    public func getSky(_ x: Int, _ y: Int, _ z: Int) -> Int {
        if y >= minY + height { return 15 }
        if y < minY { return 0 }
        return Int(skyLight[((y - minY) * CHUNK_W + z) * CHUNK_W + x])
    }
    @inline(__always)
    public func setSky(_ x: Int, _ y: Int, _ z: Int, _ v: Int) {
        if y < minY || y >= minY + height { return }
        skyLight[((y - minY) * CHUNK_W + z) * CHUNK_W + x] = UInt8(v)
    }
    @inline(__always)
    public func getBlockLight(_ x: Int, _ y: Int, _ z: Int) -> Int {
        if y < minY || y >= minY + height { return 0 }
        return Int(blockLight[((y - minY) * CHUNK_W + z) * CHUNK_W + x])
    }
    @inline(__always)
    public func setBlockLight(_ x: Int, _ y: Int, _ z: Int, _ v: Int) {
        if y < minY || y >= minY + height { return }
        blockLight[((y - minY) * CHUNK_W + z) * CHUNK_W + x] = UInt8(v)
    }

    @inline(__always)
    public func heightAt(_ x: Int, _ z: Int) -> Int { Int(heightmap[z * CHUNK_W + x]) }

    public func updateHeight(_ x: Int, _ z: Int) {
        let top = minY + height - 1
        var y = top
        while y >= minY {
            let c = blocks[((y - minY) * CHUNK_W + z) * CHUNK_W + x]
            if c != 0 {
                let id = Int(c >> 4)
                if OPAQUE[id] == 1 || LIGHT_OPACITY[id] > 0 {
                    heightmap[z * CHUNK_W + x] = Int16(y)
                    return
                }
            }
            y -= 1
        }
        heightmap[z * CHUNK_W + x] = Int16(minY - 1)
    }

    public func buildHeightmap() {
        for z in 0..<CHUNK_W {
            for x in 0..<CHUNK_W { updateHeight(x, z) }
        }
    }

    @inline(__always)
    public func biomeAt(_ x: Int, _ y: Int, _ z: Int) -> Int {
        let qy = max(0, min((height >> 2) - 1, (y - minY) >> 2))
        return Int(biomes[(qy * 4 + (z >> 2)) * 4 + (x >> 2)])
    }

    public func markDirtyAt(_ y: Int) {
        let s = max(0, min(sections - 1, (y - minY) >> 4))
        dirty[s] = true
        version += 1
    }

    // MARK: - block entities & special blocks

    public func getBlockEntity(_ x: Int, _ y: Int, _ z: Int) -> BlockEntityData? {
        blockEntities[index(x, y, z)]
    }
    public func setBlockEntity(_ x: Int, _ y: Int, _ z: Int, _ be: BlockEntityData) {
        blockEntities[index(x, y, z)] = be
        modified = true
    }
    public func removeBlockEntity(_ x: Int, _ y: Int, _ z: Int) {
        if blockEntities.removeValue(forKey: index(x, y, z)) != nil { modified = true }
    }

    public func trackSpecial(_ x: Int, _ y: Int, _ z: Int, _ id: UInt16) {
        let idx = index(x, y, z)
        if id == B.nether_portal || id == B.end_portal || id == B.end_gateway { portalBlocks.insert(idx) }
        else { portalBlocks.remove(idx) }
        if id == B.hush_sensor || id == B.calibrated_hush_sensor || id == B.hush_shrieker { hushSensors.insert(idx) }
        else { hushSensors.remove(idx) }
    }
    /// rebuild special-block sets after bulk generation
    public func scanSpecials() {
        portalBlocks.removeAll()
        hushSensors.removeAll()
        // hoisted globals + raw buffer: the naive loop pays a cross-module
        // retain/release per cell and dominated whole frames on the main thread
        let p1 = B.nether_portal, p2 = B.end_portal, p3 = B.end_gateway
        let s1 = B.hush_sensor, s2 = B.calibrated_hush_sensor, s3 = B.hush_shrieker
        var portals: [Int] = []
        var hushs: [Int] = []
        blocks.withUnsafeBufferPointer { bp in
            for i in 0..<bp.count {
                let id = bp[i] >> 4
                if id == p1 || id == p2 || id == p3 { portals.append(i) }
                else if id == s1 || id == s2 || id == s3 { hushs.append(i) }
            }
        }
        for i in portals { portalBlocks.insert(i) }
        for i in hushs { hushSensors.insert(i) }
    }
    public func idxToWorld(_ idx: Int) -> (Int, Int, Int) {
        let x = idx & 15
        let z = (idx >> 4) & 15
        let y = (idx >> 8) + minY
        return (cx * 16 + x, y, cz * 16 + z)
    }
}
