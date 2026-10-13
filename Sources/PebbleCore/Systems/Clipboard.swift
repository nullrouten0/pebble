// The clipboard behind the selection wand: //copy and //cut take the selected
// box (blocks plus contents such as chest items and sign text), //paste puts
// it back relative to where you stand now, the way it sat relative to you
// when you copied. One clipboard per player, not saved. Cuts and pastes are
// one undo step each (EditHistory.swift). Mobs and dropped items aren't copied.

import Foundation

/// the most blocks one copy or paste may cover (100×100×100)
public let CLIPBOARD_MAX_BLOCKS = 1_000_000

public final class Clipboard {
    /// width (x), height (y), length (z)
    public let w: Int, h: Int, l: Int
    /// cells, x fastest, then z, then y
    let cells: [UInt16]
    /// block entities by cell index, positions relative to the box's min corner
    let blockEntities: [Int: BlockEntityData]
    /// the box's min corner relative to the copier's block when they copied
    public let offset: (x: Int, y: Int, z: Int)

    init(w: Int, h: Int, l: Int, cells: [UInt16], blockEntities: [Int: BlockEntityData], offset: (Int, Int, Int)) {
        self.w = w; self.h = h; self.l = l
        self.cells = cells
        self.blockEntities = blockEntities
        self.offset = offset
    }

    public var volume: Int { w * h * l }
    public var blockEntityCount: Int { blockEntities.count }
}

public enum ClipboardError: Error, CustomStringConvertible {
    case noSelection, otherDimension, empty, tooBig(Int), unloaded

    public var description: String {
        switch self {
        case .noSelection: return "Mark both corners first (selection_wand, or //pos1 and //pos2)"
        case .otherDimension: return "Your selection is in another dimension"
        case .empty: return "Your clipboard is empty - //copy something first"
        case .tooBig(let n): return "Too many blocks (\(n); the limit is \(CLIPBOARD_MAX_BLOCKS))"
        case .unloaded: return "Part of that area isn't loaded - move closer and try again"
        }
    }
}

extension BlockEntityData {
    /// a deep copy at another position: item stacks are shared objects, so a
    /// pasted chest must get its own
    func cloned(_ x: Int, _ y: Int, _ z: Int) -> BlockEntityData {
        let n = BlockEntityData(type: type, x: x, y: y, z: z)
        n.copyContents(from: self)
        n.items = items?.map(copyStack)
        n.disc = copyStack(disc)
        n.item = copyStack(item)
        n.viewers = nil // nobody has the copy open
        return n
    }
}

/// the block a player stands in
private func standingBlock(_ p: Player) -> (Int, Int, Int) {
    (ifloor(p.x), ifloor(p.y), ifloor(p.z))
}

/// every chunk column the box touches is loaded
private func boxLoaded(_ w: World, _ x0: Int, _ z0: Int, _ x1: Int, _ z1: Int) -> Bool {
    for cz in floorDiv(z0, CHUNK_W)...floorDiv(z1, CHUNK_W) {
        for cx in floorDiv(x0, CHUNK_W)...floorDiv(x1, CHUNK_W) where !w.isLoadedAt(cx * CHUNK_W, cz * CHUNK_W) {
            return false
        }
    }
    return true
}

/// copy `p`'s selection to their clipboard; `cut` also clears it to air (one
/// undo step). Returns the new clipboard.
@discardableResult
public func copySelection(_ p: Player, cut: Bool) throws -> Clipboard {
    let world = p.world
    guard let sel = p.selection, let (lo, hi) = sel.box, let (w, h, l) = sel.size else { throw ClipboardError.noSelection }
    guard sel.dim == world.dim else { throw ClipboardError.otherDimension }
    // corners are clamped to build height, so w·h·l fits in an Int
    guard w * h * l <= CLIPBOARD_MAX_BLOCKS else { throw ClipboardError.tooBig(w * h * l) }
    guard boxLoaded(world, lo.x, lo.z, hi.x, hi.z) else { throw ClipboardError.unloaded }
    var cells = [UInt16](repeating: 0, count: w * h * l)
    var bes: [Int: BlockEntityData] = [:]
    var i = 0
    for y in lo.y...hi.y {
        for z in lo.z...hi.z {
            for x in lo.x...hi.x {
                cells[i] = UInt16(world.getBlock(x, y, z))
                if let be = world.getBlockEntity(x, y, z) { bes[i] = be.cloned(x - lo.x, y - lo.y, z - lo.z) }
                i += 1
            }
        }
    }
    let (px, py, pz) = standingBlock(p)
    let clip = Clipboard(w: w, h: h, l: l, cells: cells, blockEntities: bes,
                         offset: (lo.x - px, lo.y - py, lo.z - pz))
    p.clipboard = clip
    if cut {
        let batch = beginEdit(world, "cut")
        for y in lo.y...hi.y {
            for z in lo.z...hi.z {
                for x in lo.x...hi.x { batch.set(x, y, z, 0) }
            }
        }
    }
    return clip
}

public struct PasteResult {
    /// cells whose block or contents changed
    public let changed: Int
    /// cells that fell above or below the world and were left out
    public let outside: Int
    public let lo: BlockPos, hi: BlockPos
}

/// paste `p`'s clipboard where it sat relative to them when they copied; with
/// `skipAir` the clipboard's air leaves what's there alone. One undo step.
@discardableResult
public func pasteClipboard(_ p: Player, skipAir: Bool) throws -> PasteResult {
    guard let clip = p.clipboard else { throw ClipboardError.empty }
    let world = p.world
    let (px, py, pz) = standingBlock(p)
    let x0 = px + clip.offset.x, y0 = py + clip.offset.y, z0 = pz + clip.offset.z
    let x1 = x0 + clip.w - 1, z1 = z0 + clip.l - 1
    guard boxLoaded(world, x0, z0, x1, z1) else { throw ClipboardError.unloaded }
    let minY = world.info.minY, maxY = world.info.minY + world.info.height - 1
    let batch = beginEdit(world, "paste")
    var changed = 0, outside = 0, i = 0
    for dy in 0..<clip.h {
        let y = y0 + dy
        for dz in 0..<clip.l {
            for dx in 0..<clip.w {
                defer { i += 1 }
                let c = Int(clip.cells[i])
                if skipAir && c == 0 { continue }
                if y < minY || y > maxY { outside += 1; continue }
                let x = x0 + dx, z = z0 + dz
                let src = clip.blockEntities[i]
                let hadBE = world.getBlockEntity(x, y, z) != nil
                // a cell whose block stays the same may still swap contents
                if hadBE || src != nil { batch.record(x, y, z) }
                var did = batch.set(x, y, z, c)
                if hadBE, world.getBlockEntity(x, y, z) != nil {
                    world.removeBlockEntity(x, y, z)
                    did = true
                }
                if let src {
                    world.setBlockEntity(src.cloned(x, y, z))
                    did = true
                }
                if did { changed += 1 }
            }
        }
    }
    return PasteResult(changed: changed, outside: outside,
                       lo: BlockPos(x0, y0, z0), hi: BlockPos(x1, y0 + clip.h - 1, z1))
}
