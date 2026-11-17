extends Node
## Medieval mode rules: a free-for-all on the CASTLE map where only medieval
## arms exist. Everyone starts with a Sword; weapon cards and weapon pads
## only offer the medieval set (Sword, Throwing Knives, Longbow, Crossbow,
## Battle Axe, Spear, Powder Bomb), and the block is a shield: it lasts
## longer and comes back sooner (viewmodel.gd shows it on your arm).
## Everything else works like Rounds (powerup cards on every KO, first to
## the kill target wins). Added under game.world by game.gd.

const Weapons = preload("res://scripts/weapons.gd")

const START_WEAPON := 24      # Sword
## Cards that make no sense without gunpowder optics and gadgets.
const BANNED := ["Red Dot Sight", "2x Scope", "4x Scope", "Jetpack", "Buddy Drone"]

var game
var banner := ""
var banner_t := 9.0


func prepare(parts: Array) -> Array:
	return parts


func start() -> void:
	for p in game.players:
		p.weapon = START_WEAPON
		p.rebuild_stats()
	game.spawn_all_default()


func cards_on_death() -> bool:
	return true


func weapon_pool() -> Array:
	return Weapons.pool(["medieval"])


func banned_cards() -> Array:
	return BANNED


## The block is a shield here.
func modify_stats(s, _p) -> void:
	s.block_time *= 1.8
	s.block_cooldown *= 0.6


func results_title() -> String:
	return "%s RULES THE CASTLE" % game.winner.pname if game.winner != null else "MEDIEVAL"


func _physics_process(delta: float) -> void:
	banner_t += delta


func on_died(victim, attacker) -> void:
	var killer = attacker if attacker != null and is_instance_valid(attacker) and attacker != victim and game.is_player(attacker) else null
	if killer == null:
		victim.kills = maxi(0, victim.kills - 1)
	elif killer.kills >= game.kill_target:
		game.end_match(killer)


func respawn(p) -> void:
	game.respawn_default(p)


func bot_goal(_p):
	return null
