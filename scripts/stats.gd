extends RefCounted
## Per-player stats. Rebuilt from scratch by player.gd::rebuild_stats():
## defaults (this file) -> the held weapon (weapons.gd) -> every picked card
## (cards.gd), in pick order. Never edit a player's stats object directly; add
## a card or change the weapon instead, or the change is lost on the rebuild.

# --- body ---
var max_health := 100.0
var move_speed := 7.5
var jump_velocity := 9.6     # about 2.1 m high
var max_jumps := 2           # everyone can double jump; the card adds a third
var sprint_mult := 1.45      # run speed while sprinting (left-stick click / Shift)
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
var wallrun_time := 1.4     # longest wall run in seconds
var slide_boost := 1.0      # slide speed multiplier
var jetpack := 0.0          # jetpack fuel in seconds (0 = no jetpack)

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
var scope := 0.0            # > 1: a scope with this magnification (rendered live in the lens)
var red_dot := false        # holographic red-dot sight
var ads_spread := 0.3       # spread multiplier when aiming

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

# --- special bullets (new weapons / cards; see bullet.gd) ---
var chain := 0              # hits arc lightning to this many nearby enemies (50% damage)
var cluster := 0            # explodes into this many bomblets
var vortex := 0.0           # pull strength: drags enemies towards the projectile
var sticky := false         # sticks to what it hits, explodes after a second
var range_bonus := 0.0      # extra damage fraction at 40 m and beyond
var frag := 0               # splits into this many fragments on hitting a wall

# --- body / movement perks ---
var size := 1.0             # body scale (Giant / Tiny)
var stomp := 0.0            # damage for landing on someone's head
var slam := 0.0             # crouch in the air: dive, shockwave of this damage on landing
var martyr := 0.0           # blast radius of the explosion you leave when KO'd
var corpse_bomb := 0.0      # blast radius of enemies you KO
var drone := 0              # buddy drones that shoot at nearby enemies
var speed_dmg := 0.0        # bonus damage fraction at full sprint
var air_dmg := 0.0          # bonus damage fraction while airborne

# --- block perks (triggered when the block starts; see player._on_block) ---
var block_time := 1.0       # block duration multiplier
var block_empower := 0.0    # next shot after a block: bonus damage fraction
var block_blink := 0.0      # teleport this many metres on block
var block_frost := 0.0      # freeze radius on block
var block_burst := 0        # bullets fired in a ring on block
var block_pull := 0.0       # radius: drag enemies towards you on block
var block_echo := false     # block triggers a second time shortly after
var block_reload := false   # blocking reloads your weapon

# --- melee (R3 / F with any weapon; see player._melee_start) ---
var melee_damage := 45.0    # the punch / gun-butt everyone has
var melee_cd := 0.7
var melee_reach := 1.0      # reach multiplier of the basic melee
var melee_backstab := 0.0   # bonus damage fraction when hitting from behind
var melee_knock := 0.0      # extra knockback of melee hits
var melee_parry := false    # a swing bats projectiles back for a moment
var melee_heal := 0.0       # health gained by a melee KO
var melee_charge := 0.0     # lunge speed added to a swing
# Melee weapons (sword, axe, spear): fire swings instead of shooting.
var melee_weapon := false
var melee_range := 2.6
var melee_arc := 0.9        # half angle of the swing in radians

# --- looks (bullet.gd / player.gd) ---
var projectile := ""        # model flown instead of a glowing bullet: arrow, bolt, knife, bomb
var bolt := false           # draw a lightning bolt from the muzzle to the aim point

# --- meta ---
var card_draw := 3          # cards offered on death
