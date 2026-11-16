# Fragdeck

Local splitscreen first-person shooter for 1–6 players on one PC, with three
game modes:

- **Rounds** (default) – free-for-all deathmatch. Every time you die you are
  dealt three random powerup cards and keep one for the rest of the match, so
  whoever is losing keeps getting stronger. First to the kill target wins.
- **Zombies** – co-op survival. Your squad (plus optional CPU allies) holds out
  against endless, ever-growing waves of walkers, runners, brutes and a boss
  every fifth wave. Everyone picks a powerup between waves; fallen players
  return when the wave is cleared. It lasts until the whole squad is down.
- **Frontline** – Battlefield-inspired team war on a huge 200 × 140 m map:
  blue vs orange (humans split between the teams, or all together against
  the CPU), conquest flags A/B/C, tickets, parachute drops, a town with
  four-storey towers, warehouses, bunkers and trenches, and vehicles –
  buggies, tanks and helicopters.

You play as a customisable plush animal in dark, neon-lit arenas (the look is
inspired by ROUNDS).

- **12 weapons** that look like real guns (carbine, pump shotgun, revolver,
  bolt-action sniper, rocket launcher, minigun...), each with its own sound and
  firing animation: Blaster,
  Scatter, Zapper, Boomer, Rail, Lobber, Bubbler, Tripler, Magnum, Spinner,
  Pinball and Flamer. Get them from weapon cards or by pressing the pick-up
  button on a purple weapon pad; your powerups carry over.
- **49 powerup cards** in three rarities, including live-magnifying 2x/4x
  scopes, a red-dot sight and a jetpack.
- **Movement inspired by Titanfall:** crouch, sliding (crouch while running),
  wall running, wall jumps and mantling onto ledges, plus dash and aim down
  sights.
- **Block** catches and reflects every bullet, rocket, grenade, bubble and
  flame that comes near you back at whoever fired it.
- **6 arena maps** for Rounds and Zombies: Neon Yard, Ember Pit, Frost Line, and three based on real
  places: a **Museum** (indoor, balconies, vaults), a **Stadium** (pitch,
  bleachers, floodlights, locker rooms) and a **Suburb** (houses with stairs,
  yards, pools, a treehouse, a storm drain). Two-storey buildings, tunnels and
  basements on every outdoor map.
- **Time of day and weather:** each match is day, sunset or night (or pick
  one in the lobby), with random clear / rain / fog / snow weather.
- **Character customisation:** animal, colour, hat and face per player,
  remembered between sessions.

Built with [Godot 4.7.2](https://godotengine.org) (MIT licensed), 100% GDScript.
The maps, characters, textures, icons, sounds and music are all generated in code; the
only bundled asset is the Fredoka UI font (SIL Open Font License, see
`fonts/OFL.txt`).

## Play

Double-click **`Play.bat`**. It runs `build\Fragdeck.exe` if it exists,
otherwise it runs the project from source with the bundled engine.

In the lobby each player presses **A** on their own gamepad to take a seat
(Space joins a keyboard + mouse player). Up/down picks what to customise
(animal, colour, hat, face) and left/right changes it.

| Lobby | Gamepad | Keyboard |
|---|---|---|
| Join / leave | A / B | Space / Backspace |
| Customise | D-pad or left stick | WASD or arrows |
| Game mode (Rounds / Zombies / Frontline) | RT | G |
| Bots (Zombies: CPU allies; Frontline: teams versus / co-op) | Y | B |
| Kill target (Frontline: tickets) | X | K |
| Next map (Rounds and Zombies) | RB | M |
| Time of day | LB | T |
| Options | Back / Select | O |
| Start | Start | Enter |

| In a match | Gamepad | Keyboard + mouse |
|---|---|---|
| Move | Left stick | WASD |
| Look | Right stick (with aim assist) | Mouse |
| Fire | RT | Left click |
| Aim down sights | LT (hold) | Right click (hold) |
| Jump (hold with jetpack) | A | Space |
| Crouch (hold) / slide (while running) | B or right-stick click | C or Ctrl |
| Dash | RB or left-stick click | Shift |
| Block | LB | Q |
| Reload | X | R |
| Pick up weapon / get in or out of a vehicle | Y | E |
| Open parachute (Frontline drop) | A | Space |
| Wall run | Jump at a wall and keep moving forward | same |
| Mantle | Move forward into a ledge in the air | same |
| Pick a card | D-pad / stick left-right, A to confirm | A / D, Space to confirm |

| In a vehicle | Gamepad | Keyboard + mouse |
|---|---|---|
| Drive / fly | Left stick | WASD |
| Aim the turret / guns | Right stick | Mouse |
| Main weapon (MG, tank cannon, nose gun) | RT | Left click |
| Second weapon (tank MG, helicopter rockets) or zoom | LT | Right click |
| Helicopter up / down | A / B | Space / C |
| Get out (bail out of a helicopter = parachute) | Y | E |
| Pause / options / quit to lobby | Start | Esc |
| Toggle fullscreen (lobby) | – | F11 |

### Options

Reachable from the lobby and from the pause menu:

- **Display:** fullscreen, V-Sync, frame rate limit (60 by default; with V-Sync
  on a 60 Hz display the limiter steps aside so V-Sync alone paces frames).
- **Graphics:** quality preset (Low to Ultra), anti-aliasing (Off, FXAA,
  MSAA 2x/4x/8x), render scale, shadows, ambient occlusion, bloom, scenery.
- **Audio:** master, music and effects volume.
- **Controls:** gamepad and mouse look speed, stick dead zone, invert Y, aim
  assist, rumble.
- **Gameplay:** field of view, screen shake, view bob and sway, damage numbers,
  bot difficulty.

Options are saved in `fragdeck_settings.cfg` beside the game executable.

Up to six gamepads are supported; one of the six seats can be keyboard + mouse
instead. Screen layout: 1 player full screen, 2 stacked, 3–4 in a 2×2 grid,
5–6 in a 3×2 grid. Unused cells show a spectator camera and the scoreboard.

## Folder layout / portability

The whole game is this one folder. Copy it to a USB stick or another PC and it
runs; nothing is installed and nothing is written outside it.

```
Play.bat / Edit.bat   launchers (game / Godot editor)
project.godot         Godot project file
main.tscn             the only scene; everything else is built in code
scripts/              all game code (see docs/ARCHITECTURE.md)
fonts/                Fredoka UI font + its licence
docs/                 architecture + handoff notes
tools/                build.bat, setup_engine.ps1
engine/               bundled Godot editor + export templates  (not in git)
build/Fragdeck.exe    standalone single-file game              (not in git)
```

`build\Fragdeck.exe` on its own is also fully portable: it is a single file
with the game data embedded.

### Restoring from GitHub

`engine/` and `build/` are too large for git (each file is over GitHub's 100 MB
limit). After cloning:

```
powershell -ExecutionPolicy Bypass -File tools\setup_engine.ps1 -Templates
tools\build.bat
```

The first command re-downloads Godot 4.7.2 into `engine/`; the second
re-exports `build\Fragdeck.exe`. A ready-made build is also attached to the
repository's GitHub Releases.

## Developing

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how everything works and
how to add cards, change the map, or test without controllers.
