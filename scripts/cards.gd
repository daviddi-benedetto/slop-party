extends RefCounted
## The powerup deck. A dead player is offered a random hand from this list.
##
## A card is {name, icon, rarity, desc, apply} where apply is func(stats) and
## icon names a pictogram in ui_kit.icon(). Weapon cards have rarity WEAPON and
## a "weapon" id instead of doing anything in apply; picking one swaps the
## player's weapon (weapons.gd) and keeps every other card.
##
## To add a card: append one entry. If it needs a new mechanic, add a field to
## stats.gd and implement it in player.gd / bullet.gd.

const Weapons = preload("res://scripts/weapons.gd")

const COMMON := 0
const RARE := 1
const EPIC := 2
const WEAPON := 3

const RARITY_NAMES := ["COMMON", "RARE", "EPIC", "WEAPON"]
const RARITY_COLORS := [Color(0.4, 0.82, 0.55), Color(0.3, 0.62, 1.0), Color(1.0, 0.62, 0.2), Color(0.74, 0.46, 1.0)]
const RARITY_WEIGHTS := [60.0, 30.0, 12.0, 22.0]

static var _deck: Array = []


static func deck() -> Array:
	if _deck.is_empty():
		_deck = [
			# ---------------- common ----------------
			{"name": "Bigger Mag", "icon": "ammo", "rarity": COMMON, "desc": "+50% magazine size",
				"apply": func(s): s.mag_size = int(ceil(s.mag_size * 1.5))},
			{"name": "Quick Hands", "icon": "ammo", "rarity": COMMON, "desc": "35% faster reload",
				"apply": func(s): s.reload_time *= 0.65},
			{"name": "Hollow Points", "icon": "star", "rarity": COMMON, "desc": "+25% damage",
				"apply": func(s): s.damage *= 1.25},
			{"name": "Fast Feet", "icon": "speed", "rarity": COMMON, "desc": "+20% move speed",
				"apply": func(s): s.move_speed *= 1.2},
			{"name": "Beefy", "icon": "heart", "rarity": COMMON, "desc": "+40 max health",
				"apply": func(s): s.max_health += 40.0},
			{"name": "Spring Legs", "icon": "jump", "rarity": COMMON, "desc": "+18% jump power",
				"apply": func(s): s.jump_velocity *= 1.18},
			{"name": "Hot Barrel", "icon": "bolt", "rarity": COMMON, "desc": "+30% fire rate",
				"apply": func(s): s.fire_interval /= 1.3},
			{"name": "High Velocity", "icon": "speed", "rarity": COMMON, "desc": "+50% bullet speed\n+10% damage",
				"apply": func(s): s.bullet_speed *= 1.5; s.damage *= 1.1},
			{"name": "Marksman", "icon": "target", "rarity": COMMON, "desc": "60% tighter spread\n+20% bullet speed",
				"apply": func(s): s.spread *= 0.4; s.bullet_speed *= 1.2},
			{"name": "Scavenger", "icon": "heart", "rarity": COMMON, "desc": "Heal 35 on every KO",
				"apply": func(s): s.kill_heal += 35.0},
			{"name": "Feather Fall", "icon": "jump", "rarity": COMMON, "desc": "30% lower gravity\n+10% jump power",
				"apply": func(s): s.gravity_mult *= 0.7; s.jump_velocity *= 1.1},
			# ---------------- rare ----------------
			{"name": "Bouncy", "icon": "bounce", "rarity": RARE, "desc": "Bullets bounce 2 more times",
				"apply": func(s): s.bounces += 2},
			{"name": "Ricochet", "icon": "bounce", "rarity": RARE, "desc": "+1 bounce, and each bounce\nadds 40% damage",
				"apply": func(s): s.bounces += 1; s.bounce_bonus += 0.4},
			{"name": "Buckshot", "icon": "boom", "rarity": RARE, "desc": "+3 pellets per shot\n-35% damage per pellet",
				"apply": func(s): s.pellets += 3; s.damage *= 0.65; s.spread += 0.035},
			{"name": "Vampire", "icon": "heart", "rarity": RARE, "desc": "Heal for 30% of damage dealt",
				"apply": func(s): s.lifesteal += 0.3},
			{"name": "Double Jump", "icon": "jump", "rarity": RARE, "desc": "+1 jump in mid-air",
				"apply": func(s): s.max_jumps += 1},
			{"name": "Regeneration", "icon": "heart", "rarity": RARE, "desc": "Constantly regenerate 6 HP/s",
				"apply": func(s): s.regen += 6.0},
			{"name": "Toxic Rounds", "icon": "drop", "rarity": RARE, "desc": "Hits poison for +40% damage over 3s",
				"apply": func(s): s.poison += 0.4},
			{"name": "Frost Rounds", "icon": "drop", "rarity": RARE, "desc": "Hits slow enemies by 35% for 2s",
				"apply": func(s): s.frost = 1.0 - (1.0 - s.frost) * 0.65},
			{"name": "Big Bullets", "icon": "target", "rarity": RARE, "desc": "Huge bullets, +20% damage\n-15% bullet speed",
				"apply": func(s): s.bullet_size *= 2.0; s.damage *= 1.2; s.bullet_speed *= 0.85},
			{"name": "Dash Master", "icon": "speed", "rarity": RARE, "desc": "Dash recharges twice as fast",
				"apply": func(s): s.dash_cooldown *= 0.5},
			{"name": "Ghost Dash", "icon": "speed", "rarity": RARE, "desc": "Nothing can hurt you\nwhile you dash",
				"apply": func(s): s.dash_invuln = true; s.dash_cooldown *= 0.85},
			{"name": "Thick Skin", "icon": "shield", "rarity": RARE, "desc": "Take 20% less damage",
				"apply": func(s): s.damage_taken *= 0.8},
			{"name": "Thorns", "icon": "shield", "rarity": RARE, "desc": "Attackers take 25% of the\ndamage they deal to you",
				"apply": func(s): s.thorns += 0.25},
			{"name": "Heavy Hitter", "icon": "star", "rarity": RARE, "desc": "Hits knock enemies back\n+10% damage",
				"apply": func(s): s.knockback += 9.0; s.damage *= 1.1},
			{"name": "Piercing Rounds", "icon": "target", "rarity": RARE, "desc": "Bullets pass through\none more enemy",
				"apply": func(s): s.pierce += 1},
			{"name": "Adrenaline", "icon": "bolt", "rarity": RARE, "desc": "Below 40% health: +35%\nspeed and fire rate",
				"apply": func(s): s.adrenaline += 0.35},
			{"name": "Last Round", "icon": "star", "rarity": RARE, "desc": "The last round in each\nmagazine deals +150% damage",
				"apply": func(s): s.overcharge += 1.5},
			{"name": "Fresh Mag", "icon": "ammo", "rarity": RARE, "desc": "Every KO instantly\nreloads your weapon",
				"apply": func(s): s.kill_reload = true},
			{"name": "Giant Slayer", "icon": "crown", "rarity": RARE, "desc": "+40% damage against\nwhoever is in the lead",
				"apply": func(s): s.giant_slayer += 0.4},
			# ---------------- epic ----------------
			{"name": "Explosive Rounds", "icon": "boom", "rarity": EPIC, "desc": "Bullets explode on impact\n-15% fire rate",
				"apply": func(s): s.explosive += 3.0; s.fire_interval /= 0.85},
			{"name": "Homing", "icon": "target", "rarity": EPIC, "desc": "Bullets steer toward enemies\n-20% damage",
				"apply": func(s): s.homing += 3.5; s.damage *= 0.8},
			{"name": "Glass Cannon", "icon": "skull", "rarity": EPIC, "desc": "+100% damage\n-40% max health",
				"apply": func(s): s.damage *= 2.0; s.max_health = maxf(20.0, s.max_health * 0.6)},
			{"name": "Juggernaut", "icon": "shield", "rarity": EPIC, "desc": "+100 max health\n-15% move speed",
				"apply": func(s): s.max_health += 100.0; s.move_speed *= 0.85},
			{"name": "Overdrive", "icon": "bolt", "rarity": EPIC, "desc": "+100% fire rate, double magazine\n-40% damage",
				"apply": func(s): s.fire_interval /= 2.0; s.mag_size *= 2; s.damage *= 0.6; s.spread += 0.012},
			{"name": "Deadeye", "icon": "target", "rarity": EPIC, "desc": "+80% damage, 2x bullet speed\nno bullet drop, -45% fire rate",
				"apply": func(s): s.damage *= 1.8; s.bullet_speed *= 2.0; s.bullet_gravity = 0.0; s.fire_interval /= 0.55},
			{"name": "Bubble Shield", "icon": "shield", "rarity": EPIC, "desc": "A bubble blocks one hit\nand recharges in 9 seconds",
				"apply": func(s): s.shield_cd = 9.0 if s.shield_cd <= 0.0 else s.shield_cd * 0.6},
			{"name": "Second Wind", "icon": "heart", "rarity": EPIC, "desc": "Once per life, survive a\nlethal hit with 1 health",
				"apply": func(s): s.second_wind += 1},
			{"name": "Rampage", "icon": "skull", "rarity": EPIC, "desc": "+15% damage per KO\nuntil you die (max +75%)",
				"apply": func(s): s.rampage += 0.15},
			{"name": "Lucky Draw", "icon": "star", "rarity": EPIC, "desc": "Every death offers you\none more card",
				"apply": func(s): s.card_draw = mini(5, s.card_draw + 1)},
		]
		# One card per weapon (the starting Blaster included, to switch back).
		for id in Weapons.LIST.size():
			var w: Dictionary = Weapons.LIST[id]
			_deck.append({"name": w.name, "icon": w.icon, "rarity": WEAPON, "weapon": id,
				"desc": w.desc, "apply": func(_s): pass})
	return _deck


## Draw `count` distinct cards, weighted by rarity. The weapon the player
## already holds is never offered, and at most one weapon appears per hand.
static func draw(count: int, held_weapon := -1) -> Array:
	var pool: Array = []
	for c in deck():
		if c.get("weapon", -2) != held_weapon:
			pool.append(c)
	var hand: Array = []
	while hand.size() < count and not pool.is_empty():
		var total := 0.0
		for c in pool:
			total += _weight(c)
		var roll := randf() * total
		var pick = pool[pool.size() - 1]
		for c in pool:
			roll -= _weight(c)
			if roll <= 0.0:
				pick = c
				break
		hand.append(pick)
		if pick.rarity == WEAPON:
			pool = pool.filter(func(c): return c.rarity != WEAPON)
		else:
			pool.erase(pick)
	return hand


static func _weight(c: Dictionary) -> float:
	# Weapon weight is shared between all weapon cards.
	if c.rarity == WEAPON:
		return RARITY_WEIGHTS[WEAPON] * 11.0 / (Weapons.LIST.size() - 1)
	return RARITY_WEIGHTS[c.rarity]
