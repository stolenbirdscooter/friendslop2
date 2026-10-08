# Mossback v0.6 "Crossroads": brief for whoever picks this up next

This is a standalone Godot 4.7.2 project. Open `project.godot` and press F5. Linux and Windows export presets are included; they need the 4.7.2 export templates.

## Identity (unchanged)

Co-op friendslop for 1–8 players. Tiny felt **Tenders** live in a cottage on the back of a 30 m mossy wandering beast called the **Mossback**. Nobody drives it. The crew persuades it with:

- a sweetroot dangled from a lure pole,
- whistles,
- thrown or flung fruit,
- kalimba tunes.

The run is 4 waystones in 6 days, past river fords, gales and thieving magpies. The run writes its own field journal. Nobody dies; failures cost time.

Everything is procedural except two OFL fonts.

## Why this version exists

Groups argue happily over choices that matter, and a route the crew *chooses* makes every run different. v0.6 turns the route into a tree. No vote UI was added: **you choose a road by steering toward its smoke.**

## What v0.6 added on top of v0.5

### Branching roads
- **The tree:** `Game._plan_route` builds a deterministic 15-node waystone tree from the seed (1 + 2 + 4 + 8).
  - Every node is flattened up front, so terrain never changes mid-run.
  - Past the first waystone, each leg forks into two candidates about ±0.4–0.6 rad apart. Each candidate has a **road character** (`Game.TRAITS`) and its own smoke colour (`TRAIT_SMOKE`).
- **The four roads:**

  | Road | Effects |
  |---|---|
  | Windward Ridge (sky smoke) | Gusts all along it whatever the weather; mites ×0.4 |
  | Magpie Woods (rose smoke) | Magpies twice as often, up to 3 at once; an extra keepsake |
  | Thistle Moor (violet smoke) | 0.8× length; mites ×2.2 |
  | Long Meadow (mint smoke) | 1.18× length; no magpies; mites ×0.5 |

- **Choosing:** whichever candidate the beast reaches first becomes the path. `_reached(id)` is broadcast, and `path` is in the run state for late joiners. The journal notes "Came by way of …".
- **Which road you're on:** `active_trait()` picks the road by the beast's bearing from the last waystone. The HUD shows "on the Windward Ridge" under the day tag, and the server applies that road's effects.
- **HUD and messages:**
  - The compass shows both smokes, labelled with road name and distance.
  - At dawn on a fork leg, a toast reads "The road forks. Left: … Right: …". Left and right are relative to the two directions, not the beast's facing.
  - The spyglass accepts either smoke.
- **Keepsakes:** one per branch (two on Magpie Woods), along each candidate road.

### Biomes and rivers that work with branches
- **Biomes are now radial bands** around the start (`Terrain.set_radial`). Band edges are each level's average waystone distance, and the last edge is pulled in so every final waystone stands in the Wintering Hollow. Chunk generation never depends on which road is taken.
- **The river is now an arc** around the start (`Terrain.add_river_arc`, `river_dist`, `river_radius`). It crosses every branch of its ring, and a height sample costs one `atan2`. The old polyline version would have been far too slow at this length.

### Volume
- The pause menu has sliders for Everything, Music, Sounds (SFX, ambience and UI) and Voices. They're saved in `user://mossback.cfg` (`G.volumes`, `G.apply_volumes`).

## Testing without humans
- `--bot=fork --leg=1` (or `--leg=2`): lists the options and traits plus the biome at every node, checks the mid-leg road detection, arrives at the second option, and checks the path and the next options.
- All earlier bots: steer, chaos, pests, fling, keepsake, serenade, ford, magpie, gale, journal, postcard.

## Known gaps
- **Untested with humans.** Trait strengths are guesses.
- **Detours and backtracking:** you can switch roads mid-leg (the road follows your bearing), and nothing stops you reaching the "other" smoke after detouring. That's intentional freedom, but untested.
- **Biome bands are radial:** a very short branch can reach a waystone just before its biome changes.
- **Weather:** traits don't change the per-day weather roll (mist can still happen anywhere). Only Windward adds gusts.

## Directions to fork toward
- **Show the tree:** a map or field-journal sketch of roads taken and not taken.
- **Signposts at waystones:** hand-painted boards naming the two roads.
- **More road characters:** a Bramble Pass (Tenders must clear a hedge on foot), the Fen (fog plus fireflies at dusk), or a Ferry Crossing.
