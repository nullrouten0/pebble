// The selection wand: left-click a block for corner 1, right-click for corner 2
// (or //pos1, //pos2 at your feet). The box between them is what the
// clipboard commands work on. Corners live on the Player, belong to one
// dimension, and aren't saved.

import Foundation

public struct Selection {
    public var dim: Dim
    public var a: BlockPos?
    public var b: BlockPos?

    public init(dim: Dim, a: BlockPos? = nil, b: BlockPos? = nil) {
        self.dim = dim; self.a = a; self.b = b
    }

    /// the box's min and max corners, once both are set
    public var box: (lo: BlockPos, hi: BlockPos)? {
        guard let a, let b else { return nil }
        return (BlockPos(min(a.x, b.x), min(a.y, b.y), min(a.z, b.z)),
                BlockPos(max(a.x, b.x), max(a.y, b.y), max(a.z, b.z)))
    }
    /// width (x) × height (y) × length (z)
    public var size: (Int, Int, Int)? {
        guard let (lo, hi) = box else { return nil }
        return (hi.x - lo.x + 1, hi.y - lo.y + 1, hi.z - lo.z + 1)
    }
}

/// set corner 1 or 2 of `p`'s selection; a corner in another dimension
/// starts a fresh selection. Returns the line to show the player.
@discardableResult
public func setSelectionCorner(_ p: Player, _ corner: Int, _ pos: BlockPos) -> String {
    let info = p.world.info
    let pos = BlockPos(pos.x, max(info.minY, min(info.minY + info.height - 1, pos.y)), pos.z)
    let dim = p.world.dim
    var s = p.selection?.dim == dim ? p.selection! : Selection(dim: dim)
    if corner == 1 { s.a = pos } else { s.b = pos }
    p.selection = s
    var line = "Corner \(corner): \(pos.x) \(pos.y) \(pos.z)"
    if let (w, h, l) = s.size {
        // corners are within the world border and build height, so this fits
        line += " (\(w)×\(h)×\(l), \(w * h * l) blocks)"
    }
    return line
}
