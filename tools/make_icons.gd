extends SceneTree
## Rasterises the brand artwork into the store icons and the boot splash:
## a 1024 opaque square (iOS), a 192 legacy launcher icon, Android's adaptive
## pair (the purple room as background, the cards and coin as foreground,
## shrunk into the 66% safe circle) and the 1024 boot splash.
## The SVGs come from tools/logo_art.py (client/icon.svg, tools/art/splash.svg).
## Run: godot --headless --path client -s ../tools/make_icons.gd
func _init():
	var svg := FileAccess.get_file_as_string("res://icon.svg")
	_save(svg, 1024, "res://icons/icon_1024.png", true)
	_save(svg, 192, "res://icons/android_192.png", true)
	# icon.svg is: head (defs), <!-- background --> room, <!-- art --> cards.
	var bg_at := svg.find("<!-- background -->")
	var art_at := svg.find("<!-- art -->")
	var head := svg.substr(0, bg_at)
	var room := svg.substr(bg_at, art_at - bg_at)
	var art := svg.substr(art_at).replace("</svg>", "")
	_save(head + room + "</svg>", 432, "res://icons/android_background_432.png", true)
	_save(head + '<g transform="translate(512 512) scale(0.7) translate(-512 -512)">' + art + "</g></svg>", 432, "res://icons/android_foreground_432.png", false)
	var splash := FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("../tools/art/splash.svg"))
	_save(splash, 1024, "res://icons/splash.png", true)
	quit()

func _save(svg: String, size: int, path: String, opaque: bool) -> void:
	var img := Image.new()
	img.load_svg_from_string(svg, size / 1024.0)
	if opaque:
		img.convert(Image.FORMAT_RGB8)
	img.save_png(path)
