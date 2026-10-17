# Changelog

All notable changes to Pebble. Versions follow `MAJOR.MINOR.PATCH`; the
in-app version string comes from `PEBBLE_VERSION` (PebbleCore/Game/Saves.swift).

## 1.8.0 — 2026-10-17 — flying mounts

- **Ride a pegasus or a dragon through the sky.** Both are new creatures you
  saddle and fly. Climb on with an empty hand, then fly the way creative
  flight works: W flies where you're looking, Space takes off and climbs,
  Shift descends, and sprint flies faster. On the ground they walk like a
  horse. On iPad and iPhone the jump and sneak buttons do the same.
- **Getting one.** From the Tools menu's Creatures tab (they're at the top),
  a spawn egg, `/summon` or `/spawn`, a pegasus or dragon arrives tamed and
  saddled, ready to ride. Wild pegasi live in meadows and cherry groves, and
  wild dragons on mountain peaks; they take short flights of their own and fly
  off when hit. Tame a wild one by feeding it (golden carrots or golden apples
  for a pegasus, raw meat or fish for a dragon — each try has a one-in-three
  chance), then put a saddle on it. Tamed ones heal and breed on the same food.
- **The dragon breathes fire.** Hold attack while riding one: everything
  living in a cone ahead of it, up to 10 blocks, catches fire, except you and
  your tamed pets. It doesn't set blocks alight, so builds are safe. Fire and
  lava can't hurt a dragon.
- **Shift gets you off any mount.** There was no way to get off a horse,
  pig, strider or camel yourself; a fresh Shift press on the ground now steps
  you off beside it. On a flying mount Shift descends instead, so land, let
  go and press it again.
- **Riding is smooth.** The camera used to jump along with the mount 20 times
  a second; it now glides with it. In third person (F5) it sits further back
  on a big mount, so the dragon's wings and head stay in view.
- **LAN guests can ride, fly and breathe fire** too.
- **Fixed: many particles were invisible.** Flames, smoke, hearts, crits,
  rain and snow splashes, petals and notes drew only an empty corner of their
  picture. They all show now.
- Snapshots moved: the biome spot checks (the new spawns) and the item
  snapshot's enchantment `applies` and enchantability hashes (two new spawn
  eggs lengthen the item list). Nothing else changed.

## 1.7.3 — 2026-10-15 — Tools menu tooltips

- **The Tools menu's tooltips no longer cover what you're pointing at.**
  The description used to pop up right at the pointer, on top of the entry
  and its neighbours. It now appears just below the entry (above it near the
  bottom of the screen), so the name stays readable.

## 1.7.2 — 2026-10-15 — spawn crash fix

- **Fixed a crash when spawning lots of creatures with the Blight among
  them.** Clicking creatures in the Tools menu without moving puts each one
  on the same spot. Once the Blight finished charging and went after a
  creature directly below it, it divided by its zero distance to that
  creature, flew off to nowhere and took the game down. It now just hovers.
- **An XP orb exactly at your eye no longer has the same problem.**
- **A safety net:** a creature asked to move by an impossible amount (from
  any bug like this) now stands still instead of crashing the game.

## 1.7.1 — 2026-10-15 — tool icons

- **The seven building and demolition tools have real icons** in place of
  the coloured blobs they've shown since 1.1.0. They appear in the
  inventory, the hotbar, your hand and the Tools menu:
  - **Bazooka:** an olive launch tube with a red warhead.
  - **Mining laser:** a ray gun with a red-hot emitter.
  - **Void bomb:** a dark orb with a violet rim and a sparking fuse.
  - **Quarry charge:** a red charge over a drill bit.
  - **Wall builder:** a brick wall with a gold arrow rising from it.
  - **Box builder:** an open-topped stone box.
  - **Infinity Wipe:** a glowing infinity sign.
- **A thrown void bomb now looks like the void bomb** in flight, not a
  heart of the sea.

## 1.7.0 — 2026-10-15 — Creative Tools menu

### Creative Tools menu
- **Everything the building and demolition releases added, without typing.**
  Press **G** (rebindable in Options → Controls) or tap the new toolbox
  button, marked G, at the top of a touch screen. It's for creative mode
  only. In survival, G just says so, and the button is hidden.
- **Four tabs:**
  - **Tools** puts a tool in your hand. It has the bazooka, mining laser,
    void bomb, quarry charge, wall and box builders, Infinity Wipe, selection
    wand and headlamp.
  - **Structures** has every `/place` structure, the mountain included, and
    places it in front of you. **Layout** picks one of ten layouts, the same
    as `/place`'s variant number.
  - **Creatures** spawns one creature in front of you, or all ten anime
    animals at once. Each spawn egg shows beside its name.
  - **Edit** has undo, redo, selection corners at your feet, copy, cut,
    paste, paste skipping air, and clear selection. Undo and redo are now one
    tap away on iPad and iPhone.
- **What happened shows at the bottom of the menu**, such as where a
  structure landed or why a paste didn't. Hovering an entry shows the command
  it runs, so you can learn the typed form.
- **The menu stays open**, so you can place, spawn and undo in a row. G again,
  Esc or Done closes it.
- **It works for LAN guests.** Every entry runs its chat command, so a
  guest's structures, creatures and undo still run on the host, the same as
  typing them.

### Also
- **`/spawn <creature>`** brings one creature in front of you, on the
  ground and facing you, like `/spawn anime_zoo` does for a group.

### Development
- **`#click X Y` in `PEBBLE_CMD`** clicks the open screen at UI units X, Y,
  for scripted menu checks.
- **Five new checks (897).**
  - The menu offers every special tool and every `/place` structure, and each
    structure's layouts.
  - It offers every creature group and creature.
  - The Edit tab has undo, redo and the clipboard.
  - A single `/spawn` lands ahead of you on the ground.
  - A tool added later without a menu entry fails the first check. I tested
    this by leaving one out.

## 1.6.22 — 2026-10-15 — /spawn anime_zoo

- **`/spawn anime_zoo` brings all ten anime animals at once**, in rows of
  five a few blocks ahead of you, each on the ground and facing you. They
  stay until you remove them, like ones you summon. `/spawn` alone lists the
  groups; this is the first, and the creative menus to come will use the
  same groups. A LAN guest's `/spawn` runs on the host, in front of the guest.

## 1.6.21 — 2026-10-15 — round six fixes

Fixes from a review of 1.6.13–1.6.20, several in those releases' own changes.

- **LAN guests really are freed now.** When the host's `/place`, paste,
  builder or undo lifted a guest out of blocks, the guest's own next report
  put them straight back, and they stayed stuck; undo putting a guest back
  was lost the same way. The guest is now teleported the moment it happens.
- **Only people a block actually landed in are lifted.** The lift also moved
  anyone inside the edit's whole box who didn't quite fit: a minecart rider
  under a two-high tunnel roof (sent up through the rock, off the rails),
  someone asleep in a low bedroom, someone in a crawl space, or a vex.
- **Undo puts you back safely** even if a block went in where you stood
  since; you land on top of it instead of inside it.
- **`/place` of a buried structure in the Nether or near the top of the
  world no longer crashes the game**, and puts nothing above the build
  limit. Buried structures get their marked entrance in the Overworld only.
- **A chunk you come straight back to can't be overwritten by its older
  copy** when you save right after, and its chests and furnaces are no longer
  shared with the copy waiting to be written. Coming back while that copy is
  still being written no longer waits for the write.
- **A world rewritten by another build** (an older one opening it) is now
  saved in full again when you reopen it here; before, chunks this build had
  saved earlier could be skipped and left in that build's block ids.
- **A save that fails while leaving a world** is retried for that world, not
  applied to the next one you open.
- Leaving a world lets go of a rising mountain; mountains pin land only in
  their own dimension; big `/place` clearings relight in bulk; a whole
  dimension unloads in one pass; portals arrive a few blocks inside the edge.
- **Measured, about saving:** 1.6.18's skip helps chunks that truly didn't
  change, but in a lived-in world about a third of the loaded chunks really
  do change each minute (grass, crops, leaves), so autosave still writes them:
  about 90 chunks, 350 KB and 5 ms of main-thread time a minute.
- `pebble check-pack` now says why when the app quits before loading the
  pack (it exited silently); a default pack replaced under its own name is
  put back with a message saying so.

## 1.6.20 — 2026-10-14 — loose ends

- **`/place` keeps a full 3 blocks clear of you**, as 1.6.12 said; rounding
  could bring the footprint to about 2.
- **Undoing `/place` brings back a chest's own contents** when the structure
  put a chest exactly where yours was.
- **A paste that would land entirely outside the world is refused** instead
  of reporting an upside-down box and using up an undo step.
- **Leaving a world forgets everything the editing tools held on to:** the
  mining laser's last burst, running carve jobs, and the wall and box
  builders' memory of recent builds (which a new world could pick up).
- Big `/fill`s and `/place`s relight each chunk once, like pastes.
- The selection wand's outline really no longer builds lists every frame
  (1.6.11 missed a few); `pebble check-pack` cleans up after itself if
  interrupted and notices at once if the app quits early; the mountain aims
  with the same maths as everything else; the anime animals' quirks (the
  tanuki's mask, the chick's flutter, the neko landing on its feet) are named
  per animal rather than read off body shapes.

## 1.6.19 — 2026-10-14 — pack and portal edges

- **The built-in texture pack notices when it's been swapped.** It was
  re-copied only when this build's release differed from the one recorded
  beside it, so if an older build copied its own art over it (opening the
  same profile), newer builds kept that older art until the next release.
  The pack's installed size is now recorded too, and a pack that no longer
  matches is copied again. Builds from 1.6.8 on still read the same record.
- **Portals stop at the world's edge.** Coming out of the Nether multiplies
  your position by 8, which from far enough out landed past the ±30 million
  blocks commands keep to (and past where undo can keep track). You now
  arrive at the edge instead.

## 1.6.18 — 2026-10-14 — saving skips unchanged land

- **Saving skips land that hasn't changed.** Since 1.6.1, every save
  (including the one-minute autosave) wrote out every loaded chunk with an
  animal or a chest in it, whether anything had changed or not: dozens of
  chunks each time in a lived-in world. A chunk that would be saved exactly
  as it was last time is now skipped.
- **Save & Quit saves once.** It saved the world and then saved it again on
  the way out; quitting the app did the same in a LAN game.
- Saving also sorts creatures into their chunks once, rather than going
  through every creature in the world for each chunk.

## 1.6.17 — 2026-10-14 — baby zombies stay put

- **Zombies keep their speed across a save.** Every zombie, husk and drowned
  re-rolled its 1-in-20 baby chance as it loaded and kept the speed from that
  roll, so some adults came back running at a baby's speed and saved babies
  came back at an adult's. Speed now follows whether it's a baby.
- **A baby zombie that drowns stays a baby.** The baby drowned it turned into
  grew up 20 minutes later; and an adult zombie could turn into a baby
  drowned. It's now the same age it was, and baby monsters already saved
  with a countdown stay babies.

## 1.6.16 — 2026-10-14 — nobody stays stuck in blocks

- **No building tool leaves anyone stuck inside blocks.** The box builder
  clicked on the ground you stand on put its floor at your feet; a paste, a
  `/fill`, or an undo that closed a hole you'd walked into could seal you in
  too. Each of them now lifts anyone left inside blocks onto the first spot
  where they fit, as `/place` and the mountain did.
- **Everyone is freed, not just you.** `/place` lifted only the player who
  ran it: in a LAN game the host or the other guests stayed stuck in its
  walls. Players, guests, mobs, and boats or minecarts with their riders are
  all lifted now.
- **It only lifts people who are really stuck.** Standing on a slab, a path
  or farmland counted as being inside a block, so someone under a low
  ceiling could be pushed up through the roof. It now goes by the blocks'
  real shapes, across a mob's whole width.
- **A buried structure's entrance can't wall you back in.** `/place` lifted
  you before it built the ladder shaft and flag, so they could go in around
  you; it now lifts once everything is built.
- **Undo puts lifted people back.** Undoing a structure that lifted you onto
  its roof dropped you from up there (with fall damage); you're now put back
  where you stood, if you haven't moved since.

## 1.6.15 — 2026-10-14 — quick revisits keep your changes

- **Land you leave and come straight back to keeps your changes.** A chunk
  you moved away from waited up to a second before it was written to disk,
  and coming back read only what was on disk: `/tp` away and back quickly
  and it loaded as it was at the last save (or as brand-new land), and the
  next save wrote that over your changes. Loading now picks up a chunk's
  newest record, written yet or not.

## 1.6.14 — 2026-10-14 — placed lurker boxes keep their own items

- **Lurker boxes placed in creative keep their own items.** Creative keeps
  the box in your hand, and every box placed from it shared the same stacks
  with it and with each other: take half a stack from one and the others
  lost it too. Each placed box now gets its own copy.

## 1.6.13 — 2026-10-14 — undo leaves untouched land alone

- **Undo no longer erases land an edit never touched.** An edit that reached
  land that wasn't loaded yet, or above the top of the world, wrote nothing
  there but remembered it all as air. Walk over and `/undo` later, and that
  whole box of ground was dug out; a `/fill` far above the build limit dug
  out a block somewhere else entirely. Edits now remember only the blocks
  they really changed.
- **`/fill` says when it can't reach.** It refuses a box outside the world's
  height or in land that isn't loaded, instead of reporting blocks it never
  placed, and its count is the blocks it changed.

## 1.6.12 — 2026-10-14 — /place lands clear of you

- **`/place` no longer drops a structure on top of you.** It aimed the
  middle of the structure half its width ahead of you, which only cleared
  you when you faced straight along an axis. Turned even 20°, a city's
  corner reached back over where you stood, burying you in its walls: the
  view broke through the terrain and you (and any pets) were stuck. It now
  picks the nearest spot along your view that keeps the whole footprint at
  least 3 blocks away, whichever way you face.
- **Anyone a structure lands on is lifted out.** If something placed with
  `/place` (say at coordinates you typed) ends up around you or a mob, you
  move up to the first spot where you fit instead of staying stuck inside it.

## 1.6.11 — 2026-10-13 — tidying

- The selection wand's outline no longer builds new lists of points every
  frame, and code comments that had gone wrong or ended up beside the wrong
  function are fixed. Nothing changes in play.

## 1.6.10 — 2026-10-13 — anime animal touch-ups

- **Kitsune Kit's three tails wag out of step**, as they were meant to; the
  two side tails moved together.
- **Ears twitch from their base.** An anime animal's ear twitch turned
  around the middle of its head, so the ears slid across it; they now pivot
  where they meet the head.

## 1.6.9 — 2026-10-13 — editing tool fixes

- **Undo works anywhere.** More than about 16.7 million blocks from the
  centre of the world, undo said it had worked but left everything as it
  was. It now reaches as far as you can teleport.
- **Redo isn't lost to an edit that changes nothing**, such as pasting a copy
  over itself. Only an edit that actually changes a block clears it.
- **`//paste` checks its options.** Anything other than `-a` is refused with
  a usage hint instead of being ignored.
- **Paste and undo messages are exact.** A paste that runs past the top or
  bottom of the world reports the part inside it, and undo counts only the
  blocks it actually put back.

## 1.6.8 — 2026-10-13 — texture pack updates by release

- **The built-in texture pack updates by release.** Pebble replaced its copy
  of the default pack whenever the file size differed from the one in the
  app, and deleted the old copy before copying the new one, so a failed copy
  (a full disk, say) silently left you on the plain fallback textures. It now
  records which release it installed and copies a newer one once, beside
  the old file before swapping it in. A failure is logged and leaves the
  working pack where it is.

## 1.6.7 — 2026-10-13 — unknown creatures are kept

- **Opening a world in an older version keeps the newer mobs.** A version
  that didn't know a creature (opening a 1.6 world in 1.5, say) left it out
  when it loaded the world and then saved over it, so it was gone for good.
  From this version on, creatures Pebble doesn't recognise are kept in the
  save as they were and come back in the version that knows them. Versions
  before 1.6.7 can't do this, so open worlds with anime animals in 1.6 or
  later.

## 1.6.6 — 2026-10-13 — anime animal hitboxes, fluttering chick

- **Anime animals can be clicked where they look like they are.** Their
  hitboxes stopped below the tops of their big heads and well short of the
  long faces, so feeding, hitting or name-tagging the head missed, and
  arrows passed through it. Each is now as tall as its head and wide enough
  to cover most of a long face, while still fitting through one-block gaps.
- **Piyo Chick flutters.** It flapped its wings in the air but fell like a
  stone. It now drifts down like a chicken and takes no fall damage, and
  Bell Neko lands on its feet like a cat.

## 1.6.5 — 2026-10-13 — undo stays with its world; the wand never digs

- **Undo stays with its world.** Leaving a world kept its undo history, so
  Cmd-Z in the next world you opened "undid" an edit in the world you'd left.
  Nothing visible happened, an undo step was used up, and the old world was
  kept in memory. Leaving a world now clears it.
- **The selection wand never digs.** Holding the button down with another
  item and then scrolling to the wand kept breaking blocks.

## 1.6.4 — 2026-10-13 — big pastes without the freeze

- **Big copy-and-paste edits no longer freeze the game.** Pasting, cutting,
  undoing or redoing a large box (up to the 100×100×100 limit) updated the
  lighting one block at a time, which could hang the game for up to half a
  minute. Edits of more than 4,096 blocks now relight each chunk they touch
  once, plus the chunks around them, when they finish. The largest paste
  measured went from 26.6 s to 0.5 s, and undoing it from 5.6 s to 0.3 s.

## 1.6.3 — 2026-10-13 — pasted lurker boxes keep their own contents

- **Pasted lurker boxes have their own contents.** Copying a chest that held
  a filled lurker box and pasting it gave both chests the same box contents:
  taking items out of one box took them out of the other too. Every copy of
  an item now copies what's inside it.

## 1.6.2 — 2026-10-13 — bred animals grow up

- **Bred animals grow up.** A baby stayed drawn at half size forever, for
  you and for LAN guests, even once it had grown up. Feeding a baby that was
  close to grown, or reloading the world while it was a baby, could also stop
  it growing for good. Babies now keep their time to grow up in the save, and
  ones already stuck in a world start growing again.
- **Baby zombies are drawn small**, as they always should have been.

## 1.6.1 — 2026-10-13 — saving keeps your animals and chests

- **Saving keeps everything again.** Saving (the pause menu, quitting, or the
  minute-by-minute autosave) wrote only chunks whose blocks had changed. A
  mob you summoned, bred or led into a part of the world that was already
  saved, or a chest you filled there, was missing when you came back, unless
  you had wandered far enough away for that land to unload first. Saving now
  uses the same rule as unloading: any chunk with mobs, chests, furnaces or
  other block entities in it, or that mobs have just left, is written.

## 1.6.0 — 2026-10-13 — anime animals, Faithful September 2026

### Anime-style animals

- **Ten anime-style animals**: Mochi Bunny, Kitsune Kit, Bell Neko, Leaf
  Tanuki, Bao Panda, Puff Shiba, Scarf Penguin, Hamu Hamster, Momiji Red
  Panda and Piyo Chick. Chibi proportions, big sparkly eyes and blush, and a
  body built for each: a round bunny with big flat hind feet, a leggy
  kitsune with three brush tails, a sleek neko with its tail held up and a
  bell collar, a pot-bellied tanuki with a leaf on its head, a chunky panda,
  a shiba with a chest ruff, white socks and a curled tail, an egg-shaped
  penguin in a scarf, a hamster that's nearly a ball, a long red panda with
  a huge ringed tail, and a puffball chick.
- **Placed only:** each has a spawn egg (in the Spawn Eggs tab, coloured like
  the animal) and works with `/summon`. They never spawn naturally, so
  worlds and their wildlife are unchanged.
- They're gentle passive animals: they wander, look at you, panic when hit,
  follow you for their favourite food and breed with it. They bounce as they
  walk (the bunny hops, the penguin and chick waddle), tilt their heads,
  twitch their ears and wag their tails.
- Each has its own synthesized voice: a soft chirp, a squeak when hurt.

### Faithful September 2026

- **Textures:** the built-in Faithful 32x pack for 1.20.1 is now Faithful's
  September 2026 release (was December 2025): 539 textures updated, the same
  coverage as before. An existing install replaces its old copy on the next
  launch.
- **License:** the bundled Faithful License is now version 4 (Jul 31, 2026),
  an unmodified copy of the file inside the pack.
- **Credits:** they now say "by Faithful", the name Faithful uses for itself,
  instead of "the Faithful Team". The README describes the license's
  current terms (no paywall, no monetized download links) instead of the
  old blanket no-monetization rule.

## 1.5.5 — 2026-10-13 — paste where you look

- **`//paste` goes where you're looking**, up to 96 blocks away, the way a
  placed block would. In 1.5.4 it kept its old position relative to you, so
  after you turned around it landed behind you, out of sight.
  - Looking at the ground or a floor: the copy stands on it, centred across
    your view and running away from you.
  - Looking at a wall: it grows out of the wall toward you.
  - Looking at a ceiling: it hangs from it.
  - Looking at grass or other plants you could build through: it replaces
    them instead of floating on top.
  - Looking at open sky: it lands 3 blocks ahead, level with your feet.

## 1.5.4 — 2026-10-13 — copy and paste

- **`//copy`** copies the selection to your clipboard: blocks plus their
  contents, such as chest items and sign text. **`//cut`** also clears it.
- **`//paste`** puts the clipboard back where it sat relative to you when you
  copied (1.5.5 changes this to where you're looking). **`//paste -a`** skips
  the clipboard's air, so it doesn't carve out what's around it.
- Each paste or cut is one undo step. **`//undo`** and **`//redo`** work the
  same as `/undo` and `/redo`.
- Up to 1,000,000 blocks (100×100×100) at a time. The whole area must be
  loaded. Mobs and dropped items aren't copied. Each player has their own
  clipboard, and it's cleared on quit.
- For now, only the host can copy and paste in a LAN game.
- **Undo restores chest contents in more cases.** Undoing an edit that
  replaced a chest with an identical-looking one brings back the original's
  items. Undoing an edit that added a furnace, chest or similar where there
  was none no longer leaves its contents data behind.

## 1.5.3 — 2026-10-13 — selection wand

- **Selection wand (`selection_wand`).** Left-click a block to mark corner 1
  and right-click for corner 2. The wand never digs or places. The action bar
  shows each corner and the box's size, e.g. "12×5×9, 540 blocks".
- **`//pos1` and `//pos2`** mark a corner at your feet, or at `x y z`
  (`~` works). **`//desel`** clears the selection.
- The selection shows as a gold box with a red marker on corner 1 and a blue
  one on corner 2. Its edges are thick, dark-bordered strips that stay a few
  pixels wide at any distance and still show, a little dimmer, through
  terrain.
- The selection belongs to one dimension and is cleared on quit. It's the
  groundwork for copy and paste, which come next.
- Release builds no longer fail on toolchains that time out type-checking the
  view-frustum box test.

## 1.5.2 — 2026-10-13 — texture credits

- The title screen's texture credit reads "Textures: Faithful 32x by the
  Faithful Team - faithfulpack.net", and clicking it opens
  [faithfulpack.net](https://faithfulpack.net/) (Mac and iOS).
- The end credits name the pack, the team and the Faithful License, and
  say Pebble isn't affiliated with or endorsed by the Faithful Team; the
  README says the same.
- Mac packaging always ships the Faithful License alongside the pack.

## 1.5.1 — 2026-10-13 — Pebble's own names

- **New names across the game.** A few creatures, blocks and items have
  Pebble names now: fizzlers, riftwalkers and riftmites, the rift dragon,
  the blight, wailers, cinders, lurkers (and lurker boxes), snouters,
  tuskers and ghoultusks, mushcows, wingsuits, darksteel, sparkstone,
  hush blocks, lumenstone, glowcaps, violite, seaglass, ashrock, conjurers,
  marauders, lifecharms, the rift eye and the Bugbane enchantment. `/give`
  and `/summon` use the new names.
- **New wording** for death messages and all 55 advancements.
- Existing worlds open with everything renamed in place: blocks, items,
  creatures, effects, enchantments and earned advancements carry over.
- Resource packs in the standard pack layout still apply: their texture
  names are translated on load.

## 1.5.0 — 2026-10-13 — worlds that survive updates

Pebble no longer tries to match the JavaScript original it was ported from,
and its saves are built to outlast changes to the game.

- **Every chunk you visit is saved, blocks and all.** Before, untouched
  land was saved without its blocks and rebuilt from the seed each time it
  loaded, so any change to world generation quietly reshaped places you'd
  already seen. Now generation changes only affect land nobody has visited.
- **Worlds remember which block and item each id means.** A build that
  adds, moves, renames or removes blocks and items opens existing worlds
  correctly: the world is updated once, the first time it opens. A
  removed block becomes air, and a removed item leaves an empty slot.
- **New worlds** place trees, flowers, ores and other decorations from
  each feature's name, so future additions can't reshuffle the rest; trees
  never generate leaves out of their logs' reach (those used to start
  falling as soon as snow settled on them). **Worlds created before 1.5 keep
  their original generator**, so their unvisited land matches what it would
  always have been.
- **Blast furnaces only smelt ores and smokers only cook food** (the blast
  furnace used to take sand, cobblestone and logs).
- Open 1.5 worlds only in 1.5 or later: older builds don't know about
  palettes or generator versions.

For contributors: CONTRIBUTING now sorts the 788 checks into contracts,
behaviour checks and snapshots, and `pebble test --regold <names>`
regenerates snapshots and lists exactly what changed.

## 1.4.11 — 2026-10-13 — anvils are "Too Expensive!" again

- **Anvils have a limit:** a job costing 40 levels or more says
  "Too Expensive!" and can't be taken in survival (creative ignores the
  limit). Renaming alone is held at 39, so you can always rename an item.
  Pebble used to cap every job at 39, so heavily reworked gear could be
  combined forever.
- Mob data that nothing drew is gone: the brown mushcow toggle from
  lightning, tropical fish patterns and panda genes. Spawns are unchanged
  (their random draws stay).

## 1.4.10 — 2026-10-13 — fewer strings standing in for types

No visible changes. Which hand an item use runs in and a mob's spawning
category are enums now (`Hand`, `MobCategory`) instead of strings, so a
typo is a compile error rather than a silent miss — the same kind of slip
that broke long-fall damage before 1.4.7. Mining speed and harvesting
share one tool-match rule, and the stacking test is named `sameItem` so
it isn't mistaken for `==`.

## 1.4.9 — 2026-10-13 — thread-safe registration

No visible changes. The thirteen one-time registrations (blocks, items,
entities, biomes, recipes, loot, models, painters and the systems
handlers) run through `let`-initialized globals, which Swift runs exactly
once even if two threads ask at the same moment, instead of boolean flags
that two threads could both see as unset. CONTRIBUTING asks for this.

## 1.4.8 — 2026-10-13 — one copy of each

No visible changes: code that existed twice now exists once (the noise
permutation shuffle, name prettifying, angle wrapping, item pickup for
local and LAN players, the box geometry for TNT/falling blocks and the
block-crack overlay, the enchantment level pick), the chunk renderer
compiles one pipeline where it compiled two identical ones, and explosions
track destroyed blocks by exact position.

## 1.4.7 — 2026-10-13 — fall damage, spiders, mobs that remember

- **Falls over 5 blocks follow the rules again.** Feather Falling now
  protects against them, armor no longer does, and
  cats, chickens, bees, parrots, bats, lurkers and iron golems are immune
  at any height, not just short drops.
- **Spiders are neutral in the light:** they only come for you in the
  dark, though they still fight back if you hit one.
- **Natural regeneration is fixed:** with a full food bar, the
  fast heal spends saturation and slows down as saturation runs below 6.
- **Saved and reloaded correctly now:** a slime's size and health,
  saddles on striders and camels (which also drop their saddle),
  vindicator captains, charged fizzlers, hanging bats, and bees that have
  stung (they used to survive a reload).
- **Death messages** for arrows, fireballs, blight skulls, thorns, stings
  and fireworks ("was shot by Skeleton" instead of "died"); fire deaths
  say "burned to death".
- **Lit fizzlers swell** before they blow, for you and for LAN guests.
- **LAN guests see skeletons and pillagers aim.** Also on LAN: stacks of
  stone (item 0) no longer vanish when they're dropped, picked up or
  handed between host and guest.
- **Ruined portals in the Nether** get their Nether variant (less decay,
  more magma and lava).
- Leather boots carry you through powder snow at full speed.

## 1.4.6 — 2026-10-13 — faster world generation, sound and particles

Same worlds, less work:

- **World generation** no longer looks up a stronghold plan for every chunk
  within 11 chunks of each one it builds (about 530 lookups a chunk, which
  also kept flushing the village and mineshaft plan cache); climate is
  sampled once per chunk instead of twice; biome feature lists are parsed
  once at startup instead of for every chunk.
- **Sound:** envelopes and pitch glides cost one `exp` per voice per audio
  block instead of a `pow` per sample.
- **Particles:** expiring and over-the-cap particles are removed in one pass
  instead of shifting the whole list each time (noticeable in heavy rain or
  snow), and instances are written straight into the GPU buffer.
- **Flowing water and lava** search for drops about 3× faster.
- **Mob pathfinding** uses a heap for its open list; despawn checks look
  only at players; unloading a chunk removes its mobs and block entities in
  one pass.
- **UI:** colours are parsed once rather than on every fill; the HUD
  hearts, sprites and translucent-pass lists stop allocating per frame.
- **Resource packs:** applying packs opens only the enabled ones, once
  (it used to unzip every pack in the folder twice).

## 1.4.5 — 2026-10-13 — dead code out

Mostly invisible: about 500 lines that nothing called are gone (an unused
vector/matrix/easing library, an old chunk-lighting path, three HDR render
pipelines that were compiled at every launch and never used, helpers that
were never wired up). Worlds generate exactly as before. What you might
notice:

- **"What a Deal!"** is granted when you actually trade, not when you open
  a villager's trade screen.
- The renderer culls chunks with the same tested frustum code the test
  suite checks, with Metal's near plane, and without allocating every
  frame.
- The world list no longer builds a date formatter every frame.

## 1.4.4 — 2026-10-13 — crash and exploit fixes from a code review

- **Anvils charge you.** Taking an anvil result when you couldn't afford
  it used to work and just left you at level 0. Now the result can't be
  taken until you have the levels (creative is free).
- **Crashes fixed:** hovering an item enchanted with `/enchant <id> 0`;
  `/tp`, `/setblock`, `/fill` and `/summon` with `nan` or huge
  coordinates; `/effect`, `/xp` and `/fill` with numbers big enough to
  overflow; `/host 65530`; a resource pack whose `font/ascii.png` is wider
  than it is tall; more than 4095 different icons in one session.
- **LAN hosts and guests check what they receive.** A guest (or host)
  sending a bad block face, NaN or huge positions, an unknown item,
  enchantment or effect, a second hello, or a 2-billion-XP orb can no
  longer crash or flood the other side; bad messages are dropped and
  unknown items become empty slots.
- **Saves:** stacks of items this build doesn't know (say, from a newer
  build's world) load as empty slots instead of crashing on the first draw.
- **Lurkers open** when they shoot or peek (the lid never moved), and a
  peek now lasts a second instead of one tick.
- **Sound:** the audio thread no longer allocates memory while mixing,
  which could cause crackles under load.
- `/time add` with a negative number no longer leaves the clock negative;
  `/gamerule` rejects values that aren't numbers.
- Keys the game can't name (Home, Page Up…) can't be bound any more, which
  used to leave the action on no key.
- Resource packs with several namespaces always load from the main
  namespace first, instead of whichever one happened to come up first.
- Sparkstone torch burnout is tracked per world, and its memory is trimmed.
- Every `B.<block>` name used in code is in the generated block-id cache
  (16 newer names fell back to a string lookup), and a missing one is now
  a compile error.

## 1.4.3 — 2026-10-12 — iPhone title screen fits the screen

- **Title screen on iPhone:** the version, texture credit and "Singleplayer
  & LAN" lines sat in the rounded corners, under the Dynamic Island and the
  home indicator. They stay inside the safe area now, and on short screens
  the logo and buttons move up to make room. Touch screens get a little
  extra margin for their rounded corners. The chat input box, the
  advancements screen's Done button and the credits' skip hint stay inside
  the safe area too.

## 1.4.2 — 2026-10-12 — creative inventory tab, icon tabs

- **Your character and armor slots in creative.** The creative screen has
  an **Inventory** tab (the chest, at the far end of the bottom row): it
  shows your character, the helmet, chestplate, leggings and
  boots slots, the offhand slot and crafting, with the tabs still around it
  to go back to the items. The inventory button reopens whichever tab you
  were on.
- **Icon tabs.** Creative tabs show an item instead of a name cut to seven
  letters ("Buildin", "Functio"); the selected category's name is the
  panel title, and a mouse hover names any tab. They're finger-sized, and
  sit in columns beside the panel on a phone.

## 1.4.1 — 2026-10-12 — Mac: smaller saves, creative dig erode

- **Mac worlds save compressed**, as iOS has since the beta: chunk records
  are about 50× smaller, so world folders shrink and saving writes far less.
  Existing worlds keep loading (every build since 1.3 reads both formats);
  chunks convert as they're saved again. Builds older than 1.3 can't read
  compressed chunks, so don't open a 1.4.1 world in one.
- **Creative blocks erode on the Mac too**: holding left-click shows the
  crack growing for 0.4 s before the block breaks, so you can see where
  you're digging and stop in time. Options → Controls → Creative Dig sets
  it, down to Instant (the old behavior).

## 1.4.0 — 2026-10-12 — iPad & iPhone, headlamp, world wonders

Pebble now runs on iPad and iPhone (beta): build it with `./pebble ios`
(see the README banner). The Mac app shares all its game, render and UI
code with the iOS app now. Known rough edges on iOS: frame rate dips while
new terrain streams in, and iPhone layouts are only lightly polished.
Entries tagged with a version below landed during the iOS beta; everything
here ships to the Mac too unless it says touch, iPad or iPhone.

- **Four world wonders for `/place` (1.4.0):** `eiffel_tower` (about 150
  tall: curved lattice legs, the great arches, three platforms, a glass room
  and lit spire on top, a ladder up the middle), `stonehenge` (1:1: the
  sarsen circle and lintels with the real gaps, five trilithons opening to
  the midsummer sunrise with the great one fallen, bluestones, ditch, bank
  and Avenue), `colosseum` (125×105 and 32 tall: three arcaded stories and
  an attic, corridors, seating, the arena half floored over the hypogeum,
  the south side ruined as it is in Rome) and `devils_tower` (an 80-block
  monolith of fluted basalt columns on a talus apron with fallen columns
  and pines). `/place` also clears tree canopies left floating over a site
  when it cut their trunks.
- **Headlamp (1.4.0).** Wear it in the helmet slot and a warm beam lights
  whatever you look at, about 22 blocks out, like a real headlamp. It lights
  terrain and mobs, shows as a lamp on your forehead to other players, and
  in LAN games you see everyone's beams (up to four at once). It's light
  only: mobs still spawn in the dark. Never wears out. Craft it from
  lumenstone dust over an iron ingot with leather either side, or take one
  from the creative Tools tab.
- **Bigger touch targets on iPhone (1.3.4).** Menus need the full screen
  height, which pins an iPhone's GUI scale low (inventory slots about 5 mm
  on a Pro Max). In-world and on inventory screens nothing needs that
  height, so phones now zoom the UI up there: in-world as far as the
  hotbar and corner buttons still fit side by side (about 20% bigger on a
  Pro Max), inventory, crafting, furnace and chest screens as far as their
  panel fits (about 40% bigger slots), creative about 30% with its
  category tabs moved beside the panel. Menus keep their size; a manual
  GUI Scale turns the zoom off. iPads are unchanged. The creative screen's
  "Destroy item" hint moved under the grid (the search box covered it).
- **Untouched terrain stays put (1.3.3).** Two things changed the world
  on their own as players explored (single-player too, but worst while
  hosting guests who explore):
  - *Cave gravel and sand collapsed.* Generated springs are woken when a
    chunk loads, and their flow brushing a gravel or sand deposit over a
    cave brought the whole deposit down: over 1,000 falling blocks at once
    on one route, all simulated (and sent to guests) by the host. Fluid
    flowing in beside or above a gravity block no longer unsettles it;
    flowing in underneath still does. 81% fewer falls.
  - *Forests shed saplings.* 2-3% of generated leaves sit past the
    6-block reach to a log, and every random tick re-checked them, so
    about 100 saplings and sticks dropped around spawn every 5 minutes.
    Leaves now re-check only after something next to them
    changes: chopping a trunk still brings its canopy down, leaf by leaf.
- **Hosting a LAN game is much lighter (1.3.2).** The host has to load and
  run every guest's surroundings (it owns the world), but it was also
  building 3D meshes for them, which it never draws. It now meshes only
  what's within its own render distance. On an iPad Pro hosting two
  exploring guests: processor 91% → 49%, meshes held 8,500 → 3,000, and
  about 300 MB less memory. Guests are also held to the host's render
  distance (a Mac guest at 16 made the host load ~1,500 chunks for it
  alone); the host tells guests its distance, so they draw fog there
  instead of a hard terrain edge.
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
- **Hold to dig.** Press and hold a finger still on the
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
- **Elder Guardians no longer curse creative players** with Mining
  Fatigue.
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
    with lumenstone.
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
- **Equipped wingsuit are visible in third person.** A textured wing layer now
  follows the player and changes pose during wingsuit flight.
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
  neighbours now contribute the face light (standard smooth lighting);
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
  rotated by `-yaw` instead of the `180° - yaw` convention, so they
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
  plus the Blight and the Warden.
- **Worldgen**: multi-noise climate sampling, spline terrain, 3D density caves,
  ravines, aquifers, layered ore tables, snow lines, cave biomes
  including the deep dark.
- **Sparkstone**: wire networks, repeaters, comparators with container reading,
  pistons with quasi-connectivity, observers, hoppers, rails, hush sensors.
- **Precise player physics**, verified by independent derivations in the
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
- Wingsuit flight omits a dive-redirect term (look-pitch speed transfer).
- Armor trims show in tooltips but not yet on worn armor.
- No resource-pack or shader-pack loading — the Faithful art and the ultra
  pipeline are built in; user-supplied packs are not a feature.
