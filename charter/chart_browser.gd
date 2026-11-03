class_name ChartBrowser
extends AcceptDialog

signal chart_imported

var _search: LineEdit
var _version: OptionButton
var _genre: OptionButton
var _list: ItemList
var _status: Label
var _entries: Array = []
var _specs: Dictionary = {}

func _ready() -> void:
	title = "在线舞萌谱面"
	ok_button_text = "下载并导入"
	min_size = Vector2i(760, 560)
	_entries = _load_json("res://charts/adx_search.json")
	_specs = _load_json("res://charts/adx_specs.json")
	_build()
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
	_search.text_changed.connect(func(_t: String) -> void: _refresh())
	row.add_child(_search)
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
		var body := await _fetch_bytes(url)
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
	var diffs := SimaiIO.list_maidata(maidata)
	var index := 0
	if not diffs.is_empty():
		index = int(diffs[-1].get("index", 0))
	var chart := SimaiIO.import_maidata(maidata, index)
	if chart == null:
		_status.text = "转换失败：%s" % SimaiIO.last_error
		return
	chart_imported.emit(chart)
	hide()

func _fetch_bytes(url: String) -> PackedByteArray:
	var http := HTTPRequest.new()
	add_child(http)
	http.request(url)
	var result: Array = await http.request_completed
	http.queue_free()
	if int(result[0]) != HTTPRequest.RESULT_SUCCESS or int(result[1]) < 200 or int(result[1]) >= 300:
		return PackedByteArray()
	return result[3]
