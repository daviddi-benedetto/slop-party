extends RefCounted
## Human input for one player. device == -1 is keyboard + mouse,
## device >= 0 is a gamepad id. Devices are polled directly (no InputMap) so
## that every player has a fully independent control set.
##
##             gamepad                     keyboard + mouse
##   move      left stick                  WASD
##   look      right stick                 mouse
##   fire      RT                          left mouse
##   aim       LT (hold)                   right mouse (hold)
##   jump      A                           Space
##   dash      RB or left-stick click      Shift
##   block     LB                          Q
##   reload    X                           R
##   interact  Y (pick up weapon)          E
##   melee     right-stick click           F
##   crouch    B (hold)                    C or Ctrl  (slide when running)
##   (in a vehicle: interact = get out, jump/crouch = climb/descend)
##
## Look is applied every rendered frame (update_look) for the lowest latency;
## buttons and movement are sampled every physics tick (update_buttons).
## The right stick uses a radial dead zone, a 1.6-power response curve and a
## short turn boost when held hard over, so small corrections are precise and
## big turns are quick.

const KEYBOARD := -1

var device := KEYBOARD

var move := Vector2.ZERO      # x = strafe right, y = forward
var fire := false
var aim := false              # held
var crouch := false           # held (crouch, or slide when running)
var jump_held := false        # held (jetpack)
var jump := false             # edge triggered
var dash := false             # edge triggered
var block := false            # edge triggered
var reload := false           # edge triggered
var interact := false         # edge triggered
var melee := false            # edge triggered
var ui_left := false          # edge triggered
var ui_right := false         # edge triggered
var ui_accept := false        # edge triggered

var mouse_accum := Vector2.ZERO
var mouse_sens := 0.0022
var stick_sens := 3.5

var _prev := {}
var _boost := 0.0


func _init(dev := KEYBOARD) -> void:
	device = dev


func label() -> String:
	return "Keyboard + Mouse" if device == KEYBOARD else "Gamepad %d" % (device + 1)


func _edge(key: String, now: bool) -> bool:
	var was: bool = _prev.get(key, true)
	_prev[key] = now
	return now and not was


## Stick with a radial dead zone, rescaled so it starts from zero at the edge
## of the dead zone. `power` > 1 gives finer control near the centre.
func _stick(axis_x: int, axis_y: int, power: float) -> Vector2:
	var v := Vector2(Input.get_joy_axis(device, axis_x), Input.get_joy_axis(device, axis_y))
	var m := v.length()
	var dz: float = Settings.v("deadzone")
	if m <= dz:
		return Vector2.ZERO
	return v / m * pow((minf(m, 1.0) - dz) / (1.0 - dz), power)


## Called every rendered frame while alive: turns the view.
func update_look(player, delta: float) -> void:
	var zoom: float = player.zoom_factor()
	var inv := -1.0 if Settings.v("invert_y") else 1.0
	if device == KEYBOARD:
		var ms: float = mouse_sens * (0.4 + Settings.v("mouse") * 0.15) * zoom
		player.yaw -= mouse_accum.x * ms
		player.pitch -= mouse_accum.y * ms * inv
		mouse_accum = Vector2.ZERO
	else:
		var v := _stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y, 1.6)
		# Held hard over: ramp the turn rate up for fast 180s.
		_boost = minf(1.0, _boost + delta * 3.0) if absf(v.x) > 0.9 else 0.0
		var f: float = player.game.aim_friction(player) if Settings.v("aim_assist") else 1.0
		var ss: float = stick_sens * (0.4 + Settings.v("stick") * 0.15) * f * zoom
		player.yaw -= v.x * ss * (1.0 + 0.6 * _boost) * delta
		player.pitch -= v.y * ss * 0.72 * delta * inv
	player.pitch = clampf(player.pitch, -1.5, 1.5)


## Called every physics tick: movement and buttons.
func update_buttons(_player, _delta: float) -> void:
	if device == KEYBOARD:
		var k := Vector2.ZERO
		if Input.is_physical_key_pressed(KEY_W): k.y += 1.0
		if Input.is_physical_key_pressed(KEY_S): k.y -= 1.0
		if Input.is_physical_key_pressed(KEY_D): k.x += 1.0
		if Input.is_physical_key_pressed(KEY_A): k.x -= 1.0
		move = k.normalized()
		fire = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		aim = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
		jump_held = Input.is_physical_key_pressed(KEY_SPACE)
		jump = _edge("jump", jump_held)
		crouch = Input.is_physical_key_pressed(KEY_C) or Input.is_physical_key_pressed(KEY_CTRL)
		dash = _edge("dash", Input.is_physical_key_pressed(KEY_SHIFT))
		block = _edge("block", Input.is_physical_key_pressed(KEY_Q))
		reload = _edge("reload", Input.is_physical_key_pressed(KEY_R))
		interact = _edge("interact", Input.is_physical_key_pressed(KEY_E))
		melee = _edge("melee", Input.is_physical_key_pressed(KEY_F))
		ui_left = _edge("ui_left", Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
		ui_right = _edge("ui_right", Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))
		ui_accept = _edge("ui_accept", Input.is_physical_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_ENTER) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))
	else:
		var m := _stick(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, 1.0)
		move = Vector2(m.x, -m.y).limit_length(1.0)
		fire = Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT) > 0.3
		aim = Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT) > 0.3
		jump_held = Input.is_joy_button_pressed(device, JOY_BUTTON_A)
		jump = _edge("jump", jump_held)
		# B crouches or slides when running; R3 is reserved for melee.
		crouch = Input.is_joy_button_pressed(device, JOY_BUTTON_B)
		dash = _edge("dash", Input.is_joy_button_pressed(device, JOY_BUTTON_RIGHT_SHOULDER) or Input.is_joy_button_pressed(device, JOY_BUTTON_LEFT_STICK))
		block = _edge("block", Input.is_joy_button_pressed(device, JOY_BUTTON_LEFT_SHOULDER))
		reload = _edge("reload", Input.is_joy_button_pressed(device, JOY_BUTTON_X))
		interact = _edge("interact", Input.is_joy_button_pressed(device, JOY_BUTTON_Y))
		melee = _edge("melee", Input.is_joy_button_pressed(device, JOY_BUTTON_RIGHT_STICK))
		var sx := Input.get_joy_axis(device, JOY_AXIS_LEFT_X)
		ui_left = _edge("ui_left", Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_LEFT) or sx < -0.6)
		ui_right = _edge("ui_right", Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_RIGHT) or sx > 0.6)
		ui_accept = _edge("ui_accept", Input.is_joy_button_pressed(device, JOY_BUTTON_A))
