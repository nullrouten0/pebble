// Advancements — definition tree, trigger
// API, persistence-ready state. earned keeps insertion order (deterministic Set).

import Foundation

public struct AdvancementDef {
    public let id: String
    public let title: String
    public let description: String
    public let icon: String            // item name for the icon
    public let parent: String?
    public let frame: String           // task | goal | challenge
}

public let ADVANCEMENTS: [AdvancementDef] = {
    var A: [AdvancementDef] = []
    func adv(_ id: String, _ title: String, _ description: String, _ icon: String, _ parent: String?, _ frame: String = "task") {
        A.append(AdvancementDef(id: id, title: title, description: description, icon: icon, parent: parent, frame: frame))
    }

    // story (main progression)
    adv("root", "Pebble", "Where it all starts", "grass_block", nil)
    adv("mine_log", "Timber!", "Knock a log loose from a tree", "oak_log", "root")
    adv("crafting_table", "Workshop", "Make a crafting table", "crafting_table", "mine_log")
    adv("wooden_pickaxe", "First Pick", "Make a pickaxe from planks and sticks", "wooden_pickaxe", "crafting_table")
    adv("mine_stone", "Breaking Ground", "Dig out some stone", "cobblestone", "wooden_pickaxe")
    adv("stone_pickaxe", "Sharper Edge", "Make a stone pickaxe", "stone_pickaxe", "mine_stone")
    adv("iron_ingot", "Ironworks", "Smelt your first iron ingot", "iron_ingot", "stone_pickaxe")
    adv("iron_tools", "Iron Grip", "Make an iron pickaxe", "iron_pickaxe", "iron_ingot")
    adv("iron_armor", "Plated", "Wear any piece of iron armor", "iron_chestplate", "iron_ingot")
    adv("mine_diamond", "Sparkle", "Find a diamond", "diamond", "iron_tools")
    adv("diamond_armor", "Glittering Guard", "Wear any piece of diamond armor", "diamond_chestplate", "mine_diamond")
    adv("enchant_item", "A Little Magic", "Enchant something at an enchanting table", "enchanting_table", "mine_diamond")
    adv("ignite_portal", "Down Below", "Light a portal to the Nether and step through", "flint_and_steel", "mine_diamond")
    adv("return_portal", "Return Fire", "Bring down a wailer with its own fireball", "fire_charge", "ignite_portal", "challenge")
    adv("obtain_cinder_rod", "Hot Property", "Take a rod from a cinder", "cinder_rod", "ignite_portal")
    adv("brew_potion", "Home Brew", "Brew any potion", "brewing_stand", "obtain_cinder_rod")
    adv("rift_eye", "Seeing Eye", "Make a rift eye", "rift_eye", "obtain_cinder_rod")
    adv("follow_rift_eye", "Follow the Eye", "Throw a rift eye and see where it goes", "rift_eye", "obtain_cinder_rod")
    adv("enter_end", "Beyond the Frame", "Step through an End portal", "end_stone", "rift_eye")
    adv("kill_dragon", "Dragonfall", "Defeat the rift dragon", "dragon_head", "enter_end", "goal")
    adv("dragon_egg", "Egg Hunt", "Pick up the dragon egg", "dragon_egg", "kill_dragon")
    adv("enter_gateway", "Island Hopping", "Travel through an End gateway", "rift_pearl", "kill_dragon")
    adv("wingsuit", "Lift-Off", "Find a wingsuit", "wingsuit", "enter_gateway")
    adv("dragon_breath", "Bottled Breath", "Catch dragon's breath in a glass bottle", "dragon_breath", "kill_dragon", "goal")

    // nether branch
    adv("nether_root", "Nether", "A hot, unfriendly place", "ashrock", "ignite_portal")
    adv("find_fortress", "Brick by Brick", "Find a Nether fortress", "nether_bricks", "nether_root")
    adv("obtain_ancient_debris", "Deep Find", "Dig up ancient debris", "ancient_debris", "nether_root")
    adv("darksteel_armor", "Head to Toe in Dark", "Wear a full set of darksteel armor", "darksteel_chestplate", "obtain_ancient_debris", "challenge")
    adv("find_bastion", "Old Stones", "Find a bastion", "gilded_blackstone", "nether_root")
    adv("distract_snouter", "Shiny Distraction", "Keep a snouter busy with gold", "gold_ingot", "find_bastion")
    adv("kill_blight", "Blight Begone", "Summon the blight and defeat it", "nether_star", "find_fortress", "challenge")
    adv("beacon", "Shine a Light", "Build a beacon and set it in place", "beacon", "kill_blight")

    // adventure branch
    adv("adventure_root", "Adventure", "Explore, fight and travel", "compass", "root")
    adv("kill_mob", "First Victory", "Defeat any hostile mob", "iron_sword", "adventure_root")
    adv("shoot_arrow", "Archer", "Hit something with an arrow", "bow", "kill_mob")
    adv("sleep_in_bed", "Good Night", "Sleep in a bed to set your spawn", "red_bed", "adventure_root")
    adv("trade_villager", "Fair Trade", "Complete a trade with a villager", "emerald", "adventure_root")
    adv("totem", "Second Chance", "Survive a deadly hit with a lifecharm", "lifecharm", "kill_mob", "goal")
    adv("sniper_duel", "Long Shot", "Take down a skeleton from 50 blocks or more", "arrow", "shoot_arrow", "challenge")
    adv("hero_village", "Village Defender", "Fight off a raid on a village", "iron_axe", "kill_mob", "challenge")
    adv("brush_sherd", "Careful Digging", "Brush a suspicious block and find a pottery sherd", "brush", "adventure_root")
    adv("avoid_warden", "Spreading Hush", "Defeat a mob near a hush catalyst", "hush_catalyst", "kill_mob")
    adv("lightning_rod", "Grounded", "Save a villager from a lightning strike", "lightning_rod", "adventure_root")

    // husbandry
    adv("husbandry_root", "Husbandry", "Animals, crops and food", "wheat", "root")
    adv("husbandry_eat", "Snack Time", "Eat anything at all", "apple", "husbandry_root")
    adv("breed_animals", "Family Ties", "Breed two animals", "wheat", "husbandry_root")
    adv("tame_animal", "Loyal Companion", "Tame an animal", "bone", "husbandry_root")
    adv("plant_seed", "Green Thumb", "Plant a seed", "wheat_seeds", "husbandry_root")
    adv("fish", "Gone Fishing", "Catch a fish", "fishing_rod", "husbandry_root")
    adv("tactical_fishing", "Bucket Catch", "Catch a fish in a bucket", "pufferfish_bucket", "fish")
    adv("sniffer_egg", "Ancient Egg", "Find a sniffer egg", "sniffer_egg", "husbandry_root")
    adv("plant_torchflower", "Old Seeds", "Plant a seed a sniffer dug up", "torchflower_seeds", "sniffer_egg")
    adv("full_beehive", "Moving Day", "Move a bee nest with Silk Touch", "bee_nest", "husbandry_root")
    adv("axolotl_bucket", "Pond Friend", "Scoop up an axolotl in a bucket", "axolotl_bucket", "husbandry_root")
    adv("wax_copper", "Polished", "Wax a copper block with honeycomb", "honeycomb", "husbandry_root")

    return A
}()

public let ADV_BY_ID: [String: AdvancementDef] = Dictionary(uniqueKeysWithValues: ADVANCEMENTS.map { ($0.id, $0) })

public final class AdvancementTracker {
    /// insertion-ordered (deterministic Set semantics)
    public private(set) var earnedOrder: [String] = []
    private var earnedSet = Set<String>()
    public var pendingToasts: [AdvancementDef] = []

    public init() {}

    @discardableResult
    public func grant(_ id: String) -> Bool {
        if earnedSet.contains(id) { return false }
        guard let def = ADV_BY_ID[id] else { return false }
        addEarned(id)
        // auto-grant parents (silently)
        var p = def.parent
        while let cur = p {
            addEarned(cur)
            p = ADV_BY_ID[cur]?.parent
        }
        pendingToasts.append(def)
        return true
    }
    private func addEarned(_ id: String) {
        if earnedSet.insert(id).inserted {
            earnedOrder.append(id)
        }
    }
    public func has(_ id: String) -> Bool { earnedSet.contains(id) }
    public func save() -> [String] { earnedOrder }
    public func load(_ ids: [String]) {
        earnedOrder = []
        earnedSet = []
        for id in ids { addEarned(id) }
    }
}
