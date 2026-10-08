# Mossback v1.2 "Back Aboard": brief for whoever picks this up next

This is a standalone Godot 4.7.2 project. Open `project.godot` and press F5. Linux and Windows export presets are included; they need the 4.7.2 export templates. *(The v1.0 brief has the full file map; v1.1's covers the autopilot.)*

## What Mossback is

Co-op friendslop for 1–8 players. Tiny felt **Tenders** live in a cottage on the back of a 30 m mossy wandering beast called the **Mossback**, and persuade it across a branching route:

- a sweetroot dangled from a lure pole,
- whistles,
- thrown or flung fruit,
- kalimba tunes.

Along the way: fords, gales, magpies, thistlemites and a lost calf. The beast picks a favourite, and the run writes its own field journal. Everything is procedural except two OFL fonts.

## Why this version exists

More whole-system testing, aimed at the moments scripted bots never reach.

### 1. Getting back on the beast was much harder than intended
Nearly everything in the game throws Tenders off the beast: sneezes, shakes, gusts, the flinger. The only way back is up the tail. A new `--bot=reboard` chases a walking beast from several start positions and tries to climb aboard.
- **Separate boxes made ledges:** the tail's collision was eight straight boxes, and the joints made small ledges. Godot's `CharacterBody3D` won't step up a ledge on a slope, so Tenders stalled halfway up.
- **The tip was a ledge too:** the tail tip ended about 1.35 m above the grass, at the limit of a Tender's 1.2 m jump. Boarding depended on jump timing.
- **Fix:** the tail is now **one continuous concave strip** following the tail curve. It continues a little onto the back so there's no lip at the root, and **runs down into the grass** 3.5 m behind the tip, so you can simply run up it.
- **Result:** reboarding a beast walking at 3.2 m/s takes **5–11 s** from behind, either side, or 48 m back. Before the fix it failed or stalled.

### 2. Fuzzing found nothing
A new `--bot=fuzz` mashes random inputs: movement, jumping, grabbing, throwing, whistles, waves, flops, interacts, pings, kalimba notes. It randomly teleports to the lure, flinger, spyglass, cottage and mouth, spawns fruit, mites and magpies, and triggers gusts.
- **Runs:** solo, plus host *and* client simultaneously in co-op, each for 15 minutes at an accelerated fixed timestep (`--fixed-fps 30 --fuzz_s=900`).
- **Result:** all three survived with **zero script errors**.

## Testing without humans
- `--bot=reboard [--rx=X --rz=Z]`: start position in beast-local metres.
- `--bot=fuzz [--fuzz_s=SECONDS]`.
- `--bot=autopilot` (whole runs), plus all earlier bots.

## Known gaps
- **Still never played by real humans.** The bots found real bugs each time they were pointed at a new part of the game; humans will find more.
- **The underside of the beast:** a straight-line run toward the tail from the side can still wedge a Tender among the hind legs. Players can walk out, but a "nudge out from under the belly" helper would be kind.

## Directions to fork toward
- **Haul ropes:** a rope ladder dangling from the flank, so friends can haul you up (another co-op verb).
- **A capturable "fall-off" moment:** the journal could note the most spectacular falls.
