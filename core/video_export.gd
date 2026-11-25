class_name VideoExport
extends Node

## 回放视频导出：用真正的 Playtest 在离线固定步长下跑一遍 replay，静音渲染到
## SubViewport，逐帧 rgb24 从 stdin 喂给外部 ffmpeg。
##
## 关键点（对照 danser-go 的 mainLoopRecord）：
##   · 第 k 帧的谱面时间恒为 start + k*1000/fps，绝不读墙钟 —— 帧数确定、两次导出逐帧一致。
##   · 判定/特效/连击全部来自 Playtest，不再是「按时间猜命中」的重建画面。
##   · 写管道失败必须报错，禁止「丢了一半帧还改名成功」。

signal progress(done: int, total: int)
signal finished(path: String, message: String)

## 导出的分辨率与帧率（UI 里选）。
var size := Vector2i(1920, 1080)
var fps := 60
## auto / nvenc / qsv / videotoolbox / vaapi / libx264。强制指定但跑不了时自动回退。
var encoder_pref := "auto"
## 背景明暗（0–1）：曲绘 / BGA / 故事板，和游戏里同一个系数。
var background_brightness: float = 1.0
## 谱面没有 replay 时（AUTO / 基准）用自动演奏跑同一套离线管线。
var auto_play := false
## 没有 replay 时跟随当前试玩镜像；有 replay 时由回放文件自己的 mirror 决定。
var mirror_mode := "off"

var _running := false
var _cancel := false
## 编码器探测要真编码一帧（~2s）。缓存跨实例复用：同一台机器反复导出不必重探。
static var _chosen: Dictionary = {}
static var _listed: Dictionary = {}


## 当前机器上能用的编码器（先真编码一帧，结果缓存）。
func pick_encoder() -> Dictionary:
	if not _chosen.is_empty():
		return _chosen
	var ffmpeg := _ffmpeg()
	if ffmpeg.is_empty():
		return {}
	var listed := _list_encoders(ffmpeg)
	var wanted := _pref_name()
	if not wanted.is_empty():
		for cand in _candidates():
			if String(cand["name"]) == wanted and listed.has(wanted) and _smoke(ffmpeg, cand):
				_chosen = cand
				return _chosen
	for cand in _candidates():
		if not listed.has(String(cand["name"])):
			continue
		if _smoke(ffmpeg, cand):
			_chosen = cand
			return _chosen
	return {}


## auto 时按「硬件优先」的顺序挑；UI 里也能强制指定。
func _pref_name() -> String:
	match encoder_pref:
		"nvenc":
			return "h264_nvenc"
		"qsv":
			return "h264_qsv"
		"videotoolbox":
			return "h264_videotoolbox"
		"vaapi":
			return "h264_vaapi"
		"libx264":
			return "libx264"
	return ""


static func _candidates() -> Array:
	return [
		{"name": "h264_nvenc", "args": ["-c:v", "h264_nvenc", "-preset", "p5", "-tune", "hq",
			"-rc", "vbr", "-cq", "23", "-b:v", "0", "-pix_fmt", "yuv420p"]},
		{"name": "h264_qsv", "args": ["-init_hw_device", "qsv=hw", "-filter_hw_device", "hw",
			"-vf", "format=nv12,hwupload", "-c:v", "h264_qsv", "-global_quality", "23", "-preset", "veryfast"]},
		{"name": "h264_videotoolbox", "args": ["-c:v", "h264_videotoolbox", "-q:v", "60", "-pix_fmt", "yuv420p"]},
		{"name": "h264_amf", "args": ["-c:v", "h264_amf", "-quality", "quality", "-rc", "cqp",
			"-qp_i", "20", "-qp_p", "22", "-pix_fmt", "yuv420p"]},
		{"name": "h264_vaapi", "args": []},
		{"name": "libx264", "args": ["-c:v", "libx264", "-preset", "veryfast", "-crf", "20",
			"-pix_fmt", "yuv420p", "-movflags", "+faststart"]},
	]


func _ffmpeg() -> String:
	# 必须走 exe()：ffmpeg_exe 只是「用户手动指定」的设置值，默认是哨兵 "ffmpeg"。
	# 直接返回它的话，装了内置 ffmpeg 但 PATH 里没有 ffmpeg 的机器会拿到一个执行不起来的字符串。
	return MediaIO.exe() if MediaIO.has_ffmpeg() else ""


func _list_encoders(ffmpeg: String) -> Dictionary:
	if not _listed.is_empty():
		return _listed
	var out: Array = []
	OS.execute(ffmpeg, ["-hide_banner", "-encoders"], out, true, false)
	var text := "\n".join(out)
	var names := {}
	for cand in _candidates():
		names[String(cand["name"])] = text.contains(String(cand["name"]))
	_listed = names
	return _listed


## VAAPI 的设备名各机器不同，逐个 renderD* 试一遍。
static func _vaapi_devices() -> Array:
	var devices: Array = []
	var dir := DirAccess.open("/dev/dri")
	if dir == null:
		return ["/dev/dri/renderD128"]
	for file_name in dir.get_files():
		if file_name.begins_with("renderD"):
			devices.append("/dev/dri/" + file_name)
	devices.sort()
	if devices.is_empty():
		devices.append("/dev/dri/renderD128")
	return devices


func _probe_args(cand: Dictionary, device: String) -> Array:
	if String(cand["name"]) == "h264_vaapi":
		return ["-vaapi_device", device, "-vf", "format=nv12,hwupload", "-c:v", "h264_vaapi", "-qp", "23"]
	return cand["args"]


## 真编码一帧到 null（不落盘、能拿退出码）。只写文件再看大小会把
## 「ffmpeg 装坏了」和「这台机器没这个硬件」混在一起。
func _smoke(ffmpeg: String, cand: Dictionary) -> bool:
	var devices := _vaapi_devices() if String(cand["name"]) == "h264_vaapi" else [""]
	for device in devices:
		var args: Array = ["-hide_banner", "-loglevel", "error",
			"-f", "lavfi", "-i", "color=c=black:s=256x256:d=0.1:r=10",
			"-frames:v", "1"] + _probe_args(cand, String(device)) + ["-f", "null", "-"]
		var code := OS.execute(ffmpeg, args, [], true, false)
		if code == 0:
			return true
	return false


func _input_args(input_size: Vector2i) -> Array:
	return ["-hide_banner", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24",
		"-s", "%dx%d" % [input_size.x, input_size.y], "-r", str(fps), "-i", "-"]


## 帧数是硬约定：给定跨度与帧率，导出的 nb_frames 必须等于它。
static func frame_total(span_ms: float, frames_per_second: int) -> int:
	return maxi(1, ceili(maxf(0.0, span_ms) / 1000.0 * float(frames_per_second)))


## 回放从录制起点开始导出；AUTO/没有回放时才从 0 开始。
static func start_ms_for(chart: Chart, replay: Replay) -> float:
	if chart == null or replay == null:
		return 0.0
	return chart.timing.beat_to_chart_ms(maxf(0.0, replay.start_beat))


## 渲染 [start_ms, end_ms]。
## replay 为 null 时用自动演奏（AUTO）跑同一条管线。
func export_chart(chart: Chart, start_ms: float, end_ms: float, out_path: String,
		replay: Replay = null, show_storyboard: bool = true) -> void:
	if _running or chart == null:
		return
	_running = true
	_cancel = false
	var encoder: Dictionary = await pick_encoder()
	if encoder.is_empty():
		_running = false
		finished.emit("", "找不到可用的 H.264 编码器（需要外部 ffmpeg）")
		return
	var device := ""
	if String(encoder["name"]) == "h264_vaapi":
		device = String(_smoke_device(String(encoder["name"])))
	var temp := out_path.get_basename() + ".part.mp4"
	var args: Array = _input_args(size) + _probe_args(encoder, device) + ["-an", "-y", temp]
	var pipe := OS.execute_with_pipe(_ffmpeg(), args, false)
	if pipe.is_empty():
		_running = false
		finished.emit("", "启动 ffmpeg 失败")
		return
	var stdin: FileAccess = pipe.get("stdio")
	var pid := int(pipe.get("pid", -1))

	var viewport := SubViewport.new()
	viewport.size = size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.disable_3d = false
	add_child(viewport)

	var playtest := PlaytestScript.new()
	playtest.offline_mode = true
	playtest.auto_play = auto_play and replay == null
	playtest.replay_source = replay
	playtest.next_playback_rate = 1.0
	playtest.mirror_mode = mirror_mode
	# 打击音不能让整机静音吃掉：收集事件，导出时合成一条 SFX 音轨。
	playtest.sfx_capture = []
	add_child(playtest)
	# 引擎自己也会每帧调 _process；离线导出必须只由帧循环驱动，
	# 否则真实帧率一变，特效和判定就多走几步。
	playtest.set_process(false)
	playtest.set_physics_process(false)
	playtest.setup(chart, chart.ms_to_beat(maxf(0.0, start_ms)), "")
	# 把预览搬进 SubViewport：判定/特效仍由 Playtest 驱动，画面只留预览与 HUD。
	var preview = playtest._preview
	if preview == null:
		_fail(stdin, viewport, playtest, temp, "预览节点初始化失败")
		_running = false
		return
	preview.reparent(viewport)
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview.set_background_brightness(background_brightness)
	preview.show_storyboard = show_storyboard
	preview.show_storyboard_background = show_storyboard
	preview.set_process(false)
	# 导出按目标 fps 逐帧采样，不要被主界面的帧率上限节流。
	preview.storyboard_sample_hz = fps

	# 导出期间整台机器彻底静音（音效、音乐都不要漏出来）。
	var previous_mute := AudioServer.is_bus_mute(AudioServer.get_bus_index("Master"))
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)

	var span := maxf(1.0, end_ms - start_ms)
	var total := frame_total(span, fps)
	var step_ms := 1000.0 / float(fps)
	var written := 0

	# SubViewport 要渲染过一帧才会分配贴图。
	await _await_draw()
	await _await_draw()

	for frame in total:
		if _cancel or stdin == null:
			break
		# 帧号决定时间：同一份 replay 在任何机器、任何速度下都得到同一批时间点。
		var ms := start_ms + float(frame) * step_ms
		playtest.offline_ms = ms
		playtest._process(1.0 / float(fps))
		await _await_draw()
		var image := viewport.get_texture().get_image()
		if image != null and not image.is_empty():
			if image.get_format() != Image.FORMAT_RGB8:
				image.convert(Image.FORMAT_RGB8)
			if not await _write_frame(stdin, image.get_data()):
				break
			written += 1
		if frame % 10 == 0:
			progress.emit(frame, total)

	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), previous_mute)
	stdin.close()
	print("[ve] %dx%d@%d total=%d written=%d device=%s" % [size.x, size.y, fps, total, written, device])

	var deadline := Time.get_ticks_msec() + 120000
	while pid > 0 and OS.is_process_running(pid) and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.05).timeout
	var err_pipe: FileAccess = pipe.get("stderr")
	if err_pipe != null:
		var err_text := err_pipe.get_as_text().strip_edges()
		if not err_text.is_empty():
			print("[ve] ffmpeg stderr: ", err_text.substr(0, 600))
	# 导出跑的是同一套判定；留一份结果，和录制时结算的成绩对一下。
	var judged := {
		"hit": playtest._hit_count,
		"miss": playtest._miss_count,
		"combo": playtest._max_combo,
	}
	var sfx_events: Array = playtest.sfx_capture if playtest.sfx_capture != null else []
	var sfx_style := String(playtest._sfx.style) if playtest._sfx != null else "default"
	playtest.queue_free()
	viewport.queue_free()
	_running = false

	if _cancel:
		_remove_quietly(temp)
		finished.emit("", "已取消")
		return
	# 帧数对不上就是丢了帧：绝不改名成功，否则会出现「后半段没了但提示已导出」。
	if written != total:
		_remove_quietly(temp)
		finished.emit("", "导出中断：只写入 %d/%d 帧（编码器 %s）" % [written, total, String(encoder["name"])])
		return
	if not FileAccess.file_exists(temp) or FileAccess.get_file_as_bytes(temp).size() < 1024:
		finished.emit("", "ffmpeg 没有产出视频（编码器：%s）" % String(encoder["name"]))
		return
	# 音轨：和 danser 一样分两步 —— 先出无声视频，再和音源封装成成片。
	# 直接把音源塞进录制管道会和逐帧写 rawvideo 抢节奏，失败时整段都没了。
	var audio_note := ""
	var muxed := ""
	var sfx := ""
	if not sfx_events.is_empty():
		sfx = out_path.get_basename() + ".sfx.wav"
		if not _render_sfx(sfx_events, sfx_style, start_ms, span, sfx):
			sfx = ""
	var audio := _audio_source(chart)
	if not audio.is_empty() or not sfx.is_empty():
		muxed = out_path.get_basename() + ".mux.mp4"
		if _mux_audio(temp, audio, sfx, muxed, start_ms, span, chart.offset_ms):
			audio_note = " · 含音轨" + ("（含打击音）" if not sfx.is_empty() else "")
		else:
			_remove_quietly(muxed)
			audio_note = " · 音轨封装失败（仅视频）"
	_remove_quietly(sfx)
	var source := muxed if not muxed.is_empty() and FileAccess.file_exists(muxed) else temp
	_remove_quietly(out_path)
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(source),
		ProjectSettings.globalize_path(out_path))
	if err != OK:
		finished.emit("", "无法写入 %s" % out_path)
		return
	_remove_quietly(temp)
	# 时长对不上就是编码器/管道丢了帧：宁可报出来，也不要给一个「提示已导出」的短片。
	var expected := span / 1000.0
	var actual := _probe_duration(out_path)
	if actual > 0.0 and absf(actual - expected) > maxf(0.12, 2.0 / float(fps)):
		finished.emit(out_path, "已导出 %s，但时长 %.2fs ≠ 预期 %.2fs（%s · %dx%d@%d%s）" % [
			out_path.get_file(), actual, expected, String(encoder["name"]), size.x, size.y, fps, audio_note])
		return
	# 成绩对不上说明这局回放没从录制起点/同一张谱面重跑，直接写进提示，别让人以为「导出的就是本局」。
	var mismatch := ""
	if replay != null and not replay.result.is_empty():
		var want_hit := int(replay.result.get("hit", -1))
		var want_miss := int(replay.result.get("miss", -1))
		var want_combo := int(replay.result.get("max_combo", -1))
		if want_hit >= 0 and (want_hit != int(judged["hit"]) or want_miss != int(judged["miss"])
				or (want_combo >= 0 and want_combo != int(judged["combo"]))):
			mismatch = " · ⚠ 判定与录制不一致（命中 %d/%d，失误 %d/%d，最大连击 %d/%d）" % [
				int(judged["hit"]), want_hit, int(judged["miss"]), want_miss,
				int(judged["combo"]), want_combo]
	finished.emit(out_path, "已导出 %s（%s · %dx%d@%d · %.2fs%s%s）" % [
		out_path.get_file(), String(encoder["name"]), size.x, size.y, fps, expected, audio_note, mismatch])


## 等一帧画完。窗口被遮挡/最小化时引擎可能不再发 frame_post_draw，
## 没有兜底就会永远卡在导出第 N 帧。超时后用上一帧继续，至少把片子写完。
func _await_draw(timeout_ms: int = 3000) -> void:
	var seen := [false]
	var callback := func() -> void: seen[0] = true
	RenderingServer.frame_post_draw.connect(callback, CONNECT_ONE_SHOT)
	var deadline := Time.get_ticks_msec() + timeout_ms
	while not seen[0] and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if RenderingServer.frame_post_draw.is_connected(callback):
		RenderingServer.frame_post_draw.disconnect(callback)


## 音源文件：优先用播放器已经在用的那份（原生格式或转码缓存）。
func _audio_source(chart: Chart) -> String:
	if chart == null:
		return ""
	var path := chart.audio_path
	if path.is_empty():
		return ""
	if not (path.begins_with("res://") or path.begins_with("user://") or path.is_absolute_path()):
		path = ProjectSettings.globalize_path(path)
	var prepared := MediaIO.prepare_audio(path)
	if prepared.is_empty() or not FileAccess.file_exists(ProjectSettings.globalize_path(prepared)):
		return ""
	return ProjectSettings.globalize_path(prepared)


## 把音源按谱面 offset 对齐后封进视频。时间基准和预览一致：
## chart_ms = audio_ms + offset_ms，所以音频起点 = start_ms - offset_ms。
func _mux_audio(video: String, audio: String, sfx: String, out: String, start_ms: float,
		span_ms: float, offset_ms: float) -> bool:
	var ffmpeg := _ffmpeg()
	if ffmpeg.is_empty():
		return false
	var audio_start := maxf(0.0, (start_ms - offset_ms) / 1000.0)
	var span_s := maxf(0.05, span_ms / 1000.0)
	# 不要 -shortest：音源比故事板短时会连带把视频截短，正是「提示已导出但时长偏短」的来源。
	var args: Array = ["-hide_banner", "-loglevel", "error", "-y",
		"-i", ProjectSettings.globalize_path(video)]
	if not audio.is_empty():
		args += ["-ss", "%.3f" % audio_start, "-t", "%.3f" % span_s, "-i", audio]
	if not sfx.is_empty():
		args += ["-i", ProjectSettings.globalize_path(sfx)]
	args += ["-map", "0:v:0"]
	if not audio.is_empty() and not sfx.is_empty():
		# 打击音是离线合成的 44.1k 单声道 wav：先统一格式再和音乐求和。
		args += ["-filter_complex",
			"[1:a]aformat=sample_fmts=fltp:sample_rates=44100:channel_layouts=stereo[m];"
			+ "[2:a]aformat=sample_fmts=fltp:sample_rates=44100:channel_layouts=stereo[s];"
			+ "[m][s]amix=inputs=2:duration=first:normalize=0[a]",
			"-map", "[a]"]
	elif not audio.is_empty() or not sfx.is_empty():
		# 只有一条音轨：没有音乐时它是打击音，没有打击音时它是音乐。
		args += ["-map", "1:a:0"]
	args += ["-c:v", "copy", "-c:a", "aac", "-b:a", "192k",
		"-movflags", "+faststart", ProjectSettings.globalize_path(out)]
	return OS.execute(ffmpeg, args, [], true, false) == 0 and FileAccess.file_exists(out)


## 离线判定不发声：把捕获到的打击音事件按 HitSfx 的音量/音高混成一条 wav 音轨。
## 源素材统一交给 ffmpeg 转成 44.1k 单声道（.ogg 在 GDScript 里没法解码）。
func _render_sfx(events: Array, style: String, start_ms: float, span_ms: float, out_path: String) -> bool:
	# 「打击音效 → 静音」在游戏里就是不播，导出也要一致。
	if style == "mute":
		return false
	var rate := 44100
	var total := maxi(1, int(ceil(span_ms / 1000.0 * float(rate))))
	var samples := {}
	for event in events:
		var kind := String(event.get("k", ""))
		if samples.has(kind):
			continue
		samples[kind] = _sfx_pcm(kind)
	var mix := PackedFloat32Array()
	mix.resize(total)
	var played := false
	for event in events:
		var kind := String(event.get("k", ""))
		var buf: PackedFloat32Array = samples.get(kind, PackedFloat32Array())
		if buf.size() < 2:
			continue
		var step := maxf(0.05, float(event.get("p", 1.0)) * float(HitSfx.STYLE_PITCH.get(style, 1.0)))
		var gain := db_to_linear(float(HitSfx.KIND_DB.get(kind, HitSfx.VOLUME_DB))
			+ float(HitSfx.STYLE_DB.get(style, 0.0)))
		var start := int(round((float(event.get("t", 0.0)) - start_ms) / 1000.0 * float(rate)))
		var pos := 0.0
		var i := 0
		while pos < float(buf.size() - 1) and start + i < total:
			if start + i >= 0:
				var index := int(pos)
				mix[start + i] += lerpf(buf[index], buf[index + 1], pos - float(index)) * gain
			pos += step
			i += 1
		played = true
	if not played:
		return false
	var data := PackedByteArray()
	data.resize(total * 2)
	for i in total:
		data.encode_s16(i * 2, int(clampf(mix[i], -1.0, 1.0) * 32767.0))
	var header := PackedByteArray()
	header.resize(44)
	header.encode_u32(0, 0x46464952)  # RIFF
	header.encode_u32(4, 36 + data.size())
	header.encode_u32(8, 0x45564157)  # WAVE
	header.encode_u32(12, 0x20746D66)  # "fmt "
	header.encode_u32(16, 16)
	header.encode_u16(20, 1)
	header.encode_u16(22, 1)
	header.encode_u32(24, rate)
	header.encode_u32(28, rate * 2)
	header.encode_u16(32, 2)
	header.encode_u16(34, 16)
	header.encode_u32(36, 0x61746164)  # data
	header.encode_u32(40, data.size())
	var file := FileAccess.open(ProjectSettings.globalize_path(out_path), FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(header)
	file.store_buffer(data)
	file.close()
	return true


## 打击音的 PCM 数据（-1..1）。导出本来就要外部 ffmpeg，借它统一采样率/声道。
func _sfx_pcm(kind: String) -> PackedFloat32Array:
	var path := String(HitSfx.PATHS.get(kind, ""))
	var ffmpeg := _ffmpeg()
	if path.is_empty() or ffmpeg.is_empty():
		return PackedFloat32Array()
	var tmp := "user://.sfx_%s.wav" % kind
	var code := OS.execute(ffmpeg, ["-hide_banner", "-loglevel", "error", "-y",
		"-i", ProjectSettings.globalize_path(path), "-ac", "1", "-ar", "44100",
		ProjectSettings.globalize_path(tmp)], [], true, false)
	if code != 0 or not FileAccess.file_exists(ProjectSettings.globalize_path(tmp)):
		return PackedFloat32Array()
	var bytes := FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(tmp))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
	if bytes.size() < 44 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF":
		return PackedFloat32Array()
	var offset := 12
	var data := PackedByteArray()
	while offset + 8 <= bytes.size():
		var id := bytes.slice(offset, offset + 4).get_string_from_ascii()
		var chunk := bytes.decode_u32(offset + 4)
		var body := offset + 8
		if id == "data":
			data = bytes.slice(body, mini(body + chunk, bytes.size()))
		offset = body + chunk + (chunk & 1)
	var out := PackedFloat32Array()
	out.resize(data.size() / 2)
	for i in out.size():
		out[i] = float(data.decode_s16(i * 2)) / 32768.0
	return out


## 成片时长（秒）。ffprobe 不在就退回 ffmpeg 的 -i 输出，都拿不到就返回 0（跳过校验）。
func _probe_duration(path: String) -> float:
	return MediaIO.probe_video_duration(ProjectSettings.globalize_path(path))


func _smoke_device(encoder_name: String) -> String:
	var ffmpeg := _ffmpeg()
	for device in _vaapi_devices():
		var args: Array = ["-hide_banner", "-loglevel", "error",
			"-f", "lavfi", "-i", "color=c=black:s=256x256:d=0.1:r=10", "-frames:v", "1",
			"-vaapi_device", device, "-vf", "format=nv12,hwupload", "-c:v", encoder_name,
			"-qp", "23", "-f", "null", "-"]
		if OS.execute(ffmpeg, args, [], true, false) == 0:
			return device
	return ""


func _remove_quietly(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _fail(stdin: FileAccess, viewport: SubViewport, playtest: Node, temp: String, message: String) -> void:
	if stdin != null:
		stdin.close()
	if playtest != null:
		playtest.queue_free()
	if viewport != null:
		viewport.queue_free()
	_remove_quietly(temp)
	finished.emit("", message)


## Godot 的管道写入是非阻塞的：一次丢几 MB 会直接失败（EAGAIN）。
## 拆成 4KB 小块重试；只有超过墙钟期限才认定 ffmpeg 死了。
func _write_frame(stdin: FileAccess, data: PackedByteArray) -> bool:
	var offset := 0
	var start := Time.get_ticks_msec()
	# 4KB 一块不是性能选择：管道一次 store_buffer 只吃下有限字节且返回值不报
	# 实际写入量，块再大就会悄悄丢帧（实测 256KB 只写进 565KB/2.7MB）。
	while offset < data.size():
		var chunk := data.slice(offset, mini(offset + 4096, data.size()))
		if stdin.store_buffer(chunk):
			offset += chunk.size()
			continue
		if Time.get_ticks_msec() - start > 30000:
			return false
		await get_tree().process_frame
	return true


func cancel() -> void:
	_cancel = true


## 把 .replay 里的 press 事件配到谱面音符上（只给旧测试与预览用）。
## 导出现在走真 Playtest 判定，不再用这份近似。
func plan_hits(chart: Chart, events: Array) -> Array:
	var notes: Array[Dictionary] = []
	for note in chart.notes:
		if not (note.type in ["tap", "hold", "path"]):
			continue
		notes.append({
			"note": note,
			"target": chart.timing.beat_to_chart_ms(note.beat),
			"half": maxf(12.0, (note.arc_width() + 20.0) * 0.5),
			"used": false,
		})
	if notes.is_empty():
		return []
	var hits: Array[Dictionary] = []
	for raw in events:
		var event := raw as Dictionary
		if String(event.get("k", "")) != "press":
			continue
		var time := float(event.get("t", 0.0))
		var angle := float(event.get("a", NAN))
		var best := -1
		var best_error := 1.0e9
		for i in notes.size():
			var entry: Dictionary = notes[i]
			if bool(entry["used"]):
				continue
			var error: float = absf(time - float(entry["target"]))
			if error > 200.0:
				continue
			if not is_nan(angle):
				var note: Note = entry["note"]
				if absf(JudgeMath.angle_delta(angle, note.angle)) > float(entry["half"]):
					continue
			if error < best_error:
				best_error = error
				best = i
		if best < 0:
			continue
		notes[best]["used"] = true
		var picked: Note = notes[best]["note"]
		hits.append({
			"ms": float(notes[best]["target"]),
			"note": picked,
			"kind": picked.type,
			"tier": _tier_for(best_error),
		})
	hits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["ms"]) < float(b["ms"]))
	return hits


## 0=PERFECT 1=GREAT 2=GOOD 3=MISS/BAD，和试玩窗口一致。
static func _tier_for(error: float) -> int:
	if error <= 65.0:
		return 0
	if error <= 115.0:
		return 1
	if error <= 170.0:
		return 2
	return 3


static func _tier_colour(tier: int) -> Color:
	match tier:
		0:
			return UITheme.GOLD
		1:
			return UITheme.CYAN
		2:
			return UITheme.INK
	return UITheme.RED


static func _move_events(events: Array) -> Array:
	var moves: Array = []
	for raw in events:
		var event := raw as Dictionary
		if String(event.get("k", "")) == "move":
			moves.append(event)
	return moves


## 光标按录制点线性插值；超出最后一条就停在最后位置。
static func _cursor_at(moves: Array, ms: float) -> Vector2:
	if moves.is_empty():
		return Vector2.INF
	var index := 0
	while index < moves.size() and float(moves[index]["t"]) <= ms:
		index += 1
	if index == 0:
		return Vector2(float(moves[0]["x"]), float(moves[0]["y"]))
	if index >= moves.size():
		var last: Dictionary = moves[moves.size() - 1]
		return Vector2(float(last["x"]), float(last["y"]))
	var a: Dictionary = moves[index - 1]
	var b: Dictionary = moves[index]
	var span := maxf(0.001, float(b["t"]) - float(a["t"]))
	var w := clampf((ms - float(a["t"])) / span, 0.0, 1.0)
	return Vector2(float(a["x"]), float(a["y"])).lerp(Vector2(float(b["x"]), float(b["y"])), w)


const PlaytestScript := preload("res://charter/playtest.gd")
