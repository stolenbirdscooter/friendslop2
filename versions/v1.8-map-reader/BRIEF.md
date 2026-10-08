# Mossback v1.8 "Map Reader": brief for whoever picks this up next

This is a standalone Godot 4.7.2 project. Open `project.godot` and press F5. Linux and Windows export presets are included; they need the 4.7.2 export templates.

## What Mossback is

Co-op friendslop for 1–8 players. Tiny felt **Tenders** ride a 30 m mossy wandering beast called the **Mossback** that nobody drives. The crew persuades it with:

- a lure,
- whistles,
- thrown or flung fruit,
- kalimba tunes.

The route is a branching tree of waystones over 6 days, with fords, gales, magpies, mites, a lost calf, a bramble hedge and a snowy ending. The run writes its own journal and, since v1.7, draws its own map.

*(v1.0's brief has the file map, and v1.7's describes the map in full.)*

## Why this version exists

In friendslop, what your friends *see you doing* matters as much as what you see. In v1.7, a player studying the map looked like any other Tender standing still. v1.8 makes map-reading a visible, slightly ridiculous act.

## What v1.8 added
- **An in-world map prop:** while a player has the map unfolded (M, Tab or gamepad Back), their Tender holds up a paper map nearly as wide as they are.
  - It shows watercolour bands and an inked trail, printed on both faces.
  - Both mitts grip its edges.
  - It hides while tumbling, carrying or at a station.
- **How it works:**
  - `Player.map_open` is set by `Hud.toggle_map` and cleared when the end page opens.
  - It's replicated as flag bit 512.
  - `TenderVisual.reading` drives the pose, and `TenderVisual.map_prop` holds the mesh.
- **Dev:** `--cam=reading` frames a Tender reading the map.

## Known gaps
- **The navigator can still walk at full speed while reading.** It might be funnier, and give the "map person" a real role, if reading slowed you to a shuffle, or tipped you over when the beast lurches.
- **The prop is static.** It doesn't show the real map's content.

## Directions to fork toward
- **Render the prop from the real map:** draw the live `RouteMap` into a SubViewport texture on the prop, so onlookers see the actual route.
- **Wind:** gusts could snatch the map away (a paper chase across the meadow).
- **Pointing:** a player reading the map could point to a spot, placing a ping that everyone sees on their own map.
