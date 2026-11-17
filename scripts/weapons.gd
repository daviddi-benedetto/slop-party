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
## "era" groups weapons: "modern" (default), "magic", "medieval". Medieval
## mode only deals medieval ones (pool()); Gun Game walks ladder().
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
	{"name": "Twins", "icon": "ammo", "desc": "Rapid akimbo pistols
fast reload",
		"style": "twins", "tp": [0.07, 0.4]},
	{"name": "Tesla", "icon": "bolt", "desc": "Bolts arc to two
more enemies nearby",
		"style": "tesla", "tp": [0.09, 0.8]},
	{"name": "Cluster", "icon": "boom", "desc": "A bomb that bursts
into six bomblets",
		"style": "cluster", "tp": [0.13, 0.5]},
	{"name": "Vortex", "icon": "target", "desc": "A slow orb that drags
enemies in, then pops",
		"style": "vortex", "tp": [0.13, 0.5]},
	{"name": "Ripper", "icon": "bounce", "desc": "Saw discs bounce off walls
and cut through enemies",
		"style": "ripper", "tp": [0.1, 0.6]},
	{"name": "Sticky", "icon": "boom", "desc": "Bombs stick to walls
and enemies, then blow",
		"style": "sticky", "tp": [0.1, 0.7]},
	{"name": "Longshot", "icon": "target", "desc": "Hits harder the further
the bolt flies (up to x2.5)",
		"style": "longshot", "tp": [0.05, 0.9]},
	{"name": "Frostbite", "icon": "drop", "desc": "Freezing stream:
slows enemies to a crawl",
		"style": "frost", "tp": [0.09, 0.6]},
	# ---- magic ----
	{"name": "Fire Hands", "icon": "boom", "desc": "Mage hands hurl fireballs\nthat burst and burn",
		"style": "hands_fire", "tp": [0.1, 0.3], "era": "magic"},
	{"name": "Storm Staff", "icon": "bolt", "desc": "Lightning that leaps\nbetween three enemies",
		"style": "staff_storm", "tp": [0.05, 1.2], "era": "magic"},
	{"name": "Frost Hands", "icon": "drop", "desc": "Fans of ice shards\nthat slow what they hit",
		"style": "hands_frost", "tp": [0.1, 0.3], "era": "magic"},
	{"name": "Arcane Staff", "icon": "target", "desc": "Volleys of three seeking\narcane missiles",
		"style": "staff_arcane", "tp": [0.05, 1.2], "era": "magic"},
	# ---- medieval ----
	{"name": "Sword", "icon": "star", "desc": "Fast, wide slashes that\nhit everyone in reach",
		"style": "sword", "tp": [0.05, 1.0], "era": "medieval"},
	{"name": "Throwing Knives", "icon": "ammo", "desc": "Quick thrown blades\nfour to a hand",
		"style": "knives", "tp": [0.04, 0.3], "era": "medieval"},
	{"name": "Longbow", "icon": "target", "desc": "Heavy arrows that hit\nharder at long range",
		"style": "bow", "tp": [0.04, 1.0], "era": "medieval"},
	{"name": "Crossbow", "icon": "target", "desc": "One brutal piercing bolt\nslow to crank",
		"style": "crossbow", "tp": [0.08, 0.8], "era": "medieval"},
	{"name": "Battle Axe", "icon": "skull", "desc": "Slow, crushing swings\nthat send enemies flying",
		"style": "axe", "tp": [0.08, 1.0], "era": "medieval"},
	{"name": "Spear", "icon": "speed", "desc": "Long thrusts that keep\nenemies at a distance",
		"style": "spear", "tp": [0.04, 1.6], "era": "medieval"},
	{"name": "Powder Bomb", "icon": "boom", "desc": "Lit bombs you lob\nover walls",
		"style": "bomb", "tp": [0.14, 0.3], "era": "medieval"},
]


static func era(id: int) -> String:
	return LIST[id].get("era", "modern")


## Weapon ids of one era (or of several: pool(["magic", "medieval"])).
static func pool(eras) -> Array:
	var out: Array = []
	for id in LIST.size():
		if era(id) in eras:
			out.append(id)
	return out


## Gun Game order: guns first, then magic, then the medieval arsenal, ending
## on the Sword (the last KO has to be up close).
static func ladder() -> Array:
	var out: Array = pool(["modern"]) + pool(["magic"])
	var med: Array = pool(["medieval"])
	med.erase(24)
	return out + med + [24]


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
		12:  # Twins
			s.damage = 13.0
			s.fire_interval = 0.105
			s.mag_size = 24
			s.reload_time = 1.1
			s.spread = 0.018
			s.bullet_speed = 80.0
			s.recoil_kick = 0.7
			s.shoot_pitch = 1.35
		13:  # Tesla
			s.damage = 22.0
			s.chain = 2
			s.fire_interval = 0.36
			s.mag_size = 10
			s.reload_time = 1.7
			s.bullet_speed = 95.0
			s.bullet_gravity = 0.0
			s.bullet_size = 1.4
			s.recoil_kick = 1.0
			s.shoot_pitch = 1.7
		14:  # Cluster
			s.damage = 34.0
			s.explosive = 2.6
			s.cluster = 6
			s.fire_interval = 1.1
			s.mag_size = 3
			s.reload_time = 2.2
			s.bullet_speed = 26.0
			s.bullet_gravity = 14.0
			s.bullet_size = 2.6
			s.recoil_kick = 2.2
			s.shoot_pitch = 0.55
		15:  # Vortex
			s.damage = 45.0
			s.explosive = 4.0
			s.vortex = 30.0
			s.fuse = 0.0
			s.fire_interval = 1.4
			s.mag_size = 2
			s.reload_time = 2.4
			s.bullet_speed = 11.0
			s.bullet_gravity = 0.0
			s.bullet_size = 4.0
			s.bullet_life = 2.2
			s.recoil_kick = 2.0
			s.shoot_pitch = 0.4
		16:  # Ripper
			s.damage = 26.0
			s.bounces = 3
			s.pierce = 3
			s.fire_interval = 0.55
			s.mag_size = 6
			s.reload_time = 1.8
			s.bullet_speed = 42.0
			s.bullet_gravity = 0.0
			s.bullet_size = 3.0
			s.bullet_life = 5.0
			s.recoil_kick = 1.4
			s.shoot_pitch = 0.9
		17:  # Sticky
			s.damage = 55.0
			s.explosive = 3.4
			s.sticky = true
			s.fire_interval = 0.6
			s.mag_size = 5
			s.reload_time = 2.0
			s.bullet_speed = 34.0
			s.bullet_gravity = 10.0
			s.bullet_size = 2.0
			s.recoil_kick = 1.5
			s.shoot_pitch = 0.75
		18:  # Longshot
			s.damage = 34.0
			s.range_bonus = 1.5
			s.fire_interval = 0.9
			s.mag_size = 5
			s.reload_time = 1.9
			s.bullet_speed = 150.0
			s.bullet_gravity = 1.5
			s.spread = 0.0
			s.recoil_kick = 2.0
			s.shoot_pitch = 1.5
			s.zoom = 0.5
		19:  # Frostbite
			s.damage = 5.0
			s.frost = 0.6
			s.fire_interval = 0.06
			s.mag_size = 60
			s.reload_time = 2.0
			s.spread = 0.03
			s.bullet_speed = 48.0
			s.bullet_gravity = 0.0
			s.bullet_size = 1.6
			s.bullet_life = 0.7
			s.recoil_kick = 0.3
			s.shoot_pitch = 1.9
			s.zoom = 0.85
		20:  # Fire Hands
			s.damage = 32.0
			s.explosive = 2.3
			s.poison = 0.5
			s.fire_interval = 0.5
			s.mag_size = 6
			s.reload_time = 1.6
			s.bullet_speed = 36.0
			s.bullet_gravity = 1.5
			s.bullet_size = 2.6
			s.smoke = true
			s.recoil_kick = 1.3
			s.shoot_pitch = 0.6
			s.zoom = 0.85
		21:  # Storm Staff
			s.damage = 27.0
			s.chain = 3
			s.bolt = true
			s.fire_interval = 0.55
			s.mag_size = 8
			s.reload_time = 1.8
			s.bullet_speed = 190.0
			s.bullet_gravity = 0.0
			s.spread = 0.0
			s.recoil_kick = 1.4
			s.shoot_pitch = 1.6
			s.zoom = 0.7
		22:  # Frost Hands
			s.damage = 11.0
			s.pellets = 3
			s.frost = 0.5
			s.spread = 0.03
			s.fire_interval = 0.3
			s.mag_size = 12
			s.reload_time = 1.5
			s.bullet_speed = 62.0
			s.bullet_gravity = 0.0
			s.bullet_size = 1.5
			s.recoil_kick = 0.7
			s.shoot_pitch = 1.8
			s.zoom = 0.85
		23:  # Arcane Staff
			s.damage = 14.0
			s.homing = 4.2
			s.burst = 3
			s.fire_interval = 0.75
			s.mag_size = 12
			s.reload_time = 1.7
			s.bullet_speed = 30.0
			s.bullet_gravity = 0.0
			s.bullet_size = 2.2
			s.bullet_life = 3.0
			s.spread = 0.05
			s.recoil_kick = 0.8
			s.shoot_pitch = 1.4
		24:  # Sword
			s.melee_weapon = true
			s.damage = 55.0
			s.fire_interval = 0.5
			s.melee_range = 2.8
			s.melee_arc = 1.0
			s.move_speed *= 1.06
			_melee_common(s)
		25:  # Throwing Knives
			s.projectile = "knife"
			s.damage = 30.0
			s.fire_interval = 0.26
			s.mag_size = 4
			s.reload_time = 0.9
			s.bullet_speed = 52.0
			s.bullet_gravity = 7.0
			s.bullet_size = 1.6
			s.spread = 0.008
			s.recoil_kick = 0.5
			s.shoot_pitch = 1.5
			s.move_speed *= 1.08
			s.zoom = 0.85
		26:  # Longbow
			s.projectile = "arrow"
			s.damage = 58.0
			s.range_bonus = 0.6
			s.fire_interval = 0.85
			s.mag_size = 10
			s.reload_time = 1.8
			s.bullet_speed = 85.0
			s.bullet_gravity = 9.0
			s.bullet_size = 1.4
			s.spread = 0.002
			s.recoil_kick = 0.9
			s.shoot_pitch = 1.0
			s.zoom = 0.62
		27:  # Crossbow
			s.projectile = "bolt"
			s.damage = 88.0
			s.pierce = 1
			s.fire_interval = 0.4
			s.mag_size = 1
			s.reload_time = 1.5
			s.bullet_speed = 130.0
			s.bullet_gravity = 3.0
			s.bullet_size = 1.4
			s.spread = 0.0
			s.recoil_kick = 1.8
			s.shoot_pitch = 0.8
			s.zoom = 0.5
		28:  # Battle Axe
			s.melee_weapon = true
			s.damage = 92.0
			s.fire_interval = 0.95
			s.melee_range = 3.0
			s.melee_arc = 1.15
			s.knockback = 8.0
			s.move_speed *= 0.94
			_melee_common(s)
		29:  # Spear
			s.melee_weapon = true
			s.damage = 46.0
			s.fire_interval = 0.6
			s.melee_range = 4.4
			s.melee_arc = 0.35
			s.knockback = 3.0
			_melee_common(s)
		30:  # Powder Bomb
			s.projectile = "bomb"
			s.damage = 60.0
			s.explosive = 3.6
			s.fuse = 1.5
			s.fire_interval = 0.8
			s.mag_size = 3
			s.reload_time = 1.9
			s.bullet_speed = 22.0
			s.bullet_gravity = 15.0
			s.bullet_size = 2.4
			s.recoil_kick = 0.8
			s.shoot_pitch = 0.6
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


## Melee weapons never reload; the short "bullet" numbers only tell bots how
## close they have to get.
static func _melee_common(s) -> void:
	s.mag_size = 1
	s.reload_time = 0.01
	s.bullet_speed = 12.0
	s.bullet_life = 0.25
	s.recoil_kick = 0.6
	s.zoom = 0.9
	s.spread = 0.0
