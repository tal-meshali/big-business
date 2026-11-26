class_name Sfx
extends Node
## Table sounds and haptics. The sounds are synthesised at startup (soft
## sine chimes and filtered noise), so there are no audio assets yet; the
## commissioned sound set replaces `_build` one name at a time.
##
## The sound is meant to settle, not to grab: card sounds (the most frequent)
## are the quietest and darkest, chimes stay under about 1.3 kHz with gentle
## overtones, and every sound fades in and out so nothing clicks. Card and
## coin sounds come in a few takes so repeats do not sound mechanical.
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
## name -> Array[AudioStreamWAV]: one or more takes of the same sound.
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
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _take(sound_name)
	p.volume_db = volume_db
	p.play()


## A take of the sound, never the same one twice in a row.
func _take(sound_name: String) -> AudioStreamWAV:
	var takes: Array = _streams[sound_name]
	var i := 0
	if takes.size() > 1:
		i = randi() % (takes.size() - 1)
		if i >= int(_last_take.get(sound_name, -1)):
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
# Synthesis
# ---------------------------------------------------------------------------

static func _build() -> void:
	# Drawing a card: a soft paper slide, dark and breathy, no hiss.
	_streams["deal"] = [
		_slide(0.17, 0.16, 1900.0, 650.0, 11),
		_slide(0.15, 0.15, 1700.0, 600.0, 23),
		_slide(0.18, 0.16, 2000.0, 700.0, 37),
	]
	# Playing a card: a muted pat on felt, felt more than heard.
	_streams["place"] = [
		_mix([_thump(190.0, 120.0, 0.16, 0.16), _slide(0.07, 0.10, 1100.0, 450.0, 5)]),
		_mix([_thump(175.0, 112.0, 0.16, 0.16), _slide(0.07, 0.10, 1000.0, 420.0, 17)]),
		_mix([_thump(205.0, 128.0, 0.16, 0.16), _slide(0.07, 0.10, 1150.0, 480.0, 29)]),
	]
	# Capital: two soft wooden notes instead of a bright ting.
	_streams["coin"] = [
		_seq([[784.0, 0.06], [1047.0, 0.0]], 0.09, 16.0, MARIMBA),
		_seq([[740.0, 0.06], [988.0, 0.0]], 0.09, 16.0, MARIMBA),
	]
	_streams["gold"] = [_seq([[659.0, 0.07], [784.0, 0.07], [1047.0, 0.0]], 0.09, 10.0, MARIMBA)]
	_streams["turn"] = [_seq([[523.0, 0.13], [784.0, 0.0]], 0.16, 5.0, BELL)]
	_streams["tick"] = [_mix([_tone([523.0], 0.06, 55.0, 0.15, MARIMBA), _slide(0.03, 0.03, 900.0, 600.0, 3)])]
	_streams["fanfare"] = [_seq([[523.0, 0.15], [659.0, 0.15], [784.0, 0.15], [1047.0, 0.0]], 0.13, 3.2, BELL)]


## Overtone recipes: [ratio to the note, level]. MARIMBA's 4x partial gives a
## soft wooden knock; BELL keeps only a whisper of the octave.
const MARIMBA := [[1.0, 1.0], [4.0, 0.12]]
const BELL := [[1.0, 1.0], [2.0, 0.18], [3.0, 0.05]]
## Fade-in at the start of every note, long enough to round off the attack.
const ATTACK := 0.008


## Decaying note made of `partials`. `decay` is the exponential rate per second.
static func _tone_samples(freq: float, seconds: float, decay: float, gain: float, partials: Array) -> PackedFloat32Array:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var norm := 0.0
	for pt in partials:
		norm += pt[1]
	for i in n:
		var t := float(i) / MIX_RATE
		var v := 0.0
		for pt in partials:
			# Higher partials die away faster, like a struck bar.
			v += pt[1] * sin(TAU * freq * pt[0] * t) * exp(-decay * (pt[0] - 1.0) * 0.5 * t)
		out[i] = v / norm * _attack(t) * exp(-decay * t) * gain
	return out


static func _tone(freqs: Array, seconds: float, decay: float, gain: float, partials: Array) -> AudioStreamWAV:
	var out := PackedFloat32Array()
	out.resize(int(seconds * MIX_RATE))
	for f in freqs:
		var s := _tone_samples(f, seconds, decay, gain / freqs.size(), partials)
		for i in s.size():
			out[i] += s[i]
	return _wav(out)


## Notes one after another: [[freq, gap to the next note], ...], each ringing
## out for as long as its decay needs.
static func _seq(notes: Array, gain: float, decay: float, partials: Array) -> AudioStreamWAV:
	# Ring until the note is 50 dB down (ln(10^2.5) = 5.76).
	var ring := minf(5.76 / decay, 1.6)
	var total := 0.0
	var offset := 0.0
	for note in notes:
		total = maxf(total, offset + ring)
		offset += note[1]
	var out := PackedFloat32Array()
	out.resize(int(total * MIX_RATE))
	offset = 0.0
	for note in notes:
		var s := _tone_samples(note[0], ring, decay, gain, partials)
		var start := int(offset * MIX_RATE)
		for i in s.size():
			if start + i < out.size():
				out[start + i] += s[i]
		offset += note[1]
	return _wav(out)


## Low thud whose pitch sags as it lands, with a little second harmonic so a
## phone speaker (which cannot play the fundamental) still carries it.
static func _thump(f_start: float, f_end: float, seconds: float, gain: float) -> AudioStreamWAV:
	var n := int(seconds * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var f := f_end + (f_start - f_end) * exp(-t * 40.0)
		phase += TAU * f / MIX_RATE
		var v := sin(phase) + 0.35 * sin(2.0 * phase)
		out[i] = v / 1.35 * _attack(t) * exp(-t * 30.0) * gain
	return _wav(out)


## Noise through a two-pole low-pass whose cutoff glides from `cut_start` to
## `cut_end`: a card sliding (long) or brushing the felt (short). The
## envelope swells in over the first fifth and eases out, so there is no hiss
## spike at the start.
static func _slide(seconds: float, gain: float, cut_start: float, cut_end: float, seed: int) -> AudioStreamWAV:
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
	return _wav(out)


## Raised-cosine fade-in over ATTACK seconds.
static func _attack(t: float) -> float:
	return 1.0 if t >= ATTACK else 0.5 - 0.5 * cos(PI * t / ATTACK)


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


## Packs samples as 16-bit PCM, with a 6 ms fade at the end so a sound that
## is cut short never ends on a click.
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
