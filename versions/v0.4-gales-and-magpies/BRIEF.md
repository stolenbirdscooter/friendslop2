# Mossback v0.4 "Gales & Magpies": brief for whoever picks this up next

This is a standalone Godot 4.7.2 project. Open `project.godot` and press F5. Linux and Windows export presets are included; they need the 4.7.2 export templates.

## Identity (unchanged)

Co-op friendslop for 1–8 players. Tiny felt **Tenders** live in a cottage on the back of a 30 m mossy wandering beast called the **Mossback**. Nobody drives it. The crew persuades it with:

- a sweetroot dangled from a lure pole,
- whistles,
- thrown or flung fruit,
- kalimba tunes.

The goal is 4 waystones in 6 days. Nobody dies; failures cost time.

Everything is procedural except two OFL fonts.

## Why this version exists

Friendslop write-ups agree that the fun is the *retellable mishap*, and that the genre's weakness is a short honeymoon: a week or two until friends have "seen everything". I didn't add more systems to master. v0.4 adds **per-run variety and story-making events** that reuse the verbs the crew already has (whistle, throw, flop, sing, shake trees).

## What v0.4 added on top of v0.3

### River fords
- **Placement:** every run, one leg (leg 1 or 2, seeded) is cut by a 680 m meandering river.
  - It's carved in `Terrain.add_river` and `height()`, and `river_dist()` gives the distance to its centreline.
  - The banks are soft and the bed sits below the water plane.
- **The beast won't wade in.** It refuses deep water (`Beast._deep_ahead`, a probe 15 m ahead) unless it's **enchanted** (serenade > 0.55) or **chasing food**. Food sight range is now 30 m, so a gourdle flung or thrown to the far bank works.
  - While it balks it can still turn on the spot, so the steerer can walk it along the bank instead.
- **Replication:** `balk` rides in the beast snapshot (22 floats now). The HUD mood reads "won't wade in deep water", and a coach hint explains it.
- **Lakes too:** this also applies to deep meres, which are now real obstacles to steer around.

### Gale days
- **Weather roll:** `roll_weather()` gives mist 30% / gale 25% / clear, from day 2.
- **Gusts:** the server sends `_gust(dir)` every 16–28 s, mostly from the beast's side.
  - Everyone gets 2 s of warning: rustle and whistle sounds, inked wind lines across the HUD, and "Gust coming! hold R".
  - Then the gust hits (`Player.on_gust`). You're fine if you're **flopping (hold R)**, at a station, inside the cottage, or carrying something heavy or a friend. Otherwise you're knocked tumbling.
- **Props:** loose props on the back get shoved. Thistlemites get blown off, which is the gale's one kindness.
- **Ambience:** the wind is louder all day.

### Magpies
- **Arrival (`src/props/magpie.gd`):**
  - From leg 2 (or day 2), 1–2 birds arrive every 70–130 s, with a cap of 2.
  - The server flies them: ARRIVE (circle) → SWOOP → ESCAPE → PERCH, or FLEE.
  - Clients lerp them from `Game._magpie_states` at 10 Hz.
- **Targets (weighted):** a Tender's **hat** (hidden while stolen, and drawn in the beak via `TenderVisual.hat_for`), loose **keepsakes**, and fruit on the back.
- **Where loot goes:** to a nest on a nearby tree. A twig nest appears there with a "nest" compass marker. With no trees anywhere, it nests in the grass.
- **Getting things back:**
  - **Whistle** within 16 m, or **bonk it** with a fast prop (thrown, or from the flinger), while it's still in the air. It drops its loot (hats pop straight back).
  - Or go out and **shake the nest tree** (E). Even the beast shoving through that tree works.
- **Holding convention:** carried props use `held_by = -magpie_id`, and nested props use `held_by = NEST_HOLD (-9999)`. Grab, eat and shelve logic all skip anything negative.
- **Late joiners:** stolen hats and nests are in the run state.

## Testing without humans
- New bots:
  - `--bot=ford`: balks at the river, then crosses it with a tune.
  - `--bot=magpie`: a prop theft goes to the nest and comes back on a shake; a hat theft is undone by a whistle.
  - `--bot=gale`: a gust knocks you down, and flopping holds you.
- Dev views:
  - `--cam=river`
  - `look_test.tscn -- --props=1` (now includes a magpie carrying a hat, and a nest).
- All older bots still pass: steer, chaos, pests, fling, keepsake, serenade.

## Known gaps
- **Untested with real humans and real audio.** Gust force, magpie frequency and river width are guesses.
- **Magpie sound:** the chatter is the existing "chirp" SFX pitched down. A dedicated magpie rattle would be better.
- **Nest height:** the nest sits at an estimated canopy height (6.4 × tree scale, or 8.2 × for spire pines), so it can float or sink a little.
- **No ford for Tenders:** on foot, you swim slowly.
- **Hat swaps while robbed:** if you swap hats in the cottage while one is stolen, the new hat stays hidden until the theft resolves.

## Directions to fork toward
- **Events deck:** more set pieces using existing verbs. Ideas: a bramble gate Tenders must clear on foot, a lost Mosslet calf that follows a serenade, a rickety rope bridge for Tenders.
- **Branching routes:** at waystones, choose between two smokes, for example the gale ridge or the magpie woods.
- **A rival crew** on a second beast that magpies also raid.
- **Hat economy:** magpie nests could also hold *other* crews' lost hats (bonus unlocks).
