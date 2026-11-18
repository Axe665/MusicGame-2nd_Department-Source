class_name Chart
extends RefCounted

var format_version: int = 1
var audio_path: String = ""
var video_path: String = ""
var video_offset_ms: float = 0.0
var video_fps: float = 60.0
var video_opacity: float = 0.35
## 音符从出现到该打的时间（毫秒）。和 BPM 无关：BPM 描述谱面密度，
## 不该改变读谱时间。显示层再按「音符速度（倍率）」除一次。
const NOTE_FALL_MS := 1000.0
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


## 试玩镜像：音符与 Limit 红区各翻一份，形状/视图/时间共用。原谱不动。
## mode: "off"（原样返回）/ "lr"（左右翻转）/ "rot180"（旋转 180°）。
func mirrored_copy(mode: String) -> Chart:
	if mode != "lr" and mode != "rot180":
		return self
	var result := Chart.new()
	result.format_version = format_version
	result.audio_path = audio_path
	result.video_path = video_path
	result.video_offset_ms = video_offset_ms
	result.video_fps = video_fps
	result.video_opacity = video_opacity
	result.offset_ms = offset_ms
	result.difficulty = difficulty
	result.metadata = metadata.duplicate(true)
	result.timing = timing
	result.default_shape_id = default_shape_id
	result.shapes = shapes
	result.events = events
	result.shape_keys = shape_keys
	result.view_states = view_states
	result.load_warnings = load_warnings
	result.editor = editor
	result.palette = palette
	result._next_note_id = _next_note_id
	result._next_region_id = _next_region_id
	result._next_event_id = _next_event_id
	result.notes = []
	for note in notes:
		var copy := Note.from_dict(note.to_dict())
		if mode == "lr":
			copy.mirror_lr()
		else:
			copy.mirror_u()
		result.notes.append(copy)
	result.regions = []
	for region in regions:
		var copy := Region.from_dict(region.to_dict())
		var flipped := 180.0 - copy.angle if mode == "lr" else copy.angle + 180.0
		copy.angle = fposmod(flipped, 360.0)
		result.regions.append(copy)
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


## 同一条 Path 链上的全部 part（含自身），从 root 到末段。复制/粘贴要整链一起，
## 否则粘出来的 part 会指向原链，预览、试玩和存盘都把它当成别人的子部件跳过。
func path_chain(note: Note) -> Array[Note]:
	var chain: Array[Note] = [note]
	if note.type != "path":
		return chain
	var by_id := {}
	for other in notes:
		by_id[other.id] = other
	var root := note
	var guard := 0
	while root.path_prev_id >= 0 and by_id.has(root.path_prev_id) and guard < 64:
		root = by_id[root.path_prev_id]
		guard += 1
	chain = [root]
	var current := root
	guard = 0
	while current.path_next_id >= 0 and by_id.has(current.path_next_id) and guard < 64:
		current = by_id[current.path_next_id]
		if current.type != "path":
			break
		chain.append(current)
		guard += 1
	return chain


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


## 音频长度（毫秒）：导入歌曲或加载播放流时写入 editor，没有就返回 0。
func audio_length_ms() -> float:
	return maxf(0.0, float(editor.get("audio_length_ms", 0.0)))


## 音频最后一个拍的位置。offset 是音频偏移，换算回谱面毫秒要加回去。
func audio_end_beat() -> float:
	var length := audio_length_ms()
	if length <= 0.0:
		return 0.0
	return timing.chart_ms_to_beat(length + offset_ms)


## 音频与最后一个音符/区域/事件取大：播放和「音频结束」标记都用它。
func content_end_beat() -> float:
	return maxf(duration_beats(), audio_end_beat())


## 编辑器可滚动/可跳转的终点：内容末尾再留 4 小节。
func end_limit_beat() -> float:
	var last := content_end_beat()
	var bpb := maxf(1.0, float(timing.beats_per_bar_at(last)))
	return last + bpb * 4.0


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


## 音符飞行时长（毫秒，已含当前 BPM 不影响）。显示层再按音符速度倍率缩放。
func note_fall_ms() -> float:
	return NOTE_FALL_MS


## 改 BPM 之后，把 anchor 之后所有「按拍存」的东西按 factor 缩放拍位。
## factor = 新 BPM / 旧 BPM：大于 1 时同样的真实时间只占更少拍（保持毫秒位置）。
func scale_beats_after(anchor_beat: float, factor: float) -> void:
	if is_equal_approx(factor, 1.0):
		return
	for note in notes:
		note.beat = _scale_one(anchor_beat, note.beat, factor)
		note.end_beat = _scale_one(anchor_beat, note.end_beat, factor)
	for region in regions:
		region.start_beat = _scale_one(anchor_beat, region.start_beat, factor)
		region.end_beat = _scale_one(anchor_beat, region.end_beat, factor)
	for event in events:
		event.start_beat = _scale_one(anchor_beat, event.start_beat, factor)
		event.end_beat = _scale_one(anchor_beat, event.end_beat, factor)
	for key in shape_keys:
		key["beat"] = _scale_one(anchor_beat, float(key.get("beat", 0.0)), factor)
	for state in view_states:
		state.beat = _scale_one(anchor_beat, state.beat, factor)
	for point in timing.points:
		point.beat = _scale_one(anchor_beat, point.beat, factor)
	timing.sort_points()


static func _scale_one(anchor_beat: float, beat: float, factor: float) -> float:
	return anchor_beat + (beat - anchor_beat) * factor if beat > anchor_beat else beat
