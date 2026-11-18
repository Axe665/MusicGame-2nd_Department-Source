extends RefCounted

## 压力谱面工厂：性能基线用，固定种子、固定规模，跨机器可复现。
## notes 越大越接近用户的「高压力场景」；keys 控制形状关键帧密度。

const NOTES_PER_BEAT := 2.0


static func make(notes: int, keys: int = 200) -> Chart:
	var chart := Chart.new()
	chart.timing.points = [TimingPoint.new(0.0, 120.0, 4)]
	chart.shapes["S0"] = BoundaryShape.circle("S0", 330.0, 48)
	chart.shapes["S1"] = BoundaryShape.circle("S1", 230.0, 12)
	chart.shapes["S2"] = BoundaryShape.circle("S2", 180.0, 4)
	chart.default_shape_id = "S0"
	var key_count := maxi(2, keys)
	var shape_ids := ["S0", "S1", "S2"]
	for i in key_count:
		chart.shape_keys.append({
			"beat": float(i) * 4.0,
			"shape_id": shape_ids[i % shape_ids.size()],
			"easing": "in-out",
		})
	for i in maxi(2, key_count / 4):
		chart.view_states.append(ViewState.new(float(i) * 16.0, 1.0, 0.0, 0.0, 1.0,
			float((i * 37) % 360 - 180)))
	var types := ["tap", "hold", "path", "anchor", "bell"]
	for i in notes:
		var type: String = types[i % types.size()]
		var beat := float(i) / NOTES_PER_BEAT
		var angle := fposmod(float(i) * 37.0, 360.0)
		var note := Note.new(type, beat, angle, 60.0)
		note.id = chart.next_note_id()
		if type == "hold":
			note.end_beat = beat + 2.0
		elif type == "path":
			note.end_beat = beat + 2.0
			note.tail_angle = fposmod(angle + 90.0, 360.0)
			note.trace_pts = [
				{"x": cos(deg_to_rad(angle)), "y": sin(deg_to_rad(angle)), "db": 0.0},
				{"x": cos(deg_to_rad(angle + 60.0)) * 0.7, "y": sin(deg_to_rad(angle + 60.0)) * 0.7, "db": 1.0},
				{"x": cos(deg_to_rad(angle + 90.0)), "y": sin(deg_to_rad(angle + 90.0)), "db": 2.0},
			]
		elif type == "anchor":
			note.pair_id = "P%d" % (i / 2)
		chart.notes.append(note)
	for i in 8:
		var region := Region.new(100 + i, 380.0 + float(i) * 3.0, 381.0 + float(i) * 3.0)
		region.angle = float(i) * 45.0
		region.width = 30.0
		chart.regions.append(region)
	return chart
