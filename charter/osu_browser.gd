class_name OsuBrowser
extends AcceptDialog

## 在线 osu! 谱面：卡片式可视化浏览器。
## 搜索走 osu.direct 镜像（mode=0），下载走 sayobot 去视频包，失败退回 osu.direct。
## 拿到 .osz 交给 source_ready，和本地导入走同一套转谱管线。

## [param star_hints] 难度名 → 星数（osu! 接口的 difficulty_rating），导入时用来排序和显示。
signal source_ready(source_path: String, star_hints: Dictionary)

const SEARCH_URL := "https://osu.direct/api/v2/search?query=%s&mode=0&amount=25"
const DOWNLOAD_URLS := [
	"https://dl.sayobot.cn/beatmaps/download/novideo/%d",
	"https://osu.direct/api/d/%d",
]
const COVER_DIR := "user://osu_covers"
## osu! 官方的类型 / 语言枚举（索引就是 API 的 genre_id / language_id）。
const GENRES := ["任何", "电子游戏", "动画", "J-Pop", "J-Rock", "同人", "纯音乐", "K-Pop", "电子", "摇滚", "嘻哈", "流行", "金属", "古典", "民谣", "爵士"]
const LANGUAGES := ["任何", "英语", "中文", "日语", "韩语", "西班牙语", "法语", "德语", "意大利语", "俄语", "波兰语", "葡萄牙语"]
const LANGUAGE_OTHER := -1
const PAGE_SIZE := 30
const CARD_HEIGHT := 118.0
const CARD_SEP := 10.0
const COVER_SIZE := 88.0
const COVER_CONCURRENCY := 3
const SET_INFO_URL := "https://osu.direct/api/v2/s/%d"

var _search: LineEdit
var _cards: VBoxContainer
var _scroll: ScrollContainer
var _status: Label
var _progress: ProgressBar
var _progress_label: Label
var _progress_bar: ProgressBar
var _progress_window: AcceptDialog
var _prev_button: Button
var _next_button: Button
var _page_edit: LineEdit

var _query := ""
## 当前页（0 起）；搜索结果按页缓存，翻回去不重新请求。
var _page := 0
var _page_items: Dictionary = {}
## 拉到不满一页就说明到底了。
var _exhausted := false
var _fetch_error := false
var _page_loading := false
var _favorites_only := false
var _favorites_check: CheckBox
var _filter_open := false
var _genre_filter := 0
var _language_filter := 0
var _tag_filter: LineEdit
var _filters_row: HBoxContainer
var _filter_button: Button
var _filtered_count := 0
var _shown_count := 0
var _busy := false
## 上一次请求还没回来时又改了搜索词：等它回来再按最新输入搜一次。
var _refresh_pending := false
var _cover_pending: Dictionary = {}
## 封面下载队列（同时最多 COVER_CONCURRENCY 个 HTTPRequest，避免一次开几百个）。
var _cover_queue: Array = []
var _cover_active := 0
var _tag_timer: Timer = null
## 收藏：settings 里只存 id，元数据在内存缓存；切到「只看收藏」时按页取。
var _fav_meta: Dictionary = {}
var _fav_items: Array = []
var _include_video := true
var _detail: AcceptDialog
var _detail_box: VBoxContainer
var _detail_serial := 0
var _debounce: Timer = null


func _ready() -> void:
	title = "在线 osu! 谱面"
	ok_button_text = "关闭"
	min_size = Vector2i(820, 700)
	_build()
	# 不在编辑器启动时打网络：第一次打开且还没有列表时才拉「最新上架」。
	about_to_popup.connect(_on_about_to_popup)


func _on_about_to_popup() -> void:
	if _page_items.is_empty():
		await _refresh()


func _build() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	# 搜索行：圆角输入框 + 漏斗筛选（和舞萌浏览器同一套控件）
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	root.add_child(row)
	_search = LineEdit.new()
	_search.placeholder_text = "搜索 ID、曲名、罗马音、艺术家…（留空 = 最新上架；也可粘贴谱面链接/ID）"
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.custom_minimum_size = Vector2(0, 34)
	_search.add_theme_font_size_override("font_size", 14)
	_search.text_submitted.connect(func(_t: String) -> void: _refresh())
	_search.text_changed.connect(_on_search_changed)
	row.add_child(_search)
	_filter_button = Button.new()
	_filter_button.toggle_mode = true
	_filter_button.focus_mode = Control.FOCUS_NONE
	_filter_button.custom_minimum_size = Vector2(44, 34)
	_filter_button.tooltip_text = "类型 / 语言 / 标签 / 只看收藏"
	_filter_button.toggled.connect(_on_filter_toggled)
	var filter_icon := ChartBrowser.FunnelIcon.new()
	filter_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_filter_button.add_child(filter_icon)
	filter_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_child(_filter_button)

	# 筛选行：类型 / 语言 / 标签 / 只看收藏（默认收起）
	_filters_row = HBoxContainer.new()
	_filters_row.add_theme_constant_override("separation", 8)
	_filters_row.visible = false
	root.add_child(_filters_row)
	var genre_box := OptionButton.new()
	genre_box.custom_minimum_size = Vector2(150, 30)
	for i in GENRES.size():
		genre_box.add_item(String(GENRES[i]))
	genre_box.select(0)
	genre_box.item_selected.connect(func(index: int) -> void:
		_genre_filter = index
		_filtered_count = 0
		_shown_count = 0
		_fill_cards()
	)
	_filters_row.add_child(genre_box)
	var language_box := OptionButton.new()
	language_box.custom_minimum_size = Vector2(130, 30)
	for i in LANGUAGES.size():
		language_box.add_item(String(LANGUAGES[i]))
	language_box.add_item("其他")
	language_box.select(0)
	language_box.item_selected.connect(func(index: int) -> void:
		_language_filter = index if index < LANGUAGES.size() else LANGUAGE_OTHER
		_filtered_count = 0
		_shown_count = 0
		_fill_cards()
	)
	_filters_row.add_child(language_box)
	_tag_filter = LineEdit.new()
	_tag_filter.placeholder_text = "标签（空格分隔，如 anime jpop touhou）"
	_tag_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tag_filter.custom_minimum_size = Vector2(0, 30)
	_tag_filter.text_changed.connect(func(_text: String) -> void:
		if _tag_timer == null:
			_tag_timer = Timer.new()
			_tag_timer.one_shot = true
			_tag_timer.wait_time = 0.25
			_tag_timer.timeout.connect(func() -> void:
				_filtered_count = 0
				_shown_count = 0
				_fill_cards()
			)
			add_child(_tag_timer)
		_tag_timer.start()
	)
	_filters_row.add_child(_tag_filter)
	_favorites_check = CheckBox.new()
	_favorites_check.text = "只看收藏"
	_favorites_check.add_theme_font_size_override("font_size", 12)
	_favorites_check.toggled.connect(func(on: bool) -> void:
		_favorites_only = on
		_page = 0
		_fill_cards()
		if on:
			_ensure_favorites_loaded()
	)
	_filters_row.add_child(_favorites_check)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_scroll)
	_cards = VBoxContainer.new()
	_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards.add_theme_constant_override("separation", int(CARD_SEP))
	_scroll.add_child(_cards)

	_progress = ProgressBar.new()
	_progress.max_value = 100.0
	_progress.show_percentage = true
	_progress.custom_minimum_size = Vector2(0, 8)
	_progress.visible = false
	root.add_child(_progress)

	# 分页行：状态 / 上一页 / 页码 / 下一页（osu 搜索接口没有总数）
	var page_row := HBoxContainer.new()
	page_row.add_theme_constant_override("separation", 6)
	root.add_child(page_row)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.add_theme_font_size_override("font_size", 12)
	_status.add_theme_color_override("font_color", UITheme.MUTED)
	page_row.add_child(_status)
	_prev_button = Button.new()
	_prev_button.text = "上一页"
	_prev_button.add_theme_font_size_override("font_size", 11)
	_prev_button.pressed.connect(func() -> void: _go_page(_page - 1))
	page_row.add_child(_prev_button)
	_page_edit = LineEdit.new()
	_page_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_edit.custom_minimum_size = Vector2(48, 0)
	_page_edit.add_theme_font_size_override("font_size", 11)
	_page_edit.text_submitted.connect(func(text: String) -> void:
		var wanted := int(text.strip_edges()) - 1
		if text.strip_edges().is_valid_int():
			_go_page(wanted)
		else:
			_page_edit.text = str(_page + 1)
	)
	page_row.add_child(_page_edit)
	_next_button = Button.new()
	_next_button.text = "下一页"
	_next_button.add_theme_font_size_override("font_size", 11)
	_next_button.pressed.connect(func() -> void: _go_page(_page + 1))
	page_row.add_child(_next_button)


func _on_filter_toggled(on: bool) -> void:
	_filter_open = on
	_filters_row.visible = on
	_filtered_count = 0
	_shown_count = 0
	_fill_cards()


func _has_filters() -> bool:
	return _genre_filter > 0 or _language_filter != 0 or not tag_tokens(_tag_filter.text if _tag_filter != null else "").is_empty()


func _on_search_changed(_text: String) -> void:
	# 输入防抖交给定时器，避免每个字符都打一次网络；清空也回到最新上架。
	if not is_inside_tree():
		return
	if _debounce == null:
		_debounce = Timer.new()
		_debounce.one_shot = true
		_debounce.wait_time = 0.45
		_debounce.timeout.connect(func() -> void: await _refresh())
		add_child(_debounce)
	_debounce.start()


# ---------------------------------------------------------------- 搜索

func _refresh() -> void:
	if _busy:
		_refresh_pending = true
		return
	var query := _search.text.strip_edges()
	var tags_text := _tag_filter.text if _tag_filter != null else ""
	if query.is_empty() and not tag_tokens(tags_text).is_empty():
		# 只填了标签：拿标签当搜索词去捞候选，再在本地按标签过滤。
		query = tags_text
	# 空搜索 = 浏览最新上架：镜像不传 query 就是 ranked 时间倒序。
	var direct := parse_osu_input(query)
	if not direct.is_empty():
		await _open_direct(direct)
		return
	if query == _query and _page_items.has(0):
		_page = 0
		_favorites_only = false
		if _favorites_check != null:
			_favorites_check.set_pressed_no_signal(false)
		_fill_cards()
		return
	_busy = true
	_query = query
	_page = 0
	_exhausted = false
	_page_items.clear()
	_favorites_only = false
	_cards_box_clear()
	_status.text = "正在加载最新上架…" if query.is_empty() else "正在搜索「%s」…" % query
	await _fetch_page(query, 0)
	_busy = false
	var again := _refresh_pending
	_refresh_pending = false
	if _fetch_error:
		_status.text = "最新上架加载失败（网络不通或镜像超时）" if query.is_empty() else "搜索失败（网络不通或镜像超时）"
		if again:
			await _refresh()
		return
	_fill_cards()
	if again:
		await _refresh()


## 粘贴链接 / 纯 ID：先取谱面包详情再开详情页；取不到就退回直接下载卡片。
func _open_direct(direct: Dictionary) -> void:
	var kind := String(direct.get("kind", "set"))
	var id := int(direct.get("id", 0))
	var set_id := id
	if kind == "beatmap":
		_status.text = "解析谱面 #%d…" % id
		set_id = await _resolve_set_id(id)
	if set_id <= 0:
		_status.text = "解析谱面 #%d 失败" % id
		return
	_status.text = "读取谱面包 #%d…" % set_id
	var entry := await _fetch_set_meta(set_id)
	if entry.is_empty():
		_page_items = {0: [{"id": set_id, "title": "谱面包 #%d" % set_id, "artist": "", "beatmaps": [], "covers": {}, "_direct": direct}]}
	else:
		_page_items = {0: [entry]}
	_page = 0
	_exhausted = true
	_fill_cards()
	if not entry.is_empty():
		_open_detail(entry)


## 拉第 page 页（0 起）并缓存；返回本页条目。失败时置 _fetch_error 并返回空数组。
func _fetch_page(query: String, page: int) -> Array:
	_fetch_error = false
	var url := SEARCH_URL % query.uri_encode()
	url = url.replace("amount=25", "amount=%d" % PAGE_SIZE) + "&offset=%d" % (page * PAGE_SIZE)
	var bytes := await _http_get(url, "搜索 osu!")
	if bytes.is_empty():
		_fetch_error = true
		return []
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if not parsed is Array:
		_fetch_error = true
		return []
	var raw := 0
	var entries: Array = []
	for item in parsed:
		if not item is Dictionary:
			continue
		raw += 1
		if osu_std_count(item) <= 0:
			continue
		entries.append(item)
	_page_items[page] = entries
	_exhausted = raw < PAGE_SIZE
	return entries


func _go_page(wanted: int) -> void:
	if wanted < 0 or _busy or _page_loading:
		_update_page_bar()
		return
	if _favorites_only:
		var pages := maxi(1, int(ceil(float(_fav_items.size()) / float(PAGE_SIZE))))
		_page = clampi(wanted, 0, pages - 1)
		_fill_cards()
		return
	if _page_items.has(wanted):
		_page = wanted
		_fill_cards()
		return
	if _exhausted and wanted > _page:
		_update_page_bar()
		return
	_page_loading = true
	_status.text = "加载第 %d 页…" % (wanted + 1)
	await _fetch_page(_query, wanted)
	_page_loading = false
	if _fetch_error:
		_status.text = "第 %d 页加载失败（网络不通或镜像超时）" % (wanted + 1)
		_update_page_bar()
		return
	_page = wanted
	_fill_cards()


func _update_page_bar() -> void:
	if _page_edit == null:
		return
	_page_edit.text = str(_page + 1)
	_prev_button.disabled = _page <= 0
	if _favorites_only:
		var pages := maxi(1, int(ceil(float(_fav_items.size()) / float(PAGE_SIZE))))
		_next_button.disabled = _page >= pages - 1
	else:
		_next_button.disabled = _exhausted and not _page_items.has(_page + 1)


func _current_items() -> Array:
	if _favorites_only:
		return _fav_items
	var page: Variant = _page_items.get(_page, [])
	return page if page is Array else []


## 全量重建当前页（搜索 / 筛选 / 收藏 / 翻页后都用它）。
func _fill_cards() -> void:
	_cards_box_clear()
	_shown_count = 0
	_filtered_count = 0
	for entry in _current_items():
		_append_card_if_visible(entry)
	if _filter_button != null:
		# 有筛选项时给漏斗一点颜色，和舞萌浏览器一致。
		_filter_button.modulate = UITheme.ACCENT if (_has_filters() or _favorites_only) else Color.WHITE
	_update_status()
	_update_page_bar()


func _append_card_if_visible(entry: Dictionary) -> bool:
	var tokens := tag_tokens(_tag_filter.text if _tag_filter != null else "")
	if _favorites_only and not _is_favorite(int(entry.get("id", 0))):
		return false
	if not matches_filters(entry, _genre_filter, _language_filter, tokens):
		_filtered_count += 1
		return false
	_add_card(entry)
	_shown_count += 1
	return true


func _update_status() -> void:
	if _shown_count == 0:
		if _favorites_only:
			_status.text = "还没有收藏（点卡片右侧的 ☆ 收藏）"
		elif _filtered_count > 0:
			_status.text = "当前筛选项把本页 %d 个结果全过滤掉了" % _filtered_count
		else:
			_status.text = "没有结果"
		return
	var suffix := "，筛选掉 %d 个" % _filtered_count if _filtered_count > 0 else ""
	var prefix := "最新上架， " if _query.is_empty() and not _favorites_only else ""
	_status.text = "%s%d 个谱面包%s，第 %d 页（点卡片看详情）" % [prefix, _shown_count, suffix, _page + 1]


func _cards_box_clear() -> void:
	var keep: Array = []
	for job in _cover_queue:
		if job.get("target") != null:
			keep.append(job)
		else:
			_cover_pending.erase(int(job.get("id", 0)))
	_cover_queue = keep
	for child in _cards.get_children():
		_cards.remove_child(child)
		child.queue_free()


func _add_card(entry: Dictionary) -> void:
	var card := BeatmapCard.new()
	card.setup(entry, _is_favorite(int(entry.get("id", 0))))
	card.custom_minimum_size = Vector2(0, CARD_HEIGHT)
	card.activated.connect(func(_id: int, _direct: Dictionary) -> void:
		_open_detail(entry)
	)
	card.favorite_toggled.connect(func(set_id: int) -> void:
		_toggle_favorite(set_id)
	)
	_cards.add_child(card)
	_load_cover(card, entry)


# ---------------------------------------------------------------- 收藏

func _is_favorite(set_id: int) -> bool:
	var app := _app()
	if app == null:
		return false
	return (app.osu_favorites as Array).has(set_id)


func _toggle_favorite(set_id: int) -> void:
	var app := _app()
	if app == null or set_id <= 0:
		return
	var list: Array = app.osu_favorites
	var at := list.find(set_id)
	if at >= 0:
		list.remove_at(at)
		_fav_meta.erase(set_id)
	else:
		list.append(set_id)
		var entry := _entry_by_id(set_id)
		if not entry.is_empty():
			_fav_meta[set_id] = entry
	app.save_settings()
	if _favorites_only:
		_page = 0
		await _ensure_favorites_loaded()
		_fill_cards()


## 收藏列表：settings 里只有 id，缺元数据的用 /api/v2/s/<id> 补。
func _ensure_favorites_loaded() -> void:
	var app := _app()
	if app == null:
		return
	_fav_items.clear()
	var pending: Array = []
	for value in app.osu_favorites:
		var set_id := int(value)
		if _fav_meta.has(set_id):
			_fav_items.append(_fav_meta[set_id])
		else:
			pending.append(set_id)
	if not pending.is_empty():
		_status.text = "读取收藏（%d 个）…" % pending.size()
		for set_id in pending:
			var entry := await _fetch_set_meta(int(set_id))
			if entry.is_empty():
				continue
			_fav_meta[int(set_id)] = entry
			_fav_items.append(entry)
	_fill_cards()


func _fetch_set_meta(set_id: int) -> Dictionary:
	if set_id <= 0:
		return {}
	var bytes := await _http_get(SET_INFO_URL % set_id, "信息 #%d" % set_id, 25.0)
	if bytes.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	return parsed if parsed is Dictionary else {}


func _entry_by_id(set_id: int) -> Dictionary:
	for page in _page_items.values():
		if page is Array:
			for entry in page:
				if entry is Dictionary and int(entry.get("id", 0)) == set_id:
					return entry
	var cached: Variant = _fav_meta.get(set_id, {})
	return cached if cached is Dictionary else {}


func _app() -> Node:
	return get_node_or_null("/root/App")


# ---------------------------------------------------------------- 封面

func _cover_path(set_id: int) -> String:
	return COVER_DIR.path_join("%d.jpg" % set_id)


func _load_cover(card: BeatmapCard, entry: Dictionary) -> void:
	var set_id := int(entry.get("id", 0))
	if set_id <= 0:
		return
	var path := _cover_path(set_id)
	if FileAccess.file_exists(path):
		var image := Image.load_from_file(ProjectSettings.globalize_path(path))
		if image != null and not image.is_empty():
			card.set_cover(ImageTexture.create_from_image(image))
			return
	var covers: Dictionary = entry.get("covers", {})
	var url := String(covers.get("list", covers.get("cover", "")))
	if url.is_empty() or _cover_pending.has(set_id):
		return
	_cover_pending[set_id] = true
	_cover_queue.append({"card": card, "url": url, "path": path, "id": set_id})
	_pump_covers()


## 详情页封面：和卡片共用缓存和请求队列，贴到 TextureRect 上。
func _load_cover_into(entry: Dictionary, target: TextureRect, glyph: Label) -> void:
	var set_id := int(entry.get("id", 0))
	if set_id <= 0:
		return
	var path := _cover_path(set_id)
	if FileAccess.file_exists(path):
		var image := Image.load_from_file(ProjectSettings.globalize_path(path))
		if image != null and not image.is_empty():
			target.texture = ImageTexture.create_from_image(image)
			if is_instance_valid(glyph):
				glyph.visible = false
			return
	var covers: Dictionary = entry.get("covers", {})
	var url := String(covers.get("list", covers.get("cover", "")))
	if url.is_empty() or _cover_pending.has(set_id):
		return
	_cover_pending[set_id] = true
	_cover_queue.append({"target": target, "glyph": glyph, "url": url, "path": path, "id": set_id})
	_pump_covers()


## 同时最多 COVER_CONCURRENCY 个封面请求；完成一个再补一个。
func _pump_covers() -> void:
	while _cover_active < COVER_CONCURRENCY and not _cover_queue.is_empty():
		var job: Dictionary = _cover_queue.pop_front()
		_cover_active += 1
		_start_cover(job)


func _start_cover(job: Dictionary) -> void:
	var http := HTTPRequest.new()
	http.timeout = 20.0
	add_child(http)
	http.request_completed.connect(func(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		http.queue_free()
		_cover_active = maxi(0, _cover_active - 1)
		_cover_pending.erase(int(job.get("id", 0)))
		# 卡片可能已经被过滤/翻页重建时释放，先按 Variant 拿引用再判有效。
		var card = job.get("card")
		var target = job.get("target")
		var glyph = job.get("glyph")
		if code == 200 and body.size() >= 256:
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(COVER_DIR))
			var file := FileAccess.open(String(job.get("path")), FileAccess.WRITE)
			if file != null:
				file.store_buffer(body)
				file.close()
			var image := Image.new()
			if image.load_jpg_from_buffer(body) == OK or image.load_png_from_buffer(body) == OK:
				var texture := ImageTexture.create_from_image(image)
				if is_instance_valid(card):
					card.set_cover(texture)
				elif is_instance_valid(target):
					target.texture = texture
					if is_instance_valid(glyph):
						glyph.visible = false
		_pump_covers()
	)
	http.request(String(job.get("url")))


# ---------------------------------------------------------------- 下载

## 详情页选了「不带视频」→ main 导入后把视频丢掉；读完自动复位。
func take_include_video() -> bool:
	var value := _include_video
	_include_video = true
	return value


func _download_osu(entry: Dictionary) -> void:
	if _busy:
		return
	var kind := String(entry.get("kind", "set"))
	var set_id := int(entry.get("id", 0))
	if set_id <= 0:
		_include_video = true
		return
	_show_progress("准备下载 #%d…" % set_id)
	_busy = true
	if kind == "beatmap":
		var resolved := await _resolve_set_id(set_id)
		if resolved <= 0:
			_finish_progress("解析谱面 #%d 失败" % set_id)
			_busy = false
			_include_video = true
			return
		set_id = resolved
	var candidates: Array = [set_id]
	var target := ""
	for _attempt in 2:
		for guess in candidates:
			target = await _download_osz(int(guess))
			if not target.is_empty():
				break
		if not target.is_empty():
			break
		if kind == "set":
			# 纯数字既可能是谱面包 id 也可能是谱面 id：解析一次再试。
			var fallback := await _resolve_set_id(set_id)
			if fallback > 0 and fallback != set_id:
				candidates = [fallback]
				continue
		break
	_busy = false
	if target.is_empty():
		_finish_progress("下载失败（两个镜像都没拿到）")
		_include_video = true
		return
	_finish_progress("下载完成，开始转谱")
	var hints := await _star_hints_for(entry, set_id)
	# 先关窗口再交棒：导入时会弹进度/报告对话框。
	hide()
	source_ready.emit(target, hints)


## 收集这个谱面包每个难度的星数：搜索/收藏的缓存里通常已经带 beatmaps，
## 没有就再查一次单包详情（失败就算了，只影响排序不阻塞导入）。
func _star_hints_for(entry: Dictionary, set_id: int) -> Dictionary:
	var hints := {}
	var maps: Array = entry.get("beatmaps", []) if entry.get("beatmaps", []) is Array else []
	if maps.is_empty() and set_id > 0:
		var meta := await _fetch_set_meta(set_id)
		if meta.get("beatmaps", []) is Array:
			maps = meta["beatmaps"]
	for item in maps:
		if not item is Dictionary:
			continue
		var map: Dictionary = item
		var version := String(map.get("version", ""))
		if version.is_empty():
			continue
		hints[version] = float(map.get("difficulty_rating", 0.0))
	return hints


func _download_osz(set_id: int) -> String:
	var folder := "user://imports/osu_%d/" % set_id
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var target := folder + "chart.osz"
	for template in DOWNLOAD_URLS:
		_set_progress_text("下载 osu! 谱面（#%d）…" % set_id)
		var bytes := await _http_get(String(template) % set_id, "下载 osu! 谱面", 120.0, true)
		if bytes.size() < 2048:
			continue
		var file := FileAccess.open(target, FileAccess.WRITE)
		if file == null:
			continue
		file.store_buffer(bytes)
		file.close()
		return target
	return ""


## 谱面 id → 谱面包 id：osu.ppy.sh 的 .osu 文本里带 BeatmapSetID，不需要 OAuth。
func _resolve_set_id(beatmap_id: int) -> int:
	if beatmap_id <= 0:
		return 0
	_set_progress_text("解析谱面 #%d…" % beatmap_id)
	var body := await _http_get("https://osu.ppy.sh/osu/%d" % beatmap_id, "解析谱面", 30.0)
	if body.is_empty():
		return 0
	var text := body.get_string_from_utf8()
	var at := text.find("BeatmapSetID:")
	if at < 0:
		return 0
	var line := text.substr(at + 13, 24).split("\n")[0].strip_edges()
	return int(line) if line.is_valid_int() else 0


func _http_get(url: String, label: String = "", timeout_sec: float = 40.0, show_progress: bool = false) -> PackedByteArray:
	var http := HTTPRequest.new()
	http.timeout = timeout_sec
	add_child(http)
	if not label.is_empty():
		_set_progress_text("%s…" % label)
	var err := http.request(url)
	if err != OK:
		http.queue_free()
		return PackedByteArray()
	var state := {"done": false, "code": 0, "body": PackedByteArray()}
	http.request_completed.connect(func(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		state["done"] = true
		state["code"] = code
		state["body"] = body
	)
	var total := 0
	var last_bytes := 0
	var last_tick := Time.get_ticks_msec()
	var speed_samples: Array = []
	while not state["done"]:
		await get_tree().process_frame
		if not is_inside_tree():
			break
		if not show_progress:
			continue
		var got := http.get_downloaded_bytes()
		if total <= 0:
			total = http.get_body_size()
		var now := Time.get_ticks_msec()
		var dt := float(now - last_tick) / 1000.0
		if dt >= 0.3:
			speed_samples.append(float(got - last_bytes) / dt / 1048576.0)
			if speed_samples.size() > 8:
				speed_samples.pop_front()
			last_bytes = got
			last_tick = now
		_update_download_progress(got, total, speed_samples)
	http.queue_free()
	if int(state["code"]) != 200:
		return PackedByteArray()
	var body: PackedByteArray = state["body"]
	return body


# ---------------------------------------------------------------- 进度窗

func _show_progress(text: String) -> void:
	if _progress_window == null:
		_progress_window = AcceptDialog.new()
		_progress_window.title = "下载 osu! 谱面"
		_progress_window.min_size = Vector2i(460, 150)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 12)
		_progress_window.add_child(box)
		_progress_label = Label.new()
		box.add_child(_progress_label)
		_progress_bar = ProgressBar.new()
		_progress_bar.max_value = 100.0
		_progress_bar.show_percentage = true
		_progress_bar.custom_minimum_size = Vector2(420, 22)
		box.add_child(_progress_bar)
		add_child(_progress_window)
		var ok := _progress_window.get_ok_button()
		if ok != null:
			ok.visible = false
	_progress_bar.value = 0.0
	_progress_label.text = text
	_progress_window.popup_centered(Vector2i(500, 170))


func _set_progress_text(text: String) -> void:
	if _progress_label != null:
		_progress_label.text = text
	if _status != null:
		_status.text = text


## 下载中：已下 / 总量 + 平均速度（最近 8 个采样）。
func _update_download_progress(got: int, total: int, speed_samples: Array) -> void:
	if _progress_label == null:
		return
	var text := "下载中 %.1f MB" % (float(got) / 1048576.0)
	if total > 0:
		text += " / %.1f MB" % (float(total) / 1048576.0)
		if _progress_bar != null:
			_progress_bar.value = clampf(float(got) / float(total), 0.0, 1.0) * 100.0
	if not speed_samples.is_empty():
		var speed := 0.0
		for sample in speed_samples:
			speed += float(sample)
		text += "（%.1f MB/s）" % (speed / float(speed_samples.size()))
	_progress_label.text = text


func _finish_progress(text: String) -> void:
	if _progress_window != null:
		_progress_window.hide()
	if _status != null:
		_status.text = text


# ---------------------------------------------------------------- 详情

func _ensure_detail() -> AcceptDialog:
	if _detail != null:
		return _detail
	_detail = AcceptDialog.new()
	_detail.title = "谱面详情：osu!"
	_detail.ok_button_text = "关闭"
	_detail.min_size = Vector2i(700, 560)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(660, 510)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail.add_child(scroll)
	_detail_box = VBoxContainer.new()
	_detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_box.add_theme_constant_override("separation", 10)
	scroll.add_child(_detail_box)
	add_child(_detail)
	return _detail


func _clear_detail() -> void:
	if _detail_box == null:
		return
	for child in _detail_box.get_children():
		_detail_box.remove_child(child)
		child.queue_free()


func _open_detail(entry: Dictionary) -> void:
	_detail_serial += 1
	var serial := _detail_serial
	var dialog := _ensure_detail()
	_clear_detail()

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
	_load_cover_into(entry, cover, glyph)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 4)
	top.add_child(info)
	var title := Label.new()
	title.text = String(entry.get("title", ""))
	title.add_theme_font_override("font", UITheme.bold_font())
	title.add_theme_font_size_override("font_size", 20)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(title)
	var unicode_title := String(entry.get("title_unicode", "")).strip_edges()
	if not unicode_title.is_empty() and unicode_title != title.text:
		var alt := Label.new()
		alt.text = unicode_title
		alt.add_theme_font_size_override("font_size", 12)
		alt.add_theme_color_override("font_color", UITheme.MUTED)
		info.add_child(alt)
	var artist := Label.new()
	artist.text = String(entry.get("artist", ""))
	artist.add_theme_font_size_override("font_size", 13)
	info.add_child(artist)
	var meta := Label.new()
	var creator := String(entry.get("creator", "")).strip_edges()
	var source_text := String(entry.get("source", "")).strip_edges()
	var bits: Array[String] = []
	if not creator.is_empty():
		bits.append("谱师 %s" % creator)
	if not source_text.is_empty():
		bits.append("来源 %s" % source_text)
	meta.text = "  ".join(bits)
	meta.add_theme_font_size_override("font_size", 11)
	meta.add_theme_color_override("font_color", UITheme.MUTED)
	info.add_child(meta)
	var tags_text := String(entry.get("tags", "")).strip_edges()
	if not tags_text.is_empty():
		var tags := Label.new()
		tags.text = tags_text.substr(0, 120)
		tags.add_theme_font_size_override("font_size", 10)
		tags.add_theme_color_override("font_color", UITheme.FAINT)
		tags.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(tags)

	var maps := _std_maps(entry)
	var levels_label := Label.new()
	levels_label.text = "难度（%d 个 osu!std）" % maps.size()
	levels_label.add_theme_font_size_override("font_size", 12)
	_detail_box.add_child(levels_label)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	_detail_box.add_child(flow)
	for map in maps:
		flow.add_child(_difficulty_chip(map))

	var stats := Label.new()
	stats.text = _stats_text(entry)
	stats.add_theme_font_size_override("font_size", 11)
	stats.add_theme_color_override("font_color", UITheme.MUTED)
	_detail_box.add_child(stats)
	_detail_box.add_child(HSeparator.new())

	var has_video := bool(entry.get("video", false))
	var note := Label.new()
	note.add_theme_font_size_override("font_size", 11)
	note.add_theme_color_override("font_color", UITheme.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if has_video:
		note.text = "这个谱面包带视频（BGA）。带/不带下载的是同一个包：「不带」会在导入后删除视频文件、不绑定 BGA。"
	else:
		note.text = "这个谱面包没有视频。"
	_detail_box.add_child(note)

	var size_label := Label.new()
	size_label.text = "包体：检测中…"
	size_label.add_theme_font_size_override("font_size", 11)
	size_label.add_theme_color_override("font_color", UITheme.FAINT)
	_detail_box.add_child(size_label)
	_probe_entry_size(entry, size_label, serial)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	_detail_box.add_child(buttons)
	if has_video:
		var with_video := Button.new()
		with_video.text = "带视频下载"
		with_video.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		with_video.custom_minimum_size = Vector2(0, 42)
		with_video.pressed.connect(func() -> void:
			_include_video = true
			dialog.hide()
			_download_osu(entry)
		)
		buttons.add_child(with_video)
		var without_video := Button.new()
		without_video.text = "不带视频下载"
		without_video.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		without_video.custom_minimum_size = Vector2(0, 42)
		without_video.tooltip_text = "包体相同；导入后删除视频文件、不绑定 BGA"
		without_video.pressed.connect(func() -> void:
			_include_video = false
			dialog.hide()
			_download_osu(entry)
		)
		buttons.add_child(without_video)
	else:
		var download := Button.new()
		download.text = "下载谱面"
		download.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		download.custom_minimum_size = Vector2(0, 42)
		download.pressed.connect(func() -> void:
			dialog.hide()
			_download_osu(entry)
		)
		buttons.add_child(download)

	dialog.popup_centered(Vector2i(720, 580))


func _std_maps(entry: Dictionary) -> Array:
	var out: Array = []
	for map in entry.get("beatmaps", []):
		if map is Dictionary and int((map as Dictionary).get("mode_int", 0)) == 0:
			out.append(map)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("difficulty_rating", 0.0)) < float(b.get("difficulty_rating", 0.0))
	)
	return out


func _difficulty_chip(map: Dictionary) -> PanelContainer:
	var stars := float(map.get("difficulty_rating", 0.0))
	var chip := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = star_color(stars)
	style.set_corner_radius_all(6)
	chip.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var star_label := Label.new()
	star_label.text = "%.1f" % stars
	star_label.add_theme_font_size_override("font_size", 12)
	star_label.add_theme_color_override("font_color", Color(0.06, 0.08, 0.10))
	row.add_child(star_label)
	var name := Label.new()
	name.text = String(map.get("version", ""))
	name.add_theme_font_size_override("font_size", 11)
	name.add_theme_color_override("font_color", Color(0.06, 0.08, 0.10, 0.88))
	row.add_child(name)
	chip.add_child(row)
	return chip


func _stats_text(entry: Dictionary) -> String:
	var bits: Array[String] = []
	bits.append("BPM %d" % int(entry.get("bpm", 0)))
	var longest := 0
	for map in _std_maps(entry):
		longest = maxi(longest, int(map.get("total_length", 0)))
	if longest > 0:
		bits.append("时长 %d:%02d" % [longest / 60, longest % 60])
	bits.append("游玩 %s" % _thousands(int(entry.get("play_count", 0))))
	bits.append("收藏 %s" % _thousands(int(entry.get("favourite_count", 0))))
	var status := String(entry.get("status", "")).strip_edges()
	if not status.is_empty():
		bits.append(status)
	return "  ".join(bits)


static func _thousands(value: int) -> String:
	var text := str(absi(value))
	var out := ""
	while text.length() > 3:
		out = "," + text.substr(text.length() - 3) + out
		text = text.substr(0, text.length() - 3)
	return text + out


## HEAD 拿包体大小；失败就显示「未知」。
func _probe_entry_size(entry: Dictionary, label: Label, serial: int) -> void:
	var set_id := int(entry.get("id", 0))
	if set_id <= 0:
		label.text = "包体：未知"
		return
	var url := String(DOWNLOAD_URLS[0]) % set_id
	var http := HTTPRequest.new()
	http.timeout = 15.0
	add_child(http)
	var err := http.request(url, PackedStringArray(), HTTPClient.METHOD_HEAD)
	if err != OK:
		http.queue_free()
		label.text = "包体：未知"
		return
	var result: Array = await http.request_completed
	http.queue_free()
	if serial != _detail_serial or not is_instance_valid(label):
		return
	var size := 0
	if result.size() >= 3:
		for header in (result[2] as PackedStringArray):
			var lower := String(header).to_lower()
			if lower.begins_with("content-length:"):
				var value := lower.substr(15).strip_edges()
				if value.is_valid_int():
					size = int(value)
				break
	if size <= 0:
		label.text = "包体：未知"
	elif size >= 1048576:
		label.text = "包体：%.1f MB" % (float(size) / 1048576.0)
	else:
		label.text = "包体：%.0f KB" % (float(size) / 1024.0)


# ---------------------------------------------------------------- 纯函数

## 展开时难度药丸要排几行（每行按卡片可用宽度算，+1 是末尾的“收起”胶囊）。
static func pill_rows(count: int, card_width: float) -> int:
	var per_row := maxi(1, int((card_width - 236.0) / (BeatmapCard.PILL_W + BeatmapCard.PILL_GAP)))
	return maxi(1, int(ceil(float(count + 1) / float(per_row))))


## 标签串 → 小写 token 列表（空格/逗号分隔，去重）。
static func tag_tokens(text: String) -> Array[String]:
	var out: Array[String] = []
	for raw in text.to_lower().replace(",", " ").replace("，", " ").split(" ", false):
		var token := String(raw).strip_edges()
		if not token.is_empty() and not out.has(token):
			out.append(token)
	return out


## osu 官方筛选：类型 / 语言 / 标签（token 之间是 AND，匹配 tags + 曲名 + 艺术家）。
static func matches_filters(entry: Dictionary, genre_id: int, language_id: int, tags: Array) -> bool:
	if genre_id > 0 and int(entry.get("genre_id", 0)) != genre_id:
		return false
	if language_id == LANGUAGE_OTHER:
		if int(entry.get("language_id", 0)) < 12:
			return false
	elif language_id > 0 and int(entry.get("language_id", 0)) != language_id:
		return false
	if tags.is_empty():
		return true
	var hay := (String(entry.get("tags", "")) + " " + String(entry.get("title", "")) + " " + String(entry.get("artist", ""))).to_lower()
	for token in tags:
		if not hay.contains(String(token).to_lower()):
			return false
	return true


## 一个谱面包里有几个 osu!std 难度（taiko / mania / catch 不算）。
static func osu_std_count(entry: Dictionary) -> int:
	var count := 0
	for map in entry.get("beatmaps", []):
		if map is Dictionary and int((map as Dictionary).get("mode_int", 0)) == 0:
			count += 1
	return count


## 星数 → 药丸颜色（绿 → 黄 → 橙 → 红 → 紫）。
static func star_color(stars: float) -> Color:
	if stars < 2.5:
		return Color(0.36, 0.78, 0.42)
	if stars < 4.0:
		return Color(0.95, 0.82, 0.28)
	if stars < 5.5:
		return Color(0.95, 0.60, 0.26)
	if stars < 6.5:
		return Color(0.92, 0.33, 0.33)
	return Color(0.72, 0.44, 0.95)


## 搜索框里的链接 / 纯 ID → 直接下载。
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
		var short_id := _regex_int(value, "/s/(\\d+)")
		if short_id > 0:
			return {"kind": "set", "id": short_id}
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


# ---------------------------------------------------------------- 卡片

class BeatmapCard extends Control:
	signal activated(set_id: int, direct: Dictionary)
	signal favorite_toggled(set_id: int)

	var set_id: int = 0
	var title: String = ""
	var artist: String = ""
	var difficulties: Array = []      # [{stars, name}]
	const PILL_W := 74.0
	const PILL_H := 38.0
	const PILL_GAP := 6.0
	const CHIP_W := 64.0
	const COLLAPSED_PILLS := 4
	var favorite: bool = false
	var expanded := false
	var _chip_rect := Rect2()
	var direct: Dictionary = {}
	var cover: Texture2D = null
	var _hover: bool = false
	var _bg: StyleBoxFlat

	func setup(entry: Dictionary, is_favorite: bool) -> void:
		set_id = int(entry.get("id", 0))
		title = String(entry.get("title", ""))
		artist = String(entry.get("artist", ""))
		favorite = is_favorite
		direct = entry.get("_direct", {})
		difficulties.clear()
		for map in entry.get("beatmaps", []):
			if not map is Dictionary:
				continue
			var item: Dictionary = map
			if int(item.get("mode_int", 0)) != 0:
				continue
			difficulties.append({
				"stars": float(item.get("difficulty_rating", 0.0)),
				"name": String(item.get("version", "")),
			})
		difficulties.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.get("stars", 0.0)) < float(b.get("stars", 0.0))
		)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func() -> void:
			_hover = true
			queue_redraw()
		)
		mouse_exited.connect(func() -> void:
			_hover = false
			queue_redraw()
		)

	func set_cover(texture: Texture2D) -> void:
		cover = texture
		queue_redraw()

	func _favorite_rect() -> Rect2:
		return Rect2(size.x - 96.0, (size.y - 26.0) * 0.5, 26.0, 26.0)

	func _gui_input(event: InputEvent) -> void:
		if not (event is InputEventMouseButton):
			return
		var click: InputEventMouseButton = event
		if not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
			return
		if _favorite_rect().has_point(click.position):
			favorite = not favorite
			favorite_toggled.emit(set_id)
			queue_redraw()
			accept_event()
			return
		if _chip_rect.has_area() and _chip_rect.has_point(click.position):
			expanded = not expanded
			_layout_height()
			queue_redraw()
			accept_event()
			return
		activated.emit(set_id, direct)
		accept_event()

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		_chip_rect = Rect2()
		_bg = StyleBoxFlat.new()
		_bg.bg_color = UITheme.RAISED_HOVER if _hover else UITheme.RAISED
		_bg.border_color = UITheme.BORDER_BRIGHT if _hover else UITheme.BORDER
		_bg.set_border_width_all(1)
		_bg.set_corner_radius_all(12)
		draw_style_box(_bg, rect)
		# 封面
		var cover_rect := Rect2(Vector2(14, 14), Vector2(88, 88))
		if cover != null:
			draw_texture_rect(cover, cover_rect, false)
		else:
			draw_rect(cover_rect, Color(0.12, 0.14, 0.18))
			draw_string(UITheme.bold_font(), cover_rect.position + Vector2(30, 52), "♪", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, UITheme.FAINT)
		draw_rect(cover_rect, Color(1, 1, 1, 0.08), false, 1.0)
		# 标题 / 作者
		var text_x := 116.0
		var text_width := maxf(40.0, size.x - text_x - 120.0)
		draw_string(UITheme.bold_font(), Vector2(text_x, 34), _elide(title, text_width, 17), HORIZONTAL_ALIGNMENT_LEFT, text_width, 17, UITheme.INK)
		draw_string(UITheme.mono_font(), Vector2(text_x, 56), _elide("%s，%d 个难度" % [artist, difficulties.size()], text_width, 12), HORIZONTAL_ALIGNMENT_LEFT, text_width, 12, UITheme.MUTED)
		# 难度药丸：两行（星数 + 难度名）
		var pill_x := text_x
		var pill_y := 68.0
		var max_x := size.x - 120.0
		var shown := difficulties.size() if expanded else mini(COLLAPSED_PILLS, difficulties.size())
		for i in shown:
			if pill_x + PILL_W > max_x and pill_x > text_x:
				pill_x = text_x
				pill_y += PILL_H + PILL_GAP
			_draw_pill(pill_x, pill_y, difficulties[i])
			pill_x += PILL_W + PILL_GAP
		# 还有没显示的难度：一个“+N ▾”胶囊，点开/收起
		var hidden := difficulties.size() - shown
		if hidden > 0 or expanded:
			if pill_x + CHIP_W > max_x and pill_x > text_x:
				pill_x = text_x
				pill_y += PILL_H + PILL_GAP
			_chip_rect = Rect2(Vector2(pill_x, pill_y), Vector2(CHIP_W, PILL_H))
			var chip_style := StyleBoxFlat.new()
			chip_style.bg_color = Color(0.18, 0.20, 0.26) if not _hover else Color(0.24, 0.27, 0.34)
			chip_style.border_color = UITheme.BORDER_BRIGHT
			chip_style.set_border_width_all(1)
			chip_style.set_corner_radius_all(6)
			draw_style_box(chip_style, _chip_rect)
			var chip_text := "收起 ▴" if expanded else "+%d ▾" % hidden
			draw_string(UITheme.bold_font(), Vector2(pill_x, pill_y + 25), chip_text, HORIZONTAL_ALIGNMENT_CENTER, CHIP_W, 12, UITheme.INK)
		# 展开时按实际宽度算行数，卡片高度跟着长
		if expanded:
			var rows := OsuBrowser.pill_rows(difficulties.size(), size.x)
			var needed := OsuBrowser.CARD_HEIGHT + float(rows - 1) * (PILL_H + PILL_GAP)
			if absf(custom_minimum_size.y - needed) > 0.5:
				custom_minimum_size = Vector2(0, needed)
		elif absf(custom_minimum_size.y - OsuBrowser.CARD_HEIGHT) > 0.5:
			custom_minimum_size = Vector2(0, OsuBrowser.CARD_HEIGHT)
		var star_rect := _favorite_rect()
		_draw_star(star_rect.get_center(), 9.0, favorite)
		# 箭头
		var arrow_x := size.x - 30.0
		var mid_y := size.y * 0.5
		var arrow_color := UITheme.INK if _hover else UITheme.MUTED
		draw_line(Vector2(arrow_x - 4, mid_y - 6), Vector2(arrow_x + 2, mid_y), arrow_color, 2.0, true)
		draw_line(Vector2(arrow_x + 2, mid_y), Vector2(arrow_x - 4, mid_y + 6), arrow_color, 2.0, true)

	func _draw_pill(x: float, y: float, entry: Dictionary) -> void:
		var stars := float(entry.get("stars", 0.0))
		var name := String(entry.get("name", ""))
		var style := StyleBoxFlat.new()
		style.bg_color = OsuBrowser.star_color(stars)
		style.set_corner_radius_all(6)
		draw_style_box(style, Rect2(Vector2(x, y), Vector2(PILL_W, PILL_H)))
		draw_string(UITheme.bold_font(), Vector2(x, y + 16), "%.1f" % stars, HORIZONTAL_ALIGNMENT_CENTER, PILL_W, 13, Color(0.06, 0.08, 0.10))
		draw_string(UITheme.mono_font(), Vector2(x, y + 32), _elide(name, PILL_W - 6.0, 9), HORIZONTAL_ALIGNMENT_CENTER, PILL_W, 9, Color(0.06, 0.08, 0.10, 0.85))

	func _layout_height() -> void:
		if not expanded:
			custom_minimum_size = Vector2(0, OsuBrowser.CARD_HEIGHT)
			return
		var rows := OsuBrowser.pill_rows(difficulties.size(), maxf(size.x, 600.0))
		custom_minimum_size = Vector2(0, OsuBrowser.CARD_HEIGHT + float(rows - 1) * (PILL_H + PILL_GAP))

	func _draw_star(center: Vector2, radius: float, filled: bool) -> void:
		var points := PackedVector2Array()
		for i in 10:
			var angle := -PI * 0.5 + float(i) * PI / 5.0
			var r := radius if i % 2 == 0 else radius * 0.45
			points.append(center + Vector2(cos(angle), sin(angle)) * r)
		if filled:
			draw_colored_polygon(points, UITheme.GOLD)
		else:
			points.append(points[0])
			draw_polyline(points, UITheme.MUTED, 1.6, true)

	static func _elide(text: String, width: float, font_size: int) -> String:
		var font := UITheme.bold_font() if font_size >= 15 else UITheme.mono_font()
		if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= width:
			return text
		var cut := text
		while cut.length() > 1 and font.get_string_size(cut + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
			cut = cut.substr(0, cut.length() - 1)
		return cut + "…"
