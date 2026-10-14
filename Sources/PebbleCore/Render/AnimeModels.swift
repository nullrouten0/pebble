// Models and painted skins for the anime-style animals (Entity/AnimeAnimals.swift).
// Each animal is built from its spec: a big head on a small body (four legs,
// or two legs and flippers/wings), ears, a tail and a few extras, laid out on
// a box-UV sheet by a shelf packer, then painted to match — big sparkly eyes,
// blush, lighter belly. They have no pack texture: the painted skin is the art.
// Animated by the "chibi" profiles in PebbleApp/EntityRendererM.swift.

import Foundation

/// what a box is for, so the painter knows how to colour it
private enum Role {
    case head, snout, beak, ear, body, leg, foot, tail, tailTip, wing, cheek, collar, bell, leaf, scarf, tuft
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

    // ---- body, legs and where the head sits ---------------------------------
    let headPivot: (Double, Double, Double)
    let headZ: Double   // the head box's back-to-front placement (front face at headZ)
    switch s.plan {
    case .quad:
        part("body", (0, lh, 0))
        add("body", .body, -bw / 2, 0, -bl / 2, bw, bh, bl)
        let lx = bw / 2 - 1.5, lz = bl / 2 - 1.5
        for (n, x, z) in [("legFR", -lx, -lz), ("legFL", lx, -lz), ("legBR", -lx, lz), ("legBL", lx, lz)] {
            part(n, (x, lh, z))
            add(n, .leg, -1, -lh, -1, 2, lh, 2)
        }
        // the head sits up on the front of the body, overlapping it
        headPivot = (0, lh + bh * 0.55, -bl / 2 + 1.5)
        headZ = -hd + 2
    case .biped:
        part("body", (0, lh, 0))
        add("body", .body, -bw / 2, 0, -bl / 2, bw, bh, bl)
        for (n, x) in [("legR", -bw / 4), ("legL", bw / 4)] {
            part(n, (x, lh, 0))
            add(n, .leg, -0.5, -lh, -0.5, 1, lh, 1)
            add(n, .foot, -1.5, -lh, -2.5, 3, 0.5, 3)
        }
        for (n, x, side) in [("wingR", -bw / 2, -1.0), ("wingL", bw / 2, 1.0)] {
            part(n, (x, lh + bh - 1, 0))
            add(n, .wing, side < 0 ? -1 : 0, -(bh - 2), -bl / 2 + 1.5, 1, bh - 2, bl - 3)
        }
        headPivot = (0, lh + bh, 0)
        headZ = -hd / 2
    }

    // ---- head and face ---------------------------------------------------
    part("head", headPivot)
    add("head", .head, -hw / 2, 0, headZ, hw, hh, hd)
    if s.snout {
        add("head", .snout, -1.5, 0.5, headZ - 2, 3, 2, 2)
    }
    if s.beak {
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

    // ---- tails ---------------------------------------------------------------
    let tailBase: (Double, Double, Double) = s.plan == .quad ? (0, lh + bh - 1.5, bl / 2) : (0, lh + 1.5, bl / 2)
    switch s.tail {
    case .none:
        break
    case .puff:
        part("tail", tailBase)
        add("tail", .tailTip, -1.5, -1.5, -0.5, 3, 3, 2)
    case .stub:
        part("tail", tailBase, rot: (-0.5, 0, 0))
        add("tail", .tail, -1, -1, 0, 2, 2, 3)
    case .fluffy:
        part("tail", tailBase, rot: (-0.35, 0, 0))
        add("tail", .tail, -1.5, -1.5, 0, 3, 3, 5)
        add("tail", .tailTip, -1.5, -1.5, 5, 3, 3, 2)
    case .triple:
        for (n, yaw) in [("tail", 0.0), ("tail2", -0.55), ("tail3", 0.55)] {
            part(n, tailBase, rot: (-0.95, yaw, 0))   // fanned up and out
            add(n, .tail, -1.5, -1.5, 0, 3, 3, 5)
            add(n, .tailTip, -1.5, -1.5, 5, 3, 3, 2)
        }
    case .curl:
        // up over the back, the way a shiba carries it
        part("tail", tailBase, rot: (-1.9, 0, 0))
        add("tail", .tail, -1.5, -1.5, 0, 3, 3, 4)
        add("tail", .tailTip, -1, -1, 4, 2, 2, 2)
    case .ringed:
        part("tail", tailBase, rot: (-0.55, 0, 0))
        add("tail", .tail, -1.5, -1.5, 0, 3, 3, 7)
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
        case .leg:
            let c = s.plan == .biped ? s.dark : (s.extra == .pandaPatches || s.extra == .mask ? s.dark : s.fur)
            k.box(u, v, w, h, d, c, 0.05)
            k.fill(front.0, front.1 + h - 1, w, 1, shadeColor(c, 0.8), 0.03)     // paw
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
            k.box(u, v, w, h, d, s.light, 0.04)
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
    if s.snout {
        // a light muzzle patch around the snout
        k.rect(fu + w / 2 - 2, fv + h - 3, 4, 3, s.light)
    }
    if s.id == "leaf_tanuki" {
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
    if !s.snout && !s.beak {
        // a small cat-like mouth
        let my = min(fv + h - 1, eyeY + eyeH + 1)
        k.px(fu + w / 2 - 1, my, 0x7a2a3a)
        k.px(fu + w / 2, my, 0x7a2a3a)
        if s.ears == .tall { k.px(fu + w / 2 - 1, my - 1, s.accent); k.px(fu + w / 2, my - 1, s.accent) } // bunny nose
    }
}
