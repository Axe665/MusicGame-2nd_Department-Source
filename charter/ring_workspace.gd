class_name RingWorkspace
extends Control

## 环编辑工作区：形状关键帧 + 形变时间轴 + 镜头，一屏直操作。
## 形状关键帧是唯一真源；BoundaryEvent 只在存盘时双写给旧版本。

signal closed
signal play_toggled
signal loop_requested(start: float, end: float, enabled: bool)

const ZOOM_LEVELS := [8.0, 16.0, 32.0, 64.0]
const THUMB_SIZE := Vector2(64, 64)
const EASINGS := ["linear", "in-out"]


## 一段关键帧的长度文字：不足 1 小节写拍，超过写「N 小节 M 拍」。
static func span_label(beats: float, bpb: float) -> String:
	bpb = maxf(1.0, bpb)
	var bars := floori(beats / bpb + 0.0001)
	var rest := beats - float(bars) * bpb
	if bars <= 0:
		return "%s 拍" % _beat_num(rest)
	if rest < 0.005:
		return "%d 小节" % bars
	return "%d 小节 %s 拍" % [bars, _beat_num(rest)]


## 页脚用的 m:ss.mmm。ring 时间轴是拍，这里是谱面毫秒。
static func _fmt_clock(ms: float) -> String:
	var total := maxf(0.0, ms)
	var minutes := int(total / 60000.0)
	var seconds := int(fmod(total, 60000.0) / 1000.0)
	var millis := int(fmod(total, 1000.0))
	return "%d:%02d.%03d" % [minutes, seconds, millis]


## 标尺上的 m:ss（不带毫秒）：小节号和秒数并排，一屏内能对上时间。
static func _fmt_short(ms: float) -> String:
	var total := maxf(0.0, ms)
	return "%d:%02d" % [int(total / 60000.0), int(fmod(total, 60000.0) / 1000.0)]


static func _beat_num(value: float) -> String:
	var snapped := snappedf(value, 0.01)
	if absf(snapped - round(snapped)) < 0.001:
		return str(int(round(snapped)))
	return String.num(snapped, 2)


## 第 index 帧的保持段到哪结束：下一帧，或最后一个内容/音频结束；空谱至少留 1 小节。
static func span_end(beats: Array, index: int, content_end: float, bpb: float) -> float:
	if index < 0 or index >= beats.size():
		return 0.0
	var start := float(beats[index])
	if index + 1 < beats.size():
		return float(beats[index + 1])
	var end := maxf(start, content_end)
	if end - start < 0.001:
		end = start + maxf(1.0, bpb)
	return end


var _app: Node = null
var _preview: Preview3D = null
var _preview_slot: Control = null
var _restore_preview: Callable = Callable()
var _thumbs: GridContainer = null
var _panel: VBoxContainer = null
var _timeline: Timeline = null
var _title: Label = null
var _beat_spin: SpinBox = null
var _time_label: Label = null
var _fps_label: Label = null
var _fps_accum := 0.0
var _zoom_index := 1
## 播放时时间轴是否跟着播放头滚（时间轴选项里可关）。
var follow_playhead_view := true
var _view_start := 0.0
var onion_skin := false
var _fold_open: Dictionary = {}
var _play_button: Button = null
var _loop_button: Button = null
var _loop_on := false
var _pad: ShapePadOverlay = null

var _thumb_signature := ""
var _drag_kind := ""
var _drag_key: Dictionary = {}
var _drag_view: ViewState = null
var _last_key_beat: float = -999.0
var _sync_last_msec: int = 0
var _sync_last_beat: float = -99999.0
var _sync_last_spin: float = -99999.0


class ShapeThumb:
	extends Control
	var workspace: RingWorkspace
	var shape_id: String = ""
	var selected := false

	func _init(p_workspace: RingWorkspace, p_id: String) -> void:
		workspace = p_workspace
		shape_id = p_id
		custom_minimum_size = RingWorkspace.THUMB_SIZE
		mouse_filter = Control.MOUSE_FILTER_STOP
		tooltip_text = p_id

	func _draw() -> void:
		var chart: Chart = workspace.chart()
		if chart == null:
			return
		var shape := chart.get_shape(shape_id)
		if shape == null:
			return
		var center := size * 0.5
		var scale := minf(size.x, size.y) * 0.42 / 400.0
		var points := PackedVector2Array()
		for i in 73:
			var data := shape.point_at(float(i) / 72.0)
			if bool(data.get("gap", false)):
				continue
			points.append(center + (data.point as Vector2) * scale)
		if points.size() > 1:
			draw_polyline(points, UITheme.CORAL if selected else UITheme.CYAN, 2.0, true)
		if selected:
			draw_rect(Rect2(Vector2.ZERO, size), UITheme.CORAL, false, 1.0)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			workspace.open_pad_for_shape(shape_id)
			accept_event()


class Timeline:
	extends Control
	## 参考 Flash/Animate 的 Timeline：顶部标题 + 标尺，中间四行（形状/镜头/边界事件/BPM），
	## 底部页脚显示拍、ms、总长、帧率。每行有显隐/锁定。
	const GUTTER := 168.0
	const HEADER_H := 24.0
	const RULER_H := 48.0
	const LANE_TOP := 50.0
	const LANE_H := 34.0
	const LANE_GAP := 4.0
	const FOOTER_H := 24.0
	const BAR_H := 18.0
	const KEY_SIZE := 9.0
	const LABEL_MIN := 84.0
	const EDGE_HIT := 5.0
	const KEY_HIT := 8.0

	var workspace: RingWorkspace
	var _drag_kind := ""
	var _hover_lane := -1
	var _hover_index := -1
	var _hover_pos := Vector2(-9999, -9999)
	var hidden_lanes: Dictionary = {}
	var locked_lanes: Dictionary = {}
	var show_grid := true
	var follow_playhead := true
	var _new_button: Button = null
	var _delete_button: Button = null
	var _menu: MenuButton = null

	func _init(p_workspace: RingWorkspace) -> void:
		workspace = p_workspace
		custom_minimum_size = Vector2(0, 224)
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true
		_new_button = Button.new()
		_new_button.custom_minimum_size = Vector2(66, 20)
		_new_button.text = "+ 形状"
		_new_button.add_theme_font_size_override("font_size", 10)
		_new_button.tooltip_text = "新建一个形状（等于新建一层）"
		_new_button.pressed.connect(func() -> void: workspace._new_shape())
		add_child(_new_button)
		_delete_button = Button.new()
		_delete_button.custom_minimum_size = Vector2(66, 20)
		_delete_button.text = "− 形状"
		_delete_button.add_theme_font_size_override("font_size", 10)
		_delete_button.tooltip_text = "删除当前形状"
		_delete_button.pressed.connect(func() -> void: workspace._delete_shape())
		add_child(_delete_button)
		_menu = MenuButton.new()
		_menu.text = "⋯"
		_menu.tooltip_text = "时间轴选项"
		var popup := _menu.get_popup()
		popup.add_item("适配全部", 1)
		popup.add_item("跳到开头", 2)
		popup.add_item("跳到结尾", 3)
		popup.add_check_item("显示拍线", 4)
		popup.set_item_checked(popup.get_item_index(4), true)
		popup.add_check_item("跟随播放头", 5)
		popup.set_item_checked(popup.get_item_index(5), true)
		popup.id_pressed.connect(_on_menu)
		add_child(_menu)

	func _ready() -> void:
		_layout_children()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			_layout_children()

	func _layout_children() -> void:
		if _new_button == null:
			return
		var y := size.y - FOOTER_H + 2.0
		_new_button.position = Vector2(6.0, y)
		_delete_button.position = Vector2(76.0, y)
		if _menu != null:
			_menu.position = Vector2(size.x - 38.0, 1.0)

	func _on_menu(id: int) -> void:
		match id:
			1:
				workspace.fit_all_timeline()
			2:
				workspace.seek(0.0)
			3:
				var chart: Chart = workspace.chart()
				if chart != null:
					workspace.seek(chart.content_end_beat())
			4:
				show_grid = not show_grid
				_menu.get_popup().set_item_checked(_menu.get_popup().get_item_index(4), show_grid)
			5:
				follow_playhead = not follow_playhead
				workspace.follow_playhead_view = follow_playhead
				_menu.get_popup().set_item_checked(_menu.get_popup().get_item_index(5), follow_playhead)
		queue_redraw()

	func _x_for(beat: float) -> float:
		return GUTTER + (beat - workspace.window_start()) / maxf(0.001, workspace.view_beats()) * (size.x - GUTTER)

	func _beat_at(x: float) -> float:
		return workspace.window_start() + ((x - GUTTER) / maxf(1.0, size.x - GUTTER)) * workspace.view_beats()

	func _lane_top(lane: int) -> float:
		return LANE_TOP + float(lane) * (LANE_H + LANE_GAP)

	func _lane_center(lane: int) -> float:
		return _lane_top(lane) + LANE_H * 0.5

	func _lane_at(y: float) -> int:
		for lane in 4:
			if y >= _lane_top(lane) and y <= _lane_top(lane) + LANE_H:
				return lane
		return -1

	func _lane_items(chart: Chart, lane: int) -> Array:
		match lane:
			0:
				return chart.sorted_shape_keys()
			1:
				var states: Array = chart.view_states.duplicate()
				states.sort_custom(func(a: ViewState, b: ViewState) -> bool: return a.beat < b.beat)
				return states
			2:
				var events: Array = chart.events.duplicate()
				events.sort_custom(func(a, b) -> bool: return float(a.beat) < float(b.beat))
				return events
			3:
				var points: Array = chart.timing.points.duplicate()
				points.sort_custom(func(a, b) -> bool: return float(a.beat) < float(b.beat))
				return points
		return []

	func _item_beat(item) -> float:
		if item is Dictionary:
			return float(item.get("beat", 0.0))
		return float((item as Object).get("beat"))

	func _item_easing(item) -> String:
		if item is Dictionary:
			return String(item.get("easing", "in-out"))
		if item is ViewState:
			return (item as ViewState).easing
		return "linear"

	func _lane_name(lane: int) -> String:
		return ["形状", "镜头", "边界事件", "BPM"][clampi(lane, 0, 3)]

	func _lane_colour(lane: int) -> Color:
		match lane:
			0:
				return UITheme.CYAN
			1:
				return UITheme.AMBER
			2:
				return UITheme.CORAL
			3:
				return Color(0.62, 0.85, 0.62)
		return Color.WHITE

	func _item_beats(items: Array) -> Array[float]:
		var beats: Array[float] = []
		for item in items:
			beats.append(_item_beat(item))
		return beats

	func _draw() -> void:
		var chart: Chart = workspace.chart()
		draw_rect(Rect2(Vector2.ZERO, size), Color("#0B0D12"))
		draw_rect(Rect2(Vector2(0, 0), Vector2(size.x, HEADER_H)), Color("#10131B"))
		draw_rect(Rect2(Vector2(0, 0), Vector2(GUTTER, size.y)), Color("#0E1118"))
		draw_line(Vector2(GUTTER, 0), Vector2(GUTTER, size.y), Color(1, 1, 1, 0.12), 1.0)
		draw_string(UITheme.FONT_REGULAR, Vector2(8, 16), "时间轴", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
			Color(1, 1, 1, 0.82))
		draw_string(UITheme.mono_font(), Vector2(70, 16), "形状 / 镜头 / 边界事件 / BPM",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.38))
		if chart == null:
			return
		var start := workspace.window_start()
		var span := workspace.view_beats()
		var bpb := maxf(1.0, chart.timing.beats_per_bar_at(start))
		var snap_division: int = workspace.snap_division()
		_draw_ruler(start, span, bpb)
		# 内容结束拍是 O(音符+红区+事件) 的扫描：一次重绘只算一遍，别每个轨道各扫一遍。
		var content_end := chart.content_end_beat()
		var lane_items: Array = []
		for lane in 4:
			var items := _lane_items(chart, lane)
			lane_items.append(items)
			if not hidden_lanes.has(lane):
				_draw_lane(lane, items, chart, bpb, snap_division, content_end)
		_draw_gutter(lane_items)
		_draw_playhead()
		_draw_status(chart, lane_items, bpb, content_end)

	func _draw_ruler(start: float, span: float, bpb: float) -> void:
		var font := UITheme.mono_font()
		var chart: Chart = workspace.chart()
		var beat_px := (size.x - GUTTER) / maxf(0.001, span)
		var bar_px := beat_px * bpb
		var step := 1
		# 64px 才放得下「小节 + 时间」双标注；抽稀比挤成一团好读。
		while float(step) * bar_px < 64.0 and step < 64:
			step *= 2
		var first := floori(start / bpb)
		var last := ceili((start + span) / bpb)
		for bar in range(first, last + 1):
			var x := _x_for(float(bar) * bpb)
			if x < GUTTER - 1.0 or x > size.x + 1.0:
				continue
			draw_line(Vector2(x, RULER_H - 11.0), Vector2(x, RULER_H), Color(1, 1, 1, 0.45), 1.0)
			if bar % step == 0:
				# 标尺双单位：小节号 + 该小节起点的时间，找段落不用心算 BPM。
				var label := str(bar + 1)
				if chart != null:
					label = "%d · %s" % [bar + 1, RingWorkspace._fmt_short(
						chart.timing.beat_to_chart_ms(float(bar) * bpb) + chart.offset_ms)]
				draw_string(font, Vector2(x + 3, RULER_H - 13.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.75))
		if beat_px >= 12.0:
			for beat in range(floori(start), ceili(start + span) + 1):
				var x := _x_for(float(beat))
				if x < GUTTER or x > size.x:
					continue
				draw_line(Vector2(x, RULER_H - 5.0), Vector2(x, RULER_H), Color(1, 1, 1, 0.16), 1.0)
		draw_line(Vector2(GUTTER, RULER_H), Vector2(size.x, RULER_H), Color(1, 1, 1, 0.10), 1.0)

	func _draw_lane(lane: int, items: Array, chart: Chart, bpb: float, snap_division: int, content_end: float) -> void:
		var top := _lane_top(lane)
		var color := _lane_colour(lane)
		draw_rect(Rect2(Vector2(GUTTER, top), Vector2(size.x - GUTTER, LANE_H)), Color(color.r, color.g, color.b, 0.035 if lane == 0 else 0.02))
		if show_grid:
			_draw_lane_grid(lane, bpb, snap_division)
		if items.is_empty():
			draw_string(UITheme.FONT_REGULAR, Vector2(GUTTER + 8, _lane_center(lane) + 4), "还没有关键帧", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.28))
			return
		var beats := _item_beats(items)
		for i in items.size():
			var start := beats[i]
			var seg_bpb := maxf(1.0, chart.timing.beats_per_bar_at(start))
			var end := RingWorkspace.span_end(beats, i, content_end, seg_bpb)
			if end <= start:
				end = start + 0.25
			var x0 := _x_for(start)
			var x1 := _x_for(end)
			if x1 < GUTTER - 4.0 or x0 > size.x + 4.0:
				continue
			var key_visible := x0 >= GUTTER - 0.5
			x0 = clampf(x0, GUTTER + 1.0, size.x - 1.0)
			x1 = clampf(x1, GUTTER + 1.0, size.x - 1.0)
			var y := _lane_center(lane) - BAR_H * 0.5
			var hovered := _hover_lane == lane and _hover_index == i
			var selected := absf(workspace.playhead() - start) < 0.01
			var fill_alpha := 0.34 if selected else (0.24 if hovered else 0.16)
			var border_alpha := 0.90 if selected else (0.68 if hovered else 0.45)
			var rect := Rect2(Vector2(x0, y), Vector2(maxf(2.0, x1 - x0), BAR_H))
			var span_beats := end - start
			# 形状帧可以只花一段的一部分在变形上，剩下的时间保持到下一帧。
			var morph := span_beats
			if lane == 0 and items[i] is Dictionary:
				morph = BoundaryRuntime.morph_beats(items[i], span_beats)
			draw_rect(rect, Color(color.r, color.g, color.b, fill_alpha))
			var morph_rect := rect
			if morph < span_beats - 0.0001:
				var hold_x := clampf(_x_for(start + morph), x0, x1)
				morph_rect = Rect2(Vector2(x0, y), Vector2(maxf(2.0, hold_x - x0), BAR_H))
				# 保持段压暗：在已经画好的填充上再叠一层半透明也是「更亮」，得往黑里压。
				draw_rect(Rect2(Vector2(hold_x, y), Vector2(maxf(0.0, x1 - hold_x), BAR_H)),
					Color(0.02, 0.03, 0.04, 0.62))
				draw_line(Vector2(hold_x, y), Vector2(hold_x, y + BAR_H),
					Color(color.r, color.g, color.b, 0.8), 1.0)
			draw_rect(rect, Color(color.r, color.g, color.b, border_alpha), false, 1.0)
			_draw_easing(morph_rect, String(_item_easing(items[i])), color)
			# 两端方向箭头：这段是从左往右走的，不用猜。
			_draw_flow_arrow(x0 + 5.0, _lane_center(lane), color, 0.9)
			var text_left := x0 + 14.0
			if lane == 0 and rect.size.x >= 110.0 and items[i] is Dictionary:
				var shape := chart.get_shape(String(items[i].get("shape_id", "")))
				if shape != null:
					_draw_shape_thumb(Rect2(Vector2(x0 + 14.0, y + 2.0), Vector2(14.0, 14.0)), shape, color)
					text_left = x0 + 32.0
			_draw_flow_arrow(rect.end.x - 7.0, _lane_center(lane), color, 0.9)
			if rect.size.x >= LABEL_MIN:
				var secs := (chart.timing.beat_to_chart_ms(end) - chart.timing.beat_to_chart_ms(start)) * 0.001
				var text := "%s · %.2f 秒" % [RingWorkspace.span_label(span_beats, seg_bpb), secs]
				if rect.size.x >= 190.0:
					text = "%.2f→%.2f 拍 · %s · %.2f 秒" % [
						start, end, RingWorkspace.span_label(span_beats, seg_bpb), secs]
				draw_string(UITheme.FONT_REGULAR, Vector2(text_left, y + 15), text,
					HORIZONTAL_ALIGNMENT_LEFT, maxf(0.0, rect.end.x - 12.0 - text_left), 11,
					Color(1, 1, 1, 0.92 if (selected or hovered) else 0.72))
			if key_visible:
				var key_rect := Rect2(Vector2(x0 - KEY_SIZE * 0.5, _lane_center(lane) - KEY_SIZE * 0.5), Vector2(KEY_SIZE, KEY_SIZE))
				draw_rect(key_rect, Color(color.r, color.g, color.b, 1.0 if selected else 0.9))
				draw_rect(key_rect, Color(0.05, 0.06, 0.08, 0.9), false, 1.0)
				if selected:
					draw_rect(key_rect.grow(3.0), UITheme.CORAL, false, 1.5)
		# 最后一段的端帽：Animate 的「竖线 + 空心方块」。
		var tail_x := _x_for(RingWorkspace.span_end(beats, beats.size() - 1, content_end, maxf(1.0, chart.timing.beats_per_bar_at(beats[-1]))))
		if tail_x <= size.x - 1.0:
			var tail_end := clampf(tail_x, GUTTER, size.x - 3.0)
			var ty := _lane_center(lane)
			draw_line(Vector2(tail_end, ty - 8.0), Vector2(tail_end, ty + 8.0), Color(color.r, color.g, color.b, 0.55), 1.5)
			draw_rect(Rect2(Vector2(tail_end - 3.0, ty + 5.0), Vector2(6, 6)), Color(color.r, color.g, color.b, 0.75), false, 1.0)

	func _draw_easing(rect: Rect2, easing: String, color: Color) -> void:
		if rect.size.x < 16.0:
			return
		var points := PackedVector2Array()
		var steps := 14
		for i in steps:
			var t := float(i) / float(steps - 1)
			var eased := Ease.apply(easing, t)
			points.append(Vector2(lerpf(rect.position.x + 3.0, rect.end.x - 3.0, t), rect.end.y - 5.0 - (t - eased) * 12.0))
		draw_polyline(points, Color(color.r, color.g, color.b, 0.80), 1.2, true)


	## 段块两端的方向箭头：一个 5px 的实心三角，读作「这段时间往右走」。
	func _draw_flow_arrow(x: float, center_y: float, color: Color, alpha: float) -> void:
		draw_colored_polygon(PackedVector2Array([
			Vector2(x, center_y - 4.0), Vector2(x + 5.0, center_y), Vector2(x, center_y + 4.0),
		]), Color(color.r, color.g, color.b, alpha))


	## 段块里的形状缩略图：按边界真实采样画，方形/星形/椭圆一眼能分。
	func _draw_shape_thumb(box: Rect2, shape: BoundaryShape, color: Color) -> void:
		var raw := shape.sample_points(24)
		var points := PackedVector2Array()
		var low := Vector2(INF, INF)
		var high := Vector2(-INF, -INF)
		for item in raw:
			if bool(item.get("gap", false)):
				continue
			var p: Vector2 = item.get("point", Vector2.ZERO)
			low = Vector2(minf(low.x, p.x), minf(low.y, p.y))
			high = Vector2(maxf(high.x, p.x), maxf(high.y, p.y))
			points.append(p)
		if points.size() < 3:
			return
		var span := high - low
		var scale := minf(box.size.x / maxf(0.001, span.x), box.size.y / maxf(0.001, span.y))
		var origin := box.position + box.size * 0.5 - (low + span * 0.5) * scale
		var mapped := PackedVector2Array()
		for p in points:
			mapped.append(origin + p * scale)
		if mapped.size() > 1:
			mapped.append(mapped[0])
		draw_polyline(mapped, Color(color.r, color.g, color.b, 0.8), 1.0, true)

	func _draw_lane_grid(lane: int, bpb: float, snap_division: int) -> void:
		var top := _lane_top(lane)
		var start := workspace.window_start()
		var span := workspace.view_beats()
		var beat_px := (size.x - GUTTER) / maxf(0.001, span)
		var half := LANE_H * 0.5
		for beat in range(floori(start), ceili(start + span) + 1):
			var x := _x_for(float(beat))
			if x < GUTTER or x > size.x:
				continue
			var is_bar := posmod(beat, int(maxf(1.0, bpb))) == 0
			draw_line(Vector2(x, top), Vector2(x, top + LANE_H), Color(1, 1, 1, 0.09 if is_bar else 0.04), 1.0)
		var step := GridDivisions.step_beats(snap_division)
		if step > 0.0 and step * beat_px >= 7.0:
			var b := floorf(start / step) * step
			while b <= start + span:
				if absf(b - round(b)) > 0.001:
					var x := _x_for(b)
					if x >= GUTTER and x <= size.x:
						draw_line(Vector2(x, top + 4.0), Vector2(x, top + LANE_H - 4.0), Color(1, 1, 1, 0.022), 1.0)
				b += step

	func _draw_gutter(lane_items: Array) -> void:
		var font := UITheme.FONT_REGULAR
		for lane in 4:
			var color := _lane_colour(lane)
			var center := _lane_center(lane)
			var hidden := hidden_lanes.has(lane)
			var locked := locked_lanes.has(lane)
			var tint := Color(1, 1, 1, 0.3) if (hidden or locked) else color
			draw_rect(Rect2(Vector2(6, center - 9), Vector2(3, 18)), tint)
			# 眼睛
			draw_arc(Vector2(24, center), 4.5, 0, TAU, 12, tint if not hidden else Color(1, 1, 1, 0.25), 1.0)
			draw_circle(Vector2(24, center), 1.8, tint)
			if hidden:
				draw_line(Vector2(19, center - 5), Vector2(29, center + 5), UITheme.CORAL, 1.2)
			# 锁
			var lock_colour := UITheme.CORAL if locked else Color(1, 1, 1, 0.22)
			draw_rect(Rect2(Vector2(36, center - 1), Vector2(8, 6)), lock_colour, false, 1.0)
			if locked:
				draw_arc(Vector2(40, center - 2), 3.0, PI, TAU, 8, lock_colour, 1.0)
			draw_string(font, Vector2(52, center + 4), _lane_name(lane), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, tint)
			var items: Array = lane_items[lane] if lane < lane_items.size() else []
			draw_string(UITheme.mono_font(), Vector2(126, center + 4), str(items.size()),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.38))

	func _draw_playhead() -> void:
		var px := _x_for(workspace.playhead())
		if px < GUTTER or px > size.x:
			return
		draw_line(Vector2(px, RULER_H), Vector2(px, size.y - FOOTER_H), UITheme.CORAL, 1.5)
		draw_colored_polygon(PackedVector2Array([Vector2(px - 5, RULER_H - 10), Vector2(px + 5, RULER_H - 10), Vector2(px, RULER_H)]), UITheme.CORAL)

	func _draw_status(chart: Chart, lane_items: Array, bpb: float, content_end: float) -> void:
		draw_rect(Rect2(0, size.y - FOOTER_H, size.x, FOOTER_H), Color("#10131B"))
		var beat := workspace.playhead()
		var ms := chart.timing.beat_to_chart_ms(beat) + chart.offset_ms
		var total_ms := chart.timing.beat_to_chart_ms(content_end) + chart.offset_ms
		var text := "当前 %s · %.2f 拍 · 总长 %s · %d FPS · 吸附 %s" % [
			RingWorkspace._fmt_clock(ms), beat,
			RingWorkspace._fmt_clock(total_ms), int(Engine.get_frames_per_second()),
			GridDivisions.label(workspace.snap_division())]
		if _hover_index >= 0 and _hover_lane >= 0:
			var items: Array = lane_items[_hover_lane] if _hover_lane < lane_items.size() else []
			if _hover_index < items.size():
				var beats := _item_beats(items)
				var start := beats[_hover_index]
				var end := RingWorkspace.span_end(beats, _hover_index, content_end, bpb)
				text = "%s · %s → %s · %s" % [
					_lane_name(_hover_lane), chart.timing.format_beat(start),
					chart.timing.format_beat(end), RingWorkspace.span_label(end - start, bpb)]
		draw_string(UITheme.FONT_REGULAR, Vector2(152, size.y - 7), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
			Color(1, 1, 1, 0.48))

	func _gui_input(event: InputEvent) -> void:
		if workspace.chart() == null:
			return
		if event is InputEventMouseButton:
			if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
				var dir := -1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
				if event.ctrl_pressed:
					workspace.zoom_timeline(-1 if dir < 0 else 1)
				else:
					workspace.scroll_timeline(dir)
				accept_event()
				return
			if event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed:
					_press(event.position, event)
				else:
					var was_scrubbing := _drag_kind == "playhead"
					_drag_kind = ""
					if workspace.dragging():
						workspace.end_drag()
					elif was_scrubbing:
						workspace.finish_scrub()
				accept_event()
		elif event is InputEventMouseMotion:
			if _drag_kind != "":
				if _drag_kind == "playhead":
					workspace.seek(workspace.snap(_beat_at(event.position.x)))
				else:
					workspace.drag_to(_beat_at(event.position.x))
				accept_event()
			else:
				_update_hover(event.position)

	func _update_hover(pos: Vector2) -> void:
		# 鼠标事件可能 500Hz；同一位置不重复排序关键帧。
		if pos.distance_squared_to(_hover_pos) < 2.25:
			return
		_hover_pos = pos
		var lane := _lane_at(pos.y)
		var index := -1
		if lane >= 0 and pos.x > GUTTER and not hidden_lanes.has(lane) and not locked_lanes.has(lane):
			var chart: Chart = workspace.chart()
			var items := _lane_items(chart, lane)
			var beats := _item_beats(items)
			for i in items.size():
				var sx := _x_for(beats[i])
				var bpb := maxf(1.0, chart.timing.beats_per_bar_at(beats[i]))
				var ex := _x_for(RingWorkspace.span_end(beats, i, chart.content_end_beat(), bpb))
				if absf(pos.x - sx) <= KEY_HIT or (pos.x > sx and pos.x < ex):
					index = i
					break
		if lane != _hover_lane or index != _hover_index:
			_hover_lane = lane
			_hover_index = index
			queue_redraw()

	func _press(pos: Vector2, event: InputEventMouseButton) -> void:
		var lane := _lane_at(pos.y)
		if pos.x <= GUTTER:
			# 左侧图层栏：眼睛 / 锁。
			if lane >= 0:
				if pos.x < 33.0:
					if hidden_lanes.has(lane):
						hidden_lanes.erase(lane)
					else:
						hidden_lanes[lane] = true
					queue_redraw()
				elif pos.x < 48.0:
					if locked_lanes.has(lane):
						locked_lanes.erase(lane)
					else:
						locked_lanes[lane] = true
					queue_redraw()
			return
		if pos.y <= RULER_H:
			_drag_kind = "playhead"
			workspace.seek(workspace.snap(_beat_at(pos.x)))
			return
		if lane < 0:
			workspace.seek(workspace.snap(_beat_at(pos.x)))
			return
		if hidden_lanes.has(lane) or locked_lanes.has(lane):
			return
		var chart: Chart = workspace.chart()
		var items := _lane_items(chart, lane)
		var beats := _item_beats(items)
		# 关键帧方块：命中就选中并开始拖时间。
		for i in items.size():
			if absf(pos.x - _x_for(beats[i])) <= KEY_HIT:
				workspace.seek(beats[i])
				if event.double_click:
					if lane == 0:
						workspace.open_pad_for_current()
					return
				if lane <= 1:
					_begin_item_drag(lane, items[i])
				return
		# 段块右缘：拖下一帧；段块本身：选中该段起点。
		for i in items.size() - 1:
			var sx := _x_for(beats[i])
			var ex := _x_for(beats[i + 1])
			if pos.x >= sx - 2.0 and pos.x <= ex + 2.0:
				if absf(pos.x - ex) <= EDGE_HIT:
					workspace.seek(beats[i + 1])
					if lane <= 1:
						_begin_item_drag(lane, items[i + 1])
					return
				workspace.seek(beats[i])
				return
		workspace.seek(workspace.snap(_beat_at(pos.x)))

	func _begin_item_drag(lane: int, item) -> void:
		if lane == 0:
			workspace.begin_key_drag(item)
			_drag_kind = "key"
		else:
			workspace.begin_view_drag(item)
			_drag_kind = "view"


## 2D 简图：画形状用的浮层，改完立刻反映到背景 3D。
## 标题栏可拖、右下角可缩放，位置和大小记进设置。
class ShapePadOverlay:
	extends Control
	var workspace: RingWorkspace
	var shape_id: String = ""
	var shape: BoundaryShape = null
	var _drag_vertex := -1
	var _canvas: Control = null
	var _box: Panel = null
	var _dragging_window := false
	var _resizing := false
	var _grab_offset := Vector2.ZERO
	var _resize_start := Vector2.ZERO
	var _resize_size := Vector2.ZERO

	func _init(p_workspace: RingWorkspace) -> void:
		workspace = p_workspace
		visible = false
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_STOP
		var dim := ColorRect.new()
		dim.color = Color(0, 0, 0, 0.55)
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(dim)
		_box = Panel.new()
		_box.set_anchors_preset(Control.PRESET_TOP_LEFT)
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#10131B")
		style.set_corner_radius_all(6)
		_box.add_theme_stylebox_override("panel", style)
		add_child(_box)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 6)
		_box.add_child(col)
		col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		col.offset_left = 10
		col.offset_right = -10
		col.offset_top = 8
		col.offset_bottom = -8

		var header := HBoxContainer.new()
		header.mouse_filter = Control.MOUSE_FILTER_STOP
		header.gui_input.connect(_window_input)
		col.add_child(header)
		var title := Label.new()
		title.text = "画形状，拖标题栏移动，右下角缩放"
		UITheme.style_section(title)
		header.add_child(title)
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(spacer)
		var close := Button.new()
		close.text = "完成"
		close.pressed.connect(close_pad)
		header.add_child(close)

		var quick := HBoxContainer.new()
		quick.add_theme_constant_override("separation", 4)
		col.add_child(quick)
		quick.add_child(_button("放大", func() -> void: _scale_shape(1.1)))
		quick.add_child(_button("缩小", func() -> void: _scale_shape(1.0 / 1.1)))
		quick.add_child(_button("居中", _center_shape))
		quick.add_child(_button("圆形化", _round_shape))
		quick.add_child(_button("切一刀", func() -> void: _preset("gap")))

		_canvas = Control.new()
		_canvas.custom_minimum_size = Vector2(520, 360)
		_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
		_canvas.draw.connect(_draw_pad)
		_canvas.gui_input.connect(_pad_input)
		col.add_child(_canvas)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		col.add_child(row)
		row.add_child(_button("圆", func() -> void: _preset("circle")))
		row.add_child(_button("椭圆", func() -> void: _preset("ellipse")))
		row.add_child(_button("竖椭圆", func() -> void: _preset("tall")))
		row.add_child(_button("加点", _add_vertex))
		row.add_child(_button("删点", _delete_vertex))
		var hint := Label.new()
		hint.text = "拖顶点改形状，双击线上加点，G 切换缺口片段，背景 3D 环实时更新"
		UITheme.style_mono(hint, 11, UITheme.MUTED)
		col.add_child(hint)

		var resize := Control.new()
		resize.custom_minimum_size = Vector2(14, 14)
		resize.mouse_filter = Control.MOUSE_FILTER_STOP
		resize.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
		resize.gui_input.connect(_resize_input)
		_box.add_child(resize)
		resize.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		resize.offset_left = -16
		resize.offset_top = -16
		resize.offset_right = -2
		resize.offset_bottom = -2

	func open(p_shape_id: String) -> void:
		shape_id = p_shape_id
		shape = workspace.chart().get_shape(p_shape_id)
		visible = true
		_apply_saved_rect()
		_canvas.queue_redraw()

	func close_pad() -> void:
		_save_rect()
		visible = false
		workspace._refresh()

	func _apply_saved_rect() -> void:
		var rect: Array = workspace._app.ring_pad_rect
		var view := get_viewport_rect().size
		if rect.size() == 4:
			_box.position = Vector2(float(rect[0]), float(rect[1]))
			_box.size = Vector2(maxf(520.0, float(rect[2])), maxf(360.0, float(rect[3])))
		else:
			_box.size = Vector2(640, 600)
			_box.position = (view - _box.size) * 0.5
		_box.size.x = minf(_box.size.x, maxf(420.0, view.x - 20.0))
		_box.size.y = minf(_box.size.y, maxf(300.0, view.y - 20.0))
		_box.position.x = clampf(_box.position.x, 0.0, maxf(0.0, view.x - _box.size.x))
		_box.position.y = clampf(_box.position.y, 0.0, maxf(0.0, view.y - _box.size.y))

	func _save_rect() -> void:
		workspace._app.ring_pad_rect = [_box.position.x, _box.position.y, _box.size.x, _box.size.y]
		workspace._app.save_settings()

	func _window_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			_dragging_window = event.pressed
			_grab_offset = event.position
			if not event.pressed:
				_save_rect()
			_box.accept_event()
		elif event is InputEventMouseMotion and _dragging_window:
			_box.position += event.relative
			_box.accept_event()

	func _resize_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			_resizing = event.pressed
			_resize_start = event.position
			_resize_size = _box.size
			if not event.pressed:
				_save_rect()
			_box.accept_event()
		elif event is InputEventMouseMotion and _resizing:
			var delta: Vector2 = event.position - _resize_start
			_box.size = Vector2(maxf(520.0, _resize_size.x + delta.x), maxf(360.0, _resize_size.y + delta.y))
			_box.accept_event()

	func _scale() -> float:
		return minf(_canvas.size.x, _canvas.size.y) * 0.40 / 420.0

	func _center() -> Vector2:
		return _canvas.size * 0.5

	func _draw_pad() -> void:
		_canvas.draw_rect(Rect2(Vector2.ZERO, _canvas.size), Color("#0B0D12"))
		if shape == null:
			return
		var center := _center()
		var scale := _scale()
		var points := PackedVector2Array()
		for i in 145:
			var data := shape.point_at(float(i) / 144.0)
			if bool(data.get("gap", false)):
				continue
			points.append(center + (data.point as Vector2) * scale)
		if points.size() > 1:
			_canvas.draw_polyline(points, UITheme.CYAN, 2.0, true)
		# 洋葱皮：相邻关键帧的轮廓。
		var keys := workspace.chart().sorted_shape_keys()
		var current_index := -1
		for i in keys.size():
			if String(keys[i].get("shape_id", "")) == shape_id and absf(float(keys[i].get("beat", 0.0)) - workspace.playhead()) < 0.01:
				current_index = i
				break
		if current_index >= 0 and workspace.onion_skin:
			for offset in [-1, 1]:
				var other_index: int = current_index + int(offset)
				if other_index < 0 or other_index >= keys.size():
					continue
				var other := workspace.chart().get_shape(String(keys[other_index].get("shape_id", "")))
				if other == null:
					continue
				var ghost := PackedVector2Array()
				for i in 145:
					var data := other.point_at(float(i) / 144.0)
					if bool(data.get("gap", false)):
						continue
					ghost.append(center + (data.point as Vector2) * scale)
				if ghost.size() > 1:
					_canvas.draw_polyline(ghost, Color(1, 1, 1, 0.20), 1.0, true)
		var index := int(workspace._app.selected_segment_index)
		var vertices := shape.vertices()
		for i in vertices.size():
			var p := center + vertices[i] * scale
			var color := UITheme.CORAL if i == index else UITheme.CYAN
			_canvas.draw_rect(Rect2(p - Vector2(5, 5), Vector2(10, 10)), color)
			_canvas.draw_rect(Rect2(p - Vector2(5, 5), Vector2(10, 10)), UITheme.BG, false, 1.0)

	func _pad_input(event: InputEvent) -> void:
		if shape == null:
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if event.double_click:
					var index: int = _nearest_segment(event.position)
					if index >= 0:
						workspace._app.mutate(func() -> void: shape.insert_vertex(index))
						_canvas.queue_redraw()
					return
				_drag_vertex = _pick(event.position)
				if _drag_vertex >= 0:
					workspace._app.select_segment(_drag_vertex)
					workspace._app.begin_edit()
					_canvas.queue_redraw()
			else:
				if _drag_vertex >= 0:
					_drag_vertex = -1
					workspace._app.finish_edit()
			_canvas.accept_event()
		elif event is InputEventMouseMotion and _drag_vertex >= 0:
			var local: Vector2 = (event.position - _center()) / maxf(0.0001, _scale())
			shape.set_vertex(_drag_vertex, local)
			workspace._app.touch_chart()
			_canvas.queue_redraw()
			_canvas.accept_event()

	func _pick(pos: Vector2) -> int:
		var center := _center()
		var scale := _scale()
		var best := -1
		var best_distance := 16.0
		var vertices := shape.vertices()
		for i in vertices.size():
			var distance := (center + vertices[i] * scale).distance_to(pos)
			if distance < best_distance:
				best_distance = distance
				best = i
		return best

	func _nearest_segment(pos: Vector2) -> int:
		var center := _center()
		var scale := _scale()
		var best := -1
		var best_distance := 12.0
		for i in 72:
			var u := float(i) / 72.0
			var data := shape.point_at(u)
			if bool(data.get("gap", false)):
				continue
			var distance := (center + (data.point as Vector2) * scale).distance_to(pos)
			if distance < best_distance:
				best_distance = distance
				var segment := shape.segment_at(u)
				if segment != null:
					best = shape.sorted_segments().find(segment)
		return best

	func _scale_shape(factor: float) -> void:
		var vertices := shape.vertices()
		if vertices.is_empty():
			return
		var centroid := Vector2.ZERO
		for point in vertices:
			centroid += point
		centroid /= float(vertices.size())
		workspace._app.mutate(func() -> void:
			for i in vertices.size():
				shape.set_vertex(i, centroid + (vertices[i] - centroid) * factor)
		)
		_canvas.queue_redraw()

	func _center_shape() -> void:
		var vertices := shape.vertices()
		if vertices.is_empty():
			return
		var centroid := Vector2.ZERO
		for point in vertices:
			centroid += point
		centroid /= float(vertices.size())
		workspace._app.mutate(func() -> void:
			for i in vertices.size():
				shape.set_vertex(i, vertices[i] - centroid)
		)
		_canvas.queue_redraw()

	func _round_shape() -> void:
		var vertices := shape.vertices()
		if vertices.is_empty():
			return
		var total := 0.0
		for point in vertices:
			total += point.length()
		var radius := total / float(vertices.size())
		workspace._app.mutate(func() -> void:
			for i in vertices.size():
				var direction := vertices[i].normalized()
				if direction.length_squared() < 0.0001:
					direction = Vector2.RIGHT
				shape.set_vertex(i, direction * radius)
		)
		_canvas.queue_redraw()

	func _preset(kind: String) -> void:
		var replacement: BoundaryShape
		match kind:
			"circle":
				replacement = BoundaryShape.circle(shape_id, 330.0, 48)
			"ellipse":
				replacement = BoundaryShape.ellipse(shape_id, 410.0, 245.0, 48)
			"tall":
				replacement = BoundaryShape.ellipse(shape_id, 300.0, 400.0, 48)
			"gap":
				replacement = BoundaryShape.circle(shape_id, 330.0, 48)
				replacement.segments[0].gap = true
			_:
				return
		workspace._app.mutate(func() -> void:
			shape.segments = replacement.segments
			shape.closed = replacement.closed
		)
		_canvas.queue_redraw()

	func _add_vertex() -> void:
		var index: int = maxi(0, int(workspace._app.selected_segment_index))
		workspace._app.mutate(func() -> void:
			shape.insert_vertex(index)
			workspace._app.select_segment(mini(index + 1, shape.vertex_count() - 1))
		)
		_canvas.queue_redraw()

	func _delete_vertex() -> void:
		var index: int = maxi(0, int(workspace._app.selected_segment_index))
		workspace._app.mutate(func() -> void:
			shape.remove_vertex(index)
			workspace._app.select_segment(clampi(index, 0, shape.vertex_count() - 1))
		)
		_canvas.queue_redraw()

	func _button(text: String, callback: Callable) -> Button:
		var button := Button.new()
		button.text = text
		button.add_theme_font_size_override("font_size", 12)
		button.pressed.connect(callback)
		return button


func _ready() -> void:
	_app = get_node_or_null("/root/App")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_build()
	_pad = ShapePadOverlay.new(self)
	add_child(_pad)
	if _app != null:
		_app.chart_live_changed.connect(func() -> void:
			_timeline.queue_redraw()
			if _pad.visible:
				_pad._canvas.queue_redraw()
		)
		_app.chart_changed.connect(func() -> void:
			if visible:
				_timeline.queue_redraw()
				_rebuild_thumbs()
				_sync_time_tool()
		)
		_app.playhead_changed.connect(func(_beat: float) -> void:
			_follow_playhead()
			_sync_time_tool()
			_timeline.queue_redraw()
		)


func _build() -> void:
	var bg := PanelContainer.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#0A0C11")
	style.set_corner_radius_all(0)
	bg.add_theme_stylebox_override("panel", style)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	root.offset_left = 10
	root.offset_right = -10
	root.offset_top = 8
	root.offset_bottom = -8
	bg.add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	root.add_child(header)
	var title := Label.new()
	title.text = "环编辑"
	UITheme.style_section(title)
	header.add_child(title)
	_title = Label.new()
	UITheme.style_mono(_title, 12, UITheme.MUTED)
	_title.add_theme_font_override("font", UITheme.FONT_REGULAR)
	header.add_child(_title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var close := Button.new()
	close.text = "返回 (Esc)"
	close.pressed.connect(close_workspace)
	header.add_child(close)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	root.add_child(body)

	var library := VBoxContainer.new()
	library.custom_minimum_size = Vector2(78, 0)
	library.add_theme_constant_override("separation", 6)
	body.add_child(library)
	_thumbs = GridContainer.new()
	_thumbs.columns = 1
	library.add_child(_thumbs)
	library.add_child(_button("＋ 新形状", _new_shape))
	library.add_child(_button("复制", _duplicate_shape))
	library.add_child(_button("删除", _delete_shape))

	_preview_slot = Control.new()
	_preview_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview_slot.clip_contents = true
	body.add_child(_preview_slot)

	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(270, 0)
	side.add_theme_constant_override("separation", 6)
	body.add_child(side)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(scroll)
	_panel = VBoxContainer.new()
	_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel.add_theme_constant_override("separation", 6)
	scroll.add_child(_panel)

	var time_row := HBoxContainer.new()
	time_row.add_theme_constant_override("separation", 6)
	root.add_child(time_row)
	var beat_label := Label.new()
	beat_label.text = "拍"
	UITheme.style_mono(beat_label, 11, UITheme.MUTED)
	time_row.add_child(beat_label)
	_beat_spin = SpinBox.new()
	_beat_spin.min_value = 0.0
	_beat_spin.max_value = 100000.0
	_beat_spin.step = 0.25
	_beat_spin.custom_minimum_size = Vector2(110, 0)
	_beat_spin.value_changed.connect(func(value: float) -> void:
		if _app != null and absf(value - playhead()) > 0.0001:
			_app.seek(value)
	)
	time_row.add_child(_beat_spin)
	time_row.add_child(_button("◀ 上一帧", _prev_key))
	time_row.add_child(_button("下一帧 ▶", _next_key))
	_play_button = _button("播放 / 暂停", func() -> void: play_toggled.emit())
	time_row.add_child(_play_button)
	_loop_button = _button("循环本段", _toggle_loop)
	time_row.add_child(_loop_button)
	var zoom_option := OptionButton.new()
	for value in ["8 拍", "16 拍", "32 拍", "64 拍", "全部"]:
		zoom_option.add_item(value)
	zoom_option.selected = _zoom_index
	zoom_option.add_theme_font_size_override("font_size", 11)
	zoom_option.item_selected.connect(func(index: int) -> void:
		_zoom_index = clampi(index, 0, ZOOM_LEVELS.size())
		_follow_playhead(true)
		_timeline.queue_redraw()
	)
	time_row.add_child(zoom_option)
	var onion := CheckBox.new()
	onion.text = "洋葱皮"
	onion.add_theme_font_size_override("font_size", 11)
	onion.toggled.connect(func(value: bool) -> void:
		onion_skin = value
		_update_onion()
	)
	time_row.add_child(onion)
	var fps_label := Label.new()
	fps_label.text = "帧率"
	UITheme.style_mono(fps_label, 11, UITheme.MUTED)
	time_row.add_child(fps_label)
	var fps_keys: Array[String] = ["vsync", "60", "120", "144", "240", "unlimited"]
	var fps_labels: Array[String] = ["跟随屏幕", "60", "120", "144", "240", "不限"]
	var fps_option := OptionButton.new()
	for item in fps_labels:
		fps_option.add_item(item)
	fps_option.selected = maxi(0, fps_keys.find(String(_app.frame_cap)))
	fps_option.add_theme_font_size_override("font_size", 11)
	fps_option.item_selected.connect(func(index: int) -> void:
		_app.frame_cap = fps_keys[index]
		_app.apply_frame_cap()
		_app.save_settings()
	)
	time_row.add_child(fps_option)
	_time_label = Label.new()
	UITheme.style_mono(_time_label, 12, UITheme.CYAN)
	_time_label.add_theme_font_override("font", UITheme.FONT_REGULAR)
	time_row.add_child(_time_label)
	_fps_label = Label.new()
	UITheme.style_mono(_fps_label, 12, UITheme.MUTED)
	time_row.add_child(_fps_label)
	var hint := Label.new()
	hint.text = "拖青色菱形改时间，双击画形状"
	UITheme.style_mono(hint, 11, UITheme.MUTED)
	time_row.add_child(hint)

	_timeline = Timeline.new(self)
	root.add_child(_timeline)
	var explain := Label.new()
	explain.text = "块=这一帧保持到下一帧，块越长隔得越久；半透明段=形变已完成、在原地保持（检查器「形变时长」）；拖方块改时间，拖块右缘改下一帧；滚轮滚动，Ctrl+滚轮缩放。"
	explain.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.style_mono(explain, 11, UITheme.MUTED)
	root.add_child(explain)


## 复用主预览：把同一个 Preview3D 挪进来，省掉第二个 3D 视口。
func open_workspace(preview: Preview3D = null, restore: Callable = Callable()) -> void:
	visible = true
	# 每次打开都要把预览搬进来并重新记下恢复回调：关闭时预览会回到主界面，
	# 只搬第一次的话，第二次打开预览槽是空的，关闭时也没人把主界面显示回来。
	if preview != null:
		if preview.get_parent() != _preview_slot:
			if preview.get_parent() != null:
				preview.get_parent().remove_child(preview)
			_preview_slot.add_child(preview)
			preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_preview = preview
		_restore_preview = restore
	if _preview != null:
		_preview.ring_edit_mode = true
		_preview.show_hud = false
		_preview.use_3d_ring = _app.use_3d_ring
		_preview.flow_scale = _app.flow_scale
		_preview.note_skin = _app.note_skin
		_preview.cursor_scale = _app.cursor_scale
		if not _preview.notice.is_connected(_set_hint):
			_preview.notice.connect(_set_hint)
		if not _preview.ring_zoom.is_connected(_on_ring_zoom):
			_preview.ring_zoom.connect(_on_ring_zoom)
		if not _preview.ring_rotate.is_connected(_on_ring_rotate):
			_preview.ring_rotate.connect(_on_ring_rotate)
		_preview.set_process(true)
		_preview.queue_redraw()
	grab_focus()
	_follow_playhead(true)
	_refresh()


func close_workspace() -> void:
	if _pad != null and _pad.visible:
		_pad.close_pad()
		return
	visible = false
	if _preview != null and _preview.get_parent() == _preview_slot:
		_preview_slot.remove_child(_preview)
	if _restore_preview.is_valid():
		_restore_preview.call(_preview)
		_restore_preview = Callable()
	closed.emit()


func chart() -> Chart:
	return _app.chart if _app != null else null


func playhead() -> float:
	return float(_app.playhead_beat) if _app != null else 0.0


func view_beats() -> float:
	if _zoom_index >= ZOOM_LEVELS.size():
		# 「全部」：按内容长度铺满，再留 1 小节给最后一段的端帽。
		if chart() == null:
			return 16.0
		return maxf(8.0, chart().content_end_beat() + chart().bar_length())
	return float(ZOOM_LEVELS[clampi(_zoom_index, 0, ZOOM_LEVELS.size() - 1)])


func window_start() -> float:
	return _view_start


## 「适配全部」：缩放到能看到整张谱。
func fit_all_timeline() -> void:
	_zoom_index = ZOOM_LEVELS.size()
	_view_start = 0.0
	_timeline.queue_redraw()


func zoom_timeline(step: int) -> void:
	_zoom_index = clampi(_zoom_index + step, 0, ZOOM_LEVELS.size())
	_follow_playhead(true)
	_timeline.queue_redraw()


func scroll_timeline(direction: float) -> void:
	var ahead := view_beats() * 0.15 * direction
	var end := chart().content_end_beat() + chart().bar_length() if chart() != null else 0.0
	_view_start = clampf(_view_start + ahead, 0.0, maxf(0.0, end - view_beats()))
	_timeline.queue_redraw()


func _follow_playhead(force: bool = false) -> void:
	if not force and not follow_playhead_view:
		return
	var span := view_beats()
	if chart() != null and span >= chart().content_end_beat() + chart().bar_length():
		# 「全部」能看到整张谱：播放头走动时不要把它重新滚走。
		_view_start = 0.0
		return
	var beat := playhead()
	if force or beat < _view_start or beat > _view_start + span * 0.9:
		_view_start = maxf(0.0, beat - span * 0.3)


func seek(beat: float) -> void:
	if _app != null:
		_app.seek(beat)


func dragging() -> bool:
	return not _drag_kind.is_empty() or scrubbing()


## 正在拖时间轴的播放头。拖过关键帧时不要重建面板：一次重建 ≈70–80 个控件，
## 拖动时每跨一帧都要付两遍（进/出各一次），这就是「经过关键帧极卡」的来源。
func scrubbing() -> bool:
	return _timeline != null and _timeline._drag_kind == "playhead"


## 拖动播放头结束：面板与洋葱皮补一次，拖动过程中全部跳过。
func finish_scrub() -> void:
	var key := current_key()
	_last_key_beat = float(key.get("beat", -999.0)) if not key.is_empty() else -999.0
	_rebuild_panel()
	_update_onion()
	_sync_time_tool(true)
	_timeline.queue_redraw()


func current_key() -> Dictionary:
	var chart_data := chart()
	if chart_data == null:
		return {}
	return chart_data.shape_key_at(playhead())


func _refresh() -> void:
	if _app == null or _app.chart == null:
		return
	_rebuild_thumbs()
	_rebuild_panel()
	_sync_time_tool()
	_timeline.queue_redraw()


func snap(beat: float) -> float:
	return float(_app.snap_beat(beat, false)) if _app != null else beat


func snap_division() -> int:
	return int(_app.snap_division) if _app != null else GridDivisions.DEFAULT_DIVISION


func _process(delta: float) -> void:
	if not visible or _fps_label == null:
		return
	_fps_accum += delta
	if _fps_accum >= 0.25:
		_fps_accum = 0.0
		_fps_label.text = "%d FPS" % Engine.get_frames_per_second()


func _sync_time_tool(force: bool = false) -> void:
	# 每帧写 Label / SpinBox 会让整页 UI 重新排版（实测 78ms/帧）；
	# 只在显示值变化时写，并且限到 ~12Hz。播放头位置本身仍然是逐帧的。
	var now := Time.get_ticks_msec()
	if not force and now - _sync_last_msec < 80:
		return
	_sync_last_msec = now
	var beat := playhead()
	if not is_equal_approx(beat, _sync_last_beat):
		_sync_last_beat = beat
		# SpinBox / Label 的文本一变就会触发整页重新排版（实测 ~40ms），
		# 所以只在显示值真的变了才写：拍数按 1/4 拍、时间按 0.1 拍。
		if _beat_spin != null:
			var spin_value := snappedf(beat, 0.25)
			if not is_equal_approx(spin_value, _sync_last_spin):
				_sync_last_spin = spin_value
				_beat_spin.set_value_no_signal(spin_value)
		if _time_label != null and chart() != null:
			var bpb := maxf(1.0, chart().timing.beats_per_bar_at(beat))
			var text := "第 %d 小节，拍 %.1f / %d" % [int(floorf(beat / bpb)) + 1, fmod(beat, bpb), int(bpb)]
			if _time_label.text != text:
				_time_label.text = text
	var key := current_key()
	if _title != null:
		var text := "拍 %.1f，%s" % [beat, ("关键帧 " + String(key.get("shape_id", ""))) if not key.is_empty() else "无关键帧"]
		if _title.text != text:
			_title.text = text
	# 播放/拖时间跨过关键帧时，右侧按钮跟着换。
	var key_beat := float(key.get("beat", -999.0)) if not key.is_empty() else -999.0
	if not is_equal_approx(key_beat, _last_key_beat) and not dragging():
		_last_key_beat = key_beat
		_rebuild_panel()
		_update_onion()


func _current_shape() -> BoundaryShape:
	var key := current_key()
	if not key.is_empty():
		return chart().get_shape(String(key.get("shape_id", "")))
	return null


func _rebuild_thumbs() -> void:
	var chart_data := chart()
	if chart_data == null:
		return
	var active := String(_app.selected_shape_id)
	var signature := active
	for shape in chart_data.sorted_shapes():
		signature += "|" + shape.id
	if signature == _thumb_signature:
		return
	_thumb_signature = signature
	for child in _thumbs.get_children():
		child.queue_free()
	for shape in chart_data.sorted_shapes():
		var thumb := ShapeThumb.new(self, shape.id)
		thumb.selected = shape.id == active
		_thumbs.add_child(thumb)


func _fold(title: String) -> VBoxContainer:
	var key := title
	var open: bool = bool(_fold_open.get(key, true))
	var header := Button.new()
	header.text = ("▾ " if open else "▸ ") + title
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.add_theme_font_size_override("font_size", 12)
	header.pressed.connect(func() -> void:
		_fold_open[key] = not open
		_rebuild_panel()
	)
	_panel.add_child(header)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.visible = open
	_panel.add_child(box)
	return box


func _rebuild_panel() -> void:
	for child in _panel.get_children():
		child.queue_free()
	var chart_data := chart()
	if chart_data == null:
		return
	var key := current_key()
	var shape_box := _fold("形变")
	if key.is_empty():
		shape_box.add_child(_button("＋ 在播放头加关键帧", _add_key))
	else:
		shape_box.add_child(_button("编辑形状（2D）", open_pad_for_current))
		shape_box.add_child(_button("删除这一帧", _delete_key))
		shape_box.add_child(_button("切断/恢复这一段 (G)", _toggle_gap))
		var easing := String(key.get("easing", "in-out"))
		# 白话标签：谱师不需要知道 cubic-bezier 是什么。原来的「柔和」没有对应值，
		# 选中会越界，已隐藏（EASINGS 里只有匀速 / 缓入缓出）。
		shape_box.add_child(_option("到下一帧怎么变", ["匀速", "缓入缓出"], maxi(0, EASINGS.find(easing)), func(index: int) -> void:
			_app.mutate(func() -> void: key["easing"] = EASINGS[index])
		))
		# 形变时长：默认等于整段（旧行为）；改短 = 快速变完，剩下的时间保持这个形状。
		var span := _key_span(key)
		var morph := BoundaryRuntime.morph_beats(key, span)
		var morph_max := maxf(0.05, span)
		shape_box.add_child(_number("形变时长（拍）", morph, 0.05, morph_max, 0.05,
			func(value: float) -> void: _app.mutate(func() -> void: key["morph"] = clampf(value, 0.05, morph_max))))
		shape_box.add_child(_label("变完到下一帧之前保持这个形状。整段 %s 拍，调小就是变快点。" % RingWorkspace._beat_num(span)))
		var shape := _current_shape()
		if shape != null:
			var index: int = clampi(int(_app.selected_segment_index), 0, maxi(0, shape.vertex_count() - 1))
			shape_box.add_child(_label("选中顶点 %d / %d" % [index, shape.vertex_count()]))

	var cam_box := _fold("镜头")
	var view := _active_view()
	cam_box.add_child(_slider("缩放", float(view.get("zoom", 1.0)), 0.75, 1.4, 0.01, func(value: float) -> void:
		_apply_view("zoom", value)
	))
	cam_box.add_child(_slider("旋转", float(view.get("rotation", 0.0)), -180.0, 180.0, 1.0, func(value: float) -> void:
		_apply_view("rotation", value)
	))
	cam_box.add_child(_button("在这里打镜头关键帧", _add_view_keyframe))
	if _app.selected_view_index >= 0:
		cam_box.add_child(_button("删除选中镜头帧", _delete_view_keyframe))
		var selected_view: ViewState = _app.get_selected_view()
		if selected_view != null:
			# 每段可以单独选缓动；旋转本身在 ViewState.evaluate 里走最短弧。
			var rotate_easing := maxi(0, EASINGS.find(selected_view.easing))
			cam_box.add_child(_option("这一段怎么转", ["匀速", "缓入缓出"], rotate_easing,
				func(index: int) -> void: _app.mutate(func() -> void: selected_view.easing = EASINGS[index])))
			cam_box.add_child(_label("旋转走最短弧：350°→10° 是 +20°，不会反向绕 340°。"))

	var advanced := _fold("高级数值")
	if advanced.visible:
		_build_advanced(advanced)


func _build_advanced(parent: VBoxContainer) -> void:
	var key := current_key()
	var shape := _current_shape()
	if not key.is_empty() and shape != null:
		var index: int = clampi(int(_app.selected_segment_index), 0, maxi(0, shape.vertex_count() - 1))
		var points := shape.vertices()
		if index < points.size():
			parent.add_child(_number("顶点 x", points[index].x, -2000, 2000, 1.0, func(value: float) -> void:
				shape.set_vertex(index, Vector2(value, shape.vertices()[index].y))
			))
			parent.add_child(_number("顶点 y", points[index].y, -2000, 2000, 1.0, func(value: float) -> void:
				shape.set_vertex(index, Vector2(shape.vertices()[index].x, value))
			))
		parent.add_child(_number("顶点数", float(shape.vertex_count()), 3, 48, 1.0, func(value: float) -> void:
			shape.set_vertex_count(int(value))
			_refresh()
		))
		parent.add_child(_number("关键帧拍", float(key.get("beat", 0.0)), 0, 100000, 0.25, func(value: float) -> void:
			key["beat"] = value
		))
	var view := _active_view()
	parent.add_child(_number("tiltX", float(view.get("tilt_x", 0.0)), -60, 60, 1.0, func(value: float) -> void:
		_apply_view("tilt_x", value)
	))
	parent.add_child(_number("tiltY", float(view.get("tilt_y", 0.0)), -60, 60, 1.0, func(value: float) -> void:
		_apply_view("tilt_y", value)
	))
	parent.add_child(_number("ellipse", float(view.get("ellipse", 1.0)), 0.5, 1.5, 0.01, func(value: float) -> void:
		_apply_view("ellipse", value)
	))


## 当前形状关键帧到下一帧的拍数（最后一帧算到谱面内容结束）。
func _key_span(key: Dictionary) -> float:
	var chart_data := chart()
	if chart_data == null:
		return 0.0
	var keys := chart_data.sorted_shape_keys()
	var beats: Array[float] = []
	var index := -1
	var key_beat := float(key.get("beat", 0.0))
	for i in keys.size():
		beats.append(float(keys[i].get("beat", 0.0)))
		if absf(beats[i] - key_beat) < 0.0005:
			index = i
	if index < 0:
		return 0.0
	var bpb := maxf(1.0, chart_data.timing.beats_per_bar_at(key_beat))
	return maxf(0.25, RingWorkspace.span_end(beats, index, chart_data.content_end_beat(), bpb) - key_beat)


func _update_onion() -> void:
	if _preview != null:
		_preview.onion_shapes.clear()
		if onion_skin and chart() != null:
			var keys := chart().sorted_shape_keys()
			var index := -1
			for i in keys.size():
				if absf(float(keys[i].get("beat", 0.0)) - playhead()) < 0.01:
					index = i
					break
			if index >= 0:
				for offset in [-1, 1]:
					var j: int = index + int(offset)
					if j >= 0 and j < keys.size():
						var other := chart().get_shape(String(keys[j].get("shape_id", "")))
						if other != null:
							_preview.onion_shapes.append(other)
		_preview.queue_redraw()
	if _pad != null and _pad.visible:
		_pad._canvas.queue_redraw()


func _active_view() -> Dictionary:
	var chart_data := chart()
	if chart_data == null:
		return ViewState.default_state()
	var selected: ViewState = _app.get_selected_view()
	if selected != null:
		return {
			"zoom": selected.zoom, "rotation": selected.rotation,
			"tilt_x": selected.tilt_x, "tilt_y": selected.tilt_y, "ellipse": selected.ellipse,
		}
	return BoundaryRuntime.eval_view(chart_data, playhead())


func _apply_view(key: String, value: float) -> void:
	var state: ViewState = _app.get_selected_view()
	if state == null:
		_add_view_keyframe()
		state = _app.get_selected_view()
		if state == null:
			return
	match key:
		"zoom":
			state.zoom = value
		"rotation":
			state.rotation = value
		"tilt_x":
			state.tilt_x = value
		"tilt_y":
			state.tilt_y = value
		"ellipse":
			state.ellipse = value


func _on_ring_zoom(delta: float) -> void:
	var view := _active_view()
	var target := clampf(float(view.get("zoom", 1.0)) + delta, 0.75, 1.4)
	_app.mutate(func() -> void: _apply_view("zoom", target))


func _on_ring_rotate(degrees: float) -> void:
	var state: ViewState = _app.get_selected_view()
	if state == null:
		_add_view_keyframe()
		state = _app.get_selected_view()
		if state == null:
			return
	state.rotation = clampf(state.rotation + degrees, -180.0, 180.0)
	_app.touch_chart()
	_preview.queue_redraw()


func _add_view_keyframe() -> void:
	var chart_data := chart()
	if chart_data == null:
		return
	var current := _active_view()
	var state := ViewState.new(playhead(), float(current.get("zoom", 1.0)), float(current.get("tilt_x", 0.0)),
		float(current.get("tilt_y", 0.0)), float(current.get("ellipse", 1.0)), float(current.get("rotation", 0.0)))
	_app.mutate(func() -> void:
		chart_data.view_states.append(state)
		chart_data.view_states.sort_custom(func(a: ViewState, b: ViewState) -> bool: return a.beat < b.beat)
		_app.select_view(chart_data.view_states.find(state))
	)
	_refresh()


func _delete_view_keyframe() -> void:
	var chart_data := chart()
	if chart_data == null or _app.selected_view_index < 0:
		return
	var state: ViewState = _app.get_selected_view()
	if state == null:
		return
	_app.mutate(func() -> void:
		chart_data.view_states.erase(state)
		_app.select_view(-1)
	)
	_refresh()


# ---- 形状关键帧 -------------------------------------------------------------

func _next_shape_id() -> String:
	var chart_data := chart()
	if chart_data == null:
		return "S0"
	var index := 1
	while chart_data.shapes.has("S%d" % index):
		index += 1
	return "S%d" % index


## 把当前拍实际显示的轮廓定型成一个新形状。
func _snapshot_shape(beat: float) -> BoundaryShape:
	var shape := BoundaryShape.new()
	shape.id = _next_shape_id()
	shape.closed = true
	var count := BoundaryShape.MAX_VERTICES
	var points := BoundaryRuntime.eval_shape(chart(), beat, count)
	for i in count:
		var a: Dictionary = points[i]
		var b: Dictionary = points[(i + 1) % count]
		shape.segments.append(BoundarySegment.new(
			float(i) / float(count), float(i + 1) / float(count),
			a.point, b.point, "l", "l", bool(a.get("gap", false))
		))
	return shape


func _add_key() -> void:
	var chart_data := chart()
	if chart_data == null:
		return
	if not current_key().is_empty():
		_set_hint("播放头已经在关键帧上了。")
		return
	var beat := playhead()
	var shape := _snapshot_shape(beat)
	_app.mutate(func() -> void:
		chart_data.shapes[shape.id] = shape
		chart_data.shape_keys.append({"beat": beat, "shape_id": shape.id, "easing": "in-out"})
		_app.select_shape(shape.id)
		_app.select_segment(0)
	)
	_refresh()
	_set_hint("已加关键帧 %s；点「编辑形状（2D）」开始画。" % shape.id)


func _delete_key() -> void:
	var chart_data := chart()
	var key := current_key()
	if chart_data == null or key.is_empty():
		return
	var shape_id := String(key.get("shape_id", ""))
	var still_used := false
	for other in chart_data.shape_keys:
		if other != key and String(other.get("shape_id", "")) == shape_id:
			still_used = true
			break
	_app.mutate(func() -> void:
		chart_data.shape_keys.erase(key)
		if not still_used and shape_id != chart_data.default_shape_id and shape_id != "":
			chart_data.shapes.erase(shape_id)
	)
	_refresh()


func _toggle_gap() -> void:
	var shape := _current_shape()
	if shape == null:
		_set_hint("先选中一个形状关键帧。")
		return
	var index: int = clampi(int(_app.selected_segment_index), 0, shape.vertex_count() - 1)
	_app.mutate(func() -> void: shape.set_gap(index, not shape.segment_has_gap(index)))
	_refresh()


func _new_shape() -> void:
	var chart_data := chart()
	if chart_data == null:
		return
	var id := _next_shape_id()
	_app.mutate(func() -> void:
		chart_data.shapes[id] = BoundaryShape.circle(id, 330.0, BoundaryShape.DEFAULT_VERTICES)
	)
	_app.select_shape(id)
	_refresh()


func _duplicate_shape() -> void:
	var shape := _current_shape()
	var chart_data := chart()
	if shape == null or chart_data == null:
		return
	var copy := BoundaryShape.from_dict(shape.to_dict())
	copy.id = _next_shape_id()
	_app.mutate(func() -> void:
		chart_data.shapes[copy.id] = copy
	)
	_app.select_shape(copy.id)
	_refresh()


func _delete_shape() -> void:
	var shape := _current_shape()
	var chart_data := chart()
	if shape == null or chart_data == null or chart_data.shapes.size() <= 1:
		return
	if shape.id == chart_data.default_shape_id:
		_set_hint("默认形状不能删。")
		return
	_app.mutate(func() -> void:
		chart_data.shapes.erase(shape.id)
	)
	_refresh()


func _toggle_loop() -> void:
	_loop_on = not _loop_on
	var start := 0.0
	var end := 0.0
	var beats: Array[float] = []
	for key in chart().sorted_shape_keys():
		beats.append(float(key.get("beat", 0.0)))
	var beat := playhead()
	for b in beats:
		if b < beat - 0.0005:
			start = b
		elif b > beat + 0.0005:
			end = b
			break
	if end <= start:
		start = maxf(0.0, beat - 2.0)
		end = beat + 2.0
	loop_requested.emit(start, end, _loop_on)
	_loop_button.text = "循环中 %.1f–%.1f 拍" % [start, end] if _loop_on else "循环本段"


func _prev_key() -> void:
	var target := -1.0
	for key in chart().sorted_shape_keys():
		var beat := float(key.get("beat", 0.0))
		if beat < playhead() - 0.0005:
			target = beat
	if target >= 0.0:
		seek(target)


func _next_key() -> void:
	for key in chart().sorted_shape_keys():
		var beat := float(key.get("beat", 0.0))
		if beat > playhead() + 0.0005:
			seek(beat)
			return


func open_pad_for_current() -> void:
	var key := current_key()
	if key.is_empty():
		_add_key()
		key = current_key()
		if key.is_empty():
			return
	open_pad_for_shape(String(key.get("shape_id", "")))


func open_pad_for_shape(shape_id: String) -> void:
	if shape_id.is_empty():
		return
	_app.select_shape(shape_id)
	_pad.open(shape_id)


# ---- 时间轴拖拽 -------------------------------------------------------------

func begin_key_drag(key: Dictionary) -> void:
	_drag_kind = "key"
	_drag_key = key
	_app.begin_edit()


func begin_view_drag(state: ViewState) -> void:
	_drag_kind = "view"
	_drag_view = state
	_app.select_view(chart().view_states.find(state))
	_app.begin_edit()


func drag_to(beat: float) -> void:
	var target: float = _app.snap_beat(beat, false)
	match _drag_kind:
		"key":
			_drag_key["beat"] = maxf(0.0, target)
		"view":
			_drag_view.beat = maxf(0.0, target)
	_app.touch_chart()
	_timeline.queue_redraw()


func end_drag() -> void:
	_drag_kind = ""
	_drag_key = {}
	_drag_view = null
	chart().shape_keys.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("beat", 0.0)) < float(b.get("beat", 0.0)))
	_app.finish_edit()
	_refresh()


func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	# 在输入框里打字时不要把 G / Delete 当成快捷键。
	var focus = get_viewport().gui_get_focus_owner()
	if focus is LineEdit:
		return
	if _pad != null and _pad.visible:
		if event.keycode == KEY_ESCAPE:
			_pad.close_pad()
			get_viewport().set_input_as_handled()
		return
	match event.keycode:
		KEY_ESCAPE:
			close_workspace()
			get_viewport().set_input_as_handled()
		KEY_G:
			_toggle_gap()
			get_viewport().set_input_as_handled()
		KEY_DELETE:
			if not current_key().is_empty():
				_delete_key()
				get_viewport().set_input_as_handled()
		KEY_LEFT, KEY_RIGHT:
			var key := current_key()
			if not key.is_empty():
				var step := -0.25 if event.keycode == KEY_LEFT else 0.25
				var beat := maxf(0.0, float(key.get("beat", 0.0)) + step)
				_app.mutate(func() -> void:
					key["beat"] = beat
					chart().shape_keys.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("beat", 0.0)) < float(b.get("beat", 0.0)))
				)
				seek(beat)
				get_viewport().set_input_as_handled()


# ---- 小部件 ---------------------------------------------------------------

func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UITheme.style_mono(label, 11, UITheme.MUTED)
	return label


func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 12)
	button.pressed.connect(callback)
	return button


func _option(text: String, items: Array, selected: int, callback: Callable) -> OptionButton:
	var option := OptionButton.new()
	for item in items:
		option.add_item(String(item))
	option.selected = clampi(selected, 0, items.size() - 1)
	option.add_theme_font_size_override("font_size", 12)
	option.item_selected.connect(func(index: int) -> void:
		if _app != null:
			_app.mutate(func() -> void: callback.call(index))
	)
	return option


func _slider(text: String, value: float, min_value: float, max_value: float, step: float, callback: Callable) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var label := Label.new()
	label.text = "%s  %.2f" % [text, value]
	UITheme.style_mono(label, 11, UITheme.MUTED)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = clampf(value, min_value, max_value)
	slider.custom_minimum_size = Vector2(0, 22)
	# 拖动期间只改值 + 标脏，松手才记一条撤销：不再每格都 snapshot 整份谱面。
	slider.drag_started.connect(func() -> void:
		if _app != null:
			_app.begin_edit()
	)
	slider.value_changed.connect(func(new_value: float) -> void:
		label.text = "%s  %.2f" % [text, new_value]
		if _app != null:
			callback.call(new_value)
			_app.touch_chart()
	)
	slider.drag_ended.connect(func(_changed: bool) -> void:
		if _app != null:
			_app.finish_edit()
	)
	row.add_child(slider)
	return row


func _number(text: String, value: float, min_value: float, max_value: float, step: float, callback: Callable) -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(96, 0)
	UITheme.style_mono(label, 11, UITheme.MUTED)
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.value = value
	spin.allow_greater = true
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(func(new_value: float) -> void:
		if _app != null:
			_app.mutate(func() -> void: callback.call(new_value))
	)
	row.add_child(spin)
	return row


func _set_hint(text: String) -> void:
	if _title != null:
		_title.text = text
