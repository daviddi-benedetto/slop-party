extends Node
## Autoload "Sfx": all audio. Nothing is loaded from disk - sound effects are
## synthesised at startup and the music is composed and rendered in a
## background thread (so startup is not delayed; a track fades in when ready).
##
## play(name)            UI / personal feedback, always full volume.
## play_at(name, pos)    world sounds. Volume falls off with the distance to
##                       the nearest entry of `listeners` (game.gd keeps that
##                       list filled with the human players' positions). With
##                       several players on one screen there is no stereo pan.
## music(name)           a key of TRACKS ("lobby", "map0".."map5", "zombies",
##                       "frontline") or
##                       "" - cross-fades. A track that is not rendered yet
##                       jumps the queue and starts as soon as it is done.
##
## Music: every track is an 8-bar loop described by a TRACKS entry (tempo,
## four 2-bar chords, and a style for bass, chords, lead and drums) and
## rendered by _render_track with a few small synth voices: filtered saw bass,
## plucked arpeggio, detuned-saw pad, pulse lead with echo, and drums, plus
## side-chain "pumping" on the pad. Bars 1-4 are the groove alone; the lead
## joins for bars 5-8. To add a song, add a TRACKS entry.
##
## Volumes come from Settings ("sfx", "music"; master is the audio bus).

const RATE := 22050
const VOICES := 24

## chords: [bass note, then chord tones] as MIDI numbers; each lasts two bars.
const TRACKS := {
	# Laid-back funk for the lobby.
	"lobby": {"bpm": 100.0, "bass": "funk", "keys": "stab", "drums": "funk", "lead": 0.0, "pad": 0.0, "lead_shift": 0,
		"chords": [[33, 57, 60, 64, 67], [29, 57, 60, 64, 65], [36, 55, 60, 64, 67], [31, 55, 59, 62, 67]]},
	# Neon Yard: driving synthwave.
	"map0": {"bpm": 112.0, "bass": "drive", "keys": "arp", "drums": "four", "lead": 0.2, "pad": 0.05, "lead_shift": 0,
		"chords": [[38, 57, 62, 65, 69], [34, 58, 62, 65, 70], [29, 57, 60, 65, 69], [36, 55, 60, 64, 67]]},
	# Ember Pit: fast and aggressive.
	"map1": {"bpm": 132.0, "bass": "pump", "keys": "stab", "drums": "hard", "lead": 0.2, "pad": 0.0, "lead_shift": 3,
		"chords": [[28, 59, 64, 67, 71], [29, 60, 65, 69, 72], [28, 59, 64, 67, 71], [26, 57, 62, 66, 69]]},
	# Frost Line: spacious half-time funk with bells.
	"map2": {"bpm": 96.0, "bass": "slap", "keys": "bell", "drums": "half", "lead": 0.17, "pad": 0.055, "lead_shift": 5,
		"chords": [[30, 57, 61, 66, 69], [26, 57, 62, 66, 69], [33, 57, 61, 64, 69], [28, 56, 59, 64, 68]]},
	# Museum: smooth late-night funk with bells.
	"map3": {"bpm": 104.0, "bass": "funk", "keys": "bell", "drums": "funk", "lead": 0.16, "pad": 0.05, "lead_shift": 7,
		"chords": [[29, 57, 60, 64, 67], [31, 58, 62, 65, 69], [33, 57, 60, 64, 67], [28, 56, 59, 62, 67]]},
	# Stadium: big four-on-the-floor anthem.
	"map4": {"bpm": 124.0, "bass": "pump", "keys": "arp", "drums": "four", "lead": 0.2, "pad": 0.06, "lead_shift": 0,
		"chords": [[36, 60, 64, 67, 72], [31, 59, 62, 67, 71], [33, 57, 60, 64, 69], [29, 57, 60, 65, 69]]},
	# Suburb: sunny slap-bass groove.
	"map5": {"bpm": 108.0, "bass": "slap", "keys": "stab", "drums": "funk", "lead": 0.17, "pad": 0.0, "lead_shift": 5,
		"chords": [[31, 59, 62, 66, 69], [36, 60, 64, 67, 71], [28, 59, 62, 67, 71], [33, 57, 61, 64, 69]]},
	# Zombies: dark, tense half-time.
	"zombies": {"bpm": 92.0, "bass": "pump", "keys": "bell", "drums": "half", "lead": 0.12, "pad": 0.07, "lead_shift": 3,
		"chords": [[28, 55, 59, 64, 67], [24, 55, 60, 64, 67], [26, 57, 62, 65, 69], [23, 54, 59, 62, 66]]},
	# Frontline: driving battle synthwave.
	"frontline": {"bpm": 122.0, "bass": "drive", "keys": "arp", "drums": "hard", "lead": 0.2, "pad": 0.06, "lead_shift": 0,
		"chords": [[26, 57, 62, 65, 69], [22, 58, 62, 65, 70], [24, 55, 60, 64, 67], [21, 57, 61, 64, 69]]},
}

var listeners: Array = []          # Vector3 world positions of human players

var _streams := {}
var _players: Array = []
var _next := 0
var _music_player: AudioStreamPlayer
var _tracks := {}
var _want_music := ""
var _playing_music := ""
var _thread: Thread
var _mutex := Mutex.new()
var _priority := ""
var _quit := false
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
	_mutex.lock()
	_quit = true
	_mutex.unlock()
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
	_mutex.lock()
	_priority = track
	_mutex.unlock()


func duck(on: bool) -> void:
	_duck = 10.0 if on else 0.0


func _process(delta: float) -> void:
	var level: int = Settings.v("music")
	var target := -60.0
	if _want_music == _playing_music and _playing_music != "" and level > 0:
		target = -13.0 + linear_to_db(level / 6.0) - _duck
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
	# One shot sound per weapon style (player.gd plays "shot_" + style).
	_streams["shot_blaster"] = _streams["shoot"]
	_streams["shot_scatter"] = _make(0.38, 0.35, func(t, _d): return (_noise() * 1.1 * exp(-t * 16.0) + _sweep(t, 240.0, 55.0, 14.0) * 0.9 * exp(-t * 9.0)))
	_streams["shot_zapper"] = _make(0.1, 0.9, func(t, _d): return (_sweep(t, 2600.0, 700.0, 50.0) * 0.5 + (1.0 if fmod(t * 1900.0, 1.0) < 0.5 else -1.0) * 0.15) * exp(-t * 34.0))
	_streams["shot_boomer"] = _make(0.5, 0.3, func(t, _d): return _noise() * 0.6 * sin(PI * minf(t / 0.45, 1.0)) * exp(-t * 3.0) + _sweep(t, 120.0, 45.0, 10.0) * 0.8 * exp(-t * 12.0))
	_streams["shot_rail"] = _make(0.6, 0.8, func(t, _d): return _sweep(t, 4200.0, 240.0, 9.0) * 0.45 * exp(-t * 6.0) + _bell(t, 1760.0, 7.0) * 0.18 + (_noise() * 0.5 if t < 0.02 else 0.0))
	_streams["shot_lobber"] = _make(0.28, 0.4, func(t, _d): return _sweep(t, 180.0, 85.0, 18.0) * 0.9 * exp(-t * 13.0) + (_noise() * 0.4 if t < 0.015 else 0.0))
	_streams["shot_bubbler"] = _make(0.18, 0.7, func(t, _d): return sin(TAU * (300.0 * t + 1700.0 * t * t) + sin(t * 140.0) * 0.8) * 0.45 * exp(-t * 14.0))
	_streams["shot_burst"] = _make(0.09, 0.6, func(t, _d): return (_noise() * 0.6 * exp(-t * 70.0) + _sweep(t, 1200.0, 420.0, 40.0) * 0.45) * exp(-t * 30.0))
	_streams["shot_magnum"] = _make(0.6, 0.3, func(t, _d): return _noise() * 1.2 * exp(-t * 22.0) + _sweep(t, 160.0, 48.0, 8.0) * 1.0 * exp(-t * 7.0) + _noise() * 0.12 * exp(-t * 3.0))
	_streams["shot_spinner"] = _make(0.07, 0.5, func(t, _d): return ((1.0 if fmod(t * 150.0, 1.0) < 0.5 else -1.0) * 0.4 + _noise() * 0.5) * exp(-t * 40.0))
	_streams["shot_pinball"] = _make(0.2, 0.9, func(t, _d): return sin(TAU * (600.0 * t + 1500.0 * t * t) + sin(t * 90.0) * 2.0) * 0.4 * exp(-t * 12.0))
	_streams["shot_flamer"] = _make(0.14, 0.2, func(t, d): return _noise() * 0.8 * sin(PI * t / d))
	# Extra layers for bullet effects.
	_streams["mod_boom"] = _make(0.3, 0.2, func(t, _d): return _sweep(t, 90.0, 40.0, 10.0) * 0.9 * exp(-t * 10.0))
	_streams["mod_ice"] = _make(0.3, 1.0, func(t, _d): return (_bell(t, 2637.0, 12.0) + _bell(t - 0.04, 3520.0, 14.0)) * 0.25)
	_streams["mod_toxic"] = _make(0.25, 0.6, func(t, _d): return sin(TAU * 220.0 * t + sin(t * 180.0) * 4.0) * 0.35 * exp(-t * 10.0))
	_streams["mod_seek"] = _make(0.2, 1.0, func(t, _d): return _sweep(t, 900.0, 2400.0, 12.0) * 0.3 * exp(-t * 9.0))
	_streams["mod_pierce"] = _make(0.35, 1.0, func(t, _d): return _bell(t, 1318.0, 8.0) * 0.3)
	# Movement and weather.
	_streams["slide"] = _make(0.45, 0.3, func(t, d): return _noise() * 0.5 * sin(PI * t / d))
	_streams["jet"] = _make(0.16, 0.25, func(t, d): return _noise() * 0.7 * sin(PI * t / d))
	# Zombies and vehicles.
	_streams["zombie"] = _make(0.9, 0.12, func(t, d): return (sin(TAU * (95.0 + 25.0 * sin(t * 9.0)) * t) * 0.6 + _noise() * 0.35) * sin(PI * t / d) * (0.7 + 0.3 * sin(t * 31.0)))
	_streams["engine"] = _make(0.3, 0.2, func(t, d): return ((1.0 if fmod(t * 55.0, 1.0) < 0.35 else -0.6) * 0.4 + _noise() * 0.25) * sin(PI * t / d))
	_streams["rotor"] = _make(0.3, 0.15, func(t, d): return _noise() * (0.3 + 0.6 * pow(absf(sin(PI * t * 13.0)), 6.0)) * sin(PI * t / d))
	_streams["cannon"] = _make(0.9, 0.15, func(t, _d): return _noise() * 1.4 * exp(-t * 9.0) + _sweep(t, 90.0, 30.0, 6.0) * 1.0 * exp(-t * 4.0))
	_streams["capture"] = _make(0.8, 1.0, func(t, _d): return (_bell(t, 784.0, 6.0) + _bell(t - 0.1, 988.0, 6.0) + _bell(t - 0.2, 1175.0, 5.0)) * 0.25)
	_streams["lost"] = _make(0.8, 1.0, func(t, _d): return (_bell(t, 659.0, 6.0) + _bell(t - 0.12, 523.0, 6.0) + _bell(t - 0.24, 415.0, 5.0)) * 0.25)
	_streams["wave"] = _make(1.6, 0.5, func(t, _d): return (sin(TAU * 110.0 * t) + 0.5 * sin(TAU * 116.0 * t) + 0.3 * sin(TAU * 165.0 * t)) * 0.35 * minf(t * 4.0, 1.0) * exp(-t * 1.6))
	_streams["thunder"] = _make(2.2, 0.06, func(t, _d): return _noise() * (1.4 * exp(-t * 2.2) + 0.5 * exp(-absf(t - 0.6) * 4.0)))
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
# Music (everything below runs in the worker thread)
# --------------------------------------------------------------------------

func _hz(midi: int) -> float:
	return 440.0 * pow(2.0, (midi - 69) / 12.0)


func _render_music() -> void:
	var pending: Array = TRACKS.keys()
	while not pending.is_empty():
		_mutex.lock()
		var stop := _quit
		var want := _priority
		_mutex.unlock()
		if stop:
			return
		var track: String = want if pending.has(want) else pending[0]
		pending.erase(track)
		var data := _render_track(TRACKS[track])
		call_deferred("_track_ready", track, data)


func _track_ready(track: String, data: PackedByteArray) -> void:
	var wav := _wav(data)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = data.size() / 2
	_tracks[track] = wav


## Eight bars, 16 steps per bar. Each voice is mixed into a float buffer whose
## length is exactly the loop length; note tails wrap around to the start, so
## the loop is seamless.
func _render_track(tr: Dictionary) -> PackedByteArray:
	var step: float = 60.0 / tr.bpm / 4.0
	var beat := step * 4.0
	var n := int(step * 16.0 * 8.0 * RATE)
	var drums := PackedFloat32Array()
	drums.resize(n)
	var bass := PackedFloat32Array()
	bass.resize(n)
	var keys := PackedFloat32Array()      # chords / arps / pad: side-chained to the kick
	keys.resize(n)
	var lead := PackedFloat32Array()      # gets an echo
	lead.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7

	for bar in 8:
		var chord: Array = tr.chords[bar / 2]
		var t0 := bar * 16
		var b := bar >= 4                 # second half: fuller arrangement
		var root: int = chord[0]

		# --- bass ---
		match tr.bass:
			"funk":
				for hit in [[0, 0, 2.2], [3, 0, 1.0], [6, 12, 0.8], [7, 0, 1.4], [10, 0, 1.0], [12, 7, 1.2], [14, 12, 0.8], [15, 10, 0.8]]:
					_bass(bass, n, (t0 + hit[0]) * step, step * hit[2], _hz(root + hit[1]), 0.42, 16.0)
			"drive":
				for s in range(0, 16, 2):
					_bass(bass, n, (t0 + s) * step, step * 1.7, _hz(root + (12 if s == 6 or s == 14 else 0)), 0.4, 9.0)
			"pump":
				for s in 16:
					var up := 12 if (s == 7 or s == 15 or (b and s == 11)) else 0
					_bass(bass, n, (t0 + s) * step, step * 0.9, _hz(root + up), 0.36 if s % 4 == 0 else 0.26, 22.0)
			"slap":
				for hit in [[0, 0, 3.0], [3, 12, 0.7], [4, 0, 1.6], [7, 7, 0.9], [10, 0, 1.2], [11, 12, 0.7], [14, 10, 1.4]]:
					_bass(bass, n, (t0 + hit[0]) * step, step * hit[2], _hz(root + hit[1]), 0.44, 13.0)

		# --- chords ---
		match tr.keys:
			"stab":
				for s in ([2, 6, 10, 14] if not b else [2, 5, 6, 10, 13, 14]):
					for k in range(1, 5):
						_pluck(keys, n, (t0 + s) * step, step * 1.3, _hz(chord[k]), 0.07, 20.0)
			"arp":
				var order := [1, 2, 3, 4, 3, 2, 1, 3]
				for s in 16:
					var note: int = chord[order[s % 8]] + (12 if b and s % 4 == 3 else 0)
					_pluck(keys, n, (t0 + s) * step, step * 1.8, _hz(note), 0.09, 13.0)
			"bell":
				var order2 := [1, 3, 2, 4, 3, 1, 4, 2]
				for i in 8:
					_tone(keys, n, (t0 + i * 2) * step, step * 5.0, _hz(chord[order2[i]] + 12), 0.075, 4.5)
		if tr.pad > 0.0 and bar % 2 == 0:
			for k in range(1, 5):
				_pad(keys, n, t0 * step, step * 32.0, _hz(chord[k]), tr.pad)

		# --- lead: a two-bar phrase per chord, second half only ---
		if b and tr.lead > 0.0 and bar % 2 == 0:
			var rhythm := [0, 3, 6, 8, 12, 14, 16, 19, 22, 24, 28]
			var shape := [3, 2, 1, 2, 3, 4, 3, 2, 1, 3, 2]
			var shift: int = tr.lead_shift + bar
			for i in rhythm.size():
				var tone: int = chord[1 + (shape[(i + shift) % shape.size()] - 1)] + 12
				var length := 2.6 if i % 3 != 2 else 3.6
				_lead(lead, n, (t0 + rhythm[i]) * step, step * length, _hz(tone), tr.lead)

		# --- drums ---
		for s in 16:
			var at := (t0 + s) * step
			match tr.drums:
				"funk":
					if s == 0 or s == 7 or s == 10:
						_kick(drums, n, at, 0.55)
					if s == 4 or s == 12:
						_snare(drums, n, at, 0.3, rng)
					_hat(drums, n, at, 0.085 if s % 4 == 2 else 0.04, 0.035, rng)
					if b and s == 14:
						_hat(drums, n, at, 0.09, 0.2, rng)
				"four":
					if s % 4 == 0:
						_kick(drums, n, at, 0.62)
					if s == 4 or s == 12:
						_snare(drums, n, at, 0.34, rng)
					if s % 4 == 2:
						_hat(drums, n, at, 0.1, 0.16, rng)
					elif b:
						_hat(drums, n, at, 0.035, 0.03, rng)
				"hard":
					if s % 4 == 0 or s == 14 or (b and s == 11):
						_kick(drums, n, at, 0.66)
					if s == 4 or s == 12:
						_snare(drums, n, at, 0.4, rng)
					_hat(drums, n, at, 0.09 if s % 2 == 0 else 0.045, 0.03, rng)
					if s % 4 == 2:
						_hat(drums, n, at, 0.07, 0.14, rng)
				"half":
					if s == 0 or s == 6 or (b and s == 10):
						_kick(drums, n, at, 0.6)
					if s == 8:
						_snare(drums, n, at, 0.38, rng)
					if s % 2 == 0:
						_hat(drums, n, at, 0.07 if s % 4 == 0 else 0.04, 0.04, rng)
					if s == 14:
						_hat(drums, n, at, 0.06, 0.22, rng)

	# Mix down: side-chain pump on the keys, echo on the lead, soft clip.
	var delay := int(step * 3.0 * RATE)
	var pump: float = 0.55 if tr.drums == "four" or tr.drums == "hard" else 0.25
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var phase := fmod(float(i) / RATE, beat)
		var duck_gain := 1.0 - pump * exp(-phase * 9.0)
		var v := drums[i] + bass[i] * (0.75 + 0.25 * duck_gain) + keys[i] * duck_gain
		v += lead[i] + lead[(i - delay + n) % n] * 0.34 + lead[(i - delay * 2 + n * 2) % n] * 0.13
		data.encode_s16(i * 2, int(tanh(v * 1.2) * 30000.0))
	return data


## Saw bass through a low-pass whose cutoff snaps shut: the "wow" of a synth bass.
func _bass(buf: PackedFloat32Array, n: int, start: float, length: float, freq: float, vol: float, snap: float) -> void:
	var i0 := int(start * RATE)
	var count := int(length * RATE)
	var y := 0.0
	var inc := freq / RATE
	var ph := 0.0
	var release := 0.02 * RATE
	for i in count:
		var t := float(i) / RATE
		ph += inc
		if ph >= 1.0:
			ph -= 1.0
		var x := (ph * 2.0 - 1.0) + sin(TAU * ph * 0.5) * 0.6
		y += (x - y) * (0.06 + 0.5 * exp(-t * snap))
		buf[(i0 + i) % n] += y * vol * minf(1.0, i / 60.0) * minf(1.0, (count - i) / release)


## Short plucked saw: arpeggios and chord stabs.
func _pluck(buf: PackedFloat32Array, n: int, start: float, length: float, freq: float, vol: float, decay: float) -> void:
	var i0 := int(start * RATE)
	var count := int(length * RATE)
	var y := 0.0
	var inc := freq / RATE
	var ph := 0.0
	for i in count:
		var t := float(i) / RATE
		ph += inc
		if ph >= 1.0:
			ph -= 1.0
		y += ((ph * 2.0 - 1.0) - y) * (0.1 + 0.6 * exp(-t * decay))
		buf[(i0 + i) % n] += y * vol * exp(-t * decay * 0.5) * minf(1.0, i / 40.0)


## Two detuned saws, heavily filtered, with a slow fade in and out.
func _pad(buf: PackedFloat32Array, n: int, start: float, length: float, freq: float, vol: float) -> void:
	var i0 := int(start * RATE)
	var count := int(length * RATE)
	var y := 0.0
	var inc_a := freq * 0.996 / RATE
	var inc_b := freq * 1.005 / RATE
	var pa := 0.0
	var pb := 0.37
	var edge := 0.35 * RATE
	for i in count:
		pa += inc_a
		if pa >= 1.0:
			pa -= 1.0
		pb += inc_b
		if pb >= 1.0:
			pb -= 1.0
		y += ((pa + pb - 1.0) - y) * 0.11
		buf[(i0 + i) % n] += y * vol * minf(1.0, i / edge) * minf(1.0, (count - i) / edge)


## Pulse-wave lead with vibrato.
func _lead(buf: PackedFloat32Array, n: int, start: float, length: float, freq: float, vol: float) -> void:
	var i0 := int(start * RATE)
	var count := int(length * RATE)
	var y := 0.0
	var ph := 0.0
	var release := 0.05 * RATE
	for i in count:
		var t := float(i) / RATE
		ph += freq * (1.0 + sin(t * 36.0) * 0.006 * minf(1.0, t * 6.0)) / RATE
		if ph >= 1.0:
			ph -= 1.0
		var x := (1.0 if ph < 0.3 else -0.55) + sin(TAU * ph) * 0.4
		y += (x - y) * 0.32
		buf[(i0 + i) % n] += y * vol * minf(1.0, i / 90.0) * minf(1.0, (count - i) / release) * (0.6 + 0.4 * exp(-t * 5.0))


## Bell-like sine stack.
func _tone(buf: PackedFloat32Array, n: int, start: float, length: float, freq: float, vol: float, decay: float) -> void:
	var i0 := int(start * RATE)
	var count := int(length * RATE)
	var release := 0.03 * RATE
	for i in count:
		var t := float(i) / RATE
		var x := sin(TAU * freq * t) + 0.3 * sin(TAU * freq * 2.0 * t) + 0.12 * sin(TAU * freq * 3.01 * t)
		buf[(i0 + i) % n] += x * exp(-t * decay) * minf(1.0, i / 100.0) * minf(1.0, (count - i) / release) * vol


func _kick(buf: PackedFloat32Array, n: int, start: float, vol: float) -> void:
	var i0 := int(start * RATE)
	for i in int(0.17 * RATE):
		var t := float(i) / RATE
		buf[(i0 + i) % n] += sin(TAU * (46.0 * t + 120.0 / 32.0 * (1.0 - exp(-32.0 * t)))) * exp(-t * 19.0) * vol


func _snare(buf: PackedFloat32Array, n: int, start: float, vol: float, rng: RandomNumberGenerator) -> void:
	var i0 := int(start * RATE)
	var y := 0.0
	for i in int(0.16 * RATE):
		var t := float(i) / RATE
		y += (rng.randf_range(-1.0, 1.0) - y) * 0.7
		buf[(i0 + i) % n] += (y * 0.85 + sin(TAU * 185.0 * t) * 0.4) * exp(-t * 22.0) * vol


## `length` in seconds: ~0.03 closed, ~0.2 open.
func _hat(buf: PackedFloat32Array, n: int, start: float, vol: float, length: float, rng: RandomNumberGenerator) -> void:
	var i0 := int(start * RATE)
	var prev := 0.0
	var decay := 3.5 / length
	for i in int(length * RATE):
		var t := float(i) / RATE
		var x := rng.randf_range(-1.0, 1.0)
		buf[(i0 + i) % n] += (x - prev) * exp(-t * decay) * vol
		prev = x
