// Models and painted skins for the anime-style animals (Entity/AnimeAnimals.swift).
// Each animal is built from its spec: a big head on a small body (four legs,
// or two legs and flippers/wings), ears, a tail and a few extras, laid out on
// a box-UV sheet by a shelf packer, then painted to match — big sparkly eyes,
// blush, lighter belly. They have no pack texture: the painted skin is the art.
// Animated by the "chibi" profiles in PebbleApp/EntityRendererM.swift.

import Foundation

/// what a box is for, so the painter knows how to colour it
private enum Role {
    case head, snout, beak, ear, body, belly, bodyDark, leg, legDark, legSock, foot, tail, tailTip, wing, cheek, collar, bell, leaf, scarf, tuft
}

private struct PlacedBox {
    let part: String
    let box: ModelBox
    let role: Role
}

/// box-UV shelf packer: each box needs 2·(w+d) × (d+h) texels
private struct UVPacker {
    let width: Int
    var x = 0, y = 0, row = 0
    init(width: Int) { self.width = width }

    mutating func place(_ w: Double, _ h: Double, _ d: Double) -> (Double, Double) {
        let uw = 2 * (Int(w.rounded(.up)) + Int(d.rounded(.up)))
        let uh = Int(d.rounded(.up)) + Int(h.rounded(.up))
        if x + uw > width { x = 0; y += row; row = 0 }
        let at = (Double(x), Double(y))
        x += uw
        row = max(row, uh)
        return at
    }
    var usedHeight: Int { y + row }
}

func buildAnimeModel(_ s: AnimeAnimalSpec) -> MobModel {
    var packer = UVPacker(width: 128)
    var placed: [PlacedBox] = []
    var pivots: [String: (Double, Double, Double)] = [:]
    var rots: [String: (Double, Double, Double)] = [:]
    var order: [String] = []

    func part(_ name: String, _ pivot: (Double, Double, Double), rot: (Double, Double, Double) = (0, 0, 0)) {
        pivots[name] = pivot
        rots[name] = rot
        order.append(name)
    }
    /// a box in `part`'s space (relative to its pivot)
    func add(_ p: String, _ role: Role, _ x: Double, _ y: Double, _ z: Double,
             _ w: Double, _ h: Double, _ d: Double, grow: Double = 0) {
        let (u, v) = packer.place(w, h, d)
        placed.append(PlacedBox(part: p, box: ModelBox(x, y, z, w, h, d, u, v, grow), role: role))
    }

    let (hw, hh, hd) = s.head
    let (bw, bh, bl) = s.body
    let lh = s.legH

    /// one leg hanging from the body's underside at (x, z): w wide, lh tall
    func leg(_ n: String, _ x: Double, _ z: Double, _ w: Double, _ role: Role = .leg) {
        part(n, (x, lh, z))
        add(n, role, -w / 2, -lh, -w / 2, w, lh, w)
    }
    /// four legs, inset from the body's corners; front and back can differ
    func fourLegs(front: Double, back: Double, inset: Double = 1.5, role: Role = .leg) {
        let fx = bw / 2 - max(inset, front / 2 + 0.5), bx = bw / 2 - max(inset, back / 2 + 0.5)
        let fz = -bl / 2 + max(inset, front / 2 + 0.5), bz = bl / 2 - max(inset, back / 2 + 0.5)
        leg("legFR", -fx, fz, front, role); leg("legFL", fx, fz, front, role)
        leg("legBR", -bx, bz, back, role); leg("legBL", bx, bz, back, role)
    }
    /// two bird legs with flat feet, and a wing or flipper on each side
    func birdLegsAndWings(wingH: Double, wingD: Double) {
        for (n, x) in [("legR", -bw / 4), ("legL", bw / 4)] {
            part(n, (x, lh, 0))
            add(n, .leg, -0.5, -lh, -0.5, 1, lh, 1)
            add(n, .foot, -1.5, -lh, -2.5, 3, 0.5, 3)
        }
        for (n, x, side) in [("wingR", -bw / 2, -1.0), ("wingL", bw / 2, 1.0)] {
            part(n, (x, lh + bh - 1, 0))
            add(n, .wing, side < 0 ? -1 : 0, -wingH, -wingD / 2, 1, wingH, wingD)
        }
    }

    // ---- each animal's body, legs, head position and tail -------------------
    var headPivot = (0.0, lh + bh * 0.55, -bl / 2 + 1.5)   // up on the front of the body
    var headZ = -hd + 2                                   // the head box's front face
    var tailBase = (0.0, lh + bh - 1.5, bl / 2)
    var tailThick = 3.0, tailLen = 5.0, tailTip = 2.0, tailPitch = -0.5
    part("body", (0, lh, 0))
    add("body", .body, -bw / 2, 0, -bl / 2, bw, bh, bl)
    switch s.shape {
    case .mound:
        // a soft round bun: rounded top, haunches at the back, big flat hind
        // feet and tiny front paws
        add("body", .body, -bw / 2 + 1, bh, -bl / 2 + 1, bw - 2, 1.5, bl - 2)
        add("body", .body, -bw / 2 - 1, 0, bl / 2 - 4.5, 1.5, 3.5, 4)
        add("body", .body, bw / 2 - 0.5, 0, bl / 2 - 4.5, 1.5, 3.5, 4)
        leg("legFR", -1.5, -bl / 2 + 1, 1.5); leg("legFL", 1.5, -bl / 2 + 1, 1.5)
        for (n, x) in [("legBR", -bw / 2 + 0.75), ("legBL", bw / 2 - 0.75)] {
            part(n, (x, lh, bl / 2 - 2))
            add(n, .leg, -1.25, -lh, -1.5, 2.5, lh, 3)
            add(n, .foot, -1.25, -lh, -4.5, 2.5, 1, 3)        // long flat hind foot
        }
        headPivot = (0, lh + bh * 0.7, -bl / 2 + 2)
        tailBase = (0, lh + bh * 0.6, bl / 2)
    case .slender:
        // a fox kit: narrow, deep chest, long thin legs, big brush tails
        add("body", .belly, -bw / 2 + 0.5, -0.5, -bl / 2 - 0.5, bw - 1, bh, 3)
        fourLegs(front: 1.5, back: 1.5)
        headPivot = (0, lh + bh * 0.7, -bl / 2 + 1)
        tailThick = 3.5; tailLen = 6; tailTip = 2.5
    case .sleek:
        // a cat: sleek and level, thin legs, a long thin tail held straight up
        fourLegs(front: 1.5, back: 1.5)
        headPivot = (0, lh + bh * 0.75, -bl / 2 + 1)
        tailThick = 1.5; tailLen = 8; tailTip = 1.5; tailPitch = -1.25
        tailBase = (0, lh + bh - 1, bl / 2 - 0.5)
    case .tubby:
        // a raccoon-dog: round pot belly sagging between stubby legs
        add("body", .belly, -bw / 2 + 1, 0.5, -bl / 2 - 1, bw - 2, bh - 2, 1.5)
        add("body", .belly, -bw / 2 + 1, -1, -bl / 2 + 1, bw - 2, 1.5, bl - 2)
        add("body", .body, -bw / 2 + 1, bh, -bl / 2 + 1, bw - 2, 1, bl - 2)
        fourLegs(front: 2.5, back: 2.5, inset: 1.5)
        headPivot = (0, lh + bh * 0.6, -bl / 2 + 1.5)
        tailThick = 4; tailLen = 6; tailPitch = -0.15
        tailBase = (0, lh + bh * 0.45, bl / 2)
    case .chunky:
        // a panda: big round body, black shoulder band and thick black legs
        add("body", .bodyDark, -bw / 2 + 0.5, bh, -bl / 2 + 0.5, bw - 1, 1.5, 5)
        add("body", .body, -bw / 2 + 1, bh, -bl / 2 + 5.5, bw - 2, 1, bl - 7)
        fourLegs(front: 3, back: 3, inset: 2, role: .legDark)
        headPivot = (0, lh + bh * 0.65, -bl / 2 + 1.5)
        tailThick = 2; tailLen = 2; tailPitch = -0.6
    case .ruff:
        // a shiba: compact, a fluffy white chest ruff, white socks, curled tail
        add("body", .belly, -bw / 2 - 0.5, 0, -bl / 2 - 1.5, bw + 1, bh - 0.5, 2.5)
        fourLegs(front: 2, back: 2, role: .legSock)
        headPivot = (0, lh + bh * 0.75, -bl / 2 + 1)
        tailThick = 3.5; tailLen = 4; tailPitch = -1.9
    case .long:
        // a red panda: long and low, dark legs, a huge ringed tail
        fourLegs(front: 2, back: 2, role: .legDark)
        headPivot = (0, lh + bh * 0.6, -bl / 2 + 1)
        tailThick = 4; tailLen = 10; tailPitch = -0.3
        tailBase = (0, lh + bh - 2, bl / 2)
    case .ball:
        // a hamster: nearly a ball, head sunk into the front, feet just peeking out
        add("body", .body, -bw / 2 + 1, bh, -bl / 2 + 1, bw - 2, 1, bl - 2)
        add("body", .belly, -bw / 2 + 1.5, 0.5, -bl / 2 - 0.5, bw - 3, bh - 2, 1)
        fourLegs(front: 1.5, back: 1.5, inset: 2)
        headPivot = (0, lh + 0.5, -bl / 2 + 2.5)
        headZ = -hd + 2.5
    case .egg:
        // a penguin: an upright egg, wider at the bottom, white belly bulge
        add("body", .body, -bw / 2 - 0.5, 0, -bl / 2 - 0.5, bw + 1, 3, bl + 1)
        add("body", .body, -bw / 2 + 1, bh, -bl / 2 + 1, bw - 2, 1, bl - 2)
        add("body", .belly, -bw / 2 + 1.5, 1, -bl / 2 - 1, bw - 3, bh - 2.5, 1)
        birdLegsAndWings(wingH: bh - 1.5, wingD: 3)
        headPivot = (0, lh + bh + 0.5, 0)
        headZ = -hd / 2
    case .puffball:
        // a chick: a fluffy ball on thin legs, tiny wings
        add("body", .body, -bw / 2 + 1, bh, -bl / 2 + 1, bw - 2, 1, bl - 2)
        add("body", .body, -bw / 2 + 1, -1, -bl / 2 + 1, bw - 2, 1, bl - 2)
        add("body", .body, -bw / 2 - 0.5, 1, -bl / 2 + 1, bw + 1, bh - 2, bl - 2)
        birdLegsAndWings(wingH: 3, wingD: 3)
        headPivot = (0, lh + bh, 0)
        headZ = -hd / 2
    }

    // ---- head and face ---------------------------------------------------
    part("head", headPivot)
    add("head", .head, -hw / 2, 0, headZ, hw, hh, hd)
    if s.muzzle == .snout {
        add("head", .snout, -1.5, 0.5, headZ - 2, 3, 2, 2)
    }
    if s.muzzle == .beak {
        add("head", .beak, -1, hh / 2 - 1.5, headZ - 1.5, 2, 1.5, 1.5)
    }
    switch s.extra {
    case .cheeks:
        add("head", .cheek, -hw / 2 - 1, 0.5, headZ + 1, 2, 3, 3)
        add("head", .cheek, hw / 2 - 1, 0.5, headZ + 1, 2, 3, 3)
    case .bell:
        add("head", .collar, -hw / 2 + 1, -1, headZ + 1, hw - 2, 1, hd - 2, grow: 0.25)
        add("head", .bell, -1, -2.5, headZ, 2, 2, 1.5)
    case .leaf:
        add("head", .leaf, -2, hh, headZ + 1.5, 4, 1, 3)
    case .scarf:
        // a red band where head meets body, its end hanging down the chest
        add("body", .scarf, -bw / 2 - 0.5, bh - 2, -bl / 2 - 0.5, bw + 1, 2, bl + 1)
        add("body", .scarf, bw / 4 - 1, bh - 6, -bl / 2 - 0.7, 2, 4, 1)
    case .none, .pandaPatches, .mask:
        break
    }

    // ---- ears (their own parts so they can twitch; they turn with the head) --
    let earZ = headZ + hd / 2 - 1
    switch s.ears {
    case .none:
        break
    case .tall:
        for (n, x) in [("earR", -hw / 2 + 0.5), ("earL", hw / 2 - 2.5)] {
            part(n, headPivot)
            add(n, .ear, x, hh, earZ, 2, 6, 1)
        }
    case .pointed:
        for (n, x) in [("earR", -hw / 2), ("earL", hw / 2 - 3)] {
            part(n, headPivot)
            add(n, .ear, x, hh, earZ, 3, 3, 1)
        }
    case .round:
        for (n, x) in [("earR", -hw / 2 - 0.5), ("earL", hw / 2 - 2.5)] {
            part(n, headPivot)
            add(n, .ear, x, hh - 0.5, earZ, 3, 2.5, 1)
        }
    case .tuft:
        part("earR", headPivot)
        add("earR", .tuft, -0.5, hh, earZ - 1, 1, 2.5, 1)
        add("earR", .tuft, 0.5, hh, earZ, 1, 1.5, 1)
    }

    // ---- tails (sized and angled by the body shape above) ----------------------
    let half = tailThick / 2
    /// a tail from tailBase, with a tip `tip` long, inset `inset` on each side
    func tail(_ n: String, rot: (Double, Double, Double), tip: Double = 0, inset: Double = 0) {
        part(n, tailBase, rot: rot)
        add(n, .tail, -half, -half, 0, tailThick, tailThick, tailLen)
        if tip > 0 {
            add(n, .tailTip, -half + inset, -half + inset, tailLen, tailThick - 2 * inset, tailThick - 2 * inset, tip)
        }
    }
    switch s.tail {
    case .none:
        break
    case .puff:
        part("tail", tailBase)
        add("tail", .tailTip, -1.5, -1.5, -0.5, 3, 3, 2)
    case .stub, .ringed:   // the ringed one is painted with rings
        tail("tail", rot: (tailPitch, 0, 0))
    case .thin:
        tail("tail", rot: (tailPitch, 0, 0), tip: tailTip)
    case .triple:
        for (n, yaw) in [("tail", 0.0), ("tail2", -0.6), ("tail3", 0.6)] {
            tail(n, rot: (-0.95, yaw, 0), tip: tailTip)   // fanned up and out
        }
    case .curl:
        // up over the back, the way a shiba carries it
        tail("tail", rot: (tailPitch, 0, 0), tip: 2, inset: 0.5)
    }

    let texH = max(32, ((packer.usedHeight + 15) / 16) * 16)
    let parts = order.map { n in
        ModelPart(name: n, pivot: pivots[n]!, rot: rots[n]!,
                  boxes: placed.filter { $0.part == n }.map { $0.box })
    }
    let anim = s.plan == .biped ? "chibi_waddle" : (s.ears == .tall ? "chibi_hop" : "chibi")
    let boxes = placed
    return MobModel(texW: 128, texH: texH, parts: parts, anim: anim, scale: 1,
                    paint: { skin in paintAnime(skin, s, boxes) })
}

// ---------------------------------------------------------------------------
// skins
// ---------------------------------------------------------------------------

private func paintAnime(_ k: EntitySkin, _ s: AnimeAnimalSpec, _ boxes: [PlacedBox]) {
    for pb in boxes {
        let b = pb.box
        let u = Int(b.u), v = Int(b.v)
        let w = Int(b.w.rounded(.up)), h = Int(b.h.rounded(.up)), d = Int(b.d.rounded(.up))
        // faces of a box-UV unwrap
        let top = (u + d, v), bottom = (u + d + w, v)
        let front = (u + d, v + d), back = (u + 2 * d + w, v + d)
        let right = (u, v + d), left = (u + d + w, v + d)
        switch pb.role {
        case .head:
            k.box(u, v, w, h, d, s.fur, 0.05)
            paintFace(k, s, front.0, front.1, w, h)
        case .snout:
            k.box(u, v, w, h, d, s.light, 0.04)
            k.rect(front.0 + w / 2 - 1, front.1, 2, 1, 0x2a1c1c)                 // nose
            k.px(front.0 + w / 2 - 1, front.1 + h - 1, 0x8a3a3a)                 // mouth
            k.px(front.0 + w / 2, front.1 + h - 1, 0x8a3a3a)
        case .beak:
            k.box(u, v, w, h, d, s.dark, 0.04)
        case .ear:
            k.box(u, v, w, h, d, s.ears == .round && s.extra == .pandaPatches ? s.dark : s.fur, 0.05)
            // pink lining on the face side (the back stays plain fur, or from
            // behind the ears read as a second pair of eyes); dark tips on top
            if w >= 2 && h >= 2 {
                k.fill(front.0 + (w > 2 ? 1 : 0), front.1 + 1, max(1, w - 2), max(1, h - 1),
                       s.ears == .tall ? s.accent : 0xf4b4c4, 0.04)
            }
            if s.ears == .pointed { k.rect(top.0, top.1, w, d, s.dark) }
        case .tuft:
            k.box(u, v, w, h, d, s.accent, 0.04)
        case .body:
            k.box(u, v, w, h, d, s.fur, 0.06)
            if s.plan == .biped {
                // white/light belly down the front
                k.fill(front.0 + 1, front.1 + 1, max(1, w - 2), max(1, h - 1), s.light, 0.03)
            } else {
                k.fill(bottom.0, bottom.1, w, d, s.light, 0.04)                  // belly
                k.fill(front.0 + 1, front.1 + 1, max(1, w - 2), max(1, h - 2), s.light, 0.04) // chest
            }
            if s.extra == .pandaPatches {
                // black shoulder band, like a panda's
                let band = min(4, d / 3)
                k.fill(top.0, top.1, w, band, s.dark, 0.04)
                k.fill(right.0, right.1, band, h, s.dark, 0.04)
                k.fill(left.0 + d - band, left.1, band, h, s.dark, 0.04)
                k.fill(front.0, front.1, w, h, s.dark, 0.04)
            }
        case .belly:
            k.box(u, v, w, h, d, s.light, 0.04)
        case .bodyDark:
            k.box(u, v, w, h, d, s.dark, 0.05)
        case .leg, .legDark, .legSock:
            let c = s.plan == .biped || pb.role == .legDark ? s.dark : s.fur
            k.box(u, v, w, h, d, c, 0.05)
            if pb.role == .legSock {
                // white socks on the lower half of each leg
                let sock = max(1, h / 2)
                for (fx, fw) in [(right.0, d), (front.0, w), (left.0, d), (back.0, w)] {
                    k.fill(fx, front.1 + h - sock, fw, sock, s.light, 0.03)
                }
                k.fill(bottom.0, bottom.1, w, d, s.light, 0.03)
            } else {
                k.fill(front.0, front.1 + h - 1, w, 1, shadeColor(c, 0.8), 0.03)     // paw
            }
        case .foot:
            k.box(u, v, w, h, d, s.dark, 0.04)
        case .tail:
            k.box(u, v, w, h, d, s.fur, 0.06)
            if s.tail == .ringed {
                // rings across the tail's length (the faces run along z)
                for i in stride(from: 1, to: d, by: 2) {
                    k.fill(top.0, top.1 + i, w, 1, s.accent, 0.03)
                    k.fill(bottom.0, bottom.1 + i, w, 1, s.accent, 0.03)
                    k.fill(right.0 + i, right.1, 1, h, s.accent, 0.03)
                    k.fill(left.0 + d - 1 - i, left.1, 1, h, s.accent, 0.03)
                }
                k.fill(back.0, back.1, w, h, s.accent, 0.03)
            }
        case .tailTip:
            k.box(u, v, w, h, d, s.tail == .puff ? s.light : s.accent, 0.04)
        case .wing:
            k.box(u, v, w, h, d, shadeColor(s.fur, 0.9), 0.05)
        case .cheek:
            // halfway between fur and belly, so the pouches read as cheeks
            let mid = (((s.fur >> 16 & 255) + (s.light >> 16 & 255)) / 2) << 16
                | (((s.fur >> 8 & 255) + (s.light >> 8 & 255)) / 2) << 8 | ((s.fur & 255) + (s.light & 255)) / 2
            k.box(u, v, w, h, d, mid, 0.04)
            k.fill(right.0, right.1 + 1, d, 1, s.accent, 0.03)
            k.fill(left.0, left.1 + 1, d, 1, s.accent, 0.03)
        case .collar:
            k.box(u, v, w, h, d, 0xd0303a, 0.04)
        case .bell:
            k.box(u, v, w, h, d, 0xf2c838, 0.04)
            k.px(front.0, front.1, 0xfff4b0)
            k.px(front.0 + w / 2, front.1 + h - 1, 0x8a6a10)
        case .leaf:
            k.box(u, v, w, h, d, 0x5cb840, 0.06)
            k.fill(top.0 + w / 2, top.1, 1, d, 0x3a8a2a, 0.02)                   // midrib
        case .scarf:
            k.box(u, v, w, h, d, s.accent, 0.05)
            k.fill(front.0, front.1 + h - 1, w, 1, shadeColor(s.accent, 0.75), 0.02)
        }
    }
}

/// big anime eyes with a highlight, blush and a little mouth on a head's front face
private func paintFace(_ k: EntitySkin, _ s: AnimeAnimalSpec, _ fu: Int, _ fv: Int, _ w: Int, _ h: Int) {
    let eyeW = 2, eyeH = h >= 8 ? 4 : 3
    let eyeY = fv + max(1, h / 2 - 2)
    let gap = w >= 9 ? 3 : 2
    let leftX = fu + w / 2 - gap / 2 - eyeW, rightX = fu + w / 2 + (gap + 1) / 2
    // markings under the eyes first, so the eyes sit on top
    if s.extra == .pandaPatches {
        k.rect(leftX - 1, eyeY - 1, eyeW + 2, eyeH + 2, s.dark)
        k.rect(rightX - 1, eyeY - 1, eyeW + 2, eyeH + 2, s.dark)
    }
    if s.extra == .mask {
        // red panda: white brows and cheeks around a russet mask
        k.rect(leftX - 1, eyeY - 2, eyeW + 1, 1, s.light)
        k.rect(rightX, eyeY - 2, eyeW + 1, 1, s.light)
        k.rect(fu, eyeY + eyeH, 2, 2, s.light)
        k.rect(fu + w - 2, eyeY + eyeH, 2, 2, s.light)
    }
    if s.muzzle == .snout {
        // a light muzzle patch around the snout
        k.rect(fu + w / 2 - 2, fv + h - 3, 4, 3, s.light)
    }
    if s.raccoonMask {
        k.rect(fu + 1, eyeY - 1, w - 2, eyeH + 1, s.accent) // raccoon-dog mask, a shade off the eyes
    }
    for x in [leftX, rightX] {
        k.rect(x, eyeY, eyeW, eyeH, 0x1c1418)                      // dark of the eye
        k.rect(x, eyeY + eyeH - 1, eyeW, 1, s.iris)                // iris glow at the bottom
        k.px(x, eyeY, 0xffffff)                                     // sparkle
    }
    // blush
    let blush = 0xf58aa8
    k.rect(leftX - 1, eyeY + eyeH, 2, 1, blush)
    k.rect(rightX + eyeW - 1, eyeY + eyeH, 2, 1, blush)
    if s.muzzle == .none {
        // a small cat-like mouth
        let my = min(fv + h - 1, eyeY + eyeH + 1)
        k.px(fu + w / 2 - 1, my, 0x7a2a3a)
        k.px(fu + w / 2, my, 0x7a2a3a)
        if s.ears == .tall { k.px(fu + w / 2 - 1, my - 1, s.accent); k.px(fu + w / 2, my - 1, s.accent) } // bunny nose
    }
}
