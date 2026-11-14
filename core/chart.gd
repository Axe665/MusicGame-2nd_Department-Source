class_name Chart
extends RefCounted

var format_version: int = 1
var audio_path: String = ""
var video_path: String = ""
var video_offset_ms: float = 0.0
var video_fps: float = 60.0
var video_opacity: float = 0.35
var pre_read_ms: float = 1000.0
var offset_ms: float = 0.0
var difficulty: String = "Normal"
var metadata: Dictionary = {
	"title": "未命名谱面",
	"artist": "",
	"creator": "",
	"version": "",
	"tags": "",
	"license": "",
	"background": "",
}
var timing: TimingMap = TimingMap.new()
var default_shape_id: String = "S0"
var shapes: Dictionary = {}
var events: Array[BoundaryEvent] = []
## 形状关键帧：{beat, shape_id, easing}。easing 管“从这一帧到下一帧”。
## 运行时以关键帧为准；events 只用于读旧谱和给旧版本双写。
var shape_keys: Array[Dictionary] = []
## 载入时产生的兼容提示（曲线降级等），由编辑器弹一次。
var load_warnings: Array[String] = []
var view_states: Array[ViewState] = []
var regions: Array[Region] = []
var notes: Array[Note] = []


## Anchor 的配对：同一 pairId、同一拍即可，角度自由。
func anchor_partner(note: Note) -> Note:
	if note.type != "anchor" or note.pair_id.is_empty():
		return null
	for other in notes:
		if other.id == note.id or other.type != "anchor":
			continue
		if other.pair_id != note.pair_id:
			continue
		if absf(other.beat - note.beat) > 0.0001:
			continue
		return other
	return null


## 放一颗 Anchor 时同时生成同拍反向的另一颗，返回 [a, b]。
func make_anchor_pair(beat: float, angle: float) -> Array[Note]:
	var a := Note.new("anchor", beat, fposmod(angle, 360.0), 0.0)
	a.id = next_note_id()
	a.anchor_pair = 0
	a.pair_id = "P%d" % a.id
	var b := Note.new("anchor", beat, fposmod(angle + 180.0, 360.0), 0.0)
	b.id = next_note_id()
	b.anchor_pair = 0
	b.pair_id = a.pair_id
	var out: Array[Note] = [a, b]
	return out


var editor: Dictionary = {}

## 配色分组：每组 {name, tap, hold, path}，颜色存 "#rrggbb" 字符串。
## Note.color 是 1 起的组号，0 = 跟随各类型的默认皮肤色。
const PALETTE_TYPES: Array[String] = ["tap", "hold", "path"]
const PALETTE_DEFAULTS := {
	"tap": "#ff6fae",
	"hold": "#f0c36a",
	"path": "#8cbfff",
}
var palette: Array[Dictionary] = []

var _next_note_id: int = 1
var _next_region_id: int = 1
var _next_event_id: int = 1


func _init() -> void:
	shapes["S0"] = BoundaryShape.circle("S0", 330.0, 48)
	view_states = [ViewState.new(0.0, 1.0, 0.0, 0.0, 1.0, 0.0, "linear")]


func get_shape(shape_id: String) -> BoundaryShape:
	return shapes.get(shape_id, null)


func get_default_shape() -> BoundaryShape:
	var shape: BoundaryShape = get_shape(default_shape_id)
	if shape == null and not shapes.is_empty():
		shape = shapes.values()[0]
	return shape


func sorted_shape_keys() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for key in shape_keys:
		if key is Dictionary:
			result.append(key)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("beat", 0.0)) < float(b.get("beat", 0.0)))
	return result


## 播放头正好落在关键帧上时返回那一帧，否则返回空字典。
func shape_key_at(beat: float) -> Dictionary:
	for key in shape_keys:
		if absf(float(key.get("beat", -1.0)) - beat) < 0.0005:
			return key
	return {}


func sorted_shapes() -> Array[BoundaryShape]:
	var result: Array[BoundaryShape] = []
	for shape in shapes.values():
		if shape is BoundaryShape:
			result.append(shape)
	result.sort_custom(func(a: BoundaryShape, b: BoundaryShape) -> bool: return a.id < b.id)
	return result


## 旧谱的圆心 Bell（bell_radius = 0）并到判定环：角度继承时间上最近的音符。
## 一份谱只有圆心 Bell 时保留 0°，不会把整张谱打散。
func merge_center_bells() -> void:
	var ordered := sorted_notes()
	var center := {}
	for i in ordered.size():
		var note := ordered[i]
		if note.type == "bell" and float(note.bell_radius) < 0.5:
			center[i] = true
	if center.is_empty():
		return
	# 先找前一个非圆心音符，找不到再找后一个。
	var donor: Array[float] = []
	donor.resize(ordered.size())
	var last := -1.0
	for i in ordered.size():
		if center.has(i):
			donor[i] = last
			continue
		last = _position_angle(ordered[i])
		donor[i] = last
	var next := -1.0
	for i in range(ordered.size() - 1, -1, -1):
		if center.has(i):
			if donor[i] < 0.0:
				donor[i] = next
			continue
		next = _position_angle(ordered[i])
	for i in center.keys():
		var note := ordered[i]
		var angle := donor[i]
		if angle >= 0.0:
			note.angle = fposmod(angle, 360.0)
			note.center_u = fposmod(note.angle / 360.0, 1.0)
		note.bell_radius = 1.0


static func _position_angle(note: Note) -> float:
	if note.type == "bell":
		return fposmod(note.center_u * 360.0, 360.0)
	return fposmod(note.angle, 360.0)


func sorted_notes() -> Array[Note]:
	var result := notes.duplicate()
	result.sort_custom(func(a: Note, b: Note) -> bool: return a.beat < b.beat)
	return result


func next_note_id() -> int:
	var result := _next_note_id
	_next_note_id += 1
	return result


func next_region_id() -> int:
	var result := _next_region_id
	_next_region_id += 1
	return result


func next_event_id() -> String:
	var result := "E%d" % _next_event_id
	_next_event_id += 1
	return result


func refresh_ids() -> void:
	var max_note := 0
	for note in notes:
		max_note = maxi(max_note, note.id)
	_next_note_id = max_note + 1
	var max_region := 0
	for region in regions:
		max_region = maxi(max_region, region.id)
	_next_region_id = max_region + 1
	var max_event := 0
	for event in events:
		var digits := event.id.trim_prefix("E")
		if digits.is_valid_int():
			max_event = maxi(max_event, int(digits))
	_next_event_id = max_event + 1


func notes_at(beat: float, tolerance: float = 0.001) -> Array[Note]:
	var result: Array[Note] = []
	for note in notes:
		if absf(note.beat - beat) <= tolerance:
			result.append(note)
	return result


func regions_at(beat: float) -> Array[Region]:
	var result: Array[Region] = []
	for region in regions:
		if region.active_at(beat):
			result.append(region)
	return result


func beat_to_ms(beat: float) -> float:
	return timing.beat_to_chart_ms(beat)


func ms_to_beat(ms: float) -> float:
	return timing.chart_ms_to_beat(ms)


func duration_beats() -> float:
	var last := 0.0
	for note in notes:
		last = maxf(last, maxf(note.beat, note.end_beat))
	for region in regions:
		last = maxf(last, region.end_beat)
	for event in events:
		last = maxf(last, event.end_beat + maxf(0.0, event.restore_duration))
	return last


func bar_length() -> float:
	return float(timing.beats_per_bar_at(0.0))


# ---------------------------------------------------------------- 配色分组


func palette_count() -> int:
	return palette.size()


func palette_group(index: int) -> Dictionary:
	if index < 1 or index > palette.size():
		return {}
	var group: Variant = palette[index - 1]
	return group if group is Dictionary else {}


## 返回组内某类型的颜色；组号越界或颜色非法时返回 alpha=0 的空色。
func palette_color(index: int, type_key: String) -> Color:
	var group := palette_group(index)
	if group.is_empty():
		return Color(0, 0, 0, 0)
	var text := String(group.get(type_key, ""))
	if text.is_empty() or not Color.html_is_valid(text):
		return Color(0, 0, 0, 0)
	return Color(text)


func palette_name(index: int) -> String:
	var group := palette_group(index)
	if group.is_empty():
		return "配色 %d" % index
	var title := String(group.get("name", "")).strip_edges()
	return title if not title.is_empty() else "配色 %d" % index


## 新建一组（返回 1 起的组号），默认三色取各类型默认皮肤色。
func add_palette_group(title: String = "") -> int:
	var group := {
		"name": title,
		"tap": String(PALETTE_DEFAULTS["tap"]),
		"hold": String(PALETTE_DEFAULTS["hold"]),
		"path": String(PALETTE_DEFAULTS["path"]),
	}
	palette.append(group)
	return palette.size()


## 删除一组；引用该组的音符回到默认色，后面的组号整体前移。
func remove_palette_group(index: int) -> void:
	if index < 1 or index > palette.size():
		return
	palette.remove_at(index - 1)
	for note in notes:
		if note.color == index:
			note.color = 0
		elif note.color > index:
			note.color -= 1


## 组号 → 使用它的音符数。
func palette_usage(index: int) -> int:
	var total := 0
	for note in notes:
		if note.color == index:
			total += 1
	return total


## 谱面里是否有音符使用自定义颜色（分组或单音符覆盖）。
func has_custom_note_colors() -> bool:
	for note in notes:
		if note.has_custom_color or note.color > 0:
			return true
	return false
