class_name BpmDetect
extends RefCounted

## Estimates the base BPM and the first-beat offset of a song from its PCM.
##
## This is a behaviour-compatible rewrite of the "import a song, get a BPM and
## offset" flow of the Malody 4.3.7 editor, not a port of its code: that client
## is a Cocos2d-x C++ binary whose auto-timing routine has no readable source.
## The pipeline is the usual one for charting tools:
##
##   1. Onset envelope at ~100 frames/s from three one-pole bands
##      (low <120 Hz, mid, high >2.5 kHz), log-energy flux per band, summed.
##   2. Normalised autocorrelation of the envelope -> a coarse beat period.
##   3. Comb search over the envelope phase -> a coarse first-beat position.
##   4. Beat tracking (strongest onset near each predicted beat) and a
##      least-squares fit -> sub-frame period and phase.
##   5. Attack refinement on the raw samples -> the offset is not quantised to
##      the envelope hop.
##
## The offset is expressed the way the charter stores it: the audio time in
## milliseconds of chart beat 0.

const RATE := 100.0
const MIN_BPM := 40.0
const MAX_BPM := 240.0
const PREFERRED_CENTER := 140.0
const PRIOR_SIGMA := 0.55
const MAX_AUTOCORR_SECONDS := 45.0
const ATTACK_FLOOR := 0.35


## Effective envelope frame rate. The hop is rounded to whole samples, so it is
## not exactly RATE; using the nominal value would bias every tempo by the
## rounding error (0.23% at 11 kHz).
static func frame_rate(sample_rate: float) -> float:
	var hop := maxi(1, int(round(sample_rate / RATE)))
	return sample_rate / float(hop)


static func analyze(samples: PackedFloat32Array, sample_rate: float) -> Dictionary:
	var result := {
		"ok": false,
		"bpm": 0.0,
		"offset_ms": 0.0,
		"confidence": 0.0,
		"half_bpm": 0.0,
		"double_bpm": 0.0,
		"beats": 0,
		"error": "",
	}
	if sample_rate <= 0.0 or samples.size() < int(sample_rate * 2.0):
		result["error"] = "音频太短（至少 2 秒）"
		return result
	var fps := frame_rate(sample_rate)
	var env := onset_envelope(samples, sample_rate)
	if env.size() < 40:
		result["error"] = "音频太短"
		return result
	var peak := 0.0
	for value in env:
		peak = maxf(peak, value)
	if peak <= 0.000001:
		result["error"] = "没有检测到节拍（静音或纯音）"
		return result
	var acf := autocorrelation(env, fps)
	var coarse := _best_lag(acf, fps)
	if coarse <= 0.0:
		result["error"] = "找不到稳定的节拍周期"
		return result
	var period := coarse
	var phase := _best_phase(env, period)
	var tracked := _track_beats(env, period, phase, samples, sample_rate)
	period = float(tracked["period"])
	phase = float(tracked["phase"])
	if period < 60.0 * fps / MAX_BPM or period > 60.0 * fps / MIN_BPM:
		result["error"] = "节拍周期超出 40–240 BPM"
		return result
	var bpm := 60.0 * fps / period
	result["ok"] = true
	result["bpm"] = bpm
	result["offset_ms"] = phase / fps * 1000.0
	result["beats"] = int(tracked["matched"])
	result["half_bpm"] = bpm * 0.5 if bpm * 0.5 >= MIN_BPM else 0.0
	result["double_bpm"] = bpm * 2.0 if bpm * 2.0 <= MAX_BPM else 0.0
	var acf_peak := _acf_at(acf, period)
	var confidence := 0.35 * clampf(acf_peak * 1.4, 0.0, 1.0) + 0.65 * clampf(float(tracked["ratio"]), 0.0, 1.0)
	result["confidence"] = clampf(confidence, 0.0, 1.0)
	return result


## Onset strength per frame, normalised so the loudest onset is 1.0.
static func onset_envelope(samples: PackedFloat32Array, sample_rate: float) -> PackedFloat32Array:
	var hop := maxi(1, int(round(sample_rate / RATE)))
	var frames := samples.size() / hop
	if frames <= 0:
		return PackedFloat32Array()
	var low := PackedFloat32Array()
	var mid := PackedFloat32Array()
	var high := PackedFloat32Array()
	low.resize(frames)
	mid.resize(frames)
	high.resize(frames)
	var a_low := 1.0 - exp(-TAU * 120.0 / sample_rate)
	var a_high := 1.0 - exp(-TAU * 2500.0 / sample_rate)
	var lp_low := 0.0
	var lp_high := 0.0
	var acc_low := 0.0
	var acc_mid := 0.0
	var acc_high := 0.0
	var fill := 0
	var frame := 0
	for i in samples.size():
		var x := samples[i]
		lp_low += a_low * (x - lp_low)
		lp_high += a_high * (x - lp_high)
		var band_mid := lp_high - lp_low
		var band_high := x - lp_high
		acc_low += lp_low * lp_low
		acc_mid += band_mid * band_mid
		acc_high += band_high * band_high
		fill += 1
		if fill >= hop:
			if frame < frames:
				var inverse := 1.0 / float(fill)
				low[frame] = sqrt(acc_low * inverse)
				mid[frame] = sqrt(acc_mid * inverse)
				high[frame] = sqrt(acc_high * inverse)
			frame += 1
			fill = 0
			acc_low = 0.0
			acc_mid = 0.0
			acc_high = 0.0
	var flux := PackedFloat32Array()
	flux.resize(frames)
	var prev_low := 0.0
	var prev_mid := 0.0
	var prev_high := 0.0
	for t in frames:
		var l := log(0.000001 + low[t])
		var m := log(0.000001 + mid[t])
		var h := log(0.000001 + high[t])
		var dl := maxf(0.0, l - prev_low)
		var dm := maxf(0.0, m - prev_mid)
		var dh := maxf(0.0, h - prev_high)
		flux[t] = dl + dm + dh * 1.25
		prev_low = l
		prev_mid = m
		prev_high = h
	flux[0] = 0.0
	var smoothed := PackedFloat32Array()
	smoothed.resize(frames)
	for t in frames:
		var a := flux[maxi(0, t - 1)]
		var c := flux[mini(frames - 1, t + 1)]
		smoothed[t] = (a + 2.0 * flux[t] + c) * 0.25
	# Subtract a local mean so a long quiet intro or a sustained pad does not
	# dominate; keeping the residual positive is enough for the comb search.
	var window := int(RATE * 0.5)
	var out := PackedFloat32Array()
	out.resize(frames)
	var best := 0.0
	for t in frames:
		var from := maxi(0, t - window)
		var to := mini(frames, t + window + 1)
		var sum := 0.0
		for j in range(from, to):
			sum += smoothed[j]
		var residual := maxf(0.0, smoothed[t] - 1.2 * sum / float(maxi(1, to - from)))
		out[t] = residual
		best = maxf(best, residual)
	if best <= 0.0:
		return PackedFloat32Array()
	var scale := 1.0 / best
	for t in frames:
		out[t] *= scale
	return out


static func autocorrelation(env: PackedFloat32Array, fps: float = RATE) -> PackedFloat32Array:
	var n := mini(env.size(), int(fps * MAX_AUTOCORR_SECONDS))
	var max_lag := mini(int(ceil(60.0 * fps / MIN_BPM)) * 4 + 2, n - 1)
	var acf := PackedFloat32Array()
	acf.resize(max_lag + 1)
	for lag in max_lag + 1:
		var sum := 0.0
		for i in range(0, n - lag):
			sum += env[i] * env[i + lag]
		acf[lag] = sum / float(maxi(1, n - lag))
	if acf[0] > 0.0:
		var scale := 1.0 / acf[0]
		for i in acf.size():
			acf[i] *= scale
	return acf


static func _best_lag(acf: PackedFloat32Array, fps: float) -> float:
	var lag_min := int(floor(60.0 * fps / MAX_BPM))
	var lag_max := mini(int(ceil(60.0 * fps / MIN_BPM)), acf.size() - 2)
	var best_lag := -1
	var best_score := -1.0
	for lag in range(maxi(1, lag_min), lag_max + 1):
		var bpm := 60.0 * fps / float(lag)
		var score := acf[lag] * _prior(bpm)
		if score > best_score:
			best_score = score
			best_lag = lag
	if best_lag < 0:
		return 0.0
	return _parabolic(acf, best_lag)


static func _prior(bpm: float) -> float:
	var octaves := log(absf(bpm) / PREFERRED_CENTER) / log(2.0)
	return exp(-0.5 * pow(octaves / PRIOR_SIGMA, 2.0))


static func _parabolic(values: PackedFloat32Array, index: int) -> float:
	if index <= 0 or index >= values.size() - 1:
		return float(index)
	var left := values[index - 1]
	var middle := values[index]
	var right := values[index + 1]
	var denominator := left - 2.0 * middle + right
	if absf(denominator) < 0.0000001:
		return float(index)
	var delta := 0.5 * (left - right) / denominator
	return float(index) + clampf(delta, -0.5, 0.5)


static func _acf_at(acf: PackedFloat32Array, lag: float) -> float:
	var index := int(floor(lag))
	if index < 0 or index + 1 >= acf.size():
		return 0.0
	return lerpf(acf[index], acf[index + 1], lag - float(index))


static func _best_phase(env: PackedFloat32Array, period: float) -> float:
	var steps := 4
	var count := maxi(1, int(period * steps))
	var best_phase := 0.0
	var best_score := -1.0
	for s in count:
		var phase := float(s) / float(steps)
		var score := _comb_score(env, period, phase)
		if score > best_score:
			best_score = score
			best_phase = phase
	var below := _comb_score(env, period, best_phase - 1.0 / float(steps))
	var above := _comb_score(env, period, best_phase + 1.0 / float(steps))
	var denominator := below - 2.0 * best_score + above
	if absf(denominator) > 0.0000001:
		var delta := 0.5 * (below - above) / denominator
		best_phase += clampf(delta, -0.5, 0.5) / float(steps)
	return fposmod(best_phase, period)


static func _comb_score(env: PackedFloat32Array, period: float, phase: float) -> float:
	var score := 0.0
	var t := phase
	while t < float(env.size() - 1):
		score += _sample(env, t)
		t += period
	return score


static func _sample(env: PackedFloat32Array, position: float) -> float:
	if position < 0.0:
		return 0.0
	var index := int(floor(position))
	if index + 1 >= env.size():
		return env[env.size() - 1] if index < env.size() else 0.0
	var fraction := position - float(index)
	return lerpf(env[index], env[index + 1], fraction)


static func _track_beats(
	env: PackedFloat32Array,
	period: float,
	phase: float,
	samples: PackedFloat32Array,
	sample_rate: float
) -> Dictionary:
	var first := _match_beats(env, period, phase)
	var total_beats := int((float(env.size() - 1) - phase) / maxf(1.0, period))
	var matched := int(first["matched"])
	if matched < 8:
		return {"period": period, "phase": phase, "matched": matched, "ratio": 0.0}
	var best_beats: Array = first["beats"]
	var best_times: Array = first["times"]
	var best_period := period
	var best_phase := phase
	var fit := _robust_fit(best_beats, best_times)
	var fitted_period := float(fit["slope"])
	if fitted_period > 0.0 and absf(fitted_period - period) / period < 0.15:
		# Second pass: reassign against the fitted grid so a syncopated onset that
		# was grabbed in the first pass does not bias the final fit.
		var second := _match_beats(env, fitted_period, float(fit["intercept"]))
		if int(second["matched"]) >= 8:
			var fit_two := _robust_fit(second["beats"], second["times"])
			if float(fit_two["slope"]) > 0.0 and absf(float(fit_two["slope"]) - fitted_period) / fitted_period < 0.1:
				best_beats = second["beats"]
				best_times = second["times"]
				best_period = float(fit_two["slope"])
				best_phase = float(fit_two["intercept"])
	# The envelope hop quantises the attack; measuring it on the raw samples
	# removes the bias that would otherwise show up as a few ms of offset error.
	var hop := sample_rate / maxf(0.001, frame_rate(sample_rate))
	var refined := _refine_attacks(samples, sample_rate, hop, best_times)
	if refined.size() >= 8:
		var fit_three := _robust_fit(best_beats, refined)
		var slope := float(fit_three["slope"])
		if slope > 0.0 and absf(slope - best_period) / best_period < 0.05:
			best_period = slope
			best_phase = float(fit_three["intercept"])
	return {
		"period": best_period,
		"phase": best_phase,
		"matched": matched,
		"ratio": float(matched) / float(maxi(1, total_beats + 1)),
	}


## Strongest onset near every predicted beat, taken one envelope frame before
## the flux peak (the flux smears the attack backwards by one cell).
static func _match_beats(env: PackedFloat32Array, period: float, phase: float) -> Dictionary:
	var beats: Array[float] = []
	var times: Array[float] = []
	var index := 0
	while true:
		var predicted := phase + float(index) * period
		if predicted > float(env.size() - 1):
			break
		var from := maxi(0, int(predicted - period * 0.35))
		var to := mini(env.size() - 1, int(predicted + period * 0.35))
		var peak_index := -1
		var peak_value := 0.0
		for j in range(from, to + 1):
			if env[j] > peak_value:
				peak_value = env[j]
				peak_index = j
		if peak_index >= 0 and peak_value > 0.12:
			beats.append(float(index))
			times.append(float(peak_index) - 0.5)
		index += 1
	return {"beats": beats, "times": times, "matched": times.size()}


## Locates the attack of each beat on the raw waveform: a 1.5 ms rectified
## energy window, then the first crossing of 30% between the local floor and the
## local peak, linearly interpolated.
static func _refine_attacks(
	samples: PackedFloat32Array,
	sample_rate: float,
	hop: float,
	coarse_times: Array
) -> Array[float]:
	var result: Array[float] = []
	var window := maxi(1, int(sample_rate * 0.0015))
	var span := int(sample_rate * 0.030)
	var total := samples.size()
	if total <= window + 2:
		return result
	for i in coarse_times.size():
		var center := int(float(coarse_times[i]) * hop)
		var from := maxi(0, center - span)
		var to := mini(total - window - 1, center + span)
		if to <= from + 2:
			result.append(float(coarse_times[i]))
			continue
		var energy := PackedFloat32Array()
		energy.resize(to - from + 1)
		var sum := 0.0
		for k in range(from, from + window):
			sum += absf(samples[k])
		var best := sum
		var best_pos := from
		energy[0] = sum
		for pos in range(from + 1, to + 1):
			sum += absf(samples[pos + window - 1]) - absf(samples[pos - 1])
			energy[pos - from] = sum
			if sum > best:
				best = sum
				best_pos = pos
		var baseline := energy[0]
		var threshold := baseline + 0.30 * maxf(0.0, best - baseline)
		var crossing := best_pos
		var offset := best_pos - from
		while offset > 0:
			if energy[offset - 1] <= threshold:
				break
			offset -= 1
			crossing = from + offset
		var position := float(crossing)
		if offset > 0:
			var previous := energy[offset - 1]
			var current := energy[offset]
			if current > previous + 0.000001:
				position -= clampf((current - threshold) / (current - previous), 0.0, 1.0)
		result.append(position / hop)
	return result


## Least squares, then a median-absolute-deviation pass that drops beats whose
## onset was grabbed by something that is not the beat (syncopation, a stray
## effect, an edit) and refits. Without it a handful of wrong onsets tilt the
## slope and the tempo drifts by a fraction of a BPM.
static func _robust_fit(xs: Array, ys: Array) -> Dictionary:
	var fit := _linear_fit(xs, ys)
	var count := mini(xs.size(), ys.size())
	if count < 12:
		return fit
	var residuals: Array[float] = []
	for i in count:
		residuals.append(float(ys[i]) - (float(fit["slope"]) * float(xs[i]) + float(fit["intercept"])))
	var median := _median(residuals)
	var deviations: Array[float] = []
	for value in residuals:
		deviations.append(absf(value - median))
	var limit := maxf(0.5, 3.0 * _median(deviations))
	var kept_x: Array = []
	var kept_y: Array = []
	for i in count:
		if absf(residuals[i] - median) <= limit:
			kept_x.append(xs[i])
			kept_y.append(ys[i])
	if kept_x.size() < 12:
		return fit
	return _linear_fit(kept_x, kept_y)


static func _median(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var middle := sorted.size() / 2
	if sorted.size() % 2 == 0:
		return (float(sorted[middle - 1]) + float(sorted[middle])) * 0.5
	return float(sorted[middle])


static func _linear_fit(xs: Array, ys: Array) -> Dictionary:
	var count := mini(xs.size(), ys.size())
	if count < 2:
		return {"slope": 0.0, "intercept": 0.0}
	var sum_x := 0.0
	var sum_y := 0.0
	var sum_xx := 0.0
	var sum_xy := 0.0
	for i in count:
		var x := float(xs[i])
		var y := float(ys[i])
		sum_x += x
		sum_y += y
		sum_xx += x * x
		sum_xy += x * y
	var denominator := float(count) * sum_xx - sum_x * sum_x
	if absf(denominator) < 0.0000001:
		return {"slope": 0.0, "intercept": 0.0}
	var slope := (float(count) * sum_xy - sum_x * sum_y) / denominator
	var intercept := (sum_y - slope * sum_x) / float(count)
	return {"slope": slope, "intercept": intercept}
