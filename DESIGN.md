# Mossback: living design document

*A co-op game about walking a very large friend.*

This file describes the **current** design (`game/`). Each frozen version in `versions/` has its own `BRIEF.md`.

## The pitch

You and up to seven friends are **Tenders**: tiny felt caretakers who live in a cottage on the mossy back of a **Mossback**, a gentle, dim, enormous wandering beast. You can't drive it. You can only *persuade* it:

- dangle a sweetroot in front of its face from a long pole (the **lure**),
- whistle at it from the ground,
- toss fruit into its mouth (or onto the grass ahead of it),
- and hope it doesn't sneeze.

Each day you have to coax it to the next **Waystone** before sunset, following coloured signal smoke on the horizon. You get four waystones and six days.

## Why it's fun (design pillars)

1. **A shared home that moves.** R.E.P.O.'s developer said the game only worked once something kept players together. Here the beast does that job. Everyone lives on one moving platform, so there's no lonely wandering. But hopping off to forage is always a gamble, because it keeps walking.
2. **Persuasion, not control.** The beast has wants: hunger, distraction, pollen. Steering is a negotiation, and failures are the beast's fault, so they're funny rather than frustrating.
3. **Physics slapstick with soft consequences.**
   - Sneezes launch the crew.
   - Feet pancake the careless.
   - Holding a snack near the mouth gets you eaten, then spat out.
   - Friends can be picked up and thrown.
   - Nobody dies. You lose *time*, and the run fails only when the season runs out.
4. **Roles appear on their own, without being assigned.** Typical jobs that come up:
   - one person steers,
   - one forages,
   - one feeds,
   - one shouts directions from the cottage roof,
   - one is being thrown off the beast.
5. **Clip-worthy scale.** Seeing a cottage-topped hill wander through a meadow is a screenshot by itself.

## What it deliberately is *not*

- No monsters, horror, or dark facilities (Lethal Company / R.E.P.O. / Content Warning).
- No quota of loot to extract, and no camera-for-views.
- No climbing-a-mountain survival (PEAK).
- No AI-generated art or audio. Everything is built from code:
  - meshes come from math,
  - sounds are synthesized,
  - fonts are human-designed OFL faces (Fraunces, Atkinson Hyperlegible).

## Look: "printed field guide"

- A two-tone toon light with a painterly, noise-broken terminator.
- Shadows take a cool violet from the ambient light.
- A full-screen ink pass draws outlines from depth and normals, with grain, a warm/cool grade and a vignette.
  - **ROUGHNESS is an ink tag:** materials at ≥0.5 get outlines, and grass sits at 0.
  - The ink pass reads the screen *before* transparent objects. Avoid alpha-blended materials: use opaque or alpha-scissor instead.
- A banded sky with cut-paper clouds.
- Palette: everything visible comes from `src/core/g.gd`.

## Architecture (Godot 4.7.2, GDScript, Jolt)

| Area | Where | Notes |
|---|---|---|
| Globals, palette, input map | `src/core/g.gd` (autoload `G`) | Input actions are created in code |
| Procedural meshes | `src/core/geo.gd`, `src/world/props_lib.gd`, `src/beast/beast_build.gd` | lathe, blob, tube, merge |
| Terrain data | `src/world/terrain.gd` | Seeded noise. Gives height, colour, and scatter records. Pure data, so the server can use it |
| World streaming | `src/world/world.gd` | 64 m chunks with LOD and skirts, MultiMesh scatter, collision only near anything that needs it |
| Sky / day cycle | `src/world/sky_env.gd` | Palette keyframes over time of day |
| Beast | `src/beast/beast.gd` | Server simulates behaviour. Every peer animates its own legs, head and lure from the interpolated state. The body is an `AnimatableBody3D` the crew stands on |
| Crew | `src/player/player.gd`, `tender_visual.gd` | Owner-authoritative movement. Syncs in beast-local space while aboard |
| Session | `src/net/net.gd` (autoload `Net`) | ENet host/join, roster, LAN beacon on UDP 24681 |
| Run logic | `src/game.gd` | Server-authoritative fruit, beast, clock and waystones. Lives at `/root/Main/Game` everywhere so RPC paths match |
| Audio | `src/audio/sfx.gd` (autoload `Sfx`) | Everything synthesized at startup (about 0.5 s) |
| UI | `src/ui/*.gd` | Paper-tag HUD drawn in `_draw` |

## Dev tools

- `tools/check.sh game -- --autostart=solo`: headless boot plus script errors.
- `tools/shot.sh game res://scenes/main.tscn out.png --autostart=solo --cam=side --walk=1`: a software-rendered screenshot.
- Bots: `godot --headless --path game -- --autostart=solo --bot=steer|chaos|hop|release` and `--autostart=join --bot=watch`.
- `tools/snapshot.sh vX.Y-slug "Label"`: freezes `game/` into `versions/`.
