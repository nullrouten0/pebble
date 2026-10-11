// Infinity wipe — erases the land for hundreds of blocks around where it's
// fired, following its contour: every column loses whatever stands on the
// natural ground (trees, buildings, overhangs) plus the top WIPE_DEPTH blocks
// of the ground itself. It never cuts below sea level, so oceans, rivers and
// shores stay put, and the cut tapers off over the last WIPE_RIM blocks.
// Overworld only — the natural ground height comes from the terrain noise.
//
// The blast zone is kept in the world record. Loaded chunks are wiped by an
// expanding shockwave (GameCore); every other chunk in the zone is wiped when
// it loads, before it's lit or drawn, so the radius costs nothing up front.
// Far too big for the undo history: it's armed by one use and fired by a second.

import Foundation

public let WIPE_RADIUS = 320.0
/// sneak when firing
public let WIPE_BIG_RADIUS = 1000.0
/// blocks of natural ground stripped under everything that stood on it
public let WIPE_DEPTH = 12
/// the cut eases from full depth to nothing over this many blocks at the edge
let WIPE_RIM = 24.0
/// shockwave speed, blocks per tick
let WIPE_SPEED = 8.0

/// one fired wipe: where, how big, and which chunks it has already reached
public struct WipeZone: Codable {
    public var dim: Int
    public var x: Double
    public var z: Double
    public var radius: Double
    /// chunk keys already wiped (or checked and left alone)
    public var done: Set<Int64> = []

    public init(dim: Int, x: Double, z: Double, radius: Double) {
        self.dim = dim
        self.x = x
        self.z = z
        self.radius = radius
    }

    /// does the zone reach into chunk (cx, cz)?
    public func touches(_ cx: Int, _ cz: Int) -> Bool {
        chunkDistance(cx, cz) <= radius
    }
    /// distance from the center to the nearest point of chunk (cx, cz)
    func chunkDistance(_ cx: Int, _ cz: Int) -> Double {
        let x0 = Double(cx * 16), z0 = Double(cz * 16)
        let dx = max(x0 - x, 0, x - (x0 + 16))
        let dz = max(z0 - z, 0, z - (z0 + 16))
        return (dx * dx + dz * dz).squareRoot()
    }
}

/// strip one chunk's block array (y-major, 16×16 columns, `minY` at index 0)
/// for `zone`; returns true if any block changed. Pure — safe off the main thread.
public func wipeChunkBlocks(_ blocks: inout [UInt16], _ cx: Int, _ cz: Int, minY: Int, height: Int,
                            seed: UInt32, zone: WipeZone) -> Bool {
    if !zone.touches(cx, cz) { return false }
    let gen = overworldGen(seed)
    let sea = DIMS[Dim.overworld.rawValue].seaLevel
    var changed = false
    blocks.withUnsafeMutableBufferPointer { bp in
        for lz in 0..<16 {
            for lx in 0..<16 {
                let wx = cx * 16 + lx, wz = cz * 16 + lz
                let dx = Double(wx) + 0.5 - zone.x, dz = Double(wz) + 0.5 - zone.z
                // ragged edge so the rim doesn't read as a perfect circle
                let n = Double(hash3(0x1F1D, wx, 0, wz) & 0xFFFF) / 65535
                let edge = zone.radius - n * 6
                let d = (dx * dx + dz * dz).squareRoot()
                if d > edge { continue }
                let t = min(1, (edge - d) / WIPE_RIM)
                let depth = Int((Double(WIPE_DEPTH) * t * t * (3 - 2 * t)).rounded())
                let col = lz * 16 + lx
                // natural ground: the terrain noise's height, unless the real
                // column (looking through trees and plants) is lower — then an
                // estimate a few blocks high can't leave a grove standing.
                // Builds sit above the noise height, so they still go.
                var top = minY - 1
                for y in stride(from: height - 1, through: 0, by: -1) where !isTreeOrPlant(Int(bp[y * 256 + col] >> 4)) {
                    top = y + minY
                    break
                }
                let ground = min(gen.refinedHeightEstimate(Double(wx), Double(wz)), top)
                // highest y that stays; never below sea level
                let keep = max(ground - depth, sea)
                let from = max(0, keep + 1 - minY)
                if from >= height { continue }
                for y in from..<height where bp[y * 256 + col] != 0 {
                    bp[y * 256 + col] = 0
                    changed = true
                }
            }
        }
    }
    return changed
}
