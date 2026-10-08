# Mossback v0.7 "The Favourite": brief for whoever picks this up next

This is a standalone Godot 4.7.2 project. Open `project.godot` and press F5. Linux and Windows export presets are included; they need the 4.7.2 export templates.

## Identity (unchanged)

Co-op friendslop for 1–8 players. Tiny felt **Tenders** live in a cottage on the back of a 30 m mossy wandering beast called the **Mossback**. Nobody drives it. The crew persuades it with:

- a sweetroot dangled from a lure pole,
- whistles,
- thrown or flung fruit,
- kalimba tunes.

The route is a branching tree of waystones, past river fords, gales and thieving magpies, and the run writes its own field journal. Nobody dies; failures cost time.

Everything is procedural except two OFL fonts.

## Why this version exists

The beast is the star, and a star needs a personality that responds to *people*. A visible, slightly unfair preference for one crew member is a reliable generator of banter ("it likes Pip more than me!"). The bond affects play without becoming a stat screen. v0.7 also fixes a basic hole: gamepads couldn't move at all.

## What v0.7 added on top of v0.6

### The Favourite
- **Affection (server):** `Beast.affection[peer]` rises through `Game.tally()` when a Tender is kind:

  | Act | Affection |
  |---|---|
  | Feeding | +4 |
  | Shelving a keepsake | +6 |
  | Evicting a mite | +1.5 |
  | Shooing a magpie | +2.5 |
  | Spotting the smoke | +3 |
  | Steering | +0.04/s |
  | Playing notes within 20 m of its head | +0.12 each |

- **Choosing a favourite:** once someone has ≥14 affection and leads by ≥4, the beast takes a shine to them. It's announced and journalled, and `favourite` rides in the beast snapshot (23 floats now).
- **What the favourite gets:**
  - **Eye contact:** the head-glance treats the favourite as about 3× closer than they are.
  - **Comes when called:** the favourite's whistle within 90 m makes it come for 6 s, *even while the lure is down* (`Beast._fav_call_t`, a priority just under food).
  - **Nuzzle-boop:** if the favourite stands on the ground within 7 m of its mouth while it's slow, it nuzzles them (head dip, then an upward boop). The owner's client launches them on a ballistic arc that lands on the back, allowing for the walk. There's a 25 s cooldown, and it's journalled.
- **HUD:** a prize rosette by the favourite's name tag, and the belly header reads "… · fond of Pip".
- **End page:** a "Teacher's Pet" commendation.

### Gamepad
- **Movement:** the left stick moves (it was unmapped before).
- **Triggers:** the left trigger throws and the right trigger grabs or charges the flinger.
- **Other buttons:** the D-pad plays four kalimba notes (1, 3, 5, 8) and Back takes a postcard.
- **Unchanged:** the right stick still turns the camera.

## Testing without humans
- `--bot=favourite` checks three things:
  - feeding makes you the favourite;
  - standing in front of its face gets a boop onto its back (it lands with `on_beast` true);
  - your whistle 60 m to the side turns it off the lure line (about 1.2 rad).
- All earlier bots still apply.

## Known gaps
- **Untested with humans.** Affection weights and thresholds are guesses. There's no decay, so an early favourite may be hard to dethrone.
- **Nuzzle detection** uses the server's view of the favourite's position, about 100 ms stale.
- **Gamepad UI:** menu navigation relies on Godot's default `ui_*` actions and hasn't been tested on hardware. The kalimba only gets four notes on a pad.

## Directions to fork toward
- **Jealousy and rivalry:** the beast sulks if its favourite leaves for long, or affection decays so favourites change hands mid-run.
- **More favourite perks:** it catches the favourite when they fall off, or carries them in its mouth.
- **Per-beast memory across runs:** the same seed's beast remembers who it liked last time.
