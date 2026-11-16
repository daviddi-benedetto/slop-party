extends Node
## Autoload "Sfx": all audio. Nothing is loaded from disk - sound effects are
## synthesised at startup and the two music loops are composed and rendered in
## a background thread (so startup is not delayed; music fades in when ready).
##
## play(name)            UI / personal feedback, always full volume.
## play_at(name, pos)    world sounds. Volume falls off with the distance to
##                       the nearest entry of `listeners` (game.gd keeps that
##                       list filled with the human players' positions). With
##                       several players on one screen there is no stereo pan.
## music(name)           "lobby", "battle" or "" - cross-fades.
##
## Volumes come from Settings ("sfx", "music"; master is the audio bus).

const RATE := 22050
const VOICES := 24

var listeners: Array = []          # Vector3 world positions of human players

var _streams := {}
var _players: Array = []
var _next := 0
var _music_player: AudioStreamPlayer
var _tracks := {}
var _want_music := ""
var _playing_music := ""
var _thread: Thread
var _duck := 0.0                    # extra dB reduction (pause menu)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_music_player = AudioStreamPlayer.new()
	_music_player.volume_db = -60.0
	add_child(_music_player)
	_build_effects()
	_thread = Thread.new()
	_thread.start(_render_music)


func _exit_tree() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()


# --------------------------------------------------------------------------
# Playback
# --------------------------------------------------------------------------

func play(sound: String, volume_db := 0.0, pitch := 1.0) -> void:
	if not _streams.has(sound):
		return
	var level: int = Settings.v("sfx")
	if level == 0:
		return
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = _streams[sound]
	p.volume_db = volume_db - 5.0 + linear_to_db(level / 8.0)
	p.pitch_scale = pitch * randf_range(0.96, 1.04)
	p.play()


func play_at(sound: String, pos: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	if listeners.is_empty():
		play(sound, volume_db, pitch)
		return
	var nearest := 1e9
	for l in listeners:
		nearest = minf(nearest, pos.distance_to(l))
	if nearest > 75.0:
		return
	play(sound, volume_db - 20.0 * log(1.0 + nearest / 9.0) / log(10.0), pitch)


func music(track: String) -> void:
	_want_music = track


func duck(on: bool) -> void:
	_duck = 10.0 if on else 0.0


func _process(delta: float) -> void:
	var level: int = Settings.v("music")
	var target := -60.0
	if _want_music == _playing_music and _playing_music != "" and level > 0:
		target = -15.0 + linear_to_db(level / 6.0) - _duck
	_music_player.volume_db = move_toward(_music_player.volume_db, target, delta * 70.0)
	if _want_music != _playing_music and _music_player.volume_db <= -59.0:
		_playing_music = ""
		_music_player.stop()
		if _want_music != "" and _tracks.has(_want_music):
			_music_player.stream = _tracks[_want_music]
			_music_player.play()
			_playing_music = _want_music


# --------------------------------------------------------------------------
# Sound effects
# --------------------------------------------------------------------------

func _noise() -> float:
	return randf() * 2.0 - 1.0


## A soft bell/chime partial stack.
func _bell(t: float, f: float, decay: float) -> float:
	if t < 0.0:
		return 0.0
	return (sin(TAU * f * t) + 0.35 * sin(TAU * f * 2.0 * t) + 0.15 * sin(TAU * f * 3.01 * t)) * exp(-t * decay)


## Sine whose frequency glides from f0 to f1 (exponentially, rate k).
func _sweep(t: float, f0: float, f1: float, k: float) -> float:
	return sin(TAU * (f1 * t + (f0 - f1) / k * (1.0 - exp(-k * t))))


func _build_effects() -> void:
	_streams["shoot"] = _make(0.16, 0.5, func(t, _d): return (_sweep(t, 1500.0, 240.0, 34.0) * 0.6 + _sweep(t, 3000.0, 480.0, 34.0) * 0.15 + (_noise() * 0.5 if t < 0.012 else 0.0)) * exp(-t * 20.0))
	_streams["hit"] = _make(0.12, 1.0, func(t, _d): return (_bell(t, 1760.0, 45.0) + _bell(t - 0.03, 2349.0, 45.0)) * 0.3)
	_streams["hurt"] = _make(0.16, 0.25, func(t, _d): return (_sweep(t, 220.0, 90.0, 20.0) * 0.8 + _noise() * 0.35) * exp(-t * 22.0))
	_streams["pop"] = _make(0.5, 0.6, func(t, _d): return (_noise() * 0.7 if t < 0.03 else 0.0) + _sweep(t, 900.0, 140.0, 16.0) * 0.6 * exp(-t * 12.0) + (_bell(t - 0.05, 1568.0, 14.0) + _bell(t - 0.11, 2093.0, 14.0) + _bell(t - 0.17, 2637.0, 14.0)) * 0.14)
	_streams["boom"] = _make(0.7, 0.18, func(t, _d): return _noise() * 1.2 * exp(-t * 7.0) + _sweep(t, 110.0, 34.0, 9.0) * 0.9 * exp(-t * 5.0))
	_streams["dash"] = _make(0.24, 0.35, func(t, d): return _noise() * 0.7 * pow(sin(PI * t / d), 2.0))
	_streams["jump"] = _make(0.12, 1.0, func(t, _d): return _sweep(t, 300.0, 760.0, 22.0) * 0.4 * exp(-t * 22.0))
	_streams["land"] = _make(0.1, 0.2, func(t, _d): return (_sweep(t, 150.0, 70.0, 30.0) * 0.9 + _noise() * 0.3) * exp(-t * 40.0))
	_streams["step"] = _make(0.05, 0.15, func(t, _d): return (_noise() * 0.6 + sin(TAU * 120.0 * t) * 0.5) * exp(-t * 90.0))
	_streams["pad"] = _make(0.4, 1.0, func(t, _d): return sin(TAU * (260.0 * t + 900.0 * t * t) + sin(t * 70.0) * 0.6) * 0.5 * exp(-t * 7.0))
	_streams["reload"] = _make(0.26, 0.5, func(t, _d): return (_noise() * 0.6 * exp(-t * 160.0)) + (_noise() * 0.7 * exp(-(t - 0.17) * 140.0) if t > 0.17 else 0.0) + _bell(t - 0.17, 880.0, 60.0) * 0.12)
	_streams["block"] = _make(0.26, 1.0, func(t, _d): return (_bell(t, 880.0, 20.0) + _bell(t, 1320.0, 24.0)) * 0.3 + _noise() * 0.35 * exp(-t * 80.0))
	_streams["tick"] = _make(0.06, 1.0, func(t, _d): return _bell(t, 1245.0, 90.0) * 0.4)
	_streams["bounce"] = _make(0.1, 1.0, func(t, _d): return _sweep(t, 1500.0, 900.0, 40.0) * 0.35 * exp(-t * 45.0))
	_streams["card"] = _make(0.7, 1.0, func(t, _d): return (_bell(t, 523.0, 9.0) + _bell(t - 0.07, 659.0, 9.0) + _bell(t - 0.14, 784.0, 9.0) + _bell(t - 0.21, 1046.0, 7.0)) * 0.24)
	_streams["join"] = _make(0.45, 1.0, func(t, _d): return (_bell(t, 659.0, 10.0) + _bell(t - 0.09, 988.0, 9.0)) * 0.3)
	_streams["count"] = _make(0.3, 1.0, func(t, _d): return _bell(t, 660.0, 14.0) * 0.42)
	_streams["go"] = _make(0.8, 1.0, func(t, _d): return (_bell(t, 660.0, 5.0) + _bell(t, 990.0, 5.0) + _bell(t, 1320.0, 5.0)) * 0.22)
	_streams["win"] = _make(2.0, 1.0, func(t, _d): return (_bell(t, 523.0, 5.0) + _bell(t - 0.14, 659.0, 5.0) + _bell(t - 0.28, 784.0, 5.0) + _bell(t - 0.42, 1046.0, 3.0) + _bell(t - 0.7, 784.0, 5.0) + _bell(t - 0.84, 1046.0, 2.5) + _bell(t - 0.84, 1318.0, 2.5) + _bell(t - 0.84, 1568.0, 2.5)) * 0.2)


## Render fn(t, duration) to a WAV. `lp` (0..1] is a one-pole low-pass: lower
## values give a duller, softer sound.
func _make(duration: float, lp: float, fn: Callable) -> AudioStreamWAV:
	var count := int(duration * RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var y := 0.0
	var fade := int(0.006 * RATE)
	for i in count:
		var t := float(i) / RATE
		var x: float = fn.call(t, duration)
		y += (x - y) * lp
		var out := y * minf(1.0, float(count - i) / fade)
		data.encode_s16(i * 2, int(clampf(out, -1.0, 1.0) * 32000.0))
	return _wav(data)


func _wav(data: PackedByteArray) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav


# --------------------------------------------------------------------------
# Music (runs in a worker thread)
# --------------------------------------------------------------------------
# Eight bars in C major, 16 steps per bar. Each track is mixed into a float
# buffer whose length is exactly the loop length; note tails wrap around to
# the start, so the loop is seamless.

const CHORDS := {
	"C": [36, 60, 64, 67], "G": [31, 59, 62, 67], "Am": [33, 60, 64, 69], "F": [29, 60, 65, 69],
}
const PROGRESSION := ["C", "G", "Am", "F", "C", "G", "F", "G"]
## [step, midi note, length in steps] per bar.
const MELODY := [
	[[0, 76, 2], [2, 79, 2], [4, 84, 3], [8, 79, 2], [10, 76, 2], [12, 79, 4]],
	[[0, 74, 2], [2, 79, 2], [4, 83, 3], [8, 79, 2], [10, 74, 2], [12, 79, 4]],
	[[0, 76, 2], [2, 81, 2], [4, 84, 3], [8, 81, 2], [10, 76, 2], [12, 81, 4]],
	[[0, 77, 2], [2, 81, 2], [4, 84, 2], [6, 81, 2], [8, 79, 3], [12, 76, 2], [14, 74, 2]],
	[[0, 84, 3], [4, 79, 2], [6, 76, 2], [8, 79, 2], [10, 84, 2], [12, 88, 4]],
	[[0, 86, 3], [4, 83, 2], [6, 79, 2], [8, 83, 2], [10, 86, 2], [12, 79, 4]],
	[[0, 84, 2], [2, 81, 2], [4, 77, 2], [6, 81, 2], [8, 84, 3], [12, 81, 2], [14, 84, 2]],
	[[0, 83, 2], [2, 86, 2], [4, 79, 4], [8, 86, 2], [10, 83, 2], [12, 79, 2], [14, 83, 2]],
]


func _hz(midi: int) -> float:
	return 440.0 * pow(2.0, (midi - 69) / 12.0)


func _render_music() -> void:
	var lobby := _render_track(96.0, false)
	call_deferred("_track_ready", "lobby", lobby)
	var battle := _render_track(132.0, true)
	call_deferred("_track_ready", "battle", battle)


func _track_ready(track: String, data: PackedByteArray) -> void:
	var wav := _wav(data)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = data.size() / 2
	_tracks[track] = wav


func _render_track(bpm: float, battle: bool) -> PackedByteArray:
	var step := 60.0 / bpm / 4.0
	var n := int(step * 16.0 * 8.0 * RATE)
	var mix := PackedFloat32Array()
	mix.resize(n)
	var lead := PackedFloat32Array()
	lead.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7

	for bar in 8:
		var chord: Array = CHORDS[PROGRESSION[bar]]
		var t0 := bar * 16
		# Bass.
		for s in ([0, 3, 6, 8, 11, 14] if battle else [0, 8, 11]):
			_tone(mix, n, (t0 + s) * step, step * 2.6, _hz(chord[0] + 12), 0.34, 0, 9.0)
		# Chords: off-beat stabs in battle, slow arpeggio in the lobby.
		if battle:
			for s in [2, 6, 10, 14]:
				for k in 3:
					_tone(mix, n, (t0 + s) * step, step * 1.6, _hz(chord[1 + k]), 0.075, 1, 16.0)
		else:
			var arp := [1, 2, 3, 2, 1, 2, 3, 2]
			for i in 8:
				_tone(mix, n, (t0 + i * 2) * step, step * 3.5, _hz(chord[arp[i]]), 0.1, 2, 5.0)
		# Melody (the lobby plays a sparser version, an octave down).
		for note in MELODY[bar]:
			if not battle and note[2] < 3 and note[0] % 8 != 0:
				continue
			var midi: int = note[1] if battle else note[1] - 12
			_tone(lead, n, (t0 + note[0]) * step, step * (note[2] + 0.8), _hz(midi), 0.2 if battle else 0.17, 2, 5.5)
		# Drums.
		for s in 16:
			var at := (t0 + s) * step
			if battle:
				if s % 4 == 0:
					_kick(mix, n, at, 0.6)
				if s % 8 == 4:
					_snare(mix, n, at, 0.34, rng)
				if s % 2 == 0:
					_hat(mix, n, at, 0.1 if s % 4 == 2 else 0.05, rng)
			else:
				if s == 0 or s == 10:
					_kick(mix, n, at, 0.4)
				if s == 4 or s == 12:
					_snare(mix, n, at, 0.16, rng)
				if s % 4 == 2:
					_hat(mix, n, at, 0.05, rng)

	# Echo on the melody, then mix down with a soft clip.
	var delay := int(step * 3.0 * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var v := mix[i] + lead[i] + lead[(i - delay + n) % n] * 0.32 + lead[(i - delay * 2 + n * 2) % n] * 0.12
		data.encode_s16(i * 2, int(tanh(v * 1.25) * 30000.0))
	return data


## wave: 0 = triangle + sub sine (bass), 1 = soft pulse (stab), 2 = bell-ish sine stack.
func _tone(buf: PackedFloat32Array, n: int, start: float, length: float, freq: float, vol: float, wave: int, decay: float) -> void:
	var i0 := int(start * RATE)
	var count := int(length * RATE)
	var attack := 0.006 * RATE
	var release := 0.03 * RATE
	for i in count:
		var t := float(i) / RATE
		var ph := fmod(t * freq, 1.0)
		var x := 0.0
		match wave:
			0:
				x = (absf(ph * 4.0 - 2.0) - 1.0) * 0.8 + sin(TAU * freq * 0.5 * t) * 0.5
			1:
				x = sin(TAU * ph) + 0.33 * sin(TAU * 3.0 * ph) + 0.2 * sin(TAU * 5.0 * ph)
			_:
				var vib := sin(t * 34.0) * 0.004 * minf(1.0, t * 5.0)
				x = sin(TAU * freq * t * (1.0 + vib)) + 0.3 * sin(TAU * freq * 2.0 * t) + 0.1 * sin(TAU * freq * 3.0 * t)
		var env := exp(-t * decay) * minf(1.0, i / attack) * minf(1.0, (count - i) / release)
		buf[(i0 + i) % n] += x * env * vol


func _kick(buf: PackedFloat32Array, n: int, start: float, vol: float) -> void:
	var i0 := int(start * RATE)
	for i in int(0.16 * RATE):
		var t := float(i) / RATE
		buf[(i0 + i) % n] += sin(TAU * (48.0 * t + 110.0 / 30.0 * (1.0 - exp(-30.0 * t)))) * exp(-t * 20.0) * vol


func _snare(buf: PackedFloat32Array, n: int, start: float, vol: float, rng: RandomNumberGenerator) -> void:
	var i0 := int(start * RATE)
	var y := 0.0
	for i in int(0.13 * RATE):
		var t := float(i) / RATE
		y += (rng.randf_range(-1.0, 1.0) - y) * 0.7
		buf[(i0 + i) % n] += (y * 0.8 + sin(TAU * 190.0 * t) * 0.4) * exp(-t * 26.0) * vol


func _hat(buf: PackedFloat32Array, n: int, start: float, vol: float, rng: RandomNumberGenerator) -> void:
	var i0 := int(start * RATE)
	var prev := 0.0
	for i in int(0.035 * RATE):
		var t := float(i) / RATE
		var x := rng.randf_range(-1.0, 1.0)
		buf[(i0 + i) % n] += (x - prev) * exp(-t * 110.0) * vol
		prev = x
