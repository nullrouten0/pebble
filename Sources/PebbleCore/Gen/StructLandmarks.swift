// Landmark starter structures for /place — bigger showpieces than the kits in
// StructStarters.swift. Same convention: (x, y, z) is the north-west corner at
// ground level, y is the first air layer.

import Foundation

@inline(__always) private func C(_ b: UInt16, _ m: Int = 0) -> Int { Int(cell(b, m)) }
private let AIR = 0

/// a box of air with a 1-block shell; shells go down first so neighboring
/// rooms never wall each other off
private struct Carver {
    var rooms: [(Int, Int, Int, Int, Int, Int, Int)] = []
    mutating func room(_ x0: Int, _ y0: Int, _ z0: Int, _ x1: Int, _ y1: Int, _ z1: Int, _ shell: Int) {
        rooms.append((x0, y0, z0, x1, y1, z1, shell))
    }
    func carve(_ b: Builder) {
        for (x0, y0, z0, x1, y1, z1, sh) in rooms { b.fill(x0 - 1, y0 - 1, z0 - 1, x1 + 1, y1 + 1, z1 + 1, sh) }
        for (x0, y0, z0, x1, y1, z1, _) in rooms { b.fill(x0, y0, z0, x1, y1, z1, AIR) }
    }
}

// ---------------------------------------------------------------------------
// Great Pyramid: 101×101 stepped sandstone pyramid (51 tall) with a gold cap.
// The casing is stairs, so every face is walkable. Entrance on the north face,
// 10 up, framed in chiseled sandstone with lanterns.
//   descending passage → buried chamber 12 below ground (pit + chest)
//   junction → ascending passage → landing → Queen's chamber (+ treasury)
//                                         → Grand Gallery → King's chamber
// ---------------------------------------------------------------------------
func starterPyramid(_ b: Builder, _ x: Int, _ y: Int, _ z: Int) {
    let N = 101, K = N / 2
    let body = C(B.sandstone), smooth = C(B.smooth_sandstone), cut = C(B.cut_sandstone)
    let gold = C(B.gold_block), granite = C(B.polished_granite)
    // layers: k=0 is the ground platform, k≥1 the stepped body
    for k in 0...K {
        let yy = y + k - 1
        let lo = k, hi = N - 1 - k
        b.fill(x + lo, yy, z + lo, x + hi, yy, z + hi, k >= K - 3 ? gold : body)
        if k == 0 || k >= K - 3 || lo == hi { continue }
        for d in (lo + 1)..<hi {
            b.set(x + d, yy, z + lo, C(B.sandstone_stairs, 1)) // north face climbs south
            b.set(x + d, yy, z + hi, C(B.sandstone_stairs, 0))
            b.set(x + lo, yy, z + d, C(B.sandstone_stairs, 3))
            b.set(x + hi, yy, z + d, C(B.sandstone_stairs, 2))
        }
        for (cx, cz) in [(lo, lo), (hi, lo), (lo, hi), (hi, hi)] { b.set(x + cx, yy, z + cz, smooth) }
    }

    // local coords: u across (0 = center line), v from the north edge
    let cx = x + K
    func P(_ u: Int) -> Int { cx + u }
    func Q(_ v: Int) -> Int { z + v }
    var cv = Carver()

    // descending passage: 1 down per 1 south, from y+10 to y-12
    let entF = y + 10, lowF = y - 12
    let dSteps = entF - lowF
    for i in 0...dSteps { cv.room(P(-1), entF - i, Q(11 + i), P(1), entF - i + 3, Q(11 + i), body) }
    cv.room(P(-1), lowF, Q(12 + dSteps), P(1), lowF + 3, Q(45), body)            // lower corridor
    cv.room(P(-7), lowF, Q(46), P(7), lowF + 5, Q(56), body)                    // buried chamber
    cv.room(P(-1), lowF - 4, Q(50), P(1), lowF - 1, Q(52), body)                // the pit
    // junction off the descending passage, then the ascending passage
    let jF = y + 2
    cv.room(P(2), jF, Q(18), P(6), jF + 3, Q(20), body)
    let aStart = 21, aF0 = jF + 1
    let landF = y + 15
    for j in 0...(landF - aF0) { cv.room(P(4), aF0 + j, Q(aStart + j), P(6), aF0 + j + 3, Q(aStart + j), body) }
    let landV = aStart + (landF - aF0) + 1 // 34
    cv.room(P(-1), landF, Q(landV), P(8), landF + 3, Q(landV + 2), body)         // landing
    cv.room(P(-1), landF, Q(landV + 3), P(1), landF + 2, Q(45), body)           // Queen's passage
    cv.room(P(-5), landF, Q(46), P(5), landF + 4, Q(54), body)                  // Queen's chamber
    cv.room(P(-3), landF + 5, Q(47), P(3), landF + 5, Q(53), body)
    cv.room(P(-1), landF + 6, Q(48), P(1), landF + 6, Q(52), body)
    cv.room(P(-7), landF, Q(40), P(-2), landF + 2, Q(41), body)                 // side tunnel
    cv.room(P(-14), landF, Q(37), P(-8), landF + 3, Q(44), body)                // treasury
    // Grand Gallery: tall, narrowing toward the ceiling, rising 1 per 1
    let gV0 = landV + 3, kingF = y + 28
    let gLen = kingF - (landF + 1)
    for j in 0...gLen {
        let f = landF + 1 + j, v = gV0 + j
        cv.room(P(3), f, Q(v), P(7), f + 4, Q(v), body)
        cv.room(P(4), f + 5, Q(v), P(6), f + 7, Q(v), body)
        cv.room(P(5), f + 8, Q(v), P(5), f + 9, Q(v), body)
    }
    let kV = gV0 + gLen + 1
    cv.room(P(4), kingF, Q(kV), P(6), kingF + 2, Q(kV), body)                   // antechamber
    cv.carve(b)

    // King's chamber: polished granite box
    let k0 = kV + 1, k1 = k0 + 6
    b.fill(P(-3), kingF - 1, Q(k0 - 1), P(11), kingF + 6, Q(k1 + 1), granite)
    b.fill(P(-2), kingF, Q(k0), P(10), kingF + 5, Q(k1), AIR)
    b.fill(P(4), kingF, Q(k0 - 1), P(6), kingF + 2, Q(k0 - 1), AIR)
    // air shaft: 1×1, climbing south out through the casing
    var sv = k1 + 1, sy = kingF + 2
    while sv < N - 1 - (sy - y + 1) + 1 {
        b.set(P(4), sy, Q(sv), AIR)
        b.set(P(4), sy + 1, Q(sv), AIR)
        sv += 1; sy += 1
    }

    // stairs: the descending passage climbs north, the others climb south
    for i in 0...dSteps {
        let f = entF - i
        for u in -1...1 { b.set(P(u), f - 1, Q(11 + i), C(B.sandstone_stairs, 0)) }
    }
    for j in 0...(landF - aF0) {
        for u in 4...6 { b.set(P(u), aF0 + j - 1, Q(aStart + j), C(B.sandstone_stairs, 1)) }
    }
    for j in 0...gLen {
        let f = landF + 1 + j
        for u in 4...6 { b.set(P(u), f - 1, Q(gV0 + j), C(B.sandstone_stairs, 1)) }
        b.set(P(3), f, Q(gV0 + j), cut) // side ramps
        b.set(P(7), f, Q(gV0 + j), cut)
        if j % 3 == 1 { b.set(P(5), f + 9, Q(gV0 + j), C(B.lantern, 1)) }
    }

    // entrance frame on the north face
    let fv = 10
    for h in 0...4 {
        b.set(P(-2), entF + h, Q(fv), C(B.chiseled_sandstone))
        b.set(P(2), entF + h, Q(fv), C(B.chiseled_sandstone))
    }
    b.fill(P(-3), entF + 5, Q(fv), P(3), entF + 5, Q(fv), C(B.chiseled_sandstone))
    b.fill(P(-2), entF + 6, Q(fv), P(2), entF + 6, Q(fv), cut)
    b.fill(P(-1), entF, Q(fv), P(1), entF + 4, Q(fv), AIR)
    b.set(P(-3), entF, Q(fv), C(B.lantern))
    b.set(P(3), entF, Q(fv), C(B.lantern))
    // lanterns up the north face flank the climb to the door
    for i in stride(from: 1, to: 10, by: 3) {
        b.set(P(-2), y + i, Q(i), C(B.lantern))
        b.set(P(2), y + i, Q(i), C(B.lantern))
    }

    // lights along the passages
    for i in stride(from: 2, to: dSteps, by: 4) { b.set(P(0), entF - i + 3, Q(11 + i), C(B.lantern, 1)) }
    for v in stride(from: 12 + dSteps, through: 45, by: 4) { b.set(P(0), lowF + 3, Q(v), C(B.lantern, 1)) }
    for j in stride(from: 2, to: landF - aF0, by: 4) { b.set(P(5), aF0 + j + 3, Q(aStart + j), C(B.lantern, 1)) }
    b.set(P(0), landF + 3, Q(landV + 1), C(B.lantern, 1))
    b.set(P(5), jF + 3, Q(19), C(B.lantern, 1))

    // buried chamber: rough, webbed, a chest at the bottom of the pit
    for (u, v) in [(-7, 46), (7, 46), (-7, 56), (7, 56), (-6, 46), (6, 56)] { b.set(P(u), lowF + 5, Q(v), C(B.cobweb)) }
    for (u, v) in [(-6, 47), (6, 55)] { b.set(P(u), lowF, Q(v), C(B.lantern)) }
    kitChest(b, P(0), lowF - 4, Q(51), 0, "gold_ingot*12,emerald*6,bone*16,rotten_flesh*8,enchanted_golden_apple")
    b.set(P(-1), lowF - 4, Q(50), C(B.soul_lantern))
    for h in (lowF - 4)...(lowF - 1) { b.set(P(0), h, Q(52), C(B.ladder, 0)) }

    // Queen's chamber
    b.set(P(-4), landF, Q(47), C(B.lantern))
    b.set(P(4), landF, Q(53), C(B.lantern))
    b.fill(P(-1), landF, Q(53), P(1), landF + 1, Q(54), smooth) // niche statue base
    b.set(P(0), landF + 2, Q(54), C(B.chiseled_sandstone))
    kitChest(b, P(0), landF, Q(52), 0, "gold_ingot*8,lapis_lazuli*24,bread*16")

    // treasury
    for u in -13...(-9) { b.set(P(u), landF, Q(44), C(B.gold_block)) }
    kitChest(b, P(-13), landF, Q(38), 1, "diamond*8,gold_block*4,emerald*12,golden_apple*4")
    kitChest(b, P(-11), landF, Q(38), 1, "gold_ingot*32,golden_horse_armor,name_tag,saddle")
    kitChest(b, P(-9), landF, Q(38), 1, "tnt*16,flint_and_steel,arrow*32,bow")
    b.set(P(-14), landF + 3, Q(41), C(B.lantern, 1))
    b.set(P(-8), landF + 3, Q(41), C(B.lantern, 1))

    // King's chamber: sarcophagus and treasure
    b.fill(P(5), kingF, Q(k0 + 2), P(7), kingF, Q(k0 + 4), granite)
    b.set(P(6), kingF, Q(k0 + 3), C(B.gold_block))
    kitChest(b, P(-2), kingF, Q(k1), 0, "diamond*16,gold_block*8,emerald_block*2,lifecharm")
    kitChest(b, P(10), kingF, Q(k1), 0, "golden_apple*8,enchanted_golden_apple*2,darksteel_scrap*4,music_disc_wander")
    for (u, v) in [(-2, k0), (10, k0), (-2, k1 - 1), (10, k1 - 1)] { b.set(P(u), kingF, Q(v), C(B.lantern)) }
    b.set(P(4), kingF + 5, Q(k0 + 3), C(B.lantern, 1))
}

// ---------------------------------------------------------------------------
// Castle: 33×33 curtain wall with corner towers, gatehouse, wall walk and a
// three-story keep
// ---------------------------------------------------------------------------
func starterCastle(_ b: Builder, _ x: Int, _ y: Int, _ z: Int) {
    let S = 32
    let brick = C(B.stone_bricks), mossy = C(B.mossy_stone_bricks), cracked = C(B.cracked_stone_bricks)
    let planks = C(B.spruce_planks)
    func wallBlock(_ i: Int, _ h: Int) -> Int { (i * 7 + h * 3) % 11 == 0 ? mossy : (i * 5 + h) % 13 == 0 ? cracked : brick }
    // courtyard
    b.fill(x, y - 1, z, x + S, y - 1, z + S, C(B.grass_block))
    b.fill(x, y, z, x + S, y + 16, z + S, AIR)
    // curtain wall, 7 tall, with crenellations and a plank wall walk
    let wh = 7
    for i in 0...S {
        for h in 0..<wh {
            for (wx, wz) in [(x + i, z), (x + i, z + S), (x, z + i), (x + S, z + i)] { b.set(wx, y + h, wz, wallBlock(i, h)) }
            for (wx, wz) in [(x + i, z + 1), (x + i, z + S - 1), (x + 1, z + i), (x + S - 1, z + i)] {
                b.set(wx, y + h, wz, h == wh - 1 ? planks : wallBlock(i + 3, h))
            }
        }
        if i % 2 == 0 {
            for (wx, wz) in [(x + i, z), (x + i, z + S), (x, z + i), (x + S, z + i)] { b.set(wx, y + wh, wz, brick) }
        }
    }
    // corner towers 7×7, 12 tall, hollow with ladders
    for (tx, tz) in [(x - 2, z - 2), (x + S - 4, z - 2), (x - 2, z + S - 4), (x + S - 4, z + S - 4)] {
        b.fill(tx, y - 1, tz, tx + 6, y + 11, tz + 6, brick)
        b.fill(tx + 1, y, tz + 1, tx + 5, y + 10, tz + 5, AIR)
        for d in 0...6 where d % 2 == 0 {
            for (cx, cz) in [(tx + d, tz), (tx + d, tz + 6), (tx, tz + d), (tx + 6, tz + d)] { b.set(cx, y + 12, cz, brick) }
        }
        for h in 0...11 { b.set(tx + 3, y + h, tz + 4, C(B.ladder, 0)) }
        b.set(tx + 3, y + 11, tz + 3, AIR)
        b.set(tx + 3, y + 11, tz + 4, C(B.ladder, 0))
        b.fill(tx + 3, y, tz + 5, tx + 3, y + 11, tz + 5, brick)
        b.set(tx + 1, y, tz + 1, C(B.lantern))
        // upper floor level with the wall walk, doorways onto the walk
        b.fill(tx + 1, y + wh - 1, tz + 1, tx + 5, y + wh - 1, tz + 5, planks)
        b.set(tx + 3, y + wh - 1, tz + 4, C(B.ladder, 0))
        for a in 0...6 {
            for c in 0...6 where a == 0 || a == 6 || c == 0 || c == 6 {
                let wx = tx + a, wz = tz + c
                let onWalk = ((wx == x + 1 || wx == x + S - 1) && wz >= z && wz <= z + S)
                    || ((wz == z + 1 || wz == z + S - 1) && wx >= x && wx <= x + S)
                if onWalk { b.set(wx, y + wh, wz, AIR); b.set(wx, y + wh + 1, wz, AIR) }
            }
        }
        // ground doorway facing the courtyard
        let gdx = tx < x + S / 2 ? tx + 5 : tx + 1
        let gdz = tz < z + S / 2 ? tz + 6 : tz
        b.set(gdx, y, gdz, AIR); b.set(gdx, y + 1, gdz, AIR)
        flag(b, tx + 3, y + 12, tz + 3)
    }
    // gatehouse on the north wall: archway, raised iron portcullis, lanterns
    let gx = x + S / 2
    b.fill(gx - 3, y - 1, z - 2, gx + 3, y + wh + 3, z + 2, brick)
    b.fill(gx - 1, y, z - 2, gx + 1, y + 3, z + 2, AIR)
    b.fill(gx - 1, y + 3, z, gx + 1, y + 3, z, C(B.iron_bars)) // portcullis, half raised
    b.fill(gx - 2, y + wh, z - 1, gx + 2, y + wh + 2, z + 1, AIR)
    for d in stride(from: -3, through: 3, by: 2) { b.set(gx + d, y + wh + 3, z - 2, AIR) }
    b.set(gx - 2, y + 2, z - 3, C(B.lantern))
    b.set(gx + 2, y + 2, z - 3, C(B.lantern))
    b.fill(gx - 1, y - 1, z - 8, gx + 1, y - 1, z - 3, C(B.cobblestone))
    // stairs up to the wall walk inside the gate
    for i in 0..<wh {
        b.set(gx + 3 + i, y + i, z + 2, C(B.stone_brick_stairs, 3))
        b.fill(gx + 3 + i, y, z + 2, gx + 3 + i, y + i - 1, z + 2, brick)
    }
    // keep: 13×13, 3 floors, roof with crenellations
    let kx = x + 10, kz = z + 14, ks = 12, fh = 5
    b.fill(kx, y - 1, kz, kx + ks, y + fh * 3, kz + ks, brick)
    for f in 0..<3 {
        let fy = y + f * fh
        b.fill(kx + 1, fy, kz + 1, kx + ks - 1, fy + fh - 2, kz + ks - 1, AIR)
        for d in [3, 6, 9] where f > 0 {
            for (wx, wz) in [(kx + d, kz), (kx + d, kz + ks), (kx, kz + d), (kx + ks, kz + d)] {
                b.set(wx, fy + 1, wz, C(B.glass_pane)); b.set(wx, fy + 2, wz, C(B.glass_pane))
            }
        }
        b.fill(kx + 1, fy - 1, kz + 1, kx + ks - 1, fy - 1, kz + ks - 1, f == 0 ? C(B.polished_andesite) : planks)
        b.set(kx + 6, fy + fh - 2, kz + 6, C(B.lantern, 1))
    }
    for h in y...(y + fh * 3) { b.set(kx + ks - 2, h, kz + ks - 1, C(B.ladder, 0)) }
    for d in 0...ks where d % 2 == 0 {
        for (cx, cz) in [(kx + d, kz), (kx + d, kz + ks), (kx, kz + d), (kx + ks, kz + d)] { b.set(cx, y + fh * 3 + 1, cz, brick) }
    }
    flag(b, kx + 6, y + fh * 3 + 1, kz + 6)
    door(b, kx + 6, y, kz, 0)
    // ground floor: great hall
    b.fill(kx + 3, y, kz + 4, kx + 9, y, kz + 8, C(B.spruce_planks))
    b.set(kx + 1, y, kz + 11, C(B.crafting_table))
    b.set(kx + 2, y, kz + 11, C(B.furnace, 0))
    kitChest(b, kx + 3, y, kz + 11, 0, "iron_sword,iron_helmet,iron_chestplate,iron_leggings,iron_boots,shield,bread*32")
    // second floor: bedrooms
    let f2 = y + fh
    bed(b, kx + 2, f2, kz + 4, 0); bed(b, kx + 4, f2, kz + 4, 0); bed(b, kx + 8, f2, kz + 4, 0)
    kitChest(b, kx + 10, f2, kz + 2, 1, "torch*64,arrow*64,bow,cooked_beef*32")
    // third floor: library
    let f3 = y + fh * 2
    for z2 in [kz + 2, kz + 10] { b.fill(kx + 2, f3, z2, kx + 8, f3 + 2, z2, C(B.bookshelf)) }
    b.set(kx + 6, f3, kz + 6, C(B.enchanting_table))
    // courtyard: well, hay, lamp posts
    let wx = x + 24, wz = z + 6
    b.fill(wx, y - 1, wz, wx + 2, y, wz + 2, C(B.cobblestone))
    b.set(wx + 1, y - 1, wz + 1, C(B.water)); b.set(wx + 1, y, wz + 1, C(B.water))
    for (px, pz) in [(wx, wz), (wx + 2, wz), (wx, wz + 2), (wx + 2, wz + 2)] { b.set(px, y + 1, pz, C(B.oak_fence)); b.set(px, y + 2, pz, C(B.oak_fence)) }
    b.fill(wx, y + 3, wz, wx + 2, y + 3, wz + 2, C(B.spruce_slab))
    for (hx, hz) in [(x + 4, z + 5), (x + 5, z + 5), (x + 4, z + 6), (x + 4, z + 5)] { b.set(hx, y, hz, C(B.hay_block)) }
    b.set(x + 4, y + 1, z + 5, C(B.hay_block))
    for (lx, lz) in [(x + 8, z + 8), (x + 24, z + 24), (x + 8, z + 24), (x + 24, z + 14)] {
        b.set(lx, y, lz, C(B.cobblestone_wall)); b.set(lx, y + 1, lz, C(B.cobblestone_wall)); b.set(lx, y + 2, lz, C(B.lantern))
    }
}

// ---------------------------------------------------------------------------
// Lighthouse: striped round tower on a rocky base, ladder inside, glass lamp
// room with a sea-lantern beacon and a railed balcony
// ---------------------------------------------------------------------------
func starterLighthouse(_ b: Builder, _ x: Int, _ y: Int, _ z: Int) {
    let cx = x + 7, cz = z + 7, R = 4, H = 26
    func ring(_ yy: Int, _ r: Double, wall: Int?, inner: Int?) {
        let ir = Int(r.rounded(.up)) + 1
        for dz in -ir...ir {
            for dx in -ir...ir {
                let d = (Double(dx * dx + dz * dz)).squareRoot()
                if d <= r + 0.5 && d > r - 0.5 { if let wall { b.set(cx + dx, yy, cz + dz, wall) } }
                else if d <= r - 0.5 { if let inner { b.set(cx + dx, yy, cz + dz, inner) } }
            }
        }
    }
    // rocky base
    for h in -3...1 { ring(y + h, Double(R + 3 - max(0, h)), wall: C(B.cobblestone), inner: C(B.stone)) }
    ring(y + 1, Double(R + 2), wall: C(B.cobblestone_wall), inner: C(B.stone))
    // striped tower
    for h in 2..<H {
        let band = ((h - 2) / 4) % 2 == 0 ? C(B.white_concrete) : C(B.red_concrete)
        ring(y + h, Double(R), wall: band, inner: AIR)
    }
    for h in 2..<H { b.set(cx, y + h, cz + 3, C(B.ladder, 0)) }
    door(b, cx, y + 2, cz - R, 0)
    b.fill(cx, y + 1, cz - R - 3, cx, y + 1, cz - R, C(B.cobblestone))
    b.fill(cx, y + 2, cz - R - 3, cx, y + 4, cz - R - 1, AIR)
    for (h, dx, dz) in [(7, R, 0), (12, -R, 0), (17, 0, R), (21, R, 0)] {
        b.set(cx + dx, y + h, cz + dz, C(B.glass_pane)); b.set(cx + dx, y + h + 1, cz + dz, C(B.glass_pane))
    }
    b.set(cx - 2, y + 2, cz, C(B.lantern))
    // gallery deck and railing
    let dy = y + H
    ring(dy, Double(R + 2), wall: C(B.stone_bricks), inner: C(B.stone_bricks))
    ring(dy + 1, Double(R + 2), wall: C(B.iron_bars), inner: nil)
    b.set(cx, dy, cz + 3, C(B.ladder, 0))
    // lamp room
    for h in 1...4 { ring(dy + h, 2, wall: C(B.glass), inner: AIR) }
    b.fill(cx - 1, dy + 1, cz - 1, cx + 1, dy + 3, cz + 1, C(B.sea_lantern))
    b.set(cx, dy + 4, cz, C(B.lumenstone))
    // red cap
    for (i, r) in [3.0, 2.0, 1.0, 0.0].enumerated() { ring(dy + 5 + i, r, wall: C(B.red_concrete), inner: C(B.red_concrete)) }
    b.set(cx, dy + 9, cz, C(B.lightning_rod))
    kitChest(b, cx + 2, y + 2, cz - 1, 2, "spyglass,compass,clock,cooked_cod*16,fishing_rod")
}

// ---------------------------------------------------------------------------
// Windmill: stone base, tapering plank tower, four wool sails facing north
// ---------------------------------------------------------------------------
func starterWindmill(_ b: Builder, _ x: Int, _ y: Int, _ z: Int) {
    let cx = x + 8, cz = z + 8
    let stone = C(B.cobblestone), planks = C(B.spruce_planks), log = C(B.dark_oak_log)
    b.fill(cx - 4, y - 1, cz - 4, cx + 4, y - 1, cz + 4, stone)
    b.fill(cx - 4, y, cz - 4, cx + 4, y + 18, cz + 4, AIR)
    // tower: 9 wide at the base, narrowing every 4 layers
    for h in 0..<16 {
        let r = h < 3 ? 4 : h < 8 ? 3 : h < 13 ? 3 : 2
        let mat = h < 3 ? stone : planks
        b.walls(cx - r, y + h, cz - r, cx + r, y + h, cz + r, mat, AIR)
        b.fill(cx - r + 1, y + h, cz - r + 1, cx + r - 1, y + h, cz + r - 1, AIR)
        for (px, pz) in [(cx - r, cz - r), (cx + r, cz - r), (cx - r, cz + r), (cx + r, cz + r)] { b.set(px, y + h, pz, h < 3 ? stone : log) }
    }
    b.fill(cx - 3, y + 7, cz - 3, cx + 3, y + 7, cz + 3, planks)
    for h in 0...7 { b.set(cx, y + h, cz + 2, C(B.ladder, 0)) }
    b.fill(cx - 1, y, cz + 3, cx + 1, y + 7, cz + 3, planks)
    // pyramid roof
    for i in 0...3 { b.walls(cx - 3 + i, y + 16 + i, cz - 3 + i, cx + 3 - i, y + 16 + i, cz + 3 - i, C(B.dark_oak_planks), C(B.dark_oak_planks)) }
    for (wx, wz) in [(cx - 4, cz), (cx + 4, cz)] {
        b.set(wx, y + 1, wz, C(B.glass_pane)); b.set(wx, y + 2, wz, AIR)
    }
    b.set(cx - 4, y + 2, cz, stone); b.set(cx + 4, y + 2, cz, stone)
    door(b, cx, y, cz - 4, 0)
    b.set(cx, y + 2, cz - 4, stone)
    b.set(cx, y + 10, cz - 3, C(B.glass_pane)); b.set(cx + 3, y + 11, cz, C(B.glass_pane))
    // sails on a hub out the north face
    let hy = y + 12, hz = cz - 4
    b.set(cx, hy, hz, log); b.set(cx, hy, hz - 1, log)
    for d in 1...9 {
        for (sx, sy) in [(cx + d, hy), (cx - d, hy), (cx, hy + d), (cx, hy - d)] { b.set(sx, sy, hz - 1, C(B.oak_fence)) }
        if d >= 3 {
            b.set(cx + d, hy + 1, hz - 1, C(B.white_wool)); b.set(cx + d, hy + 2, hz - 1, C(B.white_wool))
            b.set(cx - d, hy - 1, hz - 1, C(B.white_wool)); b.set(cx - d, hy - 2, hz - 1, C(B.white_wool))
            b.set(cx - 1, hy + d, hz - 1, C(B.white_wool)); b.set(cx - 2, hy + d, hz - 1, C(B.white_wool))
            b.set(cx + 1, hy - d, hz - 1, C(B.white_wool)); b.set(cx + 2, hy - d, hz - 1, C(B.white_wool))
        }
    }
    // interior: millstone and sacks
    b.set(cx - 2, y, cz - 2, C(B.hay_block)); b.set(cx - 2, y, cz - 1, C(B.hay_block)); b.set(cx - 2, y + 1, cz - 2, C(B.hay_block))
    b.set(cx + 2, y, cz - 2, C(B.composter))
    b.set(cx + 2, y + 8, cz - 2, C(B.grindstone))
    kitChest(b, cx + 2, y, cz + 1, 2, "bread*32,wheat*64,wheat_seeds*32,cake")
    b.set(cx - 2, y + 2, cz + 1, C(B.lantern, 0))
    b.set(cx - 2, y + 8, cz + 1, C(B.lantern))
}

// ---------------------------------------------------------------------------
// Treehouse: giant oak with a railed deck 10 up, a hut on the deck and a
// rope-ladder climb
// ---------------------------------------------------------------------------
func starterTreehouse(_ b: Builder, _ x: Int, _ y: Int, _ z: Int) {
    let cx = x + 9, cz = z + 9
    let log = C(B.oak_log), leaves = C(B.oak_leaves), planks = C(B.oak_planks)
    // canopy first so the deck and hut cut through it
    let ty = y + 22
    for dy in -6...5 {
        for dz in -9...9 {
            for dx in -9...9 {
                let r = 9.0 - Double(max(0, dy)) * 0.9
                let d = (Double(dx * dx + dz * dz) + Double(dy * dy) * 1.8).squareRoot()
                if d <= r && (dx * 31 + dz * 17 + dy * 7) % 9 != 0 { b.set(cx + dx, ty + dy, cz + dz, leaves) }
            }
        }
    }
    // trunk 2×2, roots and branches
    b.fill(cx, y - 1, cz, cx + 1, ty, cz + 1, log)
    for (dx, dz) in [(-1, 0), (2, 1), (0, -1), (1, 2)] { b.set(cx + dx, y, cz + dz, log); b.set(cx + dx, y - 1, cz + dz, log) }
    for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
        for i in 1...5 { b.set(cx + (dx < 0 ? 0 : 1) + dx * i, ty - 4 + i / 2, cz + (dz < 0 ? 0 : 1) + dz * i, log) }
    }
    // deck 13×13 at y+10, fence rail, hatch for the ladder
    let dy = y + 10
    b.fill(cx - 6, dy, cz - 6, cx + 7, dy, cz + 7, planks)
    b.fill(cx - 6, dy + 1, cz - 6, cx + 7, dy + 6, cz + 7, AIR)
    b.fill(cx, dy, cz, cx + 1, dy + 6, cz + 1, log)
    for d in -6...7 {
        for (fx, fz) in [(cx + d, cz - 6), (cx + d, cz + 7), (cx - 6, cz + d), (cx + 7, cz + d)] { b.set(fx, dy + 1, fz, C(B.oak_fence)) }
    }
    for (px, pz) in [(cx - 6, cz - 6), (cx + 7, cz - 6), (cx - 6, cz + 7), (cx + 7, cz + 7)] {
        b.set(px, dy + 2, pz, C(B.oak_fence)); b.set(px, dy + 3, pz, C(B.lantern))
    }
    // supports
    for (px, pz) in [(cx - 6, cz - 6), (cx + 7, cz - 6), (cx - 6, cz + 7), (cx + 7, cz + 7)] {
        b.fill(px, y, pz, px, dy - 1, pz, C(B.oak_log))
    }
    // ladder up the north side of the trunk, through a hatch in the deck
    for h in y...dy { b.set(cx, h, cz - 1, C(B.ladder, 0)) }
    // hut on the south half of the deck
    let hx = cx - 4, hz = cz + 3
    b.walls(hx, dy + 1, hz, hx + 9, dy + 4, hz + 3, planks, AIR)
    b.fill(hx + 1, dy + 1, hz + 1, hx + 8, dy + 3, hz + 2, AIR)
    for i in 0...2 { b.fill(hx - 1 + i, dy + 5 + i, hz - 1 + i, hx + 10 - i, dy + 5 + i, hz + 4 - i, C(B.spruce_slab)) }
    b.fill(hx, dy + 5, hz, hx + 9, dy + 5, hz + 3, planks)
    door(b, hx + 2, dy + 1, hz, 0)
    b.set(hx + 7, dy + 2, hz, C(B.glass_pane))
    b.set(hx, dy + 2, hz + 2, C(B.glass_pane)); b.set(hx + 9, dy + 2, hz + 2, C(B.glass_pane))
    bed(b, hx + 7, dy + 1, hz + 2, 2)
    kitChest(b, hx + 1, dy + 1, hz + 2, 0, "apple*16,cookie*16,bow,arrow*32,oak_sapling*8,lead*2")
    b.set(hx + 4, dy + 3, hz + 2, C(B.lantern, 1))
    // swing under the deck
    b.set(cx - 4, dy - 1, cz - 3, C(B.oak_fence)); b.set(cx - 4, dy - 2, cz - 3, C(B.oak_fence))
    b.set(cx - 4, dy - 3, cz - 3, C(B.oak_slab))
}

// ---------------------------------------------------------------------------
// Sky island: floating chunk of land 40 up with a tree, pond and waterfall,
// a small shelter and a chest. Reach it by flying, or by the ladder pillar.
// ---------------------------------------------------------------------------
func starterSkyIsland(_ b: Builder, _ x: Int, _ y: Int, _ z: Int) {
    let cx = x + 12, cz = z + 12, top = y + 40
    let R = 12.0
    for dz in -12...12 {
        for dx in -12...12 {
            let d = Double(dx * dx + dz * dz).squareRoot()
            let wob = Double((dx * 73 + dz * 151) & 7) / 7
            if d > R - wob * 1.5 { continue }
            let depth = Int(((R - d) * 1.1 + wob * 2).rounded())
            for h in 0...depth {
                let c = h == 0 ? C(B.grass_block) : h < 3 ? C(B.dirt) : (dx + dz + h) % 7 == 0 ? C(B.andesite) : C(B.stone)
                b.set(cx + dx, top - h, cz + dz, c)
            }
            if depth > 6 && (dx * dz + h7(dx, dz)) % 13 == 0 { b.set(cx + dx, top - depth + 2, cz + dz, C(B.iron_ore)) }
        }
    }
    // pond spilling a waterfall over the east edge
    b.fill(cx + 3, top - 1, cz - 2, cx + 6, top, cz + 1, C(B.water))
    for i in 7...12 { b.set(cx + i, top, cz, C(B.water)) }
    b.fill(cx + 3, top - 2, cz - 2, cx + 6, top - 2, cz + 1, C(B.dirt))
    // tree
    let tx = cx - 5, tz = cz - 4
    for h in 1...6 { b.set(tx, top + h, tz, C(B.oak_log)) }
    for dy in 4...8 {
        let r = dy < 7 ? 2 : 1
        for dz in -r...r { for dx in -r...r where dx != 0 || dz != 0 || dy > 6 { b.set(tx + dx, top + dy, tz + dz, C(B.oak_leaves)) } }
    }
    // shelter
    let sx = cx - 3, sz = cz + 4
    b.walls(sx, top + 1, sz, sx + 4, top + 3, sz + 4, C(B.oak_planks), AIR)
    b.fill(sx + 1, top + 1, sz + 1, sx + 3, top + 2, sz + 3, AIR)
    b.fill(sx, top + 4, sz, sx + 4, top + 4, sz + 4, C(B.oak_slab))
    door(b, sx + 2, top + 1, sz, 0)
    bed(b, sx + 1, top + 1, sz + 3, 3)
    kitChest(b, sx + 3, top + 1, sz + 1, 2, "water_bucket*2,lava_bucket,bone_meal*16,oak_sapling*4,ice*2,melon_seeds,pumpkin_seeds")
    b.set(sx + 3, top + 3, sz + 2, C(B.lantern, 1))
    // ladder on a plank pillar from the ground up the north rim
    var vy = top - 1
    while vy > y { b.set(cx, vy, cz - 13, C(B.ladder, 0)); vy -= 1 }
    b.set(cx, top, cz - 13, C(B.grass_block))
    for h in (y)...(top - 1) where b.get(cx, h, cz - 12) == 0 { b.set(cx, h, cz - 12, C(B.oak_planks)) }
    flag(b, cx + 9, top + 1, cz + 6)
}

@inline(__always) private func h7(_ a: Int, _ b: Int) -> Int { (a &* 0x45 ^ b &* 0x27) & 0xFF }
