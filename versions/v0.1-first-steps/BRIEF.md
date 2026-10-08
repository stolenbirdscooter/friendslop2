# Mossback v0.1 "First Steps": brief for whoever picks this up next

This is a frozen, standalone Godot 4.7.2 project. Open `project.godot` and press F5. Nothing outside this folder is needed.

## The game in one breath

You play friendslop co-op as tiny felt "Tenders" who live in a cottage on the mossy back of a 30 m wandering beast, the **Mossback**. You can't drive it, only persuade it:

- A **lure pole** at the front of its back dangles a sweetroot before its eyes:
  - A/D swings the lure, which sets the turn rate.
  - W/S lowers it (walk) or raises it (stop).
- **Whistling** (Q) from the ground makes it turn toward you.
- **Fruit** thrown into its mouth feeds it.
- Fruit lying on the ground *distracts* it, but only when it's peckish (belly < 65).

Reach each day's **Waystone** (coloured smoke on the horizon) before sunset. There are 4 waystones and 6 days; missing sunset costs a day.

## What exists and works (verified by headless bots, not by human playtest)

**Core loop**
- Ride the beast. Take the lure; the beast walks and turns. Release the lure.
- Hop off, land, and whistle the beast over.
- Feeding gives +12 belly per plumbob and +30 per gourdle. The belly drains while walking; at 0 the beast sits down until fed.

**Chaos**
- **Pollen sneezes:** walking through flower patches builds pollen. The sneeze launches everyone on the back, so the crew tumbles, and blows fruit around.
- **Gulp-and-spit:** a Tender holding fruit at its mouth is eaten too, then spat out.
- **Pancaking:** feet flatten Tenders standing under them.
- **Throwing:** Tenders can grab and throw each other; mash Space to escape.
- **Bonks:** fruit thrown hard bonks people over.
- **Tree shoves:** the beast shoves through trees, and fruit trees drop fruit, sometimes onto its own back. Press E at a tree to shake it.

**World**
- Seeded procedural meadows, groves, lakes and boulders, streamed in 64 m chunks.
- Big boulders block the beast and confuse it into turning.
- Day/night palette cycle.

**Co-op**
- ENet host/join by IP, LAN discovery beacon, up to 8.
- Owner-authoritative Tenders, synced in beast-local space while aboard.
- Server-authoritative beast, fruit and clock.
- Late join gets a welcome snapshot.

**Presentation**
- A "printed field guide" look: toon terminator with noise breakup, a violet ambient, and a full-screen ink pass (depth + normal outlines, grain, vignette).
- Cut-paper sky.
- Paper-tag HUD: day and sun-arc clock, compass with waystone distance, belly gauge, name tags, toasts.
- A title screen with the beast wandering behind it.

**Audio**
- 28 synthesized sounds: beast steps, moans, sneeze, chomp, whistle, bell, ambience, and more.

## Architecture map

| Area | Files |
|---|---|
| Autoloads | `G` (palette, input map, fonts: `src/core/g.gd`), `Sfx` (`src/audio/sfx.gd`), `Net` (`src/net/net.gd`) |
| Flow | `src/main.gd` (menu ↔ game, dev flags) → `src/game.gd` (always at `/root/Main/Game`; all gameplay RPCs) |
| Beast | `src/beast/beast.gd` (sim + animation + snapshot replication), `beast_build.gd` (meshes, collision). The shell is an analytic superellipsoid, and `BeastBuild.back_height(x,z)` gives the exact walkable top |
| Crew | `src/player/player.gd` (states NORMAL/TUMBLE/STATION/GULPED/CARRIED), `tender_visual.gd` (procedural body, floating mitts/boots, hats) |
| World | `src/world/terrain.gd` (pure data), `world.gd` (streaming), `props_lib.gd` (procedural props), `sky_env.gd` |
| Rendering rules | `shaders/post.gdshader` reads the screen *before* transparents, so **no alpha-blended materials**. ROUGHNESS ≥ 0.5 means "draw ink lines" |

## How to test without a GPU or a human

- `godot --headless --path . -- --autostart=solo --bot=steer`. Other scenarios: `chaos` (feed / sneeze / gulp), `hop`, `release`.
- Two-process co-op: run `--autostart=host --bot=steer` in one process and `--autostart=join --ip=127.0.0.1 --bot=watch` in another.
- Screenshots under Xvfb with lavapipe: `--shot=out.png --cam=side|front|far|player --walk=1`.

## Known gaps and rough edges

- **No human playtest yet.** Tuning numbers are first guesses: speeds, drain rates, sneeze strength, day length (540 s), and how distractible the beast is.
- **No voice chat**, so proximity voice is the biggest missing friendslop ingredient. There's also no Steam lobby or NAT punch-through: internet play needs port forwarding.
- **Throwing** fruit into the mouth from the back is hard to aim. There's no arc preview.
- **Camera** can clip inside the hut. There's no first-person mode.
- **Beast animation:**
  - The tail mesh is rebuilt every 4 physics frames (cheap but crude).
  - Legs use 2-bone IK with a simple 4-beat gait.
  - The head collision doesn't match eating poses closely.
- **Art:** trees are generic puffballs, and the shell fringe reads as leaves more than fur.
- **Audio:**
  - No music.
  - The `whistle` is shared, with only its pitch varying per crew colour.
- **Night:** nothing happens at night except a skip to dawn.

## Directions this version could fork toward (ideas, not plans)

- **Caravan:** several beasts per crew, roped together, each with its own temperament.
- **Asymmetric roles:** one player *is* the beast (head-cam, sniffing, vetoing), and the rest are Tenders who must bribe it.
- **Survival-cozy:** grow food in the back garden, build onto the cottage, and spend nights defending the beast from pests.
- **Racing:** competing crews on rival beasts heading to the same waystone, sabotaging each other with thrown decoys.
- **Puzzle-pilgrimage:** fixed hand-designed routes with terrain puzzles (rivers to ford, bridges too weak, narrow passes).
