// Models for the flying mounts (Entity/FlyingMounts.swift): the pegasus (the
// horse rig plus feathered wings), the alicorn (the same with a horn), the
// dragon, the griffin, and a saddle for each, drawn
// over a saddled mount with the same pose. Wing panels are flat planes whose
// feather tips and membrane scallops are cut out of the skin (the entity
// shader drops clear pixels). Animated by the "pegasus", "mount_dragon" and
// "griffin" profiles (PebbleApp/EntityRendererM.swift), which fold the wings along the
// body on the ground and spread and flap them in flight (data.wings).

import Foundation

private func part(_ name: String, _ pivot: (Double, Double, Double), _ boxes: ModelBox...) -> ModelPart {
    ModelPart(name: name, pivot: pivot, boxes: boxes)
}
private func rpart(_ name: String, _ pivot: (Double, Double, Double), _ rot: (Double, Double, Double), _ boxes: ModelBox...) -> ModelPart {
    ModelPart(name: name, pivot: pivot, rot: rot, boxes: boxes)
}
private func box(_ x: Double, _ y: Double, _ z: Double, _ w: Double, _ h: Double, _ d: Double, _ u: Double, _ v: Double) -> ModelBox {
    ModelBox(x, y, z, w, h, d, u, v)
}

/// paint a flat wing panel (a box with no height) at box-UV (u, v), `w` along
/// the span and `d` along the chord. `chord(c)` is how far back the panel
/// reaches at span column c, counted from the wingtip; past it stays clear.
/// `tipFirst`: the wingtip is at the panel's low-u end (a wing reaching to -x).
private func paintPanel(_ s: EntitySkin, _ u: Int, _ v: Int, _ w: Int, _ d: Int, tipFirst: Bool,
                        _ chord: (Int) -> Int, _ color: (Int, Int) -> Int) {
    for col in 0..<w {
        let fromTip = tipFirst ? col : w - 1 - col
        let reach = min(d, chord(fromTip))
        for row in 0..<reach {
            // top face: the leading edge is the first row; bottom face: the last
            s.px(u + d + col, v + row, color(fromTip, row))
            s.px(u + d + w + col, v + d - 1 - row, shadeColor(color(fromTip, row), 0.86))
        }
    }
}

func registerMountModels() {
    // ---- pegasus and alicorn: the horse rig (same UVs) with feathered wings
    // at u 64+; the alicorn adds a spiral horn (u 24, v 0) ----
    func winged(_ name: String, coat: Int, mane: Int, hoof: Int, feather: Int, horn: Int?) {
        func wingBoxes(_ right: Bool, _ v: Double) -> [ModelBox] {
            // a leading-edge bar and the feather panel behind it, reaching 20 out
            right ? [box(-20, -1, -1.5, 20, 2.5, 3, 64, v), box(-20, 0, 1.5, 20, 0, 14, 64, v + 6)]
                  : [box(0, -1, -1.5, 20, 2.5, 3, 64, v), box(0, 0, 1.5, 20, 0, 14, 64, v + 6)]
        }
        var head = [box(-2.05, -5, -2, 4.1, 14.8, 8, 0, 35),
                    box(-3, 6, -2, 6, 5, 7, 0, 13),
                    box(-2, 6, -7, 4, 5, 5, 0, 25),
                    box(-1, -5, 5.01, 2, 16, 2, 56, 36),
                    box(0.55, 10, 4, 2, 3, 1, 19, 16),
                    box(-2.55, 10, 4, 2, 3, 1, 29, 16)]
        if horn != nil {
            // rises from the forehead; the head's tilt leans it forward
            head += [box(-0.75, 11, -1.5, 1.5, 3, 1.5, 24, 0), box(-0.5, 14, -1.25, 1, 3.5, 1, 32, 0)]
        }
        M2(name, MobModel(
            texW: 128, texH: 64,
            parts: [
                ModelPart(name: "head", pivot: (0, 20, -12), rot: (-0.5236, 0, 0), boxes: head),
                part("body", (0, 13, 5), box(-5, -2, -19, 10, 10, 22, 0, 32)),
                rpart("tail", (0, 19, 9), (-0.5, 0, 0), box(-1.5, -14, 0, 3, 14, 4, 42, 36)),
                part("legFR", (-4, 11, -8), box(-2, -11, -2, 4, 11, 4, 48, 21)),
                part("legFL", (4, 11, -8), box(-2, -11, -2, 4, 11, 4, 48, 21)),
                part("legBR", (-4, 11, 9), box(-2, -11, -2, 4, 11, 4, 48, 21)),
                part("legBL", (4, 11, 9), box(-2, -11, -2, 4, 11, 4, 48, 21)),
                ModelPart(name: "wingR", pivot: (-4.5, 20, -6), boxes: wingBoxes(true, 0)),
                ModelPart(name: "wingL", pivot: (4.5, 20, -6), boxes: wingBoxes(false, 32)),
            ],
            anim: "pegasus", scale: 1,
            paint: { s in
                s.box(0, 35, 4, 15, 8, coat, 0.06)   // neck
                s.box(0, 13, 6, 5, 7, coat, 0.06)    // head
                s.px(2, 20, 0x2a3a5c); s.px(17, 20, 0x2a3a5c)
                s.box(0, 25, 4, 5, 5, shadeColor(coat, 0.95), 0.06)   // muzzle
                s.box(56, 36, 2, 16, 2, mane, 0.12)  // mane
                s.box(19, 16, 2, 3, 1, shadeColor(coat, 0.9))
                s.box(29, 16, 2, 3, 1, shadeColor(coat, 0.9))
                s.box(0, 32, 10, 10, 22, coat, 0.06) // body
                s.box(42, 36, 3, 14, 4, mane, 0.12)  // tail
                s.box(48, 21, 4, 11, 4, coat, 0.06)  // legs
                s.fill(48, 21 + 4 + 9, 16, 2, hoof, 0.08)   // hooves
                if let horn {
                    // a pale spiral: every other row darker, round the horn
                    s.box(24, 0, 2, 3, 2, horn, 0.04)
                    s.box(32, 0, 1, 4, 1, horn, 0.04)
                    for (u, w, h) in [(24, 8, 5), (32, 4, 5)] {
                        for y in stride(from: 1, to: h, by: 2) { s.fill(u, y, w, 1, shadeColor(horn, 0.8), 0) }
                    }
                }
                // wings: bar, then feathers — primaries longest at the tip, ragged
                // ends, a vane line down every other feather
                for (v, tipFirst) in [(0, true), (32, false)] {
                    s.box(64, v, 20, 3, 3, shadeColor(feather, 0.97), 0.05)
                    paintPanel(s, 64, v + 6, 20, 14, tipFirst: tipFirst, { c in
                        14 - c / 5 - (c % 2 == 0 ? 0 : 1) - (c % 4 == 1 ? 1 : 0)
                    }) { c, row in
                        let base = row < 4 ? shadeColor(feather, 1.04) : feather
                        return c % 2 == 0 && row > 2 ? shadeColor(base, 0.9) : base
                    }
                }
            }))
    }
    winged("pegasus", coat: 0xf2f0ea, mane: 0xe6c15a, hoof: 0x8c8478, feather: 0xf2f0ea, horn: nil)
    winged("alicorn", coat: 0xece0f8, mane: 0xb46ad8, hoof: 0x9a86b0, feather: 0xe2d2f6, horn: 0xf6e7a6)

    // ---- griffin: an eagle's white head, hooked beak, brown wings and
    // yellow taloned forelegs on a tawny lion's body with a tufted tail ----
    let tawny = 0xc8954f, eagleWhite = 0xf4efe4, brown = 0x7a5232, gold = 0xe8b23a, tuft = 0x5a3a1e
    M2("griffin", MobModel(
        texW: 128, texH: 64,
        parts: [
            part("body", (0, 14, 2), box(-5, -5, -10, 10, 10, 20, 0, 32)),
            part("head", (0, 21, -8),
                 box(-3.5, -2, -7, 7, 7, 7, 0, 0),           // skull
                 box(-1.5, 0, -11, 3, 3, 4, 30, 0),          // upper beak
                 box(-1.5, -1, -11, 3, 1, 1, 30, 8),         // its hook
                 box(-3, 5, -2, 1, 3, 2, 46, 0), box(2, 5, -2, 1, 3, 2, 46, 0)),   // ear tufts
            part("jaw", (0, 21, -8), box(-1.25, -1, -10.5, 2.5, 1, 3.5, 30, 10)),
            rpart("tail", (0, 18, 12), (-0.3, 0, 0), box(-1, -12, 0, 2, 12, 2, 32, 16), box(-1.5, -15, -0.5, 3, 3, 3, 42, 16)),
            part("legFR", (-3.5, 10, -5), box(-1.5, -10, -1.5, 3, 10, 3, 0, 16)),
            part("legFL", (3.5, 10, -5), box(-1.5, -10, -1.5, 3, 10, 3, 0, 16)),
            part("legBR", (-3.5, 10, 9), box(-2, -10, -2, 4, 10, 4, 14, 16)),
            part("legBL", (3.5, 10, 9), box(-2, -10, -2, 4, 10, 4, 14, 16)),
            ModelPart(name: "wingR", pivot: (-5, 18, -5), boxes: [box(-22, -1, -1.5, 22, 2.5, 3, 64, 0), box(-22, 0, 1.5, 22, 0, 15, 64, 6)]),
            ModelPart(name: "wingL", pivot: (5, 18, -5), boxes: [box(0, -1, -1.5, 22, 2.5, 3, 64, 32), box(0, 0, 1.5, 22, 0, 15, 64, 38)]),
        ],
        anim: "griffin", scale: 1,
        paint: { s in
            // body: lion behind, eagle feathers over the front third
            s.box(0, 32, 10, 10, 20, tawny, 0.08)
            s.fill(20, 32 + 20, 10, 10, eagleWhite, 0.06)                // chest (front face)
            s.fill(20 - 7, 32 + 20, 7, 10, eagleWhite, 0.08)             // one flank's front
            s.fill(30, 32 + 20, 7, 10, eagleWhite, 0.08)                 // the other's
            s.fill(20, 32, 10, 7, eagleWhite, 0.08)                      // the back's front
            s.fill(30, 32, 10, 7, shadeColor(eagleWhite, 0.9), 0.08)     // the belly's
            // head: white, amber eyes on the sides, a dark brow
            s.box(0, 0, 7, 7, 7, eagleWhite, 0.05)
            s.rect(2, 7 + 2, 2, 2, 0xf2a020); s.px(2, 7 + 2, 0x1a1a1a)
            s.rect(7 + 7 + 3, 7 + 2, 2, 2, 0xf2a020); s.px(7 + 7 + 4, 7 + 2, 0x1a1a1a)
            s.fill(1, 7 + 1, 4, 1, shadeColor(eagleWhite, 0.7)); s.fill(7 + 7 + 2, 7 + 1, 4, 1, shadeColor(eagleWhite, 0.7))
            s.box(30, 0, 3, 3, 4, gold, 0.05)
            s.box(30, 8, 3, 1, 1, shadeColor(gold, 0.6), 0.05)
            s.box(30, 10, 3, 1, 4, shadeColor(gold, 0.9), 0.05)
            s.box(46, 0, 1, 3, 2, eagleWhite, 0.06)
            // legs: yellow scaled forelegs with dark talons, tawny hind legs with pale paws
            s.box(0, 16, 3, 10, 3, gold, 0.1)
            s.fill(0, 16 + 3 + 8, 12, 2, 0x2a2420, 0.05)
            s.box(14, 16, 4, 10, 4, tawny, 0.08)
            s.fill(14, 16 + 4 + 8, 16, 2, shadeColor(tawny, 1.12), 0.05)
            s.box(32, 16, 2, 12, 2, tawny, 0.08)
            s.box(42, 16, 3, 3, 3, tuft, 0.12)
            // wings: brown, banded, lighter leading edge
            for (v, tipFirst) in [(0, true), (32, false)] {
                s.box(64, v, 22, 3, 3, shadeColor(brown, 1.15), 0.06)
                paintPanel(s, 64, v + 6, 22, 15, tipFirst: tipFirst, { c in
                    15 - c / 5 - (c % 2 == 0 ? 0 : 1) - (c % 4 == 1 ? 1 : 0)
                }) { c, row in
                    let base = row < 4 ? shadeColor(brown, 1.2) : (row % 5 == 4 ? shadeColor(brown, 0.75) : brown)
                    return c % 2 == 0 && row > 2 ? shadeColor(base, 0.9) : base
                }
            }
        }))

    // ---- dragon: emerald scales, a cream belly, a jaw that opens to breathe ----
    let scale = 0x2e8a4c, belly = 0xe4d29a, dark = 0x1d5a33, horn = 0xefe6c8, membrane = 0x47a86a
    M2("dragon", MobModel(
        texW: 128, texH: 128,
        parts: [
            part("body", (0, 13, 0), box(-6, -5, -9, 12, 10, 24, 0, 0),
                 box(-1, 5, -6, 2, 3, 3, 72, 0), box(-1, 5, 1, 2, 3, 3, 72, 0), box(-1, 5, 8, 2, 3, 3, 72, 0)),
            rpart("neck", (0, 15, -8), (0.6, 0, 0), box(-3, -3, -10, 6, 6, 10, 0, 34),
                  box(-0.5, 3, -8, 1, 2, 3, 72, 0)),
            part("head", (0, 20, -15),
                 box(-4, -2.5, -7, 8, 6, 7, 0, 50),        // skull
                 box(-2.5, -2.5, -13, 5, 3.5, 6, 30, 50),  // snout
                 box(-3.5, 3, -1, 1.5, 1.5, 6, 52, 50), box(2, 3, -1, 1.5, 1.5, 6, 52, 50)),  // horns
            part("jaw", (0, 20, -15), box(-2.5, -4, -12, 5, 1.5, 11, 0, 64)),
            part("tail1", (0, 13, 14), box(-3, -3, 0, 6, 5, 9, 72, 10)),
            part("tail2", (0, 12.5, 22), box(-2, -2, 0, 4, 4, 9, 72, 24)),
            part("tail3", (0, 12, 30), box(-1.5, -1.5, 0, 3, 3, 9, 72, 37), box(-3, 0, 6, 6, 0, 6, 100, 37)),
            part("legFR", (-4.5, 9, -5), box(-2, -9, -2, 4, 9, 4, 0, 80)),
            part("legFL", (4.5, 9, -5), box(-2, -9, -2, 4, 9, 4, 0, 80)),
            part("legBR", (-5, 10, 9), box(-2.5, -10, -2.5, 5, 10, 5, 20, 80)),
            part("legBL", (5, 10, 9), box(-2.5, -10, -2.5, 5, 10, 5, 20, 80)),
            part("wingR", (-5, 17, -5), box(-30, -1, -1, 30, 2, 2, 0, 96), box(-30, 0, 1, 30, 0, 22, 0, 100)),
            part("wingL", (5, 17, -5), box(0, -1, -1, 30, 2, 2, 64, 96), box(0, 0, 1, 30, 0, 22, 40, 64)),
        ],
        anim: "mount_dragon", scale: 1.25,
        paint: { s in
            s.box(0, 0, 12, 10, 24, scale, 0.12)
            s.fill(24 + 12, 0, 12, 24, belly, 0.08)    // underside
            s.box(72, 0, 2, 3, 3, horn, 0.08)           // back spines
            s.box(0, 34, 6, 6, 10, scale, 0.12)
            s.fill(10 + 6, 34, 6, 10, belly, 0.08)     // throat
            s.box(0, 50, 8, 6, 7, scale, 0.12)
            // eyes: amber, slit pupils, one on each side of the skull
            s.rect(1, 50 + 7 + 1, 2, 2, 0xf2b632); s.px(2, 58, 0x1a1a1a)
            s.rect(7 + 8 + 4, 50 + 7 + 1, 2, 2, 0xf2b632); s.px(7 + 8 + 4, 58, 0x1a1a1a)
            s.box(30, 50, 5, 3, 6, scale, 0.12)
            s.px(30 + 6 + 1, 50 + 6, 0x111111); s.px(30 + 6 + 3, 50 + 6, 0x111111)   // nostrils
            s.box(52, 50, 1, 1, 6, horn, 0.06)
            s.box(0, 64, 5, 1, 11, belly, 0.08)
            s.fill(11, 64, 5, 11, 0xb83a2a, 0.1)        // inside of the mouth
            s.box(72, 10, 6, 5, 9, scale, 0.12)
            s.box(72, 24, 4, 4, 9, scale, 0.12)
            s.box(72, 37, 3, 3, 9, scale, 0.12)
            s.fill(106, 37, 6, 6, dark, 0.1); s.fill(112, 37, 6, 6, dark, 0.1)   // tail spade
            s.box(0, 80, 4, 9, 4, scale, 0.12)
            s.box(20, 80, 5, 10, 5, scale, 0.12)
            s.fill(4, 80 + 4 + 7, 4, 2, horn, 0.05); s.fill(25, 80 + 5 + 8, 5, 2, horn, 0.05)   // claws
            // wings: a dark bone along the front; membranes narrow to the tip,
            // scalloped between four finger bones that fan out from the root
            s.box(0, 96, 30, 2, 2, dark, 0.1)
            s.box(64, 96, 30, 2, 2, dark, 0.1)
            func chord(_ c: Int) -> Int {
                let base = 7.0 + 15.0 * Double(c) / 29
                let f = Double(c % 8) / 8
                return Int(base - 3.5 * detSin(f * .pi))
            }
            func skin(_ c: Int, _ row: Int) -> Int {
                // a finger bone where the column is a multiple of 8 from the tip
                c % 8 == 0 && row > 0 ? dark : (row == 0 ? shadeColor(membrane, 0.8) : membrane)
            }
            paintPanel(s, 0, 100, 30, 22, tipFirst: true, chord, skin)
            paintPanel(s, 40, 64, 30, 22, tipFirst: false, chord, skin)
        }))

    // ---- saddles, drawn over a saddled mount ----
    let leather = 0x7a4a26, trim = 0x4a2c16, metal = 0xb8b8c0
    M2("pegasus_saddle", MobModel(
        texW: 64, texH: 32,
        parts: [
            part("body", (0, 13, 5),
                 box(-5.5, 8, -12, 11, 1, 10, 0, 0),       // seat
                 box(-5.6, 2, -9, 0.5, 6, 4, 0, 12), box(5.1, 2, -9, 0.5, 6, 4, 0, 12),   // flaps
                 box(-1, 9, -12.5, 2, 1.5, 1.5, 30, 12)),   // pommel
        ],
        anim: "none", scale: 1,
        paint: { s in
            s.box(0, 0, 11, 1, 10, leather, 0.08)
            s.fill(10, 0, 11, 1, trim, 0.05)
            s.box(0, 12, 1, 6, 4, trim, 0.08)
            s.box(30, 12, 2, 2, 2, metal, 0.05)
        }))
    // the alicorn wears the pegasus's saddle; the griffin's sits behind its wings
    M2("alicorn_saddle", MODELS["pegasus_saddle"]!)
    M2("griffin_saddle", MobModel(
        texW: 64, texH: 32,
        parts: [
            part("body", (0, 14, 2),
                 box(-5.5, 5, -4, 11, 1, 10, 0, 0),
                 box(-5.6, -1, -1, 0.5, 6, 4, 0, 12), box(5.1, -1, -1, 0.5, 6, 4, 0, 12),
                 box(-1, 6, -4.5, 2, 1.5, 1.5, 30, 12)),
        ],
        anim: "none", scale: 1,
        paint: { s in
            s.box(0, 0, 11, 1, 10, leather, 0.08)
            s.fill(10, 0, 11, 1, trim, 0.05)
            s.box(0, 12, 1, 6, 4, trim, 0.08)
            s.box(30, 12, 2, 2, 2, metal, 0.05)
        }))
    M2("dragon_saddle", MobModel(
        texW: 64, texH: 32,
        parts: [
            part("body", (0, 13, 0),
                 box(-6.5, 5, -6, 13, 1, 10, 0, 0),
                 box(-6.6, -1, -3, 0.5, 6, 4, 0, 12), box(6.1, -1, -3, 0.5, 6, 4, 0, 12),
                 box(-1, 6, -6.5, 2, 2, 1.5, 30, 12)),
        ],
        anim: "none", scale: 1.25,
        paint: { s in
            s.box(0, 0, 13, 1, 10, 0x6a2a20, 0.08)
            s.fill(10, 0, 13, 1, 0x3a1810, 0.05)
            s.box(0, 12, 1, 6, 4, 0x3a1810, 0.08)
            s.box(30, 12, 2, 2, 2, 0xd8b048, 0.05)
        }))
}
