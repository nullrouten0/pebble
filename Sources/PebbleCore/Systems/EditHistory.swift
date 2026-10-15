// Undo/redo for big player-driven block edits: destroyers, /place, /fill and
// the wall/box builders. Each edit is one batch holding the original cell (and
// block entity, e.g. chest contents) of every block it touched, recorded the
// first time it's touched. Blocks are restored, and anyone the edit lifted out
// of its blocks is put back if they haven't moved; mobs killed or spawned stay
// as they are. App/player-driven only; never part of the deterministic tick.

import Foundation

public final class EditBatch {
    public let label: String
    let world: World
    /// whose edit this is: 0 = the local player, else a LAN guest's entity id
    public let owner: Int
    var keys: [Int64] = []
    var olds: [UInt16] = []
    var bes: [Int64: BlockEntityData] = [:]
    var seen = Set<Int64>()
    /// carve/quarry jobs still writing into this batch (stopped on undo)
    var jobs: [DestroyJob] = []
    /// for big edits: blocks go in without a light update each, and
    /// finishLight() relights every chunk they touched once
    public var bulkLight = false
    var touched: [Int64: Chunk] = [:]
    /// a new edit clears its owner's redo steps, but only once it changes something
    var clearsRedo = false
    /// the box around every cell recorded (inclusive), nil while empty
    var bounds: (x0: Int, y0: Int, z0: Int, x1: Int, y1: Int, z1: Int)? = nil
    /// who liftEntities moved, from where, so undo can put them back
    struct Lift { weak var entity: Entity?; let x: Double, y: Double, z: Double, toY: Double }
    var lifts: [Lift] = []

    init(_ world: World, _ label: String, owner: Int = editOwner) {
        self.world = world
        self.label = label
        self.owner = owner
    }

    public var count: Int { keys.count }

    // x: 26 bits at 37, y: 11 bits at 26, z: 26 bits — 63 bits, sign bit clear.
    // x and z cover ±33.5M, past WORLD_COORD_LIMIT (±30M), which commands and
    // portals keep to; y covers ±1024, and only cells inside the world are recorded
    @inline(__always) static func pack(_ x: Int, _ y: Int, _ z: Int) -> Int64 {
        (Int64(x + (1 << 25)) << 37) | (Int64(y + 1024) << 26) | Int64(z + (1 << 25))
    }
    @inline(__always) static func unpack(_ k: Int64) -> (Int, Int, Int) {
        (Int(k >> 37) - (1 << 25), Int((k >> 26) & 0x7FF) - 1024, Int(k & 0x3FF_FFFF) - (1 << 25))
    }

    /// set a block, remembering what was there first; returns true if it changed.
    /// A cell in a chunk that isn't loaded, or outside the world's height, is
    /// left alone and not recorded (undo would otherwise "restore" it to air)
    @discardableResult
    public func set(_ x: Int, _ y: Int, _ z: Int, _ c: Int, _ flags: Int = SET_NO_NEIGHBORS) -> Bool {
        guard reachable(x, y, z) else { return false }
        let be = world.getBlockEntity(x, y, z)
        let old = world.setBlock(x, y, z, c, bulkLight ? flags & ~2 : flags)
        if old == c { return false }
        remember(x, y, z, old, be)
        if bulkLight { touch(x, z) }
        return true
    }

    func touch(_ x: Int, _ z: Int) {
        let k = chunkKey(floorDiv(x, CHUNK_W), floorDiv(z, CHUNK_W))
        if touched[k] == nil, let c = world.getChunk(floorDiv(x, CHUNK_W), floorDiv(z, CHUNK_W)) { touched[k] = c }
    }

    /// relight what a bulkLight edit touched
    public func finishLight() {
        if touched.isEmpty { return }
        world.relightChunks(Array(touched.values))
        touched.removeAll()
    }

    /// remember a cell as it is now without changing it — for an edit that
    /// replaces only its block entity (a chest pasted over a chest)
    public func record(_ x: Int, _ y: Int, _ z: Int) {
        guard reachable(x, y, z) else { return }
        remember(x, y, z, world.getBlock(x, y, z), world.getBlockEntity(x, y, z))
    }

    @inline(__always) private func reachable(_ x: Int, _ y: Int, _ z: Int) -> Bool {
        world.getChunkAt(x, z)?.inYRange(y) ?? false
    }

    private func remember(_ x: Int, _ y: Int, _ z: Int, _ old: Int, _ be: BlockEntityData?) {
        let k = EditBatch.pack(x, y, z)
        guard seen.insert(k).inserted else { return }
        if clearsRedo {
            clearsRedo = false
            redoStack.removeAll { $0.owner == owner }
        }
        keys.append(k)
        olds.append(UInt16(old))
        if let be { bes[k] = be }
        if let b = bounds {
            bounds = (min(b.x0, x), min(b.y0, y), min(b.z0, z), max(b.x1, x), max(b.y1, y), max(b.z1, z))
        } else {
            bounds = (x, y, z, x, y, z)
        }
    }

    /// everyone this edit left inside blocks (players and LAN guests, mobs,
    /// vehicles with their riders) climbs out on top, and is remembered so an
    /// undo can put them back where they stood
    public func liftEntities() {
        guard let b = bounds else { return }
        for ref in world.entities {
            guard let e = ref as? Entity, !e.dead, e.vehicle == nil,
                  e is LivingEntity || !e.passengers.isEmpty else { continue }
            let hw = e.width / 2
            if e.x + hw < Double(b.x0) || e.x - hw > Double(b.x1 + 1) || e.z + hw < Double(b.z0) || e.z - hw > Double(b.z1 + 1)
                || e.y + e.height < Double(b.y0) || e.y > Double(b.y1 + 1) { continue }
            let (x, y, z) = (e.x, e.y, e.z)
            guard liftOutOfBlocks(e) else { continue }
            // lifted again (a rising mountain): undo still goes back to the start
            if let i = lifts.firstIndex(where: { $0.entity === e }) {
                lifts[i] = Lift(entity: e, x: lifts[i].x, y: lifts[i].y, z: lifts[i].z, toY: e.y)
            } else {
                lifts.append(Lift(entity: e, x: x, y: y, z: z, toY: e.y))
            }
        }
    }
}

public private(set) var undoStack: [EditBatch] = []
public private(set) var redoStack: [EditBatch] = []
/// owner stamped on new edits — the LAN host sets it while running a guest's
/// action, so everyone's Cmd+Z undoes only their own edits
public var editOwner = 0
private let UNDO_MAX_BATCHES = 64
private let UNDO_MAX_CELLS = 6_000_000
/// edits bigger than this relight whole chunks at the end (EditBatch.bulkLight)
public let BULK_LIGHT_CELLS = 4096

/// open a new undoable edit; its first change clears the owner's redo steps
public func beginEdit(_ w: World, _ label: String) -> EditBatch {
    let b = EditBatch(w, label)
    b.clearsRedo = true
    undoStack.append(b)
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
    let inv = EditBatch(w, b.label, owner: b.owner)
    inv.bulkLight = b.keys.count > BULK_LIGHT_CELLS
    for i in stride(from: b.keys.count - 1, through: 0, by: -1) {
        let k = b.keys[i]
        let (x, y, z) = EditBatch.unpack(k)
        guard w.isLoadedAt(x, z) else { continue }
        let old = Int(b.olds[i]), want = b.bes[k]
        if w.getBlock(x, y, z) == old && w.getBlockEntity(x, y, z) === want { continue }
        inv.record(x, y, z)
        w.setBlock(x, y, z, old, inv.bulkLight ? 4 : SET_NO_NEIGHBORS)
        if inv.bulkLight { inv.touch(x, z) }
        // exactly the block entity that was there, or none: setBlock keeps a
        // block entity when the shape doesn't change (chest over chest)
        if let now = w.getBlockEntity(x, y, z), now !== want { w.removeBlockEntity(x, y, z) }
        if let want, w.getBlockEntity(x, y, z) !== want { w.setBlockEntity(want) }
    }
    inv.finishLight()
    // whoever the edit lifted goes back where it stood, unless it has moved
    // on (so undoing a structure doesn't drop them from its roof)
    for l in b.lifts {
        guard let e = l.entity, !e.dead, e.vehicle == nil,
              abs(e.x - l.x) < 0.5, abs(e.z - l.z) < 0.5, abs(e.y - l.toY) < 0.5 else { continue }
        e.setPos(l.x, l.y, l.z)
        e.vy = 0
        e.fallDistance = 0
        for r in e.passengers { r.setPos(r.x, l.y + riderOffset(e), r.z); r.fallDistance = 0 }
    }
    // and anyone the restored blocks now enclose climbs out
    inv.liftEntities()
    return inv
}

/// undo `owner`'s most recent edit; returns what was put back (cells in
/// unloaded chunks are skipped), nil when there's nothing to undo
public func undoLastEdit(owner: Int = 0) -> EditBatch? {
    // skip edits that never changed anything (a rocket that hit only air)
    undoStack.removeAll { $0.owner == owner && $0.count == 0 && $0.jobs.allSatisfy({ $0.done }) }
    guard let i = undoStack.lastIndex(where: { $0.owner == owner }) else { return nil }
    let inv = revert(undoStack.remove(at: i))
    redoStack.append(inv)
    return inv
}

public func redoLastEdit(owner: Int = 0) -> EditBatch? {
    guard let i = redoStack.lastIndex(where: { $0.owner == owner }) else { return nil }
    let inv = revert(redoStack.remove(at: i))
    undoStack.append(inv)
    return inv
}

/// forget every edit (leaving a world: they point at it and would keep it in
/// memory), with the jobs still writing into them, the laser's open burst and
/// the builders' list of recent builds
public func clearEditHistory() {
    for b in undoStack { stopJobs(of: b) }
    undoStack.removeAll()
    redoStack.removeAll()
    stopAllJobs()
    forgetLaserBursts()
    forgetBuilds()
}

/// how many undo / redo steps `owner` has
public func editCounts(owner: Int = 0) -> (undo: Int, redo: Int) {
    (undoStack.filter { $0.owner == owner }.count, redoStack.filter { $0.owner == owner }.count)
}
