class_name Storyboard
extends RefCounted

## osu! storyboard（.osb / .osu 内联 [Events]）的解析与求值。
## 移植自 ppy/osu 的 LegacyStoryboardDecoder + Storyboards/Commands/*，
## 以及 osu-framework 的 DefaultEasingFunction。
##
## 解析时就把 L（loop）展开成每一轮的绝对时间段，运行时只做二分查找 + 插值。

## 绘制顺序（先画的在下）：Video 在 Background 后面（对照 lazer 的 layer depth）。
const LAYERS := ["Video", "Background", "Fail", "Pass", "Foreground", "Overlay"]
const FIELD_WIDTH := 640.0
const FIELD_HEIGHT := 480.0
const FIELD_WIDTH_WIDE := 854.0
const MAX_SEGMENTS_PER_KIND := 2048

## 一条命令：时间已展开为绝对 ms。
class Command:
	var kind_name := ""
	var start: float = 0.0
	var end: float = 0.0
	var easing: int = 0
	var from: Array = []
	var to: Array = []

	func progress(ms: float) -> float:
		var span := end - start
		if span <= 0.0001:
			return 1.0
		return clampf((ms - start) / span, 0.0, 1.0)


## 一个可绘制对象（Sprite / Animation）。
class Sprite:
	var path := ""
	var layer := "Background"
	var origin := 0
	var pos := Vector2.ZERO
	var frames := 0
	var frame_delay := 0.0
	var loop_type := 0
	var commands: Array = []
	## 未展开的 loop 块：[{start, count, commands}]
	var loops: Array = []
	## kind_name -> Array[Command]，解析结束时构建。
	var timeline: Dictionary = {}
	var first_ms := INF
	var last_ms := -INF
	## 文件里的顺序：同图层内靠后的画在上面，必须保留。
	var order: int = 0
	## 生命周期（对齐 lazer 的 StoryboardSprite.StartTime / EndTimeForDisplay）：
	## 对象只在这段时间里存在，窗口外根本不画。
	var start_time: float = 0.0
	var end_time: float = 0.0
	## 第一个 alpha 命令的起始值 / 最后一个 alpha 命令的终值（窗口外快速剔除用）。
	var first_alpha := 1.0
	var last_alpha := 1.0

	func add(command: Command) -> void:
		commands.append(command)
		first_ms = minf(first_ms, command.start)
		last_ms = maxf(last_ms, command.end)

	func build() -> void:
		timeline.clear()
		for command in commands:
			if not timeline.has(command.kind_name):
				timeline[command.kind_name] = []
			(timeline[command.kind_name] as Array).append(command)
		for key in timeline.keys():
			var list: Array = timeline[key]
			list.sort_custom(func(a: Command, b: Command) -> bool: return a.start < b.start)
			if list.size() > MAX_SEGMENTS_PER_KIND:
				list.resize(MAX_SEGMENTS_PER_KIND)
		first_alpha = 1.0
		last_alpha = 1.0
		var alpha_list: Array = timeline.get("alpha", [])
		if not alpha_list.is_empty():
			first_alpha = float((alpha_list[0] as Command).from[0])
			last_alpha = float((alpha_list[alpha_list.size() - 1] as Command).to[0])
		# StartTime / EndTimeForDisplay
		var earliest := INF
		var latest := -INF
		for command in commands:
			earliest = minf(earliest, (command as Command).start)
			latest = maxf(latest, (command as Command).end)
		if commands.is_empty():
			start_time = 0.0
			end_time = -1.0
		elif not alpha_list.is_empty():
			var first_alpha_command: Command = alpha_list[0]
			var first_visible: Command = null
			for command in alpha_list:
				var c := command as Command
				if float(c.from[0]) > 0.0 or float(c.to[0]) > 0.0:
					first_visible = c
					break
			if float(first_alpha_command.from[0]) == 0.0 and first_visible != null:
				start_time = first_visible.start
			else:
				start_time = earliest
			end_time = latest
		else:
			start_time = earliest
			end_time = latest

	func visible_at(ms: float) -> bool:
		# 没有命令的 sprite 在 osu 里 IsDrawable = false，不画。
		if commands.is_empty():
			return false
		return ms >= start_time and ms <= end_time

	## 终态 / 初态缓存：命令全部结束（或还没开始）的对象状态是常量，
	## 每帧重算 700 个常驻对象太贵，这里缓存一份直接复用。
	var _final_state: Dictionary = {}
	var _final_ready := false
	var _initial_state: Dictionary = {}
	var _initial_ready := false

	func state_at(ms: float, alpha: float) -> Dictionary:
		if commands.is_empty():
			if not _final_ready:
				_final_state = Storyboard.object_state(self, 0.0, alpha)
				_final_ready = true
			return _final_state
		if ms >= last_ms:
			if not _final_ready:
				_final_state = Storyboard.object_state(self, last_ms + 0.0001, last_alpha)
				_final_ready = true
			return _final_state
		if ms <= first_ms:
			if not _initial_ready:
				_initial_state = Storyboard.object_state(self, first_ms, first_alpha)
				_initial_ready = true
			return _initial_state
		return Storyboard.object_state(self, ms, alpha)

	## 找到 ms 时刻生效的命令（二分），没有则返回 null。
	func command_at(kind: String, ms: float) -> Command:
		var list: Array = timeline.get(kind, [])
		if list.is_empty():
			return null
		var lo := 0
		var hi := list.size() - 1
		var found := -1
		while lo <= hi:
			var mid := (lo + hi) / 2
			if (list[mid] as Command).start <= ms:
				found = mid
				lo = mid + 1
			else:
				hi = mid - 1
		return list[found] if found >= 0 else null

	## 单分量命令插值（不分配数组）。
	func sample_float(kind: String, ms: float, fallback: float) -> float:
		var command := command_at(kind, ms)
		if command == null or command.from.is_empty():
			return fallback
		var a := float(command.from[0])
		var b := float(command.to[0]) if not command.to.is_empty() else a
		var progress := command.progress(ms)
		if progress >= 1.0:
			return b
		return lerpf(a, b, Easing.apply(command.easing, progress))

	## 双分量命令插值（M / V）。
	func sample_vec2(kind: String, ms: float, fallback: Vector2) -> Vector2:
		var command := command_at(kind, ms)
		if command == null or command.from.is_empty():
			return fallback
		var a := Vector2(float(command.from[0]), float(command.from[1]) if command.from.size() > 1 else float(command.from[0]))
		var b := a
		if command.to.size() > 0:
			b = Vector2(float(command.to[0]), float(command.to[1]) if command.to.size() > 1 else float(command.to[0]))
		var progress := command.progress(ms)
		if progress >= 1.0:
			return b
		return a.lerp(b, Easing.apply(command.easing, progress))

	## 颜色命令插值（C 的 RGB 三段）。
	func sample_colour(ms: float) -> Color:
		var command := command_at("colour", ms)
		if command == null or command.from.size() < 3:
			return Color.WHITE
		var a := Color(float(command.from[0]), float(command.from[1]), float(command.from[2]))
		var b := a
		if command.to.size() >= 3:
			b = Color(float(command.to[0]), float(command.to[1]), float(command.to[2]))
		var progress := command.progress(ms)
		if progress >= 1.0:
			return b
		return a.lerp(b, Easing.apply(command.easing, progress))

	## 某一类命令在 ms 时刻的插值结果（各分量分别插值）。
	func sample(kind: String, ms: float) -> Array:
		var list: Array = timeline.get(kind, [])
		if list.is_empty():
			return []
		var lo := 0
		var hi := list.size() - 1
		var found := -1
		while lo <= hi:
			var mid := (lo + hi) / 2
			var command: Command = list[mid]
			if command.start <= ms:
				found = mid
				lo = mid + 1
			else:
				hi = mid - 1
		if found < 0:
			var first: Command = list[0]
			return first.from
		var current: Command = list[found]
		var t := current.progress(ms)
		if t >= 1.0:
			return current.to
		var eased := Easing.apply(current.easing, t)
		var out: Array = []
		for i in current.from.size():
			var a := float(current.from[i])
			var b := float(current.to[i]) if i < current.to.size() else a
			out.append(lerpf(a, b, eased))
		return out


## osu! 的缓动函数（移植自 osu-framework DefaultEasingFunction）。
class Easing:
	const ELASTIC_CONST := 2.0 * PI / 0.3
	const ELASTIC_CONST2 := 0.3 / 4.0
	const BACK_CONST := 1.70158
	const BACK_CONST2 := 1.70158 * 1.525
	const BOUNCE_CONST := 1.0 / 2.75
	const EXPO_OFFSET := 0.0009765625

	static func _offset_half() -> float:
		return pow(2.0, -10.0) * sin((0.5 - ELASTIC_CONST2) * ELASTIC_CONST)

	static func _offset_quarter() -> float:
		return pow(2.0, -10.0) * sin((0.25 - ELASTIC_CONST2) * ELASTIC_CONST)

	static func _offset_in_out() -> float:
		return pow(2.0, -10.0) * sin((1.0 - ELASTIC_CONST2 * 1.5) * ELASTIC_CONST / 1.5)

	static func apply(id: int, t: float) -> float:
		t = clampf(t, 0.0, 1.0)
		match id:
			1, 4:
				return t * (2.0 - t)
			2, 3:
				return t * t
			5:
				return t * t * 2.0 if t < 0.5 else 1.0 - (1.0 - t) * (1.0 - t) * 2.0
			6:
				return t * t * t
			7:
				var u := 1.0 - t
				return 1.0 - u * u * u
			8:
				if t < 0.5:
					return t * t * t * 4.0
				var u8 := 1.0 - t
				return 1.0 - u8 * u8 * u8 * 4.0
			9:
				return t * t * t * t
			10:
				var u10 := 1.0 - t
				return 1.0 - u10 * u10 * u10 * u10
			11:
				if t < 0.5:
					return t * t * t * t * 8.0
				var u11 := 1.0 - t
				return 1.0 - u11 * u11 * u11 * u11 * 8.0
			12:
				return t * t * t * t * t
			13:
				var u13 := 1.0 - t
				return 1.0 - u13 * u13 * u13 * u13 * u13
			14:
				if t < 0.5:
					return t * t * t * t * t * 16.0
				var u14 := 1.0 - t
				return 1.0 - u14 * u14 * u14 * u14 * u14 * 16.0
			15:
				return 1.0 - cos(t * PI * 0.5)
			16:
				return sin(t * PI * 0.5)
			17:
				return 0.5 - 0.5 * cos(PI * t)
			18:
				return pow(2.0, 10.0 * (t - 1.0)) + EXPO_OFFSET * (t - 1.0)
			19:
				return -pow(2.0, -10.0 * t) + 1.0 + EXPO_OFFSET * t
			20:
				if t < 0.5:
					return 0.5 * (pow(2.0, 20.0 * t - 10.0) + EXPO_OFFSET * (2.0 * t - 1.0))
				return 1.0 - 0.5 * (pow(2.0, -20.0 * t + 10.0) + EXPO_OFFSET * (-2.0 * t + 1.0))
			21:
				return 1.0 - sqrt(maxf(0.0, 1.0 - t * t))
			22:
				var u22 := 1.0 - t
				return sqrt(maxf(0.0, 1.0 - u22 * u22))
			23:
				var x := t * 2.0
				if x < 1.0:
					return 0.5 - 0.5 * sqrt(maxf(0.0, 1.0 - x * x))
				x -= 2.0
				return 0.5 * sqrt(maxf(0.0, 1.0 - x * x)) + 0.5
			24:
				return -pow(2.0, -10.0 + 10.0 * t) * sin((1.0 - ELASTIC_CONST2 - t) * ELASTIC_CONST) + pow(2.0, -11.0) * (1.0 - t)
			25:
				return pow(2.0, -10.0 * t) * sin((t - ELASTIC_CONST2) * ELASTIC_CONST) + 1.0 - pow(2.0, -11.0) * t
			26:
				return pow(2.0, -10.0 * t) * sin((0.5 * t - ELASTIC_CONST2) * ELASTIC_CONST) + 1.0 - _offset_half() * t
			27:
				return pow(2.0, -10.0 * t) * sin((0.25 * t - ELASTIC_CONST2) * ELASTIC_CONST) + 1.0 - _offset_quarter() * t
			28:
				var x28 := t * 2.0
				if x28 < 1.0:
					return -0.5 * (pow(2.0, -10.0 + 10.0 * x28) * sin((1.0 - ELASTIC_CONST2 * 1.5 - x28) * ELASTIC_CONST / 1.5) - _offset_in_out() * (1.0 - x28))
				x28 -= 1.0
				return 0.5 * (pow(2.0, -10.0 * x28) * sin((x28 - ELASTIC_CONST2 * 1.5) * ELASTIC_CONST / 1.5) - _offset_in_out() * x28) + 1.0
			29:
				return t * t * ((BACK_CONST + 1.0) * t - BACK_CONST)
			30:
				var u30 := 1.0 - t
				return u30 * u30 * ((BACK_CONST + 1.0) * u30 + BACK_CONST) + 1.0
			31:
				var x31 := t * 2.0
				if x31 < 1.0:
					return 0.5 * x31 * x31 * ((BACK_CONST2 + 1.0) * x31 - BACK_CONST2)
				x31 -= 2.0
				return 0.5 * (x31 * x31 * ((BACK_CONST2 + 1.0) * x31 + BACK_CONST2) + 2.0)
			32:
				var u32 := 1.0 - t
				if u32 < BOUNCE_CONST:
					return 1.0 - 7.5625 * u32 * u32
				if u32 < 2.0 * BOUNCE_CONST:
					u32 -= 1.5 * BOUNCE_CONST
					return 1.0 - (7.5625 * u32 * u32 + 0.75)
				if u32 < 2.5 * BOUNCE_CONST:
					u32 -= 2.25 * BOUNCE_CONST
					return 1.0 - (7.5625 * u32 * u32 + 0.9375)
				u32 -= 2.625 * BOUNCE_CONST
				return 1.0 - (7.5625 * u32 * u32 + 0.984375)
			33:
				var u33 := t
				if u33 < BOUNCE_CONST:
					return 7.5625 * u33 * u33
				if u33 < 2.0 * BOUNCE_CONST:
					u33 -= 1.5 * BOUNCE_CONST
					return 7.5625 * u33 * u33 + 0.75
				if u33 < 2.5 * BOUNCE_CONST:
					u33 -= 2.25 * BOUNCE_CONST
					return 7.5625 * u33 * u33 + 0.9375
				u33 -= 2.625 * BOUNCE_CONST
				return 7.5625 * u33 * u33 + 0.984375
			34:
				if t < 0.5:
					return 0.5 - 0.5 * apply(33, 1.0 - t * 2.0)
				return apply(33, (t - 0.5) * 2.0) * 0.5 + 0.5
			35:
				var u35 := 1.0 - t
				return u35 * pow(u35, 10.0) + 1.0
		return t


var sprites: Array = []
var background_offset := Vector2.ZERO
var widescreen := true
var source_name := ""
var referenced_files: Array[String] = []
var last_error := ""

## ── 运行时索引（性能） ────────────────────────────────────────────
## 3936 个 sprite 每帧全量求值太重：按 500ms 分桶，只查当前桶 + 常驻列表。
const BUCKET_MS := 500.0
## 一个 sprite 的可见跨度超过这个值就丢进常驻列表，避免桶里塞太多。
const BUCKET_MAX_SPAN_MS := 20000.0
var _buckets: Dictionary = {}
var _persistent: Array = []
var _index_ready := false
## 同一帧里背景层和前景层会用同一个 ms 查两次，缓存一次结果。
var _cache_ms := -INF
var _cache_result: Array[Dictionary] = []


func build_index() -> void:
	_buckets.clear()
	_persistent.clear()
	for sprite in sprites:
		var s := sprite as Sprite
		if s.commands.is_empty():
			_persistent.append(s)
			continue
		var span := s.last_ms - s.first_ms
		if span > BUCKET_MAX_SPAN_MS or s.last_alpha > 0.004:
			# 命令结束后仍然可见 → 常驻（visible_at 会用首尾 alpha 快速判断）
			_persistent.append(s)
			continue
		var from_bucket := int(floor(s.first_ms / BUCKET_MS))
		var to_bucket := int(floor(s.last_ms / BUCKET_MS))
		for b in range(from_bucket, to_bucket + 1):
			if not _buckets.has(b):
				_buckets[b] = []
			(_buckets[b] as Array).append(s)
	_index_ready = true


## 索引统计（调试/测试用）。
func index_stats() -> Dictionary:
	if not _index_ready:
		build_index()
	var bucket_sizes := 0
	for key in _buckets.keys():
		bucket_sizes = maxi(bucket_sizes, (_buckets[key] as Array).size())
	return {"buckets": _buckets.size(), "persistent": _persistent.size(), "max_bucket": bucket_sizes}


## 谱面背景图是否被 storyboard 的 Background 层替代（对照 lazer Storyboard.ReplacesBackground）。
func replaces_background(background_file: String) -> bool:
	if background_file.is_empty():
		return false
	var target := background_file.get_file().to_lower()
	for sprite in sprites:
		var s := sprite as Sprite
		if s.layer == "Background" and s.path.get_file().to_lower() == target:
			return true
	return false


## 从文本解析（.osb 或 .osu 的 [Events] 段都可）。
static func parse(text: String, source_name_in: String = "") -> Storyboard:
	var sb := Storyboard.new()
	sb.source_name = source_name_in
	var clean := text.replace("\r\n", "\n").replace("\r", "\n")
	var lines := clean.split("\n")
	var current: Sprite = null
	var loop_stack: Array = []
	var in_events := false
	var has_sections := false
	for line in lines:
		var raw := line.strip_edges()
		if raw.is_empty() or raw.begins_with("//"):
			continue
		if raw.begins_with("[") and raw.ends_with("]"):
			has_sections = true
			var section := raw.substr(1, raw.length() - 2).to_lower()
			in_events = section == "events"
			if not in_events:
				current = null
			continue
		if has_sections and not in_events:
			continue
		var depth := 0
		for ch in line:
			if ch == " " or ch == "_":
				depth += 1
			else:
				break
		var parts := raw.split(",")
		if depth == 0:
			loop_stack.clear()
			current = null
			var type := String(parts[0]).strip_edges()
			if type == "Sprite" and parts.size() >= 6:
				current = Sprite.new()
				current.layer = _clean_layer(parts[1])
				current.origin = _clean_origin(parts[2])
				current.path = _clean_path(parts[3])
				current.pos = Vector2(_float(parts[4]), _float(parts[5]))
				current.order = sb.sprites.size()
				sb.sprites.append(current)
				sb._note_reference(current.path)
			elif type == "Animation" and parts.size() >= 8:
				current = Sprite.new()
				current.layer = _clean_layer(parts[1])
				current.origin = _clean_origin(parts[2])
				current.path = _clean_path(parts[3])
				current.pos = Vector2(_float(parts[4]), _float(parts[5]))
				current.frames = maxi(1, int(_float_at(parts, 6, 1.0)))
				current.frame_delay = _float_at(parts, 7, 0.0)
				current.loop_type = int(_float_at(parts, 8, 0.0))
				current.order = sb.sprites.size()
				sb.sprites.append(current)
				sb._note_reference(current.path)
			elif type == "0" and parts.size() > 4:
				sb.background_offset = Vector2(_float(parts[3]), _float(parts[4]))
			continue
		if current == null:
			continue
		if depth == 1:
			var kind := String(parts[0]).strip_edges()
			if kind == "L" and parts.size() >= 3:
				var loop := {"start": _float(parts[1]), "count": maxi(0, int(_float(parts[2]))), "commands": []}
				current.loops.append(loop)
				loop_stack = [loop]
				continue
			if kind == "T":
				# trigger 组：忽略组内命令（大多只影响 Passing/Failing 演出）
				loop_stack.clear()
				continue
		var command := _parse_command(parts)
		if command == null:
			continue
		if loop_stack.is_empty():
			current.add(command)
		else:
			((loop_stack[0] as Dictionary)["commands"] as Array).append(command)
	for sprite in sb.sprites:
		_expand_loops(sprite)
		(sprite as Sprite).build()
	return sb


## 把每个 L 块展开成绝对时间的命令。
static func _expand_loops(sprite: Sprite) -> void:
	for loop in sprite.loops:
		var commands: Array = (loop as Dictionary)["commands"]
		if commands.is_empty() or int((loop as Dictionary)["count"]) <= 0:
			continue
		var length := 0.0
		for command in commands:
			length = maxf(length, (command as Command).end)
		if length <= 0.0:
			continue
		var start := float((loop as Dictionary)["start"])
		for iteration in int((loop as Dictionary)["count"]):
			var offset := start + float(iteration) * length
			for command in commands:
				var copy := Command.new()
				copy.kind_name = (command as Command).kind_name
				copy.start = (command as Command).start + offset
				copy.end = (command as Command).end + offset
				copy.easing = (command as Command).easing
				copy.from = (command as Command).from
				copy.to = (command as Command).to
				sprite.add(copy)


static func _parse_command(parts: PackedStringArray) -> Command:
	if parts.size() < 4:
		return null
	var kind_text := String(parts[0]).strip_edges()
	var easing := int(_float(parts[1]))
	var start := _float(parts[2])
	var end_text := String(parts[3]).strip_edges()
	var end := _float(end_text) if not end_text.is_empty() else start
	if end < start:
		end = start
	var command := Command.new()
	command.start = start
	command.end = end
	command.easing = easing
	match kind_text:
		"F":
			command.kind_name = "alpha"
			command.from = [_float_at(parts, 4, 1.0)]
			command.to = [_float_at(parts, 5, float(command.from[0]))]
		"S":
			command.kind_name = "scale"
			command.from = [_float_at(parts, 4, 1.0)]
			command.to = [_float_at(parts, 5, float(command.from[0]))]
		"V":
			command.kind_name = "vector"
			var x0 := _float_at(parts, 4, 1.0)
			var y0 := _float_at(parts, 5, 1.0)
			command.from = [x0, y0]
			command.to = [_float_at(parts, 6, x0), _float_at(parts, 7, y0)]
		"R":
			command.kind_name = "rotation"
			var r0 := _float_at(parts, 4, 0.0)
			command.from = [rad_to_deg(r0)]
			command.to = [rad_to_deg(_float_at(parts, 5, r0))]
		"M":
			command.kind_name = "move"
			var mx := _float_at(parts, 4, 0.0)
			var my := _float_at(parts, 5, 0.0)
			command.from = [mx, my]
			command.to = [_float_at(parts, 6, mx), _float_at(parts, 7, my)]
		"MX":
			command.kind_name = "x"
			command.from = [_float_at(parts, 4, 0.0)]
			command.to = [_float_at(parts, 5, float(command.from[0]))]
		"MY":
			command.kind_name = "y"
			command.from = [_float_at(parts, 4, 0.0)]
			command.to = [_float_at(parts, 5, float(command.from[0]))]
		"C":
			command.kind_name = "colour"
			var r0c := _float_at(parts, 4, 255.0)
			var g0c := _float_at(parts, 5, 255.0)
			var b0c := _float_at(parts, 6, 255.0)
			command.from = [r0c / 255.0, g0c / 255.0, b0c / 255.0]
			command.to = [_float_at(parts, 7, r0c) / 255.0, _float_at(parts, 8, g0c) / 255.0, _float_at(parts, 9, b0c) / 255.0]
		"P":
			var flag := String(parts[4]).strip_edges() if parts.size() > 4 else ""
			match flag:
				"A":
					command.kind_name = "additive"
					command.from = [1.0]
					command.to = [1.0 if start == end else 0.0]
				"H":
					command.kind_name = "flip_h"
					command.from = [1.0]
					command.to = [1.0 if start == end else 0.0]
				"V":
					command.kind_name = "flip_v"
					command.from = [1.0]
					command.to = [1.0 if start == end else 0.0]
				_:
					return null
		_:
			return null
	return command


static func _float(text: String) -> float:
	var value := text.strip_edges()
	return float(value) if not value.is_empty() else 0.0


static func _float_at(parts: PackedStringArray, index: int, fallback: float = 0.0) -> float:
	if index < 0 or index >= parts.size():
		return fallback
	var value := String(parts[index]).strip_edges()
	if value.is_empty():
		return fallback
	return float(value)


static func _clean_path(value: String) -> String:
	var path := value.strip_edges()
	if path.begins_with("\"") and path.ends_with("\"") and path.length() >= 2:
		path = path.substr(1, path.length() - 2)
	return path.replace("\\", "/").strip_edges()


static func _clean_layer(value: String) -> String:
	var layer := value.strip_edges()
	return layer if layer in LAYERS else "Background"


static func _clean_origin(value: String) -> int:
	match value.strip_edges():
		"TopLeft":
			return 0
		"TopCentre":
			return 1
		"TopRight":
			return 2
		"CentreLeft":
			return 3
		"Centre":
			return 4
		"CentreRight":
			return 5
		"BottomLeft":
			return 6
		"BottomCentre":
			return 7
		"BottomRight":
			return 8
	return 0


func _note_reference(path: String) -> void:
	if path.is_empty():
		return
	if not referenced_files.has(path):
		referenced_files.append(path)


## 写回 .osb 文本（供故事板编辑器保存 / 导出）。
func to_osb_text() -> String:
	var lines: Array[String] = ["[Events]"]
	for sprite in sprites:
		var s := sprite as Sprite
		lines.append('Sprite,%s,%s,"%s",%s,%s' % [
			s.layer, _origin_name(s.origin), s.path, _fmt(s.pos.x), _fmt(s.pos.y)])
		var ordered: Array = s.commands.duplicate()
		ordered.sort_custom(func(a: Command, b: Command) -> bool: return a.start < b.start)
		for command in ordered:
			var text := _command_text(command as Command)
			if not text.is_empty():
				lines.append(" " + text)
	return "\n".join(lines) + "\n"


static func _command_text(command: Command) -> String:
	var kind := command.kind_name
	var letter := ""
	match kind:
		"alpha":
			letter = "F"
		"scale":
			letter = "S"
		"rotation":
			letter = "R"
		"move":
			letter = "M"
		"x":
			letter = "MX"
		"y":
			letter = "MY"
		"vector":
			letter = "V"
		"colour":
			letter = "C"
		"additive":
			letter = "P,A"
		"flip_h":
			letter = "P,H"
		"flip_v":
			letter = "P,V"
		_:
			return ""
	var head := "%s,%d,%s,%s" % [letter, command.easing, _fmt(command.start), _fmt(command.end)]
	match kind:
		"rotation":
			return "%s,%s,%s" % [head, _fmt(rad_to_deg(float(command.from[0])) * 0.0 + float(command.from[0]) * PI / 180.0), _fmt(float(command.to[0]) * PI / 180.0)]
		"alpha", "scale", "x", "y":
			return "%s,%s,%s" % [head, _fmt(float(command.from[0])), _fmt(float(command.to[0]))]
		"move", "vector":
			return "%s,%s,%s,%s,%s" % [head, _fmt(float(command.from[0])), _fmt(float(command.from[1])), _fmt(float(command.to[0])), _fmt(float(command.to[1]))]
		"colour":
			return "%s,%d,%d,%d,%d,%d,%d" % [head,
				roundi(float(command.from[0]) * 255.0), roundi(float(command.from[1]) * 255.0), roundi(float(command.from[2]) * 255.0),
				roundi(float(command.to[0]) * 255.0), roundi(float(command.to[1]) * 255.0), roundi(float(command.to[2]) * 255.0)]
	return head


static func _origin_name(origin: int) -> String:
	match origin:
		1:
			return "TopCentre"
		2:
			return "TopRight"
		3:
			return "CentreLeft"
		4:
			return "Centre"
		5:
			return "CentreRight"
		6:
			return "BottomLeft"
		7:
			return "BottomCentre"
		8:
			return "BottomRight"
	return "TopLeft"


static func _fmt(value: float) -> String:
	if absf(value - roundf(value)) < 0.0005:
		return "%d" % roundi(value)
	return "%.5f" % value


## 新建一个空故事板（编辑器的「新建」用）。
static func create_blank() -> Storyboard:
	return Storyboard.new()


## 编辑器：加一个 sprite。
func add_sprite(path: String, layer: String = "Background", origin: int = 4, pos: Vector2 = Vector2(320, 240)) -> Sprite:
	var sprite := Sprite.new()
	sprite.path = path
	sprite.layer = layer
	sprite.origin = origin
	sprite.pos = pos
	sprite.order = sprites.size()
	sprites.append(sprite)
	_note_reference(path)
	return sprite


## 编辑器：给 sprite 加一条命令（时间用绝对 ms）。
func add_command(sprite: Sprite, kind: String, easing: int, start: float, end: float, from: Array, to: Array) -> Command:
	var command := Command.new()
	command.kind_name = kind
	command.easing = easing
	command.start = start
	command.end = end
	command.from = from
	command.to = to
	sprite.add(command)
	sprite.build()
	return command


## 时刻 ms 的可见对象（已按图层顺序排好）。
func sample(ms: float) -> Array[Dictionary]:
	if ms == _cache_ms:
		return _cache_result
	if not _index_ready:
		build_index()
	_cache_ms = ms
	var bucket: Array = _buckets.get(int(floor(ms / BUCKET_MS)), [])
	# 两个列表各自按文件顺序排好，这里归并一次，保证同图层里的遮挡关系不变。
	var merged: Array[Sprite] = []
	var i := 0
	var j := 0
	while i < _persistent.size() or j < bucket.size():
		var a: Sprite = _persistent[i] if i < _persistent.size() else null
		var b: Sprite = bucket[j] if j < bucket.size() else null
		if b == null or (a != null and a.order <= b.order):
			merged.append(a)
			i += 1
		else:
			merged.append(b)
			j += 1
	var result: Array[Dictionary] = []
	for sprite in merged:
		_collect(sprite, ms, result)
	_cache_result = result
	return result


func _collect(s: Sprite, ms: float, out: Array[Dictionary]) -> void:
	if not s.visible_at(ms):
		return
	# 命令窗口之外 alpha 是已知的（首/尾值），不用再查一次时间轴。
	var alpha := 1.0
	if s.commands.is_empty():
		alpha = 1.0
	elif ms >= s.last_ms:
		alpha = s.last_alpha
	elif ms <= s.first_ms:
		alpha = s.first_alpha
	else:
		var alpha_values: Array = s.sample("alpha", ms)
		alpha = float(alpha_values[0]) if not alpha_values.is_empty() else 1.0
	if alpha <= 0.004:
		return
	out.append(s.state_at(ms, alpha))


## 单个对象在 ms 时刻的状态（测试直接用它）。
static func object_state(sprite: Sprite, ms: float, alpha: float) -> Dictionary:
	var pos := sprite.pos
	if sprite.timeline.has("move"):
		pos = sprite.sample_vec2("move", ms, pos)
	if sprite.timeline.has("x"):
		pos.x = sprite.sample_float("x", ms, pos.x)
	if sprite.timeline.has("y"):
		pos.y = sprite.sample_float("y", ms, pos.y)
	var scale := Vector2.ONE
	if sprite.timeline.has("scale"):
		scale = Vector2.ONE * sprite.sample_float("scale", ms, 1.0)
	if sprite.timeline.has("vector"):
		scale = sprite.sample_vec2("vector", ms, scale)
	var rotation := 0.0
	if sprite.timeline.has("rotation"):
		rotation = sprite.sample_float("rotation", ms, 0.0)
	var colour := Color.WHITE
	if sprite.timeline.has("colour"):
		colour = sprite.sample_colour(ms)
	var additive := false
	if sprite.timeline.has("additive"):
		additive = sprite.sample_float("additive", ms, 0.0) > 0.5
	var frame := 0
	if sprite.frames > 1 and sprite.frame_delay > 0.0:
		var elapsed := maxf(0.0, ms - sprite.first_ms)
		frame = int(elapsed / sprite.frame_delay)
		if sprite.loop_type == 1:
			frame = mini(frame, sprite.frames - 1)
		else:
			frame = frame % sprite.frames
	return {
		"path": sprite.path,
		"layer": sprite.layer,
		"origin": sprite.origin,
		"pos": pos,
		"scale": scale,
		"rotation": rotation,
		"alpha": alpha,
		"colour": colour,
		"additive": additive,
		"frame": frame,
	}
