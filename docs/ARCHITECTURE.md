# Fragdeck – architecture and handoff notes

Read this first if you are picking the project up. It describes what exists,
how the pieces talk to each other, the non-obvious decisions, and what has and
has not been verified.

## 1. What the game is

- Local splitscreen FPS, 1–6 humans plus optional bots, one PC, one screen.
- One mode: free-for-all deathmatch, first to N KOs (5/10/15/20/30).
- One map: "Toy Park", a 64 × 48 m walled yard.
- ROUNDS-style progression: **on every death** the dead player is shown three
  random cards and must pick one before respawning. Cards permanently modify
  that player's stats for the match and stack.
- Seven weapons (everyone starts with the Blaster). Weapons come from weapon
  cards in the deck and from pickup pads on the map; health pads too.
- 40 stat cards plus the weapon cards.
- Art direction: bright, soft, toy-like party game. Plush animal characters,
  rounded pastel geometry, chunky "sticker" UI with the Fredoka font.
- Engine: Godot 4.7.2, Forward+ renderer, GDScript only. The only imported
  asset is `fonts/Fredoka.ttf` (SIL OFL, licence beside it). Everything else –
  meshes, textures, sounds, icons – is generated in code.

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
- `--target=K` sets the kill target (`--target=1` reaches the podium quickly).
- `--lobby-demo=H,B` shows the lobby with H fake humans and B bots seated.
- `--pause-at=S` opens the pause menu after S seconds.
- `--options-demo` opens the Options screen in the lobby after one second.
- `--uncapped` stops `settings.gd` from applying v-sync and the frame limit.
  **Benchmarks need both** `--disable-vsync` (engine flag, before `--`) and
  `--uncapped` (after `--`), otherwise the default 60 FPS cap hides the result.
- `--shot=file.png --shot-time=S` saves a screenshot after S seconds, prints
  FPS and every player's kills/deaths/cards, then quits.
- `--debug` adds bot position / path / line-of-sight info to that printout.

This is how the game was verified during development: run, read the printed
stats, look at the PNG. Script errors show up on stderr as `SCRIPT ERROR`.
After adding or renaming script files run
`engine\...console.exe --headless --path . --import` once.
`--headless --path . --check-only --script res://scripts/x.gd` pinpoints a
parse error in one script.

## 3. File map

| File | Role |
|---|---|
| `project.godot` | Project settings. Notable: physics interpolation ON; autoloads `Settings` then `Sfx`. Display and AA values here are only startup defaults – `settings.gd` overrides them. |
| `main.tscn` | A single `Node` with `main.gd`. Every other node is created in code. |
| `fonts/Fredoka.ttf` | The UI font (variable weight). Loaded by `ui_kit.gd`. |
| `scripts/main.gd` | Entry point. Owns the lobby, creates/destroys a `game.gd` per match, screen fades, dev flags. |
| `scripts/ui_kit.gd` | Shared UI look: colours, font, panels, bars, text with outline, icons, 2D animal portraits, button prompts, easing. |
| `scripts/lobby.gd` | Join screen: 3D stage with podiums plus a drawn overlay. Emits `start(config)`. |
| `scripts/stage.gd` | Small sunny 3D "showroom" (sky, hills, podiums, camera) behind the lobby and results. |
| `scripts/game.gd` | One match: world, splitscreen viewports, cameras, countdown, scoring, respawn, explosions, pause menu, aim assist, hand-over to results. |
| `scripts/results.gd` | Victory screen: podium, crown, confetti, results table. |
| `scripts/map.gd` | Builds the arena, materials, lighting, scenery, spawn points, jump pads, bot nav graph. |
| `scripts/player.gd` | `CharacterBody3D`: movement, weapon, health, status effects, feedback values, death → card pick → respawn. |
| `scripts/character.gd` | The plush animal model (6 species) and its procedural animation. |
| `scripts/weapons.gd` | The weapon list: name, look, and the base stat profile each one applies. |
| `scripts/viewmodel.gd` | Toy gun model per weapon style; first-person sway/recoil/reload animation; also used as the pickup prop. |
| `scripts/pickup.gd` | Weapon and health pickup pads. |
| `scripts/sky.gd` | Sky shader (gradient, sun halo, painted clouds) shared by the arena and the stage. |
| `scripts/stats.gd` | Per-player stats, rebuilt from defaults + weapon + cards. |
| `scripts/cards.gd` | The card deck (stat cards and weapon cards) and the weighted draw. |
| `scripts/bullet.gd` | Ray-stepped projectile; bounce, pierce, homing, explosion, grenade fuse, smoke, poison, frost, knockback, headshots. |
| `scripts/input_source.gd` | Human input for one device (keyboard+mouse or one gamepad). |
| `scripts/bot_brain.gd` | AI that exposes the same interface as `input_source.gd`. |
| `scripts/hud.gd` | Per-viewport HUD and the animated card picker. |
| `scripts/fx.gd` | Particles, flashes, rings, confetti, floating damage numbers. |
| `scripts/sfx.gd` | Autoload. Synthesises all sound effects, composes and renders the two music loops in a thread, distance-attenuated playback. |
| `scripts/settings.gd` | Autoload. The list of user options, their values, saving/loading, and applying display/AA/audio settings. |
| `scripts/settings_menu.gd` | The Options screen (opened from the lobby and the pause menu). |

No script uses `class_name`; scripts reference each other with `preload()`
constants. This avoids depending on Godot's global class cache.

## 4. Runtime structure

```
root (Window)
├─ Settings                 autoload
├─ Sfx                      autoload
└─ Main (main.gd)
   ├─ Lobby (lobby.gd)      Control; owns a Stage while visible
   ├─ Game (game.gd)        created per match, freed afterwards
   │  ├─ world (Node3D, pausable)
   │  │  ├─ Map (map.gd)    StaticBody3D + meshes + lights + Area3D jump pads
   │  │  ├─ Player × N      CharacterBody3D → Character, name tag, health bar
   │  │  └─ bullets, fx     added/removed at runtime
   │  ├─ _ui (Control)
   │  │  └─ SubViewportContainer × cells
   │  │     └─ SubViewport
   │  │        ├─ Camera3D → Viewmodel (first-person blaster)
   │  │        └─ CanvasLayer → Hud (hud.gd)
   │  ├─ CanvasLayer        pause menu + fade
   │  └─ Results            replaces world/_ui when the match ends
   └─ CanvasLayer           screen fade between lobby and match
```

### One World3D for everything

Lobby stage, match world and results stage all live in the root viewport's
`World3D`, one at a time. `main.gd` calls `lobby.deactivate()` (frees the
stage) before creating the game; `game.gd::_show_results` frees `world` before
adding `Results`. Never keep two of them alive together: they would overlap
and their `WorldEnvironment`s would conflict.

### Match flow (`game.gd`)

countdown (`countdown` > 0, `frozen` = true) → play → winning kill sets
`match_over`/`frozen`, `Engine.time_scale = 0.3` for a slow-motion "GAME!" →
after 2.8 real seconds fade → `_show_results()` → `finished` signal → lobby.
`player.gd` does nothing while `game.frozen` is true.

Pause: Start or Esc toggles `SceneTree.paused`. `Game` runs with
`PROCESS_MODE_ALWAYS` so it can read buttons while paused; `world` is
`PROCESS_MODE_PAUSABLE`. Timers that must stop while paused use
`create_timer(t, false)`.

### Splitscreen

A `SubViewport` without `own_world_3d` renders its parent's world, so each cell
only needs its own `Camera3D`. `game.gd::_update_cameras` positions each camera
from its player's interpolated position plus `yaw`/`pitch`, and adds screen
shake, FOV kick and a landing dip. `game.gd::_layout` sizes the cells
(1 → 1×1, 2 → 1×2 stacked, 3–4 → 2×2, 5–6 → 3×2) and picks a vertical FOV
giving about 100° horizontal. Empty cells get `player == null`: an orbiting
spectator camera + scoreboard.

A cell's container is given a real size *before* its SubViewport is created.
Creating a viewport at the default 2×2 size makes the glow/blur buffers fail
and floods the log with rendering errors.

### Visibility layers

| Bit | Used for |
|---|---|
| 0 | World, bullets, effects |
| 1 + i | Player i's character, name tag and health bar. Player i's camera masks it out. |
| 8 + i | Player i's first-person blaster and the damage numbers player i causes. Only player i's camera includes it. |

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
`bot_brain.gd` implements the same interface. Lobby, pause menu and results
poll devices the same way.

Mouse motion is the one event-driven input: `game.gd::_input` accumulates
`InputEventMouseMotion.relative` into the keyboard brain's `mouse_accum`.

Gamepad extras: aim assist (`game.gd::aim_friction` – stick sensitivity drops
to 45% while the crosshair is over an enemy) and rumble when hit or on a KO.

### Physics interpolation

Physics runs at 60 Hz with interpolation on, so motion is smooth on high
refresh displays. Consequences to remember:
- Cameras, the viewmodel, particles and anything animated per rendered frame
  set `physics_interpolation_mode = OFF`.
- Character models are animated from `_physics_process` (by `player.gd` or
  `stage.gd`) and rely on interpolation for smoothness.
- Camera position uses `player.get_global_transform_interpolated()`.
- Anything teleported (spawn, new bullet) calls `reset_physics_interpolation()`.

## 5. Look and feel internals

### UI (`ui_kit.gd`, `hud.gd`, `lobby.gd`, `results.gd`)

All 2D UI is immediate-mode: Controls override `_draw()` and call `UiKit`
helpers, passing a scale factor derived from the viewport height. There are no
theme resources or UI scenes. To restyle the whole game, change the constants
and helpers in `ui_kit.gd`.

**HUD performance matters.** With six HUDs, redrawing everything each frame
cost about 10 ms in GDScript. `hud.gd` therefore splits itself into child
"layers" (score strip, kill feed, status, ammo). Each layer has a signature
function returning the data it displays, and is redrawn only when that
signature changes. Only the crosshair, vignettes, banners and the card picker
redraw every frame. When adding HUD elements, put them in a layer and include
their data in that layer's signature.

The card picker and pause menu blur the 3D view with a small canvas shader
that reads the screen texture (`hud.gd::BLUR_SHADER`).

### Characters (`character.gd`)

Built from scaled spheres/capsules/cones with a soft "plush" material and an
inverted-hull outline (`next_pass` material with `grow`). Species differ by
ears, tail and face. `animate()` drives walk cycle, bob, lean, landing squash
(a damped spring), blinking, ear/tail wiggle and the `cheer`/`sad` emotes.
`ui_kit.portrait()` draws the matching 2D face used across the UI.

### Rendering extras

- **Sky** (`sky.gd`): a sky shader with no `TIME` dependency, so its lighting
  cubemap is rendered once.
- **Surface detail**: `map.gd::_texture` also produces a height image that is
  converted to a normal map (`_normals`), so seams and grain catch the light.
  Characters get a fine felt normal map (`character.gd::_felt`).
- **Grass** (`map.gd::_grass`): 60,000 single-triangle blades in one
  MultiMesh, bent by a wind vertex shader. Flowers are a second MultiMesh,
  petals a CPUParticles3D. All three are skipped on Low scenery detail.
- **Warm-up** (`game.gd::_prewarm`): every effect is played once out of sight
  during the countdown so the first real one does not hitch.

### Map (`map.gd`)

Built from `_box()` (rounded-edge mesh, plain box collider), `_wedge()`
(ramps), `_barrel()`, `_jump_pad()`, `_lamp()`. Most calls mirror the piece
through the origin, so only half the map is described. Materials use
world-space triplanar mapping with small tileable textures generated at
startup, so any box can be any size without UV work. `_build_scenery()` adds
collision-free decoration: hills, trees, bushes, clouds, bunting, balloons.

To edit the map, change `_build_geometry()`. Keep walkable tops flush (a lip
of a few cm can snag the capsule), and keep doorways at least 2.4 m wide and
2 m high so the nav generator links through them. The visible perimeter wall
is 4.5 m tall but its collider is 16 m, so nobody can jump out.

### Effects (`fx.gd`)

`CPUParticles3D` bursts, expanding spheres/rings and `Label3D` damage numbers.
Every effect frees itself with a pausable timer. For `burst()` with
`explosiveness = 1`, all particle properties must be set **before** `emitting`
is turned on (see `confetti()`), or they are ignored.

### Options (`settings.gd`, `settings_menu.gd`)

`Settings.ITEMS` is the single list of options (display, graphics, audio,
controls, gameplay). Each is stored as an index into its choices; read the
value anywhere with `Settings.v("key")`. The menu is generated from that list.

**To add an option:** add one entry to `ITEMS`, then either read
`Settings.v()` where the value is used, or react to the `Settings.changed`
signal if something has to be re-applied (see `map.gd::_on_settings`,
`game.gd::_on_settings`). Graphics keys listed in `PRESETS` are overwritten by
the quality preset; changing one of them by hand sets the preset to "Custom".

Defaults: fullscreen, v-sync on, 60 FPS limit, High preset (MSAA 2×, full
render scale, high shadows, ambient occlusion and bloom on).

What applies where:
- window mode, v-sync, `Engine.max_fps`, master bus volume, shadow atlas
  size, root viewport AA: `Settings.apply()`.
- each splitscreen cell's MSAA/FXAA and render scale:
  `Settings.apply_viewport()` from `game.gd`.
- shadows, ambient occlusion, bloom: `Settings.apply_environment()` from
  `map.gd` and `stage.gd`.
- "Scenery detail" is read when a map is built, so it takes effect next match.
- look speed, invert Y, aim assist: `input_source.gd`. These are global, not
  per player.
- FOV, screen shake, bot difficulty, rumble: `game.gd`. Damage numbers:
  `player.gd`.

The file is saved as `fragdeck_settings.cfg` next to the executable (the
`engine` folder when running from source, `build` for the exported game), not
in the user profile, to keep the folder portable. Delete it to reset.

### Audio (`sfx.gd`)

There are no audio files. Effects are small functions of time rendered to
16-bit mono WAV data at startup (`_build_effects`). Music is a hand-written
8-bar tune in C major (`PROGRESSION`, `MELODY`) rendered twice by
`_render_track` – a slow "lobby" arrangement and a faster "battle" one – in a
worker thread, so it starts a second or two after launch. The buffers are
exactly one loop long and note tails wrap around, so the loops are seamless.

- `Sfx.play(name)` is for UI and personal feedback.
- `Sfx.play_at(name, pos)` is for world sounds: volume falls off with the
  distance to the nearest human player's camera (`Sfx.listeners`, filled by
  `game.gd::_update_cameras`). There is no stereo panning, because several
  listeners share one pair of speakers.
- `Sfx.music("lobby" | "battle" | "")` cross-fades; `Sfx.duck(true)` lowers
  the music while paused.

## 6. Gameplay internals

### Player life cycle (`player.gd`)

`spawn()` → alive → `take_damage()` → `_die()` → `_dead_tick()` handles card
selection → `_pick_card()` applies the card and calls
`game.respawn_later()` → `game.respawn()` picks one of the three spawn points
farthest from living enemies → `spawn()`.

- 1.5 s spawn protection. Slow passive regen after 6 s without damage.
- Movement: ground accel 70, air accel 22, gravity 22, dash (0.16 s burst,
  3 s cooldown), optional air jumps from cards.
- Self-inflicted deaths (own explosion, falling out) cost 1 KO.
- Headshots (hit more than 1.12 m above the feet – the big head) deal ×1.5.
- Feedback fields (`hit_marker`, `hurt_flash`, `shake`, `fov_kick`,
  `damage_dirs`, …) are written here and read by `hud.gd` / `game.gd`.

### Stats, weapons and cards (`stats.gd`, `weapons.gd`, `cards.gd`)

A player's `stats` object is never edited in place. `player.gd::rebuild_stats`
builds a fresh one every time something changes:

    defaults (stats.gd)  ->  Weapons.apply(player.weapon)  ->  each card in player.picked

So swapping weapon keeps every card, and cards work with every weapon (a
"+50% magazine" card gives the 2-rocket Boomer 3 rockets). Anything written
straight into `player.stats` is lost at the next rebuild.

A card is `{name, icon, rarity, desc, apply}` where `apply` is `func(stats)`
and `icon` names a pictogram in `ui_kit.icon()`. Weapon cards (rarity
`WEAPON`, generated from `Weapons.LIST`) carry a `weapon` id instead and set
`player.weapon`.
**To add a card, append one entry to `deck()`.** If it needs a new mechanic,
add a field to `stats.gd`, copy it in `bullet.gd::setup` if it is a bullet
property, and implement it where relevant (`bullet.gd` for on-hit effects,
`player.gd` for movement/defence/on-KO).
**To add a weapon,** append to `Weapons.LIST`, add its profile in
`Weapons.apply`, and add a branch for its `style` in
`viewmodel.gd::_build_gun`; its card appears automatically.

Draw weights: common 60, rare 30, epic 12; all weapon cards together are about
15% of each draw, at most one per hand, never the weapon already held. A hand
is 3 cards (more with the Lucky Draw card).

Where the less obvious card mechanics live in `player.gd`: bubble shield and
ghost dash and thorns and second wind in `take_damage`; adrenaline in the
movement/fire code; last-round and rampage bonuses in `_shoot`; scavenger and
fresh mag in `on_kill`.

### Pickups (`pickup.gd`)

`map.gd` lists `pickup_spots`; `game.gd` creates a `Pickup` at each. Weapon
pads hold a random non-default weapon and re-roll 16 s after being taken;
health pads restore 50 and return after 12 s. Bots only collect them by
walking over them.

### Bullets (`bullet.gd`)

Each bullet snapshots the shooter's stats in `setup()`. Per physics tick it
applies homing and gravity, ray-casts from its current to its next position,
and resolves the hit. Bullets with `bullet_size` above ~1.7 also do a swept
sphere test against player chests. A bullet cannot hit its owner until it has
bounced once. Explosions go through `game.gd::explode` (radial falloff, half
damage to the shooter, no line-of-sight check).

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

## 7. Verified vs not verified

Verified by automated runs on an RTX 2070 at 1920×1080:
- Lobby, Options screen, match (2/3/4/5/6 views), card picker, pause menu and
  victory podium all render with no script errors.
- 6-way splitscreen with vsync off and no frame cap: roughly 200 FPS on the
  High preset (measured after the grass/sky/normal-map upgrade).
- A settings file is read and applied (Low preset, wide FOV, hard bots).
- Bots fight, die, pick cards, respawn; a match reaches the kill target, shows
  the podium and returns to the lobby.
- The exported `build\Fragdeck.exe` starts and plays.

**Not verified:**
- Weapon balance. Every weapon and card runs without errors in bot matches,
  but the numbers in `weapons.gd` and `cards.gd` are first guesses.
- Anything audible. The music and sound effects are generated without errors
  but nobody has listened to them; expect to tune `sfx.gd` by ear.
- The Options screen was only rendered, not operated: changing values at
  runtime (fullscreen toggle, AA switch mid-match) has not been exercised.

**Not verified because no gamepad was attached during development:**
- Real gamepad input: joining, animal selection, pause menu navigation,
  rumble, aim assist feel.
- More than four gamepads at once. Godot 4.7 uses SDL for controllers, which
  supports this, but it has not been tried on real hardware.
- Human "game feel": sensitivity, weapon balance, card balance.
- Performance on hardware weaker than an RTX 2070.

## 8. Known limitations / ideas

- Only one keyboard + mouse player (Windows gives one shared mouse).
- Audio is fully synthesised; distance affects volume but there is no
  stereo positioning.
- Control options (look speed, invert Y) are global rather than per player,
  and buttons cannot be rebound.
- If a gamepad in use disconnects, the match pauses with a message; it resumes
  with that seat on the same device id when it is plugged back in.
- Characters are primitive shapes with procedural animation; real modelled,
  rigged characters would be the biggest visual step up from here.
- If performance is a problem, use the Low or Medium quality preset in
  Options.
- Possible next steps: more maps, health/ammo pickups, team mode, per-player
  control options and rebinding, kill-cam.
