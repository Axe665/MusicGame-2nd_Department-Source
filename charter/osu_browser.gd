class_name OsuBrowser
extends AcceptDialog

## 在线 osu! 谱面：卡片式可视化浏览器。
## 搜索走 osu.direct 镜像（mode=0），下载走 sayobot 去视频包，失败退回 osu.direct。
## 拿到 .osz 交给 source_ready，和本地导入走同一套转谱管线。

signal source_ready(source_path: String)

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
const PAGE_SIZE := 50
const CARD_HEIGHT := 118.0
const CARD_SEP := 10.0
const COVER_SIZE := 88.0
const COVER_CONCURRENCY := 3

var _search: LineEdit
var _favorites_button: Button
var _cards: VBoxContainer
var _scroll: ScrollContainer
var _status: Label
var _progress: ProgressBar
var _progress_label: Label
var _progress_bar: ProgressBar
var _progress_window: AcceptDialog

var _items: Array = []
var _query := ""
var _favorites_only := false
var _filter_open := false
var _genre_filter := 0
var _language_filter := 0
var _tag_filter: LineEdit
var _filters_row: HBoxContainer
var _filter_button: Button
var _filtered_count := 0
var _offset := 0
var _has_more := false
var _loading_more := false
var _fetch_error := false
var _shown_count := 0
var _more_button: Button
var _busy := false
var _cover_pending: Dictionary = {}
## 封面下载队列（同时最多 COVER_CONCURRENCY 个 HTTPRequest，避免一次开几百个）。
var _cover_queue: Array = []
var _cover_active := 0
var _tag_timer: Timer = null


func _ready() -> void:
	title = "在线 osu! 谱面"
	ok_button_text = "关闭"
	min_size = Vector2i(820, 700)
	_build()
	await _refresh()


func _build() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	# 搜索行：圆角输入框 + 只看收藏
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	root.add_child(row)
	_search = LineEdit.new()
	_search.placeholder_text = "搜索 ID、曲名、罗马音、艺术家…（也可粘贴谱面链接/ID）"
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.custom_minimum_size = Vector2(0, 34)
	_search.add_theme_font_size_override("font_size", 14)
	_search.text_submitted.connect(func(_t: String) -> void: _refresh())
	_search.text_changed.connect(_on_search_changed)
	row.add_child(_search)
	_favorites_button = Button.new()
	_favorites_button.text = "☆ 收藏"
	_favorites_button.toggle_mode = true
	_favorites_button.custom_minimum_size = Vector2(96, 34)
	_favorites_button.tooltip_text = "只看已收藏的谱面"
	_favorites_button.toggled.connect(func(on: bool) -> void:
		_favorites_only = on
		_fill_cards()
	)
	row.add_child(_favorites_button)
	_filter_button = Button.new()
	_filter_button.text = "筛选"
	_filter_button.toggle_mode = true
	_filter_button.custom_minimum_size = Vector2(88, 34)
	_filter_button.tooltip_text = "按 osu! 官方的类型 / 语言 / 标签过滤"
	_filter_button.toggled.connect(_on_filter_toggled)
	row.add_child(_filter_button)

	# 筛选行：类型 / 语言 / 标签（默认收起）
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
			_tag_timer.timeout.connect(_fill_cards)
			add_child(_tag_timer)
		_tag_timer.start()
	)
	_filters_row.add_child(_tag_filter)

	_more_button = Button.new()
	_more_button.text = "加载更多"
	_more_button.visible = false
	_more_button.custom_minimum_size = Vector2(0, 32)
	_more_button.pressed.connect(_load_more)
	root.add_child(_more_button)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_scroll)
	_cards = VBoxContainer.new()
	_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards.add_theme_constant_override("separation", int(CARD_SEP))
	_scroll.add_child(_cards)
	# 滚到底自动加载下一页（信号里不能直接 await 协程，用 call_deferred 起一个）。
	_scroll.get_v_scroll_bar().value_changed.connect(func(value: float) -> void:
		var bar := _scroll.get_v_scroll_bar()
		if _has_more and not _loading_more and value >= bar.max_value - bar.page - 120.0:
			_load_more.call_deferred()
	)

	_progress = ProgressBar.new()
	_progress.max_value = 100.0
	_progress.show_percentage = true
	_progress.custom_minimum_size = Vector2(0, 8)
	_progress.visible = false
	root.add_child(_progress)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 12)
	_status.add_theme_color_override("font_color", UITheme.MUTED)
	root.add_child(_status)


func _on_filter_toggled(on: bool) -> void:
	_filter_open = on
	_filters_row.visible = on
	_filter_button.text = "筛选 ●" if on and _has_filters() else "筛选"
	_fill_cards()


func _has_filters() -> bool:
	return _genre_filter > 0 or _language_filter != 0 or not tag_tokens(_tag_filter.text if _tag_filter != null else "").is_empty()


func _on_search_changed(_text: String) -> void:
	# 输入防抖交给定时器，避免每个字符都打一次网络。
	if not is_inside_tree():
		return
	if _search.text.strip_edges().length() >= 3 or not _search.text.strip_edges().is_empty():
		if _debounce == null:
			_debounce = Timer.new()
			_debounce.one_shot = true
			_debounce.wait_time = 0.45
			_debounce.timeout.connect(func() -> void: await _refresh())
			add_child(_debounce)
		_debounce.start()


var _debounce: Timer = null


# ---------------------------------------------------------------- 搜索

func _refresh() -> void:
	if _busy:
		return
	var query := _search.text.strip_edges()
	var tags_text := _tag_filter.text if _tag_filter != null else ""
	if query.is_empty() and not tag_tokens(tags_text).is_empty():
		# 只填了标签：拿标签当搜索词去捞候选，再在本地按标签过滤。
		query = tags_text
	if query.is_empty():
		_cards_box_clear()
		_status.text = "输入曲名 / 作者 / ID，或粘贴 osu! 谱面链接"
		return
	var direct := parse_osu_input(query)
	if not direct.is_empty():
		_items = []
		_cards_box_clear()
		var kind_text := "谱面包" if String(direct.get("kind", "set")) == "set" else "单谱面（自动找所属谱面包）"
		_has_more = false
		_update_more_button()
		_status.text = "识别为%s #%d — 回车或点击卡片开始下载" % [kind_text, int(direct.get("id", 0))]
		_add_card({
			"id": int(direct.get("id", 0)),
			"title": "直接下载 " + kind_text,
			"artist": "#%d" % int(direct.get("id", 0)),
			"beatmaps": [],
			"covers": {},
			"_direct": direct,
		})
		return
	if query == _query and not _items.is_empty():
		_fill_cards()
		return
	_busy = true
	_items = []
	_offset = 0
	_has_more = false
	_cards_box_clear()
	_status.text = "正在搜索「%s」…" % query
	await _fetch_page(query)
	_busy = false
	if _fetch_error:
		_status.text = "搜索失败（网络不通或镜像超时）"
		return
	_query = query
	_fill_cards()
	_update_more_button()


## 拉一页（amount=PAGE_SIZE, offset=_offset），把新的谱面包追加进 _items。
## 返回新增条数；-1 表示请求失败。
## 拉一页（amount=PAGE_SIZE, offset=_offset），新谱面包追加进 _items 并返回它们。
## 失败时置 _fetch_error 并返回空数组。
func _fetch_page(query: String) -> Array:
	_fetch_error = false
	var url := SEARCH_URL % query.uri_encode()
	url = url.replace("amount=25", "amount=%d" % PAGE_SIZE) + "&offset=%d" % _offset
	var bytes := await _http_get(url, "搜索 osu!")
	if bytes.is_empty():
		_fetch_error = true
		return []
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if not parsed is Array:
		_fetch_error = true
		return []
	var raw_count := 0
	var added: Array = []
	for item in parsed:
		if not item is Dictionary:
			continue
		raw_count += 1
		var entry: Dictionary = item
		if osu_std_count(entry) <= 0:
			continue
		var set_id := int(entry.get("id", 0))
		if _items.any(func(existing: Dictionary) -> bool: return int(existing.get("id", 0)) == set_id):
			continue
		_items.append(entry)
		added.append(entry)
	_offset += PAGE_SIZE
	# 这一页不满 → 数据库见底了
	_has_more = raw_count >= PAGE_SIZE
	return added


func _load_more() -> void:
	if _busy or _loading_more or not _has_more:
		return
	_loading_more = true
	var query := _query if not _query.is_empty() else _search.text.strip_edges()
	_set_more_button("正在加载…")
	var added: Array = await _fetch_page(query)
	_loading_more = false
	if _fetch_error:
		_set_more_button("加载失败，点我再试")
		return
	# 只追加新卡片：不重建整张列表，已经加载好的封面不会被打回队列。
	_append_cards(added)
	_update_more_button()


func _update_more_button() -> void:
	if _more_button == null:
		return
	_more_button.visible = _has_more
	if _has_more:
		_more_button.text = "加载更多（已加载 %d 个）" % _items.size()


func _set_more_button(text: String) -> void:
	if _more_button == null:
		return
	_more_button.visible = true
	_more_button.text = text


## 全量重建（搜索 / 筛选 / 收藏变化时用）。
func _fill_cards() -> void:
	_cards_box_clear()
	_shown_count = 0
	_filtered_count = 0
	for entry in _items:
		_append_card_if_visible(entry)
	_update_status()


## 追加新一页（“加载更多”用）。
func _append_cards(entries: Array) -> void:
	for entry in entries:
		_append_card_if_visible(entry)
	_update_status()


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
	if _filter_button != null:
		_filter_button.text = "筛选 ●" if _filter_open and _has_filters() else "筛选"
	if _shown_count == 0:
		if _favorites_only:
			_status.text = "没有收藏的谱面（点卡片右侧的 ☆ 收藏）"
		elif _filtered_count > 0:
			_status.text = "当前筛选项把 %d 个结果全过滤掉了" % _filtered_count
		else:
			_status.text = "没有结果"
		return
	var suffix := "，筛选掉 %d 个" % _filtered_count if _filtered_count > 0 else ""
	var more := "（还有更多，滚到底或点下面按钮继续）" if _has_more else ""
	_status.text = "%d 个谱面包%s%s（点卡片下载整包，导入后能切难度）" % [_shown_count, suffix, more]


func _cards_box_clear() -> void:
	for job in _cover_queue:
		_cover_pending.erase(int(job.get("id", 0)))
	_cover_queue.clear()
	for child in _cards.get_children():
		_cards.remove_child(child)
		child.queue_free()


func _add_card(entry: Dictionary) -> void:
	var card := BeatmapCard.new()
	card.setup(entry, _is_favorite(int(entry.get("id", 0))))
	card.custom_minimum_size = Vector2(0, CARD_HEIGHT)
	card.activated.connect(func(_id: int, direct: Dictionary) -> void:
		if direct.is_empty():
			_download_osu({"kind": "set", "id": int(entry.get("id", 0))})
		else:
			_download_osu(direct)
	)
	card.favorite_toggled.connect(func(set_id: int) -> void:
		_toggle_favorite(set_id)
		_fill_cards()
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
	else:
		list.append(set_id)
	app.save_settings()


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
		if code == 200 and body.size() >= 256:
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(COVER_DIR))
			var file := FileAccess.open(String(job.get("path")), FileAccess.WRITE)
			if file != null:
				file.store_buffer(body)
				file.close()
			var image := Image.new()
			if image.load_jpg_from_buffer(body) == OK or image.load_png_from_buffer(body) == OK:
				if is_instance_valid(card):
					card.set_cover(ImageTexture.create_from_image(image))
		_pump_covers()
	)
	http.request(String(job.get("url")))


# ---------------------------------------------------------------- 下载

func _download_osu(entry: Dictionary) -> void:
	if _busy:
		return
	var kind := String(entry.get("kind", "set"))
	var set_id := int(entry.get("id", 0))
	if set_id <= 0:
		return
	_show_progress("准备下载 #%d…" % set_id)
	_busy = true
	if kind == "beatmap":
		var resolved := await _resolve_set_id(set_id)
		if resolved <= 0:
			_finish_progress("解析谱面 #%d 失败" % set_id)
			_busy = false
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
		return
	_finish_progress("下载完成，开始转谱")
	source_ready.emit(target)
	hide()


func _download_osz(set_id: int) -> String:
	var folder := "user://imports/osu_%d/" % set_id
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var target := folder + "chart.osz"
	for template in DOWNLOAD_URLS:
		_set_progress_text("下载 osu! 谱面（#%d）…" % set_id)
		var bytes := await _http_get(String(template) % set_id, "下载 osu! 谱面", 120.0)
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


func _http_get(url: String, label: String = "", timeout_sec: float = 40.0) -> PackedByteArray:
	var http := HTTPRequest.new()
	http.timeout = timeout_sec
	add_child(http)
	if not label.is_empty():
		_set_progress_text("%s…" % label)
	var err := http.request(url)
	if err != OK:
		http.queue_free()
		return PackedByteArray()
	var result: Array = await http.request_completed
	http.queue_free()
	if result.size() < 4:
		return PackedByteArray()
	if int(result[1]) != 200:
		return PackedByteArray()
	var body: PackedByteArray = result[3]
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
	if _progress_bar != null:
		_progress_bar.value = fmod(_progress_bar.value + 12.0, 100.0)
	if _status != null:
		_status.text = text


func _finish_progress(text: String) -> void:
	if _progress_window != null:
		_progress_window.hide()
	if _status != null:
		_status.text = text


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
		draw_string(UITheme.mono_font(), Vector2(text_x, 56), _elide("%s · %d 个难度" % [artist, difficulties.size()], text_width, 12), HORIZONTAL_ALIGNMENT_LEFT, text_width, 12, UITheme.MUTED)
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
