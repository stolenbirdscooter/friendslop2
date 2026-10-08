# Mossback v1.4 "First Snow": brief for whoever picks this up next

This is a standalone Godot 4.7.2 project. Open `project.godot` and press F5. Linux and Windows export presets are included; they need the 4.7.2 export templates. *(The v1.0 brief has the full file map.)*

## What Mossback is

Co-op friendslop for 1–8 players. Tiny felt **Tenders** live in a cottage on the back of a 30 m mossy wandering beast called the **Mossback**, and persuade it across a branching route:

- a sweetroot dangled from a lure pole,
- whistles,
- thrown or flung fruit,
- kalimba tunes.

Along the way: fords, gales, magpies, thistlemites, a lost calf and rope-ladder rescues. The beast picks a favourite, and the run writes its own field journal. Everything is procedural except two OFL fonts.

## Why this version exists

Reaching the last biome should *feel* like arriving somewhere. v0.8 made it snow in the air, and v1.4 lets the snow **settle on the beast and the cottage**. The journey's end becomes a visible transformation of your home, not just a different ground colour.

It also includes a quality-of-life fix found by the v1.2 reboarding bot.

## What v1.4 added on top of v1.3

- **Snow settles** (`Beast._build_snow`, `Beast.snow` 0..1):
  - about 70 flattened white drifts over the beast's mossy back (a MultiMesh on the garden points), plus a snow cap on each cottage roof slope;
  - every peer computes it locally from how much of the Wintering Hollow is under the beast (`Game`, beside the dark-lantern check), and it builds up slowly (0.02/s), so the beast whitens over about the first minute in the hollow.
- **Unwedge:** a Tender standing in NORMAL state under the belly (beast-local |x| < 7.5, |z| < 11, y < 4.5) for more than 2 s is gently shuffled out sideways, so nobody stays trapped among the walking legs.

## Testing without humans
- `--cam=snow` now shows the fully snowed beast.
- Regression: reboard (5–10 s), ladder, chaos and the earlier bots all pass.

## Known gaps
- **Flowers poke up through the snow** on the beast's back. It's quirky; you could hide the flower MultiMeshes as snow builds.
- **The hair fringe and the Tenders' hats** don't frost.

## Directions to fork toward
- **Seasons as a metagame:** spring, summer and autumn runs with their own particles and back-garden looks.
- **A thaw:** snow melting as the beast lies down to winter (an ending vignette).
