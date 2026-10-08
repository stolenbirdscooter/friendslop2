# Mossback v0.8 "Weathering": brief for whoever picks this up next

This is a standalone Godot 4.7.2 project. Open `project.godot` and press F5. Linux and Windows export presets are included; they need the 4.7.2 export templates.

## Identity (unchanged)

Co-op friendslop for 1–8 players. Tiny felt **Tenders** live in a cottage on the back of a 30 m mossy wandering beast called the **Mossback**. Nobody drives it. The crew persuades it with:

- a sweetroot dangled from a lure pole,
- whistles,
- thrown or flung fruit,
- kalimba tunes.

The route is a branching tree of waystones, past fords, gales and magpies. The beast picks a favourite, and the run writes its own field journal. Nobody dies; failures cost time.

Everything is procedural except two OFL fonts.

## Why this version exists

The "printed field guide" look was strong in stills but the air was empty, and the five biomes differed mostly in ground colour. v0.8 makes each place *feel* different while you're moving through it, and gives the last leg an emotional payoff: it snows in the Wintering Hollow. It also flattens frame-time spikes.

## What v0.8 added on top of v0.7

### Ambient weather (`src/fx/ambient.gd`, class `Ambient`)
Five GPU particle emitters follow the camera. Each blends in via `amount_ratio`, from the biome under the camera and the time of day:

| Effect | Where and when |
|---|---|
| Pollen motes | Clover Meadows, a little in Mere Country; fades at dusk and in mist |
| Seed fluff | Gold Steppe |
| Leaf flurries | Ember Woods. Each particle is four differently coloured leaves, so there's colour variety without particle colour ramps |
| Cut-paper snowflakes | Wintering Hollow. Six flat arms with barbs, spinning. Up close they read as paper cut-outs, not polygon balls |
| Fireflies | Dusk and night anywhere except the snow. They wander with turbulence and blink via the scale curve |

- **Material rule:** motes use a bright, *un-inked* toon material (`_mote_mat`: `outline_tag` 0 plus emission). With ink outlines, tiny particles render as dark specks.
- **Wind:** on gale days and during gusts, the emitters' gravity is pushed downwind.

### Gusts bend the world
- **Uniform:** a new global shader uniform `gale` (vec3), declared in `project.godot` `[shader_globals]`.
- **Shaders:** `toon.gdshader` (foliage materials only, i.e. `wind > 0`) and `grass.gdshader` add it in local space, so trees and grass lean downwind during gusts.
- **Driver:** `Ambient` sets it every frame and zeroes it on exit.

### Frame-time smoothing
- **Tail:** it no longer re-merges (and re-indexes) the noise-blob tuft every 4 physics frames. The tuft is a separate cached mesh riding the tip.
- **Chunks:** world chunks build one per frame instead of two.
- **Measured headless:** physics frame-time spikes during chunk streaming dropped from about 15 ms to under 6 ms. Steady script cost is about 0.75 ms (beast) plus 0.35 ms (game logic) per physics frame. Most of the remaining physics time is Jolt stepping the moving kinematic shell.

### Verified
- **Export:** an exported Linux build of the v0.7 snapshot boots and builds a world with no script errors, so the snapshots really are independently buildable.

## Testing without humans
- Look-dev cameras: `--cam=snow|leaves|dusk` (they jump to the right ring of the route).
- `--bot=perf`: walks with the lure and prints fps plus process and physics milliseconds.
- All earlier bots still apply.

## Known gaps
- **Particle look on real GPUs:** only checked under software Vulkan (lavapipe). Particle counts (up to about 1,100 flakes) are untested on low-end hardware.
- **Snowy ground:** the Wintering Hollow ground has no snow cover yet, and neither does the moss on the beast's back. Only the air snows.
- **Weather variety:** there's still no rain.

## Directions to fork toward
- **Seasonal ground:** snow settling on the beast's back garden and cottage roof in the last biome, and frost on the Tenders' hats.
- **Rain days:** puddles that reflect (opaque!), with drips off the cottage eaves.
- **Biome soundscapes** to match: wind over the steppe, crackling leaves, muffled snow.
