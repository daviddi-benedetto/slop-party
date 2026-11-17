extends Node
## Gun Game rules: free-for-all where every KO hands you the next weapon on
## the ladder (weapons.gd ladder(): every gun, then the magic, then the
## medieval arsenal, ending on the Sword). The first player to score with
## the last weapon wins.
##
## A player's rung is simply their `kills`. Being finished off with the
## basic melee (R3 / F punch) or killing yourself knocks you one rung down.
## No powerup cards and no weapon pads: respawns are quick.
## Added under game.world by game.gd, which calls the hooks below.

const Weapons = preload("res://scripts/weapons.gd")

var game
var ladder: Array = []
var banner := ""
var banner_t := 9.0


func prepare(parts: Array) -> Array:
	return parts


func start() -> void:
	ladder = Weapons.ladder()
	game.kill_target = ladder.size()
	game.spawn_all_default()
	for p in game.players:
		_arm(p)


func cards_on_death() -> bool:
	return false


func weapon_pads() -> bool:
	return false


func results_title() -> String:
	return "%s FINISHED THE GUN GAME" % game.winner.pname if game.winner != null else "GUN GAME"


func _physics_process(delta: float) -> void:
	banner_t += delta


func _arm(p) -> void:
	var id: int = ladder[clampi(p.kills, 0, ladder.size() - 1)]
	if p.weapon != id:
		if p.alive:
			p.pick_weapon(id)
		else:
			p.weapon = id
			p.rebuild_stats()


func on_died(victim, attacker) -> void:
	var killer = attacker if attacker != null and is_instance_valid(attacker) and attacker != victim and game.is_player(attacker) else null
	if killer == null:
		victim.kills = maxi(0, victim.kills - 1)
	else:
		if game.melee_strike and not killer.stats.melee_weapon and victim.kills > 0:
			victim.kills -= 1
			banner = "%s HUMILIATED %s" % [killer.pname, victim.pname]
			banner_t = 0.0
		if killer.kills >= ladder.size():
			game.end_match(killer)
			return
		_arm(killer)
		if killer.kills == ladder.size() - 1:
			banner = "%s IS ON THE LAST WEAPON!" % killer.pname
			banner_t = 0.0
	_arm(victim)
	game.respawn_later(victim, 1.6)


func respawn(p) -> void:
	_arm(p)
	game.respawn_default(p)


func bot_goal(_p):
	return null
