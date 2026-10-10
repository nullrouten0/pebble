// LAN wire format — length-prefixed binary frames over TCP. Each frame is
// u32 length (type byte + payload, little-endian) · u8 message type · payload.
// The host owns the world; a guest owns its own player (movement, inventory,
// health) and sends its actions to the host, which runs them for real.

import Foundation

public let NET_PROTOCOL = 1
public let NET_DEFAULT_PORT: UInt16 = 25575
public let NET_SERVICE_TYPE = "_pebble._tcp"
/// frames larger than this are a corrupt stream, not a message
let NET_MAX_FRAME = 64 << 20

enum NetMsg: UInt8 {
    // guest → host
    case hello = 1
    case playerState
    case inventory
    case actBreak
    case actUse
    case actRelease
    case actAttack
    case chat
    case command
    case blockEntity
    case playerSave
    case spawnItem
    case spawnXP
    case actBrush
    case bye

    // host → guest
    case welcome = 64
    case kick
    case chunk
    case unloadChunk
    case blocks
    case entSpawn
    case entMove
    case entDespawn
    case entData
    case worldTime
    case worldInfo
    case sounds
    case particles
    case chatLine
    case hurt
    case give
    case xp
    case effect
    case impulse
    case teleport
    case setFire
    case dimChange
    case playerList
    case wake
}

enum NetError: Error { case truncated, badFrame }

// ---------------------------------------------------------------------------
// Writer / reader
// ---------------------------------------------------------------------------
struct ByteWriter {
    var data = Data()

    init(capacity: Int = 256) { data.reserveCapacity(capacity) }

    private mutating func raw<T>(_ v: T) {
        withUnsafeBytes(of: v) { data.append(contentsOf: $0) }
    }
    mutating func u8(_ v: Int) { data.append(UInt8(truncatingIfNeeded: v)) }
    mutating func bool(_ v: Bool) { data.append(v ? 1 : 0) }
    mutating func u16(_ v: Int) { raw(UInt16(truncatingIfNeeded: v).littleEndian) }
    mutating func i16(_ v: Int) { raw(Int16(truncatingIfNeeded: v).littleEndian) }
    mutating func i32(_ v: Int) { raw(Int32(truncatingIfNeeded: v).littleEndian) }
    mutating func u32(_ v: Int) { raw(UInt32(truncatingIfNeeded: v).littleEndian) }
    mutating func i64(_ v: Int) { raw(Int64(v).littleEndian) }
    mutating func f32(_ v: Double) { raw(Float(v).bitPattern.littleEndian) }
    mutating func f64(_ v: Double) { raw(v.bitPattern.littleEndian) }
    mutating func str(_ s: String) {
        let b = Array(s.utf8.prefix(65535))
        u16(b.count)
        data.append(contentsOf: b)
    }
    mutating func blob(_ d: Data) {
        u32(d.count)
        data.append(d)
    }
    /// any JSONSerialization-compatible value
    mutating func json(_ v: Any) {
        blob((try? JSONSerialization.data(withJSONObject: v, options: [.fragmentsAllowed])) ?? Data("null".utf8))
    }
    mutating func encodable<T: Encodable>(_ v: T) {
        blob((try? fingerprintEncoder.encode(v)) ?? Data("null".utf8))
    }

    /// wrap as one frame
    func frame(_ type: NetMsg) -> Data {
        var out = Data(capacity: data.count + 5)
        var len = UInt32(data.count + 1).littleEndian
        withUnsafeBytes(of: &len) { out.append(contentsOf: $0) }
        out.append(type.rawValue)
        out.append(data)
        return out
    }
}

struct ByteReader {
    let b: [UInt8]
    var p = 0

    init(_ bytes: [UInt8]) { b = bytes }

    var remaining: Int { b.count - p }

    private mutating func take(_ n: Int) throws -> ArraySlice<UInt8> {
        guard n >= 0, p + n <= b.count else { throw NetError.truncated }
        defer { p += n }
        return b[p..<(p + n)]
    }
    private mutating func le<T: FixedWidthInteger>(_: T.Type) throws -> T {
        let s = try take(MemoryLayout<T>.size)
        var v: T = 0
        for (i, byte) in s.enumerated() { v |= T(truncatingIfNeeded: byte) << (8 * i) }
        return v
    }
    mutating func u8() throws -> Int { Int(try le(UInt8.self)) }
    mutating func bool() throws -> Bool { try u8() != 0 }
    mutating func u16() throws -> Int { Int(try le(UInt16.self)) }
    mutating func i16() throws -> Int { Int(try le(Int16.self)) }
    mutating func i32() throws -> Int { Int(try le(Int32.self)) }
    mutating func u32() throws -> Int { Int(try le(UInt32.self)) }
    mutating func i64() throws -> Int { Int(try le(Int64.self)) }
    mutating func f32() throws -> Double { Double(Float(bitPattern: try le(UInt32.self))) }
    mutating func f64() throws -> Double { Double(bitPattern: try le(UInt64.self)) }
    mutating func str() throws -> String {
        let n = try u16()
        return String(decoding: try take(n), as: UTF8.self)
    }
    mutating func blob() throws -> Data { Data(try take(try u32())) }
    mutating func json() throws -> Any? {
        try JSONSerialization.jsonObject(with: try blob(), options: [.fragmentsAllowed])
    }
    mutating func decodable<T: Decodable>(_ t: T.Type) throws -> T? {
        try? JSONDecoder().decode(t, from: try blob())
    }
}

// ---------------------------------------------------------------------------
// Shared payload helpers
// ---------------------------------------------------------------------------
/// lzfse via Foundation (no dependencies)
func netCompress(_ d: Data) -> Data {
    ((try? (d as NSData).compressed(using: .lzfse)) as Data?) ?? d
}
func netDecompress(_ d: Data) -> Data? {
    (try? (d as NSData).decompressed(using: .lzfse)) as Data?
}

extension ByteWriter {
    mutating func stack(_ s: ItemStack?) {
        if let s { encodable(s) } else { blob(Data("null".utf8)) }
    }
}
extension ByteReader {
    mutating func stack() throws -> ItemStack? {
        let d = try blob()
        let nItems = itemDefs.count
        guard let s = try? JSONDecoder().decode(ItemStack.self, from: d), s.id > 0, s.id < nItems else { return nil }
        return s
    }
}

/// chunk payload: blocks + biomes + block entities, compressed together
func encodeChunkPayload(_ c: Chunk) -> Data {
    var w = ByteWriter(capacity: c.blocks.count * 2 + c.biomes.count + 64)
    c.blocks.withUnsafeBytes { w.data.append(contentsOf: $0) }  // UInt16, host byte order (LE on every Mac)
    w.data.append(contentsOf: c.biomes)
    let bes = Array(c.blockEntities.values)
    w.blob((try? JSONEncoder().encode(bes)) ?? Data("[]".utf8))
    return netCompress(w.data)
}

func decodeChunkPayload(_ d: Data, height: Int) -> (blocks: [UInt16], biomes: [UInt8], bes: [BlockEntityData])? {
    guard let raw = netDecompress(d) else { return nil }
    let nBlocks = 16 * 16 * height
    let nBiomes = 4 * 4 * ((height + 3) / 4)
    guard raw.count >= nBlocks * 2 + nBiomes + 4 else { return nil }
    var blocks = [UInt16](repeating: 0, count: nBlocks)
    let nItems = UInt16(blockDefs.count)
    raw.withUnsafeBytes { src in
        blocks.withUnsafeMutableBytes { dst in
            dst.copyMemory(from: UnsafeRawBufferPointer(rebasing: src[0..<(nBlocks * 2)]))
        }
    }
    // out-of-range ids from a newer peer → air (same rule as corrupt saves)
    for i in 0..<nBlocks where blocks[i] >> 4 >= nItems { blocks[i] = 0 }
    let biomes = [UInt8](raw[(raw.startIndex + nBlocks * 2)..<(raw.startIndex + nBlocks * 2 + nBiomes)])
    var r = ByteReader([UInt8](raw[(raw.startIndex + nBlocks * 2 + nBiomes)...]))
    let bes = (try? r.decodable([BlockEntityData].self)) ?? nil
    return (blocks, biomes, bes ?? [])
}

/// JSON fingerprint used to notice block-entity changes (sorted keys: the
/// default key order isn't stable, so identical contents would look changed)
func beFingerprint(_ be: BlockEntityData) -> Data {
    (try? fingerprintEncoder.encode(be)) ?? Data()
}
let fingerprintEncoder: JSONEncoder = {
    let e = JSONEncoder()
    e.outputFormatting = .sortedKeys
    return e
}()

/// PEBBLE_NETLOG=1: every 5 s, print what arrived (debugging LAN games)
final class NetLog {
    let on = ProcessInfo.processInfo.environment["PEBBLE_NETLOG"] != nil
    private var counts: [NetMsg: Int] = [:]
    func count(_ t: NetMsg) { if on { counts[t, default: 0] += 1 } }
    func report(_ side: String, _ tick: Int, _ extra: @autoclosure () -> String) {
        guard on, tick % 100 == 0 else { return }
        let parts = counts.sorted { $0.key.rawValue < $1.key.rawValue }.map { "\($0.key)×\($0.value)" }
        print("[netlog] \(side) t\(tick): \(extra()) | got \(parts.joined(separator: " "))")
        fflush(stdout)
        counts.removeAll()
    }
}
let netLog = NetLog()
