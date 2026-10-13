// World wonders for /place — famous structures at landmark scale, alongside
// the pyramid and castle in StructLandmarks.swift. Same convention: (x, y, z)
// is the north-west corner at ground level, y is the first air layer, and
// /place clears the site and pours foundations under every column.

import Foundation

@inline(__always) private func C(_ b: UInt16, _ m: Int = 0) -> Int { Int(cell(b, m)) }
private let AIR = 0

/// deterministic 0..<1 per position (the same build every time)
private func rnd(_ x: Int, _ y: Int, _ z: Int, _ salt: UInt32) -> Double {
    Double(hash3(0x5eed_1f2e, x, y, z, salt) % 10_000) / 10_000
}
@inline(__always) private func smooth(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let t = min(1, max(0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)
}

// ---------------------------------------------------------------------------
// Eiffel Tower: ~150 tall at about half scale. Four tapering lattice legs on
// stone footings, the great arches between them, three platforms, a single
// lattice shaft above the second, a glass room up top and a lit spire. A
// ladder pole runs up the middle.
// ---------------------------------------------------------------------------
func starterEiffelTower(_ b: Builder, _ x: Int, _ y: Int, _ z: Int) {
    let K = 31, cx = x + K, cz = z + K
    let iron = C(B.brown_terracotta), deck = C(B.smooth_stone), rail = C(B.iron_bars)
    let P1 = 26, P2 = 52, P3 = 125
    /// outer half-width of the tower at height h (the curve of the legs)
    func w(_ h: Double) -> Double { 2.0 + 28.0 * pow(max(0, 1 - h / 128), 2.2) }
    /// leg thickness below the second platform
    func lw(_ h: Double) -> Double { 11 - 5.5 * min(1, h / Double(P2)) }
    func lattice(_ u: Int, _ h: Int) -> Bool {
        h % 8 == 0 || (u + h) % 4 == 0 || ((u - h) % 4 + 4) % 4 == 0
    }

    // the Champ de Mars: lawn, gravel under the tower
    for dz in -K...K {
        for dx in -K...K {
            let m = max(abs(dx), abs(dz))
            b.set(cx + dx, y - 1, cz + dz, m <= 24 || abs(abs(dx) - abs(dz)) <= 1 ? C(B.gravel) : C(B.grass_block))
        }
    }
    for h in 0..<P3 {
        let hd = Double(h), W = w(hd), yy = y + h
        let R = Int(W.rounded(.up))
        if h < P2 {
            // four legs: hollow lattice columns leaning in
            let inner = W - lw(hd)
            for dz in -R...R {
                for dx in -R...R {
                    let ax = Double(abs(dx)), az = Double(abs(dz))
                    guard ax >= inner - 0.5, ax <= W + 0.5, az >= inner - 0.5, az <= W + 0.5 else { continue }
                    let edgeX = ax >= W - 0.5 || ax <= inner + 0.5
                    let edgeZ = az >= W - 0.5 || az <= inner + 0.5
                    if !(edgeX || edgeZ) { continue }   // hollow inside
                    let corner = edgeX && edgeZ
                    let along = edgeX ? abs(dz) : abs(dx)
                    if h < 2 { b.set(cx + dx, yy, cz + dz, C(B.stone_bricks)); continue }   // masonry footings
                    if corner || lattice(along, h) { b.set(cx + dx, yy, cz + dz, iron) }
                }
            }
            // the great arches, one per side, springing from the legs at 6
            if h >= 6 && h <= 26 {
                let a = w(6) - lw(6) + 0.5, rise = 18.0
                for side in 0..<4 {
                    for u in -R...R {
                        let au = Double(abs(u))
                        guard au < a else { continue }
                        let lower = 6 + rise * (1 - au * au / (a * a)).squareRoot()
                        guard hd >= lower - 0.5, hd <= lower + 1.5 else { continue }
                        for t in 0...1 {
                            let o = R - t
                            let (dx, dz) = [(u, -o), (u, o), (-o, u), (o, u)][side]
                            b.set(cx + dx, yy, cz + dz, iron)
                        }
                    }
                }
            }
        } else if h > P2 + 1 {
            // one shaft: a hollow lattice square, solid every tenth level
            let r = max(1, Int(W.rounded()))
            for dz in -r...r {
                for dx in -r...r where max(abs(dx), abs(dz)) == r {
                    let corner = abs(dx) == r && abs(dz) == r
                    if corner || h % 10 == 0 || lattice(abs(dx) == r ? dz + r : dx + r, h) {
                        b.set(cx + dx, yy, cz + dz, iron)
                    }
                }
            }
        }
    }
    // first platform: a square ring with a girder skirt and railing
    let o1 = Int(w(Double(P1))) + 3, i1 = Int(w(Double(P1)) - lw(Double(P1))) - 1
    for dz in -o1...o1 {
        for dx in -o1...o1 {
            let m = max(abs(dx), abs(dz))
            guard m >= i1 else { continue }
            b.set(cx + dx, y + P1, cz + dz, iron)
            b.set(cx + dx, y + P1 + 1, cz + dz, deck)
            if m == o1 {
                b.set(cx + dx, y + P1 - 1, cz + dz, iron)
                b.set(cx + dx, y + P1 + 2, cz + dz, rail)
            }
        }
    }
    // second platform: solid square, railing
    let o2 = Int(w(Double(P2))) + 2
    for dz in -o2...o2 {
        for dx in -o2...o2 {
            b.set(cx + dx, y + P2, cz + dz, iron)
            b.set(cx + dx, y + P2 + 1, cz + dz, deck)
            if max(abs(dx), abs(dz)) == o2 { b.set(cx + dx, y + P2 + 2, cz + dz, rail) }
        }
    }
    for (dx, dz) in [(-o1 + 1, -o1 + 1), (o1 - 1, o1 - 1), (-o2 + 1, o2 - 1), (o2 - 1, -o2 + 1)] {
        let py = abs(dx) == o1 - 1 ? y + P1 + 2 : y + P2 + 2
        b.set(cx + dx, py, cz + dz, C(B.lantern))
    }
    // top: glass room, roof, spire with a light and a lightning rod
    for dz in -4...4 {
        for dx in -4...4 {
            let m = max(abs(dx), abs(dz))
            b.set(cx + dx, y + P3, cz + dz, deck)
            b.set(cx + dx, y + P3 + 4, cz + dz, iron)
            if m == 4 {
                for h in 1...3 { b.set(cx + dx, y + P3 + h, cz + dz, abs(dx) == 4 && abs(dz) == 4 ? iron : C(B.glass_pane)) }
            }
        }
    }
    b.fill(cx - 1, y + P3 + 5, cz - 1, cx + 1, y + P3 + 14, cz + 1, iron)
    for h in 15...21 { b.set(cx, y + P3 + h, cz, rail) }
    b.set(cx, y + P3 + 22, cz, C(B.sea_lantern))
    b.set(cx, y + P3 + 23, cz, C(B.lightning_rod))
    b.set(cx + 2, y + P3 + 1, cz + 2, C(B.lantern))
    // the climb: a pole up the middle with a ladder on its north side
    for h in 1...P3 {
        b.set(cx, y + h, cz + 1, iron)
        b.set(cx, y + h, cz, C(B.ladder, 0))
    }
    b.set(cx, y + P3 + 1, cz, AIR)
    kitChest(b, cx - 2, y + P3 + 1, cz - 2, 1, "spyglass,map,bread*8,firework_rocket*16")
}

// ---------------------------------------------------------------------------
// Stonehenge at 1:1: the sarsen circle with its lintels (gaps where stones
// are missing, as at the real site), five trilithons in a horseshoe opening
// north-east to the midsummer sunrise (the great one fallen), the bluestone
// circle and horseshoe, altar, slaughter and heel stones, the ditch and bank,
// and the Avenue running north-east.
// ---------------------------------------------------------------------------
func starterStonehenge(_ b: Builder, _ x: Int, _ y: Int, _ z: Int) {
    let cx = x + 56, cz = z + 82
    let axis = -Double.pi / 4   // north-east: +x, -z
    func sarsen(_ px: Int, _ py: Int, _ pz: Int) -> Int {
        let r = rnd(px, py, pz, 1)
        return r < 0.6 ? C(B.stone) : r < 0.82 ? C(B.andesite) : r < 0.94 ? C(B.tuff) : C(B.mossy_cobblestone)
    }
    func blue(_ px: Int, _ py: Int, _ pz: Int) -> Int {
        rnd(px, py, pz, 2) < 0.6 ? C(B.cobbled_deepslate) : C(B.polished_deepslate)
    }
    func angDiff(_ a: Double, _ b: Double) -> Double {
        var d = (a - b).truncatingRemainder(dividingBy: 2 * .pi)
        if d > .pi { d -= 2 * .pi }
        if d < -.pi { d += 2 * .pi }
        return d
    }

    // ground: henge, ditch with a bank inside it, the entrance and the Avenue
    for dz in -82...56 {
        for dx in -56...70 {
            let rho = (Double(dx * dx + dz * dz)).squareRoot()
            let th = atan2(Double(dz), Double(dx))
            let along = Double(dx) * cos(axis) + Double(dz) * sin(axis)      // toward the NE
            let across = -Double(dx) * sin(axis) + Double(dz) * cos(axis)
            let inAvenue = along > 40 && along < 98 && abs(across) < 8
            let entrance = abs(angDiff(th, axis)) < 0.16
            guard rho <= 55 || inAvenue else { continue }
            let X = cx + dx, Z = cz + dz
            b.set(X, y - 1, Z, C(B.grass_block))
            if !entrance && rho >= 49 && rho < 53 {
                b.set(X, y - 1, Z, AIR); b.set(X, y - 2, Z, C(B.grass_block))     // ditch
            } else if !entrance && rho >= 45 && rho < 49 {
                b.set(X, y, Z, C(B.grass_block))                                    // bank
            } else if inAvenue && abs(abs(across) - 7) < 1 {
                b.set(X, y, Z, C(B.grass_block))                                    // Avenue banks
            } else if rnd(X, y, Z, 3) < 0.08 {
                b.set(X, y, Z, C(B.short_grass))
            }
        }
    }

    // sarsen circle: 30 uprights 4 tall around r=15, lintels where both stand
    let n = 30, step = 2 * Double.pi / Double(n)
    let missing: Set<Int> = [9, 10, 12, 13, 14, 17, 18, 19, 20, 22, 24, 25]
    for dz in -16...16 {
        for dx in -16...16 {
            let rho = (Double(dx * dx + dz * dz)).squareRoot()
            guard rho >= 14.4, rho <= 15.6 else { continue }
            let th = atan2(Double(dz), Double(dx)) - axis
            let k = ((Int((th / step).rounded()) % n) + n) % n
            let off = abs(angDiff(th, Double(k) * step))
            let X = cx + dx, Z = cz + dz
            if off <= 1.05 / 15 && !missing.contains(k) {
                for h in 0...3 { b.set(X, y + h, Z, sarsen(X, y + h, Z)) }
            }
            // lintel between stone k and its neighbor on the near side
            let k2 = ((Int((th / step).rounded(.down)) % n) + n) % n
            if !missing.contains(k2) && !missing.contains((k2 + 1) % n) && ![27, 6].contains(k2) {
                b.set(X, y + 4, Z, C(B.smooth_stone))
            }
        }
    }
    // trilithons: two uprights and a lintel, set along the horseshoe
    func trilithon(_ ang: Double, _ r: Double, _ height: Int, fallen: Bool) {
        let a = axis + ang
        let px = Double(cx) + r * cos(a), pz = Double(cz) + r * sin(a)
        let tx = -sin(a), tz = cos(a)
        for oz in -5...5 {
            for ox in -5...5 {
                let X = Int(px.rounded()) + ox, Z = Int(pz.rounded()) + oz
                let vx = Double(X) - px, vz = Double(Z) - pz
                let s = vx * tx + vz * tz, nn = vx * cos(a) + vz * sin(a)
                guard abs(nn) <= 0.7 else { continue }
                if abs(s) >= 0.5 && abs(s) <= 2.5 {
                    let upright = s > 0 ? 1 : 0
                    if fallen && upright == 1 { continue }
                    for h in 0..<height { b.set(X, y + h, Z, sarsen(X, y + h, Z)) }
                }
                if !fallen && abs(s) <= 2.6 { b.set(X, y + height, Z, C(B.smooth_stone)) }
            }
        }
        if fallen {
            // the toppled upright and lintel lie broken across the middle
            for i in 1...6 {
                let X = Int((px - cos(a) * Double(i) + tx * 1.5).rounded()), Z = Int((pz - sin(a) * Double(i) + tz * 1.5).rounded())
                b.set(X, y, Z, sarsen(X, y, Z)); b.set(X + 1, y, Z, sarsen(X + 1, y, Z))
            }
            for i in -2...2 {
                let X = Int((px - cos(a) * 3 + tx * Double(i)).rounded()), Z = Int((pz - sin(a) * 3 + tz * Double(i)).rounded())
                b.set(X, y, Z, C(B.smooth_stone))
            }
        }
    }
    let half = Double.pi
    trilithon(half, 6.5, 7, fallen: true)               // the Great Trilithon
    trilithon(half - 1.0, 8.0, 6, fallen: false)
    trilithon(half + 1.0, 8.0, 6, fallen: false)
    trilithon(half - 1.85, 9.0, 5, fallen: false)
    trilithon(half + 1.85, 9.0, 5, fallen: false)
    // bluestones: a ragged circle, and a horseshoe inside the trilithons
    for i in 0..<44 where rnd(i, 0, 7, 4) < 0.62 {
        let a = Double(i) / 44 * 2 * .pi
        let X = cx + Int((11.5 * cos(a)).rounded()), Z = cz + Int((11.5 * sin(a)).rounded())
        for h in 0..<(2 + Int(rnd(i, 1, 7, 5) * 2)) { b.set(X, y + h, Z, blue(X, y + h, Z)) }
    }
    for i in 0..<13 {
        let a = axis + half + (Double(i) / 12 - 0.5) * 3.6
        let r = 4.8 + abs(Double(i) / 12 - 0.5) * 1.6
        let X = cx + Int((r * cos(a)).rounded()), Z = cz + Int((r * sin(a)).rounded())
        for h in 0..<2 { b.set(X, y + h, Z, blue(X, y + h, Z)) }
    }
    // altar stone (fallen, under the great trilithon), slaughter and heel stones
    for i in -2...1 {
        let X = cx + Int((-cos(axis) * 3.2 + -sin(axis) * Double(i)).rounded())
        let Z = cz + Int((-sin(axis) * 3.2 + cos(axis) * Double(i)).rounded())
        b.set(X, y, Z, C(B.polished_andesite))
    }
    func along(_ d: Double, _ s: Double) -> (Int, Int) {
        (cx + Int((cos(axis) * d - sin(axis) * s).rounded()), cz + Int((sin(axis) * d + cos(axis) * s).rounded()))
    }
    for d in 0..<3 { for s in 0..<2 { let (X, Z) = along(44 + Double(d), Double(s) - 2); b.set(X, y, Z, sarsen(X, y, Z)) } }
    for h in 0..<5 {
        for (d, s) in [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0)] {
            let (X, Z) = along(70 + d + Double(h) * 0.2, s)
            b.set(X, y + h, Z, sarsen(X, y + h, Z))
        }
    }
}

// ---------------------------------------------------------------------------
// Colosseum: a 125×105 ellipse, 32 tall. Three stories of arcades and an
// attic outside, a corridor behind them, the inner ring, stepped seating
// down to the podium wall, and the arena: half floored in planks, half open
// over the hypogeum's passages. The south side is ruined, as it is in Rome,
// leaving the inner ring stepped and exposed.
// ---------------------------------------------------------------------------
func starterColosseum(_ b: Builder, _ x: Int, _ y: Int, _ z: Int) {
    let A = 62.0, B2 = 52.0, a = 28.0, bb = 18.0
    let cx = x + 63, cz = z + 53
    let top = 31, ringTop = 23
    func trav(_ px: Int, _ py: Int, _ pz: Int) -> Int {
        rnd(px, py, pz, 11) < 0.88 ? C(B.white_terracotta) : C(B.smooth_sandstone)
    }
    func brick(_ px: Int, _ py: Int, _ pz: Int) -> Int {
        let r = rnd(px, py, pz, 12)
        return r < 0.7 ? C(B.bricks) : r < 0.9 ? C(B.terracotta) : C(B.granite)
    }
    /// arcade opening at (story-local height, bay-local u): 3½ wide in a
    /// 5-block bay, `tall` high with the corners rounded off the top
    let bay = 5.0
    func opening(_ hs: Int, _ u: Double, tall: Int) -> Bool {
        guard u >= 1.2, u <= 4.8 else { return false }
        let mid = abs(u - 3.0)
        return hs >= 0 && hs < tall - (mid > 1.2 ? 1 : 0)
    }
    /// how high the outer ring still stands: the ruined south side
    func standing(_ th: Double, _ px: Int, _ pz: Int) -> Int {
        let start = 0.36 * Double.pi, end = 0.92 * Double.pi
        guard th > start - 0.12 && th < end + 0.12 else { return top }
        let into = min(th - (start - 0.12), (end + 0.12) - th)
        if into < 0.12 {
            // stepped buttress ends
            return max(2, top - Int(into / 0.12 * Double(top - 2)) - Int(rnd(px, 0, pz, 13) * 3))
        }
        return Int(rnd(px, 1, pz, 14) * 3)
    }

    for dz in -54...54 {
        for dx in -64...64 {
            let fx = Double(dx), fz = Double(dz)
            let rho = (fx * fx + fz * fz).squareRoot()
            let th = atan2(fz, fx)
            let c = cos(th), s = sin(th)
            let R = A * B2 / ((B2 * c) * (B2 * c) + (A * s) * (A * s)).squareRoot()
            guard rho <= R + 0.5 else { continue }
            let rA = a * bb / ((bb * c) * (bb * c) + (a * s) * (a * s)).squareRoot()
            let d = R - rho              // depth in from the outer face
            let dArena = rho - rA        // out from the arena's edge
            let X = cx + dx, Z = cz + dz
            let arc = (th + Double.pi) * (A + B2) / 2
            let u = arc.truncatingRemainder(dividingBy: bay)
            let pier = u < 1.2 || u > 4.8
            let ruinTop = standing(th < 0 ? th + 2 * .pi : th, X, Z)
            b.set(X, y - 1, Z, C(B.stone_bricks))

            if d < 1.5 {
                // facade: three arcaded stories, then the attic
                for h in 0...top where h <= ruinTop {
                    let story = h / 8, hs = h % 8
                    var solid = true
                    if story < 3 && hs < 7 && opening(hs, u, tall: 6) { solid = false }
                    if story == 3 && (hs == 3 || hs == 4) && u > 2.4 && u < 3.6 && Int(arc / bay) % 2 == 0 { solid = false }
                    // cornices between the stories: the facade's horizontal lines
                    let cornice = hs == 7 && story < 3
                    if solid { b.set(X, y + h, Z, cornice ? C(B.smooth_sandstone) : trav(X, y + h, Z)) }
                }
            } else if d < 6 {
                // corridor behind the facade: floors at each story, piers in line with the facade's
                for h in 0...ringTop where h <= ruinTop {
                    if h == 7 || h == 15 || h == 23 { b.set(X, y + h, Z, brick(X, y + h, Z)); continue }
                    if pier && (d < 2.5 || d > 5) { b.set(X, y + h, Z, trav(X, y + h, Z)) }
                }
            } else if d < 7.5 {
                // inner ring: arcaded too, standing even where the outside fell
                for h in 0...ringTop {
                    let story = h / 8, hs = h % 8
                    if story < 3 && hs < 6 && opening(hs, u, tall: 5) { continue }
                    b.set(X, y + h, Z, h > 20 ? brick(X, y + h, Z) : trav(X, y + h, Z))
                }
            } else if dArena >= 2 {
                // seating: stepped down to the podium, two blocks thick over vaults
                let t = dArena / (dArena + d - 7.5)
                let hs = 4 + Int((18 * t).rounded())
                let radialWall = Int(arc / bay) % 6 == 0 && u < 1.5
                for h in 0...hs {
                    if h >= hs - 1 {
                        let worn = rnd(X, h, Z, 15)
                        if worn < 0.06 { continue }
                        b.set(X, y + h, Z, worn < 0.3 ? brick(X, y + h, Z) : trav(X, y + h, Z))
                    } else if radialWall {
                        b.set(X, y + h, Z, brick(X, y + h, Z))
                    }
                }
            } else if dArena >= 0 {
                // podium wall
                for h in 0...3 { b.set(X, y + h, Z, trav(X, y + h, Z)) }
            } else {
                // the arena over the hypogeum: a grid of passages 4 deep
                let wall = ((dx % 6) + 6) % 6 == 0 || ((dz % 6) + 6) % 6 == 0
                for h in -5...(-2) { b.set(X, y + h, Z, wall ? brick(X, y + h, Z) : AIR) }
                b.set(X, y - 6, Z, C(B.stone_bricks))
                b.set(X, y - 1, Z, dx > 0 ? (rnd(X, 0, Z, 16) < 0.25 ? C(B.sand) : C(B.spruce_planks))
                                          : (wall ? brick(X, y - 1, Z) : AIR))
            }
        }
    }
    // rubble along the fallen side
    for i in 0..<60 {
        let th = (0.36 + rnd(i, 2, 0, 17) * 0.56) * Double.pi
        let r = A * B2 / ((B2 * cos(th)) * (B2 * cos(th)) + (A * sin(th)) * (A * sin(th))).squareRoot() + 1 + rnd(i, 3, 0, 18) * 3
        let X = cx + Int((r * cos(th)).rounded()), Z = cz + Int((r * sin(th)).rounded())
        b.set(X, y, Z, trav(X, y, Z))
        if rnd(i, 4, 0, 19) < 0.4 { b.set(X, y + 1, Z, trav(X, y + 1, Z)) }
    }
}

// ---------------------------------------------------------------------------
// Devils Tower: an 80-block monolith of fluted basalt columns rising from a
// talus apron of rubble, fallen columns, grass and pines; the summit is a
// rough pavement of column tops with grass and a few trees.
// ---------------------------------------------------------------------------
func starterDevilsTower(_ b: Builder, _ x: Int, _ y: Int, _ z: Int) {
    let cx = x + 52, cz = z + 52
    let Rb = 26.0, Rapron = 51.0, apronTop = 14, H = 78, N = 42.0
    var rng = RandomX(0xde71_1570)
    func basalt(_ col: Int, _ h: Int) -> Int {
        let r = rnd(col, h / 7, 0, 21)
        return r < 0.72 ? C(B.basalt, 0) : r < 0.86 ? C(B.smooth_basalt) : r < 0.95 ? C(B.tuff) : C(B.polished_basalt, 0)
    }
    /// tower radius at height h above the apron, toward angle th (fluted)
    func radius(_ h: Int, _ th: Double) -> Double {
        let r0 = 17 + 9 * pow(max(0, 1 - Double(h) / Double(H)), 2.2)
        let flute = abs(sin(th * N / 2))
        return r0 + 1.3 * flute - 0.6
    }

    var treeSpots: [(Int, Int, Int)] = []
    for dz in -52...52 {
        for dx in -52...52 {
            let fx = Double(dx), fz = Double(dz)
            let rho = (fx * fx + fz * fz).squareRoot()
            guard rho <= Rapron + 1 else { continue }
            let th = atan2(fz, fx)
            let X = cx + dx, Z = cz + dz
            // apron: rises to the tower's foot, rubble getting coarser near it
            var ah = apronTop
            if rho > Rb {
                let t = min(1, (rho - Rb) / (Rapron - Rb))   // (pow of a negative is NaN)
                ah = Int((Double(apronTop) * pow(1 - t, 1.6) + (rnd(X, 0, Z, 22) - 0.5) * 2).rounded())
            }
            for h in 0..<max(0, ah) {
                let surface = h == ah - 1
                let near = 1 - min(1, max(0, (rho - Rb) / (Rapron - Rb)))
                var c = C(B.stone)
                if surface {
                    let r = rnd(X, h, Z, 23)
                    c = r < near * 0.45 ? (rnd(X, h, Z, 24) < 0.6 ? C(B.basalt, 0) : C(B.blackstone))
                        : r < near * 0.45 + 0.15 ? C(B.gravel)
                        : r < near * 0.45 + 0.35 ? C(B.coarse_dirt) : C(B.grass_block)
                } else if h >= ah - 3 {
                    c = C(B.dirt)
                }
                b.set(X, y + h, Z, c)
            }
            if ah > 0 && rho > Rb + 6 && rnd(X, 1, Z, 25) < 0.012 { treeSpots.append((X, y + ah, Z)) }
            else if ah > 0 && rho > Rb + 2 && rnd(X, 2, Z, 26) < 0.05 { b.set(X, y + ah, Z, C(B.short_grass)) }
            // the tower
            let col = Int(((th + Double.pi) * N / (2 * .pi)).rounded(.down))
            let ring = Int(rho / 3.5)
            let topH = H - Int(2 * pow(rho / 18, 2)) - Int(rnd(col, ring, 0, 27) * 4)
            guard rho <= radius(0, th) + 0.5 else { continue }
            for h in 0..<topH where rho <= radius(h, th) {
                b.set(X, y + apronTop + h, Z, basalt(col * 31 + ring, h))
            }
            // the summit: grass in the hollows between column tops
            let sy = y + apronTop + topH
            if rho <= radius(topH - 1, th) && rnd(X, 3, Z, 28) < 0.35 {
                b.set(X, sy - 1, Z, C(B.grass_block))
                if rnd(X, 4, Z, 29) < 0.2 { b.set(X, sy, Z, C(B.short_grass)) }
                else if rho < 12 && rnd(X, 5, Z, 30) < 0.01 { treeSpots.append((X, sy, Z)) }
            }
        }
    }
    // fallen columns lying on the talus, pointing away from the tower
    for i in 0..<28 {
        let th = rnd(i, 0, 9, 31) * 2 * .pi
        let r = Rb + 3 + rnd(i, 1, 9, 32) * 16
        let len = 3 + Int(rnd(i, 2, 9, 33) * 4)
        let alongX = abs(cos(th)) > abs(sin(th))
        for k in 0..<len {
            let fx = (r + Double(k)) * cos(th), fz = (r + Double(k)) * sin(th)
            let X = cx + Int(fx.rounded()), Z = cz + Int(fz.rounded())
            var top = y
            while top < y + apronTop + 2 && b.get(X, top, Z) > 0 { top += 1 }
            b.set(X, top, Z, C(B.basalt, alongX ? 1 : 2))
        }
    }
    for (tx, ty, tz) in treeSpots { genSpruceTree(b.s, &rng, tx, ty, tz) }
}
