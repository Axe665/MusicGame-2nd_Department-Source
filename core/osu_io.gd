class_name OsuIO
extends RefCounted

static var last_error: String = ""

const PLAYFIELD_CENTER := Vector2(256.0, 192.0)
const DEFAULT_WIDTH := 120.0
const TAIKO_STACK_GAP := 0.32
const STD_ANGLE_COMPRESSION := 0.50
const STD_MAX_STEP := 60.0


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
	var counts := {"tap": 0, "path": 0, "hold": 0, "spinner": 0, "invalid": 0}
	var taiko_prev_beat := -1.0e9
	var taiko_prev_angle := 0.0
	var std_prev_raw := 0.0
	var std_prev_ring := 0.0
	var std_has_prev := false
	objects_raw.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["time"]) < float(b["time"]))
	for object in objects_raw:
		var type := int(object["type"])
		if type & 8:
			counts["spinner"] += 1
			continue
		if type & 128:
			counts["invalid"] += 1
			continue
		var object_time: float = float(object["time"])
		var beat: float = chart.timing.audio_ms_to_beat(object_time)
		var hit_sound := int(object["hit_sound"])
		var raw_angle := _std_angle(Vector2(float(object["x"]), float(object["y"])))
		if mode == 1:
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
			continue
		var ring_angle := raw_angle
		if std_has_prev:
			var delta := JudgeMath.angle_delta(std_prev_raw, raw_angle) * STD_ANGLE_COMPRESSION
			ring_angle = std_prev_ring + clampf(delta, -STD_MAX_STEP, STD_MAX_STEP)
		var angle := fposmod(ring_angle, 360.0)
		if type & 1:
			var note := Note.new("tap", beat, angle, DEFAULT_WIDTH)
			note.id = chart.next_note_id()
			chart.notes.append(note)
			counts["tap"] += 1
			std_prev_raw = raw_angle
			std_prev_ring = ring_angle
			std_has_prev = true
		elif type & 2:
			var result := _std_slider(object, chart, beat, raw_angle, ring_angle, timing_raw, slider_multiplier)
			if result.is_empty():
				counts["invalid"] += 1
			else:
				var note: Note = result["note"]
				note.id = chart.next_note_id()
				chart.notes.append(note)
				counts["path"] += 1
				std_prev_raw = float(result["tail_raw"])
				std_prev_ring = float(result["tail_ring"])
				std_has_prev = true
		else:
			counts["invalid"] += 1
	chart.refresh_ids()
	report.append("保留：Tap %d，Path %d，Hold %d；跳过：spinner %d，无效 %d" % [counts["tap"], counts["path"], counts["hold"], counts["spinner"], counts["invalid"]])
	if mode == 1:
		report.append("taiko 映射：don/kat 按 hitsound（whistle/clap = kat）分色；就近取 0/90/180/270 两车道，密集段堆叠不甩圈；短滑条 → Tap，长滑条 → Hold；spinner 跳过。")
	else:
		report.append("osu!std 映射：circle → Tap；slider → Path；角度按相邻位移压缩 %.2f（单步 ≤ %.0f°），避免整圈散点；spinner 跳过。" % [STD_ANGLE_COMPRESSION, STD_MAX_STEP])
	if counts["spinner"] > 0:
		report.append("注意：spinner 没有头尾，按设计不导入。")
	return {"chart": chart, "report": report, "_events": events, "_general": general}


static func _std_angle(point: Vector2) -> float:
	return fposmod(rad_to_deg(atan2(point.y - PLAYFIELD_CENTER.y, point.x - PLAYFIELD_CENTER.x)), 360.0)


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


static func _std_slider(object: Dictionary, chart: Chart, beat: float, raw_head: float, ring_head: float, timing_raw: Array[Dictionary], slider_multiplier: float) -> Dictionary:
	var fields: Array = object["fields"]
	if fields.size() < 8:
		return {}
	var curve: String = String(fields[5])
	var slides := maxi(1, int(fields[6]))
	var one_pass := _slider_one_pass_beats(object, timing_raw, slider_multiplier)
	if one_pass <= 0.001:
		one_pass = 0.25
	var total := one_pass * float(slides)
	var pieces := curve.split("|")
	var points: Array[Vector2] = []
	for i in range(1, pieces.size()):
		var xy := pieces[i].split(":")
		if xy.size() >= 2:
			points.append(Vector2(float(xy[0]), float(xy[1])))
	var tail_raw := raw_head
	if slides % 2 == 1 and not points.is_empty():
		tail_raw = _std_angle(points[-1])
	var tail_ring := ring_head + clampf(JudgeMath.angle_delta(raw_head, tail_raw) * STD_ANGLE_COMPRESSION, -90.0, 90.0)
	var note := Note.new("path", beat, fposmod(ring_head, 360.0), DEFAULT_WIDTH)
	note.end_beat = beat + total
	note.tail_angle = fposmod(tail_ring, 360.0)
	note.tail_width = 90.0
	note.path_style = "arc"
	for i in points.size():
		var point := points[i]
		var point_angle := _std_angle(point)
		var delta := clampf(JudgeMath.angle_delta(raw_head, point_angle) * STD_ANGLE_COMPRESSION, -90.0, 90.0)
		note.visual_pts.append({
			"db": one_pass * float(i + 1) / float(points.size() + 1),
			"da": delta,
		})
	return {"note": note, "tail_raw": tail_raw, "tail_ring": tail_ring}


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
