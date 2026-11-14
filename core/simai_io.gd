class_name SimaiIO
extends RefCounted

## Simai (maidata.txt) import. Supports tap/hold/slide/break/touch,
## p/q/pp/qq/s/z/V/w shapes, chains, same-head slides and EACH.
## The layout pass in ConvertOptimizer removes one-mouse conflicts.

static var last_error: String = ""
static var last_report: String = ""


static func list_maidata(path: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var text := _read_text(path)
	if text.is_empty():
		return result
	var meta := _metadata(text)
	var keys: Array[int] = []
	for key in meta.keys():
		var name := String(key)
		if name.begins_with("inote_"):
			keys.append(int(name.trim_prefix("inote_")))
	keys.sort()
	for index in keys:
		result.append({
			"index": index,
			"title": String(meta.get("title", "")),
			"artist": String(meta.get("artist", "")),
			"version": "Lv.%s" % String(meta.get("lv_%d" % index, "?")),
			"creator": String(meta.get("des_%d" % index, meta.get("des", ""))),
			"level": String(meta.get("lv_%d" % index, "?")),
		})
	return result


static func import_maidata(path: String, difficulty_index: int = 0) -> Chart:
	last_error = ""
	last_report = ""
	var text := _read_text(path)
	if text.is_empty():
		return null
	var meta := _metadata(text)
	var inote := String(meta.get("inote_%d" % difficulty_index, ""))
	if inote.is_empty():
		# 调用方传错索引时退回第一个可用难度，而不是静默失败。
		for key in meta.keys():
			var name := String(key)
			if name.begins_with("inote_") and not String(meta[key]).is_empty():
				difficulty_index = int(name.trim_prefix("inote_"))
				inote = String(meta[key])
				break
	if inote.is_empty():
		last_error = "maidata.txt 里没有可用的 inote"
		return null
	var chart := Chart.new()
	chart.metadata["title"] = String(meta.get("title", "未命名"))
	chart.metadata["artist"] = String(meta.get("artist", ""))
	chart.metadata["creator"] = String(meta.get("des_%d" % difficulty_index, meta.get("des", "")))
	chart.metadata["version"] = "Lv.%s" % String(meta.get("lv_%d" % difficulty_index, "?"))
	chart.difficulty = String(chart.metadata["version"])
	chart.offset_ms = -float(meta.get("first", "0")) * 1000.0
	var base_bpm := maxf(1.0, float(meta.get("wholebpm", "120")))
	chart.timing.points = [TimingPoint.new(0.0, base_bpm, 4)]
	var counts := {"tap": 0, "hold": 0, "path": 0, "bell": 0, "dropped": 0}
	_parse_notes(inote, chart, counts)
	chart.merge_center_bells()
	var base_dropped := int(counts["dropped"])
	var stats := ConvertOptimizer.optimize_maimai(chart, counts)
	chart.notes.sort_custom(func(a: Note, b: Note) -> bool: return a.beat < b.beat)
	_extract_assets(path, chart)
	var final := {"tap": 0, "hold": 0, "path": 0, "bell": 0}
	for note in chart.notes:
		final[note.type] = int(final.get(note.type, 0)) + 1
	var audio_note := "音频：未找到 track.*" if chart.audio_path.is_empty() else "音频：%s" % chart.audio_path.get_file()
	last_report = "Simai 导入 Lv.%s：Tap %d，Hold %d，Slide→Path %d，Touch→Bell %d，跳过 %d（解析 %d + 优化 %d）。\nBPM %.1f，offset %.0fms，%s。\n优化：同刻去重 %d，尾判吸附 %d，缩短星星 %d，降级 %d，轨外删除 %d，交互段锁定 %d，交互段叠键 %d，逐颗压角 %d，Bell 吸附 %d，扫键段转 Bell %d，同角度降密度 %d。" % [
		String(meta.get("lv_%d" % difficulty_index, "?")),
		final["tap"], final["hold"], final["path"], final["bell"], counts["dropped"],
		base_dropped, stats.get("dropped", 0),
		base_bpm, chart.offset_ms, audio_note,
		stats.get("chords", 0), stats.get("snapped", 0), stats.get("shortened", 0),
		stats.get("degraded", 0), stats.get("off_track", 0),
		stats.get("locked", 0), stats.get("stacked", 0), stats.get("relaxed", 0),
		stats.get("bells_moved", 0), stats.get("swept", 0), stats.get("thinned", 0),
	]
	return chart


static func _read_text(path: String) -> String:
	if DirAccess.dir_exists_absolute(path):
		var inside := path.path_join("maidata.txt")
		if FileAccess.file_exists(inside):
			return FileAccess.get_file_as_string(inside)
		last_error = "文件夹里没有 maidata.txt"
		return ""
	if path.to_lower().ends_with(".zip"):
		var zip := ZIPReader.new()
		if zip.open(path) != OK:
			last_error = "无法打开 zip"
			return ""
		for name in zip.get_files():
			if name.to_lower().ends_with("maidata.txt"):
				var text := zip.read_file(name).get_string_from_utf8()
				zip.close()
				return text
		zip.close()
		last_error = "zip 里没有 maidata.txt"
		return ""
	if not FileAccess.file_exists(path):
		last_error = "文件不存在"
		return ""
	return FileAccess.get_file_as_string(path)


static func _metadata(text: String) -> Dictionary:
	var meta := {}
	var current := ""
	for line in text.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("&") and trimmed.find("=") > 1:
			var eq := trimmed.find("=")
			current = trimmed.substr(1, eq - 1).strip_edges()
			meta[current] = trimmed.substr(eq + 1)
			continue
		if not current.is_empty():
			# maidata 的 inote 是多行值，直到下一个 &key= 为止。
			meta[current] = String(meta.get(current, "")) + "\n" + line
	return meta


static func _parse_notes(inote: String, chart: Chart, counts: Dictionary) -> void:
	var beat := 0.0
	var slot := 1.0
	var bpm := chart.timing.bpm_at(0.0)
	var tokens := inote.replace("\r", "").split(",")
	for raw in tokens:
		var token := String(raw).strip_edges()
		token = token.split("||")[0].strip_edges()
		if token == "E":
			break
		while token.begins_with("("):
			var close := token.find(")")
			if close < 0:
				break
			bpm = maxf(1.0, float(token.substr(1, close - 1)))
			if absf(chart.timing.bpm_at(beat) - bpm) > 0.001:
				chart.timing.points.append(TimingPoint.new(beat, bpm, 4))
			token = token.substr(close + 1).strip_edges()
		while token.begins_with("{"):
			var close := token.find("}")
			if close < 0:
				break
			var inner := token.substr(1, close - 1).strip_edges()
			if inner.begins_with("#"):
				# {#0.35} 是秒，不是拍。
				slot = maxf(0.01, float(inner.substr(1))) * bpm / 60.0
			else:
				slot = 4.0 / maxf(0.01, float(inner))
			token = token.substr(close + 1).strip_edges()
		if token.is_empty():
			beat += slot
			continue
		var parsed := _parse_token(token, beat, bpm, chart)
		if parsed.is_empty():
			counts["dropped"] += 1
		for note in parsed:
			note.id = chart.next_note_id()
			chart.notes.append(note)
			match note.type:
				"tap": counts["tap"] += 1
				"hold": counts["hold"] += 1
				"path": counts["path"] += 1
				"bell": counts["bell"] += 1
		beat += slot


## 一个逗号里的内容：EACH 用 / 分隔，同头多星用 * 分隔。
static func _parse_token(token: String, beat: float, bpm: float, chart: Chart) -> Array[Note]:
	var result: Array[Note] = []
	for piece in _split_outside(token, "/"):
		var part := String(piece).strip_edges()
		if part.is_empty():
			continue
		result.append_array(_parse_star_group(part, beat, bpm, chart))
	return result


static func _parse_star_group(token: String, beat: float, bpm: float, chart: Chart) -> Array[Note]:
	var parts := _split_outside(token, "*")
	if parts.size() <= 1:
		var note := _parse_single(token, beat, bpm, chart, -1)
		return [note] if note != null else []
	var head := _head_button(String(parts[0]))
	if head < 1 or head > 8:
		return []
	var result: Array[Note] = []
	for i in parts.size():
		var part := String(parts[i]).strip_edges()
		if part.is_empty():
			continue
		var note := _parse_single(part, beat, bpm, chart, head)
		if note != null:
			result.append(note)
	return result


static func _parse_single(token: String, beat: float, bpm: float, chart: Chart, shared_head: int) -> Note:
	var body := token
	var timing := ""
	var open := token.rfind("[")
	if open >= 0:
		var close := token.find("]", open)
		if close > open:
			timing = token.substr(open, close - open + 1)
			body = token.substr(0, open) + token.substr(close + 1)
	body = body.replace("x", "").replace("f", "").strip_edges()
	if body.is_empty():
		return null
	var first := body.substr(0, 1)
	if first in ["A", "B", "C", "D", "E"]:
		return _parse_touch(body, beat)
	var head := shared_head if shared_head > 0 else _digit_at(body, 0)
	if head < 1 or head > 8:
		return null
	var rest := body
	if rest.begins_with(str(head)):
		rest = rest.substr(1)
	# Hold：h 出现在按钮后，且去掉 h 后没有形状字符。
	if rest.contains("h") and not _has_shape(rest.replace("h", "")):
		var hold_time := _parse_timing(timing, bpm)
		var hold := Note.new("hold", beat, SimaiSlide.button_angle(head), 62.0)
		hold.end_beat = beat + maxf(0.25, float(hold_time["move"]))
		hold.hold = true
		hold.hold_style = "straight"
		if body.contains("b"):
			hold.width = 72.0
		return hold
	var segments := _parse_segments(rest, head, bpm)
	if segments.is_empty():
		var tap := Note.new("tap", beat, SimaiSlide.button_angle(head), 62.0)
		if body.contains("b"):
			tap.width = 72.0
		return tap
	var timing_data := _parse_timing(timing, bpm)
	var wait := maxf(0.0, float(timing_data["wait"]))
	var move := maxf(0.0, float(timing_data["move"]))
	# 链式星星自带每段时长时，用它们的和。
	var explicit := 0.0
	for segment in segments:
		explicit += float(segment.get("time", 0.0))
	if explicit > move:
		move = explicit
	var points := SimaiSlide.build(head, segments)
	if points.size() < 2:
		return null
	var note := Note.new("path", beat, SimaiSlide.button_angle(head), 62.0)
	note.wait_beat = wait
	note.end_beat = beat + wait + move
	note.tail_angle = SimaiSlide.button_angle(int(segments[-1]["end"]))
	note.tail_width = 52.0
	note.tolerance = 0.24
	note.samples_per_beat = 4.0
	note.space = "plane"
	note.trace_pts = _trace_from_points(points, wait, move)
	if body.contains("b"):
		note.tail_width = 72.0
	return note


## 形状链：1-4q7-2 / 1V35 / 1w5 / 1pp5……
static func _parse_segments(text: String, head: int, bpm: float) -> Array[Dictionary]:
	var segments: Array[Dictionary] = []
	var i := 0
	var current := head
	while i < text.length():
		var shape := ""
		var pair := text.substr(i, 2)
		if pair in ["pp", "qq"]:
			shape = pair
			i += 2
		else:
			var ch := text.substr(i, 1)
			if ch in ["-", "^", "<", ">", "v", "p", "q", "s", "z", "V", "w"]:
				shape = ch
				i += 1
			else:
				i += 1
				continue
		var segment_time := 0.0
		if i < text.length() and text.substr(i, 1) == "[":
			var close := text.find("]", i)
			if close > i:
				var bracket := text.substr(i, close - i + 1)
				segment_time = float(_parse_timing(bracket, bpm)["move"])
				i = close + 1
		if shape == "V":
			if i + 1 >= text.length():
				break
			var via := int(text.substr(i, 1))
			var end := int(text.substr(i + 1, 1))
			if end < 1 or end > 8:
				break
			i += 2
			segments.append({"shape": shape, "end": end, "via": via, "time": segment_time})
			current = end
		else:
			if i >= text.length():
				break
			var end_text := text.substr(i, 1)
			if not end_text.is_valid_int():
				break
			var end := int(end_text)
			if end < 1 or end > 8:
				break
			i += 1
			segments.append({"shape": shape, "end": end, "time": segment_time})
			current = end
	return segments


static func _parse_touch(body: String, beat: float) -> Note:
	var group := body.substr(0, 1)
	var digit := 0
	if body.length() > 1 and body.substr(1, 1).is_valid_int():
		digit = int(body.substr(1, 1))
	var angle := 0.0
	var radius := 0.0
	match group:
		"C":
			# 圆心触先标成半径 0；解析完后由 Chart.merge_center_bells 并到外环并继承角度。
			angle = 0.0
			radius = 0.0
		# 键鼠只有一只光标：A/B/D/E 全部落外圈，连续 Touch 才能沿同一个圆扫过去。
		"A":
			if digit < 1 or digit > 8:
				return null
			angle = SimaiSlide.button_angle(digit)
			radius = 1.0
		"B":
			if digit < 1 or digit > 8:
				return null
			angle = SimaiSlide.button_angle(digit)
			radius = 1.0
		"D":
			if digit < 1 or digit > 8:
				return null
			angle = fposmod(SimaiSlide.button_angle(digit) - 22.5, 360.0)
			radius = 1.0
		"E":
			if digit < 1 or digit > 8:
				return null
			angle = fposmod(SimaiSlide.button_angle(digit) - 22.5, 360.0)
			radius = 1.0
		_:
			return null
	var bell := Note.new("bell", beat, angle, Note.BELL_MAX_WIDTH)
	bell.center_u = fposmod(angle, 360.0) / 360.0
	bell.bell_radius = radius
	bell.radius = 50.0
	bell.end_beat = beat
	return bell


## [x:y] = x 分音符 y 个；[#0.5] = 秒；[a#b:c] = 用 a BPM；
## [w##m] = w 秒后开始、再滑 m；[w##a#b:c] = w 秒后按 a BPM 滑。
static func _parse_timing(bracket: String, chart_bpm: float) -> Dictionary:
	if bracket.is_empty():
		return {"wait": 1.0, "move": 1.0}
	var inner := bracket.trim_prefix("[").trim_suffix("]")
	if inner.is_empty():
		return {"wait": 1.0, "move": 1.0}
	var parts := inner.split("#")
	if parts.size() >= 3:
		var wait_seconds := float(parts[0]) if not parts[0].is_empty() else 0.0
		var wait := wait_seconds * chart_bpm / 60.0 if wait_seconds > 0.0 else 1.0
		var move_bpm := chart_bpm
		if parts.size() >= 4 and not parts[-2].is_empty():
			move_bpm = float(parts[-2])
		elif parts.size() == 3 and not parts[1].is_empty():
			move_bpm = float(parts[1])
		return {"wait": wait, "move": _beat_span(parts[-1], move_bpm, chart_bpm)}
	if parts.size() == 2:
		if parts[0].is_empty():
			return {"wait": 1.0, "move": _beat_span(parts[1], chart_bpm, chart_bpm)}
		var move_bpm := maxf(1.0, float(parts[0]))
		return {"wait": chart_bpm / move_bpm, "move": _beat_span(parts[1], move_bpm, chart_bpm)}
	return {"wait": 1.0, "move": _beat_span(inner, chart_bpm, chart_bpm)}


## 统一换成谱面拍数：x:y 按 move_bpm 折算，纯数字是秒。
static func _beat_span(spec: String, move_bpm: float, chart_bpm: float) -> float:
	if spec.contains(":"):
		var pieces := spec.split(":")
		var division := maxf(0.01, float(pieces[0]))
		var count := float(pieces[1]) if pieces.size() > 1 else 1.0
		return 4.0 * count / division * chart_bpm / maxf(1.0, move_bpm)
	return maxf(0.0, float(spec)) * chart_bpm / 60.0


## 按弧长匀速分配时间；开头留出 wait 拍原地不动。
static func _trace_from_points(points: Array[Vector2], wait: float, move: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if points.is_empty():
		return result
	var distances: Array[float] = [0.0]
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i].distance_to(points[i - 1])
		distances.append(total)
	total = maxf(0.0001, total)
	var safe_move := maxf(0.001, move)
	result.append({"x": points[0].x, "y": points[0].y, "db": 0.0})
	if wait > 0.0:
		result.append({"x": points[0].x, "y": points[0].y, "db": wait})
	for i in range(1, points.size()):
		result.append({"x": points[i].x, "y": points[i].y, "db": wait + safe_move * distances[i] / total})
	return result


static func _split_outside(text: String, separator: String) -> Array[String]:
	var result: Array[String] = []
	var depth := 0
	var start := 0
	for i in text.length():
		var ch := text.substr(i, 1)
		if ch == "[":
			depth += 1
		elif ch == "]":
			depth = maxi(0, depth - 1)
		elif ch == separator and depth == 0:
			result.append(text.substr(start, i - start))
			start = i + 1
	result.append(text.substr(start))
	return result


static func _head_button(token: String) -> int:
	var digit := _digit_at(token, 0)
	return digit if digit >= 1 and digit <= 8 else 0


static func _digit_at(text: String, index: int) -> int:
	if index < text.length() and text.substr(index, 1).is_valid_int():
		return int(text.substr(index, 1))
	return -1


static func _has_shape(text: String) -> bool:
	for ch in text:
		if ch in ["-", "^", "<", ">", "v", "p", "q", "s", "z", "V", "w"]:
			return true
	return false


## 同一个 zip（路径 + 大小 + 修改时间）固定落到同一个目录，重复导入直接复用。
static func _zip_import_folder(path: String) -> String:
	var size := 0
	var file := FileAccess.open(path, FileAccess.READ)
	if file != null:
		size = file.get_length()
		file.close()
	var key := "%s|%d|%d" % [path, FileAccess.get_modified_time(path), size]
	return "user://imports/simai_zip_%d/" % (absi(key.hash()) % 1000000000)


static func _extract_assets(path: String, chart: Chart) -> void:
	var folder := ""
	if path.to_lower().ends_with(".zip"):
		var zip := ZIPReader.new()
		if zip.open(path) != OK:
			return
		var names := zip.get_files()
		# 同一个压缩包只解一次：导入整个难度组时以前会每个难度都复制 20MB+ 并重跑 ffmpeg。
		folder = _zip_import_folder(path)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
		for name in names:
			var lower := name.to_lower()
			var target := ""
			if lower.ends_with("track.mp3") or lower.ends_with("track.ogg") or lower.ends_with("track.wav"):
				target = folder + "track" + lower.substr(lower.rfind("."))
				chart.audio_path = target
			elif lower.ends_with("bg.png") or lower.ends_with("bg.jpg"):
				target = folder + "bg" + lower.substr(lower.rfind("."))
				chart.metadata["background"] = target
			elif lower.ends_with("pv.mp4"):
				target = folder + "pv.mp4"
				chart.video_path = target
			if target.is_empty() or FileAccess.file_exists(target):
				continue
			var data := zip.read_file(name)
			var file := FileAccess.open(target, FileAccess.WRITE)
			if file != null:
				file.store_buffer(data)
				file.close()
		zip.close()
		# mp3 → ogg 以前在这里同步跑 ffmpeg，导入整包时会冻结界面；
		# 现在导入完由主窗口带着进度条异步转（见 Main._prepare_import_media）。
		return
	# 直接选择 maidata.txt 或解压后的文件夹时，直接用同目录的 track 文件，不复制。
	folder = path.get_base_dir() if not DirAccess.dir_exists_absolute(path) else path
	for name in ["track.ogg", "track.mp3", "track.wav", "track.flac", "track.m4a"]:
		var candidate := folder.path_join(name)
		if FileAccess.file_exists(candidate):
			chart.audio_path = candidate
			break
	for name in ["bg.jpg", "bg.png"]:
		var candidate := folder.path_join(name)
		if FileAccess.file_exists(candidate):
			chart.metadata["background"] = candidate
			break
	for name in ["pv.mp4", "pv.webm"]:
		var candidate := folder.path_join(name)
		if FileAccess.file_exists(candidate):
			chart.video_path = candidate
			break


static func _polyline_self_intersects(points: Array[Vector2]) -> bool:
	if points.size() < 4:
		return false
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		for j in range(i + 2, points.size() - 1):
			var hit = Geometry2D.segment_intersects_segment(a, b, points[j], points[j + 1])
			if hit != null:
				return true
	return false
