// Headless smoke tests for PebbleCore. The frozen golden baselines
// (goldens/*.json) pin engine behavior — the engine must reproduce them
// bit-for-bit so worldgen seeds carry over across releases.

import Foundation
import simd
import PebbleCore

// PEBBLE_CWD=<repo> lets runners that can't set the working directory
// (simctl spawn in the iOS Simulator) still find goldens/
if let cwd = ProcessInfo.processInfo.environment["PEBBLE_CWD"] {
    FileManager.default.changeCurrentDirectoryPath(cwd)
}

var passed = 0
var failed = 0

func check(_ name: String, _ cond: Bool, _ detail: String = "") {
    if cond {
        passed += 1
        print("  ✓ \(name)")
    } else {
        failed += 1
        print("  ✗ \(name) \(detail)")
    }
}

func checkD(_ name: String, _ got: Double, _ want: Double, tol: Double = 1e-12) {
    check(name, abs(got - want) <= tol, "got \(got) want \(want)")
}

func section(_ name: String) { print("\n— \(name)") }

// ---------------------------------------------------------------------------
section("random (vs goldens)")
check("hashString abc", hashString("abc") == 440920331, "got \(hashString("abc"))")
check("mix32 12345", mix32(12345) == 1011272156, "got \(mix32(12345))")
check("hash2", hash2(999, -1234, 5678, 7) == 1511826033, "got \(hash2(999, -1234, 5678, 7))")
check("hash3", hash3(999, -12, 34, -56, 3) == 2031202406, "got \(hash3(999, -12, 34, -56, 3))")

var r = RandomX(12345)
let golden12345: [UInt32] = [1009662611, 487413528, 3278825217, 2736101217, 2510057557, 1701016183, 572264801, 2565169478]
var seqOK = true
for (i, want) in golden12345.enumerated() {
    let got = r.next()
    if got != want { seqOK = false; print("    sfc32[\(i)] got \(got) want \(want)") }
}
check("sfc32 seed 12345 sequence", seqOK)

var r2 = RandomX(0xDEAD_BEEF)
let goldenDB: [UInt32] = [1504311087, 3087835436, 4013932724, 864736003]
var seq2OK = true
for want in goldenDB { if r2.next() != want { seq2OK = false } }
check("sfc32 seed 0xDEADBEEF sequence", seq2OK)

var r3 = RandomX(777)
var inRange = true
for _ in 0..<1000 {
    let v = r3.nextInt(10)
    if v < 0 || v >= 10 { inRange = false }
}
check("nextInt bounds", inRange)

// ---------------------------------------------------------------------------
section("simplex noise (vs goldens)")
let n = SimplexNoise(42)
checkD("noise2 (0.5,0.5)", n.noise2(0.5, 0.5), -0.30780618346945793)
checkD("noise2 (10.25,-3.75)", n.noise2(10.25, -3.75), 0)
checkD("noise2 (100.1,200.9)", n.noise2(100.1, 200.9), -0.6225765639891507)
checkD("noise2 (-55.5,17.3)", n.noise2(-55.5, 17.3), 0.4811125458747653)
checkD("noise3 (1.5,2.5,3.5)", n.noise3(1.5, 2.5, 3.5), 0)
checkD("noise3 (-10.1,40.2,-7.7)", n.noise3(-10.1, 40.2, -7.7), 0.12712837501423255)

let f = FBM(7, 4, 0.01)
checkD("fbm sample2 (123.4,567.8)", f.sample2(123.4, 567.8), -0.17945870068084002)
checkD("fbm ridge2 (123.4,567.8)", f.ridge2(123.4, 567.8), 0.4321547307883241)
checkD("fbm sample2 (-1000.5,250.25)", f.sample2(-1000.5, 250.25), -0.37532916362726393)
checkD("fbm ridge2 (-1000.5,250.25)", f.ridge2(-1000.5, 250.25), 0.41162552326329793)

let sp = Spline([(0, 0), (0.5, 10), (1, 4)])
checkD("spline at -1", sp.at(-1), 0)
checkD("spline at 0.25", sp.at(0.25), 5)
checkD("spline at 0.5", sp.at(0.5), 10)
checkD("spline at 0.75", sp.at(0.75), 7)
checkD("spline at 2", sp.at(2), 4)

// ---------------------------------------------------------------------------
section("math")
let a = AABB(0, 0, 0, 1, 1, 1)
let b = AABB(2, 0, 0, 3, 1, 1)
checkD("sweepX blocked", sweepX(a, b, 5), 1)
checkD("sweepX clear (offset z)", sweepX(a, b.offset(0, 0, 5), 5), 5)
checkD("sweepY through", sweepY(a, b, 3), 3)
check("aabb intersects", AABB(0, 0, 0, 2, 2, 2).intersects(AABB(1, 1, 1, 3, 3, 3)))
check("aabb no intersect", !AABB(0, 0, 0, 1, 1, 1).intersects(AABB(1, 0, 0, 2, 1, 1)))

let t = rayAABB(-5, 0.5, 0.5, 1, 0, 0, a)
checkD("rayAABB hit", t, 5)
check("rayAABB miss", rayAABB(-5, 5, 0.5, 1, 0, 0, a) == -1)

var fr = Frustum()
let proj = mat4Perspective(fovYRad: Float(degToRad(70)), aspect: 16.0 / 9.0, near: 0.05, far: 400)
let view = mat4LookDir(eye: SIMD3<Float>(0, 0, 0), dir: SIMD3<Float>(0, 0, 1), up: SIMD3<Float>(0, 1, 0))
fr.setFromMatrix(proj * view)
check("frustum sees box ahead", fr.intersectsBox(-5, -5, 10, 5, 5, 20))
check("frustum culls box behind", !fr.intersectsBox(-5, -5, -20, 5, 5, -10))
check("frustum culls box far right", !fr.intersectsBox(500, -5, 10, 510, 5, 20))

checkD("wrapDegrees 270", wrapDegrees(270), -90)
checkD("wrapDegrees -270", wrapDegrees(-270), 90)
checkD("lerp", lerpD(0, 10, 0.25), 2.5)

// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
section("block registry (vs goldens)")
registerAllBlocks()
// ids are per world now (a saved palette maps them), so only air's is fixed:
// cell 0 means "nothing here" throughout the engine
check("air is block 0", bid("air") == 0)
check("block names are unique", Set(blockDefs.map(\.name)).count == blockDefs.count)
check("tile count (fallback atlas)", tileCount() >= 757, "got \(tileCount())")
check("tile grass_top", tileId("grass_top") == 38, "got \(tileId("grass_top"))")
check("tile destroy_9", tileId("destroy_9") == 740, "got \(tileId("destroy_9"))")
check("tile 756 is sweep_particle", allTileNames().count > 756 && allTileNames()[756] == "sweep_particle", "got \(allTileNames().count > 756 ? allTileNames()[756] : "nil")")
check("cell roundtrip", cell(B.stone, 7) >> 4 == B.stone && cellMeta(cell(B.stone, 7)) == 7)
check("lightEmitOf torch", lightEmitOf(cell(B.torch)) == 14)
check("lightEmitOf sea_pickle x4", lightEmitOf(cell(B.sea_pickle, 3)) == 15)
check("water replaceable", REPLACEABLE[Int(B.water)] == 1)
check("stone opaque", OPAQUE[Int(B.stone)] == 1)
check("glass not opaque", OPAQUE[Int(B.glass)] == 0)
let bedDropCtx = DropCtx(random: { 0 })
let bedDrops = blockDefs[Int(B.white_bed)].drops
check("two-block bed drops exactly once",
      bedDrops?(0, bedDropCtx).map(\.item) == ["white_bed"] &&
      bedDrops?(4, bedDropCtx).isEmpty == true)

// ---------------------------------------------------------------------------
section("item registry (vs goldens)")
registerAllItems()
check("item names are unique", Set(itemDefs.map(\.name)).count == itemDefs.count)
check("blockToItem stone", blockToItem[Int(B.stone)] == Int32(iid("stone")))
check("cake maxStack 1", itemDefs[iid("cake")].maxStack == 1)
check("darksteel sword dmg", itemDefs[iid("darksteel_sword")].tool?.attackDamage == 7)
check("diamond chest durability", itemDefs[iid("diamond_chestplate")].armor?.durability == 529)
check("steak hunger", itemDefs[iid("cooked_beef")].food?.hunger == 8)
check("lava bucket burn", itemDefs[iid("lava_bucket")].burnTime == 20000)
check("merge same", canMerge(ItemStack(iid("stone"), 5), ItemStack(iid("stone"), 3)))
check("no merge tools", !canMerge(ItemStack(iid("iron_sword")), ItemStack(iid("iron_sword"))))

// ---------------------------------------------------------------------------
section("biomes (vs goldens)")
registerAllBiomes()
check("biome count = enum count", BIOMES.count == Biome.allCases.count, "got \(BIOMES.count)")


/// snapshots named in PEBBLE_REGOLD ("terrain,feature", or "all" / "1") are
/// rewritten from this run instead of checked — `pebble test --regold …`
let REGOLD: Set<String> = Set((ProcessInfo.processInfo.environment["PEBBLE_REGOLD"] ?? "")
    .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
func regolding(_ name: String) -> Bool { REGOLD.contains(name) || REGOLD.contains("all") || REGOLD.contains("1") }

/// write a regenerated golden file with sorted keys (so it's byte-stable),
/// printing every key path whose value changed — check that only what you
/// meant to move moved
func writeGolden(_ path: String, _ data: Data) {
    guard let new = try? JSONSerialization.jsonObject(with: data) else { return }
    let old = FileManager.default.contents(atPath: path).flatMap { try? JSONSerialization.jsonObject(with: $0) }
    func diff(_ a: Any?, _ b: Any?, _ at: String, _ out: inout [String]) {
        if let da = a as? [String: Any], let db = b as? [String: Any] {
            for k in Set(da.keys).union(db.keys).sorted() { diff(da[k], db[k], at + "/" + k, &out) }
        } else if let la = a as? [Any], let lb = b as? [Any], la.count == lb.count {
            for i in la.indices { diff(la[i], lb[i], at + "[\(i)]", &out) }
        } else if !((a as? NSObject)?.isEqual(b) ?? (a == nil && b == nil)) {
            out.append(at)
        }
    }
    var changed: [String] = []
    diff(old, new, "", &changed)
    if let sorted = try? JSONSerialization.data(withJSONObject: new, options: [.sortedKeys]) {
        try? sorted.write(to: URL(fileURLWithPath: path))
    }
    let file = (path as NSString).lastPathComponent
    if changed.isEmpty { print("    \(file): no values changed") }
    for c in changed.prefix(40) { print("    \(file) changed: \(c)") }
    if changed.count > 40 { print("    \(file): …and \(changed.count - 40) more") }
}

/// candidate paths for a golden file — goldens/ beside the package manifest,
/// tolerant of being run from the repo root, its parent, or a subdirectory
func goldenPaths(_ name: String) -> [String] {
    ["goldens/\(name)", "../goldens/\(name)", name]
}

func loadJSON(_ name: String) -> [String: Any]? {
    for p in goldenPaths(name) {
        if let d = FileManager.default.contents(atPath: p),
           let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] {
            return obj
        }
    }
    return nil
}

if let g = loadJSON("biome-goldens.json") {
    let count = (g["biomeCount"] as! NSNumber).intValue
    check("biome count vs goldens", BIOMES.count == count, "got \(BIOMES.count) want \(count)")

    let names = g["names"] as! [String]
    var namesOK = true
    for (i, want) in names.enumerated() where BIOMES[i]?.name != want {
        namesOK = false
        print("    biome[\(i)] got \(BIOMES[i]?.name ?? "nil") want \(want)")
    }
    check("\(names.count) biome names in identical order", namesOK)

    let climates = g["climates"] as! [[NSNumber]]
    let samples = (g["samples"] as! [NSNumber]).map { $0.intValue }
    var mismatches = 0
    for (i, cl) in climates.enumerated() {
        let c = Climate(t: cl[0].doubleValue, h: cl[1].doubleValue, c: cl[2].doubleValue,
                        e: cl[3].doubleValue, w: cl[4].doubleValue,
                        pv: peaksValleys(cl[4].doubleValue), rare: cl[5].doubleValue)
        if selectBiome(c).rawValue != samples[i] {
            mismatches += 1
            if mismatches <= 5 {
                print("    selectBiome[\(i)] got \(selectBiome(c).rawValue) want \(samples[i]) cl=\(cl)")
            }
        }
    }
    check("selectBiome 2000 samples bit-identical", mismatches == 0, "\(mismatches) mismatches")

    let pvG = (g["pv"] as! [NSNumber]).map { $0.doubleValue }
    var pvOK = true
    for (i, want) in pvG.enumerated() where abs(peaksValleys(-1 + Double(i) * 0.05) - want) > 1e-12 {
        pvOK = false
    }
    check("peaksValleys curve", pvOK)

    let defs = g["defChecks"] as! [[String: Any]]
    var defOK = true
    func defFail(_ b: Int, _ what: String) { defOK = false; print("    def[\(b)] \(what)") }
    for d in defs {
        let b = (d["b"] as! NSNumber).intValue
        guard let def = BIOMES[b] else { defFail(b, "missing"); continue }
        if def.name != d["name"] as! String { defFail(b, "name") }
        if def.displayName != d["display"] as! String { defFail(b, "display") }
        if abs(def.temperature - (d["temp"] as! NSNumber).doubleValue) > 1e-12 { defFail(b, "temp") }
        if abs(def.downfall - (d["downfall"] as! NSNumber).doubleValue) > 1e-12 { defFail(b, "downfall") }
        if def.grassColor != (d["grass"] as! NSNumber).uint32Value { defFail(b, "grass") }
        if def.foliageColor != (d["foliage"] as! NSNumber).uint32Value { defFail(b, "foliage") }
        if def.waterColor != (d["water"] as! NSNumber).uint32Value { defFail(b, "water") }
        if def.fogTint != (d["fogTint"] as! NSNumber).uint32Value { defFail(b, "fogTint") }
        if Int(def.top) != (d["top"] as! NSNumber).intValue { defFail(b, "top got \(def.top) want \(d["top"]!)") }
        if Int(def.under) != (d["under"] as! NSNumber).intValue { defFail(b, "under got \(def.under) want \(d["under"]!)") }
        if Int(def.underwaterTop) != (d["uwTop"] as! NSNumber).intValue { defFail(b, "uwTop got \(def.underwaterTop) want \(d["uwTop"]!)") }
        if def.features != d["features"] as! [String] {
            defFail(b, "features\n      got  \(def.features)\n      want \(d["features"]!)")
        }
        if def.mood != d["mood"] as! String { defFail(b, "mood") }
        let monsters = d["monsters"] as! [[Any]]
        if def.monsters.count != monsters.count { defFail(b, "monsters count") }
        else {
            for (i, m) in monsters.enumerated() {
                let got = def.monsters[i]
                if got.mob != m[0] as! String || got.weight != (m[1] as! NSNumber).doubleValue
                    || got.minPack != (m[2] as! NSNumber).intValue || got.maxPack != (m[3] as! NSNumber).intValue {
                    defFail(b, "monster[\(i)]")
                }
            }
        }
        let creatures = d["creatures"] as! [[Any]]
        if def.creatures.count != creatures.count { defFail(b, "creatures count") }
        else {
            for (i, m) in creatures.enumerated() {
                let got = def.creatures[i]
                if got.mob != m[0] as! String || got.weight != (m[1] as! NSNumber).doubleValue {
                    defFail(b, "creature[\(i)]")
                }
            }
        }
    }
    check("10 BiomeDef spot checks (fields, features, spawns)", defOK || regolding("biome"))

    let temps = g["tempSamples"] as! [[String: Any]]
    // native baseline since the vanilla snow-lapse fix (PEBBLE_REGOLD regenerates)
    if regolding("biome") {
        let captured = temps.map { s -> [String: Any] in
            let b = (s["b"] as! NSNumber).intValue
            let y = (s["y"] as! NSNumber).intValue
            return ["b": b, "y": y, "t": temperatureAt(b, y), "snows": snowsAt(b, y)]
        }
        for path in goldenPaths("biome-goldens.json") {
            guard let d = FileManager.default.contents(atPath: path),
                  var obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { continue }
            obj["tempSamples"] = captured
            // the spot-checked biomes' feature lists follow the code too
            obj["defChecks"] = defs.map { d -> [String: Any] in
                var d = d
                if let def = BIOMES[(d["b"] as! NSNumber).intValue] {
                    d["features"] = def.features
                    d["monsters"] = def.monsters.map { [$0.mob, $0.weight, $0.minPack, $0.maxPack] as [Any] }
                    d["creatures"] = def.creatures.map { [$0.mob, $0.weight, $0.minPack, $0.maxPack] as [Any] }
                }
                return d
            }
            if let out = try? JSONSerialization.data(withJSONObject: obj) {
                writeGolden(path, out)
            }
            break
        }
        check("temperature: goldens regenerated (native baseline)", true)
    } else {
    var tOK = true
    for s in temps {
        let b = (s["b"] as! NSNumber).intValue
        let y = (s["y"] as! NSNumber).intValue
        let want = (s["t"] as! NSNumber).doubleValue
        let wantSnows = (s["snows"] as! NSNumber).boolValue
        if abs(temperatureAt(b, y) - want) > 1e-12 || snowsAt(b, y) != wantSnows {
            tOK = false
            print("    temp b=\(b) y=\(y) got \(temperatureAt(b, y)) want \(want)")
        }
    }
    check("temperatureAt/snowsAt \(temps.count) samples", tOK)
    }

    let flags = (g["flags"] as! [NSNumber]).map { $0.intValue }
    var flagsOK = true
    for (i, f) in flags.enumerated() {
        let got = (isOceanBiome(i) ? 1 : 0) | (isCaveBiome(i) ? 2 : 0)
        if got != f { flagsOK = false; print("    flags[\(i)] got \(got) want \(f)") }
    }
    check("ocean/cave flags all \(flags.count) biomes", flagsOK)

    if let allColors = g["allColors"] as? [[NSNumber]] {
        var colorsOK = true
        for (i, cs) in allColors.enumerated() {
            guard let d = BIOMES[i] else { colorsOK = false; continue }
            let got = [d.grassColor, d.foliageColor, d.waterColor, d.fogTint]
            for (j, w) in cs.enumerated() where got[j] != w.uint32Value {
                colorsOK = false
                print("    \(d.name) color[\(j)] got \(String(got[j], radix: 16)) want \(String(w.uint32Value, radix: 16))")
            }
        }
        check("grass/foliage/water/fog colors all \(allColors.count) biomes", colorsOK)
    }
} else {
    check("biome-goldens.json loadable", false, "not found — run from the repo root (goldens/)")
}

// ---------------------------------------------------------------------------
section("overworld terrain (vs goldens)")

func fnvU16(_ arr: [UInt16]) -> UInt32 {
    var h: UInt32 = 2166136261
    for v in arr {
        h = (h ^ UInt32(v & 0xff)) &* 16777619
        h = (h ^ UInt32(v >> 8)) &* 16777619
    }
    return h
}
func fnvI16(_ arr: [Int16]) -> UInt32 {
    var h: UInt32 = 2166136261
    for s in arr {
        let v = UInt16(bitPattern: s)
        h = (h ^ UInt32(v & 0xff)) &* 16777619
        h = (h ^ UInt32(v >> 8)) &* 16777619
    }
    return h
}
func fnvU8(_ arr: [UInt8]) -> UInt32 {
    var h: UInt32 = 2166136261
    for b in arr { h = (h ^ UInt32(b)) &* 16777619 }
    return h
}

if let g = loadJSON("terrain-goldens.json") {
    var terrainGens: [UInt32: OverworldGen] = [:]
    func genFor(_ s: UInt32) -> OverworldGen {
        if let g = terrainGens[s] { return g }
        let g = OverworldGen(s)
        terrainGens[s] = g
        return g
    }

    // native baseline since the #26 worldgen quality pass (regenerate with
    // PEBBLE_REGOLD=1 after deliberate generation changes)
    let tRegold = regolding("terrain")
    var tCaptured: [[String: Any]] = []
    let chunkList = g["chunks"] as! [[String: Any]]
    for (i, c) in chunkList.enumerated() {
        let seed = (c["seed"] as! NSNumber).uint32Value
        let cx = (c["cx"] as! NSNumber).intValue
        let cz = (c["cz"] as! NSNumber).intValue
        let gen = genFor(seed)
        var blocks = [UInt16](repeating: 0, count: 16 * 16 * WORLD_H)
        var biomes = [UInt8](repeating: 0, count: 4 * 4 * ((WORLD_H + 3) / 4))
        let t0 = DispatchTime.now()
        let res = gen.fillTerrain(cx, cz, &blocks, &biomes)
        let label = "seed \(seed) (\(cx),\(cz))"
        let hFill = fnvU16(blocks)
        let hHeights = fnvI16(res.heights)
        let hSurfaceBiomes = fnvU8(res.surfaceBiomes)
        let hBiomes = fnvU8(biomes)
        gen.carve(cx, cz, &blocks)
        let hCarve = fnvU16(blocks)
        gen.applySurface(cx, cz, &blocks, res.surfaceBiomes)
        let hSurface = fnvU16(blocks)
        gen.placeOres(cx, cz, &blocks, res.surfaceBiomes)
        let hOres = fnvU16(blocks)
        gen.applySnowAndIce(cx, cz, &blocks, res.surfaceBiomes)
        let hSnow = fnvU16(blocks)
        let ms = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1e6
        if tRegold {
            tCaptured.append([
                "seed": NSNumber(value: seed), "cx": cx, "cz": cz,
                "hFill": NSNumber(value: hFill), "hHeights": NSNumber(value: hHeights),
                "hSurfaceBiomes": NSNumber(value: hSurfaceBiomes), "hBiomes": NSNumber(value: hBiomes),
                "hCarve": NSNumber(value: hCarve), "hSurface": NSNumber(value: hSurface),
                "hOres": NSNumber(value: hOres), "hSnow": NSNumber(value: hSnow),
                "heights": res.heights.map { NSNumber(value: $0) },
            ])
            continue
        }
        check("\(label) fillTerrain hash", hFill == (c["hFill"] as! NSNumber).uint32Value,
              "got \(String(hFill, radix: 16)) want \(String((c["hFill"] as! NSNumber).uint32Value, radix: 16))")
        check("\(label) heights hash", hHeights == (c["hHeights"] as! NSNumber).uint32Value)
        check("\(label) surfaceBiomes hash", hSurfaceBiomes == (c["hSurfaceBiomes"] as! NSNumber).uint32Value)
        check("\(label) biomes hash", hBiomes == (c["hBiomes"] as! NSNumber).uint32Value)
        check("\(label) carve hash", hCarve == (c["hCarve"] as! NSNumber).uint32Value,
              "got \(String(hCarve, radix: 16)) want \(String((c["hCarve"] as! NSNumber).uint32Value, radix: 16))")
        check("\(label) applySurface hash", hSurface == (c["hSurface"] as! NSNumber).uint32Value)
        check("\(label) placeOres hash", hOres == (c["hOres"] as! NSNumber).uint32Value)
        check("\(label) snow/ice hash [\(String(format: "%.1f", ms))ms]", hSnow == (c["hSnow"] as! NSNumber).uint32Value)

        // cell-level diff for the first case if anything mismatched
        if i == 0, let b64 = c["blocksB64"] as? String, fnvU16(blocks) != (c["hSnow"] as! NSNumber).uint32Value {
            if let data = Data(base64Encoded: b64) {
                let want: [UInt16] = data.withUnsafeBytes { Array($0.bindMemory(to: UInt16.self)) }
                var shown = 0
                for idx in 0..<min(want.count, blocks.count) where want[idx] != blocks[idx] {
                    let y = idx / 256 + GEN_MIN_Y, z = (idx / 16) % 16, x = idx % 16
                    print("    cell (\(x),\(y),\(z)) got \(blocks[idx]) want \(want[idx])")
                    shown += 1
                    if shown >= 12 { break }
                }
            }
        }

        // heights array equality (cheap, already hashed — belt and suspenders)
        let wantHeights = (c["heights"] as! [NSNumber]).map { Int16(truncating: $0) }
        check("\(label) heights array equal", res.heights == wantHeights)
    }

    // scalar samples on seed 12345
    let sg = genFor(12345)
    let coords = (g["coords"] as! [[NSNumber]]).map { (Double(truncating: $0[0]), Double(truncating: $0[1])) }
    if tRegold {
        for path in goldenPaths("terrain-goldens.json") {
            guard let d = FileManager.default.contents(atPath: path),
                  var obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { continue }
            obj["chunks"] = tCaptured
            obj["heightSamples"] = coords.map { NSNumber(value: sg.heightEstimate($0.0, $0.1)) }
            obj["biomeSamples"] = coords.map { NSNumber(value: sg.surfaceBiomeAt($0.0, $0.1).rawValue) }
            obj["aquiferSamples"] = coords.map { (x, z) -> [NSNumber] in
                let a = sg.aquiferAt(x, z, sg.climate.at(x, z))
                return [NSNumber(value: a.level), NSNumber(value: a.lava ? 1 : 0)]
            }
            var caves: [NSNumber] = []
            for (x, z) in coords {
                for y in [-30, 0, 40] {
                    caves.append(NSNumber(value: sg.caveBiomeAt(x, y, z, sg.heightEstimate(x, z))))
                }
            }
            obj["caveSamples"] = caves
            if let out = try? JSONSerialization.data(withJSONObject: obj) {
                writeGolden(path, out)
                print("    REGENERATED terrain chunks (\(tCaptured.count)) + scalar samples -> \(path)")
            }
            break
        }
        check("terrain: goldens regenerated (native baseline)", true)
    } else {
    let wantHeightsS = (g["heightSamples"] as! [NSNumber]).map { $0.intValue }
    var hOK = true
    for (i, (x, z)) in coords.enumerated() where sg.heightEstimate(x, z) != wantHeightsS[i] {
        hOK = false
        print("    heightEstimate(\(x),\(z)) got \(sg.heightEstimate(x, z)) want \(wantHeightsS[i])")
    }
    check("heightEstimate \(coords.count) samples", hOK)

    let wantBiomesS = (g["biomeSamples"] as! [NSNumber]).map { $0.intValue }
    var bOK = true
    for (i, (x, z)) in coords.enumerated() where sg.surfaceBiomeAt(x, z).rawValue != wantBiomesS[i] {
        bOK = false
    }
    check("surfaceBiomeAt \(coords.count) samples", bOK)

    let wantAq = (g["aquiferSamples"] as! [[NSNumber]])
    var aqOK = true
    for (i, (x, z)) in coords.enumerated() {
        let a = sg.aquiferAt(x, z, sg.climate.at(x, z))
        if a.level != wantAq[i][0].intValue || (a.lava ? 1 : 0) != wantAq[i][1].intValue { aqOK = false }
    }
    check("aquiferAt \(coords.count) samples", aqOK)

    let wantCave = (g["caveSamples"] as! [NSNumber]).map { $0.intValue }
    var cvOK = true
    var cvi = 0
    for (x, z) in coords {
        for y in [-30, 0, 40] {
            if sg.caveBiomeAt(x, y, z, sg.heightEstimate(x, z)) != wantCave[cvi] { cvOK = false }
            cvi += 1
        }
    }
    check("caveBiomeAt \(wantCave.count) samples", cvOK)
    }

    let wantClim = (g["climSamples"] as! [[String]])
    var clOK = true
    for (i, cs) in wantClim.enumerated() {
        let (x, z) = coords[i]
        let c = sg.climate.at(x, z)
        let got = [c.t, c.h, c.c, c.e, c.w, c.pv, c.rare]
        for (j, hex) in cs.enumerated() {
            let want = Double(bitPattern: UInt64(hex, radix: 16)!)
            if got[j].bitPattern != want.bitPattern {
                clOK = false
                print("    climate[\(i)][\(j)] got \(got[j]) want \(want)")
            }
        }
    }
    check("climate fields bit-pattern-exact \(wantClim.count) samples", clOK)
} else {
    check("terrain-goldens.json loadable", false, "not found — run from the repo root (goldens/)")
}

// ---------------------------------------------------------------------------
section("full chunk pipeline with features (vs goldens)")

if let g = loadJSON("feature-goldens.json") {
    func fnvStr(_ h0: UInt32, _ s: String) -> UInt32 {
        var h = h0
        for b in Array(s.utf8) { h = (h ^ UInt32(b)) &* 16777619 }
        return h
    }
    func fnvInt(_ h0: UInt32, _ v: Int) -> UInt32 {
        var h = h0
        let u = UInt32(truncatingIfNeeded: v)
        h = (h ^ (u & 0xff)) &* 16777619
        h = (h ^ ((u >> 8) & 0xff)) &* 16777619
        h = (h ^ ((u >> 16) & 0xff)) &* 16777619
        h = (h ^ ((u >> 24) & 0xff)) &* 16777619
        return h
    }
    // "cases" is a CONTRACT: generator version 1 must keep building exactly
    // these chunks, because worlds made before 1.5 regenerate untouched land
    // from the seed. Never regenerated. "casesV2" is the snapshot for new
    // worlds (same chunks, current generator): --regold feature.
    let contractCases = g["cases"] as! [[String: Any]]
    var totalMs = 0.0
    for (version, key) in [(1, "cases"), (2, "casesV2")] {
    let fRegold = version >= 2 && regolding("feature")
    var fCaptured: [[String: Any]] = []
    let stored = g[key] as? [[String: Any]]
    if stored == nil && !fRegold {
        check("feature-goldens.json has \(key)", false, "missing: run pebble test --regold feature")
        continue
    }
    let cases = stored ?? contractCases
    for c in cases {
        let seed = (c["seed"] as! NSNumber).uint32Value
        let cx = (c["cx"] as! NSNumber).intValue
        let cz = (c["cz"] as! NSNumber).intValue
        let dim = Dim(rawValue: (c["dim"] as! NSNumber).intValue)!
        let t0 = DispatchTime.now()
        let out = generateChunk(dim, seed, cx, cz, genVersion: version)
        let ms = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1e6
        totalMs += ms
        let label = "gen v\(version) d\(dim.rawValue) seed \(seed) (\(cx),\(cz))"
        let hBlocks = fnvU16(out.blocks)
        let hBiomes = fnvU8(out.biomes)
        var beHash: UInt32 = 2166136261
        for be in out.blockEntities {
            beHash = fnvInt(beHash, be.x); beHash = fnvInt(beHash, be.y); beHash = fnvInt(beHash, be.z)
            beHash = fnvStr(beHash, be.kind)
        }
        var entHash: UInt32 = 2166136261
        for e in out.entities {
            // the contract was recorded before mobs were renamed: hash their
            // names as they were then (FormatNames), so it still proves the
            // same mobs generate in the same places
            entHash = fnvStr(entHash, version == 1 ? packName(e.mob) : e.mob)
            entHash = fnvInt(entHash, Int((e.x * 2).rounded())); entHash = fnvInt(entHash, Int((e.y * 2).rounded())); entHash = fnvInt(entHash, Int((e.z * 2).rounded()))
        }
        var refHash: UInt32 = 2166136261
        for rf in out.structRefs {
            refHash = fnvStr(refHash, rf.id)
            refHash = fnvInt(refHash, rf.x0); refHash = fnvInt(refHash, rf.y0); refHash = fnvInt(refHash, rf.z0)
            refHash = fnvInt(refHash, rf.x1); refHash = fnvInt(refHash, rf.y1); refHash = fnvInt(refHash, rf.z1)
        }
        if fRegold {
            fCaptured.append([
                "seed": NSNumber(value: seed), "cx": cx, "cz": cz, "dim": dim.rawValue,
                "hBlocks": NSNumber(value: hBlocks), "hBiomes": NSNumber(value: hBiomes),
                "beCount": out.blockEntities.count, "beHash": NSNumber(value: beHash),
                "entCount": out.entities.count, "entHash": NSNumber(value: entHash),
                "refCount": out.structRefs.count, "refHash": NSNumber(value: refHash),
            ])
            continue
        }
        let wantBlocks = (c["hBlocks"] as! NSNumber).uint32Value
        check("\(label) blocks hash [\(String(format: "%.0f", ms))ms]", hBlocks == wantBlocks,
              "got \(String(hBlocks, radix: 16)) want \(String(wantBlocks, radix: 16))")
        check("\(label) biomes hash", hBiomes == (c["hBiomes"] as! NSNumber).uint32Value)
        check("\(label) BE count", out.blockEntities.count == (c["beCount"] as! NSNumber).intValue,
              "got \(out.blockEntities.count) want \(c["beCount"]!)")
        check("\(label) BE hash", beHash == (c["beHash"] as! NSNumber).uint32Value)
        check("\(label) entity count", out.entities.count == (c["entCount"] as! NSNumber).intValue,
              "got \(out.entities.count) want \(c["entCount"]!)")
        check("\(label) entity hash", entHash == (c["entHash"] as! NSNumber).uint32Value)
        check("\(label) structRefs \(out.structRefs.count)", out.structRefs.count == (c["refCount"] as! NSNumber).intValue
              && refHash == (c["refHash"] as! NSNumber).uint32Value)
    }
    if fRegold {
        for path in goldenPaths("feature-goldens.json") {
            guard let d = FileManager.default.contents(atPath: path),
                  var obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { continue }
            obj[key] = fCaptured
            if let out = try? JSONSerialization.data(withJSONObject: obj) {
                writeGolden(path, out)
            }
            break
        }
        check("features: \(key) regenerated", true)
    }
    }
    print("  · full pipeline avg \(String(format: "%.1f", totalMs / Double(contractCases.count * 2)))ms/chunk")
} else {
    check("feature-goldens.json loadable", false, "not found — run from the repo root (goldens/)")
}

// ---------------------------------------------------------------------------
section("atlas painters (vs goldens)")

if let g = loadJSON("atlas-goldens.json") {
    // a snapshot of every painted tile (the fallback atlas used without a pack)
    let t0 = DispatchTime.now()
    let atlas = buildAtlas()
    let ms = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1e6
    check("no missing painters", atlas.missing.isEmpty, "missing: \(atlas.missing.prefix(10))")
    let names = allTileNames()
    var hashes: [String: NSNumber] = [:]
    for (i, n) in names.enumerated() where i < atlas.pixels.count { hashes[n] = NSNumber(value: fnvU8(atlas.pixels[i])) }
    let sampleName = (g["sampleName"] as? String) ?? "grass_block_side"
    if regolding("atlas") {
        let sample = names.firstIndex(of: sampleName).map { Data(atlas.pixels[$0]).base64EncodedString() } ?? ""
        let obj: [String: Any] = ["count": atlas.count, "hashes": hashes, "sampleName": sampleName, "sampleB64": sample]
        if let path = goldenPaths("atlas-goldens.json").first(where: { FileManager.default.fileExists(atPath: $0) }),
           let data = try? JSONSerialization.data(withJSONObject: obj) {
            writeGolden(path, data)
        }
        check("atlas: snapshot regenerated", true)
    } else {
        let want = g["hashes"] as! [String: NSNumber]
        check("tile count", atlas.count == (g["count"] as! NSNumber).intValue, "got \(atlas.count) want \(g["count"]!)")
        let mismatches = names.filter { hashes[$0] != want[$0] }
        check("\(names.count) tiles pixel-identical [\(String(format: "%.0f", ms))ms]", mismatches.isEmpty,
              "\(mismatches.count) differ: \(mismatches.prefix(12))")
        if mismatches.contains(sampleName), let b64 = g["sampleB64"] as? String, let data = Data(base64Encoded: b64),
           let idx = names.firstIndex(of: sampleName) {
            let wantPx = [UInt8](data), gotPx = atlas.pixels[idx]
            for k in 0..<min(wantPx.count, gotPx.count) where wantPx[k] != gotPx[k] {
                print("    \(sampleName) byte[\(k)] px(\(k / 4 % 16),\(k / 64)) ch\(k % 4) got \(gotPx[k]) want \(wantPx[k])")
                break
            }
        }
    }
} else {
    check("atlas-goldens.json loadable", false, "not found — run from the repo root (goldens/)")
}

// ---------------------------------------------------------------------------
section("section mesher (vs goldens)")

if let g = loadJSON("mesh-goldens.json") {
    func fnvU32(_ arr: [UInt32]) -> UInt32 {
        var h: UInt32 = 2166136261
        for v in arr {
            h = (h ^ (v & 0xff)) &* 16777619
            h = (h ^ ((v >> 8) & 0xff)) &* 16777619
            h = (h ^ ((v >> 16) & 0xff)) &* 16777619
            h = (h ^ ((v >> 24) & 0xff)) &* 16777619
        }
        return h
    }

    struct LitChunk {
        let blocks: [UInt16]
        let biomes: [UInt8]
        let sky: [UInt8]
        let blk: [UInt8]
    }
    var litCache: [String: LitChunk] = [:]
    func litChunk(_ seed: UInt32, _ cx: Int, _ cz: Int) -> LitChunk {
        let key = "\(seed):\(cx),\(cz)"
        if let c = litCache[key] { return c }
        let out = generateChunk(.overworld, seed, cx, cz)
        let light = computeLocalLight(blocks: out.blocks, height: WORLD_H, hasSky: true)
        let c = LitChunk(blocks: out.blocks, biomes: out.biomes, sky: light.sky, blk: light.blk)
        litCache[key] = c
        return c
    }
    func chunkBiomeAt(_ c: LitChunk, _ lx: Int, _ y: Int, _ lz: Int) -> UInt8 {
        let qy = max(0, min((WORLD_H >> 2) - 1, (y - GEN_MIN_Y) >> 2))
        return c.biomes[(qy * 4 + (lz >> 2)) * 4 + (lx >> 2)]
    }
    func buildSnapshot(_ seed: UInt32, _ cx: Int, _ sy: Int, _ cz: Int) -> MeshInput {
        let P = 18
        var blocks = [UInt16](repeating: 0, count: P * P * P)
        var skyLight = [UInt8](repeating: 0, count: P * P * P)
        var blockLight = [UInt8](repeating: 0, count: P * P * P)
        var biomes = [UInt8](repeating: 0, count: BIOME_P * BIOME_P)
        let baseY = GEN_MIN_Y + sy * 16
        let baseX = cx * 16, baseZ = cz * 16
        for dz in -BIOME_H...(15 + BIOME_H) {
            for dx in -BIOME_H...(15 + BIOME_H) {
                let wx = baseX + dx, wz = baseZ + dz
                let c = litChunk(seed, floorDiv(wx, 16), floorDiv(wz, 16))
                let lx = posMod(wx, 16), lz = posMod(wz, 16)
                biomes[(dz + BIOME_H) * BIOME_P + (dx + BIOME_H)] = chunkBiomeAt(c, lx, min(GEN_MIN_Y + WORLD_H - 1, max(GEN_MIN_Y, baseY + 8)), lz)
                guard dx >= -1, dx <= 16, dz >= -1, dz <= 16 else { continue }
                for dy in -1...16 {
                    let wy = baseY + dy
                    let idx = ((dy + 1) * P + (dz + 1)) * P + (dx + 1)
                    if wy < GEN_MIN_Y || wy >= GEN_MIN_Y + WORLD_H {
                        blocks[idx] = 0
                        skyLight[idx] = wy >= GEN_MIN_Y + WORLD_H ? 15 : 0
                        blockLight[idx] = 0
                    } else {
                        let ci = ((wy - GEN_MIN_Y) * 16 + lz) * 16 + lx
                        blocks[idx] = c.blocks[ci]
                        skyLight[idx] = c.sky[ci]
                        blockLight[idx] = c.blk[ci]
                    }
                }
            }
        }
        return MeshInput(blocks: blocks, skyLight: skyLight, blockLight: blockLight, biomes: biomes)
    }

    // verify lighting first — light feeds the greedy merge keys
    if let lights = g["lights"] as? [[String: Any]] {
        var lightOK = true
        var lightCaptured: [[String: Any]] = []
        let lRegold = regolding("mesh")
        for l in lights {
            let key = l["key"] as! String
            let parts = key.split(separator: ":")
            let seed = UInt32(parts[0])!
            let coords = parts[1].split(separator: ",")
            let c = litChunk(seed, Int(coords[0])!, Int(coords[1])!)
            if lRegold {
                lightCaptured.append(["key": key, "hSky": NSNumber(value: fnvU8(c.sky)), "hBlk": NSNumber(value: fnvU8(c.blk))])
                continue
            }
            if fnvU8(c.sky) != (l["hSky"] as! NSNumber).uint32Value {
                lightOK = false
                print("    sky light mismatch at \(key): got \(String(fnvU8(c.sky), radix: 16)) want \(String((l["hSky"] as! NSNumber).uint32Value, radix: 16))")
            }
            if fnvU8(c.blk) != (l["hBlk"] as! NSNumber).uint32Value {
                lightOK = false
                print("    block light mismatch at \(key)")
            }
        }
        if lRegold {
            for path in goldenPaths("mesh-goldens.json") {
                guard let d = FileManager.default.contents(atPath: path),
                      var obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { continue }
                obj["lights"] = lightCaptured
                if let out = try? JSONSerialization.data(withJSONObject: obj) {
                    writeGolden(path, out)
                    print("    REGENERATED mesh lights (\(lightCaptured.count))")
                }
                break
            }
            check("computeLocalLight: goldens regenerated", true)
        } else {
            check("computeLocalLight \(lights.count) chunks bit-identical", lightOK)
        }
    }

    // native baseline since the emitCross perpendicular-diagonal fix
    // (regenerate with PEBBLE_REGOLD=1 after deliberate mesher changes)
    let meshRegold = regolding("mesh")
    var meshCaptured: [[String: Any]] = []
    let meshCases = g["cases"] as! [[String: Any]]
    for c in meshCases {
        let seed = (c["seed"] as! NSNumber).uint32Value
        let cx = (c["cx"] as! NSNumber).intValue
        let sy = (c["sy"] as! NSNumber).intValue
        let cz = (c["cz"] as! NSNumber).intValue
        let snap = buildSnapshot(seed, cx, sy, cz)
        let t0 = DispatchTime.now()
        let mesh = buildSectionMesh(snap)
        let ms = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1e6
        let label = "seed \(seed) (\(cx),s\(sy),\(cz))"
        if meshRegold {
            meshCaptured.append([
                "seed": NSNumber(value: seed), "cx": cx, "sy": sy, "cz": cz,
                "o": ["n": mesh.opaque.count, "hd": NSNumber(value: fnvU32(mesh.opaque.data)), "hi": NSNumber(value: fnvU32(mesh.opaque.idx))],
                "c": ["n": mesh.cutout.count, "hd": NSNumber(value: fnvU32(mesh.cutout.data)), "hi": NSNumber(value: fnvU32(mesh.cutout.idx))],
                "t": ["n": mesh.translucent.count, "hd": NSNumber(value: fnvU32(mesh.translucent.data)), "hi": NSNumber(value: fnvU32(mesh.translucent.idx))],
            ])
            continue
        }
        for (name, layer, want) in [("opaque", mesh.opaque, c["o"] as! [String: Any]),
                                    ("cutout", mesh.cutout, c["c"] as! [String: Any]),
                                    ("translucent", mesh.translucent, c["t"] as! [String: Any])] {
            let wn = (want["n"] as! NSNumber).intValue
            let whd = (want["hd"] as! NSNumber).uint32Value
            let whi = (want["hi"] as! NSNumber).uint32Value
            check("\(label) \(name) \(wn)v [\(String(format: "%.1f", ms))ms]",
                  layer.count == wn && fnvU32(layer.data) == whd && fnvU32(layer.idx) == whi,
                  "got n=\(layer.count) hd=\(String(fnvU32(layer.data), radix: 16)) hi=\(String(fnvU32(layer.idx), radix: 16)) want n=\(wn) hd=\(String(whd, radix: 16)) hi=\(String(whi, radix: 16))")
            if name == "cutout", layer.count != wn, let b64 = c["cutB64"] as? String, let dd = Data(base64Encoded: b64) {
                let want: [UInt32] = dd.withUnsafeBytes { Array($0.bindMemory(to: UInt32.self)) }
                var vi = 0
                while vi * 7 < min(want.count, layer.data.count) {
                    var same = true
                    for w in 0..<7 where want[vi * 7 + w] != layer.data[vi * 7 + w] { same = false }
                    if !same { break }
                    vi += 1
                }
                func dumpVert(_ src: [UInt32], _ i: Int, _ tag: String) {
                    guard i * 7 + 6 < src.count else { print("    \(tag) v\(i): <end>"); return }
                    let x = Float(bitPattern: src[i * 7]), y = Float(bitPattern: src[i * 7 + 1]), z = Float(bitPattern: src[i * 7 + 2])
                    let u = Float(bitPattern: src[i * 7 + 3]), v = Float(bitPattern: src[i * 7 + 4])
                    let A = src[i * 7 + 5], Bw = src[i * 7 + 6]
                    let tileIdx = Int(A & 4095), nrm = (A >> 12) & 7
                    let ao = (A >> 15) & 3, sk = (A >> 17) & 15, bl = (A >> 21) & 15
                    print("    \(tag) v\(i): pos(\(x),\(y),\(z)) uv(\(u),\(v)) tile=\(tileName(tileIdx)) n=\(nrm) ao=\(ao) sky=\(sk) blk=\(bl) B=\(String(Bw, radix: 16))")
                }
                // snapshot cells around the divergence
                let snap2 = buildSnapshot(seed, cx, sy, cz)
                for zz in 14...16 {
                    var row = "    cells z=\(zz): "
                    for xx in 5...10 {
                        for yy in 1...4 {
                            let cl = Int(snap2.blocks[((yy + 1) * 18 + (zz + 1)) * 18 + (xx + 1)])
                            if cl != 0 { row += "(\(xx),\(yy))=\(blockDefs[cl >> 4].name):\(cl & 15) " }
                        }
                    }
                    print(row)
                }
                print("    first divergent vertex: \(vi)")
                for k in 0..<6 {
                    dumpVert(layer.data, vi + k, "got ")
                    dumpVert(want, vi + k, "want")
                }
            }
        }
    }
    if meshRegold {
        for path in goldenPaths("mesh-goldens.json") {
            guard let d = FileManager.default.contents(atPath: path),
                  var obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { continue }
            obj["cases"] = meshCaptured
            if let out = try? JSONSerialization.data(withJSONObject: obj) {
                writeGolden(path, out)
                print("    REGENERATED mesh cases (\(meshCaptured.count)) -> \(path)")
            }
            break
        }
        check("mesh: goldens regenerated (native baseline)", true)
    }
} else {
    check("mesh-goldens.json loadable", false, "not found — run from the repo root (goldens/)")
}

// Targeted multi-part block regression: both block seams must sample the
// midpoint of their composite texture, and powered levers must change pose.
do {
    let padded = 18
    func pi(_ x: Int, _ y: Int, _ z: Int) -> Int {
        ((y + 1) * padded + (z + 1)) * padded + (x + 1)
    }
    var blocks = [UInt16](repeating: 0, count: padded * padded * padded)
    var sky = [UInt8](repeating: 15, count: blocks.count)
    let blockLight = [UInt8](repeating: 0, count: blocks.count)
    blocks[pi(2, 4, 2)] = cell(B.oak_door, 0)
    blocks[pi(2, 5, 2)] = cell(B.oak_door, 8)
    blocks[pi(6, 4, 8)] = cell(B.white_bed, 0)
    blocks[pi(6, 4, 7)] = cell(B.white_bed, 4)
    // Keep the compiler from treating the all-15 array as immutable storage in
    // older Swift releases used by the supported toolchain sweep.
    sky[pi(0, 0, 0)] = 15
    let multipart = buildSectionMesh(MeshInput(
        blocks: blocks, skyLight: sky, blockLight: blockLight,
        biomes: [UInt8](repeating: 0, count: BIOME_P * BIOME_P), noMerge: true))
    let doorTile = Int(TILE_TABLE[(Int(cell(B.oak_door, 0)) << 3) | 2])
    let bedTopTile = Int(TILE_TABLE[(Int(cell(B.white_bed, 0)) << 3) | 1])
    var doorSeamV: [Float] = []
    var bedSeamV: [Float] = []
    for vi in 0..<(multipart.cutout.data.count / 7) {
        let o = vi * 7
        let a = multipart.cutout.data[o + 5]
        let layer = Int(a & 4095)
        let normal = Int((a >> 12) & 7)
        let y = Float(bitPattern: multipart.cutout.data[o + 1])
        let z = Float(bitPattern: multipart.cutout.data[o + 2])
        let v = Float(bitPattern: multipart.cutout.data[o + 4])
        if layer == doorTile && normal >= 2 && abs(y - 5) < 0.001 { doorSeamV.append(v) }
        if layer == bedTopTile && normal == 1 && abs(z - 8) < 0.001 { bedSeamV.append(v) }
    }
    var leverOff: [AABB] = [], leverOn: [AABB] = []
    shapeBoxes(Int(cell(B.lever, 0)), { _, _, _ in 0 }, &leverOff, false)
    shapeBoxes(Int(cell(B.lever, 8)), { _, _, _ in 0 }, &leverOn, false)
    let leverChangesPose = leverOff.count == 5 && leverOn.count == 5 &&
        abs((leverOff.last!.z0 + leverOff.last!.z1) - (leverOn.last!.z0 + leverOn.last!.z1)) > 0.1
    check("door/bed composite seams and lever powered pose",
          !doorSeamV.isEmpty && doorSeamV.allSatisfy { abs($0 - 0.5) < 0.001 } &&
          !bedSeamV.isEmpty && bedSeamV.allSatisfy { abs($0 - 0.5) < 0.001 } &&
          leverChangesPose)
}

// ---------------------------------------------------------------------------
section("world simulation: light engine + fluids + ticks (vs goldens)")

if let g = loadJSON("worldsim-goldens.json") {
    registerFluidHandlers()
    let world = World(dim: .overworld, seed: 12345)
    for cz in -1...1 {
        for cx in -1...1 {
            let out = generateChunk(.overworld, 12345, cx, cz)
            let light = computeLocalLight(blocks: out.blocks, height: WORLD_H, hasSky: true)
            let c = Chunk(cx: cx, cz: cz, minY: GEN_MIN_Y, height: WORLD_H)
            c.blocks = out.blocks
            c.skyLight = light.sky
            c.blockLight = light.blk
            c.biomes = out.biomes
            c.buildHeightmap()
            c.scanSpecials()
            c.status = .generated
            world.setChunk(c)
        }
    }
    for cz in -1...1 {
        for cx in -1...1 {
            world.light.stitchChunk(world.getChunk(cx, cz)!)
        }
    }

    func fnvAll() -> (UInt32, UInt32, UInt32) {
        var hb: UInt32 = 2166136261, hs: UInt32 = 2166136261, hl: UInt32 = 2166136261
        for cz in -1...1 {
            for cx in -1...1 {
                let c = world.getChunk(cx, cz)!
                for i in 0..<c.blocks.count {
                    let v = c.blocks[i]
                    hb = (hb ^ UInt32(v & 0xff)) &* 16777619
                    hb = (hb ^ UInt32(v >> 8)) &* 16777619
                    hs = (hs ^ UInt32(c.skyLight[i])) &* 16777619
                    hl = (hl ^ UInt32(c.blockLight[i])) &* 16777619
                }
            }
        }
        return (hb, hs, hl)
    }

    // native baseline since the #26 worldgen quality pass (regenerate with
    // PEBBLE_REGOLD=1 after deliberate generation changes)
    let wsRegold = regolding("worldsim")
    var wsCaptured: [[String: Any]] = []
    let stages = g["stages"] as! [[String: Any]]
    var stageIdx = 0
    func checkStage(_ name: String) {
        let (hb, hs, hl) = fnvAll()
        if wsRegold {
            wsCaptured.append(["name": name, "h": ["b": NSNumber(value: hb), "s": NSNumber(value: hs), "l": NSNumber(value: hl)]])
            stageIdx += 1
            return
        }
        let want = stages[stageIdx]
        stageIdx += 1
        let wn = want["name"] as! String
        let wh = want["h"] as! [String: NSNumber]
        check("stage \(name) blocks+sky+blockLight",
              wn == name && hb == wh["b"]!.uint32Value && hs == wh["s"]!.uint32Value && hl == wh["l"]!.uint32Value,
              "got b=\(String(hb, radix: 16)) s=\(String(hs, radix: 16)) l=\(String(hl, radix: 16)) want b=\(String(wh["b"]!.uint32Value, radix: 16)) s=\(String(wh["s"]!.uint32Value, radix: 16)) l=\(String(wh["l"]!.uint32Value, radix: 16))")
    }

    checkStage("adopted")

    let TORCH = Int(cell(B.torch)), GLOW = Int(cell(B.lumenstone)), STONE = Int(cell(B.stone))
    let WATERC = Int(cell(B.water, 0)), LAVAC = Int(cell(B.lava, 0))

    for y in 70...74 { for z in 2...6 { for x in 2...6 { world.setBlock(x, y, z, 0) } } }
    for z in 2...6 { for x in 2...6 { world.setBlock(x, 69, z, STONE) } }
    checkStage("box")

    world.setBlock(4, 70, 4, TORCH)
    checkStage("torch")

    for y in stride(from: 68, through: 40, by: -1) { world.setBlock(8, y, 8, 0) }
    world.setBlock(8, 40, 8, GLOW)
    checkStage("shaft")

    world.setBlock(4, 72, 4, WATERC)
    world.scheduleTick(4, 72, 4, Int(B.water), 1)
    for _ in 0..<200 { world.tick() }
    checkStage("water")

    world.setBlock(6, 73, 6, LAVAC)
    world.scheduleTick(6, 73, 6, Int(B.lava), 1)
    for _ in 0..<400 { world.tick() }
    checkStage("lava")

    world.setBlock(4, 70, 4, 0)
    for _ in 0..<10 { world.tick() }
    checkStage("untorch")

    world.setBlock(4, 69, 4, 0)
    world.setBlock(4, 68, 4, 0)
    for _ in 0..<600 { world.tick() }
    checkStage("drain")

    let p1 = world.rng.nextInt(1000000007), p2 = world.rng.nextInt(1000000007)
    if wsRegold {
        for path in goldenPaths("worldsim-goldens.json") {
            guard let d = FileManager.default.contents(atPath: path),
                  var obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { continue }
            obj["stages"] = wsCaptured
            obj["rngProbe"] = [p1, p2]
            obj["time"] = world.time
            obj["dayTime"] = world.dayTime
            if let out = try? JSONSerialization.data(withJSONObject: obj) {
                writeGolden(path, out)
                print("    REGENERATED worldsim stages (\(wsCaptured.count)) -> \(path)")
            }
            break
        }
        check("worldsim: goldens regenerated (native baseline)", true)
    } else {
        let wantProbe = (g["rngProbe"] as! [NSNumber]).map { $0.intValue }
        check("world rng state in lockstep", p1 == wantProbe[0] && p2 == wantProbe[1],
              "got \(p1),\(p2) want \(wantProbe[0]),\(wantProbe[1])")
        check("world time/dayTime", world.time == (g["time"] as! NSNumber).intValue
              && world.dayTime == (g["dayTime"] as! NSNumber).intValue)
    }
} else {
    check("worldsim-goldens.json loadable", false, "not found — run from the repo root (goldens/)")
}

// ---------------------------------------------------------------------------
section("items: recipes/enchants/potions/loot (vs goldens)")
registerAllRecipes()
registerAllLootTables()

if let g = loadJSON("items-goldens.json") {
    // a snapshot of every recipe, enchantment, effect, potion and loot table:
    // each value is checked against the golden, or captured under --regold items
    let regold = regolding("items")
    var got: [String: Any] = [:]
    func snap(_ key: String, _ value: Any, _ label: String) {
        got[key] = value
        if regold { return }
        let want = g[key]
        let same = (value as AnyObject).isEqual(want)
        check(label, same, same ? "" : "got \(value) want \(want ?? "nothing")")
    }
    func h(_ s: String) -> NSNumber { NSNumber(value: hashString(s)) }

    let craftSer = craftingRecipes.map { r -> String in
        switch r {
        case .shaped(let w, let h, let grid, let out, let count):
            return "S|\(w)|\(h)|\(grid.map { $0 ?? "." }.joined(separator: ","))|\(out)|\(count)"
        case .shapeless(let inputs, let out, let count):
            return "L|\(inputs.joined(separator: ","))|\(out)|\(count)"
        }
    }.joined(separator: ";")
    snap("craftCount", craftingRecipes.count, "crafting recipe count")
    snap("craftH", h(craftSer), "crafting recipes hash")
    let smeltSer = smeltingRecipes.map {
        "\($0.input)>\($0.output)|\(Int(($0.xp * 1000 + 0.5).rounded(.down)))|\($0.kind.rawValue)"
    }.joined(separator: ";")
    snap("smeltCount", smeltingRecipes.count, "smelting recipe count")
    snap("smeltH", h(smeltSer), "smelting recipes hash")
    snap("cutCount", stonecuttingRecipes.count, "stonecutting recipe count")
    snap("cutH", h(stonecuttingRecipes.map { "\($0.input)>\($0.output)x\($0.count)" }.joined(separator: ";")), "stonecutting recipes hash")
    snap("smithCount", smithingRecipes.count, "smithing recipe count")
    snap("smithH", h(smithingRecipes.map { "\($0.template)+\($0.base)+\($0.addition)>\($0.output)" }.joined(separator: ";")), "smithing recipes hash")
    snap("tagsH", h(TAGS.keys.sorted().map { "\($0):\(TAGS[$0]!.joined(separator: ","))" }.joined(separator: ";")), "tags hash")
    snap("trimMaterials", TRIM_MATERIALS.joined(separator: ","), "trim materials")

    // enchantments: definitions, power windows, and which items each applies to
    snap("enchCount", ENCHANTMENTS.count, "enchantment count")
    let enchEntries: [[String: Any]] = ENCHANTMENTS.map { e in
        var s = "\(e.id)|\(e.maxLevel)|\(e.weight)|\(e.target.rawValue)|\(e.treasure ? 1 : 0)|\(e.curse ? 1 : 0)|\(e.tradeable ? 1 : 0)|\(e.exclusiveGroup ?? "-")"
        for l in 1...e.maxLevel { s += "|\(e.minPower(l))..\(e.maxPower(l))" }
        let applies = itemDefs.map { appliesTo(e, $0) ? "1" : "0" }.joined()
        return ["id": e.id, "h": h(s), "applies": h(applies)]
    }
    snap("enchEntries", enchEntries, "\(ENCHANTMENTS.count) enchantment defs, power windows and appliesTo")
    snap("compatH", h(ENCHANTMENTS.map { a in ENCHANTMENTS.map { b in compatible(a, b) ? "1" : "0" }.joined() }.joined(separator: "|")),
         "compatibility matrix hash")
    snap("enchabilityH", h(itemDefs.map { "\($0.name):\(enchantability($0))" }.joined(separator: ";")), "enchantability hash")

    // effects / potions / brewing
    snap("effectsCount", EFFECTS.count, "effect count")
    snap("effectsH", h(EFFECTS.map { "\($0.id)|\($0.displayName)|\($0.color)|\($0.beneficial ? 1 : 0)|\($0.instant ? 1 : 0)" }.joined(separator: ";")),
         "effects hash")
    snap("potionsCount", POTIONS.count, "potion count")
    snap("potionsH", h(POTIONS.map { p in
        "\(p.id)|\(p.displayName)|\(p.color)|\(p.effects.map { "\($0.effect):\($0.duration):\($0.amplifier)" }.joined(separator: ","))"
    }.joined(separator: ";")), "potions hash")
    snap("brewCount", BREW_RECIPES.count, "brew recipe count")
    snap("brewH", h(BREW_RECIPES.map { "\($0.base)+\($0.ingredient)>\($0.result)" }.joined(separator: ";")), "brew recipes hash")

    // loot tables — 40 rolls per table, full stack serialization
    func serStack(_ s: ItemStack) -> String {
        var str = "\(itemDef(s.id).name)x\(s.count)"
        if !s.ench.isEmpty { str += "e[\(s.ench.map { "\($0.id):\($0.lvl)" }.joined(separator: ","))]" }
        if let pot = s.data.potion { str += "p[\(pot)]" }
        return str
    }
    let loot: [[String: Any]] = allLootTables().map { name in
        var rng = RandomX(hashString(name))
        var parts: [String] = []
        for _ in 0..<40 {
            for s in rollLoot(name, &rng) { parts.append(serStack(s)) }
            parts.append(";")
        }
        return ["name": name, "h": h(parts.joined(separator: "|"))]
    }
    snap("lootTables", loot, "\(loot.count) loot tables × 40 rolls")

    // enchantStackRandomly probes (raw strings, so a diff is readable)
    var probes: [String] = []
    for item in ["diamond_sword", "book", "fishing_rod", "diamond_chestplate", "diamond_pickaxe", "bow", "iron_boots", "diamond_hoe"] {
        for lvl in [1, 5, 10, 15, 20, 25, 30, 39, 50] {
            var rng = RandomX(hashString("\(item)/\(lvl)"))
            let s = enchantStackRandomly(ItemStack(iid(item), 1), &rng, lvl)
            probes.append("\(item)@\(lvl)=\(itemDef(s.id).name):\(s.ench.map { "\($0.id):\($0.lvl)" }.joined(separator: ","))")
        }
    }
    snap("enchProbes", probes, "\(probes.count) enchant-randomly probes")

    if regold, let path = goldenPaths("items-goldens.json").first(where: { FileManager.default.fileExists(atPath: $0) }),
       let data = try? JSONSerialization.data(withJSONObject: got) {
        writeGolden(path, data)
        check("items: snapshot regenerated", true)
    }
} else {
    check("items-goldens.json loadable", false, "not found — run from the repo root (goldens/)")
}

// ---------------------------------------------------------------------------
section("portable fdlibm math (vs fmath goldens)")

if let g = loadJSON("fmath-goldens.json") {
    func hexD(_ x: Double) -> String {
        String(x.bitPattern >> 32, radix: 16) + "-" + String(x.bitPattern & 0xffff_ffff, radix: 16)
    }
    func parseHex(_ s: Substring) -> Double {
        let parts = s.split(separator: "-")
        let h = UInt64(parts[0], radix: 16)!
        let l = UInt64(parts[1], radix: 16)!
        return Double(bitPattern: (h << 32) | l)
    }
    let probes = g["probes"] as! [String]
    var okCount = 0, badCount = 0
    for p in probes {
        let io = p.split(separator: ":")
        let ins = io[0].split(separator: ",")
        let outs = io[1].split(separator: ",")
        if ins.count == 1 {
            let x = parseHex(ins[0])
            let ws = parseHex(outs[0]), wc = parseHex(outs[1])
            if detSin(x).bitPattern == ws.bitPattern && detCos(x).bitPattern == wc.bitPattern { okCount += 1 }
            else {
                badCount += 1
                if badCount <= 3 { print("    sin/cos(\(x)): got \(hexD(detSin(x))),\(hexD(detCos(x))) want \(outs)") }
            }
        } else {
            let y = parseHex(ins[0]), x = parseHex(ins[1])
            let w = parseHex(outs[0])
            if detAtan2(y, x).bitPattern == w.bitPattern { okCount += 1 }
            else {
                badCount += 1
                if badCount <= 3 { print("    atan2(\(y),\(x)): got \(hexD(detAtan2(y, x))) want \(outs[0])") }
            }
        }
    }
    check("\(probes.count) fdlibm sin/cos/atan2 probes bit-identical", badCount == 0, "\(badCount) mismatches")
} else {
    check("fmath-goldens.json loadable", false, "not found")
}

// ---------------------------------------------------------------------------
section("entities: zoo/combat/physics/trades/pathfinding/spawning (vs goldens)")
registerAllEntities()
let wingsuitGeometry = buildEntityGeometry("wingsuit")
let wingsuitU = stride(from: 6, to: wingsuitGeometry.verts.count, by: 9).map { wingsuitGeometry.verts[$0] }
check("third-person wingsuit layer has two rendered wings",
      hasModel("wingsuit") && wingsuitGeometry.partNames == ["wingR", "wingL"] &&
      wingsuitGeometry.vertexCount > 0 &&
      (wingsuitU.min() ?? 0) >= 22.0 / 64.0 &&
      wingsuitGeometry.model.packTex == ["entity/elytra.png"])

if let g = loadJSON("entity-goldens.json") {
    func hex(_ x: Double) -> String {
        String(x.bitPattern >> 32, radix: 16) + "-" + String(x.bitPattern & 0xffff_ffff, radix: 16)
    }
    func num(_ k: String) -> Int { (g[k] as! NSNumber).intValue }
    func hash32(_ k: String) -> UInt32 { UInt32(truncating: g[k] as! NSNumber) }

    check("entity type count", entityTypes().count == num("entityTypeCount"),
          "got \(entityTypes().count) want \(num("entityTypeCount"))")
    let typesH = hashString(entityTypes().joined(separator: ",")), spawnH = hashString(spawnableMobs().joined(separator: ","))
    if regolding("entity"), let path = goldenPaths("entity-goldens.json").first(where: { FileManager.default.fileExists(atPath: $0) }),
       let d = FileManager.default.contents(atPath: path), var obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] {
        obj["entityTypeCount"] = entityTypes().count
        obj["entityTypesH"] = NSNumber(value: typesH)
        obj["spawnableH"] = NSNumber(value: spawnH)
        if let out = try? JSONSerialization.data(withJSONObject: obj) { writeGolden(path, out) }
    } else {
        check("entity registration order", typesH == hash32("entityTypesH"))
        check("spawnable mob list", spawnH == hash32("spawnableH"))
    }

    func buildWorld() -> World {
        let world = World(dim: .overworld, seed: 12345)
        for cz in -2...2 {
            for cx in -2...2 {
                let out = generateChunk(.overworld, 12345, cx, cz)
                let light = computeLocalLight(blocks: out.blocks, height: WORLD_H, hasSky: true)
                let c = Chunk(cx: cx, cz: cz, minY: GEN_MIN_Y, height: WORLD_H)
                c.blocks = out.blocks
                c.skyLight = light.sky
                c.blockLight = light.blk
                c.biomes = out.biomes
                c.buildHeightmap()
                c.scanSpecials()
                c.status = .generated
                world.setChunk(c)
            }
        }
        for cz in -2...2 {
            for cx in -2...2 {
                world.light.stitchChunk(world.getChunk(cx, cz)!)
            }
        }
        return world
    }

    func serMob(_ e: Entity, _ i: Int) -> String {
        var s = "\(e.type)#\(i):\(hex(e.x)),\(hex(e.y)),\(hex(e.z)),\(hex(e.vx)),\(hex(e.vy)),\(hex(e.vz)),\(hex(e.yaw))"
        s += ",og\(e.onGround ? 1 : 0),w\(e.inWater ? 1 : 0),a\(e.age),f\(e.fireTicks)"
        if let liv = e as? LivingEntity { s += ",h\(hex(liv.health))" }
        return s
    }

    func stepWorld(_ world: World) {
        world.tick()
        tickPendingTimeouts(world)
        for e in world.entities { (e as? Entity)?.tick() }
        for e in world.entities where e.dead {
            world.removeEntity(e)
        }
    }

    func determinize(_ e: Entity, _ i: Int) {
        e.persistent = true
        if let m = e as? LivingEntity { m.rng = RandomX(hashString("\(e.type)#\(i)")) }
        if let sheep = e as? Sheep { sheep.color = i % 16; sheep.sheared = false }
        if let chicken = e as? Chicken { chicken.eggTime = 99999 }
        if e is Parrot { e.data.variant = i % 5 }
        if e is Frog { e.data.variant = i % 3 }
        if e is Axolotl { e.data.variant = i % 4 }
        if let z = e as? Zombie {
            z.baby = false; z.speed = 0.095
            if let d = z as? Drowned { d.hasTrident = false }
        }
        if let slime = e as? Slime { slime.setSize(2) }
        if let h = e as? HorseBase { h.jumpStrength = 0.7; h.speed = 0.2; h.maxHealth = 26; h.health = 26 }
        if let l = e as? Llama { l.maxHealth = 22; l.health = 22; l.data.variant = i % 4 }
        if let v = e as? Vex { v.lifeTicks = 99999 }
        if let d = e as? RiftDragon { d.pathAngle = 1.25 }
    }

    // --- A) zoo
    let ZOO = ["cow", "mushcow", "pig", "sheep", "chicken", "rabbit", "wolf", "cat", "fox", "parrot",
               "bee", "axolotl", "frog", "goat", "turtle", "dolphin", "squid", "bat", "polar_bear", "panda",
               "strider", "camel", "sniffer", "allay", "cod", "villager", "iron_golem", "snow_golem", "horse", "llama",
               "zombie", "skeleton", "fizzler", "spider", "slime", "witch", "riftwalker", "silverfish", "phantom", "guardian",
               "lurker", "pillager", "vindicator", "conjurer", "vex", "cinder", "wailer", "magma_cube", "rotting_snouter", "snouter",
               "tusker", "blight_skeleton", "warden", "blight", "rift_dragon"]
    resetGameRng(hashString("zoo"))
    let zooWorld = buildWorld()
    zooWorld.dayTime = 13000
    var zooMobs: [Entity] = []
    for i in 0..<ZOO.count {
        let sx = -20 + (i % 8) * 6
        let sz = -20 + (i / 8) * 6
        let sy = zooWorld.surfaceY(sx, sz)
        let e = spawnMob(zooWorld, ZOO[i], Double(sx) + 0.5, Double(sy), Double(sz) + 0.5, SpawnOpts())!
        determinize(e, i)
        zooMobs.append(e)
    }
    func diffSer(_ label: String, _ got: String, _ want: String) -> Bool {
        if got == want { return true }
        let gParts = got.split(separator: "|", omittingEmptySubsequences: false)
        let wParts = want.split(separator: "|", omittingEmptySubsequences: false)
        for i in 0..<min(gParts.count, wParts.count) where gParts[i] != wParts[i] {
            print("    \(label) first diff @\(i):\n      got \(gParts[i])\n      want \(wParts[i])")
            return false
        }
        print("    \(label) length mismatch: got \(gParts.count) want \(wParts.count)")
        return false
    }

    // native baseline since entity-pushing landed (regenerate with
    // PEBBLE_REGOLD=1 after deliberate entity-behavior changes)
    let zooGold = g["zooStages"] as! [[String: Any]]
    let zooRegold = regolding("entity")
    var zooCaptured: [[String: Any]] = []
    var zooIdx = 0
    var zooOK = true
    for t in 1...200 {
        stepWorld(zooWorld)
        if t == 50 || t == 120 || t == 200 {
            let ser = zooMobs.enumerated().map { serMob($0.element, $0.offset) }.joined(separator: "|")
            if zooRegold {
                zooCaptured.append(["ser": ser, "t": t])
            } else {
                let want = zooGold[zooIdx]["ser"] as! String
                if !diffSer("zoo t=\(t)", ser, want) { zooOK = false }
            }
            zooIdx += 1
        }
    }
    if zooRegold {
        for path in goldenPaths("entity-goldens.json") {
            guard let d = FileManager.default.contents(atPath: path),
                  var obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { continue }
            obj["zooStages"] = zooCaptured
            if let out = try? JSONSerialization.data(withJSONObject: obj) {
                writeGolden(path, out)
                print("    REGENERATED zooStages (\(zooCaptured.count) checkpoints) -> \(path)")
            }
            break
        }
        check("zoo: golden regenerated (native baseline)", true)
    } else {
        check("zoo: 55 mob types × 200 ticks bit-identical (3 checkpoints)", zooOK)
    }

    // --- B) combat
    resetGameRng(hashString("combat"))
    let combatWorld = buildWorld()
    combatWorld.dayTime = 13000
    let cPlayer = Player(world: combatWorld)
    let py = combatWorld.surfaceY(0, 0)
    cPlayer.setPos(0.5, Double(py), 0.5)
    cPlayer.rng = RandomX(hashString("player"))
    combatWorld.addEntity(cPlayer)
    var combatants: [Entity] = [cPlayer]
    let CMOBS = ["zombie", "spider", "slime", "vex", "iron_golem"]
    for i in 0..<CMOBS.count {
        let ang = Double(i) / Double(CMOBS.count) * .pi * 2
        let sx = ifloor(0.5 + cos(ang) * 10)
        let sz = ifloor(0.5 + sin(ang) * 10)
        let sy = combatWorld.surfaceY(sx, sz)
        let e = spawnMob(combatWorld, CMOBS[i], Double(sx) + 0.5, Double(sy), Double(sz) + 0.5, SpawnOpts())!
        determinize(e, 100 + i)
        combatants.append(e)
    }
    // contains the player → native baseline since the vanilla-physics change
    // (regenerate with PEBBLE_REGOLD=1 after deliberate physics changes)
    let combatGold = g["combatStages"] as! [[String: Any]]
    let combatRegold = regolding("entity")
    var combatCaptured: [[String: Any]] = []
    var combatIdx = 0
    var combatOK = true
    for t in 1...150 {
        stepWorld(combatWorld)
        cPlayer.travel()
        if t == 50 || t == 100 || t == 150 {
            var ser = combatants.enumerated().map { serMob($0.element, $0.offset) }.joined(separator: "|")
            ser += "|hunger\(cPlayer.hunger),sat\(hex(cPlayer.saturation)),exh\(hex(cPlayer.exhaustion)),dead\(cPlayer.dead ? 1 : 0)"
            if combatRegold {
                combatCaptured.append(["t": t, "ser": ser])
            } else {
                let want = combatGold[combatIdx]["ser"] as! String
                if !diffSer("combat t=\(t)", ser, want) { combatOK = false }
            }
            combatIdx += 1
        }
    }
    if combatRegold {
        for path in goldenPaths("entity-goldens.json") {
            guard let d = FileManager.default.contents(atPath: path),
                  var obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { continue }
            obj["combatStages"] = combatCaptured
            if let out = try? JSONSerialization.data(withJSONObject: obj) {
                writeGolden(path, out)
                print("    REGENERATED combatStages (\(combatCaptured.count) checkpoints) -> \(path)")
            }
            break
        }
        check("combat: golden regenerated (vanilla baseline)", true)
    } else {
        check("combat: player + 5 mobs, damage/knockback in lockstep", combatOK)
    }

    // --- C) player physics
    resetGameRng(hashString("phys"))
    let physWorld = buildWorld()
    physWorld.dayTime = 13000
    let pPlayer = Player(world: physWorld)
    let ppy = physWorld.surfaceY(4, 4)
    pPlayer.setPos(4.5, Double(ppy), 4.5)
    pPlayer.rng = RandomX(hashString("physplayer"))
    physWorld.addEntity(pPlayer)
    // player physics is vanilla-exact since task #21 — this golden is a NATIVE
    // regression baseline now (regenerate with PEBBLE_REGOLD=1 after deliberate
    // physics changes) — these are native baselines, regenerated deliberately
    let physGold = g["physStages"] as! [[String: Any]]
    let regold = regolding("entity")
    var physCaptured: [[String: Any]] = []
    var physIdx = 0
    var physOK = true
    for t in 1...200 {
        pPlayer.moveForward = 0; pPlayer.moveStrafe = 0
        pPlayer.jumping = false; pPlayer.sprinting = false; pPlayer.sneaking = false
        if t <= 40 { pPlayer.moveForward = 1 }
        else if t <= 60 { pPlayer.moveForward = 1; pPlayer.jumping = true }
        else if t <= 100 { pPlayer.moveStrafe = 1 }
        else if t <= 140 { pPlayer.moveForward = 1; pPlayer.sprinting = true; pPlayer.jumping = t % 10 == 0 }
        else if t <= 160 { pPlayer.moveForward = 1; pPlayer.sneaking = true; pPlayer.yaw = 0.8 }
        physWorld.tick()
        pPlayer.tick()
        pPlayer.travel()
        if t % 20 == 0 {
            let s = "\(hex(pPlayer.x)),\(hex(pPlayer.y)),\(hex(pPlayer.z)),\(hex(pPlayer.vx)),\(hex(pPlayer.vy)),\(hex(pPlayer.vz)),og\(pPlayer.onGround ? 1 : 0),fall\(hex(pPlayer.fallDistance)),h\(hex(pPlayer.health))"
            if regold {
                physCaptured.append(["t": t, "s": s])
            } else {
                let want = physGold[physIdx]["s"] as! String
                if s != want {
                    physOK = false
                    print("    phys t=\(t):\n      got \(s)\n      want \(want)")
                }
            }
            physIdx += 1
        }
    }
    if regold {
        for path in goldenPaths("entity-goldens.json") {
            guard let d = FileManager.default.contents(atPath: path),
                  var obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { continue }
            obj["physStages"] = physCaptured
            if let out = try? JSONSerialization.data(withJSONObject: obj) {
                writeGolden(path, out)
                print("    REGENERATED physStages (\(physCaptured.count) checkpoints) -> \(path)")
            }
            break
        }
        check("player physics: golden regenerated (vanilla baseline)", true)
    } else {
        check("player physics: 200 scripted-input ticks vs native baseline", physOK)
    }

    // --- D) trades
    resetGameRng(hashString("trades"))
    let tradeWorld = buildWorld()
    var tradeOK = true
    let tradeGold = g["tradeProbes"] as! [String]
    var tg = 0
    for prof in PROFESSIONS {
        for lvl in 1...5 {
            let v = createEntity("villager", tradeWorld) as! Villager
            v.profession = prof
            v.tradeLevel = lvl
            v.rng = RandomX(hashString("\(prof)/\(lvl)"))
            v.refreshTrades()
            let ser = v.offers.map { o -> String in
                var s = "\(o.buyA.id)x\(o.buyA.count)"
                if let b = o.buyB { s += "+\(b.id)x\(b.count)" }
                s += ">\(o.sell.id)x\(o.sell.count)"
                if !o.sell.ench.isEmpty { s += "e[\(o.sell.ench.map { "\($0.id):\($0.lvl)" }.joined(separator: ","))]" }
                return s
            }.joined(separator: ";")
            let got = "\(prof)@\(lvl)=\(ser)"
            if got != tradeGold[tg] {
                tradeOK = false
                print("    trade \(prof)@\(lvl):\n      got \(got)\n      want \(tradeGold[tg])")
            }
            tg += 1
        }
    }
    check("\(tradeGold.count) villager trade tables byte-identical", tradeOK)

    // --- E) pathfinding (terrain-dependent: regold rewrites with the rest)
    resetGameRng(hashString("paths"))
    let pathWorld = buildWorld()
    let pathGold = g["pathProbes"] as! [String]
    var pathOK = true
    var pathCaptured: [String] = []
    for i in 0..<8 {
        let fx = -24 + i * 6, fz = -18 + i * 4
        let tx = fx + 10 - (i % 3) * 7, tz = fz + 8 - (i % 4) * 5
        let p = findPath(pathWorld, Double(fx) + 0.5, Double(pathWorld.surfaceY(fx, fz)), Double(fz) + 0.5,
                         Double(tx) + 0.5, Double(pathWorld.surfaceY(tx, tz)), Double(tz) + 0.5)
        let got = p == nil ? "null" : p!.map { "\($0.x),\($0.y),\($0.z)" }.joined(separator: ";")
        pathCaptured.append(got)
        if !regold, got != pathGold[i] {
            pathOK = false
            print("    path[\(i)]:\n      got \(got.prefix(120))\n      want \(pathGold[i].prefix(120))")
        }
    }
    if regold {
        for path in goldenPaths("entity-goldens.json") {
            guard let d = FileManager.default.contents(atPath: path),
                  var obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { continue }
            obj["pathProbes"] = pathCaptured
            if let out = try? JSONSerialization.data(withJSONObject: obj) {
                writeGolden(path, out)
                print("    REGENERATED pathProbes (8)")
            }
            break
        }
        check("A* paths: golden regenerated (native baseline)", true)
    } else {
        check("8 A* paths node-identical", pathOK)
    }

    // --- F) natural spawning
    resetGameRng(hashString("spawn"))
    let spawnWorld = buildWorld()
    spawnWorld.dayTime = 13000
    let sPlayer = Player(world: spawnWorld)
    sPlayer.setPos(0.5, Double(spawnWorld.surfaceY(0, 0)), 0.5)
    spawnWorld.addEntity(sPlayer)
    var spawnRng = RandomX(hashString("natural"))
    for i in 0..<40 {
        spawnWorld.time = i * 400
        naturalSpawnTick(spawnWorld, [sPlayer], &spawnRng)
    }
    let spawnedSer = spawnWorld.entities
        .compactMap { $0 as? Entity }
        .filter { $0 !== sPlayer }
        .map { "\($0.type)@\(hex($0.x)),\(hex($0.y)),\(hex($0.z))" }
        .joined(separator: "|")
    // native baseline since the vanilla-1.20 spawn-light rework (regenerate
    // with PEBBLE_REGOLD=1 after deliberate spawning changes)
    if regolding("entity") {
        for path in goldenPaths("entity-goldens.json") {
            guard let d = FileManager.default.contents(atPath: path),
                  var obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { continue }
            obj["spawnCount"] = spawnWorld.entities.count - 1
            obj["spawnH"] = hashString(spawnedSer)
            if let out = try? JSONSerialization.data(withJSONObject: obj) {
                writeGolden(path, out)
                print("    REGENERATED spawnCount=\(spawnWorld.entities.count - 1) spawnH")
            }
            break
        }
        check("natural spawn: golden regenerated (native baseline)", true)
        check("natural spawn hash: golden regenerated", true)
    } else {
        check("natural spawn count", spawnWorld.entities.count - 1 == num("spawnCount"),
              "got \(spawnWorld.entities.count - 1) want \(num("spawnCount"))")
        check("natural spawn types+positions hash", hashString(spawnedSer) == hash32("spawnH"),
              "got \(hashString(spawnedSer)) want \(hash32("spawnH"))")
    }
} else {
    check("entity-goldens.json loadable", false, "not found — run from the repo root (goldens/)")
}

// ---------------------------------------------------------------------------
section("systems: crafting/BEs/sparkstone/explosion/interact/portals (vs goldens)")
// terrain-dependent systems goldens re-baseline under PEBBLE_REGOLD
let sysRegold = regolding("systems")
registerAllSystems()

if let g = loadJSON("systems-goldens.json") {
    func hex(_ x: Double) -> String {
        String(x.bitPattern >> 32, radix: 16) + "-" + String(x.bitPattern & 0xffff_ffff, radix: 16)
    }
    /// deterministic Number→string: integral doubles print without ".0"
    func detNum(_ x: Double) -> String {
        if x == x.rounded() && abs(x) < 1e15 { return String(Int(x)) }
        return String(x)
    }
    func buildWorld() -> World {
        let world = World(dim: .overworld, seed: 12345)
        for cz in -1...1 {
            for cx in -1...1 {
                let out = generateChunk(.overworld, 12345, cx, cz)
                let light = computeLocalLight(blocks: out.blocks, height: WORLD_H, hasSky: true)
                let c = Chunk(cx: cx, cz: cz, minY: GEN_MIN_Y, height: WORLD_H)
                c.blocks = out.blocks
                c.skyLight = light.sky
                c.blockLight = light.blk
                c.biomes = out.biomes
                c.buildHeightmap()
                c.scanSpecials()
                c.status = .generated
                world.setChunk(c)
            }
        }
        for cz in -1...1 { for cx in -1...1 { world.light.stitchChunk(world.getChunk(cx, cz)!) } }
        return world
    }
    func serStack(_ s: ItemStack?) -> String {
        guard let s else { return "-" }
        var str = "\(itemDef(s.id).name)x\(s.count)"
        if s.damage != 0 { str += "d\(s.damage)" }
        if !s.ench.isEmpty { str += "e[\(s.ench.map { "\($0.id):\($0.lvl)" }.joined(separator: ","))]" }
        if let p = s.data.potion { str += "p[\(p)]" }
        if let w = s.data.priorWork, w != 0 { str += "w\(w)" }
        if let t = s.data.trim { str += "t[\(t.pattern):\(t.material)]" }
        if let l = s.label { str += "l[\(l)]" }
        return str
    }
    func regionHash(_ world: World, _ x0: Int, _ y0: Int, _ z0: Int, _ x1: Int, _ y1: Int, _ z1: Int) -> UInt32 {
        var h: UInt32 = 2166136261
        for y in y0...y1 {
            for z in z0...z1 {
                for x in x0...x1 {
                    let c = world.getBlock(x, y, z)
                    h = (h ^ UInt32(c & 0xff)) &* 16777619
                    h = (h ^ UInt32(c >> 8)) &* 16777619
                }
            }
        }
        return h
    }
    func entsSer(_ world: World, _ skip: EntityRef? = nil) -> String {
        world.entities.filter { !($0 === skip) }
            .map { "\(($0 as? Entity)?.type ?? "?")@\(hex($0.x)),\(hex($0.y)),\(hex($0.z))" }
            .joined(separator: "|")
    }
    func stepWorld(_ world: World) {
        world.tick()
        tickPendingTimeouts(world)
        for e in world.entities { (e as? Entity)?.tick() }
        for e in world.entities where e.dead { world.removeEntity(e) }
    }
    var sysCaptured: [String: Any] = [:]
    /// a probe list: compared with goldens key `key`, or captured under --regold systems
    func cmpList(_ label: String, _ got: [String], _ key: String) {
        if sysRegold { sysCaptured[key] = got; return }
        let want = g[key] as! [String]
        var ok = got.count == want.count
        if ok {
            for (i, w) in want.enumerated() where got[i] != w {
                ok = false
                print("    \(label)[\(i)]:\n      got \(got[i])\n      want \(w)")
                break
            }
        } else {
            print("    \(label) count: got \(got.count) want \(want.count)")
        }
        check(label, ok)
    }

    // --- A) crafting probes
    func st(_ name: String, _ count: Int = 1) -> ItemStack { ItemStack(iid(name), count) }
    var craftGot: [String] = []
    let craftCases: [(String, Int, Int, [ItemStack?])] = [
        ("planks", 2, 2, [st("oak_log"), nil, nil, nil]),
        ("sticks", 2, 2, [st("oak_planks"), nil, st("oak_planks"), nil]),
        ("table", 2, 2, [st("oak_planks"), st("oak_planks"), st("oak_planks"), st("oak_planks")]),
        ("pick", 3, 3, [st("oak_planks"), st("oak_planks"), st("oak_planks"), nil, st("stick"), nil, nil, st("stick"), nil]),
        ("axe-mirrored", 3, 3, [nil, st("oak_planks"), st("oak_planks"), nil, st("stick"), st("oak_planks"), nil, st("stick"), nil]),
        ("tag-planks-chest", 3, 3, [st("birch_planks"), st("birch_planks"), st("birch_planks"), st("birch_planks"), nil, st("birch_planks"), st("birch_planks"), st("birch_planks"), st("birch_planks")]),
        ("shapeless-flint", 2, 2, [st("iron_ingot"), st("flint"), nil, nil]),
        ("no-match-extra", 3, 3, [st("oak_log"), st("stick"), nil, nil, nil, nil, nil, nil, nil]),
        ("torch", 2, 2, [st("coal"), nil, st("stick"), nil]),
        ("bread", 3, 3, [st("wheat"), st("wheat"), st("wheat"), nil, nil, nil, nil, nil, nil]),
    ]
    for (label, w, h, grid) in craftCases {
        let m = matchCrafting(grid, w, h)
        craftGot.append("\(label)=\(m != nil ? serStack(m!.out) : "null")")
    }
    cmpList("crafting grid probes", craftGot, "craftProbes")

    var smithGot: [String] = []
    smithGot.append("darksteel=\(serStack(matchSmithing(st("darksteel_upgrade"), st("diamond_sword"), st("darksteel_ingot"))))")
    smithGot.append("trim=\(serStack(matchSmithing(st("coast_armor_trim"), st("iron_chestplate"), st("emerald"))))")
    smithGot.append("bad=\(serStack(matchSmithing(st("darksteel_upgrade"), st("stone"), st("darksteel_ingot"))))")
    cmpList("smithing probes", smithGot, "smithProbes")

    // --- B) enchanting / anvil / grindstone
    var enchGot: [String] = []
    for (item, shelves, sd) in [("diamond_sword", 15, 777), ("book", 8, 1234), ("iron_pickaxe", 0, 42), ("diamond_chestplate", 15, 90210)] {
        let opts = enchantingOptions(st(item), shelves, sd)
        enchGot.append("\(item)@\(shelves)/\(sd)=" + opts.map { o in
            "L\(o.level):\(o.enchants.map { "\($0.id):\($0.lvl)" }.joined(separator: ","))"
        }.joined(separator: ";"))
    }
    cmpList("enchanting options", enchGot, "enchProbes")

    var anvilGot: [String] = []
    let sword = ItemStack(iid("diamond_sword"), 1, damage: 100)
    let sword2 = ItemStack(iid("diamond_sword"), 1, damage: 500, ench: [EnchInstance("sharpness", 3)])
    let book = ItemStack(iid("enchanted_book"), 1, ench: [EnchInstance("sharpness", 3), EnchInstance("knockback", 2)])
    let r1 = anvilCombine(sword, sword2, nil)
    anvilGot.append("combine=\(r1 != nil ? serStack(r1!.out) + "$\(r1!.cost)" : "null")")
    let r2 = anvilCombine(sword, book, nil)
    anvilGot.append("book=\(r2 != nil ? serStack(r2!.out) + "$\(r2!.cost)" : "null")")
    let r3 = anvilCombine(sword, ItemStack(iid("diamond"), 3), nil)
    anvilGot.append("repair=\(r3 != nil ? serStack(r3!.out) + "$\(r3!.cost)" : "null")")
    let r4 = anvilCombine(ItemStack(iid("iron_sword"), 1), nil, "Slicey")
    anvilGot.append("rename=\(r4 != nil ? serStack(r4!.out) + "$\(r4!.cost)" : "null")")
    let g1 = grindstoneResult(sword2, nil)
    anvilGot.append("grind=\(g1 != nil ? serStack(g1!.out) + "$\(g1!.xp)" : "null")")
    cmpList("anvil/grindstone probes", anvilGot, "anvilProbes")

    // --- C) BE timelines
    resetGameRng(hashString("be"))
    let beWorld = buildWorld()
    let bePy = beWorld.surfaceY(0, 0)
    let beBase = bePy + 20
    for dz in -3...3 { for dx in -3...3 { beWorld.setBlock(dx, beBase - 1, dz, Int(cell(B.stone))) } }
    beWorld.setBlock(0, beBase, 0, Int(cell(B.furnace, 0)))
    let fbe = makeFurnaceBE(0, beBase, 0, .furnace)
    var fitems = fbe.items!
    fitems[0] = ItemStack(iid("raw_iron"), 3)
    fitems[1] = ItemStack(iid("coal"), 2)
    fbe.items = fitems
    beWorld.setBlockEntity(fbe)
    beWorld.setBlock(0, beBase + 1, 0, Int(cell(B.hopper, 0)))
    let hbe = makeHopperBE(0, beBase + 1, 0)
    var hitems = hbe.items!
    hitems[0] = ItemStack(iid("raw_gold"), 2)
    hbe.items = hitems
    beWorld.setBlockEntity(hbe)
    beWorld.setBlock(2, beBase, 0, Int(cell(B.brewing_stand, 0)))
    let bbe = makeBrewingBE(2, beBase, 0)
    var bitems = bbe.items!
    var pd = StackData(); pd.potion = "awkward"
    bitems[0] = ItemStack(iid("potion"), 1, data: pd)
    bitems[3] = ItemStack(iid("cinder_powder"), 2)
    bitems[4] = ItemStack(iid("cinder_powder"), 2)
    bbe.items = bitems
    beWorld.setBlockEntity(bbe)
    var beGot: [String] = []
    for t in 1...450 {
        stepWorld(beWorld)
        if t == 100 || t == 250 || t == 450 {
            let f = "f:\((fbe.items ?? []).map(serStack).joined(separator: ",")):b\(fbe.burnTime ?? 0):c\(fbe.cookTime ?? 0):x\(detNum(fbe.xpBank ?? 0))"
            let h = "h:\((hbe.items ?? []).map(serStack).joined(separator: ",")):cd\(hbe.cooldown ?? 0)"
            let p = "p:\((bbe.items ?? []).map(serStack).joined(separator: ",")):bt\(bbe.brewTime ?? 0):fu\(bbe.fuel ?? 0)"
            beGot.append([f, h, p].joined(separator: "|"))
        }
    }
    cmpList("BE timelines (furnace/hopper/brewing)", beGot, "beStages")

    // --- D) sparkstone contraption
    resetGameRng(hashString("sparkstone"))
    let rsWorld = buildWorld()
    let rsBase = rsWorld.surfaceY(8, 8) + 20
    for dz in 0...8 { for dx in 0...12 { rsWorld.setBlock(8 + dx, rsBase - 1, 8 + dz, Int(cell(B.stone))) } }
    rsWorld.setBlock(8, rsBase, 8, Int(cell(B.lever, 0)))
    for i in 1...5 { rsWorld.setBlock(8 + i, rsBase, 8, Int(cell(B.sparkstone_wire, 0))) }
    rsWorld.setBlock(14, rsBase, 8, Int(cell(B.repeater, 3)))
    rsWorld.setBlock(15, rsBase, 8, Int(cell(B.sparkstone_wire, 0)))
    rsWorld.setBlock(16, rsBase, 8, Int(cell(B.sparkstone_lamp)))
    rsWorld.setBlock(11, rsBase, 9, Int(cell(B.piston, 3)))
    rsWorld.setBlock(11, rsBase, 10, Int(cell(B.stone)))
    rsWorld.setBlock(12, rsBase, 10, Int(cell(B.observer, 4)))
    func flip(_ on: Bool) {
        let c = rsWorld.getBlock(8, rsBase, 8)
        rsWorld.setBlock(8, rsBase, 8, Int(cell(B.lever, on ? (c & 7) | 8 : c & 7)))
        rsWorld.updateNeighbors(8, rsBase, 8)
        rsWorld.updateNeighbors(8, rsBase - 1, 8)
    }
    var rsGot: [UInt32] = []
    flip(true)
    for _ in 1...30 { stepWorld(rsWorld) }
    rsGot.append(regionHash(rsWorld, 6, rsBase - 2, 6, 20, rsBase + 2, 14))
    flip(false)
    for _ in 1...30 { stepWorld(rsWorld) }
    rsGot.append(regionHash(rsWorld, 6, rsBase - 2, 6, 20, rsBase + 2, 14))
    flip(true)
    for _ in 1...4 { stepWorld(rsWorld) }
    rsGot.append(regionHash(rsWorld, 6, rsBase - 2, 6, 20, rsBase + 2, 14))
    let rsWant = (g["sparkstoneStages"] as! [NSNumber]).map { UInt32(truncating: $0) }
    check("sparkstone contraption (lever/wire/repeater/piston/lamp/observer)", rsGot == rsWant,
          "got \(rsGot) want \(rsWant)")

    // Sticky retraction must move the entire slime adhesion set, not just the
    // one block directly in front of the piston.
    let adhesionWorld = buildWorld()
    adhesionWorld.randomTickSpeed = 0
    let ax = 20, az = 20, ay = adhesionWorld.surfaceY(ax, az) + 20
    adhesionWorld.setBlock(ax, ay, az, Int(cell(B.sticky_piston, Dir.east)))
    adhesionWorld.setBlock(ax + 1, ay, az, Int(cell(B.slime_block)))
    adhesionWorld.setBlock(ax + 1, ay + 1, az, Int(cell(B.stone)))
    adhesionWorld.setBlock(ax, ay - 1, az, Int(cell(B.sparkstone_block)))
    for _ in 0..<4 { stepWorld(adhesionWorld) }
    let adhesionExtended =
        adhesionWorld.getBlock(ax, ay, az) == Int(cell(B.sticky_piston, Dir.east | 8)) &&
        (adhesionWorld.getBlock(ax + 1, ay, az) >> 4) == Int(B.piston_head) &&
        (adhesionWorld.getBlock(ax + 2, ay, az) >> 4) == Int(B.slime_block) &&
        (adhesionWorld.getBlock(ax + 2, ay + 1, az) >> 4) == Int(B.stone)
    adhesionWorld.setBlock(ax, ay - 1, az, 0)
    for _ in 0..<4 { stepWorld(adhesionWorld) }
    let adhesionRetracted =
        adhesionWorld.getBlock(ax, ay, az) == Int(cell(B.sticky_piston, Dir.east)) &&
        (adhesionWorld.getBlock(ax + 1, ay, az) >> 4) == Int(B.slime_block) &&
        (adhesionWorld.getBlock(ax + 1, ay + 1, az) >> 4) == Int(B.stone) &&
        adhesionWorld.getBlock(ax + 2, ay, az) == 0 &&
        adhesionWorld.getBlock(ax + 2, ay + 1, az) == 0
    check("sticky piston retracts the full slime adhesion set",
          blockDefs[Int(B.piston)].piston == .normal && adhesionExtended && adhesionRetracted)

    // Pistons/fluids/mob griefing use World.breakBlockNaturally rather than the
    // player-breaking path; both halves of multipart blocks must still vanish.
    let multipartBreakWorld = buildWorld()
    multipartBreakWorld.randomTickSpeed = 0
    let mbx = 28, mbz = 28, mby = multipartBreakWorld.surfaceY(mbx, mbz) + 20
    multipartBreakWorld.setBlock(mbx, mby, mbz, Int(cell(B.white_bed, 3)))
    multipartBreakWorld.setBlock(mbx + 1, mby, mbz, Int(cell(B.white_bed, 7)))
    multipartBreakWorld.breakBlockNaturally(mbx, mby, mbz)
    let bedNaturalCleanup =
        multipartBreakWorld.getBlock(mbx, mby, mbz) == 0 &&
        multipartBreakWorld.getBlock(mbx + 1, mby, mbz) == 0
    multipartBreakWorld.setBlock(mbx, mby, mbz, Int(cell(B.oak_door, 0)))
    multipartBreakWorld.setBlock(mbx, mby + 1, mbz, Int(cell(B.oak_door, 8)))
    multipartBreakWorld.breakBlockNaturally(mbx, mby + 1, mbz)
    let doorNaturalCleanup =
        multipartBreakWorld.getBlock(mbx, mby, mbz) == 0 &&
        multipartBreakWorld.getBlock(mbx, mby + 1, mbz) == 0
    check("natural destruction cleans both door/bed halves",
          bedNaturalCleanup && doorNaturalCleanup)

    // --- E) random ticks
    resetGameRng(hashString("crops"))
    let cropWorld = buildWorld()
    let cropBase = cropWorld.surfaceY(-8, -8) + 20
    for dz in 0..<6 {
        for dx in 0..<6 {
            cropWorld.setBlock(-8 + dx, cropBase - 1, -8 + dz, Int(cell(B.farmland, 7)))
            cropWorld.setBlock(-8 + dx, cropBase, -8 + dz, Int(cell(B.wheat, 0)))
        }
    }
    cropWorld.randomTickSpeed = 40
    for _ in 1...400 { cropWorld.tick() }
    let cropGot = regionHash(cropWorld, -8, cropBase - 1, -8, -3, cropBase, -3)
    if sysRegold {
        sysCaptured["cropHash"] = NSNumber(value: cropGot)
        check("crop growth: golden regenerated", true)
    } else {
        check("crop growth via seeded random ticks", cropGot == UInt32(truncating: g["cropHash"] as! NSNumber),
              "got \(cropGot) want \(g["cropHash"]!)")
    }

    // --- F) explosion
    resetGameRng(hashString("boom"))
    let boomWorld = buildWorld()
    let bpx = 4, bpz = 4
    let bpy = boomWorld.surfaceY(bpx, bpz)
    let cow = spawnMob(boomWorld, "cow", Double(bpx) + 3.5, Double(bpy) + 1, Double(bpz) + 0.5, SpawnOpts())!
    (cow as? LivingEntity)?.rng = RandomX(hashString("boomcow"))
    cow.persistent = true
    explode(boomWorld, Double(bpx) + 0.5, Double(bpy) + 0.5, Double(bpz) + 0.5, 4, true, nil)
    let boomGot = regionHash(boomWorld, bpx - 8, bpy - 8, bpz - 8, bpx + 8, bpy + 8, bpz + 8)
    let boomEnts = hashString(entsSer(boomWorld))
    if sysRegold {
        sysCaptured["explosionHash"] = NSNumber(value: boomGot)
        sysCaptured["explosionEnts"] = NSNumber(value: boomEnts)
        check("explosion: goldens regenerated", true)
        check("explosion ents: goldens regenerated", true)
    } else {
        check("explosion crater bit-identical", boomGot == UInt32(truncating: g["explosionHash"] as! NSNumber),
              "got \(boomGot) want \(g["explosionHash"]!)")
        check("explosion entity state (knockback + drops)", boomEnts == UInt32(truncating: g["explosionEnts"] as! NSNumber),
              "got \(boomEnts) want \(g["explosionEnts"]!)")
    }

    // --- G) interact
    resetGameRng(hashString("interact"))
    let iWorld = buildWorld()
    let iPlayer = Player(world: iWorld)
    let ipy = iWorld.surfaceY(0, -10)
    iPlayer.setPos(0.5, Double(ipy), -9.5)
    iPlayer.rng = RandomX(hashString("iplayer"))
    iWorld.addEntity(iPlayer)
    let ictx = InteractCtx(world: iWorld, player: iPlayer)
    func giveP(_ name: String, _ count: Int = 1) { iPlayer.inventory[iPlayer.selectedSlot] = ItemStack(iid(name), count) }
    func mkHit(_ x: Int, _ y: Int, _ z: Int, _ face: Int) -> RaycastHit {
        RaycastHit(x: x, y: y, z: z, face: face, cell: iWorld.getBlock(x, y, z), t: 0,
                   px: Double(x) + 0.5, py: Double(y) + (face == 1 ? 1 : 0.5), pz: Double(z) + 0.5)
    }
    var iGot: [String] = []
    let ibx = 0, ibz = -14
    let iby = iWorld.surfaceY(ibx, ibz)
    iPlayer.yaw = 0
    giveP("oak_stairs", 4)
    iGot.append("stairs=\(placeBlock(ictx, mkHit(ibx, iby - 1, ibz, 1), Int(itemDef(iPlayer.mainHand!.id).block!), iPlayer.mainHand!))@\(String(iWorld.getBlock(ibx, iby, ibz), radix: 16))")
    giveP("oak_door", 2)
    iGot.append("door=\(placeBlock(ictx, mkHit(ibx + 2, iby - 1, ibz, 1), Int(itemDef(iPlayer.mainHand!.id).block!), iPlayer.mainHand!))@\(String(iWorld.getBlock(ibx + 2, iby, ibz), radix: 16)),\(String(iWorld.getBlock(ibx + 2, iby + 1, ibz), radix: 16))")
    iGot.append("doorUse=\(useBlock(ictx, mkHit(ibx + 2, iby, ibz, 3)))@\(String(iWorld.getBlock(ibx + 2, iby, ibz), radix: 16))")
    giveP("white_bed")
    iGot.append("bed=\(placeBlock(ictx, mkHit(ibx + 4, iby - 1, ibz, 1), Int(itemDef(iPlayer.mainHand!.id).block!), iPlayer.mainHand!))@\(String(iWorld.getBlock(ibx + 4, iby, ibz), radix: 16))")
    giveP("torch", 4)
    iGot.append("torch=\(placeBlock(ictx, mkHit(ibx, iby, ibz - 2, 3), Int(itemDef(iPlayer.mainHand!.id).block!), iPlayer.mainHand!))")
    giveP("iron_pickaxe")
    finishBreaking(ictx, ibx, iby, ibz)
    iWorld.setBlock(ibx + 6, iby - 1, ibz, Int(cell(B.farmland, 7)))
    iWorld.setBlock(ibx + 6, iby, ibz, Int(cell(B.wheat, 0)))
    iGot.append("bonemeal=\(applyBonemeal(iWorld, ibx + 6, iby, ibz))@\(String(iWorld.getBlock(ibx + 6, iby, ibz), radix: 16))")
    giveP("golden_apple")
    _ = useItem(ictx, nil)
    finishUsingItem(ictx)
    iGot.append("ate=h\(iPlayer.hunger),s\(hex(iPlayer.saturation)),fx\(iPlayer.effects.map { "\($0.id):\($0.duration):\($0.amplifier)" }.joined(separator: ";"))")
    let iEnts = hashString(entsSer(iWorld, iPlayer))
    let iRegion = regionHash(iWorld, ibx - 2, iby - 2, ibz - 4, ibx + 8, iby + 2, ibz + 2)
    if sysRegold {
        sysCaptured["interactProbes"] = iGot
        sysCaptured["interactEnts"] = NSNumber(value: iEnts)
        sysCaptured["interactRegion"] = NSNumber(value: iRegion)
        check("interact: goldens regenerated", true)
        check("interact ents: goldens regenerated", true)
        check("interact region: goldens regenerated", true)
    } else {
        cmpList("interact probes (place/use/break/bonemeal/eat)", iGot, "interactProbes")
        check("interact entity drops", iEnts == UInt32(truncating: g["interactEnts"] as! NSNumber),
              "got \(iEnts) want \(g["interactEnts"]!)")
        check("interact region blocks", iRegion == UInt32(truncating: g["interactRegion"] as! NSNumber),
              "got \(iRegion) want \(g["interactRegion"]!)")
    }

    // --- H) portal
    let pWorld = buildWorld()
    let ppy2 = pWorld.surfaceY(-12, 12) + 25
    for dy in 0..<5 {
        for dx in 0..<4 {
            let frame = dy == 0 || dy == 4 || dx == 0 || dx == 3
            pWorld.setBlock(-12 + dx, ppy2 + dy, 12, frame ? Int(cell(B.obsidian)) : 0)
        }
    }
    let pok = tryIgnitePortal(pWorld, -11, ppy2 + 1, 12)
    let pGot = "\(pok)@\(regionHash(pWorld, -13, ppy2 - 1, 11, -8, ppy2 + 5, 13))"
    if sysRegold {
        sysCaptured["portal"] = pGot
        check("portal: golden regenerated", true)
    } else {
        check("nether portal frame ignition", pGot == (g["portal"] as! String),
              "got \(pGot) want \(g["portal"]!)")
    }
    if sysRegold, !sysCaptured.isEmpty {
        for path in goldenPaths("systems-goldens.json") {
            guard let d = FileManager.default.contents(atPath: path),
                  var obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { continue }
            for (k, v) in sysCaptured { obj[k] = v }
            if let out = try? JSONSerialization.data(withJSONObject: obj) {
                writeGolden(path, out)
                print("    REGENERATED systems keys: \(sysCaptured.keys.sorted().joined(separator: ", "))")
            }
            break
        }
    }
} else {
    check("systems-goldens.json loadable", false, "not found")
}


// ---------------------------------------------------------------------------
section("vanilla player physics constants (independent derivations)")
do {
    // flat stone slab world — equilibrium measurements need perfectly flat ground
    func flatWorld(_ topBlock: UInt16 = 0) -> (World, Int) {
        let world = World(dim: .overworld, seed: 1)
        let groundY = 64
        for cz in -2...2 {
            for cx in -2...2 {
                let c = Chunk(cx: cx, cz: cz, minY: GEN_MIN_Y, height: WORLD_H)
                var blocks = [UInt16](repeating: 0, count: 16 * 16 * WORLD_H)
                let stone = cell(B.stone)
                for y in 0...(groundY - GEN_MIN_Y) {
                    for i in 0..<256 {
                        blocks[y * 256 + i] = y == groundY - GEN_MIN_Y && topBlock != 0 ? cell(topBlock) : stone
                    }
                }
                c.blocks = blocks
                c.skyLight = [UInt8](repeating: 15, count: blocks.count)
                c.blockLight = [UInt8](repeating: 0, count: blocks.count)
                c.buildHeightmap()
                c.scanSpecials()
                c.status = .lit
                world.setChunk(c)
            }
        }
        return (world, groundY + 1)
    }
    func mkPlayer(_ world: World, _ gy: Int) -> Player {
        let p = Player(world: world)
        p.setPos(0.5, Double(gy), 0.5)
        p.rng = RandomX(7)
        world.addEntity(p)
        // settle onto the ground
        for _ in 0..<5 { p.tick(); p.travel() }
        return p
    }
    func runTicks(_ p: Player, _ n: Int, forward: Double = 0, strafe: Double = 0,
                  jump: Bool = false, sprint: Bool = false, sneak: Bool = false) {
        for _ in 0..<n {
            p.moveForward = forward; p.moveStrafe = strafe
            p.jumping = jump; p.sprinting = sprint; p.sneaking = sneak
            p.tick()
            p.travel()
        }
    }

    // 1) WALK equilibrium: v* = a/(1-f), a = 0.98·speed·0.216…/slip³, f = slip·0.91
    do {
        let (w, gy) = flatWorld()
        let p = mkPlayer(w, gy)
        runTicks(p, 150, forward: 1)
        let z0 = p.z
        runTicks(p, 1, forward: 1)
        let perTick = p.z - z0
        let a = 0.98 * 0.1 * (0.21600002 / (0.6 * 0.6 * 0.6))
        let expect = a / (1 - 0.6 * 0.91)
        check("walk speed = \(String(format: "%.4f", perTick * 20)) b/s (vanilla 4.317)",
              abs(perTick - expect) < 1e-9 && abs(perTick * 20 - 4.317) < 0.001,
              "got \(perTick) want \(expect)")
    }
    // 2) SPRINT equilibrium (×1.3) → 5.612 b/s
    do {
        let (w, gy) = flatWorld()
        let p = mkPlayer(w, gy)
        runTicks(p, 150, forward: 1, sprint: true)
        let z0 = p.z
        runTicks(p, 1, forward: 1, sprint: true)
        let perTick = p.z - z0
        let a = 0.98 * 0.13 * (0.21600002 / 0.216)
        let expect = a / (1 - 0.546)
        check("sprint speed = \(String(format: "%.4f", perTick * 20)) b/s (vanilla 5.612)",
              abs(perTick - expect) < 1e-9 && abs(perTick * 20 - 5.612) < 0.001)
    }
    // 3) SNEAK (input ×0.3) → 1.295 b/s
    do {
        let (w, gy) = flatWorld()
        let p = mkPlayer(w, gy)
        runTicks(p, 150, forward: 1, sneak: true)
        let z0 = p.z
        runTicks(p, 1, forward: 1, sneak: true)
        let perTick = p.z - z0
        let a = 0.3 * 0.98 * 0.1 * (0.21600002 / 0.216)
        let expect = a / (1 - 0.546)
        check("sneak speed = \(String(format: "%.4f", perTick * 20)) b/s (vanilla 1.295)",
              abs(perTick - expect) < 1e-9 && abs(perTick * 20 - 1.295) < 0.001)
    }
    // 4) JUMP apex — independent recurrence: y += v; v = (v−0.08)·0.98 from 0.42
    do {
        let (w, gy) = flatWorld()
        let p = mkPlayer(w, gy)
        let y0 = p.y
        var apex = 0.0
        for t in 0..<30 {
            runTicks(p, 1, jump: t == 0)
            apex = max(apex, p.y - y0)
        }
        var ev = 0.42, ey = 0.0, eApex = 0.0
        for _ in 0..<30 {
            ey += ev
            eApex = max(eApex, ey)
            ev = (ev - 0.08) * 0.98
        }
        check("jump apex = \(String(format: "%.4f", apex)) (vanilla 1.2522)",
              abs(apex - eApex) < 1e-9 && abs(apex - 1.2522) < 0.001,
              "got \(apex) want \(eApex)")
    }
    // 5) SPRINT-JUMP: boosted arc lands ~12 ticks, covers vanilla-ish ~3.8-4.4 blocks
    do {
        let (w, gy) = flatWorld()
        let p = mkPlayer(w, gy)
        runTicks(p, 150, forward: 1, sprint: true)
        let z0 = p.z
        runTicks(p, 1, forward: 1, jump: true, sprint: true)
        var airTicks = 1
        while !p.onGround && airTicks < 30 {
            runTicks(p, 1, forward: 1, sprint: true)
            airTicks += 1
        }
        let dist = p.z - z0
        check("sprint-jump: \(String(format: "%.3f", dist)) blocks in \(airTicks) air ticks",
              dist > 3.5 && dist < 4.6 && airTicks >= 11 && airTicks <= 14)
    }
    // 6) FALL DAMAGE: 20-block drop
    do {
        let (w, gy) = flatWorld()
        let p = mkPlayer(w, gy)
        p.setPos(0.5, Double(gy + 20), 0.5)
        p.vx = 0; p.vy = 0; p.vz = 0
        p.onGround = false   // stale from the settle phase pre-teleport
        var t = 0
        while !p.onGround && t < 100 {
            runTicks(p, 1)
            t += 1
        }
        check("20-block fall: damage \(String(format: "%.1f", 20 - p.health)) (vanilla 17)",
              abs((20 - p.health) - 17) < 1.01)
    }
    // 7) WATER terminal sink velocity = −0.005/(1−0.8) = −0.025
    do {
        let (w, gy) = flatWorld()
        // water column (tall — the swim-up phase rises fast)
        for y in gy...(gy + 60) {
            w.setBlock(0, y, 0, Int(cell(B.water)), SET_SILENT)
        }
        let p = Player(world: w)
        p.setPos(0.5, Double(gy + 40), 0.5)
        p.rng = RandomX(7)
        w.addEntity(p)
        for _ in 0..<60 { p.tick(); p.travel() }
        check("water sink terminal vy = \(String(format: "%.4f", p.vy)) (vanilla −0.025)",
              abs(p.vy - (-0.025)) < 0.002)
        // swim up: vy += 0.04 then ×0.8 −0.005 → +0.135 terminal
        p.setPos(0.5, Double(gy + 8), 0.5)
        p.vy = 0
        for _ in 0..<50 {
            p.jumping = true
            p.tick()
            p.travel()
        }
        check("swim-up terminal vy = \(String(format: "%.4f", p.vy)) (vanilla +0.135)",
              abs(p.vy - 0.135) < 0.002)
    }
    // 8) ICE equilibrium: slip 0.98
    do {
        let (w, gy) = flatWorld(B.packed_ice)
        let p = mkPlayer(w, gy)
        runTicks(p, 150, forward: 1)
        let z0 = p.z
        runTicks(p, 1, forward: 1)
        let perTick = p.z - z0
        let slip = 0.98
        let a = 0.98 * 0.1 * (0.21600002 / (slip * slip * slip))
        let expect = a / (1 - slip * 0.91)
        check("ice glide = \(String(format: "%.3f", perTick * 20)) b/s",
              abs(perTick - expect) < 1e-6)
    }
}

section("infinity wipe")
do {
    let seed: UInt32 = 12345
    let gen = overworldGen(seed)
    let info = DIMS[Dim.overworld.rawValue]
    // a land chunk (same walk createWorld uses to pick a spawn)
    var lcx = 0, lcz = 0
    for r in 0..<40 {
        let tx = 8 + r * 40, tz = 8 + ((r * 13) % 7 - 3) * 40
        let bname = (BIOMES[Int(gen.surfaceBiomeAt(Double(tx), Double(tz)).rawValue)]?.name ?? "").lowercased()
        if gen.heightEstimate(Double(tx), Double(tz)) > info.seaLevel + 4 && !bname.contains("ocean") && !bname.contains("river") {
            lcx = floorDiv(tx, 16); lcz = floorDiv(tz, 16)
            break
        }
    }
    let orig = generateChunk(.overworld, seed, lcx, lcz).blocks
    var blocks = orig
    let zone = WipeZone(dim: 0, x: Double(lcx * 16 + 8), z: Double(lcz * 16 + 8), radius: WIPE_RADIUS)
    let changed = wipeChunkBlocks(&blocks, lcx, lcz, minY: info.minY, height: info.height, seed: seed, zone: zone)
    check("wipe changes a land chunk at the center", changed)
    var aboveClear = true, belowKept = true, cut = 0, estErr = 0, cols = 0
    for lz in 0..<16 {
        for lx in 0..<16 {
            let wx = lcx * 16 + lx, wz = lcz * 16 + lz
            let est = gen.refinedHeightEstimate(Double(wx), Double(wz))
            // natural top: highest solid block that isn't a tree, plant, snow or fluid
            var top = info.minY
            for y in stride(from: info.minY + info.height - 1, through: info.minY, by: -1) {
                let id = Int(orig[(y - info.minY) * 256 + lz * 16 + lx] >> 4)
                if id == 0 || isTreeOrPlant(id) || id == Int(B.water) || id == Int(B.lava) || id == Int(B.snow) { continue }
                top = y
                break
            }
            estErr += abs(top - est)
            // the cut uses the lower of the estimate and the real ground (fluids count as ground)
            var real = info.minY - 1
            for y in stride(from: info.minY + info.height - 1, through: info.minY, by: -1)
                where !isTreeOrPlant(Int(orig[(y - info.minY) * 256 + lz * 16 + lx] >> 4)) {
                real = y
                break
            }
            let keep = max(min(est, real) - WIPE_DEPTH, info.seaLevel)
            cols += 1
            for y in info.minY..<(info.minY + info.height) {
                let i = (y - info.minY) * 256 + lz * 16 + lx
                if y > keep && blocks[i] != 0 { aboveClear = false }
                if y <= keep && blocks[i] != orig[i] { belowKept = false }
                if blocks[i] != orig[i] { cut += 1 }
            }
        }
    }
    check("everything above the cut is air", aboveClear)
    check("nothing at or below the cut changes", belowKept)
    let meanErr = Double(estErr) / Double(cols)
    check("ground estimate tracks the real surface (mean off by \(String(format: "%.1f", meanErr)) blocks)", meanErr < 4)
    check("about \(WIPE_DEPTH)+ blocks per column cut (\(cut / 256) avg)", cut / 256 >= WIPE_DEPTH - 4)

    // a 30-tall stone tower someone built on the ground goes entirely
    do {
        var built = orig
        let est = gen.refinedHeightEstimate(Double(lcx * 16 + 8), Double(lcz * 16 + 8))
        let stone = UInt16(B.stone) << 4
        for y in (est + 1)...(est + 30) { built[(y - info.minY) * 256 + 8 * 16 + 8] = stone }
        _ = wipeChunkBlocks(&built, lcx, lcz, minY: info.minY, height: info.height, seed: seed, zone: zone)
        let towerLeft = ((est - WIPE_DEPTH + 1)...(est + 30)).contains { y in
            y > info.seaLevel && built[(y - info.minY) * 256 + 8 * 16 + 8] != 0
        }
        check("a tower built on the ground is erased with the land under it", !towerLeft)
    }

    // outside the radius: untouched
    var far = orig
    let farZone = WipeZone(dim: 0, x: Double(lcx * 16 + 8) + WIPE_RADIUS + 64, z: Double(lcz * 16 + 8), radius: WIPE_RADIUS)
    check("chunks past the radius are untouched",
          !wipeChunkBlocks(&far, lcx, lcz, minY: info.minY, height: info.height, seed: seed, zone: farZone) && far == orig)

    // the rim tapers: a column just inside the edge loses less ground than one at the center
    let rimZone = WipeZone(dim: 0, x: Double(lcx * 16 + 8) - (WIPE_RADIUS - 12), z: Double(lcz * 16 + 8), radius: WIPE_RADIUS)
    var rim = orig
    _ = wipeChunkBlocks(&rim, lcx, lcz, minY: info.minY, height: info.height, seed: seed, zone: rimZone)
    let rimCut = zip(rim, orig).filter { $0 != $1 }.count
    check("the rim cuts shallower than the center (\(rimCut / 256) vs \(cut / 256) per column)", rimCut < cut)

    // an ocean chunk: nothing at or below sea level moves
    var ocx = 0, ocz = 0, foundOcean = false
    outer: for r in 0..<200 {
        for (tx, tz) in [(r * 64, 0), (0, r * 64), (-r * 64, 0), (0, -r * 64)] {
            let bname = (BIOMES[Int(gen.surfaceBiomeAt(Double(tx), Double(tz)).rawValue)]?.name ?? "").lowercased()
            if bname.contains("ocean") && gen.heightEstimate(Double(tx), Double(tz)) < info.seaLevel - 8 {
                ocx = floorDiv(tx, 16); ocz = floorDiv(tz, 16); foundOcean = true
                break outer
            }
        }
    }
    if foundOcean {
        let oOrig = generateChunk(.overworld, seed, ocx, ocz).blocks
        var ocean = oOrig
        let oz = WipeZone(dim: 0, x: Double(ocx * 16 + 8), z: Double(ocz * 16 + 8), radius: WIPE_RADIUS)
        _ = wipeChunkBlocks(&ocean, ocx, ocz, minY: info.minY, height: info.height, seed: seed, zone: oz)
        let seaIdx = (info.seaLevel - info.minY + 1) * 256
        check("oceans keep their water and seabed", Array(ocean[0..<seaIdx]) == Array(oOrig[0..<seaIdx]))
    } else {
        check("found an ocean chunk to test", false)
    }

    // zones survive a save
    var z2 = zone
    z2.done = [chunkKey(1, 2), chunkKey(-3, 4)]
    let back = try? JSONDecoder().decode(WipeZone.self, from: JSONEncoder().encode(z2))
    check("wipe zones round-trip through JSON", back?.done == z2.done && back?.radius == z2.radius)
}

section("world wonders (/place eiffel_tower, stonehenge, colosseum, devils_tower)")
do {
    func capture(_ id: String) -> (pf: Prefab, n: (String) -> Int)? {
        guard let pf = capturePrefab(id, dim: 0, minY: -64, maxY: 320, biome: 1, variant: 0) else { return nil }
        var counts: [Int: Int] = [:]
        for (_, _, _, c) in pf.cells { counts[Int(c >> 4), default: 0] += 1 }
        return (pf, { counts[Int(bid($0))] ?? 0 })
    }
    func size(_ pf: Prefab) -> (w: Int, d: Int, h: Int) { (pf.x1 - pf.x0 + 1, pf.z1 - pf.z0 + 1, pf.y1 - PREFAB_GROUND) }
    if let (pf, n) = capture("eiffel_tower") {
        let sz = size(pf)
        check("eiffel_tower: ~150 tall on a 63-block square (\(sz.w)×\(sz.d), \(sz.h) tall)", sz.h >= 145 && sz.w == 63 && sz.d == 63)
        check("eiffel_tower: iron lattice, a ladder to the top room, a light on the spire",
              n("brown_terracotta") > 5000 && n("ladder") >= 125 && n("sea_lantern") == 1, "lattice \(n("brown_terracotta")), ladder \(n("ladder"))")
    } else { check("eiffel_tower captures", false) }
    if let (pf, n) = capture("stonehenge") {
        let sz = size(pf)
        check("stonehenge: henge and Avenue (\(sz.w)×\(sz.d))", sz.w >= 110 && sz.d >= 110)
        let sarsen = n("stone") + n("andesite") + n("tuff") + n("mossy_cobblestone")
        check("stonehenge: sarsens, lintels and bluestones",
              sarsen > 300 && n("smooth_stone") > 60 && n("cobbled_deepslate") + n("polished_deepslate") > 40,
              "sarsen \(sarsen), lintels \(n("smooth_stone"))")
    } else { check("stonehenge captures", false) }
    if let (pf, n) = capture("colosseum") {
        let sz = size(pf)
        check("colosseum: a 125×105 ellipse, 32 tall (\(sz.w)×\(sz.d), \(sz.h))", sz.w == 125 && sz.d >= 103 && sz.h >= 31)
        check("colosseum: travertine arcades, brick vaults, a planked arena",
              n("white_terracotta") > 10000 && n("bricks") > 2000 && n("spruce_planks") > 300,
              "travertine \(n("white_terracotta")), bricks \(n("bricks")), planks \(n("spruce_planks"))")
    } else { check("colosseum captures", false) }
    if let (pf, n) = capture("devils_tower") {
        let sz = size(pf)
        check("devils_tower: ~90 tall over a 100-block apron (\(sz.w)×\(sz.d), \(sz.h))", sz.h >= 85 && sz.w >= 100)
        check("devils_tower: basalt columns, fallen columns, pines",
              n("basalt") > 40000 && n("spruce_log") > 30, "basalt \(n("basalt")), spruce \(n("spruce_log"))")
    } else { check("devils_tower captures", false) }
}

section("town structures (/place city, small_school, large_school)")
do {
    func key(_ x: Int, _ y: Int, _ z: Int) -> Int64 { (Int64(x + 4096) << 40) | (Int64(y + 4096) << 20) | Int64(z + 4096) }
    func capture(_ id: String, _ variant: Int = 0) -> (Prefab, [Int64: UInt16])? {
        guard let pf = capturePrefab(id, dim: 0, minY: -64, maxY: 320, biome: 1, variant: variant) else { return nil }
        var m: [Int64: UInt16] = [:]
        for (x, y, z, c) in pf.cells { m[key(x, y, z)] = c }
        return (pf, m)
    }
    func count(_ m: [Int64: UInt16], _ name: String) -> Int {
        let id = bid(name)
        return m.values.filter { $0 >> 4 == id }.count
    }
    for (id, floors) in [("small_school", 1), ("large_school", 3)] {
        guard let (pf, m) = capture(id) else { check("\(id) captures", false); continue }
        check("\(id) captures", true)
        // each floor: two partition walls carrying a 6×2 board seen from both rooms
        check("\(id): \(floors) floor(s) of chalkboards", count(m, "black_concrete") == 24 * floors,
              "got \(count(m, "black_concrete"))")
        check("\(id): 4 classrooms per floor of desks", count(m, "oak_slab") == 48 * floors, "got \(count(m, "oak_slab"))")
        check("\(id): sign over the door", pf.blockEntities.contains { $0.kind == "sign" })
        if floors > 1 {
            let stairs = pf.cells.filter { $0.3 >> 4 == bid("stone_brick_stairs") }
            check("\(id): stair runs between every floor", stairs.count == (floors - 1) * 10, "got \(stairs.count)")
            // two blocks of headroom over every step
            let clear = stairs.allSatisfy { (x, y, z, _) in
                (1...2).allSatisfy { dy in
                    let c = m[key(x, y + dy, z)] ?? 0
                    return c == 0 || bid("stone_brick_stairs") == c >> 4
                }
            }
            check("\(id): headroom over every stair", clear)
        }
    }
    if let (pf, m) = capture("city") {
        check("city captures (\(pf.x1 - pf.x0 + 1) wide, \(pf.y1 - PREFAB_GROUND) tall)",
              pf.x1 - pf.x0 + 1 == 107 && pf.y1 - PREFAB_GROUND > 40)
        check("city has streets, crosswalks and lit floors",
              count(m, "gray_concrete") > 3000 && count(m, "white_concrete") > 100 && count(m, "sea_lantern") > 100)
        check("city buildings have ladders to the roof", count(m, "ladder") > 200)
    } else {
        check("city captures", false)
    }
    // a different variant lays the city out differently
    if let (_, a) = capture("city", 0), let (_, b) = capture("city", 7) {
        check("city variants differ", a.count != b.count || a != b)
    }
}

// ---------------------------------------------------------------------------
section("analog movement and creative dig (touch / controller input)")
do {
    // a real GameCore on a scratch profile: the stick path must move the
    // player exactly like the keys, and stay inert when unset
    let home = NSTemporaryDirectory() + "pebsmoke-\(getpid())"
    setenv("PEBBLE_HOME", home, 1)
    defer {
        try? FileManager.default.removeItem(atPath: home)
        unsetenv("PEBBLE_HOME")
    }
    /// settle a fresh creative world's player on the ground
    func settled() -> GameCore? {
        let g = GameCore()
        g.createWorld(name: "smoke", seedText: "12345", mode: GameMode.creative, difficulty: 0)
        var grounded = 0
        let deadline = Date().addingTimeInterval(30)
        while grounded < 20 {
            if Date() > deadline { return nil }
            _ = g.frame(dtMs: 50)
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
            grounded = g.player.onGround ? grounded + 1 : 0
        }
        return g
    }
    /// settle, apply `input`, walk 30 ticks
    func walk(_ input: (GameCore) -> Void) -> (dx: Double, dz: Double)? {
        guard let g = settled() else { return nil }
        let x0 = g.player.x, z0 = g.player.z
        input(g)
        for _ in 0..<30 { _ = g.frame(dtMs: 50) }
        let d = (g.player.x - x0, g.player.z - z0)
        g.exitToTitle()
        return d
    }
    let fwd = DEFAULT_KEYBINDS["forward"]!
    // (now: 0 would read as a double-tap sprint against lastForwardPress = 0)
    if let keys = walk({ $0.keyDown(fwd, now: 100_000) }),
       let stick = walk({ $0.analogMove = (1, 0) }),
       let idle = walk({ $0.analogMove = (0, 0) }),
       let none = walk({ _ in }) {
        check("forward key walks the player", hypot(keys.dx, keys.dz) > 1, "moved \(keys)")
        check("full stick forward == forward key",
              abs(keys.dx - stick.dx) < 1e-9 && abs(keys.dz - stick.dz) < 1e-9, "keys \(keys) stick \(stick)")
        check("centered stick and no stick both stand still",
              hypot(idle.dx, idle.dz) < 1e-9 && hypot(none.dx, none.dz) < 1e-9, "idle \(idle) none \(none)")
    } else {
        check("analog movement world loads", false)
    }

    // creative dig delay: looking straight down, count ticks until the block
    // underfoot is gone (nil = still there after `limit`)
    func ticksToBreak(_ delay: Double?, interrupt: Int? = nil, limit: Int = 30) -> Int?? {
        guard let g = settled() else { return .none }
        defer { g.exitToTitle() }
        g.settings.creativeBreakDelay = delay
        let p = g.player!
        p.pitch = .pi / 2 - 0.01
        let bx = Int(floor(p.x)), by = Int(floor(p.y)) - 1, bz = Int(floor(p.z))
        let id = g.world.getBlockId(bx, by, bz)
        g.mouseDown(0)
        for t in 1...limit {
            if t == interrupt { g.mouseUp(0); g.mouseDown(0) }   // let go, press again
            _ = g.frame(dtMs: 50)
            if g.world.getBlockId(bx, by, bz) != id { return .some(t) }
        }
        return .some(nil)
    }
    if case .some(let instant) = ticksToBreak(0),
       case .some(let erode) = ticksToBreak(0.4),
       case .some(let regrip) = ticksToBreak(0.4, interrupt: 6) {
        check("creative dig 0 breaks on the first tick", instant == 1, "\(String(describing: instant))")
        check("creative dig 0.4 s takes 8 ticks", erode == 8, "\(String(describing: erode))")
        check("letting go restarts the erode", regrip == 6 + 8 - 1, "\(String(describing: regrip))")
    } else {
        check("creative dig world loads", false)
    }

    // selection wand: left-click marks corner 1 without digging (even held),
    // right-click marks corner 2 without placing anything
    if let g = settled() {
        let p = g.player!, w = g.world
        p.pitch = .pi / 2 - 0.01
        p.inventory[p.selectedSlot] = ItemStack(iid("selection_wand"), 1)
        let bx = Int(floor(p.x)), by = Int(floor(p.y)) - 1, bz = Int(floor(p.z))
        let under = w.getBlock(bx, by, bz), above = w.getBlock(bx, by + 1, bz)
        g.mouseDown(0)
        for _ in 0..<20 { _ = g.frame(dtMs: 50) }
        g.mouseUp(0)
        check("wand left-click marks corner 1", p.selection?.a == BlockPos(bx, by, bz), "\(String(describing: p.selection))")
        check("wand left-click never digs, even held", w.getBlock(bx, by, bz) == under)
        g.mouseDown(2)
        for _ in 0..<10 { _ = g.frame(dtMs: 50) }
        g.mouseUp(2)
        check("wand right-click marks corner 2", p.selection?.b == BlockPos(bx, by, bz), "\(String(describing: p.selection))")
        check("wand right-click places nothing", w.getBlock(bx, by + 1, bz) == above && w.getBlock(bx, by, bz) == under)
        let line = setSelectionCorner(p, 2, BlockPos(bx + 2, by + 4, bz - 1))
        check("a selection reports its size and volume", line.hasSuffix("(3×5×2, 30 blocks)"), line)
        let top = w.info.minY + w.info.height - 1
        setSelectionCorner(p, 1, BlockPos(bx, 1_000_000, bz))
        check("a corner above the build limit is clamped to it", p.selection?.a?.y == top, "\(String(describing: p.selection))")
        p.selection = Selection(dim: .nether, a: BlockPos(0, 64, 0), b: BlockPos(5, 64, 5))
        setSelectionCorner(p, 1, BlockPos(bx, by, bz))
        check("a corner in another dimension starts a fresh selection", p.selection?.dim == w.dim && p.selection?.b == nil)
        g.exitToTitle()
    } else {
        check("selection wand world loads", false)
    }

    // clipboard: //copy, //cut and //paste (each one undo step)
    if let g = settled() {
        let p = g.player!, w = g.world
        // a 3×2×3 build floating over the player: a stone floor with a chest of
        // 5 diamonds in the middle of the layer above
        let bx = ifloor(p.x) + 4, by = ifloor(p.y) + 10, bz = ifloor(p.z)
        let stone = Int(cell(B.stone)), chestCell = Int(cell(B.chest))
        for dz in 0..<3 { for dx in 0..<3 { w.setBlock(bx + dx, by, bz + dz, stone) } }
        w.setBlock(bx + 1, by + 1, bz + 1, chestCell)
        let chest = makeContainerBE(bx + 1, by + 1, bz + 1, 27)
        chest.items![0] = ItemStack(iid("diamond"), 5)
        w.setBlockEntity(chest)
        p.selection = Selection(dim: w.dim, a: BlockPos(bx, by, bz), b: BlockPos(bx + 2, by + 1, bz + 2))
        let clip = try? copySelection(p, cut: false)
        check("//copy takes the box and the chest in it", clip?.volume == 18 && clip?.blockEntityCount == 1,
              "\(String(describing: clip?.volume)) \(String(describing: clip?.blockEntityCount))")

        // walk 10 east and paste: it lands 10 east of the original
        p.setPos(p.x + 10, p.y, p.z)
        let ox = bx + 10
        let r = try? pasteClipboard(p, skipAir: false)
        check("//paste keeps the offset from where you stand", r?.lo == BlockPos(ox, by, bz), "\(String(describing: r?.lo))")
        check("pasted blocks match the copy",
              w.getBlock(ox, by, bz) == stone && w.getBlock(ox + 2, by, bz + 2) == stone && w.getBlock(ox + 1, by + 1, bz + 1) == chestCell)
        let pasted = w.getBlockEntity(ox + 1, by + 1, bz + 1)
        check("the pasted chest gets its own copy of the items",
              pasted?.items?[0]?.count == 5 && pasted !== chest && pasted?.items?[0] !== chest.items![0])

        // paste again over the first paste: the blocks match, only the chest's contents differ
        pasted?.items?[0] = ItemStack(iid("emerald"), 3)
        _ = try? pasteClipboard(p, skipAir: false)
        check("pasting a chest over a chest replaces its contents",
              w.getBlockEntity(ox + 1, by + 1, bz + 1)?.items?[0]?.id == iid("diamond"))
        _ = undoLastEdit()
        check("undoing that paste brings back the chest it replaced",
              w.getBlockEntity(ox + 1, by + 1, bz + 1)?.items?[0]?.id == iid("emerald"))
        _ = undoLastEdit()
        check("undoing the first paste leaves air and no chest data",
              w.getBlock(ox, by, bz) == 0 && w.getBlock(ox + 1, by + 1, bz + 1) == 0 && w.getBlockEntity(ox + 1, by + 1, bz + 1) == nil)

        // -a: the clipboard's air (the top layer around the chest) leaves what's there
        let glass = Int(cell(B.glass))
        w.setBlock(ox, by + 1, bz, glass)
        _ = try? pasteClipboard(p, skipAir: true)
        check("//paste -a leaves blocks where the clipboard has air", w.getBlock(ox, by + 1, bz) == glass && w.getBlock(ox, by, bz) == stone)
        _ = undoLastEdit()
        w.setBlock(ox, by + 1, bz, 0)

        _ = try? copySelection(p, cut: true)
        check("//cut clears the box", w.getBlock(bx, by, bz) == 0 && w.getBlock(bx + 1, by + 1, bz + 1) == 0
              && w.getBlockEntity(bx + 1, by + 1, bz + 1) == nil)
        _ = undoLastEdit()
        let back = w.getBlockEntity(bx + 1, by + 1, bz + 1)
        check("undoing a cut brings back the chest and its items",
              w.getBlock(bx, by, bz) == stone && back?.items?[0]?.id == iid("diamond") && back?.items?[0]?.count == 5)

        p.selection = Selection(dim: w.dim, a: BlockPos(bx, by, bz), b: BlockPos(bx + 200, by + 30, bz + 200))
        var tooBig = false
        do { try copySelection(p, cut: false) } catch ClipboardError.tooBig { tooBig = true } catch {}
        check("a copy over the block limit is refused", tooBig)
        p.selection = nil
        check("//copy without a selection is refused", (try? copySelection(p, cut: false)) == nil)
        g.exitToTitle()
    } else {
        check("clipboard world loads", false)
    }

    // saves: a chest edited in place (no block change) in an already-saved
    // chunk must survive an unload + reload, and the untouched chunks around
    // it must not be rewritten when they're revisited
    if let g = settled() {
        g.settings.renderDistance = 4
        let w = g.world, p = g.player!
        let bx = Int(floor(p.x)) + 2, by = Int(floor(p.y)), bz = Int(floor(p.z))
        w.setBlock(bx, by, bz, Int(B.chest) << 4)
        let be = BlockEntityData(type: "chest", x: bx, y: by, z: bz)
        be.items = [ItemStack?](repeating: nil, count: 27)
        w.setBlockEntity(be)
        g.saveAndFlush(); g.waitForSaves()
        be.items![0] = ItemStack(iid("diamond"), 5)   // in place: the chunk isn't marked
        let key = chunkKey(floorDiv(bx, 16), floorDiv(bz, 16))
        let home = (p.x, p.y, p.z)
        func go(_ x: Double, until done: () -> Bool) -> Bool {
            p.setPos(x, 200, home.2); p.flying = true
            for _ in 0..<2000 {
                _ = g.frame(dtMs: 50)
                RunLoop.main.run(until: Date().addingTimeInterval(0.002))
                if done() { return true }
            }
            return false
        }
        let away = go(home.0 + 3000) { w.chunks[key] == nil }
        for _ in 0..<40 { _ = g.frame(dtMs: 50) }   // the once-a-second unload batch
        g.waitForSaves()
        let awayKey = chunkKey(floorDiv(Int(home.0) + 3000, 16), floorDiv(bz, 16))
        let back = go(home.0) { w.chunks[key] != nil && w.chunks[awayKey] == nil }
        // the land generated out there is saved in full as it unloads (every
        // generated chunk is kept); let that land, then watch home alone
        for _ in 0..<40 { _ = g.frame(dtMs: 50); RunLoop.main.run(until: Date().addingTimeInterval(0.002)) }
        g.waitForSaves()
        let fullBefore = g.db.fullChunkWrites
        for _ in 0..<60 { _ = g.frame(dtMs: 50); RunLoop.main.run(until: Date().addingTimeInterval(0.002)) }
        let kept: ItemStack? = w.getBlockEntity(bx, by, bz)?.items?[0] ?? nil
        check("chest edited in place survives unload + reload",
              away && back && kept?.id == iid("diamond") && kept?.count == 5,
              "away \(away) back \(back) slot0 \(String(describing: kept))")
        // revisiting writes nothing on its own (natural block changes may)
        g.waitForSaves()
        check("revisiting saved chunks doesn't rewrite them", g.db.fullChunkWrites - fullBefore < 5,
              "\(g.db.fullChunkWrites - fullBefore) full writes")
        g.exitToTitle()
    } else {
        check("save world loads", false)
    }
}

section("world spawn on dry land")
do {
    // the spawn search reads a terrain estimate, so a new world could start
    // its player on a lake or ocean floor (surfaceY looks through water)
    let home = NSTemporaryDirectory() + "pebsmoke-spawn-\(getpid())"
    setenv("PEBBLE_HOME", home, 1)
    defer {
        try? FileManager.default.removeItem(atPath: home)
        unsetenv("PEBBLE_HOME")
    }
    let g = GameCore()
    var wet: [Int] = []
    // 16 of 300 random seeds started underwater before; a few dry ones too
    let seeds = [-957389223, -570112306, -1675440399, 2140826113, -365683123, 1662125329,
                 -696457382, 78096452, 761226419, -879305116, -583452066, -822802458,
                 782807868, 930734393, -1963051760, -1279921793, 1, 2, 3, 12345]
    for seed in seeds {
        g.createWorld(name: "spawn", seedText: "\(seed)", mode: GameMode.survival, difficulty: 0)
        let p = g.player!
        let x = Int(p.x.rounded(.down)), y = Int(p.y.rounded(.down)), z = Int(p.z.rounded(.down))
        let feet = UInt16(truncatingIfNeeded: g.world.getBlock(x, y, z))
        let ground = g.world.getBlock(x, y - 1, z) >> 4
        if isWaterlogged(feet) || !blockDefs[ground].solid { wet.append(seed) }
        let id = g.worldRec!.id
        g.exitToTitle()
        g.deleteWorld(id)
    }
    check("\(seeds.count) new worlds start on dry ground", wet.isEmpty, "wet: seeds \(wet)")
}

// ---------------------------------------------------------------------------
section("untouched terrain stays put: leaves, loose ground")
do {
    // generated trees shed 2-3% of their leaves (canopy past the 6-block
    // reach) and water woken on chunk load collapsed cave gravel deposits:
    // ~100 sapling drops per 5 minutes around spawn, 1,000+ falling blocks
    // while exploring
    let home = NSTemporaryDirectory() + "pebsmoke-terrain-\(getpid())"
    setenv("PEBBLE_HOME", home, 1)
    defer {
        try? FileManager.default.removeItem(atPath: home)
        unsetenv("PEBBLE_HOME")
    }
    let g = GameCore()
    g.settings.renderDistance = 6
    g.createWorld(name: "terrain", seedText: "12345", mode: GameMode.creative, difficulty: 0)
    let w = g.worlds[.overworld]!
    var leafDrops = 0
    w.onLocalSpawn = { e in
        if let it = e as? ItemEntity {
            let n = itemDefs[it.stack.id].name
            if n.hasSuffix("_sapling") || n == "stick" || n == "apple" || n == "propagule" { leafDrops += 1 }
        }
        return true
    }
    w.randomTickSpeed = 30   // 10x: 600 ticks ≈ 5 minutes of play
    for _ in 0..<600 { _ = g.frame(dtMs: 50); RunLoop.main.run(until: Date().addingTimeInterval(0.002)) }
    check("untouched trees keep their leaves", leafDrops == 0, "\(leafDrops) leaf drops")

    // a tree in the sky: chopping its trunk still makes the canopy decay
    let tx = Int(g.player.x) + 3, tz = Int(g.player.z) + 3, base = 200
    let LOG = Int(cell(B.oak_log)), LEAF = Int(cell(B.oak_leaves))
    func leaves() -> Int {
        var n = 0
        for y in (base + 2)...(base + 6) { for z in (tz - 2)...(tz + 2) { for x in (tx - 2)...(tx + 2) where (w.getBlock(x, y, z) >> 4) == Int(B.oak_leaves) { n += 1 } } }
        return n
    }
    func plantTree() {
        for y in (base + 2)...(base + 5) { for z in (tz - 2)...(tz + 2) { for x in (tx - 2)...(tx + 2) where x != tx || z != tz { w.setBlock(x, y, z, LEAF) } } }
        for y in base...(base + 5) { w.setBlock(tx, y, tz, LOG) }
        w.setBlock(tx, base + 6, tz, LEAF)
    }
    plantTree()
    let full = leaves()
    w.randomTickSpeed = 300
    for _ in 0..<200 { _ = g.frame(dtMs: 50) }
    check("a tree with its trunk keeps its leaves", leaves() == full, "\(leaves()) of \(full)")
    for y in base...(base + 5) { w.setBlock(tx, y, tz, 0) }
    for _ in 0..<1500 { _ = g.frame(dtMs: 50) }
    check("a chopped tree's leaves decay", leaves() == 0, "\(leaves()) of \(full) left")
    w.randomTickSpeed = 3

    // gravel over air beside flowing water stays; water flowing in under it doesn't
    let gx = tx + 8, gy = base, gz = tz
    let STONE = Int(cell(B.stone)), GRAVEL = Int(cell(B.gravel))
    // a stone floor with a sealed one-block pocket under the gravel
    for z in (gz - 4)...(gz + 4) { for x in (gx - 4)...(gx + 4) {
        w.setBlock(x, gy - 2, z, STONE)
        if x != gx || z != gz { w.setBlock(x, gy - 1, z, STONE) }
    } }
    w.setBlock(gx, gy, gz, GRAVEL, SET_SILENT)          // a generated deposit over a "cave"
    w.setBlock(gx + 1, gy, gz, Int(cell(B.water, 0)))   // a spring beside it
    for _ in 0..<100 { _ = g.frame(dtMs: 50) }
    check("water flowing beside gravel over a cave leaves it", (w.getBlock(gx, gy, gz) >> 4) == Int(B.gravel))
    w.setBlock(gx + 1, gy - 1, gz, 0)                    // open the pocket: water runs in under it
    for _ in 0..<100 { _ = g.frame(dtMs: 50) }
    check("water flowing in under gravel still drops it", (w.getBlock(gx, gy, gz) >> 4) != Int(B.gravel))
    g.exitToTitle()
}

// ---------------------------------------------------------------------------
section("headlamp")
do {
    func st(_ n: String) -> ItemStack? { n.isEmpty ? nil : ItemStack(iid(n), 1) }
    let grid = ["", "lumenstone_dust", "", "leather", "iron_ingot", "leather", "", "", ""].map(st)
    let out = matchCrafting(grid, 3, 3)?.out
    check("lumenstone over iron, leather either side crafts a headlamp", out.map { itemDefs[$0.id].name } == "headlamp")
    check("it's worn on the head", itemDefs[iid("headlamp")].armor?.slot == 0)
    let home = NSTemporaryDirectory() + "pebsmoke-lamp-\(getpid())"
    setenv("PEBBLE_HOME", home, 1)
    defer {
        try? FileManager.default.removeItem(atPath: home)
        unsetenv("PEBBLE_HOME")
    }
    let g = GameCore()
    g.createWorld(name: "lamp", seedText: "12345", mode: GameMode.survival, difficulty: 2)
    let p = g.player!
    check("no headlamp, no light", !p.headlampOn)
    p.armor[0] = ItemStack(iid("headlamp"), 1)
    check("wearing one turns it on", p.headlampOn)
    for _ in 0..<200 { p.damageArmor(20) }
    check("it never wears out", p.armor[0]?.id == iid("headlamp"))
    g.exitToTitle()
}

// ---------------------------------------------------------------------------
section("code-review fixes")
do {
    let home = NSTemporaryDirectory() + "pebsmoke-review-\(getpid())"
    setenv("PEBBLE_HOME", home, 1)
    defer {
        try? FileManager.default.removeItem(atPath: home)
        unsetenv("PEBBLE_HOME")
    }
    let g = GameCore()
    g.createWorld(name: "review", seedText: "12345", mode: GameMode.survival, difficulty: 2)
    let w = g.world
    let p = g.player!
    func mob(_ type: String) -> LivingEntity {
        let e = createEntity(type, w) as! LivingEntity
        e.setPos(p.x + 3, p.y, p.z)
        return e
    }
    // long falls used to arrive as "fall_high", which no fall rule matched
    let chicken = mob("chicken")
    chicken.onLand(12)
    check("a chicken takes no damage from a 12-block fall", chicken.health == chicken.maxHealth)
    let zombie = mob("zombie")
    zombie.onLand(12)
    checkD("a zombie takes 9 from a 12-block fall", zombie.maxHealth - zombie.health, 9)
    p.armor[3] = ItemStack(iid("diamond_boots"), 1, ench: [EnchInstance("feather_falling", 4)])
    let before = p.health
    p.onLand(12)
    check("Feather Falling IV cuts a 12-block fall", before - p.health > 0 && before - p.health < 5,
          "took \(before - p.health)")
    p.armor[3] = nil
    check("death text: a long fall reads differently from a short one", deathCauseText("fall_high") == "took a long fall" && deathCauseText("fall") == "landed badly")
    check("death text names the attacker", deathCauseText("projectile", "Skeleton") == "took an arrow from Skeleton")
    // state that used to be lost on save and reload
    func reload(_ e: Entity) -> Entity { loadEntity(w, e.save())! }
    let slime = mob("slime") as! Slime
    slime.setSize(4)
    slime.health = 5
    let slime2 = reload(slime) as! Slime
    check("a slime keeps its size and health", slime2.size == 4 && slime2.health == 5)
    let strider = mob("strider") as! Strider
    strider.saddled = true
    check("a strider keeps its saddle", (reload(strider) as! Strider).saddled)
    let camel = mob("camel") as! Camel
    camel.saddled = true
    check("a camel keeps its saddle", (reload(camel) as! Camel).saddled)
    let vind = mob("vindicator") as! Vindicator
    vind.isCaptain = true
    check("a vindicator captain stays captain", (reload(vind) as! Vindicator).isCaptain)
    let bee = mob("bee") as! Bee
    bee.doMeleeAttack(zombie)
    check("a bee that stung is still doomed after a reload", (reload(bee) as! Bee).hasStung)
    let fizzler = mob("fizzler") as! Fizzler
    fizzler.charged = true
    check("a charged fizzler stays charged", (reload(fizzler) as! Fizzler).charged)
    // trees: leaves out of a log's reach (7+ steps) are never generated
    let treeSink = ArraySink(cx: 0, cz: 0, blocks: [UInt16](repeating: 0, count: 16 * 16 * WORLD_H),
                             minY: GEN_MIN_Y, maxY: GEN_MIN_Y + WORLD_H, heightFallback: { _, _ in 64 })
    placeTree(treeSink, prune: true) { s in
        s.set(2, 70, 2, cell(B.oak_log))
        for dx in 1...8 { s.set(2 + dx, 70, 2, cell(B.oak_leaves)) }   // a 1-wide arm, 8 long
    }
    check("leaves within 6 steps of the log stay", treeSink.get(8, 70, 2) >> 4 == Int(B.oak_leaves))
    check("leaves 7 or more steps out are pruned", treeSink.get(9, 70, 2) == 0 && treeSink.get(10, 70, 2) == 0)
    // furnaces: a blast furnace only takes ores, a smoker only food (vanilla)
    func smelts(_ item: String, _ k: FurnaceKind) -> String? { smeltResultFor(ItemStack(iid(item), 1), k)?.output }
    check("a furnace smelts sand, ore and food", smelts("sand", .furnace) == "glass" && smelts("raw_iron", .furnace) == "iron_ingot" && smelts("beef", .furnace) == "cooked_beef")
    check("a blast furnace smelts ore, not sand or food", smelts("raw_iron", .blast) == "iron_ingot" && smelts("sand", .blast) == nil && smelts("beef", .blast) == nil)
    check("a smoker cooks food only", smelts("beef", .smoker) == "cooked_beef" && smelts("raw_iron", .smoker) == nil)
    // anvil: vanilla's 40-level limit, with renames held at 39
    let worn = ItemStack(iid("iron_sword"), 1, damage: 100)
    worn.data.priorWork = 5
    let worn2 = worn.copy()
    let pricey = anvilCombine(worn, worn2, nil)
    check("a heavily reworked repair costs 40+ (Too Expensive)", (pricey?.cost ?? 0) >= ANVIL_TOO_EXPENSIVE, "cost \(pricey?.cost ?? -1)")
    let veteran = worn.copy()
    veteran.data.priorWork = 6   // 63 levels of prior-work penalty
    let rename = anvilCombine(veteran, nil, "Old Faithful")
    check("renaming it alone stays at 39", rename?.cost == 39, "cost \(rename?.cost ?? -1)")
    // stacks from a newer build or a bad LAN peer
    // stone is item 0: the old LAN check (id > 0) silently dropped stacks of it
    check("stone (item 0) is a known stack", ItemStack(iid("stone"), 1).isKnown)
    check("an unknown item id isn't", !ItemStack(itemDefs.count + 5, 1).isKnown)
    check("an unknown enchantment isn't", !ItemStack(iid("diamond_sword"), 1, ench: [EnchInstance("smite_2", 1)]).isKnown)
    check("knownStacks empties only the bad slot",
          knownStacks([ItemStack(iid("stone"), 1), ItemStack(9999, 1), nil]).map { $0 != nil } == [true, false, false])
    check("leather boots count as leather boots", { p.armor[3] = ItemStack(iid("leather_boots"), 1); defer { p.armor[3] = nil }; return p.wearsLeatherBoots }())
    // every generated chunk is saved, not just edited ones, so changes to
    // world generation can't reshape land a player has already seen
    g.saveAndFlush(synchronous: true)
    let rec = g.worldRec!
    let spawnKey = g.db.chunkKey(rec.id, 0, floorDiv(ifloor(p.x), 16), floorDiv(ifloor(p.z), 16))
    let spawnChunk = g.db.getChunk(rec.id, 0, floorDiv(ifloor(p.x), 16), floorDiv(ifloor(p.z), 16))
    check("an untouched chunk the player stood in is saved, blocks and all",
          g.db.getChunkKeys(rec.id).contains(spawnKey) && spawnChunk?.blocks != nil)
    check("a new world uses the current generator", rec.genVersion == GEN_VERSION && w.genVersion == GEN_VERSION)
    // a player's death records the high-fall wording
    p.health = 1
    p.invulnTicks = 0   // the Feather Falling check above just hurt it
    p.fallDistance = 20
    p.onLand(20)
    check("dying from a long fall records the long-fall cause", p.data.deathCause == "fall_high")
    // a world saved before 1.5 has no genVersion: it keeps generator 1
    var old = g.worldRec!
    g.exitToTitle()
    old = g.db.listWorlds().first { $0.id == old.id } ?? old
    old.genVersion = nil
    g.db.putWorld(old)
    g.loadWorld(old.id)
    check("a pre-1.5 world reopens on generator version 1", g.world.genVersion == 1)
    g.exitToTitle()
}

// ---------------------------------------------------------------------------
section("chunk saves (VCK1 plain, VCK2 compressed)")
do {
    let home = NSTemporaryDirectory() + "pebsmoke-db-\(getpid())"
    setenv("PEBBLE_HOME", home, 1)
    defer {
        try? FileManager.default.removeItem(atPath: home)
        unsetenv("PEBBLE_HOME")
    }
    let db = SaveDB()
    let gen = generateChunk(.overworld, 12345, 3, -2)
    func record(_ cx: Int) -> ChunkRecord {
        ChunkRecord(key: db.chunkKey("w", 0, cx, 0), worldId: "w", dim: 0, cx: cx, cz: 0,
                    blocks: gen.blocks, biomes: gen.biomes, blockEntities: [],
                    entities: [["type": "cow", "x": 1.5, "y": 70.0, "z": 2.5]])
    }
    func write(_ r: ChunkRecord, compressed: Bool) -> Int {
        db.compressChunks = compressed
        let before = db.chunkBytesWritten
        _ = db.putChunks([r])
        return db.chunkBytesWritten - before
    }
    let plainBytes = write(record(0), compressed: false)
    let zBytes = write(record(1), compressed: true)
    var stub = ChunkRecord(key: db.chunkKey("w", 0, 2, 0), worldId: "w", dim: 0, cx: 2, cz: 0)
    stub.entities = [["type": "sheep", "x": 33.0, "y": 64.0, "z": 1.0]]
    _ = write(stub, compressed: true)
    let a = db.getChunk("w", 0, 0, 0), b = db.getChunk("w", 0, 1, 0), c = db.getChunk("w", 0, 2, 0)
    check("plain record reads back", a?.blocks == gen.blocks && a?.biomes == gen.biomes && a?.entities.count == 1)
    check("compressed record reads back identical",
          b?.blocks == gen.blocks && b?.biomes == gen.biomes && (b?.entities.first?["type"] as? String) == "cow")
    check("compressed entity-only record reads back", c?.blocks == nil && (c?.entities.first?["type"] as? String) == "sheep")
    check("compressed full record is >10× smaller", zBytes * 10 < plainBytes, "\(plainBytes) → \(zBytes) bytes")
}

// ---------------------------------------------------------------------------
section("block/item palettes (a world from another build)")
do {
    let home = NSTemporaryDirectory() + "pebsmoke-pal-\(getpid())"
    setenv("PEBBLE_HOME", home, 1)
    defer {
        try? FileManager.default.removeItem(atPath: home)
        unsetenv("PEBBLE_HOME")
    }
    let db = SaveDB()
    // the "old build": stone and dirt swapped places, stone and diamond items
    // too, and each list ends with something this build doesn't have
    var old = Palette.current()
    let stoneB = Int(bid("stone")), dirtB = Int(bid("dirt"))
    old.blocks.swapAt(stoneB, dirtB)
    old.blocks.append("retired_block")
    let stoneI = iid("stone"), diamondI = iid("diamond")
    old.items.swapAt(stoneI, diamondI)
    old.items.append("retired_item")
    let oldStoneCell = UInt16(dirtB << 4 | 2), oldGoneCell = UInt16(old.blocks.count - 1) << 4
    let goneItem = old.items.count - 1
    func oldStack(_ id: Int) -> [String: Any] { ["id": id, "count": 3, "damage": 0, "ench": [], "data": [:]] }
    let chest = BlockEntityData(type: "chest", x: 1, y: 64, z: 1)
    chest.items = [ItemStack(diamondI, 5), ItemStack(goneItem, 1), nil]   // old ids: stone, then the gone item
    var blocks = [UInt16](repeating: 0, count: 16 * 16 * DIMS[0].height)
    blocks[0] = oldStoneCell; blocks[1] = oldGoneCell
    let rec = ChunkRecord(key: db.chunkKey("old", 0, 0, 0), worldId: "old", dim: 0, cx: 0, cz: 0,
                          blocks: blocks, biomes: [UInt8](repeating: 0, count: 4 * 4 * (DIMS[0].height / 4)),
                          blockEntities: [chest],
                          entities: [["type": "item", "x": 1.5, "y": 65.0, "z": 1.5, "stack": oldStack(diamondI)],
                                     ["type": "falling_block", "x": 2.5, "y": 70.0, "z": 2.5, "blockCell": Int(oldStoneCell)]])
    _ = db.putChunks([rec])
    db.putPlayer("old", ["dim": 0, "data": ["inventory": [oldStack(diamondI), oldStack(goneItem), NSNull()]]])
    db.putPlayer("old#guest:Bob", ["dim": 0, "data": ["inventory": [oldStack(stoneI)]]])   // old id of diamond
    db.putPalette("old", old)
    let remap = db.migratePalette("old")
    check("a world from another build is migrated", remap != nil && db.getPalette("old") == Palette.current())
    check("…and names what it couldn't keep", remap?.droppedBlocks == ["retired_block"] && remap?.droppedItems == ["retired_item"])
    let got = db.getChunk("old", 0, 0, 0)
    check("stone stays stone, meta kept", got?.blocks?[0] == UInt16(stoneB << 4 | 2))
    check("a block this build lacks becomes air", got?.blocks?[1] == 0)
    let gotChest = got?.blockEntities?.first
    check("chest items keep their identity; a gone item leaves an empty slot",
          gotChest?.items?.map { $0?.id } == [stoneI, nil, nil])
    let item = (got?.entities.first { $0["type"] as? String == "item" }?["stack"] as? [String: Any])?["id"] as? NSNumber
    check("an item on the ground keeps its identity", item?.intValue == stoneI)
    let fb = got?.entities.first { $0["type"] as? String == "falling_block" }?["blockCell"] as? NSNumber
    check("a falling block keeps its identity", fb?.intValue == stoneB << 4 | 2)
    let inv = (db.getPlayer("old")?["data"] as? [String: Any])?["inventory"] as? [Any]
    check("the player's inventory keeps its identity", ((inv?[0] as? [String: Any])?["id"] as? NSNumber)?.intValue == stoneI && inv?[1] is NSNull)
    let guestInv = (db.getPlayer("old#guest:Bob")?["data"] as? [String: Any])?["inventory"] as? [Any]
    check("LAN guests' saved players are migrated too", ((guestInv?[0] as? [String: Any])?["id"] as? NSNumber)?.intValue == diamondI)
    check("a second open changes nothing", db.migratePalette("old") == nil)
    // names in Java-format resource packs and in worlds saved before the renames
    check("pack names: Pebble names map to the format's texture names",
          packName("sparkstone_torch") == "red" + "stone_torch" && packName("stone") == "stone")
    check("older saves' names map to Pebble's", pebbleName("nether" + "ite_sword") == "darksteel_sword"
          && pebbleName("eye_of_" + "ender") == "rift_eye" && pebbleName("oak_log") == "oak_log")
    check("a world saved before palettes is translated to this build's names",
          db.migratePalette("prepalette") != nil && db.getPalette("prepalette") == Palette.current())
}

print("\n\(passed) passed, \(failed) failed")
exit(failed > 0 ? 1 : 0)
