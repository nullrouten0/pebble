// Persistence — a single SQLite database at
// ~/Library/Application Support/Pebble/pebble.db (WAL mode, fully mutexed):
//   worlds(id, json, lastPlayed)            — world metadata + global state
//   chunks(world, dim, cx, cz, data BLOB)   — modified chunks (VCK1 binary)
//   player(world, json)                     — player snapshot per world
//   advancements(world, json)               — earned advancement ids per world
// Legacy installs stored loose files under saves/; they are imported once on
// first open and the old folder is kept as saves-legacy-backup. Chunk records
// keep the VCK1 container (binary blocks + JSON tail); entity-only records
// regenerate terrain from seed and re-attach saved entities.

import Compression
import Foundation
import SQLite3

public struct DimState: Codable {
    public var time: Int
    public var dayTime: Int
    public var raining: Bool
    public var thundering: Bool
    public var weatherTimer: Int

    public init(time: Int = 0, dayTime: Int = 1000, raining: Bool = false,
                thundering: Bool = false, weatherTimer: Int = 24000) {
        self.time = time
        self.dayTime = dayTime
        self.raining = raining
        self.thundering = thundering
        self.weatherTimer = weatherTimer
    }
}

/// single source of truth for the app version — the title screen, the F3
/// overlay and save records all read this (Info.plist is bumped separately
/// at packaging time). major.minor.revision: a new minor adds features, a
/// new revision is a small feature or a fix.
public let PEBBLE_VERSION = "1.9.0"

/// the commit this build came from: 8 hex digits, "+" when built with
/// uncommitted changes. Stamped into the app's Info.plist at build time
/// (`bundle` in ./pebble; a build phase in ios/project.yml); nil for bare
/// `swift run` builds.
public let PEBBLE_COMMIT = Bundle.main.object(forInfoDictionaryKey: "PebbleCommit") as? String

/// what players see, e.g. "1.3.0.2d559e0a" — tells apart builds that share a
/// version
public let PEBBLE_BUILD = PEBBLE_COMMIT.map { "\(PEBBLE_VERSION).\($0)" } ?? PEBBLE_VERSION

/// WorldMeta + the global-state extension (baseline WorldRecord extends WorldMeta)
public struct WorldRecord: Codable {
    public var id: String
    public var name: String
    public var seed: Int32
    public var gameMode: Int
    public var difficulty: Int
    public var lastPlayed: Double      // ms epoch, like Date.now()
    public var version: String
    /// keyed by dim rawValue as a string — Swift encodes [Int:] dicts as JSON
    /// arrays, and the record should read as `{"0": {...}, "1": {...}}` on disk
    public var dims: [String: DimState]
    public var spawnX: Int
    public var spawnY: Int
    public var spawnZ: Int
    public var gameRules: [String: Double]
    public var dragonKilled: Bool
    public var gatewaysSpawned: Int
    public var nextEntityId: Int
    /// Infinity Wipe blast zones (Systems/InfinityWipe.swift); nil when none
    public var wipes: [WipeZone]?
    /// world generator version (GEN_VERSION when created); absent in worlds
    /// made before 1.5, which are version 1
    public var genVersion: Int?

    public init(id: String, name: String, seed: Int32, gameMode: Int, difficulty: Int) {
        self.id = id
        self.name = name
        self.seed = seed
        self.gameMode = gameMode
        self.difficulty = difficulty
        lastPlayed = Date().timeIntervalSince1970 * 1000
        version = "pebble-\(PEBBLE_VERSION)"
        dims = ["0": DimState(), "1": DimState(), "2": DimState()]
        spawnX = 0
        spawnY = 80
        spawnZ = 0
        gameRules = [:]
        dragonKilled = false
        gatewaysSpawned = 0
        nextEntityId = 1
        genVersion = GEN_VERSION
    }
}

public struct ChunkRecord {
    public var key: String
    public var worldId: String
    public var dim: Int
    public var cx: Int
    public var cz: Int
    /// absent on entity-only records: the chunk itself regenerates from seed
    public var blocks: [UInt16]?
    public var biomes: [UInt8]?
    public var blockEntities: [BlockEntityData]?
    public var entities: [[String: Any]]

    public init(key: String, worldId: String, dim: Int, cx: Int, cz: Int,
                blocks: [UInt16]? = nil, biomes: [UInt8]? = nil,
                blockEntities: [BlockEntityData]? = nil, entities: [[String: Any]] = []) {
        self.key = key
        self.worldId = worldId
        self.dim = dim
        self.cx = cx
        self.cz = cz
        self.blocks = blocks
        self.biomes = biomes
        self.blockEntities = blockEntities
        self.entities = entities
    }

    /// the same record with block entities of its own (they're objects), for
    /// a chunk going live while this record may still be written out
    func withOwnBlockEntities() -> ChunkRecord {
        var r = self
        r.blockEntities = blockEntities.map(copiedBlockEntities)
        return r
    }
}

/// independent copies of block entities (a reference type), by a JSON round
/// trip: what's saved or loaded mustn't share objects with the live world
func copiedBlockEntities(_ bes: [BlockEntityData]) -> [BlockEntityData] {
    guard let data = try? JSONEncoder().encode(bes),
          let copy = try? JSONDecoder().decode([BlockEntityData].self, from: data) else { return bes }
    return copy
}

/// JSON can't carry NaN/Infinity (structured clone could) — scrub them so one
/// blown-up velocity never poisons a whole chunk record
private func sanitizeJSON(_ v: Any) -> Any {
    if let d = v as? Double { return d.isFinite ? d : 0 }
    if let arr = v as? [Any] { return arr.map(sanitizeJSON) }
    if let dict = v as? [String: Any] { return dict.mapValues(sanitizeJSON) }
    return v
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public final class SaveDB {
    private var db: OpaquePointer?
    /// chunk-write tallies since launch (updated on the save queue; read for
    /// diagnostics only): full records carry block data, stubs only entities
    public private(set) var chunkBytesWritten = 0
    public private(set) var fullChunkWrites = 0
    public private(set) var stubChunkWrites = 0
    /// records skipped because they matched what was last written
    public private(set) var unchangedChunkSkips = 0
    /// a hash of each chunk's record as last written (uncompressed), so saving
    /// the same record again skips compressing and writing it: every save
    /// offers each loaded chunk with mobs or block entities, changed or not
    private var writtenHashes: [String: Int] = [:]
    private let hashLock = NSLock()   // putChunks runs on the save queue, deleteWorld on main
    /// write chunks as zlib-compressed VCK2 (~50× smaller full records).
    /// Every build since 1.3 reads both formats (iOS wrote VCK2 from the
    /// start; the Mac since 1.4.1). Builds before 1.3 can't read VCK2: they'd
    /// regenerate those chunks, so don't open a newer world in one.
    public var compressChunks = true

    public init() {
        let url = vcSupportDir().appendingPathComponent("pebble.db")
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &db, flags, nil) == SQLITE_OK else {
            fatalError("pebble.db could not be opened: \(String(cString: sqlite3_errmsg(db)))")
        }
        exec("PRAGMA journal_mode=WAL")
        exec("PRAGMA synchronous=NORMAL")
        exec("PRAGMA busy_timeout=5000")
        exec("""
        CREATE TABLE IF NOT EXISTS worlds(
            id TEXT PRIMARY KEY, json TEXT NOT NULL, lastPlayed REAL NOT NULL DEFAULT 0)
        """)
        exec("""
        CREATE TABLE IF NOT EXISTS chunks(
            world TEXT NOT NULL, dim INTEGER NOT NULL, cx INTEGER NOT NULL, cz INTEGER NOT NULL,
            data BLOB NOT NULL, PRIMARY KEY(world, dim, cx, cz)) WITHOUT ROWID
        """)
        exec("CREATE TABLE IF NOT EXISTS player(world TEXT PRIMARY KEY, json TEXT NOT NULL)")
        exec("CREATE TABLE IF NOT EXISTS advancements(world TEXT PRIMARY KEY, json TEXT NOT NULL)")
        exec("CREATE TABLE IF NOT EXISTS palette(world TEXT PRIMARY KEY, json TEXT NOT NULL)")
        migrateLegacySaves()
    }

    deinit { sqlite3_close(db) }

    // ---- tiny statement helpers -------------------------------------------------
    @discardableResult
    private func exec(_ sql: String) -> Bool {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            print("[saves] exec failed: \(String(cString: sqlite3_errmsg(db))) — \(sql.prefix(60))")
            return false
        }
        return true
    }

    /// prepare + bind + step a statement; row() is called once per result row.
    /// returns false (and logs) on prepare/step errors — a silently failed
    /// write (disk full, SQLITE_ERROR) is data loss
    @discardableResult
    private func run(_ sql: String, bind: ((OpaquePointer) -> Void)? = nil,
                     row: ((OpaquePointer) -> Void)? = nil) -> Bool {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            print("[saves] prepare failed: \(String(cString: sqlite3_errmsg(db))) — \(sql.prefix(60))")
            return false
        }
        defer { sqlite3_finalize(stmt) }
        bind?(stmt)
        var rc = sqlite3_step(stmt)
        while rc == SQLITE_ROW { row?(stmt); rc = sqlite3_step(stmt) }
        if rc != SQLITE_DONE {
            print("[saves] step failed (\(rc)): \(String(cString: sqlite3_errmsg(db))) — \(sql.prefix(60))")
            return false
        }
        return true
    }

    private func bindText(_ stmt: OpaquePointer, _ idx: Int32, _ s: String) {
        sqlite3_bind_text(stmt, idx, s, -1, SQLITE_TRANSIENT)
    }
    private func columnText(_ stmt: OpaquePointer, _ idx: Int32) -> String? {
        sqlite3_column_text(stmt, idx).map { String(cString: $0) }
    }

    // ---- worlds ---------------------------------------------------------------
    public func listWorlds() -> [WorldRecord] {
        var out: [WorldRecord] = []
        run("SELECT json FROM worlds", row: { stmt in
            if let json = self.columnText(stmt, 0),
               let rec = try? JSONDecoder().decode(WorldRecord.self, from: Data(json.utf8)) {
                out.append(rec)
            }
        })
        return out
    }
    public func getWorld(_ id: String) -> WorldRecord? {
        var rec: WorldRecord?
        run("SELECT json FROM worlds WHERE id=?", bind: { self.bindText($0, 1, id) }) { stmt in
            if let json = self.columnText(stmt, 0) {
                rec = try? JSONDecoder().decode(WorldRecord.self, from: Data(json.utf8))
            }
        }
        return rec
    }
    public func putWorld(_ rec: WorldRecord) {
        guard let data = try? JSONEncoder().encode(rec), let json = String(data: data, encoding: .utf8) else { return }
        run("INSERT OR REPLACE INTO worlds(id, json, lastPlayed) VALUES(?,?,?)", bind: { stmt in
            self.bindText(stmt, 1, rec.id)
            self.bindText(stmt, 2, json)
            sqlite3_bind_double(stmt, 3, rec.lastPlayed)
        })
    }
    public func deleteWorld(_ id: String) {
        exec("BEGIN")
        for table in ["worlds", "chunks", "player", "advancements", "palette"] {
            let col = table == "worlds" ? "id" : "world"
            run("DELETE FROM \(table) WHERE \(col)=?", bind: { self.bindText($0, 1, id) })
        }
        // LAN guests' players are stored as "<world id>#guest:<name>"
        run("DELETE FROM player WHERE world LIKE ?", bind: { self.bindText($0, 1, id + "#guest:%") })
        exec("COMMIT")
        forgetWrites(id)
    }

    // ---- chunks ---------------------------------------------------------------
    public func chunkKey(_ worldId: String, _ dim: Int, _ cx: Int, _ cz: Int) -> String {
        "\(worldId):\(dim):\(cx),\(cz)"
    }

    /// all saved chunk keys for a world — lets the streamer skip the DB for fresh chunks
    public func getChunkKeys(_ worldId: String) -> Set<String> {
        var keys = Set<String>()
        run("SELECT dim, cx, cz FROM chunks WHERE world=?", bind: { self.bindText($0, 1, worldId) }) { stmt in
            let dim = Int(sqlite3_column_int(stmt, 0))
            let cx = Int(sqlite3_column_int(stmt, 1))
            let cz = Int(sqlite3_column_int(stmt, 2))
            keys.insert(self.chunkKey(worldId, dim, cx, cz))
        }
        return keys
    }

    /// every saved chunk's coordinates for a world
    public func chunkCoords(_ worldId: String) -> [(dim: Int, cx: Int, cz: Int)] {
        var out: [(dim: Int, cx: Int, cz: Int)] = []
        run("SELECT dim, cx, cz FROM chunks WHERE world=?", bind: { self.bindText($0, 1, worldId) }) { stmt in
            out.append((Int(sqlite3_column_int(stmt, 0)), Int(sqlite3_column_int(stmt, 1)), Int(sqlite3_column_int(stmt, 2))))
        }
        return out
    }

    /// `remap`: the record was written under another palette (migratePalette)
    public func getChunk(_ worldId: String, _ dim: Int, _ cx: Int, _ cz: Int, remap: PaletteRemap? = nil) -> ChunkRecord? {
        var rec: ChunkRecord?
        run("SELECT data FROM chunks WHERE world=? AND dim=? AND cx=? AND cz=?", bind: { stmt in
            self.bindText(stmt, 1, worldId)
            sqlite3_bind_int(stmt, 2, Int32(dim))
            sqlite3_bind_int(stmt, 3, Int32(cx))
            sqlite3_bind_int(stmt, 4, Int32(cz))
        }) { stmt in
            if let bytes = sqlite3_column_blob(stmt, 0) {
                let count = Int(sqlite3_column_bytes(stmt, 0))
                let data = Data(bytes: bytes, count: count)
                rec = self.decodeChunk(data, key: self.chunkKey(worldId, dim, cx, cz),
                                       worldId: worldId, dim: dim, cx: cx, cz: cz, remap: remap)
            }
        }
        return rec
    }

    /// batch write — one transaction, mirrors the once-per-second save tick.
    /// false = the batch did not land (rolled back); callers must re-mark the
    /// chunks dirty or the edits are silently lost
    @discardableResult
    public func putChunks(_ records: [ChunkRecord]) -> Bool {
        guard !records.isEmpty else { return true }
        guard exec("BEGIN") else { return false }
        var ok = true
        var hashes: [String: Int] = [:]
        for r in records {
            guard let plain = encodeChunk(r) else { ok = false; continue }
            var hasher = Hasher()
            plain.withUnsafeBytes { hasher.combine(bytes: $0) }   // Data's own hash reads only 80 bytes
            let h = hasher.finalize()
            if hashLock.withLock({ writtenHashes[r.key] }) == h { unchangedChunkSkips += 1; continue }
            hashes[r.key] = h
            let data = compressChunks ? compressChunk(plain) : plain
            chunkBytesWritten += data.count
            if r.blocks != nil { fullChunkWrites += 1 } else { stubChunkWrites += 1 }
            let wrote = run("INSERT OR REPLACE INTO chunks(world, dim, cx, cz, data) VALUES(?,?,?,?,?)", bind: { stmt in
                self.bindText(stmt, 1, r.worldId)
                sqlite3_bind_int(stmt, 2, Int32(r.dim))
                sqlite3_bind_int(stmt, 3, Int32(r.cx))
                sqlite3_bind_int(stmt, 4, Int32(r.cz))
                data.withUnsafeBytes { raw in
                    _ = sqlite3_bind_blob(stmt, 5, raw.baseAddress, Int32(raw.count), SQLITE_TRANSIENT)
                }
            })
            ok = ok && wrote
        }
        if ok {
            ok = exec("COMMIT")
        } else {
            exec("ROLLBACK")
        }
        if ok { hashLock.withLock { writtenHashes.merge(hashes) { $1 } } }
        return ok
    }

    /// stop trusting what this process last wrote for a world: another build
    /// (another process) may have rewritten its rows since, e.g. migrating its
    /// palette. Called on opening a world, and on deleting one
    public func forgetWrites(_ worldId: String) {
        hashLock.withLock { writtenHashes = writtenHashes.filter { !$0.key.hasPrefix(worldId + ":") } }
    }

    // binary container: "VCK1" | u8 flags | [u32 nBlocks, u16[] LE, u32 nBiomes, u8[]] | u32 jsonLen, json
    // compressed:       "VCK2" | u32 bodyLen | zlib(the VCK1 container after its magic)
    func encodeChunk(_ r: ChunkRecord, compress: Bool) -> Data? {
        guard let plain = encodeChunk(r) else { return nil }
        return compress ? compressChunk(plain) : plain
    }

    private func compressChunk(_ plain: Data) -> Data {
        let body = plain.dropFirst(4)
        let cap = body.count + 4096
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: cap)
        defer { dst.deallocate() }
        let n = body.withUnsafeBytes { src in
            compression_encode_buffer(dst, cap, src.bindMemory(to: UInt8.self).baseAddress!, body.count, nil, COMPRESSION_ZLIB)
        }
        guard n > 0 else { return plain }   // incompressible / failed: store plain
        var out = Data("VCK2".utf8)
        var le = UInt32(body.count).littleEndian
        withUnsafeBytes(of: &le) { out.append(contentsOf: $0) }
        out.append(dst, count: n)
        return out
    }

    private func encodeChunk(_ r: ChunkRecord) -> Data? {
        var data = Data("VCK1".utf8)
        let hasBlocks = r.blocks != nil && r.biomes != nil
        data.append(hasBlocks ? 1 : 0)
        func putU32(_ v: Int) {
            var le = UInt32(v).littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        if hasBlocks {
            let blocks = r.blocks!, biomes = r.biomes!
            putU32(blocks.count)
            blocks.withUnsafeBufferPointer { bp in
                bp.baseAddress!.withMemoryRebound(to: UInt8.self, capacity: blocks.count * 2) { p in
                    data.append(p, count: blocks.count * 2)  // host LE on all Apple silicon/x86
                }
            }
            putU32(biomes.count)
            data.append(contentsOf: biomes)
        }
        var tail: [String: Any] = ["entities": r.entities.map(sanitizeJSON)]
        if let bes = r.blockEntities,
           let enc = try? JSONEncoder().encode(bes),
           let obj = try? JSONSerialization.jsonObject(with: enc) {
            tail["blockEntities"] = obj
        }
        // sorted keys: the same record always encodes to the same bytes (putChunks)
        guard let json = try? JSONSerialization.data(withJSONObject: tail, options: .sortedKeys) else { return nil }
        putU32(json.count)
        data.append(json)
        return data
    }

    func decodeChunk(_ data: Data, key: String, worldId: String, dim: Int, cx: Int, cz: Int,
                     remap: PaletteRemap? = nil) -> ChunkRecord? {
        if data.count >= 8, data.prefix(4) == Data("VCK2".utf8) {
            let bodyLen = Int(UInt32(littleEndian: data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self) }))
            guard bodyLen > 0, bodyLen < 64 << 20 else { return nil }
            var plain = Data("VCK1".utf8)
            plain.count = 4 + bodyLen
            let got = plain.withUnsafeMutableBytes { dst in
                data.subdata(in: 8..<data.count).withUnsafeBytes { src in
                    compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress! + 4, bodyLen,
                                              src.bindMemory(to: UInt8.self).baseAddress!, src.count, nil, COMPRESSION_ZLIB)
                }
            }
            guard got == bodyLen else { return nil }
            return decodeChunk(plain, key: key, worldId: worldId, dim: dim, cx: cx, cz: cz, remap: remap)
        }
        var rec = ChunkRecord(key: key, worldId: worldId, dim: dim, cx: cx, cz: cz)
        var off = 0
        func readU32() -> Int? {
            guard off + 4 <= data.count else { return nil }
            let v = data.subdata(in: off..<off + 4).withUnsafeBytes { $0.load(as: UInt32.self) }
            off += 4
            return Int(UInt32(littleEndian: v))
        }
        guard data.count >= 5, data.prefix(4) == Data("VCK1".utf8) else { return nil }
        off = 4
        let flags = data[off]; off += 1
        if flags & 1 != 0 {
            guard let nBlocks = readU32(), off + nBlocks * 2 <= data.count else { return nil }
            var blocks = [UInt16](repeating: 0, count: nBlocks)
            data.subdata(in: off..<off + nBlocks * 2).withUnsafeBytes { raw in
                blocks.withUnsafeMutableBytes { dst in
                    dst.copyMemory(from: raw)
                }
            }
            off += nBlocks * 2
            if let remap { for i in 0..<blocks.count { blocks[i] = remap.cell(blocks[i]) } }
            // clamp corrupted ids — blockDefs[cell >> 4] is indexed unchecked
            // in hot paths, and one bad blob must not crash the game
            let maxId = UInt16(blockDefs.count)
            for i in 0..<blocks.count where (blocks[i] >> 4) >= maxId { blocks[i] = 0 }
            rec.blocks = blocks
            guard let nBiomes = readU32(), off + nBiomes <= data.count else { return nil }
            rec.biomes = [UInt8](data.subdata(in: off..<off + nBiomes))
            off += nBiomes
        }
        guard let jsonLen = readU32(), off + jsonLen <= data.count,
              var tail = try? JSONSerialization.jsonObject(with: data.subdata(in: off..<off + jsonLen)) as? [String: Any]
        else { return nil }
        if let remap, let t = remap.json(tail) as? [String: Any] { tail = t }
        rec.entities = tail["entities"] as? [[String: Any]] ?? []
        if let rawBE = tail["blockEntities"],
           let bytes = try? JSONSerialization.data(withJSONObject: rawBE),
           let bes = try? JSONDecoder().decode([BlockEntityData].self, from: bytes) {
            bes.forEach { $0.dropUnknownItems() }
            rec.blockEntities = bes
        }
        return rec
    }

    // ---- palette -------------------------------------------------------------------
    public func getPalette(_ worldId: String) -> Palette? {
        var out: Palette?
        run("SELECT json FROM palette WHERE world=?", bind: { self.bindText($0, 1, worldId) }) { stmt in
            if let json = self.columnText(stmt, 0) { out = try? JSONDecoder().decode(Palette.self, from: Data(json.utf8)) }
        }
        return out
    }
    public func putPalette(_ worldId: String, _ p: Palette) {
        guard let bytes = try? JSONEncoder().encode(p), let json = String(data: bytes, encoding: .utf8) else { return }
        run("INSERT OR REPLACE INTO palette(world, json) VALUES(?,?)", bind: { stmt in
            self.bindText(stmt, 1, worldId)
            self.bindText(stmt, 2, json)
        })
    }

    /// Bring a world saved under another block/item palette in line with this
    /// build, once, before it opens: every chunk record and every player row
    /// (the host's and LAN guests') is rewritten with this build's ids, then
    /// the current palette is recorded. Worlds from before palettes were
    /// saved in this registration order but under the names Pebble used then
    /// (Palette.beforePalettes), so they get the same translation. Returns the
    /// remap it applied, if any.
    @discardableResult
    public func migratePalette(_ worldId: String) -> PaletteRemap? {
        let now = Palette.current()
        let old = getPalette(worldId) ?? Palette.beforePalettes()
        guard let remap = PaletteRemap(from: old) else {
            if getPalette(worldId) == nil { putPalette(worldId, now) }
            return nil
        }
        var batch: [ChunkRecord] = []
        for (dim, cx, cz) in chunkCoords(worldId) {
            if let r = getChunk(worldId, dim, cx, cz, remap: remap) { batch.append(r) }
            if batch.count >= 256 { putChunks(batch); batch.removeAll() }
        }
        putChunks(batch)
        for key in playerKeys(worldId) {
            if let p = getPlayer(key), let d = remap.json(p) as? [String: Any] { putPlayer(key, d) }
        }
        if let adv = getAdvancements(worldId) { putAdvancements(worldId, adv.map(pebbleName)) }
        putPalette(worldId, now)
        return remap
    }

    /// the world's own player row and its LAN guests' ("<world id>#guest:<name>")
    func playerKeys(_ worldId: String) -> [String] {
        var out: [String] = []
        run("SELECT world FROM player WHERE world=? OR world LIKE ?", bind: { stmt in
            self.bindText(stmt, 1, worldId)
            self.bindText(stmt, 2, worldId + "#guest:%")
        }) { stmt in
            if let k = self.columnText(stmt, 0) { out.append(k) }
        }
        return out
    }

    // ---- player / advancements --------------------------------------------------
    public func getPlayer(_ worldId: String) -> [String: Any]? {
        var out: [String: Any]?
        run("SELECT json FROM player WHERE world=?", bind: { self.bindText($0, 1, worldId) }) { stmt in
            if let json = self.columnText(stmt, 0) {
                out = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any]
            }
        }
        return out
    }
    public func putPlayer(_ worldId: String, _ data: [String: Any]) {
        guard let bytes = try? JSONSerialization.data(withJSONObject: sanitizeJSON(data)),
              let json = String(data: bytes, encoding: .utf8) else { return }
        run("INSERT OR REPLACE INTO player(world, json) VALUES(?,?)", bind: { stmt in
            self.bindText(stmt, 1, worldId)
            self.bindText(stmt, 2, json)
        })
    }
    public func getAdvancements(_ worldId: String) -> [String]? {
        var out: [String]?
        run("SELECT json FROM advancements WHERE world=?", bind: { self.bindText($0, 1, worldId) }) { stmt in
            if let json = self.columnText(stmt, 0) {
                out = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String]
            }
        }
        return out
    }
    public func putAdvancements(_ worldId: String, _ ids: [String]) {
        guard let bytes = try? JSONSerialization.data(withJSONObject: ids),
              let json = String(data: bytes, encoding: .utf8) else { return }
        run("INSERT OR REPLACE INTO advancements(world, json) VALUES(?,?)", bind: { stmt in
            self.bindText(stmt, 1, worldId)
            self.bindText(stmt, 2, json)
        })
    }

    // ---- legacy import ----------------------------------------------------------
    /// one-time import of the pre-1.0 loose-file layout (saves/worlds/*.json,
    /// saves/chunks/<id>/*.vck, …); the old folder is renamed, never deleted
    private func migrateLegacySaves() {
        let fm = FileManager.default
        let legacy = vcSupportDir().appendingPathComponent("saves", isDirectory: true)
        let worldsDir = legacy.appendingPathComponent("worlds")
        guard fm.fileExists(atPath: worldsDir.path),
              let files = try? fm.contentsOfDirectory(at: worldsDir, includingPropertiesForKeys: nil),
              !files.isEmpty else { return }

        var worlds = 0, chunks = 0
        for f in files where f.pathExtension == "json" {
            guard let data = try? Data(contentsOf: f),
                  let rec = try? JSONDecoder().decode(WorldRecord.self, from: data) else { continue }
            putWorld(rec)
            worlds += 1
            let id = rec.id
            if let pdata = try? Data(contentsOf: legacy.appendingPathComponent("player/\(id).json")),
               let pobj = (try? JSONSerialization.jsonObject(with: pdata)) as? [String: Any] {
                putPlayer(id, pobj)
            }
            if let adata = try? Data(contentsOf: legacy.appendingPathComponent("advancements/\(id).json")),
               let aobj = (try? JSONSerialization.jsonObject(with: adata)) as? [String] {
                putAdvancements(id, aobj)
            }
            let cdir = legacy.appendingPathComponent("chunks/\(id)", isDirectory: true)
            guard let cfiles = try? fm.contentsOfDirectory(at: cdir, includingPropertiesForKeys: nil) else { continue }
            exec("BEGIN")
            for cf in cfiles where cf.pathExtension == "vck" {
                let parts = cf.deletingPathExtension().lastPathComponent.split(separator: "_")
                guard parts.count == 3, let dim = Int(parts[0]), let cx = Int(parts[1]), let cz = Int(parts[2]),
                      let cdata = try? Data(contentsOf: cf) else { continue }
                run("INSERT OR REPLACE INTO chunks(world, dim, cx, cz, data) VALUES(?,?,?,?,?)", bind: { stmt in
                    self.bindText(stmt, 1, id)
                    sqlite3_bind_int(stmt, 2, Int32(dim))
                    sqlite3_bind_int(stmt, 3, Int32(cx))
                    sqlite3_bind_int(stmt, 4, Int32(cz))
                    cdata.withUnsafeBytes { raw in
                        _ = sqlite3_bind_blob(stmt, 5, raw.baseAddress, Int32(raw.count), SQLITE_TRANSIENT)
                    }
                })
                chunks += 1
            }
            exec("COMMIT")
        }
        let backup = vcSupportDir().appendingPathComponent("saves-legacy-backup")
        try? fm.moveItem(at: legacy, to: backup)
        print("[saves] migrated \(worlds) worlds, \(chunks) chunks into pebble.db (old files kept in saves-legacy-backup)")
        fflush(stdout)
    }
}
