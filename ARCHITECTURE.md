# Pebble — Architecture

This is the technical tour. The one-paragraph version: **PebbleCore** is a headless, deterministic game engine (no UI framework imports anywhere); **PebbleApp** is the shared app stack — the Metal renderer, the synthesized audio engine, the UI, and input routing — with no AppKit or UIKit either; **Pebble** (macOS, `Sources/Pebble`) and **PebbleiOS** (iPad/iPhone, `ios/`) are thin shells that own a window and translate native events; **pebsmoke** is the regression harness: contract checks, behaviour checks, and snapshots in `goldens/`. The app talks to the engine exclusively through the `GameHost` protocol, and the engine never draws, plays, or reads input directly.

```
┌──── Pebble.app (macOS) ─────┐   ┌──── Pebble (iPad / iPhone) ────┐
│ main.swift: NSWindow, menus,│   │ ios/PebbleiOS: UIKit scene,    │
│ NSEvent → key codes, cursor │   │ touches, HID keys, GCMouse,    │
│ capture, fullscreen         │   │ soft keyboard, lifecycle saves │
└──────────────┬──────────────┘   └───────────────┬────────────────┘
               │   PlatformHooks · InputRouter · TouchControls
┌──────────────┴──────── PebbleApp (shared library) ┴──────────────┐
│  GameRuntime       owns game/renderer/UI/audio, the frame loop,  │
│                    HostBridge, PEBBLE_* test hooks               │
│  InputRouter       key codes + pointer → open screen or game     │
│  TouchControls     on-screen stick/look/buttons, touch screens   │
│  ControllerInput   gamepads (move/look/break/use, menu cursor)   │
│  WorldRenderer     Metal pipelines, mesh arena, atlas, shadows,  │
│                    sky/celestials/clouds, bloom, ultra, capture  │
│  UICanvas/UIManager/Screens/Menus/HUD   canvas-2D-style batcher, │
│                    screen stack, 17 gameplay screens, menus      │
│  Audio             AVAudioSourceNode synth, recipes, reverb      │
│  ResourcePacks     built-in Faithful loading (installed by       │
│                    the core's PackInstall)                       │
└────────────────────────────┬─────────────────────────────────────┘
                   GameHost protocol (openScreen, playSound,
                   addParticles, mesh upload, chunk requests…)
┌────────────────────────────┴─────────────────────────────────────┐
│                         PebbleCore                               │
│  GameCore (20Hz tick orchestrator)  ·  GameWorld  ·  LightEngine │
│  Net (LAN host/guest sessions over TCP + Bonjour)                │
│  Gen (terrain/biomes/features/structures)  ·  Entity (AI)        │
│  Items (recipes/enchants/loot)  ·  Systems (sparkstone/interact/…) │
│  Render (mesher + texture atlas — data only, no Metal)           │
│  Saves (SQLite)  ·  Core (fdlibm, RNG, noise)                    │
└──────────────────────────────────────────────────────────────────┘
```

## The determinism layer (Core/)

Pebble's engine is fully deterministic — identical seeds produce identical worlds on any machine, across releases — and everything downstream depends on this layer:

- **`DetMath.swift`** — fdlibm 5.3c `sin`/`cos`/`atan`/`atan2` implemented with only IEEE-754 primitive operations, so trig results never depend on the platform math library. Also `detRound` (well-defined `.5` boundary behavior) and hypot helpers.
- **`RandomX.swift`** — sfc32-style seeded RNG plus `hashString`, `mix32` (murmur3 finalizer), and `hash2`/`hash3` position hashes. All arithmetic uses explicit 32-bit wrapping, so hashes are identical everywhere. Position hashing is what makes features/structures reproducible per-coordinate rather than per-generation-order.
- **`Noise.swift`** — simplex 2D/3D with a seeded permutation shuffle, FBM stacks, spline interpolation.

Rules that keep determinism intact are listed in CONTRIBUTING — the short version is: sim code never touches `Double.random`, `Date`, or unordered collection iteration.

## World & simulation

- **`Chunk`** — 16×384×16 cells, one `UInt16` per cell packed as `(blockId << 4) | meta`. Separate sky/block light arrays, a heightmap, and biome data at 4×4×4 resolution. Dimensions: overworld y −64…320, nether 128, end 256.
- **`GameWorld`** — chunk map, block get/set with light + remesh propagation, scheduled ticks (binary heap with stable tie-break ordering), random ticks, block entities (insertion-ordered ticking), entity lists, raycasting. Behavior is attached via handler registries (`blockTickHandlers`, `randomTickHandlers`, `neighborHandlers`, `beTickHandlers`, `onPlacedHandlers`) that the Systems modules fill at startup.
- **`LightEngine`** — incremental flood-fill for sky and block light with cross-chunk seam stitching. Never propagates into missing chunks (frontier rule), heals dropped chunks once a second.
- **`GameCore`** — the orchestrator. Fixed 20 Hz tick (50 ms), with chunk generation on a concurrent queue (capped in-flight), meshing on its own queue, and saves on a serial queue. Chunks are generated off-main and only published to the world on the main thread (`adoptChunk`), which is the threading contract that keeps the engine lock-free. Autosave every 60 s; unloads batch their writes into one SQLite transaction per second. A chunk loaded again before its record reaches disk is served that record from memory (the unload buffer, or a write still on the save queue), never an older one from the database.

## Worldgen (Gen/)

Climate sampling (six FBM samplers seeded from the world seed) feeds spline lookups for base height, erosion flattening, and peak/valley amplitude; a 3D density lattice (sampled at fixed f32 precision for reproducibility, interpolated per-cell) carves cheese/spaghetti/noodle caves; worm carvers and ravines run after; aquifers place water/lava bodies; surface rules paint grass/dirt/sand/deepslate; ores follow per-band attempt tables. Structures use a region grid (`spacing`/`separation`/`salt`) with a `check` predicate and a `plan` that emits **pieces** (AABB + build closure). Every chunk within `maxRadiusChunks` of an origin re-runs the plan and builds only the pieces that intersect it — which is why **piece RNG must be a pure function of (structure, piece), never of the target chunk**, and why every random draw happens *before* any chunk-relative `get()` check.

## Entities (Entity/)

`Entity` (AABB physics with auto-step, fluid state, fire, riding) → `LivingEntity` (health, effects with insertion-order semantics, equipment, per-entity seeded RNG) → `Mob` (goal selectors with stable priority sort, A* grid navigation up to 600 nodes) → 100 concrete types. The player's physics are exact: input ×0.98, ground accel `speed × 0.21600002 / slip³`, friction `slip × 0.91`, gravity `(vy − 0.08) × 0.98`, jump 0.42 + sprint boost, water/lava/wingsuit regimes, sneak edge-guard. Those constants are *derived* in the test suite, not just asserted. Riders steer their mount through their own input (`moveForward`, `jumping`, `sneaking`, `yaw`), so a LAN guest's synced input drives a mount on the host the same way. The flying mounts (`FlyingMount`: `Pegasus`, `Dragon`, `Alicorn`, `Griffin`) switch gravity off while `flying` and fly like creative flight; a mount with a power (`hasPower`/`usePower`: fire, bolts, a screech) runs it each tick its rider holds attack (`Player.powerHeld`, synced for guests); what the renderer and guests need (tamed, saddled, flying, wing spread, using the power) lives in `EntityData`.

## Rendering

Engine side (`Render/`): the **mesher** consumes a padded 18×18×18 snapshot and emits opaque/cutout/translucent vertex buffers — greedy quad merging for full cubes, per-vertex AO, smooth light, biome tint, and an animation channel (water/lava/portal/fire/sway). Vertex format is 28 bytes / 7 words. The **atlas substrate** generates all 789 tiles in code with integer-only color math (snapshotted by `atlas-goldens.json`); the built-in Faithful art overlays it. Tiles drawn as block entities in the pack format (beds, chests, the bell, the decorated pot) have no flat `block/` texture there — the loader composites them from the art's `entity/` unwraps, so every visible surface comes from the Faithful set (the only substrate tiles left at runtime are the three airs, a particle speck, and the end-portal effect, which packs don't provide as a texture either).

App side (`WorldRenderer`): runtime-compiled MSL (no `.metal` files — SPM doesn't build them), a **mesh arena** of 32 MB shared `MTLBuffer` pages with a first-fit free list and 3-frame deferred frees so all section draws bind one buffer at different offsets. Pass order: shadow (PCF/Poisson, snapped texel grid) → sky gradient → stars → celestials (Faithful sun/moon drawn additively) → clouds → opaque → cutout (back-culled) → translucent → entities (pose animator, Faithful skins) → particles (instanced, triple-buffered) → ultra (half-res SSAO + shadow-marched volumetrics) → bloom → composite (ACES) → UI. The UI is a single draw call: `UICanvas` mimics Canvas2D (fillRect, gradients, transforms, text via a built-in 5×7 font or the Faithful font sheets) into one vertex stream with a texture-segmented batch.

CPU/GPU synchronization leans on `CAMetalLayer`'s default 3-drawable back-pressure: the mesh arena defers frees 3 frames, and UI/particle instance buffers are 3-deep rings. Atlas animation updates are staged into buffers and blitted at frame start so in-flight frames never see a half-written texture.

## Audio

No samples. `Audio.swift` is a synthesizer (on iOS it runs under an `.ambient` audio session and rewires itself after interruptions and route changes): each sound effect is a recipe that spawns voices (oscillator or filtered noise) with envelopes, pitch sweeps, and vibrato, mixed in an `AVAudioSourceNode` render callback at 48 kHz. Effects: RBJ biquad filters, positional stereo panning, underwater lowpass, and a cave reverb built from two coprime-length feedback delay lines. Music (ambient + jukebox discs) is generated on the fly from scale/tempo configs. The render thread owns the voice list; the main thread communicates through a locked inbox.

## LAN multiplayer (Net/)

The host runs the only real simulation; guests run a copy of the world that the host fills in. Transport is Network.framework TCP (Nagle off) with length-prefixed binary frames (`NetCodec.swift`), and games are advertised and found over Bonjour (`_pebble._tcp`). Frames are parsed on each connection's queue and handed to the main thread through a locked inbox, drained once per tick, so game state stays main-thread only.

- **Host (`NetHost`).** Each guest gets a stand-in `Player` in the host world, so mobs target it and pressure plates see it. The guest moves it and owns its health and inventory; anything the host world does to the stand-in (damage, pickups, XP, effects, knockback, teleports) is forwarded to the guest through `NetPlayerLink`. Per tick the host streams lzfse-compressed chunks nearest-first around each guest, sends block changes (a whole chunk is resent after a big edit), tracks entities in range (spawn with their save data, then per-tick pose snapshots), syncs changed block entities, and relays sounds, particles, time, weather and chat. Chunk loading, random ticks, entity simulation and mob spawning cover every player, not just the host.
- **Guest (`NetClient`).** The guest simulates only its own player; entities are drawn copies that are never ticked. Actions run locally for instant feedback and are also sent to the host, which replays them with the guest's held items (`performUse`, `finishBreaking`, `playerAttack`…) so world effects happen once. Item and XP drops the guest predicts are forwarded instead of duplicated. After each action the host resends the cells around it, which repairs any misprediction.
- **Edits and undo.** `EditBatch` records an owner (`editOwner`), so each player's undo/redo only touches their own edits. A building tool or undo that moves a player (see below) tells the host through `WorldHooks.onPlayerMovedByTool`, which teleports that guest at once.

**Building tools and undo (Systems/).** Every big edit is an `EditBatch`: `/fill` (`fillBox`), `/place`, paste and cut, the wall and box builders, the destroyers and the mountain. It records each changed cell once (only cells inside the world and in loaded chunks), relights whole chunks at the end when it's large (`bulkLight`), and then `liftEntities` lifts anyone a block of the edit landed inside (players and guests, mobs, vehicles with their riders, by the blocks' real collision shapes) onto the first spot where they fit. Undo restores the cells and puts lifted people back where they stood. x and z stay within `WORLD_COORD_LIMIT` (±30M): commands clamp to it and portals arrive inside it. The creative Tools menu (`ToolsScreen`) adds no new paths: its entries come from `toolEntries` (Systems/ToolCatalog.swift), and each one is a chat command run through `runCommand`, so a LAN guest's world edits still run on the host. Checks hold the catalog to what the commands accept.

The determinism contract isn't needed for this: guests never re-simulate anything, they only show what the host sends.

## Persistence

One SQLite database (WAL, FULLMUTEX, serial save queue): `worlds(id, json, lastPlayed)`, `chunks(world, dim, cx, cz, data)`, `player(world, json)`, `advancements(world, json)`, `palette(world, json)`. LAN guests who visit a world are stored in `player` under `<world id>#guest:<name>`. Chunk blobs are a small binary container (`VCK1`, or `VCK2` zlib-compressed: flags, u16 block array, biome array, JSON tail for block entities + entities).

Every generated chunk is saved in full, blocks included, the first time it's saved (tracked via `savedFullKeys`), so changes to world generation never reach land a player has seen. Records written before 1.5 may be entity-only stubs; those chunks regenerate once (with the world's generator) and are then saved in full. `WorldRecord.genVersion` says which generator builds a world's new chunks: 1 for worlds made before 1.5 (positional feature salts, unpruned trees), 2 since.

Block and item ids follow registration order, which may change between builds. Each world's `palette` row lists the names behind its ids; `SaveDB.migratePalette` rewrites a world saved under a different palette once, on open (chunk cells, item stacks anywhere in the JSON, `blockCell`/`movedCell`), mapping renames through `BLOCK_ALIASES`/`ITEM_ALIASES` and turning removed blocks into air and removed items into empty slots. Failed batches log and re-mark chunks dirty for retry. Corrupt blobs are clamped (out-of-range block ids → air) rather than trusted. A record that would be written byte-for-byte as last time is skipped (`SaveDB.writtenHashes`); that memory is dropped whenever a world is opened, since another build may have rewritten it meanwhile.

A shared world (`.pebbleworld`, UTI `net.stonekitty.pebble.world`) is a SQLite file with the same five tables holding one world's rows, plus `share(key, value)` naming the format (`pebble-world-1`) and the exporting version. `SaveDB.exportWorld` attaches a new file and copies the rows across; `importWorld` attaches one read-only (a `file:…?mode=ro` URI) and copies its rows in under a fresh world id (renaming guests' `<old id>#guest:` rows to match) and a name that doesn't clash. The palette travels with the world, so the usual migration covers another build's ids. The shells reach it through `PlatformHooks.shareFile`/`pickFile` and `GameRuntime.openFile`.

## The test harness (pebsmoke)

About 900 checks, run with `pebble test`:

random/noise/math → block & item registries → biomes (all 63 defs + 2,000 biome selections) → terrain (full pipeline hashes on 2 seeds) → features (whole-chunk generation across all three dimensions) → atlas (pixel-identical tiles) → mesher (vertex/index hashes) → world sim (light, fluids over hundreds of ticks, RNG lockstep) → items (recipes/enchants/potions/loot rolls) → fdlibm (911 probes) → entities (55-mob zoo × 200 ticks, combat, scripted player physics, trades, pathfinding, spawning) → systems (crafting probes, BE timelines, a full sparkstone contraption, explosion crater, interactions, portals) → a suite that *independently derives* the physics constants instead of trusting goldens → and analog (stick/touch) movement checked against the keyboard path through a live headless `GameCore`.

pebsmoke builds and runs on iOS too: `pebble test ios` spawns it inside the iOS Simulator runtime, where the same seeds produce the same worlds.

The checks come in three kinds (see CONTRIBUTING, "Tests"): **contracts** that never change (portable math probes, generator-version-1 chunks, every save format and palette migration), **behaviour checks** that state rules, and **snapshots** in `goldens/*.json` that detect change. A snapshot is regenerated deliberately with `pebble test --regold <names>`, which prints every key whose value moved.
