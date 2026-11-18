extends RefCounted
## Text shown to players: the button reference and mode descriptions on the
## Options screen's HOW TO PLAY and MODES pages (settings_menu.gd), and the
## tips on the loading card (main.gd). Keep it short: it is read from a sofa.

## [action, gamepad, keyboard]; a one-element row is a heading.
const CONTROLS := [
	["ON FOOT"],
	["Move / look", "Left / right stick", "WASD / mouse"],
	["Fire / aim down sights", "RT / LT (hold)", "Left / right click"],
	["Jump (again in the air)", "A", "Space"],
	["Crouch; slide while running", "B", "C or Ctrl"],
	["Sprint", "Left stick click", "Shift (hold)"],
	["Dash", "RB", "Alt or V"],
	["Block (reflects bullets)", "LB", "Q"],
	["Melee: knife slash or blade swing", "Right stick click", "F or middle mouse"],
	["Reload", "X", "R"],
	["Open mystery box / enter vehicle", "Y", "E"],
	["Taunts", "D-pad", "1 - 4"],
	["Wall run", "Jump at a wall, keep moving", "same"],
	["Mantle", "Move into a ledge in the air", "same"],
	["Open parachute", "A", "Space"],
	["Pick a card", "Stick + A", "A / D + Space"],
	["Pause / options", "Start", "Esc"],
	["IN A VEHICLE"],
	["Drive / fly / aim", "Left / right stick", "WASD / mouse"],
	["Main weapon", "RT", "Left click"],
	["Second weapon or zoom", "LT", "Right click"],
	["Helicopter up / down", "A / B", "Space / C"],
	["Get out (helicopter: bail out)", "Y", "E"],
	["LOBBY"],
	["Join / leave", "A / B", "Space / Backspace"],
	["Customise your animal", "D-pad or left stick", "WASD or arrows"],
	["Mode / bots / target", "RT / Y / X", "G / B / K"],
	["Map / theme / options", "RB / LB / Back", "M / T / O"],
	["Start", "Start", "Enter"],
	["MENUS WITH THE MOUSE"],
	["Lobby: step a chip / your animal", "-", "Click (right-click: back)"],
	["Join as keyboard player / leave", "-", "Click a JOIN plate / the X"],
	["Options and pause menu", "-", "Hover + click, wheel scrolls"],
	["Close a menu", "-", "Right-click"],
]

## [name, one-line description]
const MODES := [
	["ROUNDS", "Free-for-all. Every time you are knocked out you pick one of three powerup cards and keep it, so whoever is behind keeps getting stronger. First to the kill target wins."],
	["ZOMBIES", "Co-op survival in the Quarantine zone. Hold out against ever bigger waves, with a boss every fifth wave. Everyone picks a card between waves; fallen players return when a wave is cleared."],
	["FRONTLINE", "Team war on a huge map: capture flags A, B and C to drain the other team's tickets. Parachute in, and drive buggies, tanks and helicopters."],
	["GUN GAME", "Every knockout hands you the next weapon on a ladder of all 31. Get knifed and you drop a rung. First to score with the last weapon wins."],
	["MEDIEVAL", "A free-for-all in the Castle with swords, axes, spears, bows, knives and powder bombs. Your block is a shield."],
]

const TIPS := [
	"Block (LB / Q) reflects bullets, rockets and grenades back at whoever fired them.",
	"Crouch while sprinting to slide. Jump out of a slide to keep the speed.",
	"Jump at a wall and keep moving forward to wall run.",
	"Your melee knife works with any gun in hand. Finish someone with it in Gun Game to knock them down a rung.",
	"Losing? Every knockout deals you a new card, and the cards stack.",
	"Purple mystery boxes hand out a random weapon (Y / E to open). Pink pads heal you. Both come back after a while.",
	"Doors have no button: just walk through. Shoot one enough and it splinters.",
	"Dash (RB / Alt) is a quick burst in the direction you are moving.",
	"Fall from high up in Frontline? Press jump to open your parachute.",
	"In Zombies, stick together: fallen players come back when the wave is cleared.",
	"Pets wander every map. Walk up to one and press Y / E to pet it: it heals you a little.",
	"Each player has their own look speed: Options > Controls > Player 1-6 look speed.",
	"Taunt with the D-pad (keys 1 - 4) after a knockout. It is only polite.",
	"The theme (LB / T in the lobby) restyles every map: try Toy, Warm or Cyberpunk.",
	"The Longshot hits harder the further its shot travels.",
	"Helicopters bail you out with a parachute. Tanks have a cannon and a machine gun.",
	"Aim down sights (LT / right click) for tighter spread and a little zoom.",
	"Headshots deal half as much damage again.",
]


static func tip() -> String:
	return TIPS[randi() % TIPS.size()]


static func mode_line(mode: String) -> String:
	for m in MODES:
		if m[0].replace(" ", "").to_lower() == mode.replace(" ", "").to_lower():
			return m[1]
	return ""
