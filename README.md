# Slop Game

*(formerly Fragdeck: the repository, the project folder and the settings file keep the old name.)*

Local splitscreen first-person shooter for 1–6 players on one PC, with five
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
- **Gun Game** – free-for-all where every KO hands you the next weapon on a
  ladder of all 31 (guns, then magic, then medieval arms, ending on the
  Sword). Being finished off with a punch knocks you one rung down. First to
  score with the last weapon wins. No cards, quick respawns.
- **Medieval** – a free-for-all in the **Castle** with medieval arms only:
  Sword, Battle Axe, Spear, Longbow, Crossbow, Throwing Knives and Powder
  Bombs. Your block is a shield (it lasts longer and returns sooner), and
  cards and weapon pads only deal medieval weapons.

You play as one of seven customisable, rigged animal characters in stylised
arenas with readable colour and atmosphere at every time of day.

- **Melee with anything in hand:** click the right stick (or F) for a punch
  that also smashes props, doors and crumbling walls. Eight melee cards
  upgrade it (Brass Knuckles, Backstab, Haymaker, Parry, Bloodthirst, Bull
  Rush...). Swords, axes and spears swing on the fire button and cleave
  everyone in reach; every on-hit card (poison, frost, knockback, chain
  lightning, lifesteal...) works on melee hits too.
- **Magic:** Fire Hands (mage hands hurling fireballs), Frost Hands, the
  Storm Staff (chain lightning) and the Arcane Staff (seeking missiles).
  They are ordinary weapons under the hood, so every card works on them.
- **Taunts:** four per player on the D-pad (keys 1–4): Wave, Dance, Nope and
  Flex. Your camera pulls out so you can watch yourself; everyone else sees
  the emote and a speech bubble.
- **A world you can break:** doors open and close (Y / E; bots and zombies
  open them themselves) and splinter when shot; chairs, crates, TVs and
  barrels break apart; red fuel barrels and gas cans explode; ruined wall
  stubs and the castle's bricked-up breach crumble brick by brick under
  fire.
- **Characters hold what they carry:** both hands reach the weapon (arm IK
  on top of the walk, run, jump and crouch animations).
- **A lived-in world:** furnished houses, loose physics props you can kick
  and shoot around (chairs, tables, books, boxes, bottles), window glass that
  shatters, dense forests, camps, sidewalks and crossings. Props never block
  you.
- **Pets:** dogs, cats, a fox and a bunny wander every map. Walk up and press
  the pick-up button to pet one (it heals you a little).
- **Seven selectable animals:** Bunny, Frog, Dino, Bird, Yeti, Fish and
  Monkroose. Each uses the imported creature rig and animations, with colour,
  hat and face customisation.
- **31 weapons**: 20 guns (including Tesla, Cluster, Vortex, Ripper, Sticky,
  Longshot, Frostbite and the akimbo Twins), 4 magic weapons and 7 medieval
  ones.
- **77 powerup cards**, among them block perks that turn your block into a
  weapon (Blink Guard, Frost Guard, Radiant Guard, Echo Guard, Empower...)
  and oddities like Tiny, Giant, Goomba Stomp, Ground Slam, Buddy Drone and
  Chain Reaction.
- The original 12 weapons look like real guns (carbine, pump shotgun, revolver,
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
- **6 arena maps** for Rounds: Neon Yard, Ember Pit, Frost Line, and three based on real
  places: a **Museum** (indoor, balconies, vaults), a **Stadium** (pitch,
  bleachers, floodlights, locker rooms) and a **Suburb** (houses with stairs,
  yards, pools, a treehouse, a storm drain). Two-storey buildings, tunnels and
  basements on every outdoor map.
- **Quarantine**, a dedicated large Zombies map with a multi-floor hospital,
  annex, warehouse, motel, fenced campus, service roads, wooded edges, utility
  tunnel and underground triage room. Red emergency beacons and blood effects
  give it a scarier tone while keeping the spaces readable.
- **Time of day:** each match is day, sunset or night (or pick one in the
  lobby). Weather stays clear; large outdoor maps use a light distance haze.
- **Castle**, a seventh arena (and Medieval mode's home): curtain walls you
  can walk on, towers, gatehouses with gates you can open or smash, a
  three-storey keep, a market courtyard and a siege camp outside.
- **Character customisation:** animal, colour, hat, back accessory and your
  own **look speed** (LOOK, 1–10) per player, remembered between sessions.

Built with [Godot 4.7.2](https://godotengine.org) (MIT licensed), 100% GDScript.
The map layouts, textures, icons, sounds and music are generated in code.
Characters, weapons, zombies, cars, trees, furniture, doors and castle
pieces are public-domain (CC0) 3D models by Quaternius, Kenney and Kay
Lousberg. **[ASSETS.md](ASSETS.md) lists every asset, its author, licence
and download source**; `THIRD_PARTY_LICENSES.txt` carries the notices that
ship with the game. The UI font is Fredoka (SIL Open Font License).

## Play

Double-click **`Play.bat`**. It runs `build\SlopGame.exe` if it exists,
otherwise it runs the project from source with the bundled engine.

In the lobby each player presses **A** on their own gamepad to take a seat
(Space joins a keyboard + mouse player). Up/down picks what to customise
(animal, colour, hat, back, look speed) and left/right changes it.

| Lobby | Gamepad | Keyboard |
|---|---|---|
| Join / leave | A / B | Space / Backspace |
| Customise | D-pad or left stick | WASD or arrows |
| Game mode (Rounds / Zombies / Frontline / Gun Game / Medieval) | RT | G |
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
| Crouch (hold) / slide (while running) | B | C or Ctrl |
| Melee (punch, or swing a melee weapon) | Right-stick click | F or middle mouse |
| Taunt (Wave / Dance / Nope / Flex) | D-pad up / right / down / left | 1 / 2 / 3 / 4 |
| Dash | RB or left-stick click | Shift |
| Block | LB | Q |
| Reload | X | R |
| Pick up weapon / open or close a door / get in or out of a vehicle | Y | E |
| Open parachute (Frontline drops and high falls) | A | Space |
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

- **Display:** fullscreen, V-Sync, frame rate limit. The default limit is
  **Display**: frames are paced by your screen's own refresh rate, which is
  the smoothest setting (a fixed 60 on a 120 or 144 Hz screen judders).
- **Graphics:** quality preset (Low to Ultra), anti-aliasing (Off, FXAA,
  MSAA 2x/4x/8x), motion blur slider, render scale, shadows, ambient
  occlusion, bloom, scenery.
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
build/SlopGame.exe    standalone single-file game              (not in git)
```

`build\SlopGame.exe` on its own is also fully portable: it is a single file
with the game data embedded.

### Restoring from GitHub

`engine/` and `build/` are too large for git (each file is over GitHub's 100 MB
limit). After cloning:

```
powershell -ExecutionPolicy Bypass -File tools\setup_engine.ps1 -Templates
tools\build.bat
```

The first command re-downloads Godot 4.7.2 into `engine/`; the second
re-exports `build\SlopGame.exe`. A ready-made build is also attached to the
repository's GitHub Releases.

## Developing

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how everything works and
how to add cards, change the map, or test without controllers.
