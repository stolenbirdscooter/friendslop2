# Mossback v0.3 "Songs & Slingshots": brief for whoever picks this up next

This is a standalone Godot 4.7.2 project. Open `project.godot` and press F5. Linux and Windows export presets are included; they need the 4.7.2 export templates.

## Identity (unchanged)

Co-op friendslop for 1–8 players. Tiny felt **Tenders** live in a cottage on the back of a 30 m mossy wandering beast called the **Mossback**. Nobody drives it. The crew persuades it with:

- a sweetroot dangled from a lure pole,
- whistles,
- thrown fruit,
- and now, music.

The goal is 4 waystones in 6 days. Nobody dies; failures cost time.

Everything is procedural (meshes from math, synthesized audio) except two OFL fonts.

## What v0.3 added on top of v0.2

### The flinger
A torsion-spoon catapult on the cottage's **left flank** (`BeastBuild.FLINGER`, beast-local x=-5, z=4).
- **Physics:** it has its own `AnimatableBody3D` (`Beast.fl_body`), so the turntable can turn without rebuilding the shell's compound collision. The bowl sits on the yaw axis.
- **Crewing it:** press E at the stand behind the bowl. Mouse or A/D aims, hold LMB to wind, release to fling, E to leave.
- **Aim arc:** ±120° around "out to the left" (`FL_AIM_CENTER`, `clamp_fl_yaw`). It never points over the roof, which is why it lives on the flank.
  - Earlier placements behind the hut put the release point *under the roof overhang*, and every shot hit the roof.
- **Firing (server):** `_request_fling` teleports every prop in the bowl to the release point with `flinger_velocity(power)`. That includes fruit, thistlemites and keepsakes.
- **Players in the bowl:** each client checks its own Tender in `_flinger_fired` and launches itself with velocity × 1.355 (`PLAYER_FLING` = √(18/9.8)), so a Tender lands where a plumbob would.
- **HUD:** the operator sees a dotted arc preview, an X landing mark with the distance, and a wind-up gauge.
- **Why it matters:** fling fruit *far ahead* and the beast walks to it, which is a new long-range way to steer. Fling friends off to forage, and fling mites overboard.

### Keepsakes and hats
- **Spawning:** six trinkets (teacup, acorn, paper crown, heron feather, snail shell, lampshade; `PropsLib.KEEPSAKES`). Two scatter per leg, 35–90 m off the route line (`Game._spawn_keepsakes`). Kinds the host hasn't unlocked yet come first.
- **Finding them:** a pulsing inked star plus butter puffs, and diamond markers in the spyglass view (the lookout's second job).
- **Bringing them home:** carry or throw one into the cottage (`Beast.in_hut`). It goes on the shelf inside, for everyone, and it's part of the run state for late joiners.
  - The hat unlocks for **every peer**, saved in `user://mossback.cfg` (see `G.load_prefs`/`save_prefs`, `G.unlocked_hats`).
  - Press E inside the cottage to cycle hats live (`Net.update_my_look`).
- **Physics:** keepsakes use a cylinder collider so they don't roll into meres. They stay frozen until the ground under them has collision (`World.has_collision_at`).
- **The beast won't eat them:** it spits them back out.

### Kalimba serenades
- **Playing:** keys 1–8 play a handheld kalimba.
  - `Music.player_scale()` gives 8 notes in the score's *current* key, so anything sounds right.
  - `Music.play_positional_note()` plays it in 3D on the SFX bus.
  - Notes arrive by RPC (`Game._note`), with crew-coloured puffs, a held kalimba prop and pose, and a HUD thumb-piano strip.
- **Effect on the beast:** notes within 20 m of its head raise `Beast.serenade` (0..1).
  - Mashing gives ×0.3, and repeating a note gives ×0.5.
  - Several players playing at once multiply it (+60% per extra player in a 3 s window). It decays at 0.05/s.
- **Above 0.55, "enchanted":**
  - It trots on the lure even when it hasn't been fed recently.
  - Hunger drain and itch gain are halved.
  - Joy rises, and it wakes from naps.
  - It hums, sways its head, half-closes its eyes and wags its tail.
- **HUD:** the belly tag has a "Tune" stave whose notes fill in.

### Waystone arrival spectacle
- A ring of coloured smoke bursts from the turf and the smoke column blooms.
- The stone glows, and a light swells.
- The beast rears its head and bellows (`Beast.celebrate`).

### Fixes
- **`Geo.merge` was silently dropping geometry** whenever it mixed Godot primitive meshes (indexed) with SurfaceTool-built ones (non-indexed). Every v0.1 and v0.2 build was missing:
  - the flower clusters on the beast's back,
  - the spire pines,
  - the fruit on trees,
  - parts of several props.

  Merge now indexes non-indexed parts first. Expect the world to look noticeably richer than earlier versions.
- The cottage now has gable walls, with the round window in the back gable. The lantern hangs from the ridge and glows faintly by day.
- Net: updating your look no longer reshuffles your crew colour.
- Coach hints that depend on time no longer starve each other.
- Tumble drag grows with speed.

## Testing without humans
- Bots: `-- --autostart=solo --seed=42 --bot=fling|keepsake|serenade` (plus the older steer, hop, chaos, release, pests and spy).
- Dev cameras: `--cam=flinger` (with fruit in the bowl) and `--cam=hut` (shelf filled with every keepsake).
- Verified headless:
  - A fruit is flung about 39 m.
  - A Tender launched from the bowl travels about 72 m, including the skid.
  - A keepsake 300 m away is collected, shelved and unlocks its hat, and swapping hats updates the visual.
  - One player serenading reaches enchanted in about 6 s of melody.

## Known gaps
- **Untested with real humans and real audio.** The tuning numbers are guesses:
  - fling power 10–27 m/s,
  - serenade gains,
  - keepsake distances.
- **Clients:** the flinger yaw is interpolated 120 ms behind, so a client may launch a hair off the server's aim.
- **Far keepsakes:** these only get collision within the host's view radius (7 chunks ≈ 450 m).
- **Kalimba keys:** each peer hears notes in *their own* composer's key, which may differ between peers that joined at different times. This is harmless, but not a shared key.
- **Hats:** the hat unlock is per machine. A hat earned as a client unlocks only on clients present at the time.

## Directions to fork toward
- **Rhythm:** make serenades rhythmic. The beast could have a gait-locked beat, and on-beat notes count double. Let jams harmonize across peers with a host-authoritative key.
- **Flinger trick shots:** targets, hoops on waystones, "message in a gourdle" delivery.
- **Keepsakes as decor:** put a cottage interior to decorate between runs.
- **Branching routes:** choose the next biome at each waystone.
- **A rival crew** on a second beast.
