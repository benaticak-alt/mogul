extends Node
## Audio. Everything is synthesised at boot - a register, a coin, a chime -
## so the project has no asset folder to lose and no import step.

const RATE := 22050.0
const VOICES := 16

var _players: Array[AudioStreamPlayer] = []
var _next: int = 0
var _bank: Dictionary = {}
var muted: bool = false
var volume: float = 0.8

func _ready() -> void:
	for i in range(VOICES):
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)
	_build_bank()

func _build_bank() -> void:
	# The register. Two short bright partials and a little mechanical thunk
	# under them: the sound the player hears ten thousand times, so it is
	# short and it does not ring.
	_bank["sale"]     = _register()
	_bank["sale_big"] = _chord([1046.0, 1568.0, 2093.0], 0.16, 0.22, 1.6)
	# A coin landing in the till.
	_bank["coin"]     = _tone(2200.0, 0.045, 0.09, "sine", 3.0)
	# Progression.
	_bank["buy"]      = _tone(330.0, 0.06, 0.22, "square", 0.9)
	_bank["buy_big"]  = _chord([392.0, 588.0, 784.0], 0.22, 0.20, 1.3)
	_bank["upgrade"]  = _chord([523.0, 784.0, 1046.0], 0.40, 0.24, 1.1)
	_bank["unlock"]   = _chord([440.0, 660.0, 880.0, 1320.0], 0.55, 0.24, 0.9)
	_bank["vip"]      = _chord([784.0, 988.0, 1175.0, 1568.0], 0.70, 0.22, 0.8)
	_bank["windfall"] = _sweep(400.0, 1800.0, 0.55, 0.28)
	_bank["rush"]     = _sweep(200.0, 1400.0, 0.80, 0.30)
	_bank["cashout"]  = _sweep(900.0, 90.0, 1.40, 0.36)
	_bank["legacy"]   = _chord([349.0, 523.0, 698.0, 1047.0], 0.95, 0.24, 0.8)
	_bank["node"]     = _chord([659.0, 988.0, 1319.0], 0.35, 0.22, 1.2)
	_bank["deny"]     = _tone(140.0, 0.11, 0.18, "square", 0.7)
	# UI.
	_bank["hover"]    = _tone(1500.0, 0.028, 0.10, "sine", 2.4)
	_bank["click"]    = _chord([950.0, 1420.0], 0.05, 0.16, 2.1)
	_bank["tab"]      = _tone(680.0, 0.065, 0.16, "sine", 1.8)

func play(sound: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if muted or not _bank.has(sound):
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _bank[sound]
	p.pitch_scale = clampf(pitch, 0.25, 4.0)
	p.volume_db = volume_db + linear_to_db(maxf(volume, 0.0001))
	p.play()

var _sale_streak: int = 0
var _sale_last_msec: int = 0

## A manual sale. Fast consecutive clicks climb a step at a time and the run
## resets after a short pause, so a burst of clicking reads as a rising run
## rather than one blip repeated forty times.
func sale(volume_db: float = 0.0) -> void:
	var now := Time.get_ticks_msec()
	if now - _sale_last_msec > 380:
		_sale_streak = 0
	_sale_last_msec = now
	_sale_streak = mini(_sale_streak + 1, 12)
	var pitch := pow(2.0, float(_sale_streak) / 14.0)
	play("sale", pitch, volume_db)

# ---------------------------------------------------------------- synthesis

func _stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in range(samples.size()):
		var v := int(clampf(samples[i], -1.0, 1.0) * 32000.0)
		bytes.encode_s16(i * 2, v)
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = int(RATE)
	s.stereo = false
	s.data = bytes
	return s

## Exponential decay with a short attack, so nothing clicks on start.
func _env(i: int, n: int, decay: float) -> float:
	var t := float(i) / float(n)
	var attack := minf(1.0, float(i) / maxf(1.0, RATE * 0.004))
	return attack * pow(1.0 - t, decay * 4.0)

func _wave(shape: String, phase: float) -> float:
	match shape:
		"square":
			return 1.0 if fmod(phase, TAU) < PI else -1.0
		"saw":
			return (fmod(phase, TAU) / PI) - 1.0
		_:
			return sin(phase)

func _tone(freq: float, dur: float, vol: float, shape: String = "sine", decay: float = 1.0) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in range(n):
		var phase := TAU * freq * (float(i) / RATE)
		out[i] = _wave(shape, phase) * _env(i, n, decay) * vol
	return _stream(out)

func _chord(freqs: Array, dur: float, vol: float, decay: float = 1.0) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in range(n):
		var v := 0.0
		for f in freqs:
			v += sin(TAU * float(f) * (float(i) / RATE))
		out[i] = (v / float(freqs.size())) * _env(i, n, decay) * vol
	return _stream(out)

func _sweep(f0: float, f1: float, dur: float, vol: float) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in range(n):
		var t := float(i) / float(n)
		var f: float = lerpf(f0, f1, t * t)
		phase += TAU * f / RATE
		out[i] = sin(phase) * _env(i, n, 0.9) * vol
	return _stream(out)

## A cash register: a bright two-partial ding with a dull mechanical thunk a
## few milliseconds ahead of it, which is what makes it a machine and not a
## bell.
func _register() -> AudioStreamWAV:
	var dur := 0.11
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var last := 0.0
	for i in range(n):
		var t := float(i) / float(n)
		var ts := float(i) / RATE
		last = lerpf(last, randf() * 2.0 - 1.0, 0.35)
		var thunk := last * pow(1.0 - t, 18.0) * 0.55
		var ding := (sin(TAU * 1760.0 * ts) + 0.6 * sin(TAU * 2637.0 * ts)) * pow(1.0 - t, 5.0) * 0.28
		out[i] = (thunk + ding) * minf(1.0, float(i) / (RATE * 0.002))
	return _stream(out)
