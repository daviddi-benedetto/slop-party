extends RefCounted
## The weapon list. A weapon is a base profile applied to a fresh stats.gd
## before the player's cards (see player.gd::rebuild_stats), so cards keep
## working with every weapon.
##
## Players get weapons from weapon cards (cards.gd) and from the pickup pads on
## the map (pickup.gd). Index 0 is what everyone starts with.
##
## `style` selects the model in viewmodel.gd::_build_gun; "tp" = [radius,
## length] of the simple third-person barrel in character.gd.
##
## To add a weapon: append an entry here, add its profile in apply(), add a
## branch for its style in viewmodel.gd::_build_gun (or reuse a style). Its
## weapon card and pickup appear automatically.

const LIST := [
	{"name": "Blaster", "icon": "bolt", "desc": "Reliable all-rounder",
		"style": "blaster", "tp": [0.085, 0.62]},
	{"name": "Scatter", "icon": "boom", "desc": "6 pellets, brutal up close\nshort range",
		"style": "scatter", "tp": [0.12, 0.5]},
	{"name": "Zapper", "icon": "bolt", "desc": "Very fast fire, big magazine\nlow damage per hit",
		"style": "zapper", "tp": [0.06, 0.7]},
	{"name": "Boomer", "icon": "boom", "desc": "Slow rockets that explode\n2 per magazine",
		"style": "boomer", "tp": [0.14, 0.8]},
	{"name": "Rail", "icon": "target", "desc": "Instant, piercing, huge damage\nscoped, slow to fire",
		"style": "rail", "tp": [0.05, 0.95]},
	{"name": "Lobber", "icon": "bounce", "desc": "Bouncing grenades\non a short fuse",
		"style": "lobber", "tp": [0.13, 0.45]},
	{"name": "Bubbler", "icon": "drop", "desc": "Slow bubbles that\nchase enemies",
		"style": "bubbler", "tp": [0.11, 0.5]},
	{"name": "Tripler", "icon": "ammo", "desc": "Accurate 3-round bursts",
		"style": "burst", "tp": [0.07, 0.8]},
	{"name": "Magnum", "icon": "star", "desc": "Six heavy, precise shots\nbig kick",
		"style": "magnum", "tp": [0.09, 0.42]},
	{"name": "Spinner", "icon": "bolt", "desc": "Huge magazine, wild spray\nslows you down",
		"style": "spinner", "tp": [0.13, 0.75]},
	{"name": "Pinball", "icon": "bounce", "desc": "Shots ricochet 4 times\nand hit harder each bounce",
		"style": "pinball", "tp": [0.11, 0.5]},
	{"name": "Flamer", "icon": "drop", "desc": "Short-range burning stream",
		"style": "flamer", "tp": [0.1, 0.6]},
]


static func apply(id: int, s) -> void:
	match id:
		1:  # Scatter
			s.pellets = 6
			s.damage = 9.0
			s.spread = 0.055
			s.fire_interval = 0.8
			s.mag_size = 4
			s.reload_time = 1.7
			s.bullet_speed = 50.0
			s.bullet_life = 0.55
			s.recoil_kick = 2.2
			s.shoot_pitch = 0.7
			s.zoom = 0.85
		2:  # Zapper
			s.damage = 10.0
			s.fire_interval = 0.085
			s.mag_size = 28
			s.spread = 0.022
			s.reload_time = 1.7
			s.bullet_speed = 70.0
			s.recoil_kick = 0.5
			s.shoot_pitch = 1.5
		3:  # Boomer
			s.damage = 60.0
			s.explosive = 3.6
			s.fire_interval = 1.0
			s.mag_size = 2
			s.reload_time = 2.1
			s.bullet_speed = 30.0
			s.bullet_gravity = 0.0
			s.bullet_size = 2.4
			s.smoke = true
			s.recoil_kick = 2.6
			s.shoot_pitch = 0.5
		4:  # Rail
			s.damage = 75.0
			s.fire_interval = 1.15
			s.mag_size = 3
			s.reload_time = 2.0
			s.bullet_speed = 200.0
			s.bullet_gravity = 0.0
			s.spread = 0.0
			s.bullet_size = 0.8
			s.pierce = 1
			s.recoil_kick = 2.4
			s.shoot_pitch = 1.8
			s.zoom = 0.36
		5:  # Lobber
			s.damage = 50.0
			s.explosive = 3.2
			s.fuse = 1.6
			s.fire_interval = 0.75
			s.mag_size = 4
			s.reload_time = 1.9
			s.bullet_speed = 24.0
			s.bullet_gravity = 15.0
			s.bullet_size = 2.2
			s.recoil_kick = 1.8
			s.shoot_pitch = 0.6
		6:  # Bubbler
			s.damage = 15.0
			s.homing = 2.6
			s.bullet_speed = 20.0
			s.bullet_gravity = 0.0
			s.bullet_size = 2.6
			s.bullet_life = 3.0
			s.fire_interval = 0.2
			s.mag_size = 14
			s.reload_time = 1.6
			s.recoil_kick = 0.6
			s.shoot_pitch = 1.25
		7:  # Tripler
			s.damage = 17.0
			s.burst = 3
			s.fire_interval = 0.5
			s.mag_size = 15
			s.spread = 0.004
			s.reload_time = 1.6
			s.bullet_speed = 85.0
			s.bullet_gravity = 2.0
			s.recoil_kick = 0.8
			s.shoot_pitch = 1.3
			s.zoom = 0.62
		8:  # Magnum
			s.damage = 46.0
			s.fire_interval = 0.5
			s.mag_size = 6
			s.spread = 0.0
			s.reload_time = 1.8
			s.bullet_speed = 110.0
			s.bullet_gravity = 1.0
			s.bullet_size = 1.3
			s.knockback = 4.0
			s.recoil_kick = 3.0
			s.shoot_pitch = 0.62
			s.zoom = 0.68
		9:  # Spinner
			s.damage = 7.5
			s.fire_interval = 0.05
			s.mag_size = 70
			s.spread = 0.045
			s.reload_time = 2.6
			s.bullet_speed = 75.0
			s.move_speed *= 0.85
			s.recoil_kick = 0.45
			s.shoot_pitch = 1.1
			s.zoom = 0.85
		10:  # Pinball
			s.damage = 20.0
			s.bounces = 4
			s.bounce_bonus = 0.35
			s.fire_interval = 0.34
			s.mag_size = 8
			s.bullet_speed = 62.0
			s.bullet_gravity = 0.0
			s.bullet_size = 1.6
			s.bullet_life = 5.0
			s.recoil_kick = 1.2
			s.shoot_pitch = 1.6
		11:  # Flamer
			s.damage = 4.5
			s.poison = 0.8
			s.fire_interval = 0.04
			s.mag_size = 90
			s.spread = 0.07
			s.reload_time = 2.2
			s.bullet_speed = 26.0
			s.bullet_gravity = -2.0
			s.bullet_size = 2.4
			s.bullet_life = 0.42
			s.flame = true
			s.recoil_kick = 0.25
			s.shoot_pitch = 0.45
			s.zoom = 0.9
