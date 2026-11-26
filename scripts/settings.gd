extends Node
## Autoload "Settings". Every user option lives in ITEMS; each one is stored
## as an index into its list of choices (`idx[key]`). Read a value anywhere
## with Settings.v("key"). settings_menu.gd draws and edits this list, so
## adding an option is: add an entry here, then read it where it matters.
##
## Things this node applies itself: window mode, v-sync, frame cap, master
## volume, shadow atlas size, and anti-aliasing / render scale of any viewport
## passed to apply_viewport(). Everything else reacts to the `changed` signal
## (map.gd, stage.gd, game.gd, sfx.gd) or simply reads v() when needed.
##
## Saved to "slop_party_settings.cfg" next to the executable, so the game folder
## stays portable and nothing is written to the user profile. (On a Mac the
## .app bundle is read-only, so there it goes to Godot's user data folder:
## ~/Library/Application Support/Godot/app_userdata/Slop Party.)
##
## Dev flags (after "--"): --uncapped leaves v-sync / frame cap alone so
## benchmarks work; running with -w / --windowed keeps the window windowed;
## --set-<key>=<index> overrides one setting for that run (not saved).

signal changed

const ON_OFF := ["Off", "On"]
const RES_NAMES := ["Native", "1280 x 720", "1600 x 900", "1920 x 1080", "2560 x 1440", "3840 x 2160 (4K)",
	"2560 x 1080 (21:9)", "3440 x 1440 (21:9)", "3840 x 1600 (21:9)", "5120 x 2160 (21:9)", "3840 x 1080 (32:9)", "5120 x 1440 (32:9)"]
const RES_SIZES := [Vector2i.ZERO, Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160),
	Vector2i(2560, 1080), Vector2i(3440, 1440), Vector2i(3840, 1600), Vector2i(5120, 2160), Vector2i(3840, 1080), Vector2i(5120, 1440)]
const ITEMS := [
	{"section": "DISPLAY"},
	# "Fullscreen" is a borderless window the size of the screen (quick to
	# alt-tab); "Exclusive" hands the screen to the game (can cut latency).
	{"key": "fullscreen", "label": "Window mode", "opts": ["Windowed", "Fullscreen", "Exclusive fullscreen"], "vals": [0, 1, 2], "def": 1},
	# The whole game (3D and menus) is drawn at this size and scaled to the
	# window; "Native" = the window's own size. A size whose shape differs from
	# the screen gets black bars. Ultrawide 21:9 and super-ultrawide 32:9
	# sizes are included; on an ultrawide screen "Native" already fills it.
	{"key": "resolution", "label": "Resolution", "opts": RES_NAMES, "vals": RES_SIZES, "def": 0},
	# Ultrawide: keep the HUD in a 16:9 area in the middle of the screen so
	# health and ammo are not out in your peripheral vision.
	{"key": "hud_width", "label": "HUD width (ultrawide)", "opts": ["Full screen", "16:9 centred"], "vals": [0, 1], "def": 0},
	{"key": "vsync", "label": "V-Sync", "opts": ON_OFF, "vals": [false, true], "def": 1},
	# "Display" = let V-Sync pace the frames at the screen's own refresh rate
	# (or cap at that rate with V-Sync off). A fixed cap that does not divide
	# the refresh rate (60 on a 144 Hz screen) judders, so it is not the default.
	{"key": "fps_limit", "label": "Frame rate limit", "opts": ["Display", "30", "60", "120", "144", "240", "Unlimited"], "vals": [-1, 30, 60, 120, 144, 240, 0], "def": 0},
	{"section": "GRAPHICS"},
	{"key": "preset", "label": "Quality preset", "opts": ["Custom", "Low", "Medium", "High", "Ultra"], "vals": [0, 1, 2, 3, 4], "def": 3},
	# Textures on floors and walls seen at a low angle stay sharp further
	# out (otherwise they blur a few metres ahead).
	{"key": "aniso", "label": "Texture filtering", "opts": ["2x", "4x", "8x", "16x"], "vals": [1, 2, 3, 4], "def": 3},
	{"key": "aa", "label": "Anti-aliasing", "opts": ["Off", "FXAA", "MSAA 2x", "MSAA 4x", "MSAA 8x"], "vals": [0, 1, 2, 3, 4], "def": 2},
	{"key": "motion_blur", "label": "Motion blur", "range": [0, 10], "def": 0},
	# 3D resolution as a share of the screen's. Above 100 % is supersampling:
	# drawn bigger, then shrunk down: the smoothest, sharpest image, at a
	# big GPU cost (150 % = 2.25x the pixels).
	{"key": "scale", "label": "Render scale", "opts": ["50%", "67%", "75%", "85%", "100%", "125%", "150%", "200%"], "vals": [0.5, 0.67, 0.75, 0.85, 1.0, 1.25, 1.5, 2.0], "def": 4},
	# How the 3D image is brought up to the screen (apply_viewport):
	# Bilinear = plain, soft; FSR 1 = sharpened (crisp edges below 100 %);
	# FSR 2 = temporal: blends several frames, so it also smooths the
	# flicker and jaggies MSAA cannot reach (texture detail, outlines, thin
	# shapes, shiny highlights). FSR 2 replaces the anti-aliasing setting and
	# works at 100 % as a high-quality anti-aliasing on its own.
	{"key": "upscaler", "label": "Upscaling", "opts": ["Bilinear", "FSR 1 (sharp)", "FSR 2 (smoothest)"], "vals": [0, 1, 2], "def": 1},
	{"key": "sharpen", "label": "Sharpening (FSR)", "opts": ["Off", "Low", "Medium", "High"], "vals": [2.0, 1.0, 0.5, 0.15], "def": 2},
	{"key": "shadows", "label": "Shadows", "opts": ["Off", "Low", "High"], "vals": [0, 1, 2], "def": 2},
	{"key": "ssao", "label": "Ambient occlusion", "opts": ON_OFF, "vals": [false, true], "def": 1},
	# Light bouncing off surfaces (screen-space indirect light, SSIL). Tested
	# SDFGI too: it cost over 10 ms a frame and stalled for seconds, so no.
	# Grooves with real depth on bricks, tiles, planks, stone... (surface.gd).
	# Speed blur on dashes and slides, zoom blur from nearby blasts, colour
	# fringing when badly hurt (screen_fx.gd).
	{"key": "screenfx", "label": "Screen effects", "opts": ON_OFF, "vals": [false, true], "def": 1},
	{"key": "parallax", "label": "Surface depth", "opts": ON_OFF, "vals": [false, true], "def": 1},
	{"key": "gi", "label": "Bounce light", "opts": ON_OFF, "vals": [false, true], "def": 1},
	# Light shafts through the haze (volumetric fog), one or two views only.
	{"key": "volfog", "label": "Light shafts in the air", "opts": ON_OFF, "vals": [false, true], "def": 0},
	# Screen-space reflections on wet ground (Cyberpunk, Synthwave).
	{"key": "ssr", "label": "Reflections on wet ground", "opts": ON_OFF, "vals": [false, true], "def": 1},
	{"key": "decals", "label": "Bullet holes and scorch marks", "opts": ON_OFF, "vals": [false, true], "def": 1},
	{"key": "glow", "label": "Bloom", "opts": ON_OFF, "vals": [false, true], "def": 1},
	# The look of the level (voxel.gd): built from small cubes, or smooth.
	# Takes effect from the next match.
	{"key": "voxel", "label": "World style", "opts": ["Voxel", "Smooth"], "vals": [true, false], "def": 0},
	# Voxel style: ray-marched depth (voxels really step in and out as you
	# move). Off by default: the illusion shifts with the view, so thin
	# parts seemed to shake, floors seemed to sink under walls and doors,
	# and it faded out a few metres ahead. The baked voxel shading is
	# stable at every distance.
	{"key": "voxel_relief", "label": "Voxel parallax depth (may shimmer)", "opts": ON_OFF, "vals": [false, true], "def": 0},
	{"key": "scenery", "label": "Scenery detail", "opts": ["Low", "High"], "vals": [0, 1], "def": 1},
	# Lowers the 3D resolution on the fly whenever a frame would take too long
	# (game.gd::_auto_resolution), so busy six-player moments stay at 60.
	# The value is the lowest share of the chosen render scale it may drop to.
	{"key": "auto_res", "label": "Auto resolution (hold 60 FPS)", "opts": ["Off", "On", "On, never below 75%"], "vals": [1.0, 0.5, 0.75], "def": 1},
	{"key": "dof", "label": "Soft focus in the distance", "opts": ON_OFF, "vals": [false, true], "def": 1},
	{"key": "rays", "label": "Sun rays", "opts": ON_OFF, "vals": [false, true], "def": 1},
	{"section": "AUDIO"},
	{"key": "master", "label": "Master volume", "range": [0, 10], "def": 8},
	{"key": "music", "label": "Music volume", "range": [0, 10], "def": 6},
	{"key": "sfx", "label": "Effects volume", "range": [0, 10], "def": 8},
	{"section": "CONTROLS"},
	{"key": "stick", "label": "Gamepad look speed", "range": [1, 10], "def": 5},
	{"key": "deadzone", "label": "Stick dead zone", "opts": ["Small", "Normal", "Large"], "vals": [0.08, 0.14, 0.24], "def": 1},
	{"key": "mouse", "label": "Mouse look speed", "range": [1, 10], "def": 4},
	# Each player's own look speed on top of the gamepad / mouse speed above
	# (P1 = the first player to join in the lobby, and so on).
	{"key": "look_p1", "label": "Player 1 look speed", "range": [1, 10], "def": 5},
	{"key": "look_p2", "label": "Player 2 look speed", "range": [1, 10], "def": 5},
	{"key": "look_p3", "label": "Player 3 look speed", "range": [1, 10], "def": 5},
	{"key": "look_p4", "label": "Player 4 look speed", "range": [1, 10], "def": 5},
	{"key": "look_p5", "label": "Player 5 look speed", "range": [1, 10], "def": 5},
	{"key": "look_p6", "label": "Player 6 look speed", "range": [1, 10], "def": 5},
	{"key": "aim_assist", "label": "Gamepad aim assist", "opts": ON_OFF, "vals": [false, true], "def": 1},
	{"key": "rumble", "label": "Controller rumble", "opts": ON_OFF, "vals": [false, true], "def": 1},
	{"section": "GAMEPLAY"},
	# Horizontal field of view in degrees, as on a 16:9 screen (ultrawide
	# screens see more to the sides). Was Narrow 86 / Normal 100 / Wide 112
	# under the key "fov"; the new key starts everyone at 100.
	{"key": "fov_h", "label": "Field of view", "range": [60, 130], "step": 5, "suffix": "°", "def": 100},
	{"key": "shake", "label": "Screen shake", "opts": ["Off", "Low", "Full"], "vals": [0.0, 0.5, 1.0], "def": 2},
	{"key": "bob", "label": "View bob and sway", "opts": ["Off", "Low", "Full"], "vals": [0.0, 0.5, 1.0], "def": 2},
	{"key": "numbers", "label": "Damage numbers", "opts": ON_OFF, "vals": [false, true], "def": 1},
	{"key": "bots", "label": "Bot difficulty", "opts": ["Easy", "Normal", "Hard"], "vals": [0, 1, 2], "def": 1},
]

## preset index -> {key: choice index}
const PRESETS := {
	1: {"aa": 0, "scale": 2, "shadows": 0, "ssao": 0, "glow": 0, "scenery": 0, "dof": 0, "gi": 0, "volfog": 0, "decals": 0, "parallax": 0, "ssr": 0},
	2: {"aa": 1, "scale": 4, "shadows": 1, "ssao": 0, "glow": 1, "scenery": 1, "dof": 0, "gi": 0, "volfog": 0, "decals": 1},
	3: {"aa": 2, "scale": 4, "shadows": 2, "ssao": 1, "glow": 1, "scenery": 1, "dof": 1, "gi": 1, "volfog": 0, "decals": 1},
	4: {"aa": 3, "scale": 4, "shadows": 2, "ssao": 1, "glow": 1, "scenery": 1, "dof": 1, "gi": 1, "volfog": 1, "decals": 1},
}

## Steam Deck first-start defaults (choice indices): the Medium preset,
## minus the screen-space extras that cost most on its APU. The screen is
## only 1280 x 800, so the 3D stays at 100 % and FSR 1 sharpens it.
const DECK := {"preset": 2, "aa": 1, "scale": 4, "shadows": 1, "ssao": 0, "glow": 1, "scenery": 1, "dof": 0,
	"gi": 0, "volfog": 0, "decals": 1, "parallax": 0, "ssr": 0, "rays": 0, "upscaler": 1, "auto_res": 1}

var idx := {}
var res_factor := 1.0      # auto resolution: extra 3D scale factor set by game.gd (0.5-1)
var view_count := 1        # splitscreen views in play (game.gd); heavy effects need few views
var lobby := {}            # free-form values the lobby remembers (loadouts, map, bots)
var _items := {}           # key -> item dictionary (with opts/vals filled in)
var rows: Array = []       # ITEMS with ranges expanded; what the menu shows
var _path := ""
var _saved_idx := {}       # --set-<key> overrides: the real value, which is what gets saved
var _uncapped := false
var _keep_window := false
var _win_res := Vector2i(-1, -1)   # the resolution the window was last sized for


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Round, smooth depth-of-field blur (the "soft focus" option).
	RenderingServer.camera_attributes_set_dof_blur_bokeh_shape(RenderingServer.DOF_BOKEH_CIRCLE)
	RenderingServer.camera_attributes_set_dof_blur_quality(RenderingServer.DOF_BLUR_QUALITY_MEDIUM, false)
	# Deliver mouse motion as it arrives instead of once per frame.
	Input.use_accumulated_input = false
	_uncapped = "--uncapped" in OS.get_cmdline_user_args()
	for a in OS.get_cmdline_args():
		if a == "-w" or a == "--windowed":
			_keep_window = true
	for raw in ITEMS:
		var item: Dictionary = raw.duplicate()
		if item.has("range"):
			var opts: Array = []
			var vals: Array = []
			var stp: int = item.get("step", 1)
			for n in range(item.range[0], item.range[1] + 1, stp):
				opts.append(str(n) + item.get("suffix", ""))
				vals.append(n)
			item["opts"] = opts
			item["vals"] = vals
			item["def"] = (item.def - item.range[0]) / stp
			item["slider"] = true
		rows.append(item)
		if item.has("key"):
			_items[item.key] = item
			idx[item.key] = item.def
	var dir := OS.get_executable_path().get_base_dir()
	# On a Mac the executable lives inside the signed, read-only .app bundle,
	# so settings go to the user data folder instead. Same for any folder we
	# can't write to (Linux: an AppImage / Flatpak mount, a read-only
	# install, a game folder owned by another user).
	if OS.get_name() == "macOS" or not _writable(dir):
		dir = OS.get_user_data_dir()
	_path = dir.path_join("slop_party_settings.cfg")
	# Settings from before the rename (Fragdeck / Slop Game) carry over.
	if not FileAccess.file_exists(_path) and FileAccess.file_exists(dir.path_join("fragdeck_settings.cfg")):
		DirAccess.copy_absolute(dir.path_join("fragdeck_settings.cfg"), _path)
	# First start on a Steam Deck: begin from settings its APU holds at
	# 60 FPS. Only when there is no settings file yet, so a player's own
	# choices always win.
	if not FileAccess.file_exists(_path) and is_steam_deck():
		for k in DECK:
			idx[k] = DECK[k]
	_load()
	# Dev: --set-<key>=<choice index> overrides a setting for this run only.
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--set-") and "=" in a:
			var kv := a.substr(6).split("=")
			if _items.has(kv[0]):
				_saved_idx[kv[0]] = idx[kv[0]]
				idx[kv[0]] = clampi(int(kv[1]), 0, _items[kv[0]].opts.size() - 1)
	apply()


func v(key: String):
	return _items[key].vals[idx[key]]


func label(key: String) -> String:
	return _items[key].opts[idx[key]]


## Move a setting one step. Two-way toggles and choice lists wrap; sliders clamp.
func step(key: String, dir: int) -> void:
	var item: Dictionary = _items[key]
	var n: int = item.opts.size()
	if item.has("slider"):
		idx[key] = clampi(idx[key] + dir, 0, n - 1)
	else:
		idx[key] = posmod(idx[key] + dir, n)
	if key == "preset":
		if PRESETS.has(idx[key]):
			for k in PRESETS[idx[key]]:
				idx[k] = PRESETS[idx[key]][k]
	elif PRESETS[1].has(key):
		idx["preset"] = 0
	apply()
	save()


## F11: windowed <-> fullscreen (keeps "exclusive" if that was chosen).
func toggle_fullscreen() -> void:
	idx["fullscreen"] = 1 if idx["fullscreen"] == 0 else 0
	apply()
	save()


func reset() -> void:
	for key in _items:
		idx[key] = _items[key].def
	apply()
	save()


func apply() -> void:
	var win := get_window()
	var res: Vector2i = v("resolution")
	if not _keep_window:
		var want: Window.Mode = [Window.MODE_WINDOWED, Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN][v("fullscreen")]
		if win.mode != want:
			win.mode = want
			_win_res = Vector2i(-1, -1)
		# Windowed with a chosen size: size the window to it (shrunk to fit
		# the screen if it is bigger, keeping its shape) and centre it.
		if want == Window.MODE_WINDOWED and res != Vector2i.ZERO and res != _win_res:
			var area := DisplayServer.screen_get_usable_rect(win.current_screen)
			var k := minf(1.0, minf(area.size.x * 0.96 / res.x, area.size.y * 0.92 / res.y))
			win.size = Vector2i(Vector2(res) * k)
			win.position = area.position + (area.size - win.size) / 2
		_win_res = res if want == Window.MODE_WINDOWED else Vector2i(-1, -1)
	# A chosen resolution: draw everything at that size and scale it to the
	# window, with black bars where the shapes differ.
	if res == Vector2i.ZERO:
		win.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	else:
		win.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
		win.content_scale_size = res
	if _uncapped:
		# Benchmarks: no v-sync, no frame cap, so frame times show the real cost.
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if v("vsync") else DisplayServer.VSYNC_DISABLED)
		# A frame limiter fighting v-sync causes uneven frame pacing. With v-sync
		# on, only limit when the cap is clearly below the display's refresh
		# rate; otherwise let v-sync alone pace the frames.
		var cap: int = v("fps_limit")
		var refresh := DisplayServer.screen_get_refresh_rate()
		if cap < 0:
			cap = 0 if v("vsync") or refresh <= 0.0 else int(round(refresh))
		elif v("vsync") and cap > 0 and refresh > 0.0 and cap >= int(refresh) - 2:
			cap = 0
		Engine.max_fps = cap
	var master: int = v("master")
	AudioServer.set_bus_mute(0, master == 0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.001, master / 10.0)))
	RenderingServer.directional_shadow_atlas_set_size(4096 if v("shadows") == 2 else 2048, true)
	apply_viewport(get_viewport())
	changed.emit()


## Anti-aliasing and render scale for one viewport (root or a splitscreen cell).
func apply_viewport(vp: Viewport) -> void:
	# Smooth edges on every 2D shape (HUD, menus): the drawing helpers fill
	# polygons and circles without anti-aliasing of their own.
	vp.msaa_2d = Viewport.MSAA_4X
	vp.anisotropic_filtering_level = v("aniso")
	var aa: int = v("aa")
	var up: int = v("upscaler")
	var sc: float = clampf(v("scale") * res_factor, 0.25, 2.0)
	vp.scaling_3d_scale = sc
	vp.fsr_sharpness = v("sharpen")
	if up == 2 and sc <= 1.0:
		# FSR 2 does its own temporal anti-aliasing; MSAA / FXAA on top only
		# cost time (and FXAA would blur its result).
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
		vp.msaa_3d = Viewport.MSAA_DISABLED
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		vp.use_taa = false
		return
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X][aa]
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa == 1 else Viewport.SCREEN_SPACE_AA_DISABLED
	# Supersampling (above 100 %) only works with the plain filter; FSR 2
	# above 100 % falls back to that plus TAA, which keeps its smoothness.
	vp.use_taa = up == 2
	if sc > 1.0:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	elif up >= 1 and sc < 0.99:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
	else:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR


## Shared by map.gd and stage.gd.
func apply_environment(env: Environment, sun: DirectionalLight3D) -> void:
	env.ssao_enabled = v("ssao")
	# Deep, soft contact shadows in corners, under props and between parts,
	# and (light_affect) a little of it even in direct sunlight: depth on
	# simple shapes.
	env.ssao_radius = 1.8
	env.ssao_intensity = 2.2
	env.ssao_power = 1.6
	env.ssao_detail = 0.7
	env.ssao_horizon = 0.06
	env.ssao_light_affect = 0.3
	env.ssao_ao_channel_affect = 0.5
	env.glow_enabled = v("glow")
	# Bounce light: colour picked up from nearby lit surfaces.
	env.ssil_enabled = v("gi")
	env.ssil_radius = 4.0
	env.ssil_intensity = 0.9
	env.ssil_sharpness = 0.98
	env.ssr_enabled = v("ssr") and env.get_meta("ssr", false)
	if env.ssr_enabled:
		env.ssr_max_steps = 48 if view_count <= 2 else 24
		env.ssr_fade_in = 0.15
		env.ssr_fade_out = 2.0
		env.ssr_depth_tolerance = 0.3
	env.volumetric_fog_enabled = v("volfog") and view_count <= 2 and env.get_meta("volfog_density", 0.0) > 0.0
	if env.volumetric_fog_enabled:
		env.volumetric_fog_density = env.get_meta("volfog_density", 0.01)
		env.volumetric_fog_albedo = env.get_meta("volfog_albedo", Color(0.8, 0.8, 0.85))
		env.volumetric_fog_anisotropy = 0.55
		env.volumetric_fog_length = 48.0
		env.volumetric_fog_detail_spread = 2.0
		env.volumetric_fog_ambient_inject = 0.25
		env.volumetric_fog_sky_affect = 0.0
	var sh: int = v("shadows")
	sun.shadow_enabled = sh > 0
	sun.shadow_blur = 2.6 if sh == 2 else 1.4
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if sh == 2 else DirectionalLight3D.SHADOW_ORTHOGONAL


func save() -> void:
	var cfg := ConfigFile.new()
	for key in idx:
		cfg.set_value("settings", key, _saved_idx.get(key, idx[key]))
	for key in lobby:
		cfg.set_value("lobby", key, lobby[key])
	cfg.save(_path)


## True on a Steam Deck (LCD "Jupiter" or OLED "Galileo"), in Game Mode
## or Desktop Mode.
static func is_steam_deck() -> bool:
	if OS.get_name() != "Linux":
		return false
	if OS.get_environment("SteamDeck") == "1":
		return true
	var f := FileAccess.open("/sys/devices/virtual/dmi/id/product_name", FileAccess.READ)
	if f == null:
		return false
	return f.get_as_text().strip_edges() in ["Jupiter", "Galileo"]


## Can we create files in this folder?
static func _writable(dir: String) -> bool:
	var probe := dir.path_join(".slop_party_write_test")
	var f := FileAccess.open(probe, FileAccess.WRITE)
	if f == null:
		return false
	f.close()
	DirAccess.remove_absolute(probe)
	return true


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_path) != OK:
		return
	if cfg.has_section("lobby"):
		for key in cfg.get_section_keys("lobby"):
			lobby[key] = cfg.get_value("lobby", key)
	for key in idx:
		var val = cfg.get_value("settings", key, idx[key])
		if val is int and val >= 0 and val < _items[key].opts.size():
			idx[key] = val
