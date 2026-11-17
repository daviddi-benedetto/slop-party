extends Control
## Screen transition used in place of a black fade (main.gd, game.gd). It is
## driven exactly like a fading ColorRect: tween `color:a` from 0 to 1 to
## cover the screen and back to 0 to reveal it. Instead of fading, a slanted
## curtain in the theme's colours (UiKit.GOLD / ACCENT stripes on an ink
## body) sweeps in from the left and carries on out to the right.

const UiKit = preload("res://scripts/ui_kit.gd")

var color := Color(UiKit.INK, 1.0):
	set(v):
		var rising: bool = v.a > color.a
		if color.a <= 0.001 and rising:
			_out = false          # covering: sweep in from the left
		elif color.a >= 0.999 and not rising:
			_out = true           # revealing: carry on out to the right
		color = v
		queue_redraw()

var _out := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var a := clampf(color.a, 0.0, 1.0)
	if a <= 0.001:
		return
	var w := size.x
	var h := size.y
	var skew := h * 0.35
	var bands := [[UiKit.ACCENT, 0.0], [UiKit.GOLD, h * 0.05], [color, h * 0.1]]
	if a >= 0.999:
		draw_rect(Rect2(Vector2.ZERO, size), Color(color, 1.0))
		return
	var e := a * a * (3.0 - 2.0 * a)     # smoothstep
	for b in bands:
		var col: Color = Color(b[0], 1.0)
		var lag: float = b[1]
		var pts := PackedVector2Array()
		if not _out:
			# Leading edge moves right as `a` grows; covered on its left.
			var x: float = lerpf(-skew - h * 0.1, w + h * 0.05, e) - lag
			if x + skew <= -9.0:
				continue
			if x < -10.0:
				# Only the top corner is on screen yet: a triangle.
				var yb: float = -10.0 + (h + 20.0) * (x + skew + 10.0) / skew
				pts = PackedVector2Array([Vector2(-10, -10), Vector2(x + skew, -10), Vector2(-10, yb)])
			else:
				pts = PackedVector2Array([Vector2(-10, -10), Vector2(x + skew, -10), Vector2(x, h + 10), Vector2(-10, h + 10)])
		else:
			# Trailing edge moves right as `a` falls; covered on its right.
			var x2: float = lerpf(w + h * 0.1, -skew - h * 0.05, e) + lag
			if x2 >= w + 9.0:
				continue
			if x2 + skew > w + 10.0:
				# Only the bottom corner is still covered: a triangle.
				var yt: float = h + 10.0 - (h + 20.0) * (w + 10.0 - x2) / skew
				pts = PackedVector2Array([Vector2(w + 10, yt), Vector2(w + 10, h + 10), Vector2(x2, h + 10)])
			else:
				pts = PackedVector2Array([Vector2(x2 + skew, -10), Vector2(w + 10, -10), Vector2(w + 10, h + 10), Vector2(x2, h + 10)])
		draw_colored_polygon(pts, col)
