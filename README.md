# Fragdeck

Local splitscreen first-person deathmatch for 1–6 players on one PC. Every time
you die you are dealt three random powerup cards and keep one for the rest of
the match, so whoever is losing keeps getting stronger.

You play as a customisable plush animal in dark, neon-lit arenas (the look is
inspired by ROUNDS).

- **12 weapons:** Blaster, Scatter, Zapper, Boomer, Rail, Lobber, Bubbler,
  Tripler (burst), Magnum, Spinner (minigun), Pinball (ricochet) and Flamer.
  Get them from weapon cards or by pressing the pick-up button on a purple
  weapon pad; your powerups carry over.
- **43 powerup cards** in three rarities.
- **Abilities:** dash, block (a short guard that negates damage and bats
  bullets back at the shooter) and aim down sights.
- **3 maps, each with its own look and song:** Neon Yard (medium night
  container yard with cranes and neon signs), Ember Pit (small sandstone
  foundry with a forge and burning lava channels) and Frost Line (large polar
  outpost with ice walls, lab modules and pines).
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
| Bots | Y | B |
| Kill target | X | K |
| Next map | RB | M |
| Options | Back / Select | O |
| Start | Start | Enter |

| In a match | Gamepad | Keyboard + mouse |
|---|---|---|
| Move | Left stick | WASD |
| Look | Right stick (with aim assist) | Mouse |
| Fire | RT | Left click |
| Aim down sights | LT (hold) | Right click (hold) |
| Jump | A | Space |
| Dash | B or left-stick click | Shift |
| Block | LB or RB | Q |
| Reload | X | R |
| Pick up weapon | Y | E |
| Pick a card | D-pad / stick left-right, A to confirm | A / D, Space to confirm |
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
