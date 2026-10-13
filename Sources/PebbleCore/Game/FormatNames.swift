// Name translation for two external formats Pebble reads:
//  - resource packs, which follow the Java Edition layout, so their texture
//    files carry that format's names (textures/block/<name>.png);
//  - worlds saved before Pebble renamed some blocks, items and mobs.
// Pebble's own names are on the right; the format's on the left. Only whole
// words of a snake_case name are translated.

/// (format word, Pebble word), whole-name phrases first
private let FORMAT_WORDS: [(String, String)] = [
    ("eye_of_ender", "rift_eye"), ("end_crystal", "rift_crystal"),
    ("totem_of_undying", "lifecharm"), ("bane_of_arthropods", "bugbane"),
    ("endermen", "riftwalkers"), ("enderman", "riftwalker"), ("endermite", "riftmite"), ("ender", "rift"),
    ("creeper", "fizzler"), ("wither", "blight"), ("ghast", "wailer"), ("blaze", "cinder"),
    ("shulker", "lurker"), ("piglin", "snouter"), ("hoglin", "tusker"), ("zoglin", "ghoultusk"),
    ("zombified", "rotting"), ("mooshroom", "mushcow"), ("elytra", "wingsuit"), ("netherite", "darksteel"),
    ("netherrack", "ashrock"), ("redstone", "sparkstone"), ("sculk", "hush"), ("glowstone", "lumenstone"),
    ("shroomlight", "glowcap"), ("purpur", "violite"), ("prismarine", "seaglass"), ("evoker", "conjurer"),
    ("illager", "marauder"),
]

private func translate(_ name: String, from: KeyPath<(String, String), String>, to: KeyPath<(String, String), String>) -> String {
    var parts = name.split(separator: "_", omittingEmptySubsequences: false).map(String.init)
    // phrases (several words) first, then single words
    var joined = "_" + parts.joined(separator: "_") + "_"
    for pair in FORMAT_WORDS where pair[keyPath: from].contains("_") {
        joined = joined.replacingOccurrences(of: "_" + pair[keyPath: from] + "_", with: "_" + pair[keyPath: to] + "_")
    }
    parts = joined.dropFirst().dropLast().split(separator: "_", omittingEmptySubsequences: false).map(String.init)
    let words = Dictionary(FORMAT_WORDS.filter { !$0[keyPath: from].contains("_") }.map { ($0[keyPath: from], $0[keyPath: to]) },
                           uniquingKeysWith: { a, _ in a })
    return parts.map { words[$0] ?? $0 }.joined(separator: "_")
}

/// a block, item or texture name as a Java-format resource pack spells it
public func packName(_ name: String) -> String { translate(name, from: \.1, to: \.0) }

/// a name from a resource pack or an older save, in Pebble's terms
public func pebbleName(_ formatName: String) -> String { translate(formatName, from: \.0, to: \.1) }
