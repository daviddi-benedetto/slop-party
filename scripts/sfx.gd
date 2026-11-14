extends Node
## Autoload. All sound effects are synthesised at startup, so the project
## ships with no audio assets.

const RATE := 22050
const VOICES := 20

var _streams := {}
var _players: Array = []
var _next := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_streams["shoot"] = _make(0.13, func(t, d): return (_noise() * 0.6 + _square(t, 170.0 - 600.0 * t) * 0.5) * _decay(t, d, 2.2))
	_streams["hit"] = _make(0.06, func(t, d): return _square(t, 1250.0) * 0.45 * _decay(t, d, 1.5))
	_streams["hurt"] = _make(0.12, func(t, d): return (_noise() * 0.35 + sin(TAU * 130.0 * t) * 0.7) * _decay(t, d, 1.5))
	_streams["death"] = _make(0.5, func(t, d): return _square(t, 420.0 - 620.0 * t) * 0.5 * _decay(t, d, 1.2))
	_streams["boom"] = _make(0.55, func(t, d): return (_noise() * 0.8 + sin(TAU * (75.0 - 60.0 * t) * t) * 0.8) * _decay(t, d, 2.5))
	_streams["dash"] = _make(0.2, func(t, d): return _noise() * 0.4 * sin(PI * t / d))
	_streams["jump"] = _make(0.1, func(t, d): return sin(TAU * (240.0 + 1400.0 * t) * t) * 0.35 * _decay(t, d, 1.0))
	_streams["pad"] = _make(0.3, func(t, d): return sin(TAU * (200.0 + 1200.0 * t) * t) * 0.5 * _decay(t, d, 1.0))
	_streams["reload"] = _make(0.22, func(t, d): return _noise() * 0.5 * (1.0 if (t < 0.03 or (t > 0.15 and t < 0.19)) else 0.0))
	_streams["tick"] = _make(0.03, func(t, d): return _square(t, 800.0) * 0.3 * _decay(t, d, 1.0))
	_streams["bounce"] = _make(0.05, func(t, d): return sin(TAU * 900.0 * t) * 0.3 * _decay(t, d, 1.0))
	_streams["card"] = _make(0.36, func(t, d): return _square(t, [523.0, 659.0, 784.0, 1046.0][mini(3, int(t / 0.09))]) * 0.32 * _decay(fmod(t, 0.09), 0.09, 0.6))
	_streams["join"] = _make(0.18, func(t, d): return _square(t, [440.0, 660.0][mini(1, int(t / 0.09))]) * 0.3 * _decay(t, d, 0.8))
	_streams["win"] = _make(1.1, func(t, d): return _square(t, [392.0, 523.0, 659.0, 784.0, 1046.0, 1046.0][mini(5, int(t / 0.16))]) * 0.32 * _decay(t, d, 0.5))


func play(sound: String, volume_db := 0.0, pitch := 1.0) -> void:
	if not _streams.has(sound):
		return
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = _streams[sound]
	p.volume_db = volume_db - 6.0
	p.pitch_scale = pitch * randf_range(0.96, 1.04)
	p.play()


func _noise() -> float:
	return randf() * 2.0 - 1.0


func _square(t: float, freq: float) -> float:
	return 1.0 if fmod(t * freq, 1.0) < 0.5 else -1.0


func _decay(t: float, d: float, power: float) -> float:
	return pow(clampf(1.0 - t / d, 0.0, 1.0), power)


func _make(duration: float, fn: Callable) -> AudioStreamWAV:
	var count := int(duration * RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var t := float(i) / RATE
		var v: float = clampf(fn.call(t, duration), -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav
