// Chat commands — (/debug and /rendertest were
// legacy diagnostics and stay behind.)

import Foundation
import PebbleCore

/// commands that change the shared world — a LAN guest asks the host to run them
let HOST_COMMANDS: Set<String> = [
    "time", "weather", "summon", "setblock", "fill", "place", "undo", "redo", "difficulty", "gamerule",
]

/// run a LAN guest's command on the host as that guest's player; returns what it printed
func runCommandAs(_ game: GameCore, _ guest: Player, _ raw: String) -> [String] {
    let me = game.player
    game.player = guest
    chatCapture = []
    runCommand(game, raw)
    let out = chatCapture ?? []
    chatCapture = nil
    game.player = me
    return out
}

func runCommand(_ game: GameCore, _ raw: String) {
    if !raw.hasPrefix("/") {
        if game.isNetworked { game.lanChat(raw) } else { pushChat("<You> \(raw)") }
        return
    }
    let parts = raw.dropFirst().trimmingCharacters(in: .whitespaces)
        .split(separator: " ", omittingEmptySubsequences: true).map(String.init)
    let cmd = parts.first?.lowercased() ?? ""
    let args = Array(parts.dropFirst())
    if let nc = game.netClient, HOST_COMMANDS.contains(cmd) {
        nc.sendCommand(raw)
        return
    }
    guard let p = game.player else { return }
    let world = game.world
    func fail(_ msg: String) { pushChat("§c" + msg) }
    func ok(_ msg: String) { pushChat("§7" + msg) }
    /// a typed coordinate, kept finite and inside the world border: "nan" or
    /// "1e300" would otherwise trap in Int() here or ifloor() on the next tick
    func parseCoord(_ s: String, _ base: Double) -> Double {
        let v = s.hasPrefix("~") ? base + (s.count > 1 ? Double(s.dropFirst()) ?? 0 : 0) : Double(s) ?? 0
        return v.isFinite ? max(-30_000_000, min(30_000_000, v)) : base
    }
    func arg(_ i: Int) -> String? { i < args.count ? args[i] : nil }
    /// an integer argument clamped to a range, so later arithmetic can't overflow
    func intArg(_ i: Int, _ def: Int, _ range: ClosedRange<Int>) -> Int {
        max(range.lowerBound, min(range.upperBound, arg(i).flatMap { Int($0) } ?? def))
    }

    switch cmd {
    case "help":
        ok("Commands: give, tp, time, weather, gamemode, seed, kill, summon, effect, enchant, xp, setblock, fill, locate, place, undo, redo, chatsize, difficulty, gamerule, clear, spawnpoint, heal")
        ok("LAN: host [port], join <address[:port]>, leave, list, name <name>")
        ok("Selection: //pos1 [x y z], //pos2 [x y z], //desel (or use the selection_wand)")
    case "give":
        guard let itemName = arg(0) else { return fail("Usage: /give <item> [count]") }
        let count = arg(1).flatMap(Int.init) ?? 1
        guard let id = iidOpt(itemName) else { return fail("Unknown item: \(itemName)") }
        var remaining = count
        while remaining > 0 {
            let give = min(remaining, itemDef(id).maxStack)
            if !p.give(ItemStack(id, give)) { break }
            remaining -= give
        }
        ok("Gave \(count - remaining) \(itemName)")
    case "tp", "teleport":
        guard args.count >= 3 else { return fail("Usage: /tp <x> <y|top> <z> [yaw pitch]") }
        let x = parseCoord(args[0], p.x)
        let z = parseCoord(args[2], p.z)
        let y = args[1] == "top" ? Double(world.surfaceY(Int(x.rounded(.down)), Int(z.rounded(.down))) + 1)
                                 : parseCoord(args[1], p.y)
        p.setPos(x, y, z)
        p.vx = 0; p.vy = 0; p.vz = 0
        if args.count >= 5, let yaw = Double(args[3]), let pitch = Double(args[4]), yaw.isFinite, pitch.isFinite {
            p.yaw = yaw * .pi / 180
            p.pitch = max(-89.9, min(89.9, pitch)) * .pi / 180
        }
        ok(String(format: "Teleported to %.1f %.1f %.1f", x, y, z))
    case "time":
        if arg(0) == "set" {
            let presets: [String: Int] = ["day": 1000, "noon": 6000, "sunset": 12000, "night": 13000, "midnight": 18000, "sunrise": 23000]
            guard let v = presets[arg(1) ?? ""] ?? arg(1).flatMap(Int.init) else {
                return fail("Usage: /time set <day|noon|night|midnight|ticks>")
            }
            world.dayTime = ((v % 24000) + 24000) % 24000
            ok("Set time to \(world.dayTime)")
        } else if arg(0) == "add" {
            world.dayTime = ((world.dayTime + intArg(1, 0, -24000...24000) % 24000) % 24000 + 24000) % 24000
            ok("Time is now \(world.dayTime)")
        } else {
            ok("Time: \(world.dayTime) (day \(world.time / 24000))")
        }
    case "weather":
        switch arg(0) {
        case "clear":
            world.raining = false
            world.thundering = false
            world.weatherTimer = 12000
        case "rain":
            world.raining = true
            world.thundering = false
            world.weatherTimer = 12000
        case "thunder":
            world.raining = true
            world.thundering = true
            world.weatherTimer = 12000
        default:
            return fail("Usage: /weather <clear|rain|thunder>")
        }
        ok("Weather set to \(arg(0)!)")
    case "gamemode", "gm":
        switch arg(0) {
        case "creative", "1", "c": game.applyGameMode(GameMode.creative)
        case "survival", "0", "s": game.applyGameMode(GameMode.survival)
        default: return fail("Usage: /gamemode <survival|creative>")
        }
        ok("Game mode set to \(p.gameMode == GameMode.creative ? "Creative" : "Survival")")
    case "seed":
        ok("Seed: \(world.seed)")
    case "kill":
        if arg(0) == "@e" {
            var n = 0
            for e in Array(world.entities) {
                guard let ent = e as? Entity, !ent.isPlayer else { continue }
                ent.remove()
                n += 1
            }
            ok("Removed \(n) entities")
        } else {
            _ = p.hurt(10000, .void)
            ok("Ouch")
        }
    case "summon":
        guard let mob = arg(0) else { return fail("Usage: /summon <mob> [x y z]") }
        let mobs = spawnableMobs()
        if !mobs.contains(mob) {
            return fail("Unknown mob: \(mob). Try: \(mobs.prefix(8).joined(separator: ", "))...")
        }
        let x = arg(1).map { parseCoord($0, p.x) } ?? p.x
        let y = arg(2).map { parseCoord($0, p.y) } ?? p.y
        let z = arg(3).map { parseCoord($0, p.z) } ?? p.z
        if spawnMob(world, mob, x, y, z, nil) != nil {
            ok("Summoned \(mob)")
        }
    case "effect":
        if arg(0) == "clear" {
            p.clearEffects()
            ok("Cleared effects")
            return
        }
        let give = arg(0) == "give" ? Array(args.dropFirst()) : args
        guard let effId = give.first, EFFECT_BY_ID[effId] != nil else {
            return fail("Unknown effect: \(give.first ?? "?")")
        }
        let dur = max(1, min(1_000_000, give.count > 1 ? Int(give[1]) ?? 30 : 30))
        let amp = max(0, min(255, give.count > 2 ? Int(give[2]) ?? 0 : 0))
        p.addEffect(effId, dur * 20, amp)
        ok("Applied \(effId) \(amp + 1) for \(dur)s")
    case "enchant":
        guard let enchId = arg(0), let e = ENCH_BY_ID[enchId] else {
            return fail("Unknown enchantment: \(arg(0) ?? "?")")
        }
        let lvl = intArg(1, 1, 1...255)
        guard let held = p.mainHand else { return fail("Hold an item first") }
        held.ench = held.ench.filter { $0.id != enchId } + [EnchInstance(enchId, lvl)]
        ok("Enchanted with \(e.displayName) \(lvl)")
    case "xp", "experience":
        let amount = max(-1_000_000, min(1_000_000, arg(0).flatMap { Int($0.replacingOccurrences(of: "L", with: "")) } ?? 1))
        if arg(1) == "levels" || (arg(0) ?? "").hasSuffix("L") {
            p.xpLevel = max(0, min(1_000_000, p.xpLevel + amount))
            ok("Added \(amount) levels")
        } else {
            p.addXP(amount)
            ok("Added \(amount) XP")
        }
    case "setblock":
        guard args.count >= 4 else { return fail("Usage: /setblock <x> <y> <z> <block> [meta]") }
        let x = Int(parseCoord(args[0], p.x).rounded(.down))
        let y = Int(parseCoord(args[1], p.y).rounded(.down))
        let z = Int(parseCoord(args[2], p.z).rounded(.down))
        let blockName = args[3]
        let id: UInt16? = blockName == "air" ? 0 : bidOpt(blockName)
        guard let id else { return fail("Unknown block: \(blockName)") }
        let meta = arg(4).flatMap(Int.init) ?? 0
        world.setBlock(x, y, z, id == 0 ? 0 : Int(cell(id, meta)))
        ok("Set block at \(x) \(y) \(z)")
    case "fill":
        guard args.count >= 7 else { return fail("Usage: /fill <x0> <y0> <z0> <x1> <y1> <z1> <block>") }
        let x0 = Int(parseCoord(args[0], p.x).rounded(.down)), y0 = Int(parseCoord(args[1], p.y).rounded(.down)), z0 = Int(parseCoord(args[2], p.z).rounded(.down))
        let x1 = Int(parseCoord(args[3], p.x).rounded(.down)), y1 = Int(parseCoord(args[4], p.y).rounded(.down)), z1 = Int(parseCoord(args[5], p.z).rounded(.down))
        let blockName = args[6]
        let id: UInt16? = blockName == "air" ? 0 : bidOpt(blockName)
        guard let id else { return fail("Unknown block: \(blockName)") }
        // coordinates are within the border, so each side fits; the product may not
        let (vxz, o1) = (abs(x1 - x0) + 1).multipliedReportingOverflow(by: abs(z1 - z0) + 1)
        let (vol, o2) = vxz.multipliedReportingOverflow(by: abs(y1 - y0) + 1)
        if o1 || o2 || vol > 32768 { return fail("Too many blocks (more than 32768)") }
        var n = 0
        let batch = beginEdit(world, "fill")
        for y in min(y0, y1)...max(y0, y1) {
            for z in min(z0, z1)...max(z0, z1) {
                for x in min(x0, x1)...max(x0, x1) {
                    batch.set(x, y, z, id == 0 ? 0 : Int(cell(id, 0)), SET_DEFAULT)
                    n += 1
                }
            }
        }
        ok("Filled \(n) blocks")
    case "/pos1", "/pos2":
        // at your feet, or at typed coordinates
        if !args.isEmpty && args.count < 3 { return fail("Usage: /\(cmd) [x y z]") }
        let x = Int((args.isEmpty ? p.x : parseCoord(args[0], p.x)).rounded(.down))
        let y = Int((args.isEmpty ? p.y : parseCoord(args[1], p.y)).rounded(.down))
        let z = Int((args.isEmpty ? p.z : parseCoord(args[2], p.z)).rounded(.down))
        ok(setSelectionCorner(p, cmd == "/pos1" ? 1 : 2, BlockPos(x, y, z)))
    case "/desel":
        p.selection = nil
        ok("Selection cleared")
    case "locate":
        guard let target = arg(0) else { return fail("Usage: /locate <structure>") }
        if target == "stronghold" {
            var best: (Int, Int)?
            var bestD = Double.infinity
            for (cx, cz) in strongholdPositions(world.seed) {
                let dx = Double(cx * 16) - p.x, dz = Double(cz * 16) - p.z
                let d = dx * dx + dz * dz
                if d < bestD {
                    bestD = d
                    best = (cx * 16, cz * 16)
                }
            }
            if let best {
                ok("Nearest stronghold: \(best.0), ~, \(best.1) (\(Int(bestD.squareRoot().rounded())) blocks)")
            }
            return
        }
        guard let def = STRUCTURES.first(where: { $0.id == target }) else {
            return fail("Unknown structure. Try: \(STRUCTURES.map { $0.id }.joined(separator: ", "))")
        }
        let pcx = Int((p.x / 16).rounded(.down)), pcz = Int((p.z / 16).rounded(.down))
        let ctx = GenCtx(
            seed: world.seed,
            heightAt: { x, z in world.surfaceY(x, z) },
            biomeAt: { x, z in world.biomeAt(x, world.surfaceY(x, z), z) },
            dim: world.dim.rawValue)
        for r in 0..<12 {
            for rz in -r...r {
                for rx in -r...r {
                    if max(abs(rx), abs(rz)) != r { continue }
                    let rcx = Int((Double(pcx) / Double(def.spacing)).rounded(.down)) + rx
                    let rcz = Int((Double(pcz) / Double(def.spacing)).rounded(.down)) + rz
                    let (ocx, ocz) = structureOriginFor(def, world.seed, rcx, rcz)
                    if getPlan(def, ctx, ocx, ocz) != nil {
                        ok("Nearest \(target): \(ocx * 16 + 8), ~, \(ocz * 16 + 8)")
                        return
                    }
                }
            }
        }
        fail("Could not find \(target) nearby")
    case "difficulty":
        guard let d = ["peaceful", "easy", "normal", "hard"].firstIndex(of: arg(0) ?? "") else {
            return fail("Usage: /difficulty <peaceful|easy|normal|hard>")
        }
        game.setDifficulty(d)
        ok("Difficulty set to \(DIFFICULTY_NAMES[d])")
    case "gamerule":
        guard let rule = arg(0) else {
            ok(world.gameRules.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", "))
            return
        }
        guard world.gameRules[rule] != nil else { return fail("Unknown gamerule: \(rule)") }
        if let v = arg(1) {
            let n = v == "true" ? 1 : v == "false" ? 0 : Double(v) ?? 0
            guard n.isFinite, abs(n) <= 1_000_000 else { return fail("Value out of range: \(v)") }
            game.setGameRule(rule, n)
        }
        ok("\(rule) = \(world.gameRules[rule]!)")
    case "clear":
        for i in 0..<p.inventory.count { p.inventory[i] = nil }
        for i in 0..<p.armor.count { p.armor[i] = nil }
        p.offHand = nil
        ok("Inventory cleared")
    case "spawnpoint":
        p.spawnPoint = (Int(p.x.rounded(.down)), Int(p.y.rounded(.down)), Int(p.z.rounded(.down)))
        p.spawnDim = world.dim.rawValue
        ok("Spawn point set")
    case "heal":
        p.health = p.maxHealth
        p.hunger = 20
        p.saturation = 20
        ok("Healed")
    case "meshmode":
        let mode = arg(0)
        guard mode == "simple" || mode == "greedy" else { return fail("Usage: /meshmode <simple|greedy>") }
        game.setMeshMode(simple: mode == "simple")
        ok("Mesh mode: \(mode!) - rebuilding world...")
    case "place":
        let ids = placeableStructureIds()
        guard let name = arg(0), name != "list" else {
            return ok("Structures: mountain, \(ids.joined(separator: ", "))")
        }
        guard ids.contains(name) || name == "mountain" else { return fail("Unknown structure: \(name). Try /place list") }
        let usage = "Usage: /place <structure> [<x> <y|ground> <z>] [variant]"
        let hasPos = args.count >= 4
        if args.count == 3 || args.count > 5 { return fail(usage) }
        let variant = (hasPos ? arg(4) : arg(1)).map { Int($0) } ?? 0
        guard let variant else { return fail(usage) }
        let t0 = Date()
        if name == "mountain" {
            // sits on the ground wherever it lands, so a given y is ignored
            var tx = Int(p.x.rounded(.down)), tz = Int(p.z.rounded(.down))
            if hasPos {
                tx = Int(parseCoord(args[1], p.x).rounded(.down))
                tz = Int(parseCoord(args[3], p.z).rounded(.down))
            } else {
                // far enough ahead that you're at its foot, not inside it
                let reach = MOUNTAIN_RADIUS * 1.25 + 8
                tx = Int((p.x - sin(p.yaw) * reach).rounded(.down))
                tz = Int((p.z + cos(p.yaw) * reach).rounded(.down))
            }
            let plan = game.placeMountain(tx, tz, variant: variant)
            if plan.keys.isEmpty { return fail("No room for a mountain at \(tx) \(tz) - the ground there is already higher") }
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            ok("A mountain is rising at \(tx) \(tz): \(plan.x1 - plan.x0 + 1)x\(plan.z1 - plan.z0 + 1) wide, peak at y=\(plan.peakY), \(plan.keys.count) blocks (planned in \(ms) ms)")
            if plan.skipped > 0 { fail("\(plan.skipped) columns fell in unloaded chunks and were skipped") }
            return
        }
        guard let pf = capturePrefab(name, dim: world.dim.rawValue, minY: world.info.minY,
                                     maxY: world.info.minY + world.info.height,
                                     biome: world.biomeAt(Int(p.x.rounded(.down)), Int(p.y), Int(p.z.rounded(.down))),
                                     variant: variant) else {
            return fail("\(name) produced nothing here (try another variant)")
        }
        var tx: Int, tz: Int, ty: Int?
        if hasPos {
            tx = Int(parseCoord(args[1], p.x).rounded(.down))
            tz = Int(parseCoord(args[3], p.z).rounded(.down))
            ty = args[2] == "ground" || args[2] == "_" ? nil : Int(parseCoord(args[2], p.y).rounded(.down))
        } else {
            // in front of the player, far enough that the footprint clears them
            let reach = Double(max(pf.x1 - pf.x0, pf.z1 - pf.z0)) / 2 + 3
            tx = Int((p.x - sin(p.yaw) * reach).rounded(.down))
            tz = Int((p.z + cos(p.yaw) * reach).rounded(.down))
            ty = nil
        }
        let r = game.placePrefab(pf, tx, ty, tz)
        let ms = Int(Date().timeIntervalSince(t0) * 1000)
        ok("Placed \(name) at \(r.x0)..\(r.x1), \(r.y0)..\(r.y1), \(r.z0)..\(r.z1) - \(r.changed) blocks in \(ms) ms")
        if let (ex, ey, ez) = r.entrance { ok("§eEntrance: ladder shaft under the red flag at \(ex) \(ey) \(ez) - /tp \(ex) \(ey + 1) \(ez - 2)") }
        if r.skippedCells > 0 { fail("\(r.skippedCells) blocks fell in unloaded chunks and were skipped") }
    case "undo", "redo":
        let n = max(1, min(64, arg(0).flatMap(Int.init) ?? 1))
        var done: [String] = []
        for _ in 0..<n {
            // editOwner: a LAN guest's command undoes only that guest's edits
            guard let b = cmd == "undo" ? undoLastEdit(owner: editOwner) : redoLastEdit(owner: editOwner) else { break }
            done.append("\(b.label) (\(b.count) blocks)")
        }
        if done.isEmpty { return fail("Nothing to \(cmd)") }
        let left = editCounts(owner: editOwner)
        ok((cmd == "undo" ? "Undid " : "Redid ") + done.joined(separator: ", ")
           + " - \(left.undo) undo / \(left.redo) redo left")
    case "chatsize":
        guard let v = arg(0).flatMap(Double.init), v >= 1, v <= 3 else {
            return fail("Usage: /chatsize <1-3> (current \(game.settings.chatScale ?? 1))")
        }
        game.settings.chatScale = v
        game.applySettings()
        ok("Chat size set to \(v)")
    case "surface", "top":
        let sx = Int(p.x.rounded(.down)), sz = Int(p.z.rounded(.down))
        let sy = world.surfaceY(sx, sz)
        p.setPos(p.x, Double(sy), p.z)
        p.vx = 0; p.vy = 0; p.vz = 0
        p.fallDistance = 0
        ok("Brought you to the surface (y=\(sy))")
    case "host", "lan", "publish":
        if game.isGuest { return fail("You're a guest in someone else's game") }
        if let port = game.lanPort { return ok("Already open to LAN on port \(port)") }
        let want = arg(0).flatMap(UInt16.init) ?? NET_DEFAULT_PORT
        do {
            let port = try game.hostLAN(port: want)
            let ips = localIPv4Addresses()
            ok("§aOpen to LAN on port \(port).")
            ok(ips.isEmpty ? "Friends can find it under Join LAN Game." :
                "Friends: Join LAN Game, or connect to \(ips.map { port == NET_DEFAULT_PORT ? $0 : "\($0):\(port)" }.joined(separator: " / "))")
        } catch {
            fail("Couldn't open to LAN: \(error.localizedDescription)")
        }
    case "join", "connect":
        guard let addr = arg(0) else { return fail("Usage: /join <address[:port]>") }
        let (h, port) = parseLANAddress(addr)
        gRuntime?.beginJoin { $0.joinLAN(host: h, port: port) }
    case "leave", "disconnect":
        if !game.isNetworked { return fail("Not in a LAN game") }
        if game.isGuest { game.exitToTitle(); return }
        game.stopHosting()
        ok("Closed the LAN game - guests were disconnected")
    case "list", "players", "who":
        if !game.isNetworked { return ok("Just you (open to LAN with /host)") }
        let names = game.lanPlayers
        ok("\(names.count) playing: \(names.joined(separator: ", "))")
    case "name":
        guard let n = arg(0), !n.isEmpty else { return ok("Your name is \(game.playerName)") }
        if game.isNetworked { return fail("Change your name before hosting or joining") }
        game.settings.playerName = String(args.joined(separator: " ").prefix(16))
        game.applySettings()
        ok("You'll be \(game.playerName) in LAN games")
    default:
        fail("Unknown command: /\(cmd). Try /help")
    }
}

/// "192.168.1.5", "192.168.1.5:25576", "mac.local"
func parseLANAddress(_ s: String) -> (String, UInt16) {
    let t = s.trimmingCharacters(in: .whitespaces)
    if let i = t.lastIndex(of: ":"), !t.contains("]"), t.filter({ $0 == ":" }).count == 1,
       let port = UInt16(t[t.index(after: i)...]), port > 0 {
        return (String(t[..<i]), port)
    }
    return (t, NET_DEFAULT_PORT)
}
