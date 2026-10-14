// Anime-style animals: ten chibi critters (big heads, big sparkly eyes,
// blush) that only appear when placed — from their spawn eggs or /summon,
// never by natural spawning. They're ordinary passive animals: they wander,
// panic when hit, follow their favourite food and breed with it. One spec per
// animal drives the entity here, its model and skin (Render/AnimeModels.swift),
// its egg colours (Render/Icons.swift) and its voice (PebbleApp/Audio.swift).

import Foundation

public struct AnimeAnimalSpec {
    public enum Plan { case quad, biped }
    /// each animal's own build (Render/AnimeModels.swift)
    public enum Shape { case mound, slender, sleek, tubby, chunky, ruff, egg, ball, long, puffball }
    public enum Ears { case none, tall, pointed, round, tuft }
    public enum Tail { case none, puff, triple, curl, ringed, stub, thin }
    public enum Extra { case none, bell, leaf, scarf, cheeks, pandaPatches, mask }

    public let id: String
    public let display: String
    public let plan: Plan
    public let shape: Shape
    /// head width, height, depth; body width, height, length; leg height (1/16 block)
    public let head: (Double, Double, Double)
    public let body: (Double, Double, Double)
    public let legH: Double
    public let ears: Ears
    public let tail: Tail
    public let extra: Extra
    /// snout box on the face (fox, dog, raccoon-dog…) or a beak (birds)
    public let snout: Bool, beak: Bool
    /// main fur, lighter belly/face, ear lining / tail tip, dark detail (paws, patches)
    public let fur: Int, light: Int, accent: Int, dark: Int
    /// iris colour of the big eyes
    public let iris: Int
    public let foods: [String]
    public let width: Double, height: Double
    /// voice: base pitch (Hz) and how it bends (end/start ratio)
    public let voice: Double, bend: Double
}

private typealias S = AnimeAnimalSpec

public let ANIME_ANIMALS: [AnimeAnimalSpec] = [
    S(id: "mochi_bunny", display: "Mochi Bunny", plan: .quad, shape: .mound,
      head: (9, 8, 8), body: (7, 5, 7), legH: 1.5, ears: .tall, tail: .puff, extra: .none,
      snout: false, beak: false, fur: 0xf6f1f4, light: 0xffffff, accent: 0xf4a6c0, dark: 0xd9c8d0,
      iris: 0xc0306a, foods: ["carrot", "golden_carrot"], width: 0.5, height: 0.6, voice: 1400, bend: 1.3),
    S(id: "kitsune_kit", display: "Kitsune Kit", plan: .quad, shape: .slender,
      head: (9, 8, 8), body: (5, 4, 10), legH: 4, ears: .pointed, tail: .triple, extra: .none,
      snout: true, beak: false, fur: 0xf08a2e, light: 0xfff4e6, accent: 0xffffff, dark: 0x4a2a1a,
      iris: 0xe0a020, foods: ["sweet_berries", "glow_berries"], width: 0.6, height: 0.7, voice: 1100, bend: 1.5),
    S(id: "bell_neko", display: "Bell Neko", plan: .quad, shape: .sleek,
      head: (9, 8, 8), body: (5, 4.5, 9), legH: 3.5, ears: .pointed, tail: .thin, extra: .bell,
      snout: false, beak: false, fur: 0xfaf0dc, light: 0xffffff, accent: 0xe8902c, dark: 0x3a3030,
      iris: 0x3aa860, foods: ["cod", "salmon"], width: 0.6, height: 0.7, voice: 950, bend: 1.35),
    S(id: "leaf_tanuki", display: "Leaf Tanuki", plan: .quad, shape: .tubby,
      head: (10, 8, 8), body: (8, 6, 8), legH: 2, ears: .round, tail: .ringed, extra: .leaf,
      snout: true, beak: false, fur: 0x9a7650, light: 0xe8d8bc, accent: 0x5a4030, dark: 0x3a2a20,
      iris: 0x6a3a1a, foods: ["apple", "sweet_berries"], width: 0.7, height: 0.75, voice: 700, bend: 1.2),
    S(id: "bao_panda", display: "Bao Panda", plan: .quad, shape: .chunky,
      head: (11, 9, 9), body: (10, 7, 11), legH: 3, ears: .round, tail: .stub, extra: .pandaPatches,
      snout: false, beak: false, fur: 0xf6f6f2, light: 0xffffff, accent: 0x2a2a2e, dark: 0x1c1c20,
      iris: 0x3a2a2a, foods: ["bamboo", "cookie"], width: 0.85, height: 0.85, voice: 520, bend: 1.15),
    S(id: "puff_shiba", display: "Puff Shiba", plan: .quad, shape: .ruff,
      head: (9, 8, 8), body: (6, 5, 9), legH: 3.5, ears: .pointed, tail: .curl, extra: .none,
      snout: true, beak: false, fur: 0xd88a3c, light: 0xfff6ea, accent: 0xfff6ea, dark: 0x5a3a24,
      iris: 0x4a2a1a, foods: ["bone", "cooked_beef"], width: 0.6, height: 0.75, voice: 820, bend: 1.4),
    S(id: "scarf_penguin", display: "Scarf Penguin", plan: .biped, shape: .egg,
      head: (9, 8, 8), body: (7, 8, 6), legH: 1, ears: .none, tail: .none, extra: .scarf,
      snout: false, beak: true, fur: 0x2c3442, light: 0xfafafa, accent: 0xd8302c, dark: 0xf0a020,
      iris: 0x2060c0, foods: ["cod", "salmon"], width: 0.55, height: 0.95, voice: 640, bend: 0.85),
    S(id: "hamu_hamster", display: "Hamu Hamster", plan: .quad, shape: .ball,
      head: (9, 7, 7), body: (8, 6, 8), legH: 0.75, ears: .round, tail: .none, extra: .cheeks,
      snout: false, beak: false, fur: 0xe6a95a, light: 0xfff4e4, accent: 0xf4a6b0, dark: 0xb07a3a,
      iris: 0x2a1a1a, foods: ["wheat_seeds", "melon_seeds", "pumpkin_seeds"], width: 0.5, height: 0.45,
      voice: 1700, bend: 1.2),
    S(id: "momiji_red_panda", display: "Momiji Red Panda", plan: .quad, shape: .long,
      head: (10, 8, 8), body: (6, 5, 11), legH: 3, ears: .pointed, tail: .ringed, extra: .mask,
      snout: true, beak: false, fur: 0xc2502a, light: 0xfff2e8, accent: 0x8a3018, dark: 0x3a1c14,
      iris: 0x5a2a14, foods: ["bamboo", "apple"], width: 0.6, height: 0.7, voice: 900, bend: 1.25),
    S(id: "piyo_chick", display: "Piyo Chick", plan: .biped, shape: .puffball,
      head: (8, 7, 7), body: (7, 6, 6), legH: 2, ears: .tuft, tail: .none, extra: .none,
      snout: false, beak: true, fur: 0xffd83a, light: 0xfff2a0, accent: 0xffc020, dark: 0xf08a20,
      iris: 0x2a2a2a, foods: ["wheat_seeds", "melon_seeds", "pumpkin_seeds"], width: 0.45, height: 0.75,
      voice: 2000, bend: 1.35),
]

public let ANIME_ANIMAL_BY_ID: [String: AnimeAnimalSpec] =
    Dictionary(uniqueKeysWithValues: ANIME_ANIMALS.map { ($0.id, $0) })

public final class AnimeAnimal: Animal {
    public let spec: AnimeAnimalSpec
    public override var type: String { spec.id }

    public init(world: World, _ spec: AnimeAnimalSpec) {
        self.spec = spec
        super.init(world: world)
        width = spec.width; height = spec.height
        maxHealth = 8; health = 8
        speed = spec.plan == .biped ? 0.07 : 0.1
        foods = spec.foods
        xpReward = 2
        addBasicGoals()
    }
}
