# Mossback v1.6 "Bramble Gate": brief for whoever picks this up next

This is a standalone Godot 4.7.2 project. Open `project.godot` and press F5. Linux and Windows export presets are included; they need the 4.7.2 export templates. *(The v1.0 brief has the full file map.)*

## What Mossback is

Co-op friendslop for 1–8 players. Tiny felt **Tenders** live in a cottage on the back of a 30 m mossy wandering beast called the **Mossback**, and persuade it across a branching route:

- a sweetroot dangled from a lure pole,
- whistles,
- thrown or flung fruit,
- kalimba tunes.

Along the way: fords, gales, magpies, thistlemites, a lost calf, rope ladders and now a bramble hedge. The beast picks a favourite, the run writes its own field journal, and it ends in a wintering vignette. Everything is procedural except two OFL fonts.

## Why this version exists

Almost all crew work happened *on* the beast. v1.6 adds a set piece that needs the crew **off** it, working together ahead of it, then scrambling back aboard (tail or rope ladder) as it walks through. Leaving and returning is where friendslop's best panic lives.

## What v1.6 added on top of v1.5

### The bramble hedge (`Game` "bramble gate" section, `PropsLib.bramble_mesh`)
- **Where:** a seeded arc of 400–600 bramble bushes, 4.2 m apart, at the middle of the **last** ring of the route. Like the river, it's an arc around the start, so it crosses every branch.
  - It wobbles ±9 m radially and skips water.
  - It's drawn as one MultiMesh: a leafy mound with thin thorny plum canes arching out, plus leaves and berries.
- **The beast won't push through:** `Beast.thorns_check` is a callable set by Game, checked 15 m ahead with an 8 m radius.
  - Unlike water, **no tune or snack** gets it through.
  - `balk` is sent as 2 for thorns (`Beast.thorns`). The HUD mood reads "won't push through brambles", and a coach hint explains what to do.
- **Hacking a gap:** Tenders press **E within 4.2 m** of a bush. Each bush takes 4 whacks, with rustles and leaf puffs. Cut bushes vanish with a burst.
  - A beast-wide gap is about 3 bushes, which took 12 whacks in testing.
  - The cut list is in the run state for late joiners.
- **Credit:** whacks are tallied ("Hedge Trimmer" commendation).
  - The journal records the refusal ("stopped at a wall of brambles…") and, when the beast squeezes through, "*X and Y hacked a gap through the brambles, scratched all over, and it squeezed through.*"
- **Cost:** the hedge scan is skipped unless a point is near the hedge's ring radius.

## Testing without humans
- `--bot=brambles`: the beast balks about 24 m before the hedge, the bot hacks a gap, and the beast walks through about 22 m past the line.
- `--cam=brambles`, and the prop line-up (`look_test.tscn -- --props=1`) includes a bramble bush.
- The autopilot now chops through like a crew. Two full migrations (seeds 42 and 7) both **won on day 4**, and seed 7 spent about 14 s chopping through the hedge. These thistle-heavy seeds still showed 10–12 shakes a run, so the base mite spawn rate was cut by 35% (). That isn't re-measured yet; expect roughly 6–8 shakes on such seeds.

## Known gaps
- **The hedge has no physical collision**, so Tenders walk through bushes. A slow-down or scratch-tumble inside brambles would make it feel thornier.
- **Only one hedge per run, always on the last leg.**
- **A whack is one E press per hit.** No swing animation beyond a squash.

## Directions to fork toward
- **Garden shears** as a keepsake-unlocked tool (faster cutting).
- **Brambles that regrow** if the beast waits too long.
- **Make the beast help:** a well-fed, happy beast could trample a thin patch itself.
