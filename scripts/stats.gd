extends RefCounted
## Per-player stats. Every powerup card mutates one of these.

var max_health := 100.0
var move_speed := 7.5
var jump_velocity := 8.5
var max_jumps := 1
var damage := 24.0
var fire_interval := 0.28
var mag_size := 8
var reload_time := 1.5
var bullet_speed := 55.0
var bullet_gravity := 5.0
var bullet_size := 1.0
var pellets := 1
var spread := 0.006
var bounces := 0
var explosive := 0.0      # blast radius in metres
var homing := 0.0         # steering strength (rad/s)
var lifesteal := 0.0      # fraction of damage dealt returned as health
var regen := 0.0          # hp per second, always on
var poison := 0.0         # fraction of damage dealt again over 3 s
var frost := 0.0          # slow fraction applied to victims
var knockback := 0.0
var damage_taken := 1.0
var dash_cooldown := 3.0
