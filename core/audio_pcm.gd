class_name AudioPCM
extends RefCounted

## Decodes an audio file into a mono float PCM buffer for analysis.
##
## Godot exposes playback for WAV/OGG/MP3 but not the decoded samples, so the
## analyzer needs its own path in:
##   * WAV: parsed here (PCM 8/16/24/32-bit and IEEE float, any channel count).
##   * Everything else: converted to a mono 11 kHz WAV by ffmpeg and cached in
##     `user://analysis/`, then parsed with the same reader.
##
## The cache is keyed by the absolute source path, so a song is only decoded
## once. Nothing here touches the audio server, which keeps it safe to call from
## a worker thread.

const DEFAULT_RATE := 11025
const MAX_SECONDS := 600.0
const CACHE_DIR := "user://analysis"

static var last_error: String = ""


static func load_mono(path: String, target_rate: int = DEFAULT_RATE) -> PackedFloat32Array:
	last_error = ""
	if path.is_empty():
		last_error = "音频路径为空"
		return PackedFloat32Array()
	var resolved := resolve(path)
	if resolved.is_empty():
		last_error = "找不到音频文件：%s" % path
		return PackedFloat32Array()
	var source := resolved
	if resolved.get_extension().to_lower() != "wav":
		source = _transcode_to_wav(resolved, target_rate)
		if source.is_empty():
			return PackedFloat32Array()
	var decoded := _read_wav(source)
	if decoded.is_empty():
		if last_error.is_empty():
			last_error = "无法解析 WAV：%s" % source.get_file()
		return PackedFloat32Array()
	return resample_mono(decoded["samples"], int(decoded["rate"]), target_rate)


static func resolve(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		if FileAccess.file_exists(path):
			return ProjectSettings.globalize_path(path)
		return ""
	if path.is_absolute_path():
		return path if FileAccess.file_exists(path) else ""
	if FileAccess.file_exists(path):
		return ProjectSettings.globalize_path(path)
	return ""


static func _transcode_to_wav(path: String, target_rate: int) -> String:
	if not MediaIO.has_ffmpeg():
		last_error = "%s 需要 ffmpeg 解码：请安装 ffmpeg，或在导入窗口里指定 ffmpeg 路径" % path.get_extension().to_upper()
		return ""
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	var target := "%s/%s_%d.wav" % [CACHE_DIR, path.md5_text().substr(0, 12), target_rate]
	var existing := FileAccess.open(target, FileAccess.READ)
	if existing != null:
		var size := existing.get_length()
		existing.close()
		if size > 1024:
			return target
	var args := [
		"-y", "-v", "error", "-i", path,
		"-vn", "-ac", "1", "-ar", str(target_rate), "-f", "wav",
		ProjectSettings.globalize_path(target),
	]
	var output: Array = []
	var code := OS.execute(MediaIO.ffmpeg_exe, args, output, true, false)
	if code != 0 or not FileAccess.file_exists(target):
		var detail := ""
		if not output.is_empty():
			detail = String(output[0]).strip_edges().replace("\n", " ").substr(0, 180)
		last_error = "ffmpeg 解码失败（退出码 %d）：%s" % [code, detail]
		return ""
	return target


static func _read_wav(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_error = "无法打开 %s" % path.get_file()
		return {}
	var total := file.get_length()
	var header := file.get_buffer(12)
	if header.size() < 12:
		file.close()
		last_error = "WAV 文件头不完整"
		return {}
	if header.slice(0, 4).get_string_from_ascii() != "RIFF":
		file.close()
		last_error = "不是 RIFF 文件"
		return {}
	if header.slice(8, 12).get_string_from_ascii() != "WAVE":
		file.close()
		last_error = "不是 WAVE 数据"
		return {}
	var audio_format := 1
	var channels := 0
	var rate := 0
	var bits := 0
	var payload := PackedByteArray()
	while file.get_position() + 8 <= total:
		var chunk_start := file.get_position()
		var chunk_id := file.get_buffer(4)
		if chunk_id.size() < 4:
			break
		var chunk_size := file.get_32()
		var id := chunk_id.get_string_from_ascii()
		var next_pos := chunk_start + 8 + chunk_size + (chunk_size & 1)
		if id == "fmt ":
			var fmt := file.get_buffer(mini(chunk_size, 64))
			if fmt.size() >= 16:
				audio_format = fmt.decode_u16(0)
				channels = fmt.decode_u16(2)
				rate = fmt.decode_u32(4)
				bits = fmt.decode_u16(14)
				if audio_format == 0xFFFE and fmt.size() >= 26:
					audio_format = fmt.decode_u16(24)
		elif id == "data":
			var available := mini(chunk_size, total - file.get_position())
			if available <= 0:
				break
			if rate > 0 and channels > 0 and bits >= 8:
				var frame_bytes := maxi(1, (bits / 8) * channels)
				available = mini(available, int(MAX_SECONDS * rate) * frame_bytes)
			payload = file.get_buffer(available)
		if next_pos <= chunk_start:
			break
		file.seek(next_pos)
	file.close()
	if payload.is_empty() or channels <= 0 or rate <= 0 or bits < 8:
		last_error = "WAV 缺少 fmt/data 块"
		return {}
	var bytes_per_sample := maxi(1, bits / 8)
	var frame_bytes := bytes_per_sample * channels
	var frames := payload.size() / frame_bytes
	if frames <= 0:
		last_error = "WAV 数据为空"
		return {}
	var samples := PackedFloat32Array()
	samples.resize(frames)
	var is_float := audio_format == 3
	for i in frames:
		var base := i * frame_bytes
		var sum := 0.0
		for channel in channels:
			var offset := base + channel * bytes_per_sample
			match bits:
				8:
					sum += (float(payload[offset]) - 128.0) / 128.0
				16:
					sum += float(payload.decode_s16(offset)) / 32768.0
				24:
					sum += float(_decode_s24(payload, offset)) / 8388608.0
				32:
					if is_float:
						sum += payload.decode_float(offset)
					else:
						sum += float(payload.decode_s32(offset)) / 2147483648.0
				_:
					sum += 0.0
		samples[i] = sum / float(channels)
	return {"samples": samples, "rate": rate, "channels": channels, "bits": bits}


static func _decode_s24(data: PackedByteArray, offset: int) -> int:
	var value: int = int(data[offset]) | (int(data[offset + 1]) << 8) | (int(data[offset + 2]) << 16)
	if value & 0x800000:
		value -= 0x1000000
	return value


static func resample_mono(samples: PackedFloat32Array, source_rate: int, target_rate: int) -> PackedFloat32Array:
	if samples.is_empty() or source_rate <= 0 or target_rate <= 0 or source_rate == target_rate:
		return samples
	var ratio := float(source_rate) / float(target_rate)
	var out_frames := int(floor(float(samples.size()) / ratio))
	if out_frames <= 0:
		return PackedFloat32Array()
	var out := PackedFloat32Array()
	out.resize(out_frames)
	var last := samples.size() - 1
	if ratio > 1.0:
		# Box average over the samples that fall into one output frame; acts as a
		# crude anti-alias filter, which is plenty for an onset envelope.
		var window := maxi(1, int(ceil(ratio)))
		for i in out_frames:
			var start := int(floor(float(i) * ratio))
			var finish := mini(samples.size(), start + window)
			var sum := 0.0
			for j in range(start, finish):
				sum += samples[j]
			out[i] = sum / float(maxi(1, finish - start))
	else:
		for i in out_frames:
			var position := float(i) * ratio
			var index := int(floor(position))
			var fraction := position - float(index)
			var a := samples[clampi(index, 0, last)]
			var b := samples[clampi(index + 1, 0, last)]
			out[i] = lerpf(a, b, fraction)
	return out
