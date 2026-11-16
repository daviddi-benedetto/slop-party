extends RefCounted
## Per-player stats. Rebuilt from scratch by player.gd::rebuild_stats():
## defaults (this file) -> the held weapon (weapons.gd) -> every picked card
## (cards.gd), in pick order. Never edit a player's stats object directly; add
## a card or change the weapon instead, or the change is lost on the rebuild.

# --- body ---
var max_health := 100.0
var move_speed := 7.5
var jump_velocity := 8.5
var max_jumps := 1
var gravity_mult := 1.0
var dash_cooldown := 3.0
var dash_invuln := false    # cannot be hurt while dashing
var damage_taken := 1.0
var regen := 0.0            # hp per second, always on
var thorns := 0.0           # fraction of damage taken reflected to the attacker
var shield_cd := 0.0        # > 0: a bubble that blocks one hit, recharging in this many seconds
var second_wind := 0        # lethal hits survived per life
var adrenaline := 0.0       # bonus speed and fire rate while below 40% health
var block_cooldown := 4.0   # seconds between blocks
var block_heal := 0.0       # health restored by a successful block
var block_wave := 0.0       # damage of the shockwave released by a successful block

# --- gun ---
var damage := 24.0
var fire_interval := 0.28
var mag_size := 8
var reload_time := 1.5
var pellets := 1
var spread := 0.006
var recoil_kick := 1.0
var shoot_pitch := 1.0
var burst := 1              # rounds fired per trigger pull
var zoom := 0.72            # FOV multiplier when aiming down sights (lower = more zoom)

# --- bullet ---
var bullet_speed := 55.0
var bullet_gravity := 5.0
var bullet_size := 1.0
var bullet_life := 4.0      # seconds before it fizzles
var bounces := 0
var bounce_bonus := 0.0     # extra damage fraction gained per bounce
var pierce := 0             # players a bullet can pass through
var explosive := 0.0        # blast radius in metres
var fuse := 0.0             # > 0: grenade - bounces around and explodes after this long
var smoke := false          # leaves a smoke trail
var flame := false          # short-lived growing fire puff instead of a bullet
var homing := 0.0           # steering strength (rad/s)

# --- on hit / on KO ---
var lifesteal := 0.0        # fraction of damage dealt returned as health
var poison := 0.0           # fraction of damage dealt again over 3 s
var frost := 0.0            # slow fraction applied to victims
var knockback := 0.0
var overcharge := 0.0       # bonus damage fraction on the last round of a magazine
var giant_slayer := 0.0     # bonus damage fraction against the current leader
var rampage := 0.0          # bonus damage fraction per KO this life (max 5 stacks)
var kill_heal := 0.0
var kill_reload := false

# --- meta ---
var card_draw := 3          # cards offered on death
