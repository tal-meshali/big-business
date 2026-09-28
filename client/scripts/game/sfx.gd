extends Node
## Autoload "Sfx": placeholder sound set synthesized in code at startup, so
## the table has feedback sounds before any audio assets are commissioned
## (docs/TODO-local.md, section F). Bottom layer: never references scripts/ui.
##
## Every sound is a short 16-bit mono 22050 Hz AudioStreamWAV built from
## sine or triangle blips with an attack/decay envelope, plus a little noise
## for the card sounds. `play(name)` picks a free player from a small pool.

const SETTINGS_PATH := "user://sfx.cfg"
const MIX_RATE := 22050
const POOL_SIZE := 6
const NAMES: Array[String] = [
	"card_deal", "card_place", "coin_slide", "coin_gold",
	"turn_chime", "dividend_fanfare", "timer_tick",
]

## Sound on/off, persisted so the choice survives a restart.
## WHY: stored in its own file rather than user://net.cfg, because
## Net.save_settings rewrites that file wholesale and would drop this key.
var enabled: bool = true:
	set(value):
		if enabled == value:
			return
		enabled = value
		_save_settings()

## name -> AudioStreamWAV, filled by _build_all in _ready.
var streams: Dictionary = {}
## Sounds accepted by play() since startup (enabled and known), for tests.
var played_count: int = 0
var _pool: Array[AudioStreamPlayer] = []
var _next_player: int = 0
## WHY: the headless dummy audio driver never mixes, so a playback started
## in a headless test never finishes and its objects leak at exit. Sounds are
## accepted and counted but no player is started.
var _silent: bool = DisplayServer.get_name() == "headless"


func _ready() -> void:
	_load_settings()
	_build_all()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_pool.append(p)


## Play a named sound. Returns true when the sound was accepted (sound on
## and the name known), so a test can confirm the disabled state is a no-op.
func play(sound_name: String) -> bool:
	if not enabled:
		return false
	var stream: AudioStreamWAV = streams.get(sound_name)
	if stream == null or _pool.is_empty():
		push_warning("Sfx: unknown sound %s" % sound_name)
		return false
	played_count += 1
	if _silent:
		return true
	# WHY: a small pool instead of one player, so a coin shower on dividend
	# day does not cut off the sound that started a few milliseconds earlier.
	var player := _pool[_next_player]
	for p in _pool:
		if not p.playing:
			player = p
			break
	_next_player = (_next_player + 1) % _pool.size()
	player.stream = stream
	player.play()
	return true


## Silence every pooled player (leaving the table, or before a test).
func stop_all() -> void:
	for p in _pool:
		p.stop()


## True while any pooled player is playing (for tests).
func is_playing() -> bool:
	for p in _pool:
		if p.playing:
			return true
	return false


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		enabled = bool(cfg.get_value("sound", "enabled", true))


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("sound", "enabled", enabled)
	cfg.save(SETTINGS_PATH)


# ---------------------------------------------------------------------------
# Synthesis. A "note" is {freq, freq_end, start, dur, wave, gain}; the
# sample is the sum of all notes, each with a 5 ms attack and a decay that
# reaches silence at the end of the note. Noise is a separate burst.
# ---------------------------------------------------------------------------

func _build_all() -> void:
	streams["card_deal"] = _synth(0.12, [_note(260.0, 0.0, 0.10, "tri", 0.25, 180.0)], 0.35, 0.0, 0.07)
	streams["card_place"] = _synth(0.10, [_note(170.0, 0.0, 0.08, "tri", 0.3, 120.0)], 0.28, 0.0, 0.05)
	streams["coin_slide"] = _synth(0.14, [_note(640.0, 0.0, 0.12, "sine", 0.35, 960.0)], 0.06, 0.0, 0.03)
	streams["coin_gold"] = _synth(0.26, [
		_note(880.0, 0.0, 0.10, "sine", 0.35),
		_note(1320.0, 0.09, 0.16, "sine", 0.4),
	], 0.0, 0.0, 0.0)
	streams["turn_chime"] = _synth(0.55, [
		_note(660.0, 0.0, 0.30, "sine", 0.35),
		_note(990.0, 0.14, 0.40, "sine", 0.35),
	], 0.0, 0.0, 0.0)
	streams["dividend_fanfare"] = _synth(0.85, [
		_note(523.25, 0.0, 0.16, "tri", 0.35),
		_note(659.25, 0.15, 0.16, "tri", 0.35),
		_note(783.99, 0.30, 0.16, "tri", 0.35),
		_note(1046.5, 0.45, 0.40, "tri", 0.4),
		_note(1318.5, 0.45, 0.40, "sine", 0.15),
	], 0.0, 0.0, 0.0)
	streams["timer_tick"] = _synth(0.05, [_note(1400.0, 0.0, 0.035, "sine", 0.45)], 0.15, 0.0, 0.01)


func _note(freq: float, start: float, dur: float, wave: String, gain: float, freq_end: float = -1.0) -> Dictionary:
	return {"freq": freq, "freq_end": freq_end if freq_end > 0.0 else freq, "start": start, "dur": dur, "wave": wave, "gain": gain}


## Render `duration` seconds of the given notes plus a noise burst of
## `noise_gain` starting at `noise_start` lasting `noise_dur` seconds.
func _synth(duration: float, notes: Array, noise_gain: float, noise_start: float, noise_dur: float) -> AudioStreamWAV:
	var count := int(duration * MIX_RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var phases: PackedFloat64Array = PackedFloat64Array()
	phases.resize(notes.size())
	var dt := 1.0 / MIX_RATE
	for i in count:
		var t := i * dt
		var v := 0.0
		for n in notes.size():
			var note: Dictionary = notes[n]
			var local := t - float(note["start"])
			var dur := float(note["dur"])
			if local < 0.0 or local >= dur:
				continue
			# WHY: phase accumulation (not sin(2*pi*f*t)) so a frequency sweep
			# stays continuous and does not click.
			var f := lerpf(float(note["freq"]), float(note["freq_end"]), local / dur)
			phases[n] += f * dt
			var ph := fmod(phases[n], 1.0)
			var s := sin(ph * TAU) if note["wave"] == "sine" else (4.0 * absf(ph - 0.5) - 1.0)
			v += s * float(note["gain"]) * _envelope(local, dur)
		if noise_gain > 0.0:
			var nl := t - noise_start
			if nl >= 0.0 and nl < noise_dur:
				v += rng.randf_range(-1.0, 1.0) * noise_gain * _envelope(nl, noise_dur)
		var sample := int(clampf(v, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, sample)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream


## 5 ms linear attack, then a decay that reaches zero at the note's end.
func _envelope(t: float, dur: float) -> float:
	var attack := minf(t / 0.005, 1.0)
	var remaining := clampf((dur - t) / dur, 0.0, 1.0)
	return attack * remaining * remaining
