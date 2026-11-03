class_name SimaiIO
extends RefCounted

## Simai (maidata.txt) import. Supports the common tap/hold/slide/break/touch
## subset; V/wifi/p/q shapes are approximated as arcs and reported.

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
	chart.metadata["slide_mode"] = "maimai"
	var base_bpm := maxf(1.0, float(meta.get("wholebpm", "120")))
	chart.timing.points = [TimingPoint.new(0.0, base_bpm, 4)]
	var counts := {"tap": 0, "hold": 0, "path": 0, "bell": 0, "dropped": 0}
	_parse_notes(inote, chart, counts)
	_remove_chords(chart, counts)
	_clamp_holds(chart, counts)
	_resolve_path_overlaps(chart, counts)
	_resolve_conflicts(chart, counts)
	chart.notes.sort_custom(func(a: Note, b: Note) -> bool: return a.beat < b.beat)
	_extract_assets(path, chart)
	var audio_note := "音频：未找到 track.*" if chart.audio_path.is_empty() else "音频：%s" % chart.audio_path.get_file()
	last_report = "Simai 导入 Lv.%s：Tap %d，Hold %d，Slide→Path %d，Touch→Bell %d，跳过 %d。\nBPM %.1f，offset %.0fms，%s。" % [
		String(meta.get("lv_%d" % difficulty_index, "?")),
		counts["tap"], counts["hold"], counts["path"], counts["bell"], counts["dropped"],
		base_bpm, chart.offset_ms, audio_note,
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
	var previous_angle := 0.0
	for raw in tokens:
		var token := String(raw).strip_edges()
		token = token.split("||")[0].strip_edges()
		if token == "E":
			break
		var had_directive := false
		while token.begins_with("("):
			var close := token.find(")")
			if close < 0:
				break
			bpm = maxf(1.0, float(token.substr(1, close - 1)))
			if absf(chart.timing.bpm_at(beat) - bpm) > 0.001:
				chart.timing.points.append(TimingPoint.new(beat, bpm, 4))
			token = token.substr(close + 1).strip_edges()
			had_directive = true
		while token.begins_with("{"):
			var close := token.find("}")
			if close < 0:
				break
			var inner := token.substr(1, close - 1).strip_edges()
			if inner.begins_with("#"):
				slot = maxf(0.01, float(inner.substr(1)))
			else:
				slot = 4.0 / maxf(0.01, float(inner))
			token = token.substr(close + 1).strip_edges()
			had_directive = true
		if token.is_empty():
			# 只有指令的 token 仍然占一个空格；之前不推进会让整张谱提前 4 拍。
			beat += slot
			continue
		if token.contains("*"):
			var branches := token.split("*")
			var head := String(branches[0]).strip_edges().substr(0, 1)
			var best: Note = null
			for i in branches.size():
				var part := String(branches[i]).strip_edges()
				if i > 0 and not part.begins_with(head):
					part = head + part
				var branch := _parse_note(part, beat, bpm)
				if branch != null and (best == null or branch.duration() > best.duration()):
					best = branch
				elif branch != null:
					counts["dropped"] += 1
			if best != null:
				best.id = chart.next_note_id()
				chart.notes.append(best)
				previous_angle = best.angle
				match best.type:
					"tap": counts["tap"] += 1
					"hold": counts["hold"] += 1
					"path": counts["path"] += 1
					"bell": counts["bell"] += 1
			beat += slot
			continue
		var pieces := token.split("/")
		var parsed_at_beat: Array[Note] = []
		for piece in pieces:
			var note := _parse_note(String(piece).strip_edges(), beat, bpm)
			if note == null:
				counts["dropped"] += 1
				continue
			parsed_at_beat.append(note)
		if parsed_at_beat.size() > 1:
			# 只保留与上一个 note 流向更连续的一侧。
			var keeper := parsed_at_beat[0]
			var best := absf(_short_delta(previous_angle, keeper.angle))
			for i in range(1, parsed_at_beat.size()):
				var candidate := parsed_at_beat[i]
				var distance := absf(_short_delta(previous_angle, candidate.angle))
				if distance < best:
					best = distance
					keeper = candidate
			parsed_at_beat = [keeper]
			counts["dropped"] += pieces.size() - 1
		for note in parsed_at_beat:
			note.id = chart.next_note_id()
			chart.notes.append(note)
			previous_angle = note.angle
			match note.type:
				"tap": counts["tap"] += 1
				"hold": counts["hold"] += 1
				"path": counts["path"] += 1
				"bell": counts["bell"] += 1
		beat += slot


static func _parse_note(token: String, beat: float, bpm: float) -> Note:
	if token.is_empty():
		return null
	var first := token.substr(0, 1)
	if first in ["A", "B", "C", "D", "E"]:
		# 触摸区 → Bell；中心 C 没有环上角度，跳过。
		var digit := 0
		if token.length() > 1 and token.substr(1, 1).is_valid_int():
			digit = int(token.substr(1, 1))
		if first == "C" or digit == 0:
			return null
		var bell := Note.new("bell", beat, fposmod(_button_angle(digit), 360.0), 45.0)
		bell.center_u = fposmod(_button_angle(digit), 360.0) / 360.0
		bell.radius = 50.0
		bell.end_beat = beat
		return bell
	if not first.is_valid_int():
		return null
	var start_button := int(first)
	if start_button < 1 or start_button > 8:
		return null
	var start_angle := _button_angle(start_button)
	var duration := _duration_beats(token, bpm)
	var is_slide := false
	for mark in ["-", "^", "<", ">", "v", "p", "q", "s", "z", "V", "w"]:
		if token.find(mark) > 0:
			is_slide = true
			break
	if is_slide:
		var end_button := _end_button(token)
		if end_button < 1 or end_button > 8 or end_button == start_button:
			return null
		var delta := _short_delta(start_angle, _button_angle(end_button))
		if token.find(">") > 0:
			delta = -absf(delta)
		elif token.find("<") > 0:
			delta = absf(delta)
		var note := Note.new("path", beat, fposmod(start_angle, 360.0), 62.0)
		note.end_beat = beat + 1.0 + maxf(0.25, duration)
		note.wait_beat = 1.0
		note.tail_angle = fposmod(start_angle + delta, 360.0)
		note.tail_width = 52.0
		note.tolerance = 0.24
		note.samples_per_beat = 4.0
		note.space = "plane"
		var mid_angle := NAN
		if token.contains("v") or token.contains("V") or token.contains("w") or token.contains("p") or token.contains("q") or token.contains("s") or token.contains("z"):
			var digits := ""
			for ch in token.split("[")[0]:
				if ch.is_valid_int():
					digits += ch
			var turn := int(digits.substr(1, 1)) if digits.length() >= 3 else 0
			if turn > 0:
				mid_angle = _button_angle(turn)
		note.trace_pts = _plane_slide_points(
			start_angle, note.tail_angle, note.wait_beat,
			note.end_beat - note.beat, mid_angle
		)
		return note
	if token.find("h") >= 0:
		var hold := Note.new("hold", beat, fposmod(start_angle, 360.0), 62.0)
		hold.end_beat = beat + maxf(0.25, duration)
		hold.hold = true
		return hold
	var tap := Note.new("tap", beat, fposmod(start_angle, 360.0), 62.0)
	if token.find("b") >= 0:
		tap.width = 72.0
	return tap


static func _plane_slide_points(head_angle: float, tail_angle: float, wait: float, total: float, mid_angle: float = NAN) -> Array[Dictionary]:
	var head := Vector2(cos(deg_to_rad(head_angle)), sin(deg_to_rad(head_angle)))
	var tail := Vector2(cos(deg_to_rad(tail_angle)), sin(deg_to_rad(tail_angle))) * 0.70
	var control_angle := head_angle + _short_delta(head_angle, tail_angle) * 0.5 if is_nan(mid_angle) else mid_angle
	var control := Vector2(cos(deg_to_rad(control_angle)), sin(deg_to_rad(control_angle))) * 0.84
	var result: Array[Dictionary] = [{"x": head.x, "y": head.y, "db": 0.0}]
	if wait > 0.0:
		result.append({"x": head.x, "y": head.y, "db": wait})
	var move := maxf(0.001, total - wait)
	for i in 25:
		var q := float(i) / 24.0
		var inverse := 1.0 - q
		var point := head * inverse * inverse + control * 2.0 * inverse * q + tail * q * q
		result.append({"x": point.x, "y": point.y, "db": wait + move * q})
	return result


static func _duration_beats(token: String, bpm: float) -> float:
	var open := token.find("[")
	var close := token.find("]")
	if open < 0 or close < open:
		return 0.0
	var inner := token.substr(open + 1, close - open - 1)
	if inner.begins_with("#") and inner.count("#") == 1 and not inner.contains(":"):
		return maxf(0.0, float(inner.substr(1))) * bpm / 60.0
	var parts := inner.split("#")
	var timing := parts[-1]
	if timing.contains(":"):
		var pieces := timing.split(":")
		var division := maxf(0.01, float(pieces[0]))
		var count := float(pieces[1])
		return 4.0 * count / division
	return maxf(0.0, float(timing)) * bpm / 60.0


static func _end_button(token: String) -> int:
	var end := token.find("[")
	var head := token if end < 0 else token.substr(0, end)
	head = head.replace("x", "").replace("b", "").replace("f", "")
	for i in range(head.length() - 1, 0, -1):
		var c := head.substr(i, 1)
		if c.is_valid_int():
			return int(c)
	return 0


static func _button_angle(button: int) -> float:
	# maimai 1 在正上方，顺时针编号；设计坐标 y 向上。
	return fposmod(90.0 - float(button - 1) * 45.0, 360.0)


static func _short_delta(from_angle: float, to_angle: float) -> float:
	return fposmod(to_angle - from_angle + 180.0, 360.0) - 180.0


static func _remove_chords(chart: Chart, counts: Dictionary) -> void:
	var by_beat := {}
	for note in chart.notes:
		var key := snappedf(note.beat, 0.001)
		if not by_beat.has(key):
			by_beat[key] = []
		by_beat[key].append(note)
	for key in by_beat.keys():
		var group: Array = by_beat[key]
		if group.size() <= 1:
			continue
		group.sort_custom(func(a: Note, b: Note) -> bool: return a.id < b.id)
		var keep: Note = group[0]
		for i in range(1, group.size()):
			var note: Note = group[i]
			chart.notes.erase(note)
			counts["dropped"] += 1


static func _clamp_holds(chart: Chart, counts: Dictionary) -> void:
	var ordered := chart.sorted_notes()
	for i in ordered.size():
		var note := ordered[i]
		if note.type != "hold":
			continue
		var next_beat := INF
		for j in range(i + 1, ordered.size()):
			if ordered[j].beat > note.beat + 0.0001:
				next_beat = ordered[j].beat
				break
		var limit := next_beat - 0.0625
		if limit < note.end_beat:
			note.end_beat = limit
		if note.end_beat - note.beat < 0.5:
			# 无法安全长按的短 Hold 降级为 Tap，避免 Hold+Tap 必须双手。
			note.type = "tap"
			note.end_beat = note.beat
			counts["hold"] -= 1
			counts["tap"] += 1


static func _extract_assets(path: String, chart: Chart) -> void:
	var folder := ""
	if path.to_lower().ends_with(".zip"):
		var zip := ZIPReader.new()
		if zip.open(path) != OK:
			return
		var names := zip.get_files()
		folder = "user://imports/simai_%d/" % Time.get_unix_time_from_system()
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
			if target.is_empty():
				continue
			var data := zip.read_file(name)
			var file := FileAccess.open(target, FileAccess.WRITE)
			if file != null:
				file.store_buffer(data)
				file.close()
		zip.close()
		if not chart.audio_path.is_empty() and chart.audio_path.get_extension().to_lower() != "ogg":
			# MP3 在部分音频驱动/解码器上会静音；解包时转成 OGG 更稳。
			var ogg_path := folder + "track.ogg"
			var output: Array = []
			var code := OS.execute("ffmpeg", ["-y", "-i", ProjectSettings.globalize_path(chart.audio_path), "-vn", "-acodec", "libvorbis", "-q:a", "5", ProjectSettings.globalize_path(ogg_path)], output, true, false)
			if code == 0 and FileAccess.file_exists(ogg_path):
				chart.audio_path = ogg_path
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


static func _resolve_path_overlaps(chart: Chart, counts: Dictionary) -> void:
	# Path 尾拍与其他目标同刻且角度不重合时，删掉另一侧，保证单手可打。
	var remove: Array[Note] = []
	for path in chart.notes:
		if path.type != "path" or remove.has(path):
			continue
		for other in chart.notes:
			if other == path or remove.has(other):
				continue
			if not other.type in ["tap", "hold", "path"]:
				continue
			if absf(other.beat - path.end_beat) > 0.001:
				continue
			if other.type == "path":
				if other.duration() >= path.duration():
					remove.append(path)
				else:
					remove.append(other)
			else:
				remove.append(other)
	for note in remove:
		chart.notes.erase(note)
		counts["dropped"] += 1


static func _resolve_conflicts(chart: Chart, counts: Dictionary) -> void:
	# 同刻目标角度不重合时只保留最宽的一侧，保证单手可打。
	for _pass in 6:
		var by_beat := {}
		for note in chart.notes:
			if note.type in ["tap", "hold", "path"]:
				var key := snappedf(note.beat, 0.001)
				if not by_beat.has(key):
					by_beat[key] = []
				by_beat[key].append({"note": note, "angle": note.angle, "width": note.width})
			if note.type == "path":
				var tail_key := snappedf(note.end_beat, 0.001)
				if not by_beat.has(tail_key):
					by_beat[tail_key] = []
				by_beat[tail_key].append({"note": note, "angle": note.tail_angle, "width": note.tail_width})
		var remove: Array[Note] = []
		for key in by_beat.keys():
			var events: Array = by_beat[key]
			if events.size() <= 1:
				continue
			var lists: Array = []
			for event in events:
				lists.append(JudgeMath.interval(float(event["angle"]), float(event["width"])))
			if not JudgeMath.intersect_all(lists).is_empty():
				continue
			events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["width"]) > float(b["width"]))
			var keeper: Note = events[0]["note"]
			for event in events:
				var note: Note = event["note"]
				if note != keeper and not remove.has(note):
					remove.append(note)
		if remove.is_empty():
			return
		for note in remove:
			chart.notes.erase(note)
			counts["dropped"] += 1
