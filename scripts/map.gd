extends Node3D
## An arena. Everything is generated in code: geometry, materials, textures,
## lighting, sky, weather, foliage, spawn points, pickup spots, jump pads,
## hazards and the bot nav graph.
##
## build(index, time) makes one. MAPS lists the arenas; each is a
## layout function plus a THEMES entry:
##   0  NEON YARD   medium  container yard, two-storey warehouses, tunnels
##   1  EMBER PIT   small   foundry: forge, smelter houses, lava, a tunnel
##   2  FROST LINE  large   polar outpost: lab tower, comms buildings, bunkers
##   3  MUSEUM      medium  indoor: atrium, balcony ring, galleries, vaults
##   4  STADIUM     large   football pitch, bleachers, floodlights, lockers
##   5  SUBURB      large   houses with yards, a street, pools, storm drain
## Layouts 0-2 live in this file, 3-5 in map_places.gd (same helpers).
##
## VISUAL THEME (looks.gd, picked in the lobby): sets the time of day ("day",
## "sunset" or "night"). Night uses the map theme's own lighting; day and
## sunset start from the DAY / SUNSET presets and apply the map theme's
## optional "day" / "sunset" overrides. Then the visual theme overrides sky,
## light, neon colours, surface colours (Looks.grade in _mat) and colour
## grading (Looks.apply_post). The preset also scales neon emission
## (neon_scale) and point lights (light_scale) so each map reads well.
## Matches vary by theme only. Rain and snow are disabled; subtle fog is
## retained on large maps for depth.
##
## MATERIALS: a theme's "mats" maps a key to
## [colour, texture kind, tiles per metre, roughness, metallic]. Texture kinds
## are generated in _tex() (albedo + normal map, emission for lava). Every map
## also gets accent_a / accent_b (neon), rail, pad, dark, beacon, lamp, glass,
## window, water, leaf0 / leaf1, stripes, lava, trunk.
##
## PERFORMANCE: static meshes are not separate nodes. _add() appends each one
## into a per-material SurfaceTool and _flush() commits one MeshInstance per
## material at the end, so even a detailed map is a few dozen draw calls.
##
## CONVENTIONS (metres, Y up): the floor is centred on the origin with
## half-extents half_x / half_z. Most pieces take mirror=true, which also
## places a copy rotated 180 deg about Y ((x, z) -> (-x, -z)), so maps are
## point-symmetric. Anything centred on the origin must pass mirror=false.
## Underground floors are at y = -DEPTH; the ground is a 1 m slab (-1..0)
## with holes cut wherever _hole() was called (the floor is built after the
## layout, so layouts can add holes freely).
##
## Collision layers: 1 = world (this file), 2 = players.
##
## To add a map: write a layout function (here or in map_places.gd), add a
## THEMES entry, append to MAPS, and add a "mapN" song in sfx.gd.

const SkyKit = preload("res://scripts/sky.gd")
const Places = preload("res://scripts/map_places.gd")
const Front = preload("res://scripts/map_front.gd")
const Models = preload("res://scripts/models.gd")
const Prop = preload("res://scripts/prop.gd")
const Glass = preload("res://scripts/glass.gd")
const ZombieMap = preload("res://scripts/map_zombie.gd")
const CastleMap = preload("res://scripts/map_castle.gd")
const CityMap = preload("res://scripts/map_city.gd")
const RaceMap = preload("res://scripts/map_race.gd")
const Arch = preload("res://scripts/arch.gd")
const Door = preload("res://scripts/door.gd")
const Rubble = preload("res://scripts/rubble.gd")
const Looks = preload("res://scripts/looks.gd")
const Fx = preload("res://scripts/fx.gd")
const Surface = preload("res://scripts/surface.gd")
const Voxel = preload("res://scripts/voxel.gd")
const Voxelizer = preload("res://scripts/voxelizer.gd")

signal nav_built

const DOORS := false              # hang doors in doorways (off: open doorways everywhere)
const MAX_LIVE_BOOMS := 12         # outdoor fuel cans / barrels kept as live, explodable props per map
const WIN_W := 1.6                # building windows: width, sill and top height
const WIN_LO := 0.6
const WIN_HI := 2.6
const WIN_MID := 1.6
const FURN := 2.15               # scale of the Kenney furniture kit models
## Loose clutter scattered on walkable spots after the nav graph exists:
## [model, scale, mass].
## Per-theme clutter (theme / MAPS entry "clutter"); CLUTTER is the fallback.
const CLUTTER_SETS := {
	"yard": [["toon/Prop/Crate", 0.9, 5.0], ["toon/Prop/Pallet", 0.8, 7.0], ["toon/Prop/Traffic_Cone", 1.0, 2.0], ["survival/Barrel", 3.0, 10.0],
		["blaster/Crate_Small", 1.6, 6.0], ["toon/Prop/Exploding_Barrel", 1.0, 10.0], ["toon/Prop/Gas_Can", 0.8, 5.0], ["furniture/Cardboard_Box_Closed", 2.4, 2.0]],
	"foundry": [["survival/Barrel", 3.0, 10.0], ["toon/Prop/Pallet", 0.8, 7.0], ["toon/Prop/Crate", 0.9, 5.0], ["survival/Bucket", 2.6, 1.5],
		["toon/Prop/Exploding_Barrel", 1.0, 10.0], ["toon/Prop/Gas_Tank", 0.8, 8.0], ["blaster/Crate_Small", 1.6, 6.0]],
	"outpost": [["blaster/Crate_Small", 1.6, 6.0], ["survival/Box", 3.0, 5.0], ["survival/Barrel", 3.0, 10.0], ["toon/Prop/Gas_Can", 0.8, 5.0],
		["toon/Prop/Crate", 0.9, 5.0], ["survival/Bottle", 2.6, 0.5], ["toon/Prop/Exploding_Barrel", 1.0, 10.0]],
	"museum": [["furniture/Bench", 2.15, 9.0], ["furniture/Potted_Plant", 2.15, 4.0], ["furniture/Stool_Bar", 2.15, 3.0], ["furniture/Books", 2.6, 0.6],
		["furniture/Cardboard_Box_Closed", 2.4, 2.0], ["furniture/Trashcan", 2.15, 3.0], ["furniture/Chair", 2.15, 4.0]],
	"stadium": [["toon/Prop/Traffic_Cone", 1.0, 2.0], ["survival/Bottle", 2.6, 0.5], ["furniture/Trashcan", 2.15, 3.0], ["blaster/Target_Large", 2.5, 1.5],
		["furniture/Bench", 2.15, 9.0], ["survival/Bucket", 2.6, 1.5], ["furniture/Cardboard_Box_Closed", 2.4, 2.0]],
	"suburb": [["furniture/Trashcan", 2.15, 3.0], ["furniture/Cardboard_Box_Closed", 2.4, 2.0], ["survival/Bottle", 2.6, 0.5], ["survival/Bucket", 2.6, 1.5],
		["furniture/Chair", 2.15, 4.0], ["toon/Prop/Traffic_Cone", 1.0, 2.0], ["furniture/Potted_Plant", 2.15, 4.0], ["toon/Prop/Gas_Can", 0.8, 5.0]],
	"quarantine": [["furniture/Cardboard_Box_Closed", 2.4, 2.0], ["survival/Barrel", 3.0, 10.0], ["toon/Prop/Traffic_Cone", 1.0, 2.0], ["survival/Box", 3.0, 5.0],
		["furniture/Trashcan", 2.15, 3.0], ["toon/Prop/Exploding_Barrel", 1.0, 10.0], ["toon/Prop/Gas_Can", 0.8, 5.0], ["survival/Bottle", 2.6, 0.5]],
	"front": [["survival/Box", 3.0, 5.0], ["survival/Barrel", 3.0, 10.0], ["toon/Prop/Crate", 0.9, 5.0], ["survival/Tree_Log_Small", 2.4, 9.0],
		["toon/Prop/Exploding_Barrel", 1.0, 10.0], ["toon/Prop/Gas_Can", 0.8, 5.0], ["toon/Prop/Pallet", 0.8, 7.0]],
	"castle": [["fantasy/Barrel", 1.0, 12.0], ["fantasy/Crate_Wooden", 0.9, 6.0], ["fantasy/Bucket_Wooden_1", 1.2, 1.5], ["fantasy/Vase_2", 1.0, 2.0],
		["fantasy/Stool", 1.0, 3.0], ["fantasy/Pot_1", 1.3, 1.0], ["fantasy/FarmCrate_Apple", 1.2, 4.0], ["fantasy/Bag", 1.2, 3.0],
		["survival/Tree_Log_Small", 2.4, 9.0], ["fantasy/Mug", 1.4, 0.3]],
}
const CLUTTER := [["survival/Box", 3.0, 5.0], ["survival/Barrel", 3.0, 10.0], ["toon/Prop/Traffic_Cone", 1.0, 2.0],
	["furniture/Cardboard_Box_Closed", 2.4, 2.0], ["survival/Bottle", 2.6, 0.5], ["survival/Bucket", 2.6, 1.5],
	["furniture/Chair", 2.15, 4.0], ["toon/Prop/Pallet", 0.8, 7.0], ["furniture/Trashcan", 2.15, 3.0],
	["blaster/Crate_Small", 1.6, 6.0], ["furniture/Books", 2.6, 0.6], ["survival/Tree_Log_Small", 2.4, 9.0],
	["furniture/Stool_Bar", 2.15, 3.0], ["blaster/Target_Large", 2.5, 1.5],
	["toon/Prop/Exploding_Barrel", 1.0, 10.0], ["toon/Prop/Gas_Can", 0.8, 5.0], ["fantasy/Crate_Wooden", 0.9, 6.0], ["fantasy/Barrel", 1.0, 12.0]]

const DEPTH := 3.6
const FLOOR_H := 3.4
const NAV_STEP := 2.0
const CHUNK := 40.0             # batch chunk size on big maps (see _add)
const LAVA_DPS := 26.0

const MAPS := [
	{"name": "NEON YARD", "size": "MEDIUM", "clutter": "yard", "theme": "neon", "half": Vector2(32, 24), "wall": 4.5},
	{"name": "EMBER PIT", "size": "SMALL", "clutter": "foundry", "theme": "ember", "half": Vector2(19, 15), "wall": 4.0},
	{"name": "FROST LINE", "size": "LARGE", "clutter": "outpost", "theme": "frost", "half": Vector2(44, 32), "wall": 5.0},
	{"name": "MUSEUM", "size": "MEDIUM", "clutter": "museum", "theme": "museum", "half": Vector2(26, 20), "wall": 11.0},
	{"name": "STADIUM", "size": "LARGE", "clutter": "stadium", "theme": "stadium", "half": Vector2(46, 30), "wall": 3.0},
	{"name": "SUBURB", "size": "LARGE", "clutter": "suburb", "theme": "suburb", "half": Vector2(40, 30), "wall": 1.6},
	# Frontline mode only (not in the lobby's map list): 200 x 140 m.
	{"name": "FRONTLINE", "size": "HUGE", "clutter": "front", "theme": "front", "half": Vector2(100, 70), "wall": 1.4, "nav_step": 3.0, "nav_top": 20.0},
	{"name": "QUARANTINE", "size": "HUGE", "clutter": "quarantine", "theme": "suburb", "half": Vector2(72, 52), "wall": 3.0, "nav_step": 3.0, "nav_top": 16.0},
	{"name": "CASTLE", "size": "LARGE", "clutter": "castle", "theme": "castle", "half": Vector2(46, 34), "wall": 1.8, "nav_step": 2.0, "nav_top": 16.0},
	# Frontline and free-for-all: a medieval city of towers (map_city.gd).
	{"name": "HIGHTOWN", "size": "HUGE", "clutter": "front", "theme": "front", "half": Vector2(100, 70), "wall": 1.4, "nav_step": 3.0, "nav_top": 41.0},
	# Racing mode only: the circuit (map_race.gd).
	{"name": "RACEWAY", "size": "HUGE", "clutter": "front", "theme": "front", "half": Vector2(100, 70), "wall": 1.4, "nav_step": 5.0, "nav_top": 8.0},
]
const FRONTLINE := 6             # index of the Frontline map; the lobby lists maps below it
const ZOMBIE := 7                # large Zombies-only indoor/outdoor map
const CASTLE := 8                # Medieval mode's home; also in the lobby's map list
const HIGHTOWN := 9              # medieval tower city (Frontline or free-for-all)
const RACEWAY := 10              # Racing mode's circuit
const ARENAS := [0, 1, 2, 3, 4, 5, 8, 6, 9]   # maps the lobby offers (Rounds, Gun Game); 6, 9 = huge free-for-alls
const FRONT_MAPS := [6, 9]       # maps Frontline mode can be played on
const TIMES := ["day", "sunset", "night"]

const DAY := {
	"sky": {"top": Color(0.2, 0.45, 0.92), "horizon": Color(0.7, 0.82, 0.95), "ground": Color(0.28, 0.28, 0.3),
		"sun": Color(1.0, 0.95, 0.85), "cloud_color": Color(0.94, 0.95, 1.0), "clouds": 0.55, "stars": 0.0, "aurora": 0.0},
	"sun_color": Color(1.0, 0.96, 0.9), "sun_energy": 2.2, "sun_pitch": -52.0,
	"ambient": 1.0, "exposure": 0.95, "glow": 1.4, "neon": 0.45, "lights": 0.3,
	"fog": Color(0.66, 0.76, 0.88), "fog_mult": 0.5,
}
const SUNSET := {
	"sky": {"top": Color(0.14, 0.17, 0.38), "horizon": Color(1.0, 0.46, 0.2), "ground": Color(0.16, 0.08, 0.07),
		"sun": Color(1.0, 0.62, 0.3), "cloud_color": Color(0.6, 0.3, 0.27), "clouds": 0.75, "stars": 0.12, "aurora": 0.0},
	"sun_color": Color(1.0, 0.6, 0.36), "sun_energy": 1.9, "sun_pitch": -13.0,
	"ambient": 1.5, "exposure": 1.15, "glow": 1.2, "neon": 0.8, "lights": 0.75,
	"fog": Color(0.6, 0.32, 0.22), "fog_mult": 0.8,
}

const THEMES := {
	"neon": {
		"mats": {
			"ground": [Color(0.18, 0.2, 0.27), "concrete", 0.12, 0.45, 0.1],
			"path": [Color(0.27, 0.29, 0.38), "plates", 0.25, 0.35, 0.3],
			"wall": [Color(0.23, 0.28, 0.42), "plates", 0.25, 0.55, 0.2],
			"block_a": [Color(0.5, 0.54, 0.64), "concrete", 0.2, 0.6, 0.0],
			"block_b": [Color(0.62, 0.29, 0.23), "bricks", 0.4, 0.75, 0.0],
			"block_c": [Color(0.19, 0.22, 0.32), "corrugated", 0.5, 0.4, 0.5],
			"deck": [Color(0.36, 0.39, 0.47), "tiles", 0.5, 0.4, 0.5],
			"crate": [Color(0.58, 0.42, 0.25), "planks", 0.6, 0.7, 0.0],
			"c_red": [Color(0.7, 0.21, 0.17), "corrugated", 0.55, 0.5, 0.3],
			"c_blue": [Color(0.17, 0.4, 0.72), "corrugated", 0.55, 0.5, 0.3],
			"c_yellow": [Color(0.84, 0.65, 0.13), "corrugated", 0.55, 0.5, 0.3],
			"c_teal": [Color(0.1, 0.58, 0.52), "corrugated", 0.55, 0.5, 0.3],
			"soil": [Color(0.22, 0.17, 0.13), "soft", 0.3, 0.9, 0.0],
		},
		"accent_a": Color(1.0, 0.42, 0.16), "accent_b": Color(0.15, 0.75, 1.0), "neon": true, "paths": true,
		"night": {"sky": {"top": Color(0.01, 0.015, 0.05), "horizon": Color(0.1, 0.1, 0.26), "ground": Color(0.02, 0.02, 0.05),
			"sun": Color(0.75, 0.82, 1.0), "cloud_color": Color(0.13, 0.13, 0.26), "clouds": 0.55, "stars": 1.0, "aurora": 0.0},
			"sun_color": Color(0.62, 0.72, 1.0), "sun_energy": 0.8, "ambient": 0.6, "fog": Color(0.05, 0.06, 0.14), "fog_density": 0.006},
		"sun_yaw": 38.0, "weathers": ["clear", "clear", "rain", "fog"],
		"leaf": [Color(0.16, 0.42, 0.2), Color(0.22, 0.5, 0.18)], "grass": [Color(0.1, 0.25, 0.1), Color(0.3, 0.55, 0.22)],
		"scenery": "city", "motes": [Color(0.4, 0.9, 1.0), Color(1.0, 0.6, 0.3)], "mote_rise": 0.05,
	},
	"ember": {
		"mats": {
			"ground": [Color(0.25, 0.2, 0.18), "rock", 0.1, 0.7, 0.0],
			"path": [Color(0.38, 0.27, 0.21), "tiles", 0.3, 0.55, 0.0],
			"wall": [Color(0.38, 0.25, 0.21), "bricks", 0.18, 0.8, 0.0],
			"block_a": [Color(0.66, 0.47, 0.3), "rock", 0.3, 0.75, 0.0],
			"block_b": [Color(0.32, 0.32, 0.36), "plates", 0.3, 0.4, 0.7],
			"block_c": [Color(0.17, 0.15, 0.16), "corrugated", 0.5, 0.4, 0.6],
			"deck": [Color(0.5, 0.33, 0.2), "planks", 0.5, 0.7, 0.0],
			"crate": [Color(0.6, 0.37, 0.17), "planks", 0.6, 0.7, 0.0],
			"lava": [Color(0.32, 0.11, 0.05), "lava", 0.18, 0.6, 0.0],
			"house": [Color(0.55, 0.38, 0.26), "bricks", 0.4, 0.8, 0.0],
		},
		"accent_a": Color(1.0, 0.5, 0.1), "accent_b": Color(1.0, 0.85, 0.3), "neon": true, "paths": true,
		"night": {"sky": {"top": Color(0.03, 0.01, 0.02), "horizon": Color(0.42, 0.12, 0.05), "ground": Color(0.12, 0.03, 0.01),
			"sun": Color(1.0, 0.55, 0.25), "cloud_color": Color(0.2, 0.07, 0.05), "clouds": 0.8, "stars": 0.3, "aurora": 0.0},
			"sun_color": Color(1.0, 0.66, 0.45), "sun_energy": 0.85, "ambient": 0.62, "fog": Color(0.2, 0.06, 0.03), "fog_density": 0.009},
		"day": {"sky": {"top": Color(0.32, 0.22, 0.2), "horizon": Color(0.86, 0.52, 0.32), "cloud_color": Color(0.55, 0.38, 0.32)},
			"fog": Color(0.55, 0.36, 0.26), "sun_color": Color(1.0, 0.85, 0.7)},
		"sun_yaw": -60.0, "weathers": ["clear", "clear", "fog"],
		"leaf": [Color(0.2, 0.18, 0.1), Color(0.3, 0.22, 0.1)], "grass": [],
		"scenery": "rocks", "motes": [Color(1.0, 0.6, 0.15), Color(1.0, 0.3, 0.1)], "mote_rise": 0.7,
	},
	"frost": {
		"mats": {
			"ground": [Color(0.5, 0.57, 0.68), "snow", 0.08, 0.85, 0.0],
			"path": [Color(0.27, 0.5, 0.64), "ice", 0.12, 0.12, 0.2],
			"wall": [Color(0.4, 0.5, 0.62), "plates", 0.25, 0.5, 0.3],
			"block_a": [Color(0.72, 0.76, 0.82), "plates", 0.3, 0.45, 0.2],
			"block_b": [Color(0.42, 0.72, 0.88), "ice", 0.25, 0.1, 0.1],
			"block_c": [Color(0.22, 0.28, 0.38), "corrugated", 0.5, 0.4, 0.5],
			"deck": [Color(0.36, 0.42, 0.5), "tiles", 0.5, 0.4, 0.5],
			"crate": [Color(0.88, 0.45, 0.12), "plates", 0.5, 0.5, 0.2],
			"pine": [Color(0.09, 0.3, 0.24), "leaves", 1.2, 0.9, 0.0],
			"trunk": [Color(0.3, 0.2, 0.14), "rock", 0.8, 0.9, 0.0],
			"snowcap": [Color(0.8, 0.86, 0.95), "snow", 0.5, 0.9, 0.0],
		},
		"accent_a": Color(0.3, 1.0, 0.95), "accent_b": Color(0.45, 0.6, 1.0), "neon": true, "paths": true,
		"night": {"sky": {"top": Color(0.01, 0.03, 0.07), "horizon": Color(0.06, 0.2, 0.26), "ground": Color(0.02, 0.05, 0.07),
			"sun": Color(0.8, 0.95, 1.0), "cloud_color": Color(0.1, 0.18, 0.24), "clouds": 0.35, "stars": 1.0, "aurora": 1.0},
			"sun_color": Color(0.7, 0.86, 1.0), "sun_energy": 0.7, "ambient": 0.42, "fog": Color(0.05, 0.12, 0.16), "fog_density": 0.005},
		"day": {"sky": {"top": Color(0.3, 0.55, 0.9), "horizon": Color(0.8, 0.9, 0.97)}, "fog": Color(0.75, 0.85, 0.95), "sun_energy": 1.7, "exposure": 0.85},
		"sun_yaw": 130.0, "weathers": ["clear", "snow", "snow", "fog"],
		"leaf": [Color(0.09, 0.3, 0.24), Color(0.12, 0.34, 0.26)], "grass": [],
		"scenery": "ice", "motes": [Color(0.9, 0.97, 1.0), Color(0.7, 0.9, 1.0)], "mote_rise": -0.6,
	},
	"museum": {
		"mats": {
			"ground": [Color(0.8, 0.77, 0.72), "marble", 0.1, 0.12, 0.0],
			"path": [Color(0.4, 0.36, 0.34), "marble", 0.1, 0.12, 0.0],
			"wall": [Color(0.84, 0.8, 0.72), "plaster", 0.15, 0.85, 0.0],
			"block_a": [Color(0.92, 0.91, 0.9), "marble", 0.25, 0.15, 0.0],
			"block_b": [Color(0.55, 0.14, 0.13), "plaster", 0.2, 0.8, 0.0],
			"block_c": [Color(0.3, 0.19, 0.12), "planks", 0.5, 0.5, 0.0],
			"deck": [Color(0.55, 0.36, 0.2), "planks", 0.5, 0.45, 0.0],
			"crate": [Color(0.5, 0.36, 0.22), "planks", 0.6, 0.7, 0.0],
			"gold": [Color(0.95, 0.72, 0.32), "", 1.0, 0.25, 1.0],
			"bone": [Color(0.86, 0.8, 0.66), "rock", 0.8, 0.7, 0.0],
			"ceiling": [Color(0.86, 0.84, 0.8), "plaster", 0.15, 0.9, 0.0],
			"teal": [Color(0.12, 0.36, 0.38), "plaster", 0.2, 0.8, 0.0],
			"soil": [Color(0.24, 0.17, 0.11), "soft", 0.3, 0.9, 0.0],
		},
		"accent_a": Color(1.0, 0.72, 0.4), "accent_b": Color(0.6, 0.82, 1.0), "neon": false, "paths": false, "indoor": true,
		"night": {"sky": {"top": Color(0.01, 0.02, 0.06), "horizon": Color(0.08, 0.1, 0.22), "ground": Color(0.02, 0.02, 0.05),
			"sun": Color(0.8, 0.85, 1.0), "cloud_color": Color(0.1, 0.11, 0.2), "clouds": 0.4, "stars": 1.0, "aurora": 0.0},
			"sun_color": Color(0.6, 0.7, 1.0), "sun_energy": 0.7, "ambient": 0.35, "fog": Color(0.05, 0.05, 0.1), "fog_density": 0.002},
		"day": {"ambient": 0.55, "sun_energy": 2.6}, "sunset": {"ambient": 0.75},
		"sun_yaw": 25.0, "weathers": ["clear"], "leaf": [Color(0.15, 0.4, 0.2), Color(0.2, 0.48, 0.18)], "grass": [Color(0.1, 0.28, 0.1), Color(0.3, 0.55, 0.2)],
		"scenery": "none", "motes": [Color(1.0, 0.95, 0.85), Color(0.9, 0.9, 1.0)], "mote_rise": 0.02,
	},
	"stadium": {
		"mats": {
			"ground": [Color(0.24, 0.46, 0.18), "turf", 0.125, 0.9, 0.0],
			"path": [Color(0.6, 0.2, 0.15), "rubber", 0.2, 0.85, 0.0],
			"wall": [Color(0.55, 0.56, 0.6), "concrete", 0.2, 0.7, 0.0],
			"block_a": [Color(0.62, 0.63, 0.66), "concrete", 0.2, 0.7, 0.0],
			"block_b": [Color(0.16, 0.32, 0.65), "plates", 0.4, 0.5, 0.1],
			"block_c": [Color(0.22, 0.24, 0.28), "corrugated", 0.5, 0.45, 0.5],
			"deck": [Color(0.45, 0.47, 0.5), "tiles", 0.5, 0.5, 0.2],
			"crate": [Color(0.85, 0.62, 0.12), "plates", 0.5, 0.5, 0.2],
			"seat_red": [Color(0.72, 0.15, 0.14), "plates", 0.4, 0.5, 0.1],
			"line": [Color(0.94, 0.94, 0.92), "", 1.0, 0.9, 0.0],
			"metal": [Color(0.86, 0.87, 0.9), "", 1.0, 0.3, 0.8],
			"soil": [Color(0.24, 0.18, 0.13), "soft", 0.3, 0.9, 0.0],
		},
		"accent_a": Color(1.0, 0.55, 0.15), "accent_b": Color(0.2, 0.72, 1.0), "neon": true, "paths": false,
		"night": {"sky": {"top": Color(0.01, 0.02, 0.05), "horizon": Color(0.12, 0.12, 0.22), "ground": Color(0.02, 0.02, 0.04),
			"sun": Color(0.8, 0.85, 1.0), "cloud_color": Color(0.12, 0.12, 0.2), "clouds": 0.5, "stars": 0.8, "aurora": 0.0},
			"sun_color": Color(0.62, 0.7, 1.0), "sun_energy": 0.6, "ambient": 0.5, "fog": Color(0.05, 0.06, 0.12), "fog_density": 0.004},
		"sun_yaw": 70.0, "weathers": ["clear", "clear", "rain", "fog"],
		"leaf": [Color(0.15, 0.4, 0.17), Color(0.22, 0.48, 0.16)], "grass": [Color(0.12, 0.32, 0.1), Color(0.32, 0.6, 0.22)],
		"mown": true, "scenery": "stadium", "motes": [Color(1.0, 1.0, 0.9), Color(0.9, 0.95, 1.0)], "mote_rise": 0.05,
	},
	"suburb": {
		"mats": {
			"ground": [Color(0.26, 0.42, 0.17), "lawn", 0.1, 0.9, 0.0],
			"path": [Color(0.62, 0.6, 0.56), "concrete", 0.25, 0.7, 0.0],
			"road": [Color(0.2, 0.2, 0.22), "asphalt", 0.12, 0.8, 0.0],
			"wall": [Color(0.55, 0.4, 0.27), "planks", 0.5, 0.8, 0.0],
			"block_a": [Color(0.6, 0.58, 0.55), "concrete", 0.25, 0.7, 0.0],
			"block_b": [Color(0.55, 0.25, 0.18), "bricks", 0.4, 0.8, 0.0],
			"block_c": [Color(0.27, 0.24, 0.26), "shingles", 0.4, 0.8, 0.0],
			"roof_red": [Color(0.45, 0.2, 0.16), "shingles", 0.4, 0.8, 0.0],
			"deck": [Color(0.5, 0.34, 0.2), "planks", 0.5, 0.7, 0.0],
			"crate": [Color(0.5, 0.36, 0.22), "planks", 0.6, 0.7, 0.0],
			"siding0": [Color(0.86, 0.83, 0.72), "siding", 0.45, 0.8, 0.0],
			"siding1": [Color(0.5, 0.62, 0.74), "siding", 0.45, 0.8, 0.0],
			"siding2": [Color(0.6, 0.7, 0.54), "siding", 0.45, 0.8, 0.0],
			"siding3": [Color(0.84, 0.68, 0.55), "siding", 0.45, 0.8, 0.0],
			"trim": [Color(0.92, 0.92, 0.9), "", 1.0, 0.7, 0.0],
			"line": [Color(0.95, 0.8, 0.2), "", 1.0, 0.8, 0.0],
			"tile_blue": [Color(0.4, 0.7, 0.85), "tiles", 0.8, 0.2, 0.0],
			"car_red": [Color(0.7, 0.08, 0.08), "", 1.0, 0.25, 0.6],
			"car_blue": [Color(0.1, 0.25, 0.6), "", 1.0, 0.25, 0.6],
			"car_white": [Color(0.88, 0.88, 0.9), "", 1.0, 0.25, 0.6],
			"car_black": [Color(0.06, 0.06, 0.07), "", 1.0, 0.25, 0.6],
			"tyre": [Color(0.04, 0.04, 0.05), "", 1.0, 0.9, 0.0],
			"metal": [Color(0.6, 0.62, 0.66), "", 1.0, 0.35, 0.8],
			"soil": [Color(0.24, 0.17, 0.11), "soft", 0.3, 0.9, 0.0],
		},
		"accent_a": Color(1.0, 0.78, 0.45), "accent_b": Color(0.55, 0.8, 1.0), "neon": false, "paths": false,
		"night": {"sky": {"top": Color(0.01, 0.02, 0.06), "horizon": Color(0.1, 0.12, 0.24), "ground": Color(0.02, 0.02, 0.05),
			"sun": Color(0.85, 0.9, 1.0), "cloud_color": Color(0.12, 0.13, 0.22), "clouds": 0.5, "stars": 1.0, "aurora": 0.0},
			"sun_color": Color(0.6, 0.72, 1.0), "sun_energy": 0.75, "ambient": 0.5, "fog": Color(0.05, 0.06, 0.12), "fog_density": 0.004},
		"sun_yaw": 50.0, "weathers": ["clear", "clear", "rain", "fog", "snow"],
		"leaf": [Color(0.16, 0.4, 0.15), Color(0.28, 0.5, 0.14)], "grass": [Color(0.12, 0.3, 0.08), Color(0.36, 0.6, 0.2)],
		"cover": true, "scenery": "suburb", "motes": [Color(1.0, 1.0, 0.7), Color(0.8, 1.0, 0.6)], "mote_rise": 0.05,
	},
	"castle": {
		"mats": {
			"ground": [Color(0.28, 0.42, 0.18), "lawn", 0.1, 0.9, 0.0],
			"path": [Color(0.5, 0.48, 0.44), "rock", 0.22, 0.85, 0.0],
			"road": [Color(0.4, 0.31, 0.22), "soft", 0.15, 0.95, 0.0],
			"wall": [Color(0.58, 0.56, 0.52), "bricks", 0.3, 0.9, 0.0],
			"block_a": [Color(0.66, 0.63, 0.58), "bricks", 0.35, 0.9, 0.0],
			"block_b": [Color(0.45, 0.43, 0.42), "rock", 0.3, 0.9, 0.0],
			"block_c": [Color(0.27, 0.28, 0.33), "shingles", 0.4, 0.8, 0.0],
			"roof_red": [Color(0.5, 0.2, 0.16), "shingles", 0.4, 0.8, 0.0],
			"deck": [Color(0.46, 0.32, 0.2), "planks", 0.5, 0.75, 0.0],
			"crate": [Color(0.5, 0.36, 0.22), "planks", 0.6, 0.7, 0.0],
			"trim": [Color(0.74, 0.7, 0.62), "", 1.0, 0.8, 0.0],
			"hay": [Color(0.8, 0.66, 0.32), "soft", 0.5, 0.95, 0.0],
			"metal": [Color(0.4, 0.4, 0.44), "", 1.0, 0.4, 0.8],
			"soil": [Color(0.3, 0.22, 0.15), "soft", 0.3, 0.9, 0.0],
		},
		"accent_a": Color(1.0, 0.62, 0.25), "accent_b": Color(0.8, 0.2, 0.2), "neon": false, "paths": false,
		"night": {"sky": {"top": Color(0.01, 0.02, 0.07), "horizon": Color(0.12, 0.14, 0.28), "ground": Color(0.02, 0.02, 0.05),
			"sun": Color(0.85, 0.9, 1.0), "cloud_color": Color(0.13, 0.14, 0.24), "clouds": 0.5, "stars": 1.0, "aurora": 0.0},
			"sun_color": Color(0.62, 0.74, 1.0), "sun_energy": 0.8, "ambient": 0.6, "fog": Color(0.06, 0.07, 0.13), "fog_density": 0.004},
		"sun_yaw": 40.0, "weathers": ["clear"],
		"leaf": [Color(0.16, 0.38, 0.14), Color(0.3, 0.46, 0.14)], "grass": [Color(0.14, 0.3, 0.08), Color(0.4, 0.6, 0.22)],
		"cover": true, "scenery": "castle", "motes": [Color(1.0, 0.9, 0.6), Color(0.9, 1.0, 0.7)], "mote_rise": 0.05,
	},
	"front": {
		"mats": {
			"ground": [Color(0.3, 0.42, 0.2), "lawn", 0.08, 0.9, 0.0],
			"path": [Color(0.55, 0.5, 0.42), "tiles", 0.25, 0.75, 0.0],
			"road": [Color(0.19, 0.19, 0.21), "asphalt", 0.1, 0.8, 0.0],
			"dirt": [Color(0.36, 0.28, 0.2), "soft", 0.15, 0.95, 0.0],
			"wall": [Color(0.5, 0.47, 0.42), "rock", 0.3, 0.9, 0.0],
			"block_a": [Color(0.6, 0.58, 0.54), "concrete", 0.25, 0.75, 0.0],
			"block_b": [Color(0.56, 0.3, 0.22), "bricks", 0.4, 0.8, 0.0],
			"block_c": [Color(0.3, 0.32, 0.3), "corrugated", 0.45, 0.5, 0.5],
			"house": [Color(0.8, 0.74, 0.6), "plaster", 0.2, 0.85, 0.0],
			"roof_red": [Color(0.5, 0.22, 0.16), "shingles", 0.4, 0.8, 0.0],
			"deck": [Color(0.48, 0.34, 0.22), "planks", 0.5, 0.7, 0.0],
			"crate": [Color(0.42, 0.4, 0.25), "planks", 0.6, 0.7, 0.0],
			"sand": [Color(0.62, 0.55, 0.4), "soft", 0.6, 0.95, 0.0],
			"olive": [Color(0.3, 0.34, 0.2), "plates", 0.4, 0.6, 0.3],
			"metal": [Color(0.55, 0.56, 0.6), "", 1.0, 0.35, 0.8],
			"trim": [Color(0.88, 0.86, 0.82), "", 1.0, 0.7, 0.0],
			"line": [Color(0.95, 0.85, 0.3), "", 1.0, 0.8, 0.0],
			"tyre": [Color(0.04, 0.04, 0.05), "", 1.0, 0.9, 0.0],
			"car_red": [Color(0.6, 0.1, 0.08), "", 1.0, 0.3, 0.5],
			"car_white": [Color(0.85, 0.85, 0.86), "", 1.0, 0.3, 0.5],
			"car_blue": [Color(0.12, 0.25, 0.5), "", 1.0, 0.3, 0.5],
			"hay": [Color(0.78, 0.64, 0.32), "soft", 0.5, 0.95, 0.0],
			"pine": [Color(0.12, 0.3, 0.16), "leaves", 1.2, 0.9, 0.0],
			"soil": [Color(0.3, 0.22, 0.15), "soft", 0.3, 0.9, 0.0],
			"team0": [Color(0.2, 0.45, 0.95), "", 1.0, 0.5, 0.1],
			"team1": [Color(0.95, 0.42, 0.15), "", 1.0, 0.5, 0.1],
		},
		"accent_a": Color(1.0, 0.75, 0.4), "accent_b": Color(0.6, 0.85, 1.0), "neon": false, "paths": false,
		"night": {"sky": {"top": Color(0.01, 0.02, 0.06), "horizon": Color(0.1, 0.12, 0.22), "ground": Color(0.02, 0.02, 0.05),
			"sun": Color(0.85, 0.9, 1.0), "cloud_color": Color(0.12, 0.13, 0.22), "clouds": 0.5, "stars": 1.0, "aurora": 0.0},
			"sun_color": Color(0.6, 0.72, 1.0), "sun_energy": 0.8, "ambient": 0.55, "fog": Color(0.05, 0.06, 0.12), "fog_density": 0.0035},
		"sun_yaw": 35.0, "weathers": ["clear", "clear", "rain", "fog"],
		"leaf": [Color(0.16, 0.38, 0.14), Color(0.3, 0.46, 0.14)], "grass": [Color(0.14, 0.3, 0.08), Color(0.42, 0.6, 0.22)],
		"cover": true, "scenery": "front", "motes": [Color(1.0, 1.0, 0.7), Color(0.8, 1.0, 0.6)], "mote_rise": 0.05,
	},
}

static var _tex_cache := {}       # texture kind -> [albedo, normal, emission]
static var _blob_cache: Array = []

var map_index := 0
var theme := {}
var time := "night"
var look := {}                    # the visual theme (looks.gd entry)
var weather := "clear"
var half_x := 32.0
var half_z := 24.0
var wall_h := 4.5
var light_scale := 1.0            # point-light multiplier for the time of day
var neon_scale := 1.0             # emission multiplier for the time of day
var night_amount := 1.0           # 0 day, 0.45 sunset, 1 night (windows, street lamps)
var indoor := false
var nav_step := NAV_STEP          # nav grid spacing (bigger on the Frontline map)
var nav_top := 14.0               # highest walkable surface the nav graph samples
var flags: Array = []             # Frontline: capture point positions (A, B, C)
var bases: Array = []             # Frontline: team 0 / team 1 base centres
var vehicle_spots: Array = []     # Frontline: [type, Transform3D, team]
var ffa_vehicle_spots: Array = [] # Rounds on this map: [type, Transform3D] (unarmed)
var race_path: Array = []         # Racing: the circuit's centre line, every 3 m (map_race.gd)
var race_width := 14.0
var nav_links: Array = []         # [bottom, top] stair flights too steep for the nav grid's step (map_city.gd)

var spawn_points: Array = []      # Array of Vector3
var pickup_spots: Array = []      # [["weapon" | "health", Vector3], ...] read by game.gd
var _audit := false               # dev flag --audit: report models standing inside other solids
var _audit_models: Array = []
var mounds: Array = []            # Vector4(x, z, radius, height): gentle hills (see _mounds)
var _occ := PackedByteArray()     # ground occupancy grid (see _occ_build)
var _occ_w := 0
var _occ_h := 0
var _occ_extra: Array = []        # Vector3(x, z, radius) blocked spots that have no world collider
var _paved: Array = []            # Rect2 of every _surface() (roads, paths, courts)
var lawns: Array = []             # Rect2 (XZ) where grass grows
var no_grass: Array = []          # Rect2 (XZ) kept clear of grass (drives, paths)
var nav := AStar3D.new()
var nav_ready := false
var _nav_ids := PackedInt64Array()
var _body: StaticBody3D
var _mats := {}
var _holes: Array = []            # Rect2 (XZ) cut out of the ground slab
var _pending_surfaces: Array = [] # [Rect2, y, mat] waiting for _lay_surfaces()
var roofs: Array = []             # Rect2 footprints of every _building (indoors)
var _box_cache := {}
var _stairs_cache := {}
var _batches := {}
var _unit_sphere: SphereMesh
var _unit_cyl: CylinderMesh
var _rng := RandomNumberGenerator.new()
var _env: Environment
var boundary: StaticBody3D      # the invisible perimeter walls (player.gd: no wall runs on them)
var _sun: DirectionalLight3D
var _hazards: Array = []
var _pad_rings: Array = []
var _time := 0.0
var _beacon: StandardMaterial3D   # skyline warning lights (blink together)
var _rotors: Array = []           # wind turbine rotors (spin in _process)
var _blimp: Node3D                # a blimp circling the arena far out
var _live_booms := 0              # outdoor fuel cans / barrels left as live (explodable) props
var _keep: Array = []             # [Rect2 (XZ), y0, y1]: doorways, stairs, windows kept clear of furniture
var _deferred: Array = []         # furniture / props waiting for the keep-clear check at the end of build()
var _dropped := 0
var _placing := false             # true while _place_deferred() runs (place for real)
var _skipped: Array = []          # [Rect2, y] footprints of skipped furniture (things on top go too)
var _flicker: Array = []         # [OmniLight3D, base energy, phase, speed]: neon that stutters
var _water_t := 0.0


func build(index := 0, theme_key := "classic") -> void:
	map_index = clampi(index, 0, MAPS.size() - 1)
	var info: Dictionary = MAPS[map_index]
	# Old time-of-day names still work (command line): day, sunset, night.
	theme_key = {"day": "classic", "sunset": "warm", "night": "moonlit"}.get(theme_key, theme_key)
	look = Looks.get_look(theme_key)
	Models.look = look
	Voxel.on = Settings.v("voxel")
	Voxel.look = look
	time = look.base
	theme = THEMES[info.theme].duplicate()
	for k in ["accent_a", "accent_b"]:
		if look.has(k):
			theme[k] = look[k]
	theme.leaf = theme.leaf.map(func(c): return Looks.grade(look, c))
	theme.grass = theme.grass.map(func(c): return Looks.grade(look, c))
	# Matches vary by time of day only. Keep the atmosphere in the map theme;
	# precipitation and random fog presets are intentionally disabled.
	weather = "clear"
	indoor = theme.get("indoor", false)
	half_x = info.half.x
	half_z = info.half.y
	wall_h = info.wall
	nav_step = info.get("nav_step", NAV_STEP)
	nav_top = info.get("nav_top", 14.0)
	_rng.seed = 20240607 + map_index
	_audit = "--audit" in OS.get_cmdline_user_args()
	_body = StaticBody3D.new()
	_body.collision_layer = 1
	_body.collision_mask = 0
	add_child(_body)
	_unit_sphere = SphereMesh.new()
	_unit_sphere.radius = 1.0
	_unit_sphere.height = 2.0
	_unit_sphere.radial_segments = 16
	_unit_sphere.rings = 8
	_unit_cyl = CylinderMesh.new()
	_unit_cyl.top_radius = 1.0
	_unit_cyl.bottom_radius = 1.0
	_unit_cyl.height = 1.0
	_unit_cyl.radial_segments = 16
	_unit_cyl.rings = 1
	_build_environment()
	_make_materials()
	_build_walls()
	match map_index:
		1: _layout_pit()
		2: _layout_frost()
		3: Places.museum(self)
		4: Places.stadium(self)
		5: Places.suburb(self)
		6: Front.frontline(self)
		7: ZombieMap.build(self)
		8: CastleMap.build(self)
		9: CityMap.build(self)
		10: RaceMap.build(self)
		_: _layout_yard()
	if _audit:
		_audit_report()
	_ruins()
	_occ_build()
	_mounds()
	_build_floor()
	_build_scenery()
	_place_deferred()
	_flush()
	_set_pieces()
	_wall_art()
	_ambient_life()
	_ground_decals()


func _process(delta: float) -> void:
	_time += delta
	# Neon that buzzes: mostly steady, with the odd stutter.
	for f in _flicker:
		var l: OmniLight3D = f[0]
		var n := sin(_time * f[3] + f[2]) * sin(_time * f[3] * 2.7 + f[2] * 1.9)
		l.light_energy = f[1] * (0.25 if n > 0.93 else (0.9 + 0.1 * sin(_time * 31.0 + f[2])))
	if _beacon != null:
		var bl := 1.0 if fmod(_time, 1.6) < 0.25 else 0.08
		_beacon.emission_energy_multiplier = 6.0 * bl
	for r in _rotors:
		(r as Node3D).rotate_object_local(Vector3.FORWARD, delta * 0.9)
	if _blimp != null:
		var ba := _time * 0.012
		_blimp.position = Vector3(cos(ba) * 230.0, 75.0, sin(ba) * 230.0)
		_blimp.rotation.y = -ba
	# Water ripples drift.
	if _mats.has("water"):
		_water_t += delta
		var wm: StandardMaterial3D = _mats.water
		wm.uv1_offset = Vector3(_water_t * 0.02, _water_t * 0.013, 0)
	for r in _pad_rings:
		var t := fmod(_time * 0.8 + r[2], 1.0)
		r[0].position.y = 0.15 + t * 1.6
		r[0].scale = Vector3.ONE * (1.0 - t * 0.35)
		r[1].albedo_color.a = (1.0 - t) * 0.8


func _physics_process(delta: float) -> void:
	for area in _hazards:
		for body in area.get_overlapping_bodies():
			if body.has_method("take_damage") and body.alive:
				body.take_damage(LAVA_DPS * delta, null, true)
				body.hurt_flash = maxf(body.hurt_flash, 0.6)


## Song for this map (a key of sfx.gd TRACKS).
func music_key() -> String:
	if map_index == FRONTLINE:
		return "frontline"
	if map_index == HIGHTOWN:
		return "castle"
	if map_index == RACEWAY:
		return "frontline"
	if map_index == ZOMBIE:
		return "zombies"
	return "castle" if map_index == CASTLE else "map%d" % map_index


func label() -> String:
	return "%s  -  %s" % [MAPS[map_index].name, look.get("name", time.to_upper())]


# --------------------------------------------------------------------------
# Lighting, time of day, weather
# --------------------------------------------------------------------------

func _build_environment() -> void:
	var night: Dictionary = theme.night
	var p := {}
	var sky: Dictionary = night.sky.duplicate()
	if time == "night":
		p = {"sun_color": night.sun_color, "sun_energy": night.sun_energy * 1.7, "sun_pitch": -48.0,
			"ambient": night.ambient * 7.2, "exposure": 1.55, "glow": 1.15, "neon": 1.0, "lights": 1.0,
			"fog": night.fog, "fog_mult": 1.0}
		night_amount = 1.0
	else:
		var preset: Dictionary = DAY if time == "day" else SUNSET
		p = preset.duplicate()
		sky = preset.sky.duplicate()
		night_amount = 0.0 if time == "day" else 0.45
		var over: Dictionary = theme.get(time, {})
		for k in over:
			if k == "sky":
				for sk in over.sky:
					sky[sk] = over.sky[sk]
			else:
				p[k] = over[k]
	# The visual theme has the last word on sky and light.
	for k in look:
		if k == "sky":
			for sk in look.sky:
				sky[sk] = look.sky[sk]
		elif p.has(k):
			p[k] = look[k]
	# Indoor maps have their own lamps: a theme's (night) ambient would wash
	# them out.
	if indoor and look.has("ambient"):
		p.ambient *= 0.7
	var fog_density: float = night.fog_density * p.fog_mult
	var fog_col: Color = p.fog
	var dim := 0.2 if time == "night" else 1.0
	match weather:
		"rain":
			sky.clouds = 1.0
			sky.cloud_color = sky.cloud_color * 0.6
			sky.stars = 0.0
			p.sun_energy *= 0.45
			p.ambient *= 0.8
			fog_density *= 2.5
			fog_col = fog_col.lerp(Color(0.35, 0.38, 0.42) * dim, 0.5)
		"fog":
			sky.clouds = 0.9
			p.sun_energy *= 0.6
			fog_density = maxf(fog_density * 3.0, 0.009)
			fog_col = fog_col.lerp(Color(0.6, 0.62, 0.66) * dim, 0.5)
		"snow":
			sky.clouds = 0.95
			sky.stars *= 0.3
			p.sun_energy *= 0.6
			fog_density *= 2.0
			fog_col = fog_col.lerp(Color(0.75, 0.8, 0.88) * dim, 0.4)
	# Keep map silhouettes and player colours readable in every time/weather
	# combination; the atmosphere comes from hue and lights rather than crushed
	# shadows.
	p.ambient = maxf(p.ambient, 1.0)
	fog_density = minf(fog_density, 0.012)
	# A slight distance haze gives the large outdoor arenas more depth without
	# obscuring players or landmarks.
	if half_x >= 44.0:
		fog_density = maxf(fog_density, 0.0035)
	elif not indoor:
		# A little haze on the smaller outdoor maps too, so the scenery beyond
		# the walls sits back in the distance.
		fog_density = maxf(fog_density, 0.0028)
	light_scale = p.lights
	neon_scale = p.neon

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = SkyKit.make(sky)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = p.ambient
	if look.has("ambient_color"):
		env.ambient_light_color = look.ambient_color
		env.ambient_light_sky_contribution = 0.5
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = p.exposure
	env.tonemap_white = 4.0
	env.ssao_enabled = true
	env.ssao_radius = 2.2
	env.ssao_intensity = 1.1
	env.ssao_power = 1.2
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_strength = 1.0
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = p.glow
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.set_glow_level(2, 1.0)
	env.set_glow_level(4, 0.7)
	env.set_glow_level(6, 0.25)
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08 if time == "sunset" else 1.24
	env.adjustment_contrast = 1.0
	env.adjustment_brightness = 1.04
	env.fog_enabled = true
	env.fog_light_color = fog_col
	env.fog_density = fog_density
	env.fog_sky_affect = 0.35 if weather == "fog" else 0.0
	Looks.apply_post(look, env)
	# Light shafts (Settings "volfog"): a thin haze the sun and lamps cut
	# through, tinted like the fog. Kept thin so players stay readable.
	env.set_meta("volfog_density", look.get("volfog", 0.012 if indoor else 0.007))
	env.set_meta("volfog_albedo", fog_col.lerp(Color(0.85, 0.85, 0.9), 0.5))
	# Wet themes: screen-space reflections in the puddles (Settings decides).
	env.set_meta("ssr", float(look.get("wet", 0.0)) > 0.0 and not indoor)
	# Low mist pooling in the bottom metre or so (night themes).
	if float(look.get("mist", 0.0)) > 0.0 and not indoor:
		env.fog_height = 1.2
		env.fog_height_density = float(look.mist)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(p.sun_pitch, theme.sun_yaw, 0)
	sun.light_color = p.sun_color
	sun.light_energy = p.sun_energy
	sun.shadow_enabled = true
	sun.shadow_blur = 2.6
	sun.shadow_opacity = look.get("shadow", 0.72)
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 90.0
	sun.shadow_bias = 0.06
	add_child(sun)
	_env = env
	_sun = sun
	_reflection_probe()
	_on_settings()
	Settings.changed.connect(_on_settings)


func _on_settings() -> void:
	Settings.apply_environment(_env, _sun)


func _beacon_mat() -> StandardMaterial3D:
	if _beacon == null:
		_beacon = StandardMaterial3D.new()
		_beacon.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_beacon.albedo_color = Color(1.0, 0.15, 0.1)
		_beacon.emission_enabled = true
		_beacon.emission = Color(1.0, 0.1, 0.05)
	return _beacon


## Life on the horizon (outdoor maps): wind turbines turning slowly on
## the hills, and a blimp drifting round the arena far out (lit at night).
func _set_pieces() -> void:
	if indoor or Settings.v("scenery") == 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 909 + map_index
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.92, 0.93, 0.95) if time != "night" else Color(0.3, 0.32, 0.38)
	white.roughness = 0.6
	var r0 := maxf(half_x, half_z) + 140.0
	if not theme.get("neon", false):
		var tower := CylinderMesh.new()
		tower.top_radius = 0.9
		tower.bottom_radius = 1.6
		tower.height = 46.0
		tower.radial_segments = 10
		var blade := BoxMesh.new()
		blade.size = Vector3(1.2, 20.0, 0.4)
		var hub := BoxMesh.new()
		hub.size = Vector3(2.2, 2.2, 5.0)
		var n := 6
		for i in n:
			var a := TAU * (i + rng.randf_range(-0.25, 0.25)) / n + 0.4
			var d := r0 + rng.randf_range(0.0, 90.0)
			var base := Vector3(cos(a) * d, 0.0, sin(a) * d)
			var t := Node3D.new()
			t.position = base
			t.rotation.y = rng.randf() * TAU
			add_child(t)
			for spec in [[tower, Vector3(0, 23.0, 0)], [hub, Vector3(0, 46.5, 0.8)]]:
				var mi := MeshInstance3D.new()
				mi.mesh = spec[0]
				mi.material_override = white
				mi.position = spec[1]
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				t.add_child(mi)
			var rotor := Node3D.new()
			rotor.position = Vector3(0, 46.5, -1.9)
			rotor.rotation.z = rng.randf() * TAU
			t.add_child(rotor)
			for k in 3:
				var bm := MeshInstance3D.new()
				bm.mesh = blade
				bm.material_override = white
				bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				var arm := Basis(Vector3.FORWARD, TAU * k / 3.0)
				bm.transform = Transform3D(arm, arm * Vector3(0, 10.0, 0))
				rotor.add_child(bm)
			_rotors.append(rotor)
	# The blimp.
	_blimp = Node3D.new()
	add_child(_blimp)
	var body := MeshInstance3D.new()
	body.mesh = _unit_sphere
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = theme.accent_a.lerp(Color(0.85, 0.85, 0.9), 0.55)
	bmat.roughness = 0.5
	body.material_override = bmat
	body.scale = Vector3(7.0, 6.5, 22.0)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_blimp.add_child(body)
	for f in [[Vector3(0, 4.5, 17.0), Vector3(0.4, 5.0, 4.0)], [Vector3(4.5, 0, 17.0), Vector3(5.0, 0.4, 4.0)], [Vector3(-4.5, 0, 17.0), Vector3(5.0, 0.4, 4.0)]]:
		var fin := MeshInstance3D.new()
		var fb := BoxMesh.new()
		fb.size = f[1]
		fin.mesh = fb
		fin.material_override = bmat
		fin.position = f[0]
		_blimp.add_child(fin)
	var band := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 7.05
	cyl.bottom_radius = 7.05
	cyl.height = 2.0
	band.mesh = cyl
	band.rotation.x = PI / 2
	band.scale = Vector3(1.0, 1.0, 0.93)
	band.material_override = _neon(theme.accent_b, 1.2 + 2.5 * night_amount)
	_blimp.add_child(band)
	_blimp.position = Vector3(230.0, 75.0, 0.0)


## Posters and graffiti on the long perimeter walls (decals): the place has
## been lived in. Graffiti in neon, ruined and street themes; posters
## everywhere else; nothing on low fences.
func _wall_art() -> void:
	if wall_h < 2.4 or not Settings.v("decals") or Settings.v("scenery") == 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 313 + map_index
	var n := clampi(int((half_x + half_z) / 7.0), 4, 14)
	for i in n:
		var graffiti := rng.randf() < 0.55
		var on_x := rng.randf() < half_x / (half_x + half_z)
		var u := rng.randf_range(-0.85, 0.85)
		var sgn := 1.0 if rng.randf() < 0.5 else -1.0
		var size := Vector2(rng.randf_range(2.2, 3.6), rng.randf_range(1.2, 1.9)) if graffiti else Vector2(0.9, 1.3)
		var y := (rng.randf_range(0.9, 1.6) if graffiti else rng.randf_range(1.4, 1.9))
		var pos: Vector3
		var normal: Vector3
		if on_x:
			pos = Vector3(u * half_x, y, sgn * (half_z - 0.02))
			normal = Vector3(0, 0, -sgn)
		else:
			pos = Vector3(sgn * (half_x - 0.02), y, u * half_z)
			normal = Vector3(-sgn, 0, 0)
		var d := Decal.new()
		d.texture_albedo = Fx.art_texture(("tag%d" if graffiti else "poster%d") % rng.randi_range(0, 2))
		d.size = Vector3(size.x, 0.4, size.y)
		d.cull_mask = 1
		d.upper_fade = 0.2
		d.lower_fade = 0.2
		d.distance_fade_enabled = true
		d.distance_fade_begin = 45.0
		d.distance_fade_length = 10.0
		var x_axis := normal.cross(Vector3.UP).normalized()
		d.transform = Transform3D(Basis(x_axis, normal, x_axis.cross(normal)), pos)
		add_child(d)


## Drifting specks in the air, one kind per theme: pollen and dandelion
## fluff by day, embers at sunset, fireflies at night, neon dust in the
## neon themes, dust motes indoors. GPU particles over the whole arena:
## nearly free, and they make the air feel alive.
func _ambient_life() -> void:
	if Settings.v("scenery") == 0:
		return
	var key: String = look.get("key", "classic")
	var col := Color(1.0, 1.0, 0.95, 0.7)
	var glow := 0.0
	var size := 0.05
	var speed := 0.25
	match key:
		"toy":
			col = Color(1.0, 0.85, 0.95, 0.8)
			size = 0.07
		"warm":
			col = Color(1.0, 0.62, 0.25, 1.0)
			glow = 2.5
			size = 0.04
			speed = 0.45
		"cyberpunk", "synthwave":
			col = theme.accent_b if randf() < 0.5 else theme.accent_a
			glow = 3.0
			size = 0.035
			speed = 0.35
		"spooky":
			col = Color(0.7, 1.0, 0.3, 1.0)
			glow = 4.0
			size = 0.06
		"moonlit":
			col = Color(1.0, 0.9, 0.5, 1.0)
			glow = 3.5
			size = 0.05
	if indoor:
		col = Color(1.0, 0.95, 0.85, 0.45)
		glow = 0.0
		size = 0.03
		speed = 0.08
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	var hy := 3.5 if indoor else 5.0
	pm.emission_box_extents = Vector3(half_x, hy, half_z)
	pm.direction = Vector3(0.3, 0.2, 0.1)
	pm.spread = 180.0
	pm.initial_velocity_min = speed * 0.3
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, 0.02 if glow > 0.0 else -0.03, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 6.0
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.15
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	var fade := Curve.new()
	fade.add_point(Vector2(0, 0))
	fade.add_point(Vector2(0.15, 1))
	fade.add_point(Vector2(0.85, 1))
	fade.add_point(Vector2(1, 0))
	var ft := CurveTexture.new()
	ft.curve = fade
	pm.scale_curve = ft
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	glow *= 0.5
	mat.albedo_color = Color(col.r * (1.0 + glow), col.g * (1.0 + glow), col.b * (1.0 + glow), col.a * 0.8)
	if glow > 0.0:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 32
	tex.height = 32
	mat.albedo_texture = tex
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	quad.material = mat
	# Only specks near you show: far ones fade out (they flickered against the
	# soft-focus background and read as flashing).
	mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	mat.distance_fade_min_distance = 14.0
	mat.distance_fade_max_distance = 5.0
	var p := GPUParticles3D.new()
	p.amount = clampi(int(half_x * half_z * 0.05), 60, 260)
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.process_material = pm
	p.draw_pass_1 = quad
	p.position = Vector3(0, hy + 0.3, 0)
	p.visibility_aabb = AABB(Vector3(-half_x - 4, -hy - 4, -half_z - 4), Vector3(half_x * 2 + 8, hy * 2 + 8, half_z * 2 + 8))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)


## Ground dressing: soft dirt, scuff and crack decals scattered over open
## floor so big surfaces do not read as one repeating tile.
func _ground_decals() -> void:
	if Settings.v("scenery") == 0 or not Settings.v("decals"):
		return
	var n := clampi(int(half_x * half_z * 0.012), 10, 44)
	var placed := 0
	var tries := 0
	while placed < n and tries < n * 6:
		tries += 1
		var px := _rng.randf_range(-half_x + 2.0, half_x - 2.0)
		var pz := _rng.randf_range(-half_z + 2.0, half_z - 2.0)
		var y := ground_y(px, pz)
		var d := Decal.new()
		var dirt := _rng.randf() < 0.7
		d.texture_albedo = Fx.grime_texture() if dirt else Fx.crack_texture()
		var sz := _rng.randf_range(2.5, 6.0) if dirt else _rng.randf_range(1.2, 2.4)
		d.size = Vector3(sz, 1.2, sz * _rng.randf_range(0.6, 1.0))
		d.position = Vector3(px, y, pz)
		d.rotation.y = _rng.randf() * TAU
		d.modulate = Color(0.25, 0.2, 0.16, _rng.randf_range(0.25, 0.45)) if dirt else Color(0.1, 0.1, 0.12, 0.55)
		d.cull_mask = 1
		d.upper_fade = 0.5
		d.lower_fade = 0.5
		d.distance_fade_enabled = true
		d.distance_fade_begin = 40.0
		d.distance_fade_length = 10.0
		add_child(d)
		placed += 1


## What a bullet hit at `pos` is made of, for the impact effect: "stone",
## "wood", "metal", "snow" or "dirt". Floors use the lawns and the map's
## ground material; walls the map's wall material.
func surface_kind(pos: Vector3, normal: Vector3) -> String:
	var kind := ""
	if normal.y > 0.6:
		for r in lawns:
			if (r as Rect2).has_point(Vector2(pos.x, pos.z)):
				return "dirt"
		kind = theme.mats.ground[1]
		if theme.get("cover", false) and not indoor and pos.y < 0.3:
			return "dirt"
	else:
		kind = theme.mats.get("wall", ["", "concrete"])[1]
	match kind:
		"planks", "siding", "shingles":
			return "wood"
		"plates", "corrugated":
			return "metal"
		"snow", "ice":
			return "snow"
		"lawn", "turf", "soft":
			return "dirt"
	return "stone"


## One box-projected reflection probe over the arena, rendered once: glass,
## water, metal and glossy floors reflect the level instead of only the sky.
func _reflection_probe() -> void:
	var probe := ReflectionProbe.new()
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	var hy := maxf(wall_h, 10.0)
	probe.size = Vector3(half_x * 2.0 + 4.0, hy * 2.0, half_z * 2.0 + 4.0)
	probe.position = Vector3(0, hy * 0.5, 0)
	probe.origin_offset = Vector3(0, 2.5 - hy * 0.5, 0)
	probe.box_projection = true
	probe.interior = indoor
	probe.intensity = 0.7
	probe.max_distance = maxf(half_x, half_z) * 2.5
	probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	probe.mesh_lod_threshold = 4.0
	add_child(probe)


## Unit vector pointing at the sun (or moon), and its colour (sun_rays.gd).
func sun_direction() -> Vector3:
	return _sun.global_transform.basis.z.normalized()


func sun_color() -> Color:
	return _sun.light_color.lerp(Color(1.0, 0.92, 0.75), 0.35)


## Lightning during rain: a brief flash of the ambient light.
func flash_lightning() -> void:
	var base := _env.ambient_light_energy
	var tw := create_tween()
	tw.tween_property(_env, "ambient_light_energy", base * 4.0, 0.05)
	tw.tween_property(_env, "ambient_light_energy", base, 0.35)


## A coloured point light with no shadows, scaled for the time of day.
func _glow(pos: Vector3, col: Color, radius := 8.0, energy := 1.6, mirror := true) -> void:
	if light_scale * energy < 0.05:
		return
	for s in ([pos, Vector3(-pos.x, pos.y, -pos.z)] if mirror else [pos]):
		var l := OmniLight3D.new()
		l.position = s
		l.light_color = col
		l.light_energy = energy * 0.8 * light_scale
		l.omni_range = radius
		l.omni_attenuation = 1.6
		add_child(l)
		# Neon themes: about one coloured light in four buzzes and stutters.
		if neon_scale > 1.2 and _rng.randf() < 0.25:
			_flicker.append([l, l.light_energy, _rng.randf() * TAU, _rng.randf_range(0.6, 1.4)])


# --------------------------------------------------------------------------
# Materials and textures
# --------------------------------------------------------------------------

func _make_materials() -> void:
	var wet: bool = weather == "rain" and not indoor
	for key in theme.mats:
		var d: Array = theme.mats[key]
		# Containers, crates and cars keep object-space mapping (no parallax).
		var local: bool = key.begins_with("c_") or key == "crate" or key.begins_with("car_")
		var m: Material = _mat(d[0], d[1], d[2], d[3], d[4], not local)
		if m is StandardMaterial3D:
			if wet:
				m.roughness *= 0.45
			if local:
				m.uv1_world_triplanar = false
		_mats[key] = m
	if not _mats.has("lava"):
		_mats["lava"] = _mat(Color(0.32, 0.11, 0.05), "lava", 0.18, 0.6, 0.0)
	if not _mats.has("trunk"):
		_mats["trunk"] = _mat(Color(0.3, 0.21, 0.14), "rock", 0.8, 0.9, 0.0)
	_mats["dark"] = _mat(Color(0.06, 0.06, 0.09), "", 1.0, 0.5, 0.3)
	_mats["accent_a"] = _neon(theme.accent_a, 1.7 * neon_scale)
	_mats["accent_b"] = _neon(theme.accent_b, 1.7 * neon_scale)
	_mats["rail"] = _neon(theme.accent_b, 0.9 * neon_scale)
	_mats["pad"] = _neon(Color(0.3, 1.0, 0.85), 2.0 * maxf(neon_scale, 0.6))
	_mats["beacon"] = _neon(Color(1.0, 0.2, 0.2), 3.0)
	_mats["lamp"] = _neon(look.get("lamp", Color(1.0, 0.86, 0.6)), 0.4 + 3.2 * night_amount)
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.6, 0.8, 0.9, 0.18)
	glass.roughness = 0.05
	glass.metallic = 0.4
	glass.rim_enabled = true
	_mats["glass"] = glass
	var window := StandardMaterial3D.new()
	window.albedo_color = Color(0.12, 0.16, 0.22)
	window.roughness = 0.1
	window.metallic = 0.5
	window.emission_enabled = night_amount > 0.0
	window.emission = look.get("window", Color(1.0, 0.78, 0.45))
	window.emission_energy_multiplier = 1.6 * night_amount
	_mats["window"] = window
	var water := StandardMaterial3D.new()
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.albedo_color = Color(0.15, 0.5, 0.65, 0.55)
	# Not mirror-smooth: a near-zero roughness on rippling normals made the
	# sun's highlight sparkle and flash across the pools.
	water.roughness = 0.22
	water.metallic = 0.0
	# Rippling surface: a seamless noise normal map that drifts (_process).
	var wn := NoiseTexture2D.new()
	wn.seamless = true
	wn.as_normal_map = true
	wn.bump_strength = 6.0
	wn.width = 256
	wn.height = 256
	var wnoise := FastNoiseLite.new()
	wnoise.frequency = 0.02
	wn.noise = wnoise
	water.normal_enabled = true
	water.normal_texture = wn
	water.normal_scale = 0.25
	water.uv1_triplanar = true
	water.uv1_world_triplanar = true
	water.uv1_scale = Vector3.ONE * 0.12
	_mats["water"] = water
	for i in 2:
		_mats["leaf%d" % i] = Voxel.from_standard(_leaf_mat(theme.leaf[i])) if Voxel.on else _leaf_mat(theme.leaf[i])
	var st: Array = _tex("stripes")
	var stripes := StandardMaterial3D.new()
	stripes.albedo_color = theme.accent_a.lerp(Color.WHITE, 0.15)
	stripes.albedo_texture = st[0]
	stripes.roughness = 0.5
	stripes.uv1_triplanar = true
	stripes.uv1_world_triplanar = true
	stripes.uv1_scale = Vector3.ONE * 0.7
	stripes.emission_enabled = true
	stripes.emission = theme.accent_a
	stripes.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	stripes.emission_texture = st[0]
	stripes.emission_energy_multiplier = 0.7 * neon_scale
	_mats["stripes"] = stripes


## Toy-diorama surfaces: clean, slightly pastel colours, matte, with soft
## wrapped lighting and a faint rim sheen; the procedural textures are
## flattened (_soft) and their normal maps turned down so walls read as
## painted clay rather than gritty photo-noise.
func _mat(tint: Color, kind: String, uv_scale: float, rough: float, metal: float, depth_ok := true) -> Material:
	var m := StandardMaterial3D.new()
	tint = Looks.grade(look, tint)
	var toy := Color.from_hsv(tint.h, minf(1.0, tint.s * 1.12), minf(1.0, tint.v * 1.06 + 0.03), tint.a)
	if depth_ok and Surface.DEPTH.has(kind) and Settings.v("parallax"):
		# Parallax occlusion surfaces (surface.gd): grooves with real depth.
		var tx: Array = _tex(kind)
		var sm := Surface.make(toy.lerp(Color.WHITE, 0.06), _soft(kind, tx[0]) if tx[2] == null and kind != "lawn" else tx[0], tx[1], tx[3], tx[2],
			uv_scale, Surface.DEPTH[kind], maxf(rough, 0.62) if metal < 0.5 else rough, metal * 0.6)
		sm.set_shader_parameter("weather", 0.6 if indoor else 1.0)
		if not indoor:
			sm.set_shader_parameter("wet", float(look.get("wet", 0.0)))
		return sm
	if Voxel.on:
		# The voxel style (voxel.gd) for plain and textured surfaces alike.
		var vt: Array = _tex(kind) if kind != "" else [null, null, null]
		var alb: Texture2D = null
		if vt[0] != null:
			alb = _soft(kind, vt[0]) if vt[2] == null else vt[0]
		return Voxel.plain(toy.lerp(Color.WHITE, 0.06), alb, uv_scale, maxf(rough, 0.62) if metal < 0.5 else rough, metal * 0.6, vt[2], 2.4)
	m.albedo_color = toy.lerp(Color.WHITE, 0.06)
	m.roughness = maxf(rough, 0.62) if metal < 0.5 else rough
	m.metallic = metal * 0.6
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	m.rim_enabled = true
	m.rim = 0.22
	m.rim_tint = 0.6
	if kind == "":
		return m
	var t: Array = _tex(kind)
	m.albedo_texture = _soft(kind, t[0]) if t[2] == null else t[0]
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * uv_scale
	if t[1] != null:
		m.normal_enabled = true
		m.normal_texture = t[1]
		m.normal_scale = 0.5
	if t[2] != null:
		m.emission_enabled = true
		m.emission_texture = t[2]
		m.emission_energy_multiplier = 2.4
	return m


static var _soft_cache := {}

## A lower-contrast copy of a generated albedo texture: every pixel is pulled
## 45 % of the way to the texture's average colour.
static func _soft(kind: String, tex: Texture2D) -> Texture2D:
	if _soft_cache.has(kind):
		return _soft_cache[kind]
	var img: Image = tex.get_image()
	if img == null:
		return tex
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var tiny: Image = img.duplicate()
	tiny.resize(1, 1, Image.INTERPOLATE_LANCZOS)
	var avg := tiny.get_pixel(0, 0)
	var flat := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	flat.fill(Color(avg.r, avg.g, avg.b, 0.45))
	img.blend_rect(flat, Rect2i(0, 0, img.get_width(), img.get_height()), Vector2i.ZERO)
	img.generate_mipmaps()
	var out := ImageTexture.create_from_image(img)
	_soft_cache[kind] = out
	return out


func _leaf_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.85
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	m.rim_enabled = true
	m.rim = 0.35
	m.backlight_enabled = true
	m.backlight = col.lightened(0.2) * 0.6
	var t: Array = _tex("leaves")
	m.albedo_texture = t[0]
	m.normal_enabled = true
	m.normal_texture = t[1]
	m.normal_scale = 1.4
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 1.4
	return m


## Emissive strip material: this is what the bloom picks up.
func _neon(col: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col.darkened(0.3)
	m.roughness = 0.4
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	return m


## Tileable 256x256 detail textures. Returns [albedo, normal, emission]; the
## albedo is greyscale and gets multiplied by the material colour. Cached for
## the whole session, so only the first match using a kind pays for it.
static func _tex(kind: String) -> Array:
	if _tex_cache.has(kind):
		return _tex_cache[kind]
	const N := 256
	const P := 16
	const G := 5
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	var lattice := PackedFloat32Array()
	lattice.resize(P * P)
	for i in P * P:
		lattice[i] = rng.randf()
	var noise := func(u: float, v: float, freq: int) -> float:
		var x := u * freq
		var y := v * freq
		var x0 := int(floor(x))
		var y0 := int(floor(y))
		var fx := x - x0
		var fy := y - y0
		fx = fx * fx * (3.0 - 2.0 * fx)
		fy = fy * fy * (3.0 - 2.0 * fy)
		var a := lattice[(y0 % freq) * P + (x0 % freq)]
		var b := lattice[(y0 % freq) * P + ((x0 + 1) % freq)]
		var c := lattice[((y0 + 1) % freq) * P + (x0 % freq)]
		var d := lattice[((y0 + 1) % freq) * P + ((x0 + 1) % freq)]
		return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)
	var cellular := kind in ["rock", "lava", "ice", "leaves"]
	var seeds := PackedVector2Array()
	for i in G * G:
		seeds.append(Vector2(rng.randf(), rng.randf()))

	var img := Image.create(N, N, true, Image.FORMAT_RGB8)
	var himg := Image.create(N, N, false, Image.FORMAT_RGB8)
	var eimg: Image = null
	if kind == "lava":
		eimg = Image.create(N, N, true, Image.FORMAT_RGB8)
	for py in N:
		for px in N:
			var u := float(px) / N
			var v := float(py) / N
			var n: float = noise.call(u, v, 4) * 0.65 + noise.call(u, v, 8) * 0.35
			var val := 0.82 + n * 0.18
			var hgt := 0.6 + n * 0.4
			var edge := 1.0
			var cell_id := 0
			if cellular:
				var gx := u * G
				var gy := v * G
				var d1 := 9.0
				var d2 := 9.0
				for oy in [-1, 0, 1]:
					for ox in [-1, 0, 1]:
						var cx: int = int(floor(gx)) + ox
						var cy: int = int(floor(gy)) + oy
						var id := posmod(cy, G) * G + posmod(cx, G)
						var d := Vector2(gx, gy).distance_to(Vector2(cx, cy) + seeds[id])
						if d < d1:
							d2 = d1
							d1 = d
							cell_id = id
						elif d < d2:
							d2 = d
				edge = d2 - d1
			match kind:
				"concrete":
					val = 0.76 + n * 0.24 - 0.07 * noise.call(u, v, 16)
					if px % 128 < 2 or py % 128 < 2:
						val *= 0.75
						hgt = 0.0
				"plates":
					var lx := px % 128
					var ly := py % 128
					if lx < 3 or ly < 3:
						val *= 0.55
						hgt = 0.0
					else:
						hgt = 0.7
						for corner in [Vector2(14, 14), Vector2(114, 14), Vector2(14, 114), Vector2(114, 114)]:
							if Vector2(lx, ly).distance_to(corner) < 4.5:
								val *= 1.25
								hgt = 1.0
				"corrugated":
					var ridge := 0.5 + 0.5 * sin(u * TAU * 16.0)
					val = 0.6 + 0.4 * ridge + n * 0.06
					hgt = ridge
					if py % 128 < 3:
						val *= 0.6
						hgt = 0.0
				"planks":
					var plank := py / 32
					val *= 0.82 + 0.18 * lattice[plank % (P * P)]
					hgt = 0.7 + 0.3 * n
					if py % 32 < 3 or (px + plank * 67) % 128 < 3:
						val *= 0.55
						hgt = 0.0
				"bricks":
					var row := py / 32
					var bx := (px + (row % 2) * 32) % 64
					val *= 0.8 + 0.2 * lattice[(row * 5 + ((px + (row % 2) * 32) / 64) * 3) % (P * P)]
					hgt = 0.75 + 0.25 * n
					if py % 32 < 3 or bx < 3:
						val *= 0.5
						hgt = 0.0
				"tiles":
					var tx := px % 64
					var ty := py % 64
					val = 0.78 + 0.16 * lattice[((py / 64) * 7 + (px / 64) * 3) % (P * P)] + 0.06 * ((px / 64 + py / 64) % 2)
					hgt = 0.8
					if tx < 3 or ty < 3:
						val *= 0.5
						hgt = 0.0
				"rock":
					val = 0.6 + 0.3 * lattice[cell_id % (P * P)] + n * 0.14
					hgt = clampf(edge * 3.0, 0.0, 1.0)
					if edge < 0.05:
						val *= 0.5
				"lava":
					var glow := 1.0 - smoothstep(0.0, 0.16, edge)
					val = 0.5 + 0.3 * n
					hgt = clampf(edge * 3.0, 0.0, 1.0)
					eimg.set_pixel(px, py, Color(1.0, 0.42 + 0.3 * glow, 0.08) * (glow + 0.06))
				"snow":
					val = 0.86 + n * 0.14
					hgt = n
				"ice":
					val = 0.8 + 0.14 * n
					hgt = 0.8
					if edge < 0.03:
						val = 1.0
						hgt = 0.0
				"marble":
					var vein := absf(sin((u * 3.0 + v * 1.5 + n * 2.2) * PI))
					val = 0.9 + 0.1 * n
					if vein < 0.05:
						val *= 0.72
					hgt = 0.9
					if px % 128 < 2 or py % 128 < 2:
						val *= 0.7
						hgt = 0.0
				"plaster":
					val = 0.9 + 0.1 * n - 0.04 * noise.call(u, v, 16)
					hgt = n
				"asphalt":
					val = 0.55 + 0.25 * n + rng.randf_range(-0.12, 0.12)
					hgt = 0.5 + 0.5 * rng.randf()
				"rubber":
					val = 0.8 + 0.12 * n + rng.randf_range(-0.08, 0.08)
					hgt = 0.6 + 0.4 * rng.randf()
				"turf":
					val = 0.82 + 0.12 * float((px / 64) % 2) + n * 0.08
					hgt = 0.5 + 0.3 * rng.randf()
				"lawn":
					# Clumpy turf with patches of bare soil, so the ground under
					# the grass reads as ground, not a flat green sheet.
					var clump: float = noise.call(u, v, 16)
					var soil: float = smoothstep(0.42, 0.3, n)
					val = (0.62 + 0.22 * n + 0.2 * clump + rng.randf_range(-0.05, 0.05)) * (1.0 - 0.35 * soil)
					hgt = clampf(0.3 + 0.55 * clump - 0.25 * soil, 0.0, 1.0)
				"soft":
					val = 0.7 + 0.3 * n
					hgt = n
				"shingles":
					var srow := py / 32
					var sx := (px + (srow % 2) * 24) % 48
					val = 0.7 + 0.25 * lattice[(srow * 3 + (px + (srow % 2) * 24) / 48) % (P * P)] + float(py % 32) / 32.0 * 0.1
					hgt = float(py % 32) / 32.0
					if sx < 2 or py % 32 < 3:
						val *= 0.55
						hgt = 0.0
				"siding":
					var t := float(py % 24) / 24.0
					val = 0.8 + 0.12 * t + n * 0.06
					hgt = t
					if py % 24 < 2:
						val *= 0.6
				"leaves":
					val = 0.65 + 0.35 * lattice[cell_id % (P * P)]
					hgt = clampf(edge * 4.0, 0.0, 1.0)
				"stripes":
					val = 1.0 if ((px + py) % 128) < 52 else 0.05
			val = clampf(val, 0.0, 1.0)
			img.set_pixel(px, py, Color(val, val, val))
			himg.set_pixel(px, py, Color(hgt, hgt, hgt))
	img.generate_mipmaps()
	# The height field itself, for parallax (surface.gd), before it becomes
	# the normal map.
	var hcopy: Image = himg.duplicate()
	hcopy.convert(Image.FORMAT_L8)
	hcopy.generate_mipmaps()
	var height := ImageTexture.create_from_image(hcopy)
	var normal: ImageTexture = null
	if kind != "stripes":
		himg.bump_map_to_normal_map(2.5 if kind in ["snow", "concrete", "plaster", "lawn", "turf"] else 5.0)
		himg.generate_mipmaps(true)
		normal = ImageTexture.create_from_image(himg)
	var emission: ImageTexture = null
	if eimg != null:
		eimg.generate_mipmaps()
		emission = ImageTexture.create_from_image(eimg)
	var out := [ImageTexture.create_from_image(img), normal, emission, height]
	_tex_cache[kind] = out
	return out


# --------------------------------------------------------------------------
# Static mesh batching
# --------------------------------------------------------------------------

## Queue a static mesh. Meshes sharing a material are merged at _flush().
## Primitive meshes and our own ArrayMeshes have different vertex formats, so
## they go into separate batches.
func _add(mesh: Mesh, mat: Material, xf: Transform3D, shadow := true, surface := 0, kind := "") -> void:
	# The voxel style for every remaining plain material (hills, horizon,
	# pieces built with their own StandardMaterial3D); see-through and
	# unshaded ones stay as they are (Voxel.from_standard).
	if Voxel.on and mat is BaseMaterial3D and (mat as BaseMaterial3D).shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
		mat = Voxel.from_standard(mat)
	if kind == "":
		kind = "p" if mesh is PrimitiveMesh else "c"
	var key := "%d_%s_%s" % [mat.get_instance_id() if mat != null else 0, kind, shadow]
	# Big maps: batch per 40 m chunk too, so cameras and shadow passes can
	# cull the parts of the map they cannot see.
	if half_x > 60.0 and absf(xf.origin.x) < half_x + 2.0 and absf(xf.origin.z) < half_z + 2.0:
		key += "_%d_%d" % [floori(xf.origin.x / CHUNK), floori(xf.origin.z / CHUNK)]
	if not _batches.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batches[key] = [mat, shadow, st]
	_batches[key][2].append_from(mesh, surface, xf)


## Voxel models (voxelizer.gd) are instanced: one MultiMesh per model per
## VOX_CHUNK square and detail level (merging them all into one atlas was
## tried: no faster to draw, and much slower to load).
var _vox_batches := {}


## lod 0 = full detail (drawn up to Voxelizer.FAR_FROM), 1 = the coarse
## far version (drawn beyond). Batches are per VOX_CHUNK square on every map,
## so the distance switch works per neighbourhood.
const VOX_CHUNK := 40.0


## vx: Voxelizer.model() result [mesh, material, key, data].
func _add_vox(vx: Array, xf: Transform3D, shadow: bool, lod: int, _sway: bool) -> void:
	var key := "%s_%s_%d_%d_%d" % [vx[2], shadow, lod, floori(xf.origin.x / VOX_CHUNK), floori(xf.origin.z / VOX_CHUNK)]
	if not _vox_batches.has(key):
		_vox_batches[key] = [vx[0], vx[1], shadow, lod, []]
	_vox_batches[key][4].append(xf)


func _flush() -> void:
	_lay_surfaces()   # any decal added after _build_floor
	if "--clutter" in OS.get_cmdline_user_args():
		print("[clutter] batches: %d merged, %d voxel batches" % [_batches.size(), _vox_batches.size()])
	_flush_vox()
	for key in _batches:
		var b: Array = _batches[key]
		var mi := MeshInstance3D.new()
		mi.mesh = b[2].commit()
		mi.material_override = b[0]
		if not b[1]:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	_batches.clear()


func _flush_vox() -> void:
	if "--clutter" in OS.get_cmdline_user_args():
		print("[clutter] %d voxel multimeshes" % _vox_batches.size())
	for key in _vox_batches:
		var vb: Array = _vox_batches[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = vb[0]
		var xfs: Array = vb[4]
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = vb[1]
		if not vb[2]:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif vb[3] == 1:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		add_child(mmi)
	_vox_batches.clear()


func _glows(mat: String) -> bool:
	return mat.begins_with("accent") or mat in ["rail", "pad", "lamp", "beacon", "lava", "window", "glass", "water", "line"]


# --------------------------------------------------------------------------
# Building blocks
# --------------------------------------------------------------------------

## An imported model (models.gd path, e.g. "toon/Prop/Crate") placed at `pos`
## (its own origin = the model's ground point) turned by `yaw` and scaled by
## `scl` (float or Vector3). Its meshes join the material batches like any
## other static geometry. collide: "box" (its bounding box), "none".
func _model(path: String, pos: Vector3, yaw := 0.0, scl: Variant = 1.0, mirror := true, collide := "box", shadow := true) -> void:
	var s3: Vector3 = scl if scl is Vector3 else Vector3.ONE * float(scl)
	var b: AABB = Models.bounds(path)
	for k in (2 if mirror else 1):
		var p := pos if k == 0 else Vector3(-pos.x, pos.y, -pos.z)
		var y := yaw + (PI if k == 1 else 0.0)
		var rot := Basis(Vector3.UP, y)
		var xf := Transform3D(rot * Basis.from_scale(s3), p)
		# Trees, bushes and plants bend in the wind (Models.sway).
		var leafy: bool = "Tree" in path or "Bush" in path or "Pine" in path or "Plant" in path or "Fern" in path
		if Voxel.on:
			# The voxel style: the model as real voxels (voxelizer.gd).
			var sc := (s3.x + s3.y + s3.z) / 3.0
			var vx := Voxelizer.model(path, Models.parts(path), sc, leafy)
			if not vx.is_empty():
				# What you see is always full detail (no swapping by distance:
				# that read as pop-in). Shadows come from the 2x coarser
				# version, which looks the same in a soft shadow and costs a
				# fraction of the triangles.
				_add_vox(vx, xf, false, 0, leafy)
				if shadow:
					var vf := Voxelizer.model(path, Models.parts(path), sc, leafy, true)
					_add_vox(vf if not vf.is_empty() else vx, xf, true, 1, leafy)
				if collide == "box":
					_collider(p + rot * (b.get_center() * s3), b.size * s3, y)
				continue
		for part in Models.parts(path):
			var mesh: Mesh = part[0]
			for si in mesh.get_surface_count():
				var src: Material = mesh.surface_get_material(si)
				_add(mesh, Models.sway(src) if leafy else Models.toy(src), xf * part[1], shadow, si, "g%d" % mesh.surface_get_format(si))
		if collide == "box":
			_collider(p + rot * (b.get_center() * s3), b.size * s3, y)
		if _audit:
			_audit_models.append([path, p + rot * (b.get_center() * s3), b.size * s3, y, _body.get_child_count()])


## A loose physics prop (prop.gd) standing at `pos`.
func _prop(path: String, pos: Vector3, yaw := 0.0, scl := 1.0, weight := 4.0, mirror := true, awake := false) -> void:
	if not _placing:
		_defer(_prop.bind(path, pos, yaw, scl, weight, mirror, awake), path, pos, scl, mirror, true)
		return
	# Clutter outdoors is scenery, not physics: it stays where it is (and the
	# small stuff does not even block you). Indoors a few loose things remain,
	# heavy enough that a shove barely moves them.
	# Fuel cans and barrels stay live so they can be shot and blow up, but
	# only a handful per map: each live prop is a separate body and draw call,
	# and dozens of them cost Frontline several milliseconds a frame.
	var boom: bool = path in Prop.EXPLOSIVE and _live_booms < MAX_LIVE_BOOMS
	if boom:
		_live_booms += 2 if mirror else 1
	if not indoor and not _under_roof(pos) and not boom:
		var bs: Vector3 = Models.bounds(path).size * scl
		_fixed(path, pos, yaw, scl, mirror, "box" if maxf(bs.x, bs.z) > 0.7 and bs.y > 0.5 else "none")
		return
	for k in (2 if mirror else 1):
		var p = Prop.new()
		p.setup(path, scl, weight)
		p.awake = awake
		p.position = pos if k == 0 else Vector3(-pos.x, pos.y, -pos.z)
		p.rotation.y = yaw + (PI if k == 1 else 0.0)
		add_child(p)


## A breakable glass pane (glass.gd) centred at `pos`, w x h, in a wall that
## runs along X (or along Z with along_z).
func _glass(pos: Vector3, w: float, h: float, along_z := false, mirror := true) -> void:
	for k in (2 if mirror else 1):
		var g = Glass.new()
		g.size = Vector3(w, h, 0.05)
		g.position = pos if k == 0 else Vector3(-pos.x, pos.y, -pos.z)
		g.rotation.y = PI * 0.5 if along_z else 0.0
		add_child(g)


## A hinged door (door.gd). `hinge` is the hinge post at floor level; the
## leaf runs from there along +X turned by `yaw`. It opens for bots, on the
## interact button for humans, and can be smashed.
func _door(hinge: Vector3, yaw := 0.0, w := 1.7, h := 2.45, model := "doors/Door_Brown", mirror := true, hp := 110.0, label := "DOOR") -> void:
	# Keep 1.3 m either side of every doorway free of furniture.
	var mid: Vector3 = hinge + Basis(Vector3.UP, yaw) * Vector3(w * 0.5, 0, 0)
	var along_x: bool = absf(cos(yaw)) > 0.7
	var r := Rect2(mid.x - w * 0.5 - 0.3, mid.z - 1.3, w + 0.6, 2.6) if along_x else Rect2(mid.x - 1.3, mid.z - w * 0.5 - 0.3, 2.6, w + 0.6)
	_keep_clear(r, hinge.y - 0.5, hinge.y + 2.5, mirror)
	# Doorways are left open so the maps flow (doors only slowed people down).
	if not DOORS:
		return
	for k in (2 if mirror else 1):
		var d = Door.new()
		d.width = w
		d.height = h
		d.model = model
		d.hp = hp
		d.label = label
		d.position = hinge if k == 0 else Vector3(-hinge.x, hinge.y, -hinge.z)
		d.rotation.y = yaw + (PI if k == 1 else 0.0)
		add_child(d)


## A wall that crumbles under fire (rubble.gd). `pos` = middle of its foot,
## `size` = length, height, thickness; the length runs along X turned by yaw.
func _weak_wall(pos: Vector3, size: Vector3, yaw := 0.0, col := Color(0.6, 0.56, 0.5), hp := 150.0, mirror := true) -> void:
	for k in (2 if mirror else 1):
		var r = Rubble.new()
		r.size = size
		r.color = col
		r.hp = hp
		r.position = pos if k == 0 else Vector3(-pos.x, pos.y, -pos.z)
		r.rotation.y = yaw + (PI if k == 1 else 0.0)
		add_child(r)


## A hanging lamp: cord, glowing shade and a warm light that is on at every
## time of day (interiors are lit by their lamps, not by the sky). `tone`
## varies the warmth a little from lamp to lamp.
func _lamp(pos: Vector3, mirror := true, radius := 7.5, tone := 0.0) -> void:
	var col := Color(1.0, 0.74, 0.46).lerp(Color(1.0, 0.56, 0.3), clampf(tone, 0.0, 1.0))
	_box(pos + Vector3(0, 0.32, 0), Vector3(0.03, 0.5, 0.03), "dark", mirror, 0.0, false)
	_cyl(pos + Vector3(0, -0.1, 0), 0.26, 0.2, "dark", mirror, false, 0.1)
	_ball(pos + Vector3(0, -0.14, 0), Vector3(0.14, 0.12, 0.14), "lamp", mirror)
	for s in ([pos, Vector3(-pos.x, pos.y, -pos.z)] if mirror else [pos]):
		var l := OmniLight3D.new()
		l.position = s + Vector3(0, -0.35, 0)
		l.light_color = col
		l.light_energy = 1.25
		l.omni_range = radius
		l.omni_attenuation = 1.3
		l.distance_fade_enabled = true
		l.distance_fade_begin = 42.0
		l.distance_fade_length = 12.0
		add_child(l)


## A wall torch: bracket model plus a warm flickerless light.
func _torch(pos: Vector3, mirror := true) -> void:
	_model("fantasy/Torch_Metal", pos, 0.0, 1.5, mirror, "none")
	_glow(pos + Vector3(0, 0.9, 0.3), Color(1.0, 0.6, 0.25), 9.0, 1.5, mirror)


## Free-standing ruined wall stubs on open ground: cover that falls apart
## when shot or blown up. Seeded, kept away from spawns, pads, holes and
## whatever the layout already built.
func _ruins() -> void:
	if indoor or not race_path.is_empty():
		return                    # (not on the race circuit: they landed on the road)
	var want := clampi(int(half_x * half_z / 260.0), 3, 9)
	var boxes: Array = []
	for cs in _body.get_children():
		if cs is CollisionShape3D and cs.shape is BoxShape3D:
			var ext: Vector3 = (cs.shape as BoxShape3D).size * 0.5
			var r := maxf(ext.x, ext.z)
			var o: Vector3 = cs.transform.origin
			if o.y - ext.y < 2.5 and o.y + ext.y > 0.2:
				boxes.append([Vector2(o.x, o.z), ext, r])
	var col: Color = theme.mats.block_a[0] if theme.mats.has("block_a") else Color(0.6, 0.56, 0.5)
	var placed := 0
	var tries := 0
	while placed < want and tries < 200:
		tries += 1
		var p := Vector2(_rng.randf_range(-half_x + 5.0, half_x - 5.0), _rng.randf_range(-half_z + 5.0, half_z - 5.0))
		var ok := p.length() > 4.0
		for b in boxes:
			var d: Vector2 = (p - b[0]).abs()
			if d.x < b[1].x + 3.2 and d.y < b[1].z + 3.2:
				ok = false
				break
		if ok:
			for h in _holes:
				if (h as Rect2).grow(2.5).has_point(p):
					ok = false
			for s in spawn_points:
				if Vector2(s.x, s.z).distance_to(p) < 3.5:
					ok = false
			for s in pickup_spots:
				if Vector2(s[1].x, s[1].z).distance_to(p) < 3.5:
					ok = false
		if not ok:
			continue
		var len := _rng.randf_range(2.6, 4.2)
		_weak_wall(Vector3(p.x, 0, p.y), Vector3(len, _rng.randf_range(1.5, 2.4), 0.45), _rng.randf() * PI, col, 110.0, false)
		boxes.append([p, Vector3(2.5, 1.0, 2.5), 2.5])
		_occ_extra.append(Vector3(p.x, p.y, len * 0.5 + 0.3))
		placed += 1


## Furniture for one storey of a building: a dining room, a lounge or an
## office, chosen with the map's seeded random generator. Big pieces are
## fixed in place (_fixed); only chairs are loose. The stairs run along the
## west / east walls, so the middle is free.
func _furnish(c: Vector3, sx: float, sz: float, y: float, mirror: bool) -> void:
	var f := FURN
	var north := c.z + sz * 0.26
	var south := c.z - sz * 0.26
	match _rng.randi() % 3:
		0:
			_fixed("furniture/Table" if _rng.randf() < 0.5 else "furniture/Table_Cross_Cloth", Vector3(c.x, y, north), 0.0, f, mirror)
			for sgn in [-1.0, 1.0]:
				_prop("furniture/Chair", Vector3(c.x - 0.45, y, north + sgn * 0.85), 0.0 if sgn > 0 else PI, f, 4.0, mirror)
				_prop("furniture/Chair_Cushion", Vector3(c.x + 0.45, y, north + sgn * 0.85), 0.0 if sgn > 0 else PI, f, 4.0, mirror)
			_fixed("furniture/Kitchen_Fridge", Vector3(c.x + sx * 0.2, y, c.z + sz * 0.5 - 0.75), PI, f, mirror)
			_fixed("furniture/Kitchen_Stove", Vector3(c.x + sx * 0.2 - 1.0, y, c.z + sz * 0.5 - 0.85), PI, f, mirror)
		1:
			_fixed("furniture/Lounge_Sofa", Vector3(c.x, y, c.z + sz * 0.5 - 0.9), PI, f, mirror)
			_fixed("furniture/Table_Coffee_Glass" if _rng.randf() < 0.5 else "furniture/Table_Coffee", Vector3(c.x, y, north - 0.3), 0.0, f, mirror)
			_prop("furniture/Lounge_Chair", Vector3(c.x - 1.9, y, north - 0.3), PI * 0.5, f, 12.0, mirror)
			_fixed("furniture/Cabinet_Television", Vector3(c.x - sx * 0.2, y, south - 0.2), 0.0, f, mirror)
			_fixed("furniture/Television_Vintage" if _rng.randf() < 0.5 else "furniture/Television_Modern", Vector3(c.x - sx * 0.2, y + 0.31 * f + 0.02, south - 0.2), 0.0, f, mirror, "none")
			_fixed("furniture/Potted_Plant", Vector3(c.x + sx * 0.2, y, south - 0.4), 0.0, f, mirror)
		_:
			_fixed("furniture/Desk", Vector3(c.x, y, north), 0.0, f, mirror)
			_prop("furniture/Chair_Desk", Vector3(c.x, y, north - 0.9), PI, f, 6.0, mirror)
			_fixed("furniture/Computer_Screen", Vector3(c.x, y + 0.38 * f + 0.02, north + 0.15), 0.0, f, mirror, "none")
			_fixed("furniture/Bookcase_Closed_Wide", Vector3(c.x - 1.9, y, c.z + sz * 0.5 - 0.65), PI, f, mirror)


## A piece of furniture fixed in place: a static model centred on its
## footprint (the same placement as a loose _prop), with a box collider
## unless collide is "none" (things standing on tables and counters).
func _fixed(path: String, pos: Vector3, yaw := 0.0, scl := 1.0, mirror := true, collide := "box") -> void:
	if not _placing:
		_defer(_fixed.bind(path, pos, yaw, scl, mirror, collide), path, pos, scl, mirror, collide != "none")
		return
	var b: AABB = Models.bounds(path)
	var o := Basis(Vector3.UP, yaw) * (Vector3(b.get_center().x, b.position.y, b.get_center().z) * scl)
	_model(path, pos - o, yaw, scl, mirror, collide)


## Scatter loose clutter on random walkable spots (called once the nav graph
## exists), away from spawn points and pickup pads. Outdoors only: never
## inside a building, on an upper floor or on an indoor map, where it would
## clog rooms and doorways.
func _scatter_props() -> void:
	if _nav_ids.is_empty() or indoor:
		return
	var count := clampi(int(half_x * half_z / 26.0), 14, 70)
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 4:
		tries += 1
		var p := random_nav_point()
		var ok := true
		for s in spawn_points:
			if (s as Vector3).distance_to(p) < 2.5:
				ok = false
		for s in pickup_spots:
			if (s[1] as Vector3).distance_to(p) < 2.5:
				ok = false
		if p.y > 0.6:
			ok = false
		for r in roofs:
			if (r as Rect2).grow(0.5).has_point(Vector2(p.x, p.z)):
				ok = false
		if not ok:
			continue
		var pool: Array = CLUTTER_SETS.get(MAPS[map_index].get("clutter", ""), CLUTTER)
		var c: Array = pool[randi() % pool.size()]
		var n := 1 + (randi() % 3 if float(c[2]) < 6.0 else 0)
		# Side by side with room between them (never inside one another), dropped
		# from a hand's height so physics settles them.
		var bs: Vector3 = Models.bounds(c[0]).size * float(c[1])
		var gap := maxf(bs.x, bs.z) * 1.45 + 0.1
		var a0 := randf() * TAU
		for i in n:
			var off := Vector3.ZERO if n == 1 else Vector3(cos(a0 + i * TAU / n), 0, sin(a0 + i * TAU / n)) * gap * 0.6
			_prop(c[0], p + off + Vector3(0, 0.12, 0), randf() * TAU, c[1], c[2], false, true)
		placed += 1


## Doorways, stairs and windows register an area here; furniture and props
## that would stand in one are left out (_place_deferred).
func _keep_clear(r: Rect2, y0: float, y1: float, mirror: bool) -> void:
	_keep.append([r, y0, y1])
	if mirror:
		_keep.append([Rect2(-r.end.x, -r.end.y, r.size.x, r.size.y), y0, y1])


func _defer(place: Callable, path: String, pos: Vector3, scl: float, mirror: bool, solid: bool) -> void:
	var bs: Vector3 = Models.bounds(path).size * scl
	_deferred.append([place, pos, maxf(bs.x, bs.z) * 0.5, mirror, solid])


func _blocked(p: Vector3, radius: float) -> bool:
	for k in _keep:
		if p.y >= float(k[1]) and p.y <= float(k[2]) and (k[0] as Rect2).grow(radius * 0.5).has_point(Vector2(p.x, p.z)):
			return true
	return false


func _under_roof(p: Vector3) -> bool:
	for r in roofs:
		if (r as Rect2).has_point(Vector2(p.x, p.z)):
			return true
	return false


## Place the furniture and props queued during the build, except anything
## standing in a doorway, on or at the foot of stairs, or in front of a
## window. Things standing on skipped furniture (a TV on its cabinet) go too.
func _place_deferred() -> void:
	_placing = true
	for d in _deferred:
		var pos: Vector3 = d[1]
		var radius: float = d[2]
		var copies: Array = [pos, Vector3(-pos.x, pos.y, -pos.z)] if d[3] else [pos]
		var skip := false
		for c in copies:
			if _blocked(c, radius):
				skip = true
			if not d[4]:
				# Things without a collider stand on something: on skipped
				# furniture they go too.
				for s in _skipped:
					if (s[0] as Rect2).has_point(Vector2(c.x, c.z)) and c.y - float(s[1]) > 0.05 and c.y - float(s[1]) < 2.0:
						skip = true
		if skip:
			_dropped += 1
			if d[4]:
				for c in copies:
					_skipped.append([Rect2(c.x - radius, c.z - radius, radius * 2.0, radius * 2.0), c.y])
			continue
		(d[0] as Callable).call()
	if "--audit" in OS.get_cmdline_user_args() or "--clutter" in OS.get_cmdline_user_args():
		print("[clutter] %s: %d placed, %d left out (doorways, stairs, windows), %d live explosives" % [MAPS[map_index].name, _deferred.size() - _dropped, _dropped, _live_booms])
	_deferred.clear()


## Pick one of several model variants with the map's seeded random generator.
func _pick(paths: Array) -> String:
	return paths[_rng.randi() % paths.size()]


func _collider(pos: Vector3, size: Vector3, yaw := 0.0) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	_body.add_child(cs)


func _visual(pos: Vector3, size: Vector3, mat: String, yaw := 0.0) -> void:
	_add(_rounded_box(size), _mats[mat], Transform3D(Basis(Vector3.UP, yaw), pos), not _glows(mat))


func _box(pos: Vector3, size: Vector3, mat: String, mirror := true, yaw := 0.0, collide := true) -> void:
	var copies := [[pos, yaw]]
	if mirror:
		copies.append([Vector3(-pos.x, pos.y, -pos.z), yaw + PI])
	var cube := mat == "crate" and maxf(size.x, maxf(size.y, size.z)) < 1.35 * minf(size.x, minf(size.y, size.z))
	for c in copies:
		if collide:
			_collider(c[0], size, c[1])
		if cube:
			# Wooden crate model, scaled to the requested size.
			_model("toon/Prop/Crate", c[0] - Vector3(0, size.y * 0.5, 0), c[1], size / 0.79, false, "none")
			continue
		_visual(c[0], size, mat, c[1])


## An upright cylinder (or cone, with top_radius) standing on `base`.
func _cyl(base: Vector3, radius: float, height: float, mat: String, mirror := true, collide := true, top_radius := -1.0) -> void:
	var mesh: Mesh = _unit_cyl
	if top_radius >= 0.0:
		var cm := CylinderMesh.new()
		cm.top_radius = top_radius / radius
		cm.bottom_radius = 1.0
		cm.height = 1.0
		cm.radial_segments = 16
		cm.rings = 1
		mesh = cm
	for s in ([base, Vector3(-base.x, base.y, -base.z)] if mirror else [base]):
		if collide:
			var shape := CylinderShape3D.new()
			shape.radius = radius
			shape.height = height
			var cs := CollisionShape3D.new()
			cs.shape = shape
			cs.position = s + Vector3(0, height * 0.5, 0)
			_body.add_child(cs)
		_add(mesh, _mats[mat], Transform3D(Basis.from_scale(Vector3(radius, height, radius)), s + Vector3(0, height * 0.5, 0)), not _glows(mat))


## A sphere (visual only) with the given radii.
func _ball(pos: Vector3, radii: Vector3, mat, mirror := true) -> void:
	var m: Material = _mats[mat] if mat is String else mat
	for s in ([pos, Vector3(-pos.x, pos.y, -pos.z)] if mirror else [pos]):
		_add(_unit_sphere, m, Transform3D(Basis.from_scale(radii), s))


## A round rod between two points (visual only): bones, branches, poles.
func _rod(a: Vector3, b: Vector3, radius: float, mat: String, mirror := true) -> void:
	var pairs := [[a, b]]
	if mirror:
		pairs.append([Vector3(-a.x, a.y, -a.z), Vector3(-b.x, b.y, -b.z)])
	for pair in pairs:
		var aa: Vector3 = pair[0]
		var bb: Vector3 = pair[1]
		var d := bb - aa
		var length := d.length()
		if length < 0.01:
			continue
		var y := d / length
		var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
		var z := x.cross(y)
		_add(_unit_cyl, _mats[mat], Transform3D(Basis(x * radius, y * length, z * radius), (aa + bb) * 0.5))


## Box mesh with slightly rounded edges, built at its real size so the bevel
## radius is not distorted by scaling. Cached per size.
func _rounded_box(size: Vector3) -> ArrayMesh:
	var key := "%.3f,%.3f,%.3f" % [size.x, size.y, size.z]
	if _box_cache.has(key):
		return _box_cache[key]
	const SEG := 2
	var h := size * 0.5
	var r := minf(0.06, minf(size.x, minf(size.y, size.z)) * 0.3)
	var faces := [
		[Vector3.RIGHT, Vector3.UP, Vector3.BACK], [Vector3.LEFT, Vector3.BACK, Vector3.UP],
		[Vector3.UP, Vector3.BACK, Vector3.RIGHT], [Vector3.DOWN, Vector3.RIGHT, Vector3.BACK],
		[Vector3.BACK, Vector3.RIGHT, Vector3.UP], [Vector3.FORWARD, Vector3.UP, Vector3.RIGHT],
	]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inner := (h - Vector3.ONE * r)
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var hn := absf(n.dot(h))
		var cu := _edge_coords(absf(u.dot(h)), r, SEG)
		var cv := _edge_coords(absf(v.dot(h)), r, SEG)
		var grid: Array = []
		var norms: Array = []
		for a in cu:
			for b in cv:
				var p: Vector3 = n * hn + u * a + v * b
				var core := Vector3(clampf(p.x, -inner.x, inner.x), clampf(p.y, -inner.y, inner.y), clampf(p.z, -inner.z, inner.z))
				var d := (p - core).normalized()
				grid.append(core + d * r)
				norms.append(d)
		var w := cv.size()
		for i in cu.size() - 1:
			for j in w - 1:
				# u x v = n, so (00, 10, 11) is counter-clockwise from outside;
				# Godot front faces are clockwise.
				for idx in [i * w + j, (i + 1) * w + j + 1, (i + 1) * w + j, i * w + j, i * w + j + 1, (i + 1) * w + j + 1]:
					st.set_normal(norms[idx])
					st.add_vertex(grid[idx])
	var mesh := st.commit()
	_box_cache[key] = mesh
	return mesh


func _edge_coords(hh: float, r: float, seg: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in seg + 1:
		out.append(-hh + r * i / seg)
	for i in seg + 1:
		out.append(hh - r + r * i / seg)
	return out


## Convex mesh from triangles (any winding); normals face away from `centroid`.
func _convex_mesh(tris: Array, centroid: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in tris:
		var p0: Vector3 = t[0]
		var p1: Vector3 = t[1]
		var p2: Vector3 = t[2]
		var n := (p1 - p0).cross(p2 - p0).normalized()
		var outward := ((p0 + p1 + p2) / 3.0 - centroid)
		if n.dot(outward) > 0.0:
			var tmp := p1
			p1 = p2
			p2 = tmp
		else:
			n = -n
		for p in [p0, p1, p2]:
			st.set_normal(n)
			st.add_vertex(p)
	return st.commit()


func _wedge_points(size: Vector3) -> Array:
	var r := size.x * 0.5
	var h := size.y
	var w := size.z * 0.5
	return [Vector3(-r, 0, -w), Vector3(-r, 0, w), Vector3(r, 0, -w), Vector3(r, 0, w), Vector3(r, h, -w), Vector3(r, h, w)]


func _ramp_collider(xf: Transform3D, size: Vector3) -> void:
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array(_wedge_points(size))
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = xf
	_body.add_child(cs)


## A solid ramp. `size` = (run, rise, width); it rises toward local +X, then is
## rotated by `yaw` about Y. `base` is the centre of its footprint.
func _wedge(base: Vector3, size: Vector3, yaw: float, mat: String, mirror := true, rails := true) -> void:
	var p: Array = _wedge_points(size)
	var tris := [[p[0], p[1], p[5]], [p[0], p[5], p[4]], [p[2], p[4], p[5]], [p[2], p[5], p[3]],
		[p[0], p[4], p[2]], [p[1], p[3], p[5]], [p[0], p[2], p[3]], [p[0], p[3], p[1]]]
	var mesh := _convex_mesh(tris, Vector3(size.x / 6.0, size.y / 3.0, 0))
	var copies := [Transform3D(Basis(Vector3.UP, yaw), base)]
	if mirror:
		copies.append(Transform3D(Basis(Vector3.UP, yaw + PI), Vector3(-base.x, base.y, -base.z)))
	for xf in copies:
		_ramp_collider(xf, size)
		_add(mesh, _mats[mat], xf)
		if rails:
			for side in [-1.0, 1.0]:
				var length := sqrt(size.x * size.x + size.y * size.y)
				_add(_rounded_box(Vector3(length, 0.12, 0.12)), _mats["accent_a" if theme.neon else "rail"],
					xf * Transform3D(Basis(Vector3.BACK, atan2(size.y, size.x)), Vector3(0, size.y * 0.5 + 0.04, side * (size.z * 0.5 - 0.05))), false)


## Stairs: a hidden ramp to walk on, drawn as steps. Same frame as _wedge.
func _stairs(base: Vector3, size: Vector3, yaw: float, mat: String, mirror := true) -> void:
	var key := "%.2f,%.2f,%.2f" % [size.x, size.y, size.z]
	if not _stairs_cache.has(key):
		var n := maxi(2, int(ceil(size.y / 0.25)))
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var dx := size.x / n
		for i in n:
			var hh := size.y * (i + 1) / n
			st.append_from(_rounded_box(Vector3(dx + 0.02, hh, size.z)), 0, Transform3D(Basis(), Vector3(-size.x * 0.5 + dx * (i + 0.5), hh * 0.5, 0)))
		_stairs_cache[key] = st.commit()
	var copies := [Transform3D(Basis(Vector3.UP, yaw), base)]
	if mirror:
		copies.append(Transform3D(Basis(Vector3.UP, yaw + PI), Vector3(-base.x, base.y, -base.z)))
	for xf in copies:
		_ramp_collider(xf, size)
		_add(_stairs_cache[key], _mats[mat], xf)
		# Stairs and a landing at each end stay clear.
		var ext := Vector3(size.x * 0.5 + 0.8, 0, size.z * 0.5 + 0.2)
		var c0: Vector3 = xf.origin
		var b: Basis = xf.basis
		var ax: Vector3 = (b * Vector3(ext.x, 0, 0)).abs()
		var az: Vector3 = (b * Vector3(0, 0, ext.z)).abs()
		var hx: float = ax.x + az.x
		var hz: float = ax.z + az.z
		_keep_clear(Rect2(c0.x - hx, c0.z - hz, hx * 2.0, hz * 2.0), c0.y - 0.5, c0.y + size.y + 2.5, false)


## A pitched roof: a prism with its ridge along X, sitting on y = base.y.
func _gable(base: Vector3, sx: float, sz: float, h: float, mat: String, mirror := true) -> void:
	var a := sx * 0.5
	var b := sz * 0.5
	var pts := [Vector3(-a, 0, -b), Vector3(a, 0, -b), Vector3(-a, 0, b), Vector3(a, 0, b), Vector3(-a, h, 0), Vector3(a, h, 0)]
	var tris := [[pts[0], pts[1], pts[5]], [pts[0], pts[5], pts[4]], [pts[2], pts[3], pts[5]], [pts[2], pts[5], pts[4]],
		[pts[0], pts[2], pts[4]], [pts[1], pts[3], pts[5]], [pts[0], pts[1], pts[3]], [pts[0], pts[3], pts[2]]]
	var mesh := _convex_mesh(tris, Vector3(0, h / 3.0, 0))
	for s in ([base, Vector3(-base.x, base.y, -base.z)] if mirror else [base]):
		var xf := Transform3D(Basis(), s)
		var shape := ConvexPolygonShape3D.new()
		shape.points = PackedVector3Array(pts)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.transform = xf
		_body.add_child(cs)
		_add(mesh, _mats[mat], xf)


## Wall segments with openings. `openings` = [[centre, width, bottom, top], ...]
## measured along the wall; bottom/top are heights above the wall's base.
func _wall_segments(a: float, b: float, h: float, openings: Array) -> Array:
	var out: Array = []
	var cur := a
	var ops := openings.duplicate()
	ops.sort_custom(func(p, q): return p[0] < q[0])
	for o in ops:
		var oa: float = o[0] - o[1] * 0.5
		var ob: float = o[0] + o[1] * 0.5
		out.append([cur, oa, 0.0, h])
		if o[2] > 0.0:
			out.append([oa, ob, 0.0, o[2]])
		if o[3] < h:
			out.append([oa, ob, o[3], h])
		cur = ob
	out.append([cur, b, 0.0, h])
	return out


## A wall running along X at depth z, from x0 to x1.
func _wall_x(z: float, x0: float, x1: float, y0: float, h: float, mat: String, openings := [], mirror := true, t := 0.3) -> void:
	for o in openings:
		if float(o[2]) < 0.3 and float(o[3]) > 1.8:
			# A doorway: keep 1.3 m either side clear of furniture.
			_keep_clear(Rect2(float(o[0]) - float(o[1]) * 0.5 - 0.3, z - 1.3, float(o[1]) + 0.6, 2.6), y0 - 0.5, y0 + 2.5, mirror)
	for s in _wall_segments(x0, x1, h, openings):
		var length: float = s[1] - s[0]
		var hh: float = s[3] - s[2]
		if length > 0.02 and hh > 0.02:
			_box(Vector3((s[0] + s[1]) * 0.5, y0 + (s[2] + s[3]) * 0.5, z), Vector3(length, hh, t), mat, mirror)


## A wall running along Z at x, from z0 to z1.
func _wall_z(x: float, z0: float, z1: float, y0: float, h: float, mat: String, openings := [], mirror := true, t := 0.3) -> void:
	for o in openings:
		if float(o[2]) < 0.3 and float(o[3]) > 1.8:
			_keep_clear(Rect2(x - 1.3, float(o[0]) - float(o[1]) * 0.5 - 0.3, 2.6, float(o[1]) + 0.6), y0 - 0.5, y0 + 2.5, mirror)
	for s in _wall_segments(z0, z1, h, openings):
		var length: float = s[1] - s[0]
		var hh: float = s[3] - s[2]
		if length > 0.02 and hh > 0.02:
			_box(Vector3(x, y0 + (s[2] + s[3]) * 0.5, (s[0] + s[1]) * 0.5), Vector3(t, hh, length), mat, mirror)


## Split `area` into rectangles that avoid every hole (XZ Rect2s).
func _split(area: Rect2, holes: Array) -> Array:
	var xs := [area.position.x, area.end.x]
	var zs := [area.position.y, area.end.y]
	for h in holes:
		var r: Rect2 = h
		if not r.intersects(area):
			continue
		for x in [r.position.x, r.end.x]:
			if x > area.position.x and x < area.end.x:
				xs.append(x)
		for z in [r.position.y, r.end.y]:
			if z > area.position.y and z < area.end.y:
				zs.append(z)
	xs.sort()
	zs.sort()
	var out: Array = []
	for j in zs.size() - 1:
		var z0: float = zs[j]
		var z1: float = zs[j + 1]
		if z1 - z0 < 0.001:
			continue
		var run_start := 0.0
		var run_end := 0.0
		var running := false
		for i in xs.size() - 1:
			var x0: float = xs[i]
			var x1: float = xs[i + 1]
			if x1 - x0 < 0.001:
				continue
			var centre := Vector2((x0 + x1) * 0.5, (z0 + z1) * 0.5)
			var blocked := false
			for h in holes:
				if (h as Rect2).has_point(centre):
					blocked = true
					break
			if blocked:
				if running:
					out.append(Rect2(run_start, z0, run_end - run_start, z1 - z0))
				running = false
			else:
				if not running:
					run_start = x0
					running = true
				run_end = x1
		if running:
			out.append(Rect2(run_start, z0, run_end - run_start, z1 - z0))
	return out


func _hole(r: Rect2, mirror := true) -> void:
	_holes.append(r)
	if mirror:
		_holes.append(Rect2(-r.end.x, -r.end.y, r.size.x, r.size.y))


## A horizontal slab (top at y) over `r`, with holes.
func _slab(r: Rect2, y: float, mat: String, holes := [], mirror := true, t := 0.3) -> void:
	for p in _split(r, holes):
		var pr: Rect2 = p
		_box(Vector3(pr.get_center().x, y - t * 0.5, pr.get_center().y), Vector3(pr.size.x, t, pr.size.y), mat, mirror)


## A flat surface decal (visual only) at height y, cut around ground holes.
## Ground holes are already mirrored, so `mirror` only mirrors the rectangle.
## The decals are laid at the end of the layout (_build_floor), once every
## hole is known, so a floor or path never covers a stairwell or ramp down,
## whatever order the layout code runs in.
func _surface(r: Rect2, y: float, mat: String, mirror := true) -> void:
	var rects := [r]
	if mirror:
		rects.append(Rect2(-r.end.x, -r.end.y, r.size.x, r.size.y))
	for rr in rects:
		_paved.append(rr)
		_pending_surfaces.append([rr, y, mat])


func _lay_surfaces() -> void:
	for s in _pending_surfaces:
		for p in _split(s[0], _holes):
			var pr: Rect2 = p
			_visual(Vector3(pr.get_center().x, s[1], pr.get_center().y), Vector3(pr.size.x, 0.012, pr.size.y), s[2])
	_pending_surfaces.clear()


## Perimeter walls (the ground itself is made by _build_floor after the layout).
func _build_walls() -> void:
	var w := half_x * 2.0
	var d := half_z * 2.0
	# The invisible boundary: 8 m thick and 500 m tall (from 20 m below the
	# floor), so no blast or jump pad can fling anyone out. Its own body, so
	# players can tell it apart (no wall running on the invisible part).
	boundary = StaticBody3D.new()
	boundary.collision_layer = 1
	boundary.collision_mask = 0
	add_child(boundary)
	for sgn in [1.0, -1.0]:
		for spec in [[Vector3(0, 230, sgn * (half_z + 4.0)), Vector3(w + 18, 500, 8)], [Vector3(sgn * (half_x + 4.0), 230, 0), Vector3(8, 500, d + 18)]]:
			var shape := BoxShape3D.new()
			shape.size = spec[1]
			var cs := CollisionShape3D.new()
			cs.shape = shape
			cs.position = spec[0]
			boundary.add_child(cs)
	_box(Vector3(0, wall_h * 0.5, half_z + 0.5), Vector3(w + 2, wall_h, 1), "wall", true, 0.0, false)
	_box(Vector3(half_x + 0.5, wall_h * 0.5, 0), Vector3(1, wall_h, d + 2), "wall", true, 0.0, false)
	_perimeter_dressing()
	if theme.neon:
		_box(Vector3(0, wall_h + 0.04, half_z + 0.08), Vector3(w + 0.3, 0.1, 0.16), "accent_a", true, 0.0, false)
		_box(Vector3(half_x + 0.08, wall_h + 0.04, 0), Vector3(0.16, 0.1, d + 0.3), "accent_a", true, 0.0, false)
		_box(Vector3(0, 0.12, half_z + 0.02), Vector3(w, 0.16, 0.14), "accent_b", true, 0.0, false)
		_box(Vector3(half_x + 0.02, 0.12, 0), Vector3(0.14, 0.16, d), "accent_b", true, 0.0, false)


## Relief on the long perimeter walls so they are not one flat plane:
## pilasters every few metres, a coping along the top, a skirting at the
## foot and a little fallen rubble against it. Visual only (no colliders).
func _perimeter_dressing() -> void:
	if wall_h < 1.3 or indoor and wall_h > 8.0:
		return
	# Its own random numbers, so the rest of the layout stays as it was.
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242 + map_index
	var trim := "trim" if _mats.has("trim") else ("block_a" if _mats.has("block_a") else "wall")
	var step := 6.0
	for axis in 2:
		var half_len: float = half_x if axis == 0 else half_z
		var n := int(half_len * 2.0 / step)
		for i in range(1, n):
			var u := -half_len + i * (half_len * 2.0 / n)
			# Pilaster.
			if axis == 0:
				_box(Vector3(u, wall_h * 0.5, half_z - 0.07), Vector3(0.55, wall_h, 0.14), trim, true, 0.0, false)
			else:
				_box(Vector3(half_x - 0.07, wall_h * 0.5, u), Vector3(0.14, wall_h, 0.55), trim, true, 0.0, false)
			# Rubble at the foot now and then.
			if rng.randf() < 0.35:
				for k in rng.randi_range(2, 4):
					var off := rng.randf_range(-1.2, 1.2)
					var sz := Vector3(rng.randf_range(0.18, 0.4), rng.randf_range(0.1, 0.22), rng.randf_range(0.18, 0.35))
					var inset := rng.randf_range(0.15, 0.5)
					var pos := Vector3(u + off, sz.y * 0.5, half_z - inset) if axis == 0 else Vector3(half_x - inset, sz.y * 0.5, u + off)
					_box(pos, sz, "wall" if rng.randf() < 0.6 else trim, true, rng.randf() * TAU, false)
	if not theme.neon:
		# Coping and skirting.
		_box(Vector3(0, wall_h + 0.06, half_z + 0.02), Vector3(half_x * 2.0 + 0.4, 0.14, 0.34), trim, true, 0.0, false)
		_box(Vector3(half_x + 0.02, wall_h + 0.06, 0), Vector3(0.34, 0.14, half_z * 2.0 + 0.4), trim, true, 0.0, false)
		_box(Vector3(0, 0.13, half_z - 0.05), Vector3(half_x * 2.0, 0.26, 0.1), trim, true, 0.0, false)
		_box(Vector3(half_x - 0.05, 0.13, 0), Vector3(0.1, 0.26, half_z * 2.0), trim, true, 0.0, false)


## The ground slab with every hole cut out, and the painted paths.
func _build_floor() -> void:
	var area := Rect2(-half_x - 1.0, -half_z - 1.0, half_x * 2.0 + 2.0, half_z * 2.0 + 2.0)
	for p in _split(area, _holes):
		var r: Rect2 = p
		var pos := Vector3(r.get_center().x, -0.5, r.get_center().y)
		_collider(pos, Vector3(r.size.x, 1.0, r.size.y))
		_add(_rounded_box(Vector3(r.size.x, 1.0, r.size.y)), _mats["ground"], Transform3D(Basis(), pos))
	if theme.paths:
		_surface(Rect2(-half_x, -3.5, half_x * 2.0, 7.0), 0.006, "path", false)
		_surface(Rect2(-3.5, -half_z, 7.0, half_z * 2.0), 0.008, "path", false)
		for off in [3.5, -3.5]:
			_surface(Rect2(-half_x, off - 0.04, half_x * 2.0, 0.08), 0.016, "rail", false)
			_surface(Rect2(off - 0.04, -half_z, 0.08, half_z * 2.0), 0.016, "rail", false)
	_lay_surfaces()


# --------------------------------------------------------------------------
# Composite pieces
# --------------------------------------------------------------------------

## A building with `floors` storeys, doors on the ground floor (+X and -Z
## sides), windows above, stairs inside between storeys, and either a flat
## roof with a parapet (reachable by stairs: a vantage point) or a pitched
## roof (opts.pitched). Needs sz >= 8.5. c = footprint centre at ground level.
## opts: mirror, pitched, roof, floor (materials), glass (bool: glazed windows),
## style (arch.gd: house, cabin, store, office, warehouse, barn, clinic,
## motel, garage, barracks, lab, workshop, clubhouse: exterior character and a room
## programme per storey), roof_h (ridge height), tiers (office tower).
func _building(c: Vector3, sx: float, sz: float, floors: int, mat: String, opts := {}) -> void:
	var mirror: bool = opts.get("mirror", true)
	var pitched: bool = opts.get("pitched", false)
	var roof_mat: String = opts.get("roof", "block_c")
	var floor_mat: String = opts.get("floor", "deck")
	var t := 0.3
	var x0 := c.x - sx * 0.5
	var x1 := c.x + sx * 0.5
	var z0 := c.z - sz * 0.5
	var z1 := c.z + sz * 0.5
	var run := 6.0
	var sw := 1.5
	var flights := floors - 1 if pitched else floors
	var stair_x := [x0 + t + sw * 0.5 + 0.05, x1 - t - sw * 0.5 - 0.05]
	roofs.append(Rect2(x0, z0, sx, sz))
	if mirror:
		roofs.append(Rect2(-x1, -z1, sx, sz))
	# A real ground floor (boards or tiles), not the lawn or street outside.
	_surface(Rect2(x0 + t, z0 + t, sx - t * 2.0, sz - t * 2.0), c.y + 0.015, floor_mat, mirror)
	for f in floors:
		var y0 := c.y + f * FLOOR_H
		var win_x: Array = []
		var win_z: Array = []
		var nx := maxi(1, int((sx - 1.0) / 4.0))
		var nz := maxi(1, int((sz - 1.0) / 4.0))
		for i in nx:
			# Windows big enough to jump through (1.6 m wide, 0.6 m to 2.6 m).
			win_x.append([x0 + sx * (i + 0.5) / nx, WIN_W, WIN_LO, WIN_HI])
		for i in nz:
			win_z.append([z0 + sz * (i + 0.5) / nz, WIN_W, WIN_LO, WIN_HI])
		var south: Array = win_x.duplicate()
		var east: Array = win_z.duplicate()
		if f == 0:
			south = [[c.x, 1.8, 0.0, 2.5]]
			east = [[c.z, 1.8, 0.0, 2.5]]
			if opts.get("style", "") in ["store", "office", "clinic"] and sx >= 8.0:
				# A glazed front: tall display windows either side of the door.
				var dw := minf(3.0, sx * 0.5 - 2.0)
				for sgn in [-1.0, 1.0]:
					var wx: float = c.x + sgn * (1.35 + dw * 0.5)
					south.append([wx, dw, 0.45, 2.75])
					_glass(Vector3(wx, y0 + 1.6, z0 + t * 0.5), dw, 2.3, false, mirror)
		# Doors in both ground-floor doorways.
		if f == 0 and opts.get("doors", true):
			var dm: String = opts.get("door_model", "doors/Door_Brown" if _rng.randf() < 0.5 else "doors/Door_White")
			# Hung 6 cm clear of the floor and the porch step so the leaf never
			# scrapes through them as it swings.
			_door(Vector3(c.x - 0.88, y0 + 0.06, z0 + t * 0.5), 0.0, 1.76, 2.42, dm, mirror)
			_door(Vector3(x1 - t * 0.5, y0 + 0.06, c.z - 0.88), -PI * 0.5, 1.76, 2.42, dm, mirror)
		# The floor in front of every window stays clear (you can jump through).
		for w in win_x:
			for zz in ([z1] if f == 0 else [z1, z0]):
				_keep_clear(Rect2(w[0] - WIN_W * 0.5, zz - 0.8, WIN_W, 1.6), y0 - 0.2, y0 + 2.6, mirror)
		for w in win_z:
			for xx in ([x0] if f == 0 else [x0, x1]):
				_keep_clear(Rect2(xx - 0.8, w[0] - WIN_W * 0.5, 1.6, WIN_W), y0 - 0.2, y0 + 2.6, mirror)
		# Glass in every window (not the doors), furniture on every floor.
		for w in (win_x if opts.get("glass", true) else []):
			_glass(Vector3(w[0], y0 + WIN_MID, z1 - t * 0.5), WIN_W, WIN_HI - WIN_LO, false, mirror)
			if f > 0:
				_glass(Vector3(w[0], y0 + WIN_MID, z0 + t * 0.5), WIN_W, WIN_HI - WIN_LO, false, mirror)
		for w in (win_z if opts.get("glass", true) else []):
			_glass(Vector3(x0 + t * 0.5, y0 + WIN_MID, w[0]), WIN_W, WIN_HI - WIN_LO, true, mirror)
			if f > 0:
				_glass(Vector3(x1 - t * 0.5, y0 + WIN_MID, w[0]), WIN_W, WIN_HI - WIN_LO, true, mirror)
		if opts.has("style"):
			Arch.interior(self, opts.style, f, floors, c, sx, sz, y0, mirror)
		elif opts.get("furnish", true):
			_furnish(c, sx, sz, y0, mirror)
		_facade(c, sx, sz, y0, f, win_x, win_z, pitched, mirror)
		_wall_x(z0 + t * 0.5, x0, x1, y0, FLOOR_H, mat, south, mirror, t)
		_wall_x(z1 - t * 0.5, x0, x1, y0, FLOOR_H, mat, win_x, mirror, t)
		_wall_z(x0 + t * 0.5, z0 + t, z1 - t, y0, FLOOR_H, mat, win_z, mirror, t)
		_wall_z(x1 - t * 0.5, z0 + t, z1 - t, y0, FLOOR_H, mat, east, mirror, t)
		# Warm lamps on every storey: two or more pools of light per room
		# instead of one flat glow.
		var lx := maxi(2, int(round(sx / 7.0)))
		var lz := 2 if sz > 13.0 else 1
		for ix in lx:
			for iz in lz:
				var lp := Vector3(x0 + sx * (ix + 0.5) / lx, y0 + FLOOR_H - 0.75, z0 + sz * (iz + 0.5) / lz)
				_lamp(lp, mirror, 7.5, _rng.randf())
	for f in flights:
		var y0 := c.y + f * FLOOR_H
		var even := f % 2 == 0
		var sxp: float = stair_x[0] if even else stair_x[1]
		_stairs(Vector3(sxp, y0, c.z), Vector3(run, FLOOR_H, sw), -PI * 0.5 if even else PI * 0.5, floor_mat, mirror)
	var rail_mat := "rail" if theme.neon else ("trim" if _mats.has("trim") else "block_c")
	for f in range(1, floors + 1):
		var y := c.y + f * FLOOR_H
		var holes: Array = []
		var fl := f - 1
		if fl < flights:
			var even := fl % 2 == 0
			var sxp: float = stair_x[0] if even else stair_x[1]
			# The stair mesh/ramp spans the full 6 m run along Z. Leave a generous
			# matching opening so the upper floor cannot cap the stairwell.
			holes.append(Rect2(sxp - sw * 0.5 - 0.18, c.z - run * 0.5 - 0.18, sw + 0.36, run + 0.36))
			var rail_x := sxp + (sw * 0.5 + 0.1) * (1.0 if even else -1.0)
			_box(Vector3(rail_x, y + 0.5, c.z), Vector3(0.08, 1.0, run), rail_mat, mirror)
		var is_roof := f == floors
		if is_roof and pitched:
			_slab(Rect2(x0 + 0.05, z0 + 0.05, sx - 0.1, sz - 0.1), y, roof_mat, [], mirror)
			_gable(Vector3(c.x, y, c.z), sx + 0.8, sz + 0.8, opts.get("roof_h", minf(sz * 0.32, 3.0)), roof_mat, mirror)
		else:
			# Floors stop just inside the outer wall face: an edge flush with the
			# wall would shimmer (two surfaces in the same plane).
			_slab(Rect2(x0 + 0.05, z0 + 0.05, sx - 0.1, sz - 0.1), y, floor_mat if not is_roof else roof_mat, holes, mirror)
	# Foundation band and corner posts: the building reads as built, not a box.
	var trim := "trim" if _mats.has("trim") else ("block_a" if mat != "block_a" else "block_c")
	# A plinth round the outside, open at both doors. (A solid slab here used
	# to stand 28 cm proud of the ground floor, swallowing feet and doors.)
	var fy := c.y + 0.14
	var has_doors: bool = opts.get("doors", true)
	_box(Vector3(c.x, fy, z1 + 0.04), Vector3(sx + 0.16, 0.28, 0.08), "dark", mirror, 0.0, false)
	_box(Vector3(x0 - 0.04, fy, c.z), Vector3(0.08, 0.28, sz), "dark", mirror, 0.0, false)
	for sgn in [-1.0, 1.0]:
		var gap := 1.0 if has_doors else 0.0
		_box(Vector3(c.x + sgn * (gap + (sx * 0.5 + 0.08 - gap) * 0.5), fy, z0 - 0.04), Vector3(sx * 0.5 + 0.08 - gap, 0.28, 0.08), "dark", mirror, 0.0, false)
		_box(Vector3(x1 + 0.04, fy, c.z + sgn * (gap + (sz * 0.5 - gap) * 0.5)), Vector3(0.08, 0.28, sz * 0.5 - gap), "dark", mirror, 0.0, false)
	for cx_side in [[x0, 1.0], [x1, -1.0]]:
		for cz_side in [[z0, 1.0], [z1, -1.0]]:
			var post_pos := Vector3(cx_side[0] + cx_side[1] * 0.15, c.y + floors * FLOOR_H * 0.5, cz_side[0] + cz_side[1] * 0.15)
			_box(post_pos, Vector3(0.22, floors * FLOOR_H, 0.22), trim, mirror, 0.0, false)
	if pitched:
		# Chimney through the ridge side.
		var ry := c.y + floors * FLOOR_H
		_box(Vector3(c.x + sx * 0.28, ry + 1.5, c.z - sz * 0.14), Vector3(0.8, 3.0, 0.8), "block_b" if _mats.has("block_b") else "block_a", mirror)
		_box(Vector3(c.x + sx * 0.28, ry + 3.05, c.z - sz * 0.14), Vector3(0.95, 0.14, 0.95), "dark", mirror, 0.0, false)
	else:
		# Roof clutter on the terrace: vents, a water tank, an aerial.
		var ry2 := c.y + floors * FLOOR_H
		_box(Vector3(c.x - sx * 0.3, ry2 + 0.4, c.z + sz * 0.3), Vector3(1.4, 0.8, 1.0), "block_c", mirror)
		_box(Vector3(c.x - sx * 0.3, ry2 + 0.85, c.z + sz * 0.3), Vector3(1.0, 0.12, 0.7), "dark", mirror, 0.0, false)
		_cyl(Vector3(c.x + sx * 0.32, ry2, c.z + sz * 0.3), 0.06, 3.2, "dark", mirror, false)
		_box(Vector3(c.x + sx * 0.32, ry2 + 2.7, c.z + sz * 0.3), Vector3(0.9, 0.04, 0.04), "dark", mirror, 0.0, false)
		if sx > 11.0:
			_model("toon/Building/Water_Tank_Floor", Vector3(c.x + sx * 0.1, ry2, c.z - sz * 0.3), PI * 0.5, 0.8, mirror)
	if not pitched:
		# A cornice round the roof line, standing proud of the walls.
		var cy := c.y + floors * FLOOR_H - 0.12
		_box(Vector3(c.x, cy, z0 - 0.06), Vector3(sx + 0.36, 0.24, 0.16), trim, mirror, 0.0, false)
		_box(Vector3(c.x, cy, z1 + 0.06), Vector3(sx + 0.36, 0.24, 0.16), trim, mirror, 0.0, false)
		_box(Vector3(x0 - 0.06, cy, c.z), Vector3(0.16, 0.24, sz + 0.04), trim, mirror, 0.0, false)
		_box(Vector3(x1 + 0.06, cy, c.z), Vector3(0.16, 0.24, sz + 0.04), trim, mirror, 0.0, false)
	if not pitched:
		var y := c.y + floors * FLOOR_H
		# Stop parapet runs at their corner joints so rounded segments do not
		# intersect through each other at the outside edges.
		_wall_x(z0 + 0.15, x0 + 0.45, x1 - 0.45, y, 1.0, mat, [], mirror, 0.3)
		_wall_x(z1 - 0.15, x0 + 0.45, x1 - 0.45, y, 1.0, mat, [], mirror, 0.3)
		_wall_z(x0 + 0.15, z0 + 0.45, z1 - 0.45, y, 1.0, mat, [], mirror, 0.3)
		_wall_z(x1 - 0.15, z0 + 0.45, z1 - 0.45, y, 1.0, mat, [], mirror, 0.3)
		for x_corner in [x0 + 0.15, x1 - 0.15]:
			for z_corner in [z0 + 0.15, z1 - 0.15]:
				_box(Vector3(x_corner, y + 0.5, z_corner), Vector3(0.3, 1.0, 0.3), mat, mirror)
		if theme.neon:
			_box(Vector3(c.x, y + 1.02, z0 + 0.15), Vector3(sx, 0.06, 0.34), "accent_b", mirror, 0.0, false)
			_box(Vector3(c.x, y + 1.02, z1 - 0.15), Vector3(sx, 0.06, 0.34), "accent_b", mirror, 0.0, false)
	if opts.has("style"):
		Arch.exterior(self, opts.style, c, sx, sz, floors, mat, opts)


## Facade details for one storey: window sills, lintels and shutters, a porch
## roof with posts and a step at each ground-floor door, a string course
## between storeys. Visual only except the porch roof.
func _facade(c: Vector3, sx: float, sz: float, y0: float, f: int, win_x: Array, win_z: Array, pitched: bool, mirror: bool) -> void:
	var trim := "trim" if _mats.has("trim") else "block_a"
	var shut := "roof_red" if _mats.has("roof_red") else "block_c"
	var x0 := c.x - sx * 0.5
	var x1 := c.x + sx * 0.5
	var z0 := c.z - sz * 0.5
	var z1 := c.z + sz * 0.5
	for w in win_x:
		for side in ([[z1, 1.0]] if f == 0 else [[z1, 1.0], [z0, -1.0]]):
			var z: float = side[0] + side[1] * 0.05
			_box(Vector3(w[0], y0 + WIN_LO - 0.05, z), Vector3(WIN_W + 0.3, 0.1, 0.22), trim, mirror, 0.0, false)
			_box(Vector3(w[0], y0 + WIN_HI + 0.06, z), Vector3(WIN_W + 0.2, 0.12, 0.14), trim, mirror, 0.0, false)
			for sgn in [-1.0, 1.0]:
				_box(Vector3(w[0] + sgn * (WIN_W * 0.5 + 0.05), y0 + WIN_MID, z), Vector3(0.1, WIN_HI - WIN_LO + 0.05, 0.14), trim, mirror, 0.0, false)
			if pitched:
				for sgn in [-1.0, 1.0]:
					_box(Vector3(w[0] + sgn * (WIN_W * 0.5 + 0.23), y0 + WIN_MID, z), Vector3(0.36, WIN_HI - WIN_LO, 0.06), shut, mirror, 0.0, false)
	for w in win_z:
		for side in ([[x0, -1.0]] if f == 0 else [[x0, -1.0], [x1, 1.0]]):
			var x: float = side[0] + side[1] * 0.05
			_box(Vector3(x, y0 + WIN_LO - 0.05, w[0]), Vector3(0.22, 0.1, WIN_W + 0.3), trim, mirror, 0.0, false)
			_box(Vector3(x, y0 + WIN_HI + 0.06, w[0]), Vector3(0.14, 0.12, WIN_W + 0.2), trim, mirror, 0.0, false)
			for sgn in [-1.0, 1.0]:
				_box(Vector3(x, y0 + WIN_MID, w[0] + sgn * (WIN_W * 0.5 + 0.05)), Vector3(0.14, WIN_HI - WIN_LO + 0.05, 0.1), trim, mirror, 0.0, false)
			if pitched:
				for sgn in [-1.0, 1.0]:
					_box(Vector3(x, y0 + WIN_MID, w[0] + sgn * (WIN_W * 0.5 + 0.23)), Vector3(0.06, WIN_HI - WIN_LO, 0.36), shut, mirror, 0.0, false)
	if f == 0:
		# Porches: south door (z0 side) and east door (x1 side).
		_box(Vector3(c.x, y0 + 2.75, z0 - 0.75), Vector3(3.0, 0.14, 1.6), shut, mirror)
		_box(Vector3(c.x, y0 + 0.02, z0 - 0.7), Vector3(2.4, 0.04, 1.4), trim, mirror, 0.0, false)
		_box(Vector3(x1 + 0.75, y0 + 2.75, c.z), Vector3(1.6, 0.14, 3.0), shut, mirror)
		_box(Vector3(x1 + 0.7, y0 + 0.02, c.z), Vector3(1.4, 0.04, 2.4), trim, mirror, 0.0, false)
		for sgn in [-1.0, 1.0]:
			_cyl(Vector3(c.x + sgn * 1.35, y0, z0 - 1.4), 0.07, 2.7, trim, mirror, false)
			_cyl(Vector3(x1 + 1.4, y0, c.z + sgn * 1.35), 0.07, 2.7, trim, mirror, false)
			_box(Vector3(c.x + sgn * 1.0, y0 + 1.25, z0 - 0.02), Vector3(0.14, 2.5, 0.16), trim, mirror, 0.0, false)
			_box(Vector3(x1 + 0.02, y0 + 1.25, c.z + sgn * 1.0), Vector3(0.16, 2.5, 0.14), trim, mirror, 0.0, false)
	else:
		# Perimeter string-course only. A full-footprint trim slab here used to
		# cover the stairwell cutout made by _slab(), so players hit an invisible
		# floor while climbing.
		# The band stands 6 cm proud of the wall (never flush with it).
		var band := 0.18
		_box(Vector3(c.x, y0, z0 + 0.03), Vector3(sx + 0.12, 0.12, band), trim, mirror, 0.0, false)
		_box(Vector3(c.x, y0, z1 - 0.03), Vector3(sx + 0.12, 0.12, band), trim, mirror, 0.0, false)
		_box(Vector3(x0 + 0.03, y0, c.z), Vector3(band, 0.12, sz - 0.26), trim, mirror, 0.0, false)
		_box(Vector3(x1 - 0.03, y0, c.z), Vector3(band, 0.12, sz - 0.26), trim, mirror, 0.0, false)


## A dense patch of woodland in `r`: mostly light low-poly trees (cheap), a
## few detailed ones, with undergrowth, logs and rocks. Trunks collide.
func _forest(r: Rect2, count: int, mirror := true) -> void:
	var light := ["survival/Tree", "survival/Tree_Tall", "survival/Tree_Large", "survival/Tree_Fall", "survival/Tree_Autumn", "toon/Plant/Tree_1", "toon/Plant/Tree_3"]
	for i in count:
		var p := Vector3(_rng.randf_range(r.position.x, r.end.x), 0, _rng.randf_range(r.position.y, r.end.y))
		var roll := _rng.randf()
		if roll < 0.04:
			_pine(p, _rng.randf_range(0.9, 1.4), mirror)
		elif roll < 0.07:
			_tree(p, _rng.randf_range(0.9, 1.3), mirror)
		else:
			var path: String = light[_rng.randi() % light.size()]
			var s := _rng.randf_range(3.6, 5.2) if path.begins_with("survival") else _rng.randf_range(0.9, 1.4)
			_model(path, p, _rng.randf() * TAU, s, mirror, "none")
			_trunk(p, 0.28, 3.0, mirror)
	for i in count / 2:
		var p := Vector3(_rng.randf_range(r.position.x, r.end.x), 0, _rng.randf_range(r.position.y, r.end.y))
		var roll := _rng.randf()
		if roll < 0.45:
			_plant(p, _rng.randf_range(0.8, 1.3), mirror)
		elif roll < 0.7:
			_bush(p, _rng.randf_range(0.7, 1.2), mirror)
		elif roll < 0.85:
			_model("survival/Tree_Log", p, _rng.randf() * TAU, 3.0, mirror)
		else:
			_model(_pick(["survival/Rock_A", "survival/Rock_B", "survival/Rock_C"]), p, _rng.randf() * TAU, 2.6, mirror)
	no_grass.append(r)


## A camp: tents round a fire (with a flickering-free warm light), bedrolls,
## crates and a log to sit on.
func _camp(pos: Vector3, mirror := true) -> void:
	_model("survival/Campfire", pos, 0.0, 3.2, mirror, "none")
	for fp in ([pos, Vector3(-pos.x, pos.y, -pos.z)] if mirror else [pos]):
		Fx.fire_patch(self, fp + Vector3(0, 0.25, 0), 0.35, 0.0, false)
	_glow(pos + Vector3(0, 1.0, 0), Color(1.0, 0.6, 0.25), 9.0, 2.2 / maxf(light_scale, 0.5), mirror)
	_model("survival/Tent", pos + Vector3(4.6, 0, 1.6), -1.2, 5.0, mirror)
	_model("survival/Tent_Canvas", pos + Vector3(-4.2, 0, 3.6), 0.9, 5.0, mirror)
	_model("survival/Tree_Log", pos + Vector3(0.2, 0, -3.0), PI * 0.5, 2.6, mirror)
	_model("survival/Bedroll", pos + Vector3(-3.0, 0, -1.6), 0.5, 3.0, mirror, "none")
	_prop("survival/Box", pos + Vector3(2.0, 0.05, -2.0), 0.4, 3.0, 5.0, mirror)
	_prop("survival/Bucket", pos + Vector3(1.2, 0.05, 1.8), 0.0, 2.6, 1.5, mirror)
	_prop("survival/Bottle", pos + Vector3(-0.9, 0.05, -1.6), 0.0, 2.6, 0.5, mirror)
	no_grass.append(Rect2(pos.x - 2.0, pos.z - 2.0, 4.0, 4.0))
	no_grass.append(Rect2(-pos.x - 2.0, -pos.z - 2.0, 4.0, 4.0))


## A sidewalk with a kerb along a road edge (visual; 6 cm high).
func _sidewalk(r: Rect2, mirror := true) -> void:
	var mat := "path" if _mats.has("path") else "block_a"
	_surface(r, 0.03, mat, mirror)
	no_grass.append(r)
	if mirror:
		no_grass.append(Rect2(-r.end.x, -r.end.y, r.size.x, r.size.y))


## Zebra crossing: stripes across a road. along_x = the road runs along X.
func _crossing(centre: Vector3, road_w: float, along_x := true, mirror := true) -> void:
	for i in 6:
		var o := (i - 2.5) * (road_w / 6.5)
		var p := centre + (Vector3(0, 0.024, o) if along_x else Vector3(o, 0.024, 0))
		_box(p, Vector3(2.4, 0.01, road_w / 13.0) if along_x else Vector3(road_w / 13.0, 0.01, 2.4), "trim" if _mats.has("trim") else "line", mirror, 0.0, false)


## An underground passage along X at `z` from x0 to x1, with ramps down at
## both ends (open holes in the ground with guard rails).
## Below-ground walls sit this far inside a hole's edge (no z-fighting).
const ZF := 0.015


func _tunnel(z: float, x0: float, x1: float, mirror := true, w := 3.2) -> void:
	var L := 6.5
	var mid := (x0 + x1) * 0.5
	_hole(Rect2(x0, z - w * 0.5, L, w), mirror)
	_hole(Rect2(x1 - L, z - w * 0.5, L, w), mirror)
	_wedge(Vector3(x0 + L * 0.5, -DEPTH, z), Vector3(L, DEPTH, w), PI, "deck", mirror)
	_wedge(Vector3(x1 - L * 0.5, -DEPTH, z), Vector3(L, DEPTH, w), 0.0, "deck", mirror)
	_box(Vector3(mid, -DEPTH - 0.5, z), Vector3(x1 - x0 + 0.6, 1.0, w + 0.6), "path" if theme.paths else "block_a", mirror)
	var wh := DEPTH - 0.02
	# Walls stand ZF inside the hole's edge: exactly flush, the ground's cut
	# face and the wall fought over the same pixels (flicker).
	for sgn in [1.0, -1.0]:
		_box(Vector3(mid, -DEPTH + wh * 0.5, z + sgn * (w * 0.5 + 0.15 - ZF)), Vector3(x1 - x0 + 0.6, wh, 0.3), "wall", mirror)
		_box(Vector3(x0 + L * 0.5, 0.5, z + sgn * (w * 0.5 + 0.08)), Vector3(L, 1.0, 0.1), "rail", mirror)
		_box(Vector3(x1 - L * 0.5, 0.5, z + sgn * (w * 0.5 + 0.08)), Vector3(L, 1.0, 0.1), "rail", mirror)
	_box(Vector3(x0 - 0.15 + ZF, -DEPTH + wh * 0.5, z), Vector3(0.3, wh, w), "wall", mirror)
	_box(Vector3(x1 + 0.15 - ZF, -DEPTH + wh * 0.5, z), Vector3(0.3, wh, w), "wall", mirror)
	_box(Vector3(x0 + L + 0.05, 0.5, z), Vector3(0.1, 1.0, w), "rail", mirror)
	_box(Vector3(x1 - L - 0.05, 0.5, z), Vector3(0.1, 1.0, w), "rail", mirror)
	_box(Vector3(mid, -1.05, z), Vector3(maxf(1.0, x1 - x0 - 2.0 * L), 0.06, 0.18), "accent_b", mirror, 0.0, false)
	var n := maxi(2, int((x1 - x0) / 9.0))
	for i in n:
		_glow(Vector3(lerpf(x0 + L, x1 - L, (i + 0.5) / n), -1.6, z), theme.accent_b, 7.0, 1.4 / maxf(light_scale, 0.4), mirror)


## A room below ground (rect r in XZ) entered by a ramp along its south edge.
func _basement(r: Rect2, mirror := true) -> void:
	var L := 6.5
	var rw := 2.8
	_hole(Rect2(r.position.x, r.position.y, L, rw), mirror)
	_wedge(Vector3(r.position.x + L * 0.5, -DEPTH, r.position.y + rw * 0.5), Vector3(L, DEPTH, rw), PI, "deck", mirror)
	var c := r.get_center()
	_box(Vector3(c.x, -DEPTH - 0.5, c.y), Vector3(r.size.x + 0.6, 1.0, r.size.y + 0.6), "block_a", mirror)
	var wh := DEPTH - 0.02
	_box(Vector3(c.x, -DEPTH + wh * 0.5, r.position.y - 0.15 + ZF), Vector3(r.size.x + 0.6, wh, 0.3), "wall", mirror)
	_box(Vector3(c.x, -DEPTH + wh * 0.5, r.end.y + 0.15 - ZF), Vector3(r.size.x + 0.6, wh, 0.3), "wall", mirror)
	_box(Vector3(r.position.x - 0.15 + ZF, -DEPTH + wh * 0.5, c.y), Vector3(0.3, wh, r.size.y), "wall", mirror)
	_box(Vector3(r.end.x + 0.15 - ZF, -DEPTH + wh * 0.5, c.y), Vector3(0.3, wh, r.size.y), "wall", mirror)
	_box(Vector3(r.position.x + L * 0.5, 0.5, r.position.y + rw + 0.05), Vector3(L, 1.0, 0.1), "rail", mirror)
	_box(Vector3(r.position.x + L + 0.05, 0.5, r.position.y + rw * 0.5), Vector3(0.1, 1.0, rw), "rail", mirror)
	_box(Vector3(c.x + r.size.x * 0.2, -DEPTH + 0.6, c.y + r.size.y * 0.15), Vector3(1.2, 1.2, 1.2), "crate", mirror, 0.3)
	_box(Vector3(c.x - r.size.x * 0.25, -DEPTH + 0.6, r.end.y - 1.0), Vector3(2.2, 1.2, 1.0), "block_c", mirror)
	_box(Vector3(c.x, -1.05, c.y), Vector3(r.size.x * 0.6, 0.06, 0.18), "accent_a", mirror, 0.0, false)
	_glow(Vector3(c.x, -1.6, c.y), theme.accent_a, maxf(r.size.x, r.size.y), 1.8 / maxf(light_scale, 0.4), mirror)


## A shipping container resting on `base` (its floor centre), with dark end frames.
func _container(base: Vector3, yaw: float, mat: String, length := 6.0, mirror := true) -> void:
	var red := mat.contains("red") or mat == "block_b"
	_model("zombie/Prop/Container_Red" if red else "zombie/Prop/Container_Green", base, yaw, Vector3(length / 5.71, 1.0, 0.98), mirror)


## A glowing wall sign (visual only) with a matching light.
func _sign(pos: Vector3, size: Vector3, mat: String, mirror := true) -> void:
	_box(pos, size + Vector3(0.3, 0.3, 0.3) * Vector3(1.0 if size.x > 0.2 else 0.0, 1.0, 1.0 if size.z > 0.2 else 0.0), "dark", mirror, 0.0, false)
	var inward := Vector3(-signf(pos.x) if size.x <= 0.2 else 0.0, 0, -signf(pos.z) if size.z <= 0.2 else 0.0)
	_box(pos + inward * 0.06, size, mat, mirror, 0.0, false)
	_glow(pos + inward * 1.5, theme.accent_a if mat == "accent_a" else theme.accent_b, 9.0, 1.4, mirror)


func _barrel(pos: Vector3, mirror := true) -> void:
	_model("toon/Prop/Exploding_Barrel", pos, _rng.randf() * TAU, Vector3(1.08, 1.18, 1.08), mirror, "none")
	for s in ([pos, Vector3(-pos.x, pos.y, -pos.z)] if mirror else [pos]):
		var shape := CylinderShape3D.new()
		shape.radius = 0.42
		shape.height = 1.2
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = s + Vector3(0, 0.6, 0)
		_body.add_child(cs)


## Launches any player that steps on it straight up.
func _jump_pad(pos: Vector3, power: float, mirror := true) -> void:
	for s in ([pos, Vector3(-pos.x, pos.y, -pos.z)] if mirror else [pos]):
		_cyl(s, 1.25, 0.14, "dark", false, false, 1.15)
		_cyl(s + Vector3(0, 0.13, 0), 0.9, 0.06, "pad", false, false)
		_glow(s + Vector3(0, 1.2, 0), Color(0.3, 1.0, 0.85), 6.0, 1.6 / maxf(light_scale, 0.5), false)
		var torus := TorusMesh.new()
		torus.inner_radius = 0.78
		torus.outer_radius = 0.9
		torus.rings = 28
		torus.ring_segments = 6
		for i in 3:
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			m.albedo_color = Color(0.4, 1.4, 1.2, 0.8)
			var holder := Node3D.new()
			holder.position = s
			add_child(holder)
			var ring := MeshInstance3D.new()
			ring.mesh = torus
			ring.material_override = m
			ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ring.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			holder.add_child(ring)
			_pad_rings.append([ring, m, i / 3.0])
		var area := Area3D.new()
		area.collision_layer = 0
		area.collision_mask = 2
		var shape := CylinderShape3D.new()
		shape.radius = 1.0
		shape.height = 0.8
		var cs := CollisionShape3D.new()
		cs.shape = shape
		area.add_child(cs)
		area.position = s + Vector3(0, 0.4, 0)
		add_child(area)
		area.body_entered.connect(func(body):
			if body.has_method("launch"):
				body.launch(Vector3(body.velocity.x, power, body.velocity.z))
				Sfx.play_at("pad", body.global_position, -5.0))


## A glowing lava channel that burns anyone standing in it, behind a low kerb
## on its arena-centre side (bots never path across the kerb).
func _lava(center: Vector3, size: Vector3) -> void:
	for sgn in [1.0, -1.0]:
		var c := Vector3(center.x * sgn, center.y, center.z * sgn)
		_visual(c + Vector3(0, 0.03, 0), Vector3(size.x, 0.06, size.z), "lava")
		var kerb := c + Vector3(0, 0.3, -sgn * (size.z * 0.5 + 0.15))
		_collider(kerb, Vector3(size.x + 0.6, 0.6, 0.3))
		_visual(kerb, Vector3(size.x + 0.6, 0.6, 0.3), "block_b")
		var area := Area3D.new()
		area.collision_layer = 0
		area.collision_mask = 2
		var shape := BoxShape3D.new()
		shape.size = Vector3(size.x, 1.0, size.z)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		area.add_child(cs)
		area.position = c + Vector3(0, 0.5, 0)
		add_child(area)
		_hazards.append(area)
		for i in 3:
			_glow(c + Vector3((i - 1) * size.x * 0.33, 1.0, -sgn * 0.5), Color(1.0, 0.4, 0.1), 8.0, 1.5 / maxf(light_scale, 0.5), false)
		# Embers and heat rising off the molten rock.
		Fx.ember_field(self, c + Vector3(0, 0.1, 0), Vector3(size.x * 0.5, 0.05, size.z * 0.5))


func _spawns(points: Array, mirror := true) -> void:
	for p in points:
		spawn_points.append(p)
		if mirror:
			spawn_points.append(Vector3(-p.x, p.y, -p.z))


func _pickups(spots: Array, mirror := true) -> void:
	for spot in spots:
		pickup_spots.append(spot)
		if mirror:
			pickup_spots.append([spot[0], Vector3(-spot[1].x, spot[1].y, -spot[1].z)])


func _lawn(r: Rect2, mirror := true) -> void:
	lawns.append(r)
	if mirror:
		lawns.append(Rect2(-r.end.x, -r.end.y, r.size.x, r.size.y))


## A street lamp: pole, glowing head and (scaled by time of day) a light.
func _lamp_post(pos: Vector3, mirror := true, h := 4.6) -> void:
	var k := h / 5.4
	for s in ([[pos, 0.0], [Vector3(-pos.x, pos.y, -pos.z), PI]] if mirror else [[pos, 0.0]]):
		var p: Vector3 = s[0]
		var rot := Basis(Vector3.UP, s[1])
		_model("toon/Prop/Street_Light", p, s[1], k, false, "none")
		_collider(p + Vector3(0, h * 0.5, 0), Vector3(0.25, h, 0.25))
		var head: Vector3 = p + rot * Vector3(0, 5.25 * k, 1.75 * k)
		_box(head, Vector3(0.36, 0.05, 0.5), "lamp", false, s[1], false)
		if night_amount > 0.0:
			var l := OmniLight3D.new()
			l.position = head - Vector3(0, 0.4, 0)
			l.light_color = Color(1.0, 0.82, 0.55)
			l.light_energy = 2.4 * night_amount
			l.omni_range = 11.0
			add_child(l)


# --------------------------------------------------------------------------
# Foliage
# --------------------------------------------------------------------------

## Lumpy leaf-cluster meshes: spheres displaced by 3D noise. Cached.
func _blob(i: int) -> ArrayMesh:
	if _blob_cache.is_empty():
		for v in 3:
			var sm := SphereMesh.new()
			sm.radius = 1.0
			sm.height = 2.0
			sm.radial_segments = 20
			sm.rings = 10
			var arr := sm.get_mesh_arrays()
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var nz := FastNoiseLite.new()
			nz.seed = 31 + v * 17
			nz.frequency = 0.9
			for k in verts.size():
				var p := verts[k]
				var d := 1.0 + nz.get_noise_3dv(p * 1.6) * 0.38
				if p.y < -0.2:
					p.y *= 0.7
				verts[k] = p * d
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			for k in idx:
				st.add_vertex(verts[k])
			st.generate_normals()
			_blob_cache.append(st.commit())
	return _blob_cache[i % _blob_cache.size()]


## A broad-leaved tree: tapered trunk, branches and a canopy of leaf clusters.
## A leafy tree (one of five models) with a collidable trunk.
func _tree(pos: Vector3, scl := 1.0, mirror := true) -> void:
	var path := _pick(["nature/Tree/Common_Tree_1", "nature/Tree/Common_Tree_2", "nature/Tree/Common_Tree_3", "nature/Tree/Common_Tree_4", "nature/Tree/Common_Tree_5"])
	_model(path, pos, _rng.randf() * TAU, scl * 0.72, mirror, "none")
	_trunk(pos, 0.3 * scl, 4.0 * scl, mirror)


func _trunk(pos: Vector3, r: float, h: float, mirror: bool) -> void:
	for s in ([pos, Vector3(-pos.x, pos.y, -pos.z)] if mirror else [pos]):
		var shape := CylinderShape3D.new()
		shape.radius = r
		shape.height = h
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = s + Vector3(0, h * 0.5, 0)
		_body.add_child(cs)


func _bush(pos: Vector3, scl := 1.0, mirror := true) -> void:
	var path := "nature/Bush/Bush_Common_Flowers" if _rng.randf() < 0.3 else "nature/Bush/Bush_Common"
	_model(path, pos, _rng.randf() * TAU, scl * 0.75, mirror, "none")


## A pine (one of five models) with a collidable trunk.
func _pine(pos: Vector3, scl := 1.0, mirror := true) -> void:
	var path := _pick(["nature/Tree/Pine_1", "nature/Tree/Pine_2", "nature/Tree/Pine_3", "nature/Tree/Pine_4", "nature/Tree/Pine_5"])
	_model(path, pos, _rng.randf() * TAU, scl * 0.85, mirror, "none")
	_trunk(pos, 0.35 * scl, 4.0 * scl, mirror)


## A boulder (visual + box collider).
func _rock(pos: Vector3, scl := 1.0, mirror := true) -> void:
	var path := _pick(["nature/Rock/Rock_Medium_1", "nature/Rock/Rock_Medium_2", "nature/Rock/Rock_Medium_3"])
	_model(path, pos + Vector3(0, -0.15 * scl, 0), _rng.randf() * TAU, scl, mirror)


## Ground plants (visual only).
func _plant(pos: Vector3, scl := 1.0, mirror := true) -> void:
	var path := _pick(["nature/Plant/Fern_1", "nature/Plant/Plant_1", "nature/Plant/Plant_7", "nature/Plant/Plant_7_Big", "nature/Plant/Plant_1_Big"])
	_model(path, pos, _rng.randf() * TAU, scl, mirror, "none", false)


const GRASS_SHADER := """
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled;
uniform vec3 base : source_color = vec3(0.1, 0.3, 0.1);
uniform vec3 tip : source_color = vec3(0.3, 0.6, 0.2);
void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float bend = 1.0 - UV.y;
	float wave = sin(TIME * 1.6 + wp.x * 0.5 + wp.z * 0.7) + 0.5 * sin(TIME * 2.7 + wp.x * 1.3);
	VERTEX.x += wave * 0.05 * bend;
	VERTEX.z += wave * 0.035 * bend;
	NORMAL = vec3(0.0, 1.0, 0.0);
}
void fragment() {
	ALBEDO = mix(base, tip, (1.0 - UV.y) * 0.9) * COLOR.rgb;
	ROUGHNESS = 1.0;
}
"""


# --------------------------------------------------------------------------
# Ground: occupancy grid, gentle mounds, grass / flowers / undergrowth
# --------------------------------------------------------------------------

const OCC := 0.5                 # occupancy grid cell (m)

## Dev (--audit): print every placed model whose box cuts into a world
## collider that is not its own (cars in houses, props in walls...).
func _audit_report() -> void:
	var boxes: Array = []
	for i in _body.get_child_count():
		var cs = _body.get_child(i)
		if cs is CollisionShape3D and cs.shape is BoxShape3D:
			var ext: Vector3 = (cs.shape as BoxShape3D).size * 0.5
			var bx: Vector3 = cs.transform.basis.x.abs() * ext.x + cs.transform.basis.z.abs() * ext.z
			boxes.append([i, cs.transform.origin, Vector3(bx.x, ext.y, bx.z)])
	var n := 0
	for m in _audit_models:
		var ext2: Vector3 = m[2] * 0.5
		var rot := Basis(Vector3.UP, m[3])
		var mx: Vector3 = rot.x.abs() * ext2.x + rot.z.abs() * ext2.z
		var me := Vector3(mx.x, ext2.y, mx.z) * 0.82
		for b in boxes:
			if b[0] == m[4] - 1 or b[1].y + b[2].y < 0.05:
				continue
			var d: Vector3 = (m[1] - b[1]).abs()
			if d.x < me.x + b[2].x - 0.05 and d.y < me.y + b[2].y - 0.05 and d.z < me.z + b[2].z - 0.05 and b[2].x * b[2].z < 400.0:
				n += 1
				print("[audit] %s at %s overlaps collider at %s size %s" % [m[0], (m[1] as Vector3).snapped(Vector3.ONE * 0.1), (b[1] as Vector3).snapped(Vector3.ONE * 0.1), ((b[2] as Vector3) * 2.0).snapped(Vector3.ONE * 0.1)])
				break
	print("[audit] %s: %d of %d models overlap something" % [MAPS[map_index].name, n, _audit_models.size()])


## Mark every ground cell something stands on (walls, buildings, trunks,
## paved surfaces, holes, no_grass rects). Ground cover and mounds ask
## _occupied() instead of testing hundreds of boxes per sample.
func _occ_build() -> void:
	_occ_w = int(ceil(half_x * 2.0 / OCC)) + 2
	_occ_h = int(ceil(half_z * 2.0 / OCC)) + 2
	_occ = PackedByteArray()
	_occ.resize(_occ_w * _occ_h)
	for cs in _body.get_children():
		if not cs is CollisionShape3D:
			continue
		var o: Vector3 = cs.transform.origin
		var ext := Vector3.ZERO
		if cs.shape is BoxShape3D:
			ext = (cs.shape as BoxShape3D).size * 0.5
			# A turned box covers a bit more ground than its own half-size.
			var bx: Vector3 = cs.transform.basis.x.abs() * ext.x + cs.transform.basis.z.abs() * ext.z
			ext = Vector3(bx.x, ext.y, bx.z)
		elif cs.shape is CylinderShape3D:
			var cy: CylinderShape3D = cs.shape
			ext = Vector3(cy.radius, cy.height * 0.5, cy.radius)
		else:
			continue
		if o.y - ext.y > 0.45 or o.y + ext.y < 0.03:
			continue
		_occ_rect(Rect2(o.x - ext.x, o.z - ext.z, ext.x * 2.0, ext.z * 2.0).grow(0.15))
	for r in _paved + no_grass + _holes:
		_occ_rect((r as Rect2).grow(0.1))
	for c in _occ_extra:
		_occ_rect(Rect2(c.x - c.z, c.y - c.z, c.z * 2.0, c.z * 2.0))


func _occ_rect(r: Rect2) -> void:
	var x0 := clampi(int(floor((r.position.x + half_x) / OCC)), 0, _occ_w - 1)
	var x1 := clampi(int(floor((r.end.x + half_x) / OCC)), 0, _occ_w - 1)
	var z0 := clampi(int(floor((r.position.y + half_z) / OCC)), 0, _occ_h - 1)
	var z1 := clampi(int(floor((r.end.y + half_z) / OCC)), 0, _occ_h - 1)
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			_occ[z * _occ_w + x] = 1


func _occupied(x: float, z: float) -> bool:
	var cx := int(floor((x + half_x) / OCC))
	var cz := int(floor((z + half_z) / OCC))
	if cx < 0 or cz < 0 or cx >= _occ_w or cz >= _occ_h:
		return true
	return _occ[cz * _occ_w + cx] != 0


## True when a disc of `radius` around (x, z) touches nothing.
func _clear_disc(x: float, z: float, radius: float) -> bool:
	if _occupied(x, z):
		return false
	for ring in [0.5, 1.0]:
		for i in 10:
			var a := TAU * i / 10.0
			if _occupied(x + cos(a) * radius * ring, z + sin(a) * radius * ring):
				return false
	return true


## Height of the ground at (x, z): 0, or up a mound.
func ground_y(x: float, z: float) -> float:
	var y := 0.0
	for m in mounds:
		var d := Vector2(x - m.x, z - m.y).length()
		if d < m.z:
			var big: float = (m.z * m.z + m.w * m.w) / (2.0 * m.w)
			y = maxf(y, sqrt(big * big - d * d) - (big - m.w))
	return y


## Gentle grassy mounds on open ground, so outdoor maps are not one flat
## plane. Each is a shallow dome (a cap of a big sphere: 4-7 m wide, up to
## about 1 m high) with a matching convex collider; you walk straight over
## them and they break up sight lines a little. Seeded per map.
func _mounds() -> void:
	if indoor or not theme.get("cover", false) or OS.get_environment("SLOP_TEST") == "nomounds":
		return
	var want := clampi(int(half_x * half_z / 150.0), 4, 34)
	var tries := 0
	while mounds.size() < want and tries < want * 30:
		tries += 1
		var a := _rng.randf_range(3.6, 7.0)
		var h := a * _rng.randf_range(0.11, 0.17)
		var x := _rng.randf_range(-half_x + a + 1.0, half_x - a - 1.0)
		var z := _rng.randf_range(-half_z + a + 1.0, half_z - a - 1.0)
		if not _clear_disc(x, z, a + 0.8):
			continue
		var ok := true
		for s in spawn_points:
			if Vector2(s.x - x, s.z - z).length() < a + 2.0:
				ok = false
		for s in pickup_spots:
			if Vector2(s[1].x - x, s[1].z - z).length() < a + 2.0:
				ok = false
		for m in mounds:
			if Vector2(m.x - x, m.y - z).length() < a + m.z:
				ok = false
		for hole in _holes:
			if (hole as Rect2).grow(a + 1.0).has_point(Vector2(x, z)):
				ok = false
		if not ok:
			continue
		mounds.append(Vector4(x, z, a, h))
		var big := (a * a + h * h) / (2.0 * h)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var rings := 7
		var seg := 28
		var pts := PackedVector3Array()
		var grid: Array = []
		for r in rings + 1:
			var d := a * r / rings
			var y := sqrt(big * big - d * d) - (big - h)
			var row: Array = []
			for sI in seg:
				var ang := TAU * sI / seg
				var v := Vector3(cos(ang) * d, y, sin(ang) * d)
				row.append(v)
				if r == 0:
					break
			grid.append(row)
		for r in rings:
			for sI in seg:
				var i0: Vector3 = grid[r][0] if r == 0 else grid[r][sI]
				var i1: Vector3 = grid[r][0] if r == 0 else grid[r][(sI + 1) % seg]
				var o0: Vector3 = grid[r + 1][sI]
				var o1: Vector3 = grid[r + 1][(sI + 1) % seg]
				var tris := [[i0, o1, o0]] if r == 0 else [[i0, i1, o1], [i0, o1, o0]]
				for tri in tris:
					for v in tri:
						st.set_normal((Vector3(v.x, v.y + big - h, v.z)).normalized())
						st.add_vertex(v)
		# The collider is a much coarser hull than the mesh (25 points): a
		# detailed one made every character standing on a mound expensive.
		pts.append(Vector3(0, h, 0))
		for ring_d in [0.5, 1.0]:
			var dd: float = a * ring_d
			var yy := sqrt(big * big - dd * dd) - (big - h)
			for sI in 8:
				var ang2 := TAU * sI / 8.0
				pts.append(Vector3(cos(ang2) * dd, yy, sin(ang2) * dd))
		for sI in 8:
			var ang3 := TAU * sI / 8.0
			pts.append(Vector3(cos(ang3) * a, -0.4, sin(ang3) * a))
		_add(st.commit(), _mats["ground"], Transform3D(Basis(), Vector3(x, 0, z)), true, 0, "mound")
		var shape := ConvexPolygonShape3D.new()
		shape.points = pts
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = Vector3(x, 0, z)
		_body.add_child(cs)


const FOLIAGE_SHADER := """
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled, depth_draw_opaque;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float sway = 0.06;
varying float lift;
void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	lift = 1.0 - UV.y;
	float wave = sin(TIME * 1.5 + wp.x * 0.45 + wp.z * 0.6) + 0.5 * sin(TIME * 2.6 + wp.x * 1.2 + wp.z * 0.3);
	VERTEX.x += wave * sway * lift * lift;
	VERTEX.z += wave * sway * 0.7 * lift * lift;
	// Lit as if every card faced the sky: soft, even foliage shading.
	NORMAL = normalize(vec3(0.0, 1.0, 0.0) + NORMAL * 0.25);
}
void fragment() {
	vec4 c = texture(tex, UV);
	if (c.a < 0.45) { discard; }
	ALBEDO = c.rgb * COLOR.rgb * mix(0.62, 1.08, lift);
	ROUGHNESS = 1.0;
	BACKLIGHT = c.rgb * 0.35;
}
"""

static var _foliage_cache := {}

## Voxel grass (Voxel.on): blades are columns of voxels; colour steps from
## base to tip one voxel at a time (local height), flower heads come from the
## vertex colour (alpha 0), per-voxel light/dark from a hash, wind sway.
const VOX_GRASS_SHADER := """
shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled;
uniform vec3 base : source_color = vec3(0.3, 0.5, 0.2);
uniform vec3 tip : source_color = vec3(0.6, 0.8, 0.3);
uniform float sway = 0.06;
uniform float vs = 0.09;
varying vec3 lp;
float gh(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}
void vertex() {
	lp = VERTEX;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float lift = clamp(VERTEX.y / 0.7, 0.0, 1.0);
	float wave = sin(TIME * 1.5 + wp.x * 0.45 + wp.z * 0.6) + 0.5 * sin(TIME * 2.6 + wp.x * 1.2 + wp.z * 0.3);
	VERTEX.x += wave * sway * lift * lift;
	VERTEX.z += wave * sway * 0.7 * lift * lift;
}
void fragment() {
	vec3 cellp = floor(lp / vs + vec3(0.001));
	float t = clamp(cellp.y * vs / 0.6, 0.0, 1.0);
	vec3 c = COLOR.a < 0.5 ? COLOR.rgb : mix(base, tip, t) * COLOR.rgb;
	c *= 0.86 + 0.26 * gh(cellp + vec3(7.1, 3.3, 1.7));
	ALBEDO = c;
	ROUGHNESS = 1.0;
	BACKLIGHT = c * 0.3;
}
"""
static var _tufts := {}


## A voxel tuft for a ground-cover kind (cached): a few blades made of voxel
## columns (lower part straight, top leaning one voxel), on a 0.09 grid.
func _vox_tuft(kind: String) -> ArrayMesh:
	if _tufts.has(kind):
		return _tufts[kind]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind) + 11
	var v := 0.09
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var flower := kind.begins_with("flower")
	var petal: Color = [Color(1.0, 0.32, 0.36), Color(1.0, 0.85, 0.3), Color(0.95, 0.95, 1.0), Color(0.72, 0.45, 1.0)][int(kind.substr(6)) % 4] if flower else Color.WHITE
	var blades: int = {"grass": 9, "leafy": 6, "fern": 7}.get(kind, 6)
	var wide := 2 if kind == "leafy" else 1
	for b in blades:
		var gx := rng.randi_range(-4, 4)
		var gz := rng.randi_range(-4, 4)
		var hgt := rng.randi_range(3, 7) if kind != "leafy" else rng.randi_range(2, 4)
		var lower := maxi(1, hgt - rng.randi_range(1, 3))
		var lean := Vector2i(rng.randi_range(-1, 1), rng.randi_range(-1, 1)) * (2 if kind == "fern" else 1)
		if rng.randf() < 0.5 and kind != "fern":
			lean = Vector2i.ZERO
		var p0 := Vector3(gx * v, 0.0, gz * v)
		var p1 := p0 + Vector3(lean.x * v, lower * v, lean.y * v)
		if lean == Vector2i.ZERO:
			# A straight blade is one box (half the triangles).
			_vox_box(st, p0, Vector3(v * wide, hgt * v, v), Color.WHITE)
		else:
			_vox_box(st, p0, Vector3(v * wide, lower * v, v), Color.WHITE)
			_vox_box(st, p1, Vector3(v * wide, (hgt - lower) * v, v), Color.WHITE)
		if flower and b < 2:
			var top := p1 + Vector3(-v * 0.5, (hgt - lower) * v, -v * 0.5)
			_vox_box(st, top, Vector3(v * 2.0, v, v * 2.0), Color(petal, 0.0))
	st.generate_normals()
	var m := st.commit()
	_tufts[kind] = m
	return m


## An axis-aligned box from `p` (min x/z corner at its base) of size `s`,
## without a bottom face; colour per vertex.
static func _vox_box(st: SurfaceTool, p: Vector3, s: Vector3, col: Color) -> void:
	var c := [p, p + Vector3(s.x, 0, 0), p + Vector3(s.x, 0, s.z), p + Vector3(0, 0, s.z)]
	var u: Array = []
	for q in c:
		u.append((q as Vector3) + Vector3(0, s.y, 0))
	var quads := [[u[0], u[3], u[2], u[1]], [c[0], u[0], u[1], c[1]], [c[1], u[1], u[2], c[2]], [c[2], u[2], u[3], c[3]], [c[3], u[3], u[0], c[0]]]
	for q in quads:
		st.set_color(col)
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_color(col)
			st.add_vertex(q[idx])


## Painted foliage textures (made once, in code): alpha-cut cards in the
## Skyrim / Minecraft tradition, where a few flat pictures of many blades or
## leaves, crossed and repeated densely, read as lush undergrowth.
##   grass   a fan of tapering blades         fern    arching fronds
##   leafy   broad leaves on short stems      flower0-2  blooms among blades
static func _foliage_tex(kind: String, base: Color, tip: Color) -> ImageTexture:
	var key := "%s_%s_%s" % [kind, base.to_html(), tip.to_html()]
	if _foliage_cache.has(key):
		return _foliage_cache[key]
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(tip.r, tip.g, tip.b, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	# Grass: a few fat, soft, round-tipped blades (cartoony), not many sharp ones.
	var blades := 11 if kind == "grass" else (12 if kind.begins_with("flower") else 0)
	for i in blades:
		var x0 := rng.randf_range(n * 0.28, n * 0.72)
		var length := rng.randf_range(0.45, 0.85) * n * (0.95 if kind == "grass" else 0.6)
		var bend := rng.randf_range(-0.3, 0.3) * n * 0.5
		var w0 := rng.randf_range(6.0, 9.0) if kind == "grass" else rng.randf_range(2.6, 4.6)
		var shade := rng.randf_range(0.82, 1.15)
		_paint_blade(img, x0, length, bend, w0, base * shade, tip * shade)
	if kind == "fern":
		for i in 7:
			var ang := lerpf(-1.15, 1.15, i / 6.0) + rng.randf_range(-0.1, 0.1)
			_paint_frond(img, Vector2(n * 0.5, n - 2.0), ang, n * rng.randf_range(0.6, 0.9), base, tip, rng)
	elif kind == "leafy":
		for i in 9:
			var ang2 := lerpf(-1.25, 1.25, i / 8.0) + rng.randf_range(-0.15, 0.15)
			var reach := n * rng.randf_range(0.35, 0.72)
			var c := Vector2(n * 0.5 + sin(ang2) * reach, n - 4.0 - cos(ang2) * reach)
			_paint_blade(img, n * 0.5, reach, sin(ang2) * reach, 2.0, base * 0.8, base)
			_paint_leaf(img, c, ang2, n * rng.randf_range(0.13, 0.2), base.lerp(tip, rng.randf_range(0.3, 0.9)))
	elif kind.begins_with("flower"):
		var petal: Color = [Color(1.0, 0.97, 0.9), Color(1.0, 0.82, 0.15), Color(1.0, 0.42, 0.62), Color(0.72, 0.5, 1.0), Color(1.0, 0.4, 0.22)][int(kind.substr(6)) % 5]
		for i in 7:
			var x1 := rng.randf_range(n * 0.18, n * 0.82)
			var h := rng.randf_range(0.45, 0.92) * n
			_paint_blade(img, x1, h, rng.randf_range(-6.0, 6.0), 1.6, base * 0.9, base)
			var c2 := Vector2(x1 + rng.randf_range(-3.0, 3.0), n - h)
			var r := rng.randf_range(5.0, 8.5)
			for p in 6:
				var pa := TAU * p / 6.0
				_paint_disc(img, c2 + Vector2(cos(pa), sin(pa)) * r * 0.62, r * 0.55, petal * rng.randf_range(0.9, 1.0))
			_paint_disc(img, c2, r * 0.38, Color(1.0, 0.8, 0.2) if petal.g > 0.9 and petal.b > 0.5 else Color(0.35, 0.22, 0.1))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_foliage_cache[key] = tex
	return tex


static func _paint_blade(img: Image, x0: float, length: float, bend: float, w0: float, base: Color, tip: Color) -> void:
	var n := img.get_width()
	var steps := int(length)
	for s in steps:
		var t := float(s) / maxf(steps, 1)
		var cx := x0 + bend * t * t
		var y := n - 1 - s
		# Tapers gently, then rounds off at the tip.
		var half := maxf(0.5, w0 * (1.0 - t * 0.45) * sqrt(maxf(0.0, 1.0 - pow(maxf(0.0, (t - 0.75) / 0.25), 2.0))))
		var col := base.lerp(tip, t)
		for dx in range(-int(ceil(half)), int(ceil(half)) + 1):
			var px := int(round(cx)) + dx
			if px >= 0 and px < n and y >= 0 and absf(dx) <= half:
				var edge := 1.0 - absf(dx) / (half + 0.5) * 0.25
				img.set_pixel(px, y, Color(col.r * edge, col.g * edge, col.b * edge, 1.0))


static func _paint_disc(img: Image, c: Vector2, r: float, col: Color) -> void:
	var n := img.get_width()
	for y in range(int(c.y - r), int(c.y + r) + 1):
		for x in range(int(c.x - r), int(c.x + r) + 1):
			if x >= 0 and y >= 0 and x < n and y < n and Vector2(x, y).distance_to(c) <= r:
				img.set_pixel(x, y, Color(col.r, col.g, col.b, 1.0))


static func _paint_leaf(img: Image, c: Vector2, ang: float, size: float, col: Color) -> void:
	var n := img.get_width()
	var axis := Vector2(sin(ang), -cos(ang))
	var side := Vector2(axis.y, -axis.x)
	for y in range(int(c.y - size), int(c.y + size) + 1):
		for x in range(int(c.x - size), int(c.x + size) + 1):
			if x < 0 or y < 0 or x >= n or y >= n:
				continue
			var d := Vector2(x, y) - c
			var u := d.dot(axis) / size
			var v := d.dot(side) / (size * 0.55)
			if u * u + v * v <= 1.0 and absf(v) <= 1.0 - u * 0.5:
				var rib := 1.15 if absf(v) < 0.12 else (0.9 + 0.1 * (1.0 - absf(v)))
				img.set_pixel(x, y, Color(col.r * rib, col.g * rib, col.b * rib, 1.0))


static func _paint_frond(img: Image, root: Vector2, ang: float, length: float, base: Color, tip: Color, rng: RandomNumberGenerator) -> void:
	var steps := int(length)
	for s in steps:
		var t := float(s) / steps
		var droop := ang + signf(ang) * t * t * 0.9
		var p := root + Vector2(sin(droop), -cos(droop)) * s * (1.0 - t * 0.15)
		var col := base.lerp(tip, t * 0.8)
		_paint_disc(img, p, 1.1, col * 0.85)
		if s % 5 == 2:
			var leaf := length * 0.16 * (1.0 - t * 0.7)
			for sgn in [-1.0, 1.0]:
				_paint_leaf(img, p + Vector2(cos(droop), sin(droop)) * sgn * leaf * 0.7, droop + sgn * 1.25, leaf, col * rng.randf_range(0.9, 1.1))


## Three crossed upright cards, one metre square, feet on the ground.
func _card_mesh(planes := 3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for q in planes:
		var a := PI * q / planes
		var ax := Vector3(cos(a), 0, sin(a)) * 0.5
		var nrm := Vector3(-sin(a), 0, cos(a))
		var quad := [[-ax, Vector2(0, 1)], [ax, Vector2(1, 1)], [ax + Vector3.UP, Vector2(1, 0)], [-ax, Vector2(0, 1)], [ax + Vector3.UP, Vector2(1, 0)], [-ax + Vector3.UP, Vector2(0, 0)]]
		for vtx in quad:
			st.set_uv(vtx[1])
			st.set_normal(nrm)
			st.add_vertex(vtx[0])
	return st.commit()


## Ground cover. Where the theme says "cover" the whole open ground grows
## grass, ferns, leafy plants and flowers (everything the occupancy grid
## leaves free); other maps only grow it on their `lawns` rects.
## Everything is textured cards (_foliage_tex) in MultiMeshes split into
## 16 m chunks that are only drawn near a camera, so a lush meadow stays
## cheap in six-player splitscreen. Cards follow the mounds (ground_y) and
## sway in the wind (FOLIAGE_SHADER).
func _grass() -> void:
	if theme.grass.is_empty() or OS.get_environment("SLOP_TEST") == "nograss":
		return
	var whole: bool = theme.get("cover", false) and not indoor
	if not whole and lawns.is_empty():
		return
	var areas: Array = [Rect2(-half_x, -half_z, half_x * 2.0, half_z * 2.0)] if whole else lawns
	var area := 0.0
	for r in areas:
		area += (r as Rect2).get_area()
	var base: Color = theme.grass[0]
	var tip: Color = theme.grass[1]
	var sh := Shader.new()
	sh.code = FOLIAGE_SHADER
	# kind -> [texture kind, share of the cover, min size, max size, sway]
	var kinds := [["grass", 0.72, 0.5, 1.0, 0.07], ["leafy", 0.09, 0.5, 0.9, 0.04], ["fern", 0.08, 0.6, 1.1, 0.05],
		["flower0", 0.03, 0.45, 0.7, 0.06], ["flower1", 0.03, 0.45, 0.7, 0.06], ["flower2", 0.025, 0.45, 0.7, 0.06], ["flower3", 0.025, 0.45, 0.7, 0.06]]
	var mats: Array = []
	for k in kinds:
		var mat := ShaderMaterial.new()
		mat.shader = sh
		var b2 := base if not k[0].begins_with("f") or k[0] == "fern" else base.lerp(tip, 0.3)
		mat.set_shader_parameter("tex", _foliage_tex(k[0], b2, tip if k[0] != "fern" else tip.lerp(base, 0.35)))
		mat.set_shader_parameter("sway", k[4])
		mats.append(mat)
	var card := _card_mesh(3)
	# The voxel style: tufts of blocky voxel blades instead of painted cards.
	var vmats: Array = []
	if Voxel.on:
		var vsh := Shader.new()
		vsh.code = VOX_GRASS_SHADER
		for k in kinds:
			var vm := ShaderMaterial.new()
			vm.shader = vsh
			vm.set_shader_parameter("base", base if not k[0].begins_with("f") or k[0] == "fern" else base.lerp(tip, 0.3))
			vm.set_shader_parameter("tip", tip if k[0] != "fern" else tip.lerp(base, 0.35))
			vm.set_shader_parameter("sway", k[4])
			vmats.append(vm)
	# Sports turf (theme "mown") is kept short and free of weeds.
	var mown: bool = theme.get("mown", false)

	var density := 5.0 if area < 3000.0 else (3.8 if area < 9000.0 else 2.4)
	# (Voxel tufts are fuller than cards, so fewer of them.)
	var count := mini(int(area * density * (0.55 if Voxel.on else 1.0)), 70000)
	var chunks := {}
	var placed := 0
	var tries := 0
	# Flowers and ferns grow in patches: a slowly varying field picks the kind.
	while placed < count and tries < count * 2:
		tries += 1
		var pick := _rng.randf() * area
		var rr: Rect2 = areas[0]
		for r in areas:
			pick -= (r as Rect2).get_area()
			if pick <= 0.0:
				rr = r
				break
		var px := _rng.randf_range(rr.position.x, rr.end.x)
		var pz := _rng.randf_range(rr.position.y, rr.end.y)
		if _occupied(px, pz):
			continue
		var patch := sin(px * 0.21 + 1.3) * cos(pz * 0.17 - 0.6) + 0.5 * sin(px * 0.07 - pz * 0.11)
		var roll := _rng.randf()
		var ki := 0
		if mown:
			pass                      # a mown pitch: short grass only
		elif patch > 0.75 and roll < 0.5:
			ki = 3 + (int(floor((px + 500.0) / 9.0)) + int(floor((pz + 500.0) / 9.0))) % 4
		elif patch < -0.6 and roll < 0.45:
			ki = 2
		elif roll < 0.1:
			ki = 1
		elif roll < 0.13:
			ki = 3 + _rng.randi() % 4
		var key := Vector3i(floori(px / 16.0), floori(pz / 16.0), ki)
		if not chunks.has(key):
			chunks[key] = []
		chunks[key].append(Vector3(px, ground_y(px, pz) - 0.03, pz))
		placed += 1
	for key in chunks:
		var k: Array = kinds[key.z]
		var centre := Vector3((key.x + 0.5) * 16.0, 0.4, (key.y + 0.5) * 16.0)
		var spots: Array = chunks[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _vox_tuft(k[0]) if Voxel.on else card
		mm.instance_count = spots.size()
		for i in spots.size():
			var w := _rng.randf_range(k[2], k[3]) * (0.32 if mown else 1.0)
			var hgt := w * _rng.randf_range(0.75, 1.15)
			var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(w, hgt, w))
			mm.set_instance_transform(i, Transform3D(basis, spots[i] - centre))
			var tone := _rng.randf_range(0.8, 1.15)
			mm.set_instance_color(i, Color(tone, tone * _rng.randf_range(0.96, 1.06), tone * _rng.randf_range(0.85, 1.0)))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = vmats[key.z] if Voxel.on else mats[key.z]
		mmi.position = centre
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 62.0 if Voxel.on else 52.0
		mmi.visibility_range_end_margin = 16.0 if Voxel.on else 6.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(mmi)
	if not whole:
		return
	# Bigger undergrowth models (bushes, plants, pebbles), thicker towards the
	# edges of the map.
	var plants := clampi(int(area / 45.0), 30, 240)
	var done := 0
	tries = 0
	while done < plants and tries < plants * 8:
		tries += 1
		var px3 := _rng.randf_range(-half_x + 1.0, half_x - 1.0)
		var pz3 := _rng.randf_range(-half_z + 1.0, half_z - 1.0)
		var edge := maxf(absf(px3) / half_x, absf(pz3) / half_z)
		if _rng.randf() > 0.35 + edge * 0.65 or not _clear_disc(px3, pz3, 0.7):
			continue
		var pos := Vector3(px3, ground_y(px3, pz3), pz3)
		var roll2 := _rng.randf()
		if roll2 < 0.3:
			_bush(pos, _rng.randf_range(0.7, 1.2), false)
		elif roll2 < 0.42:
			_model(_pick(["nature/Rock/Pebble_Round_1", "nature/Rock/Pebble_Round_2", "nature/Rock/Pebble_Round_3", "nature/Rock/Pebble_Round_4"]), pos, _rng.randf() * TAU, _rng.randf_range(1.0, 2.2), false, "none", false)
		else:
			_plant(pos, _rng.randf_range(0.8, 1.5), false)
		done += 1


# --------------------------------------------------------------------------
# Layout 0: NEON YARD (medium) - a container yard
# --------------------------------------------------------------------------

func _layout_yard() -> void:
	# Concrete loading platform with steel ramps.
	_box(Vector3(0, 1.5, 0), Vector3(12, 3, 12), "block_a", false)
	_box(Vector3(0, 2.6, 0), Vector3(12.1, 0.14, 12.1), "accent_b", false, 0.0, false)
	_wedge(Vector3(10, 0, 0), Vector3(8, 3, 5), PI, "deck")
	_box(Vector3(0, 3.65, 0), Vector3(2.4, 1.3, 2.4), "crate", false, 0.5)
	_box(Vector3(4.6, 3.5, -4.2), Vector3(0.5, 1.0, 3.0), "stripes")
	_glow(Vector3(0, 5.2, 0), theme.accent_b, 13.0, 2.2, false)

	# Steel catwalk from the platform to the north deck (mirrored: south deck).
	_box(Vector3(0, 2.8, 10), Vector3(3, 0.4, 8), "deck")
	_box(Vector3(1.55, 3.45, 10), Vector3(0.15, 0.9, 8), "rail")
	_box(Vector3(-1.55, 3.45, 10), Vector3(0.15, 0.9, 8), "rail")
	_box(Vector3(0, 2.8, 18), Vector3(16, 0.4, 8), "deck")
	for px in [-7.0, 7.0]:
		for pz in [15.0, 21.0]:
			_box(Vector3(px, 1.3, pz), Vector3(0.8, 2.6, 0.8), "block_c")
			_box(Vector3(px, 1.3, pz), Vector3(0.86, 0.12, 0.86), "accent_a", true, 0.0, false)
	_wedge(Vector3(-12, 0, 18), Vector3(8, 3, 4), 0.0, "deck")
	_box(Vector3(-4.75, 3.45, 14.1), Vector3(6.5, 0.9, 0.2), "rail")
	_box(Vector3(4.75, 3.45, 14.1), Vector3(6.5, 0.9, 0.2), "rail")
	_box(Vector3(4, 3.6, 20.5), Vector3(3, 1.2, 0.5), "stripes")
	_jump_pad(Vector3(9.6, 0, 18), 14.5)
	_glow(Vector3(0, 1.6, 18), theme.accent_a, 10.0, 1.6)

	# Two-storey brick warehouse with a roof terrace, and a gantry crane over it.
	_building(Vector3(-23, 0, 13), 9.0, 9.0, 2, "block_b", {"style": "office", "tiers": 3})
	_box(Vector3(-26.5, 5.5, 7.4), Vector3(0.9, 11, 0.9), "c_yellow")
	_box(Vector3(-26.5, 5.5, 18.6), Vector3(0.9, 11, 0.9), "c_yellow")
	_box(Vector3(-26.5, 11.2, 13.0), Vector3(1.1, 0.9, 12.2), "c_yellow", true, 0.0, false)
	_box(Vector3(-26.5, 10.3, 13.0), Vector3(0.1, 1.0, 0.1), "dark", true, 0.0, false)
	_box(Vector3(-26.5, 9.3, 13.0), Vector3(2.5, 1.4, 4.0), "c_teal", true, 0.0, false)
	_box(Vector3(-26.5, 11.75, 13.0), Vector3(0.3, 0.2, 0.3), "beacon", true, 0.0, false)

	# Shipping containers: stacks to fight around and climb.
	_container(Vector3(21, 0, 13), 0.1, "c_red")
	_container(Vector3(21.4, 2.6, 13.2), 0.1, "c_blue", 4.5)
	_box(Vector3(17.1, 0.65, 13.0), Vector3(1.3, 1.3, 1.3), "crate", true, 0.3)
	_container(Vector3(25.6, 0, 18.6), PI / 2 + 0.08, "c_yellow")
	_container(Vector3(-28.3, 0, -3), PI / 2, "c_teal")
	_container(Vector3(12.5, 0, 21.2), 0.0, "c_blue", 4.5)

	# Drainage tunnels under the yard (one each side of the platform).
	_tunnel(8.0, -14.0, 14.0)

	# Blast wall, barriers, barrels, planters with trees.
	_box(Vector3(16, 2, -5), Vector3(1, 4, 9), "block_a")
	_box(Vector3(16, 4.1, -5), Vector3(1.2, 0.16, 9.2), "accent_a", true, 0.0, false)
	_box(Vector3(9, 0.6, -12.0), Vector3(5, 1.2, 0.6), "stripes")
	_box(Vector3(-12, 0.6, -13.5), Vector3(0.6, 1.2, 5), "stripes")
	_barrel(Vector3(20, 0, -20.5))
	_barrel(Vector3(21.3, 0, -19.8))
	_barrel(Vector3(-3, 0, 22.6))
	_barrel(Vector3(30.5, 0, 9))
	for p in [Vector3(29.5, 0, -16), Vector3(-20.5, 0, -22)]:
		_box(p + Vector3(0, 0.35, 0), Vector3(3.2, 0.7, 3.2), "block_a")
		_box(p + Vector3(0, 0.71, 0), Vector3(2.8, 0.04, 2.8), "soil", true, 0.0, false)
		_tree(p + Vector3(0, 0.7, 0), 0.85)
	_bush(Vector3(-30.5, 0, -22.5), 1.1)
	_bush(Vector3(-9.0, 0, -22.6), 1.0)
	_lawn(Rect2(-31.8, -23.8, 6.0, 3.2))
	_lawn(Rect2(-14.0, -23.8, 6.0, 2.2))
	# Neon signs on the perimeter.
	_sign(Vector3(-10, 3.0, half_z - 0.08), Vector3(7, 1.6, 0.1), "accent_a")
	_sign(Vector3(half_x - 0.08, 3.0, -12), Vector3(0.1, 1.4, 6), "accent_b")
	_glow(Vector3(24, 3.5, -4), theme.accent_b, 12.0, 1.5)

	_spawns([Vector3(28, 0.1, 21.5), Vector3(29.5, 0.1, -6), Vector3(-18, 0.1, 21.5),
		Vector3(24, 0.1, -21.5), Vector3(-21, 3.5, 11), Vector3(0, -DEPTH + 0.1, 8.0)])
	_pickups([["weapon", Vector3(0, 3.0, 3.9)], ["weapon", Vector3(-5.0, 3.0, 19.6)],
		["health", Vector3(-24.5, 6.8, 15.0)], ["health", Vector3(20.0, 0.0, 2.0)], ["weapon", Vector3(3.0, -DEPTH, -8.0)]])


# --------------------------------------------------------------------------
# Layout 1: EMBER PIT (small) - a foundry in a volcano
# --------------------------------------------------------------------------

func _layout_pit() -> void:
	# Round sandstone forge with ramps and a glowing iron chimney.
	_cyl(Vector3(0, 0, 0), 3.4, 2.0, "block_a", false)
	_cyl(Vector3(0, 1.7, 0), 3.46, 0.14, "accent_a", false, false)
	_wedge(Vector3(5.4, 0, 0), Vector3(5.6, 2, 3.5), PI, "deck")
	_cyl(Vector3(0, 2.0, 0), 0.9, 3.4, "block_b", false)
	_cyl(Vector3(0, 3.0, 0), 0.95, 0.16, "lava", false, false)
	_cyl(Vector3(0, 4.3, 0), 0.95, 0.16, "lava", false, false)
	_cyl(Vector3(0, 5.4, 0), 1.1, 0.3, "block_c", false, false)
	_glow(Vector3(0, 6.2, 0), theme.accent_a, 13.0, 2.6, false)

	# Two-storey smelter houses in two corners, with roof terraces.
	_building(Vector3(-13.0, 0, 7.3), 8.0, 8.6, 2, "house", {"roof": "block_c", "style": "workshop"})
	_box(Vector3(-8.2, 0.7, 4.2), Vector3(1.4, 1.4, 1.4), "crate", true, 0.3)

	# Stone arches over the north and south lanes.
	_box(Vector3(2.8, 1.8, 9.6), Vector3(1.0, 3.6, 1.0), "block_a")
	_box(Vector3(-2.8, 1.8, 9.6), Vector3(1.0, 3.6, 1.0), "block_a")
	_box(Vector3(0, 4.0, 9.6), Vector3(7.0, 0.8, 1.2), "block_a")
	_box(Vector3(0, 3.56, 9.6), Vector3(4.4, 0.1, 1.24), "accent_a", true, 0.0, false)

	# A crawl tunnel right under the forge, from wall to wall.
	_tunnel(0.0, -18.0, 18.0, false)

	# Iron plates, a column, crates, barrels.
	_box(Vector3(10, 1, 9.0), Vector3(4, 2, 0.6), "block_b")
	_box(Vector3(-6.5, 1, -6.0), Vector3(0.6, 2, 4), "block_b")
	_cyl(Vector3(9.6, 0, -4.4), 0.65, 3.4, "block_a")
	_box(Vector3(5.0, 0.6, -9.4), Vector3(4, 1.2, 0.6), "stripes")
	_box(Vector3(-3.6, 0.75, 11.0), Vector3(1.5, 1.5, 1.5), "crate", true, 0.3)
	_barrel(Vector3(17.2, 0, 11.6))
	_barrel(Vector3(17.6, 0, -4.0))
	_jump_pad(Vector3(0, 0, 6.2), 10.5)

	# Lava channels along the north and south walls.
	_lava(Vector3(0, 0, 14.2), Vector3(26.0, 0.1, 1.6))

	_spawns([Vector3(15, 0.1, 11.0), Vector3(0, 0.1, 12.2), Vector3(-16, 0.1, 12.0), Vector3(-12, 3.5, 7.0), Vector3(8, -DEPTH + 0.1, 0)])
	_pickups([["weapon", Vector3(2.2, 2.0, 2.2)], ["health", Vector3(-14.5, 6.8, 9.0)]])
	_pickups([["weapon", Vector3(0, -DEPTH, 0)]], false)


# --------------------------------------------------------------------------
# Layout 2: FROST LINE (large) - a polar research outpost
# --------------------------------------------------------------------------

func _layout_frost() -> void:
	# Central lab tower with long ramps, a second tier and a radio mast.
	_box(Vector3(0, 2, 0), Vector3(10, 4, 10), "block_a", false)
	_box(Vector3(0, 3.6, 0), Vector3(10.1, 0.14, 10.1), "accent_a", false, 0.0, false)
	_box(Vector3(0, 1.0, 0), Vector3(10.08, 0.5, 10.08), "crate", false, 0.0, false)
	_wedge(Vector3(10, 0, 0), Vector3(10, 4, 5), PI, "deck")
	_box(Vector3(0, 5, 0), Vector3(3.6, 2, 3.6), "block_c", false)
	_box(Vector3(0, 5.6, 0), Vector3(3.7, 0.12, 3.7), "accent_b", false, 0.0, false)
	_cyl(Vector3(0, 6, 0), 0.1, 5.5, "dark", false, false)
	_ball(Vector3(0, 11.6, 0), Vector3.ONE * 0.22, "beacon", false)
	_glow(Vector3(0, 7.5, 0), theme.accent_a, 18.0, 2.6, false)

	# Steel bridges to the north/south decks; each deck has a ramp at both ends.
	_box(Vector3(0, 3.8, 11), Vector3(4, 0.4, 12), "deck")
	_box(Vector3(2.05, 4.45, 11), Vector3(0.15, 0.9, 12), "rail")
	_box(Vector3(-2.05, 4.45, 11), Vector3(0.15, 0.9, 12), "rail")
	_box(Vector3(0, 3.8, 21), Vector3(20, 0.4, 8), "deck")
	for px in [-9.0, 9.0]:
		for pz in [18.0, 24.0]:
			_box(Vector3(px, 1.8, pz), Vector3(0.9, 3.6, 0.9), "block_c")
			_box(Vector3(px, 1.8, pz), Vector3(0.96, 0.12, 0.96), "accent_a", true, 0.0, false)
	_wedge(Vector3(15, 0, 21), Vector3(10, 4, 4), PI, "deck")
	_wedge(Vector3(-15, 0, 21), Vector3(10, 4, 4), 0.0, "deck")
	_box(Vector3(-6.2, 4.45, 17.1), Vector3(8, 0.9, 0.2), "rail")
	_box(Vector3(6.2, 4.45, 17.1), Vector3(8, 0.9, 0.2), "rail")
	_box(Vector3(-5, 4.6, 23.5), Vector3(3, 1.2, 0.5), "stripes")
	_glow(Vector3(0, 2.0, 21), theme.accent_b, 12.0, 1.6)

	# East/west lab modules: white panels with an orange band, walkable roof.
	_box(Vector3(28.2, 1.6, -6.25), Vector3(0.4, 3.2, 3.5), "block_a")
	_box(Vector3(28.2, 1.6, 0), Vector3(0.4, 3.2, 4), "block_a")
	_box(Vector3(28.2, 1.6, 6.25), Vector3(0.4, 3.2, 3.5), "block_a")
	_box(Vector3(28.2, 2.85, -3.25), Vector3(0.4, 0.7, 2.5), "block_a")
	_box(Vector3(28.2, 2.85, 3.25), Vector3(0.4, 0.7, 2.5), "block_a")
	_box(Vector3(32, 1.6, 7.8), Vector3(8, 3.2, 0.4), "block_a")
	_box(Vector3(32, 1.6, -7.8), Vector3(8, 3.2, 0.4), "block_a")
	_box(Vector3(32, 1.0, 7.8), Vector3(8.04, 0.5, 0.46), "crate", true, 0.0, false)
	_box(Vector3(32, 1.0, -7.8), Vector3(8.04, 0.5, 0.46), "crate", true, 0.0, false)
	_box(Vector3(35, 3.4, 0), Vector3(14, 0.4, 16), "block_c")
	_box(Vector3(35, 3.4, 0), Vector3(14.1, 0.12, 16.1), "accent_b", true, 0.0, false)
	_wedge(Vector3(35, 0, 11.5), Vector3(7, 3.6, 5), PI / 2, "deck")
	_box(Vector3(30, 4.2, -5), Vector3(0.5, 1.2, 4), "stripes")
	_glow(Vector3(34, 2.6, 0), theme.accent_a, 11.0, 2.0)

	# Two-storey comms buildings with roof terraces, and bunker tunnels.
	_building(Vector3(22, 0, -24), 9.0, 9.0, 2, "block_a", {"roof": "block_c", "style": "lab"})
	_tunnel(-8.0, -18.0, 18.0)

	# Mid-field: walls of ice blocks, supply crates, barriers, pines.
	_box(Vector3(20, 2, -12), Vector3(1.4, 4, 10), "block_b")
	_box(Vector3(22, 1.5, 13), Vector3(6, 3, 1.4), "block_b")
	_box(Vector3(12, 1.25, -14), Vector3(2.5, 2.5, 2.5), "block_b", true, 0.15)
	_box(Vector3(14.7, 1.0, -13), Vector3(2, 2, 2), "crate", true, -0.3)
	_box(Vector3(-10, 1.0, -27), Vector3(2, 2, 2), "crate", true, 0.3)
	_box(Vector3(-11.6, 0.65, -25.2), Vector3(1.3, 1.3, 1.3), "crate", true, 0.6)
	_box(Vector3(8, 0.6, -11.5), Vector3(5, 1.2, 0.6), "stripes")
	_box(Vector3(-8, 0.6, -14), Vector3(0.6, 1.2, 5), "stripes")
	_box(Vector3(30, 0.6, 21), Vector3(0.6, 1.2, 6), "stripes")
	_barrel(Vector3(40.5, 0, 14))
	_barrel(Vector3(-22, 0, 30.2))
	_barrel(Vector3(6, 0, 29.5))
	for p in [Vector3(41.5, 0, -10), Vector3(-12, 0, 30), Vector3(15, 0, -30), Vector3(31, 0, 30), Vector3(-36, 0, 24.5), Vector3(30, 0, -17)]:
		_pine(p, _rng.randf_range(0.9, 1.3))
	_jump_pad(Vector3(7.2, 0, 7.2), 15.5)
	_jump_pad(Vector3(40, 0, -18), 16.0)
	_glow(Vector3(-30, 4.0, 22), theme.accent_a, 14.0, 1.6)

	_spawns([Vector3(41, 0.1, 27), Vector3(41, 0.1, -27), Vector3(24, 0.1, 29), Vector3(39, 0.1, 0),
		Vector3(30, 0.1, -14), Vector3(-24, 0.1, 29), Vector3(22, 3.5, -23)])
	_pickups([["weapon", Vector3(3.2, 4.0, 3.2)], ["weapon", Vector3(6.5, 4.0, 22.5)], ["weapon", Vector3(36, 3.6, -4)],
		["health", Vector3(38, 0.0, 0)], ["health", Vector3(0, -DEPTH, -8.0)], ["weapon", Vector3(20.0, 6.8, -25.5)]])


# --------------------------------------------------------------------------
# Scenery (no gameplay effect)
# --------------------------------------------------------------------------

func _build_scenery() -> void:
	var rich: bool = Settings.v("scenery") == 1
	if not indoor:
		# The land carries on to the horizon in the map's own ground colour.
		# A ring round the arena, not one sheet under it: under the arena it
		# would cut across every ramp, tunnel and basement below ground.
		var ground_col: Color = theme.mats.ground[0]
		var am := StandardMaterial3D.new()
		am.albedo_color = ground_col.darkened(0.18)
		am.roughness = 0.9
		var E := 1200.0
		var ix := half_x + 1.0
		var iz := half_z + 1.0
		for sgn in [1.0, -1.0]:
			var ns := PlaneMesh.new()
			ns.size = Vector2(E * 2.0, E - iz)
			_add(ns, am, Transform3D(Basis(), Vector3(0, -0.6, sgn * (iz + E) * 0.5)), false)
			var ew := PlaneMesh.new()
			ew.size = Vector2(E - ix, iz * 2.0)
			_add(ew, am, Transform3D(Basis(), Vector3(sgn * (ix + E) * 0.5, -0.6, 0)), false)
		_horizon()
	match theme.scenery:
		"city": _scenery_city(30 if rich else 14, 6.0)
		"rocks": _scenery_spires(46 if rich else 20, Color(0.2, 0.13, 0.11), theme.accent_a, false)
		"ice": _scenery_spires(54 if rich else 22, Color(0.25, 0.42, 0.52), theme.accent_a, true)
		"suburb": _scenery_suburb(rich)
		"front": Front.scenery(self, rich)
		"castle": _scenery_trees(46 if rich else 18, 5.0, 40.0)
		"stadium":
			_scenery_city(22 if rich else 10, 40.0)
			_scenery_trees(30 if rich else 12, 4.0, 30.0)
	if rich:
		_grass()
		if theme.scenery == "ice":
			_snow_drifts()
		_motes()


## The horizon: what stands between the scenery ring and the sky, so the
## arena sits in a landscape instead of a void. Chosen by the theme's
## scenery kind: a far skyline for the city maps, rolling hills with
## mountains behind for the countryside, snow peaks for the ice field, dark
## crags with a lava glow for the pit. All far enough away that the depth
## of field and the haze turn them into a soft backdrop.
func _horizon() -> void:
	var r0 := sqrt(half_x * half_x + half_z * half_z)
	var ground: Color = theme.mats.ground[0]
	match theme.scenery:
		"city", "stadium":
			_skyline(r0 + 150.0, 110.0, 90, 30.0, 150.0)
			_ridge(r0 + 420.0, 60.0, 40.0, 110.0, Color(0.2, 0.24, 0.36), Color(0.36, 0.42, 0.56), 0.0, 11)
		"suburb":
			_ridge(r0 + 130.0, 70.0, 10.0, 34.0, ground.darkened(0.1), ground.lightened(0.12), 0.0, 3)
			_skyline(r0 + 300.0, 90.0, 46, 30.0, 110.0)
			_ridge(r0 + 460.0, 80.0, 60.0, 140.0, Color(0.34, 0.42, 0.52), Color(0.6, 0.66, 0.74), 0.75, 12)
		"castle":
			_ridge(r0 + 120.0, 70.0, 12.0, 40.0, ground.darkened(0.15), ground.lightened(0.08), 0.0, 5)
			_ridge(r0 + 300.0, 90.0, 70.0, 170.0, Color(0.36, 0.4, 0.42), Color(0.62, 0.64, 0.66), 0.62, 14)
		"front":
			_ridge(r0 + 110.0, 80.0, 10.0, 36.0, ground.darkened(0.12), ground.lightened(0.1), 0.0, 7)
			_ridge(r0 + 330.0, 90.0, 60.0, 150.0, Color(0.32, 0.38, 0.44), Color(0.56, 0.6, 0.66), 0.7, 15)
		"ice":
			_ridge(r0 + 120.0, 70.0, 16.0, 50.0, Color(0.62, 0.72, 0.84), Color(0.9, 0.95, 1.0), 0.0, 8)
			_ridge(r0 + 300.0, 90.0, 80.0, 190.0, Color(0.42, 0.52, 0.68), Color(0.8, 0.88, 0.98), 0.4, 16)
		"rocks":
			_ridge(r0 + 110.0, 60.0, 24.0, 70.0, Color(0.16, 0.1, 0.09), Color(0.34, 0.2, 0.15), 0.0, 9, 2.2)
			_ridge(r0 + 280.0, 90.0, 80.0, 200.0, Color(0.12, 0.07, 0.07), Color(0.4, 0.18, 0.1), 0.0, 17, 2.4)
			_glow_band(r0 + 190.0, Color(1.0, 0.35, 0.08))


## A ring of hills or mountains `radius` away: a ridge line from layered
## noise between h_min and h_max, a shoulder half-way up for shading, base
## colour fading to `top` (and to snow above `snow` of the height, 0 = no
## snow). `jag` > 1 sharpens the peaks.
func _ridge(radius: float, depth: float, h_min: float, h_max: float, base: Color, top: Color, snow: float, seed_i: int, jag := 1.0) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 1000 + map_index * 37 + seed_i
	noise.frequency = 1.0
	var seg := 160
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows: Array = []
	for i in seg + 1:
		var a := TAU * (i % seg) / seg
		var n := 0.5 + 0.5 * noise.get_noise_2d(cos(a) * 2.2, sin(a) * 2.2)
		n = n * 0.65 + 0.35 * (0.5 + 0.5 * noise.get_noise_2d(cos(a) * 9.0 + 40.0, sin(a) * 9.0))
		n = pow(clampf(n, 0.0, 1.0), jag)
		var h := lerpf(h_min, h_max, n)
		var dir := Vector3(cos(a), 0, sin(a))
		rows.append([dir * radius + Vector3(0, -4.0, 0), dir * (radius + depth * 0.45) + Vector3(0, h * 0.55, 0), dir * (radius + depth) + Vector3(0, h, 0), n])
	for i in seg:
		var p: Array = rows[i]
		var q: Array = rows[i + 1]
		for band in 2:
			var quad := [p[band], q[band], q[band + 1], p[band], q[band + 1], p[band + 1]]
			var levels := [band * 0.5, band * 0.5, band * 0.5 + 0.5, band * 0.5, band * 0.5 + 0.5, band * 0.5 + 0.5]
			var nrm: Vector3 = ((quad[1] as Vector3) - (quad[0] as Vector3)).cross((quad[2] as Vector3) - (quad[0] as Vector3)).normalized()
			if nrm.dot(-(quad[0] as Vector3)) < 0.0:
				nrm = -nrm
			for k in 6:
				var lvl: float = levels[k]
				var hn: float = (q[3] if k in [1, 2, 4] else p[3])
				var col := base.lerp(top, lvl)
				if snow > 0.0 and lvl * (0.45 + 0.55 * hn) > snow * 0.62:
					col = col.lerp(Color(0.95, 0.97, 1.0), 0.85)
				st.set_color(col)
				st.set_normal(nrm)
				st.add_vertex(quad[k])
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## A far skyline: a broad ring of towers of mixed heights, hazed towards the
## sky colour, with lit window bands at dusk and night.
func _skyline(radius: float, spread: float, count: int, h_min: float, h_max: float) -> void:
	var body := StandardMaterial3D.new()
	body.albedo_color = Color(0.07, 0.08, 0.14) if time == "night" else Color(0.42, 0.47, 0.56)
	body.roughness = 0.6
	var lit := StandardMaterial3D.new()
	lit.albedo_color = Color(0.1, 0.1, 0.12)
	lit.emission_enabled = true
	lit.emission = Color(1.0, 0.82, 0.5)
	lit.emission_energy_multiplier = 1.6 * night_amount
	var box := BoxMesh.new()
	for i in count:
		var a := TAU * i / float(count) + _rng.randf_range(-0.03, 0.03)
		var d := radius + _rng.randf() * spread
		var w := _rng.randf_range(14.0, 34.0)
		var h := lerpf(h_min, h_max, pow(_rng.randf(), 1.8))
		var p := Vector3(cos(a) * d, h * 0.5 - 2.0, sin(a) * d)
		var yaw := _rng.randf() * TAU
		_add(box, body, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(w, h, w * _rng.randf_range(0.7, 1.2))), p), false)
		if h > 70.0 and i % 2 == 0:
			# Aircraft warning light on the roof (blinks in _process).
			_add(_unit_sphere, _beacon_mat(), Transform3D(Basis.from_scale(Vector3.ONE * 1.1), Vector3(p.x, h - 1.0, p.z)), false)
		if night_amount > 0.0:
			for b in 3 + _rng.randi() % 5:
				var y := h * _rng.randf_range(0.15, 0.95) - 2.0
				_add(box, lit, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(w + 0.4, 1.6, w * 0.6)), Vector3(p.x, y, p.z)), false)


## A low band of glowing light between two ridges (lava fields far away).
func _glow_band(radius: float, col: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col * 1.6
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 2.0
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 3.0
	cyl.radial_segments = 64
	cyl.cap_top = false
	cyl.cap_bottom = false
	var mi := MeshInstance3D.new()
	mi.mesh = cyl
	mi.material_override = mat
	mi.position.y = 1.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _ring_spot(i: int, n: int, near: float, far: float) -> Vector3:
	var a := TAU * i / float(n) + _rng.randf_range(-0.08, 0.08)
	var dir := Vector2(cos(a), sin(a))
	var edge := minf((half_x + 6.0) / maxf(absf(dir.x), 0.001), (half_z + 6.0) / maxf(absf(dir.y), 0.001))
	var d := edge + _rng.randf_range(near, far)
	return Vector3(dir.x * d, 0, dir.y * d)


## Skyline: towers with glowing window bands at night, glazed by day.
func _scenery_city(count: int, near: float) -> void:
	var body := StandardMaterial3D.new()
	body.albedo_color = Color(0.04, 0.045, 0.085) if time == "night" else Color(0.32, 0.36, 0.44)
	body.roughness = 0.5
	var box := BoxMesh.new()
	for i in count:
		var p := _ring_spot(i, count, near, near + 50.0)
		var w := _rng.randf_range(7.0, 16.0)
		var h := _rng.randf_range(10.0, 44.0)
		var yaw := _rng.randf() * 0.6
		_add(box, body, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(w, h, w)), p + Vector3(0, h * 0.5, 0)), false)
		var neon: Material = _mats["accent_a" if i % 2 == 0 else "accent_b"] if night_amount > 0.9 else _mats["window"]
		var bands := 2 + _rng.randi() % 4
		for b in bands:
			var y := h * (0.25 + 0.7 * b / float(bands))
			_add(box, neon, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(w + 0.15, 0.22 if night_amount > 0.9 else 1.2, w + 0.15)), p + Vector3(0, y, 0)), false)


## Jagged spires: rock for the pit, glowing crystals for the ice field.
func _scenery_spires(count: int, col: Color, glow: Color, crystal: bool) -> void:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 1.0
	cone.height = 1.0
	cone.radial_segments = 6
	var rock := StandardMaterial3D.new()
	rock.albedo_color = col if time == "night" else col.lightened(0.35)
	rock.roughness = 0.3 if crystal else 0.8
	if crystal:
		rock.emission_enabled = true
		rock.emission = glow
		rock.emission_energy_multiplier = 0.2 * neon_scale
		rock.rim_enabled = true
	else:
		var t: Array = _tex("rock")
		rock.albedo_texture = t[0]
		rock.normal_enabled = true
		rock.normal_texture = t[1]
		rock.uv1_triplanar = true
		rock.uv1_scale = Vector3.ONE * 0.6
	for i in count:
		var p := _ring_spot(i, count, 2.0, 60.0)
		var h := _rng.randf_range(5.0, 30.0) * (1.5 if i % 7 == 0 else 1.0)
		var r := h * _rng.randf_range(0.14, 0.3)
		var basis := Basis.from_euler(Vector3(_rng.randf_range(-0.12, 0.12), _rng.randf() * TAU, _rng.randf_range(-0.12, 0.12)))
		_add(cone, rock, Transform3D(basis.scaled(Vector3(r, h, r)), p + Vector3(0, h * 0.5 - 0.6, 0)), false)
		if i % 3 == 0 and not crystal:
			_add(_unit_cyl, _mats["lava"], Transform3D(Basis.from_scale(Vector3(r * 1.8, 0.1, r * 1.8)), p + Vector3(0, -0.5, 0)), false)


func _scenery_trees(count: int, near: float, far: float) -> void:
	# Out-of-bounds trees use the light toon models (a tenth of the triangles).
	for i in count:
		var p := _ring_spot(i, count, near, far)
		_model("toon/Plant/Tree_%d" % (1 + _rng.randi() % 4), p, _rng.randf() * TAU, _rng.randf_range(1.3, 2.0), false, "none")


## Rows of houses and trees beyond the fences.
func _scenery_suburb(rich: bool) -> void:
	var walls := ["siding0", "siding1", "siding2", "siding3"]
	var n := 24 if rich else 12
	var box := BoxMesh.new()
	var prism := PrismMesh.new()
	for i in n:
		var p := _ring_spot(i, n, 8.0, 22.0)
		var w := _rng.randf_range(8.0, 11.0)
		var d := _rng.randf_range(7.0, 9.0)
		# Modelled houses (Kenney suburban kit) beyond the fences.
		_model("houses/House_Type_%02d" % (1 + _rng.randi() % 21), p, atan2(p.x, p.z) + PI * 0.5 * (_rng.randi() % 4), 8.5, false, "none")
	_scenery_trees(40 if rich else 16, 2.0, 30.0)


## Soft mounds of snow against the inside of the walls (visual only).
func _snow_drifts() -> void:
	for i in 22:
		var along := _rng.randf_range(-1.0, 1.0)
		var pos: Vector3
		match i % 4:
			0: pos = Vector3(along * (half_x - 3.0), 0, half_z - 0.4)
			1: pos = Vector3(along * (half_x - 3.0), 0, -half_z + 0.4)
			2: pos = Vector3(half_x - 0.4, 0, along * (half_z - 3.0))
			_: pos = Vector3(-half_x + 0.4, 0, along * (half_z - 3.0))
		var r := _rng.randf_range(1.2, 2.6)
		_add(_unit_sphere, _mats["ground"], Transform3D(Basis.from_scale(Vector3(r, r * 0.3, r)), pos), false)


## Glowing specks in the air: fireflies, embers or dust motes.
func _motes() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 32
	tex.height = 32
	mat.albedo_texture = tex
	var ramp := Gradient.new()
	var bright := 1.8 if time == "night" else 0.8
	ramp.set_color(0, theme.motes[0] * bright)
	ramp.set_color(1, theme.motes[1] * bright)
	var rise: float = theme.mote_rise
	var p := CPUParticles3D.new()
	p.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	p.mesh = QuadMesh.new()
	p.material_override = mat
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.amount = int(half_x * half_z * 0.2)
	p.lifetime = 10.0
	p.preprocess = 10.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(half_x, 4.0, half_z)
	p.direction = Vector3(0.6, signf(rise), 0.3)
	p.spread = 40.0
	p.initial_velocity_min = 0.15
	p.initial_velocity_max = 0.5 + absf(rise)
	p.gravity = Vector3(0, rise * 0.4, 0)
	p.scale_amount_min = 0.05
	p.scale_amount_max = 0.12
	p.color_initial_ramp = ramp
	p.position = Vector3(0, 4.5, 0)
	add_child(p)


# --------------------------------------------------------------------------
# Bot navigation
# --------------------------------------------------------------------------

func _ray(from: Vector3, to: Vector3, from_inside := false) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	q.hit_from_inside = from_inside
	return get_world_3d().direct_space_state.intersect_ray(q)


## Must run after the static body has been in the tree for a physics frame.
## Samples a 2 m grid with downward rays (several surfaces per column, so decks,
## upper floors and underground rooms all count), links walkable neighbours and
## keeps the largest connected component.
func build_nav() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var points: Array = []
	var cells := {}
	var x := -half_x + 1.0
	while x < half_x:
		var z := -half_z + 1.0
		while z < half_z:
			var top := nav_top
			for layer in 12:
				var hit := _ray(Vector3(x, top, z), Vector3(x, -DEPTH - 1.5, z))
				if hit.is_empty():
					break
				var p: Vector3 = hit.position
				top = p.y - 0.5
				if hit.normal.y > 0.7 and p.y < nav_top - 4.0:
					if _ray(p + Vector3(0, 0.15, 0), p + Vector3(0, 1.9, 0), true).is_empty():
						var key := Vector2i(roundi(x), roundi(z))
						if not cells.has(key):
							cells[key] = []
						cells[key].append(points.size())
						points.append(p)
				if top < -DEPTH - 1.0:
					break
			z += nav_step
		x += nav_step

	var links: Array = []
	var adj := {}
	var step := int(nav_step)
	for key in cells:
		for off in [Vector2i(step, 0), Vector2i(0, step), Vector2i(step, step), Vector2i(step, -step)]:
			var other: Vector2i = key + off
			if not cells.has(other):
				continue
			for i in cells[key]:
				for j in cells[other]:
					if _walkable(points[i], points[j]):
						links.append(Vector2i(i, j))
						if not adj.has(i): adj[i] = []
						if not adj.has(j): adj[j] = []
						adj[i].append(j)
						adj[j].append(i)

	# Stair flights the grid cannot link (too steep per grid step): a chain of
	# points up the flight, joined to the grid at both ends.
	for pair in nav_links:
		var a: Vector3 = pair[0]
		var b: Vector3 = pair[1]
		var n := maxi(2, int(ceil(a.distance_to(b) / 1.2)))
		var prev := -1
		for i in n + 1:
			var p := a.lerp(b, float(i) / n)
			var idx := points.size()
			points.append(p)
			if prev >= 0:
				_nav_link(links, adj, prev, idx)
			prev = idx
			if i == 0 or i == n:
				var k0 := Vector2i(roundi(p.x), roundi(p.z))
				for dx in range(-4, 5):
					for dz in range(-4, 5):
						var kk := k0 + Vector2i(dx, dz)
						if not cells.has(kk):
							continue
						for j in cells[kk]:
							var q: Vector3 = points[j]
							if absf(q.y - p.y) < 0.8 and Vector2(q.x - p.x, q.z - p.z).length() < 3.4 and _walkable(p, q):
								_nav_link(links, adj, idx, j)

	var seen := {}
	var best: Array = []
	for start in adj:
		if seen.has(start):
			continue
		var comp: Array = []
		var stack: Array = [start]
		seen[start] = true
		while not stack.is_empty():
			var cur = stack.pop_back()
			comp.append(cur)
			for nb in adj[cur]:
				if not seen.has(nb):
					seen[nb] = true
					stack.append(nb)
		if comp.size() > best.size():
			best = comp
	var keep := {}
	for i in best:
		keep[i] = true
		nav.add_point(i, points[i])
		_nav_ids.append(i)
	for l in links:
		if keep.has(l.x) and keep.has(l.y):
			nav.connect_points(l.x, l.y)
	nav_ready = true
	# (Loose street clutter is gone: it got under everyone's feet.)
	nav_built.emit()
	print("[map] %s nav graph: %d nodes, %d links" % [MAPS[map_index].name, best.size(), links.size()])


func _nav_link(links: Array, adj: Dictionary, i: int, j: int) -> void:
	links.append(Vector2i(i, j))
	if not adj.has(i): adj[i] = []
	if not adj.has(j): adj[j] = []
	adj[i].append(j)
	adj[j].append(i)


func _walkable(a: Vector3, b: Vector3) -> bool:
	if absf(a.y - b.y) > 1.25:
		return false
	for t in [0.25, 0.5, 0.75]:
		var m := a.lerp(b, t)
		var hit := _ray(m + Vector3(0, 1.0, 0), m + Vector3(0, -0.6, 0))
		if hit.is_empty() or absf(hit.position.y - m.y) > 0.45:
			return false
	var dir := (b - a)
	dir.y = 0.0
	var side := dir.normalized().cross(Vector3.UP) * 0.38
	for off in [Vector3.ZERO, side, -side]:
		for hgt in [0.35, 0.7, 1.5]:
			var up := Vector3(0, hgt, 0)
			if not _ray(a + up + off, b + up + off, true).is_empty():
				return false
	return true


func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	if not nav_ready or _nav_ids.is_empty():
		return PackedVector3Array()
	return nav.get_point_path(_closest_node(from), _closest_node(to))


func _closest_node(pos: Vector3) -> int:
	var near: Array = []
	for id in _nav_ids:
		var d := nav.get_point_position(id).distance_squared_to(pos)
		if d < 12.0 * (nav_step / NAV_STEP) * (nav_step / NAV_STEP):
			near.append([d, id])
	near.sort_custom(func(a, b): return a[0] < b[0])
	var up := Vector3(0, 0.8, 0)
	for n in near:
		if _ray(pos + up, nav.get_point_position(n[1]) + up, true).is_empty():
			return n[1]
	return nav.get_closest_point(pos)


func random_nav_point() -> Vector3:
	if not nav_ready or _nav_ids.is_empty():
		return Vector3.ZERO
	return nav.get_point_position(_nav_ids[randi() % _nav_ids.size()])
