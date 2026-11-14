class_name ChartBrowser
extends AcceptDialog

signal source_ready(source_path: String)
## BGA 可选下载失败时给主窗口一条提示，不阻断谱面导入。
signal warning(message: String)

const PAGE_SIZE := 30
const CACHE_ROOT := "user://chart_cache"
const FAVORITES_PATH := "user://chart_favorites.json"
const OSU_SEARCH_URL := "https://osu.direct/api/v2/search?query=%s&mode=0&amount=25"
const OSU_DOWNLOAD_URLS := [
	"https://dl.sayobot.cn/beatmaps/download/novideo/%d",
	"https://osu.direct/api/d/%d",
]

var _search: LineEdit
var _version: OptionButton
var _genre: OptionButton
var _favorites_only: CheckBox
var _filter_row: HBoxContainer
var _source_index := 0
var _status: Label
var _progress: ProgressBar
var _progress_window: AcceptDialog = null
var _progress_label: Label = null
var _progress_bar: ProgressBar = null
var _search_timer: Timer
var _request_serial: int = 0

## 舞萌卡列表。
var _cards_box: VBoxContainer
var _scroll: ScrollContainer
var _page := 0
var _prev_btn: Button
var _next_btn: Button
var _page_edit: LineEdit
var _page_total: Label
var _entries: Array = []
var _maj_items: Array = []
var _specs: Dictionary = {}
var _spec_lookup: Dictionary = {}

## 封面/等级懒加载：3 个 curl worker 串行消费队列，避免一页 60 个进程。
var _meta_jobs: Array = []
var _meta_seq := 0
var _adx_levels: Dictionary = {}
var _favorites: Dictionary = {}

## 详情与 BGA 询问。
var _detail: AcceptDialog
var _detail_box: VBoxContainer
var _detail_bga_label: Label
var _detail_download: Button
var _detail_serial := 0

## osu! 模式继续用原来的紧凑列表。
var osu_only: bool = false
var _list: ItemList
var _osu_items: Array = []
var _osu_query := ""


func _ready() -> void:
	if osu_only:
		title = "在线 osu! 谱面"
		ok_button_text = "下载并导入"
		min_size = Vector2i(760, 560)
		_build_osu_ui()
		confirmed.connect(_download_selected)
		about_to_popup.connect(_refresh)
		return
	title = "在线舞萌谱面"
	ok_button_text = "关闭"
	min_size = Vector2i(820, 560)
	_entries = _load_json("res://charts/adx_search.json")
	_specs = _load_json("res://charts/adx_specs.json")
	_load_favorites()
	_build_mai_ui()
	_populate_filters()
	_update_filter_visibility()
	for i in 8:
		_meta_worker()
	# 打开时才拉封面/等级：编辑器启动时不打网络。
	about_to_popup.connect(_refresh_mai)


func _load_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return [] if path.ends_with("search.json") else {}
	return JSON.parse_string(f.get_as_text())


func _setup_search_timer() -> void:
	_search_timer = Timer.new()
	_search_timer.one_shot = true
	_search_timer.wait_time = 0.35
	_search_timer.timeout.connect(_refresh)
	add_child(_search_timer)
	_search.text_changed.connect(func(_t: String) -> void: _search_timer.start())


## ── 舞萌下载器界面 ────────────────────────────────────────────────────
func _build_mai_ui() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	box.add_child(top)
	_search = LineEdit.new()
	_search.placeholder_text = "搜索 ID、曲名、罗马音、艺术家…"
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.custom_minimum_size = Vector2(0, 34)
	top.add_child(_search)
	_setup_search_timer()

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 0)
	var group := ButtonGroup.new()
	for i in 2:
		var btn := Button.new()
		btn.text = ["adxdls", "majdata"][i]
		btn.toggle_mode = true
		btn.button_group = group
		btn.button_pressed = i == 0
		btn.custom_minimum_size = Vector2(88, 34)
		btn.add_theme_font_size_override("font_size", 12)
		btn.pressed.connect(func() -> void: _set_source(i))
		tabs.add_child(btn)
	top.add_child(tabs)

	var filter_btn := Button.new()
	filter_btn.tooltip_text = "版本 / 曲风 / 只看收藏"
	filter_btn.toggle_mode = true
	filter_btn.focus_mode = Control.FOCUS_NONE
	filter_btn.custom_minimum_size = Vector2(44, 34)
	filter_btn.toggled.connect(func(on: bool) -> void: _filter_row.visible = on)
	var filter_icon := FunnelIcon.new()
	filter_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	filter_btn.add_child(filter_icon)
	filter_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	top.add_child(filter_btn)

	_filter_row = HBoxContainer.new()
	_filter_row.add_theme_constant_override("separation", 8)
	_filter_row.visible = false
	box.add_child(_filter_row)
	_version = OptionButton.new()
	_genre = OptionButton.new()
	_version.add_theme_font_size_override("font_size", 12)
	_genre.add_theme_font_size_override("font_size", 12)
	_version.item_selected.connect(_on_filter_changed)
	_genre.item_selected.connect(_on_filter_changed)
	_filter_row.add_child(_version)
	_filter_row.add_child(_genre)
	_favorites_only = CheckBox.new()
	_favorites_only.text = "只看收藏"
	_favorites_only.add_theme_font_size_override("font_size", 12)
	_favorites_only.toggled.connect(func(_on: bool) -> void: _page = 0; _refresh_mai())
	_filter_row.add_child(_favorites_only)
	var filter_spacer := Control.new()
	filter_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_filter_row.add_child(filter_spacer)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_scroll)
	_cards_box = VBoxContainer.new()
	_cards_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards_box.add_theme_constant_override("separation", 8)
	_scroll.add_child(_cards_box)

	_progress = ProgressBar.new()
	_progress.max_value = 100.0
	_progress.show_percentage = true
	_progress.custom_minimum_size = Vector2(0, 5)
	_progress.visible = false
	box.add_child(_progress)

	var page_row := HBoxContainer.new()
	page_row.add_theme_constant_override("separation", 6)
	box.add_child(page_row)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.add_theme_font_size_override("font_size", 11)
	_status.add_theme_color_override("font_color", UITheme.MUTED)
	page_row.add_child(_status)
	_prev_btn = Button.new()
	_prev_btn.text = "上一页"
	_prev_btn.add_theme_font_size_override("font_size", 11)
	_prev_btn.pressed.connect(func() -> void: _go_page(_page - 1))
	page_row.add_child(_prev_btn)
	_page_edit = LineEdit.new()
	_page_edit.text = "1"
	_page_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_edit.custom_minimum_size = Vector2(48, 0)
	_page_edit.add_theme_font_size_override("font_size", 11)
	_page_edit.text_submitted.connect(_on_page_submitted)
	page_row.add_child(_page_edit)
	_page_total = Label.new()
	_page_total.add_theme_font_size_override("font_size", 11)
	_page_total.add_theme_color_override("font_color", UITheme.MUTED)
	page_row.add_child(_page_total)
	_next_btn = Button.new()
	_next_btn.text = "下一页"
	_next_btn.add_theme_font_size_override("font_size", 11)
	_next_btn.pressed.connect(func() -> void: _go_page(_page + 1))
	page_row.add_child(_next_btn)


func _populate_filters() -> void:
	var versions := {}
	var genres := {}
	for slug in _specs:
		var s: Dictionary = _specs[slug]
		versions[String(s.get("groupDir", ""))] = true
		genres[String(s.get("genreDir", ""))] = true
	var version_names: Array = versions.keys()
	var genre_names: Array = genres.keys()
	version_names.sort()
	genre_names.sort()
	_version.add_item("全部版本")
	for v in version_names:
		_version.add_item(String(v))
	_genre.add_item("全部曲风")
	for g in genre_names:
		_genre.add_item(String(g))


func _set_source(index: int) -> void:
	if _source_index == index:
		return
	_source_index = clampi(index, 0, 1)
	_page = 0
	_update_filter_visibility()
	_refresh_mai()


func _update_filter_visibility() -> void:
	var is_adx := _source_index == 0
	_version.visible = is_adx
	_genre.visible = is_adx
	_favorites_only.visible = true


func _on_filter_changed(_index: int) -> void:
	_page = 0
	_refresh_mai()


func _go_page(page: int) -> void:
	_page = maxi(0, page)
	_refresh_mai()


func _on_page_submitted(text: String) -> void:
	var value := text.strip_edges()
	if not value.is_valid_int():
		_page_edit.text = str(_page + 1)
		return
	_page = maxi(0, int(value) - 1)
	_page_edit.release_focus()
	_refresh_mai()


func _refresh() -> void:
	if osu_mode():
		await _refresh_osu()
		return
	_refresh_mai()


func _refresh_mai() -> void:
	if _favorites_only != null and _favorites_only.button_pressed:
		_request_serial += 1
		_render_favorites()
		return
	if _source_index == 1:
		await _refresh_majdata_page()
		return
	_request_serial += 1
	_render_adx()


func osu_mode() -> bool:
	return osu_only


## ── adxdls ────────────────────────────────────────────────────────────
func _render_adx() -> void:
	var q := _search.text.strip_edges().to_lower()
	var vsel := "" if _version.selected <= 0 else _version.get_item_text(_version.selected)
	var gsel := "" if _genre.selected <= 0 else _genre.get_item_text(_genre.selected)
	var results: Array = []
	for e in _entries:
		var slug := String(e.get("slug", ""))
		var spec: Dictionary = _spec_for(slug)
		if not vsel.is_empty() and String(spec.get("groupDir", "")) != vsel:
			continue
		if not gsel.is_empty() and String(spec.get("genreDir", "")) != gsel:
			continue
		var hay := (String(e.get("title", "")) + " " + String(e.get("artist", "")) + " "
			+ " ".join(e.get("aliases", [])) + " " + String(e.get("title_romaji", "")) + " "
			+ String(e.get("artist_romaji", "")) + " " + slug + " " + String(e.get("id", ""))).to_lower()
		if not q.is_empty() and not hay.contains(q):
			continue
		results.append(e)
	var pages := maxi(1, int(ceil(float(results.size()) / float(PAGE_SIZE))))
	_page = clampi(_page, 0, pages - 1)
	var slice := paginate(results, _page, PAGE_SIZE)
	_clear_cards()
	for e in slice:
		_add_adx_card(e)
	if slice.is_empty():
		_show_empty("没有匹配的谱面")
	_update_page_bar(results.size(), pages)
	_status.text = "adxdls，共 %d 条" % results.size()


func _add_adx_card(entry: Dictionary, snapshot: Dictionary = {}) -> void:
	var slug := String(entry.get("slug", snapshot.get("id", "")))
	var spec: Dictionary = _spec_for(slug)
	var levels_value: Variant = snapshot.get("levels", _adx_levels.get(slug, []))
	var levels: Array = levels_value if levels_value is Array else []
	var designer := String(snapshot.get("designer", "")).strip_edges()
	if designer.is_empty():
		designer = _designer_from_levels(levels)
	var meta := {
		"kind": "adx",
		"id": slug,
		"title": String(entry.get("title", snapshot.get("title", ""))),
		"artist": String(entry.get("artist", snapshot.get("artist", ""))),
		"levels": levels,
		"designer": designer,
		"uploader": "",
		"spec": spec,
		"entry": entry,
	}
	var needs_levels := levels.is_empty() and not _adx_levels.has(slug)
	_add_card(meta, needs_levels)
	if needs_levels:
		_meta_jobs.append({"type": "adx_levels", "id": slug, "meta": meta})


## ── majdata ───────────────────────────────────────────────────────────
func _refresh_majdata_page() -> void:
	_request_serial += 1
	var serial := _request_serial
	_clear_cards()
	_show_loading("majdata：正在搜索…")
	var q := _search.text.strip_edges()
	var url := "https://majdata.net/api3/api/maichart/list?sort=&page=%d&search=%s" % [_page, q.uri_encode()]
	var body := await _curl_bytes(url, "https://majdata.net/", 20.0)
	if serial != _request_serial:
		return
	if body.is_empty():
		_clear_cards()
		_show_empty("majdata 搜索失败（网络不通或接口超时）")
		_status.text = "majdata，搜索失败"
		_update_page_bar(0, 0)
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	_maj_items = parsed if parsed is Array else []
	_clear_cards()
	for item in _maj_items:
		if item is Dictionary:
			_add_maj_card(item)
	if _maj_items.is_empty():
		_show_empty("没有匹配的谱面")
	_update_page_bar(_maj_items.size(), 0)
	_status.text = "majdata，第 %d 页，本页 %d 条" % [_page + 1, _maj_items.size()]


func _add_maj_card(item: Dictionary, snapshot: Dictionary = {}) -> void:
	var levels_value: Variant = snapshot.get("levels", null)
	var levels: Array = levels_value if levels_value is Array else maj_levels(item.get("levels", []))
	var meta := {
		"kind": "maj",
		"id": String(item.get("id", snapshot.get("id", ""))),
		"title": String(item.get("title", snapshot.get("title", ""))),
		"artist": String(item.get("artist", snapshot.get("artist", ""))),
		"levels": levels,
		"designer": String(item.get("designer", snapshot.get("designer", ""))),
		"uploader": String(item.get("uploader", snapshot.get("uploader", ""))),
		"item": item,
	}
	_add_card(meta)


## ── 卡片 ──────────────────────────────────────────────────────────────
func _add_card(meta: Dictionary, loading_levels: bool = false) -> void:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, 96)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var base_style := UITheme._box(UITheme.RAISED, UITheme.BORDER, 10, 0, 0)
	var hover_style := UITheme._box(UITheme.RAISED_HOVER, UITheme.BORDER_BRIGHT, 10, 0, 0)
	card.add_theme_stylebox_override("panel", base_style)
	card.mouse_entered.connect(func() -> void: card.add_theme_stylebox_override("panel", hover_style))
	card.mouse_exited.connect(func() -> void: card.add_theme_stylebox_override("panel", base_style))
	card.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_open_detail(meta)
	)
	_cards_box.add_child(card)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)

	var cover_frame := Panel.new()
	cover_frame.custom_minimum_size = Vector2(78, 78)
	cover_frame.clip_contents = true
	cover_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover_frame.add_theme_stylebox_override("panel", UITheme._box(UITheme.PANEL, UITheme.BORDER, 8, 0, 0))
	row.add_child(cover_frame)
	var cover := TextureRect.new()
	cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover_frame.add_child(cover)
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var glyph := Label.new()
	glyph.text = "♪"
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.add_theme_font_size_override("font_size", 28)
	glyph.add_theme_color_override("font_color", UITheme.FAINT)
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover_frame.add_child(glyph)
	glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_theme_constant_override("separation", 3)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(info)
	var title := Label.new()
	title.text = String(meta.get("title", ""))
	title.add_theme_font_override("font", UITheme.bold_font())
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", UITheme.INK)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(title)
	var artist := Label.new()
	artist.text = String(meta.get("artist", ""))
	artist.add_theme_font_size_override("font_size", 12)
	artist.add_theme_color_override("font_color", UITheme.MUTED)
	artist.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	artist.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	artist.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(artist)
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 5)
	chips.custom_minimum_size = Vector2(0, 22)
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(chips)

	var is_fav := _is_favorite(String(meta.get("kind", "")), String(meta.get("id", "")))
	var star := Button.new()
	star.text = "★" if is_fav else "☆"
	star.flat = true
	star.focus_mode = Control.FOCUS_NONE
	star.custom_minimum_size = Vector2(36, 36)
	star.add_theme_font_size_override("font_size", 22)
	star.add_theme_color_override("font_color", UITheme.GOLD if is_fav else UITheme.MUTED)
	star.add_theme_color_override("font_hover_color", UITheme.GOLD)
	star.tooltip_text = "收藏"
	star.mouse_filter = Control.MOUSE_FILTER_STOP
	star.pressed.connect(func() -> void: _toggle_favorite(meta, star))
	row.add_child(star)

	var arrow := Button.new()
	arrow.text = "›"
	arrow.flat = true
	arrow.focus_mode = Control.FOCUS_NONE
	arrow.custom_minimum_size = Vector2(28, 36)
	arrow.add_theme_font_size_override("font_size", 26)
	arrow.add_theme_color_override("font_color", UITheme.FAINT)
	arrow.add_theme_color_override("font_hover_color", UITheme.INK)
	arrow.tooltip_text = "详情"
	arrow.pressed.connect(func() -> void: _open_detail(meta))
	row.add_child(arrow)

	meta["chips"] = chips
	meta["star"] = star
	meta["cover"] = cover
	meta["glyph"] = glyph
	var levels_value: Variant = meta.get("levels", [])
	var levels: Array = levels_value if levels_value is Array else []
	meta["levels"] = levels
	_fill_chips(chips, levels, String(meta.get("kind", "")), loading_levels)

	var cached := _cover_from_cache(String(meta.get("kind", "")), String(meta.get("id", "")))
	if cached != null:
		cover.texture = cached
		glyph.visible = false
	else:
		_meta_jobs.append({
			"type": "cover",
			"kind": String(meta.get("kind", "")),
			"id": String(meta.get("id", "")),
			"spec": meta.get("spec", {}),
			"texture": cover,
			"glyph": glyph,
		})


func _fill_chips(chips: HBoxContainer, levels: Array, kind: String, loading: bool = false) -> void:
	for child in chips.get_children():
		chips.remove_child(child)
		child.queue_free()
	if levels.is_empty():
		var empty := Label.new()
		empty.text = ("读取难度…" if loading else "—")
		empty.add_theme_font_size_override("font_size", 11)
		empty.add_theme_color_override("font_color", UITheme.FAINT)
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chips.add_child(empty)
		return
	for d in levels:
		if not d is Dictionary:
			continue
		var index := int(d.get("index", 0))
		var level := String(d.get("level", ""))
		if level.is_empty():
			continue
		chips.add_child(_make_chip(level, index))


func _make_chip(text: String, index: int, wide: bool = false) -> PanelContainer:
	var color := _diff_color(index)
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", UITheme._box(color, color, 4, 6 if not wide else 8, 2))
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UITheme.bold_font())
	label.add_theme_font_size_override("font_size", 11 if not wide else 12)
	label.add_theme_color_override("font_color", UITheme.BG if color.get_luminance() > 0.55 else UITheme.INK)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(label)
	return chip


static func _diff_color(index: int) -> Color:
	match index:
		1: return UITheme.GREEN
		2: return UITheme.GOLD
		3: return UITheme.CORAL
		4: return UITheme.VIOLET
		5: return UITheme.PINK
	return UITheme.FAINT


func _show_loading(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(0, 80)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", UITheme.MUTED)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cards_box.add_child(label)


func _show_empty(text: String) -> void:
	_show_loading(text)


func _clear_cards() -> void:
	_meta_jobs.clear()
	for child in _cards_box.get_children():
		_cards_box.remove_child(child)
		child.queue_free()


func _update_page_bar(total: int, pages: int) -> void:
	_page_edit.text = str(_page + 1)
	if pages > 0:
		_page_total.text = "/ %d" % pages
	else:
		_page_total.text = ""
	_prev_btn.disabled = _page <= 0
	if pages > 0:
		_next_btn.disabled = _page >= pages - 1
	else:
		_next_btn.disabled = total < PAGE_SIZE


## ── 收藏 ──────────────────────────────────────────────────────────────
func _load_favorites() -> void:
	_favorites = {}
	var file := FileAccess.open(FAVORITES_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		_favorites = parsed


func _save_favorites() -> void:
	var file := FileAccess.open(FAVORITES_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(_favorites, "  "))
	file.close()


func _is_favorite(kind: String, id: String) -> bool:
	return _favorites.has(favorite_key(kind, id))


func _toggle_favorite(meta: Dictionary, star: Button) -> void:
	var key := favorite_key(String(meta.get("kind", "")), String(meta.get("id", "")))
	if _favorites.has(key):
		_favorites.erase(key)
	else:
		_favorites[key] = {
			"kind": String(meta.get("kind", "")),
			"id": String(meta.get("id", "")),
			"title": String(meta.get("title", "")),
			"artist": String(meta.get("artist", "")),
			"levels": meta.get("levels", []),
			"designer": String(meta.get("designer", "")),
			"uploader": String(meta.get("uploader", "")),
		}
	_save_favorites()
	_update_star(star, _favorites.has(key))
	if _favorites_only.button_pressed:
		_refresh_mai()


func _update_star(star: Button, on: bool) -> void:
	if not is_instance_valid(star):
		return
	star.text = "★" if on else "☆"
	star.add_theme_color_override("font_color", UITheme.GOLD if on else UITheme.MUTED)


func _update_favorite_levels(slug: String, levels: Array) -> void:
	var key := favorite_key("adx", slug)
	if not _favorites.has(key):
		return
	var fav: Dictionary = _favorites[key]
	fav["levels"] = levels
	var designer := _designer_from_levels(levels)
	if not designer.is_empty():
		fav["designer"] = designer
	_save_favorites()


func _render_favorites() -> void:
	var q := _search.text.strip_edges().to_lower()
	var kind := "adx" if _source_index == 0 else "maj"
	var vsel := "" if _version.selected <= 0 else _version.get_item_text(_version.selected)
	var gsel := "" if _genre.selected <= 0 else _genre.get_item_text(_genre.selected)
	var items: Array = []
	for key in _favorites:
		var fav: Dictionary = _favorites[key]
		if String(fav.get("kind", "")) != kind:
			continue
		var hay := (String(fav.get("title", "")) + " " + String(fav.get("artist", ""))).to_lower()
		if not q.is_empty() and not hay.contains(q):
			continue
		if kind == "adx":
			var spec: Dictionary = _spec_for(String(fav.get("id", "")))
			if not vsel.is_empty() and String(spec.get("groupDir", "")) != vsel:
				continue
			if not gsel.is_empty() and String(spec.get("genreDir", "")) != gsel:
				continue
		items.append(fav)
	var pages := maxi(1, int(ceil(float(items.size()) / float(PAGE_SIZE))))
	_page = clampi(_page, 0, pages - 1)
	var slice := paginate(items, _page, PAGE_SIZE)
	_clear_cards()
	for fav in slice:
		if kind == "adx":
			_add_adx_card({
				"slug": String(fav.get("id", "")),
				"title": String(fav.get("title", "")),
				"artist": String(fav.get("artist", "")),
			}, fav)
		else:
			_add_maj_card(fav, fav)
	if slice.is_empty():
		_show_empty("当前源还没有收藏" if q.is_empty() else "收藏里没有匹配的谱面")
	_update_page_bar(items.size(), pages)
	_status.text = "只看收藏，共 %d 条" % items.size()


## ── 详情 ──────────────────────────────────────────────────────────────
func _ensure_detail() -> AcceptDialog:
	if _detail != null:
		return _detail
	_detail = AcceptDialog.new()
	_detail.title = "谱面详情"
	_detail.ok_button_text = "关闭"
	_detail.min_size = Vector2i(560, 360)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_detail.add_child(margin)
	_detail_box = VBoxContainer.new()
	_detail_box.add_theme_constant_override("separation", 10)
	margin.add_child(_detail_box)
	add_child(_detail)
	_detail.confirmed.connect(func() -> void: _detail.hide())
	_detail.canceled.connect(func() -> void: _detail.hide())
	return _detail


func _clear_detail() -> void:
	for child in _detail_box.get_children():
		_detail_box.remove_child(child)
		child.queue_free()


func _open_detail(meta: Dictionary) -> void:
	_detail_serial += 1
	var serial := _detail_serial
	var dialog := _ensure_detail()
	_clear_detail()
	dialog.title = "谱面详情：%s" % ("adxdls" if meta.get("kind") == "adx" else "majdata")

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	_detail_box.add_child(top)
	var cover_frame := Panel.new()
	cover_frame.custom_minimum_size = Vector2(112, 112)
	cover_frame.clip_contents = true
	cover_frame.add_theme_stylebox_override("panel", UITheme._box(UITheme.PANEL, UITheme.BORDER, 10, 0, 0))
	top.add_child(cover_frame)
	var cover := TextureRect.new()
	cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	cover_frame.add_child(cover)
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var glyph := Label.new()
	glyph.text = "♪"
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.add_theme_font_size_override("font_size", 38)
	glyph.add_theme_color_override("font_color", UITheme.FAINT)
	cover_frame.add_child(glyph)
	glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var cached_cover := _cover_from_cache(String(meta.get("kind", "")), String(meta.get("id", "")))
	if cached_cover != null:
		cover.texture = cached_cover
		glyph.visible = false
	else:
		_meta_jobs.append({
			"type": "cover",
			"kind": String(meta.get("kind", "")),
			"id": String(meta.get("id", "")),
			"spec": meta.get("spec", {}),
			"texture": cover,
			"glyph": glyph,
		})

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 4)
	top.add_child(info)
	var title := Label.new()
	title.text = String(meta.get("title", ""))
	title.add_theme_font_override("font", UITheme.bold_font())
	title.add_theme_font_size_override("font_size", 20)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(title)
	var artist := Label.new()
	artist.text = String(meta.get("artist", ""))
	artist.add_theme_font_size_override("font_size", 13)
	artist.add_theme_color_override("font_color", UITheme.MUTED)
	artist.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	artist.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(artist)
	var designer := Label.new()
	designer.add_theme_font_size_override("font_size", 12)
	designer.add_theme_color_override("font_color", UITheme.MUTED)
	_designer_text(designer, meta)
	info.add_child(designer)
	var source := Label.new()
	source.text = "来源：%s" % ("adxdls" if meta.get("kind") == "adx" else "majdata")
	source.add_theme_font_size_override("font_size", 11)
	source.add_theme_color_override("font_color", UITheme.FAINT)
	info.add_child(source)

	_detail_box.add_child(HSeparator.new())
	var level_title := Label.new()
	level_title.text = "难度"
	level_title.add_theme_font_size_override("font_size", 12)
	level_title.add_theme_color_override("font_color", UITheme.MUTED)
	_detail_box.add_child(level_title)
	var levels_row := HBoxContainer.new()
	levels_row.add_theme_constant_override("separation", 6)
	_detail_box.add_child(levels_row)
	var bga := Label.new()
	bga.add_theme_font_size_override("font_size", 12)
	bga.add_theme_color_override("font_color", UITheme.MUTED)
	_detail_box.add_child(bga)
	var download := Button.new()
	download.text = "下载并导入"
	download.custom_minimum_size = Vector2(0, 36)
	download.size_flags_horizontal = Control.SIZE_SHRINK_END
	download.pressed.connect(func() -> void:
		_detail.hide()
		_ask_bga(meta)
	)
	_detail_box.add_child(download)

	_detail_bga_label = bga
	_detail_download = download
	var levels_value: Variant = meta.get("levels", [])
	var levels_now: Array = levels_value if levels_value is Array else []
	_fill_detail_levels(levels_row, levels_now)
	var bga_info: Dictionary = meta.get("bga_info", {})
	if bga_info.is_empty() and String(meta.get("kind", "")) == "adx":
		bga_info = adx_bga_info(meta.get("spec", {}))
		meta["bga_info"] = bga_info
	if bga_info.is_empty():
		bga.text = "BGA：检测中…"
		download.disabled = meta.get("kind") == "maj"
	else:
		_apply_detail_bga(bga_info)
	dialog.popup_centered(Vector2i(640, 450))

	if String(meta.get("kind", "")) == "adx" and levels_now.is_empty():
		var levels := await _load_adx_levels(String(meta.get("id", "")))
		if serial != _detail_serial or not dialog.visible:
			return
		var slug := String(meta.get("id", ""))
		if not levels.is_empty():
			_adx_levels[slug] = levels
			_update_favorite_levels(slug, levels)
		meta["levels"] = levels
		meta["designer"] = _designer_from_levels(levels)
		_fill_detail_levels(levels_row, levels)
		_designer_text(designer, meta)
	if bga_info.is_empty():
		var bga_result: Dictionary = await _maj_bga_info(String(meta.get("id", "")))
		if serial != _detail_serial or not dialog.visible:
			return
		meta["bga_info"] = bga_result
		_apply_detail_bga(bga_result)


func _designer_text(label: Label, meta: Dictionary) -> void:
	var designer := String(meta.get("designer", "")).strip_edges()
	if designer.is_empty() or designer == "-":
		designer = "未知"
	var uploader := String(meta.get("uploader", "")).strip_edges()
	if uploader.is_empty():
		label.text = "谱师：%s" % designer
	else:
		label.text = "谱师：%s，上传者：%s" % [designer, uploader]
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", UITheme.MUTED)


func _fill_detail_levels(row: HBoxContainer, levels: Array) -> void:
	for child in row.get_children():
		row.remove_child(child)
		child.queue_free()
	if levels.is_empty():
		var label := Label.new()
		label.text = "难度未知"
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", UITheme.FAINT)
		row.add_child(label)
		return
	for d in levels:
		if not d is Dictionary:
			continue
		var index := int(d.get("index", 0))
		var level := String(d.get("level", ""))
		if level.is_empty():
			continue
		row.add_child(_make_chip("%s %s" % [_difficulty_name(index), level], index, true))


func _apply_detail_bga(info: Dictionary) -> void:
	var label := _detail_bga_label
	var download := _detail_download
	if not is_instance_valid(label):
		return
	var state := String(info.get("state", "no"))
	var size := int(info.get("size", 0))
	match state:
		"yes":
			label.text = "BGA：有%s" % ("" if size <= 0 else "（%.1f MB）" % (float(size) / 1048576.0))
		"unknown":
			label.text = "BGA：状态未知（仍可尝试下载）"
		_:
			label.text = "BGA：无，下载时会跳过"
	if is_instance_valid(download):
		download.disabled = false


## ── BGA 询问与下载 ────────────────────────────────────────────────────
func _maj_bga_info(id: String) -> Dictionary:
	var url := "https://majdata.net/api3/api/maichart/%s/video" % id
	var info := await _head_info(url, "https://majdata.net/")
	var code := int(info.get("code", 0))
	if code == 200:
		return {"state": "yes", "size": int(info.get("length", 0))}
	if code == 404:
		return {"state": "no", "size": 0}
	if code == 405 or code == 403 or code == 501:
		# 部分 CDN 对 HEAD 回 405/403，但 GET 是好的：用 1 字节 Range 再确认一次。
		return await _probe_video_get(url)
	return {"state": "unknown", "size": 0}


func _probe_video_get(url: String) -> Dictionary:
	_meta_seq += 1
	var tmp := "user://probe_tmp_%d.txt" % _meta_seq
	var body_tmp := "user://probe_body_%d.bin" % _meta_seq
	var tmp_abs := ProjectSettings.globalize_path(tmp)
	var body_abs := ProjectSettings.globalize_path(body_tmp)
	if FileAccess.file_exists(tmp):
		DirAccess.remove_absolute(tmp_abs)
	if FileAccess.file_exists(body_tmp):
		DirAccess.remove_absolute(body_abs)
	var pid := OS.create_process("curl", [
		"-sL", "--max-time", "6", "--max-filesize", "65536", "-r", "0-0",
		"-A", "Mozilla/5.0", "-e", "https://majdata.net/",
		"-D", tmp_abs, "-o", body_abs, url,
	], false)
	if pid <= 0:
		return {"state": "unknown", "size": 0}
	var started := Time.get_ticks_msec()
	while OS.is_process_running(pid):
		if Time.get_ticks_msec() - started > 11000:
			OS.kill(pid)
			break
		await get_tree().create_timer(0.08).timeout
	var code := 0
	var length := 0
	var is_video_type := false
	if FileAccess.file_exists(tmp):
		var text := FileAccess.get_file_as_string(tmp)
		DirAccess.remove_absolute(tmp_abs)
		for line in text.split("\n"):
			var trimmed := line.strip_edges()
			if trimmed.begins_with("HTTP/"):
				var parts := trimmed.split(" ")
				if parts.size() >= 2 and String(parts[1]).is_valid_int():
					code = int(parts[1])
			elif trimmed.to_lower().begins_with("content-type:"):
				is_video_type = trimmed.to_lower().contains("video")
			elif trimmed.to_lower().begins_with("content-range:"):
				var slash := trimmed.find("/")
				if slash >= 0:
					var total := trimmed.substr(slash + 1).strip_edges()
					if total.is_valid_int():
						length = maxi(length, int(total))
			elif trimmed.to_lower().begins_with("content-length:"):
				var raw := trimmed.split(":", true, 1)
				if raw.size() == 2 and String(raw[1]).strip_edges().is_valid_int():
					length = maxi(length, int(String(raw[1]).strip_edges()))
	if FileAccess.file_exists(body_tmp):
		DirAccess.remove_absolute(body_abs)
	if code == 404:
		return {"state": "no", "size": 0}
	if is_video_type and (code == 200 or code == 206):
		return {"state": "yes", "size": length}
	return {"state": "unknown", "size": length}


func _ask_bga(meta: Dictionary) -> void:
	var info: Dictionary = meta.get("bga_info", {})
	if info.is_empty():
		if String(meta.get("kind", "")) == "adx":
			info = adx_bga_info(meta.get("spec", {}))
		else:
			info = await _maj_bga_info(String(meta.get("id", "")))
		meta["bga_info"] = info
	if String(info.get("state", "no")) == "no":
		_start_mai_download(meta, false)
		return
	var dialog := AcceptDialog.new()
	dialog.title = "选择下载版本"
	dialog.ok_button_text = "取消"
	dialog.min_size = Vector2i(440, 220)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	dialog.add_child(box)
	var label := Label.new()
	label.text = "《%s》\n选择要下载的版本：" % String(meta.get("title", ""))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var size_text := ""
	var size := int(info.get("size", 0))
	if size > 0:
		size_text = "（%.1f MB）" % (float(size) / 1048576.0)
	var with_bga := Button.new()
	with_bga.text = "带 BGA%s" % size_text
	with_bga.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	with_bga.custom_minimum_size = Vector2(0, 40)
	with_bga.pressed.connect(func() -> void:
		dialog.hide()
		dialog.queue_free()
		_start_mai_download(meta, true)
	)
	row.add_child(with_bga)
	var no_size := 0
	if String(meta.get("kind", "")) == "adx":
		no_size = download_size(download_files(meta.get("spec", {}), false))
	var no_size_text := ""
	if no_size > 0:
		no_size_text = "（%.1f MB）" % (float(no_size) / 1048576.0)
	var no_bga := Button.new()
	no_bga.text = "不带 BGA%s" % no_size_text
	no_bga.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	no_bga.custom_minimum_size = Vector2(0, 40)
	no_bga.pressed.connect(func() -> void:
		dialog.hide()
		dialog.queue_free()
		_start_mai_download(meta, false)
	)
	row.add_child(no_bga)
	dialog.confirmed.connect(func() -> void: dialog.queue_free())
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered(Vector2i(480, 240))


func _start_mai_download(meta: Dictionary, include_bga: bool) -> void:
	_show_download_progress()
	var result: Dictionary = {}
	if String(meta.get("kind", "")) == "adx":
		result = await _download_adx(meta, include_bga)
	else:
		result = await _download_maj(meta, include_bga)
	_hide_download_progress()
	if not bool(result.get("ok", false)):
		_status.text = "下载失败：没有拿到 maidata.txt"
		return
	_progress.visible = true
	_progress.value = 100.0
	_status.text = "下载完成 100%，开始转谱…"
	if bool(result.get("bga_failed", false)):
		warning.emit("BGA 下载失败，已导入无 BGA 版本")
	# 先关浏览器再交棒：导入过程会弹进度/报告对话框，两个独占子窗口会打架。
	hide()
	source_ready.emit(String(result.get("maidata", "")))


func _download_adx(meta: Dictionary, include_bga: bool) -> Dictionary:
	var slug := String(meta.get("id", ""))
	var folder := "user://imports/adx_%s/" % slug
	_ensure_dir(folder)
	var files := download_files(meta.get("spec", {}), include_bga)
	if files.is_empty():
		files = [
			{"name": "maidata.txt", "url": "https://adxdls.saop.cc/adxcs/%s/maidata.txt" % slug},
			{"name": "track.mp3", "url": "https://adxdls.saop.cc/adxcs/%s/track.mp3" % slug},
		]
	var maidata := ""
	var bga_failed := false
	for f in files:
		var name := String(f.get("name", ""))
		var url := String(f.get("url", ""))
		if url.begins_with("/"):
			url = "https://adxdls.saop.cc" + url
		var is_video_file := name.ends_with(".mp4") or name.ends_with(".webm")
		var body := await _fetch_bytes(url, "下载 " + name, 180.0 if is_video_file else 45.0)
		if body.is_empty():
			if is_video_file:
				bga_failed = true
			continue
		if is_video_file and not is_video(body):
			bga_failed = true
			continue
		var target := folder + name
		if _save_bytes(target, body) and name == "maidata.txt":
			maidata = target
	return {"ok": not maidata.is_empty(), "maidata": maidata, "bga_failed": bga_failed}


func _download_maj(meta: Dictionary, include_bga: bool) -> Dictionary:
	var id := String(meta.get("id", ""))
	var folder := "user://imports/maj_%s/" % id
	_ensure_dir(folder)
	var base := "https://majdata.net/api3/api/maichart/" + id
	var maidata := folder + "maidata.txt"
	var ok: bool = await _save(base + "/chart?intent=download", maidata, "下载 maidata", 60.0)
	if not ok:
		return {"ok": false, "maidata": "", "bga_failed": false}
	await _save(base + "/track", folder + "track.mp3", "下载音频", 120.0)
	var image := await _fetch_bytes(base + "/image?fullImage=true", "下载背景", 60.0)
	if _is_png(image):
		_save_bytes(folder + "bg.png", image)
	elif _is_jpeg(image):
		_save_bytes(folder + "bg.jpg", image)
	var bga_failed := false
	if include_bga:
		var video := await _fetch_bytes(base + "/video", "下载 BGA", 180.0)
		if not is_video(video):
			bga_failed = true
		else:
			_save_bytes(folder + "pv.mp4", video)
	return {"ok": true, "maidata": maidata, "bga_failed": bga_failed}


## ── 封面与等级懒加载 ──────────────────────────────────────────────────
func _meta_worker() -> void:
	while is_inside_tree():
		if _meta_jobs.is_empty():
			await get_tree().create_timer(0.08).timeout
			continue
		var job: Dictionary = _meta_jobs.pop_front()
		if String(job.get("type", "")) == "adx_levels":
			var slug := String(job.get("id", ""))
			var levels := await _load_adx_levels(slug)
			_adx_levels[slug] = levels
			_update_favorite_levels(slug, levels)
			var meta: Dictionary = job.get("meta", {})
			var chips_ref: Variant = meta.get("chips")
			if is_instance_valid(chips_ref):
				var chips: HBoxContainer = chips_ref
				meta["levels"] = levels
				meta["designer"] = _designer_from_levels(levels)
				_fill_chips(chips, levels, "adx", false)
		elif String(job.get("type", "")) == "cover":
			var texture := await _fetch_cover(job)
			if texture != null:
				var rect_ref: Variant = job.get("texture")
				if is_instance_valid(rect_ref):
					var rect: TextureRect = rect_ref
					rect.texture = texture
					var glyph_ref: Variant = job.get("glyph")
					if is_instance_valid(glyph_ref):
						var glyph: Label = glyph_ref
						glyph.visible = false


func _load_adx_levels(slug: String) -> Array:
	var cache_path := "%s/adx_maidata/%s.txt" % [CACHE_ROOT, slug]
	if FileAccess.file_exists(cache_path):
		return levels_from_maidata(cache_path)
	var spec: Dictionary = _spec_for(slug)
	var url := ""
	for f in spec.get("files", []):
		if String(f.get("name", "")) == "maidata.txt":
			url = String(f.get("url", ""))
			if url.begins_with("/"):
				url = "https://adxdls.saop.cc" + url
			break
	if url.is_empty():
		url = "https://adxdls.saop.cc/adxcs/%s/maidata.txt" % slug
	var body := await _curl_bytes(url, "https://adxdls.saop.cc/", 20.0)
	if body.is_empty():
		return []
	_ensure_dir(CACHE_ROOT + "/adx_maidata")
	_save_bytes(cache_path, body)
	return levels_from_maidata(cache_path)


func _fetch_cover(job: Dictionary) -> Texture2D:
	var kind := String(job.get("kind", ""))
	var id := String(job.get("id", ""))
	var cached := _cover_from_cache(kind, id)
	if cached != null:
		return cached
	if kind == "adx":
		for url in adx_cover_urls(job.get("spec", {})):
			var body := await _curl_bytes(url, "https://adxdls.saop.cc/", 15.0)
			if body.is_empty():
				continue
			var img := _image_from_bytes(body, kind)
			if img == null:
				continue
			var ext := "png" if _is_png(body) else "webp"
			_save_bytes("%s/covers/adx_%s.%s" % [CACHE_ROOT, id, ext], body)
			return ImageTexture.create_from_image(img)
		return null
	var url := "https://majdata.net/api3/api/maichart/%s/image" % id
	var body := await _curl_bytes(url, "https://majdata.net/", 15.0)
	if body.is_empty():
		return null
	var img := _image_from_bytes(body, kind)
	if img == null:
		return null
	var ext := "png" if _is_png(body) else "jpg"
	_save_bytes("%s/covers/maj_%s.%s" % [CACHE_ROOT, id, ext], body)
	return ImageTexture.create_from_image(img)


func _cover_from_cache(kind: String, id: String) -> Texture2D:
	var paths: Array = []
	if kind == "adx":
		paths = [
			"%s/covers/adx_%s.webp" % [CACHE_ROOT, id],
			"%s/covers/adx_%s.png" % [CACHE_ROOT, id],
		]
	else:
		paths = [
			"%s/covers/maj_%s.jpg" % [CACHE_ROOT, id],
			"%s/covers/maj_%s.png" % [CACHE_ROOT, id],
		]
	for path in paths:
		if not FileAccess.file_exists(String(path)):
			continue
		var image := Image.load_from_file(ProjectSettings.globalize_path(String(path)))
		if image == null or image.is_empty():
			continue
		return ImageTexture.create_from_image(image)
	return null


static func _image_from_bytes(data: PackedByteArray, kind: String) -> Image:
	var image := Image.new()
	var err := ERR_CANT_OPEN
	if kind == "adx":
		err = image.load_webp_from_buffer(data)
		if err != OK:
			err = image.load_png_from_buffer(data)
	else:
		err = image.load_jpg_from_buffer(data)
		if err != OK:
			err = image.load_png_from_buffer(data)
	return image if err == OK else null


static func _is_png(data: PackedByteArray) -> bool:
	if data.size() < 8:
		return false
	return data[0] == 0x89 and data[1] == 0x50 and data[2] == 0x4E and data[3] == 0x47


static func _is_jpeg(data: PackedByteArray) -> bool:
	return data.size() > 2 and data[0] == 0xFF and data[1] == 0xD8


## 有些 CDN 对 HEAD 返回 405、对不存在的视频回 404 HTML；只认真视频。
static func is_video(data: PackedByteArray) -> bool:
	if data.size() < 12:
		return false
	if data[0] == 0x1A and data[1] == 0x45 and data[2] == 0xDF and data[3] == 0xA3:
		return true
	return data[4] == 0x66 and data[5] == 0x74 and data[6] == 0x79 and data[7] == 0x70


func _save_bytes(path: String, data: PackedByteArray) -> bool:
	if data.is_empty():
		return false
	_ensure_dir(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(data)
	file.close()
	return true


func _ensure_dir(path: String) -> void:
	if path.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))


## ── 通用网络 ──────────────────────────────────────────────────────────
func _curl_bytes(url: String, referer: String, timeout_sec: float = 20.0) -> PackedByteArray:
	_meta_seq += 1
	var tmp := "user://meta_tmp_%d.bin" % _meta_seq
	var tmp_abs := ProjectSettings.globalize_path(tmp)
	var pid := OS.create_process("curl", [
		"-sL", "--max-time", str(int(timeout_sec)), "-A", "Mozilla/5.0",
		"-e", referer, "-o", tmp_abs, url,
	], false)
	if pid <= 0:
		return PackedByteArray()
	var started := Time.get_ticks_msec()
	var limit := int(timeout_sec * 1000.0) + 5000
	while OS.is_process_running(pid):
		if Time.get_ticks_msec() - started > limit:
			OS.kill(pid)
			break
		await get_tree().create_timer(0.05).timeout
	var data := PackedByteArray()
	if FileAccess.file_exists(tmp):
		data = FileAccess.get_file_as_bytes(tmp)
		DirAccess.remove_absolute(tmp_abs)
	return data


func _head_info(url: String, referer: String) -> Dictionary:
	_meta_seq += 1
	var tmp := "user://head_tmp_%d.txt" % _meta_seq
	var body_tmp := "user://head_body_%d.bin" % _meta_seq
	var tmp_abs := ProjectSettings.globalize_path(tmp)
	var body_abs := ProjectSettings.globalize_path(body_tmp)
	if FileAccess.file_exists(tmp):
		DirAccess.remove_absolute(tmp_abs)
	if FileAccess.file_exists(body_tmp):
		DirAccess.remove_absolute(body_abs)
	var pid := OS.create_process("curl", [
		"-sIL", "--max-time", "6", "-A", "Mozilla/5.0", "-e", referer,
		"-D", tmp_abs, "-o", body_abs, url,
	], false)
	if pid <= 0:
		return {}
	var started := Time.get_ticks_msec()
	while OS.is_process_running(pid):
		if Time.get_ticks_msec() - started > 11000:
			OS.kill(pid)
			break
		await get_tree().create_timer(0.08).timeout
	var code := 0
	var length := 0
	if FileAccess.file_exists(tmp):
		var text := FileAccess.get_file_as_string(tmp)
		DirAccess.remove_absolute(tmp_abs)
		for line in text.split("\n"):
			var trimmed := line.strip_edges()
			if trimmed.begins_with("HTTP/"):
				var parts := trimmed.split(" ")
				if parts.size() >= 2 and String(parts[1]).is_valid_int():
					code = int(parts[1])
			elif trimmed.to_lower().begins_with("content-length:"):
				var raw := trimmed.split(":", true, 1)
				if raw.size() == 2 and String(raw[1]).strip_edges().is_valid_int():
					length = maxi(length, int(String(raw[1]).strip_edges()))
	if FileAccess.file_exists(body_tmp):
		DirAccess.remove_absolute(body_abs)
	return {"code": code, "length": length}


func _fetch_bytes(url: String, label: String = "", timeout_sec: float = 45.0) -> PackedByteArray:
	# 统一用 curl：adxdls 和 majdata 都可能让 Godot HTTPRequest 卡住。
	var tmp := "user://online_tmp.bin"
	var tmp_abs := ProjectSettings.globalize_path(tmp)
	if FileAccess.file_exists(tmp):
		DirAccess.remove_absolute(tmp_abs)
	var referer := "https://majdata.net/" if url.contains("majdata.net") else "https://adxdls.saop.cc/"
	var total := 0
	if label.begins_with("下载"):
		total = _content_length(url, referer)
	_begin_progress(label, total)
	var pid := OS.create_process("curl", [
		"-sL", "--max-time", str(int(timeout_sec)), "-A", "Mozilla/5.0",
		"-e", referer, "-o", tmp_abs, url,
	], false)
	if pid <= 0:
		_end_progress()
		return PackedByteArray()
	var started := Time.get_ticks_msec()
	var limit := int(timeout_sec * 1000.0) + 5000
	while OS.is_process_running(pid):
		_update_progress(label, _file_size(tmp), total, started)
		if Time.get_ticks_msec() - started > limit:
			OS.kill(pid)
			break
		await get_tree().create_timer(0.08).timeout
	var data := PackedByteArray()
	if FileAccess.file_exists(tmp):
		data = FileAccess.get_file_as_bytes(tmp)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
	_update_progress(label, data.size(), total, started, true)
	_end_progress()
	if data.is_empty() and not label.is_empty():
		_status.text = "%s  下载失败" % label
	return data


func _content_length(url: String, referer: String) -> int:
	var output: Array = []
	var code := OS.execute("curl", ["-sIL", "--max-time", "4", "-A", "Mozilla/5.0", "-e", referer, url], output, true, false)
	if code != 0 or output.is_empty():
		return 0
	var total := 0
	for line in "\n".join(output).split("\n"):
		var lower := line.strip_edges().to_lower()
		if lower.begins_with("content-length:"):
			total = maxi(total, int(lower.split(":", true, 1)[1].strip_edges()))
	return total


func _file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var size := file.get_length()
	file.close()
	return size


## 用数字 slug 找到 adx_specs 里的条目（键可能是 "11213-arty-party"）。
func _spec_for(slug: String) -> Dictionary:
	if _specs.has(slug):
		return _specs[slug]
	if _spec_lookup.is_empty():
		for key in _specs:
			var key_text := String(key)
			var cut := key_text.find("-")
			var numeric := key_text.substr(0, cut) if cut > 0 else key_text
			if not _spec_lookup.has(numeric):
				_spec_lookup[numeric] = _specs[key]
	return _spec_lookup.get(slug, {})


func _save(url: String, path: String, label: String = "", timeout_sec: float = 45.0) -> bool:
	var body := await _fetch_bytes(url, label, timeout_sec)
	return _save_bytes(path, body)


## ── 进度窗口 ──────────────────────────────────────────────────────────
func _show_download_progress() -> void:
	if _progress_window == null:
		_progress_window = AcceptDialog.new()
		_progress_window.title = "下载谱面"
		_progress_window.min_size = Vector2i(460, 150)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 12)
		_progress_window.add_child(box)
		_progress_label = Label.new()
		_progress_label.text = "准备下载…"
		box.add_child(_progress_label)
		_progress_bar = ProgressBar.new()
		_progress_bar.max_value = 100.0
		_progress_bar.value = 0.0
		_progress_bar.show_percentage = true
		_progress_bar.custom_minimum_size = Vector2(420, 24)
		box.add_child(_progress_bar)
		add_child(_progress_window)
		var ok := _progress_window.get_ok_button()
		if ok != null:
			ok.visible = false
	_progress_bar.value = 0.0
	_progress_label.text = "准备下载…"
	_progress_window.popup_centered(Vector2i(500, 170))


func _hide_download_progress() -> void:
	if _progress_window != null:
		_progress_window.hide()


func _begin_progress(label: String, total: int) -> void:
	_progress.visible = true
	_progress.value = 0.0
	if label.is_empty():
		return
	if total > 0:
		_status.text = "%s  0 KB / %.0f KB" % [label, float(total) / 1024.0]
	else:
		_status.text = "%s  0 KB" % label


func _update_progress(label: String, size: int, total: int, started: int, done: bool = false) -> void:
	var percent := 0.0
	if total > 0:
		percent = clampf(100.0 * float(size) / float(maxi(1, total)), 0.0, 100.0)
	if _progress_bar != null:
		_progress_bar.value = percent
		if _progress_label != null:
			_progress_label.text = "%s\n%.0f KB / %.0f KB（%.0f%%）" % [label, float(size) / 1024.0, float(total) / 1024.0, percent]
	if total > 0:
		_progress.value = percent
		if not label.is_empty():
			_status.text = "%s  %.0f KB / %.0f KB (%.0f%%)" % [label, float(size) / 1024.0, float(total) / 1024.0, percent]
	else:
		_progress.value = fmod(float(Time.get_ticks_msec() - started) / 100.0, 100.0)
		if not label.is_empty():
			_status.text = "%s  %.0f KB" % [label, float(size) / 1024.0]
	if done and not label.is_empty():
		_status.text += "  完成"


func _end_progress() -> void:
	_progress.visible = false
	_progress.value = 0.0


## ── osu! 在线谱面 ──────────────────────────────────────────────────────
func _build_osu_ui() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var row := HBoxContainer.new()
	box.add_child(row)
	_search = LineEdit.new()
	_search.placeholder_text = "搜索 osu!std 谱面；也可粘贴谱面链接或 ID 直接下载"
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_search)
	_setup_search_timer()
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.custom_minimum_size = Vector2(0, 380)
	_list.item_activated.connect(func(_i: int) -> void: _download_selected())
	box.add_child(_list)
	_progress = ProgressBar.new()
	_progress.max_value = 100.0
	_progress.show_percentage = true
	_progress.custom_minimum_size = Vector2(0, 8)
	_progress.visible = false
	box.add_child(_progress)
	_status = Label.new()
	box.add_child(_status)


func _refresh_osu() -> void:
	var query := _search.text.strip_edges()
	if query.is_empty():
		_status.text = "osu!：输入曲名 / 作者 / 谱师搜索（镜像：osu.direct + sayobot）"
		return
	if query == _osu_query and not _osu_items.is_empty():
		_fill_osu_list()
		return
	var direct := parse_osu_input(query)
	if not direct.is_empty():
		_osu_items = []
		_list.clear()
		var kind_text := "谱面包" if String(direct.get("kind", "set")) == "set" else "单谱面（自动找所属谱面包）"
		_list.add_item("直接下载 %s #%d —— 回车开始" % [kind_text, int(direct.get("id", 0))])
		_list.set_item_metadata(0, direct)
		_osu_query = query
		_status.text = "osu!：识别为%s #%d，回车下载" % [kind_text, int(direct.get("id", 0))]
		return
	_osu_query = query
	_status.text = "osu!：正在搜索「%s」…" % query
	var bytes := await _http_get(OSU_SEARCH_URL % query.uri_encode(), "搜索 osu!")
	if bytes.is_empty():
		_status.text = "osu!：搜索失败（网络不通或镜像超时）"
		return
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if not parsed is Array:
		_status.text = "osu!：搜索返回异常"
		return
	_osu_items = parsed
	_fill_osu_list()


func _fill_osu_list() -> void:
	_list.clear()
	for item in _osu_items:
		if not item is Dictionary:
			continue
		var entry: Dictionary = item
		var std_count := osu_std_count(entry)
		if std_count <= 0:
			continue
		_list.add_item("%s — %s  [%d 个 std 难度]" % [
			String(entry.get("title", "")),
			String(entry.get("artist", "")),
			std_count,
		])
		_list.set_item_metadata(_list.item_count - 1, {"kind": "set", "id": int(entry.get("id", 0))})
	_status.text = "osu!：%d 个结果（回车下载整包，导入后在新标签页里切换难度）" % _osu_items.size()


func _download_selected() -> void:
	if not osu_mode():
		return
	var sel := _list.get_selected_items()
	if sel.is_empty():
		return
	var meta: Variant = _list.get_item_metadata(sel[0])
	var target: Dictionary = meta if meta is Dictionary else {"kind": "set", "id": int(meta)}
	_show_download_progress()
	await _download_osu(target)


func _download_osu(entry: Dictionary) -> void:
	var set_id := int(entry.get("id", 0))
	var kind := String(entry.get("kind", "set"))
	if set_id <= 0:
		return
	if kind == "beatmap":
		var resolved := await _resolve_set_id(set_id)
		if resolved <= 0:
			_hide_download_progress()
			_status.text = "osu!：解析谱面 #%d 失败（不在服上？）" % set_id
			return
		set_id = resolved
	var candidates: Array = [set_id]
	var target_path := ""
	for attempt in 2:
		for guess in candidates:
			target_path = await _download_osz(guess)
			if not target_path.is_empty():
				_hide_download_progress()
				_status.text = "osu!：下载完成，开始转谱"
				source_ready.emit(target_path)
				hide()
				return
		if kind == "set":
			var fallback := await _resolve_set_id(set_id)
			if fallback > 0 and fallback != set_id:
				candidates = [fallback]
				continue
		break
	_hide_download_progress()
	_status.text = "osu!：下载失败（两个镜像都没拿到）"


func _download_osz(set_id: int) -> String:
	var folder := "user://imports/osu_%d/" % set_id
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var target := folder + "chart.osz"
	_status.text = "osu!：正在下载谱面包 #%d…" % set_id
	for url_template in OSU_DOWNLOAD_URLS:
		var bytes := await _http_get(String(url_template) % set_id, "下载 osu! 谱面", 120.0)
		if bytes.size() < 2048:
			continue
		var file := FileAccess.open(target, FileAccess.WRITE)
		if file == null:
			continue
		file.store_buffer(bytes)
		file.close()
		return target
	return ""


func _http_get(url: String, label: String = "", timeout_sec: float = 40.0) -> PackedByteArray:
	var http := HTTPRequest.new()
	http.timeout = timeout_sec
	add_child(http)
	if not label.is_empty():
		_status.text = "%s…" % label
	var err := http.request(url)
	if err != OK:
		_status.text = "%s  启动失败" % label
		http.queue_free()
		return PackedByteArray()
	var result: Array = await http.request_completed
	http.queue_free()
	if result.size() < 4:
		return PackedByteArray()
	var code := int(result[1])
	var body: PackedByteArray = result[3]
	if int(result[0]) != HTTPRequest.RESULT_SUCCESS or code != 200 or body.is_empty():
		_status.text = "%s  失败（code=%d）" % [label, code]
		return PackedByteArray()
	if not label.is_empty():
		_status.text = "%s  完成（%.1f KB）" % [label, float(body.size()) / 1024.0]
	return body


func _resolve_set_id(beatmap_id: int) -> int:
	if beatmap_id <= 0:
		return 0
	var body := await _http_get("https://osu.ppy.sh/osu/%d" % beatmap_id, "解析谱面 #%d" % beatmap_id, 30.0)
	if body.is_empty():
		return 0
	var text := body.get_string_from_utf8()
	var idx := text.find("BeatmapSetID:")
	if idx < 0:
		return 0
	var rest := text.substr(idx + 13, 24).strip_edges()
	var line := rest.split("\n")[0].strip_edges()
	return int(line) if line.is_valid_int() else 0


## 搜索框里的链接 / 纯 ID：识别成“直接下载”。
##   https://osu.ppy.sh/beatmapsets/2356114#osu/5073664  → 谱面包 2356114
##   https://osu.ppy.sh/beatmaps/5073664                  → 单谱面 5073664
##   1234567                                              → 先当谱面包
static func parse_osu_input(text_in: String) -> Dictionary:
	var value := text_in.strip_edges()
	if value.is_empty():
		return {}
	if value.is_valid_int() and value.length() >= 3:
		return {"kind": "set", "id": int(value)}
	var lower := value.to_lower()
	if lower.contains("osu.ppy.sh") or lower.contains("osu.direct") or lower.contains("sayobot") or lower.contains("beatmapsets/") or lower.contains("beatmaps/"):
		var set_id := _regex_int(value, "beatmapsets[/#](\\d+)")
		if set_id > 0:
			return {"kind": "set", "id": set_id}
		var s_id := _regex_int(value, "/s/(\\d+)")
		if s_id > 0:
			return {"kind": "set", "id": s_id}
		var map_id := _regex_int(value, "beatmaps/(\\d+)")
		if map_id > 0:
			return {"kind": "beatmap", "id": map_id}
	return {}


static func _regex_int(text_in: String, pattern: String) -> int:
	var re := RegEx.new()
	if re.compile(pattern) != OK:
		return 0
	var found := re.search(text_in)
	if found == null:
		return 0
	var raw := found.get_string(1)
	return int(raw) if raw.is_valid_int() else 0


## 一个谱面包里有几个 osu!std 难度（taiko / mania / catch 不算）。
static func osu_std_count(entry: Dictionary) -> int:
	var count := 0
	for map in entry.get("beatmaps", []):
		if map is Dictionary and int((map as Dictionary).get("mode_int", 0)) == 0:
			count += 1
	return count


## ── 静态小工具（供测试与两个源共用） ─────────────────────────────────
static func paginate(items: Array, page: int, page_size: int = PAGE_SIZE) -> Array:
	if page < 0 or page_size <= 0:
		return []
	var start := page * page_size
	if start >= items.size():
		return []
	return items.slice(start, mini(items.size(), start + page_size))


static func maj_levels(levels: Variant) -> Array:
	var result: Array = []
	if not levels is Array:
		return result
	for index in range(1, 6):
		if index >= levels.size():
			break
		var raw: Variant = levels[index]
		if raw == null:
			continue
		var level := String(raw).strip_edges()
		if not level.is_empty():
			result.append({"index": index, "level": level})
	return result


static func levels_from_maidata(path: String) -> Array:
	var result: Array = []
	for diff in SimaiIO.list_maidata(path):
		var index := int(diff.get("index", 0))
		var level := String(diff.get("level", "")).strip_edges()
		if index < 1 or index > 5 or level.is_empty() or level == "?":
			continue
		result.append({
			"index": index,
			"level": level,
			"creator": String(diff.get("creator", "")),
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("index", 0)) < int(b.get("index", 0))
	)
	return result


static func adx_cover_url(url: String) -> String:
	if url.ends_with(".png"):
		return url.substr(0, url.length() - 4) + ".webp"
	return url


static func adx_cover_urls(spec: Dictionary) -> Array:
	for f in spec.get("files", []):
		if String(f.get("name", "")) != "bg.png":
			continue
		var url := String(f.get("url", ""))
		if url.begins_with("/"):
			url = "https://adxdls.saop.cc" + url
		var result: Array = [adx_cover_url(url)]
		if result[0] != url:
			result.append(url)
		return result
	return []


static func adx_bga_info(spec: Dictionary) -> Dictionary:
	for f in spec.get("files", []):
		var name := String(f.get("name", ""))
		if name.ends_with(".mp4") or name.ends_with(".webm"):
			return {"state": "yes", "size": int(f.get("bytes", 0))}
	return {"state": "no", "size": 0}


static func download_files(spec: Dictionary, include_bga: bool) -> Array:
	var result: Array = []
	for f in spec.get("files", []):
		var name := String(f.get("name", ""))
		var keep := name == "maidata.txt" or name.begins_with("track.") or name.begins_with("bg.")
		if include_bga and (name.ends_with(".mp4") or name.ends_with(".webm")):
			keep = true
		if keep:
			result.append(f)
	return result


static func download_size(files: Array) -> int:
	var total := 0
	for f in files:
		if f is Dictionary:
			total += int(f.get("bytes", 0))
	return total


static func favorite_key(kind: String, id: String) -> String:
	return "%s:%s" % [kind, id]


static func _designer_from_levels(levels: Array) -> String:
	for d in levels:
		if not d is Dictionary:
			continue
		var creator := String(d.get("creator", "")).strip_edges()
		if not creator.is_empty() and creator != "-":
			return creator
	return ""


static func _difficulty_name(index: int) -> String:
	match index:
		1: return "BASIC"
		2: return "ADV"
		3: return "EXP"
		4: return "MAS"
		5: return "Re:MAS"
	return "LV"


## 参考图里的漏斗图标：没有额外贴图，直接画三笔。
class FunnelIcon extends Control:
	func _draw() -> void:
		var c := size * 0.5
		var color := UITheme.MUTED
		var half := 7.0
		draw_line(c + Vector2(-half, -6.0), c + Vector2(half, -6.0), color, 1.8, true)
		draw_line(c + Vector2(-half, -6.0), c + Vector2(0.0, 1.0), color, 1.8, true)
		draw_line(c + Vector2(half, -6.0), c + Vector2(0.0, 1.0), color, 1.8, true)
		draw_line(c + Vector2(0.0, 1.0), c + Vector2(0.0, 7.0), color, 1.8, true)
