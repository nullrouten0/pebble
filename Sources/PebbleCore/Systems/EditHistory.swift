// Undo/redo for big player-driven block edits: destroyers, /place, /fill and
// the wall/box builders. Each edit is one batch holding the original cell (and
// block entity, e.g. chest contents) of every block it touched, recorded the
// first time it's touched. Only blocks are restored — mobs killed or spawned
// stay as they are. App/player-driven only; never part of the deterministic tick.

import Foundation

public final class EditBatch {
    public let label: String
    let world: World
    var keys: [Int64] = []
    var olds: [UInt16] = []
    var bes: [Int64: BlockEntityData] = [:]
    var seen = Set<Int64>()
    /// carve/quarry jobs still writing into this batch (stopped on undo)
    var jobs: [DestroyJob] = []

    init(_ world: World, _ label: String) {
        self.world = world
        self.label = label
    }

    public var count: Int { keys.count }

    // x: 25 bits (±16M) at 38, y: 12 bits at 26, z: 26 bits — 63 bits, sign bit clear
    @inline(__always) static func pack(_ x: Int, _ y: Int, _ z: Int) -> Int64 {
        (Int64(x + (1 << 24)) << 38) | (Int64(y + 2048) << 26) | Int64(z + (1 << 25))
    }
    @inline(__always) static func unpack(_ k: Int64) -> (Int, Int, Int) {
        (Int(k >> 38) - (1 << 24), Int((k >> 26) & 0xFFF) - 2048, Int(k & 0x3FF_FFFF) - (1 << 25))
    }

    /// set a block, remembering what was there first; returns true if it changed
    @discardableResult
    public func set(_ x: Int, _ y: Int, _ z: Int, _ c: Int, _ flags: Int = SET_NO_NEIGHBORS) -> Bool {
        let be = world.getBlockEntity(x, y, z)
        let old = world.setBlock(x, y, z, c, flags)
        if old == c { return false }
        let k = EditBatch.pack(x, y, z)
        if seen.insert(k).inserted {
            keys.append(k)
            olds.append(UInt16(old))
            if let be { bes[k] = be }
        }
        return true
    }
}

public private(set) var undoStack: [EditBatch] = []
public private(set) var redoStack: [EditBatch] = []
private let UNDO_MAX_BATCHES = 64
private let UNDO_MAX_CELLS = 6_000_000

/// open a new undoable edit; clears the redo stack
public func beginEdit(_ w: World, _ label: String) -> EditBatch {
    let b = EditBatch(w, label)
    undoStack.append(b)
    redoStack.removeAll()
    var total = undoStack.reduce(0) { $0 + $1.count }
    while undoStack.count > UNDO_MAX_BATCHES || (total > UNDO_MAX_CELLS && undoStack.count > 1) {
        total -= undoStack.removeFirst().count
    }
    return b
}

/// write a batch's saved cells back, returning the inverse batch (for redo/undo)
private func revert(_ b: EditBatch) -> EditBatch {
    stopJobs(of: b)
    let w = b.world
    let inv = EditBatch(w, b.label)
    for i in stride(from: b.keys.count - 1, through: 0, by: -1) {
        let k = b.keys[i]
        let (x, y, z) = EditBatch.unpack(k)
        guard w.isLoadedAt(x, z) else { continue }
        inv.set(x, y, z, Int(b.olds[i]))
        if let be = b.bes[k] { w.setBlockEntity(be) }
    }
    return inv
}

/// undo the most recent edit; nil when there's nothing to undo
public func undoLastEdit() -> EditBatch? {
    // skip edits that never changed anything (a rocket that hit only air)
    while let b = undoStack.last, b.count == 0, b.jobs.allSatisfy({ $0.done }) { undoStack.removeLast() }
    guard let b = undoStack.popLast() else { return nil }
    redoStack.append(revert(b))
    return b
}

public func redoLastEdit() -> EditBatch? {
    guard let b = redoStack.popLast() else { return nil }
    undoStack.append(revert(b))
    return b
}
