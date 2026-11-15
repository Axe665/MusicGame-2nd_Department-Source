class_name VideoExport
extends Node

## 静默导出：固定帧率渲染到 SubViewport，逐帧 rawvideo 从 stdin 管道喂给外部 ffmpeg。
## 导出过程中不启动任何音频播放器，输出也没有音轨（-an）。
## 编码器按 nvenc → qsv → videotoolbox → vaapi → libx264 的顺序挑，每个先用一帧试编码，
## 避免“列表里有但机器上跑不了”（例如没有 N 卡却装了带 nvenc 的 ffmpeg）。

signal progress(done: int, total: int)
signal finished(path: String, message: String)

const SIZE := Vector2i(1280, 720)
const FPS := 60

## auto / nvenc / qsv / videotoolbox / vaapi / libx264。强制指定但跑不了时自动回退。
var encoder_pref := "auto"
var _running := false
var _cancel := false
var _chosen: Dictionary = {}


## 当前机器上能用的编码器（先试一帧，结果缓存）。
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
			if String(cand["name"]) == wanted and listed.has(wanted) and await _smoke(ffmpeg, cand):
				_chosen = cand
				return _chosen
	for cand in _candidates():
		if not listed.has(String(cand["name"])):
			continue
		if await _smoke(ffmpeg, cand):
			_chosen = cand
			return _chosen
	return {}


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
		{"name": "h264_nvenc", "args": ["-c:v", "h264_nvenc", "-preset", "p4", "-rc", "vbr", "-cq", "23", "-pix_fmt", "yuv420p"]},
		{"name": "h264_qsv", "args": ["-c:v", "h264_qsv", "-global_quality", "23", "-pix_fmt", "nv12"]},
		{"name": "h264_videotoolbox", "args": ["-c:v", "h264_videotoolbox", "-q:v", "60", "-pix_fmt", "yuv420p"]},
		{"name": "h264_vaapi", "args": ["-vaapi_device", "/dev/dri/renderD128", "-vf", "format=nv12,hwupload",
			"-c:v", "h264_vaapi", "-qp", "23"]},
		{"name": "libx264", "args": ["-c:v", "libx264", "-preset", "medium", "-crf", "20", "-pix_fmt", "yuv420p"]},
	]


func _ffmpeg() -> String:
	return MediaIO.ffmpeg_exe if MediaIO.has_ffmpeg() else ""


func _list_encoders(ffmpeg: String) -> Dictionary:
	var out: Array = []
	OS.execute(ffmpeg, ["-hide_banner", "-encoders"], out, true, false)
	var text := "\n".join(out)
	var names := {}
	for cand in _candidates():
		names[String(cand["name"])] = text.contains(String(cand["name"]))
	return names


## 用一帧黑图试编码，确认这个编码器在这台机器上真的能出文件。
func _smoke(ffmpeg: String, cand: Dictionary) -> bool:
	var temp := ProjectSettings.globalize_path("user://.encoder_probe.mp4")
	var args: Array = _input_args(Vector2i(256, 256)) + cand["args"] + ["-frames:v", "1", "-y", temp]
	var pipe := OS.execute_with_pipe(ffmpeg, args, false)
	if pipe.is_empty():
		return false
	var stdin: FileAccess = pipe.get("stdio")
	if stdin == null:
		return false
	# 256x256：VAAPI 要求至少 128x128，用小图探测会把它误判成不可用。
	var image := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	image.fill(Color.BLACK)
	await _write_frame(stdin, image.get_data())
	stdin.close()
	var pid := int(pipe.get("pid", -1))
	var deadline := Time.get_ticks_msec() + 6000
	while pid > 0 and OS.is_process_running(pid) and Time.get_ticks_msec() < deadline:
		OS.delay_msec(10)
	var size := FileAccess.get_file_as_bytes(temp).size() if FileAccess.file_exists(temp) else 0
	if FileAccess.file_exists(temp):
		DirAccess.remove_absolute(temp)
	return size > 1024


func _input_args(input_size: Vector2i = SIZE) -> Array:
	return ["-hide_banner", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgba",
		"-s", "%dx%d" % [input_size.x, input_size.y], "-r", str(FPS), "-i", "-"]


## 渲染 [start_ms, end_ms] 到 out_path。events 是 .replay 的事件流（用来画光标）。
func export_chart(chart: Chart, start_ms: float, end_ms: float, out_path: String,
		events: Array = [], show_storyboard: bool = true) -> void:
	if _running or chart == null:
		return
	var encoder: Dictionary = await pick_encoder()
	if encoder.is_empty():
		finished.emit("", "找不到可用的 H.264 编码器（需要外部 ffmpeg）")
		return
	_running = true
	_cancel = false
	var temp := out_path.get_basename() + ".part.mp4"
	var args: Array = _input_args() + encoder["args"] + ["-an", "-y", temp]
	var pipe := OS.execute_with_pipe(_ffmpeg(), args, false)
	if pipe.is_empty():
		_running = false
		finished.emit("", "启动 ffmpeg 失败")
		return
	var stdin: FileAccess = pipe.get("stdio")

	var viewport := SubViewport.new()
	viewport.size = SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var preview := Preview3D.new()
	viewport.add_child(preview)
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview.chart_override = chart
	preview.follow_app = false
	preview.playtest_mode = true
	# 导出的是回放视频：HUD（连击/准度）要进画面，命中特效才有成绩可看。
	preview.show_hud = true
	preview.hud_title = String(chart.metadata.get("title", ""))
	preview.hud_difficulty = String(chart.metadata.get("version", chart.difficulty))
	preview.hud_total_ms = end_ms
	preview.use_3d_ring = true
	preview.mouse_tilt = false
	preview.show_storyboard = show_storyboard
	preview.show_storyboard_background = show_storyboard
	preview.notice.connect(func(_m: String, _l: String) -> void: pass)

	var span := maxf(1.0, end_ms - start_ms)
	var total := maxi(1, int(round(span / 1000.0 * float(FPS))))
	var written := 0
	var empty := 0
	var moves := _move_events(events)
	# 没有移动事件时别画光标：SubViewport 里的“真实鼠标位置”是窗口坐标，会乱飘。
	preview.custom_cursor_visible = not moves.is_empty()
	var hits := plan_hits(chart, events)
	var hit_index := 0
	var combo := 0
	var judged := 0
	var score_sum := 0.0
	preview.hud_combo = 0
	preview.hud_accuracy = -1.0
	var cursor := Vector2.INF
	var move_index := 0
	# 先空转两帧：SubViewport 要渲染过才会分配贴图。
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	for frame in total:
		if _cancel or stdin == null:
			break
		var ms := start_ms + span * float(frame) / float(total)
		cursor = _cursor_at(moves, ms)
		while move_index < moves.size() and float(moves[move_index]["t"]) <= ms:
			move_index += 1
		preview.auto_cursor = cursor if cursor.is_finite() else Vector2.INF
		var beat: float = chart.timing.chart_ms_to_beat(ms + chart.offset_ms)
		# 回放里的按键到点就放命中反馈：爆点 + 环绕闪光 + 连击/准度。
		while hit_index < hits.size() and float(hits[hit_index]["ms"]) <= ms:
			var hit: Dictionary = hits[hit_index]
			preview.set_note_state(hit["note"].id, "hit", beat)
			# 爆点用音符的目标拍：用当前拍会把特效画到环外（音符已经过了落点）。
			preview.add_note_pop(String(hit["kind"]), hit["note"], float(hit["note"].beat))
			preview.add_arc_flash(float(hit["note"].angle), float(hit["note"].arc_width()),
				float(hit["note"].beat), _tier_colour(int(hit["tier"])))
			if int(hit["tier"]) >= 3:
				combo = 0
			else:
				combo += 1
				judged += 1
				score_sum += [1.0, 0.6667, 0.3333, 0.0][clampi(int(hit["tier"]), 0, 3)]
			preview.hud_combo = combo
			preview.hud_accuracy = 100.0 * score_sum / float(maxi(1, judged)) if judged > 0 else -1.0
			preview.hud_ms = ms
			hit_index += 1
		preview.time_beat = beat
		preview.prepare_playtest_frame(beat, 1.0 / float(FPS))
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		if image == null or image.is_empty():
			empty += 1
			continue
		if image.get_format() != Image.FORMAT_RGBA8:
			image.convert(Image.FORMAT_RGBA8)
		if not await _write_frame(stdin, image.get_data()):
			break
		written += 1
		if frame % 30 == 0:
			progress.emit(frame, total)
	stdin.close()
	print("[ve] frames total=%d written=%d empty=%d" % [total, written, empty])
	var pid := int(pipe.get("pid", -1))
	var deadline := Time.get_ticks_msec() + 120000
	while pid > 0 and OS.is_process_running(pid) and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.05).timeout
	viewport.queue_free()
	var err_pipe: FileAccess = pipe.get("stderr")
	if err_pipe != null:
		var err_text := err_pipe.get_as_text().strip_edges()
		if not err_text.is_empty():
			print("[ve] ffmpeg stderr: ", err_text.substr(0, 600))
	_running = false
	if _cancel:
		if FileAccess.file_exists(temp):
			DirAccess.remove_absolute(temp)
		finished.emit("", "已取消")
		return
	if not FileAccess.file_exists(temp) or FileAccess.get_file_as_bytes(temp).size() < 1024:
		finished.emit("", "ffmpeg 没有产出视频（编码器：%s）" % String(encoder["name"]))
		return
	if FileAccess.file_exists(out_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(out_path))
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(temp),
		ProjectSettings.globalize_path(out_path))
	if err != OK:
		finished.emit("", "无法写入 %s" % out_path)
		return
	finished.emit(out_path, "已导出 %s（%s）" % [out_path.get_file(), String(encoder["name"])])


## Godot 的管道写入是非阻塞的：一次丢 3.6MB 会直接失败（EAGAIN）。
## 拆成 4KB 小块、失败就让出一帧等 ffmpeg 抽空，实测 720p60 可以稳定灌满。
## shortcut: 极端满载时仍有极小概率写进半块，靠帧数校验兜底（升级可换 mkfifo）。
func _write_frame(stdin: FileAccess, data: PackedByteArray) -> bool:
	var offset := 0
	var stalls := 0
	while offset < data.size():
		var chunk := data.slice(offset, mini(offset + 4096, data.size()))
		if stdin.store_buffer(chunk):
			offset += chunk.size()
			stalls = 0
			continue
		stalls += 1
		if stalls > 3000:
			return false
		await get_tree().process_frame
	return true


func cancel() -> void:
	_cancel = true


## 把 .replay 里的 press 事件配到谱面音符上（只用于画面反馈，不改成绩文件）。
## 规则和试玩一致：时间在 ±HIT_WINDOW_MS 内、角度落在音符弧宽 + 容差里，先到先得。
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
