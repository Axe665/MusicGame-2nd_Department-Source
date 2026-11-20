class_name AlphaCommand
extends RefCounted

## 环上的“演出指令”：判定线（JLINE）、文本（TEXT / JUDGETEXT）与滤镜。
##
## 一条指令 = 名字 + 起始拍 + 持续拍数 + 参数表。预览按拍采样出包络
## （起势 attack → 保持 → 收势 release），同名的多条指令取包络最强的一条，
## 与 MajdataPlay 的 AlphaVisualTimeline 行为一致。
##
## 这层只做纯数据与采样，不碰渲染；编辑器（环编辑工作区）和预览
## （Preview3D）都从这里取数，保证“编辑里看到的”和“导出的”是同一套。

const CATEGORY_JLINE := "jline"
const CATEGORY_TEXT := "text"
const CATEGORY_FILTER := "filter"

const CATEGORY_LABELS := {
	CATEGORY_JLINE: "判定线",
	CATEGORY_TEXT: "文本",
	CATEGORY_FILTER: "滤镜",
}

## 指令目录。params 里每个参数：
##   key/label/type(float|int|bool|color|text|option)/default/min/max/step/options/hint
## stateful = 开关型指令：起始拍立即满强度、不做起手过渡，但到 duration 结束拍就停（不会永久挂住）。
## instant = 瞬时指令：duration 固定为 0，只触发一次。
const CATALOG := [
	{
		"name": "JLINE",
		"label": "判定线样式",
		"category": CATEGORY_JLINE,
		"duration": 1.0,
		"hint": "改判定线颜色 / 粗细 / 透明度；expand 让环向外扩张一圈。",
		"params": [
			{"key": "color", "label": "颜色", "type": "color", "default": "#66e0ff"},
			{"key": "width", "label": "粗细 px", "type": "float", "default": 6.0, "min": 0.5, "max": 24.0, "step": 0.5},
			{"key": "alpha", "label": "不透明度", "type": "float", "default": 1.0, "min": 0.0, "max": 1.0, "step": 0.05},
			{"key": "expand", "label": "扩张", "type": "float", "default": 0.0, "min": 0.0, "max": 1.0, "step": 0.05},
		],
	},
	{
		"name": "TEXT",
		"label": "显示文本",
		"category": CATEGORY_TEXT,
		"duration": 1.0,
		"hint": "在舞台中央打一行字；x/y 是 -1…1 的归一化位置。",
		"params": [
			{"key": "content", "label": "文字", "type": "text", "default": "TEXT"},
			{"key": "size", "label": "字号", "type": "float", "default": 48.0, "min": 10.0, "max": 200.0, "step": 2.0},
			{"key": "x", "label": "X", "type": "float", "default": 0.0, "min": -1.0, "max": 1.0, "step": 0.01},
			{"key": "y", "label": "Y", "type": "float", "default": 0.0, "min": -1.0, "max": 1.0, "step": 0.01},
			{"key": "color", "label": "颜色", "type": "color", "default": "#ffffff"},
			{"key": "alpha", "label": "不透明度", "type": "float", "default": 1.0, "min": 0.0, "max": 1.0, "step": 0.05},
		],
	},
	{
		"name": "JUDGETEXT",
		"label": "判定文字透明度",
		"category": CATEGORY_TEXT,
		"duration": 1.0,
		"hint": "控制 PERFECT / GREAT 等判定文字的可见度；0 等于关掉。",
		"params": [
			{"key": "alpha", "label": "不透明度", "type": "float", "default": 1.0, "min": 0.0, "max": 1.0, "step": 0.05},
		],
	},
	{
		"name": "FLASH",
		"label": "闪白",
		"category": CATEGORY_FILTER,
		"duration": 1.0,
		"params": [
			{"key": "strength", "label": "强度", "type": "float", "default": 0.8, "min": 0.0, "max": 1.0, "step": 0.05},
		],
	},
	{
		"name": "FADE",
		"label": "闪黑",
		"category": CATEGORY_FILTER,
		"duration": 1.0,
		"params": [
			{"key": "strength", "label": "强度", "type": "float", "default": 0.8, "min": 0.0, "max": 1.0, "step": 0.05},
		],
	},
	{
		"name": "BRIGHTNESS",
		"label": "亮度",
		"category": CATEGORY_FILTER,
		"duration": 1.0,
		"params": [
			{"key": "value", "label": "增减", "type": "float", "default": 0.5, "min": -1.0, "max": 1.0, "step": 0.05},
		],
	},
	{
		"name": "SATURATION",
		"label": "饱和度",
		"category": CATEGORY_FILTER,
		"duration": 1.0,
		"params": [
			{"key": "value", "label": "增减", "type": "float", "default": 0.5, "min": -1.0, "max": 1.0, "step": 0.05},
		],
	},
	{
		"name": "CONTRAST",
		"label": "对比度",
		"category": CATEGORY_FILTER,
		"duration": 1.0,
		"params": [
			{"key": "value", "label": "倍率", "type": "float", "default": 1.2, "min": 0.0, "max": 2.0, "step": 0.05},
		],
	},
	{
		"name": "HUE",
		"label": "色相偏移",
		"category": CATEGORY_FILTER,
		"duration": 1.0,
		"params": [
			{"key": "value", "label": "角度", "type": "float", "default": 45.0, "min": -180.0, "max": 180.0, "step": 5.0},
		],
	},
	{
		"name": "ZOOM",
		"label": "镜头缩放",
		"category": CATEGORY_FILTER,
		"duration": 1.0,
		"params": [
			{"key": "value", "label": "倍率", "type": "float", "default": 1.5, "min": 0.5, "max": 3.0, "step": 0.05},
		],
	},
	{
		"name": "SHAKE",
		"label": "画面震动",
		"category": CATEGORY_FILTER,
		"duration": 1.0,
		"params": [
			{"key": "strength", "label": "幅度", "type": "float", "default": 0.5, "min": 0.0, "max": 1.0, "step": 0.05},
			{"key": "frequency", "label": "频率", "type": "float", "default": 12.0, "min": 1.0, "max": 40.0, "step": 1.0},
		],
	},
	{
		"name": "VIGNETTE",
		"label": "暗角",
		"category": CATEGORY_FILTER,
		"duration": 1.0,
		"params": [
			{"key": "strength", "label": "强度", "type": "float", "default": 0.6, "min": 0.0, "max": 1.0, "step": 0.05},
		],
	},
	{
		"name": "GLITCH",
		"label": "故障",
		"category": CATEGORY_FILTER,
		"duration": 1.0,
		"params": [
			{"key": "strength", "label": "强度", "type": "float", "default": 0.5, "min": 0.0, "max": 1.0, "step": 0.05},
		],
	},
	{
		"name": "PIXELATE",
		"label": "像素化",
		"category": CATEGORY_FILTER,
		"duration": 1.0,
		"params": [
			{"key": "size", "label": "像素块", "type": "float", "default": 8.0, "min": 1.0, "max": 64.0, "step": 1.0},
		],
	},
	{
		"name": "RADIALBLUR",
		"label": "径向模糊",
		"category": CATEGORY_FILTER,
		"duration": 1.0,
		"params": [
			{"key": "strength", "label": "强度", "type": "float", "default": 0.5, "min": 0.0, "max": 1.0, "step": 0.05},
		],
	},
	{
		"name": "RIPPLE",
		"label": "波纹",
		"category": CATEGORY_FILTER,
		"duration": 1.0,
		"params": [
			{"key": "strength", "label": "幅度", "type": "float", "default": 0.5, "min": 0.0, "max": 1.0, "step": 0.05},
			{"key": "frequency", "label": "频率", "type": "float", "default": 8.0, "min": 1.0, "max": 32.0, "step": 1.0},
		],
	},
	{
		"name": "INVERT",
		"label": "反色",
		"category": CATEGORY_FILTER,
		"duration": 1.0,
		"params": [
			{"key": "strength", "label": "强度", "type": "float", "default": 1.0, "min": 0.0, "max": 1.0, "step": 0.05},
		],
	},
	{
		"name": "POSTERIZE",
		"label": "色阶",
		"category": CATEGORY_FILTER,
		"duration": 1.0,
		"params": [
			{"key": "levels", "label": "级数", "type": "float", "default": 6.0, "min": 2.0, "max": 64.0, "step": 1.0},
		],
	},
	{
		"name": "KALEIDOSCOPE",
		"label": "万花筒",
		"category": CATEGORY_FILTER,
		"duration": 2.0,
		"stateful": true,
		"params": [
			{"key": "segments", "label": "份数", "type": "float", "default": 6.0, "min": 2.0, "max": 16.0, "step": 1.0},
			{"key": "on", "label": "开启", "type": "bool", "default": true},
		],
	},
	{
		"name": "BLOOM",
		"label": "泛光",
		"category": CATEGORY_FILTER,
		"duration": 1.0,
		"params": [
			{"key": "strength", "label": "强度", "type": "float", "default": 1.5, "min": 0.0, "max": 4.0, "step": 0.1},
		],
	},
	{
		"name": "NEON",
		"label": "霓虹",
		"category": CATEGORY_FILTER,
		"duration": 1.0,
		"params": [
			{"key": "strength", "label": "强度", "type": "float", "default": 0.8, "min": 0.0, "max": 1.0, "step": 0.05},
		],
	},
	{
		"name": "ROTATE",
		"label": "画面旋转",
		"category": CATEGORY_FILTER,
		"duration": 1.0,
		"params": [
			{"key": "value", "label": "角度", "type": "float", "default": 10.0, "min": -180.0, "max": 180.0, "step": 5.0},
		],
	},
	{
		"name": "RAINBOW",
		"label": "彩虹",
		"category": CATEGORY_FILTER,
		"duration": 1.0,
		"params": [
			{"key": "strength", "label": "强度", "type": "float", "default": 0.6, "min": 0.0, "max": 1.0, "step": 0.05},
		],
	},
	{
		"name": "LENSDISTORT",
		"label": "镜头畸变",
		"category": CATEGORY_FILTER,
		"duration": 1.0,
		"params": [
			{"key": "value", "label": "畸变", "type": "float", "default": 0.3, "min": -1.0, "max": 1.0, "step": 0.05},
		],
	},
	{
		"name": "SPLIT",
		"label": "色差分离",
		"category": CATEGORY_FILTER,
		"duration": 1.0,
		"params": [
			{"key": "offset", "label": "偏移", "type": "float", "default": 0.1, "min": 0.0, "max": 1.0, "step": 0.01},
		],
	},
	{
		"name": "TINT",
		"label": "染色",
		"category": CATEGORY_FILTER,
		"duration": 1.0,
		"params": [
			{"key": "color", "label": "颜色", "type": "color", "default": "#ff66cc"},
			{"key": "strength", "label": "强度", "type": "float", "default": 0.5, "min": 0.0, "max": 1.0, "step": 0.05},
		],
	},
	{
		"name": "MOVE",
		"label": "画面位移",
		"category": CATEGORY_FILTER,
		"duration": 1.0,
		"params": [
			{"key": "x", "label": "X", "type": "float", "default": 0.0, "min": -1.0, "max": 1.0, "step": 0.01},
			{"key": "y", "label": "Y", "type": "float", "default": 0.0, "min": -1.0, "max": 1.0, "step": 0.01},
		],
	},
]

## 旧谱面里已经写下的近义指令，读取时折叠到保留的那一条。
## 雪花噪点/碎裂 归到故障，高斯模糊/拖影 归到径向模糊，避免同一效果四五个名字。
const ALIASES := {
	"TVNOISE": "GLITCH",
	"SHATTER": "GLITCH",
	"GAUSSIAN": "RADIALBLUR",
	"TRAIL": "RADIALBLUR",
}

var id: String = ""
var name: String = ""
var beat: float = 0.0
var duration: float = 1.0
var easing: String = "linear"
var params: Dictionary = {}
var enabled: bool = true


func _init(command_name: String = "", at_beat: float = 0.0) -> void:
	if not command_name.is_empty():
		name = command_name
		params = defaults(command_name)
		duration = default_duration(command_name)
	beat = at_beat


func spec() -> Dictionary:
	return spec_of(name)


func category() -> String:
	return String(spec().get("category", CATEGORY_FILTER))


func category_label() -> String:
	return String(CATEGORY_LABELS.get(category(), category()))


func label() -> String:
	return String(spec().get("label", name))


func hint() -> String:
	return String(spec().get("hint", ""))


func is_stateful() -> bool:
	return bool(spec().get("stateful", false))


func end_beat() -> float:
	return beat + maxf(0.0, duration)


func duration_beats() -> float:
	return maxf(0.0, duration)


## 0..1：指令内部的时间进度；duration 为 0 时视为已完成。
func progress_at(at_beat: float) -> float:
	if duration <= 0.0001:
		return 1.0 if at_beat >= beat else 0.0
	return clampf((at_beat - beat) / duration, 0.0, 1.0)


## 三段包络：起势 → 保持 → 收势。起势/收势默认各占 1/4，可用 attack/release 覆盖。
func envelope_at(at_beat: float) -> float:
	if not enabled:
		return 0.0
	if at_beat < beat - 0.0001:
		return 0.0
	if is_stateful():
		# 开关型同样受 duration 限制：起始立即生效，到结束拍就停，不会一直挂在画面上。
		return 1.0 if at_beat <= end_beat() + 0.0001 else 0.0
	if duration <= 0.0001:
		# 瞬时指令：只在起始拍附近有效；给半拍宽限，方便在时间轴上看见。
		return 1.0 if at_beat <= beat + 0.5 else 0.0
	var attack := clampf(float(params.get("attack", 0.25)), 0.0, 0.9)
	var release := clampf(float(params.get("release", 0.25)), 0.0, 0.9)
	if attack + release > 0.98:
		release = maxf(0.0, 0.98 - attack)
	var progress := progress_at(at_beat)
	if progress >= 1.0:
		return 0.0
	if attack > 0.0001 and progress < attack:
		return ease_value(progress / attack)
	if release > 0.0001 and progress > 1.0 - release:
		return ease_value((1.0 - progress) / release)
	return 1.0


## 包络曲线。linear 之外只保留演出里常用的几种。
func ease_value(x: float) -> float:
	var t := clampf(x, 0.0, 1.0)
	match easing:
		"ease_in":
			return t * t
		"ease_out":
			return 1.0 - (1.0 - t) * (1.0 - t)
		"ease_in_out":
			return t * t * (3.0 - 2.0 * t)
		"expo_in":
			return t * t * t
		"expo_out":
			return 1.0 - pow(1.0 - t, 3.0)
		_:
			return t


func number(key: String, fallback: float = 0.0) -> float:
	var raw: Variant = params.get(key, fallback)
	if raw is float or raw is int:
		return float(raw)
	return fallback


func flag(key: String, fallback: bool = false) -> bool:
	return bool(params.get(key, fallback))


func text_value(key: String, fallback: String = "") -> String:
	return String(params.get(key, fallback))


func color_value(key: String, fallback: Color = Color.WHITE) -> Color:
	var text := String(params.get(key, ""))
	if text.is_empty() or not Color.html_is_valid(text):
		return fallback
	return Color(text)


func summary() -> String:
	var text := label()
	match name:
		"TEXT":
			text = "「%s」" % String(params.get("content", ""))
		"JLINE":
			text = "判定线 %s" % String(params.get("color", ""))
		_:
			for entry in Array(spec().get("params", [])):
				var key := String(entry.get("key", ""))
				if key == "strength" or key == "value" or key == "size" or key == "segments":
					text += " %.2f" % number(key)
					break
	return text


func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": canonical(name),
		"beat": snappedf(beat, 0.001),
		"duration": snappedf(duration, 0.001),
		"easing": easing,
		"params": params.duplicate(true),
		"enabled": enabled,
	}


static func from_dict(raw: Dictionary) -> AlphaCommand:
	var command := AlphaCommand.new()
	command.id = String(raw.get("id", ""))
	command.name = canonical(String(raw.get("name", "")))
	command.beat = float(raw.get("beat", 0.0))
	command.duration = float(raw.get("duration", default_duration(command.name)))
	command.easing = String(raw.get("easing", "linear"))
	command.enabled = bool(raw.get("enabled", true))
	command.params = defaults(command.name)
	var stored: Variant = raw.get("params", {})
	if stored is Dictionary:
		for key in (stored as Dictionary).keys():
			command.params[String(key)] = (stored as Dictionary)[key]
	command.params = normalize(command.name, command.params)
	# 旧谱里的状态指令时长是 0，按新语义会立刻结束；补成目录默认时长。
	if command.duration <= 0.0001:
		command.duration = maxf(default_duration(command.name), 0.25)
	return command


## 把历史别名折叠成目录里保留下来的名字；未知名字原样返回。
static func canonical(command_name: String) -> String:
	var upper := command_name.strip_edges().to_upper()
	return String(ALIASES.get(upper, upper))


static func spec_of(command_name: String) -> Dictionary:
	var target := canonical(command_name)
	for entry in CATALOG:
		if String(entry.get("name", "")) == target:
			return entry
	return {}


static func catalog(category: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in CATALOG:
		if String(entry.get("category", "")) == category:
			result.append(entry)
	return result


static func names(category: String) -> Array[String]:
	var result: Array[String] = []
	for entry in catalog(category):
		result.append(String(entry.get("name", "")))
	return result


static func default_duration(command_name: String) -> float:
	var entry := spec_of(command_name)
	if entry.is_empty():
		return 1.0
	return float(entry.get("duration", 1.0))


static func defaults(command_name: String) -> Dictionary:
	var result := {}
	for entry in Array(spec_of(command_name).get("params", [])):
		result[String(entry.get("key", ""))] = entry.get("default", 0.0)
	return result


## 按目录裁剪参数：补默认值、夹范围、丢弃目录外的键。
static func normalize(command_name: String, raw: Dictionary) -> Dictionary:
	var result := defaults(command_name)
	for entry in Array(spec_of(command_name).get("params", [])):
		var key := String(entry.get("key", ""))
		if not raw.has(key):
			continue
		var value: Variant = raw[key]
		match String(entry.get("type", "float")):
			"float", "int":
				var amount := float(value)
				amount = clampf(amount, float(entry.get("min", -1e9)), float(entry.get("max", 1e9)))
				result[key] = amount
			"bool":
				result[key] = bool(value)
			"color":
				var text := String(value)
				result[key] = text if Color.html_is_valid(text) else String(entry.get("default", "#ffffff"))
			"option":
				var options: Array = entry.get("options", [])
				result[key] = value if options.has(value) else entry.get("default", "")
			_:
				result[key] = String(value)
	return result


## 当前拍上生效的指令（包络大于 0）。
static func active_at(commands: Array, at_beat: float) -> Array[AlphaCommand]:
	var result: Array[AlphaCommand] = []
	for command in commands:
		if command is AlphaCommand and command.envelope_at(at_beat) > 0.0:
			result.append(command)
	return result


## 同名指令取包络最强的一条：MajdataPlay 用“绝对值最大”，这里包络是 0..1。
static func strongest(commands: Array, command_name: String, at_beat: float) -> AlphaCommand:
	var best: AlphaCommand = null
	var best_value := 0.0
	for entry in commands:
		if not (entry is AlphaCommand):
			continue
		var command := entry as AlphaCommand
		if command.name != command_name:
			continue
		var value := command.envelope_at(at_beat)
		if value > best_value:
			best = command
			best_value = value
	return best


## 某条滤镜当前的有效强度：包络 × 强度参数（strength/value 任选其一）。
static func filter_strength(commands: Array, command_name: String, at_beat: float) -> float:
	var command := strongest(commands, command_name, at_beat)
	if command == null:
		return 0.0
	var envelope := command.envelope_at(at_beat)
	if command.params.has("strength"):
		return envelope * command.number("strength", 1.0)
	if command.params.has("value"):
		return envelope * command.number("value", 1.0)
	return envelope


static func filter_color(commands: Array, command_name: String, at_beat: float, fallback: Color = Color.WHITE) -> Color:
	var command := strongest(commands, command_name, at_beat)
	if command == null:
		return fallback
	return command.color_value("color", fallback)


static func enabled_commands(commands: Array[AlphaCommand]) -> Array[AlphaCommand]:
	var result: Array[AlphaCommand] = []
	for command in commands:
		if command.enabled:
			result.append(command)
	return result
