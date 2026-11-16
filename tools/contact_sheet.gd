extends SceneTree
## Dev tool: combine screenshots into one grid image.
##   engine\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script tools/contact_sheet.gd -- out.png 3 a.png b.png c.png ...
## Arguments after "--": output file, number of columns, then the images.
## Optional first argument crop=x,y,w,h crops every image first (zoom in).

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var crop := Rect2i()
	if args.size() > 0 and args[0].begins_with("crop="):
		var c: PackedStringArray = args[0].substr(5).split(",")
		crop = Rect2i(int(c[0]), int(c[1]), int(c[2]), int(c[3]))
		args = args.slice(1)
	var out: String = args[0]
	var cols := int(args[1])
	var files := args.slice(2)
	var imgs: Array = []
	for f in files:
		var img := Image.load_from_file(f)
		if img != null:
			if crop.size != Vector2i.ZERO:
				img = img.get_region(crop)
			img.resize(640, 360)
			imgs.append(img)
	var rows := int(ceil(imgs.size() / float(cols)))
	var sheet := Image.create(640 * cols, 360 * rows, false, Image.FORMAT_RGB8)
	for i in imgs.size():
		var img: Image = imgs[i]
		img.convert(Image.FORMAT_RGB8)
		sheet.blit_rect(img, Rect2i(0, 0, 640, 360), Vector2i((i % cols) * 640, (i / cols) * 360))
	sheet.save_png(out)
	print("contact sheet: ", out)
	quit()
