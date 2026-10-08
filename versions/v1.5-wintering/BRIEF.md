# Mossback v1.5 "Wintering": brief for whoever picks this up next

This is a standalone Godot 4.7.2 project. Open `project.godot` and press F5. Linux and Windows export presets are included; they need the 4.7.2 export templates. *(The v1.0 brief has the full file map.)*

## What Mossback is

Co-op friendslop for 1–8 players. Tiny felt **Tenders** live in a cottage on the back of a 30 m mossy wandering beast called the **Mossback**, and persuade it across a branching route:

- a sweetroot dangled from a lure pole,
- whistles,
- thrown or flung fruit,
- kalimba tunes.

Along the way: fords, gales, magpies, thistlemites, a lost calf and rope-ladder rescues. The beast picks a favourite, and the run writes its own field journal. Everything is procedural except two OFL fonts.

## Why this version exists

A migration is a long, silly journey. Its ending should land as *closure*, not a menu.

## What v1.5 added on top of v1.4

### A proper ending
On WON (and LOST):
- **The beast winters:** `Beast.wintering` is set on every peer.
  - It lies down (the sit pose), tucks its head down and to the side, and closes its eyes.
  - The server stops it moving and frees the lure.
  - Snow keeps falling, and the cottage lantern glows at dusk.
- **The last look:** every player's camera drifts out over about 6 s (`Game.finale_t`, in `Player._update_camera`). It eases toward a point above the beast, pulls back to about 52 m, tilts down and slowly orbits.
- **The end page waits:** the journal spread now appears 9 s after the ending (was 4 s), so the moment can breathe.

### Fixes
- **A false river line:** the river-crossing detector's "last balk" timestamp defaulted to −100. Any deep water in the first 20 s of a phase read as a ford ("Lured across with a snack…") even with no refusal. It now defaults to −1000.
- **Plurals:** the end-page summary line now says "1 day", "1 snack" and so on.

## Testing without humans
- `--cam=finale`: a snowed beast at dusk, the ending triggered, and the camera drifting out. The end page arrives after 9 s, so capture before about frame 120 at 30 fps.
- `--bot=journal` still reaches the end page.

## Known gaps
- **No music change for the ending**, beyond the existing "won" stinger. A slow lullaby would suit it.
- **The LOST ending** reuses the same vignette. It could be a little sadder: snow in the open, no waystone glow.

## Directions to fork toward
- **An epilogue card:** "The Mossback slept until spring." Next run, the same beast could wake up remembering the crew.
