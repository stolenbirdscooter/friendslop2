# Mossback v1.1 "Field Trials": brief for whoever picks this up next

This is a standalone Godot 4.7.2 project. Open `project.godot` and press F5. Linux and Windows export presets are included; they need the 4.7.2 export templates.

## What Mossback is

Co-op friendslop for 1–8 players. Tiny felt **Tenders** live in a cottage on the back of a 30 m mossy wandering beast called the **Mossback**. Nobody drives it. The crew persuades it with:

- a sweetroot dangled from a lure pole,
- whistles,
- thrown or flung fruit,
- kalimba tunes.

The route is a branching tree of waystones, with 4 waystones in 6 days. Along the way: fords, gales, magpies, thistlemites, a lost calf and per-biome weather. The beast picks a favourite, and the run writes its own field journal. Everything is procedural except two OFL fonts.

*(The v1.0 brief has the full file map.)*

## Why this version exists

Every earlier version was tested only with short scripted bots. None played a *whole migration*. v1.1 adds an **autopilot**: a bot that plays complete runs as a competent crew, headless at an accelerated fixed timestep. It steers toward the smoke, forages when the beast is hungry, picks off mites and sings at rivers. I ran it over several seeds.

It found **two core bugs present since v0.1** that made long runs unwinnable.

## Bugs the simulations found (and fixes)

1. **The beast could never eat food lying on the ground.**
   - **What happened:** the food branch of `Beast.server_tick` set `Act.EAT`, and the last line of the same branch overwrote it with WALK in the same tick. Separately, even when eating, the eat check needed the fruit within 2.9 m of the mouth in 3D. The mouth hangs about 7 m up, and when the head dips it swings about 2.4 m back toward the body.
   - **Why no test caught it:** the only feeding ever tested was fruit thrown straight into the mouth.
   - **Fix:** EAT is no longer overwritten. While eating (after 0.5 s), the targeted fruit within 7 m horizontally of the mouth is snuffled up. The beast also keeps tracking food up to 4.5 m behind its standing mouth position.
   - **Test:** `--bot=groundfeed`.
2. **A starving beast could never be fed again.**
   - **What happened:** at zero belly it sits until it has eaten more than 18, but the eat check refused all food while it was sitting. That's a hard deadlock: the first autopilot runs sat for 1,400–2,000 s and lost.
   - **Fix:** a sitting beast eats food thrown at its mouth, and snuffles up fruit lying within 6 m of its lowered mouth.
   - **Test:** `--bot=sitfeed`.
3. **Rocks were treated as trees.**
   - **What happened:** rock records also carry a `variant` key, and every "is it a tree?" check tested `has("variant")`. The beast "shook" boulders (a script error), "E shake the tree" appeared next to rocks, magpies could nest on rocks, and pings called rocks trees.
   - **Fix:** the checks now test `has("fruit")`, which only trees have.
4. **Physics pile-ups.**
   - **What happened:** uneaten fruit could accumulate without limit, and one 50-minute autopilot run ended in a native crash (signal 11) in an engine worker thread, after about 90 fruit bodies had piled up around the moving kinematic shell.
   - **Fix:** loose fruit is capped at 45. Spawning beyond that recycles the oldest loose fruit more than 40 m from the beast. (Root cause unconfirmed: no symbols. It hasn't reproduced since the pile-ups stopped.)

## Also in v1.1
- **Settings on the title screen:** a shared `Ui.settings_box()` (look speed, four volume sliders, invert Y, push-to-talk, mute). Everything is persisted, including push-to-talk and mute, which used to reset.
- **Journal variety:** more phrasings for gulps, flinger launches and magpie thefts (`Game.pick_line`).
- **Waving back:** the beast waves an ear and hums back when its favourite waves (F) within 25 m.

## Pacing results (autopilot, after fixes)
**Before the fixes:** 4 seeds, all **lost**. Legs 1–2 took 2.5–6 min, then the beast starved, sat and never got up.

**After the fixes, with v1.0 tuning:** 3 seeds (42, 7, 99) all **won on day 4**.

| | Range |
|---|---|
| Leg times | 151–274 s, against a 540 s day |
| Shakes per run | **12–21** (about 4 per leg) |
| Sneezes per run | 4–6 |
| River balks per run | 0–40 s |

**Tuning applied from this data:**
- **Itch per mite halved** (3.2 → 1.6/s). Every shake flings the whole crew off except the lure operator, and about 4 per leg would grate. One mite now takes about 62 s to cause a shake, and three take about 21 s.
- **Day length 540 → 450 s.** A focused crew needs less than half the old day, and arriving early doesn't bank time (the next leg starts at the next dawn). 7.5 minutes keeps roughly 2× headroom for crews who forage, chase magpies and rescue calves, while a wandering crew can now lose a day.

**After tuning:** 2 seeds (1234, 5) both **won on day 4**.

| | Range |
|---|---|
| Leg times | 134–283 s |
| Shakes per run | 1–3 |
| Sneezes per run | 3–13 (the 13 is likely a "Sneezy" beast) |

## Testing without humans
- `--bot=autopilot` plays a whole migration and prints a per-day log and a summary. Run it as `godot --headless --fixed-fps 30 --path . -- --autostart=solo --seed=N --bot=autopilot`. That's about 2× real time on 4 cores, roughly 25 minutes per run.
- `--bot=groundfeed`, `--bot=sitfeed`.
- All earlier bots still apply.

## Known gaps
- **The autopilot is not a human crew.** It's efficient and never distracted, so real groups will be slower. Pacing should be judged with that in mind.
- **The native crash** has no root cause, only a mitigation.
