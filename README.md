# Mossback

*A co-op game about walking a very large friend.* Built with **Godot 4.7.2** (GDScript, Jolt physics, Forward+).

You and your friends are Tenders: tiny felt caretakers living in a cottage on the back of an enormous, gentle, easily distracted beast. You can't drive it. You can dangle a sweetroot in front of its face, whistle at it, feed it, and hope it doesn't sneeze. Get it to each day's waystone before sunset.

Every asset is procedural: meshes from math, sound from synthesis. The only exceptions are two human-designed open fonts (Fraunces and Atkinson Hyperlegible, SIL OFL).

## Repository layout

| Path | What |
|---|---|
| `game/` | The current, in-development project. Open `game/project.godot` in Godot 4.7.2. |
| `versions/` | Frozen, independently buildable snapshots in chronological order. Each is a complete Godot project with its own `BRIEF.md`. |
| `DESIGN.md` | Living design doc for `game/`. |
| `tools/` | `snapshot.sh` (freeze a version), `shot.sh` (headless screenshot), `check.sh` (headless boot + error scan). |

## Playing

- **Open and run:** open the project in Godot 4.7.2 and press F5.
- **Build:** use *Project → Export*. Linux and Windows presets are included, and the export templates for 4.7.2 must be installed.
- **Multiplayer:**
  - One player chooses **Host a crew**. Others enter the host's address and press **Join**.
  - LAN games show up automatically.
  - Over the internet, forward UDP port 24680 on the host.

**Controls**

| Input | Action |
|---|---|
| WASD | walk |
| Space | hop |
| Shift | dash |
| E | use (take the lure, shake a tree) |
| Left mouse | pick up / drop |
| Right mouse (hold) | throw |
| Q | whistle |
| F | wave |
| Esc | menu |

While on the lure: A/D swings it left/right and W/S lowers/raises the sweetroot.

## Versions

| Version | Name | Highlights |
|---|---|---|
| [v0.1](versions/v0.1-first-steps) | First Steps | The beast walks. Lure steering, feeding, sneezes, gulps, waystones over 6 days, ENet co-op, ink-and-paper look, synthesized audio. |
