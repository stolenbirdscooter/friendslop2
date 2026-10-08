# Mossback

*A co-op game about walking a very large friend.* Built with **Godot 4.7.2** (GDScript, Jolt physics, Forward+).

You and your friends are Tenders: tiny felt caretakers living in a cottage on the back of an enormous, gentle, easily distracted beast. You can't drive it. You can dangle a sweetroot in front of its face, whistle at it, feed it, and hope it doesn't sneeze. Get it to each day's waystone before sunset.

Every asset is procedural: meshes from math, sound from synthesis. The only exceptions are two human-designed open fonts (Fraunces and Atkinson Hyperlegible, SIL OFL).

## Repository layout

| Path | What |
|---|---|
| `game/` | The current, in-development project. Open `game/project.godot` in Godot 4.7.2. |
| `versions/` | Frozen, independently buildable snapshots in chronological order. Each is a complete Godot project with its own `BRIEF.md`. |
| `DESIGN.md` | Living design doc for `game/`. |
| `tools/` | `snapshot.sh` (freeze a version), `shot.sh` (headless screenshot), `check.sh` (headless boot + error scan). |

## Playing

- **Open and run:** open the project in Godot 4.7.2 and press F5.
- **Build:** use *Project → Export*. Linux and Windows presets are included, and the export templates for 4.7.2 must be installed.
- **Multiplayer:**
  - One player chooses **Host a crew**. Others enter the host's address and press **Join**.
  - LAN games show up automatically.
  - Over the internet, forward UDP port 24680 on the host.

**Controls**

| Input | Action |
|---|---|
| WASD | walk |
| Space | hop |
| Shift | dash |
| E | use (take the lure, shake a tree) |
| Left mouse | pick up / drop |
| Right mouse (hold) | throw |
| Q | whistle (also shoos magpies) |
| F | wave |
| R (hold) | flop like a sack |
| 1 – 8 | play your kalimba (the Mossback loves a tune) |
| P | save a framed postcard of the view (to `user://postcards/`) |
| G / middle mouse | ping what you're looking at |
| T | push-to-talk (optional; open mic by default) |
| Esc | menu |

On a gamepad: left stick moves, right stick looks, A hops, X uses, Y whistles, B flops, RT/RB grab, LT/LB throw, the D-pad plays four kalimba notes, Back takes a postcard.

While on the lure: A/D swings it left/right and W/S lowers/raises the sweetroot.
At the flinger: mouse or A/D aims, hold LMB to wind it up, release to fling whatever is in the bowl (including friends).
Inside the cottage: E tries on another hat.

## Versions

| Version | Name | Highlights |
|---|---|---|
| [v0.1](versions/v0.1-first-steps) | First Steps | The beast walks. Lure steering, feeding, sneezes, gulps, waystones over 6 days, ENet co-op, ink-and-paper look, synthesized audio. |
| [v0.2](versions/v0.2-chatter-and-critters) | Chatter & Critters | Proximity voice chat with talking mouths. Thistlemites and the wet-dog shake. Five biomes along the route. Beast names and temperaments. Misty days with a spyglass lookout on the cottage roof. Generative folk music. Flop, throw arcs, puff FX, coach hints. |
| [v0.3](versions/v0.3-songs-and-slingshots) | Songs & Slingshots | The flinger: a spoon catapult on the beast's back for fruit, mites and friends. Keepsakes off the path unlock hats that persist between runs. Kalimba serenades that enchant the beast. Waystone arrival spectacle. Fixed a mesh-merge bug that had been hiding flowers, pines and tree fruit since v0.1. |
| [v0.4](versions/v0.4-gales-and-magpies) | Gales & Magpies | River fords the beast won't wade without a tune or a snack. Gale days with telegraphed gusts (hold R to flop flat). Magpies that steal hats, keepsakes and fruit and nest them in trees: whistle, bonk them, or shake the nest tree. |
| [v0.5](versions/v0.5-the-field-journal) | The Field Journal | The run writes its own journal (who got eaten, who sang it across the river, who the magpies robbed), shown as an end-of-run spread with per-player commendations. P saves framed postcards. New synthesized sounds for magpies, gusts, the flinger, splashes and hats. |
| [v0.6](versions/v0.6-crossroads) | Crossroads | The route branches: past the first waystone every leg offers two smokes with different roads (Windward Ridge, Magpie Woods, Thistle Moor, Long Meadow). Steer for the one you want. Radial biomes and arc rivers that work on every branch. Volume sliders. |
| [v0.7](versions/v0.7-the-favourite) | The Favourite | The beast picks a favourite Tender from who treats it kindly. It watches them, comes when they whistle (even against the lure) and nuzzle-boops them onto its back. Rosette and "Teacher's Pet" commendation. Full gamepad movement. |
| [v0.8](versions/v0.8-weathering) | Weathering | You can see each biome's weather: pollen, seed fluff, leaf flurries, cut-paper snow in the Wintering Hollow, and fireflies at dusk. Gusts bend trees and grass. Smoother frame times. Snapshot export verified. |
| [v0.9](versions/v0.9-calls-and-calves) | Calls & Calves | Context pings (G / middle mouse): point at fruit, keepsakes, magpies, trees or ground for the whole crew. A lost Mosslet calf bleats off one leg's path; coax it home with a tune or whistle and it trots alongside for good. |
| [v1.0](versions/v1.0-homecoming) | Homecoming | The title screen shows your Tender, dressed as you chose, and your almanac: migrations walked, best finish, keepsakes, favourites, calves, and the funniest line from your last run. |
| [v1.1](versions/v1.1-field-trials) | Field Trials | An autopilot crew played whole migrations, which exposed two core bugs present since v0.1. The beast couldn't eat food on the ground, and a starving beast could never be fed again. Both are fixed, along with rocks being mistaken for trees and a cap on fruit pile-ups. Tuned from the data: half the itch rate, 7.5-minute days. Settings on the title screen. |
| [v1.2](versions/v1.2-back-aboard) | Back Aboard | The tail is now a smooth ramp that runs into the grass, so falling off is no longer a long detour; reboarding a walking beast takes 5–11 s. Fuzz crews (solo and co-op) hammered the game for 15 minutes each with zero errors. |
| [v1.3](versions/v1.3-rope-and-rescue) | Rope & Rescue | Rope ladders on both flanks: someone aboard lowers one (E at the post) so a stranded friend can climb back up, and the journal remembers who saved whom. Fixed gaps in the spyglass eyepiece mask. |
| [v1.4](versions/v1.4-first-snow) | First Snow | In the Wintering Hollow, snow settles on the beast's back and the cottage roof. Tenders stuck under the belly get shuffled out. |
| [v1.5](versions/v1.5-wintering) | Wintering | A proper ending: the beast lies down, tucks its head in and sleeps under the snow while every camera drifts out for a last look, then the journal page arrives. |
| [v1.6](versions/v1.6-bramble-gate) | Bramble Gate | The last leg is barred by a bramble hedge the beast won't push through. Hop off, hack a beast-wide gap and scramble back aboard as it squeezes past. Fewer thistlemites. |
