// Block and item palettes. Numeric ids come from registration order, which
// changes between builds as things are added, moved or removed; each world
// stores the names behind the ids it was saved with, and opening it under a
// different registry rewrites its saves once (SaveDB.migratePalette).

import Foundation

/// a block or item renamed in code: old name → new name, so worlds saved
/// before the rename keep it
public let BLOCK_ALIASES: [String: String] = [:]
public let ITEM_ALIASES: [String: String] = [:]

public struct Palette: Codable, Equatable {
    public var blocks: [String]
    public var items: [String]

    /// this build's registry
    public static func current() -> Palette {
        Palette(blocks: blockDefs.map(\.name), items: itemDefs.map(\.name))
    }
    /// what a world saved before palettes existed used: this registration
    /// order, under the names Pebble had then
    public static func beforePalettes() -> Palette {
        Palette(blocks: blockDefs.map { packName($0.name) }, items: itemDefs.map { packName($0.name) })
    }
}

/// old ids → this build's, for records written under another palette
public struct PaletteRemap {
    /// old block id → new block id (0, air, when the block is gone)
    let blocks: [UInt16]
    /// old item id → new item id (-1 when the item is gone)
    let items: [Int]
    public private(set) var droppedBlocks: [String] = []
    public private(set) var droppedItems: [String] = []

    /// nil when `old` already matches this build
    public init?(from old: Palette) {
        let now = Palette.current()
        if old == now { return nil }
        var blockIds: [String: Int] = [:]
        for (i, n) in now.blocks.enumerated() { blockIds[n] = i }
        var itemIds: [String: Int] = [:]
        for (i, n) in now.items.enumerated() { itemIds[n] = i }
        var dropped: [String] = []
        blocks = old.blocks.map { name in
            if let id = blockIds[BLOCK_ALIASES[name] ?? name] ?? blockIds[pebbleName(name)] { return UInt16(id) }
            dropped.append(name)
            return 0
        }
        droppedBlocks = dropped
        dropped = []
        items = old.items.map { name in
            if let id = itemIds[ITEM_ALIASES[name] ?? name] ?? itemIds[pebbleName(name)] { return id }
            dropped.append(name)
            return -1
        }
        droppedItems = dropped
    }

    /// a block cell (id << 4 | meta); a gone block becomes air
    public func cell(_ c: UInt16) -> UInt16 {
        let id = Int(c >> 4)
        guard id < blocks.count else { return 0 }
        let n = blocks[id]
        return n == 0 ? 0 : (n << 4) | (c & 15)
    }

    /// remap a saved JSON tree in place: every item stack (an object with
    /// id/count/damage/ench/data — how ItemStack encodes) and the block cells
    /// entities and block entities keep (`blockCell`, `movedCell`). A stack
    /// whose item is gone becomes null, which every loader reads as empty.
    public func json(_ v: Any) -> Any {
        if let a = v as? [Any] { return a.map(json) }
        // ids saved as text (entity and block-entity types, effects,
        // enchantments, death causes) under names Pebble has since changed
        if let s = v as? String { return s.allSatisfy({ $0.isLowercase || $0.isNumber || $0 == "_" }) ? pebbleName(s) : s }
        guard var d = v as? [String: Any] else { return v }
        if d["count"] != nil, d["damage"] != nil, d["ench"] != nil, d["data"] != nil,
           let id = (d["id"] as? NSNumber)?.intValue {
            let n = id >= 0 && id < items.count ? items[id] : -1
            if n < 0 { return NSNull() }
            d["id"] = n
        }
        for (k, x) in d {
            if k == "blockCell" || k == "movedCell", let c = (x as? NSNumber)?.intValue, c >= 0, c <= Int(UInt16.max) {
                d[k] = Int(cell(UInt16(c)))
            } else if x is [Any] || x is [String: Any] || x is String {
                d[k] = json(x)
            }
        }
        return d
    }
}
