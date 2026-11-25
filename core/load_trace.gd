extends RefCounted

## 载入阶段埋点（对齐 Estella 的 LoadTrace）：只在 --trace-load 时输出。
## 用法：begin(名字) → 若干 mark(阶段) → end()，打印各阶段耗时与最慢的一段。

static var _enabled: bool = false
static var _checked: bool = false
static var _label: String = ""
static var _t0: int = 0
static var _last: int = 0
static var _marks: Array[String] = []
static var _worst_ms: float = 0.0
static var _worst_phase: String = ""
static var _last_phase: String = ""
## 同一标签被反复载入时用它区分（对齐 Estella 的 run#）。
static var _run_counts: Dictionary = {}
static var _run_number: int = 0
## >33ms 的帧数：光看总耗时看不出「载入卡了一下」。
static var _slow_frames: int = 0
static var _worst_frame_ms: float = 0.0
static var _worst_frame_phase: String = ""
## -1 未探测，0 冷，1 热。
static var _cache_warm: int = -1


static func enabled() -> bool:
	if not _checked:
		_checked = true
		_enabled = OS.get_cmdline_user_args().has("--trace-load")
	return _enabled


static func begin(label: String) -> void:
	if not enabled():
		return
	_label = label
	_t0 = Time.get_ticks_usec()
	_last = _t0
	_marks.clear()
	_worst_ms = 0.0
	_worst_phase = ""
	_last_phase = ""
	_slow_frames = 0
	_worst_frame_ms = 0.0
	_worst_frame_phase = ""
	_run_number = int(_run_counts.get(label, 0)) + 1
	_run_counts[label] = _run_number


static func mark(phase: String) -> void:
	if not enabled() or _t0 == 0:
		return
	var now := Time.get_ticks_usec()
	var ms := float(now - _last) / 1000.0
	_last = now
	_marks.append("%s=%.1f" % [phase, ms])
	_last_phase = phase
	if ms > _worst_ms:
		_worst_ms = ms
		_worst_phase = phase


## 载入期间每帧喂一次：统计 >33ms 的卡顿帧和最慢帧落在哪个阶段。
static func frame_tick(delta: float) -> void:
	if not enabled() or _t0 == 0:
		return
	var ms := delta * 1000.0
	if ms > 33.0:
		_slow_frames += 1
	if ms > _worst_frame_ms:
		_worst_frame_ms = ms
		_worst_frame_phase = _last_phase


## 着色器缓存是不是热的：同一个谱首次载入和第二次载入差很多，没有这个字段会误判成回归。
static func _cache_is_warm() -> bool:
	if _cache_warm < 0:
		_cache_warm = 1 if (_dir_has_files("res://.godot/shader_cache") or _dir_has_files("user://shader_cache")) else 0
	return _cache_warm == 1


static func _dir_has_files(path: String, depth: int = 3) -> bool:
	if not DirAccess.dir_exists_absolute(path):
		return false
	if not DirAccess.get_files_at(path).is_empty():
		return true
	# shader_cache/<分组>/<驱动>/<缓存文件>，要往下走两层才看得到文件。
	if depth <= 0:
		return false
	for sub in DirAccess.get_directories_at(path):
		if _dir_has_files(path.path_join(sub), depth - 1):
			return true
	return false


static func end(note: String = "") -> void:
	if not enabled() or _t0 == 0:
		return
	var total := float(Time.get_ticks_usec() - _t0) / 1000.0
	print("[load] %s total=%.1fms%s run#%d cache=%s slow=%d | %s" % [
		_label, total, "" if note.is_empty() else " (" + note + ")",
		_run_number, "warm" if _cache_is_warm() else "cold",
		_slow_frames,
		" ".join(_marks) if not _marks.is_empty() else "—",
	])
	if _worst_ms > 0.0:
		print("[load] 最慢阶段 %s=%.1fms" % [_worst_phase, _worst_ms])
	if _worst_frame_ms > 0.0:
		print("[load] 最慢帧 %.1fms 阶段=%s" % [_worst_frame_ms, _worst_frame_phase if not _worst_frame_phase.is_empty() else "载入前"])
	_t0 = 0
