class_name Sfx
extends Node
## Table sounds and haptics. The sounds are synthesised at startup (short
## sine chimes and filtered noise), so there are no audio assets yet; the
## commissioned sound set replaces `_build` one name at a time.
##
## Settings (sound, vibration) are saved in SETTINGS_PATH and toggled from
## the rules and help screen.

const SETTINGS_PATH := "user://settings.cfg"
const MIX_RATE := 22050
const VOICES := 6
## Names every caller may play; `play` ignores anything else.
const NAMES := ["deal", "place", "coin", "gold", "turn", "tick", "fanfare"]

static var sound_on := true
static var vibration_on := true
static var _loaded := false
static var _streams: Dictionary = {}

var _players: Array[AudioStreamPlayer] = []
var _next := 0
## Names played so far, newest last (tests read this; capped).
var history: Array[String] = []


func _ready() -> void:
	load_settings()
	if _streams.is_empty():
		_build()
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


func play(sound_name: String, volume_db: float = 0.0) -> void:
	if not _streams.has(sound_name):
		return
	history.append(sound_name)
	if history.size() > 50:
		history.pop_front()
	if not sound_on or _players.is_empty():
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[sound_name]
	p.volume_db = volume_db
	p.play()


## Short buzz on phones; ignored on desktop.
static func buzz(ms: int = 30) -> void:
	if vibration_on and OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)


static func load_settings() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		sound_on = cfg.get_value("feedback", "sound", true)
		vibration_on = cfg.get_value("feedback", "vibration", true)


static func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("feedback", "sound", sound_on)
	cfg.set_value("feedback", "vibration", vibration_on)
	cfg.save(SETTINGS_PATH)


# ---------------------------------------------------------------------------
# Synthesis
# ---------------------------------------------------------------------------

static func _build() -> void:
	_streams["deal"] = _noise(0.09, 0.35, 0.02)
	_streams["place"] = _mix([_tone([140.0], 0.12, 30.0, 0.7), _noise(0.05, 0.25, 0.3)])
	_streams["coin"] = _seq([[1760.0, 0.05], [2349.0, 0.09]], 0.35, 25.0)
	_streams["gold"] = _seq([[1319.0, 0.06], [1760.0, 0.06], [2637.0, 0.16]], 0.35, 14.0)
	_streams["turn"] = _seq([[784.0, 0.12], [1175.0, 0.28]], 0.45, 7.0)
	_streams["tick"] = _tone([1200.0], 0.035, 60.0, 0.3)
	_streams["fanfare"] = _seq([[523.0, 0.14], [659.0, 0.14], [784.0, 0.14], [1047.0, 0.5]], 0.45, 4.0)


## Decaying sum of sines. `decay` is the exponential rate per second.
static func _tone_samples(freqs: Array, seconds: float, decay: float, gain: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var v := 0.0
		for f in freqs:
			v += sin(TAU * f * t)
		# 4 ms attack avoids a click at the start.
		var env := minf(1.0, t / 0.004) * exp(-decay * t)
		out[i] = v / freqs.size() * env * gain
	return out


static func _tone(freqs: Array, seconds: float, decay: float, gain: float) -> AudioStreamWAV:
	return _wav(_tone_samples(freqs, seconds, decay, gain))


## Notes one after another: [[freq, seconds], ...], each ringing out.
static func _seq(notes: Array, gain: float, decay: float) -> AudioStreamWAV:
	var offset := 0.0
	var total := 0.0
	for note in notes:
		total = maxf(total, offset + 0.5)
		offset += note[1]
	var out := PackedFloat32Array()
	out.resize(int(total * MIX_RATE))
	offset = 0.0
	for note in notes:
		var s := _tone_samples([note[0], note[0] * 2.0], 0.5, decay, gain)
		var start := int(offset * MIX_RATE)
		for i in s.size():
			if start + i < out.size():
				out[start + i] += s[i]
		offset += note[1]
	return _wav(out)


## Low-passed noise burst: a card sliding or landing.
static func _noise(seconds: float, gain: float, smooth: float) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var alpha := clampf(1.0 - smooth, 0.05, 1.0)
	for i in n:
		lp += alpha * (rng.randf_range(-1.0, 1.0) - lp)
		var t := float(i) / n
		out[i] = lp * gain * sin(PI * t)
	return _wav(out)


static func _mix(streams: Array) -> AudioStreamWAV:
	var out := PackedFloat32Array()
	for st in streams:
		var s := _samples_of(st)
		if s.size() > out.size():
			out.resize(s.size())
		for i in s.size():
			out[i] += s[i]
	return _wav(out)


static func _samples_of(stream: AudioStreamWAV) -> PackedFloat32Array:
	var data := stream.data
	var out := PackedFloat32Array()
	out.resize(data.size() >> 1)
	for i in out.size():
		out[i] = data.decode_s16(i * 2) / 32767.0
	return out


static func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = MIX_RATE
	w.stereo = false
	w.data = data
	return w
