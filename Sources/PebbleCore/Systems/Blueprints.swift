// Blueprints: a clipboard (Clipboard.swift) saved to disk by name, to load
// into the clipboard again in any world, or share as a file. //save <name>
// writes one, //load <name> reads it back, //blueprints lists them.
//
// A blueprint file (.pebbleblueprint) is "PBP1", the JSON's length (u32 LE),
// then the JSON zlib-compressed. The JSON holds the box size, its cells (u16
// LE, base64; x fastest, then z, then y, as in the clipboard), its block
// entities (chests keep their items, signs their text) and the palette of
// block and item names behind the ids, so a build with other ids reads it
// the way it reads an older world (PaletteRemap).
//
// A LAN guest's clipboard lives on the host, but its blueprints stay on the
// guest's own device, so the file's bytes travel: a guest's //save comes back
// from the host to be written there, and its //load is sent to the host.

import Foundation
import Compression

public let BLUEPRINT_EXTENSION = "pebbleblueprint"
let BLUEPRINT_FORMAT = "pebble-blueprint-1"
/// a blueprint file's JSON may not unpack past this
private let BLUEPRINT_MAX_JSON = 64 << 20

public enum BlueprintError: Error, CustomStringConvertible, Equatable {
    case badName, notFound(String), unreadable, notABlueprint, newerFormat(String), writeFailed

    public var description: String {
        switch self {
        case .badName: return "Name it with letters, digits, - and _ (up to 40)"
        case .notFound(let n): return "No blueprint called \(n) - //blueprints lists them"
        case .unreadable: return "Couldn't read that blueprint"
        case .notABlueprint: return "That isn't a Pebble blueprint"
        case .newerFormat(let v): return "That blueprint is from a newer Pebble (\(v)); update to load it"
        case .writeFailed: return "Couldn't save the blueprint"
        }
    }
}

/// where blueprints live: blueprints/ beside pebble.db
public func blueprintsDir() -> URL {
    vcSupportDir().appendingPathComponent("blueprints", isDirectory: true)
}

/// `s` as a blueprint name (lowercased), or nil if it isn't one: letters,
/// digits, - and _, 1 to 40 of them
public func blueprintName(_ s: String) -> String? {
    let n = s.lowercased()
    guard (1...40).contains(n.count),
          n.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return nil }
    return n
}

/// the saved blueprints, by name
public func listBlueprints(in dir: URL = blueprintsDir()) -> [(name: String, url: URL)] {
    let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
    return files.filter { $0.pathExtension == BLUEPRINT_EXTENSION }
        .map { ($0.deletingPathExtension().lastPathComponent, $0) }
        .sorted { $0.name < $1.name }
}

public func blueprintURL(_ name: String, in dir: URL = blueprintsDir()) -> URL {
    dir.appendingPathComponent("\(name).\(BLUEPRINT_EXTENSION)")
}

/// write `clip` as blueprint `name` (replacing one by that name)
@discardableResult
public func saveBlueprint(_ clip: Clipboard, name: String, in dir: URL = blueprintsDir()) throws -> URL {
    guard let name = blueprintName(name) else { throw BlueprintError.badName }
    return try writeBlueprint(try encodeBlueprint(clip, name: name), name: name, in: dir)
}

/// `clip` as the bytes of a blueprint file. A LAN guest's //save travels as
/// these, from the host (where its clipboard lives) to the guest, who keeps it.
public func encodeBlueprint(_ clip: Clipboard, name: String) throws -> Data {
    var cells = Data(capacity: clip.cells.count * 2)
    for c in clip.cells {
        cells.append(UInt8(c & 0xff))
        cells.append(UInt8(c >> 8))
    }
    var bes: [[String: Any]] = []
    for (i, be) in clip.blockEntities.sorted(by: { $0.key < $1.key }) {
        guard let enc = try? JSONEncoder().encode(be), let obj = try? JSONSerialization.jsonObject(with: enc) else { continue }
        bes.append(["i": i, "be": obj])
    }
    let pal = Palette.current()
    let doc: [String: Any] = [
        "format": BLUEPRINT_FORMAT, "version": PEBBLE_VERSION, "name": name,
        "size": [clip.w, clip.h, clip.l],
        "palette": ["blocks": pal.blocks, "items": pal.items],
        "cells": cells.base64EncodedString(),
        "blockEntities": bes,
    ]
    guard let json = try? JSONSerialization.data(withJSONObject: doc, options: .sortedKeys),
          let packed = zlib(json, compress: true) else { throw BlueprintError.writeFailed }
    var out = Data("PBP1".utf8)
    var len = UInt32(json.count).littleEndian
    withUnsafeBytes(of: &len) { out.append(contentsOf: $0) }
    out.append(packed)
    return out
}

/// save a blueprint file's bytes as blueprint `name` (replacing one by that name)
@discardableResult
public func writeBlueprint(_ data: Data, name: String, in dir: URL = blueprintsDir()) throws -> URL {
    guard let name = blueprintName(name) else { throw BlueprintError.badName }
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = blueprintURL(name, in: dir)
    do { try data.write(to: url, options: .atomic) } catch { throw BlueprintError.writeFailed }
    return url
}

/// read a blueprint file into a clipboard; `dropped` names blocks and items
/// this build doesn't have (they come out as air, or empty slots)
public func loadBlueprint(_ url: URL) throws -> (clip: Clipboard, dropped: [String]) {
    guard let data = try? Data(contentsOf: url) else { throw BlueprintError.unreadable }
    return try decodeBlueprint(data)
}

/// a blueprint file's bytes as a clipboard, as loadBlueprint. A LAN guest's
/// //load sends the host these, so they're checked like any file.
public func decodeBlueprint(_ data: Data) throws -> (clip: Clipboard, dropped: [String]) {
    guard data.count > 8, data.prefix(4) == Data("PBP1".utf8) else { throw BlueprintError.notABlueprint }
    let len = Int(UInt32(data[4]) | UInt32(data[5]) << 8 | UInt32(data[6]) << 16 | UInt32(data[7]) << 24)
    guard len > 0, len <= BLUEPRINT_MAX_JSON, let json = zlib(data.subdata(in: 8..<data.count), compress: false, size: len),
          let doc = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] else { throw BlueprintError.notABlueprint }
    guard let format = doc["format"] as? String else { throw BlueprintError.notABlueprint }
    guard format == BLUEPRINT_FORMAT else { throw BlueprintError.newerFormat(doc["version"] as? String ?? "?") }
    guard let size = doc["size"] as? [Int], size.count == 3, size.allSatisfy({ $0 > 0 }),
          size[0] * size[1] * size[2] <= CLIPBOARD_MAX_BLOCKS,
          let b64 = doc["cells"] as? String, let raw = Data(base64Encoded: b64), raw.count == size[0] * size[1] * size[2] * 2,
          let pd = doc["palette"] as? [String: Any], let pb = pd["blocks"] as? [String], let pi = pd["items"] as? [String]
    else { throw BlueprintError.notABlueprint }
    let remap = PaletteRemap(from: Palette(blocks: pb, items: pi))
    var cells = [UInt16](repeating: 0, count: raw.count / 2)
    raw.withUnsafeBytes { (p: UnsafeRawBufferPointer) in
        for i in 0..<cells.count {
            let c = UInt16(p[i * 2]) | UInt16(p[i * 2 + 1]) << 8
            cells[i] = remap?.cell(c) ?? c
        }
    }
    // a cell naming a block id past this build's registry is air
    for i in cells.indices where Int(cells[i] >> 4) >= blockDefs.count { cells[i] = 0 }
    var bes: [Int: BlockEntityData] = [:]
    for e in doc["blockEntities"] as? [[String: Any]] ?? [] {
        guard let i = e["i"] as? Int, i >= 0, i < cells.count, let obj = e["be"] else { continue }
        let fixed = remap?.json(obj) ?? obj
        guard let enc = try? JSONSerialization.data(withJSONObject: fixed),
              let be = try? JSONDecoder().decode(BlockEntityData.self, from: enc) else { continue }
        be.dropUnknownItems()
        bes[i] = be
    }
    let dropped = (remap?.droppedBlocks ?? []) + (remap?.droppedItems ?? [])
    return (Clipboard(w: size[0], h: size[1], l: size[2], cells: cells, blockEntities: bes), dropped)
}

/// what //save says once blueprint `name` is written
public func blueprintSavedLine(_ name: String, _ clip: Clipboard, replaced: Bool) -> String {
    "§7\(replaced ? "Replaced" : "Saved") blueprint \(name) (\(clip.w)×\(clip.h)×\(clip.l)) - //load \(name) brings it back, in any world"
}

/// what //load says: that it's on the clipboard, then what this build left out
public func blueprintLoadedLines(_ name: String, _ clip: Clipboard, _ dropped: [String]) -> [String] {
    var lines = ["§7Loaded \(name) (\(clip.w)×\(clip.h)×\(clip.l)) - //paste to place it"]
    if !dropped.isEmpty {
        lines.append("§cNot in this version, so left out: \(dropped.prefix(6).joined(separator: ", "))\(dropped.count > 6 ? "…" : "")")
    }
    return lines
}

/// copy a blueprint file shared with you into the blueprints folder, under
/// its own name (or with -2, -3… if that's taken). Returns the name.
public func importBlueprint(_ file: URL, into dir: URL = blueprintsDir()) throws -> String {
    _ = try loadBlueprint(file)   // refuse what isn't one before copying it in
    let base = blueprintName(file.deletingPathExtension().lastPathComponent
        .replacingOccurrences(of: " ", with: "_")) ?? "blueprint"
    let taken = Set(listBlueprints(in: dir).map { $0.name })
    var name = base, n = 2
    while taken.contains(name) { name = "\(base.prefix(37))-\(n)"; n += 1 }
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    do { try FileManager.default.copyItem(at: file, to: blueprintURL(name, in: dir)) } catch { throw BlueprintError.writeFailed }
    return name
}

/// zlib (de)compression through the Compression framework; `size` is the
/// unpacked length when decompressing
private func zlib(_ input: Data, compress: Bool, size: Int = 0) -> Data? {
    let cap = compress ? input.count + 4096 : size
    guard cap > 0, !input.isEmpty else { return nil }
    var out = Data(count: cap)
    let n = out.withUnsafeMutableBytes { dst in
        input.withUnsafeBytes { src in
            compress
                ? compression_encode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, cap,
                                            src.bindMemory(to: UInt8.self).baseAddress!, input.count, nil, COMPRESSION_ZLIB)
                : compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, cap,
                                            src.bindMemory(to: UInt8.self).baseAddress!, input.count, nil, COMPRESSION_ZLIB)
        }
    }
    guard n > 0, compress || n == size else { return nil }
    out.count = n
    return out
}
