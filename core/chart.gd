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

## 缓存版本：音符/关键帧/红区/事件/音频长度/offset 一旦变化就 +1。
## App.touch_chart()（拖动中）与 App._after_change()（提交）都会调 mark_dirty()。
var version: int = 0
## 音符/形状两套版本：拖形状帧时只让形状缓存失效，不能把 1 万音符的排序缓存也冲掉。
var note_version: int = 0
var ring_version: int = 0
var _stamp_notes := -1
var _stamp_shapes := -1
var _stamp_keys := -1
var _stamp_views := -1
var _stamp_duration := -1
var _stamp_anchors := -1
var _stamp_by_id := -1
var _stamp_roots := -1
var _stamp_max_len := -1
var _sorted_notes_cache: Array[Note] = []
var _sorted_shapes_cache: Array[BoundaryShape] = []
var _sorted_keys_cache: Array[Dictionary] = []
var _sorted_views_cache: Array[ViewState] = []
var _notes_by_id_cache: Dictionary = {}
var _path_roots_cache: Array[Note] = []
var _max_len_cache: float = 0.0
var _duration_cache: float = 0.0
var _content_end_cache: float = 0.0
var _anchor_index: Dictionary = {}


func mark_dirty() -> void:
	version += 1
	note_version += 1
	ring_version += 1
	_stamp_notes = -1
	_stamp_shapes = -1
	_stamp_keys = -1
	_stamp_views = -1
	_stamp_duration = -1
	_stamp_anchors = -1
	_stamp_by_id = -1
	_stamp_roots = -1
	_stamp_max_len = -1


## 只动形状/镜头：音符缓存保持有效，拖关键帧时不会每帧重排 1 万音符。
func mark_ring_dirty() -> void:
	version += 1
	ring_version += 1
	_stamp_shapes = -1
	_stamp_keys = -1
	_stamp_views = -1
	_stamp_duration = -1


## 音符缓存指纹：只跟音符数量和音符版本走。
func _note_stamp() -> int:
	return note_version * 1000003 + notes.size() * 10007


## 形状缓存指纹：关键帧/形状数量必须算进来，否则「加一帧不改音符」时
## App.mutate 的快照前后相同，会直接 early-return，帧在时间轴/存盘里消失。
func _ring_stamp() -> int:
	return ring_version * 1000003 + version * 31 \
		+ shape_keys.size() * 104729 + view_states.size() * 1299709 + shapes.size() * 15485863


## 内容末尾同时依赖音符与形状，所以两套版本都要算。
func _duration_stamp() -> int:
	return _note_stamp() * 31 + _ring_stamp() + regions.size() * 1009 \
		+ events.size() * 101 + timing.points.size() * 17 \
		+ int(audio_length_ms() * 10.0) + int(offset_ms * 10.0)


## Anchor 的配对：同一 pairId、同一拍即可，角度自由。
func anchor_partner(note: Note) -> Note:
	if note.type != "anchor" or note.pair_id.is_empty():
		return null
	var stamp := _note_stamp()
	if stamp != _stamp_anchors:
		_stamp_anchors = stamp
		_anchor_index.clear()
		for other in notes:
			if other.type != "anchor" or other.pair_id.is_empty():
				continue
			var key := "%s|%d" % [other.pair_id, roundi(other.beat * 10000.0)]
			if not _anchor_index.has(key):
				_anchor_index[key] = []
			(_anchor_index[key] as Array).append(other)
	var base := roundi(note.beat * 10000.0)
	for delta in [-1, 0, 1]:
		var bucket: Array = _anchor_index.get("%s|%d" % [note.pair_id, base + delta], [])
		for other in bucket:
			if other.id != note.id:
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
	# 镜头面板只保留推拉/滚转；保留 face_camera 兼容旧谱的倾斜/椭圆数据。
	metadata["face_camera"] = true


func get_shape(shape_id: String) -> BoundaryShape:
	return shapes.get(shape_id, null)


func get_default_shape() -> BoundaryShape:
	var shape: BoundaryShape = get_shape(default_shape_id)
	if shape == null and not shapes.is_empty():
		shape = shapes.values()[0]
	return shape


## 只读：返回内部缓存，调用方不要改它（要改就改 shape_keys 再 mark_dirty）。
## 稳定 id：多选、拖拽、撤销后选中都按 id 找键；旧文件在载入时补号。
func ensure_key_ids() -> void:
	var next := next_key_id()
	for key in shape_keys:
		if int(key.get("id", 0)) <= 0:
			key["id"] = next
			next += 1
	for state in view_states:
		if state.id <= 0:
			state.id = next
			next += 1


func next_key_id() -> int:
	var peak := 0
	for key in shape_keys:
		peak = maxi(peak, int(key.get("id", 0)))
	for state in view_states:
		peak = maxi(peak, state.id)
	return peak + 1


func shape_key_by_id(key_id: int) -> Dictionary:
	for key in shape_keys:
		if int(key.get("id", 0)) == key_id:
			return key
	return {}


func view_state_by_id(state_id: int) -> ViewState:
	for state in view_states:
		if state.id == state_id:
			return state
	return null


## 只读：镜头帧排序缓存。每帧 ViewState.evaluate 都要按拍找段，
## 不能再让调用方 duplicate+sort 一遍。
func sorted_view_states() -> Array[ViewState]:
	var stamp := _ring_stamp()
	if stamp == _stamp_views:
		return _sorted_views_cache
	_stamp_views = stamp
	var result: Array[ViewState] = []
	for state in view_states:
		result.append(state)
	result.sort_custom(func(a: ViewState, b: ViewState) -> bool: return a.beat < b.beat)
	_sorted_views_cache = result
	return _sorted_views_cache


func sorted_shape_keys() -> Array[Dictionary]:
	var stamp := _ring_stamp()
	if stamp == _stamp_keys:
		return _sorted_keys_cache
	_stamp_keys = stamp
	var result: Array[Dictionary] = []
	for key in shape_keys:
		if key is Dictionary:
			result.append(key)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("beat", 0.0)) < float(b.get("beat", 0.0)))
	_sorted_keys_cache = result
	return _sorted_keys_cache


## 播放头正好落在关键帧上时返回那一帧，否则返回空字典。
func shape_key_at(beat: float) -> Dictionary:
	for key in shape_keys:
		if absf(float(key.get("beat", -1.0)) - beat) < 0.0005:
			return key
	return {}


## 只读：返回内部缓存。
func sorted_shapes() -> Array[BoundaryShape]:
	var stamp := _ring_stamp()
	if stamp == _stamp_shapes:
		return _sorted_shapes_cache
	_stamp_shapes = stamp
	var result: Array[BoundaryShape] = []
	for shape in shapes.values():
		if shape is BoundaryShape:
			result.append(shape)
	result.sort_custom(func(a: BoundaryShape, b: BoundaryShape) -> bool: return a.id < b.id)
	_sorted_shapes_cache = result
	return _sorted_shapes_cache


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


## 只读：返回内部缓存，调用方不要排序/修改它。
func sorted_notes() -> Array[Note]:
	var stamp := _note_stamp()
	if stamp == _stamp_notes:
		return _sorted_notes_cache
	_stamp_notes = stamp
	var result := notes.duplicate()
	result.sort_custom(func(a: Note, b: Note) -> bool: return a.beat < b.beat)
	_sorted_notes_cache = result
	return _sorted_notes_cache


## id → 音符（只读）。Path 链、命中检测每帧都要它，别再自己建 10k 字典。
func notes_by_id() -> Dictionary:
	var stamp := _note_stamp()
	if stamp == _stamp_by_id:
		return _notes_by_id_cache
	_stamp_by_id = stamp
	var result := {}
	for note in notes:
		result[note.id] = note
	_notes_by_id_cache = result
	return _notes_by_id_cache


## 全谱最长的音符时长（拍）：Hold 的可见回溯窗口用它，别再写死 128 拍。
func max_note_length_beats() -> float:
	var stamp := _note_stamp()
	if stamp == _stamp_max_len:
		return _max_len_cache
	_stamp_max_len = stamp
	var longest := 0.0
	for note in notes:
		longest = maxf(longest, note.end_beat - note.beat)
	_max_len_cache = longest
	return _max_len_cache


## Path 链的根（part0 或没有父链的 path），按拍排序（只读）。
func path_roots() -> Array[Note]:
	var stamp := _note_stamp()
	if stamp == _stamp_roots:
		return _path_roots_cache
	_stamp_roots = stamp
	var by_id := notes_by_id()
	var result: Array[Note] = []
	for note in notes:
		if note.type != "path":
			continue
		if note.path_prev_id >= 0 and by_id.has(note.path_prev_id):
			continue
		result.append(note)
	result.sort_custom(func(a: Note, b: Note) -> bool: return a.beat < b.beat)
	_path_roots_cache = result
	return _path_roots_cache


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
	var stamp := _duration_stamp()
	if stamp == _stamp_duration:
		return _duration_cache
	_stamp_duration = stamp
	var last := 0.0
	for note in notes:
		last = maxf(last, maxf(note.beat, note.end_beat))
	for region in regions:
		last = maxf(last, region.end_beat)
	for event in events:
		last = maxf(last, event.end_beat + maxf(0.0, event.restore_duration))
	# 形状/镜头关键帧也要算进内容末尾：否则时间轴「全部」和 seek 上限
	# 只按音符算，落在音符之后的帧永远滚不到、跳不到。
	for key in shape_keys:
		last = maxf(last, float(key.get("beat", 0.0)))
	for state in view_states:
		last = maxf(last, state.beat)
	_duration_cache = last
	_content_end_cache = maxf(last, audio_end_beat())
	return _duration_cache


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
	duration_beats()
	return _content_end_cache


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
	mark_dirty()
	for key in shape_keys:
		key["beat"] = _scale_one(anchor_beat, float(key.get("beat", 0.0)), factor)
	for state in view_states:
		state.beat = _scale_one(anchor_beat, state.beat, factor)
	for point in timing.points:
		point.beat = _scale_one(anchor_beat, point.beat, factor)
	timing.sort_points()


static func _scale_one(anchor_beat: float, beat: float, factor: float) -> float:
	return anchor_beat + (beat - anchor_beat) * factor if beat > anchor_beat else beat
