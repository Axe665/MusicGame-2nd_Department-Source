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


static func mark(phase: String) -> void:
	if not enabled() or _t0 == 0:
		return
	var now := Time.get_ticks_usec()
	var ms := float(now - _last) / 1000.0
	_last = now
	_marks.append("%s=%.1f" % [phase, ms])
	if ms > _worst_ms:
		_worst_ms = ms
		_worst_phase = phase


static func end(note: String = "") -> void:
	if not enabled() or _t0 == 0:
		return
	var total := float(Time.get_ticks_usec() - _t0) / 1000.0
	print("[load] %s total=%.1fms%s | %s" % [
		_label, total, "" if note.is_empty() else " (" + note + ")",
		" ".join(_marks) if not _marks.is_empty() else "—",
	])
	if _worst_ms > 0.0:
		print("[load] 最慢阶段 %s=%.1fms" % [_worst_phase, _worst_ms])
	_t0 = 0
