extends RefCounted
## The powerup deck. A dead player is offered a random hand from this list.

const COMMON := 0
const RARE := 1
const EPIC := 2

const RARITY_NAMES := ["COMMON", "RARE", "EPIC"]
const RARITY_COLORS := [Color(0.62, 0.74, 0.66), Color(0.35, 0.62, 0.95), Color(0.96, 0.62, 0.2)]
const RARITY_WEIGHTS := [60.0, 30.0, 12.0]

static var _deck: Array = []


static func deck() -> Array:
	if _deck.is_empty():
		_deck = [
			# ---------------- common ----------------
			{"name": "Bigger Mag", "rarity": COMMON, "desc": "+5 magazine size",
				"apply": func(s): s.mag_size += 5},
			{"name": "Quick Hands", "rarity": COMMON, "desc": "35% faster reload",
				"apply": func(s): s.reload_time *= 0.65},
			{"name": "Hollow Points", "rarity": COMMON, "desc": "+25% damage",
				"apply": func(s): s.damage *= 1.25},
			{"name": "Fast Feet", "rarity": COMMON, "desc": "+20% move speed",
				"apply": func(s): s.move_speed *= 1.2},
			{"name": "Beefy", "rarity": COMMON, "desc": "+40 max health",
				"apply": func(s): s.max_health += 40.0},
			{"name": "Spring Legs", "rarity": COMMON, "desc": "+18% jump power",
				"apply": func(s): s.jump_velocity *= 1.18},
			{"name": "Hot Barrel", "rarity": COMMON, "desc": "+30% fire rate",
				"apply": func(s): s.fire_interval /= 1.3},
			{"name": "High Velocity", "rarity": COMMON, "desc": "+50% bullet speed\n+10% damage",
				"apply": func(s): s.bullet_speed *= 1.5; s.damage *= 1.1},
			# ---------------- rare ----------------
			{"name": "Bouncy", "rarity": RARE, "desc": "Bullets bounce 2 more times",
				"apply": func(s): s.bounces += 2},
			{"name": "Buckshot", "rarity": RARE, "desc": "+3 pellets per shot\n-35% damage per pellet",
				"apply": func(s): s.pellets += 3; s.damage *= 0.65; s.spread += 0.035},
			{"name": "Vampire", "rarity": RARE, "desc": "Heal for 30% of damage dealt",
				"apply": func(s): s.lifesteal += 0.3},
			{"name": "Double Jump", "rarity": RARE, "desc": "+1 jump in mid-air",
				"apply": func(s): s.max_jumps += 1},
			{"name": "Regeneration", "rarity": RARE, "desc": "Constantly regenerate 6 HP/s",
				"apply": func(s): s.regen += 6.0},
			{"name": "Toxic Rounds", "rarity": RARE, "desc": "Hits poison for +40% damage over 3s",
				"apply": func(s): s.poison += 0.4},
			{"name": "Frost Rounds", "rarity": RARE, "desc": "Hits slow enemies by 35% for 2s",
				"apply": func(s): s.frost = 1.0 - (1.0 - s.frost) * 0.65},
			{"name": "Big Bullets", "rarity": RARE, "desc": "Huge bullets, +20% damage\n-15% bullet speed",
				"apply": func(s): s.bullet_size *= 2.0; s.damage *= 1.2; s.bullet_speed *= 0.85},
			{"name": "Dash Master", "rarity": RARE, "desc": "Dash recharges twice as fast",
				"apply": func(s): s.dash_cooldown *= 0.5},
			{"name": "Thick Skin", "rarity": RARE, "desc": "Take 20% less damage",
				"apply": func(s): s.damage_taken *= 0.8},
			{"name": "Heavy Hitter", "rarity": RARE, "desc": "Hits knock enemies back\n+10% damage",
				"apply": func(s): s.knockback += 9.0; s.damage *= 1.1},
			# ---------------- epic ----------------
			{"name": "Explosive Rounds", "rarity": EPIC, "desc": "Bullets explode on impact\n-15% fire rate",
				"apply": func(s): s.explosive += 3.0; s.fire_interval /= 0.85},
			{"name": "Homing", "rarity": EPIC, "desc": "Bullets steer toward enemies\n-20% damage",
				"apply": func(s): s.homing += 3.5; s.damage *= 0.8},
			{"name": "Glass Cannon", "rarity": EPIC, "desc": "+100% damage\n-40% max health",
				"apply": func(s): s.damage *= 2.0; s.max_health = maxf(20.0, s.max_health * 0.6)},
			{"name": "Juggernaut", "rarity": EPIC, "desc": "+100 max health\n-15% move speed",
				"apply": func(s): s.max_health += 100.0; s.move_speed *= 0.85},
			{"name": "Minigun", "rarity": EPIC, "desc": "+100% fire rate, +12 mag\n-40% damage",
				"apply": func(s): s.fire_interval /= 2.0; s.mag_size += 12; s.damage *= 0.6; s.spread += 0.012},
			{"name": "Sniper", "rarity": EPIC, "desc": "+80% damage, 2x bullet speed\nno bullet drop, -45% fire rate",
				"apply": func(s): s.damage *= 1.8; s.bullet_speed *= 2.0; s.bullet_gravity = 0.0; s.fire_interval /= 0.55},
		]
	return _deck


## Draw `count` distinct cards, weighted by rarity.
static func draw(count: int) -> Array:
	var pool: Array = deck().duplicate()
	var hand: Array = []
	while hand.size() < count and not pool.is_empty():
		var total := 0.0
		for c in pool:
			total += RARITY_WEIGHTS[c.rarity]
		var roll := randf() * total
		var pick = pool[pool.size() - 1]
		for c in pool:
			roll -= RARITY_WEIGHTS[c.rarity]
			if roll <= 0.0:
				pick = c
				break
		hand.append(pick)
		pool.erase(pick)
	return hand
