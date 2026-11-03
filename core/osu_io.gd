class_name OsuIO
extends RefCounted

static var last_error: String = ""

const TAIKO_STACK_GAP := 0.32
const STD_MAX_DEG_PER_SEC := 360.0
const STD_STREAM_COMPRESSION := 0.55
const STD_JUMP_COMPRESSION := 0.75
const STD_JUMP_DISTANCE := 128.0
const STD_PATH_MAX_SPAN := 180.0


static func list_osz_difficulties(path: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var zip := ZIPReader.new()
	if zip.open(path) != OK:
		last_error = "无法打开 .osz：%s" % path
		return result
	for name in zip.get_files():
		if name.get_extension().to_lower() != "osu":
			continue
		var text := zip.read_file(name).get_string_from_utf8()
		var meta := _read_osu_meta(text)
		result.append({
			"index": result.size(),
			"file": name,
			"title": String(meta.get("title", name.get_file().get_basename())),
			"artist": String(meta.get("artist", "")),
			"creator": String(meta.get("creator", "")),
			"version": String(meta.get("version", "")),
			"mode": int(meta.get("mode", 0)),
		})
	zip.close()
	return result


static func _read_osu_meta(text: String) -> Dictionary:
	var result := {"mode": 0, "title": "", "artist": "", "creator": "", "version": ""}
	var section := ""
	for raw_line in text.split("\n"):
		var line := raw_line.strip_edges()
		if line.begins_with("[") and line.ends_with("]"):
			section = line.substr(1, line.length() - 2)
			continue
		if line.is_empty() or line.begins_with("//"):
			continue
		var split := line.split(":", true, 1)
		if split.size() < 2:
			continue
		var key := split[0].strip_edges()
		var value := split[1].strip_edges()
		match section:
			"General":
				if key == "Mode":
					result["mode"] = int(value)
			"Metadata":
				match key:
					"Title":
						result["title"] = value
					"Artist":
						result["artist"] = value
					"Creator":
						result["creator"] = value
					"Version":
						result["version"] = value
	return result


static func import_osz(path: String, difficulty_index: int = 0) -> Dictionary:
	last_error = ""
	var zip := ZIPReader.new()
	if zip.open(path) != OK:
		last_error = "无法打开 .osz：%s" % path
		return {}
	var files := zip.get_files()
	var charts: Array[String] = []
	for name in files:
		if name.get_extension().to_lower() == "osu":
			charts.append(name)
	if charts.is_empty():
		zip.close()
		last_error = ".osz 中没有 .osu 文件"
		return {}
	if difficulty_index < 0 or difficulty_index >= charts.size():
		difficulty_index = 0
	var chosen := charts[difficulty_index]
	var text := zip.read_file(chosen).get_string_from_utf8()
	if text.is_empty():
		zip.close()
		last_error = "无法读取 %s" % chosen
		return {}
	var parsed := parse_osu(text, path.get_file())
	if parsed.is_empty():
		zip.close()
		last_error = "解析失败：%s" % last_error
		return {}
	var chart: Chart = parsed["chart"]
	var report: Array[String] = parsed["report"]
	if charts.size() > 1:
		report.append("压缩包内有 %d 个难度，已导入第 %d 个：%s" % [charts.size(), difficulty_index + 1, chosen])
	report.append_array(_extract_assets(zip, files, chart, chosen))
	zip.close()
	chart.refresh_ids()
	report.append("完成：%d 个音符，%d 个 BPM 点，offset %.0f ms" % [chart.notes.size(), chart.timing.points.size(), chart.offset_ms])
	return {"chart": chart, "report": "\n".join(report)}


static func parse_osu(text: String, source_name: String = "") -> Dictionary:
	last_error = ""
	var clean := text.strip_edges()
	if clean.begins_with("\ufeff"):
		clean = clean.trim_prefix("\ufeff")
	var lines := clean.split("\n")
	if lines.is_empty() or not lines[0].strip_edges().begins_with("osu file format v"):
		last_error = "不是 .osu 文件"
		return {}
	var section := ""
	var general: Dictionary = {}
	var metadata: Dictionary = {}
	var difficulty: Dictionary = {}
	var timing_raw: Array[Dictionary] = []
	var objects_raw: Array[Dictionary] = []
	var events: Array[String] = []
	for raw_line in lines:
		var line := raw_line.strip_edges()
		if line.is_empty() or line.begins_with("//"):
			continue
		if line.begins_with("[") and line.ends_with("]"):
			section = line.substr(1, line.length() - 2)
			continue
		if section in ["General", "Metadata", "Difficulty"]:
			var split := line.split(":", true, 1)
			if split.size() < 2:
				continue
			var key := split[0].strip_edges()
			var value := split[1].strip_edges()
			if section == "General":
				general[key] = value
			elif section == "Metadata":
				metadata[key] = value
			else:
				difficulty[key] = value
		elif section == "TimingPoints":
			var parts := line.split(",")
			if parts.size() < 2:
				continue
			var entry := {
				"time": float(parts[0]),
				"beat_length": float(parts[1]),
				"meter": int(float(parts[2])) if parts.size() > 2 else 4,
				"uninherited": int(float(parts[6])) if parts.size() > 6 else 1,
			}
			timing_raw.append(entry)
		elif section == "Events":
			events.append(line)
		elif section == "HitObjects":
			var fields := line.split(",")
			if fields.size() < 5:
				continue
			objects_raw.append({
				"x": float(fields[0]),
				"y": float(fields[1]),
				"time": float(fields[2]),
				"type": int(fields[3]),
				"hit_sound": int(fields[4]),
				"fields": fields,
			})
	var mode := int(general.get("Mode", "0"))
	if mode != 0 and mode != 1:
		last_error = "只支持 osu!std 和 osu!taiko，当前 Mode=%d" % mode
		return {}
	var slider_multiplier := float(difficulty.get("SliderMultiplier", "1.4"))
	slider_multiplier = maxf(slider_multiplier, 0.1)
	var circle_size := float(difficulty.get("CircleSize", "5"))
	var circle_radius := clampf(54.4 - 4.48 * circle_size, 8.0, 64.0)
	var meta := {
		"title": String(metadata.get("Title", metadata.get("TitleUnicode", source_name.get_basename()))),
		"artist": String(metadata.get("Artist", metadata.get("ArtistUnicode", ""))),
		"creator": String(metadata.get("Creator", "")),
		"version": String(metadata.get("Version", "Imported")),
		"tags": String(metadata.get("Tags", "")),
		"license": "",
		"audio": "",
		"bpm": 120.0,
		"difficulty": String(metadata.get("Version", "Imported")),
	}
	var chart := DemoChart.make_empty(meta)
	chart.timing.points.clear()
	var red_points: Array[Dictionary] = []
	for entry in timing_raw:
		if int(entry["uninherited"]) == 1 and float(entry["beat_length"]) > 0.0:
			red_points.append(entry)
	red_points.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["time"]) < float(b["time"]))
	if red_points.is_empty():
		chart.timing.points.append(TimingPoint.new(0.0, 120.0, 4))
		chart.offset_ms = 0.0
		chart.timing.offset_ms = 0.0
	else:
		var first_time: float = float(red_points[0]["time"])
		var previous_time := first_time
		var previous_beat_length: float = float(red_points[0]["beat_length"])
		var beat := 0.0
		for i in red_points.size():
			var entry: Dictionary = red_points[i]
			if i > 0:
				beat += (float(entry["time"]) - previous_time) / maxf(0.001, previous_beat_length)
				previous_time = float(entry["time"])
				previous_beat_length = float(entry["beat_length"])
			chart.timing.points.append(TimingPoint.new(
				beat,
				60000.0 / maxf(0.001, float(entry["beat_length"])),
				maxi(1, int(entry["meter"]))
			))
		chart.offset_ms = -first_time
		chart.timing.offset_ms = chart.offset_ms
	chart.timing.sort_points()
	var report: Array[String] = []
	report.append("来源：%s" % source_name)
	report.append("模式：%s" % ("osu!taiko" if mode == 1 else "osu!std"))
	report.append("BPM 点：%d；offset：%.0f ms；SliderMultiplier：%.2f" % [chart.timing.points.size(), chart.offset_ms, slider_multiplier])
	objects_raw.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["time"]) < float(b["time"]))
	if mode == 0:
		var std_counts := _convert_std_continuous(objects_raw, chart, timing_raw, slider_multiplier, circle_radius)
		chart.refresh_ids()
		report.append("保留：Tap %d，Path %d，Hold %d；跳过：spinner %d，无效 %d" % [std_counts["tap"], std_counts["path"], std_counts["hold"], std_counts["spinner"], std_counts["invalid"]])
		report.append("osu!std → 连续环：circle → Tap；可跟随 slider → Path；lazy/短/重复 slider → Hold；流方向压缩 + 360°/s 限速，宽度按相邻角度/时间补偿。")
		if int(std_counts["spinner"]) > 0:
			report.append("注意：spinner 没有头尾，按设计不导入。")
		return {"chart": chart, "report": report, "_events": events, "_general": general}

	var counts := {"tap": 0, "hold": 0, "spinner": 0, "invalid": 0}
	var taiko_prev_beat := -1.0e9
	var taiko_prev_angle := 0.0
	for object in objects_raw:
		var type := int(object["type"])
		if type & 8:
			counts["spinner"] += 1
			continue
		if type & 128:
			counts["invalid"] += 1
			continue
		var beat: float = chart.timing.audio_ms_to_beat(float(object["time"]))
		var hit_sound := int(object["hit_sound"])
		var kat := _is_taiko_kat(hit_sound)
		var finish := (hit_sound & 4) != 0
		if type & 1:
			var gap := beat - taiko_prev_beat
			var angle := taiko_prev_angle
			if gap >= TAIKO_STACK_GAP:
				angle = _taiko_lane(taiko_prev_angle, kat)
			var width := 90.0 if finish else (76.0 if kat else 58.0)
			var note := Note.new("tap", beat, fposmod(angle, 360.0), width)
			note.id = chart.next_note_id()
			chart.notes.append(note)
			taiko_prev_beat = beat
			taiko_prev_angle = fposmod(angle, 360.0)
			counts["tap"] += 1
		elif type & 2:
			var duration := _slider_beats(object, chart, timing_raw, slider_multiplier)
			var gap := beat - taiko_prev_beat
			var angle := taiko_prev_angle
			if gap >= TAIKO_STACK_GAP:
				angle = _taiko_lane(taiko_prev_angle, kat)
			if duration < 1.5:
				# 短滑条按 osu!taiko 习惯拆成拍点，不生成需要长按的 Hold。
				var span := clampf(duration, 0.25, 1.5)
				var count := maxi(1, int(round(span / 0.5)))
				var last_beat := beat
				for i in count:
					var tap_beat := beat + span * float(i) / float(count)
					var tap := Note.new("tap", tap_beat, fposmod(angle, 360.0), 76.0 if kat else 58.0)
					tap.id = chart.next_note_id()
					chart.notes.append(tap)
					last_beat = tap_beat
					counts["tap"] += 1
				taiko_prev_beat = last_beat
			else:
				var hold := Note.new("hold", beat, fposmod(angle, 360.0), 58.0)
				hold.id = chart.next_note_id()
				hold.end_beat = beat + duration
				chart.notes.append(hold)
				taiko_prev_beat = beat + duration
				counts["hold"] += 1
			taiko_prev_angle = fposmod(angle, 360.0)
		else:
			counts["invalid"] += 1
	chart.refresh_ids()
	report.append("保留：Tap %d，Hold %d；跳过：spinner %d，无效 %d" % [counts["tap"], counts["hold"], counts["spinner"], counts["invalid"]])
	report.append("taiko 映射：don/kat 按 hitsound（whistle/clap = kat）分色；就近取 0/90/180/270 两车道，密集段堆叠不甩圈；短滑条 → Tap，长滑条 → Hold；spinner 跳过。")
	if counts["spinner"] > 0:
		report.append("注意：spinner 没有头尾，按设计不导入。")
	return {"chart": chart, "report": report, "_events": events, "_general": general}

static func _is_taiko_kat(hit_sound: int) -> bool:
	return (hit_sound & 2) != 0 or (hit_sound & 8) != 0


static func _taiko_lane(previous: float, kat: bool) -> float:
	# 同一类音落在固定车道上，跨 don/kat 时只走最近的 90°。
	var base := 90.0 if kat else 0.0
	var best := base
	var best_distance := INF
	for candidate in [base, fposmod(base + 180.0, 360.0)]:
		var distance := absf(JudgeMath.angle_delta(previous, candidate))
		if distance < best_distance:
			best_distance = distance
			best = candidate
	return best


static func _convert_std_continuous(objects_raw: Array, chart: Chart, timing_raw: Array[Dictionary], slider_multiplier: float, circle_radius: float) -> Dictionary:
	var counts := {"tap": 0, "path": 0, "hold": 0, "spinner": 0, "invalid": 0}
	var play: Array[Dictionary] = []
	for object in objects_raw:
		var type := int(object["type"])
		if type & 8:
			counts["spinner"] += 1
			continue
		if type & 128 or (not (type & 1) and not (type & 2)):
			counts["invalid"] += 1
			continue
		var pos := Vector2(float(object["x"]), float(object["y"]))
		var beat := chart.timing.audio_ms_to_beat(float(object["time"]))
		var is_slider := (type & 2) != 0
		var end_pos := pos
		var duration := 0.0
		var repeats := 1
		var lazy := false
		var raw: Array[Vector2] = []
		if is_slider:
			var fields: Array = object["fields"]
			if fields.size() < 8:
				counts["invalid"] += 1
				continue
			repeats = maxi(1, int(fields[6]))
			duration = _slider_beats(object, chart, timing_raw, slider_multiplier)
			raw = _std_slider_curve(object)
			if raw.size() < 2:
				counts["invalid"] += 1
				continue
			end_pos = raw[-1] if repeats % 2 == 1 else pos
			lazy = _std_is_lazy(raw, pos, circle_radius)
		play.append({
			"pos": pos, "end_pos": end_pos, "beat": beat, "is_slider": is_slider,
			"duration": duration, "repeats": repeats, "lazy": lazy, "raw": raw,
		})
	if play.is_empty():
		return counts
	play.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["beat"]) < float(b["beat"]))

	var infos: Array[Dictionary] = []
	var prev_u := 0.0
	var prev_end_beat := 0.0
	var first := true
	for i in play.size():
		var current: Dictionary = play[i]
		var pos: Vector2 = current["pos"]
		var beat := float(current["beat"])
		var raw_start := _std_angle(pos)
		var u := raw_start
		var is_jump := false
		if not first:
			var prev: Dictionary = play[i - 1]
			var prev_prev: Dictionary = play[i - 2] if i >= 2 else {}
			var midpoint := _std_midpoint(prev, prev_prev, current)
			var prev_flow := _std_angle_between(midpoint, prev["end_pos"])
			var curr_flow := _std_angle_between(midpoint, pos)
			var raw_delta := _std_short_delta(prev_flow, curr_flow)
			is_jump = (prev["end_pos"] as Vector2).distance_to(pos) >= STD_JUMP_DISTANCE
			var compression := STD_JUMP_COMPRESSION if is_jump else STD_STREAM_COMPRESSION
			var delta := raw_delta * compression
			if absf(raw_delta) <= 5.0 or absf(absf(raw_delta) - 180.0) <= 5.0:
				delta = 0.0
			var bpm := maxf(1.0, chart.timing.bpm_at(beat))
			var dt := maxf(0.0001, (beat - prev_end_beat) * 60.0 / bpm)
			var max_delta := STD_MAX_DEG_PER_SEC * dt
			delta = clampf(delta, -max_delta, max_delta)
			u = prev_u + delta
		first = false

		var note: Note
		var tail_u := u
		var end_beat := beat
		var is_path := false
		if bool(current["is_slider"]) and not bool(current["lazy"]) and int(current["repeats"]) <= 1 and float(current["duration"]) >= 0.5:
			var raw: Array[Vector2] = current["raw"]
			var raw_end := _std_angle(current["end_pos"])
			var net := _std_short_delta(raw_start, raw_end)
			var turn := _std_curve_turn(raw)
			var direction := 1.0
			if absf(turn) > 0.1:
				direction = 1.0 if turn > 0.0 else -1.0
			elif absf(net) > 1.0:
				direction = 1.0 if net > 0.0 else -1.0
			var span := clampf(absf(net) * 0.55 + float(current["duration"]) * 12.0, 45.0, STD_PATH_MAX_SPAN)
			tail_u = u + direction * span
			end_beat = beat + float(current["duration"])
			note = Note.new("path", beat, fposmod(u, 360.0), 60.0)
			note.end_beat = end_beat
			note.tail_angle = fposmod(tail_u, 360.0)
			note.tail_width = 60.0
			note.path_style = "arc"
			note.tolerance = 0.24
			note.samples_per_beat = 4.0
			counts["path"] += 1
			is_path = true
		elif bool(current["is_slider"]):
			var hold_duration := maxf(0.25, float(current["duration"]))
			end_beat = beat + hold_duration
			note = Note.new("hold", beat, fposmod(u, 360.0), 60.0)
			note.end_beat = end_beat
			counts["hold"] += 1
		else:
			note = Note.new("tap", beat, fposmod(u, 360.0), 60.0)
			counts["tap"] += 1
		note.id = chart.next_note_id()
		chart.notes.append(note)
		infos.append({
			"note": note, "beat": beat, "u": u, "is_jump": is_jump,
			"is_path": is_path, "tail_u": tail_u, "end_beat": end_beat,
		})
		prev_u = tail_u if is_path else u
		prev_end_beat = end_beat

	for i in infos.size():
		var info: Dictionary = infos[i]
		var note: Note = info["note"]
		var u := float(info["u"])
		var prev_ref := u
		var next_ref := u
		var prev_time := 4.0
		var next_time := 4.0
		if i > 0:
			var previous: Dictionary = infos[i - 1]
			prev_ref = float(previous["tail_u"]) if bool(previous["is_path"]) else float(previous["u"])
			prev_time = float(info["beat"]) - float(previous["beat"])
		if i + 1 < infos.size():
			next_ref = float(infos[i + 1]["u"])
			next_time = float(infos[i + 1]["beat"]) - float(info["beat"])
		var current_ref := float(info["tail_u"]) if bool(info["is_path"]) else u
		var prev_gap := absf(_std_short_delta(prev_ref, u))
		var next_gap := absf(_std_short_delta(current_ref, next_ref))
		var dense := prev_time < 0.5 or next_time < 0.5
		var width := 62.0
		if dense:
			width += 22.0
		width += clampf(minf(prev_gap, next_gap) * 0.25, 0.0, 25.0)
		if bool(info["is_jump"]):
			width -= 8.0
		width = clampf(width, 52.0, 110.0)
		note.width = width
		if note.type == "path":
			note.tail_width = clampf(width + 8.0, 52.0, 120.0)
	return counts


static func _std_angle(point: Vector2) -> float:
	return rad_to_deg(atan2(point.y - 192.0, point.x - 256.0))


static func _std_angle_between(from: Vector2, to: Vector2) -> float:
	return rad_to_deg(atan2(to.y - from.y, to.x - from.x))


static func _std_short_delta(from_angle: float, to_angle: float) -> float:
	return JudgeMath.angle_delta(from_angle, to_angle)


static func _std_midpoint(current: Dictionary, previous: Dictionary, next: Dictionary) -> Vector2:
	var sum: Vector2 = current["end_pos"]
	var count := 1
	if not previous.is_empty():
		sum += previous["end_pos"]
		count += 1
	sum += next["pos"]
	count += 1
	if (current["pos"] as Vector2) != (current["end_pos"] as Vector2):
		sum += current["pos"]
		count += 1
	if count > 2:
		return sum / float(count)
	return Vector2(256.0, 192.0)


static func _std_is_lazy(raw: Array[Vector2], start: Vector2, circle_radius: float) -> bool:
	var limit := circle_radius * 2.4
	var limit_squared := limit * limit
	for point in raw:
		if point.distance_squared_to(start) > limit_squared:
			return false
	return true


static func _std_curve_turn(raw: Array[Vector2]) -> float:
	var turn := 0.0
	for i in range(1, raw.size() - 1):
		var a := raw[i] - raw[i - 1]
		var b := raw[i + 1] - raw[i]
		turn += a.x * b.y - a.y * b.x
	return turn


static func _std_slider_curve(object: Dictionary) -> Array[Vector2]:
	var fields: Array = object["fields"]
	var pieces := String(fields[5]).split("|")
	var kind := String(pieces[0])
	var control: Array[Vector2] = [Vector2(float(object["x"]), float(object["y"]))]
	for i in range(1, pieces.size()):
		var xy := pieces[i].split(":")
		if xy.size() >= 2:
			control.append(Vector2(float(xy[0]), float(xy[1])))
	if control.size() < 2:
		return control
	match kind:
		"L":
			return _sample_linear(control)
		"C":
			return _sample_catmull(control)
		"P":
			return _sample_perfect(control)
		_:
			return _sample_bezier(control)


static func _sample_linear(points: Array[Vector2]) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		if a.distance_to(b) < 0.001:
			continue
		for step in 8:
			result.append(a.lerp(b, float(step) / 8.0))
	result.append(points[-1])
	return result


static func _sample_bezier(control: Array[Vector2]) -> Array[Vector2]:
	var segments: Array = []
	var current: Array[Vector2] = []
	for point in control:
		if not current.is_empty() and current[-1].distance_to(point) < 0.001:
			if current.size() >= 2:
				segments.append(current)
			current.clear()
			current.append(point)
			continue
		current.append(point)
	if current.size() >= 2:
		segments.append(current)
	if segments.is_empty():
		return control
	var result: Array[Vector2] = []
	for segment in segments:
		var seg: Array = segment
		if seg.size() == 2:
			for step in 8:
				result.append((seg[0] as Vector2).lerp(seg[1], float(step) / 8.0))
		else:
			var steps := maxi(12, seg.size() * 6)
			for step in steps:
				result.append(_bezier_point(seg, float(step) / float(steps)))
	result.append(control[-1])
	return result


static func _bezier_point(control: Array, t: float) -> Vector2:
	var points: Array = control.duplicate()
	for level in range(points.size() - 1, 0, -1):
		for i in level:
			points[i] = (points[i] as Vector2).lerp(points[i + 1] as Vector2, t)
	return points[0] as Vector2


static func _sample_catmull(control: Array[Vector2]) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var count := control.size()
	if count < 2:
		return control
	for i in count - 1:
		var p0 := control[maxi(0, i - 1)]
		var p1 := control[i]
		var p2 := control[i + 1]
		var p3 := control[mini(count - 1, i + 2)]
		if p1.distance_to(p2) < 0.001:
			continue
		for step in 12:
			result.append(_catmull_point(p0, p1, p2, p3, float(step) / 12.0))
	result.append(control[-1])
	return result


static func _catmull_point(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


static func _sample_perfect(control: Array[Vector2]) -> Array[Vector2]:
	if control.size() < 3:
		return _sample_linear(control)
	var points: Array[Vector2] = []
	for point in control:
		if points.is_empty() or points[-1].distance_to(point) > 0.001:
			points.append(point)
		if points.size() == 3:
			break
	if points.size() < 3:
		return _sample_linear(control)
	var center := _circumcenter(points[0], points[1], points[2])
	if not center.is_finite() or center == Vector2(INF, INF):
		return _sample_linear(control)
	var radius := points[0].distance_to(center)
	if radius < 0.001:
		return _sample_linear(control)
	var a0 := atan2(points[0].y - center.y, points[0].x - center.x)
	var a1 := atan2(points[1].y - center.y, points[1].x - center.x)
	var a2 := atan2(points[2].y - center.y, points[2].x - center.x)
	var ccw := fposmod(a1 - a0, TAU) <= fposmod(a2 - a0, TAU)
	if ccw:
		if a2 < a0:
			a2 += TAU
	else:
		if a2 > a0:
			a2 -= TAU
	var result: Array[Vector2] = []
	for step in 32:
		var angle := lerpf(a0, a2, float(step) / 32.0)
		result.append(center + Vector2(cos(angle), sin(angle)) * radius)
	for i in range(3, control.size()):
		var previous := result[-1]
		var next := control[i]
		for step in 8:
			result.append(previous.lerp(next, float(step) / 8.0))
		result.append(next)
	result.append(control[-1])
	return result


static func _circumcenter(a: Vector2, b: Vector2, c: Vector2) -> Vector2:
	var d := 2.0 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
	if absf(d) < 0.0001:
		return Vector2(INF, INF)
	var a2 := a.length_squared()
	var b2 := b.length_squared()
	var c2 := c.length_squared()
	var ux := (a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / d
	var uy := (a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / d
	return Vector2(ux, uy)


static func _slider_beats(object: Dictionary, chart: Chart, timing_raw: Array[Dictionary], slider_multiplier: float) -> float:
	var slides := maxi(1, int(object["fields"][6])) if object["fields"].size() >= 8 else 1
	return _slider_one_pass_beats(object, timing_raw, slider_multiplier) * float(slides)


static func _slider_one_pass_beats(object: Dictionary, timing_raw: Array[Dictionary], slider_multiplier: float) -> float:
	var fields: Array = object["fields"]
	if fields.size() < 8:
		return 0.0
	var length := maxf(0.0, float(fields[7]))
	var sv := _slider_velocity_at(float(object["time"]), timing_raw)
	return length / maxf(0.001, slider_multiplier * 100.0 * sv)


static func _slider_velocity_at(time: float, timing_raw: Array[Dictionary]) -> float:
	var sv := 1.0
	var sorted := timing_raw.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["time"]) < float(b["time"]))
	for entry in sorted:
		if float(entry["time"]) > time + 0.001:
			break
		if int(entry["uninherited"]) == 1:
			sv = 1.0
		else:
			var beat_length := float(entry["beat_length"])
			if beat_length < 0.0:
				sv = -100.0 / beat_length
	return maxf(0.01, sv)


static func _extract_assets(zip: ZIPReader, files: PackedStringArray, chart: Chart, chosen: String) -> Array[String]:
	var report: Array[String] = []
	var main := chosen
	var text := zip.read_file(main).get_string_from_utf8()
	var general := _key_values(text, "General")
	var audio_name := String(general.get("AudioFilename", ""))
	var target_dir := "user://imports/%s_%s" % [main.get_file().get_basename().validate_filename(), main.md5_text().substr(0, 8)]
	var found_audio := _find_file(files, audio_name)
	if not found_audio.is_empty():
		var target := target_dir + "/" + found_audio.get_file()
		_write_zip_file(zip, found_audio, target)
		chart.audio_path = target
		report.append("音频：%s" % target)
	else:
		report.append("音频：未找到 %s" % audio_name)
	var events := _lines_in_section(text, "Events")
	for line in events:
		var parts := line.split(",")
		if parts.size() >= 3 and parts[0].strip_edges() == "0":
			var background := parts[2].strip_edges().trim_prefix("\"").trim_suffix("\"")
			var found := _find_file(files, background)
			if not found.is_empty():
				var target := target_dir + "/" + found.get_file()
				_write_zip_file(zip, found, target)
				chart.metadata["background"] = target
				report.append("背景：%s" % target)
			break
	for line in events:
		var parts := line.split(",")
		if parts.size() >= 3 and parts[0].strip_edges() == "Video":
			var video := parts[2].strip_edges().trim_prefix("\"").trim_suffix("\"")
			var found := _find_file(files, video)
			if not found.is_empty():
				var target := target_dir + "/" + found.get_file()
				_write_zip_file(zip, found, target)
				chart.video_path = target
				report.append("视频：%s（预览时按需转码）" % target)
			break
	return report


static func _find_file(files: PackedStringArray, wanted: String) -> String:
	if wanted.is_empty():
		return ""
	var target := wanted.replace("\\", "/").to_lower()
	for name in files:
		if name.replace("\\", "/").get_file().to_lower() == target.get_file():
			return name
	return ""


static func _write_zip_file(zip: ZIPReader, name: String, target: String) -> void:
	var data := zip.read_file(name)
	if data.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target.get_base_dir()))
	var file := FileAccess.open(target, FileAccess.WRITE)
	if file != null:
		file.store_buffer(data)
		file.close()


static func _key_values(text: String, section_name: String) -> Dictionary:
	var result := {}
	var section := ""
	for raw_line in text.split("\n"):
		var line := raw_line.strip_edges()
		if line.begins_with("[") and line.ends_with("]"):
			section = line.substr(1, line.length() - 2)
			continue
		if section != section_name or line.is_empty() or line.begins_with("//"):
			continue
		var split := line.split(":", true, 1)
		if split.size() >= 2:
			result[split[0].strip_edges()] = split[1].strip_edges()
	return result


static func _lines_in_section(text: String, section_name: String) -> Array[String]:
	var result: Array[String] = []
	var section := ""
	for raw_line in text.split("\n"):
		var line := raw_line.strip_edges()
		if line.begins_with("[") and line.ends_with("]"):
			section = line.substr(1, line.length() - 2)
			continue
		if section == section_name and not line.is_empty() and not line.begins_with("//"):
			result.append(line)
	return result
