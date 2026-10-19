// Fast building tools: the wall builder (a 16×16 wall square to your facing),
// the box builder (a 16×16×16 open-topped box) and the floor builder (a floor
// poured out to the walls around it). Walls and boxes snap to a 16-block grid
// so they line up edge to edge. All build from the block in your off hand (or
// the hotbar slot right of the tool, or stone bricks) and are undoable
// (EditHistory.swift). Sneak for the smaller versions.

import Foundation

public let BUILDER_SIZE = 16
public let BUILDER_SMALL_SIZE = 8
/// how far out the floor builder may spread each way (sneak: half)
public let FLOOR_REACH = 16

/// the cell a builder builds with, and its display name
func builderMaterial(_ p: Player) -> (Int, String) {
    var candidates: [ItemStack?] = [p.offHand]
    if p.selectedSlot < 8 { candidates.append(p.inventory[p.selectedSlot + 1]) }
    for st in candidates {
        guard let st, let b = itemDef(st.id).block, b != 0 else { continue }
        return (Int(cell(b, 0)), blockName(Int(b)))
    }
    return (Int(cell(B.stone_bricks)), "stone_bricks")
}

public let FILL_MAX_BLOCKS = 32768

public enum FillError: Error, CustomStringConvertible {
    case tooBig, outsideWorld(Int, Int), unloaded
    public var description: String {
        switch self {
        case .tooBig: return "Too many blocks (more than \(FILL_MAX_BLOCKS))"
        case .outsideWorld(let lo, let hi): return "Can't fill outside the world (y \(lo) to \(hi))"
        case .unloaded: return "That area isn't loaded"
        }
    }
}

/// /fill: one cell through a box (corners in any order) as one undoable
/// edit, refusing a box partly outside the world or in land that isn't
/// loaded; returns how many blocks changed
public func fillBox(_ w: World, _ x0: Int, _ y0: Int, _ z0: Int, _ x1: Int, _ y1: Int, _ z1: Int, _ c: Int) throws -> Int {
    // coordinates are within the border, so each side fits; the product may not
    let (vxz, o1) = (abs(x1 - x0) + 1).multipliedReportingOverflow(by: abs(z1 - z0) + 1)
    let (vol, o2) = vxz.multipliedReportingOverflow(by: abs(y1 - y0) + 1)
    if o1 || o2 || vol > FILL_MAX_BLOCKS { throw FillError.tooBig }
    let top = w.info.minY + w.info.height - 1
    if min(y0, y1) < w.info.minY || max(y0, y1) > top { throw FillError.outsideWorld(w.info.minY, top) }
    for cz in floorDiv(min(z0, z1), 16)...floorDiv(max(z0, z1), 16) {
        for cx in floorDiv(min(x0, x1), 16)...floorDiv(max(x0, x1), 16) where w.getChunk(cx, cz) == nil {
            throw FillError.unloaded
        }
    }
    var n = 0
    let batch = beginEdit(w, "fill")
    batch.bulkLight = vol > BULK_LIGHT_CELLS
    for y in min(y0, y1)...max(y0, y1) {
        for z in min(z0, z1)...max(z0, z1) {
            for x in min(x0, x1)...max(x0, x1) where batch.set(x, y, z, c, SET_DEFAULT) { n += 1 }
        }
    }
    batch.finishLight()
    batch.liftEntities()
    return n
}

/// put a block unless it's unbreakable (bedrock, portals)
@inline(__always) private func place(_ b: EditBatch, _ x: Int, _ y: Int, _ z: Int, _ c: Int) {
    if blockDefs[b.world.getBlockId(x, y, z)].hardness < 0 { return }
    b.set(x, y, z, c)
}

/// columns standing over a gap get a foundation down to the ground, but only
/// when the ground is within reach (a deliberate sky build stays floating)
private func foundation(_ b: EditBatch, _ x: Int, _ y: Int, _ z: Int, _ c: Int) {
    let w = b.world
    func open(_ y: Int) -> Bool {
        let id = w.getBlockId(x, y, z)
        return isTreeOrPlant(id) || id == Int(B.water) || id == Int(B.lava)
    }
    var fy = y - 1
    while fy > max(w.info.minY, y - 24), open(fy) { fy -= 1 }
    if open(fy) { return }
    for yy in stride(from: y - 1, to: fy, by: -1) { place(b, x, yy, z, c) }
}

private func grid(_ v: Int, _ size: Int) -> Int { floorDiv(v, size) * size }

/// recent walls/boxes, so a side click lines up with the build it hit
private var built: [(ObjectIdentifier, Int, Int, Int, Int, Int, Int)] = []
private func remember(_ w: World, _ x0: Int, _ y0: Int, _ z0: Int, _ x1: Int, _ y1: Int, _ z1: Int) {
    built.append((ObjectIdentifier(w), x0, y0, z0, x1, y1, z1))
    if built.count > 4096 { built.removeFirst(1024) }
}
/// leaving a world: its builds are gone, and a new world can reuse its identifier
func forgetBuilds() { built.removeAll() }
/// base height for a build: on top of / under what was clicked, or level with
/// the earlier build whose side was clicked
private func baseY(_ w: World, _ hit: RaycastHit, _ size: Int) -> Int {
    let ty = hit.y + DIR_Y[hit.face]
    if DIR_Y[hit.face] > 0 { return ty }
    if DIR_Y[hit.face] < 0 { return ty - size + 1 }
    let wid = ObjectIdentifier(w)
    if let r = built.last(where: { $0.0 == wid && hit.x >= $0.1 && hit.x <= $0.4 && hit.y >= $0.2 && hit.y <= $0.5
                                   && hit.z >= $0.3 && hit.z <= $0.6 }) {
        return r.2
    }
    return ty
}

private func builderFX(_ w: World, _ x0: Int, _ y0: Int, _ z0: Int, _ x1: Int, _ y1: Int, _ z1: Int, _ c: Int) {
    let mx = Double(x0 + x1) / 2 + 0.5, my = Double(y0 + y1) / 2 + 0.5, mz = Double(z0 + z1) / 2 + 0.5
    w.hooks.addParticles("block", mx, my, mz, 40, Double(max(x1 - x0, z1 - z0)) * 0.4, c)
    w.hooks.addParticles("smoke", mx, Double(y0) + 0.5, mz, 12, Double(max(x1 - x0, z1 - z0)) * 0.4, 0)
    w.hooks.playSound("block.stone.place", mx, my, mz, 2, 0.6)
    w.hooks.playSound("pebble.quarry.arm", mx, my, mz, 1, 1.5)
}

/// wall square to the player's facing, on the face they clicked. Spans a
/// grid-aligned run so the next wall continues seamlessly.
@discardableResult
public func buildWall(_ w: World, _ p: Player, _ hit: RaycastHit) -> Int {
    let size = p.sneaking ? BUILDER_SMALL_SIZE : BUILDER_SIZE
    let (c, _) = builderMaterial(p)
    let tx = hit.x + DIR_X[hit.face], tz = hit.z + DIR_Z[hit.face]
    let fx = -detSin(p.yaw), fz = detCos(p.yaw)
    let alongX = abs(fz) >= abs(fx) // facing north/south → wall runs east-west
    let s0 = grid(alongX ? tx : tz, size)
    let y0 = baseY(w, hit, size)
    let b = beginEdit(w, "wall")
    for i in 0..<size {
        let x = alongX ? s0 + i : tx, z = alongX ? tz : s0 + i
        for h in 0..<size { place(b, x, y0 + h, z, c) }
        foundation(b, x, y0, z, c)
    }
    let x1 = alongX ? s0 + size - 1 : tx, z1 = alongX ? tz : s0 + size - 1
    remember(w, alongX ? s0 : tx, y0, alongX ? tz : s0, x1, y0 + size - 1, z1)
    builderFX(w, alongX ? s0 : tx, y0, alongX ? tz : s0, x1, y0 + size - 1, z1, c)
    b.liftEntities()
    return b.count
}

/// a floor, poured like paint into the open cell on the clicked face (where a
/// placed block would go) and spreading level from there, one open cell to the
/// next, until something solid stops it: it fills a room out to its walls and
/// around whatever stands in it. Open means what a placed block replaces (air,
/// water, grass…); it never replaces anything else. It spreads to the four
/// sides only: a diagonal step past an open side is two of those anyway, and
/// one between two solid blocks would leak through a wall whose blocks only
/// touch at the corners. In the open it stops FLOOR_REACH out each way.
@discardableResult
public func buildFloor(_ w: World, _ p: Player, _ hit: RaycastHit) -> Int {
    let reach = p.sneaking ? FLOOR_REACH / 2 : FLOOR_REACH
    let (c, _) = builderMaterial(p)
    // into tall grass or snow (as placing a block would), else on the face
    let into = blockDefs[hit.cell >> 4].replaceable
    let sx = into ? hit.x : hit.x + DIR_X[hit.face]
    let y = into ? hit.y : hit.y + DIR_Y[hit.face]
    let sz = into ? hit.z : hit.z + DIR_Z[hit.face]
    guard y >= w.info.minY, y < w.info.minY + w.info.height else { return 0 }
    func open(_ x: Int, _ z: Int) -> Bool {
        w.isLoadedAt(x, z) && blockDefs[w.getBlockId(x, y, z)].replaceable
    }
    guard open(sx, sz) else { return 0 }
    let side = 2 * reach + 1
    var seen = [Bool](repeating: false, count: side * side)
    func cellIndex(_ x: Int, _ z: Int) -> Int { (z - sz + reach) * side + (x - sx + reach) }
    var queue = [(sx, sz)]
    seen[cellIndex(sx, sz)] = true
    var x0 = sx, x1 = sx, z0 = sz, z1 = sz
    let b = beginEdit(w, "floor")
    var i = 0
    while i < queue.count {
        let (x, z) = queue[i]
        i += 1
        b.set(x, y, z, c)
        x0 = min(x0, x); x1 = max(x1, x); z0 = min(z0, z); z1 = max(z1, z)
        for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
            let nx = x + dx, nz = z + dz
            guard abs(nx - sx) <= reach, abs(nz - sz) <= reach, !seen[cellIndex(nx, nz)] else { continue }
            seen[cellIndex(nx, nz)] = true
            if open(nx, nz) { queue.append((nx, nz)) }
        }
    }
    builderFX(w, x0, y, z0, x1, y, z1, c)
    b.liftEntities()   // lays itself at the feet of whoever stands in it
    return b.count
}

/// open-topped box with a solid floor, in the grid cell on the clicked face.
/// Clicking the side of an earlier box lines the new one up with its floor.
@discardableResult
public func buildBox(_ w: World, _ p: Player, _ hit: RaycastHit) -> Int {
    let size = p.sneaking ? BUILDER_SMALL_SIZE : BUILDER_SIZE
    let (c, _) = builderMaterial(p)
    let tx = hit.x + DIR_X[hit.face], tz = hit.z + DIR_Z[hit.face]
    let x0 = grid(tx, size), z0 = grid(tz, size)
    let y0 = baseY(w, hit, size)
    let b = beginEdit(w, "box")
    for dz in 0..<size {
        for dx in 0..<size {
            let x = x0 + dx, z = z0 + dz
            let edge = dx == 0 || dz == 0 || dx == size - 1 || dz == size - 1
            place(b, x, y0, z, c)
            for h in 1..<size { place(b, x, y0 + h, z, edge ? c : 0) }
            foundation(b, x, y0, z, c)
        }
    }
    remember(w, x0, y0, z0, x0 + size - 1, y0 + size - 1, z0 + size - 1)
    builderFX(w, x0, y0, z0, x0 + size - 1, y0 + size - 1, z0 + size - 1, c)
    b.liftEntities()   // its floor goes in at the feet of whoever stands in the cell
    return b.count
}
