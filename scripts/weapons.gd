extends RefCounted
## The weapon list. A weapon is a base profile applied to a fresh stats.gd
## before the player's cards (see player.gd::rebuild_stats), so cards keep
## working with every weapon.
##
## Players get weapons from weapon cards (cards.gd) and from the pickup pads on
## the map (pickup.gd). Index 0 is what everyone starts with.
##
## `look` drives the models: viewmodel.gd (first person) and character.gd
## (third person) read "style", and "tp" = [radius, length] of the simple
## third-person barrel.
##
## To add a weapon: append an entry here, add a branch for its style in
## viewmodel.gd::_build_gun (or reuse a style), and add a weapon card in
## cards.gd if it should appear in the deck.

const LIST := [
	{"name": "Blaster", "icon": "bolt", "desc": "Reliable all-rounder",
		"style": "blaster", "tp": [0.085, 0.62]},
	{"name": "Scatter", "icon": "boom", "desc": "6 pellets, brutal up close\nshort range",
		"style": "scatter", "tp": [0.12, 0.5]},
	{"name": "Zapper", "icon": "bolt", "desc": "Very fast fire, big magazine\nlow damage per hit",
		"style": "zapper", "tp": [0.06, 0.7]},
	{"name": "Boomer", "icon": "boom", "desc": "Slow rockets that explode\n2 per magazine",
		"style": "boomer", "tp": [0.14, 0.8]},
	{"name": "Rail", "icon": "target", "desc": "Instant, piercing, huge damage\nslow to fire",
		"style": "rail", "tp": [0.05, 0.95]},
	{"name": "Lobber", "icon": "bounce", "desc": "Bouncing grenades\non a short fuse",
		"style": "lobber", "tp": [0.13, 0.45]},
	{"name": "Bubbler", "icon": "drop", "desc": "Slow bubbles that\nchase enemies",
		"style": "bubbler", "tp": [0.11, 0.5]},
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
