class_name PaletteIO
extends RefCounted

## 配色预设：只包含配色组定义（name / tap / hold / path），
## 不含音符→组分配，也不含单音符覆盖——那两层属于具体谱面。
##
## 文件格式（.json，UTF-8）：
## {
##   "format": "tamaki3-palette",
##   "version": 1,
##   "name": "冷色系",
##   "groups": [ { "name": "冷色", "tap": "#33d0ff", "hold": "#7fe0c0", "path": "#8cbfff" } ]
## }

const FORMAT := "tamaki3-palette"
const VERSION := 1
const LIBRARY_DIR := "user://palettes"
const FILE_FILTER := "*.json ; 配色预设"
const MAX_NAME := 40
const BUILTIN_SCHEME := "builtin://"

static var last_error := ""


## 内置预设：随编辑器分发、只读，用来当示例或起点；用户可以「存为预设」复制到本地库再改。
static func builtin_presets() -> Array[Dictionary]:
	return [
		{
			"name": "彩虹",
			"id": BUILTIN_SCHEME + "rainbow",
			"groups": [
				{"name": "红", "tap": "#ff5069", "hold": "#ff93a1", "path": "#d63a4f"},
				{"name": "橙", "tap": "#ff8a3d", "hold": "#ffb37a", "path": "#d96a22"},
				{"name": "黄", "tap": "#ffd23d", "hold": "#ffe27a", "path": "#d9a81f"},
				{"name": "绿", "tap": "#4ade80", "hold": "#8ee9ae", "path": "#2fb463"},
				{"name": "青", "tap": "#35d6e0", "hold": "#86e9ef", "path": "#1fa8b3"},
				{"name": "蓝", "tap": "#4d8dff", "hold": "#90b6ff", "path": "#2f66d6"},
				{"name": "紫", "tap": "#a86cff", "hold": "#c9a0ff", "path": "#7f45d6"},
			],
		},
	]


static func library_dir() -> String:
	if not DirAccess.dir_exists_absolute(LIBRARY_DIR):
		DirAccess.make_dir_recursive_absolute(LIBRARY_DIR)
	return LIBRARY_DIR


static func clean_groups(raw: Variant) -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	if not (raw is Array):
		return groups
	for item in raw:
		if groups.size() >= Chart.MAX_PALETTE_GROUPS:
			break
		if not (item is Dictionary):
			continue
		groups.append(Chart.normalize_palette_group(item, groups.size() + 1))
	return groups


static func is_builtin(id: String) -> bool:
	return id.begins_with(BUILTIN_SCHEME)


static func builtin_title(id: String) -> String:
	for preset in builtin_presets():
		if String(preset.get("id", "")) == id:
			return String(preset.get("name", ""))
	return ""


static func builtin_groups(id: String) -> Array[Dictionary]:
	for preset in builtin_presets():
		if String(preset.get("id", "")) == id:
			return clean_groups(preset.get("groups", []))
	var empty: Array[Dictionary] = []
	return empty


## 读取预设：既接受本地库/文件路径，也接受 builtin:// 内置 id。
static func load_preset(id: String) -> Dictionary:
	if is_builtin(id):
		var groups := builtin_groups(id)
		var title := builtin_title(id)
		if groups.is_empty() or title.is_empty():
			return {"ok": false, "error": "内置预设不存在", "name": "", "groups": []}
		return {"ok": true, "error": "", "name": title, "groups": groups}
	return load_file(id)


static func to_dict(title: String, groups: Array) -> Dictionary:
	return {
		"format": FORMAT,
		"version": VERSION,
		"name": String(title).strip_edges().substr(0, MAX_NAME),
		"groups": clean_groups(groups),
	}


static func encode(title: String, groups: Array) -> String:
	return JSON.stringify(to_dict(title, groups), "\t", false) + "\n"


## 解析预设字典；返回 {ok, error, name, groups}。
static func parse(data: Variant) -> Dictionary:
	if not (data is Dictionary):
		return {"ok": false, "error": "文件内容不是 JSON 对象", "name": "", "groups": []}
	var object: Dictionary = data
	if String(object.get("format", "")) != FORMAT:
		return {"ok": false, "error": "不是配色预设文件（format 不是 %s）" % FORMAT, "name": "", "groups": []}
	var version := int(object.get("version", 0))
	if version > VERSION:
		return {"ok": false, "error": "预设版本过新（%d），请先升级编辑器" % version, "name": "", "groups": []}
	var groups := clean_groups(object.get("groups", []))
	if groups.is_empty():
		return {"ok": false, "error": "预设里没有可用的配色组", "name": "", "groups": []}
	var title := String(object.get("name", "")).strip_edges()
	return {"ok": true, "error": "", "name": title, "groups": groups}


static func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "文件不存在：%s" % path, "name": "", "groups": []}
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {"ok": false, "error": "文件是空的", "name": "", "groups": []}
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		return {"ok": false, "error": "JSON 解析失败：%s" % path.get_file(), "name": "", "groups": []}
	return parse(parsed)


static func save_file(path: String, title: String, groups: Array) -> Dictionary:
	var rows := clean_groups(groups)
	if rows.is_empty():
		return {"ok": false, "error": "当前没有配色组可保存"}
	var dir := path.get_base_dir()
	if not dir.is_empty() and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "写不了文件：%s" % path}
	file.store_string(encode(title, rows))
	file.close()
	return {"ok": true, "error": "", "path": path, "count": rows.size()}


static func file_name_for(title: String) -> String:
	var clean := String(title).strip_edges().substr(0, MAX_NAME)
	if clean.is_empty():
		clean = "配色预设"
	return clean.validate_filename() + ".json"


static func preset_path(title: String) -> String:
	return library_dir().path_join(file_name_for(title))


static func has_preset(title: String) -> bool:
	return FileAccess.file_exists(preset_path(title))


## 保存到本地库；同名会被覆盖（调用方负责先确认）。
static func save_preset(title: String, groups: Array) -> Dictionary:
	var rows := clean_groups(groups)
	if rows.is_empty():
		return {"ok": false, "error": "当前没有配色组可保存"}
	var path := preset_path(title)
	var overwritten := FileAccess.file_exists(path)
	var result := save_file(path, title, rows)
	if bool(result.get("ok", false)):
		result["overwritten"] = overwritten
		result["path"] = path
	return result


static func delete_preset(path: String) -> Dictionary:
	if is_builtin(path):
		return {"ok": false, "error": "内置预设不能删除；可以「保存为预设」复制一份再改"}
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "预设不存在"}
	var err := DirAccess.remove_absolute(path)
	if err != OK:
		return {"ok": false, "error": "删除失败（%s）" % error_string(err)}
	return {"ok": true, "error": ""}


## 本地库列表（内置预设排在最前），按名字排序：[{name, path, count, builtin}]。
static func list_presets() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for preset in builtin_presets():
		var groups := clean_groups(preset.get("groups", []))
		if groups.is_empty():
			continue
		result.append({
			"name": String(preset.get("name", "")),
			"path": String(preset.get("id", "")),
			"count": groups.size(),
			"builtin": true,
		})
	var dir := library_dir()
	var files := DirAccess.get_files_at(dir)
	for file_name in files:
		if file_name.get_extension().to_lower() != "json":
			continue
		var path := dir.path_join(file_name)
		var loaded := load_file(path)
		var title := String(loaded.get("name", ""))
		if title.is_empty():
			title = file_name.get_basename()
		result.append({
			"name": title,
			"path": path,
			"count": Array(loaded.get("groups", [])).size(),
			"builtin": false,
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("name", "")).naturalnocasecmp_to(String(b.get("name", ""))) < 0
	)
	return result
