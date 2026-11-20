class_name MediaIO
extends RefCounted

## Native Godot formats are used directly. Everything else is converted into
## the user cache with ffmpeg when it is available; the chart keeps the original
## path, so replacing or re-linking the source still works.

const NATIVE_AUDIO := ["wav", "ogg", "mp3"]
const SUPPORTED_AUDIO := ["wav", "ogg", "mp3", "flac"]
const NATIVE_VIDEO := ["ogv"]
## 文件对话框和导入入口认这些；非 ogv 统一用 ffmpeg 转成 ogv 再预览。
const SUPPORTED_VIDEO := ["ogv", "mp4", "m4v", "webm", "mov", "mkv", "avi"]

## Executable used for every conversion. The editor keeps this in sync with its
## own setting so a bundled or non-PATH ffmpeg also works for audio analysis.
static var ffmpeg_exe: String = "ffmpeg"

## 随程序带的 ffmpeg（tools/ffmpeg/<平台>/ffmpeg.gz）。单个可执行文件超过
## GitHub 的单文件上限，所以仓库里存 gzip，第一次用到时解压到 user://。
const BUNDLE_DIR := "res://tools/ffmpeg"
const BUNDLE_VERSION := 1

static var _resolved_exe := ""
static var _resolved_checked := false
static var _ffmpeg_checked := false
static var _ffmpeg_available := false
static var last_error: String = ""
## 转码参数改了就要 +1，旧缓存自动作废（旧文件由「清理转码缓存」回收）。
const CACHE_VERSION := 2
## 正在转码的目标路径 → true；同一个文件不做第二份 ffmpeg。
static var _jobs: Dictionary = {}


static func set_ffmpeg_exe(path: String) -> void:
	var clean := path.strip_edges()
	ffmpeg_exe = clean if not clean.is_empty() else "ffmpeg"
	_resolved_checked = false
	_ffmpeg_checked = false
	_ffmpeg_available = false


## 真正执行用的路径：手动指定 > 内置包 > PATH。所有 ffmpeg 调用都要经过这里。
static func exe() -> String:
	if _resolved_checked:
		return _resolved_exe
	_resolved_checked = true
	_resolved_exe = _resolve_exe()
	return _resolved_exe


static func _resolve_exe() -> String:
	var clean := ffmpeg_exe.strip_edges()
	# 默认值 "ffmpeg" 表示“没手动指定”，这时优先用内置的那份。
	if not clean.is_empty() and clean != "ffmpeg":
		return clean
	var bundled := _bundled_exe()
	return bundled if not bundled.is_empty() else "ffmpeg"


static func _platform_dir() -> String:
	match OS.get_name():
		"Linux":
			return "linux64"
		"Windows":
			return "win64"
	return ""


## 内置 ffmpeg 的可执行路径；第一次调用会把 gz 解压到 user:// 并加执行位。
static func _bundled_exe() -> String:
	var platform := _platform_dir()
	if platform.is_empty():
		return ""
	var exe_name := "ffmpeg.exe" if platform == "win64" else "ffmpeg"
	var target := "user://tools/ffmpeg-%d-%s/%s" % [BUNDLE_VERSION, platform, exe_name]
	if FileAccess.file_exists(target):
		return ProjectSettings.globalize_path(target)
	var packed := "%s/%s/ffmpeg.gz" % [BUNDLE_DIR, platform]
	if not FileAccess.file_exists(packed):
		return ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target.get_base_dir()))
	# Godot 的 FileAccess.open_compressed 只认它自己写的头；系统 gzip 用 decompress_dynamic。
	var compressed := FileAccess.get_file_as_bytes(packed)
	if compressed.is_empty():
		last_error = "读不到内置 ffmpeg：%s" % packed
		return ""
	var bytes := compressed.decompress_dynamic(300 * 1024 * 1024, FileAccess.COMPRESSION_GZIP)
	if bytes.is_empty():
		last_error = "内置 ffmpeg 解不开：%s" % packed
		return ""
	var dst := FileAccess.open(target, FileAccess.WRITE)
	if dst == null:
		last_error = "无法写入内置 ffmpeg：%s" % target
		return ""
	dst.store_buffer(bytes)
	dst.close()
	var absolute := ProjectSettings.globalize_path(target)
	if platform != "win64":
		OS.execute("chmod", ["+x", absolute], [], true, false)
	return absolute


static func has_ffmpeg() -> bool:
	if _ffmpeg_checked:
		return _ffmpeg_available
	_ffmpeg_checked = true
	var output: Array = []
	var code := OS.execute(exe(), ["-version"], output, true, false)
	_ffmpeg_available = code == 0
	return _ffmpeg_available


static func is_native_audio(path: String) -> bool:
	return path.get_extension().to_lower() in NATIVE_AUDIO


static func is_supported_audio(path: String) -> bool:
	return path.get_extension().to_lower() in SUPPORTED_AUDIO


static func is_native_video(path: String) -> bool:
	return path.get_extension().to_lower() in NATIVE_VIDEO


static func is_supported_video(path: String) -> bool:
	return path.get_extension().to_lower() in SUPPORTED_VIDEO


## 音频转码缓存（非原生格式）；命中时 prepare_audio 不阻塞。
static func audio_cache_path(path: String) -> String:
	return _cache_path(path, "ogg")


## 变速不变调的音频缓存：atempo 预生成，键里带倍速和源文件 mtime + 大小。
static func rate_audio_cache_path(path: String, rate: float) -> String:
	var stamp := 0
	var size := 0
	if FileAccess.file_exists(path):
		stamp = FileAccess.get_modified_time(path)
		var file := FileAccess.open(path, FileAccess.READ)
		if file != null:
			size = file.get_length()
			file.close()
	var tag := "%.2f" % clampf(rate, 0.5, 2.0)
	var stem := path.get_file().get_basename().validate_filename()
	var digest := ("r%d|%s|%s|%d|%d" % [CACHE_VERSION, path, tag, stamp, size]).md5_text().substr(0, 10)
	return "user://media/%s_%s_rate%s.ogg" % [stem, digest, tag]


static func prepare_audio_at_rate(path: String, rate: float) -> String:
	last_error = ""
	if path.is_empty():
		return ""
	if absf(rate - 1.0) < 0.001:
		return prepare_audio(path)
	var target := rate_audio_cache_path(path, rate)
	if FileAccess.file_exists(target):
		return target
	if not has_ffmpeg():
		last_error = "变速不变调需要 ffmpeg；当前 PATH 中找不到 ffmpeg。"
		return ""
	DirAccess.make_dir_recursive_absolute("user://media")
	var output: Array = []
	var code := OS.execute(exe(), _rate_audio_args(_source_path(path), target, rate), output, true, false)
	if code != 0 or not FileAccess.file_exists(target):
		last_error = "变速音频生成失败：%s" % path.get_file()
		return ""
	return target


## 变速音频同理：子进程 + 进度文件；`progress` 的 ratio 固定 -1，只有已生成秒数。
static func prepare_audio_at_rate_async(path: String, rate: float, tree: SceneTree,
		progress: Callable = Callable()) -> String:
	if absf(rate - 1.0) < 0.001:
		return await prepare_audio_async(path, tree, progress)
	last_error = ""
	if path.is_empty():
		return ""
	var target := rate_audio_cache_path(path, rate)
	if FileAccess.file_exists(target):
		return target
	if tree == null:
		return prepare_audio_at_rate(path, rate)
	if not has_ffmpeg():
		last_error = "变速不变调需要 ffmpeg；当前 PATH 中找不到 ffmpeg。"
		return ""
	if _jobs.has(target):
		# 原任务已经退出却什么都没产出（调用方中途被释放等），不要一直等下去。
		while _jobs.has(target) and not FileAccess.file_exists(target) and _job_running(target):
			await tree.create_timer(0.2).timeout
		if FileAccess.file_exists(target):
			return target
		_jobs.erase(target)
	DirAccess.make_dir_recursive_absolute("user://media")
	_jobs[target] = 0
	var progress_path := target + ".progress"
	var progress_abs := ProjectSettings.globalize_path(progress_path)
	if FileAccess.file_exists(progress_path):
		DirAccess.remove_absolute(progress_abs)
	var pid := OS.create_process(exe(), _rate_audio_args(_source_path(path), target, rate, progress_abs), false)
	if pid <= 0:
		_jobs.erase(target)
		last_error = "无法启动 ffmpeg。"
		return ""
	_jobs[target] = pid
	while OS.is_process_running(pid):
		if progress.is_valid():
			progress.call(-1.0, read_progress_seconds(progress_path))
		await tree.create_timer(0.2).timeout
	_jobs.erase(target)
	if FileAccess.file_exists(progress_path):
		DirAccess.remove_absolute(progress_abs)
	if not FileAccess.file_exists(target):
		last_error = "变速音频生成失败：%s" % path.get_file()
		return ""
	if progress.is_valid():
		progress.call(1.0, 0.0)
	return target


## 转码缓存的 .ogv 路径；键里带源文件 mtime + 大小，替换同路径视频会自动重转。
static func video_cache_path(path: String) -> String:
	var stamp := 0
	var size := 0
	if FileAccess.file_exists(path):
		stamp = FileAccess.get_modified_time(path)
		var file := FileAccess.open(path, FileAccess.READ)
		if file != null:
			size = file.get_length()
			file.close()
	var stem := path.get_file().get_basename().validate_filename()
	var digest := ("v%d|%s|%d|%d" % [CACHE_VERSION, path, stamp, size]).md5_text().substr(0, 10)
	return "user://media/%s_%s.ogv" % [stem, digest]


static func prepare_audio(path: String) -> String:
	last_error = ""
	if path.is_empty():
		return ""
	if is_native_audio(path):
		return path
	var source := _source_path(path)
	var target := _cache_path(path, "ogg")
	if FileAccess.file_exists(target):
		return target
	if not has_ffmpeg():
		last_error = "该音频格式需要 ffmpeg；当前 PATH 中找不到 ffmpeg。"
		return ""
	DirAccess.make_dir_recursive_absolute("user://media")
	var output: Array = []
	var code := OS.execute(exe(), _audio_args(source, target), output, true, false)
	if code != 0 or not FileAccess.file_exists(target):
		last_error = "音频转换失败：%s" % path.get_file()
		return ""
	return target


static func prepare_video(path: String) -> String:
	last_error = ""
	if path.is_empty():
		return ""
	if is_native_video(path):
		return path
	var source := _source_path(path)
	var target := video_cache_path(path)
	if FileAccess.file_exists(target):
		return target
	if not has_ffmpeg():
		last_error = "该视频格式需要 ffmpeg；当前 PATH 中找不到 ffmpeg。"
		return ""
	DirAccess.make_dir_recursive_absolute("user://media")
	var output: Array = []
	var code := OS.execute(exe(), _video_args(source, target), output, true, false)
	if code != 0 or not FileAccess.file_exists(target):
		last_error = "视频转换失败：%s" % path.get_file()
		return ""
	return target


## 导入时用的异步转码：ffmpeg 写到 .progress 文件，调用方按帧轮询，
## 编辑器不会因为一个 20MB 的 mp4 冻结。
static func prepare_video_async(path: String, tree: SceneTree, progress: Callable = Callable()) -> String:
	last_error = ""
	if path.is_empty():
		return ""
	if is_native_video(path):
		return path
	var target := video_cache_path(path)
	if FileAccess.file_exists(target):
		return target
	if tree == null:
		return prepare_video(path)
	if not has_ffmpeg():
		last_error = "该视频格式需要 ffmpeg；当前 PATH 中找不到 ffmpeg。"
		return ""
	if _jobs.has(target):
		# 编辑器预览和试玩可能同时打开同一段 BGA：等第一份转完，别起第二个 ffmpeg。
		# 原任务已经退出却没产出时重跑，而不是永远卡在「加载中」。
		while _jobs.has(target) and not FileAccess.file_exists(target) and _job_running(target):
			await tree.create_timer(0.2).timeout
		if FileAccess.file_exists(target):
			return target
		_jobs.erase(target)
	DirAccess.make_dir_recursive_absolute("user://media")
	_jobs[target] = 0
	var progress_path := _cache_path(path, "progress")
	var progress_abs := ProjectSettings.globalize_path(progress_path)
	if FileAccess.file_exists(progress_path):
		DirAccess.remove_absolute(progress_abs)
	var pid := OS.create_process(exe(), _video_args(_source_path(path), target, progress_abs), false)
	if pid <= 0:
		_jobs.erase(target)
		last_error = "无法启动 ffmpeg。"
		return ""
	_jobs[target] = pid
	var duration := probe_video_duration(path)
	while OS.is_process_running(pid):
		if progress.is_valid():
			var seconds := read_progress_seconds(progress_path)
			var ratio := -1.0 if duration <= 0.0 else clampf(seconds / duration, 0.0, 1.0)
			progress.call(ratio, seconds)
		await tree.create_timer(0.2).timeout
	_jobs.erase(target)
	if FileAccess.file_exists(progress_path):
		DirAccess.remove_absolute(progress_abs)
	if not FileAccess.file_exists(target):
		last_error = "视频转换失败：%s" % path.get_file()
		return ""
	if progress.is_valid():
		progress.call(1.0, duration)
	return target


## 音频同理：FLAC / 导入包里的 mp3 转 OGG 走同一个「子进程 + 进度文件」流程。
static func prepare_audio_async(path: String, tree: SceneTree, progress: Callable = Callable()) -> String:
	last_error = ""
	if path.is_empty():
		return ""
	if is_native_audio(path):
		return path
	var target := _cache_path(path, "ogg")
	if FileAccess.file_exists(target):
		return target
	if tree == null:
		return prepare_audio(path)
	if not has_ffmpeg():
		last_error = "该音频格式需要 ffmpeg；当前 PATH 中找不到 ffmpeg。"
		return ""
	if _jobs.has(target):
		while _jobs.has(target) and not FileAccess.file_exists(target) and _job_running(target):
			await tree.create_timer(0.2).timeout
		if FileAccess.file_exists(target):
			return target
		_jobs.erase(target)
	DirAccess.make_dir_recursive_absolute("user://media")
	_jobs[target] = 0
	var progress_path := _cache_path(path, "progress")
	var progress_abs := ProjectSettings.globalize_path(progress_path)
	if FileAccess.file_exists(progress_path):
		DirAccess.remove_absolute(progress_abs)
	var pid := OS.create_process(exe(), _audio_args(_source_path(path), target, progress_abs), false)
	if pid <= 0:
		_jobs.erase(target)
		last_error = "无法启动 ffmpeg。"
		return ""
	_jobs[target] = pid
	# 不做 ffprobe：OS.execute 会卡主线程 ~80ms；音频这里只报已转秒数。
	while OS.is_process_running(pid):
		if progress.is_valid():
			progress.call(-1.0, read_progress_seconds(progress_path))
		await tree.create_timer(0.2).timeout
	_jobs.erase(target)
	if FileAccess.file_exists(progress_path):
		DirAccess.remove_absolute(progress_abs)
	if not FileAccess.file_exists(target):
		last_error = "音频转换失败：%s" % path.get_file()
		return ""
	if progress.is_valid():
		progress.call(1.0, 0.0)
	return target


## 画面只做环后背景层，压到 540p / 30fps 省一半以上转码时间和解码开销。
static func _video_args(source: String, target: String, progress_path: String = "") -> Array:
	var args := [
		"-y", "-i", source,
		"-vf", "scale=960:-2,fps=30",
		"-c:v", "libtheora", "-q:v", "6", "-an", "-pix_fmt", "yuv420p",
	]
	if not progress_path.is_empty():
		args.append_array(["-loglevel", "error", "-progress", progress_path])
	args.append(ProjectSettings.globalize_path(target))
	return args


static func _audio_args(source: String, target: String, progress_path: String = "") -> Array:
	var args := ["-y", "-i", source, "-vn", "-acodec", "libvorbis", "-q:a", "5"]
	if not progress_path.is_empty():
		args.append_array(["-loglevel", "error", "-progress", progress_path])
	args.append(ProjectSettings.globalize_path(target))
	return args


## atempo 0.5–2.0 正好覆盖倍速范围；只留第一条音轨，封面/视频流全部丢掉。
static func _rate_audio_args(source: String, target: String, rate: float,
		progress_path: String = "") -> Array:
	var args := [
		"-y", "-i", source, "-map", "0:a:0", "-vn",
		"-filter:a", "atempo=%.5f" % clampf(rate, 0.5, 2.0),
		"-acodec", "libvorbis", "-q:a", "5",
	]
	if not progress_path.is_empty():
		args.append_array(["-loglevel", "error", "-progress", progress_path])
	args.append(ProjectSettings.globalize_path(target))
	return args


## 转码缓存占用（字节）；设置里显示和清理共用。
static func cache_size() -> int:
	var total := 0
	var dir := DirAccess.open("user://media")
	if dir == null:
		return 0
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if not dir.current_is_dir():
			var file := FileAccess.open("user://media/" + name, FileAccess.READ)
			if file != null:
				total += file.get_length()
				file.close()
		name = dir.get_next()
	dir.list_dir_end()
	return total


## 清空转码缓存；下次打开会重新转（源文件不动）。
static func clear_cache() -> int:
	var freed := cache_size()
	var dir := DirAccess.open("user://media")
	if dir == null:
		return 0
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if not dir.current_is_dir():
			DirAccess.remove_absolute(ProjectSettings.globalize_path("user://media/" + name))
		name = dir.get_next()
	dir.list_dir_end()
	return freed


## 读 ffmpeg -progress 文件里的已转秒数；out_time_us / out_time_ms 都是微秒。
static func progress_seconds(text: String) -> float:
	var us := -1.0
	var ms := -1.0
	for line in text.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("out_time_us="):
			var value := trimmed.substr(12).strip_edges()
			if value.is_valid_int():
				us = float(int(value))
		elif trimmed.begins_with("out_time_ms="):
			var value := trimmed.substr(12).strip_edges()
			if value.is_valid_int():
				ms = float(int(value))
		elif trimmed.begins_with("out_time="):
			var parts := trimmed.substr(9).strip_edges().split(":")
			if parts.size() == 3:
				var seconds := float(parts[0]) * 3600.0 + float(parts[1]) * 60.0 + float(parts[2])
				if seconds > 0.0:
					us = seconds * 1_000_000.0
	if us >= 0.0:
		return us / 1_000_000.0
	if ms >= 0.0:
		return ms / 1_000_000.0
	return 0.0


static func read_progress_seconds(path: String) -> float:
	if not FileAccess.file_exists(path):
		return 0.0
	return progress_seconds(FileAccess.get_file_as_string(path))


static func probe_video_duration(path: String) -> float:
	var probe := _ffprobe_exe()
	if not probe.is_empty():
		var output: Array = []
		var code := OS.execute(probe, [
			"-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1",
			_source_path(path),
		], output, true, false)
		if code == 0 and not output.is_empty():
			for line in "\n".join(output).split("\n"):
				var value := line.strip_edges()
				if value.is_valid_float():
					return float(value)
	# 只有内置 ffmpeg（没带 ffprobe）时，从 `ffmpeg -i` 的 stderr 里读时长。
	var info: Array = []
	OS.execute(exe(), ["-hide_banner", "-i", _source_path(path)], info, true, false)
	for line in "\n".join(info).split("\n"):
		var at := line.find("Duration:")
		if at < 0:
			continue
		var stamp := line.substr(at + 9).strip_edges().split(",")[0].strip_edges()
		var parts := stamp.split(":")
		if parts.size() == 3:
			return float(parts[0]) * 3600.0 + float(parts[1]) * 60.0 + float(parts[2])
	return 0.0


static func _ffprobe_exe() -> String:
	var base := exe().get_base_dir()
	if not base.is_empty():
		var candidate := base.path_join("ffprobe.exe" if OS.get_name() == "Windows" else "ffprobe")
		if FileAccess.file_exists(candidate):
			return candidate
	# PATH 里恰好有 ffprobe 就用它，没有就返回空（调用方退回 ffmpeg）。
	var output: Array = []
	if OS.execute("ffprobe", ["-version"], output, true, false) == 0:
		return "ffprobe"
	return ""


static func _source_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path


## 同一目标上的转码任务是否还活着；0 = 刚占位、pid 还没写回。
static func _job_running(target: String) -> bool:
	var pid := int(_jobs.get(target, 0))
	return pid <= 0 or OS.is_process_running(pid)


static func _cache_path(path: String, extension: String) -> String:
	var stem := path.get_file().get_basename().validate_filename()
	var digest := path.md5_text().substr(0, 10)
	return "user://media/%s_%s.%s" % [stem, digest, extension]
