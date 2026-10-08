# Mossback v0.5 "The Field Journal": brief for whoever picks this up next

This is a standalone Godot 4.7.2 project. Open `project.godot` and press F5. Linux and Windows export presets are included; they need the 4.7.2 export templates.

## Identity (unchanged)

Co-op friendslop for 1–8 players. Tiny felt **Tenders** live in a cottage on the back of a 30 m mossy wandering beast called the **Mossback**. Nobody drives it. The crew persuades it with:

- a sweetroot dangled from a lure pole,
- whistles,
- thrown or flung fruit,
- kalimba tunes.

The run is 4 waystones in 6 days, past river fords, gales and thieving magpies. Nobody dies; failures cost time.

Everything is procedural except two OFL fonts.

## Why this version exists

The genre's value is the *stories friends retell*, and its clips spread the game. v0.4 made runs differ. v0.5 makes the game **remember and present what happened**, in the game's own "printed field guide" voice, and makes it easy to share.

## What v0.5 added on top of v0.4

### The field journal
- **Logging (server):** `Game.jot(kind, text, cap)` writes lines into `Game.journal`, with a per-day cap per kind so nothing spams. Lines sync to every peer (`_journal_add`), and late joiners receive the journal in `_welcome`.
- **What gets logged:**
  - departure (beast name and temperament),
  - weather each day, and biomes crossed,
  - sneezes, shakes and gulps (by name),
  - gourdle feedings (credited to the thrower via `Fruit.last_holder`),
  - flinger launches (who flung whom, and what cargo),
  - keepsakes found and shelved,
  - magpie thefts, whistle-offs, bonks and nest raids (including "the Mossback barged through the magpie's tree"),
  - the river: a refusal, then "X sang it across" or "lured across with a snack",
  - first enchantment each day, waystones, nightfall, and the ending.
- **Where it shows:** the waystone arrival card quotes a random line from that day's page, and the pause menu shows the last five lines.

### Commendations
- **Tallies:** `Game.tally(peer, key)` keeps per-Tender counts: notes, fed, flown, flings, robbed, shooed, tossed mites, steer time, gulped, keepsakes, spots. They're sent to everyone at WON/LOST (`_awards`).
- **The end page:** a two-page spread, with the field journal on the left and up to six commendations on the right. Examples: Beast Whisperer, Snack Courier, Frequent Flyer, Head of Artillery, Magpie's Favourite, Scarecrow, Pest Control, Helmsperson, Lunch, Collector, Eagle Eye.
  - Awards spread across players: ties go to whoever has fewer awards so far.
  - Text is pluralization-aware.

### Postcards
- Press **P** to hide the HUD, frame the view as a field-guide plate (paper border, ink rule, caption with the beast's name, biome, day and crew), and save a PNG to `user://postcards/` (the game shows the absolute path in a toast).

### Sounds
Five new synthesized sounds in `Sfx` (`magpie`, `gust`, `thwack`, `splash`, `hat_pop`). Before this, these moments reused the chirp, rustle and bonk sounds.
- **`magpie`**: a rattling 5-syllable chatter.
- **`gust`**: a 2.6 s swell with a gliding whistle. It plays at the start of each gust's telegraph.
- **`thwack`**: a wooden catapult knock with a rope creak.
- **`splash`**: a low thump with bubbles, on deep footfalls.
- **`hat_pop`**: a felt pop with a sparkle, when hats come back or get swapped.

Together they add about 90 ms of startup synthesis, roughly 15%.

## Testing without humans
- `--bot=journal` (under Xvfb, with `--shotpath=x.png`): plays a tune, flings, stages a few events, wins, and captures the end page.
- `--bot=postcard --shotpath=x.png`: saves a postcard and copies it out.
- All earlier bots still apply (steer, chaos, pests, fling, keepsake, serenade, ford, magpie, gale).

## Known gaps
- **Untested with real humans.** The journal phrasing is hand-written templates; more variety per kind would keep repeat runs fresh.
- **Gaps in what the journal can see:**
  - Tumbles and gust knock-downs aren't logged, because they're owner-side.
  - Flinger passengers are detected from the server's view of player positions, which is about 100 ms stale.
- **Postcards:** they capture the window at its current resolution. There's no share-to-clipboard.

## Directions to fork toward
- **A persistent "almanac"** across runs: the best lines from every migration, bound into a book in the cottage.
- **Postcards as collectibles:** pin them on the cottage wall, or let the host stamp a run-summary postcard automatically at each waystone.
- **Comedy tuning:** log owner-side events by sending small "story" RPCs (tumbles off the edge, longest fall, longest time off-beast).
