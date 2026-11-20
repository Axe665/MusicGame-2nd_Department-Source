class_name RingTimeline
extends Control

## Flash 式时间轴：左侧图层头 + 拍/秒标尺 + 关键帧色带。
## 静态内容层只在谱面/窗口/选中变化时重绘；拖播放头只重绘覆盖层。

signal selection_changed

const GUTTER := 196.0
const HEADER_H := 24.0
const RULER_H := 44.0
const LANE_TOP := 70.0
const LANE_H := 56.0
const LANE_GAP := 2.0
const AUX_HEAD_H := 20.0
const AUX_ROW_H := 20.0
const AUX_GAP := 6.0
const FOOTER_H := 26.0
const BAR_H := 30.0
const KEY_SIZE := 12.0
const KEY_HIT := 9.0
const EDGE_HIT := 5.0

const LANE_SHAPE := 0
const LANE_CAMERA := 1
const LANE_EVENTS := 2
const LANE_BPM := 3
const LANE_COMMAND_JLINE := 4
const LANE_COMMAND_TEXT := 5
const LANE_COMMAND_FILTER := 6
const COMMAND_LANES := [LANE_COMMAND_JLINE, LANE_COMMAND_TEXT, LANE_COMMAND_FILTER]
const COMMAND_CATEGORIES := ["jline", "text", "filter"]

## 演出指令区比辅助行高一点：要放得下指令块和 attack/release 两条刻度。
const COMMAND_HEAD_H := 18.0
const COMMAND_ROW_H := 30.0
const COMMAND_GAP := 6.0

var workspace
var hidden_lanes: Dictionary = {}
var locked_lanes: Dictionary = {}
var show_grid := true
var aux_open := false

## 选中集合：键 "shape:<id>" / "view:<id>"；段选中单独记左键。
var _selected: Dictionary = {}
var _primary := ""
var _segment := ""
## 演出指令单选：和形状/镜头多选分开，避免把两种编辑对象混在一起。
var _selected_command: AlphaCommand = null

var _content: Control
var _overlay: Control
var _menu: MenuButton
var _content_draws := 0
var _content_invalidations := 0

var _drag_kind := ""
var _drag_start_beat := 0.0
var _drag_bases: Array[Dictionary] = []
var _drag_command: AlphaCommand = null
var _drag_command_origin := 0.0
var _marquee_active := false
var _marquee_start := Vector2.ZERO
var _marquee_current := Vector2.ZERO
var _marquee_add := false
var _hover_lane := -1
var _hover_index := -1
## 段 hover 与关键帧 hover 分开：段命中返回目标帧下标，不能当作色带下标。
var _hover_segment := -1
var _hover_pos := Vector2(-9999, -9999)

var _clipboard: Array[Dictionary] = []
var _lane_cache: Dictionary = {}
var _lane_cache_version := -1

var _thumb_cache: Dictionary = {}
var _thumb_version := -1


class ContentLayer:
	extends Control

	func _draw() -> void:
		var tl := get_parent()
		if tl != null and tl.has_method("_draw_content"):
			tl._draw_content(self)


class OverlayLayer:
	extends Control

	func _draw() -> void:
		var tl := get_parent()
		if tl != null and tl.has_method("_draw_overlay"):
			tl._draw_overlay(self)


func _init(p_workspace) -> void:
	workspace = p_workspace
	custom_minimum_size = Vector2(0, _timeline_height())
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	clip_contents = true
	_content = ContentLayer.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_content)
	_overlay = OverlayLayer.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	_menu = MenuButton.new()
	_menu.text = "⋯"
	_menu.tooltip_text = "时间轴选项"
	_menu.add_theme_font_size_override("font_size", 11)
	var popup := _menu.get_popup()
	popup.add_item("适配全部 (F)", 1)
	popup.add_item("跳到开头 (Home)", 2)
	popup.add_item("跳到结尾 (End)", 3)
	popup.add_check_item("显示拍线", 4)
	popup.set_item_checked(popup.get_item_index(4), true)
	popup.add_check_item("跟随播放头", 5)
	popup.set_item_checked(popup.get_item_index(5), bool(workspace.follow_playhead_view))
	popup.id_pressed.connect(_on_menu)
	add_child(_menu)
	_menu.position = Vector2(size.x - 40.0, 1.0)
	_menu.size = Vector2(36.0, 20.0)
	resized.connect(func() -> void:
		if _menu != null:
			_menu.position = Vector2(size.x - 40.0, 1.0)
		invalidate()
	)


func _on_menu(id: int) -> void:
	match id:
		1:
			workspace.fit_all_timeline()
			invalidate()
		2:
			workspace.seek(0.0)
			workspace._view_start = 0.0
			invalidate()
		3:
			workspace.seek(workspace.content_end_beat())
			invalidate()
		4:
			show_grid = not show_grid
			_menu.get_popup().set_item_checked(_menu.get_popup().get_item_index(4), show_grid)
			invalidate()
		5:
			workspace.follow_playhead_view = not workspace.follow_playhead_view
			_menu.get_popup().set_item_checked(_menu.get_popup().get_item_index(5), workspace.follow_playhead_view)


# ---------------------------------------------------------------- 外部接线


func invalidate() -> void:
	_content_invalidations += 1
	if _content != null:
		_content.queue_redraw()
	if _overlay != null:
		_overlay.queue_redraw()


func invalidate_overlay() -> void:
	if _overlay != null:
		_overlay.queue_redraw()


func on_chart_changed() -> void:
	prune_selection()
	_lane_cache_version = -1
	invalidate()


func on_live_change() -> void:
	# 拖动关键帧会改变谱面：色带必须跟着重绘。拖播放头不走这里。
	invalidate()


func on_playhead_changed() -> void:
	# 播放/擦洗只重绘覆盖层。
	invalidate_overlay()


func selection_count() -> int:
	return _selected.size() + (1 if _selected_command != null else 0)


## 当前选中的演出指令；没有选中返回 null。
func selected_command() -> AlphaCommand:
	return _selected_command


func primary_key() -> Dictionary:
	if _primary.begins_with("shape:"):
		return workspace.chart().shape_key_by_id(int(_primary.substr(6)))
	return {}


func primary_view() -> ViewState:
	if _primary.begins_with("view:"):
		return workspace.chart().view_state_by_id(int(_primary.substr(5)))
	return null


func primary_kind() -> String:
	if _selected_command != null:
		return "command"
	if _primary.begins_with("shape:"):
		return "shape"
	if _primary.begins_with("view:"):
		return "view"
	return ""


func selected_shape_keys() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var chart: Chart = workspace.chart()
	if chart == null:
		return result
	for key in _selected.keys():
		var text := String(key)
		if text.begins_with("shape:"):
			var found: Dictionary = chart.shape_key_by_id(int(text.substr(6)))
			if not found.is_empty():
				result.append(found)
	return result


func selected_views() -> Array[ViewState]:
	var result: Array[ViewState] = []
	var chart: Chart = workspace.chart()
	if chart == null:
		return result
	for key in _selected.keys():
		var text := String(key)
		if text.begins_with("view:"):
			var found: ViewState = chart.view_state_by_id(int(text.substr(5)))
			if found != null:
				result.append(found)
	return result


## 段选中时返回左键（形状返回字典，镜头返回 ViewState；没有则空）。
func segment_shape_key() -> Dictionary:
	if _segment.begins_with("shape:"):
		return workspace.chart().shape_key_by_id(int(_segment.substr(6)))
	return {}


func segment_view() -> ViewState:
	if _segment.begins_with("view:"):
		return workspace.chart().view_state_by_id(int(_segment.substr(5)))
	return null


func clear_selection() -> void:
	if _selected.is_empty() and _segment.is_empty() and _selected_command == null:
		return
	_selected.clear()
	_primary = ""
	_segment = ""
	_selected_command = null
	invalidate()
	selection_changed.emit()


func prune_selection() -> void:
	var chart: Chart = workspace.chart()
	if chart == null:
		clear_selection()
		return
	if _selected_command != null and not chart.commands.has(_selected_command):
		_selected_command = null
		selection_changed.emit()
	if _selected.is_empty() and _segment.is_empty():
		return
	for key in _selected.keys():
		var text := String(key)
		var alive := false
		if text.begins_with("shape:"):
			alive = not chart.shape_key_by_id(int(text.substr(6))).is_empty()
		elif text.begins_with("view:"):
			alive = chart.view_state_by_id(int(text.substr(5))) != null
		if not alive:
			_selected.erase(key)
	if not _primary.is_empty() and not _selected.has(_primary):
		_primary = String(_selected.keys()[0]) if not _selected.is_empty() else ""
	if not _segment.is_empty():
		var seg_alive := false
		if _segment.begins_with("shape:"):
			seg_alive = not chart.shape_key_by_id(int(_segment.substr(6))).is_empty()
		elif _segment.begins_with("view:"):
			seg_alive = chart.view_state_by_id(int(_segment.substr(5))) != null
		if not seg_alive:
			_segment = ""


func _select_only(kind: String, id: int) -> void:
	var token := "%s:%d" % [kind, id]
	if _selected.size() == 1 and _selected.has(token) and _segment.is_empty() and _selected_command == null:
		return
	_selected.clear()
	_selected[token] = true
	_primary = token
	_segment = ""
	_selected_command = null
	_sync_app_selection(kind, id)
	invalidate()
	selection_changed.emit()


func _toggle_select(kind: String, id: int) -> void:
	var token := "%s:%d" % [kind, id]
	_selected_command = null
	if _selected.has(token):
		_selected.erase(token)
		if _primary == token:
			_primary = String(_selected.keys()[0]) if not _selected.is_empty() else ""
	else:
		_selected[token] = true
		_primary = token
		_sync_app_selection(kind, id)
	_segment = ""
	invalidate()
	selection_changed.emit()


func _select_segment(kind: String, id: int) -> void:
	var token := "%s:%d" % [kind, id]
	_selected.clear()
	_selected_command = null
	_selected[token] = true
	_primary = token
	_segment = token
	_sync_app_selection(kind, id)
	invalidate()
	selection_changed.emit()


func _select_command(command: AlphaCommand) -> void:
	if command == null:
		return
	if _selected_command == command and _selected.is_empty() and _segment.is_empty():
		return
	_selected.clear()
	_primary = ""
	_segment = ""
	_selected_command = command
	invalidate()
	selection_changed.emit()


## 检查器/指令列表点一条指令：选中并把播放头放到它的起始拍。
func select_command(command: AlphaCommand) -> void:
	if command == null:
		return
	_select_command(command)
	workspace.seek(command.beat)


## 选中后同步 App 的旧选择字段，预览滚轮和画形板仍能跟随。
func _sync_app_selection(kind: String, id: int) -> void:
	var chart: Chart = workspace.chart()
	if chart == null or workspace._app == null:
		return
	if kind == "view":
		var state := chart.view_state_by_id(id)
		if state != null:
			workspace._app.select_view(chart.view_states.find(state))
	else:
		var key := chart.shape_key_by_id(id)
		if not key.is_empty():
			workspace._app.select_shape(String(key.get("shape_id", "")))


# ---------------------------------------------------------------- 几何


func _x_for(beat: float) -> float:
	return GUTTER + (beat - workspace.window_start()) / maxf(0.001, workspace.view_beats()) * (size.x - GUTTER)


func _beat_at(x: float) -> float:
	return workspace.window_start() + ((x - GUTTER) / maxf(1.0, size.x - GUTTER)) * workspace.view_beats()


func _lane_top(lane: int) -> float:
	if lane == LANE_SHAPE:
		return LANE_TOP
	if lane == LANE_CAMERA:
		return LANE_TOP + LANE_H + LANE_GAP
	if lane >= LANE_COMMAND_JLINE:
		return _command_lane_top(lane - LANE_COMMAND_JLINE)
	var base := LANE_TOP + (LANE_H + LANE_GAP) * 2.0 + AUX_GAP + AUX_HEAD_H
	if lane == LANE_EVENTS:
		return base
	return base + AUX_ROW_H + 2.0


func _lane_height(lane: int) -> float:
	if lane <= LANE_CAMERA:
		return LANE_H
	if lane <= LANE_BPM:
		return AUX_ROW_H
	return COMMAND_ROW_H


func _lane_center(lane: int) -> float:
	return _lane_top(lane) + _lane_height(lane) * 0.5


func _aux_header_top() -> float:
	return LANE_TOP + (LANE_H + LANE_GAP) * 2.0 + AUX_GAP


func _aux_bottom() -> float:
	var bottom := _aux_header_top() + AUX_HEAD_H
	if aux_open:
		bottom += AUX_ROW_H * 2.0 + 4.0
	return bottom


func _command_header_top() -> float:
	return _aux_bottom() + COMMAND_GAP


func _command_lane_top(index: int) -> float:
	return _command_header_top() + COMMAND_HEAD_H + float(index) * (COMMAND_ROW_H + LANE_GAP)


func _command_bottom() -> float:
	return _command_lane_top(COMMAND_LANES.size() - 1) + COMMAND_ROW_H


func _timeline_height() -> float:
	return maxf(286.0, _command_bottom() + FOOTER_H + 8.0)


func _is_command_lane(lane: int) -> bool:
	return lane >= LANE_COMMAND_JLINE and lane < LANE_COMMAND_JLINE + COMMAND_CATEGORIES.size()


func _lane_at(y: float) -> int:
	for lane in [LANE_SHAPE, LANE_CAMERA]:
		if y >= _lane_top(lane) and y <= _lane_top(lane) + _lane_height(lane):
			return lane
	if aux_open:
		for lane in [LANE_EVENTS, LANE_BPM]:
			if y >= _lane_top(lane) and y <= _lane_top(lane) + _lane_height(lane):
				return lane
	for lane in COMMAND_LANES:
		if y >= _lane_top(lane) and y <= _lane_top(lane) + _lane_height(lane):
			return lane
	return -1


func _lane_name(lane: int) -> String:
	return ["形状", "镜头", "边界事件", "BPM 速度", "判定线", "文本", "滤镜"][clampi(lane, 0, 6)]


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
		4:
			return UITheme.CYAN
		5:
			return UITheme.GOLD
		6:
			return UITheme.VIOLET
	return Color.WHITE


func _lane_items(lane: int) -> Array:
	var chart: Chart = workspace.chart()
	if chart == null:
		return []
	if lane == LANE_SHAPE:
		return chart.sorted_shape_keys()
	if lane == LANE_CAMERA:
		return chart.sorted_view_states()
	if _is_command_lane(lane):
		return chart.commands_in(COMMAND_CATEGORIES[lane - LANE_COMMAND_JLINE])
	if _lane_cache_version != chart.version:
		_lane_cache_version = chart.version
		_lane_cache.clear()
	if not _lane_cache.has(lane):
		var items: Array = []
		if lane == LANE_EVENTS:
			for event in chart.events:
				items.append(event)
		else:
			for point in chart.timing.points:
				items.append(point)
		items.sort_custom(func(a, b) -> bool: return _beat_of(a) < _beat_of(b))
		_lane_cache[lane] = items
	return _lane_cache[lane]


func _beat_of(item) -> float:
	if item is Dictionary:
		return float(item.get("beat", 0.0))
	if item is BoundaryEvent:
		return (item as BoundaryEvent).start_beat
	return float((item as Object).get("beat"))


func _easing_of(item) -> String:
	if item is Dictionary:
		return String(item.get("easing", "in-out"))
	if item is ViewState:
		return (item as ViewState).easing
	if item is BoundaryEvent:
		return (item as BoundaryEvent).easing
	return "linear"


func _curve_of(item) -> Array:
	if item is Dictionary:
		return item.get("curve", [])
	if item is ViewState:
		return (item as ViewState).curve
	return []


func _key_token(lane: int, item) -> String:
	if lane == LANE_SHAPE and item is Dictionary:
		return "shape:%d" % int(item.get("id", 0))
	if lane == LANE_CAMERA and item is ViewState:
		return "view:%d" % (item as ViewState).id
	return ""


func _is_selected(lane: int, item) -> bool:
	var token := _key_token(lane, item)
	return not token.is_empty() and _selected.has(token)


func _is_segment(lane: int, item) -> bool:
	var token := _key_token(lane, item)
	return not token.is_empty() and _segment == token


# ---------------------------------------------------------------- 绘制


func _draw_content(canvas: CanvasItem) -> void:
	_content_draws += 1
	var chart: Chart = workspace.chart()
	canvas.draw_rect(Rect2(Vector2.ZERO, size), Color("#0B0D12"))
	canvas.draw_rect(Rect2(Vector2(0, 0), Vector2(size.x, HEADER_H)), Color("#10131B"))
	canvas.draw_rect(Rect2(Vector2(0, 0), Vector2(GUTTER, size.y)), Color("#0E1118"))
	canvas.draw_line(Vector2(GUTTER, 0), Vector2(GUTTER, size.y), Color(1, 1, 1, 0.12), 1.0)
	canvas.draw_string(UITheme.FONT_REGULAR, Vector2(8, 16), "时间轴", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		Color(1, 1, 1, 0.82))
	canvas.draw_string(UITheme.mono_font(), Vector2(66, 16), "形状 / 镜头 / 辅助 / 演出",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.38))
	if chart == null:
		return
	var start: float = workspace.window_start()
	var span: float = workspace.view_beats()
	var bpb := maxf(1.0, chart.timing.beats_per_bar_at(start))
	_draw_ruler(canvas, start, span, bpb)
	_draw_common_grid(canvas, start, span, bpb)
	for lane in [LANE_SHAPE, LANE_CAMERA]:
		if hidden_lanes.has(lane):
			continue
		_draw_lane(canvas, lane, _lane_items(lane), chart, bpb, workspace.content_end_beat())
	if aux_open and not hidden_lanes.has(LANE_EVENTS):
		_draw_lane(canvas, LANE_EVENTS, _lane_items(LANE_EVENTS), chart, bpb, workspace.content_end_beat())
	if aux_open and not hidden_lanes.has(LANE_BPM):
		_draw_lane(canvas, LANE_BPM, _lane_items(LANE_BPM), chart, bpb, workspace.content_end_beat())
	for lane in COMMAND_LANES:
		if hidden_lanes.has(lane):
			continue
		_draw_command_lane(canvas, lane, _lane_items(lane), chart)
	_draw_gutter(canvas, chart)
	_draw_footer(canvas, chart)


func _draw_ruler(canvas: CanvasItem, start: float, span: float, bpb: float) -> void:
	var font := UITheme.mono_font()
	var chart: Chart = workspace.chart()
	var beat_px := (size.x - GUTTER) / maxf(0.001, span)
	var bar_px := beat_px * bpb
	var step := 1
	while float(step) * bar_px < 72.0 and step < 64:
		step *= 2
	var first := floori(start / bpb)
	var last := ceili((start + span) / bpb)
	for bar in range(first, last + 1):
		var x := _x_for(float(bar) * bpb)
		if x < GUTTER - 1.0 or x > size.x + 1.0:
			continue
		canvas.draw_line(Vector2(x, RULER_H - 11.0), Vector2(x, RULER_H), Color(1, 1, 1, 0.45), 1.0)
		if bar % step == 0:
			var label := str(bar + 1)
			if chart != null:
				label = "%d · %s" % [bar + 1, RingWorkspace._fmt_short(
					chart.timing.beat_to_chart_ms(float(bar) * bpb) + chart.offset_ms)]
			canvas.draw_string(font, Vector2(x + 3, RULER_H - 13.0), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.75))
	if beat_px >= 12.0:
		for beat in range(floori(start), ceili(start + span) + 1):
			var x := _x_for(float(beat))
			if x < GUTTER or x > size.x:
				continue
			canvas.draw_line(Vector2(x, RULER_H - 5.0), Vector2(x, RULER_H), Color(1, 1, 1, 0.16), 1.0)
	canvas.draw_line(Vector2(GUTTER, RULER_H), Vector2(size.x, RULER_H), Color(1, 1, 1, 0.10), 1.0)


## 所有轨道共用一套竖线：以前每轨各画一遍，四倍 draw call。
func _draw_common_grid(canvas: CanvasItem, start: float, span: float, bpb: float) -> void:
	var beat_px := (size.x - GUTTER) / maxf(0.001, span)
	var bottom := _command_bottom()
	var top := LANE_TOP
	for lane in [LANE_SHAPE, LANE_CAMERA]:
		canvas.draw_rect(Rect2(Vector2(GUTTER, _lane_top(lane)), Vector2(size.x - GUTTER, LANE_H)),
			Color(_lane_colour(lane).r, _lane_colour(lane).g, _lane_colour(lane).b, 0.03 if lane == 0 else 0.02))
	if aux_open:
		for lane in [LANE_EVENTS, LANE_BPM]:
			canvas.draw_rect(Rect2(Vector2(GUTTER, _lane_top(lane)), Vector2(size.x - GUTTER, AUX_ROW_H)),
				Color(_lane_colour(lane).r, _lane_colour(lane).g, _lane_colour(lane).b, 0.02))
	for lane in COMMAND_LANES:
		canvas.draw_rect(Rect2(Vector2(GUTTER, _lane_top(lane)), Vector2(size.x - GUTTER, COMMAND_ROW_H)),
			Color(_lane_colour(lane).r, _lane_colour(lane).g, _lane_colour(lane).b, 0.02))
	if not show_grid or beat_px <= 0.0001:
		return
	# 小节格：至少 12px 才画，格数随缩放抽稀；「全部」时不会画两万条线。
	var bar_px := beat_px * maxf(1.0, bpb)
	var bar_step := 1
	while bar_px * float(bar_step) < 12.0:
		bar_step *= 2
	var first_bar := int(floor(start / bpb / float(bar_step))) * bar_step
	var last_bar := int(ceil((start + span) / bpb / float(bar_step))) * bar_step + bar_step
	for bar in range(first_bar, last_bar, bar_step):
		var x := _x_for(float(bar) * bpb)
		if x < GUTTER - 1.0 or x > size.x + 1.0:
			continue
		var next_x := _x_for(float(bar + bar_step) * bpb)
		if int(bar / bar_step) % 2 == 0 and next_x > x:
			canvas.draw_rect(Rect2(Vector2(x, top), Vector2(next_x - x, bottom - top)),
				Color(1, 1, 1, 0.014))
		canvas.draw_line(Vector2(x, top), Vector2(x, bottom), Color(1, 1, 1, 0.075), 1.0)
	# 拍格：放得下才画，按 1/2/4/8 拍抽稀。
	if beat_px >= 6.0:
		var beat_step := 1
		while float(beat_step) * beat_px < 6.0:
			beat_step *= 2
		var first_beat := int(floor(start / float(beat_step))) * beat_step
		var last_beat := int(ceil((start + span) / float(beat_step))) * beat_step + beat_step
		for beat in range(first_beat, last_beat, beat_step):
			var x := _x_for(float(beat))
			if x < GUTTER or x > size.x:
				continue
			canvas.draw_line(Vector2(x, top), Vector2(x, bottom), Color(1, 1, 1, 0.035), 1.0)
	# 吸附细分：只在放得下时画，避免密集小格糊成一片。
	var snap_step := GridDivisions.step_beats(workspace.snap_division())
	if beat_px >= 18.0 and snap_step > 0.0001 and snap_step * beat_px >= 7.0:
		var first: float = floor(start / snap_step) * snap_step
		var b: float = first
		while b <= start + span:
			if absf(b - round(b)) > 0.001:
				var x := _x_for(b)
				if x >= GUTTER and x <= size.x:
					canvas.draw_line(Vector2(x, _lane_top(LANE_SHAPE)),
						Vector2(x, _lane_top(LANE_CAMERA) + LANE_H), Color(1, 1, 1, 0.018), 1.0)
			b += snap_step


func _lane_morph(lane: int, target, span: float) -> float:
	span = maxf(0.000001, span)
	if lane == LANE_SHAPE and target is Dictionary:
		return BoundaryRuntime.morph_beats(target, span)
	if lane == LANE_CAMERA and target is ViewState:
		return (target as ViewState).morph_beats(span)
	return span


func _draw_lane(canvas: CanvasItem, lane: int, items: Array, chart: Chart, bpb: float, content_end: float) -> void:
	var color := _lane_colour(lane)
	var center := _lane_center(lane)
	var bar_h := BAR_H if lane <= LANE_CAMERA else AUX_ROW_H - 4.0
	var top := center - bar_h * 0.5
	if items.is_empty():
		if lane == LANE_SHAPE:
			# 没有形状帧 = 全程基础圆：画一条空心保持带，明确当前状态。
			var x0 := clampf(_x_for(workspace.window_start()), GUTTER + 1.0, size.x - 1.0)
			var x1 := size.x - 1.0
			var rect := Rect2(Vector2(x0, top), Vector2(maxf(2.0, x1 - x0), bar_h))
			canvas.draw_rect(rect, Color(color.r, color.g, color.b, 0.05))
			canvas.draw_dashed_line(Vector2(x0, center), Vector2(x1, center),
				Color(color.r, color.g, color.b, 0.35), 1.0, 6.0)
			canvas.draw_string(UITheme.FONT_REGULAR, Vector2(x0 + 8, center + 4),
				"基础圆（没有形状帧）", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.45))
		else:
			canvas.draw_string(UITheme.FONT_REGULAR, Vector2(GUTTER + 8, center + 4), "还没有关键帧",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.28))
		return
	var beats: Array[float] = []
	for item in items:
		beats.append(_beat_of(item))
	# 第一帧之前：0 拍到第一帧的「基础圆 → 第一帧」带，过渡归目标帧。
	if lane == LANE_SHAPE and beats[0] > 0.001:
		_draw_intro_segment(canvas, lane, items[0], chart, bpb, top, center, bar_h, color)
	for i in items.size():
		var start := beats[i]
		var seg_bpb := maxf(1.0, chart.timing.beats_per_bar_at(start))
		var end := RingWorkspace.span_end(beats, i, content_end, seg_bpb)
		if lane == LANE_EVENTS and items[i] is BoundaryEvent:
			end = maxf(start, (items[i] as BoundaryEvent).end_beat)
		if end <= start:
			end = start + 0.25
		var x0 := _x_for(start)
		var x1 := _x_for(end)
		if x1 < GUTTER - 4.0 or x0 > size.x + 4.0:
			continue
		var key_visible := x0 >= GUTTER - 0.5
		x0 = clampf(x0, GUTTER + 1.0, size.x - 1.0)
		x1 = clampf(x1, GUTTER + 1.0, size.x - 1.0)
		var selected := _is_selected(lane, items[i])
		var hovered := _hover_lane == lane and _hover_index == i
		var seg_hovered := _hover_lane == lane and _hover_segment == i + 1
		var fill_alpha := 0.24 if selected else (0.18 if (hovered or seg_hovered) else 0.12)
		var border_alpha := 0.95 if selected else (0.68 if (hovered or seg_hovered) else 0.42)
		var rect := Rect2(Vector2(x0, top), Vector2(maxf(2.0, x1 - x0), bar_h))
		var span_beats := end - start
		var is_last := i == items.size() - 1
		var clipped_start: bool = start < workspace.window_start() - 0.0001
		var clipped_end: bool = x1 >= size.x - 2.0
		var has_target := i + 1 < items.size()
		var morph := span_beats
		var easing := "linear"
		var curve: Array = []
		var target: Variant = items[i + 1] if has_target else null
		if has_target:
			morph = _lane_morph(lane, target, span_beats)
			easing = _easing_of(target)
			curve = _curve_of(target)
		var transition_selected := has_target and _is_segment(lane, target)
		# 保持段压暗、过渡段提亮：过渡只发生在目标帧前的 morph 拍内。
		canvas.draw_rect(rect, Color(color.r, color.g, color.b, fill_alpha))
		var transition_x := x1
		if has_target and lane <= LANE_CAMERA:
			if morph <= 0.0001:
				transition_x = x1
			elif morph >= span_beats - 0.0001:
				transition_x = x0
			else:
				transition_x = clampf(_x_for(end - morph), x0, x1)
			var tail_w := maxf(0.0, x1 - transition_x)
			if tail_w > 0.5:
				canvas.draw_rect(Rect2(Vector2(transition_x, top), Vector2(tail_w, bar_h)),
					Color(color.r, color.g, color.b, 0.26 if not selected else 0.34))
				_draw_easing(canvas, Rect2(Vector2(transition_x, top), Vector2(tail_w, bar_h)),
					easing, curve, color)
			if morph <= 0.0001:
				# 硬切：在目标帧处画一条亮线，表示到这一拍才切换。
				canvas.draw_line(Vector2(x1, top), Vector2(x1, top + bar_h),
					Color(color.r, color.g, color.b, 0.95), 2.0)
			elif morph < span_beats - 0.0001:
				canvas.draw_line(Vector2(transition_x, top), Vector2(transition_x, top + bar_h),
					Color(color.r, color.g, color.b, 0.85), 1.0)
		else:
			# 最后一帧之后：保持到内容结尾，没有过渡。
			canvas.draw_rect(rect, Color(0.02, 0.03, 0.04, 0.42))
		canvas.draw_rect(rect, Color(color.r, color.g, color.b, border_alpha), false, 2.0 if selected else 1.0)
		if transition_selected:
			canvas.draw_line(Vector2(x0, top + bar_h - 1.5), Vector2(x1, top + bar_h - 1.5), UITheme.CORAL, 2.0)
		# 方向：只在过渡段里画一个小三角，避免把保持段误读成动画。
		if has_target and morph > 0.0001 and not clipped_end:
			var ax := minf(x1 - 7.0, maxf(transition_x + 5.0, x1 - 10.0))
			canvas.draw_colored_polygon(PackedVector2Array([
				Vector2(ax, center - 3.5), Vector2(ax + 5.0, center), Vector2(ax, center + 3.5),
			]), Color(color.r, color.g, color.b, 0.9))
		_draw_segment_content(canvas, lane, items[i], rect, chart, start, end, span_beats, morph, color,
			is_last, clipped_start, clipped_end, has_target, target)
		_draw_key_marker(canvas, lane, items[i], x0, center, color, selected, key_visible)
		if lane <= LANE_CAMERA and x1 <= size.x - 1.0 and not is_last:
			canvas.draw_line(Vector2(x1, center - bar_h * 0.5), Vector2(x1, center + bar_h * 0.5),
				Color(color.r, color.g, color.b, 0.55), 1.5)
			if lane == LANE_SHAPE:
				canvas.draw_rect(Rect2(Vector2(x1 - 3.0, center + bar_h * 0.5 - 4.0), Vector2(6, 6)),
					Color(color.r, color.g, color.b, 0.75), false, 1.0)


## 演出指令轨：块横跨 beat → end_beat，块里画 attack/release 两条刻度。
func _draw_command_lane(canvas: CanvasItem, lane: int, items: Array, _chart: Chart) -> void:
	var color := _lane_colour(lane)
	var top := _lane_top(lane)
	var h := _lane_height(lane)
	var center := top + h * 0.5
	if items.is_empty():
		canvas.draw_string(UITheme.FONT_REGULAR, Vector2(GUTTER + 8, center + 4),
			"双击空白处添加%s指令" % _lane_name(lane), HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
			Color(1, 1, 1, 0.28))
		return
	for i in items.size():
		var command := items[i] as AlphaCommand
		if command == null:
			continue
		var start := command.beat
		var end := command.end_beat()
		if end <= start:
			end = start + 0.25
		var x0 := _x_for(start)
		var x1 := _x_for(end)
		if x1 < GUTTER - 4.0 or x0 > size.x + 4.0:
			continue
		var key_visible := x0 >= GUTTER - 0.5
		x0 = clampf(x0, GUTTER + 1.0, size.x - 1.0)
		x1 = clampf(x1, GUTTER + 1.0, size.x - 1.0)
		var selected := _selected_command == command
		var hovered := _hover_lane == lane and _hover_index == i
		var alpha := 0.26 if selected else (0.18 if hovered else 0.12)
		if not command.enabled:
			alpha *= 0.45
		var rect := Rect2(Vector2(x0, top + 3.0), Vector2(maxf(2.0, x1 - x0), h - 6.0))
		canvas.draw_rect(rect, Color(color.r, color.g, color.b, alpha))
		canvas.draw_rect(rect, Color(color.r, color.g, color.b,
			0.95 if selected else (0.70 if hovered else 0.45)), false, 2.0 if selected else 1.0)
		var length := maxf(0.0001, end - start)
		var attack := clampf(float(command.params.get("attack", 0.25)), 0.0, 0.9)
		var release := clampf(float(command.params.get("release", 0.25)), 0.0, 0.9)
		if attack > 0.001 and attack < 0.999:
			var ax := _x_for(start + length * attack)
			if ax > x0 + 1.0 and ax < x1 - 1.0:
				canvas.draw_line(Vector2(ax, rect.position.y), Vector2(ax, rect.end.y),
					Color(1, 1, 1, 0.32), 1.0)
		if release > 0.001 and release < 0.999:
			var rx := _x_for(end - length * release)
			if rx > x0 + 1.0 and rx < x1 - 1.0:
				canvas.draw_line(Vector2(rx, rect.position.y), Vector2(rx, rect.end.y),
					Color(1, 1, 1, 0.32), 1.0)
		if key_visible:
			canvas.draw_rect(Rect2(Vector2(x0 - 1.0, top + 1.0), Vector2(2.0, h - 2.0)), color)
		if rect.size.x >= 46.0:
			var label := command.label()
			if rect.size.x >= 120.0:
				label += " · %.2f 拍" % command.duration
			if not command.enabled:
				label += "（停用）"
			canvas.draw_string(UITheme.FONT_REGULAR,
				Vector2(rect.position.x + 8.0, center + 4.0), label,
				HORIZONTAL_ALIGNMENT_LEFT, maxf(0.0, rect.size.x - 14.0), 10,
				Color(1, 1, 1, 0.90 if selected else 0.70))


## 0 拍 → 第一帧的「基础圆」带：目标帧的 morph/easing 决定这段的过渡。
func _draw_intro_segment(canvas: CanvasItem, lane: int, first: Variant, chart: Chart, bpb: float,
		top: float, center: float, bar_h: float, color: Color) -> void:
	var end_beat := float((first as Dictionary).get("beat", 0.0))
	if end_beat <= 0.001:
		return
	var x0 := clampf(_x_for(0.0), GUTTER + 1.0, size.x - 1.0)
	var x1 := clampf(_x_for(end_beat), GUTTER + 1.0, size.x - 1.0)
	if x1 <= x0 + 1.0:
		return
	var span := end_beat
	var morph := _lane_morph(lane, first, span)
	var easing := _easing_of(first)
	var curve := _curve_of(first)
	var rect := Rect2(Vector2(x0, top), Vector2(x1 - x0, bar_h))
	var selected := _is_segment(lane, first)
	var hovered := _hover_lane == lane and _hover_segment == 0
	canvas.draw_rect(rect, Color(color.r, color.g, color.b, 0.12 if selected else (0.09 if hovered else 0.06)))
	var tx := x1
	if morph <= 0.0001:
		tx = x1
		canvas.draw_line(Vector2(x1, top), Vector2(x1, top + bar_h),
			Color(color.r, color.g, color.b, 0.95), 2.0)
	elif morph >= span - 0.0001:
		tx = x0
	else:
		tx = clampf(_x_for(end_beat - morph), x0, x1)
		canvas.draw_line(Vector2(tx, top), Vector2(tx, top + bar_h),
			Color(color.r, color.g, color.b, 0.85), 1.0)
	if morph > 0.0001:
		canvas.draw_rect(Rect2(Vector2(tx, top), Vector2(maxf(0.0, x1 - tx), bar_h)),
			Color(color.r, color.g, color.b, 0.20))
		_draw_easing(canvas, Rect2(Vector2(tx, top), Vector2(maxf(0.0, x1 - tx), bar_h)), easing, curve, color)
	canvas.draw_dashed_line(Vector2(x0, center), Vector2(x1, center),
		Color(color.r, color.g, color.b, 0.35), 1.0, 6.0)
	if selected:
		canvas.draw_rect(rect, UITheme.CORAL, false, 2.0)
	var label := "基础圆 → %s" % String((first as Dictionary).get("shape_id", ""))
	if morph <= 0.0001:
		label += " · 硬切"
	else:
		label += " · 过渡 %.2f 拍" % morph
	canvas.draw_string(UITheme.FONT_REGULAR, Vector2(x0 + 8, center + 4), label,
		HORIZONTAL_ALIGNMENT_LEFT, maxf(0.0, x1 - x0 - 12.0), 10, Color(1, 1, 1, 0.62))


func _draw_segment_content(canvas: CanvasItem, lane: int, item, rect: Rect2, chart: Chart,
		start: float, end: float, span_beats: float, morph: float, color: Color,
		is_last: bool, clipped_start: bool, clipped_end: bool, has_target: bool, target) -> void:
	var width := rect.size.x
	if width < 30.0:
		return
	var text_left := rect.position.x + 12.0
	if lane == LANE_SHAPE and item is Dictionary and width >= 118.0:
		var shape := chart.get_shape(String((item as Dictionary).get("shape_id", "")))
		if shape != null:
			var thumb_y := rect.position.y + (rect.size.y - 16.0) * 0.5
			_draw_shape_thumb(canvas, Rect2(Vector2(rect.position.x + 12.0, thumb_y), Vector2(16.0, 16.0)), shape, color)
			text_left = rect.position.x + 34.0
	var secs := (chart.timing.beat_to_chart_ms(end) - chart.timing.beat_to_chart_ms(start)) * 0.001
	var label := ""
	if lane == LANE_SHAPE:
		if is_last:
			label = "保持到结尾"
		else:
			label = "%s · %.2f 秒" % [RingWorkspace.span_label(span_beats, maxf(1.0, chart.timing.beats_per_bar_at(start))), secs]
			if has_target and target is Dictionary and width >= 180.0:
				label += " → %s" % String((target as Dictionary).get("shape_id", ""))
			if width >= 210.0:
				label += " · " + ("硬切" if morph <= 0.0001 else ("过渡 %.2f 拍" % morph))
	elif lane == LANE_CAMERA and item is ViewState:
		var shown: ViewState = (target as ViewState) if has_target and target is ViewState else (item as ViewState)
		var head := "推拉 %.2f · 滚转 %.0f°" % [shown.dolly, shown.rotation]
		if is_last:
			label = "保持到结尾 · " + head
		else:
			label = "%.2f 拍 → %s" % [span_beats, head]
			if width >= 200.0:
				label += " · " + ("硬切" if morph <= 0.0001 else ("过渡 %.2f 拍" % morph))
	elif lane == LANE_EVENTS and item is BoundaryEvent:
		label = "事件 %s" % (item as BoundaryEvent).id
	elif lane == LANE_BPM:
		label = "%.0f BPM" % float((item as Object).get("bpm"))
	if label.is_empty() or width < 46.0:
		return
	if clipped_start:
		label = "← " + label
	if clipped_end and not is_last:
		label += " →"
	var right_edge := minf(rect.end.x, size.x - 4.0)
	canvas.draw_string(UITheme.FONT_REGULAR, Vector2(text_left, rect.position.y + rect.size.y * 0.5 + 4.0),
		label, HORIZONTAL_ALIGNMENT_LEFT, maxf(0.0, right_edge - 8.0 - text_left), 10,
		Color(1, 1, 1, 0.90 if _is_selected(lane, item) else 0.70))


func _draw_easing(canvas: CanvasItem, rect: Rect2, easing: String, curve: Array, color: Color) -> void:
	if rect.size.x < 26.0:
		return
	var points := PackedVector2Array()
	for i in 15:
		var t := float(i) / 14.0
		var eased := Ease.apply_curve(easing, curve, t)
		points.append(Vector2(lerpf(rect.position.x + 3.0, rect.end.x - 3.0, t),
			rect.position.y + rect.size.y - 4.0 - (t - eased) * (rect.size.y - 8.0)))
	canvas.draw_polyline(points, Color(color.r, color.g, color.b, 0.72), 1.2, true)


func _draw_shape_thumb(canvas: CanvasItem, box: Rect2, shape: BoundaryShape, color: Color) -> void:
	var chart: Chart = workspace.chart()
	if chart == null:
		return
	if _thumb_version != chart.version:
		_thumb_version = chart.version
		_thumb_cache.clear()
	if not _thumb_cache.has(shape.id):
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
		_thumb_cache[shape.id] = {"points": points, "low": low, "high": high}
	var cached: Dictionary = _thumb_cache[shape.id]
	var points: PackedVector2Array = cached["points"]
	if points.size() < 3:
		return
	var low: Vector2 = cached["low"]
	var high: Vector2 = cached["high"]
	var span := high - low
	var scale := minf(box.size.x / maxf(0.001, span.x), box.size.y / maxf(0.001, span.y))
	var origin := box.position + box.size * 0.5 - (low + span * 0.5) * scale
	var mapped := PackedVector2Array()
	for p in points:
		mapped.append(origin + p * scale)
	if mapped.size() > 1:
		mapped.append(mapped[0])
	canvas.draw_polyline(mapped, Color(color.r, color.g, color.b, 0.8), 1.0, true)


func _draw_key_marker(canvas: CanvasItem, lane: int, item, x: float, center: float,
		color: Color, selected: bool, visible: bool) -> void:
	if not visible:
		return
	if lane == LANE_CAMERA:
		var r := KEY_SIZE * 0.62
		var diamond := PackedVector2Array([
			Vector2(x, center - r), Vector2(x + r, center), Vector2(x, center + r), Vector2(x - r, center),
		])
		canvas.draw_colored_polygon(diamond, color)
		canvas.draw_polyline(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]]),
			Color(0.05, 0.06, 0.08, 0.9), 1.0, true)
		if selected:
			var outer := PackedVector2Array([
				Vector2(x, center - r - 3.0), Vector2(x + r + 3.0, center),
				Vector2(x, center + r + 3.0), Vector2(x - r - 3.0, center),
			])
			canvas.draw_polyline(PackedVector2Array([outer[0], outer[1], outer[2], outer[3], outer[0]]),
				UITheme.CORAL, 1.5, true)
	elif lane == LANE_SHAPE:
		var key_rect := Rect2(Vector2(x - KEY_SIZE * 0.5, center - KEY_SIZE * 0.5), Vector2(KEY_SIZE, KEY_SIZE))
		canvas.draw_rect(key_rect, color)
		canvas.draw_rect(key_rect, Color(0.05, 0.06, 0.08, 0.9), false, 1.0)
		if selected:
			canvas.draw_rect(key_rect.grow(3.0), UITheme.CORAL, false, 1.5)
	else:
		canvas.draw_rect(Rect2(Vector2(x - 3.0, center - 3.0), Vector2(6, 6)), color, false, 1.0)


func _draw_gutter(canvas: CanvasItem, chart: Chart) -> void:
	var names := [LANE_SHAPE, LANE_CAMERA]
	for lane in names:
		var top := _lane_top(lane)
		var color := _lane_colour(lane)
		var dim := hidden_lanes.has(lane)
		var tint := Color(color.r, color.g, color.b, 0.28 if dim else 0.95)
		canvas.draw_rect(Rect2(Vector2(4, top + 4), Vector2(3, LANE_H - 8)), tint)
		# 眼睛
		var eye := Vector2(20, top + 13)
		canvas.draw_arc(eye, 5.0, 0.0, TAU, 12, Color(1, 1, 1, 0.28 if dim else 0.68), 1.0, true)
		canvas.draw_circle(eye, 1.6, Color(1, 1, 1, 0.28 if dim else 0.75))
		if dim:
			canvas.draw_line(eye + Vector2(-5, 5), eye + Vector2(5, -5), UITheme.CORAL, 1.2)
		# 锁
		var lock := Vector2(34, top + 13)
		canvas.draw_rect(Rect2(lock + Vector2(-3, -1), Vector2(6, 5)),
			UITheme.CORAL if locked_lanes.has(lane) else Color(1, 1, 1, 0.28), false, 1.0)
		canvas.draw_arc(lock + Vector2(0, -1), 2.4, PI, TAU, 8,
			UITheme.CORAL if locked_lanes.has(lane) else Color(1, 1, 1, 0.28), 1.0, true)
		canvas.draw_string(UITheme.FONT_REGULAR, Vector2(50, top + 17), _lane_name(lane),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, tint)
		canvas.draw_string(UITheme.mono_font(), Vector2(50, top + 31),
			"%d 帧" % _lane_items(lane).size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
			Color(1, 1, 1, 0.34 if dim else 0.55))
	# 辅助区
	var aux_top := _aux_header_top()
	canvas.draw_rect(Rect2(Vector2(4, aux_top + 2), Vector2(size.x - 8, AUX_HEAD_H - 4)),
		Color(1, 1, 1, 0.025))
	canvas.draw_string(UITheme.FONT_REGULAR, Vector2(12, aux_top + 15),
		("▾ 辅助" if aux_open else "▸ 辅助"), HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		Color(1, 1, 1, 0.62))
	canvas.draw_string(UITheme.mono_font(), Vector2(70, aux_top + 15), "只读",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.32))
	if aux_open:
		for lane in [LANE_EVENTS, LANE_BPM]:
			var top := _lane_top(lane)
			var color := _lane_colour(lane)
			var tint := Color(color.r, color.g, color.b, 0.85)
			canvas.draw_string(UITheme.FONT_REGULAR, Vector2(50, top + 14), _lane_name(lane),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, tint)
			canvas.draw_string(UITheme.mono_font(), Vector2(150, top + 14),
				str(_lane_items(lane).size()), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.35))
	# 演出指令区：始终展开，三条轨分别是判定线 / 文本 / 滤镜。
	var cmd_top := _command_header_top()
	canvas.draw_rect(Rect2(Vector2(4, cmd_top + 2), Vector2(size.x - 8, COMMAND_HEAD_H - 4)),
		Color(1, 1, 1, 0.025))
	canvas.draw_string(UITheme.FONT_REGULAR, Vector2(12, cmd_top + 14), "演出指令",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.62))
	canvas.draw_string(UITheme.mono_font(), Vector2(70, cmd_top + 14), "双击空白新增",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.32))
	for lane in COMMAND_LANES:
		var top := _lane_top(lane)
		var color := _lane_colour(lane)
		var dim := hidden_lanes.has(lane)
		var tint := Color(color.r, color.g, color.b, 0.28 if dim else 0.95)
		canvas.draw_rect(Rect2(Vector2(4, top + 4), Vector2(3, COMMAND_ROW_H - 8)), tint)
		var eye := Vector2(20, top + 13)
		canvas.draw_arc(eye, 5.0, 0.0, TAU, 12, Color(1, 1, 1, 0.28 if dim else 0.68), 1.0, true)
		canvas.draw_circle(eye, 1.6, Color(1, 1, 1, 0.28 if dim else 0.75))
		if dim:
			canvas.draw_line(eye + Vector2(-5, 5), eye + Vector2(5, -5), UITheme.CORAL, 1.2)
		var lock := Vector2(34, top + 13)
		canvas.draw_rect(Rect2(lock + Vector2(-3, -1), Vector2(6, 5)),
			UITheme.CORAL if locked_lanes.has(lane) else Color(1, 1, 1, 0.28), false, 1.0)
		canvas.draw_arc(lock + Vector2(0, -1), 2.4, PI, TAU, 8,
			UITheme.CORAL if locked_lanes.has(lane) else Color(1, 1, 1, 0.28), 1.0, true)
		canvas.draw_string(UITheme.FONT_REGULAR, Vector2(50, top + 18), _lane_name(lane),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, tint)
		canvas.draw_string(UITheme.mono_font(), Vector2(150, top + 18),
			"%d 条" % _lane_items(lane).size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
			Color(1, 1, 1, 0.34 if dim else 0.55))


func _draw_footer(canvas: CanvasItem, chart: Chart) -> void:
	var top := size.y - FOOTER_H
	canvas.draw_rect(Rect2(Vector2(0, top), Vector2(size.x, FOOTER_H)), Color("#10131B"))
	canvas.draw_line(Vector2(0, top), Vector2(size.x, top), Color(1, 1, 1, 0.08), 1.0)
	var beat: float = workspace.playhead()
	var ms: float = chart.timing.beat_to_chart_ms(beat) + chart.offset_ms
	var text := "%.2f 拍 · %s · 选中 %d" % [beat, RingWorkspace._fmt_short(ms), _selected.size()]
	if not _segment.is_empty():
		text += " · 已选段"
	canvas.draw_string(UITheme.mono_font(), Vector2(8, top + 17), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.62))
	var hints := "双击指令轨空白新增 · 拖指令块改拍 · Del 删除 · ←/→ 微移 · Ctrl+C/V 复制关键帧"
	canvas.draw_string(UITheme.FONT_REGULAR, Vector2(GUTTER - 8, top + 17), hints,
		HORIZONTAL_ALIGNMENT_RIGHT, size.x - GUTTER, 10, Color(1, 1, 1, 0.34))


func _draw_overlay(canvas: CanvasItem) -> void:
	var chart: Chart = workspace.chart()
	if chart == null:
		return
	var x := _x_for(workspace.playhead())
	if x >= GUTTER - 1.0 and x <= size.x + 1.0:
		canvas.draw_line(Vector2(x, RULER_H - 12.0), Vector2(x, size.y - FOOTER_H),
			UITheme.CORAL, 1.5)
		canvas.draw_colored_polygon(PackedVector2Array([
			Vector2(x - 5.0, RULER_H - 12.0), Vector2(x + 5.0, RULER_H - 12.0), Vector2(x, RULER_H - 3.0),
		]), UITheme.CORAL)
		var ms: float = chart.timing.beat_to_chart_ms(workspace.playhead()) + chart.offset_ms
		var label_x := clampf(x + 4.0, GUTTER + 4.0, size.x - 54.0)
		canvas.draw_rect(Rect2(Vector2(label_x - 3.0, 2.0), Vector2(50.0, 16.0)), Color("#10131B"))
		canvas.draw_string(UITheme.mono_font(), Vector2(label_x, 14.0),
			RingWorkspace._fmt_short(ms), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.78))
	if _marquee_active:
		var rect := Rect2(Vector2(minf(_marquee_start.x, _marquee_current.x), minf(_marquee_start.y, _marquee_current.y)),
			Vector2(absf(_marquee_current.x - _marquee_start.x), absf(_marquee_current.y - _marquee_start.y)))
		canvas.draw_rect(rect, Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.10))
		canvas.draw_rect(rect, Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.7), false, 1.0)
	if _hover_lane >= 0 and _drag_kind.is_empty() and not _marquee_active:
		var items := _lane_items(_hover_lane)
		if _hover_index >= 0 and _hover_index < items.size():
			var beat := _beat_of(items[_hover_index])
			var x0 := _x_for(beat)
			var next := beat + 0.25
			if _is_command_lane(_hover_lane) and items[_hover_index] is AlphaCommand:
				next = (items[_hover_index] as AlphaCommand).end_beat()
			elif _hover_index + 1 < items.size():
				next = _beat_of(items[_hover_index + 1])
			var x1 := _x_for(next)
			var top := _lane_top(_hover_lane)
			var h := _lane_height(_hover_lane)
			canvas.draw_rect(Rect2(Vector2(x0, top + 1), Vector2(maxf(2.0, x1 - x0), h - 2)),
				Color(1, 1, 1, 0.05))
			var hint := _hover_hint(_hover_lane, items[_hover_index], beat, next)
			if not hint.is_empty():
				canvas.draw_string(UITheme.FONT_REGULAR, Vector2(minf(x0 + 6, size.x - 190), top - 4),
					hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.78))


func _hover_hint(lane: int, item, start: float, end: float) -> String:
	var chart: Chart = workspace.chart()
	if chart == null:
		return ""
	var secs := (chart.timing.beat_to_chart_ms(end) - chart.timing.beat_to_chart_ms(start)) * 0.001
	if lane == LANE_SHAPE and item is Dictionary:
		var morph := BoundaryRuntime.morph_beats(item, maxf(0.0001, end - start))
		return "形状 %s · %.2f 拍 · %.2f 秒 · 形变 %.2f 拍" % [
			String(item.get("shape_id", "")), end - start, secs, morph]
	if lane == LANE_CAMERA and item is ViewState:
		var state := item as ViewState
		return "镜头 · %.2f 拍 · %.2f 秒 · 推拉 %.2f · 滚转 %.0f° · 缓动 %s" % [
			end - start, secs, state.dolly, state.rotation, state.easing]
	if lane == LANE_EVENTS and item is BoundaryEvent:
		return "事件 %s（只读）" % (item as BoundaryEvent).id
	if lane == LANE_BPM:
		return "BPM %.1f（只读）" % float((item as Object).get("bpm"))
	if _is_command_lane(lane) and item is AlphaCommand:
		var command := item as AlphaCommand
		return "%s · %s · %.2f 拍（%.2f → %.2f）%s" % [
			command.label(), command.category_label(), command.duration,
			command.beat, command.end_beat(), "" if command.enabled else "（停用）"]
	return ""


# ---------------------------------------------------------------- 输入


func _gui_input(event: InputEvent) -> void:
	if workspace.chart() == null:
		return
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var dir := -1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
			if event.ctrl_pressed:
				# 以光标下的拍为锚点连续缩放，放大时内容不会从指针下跑掉。
				workspace.zoom_view_at(_beat_at(event.position.x), 0.8 if dir < 0 else 1.25)
			else:
				workspace.scroll_timeline(dir)
			invalidate()
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				grab_focus()
				_press(event.position, event)
			else:
				_release(event.position)
			accept_event()
	elif event is InputEventMouseMotion:
		if _drag_kind == "playhead":
			workspace.seek(workspace.snap(_beat_at(event.position.x)))
			invalidate_overlay()
			accept_event()
		elif _drag_kind == "keys" or _drag_kind == "command":
			_drag_keys(event.position)
			accept_event()
		elif _marquee_active:
			_marquee_current = event.position
			_update_marquee_selection()
			invalidate_overlay()
			accept_event()
		else:
			_update_hover(event.position)


func _press(pos: Vector2, event: InputEventMouseButton) -> void:
	var lane := _lane_at(pos.y)
	# 左侧图层头：眼睛 / 锁 / 辅助折叠。
	if pos.x <= GUTTER:
		if lane >= 0:
			if pos.x < 30.0:
				if hidden_lanes.has(lane):
					hidden_lanes.erase(lane)
				else:
					hidden_lanes[lane] = true
				invalidate()
				return
			if pos.x < 44.0:
				if locked_lanes.has(lane):
					locked_lanes.erase(lane)
				else:
					locked_lanes[lane] = true
				invalidate()
				return
		if pos.y >= _aux_header_top() and pos.y <= _aux_header_top() + AUX_HEAD_H:
			aux_open = not aux_open
			custom_minimum_size.y = _timeline_height()
			invalidate()
			return
	# 标尺：擦洗。
	if pos.y <= RULER_H:
		_drag_kind = "playhead"
		workspace.seek(workspace.snap(_beat_at(pos.x)))
		invalidate_overlay()
		return
	if lane < 0:
		_drag_kind = "playhead"
		workspace.seek(workspace.snap(_beat_at(pos.x)))
		invalidate_overlay()
		return
	if hidden_lanes.has(lane):
		return
	# 演出指令：点块选中并拖动，双击空白新增。
	if _is_command_lane(lane):
		var command_items := _lane_items(lane)
		var command_hit := _hit_command(lane, command_items, pos)
		if command_hit >= 0:
			var command := command_items[command_hit] as AlphaCommand
			if command != null:
				workspace.seek(command.beat)
				_select_command(command)
				if not locked_lanes.has(lane):
					_begin_command_drag(command, pos)
			return
		if event.double_click:
			add_command_at(lane, workspace.snap(_beat_at(pos.x)))
			return
		clear_selection()
		workspace.seek(workspace.snap(_beat_at(pos.x)))
		invalidate_overlay()
		return
	# 关键帧命中。
	var items := _lane_items(lane)
	var hit := _hit_key(lane, items, pos)
	if hit >= 0:
		var item = items[hit]
		var beat := _beat_of(item)
		workspace.seek(beat)
		var token := _key_token(lane, item)
		if event.double_click and lane == LANE_SHAPE:
			workspace.open_pad_for_current()
			return
		var kind := "shape" if lane == LANE_SHAPE else "view"
		if event.ctrl_pressed or event.shift_pressed:
			_toggle_select(kind, int(String(token).split(":")[1]))
		else:
			_select_only(kind, int(String(token).split(":")[1]))
		if not locked_lanes.has(lane) and (lane == LANE_SHAPE or lane == LANE_CAMERA):
			_begin_key_drag(pos)
		return
	# 段命中：选中段并 seek。
	var seg := _hit_segment(lane, items, pos)
	if seg >= 0:
		var item = items[seg]
		var token := _key_token(lane, item)
		if not token.is_empty() and (lane == LANE_SHAPE or lane == LANE_CAMERA):
			_select_segment("shape" if lane == LANE_SHAPE else "view", int(String(token).split(":")[1]))
			workspace.seek(workspace.snap(_beat_at(pos.x)))
			return
	# 空白：清选 + 框选。
	if not (event.ctrl_pressed or event.shift_pressed):
		clear_selection()
	_marquee_active = true
	_marquee_add = event.ctrl_pressed or event.shift_pressed
	_marquee_start = pos
	_marquee_current = pos
	workspace.seek(workspace.snap(_beat_at(pos.x)))
	invalidate_overlay()


func _release(pos: Vector2) -> void:
	if _drag_kind == "playhead":
		_drag_kind = ""
		workspace.finish_scrub()
		return
	if _drag_kind == "command":
		_drag_kind = ""
		_drag_command = null
		workspace.end_preview_drag()
		workspace.end_content_freeze()
		var chart: Chart = workspace.chart()
		if chart != null:
			chart.commands.sort_custom(func(a: AlphaCommand, b: AlphaCommand) -> bool: return a.beat < b.beat)
		workspace.finish_edit()
		invalidate()
		return
	if _drag_kind == "keys":
		_drag_kind = ""
		workspace.end_preview_drag()
		workspace.end_content_freeze()
		var chart: Chart = workspace.chart()
		if chart != null:
			chart.shape_keys.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return float(a.get("beat", 0.0)) < float(b.get("beat", 0.0)))
			chart.view_states.sort_custom(func(a: ViewState, b: ViewState) -> bool: return a.beat < b.beat)
		workspace.finish_edit()
		invalidate()
		return
	if _marquee_active:
		_update_marquee_selection()
		_marquee_active = false
		invalidate_overlay()


func _hit_key(lane: int, items: Array, pos: Vector2) -> int:
	for i in items.size():
		var x := _x_for(_beat_of(items[i]))
		if absf(pos.x - x) <= KEY_HIT:
			return i
	return -1


func _hit_command(_lane: int, items: Array, pos: Vector2) -> int:
	if pos.x < GUTTER or items.is_empty():
		return -1
	for i in items.size():
		var command := items[i] as AlphaCommand
		if command == null:
			continue
		var x0 := _x_for(command.beat)
		var x1 := _x_for(command.end_beat())
		if x1 < GUTTER or x0 > size.x:
			continue
		if pos.x >= minf(x0, x1) - 2.0 and pos.x <= maxf(x0, x1) + 2.0:
			return i
	return -1


func _hit_segment(lane: int, items: Array, pos: Vector2) -> int:
	if pos.x < GUTTER or items.is_empty():
		return -1
	# 第一帧之前的「基础圆」带：目标就是第一帧。
	if lane == LANE_SHAPE:
		var first_beat := _beat_of(items[0])
		if first_beat > 0.001 and pos.x >= _x_for(0.0) and pos.x <= _x_for(first_beat):
			return 0
	# 第 i 段（i → i+1）的过渡归目标帧 i+1。
	for i in items.size() - 1:
		if pos.x >= _x_for(_beat_of(items[i])) and pos.x <= _x_for(_beat_of(items[i + 1])):
			return i + 1
	# 最后一帧之后的保持带：点中它选中最后一帧（入场过渡属于上一段）。
	var chart: Chart = workspace.chart()
	if chart != null:
		var last := items.size() - 1
		var start := _beat_of(items[last])
		var bpb := maxf(1.0, chart.timing.beats_per_bar_at(start))
		var end := RingWorkspace.span_end([start], 0, workspace.content_end_beat(), bpb)
		if lane == LANE_EVENTS and items[last] is BoundaryEvent:
			end = maxf(start, (items[last] as BoundaryEvent).end_beat)
		if pos.x >= _x_for(start) and pos.x <= _x_for(end):
			return last
	return -1


func _update_hover(pos: Vector2) -> void:
	if pos.distance_to(_hover_pos) < 1.5:
		return
	_hover_pos = pos
	var lane := _lane_at(pos.y)
	if lane < 0 or hidden_lanes.has(lane):
		if _hover_lane != -1:
			_hover_lane = -1
			_hover_index = -1
			_hover_segment = -1
			invalidate_overlay()
		return
	var items := _lane_items(lane)
	var index := _hit_command(lane, items, pos) if _is_command_lane(lane) else _hit_key(lane, items, pos)
	var segment := -1
	if index < 0 and not _is_command_lane(lane):
		segment = _hit_segment(lane, items, pos)
	if index != _hover_index or segment != _hover_segment or lane != _hover_lane:
		_hover_lane = lane
		_hover_index = index
		_hover_segment = segment
		invalidate_overlay()


func _begin_key_drag(pos: Vector2) -> void:
	_drag_kind = "keys"
	_drag_start_beat = workspace.snap(_beat_at(pos.x))
	_drag_bases.clear()
	for key in selected_shape_keys():
		_drag_bases.append({"kind": "shape", "id": int(key.get("id", 0)), "beat": float(key.get("beat", 0.0))})
	for state in selected_views():
		_drag_bases.append({"kind": "view", "id": state.id, "beat": state.beat})
	workspace.begin_preview_drag()
	workspace.begin_content_freeze()
	workspace.begin_edit()


func _begin_command_drag(command: AlphaCommand, pos: Vector2) -> void:
	if command == null:
		return
	_drag_kind = "command"
	_drag_command = command
	_drag_start_beat = workspace.snap(_beat_at(pos.x))
	_drag_command_origin = command.beat
	workspace.begin_preview_drag()
	workspace.begin_content_freeze()
	workspace.begin_edit()


func _drag_keys(pos: Vector2) -> void:
	var chart: Chart = workspace.chart()
	if chart == null:
		return
	var snapped: float = workspace.snap(_beat_at(pos.x))
	if _drag_kind == "command":
		if _drag_command != null:
			_drag_command.beat = maxf(0.0, _drag_command_origin + snapped - _drag_start_beat)
			workspace.touch_chart()
			invalidate()
		return
	var delta: float = snapped - _drag_start_beat
	for base in _drag_bases:
		var beat := maxf(0.0, float(base["beat"]) + delta)
		if String(base["kind"]) == "shape":
			var key := chart.shape_key_by_id(int(base["id"]))
			if not key.is_empty():
				key["beat"] = beat
		else:
			var state := chart.view_state_by_id(int(base["id"]))
			if state != null:
				state.beat = beat
	workspace.touch_chart()
	invalidate()


func _update_marquee_selection() -> void:
	if not _marquee_active:
		return
	var rect := Rect2(Vector2(minf(_marquee_start.x, _marquee_current.x), minf(_marquee_start.y, _marquee_current.y)),
		Vector2(absf(_marquee_current.x - _marquee_start.x), absf(_marquee_current.y - _marquee_start.y)))
	if not _marquee_add:
		_selected.clear()
		_primary = ""
	var chart: Chart = workspace.chart()
	if chart == null:
		return
	for lane in [LANE_SHAPE, LANE_CAMERA]:
		if hidden_lanes.has(lane):
			continue
		var items := _lane_items(lane)
		var center := _lane_center(lane)
		for item in items:
			var point := Vector2(_x_for(_beat_of(item)), center)
			if rect.has_point(point):
				var token := _key_token(lane, item)
				if not token.is_empty():
					_selected[token] = true
					if _primary.is_empty():
						_primary = token
	_segment = ""
	invalidate()
	selection_changed.emit()


# ---------------------------------------------------------------- 键盘


func handle_key(event: InputEventKey) -> bool:
	if event.ctrl_pressed:
		match event.keycode:
			KEY_C:
				copy_selection()
				return true
			KEY_X:
				cut_selection()
				return true
			KEY_V:
				paste()
				return true
		return false
	match event.keycode:
		KEY_DELETE, KEY_BACKSPACE:
			if selection_count() > 0 or not _segment.is_empty():
				delete_selection()
				return true
		KEY_LEFT, KEY_RIGHT:
			if selection_count() > 0:
				var step := GridDivisions.step_beats(workspace.snap_division())
				if step <= 0.0001:
					step = 0.25
				if event.shift_pressed:
					step = 1.0
				nudge_selection(-step if event.keycode == KEY_LEFT else step)
				return true
		KEY_HOME:
			workspace.seek(0.0)
			workspace._view_start = 0.0
			invalidate()
			return true
		KEY_END:
			if workspace.chart() != null:
				workspace.seek(workspace.content_end_beat())
			return true
		KEY_F:
			workspace.fit_key_range_timeline()
			return true
	return false


# ---------------------------------------------------------------- 帧操作


func copy_selection() -> void:
	var shapes := selected_shape_keys()
	var views := selected_views()
	if shapes.is_empty() and views.is_empty():
		workspace._set_hint("没有选中关键帧。")
		return
	_clipboard.clear()
	var origin := INF
	for key in shapes:
		origin = minf(origin, float(key.get("beat", 0.0)))
	for state in views:
		origin = minf(origin, state.beat)
	for key in shapes:
		_clipboard.append({"kind": "shape", "offset": float(key.get("beat", 0.0)) - origin,
			"data": key.duplicate(true)})
	for state in views:
		_clipboard.append({"kind": "view", "offset": state.beat - origin, "data": state.to_dict()})
	workspace._set_hint("已复制 %d 帧，播放头处粘贴。" % _clipboard.size())


func cut_selection() -> void:
	copy_selection()
	delete_selection()


func paste() -> void:
	if _clipboard.is_empty():
		workspace._set_hint("剪贴板是空的。")
		return
	var chart: Chart = workspace.chart()
	if chart == null:
		return
	var start: float = workspace.playhead()
	var added: Array[String] = []
	workspace.mutate_chart(func() -> void:
		for entry in _clipboard:
			var beat := maxf(0.0, start + float(entry.get("offset", 0.0)))
			if String(entry.get("kind", "shape")) == "shape":
				var data: Dictionary = (entry.get("data", {}) as Dictionary).duplicate(true)
				data["beat"] = beat
				data["id"] = chart.next_key_id()
				var replaced := false
				for existing in chart.shape_keys:
					if absf(float(existing.get("beat", 0.0)) - beat) < 0.001:
						existing.clear()
						for field in data.keys():
							existing[field] = data[field]
						replaced = true
						break
				if not replaced:
					chart.shape_keys.append(data)
				added.append("shape:%d" % int(data.get("id", 0)))
			else:
				var state := ViewState.from_dict(entry.get("data", {}))
				state.beat = beat
				state.id = chart.next_key_id()
				var replaced := false
				for i in chart.view_states.size():
					if absf(chart.view_states[i].beat - beat) < 0.001:
						chart.view_states[i] = state
						replaced = true
						break
				if not replaced:
					chart.view_states.append(state)
				added.append("view:%d" % state.id)
		chart.shape_keys.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.get("beat", 0.0)) < float(b.get("beat", 0.0)))
		chart.view_states.sort_custom(func(a: ViewState, b: ViewState) -> bool: return a.beat < b.beat)
	)
	_selected.clear()
	for token in added:
		_selected[token] = true
	if not added.is_empty():
		_primary = added[0]
		var parts := String(_primary).split(":")
		if parts.size() == 2:
			_sync_app_selection(String(parts[0]), int(parts[1]))
	invalidate()
	selection_changed.emit()
	workspace._set_hint("已粘贴 %d 帧。" % added.size())


func delete_selection() -> void:
	var command := _selected_command
	var shapes := selected_shape_keys()
	var views := selected_views()
	if command == null and shapes.is_empty() and views.is_empty():
		return
	var shape_ids: Array[int] = []
	for key in shapes:
		shape_ids.append(int(key.get("id", 0)))
	var view_ids: Array[int] = []
	for state in views:
		view_ids.append(state.id)
	workspace.mutate_chart(func() -> void:
		var chart: Chart = workspace.chart()
		if chart == null:
			return
		if command != null:
			chart.remove_command(command)
		for key in chart.shape_keys.duplicate():
			if shape_ids.has(int(key.get("id", 0))):
				chart.shape_keys.erase(key)
		for state in chart.view_states.duplicate():
			if view_ids.has(state.id):
				chart.view_states.erase(state)
	)
	clear_selection()
	workspace._set_hint("已删除 %d 项。" % (shape_ids.size() + view_ids.size() + (1 if command != null else 0)))


## 双击指令轨空白：默认加这一类里的第一条指令。
func add_command_at(lane: int, beat: float) -> void:
	if not _is_command_lane(lane):
		return
	var category: String = String(COMMAND_CATEGORIES[lane - LANE_COMMAND_JLINE])
	var names := AlphaCommand.names(category)
	if names.is_empty():
		return
	add_command_of(names[0], beat)


func add_command_of(name: String, beat: float) -> void:
	if AlphaCommand.spec_of(name).is_empty():
		return
	var chart: Chart = workspace.chart()
	if chart == null:
		return
	var created_box: Array = [null]
	workspace.mutate_chart(func() -> void:
		created_box[0] = chart.add_command(name, maxf(0.0, beat))
	)
	var created := created_box[0] as AlphaCommand
	if created == null:
		return
	_select_command(created)
	workspace.seek(created.beat)
	workspace._set_hint("已添加 %s（%.2f 拍）；在右侧改参数。" % [created.label(), created.beat])


func delete_command(command: AlphaCommand) -> void:
	if command == null:
		return
	var chart: Chart = workspace.chart()
	if chart == null or not chart.commands.has(command):
		return
	workspace.mutate_chart(func() -> void:
		chart.remove_command(command)
	)
	if _selected_command == command:
		_selected_command = null
	invalidate()
	selection_changed.emit()
	workspace._set_hint("已删除指令。")


func delete_selected_command() -> void:
	delete_command(_selected_command)


func insert_frames(beats: float) -> void:
	var chart: Chart = workspace.chart()
	if chart == null:
		return
	var lanes: Array[int] = []
	if not selected_shape_keys().is_empty() or _primary.begins_with("shape:"):
		lanes.append(LANE_SHAPE)
	if not selected_views().is_empty() or _primary.begins_with("view:"):
		lanes.append(LANE_CAMERA)
	if lanes.is_empty():
		lanes.append(LANE_SHAPE)
	var at: float = workspace.playhead()
	workspace.mutate_chart(func() -> void:
		if lanes.has(LANE_SHAPE):
			for key in chart.shape_keys:
				if float(key.get("beat", 0.0)) >= at - 0.0001:
					key["beat"] = float(key.get("beat", 0.0)) + beats
		if lanes.has(LANE_CAMERA):
			for state in chart.view_states:
				if state.beat >= at - 0.0001:
					state.beat += beats
	)
	workspace._set_hint("已在当前轨插入 %.2f 拍；另一条轨没有跟着移，注意同步。" % beats)


func nudge_selection(delta: float) -> void:
	if _selected.is_empty() and _selected_command == null:
		return
	var chart: Chart = workspace.chart()
	if chart == null:
		return
	workspace.mutate_chart(func() -> void:
		if _selected_command != null:
			_selected_command.beat = maxf(0.0, _selected_command.beat + delta)
		for key in selected_shape_keys():
			key["beat"] = maxf(0.0, float(key.get("beat", 0.0)) + delta)
		for state in selected_views():
			state.beat = maxf(0.0, state.beat + delta)
		chart.shape_keys.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.get("beat", 0.0)) < float(b.get("beat", 0.0)))
		chart.view_states.sort_custom(func(a: ViewState, b: ViewState) -> bool: return a.beat < b.beat)
		chart.commands.sort_custom(func(a: AlphaCommand, b: AlphaCommand) -> bool: return a.beat < b.beat)
	)
