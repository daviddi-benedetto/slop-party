extends RefCounted
## Human input for one player. device == -1 is keyboard + mouse,
## device >= 0 is a gamepad id. Devices are polled directly so that every
## player has a fully independent control set.

const KEYBOARD := -1

var device := KEYBOARD

var move := Vector2.ZERO      # x = strafe right, y = forward
var fire := false
var jump := false             # edge triggered
var dash := false             # edge triggered
var reload := false           # edge triggered
var ui_left := false          # edge triggered
var ui_right := false         # edge triggered
var ui_accept := false        # edge triggered

var mouse_accum := Vector2.ZERO
var mouse_sens := 0.0022
var stick_sens := 3.4

var _prev := {}


func _init(dev := KEYBOARD) -> void:
	device = dev


func label() -> String:
	return "Keyboard + Mouse" if device == KEYBOARD else "Gamepad %d" % (device + 1)


func _edge(key: String, now: bool) -> bool:
	var was: bool = _prev.get(key, true)
	_prev[key] = now
	return now and not was


func _axis(axis: int) -> float:
	var v := Input.get_joy_axis(device, axis)
	var a := absf(v)
	if a < 0.18:
		return 0.0
	return signf(v) * (a - 0.18) / 0.82


## Called every rendered frame while alive: turns the view.
func update_look(player, delta: float) -> void:
	if device == KEYBOARD:
		player.yaw -= mouse_accum.x * mouse_sens
		player.pitch -= mouse_accum.y * mouse_sens
		mouse_accum = Vector2.ZERO
	else:
		var lx := _axis(JOY_AXIS_RIGHT_X)
		var ly := _axis(JOY_AXIS_RIGHT_Y)
		# Squared response curve: fine aim near centre, fast turns at the edge.
		# aim_friction() is the aim assist: the stick slows while on a target.
		var f: float = player.game.aim_friction(player)
		player.yaw -= lx * absf(lx) * stick_sens * f * delta
		player.pitch -= ly * absf(ly) * stick_sens * 0.7 * f * delta
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
		jump = _edge("jump", Input.is_physical_key_pressed(KEY_SPACE))
		dash = _edge("dash", Input.is_physical_key_pressed(KEY_SHIFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT))
		reload = _edge("reload", Input.is_physical_key_pressed(KEY_R))
		ui_left = _edge("ui_left", Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
		ui_right = _edge("ui_right", Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))
		ui_accept = _edge("ui_accept", Input.is_physical_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_ENTER) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))
	else:
		var m := Vector2(_axis(JOY_AXIS_LEFT_X), -_axis(JOY_AXIS_LEFT_Y))
		move = m.limit_length(1.0)
		fire = Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT) > 0.4 or Input.is_joy_button_pressed(device, JOY_BUTTON_RIGHT_SHOULDER)
		jump = _edge("jump", Input.is_joy_button_pressed(device, JOY_BUTTON_A) or Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT) > 0.4)
		dash = _edge("dash", Input.is_joy_button_pressed(device, JOY_BUTTON_B) or Input.is_joy_button_pressed(device, JOY_BUTTON_LEFT_SHOULDER) or Input.is_joy_button_pressed(device, JOY_BUTTON_LEFT_STICK))
		reload = _edge("reload", Input.is_joy_button_pressed(device, JOY_BUTTON_X))
		var sx := Input.get_joy_axis(device, JOY_AXIS_LEFT_X)
		ui_left = _edge("ui_left", Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_LEFT) or sx < -0.6)
		ui_right = _edge("ui_right", Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_RIGHT) or sx > 0.6)
		ui_accept = _edge("ui_accept", Input.is_joy_button_pressed(device, JOY_BUTTON_A))
