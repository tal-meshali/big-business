extends SceneTree
## Rasterises the brand artwork from tools/logo_art.py into the store icons
## and the boot splash: a 1024 opaque square (iOS), a 192 legacy launcher
## icon, Android's adaptive pair (room background, cards-and-coin foreground)
## and the 1080x1920 boot splash. Exits with 1 if any file fails.
## Run: godot --headless --path client -s ../tools/make_icons.gd

const ART := "res://../tools/art/"


func _init() -> void:
	var ok := true
	var icon := _read("res://icon.svg")
	ok = _save(icon, 1.0, "res://icons/icon_1024.png", true) and ok
	ok = _save(icon, 192.0 / 1024.0, "res://icons/android_192.png", true) and ok
	ok = _save(_read(ART + "android_background.svg"), 432.0 / 1024.0, "res://icons/android_background_432.png", true) and ok
	ok = _save(_read(ART + "android_foreground.svg"), 432.0 / 1024.0, "res://icons/android_foreground_432.png", false) and ok
	ok = _save(_read(ART + "splash.svg"), 1.0, "res://icons/splash.png", true) and ok
	quit(0 if ok else 1)


func _read(path: String) -> String:
	var text := FileAccess.get_file_as_string(ProjectSettings.globalize_path(path).simplify_path())
	if text.is_empty():
		push_error("make_icons: can't read %s (run tools/logo_art.py first)" % path)
	return text


func _save(svg: String, scale: float, path: String, opaque: bool) -> bool:
	if svg.is_empty():
		return false
	var img := Image.new()
	if img.load_svg_from_string(svg, scale) != OK:
		push_error("make_icons: can't render the SVG for %s" % path)
		return false
	if opaque:
		img.convert(Image.FORMAT_RGB8)
	if img.save_png(path) != OK:
		push_error("make_icons: can't write %s" % path)
		return false
	return true
