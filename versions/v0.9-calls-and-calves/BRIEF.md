# Mossback v0.9 "Calls & Calves": brief for whoever picks this up next

This is a standalone Godot 4.7.2 project. Open `project.godot` and press F5. Linux and Windows export presets are included; they need the 4.7.2 export templates.

## Identity (unchanged)

Co-op friendslop for 1–8 players. Tiny felt **Tenders** live in a cottage on the back of a 30 m mossy wandering beast called the **Mossback**. Nobody drives it. The crew persuades it with:

- a sweetroot dangled from a lure pole,
- whistles,
- thrown or flung fruit,
- kalimba tunes.

The route is a branching tree of waystones, past fords, gales and magpies, with per-biome weather. The beast picks a favourite, and the run writes its own field journal. Nobody dies; failures cost time.

Everything is procedural except two OFL fonts.

## Why this version exists

Two gaps:
1. **No way to point.** Co-op without a shared way to say "look there" leans entirely on voice, and not everyone has a mic.
2. **No small, sweet side quest.** "Walking a very large friend" needed a *small* friend to bring home.

## What v0.9 added on top of v0.8

### Pings
- **Input:** G, middle mouse, or right-stick click.
- **What gets labelled:** the Tender points, and a raycast from the camera labels whatever is there:

  | Under the crosshair | Label |
  |---|---|
  | A prop | "a plumbob!", "a gourdle!", "something shiny!" (keepsake), "thistlemite!" |
  | The beast | "here!" |
  | A magpie near the line of sight (even if the ray missed) | "magpie!" |
  | A nearby tree | "fruit tree!" / "tree" |
  | Ground | "over there!" |

  - Far terrain has no collider, so the ray falls back to marching the analytic terrain height. If nothing is hit at all, the label is "that way!".
- **Display:** pings sync to everyone (`Game._ping`, one live ping per player). The HUD shows an inked marker in the pinger's crew colour, with their name, the label and the distance, and a pop ring on arrival. Off-screen pings pin to the screen edge in their direction, and they fade after 7 s.
- **Sound:** a soft chirp.

### The lost Mosslet (`src/props/mosslet.gd`)
- **Where:** one leg per run (seeded: leg 1 or 2) has a lost calf waiting about 90 m to one side of where that leg begins. Its position doesn't depend on which fork the crew picks.
- **Look:** a proper little beast, with big glossy eyes, ear nubs, a moss tuft, a trotting gait and a wagging tail.
- **States (server):**
  - **LOST:** sits, looks around and bleats (`beast_happy` pitched up). When the beast passes within 150 m, the crew hears "A small bleat, somewhere off to the left/right…".
  - **FOLLOW:** a kalimba note or whistle within 16 m makes it follow that Tender. It gives up and sits again if they get more than 28 m ahead for 10 s.
  - **JOINED:** within 34 m of the beast (or 50 m if its leader has climbed aboard), it falls in alongside the flank for the rest of the run. Hunger drain is ×0.85 because the big one stops fretting, joy goes to full, and the leader gets affection, a journal line and the "Shepherd" commendation.
- **Water:** it paddles across.
- **Replication:** clients interpolate a 10 Hz state RPC, and late joiners get the calf from the stream.

## Testing without humans
- `--bot=calf`: notes coax it, you lead it, board, and it joins.
- `--bot=ping`: checks a ping on the beast reads "here!".
- `--cam=calf`: ground-level view of the beast and the calf, with a ping.
- All earlier bots still apply.

## Known gaps
- **Untested with humans.**
- **Leading the calf:** it follows straight lines, with no pathfinding around rocks or trees.
- **Calf collisions:** it has no collision of its own, so Tenders and props pass through it.
- **Pings:** the label set is small, and there's no ping wheel ("go here", "danger").

## Directions to fork toward
- **A grown calf:** across several runs on the same seed it could grow up, until you have two beasts.
- **Ping wheel:** "follow me", "steer left", "feed it!".
- **More small friends to rescue:** a stuck hedgehog, a goose with a crown.
