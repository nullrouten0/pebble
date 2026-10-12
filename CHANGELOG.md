# Changelog

All notable changes to Pebble. Versions follow `MAJOR.MINOR.PATCH`; the
in-app version string comes from `PEBBLE_VERSION` (PebbleCore/Game/Saves.swift).

## iPad Beta — `ios-port` branch

Version 1.3.1. Not a main release yet: build it yourself from the branch
(see the README banner). Known rough edges: frame rate dips while new
terrain streams in, and iPhone layouts are only lightly polished.

- **Easier on the battery (1.3.1).** The title screen and the pause menu
  now draw at 30 fps instead of 60. The world behind the pause menu is
  frozen, but it was still being redrawn 60 times a second, costing as
  much as playing. The game also drops to 30 fps in Low Power Mode and
  when the device reports it's running hot (on top of the lower
  resolution it already used when hot).
- **Battery Saver** (Options → Video): 30 fps and no shadows, leaving your
  Max FPS and Soft Shadows choices untouched for when you switch it off.
  On an iPad Pro the graphics chip's work fell from about 40% to 21% at 30
  fps; turning shadows off saves a further ~7 points over open landscape
  and almost nothing looking down. Measured with the new power benchmark
  (`PEBBLE_POWERBENCH`, see CONTRIBUTING).
- **The screen no longer locks mid-game.** Playing with a game controller,
  or holding the look finger still, sent no touches, so iOS auto-lock
  could dim and lock the screen. It now stays on while you're in a world.
- **Exact build on the title screen.** The version now reads
  major.minor.revision.commit, e.g. `Pebble 1.3.0.2d559e0a` (bottom-left of
  the title screen and in F3), so you can tell which build each device is
  on. A `+` at the end means it was built with uncommitted changes. The
  revision goes up for a small feature or a fix, the minor version for a
  release that adds features.
- **No more starting on the ocean floor.** About 1 in 20 new worlds put
  spawn in water (the spawn search reads a terrain estimate, and the real
  terrain had a lake or ocean there), so you started and respawned on the
  bottom. Spawn now moves to the nearest dry land; older worlds fix
  themselves the next time you respawn there.
- **Icons on the touch buttons** in place of text labels: jump (up arrow),
  sneak (down arrow onto the floor), drop (your held item with an arrow),
  swap hands, inventory (chest), chat (speech bubble), camera view (eye),
  pause, and an × to close screens. Jump, sneak, swap, drop and inventory
  form an L in the bottom-right corner.

- **Pebble runs on iPad and iPhone.** The same game, built from the same
  repo: `pebble ios run` launches it in the simulator. Touch controls (move
  stick, drag to look, tap to place, hold to break, jump/sneak/inventory
  buttons, long-press for right-click in inventories), hardware keyboard and
  mouse, and game controllers all work. Mac↔iPad LAN games work because
  both apps are always the same version.
- **Hold to dig, like Minecraft.** Press and hold a finger still on the
  look area for a quarter second and it digs for as long as the finger stays
  down; a finger that rolls slightly keeps digging. Only a fresh press digs:
  steering with the look finger stops the dig, and pausing mid-turn no longer
  starts one. Lift and press again to dig. Held items like a bow keep
  drawing while you aim.
- **Creative blocks erode before they break.** A crack grows over the block
  you're digging, so you can see it and look away or let go to keep it.
  **Options → Controls → Creative Dig** sets the time: 0.4 s by default on
  touch screens, instant on the Mac (where it was before), up to 1 s.
- **Far fewer disk writes.** A 3-player LAN game made an iPad host write
  about 1 GB in 10 minutes, enough for iOS to flag it. Chunks you only walk
  back through are no longer re-saved unless something in them changed, and
  on iOS chunk saves are compressed (about 50× smaller). Five minutes of
  exploring went from 233 MB written to 3 MB on iPad (170 MB on the Mac).
  Every build reads both formats; only iOS writes compressed chunks until
  this branch reaches main, so Mac worlds still open in older builds.
- **Fixed: a crash typing in the creative inventory search** after switching
  tabs (and from accented letters or emoji on the iOS keyboard).
- **Game controllers on the Mac too.** Plug in an Xbox, PlayStation or MFi
  controller: sticks move and look, triggers break and place, and the left
  stick drives a cursor in menus.
- **Chunk generation is about 4–5× faster on many-core Macs.** Noise lookups no
  longer fight over a shared reference count, so chunk generation scales with
  your cores instead of slowing down past six threads. Same seeds, same worlds.

## 1.2.0 — 2026-10-10 — LAN multiplayer

### Play together over LAN
- **Host from the title screen.** **Host LAN Game** lets you set your name,
  pick a world (**Host Selected**) or make one (**Create & Host**), and drops
  you in already open to LAN.
- **Or share the world you're in.** **Open to LAN** in the pause menu (or
  `/host [port]`). The pause menu shows the address, and **Close LAN Game**
  stops it. A LAN game never pauses, and the host keeps running with its
  window in the background.
- **Join from the title screen.** **Join LAN Game** finds games on the
  local network automatically (Bonjour). You can also type an address, or use
  `/join <address[:port]>`. Set your name there or with `/name`.
- **One shared world.** Shared between all players:
  - block changes (including `/place`, `/fill` and the creative tools)
  - rockets and void bombs in flight, with their launch sounds and the blast
    screen shake, even when a guest fires them
  - particles out to each guest's view distance, so a rocket's trail and
    blast don't vanish partway out
  - a guest's own mining laser beam and hum, and the sounds and particles of
    commands a guest runs on the host (`/fill`, `/place`, `/summon`…)
  - mobs, items and projectiles
  - chests, furnaces and signs
  - time, weather, game rules, difficulty, sounds and particles
  - game mode: guests play in the host's mode, and follow the host's `/gamemode`
  - chat, with join and leave messages
- **Each other.** Players see each other with name tags. A name tag dims
  behind walls and while the player sneaks, and is hidden when they sneak
  behind a wall.
- **Survival works for guests.** Guests:
  - take damage, knockback and effects from mobs and explosions
  - pick up items and XP, and can fight each other (PvP)
  - drop their items when they die and respawn at their bed or world spawn
- **Guests come back where they left off.** The host's world saves each
  guest's inventory, health and position for their next visit.
- **Your own undo.** In a LAN game, each player's Cmd+Z / `/undo` only undoes
  their own edits.
- **More commands:** `/list` shows who's playing, and `/leave` disconnects
  (or closes the game, for the host).
- **Limits for now:**
  - Guests follow the host between dimensions instead of using portals
    themselves.
  - Sleeping skips the night only when everyone is in bed.
  - Villager trade limits and anvil wear aren't shared.
  - Everyone needs the same version.

### Infinity Wipe
- **A new creative tool, `infinity_wipe`, erases the land like a nuke.** Use it
  once to arm it, then again within 3 seconds to fire.
  - It erases everything within 320 blocks of you (1000 if you sneak).
  - It follows the land's contour: whatever stands on the natural ground
    (trees, buildings, overhangs) goes, along with the top 12 blocks of the
    ground itself.
  - It never cuts below sea level, so oceans, rivers and shores stay put. The
    cut eases off over the last 24 blocks.
  - A shockwave rolls through the loaded area. Chunks beyond your view are
    wiped as they load, and the blast zone is saved with the world.
  - It can't be undone. It's Overworld only, and LAN guests can fire it too.

### `/place mountain`
- **Pours a natural-looking mountain onto the land.** It's about 160 blocks
  across and peaks 80 blocks above its base, about 1.5× the Giza pyramid.
  - Ridges, gullies, scree, grassy lower slopes and a snowcap. A different
    `variant` gives a different mountain.
  - Every column fills from the surface down through air, water, trees and
    plants until it meets solid ground. So it settles over valleys and lakes
    and buries anything built there. Ground that already stands higher is left
    alone, so the edges melt into the hills.
  - It rises over a few seconds, lifting anyone standing where it grows. Like
    any `/place`, Cmd+Z undoes it.

### `/place city`, `small_school`, `large_school`
- **`city`** builds a dense downtown 107 blocks across on a 4×4 grid of streets.
  - The streets have dashed center lines, crosswalks and street lamps.
  - The buildings are glass, brick, stone and white, rising to about 90 blocks
    in the middle. Floors are lit, storefronts have doors front and back, and
    a ladder runs to every roof.
  - Rooftops have antennas, water towers, AC units and gardens. One block is a
    park with a fountain.
  - A different `variant` gives a different city.
- **`small_school`** has 4 classrooms off a central hall. **`large_school`**
  has 3 floors of 4 rooms with a switchback stair tower.
  - Each classroom has rows of desks and chairs, a chalkboard, a teacher's
    desk and bookshelves.
  - A sign hangs over the front door, with a flag out front.
- `/place` structures can now carry signs.

### Fixes
- **Messages no longer show "?" for dashes and ellipses.** The in-game font is
  ASCII-only, so "—", "…" and "·" in chat lines, the loading screens and the
  Credits rendered as "?". They're now plain ASCII.
- **World list dates no longer show "?" before AM/PM.** The system date
  format uses a narrow no-break space, which the font doesn't have.
- **Title screen fits short windows.** The Options / Quit row no longer
  covers the texture credit in the bottom-left corner.
- **Elder Guardians no longer curse creative players** with Mining Fatigue,
  as in vanilla.
- **Status effects say what they are.** When an effect starts or changes
  level, its name (with the level, e.g. "Mining Fatigue III") shows under the
  icons in the top right for 5 seconds.
- **Rockets no longer freeze in mid-air.** A rocket (or void bomb) that flew
  past simulation distance stopped moving and never went off. Now it keeps
  flying and detonates at the end of its range.

### Development
- **New test hooks** for LAN and UI testing:
  - `PEBBLE_JOIN`, `PEBBLE_NAME`, `PEBBLE_MULTIPLAYER`
  - `PEBBLE_MENU` clicks menu buttons by label (e.g.
    `"Host LAN Game>Create New>Create & Host"`)
  - `PEBBLE_WINDOWED` / `PEBBLE_WINSIZE` / `PEBBLE_WINPOS`
  - `PEBBLE_NETLOG` and `PEBBLE_SHOT_UI`
  - `PEBBLE_CMD` steps: `#waitguests`, `#down`/`#up`, `#key`, `#slot`, `#type`
    and `#uikey`
  - This lets a host and guests run side by side in windows from one script.
- **App bundle:** `Info.plist` now declares local-network use
  (`NSLocalNetworkUsageDescription`, `NSBonjourServices`).
- **Docs:** README, ARCHITECTURE and SECURITY now cover LAN play.
- **Tests:** pebsmoke passes 461/461 and no goldens changed.

## 1.1.0 — 2026-10-10 — building & demolition tools, structure placement, undo

### Placing structures — `/place`
- **`/place <structure> [<x> <y|ground> <z>] [variant]`** drops a whole
  structure into the world. `/place list` lists every option. With no
  coordinates it lands in front of you, clear of where you stand. A different
  `variant` number gives a different layout of the same structure.
- **Placement clears the way.** Every cell in the structure's footprint is
  replaced, so trees, terrain or water can't leave holes in it. Columns standing
  over a gap get a foundation filled down to the ground.
- **Starter structures:** `cabin`, `watchtower`, `bunker`, `farm`, `portal`.
  Each comes stocked with things like chests, beds and doors.
- **Landmarks:**
  - **`giza_pyramid`**: 101 wide and 51 tall, with internal tunnels and
    chambers. Placing it writes ~264k blocks in about a second.
  - **`castle`**
  - **`lighthouse`**
  - **`windmill`**
  - **`treehouse`**
  - **`sky_island`**
- **All worldgen structures can be placed too**, e.g. villages, strongholds and
  end cities.
- **Underground structures are easy to find.**
  - A ladder shaft leads down to each one. The shaft is lined with brick and lit
    with glowstone.
  - The surface opening has a lantern-lit collar. Trees around it are cleared
    away.
  - A flag pole with red wool marks the spot and stands taller than the forest
    canopy.
  - `/place` prints the entrance coordinates along with a ready-made `/tp`
    command.

### Destruction tools
All are tools-category items, given with `/give`.
- **Bazooka (`bazooka`).** Fires a fast rocket that blows out a crater of radius
  9. The blast spreads outward over a few ticks instead of all landing in one
  frame.
- **Mining laser (`mining_laser`).** Hold use to fire a beam that bores a
  5-wide tunnel; sneak for 9 wide. It reaches 64 blocks.
- **Void bomb (`void_bomb`, stacks to 16).** A thrown, glowing orb that implodes
  a sphere of radius 12 into nothing; sneak to throw for radius 24.
- **Quarry charge (`quarry_charge`, stacks to 16).** Placed on a block, it digs
  a 9×9 shaft down to bedrock one layer per tick; sneak for 17×17.

### Building tools
- **Wall builder (`wall_builder`).** Right-click to raise a 16×16 wall square
  to the direction you're facing.
- **Box builder (`box_builder`).** Right-click to build a 16×16×16 box with a
  solid floor, walls on four sides and an open top. The inside is cleared out.
- **Both builders:**
  - Sneak for the 8-block versions.
  - Builds snap to a 16-block grid, so walls and boxes line up edge to edge.
  - Clicking the top of a build stacks the next one on it. Clicking a side puts
    the next one alongside, at the same base height.
  - The block in your off hand sets the material. Failing that, the hotbar slot
    just right of the tool is used, and then stone bricks.
  - Builds fill a foundation down to nearby ground.
  - Bedrock and other unbreakable blocks are never overwritten.
  - Builders and quarry charges fire once per click; holding use doesn't repeat
    them.

### Undo / redo
- **Cmd/Ctrl+Z** undoes the last large edit and **Cmd/Ctrl+Shift+Z** redoes it.
  `/undo [n]` and `/redo [n]` do the same and report what changed.
- **Covered:** the bazooka, the laser (one held burst is one step), the void
  bomb, quarry charges, `/place`, `/fill` and both builders.
- **What's restored:** blocks, plus container contents such as chests.
  Undoing a blast or quarry that is still running stops it.
- **Limits:**
  - The last 64 edits are kept, capped at 6M blocks.
  - History is cleared on quit.
  - Hand mining and hand placing aren't tracked.
  - Mobs and dropped items don't come back.

### Chat
- **Long chat lines wrap** instead of running off screen. A § color code carries
  over onto the wrapped lines.
- **`/chatsize <1-3>`** scales the chat text, and the setting is saved.
- **The input line scrolls** to keep the cursor visible.

### Development
- **`PEBBLE_CMD` accepts `#wait N`.** This pauses the remaining commands for
  N frames, so a script can wait for a blast to finish before taking a
  screenshot.
- **The pebsmoke item count is now 1,194** for the six new items, appended
  after all existing ones so the ids stay stable. The suite passes 461/461 and
  no goldens changed.

## 1.0.6 — 2026-07-23 — gameplay and rendering fixes (#15, #16)

- **Doors and beds now render as coherent two-block objects.** Each half samples
  the correct portion of its composite texture, beds drop only one item, and
  using, exploding, or naturally destroying a bed consistently addresses both
  halves.
- **Levers now look and move like mounted controls.** Their base and handle
  follow the face they are attached to, use focused texture regions, and visibly
  change pose when switched.
- **Slime and honey blocks now move their attached payloads with pistons.**
  Sticky-piston retraction preserves the full adhesion set, and retracted piston
  bases can move so basic flying machines work.
- **Equipped elytra are visible in third person.** A textured wing layer now
  follows the player and changes pose during elytra flight.
- **Running no longer makes the third-person camera weave.** View bobbing is
  restricted to first person and its remaining motion is substantially milder.

## 1.0.5 — 2026-07-03 — keybind fix (#13)

- **Shift and Control can now be assigned to keybinds.** On macOS the modifier
  keys fire `flagsChanged` rather than `keyDown`, so a modifier press never
  reached the open Controls screen and couldn't be bound (e.g. setting Sprint to
  Left Shift). A modifier press is now delivered to the active screen so it can
  be captured, while releases still reach the game as before.

## 1.0.4 — 2026-07-02 — water & aquatic-plant fixes (#12)

- **Smooth water/biome color transitions.** Water (and grass/foliage) tint is now
  averaged over a 7×7 neighborhood instead of picked per-block, so the color no
  longer steps abruptly at a biome border (e.g. where two ocean biomes meet).
- **Underwater plants are properly submerged.** Seagrass, kelp, coral and sea
  pickles now render the surrounding water volume, so they no longer sit in
  un-rendered air pockets under the surface.
- **No more notch in the water surface around surface plants.** Water next to a
  seagrass/kelp poking the surface no longer bulges to a full block, so the
  surface stays flat.
- **Breaking an aquatic plant leaves water, not an air pocket** — for player
  breaks, natural pops, and piston/explosion breaks.
- **Breaking one seagrass no longer destroys its neighbors.** The water that
  filled a broken plant's cell was spreading and washing away adjacent
  (replaceable) plants; spreading water now leaves waterlogged plants intact.

## 1.0.3 — 2026-06-27 — gameplay bug fixes (#11)

- **Mobs can no longer be hit while dying, and no longer dupe their drops.**
  A mob's death was processed every tick it kept taking damage during the
  ~1s death animation, re-running its loot drop (and slime splits / raid
  `bad_omen`) each time. Damage is now rejected once an entity enters its
  death animation, so loot drops exactly once. Re-baselined the entity goldens.
- **Tree leaves now drop saplings, sticks and apples when they decay.** Leaf
  decay destroyed the block without rolling its drop table; it now uses the
  normal natural-break path, matching what hand-breaking already dropped.
- **Beds now show a sleep overlay.** Sleeping faded straight to a frozen frame
  with no feedback; the screen now fades to black with a "Sleeping…" prompt,
  and Sneak/Esc leaves the bed.
- **Entities now cast a contact shadow.** A soft dark disc is projected onto
  the ground beneath living entities — including your own player in third
  person — and fades out as they rise off the ground.
- **The offhand can now use items, and shields block.** The use action falls
  back to the offhand when the main hand does nothing (food, shields, torches,
  throwables, …), and raising a shield now negates frontal melee, projectile
  and explosion damage.

## 1.0.2 — 2026-06-13 — bug fixes

- **Fixed `./pebble install` failing to compile on Swift 6.2.x.** The
  smooth-lighting arithmetic in `Mesher.swift` (plus a few other expressions)
  overran the Swift type-checker's budget and tripped integer-vs-`Double`
  inference, breaking the build partway through `./pebble install`. The
  expressions are now broken into single-operation typed locals; Pebble builds
  cleanly on every Swift 6.0–6.3 toolchain. Worldgen/mesh output is unchanged.
  This completes the #1 fix that 1.0.1 only partially addressed.
- **Fixed over-dark lighting in pits, holes and undersides.** Smooth lighting
  averaged in the zero skylight of solid neighbours, so the walls and floor of
  a freshly-dug hole rendered far darker than they should in daylight. Opaque
  neighbours now contribute the face light (standard vanilla smooth lighting);
  ambient occlusion still shades the corners. Re-baselined the mesh goldens.
- **The installer now checks your Swift version up front.** `./pebble install`
  needs Swift 6.0+; if you're below that it explains the fix and can install a
  current toolchain for you (via swiftly) instead of failing partway through a
  build.

## 1.0.1 — 2026-06-13 — minor bug fixes

- **Fixed a build failure on newer toolchains.** A literal-arithmetic
  expression in `Mesher.swift` overran the Swift type-checker's budget on some
  toolchains (e.g. Swift 6.2.3 / Xcode 26.3, M-series), making `./pebble
  install` fail to compile. The expressions are now hoisted into typed locals;
  worldgen/mesh output is byte-identical.
- **Fixed entity facing.** Mobs and the third-person player were rendered
  rotated by `-yaw` instead of the Minecraft `180° - yaw` convention, so they
  faced (and appeared to walk) backward. Render-side only.

## 1.0.0 — 2026-06-11 — first public beta

**This is a beta.** The engine is pinned by 456 golden checks, but a game of
this scope certainly has bugs we haven't found yet. Reports and fix PRs are
incredibly welcome: https://github.com/thebriangao/pebble/issues (the README
lists what to include).

The initial release. What ships:

- **A complete, native block-survival game for macOS** — ~45,000 lines of
  Swift + Metal, zero external dependencies, no game engine, no .xcodeproj.
- **Content**: 879 blocks, 1,188 items, 63 biomes, 100 entity types (55+ mobs
  with goal-based AI and A* pathfinding), 19 structure types (30+ variants), 39 enchantments,
  full brewing/enchanting/smithing/stonecutting/archaeology systems,
  advancements, raids, and villager trading.
- **Three dimensions** with working portals and full progression: overworld →
  nether (fortresses, bastions) → end (dragon fight, end cities, gateways),
  plus the Wither and the Warden.
- **Worldgen**: multi-noise climate sampling, spline terrain, 3D density caves,
  ravines, aquifers, vanilla-1.20 ore tables, snow lines, cave biomes
  including the deep dark.
- **Redstone**: wire networks, repeaters, comparators with container reading,
  pistons with quasi-connectivity, observers, hoppers, rails, sculk sensors.
- **Vanilla-exact player physics**, verified by independent derivations in the
  test suite (walk 4.317 b/s, sprint 5.612 b/s, jump apex 1.2522 blocks).
- **Synthesized audio**: every sound and all music generated in real time
  from oscillator recipes — zero audio files.
- **Faithful 32x textures built in** (self-restoring, credited, license
  included) — atlas art, `.mcmeta` animations, GUIs, fonts, entity skins,
  and sun/moon, loaded through Pebble's own zip reader. **Ultra graphics**:
  a built-in enhanced pipeline (SSAO, volumetric light, soft shadows, ACES).
- **Persistence**: single SQLite database (WAL) holding worlds, chunks
  (compact binary records), players, and advancements.
- **Quality**: 456 golden regression checks, all green; the engine is fully
  deterministic — identical seeds produce identical worlds on any machine,
  across releases; the build is warning-free; 200+ fps at full fancy settings
  on an Apple-silicon MacBook Air, ~2–4 s world loads.

### Known limitations

- Singleplayer only, for now — there is no networking code in 1.0.0.
- Elytra flight omits vanilla's dive-redirect term (look-pitch speed transfer);
  flight feel is otherwise vanilla-derived.
- Armor trims show in tooltips but not yet on worn armor.
- No resource-pack or shader-pack loading — the Faithful art and the ultra
  pipeline are built in; user-supplied packs are not a feature.
