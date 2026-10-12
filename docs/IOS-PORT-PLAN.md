# Pebble on iPad / iPhone — feasibility, performance, and port plan

## Status (2026-10-10, branch `ios-port`)

**Done and verified in the simulator** (iPad Pro 13" M5, iPhone 18 Pro, iOS 27):
- Step 0: noise tables moved to raw buffers. Cold 361-chunk gen went from 0.57 s at best (6 threads) to 0.12 s (14 threads), and it keeps scaling. `MAX_GEN_INFLIGHT` now follows the core count, and the stronghold cache is locked.
- Step 1: `PebbleApp` library + thin AppKit shell. macOS behavior is unchanged: shots match within run-to-run noise, and LAN host+guest work.
- Step 2: XcodeGen project, UIKit shell, lifecycle saves (background → kill → relaunch keeps the world), audio session, device presets, safe area, `pebble ios [open|build|run]`.
- Step 3: hardware keyboard (HID map, Cmd-. = Escape, Cmd-V), mouse/trackpad with pointer lock, game controllers. The controller code is shared, so it works on the Mac too.
- Step 4: touch overlay, touch over screens (long-press = right-click, drag-and-drop, Quick Move, ×, drag-scroll), soft keyboard for chat/signs/fields, and `GameCore.analogMove`, which has pebsmoke checks.
- `pebble test ios`: 488/488 inside the iOS Simulator.
- Milestone 2: memoryless scene depth, lazy ultra targets, the title photo freed in-world (iOS), the mesh arena releasing empty pages, adaptive render scale (GPU-time and thermal driven), a memory-warning handler, and light-frustum culling of the shadow pass (26–47% fewer shadow draws).
- Milestone 3 (started): Settings fits the 240-unit iPhone GUI.

**Not done yet:**
- **On-device testing** on the M-series iPad and the iPhone: signing (`ios/Config/Local.xcconfig`), real touch feel, pointer lock, controllers, thermals/Metal HUD, the `ultra_fs` depth-sampler check.
- Reading the Faithful pack straight from the bundle and loading it off the main thread. It loads in ~0.2 s and is copied once (11 MB), so this was left alone.
- `half` precision in shaders and a precompiled `.metallib`.
- Touch-control tuning: layout, sizes and look speed need a real hand on a real screen.
- iPhone: non-integer GUI scale and touch-sized inventory slots.

---

## Context

Pebble is a ~46k-line Swift + Metal voxel survival game (Minecraft-like) that currently ships only as a macOS app built with SwiftPM. You asked how hard it would be to run it on iPad or iPhone, and how well an iPad would perform, before committing to the port. This document has the evidence first, then the plan for the port itself.

**Decisions from you:**
- The first playable milestone includes **both** hardware input (keyboard, mouse, controller) **and** touch controls.
- **iPad first**; iPhone runs in landscape, with layout polish later.
- **Same repo.** The iOS app lives in `ios/` next to the Mac app, so one commit builds both. That keeps Mac↔iPad LAN play on the same version, and one `pebsmoke` suite covers both.
- **A shared `PebbleApp` SwiftPM library** holds the renderer, UI, screens, HUD, audio and input. The Mac and iOS apps are thin shells around it.
- **The iOS Xcode project is generated with XcodeGen** from a committed `ios/project.yml`; the `.xcodeproj` itself is git-ignored. macOS stays SwiftPM-only.
- **Bundle ID:** `net.stonekitty.pebble`.
- Test devices are an **M-series iPad and an iPhone**.

**Out of date since this was written (Pebble 1.2):**
- LAN multiplayer now exists. iOS needs `NSLocalNetworkUsageDescription` and `NSBonjourServices: [_pebble._tcp]` (copy them from `packaging/Info.plist`).
- The golden suite is now **485** checks, not 461.
- File and line references below may have shifted.
- Full Xcode is **not installed** on the dev Mac (only the Command Line Tools), so the iOS build evidence below came from an earlier setup. Install Xcode 16+ and XcodeGen before any iOS work.

**Bottom line:** the port is very feasible. The engine already builds and passes every golden check on iOS. The new work is the app shell, input, and a touch UI. Performance on M-series iPads should be comfortable, with headroom. On iPhone, expect a solid 60 fps with a lighter preset.

---

## Evidence gathered (scratch copy at `/tmp/pebble-ios-probe`; the repo was not touched)

| Test | Result |
|---|---|
| Compile `PebbleCore` + `pebsmoke` for **iOS device** (arm64, Release, iOS 17 min) | **BUILD SUCCEEDED, zero source changes.** The only change was adding `.iOS(.v17)` to the scratch `Package.swift` |
| Run the 461-check golden suite **inside the iOS Simulator runtime** (`simctl spawn`) | **461 passed, 0 failed.** Seeds produce the same worlds on iOS |
| Native macOS golden run | 461/461 in 2.0 s. Full overworld chunk ≈ 3 ms on one core; section mesh 0.1–0.6 ms |
| Chunk-gen scaling benchmark (rd 8 = 361 chunks, cold) | Best wall time is **4 threads: 0.68 s**. It gets *slower* with more threads: 1.4 s at 10 and 3.0–3.4 s at 14 |
| `sample` of the 14-thread run | Over 40% of samples are in `swift_retain`/`swift_release`. Cause: `SimplexNoise` uses `private var perm/permMod12` arrays (`Sources/PebbleCore/Core/Noise.swift:19-20`) on a shared generator, so all threads fight over the same atomic reference count |
| GPU/CPU/memory benchmark: the real macOS app with a scratch-only bench mode, windowed at exact device pixel sizes on this M4 Pro (20-core GPU) Mac mini | Table below |

### Measured on M4 Pro (20-core GPU), median of steady-state per-second samples

| Config | Drawable | GPU ms/frame | Main-thread CPU ms/frame* | Peak footprint |
|---|---|---|---|---|
| Default (rd 8, shadows, bloom) | 2752×2064 (iPad Pro 13") | 3.3 | 0.6 | 920 MB |
| Ultra (SSAO + volumetrics, 4096² shadows) | 2752×2064 | 3.2 | 0.7 | 1.05 GB |
| Lite (rd 6, no shadows, no bloom) | 2752×2064 | 2.2 | 0.4 | 790 MB |
| Default, rd 12 | 2752×2064 | 3.4 | 0.9 | 1.27 GB |
| Default, rd 16 | 2752×2064 | 3.9 | 1.6 | 1.73 GB |
| Default | 2266×1488 (iPad mini) | 3.4 | 0.8 | 870 MB |
| Lite | 2266×1488 | 1.7 | — | 740 MB |
| Default | 2622×1206 (iPhone 17 Pro) | 3.1 | 1.0 | 870 MB |
| Lite | 2622×1206 | 1.7 | — | 740 MB |

\* Main-thread work per frame after the drawable is acquired. The 20 Hz simulation tick (≈2.8 ms) lands on about one frame in three at 60 fps. Draw calls: ~1,600 at rd 8, ~3,850 at rd 16.

### Projected to devices (estimate: measured GPU ms × spec-ratio factor, ±30–40%)

| Device | GPU factor vs M4 Pro 20c | Default @ native | Lite @ native | Expectation |
|---|---|---|---|---|
| iPad Pro M5 / M4 | ~1.7–2.3× | ~6–8 ms | ~4–5 ms | Solid 60 with thermal headroom; 120 Hz is reachable |
| iPad Air M3 / M2 | ~2.4–2.8× | ~8–9 ms | ~5–6 ms | Solid 60 |
| iPad mini (A17 Pro) | ~3.5–4.5× | ~12–15 ms | ~6–8 ms | Lite needed for a sustained 60 |
| iPad 11th gen (A16) | ~4.5–5.5× | ~15–19 ms | ~8–9 ms | Lite required |
| iPhone 17 Pro (A19 Pro) | ~2.5–3× | ~8–9.5 ms | ~4–5 ms | 60 is good; iPhones throttle sooner than iPads |

- **CPU:** not a concern.
- **World load:** about 1–2 s once the noise fix is in.
- **Memory:** ~0.75–0.95 GB at rd 6–8 is safe on every target device. The mesh arena never frees pages (`Sources/Pebble/WorldRenderer.swift:41-107`), so the footprint only ever grows during a long session.
- **Thermals:** the Mac mini has a fan; iPads and iPhones are passively cooled, so ship with a 60 fps cap and keep the GPU headroom. The macOS "unlimited" mode (a 0.1 ms timer with vsync off, `main.swift:557-577`) must not exist on iOS.

---

## Feasibility by layer

| Layer | iOS status | Effort |
|---|---|---|
| `PebbleCore` engine | Compiles and passes all goldens as-is. `vcSupportDir()` (`Settings.swift:68`) resolves into the app sandbox automatically | None |
| Renderer (runtime-compiled MSL) | Uses no macOS-only Metal APIs and is already tile-friendly. One item to check on a device: `ultra_fs` samples `depth32Float` with a linear sampler (`Shaders.swift:620`); a nearest sampler is the fallback | Small |
| UI canvas, screens, HUD | Metal-drawn with no AppKit. Auto GUI scale fits iPad as-is (18-unit slot ≈ 54–63 pt). Hover tooltips, right-click and shift-click need touch equivalents | Medium |
| App shell (`main.swift`) | Needs a UIKit rewrite. Coupling outside main.swift is small: `gAppDelegate`/`gameView` in `MenusM.swift:267,403-421`, `NSApp.terminate` in `MenusM.swift:46`, and `bundleResourcePath` in `ResourcePacks.swift:348` and `WorldRenderer.swift:394,399` | Medium |
| Audio | Add `AVAudioSession`, interruption and route-change handling | Small |
| Hardware input | The engine already exposes `keyDown/keyUp/mouseDown/mouseUp/mouseDelta/wheelHotbar` (`GameCore.swift:2003-2099`), and `Bot.swift` already drives the player through them | Small–medium |
| Touch input | New overlay, container gestures, soft keyboard | **Large** |
| Distribution | Personal devices via Xcode signing; TestFlight for internal testers. An App Store release is unlikely (guideline 4.1, Minecraft trade dress, Faithful's no-monetization license) | n/a |

---

## Repo structure (decided)

### Target layout
```
pebble/
  Package.swift            products: PebbleCore, PebbleApp (new lib), Pebble (mac exe), pebsmoke
  Sources/
    PebbleCore/            engine — unchanged
    PebbleApp/             NEW lib: WorldRenderer, Shaders, UICanvas, UIManagerM, ScreensM, MenusM,
                           HudM, Audio, ResourcePacks, ParticlesM, EntityRendererM, CommandsM, MathM,
                           Bot, PhotoBooth + new GameRuntime, InputRouter, PlatformHooks
    Pebble/                macOS shell only: main.swift (NSWindow/NSMenu, NSEvent→InputRouter, cursor capture)
    pebsmoke/              tests, runnable on macOS and the iOS simulator
  ios/
    project.yml            XcodeGen spec (committed); the generated .xcodeproj is git-ignored
    PebbleiOS/             UIKit shell: AppDelegate, SceneDelegate, GameViewController (MTKView),
                           iOS input glue, Info.plist, Assets.xcassets (AppIcon)
    Config/Shared.xcconfig bundle id, deployment target, version (committed)
    Config/Local.xcconfig  DEVELOPMENT_TEAM (git-ignored; Local.xcconfig.example committed)
  packaging/               shared art + Faithful pack (bundled by both apps)
  docs/IOS-PORT-PLAN.md    this file, moved out of the repo root
  pebble                   CLI: add `pebble ios` (generate + open/build)
```

### Setup steps
1. **Prerequisites (you):** install full Xcode (16 or newer) from the App Store, then run `sudo xcode-select -s /Applications/Xcode.app` and `brew install xcodegen`.
2. **Package.swift (no change for macOS):**
   - `platforms: [.macOS(.v14), .iOS(.v17)]`.
   - A new `PebbleApp` library target depending on PebbleCore. It links Metal, MetalKit, QuartzCore and AVFoundation; AppKit is linked only `.when(platforms: [.macOS])`.
   - The `Pebble` executable depends on PebbleApp.
3. **Split the macOS target:** this is Step 1 of the port plan below. Gate:
   - `pebble test` shows 485/485.
   - A `PEBBLE_SHOT` frame for a fixed seed is pixel-identical before and after.
   - Manual smoke test of menus, inventory, chat, paste, and LAN host/join.
4. **iOS scaffold:**
   - `ios/project.yml` defines one iOS app target, `PebbleiOS` (product name "Pebble", iPad + iPhone). It depends on the local package product `PebbleApp`.
   - Bundled resources: `../packaging/Faithful 32x - 1.20.1.zip`, `logo.png`, `title-bg.png` and `FAITHFUL-LICENSE.txt`.
   - Settings come from `Config/Shared.xcconfig`, which does `#include?` on `Local.xcconfig`.
   - Info.plist keys are listed in Step 2 below, plus the local-network/Bonjour keys.
   - Version has a single source: the CLI reads `PEBBLE_VERSION` (`Sources/PebbleCore/Game/Saves.swift`) and writes `MARKETING_VERSION` when it generates the project, so both apps report the same version.
   - First goal: the app boots to the title screen in the iPad simulator.
5. **Repo plumbing:**
   - `.gitignore`: add `ios/*.xcodeproj`, `ios/Config/Local.xcconfig`, `ios/build/` and `DerivedData/`.
   - `pebble ios`: checks for Xcode and XcodeGen, writes the version, runs `xcodegen` and opens the project. `pebble ios build` builds for the iPad simulator.
   - Optional `pebble test ios`: runs pebsmoke in the simulator (needs a `PEBBLE_CWD` hook in pebsmoke).
   - Move this file to `docs/`, and update `ARCHITECTURE.md` (PebbleApp layer, two shells) and `CONTRIBUTING.md` (iOS build steps).
6. **Branching:** work on `main` in small commits. The split only tidies macOS, and its gates catch regressions. `ios/` doesn't affect the Mac build or `pebble update`.

### Structure verification
- A fresh clone and `./pebble install` still work with **no** Xcode or XcodeGen installed, so iOS stays opt-in.
- macOS: 485/485, the pixel-identical shot, and a live LAN host+guest run (the side-by-side `PEBBLE_WINPOS` test hooks).
- iOS: `pebble ios build` succeeds, the app boots to the title screen in the iPad Pro 13" simulator and loads a world, and pebsmoke passes 485/485 in the simulator.

---

## Port plan

### Milestone 1 — playable on iPad (and iPhone in landscape) with touch and hardware input

**Step 0 — cross-platform groundwork (also helps macOS)**
1. `Package.swift`: add `.iOS(.v17)`, make the AppKit link `.when(platforms: [.macOS])`, and add the new `PebbleApp` library product (Step 1).
2. Fix the noise contention in `Sources/PebbleCore/Core/Noise.swift`:
   - Build `perm`/`permMod12` once in `init` and store them as immutable unsafe buffers, or at least as `let` arrays.
   - Do the same for `GRAD3`.
   - The arithmetic stays the same, so the goldens must stay 461/461.
3. Derive `MAX_GEN_INFLIGHT` (`GameCore.swift:18`) from `activeProcessorCount` instead of the fixed 24.
4. Synchronize `strongholdCache` (`Sources/PebbleCore/Gen/StructUnderground.swift:8`). It is unsynchronized global state written from gen threads.

**Step 1 — split the macOS app target into a shared library with a narrow public API**
- New SwiftPM library target `PebbleApp` (`Sources/PebbleApp/`). Move in WorldRenderer, Shaders, UICanvas, UIManagerM, ScreensM, MenusM, HudM, Audio, ResourcePacks, ParticlesM, EntityRendererM, CommandsM, MathM, Bot and PhotoBooth. The last two are env-var debug hooks; change their `/tmp` paths to `NSTemporaryDirectory()`.
- New `GameRuntime` class in `PebbleApp`. It owns `game`, `renderer`, `ui`, `hud`, `audio` and `HostBridge`, plus today's `draw(in:)` body (`main.swift:579-674`), resize and the `PEBBLE_*` test hooks. Shells call `runtime.draw(view)`, `runtime.resize(size)`, `runtime.pause()/resume()` and `runtime.saveNow()`.
- New `InputRouter` in `PebbleApp`, containing the logic from `GameView` (`main.swift:184-369`):
  - `key(code:down:repeat:)`, `text(_:)`
  - `pointerDown/Move/Up(guiX:guiY:button:)`, `wheel(step:)`
  - `look(dx:dy:)`, `modifiers(shift:ctrl:)`
- New `PlatformHooks` protocol, implemented by each shell: `resourcePath(name)`, `canQuit/quit()`, `supportsFullscreen/isFullscreen/toggleFullscreen()`, `setPointerCaptured(_:)`, `pasteboardString()`, `safeAreaInsets`. Replace the `gAppDelegate`/`NSApp`/`bundleResourcePath` uses listed above with these hooks.
- Remove the unused `import AppKit` lines in ResourcePacks, WorldRenderer and PhotoBooth (use ImageIO). Put the `displaySyncEnabled` unlimited-fps mode behind `#if os(macOS)`.
- `Sources/Pebble/main.swift` shrinks to the macOS shell: NSWindow, NSMenu, NSEvent → InputRouter, CG cursor capture.
- Gate: `pebble test` shows 461/461, and a `PEBBLE_SHOT` frame for a fixed seed is pixel-identical before and after.

**Step 2 — iOS shell (`ios/project.yml` → generated `Pebble.xcodeproj`, plus `ios/PebbleiOS/`)**
- The app target depends on the local package's `PebbleApp` product.
- Info.plist: `UIRequiresFullScreen`, landscape orientations, `UILaunchScreen`, `CADisableMinimumFrameDurationOnPhone`, `UIApplicationSupportsIndirectInputEvents`.
- Asset catalog for the AppIcon (from `packaging/logo.png` / icon art). Bundle the resources: the Faithful zip, logo.png, title-bg.png and FAITHFUL-LICENSE.txt.
- `AppDelegate` + `SceneDelegate` + `GameViewController` hosting an `MTKView` subclass:
  - `preferredFramesPerSecond = 60`, plus a 120 option on ProMotion.
  - `contentScaleFactor` → GUI units.
  - Lifecycle: on `sceneWillResignActive`, pause the view and audio and open the pause screen. On `sceneDidEnterBackground`, call `saveAndFlush` inside `beginBackgroundTask`.
- Audio: `AVAudioSession` category `.ambient`, restart the engine after interruptions, and re-read the sample rate on route change (`Audio.swift:88-97`).
- Device presets on first launch:
  - iPad: rd 8, shadows and bloom on, ultra off.
  - iPhone: rd 6, shadows off, bloom on.
  - Hide Quit, Fullscreen and "Unlimited" fps in Settings on iOS.
- Safe-area insets: pass them through `PlatformHooks` into `UIManager`. Inset the HUD hotbar (`HudM.swift:95-96`), the chat overlay and the effect icons.

**Step 3 — hardware input on iOS**
- Keyboard: `pressesBegan/Ended` → a `UIKeyboardHIDUsage` → DOM-code table (a parallel of `KEYCODE_MAP`, `main.swift:12-29`). Map the modifier keys directly; this replaces the `flagsChanged` workaround.
- Mouse: `GCMouse.mouseInput.mouseMovedHandler` → `look`, buttons → `pointer`/`mouseDown`, scroll → `wheel`. Use `prefersPointerLocked` while in-world with no screen open.
- Controllers: `GCController` extended gamepad, polled each frame in `GameRuntime`:
  - left stick → move, right stick → look
  - triggers → break/use
  - shoulders → hotbar
  - A → jump, B → sneak
  - menu → pause, Y → inventory
  - On screens, the right stick drives a virtual cursor.
- When any hardware input is connected, hide the touch overlay. Show it again on the next touch.

**Step 4 — touch controls (crosshair-style, so the engine's aim ray needs no changes)**
- `TouchOverlay` in `PebbleApp`, drawn with `UICanvas` after the HUD, with its own multi-touch tracking by `UITouch` identity:
  - **Left side:** a floating virtual stick feeding analog movement. Pushing past the outer ring sprints.
  - **Right side:** drag to look, using a separate touch-sensitivity setting.
  - **Tapping the look area** uses/places through the existing `mouseDown(2)/mouseUp(2)` path. **Pressing and holding still** (~250 ms within a few UI units of the press) breaks or attacks through `mouseDown(0)` and its existing per-tick hold logic. As in Minecraft, only a fresh press digs: steering past that slop releases the break until the finger lifts (a held use stays down so bows can aim); creative breaks erode over `creativeBreakDelay` (0.4 s on touch).
  - **Buttons:** jump (double-tap toggles flight, as today), sneak toggle, inventory, pause, chat, drop, perspective, offhand swap.
  - **Hotbar:** tap a slot to select it; long-press drops it. Slot layout comes from `HudM.swift:95-96`.
- Engine: add an optional analog override for `moveForward`/`moveStrafe` (`GameCore.swift:1402-1406`). The keyboard path stays untouched, so the goldens are unaffected. A pebsmoke check confirms the override is inert when unset.
- Screens:
  - One finger maps to the existing pointer flow.
  - Long-press on a slot = right-click (place one / take half) plus its tooltip.
  - A "quick move" toggle replaces shift-click (`UIManagerM.swift:481-495`).
  - Larger hit radius in `slotAt` (`UIManagerM.swift:152-154`).
  - Offset the held stack and tooltip above the finger (`UIManagerM.swift:240-247`).
  - A close (×) button on the 16 screens that only close with Escape.
  - Tap-vs-drag detection plus drag-to-scroll for `WorldSelectScreen` (`MenusM.swift:172-189`) and the Creative grid (`ScreensM.swift:1166-1191`).
- Text: a hidden `UIKeyInput` responder in `GameViewController`. Show it when a `TextField` is focused (`UIManagerM.swift:65-94,111`) or when the Chat/Sign screen opens (`ScreensM.swift:1211-1374`). Map `insertText` → `onChar`, `deleteBackward` → `onKey("Backspace")`, return → `onKey("Enter")`. Turn autocorrect off, and shift the chat input above the keyboard.

### Milestone 2 — mobile hardening
- **Render scale:** the scene renders at 0.6–1.0× of the drawable. The composite already samples by UV (`Shaders.swift:548-552`). Add adaptive scaling when the GPU frame time stays above ~80% of budget, or when `ProcessInfo.thermalState` reaches `.serious`.
- **Memory:**
  - Make `sceneDepth` `.memoryless` when ultra is off, and allocate the ultra targets and the 4096² shadow map only when ultra is on (`WorldRenderer.swift:607-716`).
  - Release the 28 MB title-bg texture once in a world.
  - Reclaim empty mesh-arena pages.
  - Handle memory warnings by dropping render distance.
- **GPU:** frustum-cull the shadow pass (`WorldRenderer.swift:888-905`), use `half` in shaders where it's safe, and precompile a `.metallib` (optional).
- **Launch:** load the Faithful pack off the main thread and read it straight from the bundle, not a copy in Application Support (`ResourcePacks.swift:345-352`).

### Milestone 3 — iPhone polish
- Design for the 240-unit GUI height: fix the Settings overlap below 250 units (`MenusM.swift:441,517`), consider non-integer GUI scale, and use touch-sized slots for inventory.
- Tune the overlay for smaller screens.

---

## Verification
- **Engine:** `pebble test` on macOS must show 461/461 after every step. Also run on iOS: build `pebsmoke` with `xcodebuild -scheme pebsmoke -destination 'generic/platform=iOS Simulator'`, then run `SIMCTL_CHILD_PEBBLE_CWD=$PWD xcrun simctl spawn booted <DerivedData>/Release-iphonesimulator/pebsmoke`. This needs a small `PEBBLE_CWD` hook added to pebsmoke, like the one in the scratch probe.
- **Noise fix:** goldens stay 461/461. Re-run the scratch chunk-gen benchmark (`/tmp/pebble-ios-probe/Sources/pebgenbench`); wall time should now fall monotonically up to the core count.
- **macOS regression (Step 1):** the `PEBBLE_SHOT` frame for a fixed seed is identical before and after. Smoke-test menus, inventory, chat and paste by hand.
- **iOS functional:** build and run in the iPad Pro 13" and iPhone 17 Pro simulators. Check title → create world → play → inventory/crafting → chat/text → pause → background/foreground → relaunch (save persists).
- **On device (M-series iPad + iPhone):**
  - Metal HUD (`MTL_HUD_ENABLED=1` in the scheme) for frame and GPU time.
  - Xcode memory gauge: expect ≤1 GB at the presets.
  - Instruments Game Performance template for a 15-minute soak at 60 fps, watching thermal state.
  - Test keyboard/mouse and controller input on the iPad.
