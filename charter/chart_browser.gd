class_name ChartBrowser
extends AcceptDialog

signal chart_imported

var _search: LineEdit
var _version: OptionButton
var _genre: OptionButton
var _list: ItemList
var _status: Label
var _entries: Array = []
var _source: OptionButton
var _maj_items: Array = []
var _diff_dialog: ConfirmationDialog
var _diff_list: ItemList
var _pending_maidata: String = ""
var _search_timer: Timer
var _request_serial: int = 0
var _specs: Dictionary = {}

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
		var spec: Dictionary = _specs.get(slug, {})
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
	if _source != null and _source.selected == 1:
		_download_majdata(slug)
		return
	var spec: Dictionary = _specs.get(slug, {})
	var files: Array = spec.get("files", [])
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
		return
	_choose_difficulty(maidata)

func _fetch_bytes(url: String, label: String = "") -> PackedByteArray:
	if url.contains("majdata.net"):
		# Godot 的 HTTPRequest 会被 majdata 的 Cloudflare 挂住；curl 正常。
		var tmp := "user://majdata_tmp.bin"
		var output: Array = []
		var code := OS.execute("curl", ["-sL", "--max-time", "25", "-A", "Mozilla/5.0", "-e", "https://majdata.net/", "-o", ProjectSettings.globalize_path(tmp), url], output, true, false)
		if code != 0 or not FileAccess.file_exists(tmp):
			return PackedByteArray()
		var data := FileAccess.get_file_as_bytes(tmp)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
		if not label.is_empty():
			_status.text = "%s  %.0f KB" % [label, float(data.size()) / 1024.0]
		return data
	var http := HTTPRequest.new()
	add_child(http)
	var done := false
	var result: Array = []
	http.request_completed.connect(func(r: Array) -> void:
		result = r
		done = true
	)
	http.request(url, ["Referer: https://majdata.net/", "User-Agent: Mozilla/5.0"])
	while not done:
		await get_tree().process_frame
		if not label.is_empty():
			var got := http.get_downloaded_bytes()
			_status.text = "%s  %.0f KB" % [label, float(got) / 1024.0]
	http.queue_free()
	if int(result[0]) != HTTPRequest.RESULT_SUCCESS or int(result[1]) < 200 or int(result[1]) >= 300:
		# 一次重试，避开 majdata 偶发的空响应/限流。
		var retry := HTTPRequest.new()
		add_child(retry)
		retry.request(url, ["Referer: https://majdata.net/", "User-Agent: Mozilla/5.0"])
		var rr: Array = await retry.request_completed
		retry.queue_free()
		if int(rr[0]) == HTTPRequest.RESULT_SUCCESS and int(rr[1]) == 200:
			return rr[3]
		return PackedByteArray()
	return result[3]


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
		return
	_choose_difficulty(maidata)


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
