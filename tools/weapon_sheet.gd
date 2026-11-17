extends Node3D
## Dev tool: render weapon models side-on (as held by a character) and from
## behind (first person) into one image. main.gd runs it for
##   Godot --path . -w -- --sheet=out.png --ids=20,21,22
const Viewmodel = preload("res://scripts/viewmodel.gd")

func run(out: String, ids: Array) -> void:
	var world := self
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.35, 0.4, 0.5)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.8
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	world.add_child(sun)
	var n := ids.size()
	for i in n:
		for row in 2:
			var m = Viewmodel.new()
			world.add_child(m)
			m.build(Color(1.0, 0.5, 0.2), 1, ids[i], row == 1)
			m.position = Vector3((i - (n - 1) * 0.5) * 1.3, 0.9 - row * 1.5, 0)
			# top row: seen from the right side (muzzle to the left); bottom: first-person style from behind
			m.rotation.y = -PI * 0.5 if row == 0 else PI
			var mark := MeshInstance3D.new()
			var s := SphereMesh.new()
			s.radius = 0.02
			s.height = 0.04
			mark.mesh = s
			m.add_child(mark)
			mark.position = m.muzzle_local()
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(3.4, n * 1.3 * 9.0 / 16.0 + 0.4)
	cam.position = Vector3(0, 0.1, 6)
	world.add_child(cam)
	cam.current = true
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
