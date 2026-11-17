# Fragdeck – architecture and handoff notes

Read this first if you are picking the project up. It describes what exists,
how the pieces talk to each other, the non-obvious decisions, and what has and
has not been verified.

## 1. What the game is

- Local splitscreen FPS, 1–6 humans plus optional bots, one PC, one screen.
- Three modes (lobby MODE chip, `config.mode`):
  - **Rounds** (default): free-for-all deathmatch, first to N KOs
    (5/10/15/20/30). Rules in `game.gd`.
- **Zombies**: co-op against endless waves (`zombies.gd`, `zombie.gd`). Zombies
  follow the navigation graph and recover from jams by repathing and sidestepping;
  they are never teleported to players when they fall behind.
  - **Frontline**: two teams, conquest flags, tickets, vehicles, parachute
    spawns on its own huge map (`frontline.gd`, `vehicle.gd`, `map_front.gd`).
- Six Rounds maps, each with its own theme and song (see `map.gd`,
  `map_places.gd`, `sfx.gd`): Neon Yard, Ember Pit, Frost Line, Museum,
  Stadium, Suburb. Zombies uses a separate, larger Quarantine campus map;
  Frontline has its own huge battlefield.
  Every match rolls a time of day (day / sunset / night, or the lobby's
  choice). Weather and precipitation are disabled; large outdoor maps use a
  restrained distance haze.
- ROUNDS-style progression: **on every death** the dead player is shown three
  random cards and must pick one before respawning. Cards permanently modify
  that player's stats for the match and stack.
- Twelve weapons (everyone starts with the Blaster). Weapons come from weapon
  cards in the deck and from pickup pads (press interact); health pads too.
- Abilities everyone has: jump, dash, block (short guard that negates damage
  and reflects every projectile passing within 1.1 m; 4 s cooldown), aim down
  sights, crouch, slide, wall run, wall jump and mantle.
- Art direction: readable colour and visibility in every time setting, with
  moody lighting, neon trims and stronger effects. Zombies' Quarantine campus
  adds red emergency beacons, a fenced perimeter, wrecks and an underground
  triage route. Selectable characters are seven imported rigged animals
  (Bunny, Frog, Dino, Bird, Yeti, Fish, Monkroose); each player chooses colour,
  hat and face. Chunky UI with the Fredoka font on near-black
  panels.
- Engine: Godot 4.7.2, Forward+ renderer, GDScript only. Imported assets:
  `fonts/Fredoka.ttf` (SIL OFL) and the CC0 models in `assets/models/`
  (Quaternius: Toon Shooter, Zombie Apocalypse, Stylized Nature; licence note
  beside them). Map layouts, plush characters, textures, sounds, music and
  icons are generated in code.

## 2. Running, testing, building

| Task | Command (from the project root) |
|---|---|
| Play | `Play.bat` |
| Open editor | `Edit.bat` |
| Export standalone exe | `tools\build.bat` → `build\SlopGame.exe` |
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
- `--map=N` picks the arena (0 Neon Yard, 1 Ember Pit, 2 Frost Line, 3 Museum,
  4 Stadium, 5 Suburb).
- `--mode=rounds|zombies|frontline` and `--teams=versus|coop` pick the mode.
- `--wave=N` (Zombies) starts at wave N; `--drive=buggy|tank|heli`
  (Frontline) puts player 1 in that vehicle. A finished match prints
  `[match] over at ... s: <result>`.
- `--force-aim` makes everyone aim down sights (to check the sight picture).
- `--seed=N` seeds the random generator so runs are comparable.
- `--time=day|sunset|night` fixes the time of day.
- `--cards=2x Scope,Jetpack` gives every player those cards; `--weapon=N` a weapon.
- `tools/contact_sheet.gd` combines screenshots into a grid (see its header).
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
| `project.godot` | Project settings. Notable: 120 Hz physics with interpolation ON and jitter fix 0; swapchain image count 2 (less input lag); autoloads `Settings` then `Sfx`. Display and AA values here are only startup defaults – `settings.gd` overrides them. |
| `main.tscn` | A single `Node` with `main.gd`. Every other node is created in code. |
| `fonts/Fredoka.ttf` | The UI font (variable weight). Loaded by `ui_kit.gd`. |
| `scripts/main.gd` | Entry point. Owns the lobby, creates/destroys a `game.gd` per match, screen fades, dev flags. |
| `scripts/ui_kit.gd` | Shared UI look: colours, font, panels, bars, text with outline, icons, 2D animal portraits, button prompts, easing. |
| `scripts/lobby.gd` | Join screen: 3D stage with podiums, per-player character customisation, map / bots / kill-target selection. Emits `start(config)`. |
| `scripts/stage.gd` | Small sunny 3D "showroom" (sky, hills, podiums, camera) behind the lobby and results. |
| `scripts/game.gd` | One match: world, splitscreen viewports, cameras (incl. the vehicle chase camera), countdown, Rounds scoring, the mode hooks, teams (`is_enemy`, `damageables`, `hostiles`), respawn, explosions, pause menu, aim assist, hand-over to results. |
| `scripts/models.gd` | Imported models: cached `scene()`, `parts()` (mesh + transform list) and `bounds()` by path relative to `assets/models/`. |
| `tools/inspect_models.gd` | Dev tool: prints every model's size, node tree and animations. |
| `scripts/zombies.gd` | Zombies mode rules: endless waves, spawning, intermission card picks, revival, game over. |
| `scripts/zombie.gd` | One zombie (walker / runner / brute / boss): model, nav pathing, melee, non-teleporting jam recovery, blood effects, damage interface. |
| `scripts/frontline.gd` | Frontline mode rules: teams and CPU fill, flags, tickets, parachute spawns, vehicle respawns, bot goals, flag HUD. |
| `scripts/vehicle.gd` | Buggy, tank and helicopter: models, driving / flying, turrets, visible muzzle flashes and tracers, weapons, damage, destruction. |
| `scripts/map_front.gd` | Layout 6 (FRONTLINE): town, towers, warehouse, bunkers, trenches, farms, bases, vehicle spots, flags. |
| `scripts/results.gd` | Victory screen: podium, crown, confetti, results table. |
| `scripts/map.gd` | The map builder: `MAPS`, `THEMES`, time-of-day lighting, procedural textures, mesh batching, building blocks (walls with openings, stairs, buildings, tunnels, basements, trees, grass), layouts 0-2, bot nav graph. Stairwell openings are kept clear through slabs and facade trim. |
| `scripts/map_places.gd` | Layouts 3-5 (Museum, Stadium, Suburb) built with the map.gd helpers. |
| `scripts/map_zombie.gd` | Dedicated large Zombies map: hospital campus, annex, warehouse, motel, quarantine fence, yard, tunnel, basement and indoor/outdoor spawns. |
| `scripts/player.gd` | `CharacterBody3D`: movement, weapon, health, status effects, feedback values, death → card pick → respawn. |
| `scripts/character.gd` | The plush animal model (6 species, 11 hats, 7 faces) and its procedural animation. |
| `scripts/weapons.gd` | The weapon list: name, look, and the base stat profile each one applies. |
| `scripts/viewmodel.gd` | Gun model per weapon style (receiver, barrel, magazine, stock, sights; merged into one mesh per material), first-person sway/recoil/reload/pump/cylinder animation and world-space muzzle position; also used as the pickup prop and, scaled up, as the third-person gun (`character.gd::set_weapon`). |
| `scripts/pickup.gd` | Weapon and health pickup pads. |
| `scripts/sky.gd` | Sky shader (gradient, sun halo, painted clouds) shared by the arena and the stage. |
| `scripts/stats.gd` | Per-player stats, rebuilt from defaults + weapon + cards. |
| `scripts/cards.gd` | The card deck (stat cards and weapon cards) and the weighted draw. |
| `scripts/bullet.gd` | Ray-stepped projectile; bounce, pierce, homing, explosion, grenade fuse, smoke, poison, frost, knockback, headshots. |
| `scripts/input_source.gd` | Human input for one device (keyboard+mouse or one gamepad). |
| `scripts/bot_brain.gd` | AI that exposes the same interface as `input_source.gd`. |
| `scripts/hud.gd` | Per-viewport HUD and the animated card picker. |
| `scripts/motion_blur.gd` | Optional, per-viewport camera-motion blur controlled by the Graphics slider. |
| `scripts/fx.gd` | Particles, flashes, rings, confetti, floating damage numbers and blood spray/stains. |
| `scripts/sfx.gd` | Autoload. Synthesises all sound effects, composes and renders the music loops (one per map, lobby, zombies, frontline) in a thread, distance-attenuated playback. |
| `scripts/settings.gd` | Autoload. The list of user options, their values, saving/loading, and applying display, AA, motion blur and audio settings. |
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
   │  │  ├─ rules           zombies.gd / frontline.gd (not in Rounds)
   │  │  ├─ Zombie / Vehicle  CharacterBody3D, listed in game.actors
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
| 7 | Bodies of players with index 6+ (Frontline fills teams to 12; only players 0-5 can have a camera). |

### Collision layers

1 = world static geometry, 2 = players, zombies and vehicles. Bullets are not
physics bodies; they ray-cast against `1 | 2`. A player inside a vehicle has
collision off (the vehicle takes the hits).

### Imported models (`models.gd`, `assets/models/`)

- The user allows free, clearly licensed models; these are all CC0. Add more
  as `.glb` under `assets/models/<pack>/`, run `--import`, and note the
  source in `assets/models/LICENSE.txt`. `tools/inspect_models.gd` shows a
  model's size, facing and animation names before you place it.
- **Static props:** `map._model(path, pos, yaw, scale, mirror, collide)` adds
  every surface of the model to the normal material batches (so props cost
  no extra draw calls) and a box collider from its bounds. `_tree`, `_pine`,
  `_bush`, `_rock`, `_plant`, `_container`, `_barrel`, `_lamp_post`, cube
  crates in `_box`, `map_places._car` and `map_front._sandbags` use it.
  Out-of-bounds scenery uses the light toon trees (the nature-pack trees
  have ~10k vertices each).
- **Guns:** `viewmodel.GLB` maps eight weapon styles to gun models
  (`_build_glb`: turned to face -Z, scaled to a length, rear end behind the
  grip). Grey surfaces are re-coloured to gun-metal (`_gunmetal`), a band in
  the player's colour is added. They are one-piece meshes, so the pump /
  cylinder animations only exist on the hand-built guns (Spinner, Bubbler,
  Pinball, Flamer keep those).
- **Zombies:** `zombie.MODELS` maps each type to a rigged model with an
  AnimationPlayer (Walk, Run, Punch / Idle_Attack, HitReact, Death). The hit
  flash is a `material_overlay`.
- **Buggy:** the armoured pickup; its wheel meshes are re-parented onto
  pivots at their centres so they spin and steer. Tank and helicopter are
  still hand-built (no free model with a separate turret / rotor was found).
- **Health pad:** the first-aid kit model.

### Physics props, glass and pets (`prop.gd`, `glass.gd`, `pet.gd`)

- **Props** are RigidBody3D on collision layer 4 with mask `1 | 4`: they hit
  the world and each other but never block characters, and the nav graph
  ignores them. Things move them explicitly: `Prop.kick_near()` (a small
  sphere query, called by player / zombie / vehicle while moving), bullets
  (`bullet.gd` ray mask includes 4 and calls `knock()`; ordinary bullets stop
  on a prop), and `game.explode` (group "props"). They start asleep, are
  re-centred on their footprint, are not drawn beyond ~22-48 m and small
  ones cast no shadow.
- Placement: `map._prop(path, pos, yaw, scale, mass)`; `map._furnish()` puts
  a dining room, lounge or office on every storey of `_building`;
  `map._scatter_props()` drops clutter on random nav points once the nav
  graph exists (signal `nav_built`).
- **Glass** (`map._glass`, automatically in every `_building` window) is a
  StaticBody3D on layer 4: `knock()` shatters it; bullets continue through.
  Panes share one mesh per size so they instance.
- **Pets** (`pet.gd`): spawned by `game._spawn_pets` on `nav_built`; they
  wander along `map.find_path`, and `player.gd` offers "PET THE ..." via
  `game.pet_near()` (interact). Dev flag `--pets-demo` lines up every kind.

### Buildings and landscape (`map.gd`)

- `_facade()` adds sills, lintels, shutters (pitched houses), porch roofs
  with posts and steps at both doors and a string course per storey;
  `_building` adds a foundation band, corner posts, a chimney or roof clutter.
- `_forest(rect, count)` = dense woodland from light low-poly trees plus a
  few detailed ones, undergrowth, logs, rocks. `_camp()`, `_sidewalk()`,
  `_crossing()` dress the open ground; see `map_front._landscape`.

### Special bullets, block perks and body perks

- `stats.gd` fields `chain`, `cluster`, `vortex`, `sticky`, `range_bonus`,
  `frag` are implemented in `bullet.gd` (`_chain_from`, `_spawn_child`,
  `_stick`, the vortex pull in `_physics_process`). Weapons 12-19 and several
  cards use them.
- Block perks fire when the block starts: `player._start_block(first)`
  (reload, empower, blink, frost, pull, bullet ring, echo). Add a new one as
  a `block_*` stat + a card + a few lines there.
- `stats.size` scales the model, capsule, eye and head heights (Tiny /
  Giant); `stomp`, `slam`, `martyr`, `corpse_bomb`, `drone`, `speed_dmg`,
  `air_dmg` live in `player.gd` (search for the stat name).

### Characters (`character.gd`)

- Every character is an imported rigged model: `character.ROSTER[kind]` =
  [model, "creature" | "human"] (names in `ui_kit.KIND_NAMES`, 2D portrait
  style in `ui_kit.PORTRAIT`). The old sphere-built plush rig is still in the
  file but unreachable (the user asked for it to go); delete it when convenient.
- Creatures (Quaternius Ultimate Monsters, one shared rig, scale 0.53):
  Idle / Walk / Run / Jump_Idle / Duck (crouch) / Wave / No / HitReact.
  Meshes off to the side of the body (their own carrot, club...) are hidden.
- Humans (Quaternius animated characters, scale 0.94): Idle_Gun_Pointing,
  Run_Shoot, Run_Left/Right, Wave (`_animate_human`).
- To add a character: drop the .glb in `assets/models`, add a ROSTER row, a
  KIND_NAMES entry and a PORTRAIT entry, bump `KIND_COUNT`. The player's colour is a light overlay; the hit
  flash swaps the overlay to white; hats ride a BoneAttachment3D on "Head";
  the gun floats in the aiming pose on the `aim` pivot.
- Customisation: hat, face (plush only) and the new back accessory
  (`_build_back`, `ui_kit.BACK_NAMES`); the lobby category list is
  `lobby.CATEGORIES` / `KEYS`.

### Melee, taunts, per-player look speed (`player.gd`, `input_source.gd`)

- **Melee** (`brain.melee`: R3 / F / middle mouse): `player._melee_start()`
  starts a swing (`melee_t` drives the viewmodel and `character.swing()`),
  `_melee_strike()` lands it 0.1 s later: enemies in an arc in front of the
  eye (nearest first; a punch hits one, melee weapons cleave), then props /
  doors on layers 4 | 8 (`hurt` + `knock`) and crumbling walls (`hurt`).
  It applies the same per-shot bonuses and on-hit stats as bullets
  (rampage, empower, poison, frost, knockback, chain, explosive), so cards
  stay compatible. `game.melee_strike` is true while it deals damage (Gun
  Game demotion, Bloodthirst).
- **Melee weapons** set `stats.melee_weapon` (+ `melee_range`, `melee_arc`):
  `_weapon_tick` then swings on fire instead of shooting; no ammo.
- Melee cards are plain stats: `melee_damage`, `melee_cd`, `melee_reach`,
  `melee_backstab`, `melee_knock`, `melee_parry` (`parry_left` makes
  `is_blocking()` true so bullets reflect), `melee_heal`, `melee_charge`.
- **Taunts** (`brain.taunt` 0-3: D-pad / keys 1-4): `player.TAUNTS`,
  `start_taunt()`; `character.taunt` picks the animation, `_bubble` is the
  speech bubble, and `taunt_view` (0..1) blends that player's camera to a
  third-person shot in `game._update_cameras` (their own body layer is
  added to the camera's cull mask meanwhile). Dev flag `--third` holds
  player 1 in that camera to inspect how weapons are held.
- **Look speed per player**: the lobby's LOOK row stores `seat.sens`
  (saved with the seat); `game.gd` turns it into `InputSource.sens`, a
  multiplier on top of the global look-speed options.

### Weapons in the hands (`arm_ik.gd`, `character.gd`, `viewmodel.gd`)

- The weapon model sits on the character's `aim` pivot (so it follows the
  view pitch exactly). `arm_ik.gd` (a SkeletonModifier3D on the creature
  skeleton) bends UpperArm / LowerArm so each hand reaches a grip marker
  (`_grip_r`, `_grip_l`) that `set_weapon()` places from the viewmodel's
  `grip_r` / `grip_l` / `two_handed`. Taunts and punches fade the IK out
  (`_ik.influence`) so the animation shows.
- `viewmodel.gd` builds three families: `GLB` guns (barrel along -Z),
  `UPRIGHT` items held in the fist (sword, axe, spear, staffs, bow, knife,
  bomb; they hang on the `_blade` pivot) and `_build_hands` (mage hands
  with a spell orb). `muzzle_local()` is where shots leave.
- `stats.projectile` makes `bullet.gd` fly a model (arrow, bolt, knife,
  bomb; `PROJECTILES`); arrows stay stuck in what they hit for 6 s.
  `stats.bolt` draws `Fx.bolt` from muzzle to aim point (Storm Staff).
- `tools/weapon_sheet.gd` (`-- --sheet=out.png --ids=24,26`) renders
  weapon models side-on and first-person for tuning.

### Ground cover, mounds, lamps, sun rays (`map.gd`, `sun_rays.gd`)

- `_occ_build()` rasterises everything standing on the ground (collider
  boxes, trunks, `_surface` rects, `no_grass`, holes) into a 0.5 m
  occupancy grid; `_occupied()` / `_clear_disc()` answer "is this ground
  free" in O(1). Mounds, grass and undergrowth all use it.
- `_mounds()` (themes with `"cover": true`): shallow sphere-cap hills with
  a deliberately coarse 25-point convex collider. A detailed hull made
  every character standing on one expensive (it caused the v0.14 hitching
  during development). `ground_y(x, z)` gives the height for foliage.
- `_grass()`: textured cards, not polygons-per-blade. `_foliage_tex()`
  paints grass / fern / leafy / flower textures in code (cached);
  `_card_mesh()` is three crossed quads; `FOLIAGE_SHADER` alpha-cuts,
  sways and lights them as if facing the sky. One MultiMesh per kind per
  16 m chunk with `visibility_range_end`, so only nearby foliage draws.
  Whole-map cover where the theme says `cover`, else only `lawns`.
- Clutter is themed: `CLUTTER_SETS[MAPS[i].clutter]`.
- `_lamp()` = pendant model + warm OmniLight that ignores the time of day
  (distance-faded); `_building` hangs a grid of them on every storey.
- Depth of field (`game._focus`, option `dof`): far blur only. Each frame
  the focus limit is set to where that camera's view leaves the map
  rectangle (clamped 16-220 m, smoothed), so the playable area stays sharp
  and the scenery beyond the boundary blurs; indoor maps push it out to
  400 m. Small outdoor maps also get a light haze.
- `sun_rays.gd`: a full-screen quad on each camera (its own layer, bits
  15-20). The shader marches from each pixel towards the sun's screen
  position counting open sky in the depth buffer. Option `rays`.
- Dev: `--top` (views=0) is an overhead camera; `--audit` prints models
  whose box cuts into another collider; the `--shot` report now includes
  slow-frame and worst-frame counts (hitches hide in averages);
  environment variable `SLOP_TEST=nograss|nomounds` switches those off for
  A/B timing.

### Doors, breakables, crumbling walls (`door.gd`, `prop.gd`, `rubble.gd`, `debris.gd`)

- Everything breakable is in group "props" and answers `knock(impulse, at)`
  and `hurt(amount, who)`; bullets, melee and `game.explode` call them.
- **Doors** (`map._door`, automatically in both ground-floor doorways of
  `_building`) have no button. `door.gd` is a damped spring on the hinge
  angle: bodies in group "door_users" standing in the doorway push the leaf
  away from their side (latched in `_side` so it does not flip as they pass
  through), harder the faster they move; with nobody there it swings back
  and settles. Characters do not collide with the leaf (layer 8 is only in
  the bullet / melee masks), so nothing ever has to be opened and the nav
  graph is unaffected. `knock()` kicks the hinge, `hurt()` breaks it
  (110 hp).
- **Props** are solid: layer 4 is in the player and zombie collision masks,
  and prop masks include bodies. Mass = `DENSITY` (70 kg/m3) x bounding
  box volume, hp from mass. Every shove is a fixed impulse (walking into it
  ~8 kg x speed, bullets damage x 0.35, blasts up to 260 N s) capped at
  `MAX_SPEED_GAIN`, so light things fly and heavy things shift.
  `EXPLOSIVE` models call `game.explode_later`. `map._scatter_props` places
  clutter side by side (never overlapping) and awake, so it settles. The
  nav graph still ignores props: a bot blocked by furniture shoves it or
  uses its unstick hop.
- **Crumbling walls** (`map._weak_wall`, and `map._ruins()` scatters stubs
  on open ground of every outdoor map): StaticBody3D on layer 1 (so bots
  path around them), drawn as a MultiMesh of bricks, losing bricks below
  55 % and collapsing into `debris.gd` chunks at 0. The nav graph is not
  rebuilt, so bots keep walking around a fallen wall.
- `debris.gd` chunks collide with the world only and cap at 140 alive.

### Gun Game and Medieval (`gungame.gd`, `medieval.gd`, `map_castle.gd`)

- Both are free-for-alls built on the rules hooks. Optional hooks added for
  them: `weapon_pool()` (limits weapon cards and pads), `banned_cards()`,
  `modify_stats(s, p)` (applied after the cards), `weapon_pads()`; and
  `draw_strip` / `strip_sig` are now optional (the default FFA strip is
  used). `game.spawn_all_default()` / `respawn_default()` are the Rounds
  spawns for rules to reuse.
- Gun Game: rung = `kills`; `weapons.ladder()` is the order.
- Medieval forces `Map.CASTLE` (index 8, also in `Map.ARENAS`, the lobby's
  map list). `weapons.era(id)` / `pool(eras)` group the arsenal.

### Game modes and teams (`game.gd`, `zombies.gd`, `frontline.gd`)

- `game.mode` is "rounds", "zombies" or "frontline". Rounds keeps its rules in
  `game.gd`; the other modes create a rules node (`game.rules`) under `world`.
  game.gd calls its hooks: `prepare(parts)` (assign teams, add CPU players),
  `start()` (spawn), `on_died(victim, attacker)`, `respawn(p)`,
  `cards_on_death()`, `bot_goal(p)`, `results_title()`, and for the HUD
  `strip_sig()` / `draw_strip()` / `draw_markers()` plus `banner` /
  `banner_t`. Rules end a match with `game.end_match()`.
- `player.team` (-1 = free-for-all). `game.is_enemy(a, b)` decides friendly
  fire; `player.take_damage` ignores allies. `game.damageables()` = players on
  foot + `game.actors` (zombies, vehicles), cached per physics frame; bullets,
  explosions and the block catch use it. `game.hostiles(who)` = living enemies
  (manned vehicles only) for bots, homing and aim assist.
- Anything damageable implements: `alive`, `team`, `pname`, `color`, `kind`,
  `take_damage(amount, attacker, silent, crit)`, `chest_position()`,
  `is_blocking()`, `apply_poison()`, `apply_slow()`, optional `hit_radius()`
  and `head_height()`. Code that needs the shooter's stats checks
  `game.is_player(x)` first (zombies and vehicles have none).
- Kill feed entries are copies (`_feed_entry`) because zombies are freed.

### Zombies (`zombies.gd`, `zombie.gd`)

- Wave n spawns `(6 + 4n) * (0.7 + 0.3 * squad)` zombies a few at a time,
  max 26 + 2 per player alive. Runners from wave 3, brutes from wave 5, a boss
  every 5th wave. Health ×(1 + 0.13(n-1) + 0.004(n-1)²), speed up to ×1.55,
  damage +4%/wave: unbounded, so it always ends eventually.
- Zombies spawn on random nav nodes 15–45 m from the players, chase the nearest
  player (straight line when close and visible, A* path otherwise), hop and
  skip waypoints when stuck, and stragglers are teleported back after 18 s.
- Between waves (9 s, shorter once everyone has picked): dead players respawn
  next to a teammate and every player gets `offer_cards()` (`player.picking`:
  stands still, the HUD shows the card picker, picking refills health/ammo).
- Dying shows "YOU'RE DOWN" (no card); all down = "SURVIVED N WAVES".

### Frontline (`frontline.gd`, `vehicle.gd`, `map_front.gd`)

- Map index `Map.FRONTLINE` (6), hidden from the lobby's map list. Point
  symmetric: built for +X and mirrored, team colours placed unmirrored. Data
  for the rules: `map.flags`, `map.bases`, `map.vehicle_spots`.
- Teams fill to 6 each with CPU soldiers (bots wear the team colour; name tags
  are tinted). Tickets = lobby value; a death costs 1; holding more flags
  bleeds the other team every 4 s. Flags swing neutral → captured while only
  one team stands in the 9 m circle (faster with more people).
- Spawning: `_drop()` puts players 40–80 m up with `player.skydive`; jump (or
  24 m above ground) opens the parachute (`player._skydive_tick`). Respawns
  drop over the most forward owned flag (else land on the base).
- Vehicles: `player.enter_vehicle` hides the player and turns off its
  collision; `vehicle.control()` keeps it in the seat and handles exit;
  the vehicle reads the driver's brain in its own `_physics_process`. The
  view becomes a chase camera (`game._vehicle_camera`); the vehicle aims where
  that camera looks (`vehicle._aim_point`). Vehicle weapons fire normal
  bullets with their own stats (`bullet.setup_stats`, the vehicle's RID
  ignored). Destroyed vehicles respawn at home after 30 s. Bots do not drive.
- Big maps batch static geometry per 40 m chunk (`map._add`) so cameras and
  shadow passes can cull it; the nav grid is 3 m there (`MAPS[].nav_step`).

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

### Smoothness and input latency

**Auto resolution** (`game._auto_resolution`, option `auto_res`): sums the
measured GPU time of every splitscreen viewport; above 14 ms it lowers
`Settings.res_factor` (0.5-1, multiplied into every view's
`scaling_3d_scale`, FSR 1 upscaling), below 62 % of that it climbs back.
The HUD is 2D and stays sharp. **The look** (toy diorama): `map._mat`
pastelises colours, flattens the generated textures (`_soft`), halves the
normal maps and adds a faint rim; soft sun shadows (`shadow_opacity`),
brighter ambient, saturation 1.24, light bloom, and far depth of field on
every camera (`CameraAttributesPractical`, option `dof`).
The lobby warns when the screen runs below 50 Hz (a TV left at 30 Hz is
the usual reason the game "runs badly").

Checklist of what keeps motion smooth (keep it true when changing things):
physics at 120 Hz with engine physics interpolation and jitter fix 0;
cameras are not interpolated nodes, they are placed every rendered frame
from `get_global_transform_interpolated()`; look input is applied per
rendered frame (stick: radial dead zone, 1.6 power curve, ~20 ms smoothing,
turn boost); every teleport calls `reset_physics_interpolation()`; effects
are pre-warmed in `game._prewarm`; and the frame limit defaults to
"Display" (`fps_limit`), because a fixed cap that does not divide the
refresh rate (60 on 144 Hz) was the main source of judder.

### Smoothness and input latency (details)

These choices exist because the game "did not feel smooth at 60":
- **Frame pacing:** a frame limiter fighting V-Sync gives uneven frame times.
  `settings.gd::apply` only sets `Engine.max_fps` when the cap is clearly
  below the display's refresh rate (or V-Sync is off); otherwise V-Sync alone
  paces frames.
- **Physics at 120 Hz** with interpolation on and `physics_jitter_fix = 0`
  (the documented pairing). Interpolation shows the previous tick, so 120 Hz
  halves that delay to about 8 ms. All gameplay code is per-second (multiplied
  by delta), so the tick rate can be changed freely.
- **View rotation is not interpolated at all:** `brain.update_look` runs every
  rendered frame and `game.gd` builds the camera from yaw/pitch directly.
- **Swapchain image count 2** and un-accumulated mouse input reduce input lag.
- **Right stick** (`input_source.gd::_stick`): radial dead zone (setting),
  1.6-power response curve, and a turn boost after holding the stick hard
  over for a moment.
Measured on an RTX 2070 at 1080p with six views: about 190 FPS uncapped on
average; momentary dips happen when several players are on the (blurred) card
screen at once.

### Abilities (`player.gd`, `input_source.gd`)

- **Block:** `block_left` (0.38 s window) and `block_cd` (`stats.block_cooldown`).
  `take_damage` returns 0 while blocking. Every tick each bullet checks whether
  its path passes within `BLOCK_RADIUS` (1.1 m) of a blocking enemy's chest;
  if so `bullet.gd::_reflect` hands it to the blocker and sends it back at the
  shooter – bullets, rockets, grenades, bubbles and flames alike. Cards hook in
  via `_blocked()` (heal, shockwave). A blocked zombie is shoved back.
- **Crouch / slide:** B (held) on a gamepad, C / Ctrl on the keyboard; pressed
  while running it becomes a slide. R3 / F performs melee. Dash is RB / L3,
  block is LB / Q.
- **Aim down sights:** `aim_amount` (0–1, smoothed). It narrows the camera FOV
  by `stats.zoom` (`game.gd::_update_cameras`), scales look sensitivity
  (`zoom_factor`), tightens spread, slows movement, and slides the gun to the
  screen centre (`viewmodel.gd`, `HIP` → `ADS`). Weapons with `zoom < 0.5`
  (Rail) hide the gun and draw a scope in `hud.gd`.
- **Interact:** a weapon pad sets `player.near_pickup` every tick for players
  standing on it; the player shows `pickup_prompt` and calls `pad.take()` when
  the interact button is pressed. Health pads stay automatic. Bots take a
  weapon automatically while they still hold the Blaster.
- **First-person motion:** `bob_phase`, `bob_amount`, `strafe_amount`,
  `fall_amount`, `land_dip`, `recoil` are smoothed on the player and consumed
  by the camera (head bob, strafe roll, recoil kick) and by `viewmodel.gd`
  (figure-of-eight bob, look sway, jump/fall inertia, guard pose). The "View
  bob and sway" option scales the walking part.

### Maps and themes (`map.gd`)

`MAPS` pairs a layout function (`_layout_yard`, `_layout_pit`, `_layout_frost`)
with a `THEMES` entry. A theme's `mats` maps each material key to
`[colour, texture kind, tiles per metre, roughness, metallic]`; the theme also
holds two neon accents, sky shader parameters, moon/sun, fog, backdrop
scenery (`city`, `rocks`, `ice`) and the drifting motes.

Texture kinds are generated once per session by the static `map.gd::_tex`
(greyscale albedo + normal map, emission for lava): concrete, plates,
corrugated metal, planks, bricks, tiles, Voronoi rock, glowing lava cracks,
snow, cracked ice, hazard stripes. Shipping-container and crate materials use
object-space mapping so their ribs stay aligned when rotated.

Map-specific pieces: `_container()` (shipping container with end frames),
`_sign()` (neon wall sign + light), `_cyl()` (round structures), `_lava()`
(burning channel behind a kerb; damage in `_physics_process`, bots kept out
by the kerb failing the nav link test), `_pine()`. `_glow()` adds shadowless
coloured point lights. The bot nav graph is generated per map with no extra
data.

### Map toolkit (`map.gd`)

- **Batching:** `_add(mesh, material, transform)` queues static geometry;
  `_flush()` merges everything per material into one MeshInstance at the end
  of `build()`. Use `_box` / `_visual` / `_cyl` / `_rod` / `_ball` for static
  pieces; only animated things (pad rings) and lights are separate nodes.
- **Ground holes:** `_hole(rect)` cuts the ground slab, which is built after
  the layout (`_build_floor`). `_surface()` decals (roads, paths) are split
  around holes that exist when they are called, so cut holes first.
- **Pieces:** `_wall_x` / `_wall_z` (walls with door/window openings),
  `_stairs` (hidden ramp + drawn steps), `_slab` (floor with holes),
  `_building` (multi-storey with stairs, flat roof terrace or `_gable` roof),
  `_tunnel` (underground passage with ramps at both ends), `_basement`
  (room below ground), `_tree` / `_bush` (noise-displaced leaf clusters),
  `_pine`, `_lamp_post`, `_container`, `_sign`, `_lava`, `_jump_pad`,
  `_lawn` (grass area) and `no_grass` (rects kept clear).
- **Time of day:** `_build_environment` picks night (theme values) or the
  DAY / SUNSET presets plus theme overrides. It sets `light_scale` (point
  lights), `neon_scale` (emission) and `night_amount` (windows, street lamps,
  floodlights) which the builders read. Indoor lights divide by light_scale so
  they stay on in daylight.
- **Weather:** disabled. Matches keep clear conditions and vary only by time
  of day; large outdoor arenas retain a subtle depth haze.

### Parkour, jetpack, scopes (`player.gd`, `viewmodel.gd`, `game.gd`)

- **Wall run:** `_find_wall` ray-casts left and right from the chest. While
  airborne, moving forward and fast enough, the player sticks to the wall for
  up to `stats.wallrun_time`, gravity is replaced by a slow sink, and jumping
  pushes off the wall (and refreshes air jumps). The same wall cannot be
  re-run immediately. `wall_side` / `wall_tilt` roll the camera and gun.
- **Slide:** crouch while running on the ground: a speed boost that decays,
  steerable a little; the capsule shrinks (`_set_crouch`) and the camera
  drops via `crouch_amount`. Jumping out of a slide keeps the speed. Air
  movement no longer bleeds speed, so slide hops and wall jumps carry.
- **Mantle:** `_find_ledge` looks for a ledge 0.4-2.0 m above the feet just
  ahead with headroom on top, and gives a vault impulse.
- **Jetpack (card):** `stats.jetpack` seconds of fuel; holding jump in the
  air after 0.18 s thrusts upward. Refuels on the ground. The character shows
  canisters and flames (`character.set_jetpack`); the HUD shows a fuel arc.
- **Scopes (cards):** `stats.scope` > 1 gives the gun a scope whose lens shows
  a live picture: `game.gd::_ensure_scope` creates a 384 px SubViewport with
  a camera that copies the player's camera at `fov / scope`; it only renders
  while aiming. `viewmodel.gd` puts that texture on the lens with a reticle
  shader and moves the gun so the lens is centred when aiming. `red_dot`
  draws a holographic sight. Weapons with `zoom < 0.5` (Rail) keep their
  full-screen scope instead.
- **Weapon feel:** each weapon style has its own shot sound
  (`sfx.gd` "shot_<style>") and fire animation (`viewmodel.gd` match on
  `_style`, driven by `player.shot_t`). Bullet effects add a sound layer
  (`_attribute_sound`) and tint bullets, trails and muzzle flashes
  (`attr_color`: frost blue, toxic green, explosive orange, homing pink).
- **Crosshair:** a circle whose radius is the current spread projected with
  the camera FOV (`hud.gd`), shrinking when aiming, hidden behind scopes.

### Character customisation

A look is `{kind, color, hat, face}`. The lobby edits one per seat and stores
them in `Settings.lobby` (saved in the settings file as `seat0`…`seat5`).
`character.gd::_build_hat` / `_build_face` build the accessories; names live
in `ui_kit.gd` (`HAT_NAMES`, `FACE_NAMES`, `COLOR_NAMES`). The winner on the
podium always wears the crown. Two humans can never pick the same colour.

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

### Music (`sfx.gd`)

Each song is a `TRACKS` entry: tempo, four two-bar chords, and a style per
part (bass: funk / drive / pump / slap; chords: stab / arp / bell; drums:
funk / four / hard / half; lead level and pad level). `lobby` is laid-back
funk; `map0` driving synthwave (Neon Yard); `map1` fast and aggressive (Ember
Pit); `map2` half-time funk with bells (Frost Line). `game.gd` plays
`"map%d"` for the current map. Tracks render in a worker thread; the one
currently wanted is rendered first. Voices: filtered saw bass with an
envelope "wow", plucked saw, detuned-saw pad, pulse lead with echo, kick,
snare and hats, with side-chain pumping on the chords.

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
- Zombies: waves spawn, zombies path to and attack the squad, waves clear,
  everyone picks a card between waves, the dead come back, a wiped squad ends
  the match with "SURVIVED N WAVES".
- Frontline: teams fill to 6 v 6, parachute drops, flag captures and ticket
  bleed, buggy / tank / helicopter driven by a bot with the chase camera and
  vehicle HUD, a match ending with "BLUE WINS!". Six views about 86 FPS
  uncapped (four views about 100).
- Gun models render in first and third person for all 12 weapons.
- With the imported models: every map and mode runs without script errors;
  six views uncapped: 165-205 FPS on the arena maps, 129 Suburb, 100
  Frontline. Zombies walk, run, punch, flinch and fall with their animations.
- Lobby, Options screen, matches on all six maps in day, sunset and night,
  rain/fog/snow, card picker, pause menu and victory podium render with no
  script errors. The live scope lens shows a correct magnified view.
- Six-view uncapped FPS: about 120 (Suburb, rain), 135 (Stadium, night),
  165-185 (Neon Yard, Frost Line).
- 6-way splitscreen with vsync off and no frame cap: roughly 190 FPS on the
  High preset.
- A settings file is read and applied (Low preset, wide FOV, hard bots).
- Bots fight, die, pick cards, respawn; a match reaches the kill target, shows
  the podium and returns to the lobby.
- The exported `build\SlopGame.exe` starts and plays.

**Not verified:**
- v0.12 (melee, taunts, magic and medieval weapons, Gun Game, Medieval,
  the Castle, doors, breakables, crumbling walls, arm IK) was exercised by
  bots and screenshots only. Nobody has held a pad: taunt camera feel,
  door prompts, melee timing and all the new balance numbers are guesses.
- The tank and helicopter are still hand-built (no suitable CC0 model with
  a separate turret / rotor was found).
- Everything added in v0.10 was only exercised by bots: nobody has kicked a
  chair, petted a dog, used a block perk or played a human character by hand.
  The new weapon and card numbers are first guesses.
- Vehicles have only been driven by bots (who steer like they walk): handling,
  turret speed and weapon numbers in `vehicle.gd` are first guesses. Bots never
  get into vehicles themselves.
- Zombies and Frontline balance (wave growth, ticket counts, flag speed).
- Whether it now *feels* smooth: the pacing and latency changes are sound in
  principle but were made on a 30 Hz remote display with no controller, so
  nobody has felt them.
- Wall running, sliding, mantling and the jetpack have not been played by a
  human (bots do not use them); the numbers are first guesses.
- Block, aim down sights and the pick-up button were only exercised by bots
  (block, pickups) or a forced-aim screenshot; no human has pressed them.
- Weapon balance. Every weapon and card runs without errors in bot matches,
  but the numbers in `weapons.gd` and `cards.gd` are first guesses.
- Anything audible, including the new songs: they render without errors
  but nobody has listened to them. The music and sound effects are generated without errors
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
- Possible next steps: more maps, per-player control options and rebinding,
  kill-cam, bots that use vehicles, a Frontline spawn-point chooser, more
  Frontline maps.
