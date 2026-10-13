# Contributing to Pebble

**Contribution is incredibly welcome.** Pebble is the open-source alternative to Minecraft: Java Edition, it's a public beta, and the bug list is unknown by definition — every issue filed and every PR opened genuinely moves the project. You don't need permission to start: pick something broken or missing and go. This file is short on ceremony and long on the things that will actually break the game if you don't know them.

## Filing a bug

Bug reports mean the world to us. [Open an issue](https://github.com/nullrouten0/pebble/issues) and include the critical bits that let us reproduce it:

1. **Device and OS** (e.g. "macOS 15.2, M2 MacBook Air" or "iPadOS 18, iPad Air M2")
2. **Pebble version** (bottom-left of the title screen)
3. **Steps**: what you did, what happened, what you expected
4. **World context** for in-world bugs: seed, dimension, coordinates (all on the F3 overlay)
5. **Settings**: render distance, ultra graphics on/off
6. **Evidence**: screenshots/video for visual bugs; `~/Library/Logs/DiagnosticReports` for crashes; the tail of `pebble test` if the engine seems wrong (expected: `535 passed, 0 failed`)

Even better than a report is a PR with the fix — the rest of this file tells you how to make one that lands.

## Setup

```bash
xcode-select --install        # Swift toolchain (Swift 6, macOS 14+ SDK)
git clone https://github.com/nullrouten0/pebble.git && cd pebble
swift build                   # debug build, ~35s clean
swift run -c release pebsmoke # the test suite — must print "535 passed, 0 failed"
./pebble install              # optional: build + install the real app
```

The Mac app has no `.xcodeproj` — its whole workflow is SwiftPM + the `./pebble` CLI. You can still open the folder in Xcode ("Open Package") if you want an IDE.

The iOS app is the one exception: `ios/project.yml` is an [XcodeGen](https://github.com/yonaskolb/XcodeGen) spec, and `pebble ios` turns it into `ios/Pebble.xcodeproj`. That project is generated and git-ignored — edit `project.yml` or `ios/Config/*.xcconfig`, never the project. iOS work needs full Xcode (16+) and `brew install xcodegen`; nothing else in the repo does.

```bash
pebble ios            # generate + open the Xcode project
pebble ios run        # build + launch in the iPad simulator (PEBBLE_SIM="iPhone 18 Pro" to switch)
pebble test ios       # the golden suite inside the iOS Simulator
cp ios/Config/Local.xcconfig.example ios/Config/Local.xcconfig   # then add your team ID to run on a device
```

### Where code goes

- **`PebbleCore`** — the engine. No UI frameworks, ever.
- **`PebbleApp`** — everything both apps share: renderer, UI, screens, HUD, audio, `GameRuntime` (owns the stack and the frame), `InputRouter`, `TouchControls`, `ControllerInput`. No AppKit or UIKit imports; anything platform-specific goes through the `PlatformHooks` protocol.
- **`Sources/Pebble/main.swift`** (macOS) and **`ios/PebbleiOS/`** — thin shells: window/view, native events → `InputRouter`, lifecycle, and a `PlatformHooks` implementation.

## Before you open a PR

1. `swift build -c release` — clean, **zero warnings**. The codebase is warning-free and stays that way.
2. `swift run -c release pebsmoke` (or `pebble test`) — **535/535**, from the repo root (goldens are found relative to cwd).
3. If goldens changed, your PR description must justify **every** changed value (see below).
4. Keep diffs surgical. Match the style of the file you're in — this codebase has a consistent voice (compact, comment-where-it-matters), and drive-by reformatting makes review impossible.

## The golden workflow (read this twice)

`goldens/*.json` pin the engine's behavior. Two categories:

- **Frozen reference goldens** — `atlas`, `fmath`, `items`. These are immutable reference baselines with no generator — they can **never** be regenerated. If your change breaks one, your change is wrong.
- **Native baselines** — `biome`, `terrain`, `feature`, `mesh`, `worldsim`, `entity`, `systems`. Regenerable with `PEBBLE_REGOLD=1 swift run -c release pebsmoke`, but only for *deliberate* behavior changes.

The required procedure for a behavior change:

1. Make the change. Run the suite. **Read every failure.**
2. For each failing check, explain to yourself (and in the PR) why your change moved that value. "Terrain hashes pass but feature hashes changed, consistent with my flower fix" — that level.
3. Only then regold, and re-run to confirm green.
4. Sanity-check the regold: `PEBBLE_REGOLD` rewrites whole files, and JSON key order shuffles, so byte diffs lie. Compare semantically (e.g. `python3 -c 'import json; print(json.load(open("a"))==json.load(open("b")))'`) and confirm that only the files you expected actually changed values.

Never blanket-regold to make red go green. The suite caught real bugs precisely because nobody did that.

## Conventions that are load-bearing

These are not style preferences. Violating them corrupts worlds or breaks determinism in ways the test suite will catch days later:

- **Registration order is ABI.** Blocks, items, biomes, and enchantments get their numeric ids from registration order, and those ids are in every saved world. Never insert, remove, or reorder registrations. New items/blocks are **appended at the end**, after the frozen baseline range, and baseline checks cover only that prefix (`BASE_ITEM_COUNT` in pebsmoke).
- **Sim code uses the deterministic layer only.** `detSin/detCos/detAtan2` (never `Foundation.sin` in sim paths), `RandomX`/`hash2`/`hash3` (never `Double.random` — cosmetic-only exceptions exist in app-side rendering/audio), `detRound` for half-step rounding.
- **No unordered iteration in sim decisions.** Swift `Dictionary`/`Set` iteration order is hash-seeded per process. If iteration order can affect world state, use an insertion-ordered array (see `tickingBEList`) or `.sorted()`.
- **Structure-piece RNG: draw, then check.** Builder RNG must be a pure function of (structure, piece). Draw every random value *before* any chunk-relative `b.get()` test — short-circuiting a draw on local chunk contents desyncs the stream across the chunks that rebuild the same piece. Also: `b.get()` returns **−1 outside the building chunk**; guard before casting.
- **Threading contract.** Chunks are built on the gen queue and published only via `adoptChunk` on main. UI/renderer state is main-thread-only. Saves go through the serial save queue. The audio render thread owns the voice list; talk to it through the inbox. One-time registration uses `let`-initialized globals (dispatch_once), not boolean guards.
- **GPU buffers the CPU rewrites per frame must be ring-buffered** (3 deep — see UICanvas, particles) or staged through blit encoders (see atlas animations). The renderer has no semaphore; it relies on the 3-drawable limit.
- **Version string** lives in one place: `PEBBLE_VERSION` (PebbleCore/Game/Saves.swift). Bump it there plus `packaging/Info.plist`. It's major.minor.revision: bump the **minor** for a release that adds features, the **revision** for a small feature or a fix. Builds show it with the commit appended (`1.3.0.2d559e0a`, `+` when built with uncommitted changes), so testers can tell exactly which build they're on; `./pebble` and the iOS project stamp the commit into Info.plist.

## Testing tips

- `PEBBLE_AUTOLOAD=1 PEBBLE_NEWWORLD=12345 swift run -c release Pebble` — straight into a fresh world.
- `PEBBLE_CMD="/tp 0 120 0;/time set 1000" PEBBLE_SHOT="/tmp/shot.png@600"` — scripted screenshots.
- `PEBBLE_POWERBENCH=1` (with `PEBBLE_AUTOLOAD=1 PEBBLE_NEWWORLD=12345`) — a hands-free 10-minute power benchmark: explore, revisit, dig, pause menu, idle. Every 10 s it logs fps, CPU %, GPU %, thermal state, battery and memory (`[power]` lines, plus `pebble-power.csv` in the debug output dir), then exits. `=0.2` scales the phases for a quick run. On a device, launch it from the Mac with `xcrun devicectl device process launch --console --environment-variables '{"PEBBLE_POWERBENCH":"1","PEBBLE_AUTOLOAD":"1","PEBBLE_NEWWORLD":"12345","PEBBLE_HOME":"powerbench"}' --device <id> net.stonekitty.pebble`; a relative `PEBBLE_HOME` lands in the app's tmp on iOS, away from real saves.
- `PEBBLE_HOSTLAN=1` with `PEBBLE_POWERBENCH=1 PEBBLE_BENCH_PHASES="idle:330"` — the host stands still and logs while guests explore: a hosting power/memory benchmark.
- On iOS, pass any of these to the app as `SIMCTL_CHILD_<NAME>=…` in front of `xcrun simctl launch`.

### Environment hooks

| Variable | Effect |
|---|---|
| `PEBBLE_HOME=/tmp/scratch` | saves and settings go there instead of your real profile |
| `PEBBLE_AUTOLOAD=1` | skip menus, load the most recent world |
| `PEBBLE_NEWWORLD=<seed>` | with `PEBBLE_AUTOLOAD`, create a fresh world with that seed instead |
| `PEBBLE_SETTINGS='{"maxFps":30}'` | override settings at launch (after the first-launch device preset); saved to the profile, so pair it with a scratch `PEBBLE_HOME` |
| `PEBBLE_CMD="/tp 0 120 0;/time set 1000"` | run chat commands once the world is up (see the scripted steps below) |
| `PEBBLE_SHOT="/tmp/x.png@300"` | capture a frame N frames after load |
| `PEBBLE_SHOT_UI=1` | include the UI in `PEBBLE_SHOT` captures, and allow captures on menu screens |
| `PEBBLE_WORLDS=1` | jump straight to the world-select screen |
| `PEBBLE_MULTIPLAYER=1` | jump straight to the Join LAN Game screen |
| `PEBBLE_MENU="Host LAN Game>Create New>Create & Host"` | click menu buttons by label, one every half second |
| `PEBBLE_HOSTLAN=1` | open the world to LAN as soon as it loads and print the address |
| `PEBBLE_JOIN=127.0.0.1[:port]` | join a LAN game at launch |
| `PEBBLE_NAME=Bob` | play as Bob in LAN games (not saved to settings) |
| `PEBBLE_WINDOWED=1` | start in a window instead of fullscreen, and don't auto-pause in the background; `PEBBLE_WINSIZE=900x506` and `PEBBLE_WINPOS=0,0` place it (side-by-side LAN testing) |
| `PEBBLE_TOUCH=1` | show the touch controls on the Mac |
| `PEBBLE_NETLOG=1` | print LAN message counts and chat every 5 s |
| `PEBBLE_BOT=1` | run the physics bot through the real input path, asserting walk/sprint/jump/fall-damage numbers |
| `PEBBLE_POWERBENCH=1` | the power benchmark above; `PEBBLE_BENCH_PHASES` overrides its phases |
| `PEBBLE_PHOTOBOOTH=1` | render every mob and block to PNGs (`PEBBLE_BOOTH_MOBS=cow,sheep` / `PEBBLE_BOOTH_BLOCKS=-` to filter) |
| `PEBBLE_PROF=1` | print per-stage load/tick timings |
| `PEBBLE_PACKDEBUG=1` | log texture tile coverage and entity-skin resolution |
| `PEBBLE_GEOM_DEBUG=1` | log entity geometry construction |
| `PEBBLE_REGOLD=1` | **rewrites golden baselines** — see [the golden workflow](#the-golden-workflow-read-this-twice) |

Scripted steps you can mix into `PEBBLE_CMD`:

| Step | Effect |
|---|---|
| `#wait N` | pause N frames before the next command |
| `#waitguests N` | pause until N LAN guests have joined |
| `#down B` / `#up B` | press / release mouse button B (0 left, 2 right) |
| `#key Code` | tap a key, e.g. `#key KeyQ` |
| `#slot N` | select hotbar slot N (1–9) |
| `#type text` / `#uikey Key` | type into / press a key on the open screen (e.g. a sign) |
| `#tdown ID X Y` / `#tmove ID X Y` / `#tup ID X Y` | drive the touch controls (UI units) |
| `#pos` | print the player's position and the block under the crosshair (with its break progress) |
| `#mem` | print draw counts, memory footprint and mesh arena size |

## Scope & conduct

Please open an issue to coordinate before large networking or architecture PRs; uncoordinated ones will likely be declined. Performance work is welcome but must keep goldens green and come with before/after numbers. Be a normal, decent person in issues and reviews; that's the whole code of conduct.

By contributing you agree your contributions are licensed under the repository's MIT license.

Pebble is an independent fan re-creation, not affiliated with Mojang Studios or Microsoft — see the README's [Disclaimer](README.md#disclaimer).
