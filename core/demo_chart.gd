class_name DemoChart
extends RefCounted

## Builds the first-run example chart. It intentionally exercises every note
## type, a local boundary event, a Red region and a ViewState keyframe.


static func make_empty(meta: Dictionary) -> Chart:
	var chart := Chart.new()
	chart.metadata = {
		"title": String(meta.get("title", "未命名谱面")),
		"artist": String(meta.get("artist", "")),
		"creator": String(meta.get("creator", "")),
		"version": String(meta.get("version", "")),
		"tags": String(meta.get("tags", "")),
		"license": String(meta.get("license", "")),
		"background": String(meta.get("background", "")),
	}
	chart.audio_path = String(meta.get("audio", ""))
	chart.video_path = String(meta.get("video", ""))
	chart.offset_ms = float(meta.get("offset_ms", 0.0))
	chart.difficulty = String(meta.get("difficulty", "Normal"))
	chart.timing = TimingMap.new()
	chart.timing.points.clear()
	chart.timing.points.append(TimingPoint.new(
		0.0,
		float(meta.get("bpm", 120.0)),
		int(meta.get("beats_per_bar", 4))
	))
	chart.timing.offset_ms = chart.offset_ms
	chart.shapes.clear()
	chart.shapes["S0"] = BoundaryShape.circle("S0", 330.0, 48)
	chart.default_shape_id = "S0"
	chart.view_states.clear()
	chart.view_states.append(ViewState.new(0.0, 1.0, 0.0, 0.0, 1.0, 0.0, "linear"))
	chart.editor = {"snap": 4, "zoom": 1.0, "waveform": true, "hud": true}
	return chart


static func make_demo() -> Chart:
	var chart := make_empty({
		"title": "夜に駆ける（示例）",
		"artist": "YOASOBI",
		"creator": "Tamaki₃",
		"version": "Insane",
		"tags": "ring v6.2 demo",
		"license": "CC-BY-4.0",
		"audio": "res://audio/demo_click.wav",
		"bpm": 120.0,
		"beats_per_bar": 4,
		"difficulty": "Insane",
	})
	chart.shapes["S1"] = BoundaryShape.ellipse("S1", 410.0, 245.0, 48)
	chart.shapes["S2"] = BoundaryShape.ellipse("S2", 300.0, 400.0, 48)

	chart.shape_keys = [
		{"beat": 8.0, "shape_id": "S0", "easing": "in-out"},
		{"beat": 12.0, "shape_id": "S1", "easing": "in-out"},
		{"beat": 12.5, "shape_id": "S0", "easing": "in-out"},
		{"beat": 20.0, "shape_id": "S0", "easing": "in-out"},
		{"beat": 24.0, "shape_id": "S2", "easing": "in-out"},
		{"beat": 24.5, "shape_id": "S0", "easing": "in-out"},
	]
	chart.refresh_ids()

	chart.view_states.clear()
	chart.view_states.append(ViewState.new(0.0, 1.0, 0.0, 0.0, 1.0, 0.0, "linear"))
	chart.view_states.append(ViewState.new(8.0, 1.06, 22.0, 0.0, 1.0, 4.0, "in-out"))
	chart.view_states.append(ViewState.new(16.0, 1.12, 30.0, 12.0, 1.04, 12.0, "in-out"))
	chart.view_states.append(ViewState.new(24.0, 1.0, 0.0, 0.0, 1.0, 0.0, "in-out"))

	var r1 := Region.new(1, 14.0, 16.0)
	r1.angle = 180.0
	r1.width = 90.0
	chart.regions.append(r1)
	var r2 := Region.new(2, 26.0, 28.0)
	r2.angle = 270.0
	r2.width = 100.0
	chart.regions.append(r2)

	_add_tap(chart, 4.0, 0.0)
	_add_tap(chart, 4.5, 60.0)
	_add_tap(chart, 5.0, 120.0)
	_add_tap(chart, 5.5, 180.0)
	_add_hold(chart, 6.0, 8.0, 240.0, 60.0)
	_add_path(chart, 8.0, 12.0, 0.0, 120.0, 180.0, 120.0)
	_add_tap(chart, 12.5, 270.0)
	_add_tap(chart, 13.0, 315.0)
	_add_tap(chart, 13.5, 0.0)
	_add_tap(chart, 14.0, 45.0)
	_add_seek(chart, 14.0, 0)
	_add_anchor_pair(chart, 16.0, 0.0, "A0")
	_add_bell(chart, 17.0, 0.25)
	_add_bell(chart, 17.5, 0.5)
	_add_path(chart, 18.0, 20.0, 180.0, 90.0, 0.0, 90.0)
	_add_tap(chart, 20.5, 90.0)
	_add_tap(chart, 21.0, 120.0)
	_add_tap(chart, 21.5, 150.0)
	_add_hold(chart, 22.0, 24.0, 270.0, 60.0)
	_add_tap(chart, 24.0, 0.0)
	_add_tap(chart, 24.5, 45.0)
	_add_tap(chart, 25.0, 90.0)
	_add_tap(chart, 25.5, 135.0)
	_add_path(chart, 26.0, 28.0, 0.0, 120.0, 180.0, 120.0)
	_add_bell(chart, 28.0, 0.75)
	_add_tap(chart, 28.5, 270.0)
	_add_tap(chart, 29.0, 315.0)
	_add_tap(chart, 29.5, 0.0)
	_add_hold(chart, 30.0, 32.0, 90.0, 60.0)
	_add_anchor_pair(chart, 32.0, 90.0, "A1")
	chart.refresh_ids()
	return chart


static func _add_tap(chart: Chart, beat: float, angle: float, width: float = 60.0) -> void:
	var note := Note.new("tap", beat, angle, width)
	note.id = chart.next_note_id()
	chart.notes.append(note)


static func _add_hold(chart: Chart, beat: float, end_beat: float, angle: float, width: float) -> void:
	var note := Note.new("hold", beat, angle, width)
	note.id = chart.next_note_id()
	note.end_beat = end_beat
	note.hold = true
	note.hold_style = "straight"
	chart.notes.append(note)


static func _add_path(
	chart: Chart,
	beat: float,
	end_beat: float,
	head_angle: float,
	head_width: float,
	tail_angle: float,
	tail_width: float
) -> void:
	var note := Note.new("path", beat, head_angle, head_width)
	note.id = chart.next_note_id()
	note.end_beat = end_beat
	note.tail_angle = tail_angle
	note.tail_width = tail_width
	note.tolerance = 0.24
	note.samples_per_beat = 4.0
	note.path_centrifuge = 0.72
	note.path_axis = 0.5
	note.generate_path_shape()
	chart.notes.append(note)


static func _add_seek(chart: Chart, beat: float, orien: int) -> void:
	var note := Note.new("seek", beat, 0.0, 360.0)
	note.id = chart.next_note_id()
	note.end_beat = beat
	note.seek_orien = 1 if orien == 1 else 0
	chart.notes.append(note)


static func _add_anchor_pair(chart: Chart, beat: float, angle: float, pair_id: String) -> void:
	var a := Note.new("anchor", beat, angle, 0.0)
	a.id = chart.next_note_id()
	a.anchor_pair = 0
	a.pair_id = pair_id
	chart.notes.append(a)
	var b := Note.new("anchor", beat, angle + 180.0, 0.0)
	b.id = chart.next_note_id()
	b.anchor_pair = 0
	b.pair_id = pair_id
	chart.notes.append(b)


static func _add_bell(chart: Chart, beat: float, center_u: float) -> void:
	var note := Note.new("bell", beat, center_u * 360.0, 0.0)
	note.id = chart.next_note_id()
	note.center_u = center_u
	note.radius = 26.0
	chart.notes.append(note)
