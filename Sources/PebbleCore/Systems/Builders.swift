// Fast building tools: the wall builder (a 16×16 wall square to your facing)
// and the box builder (a 16×16×16 open-topped box). Both snap to a 16-block
// grid so walls and boxes line up edge to edge, build from the block in your
// off hand (or the hotbar slot right of the tool, or stone bricks), and are
// undoable (EditHistory.swift). Sneak for the 8-block versions.

import Foundation

public let BUILDER_SIZE = 16
public let BUILDER_SMALL_SIZE = 8

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
    return b.count
}
