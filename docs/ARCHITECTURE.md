# Fragdeck – architecture and handoff notes

Read this first if you are picking the project up. It describes what exists,
how the pieces talk to each other, the non-obvious decisions, and what has and
has not been verified.

## 1. What the game is

- Local splitscreen FPS, 1–6 humans plus optional bots, one PC, one screen.
- One mode: free-for-all deathmatch, first to N kills (5/10/15/20/30).
- One map: "Depot", a 64 × 48 m walled yard.
- ROUNDS-style progression: **on every death** the dead player is shown three
  random cards and must pick one before respawning. Cards permanently modify
  that player's stats for the match and stack.
- Everyone has the same gun; cards are the only source of variety.
- Engine: Godot 4.7.2, Forward+ renderer, GDScript only. No imported assets.

## 2. Running, testing, building

| Task | Command (from the project root) |
|---|---|
| Play | `Play.bat` |
| Open editor | `Edit.bat` |
| Export standalone exe | `tools\build.bat` → `build\Fragdeck.exe` |
| Re-download engine after a git clone | `tools\setup_engine.ps1 [-Templates]` |

The engine binary is `engine\Godot_v4.7.2-stable_win64.exe` (use the
`_console.exe` variant to see `print()` output in a terminal). `engine\_sc_`
enables Godot's self-contained mode, so editor settings and export templates
live in `engine\editor_data\` rather than `%APPDATA%`.

### Testing without controllers (important)

`scripts/main.gd` reads flags placed after `--`:

```
engine\Godot_v4.7.2-stable_win64_console.exe --path . -w --resolution 1920x1080 --disable-vsync -- --autotest --views=6 --shot=shots/out.png --shot-time=20 --debug
```

- `--autotest` skips the lobby and starts a 6-bot match.
- `--views=N` gives the first N bots a splitscreen cell (0 = spectator only).
- `--kb` makes player 1 a keyboard/mouse human.
- `--target=K` sets the kill target.
- `--shot=file.png --shot-time=S` saves a screenshot after S seconds, prints
  FPS and every player's kills/deaths/cards, then quits.
- `--debug` adds bot position / path / line-of-sight info to that printout.

This is how the game was verified during development: run, read the printed
stats, look at the PNG. Script errors show up on stderr as `SCRIPT ERROR`.
After adding or renaming script files run
`engine\...console.exe --headless --path . --import` once.

## 3. File map

| File | Role |
|---|---|
| `project.godot` | Project settings. Notable: fullscreen, physics interpolation ON, MSAA 2×, `Sfx` autoload. |
| `main.tscn` | A single `Node` with `main.gd`. Every other node is created in code. |
| `scripts/main.gd` | Entry point. Owns the lobby, creates/destroys a `game.gd` per match, dev flags. |
| `scripts/lobby.gd` | Join screen (immediate-mode drawn). Emits `start(config)`. |
| `scripts/game.gd` | One match: world, splitscreen viewports, cameras, scoring, respawn, explosions, aim assist. |
| `scripts/map.gd` | Builds the arena, materials, lighting, spawn points, jump pads, bot nav graph. |
| `scripts/player.gd` | `CharacterBody3D`: movement, weapon, health, status effects, death → card pick → respawn. |
| `scripts/stats.gd` | Plain data object of per-player stats that cards modify. |
| `scripts/cards.gd` | The card deck (name, rarity, description, `apply` lambda) and weighted draw. |
| `scripts/bullet.gd` | Ray-stepped projectile; bounce, homing, explosion, poison, frost, knockback. |
| `scripts/input_source.gd` | Human input for one device (keyboard+mouse or one gamepad). |
| `scripts/bot_brain.gd` | AI that exposes the same interface as `input_source.gd`. |
| `scripts/hud.gd` | Per-viewport HUD and the card picker UI (immediate-mode drawn). |
| `scripts/fx.gd` | Expanding/fading sphere effect helper. |
| `scripts/sfx.gd` | Autoload. Synthesises all sound effects at startup and plays them. |

No script uses `class_name`; scripts reference each other with `preload()`
constants. This avoids depending on Godot's global class cache.

## 4. Runtime structure

```
root (Window)
├─ Sfx                      autoload
└─ Main (main.gd)
   ├─ Lobby (lobby.gd)      Control, hidden during a match
   └─ Game (game.gd)        created per match, freed afterwards
      ├─ world (Node3D)
      │  ├─ Map (map.gd)    StaticBody3D + meshes + lights + Area3D jump pads
      │  ├─ Player × N      CharacterBody3D
      │  └─ bullets, fx     added/removed at runtime
      └─ _ui (Control)
         └─ SubViewportContainer × cells
            └─ SubViewport
               ├─ Camera3D  (+ first-person gun mesh as a child)
               └─ CanvasLayer → Hud (hud.gd)
```

### Splitscreen

All gameplay nodes are under `world`, which belongs to the root viewport's
`World3D`. A `SubViewport` without `own_world_3d` renders its parent's world,
so each cell only needs its own `Camera3D`. `game.gd::_process` positions each
camera from its player's interpolated position plus `yaw`/`pitch`.
`game.gd::_layout` sizes the cells (1 → 1×1, 2 → 1×2 stacked, 3–4 → 2×2,
5–6 → 3×2) and picks a vertical FOV giving about 100° horizontal.
Empty cells get `player == null`: an orbiting spectator camera + scoreboard.

### Visibility layers

| Bit | Used for |
|---|---|
| 0 | World, bullets, effects |
| 1 + i | Player i's third-person body and name tag. Player i's camera masks it out. |
| 8 + i | Player i's first-person gun. Only player i's camera includes it. |

### Collision layers

1 = world static geometry, 2 = players. Bullets are not physics bodies; they
ray-cast against `1 | 2`.

### Input model

`player.gd` never touches `Input`. It owns a `brain` with these members:
`move: Vector2`, `fire`, `jump`, `dash`, `reload`, `ui_left`, `ui_right`,
`ui_accept`, plus `update_look(player, delta)` (called every rendered frame,
edits `player.yaw/pitch`) and `update_buttons(player, delta)` (every physics
tick). `input_source.gd` implements it by polling one specific device id with
`Input.get_joy_axis(device, …)` / `Input.is_joy_button_pressed(device, …)`, so
the InputMap is not used at all and players can never steal each other's input.
`bot_brain.gd` implements the same interface.

Mouse motion is the one event-driven input: `game.gd::_input` accumulates
`InputEventMouseMotion.relative` into the keyboard brain's `mouse_accum`.

Gamepad extras: aim assist (`game.gd::aim_friction` – stick sensitivity drops
to 45% while the crosshair is over an enemy) and rumble when hit.

### Physics interpolation

Physics runs at 60 Hz with interpolation on, so motion is smooth on high
refresh displays. Consequences to remember:
- Cameras and anything animated per frame set
  `physics_interpolation_mode = OFF`.
- Camera position uses `player.get_global_transform_interpolated()`.
- Anything teleported (spawn, new bullet) calls `reset_physics_interpolation()`.

## 5. Gameplay internals

### Player life cycle (`player.gd`)

`spawn()` → alive → `take_damage()` → `_die()` → `_dead_tick()` handles card
selection → `_pick_card()` applies the card and calls
`game.respawn_later()` → `game.respawn()` picks one of the three spawn points
farthest from living enemies → `spawn()`.

- 1.5 s spawn protection. Slow passive regen after 6 s without damage.
- Movement: ground accel 70, air accel 22, gravity 22, dash (0.16 s burst,
  3 s cooldown), optional air jumps from cards.
- Self-inflicted deaths (own explosion, falling out) cost 1 kill.
- Headshots (hit more than 1.42 m above the feet) deal ×1.5.

### Cards (`cards.gd`, `stats.gd`)

A card is `{name, rarity, desc, apply}` where `apply` is `func(stats)`.
**To add a card, append one entry to `deck()`.** If it needs a new mechanic,
add a field to `stats.gd`, copy it in `bullet.gd::setup` if it is a bullet
property, and implement it where relevant (`bullet.gd` for on-hit effects,
`player.gd` for movement/defence). Draw weights: common 60, rare 30, epic 12.
The three offered cards are always distinct; picked cards stack without limit.

### Bullets (`bullet.gd`)

Each bullet snapshots the shooter's stats in `setup()`. Per physics tick it
applies homing and gravity, ray-casts from its current to its next position,
and resolves the hit. Bullets with `bullet_size` above ~1.7 also do a swept
sphere test against player chests. A bullet cannot hit its owner until it has
bounced once. Explosions go through `game.gd::explode` (radial falloff, half
damage to the shooter, no line-of-sight check).

### Map (`map.gd`)

Built from `_box()`, `_wedge()` (ramps), `_barrel()`, `_jump_pad()`, `_lamp()`.
Most calls mirror the piece through the origin, so only half the map is
described. Materials use world-space triplanar mapping with small greyscale
textures generated at startup, so any box can be any size without UV work.

To edit the map, change `_build_geometry()`. Keep walkable tops flush (a lip
of a few cm can snag the capsule), and keep doorways at least 2.4 m wide and
2 m high so the nav generator links through them.

### Bot navigation (`map.gd::build_nav`, `bot_brain.gd`)

Generated automatically two physics frames after the map is added:
1. Sample a 2 m grid with downward rays, up to four surfaces per column, so
   areas under decks and inside the huts are included.
2. Keep points with 1.9 m of headroom.
3. Link the 8 neighbours when the height step is ≤ 1.25 m, the ground is
   continuous between them, and a body-width corridor is clear.
4. Keep only the largest connected component in an `AStar3D`.

`find_path()` starts and ends at the nearest node reachable in a straight
line (not merely the nearest – that once made bots walk into walls). Bots
fight when they have line of sight and path-find otherwise, with a hop and
re-path when stuck. Bots cannot use the jump pads or roofs deliberately.

## 6. Verified vs not verified

Verified by automated runs on an RTX 2070 at 1920×1080:
- 6-way splitscreen renders correctly, ~420 FPS with vsync off.
- Bots fight, die, pick cards, respawn; cards change stats.
- A match reaches the kill target, shows the winner and returns to the lobby
  with no script errors.
- The exported `build\Fragdeck.exe` starts and plays.

**Not verified (no gamepad was attached during development):**
- Real gamepad input, lobby joining by gamepad, rumble, aim assist feel.
- More than four gamepads at once. Godot 4.7 uses SDL for controllers, which
  supports this, but it has not been tried on real hardware.
- Human "game feel": sensitivity, weapon balance, card balance.
- Performance on hardware weaker than an RTX 2070.

## 7. Known limitations / ideas

- Only one keyboard + mouse player (Windows gives one shared mouse).
- Audio is not positional; every sound plays at the same volume for everyone.
- No pause menu, no settings menu (sensitivity is a constant in
  `input_source.gd`: `mouse_sens`, `stick_sens`).
- If performance is a problem: lower `msaa_3d` in `game.gd::_add_view`, turn
  off `ssao_enabled` in `map.gd::_build_environment`, or set
  `vp.scaling_3d_scale` below 1.0 on the SubViewports.
- Possible next steps: more maps, health/ammo pickups, team mode, a pause and
  options screen, positional audio per viewport, character animation.
