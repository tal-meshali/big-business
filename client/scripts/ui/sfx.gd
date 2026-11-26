class_name Sfx
extends Node
## Table sounds and haptics. The sounds are synthesised at startup (soft
## sine chimes and filtered noise), so there are no audio assets yet; the
## commissioned sound set replaces `_build` one name at a time.
##
## The sound is meant to settle, not to grab: card sounds (the most frequent)
## are the quietest and darkest, chime notes stay at or under C6 (1047 Hz)
## with only faint overtones, and every sound fades in and out so nothing
## clicks. Card and coin sounds come in a few takes, each played a hair
## higher or lower, so repeats do not sound mechanical. Card sounds keep a
## little body around 300-900 Hz so a phone speaker still plays them.
##
## Settings (sound, vibration) are saved in SETTINGS_PATH and toggled from
## the rules and help screen.

const SETTINGS_PATH := "user://settings.cfg"
const MIX_RATE := 22050
const VOICES := 6
## Names every caller may play; `play` ignores anything else.
const NAMES := ["deal", "place", "coin", "gold", "turn", "tick", "fanfare"]
## Sounds whose pitch drifts a little on each play. Chimes stay in tune.
const DRIFT := {"deal": 0.04, "place": 0.03, "coin": 0.02}

static var sound_on := true
static var vibration_on := true
static var _loaded := false
## name -> Array[AudioStream]: one or more takes of the same sound. A single
## AudioStream (e.g. a commissioned .ogg) is also accepted.
static var _streams: Dictionary = {}

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _last_take: Dictionary = {}
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
	var p := _free_player()
	p.stream = _take(sound_name)
	p.volume_db = volume_db
	var drift: float = DRIFT.get(sound_name, 0.0)
	p.pitch_scale = 1.0 + randf_range(-drift, drift)
	p.play()


## An idle voice if there is one, so a ringing chime is not cut short;
## otherwise the voice used longest ago.
func _free_player() -> AudioStreamPlayer:
	for k in _players.size():
		var p := _players[(_next + k) % _players.size()]
		if not p.playing:
			_next = (_next + k + 1) % _players.size()
			return p
	var oldest := _players[_next]
	_next = (_next + 1) % _players.size()
	return oldest


## A take of the sound, never the same one twice in a row.
func _take(sound_name: String) -> AudioStream:
	var entry = _streams[sound_name]
	if entry is AudioStream:
		return entry
	var takes: Array = entry
	var last := int(_last_take.get(sound_name, -1))
	var i := 0
	if takes.size() > 1:
		if last < 0:
			i = randi() % takes.size()
		else:
			i = randi() % (takes.size() - 1)
			if i >= last:
				i += 1
	_last_take[sound_name] = i
	return takes[i]


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
# Synthesis. The helpers return raw float samples so layers mix before they
# are rounded to 16 bits; `_wav` packs the finished sound.
# ---------------------------------------------------------------------------

static func _build() -> void:
	# Drawing a card: a soft paper slide, dark and breathy, no hiss.
	_streams["deal"] = [
		_wav(_slide(0.17, 0.16, 1900.0, 650.0, 11)),
		_wav(_slide(0.15, 0.15, 1700.0, 600.0, 23)),
		_wav(_slide(0.18, 0.16, 2000.0, 700.0, 37)),
	]
	# Playing a card: a muted pat on felt. The body sits around 250-750 Hz
	# (low enough to feel soft, high enough for a phone speaker) under a
	# short felt brush.
	_streams["place"] = [
		_wav(_mix([_thump(300.0, 215.0, 0.15, 0.17), _slide(0.08, 0.13, 1400.0, 600.0, 5)])),
		_wav(_mix([_thump(280.0, 200.0, 0.15, 0.17), _slide(0.08, 0.13, 1300.0, 560.0, 17)])),
		_wav(_mix([_thump(320.0, 230.0, 0.15, 0.17), _slide(0.08, 0.13, 1500.0, 640.0, 29)])),
	]
	# Capital: two soft wooden notes instead of a bright ting.
	_streams["coin"] = [
		_wav(_seq([[784.0, 0.06], [1047.0, 0.0]], 0.075, 16.0, MARIMBA)),
		_wav(_seq([[740.0, 0.06], [988.0, 0.0]], 0.075, 16.0, MARIMBA)),
		_wav(_seq([[698.0, 0.06], [932.0, 0.0]], 0.075, 16.0, MARIMBA)),
	]
	_streams["gold"] = [_wav(_seq([[659.0, 0.07], [784.0, 0.07], [1047.0, 0.0]], 0.09, 10.0, MARIMBA))]
	_streams["turn"] = [_wav(_seq([[523.0, 0.13], [784.0, 0.0]], 0.16, 5.5, BELL))]
	# Countdown: a woody tock. Short, so it needs more level than the rest
	# to be noticed (table.gd plays it at -4 dB).
	_streams["tick"] = [_wav(_mix([_tone(659.0, 0.06, 50.0, 0.3, MARIMBA), _slide(0.03, 0.06, 1100.0, 700.0, 3)]))]
	_streams["fanfare"] = [_wav(_seq([[523.0, 0.15], [659.0, 0.15], [784.0, 0.15], [1047.0, 0.0]], 0.13, 4.5, BELL))]


## Overtone recipes: [ratio to the note, level]. MARIMBA's faint 4x partial
## gives a soft wooden knock; BELL keeps only a whisper of the octave.
const MARIMBA := [[1.0, 1.0], [4.0, 0.12]]
const BELL := [[1.0, 1.0], [2.0, 0.18], [3.0, 0.05]]
## Fade-in at the start of every note, long enough to round off the attack.
const ATTACK := 0.008
## Longest a chime note rings; the end fade in `_wav` rounds off the cut.
const MAX_RING := 1.1


## Decaying note made of `partials`. `decay` is the exponential rate per
## second; higher partials die away faster, like a struck bar. Decays run as
## per-sample multipliers (no exp() per sample) to keep startup quick.
static func _tone(freq: float, seconds: float, decay: float, gain: float, partials: Array) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var norm := 0.0
	for pt in partials:
		norm += float(pt[1])
	norm = maxf(norm, 0.000001)
	var attack_n := int(ATTACK * MIX_RATE)
	for pt in partials:
		var w := TAU * freq * float(pt[0]) / MIX_RATE
		var level := float(pt[1]) / norm * gain
		var rate := decay * (1.0 + (float(pt[0]) - 1.0) * 0.5)
		var step := exp(-rate / MIX_RATE)
		var amp := 1.0
		for i in n:
			var v := sin(w * i) * level * amp
			if i < attack_n:
				v *= 0.5 - 0.5 * cos(PI * i / attack_n)
			out[i] += v
			amp *= step
	return out


## Notes one after another: [[freq, gap to the next note], ...], each ringing
## until it is about 50 dB down (ln(10^2.5) = 5.76), capped at MAX_RING.
static func _seq(notes: Array, gain: float, decay: float, partials: Array) -> PackedFloat32Array:
	var ring := minf(5.76 / decay, MAX_RING)
	var total := 0.0
	var offset := 0.0
	for note in notes:
		total = maxf(total, offset + ring)
		offset += float(note[1])
	var out := PackedFloat32Array()
	out.resize(int(total * MIX_RATE))
	offset = 0.0
	for note in notes:
		var s := _tone(float(note[0]), ring, decay, gain, partials)
		var start := int(offset * MIX_RATE)
		for i in s.size():
			if start + i < out.size():
				out[start + i] += s[i]
		offset += float(note[1])
	return out


## Thud whose pitch sags as it lands, with soft 2nd and 3rd harmonics.
static func _thump(f_start: float, f_end: float, seconds: float, gain: float) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var attack_n := int(ATTACK * MIX_RATE)
	var glide := 1.0
	var glide_step := exp(-40.0 / MIX_RATE)
	var amp := 1.0
	var amp_step := exp(-30.0 / MIX_RATE)
	for i in n:
		var f := f_end + (f_start - f_end) * glide
		phase += TAU * f / MIX_RATE
		var v := (sin(phase) + 0.4 * sin(2.0 * phase) + 0.15 * sin(3.0 * phase)) / 1.55
		if i < attack_n:
			v *= 0.5 - 0.5 * cos(PI * i / attack_n)
		out[i] = v * amp * gain
		glide *= glide_step
		amp *= amp_step
	return out


## Noise through two cascaded one-pole low-passes (12 dB/octave, no
## resonance) whose cutoff glides from `cut_start` to `cut_end`: a card
## sliding (long) or brushing the felt (short). The envelope swells in over
## the first fifth and eases out, so there is no hiss spike at the start.
static func _slide(seconds: float, gain: float, cut_start: float, cut_end: float, seed: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp1 := 0.0
	var lp2 := 0.0
	for i in n:
		var u := float(i) / n
		var cut := cut_start * pow(cut_end / cut_start, u)
		var a := 1.0 - exp(-TAU * cut / MIX_RATE)
		lp1 += a * (rng.randf_range(-1.0, 1.0) - lp1)
		lp2 += a * (lp1 - lp2)
		var env := sin(PI * 0.5 * minf(u / 0.2, 1.0)) * pow(1.0 - u, 1.6)
		# Low-passed noise loses level as the cutoff falls; make it up so the
		# gain reads the same for every cutoff.
		out[i] = lp2 * env * gain * sqrt(MIX_RATE / (2.0 * cut))
	return out


static func _mix(layers: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for s in layers:
		if s.size() > out.size():
			out.resize(s.size())
		for i in s.size():
			out[i] += s[i]
	return out


## Packs samples as 16-bit PCM, with a 6 ms fade at the end so a sound that
## is cut short never ends on a click. Fades `samples` in place.
static func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var fade := mini(int(0.006 * MIX_RATE), samples.size())
	for k in fade:
		samples[samples.size() - 1 - k] *= float(k) / fade
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
