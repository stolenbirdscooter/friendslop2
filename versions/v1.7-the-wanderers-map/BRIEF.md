# Mossback v1.7 "The Wanderer's Map": brief for whoever picks this up next

This is a standalone Godot 4.7.2 project. Open `project.godot` and press F5. Linux and Windows export presets are included; they need the 4.7.2 export templates.

## What Mossback is

Co-op friendslop for 1–8 players. Tiny felt **Tenders** live in a cottage on the back of a 30 m mossy wandering beast called the **Mossback**. Nobody drives it. The crew persuades it with:

- a sweetroot dangled from a lure pole,
- whistles,
- thrown or flung fruit,
- kalimba tunes.

The route is a branching tree of waystones (4 in 6 days). Along the way: river fords, gales, magpies, thistlemites, a lost calf, a bramble hedge to hack through and a snowy wintering ending. The beast picks a favourite, and the run writes its own field journal. Everything is procedural except two OFL fonts.

*(The v1.0 brief has the full file map. Later briefs describe each addition.)*

## Why this version exists

The journal told the story of a run in words, but nothing showed *where* it happened. The roads not taken were invisible once passed, and the crew had no way to plan past the next fork. v1.7 adds a **hand-drawn map** in the field-guide style. It's a planning tool during the run and a keepsake at the end.

## What v1.7 added

### The map (`src/ui/route_map.gd`, class `RouteMap`)
A Control that draws everything with `_draw`:

- **Biome bands:** watercolour washes as wobbly discs around the start, found by walking out along the page's axis with `Terrain.biome_index`. Their names are lettered along the bottom margin.
- **Water and woods:**
  - Water is a pale wash texture, with **inked shorelines** traced by marching squares.
  - Woods are little tree glyphs: lollipops, pines in the Wintering Hollow, autumn tints in the Ember Woods.
  - Both are sampled once per run on a `WorkerThreadPool` task from a private terrain copy (`Terrain.clone_for_thread()`, which has its own noise objects). Up to 70k samples, with the cell size growing with the route; about a second, off the main thread.
- **Roads and route:**
  - Every road of the waystone tree is dashed in its smoke colour and named along the line. Roads not yet reachable are fainter.
  - Waystones are drawn as cairns. Reached ones fly a marigold pennant, and the current options puff smoke.
  - The bramble hedge appears as plum crosses, and **cut bushes vanish, so your gap shows**.
  - Magpie nests are marked with their loot count.
- **The trail:** the beast's actual path, inked over a paper underlay.
  - Every peer records it locally from the beast's position (`Game.trail`, a point every 9 m). Late joiners get the server's copy in `_welcome`.
- **Journal marks:** `Game.jot` now stores where the beast was. Journal entries are `[day, text, kind, x, z]`, and old two-element entries still work. Kinds map to glyphs (`RouteMap.MARKS`):

  | Event | Glyph |
  |---|---|
  | Keepsake found | Star |
  | Magpie theft | Feather |
  | Nest raid | Nest |
  | Gulp | Open mouth |
  | Ford | Wave |
  | Hedge cut | Thorn |
  | Calf joined | Heart |
  | Nightfall | Tent with "night N" |
  | Shake | Zigzag |
  | Sneeze | Spray |
  | Crew fling | Arc |
  | Rescue | Ring |
  | First enchantment | Note |

- **Furniture:**
  - The beast is drawn from above, pointing along its heading, with the crew as coloured dots ("you" labelled).
  - A cartouche reads "The Wanderings of <beast name>", with a scale bar in paces, a compass rose (north rotates because the page is laid out along the migration) and a double ink border.
- **Framing:** the page is rotated so the migration runs left to right. It fits what the crew knows: the start, the trail, waystones reached, the current smokes and one fork beyond. At the end it fits the road actually taken.

### Where it appears
- **In play:** **M** or **Tab** (gamepad **Back**) unfolds it over the view, and the game carries on. `Hud.toggle_map`.
- **End of the run:** "Unfold the map" swaps the journal spread for the map.
  - The trail **inks itself** from start to finish over 6 s, a nib drawing the line, with marks appearing as it passes them.
  - Hover a mark to read its journal line in a butter-yellow callout.
  - "Keep a copy" saves the map as a PNG in `user://postcards/`.
- **Postcards on a gamepad:** the gamepad's Back used to take a postcard, so the pause menu gained a **Take a postcard** button.

### Tuning check
The v1.6 mite cut (×0.65) was re-measured with two full autopilot migrations:

| Seed | Result | Shakes | Before the cut |
|---|---|---|---|
| 42 | Won on day 4 | 7 | 10–12 |
| 7 | Won on day 4 | 4 | 10–12 |

Seed 7 also had 19 s of thorn refusal and 73 s of river balking.

## Testing without humans
- `--cam=map` (under Xvfb with `--shot=x.png --frames=300`): fakes three walked legs with journal marks, then opens the in-game map.
- `--cam=endmap`: does the same, then shows the end page with the map unfolded.
- All earlier bots and cams still apply.

## Known gaps
- **The world really is about 40% water at map scale.** Verified: the copy's heights match the live terrain exactly. So the outer bands show a lot of lake wash. A designer may want fewer lakes, or the map may want to show only water near the trail.
- **Biome labels:**
  - They're placed where each band's mid-radius meets the bottom margin. They can collide with the scale bar on very wide routes, or vanish when a band doesn't reach the bottom.
- **The map only shows the beast's trail.** Off-beast Tender adventures aren't traced, and marks sit where the *beast* was when the line was written.
- **No in-world prop:** a Tender reading the map looks like any other Tender. An oversized paper map held up in both mitts would be a cheap, funny visual for friends to see.

## Directions to fork toward
- **Fog of war:** the map is blank paper until seen, inked in as the beast walks, which gives scouting a purpose.
- **Pins:** let players drop pings onto the map, or draw on it together (shared doodles are classic friendslop).
- **The almanac:** keep every finished map, and bind them into a book in the cottage.
