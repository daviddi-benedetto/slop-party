# Recorded sound effects

Every sound effect in the game is synthesised at startup (`scripts/sfx.gd`).
A recording dropped in this folder replaces the synthesised sound of the
same name. Use `<name>.ogg` (or `.wav` / `.mp3`) for one take, or
`<name>_1.ogg`, `<name>_2.ogg`, ... for several takes that are picked at
random each time (good for footsteps, hits and gunshots).

Only use CC0 or similarly free sounds, and list each file in `ASSETS.md`.

| Name | When it plays |
|---|---|
| `shoot` | default gunshot (rifles, pistols) |
| `shot_blaster`, `shot_burst`, `shot_magnum`, `shot_scatter`, `shot_rail`, `shot_zapper`, `shot_spinner`, `shot_pinball`, `shot_bubbler`, `shot_boomer`, `shot_lobber`, `shot_flamer`, `shot_bomb` | that weapon's shot |
| `shot_bow`, `shot_crossbow`, `shot_knives` | medieval ranged weapons |
| `shot_hands_fire`, `shot_hands_frost`, `shot_staff_arcane`, `shot_staff_storm` | magic |
| `swing`, `slash` | melee swing / blade hit |
| `hit` | your shot landed (heard by the shooter) |
| `hurt` | someone took damage |
| `pop` | knockout |
| `block` | a hit blocked or reflected |
| `reload` | reloading |
| `jump`, `land`, `step`, `dash`, `slide` | movement |
| `boom`, `mod_boom`, `cannon` | explosions, tank cannon |
| `bounce`, `zap`, `thunder` | shields, electricity |
| `mod_ice`, `mod_pierce`, `mod_seek`, `mod_toxic` | bullet powerups |
| `glass`, `wood`, `crumble`, `door`, `thump` | breaking things, doors, impacts |
| `pad`, `card`, `join`, `tick`, `count`, `go`, `win`, `lost`, `wave`, `capture` | UI, pickups, countdown, results, Zombies waves, Frontline flags |
| `engine`, `rotor`, `jet` | vehicles, jetpack |
| `bark`, `meow`, `pet` | pets |
| `zombie` | zombie groan |
| `taunt0` .. `taunt3` | the four taunts |
