extends SceneTree
## Rasterises client/icon.svg into the store icons: a 1024 opaque square (iOS),
## a 192 legacy launcher icon, and Android's adaptive pair (felt background,
## artwork foreground shrunk into the 66% safe circle), and the boot splash.
## Run: godot --headless --path client -s ../tools/make_icons.gd
func _init():
	var svg := FileAccess.get_file_as_string("res://icon.svg")
	_save(svg, 1024, "res://icons/icon_1024.png", true)
	_save(svg, 192, "res://icons/android_192.png", true)
	var bg_end := svg.find("<!-- table -->")
	var head := svg.substr(0, bg_end)
	_save(head + "</svg>", 432, "res://icons/android_background_432.png", true)
	var art := svg.substr(bg_end).replace("</svg>", "")
	var head_no_bg := head.replace('<rect width="1024" height="1024" fill="url(#felt)"/>', "")
	_save(head_no_bg + '<g transform="translate(512 540) scale(0.72) translate(-512 -540)">' + art + "</g></svg>", 432, "res://icons/android_foreground_432.png", false)
	# Boot splash: the artwork alone, on the project's felt-green background.
	_save(head_no_bg + art + "</svg>", 512, "res://icons/splash.png", false)
	quit()

func _save(svg: String, size: int, path: String, opaque: bool) -> void:
	var img := Image.new()
	img.load_svg_from_string(svg, size / 1024.0)
	if opaque:
		img.convert(Image.FORMAT_RGB8)
	img.save_png(path)
