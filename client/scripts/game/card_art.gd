class_name CardArt
## Custom card art from the Designer unlock (decision D5): cropping and
## rendering a picture to a part's template, and the textures of the custom
## deck the current private room shows. Bottom layer: no Net or ui.
##
## Parts are "back" (the whole card back, 5:7) and "c0".."c5" (one company's
## art window on the card face). Sizes must match server/src/match/designer.ts.
## The card frame, company name and share count are always drawn by
## CardView around the art, so a custom design never hides what a card is.

const BACK_SIZE := Vector2i(250, 350)
const WINDOW_SIZE := Vector2i(352, 184)
## The server refuses images above this many bytes.
const MAX_BYTES := 64 * 1024
const PARTS: Array[String] = ["back", "c0", "c1", "c2", "c3", "c4", "c5"]
const CACHE_DIR := "user://card_art"
const SETTINGS_PATH := "user://designer.cfg"

## The room's deck: {owner, back, art: [6]} with art hashes or null; {} for none.
static var room_deck: Dictionary = {}
## Show custom decks other players bring to a private room.
static var show_custom: bool = true
## Show a Plus member's deck in quick play games (off unless the player opts in).
static var show_public: bool = false
## Textures by art hash (memory cache over the disk cache).
static var _textures: Dictionary = {}


static func template_size(part: String) -> Vector2i:
	return BACK_SIZE if part == "back" else WINDOW_SIZE


## The source rectangle of `src_size` to keep for a part: the largest one at
## the template's aspect, shrunk by `zoom` (1 = as large as fits), centred
## on `center` (0..1 in each axis) and kept inside the picture.
static func crop_rect(src_size: Vector2i, part: String, zoom: float, center: Vector2) -> Rect2i:
	var t := template_size(part)
	var aspect := float(t.x) / float(t.y)
	var w := float(src_size.x)
	var h := w / aspect
	if h > src_size.y:
		h = float(src_size.y)
		w = h * aspect
	var z := clampf(zoom, 1.0, 8.0)
	w /= z
	h /= z
	var cx := clampf(center.x * src_size.x, w / 2.0, src_size.x - w / 2.0)
	var cy := clampf(center.y * src_size.y, h / 2.0, src_size.y - h / 2.0)
	return Rect2i(int(round(cx - w / 2.0)), int(round(cy - h / 2.0)), maxi(1, int(round(w))), maxi(1, int(round(h))))


## The picture cropped and scaled to the part's template, without alpha.
static func render(picture: Image, part: String, zoom: float = 1.0, center: Vector2 = Vector2(0.5, 0.5)) -> Image:
	var src := picture.duplicate() as Image
	if src.is_compressed():
		src.decompress()
	var rect := crop_rect(Vector2i(src.get_width(), src.get_height()), part, zoom, center)
	var out := src.get_region(rect)
	var t := template_size(part)
	out.resize(t.x, t.y, Image.INTERPOLATE_LANCZOS)
	# WHY RGB8: an alpha channel makes the WebP an extended file with an
	# extra chunk; the art window and back are always opaque.
	out.convert(Image.FORMAT_RGB8)
	return out


## Lossy WebP bytes under MAX_BYTES (quality steps down until it fits), or
## an empty array when even the lowest quality is too large.
static func encode(rendered: Image) -> PackedByteArray:
	for quality in [0.82, 0.7, 0.55, 0.4]:
		var bytes := rendered.save_webp_to_buffer(true, quality)
		if bytes.size() > 0 and bytes.size() <= MAX_BYTES:
			return bytes
	return PackedByteArray()


## Width and height from a WebP header, or Vector2i.ZERO. Mirrors the
## server's check (designer.ts `webpSize`) for the lossy files encode() makes.
static func webp_size(bytes: PackedByteArray) -> Vector2i:
	if bytes.size() < 30 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF" or bytes.slice(8, 12).get_string_from_ascii() != "WEBP":
		return Vector2i.ZERO
	if bytes.slice(12, 16).get_string_from_ascii() != "VP8 ":
		return Vector2i.ZERO
	return Vector2i(bytes.decode_u16(26) & 0x3fff, bytes.decode_u16(28) & 0x3fff)


static func texture_from_webp(bytes: PackedByteArray) -> Texture2D:
	var img := Image.new()
	if img.load_webp_from_buffer(bytes) != OK:
		return null
	return ImageTexture.create_from_image(img)


## Keeps a fetched picture: memory and disk, keyed by its content hash.
static func add_art(hash: String, base64: String) -> bool:
	var bytes := Marshalls.base64_to_raw(base64)
	var tex := texture_from_webp(bytes)
	if tex == null:
		return false
	_textures[hash] = tex
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	var f := FileAccess.open("%s/%s.webp" % [CACHE_DIR, hash], FileAccess.WRITE)
	if f != null:
		f.store_buffer(bytes)
	return true


## The texture for a hash from memory or the disk cache, or null.
static func texture(hash: String) -> Texture2D:
	if hash.is_empty():
		return null
	if _textures.has(hash):
		return _textures[hash]
	var path := "%s/%s.webp" % [CACHE_DIR, hash]
	if not FileAccess.file_exists(path):
		return null
	var tex := texture_from_webp(FileAccess.get_file_as_bytes(path))
	if tex != null:
		_textures[hash] = tex
	return tex


## Hashes of the room deck that are not cached yet.
static func missing_hashes() -> Array[String]:
	var out: Array[String] = []
	for h in deck_hashes():
		if texture(h) == null:
			out.append(h)
	return out


static func deck_hashes() -> Array[String]:
	var out: Array[String] = []
	if room_deck.is_empty():
		return out
	for h in [room_deck.get("back")] + Array(room_deck.get("art", [])):
		if h is String and not h.is_empty() and not out.has(h):
			out.append(h)
	return out


static func set_room_deck(deck: Dictionary) -> void:
	room_deck = deck


static func clear_room_deck() -> void:
	room_deck = {}


static func deck_owner() -> String:
	return String(room_deck.get("owner", ""))


## The room's custom back, or null for the selected cosmetic back.
static func back_texture() -> Texture2D:
	if room_deck.is_empty() or not show_custom:
		return null
	var h = room_deck.get("back")
	return texture(h) if h is String else null


## The room's custom art window for a company, or null for the standard icon.
static func company_texture(company: int) -> Texture2D:
	if room_deck.is_empty() or not show_custom:
		return null
	var art: Array = room_deck.get("art", [])
	if company < 0 or company >= art.size():
		return null
	var h = art[company]
	return texture(h) if h is String else null


static func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		show_custom = bool(cfg.get_value("designer", "show_custom", true))
		show_public = bool(cfg.get_value("designer", "show_public", false))


static func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("designer", "show_custom", show_custom)
	cfg.set_value("designer", "show_public", show_public)
	cfg.save(SETTINGS_PATH)
