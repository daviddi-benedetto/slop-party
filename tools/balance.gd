extends Node
## Dev: balance statistics for bot-only matches (main.gd --balance, added to
## the game by game.gd). Every physics tick it adds up how long each weapon
## and each card was held by a living player; every knockout is credited to
## the killer's weapon and cards. When the run ends (the --shot quit) it
## prints one line:
##   [balance] {"time": s, "weapons": {name: [held_s, kills, deaths]},
##              "cards": {name: [held_s, kills, deaths]}}
## tools/balance.py adds several runs together and lists the outliers
## (kills per minute held, far from the average).

const Weapons = preload("res://scripts/weapons.gd")

var game
var _time := 0.0
var _weapons := {}
var _cards := {}


func _physics_process(delta: float) -> void:
	if game == null or game.frozen:
		return
	_time += delta
	for p in game.players:
		if not p.alive or p.vehicle != null:
			continue
		_add(_weapons, _wname(p), 0, delta)
		for c in _card_set(p):
			_add(_cards, c, 0, delta)


## Called by game.gd for every knockout.
func kill(attacker, victim) -> void:
	if attacker == null or not is_instance_valid(attacker) or attacker == victim or not game.is_player(attacker):
		return
	_add(_weapons, _wname(attacker), 1, 1.0)
	_add(_weapons, _wname(victim), 2, 1.0)
	for c in _card_set(attacker):
		_add(_cards, c, 1, 1.0)
	for c in _card_set(victim):
		_add(_cards, c, 2, 1.0)


func _exit_tree() -> void:
	print("[balance] ", JSON.stringify({"time": _time, "weapons": _weapons, "cards": _cards}))


func _wname(p) -> String:
	return Weapons.LIST[clampi(p.weapon, 0, Weapons.LIST.size() - 1)].name


func _card_set(p) -> Dictionary:
	var out := {}
	for c in p.cards:
		out[str(c)] = true
	return out


func _add(d: Dictionary, key: String, slot: int, amount: float) -> void:
	if not d.has(key):
		d[key] = [0.0, 0, 0]
	d[key][slot] += amount
