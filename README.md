<p align="center">
  <img src="packaging/logo.png" alt="Pebble" width="420">
</p>

<h3 align="center">The open-source alternative to Minecraft: Java Edition.</h3>

<p align="center">
  <em>A complete block game, built from scratch in Swift + Metal.<br>
  Survive alone, or build together over LAN with a creative toolkit.<br>
  Every sound synthesized in real time. Every chunk carved from noise.</em>
</p>

<p align="center">
  <img src="packaging/homepage.png" alt="In-game render — dawn over a lake in a cherry grove, mountains behind, ultra graphics" width="800">
</p>

---

> ### 🧪 iPad Beta — this branch (`ios-port`)
> Pebble runs on **iPad** (and iPhone, in landscape) — the same game and worlds, and it plays LAN games with the Mac version. Touch controls (move stick, drag to look, tap to place, hold to break), hardware keyboard and mouse, and game controllers all work. It's a **beta**: not in the App Store or a main release yet, performance while new terrain streams in still needs work, and the touch controls will change. See the [iPad Beta notes](CHANGELOG.md#ipad-beta--ios-port-branch).
>
> **Install it on your iPad** (needs a Mac with Xcode 16+ and a free Apple ID):
> ```bash
> brew install xcodegen
> git clone -b ios-port https://github.com/nullrouten0/pebble.git && cd pebble
> cp ios/Config/Local.xcconfig.example ios/Config/Local.xcconfig   # add your team ID + a unique bundle ID
> ./pebble ios                                                     # generates and opens the Xcode project
> ```
> In Xcode: **Settings → Accounts** → add your Apple ID (your team ID is shown there), plug in the iPad, pick it as the run destination, and press **⌘R**. On the iPad, turn on **Settings → Privacy & Security → Developer Mode** if asked, and trust your Apple ID under **Settings → General → VPN & Device Management**. Apps signed with a free Apple ID expire after 7 days — press ⌘R again to refresh. No iPad handy? `./pebble ios run` launches it in the simulator.

> ### New in Pebble 1.2: build together
> **LAN multiplayer** — click **Host LAN Game** on the title screen, pick a world, and you're in and open to the local network. Friends on the same Wi-Fi click **Join LAN Game**. Pebble finds the game for you. Everyone shares one world: blocks, mobs, items, chests, chat, day and night.
>
> **A creative toolkit to build with** — drop whole structures (up to a 101-block Giza pyramid) with `/place`, raise 16×16 walls and 16×16×16 boxes in one click, carve terrain with a bazooka, mining laser, void bomb and quarry charge, and undo any of it with Cmd+Z. In a LAN game, everyone's undo is their own.
>
> See [Multiplayer (LAN)](#multiplayer-lan) and [Creative tools](#creative-tools).

**Pebble** is the open-source alternative to Minecraft: Java Edition — a native macOS voxel game with the full overworld/nether/end progression: worldgen, mobs, redstone, crafting, enchanting, brewing, villages, raids, and boss fights — plus a creative building toolkit and LAN multiplayer. It is implemented in **~50,000 lines of Swift** with **zero external dependencies**. No game engine, no .xcodeproj. The renderer is hand-written Metal, the audio engine synthesizes every sound from oscillators at runtime, multiplayer runs on Apple's Network framework, and the game looks the way it does thanks to [Faithful 32x](https://faithfulpack.net) as its built-in texture set.

Pebble is an original fan re-creation inspired by Minecraft: Java Edition 1.20. It is **not affiliated with, endorsed by, or connected to Mojang Studios or Microsoft** in any way, and contains no Mojang code or assets. Full statement in [Disclaimer](#disclaimer) below.

> **Pebble 1.2.0 is a beta.** The engine is pinned by 491 golden regression checks, but a game of this scope absolutely has bugs we haven't found yet — we just don't know where they are. Multiplayer is the newest part and the least battle-tested. If you hit a bug, [opening an issue](https://github.com/thebriangao/pebble/issues) would mean the world to us, and a pull request with a fix even more. See [Reporting bugs & contributing](#reporting-bugs--contributing) for what to include.

## By the numbers

| | |
|---|---|
| Lines of Swift | ~50,700 across 92 files |
| External dependencies | **0** (Apple frameworks only) |
| Blocks | 879 |
| Items | 1,194 |
| Biomes | 63 (overworld, nether, end, cave biomes) |
| Entity types | 100 (55+ mobs with full AI, vehicles, projectiles) |
| Structures | 19 worldgen types, 30+ variants (villages, strongholds, bastions, end cities, ancient cities…), plus 11 placeable starters and landmarks |
| Multiplayer | LAN: one host, any number of guests, found automatically on the local network (Bonjour) |
| Golden regression checks | 491, all green (`pebble test`) |
| Renderer | Metal, 15+ passes, runtime-compiled MSL |
| Textures | [Faithful 32x](https://faithfulpack.net) by the Faithful team (third-party, fully credited) |
| Audio assets | 0 — fully synthesized (AVAudioSourceNode + biquad filters) |
| Performance | 200+ fps at full fancy settings on an Apple-silicon MacBook Air with Max FPS set to Unlimited (the default cap is 120) |
| World load | ~2–4 s cold |

## Features

- **Full survival loop** — mining with tool tiers, hunger/saturation, XP, sleeping, fall damage, drowning, fire, status effects, death messages, respawn/keep-inventory game rules.
- **LAN multiplayer** — host or join straight from the title screen; shared blocks, mobs, items, containers, chat, time and weather, with name tags over other players and everyone's progress saved in the host's world. See [Multiplayer (LAN)](#multiplayer-lan).
- **Creative tools** — drop any structure into the world with `/place` (including 11 starter builds and landmarks like a 101-wide Giza pyramid), raise 16×16 walls and 16×16×16 boxes in one click, blast or bore terrain with the bazooka, mining laser, void bomb and quarry charge, erase whole landscapes with the Infinity Wipe, and undo almost any of it with Cmd+Z. See [Creative tools](#creative-tools).
- **Worldgen** — multi-noise climate sampling (temperature/humidity/continentalness/erosion/weirdness) through spline-driven terrain, 3D density caves (cheese/spaghetti/noodle), ravines, aquifers, ore distribution per vanilla 1.20 tables, snow lines, and 63 biomes including lush caves, dripstone caves, and the deep dark.
- **Three dimensions** — overworld, nether (fortresses, bastions, all five nether biomes), and the end (dragon fight, end cities, gateways), connected by working portals.
- **Structures** — villages with professioned villagers and working trades, strongholds with the portal room, mineshafts, desert/jungle temples, igloos with basements, witch huts, ocean monuments and ruins, shipwrecks, buried treasure, ruined portals, woodland mansions, amethyst geodes, ancient cities with sculk and shriekers.
- **Mobs & AI** — 55+ mobs with A* pathfinding, goal-based AI (breeding, taming, fleeing, pack hunting), villager gossip and trades, piglin bartering, raids with waves and Hero of the Village, and the three bosses: Ender Dragon, Wither, Warden (with vibration detection).
- **Redstone** — wire networks with 0–15 power levels, repeaters with locking, comparators that read containers, pistons with quasi-connectivity and slime/honey push sets, observers, dispensers, hoppers, rails, sculk sensors.
- **Items & systems** — shaped/shapeless/tag crafting, smelting in three furnace types, brewing, enchanting with 39 enchantments and a compatibility matrix, anvils, grindstones, smithing with armor trims, stonecutters, loot tables with fortune/looting, fishing, archaeology with sherds and decorated pots, advancements.
- **Vanilla-exact player physics** — walk 4.317 b/s, sprint 5.612 b/s, jump apex 1.2522 blocks, sprint-jumping, water/lava/elytra movement, ice slipperiness, soul sand, honey — verified by independent-derivation tests in the suite.
- **Faithful 32x textures, built in** — the complete [Faithful 32x](https://faithfulpack.net) art (third-party, fully credited — see [Disclaimer](#disclaimer)) ships inside the app and loads through Pebble's own zip/`.mcmeta` reader: atlas textures, animations with interpolation, GUIs, fonts, entity skins, and sun/moon art. Self-restoring if the file goes missing.
- **Ultra graphics** — a built-in enhanced pipeline: SSAO, shadow-marched volumetric god rays, Poisson soft shadows, and ACES tonemapping. One toggle in Options → Video.
- **Generative music** — no audio files anywhere; ambient music, jukebox discs, and all ~hundreds of sound effects are synthesized from oscillator/noise recipes with envelopes, vibrato, positional stereo, underwater lowpass, and cave reverb.

## Install

Requirements: **macOS 14+** and the Xcode command-line tools (`xcode-select --install`). Apple silicon recommended.

```bash
git clone https://github.com/thebriangao/pebble.git && cd pebble
./pebble install
```

That builds in release mode, assembles a signed `Pebble.app`, installs it to `~/Applications`, and links the `pebble` CLI onto your PATH.

```
./pebble install    build from source and install ~/Applications/Pebble.app
pebble update       pull the latest version, rebuild, swap the live app
pebble run          launch Pebble
pebble test         run the 491-check golden test suite
```

For development you can also run straight from the checkout — `swift run -c release Pebble` — and the app will find its packaged assets in `packaging/`.

**iPad and iPhone (experimental).** With full Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) installed, `pebble ios` generates and opens the Xcode project, `pebble ios run` builds and launches it in the iPad simulator, and `pebble test ios` runs the golden suite inside the simulator. To install on your own device, copy `ios/Config/Local.xcconfig.example` to `Local.xcconfig`, fill in your team ID, and run from Xcode. The Mac build never needs any of this.

For LAN play, everyone needs the same Pebble version: each player runs `pebble update` (or installs the same release) before playing together.

## Controls

WASD to move, mouse to look, Space to jump (double-tap in creative to fly), Shift to sneak, Ctrl (or double-tap forward) to sprint, E for inventory, Q to drop, F to swap hands, T to chat, `/` for a command, F5 to change perspective, Esc to pause. F1 hides the GUI, F3 toggles the debug overlay, F11 toggles fullscreen (also in Options → Video). Scroll the hotbar with the wheel or trackpad. Movement and the other game keys are rebindable in Options → Controls. Cmd+Z / Cmd+Shift+Z undo and redo large edits (see [Creative tools](#creative-tools)).

## Multiplayer (LAN)

Play in the same world with people on your local network. One player hosts; everyone else joins.

**To host:** on the title screen, click **Host LAN Game**. Set the name others will see, then pick a world and click **Host Selected** (or double-click it), or click **Create New** and then **Create & Host**. The world loads already open to LAN, and chat shows the address to share. Press Esc any time to see the address again; click **Close LAN Game** there to stop.

Already playing? Press Esc and click **Open to LAN** (or type `/host`) to share the world you're in.

**To join:** on the title screen, click **Join LAN Game**. Games on your network appear in the list; double-click one, or type the host's address (e.g. `192.168.1.20`) and click **Direct Connect**. Set the name others will see at the top of that screen.

| Command | What it does |
|---|---|
| `/host [port]` | Open your world to LAN (default port 25575) |
| `/join <address[:port]>` | Join a LAN game by address |
| `/list` | Who's playing |
| `/leave` | Disconnect (as a guest), or close the LAN game (as the host) |
| `/name <name>` | Your name in LAN games |

What you share:

- **The world** — every block change, including `/place`, `/fill` and the creative tools, appears for everyone.
- **Mobs and items** — mobs chase and hurt every player, drops can be picked up by anyone, and PvP works.
- **Containers and signs** — chest, furnace and sign edits reach everyone.
- **Chat, time and weather** — `/time`, `/weather`, `/difficulty` and `/gamerule` from any player apply to the shared world.
- **Your own undo** — each player's Cmd+Z undoes only their own edits.
- **Your progress** — the host's world keeps each guest's inventory, health and position for their next visit.

Good to know:

- **The world never pauses.** The pause menu doesn't stop the game while others are playing, and the host keeps running even with its window in the background.
- **The host leads between dimensions.** When the host goes through a portal, everyone comes along; guests can't use portals on their own yet.
- **Sleeping skips the night only when everyone is in bed.**
- **When the host quits,** guests return to the title screen with a message.
- **Everyone needs the same Pebble version.**
- **Some things stay local to a guest for now:** villager trade limits, and anvils wearing out.
- **Two people editing the same chest at the same moment** can overwrite each other's change; the last edit wins.
- **macOS may ask first.** The host may see "accept incoming network connections?" the first time; click Allow. Guests may be asked to let Pebble find devices on the local network.
- **Your network is trusted.** LAN games have no password and aren't encrypted, and the host trusts guests' actions. Open your world only on networks where you'd let everyone in.

## Creative tools

Fast building and demolition for creative play. Get the tools with `/give <id>`. Sneak while using a tool for its alternate size. All of them work for LAN guests too.

| Tool / command | What it does | Sneak |
|---|---|---|
| `/place <structure> [<x> <y\|ground> <z>] [variant]` | Places a whole structure. Without coordinates it lands in front of you. It clears its footprint, so trees and terrain can't leave holes, and fills a foundation under it. `/place list` shows every option. | — |
| `wall_builder` | Right-click a block to build a 16×16 wall across your view | 8×8 |
| `box_builder` | Right-click to build a 16×16×16 box with a solid floor and open top; the inside is cleared | 8×8×8 |
| `bazooka` | Fires a rocket that blows out a crater of radius 9 | — |
| `mining_laser` | Hold use to bore a tunnel 5 blocks wide, reaching up to 64 blocks | 9 wide |
| `void_bomb` | A thrown orb that wipes out a sphere of radius 12 | radius 24 |
| `quarry_charge` | Digs a 9×9 shaft straight down to bedrock | 17×17 |
| `infinity_wipe` | Erases the land for 320 blocks around you, following its contour. Use once to arm it and again within 3 seconds to fire. **Can't be undone.** | 1000 blocks |
| `/undo [n]`, `/redo [n]` | Undo or redo your last *n* edits (also Cmd+Z / Cmd+Shift+Z) | — |

- **Structures you can place:**
  - Starters: `cabin`, `watchtower`, `bunker`, `farm`, `portal`
  - Landmarks: `giza_pyramid` (101 wide, with internal tunnels and chambers), `castle`, `lighthouse`, `windmill`, `treehouse`, `sky_island`
  - Town: `city`, a 107-block-wide downtown: a 4×4 grid of glass, brick, stone and white towers (tallest in the middle) with lit floors and a ladder to every roof, plus streets with crosswalks and street lamps, and a park. `small_school` has 4 classrooms, and `large_school` has 3 floors of 4 with a stair tower. Each classroom has desks, a chalkboard and bookshelves. A different `variant` gives a different city.
  - Terrain: `mountain` pours a natural-looking peak about 160 blocks across and 80 tall (1.5× the pyramid) onto the land. Each column fills down through air, water and trees until it meets solid ground, so it buries whatever is under it (handy for covering up old builds) and blends into higher hills around it. It rises over a few seconds, lifting anyone standing there. A different `variant` gives a different mountain.
  - Every worldgen structure, such as villages, strongholds and end cities. A different `variant` number gives a different layout.
- **Underground structures get a marked entrance.** A lit ladder shaft leads down from a flag pole that stands above the trees, and `/place` prints a `/tp` to it.
- **Walls and boxes snap to a 16-block grid,** so they line up edge to edge. Click the top of a build to stack on it; click a side to build alongside at the same height.
- **Builder material:**
  - the block in your off hand
  - otherwise, the block in the hotbar slot just right of the builder
  - otherwise, stone bricks
- **Infinity Wipe:** a shockwave rolls out from where you stand. Every column loses whatever stands on the natural ground (trees, buildings, overhangs) plus the top 12 blocks of the ground itself, so hills stay hills, just bare stone and lower. It never cuts below sea level, so oceans, rivers and shores stay put, and the cut eases off toward the edge.
  - Chunks too far away to be loaded are wiped the moment they load, so the full radius is covered even beyond your view distance. The blast zone is saved with the world.
  - Overworld only.
- **Undo covers** every tool above except the Infinity Wipe, plus `/fill`, and restores chest contents too.
  - It keeps the last 64 edits, and the history is cleared when you quit.
  - In a LAN game, each player undoes only their own edits.
  - Blocks you mine or place by hand aren't tracked.
  - Mobs killed and items dropped don't come back.
- **Chat:** long lines wrap, and `/chatsize <1-3>` scales the chat text.

## Where things live

| Path | What |
|---|---|
| `~/Library/Application Support/Pebble/pebble.db` | All worlds, chunks, players, advancements (single SQLite database), including the saved players of LAN guests who visited your worlds |
| `~/Library/Application Support/Pebble/settings.json` + `keybinds.json` | Settings (including your LAN name) and keybinds |

A LAN guest stores nothing about the host's world; the host keeps it all.

To uninstall completely: delete `~/Applications/Pebble.app`, `~/Library/Application Support/Pebble/`, and the `pebble` symlink on your PATH (`/opt/homebrew/bin/pebble` or `/usr/local/bin/pebble`).

## Project layout

```
Sources/PebbleCore/   the engine — headless, no AppKit, fully testable
  Core/               deterministic math: fdlibm trig, seeded RNG, simplex noise
  World/              chunks, block registry (879), light engine, block entities
  Gen/                terrain, biomes, features, all structures, placeable starters/landmarks
  Entity/             100 entity types, AI, pathfinding, player physics
  Items/              item registry (1,194), recipes, enchants, potions, loot
  Systems/            interact, redstone, fluids, farming, combat, raids, portals,
                      placement, destroyers, builders, undo history
  Net/                LAN multiplayer: wire format, TCP + Bonjour transport,
                      host and guest sessions
  Render/             section mesher, texture atlas, entity models
  Game/               GameCore tick orchestrator, SQLite saves, settings
Sources/PebbleApp/    the shared app: Metal renderer, UI, audio, input routing,
                      touch and controller input
Sources/Pebble/       the macOS shell — window, menus, NSEvent input
ios/                  the iPad/iPhone shell (XcodeGen spec + UIKit host)
Sources/pebsmoke/     golden test harness (491 checks against goldens/*.json)
goldens/              golden baseline files pinning engine behavior
packaging/            Info.plist, icon, logo, title art, bundled Faithful textures
pebble                the build/install/test CLI
```

A deeper tour lives in [ARCHITECTURE.md](ARCHITECTURE.md).

## The determinism contract

Pebble's engine is **fully deterministic**: a portable fdlibm implementation of `sin/cos/atan2` (pure IEEE-754 operations, no platform math library), 32-bit-wrapping integer hashes, and seeded RNG everywhere mean the same seed produces the identical world — bit for bit, on any machine, across releases. That contract is enforced by golden baseline files: `pebble test` runs 491 checks covering terrain hashes over full chunk pipelines, a 55-mob zoo ticked 200 steps and compared at checkpoints, 911 transcendental-math probes, recipe/enchant/loot RNG lockstep, a redstone contraption timeline, and independent derivations of vanilla physics constants. The goldens are the contract that keeps the engine honest — a change that moves a single block in an existing world fails the suite.

Multiplayer doesn't rely on that contract: the LAN host runs the one real simulation and sends guests what happened, so a guest never has to reproduce the host's world on its own.

## Development hooks

Useful environment variables for testing and automation:

| Variable | Effect |
|---|---|
| `PEBBLE_AUTOLOAD=1` | skip menus, load the most recent world |
| `PEBBLE_NEWWORLD=<seed>` | create a fresh world with that seed (worldgen testing) |
| `PEBBLE_CMD="/tp 0 120 0;/time set 1000"` | run chat commands once the world is up (see the scripted steps below) |
| `PEBBLE_SHOT="/tmp/x.png@300"` | capture a frame N frames after load |
| `PEBBLE_SHOT_UI=1` | include the UI (HUD, chat, menus) in `PEBBLE_SHOT` captures, and allow captures on menu screens |
| `PEBBLE_WORLDS=1` | jump straight to the world-select screen |
| `PEBBLE_MULTIPLAYER=1` | jump straight to the Join LAN Game screen |
| `PEBBLE_MENU="Host LAN Game>Create New>Create & Host"` | click menu buttons by label, one every half second (menu-flow testing) |
| `PEBBLE_JOIN=127.0.0.1[:port]` | join a LAN game at launch |
| `PEBBLE_NAME=Bob` | play as Bob in LAN games (not saved to settings) |
| `PEBBLE_WINDOWED=1` | start in a window instead of fullscreen, and don't auto-pause in the background; `PEBBLE_WINSIZE=900x506` and `PEBBLE_WINPOS=0,0` place it (side-by-side LAN testing) |
| `PEBBLE_NETLOG=1` | print LAN message counts and chat every 5 s |
| `PEBBLE_BOT=1` | run the physics validation bot through the real input path |
| `PEBBLE_PHOTOBOOTH=1` | studio rig that captures every mob and block to PNGs (`PEBBLE_BOOTH_MOBS=cow,sheep` / `PEBBLE_BOOTH_BLOCKS=-` to filter) |
| `PEBBLE_PROF=1` | print per-stage load/tick timings |
| `PEBBLE_PACKDEBUG=1` | log texture tile coverage and entity-skin resolution |
| `PEBBLE_GEOM_DEBUG=1` | log entity geometry construction |
| `PEBBLE_REGOLD=1` | **rewrites golden baselines** — see CONTRIBUTING before using |

Scripted steps you can mix into `PEBBLE_CMD`:

| Step | Effect |
|---|---|
| `#wait N` | pause N frames before the next command |
| `#waitguests N` | pause until N LAN guests have joined |
| `#down B` / `#up B` | press / release mouse button B (0 left, 2 right) |
| `#key Code` | tap a key, e.g. `#key KeyQ` |
| `#slot N` | select hotbar slot N (1–9) |
| `#type text` / `#uikey Key` | type into / press a key on the open screen (e.g. a sign) |

## Reporting bugs & contributing

**Contribution is incredibly welcome.** This is a public beta: the engine is golden-tested, but the bug list is unknown by definition — the bugs are out there, and you will find them before we do. Every report genuinely helps.

Found a bug? [Open an issue](https://github.com/thebriangao/pebble/issues). To help us identify and fix it, please include:

- **macOS version and Mac model/chip** — e.g. "macOS 15.2, M2 MacBook Air".
- **Pebble version** — bottom-left of the title screen.
- **What you did, what happened, what you expected** — rough steps to reproduce are fine.
- **World context** if it's an in-world bug: the **seed**, the **dimension**, and your **coordinates** (the F3 overlay shows all three).
- **For LAN bugs:** whether you were the host or a guest, how many people were playing, and what the other players saw.
- **Settings that matter**: render distance and whether ultra graphics are on.
- **Screenshots or video** for anything visual.
- For crashes: the crash report from `~/Library/Logs/DiagnosticReports`, and terminal output if you launched with `pebble run` from a terminal.
- If the engine itself seems wrong (worldgen, physics, redstone): the tail of `pebble test` — it should print `491 passed, 0 failed`.

Even better than a bug report is a **pull request with a fix** — see [CONTRIBUTING.md](CONTRIBUTING.md) for the build/test workflow and the conventions that are load-bearing (registration order, RNG discipline, determinism rules). PRs of all sizes are wanted, from typo fixes to subsystem work.

- [CONTRIBUTING.md](CONTRIBUTING.md) — build, test, golden workflow, load-bearing conventions.
- [SECURITY.md](SECURITY.md) — threat model and how to report vulnerabilities privately. Pebble collects nothing, and touches the network only when you host or join a LAN game.
- [LICENSE](LICENSE) — MIT, covering the code in this repository. The bundled Faithful artwork is third-party content under its own terms.
- [CHANGELOG.md](CHANGELOG.md) — release history.

## Disclaimer

**Pebble is an independent, original fan re-creation. It is not an official Minecraft product. It is not affiliated with, endorsed by, sponsored by, or connected to Mojang Studios, Microsoft Corporation, or any of their subsidiaries, in any way.** "Minecraft" is a trademark of Mojang Synergies AB / Microsoft; Pebble does not use the name in the software and claims no association with the trademark holders.

Pebble's *gameplay design* is inspired by Minecraft: Java Edition 1.20 — game rules and mechanics reimplemented from publicly observable gameplay. Concretely:

- **No Mojang/Microsoft source code is used.** Every line of game code was written for this project by its author — the sole third-party-derived code is the fdlibm trigonometry port in `Sources/PebbleCore/Core/DetMath.swift` (Sun Microsystems' permissive license, notice preserved there). Nothing is decompiled, disassembled, copied, or derived from Minecraft's code.
- **No Mojang/Microsoft asset files are included.** The engine's texture atlas is generated by code; the default visual layer is the third-party Faithful 32x pack (credited below — the Faithful team's own artwork); sounds and music are synthesized in real time from oscillator recipes; fonts are a built-in bitmap glyph set; entity models are hand-written Swift reproducing the vanilla mobs' publicly documented box dimensions and UV layouts — required for Java Edition-format entity textures to map onto them correctly. There are no extracted game files anywhere in this repository.
- **Pebble is free, open-source, and non-commercial.** Its multiplayer is local-network only, using its own protocol between copies of Pebble. It never connects to Mojang or Microsoft services, or to any internet server, and it collects nothing.

**Third-party content:** the app bundle ships the complete, unmodified [Faithful 32x](https://faithfulpack.net) (1.20.1) as its built-in texture set. That artwork is the work of the Faithful team and its contributors, distributed under the [Faithful License](packaging/FAITHFUL-LICENSE.txt) (included verbatim here and in the app bundle, as it requires) — it is **not** covered by this repository's MIT license. Pebble is free and non-commercial, consistent with that license's no-monetization requirement. If anyone with rights in that artwork prefers it not be bundled, contact the address below and it will be removed promptly; Pebble remains fully functional without it. Pebble's ability to *read* the file format the artwork ships in is an independently implemented compatibility feature and implies no affiliation.

Pebble is provided "as is", without warranty of any kind (see [LICENSE](LICENSE)). It writes only to `~/Library/Application Support/Pebble/` and `~/Applications/Pebble.app`. Questions, concerns, or good-faith takedown requests from rights holders: **briangaoo2@gmail.com** (subject starting with `[pebble]`) — they will be honored quickly.

---

<p align="center"><em>Singleplayer &amp; LAN — better together.</em></p>
