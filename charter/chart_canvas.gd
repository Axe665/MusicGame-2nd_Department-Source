class_name ChartCanvas
extends Control

signal hover_changed(u: float, beat: float)
signal notice(message: String, level: String)
signal group_note_hint(group_id: int, screen_pos: Vector2)

const LEFT_MARGIN := 58.0
const TOP_MARGIN := 24.0
const BOTTOM_MARGIN := 12.0
const RIGHT_MARGIN := 58.0
const WAVE_WIDTH := 24.0
const NOTE_TOOLS := ["tap", "hold", "path", "seek", "anchor", "bell"]
const PATH_HIT_RADIUS := 12.0
const PATH_CHAIN_BLUE := Color("#4D8DFF")
const DIVISION_WIDTH := 42.0
const DIVISION_ITEM_HEIGHT := 22.0
const DIVISION_GAP := 3.0
const DIVISION_MARGIN := 8.0

var _app: Node = null
var px_per_beat: float = 28.0
var scroll_beat: float = 0.0
var follow_playhead: bool = true
var flow_down: bool = true
var snap_division: int = GridDivisions.DEFAULT_DIVISION
## 播放滚动：page（翻页）/ pin（播放头固定，方向看 flow_down）。
var playback_view: String = "page"
## 只在播放或拖进度条时钉住；暂停时回到自由浏览。
var playback_pinned: bool = false
## 钉住的播放头离视图边缘的比例。
const PIN_MARGIN := 0.08
## 滚轮临时脱离钉住后，这么久自动拉回。
const PIN_RESUME_MS := 1200
var _pin_resume_msec: int = 0

var _mouse_pos: Vector2 = Vector2.ZERO
var _hover_u: float = 0.0
var _hover_beat: float = 0.0
var _drag_mode: String = ""
var _drag_start: Vector2 = Vector2.ZERO
var _drag_start_beat: float = 0.0
var _drag_start_u: float = 0.0
var _drag_notes: Array[Dictionary] = []
var _drag_region: Region = null
var _drag_width_side: int = 0
var _drag_width_note: Note = null
var _drag_width_origin: float = 0.0
var _drag_width_start: float = 0.0
var _drag_tail_note: Note = null
var _drag_tail_start: float = 0.0
var _drag_tail_origin: float = 0.0
var _drag_head_note: Note = null
var _drag_head_start: float = 0.0
var _drag_head_origin: float = 0.0
var _drag_region_start_beat: float = 0.0
var _drag_region_end_beat: float = 0.0
var _drag_region_angle: float = 0.0
var _drag_region_width: float = 0.0
var _marquee: Rect2 = Rect2()
var _marquee_start_beat: float = 0.0
var _marquee_start_u: float = 0.0
var _marquee_end_beat: float = 0.0
var _marquee_end_u: float = 0.0
var _right_hit: Dictionary = {}
var _pending_path: Note = null
var _pending_path_parent: Note = null
var _pending_hold: Note = null

var _waveform_peaks: PackedFloat32Array = PackedFloat32Array()
var _waveform_duration: float = 0.0
var _waveform_audio_path: String = ""
var _wave_key: String = ""
## 波形按「音频位置 → 拍」采样一次（与滚动无关），每帧只做拍→y 映射。
var _wave_beats: PackedFloat32Array = PackedFloat32Array()
var _wave_vals: PackedFloat32Array = PackedFloat32Array()
var _wave_right: PackedVector2Array = PackedVector2Array()
var _wave_left: PackedVector2Array = PackedVector2Array()
var _last_playhead_redraw: int = 0
var _overlay: Control
var _sorted_notes: Array[Note] = []
var _sorted_chart: Chart = null
var _sorted_count: int = -1
var _sorted_dirty: bool = true
var _sorted_max_duration: float = 0.0
var _ghost_layer = null
var _clipboard_notes: Array[Note] = []
var _clipboard_reference_beat: float = 0.0
var _clipboard_reference_u: float = 0.0
var _clipboard_mouse_beat: float = 0.0
var _clipboard_mouse_u: float = 0.0
var _clipboard_active: bool = false
var _clipboard_cut: bool = false
var _ghost_last_scroll: float = -INF
var _ghost_last_px: float = -INF
var _ghost_last_stretch: float = -INF
var _ghost_last_size: Vector2 = Vector2.ZERO
var _division_rects: Array[Rect2] = []
var _division_hover: int = -1
var _flow_button: Button


func _ready() -> void:
	_app = get_node_or_null("/root/App")
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	focus_mode = Control.FOCUS_CLICK
	set_process(true)
	if _app != null:
		_app.chart_changed.connect(_on_chart_changed)
		_app.chart_replaced.connect(_clear_clipboard_on_chart_replace)
		_app.chart_live_changed.connect(_on_chart_live_changed)
		_app.ring_changed.connect(_on_chart_live_changed)
		_app.playhead_changed.connect(_on_playhead_changed)
		_app.selection_changed.connect(_on_selection_changed)
		_app.tool_changed.connect(_on_tool_changed)
		_app.snap_changed.connect(_on_snap_changed)
		_app.flow_changed.connect(_on_flow_changed)
		px_per_beat = _app.zoom_px_per_beat
	var ghost_script: Script = load("res://charter/chart_ghost_layer.gd")
	if ghost_script != null:
		_ghost_layer = ghost_script.new()
		_ghost_layer.name = "GhostLayer"
		_ghost_layer.visible = false
		add_child(_ghost_layer)
		_ghost_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_ghost_layer._app = _app
		snap_division = _app.snap_division
		flow_down = _app.time_flows_down
		_ghost_layer.flow_down = flow_down
	_overlay = load("res://charter/chart_overlay.gd").new()
	_overlay.canvas = self
	add_child(_overlay)
	_build_flow_button()
	_refresh_waveform()


func _process(_delta: float) -> void:
	if not _clipboard_active or _ghost_layer == null:
		return
	var stretch: float = float(_app.vertical_stretch) if _app != null else 0.0
	if (not is_equal_approx(_ghost_last_scroll, scroll_beat)
			or not is_equal_approx(_ghost_last_px, px_per_beat)
			or not is_equal_approx(_ghost_last_stretch, stretch)
			or _ghost_last_size != size):
		_sync_ghost_layer()


func _plot_rect() -> Rect2:
	return Rect2(LEFT_MARGIN, TOP_MARGIN, maxf(10.0, size.x - LEFT_MARGIN - RIGHT_MARGIN), maxf(10.0, size.y - TOP_MARGIN - BOTTOM_MARGIN))


func _u_to_x(u: float) -> float:
	var plot := _plot_rect()
	return plot.position.x + clampf(u, 0.0, 1.0) * plot.size.x


func _x_to_u(x: float) -> float:
	var plot := _plot_rect()
	return clampf((x - plot.position.x) / maxf(1.0, plot.size.x), 0.0, 1.0)


func _vertical_scale() -> float:
	if _app == null:
		return 1.0
	return 1.0 + clampf(float(_app.vertical_stretch), 0.0, 10.0) * 0.5


func _effective_px_per_beat() -> float:
	return px_per_beat * _vertical_scale()


func _beat_to_y(beat: float) -> float:
	var plot := _plot_rect()
	var distance := (beat - scroll_beat) * _effective_px_per_beat()
	if flow_down:
		return plot.position.y + distance
	return plot.end.y - distance


func _y_to_beat(y: float) -> float:
	var plot := _plot_rect()
	if flow_down:
		return scroll_beat + (y - plot.position.y) / maxf(0.1, _effective_px_per_beat())
	return scroll_beat + (plot.end.y - y) / maxf(0.1, _effective_px_per_beat())


## 钉住时让播放头停在流动方向边缘 PIN_MARGIN 的位置。
## 两个方向共用同一个公式：向下流动时 scroll 是顶边拍，向上流动时是底边拍，
## 而底边拍 + 8% 可见高度正好等于「播放头往回流 8%」。
static func pinned_scroll_beat(playhead: float, visible_beats: float, margin: float = PIN_MARGIN) -> float:
	return maxf(0.0, playhead - visible_beats * margin)


## 翻转绘制方向时保持播放头屏幕位置不变：ratio → 1 - ratio。
## 纯函数，返回新的 scroll_beat（未钳位）。
static func flipped_scroll_beat(playhead: float, scroll_before: float, visible_beats: float) -> float:
	var ratio := (playhead - scroll_before) / maxf(0.001, visible_beats)
	if ratio < 0.0 or ratio > 1.0:
		return scroll_before
	return playhead - (1.0 - ratio) * visible_beats


## 可滚动的最后一屏：内容末端 + 4 小节，至少留一屏。
func _scroll_limit() -> float:
	var limit: float = _app.chart_limit_beats() if _app != null else 0.0
	return maxf(0.0, limit - _plot_visible_beats())


func clamp_scroll() -> void:
	var clamped := clampf(scroll_beat, 0.0, _scroll_limit())
	if is_equal_approx(clamped, scroll_beat):
		return
	scroll_beat = clamped
	queue_redraw()
	if _overlay != null:
		_overlay.queue_redraw()


## 拍线区实际可见的拍数（不含上下留白）。
func _plot_visible_beats() -> float:
	var plot := _plot_rect()
	return plot.size.y / maxf(10.0, _effective_px_per_beat())


## 由 main 在播放/拖动状态切换时调用；方向由 flow_down 单独决定。
func set_playback_view(mode: String, pinned: bool) -> void:
	if mode == playback_view and pinned == playback_pinned:
		return
	playback_view = mode
	playback_pinned = pinned
	queue_redraw()
	if _overlay != null:
		_overlay.queue_redraw()


func _visible_beats() -> float:
	return _plot_visible_beats()


func _clear_clipboard_on_chart_replace() -> void:
	_cancel_pending()
	cancel_clipboard(false)


func has_clipboard() -> bool:
	return _clipboard_active and not _clipboard_notes.is_empty()


func copy_selection(cut: bool = false) -> void:
	if _app == null or _app.chart == null:
		return
	var selected: Array[Note] = []
	for note in _app.selection_with_partners():
		# Path 必须整链复制：只带一段的话粘出来是断链（子部件会被预览/存盘跳过）。
		for part in _app.chart.path_chain(note):
			if not selected.has(part):
				selected.append(part)
	if selected.is_empty():
		notice.emit("先选中音符，再复制或剪切。", "warning")
		return
	var copies: Array[Note] = []
	var first_beat := INF
	for note in selected:
		copies.append(Note.from_dict(note.to_dict()))
		first_beat = minf(first_beat, note.beat)
	copies.sort_custom(func(a: Note, b: Note) -> bool: return a.beat < b.beat)
	_clipboard_notes = copies
	_clipboard_reference_beat = first_beat
	var reference := copies[0] if not copies.is_empty() else null
	_clipboard_reference_u = _note_u(reference) if reference != null else 0.0
	_clipboard_mouse_beat = _current_mouse_beat()
	_clipboard_mouse_u = _x_to_u(_mouse_pos.x) if _plot_rect().has_point(_mouse_pos) else _clipboard_reference_u
	_clipboard_active = true
	_clipboard_cut = cut
	if cut:
		var ids: Array[int] = []
		for note in selected:
			ids.append(note.id)
		_app.begin_edit()
		for note in _app.chart.notes.duplicate():
			if ids.has(note.id):
				_app.chart.notes.erase(note)
		_app.finish_edit()
		_app.clear_selection()
	_rebuild_ghost()
	_sync_ghost_layer()
	notice.emit(
		("已剪切 %d 个音符；在谱面点一下放置，Ctrl+V 放在鼠标处，Ctrl+A 镜像粘贴。" if cut
		else "已复制 %d 个音符；在谱面点一下放置，Ctrl+V 放在鼠标处，Ctrl+A 镜像粘贴。") % copies.size(),
		"info"
	)


func paste_clipboard(mirror: bool = false) -> bool:
	if _app == null or _app.chart == null or not has_clipboard():
		notice.emit("剪贴板为空：先 Ctrl+C 复制或 Ctrl+X 剪切。", "warning")
		return false
	return _paste_at(_clipboard_mouse_beat, mirror, _clipboard_mouse_u)


## 把剪贴板整段落在 beat（最早那颗的拍）上。Path 链的 id 在这里整体重映射——
## 照抄旧 id 会让新 part 指向原链，于是预览/试玩/存盘都把它当子部件跳过。
func _paste_at(beat: float, mirror: bool = false, drop_u: float = NAN) -> bool:
	var chart: Chart = _app.chart
	var delta := beat - _clipboard_reference_beat
	var target_u := drop_u if is_finite(drop_u) else _clipboard_mouse_u
	var reference_u := (1.0 - _clipboard_reference_u) if mirror else _clipboard_reference_u
	# Avoid dropping a copy on top of an existing note: walk to the next rail.
	var divisions := maxi(2, int(_app.angle_divisions))
	for _attempt in 24:
		var angle := fposmod(target_u * 360.0, 360.0)
		var clear := true
		for other in chart.notes:
			if absf(other.beat - maxf(0.0, beat)) > 0.01:
				continue
			var other_u := _note_u(other)
			if absf(JudgeMath.angle_delta(angle, other_u * 360.0)) <= 2.0:
				clear = false
				break
		if clear:
			break
		target_u = fposmod(target_u + 1.0 / float(divisions), 1.0)
	var delta_u := target_u - reference_u
	var id_map := {}
	var copies: Array[Note] = []
	_app.begin_edit()
	for note in _clipboard_notes:
		var copy := Note.from_dict(note.to_dict())
		copy.id = chart.next_note_id()
		copy.beat = maxf(0.0, note.beat + delta)
		if copy.type in ["hold", "path"]:
			copy.end_beat = maxf(copy.beat + 0.25, note.end_beat + delta)
		if mirror:
			copy.mirror_u()
		copy.rotate_u(delta_u * 360.0)
		id_map[note.id] = copy
		copies.append(copy)
	for copy in copies:
		if copy.type != "path":
			continue
		# 链外链接一律断开（复制时已带上整链，这里只兜底防止旧剪贴板留断链）。
		if id_map.has(copy.path_prev_id):
			copy.path_prev_id = (id_map[copy.path_prev_id] as Note).id
		else:
			copy.path_prev_id = -1
			copy.path_part = 0
		copy.path_next_id = (id_map[copy.path_next_id] as Note).id if id_map.has(copy.path_next_id) else -1
	var new_ids: Array[int] = []
	for copy in copies:
		chart.notes.append(copy)
	chart.reassign_note_ids()
	for copy in copies:
		new_ids.append(copy.id)
	_app.finish_edit()
	_app.select_notes(new_ids)
	# A paste consumes the pending clipboard: drop the ghost preview and keep
	# the freshly pasted notes selected for immediate follow-up editing.
	cancel_clipboard(false)
	queue_redraw()
	notice.emit(("已镜像粘贴 %d 个音符。" if mirror else "已粘贴 %d 个音符。") % new_ids.size(), "info")
	return true


func mirror_selected_note() -> bool:
	if _app == null or _app.chart == null:
		return false
	var selected: Array[Note] = _app.get_selected_notes()
	if selected.size() != 1:
		return false
	var group: Array[Note] = _app.with_anchor_partners(selected)
	for item in group:
		if item.lock:
			notice.emit("音符已锁定，无法镜像。", "warning")
			return false
	_app.begin_edit()
	for item in group:
		item.mirror_u()
	_app.finish_edit()
	queue_redraw()
	notice.emit("已镜像 %d 个音符。" % group.size(), "info")
	return true


func cancel_clipboard(show_notice: bool = true) -> void:
	var had_clipboard := _clipboard_active
	_clipboard_active = false
	_clipboard_cut = false
	_clipboard_notes.clear()
	if _ghost_layer != null:
		_ghost_layer.ghost_notes.clear()
		_ghost_layer.visible = false
		_ghost_layer.queue_redraw()
	if show_notice and had_clipboard:
		notice.emit("已取消复制/剪切预览；已剪切的音符可用 Ctrl+Z 恢复。", "info")


func _note_u(note: Note) -> float:
	if note == null:
		return 0.0
	if note.type == "bell":
		return fposmod(note.center_u, 1.0)
	return fposmod(note.angle, 360.0) / 360.0


func _current_mouse_beat() -> float:
	if _mouse_pos != Vector2.ZERO and _plot_rect().has_point(_mouse_pos):
		return _y_to_beat(_mouse_pos.y)
	if _app != null:
		return _app.playhead_beat
	return 0.0


func _rebuild_ghost() -> void:
	if _ghost_layer == null:
		return
	if not _clipboard_active:
		_ghost_layer.ghost_notes = []
		_ghost_layer.visible = false
		_ghost_layer.queue_redraw()
		return
	var delta := _clipboard_mouse_beat - _clipboard_reference_beat
	var ghosts: Array[Note] = []
	for note in _clipboard_notes:
		var copy := Note.from_dict(note.to_dict())
		copy.id = -1 - ghosts.size()
		copy.beat = maxf(0.0, note.beat + delta)
		if copy.type in ["hold", "path"]:
			copy.end_beat = maxf(copy.beat + 0.25, note.end_beat + delta)
		ghosts.append(copy)
	_ghost_layer.ghost_notes = ghosts
	_ghost_layer.visible = true
	_sync_ghost_layer()


func _sync_ghost_layer() -> void:
	if _ghost_layer == null:
		return
	_ghost_layer._app = _app
	_ghost_layer.scroll_beat = scroll_beat
	_ghost_layer.px_per_beat = px_per_beat
	_ghost_layer.flow_down = flow_down
	_ghost_layer.visible = _clipboard_active
	_ghost_layer.queue_redraw()
	_ghost_last_scroll = scroll_beat
	_ghost_last_px = px_per_beat
	_ghost_last_stretch = float(_app.vertical_stretch) if _app != null else 0.0
	_ghost_last_size = size


func _on_chart_changed() -> void:
	_sorted_dirty = true
	_refresh_waveform()
	queue_redraw()


func _on_chart_live_changed() -> void:
	queue_redraw()


func _on_playhead_changed(beat: float) -> void:
	var scrolled := false
	if playback_pinned and playback_view == "pin" and Time.get_ticks_msec() >= _pin_resume_msec:
		# 钉住：播放头固定，谱面连续滚动，不再等它走出视图才翻页。
		var target := pinned_scroll_beat(beat, _plot_visible_beats())
		if not is_equal_approx(target, scroll_beat):
			scroll_beat = target
			scrolled = true
	elif follow_playhead:
		var visible := _plot_visible_beats()
		if beat < scroll_beat - 0.1 or beat > scroll_beat + visible:
			scroll_beat = maxf(0.0, beat - visible * 0.25)
			scrolled = true
	if scrolled:
		scroll_beat = clampf(scroll_beat, 0.0, _scroll_limit())
		queue_redraw()
	var now := Time.get_ticks_msec()
	if now - _last_playhead_redraw >= 16:
		_last_playhead_redraw = now
		if _overlay != null:
			_overlay.queue_redraw()


func _on_selection_changed() -> void:
	queue_redraw()
	if _overlay != null:
		_overlay.queue_redraw()


func _on_tool_changed(_tool: String) -> void:
	if _app != null and _app.chart != null:
		for item in _app.chart.notes:
			if item.type == "seek" and item.seek_pending:
				item.seek_pending = false
	if _pending_hold != null or _pending_path != null:
		_cancel_pending()
	else:
		_pending_path = null
	queue_redraw()
	if _overlay != null:
		_overlay.queue_redraw()


func _on_snap_changed(division: int) -> void:
	snap_division = division
	queue_redraw()


func _on_flow_changed(down: bool) -> void:
	if down != flow_down and _app != null:
		# 方向只翻最后一步映射；这里把播放头所在的屏幕位置留住，
		# 否则一按方向键整页内容会跳到另一侧。
		scroll_beat = flipped_scroll_beat(_app.playhead_beat, scroll_beat, _plot_visible_beats())
	flow_down = down
	clamp_scroll()
	if _flow_button != null and _flow_button.button_pressed != down:
		_flow_button.set_pressed_no_signal(down)
	if _ghost_layer != null:
		_ghost_layer.flow_down = down
		_ghost_layer.queue_redraw()
	queue_redraw()
	if _overlay != null:
		_overlay.queue_redraw()


func _build_flow_button() -> void:
	_flow_button = Button.new()
	_flow_button.name = "FlowToggle"
	_flow_button.text = "从上往下"
	_flow_button.toggle_mode = true
	_flow_button.focus_mode = Control.FOCUS_NONE
	_flow_button.tooltip_text = "开启时新音符向下写入；关闭后整个写谱区上下翻转（时间向上流动）"
	_flow_button.add_theme_font_size_override("font_size", 10)
	_flow_button.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	_flow_button.add_theme_color_override("font_pressed_color", UITheme.BG)
	_flow_button.add_theme_color_override("font_hover_color", UITheme.INK)
	_flow_button.add_theme_stylebox_override("normal", UITheme._box(UITheme.PANEL, UITheme.BORDER, 4, 8, 2))
	_flow_button.add_theme_stylebox_override("hover", UITheme._box(UITheme.RAISED_HOVER, UITheme.BORDER_BRIGHT, 4, 8, 2))
	_flow_button.add_theme_stylebox_override("pressed", UITheme._box(UITheme.ACCENT, UITheme.ACCENT, 4, 8, 2))
	_flow_button.add_theme_stylebox_override("focus", UITheme._box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 4, 0, 0))
	_flow_button.set_anchor(SIDE_LEFT, 1.0)
	_flow_button.set_anchor(SIDE_RIGHT, 1.0)
	_flow_button.set_anchor(SIDE_TOP, 0.0)
	_flow_button.set_anchor(SIDE_BOTTOM, 0.0)
	_flow_button.offset_left = -106.0
	_flow_button.offset_right = -8.0
	_flow_button.offset_top = TOP_MARGIN + 2.0
	_flow_button.offset_bottom = TOP_MARGIN + 22.0
	_flow_button.button_pressed = flow_down
	_flow_button.toggled.connect(_on_flow_toggled)
	add_child(_flow_button)


func _on_flow_toggled(pressed: bool) -> void:
	if _app != null:
		_app.set_time_flows_down(pressed)
		return
	flow_down = pressed
	queue_redraw()
	if _overlay != null:
		_overlay.queue_redraw()


func _division_index_at(position: Vector2) -> int:
	for i in _division_rects.size():
		if _division_rects[i].has_point(position):
			return i
	return -1


func _refresh_waveform() -> void:
	if _app == null or _app.chart == null:
		return
	var chart: Chart = _app.chart
	var path := chart.audio_path
	if path == _waveform_audio_path:
		return
	_waveform_audio_path = path
	_waveform_peaks.clear()
	_waveform_duration = 0.0
	_wave_key = ""
	if path.is_empty() or not path.to_lower().ends_with(".wav"):
		return
	var resolved := path
	if not path.begins_with("res://") and not path.begins_with("user://") and not path.is_absolute_path():
		if _app.chart_path != "":
			resolved = ChartIO.resolve_path(_app.chart_path, path)
	var stream: AudioStream = null
	if resolved.get_extension().to_lower() == "wav":
		var absolute := resolved if resolved.is_absolute_path() else ProjectSettings.globalize_path(resolved)
		stream = AudioStreamWAV.load_from_file(absolute)
	else:
		stream = ChartIO.audio_stream_from_path(resolved)
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		if wav.format != AudioStreamWAV.FORMAT_16_BITS:
			return
		var data := wav.data
		var channels := 2 if wav.stereo else 1
		var frame_bytes := 2 * channels
		var frames := data.size() / frame_bytes
		if frames <= 0:
			return
		var peak_count := 512
		for i in peak_count:
			var start := int(float(i) / peak_count * frames)
			var finish := int(float(i + 1) / peak_count * frames)
			finish = maxi(finish, start + 1)
			var peak := 0.0
			var step := maxi(1, (finish - start) / 32)
			for frame in range(start, mini(finish, frames), step):
				var offset := frame * frame_bytes
				var value := absf(float(data.decode_s16(offset)))
				peak = maxf(peak, value)
			_waveform_peaks.append(clampf(peak / 32768.0, 0.0, 1.0))
		_waveform_duration = wav.get_length()
	# 没有存过音频长度时顺手补上：老谱面打开就能滚到正确的终点。
	if stream != null and stream.get_length() > 0.0:
		var length_ms := stream.get_length() * 1000.0
		if absf(chart.audio_length_ms() - length_ms) > 1.0:
			chart.editor["audio_length_ms"] = length_ms


func _draw() -> void:
	var plot := _plot_rect()
	draw_rect(Rect2(Vector2.ZERO, size), Color("#0E1015"))
	draw_rect(plot, Color("#11141B"))
	_division_rects.clear()
	_draw_waveform(plot)
	_draw_grid(plot)
	_draw_regions(plot)
	_draw_events(plot)
	_draw_notes(plot)
	_draw_legend(plot)


func _draw_waveform(plot: Rect2) -> void:
	if _app == null or _app.chart == null:
		return
	var strip := Rect2(plot.position.x - WAVE_WIDTH - 6.0, plot.position.y, WAVE_WIDTH, plot.size.y)
	draw_rect(strip, Color("#0A0C11"))
	draw_line(Vector2(strip.end.x, strip.position.y), Vector2(strip.end.x, strip.end.y), Color(1, 1, 1, 0.08), 1.0)
	if _waveform_peaks.is_empty() or _waveform_duration <= 0.0:
		draw_line(Vector2(strip.position.x, strip.get_center().y), Vector2(strip.end.x, strip.get_center().y), Color(1, 1, 1, 0.10), 1.0)
		draw_string(UITheme.mono_font(), Vector2(strip.position.x - 2, plot.position.y + 12), "WAVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.22))
		return
	var chart: Chart = _app.chart
	var timing_sig := "%.3f|%d" % [chart.offset_ms, chart.timing.points.size()]
	for point in chart.timing.points:
		timing_sig += "|%.4f" % point.bpm
	# 采样只依赖音频与 BPM 表：滚动/缩放不再让它每帧重建。
	var key := "%s|%.4f|%d|%s" % [
		_waveform_audio_path, _waveform_duration, _waveform_peaks.size(), timing_sig,
	]
	if key != _wave_key:
		_wave_key = key
		_wave_beats = PackedFloat32Array()
		_wave_vals = PackedFloat32Array()
		chart.timing.sort_points()
		var count := mini(800, _waveform_peaks.size())
		for i in count:
			var frac := float(i) / float(maxi(1, count - 1))
			var audio_ms := frac * _waveform_duration * 1000.0
			_wave_beats.append(chart.timing.chart_ms_to_beat(audio_ms + chart.offset_ms))
			_wave_vals.append(_waveform_peaks[mini(_waveform_peaks.size() - 1,
				int(frac * float(_waveform_peaks.size())))])
	var center_x := strip.position.x + strip.size.x * 0.5
	var half := strip.size.x * 0.5 - 2.0
	_wave_right = PackedVector2Array()
	_wave_left = PackedVector2Array()
	for i in _wave_beats.size():
		var y := _beat_to_y(_wave_beats[i])
		if y < plot.position.y or y > plot.end.y:
			continue
		var peak := _wave_vals[i]
		_wave_right.append(Vector2(center_x + peak * half, y))
		_wave_left.append(Vector2(center_x - peak * half, y))
	if _wave_right.size() > 1:
		draw_polyline(_wave_right, Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.42), 1.0, true)
	if _wave_left.size() > 1:
		draw_polyline(_wave_left, Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.26), 1.0, true)


## 全谱 4/4 时的拍线粗细：小节线 2.5、四分线 2.0；其余谱面维持 1.5 / 1.0。
static func beat_line_width(is_bar: bool, emphasize: bool) -> float:
	if not emphasize:
		return 1.5 if is_bar else 1.0
	return 2.5 if is_bar else 2.0


## 4/4 谱的半拍线（小节八分位）单独画红；N 为偶数时细分里才有这一条。
static func is_eighth_offset(offset: float) -> bool:
	return absf(offset - 0.5) < 0.001


## 每条拍号都是 4/4 才算；中途换拍号就整体退回普通拍线。
static func is_uniform_four_four(timing: TimingMap) -> bool:
	for point in timing.points:
		if point.beats_per_bar != 4:
			return false
	return true


## 每几小节强调一次（小节底色与加粗线）。
const BAR_ACCENT_EVERY := 4


func _draw_grid(plot: Rect2) -> void:
	if _app == null or _app.chart == null:
		return
	var font := UITheme.mono_font()
	var chart: Chart = _app.chart if _app != null else null
	if chart == null:
		return
	# Special-angle reference lines: every 30°, with the 90° lines emphasised.
	for i in 13:
		var x := _u_to_x(float(i) / 12.0)
		var major := i % 3 == 0
		var color := Color(1, 1, 1, 0.16 if major else 0.055)
		if i == 0 or i == 12:
			_draw_dashed_vertical(x, plot.position.y, plot.end.y, Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.25))
		else:
			draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), color, 1.0)
		if major:
			var label := "%d°" % (i * 30)
			draw_string(font, Vector2(x - 12, plot.position.y - 7), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.52))
	# 全谱 4/4 时：四条四分线一起加粗，每拍中点（小节八分位）画红线。
	var emphasize := is_uniform_four_four(chart.timing)
	var uniform_bpb := chart.timing.uniform_beats_per_bar()
	var top_beat := scroll_beat
	var bottom_beat := scroll_beat + _plot_visible_beats()
	var limit_beat := chart.end_limit_beat()
	var audio_end := chart.audio_end_beat()
	# 每 4 小节交替一块极淡底色：段落起止不用数拍就能看出来。
	if uniform_bpb > 0 and absf(_effective_px_per_beat() * uniform_bpb) >= 6.0:
		var first_bar := floori(top_beat / uniform_bpb)
		var last_bar := ceili(bottom_beat / uniform_bpb)
		for bar in range(first_bar, last_bar + 1):
			if posmod(int(bar / BAR_ACCENT_EVERY), 2) == 0:
				continue
			var y0 := _beat_to_y(float(bar * uniform_bpb))
			var y1 := _beat_to_y(float((bar + 1) * uniform_bpb))
			draw_rect(Rect2(plot.position.x, minf(y0, y1), plot.size.x, absf(y1 - y0)), Color(1, 1, 1, 0.028))
	# 音频结束后的 4 小节余量压暗：告诉作者再往后没有声音。
	if audio_end > 0.0 and audio_end < limit_beat:
		var y0 := _beat_to_y(maxf(audio_end, top_beat))
		var y1 := _beat_to_y(minf(limit_beat, bottom_beat))
		if absf(y1 - y0) > 0.5:
			draw_rect(Rect2(plot.position.x, minf(y0, y1), plot.size.x, absf(y1 - y0)), Color(0, 0, 0, 0.22))
	var beat_px := _effective_px_per_beat()
	var label_step := 1
	if uniform_bpb > 0:
		var bar_px := beat_px * float(uniform_bpb)
		if bar_px > 0.0:
			while float(label_step) * bar_px < 26.0 and label_step < 64:
				label_step *= 2
	var first_beat := maxi(0, floori(top_beat) - 1)
	var last_beat := ceili(bottom_beat) + 1
	for beat in range(first_beat, last_beat + 1):
		var y := _beat_to_y(float(beat))
		if y < plot.position.y - 2.0 or y > plot.end.y + 2.0:
			continue
		var bpb := chart.timing.beats_per_bar_at(float(beat))
		var is_bar := beat % bpb == 0
		var bar_index := int(beat / bpb) if bpb > 0 else 0
		var accent := is_bar and uniform_bpb > 0 and bar_index % BAR_ACCENT_EVERY == 0
		var width := 3.2 if accent else beat_line_width(is_bar, emphasize)
		# 4/4 谱把拍线提到和红线同一观感，普通谱面维持原来的淡线。
		var beat_alpha := (0.55 if accent else (0.38 if is_bar else 0.30)) if emphasize else (0.17 if is_bar else 0.075)
		var label_alpha := (0.92 if accent else (0.78 if is_bar else 0.52)) if emphasize else (0.62 if is_bar else 0.38)
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), Color(1, 1, 1, beat_alpha), width)
		# 左侧标尺：小节线写小节号，其余拍写「小节内第几拍」，标签太密就只留小节号。
		if is_bar:
			if bar_index % label_step == 0:
				draw_string(font, Vector2(1, y + 4), str(bar_index + 1), HORIZONTAL_ALIGNMENT_RIGHT, 24, 11, Color(1, 1, 1, label_alpha))
		elif beat_px >= 11.0:
			var within := beat % bpb + 1
			draw_string(font, Vector2(6, y + 3), str(within), HORIZONTAL_ALIGNMENT_RIGHT, 19, 9, Color(1, 1, 1, label_alpha * 0.8))
	draw_string(font, Vector2(2, plot.position.y - 8), "小节", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.45))
	if audio_end > 0.0:
		var ay := _beat_to_y(audio_end)
		if ay > plot.position.y - 1.0 and ay < plot.end.y + 1.0:
			draw_dashed_line(Vector2(plot.position.x, ay), Vector2(plot.end.x, ay), Color(UITheme.CORAL.r, UITheme.CORAL.g, UITheme.CORAL.b, 0.65), 1.0, 5.0)
			draw_string(font, Vector2(plot.end.x - 52, ay - 6), "音频结束", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(UITheme.CORAL.r, UITheme.CORAL.g, UITheme.CORAL.b, 0.85))
	var limit_y := _beat_to_y(limit_beat)
	if limit_y > plot.position.y - 1.0 and limit_y < plot.end.y + 1.0:
		draw_line(Vector2(plot.position.x, limit_y), Vector2(plot.end.x, limit_y), Color(1, 1, 1, 0.22), 1.5)
	_draw_beat_subdivisions(plot, emphasize)
	_draw_vertical_lines(plot)
	for point in chart.group_bpm_points_for(chart.current_group):
		if point.beat < top_beat or point.beat > bottom_beat:
			continue
		var y := _beat_to_y(point.beat)
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), Color(UITheme.GOLD.r, UITheme.GOLD.g, UITheme.GOLD.b, 0.55), 1.5)
		var text := "BPM %.1f" % point.bpm
		var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		draw_rect(Rect2(Vector2(plot.position.x + 4, y + 1), Vector2(text_width + 6, 14)), Color(0.05, 0.06, 0.08, 0.85))
		draw_string(font, Vector2(plot.position.x + 7, y + 12), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UITheme.GOLD)


func _draw_beat_subdivisions(plot: Rect2, emphasize: bool) -> void:
	if _app == null:
		return
	var offsets := TimingMap.beat_subdivision_offsets(int(_app.beat_subdivisions))
	if offsets.is_empty():
		return
	var first_beat := floori(scroll_beat)
	var last_beat := ceili(scroll_beat + _visible_beats() + 1.0)
	var points := PackedVector2Array()
	var eighths := PackedVector2Array()
	for beat in range(first_beat, last_beat + 1):
		for offset in offsets:
			var y := _beat_to_y(float(beat) + offset)
			if y < plot.position.y - 0.5 or y > plot.end.y + 0.5:
				continue
			# 4/4 谱的半拍线单独抽出来画红：其余细分线保持极淡。
			if emphasize and is_eighth_offset(offset):
				eighths.append(Vector2(plot.position.x, y))
				eighths.append(Vector2(plot.end.x, y))
				continue
			points.append(Vector2(plot.position.x, y))
			points.append(Vector2(plot.end.x, y))
	if points.size() >= 2:
		draw_multiline(points, Color(1, 1, 1, 0.035), 1.0)
	if eighths.size() >= 2:
		draw_multiline(eighths, Color(0.769, 0.333, 0.29, 0.6), 1.5)


func _draw_vertical_lines(plot: Rect2) -> void:
	if _app == null:
		return
	var offsets := TimingMap.angle_line_offsets(int(_app.angle_divisions))
	if offsets.is_empty():
		return
	var color := Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.09)
	for u in offsets:
		var x := _u_to_x(u)
		draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), color, 1.0)


func _draw_dashed_vertical(x: float, y0: float, y1: float, color: Color) -> void:
	var y := y0
	while y < y1:
		draw_line(Vector2(x, y), Vector2(x, minf(y + 5.0, y1)), color, 1.0)
		y += 10.0


func _draw_regions(plot: Rect2) -> void:
	if _app == null or _app.chart == null:
		return
	var chart: Chart = _app.chart if _app != null else null
	if chart == null:
		return
	for region in chart.regions:
		var color := UITheme.RED if region.kind == "limit" else UITheme.GOLD
		var y0 := _beat_to_y(region.start_beat)
		var y1 := _beat_to_y(region.end_beat)
		var top := minf(y0, y1)
		var height := maxf(2.0, absf(y1 - y0))
		if top + height < plot.position.y or top > plot.end.y:
			continue
		for interval in _u_intervals(region.angle, region.width):
			var x0 := _u_to_x(interval.x)
			var x1 := _u_to_x(interval.y)
			var rect := Rect2(Vector2(x0, top), Vector2(maxf(2.0, x1 - x0), height))
			draw_rect(rect, Color(color.r, color.g, color.b, 0.16))
			draw_rect(rect, Color(color.r, color.g, color.b, 0.55), false, 1.0)
			draw_string(UITheme.mono_font(), Vector2(x0 + 4, top + 12), "LIMIT %d" % region.id, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, color)
		if _is_region_selected(region.id):
			draw_rect(Rect2(Vector2(_u_to_x(0.0), top), Vector2(plot.size.x, height)), Color(1, 1, 1, 0.35), false, 1.0)
			# 宽度手柄：上下两条边上各画一对，抓到任意一条都能改宽度。
			for interval in _u_intervals(region.angle, region.width):
				for y in [top, top + height]:
					for x in [_u_to_x(interval.x), _u_to_x(interval.y)]:
						var handle := Rect2(Vector2(x - 6.0, y - 6.0), Vector2(12.0, 12.0))
						draw_rect(handle, UITheme.INK)
						draw_rect(handle, UITheme.BG, false, 1.5)


func _draw_events(plot: Rect2) -> void:
	if _app == null or _app.chart == null:
		return
	var chart: Chart = _app.chart if _app != null else null
	if chart == null:
		return
	for event in chart.events:
		var y0 := _beat_to_y(event.start_beat)
		var y1 := _beat_to_y(event.end_beat + event.restore_duration)
		var top := minf(y0, y1)
		var height := maxf(2.0, absf(y1 - y0))
		if top + height < plot.position.y or top > plot.end.y:
			continue
		var x0 := _u_to_x(event.target_u0)
		var x1 := _u_to_x(event.target_u1)
		var rect := Rect2(Vector2(x0, top), Vector2(maxf(2.0, x1 - x0), height))
		draw_rect(rect, Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.07))
		draw_rect(rect, Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.30), false, 1.0)
		if height > 14.0:
			draw_string(UITheme.mono_font(), Vector2(x0 + 3, top + 10), "%s → %s" % [event.from_shape, event.to_shape], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.7))


func _draw_notes(plot: Rect2) -> void:
	if _app == null or _app.chart == null:
		return
	var chart: Chart = _app.chart if _app != null else null
	if chart == null:
		return
	var first_beat := scroll_beat - 2.0
	var last_beat := scroll_beat + _visible_beats() + 2.0
	if _drag_mode != "" or _drag_width_note != null:
		# 拖拽时音符会临时改变 beat，直接全量绘制，避免二分索引顺序失效。
		for note in chart.notes:
			var note_end := note.end_beat if note.type in ["hold", "path"] else note.beat
			if note.beat <= last_beat and note_end >= first_beat:
				if note.group_id != chart.current_group:
					_draw_other_group_note(note)
				else:
					_draw_note(note, plot)
	else:
		if _sorted_dirty or _sorted_chart != chart or _sorted_count != chart.notes.size():
			_sorted_chart = chart
			_sorted_count = chart.notes.size()
			_sorted_notes = chart.notes.duplicate()
			_sorted_notes.sort_custom(func(a: Note, b: Note) -> bool: return a.beat < b.beat)
			_sorted_max_duration = 0.0
			for note in _sorted_notes:
				if note.type in ["hold", "path"]:
					_sorted_max_duration = maxf(_sorted_max_duration, note.end_beat - note.beat)
			_sorted_dirty = false
		var search_start := first_beat - _sorted_max_duration
		var low := 0
		var high := _sorted_notes.size()
		while low < high:
			var mid := (low + high) / 2
			if _sorted_notes[mid].beat < search_start:
				low = mid + 1
			else:
				high = mid
		for i in range(low, _sorted_notes.size()):
			var note := _sorted_notes[i]
			if note.beat > last_beat:
				break
			var note_end := note.end_beat if note.type in ["hold", "path"] else note.beat
			if note_end < first_beat:
				continue
			if note.group_id != chart.current_group:
				_draw_other_group_note(note)
			else:
				_draw_note(note, plot)
	if _pending_path != null:
		var head := Vector2(_u_to_x(_pending_path.angle / 360.0), _beat_to_y(_pending_path.beat))
		var tail := Vector2(_u_to_x(_hover_u), _beat_to_y(_hover_beat))
		draw_dashed_line(head, tail, UITheme.CYAN, 1.5, 6.0)


func _draw_note(note: Note, plot: Rect2) -> void:
	match note.type:
		"tap":
			_draw_tap(note)
		"hold":
			_draw_hold(note)
		"path":
			_draw_path(note)
		"seek":
			_draw_seek(note)
		"anchor":
			_draw_anchor(note)
		"bell":
			_draw_bell(note)


## Other groups stay visible in the editor, but only as 25% markers.
func _draw_other_group_note(note: Note) -> void:
	var tint := Color(UITheme.MUTED.r, UITheme.MUTED.g, UITheme.MUTED.b, 0.25)
	var y := _beat_to_y(note.beat)
	match note.type:
		"tap":
			for interval in _u_intervals(note.angle, note.arc_width()):
				draw_line(Vector2(_u_to_x(interval.x), y), Vector2(_u_to_x(interval.y), y), tint, 3.0, true)
		"hold", "path":
			var y2 := _beat_to_y(note.end_beat)
			var head := Vector2(_u_to_x(fposmod(note.angle, 360.0) / 360.0), y)
			var tail_angle := note.tail_angle if note.type == "path" else note.angle
			var tail := Vector2(_u_to_x(fposmod(tail_angle, 360.0) / 360.0), y2)
			draw_line(head, tail, tint, 2.0, true)
			draw_circle(head, 4.0, tint)
		"seek":
			draw_line(Vector2(_u_to_x(0.0), y), Vector2(_u_to_x(1.0), y), tint, 2.0, true)
		"anchor":
			draw_circle(Vector2(_u_to_x(fposmod(note.angle, 360.0) / 360.0), y), 4.0, tint)
		"bell":
			draw_circle(Vector2(_u_to_x(fposmod(note.angle, 360.0) / 360.0), y), 4.0, tint)


func _draw_tap(note: Note) -> void:
	var y := _beat_to_y(note.beat)
	var selected := _is_note_selected(note.id)
	for interval in _u_intervals(note.angle, note.arc_width()):
		var x0 := _u_to_x(interval.x)
		var x1 := _u_to_x(interval.y)
		if x1 - x0 < 1.0:
			continue
		draw_line(Vector2(x0, y), Vector2(x1, y), Color(UITheme.CORAL.r, UITheme.CORAL.g, UITheme.CORAL.b, 0.92), 10.0, true)
		draw_circle(Vector2(x0, y), 5.0, UITheme.CORAL)
		draw_circle(Vector2(x1, y), 5.0, UITheme.CORAL)
		var tick_x := x0 + 5.0
		while tick_x < x1 - 4.0:
			draw_line(Vector2(tick_x, y - 4.0), Vector2(tick_x, y + 4.0), Color(0, 0, 0, 0.24), 1.0)
			tick_x += 7.0
		if selected:
			draw_line(Vector2(x0, y - 7.0), Vector2(x1, y - 7.0), UITheme.INK, 1.0)
			draw_line(Vector2(x0, y + 7.0), Vector2(x1, y + 7.0), UITheme.INK, 1.0)
	var center_x := _u_to_x(fposmod(note.angle, 360.0) / 360.0)
	draw_line(Vector2(center_x, y - 8.0), Vector2(center_x, y + 8.0), UITheme.INK, 2.0)
	draw_circle(Vector2(center_x, y), 2.2, UITheme.INK)
	_draw_width_handles(note, y)
	if _show_type_label(note):
		_draw_type_label("TAP", Vector2(center_x + 8.0, y + 12.0), UITheme.CORAL)


func _draw_hold(note: Note) -> void:
	var y0 := _beat_to_y(note.beat)
	var y1 := _beat_to_y(note.end_beat)
	var x := _u_to_x(fposmod(note.angle, 360.0) / 360.0)
	var selected := _is_note_selected(note.id)
	var color := UITheme.AMBER
	# 弯长条已废除：一律按直 Hold 画实心矩形，宽 = 判定弧宽，长 = 拍长。
	# 旧谱里的 visual_pts 只保留数据，不再参与绘制（否则看不出宽度）。
	# 弧宽跨过 0°/360° 接缝时拆成两段画（以前“x1<x0 就铺满整行”会让压接缝的 Hold 变成满屏长条）。
	var top := minf(y0, y1)
	var height := maxf(2.0, absf(y1 - y0))
	for span in _u_intervals(note.angle, note.arc_width()):
		var x0 := _u_to_x(span.x)
		var x1 := _u_to_x(span.y)
		if x1 - x0 < 1.0:
			continue
		var rect := Rect2(Vector2(x0, top), Vector2(x1 - x0, height))
		draw_rect(rect, Color(color.r, color.g, color.b, 0.32))
		draw_rect(rect, Color(color.r, color.g, color.b, 0.95), false, 1.5)
	_draw_hexagon(Vector2(x, y0), 9.0 if selected else 8.0, color)
	_draw_ring(Vector2(x, y1), 6.0, color)
	_draw_width_handles(note, y0)
	if selected:
		# 尾巴手柄：拖它只改结束拍。
		draw_circle(Vector2(x, y1), 6.0, UITheme.INK)
		draw_arc(Vector2(x, y1), 6.0, 0.0, TAU, 16, UITheme.BG, 1.5, true)
	if _show_type_label(note):
		_draw_type_label("HOLD", Vector2(x + 11.0, y0 + 12.0), color)


func _path_screen_point(note: Note, local: float) -> Vector2:
	## Follow the same local geometry as the 3D Path (trace points included)
	## and project it to the u×time canvas. This keeps a negative tail radius
	## connected to the body instead of ending at the author-facing tail angle.
	var design := note.path_local_at(local)
	var angle := rad_to_deg(atan2(design.y, design.x))
	return Vector2(
		_u_to_x(fposmod(angle, 360.0) / 360.0),
		_beat_to_y(note.beat + local)
	)


func _draw_path(note: Note) -> void:
	var total := maxf(0.001, note.duration())
	var y0 := _beat_to_y(note.beat)
	var y1 := _beat_to_y(note.beat + total)
	var head_local := note.path_local_at(0.0)
	var head_draw_angle := note.angle
	if head_local.length() > 0.0001:
		head_draw_angle = rad_to_deg(atan2(head_local.y, head_local.x))
	var x0 := _path_screen_point(note, 0.0).x
	var tail_local := note.path_tail_local()
	var tail_draw_angle := note.tail_angle
	if tail_local.length() > 0.0001:
		tail_draw_angle = rad_to_deg(atan2(tail_local.y, tail_local.x))
	var x1 := _u_to_x(fposmod(tail_draw_angle, 360.0) / 360.0)
	var selected := _is_note_selected(note.id)
	var tail_color := PATH_CHAIN_BLUE if note.path_next_id >= 0 else UITheme.GOLD
	var head_color := PATH_CHAIN_BLUE if note.path_part > 0 else UITheme.CORAL
	var runs: Array[PackedVector2Array] = []
	var run := PackedVector2Array()
	# 采样点数按屏幕长度走：缩小看时 41 点已经是每像素一个点，白算。
	var steps := clampi(int(absf(y1 - y0) / 5.0) + 2, 8, 41)
	for i in steps:
		var local := total * float(i) / float(steps - 1)
		if note.erased_at(local):
			if run.size() > 1:
				runs.append(run)
			run = PackedVector2Array()
			continue
		run.append(_path_screen_point(note, local))
	if run.size() > 1:
		runs.append(run)
	for piece in runs:
		draw_polyline(piece, Color(0.52, 0.56, 0.64, 0.28), 14.0, true)
		var dashes := PackedVector2Array()
		for i in piece.size() - 1:
			_append_dashes(piece[i], piece[i + 1], 5.0, dashes)
		if dashes.size() > 1:
			draw_multiline(dashes, Color(UITheme.CYAN.r, UITheme.CYAN.g, UITheme.CYAN.b, 0.90), 2.0)
		for fraction in [0.33, 0.66]:
			var sample := _polyline_sample(piece, fraction)
			_draw_arrowhead(sample["point"], sample["direction"], UITheme.CYAN)
	for point in note.visual_pts:
			var local := float(point.get("db", 0.0))
			if note.erased_at(local):
				continue
			draw_circle(_path_screen_point(note, local), 2.5, UITheme.CYAN)
	_draw_width_band(head_draw_angle, note.width, y0, UITheme.CYAN)
	_draw_width_band(tail_draw_angle, note.tail_width, y1, tail_color)
	_draw_star(Vector2(x0, y0), 9.0 if selected else 8.0, head_color)
	_draw_donut(Vector2(x1, y1), 7.0, tail_color)
	if selected:
		# 头/尾都能拖：白圈标出可抓的位置（宽度手柄只在 Tap/Hold 上）。
		draw_arc(Vector2(x0, y0), 11.0, 0.0, TAU, 24, UITheme.INK, 1.5, true)
		draw_arc(Vector2(x1, y1), 11.0, 0.0, TAU, 24, UITheme.INK, 1.5, true)
	if _show_type_label(note):
		_draw_type_label("PATH", Vector2(x0 + 11.0, y0 + 12.0), UITheme.CYAN)


func _append_dashes(a: Vector2, b: Vector2, dash: float, out: PackedVector2Array) -> void:
	var length := a.distance_to(b)
	if length <= 0.01:
		return
	var direction := (b - a) / length
	var cursor := 0.0
	while cursor < length:
		var end := minf(cursor + dash, length)
		out.append(a + direction * cursor)
		out.append(a + direction * end)
		cursor += dash * 2.0


func _draw_donut(point: Vector2, radius: float, color: Color) -> void:
	draw_circle(point, radius, color)
	draw_circle(point, radius * 0.48, UITheme.BG)


func _draw_seek(note: Note) -> void:
	var y := _beat_to_y(note.beat)
	var selected := _is_note_selected(note.id)
	var color := UITheme.INK
	if not note.seek_pending:
		color = UITheme.SEEK_OUT if note.seek_orien == 0 else UITheme.SEEK_IN
	var width := 3.0 if selected else 1.6
	var span := note.seek_width()
	# 窄 Seek 只画自己那段弧；整圈仍是贯穿整行。
	var intervals := _u_intervals(note.angle, span)
	for interval in intervals:
		var x0 := _u_to_x(interval.x)
		var x1 := _u_to_x(interval.y)
		if x1 <= x0 + 0.5:
			continue
		draw_line(Vector2(x0, y), Vector2(x1, y), Color(color.r, color.g, color.b, 0.95), width, true)
		if selected:
			draw_line(Vector2(x0, y), Vector2(x1, y), Color(1, 1, 1, 0.25), width + 2.0, true)
	if note.seek_pending:
		return
	# 外在上、里在下；尖端指向滚轮方向（外 = 上滑）。
	var direction := -1.0 if note.seek_orien == 0 else 1.0
	var count := clampi(int(span / 15.0), 2, 12)
	for interval in intervals:
		var x0 := _u_to_x(interval.x)
		var x1 := _u_to_x(interval.y)
		for i in range(1, count):
			var x := lerpf(x0, x1, float(i) / float(count))
			var tip := Vector2(x, y + 4.5 * direction)
			draw_colored_polygon(PackedVector2Array([
				tip,
				Vector2(x - 2.5, y + 1.2 * direction),
				Vector2(x + 2.5, y + 1.2 * direction),
			]), color)
	_draw_width_handles(note, y)
	if _show_type_label(note):
		var first := intervals[0] if not intervals.is_empty() else Vector2(0.0, 1.0)
		_draw_type_label("SEEK OUT" if note.seek_orien == 0 else "SEEK IN", Vector2(_u_to_x(first.x) + 6.0, y - 6.0), color)


func _draw_anchor(note: Note) -> void:
	var p := Vector2(_u_to_x(fposmod(note.angle, 360.0) / 360.0), _beat_to_y(note.beat))
	# 双押线：只由 id 较小的一颗画一次，连到同拍反向的伙伴。
	var chart: Chart = _app.chart if _app != null else null
	if chart != null:
		var partner := chart.anchor_partner(note)
		if partner != null and note.id < partner.id:
			var q := Vector2(_u_to_x(fposmod(partner.angle, 360.0) / 360.0), _beat_to_y(partner.beat))
			draw_line(p, q, Color(UITheme.VIOLET.r, UITheme.VIOLET.g, UITheme.VIOLET.b, 0.55), 1.2, true)
	var selected := _is_note_selected(note.id)
	_draw_diamond(p, 8.0 if selected else 6.5, UITheme.VIOLET)
	draw_line(p + Vector2(0, -2), p + Vector2(0, 4), UITheme.VIOLET, 1.2, true)
	draw_line(p + Vector2(0, 4), p + Vector2(4, 6), UITheme.VIOLET, 1.2, true)
	if not note.pair_id.is_empty():
		draw_string(UITheme.mono_font(), p + Vector2(9, 12), "A %s" % note.pair_id, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(UITheme.VIOLET.r, UITheme.VIOLET.g, UITheme.VIOLET.b, 0.85))
	if _show_type_label(note):
		_draw_type_label("ANCHOR", p + Vector2(9, -9), UITheme.VIOLET)


func _draw_bell(note: Note) -> void:
	var p := Vector2(_u_to_x(note.center_u), _beat_to_y(note.beat))
	var selected := _is_note_selected(note.id)
	# 时间轴里的金键 = 游戏内那段弧带的俯视图：白壳 + 金色核心 + 圆头。
	var span := _bell_span(note)
	var half := 7.0 if selected else 6.0
	var tip := 4.5
	if selected:
		draw_circle(p, span * 0.5 + 9.0, Color(UITheme.KEY_YELLOW.r, UITheme.KEY_YELLOW.g, UITheme.KEY_YELLOW.b, 0.16))
	_bell_bar(p, span + 4.0, half + 2.0, Color(0, 0, 0, 0.5))
	_bell_bar(p, span, half, Color(1, 1, 1, 0.94))
	_bell_bar(p, span, half * 0.62, UITheme.KEY_YELLOW)
	if selected:
		for x in [p.x - span * 0.5, p.x + span * 0.5]:
			var handle := Rect2(Vector2(x - 6.0, p.y - 6.0), Vector2(12.0, 12.0))
			draw_rect(handle, UITheme.INK)
			draw_rect(handle, UITheme.BG, false, 1.5)


	if _show_type_label(note):
		_draw_type_label("BELL", p + Vector2(span * 0.5 + 10.0, 4.0), UITheme.KEY_YELLOW)


## 金键在时间线上的可见长度（像素）：和检测/绘制共用，手柄才抓得准。
func _bell_span(note: Note) -> float:
	return clampf(12.0 + note.bell_width() * 0.35, 14.0, 64.0)


func _bell_bar(p: Vector2, span: float, half: float, color: Color) -> void:
	draw_rect(Rect2(p + Vector2(-span * 0.5, -half), Vector2(span, half * 2.0)), color)
	draw_circle(p + Vector2(-span * 0.5, 0.0), half, color)
	draw_circle(p + Vector2(span * 0.5, 0.0), half, color)


func _show_type_label(note: Note) -> bool:
	return _app != null and (_app.debug_overlay or _is_note_selected(note.id))


func _draw_type_label(text: String, pos: Vector2, color: Color) -> void:
	draw_string(UITheme.mono_font(), pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(color.r, color.g, color.b, 0.9))


func _draw_star(p: Vector2, r: float, color: Color) -> void:
	var points := _scaled_polygon(_unit_star(), p, r)
	draw_polyline(points, color, 2.0, true)
	draw_circle(p, 1.8, color)


## 单位多边形只算一次：每帧几十个 Star/Hold 图标，重复算三角函数不值。
static var _star_unit := PackedVector2Array()
static var _hex_fill_unit := PackedVector2Array()
static var _hex_outline_unit := PackedVector2Array()


static func _unit_star() -> PackedVector2Array:
	if _star_unit.is_empty():
		for i in 11:
			var angle := -PI * 0.5 + TAU * float(i % 10) / 10.0
			var radius := 1.0 if i % 2 == 0 else 0.45
			_star_unit.append(Vector2(cos(angle), sin(angle)) * radius)
	return _star_unit


static func _unit_hex_fill() -> PackedVector2Array:
	if _hex_fill_unit.is_empty():
		for i in 6:
			var angle := -PI * 0.5 + TAU * float(i) / 6.0
			_hex_fill_unit.append(Vector2(cos(angle), sin(angle)))
	return _hex_fill_unit


static func _unit_hex_outline() -> PackedVector2Array:
	if _hex_outline_unit.is_empty():
		var fill := _unit_hex_fill()
		_hex_outline_unit = fill.duplicate()
		_hex_outline_unit.append(fill[0])
	return _hex_outline_unit


static func _scaled_polygon(unit: PackedVector2Array, p: Vector2, r: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	points.resize(unit.size())
	for i in unit.size():
		points[i] = p + unit[i] * r
	return points


func _draw_hexagon(p: Vector2, r: float, color: Color) -> void:
	draw_colored_polygon(_scaled_polygon(_unit_hex_fill(), p, r), color)
	draw_polyline(_scaled_polygon(_unit_hex_outline(), p, r), UITheme.BG, 1.5, true)
	draw_circle(p, r * 0.35, UITheme.BG)


func _draw_ring(p: Vector2, r: float, color: Color) -> void:
	draw_arc(p, r, 0.0, TAU, 28, color, 2.0, true)
	draw_circle(p, 1.6, color)


func _draw_arrowhead(p: Vector2, direction: Vector2, color: Color) -> void:
	var dir := direction.normalized()
	if dir.length_squared() < 0.1:
		return
	var normal := Vector2(-dir.y, dir.x)
	var points := PackedVector2Array([
		p + dir * 6.0,
		p - dir * 4.0 + normal * 4.0,
		p - dir * 4.0 - normal * 4.0,
	])
	draw_colored_polygon(points, color)


func _polyline_sample(points: PackedVector2Array, fraction: float) -> Dictionary:
	var total := 0.0
	for i in points.size() - 1:
		total += points[i].distance_to(points[i + 1])
	var target := clampf(fraction, 0.0, 1.0) * total
	var cursor := 0.0
	for i in points.size() - 1:
		var segment := points[i].distance_to(points[i + 1])
		if cursor + segment >= target and segment > 0.01:
			var t := (target - cursor) / segment
			return {"point": points[i].lerp(points[i + 1], t), "direction": points[i + 1] - points[i]}
		cursor += segment
	return {"point": points[-1], "direction": points[-1] - points[-2] if points.size() > 1 else Vector2.ZERO}


func _draw_width_band(angle: float, width: float, y: float, color: Color) -> void:
	for interval in _u_intervals(angle, width):
		var x0 := _u_to_x(interval.x)
		var x1 := _u_to_x(interval.y)
		draw_line(Vector2(x0, y), Vector2(x1, y), Color(color.r, color.g, color.b, 0.40), 6.0, true)


## 选中时在弧带两端画方柄：手柄要永远比窄音符宽，否则抓不到。
func _draw_width_handles(note: Note, y: float) -> void:
	if not _is_note_selected(note.id):
		return
	for interval in _u_intervals(note.angle, note.arc_width()):
		for x in [_u_to_x(interval.x), _u_to_x(interval.y)]:
			var rect := Rect2(Vector2(x - 6.0, y - 6.0), Vector2(12.0, 12.0))
			draw_rect(rect, UITheme.INK)
			draw_rect(rect, UITheme.BG, false, 1.5)


func _draw_diamond(p: Vector2, r: float, color: Color) -> void:
	var points := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0), p + Vector2(0, -r)])
	draw_polyline(points, color, 2.0, true)
	draw_circle(p, 2.0, color)


func _u_intervals(angle: float, width: float) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for interval in JudgeMath.interval(angle, width):
		result.append(Vector2(interval.x / 360.0, interval.y / 360.0))
	return result


func _draw_legend(plot: Rect2) -> void:
	if _app == null:
		return
	var y := plot.end.y + 8.0
	var entries := [
		{"type": "tap", "label": "Tap", "color": UITheme.CORAL},
		{"type": "hold", "label": "Hold", "color": UITheme.AMBER},
		{"type": "path", "label": "Path", "color": UITheme.CYAN},
		{"type": "seek", "label": "Seek", "color": UITheme.SEEK_IN},
		{"type": "anchor", "label": "Anchor", "color": UITheme.VIOLET},
		{"type": "bell", "label": "Bell", "color": UITheme.GOLD},
		{"type": "limit", "label": "Limit", "color": UITheme.RED},
	]
	var x := plot.position.x + 4.0
	for entry in entries:
		var color: Color = entry["color"]
		var p := Vector2(x, y)
		match String(entry["type"]):
			"tap":
				draw_line(p + Vector2(-5, 0), p + Vector2(5, 0), color, 4.0, true)
				draw_line(p + Vector2(0, -4), p + Vector2(0, 4), UITheme.INK, 1.0)
			"hold":
				_draw_hexagon(p, 4.0, color)
			"path":
				_draw_star(p, 5.0, color)
			"seek":
				draw_arc(p, 4.0, 0.0, TAU, 18, color, 1.6, true)
				draw_arc(p, 2.2, 0.0, TAU, 14, Color(color.r, color.g, color.b, 0.6), 1.0, true)
			"anchor":
				_draw_diamond(p, 4.0, color)
			"bell":
				draw_arc(p, 4.0, 0.0, TAU, 16, color, 1.5, true)
				draw_circle(p, 1.5, color)
			"limit":
				draw_arc(p, 4.0, -PI * 0.8, PI * 0.2, 12, color, 3.0, true)
		draw_string(UITheme.mono_font(), Vector2(x + 9, y + 4), String(entry["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.48))
		x += 88.0


func _is_note_selected(note_id: int) -> bool:
	return _app != null and _app.selected_notes.has(note_id)


func _is_region_selected(region_id: int) -> bool:
	return _app != null and _app.selected_region_id == region_id


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_pos = event.position
		_hover_u = _x_to_u(event.position.x)
		_hover_beat = _y_to_beat(event.position.y)
		_update_hover_cursor()
		var hover_index := _division_index_at(event.position)
		if hover_index != _division_hover:
			_division_hover = hover_index
			queue_redraw()
		hover_changed.emit(_hover_u, _hover_beat)
		if _clipboard_active:
			_clipboard_mouse_beat = _hover_beat
			_clipboard_mouse_u = _x_to_u(event.position.x)
			_rebuild_ghost()
		if _pending_hold != null:
			var end_beat := _snap_beat_to_subdivision(_y_to_beat(event.position.y), _snap_bypass(event))
			_pending_hold.end_beat = maxf(_pending_hold.beat, end_beat)
			_app.touch_chart()
		if _drag_mode == "note":
			_drag_notes_update(event.position, event)
		elif _drag_mode == "width":
			_drag_width_update(event.position)
		elif _drag_mode == "path_tail":
			_drag_path_tail_update(event.position, event)
		elif _drag_mode == "path_head":
			_drag_path_head_update(event.position, event)
		elif _drag_mode == "limit":
			_drag_red_update(event.position, event)
		elif _drag_mode == "region_body" or _drag_mode == "region_width":
			_drag_region_update(event.position, event)
		elif _drag_mode == "hold_end":
			_drag_hold_update(event.position, event)
		elif _drag_mode == "marquee":
			_update_marquee(event.position)
		elif _drag_mode == "scrub":
			_app.seek(_app.snap_beat(_y_to_beat(event.position.y), event.alt_pressed))
		elif _drag_mode == "right_delete":
			# 动过就当成框选，避免右键拖选时误删。
			if event.position.distance_to(_drag_start) > 5.0:
				_drag_mode = ""
				_right_hit = {}
				_begin_marquee(_drag_start)
		if _drag_mode != "" or _pending_path != null or _pending_hold != null:
			queue_redraw()
		if _overlay != null:
			_overlay.queue_redraw()
		accept_event()
		return
	if event is InputEventMouseButton:
		_mouse_pos = event.position
		_hover_u = _x_to_u(event.position.x)
		_hover_beat = _y_to_beat(event.position.y)
		if _clipboard_active:
			_clipboard_mouse_beat = _hover_beat
			_clipboard_mouse_u = _x_to_u(event.position.x)
			_rebuild_ghost()
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				_handle_wheel(event)
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_RIGHT:
			# 右键单击音符 = 删除；右键按住拖动 = 框选（沿用旧操作）。
			if event.pressed and _drag_mode == "" and _pending_path == null:
				var tail_note := _path_tail_hit(event.position)
				if tail_note != null:
					# Right-clicking a Path tail is the "new part" gesture and
					# must not start a marquee or delete the Path.
					if tail_note.path_next_id < 0:
						_begin_path_part(tail_note)
					else:
						_app.select_note(tail_note.path_next_id)
					accept_event()
					return
				var hit := _hit_test(event.position)
				if hit.is_empty():
					_begin_marquee(event.position)
				else:
					_drag_mode = "right_delete"
					_drag_start = event.position
					_right_hit = hit
			elif not event.pressed and _drag_mode == "right_delete":
				_delete_hit(_right_hit)
				_drag_mode = ""
				_right_hit = {}
				queue_redraw()
				if _overlay != null:
					_overlay.queue_redraw()
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			# Right-click stores the start time; the following left click sets
			# the end time and completes the marquee.
			if _drag_mode == "marquee":
				if event.pressed:
					_update_marquee(event.position)
					_finish_marquee()
					_drag_mode = ""
					_marquee = Rect2()
					queue_redraw()
					if _overlay != null:
						_overlay.queue_redraw()
				accept_event()
				return
			if event.pressed:
				var division_index := _division_index_at(event.position)
				if division_index >= 0:
					if _app != null:
						_app.set_snap_division(GridDivisions.ITEMS[division_index])
					accept_event()
					return
				grab_focus()
				var other_group := _other_group_note_at(event.position)
				if other_group >= 0:
					group_note_hint.emit(other_group, get_global_mouse_position())
					accept_event()
					return
				_on_left_press(event)
			else:
				_on_left_release(event)
			accept_event()
			return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
			_delete_selection()
			accept_event()
		elif event.keycode == KEY_A and event.ctrl_pressed:
			if has_clipboard():
				paste_clipboard(true)
			else:
				_select_visible()
			accept_event()
		elif event.keycode == KEY_ESCAPE:
			_cancel_pending()
			if _app != null:
				_app.set_tool("select")
			if has_clipboard():
				cancel_clipboard()
			accept_event()


func _handle_wheel(event: InputEventMouseButton) -> void:
	if event.ctrl_pressed:
		# Ctrl+wheel edits vertical stretch (clamped by App); it no longer zooms.
		var step := 0.1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -0.1
		if _app != null:
			_app.set_vertical_stretch(_app.vertical_stretch + step)
	else:
		scroll_beat = clampf(scroll_beat + wheel_step(event.button_index == MOUSE_BUTTON_WHEEL_UP, flow_down), 0.0, _scroll_limit())
		if playback_pinned and playback_view == "pin":
			# 滚轮临时脱离钉住：过一会儿自动拉回播放头。
			_pin_resume_msec = Time.get_ticks_msec() + PIN_RESUME_MS
	if _drag_mode == "marquee":
		# Re-anchor the marquee's start screen point after scrolling/stretching;
		# its stored start beat is unchanged.
		_update_marquee(event.position)
	queue_redraw()
	if _overlay != null:
		_overlay.queue_redraw()


## 默认吸到 小节线 × 角度竖线 的交点；按住 Shift 则本次操作完全不吸
## （拍轴与轨道轴一起跳过，红区同样适用）。
static func _snap_bypass(event: InputEventWithModifiers) -> bool:
	return event.shift_pressed


## 滚轮一小格的 beat 位移。规则只有一条：往上滚 = 页面往上走（回到更早的拍），
## 往下滚 = 继续往后。时间轴朝下时 scroll_beat 是顶边拍，要减小；
## 朝上时它是底边拍，要增大。
static func wheel_step(up: bool, flow_down: bool, steps: float = 3.0) -> float:
	return steps if up != flow_down else -steps


func _snap_beat_to_subdivision(raw_beat: float, bypass: bool = false) -> float:
	if bypass or _app == null:
		return raw_beat
	return _app.snap_grid_beat(raw_beat)


func _snap_beat_u(raw_beat: float, raw_u: float, bypass: bool) -> Vector2:
	## 拍轴常开：吸到顶栏「网格 小节线：N」的 1/N 拍线。轨道轴（「角度等分」
	## 的竖线）由顶栏「轨道吸附」开关控制，关掉时角度保持鼠标原样。
	if bypass or _app == null:
		return Vector2(raw_beat, raw_u)
	return Vector2(_app.snap_grid_beat(raw_beat), _app.snap_rail_u(raw_u))


## 角度（度）按轨道开关吸到最近的竖线；0°/360° 是同一个接缝。
func _snap_angle(angle: float, bypass: bool) -> float:
	if bypass or _app == null:
		return angle
	return _app.snap_rail_u(fposmod(angle, 360.0) / 360.0) * 360.0


func _snap_note_placement(screen: Vector2, bypass: bool) -> Vector2:
	return _snap_beat_u(_y_to_beat(screen.y), _x_to_u(screen.x), bypass)


func _snap_dragged_notes(bypass: bool) -> void:
	## Re-apply the grid magnet when the mouse is released. Every dragged note
	## is checked independently, so batch drags keep each note on its nearest
	## line instead of relying on the mouse-up cursor position alone.
	if _app == null or bypass:
		return
	var changed := false
	# Anchor 是刚体：先按 pair 分组，改 beat 之前就把组长定好。
	var anchor_items := {}
	for item in _drag_notes:
		var note: Note = item["note"]
		if note.type == "anchor":
			var key := note.pair_id if not note.pair_id.is_empty() else "id%d" % note.id
			if not anchor_items.has(key):
				anchor_items[key] = []
			anchor_items[key].append(item)
			continue
		if note.lock:
			continue
		var now_u := note.center_u * 360.0 if note.type == "bell" else note.angle
		var moved_beat := absf(note.beat - float(item["beat"])) > 0.000001
		var moved_angle := absf(now_u - float(item["angle"])) > 0.001
		# 只是点了一下没拖动：不动它，免得单击选中就把音符吸走。
		if not moved_beat and not moved_angle:
			continue
		var raw_u := note.center_u if note.type == "bell" else fposmod(note.angle, 360.0) / 360.0
		var snapped := _snap_beat_u(note.beat, raw_u, false)
		# 只回吸真的动过的那个轴：Ctrl 只改时间时别把角度也拽到竖线上。
		if not moved_beat:
			snapped.x = note.beat
		if not moved_angle:
			snapped.y = raw_u
		var beat_delta := snapped.x - note.beat
		var angle_delta := snapped.y * 360.0 - note.angle
		if absf(beat_delta) <= 0.000001 and absf(angle_delta) <= 0.001:
			continue
		note.beat = snapped.x
		if note.type in ["hold", "path"]:
			note.end_beat = maxf(note.beat + 0.25, note.end_beat + beat_delta)
		if note.type == "bell":
			note.angle = fposmod(snapped.y * 360.0, 360.0)
			note.center_u = snapped.y
		elif note.type != "seek":
			note.angle = fposmod(note.angle + angle_delta, 360.0)
			if note.type == "path":
				note.tail_angle = fposmod(note.tail_angle + angle_delta, 360.0)
		changed = true
	if _snap_anchor_pairs(anchor_items):
		changed = true
	if changed:
		_app.touch_chart()


## 一对 Anchor 一起吸：组长落在竖线上，伙伴跟着转同样的角度，两颗的夹角
## （含默认的 180°）保持不变。任一颗锁定就整对不动——锁不能被别的音符绕过。
func _snap_anchor_pairs(groups: Dictionary) -> bool:
	var changed := false
	for key in groups:
		var items: Array = groups[key]
		var leader: Note = items[0]["note"]
		var moved_beat := false
		var moved_angle := false
		var locked := false
		for item in items:
			var note: Note = item["note"]
			if note.lock:
				locked = true
				continue
			if note.id < leader.id:
				leader = note
			if absf(note.beat - float(item["beat"])) > 0.000001:
				moved_beat = true
			if absf(note.angle - float(item["angle"])) > 0.001:
				moved_angle = true
		if locked or (not moved_beat and not moved_angle):
			continue
		if moved_beat:
			var target := _snap_beat_to_subdivision(leader.beat, false)
			if absf(target - leader.beat) > 0.000001:
				for item in items:
					var note: Note = item["note"]
					note.beat = maxf(0.0, target)
				changed = true
		if moved_angle:
			var delta := _snap_angle(leader.angle, false) - leader.angle
			if absf(delta) > 0.001:
				for item in items:
					var note: Note = item["note"]
					note.angle = fposmod(note.angle + delta, 360.0)
				changed = true
	return changed


## 红区松手回吸：起点对齐小节线（时长不变），中心角按轨道开关吸；弧宽 10–359° 不吸。
func _snap_dragged_region(bypass: bool) -> void:
	if _drag_region == null or bypass or _app == null:
		return
	# 只是点了一下红区：没拖动就不回吸。
	if absf(_drag_region.start_beat - _drag_region_start_beat) <= 0.000001 \
			and absf(fposmod(_drag_region.angle - _drag_region_angle + 540.0, 360.0) - 180.0) <= 0.001:
		return
	var duration := maxf(0.25, _drag_region.end_beat - _drag_region.start_beat)
	var start := maxf(0.0, _snap_beat_to_subdivision(_drag_region.start_beat, false))
	_drag_region.start_beat = start
	_drag_region.end_beat = start + duration
	_drag_region.angle = fposmod(_snap_angle(_drag_region.angle, false), 360.0)
	_app.touch_chart()


func _on_left_press(event: InputEventMouseButton) -> void:
	if _app == null:
		return
	var plot := _plot_rect()
	if event.position.x > plot.end.x + 1.0:
		return
	var beat: float = _app.snap_beat(_y_to_beat(event.position.y), event.alt_pressed)
	# 顶部标尺那一行没有对应的拍，按到它就算了视口最上面那一拍，免得跳到奇怪的位置。
	beat = maxf(beat, scroll_beat)
	var u := _x_to_u(event.position.x)
	if event.position.x < plot.position.x - 4.0 or event.position.y < plot.position.y:
		# 左侧刻度栏和顶部标尺：按下去就跳转，并继续跟着拖动走 scrub。
		if event.shift_pressed and not _app.selected_notes.is_empty():
			_app.begin_edit()
			for note in _app.get_selected_notes():
				note.beat = beat
				if note.type in ["hold", "path"]:
					note.end_beat = maxf(note.end_beat, note.beat + 0.25)
			_app.finish_edit()
		else:
			_drag_mode = "scrub"
			_app.seek(beat)
		return
	# A pending hold consumes the next left click as its end time, before the
	# overlap guard can select another note.
	if _pending_hold != null:
		var end_beat := _snap_beat_to_subdivision(_y_to_beat(event.position.y), _snap_bypass(event))
		_finish_pending_hold(end_beat)
		return
	# 复制后谱面上有半透明幽灵：点一下就把整段（含 Path 链）落在点到的拍上。
	if has_clipboard():
		var drop := _snap_note_placement(event.position, _snap_bypass(event))
		_paste_at(drop.x, false, drop.y)
		return
	# Ctrl is a selection modifier across all tools: toggle the clicked note
	# and suppress every placement action while it is held. A pending Path is
	# exempt because its second click is the tail-placement step.
	if _pending_path == null and event.ctrl_pressed:
		var ctrl_hit := _hit_test(event.position)
		if String(ctrl_hit.get("kind", "")) == "note":
			_app.toggle_note_selection(int(ctrl_hit["id"]))
		return
	# When a note tool is active, clicking an existing note selects it instead
	# of stacking a new note on top.
	if _pending_path == null and _app.tool in NOTE_TOOLS:
		var hit := _hit_test(event.position)
		if String(hit.get("kind", "")) == "note":
			_app.select_note(int(hit["id"]), event.shift_pressed)
			_begin_note_drag(event.position)
			return
	# 红区（limit）也算落点对象：按下那一下就要按小节线 + 轨道吸附。
	if _app.tool in NOTE_TOOLS or _app.tool == "limit":
		var placement := _snap_note_placement(event.position, _snap_bypass(event))
		beat = placement.x
		u = placement.y
	match _app.tool:
		"select":
			_select_press(event)
		"tap", "anchor", "bell":
			_create_simple(_app.tool, beat, u)
		"hold":
			_create_hold(beat, u)
		"path":
			_place_path(beat, u)
		"seek":
			_create_seek_at(beat, u)
		"limit":
			_begin_red(beat, u)
		"boundary":
			notice.emit("边界形状在左侧预览中拖拽控制点；双击分段可拆分。", "info")
		"event":
			_create_event_at(beat, u)


func _on_left_release(event: InputEventMouseButton) -> void:
	if _app == null:
		return
	if _drag_mode == "note":
		_snap_dragged_notes(_snap_bypass(event))
	elif _drag_mode in ["limit", "region_body"]:
		_snap_dragged_region(_snap_bypass(event))
	if _drag_mode in ["note", "width", "limit", "hold_end", "path_tail", "path_head", "region_body", "region_width"]:
		_app.finish_edit()
	if _drag_mode == "marquee":
		_finish_marquee()
		_marquee = Rect2()
	_drag_mode = ""
	_drag_notes.clear()
	_drag_region = null
	_drag_width_note = null
	_drag_tail_note = null
	_drag_head_note = null
	queue_redraw()
	if _overlay != null:
		_overlay.queue_redraw()


func _begin_marquee(position: Vector2) -> void:
	if _app == null:
		return
	grab_focus()
	_drag_mode = "marquee"
	_drag_start = position
	_marquee_start_beat = _y_to_beat(position.y)
	_marquee_start_u = _x_to_u(position.x)
	_marquee_end_beat = _marquee_start_beat
	_marquee_end_u = _marquee_start_u
	_marquee = Rect2(position, Vector2.ZERO)
	queue_redraw()
	if _overlay != null:
		_overlay.queue_redraw()


func _update_marquee(current: Vector2) -> void:
	_marquee_end_beat = _y_to_beat(current.y)
	_marquee_end_u = _x_to_u(current.x)
	# The start is anchored to its beat, not to a screen pixel: scrolling or
	# stretching between the right-click and the left-click keeps it fixed.
	var start := Vector2(_u_to_x(_marquee_start_u), _beat_to_y(_marquee_start_beat))
	_marquee = Rect2(start, current - start).abs()


func _select_press(event: InputEventMouseButton) -> void:
	var hit := _hit_test(event.position)
	if hit.is_empty():
		if event.ctrl_pressed:
			return
		if event.double_click:
			_app.seek(_app.snap_beat(_y_to_beat(event.position.y)))
			return
		_app.clear_selection()
		return
	match hit["kind"]:
		"note":
			var note_id := int(hit["id"])
			if event.ctrl_pressed:
				_app.toggle_note_selection(note_id)
				return
			_app.select_note(note_id, event.shift_pressed)
			if hit.get("part", "") == "width":
				_begin_width_drag(note_id, event.position)
			elif hit.get("part", "") == "head":
				_begin_head_drag(note_id, event.position)
			elif hit.get("part", "") == "tail":
				_begin_tail_drag(note_id, event.position)
			else:
				_begin_note_drag(event.position)
		"region":
			var region_id := int(hit["id"])
			_app.select_region(region_id)
			_begin_region_drag(region_id, String(hit.get("part", "body")), event.position)
		"event":
			_app.select_event(String(hit["id"]))


func _other_group_note_at(pos: Vector2) -> int:
	if _app == null or _app.chart == null:
		return -1
	var chart: Chart = _app.chart
	for note in chart.notes:
		if note.group_id == chart.current_group:
			continue
		for item in _note_positions(note):
			if (item["point"] as Vector2).distance_to(pos) <= 14.0:
				return note.group_id
		if note.type == "seek" and absf(pos.y - _beat_to_y(note.beat)) <= 8.0:
			return note.group_id
	return -1


## 命中检测：音符优先，取「离指针最近的部件」；红区/事件只在没点到音符时响应。
## 先按指针所在行做纵向剔除——1500 音符的谱面逐个算投影会让按下延迟 20–50ms。
func _hit_test(pos: Vector2) -> Dictionary:
	var chart: Chart = _app.chart
	if chart == null:
		return {}
	var best := {}
	var best_distance := 12.0
	for note in chart.notes:
		if note.group_id != chart.current_group:
			continue
		if _note_off_row(note, pos):
			continue
		var hit := _note_hit(note, pos)
		if hit.is_empty():
			continue
		var distance := float(hit["distance"])
		if distance <= best_distance:
			best_distance = distance
			best = {"kind": "note", "id": note.id, "part": String(hit["part"])}
	if not best.is_empty():
		return best
	for region in chart.regions:
		var y0 := _beat_to_y(region.start_beat)
		var y1 := _beat_to_y(region.end_beat)
		if pos.y < minf(y0, y1) or pos.y > maxf(y0, y1):
			continue
		if not JudgeMath.in_arc(_x_to_u(pos.x) * 360.0, region.angle, region.width):
			continue
		var part := "body"
		if _is_region_selected(region.id):
			for interval in _u_intervals(region.angle, region.width):
				if absf(pos.x - _u_to_x(interval.x)) <= 7.0 or absf(pos.x - _u_to_x(interval.y)) <= 7.0:
					part = "width"
					break
		return {"kind": "region", "id": region.id, "part": part}
	for event in chart.events:
		var y0 := _beat_to_y(event.start_beat)
		var y1 := _beat_to_y(event.end_beat)
		if pos.y < minf(y0, y1) or pos.y > maxf(y0, y1):
			continue
		var u := _x_to_u(pos.x)
		if u >= event.target_u0 and u <= event.target_u1:
			return {"kind": "event", "id": event.id}
	return {}


## 纵向剔除：指针离这一行超过 14px 就不可能有命中（最长判定半径 12px + 余量）。
func _note_off_row(note: Note, pos: Vector2) -> bool:
	var head_y := _beat_to_y(note.beat)
	if note.type in ["hold", "path"]:
		var tail_y := _beat_to_y(note.end_beat)
		return pos.y < minf(head_y, tail_y) - 14.0 or pos.y > maxf(head_y, tail_y) + 14.0
	return absf(pos.y - head_y) > 14.0


## 单个音符命中了哪个部件、离指针多远。空字典 = 没点到。
func _note_hit(note: Note, pos: Vector2) -> Dictionary:
	match note.type:
		"anchor":
			var p := Vector2(_u_to_x(fposmod(note.angle, 360.0) / 360.0), _beat_to_y(note.beat))
			var distance := p.distance_to(pos)
			return {"part": "body", "distance": distance} if distance <= 11.0 else {}
		"bell":
			var center := Vector2(_u_to_x(note.center_u), _beat_to_y(note.beat))
			var half := _bell_span(note) * 0.5
			if absf(pos.y - center.y) <= 8.0 and _is_note_selected(note.id):
				var edge := minf(absf(pos.x - (center.x - half)), absf(pos.x - (center.x + half)))
				if edge <= 8.0:
					return {"part": "width", "distance": edge}
			if absf(pos.y - center.y) <= 8.0 and absf(pos.x - center.x) <= half + 6.0:
				return {"part": "body", "distance": absf(pos.y - center.y)}
			return {}
		"tap":
			var edge := _width_edge_hit(note, pos)
			if not edge.is_empty():
				return {"part": "width", "distance": float(edge["distance"])}
			var y := _beat_to_y(note.beat)
			var in_row := absf(pos.y - y) <= 7.0
			if in_row and JudgeMath.in_arc(_x_to_u(pos.x) * 360.0, note.angle, note.arc_width()):
				return {"part": "body", "distance": absf(pos.y - y)}
			var head := Vector2(_u_to_x(fposmod(note.angle, 360.0) / 360.0), y)
			var distance := head.distance_to(pos)
			return {"part": "head", "distance": distance} if distance <= 12.0 else {}
		"hold":
			var y0 := _beat_to_y(note.beat)
			var y1 := _beat_to_y(note.end_beat)
			var body_x := _u_to_x(fposmod(note.angle, 360.0) / 360.0)
			if absf(pos.x - body_x) <= 9.0 and absf(pos.y - y1) <= 7.0:
				return {"part": "tail", "distance": absf(pos.y - y1)}
			var edge := _width_edge_hit(note, pos)
			if not edge.is_empty():
				return {"part": "width", "distance": float(edge["distance"])}
			if absf(pos.y - y0) <= 7.0 and JudgeMath.in_arc(_x_to_u(pos.x) * 360.0, note.angle, note.arc_width()):
				return {"part": "body", "distance": absf(pos.y - y0)}
			if pos.y >= minf(y0, y1) - 4 and pos.y <= maxf(y0, y1) + 4 and absf(pos.x - body_x) < 8.0:
				return {"part": "body", "distance": absf(pos.x - body_x)}
			var head := Vector2(body_x, y0)
			var head_distance := head.distance_to(pos)
			return {"part": "body", "distance": head_distance} if head_distance <= 12.0 else {}
		"path":
			var tail := _path_tail_screen_point(note)
			var tail_distance := tail.distance_to(pos)
			if tail_distance <= 10.0:
				return {"part": "tail", "distance": tail_distance}
			var head := _path_screen_point(note, 0.0)
			var head_distance := head.distance_to(pos)
			if note.path_part == 0 and head_distance <= 10.0:
				return {"part": "head", "distance": head_distance}
			var body := _path_body_distance(note, pos)
			if body <= PATH_HIT_RADIUS:
				return {"part": "body", "distance": body}
			return {}
		"seek":
			var y := _beat_to_y(note.beat)
			if absf(pos.y - y) > 8.0:
				return {}
			# 端点手柄只在选中时生效（和 Tap / Hold 一致）。
			if _is_note_selected(note.id):
				var edge_distance := INF
				for interval in _u_intervals(note.angle, note.seek_width()):
					edge_distance = minf(edge_distance,
						minf(absf(pos.x - _u_to_x(interval.x)), absf(pos.x - _u_to_x(interval.y))))
				if edge_distance >= 9.0:
					edge_distance = INF
				if is_finite(edge_distance):
					return {"part": "width", "distance": edge_distance}
			for interval in _u_intervals(note.angle, note.seek_width()):
				if pos.x >= _u_to_x(interval.x) - 4.0 and pos.x <= _u_to_x(interval.y) + 4.0:
					return {"part": "body", "distance": absf(pos.y - y)}
			return {}
	return {}


func _path_tail_screen_point(note: Note) -> Vector2:
	var tail_local := note.path_tail_local()
	var tail_angle := note.tail_angle
	if tail_local.length() > 0.0001:
		tail_angle = rad_to_deg(atan2(tail_local.y, tail_local.x))
	return Vector2(_u_to_x(fposmod(tail_angle, 360.0) / 360.0), _beat_to_y(note.end_beat))


## 点到 Path 轨迹的最短距离（擦除段不算）。
func _path_body_distance(note: Note, pos: Vector2) -> float:
	var total := maxf(0.001, note.duration())
	var run: Array[Vector2] = []
	var best := INF
	for i in 41:
		var local := total * float(i) / 40.0
		if note.erased_at(local):
			best = minf(best, _path_run_distance(run, pos))
			run = []
			continue
		run.append(_path_screen_point(note, local))
	return minf(best, _path_run_distance(run, pos))


func _path_run_distance(run: Array[Vector2], pos: Vector2) -> float:
	if run.is_empty():
		return INF
	return JudgeMath.trace_distance(pos, run)


func _width_edge_hit(note: Note, pos: Vector2) -> Dictionary:
	# 手柄只在选中时画出来；没选中时抓到端点应该是「选中并整条拖动」，不是偷偷改宽度。
	if not _is_note_selected(note.id):
		return {}
	var y := _beat_to_y(note.beat)
	if absf(pos.y - y) > 7.0:
		return {}
	var center := fposmod(note.angle, 360.0) / 360.0
	var half := note.arc_width() / 720.0
	var left := fposmod(center - half + 1.0, 1.0)
	var right := fposmod(center + half, 1.0)
	var distance := minf(absf(pos.x - _u_to_x(left)), absf(pos.x - _u_to_x(right)))
	if distance >= 9.0:
		return {}
	return {"kind": "note", "id": note.id, "part": "width", "distance": distance}


## 手柄只在选中时画出来，但指针靠近也要变成左右缩放光标。
func _update_hover_cursor() -> void:
	var shape := Control.CURSOR_ARROW
	if _app != null and _drag_mode == "":
		for note in _app.get_selected_notes():
			if note.type == "bell":
				var center := Vector2(_u_to_x(note.center_u), _beat_to_y(note.beat))
				var half := _bell_span(note) * 0.5
				var edge := minf(absf(_mouse_pos.x - (center.x - half)), absf(_mouse_pos.x - (center.x + half)))
				if absf(_mouse_pos.y - center.y) <= 8.0 and edge <= 8.0:
					shape = Control.CURSOR_HSIZE
					break
			elif note.type in ["tap", "hold"] and not _width_edge_hit(note, _mouse_pos).is_empty():
				shape = Control.CURSOR_HSIZE
				break
		if shape == Control.CURSOR_ARROW and _app.selected_region_id >= 0 and _app.chart != null:
			for region in _app.chart.regions:
				if region.id != _app.selected_region_id:
					continue
				var y0 := _beat_to_y(region.start_beat)
				var y1 := _beat_to_y(region.end_beat)
				if _mouse_pos.y < minf(y0, y1) - 4.0 or _mouse_pos.y > maxf(y0, y1) + 4.0:
					continue
				for interval in _u_intervals(region.angle, region.width):
					if absf(_mouse_pos.x - _u_to_x(interval.x)) <= 7.0 or absf(_mouse_pos.x - _u_to_x(interval.y)) <= 7.0:
						shape = Control.CURSOR_HSIZE
						break
	mouse_default_cursor_shape = shape


func _note_positions(note: Note) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	match note.type:
		"path":
			result.append({"point": _path_screen_point(note, 0.0), "part": "head"})
			result.append({"point": _path_tail_screen_point(note), "part": "tail"})
		"bell":
			result.append({"point": Vector2(_u_to_x(note.center_u), _beat_to_y(note.beat)), "part": "head"})
		"tap":
			result.append({"point": Vector2(_u_to_x(fposmod(note.angle, 360.0) / 360.0), _beat_to_y(note.beat)), "part": "head"})
		_:
			result.append({"point": Vector2(_u_to_x(fposmod(note.angle, 360.0) / 360.0), _beat_to_y(note.beat)), "part": "head"})
	return result


func _begin_note_drag(screen: Vector2) -> void:
	_drag_mode = "note"
	_drag_start = screen
	_drag_start_beat = _y_to_beat(screen.y)
	_drag_start_u = _x_to_u(screen.x)
	_drag_notes.clear()
	# Anchor 是双押配置：拖一颗就整对一起动，保持同拍 + 180° 反向。
	for note in _app.with_anchor_partners(_app.get_selected_notes()):
		_drag_notes.append({
			"note": note,
			"beat": note.beat,
			# Bell 的实际位置在 center_u，angle 可能还是旧值。
			"angle": note.center_u * 360.0 if note.type == "bell" else note.angle,
			"end": note.end_beat,
			"tail": note.tail_angle,
			"center": note.center_u,
		})
	_app.begin_edit()


func _drag_notes_update(screen: Vector2, event: InputEventMouseMotion) -> void:
	var beat := _y_to_beat(screen.y)
	var u := _x_to_u(screen.x)
	var delta_beat := beat - _drag_start_beat
	if event.shift_pressed:
		delta_beat = 0.0
	var delta_u := u - _drag_start_u
	if event.ctrl_pressed:
		delta_u = 0.0
	for item in _drag_notes:
		var note: Note = item["note"]
		if note.lock:
			continue
		# 拖动过程跟手（不吸），松手时 _snap_dragged_notes 一次性回吸到格点。
		var new_beat := maxf(0.0, float(item["beat"]) + delta_beat)
		var new_angle := fposmod(float(item["angle"]) + delta_u * 360.0, 360.0)
		var beat_delta := new_beat - note.beat
		note.beat = new_beat
		note.angle = new_angle
		if note.type == "bell":
			note.center_u = new_angle / 360.0
		if note.type in ["hold", "path"]:
			note.end_beat = maxf(note.beat + 0.25, float(item["end"]) + beat_delta)
		if note.type == "path":
			note.tail_angle = fposmod(float(item["tail"]) + delta_u * 360.0, 360.0)
	_app.touch_chart()


func _drag_hold_update(screen: Vector2, event: InputEventMouseMotion) -> void:
	if _drag_notes.is_empty():
		return
	var note: Note = _drag_notes[0]["note"]
	var beat: float = _snap_beat_to_subdivision(_y_to_beat(screen.y), _snap_bypass(event))
	note.end_beat = maxf(note.beat + 0.25, beat)
	_app.touch_chart()


## 抓尾巴：Hold 只拉长短；Path 横向改尾角、纵向改结束拍。
func _begin_tail_drag(note_id: int, screen: Vector2) -> void:
	var note := _find_note(note_id)
	if note == null:
		return
	_drag_tail_note = note
	_drag_tail_start = note.tail_angle
	_drag_tail_origin = _x_to_u(screen.x)
	if note.type == "hold":
		_drag_mode = "hold_end"
		_drag_notes = [{"note": note}]
	else:
		_drag_mode = "path_tail"
	_app.begin_edit()


func _drag_path_tail_update(screen: Vector2, event: InputEventMouseMotion) -> void:
	if _drag_tail_note == null:
		return
	_drag_tail_note.tail_angle = fposmod(_snap_angle(
		_drag_tail_start + (_x_to_u(screen.x) - _drag_tail_origin) * 360.0, _snap_bypass(event)), 360.0)
	_drag_tail_note.end_beat = maxf(_drag_tail_note.beat + 0.25,
		_snap_beat_to_subdivision(_y_to_beat(screen.y), _snap_bypass(event)))
	_app.touch_chart()


## Path 头：横向改头角、纵向改起始拍；头永远贴在环上（半径 1.0）。
## 头与尾都不做宽度手柄——Path 的宽度是判定带，继续走检查器。
func _begin_head_drag(note_id: int, screen: Vector2) -> void:
	var note := _find_note(note_id)
	if note == null:
		return
	if note.type != "path" or note.path_part > 0:
		# Anchor / Bell 没有「头」这个概念：按住本体就是拖位置。
		_begin_note_drag(screen)
		return
	_drag_head_note = note
	_drag_head_start = note.angle
	_drag_head_origin = _x_to_u(screen.x)
	_drag_mode = "path_head"
	_app.begin_edit()


func _drag_path_head_update(screen: Vector2, event: InputEventMouseMotion) -> void:
	if _drag_head_note == null:
		return
	var note := _drag_head_note
	note.angle = fposmod(_snap_angle(
		_drag_head_start + (_x_to_u(screen.x) - _drag_head_origin) * 360.0, _snap_bypass(event)), 360.0)
	note.beat = path_head_beat(
		_snap_beat_to_subdivision(_y_to_beat(screen.y), _snap_bypass(event)), note.end_beat)
	if note.path_controls_set:
		# 参数化 Path 的 head 由 angle 推出来，重建一次才看得到。
		note.set_path_axis(note.path_axis)
	elif not note.trace_pts.is_empty():
		# 手绘 Path：只挪头那一点，中间形状不动。
		note.trace_pts[0]["x"] = cos(deg_to_rad(note.angle))
		note.trace_pts[0]["y"] = sin(deg_to_rad(note.angle))
	_app.touch_chart()


## 头不能越过尾巴：至少留 0.25 拍。
static func path_head_beat(desired: float, end_beat: float) -> float:
	return clampf(desired, 0.0, maxf(0.0, end_beat - 0.25))


func _begin_width_drag(note_id: int, screen: Vector2) -> void:
	var note := _find_note(note_id)
	if note == null:
		return
	_drag_mode = "width"
	_drag_width_note = note
	# Bell 的位置在 center_u（检查器只改它，angle 可能是旧值），左右手柄要按画出来的中心算。
	var center_u := note.center_u if note.type == "bell" else fposmod(note.angle, 360.0) / 360.0
	var center_x := _u_to_x(center_u)
	_drag_width_side = -1 if screen.x < center_x else 1
	_drag_width_origin = _x_to_u(screen.x)
	_drag_width_start = note.width
	_app.begin_edit()


func _drag_width_update(screen: Vector2) -> void:
	if _drag_width_note == null:
		return
	var u := _x_to_u(screen.x)
	var delta_u := u - _drag_width_origin
	var width := 0.0
	if _drag_width_note.type == "bell":
		width = dragged_bell_width(_drag_width_start, delta_u, _drag_width_side)
	elif _drag_width_note.type == "seek":
		width = dragged_seek_width(_drag_width_start, delta_u, _drag_width_side)
	else:
		width = dragged_width(
			_drag_width_start, delta_u, _drag_width_side, _drag_width_note.length_ratio())
	_drag_width_note.width = width
	_app.touch_chart()


## 画出来的是 width × length_ratio，鼠标位移要换算回 width，边缘才跟手；
## 上限也按画出来的弧宽算，否则 sized Tap ×1.5 会推出 540° 的非法宽度。
static func dragged_width(start_width: float, delta_u: float, side: int, length_ratio: float) -> float:
	var visual := maxf(0.05, length_ratio)
	return clampf(start_width + delta_u * 360.0 * 2.0 * float(side) / visual, 5.0, 360.0 / visual)


func _create_simple(type: String, beat: float, u: float) -> void:
	var chart: Chart = _app.chart
	if chart == null:
		return
	var added: Array[Note] = []
	if type == "anchor":
		# Anchor 是双押配置：一次放两颗同拍反向的锚点。
		added = chart.make_anchor_pair(beat, u * 360.0)
	else:
		var note := Note.new(type, beat, u * 360.0, 60.0)
		note.id = chart.next_note_id()
		if type == "bell":
			note.width = 0.0
			note.center_u = u
			note.radius = 26.0
		added = [note]
	_app.begin_edit()
	for item in added:
		item.group_id = chart.current_group
		chart.notes.append(item)
	chart.reassign_note_ids()
	_app.finish_edit()
	_app.select_note(added[0].id)


func _create_hold(beat: float, u: float) -> void:
	var chart: Chart = _app.chart
	if chart == null:
		return
	var note := Note.new("hold", beat, u * 360.0, 60.0)
	note.id = chart.next_note_id()
	note.group_id = chart.current_group
	note.end_beat = beat + 1.0
	_app.begin_edit()
	chart.notes.append(note)
	chart.reassign_note_ids()
	_app.select_note(note.id)
	_pending_hold = note
	notice.emit("Hold：移动鼠标到结束拍并再次左键单击；Esc 取消。", "info")


func _finish_pending_hold(end_beat: float) -> void:
	if _pending_hold == null:
		return
	var note := _pending_hold
	var start := note.beat
	var finish := maxf(0.0, end_beat)
	if finish < start:
		# The author dragged upward/backwards: the second click becomes the
		# new start, the first click becomes the end.
		note.beat = finish
		note.end_beat = start
	else:
		note.end_beat = finish
	if note.end_beat - note.beat < 0.25:
		note.end_beat = note.beat + 0.25
	_pending_hold = null
	_app.finish_edit()
	_app.select_note(note.id)
	queue_redraw()


func _begin_path_part(parent: Note) -> void:
	var chart: Chart = _app.chart
	if chart == null or parent == null:
		return
	_app.set_tool("path")
	var head := parent.path_tail_local()
	var beat := parent.end_beat
	var angle := rad_to_deg(atan2(head.y, head.x))
	var note := Note.new("path", beat, angle, parent.width)
	note.id = chart.next_note_id()
	note.group_id = parent.group_id
	note.end_beat = beat + 1.0
	note.tail_angle = angle
	note.tail_width = parent.tail_width
	note.tolerance = parent.tolerance
	note.samples_per_beat = parent.samples_per_beat
	note.path_part = parent.path_part + 1
	note.path_prev_id = parent.id
	note.path_head_local = head
	note.path_centrifuge = 0.72
	note.path_axis = 0.0
	note.generate_path_shape()
	_app.begin_edit()
	chart.notes.append(note)
	chart.reassign_note_ids()
	_app.select_note(note.id)
	_pending_path = note
	_pending_path_parent = parent
	notice.emit("Path part%d：左键放置本段尾部；Esc 取消。" % note.path_part, "info")


func _place_path(beat: float, u: float) -> void:
	var chart: Chart = _app.chart
	if chart == null:
		return
	if _pending_path == null:
		var note := Note.new("path", beat, u * 360.0, 60.0)
		note.id = chart.next_note_id()
		note.group_id = chart.current_group
		note.end_beat = beat + 1.0
		note.tail_angle = u * 360.0
		note.tail_width = 45.0
		note.tolerance = 0.24
		note.samples_per_beat = 4.0
		note.path_centrifuge = 0.72
		note.path_axis = 0.0
		note.generate_path_shape()
		_app.begin_edit()
		chart.notes.append(note)
		chart.reassign_note_ids()
		_app.finish_edit()
		_app.select_note(note.id)
		_pending_path = note
		_pending_path_parent = null
		notice.emit("Path：再点一次放置尾部；Esc 取消。", "info")
	else:
		_app.begin_edit()
		_pending_path.end_beat = maxf(_pending_path.beat + 0.25, beat)
		_pending_path.tail_angle = u * 360.0
		if _pending_path_parent != null:
			_pending_path.path_head_local = _pending_path_parent.path_tail_local()
			_pending_path.path_prev_id = _pending_path_parent.id
			_pending_path_parent.path_next_id = _pending_path.id
		_pending_path.generate_path_shape()
		_app.finish_edit()
		# Keep the Path tool active so the note-selection block stays on Path
		# after choosing the tail; Esc is the explicit way to deselect it.
		_pending_path = null
		_pending_path_parent = null


func _create_seek_at(beat: float, u: float = 0.0) -> void:
	var chart: Chart = _app.chart
	if chart == null:
		return
	for item in chart.notes:
		if item.type == "seek" and item.seek_pending:
			item.seek_pending = false
	# 整圈 Seek 的角无所谓；窄弧从放下去的位置开始，之后再拖两端。
	var note := Note.new("seek", beat, fposmod(u * 360.0, 360.0), 360.0)
	note.id = chart.next_note_id()
	note.group_id = chart.current_group
	note.end_beat = beat
	note.seek_orien = 0
	note.seek_pending = true
	_app.begin_edit()
	chart.notes.append(note)
	chart.reassign_note_ids()
	_app.finish_edit()
	_app.select_note(note.id)
	notice.emit("Seek：按 W 朝里 / S 朝外；放置期间 W/S 快捷键被屏蔽。", "info")


func has_pending_seek() -> bool:
	if _app == null or _app.chart == null:
		return false
	for item in _app.chart.notes:
		if item.type == "seek" and item.seek_pending:
			return true
	return false


func set_pending_seek_orientation(orien: int) -> void:
	if _app == null or _app.chart == null:
		return
	for item in _app.chart.notes:
		if item.type == "seek" and item.seek_pending:
			_app.begin_edit()
			item.seek_orien = 1 if orien == 1 else 0
			item.seek_pending = false
			_app.finish_edit()
			_app.select_note(item.id)
			queue_redraw()
			if _overlay != null:
				_overlay.queue_redraw()
			return


## 已存在的红区：身体拖角度 + 时间窗，左右边缘拖宽度。
func _begin_region_drag(region_id: int, part: String, screen: Vector2) -> void:
	var chart: Chart = _app.chart
	if chart == null:
		return
	var region: Region = null
	for item in chart.regions:
		if item.id == region_id:
			region = item
			break
	if region == null:
		return
	_drag_region = region
	_drag_start_beat = _y_to_beat(screen.y)
	_drag_start_u = _x_to_u(screen.x)
	_drag_region_start_beat = region.start_beat
	_drag_region_end_beat = region.end_beat
	_drag_region_angle = region.angle
	_drag_region_width = region.width
	if part == "width":
		_drag_mode = "region_width"
		var center_x := _u_to_x(fposmod(region.angle, 360.0) / 360.0)
		_drag_width_side = -1 if screen.x < center_x else 1
		_drag_width_origin = _x_to_u(screen.x)
	else:
		_drag_mode = "region_body"
	_app.begin_edit()


func _drag_region_update(screen: Vector2, _event: InputEventMouseMotion) -> void:
	if _drag_region == null:
		return
	var du := _x_to_u(screen.x) - _drag_start_u
	if _drag_mode == "region_body":
		# 边拖边跟手，松手时 _snap_dragged_region 再回吸。
		var beat := _y_to_beat(screen.y)
		var span := moved_region(_drag_region_start_beat, _drag_region_end_beat, _drag_start_beat, beat)
		_drag_region.start_beat = span.x
		_drag_region.end_beat = span.y
		_drag_region.angle = fposmod(_drag_region_angle + du * 360.0, 360.0)
	else:
		# 拖一边：另一边基本不动，所以中心角度只走一半。
		_drag_region.width = dragged_region_width(_drag_region_width, du, _drag_width_side)
		_drag_region.angle = dragged_region_angle(_drag_region_angle, du, _drag_width_side)
	_app.touch_chart()


## 红区身体平移：时长不变，起点不早于 0。
static func moved_region(start_beat: float, end_beat: float, press_beat: float, beat: float) -> Vector2:
	var duration := maxf(0.25, end_beat - start_beat)
	var start := maxf(0.0, start_beat + beat - press_beat)
	return Vector2(start, start + duration)


## 红区宽度手柄：拖一边，另一边基本不动；上限 359°（全环没有可判定区域）。
static func dragged_region_width(start_width: float, delta_u: float, side: int) -> float:
	return clampf(start_width + delta_u * 360.0 * 2.0 * float(side), 10.0, 359.0)


static func dragged_region_angle(start_angle: float, delta_u: float, side: int) -> float:
	return fposmod(start_angle + delta_u * 360.0 * 0.5 * float(side), 360.0)


## 金键只有 24–30°，按 u 的 1:1 换算（约 0.57°/px），别用 Tap 的 2 倍速。
static func dragged_bell_width(start_width: float, delta_u: float, side: int) -> float:
	return clampf(start_width + delta_u * 360.0 * float(side), Note.BELL_MIN_WIDTH, Note.BELL_MAX_WIDTH)


## Seek 的弧宽 10–360°，同样是 1:1：画出来多宽就是判定弧多宽。
static func dragged_seek_width(start_width: float, delta_u: float, side: int) -> float:
	return clampf(start_width + delta_u * 360.0 * float(side), Note.SEEK_MIN_WIDTH, 360.0)


func _begin_red(beat: float, u: float) -> void:
	var chart: Chart = _app.chart
	if chart == null:
		return
	var region := Region.new(chart.next_region_id(), beat, beat + 1.0)
	region.angle = u * 360.0
	region.width = 30.0
	_app.begin_edit()
	chart.regions.append(region)
	_drag_mode = "limit"
	_drag_start_beat = beat
	_drag_start_u = u
	_drag_region = region
	_drag_region_start_beat = region.start_beat
	_drag_region_end_beat = region.end_beat
	_drag_region_angle = region.angle
	_drag_region_width = region.width
	_app.select_region(region.id)


func _drag_red_update(screen: Vector2, _event: InputEventMouseMotion) -> void:
	if _drag_region == null:
		return
	var u := _x_to_u(screen.x)
	# 边拖边跟手，松手时 _snap_dragged_region 再回吸。
	var beat := _y_to_beat(screen.y)
	var start_u := _drag_start_u
	var delta := (u - start_u) * 360.0
	if absf(delta) < 8.0:
		delta = 30.0 if delta >= 0.0 else -30.0
	_drag_region.angle = fposmod(start_u * 360.0 + delta * 0.5, 360.0)
	_drag_region.width = clampf(absf(delta), 10.0, 359.0)
	_drag_region.start_beat = minf(_drag_start_beat, beat)
	_drag_region.end_beat = maxf(_drag_start_beat + 0.25, minf(beat, _drag_start_beat + 4.0))
	_app.touch_chart()


func _create_event_at(beat: float, u: float) -> void:
	var chart: Chart = _app.chart
	if chart == null:
		return
	var event := BoundaryEvent.new(chart.next_event_id(), beat, beat + 4.0, u, minf(1.0, u + 0.5), chart.default_shape_id, chart.default_shape_id)
	_app.begin_edit()
	chart.events.append(event)
	_app.finish_edit()
	_app.select_event(event.id)
	notice.emit("事件已创建；在事件页选择目标形状与恢复方式。", "info")


func _finish_marquee() -> void:
	if _marquee.size.x < 3.0 and _marquee.size.y < 3.0:
		_app.clear_selection()
		return
	if _marquee_start_beat > _marquee_end_beat:
		var beat := _marquee_start_beat
		_marquee_start_beat = _marquee_end_beat
		_marquee_end_beat = beat
		var u := _marquee_start_u
		_marquee_start_u = _marquee_end_u
		_marquee_end_u = u
	var ids: Array[int] = []
	var chart: Chart = _app.chart
	for note in chart.notes:
		if note.group_id != chart.current_group:
			continue
		if _note_in_marquee(note):
			ids.append(note.id)
	_app.select_notes(ids)


func _note_in_marquee(note: Note) -> bool:
	# 先按拍位剔掉框外音符：1500 音符的谱面每次松手都全量投影是框选卡顿的主因。
	var top := minf(_marquee_start_beat, _marquee_end_beat)
	var bottom := maxf(_marquee_start_beat, _marquee_end_beat)
	var note_end := note.end_beat if note.type in ["hold", "path"] else note.beat
	if note.beat > bottom + 0.1 or note_end < top - 0.1:
		return false
	for item in _note_positions(note):
		if _circle_hits_marquee(item["point"], _note_point_radius(note, String(item.get("part", "head")))):
			return true
	if note.type in ["tap", "hold", "path"]:
		var head_width := note.width if note.type == "path" else note.arc_width()
		if _arc_hits_marquee(note.angle, head_width, _beat_to_y(note.beat)):
			return true
	if note.type == "path":
		var tail_local := note.path_tail_local()
		var tail_angle := note.tail_angle
		if tail_local.length() > 0.0001:
			tail_angle = rad_to_deg(atan2(tail_local.y, tail_local.x))
		if _arc_hits_marquee(tail_angle, note.tail_width, _beat_to_y(note.end_beat)):
			return true
		var total := maxf(0.001, note.duration())
		var previous := Vector2.INF
		for i in 41:
			var local := total * float(i) / 40.0
			if note.erased_at(local):
				previous = Vector2.INF
				continue
			var point := _path_screen_point(note, local)
			if previous.is_finite() and _segment_hits_marquee(previous, point):
				return true
			previous = point
	if note.type == "bell":
		var bell_center := Vector2(_u_to_x(note.center_u), _beat_to_y(note.beat))
		var bell_half := _bell_span(note) * 0.5
		if _marquee.intersects(Rect2(bell_center - Vector2(bell_half, 7.0), Vector2(bell_half * 2.0, 14.0))):
			return true
	if note.type == "seek":
		var seek_y := _beat_to_y(note.beat)
		if _marquee.intersects(Rect2(Vector2(_u_to_x(0.0), seek_y - 4.0), Vector2(_u_to_x(1.0) - _u_to_x(0.0), 8.0))):
			return true
	if note.type == "hold":
		var y0 := _beat_to_y(note.beat)
		var y1 := _beat_to_y(note.end_beat)
		var body_x := _u_to_x(fposmod(note.angle, 360.0) / 360.0)
		var half_width := 8.0
		var body := Rect2(Vector2(body_x - half_width, minf(y0, y1)), Vector2(half_width * 2.0, maxf(2.0, absf(y1 - y0))))
		if _marquee.intersects(body):
			return true
	return false


func _note_point_radius(note: Note, part: String) -> float:
	if note.type == "path":
		return 7.0 if part == "tail" else 9.0
	if note.type == "hold" or note.type == "tap":
		return 9.0
	return 8.0


func _arc_hits_marquee(center_angle: float, width: float, y: float) -> bool:
	var steps := 8
	var previous := Vector2.INF
	var half := maxf(0.0, width) * 0.5
	for i in steps + 1:
		var angle := center_angle - half + half * 2.0 * float(i) / float(steps)
		var point := Vector2(_u_to_x(fposmod(angle, 360.0) / 360.0), y)
		if _circle_hits_marquee(point, 4.0):
			return true
		if previous.is_finite() and _segment_hits_marquee(previous, point):
			return true
		previous = point
	return false


func _circle_hits_marquee(center: Vector2, radius: float) -> bool:
	var closest := Vector2(
		clampf(center.x, _marquee.position.x, _marquee.end.x),
		clampf(center.y, _marquee.position.y, _marquee.end.y)
	)
	return center.distance_squared_to(closest) <= radius * radius


func _segment_hits_marquee(a: Vector2, b: Vector2) -> bool:
	if _marquee.has_point(a) or _marquee.has_point(b):
		return true
	var corners := [
		_marquee.position,
		Vector2(_marquee.end.x, _marquee.position.y),
		_marquee.end,
		Vector2(_marquee.position.x, _marquee.end.y),
	]
	for i in 4:
		if Geometry2D.segment_intersects_segment(a, b, corners[i], corners[(i + 1) % 4]) != null:
			return true
	return false


func _select_visible() -> void:
	var chart: Chart = _app.chart
	if chart == null:
		return
	var ids: Array[int] = []
	var top := scroll_beat
	var bottom := scroll_beat + _visible_beats()
	for note in chart.notes:
		if note.group_id != chart.current_group:
			continue
		if note.beat >= top and note.beat <= bottom:
			ids.append(note.id)
	_app.select_notes(ids)


func _delete_hit(hit: Dictionary) -> void:
	# 右键单击直接删掉命中的那一个：音符 / 红区 / 事件。
	if _app == null or _app.chart == null or hit.is_empty():
		return
	var chart: Chart = _app.chart
	_app.begin_edit()
	match String(hit.get("kind", "")):
		"note":
			var note_id := int(hit.get("id", -1))
			for note in chart.notes.duplicate():
				if note.id == note_id:
					chart.notes.erase(note)
		"region":
			var region_id := int(hit.get("id", -1))
			for region in chart.regions.duplicate():
				if region.id == region_id:
					chart.regions.erase(region)
		"event":
			var event_id := String(hit.get("id", ""))
			for event in chart.events.duplicate():
				if event.id == event_id:
					chart.events.erase(event)
	_app.finish_edit()
	_app.clear_selection()
	_pending_path = null


func _delete_selection() -> void:
	if _app == null or _app.chart == null:
		return
	var chart: Chart = _app.chart
	_app.begin_edit()
	var note_ids: Array = []
	for note in _app.selection_with_partners():
		note_ids.append(note.id)
	for note in chart.notes.duplicate():
		if note_ids.has(note.id):
			chart.notes.erase(note)
	if _app.selected_region_id >= 0:
		for region in chart.regions.duplicate():
			if region.id == _app.selected_region_id:
				chart.regions.erase(region)
	if not _app.selected_event_id.is_empty():
		for event in chart.events.duplicate():
			if event.id == _app.selected_event_id:
				chart.events.erase(event)
	_app.finish_edit()
	_app.clear_selection()
	_pending_path = null


func _cancel_pending() -> void:
	if _pending_hold != null:
		if _app != null and _app.chart != null:
			_app.begin_edit()
			_app.chart.notes.erase(_pending_hold)
			_app.finish_edit()
			_app.clear_selection()
		_pending_hold = null
	if _pending_path != null:
		if _app != null and _app.chart != null:
			_app.begin_edit()
			_app.chart.notes.erase(_pending_path)
			_app.finish_edit()
			_app.clear_selection()
		_pending_path = null
		_pending_path_parent = null
	if _drag_mode != "":
		if _drag_mode == "marquee":
			_marquee = Rect2()
		_drag_mode = ""
		_app.finish_edit()
	queue_redraw()
	if _overlay != null:
		_overlay.queue_redraw()


func _path_tail_hit(pos: Vector2) -> Note:
	if _app == null or _app.chart == null:
		return null
	var best: Note = null
	var best_distance := 14.0
	for note in _app.chart.notes:
		if note.type != "path":
			continue
		var tail: Vector2 = note.path_tail_local()
		var angle: float = float(note.tail_angle)
		if tail.length() > 0.0001:
			angle = rad_to_deg(atan2(tail.y, tail.x))
		var point := Vector2(_u_to_x(fposmod(angle, 360.0) / 360.0), _beat_to_y(note.end_beat))
		var distance := point.distance_to(pos)
		if distance < best_distance:
			best_distance = distance
			best = note
	return best


func _find_note(note_id: int) -> Note:
	if _app == null or _app.chart == null:
		return null
	for note in _app.chart.notes:
		if note.id == note_id:
			return note
	return null
