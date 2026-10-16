// What the creative Tools menu offers: the tool items, structures and
// creatures added since 1.0.0, and the edit commands. Each entry is the chat
// command that does it, so the menu, typing it and a LAN guest (whose world
// commands run on the host) all take the same path.

import Foundation

public enum ToolTab: Int, CaseIterable {
    case tools, structures, creatures, edit
    public var title: String { ["Tools", "Structures", "Creatures", "Edit"][rawValue] }
}

public struct ToolEntry {
    public let title: String
    /// item drawn beside the title (nil = text only)
    public let icon: String?
    public let command: String
    /// a line of explanation for the tooltip
    public let detail: String?
}

/// the tool items, with how many to give and what each does
public let TOOL_ITEMS: [(name: String, count: Int, detail: String)] = [
    ("bazooka", 1, "Fires a rocket that blasts a crater"),
    ("mining_laser", 1, "Hold use to bore a tunnel (sneak: wider)"),
    ("void_bomb", 16, "Throw it to erase a sphere (sneak: bigger)"),
    ("quarry_charge", 16, "Place it on a block to dig down to bedrock"),
    ("wall_builder", 1, "Raises a 16-block wall (sneak: 8)"),
    ("box_builder", 1, "Builds a 16-block box (sneak: 8)"),
    ("infinity_wipe", 1, "Use twice to erase the land around you - can't be undone"),
    ("selection_wand", 1, "Marks a box to copy, cut and paste"),
    ("headlamp", 1, "Wear it to light up where you look"),
]

/// summonable things that aren't creatures (they come from items)
private let NOT_CREATURES: Set<String> = ["boat", "minecart", "rift_crystal"]

/// the entries on one tab. `layout` picks a structure's variant (0 = the
/// usual one, as /place without a number)
public func toolEntries(_ tab: ToolTab, layout: Int = 0) -> [ToolEntry] {
    switch tab {
    case .tools:
        return TOOL_ITEMS.map { t in
            ToolEntry(title: itemDefs[iid(t.name)].displayName, icon: t.name,
                      command: "/give \(t.name) \(t.count)", detail: t.detail)
        }
    case .structures:
        let suffix = layout > 0 ? " \(layout)" : ""
        return (["mountain"] + placeableStructureIds()).sorted().map {
            ToolEntry(title: prettify($0), icon: nil, command: "/place \($0)\(suffix)", detail: nil)
        }
    case .creatures:
        let groups = MOB_GROUPS.map {
            ToolEntry(title: $0.name == "anime_zoo" ? "All Anime Animals" : prettify($0.name), icon: nil,
                      command: "/spawn \($0.name)", detail: "\($0.mobs().count) creatures in rows")
        }
        let anime = Set(ANIME_ANIMALS.map { $0.id })
        let mobs = ANIME_ANIMALS.map { $0.id }
            + summonableMobs().filter { !anime.contains($0) && !NOT_CREATURES.contains($0) }.sorted()
        return groups + mobs.map { m in
            ToolEntry(title: prettify(m), icon: iidOpt("\(m)_spawn_egg") != nil ? "\(m)_spawn_egg" : nil,
                      command: "/spawn \(m)", detail: nil)
        }
    case .edit:
        return [
            ToolEntry(title: "Undo", icon: nil, command: "/undo", detail: "Takes back the last big edit (Cmd+Z)"),
            ToolEntry(title: "Redo", icon: nil, command: "/redo", detail: "Puts it back again (Cmd+Shift+Z)"),
            ToolEntry(title: "Corner 1 Here", icon: nil, command: "//pos1", detail: "A selection corner at your feet"),
            ToolEntry(title: "Corner 2 Here", icon: nil, command: "//pos2", detail: "The opposite corner at your feet"),
            ToolEntry(title: "Copy", icon: nil, command: "//copy", detail: "Copies the selected box"),
            ToolEntry(title: "Cut", icon: nil, command: "//cut", detail: "Copies the box and clears it"),
            ToolEntry(title: "Paste", icon: nil, command: "//paste", detail: "Pastes where you're looking"),
            ToolEntry(title: "Paste, Skip Air", icon: nil, command: "//paste -a", detail: "Leaves blocks where the copy has air"),
            ToolEntry(title: "Clear Selection", icon: nil, command: "//desel", detail: nil),
        ]
    }
}
