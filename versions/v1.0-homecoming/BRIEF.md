# Mossback v1.0 "Homecoming": brief for whoever picks this up next

This is a standalone Godot 4.7.2 project. Open `project.godot` and press F5. Linux and Windows export presets are included; they need the 4.7.2 export templates. An exported Linux build of v0.7 was verified to boot.

## What Mossback is (all versions so far)

Co-op friendslop for 1–8 players (ENet host/join, LAN discovery, proximity voice). Tiny felt **Tenders** live in a cottage on the back of a 30 m mossy wandering beast called the **Mossback**. Nobody drives it. The crew persuades it with:

- a sweetroot dangled from a lure pole,
- whistles,
- thrown or flung fruit,
- kalimba tunes.

The route is a branching tree of waystones (choose a road by steering toward its smoke), with 4 waystones in 6 days. Along the way:

- river fords it won't wade without coaxing,
- gale days,
- magpies that steal hats and keepsakes,
- thistlemites and sneezes,
- a lost calf to bring home,
- per-biome weather.

The beast picks a favourite. The run writes its own field journal and hands out commendations at the end. Nobody dies; failures cost time.

**Look:** "printed field guide". Toon light, an ink-outline post pass, cut-paper sky.

**Built from code:** meshes from math, synthesized SFX and music. The only exceptions are two OFL fonts.

## Why this version exists

v1.0 is about the *frame* around the game: what you see when you open it and what it remembers about you. The title screen now shows **your** Tender and **your** history with the game, which gives players a reason to come back.

## What v1.0 added on top of v0.9

- **Live Tender preview on the title screen.**
  - A `TenderVisual` parented to the menu camera stands beside the card.
  - It rebuilds immediately when you change colour or hat (with the hat-pop sound), sways a little and waves every 5–9 s.
- **The almanac** (`G.almanac`, saved in `user://mossback.cfg`).
  - **What it records:** migrations finished, how many reached the hollow (and the best day count), keepsakes you brought home, beasts that made you their favourite, and calves you led home.
  - **Last line:** the most memorable journal line of your last run, chosen by favouring lines that name you or mention being eaten, flung, magpies, sneezes and so on, plus the beast's name.
  - **When it's written:** every peer writes its own entry when a run ends (`Game._record_almanac` from `_awards`).
  - **Where it shows:** under the title, for example *"1 migration walked · 1 reached the hollow (best: 2 days)…"* and *"Last time, with Captain Parsnip: 'Burdock got eaten along with their snack…'"*.
- **Help line:** the menu help line now lists G for pings.

## Where things live (quick map)
- **Core:**
  - `src/core/g.gd`: palette, input, prefs, almanac, volumes
  - `geo.gd`, `mats.gd`: procedural meshes and materials
- **Game logic:** `src/game.gd`, the big one. Server-authoritative run logic:
  - route tree, keepsakes, magpies, calf,
  - journal, tallies, favourite,
  - gusts, pings, the flinger.
- **The beast:** `src/beast/beast.gd`. Simulation, animation, flinger body, serenade, affection, deep-water refusal.
- **Players:** `src/player/player.gd` and `tender_visual.gd`.
- **Props:** `src/props/`: fruit and keepsakes, `magpie.gd`, `mosslet.gd`.
- **World:**
  - `src/world/terrain.gd`: radial biomes, arc river, flatten
  - `world.gd`: chunk streaming
  - `props_lib.gd`: meshes
- **Effects and audio:** `src/fx/fx.gd` (puffs) and `ambient.gd` (weather). `src/audio/` holds the synthesized SFX and the generative music.
- **Net:** `src/net/` has `net.gd` (session) and `voice.gd`.
- **UI:** `src/ui/hud.gd`, `menu.gd`, `ui.gd`.
- **Dev:** `src/dev/bot.gd` drives headless scenarios, and `look_test.gd` is a prop line-up.

## Testing without humans
- **Bots:** `-- --autostart=solo --seed=42 --bot=X`, where X is any of: steer, hop, chaos, release, pests, spy, fling, keepsake, serenade, ford, magpie, gale, fork (add `--leg=1`), favourite, calf, ping, journal, postcard, perf.
- **Co-op:** `--autostart=host` with a second process running `--autostart=join --ip=127.0.0.1 --bot=watch`.
- **Screenshots:** `tools/shot.sh game res://scenes/main.tscn out.png --autostart=solo --cam=side|front|far|player|flinger|hut|river|snow|leaves|dusk|calf`.

## Known gaps (honest)
- **Never played by real humans, with real microphones, or on real GPUs.** Every tuning number is a reasoned guess, verified only by scripted bots and software-rendered screenshots.
- **Internet play** needs port forwarding. There's no relay or Steam lobby.
- **Settings** are only in the pause menu (volume, sensitivity, push-to-talk).

## Directions to fork toward
- **A real playtest pass**, then tuning: hunger, itch, fling power, magpie rate, serenade gain.
- **Steam / relay networking** with lobby codes.
- **Seasonal metagame:** runs in spring, summer and autumn with different biome palettes, and the same beast across seasons.
- **Build out the cottage interior:** decorate with keepsakes and pin postcards on the wall.
