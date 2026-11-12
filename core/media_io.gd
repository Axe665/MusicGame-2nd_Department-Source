class_name MediaIO
extends RefCounted

## Native Godot formats are used directly. Everything else is converted into
## the user cache with ffmpeg when it is available; the chart keeps the original
## path, so replacing or re-linking the source still works.

const NATIVE_AUDIO := ["wav", "ogg", "mp3"]
const SUPPORTED_AUDIO := ["wav", "ogg", "mp3", "flac"]
const NATIVE_VIDEO := ["ogv"]
## 文件对话框和导入入口认这些；非 ogv 统一用 ffmpeg 转成 ogv 再预览。
const SUPPORTED_VIDEO := ["ogv", "mp4", "webm", "mov", "mkv", "avi"]

## Executable used for every conversion. The editor keeps this in sync with its
## own setting so a bundled or non-PATH ffmpeg also works for audio analysis.
static var ffmpeg_exe: String = "ffmpeg"

static var _ffmpeg_checked := false
static var _ffmpeg_available := false
static var last_error: String = ""


static func set_ffmpeg_exe(path: String) -> void:
	var clean := path.strip_edges()
	ffmpeg_exe = clean if not clean.is_empty() else "ffmpeg"
	_ffmpeg_checked = false
	_ffmpeg_available = false


static func has_ffmpeg() -> bool:
	if _ffmpeg_checked:
		return _ffmpeg_available
	_ffmpeg_checked = true
	var output: Array = []
	var code := OS.execute(ffmpeg_exe, ["-version"], output, true, false)
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
	var digest := ("%s|%d|%d" % [path, stamp, size]).md5_text().substr(0, 10)
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
	var args := [
		"-y", "-i", source, "-vn", "-acodec", "libvorbis", "-q:a", "5",
		ProjectSettings.globalize_path(target),
	]
	var output: Array = []
	var code := OS.execute(ffmpeg_exe, args, output, true, false)
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
	var code := OS.execute(ffmpeg_exe, _video_args(source, target), output, true, false)
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
	DirAccess.make_dir_recursive_absolute("user://media")
	var progress_path := _cache_path(path, "progress")
	var progress_abs := ProjectSettings.globalize_path(progress_path)
	if FileAccess.file_exists(progress_path):
		DirAccess.remove_absolute(progress_abs)
	var pid := OS.create_process(ffmpeg_exe, _video_args(_source_path(path), target, progress_abs), false)
	if pid <= 0:
		last_error = "无法启动 ffmpeg。"
		return ""
	var duration := probe_video_duration(path)
	while OS.is_process_running(pid):
		if progress.is_valid():
			var seconds := read_progress_seconds(progress_path)
			var ratio := -1.0 if duration <= 0.0 else clampf(seconds / duration, 0.0, 1.0)
			progress.call(ratio, seconds)
		await tree.create_timer(0.2).timeout
	if FileAccess.file_exists(progress_path):
		DirAccess.remove_absolute(progress_abs)
	if not FileAccess.file_exists(target):
		last_error = "视频转换失败：%s" % path.get_file()
		return ""
	if progress.is_valid():
		progress.call(1.0, duration)
	return target


static func _video_args(source: String, target: String, progress_path: String = "") -> Array:
	var args := [
		"-y", "-i", source,
		"-c:v", "libtheora", "-q:v", "7", "-an", "-pix_fmt", "yuv420p",
	]
	if not progress_path.is_empty():
		args.append_array(["-loglevel", "error", "-progress", progress_path])
	args.append(ProjectSettings.globalize_path(target))
	return args


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
	var output: Array = []
	var code := OS.execute(_ffprobe_exe(), [
		"-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1",
		_source_path(path),
	], output, true, false)
	if code != 0 or output.is_empty():
		return 0.0
	for line in "\n".join(output).split("\n"):
		var value := line.strip_edges()
		if value.is_valid_float():
			return float(value)
	return 0.0


static func _ffprobe_exe() -> String:
	var base := ffmpeg_exe.get_base_dir()
	if not base.is_empty():
		var candidate := base.path_join("ffprobe")
		if FileAccess.file_exists(candidate):
			return candidate
	return "ffprobe"


static func _source_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path


static func _cache_path(path: String, extension: String) -> String:
	var stem := path.get_file().get_basename().validate_filename()
	var digest := path.md5_text().substr(0, 10)
	return "user://media/%s_%s.%s" % [stem, digest, extension]
