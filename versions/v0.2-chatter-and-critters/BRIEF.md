# Mossback v0.2 "Chatter & Critters": brief for whoever picks this up next

This is a standalone Godot 4.7.2 project. Open `project.godot` and press F5. It builds with the included Linux/Windows export presets once 4.7.2 export templates are installed.

## Identity (unchanged from v0.1)

Co-op friendslop. Tiny felt **Tenders** ride a 30 m mossy wandering beast (the **Mossback**) with a cottage on its back. You steer it by *persuasion*:

- a sweetroot dangled from a lure pole,
- whistles,
- thrown fruit.

Reach 4 waystones in 6 days. Nobody dies; you lose time.

## What v0.2 added on top of v0.1

- **Proximity voice chat** (`src/net/voice.gd`, autoload `Voice`).
  - Pipeline: mic → 16 kHz → μ-law → unreliable RPC to all → per-speaker AudioStreamGenerator on each Tender, with distance falloff and muffling.
  - Voice-activity detection, optional push-to-talk on T, and mute in the pause menu.
  - Tenders' mouths flap with `Voice.level(peer)`, and name tags show sound arcs while someone speaks.
  - Verified headless with three processes. **Never tested with a real microphone.**
- **Thistlemites and the wet-dog shake.**
  - Purple thistle patches put hitchhiking pests on the beast. Mites are props (`Fruit` with `pest=true`) that crawl over the shell and raise **itch**.
  - At 100 itch the beast shakes and flings the crew sideways. Whoever holds the lure pole hangs on.
  - Remove mites by grabbing and throwing them overboard, sprint-punting them, or letting a sneeze or shake fling them.
  - Feeding a mite to the beast makes it sneeze.
- **Biomes along the route** (`Terrain.BIOMES`, `set_route`).
  - Clover Meadows → Gold Steppe → Mere Country → Ember Woods → Wintering Hollow.
  - Each biome sets ground colours, tree species mix, canopy palette (autumn reds, snow-capped spires), flower/thistle density and how many lakes there are. A title card appears when you cross into a new one.
- **Beast personality.** Seeded name ("Big Mumble"), coat colour, and a temperament that multiplies behaviour: Sneezy, Greedy, Ticklish, Dozy (naps), Stubborn (slow turns), Nosy.
- **Misty days and the lookout.**
  - From day 2, a 40% chance per day of mist: thick fog, and the waystone marker is hidden from the compass.
  - A gangplank on the cottage's side leads to the roof. The spyglass on the ridge gives a zoomed eyepiece view.
  - Holding the smoke in the glass for one second "spots" it, and the marker shows for everyone for 50 s.
- **Generative folk music** (`src/audio/music.gd`, autoload `Music`): moods are dawn, travel, tense, night and arrived, plus stingers.
- **Juice.**
  - Inked cartoon puffs (`src/fx/fx.gd`) for footfalls, splashes, sneeze pollen, leaf bursts and juice.
  - A throw-arc preview that turns mint and says "yum" when the throw will land in the mouth.
  - Hold R to flop.
  - The beast glances at nearby Tenders.
  - New umbrella-pine trees, and a shaggy hair curtain on the beast.
- **Coach.** One-time contextual hints: take the lure, lower it, feeding, mites, pollen, being left behind.
- **Netcode hardening.** Streamed state only goes to peers that have finished loading (`Game.ready_peers` and `to_ready()`). Joining is error-free.

## Architecture quick map

- **Autoloads:** `G` (palette/input/fonts), `Sfx`, `Music`, `Net`, `Voice`.
- **Gameplay:** everything lives in `src/game.gd` at `/root/Main/Game`. Server-authoritative fruit, mites, beast, clock and weather. Owner-authoritative Tender movement, synced in beast-local space.
- **The beast:** `src/beast/beast.gd`. Its server state machine is IDLE/WALK/EAT/SNEEZE_IN/SNEEZE/SIT/BLOCKED/SHAKE. The shell is an analytic superellipsoid (`BeastBuild.back_height`).
- **Rendering rule:** the post ink pass reads the screen before transparents, so **use no alpha-blended materials**. ROUGHNESS ≥ 0.5 means "ink outlines".

## Testing without humans

- Bots (headless): `-- --autostart=solo --bot=steer|chaos|hop|release|pests|spy`.
- Co-op: `--autostart=host` plus `--autostart=join --ip=127.0.0.1 --bot=watch` in a second process.
- Screenshots: `--shot=out.png --cam=far|front|side|player --walk=1 --leg=N` (Xvfb + lavapipe works).

## Known gaps

- **Untested with real players and real audio.**
  - Mix balance between SFX, music and voice is unknown.
  - Gameplay numbers (drain rates, itch rate, shake force, day length 540 s) are first guesses.
- **Voice** is sent to all peers regardless of distance (fine up to 8 players). There's no echo cancellation.
- **Internet play** needs port forwarding. There's no Steam lobby or relay.
- **Mites** can pile up if ignored (cap of 10).
- **The cottage** has no interior gameplay. The roof ridge is precarious, which is intentional but may annoy.
- **Water** ripple lines can look like contour lines up close.

## Directions to fork toward

- **Music as a mechanic:** handheld kalimbas. The beast loves serenades, and joy makes it trot. There could be jam sessions on its back.
- **Catapult/flinger** on the back for launching fruit and friends.
- **Persistent keepsakes** found off-beast that unlock hats, so there's a reason to explore and risk being left behind.
- **Branching routes:** at each waystone, choose the next biome and risk level.
- **A rival crew** on a second beast (PvPvE race).
