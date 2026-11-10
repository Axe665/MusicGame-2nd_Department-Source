class_name AudioClock
extends RefCounted

## Wall-clock driven song time with a bounded drift correction from the audio
## hardware clock. The correction is slow on purpose: a single bad playback
## position (VBR MP3, device switch, mix hiccup) must never move the song clock
## by a visible amount, and it must recover instead of latching forward.
const MAX_JUMP_MS := 220.0
const CORRECTION_RATE := 0.08
const MAX_CORRECTION_MS := 2.5
## A positive error up to this size is treated as a clock lag (hitch), not a
## bad playback sample, and is caught up without a visible jump.
const MAX_CATCHUP_ERROR_MS := 600.0
const MAX_CATCHUP_MS := 8.0
const MAX_HITCH_MS := 1000.0
const MAX_LATENCY_SEC := 0.25
const MAX_MIX_SEC := 0.25
const MAX_START_DELAY_MS := 250.0

var clock_ms := -INF
var _last_usec := 0
var _started := false

## `start_delay_ms` is the time between calling play() and the first audible
## sample (next mix + output latency). The clock starts that much behind the
## requested chart time so the first notes line up with what is heard.
func start(at_ms: float, now_usec: int, start_delay_ms := 0.0) -> void:
	clock_ms = at_ms - clampf(start_delay_ms, 0.0, MAX_START_DELAY_MS)
	_last_usec = now_usec
	_started = true

func resume(now_usec: int) -> void:
	_last_usec = now_usec

func update(now_usec: int, audio_playing: bool, playback_sec: float, chart_offset_ms: float,
		latency_sec: float, mix_sec: float) -> float:
	if not _started:
		return 0.0
	# A long main-thread hitch must not teleport the song; the audio clock will
	# catch up gradually through the correction below.
	var dt := clampf(float(now_usec - _last_usec) / 1000.0, 0.0, MAX_HITCH_MS)
	_last_usec = now_usec
	var wall := clock_ms + dt
	if audio_playing:
		var latency := clampf(latency_sec, 0.0, MAX_LATENCY_SEC)
		var mix := clampf(mix_sec, 0.0, MAX_MIX_SEC)
		var audio_ms := (playback_sec + mix - latency) * 1000.0 + chart_offset_ms
		var error := audio_ms - wall
		# Scale by elapsed time: mouse events can call this many times per frame,
		# and a fixed per-call correction would run the clock ahead.
		var scale := clampf(dt / 16.0, 0.0, 4.0)
		if absf(error) <= MAX_JUMP_MS:
			wall += clampf(error * CORRECTION_RATE * scale, -MAX_CORRECTION_MS, MAX_CORRECTION_MS)
		elif error > MAX_JUMP_MS and error <= MAX_CATCHUP_ERROR_MS:
			wall += minf(error, MAX_CATCHUP_MS * scale)
		elif error < -MAX_JUMP_MS and error >= -MAX_CATCHUP_ERROR_MS:
			# The clock is ahead: run it slightly slower until the audio catches up.
			wall -= minf(-error, MAX_CATCHUP_MS * scale)
	if is_finite(wall):
		clock_ms = wall
	return clock_ms
