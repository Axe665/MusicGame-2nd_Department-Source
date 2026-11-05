class_name ChartBrowser
extends AcceptDialog

signal chart_imported

var _search: LineEdit
var _version: OptionButton
var _genre: OptionButton
var _list: ItemList
var _status: Label
var _progress: ProgressBar
## 下载时弹出的独立进度窗口（进度条 + 当前文件）。
var _progress_window: AcceptDialog = null
var _progress_label: Label = null
var _progress_bar: ProgressBar = null
var _entries: Array = []
var _source: OptionButton
var _maj_items: Array = []
var _diff_dialog: ConfirmationDialog
var _diff_list: ItemList
var _pending_maidata: String = ""
var _search_timer: Timer
var _request_serial: int = 0
var _specs: Dictionary = {}
## adx_specs 的键是 "11213-arty-party" 这种 id，而搜索列表给的是数字 slug，
## 这里建一张 "11213" → spec 的映射，避免新谱面查不到文件列表。
var _spec_lookup: Dictionary = {}

func _ready() -> void:
	title = "在线舞萌谱面"
	ok_button_text = "下载并导入"
	min_size = Vector2i(760, 560)
	_entries = _load_json("res://charts/adx_search.json")
	_specs = _load_json("res://charts/adx_specs.json")
	_build()
	_diff_dialog = ConfirmationDialog.new()
	_diff_dialog.title = "选择难度"
	_diff_dialog.ok_button_text = "导入"
	_diff_list = ItemList.new()
	_diff_list.custom_minimum_size = Vector2(360, 200)
	_diff_dialog.add_child(_diff_list)
	_diff_dialog.confirmed.connect(_import_chosen_difficulty)
	add_child(_diff_dialog)
	_refresh()
	confirmed.connect(_download_selected)

func _load_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return [] if path.ends_with("search.json") else {}
	return JSON.parse_string(f.get_as_text())

func _build() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var row := HBoxContainer.new()
	box.add_child(row)
	_search = LineEdit.new()
	_search.placeholder_text = "搜索曲名 / 艺术家 / 别名"
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_timer = Timer.new()
	_search_timer.one_shot = true
	_search_timer.wait_time = 0.35
	_search_timer.timeout.connect(_refresh)
	add_child(_search_timer)
	_search.text_changed.connect(func(_t: String) -> void: _search_timer.start())
	row.add_child(_search)
	_source = OptionButton.new()
	_source.add_item("adxdls")
	_source.add_item("majdata")
	_source.item_selected.connect(func(_i: int) -> void: _refresh())
	row.add_child(_source)
	_version = OptionButton.new()
	_genre = OptionButton.new()
	row.add_child(_version)
	row.add_child(_genre)
	_version.item_selected.connect(func(_i: int) -> void: _refresh())
	_genre.item_selected.connect(func(_i: int) -> void: _refresh())
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
	var versions := {}
	var genres := {}
	for slug in _specs:
		var s: Dictionary = _specs[slug]
		versions[String(s.get("groupDir", ""))] = true
		genres[String(s.get("genreDir", ""))] = true
	_version.add_item("全部版本")
	for v in versions.keys():
		_version.add_item(String(v))
	_genre.add_item("全部曲风")
	for g in genres.keys():
		_genre.add_item(String(g))

func _refresh() -> void:
	_list.clear()
	if _source != null and _source.selected == 1:
		_refresh_majdata()
		return
	var q := _search.text.strip_edges().to_lower()
	var vsel := "" if _version.selected <= 0 else _version.get_item_text(_version.selected)
	var gsel := "" if _genre.selected <= 0 else _genre.get_item_text(_genre.selected)
	var shown := 0
	for e in _entries:
		var slug := String(e.get("slug", ""))
		var spec: Dictionary = _spec_for(slug)
		if not vsel.is_empty() and String(spec.get("groupDir", "")) != vsel:
			continue
		if not gsel.is_empty() and String(spec.get("genreDir", "")) != gsel:
			continue
		var hay := (String(e.get("title", "")) + " " + String(e.get("artist", "")) + " " + " ".join(e.get("aliases", []))).to_lower()
		if not q.is_empty() and not hay.contains(q):
			continue
		_list.add_item("%s — %s  [%s]" % [String(e.get("title", "")), String(e.get("artist", "")), String(spec.get("genreDir", ""))])
		_list.set_item_metadata(_list.item_count - 1, slug)
		shown += 1
		if shown >= 500:
			break
	_status.text = "显示 %d / %d 条（adxdls）" % [shown, _entries.size()]

func _download_selected() -> void:
	var sel := _list.get_selected_items()
	if sel.is_empty():
		return
	var slug := String(_list.get_item_metadata(sel[0]))
	_show_download_progress()
	if _source != null and _source.selected == 1:
		_download_majdata(slug)
		return
	var spec: Dictionary = _spec_for(slug)
	var files: Array = spec.get("files", [])
	if files.is_empty():
		# 没有文件清单时兜底：按 adxdls 的路径规则直接拼。
		files = [
			{"name": "maidata.txt", "url": "https://adxdls.saop.cc/adxcs/%s/maidata.txt" % slug},
			{"name": "track.mp3", "url": "https://adxdls.saop.cc/adxcs/%s/track.mp3" % slug},
		]
	var folder := "user://imports/adx_%s/" % slug
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var maidata := ""
	for f in files:
		var name := String(f.get("name", ""))
		if not (name == "maidata.txt" or name.begins_with("track.") or name.begins_with("bg.")):
			continue
		var url := String(f.get("url", ""))
		if url.begins_with("/"):
			url = "https://adxdls.saop.cc" + url
		var target := folder + name
		var body := await _fetch_bytes(url, "下载 " + name)
		if body.is_empty():
			continue
		var file := FileAccess.open(target, FileAccess.WRITE)
		if file != null:
			file.store_buffer(body)
			file.close()
		if name == "maidata.txt":
			maidata = target
	if maidata.is_empty():
		_status.text = "下载失败：没有 maidata.txt"
		_hide_download_progress()
		return
	_progress.visible = true
	_progress.value = 100.0
	_status.text = "下载完成 100% · 开始导入…"
	_hide_download_progress()
	_choose_difficulty(maidata)
	_status.text = "导入完成 100%"

func _fetch_bytes(url: String, label: String = "") -> PackedByteArray:
	# 统一用 curl：adxdls 和 majdata 都可能让 Godot HTTPRequest 卡住。
	var tmp := "user://online_tmp.bin"
	var referer := "https://majdata.net/" if url.contains("majdata.net") else "https://adxdls.saop.cc/"
	var total := 0
	if label.begins_with("下载"):
		total = _content_length(url, referer)
	_begin_progress(label, total)
	var pid := OS.create_process("curl", ["-sL", "--max-time", "30", "-A", "Mozilla/5.0", "-e", referer, "-o", ProjectSettings.globalize_path(tmp), url], false)
	if pid <= 0:
		_end_progress()
		return PackedByteArray()
	var started := Time.get_ticks_msec()
	while OS.is_process_running(pid):
		_update_progress(label, _file_size(tmp), total, started)
		if Time.get_ticks_msec() - started > 45000:
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


func _show_download_progress() -> void:
	# 下载时弹出一个独立的小窗口，里面是一条进度条，直到下载完成才关闭。
	if _progress_window == null:
		_progress_window = AcceptDialog.new()
		_progress_window.title = "下载舞萌谱面"
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


func _refresh_majdata() -> void:
	_request_serial += 1
	var serial := _request_serial
	var q := _search.text.strip_edges()
	var url := "https://majdata.net/api3/api/maichart/list?sort=&page=0&search=" + q.uri_encode()
	var body := await _fetch_bytes(url, "majdata 搜索")
	if serial != _request_serial:
		return
	_maj_items = []
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if parsed is Array:
		_maj_items = parsed
	for i in _maj_items.size():
		var item: Dictionary = _maj_items[i]
		_list.add_item("%s — %s  [majdata]" % [String(item.get("title", "")), String(item.get("artist", ""))])
		_list.set_item_metadata(i, String(item.get("id", "")))
	_status.text = "majdata：%d 条（第 0 页）" % _maj_items.size()


func _download_majdata(id: String) -> void:
	var folder := "user://imports/maj_%s/" % id
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var base := "https://majdata.net/api3/api/maichart/" + id
	var maidata := folder + "maidata.txt"
	var ok := await _save(base + "/chart?intent=download", maidata, "下载 maidata")
	if ok:
		await _save(base + "/track", folder + "track.mp3", "下载音频")
		await _save(base + "/image?fullImage=true", folder + "bg.jpg", "下载背景")
	if not ok:
		_status.text = "majdata 下载失败"
		_hide_download_progress()
		return
	_progress.visible = true
	_progress.value = 100.0
	_status.text = "下载完成 100% · 开始导入…"
	_hide_download_progress()
	_choose_difficulty(maidata)
	_status.text = "导入完成 100%"


func _save(url: String, path: String, label: String = "") -> bool:
	var body := await _fetch_bytes(url, label)
	if body.is_empty():
		return false
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(body)
	f.close()
	return true


func _choose_difficulty(maidata: String) -> void:
	var diffs := SimaiIO.list_maidata(maidata)
	if diffs.is_empty():
		_status.text = "无法读取难度"
		return
	_pending_maidata = maidata
	_diff_list.clear()
	for d in diffs:
		_diff_list.add_item("%s  %s" % [String(d.get("version", "?")), String(d.get("creator", ""))])
		_diff_list.set_item_metadata(_diff_list.item_count - 1, int(d.get("index", 0)))
	_diff_list.select(0)
	_diff_dialog.popup_centered_ratio(0.4)


func _import_chosen_difficulty() -> void:
	var sel := _diff_list.get_selected_items()
	if sel.is_empty() or _pending_maidata.is_empty():
		return
	var index := int(_diff_list.get_item_metadata(sel[0]))
	var chart := SimaiIO.import_maidata(_pending_maidata, index)
	if chart == null:
		_status.text = "转换失败：%s" % SimaiIO.last_error
		return
	chart_imported.emit(chart)
	hide()
