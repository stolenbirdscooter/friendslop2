# Mossback v1.3 "Rope & Rescue": brief for whoever picks this up next

This is a standalone Godot 4.7.2 project. Open `project.godot` and press F5. Linux and Windows export presets are included; they need the 4.7.2 export templates. *(The v1.0 brief has the full file map.)*

## What Mossback is

Co-op friendslop for 1–8 players. Tiny felt **Tenders** live in a cottage on the back of a 30 m mossy wandering beast called the **Mossback**, and persuade it across a branching route:

- a sweetroot dangled from a lure pole,
- whistles,
- thrown or flung fruit,
- kalimba tunes.

Along the way: fords, gales, magpies, thistlemites and a lost calf. The beast picks a favourite, and the run writes its own field journal. Everything is procedural except two OFL fonts.

## Why this version exists

v1.2 made falling off cheap: the tail ramp now works. But falling off was still a *solo* problem. v1.3 turns it into a **co-op moment**. A friend on the back lowers a rope ladder for you, and the journal remembers who saved whom.

## What v1.3 added on top of v1.2

### Rope ladders (`Beast._build_ladders`, `Player.St.CLIMB`, `Game` "rope ladders" section)
- **Where they hang:** each flank has a post with a boom reaching past the shell's bulge and hair fringe (beast-local x = ±9.7, z = −3). A rolled-up ladder coil sits on the end of each boom.
- **Lowering:** anyone aboard presses **E at the post**. The server lowers the ladder for 40 s; it unrolls, sways and later rolls itself back up. `ladder_t` rides in the beast snapshot (25 floats now).
- **Climbing:** anyone at the foot presses **E** to climb.
  - W/S climbs at 2.8 m/s; the climber rides the moving beast and faces the hull.
  - At the top they step off onto the back.
  - E or jump lets go, and if the ladder rolls up under you, you tumble.
- **Credit:** if the climber didn't lower it themselves, the lowerer gets a tally ("Lifeguard" commendation), a little affection from the beast, and a journal line such as "Wren threw down the ladder for Burdock. Friendship."
- **Prompts:** context hints at the post and the foot ("The ladder's rolled up. Shout for someone aboard to lower it"), and the stranded-player coach hint mentions ladders.

### Fix: spyglass eyepiece mask
- **Problem:** it was drawn as 64 quads that self-intersected where the ring crossed the screen's horizontal midline. The fuzz bot surfaced it as 130 "triangulation failed" errors, and in play it would show as gaps in the black mask.
- **Fix:** it's now two simple polygons, the top and bottom halves of the screen with the circle's arc cut out.

## Testing without humans
- `--bot=ladder`: lower, drop to the foot, climb, land, and check the journal credit. It takes about 6 s to climb while the beast walks.
- `--cam=ladder`: a Tender mid-climb.
- The fuzz bot now also teleports to ladder posts and feet. A 7-minute solo fuzz ran with zero script errors.
- All earlier bots still apply.

## Known gaps
- **Untested with humans.** 40 s down and 2.8 m/s climbing are guesses.
- **The ladder has no collision,** so other Tenders and props pass through it, and climbers can clip the fringe hair.
- **No hauling verb:** there's no "pull the rope to winch someone up" yet. It would be a fine next verb.

## Directions to fork toward
- **Winching:** two people on the back crank a climber up faster.
- **Ladder pranks:** roll it up while someone's climbing. Already possible: the ladder's timer can run out. Maybe make it deliberate.
