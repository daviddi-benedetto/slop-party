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
## Saved to "fragdeck_settings.cfg" next to the executable, so the game folder
## stays portable and nothing is written to the user profile.
##
## Dev flags (after "--"): --uncapped leaves v-sync / frame cap alone so
## benchmarks work; running with -w / --windowed keeps the window windowed;
## --set-<key>=<index> overrides one setting for that run (not saved).

signal changed

const ON_OFF := ["Off", "On"]
const ITEMS := [
	{"section": "DISPLAY"},
	{"key": "fullscreen", "label": "Fullscreen", "opts": ON_OFF, "vals": [false, true], "def": 1},
	{"key": "vsync", "label": "V-Sync", "opts": ON_OFF, "vals": [false, true], "def": 1},
	# "Display" = let V-Sync pace the frames at the screen's own refresh rate
	# (or cap at that rate with V-Sync off). A fixed cap that does not divide
	# the refresh rate (60 on a 144 Hz screen) judders, so it is not the default.
	{"key": "fps_limit", "label": "Frame rate limit", "opts": ["Display", "30", "60", "120", "144", "240", "Unlimited"], "vals": [-1, 30, 60, 120, 144, 240, 0], "def": 0},
	{"section": "GRAPHICS"},
	{"key": "preset", "label": "Quality preset", "opts": ["Custom", "Low", "Medium", "High", "Ultra"], "vals": [0, 1, 2, 3, 4], "def": 3},
	{"key": "aa", "label": "Anti-aliasing", "opts": ["Off", "FXAA", "MSAA 2x", "MSAA 4x", "MSAA 8x"], "vals": [0, 1, 2, 3, 4], "def": 2},
	{"key": "motion_blur", "label": "Motion blur", "range": [0, 10], "def": 0},
	{"key": "scale", "label": "Render scale", "opts": ["50%", "67%", "75%", "85%", "100%"], "vals": [0.5, 0.67, 0.75, 0.85, 1.0], "def": 4},
	{"key": "shadows", "label": "Shadows", "opts": ["Off", "Low", "High"], "vals": [0, 1, 2], "def": 2},
	{"key": "ssao", "label": "Ambient occlusion", "opts": ON_OFF, "vals": [false, true], "def": 1},
	# Light bouncing off surfaces (screen-space indirect light, SSIL). Tested
	# SDFGI too: it cost over 10 ms a frame and stalled for seconds, so no.
	# Ink lines along silhouettes and creases (outline.gd): shapes stand
	# apart even with flat colours.
	{"key": "outlines", "label": "Outlines", "opts": ON_OFF, "vals": [false, true], "def": 1},
	{"key": "gi", "label": "Bounce light", "opts": ON_OFF, "vals": [false, true], "def": 1},
	# Light shafts through the haze (volumetric fog), one or two views only.
	{"key": "volfog", "label": "Light shafts in the air", "opts": ON_OFF, "vals": [false, true], "def": 0},
	{"key": "decals", "label": "Bullet holes and scorch marks", "opts": ON_OFF, "vals": [false, true], "def": 1},
	{"key": "glow", "label": "Bloom", "opts": ON_OFF, "vals": [false, true], "def": 1},
	{"key": "scenery", "label": "Scenery detail", "opts": ["Low", "High"], "vals": [0, 1], "def": 1},
	# Lowers the 3D resolution on the fly whenever a frame would take too long
	# (game.gd::_auto_resolution), so busy six-player moments stay at 60.
	{"key": "auto_res", "label": "Auto resolution (hold 60 FPS)", "opts": ON_OFF, "vals": [false, true], "def": 1},
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
	{"key": "aim_assist", "label": "Gamepad aim assist", "opts": ON_OFF, "vals": [false, true], "def": 1},
	{"key": "rumble", "label": "Controller rumble", "opts": ON_OFF, "vals": [false, true], "def": 1},
	{"section": "GAMEPLAY"},
	{"key": "fov", "label": "Field of view", "opts": ["Narrow", "Normal", "Wide"], "vals": [86.0, 100.0, 112.0], "def": 1},
	{"key": "shake", "label": "Screen shake", "opts": ["Off", "Low", "Full"], "vals": [0.0, 0.5, 1.0], "def": 2},
	{"key": "bob", "label": "View bob and sway", "opts": ["Off", "Low", "Full"], "vals": [0.0, 0.5, 1.0], "def": 2},
	{"key": "numbers", "label": "Damage numbers", "opts": ON_OFF, "vals": [false, true], "def": 1},
	{"key": "bots", "label": "Bot difficulty", "opts": ["Easy", "Normal", "Hard"], "vals": [0, 1, 2], "def": 1},
]

## preset index -> {key: choice index}
const PRESETS := {
	1: {"aa": 0, "scale": 2, "shadows": 0, "ssao": 0, "glow": 0, "scenery": 0, "dof": 0, "gi": 0, "volfog": 0, "decals": 0, "outlines": 0},
	2: {"aa": 1, "scale": 4, "shadows": 1, "ssao": 0, "glow": 1, "scenery": 1, "dof": 0, "gi": 0, "volfog": 0, "decals": 1},
	3: {"aa": 2, "scale": 4, "shadows": 2, "ssao": 1, "glow": 1, "scenery": 1, "dof": 1, "gi": 1, "volfog": 0, "decals": 1},
	4: {"aa": 3, "scale": 4, "shadows": 2, "ssao": 1, "glow": 1, "scenery": 1, "dof": 1, "gi": 1, "volfog": 1, "decals": 1},
}

var idx := {}
var res_factor := 1.0      # auto resolution: extra 3D scale factor set by game.gd (0.5-1)
var view_count := 1        # splitscreen views in play (game.gd); heavy effects need few views
var lobby := {}            # free-form values the lobby remembers (loadouts, map, bots)
var _items := {}           # key -> item dictionary (with opts/vals filled in)
var rows: Array = []       # ITEMS with ranges expanded; what the menu shows
var _path := ""
var _uncapped := false
var _keep_window := false


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
			for n in range(item.range[0], item.range[1] + 1):
				opts.append(str(n))
				vals.append(n)
			item["opts"] = opts
			item["vals"] = vals
			item["def"] = item.def - item.range[0]
			item["slider"] = true
		rows.append(item)
		if item.has("key"):
			_items[item.key] = item
			idx[item.key] = item.def
	_path = OS.get_executable_path().get_base_dir().path_join("fragdeck_settings.cfg")
	_load()
	# Dev: --set-<key>=<choice index> overrides a setting for this run only.
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--set-") and "=" in a:
			var kv := a.substr(6).split("=")
			if _items.has(kv[0]):
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


func reset() -> void:
	for key in _items:
		idx[key] = _items[key].def
	apply()
	save()


func apply() -> void:
	var win := get_window()
	if not _keep_window:
		var want := Window.MODE_FULLSCREEN if v("fullscreen") else Window.MODE_WINDOWED
		if win.mode != want:
			win.mode = want
	if not _uncapped:
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
	var aa: int = v("aa")
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X][aa]
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa == 1 else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.scaling_3d_scale = v("scale") * res_factor
	# FSR 1 upscaling keeps edges crisp when the 3D resolution is below 100 %.
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if vp.scaling_3d_scale < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
	vp.fsr_sharpness = 0.5


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
		cfg.set_value("settings", key, idx[key])
	for key in lobby:
		cfg.set_value("lobby", key, lobby[key])
	cfg.save(_path)


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
